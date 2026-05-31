import Darwin
import Foundation

enum HeadlessMode {
    static func runIfRequested() {
        let arguments = CommandLine.arguments
        guard arguments.contains("--serve") else { return }

        do {
            guard let folderPath = try value(after: "--serve", in: arguments) else {
                throw HeadlessError.missingValue("--serve")
            }

            let portValue = try value(after: "--port", in: arguments, required: false) ?? "8765"

            guard let port = UInt16(portValue) else {
                throw HeadlessError.invalidPort
            }

            let folderURL = URL(fileURLWithPath: folderPath).standardizedFileURL
            let server = try GalleryServer(folderURL: folderURL, port: port)
            try server.start()

            let host = NetworkAddress.primaryIPv4Address() ?? "127.0.0.1"
            print("Serving \(folderURL.path) at http://\(host):\(port)")
            fflush(stdout)

            signal(SIGINT) { _ in exit(0) }
            signal(SIGTERM) { _ in exit(0) }

            withExtendedLifetime(server) {
                RunLoop.main.run()
            }
        } catch {
            fputs("LiveLoupe: \(error.localizedDescription)\n", stderr)
            exit(1)
        }
    }

    private static func value(after flag: String, in arguments: [String], required: Bool = true) throws -> String? {
        guard let index = arguments.firstIndex(of: flag), arguments.indices.contains(index + 1) else {
            if required {
                throw HeadlessError.missingValue(flag)
            }
            return nil
        }

        return arguments[index + 1]
    }
}

enum HeadlessError: LocalizedError {
    case invalidPort
    case missingValue(String)

    var errorDescription: String? {
        switch self {
        case .invalidPort:
            "Headless port must be between 1 and 65535."
        case let .missingValue(flag):
            "Missing value after \(flag)."
        }
    }
}
