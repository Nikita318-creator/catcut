import UIKit

final class AnimationPreviewStore {
    static let shared = AnimationPreviewStore()
    private var cache: [String: UIImage] = [:]
    private let queue = DispatchQueue(label: "com.editor.animationPreviews", qos: .userInitiated)

    func image(for key: String, isValid: @escaping () -> Bool, completion: @escaping (UIImage?) -> Void) {
        if let img = cache[key] {
            completion(img)
            return
        }
        queue.async {
            // Генерация превью кадра для конкретной анимации по ключу (например, "anim-1", "anim-2" и т.д.)
            // Здесь можно использовать первый/последний кадр первого клипа в проекте как базу
            DispatchQueue.main.async {
                guard isValid() else { return }
                completion(nil) // или сгенерированная картинка
            }
        }
    }
}
