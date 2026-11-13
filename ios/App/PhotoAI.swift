import UIKit
import Vision
import MoonPixelCore

/// On-device AI for photos, using Apple's Vision neural networks: face
/// detection finds the face, person segmentation cuts the person out of the
/// background. Nothing leaves the device. The pixel art itself is then drawn by
/// MoonPixelCore from that analysis (this is recognition + pixelisation, not a
/// generative image model).
enum PhotoAI {
    struct Analysis {
        var bitmap: Bitmap                                   // person cut out when segmentation succeeded
        var face: (x: Int, y: Int, w: Int, h: Int)?
        var segmented: Bool
    }

    /// Runs synchronously; call it off the main thread.
    static func analyze(_ source: Bitmap) -> Analysis {
        var out = Analysis(bitmap: source, face: nil, segmented: false)
        guard let cg = source.cgImage else { return out }
        let handler = VNImageRequestHandler(cgImage: cg, options: [:])
        let faceReq = VNDetectFaceRectanglesRequest()
        let segReq = VNGeneratePersonSegmentationRequest()
        segReq.qualityLevel = .balanced
        segReq.outputPixelFormat = kCVPixelFormatType_OneComponent8
        try? handler.perform([faceReq])
        try? handler.perform([segReq])
        if let best = faceReq.results?.max(by: { $0.boundingBox.width * $0.boundingBox.height < $1.boundingBox.width * $1.boundingBox.height }) {
            let b = best.boundingBox          // normalised, origin bottom-left
            out.face = (x: Int(b.minX * CGFloat(source.w)), y: Int((1 - b.maxY) * CGFloat(source.h)),
                        w: Int(b.width * CGFloat(source.w)), h: Int(b.height * CGFloat(source.h)))
        }
        if let pb = segReq.results?.first?.pixelBuffer {
            CVPixelBufferLockBaseAddress(pb, .readOnly)
            defer { CVPixelBufferUnlockBaseAddress(pb, .readOnly) }
            let mw = CVPixelBufferGetWidth(pb), mh = CVPixelBufferGetHeight(pb), bpr = CVPixelBufferGetBytesPerRow(pb)
            if let base = CVPixelBufferGetBaseAddress(pb)?.assumingMemoryBound(to: UInt8.self), mw > 0, mh > 0 {
                var cut = source
                var kept = 0
                for y in 0..<source.h { for x in 0..<source.w {
                    let m = base[(y * mh / source.h) * bpr + (x * mw / source.w)]
                    if m < 110 { cut.px[(y * source.w + x) * 4 + 3] = 0; cut.px[(y * source.w + x) * 4] = 0; cut.px[(y * source.w + x) * 4 + 1] = 0; cut.px[(y * source.w + x) * 4 + 2] = 0 }
                    else { kept += 1 }
                } }
                // only trust the mask when it found a plausible person
                let share = Double(kept) / Double(source.w * source.h)
                if share > 0.06 && share < 0.97 { out.bitmap = cut; out.segmented = true }
            }
        }
        return out
    }
}
