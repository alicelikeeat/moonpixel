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

    /// Crisp pixel-art texture.
    var texture: SKTexture {
        guard let cg = cgImage else { return SKTexture() }
        let t = SKTexture(cgImage: cg)
        t.filteringMode = .nearest
        return t
    }

    var uiImage: UIImage? { cgImage.map { UIImage(cgImage: $0) } }

    /// Decode any UIImage into RGBA pixels (downscaled so photos stay small).
    init?(image: UIImage, maxSide: Int = 512) {
        guard let cg = image.cgImage else { return nil }
        let k = min(1.0, Double(maxSide) / Double(max(cg.width, cg.height)))
        let w = max(1, Int(Double(cg.width) * k)), h = max(1, Int(Double(cg.height) * k))
        var buf = [UInt8](repeating: 0, count: w * h * 4)
        guard let ctx = CGContext(data: &buf, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4, space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        ctx.interpolationQuality = .medium
        // respect the photo's orientation by drawing the UIImage, not the raw CGImage
        UIGraphicsPushContext(ctx)
        ctx.translateBy(x: 0, y: CGFloat(h)); ctx.scaleBy(x: 1, y: -1)
        image.draw(in: CGRect(x: 0, y: 0, width: w, height: h))
        UIGraphicsPopContext()
        self.init(w, h)
        self.px = buf
    }
}
