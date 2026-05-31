import CoreGraphics
import Foundation

enum ScreenPerformanceMode: String, CaseIterable, Identifiable, Codable, Sendable {
    case quality
    case balanced
    case battery

    static let defaultsKey = "screen.performanceMode"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .quality:
            "Quality"
        case .balanced:
            "Balanced"
        case .battery:
            "Battery"
        }
    }

    var helpText: String {
        switch self {
        case .quality:
            "Highest live-screen fidelity and fastest polling. Uses more CPU, network, and battery."
        case .balanced:
            "Recommended live-screen profile: sharp iPhone preview with lower CPU and battery use."
        case .battery:
            "Lower resolution and slower updates to reduce CPU, network traffic, and iPhone battery drain."
        }
    }

    var jpegQuality: CGFloat {
        switch self {
        case .quality:
            0.92
        case .balanced:
            0.84
        case .battery:
            0.72
        }
    }

    var maxLongEdge: Int? {
        switch self {
        case .quality:
            nil
        case .balanced:
            2_200
        case .battery:
            1_600
        }
    }

    var activeDelayMilliseconds: Int {
        switch self {
        case .quality:
            70
        case .balanced:
            120
        case .battery:
            450
        }
    }

    var idleDelayMilliseconds: Int {
        switch self {
        case .quality:
            550
        case .balanced:
            650
        case .battery:
            2_000
        }
    }

    var idleAfterMilliseconds: Int {
        switch self {
        case .quality:
            2_200
        case .balanced:
            2_400
        case .battery:
            1_000
        }
    }

    static var current: ScreenPerformanceMode {
        guard let rawValue = UserDefaults.standard.string(forKey: defaultsKey),
              let mode = ScreenPerformanceMode(rawValue: rawValue) else {
            return .balanced
        }

        return mode
    }

    static func save(_ mode: ScreenPerformanceMode) {
        UserDefaults.standard.set(mode.rawValue, forKey: defaultsKey)
    }
}

struct ScreenRuntimeConfig: Codable {
    let mode: ScreenPerformanceMode
    let title: String
    let activeDelayMilliseconds: Int
    let idleDelayMilliseconds: Int
    let idleAfterMilliseconds: Int
    let maxLongEdge: Int?
    let jpegQuality: Double

    init(mode: ScreenPerformanceMode) {
        self.mode = mode
        title = mode.title
        activeDelayMilliseconds = mode.activeDelayMilliseconds
        idleDelayMilliseconds = mode.idleDelayMilliseconds
        idleAfterMilliseconds = mode.idleAfterMilliseconds
        maxLongEdge = mode.maxLongEdge
        jpegQuality = Double(mode.jpegQuality)
    }
}
