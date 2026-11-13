// MARK: - Controllers/ViewController+Media.swift

import UIKit
import AVFoundation
import CoreImage
import CoreMedia
import PhotosUI
import Photos
import UniformTypeIdentifiers
import SnapKit

extension ViewController {

    // MARK: Add video / photo

    func didTapAddVideo() {
        pickerPurpose = .clips
        var config = PHPickerConfiguration()
        config.filter = .any(of: [.videos, .images])
        config.selectionLimit = 0   // можно выбрать сразу несколько
        let picker = PHPickerViewController(configuration: config)
        picker.delegate = self
        present(picker, animated: true)
    }

    final class ClipCollector {
        let lock = NSLock()
        var items: [Int: VideoClip] = [:]
        func set(_ i: Int, _ c: VideoClip) { lock.lock(); items[i] = c; lock.unlock() }
        func ordered() -> [VideoClip] { lock.lock(); defer { lock.unlock() }; return items.keys.sorted().compactMap { items[$0] } }
    }

    func importVideos(_ results: [PHPickerResult]) {
        guard !results.isEmpty else { return }
        
        // 1. Создаем временные/пустые клипы-заглушки для МГНОВЕННОГО отображения на таймлайне
        var placeholderClips: [VideoClip] = []
        let tempUUIDs = results.map { _ in UUID() }
        
        for id in tempUUIDs {
            // Создаем временный пустой ассет или заглушку (на 3 секунды), пока файл копируется
            let dummyURL = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("\(id.uuidString).mov")
            let asset = AVAsset(url: dummyURL)
            let clip = VideoClip(
                id: id,
                asset: asset,
                file: "",
                isImage: false,
                sourceRange: CMTimeRange(start: .zero, duration: ticks(3)),
                speed: 1.0
            )
            placeholderClips.append(clip)
        }
        
        // Сразу добавляем на таймлайн и перестраиваем проект (пользователь видит дорожку моментально!)
        pushUndo()
        let resumeTime = clips.isEmpty ? CMTime.zero : ticks(displayTime)
        clips.append(contentsOf: placeholderClips)
        focusLane = .video
        rebuild(seekTo: resumeTime)
        
        // 2. В фоне производим реальный импорт файлов и заменяем заглушки по мере готовности
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let group = DispatchGroup()
            
            for (index, r) in results.enumerated() {
                let provider = r.itemProvider
                let targetID = tempUUIDs[index]
                group.enter()
                
                if provider.hasItemConformingToTypeIdentifier(UTType.movie.identifier) {
                    provider.loadFileRepresentation(forTypeIdentifier: UTType.movie.identifier) { url, error in
                        defer { group.leave() }
                        guard let url = url, error == nil,
                              let file = DraftStore.shared.importMedia(from: url, defaultExt: "mov") else { return }
                        let realURL = DraftStore.shared.mediaURL(file)
                        let asset = AVAsset(url: realURL)
                        let dur = floorTicks(asset.duration.secs)
                        guard dur.secs > 0.1, asset.tracks(withMediaType: .video).first != nil else { return }
                        
                        let realClip = VideoClip(
                            id: targetID,
                            asset: asset,
                            file: file,
                            sourceRange: CMTimeRange(start: .zero, duration: dur)
                        )
                        
                        DispatchQueue.main.async {
                            guard let self = self, let idx = self.clips.firstIndex(where: { $0.id == targetID }) else { return }
                            self.clips[idx] = realClip
                            ThumbnailStore.shared.prepare(asset)
                            self.rebuildVideoCompositionOnlyOrFull()
                        }
                    }
                } else if provider.canLoadObject(ofClass: UIImage.self) {
                    provider.loadObject(ofClass: UIImage.self) { obj, _ in
                        guard let img = obj as? UIImage else { group.leave(); return }
                        MediaTools.makeStillVideo(image: img) { name in
                            defer { group.leave() }
                            guard let name = name else { return }
                            let realURL = DraftStore.shared.mediaURL(name)
                            let asset = AVAsset(url: realURL)
                            let realClip = VideoClip(
                                id: targetID,
                                asset: asset,
                                file: name,
                                isImage: true,
                                sourceRange: CMTimeRange(start: .zero, duration: ticks(3))
                            )
                            
                            DispatchQueue.main.async {
                                guard let self = self, let idx = self.clips.firstIndex(where: { $0.id == targetID }) else { return }
                                self.clips[idx] = realClip
                                ThumbnailStore.shared.prepare(asset)
                                self.rebuildVideoCompositionOnlyOrFull()
                            }
                        }
                    }
                } else {
                    group.leave()
                }
            }
            
            group.notify(queue: .main) {
                [weak self] in
                self?.rebuild()
            }
        }
    }
    
    // Вспомогательный метод для мягкого апдейта, если не нужно сбрасывать позицию плеера
    private func rebuildVideoCompositionOnlyOrFull() {
        if build == nil {
            rebuild()
        } else {
            clampOverlays(total: TimelineLayout(clips: clips).total.secs)
            build = EditorBuild.make(clips: clips, audios: audios, overlays: overlays, project: project)
            if let b = build, let item = player.currentItem {
                item.videoComposition = b.makeVideoComposition(clips: clips, texts: texts, overlays: overlays, project: project)
            }
            reloadTimeline()
        }
    }

    // MARK: Reverse / freeze

    func reverseCurrentClip() {
        guard let i = currentClipIndex() else { return }
        let c = clips[i]
        guard !c.isImage else { showToast("У картинки нет движения 🙂"); return }
        guard c.sourceRange.duration.secs <= 30 else {
            showToast("Реверс — для кусков до 30 сек. Разрежьте клип")
            return
        }
        loader.startAnimating()
        showToast("Делаю реверс…")
        let id = c.id
        MediaTools.reverse(asset: c.asset, range: c.sourceRange) { [weak self] name in
            guard let self = self else { return }
            self.loader.stopAnimating()
            guard let name = name, let k = self.clips.firstIndex(where: { $0.id == id }) else {
                self.showToast("Не получилось сделать реверс")
                return
            }
            self.pushUndo()
            let asset = AVAsset(url: DraftStore.shared.mediaURL(name))
            self.clips[k].asset = asset
            self.clips[k].file = name
            self.clips[k].sourceRange = CMTimeRange(start: .zero, duration: floorTicks(asset.duration.secs))
            self.clips[k].processedAudio = nil
            self.clips[k].audioEffect = 0
            self.filterPreviewClipID = nil
            self.rebuild()
            self.refreshActivePanel()
        }
    }

    func freezeFrame(seconds: Double) {
        guard let b = build, let i = currentClipIndex() else { return }
        let t = displayTime
        let clip = clips[i]
        guard !clip.isImage else { showToast("Это уже картинка"); return }
        let offset = t - b.layout.starts[i].secs
        let dur = b.layout.durations[i].secs
        guard offset > 0.2, dur - offset > 0.2 else {
            showToast("Поставьте красную палку внутрь клипа")
            return
        }
        let srcOffset = ticks(offset * Double(clip.speed))
        let srcTime = clip.sourceRange.start.secs + offset * Double(clip.speed)
        let id = clip.id
        loader.startAnimating()

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let gen = AVAssetImageGenerator(asset: clip.asset)
            gen.appliesPreferredTrackTransform = true
            gen.requestedTimeToleranceBefore = .zero
            gen.requestedTimeToleranceAfter = .zero
            gen.maximumSize = CGSize(width: 1920, height: 1920)
            guard let cg = try? gen.copyCGImage(at: CMTime(seconds: srcTime, preferredTimescale: 600), actualTime: nil) else {
                DispatchQueue.main.async { self?.loader.stopAnimating(); self?.showToast("Не удалось взять кадр") }
                return
            }
            MediaTools.makeStillVideo(image: UIImage(cgImage: cg)) { name in
                guard let self = self else { return }
                self.loader.stopAnimating()
                guard let name = name, let k = self.clips.firstIndex(where: { $0.id == id }) else {
                    self.showToast("Не удалось сделать заморозку")
                    return
                }
                self.pushUndo()
                var first = self.clips[k]
                var second = self.clips[k]
                first.sourceRange = CMTimeRange(start: first.sourceRange.start, duration: srcOffset)
                first.transitionID = 0
                second.id = UUID()
                second.sourceRange = CMTimeRange(start: second.sourceRange.start + srcOffset,
                                                 duration: second.sourceRange.duration - srcOffset)
                var still = self.clips[k]
                still.id = UUID()
                still.asset = AVAsset(url: DraftStore.shared.mediaURL(name))
                still.file = name
                still.isImage = true
                still.sourceRange = CMTimeRange(start: .zero, duration: ticks(seconds))
                still.speed = 1
                still.transitionID = 0
                still.volume = 0
                still.audioEffect = 0
                still.processedAudio = nil
                still.fadeIn = 0
                still.fadeOut = 0
                self.clips.replaceSubrange(k...k, with: [first, still, second])
                self.clearSelection()
                self.selectedClipIndex = k + 1
                self.rebuild(seekTo: ticks(t))
                self.refreshActivePanel()
            }
        }
    }
    
    func importOverlayVideo(_ results: [PHPickerResult]) {
        guard let r = results.first else { return }
        let provider = r.itemProvider

        if provider.hasItemConformingToTypeIdentifier(UTType.movie.identifier) {
            provider.loadFileRepresentation(forTypeIdentifier: UTType.movie.identifier) { [weak self] url, error in
                guard let url = url, error == nil,
                      let file = DraftStore.shared.importMedia(from: url, defaultExt: "mov"),
                      let media = OverlayMedia.info(for: file), media.duration > 0.1 else { return }
                DispatchQueue.main.async { self?.addOverlay(file: file, isImage: false, sourceDuration: media.duration) }
            }
        } else if provider.canLoadObject(ofClass: UIImage.self) {
            provider.loadObject(ofClass: UIImage.self) { [weak self] obj, _ in
                guard let img = obj as? UIImage else { return }
                MediaTools.makeStillVideo(image: img) { name in
                    guard let name = name else { return }
                    DispatchQueue.main.async { self?.addOverlay(file: name, isImage: true, sourceDuration: 3.0) }
                }
            }
        }
    }

    /// Добавляет оверлей на отдельную видео-дорожку, выделяет его и ставит красную палку внутрь.
    func addOverlay(file: String, isImage: Bool, sourceDuration: Double) {
        let total = totalSeconds
        guard total > 0 else { return }
        pushUndo()
        let wanted = isImage ? 3.0 : min(sourceDuration, 5.0)
        var start = displayTime
        if total - start < 0.5 { start = max(0, total - wanted) }
        let dur = max(0.3, min(wanted, total - start))
        let o = VideoOverlay(file: file, isImage: isImage, sourceStart: 0,
                             sourceDuration: sourceDuration, start: start, duration: dur)
        overlays.append(o)
        clearSelection()
        selectedOverlayID = o.id
        focusLane = .overlay
        rebuild(seekTo: ticks(min(start + 0.01, total)))
        refreshActivePanel()
    }
}
