// MARK: - Controllers/ViewController+Retouch.swift

import UIKit
import AVFoundation
import CoreMedia

extension ViewController {

    // MARK: Подписка на события анализа (вызвать один раз из setupCallbacks)

    func setupRetouch() {
        RetouchStore.shared.onEvent = { [weak self] event in
            guard let self = self else { return }
            switch event {
            case .updated:
                if self.player.rate == 0 { self.refreshVideoComposition() }
            case .finished(let foundFace, let foundBody, let askedFace, let askedBody):
                if askedFace && !foundFace {
                    self.showToast("Лицо в этом клипе не найдено")
                } else if askedBody && !foundBody {
                    self.showToast("Тело не найдено — нужен человек в кадре (лучше в полный рост)")
                }
                if self.player.rate == 0 { self.refreshVideoComposition() }
            }
        }
    }

    // MARK: Анализ

    func ensureRetouchAnalysis(_ i: Int) {
        guard i >= 0, i < clips.count else { return }
        let c = clips[i]
        let s = c.retouch
        guard !s.isIdentity, !c.file.isEmpty else { return }
        RetouchStore.shared.prepare(clip: c, face: s.needsFace, body: s.needsBody)
    }

    func ensureRetouchForAllClips() {
        for i in clips.indices { ensureRetouchAnalysis(i) }
    }

    // MARK: Панель

    func refreshRetouchPanel(_ keep: Bool) {
        guard let i = currentClipIndex() else { closePanel(); return }
        let cat = RetouchCategory(rawValue: retouchTab) ?? .skin
        let params = RetouchParam.params(in: cat)
        guard !params.isEmpty else { return }
        retouchParam = max(0, min(retouchParam, params.count - 1))
        let s = clips[i].retouch

        var items: [PanelItem] = params.map { p in
            let v = s[keyPath: p.path]
            // активный параметр показывает значение вместо иконки (иконка и бейдж в ячейке накладываются)
            if abs(v) > 0.001 {
                return PanelItem(title: p.title, badge: String(format: "%+.0f", v * 100))
            }
            return PanelItem(title: p.title, symbol: p.symbol)
        }
        items.append(PanelItem(title: "Сбросить", symbol: "arrow.counterclockwise"))

        let cur = params[retouchParam]
        let cfg = SliderConfig(title: cur.title, min: Float(cur.min), max: Float(cur.max),
                               value: Float(s[keyPath: cur.path])) { v in
            cur.bipolar ? String(format: "%+.0f", Double(v) * 100) : String(format: "%.0f", Double(v) * 100)
        }
        panel.configure(title: "Ретушь · клип \(i + 1)", items: items, selected: retouchParam, slider: cfg,
                        chips: RetouchCategory.allCases.map { $0.title }, selectedChip: retouchTab,
                        extra: "Ко всем", keepScroll: keep)
    }

    func handleRetouchSelect(_ index: Int) {
        guard let i = currentClipIndex() else { return }
        let cat = RetouchCategory(rawValue: retouchTab) ?? .skin
        let params = RetouchParam.params(in: cat)

        if index == params.count {
            // «Сбросить» — вся текущая категория
            pushUndo()
            for p in params { clips[i].retouch[keyPath: p.path] = 0 }
            refreshVideoComposition()
            reloadTimeline()
            refreshActivePanel()
            return
        }
        guard index < params.count else { return }
        retouchParam = index
        ensureRetouchAnalysis(i)
        refreshActivePanel()
    }

    func retouchSliderChanged(_ v: Float) {
        guard let i = currentClipIndex() else { return }
        let cat = RetouchCategory(rawValue: retouchTab) ?? .skin
        let params = RetouchParam.params(in: cat)
        guard retouchParam < params.count else { return }
        let p = params[retouchParam]
        var value = Double(v)
        if abs(value) < 0.02 { value = 0 }          // «залипание» в нуле, чтобы можно было вернуться к оригиналу
        clips[i].retouch[keyPath: p.path] = value
        ensureRetouchAnalysis(i)
        refreshVideoComposition()
    }

    func applyRetouchToAll() {
        guard let i = currentClipIndex() else { return }
        pushUndo()
        let src = clips[i].retouch
        for k in clips.indices { clips[k].retouch = src }
        ensureRetouchForAllClips()
        refreshVideoComposition()
        reloadTimeline()
        showToast("Ретушь применена ко всем клипам")
    }
}
