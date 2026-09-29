import CoreGraphics

/// Pure geometry for head-and-shoulders framing. Coordinates are Core Image style
/// (origin bottom-left), in pixels.
public enum Framing {
    /// Share of the frame height the face box should fill.
    static let faceHeightShare: CGFloat = 0.40
    /// Where the face centre sits, measured from the bottom of the frame.
    static let faceCenterFromBottom: CGFloat = 0.56

    public static func cropRect(face: CGRect?, image: CGRect, aspect: CropAspect) -> CGRect {
        guard let ratio = aspect.ratio else { return image }

        guard let face else { return centered(ratio: ratio, in: image) }

        var height = face.height / faceHeightShare
        var width = height * ratio
        // Too big for the photo: shrink to the largest frame of that aspect that fits.
        if width > image.width { width = image.width; height = width / ratio }
        if height > image.height { height = image.height; width = height * ratio }

        var x = face.midX - width / 2
        var y = face.midY - height * faceCenterFromBottom
        x = min(max(x, image.minX), image.maxX - width)
        y = min(max(y, image.minY), image.maxY - height)
        return CGRect(x: x, y: y, width: width, height: height).integral
    }

    static func centered(ratio: CGFloat, in image: CGRect) -> CGRect {
        var width = image.width
        var height = width / ratio
        if height > image.height { height = image.height; width = height * ratio }
        return CGRect(x: image.midX - width / 2, y: image.midY - height / 2,
                      width: width, height: height).integral
    }
}
