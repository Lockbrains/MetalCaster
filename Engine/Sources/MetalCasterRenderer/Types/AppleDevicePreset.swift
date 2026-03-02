import Foundation
import CoreGraphics

// MARK: - Device Category

public enum AppleDeviceCategory: String, CaseIterable, Codable, Sendable, Identifiable {
    case iPhone  = "iPhone"
    case iPad    = "iPad"
    case mac     = "Mac"
    case appleTV = "Apple TV"
    case vision  = "Apple Vision Pro"

    public var id: String { rawValue }

    public var icon: String {
        switch self {
        case .iPhone:  return "iphone"
        case .iPad:    return "ipad"
        case .mac:     return "desktopcomputer"
        case .appleTV: return "appletv"
        case .vision:  return "visionpro"
        }
    }
}

// MARK: - Apple Device Preset

public struct AppleDevicePreset: Identifiable, Hashable, Codable, Sendable {
    public let id: String
    public let name: String
    public let category: AppleDeviceCategory
    public let widthPx: Int
    public let heightPx: Int
    public let scaleFactor: Int

    public var pointWidth: Int { widthPx / scaleFactor }
    public var pointHeight: Int { heightPx / scaleFactor }
    public var aspectRatio: Float { Float(widthPx) / Float(heightPx) }
    public var resolution: CGSize { CGSize(width: widthPx, height: heightPx) }
    public var displayString: String { "\(widthPx) x \(heightPx)" }

    public init(id: String, name: String, category: AppleDeviceCategory, widthPx: Int, heightPx: Int, scaleFactor: Int) {
        self.id = id
        self.name = name
        self.category = category
        self.widthPx = widthPx
        self.heightPx = heightPx
        self.scaleFactor = scaleFactor
    }
}

// MARK: - Preset Catalog

extension AppleDevicePreset {

    public static let allPresets: [AppleDevicePreset] = iPhonePresets + iPadPresets + macPresets + appleTVPresets + visionPresets

    public static func presets(for category: AppleDeviceCategory) -> [AppleDevicePreset] {
        allPresets.filter { $0.category == category }
    }

    // MARK: iPhone

    public static let iPhonePresets: [AppleDevicePreset] = [
        .init(id: "iphone16promax", name: "iPhone 16 Pro Max", category: .iPhone, widthPx: 2868, heightPx: 1320, scaleFactor: 3),
        .init(id: "iphone16pro",    name: "iPhone 16 Pro",     category: .iPhone, widthPx: 2622, heightPx: 1206, scaleFactor: 3),
        .init(id: "iphone16plus",   name: "iPhone 16 Plus",    category: .iPhone, widthPx: 2796, heightPx: 1290, scaleFactor: 3),
        .init(id: "iphone16",       name: "iPhone 16",         category: .iPhone, widthPx: 2556, heightPx: 1179, scaleFactor: 3),
        .init(id: "iphone16e",      name: "iPhone 16e",        category: .iPhone, widthPx: 2556, heightPx: 1179, scaleFactor: 3),
        .init(id: "iphone15promax", name: "iPhone 15 Pro Max", category: .iPhone, widthPx: 2796, heightPx: 1290, scaleFactor: 3),
        .init(id: "iphone15pro",    name: "iPhone 15 Pro",     category: .iPhone, widthPx: 2556, heightPx: 1179, scaleFactor: 3),
        .init(id: "iphone15plus",   name: "iPhone 15 Plus",    category: .iPhone, widthPx: 2796, heightPx: 1290, scaleFactor: 3),
        .init(id: "iphone15",       name: "iPhone 15",         category: .iPhone, widthPx: 2556, heightPx: 1179, scaleFactor: 3),
        .init(id: "iphonese4",      name: "iPhone SE (4th)",   category: .iPhone, widthPx: 2556, heightPx: 1179, scaleFactor: 3),
    ]

    // MARK: iPad

    public static let iPadPresets: [AppleDevicePreset] = [
        .init(id: "ipadpro13m4",  name: "iPad Pro 13\" (M4)",  category: .iPad, widthPx: 2752, heightPx: 2064, scaleFactor: 2),
        .init(id: "ipadpro11m4",  name: "iPad Pro 11\" (M4)",  category: .iPad, widthPx: 2420, heightPx: 1668, scaleFactor: 2),
        .init(id: "ipadair13m3",  name: "iPad Air 13\" (M3)",  category: .iPad, widthPx: 2732, heightPx: 2048, scaleFactor: 2),
        .init(id: "ipadair11m3",  name: "iPad Air 11\" (M3)",  category: .iPad, widthPx: 2360, heightPx: 1640, scaleFactor: 2),
        .init(id: "ipadmini7",    name: "iPad mini (7th)",     category: .iPad, widthPx: 2266, heightPx: 1488, scaleFactor: 2),
        .init(id: "ipad10",       name: "iPad (10th gen)",     category: .iPad, widthPx: 2360, heightPx: 1640, scaleFactor: 2),
    ]

    // MARK: Mac

    public static let macPresets: [AppleDevicePreset] = [
        .init(id: "macbookair13",    name: "MacBook Air 13\"",          category: .mac, widthPx: 2560, heightPx: 1664, scaleFactor: 2),
        .init(id: "macbookair15",    name: "MacBook Air 15\"",          category: .mac, widthPx: 2880, heightPx: 1864, scaleFactor: 2),
        .init(id: "macbookpro14",    name: "MacBook Pro 14\"",          category: .mac, widthPx: 3024, heightPx: 1964, scaleFactor: 2),
        .init(id: "macbookpro16",    name: "MacBook Pro 16\"",          category: .mac, widthPx: 3456, heightPx: 2234, scaleFactor: 2),
        .init(id: "imac24",          name: "iMac 24\"",                 category: .mac, widthPx: 4480, heightPx: 2520, scaleFactor: 2),
        .init(id: "studiodisplay",   name: "Apple Studio Display",      category: .mac, widthPx: 5120, heightPx: 2880, scaleFactor: 2),
        .init(id: "proxdr",          name: "Apple Pro Display XDR",     category: .mac, widthPx: 6016, heightPx: 3384, scaleFactor: 2),
    ]

    // MARK: Apple TV

    public static let appleTVPresets: [AppleDevicePreset] = [
        .init(id: "appletv4k",  name: "Apple TV 4K",  category: .appleTV, widthPx: 3840, heightPx: 2160, scaleFactor: 1),
        .init(id: "appletvhd",  name: "Apple TV HD",   category: .appleTV, widthPx: 1920, heightPx: 1080, scaleFactor: 1),
    ]

    // MARK: Apple Vision Pro

    public static let visionPresets: [AppleDevicePreset] = [
        .init(id: "visionpro", name: "Apple Vision Pro (per eye)", category: .vision, widthPx: 3660, heightPx: 3200, scaleFactor: 1),
    ]
}

// MARK: - Render Target Configuration

/// Project-level render target configuration. All cameras share this output resolution.
public struct RenderTargetConfig: Codable, Sendable, Equatable {
    public enum Mode: String, Codable, Sendable {
        case devicePreset
        case custom
    }

    public var mode: Mode
    public var presetID: String?
    public var customWidth: Int
    public var customHeight: Int
    public var isLandscape: Bool

    public init(
        mode: Mode = .devicePreset,
        presetID: String? = "iphone16pro",
        customWidth: Int = 1920,
        customHeight: Int = 1080,
        isLandscape: Bool = true
    ) {
        self.mode = mode
        self.presetID = presetID
        self.customWidth = customWidth
        self.customHeight = customHeight
        self.isLandscape = isLandscape
    }

    public var resolvedSize: CGSize {
        switch mode {
        case .devicePreset:
            guard let id = presetID,
                  let preset = AppleDevicePreset.allPresets.first(where: { $0.id == id }) else {
                return CGSize(width: 1920, height: 1080)
            }
            let w = preset.widthPx
            let h = preset.heightPx
            if isLandscape {
                return CGSize(width: max(w, h), height: min(w, h))
            } else {
                return CGSize(width: min(w, h), height: max(w, h))
            }
        case .custom:
            if isLandscape {
                return CGSize(width: max(customWidth, customHeight), height: min(customWidth, customHeight))
            } else {
                return CGSize(width: min(customWidth, customHeight), height: max(customWidth, customHeight))
            }
        }
    }

    public var resolvedPreset: AppleDevicePreset? {
        guard mode == .devicePreset, let id = presetID else { return nil }
        return AppleDevicePreset.allPresets.first { $0.id == id }
    }

    public var aspectRatio: Float {
        let size = resolvedSize
        return Float(size.width / size.height)
    }

    public var displayString: String {
        let size = resolvedSize
        return "\(Int(size.width)) x \(Int(size.height))"
    }
}
