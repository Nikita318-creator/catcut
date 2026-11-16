// MARK: - Controllers/ViewController+Drafts.swift

import UIKit
import AVFoundation
import CoreImage
import CoreMedia
import PhotosUI
import Photos
import UniformTypeIdentifiers
import SnapKit

extension ViewController {

    // MARK: Drafts

    func makeDraft(id: UUID, isAuto: Bool, overlays: [VideoOverlay]) -> Draft {
        let draft = Draft(
            id: id,
            updated: Date(),
            duration: totalSeconds,
            clips: clips.map { c in
                DraftClip(id: c.id, file: c.file, srcStart: c.sourceRange.start.secs,
                          srcDuration: c.sourceRange.duration.secs, speed: c.speed, filterID: c.filterID,
                          filterIntensity: c.filterIntensity, transitionID: c.transitionID,
                          transitionDuration: c.transitionDuration, volume: c.volume,
                          isImage: c.isImage, adjust: c.adjust, look: c.look, flipH: c.flipH, flipV: c.flipV,
                          rotation: c.rotation, zoom: c.zoom, bgMode: c.bgMode, bgFile: c.bgFile, bgColor: c.bgColor,
                          bgDepthThreshold: c.bgDepthThreshold, audioEffect: c.audioEffect,
                          fadeIn: c.fadeIn, fadeOut: c.fadeOut,
                          retouch: c.retouch.isIdentity ? nil : c.retouch)
            },
            texts: texts,
            audios: audios.map { a in
                DraftAudio(id: a.id, file: a.file, title: a.title, start: a.start, sourceOffset: a.sourceOffset,
                           duration: a.duration, volume: a.volume, effect: a.effect, fadeIn: a.fadeIn, fadeOut: a.fadeOut)
            },
            project: project,
            isAutoSaved: isAuto,
            overlays: overlays,
            filterOverlays: filterOverlays
        )
        return draft
    }
    
    func saveDraft(silent: Bool, isAuto: Bool = true) {
        guard !clips.isEmpty else { return }
        
        let id: UUID
        if isAuto {
            // Всегда ищем единственный автосейв в хранилище и перезаписываем его ID.
            let existingAuto = DraftStore.shared.list().first(where: { $0.isAutoSaved == true })
            id = existingAuto?.id ?? currentDraftID ?? UUID()
            currentDraftID = id
        } else {
            // Ручное сохранение по кнопке — только тогда создается/обновляется отдельный ручной черновик
            if currentDraftID == nil || (DraftStore.shared.list().first(where: { $0.id == currentDraftID })?.isAutoSaved == true) {
                currentDraftID = UUID()
            }
            id = currentDraftID!
        }
        
        let draftToSave = makeDraft(id: id, isAuto: isAuto, overlays: overlays)
        let first = clips[0]
        DraftStore.shared.save(draftToSave, coverAsset: first.asset, coverTime: first.sourceRange.start.secs + 0.05)
        
        if !silent { showToast("Черновик сохранён") }
    }
    
    @objc func didTapSaveDraft() {
        guard !clips.isEmpty else { showToast("Добавьте видео, чтобы сохранить черновик"); return }
        // 1. Сохраняем вручную
        saveDraft(silent: false, isAuto: false)
        // 2. Сразу же перезаписываем/обновляем автосейв, не дожидаясь 10 сек
        saveDraft(silent: true, isAuto: true)
    }

    @objc func didTapDrafts() {
        pausePlayback()
        saveDraft(silent: true, isAuto: true)
        let vc = DraftsViewController()
        vc.modalPresentationStyle = .fullScreen
        vc.currentDraftID = currentDraftID
        vc.onOpen = { [weak self] draft in
            self?.dismiss(animated: true) { self?.loadDraft(draft) }
        }
        vc.onNew = { [weak self] in self?.newProject() }
        vc.onDeleted = { [weak self] id in
            if self?.currentDraftID == id { self?.currentDraftID = nil }
        }
        present(vc, animated: true)
    }

    func newProject() {
        pausePlayback()
        closePanel()
        clips = []; texts = []; audios = []; overlays = []; filterOverlays = []
        selectedFilterOverlayID = nil
        project = ProjectSettings()
        clearSelection()
        focusLane = .video
        undoStack = []
        updateUndoRedoButtons()
        currentDraftID = nil
        filterPreviewClipID = nil
        previewPairKey = nil
        rebuild(seekTo: .zero)
    }

    func loadDraft(_ d: Draft) {
        pausePlayback()
        closePanel()
        var loadedClips: [VideoClip] = []
        for c in d.clips {
            let url = DraftStore.shared.mediaURL(c.file)
            guard FileManager.default.fileExists(atPath: url.path) else { continue }
            var clip = VideoClip(asset: AVAsset(url: url), file: c.file, isImage: c.isImage ?? false,
                                 sourceRange: CMTimeRange(start: ticks(c.srcStart), duration: ticks(c.srcDuration)))
            clip.id = c.id
            clip.speed = c.speed
            clip.filterID = c.filterID ?? 0
            clip.filterIntensity = c.filterIntensity
            clip.adjust = c.adjust ?? Adjustments()
            clip.look = c.look ?? 0
            clip.flipH = c.flipH ?? false
            clip.flipV = c.flipV ?? false
            clip.rotation = c.rotation ?? 0
            clip.zoom = c.zoom ?? 1
            clip.bgMode = c.bgMode ?? 0
            clip.bgFile = c.bgFile
            clip.bgColor = c.bgColor ?? 0
            clip.bgDepthThreshold = c.bgDepthThreshold ?? 0.5
            clip.transitionID = c.transitionID
            clip.transitionDuration = c.transitionDuration
            clip.volume = c.volume
            clip.audioEffect = c.audioEffect ?? 0
            clip.fadeIn = c.fadeIn ?? 0
            clip.fadeOut = c.fadeOut ?? 0
            clip.retouch = c.retouch ?? RetouchSettings()
            loadedClips.append(clip)
        }
        var loadedAudios: [AudioClip] = []
        for a in d.audios {
            let url = DraftStore.shared.mediaURL(a.file)
            guard FileManager.default.fileExists(atPath: url.path) else { continue }
            let asset = AVAsset(url: url)
            let srcDur = floor(asset.duration.secs * Double(kTimescale)) / Double(kTimescale)
            var clip = AudioClip(asset: asset, file: a.file, title: a.title, start: a.start,
                                 sourceOffset: a.sourceOffset, duration: a.duration, sourceDuration: srcDur)
            clip.id = a.id
            clip.volume = a.volume
            clip.effect = a.effect ?? 0
            clip.fadeIn = a.fadeIn ?? 0
            clip.fadeOut = a.fadeOut ?? 0
            loadedAudios.append(clip)
        }
        let loadedOverlays: [VideoOverlay] = (d.overlays ?? []).filter {
            FileManager.default.fileExists(atPath: DraftStore.shared.mediaURL($0.file).path)
        }
        clips = loadedClips
        texts = d.texts
        audios = loadedAudios
        overlays = loadedOverlays
        filterOverlays = d.filterOverlays ?? []
        selectedFilterOverlayID = nil
        project = d.project ?? ProjectSettings()
        clearSelection()
        focusLane = .video
        undoStack = []
        updateUndoRedoButtons()
        currentDraftID = d.id
        filterPreviewClipID = nil
        previewPairKey = nil
        rebuild(seekTo: .zero)
        if loadedClips.count < d.clips.count || loadedOverlays.count < (d.overlays?.count ?? 0) {
            showToast("Часть файлов черновика не найдена")
        }
    }
}
