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
        loader.startAnimating()
        let group = DispatchGroup()
        let collector = ClipCollector()

        for (idx, r) in results.enumerated() {
            let provider = r.itemProvider
            group.enter()
            if provider.hasItemConformingToTypeIdentifier(UTType.movie.identifier) {
                provider.loadFileRepresentation(forTypeIdentifier: UTType.movie.identifier) { url, error in
                    defer { group.leave() }
                    guard let url = url, error == nil,
                          let file = DraftStore.shared.importMedia(from: url, defaultExt: "mov") else { return }
                    let asset = AVAsset(url: DraftStore.shared.mediaURL(file))
                    let dur = floorTicks(asset.duration.secs)
                    guard dur.secs > 0.1, asset.tracks(withMediaType: .video).first != nil else { return }
                    collector.set(idx, VideoClip(asset: asset, file: file, sourceRange: CMTimeRange(start: .zero, duration: dur)))
                }
            } else if provider.canLoadObject(ofClass: UIImage.self) {
                provider.loadObject(ofClass: UIImage.self) { obj, _ in
                    guard let img = obj as? UIImage else { group.leave(); return }
                    // Картинка → клип по умолчанию на 3 секунды (можно растянуть за края)
                    MediaTools.makeStillVideo(image: img) { name in
                        defer { group.leave() }
                        guard let name = name else { return }
                        let asset = AVAsset(url: DraftStore.shared.mediaURL(name))
                        collector.set(idx, VideoClip(asset: asset, file: name, isImage: true,
                                                     sourceRange: CMTimeRange(start: .zero, duration: ticks(3))))
                    }
                }
            } else {
                group.leave()
            }
        }

        group.notify(queue: .main) { [weak self] in
            guard let self = self else { return }
            self.loader.stopAnimating()
            let newClips = collector.ordered()
            guard !newClips.isEmpty else { self.showToast("Не удалось загрузить файлы"); return }
            self.pushUndo()
            let resumeTime = self.clips.isEmpty ? CMTime.zero : ticks(self.displayTime)
            self.clips.append(contentsOf: newClips)
            self.focusLane = .video
            self.rebuild(seekTo: resumeTime)
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
}
