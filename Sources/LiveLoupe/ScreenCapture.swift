import CoreGraphics
import Foundation
import ImageIO
import ScreenCaptureKit
import UniformTypeIdentifiers

struct ScreenCaptureResult {
    let data: Data
    let windowTitle: String
    let mode: ScreenPerformanceMode
    let pixelWidth: Int
    let pixelHeight: Int
    let captureMilliseconds: Double
    let encodeMilliseconds: Double
    let signature: UInt64
}

enum ScreenCaptureError: LocalizedError {
    case permissionDenied
    case lightroomWindowNotFound
    case captureFailed
    case encodeFailed

    var errorDescription: String? {
        switch self {
        case .permissionDenied:
            "Screen Recording permission is required for Screen Live."
        case .lightroomWindowNotFound:
            "Lightroom window was not found."
        case .captureFailed:
            "Could not capture the Lightroom window."
        case .encodeFailed:
            "Could not encode the screen preview."
        }
    }
}

struct ScreenPreview: Sendable {
    let data: Data
    let pixelWidth: Int
    let pixelHeight: Int
}

enum LightroomScreenCapture {
    /// Normalized crop rectangle (origin top-left, values 0...1) within the
    /// captured Lightroom window. Full window = (0, 0, 1, 1).
    static let fullCropRect = CGRect(x: 0, y: 0, width: 1, height: 1)
    private static let cropRectKey = "screen.cropRect"
    private static let targetCache = ScreenCaptureTargetCache()

    static func currentCropRect() -> CGRect {
        guard let values = UserDefaults.standard.array(forKey: cropRectKey) as? [Double],
              values.count == 4 else {
            return fullCropRect
        }
        let rect = CGRect(x: values[0], y: values[1], width: values[2], height: values[3])
        guard rect.width > 0.01, rect.height > 0.01 else {
            return fullCropRect
        }
        return rect
    }

    static func saveCropRect(_ rect: CGRect) {
        if rect == fullCropRect {
            UserDefaults.standard.removeObject(forKey: cropRectKey)
        } else {
            UserDefaults.standard.set(
                [Double(rect.minX), Double(rect.minY), Double(rect.width), Double(rect.height)],
                forKey: cropRectKey
            )
        }
    }

    static var hasAccess: Bool {
        CGPreflightScreenCaptureAccess()
    }

    @discardableResult
    static func requestAccess() -> Bool {
        CGRequestScreenCaptureAccess()
    }

    /// Captures one uncropped JPEG frame of the Lightroom window for the crop
    /// editor. Returns JPEG bytes (Sendable) so the image can be built on the
    /// main actor without crossing concurrency boundaries with NSImage.
    static func capturePreview() async throws -> ScreenPreview {
        guard hasAccess else {
            throw ScreenCaptureError.permissionDenied
        }
        let target = try await captureTarget(forceRefresh: true)
        let image = try await captureWindowImage(target)
        let data = try encodeJPEG(image, quality: 0.9)
        return ScreenPreview(
            data: data,
            pixelWidth: image.width,
            pixelHeight: image.height
        )
    }

    static func captureJPEG(mode: ScreenPerformanceMode = ScreenPerformanceMode.current) throws -> ScreenCaptureResult {
        let semaphore = DispatchSemaphore(value: 0)
        final class CaptureBox: @unchecked Sendable {
            var result: Result<ScreenCaptureResult, Error>?
        }

        let box = CaptureBox()
        Task {
            do {
                box.result = .success(try await captureJPEGAsync(mode: mode))
            } catch {
                box.result = .failure(error)
            }
            semaphore.signal()
        }

        semaphore.wait()
        if let result = box.result {
            return try result.get()
        }

        throw ScreenCaptureError.captureFailed
    }

    private static func captureJPEGAsync(mode: ScreenPerformanceMode) async throws -> ScreenCaptureResult {
        guard hasAccess else {
            throw ScreenCaptureError.permissionDenied
        }

        let captureStart = Date()
        let fullImage = try await captureCurrentWindowImage()
        let croppedImage = cropImage(fullImage, to: currentCropRect())
        let image = resizeImage(croppedImage, maxLongEdge: mode.maxLongEdge)
        let captureElapsed = Date().timeIntervalSince(captureStart) * 1000

        let encodeStart = Date()
        let data = try encodeJPEG(image, quality: mode.jpegQuality)
        let encodeElapsed = Date().timeIntervalSince(encodeStart) * 1000

        return ScreenCaptureResult(
            data: data,
            windowTitle: targetCache.currentTitle ?? "Lightroom",
            mode: mode,
            pixelWidth: image.width,
            pixelHeight: image.height,
            captureMilliseconds: captureElapsed,
            encodeMilliseconds: encodeElapsed,
            signature: frameSignature(data)
        )
    }

    private static func captureCurrentWindowImage() async throws -> CGImage {
        let target = try await captureTarget()
        do {
            return try await captureWindowImage(target)
        } catch {
            targetCache.invalidate()
            return try await captureWindowImage(try await captureTarget(forceRefresh: true))
        }
    }

    private static func captureWindowImage(_ target: ScreenCaptureTarget) async throws -> CGImage {
        return try await SCScreenshotManager.captureImage(
            contentFilter: target.filter,
            configuration: target.configuration
        )
    }

    /// Crops the captured window image to the user-selected image area. `crop` is
    /// normalized (origin top-left, 0...1), matching CGImage's top-left origin.
    private static func cropImage(_ image: CGImage, to crop: CGRect) -> CGImage {
        guard crop != fullCropRect else {
            return image
        }

        let width = CGFloat(image.width)
        let height = CGFloat(image.height)
        let rect = CGRect(
            x: crop.minX * width,
            y: crop.minY * height,
            width: crop.width * width,
            height: crop.height * height
        )
        .integral
        .intersection(CGRect(x: 0, y: 0, width: width, height: height))

        guard !rect.isNull, rect.width >= 1, rect.height >= 1,
              let cropped = image.cropping(to: rect) else {
            return image
        }

        return cropped
    }

    private static func resizeImage(_ image: CGImage, maxLongEdge: Int?) -> CGImage {
        guard let maxLongEdge, max(image.width, image.height) > maxLongEdge else {
            return image
        }

        let scale = CGFloat(maxLongEdge) / CGFloat(max(image.width, image.height))
        let width = max(Int((CGFloat(image.width) * scale).rounded()), 1)
        let height = max(Int((CGFloat(image.height) * scale).rounded()), 1)
        let colorSpace = image.colorSpace ?? CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue

        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: bitmapInfo
        ) else {
            return image
        }

        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage() ?? image
    }

    private static func captureTarget(forceRefresh: Bool = false) async throws -> ScreenCaptureTarget {
        if !forceRefresh, let target = targetCache.target(maxAge: 10) {
            return target
        }

        let window = try await findLightroomWindow()
        let filter = SCContentFilter(desktopIndependentWindow: window)
        let configuration = SCStreamConfiguration()
        configuration.capturesAudio = false
        configuration.showsCursor = false
        let pixelScale = CGFloat(filter.pointPixelScale)
        configuration.width = max(Int(filter.contentRect.width * pixelScale), 1)
        configuration.height = max(Int(filter.contentRect.height * pixelScale), 1)

        let target = ScreenCaptureTarget(
            filter: filter,
            configuration: configuration,
            title: window.displayTitle,
            createdAt: Date()
        )
        targetCache.store(target)
        return target
    }

    private static func findLightroomWindow() async throws -> SCWindow {
        let content = try await SCShareableContent.excludingDesktopWindows(
            false,
            onScreenWindowsOnly: true
        )

        let candidates = content.windows.filter { window in
            let appName = window.owningApplication?.applicationName.lowercased() ?? ""
            let bundleID = window.owningApplication?.bundleIdentifier.lowercased() ?? ""
            let title = window.title?.lowercased() ?? ""

            return window.frame.width >= 600
                && window.frame.height >= 400
                && (
                    appName.contains("lightroom")
                    || bundleID.contains("lightroom")
                    || title.contains("lightroom")
                )
        }

        guard let window = candidates.max(by: { $0.frame.area < $1.frame.area }) else {
            throw ScreenCaptureError.lightroomWindowNotFound
        }

        return window
    }

    private static func frameSignature(_ data: Data) -> UInt64 {
        var hash: UInt64 = 14_695_981_039_346_656_037
        let step = max(data.count / 2_048, 1)

        for index in Swift.stride(from: 0, to: data.count, by: step) {
            hash ^= UInt64(data[index])
            hash &*= 1_099_511_628_211
        }

        hash ^= UInt64(data.count)
        hash &*= 1_099_511_628_211
        return hash
    }

    private static func encodeJPEG(_ image: CGImage, quality: CGFloat) throws -> Data {
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            data,
            UTType.jpeg.identifier as CFString,
            1,
            nil
        ) else {
            throw ScreenCaptureError.encodeFailed
        }

        let options = [
            kCGImageDestinationLossyCompressionQuality: min(max(quality, 0.1), 1.0)
        ] as CFDictionary
        CGImageDestinationAddImage(destination, image, options)

        guard CGImageDestinationFinalize(destination) else {
            throw ScreenCaptureError.encodeFailed
        }

        return data as Data
    }
}

private struct ScreenCaptureTarget: @unchecked Sendable {
    let filter: SCContentFilter
    let configuration: SCStreamConfiguration
    let title: String
    let createdAt: Date
}

private final class ScreenCaptureTargetCache: @unchecked Sendable {
    private let lock = NSLock()
    private var cachedTarget: ScreenCaptureTarget?

    var currentTitle: String? {
        lock.lock()
        defer { lock.unlock() }
        return cachedTarget?.title
    }

    func target(maxAge: TimeInterval) -> ScreenCaptureTarget? {
        lock.lock()
        defer { lock.unlock() }

        guard let cachedTarget,
              Date().timeIntervalSince(cachedTarget.createdAt) <= maxAge else {
            return nil
        }

        return cachedTarget
    }

    func store(_ target: ScreenCaptureTarget) {
        lock.lock()
        cachedTarget = target
        lock.unlock()
    }

    func invalidate() {
        lock.lock()
        cachedTarget = nil
        lock.unlock()
    }
}

private extension CGRect {
    var area: CGFloat {
        width * height
    }
}

private extension SCWindow {
    var displayTitle: String {
        let appName = owningApplication?.applicationName ?? "Lightroom"
        guard let title, !title.isEmpty else {
            return appName
        }

        return "\(appName) - \(title)"
    }
}
