// MARK: - Managers/TransitionPreviewStore.swift

import UIKit
import AVFoundation
import CoreImage
import CoreMedia

// =====================================================================
// MARK: - Transition previews (превью перехода на кадрах твоего видео)
// =====================================================================

final class TransitionPreviewStore {
    static let shared = TransitionPreviewStore()

    private let queue = DispatchQueue(label: "transition.preview", qos: .userInitiated)
    private let cache = NSCache<NSString, UIImage>()
    private let lock = NSLock()
    private var fromImg: CIImage?
    private var toImg: CIImage?
    private var generation = 0
    private let side: CGFloat = 112

    func setFrames(from: CGImage?, to: CGImage?) {
        lock.lock()
        generation += 1
        fromImg = from.map { fill(CIImage(cgImage: $0)) }
        toImg = to.map { fill(CIImage(cgImage: $0)) }
        lock.unlock()
        cache.removeAllObjects()
    }

    private func fill(_ img: CIImage) -> CIImage {
        let e = img.extent
        let s = max(side / e.width, side / e.height)
        let w = e.width * s, h = e.height * s
        return img.transformed(by: CGAffineTransform(translationX: -e.minX, y: -e.minY))
            .transformed(by: CGAffineTransform(scaleX: s, y: s))
            .transformed(by: CGAffineTransform(translationX: (side - w) / 2, y: (side - h) / 2))
            .cropped(to: CGRect(x: 0, y: 0, width: side, height: side))
    }

    /// key: "t<id>". Результат приходит в main.
    func image(for key: String, isValid: @escaping () -> Bool, completion: @escaping (UIImage?) -> Void) {
        if let cached = cache.object(forKey: key as NSString) { completion(cached); return }
        lock.lock(); let gen = generation; let f = fromImg; let t = toImg; lock.unlock()
        guard f != nil, t != nil, let id = Int(key.dropFirst()) else { completion(nil); return }

        queue.async { [weak self] in
            guard let self = self, isValid(), let f = f, let t = t, let spec = TransitionCatalog.spec(id) else { return }
            let rect = CGRect(x: 0, y: 0, width: self.side, height: self.side)
            var p: CGFloat = 0.45
            if case .dip = spec.base { p = 0.3 }
            let out = TransitionRenderer.render(id: id, from: f, to: t, t: p, rect: rect)
            var image: UIImage?
            if let cg = EditorCompositor.ciContext.createCGImage(out, from: rect) { image = UIImage(cgImage: cg) }
            DispatchQueue.main.async {
                self.lock.lock(); let same = (gen == self.generation); self.lock.unlock()
                guard same else { return }
                if let image = image { self.cache.setObject(image, forKey: key as NSString) }
                completion(image)
            }
        }
    }
}
