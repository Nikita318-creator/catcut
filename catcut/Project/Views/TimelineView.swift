// MARK: - Views/TimelineView.swift

import UIKit
import AVFoundation
import CoreImage
import CoreMedia
import SnapKit

// =====================================================================
// MARK: - Timeline
// =====================================================================

/// Линейка со временем. Рисуется только видимая часть (не зависит от длины видео).
final class RulerView: UIView {
    var pps: CGFloat = 64
    var offsetX: CGFloat = 0
    var total: Double = 0

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        isUserInteractionEnabled = false
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func draw(_ rect: CGRect) {
        guard let ctx = UIGraphicsGetCurrentContext() else { return }
        let side = bounds.width / 2
        let labelEvery = pps >= 90 ? 1 : (pps >= 45 ? 2 : (pps >= 26 ? 5 : (pps >= 12 ? 10 : 30)))
        let first = max(0, Int(floor((offsetX - side) / pps)) - 1)
        let last = Int(ceil((offsetX + bounds.width - side) / pps)) + 1
        guard last >= first else { return }

        let attrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.monospacedDigitSystemFont(ofSize: 9, weight: .medium),
            .foregroundColor: UIColor(white: 0.55, alpha: 1)
        ]
        ctx.setStrokeColor(UIColor(white: 0.4, alpha: 1).cgColor)
        ctx.setLineWidth(1)

        for s in first...last where Double(s) <= total + 1 {
            let x = side + CGFloat(s) * pps - offsetX
            let isLabel = s % labelEvery == 0
            ctx.move(to: CGPoint(x: x, y: isLabel ? bounds.height - 8 : bounds.height - 4))
            ctx.addLine(to: CGPoint(x: x, y: bounds.height))
            ctx.strokePath()
            if isLabel {
                let str = String(format: "%d:%02d", s / 60, s % 60) as NSString
                str.draw(at: CGPoint(x: x + 3, y: 2), withAttributes: attrs)
            }
        }
    }
}

final class ClipTileView: UIView {
    init(clip: VideoClip, width: CGFloat, height: CGFloat, selected: Bool) {
        super.init(frame: CGRect(x: 0, y: 0, width: width, height: height))
        backgroundColor = UIColor(white: 0.22, alpha: 1)
        layer.cornerRadius = 6
        clipsToBounds = true

        let tileW = height
        let count = max(1, Int(ceil(width / tileW)))
        let srcStart = clip.sourceRange.start.secs
        let srcDur = clip.sourceRange.duration.secs
        for i in 0..<count {
            let iv = UIImageView()
            iv.contentMode = .scaleAspectFill
            iv.clipsToBounds = true
            iv.frame = CGRect(x: CGFloat(i) * tileW, y: 0, width: tileW, height: height)
            let frac = min(1, max(0, (CGFloat(i) + 0.5) * tileW / width))
            iv.image = ThumbnailStore.shared.image(for: clip.asset, at: srcStart + Double(frac) * srcDur)
            addSubview(iv)
        }

        var info = String(format: " %.1fс", clip.displayDuration.secs)
        if clip.speed != 1 { info += String(format: " ⚡%gx", Double(clip.speed)) }
        if clip.filterID != 0 || !clip.adjust.isIdentity { info += " ✦" }
        if clip.look != 0 { info += " ⚡︎" }
        if clip.isImage { info += " 🖼" }
        if clip.volume == 0 && !clip.isImage { info += " 🔇" }
        info += " "
        let label = UILabel()
        label.text = info
        label.font = .systemFont(ofSize: 10, weight: .semibold)
        label.textColor = .white
        label.backgroundColor = UIColor.black.withAlphaComponent(0.5)
        label.layer.cornerRadius = 3
        label.clipsToBounds = true
        label.sizeToFit()
        label.frame.origin = CGPoint(x: 16, y: height - label.frame.height - 4)
        addSubview(label)

        if selected {
            layer.borderWidth = 2.5
            layer.borderColor = UIColor.white.cgColor
            addTrimHandles(to: self)
        }
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
}

/// Плитка оверлея на своей видео-дорожке: кадры-превью, как у основного клипа.
final class OverlayTileView: UIView {
    init(overlay: VideoOverlay, asset: AVAsset?, width: CGFloat, height: CGFloat, selected: Bool) {
        super.init(frame: CGRect(x: 0, y: 0, width: width, height: height))
        backgroundColor = UIColor(white: 0.22, alpha: 1)
        layer.cornerRadius = 6
        clipsToBounds = true
        layer.borderWidth = 1
        layer.borderColor = UIColor.systemIndigo.withAlphaComponent(0.9).cgColor

        if let asset = asset {
            let tileW = height
            let count = max(1, Int(ceil(width / tileW)))
            for i in 0..<count {
                let iv = UIImageView()
                iv.contentMode = .scaleAspectFill
                iv.clipsToBounds = true
                iv.frame = CGRect(x: CGFloat(i) * tileW, y: 0, width: tileW, height: height)
                let frac = min(1, max(0, (CGFloat(i) + 0.5) * tileW / width))
                let t = overlay.isImage ? 0 : overlay.sourceStart + Double(frac) * overlay.duration
                iv.image = ThumbnailStore.shared.image(for: asset, at: t)
                addSubview(iv)
            }
        }

        var info = String(format: " ⧉ %.1fс", overlay.duration)
        if overlay.isImage { info += " 🖼" }
        info += " "
        let label = UILabel()
        label.text = info
        label.font = .systemFont(ofSize: 10, weight: .semibold)
        label.textColor = .white
        label.backgroundColor = UIColor.black.withAlphaComponent(0.5)
        label.layer.cornerRadius = 3
        label.clipsToBounds = true
        label.sizeToFit()
        label.frame.origin = CGPoint(x: 16, y: height - label.frame.height - 3)
        addSubview(label)

        if selected {
            layer.borderWidth = 2.5
            layer.borderColor = UIColor.white.cgColor
            addTrimHandles(to: self)
        }
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
}

/// Полоска аудио с волной.
final class AudioBarView: UIView {
    var peaks: [Float] = []
    var offset: Double = 0
    var duration: Double = 1
    var title: String = ""
    var volume: Float = 1.0
    var fadeIn: Double = 0.0
    var fadeOut: Double = 0.0

    override init(frame: CGRect) {
        super.init(frame: frame)
        contentMode = .redraw
        backgroundColor = Theme.audio
        layer.cornerRadius = 6
        clipsToBounds = true
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func draw(_ rect: CGRect) {
        guard let ctx = UIGraphicsGetCurrentContext(), duration > 0 else { return }
        let w = bounds.width, h = bounds.height
        let pps = CGFloat(WaveformStore.peaksPerSecond)
        if !peaks.isEmpty {
            let pxPerSec = w / CGFloat(duration)
            let step = pxPerSec / pps
            let barW = max(1, step - 1)
            ctx.setFillColor(UIColor(white: 1, alpha: 0.7).cgColor)
            var i = Int(offset * Double(pps))
            var px: CGFloat = 0
            let midY = h / 2 + 5
            
            while px < w && i < peaks.count {
                // Текущая секунда внутри этой аудиодорожки
                let t = Double(px) / w * duration
                
                // Расчет огибающей для появления (Fade In) и затухания (Fade Out)
                var envelope: CGFloat = 1.0
                if fadeIn > 0, t < fadeIn {
                    envelope = CGFloat(t / fadeIn)
                }
                if fadeOut > 0, t > (duration - fadeOut) {
                    let remaining = duration - t
                    envelope = CGFloat(max(0, remaining / fadeOut))
                }
                
                // Учет громкости (volume от 0 до 3)
                let volFactor = CGFloat(max(0, volume))
                
                // Итоговая высота пика с учетом громкости и фейдов
                let rawPeak = CGFloat(peaks[min(i, peaks.count - 1)])
                let finalPeak = rawPeak * volFactor * envelope
                let bh = max(1.5, finalPeak * (h - 14))
                
                ctx.fill(CGRect(x: px, y: midY - bh / 2, width: barW, height: bh))
                px += step
                i += 1
            }
        }
        let attrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 10, weight: .semibold),
            .foregroundColor: UIColor.white
        ]
        ("♪ " + title as NSString).draw(at: CGPoint(x: 16, y: 2), withAttributes: attrs)
    }
}

enum TimelineLane { case video, overlay, text, audio }

/// UIScrollView, который не начинает скролл, если палец лёг на ручку обрезки / выбранную полоску.
final class TimelineScrollView: UIScrollView {
    var touchDownPoint: CGPoint = .zero
    var blocksScroll: ((CGPoint) -> Bool)?
    var isLongPressActive: Bool = false // Флаг блокировки скролла

    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        touchDownPoint = point
        return super.hitTest(point, with: event)
    }

    override func gestureRecognizerShouldBegin(_ g: UIGestureRecognizer) -> Bool {
        // Если идет перетаскивание по долгому нажатию — полностью глушим скролл ленты
        if g === panGestureRecognizer, isLongPressActive { return false }
        if g === panGestureRecognizer, blocksScroll?(touchDownPoint) == true { return false }
        return super.gestureRecognizerShouldBegin(g)
    }
}

final class TimelineView: UIView, UIScrollViewDelegate, UIGestureRecognizerDelegate {

    static let minHeight: CGFloat = 166

    private var pps: CGFloat = 64               // точек на секунду (меняется щипком)
    private let minPPS: CGFloat = 4           // максимально «сжатая» лента
    private let maxPPS: CGFloat = 240           // максимально «растянутая» лента
    private var pinchStartPPS: CGFloat = 64
    private var pinch: UIPinchGestureRecognizer!
    private let clipTop: CGFloat = 26
    private let clipHeight: CGFloat = 56
    private let laneHeight: CGFloat = 26
    private let laneStep: CGFloat = 30
    private let handleZone: CGFloat = 28
    private let overlayRowH: CGFloat = 40       // высота плитки оверлея
    private let overlayStep: CGFloat = 44       // шаг между рядами оверлеев
    private let minDur: Double = 0.3

    private let scrollView = TimelineScrollView()
    private let contentView = UIView()
    private let ruler = RulerView()
    private let playhead = UIView()
    private let knob = UIView()
    private let addTile = UIView()
    private var chips: [TimelineLane: UIButton] = [:]
    private var dragPan: UIPanGestureRecognizer!

    // callbacks
    var onScrubBegan: (() -> Void)?
    var onScrub: ((Double) -> Void)?
    var onSelectClip: ((Int) -> Void)?
    var onSelectText: ((UUID) -> Void)?
    var onSelectAudio: ((UUID) -> Void)?
    var onDeselectAll: (() -> Void)?
    var onFocusLane: ((TimelineLane) -> Void)?
    var onTapTransition: ((Int) -> Void)?
    var onTapAdd: (() -> Void)?
    var onClipTrimmed: ((Int, CMTimeRange) -> Void)?
    var onTextTimeChanged: ((UUID, Double, Double) -> Void)?
    var onAudioTimeChanged: ((UUID, Double, Double, Double) -> Void)?
    var onNeedHeight: ((CGFloat) -> Void)?
    var onClipTrimming: ((Double) -> Void)?
    var onOpenTextEditor: ((UUID) -> Void)?
    var onOpenAudioEditor: ((UUID) -> Void)?
    var onClipsReordered: (([VideoClip]) -> Void)?
    var onSelectOverlay: ((UUID) -> Void)?
    var onOverlayTimeChanged: ((UUID, Double, Double, Double) -> Void)?   // id, start, sourceStart, duration
    
    private var overlays: [VideoOverlay] = []
    private var selectedOverlay: UUID?
    private var overlayItems: [Item] = []
    private var clips: [VideoClip] = []
    private var layout = TimelineLayout(clips: [])
    private var texts: [TextOverlay] = []
    private var audios: [AudioClip] = []
    private var selectedClip: Int?
    private var selectedText: UUID?
    private var selectedAudio: UUID?
    private var focus: TimelineLane = .video

    private struct Item { let id: UUID; let frame: CGRect; let view: UIView }
    private var clipFrames: [CGRect] = []
    private var clipViews: [ClipTileView] = []
    private var transitionFrames: [CGRect] = []
    private var transitionViews: [UIView] = []
    private var textItems: [Item] = []
    private var audioItems: [Item] = []
    private var laneRows: [(lane: TimelineLane, rect: CGRect)] = []
    private(set) var requiredHeight: CGFloat = TimelineView.minHeight

    private var isProgrammatic = false
    private var lastPlayheadTime: Double = 0
    private var lastWidth: CGFloat = 0

    private var totalSeconds: Double { layout.total.secs }
    var isUserScrolling: Bool { scrollView.isTracking || scrollView.isDragging || scrollView.isDecelerating }

    // drag (обрезка за края)
    private enum DragKind {
        case clipLeft(Int), clipRight(Int)
        case textLeft(UUID), textRight(UUID)
        case audioLeft(UUID), audioRight(UUID)
        case clipMove(Int)
        case textMove(UUID)
        case audioMove(UUID)
        case overlayLeft(UUID), overlayRight(UUID)
        case overlayMove(UUID)
    }
    
    private struct DragState {
        var kind: DragKind
        var startTouchX: CGFloat
        var view: UIView
        var origFrame: CGRect
        var moved = false
        var start: Double = 0
        var duration: Double = 0
        var offset: Double = 0
        var initialSrcRange: CMTimeRange?
        var currentSrcRange: CMTimeRange?
    }
    private var drag: DragState?

    // Состояние для долгого нажатия (перемещение блоков)
    private struct MoveDragState {
        var kind: DragKind
        var view: UIView
        var origFrame: CGRect
        var grabOffsetX: CGFloat      // где палец схватил блок: touchContentX - origFrame.minX
        // видео
        var fromIndex: Int = 0
        var toIndex: Int = 0
        var slotX: CGFloat = 0        // куда «упадёт» перетаскиваемый клип
        // текст / аудио
        var origStart: Double = 0
        var newStart: Double = 0
        var duration: Double = 0
        var sourceOffset: Double = 0
    }
    private var moveDrag: MoveDragState?
    private var moveTouchX: CGFloat = 0          // позиция пальца в координатах TimelineView
    private var autoScrollLink: CADisplayLink?
    private var autoScrollStartOffset: CGFloat = 0

    /// Текущее время на таймлайне на основе позиции скролла
    var currentTime: Double {
        return Double(scrollView.contentOffset.x / pps)
    }
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        setup()
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private func setup() {
        backgroundColor = UIColor(white: 0.1, alpha: 1)

        scrollView.delegate = self
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.alwaysBounceHorizontal = true
        scrollView.contentInsetAdjustmentBehavior = .never
        scrollView.decelerationRate = .fast
        scrollView.delaysContentTouches = false
        scrollView.blocksScroll = { [weak self] p in self?.hitTarget(at: p) != nil }
        addSubview(scrollView)
        scrollView.addSubview(contentView)
        addSubview(ruler)

        addTile.backgroundColor = UIColor(white: 0.25, alpha: 1)
        addTile.layer.cornerRadius = 8
        let plus = UIImageView(image: UIImage(systemName: "plus"))
        plus.tintColor = .white
        plus.contentMode = .scaleAspectFit
        plus.frame = CGRect(x: 16, y: 16, width: 24, height: 24)
        addTile.addSubview(plus)

        playhead.backgroundColor = .systemRed
        playhead.layer.cornerRadius = 1.5
        playhead.isUserInteractionEnabled = false
        addSubview(playhead)

        knob.backgroundColor = .systemRed
        knob.layer.cornerRadius = 5
        knob.isUserInteractionEnabled = false
        addSubview(knob)

        scrollView.snp.makeConstraints { $0.edges.equalToSuperview() }
        playhead.snp.makeConstraints { make in
            make.centerX.equalToSuperview()
            make.top.equalToSuperview().offset(14)
            make.bottom.equalToSuperview().offset(-4)
            make.width.equalTo(3)
        }
        knob.snp.makeConstraints { make in
            make.centerX.equalToSuperview()
            make.centerY.equalTo(playhead.snp.top)
            make.size.equalTo(10)
        }

        let defs: [(TimelineLane, String)] = [(.video, "film"), (.overlay, "pip"), (.text, "textformat"), (.audio, "music.note")]
        for (lane, symbol) in defs {
            let b = UIButton(type: .system)
            b.setImage(UIImage(systemName: symbol), for: .normal)
            b.layer.cornerRadius = 6
            b.tag = [TimelineLane.video: 0, .text: 1, .audio: 2, .overlay: 3][lane] ?? 0
            b.addTarget(self, action: #selector(chipTapped(_:)), for: .touchUpInside)
            addSubview(b)
            chips[lane] = b
        }
        bringSubviewToFront(ruler)
        bringSubviewToFront(playhead)
        bringSubviewToFront(knob)
        chips.values.forEach { bringSubviewToFront($0) }

        let tap = UITapGestureRecognizer(target: self, action: #selector(handleTap(_:)))
        contentView.addGestureRecognizer(tap)

        dragPan = UIPanGestureRecognizer(target: self, action: #selector(handleDrag(_:)))
        dragPan.maximumNumberOfTouches = 1
        dragPan.delegate = self
        contentView.addGestureRecognizer(dragPan)

        // Долгое нажатие для перетаскивания объектов
        let longPressGesture = UILongPressGestureRecognizer(target: self, action: #selector(handleLongPress(_:)))
        longPressGesture.minimumPressDuration = 0.4
        longPressGesture.delegate = self
        contentView.addGestureRecognizer(longPressGesture)

        // Щипок двумя пальцами по любой дорожке — масштаб ленты
        pinch = UIPinchGestureRecognizer(target: self, action: #selector(handlePinch(_:)))
        pinch.delegate = self
        addGestureRecognizer(pinch)
    }

    @objc private func handlePinch(_ g: UIPinchGestureRecognizer) {
        switch g.state {
        case .began:
            pinchStartPPS = pps
            scrollView.isScrollEnabled = false   // пока щиплем — лента не скроллится
        case .changed:
            let target = min(maxPPS, max(minPPS, pinchStartPPS * g.scale))
            guard abs(target - pps) > 0.4 else { return }
            pps = target
            // Лента масштабируется вокруг красной палки (она всегда по центру)
            rebuildContent()
            setPlayhead(time: lastPlayheadTime, force: true)
        case .ended, .cancelled, .failed:
            scrollView.isScrollEnabled = true
        default:
            break
        }
    }

    func gestureRecognizer(_ g: UIGestureRecognizer,
                           shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
        return g === pinch || other === pinch
    }

    @objc private func chipTapped(_ b: UIButton) {
        switch b.tag {
        case 0: onFocusLane?(.video)
        case 1: onFocusLane?(.text)
        case 2: onFocusLane?(.audio)
        default: onFocusLane?(.overlay)
        }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        ruler.frame = CGRect(x: 0, y: 0, width: bounds.width, height: 22)
        if bounds.width != lastWidth {
            lastWidth = bounds.width
            rebuildContent()
            setPlayhead(time: lastPlayheadTime, force: true)
        }
    }

    func reload(clips: [VideoClip], layout: TimelineLayout, texts: [TextOverlay], audios: [AudioClip], overlays: [VideoOverlay],
                selectedClip: Int?, selectedText: UUID?, selectedAudio: UUID?, selectedOverlay: UUID?, focus: TimelineLane) {
        let currentOffsetX = scrollView.contentOffset.x
        if drag != nil || moveDrag != nil { return }
        self.clips = clips
        self.layout = layout
        self.texts = texts
        self.audios = audios
        self.overlays = overlays
        self.selectedClip = selectedClip
        self.selectedText = selectedText
        self.selectedAudio = selectedAudio
        self.selectedOverlay = selectedOverlay
        self.focus = focus
        
        rebuildContent()
        
        if currentOffsetX > 0 {
            scrollView.contentOffset.x = min(currentOffsetX, max(0, scrollView.contentSize.width - scrollView.bounds.width))
            ruler.offsetX = scrollView.contentOffset.x
            ruler.setNeedsDisplay()
        } else {
            setPlayhead(time: lastPlayheadTime, force: true)
        }
    }

    func setPlayhead(time: Double, force: Bool = false) {
        lastPlayheadTime = time
        if drag != nil || moveDrag != nil { return }
        if !force && isUserScrolling { return }
        isProgrammatic = true
        scrollView.contentOffset = CGPoint(x: CGFloat(max(0, min(time, totalSeconds))) * pps, y: 0)
        isProgrammatic = false
        ruler.offsetX = scrollView.contentOffset.x
        ruler.setNeedsDisplay()
    }

    private func assignLanes(_ spans: [(Double, Double)]) -> (lane: [Int], count: Int) {
        let order = spans.indices.sorted { spans[$0].0 < spans[$1].0 }
        var ends: [Double] = []
        var result = [Int](repeating: 0, count: spans.count)
        for i in order {
            let (s, e) = spans[i]
            if let l = ends.firstIndex(where: { $0 <= s + 0.0001 }) {
                ends[l] = e
                result[i] = l
            } else {
                ends.append(e)
                result[i] = ends.count - 1
            }
        }
        return (result, ends.count)
    }

    private func rebuildContent() {
        guard bounds.width > 0 else { return }
        let side = bounds.width / 2
        let contentW = CGFloat(totalSeconds) * pps + bounds.width
        contentView.subviews.forEach { $0.removeFromSuperview() }
        contentView.frame = CGRect(x: 0, y: 0, width: contentW, height: 600)
        scrollView.contentSize = CGSize(width: contentW, height: 1)
        ruler.pps = pps
        ruler.total = totalSeconds

        clipFrames = []; clipViews = []; transitionFrames = []; transitionViews = []
        textItems = []; audioItems = []; overlayItems = []; laneRows = []

        let tl = assignLanes(texts.map { ($0.start, max($0.start + $0.duration, $0.start + 24 / Double(pps))) })
        let ol = assignLanes(overlays.map { ($0.start, max($0.start + $0.duration, $0.start + 24 / Double(pps))) })
        let al = assignLanes(audios.map { ($0.start, $0.start + $0.duration) })

        let hasOverlays = !overlays.isEmpty
        let overlayRows = ol.count
        let textRows = max(1, tl.count)
        let audioRows = max(1, al.count)

        // Оверлеи — настоящие видео-дорожки НАД основной (как в CapCut).
        // Пока оверлеев нет, дорожки не видно: по умолчанию одна видео-дорожка.
        let overlayTop = clipTop
        let overlayBlockH: CGFloat = hasOverlays ? CGFloat(overlayRows) * overlayStep + 4 : 0
        let mainTop = clipTop + overlayBlockH
        let textBase = mainTop + clipHeight + 8
        let audioBase = textBase + CGFloat(textRows) * laneStep + 4
        let trackWidth = CGFloat(totalSeconds) * pps

        func addLaneBackground(_ lane: TimelineLane, y: CGFloat, height: CGFloat) {
            let focused = (focus == lane)
            if trackWidth > 0 {
                let bg = UIView(frame: CGRect(x: side, y: y, width: trackWidth, height: height))
                bg.backgroundColor = UIColor(white: 1, alpha: focused ? 0.13 : 0.06)
                bg.layer.cornerRadius = 6
                if focused { bg.layer.borderWidth = 1; bg.layer.borderColor = Theme.accent.withAlphaComponent(0.7).cgColor }
                contentView.addSubview(bg)
            }
            laneRows.append((lane, CGRect(x: 0, y: y - 2, width: contentW, height: height + 4)))
        }
        addLaneBackground(.video, y: mainTop - 2, height: clipHeight + 4)
        if hasOverlays { addLaneBackground(.overlay, y: overlayTop - 2, height: overlayBlockH - 2) }
        addLaneBackground(.text, y: textBase - 2, height: CGFloat(textRows) * laneStep)
        addLaneBackground(.audio, y: audioBase - 2, height: CGFloat(audioRows) * laneStep)

        func hint(_ text: String, y: CGFloat) {
            let l = UILabel(frame: CGRect(x: side + 10, y: y, width: 240, height: laneHeight))
            l.text = text
            l.font = .systemFont(ofSize: 11, weight: .medium)
            l.textColor = UIColor(white: 1, alpha: 0.35)
            contentView.addSubview(l)
        }
        if texts.isEmpty { hint("Текст — нажмите «Текст» внизу", y: textBase) }
        if audios.isEmpty { hint("Аудио — нажмите «Аудио» внизу", y: audioBase) }

        let chipY: [TimelineLane: CGFloat] = [
            .video: mainTop + (clipHeight - 24) / 2,
            .overlay: overlayTop + (overlayStep - 24) / 2,
            .text: textBase + 1,
            .audio: audioBase + 1
        ]
        for (lane, b) in chips {
            let on = focus == lane
            b.isHidden = (lane == .overlay && !hasOverlays)
            b.frame = CGRect(x: 6, y: chipY[lane] ?? 0, width: 28, height: 24)
            b.backgroundColor = on ? Theme.accent : UIColor(white: 0.22, alpha: 0.95)
            b.tintColor = on ? .black : .white
        }

        // 1. Основная видео-дорожка
        for (i, clip) in clips.enumerated() where i < layout.starts.count {
            let x = side + CGFloat(layout.starts[i].secs) * pps + 1
            let w = max(10, CGFloat(layout.durations[i].secs) * pps - 2)
            let tile = ClipTileView(clip: clip, width: w, height: clipHeight, selected: i == selectedClip)
            tile.frame = CGRect(x: x, y: mainTop, width: w, height: clipHeight)
            contentView.addSubview(tile)
            clipFrames.append(tile.frame)
            clipViews.append(tile)
        }

        if let sel = selectedClip, sel < clipViews.count {
            contentView.bringSubviewToFront(clipViews[sel])
        }

        // 2. Видео-дорожки оверлеев (с превью-кадрами, обрезкой за края и переносом)
        for (k, o) in overlays.enumerated() {
            let x = side + CGFloat(o.start) * pps
            let w = max(24, CGFloat(o.duration) * pps)
            let y = overlayTop + CGFloat(ol.lane[k]) * overlayStep
            let tile = OverlayTileView(overlay: o, asset: OverlayMedia.info(for: o.file)?.asset,
                                       width: w, height: overlayRowH, selected: o.id == selectedOverlay)
            tile.frame = CGRect(x: x, y: y, width: w, height: overlayRowH)
            contentView.addSubview(tile)
            overlayItems.append(Item(id: o.id, frame: tile.frame, view: tile))
        }
        if let id = selectedOverlay, let item = overlayItems.first(where: { $0.id == id }) {
            contentView.bringSubviewToFront(item.view)
        }

        // 3. Иконки переходов
        if clips.count > 1 {
            for j in 0..<(clips.count - 1) {
                let cx = side + CGFloat(layout.starts[j + 1].secs) * pps
                let f = CGRect(x: cx - 13, y: mainTop + clipHeight / 2 - 13, width: 26, height: 26)
                transitionFrames.append(f)
                let spec = TransitionCatalog.spec(clips[j].transitionID)
                let has = spec != nil
                let v = UIView(frame: f)
                v.backgroundColor = has ? Theme.accent : UIColor(white: 0.95, alpha: 0.95)
                v.layer.cornerRadius = 13
                v.layer.shadowColor = UIColor.black.cgColor
                v.layer.shadowOpacity = 0.4
                v.layer.shadowRadius = 3
                v.layer.shadowOffset = .zero
                let icon = UIImageView(image: UIImage(systemName: spec?.category.symbol ?? "rectangle.on.rectangle"))
                icon.tintColor = .black
                icon.contentMode = .scaleAspectFit
                icon.frame = CGRect(x: 5, y: 5, width: 16, height: 16)
                v.addSubview(icon)
                contentView.addSubview(v)
                transitionViews.append(v)
            }
        }

        // Текст
        for (k, o) in texts.enumerated() {
            let x = side + CGFloat(o.start) * pps
            let w = max(24, CGFloat(o.duration) * pps)
            let y = textBase + CGFloat(tl.lane[k]) * laneStep
            let bar = PaddingLabel()
            bar.insets = UIEdgeInsets(top: 0, left: 16, bottom: 0, right: 8)
            bar.frame = CGRect(x: x, y: y, width: w, height: laneHeight)
            bar.text = "T  " + o.text.replacingOccurrences(of: "\n", with: " ")
            bar.font = .systemFont(ofSize: 11, weight: .semibold)
            bar.textColor = .white
            bar.backgroundColor = Theme.textBar
            bar.layer.cornerRadius = 6
            bar.clipsToBounds = true
            if o.id == selectedText {
                bar.layer.borderWidth = 2
                bar.layer.borderColor = UIColor.white.cgColor
                addTrimHandles(to: bar)
            }
            contentView.addSubview(bar)
            textItems.append(Item(id: o.id, frame: bar.frame, view: bar))
        }

        // Аудио
        for (k, a) in audios.enumerated() {
            let x = side + CGFloat(a.start) * pps
            let w = max(24, CGFloat(a.duration) * pps)
            let y = audioBase + CGFloat(al.lane[k]) * laneStep
            let bar = AudioBarView(frame: CGRect(x: x, y: y, width: w, height: laneHeight))
            bar.title = a.title
            bar.offset = a.sourceOffset
            bar.duration = a.duration
            bar.volume = a.volume
            bar.fadeIn = a.fadeIn
            bar.fadeOut = a.fadeOut
            bar.peaks = WaveformStore.shared.peaks(for: a.processed ?? a.asset) ?? []
            if a.id == selectedAudio {
                bar.layer.borderWidth = 2
                bar.layer.borderColor = UIColor.white.cgColor
                addTrimHandles(to: bar)
            }
            contentView.addSubview(bar)
            audioItems.append(Item(id: a.id, frame: bar.frame, view: bar))
        }

        addTile.frame = CGRect(x: side + trackWidth + 10, y: mainTop, width: 56, height: clipHeight)
        contentView.addSubview(addTile)

        let needed = max(TimelineView.minHeight, audioBase + CGFloat(audioRows) * laneStep + 8)
        if abs(needed - requiredHeight) > 0.5 {
            requiredHeight = needed
            onNeedHeight?(needed)
        }
    }

    @objc private func handleTap(_ g: UITapGestureRecognizer) {
        let p = g.location(in: contentView)

        if addTile.frame.contains(p) { onTapAdd?(); return }

        for (j, f) in transitionFrames.enumerated() where f.insetBy(dx: -6, dy: -6).contains(p) {
            onTapTransition?(j)
            return
        }
        
        for item in textItems.reversed() where item.frame.contains(p) {
            onSelectText?(item.id)
            onOpenTextEditor?(item.id)
            return
        }
        
        for item in audioItems.reversed() where item.frame.contains(p) {
            onSelectAudio?(item.id)
            onOpenAudioEditor?(item.id)
            return
        }
        
        for item in overlayItems.reversed() where item.frame.contains(p) {
            if item.id == selectedOverlay { onDeselectAll?() } else { onSelectOverlay?(item.id) }
            return
        }

        for (i, f) in clipFrames.enumerated().reversed() where f.contains(p) {
            if i == selectedClip { onDeselectAll?() } else { onSelectClip?(i) }
            return
        }
        for row in laneRows where row.rect.contains(p) {
            onFocusLane?(row.lane)
            return
        }
        onDeselectAll?()
    }

    private func hitTarget(at p: CGPoint) -> DragKind? {
        if let s = selectedClip, s < clipFrames.count {
            let f = clipFrames[s]
            let hz = min(handleZone, max(18, f.width / 2))
            if p.y >= f.minY - 6 && p.y <= f.maxY + 6 {
                if p.x >= f.minX - 14 && p.x <= f.minX + hz { return .clipLeft(s) }
                if p.x <= f.maxX + 14 && p.x >= f.maxX - hz { return .clipRight(s) }
            }
        }
        if let id = selectedText, let item = textItems.first(where: { $0.id == id }),
           item.frame.insetBy(dx: -10, dy: -4).contains(p) {
            let hz = min(handleZone, item.frame.width / 3)
            if p.x <= item.frame.minX + hz { return .textLeft(id) }
            if p.x >= item.frame.maxX - hz { return .textRight(id) }
        }
        if let id = selectedAudio, let item = audioItems.first(where: { $0.id == id }),
           item.frame.insetBy(dx: -10, dy: -4).contains(p) {
            let hz = min(handleZone, item.frame.width / 3)
            if p.x <= item.frame.minX + hz { return .audioLeft(id) }
            if p.x >= item.frame.maxX - hz { return .audioRight(id) }
        }
        if let id = selectedOverlay, let item = overlayItems.first(where: { $0.id == id }),
           item.frame.insetBy(dx: -10, dy: -4).contains(p) {
            let hz = min(handleZone, item.frame.width / 3)
            if p.x <= item.frame.minX + hz { return .overlayLeft(id) }
            if p.x >= item.frame.maxX - hz { return .overlayRight(id) }
        }
        return nil
    }

    private func hitMoveTarget(at p: CGPoint) -> DragKind? {
        for (i, f) in clipFrames.enumerated() where f.contains(p) {
            return .clipMove(i)
        }
        for item in textItems.reversed() where item.frame.contains(p) {
            return .textMove(item.id)
        }
        for item in audioItems.reversed() where item.frame.contains(p) {
            return .audioMove(item.id)
        }
        for item in overlayItems.reversed() where item.frame.contains(p) {
            return .overlayMove(item.id)
        }
        return nil
    }

    override func gestureRecognizerShouldBegin(_ g: UIGestureRecognizer) -> Bool {
        if g === pinch { return drag == nil && moveDrag == nil }
        if g === dragPan {
            if moveDrag != nil { return false }
            return hitTarget(at: scrollView.touchDownPoint) != nil
        }
        return true
    }

    // MARK: - Drag (Обрезка краёв)
    @objc private func handleDrag(_ g: UIPanGestureRecognizer) {
        let x = g.location(in: self).x
        switch g.state {
        case .began:
            let p = scrollView.touchDownPoint
            if let kind = hitTarget(at: p) {
                let startX = contentView.convert(p, to: self).x
                beginDrag(kind, x: startX)
                updateDrag(x: x)
            }
        case .changed:
            updateDrag(x: x)
        case .ended:
            endDrag(commit: true)
        case .cancelled, .failed:
            endDrag(commit: false)
        default:
            break
        }
    }

    private func beginDrag(_ kind: DragKind, x: CGFloat) {
        var view: UIView?
        var srcR: CMTimeRange?
        switch kind {
        case .clipLeft(let i), .clipRight(let i):
            if i < clipViews.count {
                view = clipViews[i]
                srcR = clips[i].sourceRange
            }
        case .textLeft(let id), .textRight(let id):
            view = textItems.first { $0.id == id }?.view
        case .audioLeft(let id), .audioRight(let id):
            view = audioItems.first { $0.id == id }?.view
        case .overlayLeft(let id), .overlayRight(let id):
            view = overlayItems.first { $0.id == id }?.view
        default: break
        }
        guard let v = view else { return }
        drag = DragState(kind: kind, startTouchX: x, view: v, origFrame: v.frame, initialSrcRange: srcR, currentSrcRange: srcR)
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        v.superview?.bringSubviewToFront(v)
    }

    private func updateDrag(x: CGFloat) {
        guard var d = drag else { return }
        if abs(x - d.startTouchX) > 2 { d.moved = true }
        
        let deltaSecs = Double((x - d.startTouchX) / pps)
        let total = totalSeconds
        let side = bounds.width / 2
        
        switch d.kind {
        case .clipLeft(let i), .clipRight(let i):
            guard i < clips.count, let origR = d.initialSrcRange else { break }
            let c = clips[i]
            let speed = Double(c.speed)
            let s0 = origR.start.secs
            let e0 = origR.end.secs
            let assetDur = floor(c.asset.duration.secs * Double(kTimescale)) / Double(kTimescale)
            
            var ns = s0, ne = e0
            var isLeft = false
            if case .clipLeft = d.kind { isLeft = true }
            
            if isLeft {
                ns = min(max(0, s0 + deltaSecs * speed), e0 - minDur * speed)
            } else {
                ne = max(min(assetDur, e0 + deltaSecs * speed), s0 + minDur * speed)
            }
            
            let newSrcRange = CMTimeRange(start: ticks(ns), end: ticks(ne))
            d.currentSrcRange = newSrcRange
            
            let newDisplayDurSecs = (ne - ns) / speed
            let w = max(12, CGFloat(newDisplayDurSecs) * pps)
            let xx = isLeft ? (d.origFrame.maxX - w) : d.origFrame.minX
            d.view.frame = CGRect(x: xx, y: d.origFrame.minY, width: w, height: d.origFrame.height)
            
            let baseStart = layout.starts[i].secs
            let currentCutSecs = isLeft ? (baseStart + (ns - s0) / speed) : (baseStart + (ne - s0) / speed)
            onClipTrimming?(max(0, currentCutSecs))
            
        case .textLeft(let id), .textRight(let id):
            guard let o = texts.first(where: { $0.id == id }) else { break }
            let s0 = o.start, e0 = o.start + o.duration
            var ns = s0, ne = e0
            if case .textLeft = d.kind {
                ns = min(max(0, s0 + deltaSecs), e0 - minDur)
            } else {
                ne = max(min(total, e0 + deltaSecs), s0 + minDur)
            }
            d.start = ns; d.duration = ne - ns
            d.view.frame = CGRect(x: side + CGFloat(ns) * pps, y: d.origFrame.minY,
                                  width: max(24, CGFloat(ne - ns) * pps), height: d.origFrame.height)
            
        case .audioLeft(let id), .audioRight(let id):
            guard let a = audios.first(where: { $0.id == id }) else { break }
            let s0 = a.start, e0 = a.start + a.duration
            var ns = s0, ne = e0, off = a.sourceOffset
            if case .audioLeft = d.kind {
                let minStart = max(0, s0 - a.sourceOffset)
                ns = min(max(minStart, s0 + deltaSecs), e0 - minDur)
                off = a.sourceOffset + (ns - s0)
            } else {
                let maxEnd = min(total, s0 + (a.sourceDuration - a.sourceOffset))
                ne = max(min(maxEnd, e0 + deltaSecs), s0 + minDur)
            }
            d.start = ns; d.duration = ne - ns; d.offset = off
            d.view.frame = CGRect(x: side + CGFloat(ns) * pps, y: d.origFrame.minY,
                                  width: max(24, CGFloat(ne - ns) * pps), height: d.origFrame.height)
            if let bar = d.view as? AudioBarView {
                bar.offset = off
                bar.duration = ne - ns
                bar.setNeedsDisplay()
            }

        case .overlayLeft(let id), .overlayRight(let id):
            guard let o = overlays.first(where: { $0.id == id }) else { break }
            let maxSrc = OverlayMedia.info(for: o.file)?.duration ?? (o.sourceStart + o.duration)
            let s0 = o.start, e0 = o.start + o.duration
            var ns = s0, ne = e0, off = o.sourceStart
            if case .overlayLeft = d.kind {
                // у видео нельзя уйти левее начала исходника, у картинки — можно (кадр один)
                let minStart = o.isImage ? 0 : max(0, s0 - o.sourceStart)
                ns = min(max(minStart, s0 + deltaSecs), e0 - minDur)
                if !o.isImage { off = o.sourceStart + (ns - s0) }
            } else {
                let maxEnd = o.isImage ? total : min(total, s0 + (maxSrc - o.sourceStart))
                ne = max(min(maxEnd, e0 + deltaSecs), s0 + minDur)
            }
            d.start = ns; d.duration = ne - ns; d.offset = off
            d.view.frame = CGRect(x: side + CGFloat(ns) * pps, y: d.origFrame.minY,
                                  width: max(24, CGFloat(ne - ns) * pps), height: d.origFrame.height)
        default: break
        }
        drag = d
    }

    private func endDrag(commit: Bool) {
        guard let d = drag else { return }
        drag = nil
        guard commit, d.moved else {
            rebuildContent()
            return
        }
        switch d.kind {
        case .clipLeft(let i), .clipRight(let i):
            if let r = d.currentSrcRange { onClipTrimmed?(i, r) }
        case .textLeft(let id), .textRight(let id):
            onTextTimeChanged?(id, d.start, d.duration)
        case .audioLeft(let id), .audioRight(let id):
            onAudioTimeChanged?(id, d.start, d.offset, d.duration)
        case .overlayLeft(let id), .overlayRight(let id):
            onOverlayTimeChanged?(id, d.start, d.offset, d.duration)
        default: break
        }
    }

    // MARK: - Move (долгое нажатие: перестановка видео, сдвиг текста/аудио)

    @objc private func handleLongPress(_ g: UILongPressGestureRecognizer) {
        switch g.state {
        case .began:
            guard drag == nil, moveDrag == nil else { return }
            let p = g.location(in: contentView)
            guard let kind = hitMoveTarget(at: p) else { return }
            moveTouchX = g.location(in: self).x
            scrollView.isLongPressActive = true
            scrollView.isScrollEnabled = false
            beginMoveDrag(kind, touchContentX: p.x)
            if moveDrag == nil {            // не смогли начать — вернуть скролл
                scrollView.isLongPressActive = false
                scrollView.isScrollEnabled = true
            }
        case .changed:
            guard moveDrag != nil else { return }
            moveTouchX = g.location(in: self).x
            updateMoveDrag()
        case .ended, .cancelled, .failed:
            let had = moveDrag != nil
            scrollView.isLongPressActive = false
            scrollView.isScrollEnabled = true
            if had { endMoveDrag(commit: g.state == .ended) }
        default:
            break
        }
    }

    private func beginMoveDrag(_ kind: DragKind, touchContentX: CGFloat) {
        var state: MoveDragState?

        switch kind {
        case .clipMove(let i):
            guard i < clipViews.count else { return }
            let v = clipViews[i]
            var s = MoveDragState(kind: kind, view: v, origFrame: v.frame, grabOffsetX: touchContentX - v.frame.minX)
            s.fromIndex = i; s.toIndex = i; s.slotX = v.frame.minX
            state = s
        case .textMove(let id):
            guard let item = textItems.first(where: { $0.id == id }),
                  let o = texts.first(where: { $0.id == id }) else { return }
            var s = MoveDragState(kind: kind, view: item.view, origFrame: item.view.frame,
                                  grabOffsetX: touchContentX - item.view.frame.minX)
            s.origStart = o.start; s.newStart = o.start; s.duration = o.duration
            state = s
        case .audioMove(let id):
            guard let item = audioItems.first(where: { $0.id == id }),
                  let a = audios.first(where: { $0.id == id }) else { return }
            var s = MoveDragState(kind: kind, view: item.view, origFrame: item.view.frame,
                                  grabOffsetX: touchContentX - item.view.frame.minX)
            s.origStart = a.start; s.newStart = a.start; s.duration = a.duration; s.sourceOffset = a.sourceOffset
            state = s
        case .overlayMove(let id):
            guard let item = overlayItems.first(where: { $0.id == id }),
                  let o = overlays.first(where: { $0.id == id }) else { return }
            var s = MoveDragState(kind: kind, view: item.view, origFrame: item.view.frame,
                                  grabOffsetX: touchContentX - item.view.frame.minX)
            s.origStart = o.start; s.newStart = o.start; s.duration = o.duration; s.sourceOffset = o.sourceStart
            state = s
        default:
            return
        }

        guard let s = state else { return }
        moveDrag = s

        if case .clipMove = kind {
            // иконки переходов на время перетаскивания прячем — они привязаны к старым стыкам
            transitionViews.forEach { $0.alpha = 0 }
        }

        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        s.view.superview?.bringSubviewToFront(s.view)
        UIView.animate(withDuration: 0.15) {
            s.view.transform = CGAffineTransform(scaleX: 1.02, y: 1.05)
            s.view.alpha = 0.9
        }
        startAutoScroll()
    }

    /// Вызывается и при движении пальца, и из таймера автоскролла.
    private func updateMoveDrag() {
        guard let d = moveDrag else { return }
        let side = bounds.width / 2
        let trackWidth = CGFloat(totalSeconds) * pps
        let w = d.origFrame.width

        // Позиция пальца в координатах контента (учитывает автоскролл) минус точка захвата.
        // Никаких накопленных дельт и frame под transform — только center.x.
        let touchContentX = moveTouchX + scrollView.contentOffset.x
        let lo = side
        let hi = max(lo, side + trackWidth - w)
        let minX = min(max(touchContentX - d.grabOffsetX, lo), hi)
        d.view.center.x = minX + w / 2

        switch d.kind {
        case .clipMove:
            updateClipSlots(dragCenterX: minX + w / 2)
        case .textMove, .audioMove, .overlayMove:
            moveDrag?.newStart = Double((minX - side) / pps)
        default:
            break
        }
    }

    /// Пересчёт места вставки клипа. Считаем по серединам ОСТАЛЬНЫХ клипов — это стабильно, без дребезга.
    /// Остальные плитки плавно разъезжаются, ленту не пересобираем.
    private func updateClipSlots(dragCenterX: CGFloat) {
        guard let d = moveDrag, case .clipMove = d.kind else { return }
        let side = bounds.width / 2
        let from = d.fromIndex
        let n = min(clips.count, clipViews.count, layout.durations.count)
        guard from < n else { return }

        var cursor = side
        var to = 0
        for idx in 0..<n where idx != from {
            let sw = CGFloat(layout.durations[idx].secs) * pps
            if dragCenterX > cursor + sw / 2 { to += 1 }
            cursor += sw
        }
        guard to != d.toIndex else { return }
        moveDrag?.toIndex = to

        var order = Array(0..<n)
        order.remove(at: from)
        order.insert(from, at: to)

        var x = side
        var slotX = d.origFrame.minX
        var targets: [(UIView, CGFloat)] = []
        for idx in order {
            let sw = CGFloat(layout.durations[idx].secs) * pps
            if idx == from { slotX = x + 1 } else { targets.append((clipViews[idx], x + 1)) }
            x += sw
        }
        moveDrag?.slotX = slotX

        UISelectionFeedbackGenerator().selectionChanged()
        UIView.animate(withDuration: 0.2, delay: 0,
                       options: [.curveEaseOut, .beginFromCurrentState, .allowUserInteraction]) {
            for (v, tx) in targets { v.frame.origin.x = tx }
        }
    }

    private func endMoveDrag(commit: Bool) {
        guard let d = moveDrag else { return }
        moveDrag = nil
        stopAutoScroll()
        syncPlayheadAfterAutoScroll()

        let settle: (CGFloat?) -> Void = { x in
            d.view.transform = .identity
            d.view.alpha = 1
            if let x = x { d.view.frame.origin.x = x }
        }

        switch d.kind {
        case .clipMove:
            if commit, d.toIndex != d.fromIndex, d.fromIndex < clips.count {
                var newClips = clips
                let moved = newClips.remove(at: d.fromIndex)
                newClips.insert(moved, at: min(d.toIndex, newClips.count))
                UIView.animate(withDuration: 0.18, animations: { settle(d.slotX) }) { [weak self] _ in
                    guard let self = self, self.moveDrag == nil else { return }
                    self.onClipsReordered?(newClips)
                }
            } else {
                UIView.animate(withDuration: 0.18, animations: { settle(d.origFrame.minX) }) { [weak self] _ in
                    guard let self = self, self.moveDrag == nil else { return }
                    self.rebuildContent()
                }
            }

        case .textMove(let id):
            UIView.animate(withDuration: 0.12) { settle(nil) }
            if commit, abs(d.newStart - d.origStart) > 0.001 {
                onTextTimeChanged?(id, d.newStart, d.duration)
            } else {
                rebuildContent()
            }

        case .audioMove(let id):
            UIView.animate(withDuration: 0.12) { settle(nil) }
            if commit, abs(d.newStart - d.origStart) > 0.001 {
                onAudioTimeChanged?(id, d.newStart, d.sourceOffset, d.duration)
            } else {
                rebuildContent()
            }

        case .overlayMove(let id):
            UIView.animate(withDuration: 0.12) { settle(nil) }
            if commit, abs(d.newStart - d.origStart) > 0.001 {
                onOverlayTimeChanged?(id, d.newStart, d.sourceOffset, d.duration)
            } else {
                rebuildContent()
            }

        default:
            rebuildContent()
        }
    }

    // MARK: - Автоскролл у краёв (лента во время перетаскивания не скроллится пальцем)

    private func startAutoScroll() {
        guard autoScrollLink == nil else { return }
        let link = CADisplayLink(target: self, selector: #selector(autoScrollTick(_:)))
        link.add(to: .main, forMode: .common)
        autoScrollLink = link
        autoScrollStartOffset = scrollView.contentOffset.x
    }

    private func stopAutoScroll() {
        autoScrollLink?.invalidate()
        autoScrollLink = nil
    }

    @objc private func autoScrollTick(_ link: CADisplayLink) {
        guard moveDrag != nil else { stopAutoScroll(); return }
        let edge: CGFloat = 56
        let maxSpeed: CGFloat = 520            // pt/сек
        let x = min(max(moveTouchX, 0), bounds.width)
        var speed: CGFloat = 0
        if x < edge {
            speed = -maxSpeed * (edge - x) / edge
        } else if x > bounds.width - edge {
            speed = maxSpeed * (x - (bounds.width - edge)) / edge
        }
        guard speed != 0 else { return }

        let maxOffset = max(0, scrollView.contentSize.width - scrollView.bounds.width)
        let dt = CGFloat(link.targetTimestamp - link.timestamp)
        let newX = min(max(0, scrollView.contentOffset.x + speed * dt), maxOffset)
        guard newX != scrollView.contentOffset.x else { return }

        isProgrammatic = true
        scrollView.contentOffset.x = newX
        isProgrammatic = false
        updateMoveDrag()
    }

    /// Если лента уехала автоскроллом — красная палка теперь на другом времени, синхронизируем превью.
    private func syncPlayheadAfterAutoScroll() {
        guard abs(scrollView.contentOffset.x - autoScrollStartOffset) > 0.5 else { return }
        let t = max(0, min(totalSeconds, Double(scrollView.contentOffset.x / pps)))
        lastPlayheadTime = t
        onScrubBegan?()
        onScrub?(t)
    }

    func scrollViewWillBeginDragging(_ scrollView: UIScrollView) {
        onScrubBegan?()
    }

    func scrollViewDidScroll(_ sv: UIScrollView) {
        ruler.offsetX = sv.contentOffset.x
        ruler.setNeedsDisplay()
        guard !isProgrammatic, sv.isTracking || sv.isDragging || sv.isDecelerating else { return }
        let t = max(0, min(totalSeconds, Double(sv.contentOffset.x / pps)))
        lastPlayheadTime = t
        onScrub?(t)
    }
}
