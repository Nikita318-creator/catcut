// MARK: - Controllers/ViewController+Export.swift

import UIKit
import AVFoundation
import CoreImage
import CoreMedia
import PhotosUI
import Photos
import UniformTypeIdentifiers
import SnapKit

extension ViewController {

    // MARK: Export

    @objc func didTapExport() {
        guard let b = build, !clips.isEmpty else { showToast("Нечего экспортировать"); return }
        pausePlayback()

        let overlay = ExportOverlay()
        overlay.frame = view.bounds
        overlay.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        overlay.onCancel = { [weak self] in self?.exporter.cancel() }
        view.addSubview(overlay)
        exportOverlay = overlay

        exporter.export(build: b, clips: clips, texts: texts, project: project, overlays: overlays,
                        progress: { [weak self] p in self?.exportOverlay?.setProgress(p) },
                        completion: { [weak self] result in
            guard let self = self else { return }
            self.exportOverlay?.removeFromSuperview()
            self.exportOverlay = nil
            switch result {
            case .success(let url):
                self.saveToPhotos(url: url)
            case .failure(let error):
                if let e = error as? VideoExporter.ExportError, e == .cancelled {
                    self.showToast("Экспорт отменён")
                } else {
                    self.showResultAlert(title: "Ошибка", message: error.localizedDescription)
                }
            }
        })
    }

    func saveToPhotos(url: URL) {
        PHPhotoLibrary.requestAuthorization(for: .addOnly) { [weak self] status in
            guard status == .authorized || status == .limited else {
                DispatchQueue.main.async {
                    self?.showResultAlert(title: "Нет доступа", message: "Разрешите добавление в Фото в настройках.")
                }
                return
            }
            PHPhotoLibrary.shared().performChanges({
                PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: url)
            }) { success, error in
                DispatchQueue.main.async {
                    if success {
                        self?.showResultAlert(title: "Готово 🎉", message: "Видео сохранено в Галерею.")
                    } else {
                        self?.showResultAlert(title: "Ошибка", message: error?.localizedDescription ?? "Не удалось сохранить")
                    }
                }
            }
        }
    }

    func showResultAlert(title: String, message: String) {
        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        present(alert, animated: true)
    }
}
