import SwiftUI
import PhotosUI
import ImageIO
import AVFoundation
import CoreTransferable
import UniformTypeIdentifiers
import MoonPixelCore

/// A video picked from the photo library, copied somewhere we may read it.
struct MovieFile: Transferable {
    let url: URL
    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(contentType: .movie) { movie in
            SentTransferredFile(movie.url)
        } importing: { received in
            let dst = FileManager.default.temporaryDirectory.appendingPathComponent("mp-" + UUID().uuidString + "." + received.file.pathExtension)
            try FileManager.default.copyItem(at: received.file, to: dst)
            return MovieFile(url: dst)
        }
    }
}

enum PickedMedia {
    case still(UIImage)
    case motion([Bitmap])       // GIF or video frames, in order
    case failed
}

/// Photos, GIFs and videos all come in through the same picker.
enum MediaLoader {
    static func load(_ item: PhotosPickerItem) async -> PickedMedia {
        let types = item.supportedContentTypes
        if types.contains(where: { $0.conforms(to: .movie) || $0.conforms(to: .video) }) {
            guard let movie = try? await item.loadTransferable(type: MovieFile.self) else { return .failed }
            let frames = await videoFrames(movie.url)
            try? FileManager.default.removeItem(at: movie.url)
            if frames.count > 1 { return .motion(frames) }
            if let one = frames.first?.uiImage { return .still(one) }
            return .failed
        }
        guard let data = try? await item.loadTransferable(type: Data.self) else { return .failed }
        let frames = gifFrames(data)
        if frames.count > 1 { return .motion(frames) }
        if let img = UIImage(data: data) { return .still(img) }
        return .failed
    }

    /// Evenly spaced frames of an animated image (GIF, APNG, animated HEIC/WebP).
    static func gifFrames(_ data: Data, maxFrames: Int = 12, maxSide: Int = 256) -> [Bitmap] {
        guard let src = CGImageSourceCreateWithData(data as CFData, nil) else { return [] }
        let n = CGImageSourceGetCount(src)
        guard n > 1 else { return [] }
        let take = min(maxFrames, n)
        var out: [Bitmap] = []
        for i in 0..<take {
            guard let cg = CGImageSourceCreateImageAtIndex(src, i * n / take, nil), let b = Bitmap(image: UIImage(cgImage: cg), maxSide: maxSide) else { continue }
            out.append(b)
        }
        return out
    }

    /// Evenly spaced frames from the first seconds of a video.
    static func videoFrames(_ url: URL, maxFrames: Int = 12, maxSide: Int = 256, seconds: Double = 2.4) async -> [Bitmap] {
        let asset = AVURLAsset(url: url)
        guard let duration = try? await asset.load(.duration) else { return [] }
        let total = min(CMTimeGetSeconds(duration), seconds)
        guard total.isFinite, total > 0.05 else { return [] }
        let gen = AVAssetImageGenerator(asset: asset)
        gen.appliesPreferredTrackTransform = true
        gen.maximumSize = CGSize(width: 512, height: 512)
        gen.requestedTimeToleranceBefore = CMTime(value: 1, timescale: 20)
        gen.requestedTimeToleranceAfter = CMTime(value: 1, timescale: 20)
        var out: [Bitmap] = []
        for i in 0..<maxFrames {
            let t = CMTime(seconds: total * Double(i) / Double(maxFrames), preferredTimescale: 600)
            guard let cg = try? await gen.image(at: t).image, let b = Bitmap(image: UIImage(cgImage: cg), maxSide: maxSide) else { continue }
            out.append(b)
        }
        return out
    }
}
