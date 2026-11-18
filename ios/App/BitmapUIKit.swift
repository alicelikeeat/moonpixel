import UIKit
import SpriteKit
import MoonPixelCore

extension Bitmap {
    var cgImage: CGImage? {
        let data = Data(px) as CFData
        guard let provider = CGDataProvider(data: data) else { return nil }
        return CGImage(width: w, height: h, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: w * 4,
                       space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                       provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)
    }

    /// The art style everything is drawn in (set by the game's setting; pixel art as made, or the anime look).
    static var animeStyle = false

    /// The picture in the current style: the anime look is twice the pixels (smoothed, inked, cel-shaded).
    var styledCG: CGImage? { Bitmap.animeStyle ? anime().cgImage : cgImage }
    /// Colours only (same size): for atlases looked up by coordinates, where an outline would bleed.
    var gradedCG: CGImage? { Bitmap.animeStyle ? animeGraded().cgImage : cgImage }

    /// A sprite texture in the current style, the same size on screen in both (the anime one has twice the pixels).
    var texture: SKTexture {
        guard let cg = styledCG else { return SKTexture() }
        return Bitmap.skTexture(cg)
    }

    /// A texture from an image made in the current style: crisp pixels, or smooth at double resolution.
    static func skTexture(_ cg: CGImage) -> SKTexture {
        if animeStyle {
            let t = SKTexture(image: UIImage(cgImage: cg, scale: 2, orientation: .up))
            t.filteringMode = .linear
            return t
        }
        let t = SKTexture(cgImage: cg)
        t.filteringMode = .nearest
        return t
    }

    var uiImage: UIImage? { cgImage.map { UIImage(cgImage: $0) } }

    /// Decode any UIImage into RGBA pixels (downscaled so photos stay small).
    /// The image is first re-rendered upright, so camera orientation flags never
    /// leave the photo sideways or upside down.
    init?(image: UIImage, maxSide: Int = 512) {
        let src = image.size
        guard src.width >= 1, src.height >= 1 else { return nil }
        let k = min(1.0, Double(maxSide) / Double(max(src.width, src.height)))
        let w = max(1, Int(Double(src.width) * k)), h = max(1, Int(Double(src.height) * k))
        let fmt = UIGraphicsImageRendererFormat()
        fmt.scale = 1
        fmt.opaque = false
        let upright = UIGraphicsImageRenderer(size: CGSize(width: w, height: h), format: fmt).image { _ in
            image.draw(in: CGRect(x: 0, y: 0, width: w, height: h))
        }
        guard let cg = upright.cgImage else { return nil }
        var buf = [UInt8](repeating: 0, count: w * h * 4)
        guard let ctx = CGContext(data: &buf, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4, space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))
        self.init(w, h)
        self.px = buf
    }
}
