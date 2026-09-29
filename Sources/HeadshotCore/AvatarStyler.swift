import CoreImage
import CoreImage.CIFilterBuiltins

/// Stylized avatar looks made from a finished headshot with Core Image filters.
public enum AvatarStyle: String, CaseIterable, Identifiable, Sendable {
    case cartoon = "Cartoon"
    case popArt = "Pop Art"
    case sketch = "Pencil Sketch"
    case duotone = "Duotone"
    case halftone = "Halftone"
    case pixel = "Pixel"
    public var id: String { rawValue }
}

public enum AvatarStyler {
    /// Avatars are always rendered at this square size so filter parameters behave the same for every photo.
    public static let size: CGFloat = 1024

    /// Centre-crops to a square and scales to `size`.
    public static func normalize(_ image: CIImage) -> CIImage {
        let e = image.extent
        let side = min(e.width, e.height)
        let square = image.cropped(to: CGRect(x: e.midX - side / 2, y: e.midY - side / 2, width: side, height: side))
        let s = size / side
        return square
            .transformed(by: .init(translationX: -square.extent.minX, y: -square.extent.minY))
            .transformed(by: .init(scaleX: s, y: s))
            .cropped(to: CGRect(x: 0, y: 0, width: size, height: size))
    }

    public static func apply(_ style: AvatarStyle, to headshot: CIImage) -> CIImage {
        let img = normalize(headshot)
        let extent = img.extent
        let out: CIImage?

        switch style {
        case .cartoon:
            let flat = img.applyingFilter("CIMedianFilter").applyingFilter("CIMedianFilter")
            let poster = CIFilter.colorPosterize(); poster.inputImage = flat; poster.levels = 7
            let lines = CIFilter.lineOverlay(); lines.inputImage = img
            lines.nrNoiseLevel = 0.03; lines.nrSharpness = 0.6
            lines.edgeIntensity = 1.2; lines.threshold = 0.25; lines.contrast = 40
            out = lines.outputImage?.composited(over: poster.outputImage ?? flat)

        case .popArt:
            let boost = CIFilter.colorControls(); boost.inputImage = img
            boost.saturation = 2.2; boost.contrast = 1.3
            let poster = CIFilter.colorPosterize(); poster.inputImage = boost.outputImage; poster.levels = 4
            out = poster.outputImage

        case .sketch:
            // Classic dodge sketch: grey, inverted + blurred copy colour-dodged onto itself.
            let gray = img.applyingFilter("CIPhotoEffectNoir")
            let inverted = gray.applyingFilter("CIColorInvert")
                .clampedToExtent().applyingGaussianBlur(sigma: 12).cropped(to: extent)
            let dodge = CIFilter.colorDodgeBlendMode(); dodge.inputImage = inverted; dodge.backgroundImage = gray
            let tone = CIFilter.gammaAdjust(); tone.inputImage = dodge.outputImage; tone.power = 3
            out = tone.outputImage

        case .duotone:
            let punch = CIFilter.colorControls(); punch.inputImage = img; punch.contrast = 1.35
            let f = CIFilter.falseColor(); f.inputImage = punch.outputImage
            f.color0 = CIColor(red: 0.10, green: 0.12, blue: 0.35)
            f.color1 = CIColor(red: 1.00, green: 0.78, blue: 0.62)
            out = f.outputImage

        case .halftone:
            let f = CIFilter.cmykHalftone(); f.inputImage = img
            f.width = 10; f.sharpness = 0.7; f.center = CGPoint(x: extent.midX, y: extent.midY)
            out = f.outputImage

        case .pixel:
            let f = CIFilter.pixellate(); f.inputImage = img
            f.scale = Float(size / 40); f.center = CGPoint(x: extent.midX, y: extent.midY)
            out = f.outputImage
        }
        return (out ?? img).cropped(to: extent)
    }

    /// Puts the avatar in a circle with a transparent surround — the usual profile-picture shape.
    public static func circular(_ image: CIImage) -> CIImage {
        let e = image.extent
        let r = min(e.width, e.height) / 2
        let f = CIFilter.radialGradient()
        f.center = CGPoint(x: e.midX, y: e.midY)
        f.radius0 = Float(r - 1.5); f.radius1 = Float(r)
        f.color0 = .white; f.color1 = CIColor(red: 0, green: 0, blue: 0, alpha: 0)
        let mask = f.outputImage!.cropped(to: e)
        let blend = CIFilter.blendWithAlphaMask()
        blend.inputImage = image; blend.backgroundImage = CIImage.empty(); blend.maskImage = mask
        return (blend.outputImage ?? image).cropped(to: e)
    }
}
