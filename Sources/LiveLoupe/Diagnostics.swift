import Foundation

enum Diagnostics {
    static var logURL: URL {
        let baseURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support")

        return baseURL
            .appendingPathComponent("Live Loupe", isDirectory: true)
            .appendingPathComponent("live-debug.log")
    }

    static func log(_ message: @autoclosure () -> String) {
        do {
            let fileURL = logURL
            try FileManager.default.createDirectory(
                at: fileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )

            let safeMessage = message()
                .replacingOccurrences(of: "\r", with: " ")
                .replacingOccurrences(of: "\n", with: " ")
            let now = Date()
            let line = String(
                format: "%@  %.3f  app  %@\n",
                Self.timestamp.string(from: now),
                now.timeIntervalSince1970,
                safeMessage
            )
            let data = Data(line.utf8)

            if FileManager.default.fileExists(atPath: fileURL.path) {
                let handle = try FileHandle(forWritingTo: fileURL)
                try handle.seekToEnd()
                try handle.write(contentsOf: data)
                try handle.close()
            } else {
                try data.write(to: fileURL, options: .atomic)
            }
        } catch {
            NSLog("Could not write Live Loupe diagnostic log: \(error.localizedDescription)")
        }
    }

    private static let timestamp: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter
    }()
}
