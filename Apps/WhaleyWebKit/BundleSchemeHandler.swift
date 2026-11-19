import Foundation
import WebKit

/// Serves the staged Scala.js assets at one stable same-origin URL.
/// ES modules and fetch/Web Audio need a normal origin and MIME types;
/// file:// pages cannot reliably provide that in WKWebView.
@MainActor
final class PackagedGameSchemeHandler: NSObject, WKURLSchemeHandler {
    private let root: URL

    init(root: URL) {
        self.root = root.resolvingSymlinksInPath().standardizedFileURL
        super.init()
    }

    func webView(_ webView: WKWebView, start task: any WKURLSchemeTask) {
        guard let url = task.request.url, url.scheme == "whaleyplaytest",
              url.host == "app" else {
            task.didFailWithError(URLError(.badURL))
            return
        }

        // The host can only serve its own built resources, never arbitrary
        // local files, dotfiles, another domain, or a remote URL.
        let path = url.path == "/" ? "index.html" : String(url.path.dropFirst())
        let components = path.split(separator: "/", omittingEmptySubsequences: false)
        guard path == "index.html" ||
              (path.hasPrefix("assets/") &&
               components.allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." &&
                                       !$0.hasPrefix(".") })) else {
            respond(task, url: url, code: 404, body: Data("Not found".utf8))
            return
        }
        let file = root.appendingPathComponent(path).resolvingSymlinksInPath().standardizedFileURL
        guard file.path.hasPrefix(root.path + "/"),
              FileManager.default.fileExists(atPath: file.path) else {
            respond(task, url: url, code: 404, body: Data("Not found".utf8))
            return
        }

        do {
            let attributes = try FileManager.default.attributesOfItem(atPath: file.path)
            guard let length = (attributes[.size] as? NSNumber)?.uint64Value else {
                throw URLError(.cannotDecodeContentData)
            }
            let rangeHeader = task.request.value(forHTTPHeaderField: "Range")
            guard let byteRange = Self.parseRange(rangeHeader, length: length) else {
                respond(task, url: url, code: 416, body: Data(),
                        headers: ["Content-Range": "bytes */\(length)"])
                return
            }
            let count = byteRange.end >= byteRange.start
                ? Int(byteRange.end - byteRange.start + 1) : 0
            let handle = try FileHandle(forReadingFrom: file)
            defer { try? handle.close() }
            try handle.seek(toOffset: byteRange.start)
            let body = try handle.read(upToCount: count) ?? Data()
            guard body.count == count else { throw URLError(.cannotDecodeContentData) }

            var headers: [String: String] = [:]
            if byteRange.partial {
                headers["Content-Range"] = "bytes \(byteRange.start)-\(byteRange.end)/\(length)"
            }
            respond(task, url: url, code: byteRange.partial ? 206 : 200,
                    body: body, contentType: Self.mimeType(for: file.pathExtension),
                    headers: headers)
        } catch {
            print("[Whaley WebKit] Asset \(path): \(error)")
            task.didFailWithError(error)
        }
    }

    func webView(_ webView: WKWebView, stop task: any WKURLSchemeTask) {
        // Responses are delivered synchronously; no outstanding operation.
    }

    private func respond(_ task: any WKURLSchemeTask, url: URL, code: Int,
                         body: Data, contentType: String = "text/plain",
                         headers extra: [String: String] = [:]) {
        var headers = [
            "Content-Type": contentType,
            "Content-Length": String(body.count),
            "Accept-Ranges": "bytes",
            "Access-Control-Allow-Origin": "*",
            "Cache-Control": "no-store"
        ]
        headers.merge(extra) { _, newer in newer }
        guard let response = HTTPURLResponse(url: url, statusCode: code,
                                             httpVersion: "HTTP/1.1",
                                             headerFields: headers) else {
            task.didFailWithError(URLError(.badServerResponse))
            return
        }
        task.didReceive(response)
        task.didReceive(body)
        task.didFinish()
    }

    private static func parseRange(_ header: String?, length: UInt64)
        -> (start: UInt64, end: UInt64, partial: Bool)? {
        guard let header else {
            return (0, length == 0 ? 0 : length - 1, false)
        }
        guard length > 0, header.hasPrefix("bytes=") else { return nil }
        let spec = String(header.dropFirst("bytes=".count))
        let pair = spec.split(separator: "-", omittingEmptySubsequences: false)
        guard pair.count == 2 else { return nil }
        if pair[0].isEmpty {
            guard let suffix = UInt64(pair[1]), suffix > 0 else { return nil }
            return (length - min(suffix, length), length - 1, true)
        }
        guard let first = UInt64(pair[0]), first < length else { return nil }
        if pair[1].isEmpty { return (first, length - 1, true) }
        guard let last = UInt64(pair[1]), last >= first else { return nil }
        return (first, min(last, length - 1), true)
    }

    private static func mimeType(for ext: String) -> String {
        switch ext.lowercased() {
        case "html": return "text/html; charset=utf-8"
        case "js", "mjs": return "text/javascript; charset=utf-8"
        case "css": return "text/css; charset=utf-8"
        case "json", "map": return "application/json"
        case "png": return "image/png"
        case "jpg", "jpeg": return "image/jpeg"
        case "wav": return "audio/wav"
        case "mp3": return "audio/mpeg"
        default: return "application/octet-stream"
        }
    }
}
