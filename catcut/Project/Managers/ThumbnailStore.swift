// MARK: - Managers/ThumbnailStore.swift

import UIKit
import AVFoundation
import CoreImage
import CoreMedia

// =====================================================================
// MARK: - Thumbnails (один раз на файл, дальше режем как угодно)
// =====================================================================

final class ThumbnailStore {
    static let shared = ThumbnailStore()
    var onUpdate: (() -> Void)?

    private final class Entry {
        let asset: AVAsset
        let step: Double
        var images: [UIImage?]
        var generator: AVAssetImageGenerator?
        init(asset: AVAsset, step: Double, count: Int) {
            self.asset = asset
            self.step = step
            self.images = [UIImage?](repeating: nil, count: count)
        }
    }

    private var entries: [ObjectIdentifier: Entry] = [:]
    private var notifyScheduled = false

    func prepare(_ asset: AVAsset) {
        let key = ObjectIdentifier(asset)
        guard entries[key] == nil else { return }

        let duration = max(0.1, asset.duration.secs)
        let count = min(90, max(2, Int(ceil(duration / 0.5))))
        let step = duration / Double(count)
        let entry = Entry(asset: asset, step: step, count: count)
        entries[key] = entry

        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 240, height: 240)
        generator.requestedTimeToleranceBefore = .positiveInfinity
        generator.requestedTimeToleranceAfter = .positiveInfinity
        entry.generator = generator

        let times: [NSValue] = (0..<count).map {
            NSValue(time: CMTime(seconds: (Double($0) + 0.5) * step, preferredTimescale: 600))
        }

        generator.generateCGImagesAsynchronously(forTimes: times) { [weak self] requested, cg, _, result, _ in
            guard result == .succeeded, let cg = cg else { return }
            let idx = max(0, min(count - 1, Int(requested.seconds / step)))
            let image = UIImage(cgImage: cg)
            DispatchQueue.main.async {
                guard let self = self else { return }
                entry.images[idx] = image
                self.scheduleNotify()
            }
        }
    }

    func image(for asset: AVAsset, at seconds: Double) -> UIImage? {
        let key = ObjectIdentifier(asset)
        guard let entry = entries[key] else {
            prepare(asset)
            return nil
        }
        let count = entry.images.count
        let idx = max(0, min(count - 1, Int(seconds / entry.step)))
        if let img = entry.images[idx] { return img }
        var d = 1
        while d < count {
            if idx - d >= 0, let img = entry.images[idx - d] { return img }
            if idx + d < count, let img = entry.images[idx + d] { return img }
            d += 1
        }
        return nil
    }

    private func scheduleNotify() {
        guard !notifyScheduled else { return }
        notifyScheduled = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            self?.notifyScheduled = false
            self?.onUpdate?()
        }
    }
}
