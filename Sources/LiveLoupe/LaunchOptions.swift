import Foundation

struct LaunchOptions {
    let folderURL: URL?
    let port: Int?
    let previewMode: PreviewMode?
    let shouldStartServer: Bool

    static var current: LaunchOptions {
        let arguments = CommandLine.arguments
        let folderPath = value(after: "--folder", in: arguments)
        let portValue = value(after: "--port", in: arguments).flatMap(Int.init)
        let mode = value(after: "--mode", in: arguments).flatMap(PreviewMode.init(rawValue:))

        return LaunchOptions(
            folderURL: folderPath.map { URL(fileURLWithPath: $0).standardizedFileURL },
            port: portValue,
            previewMode: mode,
            shouldStartServer: arguments.contains("--start")
        )
    }

    static func from(url: URL) -> LaunchOptions? {
        guard url.scheme?.lowercased() == "liveloupe" else { return nil }

        let command = (url.host?.isEmpty == false ? url.host : url.path)
            .map { $0.trimmingCharacters(in: CharacterSet(charactersIn: "/")) }
            .map { $0.lowercased() }

        guard command == "start" else { return nil }

        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        var query: [String: String] = [:]
        for item in components?.queryItems ?? [] {
            query[item.name] = item.value ?? ""
        }

        let folderURL = query["folder"].flatMap { value -> URL? in
            guard !value.isEmpty else { return nil }
            return URL(fileURLWithPath: value).standardizedFileURL
        }
        let port = query["port"].flatMap(Int.init)
        let mode = query["mode"].flatMap(PreviewMode.init(rawValue:))
        let shouldStart = query["start"].map(Self.booleanValue) ?? true

        return LaunchOptions(
            folderURL: folderURL,
            port: port,
            previewMode: mode,
            shouldStartServer: shouldStart
        )
    }

    private static func value(after flag: String, in arguments: [String]) -> String? {
        guard let index = arguments.firstIndex(of: flag),
              arguments.indices.contains(index + 1) else {
            return nil
        }

        return arguments[index + 1]
    }

    private static func booleanValue(_ value: String) -> Bool {
        switch value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "1", "true", "yes", "y", "on":
            true
        default:
            false
        }
    }
}
