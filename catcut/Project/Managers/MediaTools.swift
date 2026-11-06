// MARK: - Managers/MediaTools.swift

import UIKit
import AVFoundation
import CoreImage
import CoreMedia

// =====================================================================
// MARK: - Media tools: картинка → клип, реверс
// =====================================================================

enum MediaTools {
    /// Клип-картинка = короткое «видео» из одного кадра. Длина в файле — максимум, до которого её можно растянуть.
    static let stillSeconds = 120.0

    private static func finish(_ name: String?, _ completion: @escaping (String?) -> Void) {
        DispatchQueue.main.async { completion(name) }
    }

    static func makeStillVideo(image: UIImage, completion: @escaping (String?) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async {
            let maxSide: CGFloat = 1920
            let k = min(1, maxSide / max(image.size.width, image.size.height))
            let w = max(2, floor(image.size.width * k / 2) * 2)
            let h = max(2, floor(image.size.height * k / 2) * 2)
            let fmt = UIGraphicsImageRendererFormat()
            fmt.scale = 1
            fmt.opaque = true
            let upright = UIGraphicsImageRenderer(size: CGSize(width: w, height: h), format: fmt).image { _ in
                image.draw(in: CGRect(x: 0, y: 0, width: w, height: h))
            }
            guard let cg = upright.cgImage else { finish(nil, completion); return }
            let ci = CIImage(cgImage: cg)

            let name = "\(UUID().uuidString).mp4"
            let url = DraftStore.shared.mediaURL(name)
            guard let writer = try? AVAssetWriter(outputURL: url, fileType: .mp4) else { finish(nil, completion); return }
            let settings: [String: Any] = [
                AVVideoCodecKey: AVVideoCodecType.h264,
                AVVideoWidthKey: Int(w),
                AVVideoHeightKey: Int(h),
                AVVideoCompressionPropertiesKey: [AVVideoAverageBitRateKey: 3_000_000, AVVideoMaxKeyFrameIntervalKey: 2]
            ]
            let input = AVAssetWriterInput(mediaType: .video, outputSettings: settings)
            input.expectsMediaDataInRealTime = false
            let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
                kCVPixelBufferWidthKey as String: Int(w),
                kCVPixelBufferHeightKey as String: Int(h)
            ])
            guard writer.canAdd(input) else { finish(nil, completion); return }
            writer.add(input)
            guard writer.startWriting() else { finish(nil, completion); return }
            writer.startSession(atSourceTime: .zero)

            var buf: CVPixelBuffer?
            if let pool = adaptor.pixelBufferPool { CVPixelBufferPoolCreatePixelBuffer(nil, pool, &buf) }
            guard let buffer = buf else { finish(nil, completion); return }
            EditorCompositor.ciContext.render(ci, to: buffer)

            let fps: Int32 = 2
            let frames = Int(stillSeconds) * Int(fps) + 1
            for i in 0..<frames {
                while !input.isReadyForMoreMediaData { usleep(3000) }
                adaptor.append(buffer, withPresentationTime: CMTime(value: Int64(i), timescale: fps))
            }
            input.markAsFinished()
            writer.finishWriting {
                finish(writer.status == .completed ? name : nil, completion)
            }
        }
    }

    /// Реверс куска видео (без звука). Память держим малой: идём кусками по 0.5 сек с конца.
    static func reverse(asset: AVAsset, range: CMTimeRange, completion: @escaping (String?) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async {
            guard let track = asset.tracks(withMediaType: .video).first else { finish(nil, completion); return }
            let nat = track.naturalSize
            let k = min(1, 1280 / max(nat.width, nat.height))
            let w = Int(max(2, floor(nat.width * k / 2) * 2))
            let h = Int(max(2, floor(nat.height * k / 2) * 2))
            let fpsValue = track.nominalFrameRate > 0 ? Double(track.nominalFrameRate) : 30
            let fps = Int32(min(60, max(15, fpsValue.rounded())))

            let name = "\(UUID().uuidString).mp4"
            let url = DraftStore.shared.mediaURL(name)
            guard let writer = try? AVAssetWriter(outputURL: url, fileType: .mp4) else { finish(nil, completion); return }
            let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
                AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: w, AVVideoHeightKey: h,
                AVVideoCompressionPropertiesKey: [AVVideoAverageBitRateKey: 8_000_000]
            ])
            input.expectsMediaDataInRealTime = false
            input.transform = track.preferredTransform
            let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
                kCVPixelBufferWidthKey as String: w, kCVPixelBufferHeightKey as String: h
            ])
            guard writer.canAdd(input) else { finish(nil, completion); return }
            writer.add(input)
            guard writer.startWriting() else { finish(nil, completion); return }
            writer.startSession(atSourceTime: .zero)

            let start = range.start.secs
            var segEnd = range.end.secs
            var outIndex: Int64 = 0

            while segEnd > start + 0.001 {
                let segStart = max(start, segEnd - 0.5)
                guard let reader = try? AVAssetReader(asset: asset) else { break }
                let out = AVAssetReaderTrackOutput(track: track, outputSettings: [
                    kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
                    kCVPixelBufferWidthKey as String: w, kCVPixelBufferHeightKey as String: h
                ])
                reader.timeRange = CMTimeRange(start: ticks(segStart), end: ticks(segEnd))
                guard reader.canAdd(out) else { break }
                reader.add(out)
                guard reader.startReading() else { break }

                var frames: [CVPixelBuffer] = []
                while let sb = out.copyNextSampleBuffer() {
                    guard let src = CMSampleBufferGetImageBuffer(sb) else { continue }
                    var dst: CVPixelBuffer?
                    if let pool = adaptor.pixelBufferPool { CVPixelBufferPoolCreatePixelBuffer(nil, pool, &dst) }
                    if let d = dst {
                        EditorCompositor.ciContext.render(CIImage(cvPixelBuffer: src), to: d)
                        frames.append(d)
                    }
                }
                for buf in frames.reversed() {
                    while !input.isReadyForMoreMediaData { usleep(3000) }
                    adaptor.append(buf, withPresentationTime: CMTime(value: outIndex, timescale: fps))
                    outIndex += 1
                }
                segEnd = segStart
            }
            input.markAsFinished()
            writer.finishWriting {
                finish(writer.status == .completed && outIndex > 0 ? name : nil, completion)
            }
        }
    }
}
