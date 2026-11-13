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
