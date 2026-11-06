// MARK: - Controllers/ViewController+Panels.swift

import UIKit
import AVFoundation
import CoreImage
import CoreMedia
import PhotosUI
import Photos
import UniformTypeIdentifiers
import SnapKit

extension ViewController {

    // MARK: Bottom panel

    func openPanel(_ kind: PanelKind) {
        activePanel = kind
        if kind == .filter { updateFilterPreviews() }
        toolCollection.isHidden = true
        panel.isHidden = false
        refreshActivePanel(keepScroll: false)
    }

    func closePanel() {
        activePanel = nil
        panel.isHidden = true
        toolCollection.isHidden = false
        setBottomHeight(toolBarHeight)
    }

    func setBottomHeight(_ h: CGFloat) {
        guard bottomHeightConstraint.constant != h else { return }
        bottomHeightConstraint.constant = h
        UIView.animate(withDuration: 0.25) { self.view.layoutIfNeeded() }
    }

    func refreshActivePanel(keepScroll: Bool = true) {
        guard let kind = activePanel else { return }
        switch kind {
        case .speed: refreshSpeedPanel(keepScroll)
        case .filter: refreshFilterPanel(keepScroll)
        case .adjust: refreshAdjustPanel(keepScroll)
        case .transition: refreshTransitionPanel(keepScroll)
        case .animation: refreshAnimationPanel(keepScroll)
        case .effects: refreshEffectsPanel(keepScroll)
        case .frame: refreshFramePanel(keepScroll)
        case .background: refreshBackgroundPanel(keepScroll)
        case .text: refreshTextPanel(keepScroll: keepScroll)
        case .audio: refreshAudioPanel(keepScroll)
        }
        if activePanel != nil { setBottomHeight(panel.preferredHeight) }
    }

    // MARK: Speed

    var speedPresets: [Float] { [0.25, 0.5, 0.75, 1, 1.25, 1.5, 2, 3, 4, 6, 8] }

    func refreshSpeedPanel(_ keep: Bool) {
        guard let i = currentClipIndex() else { closePanel(); return }
        let items = speedPresets.map { PanelItem(title: $0 == 1 ? "Обычная" : "\($0)x", badge: String(format: "%gx", Double($0))) }
        let sel = speedPresets.firstIndex { abs($0 - clips[i].speed) < 0.001 }
        let cfg = SliderConfig(title: "Скорость", min: 0.1, max: 8, value: clips[i].speed) { String(format: "%.2fx", Double($0)) }
        panel.configure(title: "Скорость · клип \(i + 1)", items: items, selected: sel, slider: cfg, keepScroll: keep)
    }

    // MARK: Filters

    func refreshFilterPanel(_ keep: Bool) {
        guard let i = currentClipIndex() else { closePanel(); return }
        let ids = FilterCatalog.ids(for: filterCategory)
        var items = [PanelItem(title: "Оригинал", symbol: filterPreviews[0] == nil ? "camera.filters" : nil, image: filterPreviews[0])]
        for id in ids {
            let name = FilterCatalog.preset(id)?.name ?? ""
            items.append(PanelItem(title: name, symbol: filterPreviews[id] == nil ? "camera.filters" : nil, image: filterPreviews[id]))
        }
        let cur = clips[i].filterID
        let sel: Int? = cur == 0 ? 0 : ids.firstIndex(of: cur).map { $0 + 1 }
        let cfg = SliderConfig(title: "Сила", min: 0, max: 1, value: clips[i].filterIntensity) { "\(Int($0 * 100))%" }
        panel.configure(title: "Фильтр · клип \(i + 1)", items: items, selected: sel,
                        slider: cur == 0 ? nil : cfg,
                        chips: FilterCategory.allCases.map { $0.title }, selectedChip: filterCategory.rawValue,
                        keepScroll: keep)
    }

    func updateFilterPreviews() {
        guard let i = currentClipIndex() else { return }
        let clip = clips[i]
        if filterPreviewClipID == clip.id, !filterPreviews.isEmpty { return }
        filterPreviewClipID = clip.id
        filterPreviews = [:]

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let gen = AVAssetImageGenerator(asset: clip.asset)
            gen.appliesPreferredTrackTransform = true
            gen.maximumSize = CGSize(width: 160, height: 160)
            let mid = clip.sourceRange.start + CMTimeMultiplyByFloat64(clip.sourceRange.duration, multiplier: 0.5)
            guard let cg = try? gen.copyCGImage(at: mid, actualTime: nil) else { return }
            let base = CIImage(cgImage: cg)
            var result: [Int: UIImage] = [:]
            for id in 0...FilterCatalog.all.count {
                let out = id == 0 ? base : (FilterCatalog.preset(id)?.adjust.apply(to: base) ?? base)
                if let o = EditorCompositor.ciContext.createCGImage(out, from: base.extent) {
                    result[id] = UIImage(cgImage: o)
                }
            }
            DispatchQueue.main.async {
                self?.filterPreviews = result
                if self?.activePanel == .filter { self?.refreshActivePanel() }
            }
        }
    }

    // MARK: Custom color adjustments

    typealias AdjustDef = (title: String, path: WritableKeyPath<Adjustments, Double>?, min: Double, max: Double)

    static let adjustDefs: [AdjustDef] = [
        ("Яркость", \Adjustments.brightness, -1, 1), ("Контраст", \Adjustments.contrast, -1, 1),
        ("Насыщ.", \Adjustments.saturation, -1, 1), ("Сочность", \Adjustments.vibrance, -1, 1),
        ("Тепло", \Adjustments.warmth, -1, 1), ("Оттенок", \Adjustments.tint, -1, 1),
        ("Света", \Adjustments.highlights, -1, 1), ("Тени", \Adjustments.shadows, -1, 1),
        ("Кривая тени", \Adjustments.curveShadows, -1, 1), ("Кривая средн.", \Adjustments.curveMid, -1, 1),
        ("Кривая света", \Adjustments.curveHigh, -1, 1), ("Цвет", \Adjustments.hue, -1, 1),
        ("Матовость", \Adjustments.fade, 0, 1), ("Резкость", \Adjustments.sharpen, 0, 1),
        ("Виньетка", \Adjustments.vignette, 0, 1), ("Шум", \Adjustments.grain, 0, 1),
        ("Ретушь", \Adjustments.retouch, 0, 1), ("Свечение", \Adjustments.glow, 0, 1),
        ("Размытие", \Adjustments.blur, 0, 1),
        ("Тон теней", \Adjustments.shadowTone, 0, 1), ("Сила теней", \Adjustments.shadowToneAmount, 0, 1),
        ("Тон светов", \Adjustments.highTone, 0, 1), ("Сила светов", \Adjustments.highToneAmount, 0, 1),
        ("HSL оттенок", nil, -1, 1), ("HSL насыщ.", nil, -1, 1), ("HSL яркость", nil, -1, 1)
    ]
    static let hslFirstTab = 23

    func adjustValue(_ a: Adjustments) -> Double {
        let def = ViewController.adjustDefs[adjustTab]
        if let p = def.path { return a[keyPath: p] }
        return a.hsl[hslChannel * 3 + (adjustTab - ViewController.hslFirstTab)]
    }

    func setAdjustValue(_ v: Double, _ a: inout Adjustments) {
        let def = ViewController.adjustDefs[adjustTab]
        if let p = def.path { a[keyPath: p] = v } else { a.hsl[hslChannel * 3 + (adjustTab - ViewController.hslFirstTab)] = v }
    }

    func refreshAdjustPanel(_ keep: Bool) {
        guard let i = currentClipIndex() else { closePanel(); return }
        adjustTab = max(0, min(adjustTab, ViewController.adjustDefs.count - 1))
        let def = ViewController.adjustDefs[adjustTab]
        var items: [PanelItem] = []
        var sel: Int?
        if def.path == nil {
            for k in 0..<8 { items.append(PanelItem(title: HSLChannel.titles[k], swatch: HSLChannel.colors[k])) }
            items.append(PanelItem(title: "Сбросить", symbol: "arrow.counterclockwise"))
            sel = hslChannel
        } else {
            items = [PanelItem(title: "Сбросить это", symbol: "arrow.counterclockwise"),
                     PanelItem(title: "Сбросить всё", symbol: "xmark")]
        }
        let value = adjustValue(clips[i].adjust)
        let cfg = SliderConfig(title: def.title, min: Float(def.min), max: Float(def.max), value: Float(value)) {
            def.min < 0 ? String(format: "%+.0f", Double($0) * 100) : String(format: "%.0f", Double($0) * 100)
        }
        panel.configure(title: "Цвет · клип \(i + 1)", items: items, selected: sel, slider: cfg,
                        chips: ViewController.adjustDefs.map { $0.title }, selectedChip: adjustTab, keepScroll: keep)
    }

    func handleAdjustSelect(_ index: Int) {
        guard let i = currentClipIndex() else { return }
        let isHSL = ViewController.adjustDefs[adjustTab].path == nil
        if isHSL {
            if index < 8 { hslChannel = index; refreshActivePanel() ; return }
            pushUndo()
            clips[i].adjust.hsl = Array(repeating: 0, count: 24)
        } else {
            pushUndo()
            if index == 0 { var a = clips[i].adjust; setAdjustValue(0, &a); clips[i].adjust = a }
            else { clips[i].adjust = Adjustments() }
        }
        refreshVideoComposition()
        reloadTimeline()
        refreshActivePanel()
    }

    // MARK: Transitions

    func refreshTransitionPanel(_ keep: Bool) {
        guard clips.count >= 2 else { closePanel(); return }
        let j = min(transitionBoundary, clips.count - 2)
        transitionBoundary = j
        updateTransitionPreviewFrames()
        let list = TransitionCatalog.list(transitionCategory)
        var items = [PanelItem(title: "Нет", symbol: "xmark"), PanelItem(title: "Случайный", symbol: "shuffle")]
        items += list.map {
            PanelItem(title: $0.name, symbol: $0.category.symbol, previewKey: "t\($0.id)", favorite: TransitionFavorites.contains($0.id))
        }
        let curID = clips[j].transitionID
        let sel: Int? = curID == 0 ? 0 : list.firstIndex(where: { $0.id == curID }).map { $0 + 2 }
        let cfg = SliderConfig(title: "Длительность", min: 0.2, max: 1.5, value: Float(clips[j].transitionDuration)) {
            String(format: "%.1fс", Double($0))
        }
        let curName = TransitionCatalog.spec(curID)?.name ?? "нет"
        panel.configure(title: "\(j + 1)→\(j + 2) · \(curName)", items: items, selected: sel,
                        slider: curID == 0 ? nil : cfg,
                        chips: TransitionCategory.allCases.map { "\($0.title) \(TransitionCatalog.list($0).count)" },
                        selectedChip: transitionCategory.rawValue,
                        extra: curID == 0 ? nil : "Ко всем", keepScroll: keep)
    }

    func toggleFavorite(_ index: Int) {
        guard activePanel == .transition, index >= 2 else { return }
        let list = TransitionCatalog.list(transitionCategory)
        guard index - 2 < list.count else { return }
        let nowFav = TransitionFavorites.toggle(list[index - 2].id)
        showToast(nowFav ? "Добавлено в избранное ♥" : "Убрано из избранного")
        refreshActivePanel()
    }

    func handlePanelExtra() {
        switch activePanel {
        case .transition?: applyTransitionToAll()
        case .background?: applyBackgroundToAll()
        default: break
        }
    }

    /// Кадры «конец клипа A» и «начало клипа B» — на них строятся превью всех переходов.
    func updateTransitionPreviewFrames() {
        guard clips.count >= 2 else { return }
        let j = min(transitionBoundary, clips.count - 2)
        let a = clips[j], b = clips[j + 1]
        let key = "\(a.id)-\(a.sourceRange.end.value)-\(b.id)-\(b.sourceRange.start.value)"
        if key == previewPairKey { return }
        previewPairKey = key

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            func frame(_ c: VideoClip, atEnd: Bool) -> CGImage? {
                let g = AVAssetImageGenerator(asset: c.asset)
                g.appliesPreferredTrackTransform = true
                g.maximumSize = CGSize(width: 240, height: 240)
                g.requestedTimeToleranceBefore = .positiveInfinity
                g.requestedTimeToleranceAfter = .positiveInfinity
                let s = c.sourceRange.start.secs, e = c.sourceRange.end.secs
                let t = atEnd ? max(s, e - 0.15) : min(e, s + 0.15)
                return try? g.copyCGImage(at: CMTime(seconds: t, preferredTimescale: 600), actualTime: nil)
            }
            let f = frame(a, atEnd: true)
            let t = frame(b, atEnd: false)
            DispatchQueue.main.async {
                guard let self = self, self.previewPairKey == key else { return }
                TransitionPreviewStore.shared.setFrames(from: f, to: t)
                if self.activePanel == .transition { self.refreshActivePanel() }
            }
        }
    }

    // MARK: Intro / outro animation

    func refreshAnimationPanel(_ keep: Bool) {
        let isIntro = animTab == 0
        let cur = isIntro ? project.introID : project.outroID
        var items = [PanelItem(title: "Нет", symbol: "xmark")]
        items += TransitionCatalog.all.map { PanelItem(title: $0.name, symbol: $0.category.symbol) }
        let dur = isIntro ? project.introDuration : project.outroDuration
        let cfg = SliderConfig(title: "Длительность", min: 0.2, max: 2.5, value: Float(dur)) { String(format: "%.1fс", Double($0)) }
        panel.configure(title: isIntro ? "Появление видео в начале" : "Затухание видео в конце",
                        items: items, selected: cur, slider: cur == 0 ? nil : cfg,
                        chips: ["Начало видео", "Конец видео"], selectedChip: animTab, keepScroll: keep)
    }

    func handleAnimationSelect(_ index: Int) {
        pushUndo()
        if animTab == 0 { project.introID = index } else { project.outroID = index }
        refreshVideoComposition()
        refreshActivePanel()
        let total = totalSeconds
        if animTab == 0 {
            playRange(from: 0, until: project.introDuration + 0.6)
        } else {
            playRange(from: max(0, total - project.outroDuration - 0.8), until: total)
        }
    }

    // MARK: Effects (отражение, поворот, зум, реверс, заморозка)

    func refreshEffectsPanel(_ keep: Bool) {
        guard let i = currentClipIndex() else { closePanel(); return }
        let c = clips[i]
        var items: [PanelItem] = []
        var sel: Int?
        var cfg: SliderConfig?
        switch fxTab {
        case 0:
            items = [
                PanelItem(title: "Отразить ↔", symbol: "arrow.left.and.right", on: c.flipH),
                PanelItem(title: "Отразить ↕", symbol: "arrow.up.and.down", on: c.flipV),
                PanelItem(title: "Влево 90°", symbol: "rotate.left"),
                PanelItem(title: "Вправо 90°", symbol: "rotate.right"),
                PanelItem(title: "Сбросить", symbol: "arrow.counterclockwise")
            ]
        case 1:
            items = [PanelItem(title: "Сбросить угол", symbol: "arrow.counterclockwise")]
            cfg = SliderConfig(title: "Угол", min: -180, max: 180, value: Float(c.rotation)) { String(format: "%.0f°", Double($0)) }
        case 2:
            items = [PanelItem(title: "Сбросить", symbol: "arrow.counterclockwise")]
            cfg = SliderConfig(title: "Масштаб", min: 0.5, max: 3, value: Float(c.zoom)) { String(format: "%.2fx", Double($0)) }
        case 3:
            items = VideoLook.allCases.map { PanelItem(title: $0.title, symbol: $0.symbol) }
            sel = c.look
        default:
            items = [
                PanelItem(title: "Реверс", symbol: "backward.fill"),
                PanelItem(title: "Заморозка 2с", symbol: "snowflake"),
                PanelItem(title: "Заморозка 4с", symbol: "snowflake")
            ]
        }
        panel.configure(title: "Эффекты · клип \(i + 1)", items: items, selected: sel, slider: cfg,
                        chips: ["Поворот", "Угол", "Масштаб", "Эффекты", "Время"], selectedChip: fxTab, keepScroll: keep)
    }

    func mutateClip(_ f: (inout VideoClip) -> Void) {
        guard let i = currentClipIndex() else { return }
        pushUndo()
        f(&clips[i])
        refreshVideoComposition()
        reloadTimeline()
        refreshActivePanel()
    }

    func handleEffectsSelect(_ index: Int) {
        switch fxTab {
        case 0:
            switch index {
            case 0: mutateClip { $0.flipH.toggle() }
            case 1: mutateClip { $0.flipV.toggle() }
            case 2: mutateClip { $0.rotation = ViewController.normalizeAngle($0.rotation - 90) }
            case 3: mutateClip { $0.rotation = ViewController.normalizeAngle($0.rotation + 90) }
            default: mutateClip { $0.flipH = false; $0.flipV = false; $0.rotation = 0; $0.zoom = 1 }
            }
        case 1: mutateClip { $0.rotation = 0 }
        case 2: mutateClip { $0.zoom = 1 }
        case 3: mutateClip { $0.look = index }
        default:
            switch index {
            case 0: reverseCurrentClip()
            case 1: freezeFrame(seconds: 2)
            default: freezeFrame(seconds: 4)
            }
        }
    }

    static func normalizeAngle(_ a: Double) -> Double {
        var x = a.truncatingRemainder(dividingBy: 360)
        if x > 180 { x -= 360 }
        if x <= -180 { x += 360 }
        return x
    }

    // MARK: Frame (формат кадра)

    func refreshFramePanel(_ keep: Bool) {
        var items: [PanelItem] = []
        var sel: Int?
        if frameTab == 0 {
            for p in AspectPresets.all { items.append(PanelItem(title: p.title, badge: p.title)) }
            items.append(PanelItem(title: "Своя рамка", symbol: "crop"))
            sel = project.crop == nil ? 0 : project.aspectIndex
        } else {
            items = [
                PanelItem(title: "Вписать", symbol: "arrow.down.right.and.arrow.up.left", on: project.fillMode == 0),
                PanelItem(title: "Заполнить (обрезка)", symbol: "arrow.up.left.and.arrow.down.right", on: project.fillMode == 1),
                PanelItem(title: "Размытый фон", symbol: "drop", on: project.blurBackground)
            ]
        }
        panel.configure(title: "Формат кадра", items: items, selected: sel, slider: nil,
                        chips: ["Обрезка", "Заполнение"], selectedChip: frameTab, keepScroll: keep)
    }

    /// Готовый формат = обрезка по центру до нужного соотношения (без полей и подложки).
    static func centeredCrop(ratio: Double, source: CGSize) -> CGRect {
        let a = Double(source.width / source.height)
        if ratio < a {
            let w = ratio / a
            return CGRect(x: (1 - w) / 2, y: 0, width: w, height: 1)
        } else {
            let h = a / ratio
            return CGRect(x: 0, y: (1 - h) / 2, width: 1, height: h)
        }
    }

    /// Открывает экран кадрирования: рамка с сеткой поверх кадра, края тянутся пальцем.
    func presentCrop() {
        guard let i = currentClipIndex() else { return }
        pausePlayback()
        let clip = clips[i]
        let t = clip.sourceRange.start.secs + min(0.1, clip.sourceRange.duration.secs / 2)
        loader.startAnimating()
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let gen = AVAssetImageGenerator(asset: clip.asset)
            gen.appliesPreferredTrackTransform = true
            gen.maximumSize = CGSize(width: 1600, height: 1600)
            gen.requestedTimeToleranceBefore = .positiveInfinity
            gen.requestedTimeToleranceAfter = .positiveInfinity
            let cg = try? gen.copyCGImage(at: CMTime(seconds: t, preferredTimescale: 600), actualTime: nil)
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.loader.stopAnimating()
                guard let cg = cg else { self.showToast("Не удалось получить кадр"); return }
                let vc = CropViewController()
                vc.image = UIImage(cgImage: cg)
                vc.initialCrop = self.project.crop
                vc.modalPresentationStyle = .fullScreen
                vc.onApply = { [weak self] rect in
                    guard let self = self else { return }
                    self.pushUndo()
                    self.project.crop = rect
                    self.project.aspectIndex = rect == nil ? 0 : AspectPresets.all.count   // «Своя рамка»
                    self.project.customW = 0
                    self.project.customH = 0
                    self.rebuild()
                    self.refreshActivePanel()
                }
                self.present(vc, animated: true)
            }
        }
    }

    func handleFrameSelect(_ index: Int) {
        if frameTab == 0 {
            if index >= AspectPresets.all.count { presentCrop(); return }
            let preset = AspectPresets.all[index]
            pushUndo()
            project.aspectIndex = index
            project.customW = 0
            project.customH = 0
            if preset.w > 0, let first = clips.first, let src = EditorBuild.orientedSize(of: first) {
                project.crop = ViewController.centeredCrop(ratio: preset.w / preset.h, source: src)
            } else {
                project.crop = nil     // «Оригинал»
            }
            rebuild()
        } else {
            pushUndo()
            switch index {
            case 0: project.fillMode = 0
            case 1: project.fillMode = 1
            default: project.blurBackground.toggle()
            }
            refreshVideoComposition()
        }
        refreshActivePanel()
    }

    func promptCustomRatio() {
        let alert = UIAlertController(title: "Свой формат", message: "Соотношение сторон: ширина и высота", preferredStyle: .alert)
        alert.addTextField { $0.placeholder = "Ширина (например 5)"; $0.keyboardType = .decimalPad; $0.text = self.project.customActive ? "\(self.project.customW)" : nil }
        alert.addTextField { $0.placeholder = "Высота (например 7)"; $0.keyboardType = .decimalPad; $0.text = self.project.customActive ? "\(self.project.customH)" : nil }
        alert.addAction(UIAlertAction(title: "Отмена", style: .cancel))
        alert.addAction(UIAlertAction(title: "Применить", style: .default) { [weak self, weak alert] _ in
            guard let self = self, let f = alert?.textFields else { return }
            let w = Double((f[0].text ?? "").replacingOccurrences(of: ",", with: ".")) ?? 0
            let h = Double((f[1].text ?? "").replacingOccurrences(of: ",", with: ".")) ?? 0
            guard w > 0.1, h > 0.1, w / h < 10, h / w < 10 else { self.showToast("Введите два числа, например 5 и 7"); return }
            self.pushUndo()
            self.project.customW = w
            self.project.customH = h
            self.rebuild()
            self.refreshActivePanel()
        })
        present(alert, animated: true)
    }

    // MARK: Background (вырезать фон)

    var bgSwatches: [Int] { [0, 5, 6, 7, 9, 12, 15, 17, 20, 22, 33, 40] }

    func refreshBackgroundPanel(_ keep: Bool) {
        guard let i = currentClipIndex() else { closePanel(); return }
        var items = [
            PanelItem(title: "Без замены", symbol: "xmark"),
            PanelItem(title: "Размытый фон", symbol: "drop"),
            PanelItem(title: "Фото из галереи", symbol: "photo")
        ]
        items += bgSwatches.map { PanelItem(title: "Цвет", swatch: TextPalette.color($0)) }
        let c = clips[i]
        var sel = 0
        switch c.bgMode {
        case 2: sel = 1
        case 1: sel = 2
        case 3: sel = 3 + (bgSwatches.firstIndex(of: c.bgColor) ?? 0)
        default: sel = 0
        }
        panel.configure(title: "Вырезать фон · клип \(i + 1)", items: items, selected: sel, slider: nil,
                        extra: c.bgMode == 0 ? nil : "Ко всем", keepScroll: keep)
    }

    func handleBackgroundSelect(_ index: Int) {
        guard #available(iOS 15.0, *) else { showToast("Вырезание фона работает на iOS 15 и новее"); return }
        if index == 2 {
            pickerPurpose = .bgPhoto
            var config = PHPickerConfiguration()
            config.filter = .images
            config.selectionLimit = 1
            let picker = PHPickerViewController(configuration: config)
            picker.delegate = self
            present(picker, animated: true)
            return
        }
        mutateClip {
            switch index {
            case 0: $0.bgMode = 0
            case 1: $0.bgMode = 2
            default: $0.bgMode = 3; $0.bgColor = bgSwatches[min(index - 3, bgSwatches.count - 1)]
            }
        }
    }

    func applyBackgroundToAll() {
        guard let i = currentClipIndex() else { return }
        pushUndo()
        let src = clips[i]
        for k in 0..<clips.count {
            clips[k].bgMode = src.bgMode
            clips[k].bgFile = src.bgFile
            clips[k].bgColor = src.bgColor
        }
        refreshVideoComposition()
        reloadTimeline()
        showToast("Фон применён ко всем клипам")
    }

    func setBackgroundPhoto(_ image: UIImage) {
        guard let i = currentClipIndex() else { return }
        guard let data = image.jpegData(compressionQuality: 0.9) else { return }
        let name = "\(UUID().uuidString).jpg"
        do { try data.write(to: DraftStore.shared.mediaURL(name)) } catch { showToast("Не удалось сохранить фото"); return }
        pushUndo()
        clips[i].bgMode = 1
        clips[i].bgFile = name
        refreshVideoComposition()
        reloadTimeline()
        refreshActivePanel()
    }

    // MARK: Panel selection dispatcher

    func handlePanelSelect(_ index: Int) {
        guard let kind = activePanel else { return }
        switch kind {
        case .speed:
            guard let i = currentClipIndex(), index < speedPresets.count else { return }
            pushUndo()
            clips[i].speed = speedPresets[index]
            rebuild()
            refreshActivePanel()

        case .filter:
            guard let i = currentClipIndex() else { return }
            pushUndo()
            let ids = FilterCatalog.ids(for: filterCategory)
            clips[i].filterID = index == 0 ? 0 : ids[min(index - 1, ids.count - 1)]
            refreshVideoComposition()   // только этот клип — у остальных фильтры не трогаем
            reloadTimeline()
            refreshActivePanel()

        case .adjust:
            handleAdjustSelect(index)

        case .transition:
            guard clips.count >= 2 else { return }
            let j = min(transitionBoundary, clips.count - 2)
            pushUndo()
            let list = TransitionCatalog.list(transitionCategory)
            if index == 0 {
                clips[j].transitionID = 0
            } else if index == 1 {
                clips[j].transitionID = list.randomElement()?.id ?? 0
            } else if index - 2 < list.count {
                clips[j].transitionID = list[index - 2].id
            }
            rebuild()
            refreshActivePanel()
            previewTransition(j)

        case .animation: handleAnimationSelect(index)
        case .effects: handleEffectsSelect(index)
        case .frame: handleFrameSelect(index)
        case .background: handleBackgroundSelect(index)
        case .text: handleTextPanel(index)
        case .audio: handleAudioSelect(index)
        }
    }

    // MARK: Slider callbacks

    func sliderBegan() {
        switch activePanel {
        case .text?: if selectedTextID != nil { pushUndo() }
        case .audio?, .speed?, .filter?, .transition?, .adjust?, .effects?, .animation?: pushUndo()
        default: break
        }
    }

    func mutateTextLive(_ f: (inout TextOverlay) -> Void) {
        guard let id = selectedTextID, let idx = texts.firstIndex(where: { $0.id == id }) else { return }
        f(&texts[idx])
        refreshVideoComposition()
        updateTextBox()
    }

    func sliderChanged(_ v: Float) {
        switch activePanel {
        case .speed?:
            if let i = currentClipIndex() { clips[i].speed = max(0.1, (v * 20).rounded() / 20) }
        case .filter?:
            guard let i = currentClipIndex() else { return }
            clips[i].filterIntensity = v
            refreshVideoComposition()
        case .adjust?:
            guard let i = currentClipIndex() else { return }
            var a = clips[i].adjust
            setAdjustValue(Double(v), &a)
            clips[i].adjust = a
            refreshVideoComposition()
        case .transition?:
            guard clips.count >= 2 else { return }
            clips[min(transitionBoundary, clips.count - 2)].transitionDuration = Double(v)
        case .animation?:
            if animTab == 0 { project.introDuration = Double(v) } else { project.outroDuration = Double(v) }
            refreshVideoComposition()
        case .effects?:
            guard let i = currentClipIndex() else { return }
            if fxTab == 1 { clips[i].rotation = Double(v) } else if fxTab == 2 { clips[i].zoom = Double(v) }
            refreshVideoComposition()
        case .text?:
            switch textTab {
            case .text: mutateTextLive { $0.size = CGFloat(v) }
            case .stroke: mutateTextLive { $0.strokeWidth = CGFloat(v) }
            case .box: mutateTextLive { $0.boxOpacity = Double(v) }
            case .format: mutateTextLive { $0.letterSpacing = CGFloat(v) }
            case .animIn, .animOut: mutateTextLive { $0.animDuration = Double(v) }
            default: break
            }
        case .audio?:
            guard let target = audioTarget() else { return }
            switch (audioTab, target) {
            case (1, .audio(let i)): audios[i].volume = v
            case (1, .clip(let i)): clips[i].volume = v
            case (3, .audio(let i)): audios[i].fadeIn = Double(v)
            case (3, .clip(let i)): clips[i].fadeIn = Double(v)
            case (4, .audio(let i)): audios[i].fadeOut = Double(v)
            case (4, .clip(let i)): clips[i].fadeOut = Double(v)
            default: break
            }
        default: break
        }
    }

    func sliderEnded(_ v: Float) {
        switch activePanel {
        case .speed?, .audio?:
            rebuild()
            refreshActivePanel()
        case .transition?:
            guard clips.count >= 2 else { return }
            let j = min(transitionBoundary, clips.count - 2)
            rebuild()
            previewTransition(j)
        case .animation?:
            let total = totalSeconds
            if animTab == 0 { playRange(from: 0, until: project.introDuration + 0.6) }
            else { playRange(from: max(0, total - project.outroDuration - 0.8), until: total) }
        case .text?:
            reloadTimeline()
            if (textTab == .animIn || textTab == .animOut), let o = selectedText { previewText(o) }
        default:
            reloadTimeline()
        }
    }

    // MARK: Transition helpers

    func applyTransitionToAll() {
        guard clips.count >= 2 else { return }
        let j = min(transitionBoundary, clips.count - 2)
        pushUndo()
        let id = clips[j].transitionID
        let dur = clips[j].transitionDuration
        for k in 0..<(clips.count - 1) {
            clips[k].transitionID = id
            clips[k].transitionDuration = dur
        }
        rebuild()
        refreshActivePanel()
        showToast("Переход применён ко всем стыкам")
    }

    /// Показываем переход: перематываем чуть назад и проигрываем.
    func previewTransition(_ j: Int) {
        guard let b = build, j + 1 < b.layout.starts.count else { return }
        let ov = b.layout.overlapAfter[j].secs
        let tStart = b.layout.starts[j + 1].secs
        guard ov > 0 else {
            seekTo(ticks(tStart))
            updateTimeLabel(tStart)
            timelineView.setPlayhead(time: tStart, force: true)
            return
        }
        playRange(from: max(0, tStart - 0.8), until: tStart + ov + 0.6)
    }
}
