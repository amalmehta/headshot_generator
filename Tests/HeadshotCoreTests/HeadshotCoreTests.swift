import CoreImage
import XCTest
@testable import HeadshotCore

final class FramingTests: XCTestCase {
    let image = CGRect(x: 0, y: 0, width: 3000, height: 4000)

    func testSquareCropIsSquareAndContainsFace() {
        let face = CGRect(x: 1200, y: 2200, width: 600, height: 700)
        let crop = Framing.cropRect(face: face, image: image, aspect: .square)
        XCTAssertEqual(crop.width, crop.height, accuracy: 1)
        XCTAssertTrue(crop.contains(face))
        XCTAssertTrue(image.contains(crop))
        // Face sits a little above centre, as in a head-and-shoulders shot.
        XCTAssertGreaterThan(face.midY, crop.midY)
    }

    func testPortraitCropIs4by5() {
        let face = CGRect(x: 1200, y: 2200, width: 600, height: 700)
        let crop = Framing.cropRect(face: face, image: image, aspect: .portrait)
        XCTAssertEqual(crop.width / crop.height, 0.8, accuracy: 0.01)
    }

    func testFaceNearEdgeStaysInsideImage() {
        let face = CGRect(x: 10, y: 3500, width: 500, height: 480)
        let crop = Framing.cropRect(face: face, image: image, aspect: .square)
        XCTAssertTrue(image.contains(crop))
    }

    func testHugeFaceShrinksToFit() {
        let face = CGRect(x: 200, y: 500, width: 2600, height: 3000)
        let crop = Framing.cropRect(face: face, image: image, aspect: .square)
        XCTAssertEqual(crop.width, 3000, accuracy: 1)
        XCTAssertTrue(image.contains(crop))
    }

    func testNoFaceCentreCrops() {
        let crop = Framing.cropRect(face: nil, image: image, aspect: .square)
        XCTAssertEqual(crop, CGRect(x: 0, y: 500, width: 3000, height: 3000))
        XCTAssertEqual(Framing.cropRect(face: nil, image: image, aspect: .original), image)
    }
}

final class PipelineTests: XCTestCase {
    let processor = HeadshotProcessor()

    /// A plain gradient: no face, so every stage must degrade gracefully.
    func syntheticImage() -> CIImage {
        let f = CIFilter(name: "CILinearGradient", parameters: [
            "inputPoint0": CIVector(x: 0, y: 0), "inputPoint1": CIVector(x: 600, y: 800),
            "inputColor0": CIColor(red: 0.2, green: 0.4, blue: 0.6), "inputColor1": CIColor(red: 0.9, green: 0.8, blue: 0.7),
        ])!
        return f.outputImage!.cropped(to: CGRect(x: 0, y: 0, width: 600, height: 800))
    }

    func testRenderWithoutFaceCentreCropsEveryBackground() throws {
        let analysis = try processor.analyze(syntheticImage())
        XCTAssertNil(analysis.face)
        for background in BackgroundStyle.allCases {
            var s = HeadshotSettings()
            s.background = background
            let out = processor.render(analysis, settings: s)
            XCTAssertEqual(out.extent, CGRect(x: 0, y: 0, width: 600, height: 600), "\(background)")
            XCTAssertNotNil(processor.cgImage(out))
        }
    }

    func testWarmthMakesImageWarmer() throws {
        let gray = CIImage(color: CIColor(red: 0.5, green: 0.5, blue: 0.5)).cropped(to: CGRect(x: 0, y: 0, width: 64, height: 64))
        let analysis = PhotoAnalysis(image: gray, face: nil, personMask: nil)
        var s = HeadshotSettings()
        s.autoEnhance = false; s.smoothing = 0; s.background = .original; s.crop = .original
        s.warmth = 1
        let (r, _, b) = averageRGB(processor.render(analysis, settings: s))
        XCTAssertGreaterThan(r, b + 0.02, "warmth +1 should push red above blue")
    }

    func testAvatarsAreSquareAndCircleHasTransparentCorners() {
        let img = syntheticImage()
        for style in AvatarStyle.allCases {
            let out = AvatarStyler.apply(style, to: img)
            XCTAssertEqual(out.extent, CGRect(x: 0, y: 0, width: 1024, height: 1024), "\(style)")
            XCTAssertNotNil(processor.cgImage(out), "\(style)")
        }
        let circle = AvatarStyler.circular(AvatarStyler.apply(.cartoon, to: img))
        let corner = pixel(circle, at: CGPoint(x: 2, y: 2))
        let centre = pixel(circle, at: CGPoint(x: 512, y: 512))
        XCTAssertEqual(corner.a, 0)
        XCTAssertEqual(centre.a, 255)
    }

    /// A photo with nobody in it must not get a person mask, or the background swap erases it.
    func testNoPersonMeansNoMask() throws {
        let url = URL(fileURLWithPath: "/Library/User Pictures/Nature/Cactus.heic")
        guard FileManager.default.fileExists(atPath: url.path) else { throw XCTSkip("macOS stock picture not present") }
        let analysis = try processor.analyze(try HeadshotProcessor.loadImage(at: url))
        XCTAssertNil(analysis.personMask)
        XCTAssertNil(analysis.face)
    }

    /// Runs the full pipeline on a real portrait when HEADSHOT_TEST_IMAGE points at one.
    func testRealPortrait() throws {
        guard let path = ProcessInfo.processInfo.environment["HEADSHOT_TEST_IMAGE"] else {
            throw XCTSkip("Set HEADSHOT_TEST_IMAGE=/path/to/portrait.jpg to run")
        }
        let analysis = try processor.analyze(try HeadshotProcessor.loadImage(at: URL(fileURLWithPath: path)))
        let face = try XCTUnwrap(analysis.face, "no face detected")
        XCTAssertNotNil(analysis.personMask, "no person mask")

        let out = processor.render(analysis, settings: HeadshotSettings())
        XCTAssertEqual(out.extent.width, out.extent.height, accuracy: 1)

        if let dir = ProcessInfo.processInfo.environment["HEADSHOT_TEST_OUTPUT"] {
            let url = URL(fileURLWithPath: dir)
            try processor.write(processor.cgImage(out)!, to: url.appendingPathComponent("headshot.png"))
            for style in AvatarStyle.allCases {
                let avatar = AvatarStyler.circular(AvatarStyler.apply(style, to: out))
                try processor.write(processor.cgImage(avatar)!, to: url.appendingPathComponent("avatar-\(style).png"))
            }
        }
        print("face:", face, "image:", analysis.image.extent)
    }

    // MARK: Helpers

    func pixel(_ image: CIImage, at p: CGPoint) -> (r: UInt8, g: UInt8, b: UInt8, a: UInt8) {
        var px = [UInt8](repeating: 0, count: 4)
        processor.context.render(image, toBitmap: &px, rowBytes: 4, bounds: CGRect(origin: p, size: CGSize(width: 1, height: 1)),
                                 format: .RGBA8, colorSpace: CGColorSpace(name: CGColorSpace.sRGB))
        return (px[0], px[1], px[2], px[3])
    }

    func averageRGB(_ image: CIImage) -> (Double, Double, Double) {
        let avg = image.applyingFilter("CIAreaAverage", parameters: [kCIInputExtentKey: CIVector(cgRect: image.extent)])
        let p = pixel(avg, at: .zero)
        return (Double(p.r) / 255, Double(p.g) / 255, Double(p.b) / 255)
    }
}
