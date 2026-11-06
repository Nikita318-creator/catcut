// MARK: - Managers/TextCatalog.swift

import UIKit

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
