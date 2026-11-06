// MARK: - Core/VideoExporter.swift

import UIKit
import AVFoundation
import CoreImage
import CoreMedia

// =====================================================================
// MARK: - Video exporter (вынесено из контроллера)
// =====================================================================

final class VideoExporter {

    enum ExportError: Error, LocalizedError {
        case cannotCreate
        case cancelled

        var errorDescription: String? {
            switch self {
            case .cannotCreate: return "Экспорт недоступен"
            case .cancelled: return "Экспорт отменён"
            }
        }
    }

    private var session: AVAssetExportSession?
    private var timer: Timer?

    var isRunning: Bool { session != nil }

    func cancel() {
        session?.cancelExport()
    }

    /// Рендерит проект через ту же композицию и тот же compositor, что и превью —
    /// поэтому в файле ровно то, что человек видел на экране (звук, фильтры, переходы, текст).
    func export(build: EditorBuild,
                clips: [VideoClip],
                texts: [TextOverlay],
                project: ProjectSettings,
                progress: @escaping (Float) -> Void,
                completion: @escaping (Result<URL, Error>) -> Void) {

        let videoComposition = build.makeVideoComposition(clips: clips, texts: texts, project: project)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("edit_\(UUID().uuidString).mp4")
        try? FileManager.default.removeItem(at: url)

        guard let s = AVAssetExportSession(asset: build.composition, presetName: AVAssetExportPresetHighestQuality) else {
            completion(.failure(ExportError.cannotCreate))
            return
        }
        s.outputURL = url
        s.outputFileType = .mp4
        s.videoComposition = videoComposition
        s.audioMix = build.audioMix
        s.audioTimePitchAlgorithm = .spectral
        s.shouldOptimizeForNetworkUse = true
        session = s

        timer = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { [weak self] _ in
            guard let cur = self?.session else { return }
            progress(cur.progress)
        }

        s.exportAsynchronously { [weak self] in
            DispatchQueue.main.async {
                self?.timer?.invalidate()
                self?.timer = nil
                self?.session = nil
                switch s.status {
                case .completed:
                    completion(.success(url))
                case .cancelled:
                    completion(.failure(ExportError.cancelled))
                default:
                    completion(.failure(s.error ?? ExportError.cannotCreate))
                }
            }
        }
    }
}
