import AppKit
import Foundation
import SwiftUI

@MainActor
private enum AppearanceController {
    static func apply(mode: AppAppearanceMode) {
        let appearance = mode.appKitAppearanceName.flatMap(NSAppearance.init(named:))
        NSApp.appearance = appearance

        for window in NSApp.windows {
            window.appearance = appearance
            window.contentView?.needsLayout = true
            window.contentView?.needsDisplay = true
            window.displayIfNeeded()
        }
    }
}

enum AppAppearanceMode: String, CaseIterable, Identifiable {
    case system
    case light
    case dark

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system:
            "System"
        case .light:
            "Light"
        case .dark:
            "Dark"
        }
    }

    var helpText: String {
        switch self {
        case .system:
            "Follow the current macOS appearance."
        case .light:
            "Force the app into light appearance immediately."
        case .dark:
            "Force the app into dark appearance immediately."
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .system:
            nil
        case .light:
            .light
        case .dark:
            .dark
        }
    }

    var appKitAppearanceName: NSAppearance.Name? {
        switch self {
        case .system:
            nil
        case .light:
            .aqua
        case .dark:
            .darkAqua
        }
    }
}

enum ServerStatus: Equatable {
    case stopped
    case starting
    case running
    case failed(String)

    var title: String {
        switch self {
        case .stopped:
            "Stopped"
        case .starting:
            "Starting"
        case .running:
            "Running"
        case .failed:
            "Error"
        }
    }
}

struct ConnectionTarget: Identifiable, Hashable {
    let id: String
    let title: String
    let host: String

    func url(port: Int, path: String = "/") -> URL? {
        var components = URLComponents()
        components.scheme = "http"
        components.host = host
        components.port = port
        components.path = path
        return components.url
    }
}

enum PreviewMode: String, CaseIterable, Identifiable {
    case export
    case screen

    var id: String { rawValue }

    var title: String {
        switch self {
        case .export:
            "Export"
        case .screen:
            "Live"
        }
    }

    var helpText: String {
        switch self {
        case .export:
            "Show JPEG files exported by the Lightroom plugin into the selected folder."
        case .screen:
            "Stream the current Lightroom screen or cropped image area directly to the iPhone."
        }
    }

    var path: String {
        switch self {
        case .export:
            "/"
        case .screen:
            "/screen"
        }
    }
}

@MainActor
final class AppState: ObservableObject {
    @Published var folderURL: URL?
    @Published var port: Int
    @Published private(set) var status: ServerStatus = .stopped
    @Published private(set) var networkAddress: String?
    @Published private(set) var networkEndpoints: [LocalNetworkEndpoint] = []
    @Published private(set) var connectionTargets: [ConnectionTarget] = []
    @Published var selectedTargetID: String?
    @Published var exportSettings: ExportSettings {
        didSet {
            persistExportSettings()
        }
    }
    @Published var previewMode: PreviewMode = .export {
        didSet {
            defaults.set(previewMode.rawValue, forKey: previewModeKey)
            refreshScreenCaptureAccess()
        }
    }
    @Published private(set) var localHostname: String?
    @Published private(set) var screenCaptureAccessGranted = LightroomScreenCapture.hasAccess
    @Published var screenPerformanceMode: ScreenPerformanceMode = ScreenPerformanceMode.current {
        didSet {
            ScreenPerformanceMode.save(screenPerformanceMode)
        }
    }
    @Published var appearanceMode: AppAppearanceMode {
        didSet {
            defaults.set(appearanceMode.rawValue, forKey: appearanceModeKey)
            AppearanceController.apply(mode: appearanceMode)
        }
    }

    /// Normalized (0...1, origin top-left) region of the Lightroom window that is
    /// streamed in Screen Live. Full window = LightroomScreenCapture.fullCropRect.
    @Published var screenCropRect: CGRect = LightroomScreenCapture.currentCropRect() {
        didSet {
            LightroomScreenCapture.saveCropRect(screenCropRect)
        }
    }

    var hasScreenCrop: Bool {
        screenCropRect != LightroomScreenCapture.fullCropRect
    }

    private var server: GalleryServer?

    private let defaults = UserDefaults.standard
    private let folderKey = "previewFolderPath"
    private let portKey = "serverPort"
    private let qualityKey = "export.jpegQuality"
    private let longEdgeKey = "export.longEdgePixels"
    private let outputSharpeningKey = "export.outputSharpening"
    private let minimizeMetadataKey = "export.minimizeMetadata"
    private let removeLocationMetadataKey = "export.removeLocationMetadata"
    private let liveLongEdgeKey = "export.livePreviewLongEdge"
    private let liveQualityKey = "export.livePreviewQuality"
    private let previewModeKey = "previewMode"
    private let appearanceModeKey = "appearance.mode"
    private let forceDarkAppearanceKey = "appearance.forceDark"

    init() {
        exportSettings = Self.loadExportSettings(from: defaults)
        let storedAppearanceMode = Self.loadAppearanceMode(from: defaults)
        appearanceMode = storedAppearanceMode
        AppearanceController.apply(mode: storedAppearanceMode)
        let launchOptions = LaunchOptions.current

        if let rawPreviewMode = defaults.string(forKey: previewModeKey),
           let storedPreviewMode = PreviewMode(rawValue: rawPreviewMode) {
            previewMode = storedPreviewMode
        }

        if let launchPreviewMode = launchOptions.previewMode {
            previewMode = launchPreviewMode
        }

        let storedPort = defaults.integer(forKey: portKey)
        port = launchOptions.port ?? (storedPort == 0 ? 8765 : storedPort)

        if let launchFolderURL = launchOptions.folderURL {
            folderURL = launchFolderURL
            defaults.set(launchFolderURL.path, forKey: folderKey)
        } else if let path = defaults.string(forKey: folderKey), !path.isEmpty {
            let url = URL(fileURLWithPath: path)
            if FileManager.default.fileExists(atPath: url.path) {
                folderURL = url
            }
        }

        refreshNetworkAddresses()
        persistExportSettings()

        if launchOptions.shouldStartServer {
            Task { @MainActor [weak self] in
                self?.start()
            }
        }
    }

    var localURL: URL? {
        guard status == .running else { return nil }
        return activeTarget?.url(port: port, path: previewMode.path)
    }

    var activeTarget: ConnectionTarget? {
        if let selectedTargetID,
           let target = connectionTargets.first(where: { $0.id == selectedTargetID }) {
            return target
        }

        return connectionTargets.first
    }

    func chooseFolder() {
        let panel = NSOpenPanel()
        panel.title = "Choose Preview Folder"
        panel.message = "Choose the folder Lightroom exports JPEG previews into."
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true

        if let folderURL {
            panel.directoryURL = folderURL
        }

        guard panel.runModal() == .OK, let selectedURL = panel.url else { return }
        setFolder(selectedURL)
    }

    func setFolder(_ url: URL) {
        folderURL = url
        defaults.set(url.path, forKey: folderKey)

        if status == .running {
            restart()
        }
    }

    func start() {
        let servingFolderURL: URL
        if let folderURL {
            servingFolderURL = folderURL
        } else if previewMode == .screen {
            servingFolderURL = Self.defaultPreviewFolderURL
        } else {
            Diagnostics.log("server start failed: no folder")
            status = .failed("Choose a folder first.")
            return
        }

        do {
            try FileManager.default.createDirectory(at: servingFolderURL, withIntermediateDirectories: true)
        } catch {
            Diagnostics.log("server start failed: folder create error \(error.localizedDescription)")
            status = .failed(error.localizedDescription)
            return
        }

        guard (1...65535).contains(port) else {
            Diagnostics.log("server start failed: invalid port \(port)")
            status = .failed("Port must be between 1 and 65535.")
            return
        }

        defaults.set(port, forKey: portKey)
        refreshNetworkAddresses()
        refreshScreenCaptureAccess()
        Diagnostics.log("server start requested folder=\(servingFolderURL.path) port=\(port) target=\(activeTarget?.host ?? "nil") mode=\(previewMode.rawValue)")

        do {
            status = .starting
            let newServer = try GalleryServer(folderURL: servingFolderURL, port: UInt16(port)) { [weak self] state in
                Task { @MainActor in
                    self?.handleServerState(state)
                }
            }
            try newServer.start()
            server = newServer
            Diagnostics.log("server start issued")
        } catch {
            server = nil
            status = .failed(error.localizedDescription)
            Diagnostics.log("server start error: \(error.localizedDescription)")
        }
    }

    func stop() {
        Diagnostics.log("server stop requested")
        server?.stop()
        server = nil
        status = .stopped
    }

    func restart() {
        stop()
        start()
    }

    func copyURLToPasteboard() {
        guard let urlString = localURL?.absoluteString else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(urlString, forType: .string)
    }

    func selectTarget(id: String) {
        selectedTargetID = id
    }

    func openURLOnMac() {
        guard let localURL else { return }
        NSWorkspace.shared.open(localURL)
    }

    func requestScreenCaptureAccess() {
        let granted = LightroomScreenCapture.requestAccess()
        refreshScreenCaptureAccess()
        Diagnostics.log("screen access requested returned=\(granted) granted=\(screenCaptureAccessGranted)")
    }

    func refreshScreenCaptureAccess() {
        screenCaptureAccessGranted = LightroomScreenCapture.hasAccess
    }

    func resetScreenCrop() {
        screenCropRect = LightroomScreenCapture.fullCropRect
    }

    /// Grabs one uncropped frame of the Lightroom window for the crop editor.
    func captureScreenPreview() async -> ScreenPreview? {
        do {
            return try await LightroomScreenCapture.capturePreview()
        } catch {
            Diagnostics.log("screen preview capture failed: \(error.localizedDescription)")
            return nil
        }
    }

    func revealFolder() {
        guard let folderURL else { return }
        NSWorkspace.shared.activateFileViewerSelecting([folderURL])
    }

    private func refreshNetworkAddresses() {
        networkEndpoints = NetworkAddress.ipv4Endpoints()
        networkAddress = networkEndpoints.first?.address
        localHostname = NetworkAddress.localHostname()
        connectionTargets = makeConnectionTargets()

        if let selectedTargetID,
           connectionTargets.contains(where: { $0.id == selectedTargetID }) {
            return
        }

        selectedTargetID = connectionTargets.first?.id
    }

    private func makeConnectionTargets() -> [ConnectionTarget] {
        var targets: [ConnectionTarget] = []
        var seenHosts: Set<String> = []

        if let localHostname {
            targets.append(
                ConnectionTarget(
                    id: "bonjour-\(localHostname)",
                    title: "Recommended · \(localHostname)",
                    host: localHostname
                )
            )
            seenHosts.insert(localHostname)
        }

        for endpoint in networkEndpoints where !seenHosts.contains(endpoint.address) {
            targets.append(
                ConnectionTarget(
                    id: endpoint.id,
                    title: "\(endpoint.title) · \(endpoint.address)",
                    host: endpoint.address
                )
            )
            seenHosts.insert(endpoint.address)
        }

        if targets.isEmpty {
            targets.append(ConnectionTarget(id: "localhost", title: "This Mac · 127.0.0.1", host: "127.0.0.1"))
        }

        return targets
    }

    private static var defaultPreviewFolderURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Pictures", isDirectory: true)
            .appendingPathComponent("Live Loupe", isDirectory: true)
    }

    private func handleServerState(_ state: GalleryServerState) {
        switch state {
        case .ready:
            status = .running
        case let .failed(message):
            server = nil
            status = .failed(message)
        case .stopped:
            if status != .stopped {
                status = .stopped
            }
        }
    }

    private static func loadExportSettings(from defaults: UserDefaults) -> ExportSettings {
        var settings = ExportSettings()

        let storedQuality = defaults.integer(forKey: "export.jpegQuality")
        if storedQuality > 0 {
            settings.jpegQuality = storedQuality
        }

        let storedLongEdge = defaults.integer(forKey: "export.longEdgePixels")
        if storedLongEdge > 0 {
            settings.longEdgePixels = storedLongEdge
        }

        if defaults.object(forKey: "export.outputSharpening") != nil {
            settings.outputSharpening = defaults.bool(forKey: "export.outputSharpening")
        }

        if defaults.object(forKey: "export.minimizeMetadata") != nil {
            settings.minimizeMetadata = defaults.bool(forKey: "export.minimizeMetadata")
        }

        if defaults.object(forKey: "export.removeLocationMetadata") != nil {
            settings.removeLocationMetadata = defaults.bool(forKey: "export.removeLocationMetadata")
        }

        let storedLiveLongEdge = defaults.integer(forKey: "export.livePreviewLongEdge")
        if storedLiveLongEdge > 0 {
            settings.livePreviewLongEdge = storedLiveLongEdge
        }

        let storedLiveQuality = defaults.integer(forKey: "export.livePreviewQuality")
        if storedLiveQuality > 0 {
            settings.livePreviewQuality = storedLiveQuality
        }

        settings.clamp()
        return settings
    }

    private static func loadAppearanceMode(from defaults: UserDefaults) -> AppAppearanceMode {
        if let rawValue = defaults.string(forKey: "appearance.mode"),
           let mode = AppAppearanceMode(rawValue: rawValue) {
            return mode
        }

        if defaults.bool(forKey: "appearance.forceDark") {
            return .dark
        }

        return .system
    }

    private func persistExportSettings() {
        defaults.set(exportSettings.jpegQuality, forKey: qualityKey)
        defaults.set(exportSettings.longEdgePixels, forKey: longEdgeKey)
        defaults.set(exportSettings.outputSharpening, forKey: outputSharpeningKey)
        defaults.set(exportSettings.minimizeMetadata, forKey: minimizeMetadataKey)
        defaults.set(exportSettings.removeLocationMetadata, forKey: removeLocationMetadataKey)
        defaults.set(exportSettings.livePreviewLongEdge, forKey: liveLongEdgeKey)
        defaults.set(exportSettings.livePreviewQuality, forKey: liveQualityKey)

        do {
            let fileURL = ExportSettings.configFileURL
            try FileManager.default.createDirectory(
                at: fileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try exportSettings.configContents().write(to: fileURL, atomically: true, encoding: .utf8)
        } catch {
            NSLog("Could not persist Live Loupe export settings: \(error.localizedDescription)")
        }
    }
}
