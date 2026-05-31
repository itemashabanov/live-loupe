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

    private static func value(after flag: String, in arguments: [String]) -> String? {
        guard let index = arguments.firstIndex(of: flag),
              arguments.indices.contains(index + 1) else {
            return nil
        }

        return arguments[index + 1]
    }
}
