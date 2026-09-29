import CoreImage
import CoreImage.CIFilterBuiltins
import ImageIO
import UniformTypeIdentifiers
import Vision

/// Everything Vision tells us about a photo. Computed once per photo; rendering
/// with different settings reuses it.
public struct PhotoAnalysis: @unchecked Sendable {
    /// The photo, orientation applied, extent at the origin.
    public let image: CIImage
    /// Largest detected face, in image pixels (origin bottom-left). Nil if none.
    public let face: CGRect?
    /// Person mask (white = person) scaled to `image.extent`. Nil if segmentation failed.
    public let personMask: CIImage?
}

public enum HeadshotError: LocalizedError {
    case unreadableImage
    case renderFailed
    case writeFailed

    public var errorDescription: String? {
        switch self {
        case .unreadableImage: return "That file couldn't be read as an image."
        case .renderFailed: return "The image couldn't be rendered."
        case .writeFailed: return "The image couldn't be saved."
        }
    }
}

public final class HeadshotProcessor: @unchecked Sendable {
    public let context = CIContext(options: [.cacheIntermediates: false])

    public init() {}

    // MARK: Loading

    public static func loadImage(at url: URL) throws -> CIImage {
        guard let image = CIImage(contentsOf: url, options: [.applyOrientationProperty: true]) else {
            throw HeadshotError.unreadableImage
        }
        return image.transformed(by: .init(translationX: -image.extent.minX, y: -image.extent.minY))
    }

    // MARK: Analysis

    public func analyze(_ input: CIImage) throws -> PhotoAnalysis {
        let image = input.transformed(by: .init(translationX: -input.extent.minX, y: -input.extent.minY))
        guard let cg = context.createCGImage(image, from: image.extent) else { throw HeadshotError.renderFailed }

        let faces = VNDetectFaceRectanglesRequest()
        let person = VNGeneratePersonSegmentationRequest()
        person.qualityLevel = .accurate
        person.outputPixelFormat = kCVPixelFormatType_OneComponent8

        let handler = VNImageRequestHandler(cgImage: cg, options: [:])
        try? handler.perform([faces, person])

        let size = image.extent.size
        let face = (faces.results ?? [])
            .max { $0.boundingBox.width * $0.boundingBox.height < $1.boundingBox.width * $1.boundingBox.height }
            .map { VNImageRectForNormalizedRect($0.boundingBox, Int(size.width), Int(size.height)) }

        var mask: CIImage?
        // Vision returns a mask for every photo, even with nobody in it. A near-empty one means
        // "no person": using it would replace the whole picture with background.
        if let buffer = person.results?.first?.pixelBuffer {
            let raw = CIImage(cvPixelBuffer: buffer)
            if coverage(of: raw) >= Self.minPersonCoverage {
                mask = raw.transformed(by: .init(scaleX: size.width / raw.extent.width,
                                                 y: size.height / raw.extent.height))
            }
        }
        return PhotoAnalysis(image: image, face: face, personMask: mask)
    }

    /// Share of the frame a person mask must cover to count as a person.
    static let minPersonCoverage = 0.05

    /// Mean mask value, 0...1.
    func coverage(of mask: CIImage) -> Double {
        let avg = mask.applyingFilter("CIAreaAverage", parameters: [kCIInputExtentKey: CIVector(cgRect: mask.extent)])
        var px = [UInt8](repeating: 0, count: 4)
        context.render(avg, toBitmap: &px, rowBytes: 4, bounds: CGRect(x: 0, y: 0, width: 1, height: 1),
                       format: .RGBA8, colorSpace: nil)
        return Double(px[0]) / 255
    }

    // MARK: Rendering

    /// Full pipeline: enhance → tone → smooth → background → crop. Output extent starts at the origin.
    public func render(_ analysis: PhotoAnalysis, settings s: HeadshotSettings) -> CIImage {
        let extent = analysis.image.extent
        var img = analysis.image

        if s.autoEnhance {
            for filter in img.autoAdjustmentFilters(options: [.redEye: false]) {
                filter.setValue(img, forKey: kCIInputImageKey)
                img = filter.outputImage ?? img
            }
        }

        if s.exposure != 0 {
            let f = CIFilter.exposureAdjust(); f.inputImage = img; f.ev = Float(s.exposure)
            img = f.outputImage ?? img
        }
        if s.contrast != 1 || s.saturation != 1 {
            let f = CIFilter.colorControls(); f.inputImage = img
            f.contrast = Float(s.contrast); f.saturation = Float(s.saturation); f.brightness = 0
            img = f.outputImage ?? img
        }
        if s.warmth != 0 {
            // A target neutral below the source neutral shifts the image towards amber.
            let f = CIFilter.temperatureAndTint(); f.inputImage = img
            f.neutral = CIVector(x: 6500, y: 0)
            f.targetNeutral = CIVector(x: 6500 - CGFloat(s.warmth) * 2000, y: 0)
            img = f.outputImage ?? img
        }

        if s.smoothing > 0 {
            img = smooth(img, amount: s.smoothing, mask: analysis.personMask)
        }

        if s.background != .original, let mask = analysis.personMask {
            let bg = background(for: s, source: img, extent: extent)
            let soft = mask.clampedToExtent().applyingGaussianBlur(sigma: 1.5).cropped(to: extent)
            let blend = CIFilter.blendWithMask()
            blend.inputImage = img; blend.backgroundImage = bg; blend.maskImage = soft
            img = blend.outputImage ?? img
        }

        img = img.cropped(to: extent)
        let rect = Framing.cropRect(face: analysis.face, image: extent, aspect: s.crop).intersection(extent)
        return img.cropped(to: rect).transformed(by: .init(translationX: -rect.minX, y: -rect.minY))
    }

    /// Edge-preserving smoothing: downsample, then upsample guided by the full-res
    /// image so edges (eyes, hairline) stay sharp while skin texture softens.
    func smooth(_ img: CIImage, amount: Double, mask: CIImage?) -> CIImage {
        let extent = img.extent
        let small = img.transformed(by: .init(scaleX: 0.2, y: 0.2))
        let up = CIFilter.edgePreserveUpsample()
        up.inputImage = img; up.smallImage = small
        up.spatialSigma = 5; up.lumaSigma = 0.1
        guard let smoothed = up.outputImage?.cropped(to: extent) else { return img }

        // Blend strength; restrict to the person so the background isn't touched.
        let k = CGFloat(amount * 0.8)
        let blendMask = (mask ?? CIImage(color: .white).cropped(to: extent))
            .applyingFilter("CIColorMatrix", parameters: [
                "inputRVector": CIVector(x: k, y: 0, z: 0, w: 0),
                "inputGVector": CIVector(x: 0, y: k, z: 0, w: 0),
                "inputBVector": CIVector(x: 0, y: 0, z: k, w: 0),
            ])
        let blend = CIFilter.blendWithMask()
        blend.inputImage = smoothed; blend.backgroundImage = img; blend.maskImage = blendMask
        return blend.outputImage?.cropped(to: extent) ?? img
    }

    func background(for s: HeadshotSettings, source: CIImage, extent: CGRect) -> CIImage {
        let c = s.backgroundColor
        switch s.background {
        case .original:
            return source
        case .blur:
            let radius = min(extent.width, extent.height) * s.backgroundBlur
            return source.clampedToExtent().applyingGaussianBlur(sigma: radius).cropped(to: extent)
        case .solid:
            return CIImage(color: CIColor(red: c.r, green: c.g, blue: c.b)).cropped(to: extent)
        case .gradient:
            // Soft studio light: brighter behind the head, falling off towards the edges.
            let f = CIFilter.radialGradient()
            f.center = CGPoint(x: extent.midX, y: extent.minY + extent.height * 0.62)
            f.radius0 = Float(min(extent.width, extent.height) * 0.05)
            f.radius1 = Float(max(extent.width, extent.height) * 0.8)
            f.color0 = CIColor(red: min(1, c.r + 0.15), green: min(1, c.g + 0.15), blue: min(1, c.b + 0.15))
            f.color1 = CIColor(red: c.r * 0.6, green: c.g * 0.6, blue: c.b * 0.6)
            return (f.outputImage ?? CIImage(color: .gray)).cropped(to: extent)
        }
    }

    // MARK: Output

    public func cgImage(_ image: CIImage, maxDimension: CGFloat? = nil) -> CGImage? {
        var img = image
        if let maxDimension {
            let scale = maxDimension / max(image.extent.width, image.extent.height)
            if scale < 1 { img = image.transformed(by: .init(scaleX: scale, y: scale)) }
        }
        return context.createCGImage(img, from: img.extent.integral,
                                     format: .RGBA8, colorSpace: CGColorSpace(name: CGColorSpace.sRGB))
    }

    public func write(_ cg: CGImage, to url: URL) throws {
        let type: UTType = ["jpg", "jpeg"].contains(url.pathExtension.lowercased()) ? .jpeg : .png
        guard let dest = CGImageDestinationCreateWithURL(url as CFURL, type.identifier as CFString, 1, nil) else {
            throw HeadshotError.writeFailed
        }
        CGImageDestinationAddImage(dest, cg, [kCGImageDestinationLossyCompressionQuality: 0.92] as CFDictionary)
        guard CGImageDestinationFinalize(dest) else { throw HeadshotError.writeFailed }
    }
}
