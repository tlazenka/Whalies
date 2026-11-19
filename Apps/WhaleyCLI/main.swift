import Foundation
import Dispatch
import WhaleyCore
import SQLiteJSONBlaster
import MuttniksParsers

#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

#if os(Linux)
import Glibc
#else
import Darwin
#endif

enum WhaleyCLI {
    static let help = """
        Usage:
          whaley [observe]
          whaley query [--file document.json] [--] <query expression>
          whaley --help

        Commands:
          observe   Show the mobile game's state in an interactive terminal.
                    This is also the default when no command is given.
                    Use ↑ / ↓ to change the camera size; q, Ctrl-C or Ctrl-D exits.
          query     Print matching item IDs, one per line. Without --file, queries
                    require a fresh, verified mobile snapshot from the relay.
                    --file accepts a Whaley items document or GeoJSON features.

        Options:
          -h, --help        Show this help; also accepted after either command.
          --file PATH      Read query data from PATH instead of contacting the relay.
          --               End query options; the remaining words form the expression.

        Examples:
          whaley observe
          whaley query '$.properties.kind = "coin"'
          whaley query --file whaley-data.json '$.type = "recorded-run"'

        Relay environment (observe and live query only):
          WHALEY_RELAY_HOST   Hostname or IPv4/IPv6 address; default 127.0.0.1.
                             Do not include a URL scheme, path or port.
          WHALEY_RELAY_PORT   Integer from 1 to 65535; default 8092.

        Each relay request has a 3-second deadline and a 1 MiB response limit.
        The observer needs a terminal on stdin and stdout. It labels stale or
        unverified snapshots explicitly; live queries refuse either condition.
        """

    struct Query {
        var file: String?
        var expression: String
    }

    enum Command {
        case help, observe, query(Query)
    }

    static func command(_ arguments: [String]) throws -> Command {
        guard let name = arguments.first else { return .observe }
        let rest = Array(arguments.dropFirst())
        switch name {
        case "-h", "--help", "help":
            guard rest.isEmpty else {
                throw WhaleyCLIError.usage("Unexpected argument after \(name): \(rest[0])")
            }
            return .help
        case "observe":
            if rest == ["--help"] || rest == ["-h"] { return .help }
            guard rest.isEmpty else {
                throw WhaleyCLIError.usage("Unknown observe argument: \(rest[0])")
            }
            return .observe
        case "query":
            if rest == ["--help"] || rest == ["-h"] { return .help }
            var file: String?
            var expression: [String] = []
            var literal = false
            var index = 0
            while index < rest.count {
                let value = rest[index]
                if !literal && value == "--" {
                    literal = true
                } else if !literal && value == "--file" {
                    guard file == nil, expression.isEmpty else {
                        throw WhaleyCLIError.usage("--file may appear only once, before the query expression.")
                    }
                    index += 1
                    guard index < rest.count, !rest[index].isEmpty, !rest[index].hasPrefix("-") else {
                        throw WhaleyCLIError.usage("--file requires a path (use ./ for a filename beginning with '-').")
                    }
                    file = rest[index]
                } else if !literal && value.hasPrefix("-") && Double(value) == nil {
                    throw WhaleyCLIError.usage("Unknown query option: \(value)")
                } else {
                    expression.append(value)
                }
                index += 1
            }
            let text = expression.joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { throw WhaleyCLIError.usage("query requires an expression.") }
            return .query(Query(file: file, expression: text))
        default:
            let kind = name.hasPrefix("-") ? "option" : "command"
            throw WhaleyCLIError.usage("Unknown \(kind): \(name)")
        }
    }

    static func query(_ query: Query) async throws {
        let parsed = try parseQueryExpression(query.expression)
        let source: Data
        if let file = query.file {
            source = try Data(contentsOf: URL(fileURLWithPath: file))
        } else {
            let relay = WhaleyRelayClient(configuration: try RelayConfiguration())
            guard let snapshot = relay.snapshot() else {
                throw WhaleyCLIError.unavailable(relay.lastError ?? "No mobile game snapshot is available.")
            }
            guard relay.snapshotIsFresh else {
                throw WhaleyCLIError.unavailable(
                    "Live query refused: \(relay.snapshotDescription). Keep the mobile game publishing to \(relay.endpointDescription), " +
                    "or use --file with an exported document. Older relays must be updated to provide freshness headers."
                )
            }
            source = try WhaleyJSONDocument.data(snapshot: snapshot)
        }
        guard let root = try JSONSerialization.jsonObject(with: source) as? [String: Any] else {
            throw WhaleyCLIError.unavailable("Expected a JSON object.")
        }
        var document = root
        // Accept GeoJSON feature collections alongside Whaley's native items.
        if document["items"] == nil, let features = document["features"] {
            document["items"] = features
        }
        guard document["items"] is [Any] else {
            throw WhaleyCLIError.unavailable("JSON must contain items or features.")
        }
        let normalized = try JSONSerialization.data(withJSONObject: document)
        guard let text = String(data: normalized, encoding: .utf8) else {
            throw WhaleyCLIError.unavailable("Invalid UTF-8 JSON.")
        }
        let db = try Database(path: ":memory:")
        try await db.execute("CREATE TABLE whaley_feed (document TEXT NOT NULL CHECK(json_valid(document)))")
        try await db.execute("INSERT INTO whaley_feed(document) VALUES (\(text))")
        let ids = try await db.query(SQL.whaleyIDs(matching: parsed)) { $0.string(at: 0) ?? "" }
        for id in ids where !id.isEmpty { print(id) }
    }

    static func run() throws {
        let relay = WhaleyRelayClient(configuration: try RelayConfiguration())
        guard isatty(STDIN_FILENO) == 1, isatty(STDOUT_FILENO) == 1 else {
            throw WhaleyCLIError.usage("observe needs an interactive terminal on stdin and stdout; use query for noninteractive output.")
        }
        let terminal = try RawTerminal()
        defer {
            terminal.restore()
            writeTerminal("\u{001B}[?25h\r\n")
        }
        writeTerminal("\u{001B}[?25l")
        var cameraSize = 9

        while true {
            _ = relay.snapshot()
            render(relay: relay, size: cameraSize)
            switch terminal.readKey(timeoutMilliseconds: 100) {
            case .up?: cameraSize = min(31, cameraSize + 2)
            case .down?: cameraSize = max(1, cameraSize - 2)
            case .quit?, .endOfInput?: return
            case .other?, nil: break
            }
        }
    }

    static func render(relay: WhaleyRelayClient, size: Int) {
        var lines: [String]
        if let snapshot = relay.cachedSnapshot {
            let mobile = relay.lastRequestSucceeded && relay.snapshotIsFresh ? "live" : "not live"
            lines = [
                "Whaley: level \(snapshot.level)   camera \(size)×\(size)   mobile \(mobile)",
                "relay \(relay.endpointDescription)   session \(terminalText(snapshot.session))   observation \(snapshot.sequence)",
                "state \(relay.snapshotDescription)",
                "time \(String(format: "%.1f", snapshot.gameTime))s   \(snapshot.dead ? "DEAD" : "alive")",
            ]
            if !relay.lastRequestSucceeded { lines.append("Showing a cached snapshot; \(relay.connectionDescription).") }
            if let error = relay.lastError { lines.append("error \(terminalText(error))") }
            lines.append("↑ larger  ↓ smaller   q quit")
            lines += WhaleyTerminalRenderer.lines(snapshot, size: size)
            lines.append("W Whaley  o bubble  $ coin  ^ flame  O goal  # wall  = ground")
        } else {
            lines = [
                "Whaley: \(relay.connectionDescription)",
                "relay \(relay.endpointDescription)",
                "error \(terminalText(relay.lastError ?? "none"))",
                "No level data output until the mobile game publishes a snapshot.",
                "↑ larger  ↓ smaller   q quit",
            ]
        }
        writeTerminal("\u{001B}[2J\u{001B}[H" + lines.joined(separator: "\r\n"))
    }

    static func terminalText(_ value: String) -> String {
        // Remote identifiers and error descriptions must not inject terminal controls.
        String(String.UnicodeScalarView(value.unicodeScalars.filter {
            !CharacterSet.controlCharacters.contains($0)
        })).prefix(300).description
    }

    static func writeTerminal(_ value: String) {
        FileHandle.standardOutput.write(Data(value.utf8))
    }
}

enum Key { case up, down, quit, other, endOfInput }

final class RawTerminal {
    private var original = termios(), active = false

    init() throws {
        guard tcgetattr(STDIN_FILENO, &original) == 0 else {
            throw WhaleyCLIError.unavailable("Could not read terminal settings.")
        }
        var raw = original
        cfmakeraw(&raw)
        guard tcsetattr(STDIN_FILENO, TCSANOW, &raw) == 0 else {
            throw WhaleyCLIError.unavailable("Could not enable terminal input.")
        }
        active = true
    }

    func restore() {
        if active {
            var value = original
            _ = tcsetattr(STDIN_FILENO, TCSANOW, &value)
            active = false
        }
    }

    func readKey(timeoutMilliseconds: Int32) -> Key? {
        switch byte(timeoutMilliseconds: timeoutMilliseconds) {
        case .timeout: return nil
        case .end: return .endOfInput
        case .value(let first):
            if [3, 4, 81, 113].contains(first) { return .quit }
            guard first == 27 else { return .other }
            // An isolated Escape or truncated arrow sequence must not block forever.
            guard case .value(91) = byte(timeoutMilliseconds: 25) else { return .other }
            switch byte(timeoutMilliseconds: 25) {
            case .value(65): return .up
            case .value(66): return .down
            case .end: return .endOfInput
            default: return .other
            }
        }
    }

    private enum Byte { case value(UInt8), timeout, end }

    private func byte(timeoutMilliseconds: Int32) -> Byte {
        var descriptor = pollfd(fd: STDIN_FILENO, events: Int16(POLLIN), revents: 0)
        let ready = poll(&descriptor, 1, timeoutMilliseconds)
        if ready < 0 { return errno == EINTR ? .timeout : .end }
        if ready == 0 { return .timeout }
        guard descriptor.revents & Int16(POLLIN) != 0 else { return .end }
        var value: UInt8 = 0
        let count = read(STDIN_FILENO, &value, 1)
        if count == 1 { return .value(value) }
        return count < 0 && errno == EINTR ? .timeout : .end
    }
}

typealias LiveSnapshot = WhaleySceneSnapshot

struct RelayConfiguration {
    let endpoint: URL
    let endpointDescription: String

    init(environment: [String: String] = ProcessInfo.processInfo.environment) throws {
        let rawHost = environment["WHALEY_RELAY_HOST"] ?? "127.0.0.1"
        let rawPort = environment["WHALEY_RELAY_PORT"] ?? "8092"
        var host = rawHost
        if host.hasPrefix("[") && host.hasSuffix("]") {
            host = String(host.dropFirst().dropLast())
            guard host.contains(":") else {
                throw WhaleyCLIError.configuration("WHALEY_RELAY_HOST brackets may only enclose an IPv6 address.")
            }
        }
        guard Self.validHost(host) else {
            throw WhaleyCLIError.configuration("WHALEY_RELAY_HOST must be a hostname or IPv4/IPv6 address without a URL scheme, path, whitespace or port.")
        }
        guard !rawPort.isEmpty, rawPort.utf8.allSatisfy({ $0 >= 48 && $0 <= 57 }),
              let port = UInt16(rawPort), port > 0 else {
            throw WhaleyCLIError.configuration("WHALEY_RELAY_PORT must be an integer from 1 to 65535.")
        }
        let authority = host.contains(":") ? "[\(host)]" : host
        let address = "http://\(authority):\(port)"
        guard let endpoint = URL(string: address) else {
            throw WhaleyCLIError.configuration("WHALEY_RELAY_HOST could not form a relay URL.")
        }
        self.endpoint = endpoint
        endpointDescription = address
    }

    private static func validHost(_ host: String) -> Bool {
        guard !host.isEmpty, host.utf8.count <= 253 else { return false }
        if host.contains(":") {
            var address = in6_addr()
            return host.withCString { inet_pton(AF_INET6, $0, &address) } == 1
        }
        if host.utf8.allSatisfy({ ($0 >= 48 && $0 <= 57) || $0 == 46 }) && host.contains(".") {
            var address = in_addr()
            return host.withCString { inet_pton(AF_INET, $0, &address) } == 1
        }
        let name = host.hasSuffix(".") ? String(host.dropLast()) : host
        let labels = name.split(separator: ".", omittingEmptySubsequences: false)
        return labels.allSatisfy { label in
            let bytes = Array(label.utf8)
            guard let first = bytes.first, let last = bytes.last, bytes.count <= 63,
                  first != 45, last != 45 else { return false }
            return bytes.allSatisfy {
                ($0 >= 48 && $0 <= 57) || ($0 >= 65 && $0 <= 90) || ($0 >= 97 && $0 <= 122) || $0 == 45
            }
        }
    }
}

final class WhaleyRelayClient {
    private let configuration: RelayConfiguration
    private let clientID = "cli-\(ProcessInfo.processInfo.processIdentifier)"
    private var freshness: Freshness?
    private var lastHTTPStatus: Int?
    private(set) var cachedSnapshot: LiveSnapshot?
    private(set) var lastRequestSucceeded = false
    private(set) var lastError: String?
    var endpointDescription: String { configuration.endpointDescription }

    init(configuration: RelayConfiguration) { self.configuration = configuration }

    private enum Freshness {
        case verified(age: TimeInterval, maximum: TimeInterval, requestStarted: TimeInterval, reportedLive: Bool)
        case unverified(String)

        var isFresh: Bool {
            guard case let .verified(age, maximum, started, live) = self else { return false }
            return live && age + max(0, ProcessInfo.processInfo.systemUptime - started) <= maximum
        }

        var description: String {
            switch self {
            case let .verified(age, maximum, started, _):
                let currentAge = age + max(0, ProcessInfo.processInfo.systemUptime - started)
                return "\(isFresh ? "fresh" : "STALE") snapshot; age \(String(format: "%.1f", currentAge))s, maximum \(String(format: "%.1f", maximum))s"
            case .unverified(let reason):
                return "unverified snapshot (\(reason))"
            }
        }
    }

    var snapshotIsFresh: Bool { freshness?.isFresh == true }
    var snapshotDescription: String { freshness?.description ?? "no snapshot" }
    var connectionDescription: String {
        if lastHTTPStatus == 409 { return "relay reachable; waiting for mobile game" }
        if lastRequestSucceeded { return "relay reachable" }
        if let status = lastHTTPStatus { return "relay request failed (HTTP \(status))" }
        return "relay connection failed"
    }

    func snapshot() -> LiveSnapshot? {
        // Never let an earlier successful poll mask the current request's failure.
        lastRequestSucceeded = false
        lastError = nil
        lastHTTPStatus = nil
        let started = ProcessInfo.processInfo.systemUptime
        var request = URLRequest(url: configuration.endpoint.appendingPathComponent("state"))
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("CLI", forHTTPHeaderField: "X-Whaley-Client")
        request.setValue(clientID, forHTTPHeaderField: "X-Whaley-Client-ID")
        do {
            let response = try BoundedHTTPTransfer.get(request)
            lastHTTPStatus = response.http.statusCode
            guard response.http.statusCode == 200 else {
                if response.http.statusCode == 409 {
                    lastError = "No mobile snapshot has been published to this relay (HTTP 409)."
                } else {
                    lastError = "Relay returned HTTP \(response.http.statusCode): \(HTTPURLResponse.localizedString(forStatusCode: response.http.statusCode))."
                }
                return nil
            }
            let snapshot: LiveSnapshot
            do {
                snapshot = try JSONDecoder().decode(LiveSnapshot.self, from: response.data)
            } catch {
                lastError = "Relay returned an invalid game snapshot: \(error)."
                return nil
            }
            // The terminal can expand to 31 cells around the player; reject
            // numeric extremes before its camera-coordinate arithmetic can overflow.
            let cameraBounds = (Int.min + 31)...(Int.max - 31)
            guard cameraBounds.contains(snapshot.player.x), cameraBounds.contains(snapshot.player.y) else {
                lastError = "Relay returned player coordinates outside the terminal's supported integer range."
                return nil
            }
            cachedSnapshot = snapshot
            freshness = Self.freshness(response.http, requestStarted: started)
            lastRequestSucceeded = true
            return snapshot
        } catch {
            lastHTTPStatus = (error as? BoundedHTTPTransfer.Failure)?.statusCode
            lastError = "Relay request failed: \(error)"
            return nil
        }
    }

    private static func freshness(_ response: HTTPURLResponse, requestStarted: TimeInterval) -> Freshness {
        guard let status = response.value(forHTTPHeaderField: "X-Whaley-State-Status"),
              let ageText = response.value(forHTTPHeaderField: "X-Whaley-State-Age"),
              let maximumText = response.value(forHTTPHeaderField: "X-Whaley-State-Max-Age") else {
            return .unverified("relay did not supply freshness headers")
        }
        guard let age = Double(ageText), age.isFinite, age >= 0,
              let maximum = Double(maximumText), maximum.isFinite, maximum > 0,
              status == "live" || status == "stale",
              (status == "live") == (age <= maximum) else {
            return .unverified("relay supplied invalid or inconsistent freshness headers")
        }
        // Conservatively include the whole request duration, then keep aging cached
        // data even while subsequent requests fail or the relay restarts.
        return .verified(age: age, maximum: maximum, requestStarted: requestStarted, reportedLive: status == "live")
    }
}

/// URLSession handles HTTP framing, partial I/O and address resolution. The delegate
/// caps streaming data before appending it, and a separate deadline also bounds DNS
/// or transport stalls that would otherwise prevent the observer from reading q.
private final class BoundedHTTPTransfer: NSObject, URLSessionDataDelegate, @unchecked Sendable {
    struct Response {
        let http: HTTPURLResponse
        let data: Data
    }

    struct Failure: Error, CustomStringConvertible {
        let underlying: Error
        let statusCode: Int?
        var description: String { String(describing: underlying) }
    }

    private static let timeout: TimeInterval = 3
    private static let maximumBodyBytes = 1_048_576
    private let lock = NSLock()
    private let completed = DispatchSemaphore(value: 0)
    private var response: HTTPURLResponse?
    private var body = Data()
    private var result: Result<Response, Error>?

    static func get(_ request: URLRequest) throws -> Response {
        let transfer = BoundedHTTPTransfer()
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = timeout
        configuration.timeoutIntervalForResource = timeout
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.urlCache = nil
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        let queue = OperationQueue()
        queue.maxConcurrentOperationCount = 1
        // A dedicated delegate queue can finish even when the async CLI entry point
        // is waiting on its main actor; never dispatch these callbacks to main.
        let session = URLSession(configuration: configuration, delegate: transfer, delegateQueue: queue)
        defer { session.invalidateAndCancel() }
        var request = request
        request.timeoutInterval = timeout
        let task = session.dataTask(with: request)
        task.resume()
        if transfer.completed.wait(timeout: .now() + timeout) == .timedOut {
            transfer.finish(.failure(WhaleyCLIError.unavailable("Timed out after \(Int(timeout)) seconds.")))
            task.cancel()
        }
        transfer.lock.lock()
        let result = transfer.result
        let statusCode = transfer.response?.statusCode
        transfer.lock.unlock()
        guard let result else { throw WhaleyCLIError.unavailable("Relay request ended without a response.") }
        switch result {
        case .success(let response): return response
        case .failure(let error): throw Failure(underlying: error, statusCode: statusCode)
        }
    }

    private func finish(_ value: Result<Response, Error>) {
        lock.lock()
        guard result == nil else { lock.unlock(); return }
        result = value
        body = Data()
        lock.unlock()
        completed.signal()
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse,
                    completionHandler: @Sendable @escaping (URLSession.ResponseDisposition) -> Void) {
        guard let http = response as? HTTPURLResponse else {
            finish(.failure(WhaleyCLIError.unavailable("Relay returned a non-HTTP response.")))
            completionHandler(.cancel)
            return
        }
        lock.lock()
        let pending = result == nil
        if pending { self.response = http }
        lock.unlock()
        guard pending else { completionHandler(.cancel); return }
        // Error status bodies are not needed, so stop receiving them immediately.
        guard http.statusCode == 200 else {
            finish(.success(Response(http: http, data: Data())))
            completionHandler(.cancel)
            return
        }
        guard http.expectedContentLength <= Int64(Self.maximumBodyBytes) else {
            finish(.failure(WhaleyCLIError.unavailable("Relay response exceeds the 1 MiB limit.")))
            completionHandler(.cancel)
            return
        }
        completionHandler(.allow)
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        lock.lock()
        guard result == nil else { lock.unlock(); return }
        guard data.count <= Self.maximumBodyBytes - body.count else {
            lock.unlock()
            finish(.failure(WhaleyCLIError.unavailable("Relay response exceeds the 1 MiB limit.")))
            dataTask.cancel()
            return
        }
        body.append(data)
        lock.unlock()
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        lock.lock()
        guard result == nil else { lock.unlock(); return }
        let response = self.response
        let data = body
        lock.unlock()
        if let error {
            finish(.failure(error))
        } else if let response {
            finish(.success(Response(http: response, data: data)))
        } else {
            finish(.failure(WhaleyCLIError.unavailable("Relay returned no HTTP response.")))
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @Sendable @escaping (URLRequest?) -> Void) {
        // Report 3xx to the caller instead of silently changing the configured relay.
        completionHandler(nil)
    }
}

private enum WhaleyCLIError: Error, CustomStringConvertible {
    case usage(String)
    case configuration(String)
    case unavailable(String)

    var exitCode: Int32 {
        switch self {
        case .usage, .configuration: return 2
        case .unavailable: return 1
        }
    }

    var description: String {
        switch self {
        case .usage(let message):
            return "\(message)\nRun 'whaley --help' for usage."
        case .configuration(let message), .unavailable(let message):
            return message
        }
    }
}

do {
    switch try WhaleyCLI.command(Array(CommandLine.arguments.dropFirst())) {
    case .help: print(WhaleyCLI.help)
    case .observe: try WhaleyCLI.run()
    case .query(let query): try await WhaleyCLI.query(query)
    }
} catch {
    FileHandle.standardError.write(Data("Error: \(error)\n".utf8))
    exit((error as? WhaleyCLIError)?.exitCode ?? EXIT_FAILURE)
}
