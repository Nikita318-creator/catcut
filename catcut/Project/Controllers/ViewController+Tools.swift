// MARK: - Controllers/ViewController+Tools.swift

import UIKit
import AVFoundation
import CoreImage
import CoreMedia
import PhotosUI
import Photos
import UniformTypeIdentifiers
import SnapKit

extension ViewController {

    // MARK: Tools

    func requireClips() -> Bool {
        if clips.isEmpty { showToast("Сначала добавьте видео") }
        return !clips.isEmpty
    }

    func handleTool(_ tool: EditorTool) {
        switch tool {
        case .addVideo:
            pickerPurpose = .clips
            didTapAddVideo()
        case .split: splitAtPlayhead()
        case .delete: deleteCurrent()
        case .duplicate: duplicateCurrent()
        case .speed: openClipPanel(.speed)
        case .filter: openClipPanel(.filter)
        case .adjust: openClipPanel(.adjust)
        case .transition: openTransitionPanel()
        case .animation:
            guard requireClips() else { return }
            openPanel(.animation)
        case .effects: openClipPanel(.effects)
        case .frame:
            guard requireClips() else { return }
            openPanel(.frame)
        case .background: openClipPanel(.background)
        case .text:
            guard requireClips() else { return }
            focusLane = .text
            reloadTimeline()
            textTab = .text
            openPanel(.text)
            if texts.isEmpty { presentTextInput(editing: nil) }
        case .audio:
            guard requireClips() else { return }
            focusLane = .audio
            reloadTimeline()
            audioTab = 0
            openPanel(.audio)
        }
    }

    func openClipPanel(_ kind: PanelKind) {
        guard requireClips() else { return }
        if selectedClipIndex == nil {
            let i = currentClipIndex()
            clearSelection()
            selectedClipIndex = i
        }
        focusLane = .video
        if let i = selectedClipIndex, clips.count > 1 { transitionBoundary = min(i, clips.count - 2) }
        reloadTimeline()
        openPanel(kind)
    }

    func openTransitionPanel() {
        guard clips.count >= 2, let b = build else {
            showToast("Для перехода нужно минимум 2 клипа — разрежьте видео или добавьте ещё")
            return
        }
        var bestJ = 0
        var bestDist = Double.infinity
        for j in 0..<(clips.count - 1) {
            let d = abs(displayTime - b.layout.starts[j + 1].secs)
            if d < bestDist { bestDist = d; bestJ = j }
        }
        if let s = selectedClipIndex { bestJ = min(s, clips.count - 2) }
        transitionBoundary = bestJ
        clearSelection()
        focusLane = .video
        selectedClipIndex = bestJ
        reloadTimeline()
        openPanel(.transition)
    }

    // MARK: Split / delete / duplicate (работают с той дорожкой, на которой фокус)

    func splitAtPlayhead() {
        guard requireClips() else { return }
        switch focusLane {
        case .video: splitVideo()
        case .text: splitText()
        case .audio: splitAudio()
        }
    }

    func textIndexAtPlayhead() -> Int? {
        let t = displayTime
        if let id = selectedTextID, let i = texts.firstIndex(where: { $0.id == id }),
           t > texts[i].start, t < texts[i].start + texts[i].duration { return i }
        return texts.lastIndex { t > $0.start && t < $0.start + $0.duration }
    }

    func audioIndexAtPlayhead() -> Int? {
        let t = displayTime
        if let id = selectedAudioID, let i = audios.firstIndex(where: { $0.id == id }),
           t > audios[i].start, t < audios[i].start + audios[i].duration { return i }
        return audios.lastIndex { t > $0.start && t < $0.start + $0.duration }
    }

    func splitText() {
        let t = displayTime
        guard let i = textIndexAtPlayhead(), t - texts[i].start > 0.2, texts[i].start + texts[i].duration - t > 0.2 else {
            showToast("Поставьте красную палку внутрь текста на дорожке текста")
            return
        }
        pushUndo()
        let o = texts[i]
        var second = o
        second.id = UUID()
        second.start = t
        second.duration = o.start + o.duration - t
        texts[i].duration = t - o.start
        texts.append(second)
        textsChanged()
    }

    func splitAudio() {
        let t = displayTime
        guard let i = audioIndexAtPlayhead(), t - audios[i].start > 0.2, audios[i].start + audios[i].duration - t > 0.2 else {
            showToast("Поставьте красную палку внутрь аудио на дорожке аудио")
            return
        }
        pushUndo()
        let a = audios[i]
        var second = a
        second.id = UUID()
        second.start = t
        second.sourceOffset = a.sourceOffset + (t - a.start)
        second.duration = a.start + a.duration - t
        second.fadeIn = 0
        audios[i].duration = t - a.start
        audios[i].fadeOut = 0
        audios.append(second)
        rebuild()
        refreshActivePanel()
    }

    func splitVideo() {
        guard let b = build else { return }
        let t = displayTime

        var idx: Int?
        if let s = selectedClipIndex, s < b.layout.starts.count,
           t >= b.layout.starts[s].secs, t <= b.layout.end(of: s).secs {
            idx = s
        } else {
            idx = b.layout.index(at: ticks(t))
        }
        guard let i = idx else { return }

        let clip = clips[i]
        let offset = t - b.layout.starts[i].secs
        let dur = b.layout.durations[i].secs
        guard offset > 0.2, dur - offset > 0.2 else {
            showToast("Поставьте красную палку внутрь клипа")
            return
        }

        let srcOffset = ticks(offset * Double(clip.speed))
        pushUndo()

        var first = clip
        first.sourceRange = CMTimeRange(start: clip.sourceRange.start, duration: srcOffset)
        first.transitionID = 0
        first.fadeOut = 0

        var second = clip   // у второй половины свой id → свои независимые фильтр/переход/скорость/звук
        second.id = UUID()
        second.sourceRange = CMTimeRange(start: clip.sourceRange.start + srcOffset,
                                         duration: clip.sourceRange.duration - srcOffset)
        second.fadeIn = 0

        clips[i] = first
        clips.insert(second, at: i + 1)
        clearSelection()
        rebuild(seekTo: ticks(t))
        refreshActivePanel()
    }

    func deleteCurrent() {
        if let id = selectedTextID {
            pushUndo()
            texts.removeAll { $0.id == id }
            selectedTextID = nil
            textsChanged()
            return
        }
        if let id = selectedAudioID {
            pushUndo()
            audios.removeAll { $0.id == id }
            selectedAudioID = nil
            rebuild()
            refreshActivePanel()
            return
        }
        switch focusLane {
        case .text:
            guard let i = textIndexAtPlayhead() else { showToast("Выберите текст на дорожке"); return }
            pushUndo()
            texts.remove(at: i)
            textsChanged()
        case .audio:
            guard let i = audioIndexAtPlayhead() else { showToast("Выберите аудио на дорожке"); return }
            pushUndo()
            audios.remove(at: i)
            rebuild()
            refreshActivePanel()
        case .video:
            guard let i = currentClipIndex() else { showToast("Нечего удалять"); return }
            pushUndo()
            clips.remove(at: i)
            clearSelection()
            filterPreviewClipID = nil
            rebuild()
            refreshActivePanel()
        }
    }

    func duplicateCurrent() {
        switch focusLane {
        case .text:
            guard let i = selectedTextID.flatMap({ id in texts.firstIndex { $0.id == id } }) ?? textIndexAtPlayhead() else {
                showToast("Выберите текст на дорожке"); return
            }
            pushUndo()
            var copy = texts[i]
            copy.id = UUID()
            copy.position.y = min(0.95, copy.position.y + 0.08)
            texts.append(copy)
            clearSelection()
            selectedTextID = copy.id
            textsChanged()
        case .audio:
            guard let i = selectedAudioID.flatMap({ id in audios.firstIndex { $0.id == id } }) ?? audioIndexAtPlayhead() else {
                showToast("Выберите аудио на дорожке"); return
            }
            let a = audios[i]
            guard a.start + a.duration + 0.3 < totalSeconds else { showToast("Нет места после аудио"); return }
            pushUndo()
            var copy = a
            copy.id = UUID()
            copy.start = a.start + a.duration
            copy.duration = min(a.duration, totalSeconds - copy.start)
            audios.append(copy)
            clearSelection()
            selectedAudioID = copy.id
            rebuild()
        case .video:
            guard let i = currentClipIndex() else { showToast("Сначала добавьте видео"); return }
            pushUndo()
            var copy = clips[i]
            copy.id = UUID()
            copy.transitionID = 0
            clips.insert(copy, at: i + 1)
            clearSelection()
            selectedClipIndex = i + 1
            rebuild()
        }
    }

    // MARK: Timeline commits (перетаскивание / обрезка за края)

    func commitClipTrim(_ i: Int, _ range: CMTimeRange) {
        guard i < clips.count else { return }
        pushUndo()
        clips[i].sourceRange = range
        clearSelection()
        selectedClipIndex = i
        filterPreviewClipID = nil
        rebuild()
        refreshActivePanel()
    }

    func commitTextTime(_ id: UUID, start: Double, duration: Double) {
        guard let idx = texts.firstIndex(where: { $0.id == id }) else { return }
        pushUndo()
        texts[idx].start = start
        texts[idx].duration = duration
        clearSelection()
        selectedTextID = id
        textsChanged()
    }

    func commitAudioTime(_ id: UUID, start: Double, offset: Double, duration: Double) {
        guard let idx = audios.firstIndex(where: { $0.id == id }) else { return }
        pushUndo()
        audios[idx].start = start
        audios[idx].sourceOffset = offset
        audios[idx].duration = duration
        clearSelection()
        selectedAudioID = id
        rebuild()
        refreshActivePanel()
    }
}
