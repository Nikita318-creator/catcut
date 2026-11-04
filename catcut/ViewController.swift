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
    static let audio = UIColor(red: 0.10, green: 0.50, blue: 0.46, alpha: 1)
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
// MARK: - Models
// =====================================================================

struct VideoClip {
    var id = UUID()
    let asset: AVAsset
    /// Имя файла в постоянном хранилище (нужно для черновиков).
    var file: String = ""
    /// Какой кусок исходника используем (в шкале 600).
    var sourceRange: CMTimeRange
    var speed: Float = 1.0
    var filter: FilterType = .none
    var filterIntensity: Float = 1.0
    /// Переход ПОСЛЕ этого клипа (между ним и следующим). 0 = нет.
    var transitionID: Int = 0
    var transitionDuration: Double = 0.6
    var volume: Float = 1.0

    /// Длительность клипа на таймлайне (с учётом скорости).
    var displayDuration: CMTime {
        ticks(sourceRange.duration.secs / Double(speed))
    }
}

/// Аудио-дорожка: живёт на таймлайне независимо от видео, но только в пределах видео.
struct AudioClip {
    var id = UUID()
    let asset: AVAsset
    var file: String
    var title: String
    /// Где начинается на общем таймлайне (сек).
    var start: Double
    /// С какого места исходного аудио играем (сек).
    var sourceOffset: Double = 0
    /// Сколько играем (сек).
    var duration: Double
    var volume: Float = 1.0
    /// Полная длина исходного файла.
    let sourceDuration: Double
}

struct TextOverlay: Codable {
    var id = UUID()
    var text: String
    var start: Double
    var duration: Double
    /// Центр текста, 0...1 (y считается сверху).
    var position = CGPoint(x: 0.5, y: 0.5)
    /// Размер шрифта как доля высоты кадра.
    var size: CGFloat = 0.05
    /// Поворот по часовой стрелке (радианы).
    var rotation: CGFloat = 0

    var fillIndex: Int = 0
    var strokeIndex: Int = -1
    var strokeWidth: CGFloat = 0.08
    var shadow: Int = 1
    var shadowColorIndex: Int = 5
    var glowIndex: Int = -1
    var boxIndex: Int = -1
    var boxOpacity: Double = 0.9
    var fontIndex: Int = 0
    var weight: Int = 6
    var italic = false
    var underline = false
    var strike = false
    /// 0 — слева, 1 — по центру, 2 — справа
    var alignment: Int = 1
    var letterSpacing: CGFloat = 0
    var animIn: Int = 0
    var animOut: Int = 0
    var animDuration: Double = 0.5
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
            if i < clips.count - 1, clips[i].transitionID != 0 {
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
// MARK: - Transition catalog (3500+ переходов из «конструктора»)
// =====================================================================
//
// Переход = БАЗА (сдвиг, шторка, ирис, жалюзи, шум, 3D…) + ЭФФЕКТ (размытие, RGB, вспышка…)
// + КРИВАЯ СКОРОСТИ (плавно / линейно / резко / пружина).
// Комбинации и дают тысячи вариантов. ID перехода = номер в каталоге (0 = нет перехода).

enum TransitionCategory: Int, CaseIterable {
    case all, fade, push, cover, wipe, shape, blinds, noise, zoom, flip3d, distort, pixel, glitch, light

    var title: String {
        switch self {
        case .all: return "Все"
        case .fade: return "Затемнение"
        case .push: return "Сдвиг"
        case .cover: return "Наезд"
        case .wipe: return "Шторки"
        case .shape: return "Фигуры"
        case .blinds: return "Жалюзи"
        case .noise: return "Шум"
        case .zoom: return "Зум и вращение"
        case .flip3d: return "3D"
        case .distort: return "Искажения"
        case .pixel: return "Пиксели"
        case .glitch: return "Глитч"
        case .light: return "Свет"
        }
    }

    var symbol: String {
        switch self {
        case .all: return "square.grid.2x2"
        case .fade: return "drop.halffull"
        case .push: return "arrow.left.and.right"
        case .cover: return "chevron.left.2"
        case .wipe: return "forward.end.fill"
        case .shape: return "circle.dashed"
        case .blinds: return "list.bullet"
        case .noise: return "sparkles"
        case .zoom: return "arrow.triangle.2.circlepath"
        case .flip3d: return "cube"
        case .distort: return "tornado"
        case .pixel: return "square.grid.3x3.fill"
        case .glitch: return "bolt.horizontal.fill"
        case .light: return "sun.max.fill"
        }
    }
}

enum Dir: CaseIterable {
    case left, right, up, down, upLeft, upRight, downLeft, downRight

    /// Куда едет картинка (система координат CoreImage: y вверх).
    var vector: CGPoint {
        switch self {
        case .left: return CGPoint(x: -1, y: 0)
        case .right: return CGPoint(x: 1, y: 0)
        case .up: return CGPoint(x: 0, y: 1)
        case .down: return CGPoint(x: 0, y: -1)
        case .upLeft: return CGPoint(x: -1, y: 1)
        case .upRight: return CGPoint(x: 1, y: 1)
        case .downLeft: return CGPoint(x: -1, y: -1)
        case .downRight: return CGPoint(x: 1, y: -1)
        }
    }

    var arrow: String {
        switch self {
        case .left: return "←"
        case .right: return "→"
        case .up: return "↑"
        case .down: return "↓"
        case .upLeft: return "↖"
        case .upRight: return "↗"
        case .downLeft: return "↙"
        case .downRight: return "↘"
        }
    }
}

enum Ease: CaseIterable {
    case smooth, linear, snap, back

    var title: String {
        switch self {
        case .smooth: return "плавно"
        case .linear: return "линейно"
        case .snap: return "резко"
        case .back: return "пружина"
        }
    }

    func apply(_ t: CGFloat) -> CGFloat {
        let x = max(0, min(1, t))
        switch self {
        case .linear: return x
        case .smooth: return x * x * (3 - 2 * x)
        case .snap: return (1 - pow(2, -10 * x)) / (1 - pow(2, -10))
        case .back:
            let c1: CGFloat = 1.70158
            let c3 = c1 + 1
            return 1 + c3 * pow(x - 1, 3) + c1 * pow(x - 1, 2)
        }
    }
}

/// Дополнительный эффект «поверх» базового перехода (пульсирует в середине).
enum Fx: CaseIterable {
    case none, blur, zoomPulse, rgb, shake, flash, goldFlash, hue, saturate, tilt, zoomBlur

    var suffix: String {
        switch self {
        case .none: return ""
        case .blur: return " + размытие"
        case .zoomPulse: return " + пульс"
        case .rgb: return " + RGB"
        case .shake: return " + тряска"
        case .flash: return " + вспышка"
        case .goldFlash: return " + золото"
        case .hue: return " + цвета"
        case .saturate: return " + сочность"
        case .tilt: return " + наклон"
        case .zoomBlur: return " + рывок"
        }
    }
}

enum MosaicKind { case pixel, hex, crystal }

enum Base {
    case dissolve
    case dip(CIColor)
    case push(Dir)
    case cover(Dir)
    case reveal(Dir)
    case wipe(angle: CGFloat, soft: CGFloat)
    case iris(inward: Bool, scaleX: CGFloat, soft: CGFloat, cx: CGFloat, cy: CGFloat)
    case blinds(count: Int, angle: CGFloat, soft: CGFloat)
    case grid(cells: Int, diagonal: Bool, sweep: Int)
    case noise(grain: CGFloat, cloud: Bool, soft: CGFloat)
    case slices(count: Int, vertical: Bool)
    case doors(vertical: Bool, open: Bool)
    case zoom(inward: Bool, strength: CGFloat)
    case spin(cw: Bool, angle: CGFloat)
    case flip(vertical: Bool)
    case cube(left: Bool)
    case twirl(cw: Bool, strength: CGFloat)
    case bump(sign: CGFloat)
    case pinch(sign: CGFloat)
    case mosaic(MosaicKind, strength: CGFloat)
}

struct TransitionSpec {
    let id: Int
    let name: String
    let category: TransitionCategory
    let base: Base
    let fx: Fx
    let ease: Ease
}

enum TransitionCatalog {

    static let all: [TransitionSpec] = build()

    private static let byCategory: [TransitionCategory: [TransitionSpec]] = {
        var d: [TransitionCategory: [TransitionSpec]] = [.all: all]
        for c in TransitionCategory.allCases where c != .all { d[c] = all.filter { $0.category == c } }
        return d
    }()

    static func spec(_ id: Int) -> TransitionSpec? {
        guard id > 0, id <= all.count else { return nil }
        return all[id - 1]
    }

    static func list(_ category: TransitionCategory) -> [TransitionSpec] {
        byCategory[category] ?? all
    }

    private static func build() -> [TransitionSpec] {
        typealias Entry = (String, Base, TransitionCategory, Ease)
        var bases: [Entry] = []

        // Затемнение / растворение
        bases.append(("Растворение", .dissolve, .fade, .smooth))
        let dips: [(String, CIColor)] = [
            ("чёрный", CIColor(red: 0, green: 0, blue: 0)), ("белый", CIColor(red: 1, green: 1, blue: 1)),
            ("красный", CIColor(red: 0.95, green: 0.15, blue: 0.2)), ("оранжевый", CIColor(red: 1, green: 0.55, blue: 0.1)),
            ("жёлтый", CIColor(red: 1, green: 0.9, blue: 0.2)), ("зелёный", CIColor(red: 0.2, green: 0.85, blue: 0.35)),
            ("бирюзовый", CIColor(red: 0.1, green: 0.85, blue: 0.85)), ("синий", CIColor(red: 0.15, green: 0.35, blue: 0.95)),
            ("фиолетовый", CIColor(red: 0.55, green: 0.25, blue: 0.9)), ("розовый", CIColor(red: 1, green: 0.4, blue: 0.7)),
            ("золотой", CIColor(red: 1, green: 0.78, blue: 0.3)), ("серый", CIColor(red: 0.5, green: 0.5, blue: 0.5)),
            ("персик", CIColor(red: 1, green: 0.7, blue: 0.6)), ("мятный", CIColor(red: 0.6, green: 1, blue: 0.8))
        ]
        for (n, c) in dips { bases.append(("Через \(n)", .dip(c), .fade, .smooth)) }

        // Сдвиг / наезд / уход × 8 направлений × 4 кривые
        for d in Dir.allCases {
            for e in Ease.allCases {
                bases.append(("Сдвиг \(d.arrow) \(e.title)", .push(d), .push, e))
                bases.append(("Наезд \(d.arrow) \(e.title)", .cover(d), .cover, e))
                bases.append(("Уход \(d.arrow) \(e.title)", .reveal(d), .cover, e))
            }
        }

        // Линейные шторки: 16 углов × 3 мягкости
        let softs: [(String, CGFloat)] = [("чёткая", 0.03), ("мягкая", 0.3), ("туман", 0.9)]
        for i in 0..<16 {
            let deg = Double(i) * 22.5
            let label = deg.truncatingRemainder(dividingBy: 1) == 0 ? "\(Int(deg))°" : String(format: "%.1f°", deg)
            for (sn, s) in softs {
                bases.append(("Шторка \(label) \(sn)", .wipe(angle: CGFloat(deg) * .pi / 180, soft: s), .wipe, .smooth))
            }
        }

        // Ирисы / фигуры
        let shapes: [(String, CGFloat)] = [("круг", 1.0), ("овал", 1.8), ("столб", 0.55)]
        let centers: [(String, CGFloat, CGFloat)] = [("центр", 0.5, 0.5), ("↖", 0, 1), ("↗", 1, 1), ("↙", 0, 0), ("↘", 1, 0)]
        for inward in [false, true] {
            for (sn, sx) in shapes {
                for soft in [(" чётко", CGFloat(0.03)), (" мягко", CGFloat(0.4))] {
                    for (cn, cx, cy) in centers {
                        bases.append(("\(inward ? "Сужение" : "Расширение") \(sn) \(cn)\(soft.0)",
                                      .iris(inward: inward, scaleX: sx, soft: soft.1, cx: cx, cy: cy), .shape, .smooth))
                    }
                }
            }
        }

        // Жалюзи
        let bAngles: [(String, CGFloat)] = [("верт.", 0), ("гор.", .pi / 2), ("↗", .pi / 4), ("↖", 3 * .pi / 4)]
        for count in [4, 8, 16, 32] {
            for (an, a) in bAngles {
                for (sn, s) in [("чётко", CGFloat(0.05)), ("мягко", CGFloat(0.5))] {
                    bases.append(("Жалюзи \(count) \(an) \(sn)", .blinds(count: count, angle: a, soft: s), .blinds, .smooth))
                }
            }
        }

        // Сетки
        let sweeps = ["разом", "волна →", "из центра"]
        for cells in [4, 8, 16] {
            for diag in [false, true] {
                for sw in 0..<3 {
                    bases.append(("Сетка \(cells) \(diag ? "ромбы" : "квадраты") \(sweeps[sw])",
                                  .grid(cells: cells, diagonal: diag, sweep: sw), .blinds, .smooth))
                }
            }
        }

        // Шум
        for (gn, g) in [("пыль", CGFloat(1)), ("зерно", 4), ("крупно", 10), ("блоки", 24)] {
            for (sn, s) in [("чётко", CGFloat(0.03)), ("мягко", CGFloat(0.5))] {
                bases.append(("Шум \(gn) \(sn)", .noise(grain: g, cloud: false, soft: s), .noise, .smooth))
            }
        }
        for (cn, g) in [("S", CGFloat(30)), ("M", 70), ("L", 140)] {
            bases.append(("Облака \(cn)", .noise(grain: g, cloud: true, soft: 0.35), .noise, .smooth))
        }

        // Полосы, двери
        for count in [4, 8, 16] {
            bases.append(("Полосы \(count) верт.", .slices(count: count, vertical: true), .blinds, .smooth))
            bases.append(("Полосы \(count) гор.", .slices(count: count, vertical: false), .blinds, .smooth))
        }
        bases.append(("Двери верт. откр.", .doors(vertical: true, open: true), .wipe, .smooth))
        bases.append(("Двери верт. закр.", .doors(vertical: true, open: false), .wipe, .smooth))
        bases.append(("Двери гор. откр.", .doors(vertical: false, open: true), .wipe, .smooth))
        bases.append(("Двери гор. закр.", .doors(vertical: false, open: false), .wipe, .smooth))

        // Зум / вращение
        for s in [CGFloat(0.25), 0.5, 0.9] { bases.append(("Приближение ×\(s)", .zoom(inward: true, strength: s), .zoom, .smooth)) }
        for s in [CGFloat(0.25), 0.5, 0.7] { bases.append(("Отдаление ×\(s)", .zoom(inward: false, strength: s), .zoom, .smooth)) }
        for cw in [true, false] {
            for deg in [90, 180, 360] {
                bases.append(("Вращение \(cw ? "↻" : "↺") \(deg)°", .spin(cw: cw, angle: CGFloat(deg) * .pi / 180), .zoom, .smooth))
            }
        }

        // 3D
        bases.append(("Переворот гор.", .flip(vertical: false), .flip3d, .smooth))
        bases.append(("Переворот верт.", .flip(vertical: true), .flip3d, .smooth))
        bases.append(("Куб ←", .cube(left: true), .flip3d, .smooth))
        bases.append(("Куб →", .cube(left: false), .flip3d, .smooth))

        // Искажения
        for cw in [true, false] {
            for (sn, s) in [("слабый", CGFloat(3)), ("сильный", 8)] {
                bases.append(("Вихрь \(cw ? "↻" : "↺") \(sn)", .twirl(cw: cw, strength: s), .distort, .smooth))
            }
        }
        bases.append(("Выпуклость", .bump(sign: 1), .distort, .smooth))
        bases.append(("Вогнутость", .bump(sign: -1), .distort, .smooth))
        bases.append(("Сжатие", .pinch(sign: 1), .distort, .smooth))
        bases.append(("Растяжение", .pinch(sign: -1), .distort, .smooth))

        // Мозаики
        for (kn, k) in [("Пиксели", MosaicKind.pixel), ("Соты", .hex), ("Кристаллы", .crystal)] {
            for (sn, s) in [("мелко", CGFloat(0.6)), ("крупно", 1.4)] {
                bases.append(("\(kn) \(sn)", .mosaic(k, strength: s), .pixel, .smooth))
            }
        }

        // Комбинируем: сначала «чистые» (fx = none), потом все с эффектами
        var result: [TransitionSpec] = []
        result.reserveCapacity(bases.count * Fx.allCases.count)
        for fx in Fx.allCases {
            for (name, base, cat, ease) in bases {
                var category = cat
                switch fx {
                case .rgb, .shake: category = .glitch
                case .flash, .goldFlash: category = .light
                default: break
                }
                result.append(TransitionSpec(id: result.count + 1, name: name + fx.suffix, category: category,
                                             base: base, fx: fx, ease: ease))
            }
        }
        return result
    }
}

// =====================================================================
// MARK: - Transition renderer
// =====================================================================

enum TransitionRenderer {

    static func render(id: Int, from: CIImage, to: CIImage, t: CGFloat, rect: CGRect) -> CIImage {
        guard let spec = TransitionCatalog.spec(id) else { return t < 0.5 ? from : to }
        let e = spec.ease.apply(t)
        var out = renderBase(spec.base, from: from, to: to, e: e, rect: rect)
        out = applyFx(spec.fx, out, t: t, rect: rect)
        return out.composited(over: black(rect)).cropped(to: rect)
    }

    // MARK: Helpers

    private static func black(_ r: CGRect) -> CIImage { CIImage(color: CIColor.black).cropped(to: r) }
    private static func solid(_ c: CIColor, _ r: CGRect) -> CIImage { CIImage(color: c).cropped(to: r) }
    private static func clamp01(_ x: CGFloat) -> CGFloat { max(0, min(1, x)) }

    private static func opacity(_ image: CIImage, _ a: CGFloat) -> CIImage {
        let a = clamp01(a)
        guard a < 0.999 else { return image }
        return image.applyingFilter("CIColorMatrix", parameters: [
            "inputRVector": CIVector(x: 1, y: 0, z: 0, w: 0),
            "inputGVector": CIVector(x: 0, y: 1, z: 0, w: 0),
            "inputBVector": CIVector(x: 0, y: 0, z: 1, w: 0),
            "inputAVector": CIVector(x: 0, y: 0, z: 0, w: a),
            "inputBiasVector": CIVector(x: 0, y: 0, z: 0, w: 0)
        ])
    }

    private static func crossfade(_ a: CIImage, _ b: CIImage, _ t: CGFloat) -> CIImage {
        opacity(b, t).composited(over: a)
    }

    private static func move(_ img: CIImage, _ x: CGFloat, _ y: CGFloat) -> CIImage {
        img.transformed(by: CGAffineTransform(translationX: x, y: y))
    }

    private static func scaledXY(_ img: CIImage, _ sx: CGFloat, _ sy: CGFloat, _ r: CGRect) -> CIImage {
        let t = CGAffineTransform(translationX: -r.midX, y: -r.midY)
            .concatenating(CGAffineTransform(scaleX: max(0.001, sx), y: max(0.001, sy)))
            .concatenating(CGAffineTransform(translationX: r.midX, y: r.midY))
        return img.transformed(by: t)
    }

    private static func scaled(_ img: CIImage, _ s: CGFloat, _ r: CGRect) -> CIImage { scaledXY(img, s, s, r) }

    private static func rotated(_ img: CIImage, angle: CGFloat, scale: CGFloat, _ r: CGRect) -> CIImage {
        let t = CGAffineTransform(translationX: -r.midX, y: -r.midY)
            .concatenating(CGAffineTransform(rotationAngle: angle))
            .concatenating(CGAffineTransform(scaleX: scale, y: scale))
            .concatenating(CGAffineTransform(translationX: r.midX, y: r.midY))
        return img.transformed(by: t)
    }

    private static func ciFilter(_ name: String, _ image: CIImage, _ params: [String: Any]) -> CIImage? {
        guard let f = CIFilter(name: name) else { return nil }
        f.setValue(image, forKey: kCIInputImageKey)
        for (k, v) in params where f.inputKeys.contains(k) { f.setValue(v, forKey: k) }
        return f.outputImage
    }

    private static func blurred(_ img: CIImage, sigma: CGFloat, _ r: CGRect) -> CIImage {
        guard sigma > 0.5 else { return img }
        return img.clampedToExtent().applyingGaussianBlur(sigma: Double(sigma)).cropped(to: r)
    }

    private static func vec(_ p: CGPoint) -> CIVector { CIVector(x: p.x, y: p.y) }

    // MARK: Mask fields (поле «когда открывать этот пиксель»: 0 — сразу, 1 — в самом конце)

    private static func threshold(_ g: CIImage, e: CGFloat, soft: CGFloat, _ r: CGRect) -> CIImage {
        let s = max(0.001, soft)
        let a = -1 / s
        let bias = e * (1 + s) / s
        return g
            .applyingFilter("CIColorMatrix", parameters: [
                "inputRVector": CIVector(x: a, y: 0, z: 0, w: 0),
                "inputGVector": CIVector(x: a, y: 0, z: 0, w: 0),
                "inputBVector": CIVector(x: a, y: 0, z: 0, w: 0),
                "inputAVector": CIVector(x: 0, y: 0, z: 0, w: 1),
                "inputBiasVector": CIVector(x: bias, y: bias, z: bias, w: 0)
            ])
            .applyingFilter("CIColorClamp", parameters: [
                "inputMinComponents": CIVector(x: 0, y: 0, z: 0, w: 0),
                "inputMaxComponents": CIVector(x: 1, y: 1, z: 1, w: 1)
            ])
            .cropped(to: r)
    }

    private static func revealWithMask(_ to: CIImage, over from: CIImage, mask: CIImage, _ r: CGRect) -> CIImage {
        to.applyingFilter("CIBlendWithMask", parameters: [
            kCIInputBackgroundImageKey: from,
            kCIInputMaskImageKey: mask
        ]).cropped(to: r)
    }

    private static func linearField(angle: CGFloat, _ r: CGRect) -> CIImage? {
        guard let f = CIFilter(name: "CILinearGradient") else { return nil }
        let dx = cos(angle), dy = sin(angle)
        let len = abs(r.width * dx) + abs(r.height * dy)
        f.setValue(CIVector(x: r.midX - dx * len / 2, y: r.midY - dy * len / 2), forKey: "inputPoint0")
        f.setValue(CIVector(x: r.midX + dx * len / 2, y: r.midY + dy * len / 2), forKey: "inputPoint1")
        f.setValue(CIColor.black, forKey: "inputColor0")
        f.setValue(CIColor.white, forKey: "inputColor1")
        return f.outputImage?.cropped(to: r)
    }

    private static func radialField(center: CGPoint, radius: CGFloat, invert: Bool, _ r: CGRect) -> CIImage? {
        guard let f = CIFilter(name: "CIRadialGradient") else { return nil }
        f.setValue(vec(center), forKey: "inputCenter")
        f.setValue(0, forKey: "inputRadius0")
        f.setValue(radius, forKey: "inputRadius1")
        f.setValue(invert ? CIColor.white : CIColor.black, forKey: "inputColor0")
        f.setValue(invert ? CIColor.black : CIColor.white, forKey: "inputColor1")
        return f.outputImage?.cropped(to: r)
    }

    private static func stripeField(halfWidth: CGFloat, angle: CGFloat, _ r: CGRect) -> CIImage? {
        guard let f = CIFilter(name: "CIStripesGenerator") else { return nil }
        f.setValue(CIVector(x: r.midX, y: r.midY), forKey: "inputCenter")
        f.setValue(CIColor.black, forKey: "inputColor0")
        f.setValue(CIColor.white, forKey: "inputColor1")
        f.setValue(max(2, halfWidth), forKey: "inputWidth")
        f.setValue(0, forKey: "inputSharpness")
        guard var img = f.outputImage else { return nil }
        if angle != 0 {
            let t = CGAffineTransform(translationX: -r.midX, y: -r.midY)
                .concatenating(CGAffineTransform(rotationAngle: angle))
                .concatenating(CGAffineTransform(translationX: r.midX, y: r.midY))
            img = img.transformed(by: t)
        }
        return img.cropped(to: r)
    }

    private static func noiseField(grain: CGFloat, cloud: Bool, _ r: CGRect) -> CIImage? {
        guard let rg = CIFilter(name: "CIRandomGenerator")?.outputImage else { return nil }
        var g = rg.applyingFilter("CIColorMatrix", parameters: [
            "inputRVector": CIVector(x: 1, y: 0, z: 0, w: 0),
            "inputGVector": CIVector(x: 1, y: 0, z: 0, w: 0),
            "inputBVector": CIVector(x: 1, y: 0, z: 0, w: 0),
            "inputAVector": CIVector(x: 0, y: 0, z: 0, w: 0),
            "inputBiasVector": CIVector(x: 0, y: 0, z: 0, w: 1)
        ])
        if grain > 1 {
            if !cloud { g = g.samplingNearest() }          // блоки
            g = g.transformed(by: CGAffineTransform(scaleX: grain, y: grain))   // билинейно → «облака»
        }
        if cloud {
            let k: CGFloat = 1.8
            g = g.applyingFilter("CIColorMatrix", parameters: [
                "inputRVector": CIVector(x: k, y: 0, z: 0, w: 0),
                "inputGVector": CIVector(x: k, y: 0, z: 0, w: 0),
                "inputBVector": CIVector(x: k, y: 0, z: 0, w: 0),
                "inputAVector": CIVector(x: 0, y: 0, z: 0, w: 1),
                "inputBiasVector": CIVector(x: 0.5 - 0.5 * k, y: 0.5 - 0.5 * k, z: 0.5 - 0.5 * k, w: 0)
            ])
        }
        return g.applyingFilter("CIColorClamp", parameters: [
            "inputMinComponents": CIVector(x: 0, y: 0, z: 0, w: 0),
            "inputMaxComponents": CIVector(x: 1, y: 1, z: 1, w: 1)
        ]).cropped(to: r)
    }

    // MARK: Base effects

    private static func renderBase(_ base: Base, from: CIImage, to: CIImage, e: CGFloat, rect: CGRect) -> CIImage {
        let W = rect.width, H = rect.height
        let c = CGPoint(x: rect.midX, y: rect.midY)
        let ec = clamp01(e)
        let fallback = crossfade(from, to, ec)

        switch base {

        case .dissolve:
            return fallback

        case .dip(let color):
            let bg = solid(color, rect)
            return ec < 0.5 ? opacity(from, 1 - 2 * ec).composited(over: bg)
                            : opacity(to, 2 * ec - 1).composited(over: bg)

        case .push(let d):
            let v = d.vector
            return move(to, v.x * W * (e - 1), v.y * H * (e - 1))
                .composited(over: move(from, v.x * W * e, v.y * H * e))

        case .cover(let d):
            let v = d.vector
            return move(to, v.x * W * (e - 1), v.y * H * (e - 1)).composited(over: from)

        case .reveal(let d):
            let v = d.vector
            return move(from, v.x * W * e, v.y * H * e).composited(over: to)

        case .wipe(let angle, let soft):
            guard let g = linearField(angle: angle, rect) else { return fallback }
            return revealWithMask(to, over: from, mask: threshold(g, e: ec, soft: soft, rect), rect)

        case .iris(let inward, let sx, let soft, let cx, let cy):
            let center = CGPoint(x: cx * W, y: cy * H)
            var R: CGFloat = 0
            for corner in [CGPoint(x: 0, y: 0), CGPoint(x: W, y: 0), CGPoint(x: 0, y: H), CGPoint(x: W, y: H)] {
                R = max(R, hypot((corner.x - center.x) / sx, corner.y - center.y))
            }
            guard var g = radialField(center: center, radius: max(1, R), invert: inward, rect.insetBy(dx: -W, dy: -H)) else { return fallback }
            if sx != 1 {
                let t = CGAffineTransform(translationX: -center.x, y: -center.y)
                    .concatenating(CGAffineTransform(scaleX: sx, y: 1))
                    .concatenating(CGAffineTransform(translationX: center.x, y: center.y))
                g = g.transformed(by: t)
            }
            return revealWithMask(to, over: from, mask: threshold(g, e: ec, soft: soft, rect), rect)

        case .blinds(let count, let angle, let soft):
            guard let g = stripeField(halfWidth: W / CGFloat(2 * count), angle: angle, rect) else { return fallback }
            return revealWithMask(to, over: from, mask: threshold(g, e: ec, soft: soft, rect), rect)

        case .grid(let cells, let diagonal, let sweep):
            let half = W / CGFloat(2 * cells)
            let rot: CGFloat = diagonal ? .pi / 4 : 0
            guard let gx = stripeField(halfWidth: half, angle: rot, rect),
                  let gy = stripeField(halfWidth: half, angle: rot + .pi / 2, rect) else { return fallback }
            var g = gx.applyingFilter("CIMaximumCompositing", parameters: [kCIInputBackgroundImageKey: gy]).cropped(to: rect)
            if sweep == 1, let lin = linearField(angle: 0, rect) {
                g = crossfade(g, lin, 0.5)
            } else if sweep == 2, let rad = radialField(center: c, radius: hypot(W, H) / 2, invert: false, rect) {
                g = crossfade(g, rad, 0.5)
            }
            return revealWithMask(to, over: from, mask: threshold(g, e: ec, soft: 0.12, rect), rect)

        case .noise(let grain, let cloud, let soft):
            guard let g = noiseField(grain: grain, cloud: cloud, rect) else { return fallback }
            return revealWithMask(to, over: from, mask: threshold(g, e: ec, soft: soft, rect), rect)

        case .slices(let count, let vertical):
            var acc = to
            for k in 0..<count {
                let sign: CGFloat = k % 2 == 0 ? 1 : -1
                let strip: CGRect
                var dx: CGFloat = 0, dy: CGFloat = 0
                if vertical {
                    let w = W / CGFloat(count)
                    strip = CGRect(x: CGFloat(k) * w, y: 0, width: w + 0.5, height: H)
                    dy = sign * H * ec
                } else {
                    let h = H / CGFloat(count)
                    strip = CGRect(x: 0, y: CGFloat(k) * h, width: W, height: h + 0.5)
                    dx = sign * W * ec
                }
                acc = move(from.cropped(to: strip), dx, dy).composited(over: acc)
            }
            return acc

        case .doors(let vertical, let open):
            let src = open ? from : to
            let bg = open ? to : from
            let k = open ? ec : (1 - ec)
            if vertical {
                let l = move(src.cropped(to: CGRect(x: 0, y: 0, width: W / 2, height: H)), -W / 2 * k, 0)
                let r = move(src.cropped(to: CGRect(x: W / 2, y: 0, width: W / 2, height: H)), W / 2 * k, 0)
                return l.composited(over: r.composited(over: bg))
            } else {
                let b = move(src.cropped(to: CGRect(x: 0, y: 0, width: W, height: H / 2)), 0, -H / 2 * k)
                let u = move(src.cropped(to: CGRect(x: 0, y: H / 2, width: W, height: H / 2)), 0, H / 2 * k)
                return b.composited(over: u.composited(over: bg))
            }

        case .zoom(let inward, let s):
            if inward {
                return crossfade(scaled(from, 1 + s * ec, rect), scaled(to, 1 + s * (1 - ec), rect), ec)
            } else {
                let under = scaled(to, 1 + 0.75 * s * (1 - ec), rect)
                let top = opacity(scaled(from, 1 - 0.8 * s * ec, rect), 1 - ec)
                return top.composited(over: under)
            }

        case .spin(let cw, let angle):
            let sign: CGFloat = cw ? -1 : 1
            let f = rotated(from, angle: sign * angle * ec, scale: 1 + 0.6 * ec, rect)
            let t = rotated(to, angle: -sign * angle * (1 - ec), scale: 1 + 0.6 * (1 - ec), rect)
            return crossfade(f.composited(over: black(rect)), t.composited(over: black(rect)), ec)

        case .flip(let vertical):
            let useFrom = ec < 0.5
            let img = useFrom ? from : to
            let k = abs(cos((useFrom ? ec : (1 - ec)) * .pi))
            return vertical ? scaledXY(img, 1, k, rect) : scaledXY(img, k, 1, rect)

        case .cube(let left):
            func cubeLeft(_ a: CIImage, _ b: CIImage) -> CIImage {
                let cy = H / 2
                let seam = H * (1 + 0.12 * sin(ec * .pi))
                let fromOuter = H * (1 - 0.3 * ec)
                let toOuter = H * (1 - 0.3 * (1 - ec))
                let xs = W * (1 - ec)
                func face(_ img: CIImage, tl: CGPoint, tr: CGPoint, br: CGPoint, bl: CGPoint) -> CIImage {
                    ciFilter("CIPerspectiveTransform", img.cropped(to: rect), [
                        "inputTopLeft": vec(tl), "inputTopRight": vec(tr),
                        "inputBottomRight": vec(br), "inputBottomLeft": vec(bl)
                    ]) ?? img
                }
                if xs < 2 { return b }
                if W - xs < 2 { return a }
                let fa = face(a, tl: CGPoint(x: 0, y: cy + fromOuter / 2), tr: CGPoint(x: xs, y: cy + seam / 2),
                              br: CGPoint(x: xs, y: cy - seam / 2), bl: CGPoint(x: 0, y: cy - fromOuter / 2))
                let fb = face(b, tl: CGPoint(x: xs, y: cy + seam / 2), tr: CGPoint(x: W, y: cy + toOuter / 2),
                              br: CGPoint(x: W, y: cy - toOuter / 2), bl: CGPoint(x: xs, y: cy - seam / 2))
                return fb.composited(over: fa)
            }
            func flipX(_ img: CIImage) -> CIImage {
                img.transformed(by: CGAffineTransform(scaleX: -1, y: 1).concatenating(CGAffineTransform(translationX: W, y: 0)))
            }
            return left ? cubeLeft(from, to) : flipX(cubeLeft(flipX(from), flipX(to)))

        case .twirl(let cw, let s):
            let sign: CGFloat = cw ? 1 : -1
            let R = hypot(W, H) * 0.6
            func tw(_ img: CIImage, _ a: CGFloat) -> CIImage {
                ciFilter("CITwirlDistortion", img.clampedToExtent(), [
                    "inputCenter": vec(c), "inputRadius": R, "inputAngle": a
                ])?.cropped(to: rect) ?? img
            }
            return crossfade(tw(from, sign * s * ec), tw(to, -sign * s * (1 - ec)), ec)

        case .bump(let sign):
            let R = min(W, H) * 0.7
            func bp(_ img: CIImage, _ a: CGFloat) -> CIImage {
                ciFilter("CIBumpDistortion", img.clampedToExtent(), [
                    "inputCenter": vec(c), "inputRadius": R, "inputScale": a
                ])?.cropped(to: rect) ?? img
            }
            return crossfade(bp(from, sign * 1.6 * ec), bp(to, sign * 1.6 * (1 - ec)), ec)

        case .pinch(let sign):
            let R = min(W, H) * 0.8
            func pn(_ img: CIImage, _ a: CGFloat) -> CIImage {
                ciFilter("CIPinchDistortion", img.clampedToExtent(), [
                    "inputCenter": vec(c), "inputRadius": R, "inputScale": a
                ])?.cropped(to: rect) ?? img
            }
            return crossfade(pn(from, sign * 1.5 * ec), pn(to, sign * 1.5 * (1 - ec)), ec)

        case .mosaic(let kind, let strength):
            let amount = sin(ec * .pi) * strength * min(W, H) * 0.06
            func mo(_ img: CIImage) -> CIImage {
                guard amount > 1.5 else { return img }
                let src = img.clampedToExtent()
                let out: CIImage?
                switch kind {
                case .pixel: out = ciFilter("CIPixellate", src, ["inputScale": amount, "inputCenter": CIVector(x: 0, y: 0)])
                case .hex: out = ciFilter("CIHexagonalPixellate", src, ["inputScale": amount, "inputCenter": CIVector(x: 0, y: 0)])
                case .crystal: out = ciFilter("CICrystallize", src, ["inputRadius": amount * 0.8, "inputCenter": CIVector(x: 0, y: 0)])
                }
                return out?.cropped(to: rect) ?? img
            }
            return crossfade(mo(from), mo(to), ec)
        }
    }

    // MARK: Post effects

    private static func applyFx(_ fx: Fx, _ img: CIImage, t: CGFloat, rect: CGRect) -> CIImage {
        let W = rect.width, H = rect.height
        let s = sin(clamp01(t) * .pi)       // 0 → 1 → 0
        guard s > 0.001 else { return img }

        func addColor(_ c: CIColor, _ amount: CGFloat) -> CIImage {
            let overlay = solid(CIColor(red: c.red * amount, green: c.green * amount, blue: c.blue * amount, alpha: 1), rect)
            return overlay.applyingFilter("CIAdditionCompositing", parameters: [kCIInputBackgroundImageKey: img]).cropped(to: rect)
        }

        switch fx {
        case .none:
            return img

        case .blur:
            return blurred(img, sigma: s * min(W, H) * 0.025, rect)

        case .zoomPulse:
            return scaled(img, 1 + 0.18 * s, rect)

        case .rgb:
            let d = s * W * 0.03
            func channel(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat) -> CIImage {
                img.applyingFilter("CIColorMatrix", parameters: [
                    "inputRVector": CIVector(x: r, y: 0, z: 0, w: 0),
                    "inputGVector": CIVector(x: 0, y: g, z: 0, w: 0),
                    "inputBVector": CIVector(x: 0, y: 0, z: b, w: 0),
                    "inputAVector": CIVector(x: 0, y: 0, z: 0, w: 1),
                    "inputBiasVector": CIVector(x: 0, y: 0, z: 0, w: 0)
                ])
            }
            let red = move(channel(1, 0, 0), d, 0)
            let green = channel(0, 1, 0)
            let blue = move(channel(0, 0, 1), -d, 0)
            let rg = green.applyingFilter("CIAdditionCompositing", parameters: [kCIInputBackgroundImageKey: red])
            return blue.applyingFilter("CIAdditionCompositing", parameters: [kCIInputBackgroundImageKey: rg]).cropped(to: rect)

        case .shake:
            let big = scaled(img, 1.07, rect)
            return move(big, sin(t * 45) * s * W * 0.03, cos(t * 33) * s * H * 0.012)

        case .flash:
            return addColor(CIColor(red: 1, green: 1, blue: 1), s * s * 0.95)

        case .goldFlash:
            return addColor(CIColor(red: 1, green: 0.78, blue: 0.35), s * s * 0.9)

        case .hue:
            return img.applyingFilter("CIHueAdjustment", parameters: [kCIInputAngleKey: s * 3.0])

        case .saturate:
            return img.applyingFilter("CIColorControls", parameters: [
                kCIInputSaturationKey: 1 + 1.6 * s, kCIInputContrastKey: 1 + 0.2 * s
            ])

        case .tilt:
            return rotated(img, angle: s * 0.12, scale: 1 + 0.15 * s, rect)

        case .zoomBlur:
            let blurredImg = ciFilter("CIZoomBlur", img.clampedToExtent(), [
                "inputCenter": CIVector(x: rect.midX, y: rect.midY), "inputAmount": s * 45
            ])?.cropped(to: rect)
            return blurredImg ?? img
        }
    }
}

// =====================================================================
// MARK: - Text engine: палитра, шрифты, тени, стили, анимации
// =====================================================================

enum TextPalette {
    /// 60 цветов: 6 нейтральных + 18 оттенков × (яркие, пастельные, глубокие).
    static let colors: [UIColor] = {
        var c: [UIColor] = [
            .white, UIColor(white: 0.85, alpha: 1), UIColor(white: 0.6, alpha: 1),
            UIColor(white: 0.35, alpha: 1), UIColor(white: 0.12, alpha: 1), .black
        ]
        let hues: [CGFloat] = stride(from: 0, to: 360, by: 20).map { CGFloat($0) / 360 }
        for h in hues { c.append(UIColor(hue: h, saturation: 0.9, brightness: 1.0, alpha: 1)) }
        for h in hues { c.append(UIColor(hue: h, saturation: 0.5, brightness: 1.0, alpha: 1)) }
        for h in hues { c.append(UIColor(hue: h, saturation: 0.95, brightness: 0.6, alpha: 1)) }
        return c
    }()

    static func color(_ i: Int) -> UIColor { colors[max(0, min(i, colors.count - 1))] }

    // Индексы для пресетов
    static let white = 0, black = 5
    static func vivid(_ deg: Int) -> Int { 6 + deg / 20 }
    static func pastel(_ deg: Int) -> Int { 24 + deg / 20 }
    static func deep(_ deg: Int) -> Int { 42 + deg / 20 }
}

struct TextFontOption {
    let title: String
    let name: String?
    let design: UIFontDescriptor.SystemDesign?
}

enum TextFonts {
    static let all: [TextFontOption] = [
        TextFontOption(title: "Система", name: nil, design: nil),
        TextFontOption(title: "Скруглённый", name: nil, design: .rounded),
        TextFontOption(title: "Моно", name: nil, design: .monospaced),
        TextFontOption(title: "Засечки", name: nil, design: .serif),
        TextFontOption(title: "Georgia", name: "Georgia-Bold", design: nil),
        TextFontOption(title: "Courier", name: "CourierNewPS-BoldMT", design: nil),
        TextFontOption(title: "Marker Felt", name: "MarkerFelt-Wide", design: nil),
        TextFontOption(title: "Chalkduster", name: "Chalkduster", design: nil),
        TextFontOption(title: "Noteworthy", name: "Noteworthy-Bold", design: nil),
        TextFontOption(title: "Avenir", name: "AvenirNext-Heavy", design: nil),
        TextFontOption(title: "Futura", name: "Futura-Bold", design: nil),
        TextFontOption(title: "Snell", name: "SnellRoundhand-Bold", design: nil),
        TextFontOption(title: "Papyrus", name: "Papyrus", design: nil),
        TextFontOption(title: "Bradley", name: "BradleyHandITCTT-Bold", design: nil),
        TextFontOption(title: "Copperplate", name: "Copperplate-Bold", design: nil),
        TextFontOption(title: "Didot", name: "Didot-Bold", design: nil),
        TextFontOption(title: "Optima", name: "Optima-ExtraBlack", design: nil),
        TextFontOption(title: "Baskerville", name: "Baskerville-Bold", design: nil),
        TextFontOption(title: "Trebuchet", name: "TrebuchetMS-Bold", design: nil),
        TextFontOption(title: "Arial Round", name: "ArialRoundedMTBold", design: nil),
        TextFontOption(title: "Typewriter", name: "AmericanTypewriter-Bold", design: nil),
        TextFontOption(title: "Palatino", name: "Palatino-Bold", design: nil),
        TextFontOption(title: "Gill Sans", name: "GillSans-Bold", design: nil),
        TextFontOption(title: "Zapfino", name: "Zapfino", design: nil),
        TextFontOption(title: "Savoye", name: "SavoyeLetPlain", design: nil),
        TextFontOption(title: "Party", name: "PartyLetPlain", design: nil),
        TextFontOption(title: "Bodoni", name: "BodoniSvtyTwoITCTT-Bold", design: nil),
        TextFontOption(title: "Cochin", name: "Cochin-Bold", design: nil),
        TextFontOption(title: "Menlo", name: "Menlo-Bold", design: nil),
        TextFontOption(title: "Verdana", name: "Verdana-Bold", design: nil),
        TextFontOption(title: "Condensed", name: "HelveticaNeue-CondensedBlack", design: nil),
        TextFontOption(title: "Narrow", name: "AvenirNextCondensed-Heavy", design: nil),
        TextFontOption(title: "DIN", name: "DINAlternate-Bold", design: nil),
        TextFontOption(title: "Rockwell", name: "Rockwell-Bold", design: nil),
        TextFontOption(title: "Clarendon", name: "Superclarendon-Black", design: nil)
    ]

    static let weights: [(String, UIFont.Weight)] = [
        ("Тонкий", .thin), ("Лёгкий", .light), ("Обычный", .regular), ("Medium", .medium),
        ("Semibold", .semibold), ("Bold", .bold), ("Heavy", .heavy), ("Black", .black)
    ]

    static func index(_ title: String) -> Int { all.firstIndex { $0.title == title } ?? 0 }

    static func font(_ o: TextOverlay, size: CGFloat) -> UIFont {
        let opt = all[max(0, min(o.fontIndex, all.count - 1))]
        let w = weights[max(0, min(o.weight, weights.count - 1))].1
        if let name = opt.name, let f = UIFont(name: name, size: size) { return f }
        var f = UIFont.systemFont(ofSize: size, weight: w)
        if let design = opt.design, let d = f.fontDescriptor.withDesign(design) {
            f = UIFont(descriptor: d, size: size)
        }
        return f
    }
}

enum TextShadow: Int, CaseIterable {
    case none, soft, hard, far, deep, lift, halo

    var title: String {
        switch self {
        case .none: return "Без тени"
        case .soft: return "Мягкая"
        case .hard: return "Жёсткая"
        case .far: return "Далёкая"
        case .deep: return "Глубокая"
        case .lift: return "Подъём"
        case .halo: return "Ореол"
        }
    }
}

// MARK: Animations

struct TextAnimState {
    var alpha: CGFloat = 1
    var dx: CGFloat = 0        // доля ширины кадра, + вправо
    var dy: CGFloat = 0        // доля высоты кадра, + вниз
    var scale: CGFloat = 1
    var scaleX: CGFloat = 1
    var rot: CGFloat = 0       // по часовой стрелке
    var blur: CGFloat = 0      // доля высоты кадра
    var visible: CGFloat = 1   // доля показанных символов
    var byWord = false
    var wipe: CGFloat = 1
    var wipeFromRight = false
    var glitch: CGFloat = 0
}

enum TextAnim: Int, CaseIterable {
    case none, fade, slideUp, slideDown, slideLeft, slideRight, pop, zoomIn, grow, drop
    case spin, flip, typewriter, words, wipeRight, wipeLeft, blur, flicker, glitch, swing

    var title: String {
        switch self {
        case .none: return "Нет"
        case .fade: return "Проявление"
        case .slideUp: return "Снизу вверх"
        case .slideDown: return "Сверху вниз"
        case .slideLeft: return "Справа налево"
        case .slideRight: return "Слева направо"
        case .pop: return "Поп"
        case .zoomIn: return "Из зума"
        case .grow: return "Рост"
        case .drop: return "Падение"
        case .spin: return "Вращение"
        case .flip: return "Переворот"
        case .typewriter: return "Печать"
        case .words: return "По словам"
        case .wipeRight: return "Шторка →"
        case .wipeLeft: return "Шторка ←"
        case .blur: return "Из размытия"
        case .flicker: return "Мерцание"
        case .glitch: return "Глитч"
        case .swing: return "Качели"
        }
    }

    var symbol: String {
        switch self {
        case .none: return "xmark"
        case .fade: return "drop.halffull"
        case .slideUp: return "arrow.up"
        case .slideDown: return "arrow.down"
        case .slideLeft: return "arrow.left"
        case .slideRight: return "arrow.right"
        case .pop: return "star.fill"
        case .zoomIn: return "plus.magnifyingglass"
        case .grow: return "arrow.up.left.and.arrow.down.right"
        case .drop: return "arrow.down.to.line"
        case .spin: return "arrow.triangle.2.circlepath"
        case .flip: return "arrow.left.and.right"
        case .typewriter: return "keyboard"
        case .words: return "text.alignleft"
        case .wipeRight: return "forward.end.fill"
        case .wipeLeft: return "backward.end.fill"
        case .blur: return "eye.slash"
        case .flicker: return "bolt.fill"
        case .glitch: return "waveform"
        case .swing: return "arrow.2.squarepath"
        }
    }

    /// a: 0 — текст скрыт, 1 — показан полностью. inPhase: появление (true) или исчезание (false).
    func apply(a rawA: CGFloat, inPhase: Bool, time: Double, to s: inout TextAnimState) {
        let a = max(0, min(1, rawA))
        guard a < 1, self != .none else { return }
        let k = 1 - a
        let sign: CGFloat = inPhase ? 1 : -1

        func backOut(_ x: CGFloat) -> CGFloat {
            let c1: CGFloat = 1.70158, c3 = c1 + 1
            return 1 + c3 * pow(x - 1, 3) + c1 * pow(x - 1, 2)
        }
        func bounceOut(_ x: CGFloat) -> CGFloat {
            let n1: CGFloat = 7.5625, d1: CGFloat = 2.75
            if x < 1 / d1 { return n1 * x * x }
            if x < 2 / d1 { let y = x - 1.5 / d1; return n1 * y * y + 0.75 }
            if x < 2.5 / d1 { let y = x - 2.25 / d1; return n1 * y * y + 0.9375 }
            let y = x - 2.625 / d1
            return n1 * y * y + 0.984375
        }

        switch self {
        case .none: break
        case .fade: s.alpha *= a
        case .slideUp: s.alpha *= a; s.dy += sign * k * 0.10
        case .slideDown: s.alpha *= a; s.dy -= sign * k * 0.10
        case .slideLeft: s.alpha *= a; s.dx += sign * k * 0.18
        case .slideRight: s.alpha *= a; s.dx -= sign * k * 0.18
        case .pop: s.scale *= max(0.001, backOut(a)); s.alpha *= min(1, a * 3)
        case .zoomIn: s.scale *= 1 + k; s.alpha *= a
        case .grow: s.scale *= 0.3 + 0.7 * a; s.alpha *= a
        case .drop: s.dy -= sign * (1 - bounceOut(a)) * 0.4; s.alpha *= min(1, a * 4)
        case .spin: s.rot -= sign * k * .pi; s.scale *= 0.4 + 0.6 * a; s.alpha *= a
        case .flip: s.scaleX *= max(0.02, a); s.alpha *= a
        case .typewriter: s.visible = min(s.visible, a)
        case .words: s.visible = min(s.visible, a); s.byWord = true
        case .wipeRight: s.wipe = min(s.wipe, a); s.wipeFromRight = false
        case .wipeLeft: s.wipe = min(s.wipe, a); s.wipeFromRight = true
        case .blur: s.blur += k * 0.03; s.alpha *= a
        case .flicker: s.alpha *= a * (sin(time * 70) > 0 ? 1 : 0.15)
        case .glitch: s.glitch = max(s.glitch, k); s.alpha *= max(0.35, a)
        case .swing: s.rot += sign * k * 0.7 * cos(a * 10); s.alpha *= min(1, a * 3)
        }
    }
}

// MARK: Overlay style helpers

extension TextOverlay {
    mutating func resetStyle() {
        fillIndex = 0
        strokeIndex = -1
        strokeWidth = 0.08
        shadow = 0
        shadowColorIndex = TextPalette.black
        glowIndex = -1
        boxIndex = -1
        boxOpacity = 0.9
        fontIndex = 0
        weight = 6
        italic = false
        underline = false
        strike = false
        letterSpacing = 0
    }
}

struct TextPreset {
    let title: String
    let apply: (inout TextOverlay) -> Void
}

enum TextPresets {
    static let all: [TextPreset] = [
        TextPreset(title: "Классика") { o in o.resetStyle(); o.shadow = TextShadow.soft.rawValue },
        TextPreset(title: "Контур") { o in o.resetStyle(); o.strokeIndex = TextPalette.black; o.strokeWidth = 0.1 },
        TextPreset(title: "Жёлтый") { o in
            o.resetStyle(); o.fillIndex = TextPalette.vivid(60); o.strokeIndex = TextPalette.black
            o.strokeWidth = 0.1; o.shadow = TextShadow.hard.rawValue
        },
        TextPreset(title: "Неон розовый") { o in o.resetStyle(); o.glowIndex = TextPalette.vivid(320) },
        TextPreset(title: "Неон голубой") { o in o.resetStyle(); o.glowIndex = TextPalette.vivid(180) },
        TextPreset(title: "Неон зелёный") { o in o.resetStyle(); o.glowIndex = TextPalette.vivid(120) },
        TextPreset(title: "Неон фиолет") { o in o.resetStyle(); o.glowIndex = TextPalette.vivid(280) },
        TextPreset(title: "Неон жёлтый") { o in o.resetStyle(); o.glowIndex = TextPalette.vivid(60) },
        TextPreset(title: "Плашка тёмная") { o in o.resetStyle(); o.boxIndex = TextPalette.black; o.boxOpacity = 0.85 },
        TextPreset(title: "Плашка белая") { o in o.resetStyle(); o.fillIndex = TextPalette.black; o.boxIndex = TextPalette.white; o.boxOpacity = 0.95 },
        TextPreset(title: "Плашка жёлтая") { o in o.resetStyle(); o.fillIndex = TextPalette.black; o.boxIndex = TextPalette.vivid(60); o.boxOpacity = 1 },
        TextPreset(title: "Плашка розовая") { o in o.resetStyle(); o.boxIndex = TextPalette.vivid(320); o.boxOpacity = 1 },
        TextPreset(title: "Плашка синяя") { o in o.resetStyle(); o.boxIndex = TextPalette.vivid(220); o.boxOpacity = 1 },
        TextPreset(title: "Ретро") { o in
            o.resetStyle(); o.fontIndex = TextFonts.index("Futura"); o.fillIndex = TextPalette.vivid(60)
            o.shadow = TextShadow.far.rawValue; o.shadowColorIndex = TextPalette.vivid(320)
        },
        TextPreset(title: "Комикс") { o in
            o.resetStyle(); o.fontIndex = TextFonts.index("Marker Felt"); o.fillIndex = TextPalette.vivid(60)
            o.strokeIndex = TextPalette.black; o.strokeWidth = 0.14; o.shadow = TextShadow.hard.rawValue
        },
        TextPreset(title: "Тик-ток") { o in
            o.resetStyle(); o.shadow = TextShadow.hard.rawValue; o.shadowColorIndex = TextPalette.vivid(180)
        },
        TextPreset(title: "Огонь") { o in
            o.resetStyle(); o.fillIndex = TextPalette.vivid(20); o.glowIndex = TextPalette.vivid(0)
            o.strokeIndex = TextPalette.deep(0); o.strokeWidth = 0.06
        },
        TextPreset(title: "Лёд") { o in o.resetStyle(); o.fillIndex = TextPalette.pastel(180); o.glowIndex = TextPalette.vivid(220) },
        TextPreset(title: "Золото") { o in
            o.resetStyle(); o.fillIndex = TextPalette.vivid(40); o.strokeIndex = TextPalette.deep(20)
            o.strokeWidth = 0.07; o.shadow = TextShadow.soft.rawValue
        },
        TextPreset(title: "Мятный") { o in o.resetStyle(); o.fillIndex = TextPalette.pastel(120); o.shadow = TextShadow.soft.rawValue },
        TextPreset(title: "Закат") { o in o.resetStyle(); o.fillIndex = TextPalette.pastel(320); o.glowIndex = TextPalette.vivid(20) },
        TextPreset(title: "Тёмный") { o in o.resetStyle(); o.fillIndex = TextPalette.black; o.strokeIndex = TextPalette.white; o.strokeWidth = 0.1 },
        TextPreset(title: "Двойной") { o in
            o.resetStyle(); o.strokeIndex = TextPalette.black; o.strokeWidth = 0.1; o.glowIndex = TextPalette.vivid(320)
        },
        TextPreset(title: "Минимал") { o in
            o.resetStyle(); o.weight = 1; o.letterSpacing = 0.15; o.shadow = TextShadow.soft.rawValue
        },
        TextPreset(title: "Рукописный") { o in
            o.resetStyle(); o.fontIndex = TextFonts.index("Snell"); o.shadow = TextShadow.soft.rawValue
        },
        TextPreset(title: "Машинка") { o in
            o.resetStyle(); o.fontIndex = TextFonts.index("Typewriter"); o.fillIndex = TextPalette.black
            o.boxIndex = TextPalette.white; o.boxOpacity = 0.92
        },
        TextPreset(title: "Мел") { o in o.resetStyle(); o.fontIndex = TextFonts.index("Chalkduster"); o.shadow = TextShadow.soft.rawValue },
        TextPreset(title: "Элегант") { o in
            o.resetStyle(); o.fontIndex = TextFonts.index("Didot"); o.letterSpacing = 0.1; o.shadow = TextShadow.soft.rawValue
        },
        TextPreset(title: "Код") { o in
            o.resetStyle(); o.fontIndex = TextFonts.index("Menlo"); o.fillIndex = TextPalette.vivid(120)
            o.boxIndex = TextPalette.black; o.boxOpacity = 0.9
        },
        TextPreset(title: "Милый") { o in
            o.resetStyle(); o.fontIndex = TextFonts.index("Скруглённый"); o.fillIndex = TextPalette.pastel(320)
            o.strokeIndex = TextPalette.white; o.strokeWidth = 0.12
        },
        TextPreset(title: "Крик") { o in
            o.resetStyle(); o.fillIndex = TextPalette.vivid(0); o.strokeIndex = TextPalette.white
            o.strokeWidth = 0.12; o.shadow = TextShadow.hard.rawValue
        },
        TextPreset(title: "Призрак") { o in
            o.resetStyle(); o.fillIndex = TextPalette.pastel(260); o.glowIndex = TextPalette.pastel(260); o.weight = 3
        }
    ]
}

// =====================================================================
// MARK: - Text renderer (одинаковый код для превью и экспорта)
// =====================================================================

enum TextRenderer {
    private static let cache = NSCache<NSString, CIImage>()

    struct Layout {
        let size: CGSize
        let bound: CGSize
        let pad: CGFloat
        let fontSize: CGFloat
    }

    private static func attributed(_ o: TextOverlay, fontSize fs: CGFloat, fill: UIColor, stroke: UIColor? = nil,
                                   strokeWidth: CGFloat = 0, visible: Int? = nil, shadow: NSShadow? = nil) -> NSAttributedString {
        let para = NSMutableParagraphStyle()
        para.alignment = o.alignment == 0 ? .left : (o.alignment == 2 ? .right : .center)

        func attrs(_ color: UIColor) -> [NSAttributedString.Key: Any] {
            var a: [NSAttributedString.Key: Any] = [
                .font: TextFonts.font(o, size: fs),
                .foregroundColor: color,
                .paragraphStyle: para
            ]
            if o.letterSpacing != 0 { a[.kern] = o.letterSpacing * fs }
            if o.italic { a[.obliqueness] = 0.22 }
            if o.underline { a[.underlineStyle] = NSUnderlineStyle.single.rawValue }
            if o.strike { a[.strikethroughStyle] = NSUnderlineStyle.single.rawValue }
            if let st = stroke {
                // отрицательная ширина = заливка + обводка; foreground должен быть цвета обводки
                a[.strokeColor] = st
                a[.strokeWidth] = -(strokeWidth * 200)
            }
            if let sh = shadow { a[.shadow] = sh }
            return a
        }

        let result = NSMutableAttributedString(string: o.text, attributes: attrs(fill))
        if let v = visible {
            let chars = Array(o.text)
            if v < chars.count {
                let prefix = String(chars[0..<max(0, v)])
                let start = (prefix as NSString).length
                let total = (o.text as NSString).length
                if start < total {
                    var hidden = attrs(.clear)
                    if stroke != nil { hidden[.strokeColor] = UIColor.clear }
                    result.setAttributes(hidden, range: NSRange(location: start, length: total - start))
                }
            }
        }
        return result
    }

    static func layout(_ o: TextOverlay, canvas: CGSize) -> Layout {
        let fs = max(8, o.size * canvas.height)
        let attr = attributed(o, fontSize: fs, fill: .white)
        let rect = attr.boundingRect(with: CGSize(width: canvas.width * 0.9, height: .greatestFiniteMagnitude),
                                     options: [.usesLineFragmentOrigin, .usesFontLeading], context: nil)
        let bound = CGSize(width: ceil(rect.width) + 2, height: ceil(rect.height))
        let pad = fs * 0.9
        return Layout(size: CGSize(width: bound.width + pad * 2, height: bound.height + pad * 2),
                      bound: bound, pad: pad, fontSize: fs)
    }

    static func pixelSize(for o: TextOverlay, canvas: CGSize) -> CGSize { layout(o, canvas: canvas).size }

    private static func shadowObject(_ o: TextOverlay, fs: CGFloat) -> NSShadow? {
        guard let style = TextShadow(rawValue: o.shadow), style != .none else { return nil }
        let base = TextPalette.color(o.shadowColorIndex)
        let sh = NSShadow()
        switch style {
        case .none: return nil
        case .soft:
            sh.shadowOffset = CGSize(width: 0, height: fs * 0.05); sh.shadowBlurRadius = fs * 0.12
            sh.shadowColor = base.withAlphaComponent(0.7)
        case .hard:
            sh.shadowOffset = CGSize(width: fs * 0.06, height: fs * 0.06); sh.shadowBlurRadius = 0
            sh.shadowColor = base
        case .far:
            sh.shadowOffset = CGSize(width: fs * 0.12, height: fs * 0.12); sh.shadowBlurRadius = 0
            sh.shadowColor = base
        case .deep:
            sh.shadowOffset = CGSize(width: 0, height: fs * 0.12); sh.shadowBlurRadius = fs * 0.25
            sh.shadowColor = base.withAlphaComponent(0.85)
        case .lift:
            sh.shadowOffset = CGSize(width: fs * 0.03, height: fs * 0.1); sh.shadowBlurRadius = fs * 0.18
            sh.shadowColor = base.withAlphaComponent(0.5)
        case .halo:
            sh.shadowOffset = .zero; sh.shadowBlurRadius = fs * 0.28
            sh.shadowColor = base
        }
        return sh
    }

    static func uiImage(for o: TextOverlay, canvas: CGSize, visible: Int? = nil) -> UIImage {
        let l = layout(o, canvas: canvas)
        let fs = l.fontSize
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = false
        let opts: NSStringDrawingOptions = [.usesLineFragmentOrigin, .usesFontLeading]

        return UIGraphicsImageRenderer(size: l.size, format: format).image { ctx in
            let cg = ctx.cgContext
            let textRect = CGRect(x: l.pad, y: l.pad, width: l.bound.width, height: l.bound.height)

            if o.boxIndex >= 0 {
                let r = textRect.insetBy(dx: -fs * 0.4, dy: -fs * 0.18)
                cg.setFillColor(TextPalette.color(o.boxIndex).withAlphaComponent(CGFloat(o.boxOpacity)).cgColor)
                cg.addPath(UIBezierPath(roundedRect: r, cornerRadius: fs * 0.28).cgPath)
                cg.fillPath()
            }

            if o.glowIndex >= 0 {
                let gc = TextPalette.color(o.glowIndex)
                for k in [CGFloat(0.7), 0.35, 0.12] {
                    let sh = NSShadow()
                    sh.shadowOffset = .zero
                    sh.shadowBlurRadius = fs * k
                    sh.shadowColor = gc
                    attributed(o, fontSize: fs, fill: gc, visible: visible, shadow: sh)
                        .draw(with: textRect, options: opts, context: nil)
                }
            }

            let fillColor = TextPalette.color(o.fillIndex)
            let shadow = shadowObject(o, fs: fs)
            if o.strokeIndex >= 0 {
                let sc = TextPalette.color(o.strokeIndex)
                attributed(o, fontSize: fs, fill: sc, stroke: sc, strokeWidth: o.strokeWidth, visible: visible, shadow: shadow)
                    .draw(with: textRect, options: opts, context: nil)
                attributed(o, fontSize: fs, fill: fillColor, visible: visible)
                    .draw(with: textRect, options: opts, context: nil)
            } else {
                attributed(o, fontSize: fs, fill: fillColor, visible: visible, shadow: shadow)
                    .draw(with: textRect, options: opts, context: nil)
            }
        }
    }

    private static func key(_ o: TextOverlay, canvas: CGSize, visible: Int?) -> NSString {
        "\(o.text)|\(o.size)|\(o.fillIndex)|\(o.strokeIndex)|\(o.strokeWidth)|\(o.shadow)|\(o.shadowColorIndex)|\(o.glowIndex)|\(o.boxIndex)|\(o.boxOpacity)|\(o.fontIndex)|\(o.weight)|\(o.italic)|\(o.underline)|\(o.strike)|\(o.alignment)|\(o.letterSpacing)|\(Int(canvas.width))x\(Int(canvas.height))|\(visible ?? -1)" as NSString
    }

    static func image(for o: TextOverlay, canvas: CGSize, visible: Int? = nil) -> CIImage? {
        let k = key(o, canvas: canvas, visible: visible)
        if let cached = cache.object(forKey: k) { return cached }
        guard let cg = uiImage(for: o, canvas: canvas, visible: visible).cgImage else { return nil }
        let ci = CIImage(cgImage: cg)
        cache.setObject(ci, forKey: k)
        return ci
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
    let transitionID: Int
    let texts: [TextOverlay]

    init(timeRange: CMTimeRange, from: LayerInfo, to: LayerInfo?, transitionID: Int, texts: [TextOverlay]) {
        self.timeRange = timeRange
        self.from = from
        self.to = to
        self.transitionID = transitionID
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
                    let p = CGFloat(min(1, max(0, (time - start) / dur)))
                    output = TransitionRenderer.render(id: instruction.transitionID, from: a, to: b, t: p, rect: rect)
                } else {
                    output = self.frame(for: instruction.from, request: request, rect: rect)
                }

                for o in instruction.texts where time >= o.start && time < o.start + o.duration {
                    output = self.overlayText(o, time: time, canvas: size, over: output)
                }

                EditorCompositor.ciContext.render(output.cropped(to: rect), to: outBuffer, bounds: rect,
                                                  colorSpace: CGColorSpace(name: CGColorSpace.sRGB))
                request.finish(withComposedVideoFrame: outBuffer)
            }
        }
    }


    // MARK: Text overlay (позиция, поворот, анимации появления/исчезания)

    private func rgbSplit(_ img: CIImage, d: CGFloat) -> CIImage {
        func channel(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat) -> CIImage {
            img.applyingFilter("CIColorMatrix", parameters: [
                "inputRVector": CIVector(x: r, y: 0, z: 0, w: 0),
                "inputGVector": CIVector(x: 0, y: g, z: 0, w: 0),
                "inputBVector": CIVector(x: 0, y: 0, z: b, w: 0),
                "inputAVector": CIVector(x: 0, y: 0, z: 0, w: 1),
                "inputBiasVector": CIVector(x: 0, y: 0, z: 0, w: 0)
            ])
        }
        let red = channel(1, 0, 0).transformed(by: CGAffineTransform(translationX: d, y: 0))
        let green = channel(0, 1, 0)
        let blue = channel(0, 0, 1).transformed(by: CGAffineTransform(translationX: -d, y: 0))
        let rg = green.applyingFilter("CIAdditionCompositing", parameters: [kCIInputBackgroundImageKey: red])
        return blue.applyingFilter("CIAdditionCompositing", parameters: [kCIInputBackgroundImageKey: rg])
    }

    private func overlayText(_ o: TextOverlay, time: Double, canvas: CGSize, over base: CIImage) -> CIImage {
        let rel = time - o.start
        let ad = max(0.01, min(o.animDuration, o.duration / 2))
        var st = TextAnimState()
        if let a = TextAnim(rawValue: o.animIn), a != .none {
            a.apply(a: CGFloat(rel / ad), inPhase: true, time: time, to: &st)
        }
        if let a = TextAnim(rawValue: o.animOut), a != .none {
            a.apply(a: CGFloat((o.duration - rel) / ad), inPhase: false, time: time, to: &st)
        }
        guard st.alpha > 0.005, st.wipe > 0.001 else { return base }

        var visible: Int? = nil
        if st.visible < 0.999 {
            let chars = Array(o.text)
            var n = 0
            if st.byWord {
                var ends: [Int] = []
                var inWord = false
                for (idx, ch) in chars.enumerated() {
                    if ch.isWhitespace || ch.isNewline {
                        if inWord { ends.append(idx); inWord = false }
                    } else { inWord = true }
                }
                if inWord { ends.append(chars.count) }
                let k = Int(ceil(st.visible * CGFloat(ends.count)))
                if k > 0 && !ends.isEmpty { n = ends[min(k, ends.count) - 1] }
            } else {
                n = Int(ceil(st.visible * CGFloat(chars.count)))
            }
            guard n > 0 else { return base }
            visible = min(n, chars.count)
        }

        guard var img = TextRenderer.image(for: o, canvas: canvas, visible: visible) else { return base }
        let full = img.extent

        if st.wipe < 0.999 {
            let w = full.width * st.wipe
            let r = st.wipeFromRight
                ? CGRect(x: full.maxX - w, y: full.minY, width: w, height: full.height)
                : CGRect(x: full.minX, y: full.minY, width: w, height: full.height)
            img = img.cropped(to: r)
        }
        let sigma = st.blur * canvas.height
        if sigma > 0.5 {
            img = img.applyingGaussianBlur(sigma: Double(sigma)).cropped(to: full.insetBy(dx: -sigma * 3, dy: -sigma * 3))
        }
        if st.glitch > 0.02 {
            img = rgbSplit(img, d: st.glitch * full.height * 0.12 * CGFloat(sin(time * 90)))
        }

        let cx = (o.position.x + st.dx) * canvas.width
        let cy = canvas.height - (o.position.y + st.dy) * canvas.height
        var t = CGAffineTransform(translationX: -full.width / 2, y: -full.height / 2)
        t = t.concatenating(CGAffineTransform(scaleX: st.scale * st.scaleX, y: st.scale))
        t = t.concatenating(CGAffineTransform(rotationAngle: -(o.rotation + st.rot)))
        t = t.concatenating(CGAffineTransform(translationX: cx, y: cy))
        img = opacity(img.transformed(by: t), st.alpha)
        return img.composited(over: base)
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

    static func make(clips: [VideoClip], audios: [AudioClip]) -> EditorBuild? {
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

        for a in audios {
            guard let src = a.asset.tracks(withMediaType: .audio).first,
                  let tr = comp.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid)
            else { continue }
            let dur = min(a.duration, layout.total.secs - a.start, a.sourceDuration - a.sourceOffset)
            guard dur > 0.05 else { continue }
            try? tr.insertTimeRange(CMTimeRange(start: ticks(a.sourceOffset), duration: floorTicks(dur)),
                                    of: src, at: ticks(a.start))
            let mp = AVMutableAudioMixInputParameters(track: tr)
            mp.setVolume(a.volume, at: .zero)
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
                instructions.append(EditorInstruction(timeRange: range, from: layer(i), to: nil, transitionID: 0, texts: texts))
            case .trans(let i):
                instructions.append(EditorInstruction(timeRange: range, from: layer(i), to: layer(i + 1),
                                                      transitionID: clips[i].transitionID, texts: texts))
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

/// Белые «ручки» по краям выбранного элемента — за них тянем, чтобы обрезать/вернуть.
func addTrimHandles(to v: UIView) {
    for left in [true, false] {
        let h = UIView(frame: CGRect(x: left ? 0 : v.bounds.width - 12, y: 0, width: 12, height: v.bounds.height))
        h.backgroundColor = UIColor(white: 0.97, alpha: 1)
        h.autoresizingMask = left ? [.flexibleHeight, .flexibleRightMargin] : [.flexibleHeight, .flexibleLeftMargin]
        h.isUserInteractionEnabled = false
        let grip = UIView(frame: CGRect(x: 4.5, y: max(2, v.bounds.height / 2 - 7), width: 3, height: 14))
        grip.backgroundColor = UIColor(white: 0.25, alpha: 1)
        grip.layer.cornerRadius = 1.5
        grip.autoresizingMask = [.flexibleTopMargin, .flexibleBottomMargin]
        h.addSubview(grip)
        v.addSubview(h)
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

/// Полоска аудио с волной.
final class AudioBarView: UIView {
    var peaks: [Float] = []
    var offset: Double = 0
    var duration: Double = 1
    var title: String = ""

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
                let bh = max(1.5, CGFloat(peaks[i]) * (h - 14))
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

final class TimelineView: UIView, UIScrollViewDelegate, UIGestureRecognizerDelegate {

    static let minHeight: CGFloat = 112

    private let pps: CGFloat = 64               // точек на секунду
    private let clipTop: CGFloat = 26
    private let clipHeight: CGFloat = 56
    private let laneHeight: CGFloat = 26
    private let laneStep: CGFloat = 30
    private let handleZone: CGFloat = 22
    private let minDur: Double = 0.3

    private let scrollView = UIScrollView()
    private let contentView = UIView()
    private let ruler = RulerView()
    private let playhead = UIView()
    private let knob = UIView()
    private let addTile = UIView()
    private var press: UILongPressGestureRecognizer!

    // callbacks
    var onScrubBegan: (() -> Void)?
    var onScrub: ((Double) -> Void)?
    var onSelectClip: ((Int) -> Void)?
    var onSelectText: ((UUID) -> Void)?
    var onSelectAudio: ((UUID) -> Void)?
    var onDeselectAll: (() -> Void)?
    var onTapTransition: ((Int) -> Void)?
    var onTapAdd: (() -> Void)?
    var onClipTrimmed: ((Int, CMTimeRange) -> Void)?
    var onTextTimeChanged: ((UUID, Double, Double) -> Void)?
    var onAudioTimeChanged: ((UUID, Double, Double, Double) -> Void)?
    var onNeedHeight: ((CGFloat) -> Void)?

    private var clips: [VideoClip] = []
    private var layout = TimelineLayout(clips: [])
    private var texts: [TextOverlay] = []
    private var audios: [AudioClip] = []
    private var selectedClip: Int?
    private var selectedText: UUID?
    private var selectedAudio: UUID?

    private struct Item { let id: UUID; let frame: CGRect; let view: UIView }
    private var clipFrames: [CGRect] = []
    private var clipViews: [ClipTileView] = []
    private var transitionFrames: [CGRect] = []
    private var textItems: [Item] = []
    private var audioItems: [Item] = []
    private(set) var requiredHeight: CGFloat = TimelineView.minHeight

    private var isProgrammatic = false
    private var lastPlayheadTime: Double = 0
    private var lastWidth: CGFloat = 0

    private var totalSeconds: Double { layout.total.secs }
    var isUserScrolling: Bool { scrollView.isTracking || scrollView.isDragging || scrollView.isDecelerating }

    // drag
    private enum DragKind {
        case clipLeft(Int), clipRight(Int)
        case textMove(UUID), textLeft(UUID), textRight(UUID)
        case audioMove(UUID), audioLeft(UUID), audioRight(UUID)
    }
    private struct DragState {
        var kind: DragKind
        var startX: CGFloat
        var view: UIView
        var origFrame: CGRect
        var moved = false
        var start: Double = 0
        var duration: Double = 0
        var offset: Double = 0
        var srcRange: CMTimeRange?
    }
    private var drag: DragState?

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

        // Нулевое «долгое нажатие» = жест перетаскивания, который начинается сразу при касании
        // ручки/полоски; на пустом месте он сразу «проваливается» и лента скроллится как обычно.
        press = UILongPressGestureRecognizer(target: self, action: #selector(handlePress(_:)))
        press.minimumPressDuration = 0
        press.delegate = self
        contentView.addGestureRecognizer(press)
        scrollView.panGestureRecognizer.require(toFail: press)
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

    func reload(clips: [VideoClip], layout: TimelineLayout, texts: [TextOverlay], audios: [AudioClip],
                selectedClip: Int?, selectedText: UUID?, selectedAudio: UUID?) {
        self.clips = clips
        self.layout = layout
        self.texts = texts
        self.audios = audios
        self.selectedClip = selectedClip
        self.selectedText = selectedText
        self.selectedAudio = selectedAudio
        rebuildContent()
        setPlayhead(time: lastPlayheadTime, force: true)
    }

    /// Двигаем красную палку (на самом деле прокручиваем ленту под ней).
    func setPlayhead(time: Double, force: Bool = false) {
        lastPlayheadTime = time
        if !force && isUserScrolling { return }
        isProgrammatic = true
        scrollView.contentOffset = CGPoint(x: CGFloat(max(0, min(time, totalSeconds))) * pps, y: 0)
        isProgrammatic = false
        ruler.offsetX = scrollView.contentOffset.x
        ruler.setNeedsDisplay()
    }

    // MARK: Build

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

        clipFrames = []; clipViews = []; transitionFrames = []; textItems = []; audioItems = []

        // Видео
        for (i, clip) in clips.enumerated() where i < layout.starts.count {
            let x = side + CGFloat(layout.starts[i].secs) * pps + 1
            let w = max(10, CGFloat(layout.durations[i].secs) * pps - 2)
            let tile = ClipTileView(clip: clip, width: w, height: clipHeight, selected: i == selectedClip)
            tile.frame = CGRect(x: x, y: clipTop, width: w, height: clipHeight)
            contentView.addSubview(tile)
            clipFrames.append(tile.frame)
            clipViews.append(tile)
        }

        // Переходы
        if clips.count > 1 {
            for j in 0..<(clips.count - 1) {
                let cx = side + CGFloat(layout.starts[j + 1].secs) * pps
                let f = CGRect(x: cx - 13, y: clipTop + clipHeight / 2 - 13, width: 26, height: 26)
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
            }
        }

        // Дорожки текста и аудио (под видео)
        let tl = assignLanes(texts.map { ($0.start, max($0.start + $0.duration, $0.start + 24 / Double(pps))) })
        let al = assignLanes(audios.map { ($0.start, $0.start + $0.duration) })
        let textBase = clipTop + clipHeight + 8
        let audioBase = textBase + CGFloat(tl.count) * laneStep + (tl.count > 0 ? 4 : 0)

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

        for (k, a) in audios.enumerated() {
            let x = side + CGFloat(a.start) * pps
            let w = max(24, CGFloat(a.duration) * pps)
            let y = audioBase + CGFloat(al.lane[k]) * laneStep
            let bar = AudioBarView(frame: CGRect(x: x, y: y, width: w, height: laneHeight))
            bar.title = a.title
            bar.offset = a.sourceOffset
            bar.duration = a.duration
            bar.peaks = WaveformStore.shared.peaks(for: a.asset) ?? []
            if a.id == selectedAudio {
                bar.layer.borderWidth = 2
                bar.layer.borderColor = UIColor.white.cgColor
                addTrimHandles(to: bar)
            }
            contentView.addSubview(bar)
            audioItems.append(Item(id: a.id, frame: bar.frame, view: bar))
        }

        addTile.frame = CGRect(x: side + CGFloat(totalSeconds) * pps + 10, y: clipTop, width: 56, height: clipHeight)
        contentView.addSubview(addTile)

        let needed = max(TimelineView.minHeight, audioBase + CGFloat(al.count) * laneStep + 8)
        if abs(needed - requiredHeight) > 0.5 {
            requiredHeight = needed
            onNeedHeight?(needed)
        }
    }

    // MARK: Taps

    @objc private func handleTap(_ g: UITapGestureRecognizer) {
        let p = g.location(in: contentView)

        if addTile.frame.contains(p) { onTapAdd?(); return }

        for (j, f) in transitionFrames.enumerated() where f.insetBy(dx: -6, dy: -6).contains(p) {
            onTapTransition?(j)
            return
        }
        for (i, f) in clipFrames.enumerated().reversed() where f.contains(p) {
            if i == selectedClip { onDeselectAll?() } else { onSelectClip?(i) }
            return
        }
        onDeselectAll?()
    }

    // MARK: Drag / trim

    private func hitTarget(at p: CGPoint) -> DragKind? {
        // Ручки выбранного клипа
        if let s = selectedClip, s < clipFrames.count {
            let f = clipFrames[s]
            let hz = min(handleZone, f.width / 3)
            if p.y >= f.minY && p.y <= f.maxY {
                if p.x >= f.minX - 8 && p.x <= f.minX + hz { return .clipLeft(s) }
                if p.x <= f.maxX + 8 && p.x >= f.maxX - hz { return .clipRight(s) }
            }
        }
        for item in textItems.reversed() where item.frame.insetBy(dx: -6, dy: -3).contains(p) {
            if item.id == selectedText {
                let hz = min(handleZone, item.frame.width / 3)
                if p.x <= item.frame.minX + hz { return .textLeft(item.id) }
                if p.x >= item.frame.maxX - hz { return .textRight(item.id) }
            }
            return .textMove(item.id)
        }
        for item in audioItems.reversed() where item.frame.insetBy(dx: -6, dy: -3).contains(p) {
            if item.id == selectedAudio {
                let hz = min(handleZone, item.frame.width / 3)
                if p.x <= item.frame.minX + hz { return .audioLeft(item.id) }
                if p.x >= item.frame.maxX - hz { return .audioRight(item.id) }
            }
            return .audioMove(item.id)
        }
        return nil
    }

    override func gestureRecognizerShouldBegin(_ g: UIGestureRecognizer) -> Bool {
        if g === press {
            guard !isUserScrolling else { return false }
            return hitTarget(at: g.location(in: contentView)) != nil
        }
        return true
    }

    @objc private func handlePress(_ g: UILongPressGestureRecognizer) {
        let x = g.location(in: contentView).x
        switch g.state {
        case .began:
            if let kind = hitTarget(at: g.location(in: contentView)) { beginDrag(kind, x: x) }
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
        switch kind {
        case .clipLeft(let i), .clipRight(let i):
            view = i < clipViews.count ? clipViews[i] : nil
        case .textMove(let id), .textLeft(let id), .textRight(let id):
            view = textItems.first { $0.id == id }?.view
        case .audioMove(let id), .audioLeft(let id), .audioRight(let id):
            view = audioItems.first { $0.id == id }?.view
        }
        guard let v = view else { return }
        drag = DragState(kind: kind, startX: x, view: v, origFrame: v.frame)
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        v.superview?.bringSubviewToFront(v)
    }

    private func updateDrag(x: CGFloat) {
        guard var d = drag else { return }
        if abs(x - d.startX) > 3 { d.moved = true }
        let dx = Double((x - d.startX) / pps)
        let total = totalSeconds
        let side = bounds.width / 2

        switch d.kind {
        case .clipLeft(let i), .clipRight(let i):
            guard i < clips.count else { break }
            let c = clips[i]
            let s = Double(c.speed)
            let s0 = c.sourceRange.start.secs, e0 = c.sourceRange.end.secs
            let assetDur = floor(c.asset.duration.secs * Double(kTimescale)) / Double(kTimescale)
            var ns = s0, ne = e0
            var isLeft = false
            if case .clipLeft = d.kind { isLeft = true }
            if isLeft {
                ns = min(max(0, s0 + dx * s), e0 - minDur * s)
            } else {
                ne = max(min(assetDur, e0 + dx * s), s0 + minDur * s)
            }
            d.srcRange = CMTimeRange(start: ticks(ns), end: ticks(ne))
            let w = max(10, CGFloat((ne - ns) / s) * pps - 2)
            let xx = isLeft ? d.origFrame.maxX - w : d.origFrame.minX
            d.view.frame = CGRect(x: xx, y: d.origFrame.minY, width: w, height: d.origFrame.height)

        case .textMove(let id), .textLeft(let id), .textRight(let id):
            guard let o = texts.first(where: { $0.id == id }) else { break }
            let s0 = o.start, e0 = o.start + o.duration
            var ns = s0, ne = e0
            switch d.kind {
            case .textMove:
                let len = e0 - s0
                ns = min(max(0, s0 + dx), max(0, total - len)); ne = ns + len
            case .textLeft:
                ns = min(max(0, s0 + dx), e0 - minDur)
            default:
                ne = max(min(total, e0 + dx), s0 + minDur)
            }
            d.start = ns; d.duration = ne - ns
            d.view.frame = CGRect(x: side + CGFloat(ns) * pps, y: d.origFrame.minY,
                                  width: max(24, CGFloat(ne - ns) * pps), height: d.origFrame.height)

        case .audioMove(let id), .audioLeft(let id), .audioRight(let id):
            guard let a = audios.first(where: { $0.id == id }) else { break }
            let s0 = a.start, e0 = a.start + a.duration
            var ns = s0, ne = e0, off = a.sourceOffset
            switch d.kind {
            case .audioMove:
                ns = min(max(0, s0 + dx), max(0, total - a.duration)); ne = ns + a.duration
            case .audioLeft:
                // можно тянуть влево только до начала исходного файла
                let minStart = max(0, s0 - a.sourceOffset)
                ns = min(max(minStart, s0 + dx), e0 - minDur)
                off = a.sourceOffset + (ns - s0)
            default:
                let maxEnd = min(total, s0 + (a.sourceDuration - a.sourceOffset))
                ne = max(min(maxEnd, e0 + dx), s0 + minDur)
            }
            d.start = ns; d.duration = ne - ns; d.offset = off
            d.view.frame = CGRect(x: side + CGFloat(ns) * pps, y: d.origFrame.minY,
                                  width: max(24, CGFloat(ne - ns) * pps), height: d.origFrame.height)
            if let bar = d.view as? AudioBarView {
                bar.offset = off
                bar.duration = ne - ns
                bar.setNeedsDisplay()
            }
        }
        drag = d
    }

    private func endDrag(commit: Bool) {
        guard let d = drag else { return }
        drag = nil
        guard commit, d.moved else {
            if commit {
                switch d.kind {
                case .textMove(let id), .textLeft(let id), .textRight(let id): onSelectText?(id)
                case .audioMove(let id), .audioLeft(let id), .audioRight(let id): onSelectAudio?(id)
                default: break
                }
            }
            rebuildContent()
            return
        }
        switch d.kind {
        case .clipLeft(let i), .clipRight(let i):
            if let r = d.srcRange { onClipTrimmed?(i, r) }
        case .textMove(let id), .textLeft(let id), .textRight(let id):
            onTextTimeChanged?(id, d.start, d.duration)
        case .audioMove(let id), .audioLeft(let id), .audioRight(let id):
            onAudioTimeChanged?(id, d.start, d.offset, d.duration)
        }
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
    var on: Bool? = nil            // для переключателей (курсив, подчёркивание…)
    var fit: Bool = false          // картинка вписывается целиком (превью текста)
    var previewKey: String? = nil  // ленивое превью (переходы)
}

typealias PreviewProvider = (String, @escaping () -> Bool, @escaping (UIImage?) -> Void) -> Void

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
        titleLabel.numberOfLines = 2
        titleLabel.adjustsFontSizeToFitWidth = true
        titleLabel.minimumScaleFactor = 0.8
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

    private(set) var currentKey: String?

    override func prepareForReuse() {
        super.prepareForReuse()
        currentKey = nil
        imageView.image = nil
    }

    func configure(_ item: PanelItem, selected: Bool, provider: PreviewProvider?) {
        titleLabel.text = item.title
        currentKey = item.previewKey
        imageView.contentMode = item.fit ? .scaleAspectFit : .scaleAspectFill
        imageView.image = item.image
        let hasImage = item.image != nil
        imageView.isHidden = !(hasImage || item.previewKey != nil)
        iconView.image = item.symbol.flatMap { UIImage(systemName: $0) }
        iconView.isHidden = item.symbol == nil || hasImage
        badgeLabel.text = item.badge
        badgeLabel.isHidden = item.badge == nil
        swatchView.backgroundColor = item.swatch
        swatchView.isHidden = item.swatch == nil
        let hi = selected || item.on == true
        box.layer.borderWidth = hi ? 2.5 : 0
        titleLabel.textColor = hi ? Theme.accent : .lightGray

        if item.image == nil, let key = item.previewKey, let provider = provider {
            provider(key, { [weak self] in self?.currentKey == key }) { [weak self] img in
                guard let self = self, self.currentKey == key else { return }
                self.imageView.image = img
                self.imageView.isHidden = img == nil
                self.iconView.isHidden = img != nil
            }
        }
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

    private let extraButton = UIButton(type: .system)
    private let chipsView = ChipsView()
    private var hasChips = false

    var onClose: (() -> Void)?
    var onExtra: (() -> Void)?
    var onChip: ((Int) -> Void)?
    var onSelect: ((Int) -> Void)?
    var previewProvider: PreviewProvider?
    var onSliderBegan: (() -> Void)?
    var onSliderChanged: ((Float) -> Void)?
    var onSliderEnded: ((Float) -> Void)?

    var preferredHeight: CGFloat { 38 + 106 + (sliderConfig == nil ? 0 : 34) + (hasChips ? 36 : 0) }

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
        layout.itemSize = CGSize(width: 66, height: 96)
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
        extraButton.setTitleColor(Theme.accent, for: .normal)
        extraButton.titleLabel?.font = .systemFont(ofSize: 13, weight: .semibold)
        extraButton.addTarget(self, action: #selector(extraTapped), for: .touchUpInside)
        extraButton.isHidden = true
        header.addSubview(extraButton)
        extraButton.snp.makeConstraints { make in
            make.trailing.equalTo(closeButton.snp.leading).offset(-4)
            make.centerY.equalToSuperview()
        }
        titleLabel.snp.makeConstraints { make in
            make.leading.equalToSuperview().offset(16)
            make.centerY.equalToSuperview()
            make.trailing.lessThanOrEqualTo(extraButton.snp.leading).offset(-8)
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

        let stack = UIStackView(arrangedSubviews: [header, chipsView, sliderRow, collectionView])
        stack.axis = .vertical
        addSubview(stack)
        stack.snp.makeConstraints { $0.edges.equalToSuperview() }
        header.snp.makeConstraints { $0.height.equalTo(38) }
        sliderRow.snp.makeConstraints { $0.height.equalTo(34) }
        chipsView.snp.makeConstraints { $0.height.equalTo(36) }
        chipsView.isHidden = true
        chipsView.onSelect = { [weak self] i in self?.onChip?(i) }
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func configure(title: String, items: [PanelItem], selected: Int?, slider cfg: SliderConfig?,
                   chips: [String]? = nil, selectedChip: Int = 0, extra: String? = nil, keepScroll: Bool = true) {
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
        hasChips = (chips != nil)
        chipsView.isHidden = (chips == nil)
        if let chips = chips { chipsView.configure(titles: chips, selected: selectedChip) }
        extraButton.isHidden = (extra == nil)
        extraButton.setTitle(extra, for: .normal)

        collectionView.reloadData()
        if !keepScroll {
            collectionView.layoutIfNeeded()
            if let s = selected, s < items.count {
                collectionView.scrollToItem(at: IndexPath(item: s, section: 0), at: .centeredHorizontally, animated: false)
            } else {
                collectionView.setContentOffset(.zero, animated: false)
            }
        }
    }

    @objc private func extraTapped() { onExtra?() }
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
        cell.configure(items[indexPath.item], selected: indexPath.item == selectedIndex, provider: previewProvider)
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
// MARK: - Drafts (черновики)
// =====================================================================

struct DraftClip: Codable {
    var id: UUID
    var file: String
    var srcStart: Double
    var srcDuration: Double
    var speed: Float
    var filter: Int
    var filterIntensity: Float
    var transitionID: Int
    var transitionDuration: Double
    var volume: Float
}

struct DraftAudio: Codable {
    var id: UUID
    var file: String
    var title: String
    var start: Double
    var sourceOffset: Double
    var duration: Double
    var volume: Float
}

struct Draft: Codable {
    var id: UUID
    var updated: Date
    var duration: Double
    var clips: [DraftClip]
    var texts: [TextOverlay]
    var audios: [DraftAudio]
}

final class DraftStore {
    static let shared = DraftStore()

    let draftsDir: URL
    let mediaDir: URL

    private init() {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("VideoEditor", isDirectory: true)
        draftsDir = base.appendingPathComponent("Drafts", isDirectory: true)
        mediaDir = base.appendingPathComponent("Media", isDirectory: true)
        try? FileManager.default.createDirectory(at: draftsDir, withIntermediateDirectories: true)
        try? FileManager.default.createDirectory(at: mediaDir, withIntermediateDirectories: true)
    }

    func mediaURL(_ file: String) -> URL { mediaDir.appendingPathComponent(file) }
    private func jsonURL(_ id: UUID) -> URL { draftsDir.appendingPathComponent("\(id.uuidString).json") }
    func coverURL(_ id: UUID) -> URL { draftsDir.appendingPathComponent("\(id.uuidString).jpg") }

    /// Копируем файл в постоянное хранилище (tmp система может очистить). Возвращает имя файла.
    func importMedia(from url: URL, defaultExt: String) -> String? {
        let ext = url.pathExtension.isEmpty ? defaultExt : url.pathExtension
        let name = "\(UUID().uuidString).\(ext)"
        do {
            try FileManager.default.copyItem(at: url, to: mediaURL(name))
            return name
        } catch {
            return nil
        }
    }

    func list() -> [Draft] {
        let files = (try? FileManager.default.contentsOfDirectory(at: draftsDir, includingPropertiesForKeys: nil)) ?? []
        let decoder = JSONDecoder()
        return files.filter { $0.pathExtension == "json" }
            .compactMap { try? decoder.decode(Draft.self, from: Data(contentsOf: $0)) }
            .sorted { $0.updated > $1.updated }
    }

    func save(_ draft: Draft, coverAsset: AVAsset?, coverTime: Double) {
        if let data = try? JSONEncoder().encode(draft) {
            try? data.write(to: jsonURL(draft.id), options: .atomic)
        }
        guard let asset = coverAsset else { return }
        let url = coverURL(draft.id)
        DispatchQueue.global(qos: .utility).async {
            let gen = AVAssetImageGenerator(asset: asset)
            gen.appliesPreferredTrackTransform = true
            gen.maximumSize = CGSize(width: 300, height: 300)
            if let cg = try? gen.copyCGImage(at: CMTime(seconds: coverTime, preferredTimescale: 600), actualTime: nil),
               let data = UIImage(cgImage: cg).jpegData(compressionQuality: 0.7) {
                try? data.write(to: url, options: .atomic)
            }
        }
    }

    func delete(_ id: UUID) {
        try? FileManager.default.removeItem(at: jsonURL(id))
        try? FileManager.default.removeItem(at: coverURL(id))
    }
}

final class DraftCell: UITableViewCell {
    static let reuseId = "DraftCell"
    let cover = UIImageView()
    let titleLabel = UILabel()
    let subLabel = UILabel()

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        backgroundColor = Theme.background
        contentView.backgroundColor = Theme.background
        cover.contentMode = .scaleAspectFill
        cover.clipsToBounds = true
        cover.layer.cornerRadius = 8
        cover.backgroundColor = Theme.surface
        titleLabel.textColor = .white
        titleLabel.font = .systemFont(ofSize: 16, weight: .semibold)
        subLabel.textColor = .lightGray
        subLabel.font = .systemFont(ofSize: 13)
        contentView.addSubview(cover)
        contentView.addSubview(titleLabel)
        contentView.addSubview(subLabel)
        cover.snp.makeConstraints { make in
            make.leading.equalToSuperview().offset(16)
            make.top.bottom.equalToSuperview().inset(10)
            make.size.equalTo(76)
        }
        titleLabel.snp.makeConstraints { make in
            make.leading.equalTo(cover.snp.trailing).offset(14)
            make.trailing.equalToSuperview().inset(16)
            make.bottom.equalTo(contentView.snp.centerY).offset(-2)
        }
        subLabel.snp.makeConstraints { make in
            make.leading.equalTo(titleLabel)
            make.trailing.equalToSuperview().inset(16)
            make.top.equalTo(contentView.snp.centerY).offset(2)
        }
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
}

final class DraftsViewController: UIViewController, UITableViewDataSource, UITableViewDelegate {
    var onOpen: ((Draft) -> Void)?
    var onNew: (() -> Void)?
    var onDeleted: ((UUID) -> Void)?
    var currentDraftID: UUID?

    private let tableView = UITableView()
    private let emptyLabel = UILabel()
    private var drafts: [Draft] = []

    private lazy var formatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "ru_RU")
        f.dateFormat = "d MMM, HH:mm"
        return f
    }()

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = Theme.background

        let bar = UIView()
        view.addSubview(bar)
        bar.snp.makeConstraints { make in
            make.top.equalTo(view.safeAreaLayoutGuide)
            make.leading.trailing.equalToSuperview()
            make.height.equalTo(48)
        }
        let close = UIButton(type: .system)
        close.setTitle("Закрыть", for: .normal)
        close.tintColor = .white
        close.addTarget(self, action: #selector(closeTapped), for: .touchUpInside)
        let title = UILabel()
        title.text = "Черновики"
        title.textColor = .white
        title.font = .systemFont(ofSize: 17, weight: .bold)
        let new = UIButton(type: .system)
        new.setTitle("＋ Новый", for: .normal)
        new.tintColor = Theme.accent
        new.addTarget(self, action: #selector(newTapped), for: .touchUpInside)
        [close, title, new].forEach { bar.addSubview($0) }
        close.snp.makeConstraints { make in make.leading.equalToSuperview().offset(16); make.centerY.equalToSuperview() }
        title.snp.makeConstraints { $0.center.equalToSuperview() }
        new.snp.makeConstraints { make in make.trailing.equalToSuperview().inset(16); make.centerY.equalToSuperview() }

        tableView.backgroundColor = Theme.background
        tableView.separatorColor = UIColor(white: 1, alpha: 0.08)
        tableView.dataSource = self
        tableView.delegate = self
        tableView.register(DraftCell.self, forCellReuseIdentifier: DraftCell.reuseId)
        view.addSubview(tableView)
        tableView.snp.makeConstraints { make in
            make.top.equalTo(bar.snp.bottom)
            make.leading.trailing.bottom.equalToSuperview()
        }

        emptyLabel.text = "Пока нет черновиков.\nНажмите «сохранить» в редакторе —\nи они появятся здесь."
        emptyLabel.numberOfLines = 0
        emptyLabel.textAlignment = .center
        emptyLabel.textColor = .gray
        view.addSubview(emptyLabel)
        emptyLabel.snp.makeConstraints { $0.center.equalToSuperview() }

        reload()
    }

    private func reload() {
        drafts = DraftStore.shared.list()
        emptyLabel.isHidden = !drafts.isEmpty
        tableView.reloadData()
    }

    @objc private func closeTapped() { dismiss(animated: true) }
    @objc private func newTapped() {
        dismiss(animated: true) { [onNew] in onNew?() }
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int { drafts.count }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: DraftCell.reuseId, for: indexPath) as! DraftCell
        let d = drafts[indexPath.row]
        cell.cover.image = UIImage(contentsOfFile: DraftStore.shared.coverURL(d.id).path)
        let isCurrent = d.id == currentDraftID
        cell.titleLabel.text = (isCurrent ? "● " : "") + formatter.string(from: d.updated)
        let total = Int(d.duration)
        cell.subLabel.text = String(format: "%d клип., %d:%02d", d.clips.count, total / 60, total % 60)
            + (d.texts.isEmpty ? "" : " · текст \(d.texts.count)")
            + (d.audios.isEmpty ? "" : " · аудио \(d.audios.count)")
        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        let d = drafts[indexPath.row]
        onOpen?(d)
    }

    func tableView(_ tableView: UITableView, commit editingStyle: UITableViewCell.EditingStyle, forRowAt indexPath: IndexPath) {
        guard editingStyle == .delete else { return }
        let d = drafts[indexPath.row]
        DraftStore.shared.delete(d.id)
        drafts.remove(at: indexPath.row)
        tableView.deleteRows(at: [indexPath], with: .automatic)
        emptyLabel.isHidden = !drafts.isEmpty
        onDeleted?(d.id)
    }
}

// =====================================================================
// MARK: - Waveform (волна аудио на таймлайне)
// =====================================================================

final class WaveformStore {
    static let shared = WaveformStore()
    static let peaksPerSecond = 20

    var onUpdate: (() -> Void)?
    private var cache: [ObjectIdentifier: [Float]] = [:]
    private var pending = Set<ObjectIdentifier>()

    func peaks(for asset: AVAsset) -> [Float]? {
        let key = ObjectIdentifier(asset)
        if let p = cache[key] { return p }
        if !pending.contains(key) {
            pending.insert(key)
            DispatchQueue.global(qos: .utility).async { [weak self] in
                let result = WaveformStore.compute(asset)
                DispatchQueue.main.async {
                    self?.cache[key] = result ?? []
                    self?.pending.remove(key)
                    self?.onUpdate?()
                }
            }
        }
        return nil
    }

    private static func compute(_ asset: AVAsset) -> [Float]? {
        guard let track = asset.tracks(withMediaType: .audio).first,
              let reader = try? AVAssetReader(asset: asset) else { return nil }
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false,
            AVNumberOfChannelsKey: 1,
            AVSampleRateKey: 8000
        ]
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: settings)
        guard reader.canAdd(output) else { return nil }
        reader.add(output)
        guard reader.startReading() else { return nil }

        let window = 8000 / peaksPerSecond
        var peaks: [Float] = []
        var curMax: Int32 = 0
        var count = 0

        while let sb = output.copyNextSampleBuffer() {
            guard let block = CMSampleBufferGetDataBuffer(sb) else { continue }
            let length = CMBlockBufferGetDataLength(block)
            var data = Data(count: length)
            data.withUnsafeMutableBytes { raw in
                if let base = raw.baseAddress {
                    _ = CMBlockBufferCopyDataBytes(block, atOffset: 0, dataLength: length, destination: base)
                }
            }
            data.withUnsafeBytes { (buf: UnsafeRawBufferPointer) in
                let samples = buf.bindMemory(to: Int16.self)
                for s in samples {
                    let v = abs(Int32(s))
                    if v > curMax { curMax = v }
                    count += 1
                    if count >= window {
                        peaks.append(Float(curMax) / 32768)
                        curMax = 0
                        count = 0
                    }
                }
            }
            CMSampleBufferInvalidate(sb)
        }
        guard !peaks.isEmpty else { return nil }
        let top = max(0.05, peaks.max() ?? 1)
        return peaks.map { $0 / top }
    }
}

// =====================================================================
// MARK: - Transition previews (превью перехода на кадрах твоего видео)
// =====================================================================

final class TransitionPreviewStore {
    static let shared = TransitionPreviewStore()

    private let queue = DispatchQueue(label: "transition.preview", qos: .userInitiated)
    private let cache = NSCache<NSString, UIImage>()
    private let lock = NSLock()
    private var fromImg: CIImage?
    private var toImg: CIImage?
    private var generation = 0
    private let side: CGFloat = 112

    func setFrames(from: CGImage?, to: CGImage?) {
        lock.lock()
        generation += 1
        fromImg = from.map { fill(CIImage(cgImage: $0)) }
        toImg = to.map { fill(CIImage(cgImage: $0)) }
        lock.unlock()
        cache.removeAllObjects()
    }

    private func fill(_ img: CIImage) -> CIImage {
        let e = img.extent
        let s = max(side / e.width, side / e.height)
        let w = e.width * s, h = e.height * s
        return img.transformed(by: CGAffineTransform(translationX: -e.minX, y: -e.minY))
            .transformed(by: CGAffineTransform(scaleX: s, y: s))
            .transformed(by: CGAffineTransform(translationX: (side - w) / 2, y: (side - h) / 2))
            .cropped(to: CGRect(x: 0, y: 0, width: side, height: side))
    }

    /// key: "t<id>". Результат приходит в main.
    func image(for key: String, isValid: @escaping () -> Bool, completion: @escaping (UIImage?) -> Void) {
        if let cached = cache.object(forKey: key as NSString) { completion(cached); return }
        lock.lock(); let gen = generation; let f = fromImg; let t = toImg; lock.unlock()
        guard f != nil, t != nil, let id = Int(key.dropFirst()) else { completion(nil); return }

        queue.async { [weak self] in
            guard let self = self, isValid(), let f = f, let t = t, let spec = TransitionCatalog.spec(id) else { return }
            let rect = CGRect(x: 0, y: 0, width: self.side, height: self.side)
            var p: CGFloat = 0.45
            if case .dip = spec.base { p = 0.3 }
            let out = TransitionRenderer.render(id: id, from: f, to: t, t: p, rect: rect)
            var image: UIImage?
            if let cg = EditorCompositor.ciContext.createCGImage(out, from: rect) { image = UIImage(cgImage: cg) }
            DispatchQueue.main.async {
                self.lock.lock(); let same = (gen == self.generation); self.lock.unlock()
                guard same else { return }
                if let image = image { self.cache.setObject(image, forKey: key as NSString) }
                completion(image)
            }
        }
    }
}

// =====================================================================
// MARK: - Text input (современный ввод текста, несколько строк)
// =====================================================================

final class TextInputView: UIView, UITextViewDelegate {
    var onDone: ((String) -> Void)?

    private let dim = UIView()
    private let card = UIView()
    private let textView = UITextView()
    private let placeholder = UILabel()
    private let doneButton = UIButton(type: .system)
    private var cardBottom: Constraint!
    private weak var parent: UIView?

    override init(frame: CGRect) {
        super.init(frame: frame)

        dim.backgroundColor = UIColor.black.withAlphaComponent(0.45)
        dim.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(cancelTapped)))
        addSubview(dim)
        dim.snp.makeConstraints { $0.edges.equalToSuperview() }

        card.backgroundColor = UIColor(white: 0.12, alpha: 1)
        card.layer.cornerRadius = 18
        card.layer.maskedCorners = [.layerMinXMinYCorner, .layerMaxXMinYCorner]
        addSubview(card)
        card.snp.makeConstraints { make in
            make.leading.trailing.equalToSuperview()
            cardBottom = make.bottom.equalToSuperview().constraint
        }

        let cancel = UIButton(type: .system)
        cancel.setTitle("Отмена", for: .normal)
        cancel.tintColor = .lightGray
        cancel.addTarget(self, action: #selector(cancelTapped), for: .touchUpInside)
        let title = UILabel()
        title.text = "Текст"
        title.textColor = .white
        title.font = .systemFont(ofSize: 16, weight: .semibold)
        doneButton.setTitle("Готово", for: .normal)
        doneButton.tintColor = Theme.accent
        doneButton.titleLabel?.font = .systemFont(ofSize: 16, weight: .bold)
        doneButton.addTarget(self, action: #selector(doneTapped), for: .touchUpInside)

        textView.backgroundColor = UIColor(white: 0.2, alpha: 1)
        textView.textColor = .white
        textView.tintColor = Theme.accent
        textView.font = .systemFont(ofSize: 20, weight: .medium)
        textView.layer.cornerRadius = 12
        textView.textContainerInset = UIEdgeInsets(top: 12, left: 10, bottom: 12, right: 10)
        textView.returnKeyType = .default      // Enter = новая строка
        textView.delegate = self

        placeholder.text = "Введите текст…\nEnter — новая строка"
        placeholder.numberOfLines = 2
        placeholder.textColor = UIColor(white: 1, alpha: 0.35)
        placeholder.font = .systemFont(ofSize: 17)
        placeholder.isUserInteractionEnabled = false

        [cancel, title, doneButton, textView].forEach { card.addSubview($0) }
        textView.addSubview(placeholder)
        cancel.snp.makeConstraints { make in make.top.equalToSuperview().offset(6); make.leading.equalToSuperview().offset(12); make.height.equalTo(40) }
        title.snp.makeConstraints { make in make.centerY.equalTo(cancel); make.centerX.equalToSuperview() }
        doneButton.snp.makeConstraints { make in make.centerY.equalTo(cancel); make.trailing.equalToSuperview().inset(12) }
        textView.snp.makeConstraints { make in
            make.top.equalTo(cancel.snp.bottom).offset(6)
            make.leading.trailing.equalToSuperview().inset(14)
            make.height.equalTo(130)
            make.bottom.equalToSuperview().inset(14)
        }
        placeholder.snp.makeConstraints { make in make.top.equalToSuperview().offset(12); make.leading.equalToSuperview().offset(15) }
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func show(in parent: UIView, text: String) {
        self.parent = parent
        frame = parent.bounds
        autoresizingMask = [.flexibleWidth, .flexibleHeight]
        parent.addSubview(self)
        textView.text = text
        updateState()
        NotificationCenter.default.addObserver(self, selector: #selector(keyboardChanged(_:)),
                                               name: UIResponder.keyboardWillChangeFrameNotification, object: nil)
        alpha = 0
        UIView.animate(withDuration: 0.2) { self.alpha = 1 }
        textView.becomeFirstResponder()
        textView.selectedTextRange = textView.textRange(from: textView.endOfDocument, to: textView.endOfDocument)
    }

    private func updateState() {
        placeholder.isHidden = !textView.text.isEmpty
        let empty = textView.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        doneButton.isEnabled = !empty
        doneButton.alpha = empty ? 0.4 : 1
    }

    func textViewDidChange(_ textView: UITextView) { updateState() }

    @objc private func keyboardChanged(_ n: Notification) {
        guard let end = (n.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? NSValue)?.cgRectValue else { return }
        let inSelf = convert(end, from: nil)
        let h = max(0, bounds.maxY - inSelf.minY)
        let d = (n.userInfo?[UIResponder.keyboardAnimationDurationUserInfoKey] as? Double) ?? 0.25
        cardBottom.update(offset: -h)
        UIView.animate(withDuration: d) { self.layoutIfNeeded() }
    }

    @objc private func cancelTapped() { close() }

    @objc private func doneTapped() {
        let text = textView.text.trimmingCharacters(in: .whitespacesAndNewlines)
        close()
        if !text.isEmpty { onDone?(text) }
    }

    private func close() {
        NotificationCenter.default.removeObserver(self)
        textView.resignFirstResponder()
        UIView.animate(withDuration: 0.2, animations: { self.alpha = 0 }) { _ in self.removeFromSuperview() }
    }
}

// =====================================================================
// MARK: - Main ViewController
// =====================================================================

final class ViewController: UIViewController {

    private enum PanelKind { case speed, filter, transition, text, audio }

    private enum TextTab: Int, CaseIterable {
        case text, styles, font, fill, stroke, shadow, shadowColor, glow, box, format, animIn, animOut
        var title: String {
            switch self {
            case .text: return "Текст"
            case .styles: return "Стили"
            case .font: return "Шрифт"
            case .fill: return "Цвет"
            case .stroke: return "Обводка"
            case .shadow: return "Тень"
            case .shadowColor: return "Цвет тени"
            case .glow: return "Свечение"
            case .box: return "Фон"
            case .format: return "Формат"
            case .animIn: return "Появление"
            case .animOut: return "Исчезание"
            }
        }
    }

    private struct Snapshot { var clips: [VideoClip]; var texts: [TextOverlay]; var audios: [AudioClip] }

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
    private let textInput = TextInputView()
    private var toolCollection: UICollectionView!
    private var bottomHeightConstraint: NSLayoutConstraint!
    private var timelineHeightConstraint: NSLayoutConstraint!
    private var playerLayer: AVPlayerLayer!
    private var toastLabel: PaddingLabel?
    private var exportOverlay: ExportOverlay?

    // State
    private var clips: [VideoClip] = []
    private var texts: [TextOverlay] = []
    private var audios: [AudioClip] = []
    private var selectedClipIndex: Int?
    private var selectedTextID: UUID?
    private var selectedAudioID: UUID?
    private var undoStack: [Snapshot] = []
    private var currentDraftID: UUID?

    private var build: EditorBuild?
    private var renderSize = CGSize(width: 1080, height: 1920)
    private var displayTime: Double = 0

    private let player = AVPlayer()
    private var timeObserver: Any?
    private var isSeeking = false
    private var pendingSeek: CMTime?
    private var previewToken = 0

    private var activePanel: PanelKind?
    private var textTab: TextTab = .text
    private var transitionBoundary = 0
    private var transitionCategory: TransitionCategory = .all
    private var previewPairKey: String?
    private var filterPreviews: [FilterType: UIImage] = [:]
    private var filterPreviewClipID: UUID?
    private var textPreviewCache: [String: UIImage] = [:]

    private var exportSession: AVAssetExportSession?
    private var exportTimer: Timer?

    private let speeds: [Float] = [0.25, 0.5, 1, 1.5, 2, 3, 4]
    private let toolBarHeight: CGFloat = 76

    private var totalSeconds: Double { build?.layout.total.secs ?? 0 }
    private var selectedText: TextOverlay? { texts.first { $0.id == selectedTextID } }
    private var selectedAudio: AudioClip? { audios.first { $0.id == selectedAudioID } }

    // MARK: Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        setupLayout()
        setupPlayer()
        setupCallbacks()
        updateUndoButton()
        updateEmptyState()
        reloadTimeline()
        NotificationCenter.default.addObserver(self, selector: #selector(appWillResign),
                                               name: UIApplication.willResignActiveNotification, object: nil)
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
        if presentedViewController == nil { saveDraft(silent: true) }
    }

    deinit {
        if let t = timeObserver { player.removeTimeObserver(t) }
        NotificationCenter.default.removeObserver(self)
        exportTimer?.invalidate()
    }

    @objc private func appWillResign() {
        saveDraft(silent: true)   // авто-сохранение, чтобы прогресс не терялся
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

        let saveButton = UIButton(type: .system)
        saveButton.setImage(UIImage(systemName: "tray.and.arrow.down"), for: .normal)
        saveButton.tintColor = .white
        saveButton.addTarget(self, action: #selector(didTapSaveDraft), for: .touchUpInside)
        topBar.addSubview(saveButton)
        saveButton.snp.makeConstraints { make in
            make.leading.equalToSuperview().offset(8)
            make.centerY.equalToSuperview()
            make.size.equalTo(44)
        }

        let draftsButton = UIButton(type: .system)
        draftsButton.setImage(UIImage(systemName: "folder"), for: .normal)
        draftsButton.tintColor = .white
        draftsButton.addTarget(self, action: #selector(didTapDrafts), for: .touchUpInside)
        topBar.addSubview(draftsButton)
        draftsButton.snp.makeConstraints { make in
            make.leading.equalTo(saveButton.snp.trailing)
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
        tap.delegate = self
        playerContainer.addGestureRecognizer(tap)
        let pan = UIPanGestureRecognizer(target: self, action: #selector(handlePlayerPan(_:)))
        pan.delegate = self
        playerContainer.addGestureRecognizer(pan)
        let pinch = UIPinchGestureRecognizer(target: self, action: #selector(handlePlayerPinch(_:)))
        pinch.delegate = self
        playerContainer.addGestureRecognizer(pinch)
        let rotate = UIRotationGestureRecognizer(target: self, action: #selector(handlePlayerRotate(_:)))
        rotate.delegate = self
        playerContainer.addGestureRecognizer(rotate)

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

        // Timeline (высота растёт вместе с количеством дорожек текста/аудио)
        timelineView.snp.makeConstraints { make in
            make.leading.trailing.equalToSuperview()
            make.bottom.equalTo(bottomContainer.snp.top)
        }
        timelineHeightConstraint = timelineView.heightAnchor.constraint(equalToConstant: TimelineView.minHeight)
        timelineHeightConstraint.isActive = true

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
        timelineView.onSelectText = { [weak self] id in self?.selectText(id) }
        timelineView.onSelectAudio = { [weak self] id in self?.selectAudio(id) }
        timelineView.onDeselectAll = { [weak self] in self?.deselectAll() }
        timelineView.onTapAdd = { [weak self] in self?.didTapAddVideo() }
        timelineView.onTapTransition = { [weak self] j in
            guard let self = self else { return }
            self.transitionBoundary = j
            self.clearSelection()
            self.selectedClipIndex = j
            self.reloadTimeline()
            self.openPanel(.transition)
        }
        timelineView.onClipTrimmed = { [weak self] i, range in self?.commitClipTrim(i, range) }
        timelineView.onTextTimeChanged = { [weak self] id, s, d in self?.commitTextTime(id, start: s, duration: d) }
        timelineView.onAudioTimeChanged = { [weak self] id, s, off, d in self?.commitAudioTime(id, start: s, offset: off, duration: d) }
        timelineView.onNeedHeight = { [weak self] h in self?.setTimelineHeight(h) }

        panel.onClose = { [weak self] in self?.closePanel() }
        panel.onSelect = { [weak self] index in self?.handlePanelSelect(index) }
        panel.onChip = { [weak self] index in
            guard let self = self else { return }
            if self.activePanel == .transition {
                self.transitionCategory = TransitionCategory.allCases[index]
            } else if self.activePanel == .text, let tab = TextTab(rawValue: index) {
                self.textTab = tab
            }
            self.refreshActivePanel(keepScroll: false)
        }
        panel.onExtra = { [weak self] in self?.applyTransitionToAll() }
        panel.onSliderBegan = { [weak self] in self?.sliderBegan() }
        panel.onSliderChanged = { [weak self] v in self?.sliderChanged(v) }
        panel.onSliderEnded = { [weak self] v in self?.sliderEnded(v) }
        panel.previewProvider = { key, isValid, completion in
            TransitionPreviewStore.shared.image(for: key, isValid: isValid, completion: completion)
        }

        ThumbnailStore.shared.onUpdate = { [weak self] in self?.reloadTimelineWhenIdle() }
        WaveformStore.shared.onUpdate = { [weak self] in self?.reloadTimelineWhenIdle() }
    }

    private func setTimelineHeight(_ h: CGFloat) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self, abs(self.timelineHeightConstraint.constant - h) > 0.5 else { return }
            self.timelineHeightConstraint.constant = h
            UIView.animate(withDuration: 0.2) { self.view.layoutIfNeeded() }
        }
    }

    // MARK: Player ticks / seeking

    private func playerTick(_ t: CMTime) {
        let cur = max(0, min(t.secs, totalSeconds))
        timelineView.setPlayhead(time: cur)
        updateTimeLabel(cur)
        updatePlayButton()
        updateTextBox()
    }

    @objc private func playerDidFinish() { updatePlayButton() }

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

    /// Проиграть кусок таймлайна (для предпросмотра перехода / анимации текста).
    private func playRange(from: Double, until: Double) {
        previewToken += 1
        let token = previewToken
        player.seek(to: ticks(max(0, from)), toleranceBefore: .zero, toleranceAfter: .zero) { [weak self] _ in
            DispatchQueue.main.async {
                guard let self = self, token == self.previewToken else { return }
                self.player.play()
                self.updatePlayButton()
                DispatchQueue.main.asyncAfter(deadline: .now() + max(0.2, until - from)) { [weak self] in
                    guard let self = self, token == self.previewToken else { return }
                    self.pausePlayback()
                }
            }
        }
    }

    // MARK: Rebuild engine

    /// Всё, что живёт «под видео», обязано укладываться в длину видео.
    private func clampOverlays(total: Double) {
        guard !clips.isEmpty else { texts = []; audios = []; return }
        texts = texts.map { o in
            var o = o
            o.start = max(0, min(o.start, total - 0.3))
            o.duration = max(0.1, min(o.duration, total - o.start))
            return o
        }
        audios = audios.compactMap { a in
            var a = a
            a.start = max(0, min(a.start, total - 0.3))
            let maxDur = min(total - a.start, a.sourceDuration - a.sourceOffset)
            guard maxDur >= 0.1 else { return nil }
            a.duration = min(a.duration, maxDur)
            return a
        }
        if let id = selectedTextID, !texts.contains(where: { $0.id == id }) { selectedTextID = nil }
        if let id = selectedAudioID, !audios.contains(where: { $0.id == id }) { selectedAudioID = nil }
    }

    /// Полная пересборка (меняется структура: клипы, скорость, переходы, звук).
    private func rebuild(seekTo target: CMTime? = nil) {
        let oldTime = target ?? ticks(displayTime)
        previewToken += 1
        isSeeking = false
        pendingSeek = nil
        if let s = selectedClipIndex, s >= clips.count { selectedClipIndex = nil }
        clampOverlays(total: TimelineLayout(clips: clips).total.secs)
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

        guard let b = EditorBuild.make(clips: clips, audios: audios) else {
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
                            audios: audios,
                            selectedClip: selectedClipIndex,
                            selectedText: selectedTextID,
                            selectedAudio: selectedAudioID)
    }

    /// Миниатюры и волны догружаются в фоне — не трогаем ленту, пока человек её крутит.
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
        undoStack.append(Snapshot(clips: clips, texts: texts, audios: audios))
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
        audios = s.audios
        clearSelection()
        filterPreviewClipID = nil
        rebuild()
        refreshActivePanel()
        updateUndoButton()
    }

    // MARK: Selection

    private func clearSelection() {
        selectedClipIndex = nil
        selectedTextID = nil
        selectedAudioID = nil
    }

    private func currentClipIndex() -> Int? {
        if let i = selectedClipIndex, i < clips.count { return i }
        return build?.layout.index(at: ticks(displayTime))
    }

    private func selectClip(_ index: Int) {
        clearSelection()
        selectedClipIndex = index
        if clips.count > 1 { transitionBoundary = min(index, clips.count - 2) }
        reloadTimeline()
        updateTextBox()
        refreshActivePanel()
    }

    private func selectText(_ id: UUID) {
        guard let o = texts.first(where: { $0.id == id }) else { return }
        clearSelection()
        selectedTextID = id
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

    private func selectAudio(_ id: UUID) {
        guard audios.contains(where: { $0.id == id }) else { return }
        clearSelection()
        selectedAudioID = id
        reloadTimeline()
        updateTextBox()
        refreshActivePanel()
    }

    private func deselectAll() {
        clearSelection()
        reloadTimeline()
        updateTextBox()
        refreshActivePanel()
    }

    private func ensureSelection() {
        if selectedClipIndex == nil, selectedTextID == nil, selectedAudioID == nil, let i = currentClipIndex() {
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
            textTab = .text
            openPanel(.text)
            if texts.isEmpty { presentTextInput(editing: nil) }
        case .audio:
            guard !clips.isEmpty else { showToast("Сначала добавьте видео"); return }
            openPanel(.audio)
        }
    }

    private func openClipPanel(_ kind: PanelKind) {
        guard !clips.isEmpty else { showToast("Сначала добавьте видео"); return }
        ensureSelection()
        if selectedClipIndex == nil, let i = currentClipIndex() { selectedClipIndex = i; reloadTimeline() }
        openPanel(kind)
    }

    private func openTransitionPanel() {
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
        selectedClipIndex = bestJ
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
        first.transitionID = 0

        var second = clip   // у второй половины свой id → свои независимые фильтр/переход/скорость
        second.id = UUID()
        second.sourceRange = CMTimeRange(start: clip.sourceRange.start + srcOffset,
                                         duration: clip.sourceRange.duration - srcOffset)

        clips[i] = first
        clips.insert(second, at: i + 1)
        clearSelection()
        rebuild(seekTo: ticks(t))
        refreshActivePanel()
    }

    private func deleteCurrent() {
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
        guard let i = currentClipIndex() else { showToast("Нечего удалять"); return }
        pushUndo()
        clips.remove(at: i)
        clearSelection()
        filterPreviewClipID = nil
        rebuild()
        refreshActivePanel()
    }

    private func duplicateCurrent() {
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

    // MARK: Timeline commits (перетаскивание / обрезка за края)

    private func commitClipTrim(_ i: Int, _ range: CMTimeRange) {
        guard i < clips.count else { return }
        pushUndo()
        clips[i].sourceRange = range
        clearSelection()
        selectedClipIndex = i
        filterPreviewClipID = nil
        rebuild()
        refreshActivePanel()
    }

    private func commitTextTime(_ id: UUID, start: Double, duration: Double) {
        guard let idx = texts.firstIndex(where: { $0.id == id }) else { return }
        pushUndo()
        texts[idx].start = start
        texts[idx].duration = duration
        clearSelection()
        selectedTextID = id
        textsChanged()
    }

    private func commitAudioTime(_ id: UUID, start: Double, offset: Double, duration: Double) {
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

    // MARK: Bottom panel

    private func openPanel(_ kind: PanelKind) {
        activePanel = kind
        if kind == .filter { updateFilterPreviews() }
        toolCollection.isHidden = true
        panel.isHidden = false
        refreshActivePanel(keepScroll: false)
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

    private func refreshActivePanel(keepScroll: Bool = true) {
        guard let kind = activePanel else { return }

        switch kind {
        case .speed:
            guard let i = currentClipIndex() else { closePanel(); return }
            let items = speeds.map { PanelItem(title: $0 == 1 ? "Обычная" : "\($0)x", badge: String(format: "%gx", Double($0))) }
            let sel = speeds.firstIndex { abs($0 - clips[i].speed) < 0.01 }
            panel.configure(title: "Скорость · клип \(i + 1)", items: items, selected: sel, slider: nil, keepScroll: keepScroll)

        case .filter:
            guard let i = currentClipIndex() else { closePanel(); return }
            let items = FilterType.allCases.map {
                PanelItem(title: $0.displayName, symbol: filterPreviews[$0] == nil ? "camera.filters" : nil, image: filterPreviews[$0])
            }
            let sel = FilterType.allCases.firstIndex(of: clips[i].filter)
            let cfg = SliderConfig(title: "Сила", min: 0, max: 1, value: clips[i].filterIntensity) { "\(Int($0 * 100))%" }
            panel.configure(title: "Фильтр · клип \(i + 1)", items: items, selected: sel,
                            slider: clips[i].filter == .none ? nil : cfg, keepScroll: keepScroll)

        case .transition:
            guard clips.count >= 2 else { closePanel(); return }
            let j = min(transitionBoundary, clips.count - 2)
            transitionBoundary = j
            updateTransitionPreviewFrames()
            let list = TransitionCatalog.list(transitionCategory)
            var items = [PanelItem(title: "Нет", symbol: "xmark"), PanelItem(title: "Случайный", symbol: "shuffle")]
            items += list.map { PanelItem(title: $0.name, symbol: $0.category.symbol, previewKey: "t\($0.id)") }
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
                            extra: curID == 0 ? nil : "Ко всем", keepScroll: keepScroll)

        case .text:
            refreshTextPanel(keepScroll: keepScroll)

        case .audio:
            let muted = (currentClipIndex().map { clips[$0].volume == 0 }) ?? false
            let items = [
                PanelItem(title: "Добавить аудио", symbol: "music.note"),
                PanelItem(title: "Удалить аудио", symbol: "trash"),
                PanelItem(title: muted ? "Включить звук видео" : "Выкл. звук видео",
                          symbol: muted ? "speaker.wave.2.fill" : "speaker.slash.fill")
            ]
            var cfg: SliderConfig?
            if let a = selectedAudio {
                cfg = SliderConfig(title: "Громкость", min: 0, max: 1, value: a.volume) { "\(Int($0 * 100))%" }
            }
            let title = selectedAudio.map { "Аудио · \($0.title)" } ?? "Звук · выберите аудио на дорожке"
            panel.configure(title: title, items: items, selected: nil, slider: cfg, keepScroll: keepScroll)
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

    /// Кадры «конец клипа A» и «начало клипа B» — на них строятся превью всех переходов.
    private func updateTransitionPreviewFrames() {
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

    // MARK: Slider callbacks

    private func sliderBegan() {
        switch activePanel {
        case .filter?, .transition?: pushUndo()
        case .text?: if selectedTextID != nil { pushUndo() }
        case .audio?: if selectedAudioID != nil { pushUndo() }
        default: break
        }
    }

    private func mutateTextLive(_ f: (inout TextOverlay) -> Void) {
        guard let id = selectedTextID, let idx = texts.firstIndex(where: { $0.id == id }) else { return }
        f(&texts[idx])
        refreshVideoComposition()
        updateTextBox()
    }

    private func sliderChanged(_ v: Float) {
        switch activePanel {
        case .filter?:
            guard let i = currentClipIndex() else { return }
            clips[i].filterIntensity = v
            refreshVideoComposition()
        case .transition?:
            guard clips.count >= 2 else { return }
            clips[min(transitionBoundary, clips.count - 2)].transitionDuration = Double(v)
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
            if let id = selectedAudioID, let idx = audios.firstIndex(where: { $0.id == id }) { audios[idx].volume = v }
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
        case .text?:
            reloadTimeline()
            if (textTab == .animIn || textTab == .animOut), let o = selectedText { previewText(o) }
        default:
            reloadTimeline()
        }
    }

    // MARK: Transition helpers

    private func applyTransitionToAll() {
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
        playRange(from: max(0, tStart - 0.8), until: tStart + ov + 0.6)
    }

    // MARK: Text panel

    private func textSample(_ key: String, _ build: (inout TextOverlay) -> Void) -> UIImage {
        if let c = textPreviewCache[key] { return c }
        var o = TextOverlay(text: "Aa", start: 0, duration: 1)
        o.size = 0.3
        build(&o)
        let img = TextRenderer.uiImage(for: o, canvas: CGSize(width: 150, height: 150))
        textPreviewCache[key] = img
        return img
    }

    private func refreshTextPanel(keepScroll: Bool) {
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

    private func mutateSelectedText(_ f: (inout TextOverlay) -> Void) {
        guard let id = selectedTextID, let idx = texts.firstIndex(where: { $0.id == id }) else {
            showToast("Сначала выберите текст на дорожке под видео")
            return
        }
        pushUndo()
        f(&texts[idx])
        textsChanged()
    }

    private func handleTextPanel(_ index: Int) {
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

    private func previewText(_ o: TextOverlay) {
        let d = min(o.animDuration, o.duration / 2)
        if textTab == .animOut {
            let end = o.start + o.duration
            playRange(from: max(0, end - d - 0.8), until: end + 0.15)
        } else {
            playRange(from: max(0, o.start - 0.3), until: o.start + d + 0.9)
        }
    }

    // MARK: Text editing

    private func presentTextInput(editing: TextOverlay?) {
        pausePlayback()
        textInput.onDone = { [weak self] text in self?.commitText(text, editing: editing) }
        textInput.show(in: view, text: editing?.text ?? "")
    }

    private func commitText(_ text: String, editing: TextOverlay?) {
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
            selectedTextID = o.id
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

    private func textGeometry(_ o: TextOverlay) -> (center: CGPoint, size: CGSize) {
        let vr = videoRectInPlayer()
        let px = TextRenderer.pixelSize(for: o, canvas: renderSize)
        let k = vr.height / max(1, renderSize.height)
        return (CGPoint(x: vr.minX + o.position.x * vr.width, y: vr.minY + o.position.y * vr.height),
                CGSize(width: px.width * k, height: px.height * k))
    }

    private func updateTextBox() {
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

    @objc private func handlePlayerTap(_ g: UITapGestureRecognizer) {
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

    @objc private func handlePlayerPinch(_ g: UIPinchGestureRecognizer) {
        guard let id = selectedTextID, let idx = texts.firstIndex(where: { $0.id == id }) else { return }
        if g.state == .began { pushUndo() }
        guard g.state == .changed else { return }
        texts[idx].size = min(0.4, max(0.02, texts[idx].size * g.scale))
        g.scale = 1
        refreshVideoComposition()
        updateTextBox()
    }

    @objc private func handlePlayerRotate(_ g: UIRotationGestureRecognizer) {
        guard let id = selectedTextID, let idx = texts.firstIndex(where: { $0.id == id }) else { return }
        if g.state == .began { pushUndo() }
        guard g.state == .changed else { return }
        texts[idx].rotation += g.rotation
        g.rotation = 0
        refreshVideoComposition()
        updateTextBox()
    }

    // MARK: Audio

    private func handleAudioPanel(_ index: Int) {
        switch index {
        case 0:
            guard totalSeconds > 0.2 else { showToast("Сначала добавьте видео"); return }
            let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.audio], asCopy: true)
            picker.delegate = self
            present(picker, animated: true)
        case 1:
            guard let id = selectedAudioID else { showToast("Выберите аудио на дорожке под видео"); return }
            pushUndo()
            audios.removeAll { $0.id == id }
            selectedAudioID = nil
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

    fileprivate func addAudio(from url: URL) {
        guard totalSeconds > 0.2 else { showToast("Сначала добавьте видео"); return }
        guard let file = DraftStore.shared.importMedia(from: url, defaultExt: "m4a") else {
            showToast("Не удалось загрузить аудио")
            return
        }
        let asset = AVAsset(url: DraftStore.shared.mediaURL(file))
        let srcDur = floor(asset.duration.secs * Double(kTimescale)) / Double(kTimescale)
        guard asset.tracks(withMediaType: .audio).first != nil, srcDur > 0.2 else {
            showToast("В файле нет звука")
            return
        }
        let start = min(displayTime, max(0, totalSeconds - 0.5))
        let dur = min(srcDur, totalSeconds - start)
        let a = AudioClip(asset: asset, file: file, title: url.deletingPathExtension().lastPathComponent,
                          start: start, duration: dur, sourceDuration: srcDur)
        pushUndo()
        audios.append(a)
        clearSelection()
        selectedAudioID = a.id
        rebuild()
        refreshActivePanel()
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
                guard let url = url, error == nil,
                      let file = DraftStore.shared.importMedia(from: url, defaultExt: "mov") else { return }
                let asset = AVAsset(url: DraftStore.shared.mediaURL(file))
                let dur = floorTicks(asset.duration.secs)
                guard dur.secs > 0.1, asset.tracks(withMediaType: .video).first != nil else { return }
                collector.set(idx, VideoClip(asset: asset, file: file, sourceRange: CMTimeRange(start: .zero, duration: dur)))
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

    // MARK: Drafts

    private func makeDraft(id: UUID) -> Draft {
        Draft(id: id, updated: Date(), duration: totalSeconds,
              clips: clips.map {
                  DraftClip(id: $0.id, file: $0.file, srcStart: $0.sourceRange.start.secs,
                            srcDuration: $0.sourceRange.duration.secs, speed: $0.speed, filter: $0.filter.rawValue,
                            filterIntensity: $0.filterIntensity, transitionID: $0.transitionID,
                            transitionDuration: $0.transitionDuration, volume: $0.volume)
              },
              texts: texts,
              audios: audios.map {
                  DraftAudio(id: $0.id, file: $0.file, title: $0.title, start: $0.start,
                             sourceOffset: $0.sourceOffset, duration: $0.duration, volume: $0.volume)
              })
    }

    private func saveDraft(silent: Bool) {
        guard !clips.isEmpty else { return }
        let id = currentDraftID ?? UUID()
        currentDraftID = id
        let first = clips[0]
        DraftStore.shared.save(makeDraft(id: id), coverAsset: first.asset, coverTime: first.sourceRange.start.secs + 0.05)
        if !silent { showToast("Черновик сохранён") }
    }

    @objc private func didTapSaveDraft() {
        guard !clips.isEmpty else { showToast("Добавьте видео, чтобы сохранить черновик"); return }
        saveDraft(silent: false)
    }

    @objc private func didTapDrafts() {
        pausePlayback()
        saveDraft(silent: true)
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

    private func newProject() {
        pausePlayback()
        closePanel()
        clips = []; texts = []; audios = []
        clearSelection()
        undoStack = []
        updateUndoButton()
        currentDraftID = nil
        filterPreviewClipID = nil
        previewPairKey = nil
        rebuild(seekTo: .zero)
    }

    private func loadDraft(_ d: Draft) {
        pausePlayback()
        closePanel()
        var loadedClips: [VideoClip] = []
        for c in d.clips {
            let url = DraftStore.shared.mediaURL(c.file)
            guard FileManager.default.fileExists(atPath: url.path) else { continue }
            var clip = VideoClip(asset: AVAsset(url: url), file: c.file,
                                 sourceRange: CMTimeRange(start: ticks(c.srcStart), duration: ticks(c.srcDuration)))
            clip.id = c.id
            clip.speed = c.speed
            clip.filter = FilterType(rawValue: c.filter) ?? .none
            clip.filterIntensity = c.filterIntensity
            clip.transitionID = c.transitionID
            clip.transitionDuration = c.transitionDuration
            clip.volume = c.volume
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
            loadedAudios.append(clip)
        }
        clips = loadedClips
        texts = d.texts
        audios = loadedAudios
        clearSelection()
        undoStack = []
        updateUndoButton()
        currentDraftID = d.id
        filterPreviewClipID = nil
        previewPairKey = nil
        rebuild(seekTo: .zero)
        if loadedClips.count < d.clips.count { showToast("Часть файлов черновика не найдена") }
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
    private func isTransformGesture(_ g: UIGestureRecognizer) -> Bool {
        g is UIPanGestureRecognizer || g is UIPinchGestureRecognizer || g is UIRotationGestureRecognizer
    }

    func gestureRecognizerShouldBegin(_ g: UIGestureRecognizer) -> Bool {
        if isTransformGesture(g) { return selectedText != nil }
        return true
    }

    func gestureRecognizer(_ g: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
        isTransformGesture(g) && isTransformGesture(other)
    }
}

extension ViewController: PHPickerViewControllerDelegate, UIDocumentPickerDelegate {
    func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
        picker.dismiss(animated: true)
        importVideos(results)
    }

    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        guard let url = urls.first else { return }
        addAudio(from: url)
    }
}

final class ChipsView: UIView {
    private let scroll = UIScrollView()
    private let stack = UIStackView()
    private var buttons: [UIButton] = []
    var onSelect: ((Int) -> Void)?

    override init(frame: CGRect) {
        super.init(frame: frame)
        scroll.showsHorizontalScrollIndicator = false
        addSubview(scroll)
        scroll.snp.makeConstraints { $0.edges.equalToSuperview() }
        stack.axis = .horizontal
        stack.spacing = 8
        scroll.addSubview(stack)
        stack.snp.makeConstraints { make in
            make.edges.equalToSuperview().inset(UIEdgeInsets(top: 3, left: 14, bottom: 3, right: 14))
            make.height.equalToSuperview().offset(-6)
        }
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func configure(titles: [String], selected: Int) {
        if buttons.count != titles.count {
            buttons.forEach { $0.removeFromSuperview() }
            buttons = titles.enumerated().map { (i, t) -> UIButton in
                let b = UIButton(type: .system)
                b.setTitle(t, for: .normal)
                b.titleLabel?.font = .systemFont(ofSize: 12, weight: .semibold)
                b.layer.cornerRadius = 13
                b.contentEdgeInsets = UIEdgeInsets(top: 4, left: 12, bottom: 4, right: 12)
                b.tag = i
                b.addTarget(self, action: #selector(tapped(_:)), for: .touchUpInside)
                stack.addArrangedSubview(b)
                return b
            }
        }
        for (i, b) in buttons.enumerated() {
            let on = i == selected
            b.backgroundColor = on ? Theme.accent : Theme.surface
            b.setTitleColor(on ? .black : .white, for: .normal)
        }
        if selected < buttons.count {
            let f = buttons[selected].frame
            scroll.scrollRectToVisible(f.insetBy(dx: -30, dy: 0), animated: false)
        }
    }

    @objc private func tapped(_ b: UIButton) { onSelect?(b.tag) }
}
