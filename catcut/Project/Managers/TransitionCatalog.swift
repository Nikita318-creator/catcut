// MARK: - Managers/TransitionCatalog.swift

import UIKit
import CoreImage

// =====================================================================
// MARK: - Transition catalog (~110 отобранных переходов)
// =====================================================================
//
// Переход = БАЗА (сдвиг, шторка, ирис, жалюзи, шум, 3D…) + ЭФФЕКТ (размытие, RGB, вспышка…)
// + КРИВАЯ СКОРОСТИ (плавно / линейно / резко / пружина).
// Комбинации и дают тысячи вариантов. ID перехода = номер в каталоге (0 = нет перехода).

enum TransitionCategory: Int, CaseIterable {
    case favorites, all, fade, push, zoom, wipe, shape, flip3d, distort, glitch, light

    var title: String {
        switch self {
        case .favorites: return "♥ Избранное"
        case .all: return "Все"
        case .fade: return "Фейд"
        case .push: return "Сдвиг"
        case .zoom: return "Зум"
        case .wipe: return "Шторки"
        case .shape: return "Фигуры"
        case .flip3d: return "3D"
        case .distort: return "Искажения"
        case .glitch: return "Глитч"
        case .light: return "Свет"
        }
    }

    var symbol: String {
        switch self {
        case .favorites: return "heart.fill"
        case .all: return "square.grid.2x2"
        case .fade: return "drop.halffull"
        case .push: return "arrow.left.and.right"
        case .zoom: return "arrow.triangle.2.circlepath"
        case .wipe: return "forward.end.fill"
        case .shape: return "circle.dashed"
        case .flip3d: return "cube"
        case .distort: return "tornado"
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

/// Избранные переходы (хранятся на устройстве).
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

    /// ~110 отобранных переходов. ВАЖНО: порядок не менять — id (и избранное) привязаны к номеру.
    private static func build() -> [TransitionSpec] {
        var list: [TransitionSpec] = []
        func add(_ name: String, _ base: Base, _ cat: TransitionCategory, fx: Fx = .none, ease: Ease = .smooth) {
            list.append(TransitionSpec(id: list.count + 1, name: name, category: cat, base: base, fx: fx, ease: ease))
        }
        let gold = CIColor(red: 1, green: 0.78, blue: 0.3)

        // Фейд
        add("Плавный фейд", .dissolve, .fade)
        add("Через чёрный", .dip(CIColor(red: 0, green: 0, blue: 0)), .fade)
        add("Через белый", .dip(CIColor(red: 1, green: 1, blue: 1)), .fade)
        add("Золотой фейд", .dip(gold), .fade)
        add("Розовый фейд", .dip(CIColor(red: 1, green: 0.4, blue: 0.7)), .fade)
        add("Синий фейд", .dip(CIColor(red: 0.15, green: 0.35, blue: 0.95)), .fade)
        add("Дымка", .dissolve, .fade, fx: .blur)
        add("Мягкий пульс", .dissolve, .fade, fx: .zoomPulse)
        add("Лёгкий наклон", .dissolve, .fade, fx: .tilt)
        add("Сочный фейд", .dissolve, .fade, fx: .saturate)
        add("Радужный фейд", .dissolve, .fade, fx: .hue)

        // Сдвиг и наезд
        let four: [(Dir, String)] = [(.left, "←"), (.right, "→"), (.up, "↑"), (.down, "↓")]
        for (d, a) in four { add("Сдвиг \(a)", .push(d), .push) }
        for (d, a) in four { add("Рывок \(a)", .push(d), .push, fx: .blur, ease: .snap) }
        for (d, a) in four { add("Пружина \(a)", .push(d), .push, ease: .back) }
        for (d, a) in [(Dir.upLeft, "↖"), (.upRight, "↗"), (.downLeft, "↙"), (.downRight, "↘")] { add("Диагональ \(a)", .push(d), .push) }
        for (d, a) in four { add("Наезд \(a)", .cover(d), .push) }
        add("Уход ←", .reveal(.left), .push)
        add("Уход →", .reveal(.right), .push)

        // Зум и вращение
        add("Приближение", .zoom(inward: true, strength: 0.5), .zoom)
        add("Рывок вперёд", .zoom(inward: true, strength: 0.6), .zoom, fx: .zoomBlur)
        add("Приближение + блюр", .zoom(inward: true, strength: 0.5), .zoom, fx: .blur)
        add("Отдаление", .zoom(inward: false, strength: 0.5), .zoom)
        add("Отдаление + блюр", .zoom(inward: false, strength: 0.5), .zoom, fx: .blur)
        add("Вращение ↻ 90°", .spin(cw: true, angle: .pi / 2), .zoom)
        add("Вращение ↺ 90°", .spin(cw: false, angle: .pi / 2), .zoom)
        add("Вращение ↻ 180°", .spin(cw: true, angle: .pi), .zoom, fx: .blur)
        add("Вращение ↺ 360°", .spin(cw: false, angle: 2 * .pi), .zoom, fx: .zoomBlur)
        add("Зум-наклон", .zoom(inward: true, strength: 0.9), .zoom, fx: .tilt)

        // Шторки, двери, жалюзи
        for (deg, a) in [(0, "→"), (180, "←"), (90, "↑"), (270, "↓"), (45, "↗"), (135, "↖"), (225, "↙"), (315, "↘")] {
            add("Шторка \(a)", .wipe(angle: CGFloat(deg) * .pi / 180, soft: 0.3), .wipe)
        }
        add("Туман →", .wipe(angle: 0, soft: 0.9), .wipe)
        add("Двери ↔ откр.", .doors(vertical: true, open: true), .wipe)
        add("Двери ↔ закр.", .doors(vertical: true, open: false), .wipe)
        add("Двери ↕ откр.", .doors(vertical: false, open: true), .wipe)
        add("Двери ↕ закр.", .doors(vertical: false, open: false), .wipe)
        add("Жалюзи 8", .blinds(count: 8, angle: 0, soft: 0.1), .wipe)
        add("Жалюзи 16 гор.", .blinds(count: 16, angle: .pi / 2, soft: 0.1), .wipe)
        add("Жалюзи ↗ 8", .blinds(count: 8, angle: .pi / 4, soft: 0.3), .wipe)
        add("Полосы 8", .slices(count: 8, vertical: true), .wipe)
        add("Полосы 16 гор.", .slices(count: 16, vertical: false), .wipe)
        add("Сетка 8", .grid(cells: 8, diagonal: false, sweep: 1), .wipe)
        add("Ромбы из центра", .grid(cells: 8, diagonal: true, sweep: 2), .wipe)
        add("Сетка 16", .grid(cells: 16, diagonal: false, sweep: 0), .wipe)

        // Фигуры и шум
        add("Круг из центра", .iris(inward: false, scaleX: 1, soft: 0.4, cx: 0.5, cy: 0.5), .shape)
        add("Круг чётко", .iris(inward: false, scaleX: 1, soft: 0.03, cx: 0.5, cy: 0.5), .shape)
        add("Круг внутрь", .iris(inward: true, scaleX: 1, soft: 0.4, cx: 0.5, cy: 0.5), .shape)
        add("Овал", .iris(inward: false, scaleX: 1.8, soft: 0.4, cx: 0.5, cy: 0.5), .shape)
        add("Столб внутрь", .iris(inward: true, scaleX: 0.55, soft: 0.4, cx: 0.5, cy: 0.5), .shape)
        for (cx, cy, a) in [(CGFloat(0), CGFloat(1), "↖"), (1, 1, "↗"), (0, 0, "↙"), (1, 0, "↘")] {
            add("Круг из угла \(a)", .iris(inward: false, scaleX: 1, soft: 0.4, cx: cx, cy: cy), .shape)
        }
        add("Облака", .noise(grain: 70, cloud: true, soft: 0.35), .shape)
        add("Облака L", .noise(grain: 140, cloud: true, soft: 0.35), .shape)
        add("Зерно", .noise(grain: 4, cloud: false, soft: 0.5), .shape)
        add("Блоки", .noise(grain: 24, cloud: false, soft: 0.03), .shape)
        add("Пыль", .noise(grain: 1, cloud: false, soft: 0.5), .shape)

        // 3D
        add("Переворот ↔", .flip(vertical: false), .flip3d)
        add("Переворот ↕", .flip(vertical: true), .flip3d)
        add("Куб ←", .cube(left: true), .flip3d)
        add("Куб →", .cube(left: false), .flip3d)
        add("Куб + блюр", .cube(left: true), .flip3d, fx: .blur)

        // Искажения
        add("Вихрь ↻", .twirl(cw: true, strength: 3), .distort)
        add("Вихрь ↺ сильный", .twirl(cw: false, strength: 8), .distort)
        add("Выпуклость", .bump(sign: 1), .distort)
        add("Вогнутость", .bump(sign: -1), .distort)
        add("Сжатие", .pinch(sign: 1), .distort)
        add("Растяжение", .pinch(sign: -1), .distort)
        add("Пиксели", .mosaic(.pixel, strength: 1.4), .distort)
        add("Соты", .mosaic(.hex, strength: 1.4), .distort)
        add("Кристаллы", .mosaic(.crystal, strength: 1.4), .distort)
        add("Вихрь + рывок", .twirl(cw: true, strength: 3), .distort, fx: .zoomBlur)

        // Глитч
        add("Глитч RGB", .dissolve, .glitch, fx: .rgb)
        add("Тряска", .dissolve, .glitch, fx: .shake)
        add("Сдвиг ← + RGB", .push(.left), .glitch, fx: .rgb)
        add("Сдвиг → + тряска", .push(.right), .glitch, fx: .shake)
        add("Пиксели + RGB", .mosaic(.pixel, strength: 1.4), .glitch, fx: .rgb)
        add("Вихрь + RGB", .twirl(cw: true, strength: 3), .glitch, fx: .rgb)
        add("Куб + RGB", .cube(left: false), .glitch, fx: .rgb)
        add("Жалюзи + тряска", .blinds(count: 16, angle: 0, soft: 0.1), .glitch, fx: .shake)
        add("Зум + RGB", .zoom(inward: true, strength: 0.5), .glitch, fx: .rgb)

        // Свет
        add("Вспышка", .dissolve, .light, fx: .flash)
        add("Золотая вспышка", .dissolve, .light, fx: .goldFlash)
        add("Зум-вспышка", .zoom(inward: true, strength: 0.5), .light, fx: .flash)
        add("Сдвиг + вспышка", .push(.left), .light, fx: .flash)
        add("Круг + вспышка", .iris(inward: false, scaleX: 1, soft: 0.4, cx: 0.5, cy: 0.5), .light, fx: .flash)
        add("Вихрь + золото", .twirl(cw: true, strength: 3), .light, fx: .goldFlash)
        add("Шторка + золото", .wipe(angle: 0, soft: 0.5), .light, fx: .goldFlash)
        add("Цветной вихрь", .twirl(cw: false, strength: 3), .light, fx: .hue)
        add("Вращение + вспышка", .spin(cw: true, angle: .pi / 2), .light, fx: .flash)
        return list
    }
}
