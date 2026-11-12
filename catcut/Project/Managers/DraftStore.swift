// MARK: - Managers/DraftStore.swift

import UIKit
import AVFoundation
import CoreImage
import CoreMedia

// =====================================================================
// MARK: - Drafts (черновики)
// =====================================================================

struct DraftClip: Codable {
    var id: UUID
    var file: String
    var srcStart: Double
    var srcDuration: Double
    var speed: Float
    var filterID: Int?
    var filterIntensity: Float
    var transitionID: Int
    var transitionDuration: Double
    var volume: Float
    // добавлено позже — optional, чтобы старые черновики открывались
    var isImage: Bool?
    var adjust: Adjustments?
    var look: Int?
    var flipH: Bool?
    var flipV: Bool?
    var rotation: Double?
    var zoom: Double?
    var bgMode: Int?
    var bgFile: String?
    var bgColor: Int?
    var audioEffect: Int?
    var fadeIn: Double?
    var fadeOut: Double?
}

struct DraftAudio: Codable {
    var id: UUID
    var file: String
    var title: String
    var start: Double
    var sourceOffset: Double
    var duration: Double
    var volume: Float
    var effect: Int?
    var fadeIn: Double?
    var fadeOut: Double?
}

struct Draft: Codable {
    var id: UUID
    var updated: Date
    var duration: Double
    var clips: [DraftClip]
    var texts: [TextOverlay]
    var audios: [DraftAudio]
    var project: ProjectSettings?
    var isAutoSaved: Bool? // <--- Добавили флаг автосейва
}

final class DraftStore {
    static let shared = DraftStore()

    let draftsDir: URL
    let mediaDir: URL

    private init() {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("VideoEditor", isDirectory: true)
        draftsDir = base.appendingPathComponent("Drafts", isDirectory: true)
        mediaDir = base.appendingPathComponent("Media", isDirectory: true)
        try? FileManager.default.createDirectory(at: draftsDir, withIntermediateDirectories: true)
        try? FileManager.default.createDirectory(at: mediaDir, withIntermediateDirectories: true)
    }

    func mediaURL(_ file: String) -> URL { mediaDir.appendingPathComponent(file) }
    private func jsonURL(_ id: UUID) -> URL { draftsDir.appendingPathComponent("\(id.uuidString).json") }
    func coverURL(_ id: UUID) -> URL { draftsDir.appendingPathComponent("\(id.uuidString).jpg") }

    /// Копируем файл в постоянное хранилище (tmp система может очистить). Возвращает имя файла.
    func importMedia(from url: URL, defaultExt: String) -> String? {
        let ext = url.pathExtension.isEmpty ? defaultExt : url.pathExtension
        let name = "\(UUID().uuidString).\(ext)"
        do {
            try FileManager.default.copyItem(at: url, to: mediaURL(name))
            return name
        } catch {
            return nil
        }
    }

    func list() -> [Draft] {
        let files = (try? FileManager.default.contentsOfDirectory(at: draftsDir, includingPropertiesForKeys: nil)) ?? []
        let decoder = JSONDecoder()
        return files.filter { $0.pathExtension == "json" }
            .compactMap { try? decoder.decode(Draft.self, from: Data(contentsOf: $0)) }
            .sorted { $0.updated > $1.updated }
    }

    func save(_ draft: Draft, coverAsset: AVAsset?, coverTime: Double) {
        if let data = try? JSONEncoder().encode(draft) {
            try? data.write(to: jsonURL(draft.id), options: .atomic)
        }
        guard let asset = coverAsset else { return }
        let url = coverURL(draft.id)
        DispatchQueue.global(qos: .utility).async {
            let gen = AVAssetImageGenerator(asset: asset)
            gen.appliesPreferredTrackTransform = true
            gen.maximumSize = CGSize(width: 300, height: 300)
            if let cg = try? gen.copyCGImage(at: CMTime(seconds: coverTime, preferredTimescale: 600), actualTime: nil),
               let data = UIImage(cgImage: cg).jpegData(compressionQuality: 0.7) {
                try? data.write(to: url, options: .atomic)
            }
        }
    }

    func delete(_ id: UUID) {
        try? FileManager.default.removeItem(at: jsonURL(id))
        try? FileManager.default.removeItem(at: coverURL(id))
    }
}
