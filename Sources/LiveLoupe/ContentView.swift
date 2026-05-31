import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.colorScheme) private var colorScheme
    @State private var isDropTargeted = false
    @State private var isFolderPathHovering = false
    @State private var isSettingsPresented = false
    @State private var isCropEditorPresented = false

    var body: some View {
        ZStack(alignment: .topTrailing) {
            appBackground

            VStack(spacing: 0) {
                titleBar

                Divider()
                    .opacity(0.5)

                HStack(alignment: .top, spacing: 12) {
                    scanPanel
                        .frame(width: 252)

                    VStack(spacing: 10) {
                        networkPanel

                        livePanel

                        folderPanel
                    }
                    .frame(maxWidth: .infinity)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
            }

            statusDot
                .padding(.top, 7)
                .padding(.trailing, 7)
                .ignoresSafeArea(.container, edges: .top)
        }
        .overlay(dropOverlay)
        .onDrop(of: [.fileURL], isTargeted: $isDropTargeted, perform: handleFolderDrop)
        .sheet(isPresented: $isSettingsPresented) {
            ExportSettingsView(exportSettings: $appState.exportSettings)
                .environmentObject(appState)
        }
        .sheet(isPresented: $isCropEditorPresented) {
            ScreenCropEditor()
                .environmentObject(appState)
        }
    }

    private var appBackground: some View {
        AppChromeBackground()
    }

    @ViewBuilder
    private var dropOverlay: some View {
        if isDropTargeted {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(.blue.opacity(0.75), style: StrokeStyle(lineWidth: 2, dash: [7, 6]))
                .background(.blue.opacity(0.08), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .padding(8)
                .allowsHitTesting(false)
        }
    }

    private var titleBar: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 0) {
                Text("Live Loupe")
                    .font(.system(size: 18, weight: .semibold, design: .rounded))

                Text("Artsiom Shabanau  - The Capture Crafter")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            .frame(width: 260, alignment: .leading)

            Spacer(minLength: 12)

            serverControlButton

            iconButton(systemName: "gearshape", accessibilityLabel: "Settings") {
                isSettingsPresented = true
            }
        }
        .padding(.leading, 16)
        .padding(.trailing, 14)
        .padding(.vertical, 10)
    }

    private var previewModePicker: some View {
        HStack(spacing: 0) {
            ForEach(PreviewMode.allCases) { mode in
                SegmentButton(
                    title: mode.title,
                    isSelected: appState.previewMode == mode,
                    helpText: mode.helpText,
                    action: {
                    appState.previewMode = mode
                    appState.refreshScreenCaptureAccess()
                    }
                )
            }
        }
        .segmentedGroupBackground()
    }

    private var statusDot: some View {
        Circle()
            .fill(statusColor)
            .frame(width: 10, height: 10)
            .overlay(Circle().stroke(.white.opacity(0.7), lineWidth: 1))
            .shadow(color: statusColor.opacity(0.28), radius: 5, y: 1)
            .loupeTooltip(appState.status.title)
    }

    private var statusColor: Color {
        switch appState.status {
        case .running:
            .green
        case .starting:
            .orange
        case .failed:
            .red
        case .stopped:
            .secondary
        }
    }

    private var serverControlButton: some View {
        Group {
            if appState.status == .running {
                Button {
                    appState.stop()
                } label: {
                    Image(systemName: "stop.fill")
                        .font(.system(size: 12, weight: .bold))
                        .frame(width: 28, height: 28)
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.white)
                .background(.red, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                .loupeTooltip("Stop the local preview server.")
                .keyboardShortcut(.defaultAction)
            } else {
                Button {
                    appState.start()
                } label: {
                    Image(systemName: appState.status == .starting ? "hourglass" : "play.fill")
                        .font(.system(size: 12, weight: .bold))
                        .frame(width: 28, height: 28)
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.white)
                .background(.blue, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                .opacity(appState.status == .starting ? 0.62 : 1)
                .disabled((appState.previewMode == .export && appState.folderURL == nil) || appState.status == .starting)
                .loupeTooltip(appState.status == .starting ? "Starting the local preview server." : "Start the local preview server and generate a QR code.")
                .keyboardShortcut(.defaultAction)
            }
        }
    }

    private var scanPanel: some View {
        Panel {
            VStack(alignment: .leading, spacing: 12) {
                panelHeader("Scan", detail: scanDetail, systemName: "qrcode.viewfinder")

                qrSurface
                    .frame(maxWidth: .infinity, alignment: .center)

                urlStrip

                HStack(spacing: 8) {
                    actionIconButton(systemName: "doc.on.doc", accessibilityLabel: "Copy URL") {
                        appState.copyURLToPasteboard()
                    }
                    .disabled(appState.localURL == nil)

                    actionIconButton(systemName: "safari", accessibilityLabel: "Test on Mac") {
                        appState.openURLOnMac()
                    }
                    .disabled(appState.localURL == nil)

                    actionIconButton(systemName: "arrow.clockwise", accessibilityLabel: "Restart") {
                        appState.restart()
                    }
                    .disabled(appState.status != .running)
                }

                if case let .failed(message) = appState.status {
                    MessageRow(message: message, systemName: "exclamationmark.triangle.fill", tint: .red)
                }
            }
        }
    }

    private var scanDetail: String {
        switch appState.status {
        case .running:
            appState.previewMode == .screen ? "Screen preview" : "Export preview"
        case .starting:
            "Starting server"
        case .failed:
            "Needs attention"
        case .stopped:
            "Ready to connect"
        }
    }

    @ViewBuilder
    private var qrSurface: some View {
        if let url = appState.localURL {
            QRCodeView(text: url.absoluteString)
                .frame(width: 176, height: 176)
                .padding(12)
                .background(.white, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(.black.opacity(0.06), lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.10), radius: 14, y: 8)
        } else {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(colorScheme == .dark ? Color.white.opacity(0.08) : Color.white.opacity(0.48))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(colorScheme == .dark ? Color.white.opacity(0.12) : Color.white.opacity(0.48), lineWidth: 1)
                    )

                VStack(spacing: 8) {
                    if appState.status == .starting {
                        ProgressView()
                            .controlSize(.large)
                    } else {
                        Image(systemName: "iphone")
                            .font(.system(size: 38, weight: .regular))
                            .symbolRenderingMode(.hierarchical)
                            .foregroundStyle(.secondary)
                    }

                    Text(appState.status == .starting ? "Starting" : "Start to scan")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: 200, height: 200)
        }
    }

    private var urlStrip: some View {
        HStack(spacing: 7) {
            Image(systemName: appState.localURL == nil ? "link" : "safari")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(appState.localURL == nil ? Color(nsColor: .secondaryLabelColor) : Color.blue)

            Text(appState.localURL?.absoluteString ?? "Server URL")
                .font(.system(size: 10.5, weight: .semibold, design: .monospaced))
                .foregroundStyle(appState.localURL == nil ? Color(nsColor: .secondaryLabelColor) : Color.primary)
                .lineLimit(1)
                .truncationMode(.middle)
                .minimumScaleFactor(0.82)
                .allowsTightening(true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .clipped()
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 9)
        .padding(.vertical, 8)
        .fieldBackground()
    }

    private var networkPanel: some View {
        Panel {
            HStack(spacing: 8) {
                inlinePanelHeader("Network", systemName: "antenna.radiowaves.left.and.right")
                    .frame(width: 86, alignment: .leading)

                portField
                    .frame(width: 78)

                addressPicker
            }
        }
    }

    private var portField: some View {
        HStack(spacing: 6) {
            Image(systemName: "number")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)

            TextField("8765", value: $appState.port, format: .number)
                .textFieldStyle(.plain)
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .multilineTextAlignment(.leading)
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 7)
        .fieldBackground()
        .frame(height: 36)
        .disabled(appState.status == .running || appState.status == .starting)
        .loupeTooltip("Local server port. Change it only if another app already uses this port.")
    }

    private var addressPicker: some View {
        HStack(spacing: 6) {
            Image(systemName: "network")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)

            Picker("Address", selection: Binding(
                get: { appState.selectedTargetID ?? "" },
                set: { appState.selectTarget(id: $0) }
            )) {
                ForEach(appState.connectionTargets) { target in
                    Text(target.title)
                        .tag(target.id)
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 9)
        .padding(.vertical, 7)
        .fieldBackground()
        .frame(height: 36)
        .loupeTooltip("Network address encoded into the QR code. The recommended .local address usually works best on iPhone.")
    }

    private var livePanel: some View {
        Panel {
            VStack(alignment: .leading, spacing: 10) {
                panelHeader("Share Settings", detail: liveDetail, systemName: "square.and.arrow.up")

                HStack(spacing: 8) {
                    Text("Share Mode")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.primary)
                        .frame(width: 92, alignment: .leading)

                    Spacer(minLength: 12)

                    previewModePicker
                }
                .controlRow()

                if appState.previewMode == .screen {
                    HStack(spacing: 8) {
                        Text("Stream Profile")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.primary)
                            .frame(width: 92, alignment: .leading)

                        Spacer(minLength: 12)

                        screenPerformancePicker
                    }
                    .controlRow()

                    screenCaptureAccessPanel

                    if appState.screenCaptureAccessGranted {
                        screenCropControls
                    }
                }
            }
        }
    }

    private var liveDetail: String {
        appState.previewMode == .screen ? appState.screenPerformanceMode.title : "Plugin export"
    }

    private var screenPerformancePicker: some View {
        HStack(spacing: 0) {
            ForEach(ScreenPerformanceMode.allCases) { mode in
                SegmentButton(
                    title: mode.title,
                    isSelected: appState.screenPerformanceMode == mode,
                    helpText: mode.helpText,
                    action: { appState.screenPerformanceMode = mode }
                )
            }
        }
        .segmentedGroupBackground()
    }

    @ViewBuilder
    private var screenCaptureAccessPanel: some View {
        if appState.screenCaptureAccessGranted {
            MessageRow(message: "Screen Recording allowed", systemName: "checkmark.circle.fill", tint: .green)
        } else {
            HStack(spacing: 8) {
                Image(systemName: "lock.open.display")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.orange)

                Text("Screen Recording required")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.primary)

                Spacer(minLength: 10)

                Button {
                    appState.requestScreenCaptureAccess()
                } label: {
                    Text("Allow")
                        .font(.system(size: 12, weight: .semibold))
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
            .controlRow()
        }
    }

    private var screenCropControls: some View {
        HStack(spacing: 8) {
            Button {
                isCropEditorPresented = true
            } label: {
                Label(appState.hasScreenCrop ? "Image area" : "Set image area", systemImage: "crop")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)

            if appState.hasScreenCrop {
                iconButton(systemName: "arrow.counterclockwise", accessibilityLabel: "Reset image area") {
                    appState.resetScreenCrop()
                }
            }
        }
        .controlSize(.regular)
    }

    private var folderPanel: some View {
        Panel {
            HStack(spacing: 8) {
                inlinePanelHeader("Folder", systemName: "folder")
                    .frame(width: 74, alignment: .leading)

                folderPathField

                iconButton(systemName: "folder.badge.plus", accessibilityLabel: "Choose Folder") {
                    appState.chooseFolder()
                }
                .loupeTooltip("Choose the folder Lightroom exports JPEG previews into. You can also drop a folder onto the window.")
            }
        }
    }

    private var folderPlaceholder: String {
        appState.previewMode == .screen ? "Optional folder" : "Required folder"
    }

    private var folderPathField: some View {
        HStack(spacing: 7) {
            Image(systemName: "externaldrive")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)

            Text(appState.folderURL?.path ?? "\(folderPlaceholder) · drop here")
                .font(.system(size: 10.5, weight: .medium, design: .monospaced))
                .foregroundStyle(appState.folderURL == nil ? Color(nsColor: .secondaryLabelColor) : Color.primary)
                .lineLimit(1)
                .truncationMode(.middle)
                .minimumScaleFactor(0.82)
                .frame(maxWidth: .infinity, alignment: .leading)
                .clipped()

            Button {
                appState.revealFolder()
            } label: {
                Image(systemName: "arrow.up.forward.app")
                    .font(.system(size: 11, weight: .semibold))
                    .frame(width: 22, height: 22)
            }
            .buttonStyle(.borderless)
            .foregroundStyle(.secondary)
            .opacity(isFolderPathHovering && appState.folderURL != nil ? 1 : 0)
            .disabled(appState.folderURL == nil)
            .loupeTooltip("Reveal in Finder")
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 8)
        .fieldBackground()
        .onHover { isFolderPathHovering = $0 }
        .loupeTooltip("Preview folder. In Export mode Lightroom writes JPEGs here; in Live mode this is optional.")
    }

    private func panelHeader(_ title: String, detail: String, systemName: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: systemName)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.blue)
                .frame(width: 22, height: 22)
                .background(.blue.opacity(0.10), in: RoundedRectangle(cornerRadius: 6, style: .continuous))

            VStack(alignment: .leading, spacing: 0) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))

                Text(detail)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
    }

    private func inlinePanelHeader(_ title: String, systemName: String) -> some View {
        HStack(spacing: 7) {
            Image(systemName: systemName)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.blue)
                .frame(width: 22, height: 22)
                .background(.blue.opacity(0.10), in: RoundedRectangle(cornerRadius: 6, style: .continuous))

            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .lineLimit(1)
        }
    }

    private func iconButton(systemName: String, accessibilityLabel: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 13, weight: .semibold))
                .frame(width: 28, height: 28)
                .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        .foregroundStyle(.primary)
        .iconButtonBackground()
        .accessibilityLabel(accessibilityLabel)
        .loupeTooltip(accessibilityLabel)
    }

    private func actionIconButton(systemName: String, accessibilityLabel: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 12, weight: .semibold))
                .frame(maxWidth: .infinity, minHeight: 30)
                .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        .foregroundStyle(.primary)
        .iconButtonBackground(cornerRadius: 7)
        .accessibilityLabel(accessibilityLabel)
        .loupeTooltip(accessibilityLabel)
    }

    private func handleFolderDrop(_ providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first(where: { $0.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) }) else {
            return false
        }

        provider.loadDataRepresentation(forTypeIdentifier: UTType.fileURL.identifier) { data, _ in
            guard let data,
                  let url = URL(dataRepresentation: data, relativeTo: nil),
                  Self.isDirectory(url) else {
                return
            }

            Task { @MainActor in
                appState.setFolder(url)
            }
        }

        return true
    }

    private nonisolated static func isDirectory(_ url: URL) -> Bool {
        var isDirectory: ObjCBool = false
        return FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) && isDirectory.boolValue
    }
}

private struct ExportSettingsView: View {
    @Binding var exportSettings: ExportSettings
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 1) {
                    Text("Settings")
                        .font(.system(size: 18, weight: .semibold, design: .rounded))

                    Text("Artsiom Shabanau  - The Capture Crafter")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .semibold))
                        .frame(width: 28, height: 28)
                }
                .buttonStyle(.borderless)
                .background(.quaternary, in: Circle())
                .accessibilityLabel("Close")
            }

            SettingsSection(title: "Appearance") {
                appearanceRow
            }

            SettingsSection(title: "Export") {
                settingRow(
                    title: "JPEG Quality",
                    subtitle: "Final preview exports",
                    helpText: "JPEG compression used by the Lightroom plugin for manual/final preview exports. 100 keeps maximum quality."
                ) {
                    numberStepper(value: $exportSettings.jpegQuality, range: 1...100)
                }

                settingRow(
                    title: "Long Edge",
                    subtitle: "Final export size",
                    helpText: "Maximum width or height for exported JPEG previews from the Lightroom plugin."
                ) {
                    numberStepper(value: $exportSettings.longEdgePixels, range: 512...6000, step: 128, suffix: " px", valueWidth: 70)
                }
            }

            SettingsSection(title: "Metadata") {
                toggleRow(
                    title: "Screen sharpening",
                    helpText: "Asks Lightroom to apply screen output sharpening on exported JPEG previews.",
                    isOn: $exportSettings.outputSharpening
                )
                toggleRow(
                    title: "Minimize metadata",
                    helpText: "Keeps exported previews lighter by embedding less metadata.",
                    isOn: $exportSettings.minimizeMetadata
                )
                toggleRow(
                    title: "Remove location",
                    helpText: "Strips GPS/location metadata from exported previews.",
                    isOn: $exportSettings.removeLocationMetadata
                )
            }

            SettingsSection(title: "Lightroom Live Export") {
                settingRow(
                    title: "Long Edge",
                    subtitle: "Live export size",
                    helpText: "Maximum size for Lightroom-plugin live JPEG renders. Lower values render faster."
                ) {
                    numberStepper(value: $exportSettings.livePreviewLongEdge, range: 320...2000, step: 80, suffix: " px", valueWidth: 70)
                }

                settingRow(
                    title: "Quality",
                    subtitle: "Live export compression",
                    helpText: "JPEG quality for Lightroom-plugin live renders. Higher values look cleaner but take longer to export and transfer."
                ) {
                    numberStepper(value: $exportSettings.livePreviewQuality, range: 1...100)
                }
            }
        }
        .padding(16)
        .frame(width: 410)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var appearanceRow: some View {
        HStack(alignment: .center, spacing: 14) {
            VStack(alignment: .leading, spacing: 1) {
                Text("Theme")
                    .font(.system(size: 13, weight: .semibold))

                Text("Default follows macOS")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 16)

            HStack(spacing: 0) {
                ForEach(AppAppearanceMode.allCases) { mode in
                    SegmentButton(
                        title: mode.title,
                        isSelected: appState.appearanceMode == mode,
                        helpText: mode.helpText,
                        action: { appState.appearanceMode = mode }
                    )
                }
            }
            .segmentedGroupBackground()
        }
        .frame(maxWidth: .infinity, minHeight: 30, alignment: .leading)
    }

    private func settingRow<Control: View>(
        title: String,
        subtitle: String,
        helpText: String,
        @ViewBuilder control: () -> Control
    ) -> some View {
        HStack(alignment: .center, spacing: 14) {
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))

                Text(subtitle)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 16)

            control()
                .frame(width: 118, alignment: .trailing)
        }
        .frame(maxWidth: .infinity, minHeight: 30, alignment: .leading)
        .loupeTooltip(helpText)
    }

    private func toggleRow(title: String, subtitle: String? = nil, helpText: String, isOn: Binding<Bool>) -> some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.system(size: 12, weight: .semibold))

                if let subtitle {
                    Text(subtitle)
                        .font(.system(size: 10.5, weight: .medium))
                        .foregroundStyle(.secondary)
                }
            }

            Spacer(minLength: 16)

            Toggle(title, isOn: isOn)
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.small)
        }
        .frame(maxWidth: .infinity, minHeight: 28, alignment: .leading)
        .loupeTooltip(helpText)
    }

    private func numberStepper(
        value: Binding<Int>,
        range: ClosedRange<Int>,
        step: Int = 1,
        suffix: String = "",
        valueWidth: CGFloat = 44
    ) -> some View {
        HStack(spacing: 6) {
            Text("\(value.wrappedValue)\(suffix)")
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .frame(width: valueWidth, alignment: .trailing)

            Stepper("", value: value, in: range, step: step)
                .labelsHidden()
                .controlSize(.small)
                .frame(width: 28)
        }
        .frame(maxWidth: .infinity, alignment: .trailing)
    }
}

private struct SettingsSection<Content: View>: View {
    let title: String
    private let content: Content

    init(title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.system(size: 11.5, weight: .semibold))
                .foregroundStyle(.secondary)

            VStack(spacing: 8) {
                content
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .panelBackground(cornerRadius: 10, shadow: false)
    }
}

private struct Panel<Content: View>: View {
    private let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .panelBackground(cornerRadius: 10, shadow: true)
    }
}

private struct MessageRow: View {
    let message: String
    let systemName: String
    let tint: Color

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: systemName)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(tint)

            Text(message)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.primary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .controlRow()
    }
}

private struct SegmentButton: View {
    let title: String
    let isSelected: Bool
    let helpText: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.86)
                .foregroundStyle(isSelected ? Color.white : Color.primary)
                .padding(.horizontal, 10)
                .frame(minWidth: 58, minHeight: 24)
                .background(
                    isSelected ? Color.blue : Color.clear,
                    in: RoundedRectangle(cornerRadius: 6, style: .continuous)
                )
                .contentShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        }
        .buttonStyle(.plain)
        .loupeTooltip(helpText)
        .accessibilityLabel(title)
    }
}

private struct AppChromeBackground: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ZStack {
            Color(nsColor: .windowBackgroundColor)

            LinearGradient(
                colors: colorScheme == .dark ? darkColors : lightColors,
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
        .ignoresSafeArea()
    }

    private var lightColors: [Color] {
        [
            Color(nsColor: .controlBackgroundColor).opacity(0.9),
            Color(nsColor: .windowBackgroundColor),
            Color(red: 0.95, green: 0.97, blue: 0.98).opacity(0.55),
        ]
    }

    private var darkColors: [Color] {
        [
            Color(red: 0.12, green: 0.12, blue: 0.13),
            Color(red: 0.09, green: 0.10, blue: 0.11),
            Color(red: 0.06, green: 0.07, blue: 0.08),
        ]
    }
}

private struct LoupeTooltipModifier: ViewModifier {
    let text: String

    func body(content: Content) -> some View {
        content
            .overlay(TooltipAnchorView(text: text))
    }
}

private struct TooltipAnchorView: NSViewRepresentable {
    let text: String

    func makeCoordinator() -> Coordinator {
        Coordinator(text: text)
    }

    func makeNSView(context: Context) -> TooltipTrackingView {
        let view = TooltipTrackingView()
        view.coordinator = context.coordinator
        return view
    }

    func updateNSView(_ nsView: TooltipTrackingView, context: Context) {
        context.coordinator.text = text
        nsView.coordinator = context.coordinator
    }

    @MainActor
    final class Coordinator {
        var text: String

        init(text: String) {
            self.text = text
        }

        func mouseEntered(from view: TooltipTrackingView) {
            TooltipPresenter.shared.schedule(text: text, from: view)
        }

        func mouseExited(from view: TooltipTrackingView) {
            TooltipPresenter.shared.hide(for: view)
        }

        func viewDidDetach(_ view: TooltipTrackingView) {
            TooltipPresenter.shared.hide(for: view)
        }
    }
}

private final class TooltipTrackingView: NSView {
    weak var coordinator: TooltipAnchorView.Coordinator?
    private var trackingAreaReference: NSTrackingArea?

    override var isFlipped: Bool {
        true
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        configure()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        configure()
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()

        if let trackingAreaReference {
            removeTrackingArea(trackingAreaReference)
        }

        let options: NSTrackingArea.Options = [
            .mouseEnteredAndExited,
            .activeAlways,
            .inVisibleRect,
        ]
        let trackingArea = NSTrackingArea(rect: .zero, options: options, owner: self, userInfo: nil)
        addTrackingArea(trackingArea)
        trackingAreaReference = trackingArea
    }

    override func mouseEntered(with event: NSEvent) {
        coordinator?.mouseEntered(from: self)
    }

    override func mouseExited(with event: NSEvent) {
        coordinator?.mouseExited(from: self)
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()

        if window == nil {
            coordinator?.viewDidDetach(self)
        }
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        nil
    }

    private func configure() {
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
    }
}

@MainActor
private final class TooltipPresenter {
    static let shared = TooltipPresenter()

    private weak var anchorView: NSView?
    private weak var parentWindow: NSWindow?
    private var panel: NSPanel?
    private var monitorTask: Task<Void, Never>?
    private var pendingTask: Task<Void, Never>?

    func schedule(text: String, from view: NSView) {
        pendingTask?.cancel()
        dismissPanel()

        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedText.isEmpty else {
            anchorView = nil
            return
        }

        anchorView = view
        pendingTask = Task { @MainActor [weak self, weak view] in
            try? await Task.sleep(nanoseconds: 900_000_000)
            guard !Task.isCancelled,
                  let self,
                  let view,
                  self.anchorView === view,
                  self.isMouseInside(view) else {
                return
            }

            self.show(text: trimmedText, from: view)
        }
    }

    func hide(for view: NSView) {
        guard anchorView === view else { return }
        pendingTask?.cancel()
        pendingTask = nil
        dismissPanel()
        anchorView = nil
    }

    private func show(text: String, from view: NSView) {
        guard let window = view.window,
              view.bounds.width > 0,
              view.bounds.height > 0,
              isMouseInside(view) else {
            return
        }

        dismissPanel()

        let screenFrame = window.screen?.visibleFrame ?? NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 320, height: 240)
        let width = min(CGFloat(260), max(CGFloat(180), screenFrame.width - 24))
        let rootView = TooltipBubble(text: text)
            .frame(width: width)
            .fixedSize(horizontal: false, vertical: true)
        let hostingView = NSHostingView(rootView: rootView)
        hostingView.appearance = window.effectiveAppearance
        hostingView.frame = NSRect(x: 0, y: 0, width: width, height: 1000)
        hostingView.layoutSubtreeIfNeeded()

        let fittingSize = hostingView.fittingSize
        let panelSize = NSSize(width: ceil(width), height: ceil(max(24, fittingSize.height)))
        hostingView.frame = NSRect(origin: .zero, size: panelSize)

        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: panelSize),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.appearance = window.effectiveAppearance
        panel.backgroundColor = .clear
        panel.collectionBehavior = [.transient, .ignoresCycle, .fullScreenAuxiliary]
        panel.contentView = hostingView
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.isOpaque = false
        panel.level = .floating
        panel.setFrameOrigin(origin(for: panelSize, anchorView: view, in: window, screenFrame: screenFrame))

        window.addChildWindow(panel, ordered: .above)
        panel.orderFront(nil)

        self.panel = panel
        parentWindow = window
        startMouseMonitor(for: view)
    }

    private func dismissPanel() {
        monitorTask?.cancel()
        monitorTask = nil

        if let panel {
            parentWindow?.removeChildWindow(panel)
            panel.orderOut(nil)
        }

        panel = nil
        parentWindow = nil
    }

    private func startMouseMonitor(for view: NSView) {
        monitorTask?.cancel()
        monitorTask = Task { @MainActor [weak self, weak view] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 120_000_000)
                guard !Task.isCancelled,
                      let self,
                      let view,
                      self.anchorView === view else {
                    return
                }

                if !self.isMouseInside(view) {
                    self.hide(for: view)
                    return
                }
            }
        }
    }

    private func isMouseInside(_ view: NSView) -> Bool {
        guard let window = view.window else { return false }
        let mousePoint = view.convert(window.mouseLocationOutsideOfEventStream, from: nil)
        return view.bounds.insetBy(dx: -2, dy: -2).contains(mousePoint)
    }

    private func origin(for size: NSSize, anchorView: NSView, in window: NSWindow, screenFrame: NSRect) -> NSPoint {
        let anchorWindowRect = anchorView.convert(anchorView.bounds, to: nil)
        let anchorScreenRect = window.convertToScreen(anchorWindowRect)
        let gap = CGFloat(8)
        let margin = CGFloat(10)
        let showBelow = anchorScreenRect.midY > screenFrame.midY
        let proposedX = anchorScreenRect.midX - size.width / 2
        let proposedY = showBelow ? anchorScreenRect.minY - size.height - gap : anchorScreenRect.maxY + gap
        let x = clamp(proposedX, min: screenFrame.minX + margin, max: screenFrame.maxX - size.width - margin)
        let y = clamp(proposedY, min: screenFrame.minY + margin, max: screenFrame.maxY - size.height - margin)

        return NSPoint(x: x.rounded(.toNearestOrAwayFromZero), y: y.rounded(.toNearestOrAwayFromZero))
    }

    private func clamp(_ value: CGFloat, min minValue: CGFloat, max maxValue: CGFloat) -> CGFloat {
        guard maxValue >= minValue else { return value }
        return Swift.min(Swift.max(value, minValue), maxValue)
    }
}

private struct TooltipBubble: View {
    @Environment(\.colorScheme) private var colorScheme
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(.primary)
            .multilineTextAlignment(.leading)
            .lineSpacing(1)
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            .background(fillColor, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .stroke(strokeColor, lineWidth: 1)
            )
            .shadow(color: .black.opacity(colorScheme == .dark ? 0.28 : 0.14), radius: 16, y: 8)
    }

    private var fillColor: Color {
        colorScheme == .dark ? Color.black.opacity(0.24) : Color.white.opacity(0.62)
    }

    private var strokeColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.20) : Color.white.opacity(0.74)
    }
}

private struct SegmentedGroupBackgroundModifier: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: 8, style: .continuous)

        content
            .padding(3)
            .background(fillColor, in: shape)
            .overlay(shape.stroke(strokeColor, lineWidth: 1))
    }

    private var fillColor: Color {
        colorScheme == .dark ? Color.black.opacity(0.20) : Color.white.opacity(0.42)
    }

    private var strokeColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.12) : Color.white.opacity(0.24)
    }
}

private struct PanelBackgroundModifier: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme
    let cornerRadius: CGFloat
    let shadow: Bool

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)

        content
            .background(fillColor, in: shape)
            .background(.thinMaterial, in: shape)
            .overlay(shape.stroke(strokeColor, lineWidth: 1))
            .shadow(
                color: .black.opacity(shadow && colorScheme == .light ? 0.045 : 0),
                radius: shadow ? 10 : 0,
                y: shadow ? 6 : 0
            )
    }

    private var fillColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.055) : Color.white.opacity(0.26)
    }

    private var strokeColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.20) : Color.white.opacity(0.34)
    }
}

private struct FieldBackgroundModifier: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: 7, style: .continuous)

        content
            .frame(height: 36)
            .background(fillColor, in: shape)
            .overlay(shape.stroke(strokeColor, lineWidth: 1))
    }

    private var fillColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.105) : Color.white.opacity(0.42)
    }

    private var strokeColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.16) : Color.white.opacity(0.20)
    }
}

private struct ControlRowModifier: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: 7, style: .continuous)

        content
            .padding(.horizontal, 9)
            .padding(.vertical, 8)
            .background(fillColor, in: shape)
            .overlay(shape.stroke(strokeColor, lineWidth: 1))
    }

    private var fillColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.09) : Color.white.opacity(0.34)
    }

    private var strokeColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.13) : Color.clear
    }
}

private struct IconButtonBackgroundModifier: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme
    let cornerRadius: CGFloat

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)

        content
            .background(fillColor, in: shape)
            .overlay(shape.stroke(strokeColor, lineWidth: 1))
    }

    private var fillColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.13) : Color.white.opacity(0.42)
    }

    private var strokeColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.22) : Color.white.opacity(0.4)
    }
}

private extension View {
    func loupeTooltip(_ text: String) -> some View {
        modifier(LoupeTooltipModifier(text: text))
    }

    func segmentedGroupBackground() -> some View {
        modifier(SegmentedGroupBackgroundModifier())
    }

    func panelBackground(cornerRadius: CGFloat, shadow: Bool) -> some View {
        modifier(PanelBackgroundModifier(cornerRadius: cornerRadius, shadow: shadow))
    }

    func fieldBackground() -> some View {
        modifier(FieldBackgroundModifier())
    }

    func controlRow() -> some View {
        modifier(ControlRowModifier())
    }

    func iconButtonBackground(cornerRadius: CGFloat = 7) -> some View {
        modifier(IconButtonBackgroundModifier(cornerRadius: cornerRadius))
    }
}
