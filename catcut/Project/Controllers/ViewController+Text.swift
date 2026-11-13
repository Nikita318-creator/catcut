// MARK: - Controllers/ViewController+Text.swift

import UIKit
import AVFoundation
import CoreImage
import CoreMedia
import PhotosUI
import Photos
import UniformTypeIdentifiers
import SnapKit

extension ViewController {

    // MARK: Text panel

    func textSample(_ key: String, _ build: (inout TextOverlay) -> Void) -> UIImage {
        if let c = textPreviewCache[key] { return c }
        var o = TextOverlay(text: "Aa", start: 0, duration: 1)
        o.size = 0.3
        build(&o)
        let img = TextRenderer.uiImage(for: o, canvas: CGSize(width: 150, height: 150))
        textPreviewCache[key] = img
        return img
    }

    func refreshTextPanel(keepScroll: Bool) {
        let t = selectedText
        let swatches = TextPalette.colors.map { PanelItem(title: "", swatch: $0) }
        let noneItem = PanelItem(title: "Нет", symbol: "xmark")
        var items: [PanelItem] = []
        var sel: Int?
        var cfg: SliderConfig?

        switch textTab {
        case .text:
            items = [
                PanelItem(title: "Добавить", symbol: "plus"),
                PanelItem(title: "Изменить", symbol: "pencil"),
                PanelItem(title: "Дубль", symbol: "plus.square.on.square"),
                PanelItem(title: "Удалить", symbol: "trash")
            ]
            if let t = t {
                cfg = SliderConfig(title: "Размер", min: 0.02, max: 0.3, value: Float(t.size)) {
                    String(format: "%.0f%%", Double($0) / 0.3 * 100)
                }
            }

        case .styles:
            for (i, p) in TextPresets.all.enumerated() {
                items.append(PanelItem(title: p.title, image: textSample("preset\(i)") { p.apply(&$0) }, fit: true))
            }

        case .font:
            for (i, f) in TextFonts.all.enumerated() {
                items.append(PanelItem(title: f.title, image: textSample("font\(i)") { $0.fontIndex = i }, fit: true))
            }
            sel = t?.fontIndex

        case .fill:
            items = swatches
            sel = t?.fillIndex

        case .stroke:
            items = [noneItem] + swatches
            if let t = t {
                sel = t.strokeIndex < 0 ? 0 : t.strokeIndex + 1
                if t.strokeIndex >= 0 {
                    cfg = SliderConfig(title: "Толщина", min: 0.02, max: 0.2, value: Float(t.strokeWidth)) {
                        String(format: "%.0f%%", Double($0) / 0.2 * 100)
                    }
                }
            }

        case .shadow:
            for (i, s) in TextShadow.allCases.enumerated() {
                items.append(PanelItem(title: s.title, image: textSample("shadow\(i)") {
                    $0.shadow = i; $0.shadowColorIndex = TextPalette.vivid(320)
                }, fit: true))
            }
            sel = t?.shadow

        case .shadowColor:
            items = swatches
            sel = t?.shadowColorIndex

        case .glow:
            items = [noneItem] + swatches
            if let t = t { sel = t.glowIndex < 0 ? 0 : t.glowIndex + 1 }

        case .box:
            items = [noneItem] + swatches
            if let t = t {
                sel = t.boxIndex < 0 ? 0 : t.boxIndex + 1
                if t.boxIndex >= 0 {
                    cfg = SliderConfig(title: "Прозрачн.", min: 0.1, max: 1, value: Float(t.boxOpacity)) {
                        "\(Int($0 * 100))%"
                    }
                }
            }

        case .format:
            for (i, w) in TextFonts.weights.enumerated() {
                items.append(PanelItem(title: w.0, badge: "Aa", on: t.map { $0.weight == i }))
            }
            items.append(PanelItem(title: "Курсив", symbol: "italic", on: t?.italic))
            items.append(PanelItem(title: "Подчёрк.", symbol: "underline", on: t?.underline))
            items.append(PanelItem(title: "Зачёрк.", symbol: "strikethrough", on: t?.strike))
            items.append(PanelItem(title: "Влево", symbol: "text.alignleft", on: t.map { $0.alignment == 0 }))
            items.append(PanelItem(title: "Центр", symbol: "text.aligncenter", on: t.map { $0.alignment == 1 }))
            items.append(PanelItem(title: "Вправо", symbol: "text.alignright", on: t.map { $0.alignment == 2 }))
            if let t = t {
                cfg = SliderConfig(title: "Интервал", min: -0.05, max: 0.5, value: Float(t.letterSpacing)) {
                    String(format: "%.2f", Double($0))
                }
            }

        case .animIn, .animOut:
            items = TextAnim.allCases.map { PanelItem(title: $0.title, symbol: $0.symbol) }
            if let t = t {
                sel = textTab == .animIn ? t.animIn : t.animOut
                if sel != 0 {
                    cfg = SliderConfig(title: "Длит.", min: 0.2, max: 2, value: Float(t.animDuration)) {
                        String(format: "%.1fс", Double($0))
                    }
                }
            }
        }

        let title: String
        if t == nil && textTab != .text { title = "Выберите текст на дорожке или нажмите на него в видео" }
        else { title = textTab.title }
        panel.configure(title: title, items: items, selected: sel, slider: cfg,
                        chips: TextTab.allCases.map { $0.title }, selectedChip: textTab.rawValue,
                        keepScroll: keepScroll)
    }

    func mutateSelectedText(_ f: (inout TextOverlay) -> Void) {
        guard let id = selectedTextID, let idx = texts.firstIndex(where: { $0.id == id }) else {
            showToast("Сначала выберите текст на дорожке под видео")
            return
        }
        pushUndo()
        f(&texts[idx])
        textsChanged()
    }

    func handleTextPanel(_ index: Int) {
        switch textTab {
        case .text:
            switch index {
            case 0: presentTextInput(editing: nil)
            case 1:
                guard let t = selectedText else { showToast("Выберите текст на дорожке под видео"); return }
                presentTextInput(editing: t)
            case 2:
                guard var t = selectedText else { showToast("Выберите текст на дорожке под видео"); return }
                pushUndo()
                t.id = UUID()
                t.position.y = min(0.95, t.position.y + 0.08)
                texts.append(t)
                selectedTextID = t.id
                textsChanged()
            default:
                guard let id = selectedTextID else { showToast("Выберите текст на дорожке под видео"); return }
                pushUndo()
                texts.removeAll { $0.id == id }
                selectedTextID = nil
                textsChanged()
            }

        case .styles:
            guard index < TextPresets.all.count else { return }
            mutateSelectedText { TextPresets.all[index].apply(&$0) }
        case .font:
            mutateSelectedText { $0.fontIndex = index }
        case .fill:
            mutateSelectedText { $0.fillIndex = index }
        case .stroke:
            mutateSelectedText {
                if index == 0 { $0.strokeIndex = -1 } else { $0.strokeIndex = index - 1; if $0.strokeWidth < 0.02 { $0.strokeWidth = 0.08 } }
            }
        case .shadow:
            mutateSelectedText { $0.shadow = index }
        case .shadowColor:
            mutateSelectedText { $0.shadowColorIndex = index }
        case .glow:
            mutateSelectedText { $0.glowIndex = index == 0 ? -1 : index - 1 }
        case .box:
            mutateSelectedText { $0.boxIndex = index == 0 ? -1 : index - 1 }
        case .format:
            mutateSelectedText {
                switch index {
                case 0..<8: $0.weight = index
                case 8: $0.italic.toggle()
                case 9: $0.underline.toggle()
                case 10: $0.strike.toggle()
                case 11: $0.alignment = 0
                case 12: $0.alignment = 1
                default: $0.alignment = 2
                }
            }
        case .animIn:
            mutateSelectedText { $0.animIn = index }
            if let o = selectedText { previewText(o) }
        case .animOut:
            mutateSelectedText { $0.animOut = index }
            if let o = selectedText { previewText(o) }
        }
    }

    func previewText(_ o: TextOverlay) {
        let d = min(o.animDuration, o.duration / 2)
        if textTab == .animOut {
            let end = o.start + o.duration
            playRange(from: max(0, end - d - 0.8), until: end + 0.15)
        } else {
            playRange(from: max(0, o.start - 0.3), until: o.start + d + 0.9)
        }
    }

    // MARK: Text editing

    func presentTextInput(editing: TextOverlay?) {
        pausePlayback()
        textInput.onDone = { [weak self] text in self?.commitText(text, editing: editing) }
        textInput.show(in: view, text: editing?.text ?? "")
    }

    func commitText(_ text: String, editing: TextOverlay?) {
        pushUndo()
        if let e = editing, let idx = texts.firstIndex(where: { $0.id == e.id }) {
            texts[idx].text = text
        } else {
            let total = totalSeconds
            let start = min(displayTime, max(0, total - 0.5))
            let dur = max(0.5, min(3, total - start))
            var o = TextOverlay(text: text, start: start, duration: dur)
            o.size = 0.06
            texts.append(o)
            clearSelection()
            focusLane = .text
            selectedTextID = o.id
        }
        textsChanged()
    }

    func textsChanged() {
        refreshVideoComposition()
        reloadTimeline()
        updateTextBox()
        refreshActivePanel()
    }

    func isVisible(_ o: TextOverlay, at t: Double) -> Bool {
        t >= o.start && t < o.start + o.duration
    }

    func videoRectInPlayer() -> CGRect {
        let c = playerContainer.bounds
        guard renderSize.width > 0, c.width > 0, c.height > 0 else { return c }
        let s = min(c.width / renderSize.width, c.height / renderSize.height)
        let w = renderSize.width * s, h = renderSize.height * s
        return CGRect(x: (c.width - w) / 2, y: (c.height - h) / 2, width: w, height: h)
    }

    func textGeometry(_ o: TextOverlay) -> (center: CGPoint, size: CGSize) {
        let vr = videoRectInPlayer()
        let px = TextRenderer.pixelSize(for: o, canvas: renderSize)
        let k = vr.height / max(1, renderSize.height)
        return (CGPoint(x: vr.minX + o.position.x * vr.width, y: vr.minY + o.position.y * vr.height),
                CGSize(width: px.width * k, height: px.height * k))
    }

    func updateTextBox() {
        guard build != nil, let o = selectedText, isVisible(o, at: displayTime) else {
            textBox.isHidden = true
            return
        }
        let g = textGeometry(o)
        textBox.transform = .identity
        textBox.bounds = CGRect(origin: .zero, size: g.size)
        textBox.center = g.center
        textBox.transform = CGAffineTransform(rotationAngle: o.rotation)
        textBox.isHidden = false
        playerContainer.bringSubviewToFront(textBox)
    }

    @objc func handlePlayerTap(_ g: UITapGestureRecognizer) {
        let p = g.location(in: playerContainer)
        for o in texts.reversed() where isVisible(o, at: displayTime) {
            let geo = textGeometry(o)
            let dx = p.x - geo.center.x, dy = p.y - geo.center.y
            let c = cos(-o.rotation), s = sin(-o.rotation)
            let lx = dx * c - dy * s, ly = dx * s + dy * c
            if abs(lx) <= geo.size.width / 2 + 10 && abs(ly) <= geo.size.height / 2 + 10 {
                selectText(o.id)
                return
            }
        }
        if selectedTextID != nil { deselectAll(); return }
        togglePlay()
    }

    @objc func handlePlayerPan(_ g: UIPanGestureRecognizer) {
        if let id = selectedOverlayID, let idx = overlays.firstIndex(where: { $0.id == id }) {
            if g.state == .began { pushUndo() }
            let tr = g.translation(in: playerContainer)
            let w = playerContainer.bounds.width
            let h = playerContainer.bounds.height
            guard w > 0, h > 0 else { return }
            
            var pos = overlays[idx].position
            pos.x = min(1, max(0, pos.x + tr.x / w))
            pos.y = min(1, max(0, pos.y + tr.y / h))
            overlays[idx].position = pos
            g.setTranslation(.zero, in: playerContainer)
            refreshVideoComposition()
            return
        }
        
        // Старая логика для текста:
        guard let id = selectedTextID, let idx = texts.firstIndex(where: { $0.id == id }) else { return }
        let vr = videoRectInPlayer()
        guard vr.width > 0, vr.height > 0 else { return }
        if g.state == .began { pushUndo() }
        let tr = g.translation(in: playerContainer)
        var pos = texts[idx].position
        pos.x = min(1, max(0, pos.x + tr.x / vr.width))
        pos.y = min(1, max(0, pos.y + tr.y / vr.height))
        texts[idx].position = pos
        g.setTranslation(.zero, in: playerContainer)
        refreshVideoComposition()
        updateTextBox()
    }
    
    @objc func handlePlayerPinch(_ g: UIPinchGestureRecognizer) {
        if let id = selectedOverlayID, let idx = overlays.firstIndex(where: { $0.id == id }) {
            if g.state == .began { pushUndo() }
            overlays[idx].scale = max(0.1, min(2.0, overlays[idx].scale * g.scale))
            g.scale = 1.0
            refreshVideoComposition()
            return
        }
    }
    
    @objc func handlePlayerRotate(_ g: UIRotationGestureRecognizer) {
        if let id = selectedOverlayID, let idx = overlays.firstIndex(where: { $0.id == id }) {
            if g.state == .began { pushUndo() }
            overlays[idx].rotation += g.rotation
            g.rotation = 0
            refreshVideoComposition()
            return
        }
    }
}
