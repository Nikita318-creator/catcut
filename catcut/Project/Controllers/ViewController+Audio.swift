// MARK: - Controllers/ViewController+Audio.swift

import UIKit
import AVFoundation
import CoreImage
import CoreMedia
import PhotosUI
import Photos
import UniformTypeIdentifiers
import SnapKit

extension ViewController {

    // MARK: Audio panel

    enum AudioTarget { case audio(Int), clip(Int) }

    func audioTarget() -> AudioTarget? {
        if let id = selectedAudioID, let i = audios.firstIndex(where: { $0.id == id }) { return .audio(i) }
        if let i = currentClipIndex() { return .clip(i) }
        return nil
    }

    func refreshAudioPanel(_ keep: Bool) {
        let target = audioTarget()
        var items: [PanelItem] = []
        var sel: Int?
        var cfg: SliderConfig?
        var name = "Звук"
        var volume: Float = 1, effect = 0, fadeIn = 0.0, fadeOut = 0.0
        var isImageClip = false
        switch target {
        case .audio(let i)?:
            let a = audios[i]; name = "Аудио · \(a.title)"
            volume = a.volume; effect = a.effect; fadeIn = a.fadeIn; fadeOut = a.fadeOut
        case .clip(let i)?:
            let c = clips[i]; name = "Звук видео · клип \(i + 1)"
            volume = c.volume; effect = c.audioEffect; fadeIn = c.fadeIn; fadeOut = c.fadeOut
            isImageClip = c.isImage
        case nil:
            break
        }
        switch audioTab {
        case 0:
            var clipMuted = false
            if case .clip? = target { clipMuted = volume == 0 }
            items = [
                PanelItem(title: "Файл аудио", symbol: "music.note"),
                PanelItem(title: "Звук из видео", symbol: "film"),
                PanelItem(title: "Удалить аудио", symbol: "trash"),
                PanelItem(title: "Выкл. звук этого клипа", symbol: "speaker.slash.fill", on: clipMuted),
                PanelItem(title: "Выкл. звук всех клипов", symbol: "speaker.slash"),
                PanelItem(title: "Вкл. звук всех клипов", symbol: "speaker.wave.2.fill")
            ]
        case 1:
            items = [PanelItem(title: "100%", badge: "100%"), PanelItem(title: "150%", badge: "150%"),
                     PanelItem(title: "200%", badge: "200%"), PanelItem(title: "Тишина", badge: "0%")]
            cfg = SliderConfig(title: "Громкость", min: 0, max: 3, value: volume) { "\(Int($0 * 100))%" }
        case 2:
            items = AudioEffect.allCases.map { PanelItem(title: $0.title, symbol: $0.symbol) }
            sel = effect
            // Если выбран какой-то эффект (не 0), показываем ползунок его мощности:
            if effect != 0 {
                let currentIntensity = (target.map { t in
                    switch t {
                    case .audio(let i): return Double(audios[i].effectIntensity)
                    case .clip(let i): return Double(clips[i].audioEffectIntensity)
                    }
                }) ?? 0.5
                cfg = SliderConfig(title: "Мощность эффекта", min: 0.1, max: 1.0, value: Float(currentIntensity)) { "\(Int($0 * 100))%" }
            }
        case 3:
            items = [PanelItem(title: "Без появления", symbol: "xmark")]
            cfg = SliderConfig(title: "Появление", min: 0, max: 5, value: Float(fadeIn)) { String(format: "%.1fс", Double($0)) }
        default:
            items = [PanelItem(title: "Без затухания", symbol: "xmark")]
            cfg = SliderConfig(title: "Затухание", min: 0, max: 5, value: Float(fadeOut)) { String(format: "%.1fс", Double($0)) }
        }
        if isImageClip && audioTab != 0 { name = "У картинки нет звука" }
        panel.configure(title: name, items: items, selected: sel, slider: cfg,
                        chips: ["Звук", "Громкость", "Эффекты", "Появление", "Затухание"], selectedChip: audioTab, keepScroll: keep)
    }

    func setAudioParam(_ f: (inout Float, inout Int, inout Double, inout Double) -> Void) {
        guard let target = audioTarget() else { return }
        pushUndo()
        switch target {
        case .audio(let i):
            var v = audios[i].volume, e = audios[i].effect, fi = audios[i].fadeIn, fo = audios[i].fadeOut
            f(&v, &e, &fi, &fo)
            if e != audios[i].effect { audios[i].processed = nil }
            audios[i].volume = v; audios[i].effect = e; audios[i].fadeIn = fi; audios[i].fadeOut = fo
        case .clip(let i):
            var v = clips[i].volume, e = clips[i].audioEffect, fi = clips[i].fadeIn, fo = clips[i].fadeOut
            f(&v, &e, &fi, &fo)
            if e != clips[i].audioEffect { clips[i].processedAudio = nil }
            clips[i].volume = v; clips[i].audioEffect = e; clips[i].fadeIn = fi; clips[i].fadeOut = fo
        }
        rebuild()
        refreshActivePanel()
    }

    func handleAudioSelect(_ index: Int) {
        switch audioTab {
        case 0:
            switch index {
            case 0:
                guard totalSeconds > 0.2 else { showToast("Сначала добавьте видео"); return }
                let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.audio], asCopy: true)
                picker.delegate = self
                present(picker, animated: true)
            case 1:
                guard totalSeconds > 0.2 else { showToast("Сначала добавьте видео"); return }
                pickerPurpose = .audioFromVideo
                var config = PHPickerConfiguration()
                config.filter = .videos
                config.selectionLimit = 1
                let picker = PHPickerViewController(configuration: config)
                picker.delegate = self
                present(picker, animated: true)
            case 2:
                guard let id = selectedAudioID else { showToast("Выберите аудио на дорожке аудио"); return }
                pushUndo()
                audios.removeAll { $0.id == id }
                selectedAudioID = nil
                rebuild()
                refreshActivePanel()
            case 3:
                guard let i = currentClipIndex() else { return }
                pushUndo()
                clips[i].volume = clips[i].volume > 0 ? 0 : 1
                rebuild()
                refreshActivePanel()
            case 4:
                pushUndo()
                for k in 0..<clips.count { clips[k].volume = 0 }
                rebuild()
                refreshActivePanel()
                showToast("Звук всех клипов выключен")
            default:
                pushUndo()
                for k in 0..<clips.count { clips[k].volume = 1 }
                rebuild()
                refreshActivePanel()
            }
        case 1:
            let values: [Float] = [1, 1.5, 2, 0]
            setAudioParam { v, _, _, _ in v = values[min(index, values.count - 1)] }
        case 2:
            setAudioParam { _, e, _, _ in e = index }
        case 3:
            setAudioParam { _, _, fi, _ in fi = 0 }
        default:
            setAudioParam { _, _, _, fo in fo = 0 }
        }
    }

    /// Запускает обработку звука эффектами (в фоне), после — пересобирает композицию.
    func ensureProcessedAudio() {
        for c in clips where c.audioEffect != 0 && c.processedAudio == nil {
            guard let eff = AudioEffect(rawValue: c.audioEffect) else { continue }
            let key = "c-\(c.id)-\(c.audioEffect)-\(Int(c.audioEffectIntensity * 10))"
            guard !processingKeys.contains(key) else { continue }
            processingKeys.insert(key)
            showToast("Обработка звука…")
            let id = c.id
            let intensity = c.audioEffectIntensity
            AudioFXStore.process(asset: c.asset, effect: eff, intensity: intensity) { [weak self] result in
                guard let self = self else { return }
                self.processingKeys.remove(key)
                guard let result = result, let i = self.clips.firstIndex(where: { $0.id == id }),
                      self.clips[i].audioEffect == eff.rawValue else { return }
                self.clips[i].processedAudio = result
                self.rebuild()
            }
        }
        for a in audios where a.effect != 0 && a.processed == nil {
            guard let eff = AudioEffect(rawValue: a.effect) else { continue }
            let key = "a-\(a.id)-\(a.effect)-\(Int(a.effectIntensity * 10))"
            guard !processingKeys.contains(key) else { continue }
            processingKeys.insert(key)
            showToast("Обработка звука…")
            let id = a.id
            let intensity = a.effectIntensity
            AudioFXStore.process(asset: a.asset, effect: eff, intensity: intensity) { [weak self] result in
                guard let self = self else { return }
                self.processingKeys.remove(key)
                guard let result = result, let i = self.audios.firstIndex(where: { $0.id == id }),
                      self.audios[i].effect == eff.rawValue else { return }
                self.audios[i].processed = result
                self.rebuild()
            }
        }
    }

    // MARK: Audio import

    func addAudio(importedFile file: String, title: String) {
        guard totalSeconds > 0.2 else { showToast("Сначала добавьте видео"); return }
        let asset = AVAsset(url: DraftStore.shared.mediaURL(file))
        let srcDur = floor(asset.duration.secs * Double(kTimescale)) / Double(kTimescale)
        guard asset.tracks(withMediaType: .audio).first != nil, srcDur > 0.2 else {
            showToast("В файле нет звука")
            return
        }
        let start = min(displayTime, max(0, totalSeconds - 0.5))
        let dur = min(srcDur, totalSeconds - start)
        let a = AudioClip(asset: asset, file: file, title: title, start: start, duration: dur, sourceDuration: srcDur)
        pushUndo()
        audios.append(a)
        clearSelection()
        focusLane = .audio
        selectedAudioID = a.id
        rebuild()
        refreshActivePanel()
    }

    /// Звук из видео из галереи → становится аудио-дорожкой.
    func extractAudio(_ results: [PHPickerResult]) {
        guard let r = results.first else { return }
        loader.startAnimating()
        r.itemProvider.loadFileRepresentation(forTypeIdentifier: UTType.movie.identifier) { [weak self] url, _ in
            var name: String?
            if let url = url { name = DraftStore.shared.importMedia(from: url, defaultExt: "mov") }
            DispatchQueue.main.async {
                self?.loader.stopAnimating()
                guard let name = name else { self?.showToast("Не удалось загрузить видео"); return }
                self?.addAudio(importedFile: name, title: "Звук из видео")
            }
        }
    }

    func loadBackgroundPhoto(_ results: [PHPickerResult]) {
        guard let r = results.first, r.itemProvider.canLoadObject(ofClass: UIImage.self) else { return }
        r.itemProvider.loadObject(ofClass: UIImage.self) { [weak self] obj, _ in
            DispatchQueue.main.async {
                if let img = obj as? UIImage { self?.setBackgroundPhoto(img) }
            }
        }
    }
}
