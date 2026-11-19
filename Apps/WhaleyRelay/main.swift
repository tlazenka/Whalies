import Dispatch
import Foundation
import WhaleyCore

#if os(Linux)
import Glibc
#else
import Darwin
#endif

#if os(Linux)
private let streamSocketType = Int32(SOCK_STREAM.rawValue)
#else
private let streamSocketType: Int32 = SOCK_STREAM
#endif

private let maximumHeaderBytes = 16 * 1024
private let maximumBodyBytes = 1024 * 1024
private let socketDeadlineNanoseconds: UInt64 = 5_000_000_000
private let headerTerminator = Data([13, 10, 13, 10])

private func out(_ message: String) {
    try? FileHandle.standardOutput.write(contentsOf: Data((message + "\n").utf8))
}

private func fail(_ message: String, status: Int32 = 1) -> Never {
    try? FileHandle.standardError.write(contentsOf: Data(("whaley-relay: " + message + "\n").utf8))
    exit(status)
}

private func json(_ object: Any) -> Data {
    (try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]))
        ?? Data("{\"error\":\"response encoding failed\"}".utf8)
}

private func monotonicNow() -> UInt64 { DispatchTime.now().uptimeNanoseconds }
private func socketDeadline() -> UInt64 { monotonicNow() + socketDeadlineNanoseconds }
private func elapsedSeconds(since start: UInt64) -> Double {
    let now = monotonicNow()
    return Double(now >= start ? now - start : 0) / 1_000_000_000
}

private enum ConnectionFailure: Error, CustomStringConvertible {
    case timeout
    case closed
    case system(Int32)

    var description: String {
        switch self {
        case .timeout: return "socket deadline exceeded"
        case .closed: return "connection closed"
        case .system(let code): return "socket error \(code): \(String(cString: strerror(code)))"
        }
    }
}

private struct HTTPFailure: Error {
    let status: Int
    let message: String
}

private struct HTTPRequest {
    let method: String
    let path: String
    let headers: [String: String]
    let body: Data
}

private struct HTTPResponse {
    let status: Int
    let body: Data
    var headers: [String: String] = [:]
}

private struct StoredState {
    // Keep the accepted bytes, including fields unknown to this relay version.
    let body: Data
    let receivedAt: UInt64

    func freshnessHeaders(maxAge: Double) -> [String: String] {
        let age = elapsedSeconds(since: receivedAt)
        return [
            "X-Whaley-State-Age": String(age),
            "X-Whaley-State-Status": age <= maxAge ? "live" : "stale",
            "X-Whaley-State-Max-Age": String(maxAge),
        ]
    }
}

private func waitForSocket(_ fd: Int32, events: Int16, deadline: UInt64) throws {
    while true {
        let now = monotonicNow()
        guard now < deadline else { throw ConnectionFailure.timeout }
        // Round up so sub-millisecond waits do not become busy polling.
        let milliseconds = Int32(min((deadline - now + 999_999) / 1_000_000, UInt64(Int32.max)))
        var descriptor = pollfd(fd: fd, events: events, revents: 0)
        let result = poll(&descriptor, 1, milliseconds)
        if result < 0 {
            let code = errno
            if code == EINTR { continue }
            throw ConnectionFailure.system(code)
        }
        if result == 0 { continue }
        if (descriptor.revents & Int16(POLLNVAL)) != 0 {
            throw ConnectionFailure.system(EBADF)
        }
        if (descriptor.revents & events) != 0 { return }
        // Let recv/send distinguish readable EOF from a socket failure.
        if (descriptor.revents & Int16(POLLHUP | POLLERR)) != 0 { return }
    }
}

private func receive(_ fd: Int32, maximum: Int, deadline: UInt64) throws -> Data {
    var bytes = [UInt8](repeating: 0, count: maximum)
    while true {
        try waitForSocket(fd, events: Int16(POLLIN), deadline: deadline)
        let count = recv(fd, &bytes, bytes.count, 0)
        if count > 0 { return Data(bytes.prefix(count)) }
        if count == 0 { throw HTTPFailure(status: 400, message: "incomplete HTTP request") }
        let code = errno
        if code == EINTR || code == EAGAIN || code == EWOULDBLOCK { continue }
        throw ConnectionFailure.system(code)
    }
}

private func isTokenByte(_ byte: UInt8) -> Bool {
    switch byte {
    case 48...57, 65...90, 97...122, 33, 35, 36, 37, 38, 39, 42, 43, 45, 46, 94, 95, 96, 124, 126:
        return true
    default:
        return false
    }
}

private func readRequest(_ fd: Int32, deadline: UInt64) throws -> HTTPRequest {
    var bytes = Data()
    var delimiter: Range<Data.Index>?
    while delimiter == nil {
        guard bytes.count < maximumHeaderBytes else {
            throw HTTPFailure(status: 431, message: "request headers exceed 16 KiB")
        }
        // Even a single recv cannot take an unfinished header past the limit.
        bytes.append(try receive(fd, maximum: min(8192, maximumHeaderBytes - bytes.count), deadline: deadline))
        delimiter = bytes.range(of: headerTerminator)
    }
    guard let delimiter, delimiter.upperBound <= maximumHeaderBytes else {
        throw HTTPFailure(status: 431, message: "request headers exceed 16 KiB")
    }
    let headerBytes = bytes[..<delimiter.lowerBound]
    guard headerBytes.allSatisfy({ $0 == 9 || $0 == 10 || $0 == 13 || ($0 >= 32 && $0 <= 126) }),
          let header = String(data: headerBytes, encoding: .ascii) else {
        throw HTTPFailure(status: 400, message: "invalid HTTP header bytes")
    }
    let lines = header.components(separatedBy: "\r\n")
    guard lines.allSatisfy({ !$0.contains("\r") && !$0.contains("\n") }),
          let requestLine = lines.first else {
        throw HTTPFailure(status: 400, message: "invalid HTTP line endings")
    }
    let requestParts = requestLine.split(separator: " ", omittingEmptySubsequences: false)
    guard requestParts.count == 3,
          !requestParts[0].isEmpty, requestParts[0].utf8.allSatisfy(isTokenByte),
          requestParts[1].hasPrefix("/"), !requestParts[1].contains("#"),
          requestParts[1].utf8.allSatisfy({ $0 >= 33 && $0 <= 126 }) else {
        throw HTTPFailure(status: 400, message: "invalid HTTP request line")
    }
    let method = String(requestParts[0])
    let path = String(requestParts[1])
    let version = String(requestParts[2])
    guard version == "HTTP/1.1" || version == "HTTP/1.0" else {
        throw HTTPFailure(status: 505, message: "unsupported HTTP version")
    }
    var headers: [String: String] = [:]
    for line in lines.dropFirst() {
        guard let colon = line.firstIndex(of: ":"), colon != line.startIndex else {
            throw HTTPFailure(status: 400, message: "invalid HTTP header")
        }
        let nameBytes = line[..<colon].utf8
        guard nameBytes.allSatisfy(isTokenByte) else {
            throw HTTPFailure(status: 400, message: "invalid HTTP header name")
        }
        let name = line[..<colon].lowercased()
        let value = String(line[line.index(after: colon)...]).trimmingCharacters(in: CharacterSet(charactersIn: " \t"))
        if let previous = headers[name] {
            if name == "content-length" || name == "host" {
                throw HTTPFailure(status: 400, message: "duplicate \(name) header")
            }
            headers[name] = previous + ", " + value
        } else {
            headers[name] = value
        }
    }
    if version == "HTTP/1.1" && (headers["host"]?.isEmpty ?? true) {
        throw HTTPFailure(status: 400, message: "HTTP/1.1 requires one Host header")
    }
    guard headers["transfer-encoding"] == nil else {
        throw HTTPFailure(status: 400, message: "Transfer-Encoding is unsupported; use Content-Length")
    }
    // Reject before reading a body: a client waiting for 100 Continue must not stall us.
    guard headers["expect"] == nil else {
        throw HTTPFailure(status: 417, message: "Expect is unsupported; send the body with Content-Length")
    }
    let length: Int
    if let raw = headers["content-length"] {
        guard !raw.isEmpty, raw.utf8.allSatisfy({ $0 >= 48 && $0 <= 57 }), let parsed = Int(raw) else {
            throw HTTPFailure(status: 400, message: "invalid Content-Length")
        }
        guard parsed <= maximumBodyBytes else {
            throw HTTPFailure(status: 413, message: "request body exceeds 1 MiB")
        }
        length = parsed
    } else {
        if method == "POST" && path == "/state" {
            throw HTTPFailure(status: 411, message: "POST /state requires Content-Length")
        }
        length = 0
    }
    var body = Data(bytes[delimiter.upperBound...])
    guard body.count <= length else {
        throw HTTPFailure(status: 400, message: "received bytes beyond Content-Length")
    }
    while body.count < length {
        body.append(try receive(fd, maximum: min(8192, length - body.count), deadline: deadline))
    }
    return HTTPRequest(method: method, path: path, headers: headers, body: body)
}

private func sendAll(_ fd: Int32, data: Data, deadline: UInt64) throws {
    var offset = 0
    while offset < data.count {
        try waitForSocket(fd, events: Int16(POLLOUT), deadline: deadline)
        let written = data.withUnsafeBytes { raw in
            send(fd, raw.baseAddress!.advanced(by: offset), raw.count - offset, 0)
        }
        if written > 0 { offset += written; continue }
        if written == 0 { throw ConnectionFailure.closed }
        let code = errno
        if code == EINTR || code == EAGAIN || code == EWOULDBLOCK { continue }
        throw ConnectionFailure.system(code)
    }
}

private func sendResponse(_ fd: Int32, response: HTTPResponse) throws {
    let reasons = [200: "OK", 400: "Bad Request", 404: "Not Found", 408: "Request Timeout",
                   409: "Conflict", 411: "Length Required", 413: "Content Too Large",
                   417: "Expectation Failed", 431: "Request Header Fields Too Large",
                   500: "Internal Server Error", 505: "HTTP Version Not Supported"]
    var header = "HTTP/1.1 \(response.status) \(reasons[response.status] ?? "Error")\r\n"
    header += "Content-Type: application/json\r\nContent-Length: \(response.body.count)\r\n"
    header += "Cache-Control: no-store\r\nConnection: close\r\n"
    for key in response.headers.keys.sorted() {
        header += "\(key): \(response.headers[key]!)\r\n"
    }
    header += "\r\n"
    let deadline = socketDeadline()
    try sendAll(fd, data: Data(header.utf8), deadline: deadline)
    try sendAll(fd, data: response.body, deadline: deadline)
}

private let arguments = Array(CommandLine.arguments.dropFirst())
if arguments == ["--help"] || arguments == ["-h"] {
    out("""
        Usage: whaley-relay
        Receive native Whaley snapshots over HTTP for local, trusted development.

        GET /hello   Reachability acknowledgment
        POST /state  Accept a complete WhaleySceneSnapshot JSON body
        GET /state   Latest original snapshot; 409 until the first accepted post

        Environment:
          WHALEY_RELAY_PORT     TCP port, 1...65535 (default 8092)
          WHALEY_RELAY_MAX_AGE  Positive finite freshness limit in seconds (default 2)

        GET /state keeps the snapshot body unchanged and reports age, live/stale
        status and the limit in X-Whaley-State-* headers. Stale snapshots remain
        available for observation. The relay has no gameplay command channel.
        It listens on 0.0.0.0 without authentication or TLS and stores state only
        in memory. Headers are limited to 16 KiB; bodies to 1 MiB. Transfer-Encoding
        and Expect are unsupported. Receive and send each have a 5-second deadline.
        """)
    exit(0)
}
guard arguments.isEmpty else { fail("unknown argument; use --help", status: 2) }
private let environment = ProcessInfo.processInfo.environment
private let rawPort = environment["WHALEY_RELAY_PORT"] ?? "8092"
guard !rawPort.isEmpty, rawPort.utf8.allSatisfy({ $0 >= 48 && $0 <= 57 }),
      let port = UInt16(rawPort), port > 0 else {
    fail("WHALEY_RELAY_PORT must be an integer from 1 through 65535", status: 2)
}
private let rawMaxAge = environment["WHALEY_RELAY_MAX_AGE"] ?? "2"
guard let maxAge = Double(rawMaxAge), maxAge.isFinite, maxAge > 0 else {
    fail("WHALEY_RELAY_MAX_AGE must be a positive finite number of seconds", status: 2)
}

// A disconnected reader must not terminate the relay during a partial write.
signal(SIGPIPE, SIG_IGN)
signal(SIGINT) { _ in _exit(130) }
signal(SIGTERM) { _ in _exit(143) }

private let server = socket(AF_INET, streamSocketType, 0)
guard server >= 0 else { fail("socket failed: \(String(cString: strerror(errno)))") }
private var yes: Int32 = 1
private let reuseResult = withUnsafePointer(to: &yes) {
    setsockopt(server, SOL_SOCKET, SO_REUSEADDR, $0, socklen_t(MemoryLayout<Int32>.size))
}
guard reuseResult == 0 else { fail("setsockopt failed: \(String(cString: strerror(errno)))") }
private var address = sockaddr_in()
#if !os(Linux)
address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
#endif
address.sin_family = sa_family_t(AF_INET)
address.sin_port = port.bigEndian
address.sin_addr = in_addr(s_addr: INADDR_ANY)
private let bound = withUnsafePointer(to: &address) { pointer in
    pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
        bind(server, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
    }
}
guard bound == 0 else { fail("bind 0.0.0.0:\(port) failed: \(String(cString: strerror(errno)))") }
guard listen(server, 32) == 0 else { fail("listen failed: \(String(cString: strerror(errno)))") }
out("START 0.0.0.0:\(port), freshness \(maxAge)s, body limit \(maximumBodyBytes) bytes")

private var live: StoredState?
private var acceptedSnapshots = 0
while true {
    let fd = accept(server, nil, nil)
    if fd < 0 {
        let code = errno
        if code == EINTR { continue }
        out("ERROR accept: \(String(cString: strerror(code)))")
        continue
    }
    defer { close(fd) }
    let flags = fcntl(fd, F_GETFL, 0)
    guard flags >= 0, fcntl(fd, F_SETFL, flags | O_NONBLOCK) == 0 else {
        out("ERROR configuring accepted socket: \(String(cString: strerror(errno)))")
        continue
    }
    let response: HTTPResponse
    do {
        let request = try readRequest(fd, deadline: socketDeadline())
        if request.method == "POST" && request.path == "/state" {
            guard let incoming = try? JSONDecoder().decode(WhaleySceneSnapshot.self, from: request.body) else {
                throw HTTPFailure(status: 400, message: "invalid scene snapshot")
            }
            let accepted = StoredState(body: request.body, receivedAt: monotonicNow())
            live = accepted
            acceptedSnapshots &+= 1
            if acceptedSnapshots % 50 == 1 {
                out("STATE accepted count=\(acceptedSnapshots) bytes=\(request.body.count) level=\(incoming.level)")
            }
            response = HTTPResponse(status: 200,
                body: json(["ok": true, "session": incoming.session, "sequence": incoming.sequence]),
                headers: accepted.freshnessHeaders(maxAge: maxAge))
        } else if request.method == "GET" && request.path == "/hello" {
            response = HTTPResponse(status: 200, body: json(["ok": true, "client": request.headers["x-whaley-client"] ?? "unknown"]))
        } else if request.method == "GET" && request.path == "/state" {
            if let live {
                response = HTTPResponse(status: 200, body: live.body, headers: live.freshnessHeaders(maxAge: maxAge))
            } else {
                response = HTTPResponse(status: 409, body: json(["status": "waiting-for-mobile"]))
            }
        } else {
            response = HTTPResponse(status: 404, body: json(["error": "not found"]))
        }
    } catch let failure as HTTPFailure {
        response = HTTPResponse(status: failure.status, body: json(["error": failure.message]))
    } catch ConnectionFailure.timeout {
        response = HTTPResponse(status: 408, body: json(["error": "request deadline exceeded"]))
    } catch {
        out("ERROR reading connection: \(error)")
        continue
    }
    do {
        try sendResponse(fd, response: response)
    } catch {
        out("ERROR writing connection: \(error)")
    }
}
