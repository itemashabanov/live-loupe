import Foundation
import Network

enum GalleryServerState: Sendable {
    case ready
    case failed(String)
    case stopped
}

struct ImageEntry: Codable {
    let id: String
    let name: String
    let relativePath: String
    let modified: Int64
    let size: Int64
}

enum GalleryServerError: LocalizedError {
    case invalidPort
    case invalidRequest
    case forbiddenPath
    case fileNotFound
    case routeUnavailable(PreviewMode)

    var errorDescription: String? {
        switch self {
        case .invalidPort:
            "Invalid server port."
        case .invalidRequest:
            "Invalid request."
        case .forbiddenPath:
            "Requested path is outside the preview folder."
        case .fileNotFound:
            "File not found."
        case let .routeUnavailable(mode):
            "This route is disabled while \(mode.title) mode is active."
        }
    }
}

enum GalleryRouteDecision: Equatable {
    case allowed
    case redirect(String)
    case unavailable
}

final class GalleryServer: @unchecked Sendable {
    private let folderURL: URL
    private let port: UInt16
    private let mode: PreviewMode
    private let onStateChange: @Sendable (GalleryServerState) -> Void
    private let queue = DispatchQueue(label: "lr-phone-preview.server")
    private let screenQueue = DispatchQueue(label: "lr-phone-preview.screen", qos: .userInitiated)
    private let imageExtensions: Set<String> = ["jpg", "jpeg", "png", "webp", "heic", "heif", "tif", "tiff"]
    private let livePreviewFileName = "__lr_live_preview.jpg"
    private var listener: NWListener?
    private var activeConnections: [ObjectIdentifier: NWConnection] = [:]
    private var lastLoggedLiveManifestSignature: String?
    private var screenFrameCountSinceLog = 0
    private var lastScreenLogDate = Date.distantPast
    private var lastScreenErrorSignature: String?
    private var lastScreenErrorLogDate = Date.distantPast

    init(
        folderURL: URL,
        port: UInt16,
        mode: PreviewMode = .export,
        onStateChange: @escaping @Sendable (GalleryServerState) -> Void = { _ in }
    ) throws {
        guard let nwPort = NWEndpoint.Port(rawValue: port) else {
            throw GalleryServerError.invalidPort
        }

        self.folderURL = folderURL.standardizedFileURL
        self.port = UInt16(nwPort.rawValue)
        self.mode = mode
        self.onStateChange = onStateChange
    }

    func start() throws {
        let parameters = NWParameters.tcp
        parameters.allowLocalEndpointReuse = true
        Diagnostics.log("listener start requested folder=\(folderURL.path) port=\(port) mode=\(mode.rawValue)")

        guard let nwPort = NWEndpoint.Port(rawValue: port) else {
            throw GalleryServerError.invalidPort
        }

        let listener = try NWListener(using: parameters, on: nwPort)
        listener.stateUpdateHandler = { [weak self] state in
            switch state {
            case .ready:
                self?.onStateChange(.ready)
            case let .failed(error):
                self?.onStateChange(.failed(error.localizedDescription))
            case .cancelled:
                self?.onStateChange(.stopped)
            default:
                break
            }
        }
        listener.newConnectionHandler = { [weak self] connection in
            self?.handle(connection)
        }
        listener.start(queue: queue)
        self.listener = listener
    }

    func stop() {
        Diagnostics.log("listener stop requested port=\(port) mode=\(mode.rawValue)")
        listener?.cancel()
        listener = nil

        queue.async { [weak self] in
            guard let self else { return }

            let connections = Array(self.activeConnections.values)
            self.activeConnections.removeAll()
            connections.forEach { $0.cancel() }

            if !connections.isEmpty {
                Diagnostics.log("listener cancelled active connections count=\(connections.count)")
            }
        }
    }

    private func handle(_ connection: NWConnection) {
        let connectionID = ObjectIdentifier(connection)
        activeConnections[connectionID] = connection
        connection.stateUpdateHandler = { [weak self] state in
            switch state {
            case .cancelled, .failed:
                self?.removeConnection(connectionID)
            default:
                break
            }
        }
        connection.start(queue: queue)
        receiveRequest(on: connection, buffer: Data())
    }

    private func receiveRequest(on connection: NWConnection, buffer: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) { [weak self] data, _, _, error in
            guard let self else {
                connection.cancel()
                return
            }

            guard error == nil else {
                self.sendError(GalleryServerError.invalidRequest, statusCode: 400, connection: connection)
                return
            }

            var nextBuffer = buffer
            if let data {
                nextBuffer.append(data)
            }

            guard !nextBuffer.isEmpty else {
                self.sendError(GalleryServerError.invalidRequest, statusCode: 400, connection: connection)
                return
            }

            if nextBuffer.count > 256 * 1024 {
                self.sendError(GalleryServerError.invalidRequest, statusCode: 413, connection: connection)
                return
            }

            if self.hasCompleteHeaders(nextBuffer) {
                self.route(nextBuffer, connection: connection)
            } else {
                self.receiveRequest(on: connection, buffer: nextBuffer)
            }
        }
    }

    private func hasCompleteHeaders(_ data: Data) -> Bool {
        data.range(of: Data("\r\n\r\n".utf8)) != nil || data.range(of: Data("\n\n".utf8)) != nil
    }

    private func route(_ requestData: Data, connection: NWConnection) {
        guard let request = String(data: requestData, encoding: .utf8),
              let firstLine = request.components(separatedBy: "\r\n").first else {
            sendError(GalleryServerError.invalidRequest, statusCode: 400, connection: connection)
            return
        }

        let parts = firstLine.split(separator: " ")
        guard parts.count >= 2, parts[0] == "GET" else {
            sendError(GalleryServerError.invalidRequest, statusCode: 405, connection: connection)
            return
        }

        let rawPath = String(parts[1])
        guard let url = URL(string: rawPath, relativeTo: URL(string: "http://localhost")) else {
            sendError(GalleryServerError.invalidRequest, statusCode: 400, connection: connection)
            return
        }

        switch Self.routeDecision(for: url.path, mode: mode) {
        case .allowed:
            break
        case let .redirect(path):
            Diagnostics.log("route redirect mode=\(mode.rawValue) from=\(url.path) to=\(path)")
            sendRedirect(to: path, connection: connection)
            return
        case .unavailable:
            Diagnostics.log("route denied mode=\(mode.rawValue) path=\(url.path)")
            sendRouteUnavailable(path: url.path, connection: connection)
            return
        }

        switch url.path {
        case "/":
            sendHTML(connection: connection)
        case "/screen":
            sendScreenHTML(connection: connection)
        case "/screen-config.json":
            sendScreenConfig(connection: connection)
        case "/screen.jpg":
            sendScreenFrame(mode: screenPerformanceMode(from: url), connection: connection)
        case "/screen.mjpg":
            sendScreenStream(mode: screenPerformanceMode(from: url), connection: connection)
        case "/manifest.json":
            sendManifest(connection: connection)
        default:
            if url.path.hasPrefix("/file/") {
                let id = String(url.path.dropFirst("/file/".count))
                sendFile(id: id, connection: connection)
            } else {
                sendError(GalleryServerError.fileNotFound, statusCode: 404, connection: connection)
            }
        }
    }

    private func sendHTML(connection: NWConnection) {
        send(
            data: Data(Self.galleryHTML.utf8),
            contentType: "text/html; charset=utf-8",
            cacheControl: "no-store",
            connection: connection
        )
    }

    private func sendScreenHTML(connection: NWConnection) {
        send(
            data: Data(Self.screenHTML.utf8),
            contentType: "text/html; charset=utf-8",
            cacheControl: "no-store",
            connection: connection
        )
    }

    private func sendScreenFrame(mode: ScreenPerformanceMode, connection: NWConnection) {
        screenQueue.async { [weak self] in
            guard let self else {
                connection.cancel()
                return
            }

            do {
                let frame = try LightroomScreenCapture.captureJPEG(mode: mode)
                self.logScreenFrame(frame, isStream: false, isIdle: false)
                self.send(
                    data: frame.data,
                    contentType: "image/jpeg",
                    cacheControl: "no-store, max-age=0",
                    connection: connection
                )
            } catch {
                self.logScreenError(error)
                self.sendError(error, statusCode: 503, connection: connection)
            }
        }
    }

    private func sendScreenConfig(connection: NWConnection) {
        do {
            let data = try JSONEncoder().encode(ScreenRuntimeConfig(mode: ScreenPerformanceMode.current))
            send(
                data: data,
                contentType: "application/json; charset=utf-8",
                cacheControl: "no-store",
                connection: connection
            )
        } catch {
            sendError(error, statusCode: 500, connection: connection)
        }
    }

    private func sendScreenStream(mode: ScreenPerformanceMode, connection: NWConnection) {
        screenQueue.async { [weak self] in
            guard let self else {
                connection.cancel()
                return
            }

            do {
                let firstFrame = try LightroomScreenCapture.captureJPEG(mode: mode)
                let context = ScreenStreamContext(mode: mode)
                self.sendRaw(data: context.headerData, connection: connection, isComplete: false) { [weak self] error in
                    guard error == nil else {
                        connection.cancel()
                        return
                    }

                    self?.screenQueue.async { [weak self] in
                        self?.sendScreenStreamFrame(firstFrame, context: context, connection: connection)
                    }
                }
            } catch {
                self.logScreenError(error)
                self.sendError(error, statusCode: 503, connection: connection)
            }
        }
    }

    private func sendScreenStreamFrame(_ frame: ScreenCaptureResult, context: ScreenStreamContext, connection: NWConnection) {
        let streamState = context.observe(frame)
        logScreenFrame(frame, isStream: true, isIdle: streamState.isIdle)
        let partData = context.partData(for: frame)

        sendRaw(data: partData, connection: connection, isComplete: false) { [weak self] error in
            guard let self else {
                connection.cancel()
                return
            }

            if let error {
                Diagnostics.log("screen stream closed mode=\(context.mode.rawValue) message=\(error.localizedDescription)")
                cancelConnection(connection)
                return
            }

            self.screenQueue.asyncAfter(deadline: .now() + streamState.delay) { [weak self] in
                guard let self else {
                    connection.cancel()
                    return
                }

                do {
                    let nextFrame = try LightroomScreenCapture.captureJPEG(mode: context.mode)
                    self.sendScreenStreamFrame(nextFrame, context: context, connection: connection)
                } catch {
                    self.logScreenError(error)
                    self.cancelConnection(connection)
                }
            }
        }
    }

    static func routeDecision(for path: String, mode: PreviewMode) -> GalleryRouteDecision {
        switch mode {
        case .export:
            if path == "/" || path == "/manifest.json" || path.hasPrefix("/file/") {
                return .allowed
            }

            if path == "/screen" {
                return .redirect("/")
            }

            if path == "/screen-config.json" || path == "/screen.jpg" || path == "/screen.mjpg" {
                return .unavailable
            }

            return .allowed
        case .screen:
            if path == "/screen"
                || path == "/screen-config.json"
                || path == "/screen.jpg"
                || path == "/screen.mjpg" {
                return .allowed
            }

            if path == "/" {
                return .redirect("/screen")
            }

            if path == "/manifest.json" || path.hasPrefix("/file/") {
                return .unavailable
            }

            return .allowed
        }
    }

    private func sendManifest(connection: NWConnection) {
        do {
            let entries = try imageEntries()
            logManifest(entries)
            let data = try JSONEncoder().encode(entries)
            send(
                data: data,
                contentType: "application/json; charset=utf-8",
                cacheControl: "no-store",
                connection: connection
            )
        } catch {
            sendError(error, statusCode: 500, connection: connection)
        }
    }

    private func logScreenFrame(_ frame: ScreenCaptureResult, isStream: Bool, isIdle: Bool) {
        screenFrameCountSinceLog += 1
        lastScreenErrorSignature = nil

        let now = Date()
        guard now.timeIntervalSince(lastScreenLogDate) >= 1 else {
            return
        }

        let elapsed = max(now.timeIntervalSince(lastScreenLogDate), 0.001)
        let fps = lastScreenLogDate == .distantPast ? 0 : Double(screenFrameCountSinceLog) / elapsed
        Diagnostics.log(String(
            format: "screen frame mode=%@ transport=%@ idle=%@ fps=%.1f capture=%.1fms encode=%.1fms bytes=%d size=%dx%d window=%@",
            frame.mode.rawValue,
            isStream ? "mjpeg" : "single",
            isIdle ? "true" : "false",
            fps,
            frame.captureMilliseconds,
            frame.encodeMilliseconds,
            frame.data.count,
            frame.pixelWidth,
            frame.pixelHeight,
            frame.windowTitle
        ))

        lastScreenLogDate = now
        screenFrameCountSinceLog = 0
    }

    private func logScreenError(_ error: Error) {
        let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        let now = Date()

        guard message != lastScreenErrorSignature || now.timeIntervalSince(lastScreenErrorLogDate) >= 2 else {
            return
        }

        lastScreenErrorSignature = message
        lastScreenErrorLogDate = now
        Diagnostics.log("screen ERROR \(message)")
    }

    private func screenPerformanceMode(from url: URL) -> ScreenPerformanceMode {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let rawMode = components.queryItems?.first(where: { $0.name == "mode" })?.value,
              let mode = ScreenPerformanceMode(rawValue: rawMode) else {
            return ScreenPerformanceMode.current
        }

        return mode
    }

    private func logManifest(_ entries: [ImageEntry]) {
        if let liveEntry = entries.first(where: { $0.name == livePreviewFileName || $0.relativePath == livePreviewFileName }) {
            let signature = "\(liveEntry.modified)-\(liveEntry.size)"
            if signature != lastLoggedLiveManifestSignature {
                lastLoggedLiveManifestSignature = signature
                Diagnostics.log("manifest live modified=\(liveEntry.modified) size=\(liveEntry.size)")
            }
            return
        }

        if lastLoggedLiveManifestSignature != nil {
            lastLoggedLiveManifestSignature = nil
            Diagnostics.log("manifest live absent entries=\(entries.count)")
        }
    }

    private func sendFile(id: String, connection: NWConnection) {
        do {
            guard let relativePath = Base64URL.decode(id) else {
                throw GalleryServerError.invalidRequest
            }

            let fileURL = try safeFileURL(forRelativePath: relativePath)
            let data = try Data(contentsOf: fileURL)
            send(
                data: data,
                contentType: contentType(for: fileURL),
                cacheControl: "no-store",
                connection: connection
            )
        } catch {
            sendError(error, statusCode: 404, connection: connection)
        }
    }

    private func sendError(_ error: Error, statusCode: Int, connection: NWConnection) {
        let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        let body = Data("{\"error\":\"\(message.jsonEscaped)\"}".utf8)
        send(
            data: body,
            statusCode: statusCode,
            reason: HTTPReason.phrase(for: statusCode),
            contentType: "application/json; charset=utf-8",
            cacheControl: "no-store",
            connection: connection
        )
    }

    private static func redirectHTML(activeMode: PreviewMode, targetPath: String) -> String {
        routeMessageHTML(
            title: "Opening \(activeMode.title)",
            message: "This preview link belongs to another mode. Live Loupe is opening the active \(activeMode.title) preview.",
            targetPath: targetPath,
            buttonTitle: "Open \(activeMode.title)"
        )
    }

    private static func routeUnavailableHTML(activeMode: PreviewMode, targetPath: String) -> String {
        routeMessageHTML(
            title: "\(activeMode.title) mode is active",
            message: "This background route is only available in the other preview mode.",
            targetPath: targetPath,
            buttonTitle: "Go to \(activeMode.title)"
        )
    }

    private static func routeMessageHTML(
        title: String,
        message: String,
        targetPath: String,
        buttonTitle: String
    ) -> String {
        """
        <!doctype html>
        <html lang="en">
        <head>
          <meta charset="utf-8">
          <meta name="viewport" content="width=device-width, initial-scale=1, viewport-fit=cover">
          <title>Live Loupe</title>
          <style>
            :root {
              color-scheme: light dark;
              --bg: #f5f5f7;
              --card: rgba(255, 255, 255, 0.76);
              --text: #1d1d1f;
              --muted: #6e6e73;
              --line: rgba(0, 0, 0, 0.08);
              --blue: #007aff;
            }

            @media (prefers-color-scheme: dark) {
              :root {
                --bg: #101012;
                --card: rgba(44, 44, 46, 0.72);
                --text: #f5f5f7;
                --muted: #a1a1a6;
                --line: rgba(255, 255, 255, 0.14);
              }
            }

            * { box-sizing: border-box; }

            body {
              margin: 0;
              min-height: 100vh;
              display: grid;
              place-items: center;
              padding: 24px;
              background: var(--bg);
              color: var(--text);
              font: 16px/1.45 -apple-system, BlinkMacSystemFont, "SF Pro Text", "Segoe UI", sans-serif;
            }

            main {
              width: min(100%, 380px);
              padding: 26px;
              border: 1px solid var(--line);
              border-radius: 28px;
              background: var(--card);
              text-align: center;
              box-shadow: 0 18px 60px rgba(0, 0, 0, 0.14);
              backdrop-filter: blur(24px);
            }

            .icon {
              width: 54px;
              height: 54px;
              margin: 0 auto 18px;
              display: grid;
              place-items: center;
              border-radius: 18px;
              background: rgba(0, 122, 255, 0.12);
              color: var(--blue);
              font-size: 28px;
              font-weight: 700;
            }

            h1 {
              margin: 0;
              font-size: 26px;
              line-height: 1.12;
              letter-spacing: 0;
            }

            p {
              margin: 10px 0 22px;
              color: var(--muted);
            }

            a {
              display: inline-flex;
              align-items: center;
              justify-content: center;
              min-height: 44px;
              padding: 0 18px;
              border-radius: 14px;
              background: var(--blue);
              color: white;
              font-weight: 700;
              text-decoration: none;
            }
          </style>
        </head>
        <body>
          <main>
            <div class="icon">&#8599;</div>
            <h1>\(title.htmlEscaped)</h1>
            <p>\(message.htmlEscaped)</p>
            <a href="\(targetPath.htmlAttributeEscaped)">\(buttonTitle.htmlEscaped)</a>
          </main>
          <script>
            window.setTimeout(() => {
              window.location.replace('\(targetPath.javaScriptStringEscaped)');
            }, 450);
          </script>
        </body>
        </html>
        """
    }

    private func sendRedirect(to path: String, connection: NWConnection) {
        let body = Data(Self.redirectHTML(activeMode: mode, targetPath: path).utf8)
        send(
            data: body,
            statusCode: 302,
            reason: HTTPReason.phrase(for: 302),
            contentType: "text/html; charset=utf-8",
            cacheControl: "no-store",
            connection: connection,
            additionalHeaders: [
                "Location": path,
                "X-Live-Loupe-Mode": mode.rawValue,
                "X-Live-Loupe-Redirect": path
            ]
        )
    }

    private func sendRouteUnavailable(path: String, connection: NWConnection) {
        let targetPath = mode.path
        let body = Data(Self.routeUnavailableHTML(activeMode: mode, targetPath: targetPath).utf8)
        send(
            data: body,
            statusCode: 409,
            reason: HTTPReason.phrase(for: 409),
            contentType: "text/html; charset=utf-8",
            cacheControl: "no-store",
            connection: connection,
            additionalHeaders: [
                "X-Live-Loupe-Mode": mode.rawValue,
                "X-Live-Loupe-Redirect": targetPath
            ]
        )
    }

    private func send(
        data: Data,
        statusCode: Int = 200,
        reason: String = "OK",
        contentType: String,
        cacheControl: String,
        connection: NWConnection,
        additionalHeaders: [String: String] = [:]
    ) {
        let extraHeaders = additionalHeaders
            .map { "\($0.key): \($0.value)\r\n" }
            .joined()
        let header = """
        HTTP/1.1 \(statusCode) \(reason)\r
        Content-Type: \(contentType)\r
        Content-Length: \(data.count)\r
        Cache-Control: \(cacheControl)\r
        Access-Control-Allow-Origin: *\r
        \(extraHeaders)\
        Connection: close\r
        \r

        """

        var response = Data(header.utf8)
        response.append(data)
        connection.send(content: response, completion: .contentProcessed { [weak self] _ in
            self?.cancelConnection(connection)
        })
    }

    private func sendRaw(
        data: Data,
        connection: NWConnection,
        isComplete: Bool,
        completion: (@Sendable (NWError?) -> Void)? = nil
    ) {
        connection.send(content: data, isComplete: isComplete, completion: .contentProcessed { error in
            completion?(error)
        })
    }

    private func cancelConnection(_ connection: NWConnection) {
        connection.cancel()
        removeConnection(ObjectIdentifier(connection))
    }

    private func removeConnection(_ connectionID: ObjectIdentifier) {
        queue.async { [weak self] in
            self?.activeConnections.removeValue(forKey: connectionID)
        }
    }

    private func imageEntries() throws -> [ImageEntry] {
        let keys: [URLResourceKey] = [.isRegularFileKey, .contentModificationDateKey, .fileSizeKey]
        let livePreviewURL = folderURL.appendingPathComponent(livePreviewFileName)

        if let liveEntry = try imageEntry(for: livePreviewURL, keys: keys) {
            return [liveEntry]
        }

        guard let enumerator = FileManager.default.enumerator(
            at: folderURL,
            includingPropertiesForKeys: keys,
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else {
            return []
        }

        var entries: [ImageEntry] = []

        for case let fileURL as URL in enumerator {
            guard let entry = try imageEntry(for: fileURL, keys: keys) else {
                continue
            }

            entries.append(entry)
        }

        return entries.sorted {
            if $0.modified == $1.modified {
                return $0.name.localizedStandardCompare($1.name) == .orderedAscending
            }
            return $0.modified > $1.modified
        }
    }

    private func imageEntry(for fileURL: URL, keys: [URLResourceKey]) throws -> ImageEntry? {
        guard FileManager.default.fileExists(atPath: fileURL.path),
              imageExtensions.contains(fileURL.pathExtension.lowercased()) else {
            return nil
        }

        let values = try fileURL.resourceValues(forKeys: Set(keys))
        guard values.isRegularFile == true else {
            return nil
        }

        let relativePath = try relativePath(for: fileURL)
        let modified = Int64(((values.contentModificationDate ?? .distantPast).timeIntervalSince1970 * 1000).rounded())
        let size = Int64(values.fileSize ?? 0)

        return ImageEntry(
            id: Base64URL.encode(relativePath),
            name: fileURL.lastPathComponent,
            relativePath: relativePath,
            modified: modified,
            size: size
        )
    }

    private func safeFileURL(forRelativePath relativePath: String) throws -> URL {
        guard !relativePath.hasPrefix("/"), !relativePath.contains("../") else {
            throw GalleryServerError.forbiddenPath
        }

        let fileURL = folderURL.appendingPathComponent(relativePath).standardizedFileURL
        let rootPath = folderURL.path

        guard fileURL.path == rootPath || fileURL.path.hasPrefix(rootPath + "/") else {
            throw GalleryServerError.forbiddenPath
        }

        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            throw GalleryServerError.fileNotFound
        }

        return fileURL
    }

    private func relativePath(for fileURL: URL) throws -> String {
        let rootPath = folderURL.path
        let filePath = fileURL.standardizedFileURL.path

        guard filePath.hasPrefix(rootPath + "/") else {
            throw GalleryServerError.forbiddenPath
        }

        return String(filePath.dropFirst(rootPath.count + 1))
    }

    private func contentType(for url: URL) -> String {
        switch url.pathExtension.lowercased() {
        case "jpg", "jpeg":
            "image/jpeg"
        case "png":
            "image/png"
        case "webp":
            "image/webp"
        case "heic", "heif":
            "image/heic"
        case "tif", "tiff":
            "image/tiff"
        default:
            "application/octet-stream"
        }
    }
}

private enum Base64URL {
    static func encode(_ value: String) -> String {
        Data(value.utf8)
            .base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    static func decode(_ value: String) -> String? {
        var base64 = value
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")

        let padding = 4 - base64.count % 4
        if padding < 4 {
            base64 += String(repeating: "=", count: padding)
        }

        guard let data = Data(base64Encoded: base64) else { return nil }
        return String(data: data, encoding: .utf8)
    }
}

private struct ScreenStreamState {
    let delay: DispatchTimeInterval
    let isIdle: Bool
}

private final class ScreenStreamContext: @unchecked Sendable {
    let mode: ScreenPerformanceMode
    private let boundary = "liveloupe-\(UUID().uuidString)"
    private var lastSignature: UInt64?
    private var lastChangedAt = Date()

    init(mode: ScreenPerformanceMode) {
        self.mode = mode
    }

    var headerData: Data {
        Data(
            """
            HTTP/1.1 200 OK\r
            Content-Type: multipart/x-mixed-replace; boundary=\(boundary)\r
            Cache-Control: no-store, max-age=0\r
            Access-Control-Allow-Origin: *\r
            Connection: keep-alive\r
            \r

            """.utf8
        )
    }

    func observe(_ frame: ScreenCaptureResult) -> ScreenStreamState {
        let now = Date()

        if lastSignature != frame.signature {
            lastSignature = frame.signature
            lastChangedAt = now
        }

        let idle = now.timeIntervalSince(lastChangedAt) * 1_000 >= Double(mode.idleAfterMilliseconds)
        let milliseconds = idle ? mode.idleDelayMilliseconds : mode.activeDelayMilliseconds
        return ScreenStreamState(delay: .milliseconds(milliseconds), isIdle: idle)
    }

    func partData(for frame: ScreenCaptureResult) -> Data {
        var data = Data(
            """
            --\(boundary)\r
            Content-Type: image/jpeg\r
            Content-Length: \(frame.data.count)\r
            X-Screen-Mode: \(mode.rawValue)\r
            X-Capture-Milliseconds: \(String(format: "%.1f", frame.captureMilliseconds))\r
            X-Encode-Milliseconds: \(String(format: "%.1f", frame.encodeMilliseconds))\r
            \r

            """.utf8
        )
        data.append(frame.data)
        data.append(Data("\r\n".utf8))
        return data
    }
}

private enum HTTPReason {
    static func phrase(for statusCode: Int) -> String {
        switch statusCode {
        case 302:
            "Found"
        case 400:
            "Bad Request"
        case 404:
            "Not Found"
        case 405:
            "Method Not Allowed"
        case 409:
            "Conflict"
        case 500:
            "Internal Server Error"
        case 503:
            "Service Unavailable"
        default:
            "OK"
        }
    }
}

private extension String {
    var jsonEscaped: String {
        replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: "\\n")
            .replacingOccurrences(of: "\r", with: "\\r")
    }

    var htmlEscaped: String {
        replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&#39;")
    }

    var htmlAttributeEscaped: String {
        htmlEscaped
    }

    var javaScriptStringEscaped: String {
        replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "'", with: "\\'")
            .replacingOccurrences(of: "\n", with: "\\n")
            .replacingOccurrences(of: "\r", with: "\\r")
            .replacingOccurrences(of: "\u{2028}", with: "\\u2028")
            .replacingOccurrences(of: "\u{2029}", with: "\\u2029")
    }
}
