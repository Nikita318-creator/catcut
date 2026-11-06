// MARK: - Managers/TransitionCatalog.swift

import UIKit
import CoreImage

// =====================================================================
// MARK: - Transition catalog (Премиальный набор современных переходов CapCut-style)
// =====================================================================
//
// База (сдвиг, зум, шторки, глитч, 3D, искажения) + Эффект (Zoom Blur, RGB Split, Flash, Shake)
// + Пружинная физика и резкие кривые скорости (Snap / Back / Elastic).

enum TransitionCategory: Int, CaseIterable {
    case favorites, all, motion, glitch, zoom, distort, wipe, flip3d, light, fade

    var title: String {
        switch self {
        case .favorites: return "♥ Избранное"
        case .all: return "Все"
        case .motion: return "⚡️ Рывки & Движение"
        case .glitch: return "👾 Глитч & Кибер"
        case .zoom: return "🌀 Зум & Наезд"
        case .distort: return "🌊 Искажения"
        case .wipe: return "🪟 Шторки & Сетки"
        case .flip3d: return "🧊 3D Куб"
        case .light: return "✨ Свет & Вспышки"
        case .fade: return "💧 Фейды"
        }
    }

    var symbol: String {
        switch self {
        case .favorites: return "heart.fill"
        case .all: return "square.grid.2x2"
        case .motion: return "bolt.fill"
        case .glitch: return "ladybug.fill"
        case .zoom: return "viewfinder"
        case .distort: return "waveform.path.ecg"
        case .wipe: return "squareshape.split.2x2"
        case .flip3d: return "cube.fill"
        case .light: return "sun.max.fill"
        case .fade: return "circle.fill"
        }
    }
}

enum Dir: CaseIterable {
    case left, right, up, down, upLeft, upRight, downLeft, downRight

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
    case smooth, linear, snap, back, elastic

    var title: String {
        switch self {
        case .smooth: return "плавно"
        case .linear: return "линейно"
        case .snap: return "резко"
        case .back: return "пружина"
        case .elastic: return "упругость"
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
        case .elastic:
            let c4 = (2 * CGFloat.pi) / 3
            return x == 0 ? 0 : x == 1 ? 1 : pow(2, -10 * x) * sin((x * 10 - 0.75) * c4) + 1
        }
    }
}

enum Fx: CaseIterable {
    case none, blur, zoomBlur, rgb, shake, flash, goldFlash, cyberpunk, chromatic, tilt
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

enum TransitionFavorites {
    private static let key = "favoriteTransitions"
    static var ids: [Int] {
        get { UserDefaults.standard.array(forKey: key) as? [Int] ?? [] }
        set { UserDefaults.standard.set(newValue, forKey: key) }
    }
    static func contains(_ id: Int) -> Bool { ids.contains(id) }
    @discardableResult
    static func toggle(_ id: Int) -> Bool {
        var list = ids
        if let i = list.firstIndex(of: id) { list.remove(at: i); ids = list; return false }
        list.append(id); ids = list
        return true
    }
}

enum TransitionCatalog {

    static let all: [TransitionSpec] = build()

    private static let byCategory: [TransitionCategory: [TransitionSpec]] = {
        var d: [TransitionCategory: [TransitionSpec]] = [.all: all]
        for c in TransitionCategory.allCases where c != .all && c != .favorites { d[c] = all.filter { $0.category == c } }
        return d
    }()

    static func spec(_ id: Int) -> TransitionSpec? {
        guard id > 0, id <= all.count else { return nil }
        return all[id - 1]
    }

    static func list(_ category: TransitionCategory) -> [TransitionSpec] {
        if category == .favorites { return TransitionFavorites.ids.compactMap { spec($0) } }
        return byCategory[category] ?? all
    }

    private static func build() -> [TransitionSpec] {
        var list: [TransitionSpec] = []
        func add(_ name: String, _ base: Base, _ cat: TransitionCategory, fx: Fx = .none, ease: Ease = .smooth) {
            list.append(TransitionSpec(id: list.count + 1, name: name, category: cat, base: base, fx: fx, ease: ease))
        }
        let gold = CIColor(red: 1, green: 0.78, blue: 0.3)
        let neonCyan = CIColor(red: 0, green: 0.9, blue: 1)

        // ⚡️ Премиальные рывки и зум-блюры (CapCut/Reels style)
        let four: [(Dir, String)] = [(.left, "←"), (.right, "→"), (.up, "↑"), (.down, "↓")]
        for (d, a) in four {
            add("Турбо-рывок \(a)", .push(d), .motion, fx: .zoomBlur, ease: .snap)
            add("Рывок + RGB \(a)", .push(d), .motion, fx: .rgb, ease: .snap)
            add("Пружинный сдвиг \(a)", .push(d), .motion, fx: .blur, ease: .back)
        }
        add("Кибер-наезд 🚀", .zoom(inward: true, strength: 0.95), .motion, fx: .zoomBlur, ease: .snap)
        add("Катапульта 💥", .zoom(inward: true, strength: 0.8), .motion, fx: .rgb, ease: .elastic)
        add("Ударный расфокус", .dissolve, .motion, fx: .zoomBlur, ease: .snap)

        // 👾 Глитч и Киберпанк
        add("Кибер-глитч RGB", .dissolve, .glitch, fx: .rgb, ease: .snap)
        add("Неоновый распад", .dissolve, .glitch, fx: .cyberpunk, ease: .snap)
        add("Тряска с помехами", .dissolve, .glitch, fx: .shake, ease: .snap)
        add("Глитч-шторки ↔", .wipe(angle: 0, soft: 0.05), .glitch, fx: .rgb, ease: .snap)
        add("Пиксели + RGB", .mosaic(.pixel, strength: 1.5), .glitch, fx: .rgb, ease: .snap)
        add("Вихрь + Глитч", .twirl(cw: true, strength: 5), .glitch, fx: .chromatic, ease: .snap)
        add("Куб + Киберпанк", .cube(left: true), .glitch, fx: .cyberpunk, ease: .snap)
        add("Цифровой сдвиг ←", .push(.left), .glitch, fx: .chromatic, ease: .snap)

        // 🌀 Зум и Вращение
        add("Динамический зум IN", .zoom(inward: true, strength: 0.6), .zoom, fx: .blur)
        add("Динамический зум OUT", .zoom(inward: false, strength: 0.6), .zoom, fx: .blur)
        add("Вращение 360° Turbo", .spin(cw: true, angle: 2 * .pi), .zoom, fx: .zoomBlur, ease: .back)
        add("Вращение 90° ↻", .spin(cw: true, angle: .pi / 2), .zoom)
        add("Вращение 90° ↺", .spin(cw: false, angle: .pi / 2), .zoom)
        add("Зум-наклон 3D", .zoom(inward: true, strength: 0.8), .zoom, fx: .tilt)

        // 🌊 Искажения и Кислота
        add("Вихрь пространственный", .twirl(cw: true, strength: 4), .distort)
        add("Черная дыра (Сжатие)", .pinch(sign: 1), .distort, fx: .zoomBlur)
        add("Выпуклость линзы", .bump(sign: 1), .distort)
        add("Пикселизация плавная", .mosaic(.pixel, strength: 1.2), .distort)
        add("Кристаллизация", .mosaic(.crystal, strength: 1.2), .distort)
        add("Соты кибернетические", .mosaic(.hex, strength: 1.2), .distort, fx: .chromatic)

        // 🪟 Современные шторки и геометрические формы
        for (deg, a) in [(0, "→"), (180, "←"), (90, "↑"), (270, "↓"), (45, "↗"), (135, "↖")] {
            add("Стильная шторка \(a)", .wipe(angle: CGFloat(deg) * .pi / 180, soft: 0.15), .wipe, ease: .smooth)
        }
        add("Элегантные двери ↔", .doors(vertical: true, open: true), .wipe, ease: .back)
        add("Элегантные двери ↕", .doors(vertical: false, open: true), .wipe, ease: .back)
        add("Жалюзи динамические 16", .blinds(count: 16, angle: 0, soft: 0.05), .wipe)
        add("Сетка фокусная 8x8", .grid(cells: 8, diagonal: true, sweep: 1), .wipe)
        add("Ирис-круг динамический", .iris(inward: false, scaleX: 1, soft: 0.1, cx: 0.5, cy: 0.5), .wipe, ease: .back)

        // 🧊 3D Куб и Перевороты
        add("3D Куб влево (Pro)", .cube(left: true), .flip3d, fx: .blur, ease: .smooth)
        add("3D Куб вправо (Pro)", .cube(left: false), .flip3d, fx: .blur, ease: .smooth)
        add("Флип горизонтальный", .flip(vertical: false), .flip3d, ease: .back)
        add("Флип вертикальный", .flip(vertical: true), .flip3d, ease: .back)

        // ✨ Свет, Вспышки и Золото
        add("Белая вспышка 🔥", .dissolve, .light, fx: .flash, ease: .snap)
        add("Золотая вспышка ✨", .dissolve, .light, fx: .goldFlash, ease: .snap)
        add("Неоновая вспышка 💎", .dissolve, .light, fx: .cyberpunk, ease: .snap)
        add("Зум + Вспышка", .zoom(inward: true, strength: 0.6), .light, fx: .flash, ease: .snap)
        add("Рывок + Золото", .push(.right), .light, fx: .goldFlash, ease: .snap)

        // 💧 Фейды и Мягкие переходы
        add("Шелковый фейд", .dissolve, .fade, ease: .smooth)
        add("Кинематографичный ч/ч", .dip(CIColor(red: 0, green: 0, blue: 0)), .fade, ease: .smooth)
        add("Молочный фейд (white)", .dip(CIColor(red: 1, green: 1, blue: 1)), .fade, ease: .smooth)
        add("Золотой фейд престиж", .dip(gold), .fade, ease: .smooth)
        add("Неоновый синий фейд", .dip(neonCyan), .fade, ease: .smooth)
        add("Дымка с размытием", .dissolve, .fade, fx: .blur, ease: .smooth)

        return list
    }
}
