// MARK: - Controllers/ViewController+Overlay.swift
// Жесты оверлея на превью: двигать пальцем, pinch — размер, rotate — поворот.

import UIKit
import AVFoundation

extension ViewController {

    // MARK: Install

    func installOverlayGestures() {
        let pan = UIPanGestureRecognizer(target: self, action: #selector(handleOverlayPan(_:)))
        pan.maximumNumberOfTouches = 1
        let pinch = UIPinchGestureRecognizer(target: self, action: #selector(handleOverlayPinch(_:)))
        let rotate = UIRotationGestureRecognizer(target: self, action: #selector(handleOverlayRotate(_:)))
        let all: [UIGestureRecognizer] = [pan, pinch, rotate]
        all.forEach { $0.delegate = self; playerContainer.addGestureRecognizer($0) }
        overlayGestures = all
    }

    // MARK: Geometry

    /// Где оверлей лежит в координатах playerContainer.
    func overlayGeometry(_ o: VideoOverlay) -> (center: CGPoint, size: CGSize)? {
        let vr = playerLayer.videoRect
        guard vr.width > 1, vr.height > 1 else { return nil }
        let aspect = OverlayMedia.info(for: o.file)?.aspect ?? 9.0 / 16.0
        let w = vr.width * CGFloat(o.scale)
        let h = w * aspect
        let c = CGPoint(x: vr.minX + CGFloat(o.posX) * vr.width, y: vr.minY + CGFloat(o.posY) * vr.height)
        return (c, CGSize(width: w, height: h))
    }

    func overlayHitTest(_ p: CGPoint, overlay o: VideoOverlay, padding: CGFloat) -> Bool {
        guard let g = overlayGeometry(o) else { return false }
        let dx = p.x - g.center.x, dy = p.y - g.center.y
        let th = CGFloat(o.rotation)
        let lx = dx * cos(th) + dy * sin(th)
        let ly = -dx * sin(th) + dy * cos(th)
        return abs(lx) <= g.size.width / 2 + padding && abs(ly) <= g.size.height / 2 + padding
    }

    // MARK: Delegate hook (вызывается из gestureRecognizerShouldBegin)

    func overlayGestureShouldBegin(_ g: UIGestureRecognizer) -> Bool {
        guard let o = selectedOverlay,
              displayTime >= o.start - 0.05, displayTime <= o.start + o.duration + 0.05 else { return false }
        if g is UIPanGestureRecognizer {
            // двигаем, только если палец лёг на сам оверлей (с запасом — он может быть маленьким)
            return overlayHitTest(g.location(in: playerContainer), overlay: o, padding: 28)
        }
        return true
    }

    // MARK: Handlers

    private func beginOverlayGesture() {
        guard !overlayGestureActive else { return }
        overlayGestureActive = true
        pausePlayback()
        pushUndo()
    }

    private func endOverlayGestureIfIdle() {
        let idle: Set<UIGestureRecognizer.State> = [.possible, .ended, .cancelled, .failed]
        if overlayGestures.allSatisfy({ idle.contains($0.state) }) { overlayGestureActive = false }
    }

    private func mutateSelectedOverlay(_ change: (inout VideoOverlay) -> Void) {
        guard let id = selectedOverlayID, let i = overlays.firstIndex(where: { $0.id == id }) else { return }
        change(&overlays[i])
        refreshVideoComposition()
    }

    @objc func handleOverlayPan(_ g: UIPanGestureRecognizer) {
        switch g.state {
        case .began:
            beginOverlayGesture()
        case .changed:
            let vr = playerLayer.videoRect
            guard vr.width > 1, vr.height > 1 else { return }
            let t = g.translation(in: playerContainer)
            g.setTranslation(.zero, in: playerContainer)
            mutateSelectedOverlay { o in
                o.posX = min(1, max(0, o.posX + Double(t.x / vr.width)))
                o.posY = min(1, max(0, o.posY + Double(t.y / vr.height)))
            }
        case .ended, .cancelled, .failed:
            endOverlayGestureIfIdle()
        default: break
        }
    }

    @objc func handleOverlayPinch(_ g: UIPinchGestureRecognizer) {
        switch g.state {
        case .began:
            beginOverlayGesture()
        case .changed:
            let k = Double(g.scale)
            g.scale = 1
            mutateSelectedOverlay { o in o.scale = min(2.0, max(0.05, o.scale * k)) }
        case .ended, .cancelled, .failed:
            endOverlayGestureIfIdle()
        default: break
        }
    }

    @objc func handleOverlayRotate(_ g: UIRotationGestureRecognizer) {
        switch g.state {
        case .began:
            beginOverlayGesture()
        case .changed:
            let r = Double(g.rotation)
            g.rotation = 0
            mutateSelectedOverlay { o in o.rotation += r }
        case .ended, .cancelled, .failed:
            endOverlayGestureIfIdle()
        default: break
        }
    }

    // MARK: Timeline commit (обрезка за края / перенос долгим тапом)

    func commitOverlayTime(_ id: UUID, start: Double, sourceStart: Double, duration: Double) {
        guard let idx = overlays.firstIndex(where: { $0.id == id }) else { return }
        pushUndo()
        overlays[idx].start = start
        overlays[idx].sourceStart = sourceStart
        overlays[idx].duration = duration
        clearSelection()
        focusLane = .overlay
        selectedOverlayID = id
        rebuild()
        refreshActivePanel()
    }
}
