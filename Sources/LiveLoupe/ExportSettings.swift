import Foundation

struct ExportSettings: Equatable {
    var jpegQuality: Int = 100
    var longEdgePixels: Int = 2556
    var outputSharpening: Bool = true
    var minimizeMetadata: Bool = true
    var removeLocationMetadata: Bool = true
    var livePreviewLongEdge: Int = 720
    var livePreviewQuality: Int = 45

    static let configDirectoryName = "Live Loupe"
    static let configFileName = "export-settings.conf"

    static var configFileURL: URL {
        let baseURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support")

        return baseURL
            .appendingPathComponent(configDirectoryName, isDirectory: true)
            .appendingPathComponent(configFileName)
    }

    var normalizedQuality: Double {
        Double(jpegQuality) / 100
    }

    mutating func clamp() {
        jpegQuality = min(max(jpegQuality, 1), 100)
        longEdgePixels = min(max(longEdgePixels, 512), 6000)
        livePreviewLongEdge = min(max(livePreviewLongEdge, 320), 2000)
        livePreviewQuality = min(max(livePreviewQuality, 1), 100)
    }

    func configContents() -> String {
        """
        jpegQuality=\(jpegQuality)
        longEdgePixels=\(longEdgePixels)
        outputSharpening=\(outputSharpening ? "true" : "false")
        minimizeMetadata=\(minimizeMetadata ? "true" : "false")
        removeLocationMetadata=\(removeLocationMetadata ? "true" : "false")
        livePreviewLongEdge=\(livePreviewLongEdge)
        livePreviewQuality=\(livePreviewQuality)
        """
    }
}
