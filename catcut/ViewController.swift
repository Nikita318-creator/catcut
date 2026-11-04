import UIKit
import AVFoundation
import CoreImage
import CoreMedia
import PhotosUI
import Photos
import UniformTypeIdentifiers
import SnapKit

// =====================================================================
// MARK: - Theme & helpers
// =====================================================================

enum Theme {
    static let background = UIColor(red: 18/255, green: 18/255, blue: 18/255, alpha: 1)
    static let panel = UIColor(white: 0.09, alpha: 1)
    static let surface = UIColor(white: 0.18, alpha: 1)
    static let accent = UIColor(red: 0.18, green: 0.85, blue: 0.80, alpha: 1)
    static let textBar = UIColor(red: 0.45, green: 0.35, blue: 0.85, alpha: 1)
}

/// Всё время внутри редактора живёт в одной шкале (600 тиков/сек),
/// иначе на стыках клипов появляются микро-щели и AVFoundation ругается.
let kTimescale: CMTimeScale = 600

func ticks(_ seconds: Double) -> CMTime {
    CMTime(value: Int64((max(0, seconds) * Double(kTimescale)).rounded()), timescale: kTimescale)
}

func floorTicks(_ seconds: Double) -> CMTime {
    CMTime(value: Int64((max(0, seconds) * Double(kTimescale)).rounded(.down)), timescale: kTimescale)
}

extension CMTime {
    var secs: Double {
        let s = CMTimeGetSeconds(self)
        return s.isFinite ? s : 0
    }
}

func imageOrientation(for t: CGAffineTransform) -> CGImagePropertyOrientation {
    let a = Int(t.a.rounded()), b = Int(t.b.rounded()), c = Int(t.c.rounded()), d = Int(t.d.rounded())
    switch (a, b, c, d) {
    case (0, 1, -1, 0): return .right
    case (0, -1, 1, 0): return .left
    case (-1, 0, 0, -1): return .down
    default: return .up
    }
}

// =====================================================================
// MARK: - Filters (у каждого клипа свой)
// =====================================================================

enum FilterType: Int, CaseIterable {
    case none, vivid, warm, cool, sepia, noir, mono, chrome, fade, instant, process, transfer, tonal, vignette, dramatic, bright

    var displayName: String {
        switch self {
        case .none: return "Оригинал"
        case .vivid: return "Яркий"
        case .warm: return "Тёплый"
        case .cool: return "Холодный"
        case .sepia: return "Сепия"
        case .noir: return "Нуар"
        case .mono: return "Моно"
        case .chrome: return "Хром"
        case .fade: return "Выцвет"
        case .instant: return "Инстант"
        case .process: return "Процесс"
        case .transfer: return "Ретро"
        case .tonal: return "Тональный"
        case .vignette: return "Виньетка"
        case .dramatic: return "Драма"
        case .bright: return "Светлый"
        }
    }

    func apply(to input: CIImage) -> CIImage {
        let extent = input.extent

        func run(_ name: String, _ params: [String: Any] = [:], on image: CIImage? = nil) -> CIImage {
            let source = image ?? input
            guard let f = CIFilter(name: name) else { return source }
            f.setValue(source, forKey: kCIInputImageKey)
            for (k, v) in params where f.inputKeys.contains(k) { f.setValue(v, forKey: k) }
            return f.outputImage?.cropped(to: extent) ?? source
        }

        switch self {
        case .none:
            return input
        case .vivid:
            return run("CIColorControls", [kCIInputSaturationKey: 1.55, kCIInputContrastKey: 1.1])
        case .warm:
            return run("CIColorMatrix", [
                "inputRVector": CIVector(x: 1.12, y: 0, z: 0, w: 0),
                "inputGVector": CIVector(x: 0, y: 1.02, z: 0, w: 0),
                "inputBVector": CIVector(x: 0, y: 0, z: 0.86, w: 0),
                "inputAVector": CIVector(x: 0, y: 0, z: 0, w: 1),
                "inputBiasVector": CIVector(x: 0.02, y: 0.01, z: 0, w: 0)
            ])
        case .cool:
            return run("CIColorMatrix", [
                "inputRVector": CIVector(x: 0.88, y: 0, z: 0, w: 0),
                "inputGVector": CIVector(x: 0, y: 1.0, z: 0, w: 0),
                "inputBVector": CIVector(x: 0, y: 0, z: 1.15, w: 0),
                "inputAVector": CIVector(x: 0, y: 0, z: 0, w: 1),
                "inputBiasVector": CIVector(x: 0, y: 0.01, z: 0.03, w: 0)
            ])
        case .sepia:
            return run("CISepiaTone", [kCIInputIntensityKey: 0.9])
        case .noir:
            return run("CIPhotoEffectNoir")
        case .mono:
            return run("CIPhotoEffectMono")
        case .chrome:
            return run("CIPhotoEffectChrome")
        case .fade:
            return run("CIPhotoEffectFade")
        case .instant:
            return run("CIPhotoEffectInstant")
        case .process:
            return run("CIPhotoEffectProcess")
        case .transfer:
            return run("CIPhotoEffectTransfer")
        case .tonal:
            return run("CIPhotoEffectTonal")
        case .vignette:
            return run("CIVignette", [kCIInputIntensityKey: 1.3, kCIInputRadiusKey: 1.6])
        case .dramatic:
            let c = run("CIColorControls", [kCIInputContrastKey: 1.3, kCIInputSaturationKey: 0.8])
            return run("CIVignette", [kCIInputIntensityKey: 1.0, kCIInputRadiusKey: 1.8], on: c)
        case .bright:
            return run("CIColorControls", [kCIInputBrightnessKey: 0.1, kCIInputContrastKey: 1.05, kCIInputSaturationKey: 1.1])
        }
    }
}

// =====================================================================
// MARK: - Transitions
// =====================================================================

enum TransitionType: Int, CaseIterable {
    case none, dissolve, fadeBlack, fadeWhite
    case pushLeft, pushRight, pushUp, pushDown
    case slideLeft, slideRight
    case wipeLeft, wipeRight, wipeUp, wipeDown
    case zoomIn, zoomOut, blur, spin, pixelate, bars, flash, mod

    var title: String {
        switch self {
        case .none: return "Нет"
        case .dissolve: return "Растворение"
        case .fadeBlack: return "Через чёрный"
        case .fadeWhite: return "Через белый"
        case .pushLeft: return "Сдвиг ←"
        case .pushRight: return "Сдвиг →"
        case .pushUp: return "Сдвиг ↑"
        case .pushDown: return "Сдвиг ↓"
        case .slideLeft: return "Наезд ←"
        case .slideRight: return "Наезд →"
        case .wipeLeft: return "Шторка ←"
        case .wipeRight: return "Шторка →"
        case .wipeUp: return "Шторка ↑"
        case .wipeDown: return "Шторка ↓"
        case .zoomIn: return "Приближение"
        case .zoomOut: return "Отдаление"
        case .blur: return "Размытие"
        case .spin: return "Вращение"
        case .pixelate: return "Пиксели"
        case .bars: return "Полосы"
        case .flash: return "Вспышка"
        case .mod: return "Узор"
        }
    }

    var symbol: String {
        switch self {
        case .none: return "xmark"
        case .dissolve: return "drop.halffull"
        case .fadeBlack: return "moon.fill"
        case .fadeWhite: return "sun.max.fill"
        case .pushLeft: return "arrow.left"
        case .pushRight: return "arrow.right"
        case .pushUp: return "arrow.up"
        case .pushDown: return "arrow.down"
        case .slideLeft: return "chevron.left.2"
        case .slideRight: return "chevron.right.2"
        case .wipeLeft: return "backward.end.fill"
        case .wipeRight: return "forward.end.fill"
        case .wipeUp: return "chevron.compact.up"
        case .wipeDown: return "chevron.compact.down"
        case .zoomIn: return "plus.magnifyingglass"
        case .zoomOut: return "minus.magnifyingglass"
        case .blur: return "eye.slash"
        case .spin: return "arrow.triangle.2.circlepath"
        case .pixelate: return "square.grid.2x2.fill"
        case .bars: return "list.bullet"
        case .flash: return "bolt.fill"
        case .mod: return "star.fill"
        }
    }
}

// =====================================================================
// MARK: - Models
// =====================================================================

struct VideoClip {
    var id = UUID()
    let asset: AVAsset
    /// Какой кусок исходника используем (в шкале 600).
    var sourceRange: CMTimeRange
    var speed: Float = 1.0
    var filter: FilterType = .none
    var filterIntensity: Float = 1.0
    /// Переход ПОСЛЕ этого клипа (между ним и следующим).
    var transition: TransitionType = .none
    var transitionDuration: Double = 0.6
    var volume: Float = 1.0

    /// Длительность клипа на таймлайне (с учётом скорости).
    var displayDuration: CMTime {
        ticks(sourceRange.duration.secs / Double(speed))
    }
}

enum TextStyle {
    static let colors: [UIColor] = [.white, .systemYellow, .systemRed, .cyan, .systemPink, .systemGreen, .black]
}

struct TextOverlay {
    var id = UUID()
    var text: String
    var start: Double
    var duration: Double
    /// Центр текста, 0...1 (y считается сверху).
    var position = CGPoint(x: 0.5, y: 0.5)
    /// Размер шрифта как доля высоты кадра.
    var size: CGFloat = 0.05
    var colorIndex: Int = 0

    var color: UIColor { TextStyle.colors[max(0, min(colorIndex, TextStyle.colors.count - 1))] }
}

/// Раскладка клипов на таймлайне: старты, длительности и перекрытия под переходы.
struct TimelineLayout {
    var starts: [CMTime] = []
    var durations: [CMTime] = []
    /// overlapAfter[i] — на сколько клип i перекрывается со следующим (переход).
    var overlapAfter: [CMTime] = []
    var total: CMTime = .zero

    init(clips: [VideoClip]) {
        guard !clips.isEmpty else { return }
        durations = clips.map { $0.displayDuration }

        for i in 0..<clips.count {
            if i < clips.count - 1, clips[i].transition != .none {
                let maxAllowed = 0.5 * min(durations[i].secs, durations[i + 1].secs)
                let d = min(clips[i].transitionDuration, maxAllowed)
                overlapAfter.append(d >= 0.1 ? floorTicks(d) : .zero)
            } else {
                overlapAfter.append(.zero)
            }
        }

        var cursor = CMTime.zero
        for i in 0..<clips.count {
            starts.append(cursor)
            cursor = cursor + durations[i] - overlapAfter[i]
        }
        total = starts[clips.count - 1] + durations[clips.count - 1]
    }

    func overlapIn(_ i: Int) -> CMTime { i > 0 ? overlapAfter[i - 1] : .zero }
    func overlapOut(_ i: Int) -> CMTime { overlapAfter[i] }

    func end(of i: Int) -> CMTime { starts[i] + durations[i] }

    /// Какой клип сейчас под красной палкой.
    func index(at t: CMTime) -> Int? {
        guard !starts.isEmpty else { return nil }
        let ts = t.secs
        var best: Int?
        var bestScore = -Double.infinity
        for i in 0..<starts.count {
            let s = starts[i].secs
            let e = end(of: i).secs
            if ts >= s - 0.0005 && ts <= e + 0.0005 {
                let score = min(ts - s, e - ts)
                if score > bestScore { bestScore = score; best = i }
            }
        }
        if best == nil { return ts <= 0 ? 0 : starts.count - 1 }
        return best
    }
}

// =====================================================================
// MARK: - Thumbnails (один раз на файл, дальше режем как угодно)
// =====================================================================

final class ThumbnailStore {
    static let shared = ThumbnailStore()
    var onUpdate: (() -> Void)?

    private final class Entry {
        let asset: AVAsset
        let step: Double
        var images: [UIImage?]
        var generator: AVAssetImageGenerator?
        init(asset: AVAsset, step: Double, count: Int) {
            self.asset = asset
            self.step = step
            self.images = [UIImage?](repeating: nil, count: count)
        }
    }

    private var entries: [ObjectIdentifier: Entry] = [:]
    private var notifyScheduled = false

    func prepare(_ asset: AVAsset) {
        let key = ObjectIdentifier(asset)
        guard entries[key] == nil else { return }

        let duration = max(0.1, asset.duration.secs)
        let count = min(90, max(2, Int(ceil(duration / 0.5))))
        let step = duration / Double(count)
        let entry = Entry(asset: asset, step: step, count: count)
        entries[key] = entry

        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 240, height: 240)
        generator.requestedTimeToleranceBefore = .positiveInfinity
        generator.requestedTimeToleranceAfter = .positiveInfinity
        entry.generator = generator

        let times: [NSValue] = (0..<count).map {
            NSValue(time: CMTime(seconds: (Double($0) + 0.5) * step, preferredTimescale: 600))
        }

        generator.generateCGImagesAsynchronously(forTimes: times) { [weak self] requested, cg, _, result, _ in
            guard result == .succeeded, let cg = cg else { return }
            let idx = max(0, min(count - 1, Int(requested.seconds / step)))
            let image = UIImage(cgImage: cg)
            DispatchQueue.main.async {
                guard let self = self else { return }
                entry.images[idx] = image
                self.scheduleNotify()
            }
        }
    }

    func image(for asset: AVAsset, at seconds: Double) -> UIImage? {
        let key = ObjectIdentifier(asset)
        guard let entry = entries[key] else {
            prepare(asset)
            return nil
        }
        let count = entry.images.count
        let idx = max(0, min(count - 1, Int(seconds / entry.step)))
        if let img = entry.images[idx] { return img }
        var d = 1
        while d < count {
            if idx - d >= 0, let img = entry.images[idx - d] { return img }
            if idx + d < count, let img = entry.images[idx + d] { return img }
            d += 1
        }
        return nil
    }

    private func scheduleNotify() {
        guard !notifyScheduled else { return }
        notifyScheduled = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            self?.notifyScheduled = false
            self?.onUpdate?()
        }
    }
}

// =====================================================================
// MARK: - Text rendering (один и тот же код для превью и экспорта)
// =====================================================================

enum TextRenderer {
    private static let cache = NSCache<NSString, CIImage>()

    private static func layout(_ o: TextOverlay, canvas: CGSize) -> (attr: NSAttributedString, bound: CGSize, pad: CGFloat, size: CGSize) {
        let fontSize = max(8, o.size * canvas.height)
        let shadow = NSShadow()
        shadow.shadowColor = UIColor.black.withAlphaComponent(0.75)
        shadow.shadowBlurRadius = fontSize * 0.08
        shadow.shadowOffset = CGSize(width: 0, height: fontSize * 0.04)
        let para = NSMutableParagraphStyle()
        para.alignment = .center
        let attrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: fontSize, weight: .heavy),
            .foregroundColor: o.color,
            .shadow: shadow,
            .paragraphStyle: para
        ]
        let attr = NSAttributedString(string: o.text, attributes: attrs)
        let maxW = canvas.width * 0.9
        let rect = attr.boundingRect(with: CGSize(width: maxW, height: .greatestFiniteMagnitude),
                                     options: [.usesLineFragmentOrigin, .usesFontLeading], context: nil)
        let bound = CGSize(width: ceil(rect.width), height: ceil(rect.height))
        let pad = fontSize * 0.3
        return (attr, bound, pad, CGSize(width: bound.width + pad * 2, height: bound.height + pad * 2))
    }

    /// Размер текстовой картинки в пикселях кадра (нужен, чтобы нарисовать рамку в превью).
    static func pixelSize(for o: TextOverlay, canvas: CGSize) -> CGSize {
        layout(o, canvas: canvas).size
    }

    static func image(for o: TextOverlay, canvas: CGSize) -> CIImage? {
        let key = "\(o.id.uuidString)|\(o.text)|\(o.size)|\(o.colorIndex)|\(Int(canvas.width))x\(Int(canvas.height))" as NSString
        if let cached = cache.object(forKey: key) { return cached }

        let l = layout(o, canvas: canvas)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = false
        let ui = UIGraphicsImageRenderer(size: l.size, format: format).image { _ in
            l.attr.draw(with: CGRect(x: l.pad, y: l.pad, width: l.bound.width, height: l.bound.height),
                        options: [.usesLineFragmentOrigin, .usesFontLeading], context: nil)
        }
        guard let cg = ui.cgImage else { return nil }
        let ci = CIImage(cgImage: cg)
        cache.setObject(ci, forKey: key)
        return ci
    }
}

// =====================================================================
// MARK: - Custom compositor: фильтры по клипам + переходы + текст
// =====================================================================

struct LayerInfo {
    let trackID: CMPersistentTrackID
    let orientation: CGImagePropertyOrientation
    let filter: FilterType
    let intensity: Float
}

final class EditorInstruction: NSObject, AVVideoCompositionInstructionProtocol {
    let timeRange: CMTimeRange
    let enablePostProcessing: Bool = false
    let containsTweening: Bool = true
    let requiredSourceTrackIDs: [NSValue]?
    let passthroughTrackID: CMPersistentTrackID = kCMPersistentTrackID_Invalid

    let from: LayerInfo
    let to: LayerInfo?
    let transition: TransitionType
    let texts: [TextOverlay]

    init(timeRange: CMTimeRange, from: LayerInfo, to: LayerInfo?, transition: TransitionType, texts: [TextOverlay]) {
        self.timeRange = timeRange
        self.from = from
        self.to = to
        self.transition = transition
        self.texts = texts
        var ids: [NSValue] = [NSNumber(value: from.trackID)]
        if let to = to { ids.append(NSNumber(value: to.trackID)) }
        self.requiredSourceTrackIDs = ids
        super.init()
    }
}

final class EditorCompositor: NSObject, AVVideoCompositing {

    static let ciContext = CIContext(options: [.cacheIntermediates: false])

    private let renderQueue = DispatchQueue(label: "editor.compositor.render", qos: .userInitiated)
    private let lock = NSLock()
    private var shouldCancel = false

    var sourcePixelBufferAttributes: [String: Any]? {
        [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
    }

    var requiredPixelBufferAttributesForRenderContext: [String: Any] {
        [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
    }

    func renderContextChanged(_ newRenderContext: AVVideoCompositionRenderContext) {}

    func cancelAllPendingVideoCompositionRequests() {
        lock.lock(); shouldCancel = true; lock.unlock()
        renderQueue.async { [weak self] in
            self?.lock.lock(); self?.shouldCancel = false; self?.lock.unlock()
        }
    }

    func startRequest(_ request: AVAsynchronousVideoCompositionRequest) {
        renderQueue.async { [weak self] in
            guard let self = self else { return }
            autoreleasepool {
                self.lock.lock(); let cancelled = self.shouldCancel; self.lock.unlock()
                if cancelled { request.finishCancelledRequest(); return }

                guard let instruction = request.videoCompositionInstruction as? EditorInstruction,
                      let outBuffer = request.renderContext.newPixelBuffer() else {
                    request.finish(with: NSError(domain: "Editor", code: -1, userInfo: nil))
                    return
                }

                let size = request.renderContext.size
                let rect = CGRect(origin: .zero, size: size)
                let time = request.compositionTime.secs

                var output: CIImage
                if let toLayer = instruction.to {
                    let a = self.frame(for: instruction.from, request: request, rect: rect)
                    let b = self.frame(for: toLayer, request: request, rect: rect)
                    let start = instruction.timeRange.start.secs
                    let dur = max(0.001, instruction.timeRange.duration.secs)
                    var p = CGFloat(min(1, max(0, (time - start) / dur)))
                    p = p * p * (3 - 2 * p) // плавное ускорение/замедление
                    output = self.transitionImage(instruction.transition, from: a, to: b, p: p, rect: rect)
                } else {
                    output = self.frame(for: instruction.from, request: request, rect: rect)
                }

                for o in instruction.texts where time >= o.start && time < o.start + o.duration {
                    if let img = TextRenderer.image(for: o, canvas: size) {
                        let cx = o.position.x * size.width
                        let cy = size.height - o.position.y * size.height
                        let moved = img.transformed(by: CGAffineTransform(translationX: cx - img.extent.width / 2,
                                                                          y: cy - img.extent.height / 2))
                        output = moved.composited(over: output)
                    }
                }

                EditorCompositor.ciContext.render(output.cropped(to: rect), to: outBuffer, bounds: rect,
                                                  colorSpace: CGColorSpace(name: CGColorSpace.sRGB))
                request.finish(withComposedVideoFrame: outBuffer)
            }
        }
    }

    // MARK: Frame preparation

    private func black(_ rect: CGRect) -> CIImage {
        CIImage(color: CIColor.black).cropped(to: rect)
    }

    private func frame(for layer: LayerInfo, request: AVAsynchronousVideoCompositionRequest, rect: CGRect) -> CIImage {
        guard let pb = request.sourceFrame(byTrackID: layer.trackID) else { return black(rect) }

        var img = CIImage(cvPixelBuffer: pb).oriented(layer.orientation)
        let e = img.extent
        img = img.transformed(by: CGAffineTransform(translationX: -e.origin.x, y: -e.origin.y))

        // ФИЛЬТР КЛИПА (у каждого клипа свой)
        if layer.filter != .none {
            let filtered = layer.filter.apply(to: img)
            if layer.intensity >= 0.99 {
                img = filtered
            } else {
                img = opacity(filtered, CGFloat(layer.intensity)).composited(over: img)
            }
        }

        // Вписываем в кадр
        let w = img.extent.width, h = img.extent.height
        guard w > 0, h > 0 else { return black(rect) }
        let s = min(rect.width / w, rect.height / h)
        let tx = (rect.width - w * s) / 2
        let ty = (rect.height - h * s) / 2
        img = img.transformed(by: CGAffineTransform(scaleX: s, y: s))
                 .transformed(by: CGAffineTransform(translationX: tx, y: ty))
        return img.composited(over: black(rect)).cropped(to: rect)
    }

    private func opacity(_ image: CIImage, _ a: CGFloat) -> CIImage {
        guard a < 0.999 else { return image }
        return image.applyingFilter("CIColorMatrix", parameters: [
            "inputRVector": CIVector(x: 1, y: 0, z: 0, w: 0),
            "inputGVector": CIVector(x: 0, y: 1, z: 0, w: 0),
            "inputBVector": CIVector(x: 0, y: 0, z: 1, w: 0),
            "inputAVector": CIVector(x: 0, y: 0, z: 0, w: max(0, a)),
            "inputBiasVector": CIVector(x: 0, y: 0, z: 0, w: 0)
        ])
    }

    // MARK: Transitions

    private func transitionImage(_ type: TransitionType, from: CIImage, to: CIImage, p: CGFloat, rect: CGRect) -> CIImage {
        let W = rect.width, H = rect.height
        let blackBG = black(rect)

        func move(_ img: CIImage, _ x: CGFloat, _ y: CGFloat) -> CIImage {
            img.transformed(by: CGAffineTransform(translationX: x, y: y))
        }
        func scaled(_ img: CIImage, _ s: CGFloat) -> CIImage {
            let t = CGAffineTransform(translationX: -W / 2, y: -H / 2)
                .concatenating(CGAffineTransform(scaleX: s, y: s))
                .concatenating(CGAffineTransform(translationX: W / 2, y: H / 2))
            return img.transformed(by: t)
        }
        func rotated(_ img: CIImage, angle: CGFloat, scale: CGFloat) -> CIImage {
            let t = CGAffineTransform(translationX: -W / 2, y: -H / 2)
                .concatenating(CGAffineTransform(rotationAngle: angle))
                .concatenating(CGAffineTransform(scaleX: scale, y: scale))
                .concatenating(CGAffineTransform(translationX: W / 2, y: H / 2))
            return img.transformed(by: t)
        }
        func crossfade(_ a: CIImage, _ b: CIImage, _ t: CGFloat) -> CIImage {
            opacity(b, t).composited(over: a)
        }
        func ciTransition(_ name: String, extra: [String: Any] = [:]) -> CIImage? {
            guard let f = CIFilter(name: name) else { return nil }
            var params: [String: Any] = [
                kCIInputImageKey: from,
                kCIInputTargetImageKey: to,
                kCIInputTimeKey: p,
                kCIInputCenterKey: CIVector(x: rect.midX, y: rect.midY),
                kCIInputExtentKey: CIVector(cgRect: rect)
            ]
            for (k, v) in extra { params[k] = v }
            for (k, v) in params where f.inputKeys.contains(k) { f.setValue(v, forKey: k) }
            return f.outputImage?.cropped(to: rect)
        }

        let result: CIImage
        switch type {
        case .none:
            result = p < 0.5 ? from : to

        case .dissolve:
            result = crossfade(from, to, p)

        case .fadeBlack:
            result = p < 0.5 ? opacity(from, 1 - 2 * p).composited(over: blackBG)
                             : opacity(to, 2 * p - 1).composited(over: blackBG)

        case .fadeWhite:
            let white = CIImage(color: CIColor.white).cropped(to: rect)
            result = p < 0.5 ? opacity(from, 1 - 2 * p).composited(over: white)
                             : opacity(to, 2 * p - 1).composited(over: white)

        case .pushLeft:
            result = move(to, W * (1 - p), 0).composited(over: move(from, -W * p, 0))
        case .pushRight:
            result = move(to, -W * (1 - p), 0).composited(over: move(from, W * p, 0))
        case .pushUp:
            result = move(to, 0, -H * (1 - p)).composited(over: move(from, 0, H * p))
        case .pushDown:
            result = move(to, 0, H * (1 - p)).composited(over: move(from, 0, -H * p))

        case .slideLeft:
            result = move(to, W * (1 - p), 0).composited(over: from)
        case .slideRight:
            result = move(to, -W * (1 - p), 0).composited(over: from)

        case .wipeLeft:
            result = to.cropped(to: CGRect(x: W * (1 - p), y: 0, width: W * p, height: H)).composited(over: from)
        case .wipeRight:
            result = to.cropped(to: CGRect(x: 0, y: 0, width: W * p, height: H)).composited(over: from)
        case .wipeUp:
            result = to.cropped(to: CGRect(x: 0, y: 0, width: W, height: H * p)).composited(over: from)
        case .wipeDown:
            result = to.cropped(to: CGRect(x: 0, y: H * (1 - p), width: W, height: H * p)).composited(over: from)

        case .zoomIn:
            let f = scaled(from, 1 + 0.4 * p)
            let t = scaled(to, 1.4 - 0.4 * p)
            result = crossfade(f, t, p)

        case .zoomOut:
            let under = scaled(to, 1.3 - 0.3 * p)
            let top = opacity(scaled(from, 1 - 0.4 * p), 1 - p)
            result = top.composited(over: under)

        case .blur:
            let amount = sin(p * .pi) * min(W, H) * 0.03
            func blurred(_ img: CIImage) -> CIImage {
                guard amount > 0.5 else { return img }
                return img.clampedToExtent().applyingGaussianBlur(sigma: Double(amount)).cropped(to: rect)
            }
            result = crossfade(blurred(from), blurred(to), p)

        case .spin:
            let f = rotated(from, angle: -p * 0.5, scale: 1 + 0.5 * p)
            let t = rotated(to, angle: (1 - p) * 0.5, scale: 1 + 0.5 * (1 - p))
            result = crossfade(f.composited(over: blackBG), t.composited(over: blackBG), p)

        case .pixelate:
            let mp = 1 - abs(2 * p - 1) // 0 -> 1 -> 0
            let block = mp * min(W, H) * 0.07
            func pix(_ img: CIImage) -> CIImage {
                guard block > 1.5 else { return img }
                return img.clampedToExtent()
                    .applyingFilter("CIPixellate", parameters: [kCIInputScaleKey: block,
                                                                 kCIInputCenterKey: CIVector(x: 0, y: 0)])
                    .cropped(to: rect)
            }
            result = crossfade(pix(from), pix(to), p)

        case .bars:
            result = ciTransition("CIBarsSwipeTransition",
                                  extra: [kCIInputAngleKey: 0.0, kCIInputWidthKey: W * 0.08, "inputBarOffset": W * 0.03])
                ?? crossfade(from, to, p)

        case .flash:
            result = ciTransition("CIFlashTransition", extra: [kCIInputColorKey: CIColor.white])
                ?? crossfade(from, to, p)

        case .mod:
            result = ciTransition("CIModTransition", extra: [kCIInputRadiusKey: min(W, H) * 0.15])
                ?? crossfade(from, to, p)
        }
        return result.composited(over: blackBG).cropped(to: rect)
    }
}

// =====================================================================
// MARK: - Composition builder
// =====================================================================

final class EditorBuild {
    let composition: AVMutableComposition
    let audioMix: AVMutableAudioMix?
    let layout: TimelineLayout
    let renderSize: CGSize
    let trackIDs: [CMPersistentTrackID]
    let orientations: [CGImagePropertyOrientation]

    init(composition: AVMutableComposition, audioMix: AVMutableAudioMix?, layout: TimelineLayout,
         renderSize: CGSize, trackIDs: [CMPersistentTrackID], orientations: [CGImagePropertyOrientation]) {
        self.composition = composition
        self.audioMix = audioMix
        self.layout = layout
        self.renderSize = renderSize
        self.trackIDs = trackIDs
        self.orientations = orientations
    }

    static func make(clips: [VideoClip], music: AVAsset?, musicVolume: Float) -> EditorBuild? {
        guard !clips.isEmpty else { return nil }

        let comp = AVMutableComposition()
        guard let vA = comp.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid),
              let vB = comp.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid),
              let aA = comp.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid),
              let aB = comp.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid)
        else { return nil }

        let layout = TimelineLayout(clips: clips)
        let videoTracks = [vA, vB]
        let audioTracks = [aA, aB]
        let audioParams = [AVMutableAudioMixInputParameters(track: aA), AVMutableAudioMixInputParameters(track: aB)]
        var orientations: [CGImagePropertyOrientation] = []

        for (i, clip) in clips.enumerated() {
            let slot = i % 2          // клипы чередуются по двум дорожкам — так возможны переходы
            let start = layout.starts[i]
            let dur = layout.durations[i]

            if let src = clip.asset.tracks(withMediaType: .video).first {
                try? videoTracks[slot].insertTimeRange(clip.sourceRange, of: src, at: start)
                if clip.speed != 1 {
                    videoTracks[slot].scaleTimeRange(CMTimeRange(start: start, duration: clip.sourceRange.duration), toDuration: dur)
                }
                orientations.append(imageOrientation(for: src.preferredTransform))
            } else {
                orientations.append(.up)
            }

            if let srcA = clip.asset.tracks(withMediaType: .audio).first {
                try? audioTracks[slot].insertTimeRange(clip.sourceRange, of: srcA, at: start)
                if clip.speed != 1 {
                    audioTracks[slot].scaleTimeRange(CMTimeRange(start: start, duration: clip.sourceRange.duration), toDuration: dur)
                }
                let p = audioParams[slot]
                let ovIn = layout.overlapIn(i), ovOut = layout.overlapOut(i)
                if ovIn > .zero {
                    p.setVolumeRamp(fromStartVolume: 0, toEndVolume: clip.volume, timeRange: CMTimeRange(start: start, duration: ovIn))
                } else {
                    p.setVolume(clip.volume, at: start)
                }
                if ovOut > .zero {
                    p.setVolumeRamp(fromStartVolume: clip.volume, toEndVolume: 0,
                                    timeRange: CMTimeRange(start: start + dur - ovOut, duration: ovOut))
                }
            }
        }

        var params: [AVMutableAudioMixInputParameters] = audioParams

        if let music = music,
           let mSrc = music.tracks(withMediaType: .audio).first,
           let mTrack = comp.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid) {
            let d = CMTimeMinimum(snapMusic(music.duration), layout.total)
            try? mTrack.insertTimeRange(CMTimeRange(start: .zero, duration: d), of: mSrc, at: .zero)
            let mp = AVMutableAudioMixInputParameters(track: mTrack)
            mp.setVolume(musicVolume, at: .zero)
            params.append(mp)
        }

        let mix = AVMutableAudioMix()
        mix.inputParameters = params

        // Размер кадра по первому клипу (с учётом поворота)
        var size = CGSize(width: 1080, height: 1920)
        if let t = clips[0].asset.tracks(withMediaType: .video).first {
            let r = CGRect(origin: .zero, size: t.naturalSize).applying(t.preferredTransform)
            var w = abs(r.width), h = abs(r.height)
            if w > 1 && h > 1 {
                let maxSide: CGFloat = 1920
                if max(w, h) > maxSide {
                    let k = maxSide / max(w, h)
                    w *= k; h *= k
                }
                size = CGSize(width: floor(w / 2) * 2, height: floor(h / 2) * 2)
            }
        }

        return EditorBuild(composition: comp, audioMix: mix, layout: layout, renderSize: size,
                           trackIDs: [vA.trackID, vB.trackID], orientations: orientations)
    }

    private static func snapMusic(_ t: CMTime) -> CMTime { floorTicks(t.secs) }

    /// Инструкции дёшево пересобираются — поэтому смена фильтра/текста не пересобирает всю композицию.
    func makeVideoComposition(clips: [VideoClip], texts: [TextOverlay]) -> AVMutableVideoComposition {
        enum Seg { case solo(Int), trans(Int) }
        var segs: [(CMTime, CMTime, Seg)] = []

        for i in 0..<layout.starts.count {
            let soloStart = layout.starts[i] + layout.overlapIn(i)
            let soloEnd = layout.starts[i] + layout.durations[i] - layout.overlapOut(i)
            if soloEnd > soloStart { segs.append((soloStart, soloEnd, .solo(i))) }
            if i < layout.starts.count - 1, layout.overlapAfter[i] > .zero {
                let ts = layout.starts[i] + layout.durations[i] - layout.overlapAfter[i]
                segs.append((ts, ts + layout.overlapAfter[i], .trans(i)))
            }
        }

        func layer(_ i: Int) -> LayerInfo {
            let c = clips[min(i, clips.count - 1)]
            return LayerInfo(trackID: trackIDs[i % 2], orientation: orientations[i], filter: c.filter, intensity: c.filterIntensity)
        }

        let endTime = max(layout.total, composition.duration)
        var instructions: [AVVideoCompositionInstructionProtocol] = []

        for (idx, seg) in segs.enumerated() {
            var e = seg.1
            if idx == segs.count - 1 { e = max(e, endTime) }
            let range = CMTimeRange(start: seg.0, end: e)
            switch seg.2 {
            case .solo(let i):
                instructions.append(EditorInstruction(timeRange: range, from: layer(i), to: nil, transition: .none, texts: texts))
            case .trans(let i):
                instructions.append(EditorInstruction(timeRange: range, from: layer(i), to: layer(i + 1),
                                                      transition: clips[i].transition, texts: texts))
            }
        }

        let vc = AVMutableVideoComposition()
        vc.customVideoCompositorClass = EditorCompositor.self
        vc.frameDuration = CMTime(value: 1, timescale: 30)
        vc.renderSize = renderSize
        vc.instructions = instructions
        return vc
    }
}

// =====================================================================
// MARK: - Small UI helpers
// =====================================================================

final class PaddingLabel: UILabel {
    var insets = UIEdgeInsets(top: 8, left: 14, bottom: 8, right: 14)
    override func drawText(in rect: CGRect) { super.drawText(in: rect.inset(by: insets)) }
    override var intrinsicContentSize: CGSize {
        let s = super.intrinsicContentSize
        return CGSize(width: s.width + insets.left + insets.right, height: s.height + insets.top + insets.bottom)
    }
}

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
        let labelEvery = pps >= 90 ? 1 : (pps >= 45 ? 2 : 5)
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
        layer.borderWidth = selected ? 2.5 : 0
        layer.borderColor = UIColor.white.cgColor

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
        if clip.filter != .none { info += " ✦" }
        if clip.volume == 0 { info += " 🔇" }
        info += " "
        let label = UILabel()
        label.text = info
        label.font = .systemFont(ofSize: 10, weight: .semibold)
        label.textColor = .white
        label.backgroundColor = UIColor.black.withAlphaComponent(0.5)
        label.layer.cornerRadius = 3
        label.clipsToBounds = true
        label.sizeToFit()
        label.frame.origin = CGPoint(x: 4, y: height - label.frame.height - 4)
        addSubview(label)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
}

final class TimelineView: UIView, UIScrollViewDelegate {

    static let preferredHeight: CGFloat = 128

    private let pps: CGFloat = 64               // точек на секунду
    private let clipTop: CGFloat = 26
    private let clipHeight: CGFloat = 56
    private let textTop: CGFloat = 90
    private let textHeight: CGFloat = 26

    private let scrollView = UIScrollView()
    private let contentView = UIView()
    private let ruler = RulerView()
    private let playhead = UIView()
    private let knob = UIView()
    private let addTile = UIView()

    var onScrubBegan: (() -> Void)?
    var onScrub: ((Double) -> Void)?
    var onSelectClip: ((Int?) -> Void)?
    var onTapTransition: ((Int) -> Void)?
    var onSelectText: ((UUID?) -> Void)?
    var onTapAdd: (() -> Void)?

    private var clips: [VideoClip] = []
    private var layout = TimelineLayout(clips: [])
    private var texts: [TextOverlay] = []
    private var selectedClip: Int?
    private var selectedText: UUID?

    private var clipFrames: [CGRect] = []
    private var transitionFrames: [CGRect] = []
    private var textFrames: [CGRect] = []

    private var isProgrammatic = false
    private var lastPlayheadTime: Double = 0
    private var lastWidth: CGFloat = 0

    private var totalSeconds: Double { layout.total.secs }

    var isUserScrolling: Bool { scrollView.isTracking || scrollView.isDragging || scrollView.isDecelerating }

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

        let tap = UITapGestureRecognizer(target: self, action: #selector(handleTap(_:)))
        contentView.addGestureRecognizer(tap)
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

    // MARK: Public

    func reload(clips: [VideoClip], layout: TimelineLayout, texts: [TextOverlay], selectedClip: Int?, selectedText: UUID?) {
        self.clips = clips
        self.layout = layout
        self.texts = texts
        self.selectedClip = selectedClip
        self.selectedText = selectedText
        rebuildContent()
        setPlayhead(time: lastPlayheadTime, force: true)
    }

    /// Двигаем красную палку (на самом деле прокручиваем ленту под ней).
    func setPlayhead(time: Double, force: Bool = false) {
        lastPlayheadTime = time
        if !force && (scrollView.isTracking || scrollView.isDragging || scrollView.isDecelerating) { return }
        isProgrammatic = true
        scrollView.contentOffset = CGPoint(x: CGFloat(max(0, min(time, totalSeconds))) * pps, y: 0)
        isProgrammatic = false
        ruler.offsetX = scrollView.contentOffset.x
        ruler.setNeedsDisplay()
    }

    // MARK: Build

    private func rebuildContent() {
        guard bounds.width > 0 else { return }
        let side = bounds.width / 2
        let contentW = CGFloat(totalSeconds) * pps + bounds.width
        contentView.subviews.forEach { $0.removeFromSuperview() }
        contentView.frame = CGRect(x: 0, y: 0, width: contentW, height: bounds.height)
        scrollView.contentSize = CGSize(width: contentW, height: bounds.height)
        ruler.pps = pps
        ruler.total = totalSeconds

        clipFrames = []
        transitionFrames = []
        textFrames = []

        for (i, clip) in clips.enumerated() where i < layout.starts.count {
            let x = side + CGFloat(layout.starts[i].secs) * pps + 1
            let w = max(10, CGFloat(layout.durations[i].secs) * pps - 2)
            let tile = ClipTileView(clip: clip, width: w, height: clipHeight, selected: i == selectedClip)
            tile.frame = CGRect(x: x, y: clipTop, width: w, height: clipHeight)
            contentView.addSubview(tile)
            clipFrames.append(tile.frame)
        }

        // Кнопки переходов на стыках
        if clips.count > 1 {
            for j in 0..<(clips.count - 1) {
                let cx = side + CGFloat(layout.starts[j + 1].secs) * pps
                let f = CGRect(x: cx - 13, y: clipTop + clipHeight / 2 - 13, width: 26, height: 26)
                transitionFrames.append(f)
                let has = clips[j].transition != .none
                let v = UIView(frame: f)
                v.backgroundColor = has ? Theme.accent : UIColor(white: 0.95, alpha: 0.95)
                v.layer.cornerRadius = 13
                v.layer.shadowColor = UIColor.black.cgColor
                v.layer.shadowOpacity = 0.4
                v.layer.shadowRadius = 3
                v.layer.shadowOffset = .zero
                let icon = UIImageView(image: UIImage(systemName: has ? clips[j].transition.symbol : "rectangle.on.rectangle"))
                icon.tintColor = .black
                icon.contentMode = .scaleAspectFit
                icon.frame = CGRect(x: 5, y: 5, width: 16, height: 16)
                v.addSubview(icon)
                contentView.addSubview(v)
            }
        }

        // Текстовая дорожка
        for o in texts {
            let x = side + CGFloat(o.start) * pps
            let w = max(36, CGFloat(o.duration) * pps)
            let bar = UILabel(frame: CGRect(x: x, y: textTop, width: w, height: textHeight))
            bar.text = "  " + o.text
            bar.font = .systemFont(ofSize: 11, weight: .semibold)
            bar.textColor = .white
            bar.backgroundColor = Theme.textBar
            bar.layer.cornerRadius = 6
            bar.clipsToBounds = true
            bar.layer.borderWidth = (o.id == selectedText) ? 2 : 0
            bar.layer.borderColor = UIColor.white.cgColor
            contentView.addSubview(bar)
            textFrames.append(bar.frame)
        }

        addTile.frame = CGRect(x: side + CGFloat(totalSeconds) * pps + 10, y: clipTop, width: 56, height: clipHeight)
        contentView.addSubview(addTile)
    }

    // MARK: Taps

    @objc private func handleTap(_ g: UITapGestureRecognizer) {
        let p = g.location(in: contentView)

        if addTile.frame.contains(p) { onTapAdd?(); return }

        for (j, f) in transitionFrames.enumerated() where f.insetBy(dx: -6, dy: -6).contains(p) {
            onTapTransition?(j)
            return
        }
        for (k, f) in textFrames.enumerated().reversed() where f.contains(p) {
            onSelectText?(texts[k].id)
            return
        }
        for (i, f) in clipFrames.enumerated().reversed() where f.contains(p) {
            onSelectClip?(i == selectedClip ? nil : i)
            return
        }
        onSelectClip?(nil)
        onSelectText?(nil)
    }

    // MARK: UIScrollViewDelegate

    func scrollViewWillBeginDragging(_ scrollView: UIScrollView) {
        onScrubBegan?()
    }

    func scrollViewDidScroll(_ sv: UIScrollView) {
        ruler.offsetX = sv.contentOffset.x
        ruler.setNeedsDisplay()
        // Только если крутит человек — иначе получим бесконечный цикл «плеер ↔ лента».
        guard !isProgrammatic, sv.isTracking || sv.isDragging || sv.isDecelerating else { return }
        let t = max(0, min(totalSeconds, Double(sv.contentOffset.x / pps)))
        lastPlayheadTime = t
        onScrub?(t)
    }
}

// =====================================================================
// MARK: - Bottom panel (как в нормальных видеоредакторах)
// =====================================================================

struct PanelItem {
    var title: String
    var symbol: String? = nil
    var badge: String? = nil
    var image: UIImage? = nil
    var swatch: UIColor? = nil
}

struct SliderConfig {
    var title: String
    var min: Float
    var max: Float
    var value: Float
    var format: (Float) -> String
}

final class PanelItemCell: UICollectionViewCell {
    static let reuseId = "PanelItemCell"

    private let box = UIView()
    private let imageView = UIImageView()
    private let iconView = UIImageView()
    private let badgeLabel = UILabel()
    private let swatchView = UIView()
    private let titleLabel = UILabel()

    override init(frame: CGRect) {
        super.init(frame: frame)

        box.backgroundColor = Theme.surface
        box.layer.cornerRadius = 10
        box.clipsToBounds = true
        box.layer.borderColor = Theme.accent.cgColor
        contentView.addSubview(box)

        imageView.contentMode = .scaleAspectFill
        imageView.clipsToBounds = true
        box.addSubview(imageView)

        iconView.tintColor = .white
        iconView.contentMode = .scaleAspectFit
        box.addSubview(iconView)

        badgeLabel.textColor = .white
        badgeLabel.font = .systemFont(ofSize: 15, weight: .bold)
        badgeLabel.textAlignment = .center
        box.addSubview(badgeLabel)

        swatchView.layer.cornerRadius = 14
        swatchView.layer.borderWidth = 1
        swatchView.layer.borderColor = UIColor(white: 1, alpha: 0.4).cgColor
        box.addSubview(swatchView)

        titleLabel.font = .systemFont(ofSize: 10, weight: .medium)
        titleLabel.textColor = .lightGray
        titleLabel.textAlignment = .center
        titleLabel.adjustsFontSizeToFitWidth = true
        titleLabel.minimumScaleFactor = 0.7
        contentView.addSubview(titleLabel)

        box.snp.makeConstraints { make in
            make.top.centerX.equalToSuperview()
            make.size.equalTo(56)
        }
        imageView.snp.makeConstraints { $0.edges.equalToSuperview() }
        iconView.snp.makeConstraints { make in make.center.equalToSuperview(); make.size.equalTo(24) }
        badgeLabel.snp.makeConstraints { $0.edges.equalToSuperview() }
        swatchView.snp.makeConstraints { make in make.center.equalToSuperview(); make.size.equalTo(28) }
        titleLabel.snp.makeConstraints { make in
            make.top.equalTo(box.snp.bottom).offset(5)
            make.leading.trailing.equalToSuperview()
        }
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func configure(_ item: PanelItem, selected: Bool) {
        titleLabel.text = item.title
        imageView.image = item.image
        imageView.isHidden = item.image == nil
        iconView.image = item.symbol.flatMap { UIImage(systemName: $0) }
        iconView.isHidden = item.symbol == nil
        badgeLabel.text = item.badge
        badgeLabel.isHidden = item.badge == nil
        swatchView.backgroundColor = item.swatch
        swatchView.isHidden = item.swatch == nil
        box.layer.borderWidth = selected ? 2.5 : 0
        titleLabel.textColor = selected ? Theme.accent : .lightGray
    }
}

final class EditPanelView: UIView, UICollectionViewDataSource, UICollectionViewDelegate {

    private let titleLabel = UILabel()
    private let closeButton = UIButton(type: .system)
    private let sliderRow = UIView()
    private let sliderCaption = UILabel()
    private let slider = UISlider()
    private let sliderValue = UILabel()
    private var collectionView: UICollectionView!

    private var items: [PanelItem] = []
    private var selectedIndex: Int?
    private var sliderConfig: SliderConfig?

    var onClose: (() -> Void)?
    var onSelect: ((Int) -> Void)?
    var onSliderBegan: (() -> Void)?
    var onSliderChanged: ((Float) -> Void)?
    var onSliderEnded: ((Float) -> Void)?

    var preferredHeight: CGFloat { sliderConfig == nil ? 130 : 166 }

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = Theme.panel

        titleLabel.textColor = .white
        titleLabel.font = .systemFont(ofSize: 13, weight: .semibold)
        closeButton.setImage(UIImage(systemName: "checkmark"), for: .normal)
        closeButton.tintColor = .white
        closeButton.addTarget(self, action: #selector(closeTapped), for: .touchUpInside)

        sliderCaption.textColor = .lightGray
        sliderCaption.font = .systemFont(ofSize: 12)
        sliderValue.textColor = .white
        sliderValue.font = .monospacedDigitSystemFont(ofSize: 12, weight: .medium)
        sliderValue.textAlignment = .right
        slider.minimumTrackTintColor = Theme.accent
        slider.addTarget(self, action: #selector(sliderDown), for: .touchDown)
        slider.addTarget(self, action: #selector(sliderMoved), for: .valueChanged)
        slider.addTarget(self, action: #selector(sliderUp), for: [.touchUpInside, .touchUpOutside, .touchCancel])

        let layout = UICollectionViewFlowLayout()
        layout.scrollDirection = .horizontal
        layout.itemSize = CGSize(width: 64, height: 82)
        layout.minimumLineSpacing = 8
        layout.sectionInset = UIEdgeInsets(top: 4, left: 14, bottom: 0, right: 14)
        collectionView = UICollectionView(frame: .zero, collectionViewLayout: layout)
        collectionView.backgroundColor = .clear
        collectionView.showsHorizontalScrollIndicator = false
        collectionView.dataSource = self
        collectionView.delegate = self
        collectionView.register(PanelItemCell.self, forCellWithReuseIdentifier: PanelItemCell.reuseId)

        let header = UIView()
        header.addSubview(titleLabel)
        header.addSubview(closeButton)
        titleLabel.snp.makeConstraints { make in
            make.leading.equalToSuperview().offset(16)
            make.centerY.equalToSuperview()
        }
        closeButton.snp.makeConstraints { make in
            make.trailing.equalToSuperview().inset(8)
            make.centerY.equalToSuperview()
            make.size.equalTo(40)
        }

        sliderRow.addSubview(sliderCaption)
        sliderRow.addSubview(slider)
        sliderRow.addSubview(sliderValue)
        sliderCaption.snp.makeConstraints { make in
            make.leading.equalToSuperview().offset(16)
            make.centerY.equalToSuperview()
            make.width.equalTo(60)
        }
        sliderValue.snp.makeConstraints { make in
            make.trailing.equalToSuperview().inset(16)
            make.centerY.equalToSuperview()
            make.width.equalTo(52)
        }
        slider.snp.makeConstraints { make in
            make.leading.equalTo(sliderCaption.snp.trailing).offset(4)
            make.trailing.equalTo(sliderValue.snp.leading).offset(-8)
            make.centerY.equalToSuperview()
        }

        let stack = UIStackView(arrangedSubviews: [header, sliderRow, collectionView])
        stack.axis = .vertical
        addSubview(stack)
        stack.snp.makeConstraints { $0.edges.equalToSuperview() }
        header.snp.makeConstraints { $0.height.equalTo(38) }
        sliderRow.snp.makeConstraints { $0.height.equalTo(34) }
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func configure(title: String, items: [PanelItem], selected: Int?, slider cfg: SliderConfig?) {
        titleLabel.text = title
        self.items = items
        self.selectedIndex = selected
        self.sliderConfig = cfg
        sliderRow.isHidden = (cfg == nil)
        if let cfg = cfg {
            sliderCaption.text = cfg.title
            slider.minimumValue = cfg.min
            slider.maximumValue = cfg.max
            slider.value = cfg.value
            sliderValue.text = cfg.format(cfg.value)
        }
        collectionView.reloadData()
        if let s = selected, s < items.count {
            collectionView.scrollToItem(at: IndexPath(item: s, section: 0), at: .centeredHorizontally, animated: false)
        }
    }

    @objc private func closeTapped() { onClose?() }
    @objc private func sliderDown() { onSliderBegan?() }
    @objc private func sliderMoved() {
        sliderValue.text = sliderConfig?.format(slider.value)
        onSliderChanged?(slider.value)
    }
    @objc private func sliderUp() { onSliderEnded?(slider.value) }

    // MARK: Collection

    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int { items.count }

    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(withReuseIdentifier: PanelItemCell.reuseId, for: indexPath) as! PanelItemCell
        cell.configure(items[indexPath.item], selected: indexPath.item == selectedIndex)
        return cell
    }

    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        onSelect?(indexPath.item)
    }
}

// =====================================================================
// MARK: - Main tools bar
// =====================================================================

enum EditorTool: CaseIterable {
    case addVideo, split, delete, duplicate, speed, filter, transition, text, audio

    var title: String {
        switch self {
        case .addVideo: return "Добавить"
        case .split: return "Разрезать"
        case .delete: return "Удалить"
        case .duplicate: return "Дубль"
        case .speed: return "Скорость"
        case .filter: return "Фильтры"
        case .transition: return "Переходы"
        case .text: return "Текст"
        case .audio: return "Музыка"
        }
    }

    var symbol: String {
        switch self {
        case .addVideo: return "plus.square"
        case .split: return "scissors"
        case .delete: return "trash"
        case .duplicate: return "plus.square.on.square"
        case .speed: return "speedometer"
        case .filter: return "camera.filters"
        case .transition: return "rectangle.on.rectangle"
        case .text: return "textformat"
        case .audio: return "music.note"
        }
    }
}

final class ToolCell: UICollectionViewCell {
    static let reuseId = "ToolCell"
    private let iconView = UIImageView()
    private let titleLabel = UILabel()

    override init(frame: CGRect) {
        super.init(frame: frame)
        iconView.tintColor = .white
        iconView.contentMode = .scaleAspectFit
        titleLabel.textColor = .lightGray
        titleLabel.font = .systemFont(ofSize: 10, weight: .medium)
        titleLabel.textAlignment = .center
        let stack = UIStackView(arrangedSubviews: [iconView, titleLabel])
        stack.axis = .vertical
        stack.spacing = 5
        stack.alignment = .center
        contentView.addSubview(stack)
        stack.snp.makeConstraints { $0.center.equalToSuperview() }
        iconView.snp.makeConstraints { $0.size.equalTo(24) }
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func configure(_ tool: EditorTool) {
        iconView.image = UIImage(systemName: tool.symbol)
        titleLabel.text = tool.title
    }
}

// =====================================================================
// MARK: - Export overlay
// =====================================================================

final class ExportOverlay: UIView {
    private let card = UIView()
    private let label = UILabel()
    private let progress = UIProgressView(progressViewStyle: .default)
    private let cancel = UIButton(type: .system)
    var onCancel: (() -> Void)?

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = UIColor.black.withAlphaComponent(0.6)
        card.backgroundColor = UIColor(white: 0.15, alpha: 1)
        card.layer.cornerRadius = 16
        addSubview(card)

        label.text = "Экспорт видео…"
        label.textColor = .white
        label.font = .systemFont(ofSize: 16, weight: .semibold)
        label.textAlignment = .center
        progress.progressTintColor = Theme.accent
        cancel.setTitle("Отмена", for: .normal)
        cancel.addTarget(self, action: #selector(cancelTapped), for: .touchUpInside)

        let stack = UIStackView(arrangedSubviews: [label, progress, cancel])
        stack.axis = .vertical
        stack.spacing = 16
        card.addSubview(stack)

        card.snp.makeConstraints { make in
            make.center.equalToSuperview()
            make.width.equalTo(260)
        }
        stack.snp.makeConstraints { $0.edges.equalToSuperview().inset(20) }
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func setProgress(_ p: Float) {
        progress.progress = p
        label.text = "Экспорт видео… \(Int(p * 100))%"
    }
    @objc private func cancelTapped() { onCancel?() }
}


// =====================================================================
// MARK: - Main ViewController
// =====================================================================

final class ViewController: UIViewController {

    private enum PanelKind { case speed, filter, transition, text, audio }
    private struct Snapshot { var clips: [VideoClip]; var texts: [TextOverlay] }

    // UI
    private let topBar = UIView()
    private let playerContainer = UIView()
    private let controlBar = UIView()
    private let timeLabel = UILabel()
    private let playButton = UIButton(type: .system)
    private let undoButton = UIButton(type: .system)
    private let timelineView = TimelineView()
    private let bottomContainer = UIView()
    private let panel = EditPanelView()
    private let textBox = UIView()
    private let emptyLabel = UILabel()
    private let loader = UIActivityIndicatorView(style: .large)
    private var toolCollection: UICollectionView!
    private var bottomHeightConstraint: NSLayoutConstraint!
    private var playerLayer: AVPlayerLayer!
    private var toastLabel: PaddingLabel?
    private var exportOverlay: ExportOverlay?

    // State
    private var clips: [VideoClip] = []
    private var texts: [TextOverlay] = []
    private var selectedClipIndex: Int?
    private var selectedTextID: UUID?
    private var music: AVAsset?
    private var musicVolume: Float = 0.8
    private var undoStack: [Snapshot] = []

    private var build: EditorBuild?
    private var renderSize = CGSize(width: 1080, height: 1920)
    private var displayTime: Double = 0

    private let player = AVPlayer()
    private var timeObserver: Any?
    private var isSeeking = false
    private var pendingSeek: CMTime?
    private var previewToken = 0

    private var activePanel: PanelKind?
    private var transitionBoundary = 0
    private var filterPreviews: [FilterType: UIImage] = [:]
    private var filterPreviewClipID: UUID?

    private var exportSession: AVAssetExportSession?
    private var exportTimer: Timer?

    private let speeds: [Float] = [0.25, 0.5, 1, 1.5, 2, 3, 4]
    private let toolBarHeight: CGFloat = 76

    private var totalSeconds: Double { build?.layout.total.secs ?? 0 }
    private var selectedText: TextOverlay? { texts.first { $0.id == selectedTextID } }

    // MARK: Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        setupLayout()
        setupPlayer()
        setupCallbacks()
        updateUndoButton()
        updateEmptyState()
        timelineView.reload(clips: [], layout: TimelineLayout(clips: []), texts: [], selectedClip: nil, selectedText: nil)
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        playerLayer.frame = playerContainer.bounds
        CATransaction.commit()
        updateTextBox()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        pausePlayback()
    }

    deinit {
        if let t = timeObserver { player.removeTimeObserver(t) }
        NotificationCenter.default.removeObserver(self)
        exportTimer?.invalidate()
    }

    // MARK: Layout

    private func setupLayout() {
        view.backgroundColor = Theme.background
        [topBar, playerContainer, controlBar, timelineView, bottomContainer].forEach { view.addSubview($0) }

        topBar.snp.makeConstraints { make in
            make.top.equalTo(view.safeAreaLayoutGuide)
            make.leading.trailing.equalToSuperview()
            make.height.equalTo(44)
        }

        let closeButton = UIButton(type: .system)
        closeButton.setImage(UIImage(systemName: "xmark"), for: .normal)
        closeButton.tintColor = .white
        closeButton.addTarget(self, action: #selector(didTapClose), for: .touchUpInside)
        topBar.addSubview(closeButton)
        closeButton.snp.makeConstraints { make in
            make.leading.equalToSuperview().offset(8)
            make.centerY.equalToSuperview()
            make.size.equalTo(44)
        }

        let exportButton = UIButton(type: .system)
        exportButton.setTitle("Экспорт", for: .normal)
        exportButton.titleLabel?.font = .boldSystemFont(ofSize: 14)
        exportButton.setTitleColor(.black, for: .normal)
        exportButton.backgroundColor = .white
        exportButton.layer.cornerRadius = 16
        exportButton.contentEdgeInsets = UIEdgeInsets(top: 7, left: 16, bottom: 7, right: 16)
        exportButton.addTarget(self, action: #selector(didTapExport), for: .touchUpInside)
        topBar.addSubview(exportButton)
        exportButton.snp.makeConstraints { make in
            make.trailing.equalToSuperview().inset(16)
            make.centerY.equalToSuperview()
        }

        undoButton.setImage(UIImage(systemName: "arrow.uturn.backward"), for: .normal)
        undoButton.tintColor = .white
        undoButton.addTarget(self, action: #selector(didTapUndo), for: .touchUpInside)
        topBar.addSubview(undoButton)
        undoButton.snp.makeConstraints { make in
            make.trailing.equalTo(exportButton.snp.leading).offset(-8)
            make.centerY.equalToSuperview()
            make.size.equalTo(44)
        }

        // Player
        playerContainer.backgroundColor = .black
        playerContainer.layer.cornerRadius = 10
        playerContainer.clipsToBounds = true
        playerContainer.snp.makeConstraints { make in
            make.top.equalTo(topBar.snp.bottom).offset(4)
            make.leading.trailing.equalToSuperview().inset(16)
            make.bottom.equalTo(controlBar.snp.top).offset(-2)
        }

        emptyLabel.text = "Нажмите «+» на таймлайне\nили «Добавить», чтобы выбрать видео"
        emptyLabel.numberOfLines = 0
        emptyLabel.textAlignment = .center
        emptyLabel.textColor = .gray
        emptyLabel.font = .systemFont(ofSize: 14)
        playerContainer.addSubview(emptyLabel)
        emptyLabel.snp.makeConstraints { make in
            make.center.equalToSuperview()
            make.leading.trailing.equalToSuperview().inset(20)
        }

        textBox.layer.borderColor = UIColor.white.cgColor
        textBox.layer.borderWidth = 1.5
        textBox.layer.cornerRadius = 4
        textBox.isUserInteractionEnabled = false
        textBox.isHidden = true
        playerContainer.addSubview(textBox)

        loader.color = .white
        loader.hidesWhenStopped = true
        playerContainer.addSubview(loader)
        loader.snp.makeConstraints { $0.center.equalToSuperview() }

        let tap = UITapGestureRecognizer(target: self, action: #selector(handlePlayerTap(_:)))
        playerContainer.addGestureRecognizer(tap)
        let pan = UIPanGestureRecognizer(target: self, action: #selector(handlePlayerPan(_:)))
        pan.delegate = self
        playerContainer.addGestureRecognizer(pan)

        // Control bar
        controlBar.snp.makeConstraints { make in
            make.leading.trailing.equalToSuperview()
            make.height.equalTo(40)
            make.bottom.equalTo(timelineView.snp.top)
        }
        timeLabel.textColor = .lightGray
        timeLabel.font = .monospacedDigitSystemFont(ofSize: 12, weight: .regular)
        timeLabel.text = "00:00.0 / 00:00.0"
        controlBar.addSubview(timeLabel)
        timeLabel.snp.makeConstraints { make in
            make.leading.equalToSuperview().offset(16)
            make.centerY.equalToSuperview()
        }
        playButton.setImage(UIImage(systemName: "play.fill"), for: .normal)
        playButton.tintColor = .white
        playButton.addTarget(self, action: #selector(togglePlay), for: .touchUpInside)
        controlBar.addSubview(playButton)
        playButton.snp.makeConstraints { make in
            make.center.equalToSuperview()
            make.size.equalTo(40)
        }

        // Timeline
        timelineView.snp.makeConstraints { make in
            make.leading.trailing.equalToSuperview()
            make.height.equalTo(TimelineView.preferredHeight)
            make.bottom.equalTo(bottomContainer.snp.top)
        }

        // Bottom: либо панель инструментов, либо панель редактирования
        bottomContainer.backgroundColor = Theme.panel
        bottomContainer.snp.makeConstraints { make in
            make.leading.trailing.equalToSuperview()
            make.bottom.equalTo(view.safeAreaLayoutGuide)
        }
        bottomHeightConstraint = bottomContainer.heightAnchor.constraint(equalToConstant: toolBarHeight)
        bottomHeightConstraint.isActive = true

        let layout = UICollectionViewFlowLayout()
        layout.scrollDirection = .horizontal
        layout.itemSize = CGSize(width: 68, height: 62)
        layout.minimumLineSpacing = 4
        layout.sectionInset = UIEdgeInsets(top: 6, left: 10, bottom: 6, right: 10)
        toolCollection = UICollectionView(frame: .zero, collectionViewLayout: layout)
        toolCollection.backgroundColor = .clear
        toolCollection.showsHorizontalScrollIndicator = false
        toolCollection.dataSource = self
        toolCollection.delegate = self
        toolCollection.register(ToolCell.self, forCellWithReuseIdentifier: ToolCell.reuseId)
        bottomContainer.addSubview(toolCollection)
        toolCollection.snp.makeConstraints { $0.edges.equalToSuperview() }

        panel.isHidden = true
        bottomContainer.addSubview(panel)
        panel.snp.makeConstraints { $0.edges.equalToSuperview() }
    }

    private func setupPlayer() {
        player.actionAtItemEnd = .pause
        playerLayer = AVPlayerLayer(player: player)
        playerLayer.videoGravity = .resizeAspect
        playerContainer.layer.insertSublayer(playerLayer, at: 0)

        timeObserver = player.addPeriodicTimeObserver(forInterval: CMTime(value: 1, timescale: 30), queue: .main) { [weak self] t in
            self?.playerTick(t)
        }
        NotificationCenter.default.addObserver(self, selector: #selector(playerDidFinish),
                                               name: .AVPlayerItemDidPlayToEndTime, object: nil)
    }

    private func setupCallbacks() {
        timelineView.onScrubBegan = { [weak self] in
            self?.previewToken += 1
            self?.pausePlayback()
        }
        timelineView.onScrub = { [weak self] seconds in self?.scrub(to: seconds) }
        timelineView.onSelectClip = { [weak self] index in self?.selectClip(index) }
        timelineView.onSelectText = { [weak self] id in
            if let id = id { self?.selectText(id) } else if self?.selectedTextID != nil { self?.deselectText() }
        }
        timelineView.onTapAdd = { [weak self] in self?.didTapAddVideo() }
        timelineView.onTapTransition = { [weak self] j in
            guard let self = self else { return }
            self.transitionBoundary = j
            self.selectedClipIndex = j
            self.selectedTextID = nil
            self.reloadTimeline()
            self.openPanel(.transition)
        }

        panel.onClose = { [weak self] in self?.closePanel() }
        panel.onSelect = { [weak self] index in self?.handlePanelSelect(index) }
        panel.onSliderBegan = { [weak self] in self?.sliderBegan() }
        panel.onSliderChanged = { [weak self] v in self?.sliderChanged(v) }
        panel.onSliderEnded = { [weak self] v in self?.sliderEnded(v) }

        ThumbnailStore.shared.onUpdate = { [weak self] in self?.reloadTimelineWhenIdle() }
    }

    // MARK: Player ticks / seeking

    private func playerTick(_ t: CMTime) {
        let cur = max(0, min(t.secs, totalSeconds))
        timelineView.setPlayhead(time: cur)
        updateTimeLabel(cur)
        updatePlayButton()
        updateTextBox()
    }

    @objc private func playerDidFinish() {
        updatePlayButton()
    }

    private func scrub(to seconds: Double) {
        previewToken += 1
        let s = max(0, min(seconds, totalSeconds))
        seekTo(ticks(s))
        updateTimeLabel(s)
        updateTextBox()
    }

    /// «Догоняющий» seek: не заваливаем плеер запросами, пока он ещё ищет предыдущий кадр.
    private func seekTo(_ time: CMTime) {
        pendingSeek = time
        guard !isSeeking else { return }
        performSeek()
    }

    private func performSeek() {
        guard let t = pendingSeek else { return }
        pendingSeek = nil
        isSeeking = true
        player.seek(to: t, toleranceBefore: .zero, toleranceAfter: .zero) { [weak self] _ in
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.isSeeking = false
                if self.pendingSeek != nil { self.performSeek() }
            }
        }
    }

    private func updateTimeLabel(_ cur: Double) {
        displayTime = cur
        let total = totalSeconds
        timeLabel.text = String(format: "%02d:%04.1f / %02d:%04.1f",
                                Int(cur) / 60, cur.truncatingRemainder(dividingBy: 60),
                                Int(total) / 60, total.truncatingRemainder(dividingBy: 60))
    }

    private func updatePlayButton() {
        let name = player.rate > 0 ? "pause.fill" : "play.fill"
        playButton.setImage(UIImage(systemName: name), for: .normal)
    }

    private func pausePlayback() {
        player.pause()
        updatePlayButton()
    }

    @objc private func togglePlay() {
        guard build != nil else { return }
        previewToken += 1
        if player.rate > 0 { pausePlayback(); return }
        if displayTime >= totalSeconds - 0.05 {
            player.seek(to: .zero, toleranceBefore: .zero, toleranceAfter: .zero) { [weak self] _ in
                DispatchQueue.main.async { self?.player.play(); self?.updatePlayButton() }
            }
        } else {
            player.play()
            updatePlayButton()
        }
    }

    // MARK: Rebuild engine

    /// Полная пересборка (меняется структура: клипы, скорость, переходы, звук).
    private func rebuild(seekTo target: CMTime? = nil) {
        let oldTime = target ?? ticks(displayTime)
        previewToken += 1
        isSeeking = false
        pendingSeek = nil
        if let s = selectedClipIndex, s >= clips.count { selectedClipIndex = nil }
        clips.forEach { ThumbnailStore.shared.prepare($0.asset) }
        updateEmptyState()

        guard !clips.isEmpty else {
            player.pause()
            player.replaceCurrentItem(with: nil)
            build = nil
            updatePlayButton()
            updateTimeLabel(0)
            reloadTimeline()
            timelineView.setPlayhead(time: 0, force: true)
            updateTextBox()
            return
        }

        guard let b = EditorBuild.make(clips: clips, music: music, musicVolume: musicVolume) else {
            showToast("Не удалось собрать видео")
            return
        }
        build = b
        renderSize = b.renderSize

        let item = AVPlayerItem(asset: b.composition)
        item.videoComposition = b.makeVideoComposition(clips: clips, texts: texts)
        item.audioMix = b.audioMix
        item.audioTimePitchAlgorithm = .spectral
        player.pause()
        player.replaceCurrentItem(with: item)

        let t = CMTimeMinimum(CMTimeMaximum(oldTime, .zero), b.layout.total)
        player.seek(to: t, toleranceBefore: .zero, toleranceAfter: .zero)
        updateTimeLabel(t.secs)
        updatePlayButton()
        reloadTimeline()
        timelineView.setPlayhead(time: t.secs, force: true)
        updateTextBox()
    }

    /// Лёгкое обновление (фильтры, текст): композиция та же, меняем только инструкции.
    private func refreshVideoComposition() {
        guard let b = build, let item = player.currentItem else { return }
        item.videoComposition = b.makeVideoComposition(clips: clips, texts: texts)
        if player.rate == 0 { seekTo(ticks(displayTime)) }
    }

    private func reloadTimeline() {
        timelineView.reload(clips: clips,
                            layout: build?.layout ?? TimelineLayout(clips: []),
                            texts: texts,
                            selectedClip: selectedClipIndex,
                            selectedText: selectedTextID)
    }

    /// Миниатюры догружаются в фоне — не трогаем ленту, пока человек её крутит.
    private func reloadTimelineWhenIdle() {
        if timelineView.isUserScrolling {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in self?.reloadTimelineWhenIdle() }
        } else {
            reloadTimeline()
        }
    }

    private func updateEmptyState() {
        emptyLabel.isHidden = !clips.isEmpty
    }

    // MARK: Undo

    private func pushUndo() {
        undoStack.append(Snapshot(clips: clips, texts: texts))
        if undoStack.count > 50 { undoStack.removeFirst() }
        updateUndoButton()
    }

    private func updateUndoButton() {
        undoButton.alpha = undoStack.isEmpty ? 0.35 : 1
    }

    @objc private func didTapUndo() {
        guard let s = undoStack.popLast() else { showToast("Нечего отменять"); return }
        clips = s.clips
        texts = s.texts
        selectedClipIndex = nil
        selectedTextID = nil
        filterPreviewClipID = nil
        rebuild()
        refreshActivePanel()
        updateUndoButton()
    }

    @objc private func didTapClose() {
        pausePlayback()
        if let nav = navigationController, nav.viewControllers.count > 1 {
            nav.popViewController(animated: true)
        } else {
            dismiss(animated: true)
        }
    }

    // MARK: Selection

    private func currentClipIndex() -> Int? {
        if let i = selectedClipIndex, i < clips.count { return i }
        return build?.layout.index(at: ticks(displayTime))
    }

    private func selectClip(_ index: Int?) {
        selectedClipIndex = index
        if index != nil { selectedTextID = nil }
        if let i = index, clips.count > 1 { transitionBoundary = min(i, clips.count - 2) }
        reloadTimeline()
        updateTextBox()
        refreshActivePanel()
    }

    private func selectText(_ id: UUID) {
        guard let o = texts.first(where: { $0.id == id }) else { return }
        selectedTextID = id
        selectedClipIndex = nil
        if displayTime < o.start || displayTime >= o.start + o.duration {
            let s = min(o.start + 0.01, totalSeconds)
            seekTo(ticks(s))
            updateTimeLabel(s)
            timelineView.setPlayhead(time: s, force: true)
        }
        reloadTimeline()
        updateTextBox()
        refreshActivePanel()
    }

    private func deselectText() {
        selectedTextID = nil
        reloadTimeline()
        updateTextBox()
        refreshActivePanel()
    }

    private func ensureSelection() {
        if selectedClipIndex == nil, selectedTextID == nil, let i = currentClipIndex() {
            selectedClipIndex = i
            if clips.count > 1 { transitionBoundary = min(i, clips.count - 2) }
            reloadTimeline()
        }
    }

    // MARK: Tools

    private func handleTool(_ tool: EditorTool) {
        switch tool {
        case .addVideo: didTapAddVideo()
        case .split: splitAtPlayhead()
        case .delete: deleteCurrent()
        case .duplicate: duplicateCurrent()
        case .speed: openClipPanel(.speed)
        case .filter: openClipPanel(.filter)
        case .transition: openTransitionPanel()
        case .text:
            guard !clips.isEmpty else { showToast("Сначала добавьте видео"); return }
            openPanel(.text)
            if texts.isEmpty { promptText(editing: nil) }
        case .audio:
            guard !clips.isEmpty else { showToast("Сначала добавьте видео"); return }
            openPanel(.audio)
        }
    }

    private func openClipPanel(_ kind: PanelKind) {
        guard !clips.isEmpty else { showToast("Сначала добавьте видео"); return }
        ensureSelection()
        openPanel(kind)
    }

    private func openTransitionPanel() {
        guard clips.count >= 2, let b = build else {
            showToast("Для перехода нужно минимум 2 клипа — разрежьте видео или добавьте ещё")
            return
        }
        // Выбираем ближайший к красной палке стык
        var bestJ = 0
        var bestDist = Double.infinity
        for j in 0..<(clips.count - 1) {
            let d = abs(displayTime - b.layout.starts[j + 1].secs)
            if d < bestDist { bestDist = d; bestJ = j }
        }
        if let s = selectedClipIndex { bestJ = min(s, clips.count - 2) }
        transitionBoundary = bestJ
        selectedClipIndex = bestJ
        selectedTextID = nil
        reloadTimeline()
        openPanel(.transition)
    }

    // MARK: Split / delete / duplicate

    private func splitAtPlayhead() {
        guard let b = build, !clips.isEmpty else { showToast("Сначала добавьте видео"); return }
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
        first.transition = .none

        var second = clip   // у второй половины свой id → свои независимые фильтр/переход/скорость
        second.id = UUID()
        second.sourceRange = CMTimeRange(start: clip.sourceRange.start + srcOffset,
                                         duration: clip.sourceRange.duration - srcOffset)

        clips[i] = first
        clips.insert(second, at: i + 1)
        selectedClipIndex = nil
        selectedTextID = nil
        rebuild(seekTo: ticks(t))
        refreshActivePanel()
    }

    private func deleteCurrent() {
        if let id = selectedTextID, selectedClipIndex == nil {
            pushUndo()
            texts.removeAll { $0.id == id }
            selectedTextID = nil
            textsChanged()
            return
        }
        guard let i = currentClipIndex() else { showToast("Нечего удалять"); return }
        pushUndo()
        clips.remove(at: i)
        selectedClipIndex = nil
        filterPreviewClipID = nil
        rebuild()
        refreshActivePanel()
    }

    private func duplicateCurrent() {
        guard let i = currentClipIndex() else { showToast("Сначала добавьте видео"); return }
        pushUndo()
        var copy = clips[i]
        copy.id = UUID()
        copy.transition = .none
        clips.insert(copy, at: i + 1)
        selectedClipIndex = i + 1
        rebuild()
    }

    // MARK: Bottom panel

    private func openPanel(_ kind: PanelKind) {
        activePanel = kind
        if kind == .filter { updateFilterPreviews() }
        toolCollection.isHidden = true
        panel.isHidden = false
        refreshActivePanel()
    }

    private func closePanel() {
        activePanel = nil
        panel.isHidden = true
        toolCollection.isHidden = false
        setBottomHeight(toolBarHeight)
    }

    private func setBottomHeight(_ h: CGFloat) {
        guard bottomHeightConstraint.constant != h else { return }
        bottomHeightConstraint.constant = h
        UIView.animate(withDuration: 0.25) { self.view.layoutIfNeeded() }
    }

    private func refreshActivePanel() {
        guard let kind = activePanel else { return }

        switch kind {
        case .speed:
            guard let i = currentClipIndex() else { closePanel(); return }
            let items = speeds.map { PanelItem(title: $0 == 1 ? "Обычная" : "\($0)x", badge: String(format: "%gx", Double($0))) }
            let sel = speeds.firstIndex { abs($0 - clips[i].speed) < 0.01 }
            panel.configure(title: "Скорость · клип \(i + 1)", items: items, selected: sel, slider: nil)

        case .filter:
            guard let i = currentClipIndex() else { closePanel(); return }
            let items = FilterType.allCases.map { PanelItem(title: $0.displayName, symbol: filterPreviews[$0] == nil ? "camera.filters" : nil, image: filterPreviews[$0]) }
            let sel = FilterType.allCases.firstIndex(of: clips[i].filter)
            let cfg = SliderConfig(title: "Сила", min: 0, max: 1, value: clips[i].filterIntensity) { "\(Int($0 * 100))%" }
            panel.configure(title: "Фильтр · клип \(i + 1)", items: items, selected: sel, slider: clips[i].filter == .none ? nil : cfg)

        case .transition:
            guard clips.count >= 2 else { closePanel(); return }
            let j = min(transitionBoundary, clips.count - 2)
            transitionBoundary = j
            let items = TransitionType.allCases.map { PanelItem(title: $0.title, symbol: $0.symbol) }
            let sel = TransitionType.allCases.firstIndex(of: clips[j].transition)
            let cfg = SliderConfig(title: "Длительность", min: 0.2, max: 1.5, value: Float(clips[j].transitionDuration)) {
                String(format: "%.1fс", Double($0))
            }
            panel.configure(title: "Переход · клип \(j + 1) → \(j + 2)", items: items, selected: sel,
                            slider: clips[j].transition == .none ? nil : cfg)

        case .text:
            var items = [
                PanelItem(title: "Добавить", symbol: "plus"),
                PanelItem(title: "Изменить", symbol: "pencil"),
                PanelItem(title: "Удалить", symbol: "trash"),
                PanelItem(title: "−1 сек", symbol: "minus"),
                PanelItem(title: "+1 сек", symbol: "plus.circle")
            ]
            items += TextStyle.colors.map { PanelItem(title: "Цвет", swatch: $0) }
            var sel: Int?
            var cfg: SliderConfig?
            if let t = selectedText {
                sel = 5 + t.colorIndex
                cfg = SliderConfig(title: "Размер", min: 0.03, max: 0.12, value: Float(t.size)) {
                    "\(Int(($0 - 0.03) / 0.09 * 100))%"
                }
            }
            panel.configure(title: selectedText == nil ? "Текст · выберите текст на дорожке" : "Текст", items: items, selected: sel, slider: cfg)

        case .audio:
            let muted = (currentClipIndex().map { clips[$0].volume == 0 }) ?? false
            let items = [
                PanelItem(title: "Добавить музыку", symbol: "music.note"),
                PanelItem(title: "Убрать музыку", symbol: "trash"),
                PanelItem(title: muted ? "Включить звук" : "Выкл. звук клипа", symbol: muted ? "speaker.wave.2.fill" : "speaker.slash.fill")
            ]
            let cfg = SliderConfig(title: "Музыка", min: 0, max: 1, value: musicVolume) { "\(Int($0 * 100))%" }
            panel.configure(title: "Звук", items: items, selected: nil, slider: music == nil ? nil : cfg)
        }
        setBottomHeight(panel.preferredHeight)
    }

    private func handlePanelSelect(_ index: Int) {
        guard let kind = activePanel else { return }
        switch kind {
        case .speed:
            guard let i = currentClipIndex(), index < speeds.count else { return }
            pushUndo()
            clips[i].speed = speeds[index]
            rebuild()
            refreshActivePanel()

        case .filter:
            guard let i = currentClipIndex() else { return }
            pushUndo()
            clips[i].filter = FilterType.allCases[index]
            refreshVideoComposition()   // только этот клип — у остальных фильтры не трогаем
            reloadTimeline()
            refreshActivePanel()

        case .transition:
            guard clips.count >= 2 else { return }
            let j = min(transitionBoundary, clips.count - 2)
            pushUndo()
            clips[j].transition = TransitionType.allCases[index]
            rebuild()
            refreshActivePanel()
            previewTransition(j)

        case .text:
            handleTextPanel(index)

        case .audio:
            handleAudioPanel(index)
        }
    }

    private func updateFilterPreviews() {
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
            var result: [FilterType: UIImage] = [:]
            for f in FilterType.allCases {
                let out = f.apply(to: base)
                if let o = EditorCompositor.ciContext.createCGImage(out, from: base.extent) {
                    result[f] = UIImage(cgImage: o)
                }
            }
            DispatchQueue.main.async {
                self?.filterPreviews = result
                if self?.activePanel == .filter { self?.refreshActivePanel() }
            }
        }
    }

    // Slider callbacks
    private func sliderBegan() {
        switch activePanel {
        case .filter?, .text?, .transition?: pushUndo()
        default: break
        }
    }

    private func sliderChanged(_ v: Float) {
        switch activePanel {
        case .filter?:
            guard let i = currentClipIndex() else { return }
            clips[i].filterIntensity = v
            refreshVideoComposition()
        case .transition?:
            let j = min(transitionBoundary, max(0, clips.count - 2))
            guard clips.count >= 2 else { return }
            clips[j].transitionDuration = Double(v)
        case .text?:
            guard let id = selectedTextID, let idx = texts.firstIndex(where: { $0.id == id }) else { return }
            texts[idx].size = CGFloat(v)
            refreshVideoComposition()
            updateTextBox()
        case .audio?:
            musicVolume = v
        default: break
        }
    }

    private func sliderEnded(_ v: Float) {
        switch activePanel {
        case .transition?:
            guard clips.count >= 2 else { return }
            let j = min(transitionBoundary, clips.count - 2)
            rebuild()
            previewTransition(j)
        case .audio?:
            rebuild()
        default:
            reloadTimeline()
        }
    }

    /// Показываем переход: перематываем чуть назад и проигрываем.
    private func previewTransition(_ j: Int) {
        guard let b = build, j + 1 < b.layout.starts.count else { return }
        let ov = b.layout.overlapAfter[j].secs
        let tStart = b.layout.starts[j + 1].secs
        guard ov > 0 else {
            seekTo(ticks(tStart))
            updateTimeLabel(tStart)
            timelineView.setPlayhead(time: tStart, force: true)
            return
        }
        let from = max(0, tStart - 0.8)
        let until = tStart + ov + 0.6
        previewToken += 1
        let token = previewToken
        player.seek(to: ticks(from), toleranceBefore: .zero, toleranceAfter: .zero) { [weak self] _ in
            DispatchQueue.main.async {
                guard let self = self, token == self.previewToken else { return }
                self.player.play()
                self.updatePlayButton()
                DispatchQueue.main.asyncAfter(deadline: .now() + (until - from)) { [weak self] in
                    guard let self = self, token == self.previewToken else { return }
                    self.pausePlayback()
                }
            }
        }
    }

    // MARK: Text

    private func handleTextPanel(_ index: Int) {
        switch index {
        case 0:
            promptText(editing: nil)
        case 1:
            guard let t = selectedText else { showToast("Выберите текст на дорожке под клипами"); return }
            promptText(editing: t)
        case 2:
            guard let id = selectedTextID else { showToast("Выберите текст на дорожке под клипами"); return }
            pushUndo()
            texts.removeAll { $0.id == id }
            selectedTextID = nil
            textsChanged()
        case 3, 4:
            guard let id = selectedTextID, let idx = texts.firstIndex(where: { $0.id == id }) else {
                showToast("Выберите текст на дорожке под клипами"); return
            }
            pushUndo()
            let delta: Double = index == 3 ? -1 : 1
            texts[idx].duration = max(0.5, texts[idx].duration + delta)
            textsChanged()
        default:
            guard let id = selectedTextID, let idx = texts.firstIndex(where: { $0.id == id }) else {
                showToast("Сначала выберите текст"); return
            }
            pushUndo()
            texts[idx].colorIndex = index - 5
            textsChanged()
        }
    }

    private func promptText(editing: TextOverlay?) {
        let alert = UIAlertController(title: editing == nil ? "Новый текст" : "Изменить текст", message: nil, preferredStyle: .alert)
        alert.addTextField { tf in
            tf.text = editing?.text
            tf.placeholder = "Введите текст"
            tf.autocapitalizationType = .sentences
        }
        alert.addAction(UIAlertAction(title: "Отмена", style: .cancel))
        alert.addAction(UIAlertAction(title: "Готово", style: .default) { [weak self, weak alert] _ in
            let text = alert?.textFields?.first?.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard !text.isEmpty else { return }
            self?.commitText(text, editing: editing)
        })
        present(alert, animated: true)
    }

    private func commitText(_ text: String, editing: TextOverlay?) {
        pushUndo()
        if let e = editing, let idx = texts.firstIndex(where: { $0.id == e.id }) {
            texts[idx].text = text
        } else {
            let total = totalSeconds
            let start = min(displayTime, max(0, total - 0.5))
            let dur = max(0.5, min(3, total - start))
            let o = TextOverlay(text: text, start: start, duration: dur)
            texts.append(o)
            selectedTextID = o.id
            selectedClipIndex = nil
        }
        textsChanged()
    }

    private func textsChanged() {
        refreshVideoComposition()
        reloadTimeline()
        updateTextBox()
        refreshActivePanel()
    }

    private func isVisible(_ o: TextOverlay, at t: Double) -> Bool {
        t >= o.start && t < o.start + o.duration
    }

    private func videoRectInPlayer() -> CGRect {
        let c = playerContainer.bounds
        guard renderSize.width > 0, c.width > 0, c.height > 0 else { return c }
        let s = min(c.width / renderSize.width, c.height / renderSize.height)
        let w = renderSize.width * s, h = renderSize.height * s
        return CGRect(x: (c.width - w) / 2, y: (c.height - h) / 2, width: w, height: h)
    }

    private func textFrame(_ o: TextOverlay) -> CGRect {
        let vr = videoRectInPlayer()
        let px = TextRenderer.pixelSize(for: o, canvas: renderSize)
        let k = vr.height / max(1, renderSize.height)
        let w = px.width * k, h = px.height * k
        return CGRect(x: vr.minX + o.position.x * vr.width - w / 2,
                      y: vr.minY + o.position.y * vr.height - h / 2,
                      width: w, height: h)
    }

    private func updateTextBox() {
        guard build != nil, let o = selectedText, isVisible(o, at: displayTime) else {
            textBox.isHidden = true
            return
        }
        textBox.frame = textFrame(o)
        textBox.isHidden = false
        playerContainer.bringSubviewToFront(textBox)
    }

    @objc private func handlePlayerTap(_ g: UITapGestureRecognizer) {
        let p = g.location(in: playerContainer)
        for o in texts.reversed() where isVisible(o, at: displayTime) {
            if textFrame(o).insetBy(dx: -10, dy: -10).contains(p) {
                selectText(o.id)
                return
            }
        }
        if selectedTextID != nil { deselectText(); return }
        togglePlay()
    }

    @objc private func handlePlayerPan(_ g: UIPanGestureRecognizer) {
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

    // MARK: Audio

    private func handleAudioPanel(_ index: Int) {
        switch index {
        case 0:
            let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.audio], asCopy: true)
            picker.delegate = self
            present(picker, animated: true)
        case 1:
            guard music != nil else { showToast("Музыка не добавлена"); return }
            music = nil
            rebuild()
            refreshActivePanel()
        default:
            guard let i = currentClipIndex() else { return }
            pushUndo()
            clips[i].volume = clips[i].volume > 0 ? 0 : 1
            rebuild()
            refreshActivePanel()
        }
    }

    // MARK: Add video

    private func didTapAddVideo() {
        var config = PHPickerConfiguration()
        config.filter = .videos
        config.selectionLimit = 0   // можно выбрать сразу несколько
        let picker = PHPickerViewController(configuration: config)
        picker.delegate = self
        present(picker, animated: true)
    }

    private final class ClipCollector {
        private let lock = NSLock()
        private var items: [Int: VideoClip] = [:]
        func set(_ i: Int, _ c: VideoClip) { lock.lock(); items[i] = c; lock.unlock() }
        func ordered() -> [VideoClip] { lock.lock(); defer { lock.unlock() }; return items.keys.sorted().compactMap { items[$0] } }
    }

    fileprivate func importVideos(_ results: [PHPickerResult]) {
        guard !results.isEmpty else { return }
        loader.startAnimating()
        let group = DispatchGroup()
        let collector = ClipCollector()

        for (idx, r) in results.enumerated() {
            group.enter()
            r.itemProvider.loadFileRepresentation(forTypeIdentifier: UTType.movie.identifier) { url, error in
                defer { group.leave() }
                guard let url = url, error == nil else { return }
                let ext = url.pathExtension.isEmpty ? "mov" : url.pathExtension
                let dest = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).\(ext)")
                do { try FileManager.default.copyItem(at: url, to: dest) } catch { return }
                let asset = AVAsset(url: dest)
                let dur = floorTicks(asset.duration.secs)
                guard dur.secs > 0.1, asset.tracks(withMediaType: .video).first != nil else { return }
                collector.set(idx, VideoClip(asset: asset, sourceRange: CMTimeRange(start: .zero, duration: dur)))
            }
        }

        group.notify(queue: .main) { [weak self] in
            guard let self = self else { return }
            self.loader.stopAnimating()
            let newClips = collector.ordered()
            guard !newClips.isEmpty else { self.showToast("Не удалось загрузить видео"); return }
            self.pushUndo()
            let resumeTime = self.clips.isEmpty ? CMTime.zero : ticks(self.displayTime)
            self.clips.append(contentsOf: newClips)
            self.rebuild(seekTo: resumeTime)
        }
    }

    // MARK: Export

    @objc private func didTapExport() {
        guard let b = build, !clips.isEmpty else { showToast("Нечего экспортировать"); return }
        pausePlayback()

        let vc = b.makeVideoComposition(clips: clips, texts: texts)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("edit_\(UUID().uuidString).mp4")
        try? FileManager.default.removeItem(at: url)

        guard let session = AVAssetExportSession(asset: b.composition, presetName: AVAssetExportPresetHighestQuality) else {
            showToast("Экспорт недоступен")
            return
        }
        session.outputURL = url
        session.outputFileType = .mp4
        session.videoComposition = vc
        session.audioMix = b.audioMix
        session.audioTimePitchAlgorithm = .spectral
        session.shouldOptimizeForNetworkUse = true
        exportSession = session

        let overlay = ExportOverlay()
        overlay.frame = view.bounds
        overlay.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        overlay.onCancel = { [weak self] in self?.exportSession?.cancelExport() }
        view.addSubview(overlay)
        exportOverlay = overlay

        exportTimer = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { [weak self] _ in
            guard let s = self?.exportSession else { return }
            self?.exportOverlay?.setProgress(s.progress)
        }

        session.exportAsynchronously { [weak self] in
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.exportTimer?.invalidate()
                self.exportOverlay?.removeFromSuperview()
                self.exportOverlay = nil
                switch session.status {
                case .completed:
                    self.saveToPhotos(url: url)
                case .cancelled:
                    self.showToast("Экспорт отменён")
                default:
                    self.showResultAlert(title: "Ошибка", message: session.error?.localizedDescription ?? "Ошибка экспорта")
                }
                self.exportSession = nil
            }
        }
    }

    private func saveToPhotos(url: URL) {
        PHPhotoLibrary.requestAuthorization(for: .addOnly) { [weak self] status in
            guard status == .authorized || status == .limited else {
                DispatchQueue.main.async {
                    self?.showResultAlert(title: "Нет доступа", message: "Разрешите добавление в Фото в настройках.")
                }
                return
            }
            PHPhotoLibrary.shared().performChanges({
                PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: url)
            }) { success, error in
                DispatchQueue.main.async {
                    if success {
                        self?.showResultAlert(title: "Готово 🎉", message: "Видео сохранено в Галерею.")
                    } else {
                        self?.showResultAlert(title: "Ошибка", message: error?.localizedDescription ?? "Не удалось сохранить")
                    }
                }
            }
        }
    }

    private func showResultAlert(title: String, message: String) {
        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        present(alert, animated: true)
    }

    // MARK: Toast

    private func showToast(_ text: String) {
        toastLabel?.removeFromSuperview()
        let l = PaddingLabel()
        l.text = text
        l.numberOfLines = 0
        l.textAlignment = .center
        l.textColor = .white
        l.font = .systemFont(ofSize: 13, weight: .medium)
        l.backgroundColor = UIColor(white: 0.2, alpha: 0.95)
        l.layer.cornerRadius = 14
        l.clipsToBounds = true
        view.addSubview(l)
        l.snp.makeConstraints { make in
            make.centerX.equalToSuperview()
            make.bottom.equalTo(timelineView.snp.top).offset(-8)
            make.leading.greaterThanOrEqualToSuperview().offset(24)
            make.trailing.lessThanOrEqualToSuperview().offset(-24)
        }
        toastLabel = l
        l.alpha = 0
        UIView.animate(withDuration: 0.2, animations: { l.alpha = 1 }) { _ in
            UIView.animate(withDuration: 0.3, delay: 2.0, options: [], animations: { l.alpha = 0 }) { _ in
                l.removeFromSuperview()
            }
        }
    }
}

// =====================================================================
// MARK: - Delegates
// =====================================================================

extension ViewController: UICollectionViewDataSource, UICollectionViewDelegate {
    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        EditorTool.allCases.count
    }

    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        guard let cell = collectionView.dequeueReusableCell(withReuseIdentifier: ToolCell.reuseId, for: indexPath) as? ToolCell else {
            return UICollectionViewCell()
        }
        cell.configure(EditorTool.allCases[indexPath.item])
        return cell
    }

    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        collectionView.deselectItem(at: indexPath, animated: false)
        handleTool(EditorTool.allCases[indexPath.item])
    }
}

extension ViewController: UIGestureRecognizerDelegate {
    func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        if gestureRecognizer is UIPanGestureRecognizer { return selectedText != nil }
        return true
    }
}

extension ViewController: PHPickerViewControllerDelegate, UIDocumentPickerDelegate {
    func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
        picker.dismiss(animated: true)
        importVideos(results)
    }

    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        guard let url = urls.first else { return }
        let local = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).\(url.pathExtension)")
        try? FileManager.default.copyItem(at: url, to: local)
        music = AVAsset(url: local)
        rebuild()
        refreshActivePanel()
    }
}
