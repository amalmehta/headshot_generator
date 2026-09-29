import CoreGraphics

/// How the area behind the person is treated.
public enum BackgroundStyle: String, CaseIterable, Identifiable, Sendable {
    case original = "Original"
    case blur = "Blur"
    case solid = "Solid"
    case gradient = "Studio gradient"
    public var id: String { rawValue }
}

/// Output framing.
public enum CropAspect: String, CaseIterable, Identifiable, Sendable {
    case square = "Square 1:1"
    case portrait = "Portrait 4:5"
    case original = "Uncropped"
    public var id: String { rawValue }

    /// width / height, or nil for "keep the whole image".
    public var ratio: CGFloat? {
        switch self {
        case .square: return 1
        case .portrait: return 0.8
        case .original: return nil
        }
    }
}

public struct RGBColor: Equatable, Sendable {
    public var r, g, b: Double
    public init(r: Double, g: Double, b: Double) { self.r = r; self.g = g; self.b = b }

    public static let studioGray = RGBColor(r: 0.78, g: 0.80, b: 0.83)
}

public struct HeadshotSettings: Equatable, Sendable {
    public var background: BackgroundStyle = .gradient
    public var backgroundColor: RGBColor = .studioGray
    /// Blur radius as a fraction of the image's short side.
    public var backgroundBlur: Double = 0.03
    public var crop: CropAspect = .square
    public var autoEnhance = true
    /// Exposure in EV stops, -1...1.
    public var exposure: Double = 0
    /// 0.75...1.25, 1 = unchanged.
    public var contrast: Double = 1
    /// 0...2, 1 = unchanged.
    public var saturation: Double = 1
    /// -1 (cooler) ... 1 (warmer).
    public var warmth: Double = 0
    /// Edge-preserving skin smoothing, 0...1.
    public var smoothing: Double = 0.3

    public init() {}
}
