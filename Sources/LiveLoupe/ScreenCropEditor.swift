import AppKit
import SwiftUI

/// Lets the user draw the photo area inside a snapshot of the Lightroom window.
/// The selection is stored normalized (0...1) and applied to the live stream.
struct ScreenCropEditor: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss

    @State private var snapshot: NSImage?
    @State private var pixelSize: CGSize = .zero
    @State private var draft = LightroomScreenCapture.fullCropRect
    @State private var dragStart: CGPoint?
    @State private var isLoading = true
    @State private var loadError: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
            previewArea
            footer
        }
        .padding(20)
        .frame(width: 680, height: 600)
        .onAppear {
            draft = appState.screenCropRect
            reloadSnapshot()
        }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Set Image Area")
                    .font(.system(size: 20, weight: .semibold, design: .rounded))
                Text("Drag a rectangle around the photo in Lightroom. Only that area is streamed to the iPhone.")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer()

            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 13, weight: .semibold))
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(.borderless)
            .background(.quaternary, in: Circle())
            .accessibilityLabel("Close")
        }
    }

    private var previewArea: some View {
        GeometryReader { geo in
            let frame = Self.imageFrame(in: geo.size, pixelSize: pixelSize)

            ZStack {
                Rectangle().fill(.black.opacity(0.001)) // ensures the whole area is hit-testable

                if let snapshot {
                    Image(nsImage: snapshot)
                        .resizable()
                        .interpolation(.medium)
                        .scaledToFit()
                }

                if pixelSize.width > 0, snapshot != nil {
                    let selection = Self.denormalize(draft, in: frame)

                    Path { path in
                        path.addRect(frame)
                        path.addRect(selection)
                    }
                    .fill(.black.opacity(0.5), style: FillStyle(eoFill: true))

                    Rectangle()
                        .strokeBorder(Color.accentColor, lineWidth: 2)
                        .frame(width: max(selection.width, 0), height: max(selection.height, 0))
                        .position(x: selection.midX, y: selection.midY)
                }

                if isLoading {
                    ProgressView()
                } else if let loadError {
                    Text(loadError)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(28)
                }
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 2)
                    .onChanged { value in
                        guard pixelSize.width > 0, frame.width > 0 else { return }
                        let start = dragStart ?? Self.clamp(value.startLocation, to: frame)
                        if dragStart == nil { dragStart = start }
                        let current = Self.clamp(value.location, to: frame)
                        let rect = CGRect(
                            x: min(start.x, current.x),
                            y: min(start.y, current.y),
                            width: abs(current.x - start.x),
                            height: abs(current.y - start.y)
                        )
                        draft = Self.normalize(rect, in: frame)
                    }
                    .onEnded { _ in dragStart = nil }
            )
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .windowBackgroundColor).opacity(0.5))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var footer: some View {
        HStack(spacing: 10) {
            Button {
                reloadSnapshot()
            } label: {
                Label("Recapture", systemImage: "arrow.clockwise")
            }

            Button {
                draft = LightroomScreenCapture.fullCropRect
            } label: {
                Label("Whole window", systemImage: "rectangle.dashed")
            }

            Spacer()

            Button("Cancel") {
                dismiss()
            }

            Button("Save") {
                appState.screenCropRect = sanitized(draft)
                dismiss()
            }
            .keyboardShortcut(.defaultAction)
            .buttonStyle(.borderedProminent)
        }
    }

    private func sanitized(_ rect: CGRect) -> CGRect {
        guard rect.width >= 0.03, rect.height >= 0.03 else {
            return LightroomScreenCapture.fullCropRect
        }
        return CGRect(
            x: min(max(rect.minX, 0), 1),
            y: min(max(rect.minY, 0), 1),
            width: min(rect.width, 1 - min(max(rect.minX, 0), 1)),
            height: min(rect.height, 1 - min(max(rect.minY, 0), 1))
        )
    }

    private func reloadSnapshot() {
        isLoading = true
        loadError = nil
        Task {
            if let preview = await appState.captureScreenPreview(),
               let image = NSImage(data: preview.data) {
                snapshot = image
                pixelSize = CGSize(width: preview.pixelWidth, height: preview.pixelHeight)
                isLoading = false
            } else {
                isLoading = false
                loadError = "Could not capture Lightroom. Open it (in the Develop module) and allow Screen Recording, then Recapture."
            }
        }
    }

    // MARK: - Geometry

    /// The aspect-fit frame the image occupies inside `container`.
    static func imageFrame(in container: CGSize, pixelSize: CGSize) -> CGRect {
        guard pixelSize.width > 0, pixelSize.height > 0, container.width > 0, container.height > 0 else {
            return CGRect(origin: .zero, size: container)
        }
        let scale = min(container.width / pixelSize.width, container.height / pixelSize.height)
        let width = pixelSize.width * scale
        let height = pixelSize.height * scale
        return CGRect(
            x: (container.width - width) / 2,
            y: (container.height - height) / 2,
            width: width,
            height: height
        )
    }

    static func clamp(_ point: CGPoint, to frame: CGRect) -> CGPoint {
        CGPoint(
            x: min(max(point.x, frame.minX), frame.maxX),
            y: min(max(point.y, frame.minY), frame.maxY)
        )
    }

    static func normalize(_ rect: CGRect, in frame: CGRect) -> CGRect {
        guard frame.width > 0, frame.height > 0 else { return LightroomScreenCapture.fullCropRect }
        return CGRect(
            x: (rect.minX - frame.minX) / frame.width,
            y: (rect.minY - frame.minY) / frame.height,
            width: rect.width / frame.width,
            height: rect.height / frame.height
        )
    }

    static func denormalize(_ norm: CGRect, in frame: CGRect) -> CGRect {
        CGRect(
            x: frame.minX + norm.minX * frame.width,
            y: frame.minY + norm.minY * frame.height,
            width: norm.width * frame.width,
            height: norm.height * frame.height
        )
    }
}
