// MARK: - Core/OverlaySupport.swift

import UIKit
import AVFoundation

/// Кэш метаданных файлов-оверлеев: asset, длительность и размер кадра (с учётом поворота).
/// Нужен таймлайну (миниатюры, лимит обрезки), превью (рамка выделения) и сборщику композиции.
enum OverlayMedia {
    struct Info {
        let asset: AVAsset
        let duration: Double
        let size: CGSize
        var aspect: CGFloat { size.height / max(1, size.width) }
    }

    private static var cache: [String: Info] = [:]
    private static let lock = NSLock()

    static func info(for file: String) -> Info? {
        guard !file.isEmpty else { return nil }
        lock.lock(); defer { lock.unlock() }
        if let c = cache[file] { return c }
        let url = DraftStore.shared.mediaURL(file)
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        let asset = AVAsset(url: url)
        guard let track = asset.tracks(withMediaType: .video).first else { return nil }
        let r = CGRect(origin: .zero, size: track.naturalSize).applying(track.preferredTransform)
        let size = CGSize(width: max(1, abs(r.width)), height: max(1, abs(r.height)))
        let info = Info(asset: asset, duration: asset.duration.secs, size: size)
        cache[file] = info
        return info
    }
}
