// MARK: - Managers/TransitionCatalog.swift

import UIKit
import CoreImage

// =====================================================================
// MARK: - Transition catalog (Mega Unified CapCut-Grade Engine)
// =====================================================================

enum TransitionCategory: Int, CaseIterable {
    case favorites, all, motion, glitch, zoom, distort, wipe, flip3d, light, fade, mathMatrix, warpAdvanced, velocityMotion, spinWarp, cyberGlitch, lightLeaks, opticalFlow, atmosphericFade
    // Premium-коллекция (добавлена в конец, чтобы не сдвигать rawValue)
    case cinematic, depthCard, glassSoft, editorial, luxeLight
    // Флагманская коллекция на кастомных GPU-ядрах
    case rich

    var title: String {
        switch self {
        case .favorites: return "Избранное"
        case .all: return "Все"
        case .motion: return "Движение"
        case .glitch: return "Помехи"
        case .zoom: return "Приближение"
        case .distort: return "Волны"
        case .wipe: return "Шторки"
        case .flip3d: return "Объём"
        case .light: return "Вспышки"
        case .fade: return "Плавные"
        case .mathMatrix: return "Геометрия"
        case .warpAdvanced: return "Пластика"
        case .velocityMotion: return "Скорость"
        case .spinWarp: return "Вращение"
        case .cyberGlitch: return "Ретро и сбои"
        case .lightLeaks: return "Засветки"
        case .opticalFlow: return "Жидкость"
        case .atmosphericFade: return "Атмосфера"
        case .cinematic: return "Кино"
        case .depthCard: return "Карточки"
        case .glassSoft: return "Стекло и дымка"
        case .editorial: return "Линии"
        case .luxeLight: return "Мягкий свет"
        case .rich: return "Премиум"
        }
    }

    var symbol: String {
        switch self {
        case .favorites: return "heart.fill"
        case .all: return "square.grid.2x2"
        case .motion, .velocityMotion: return "bolt.fill"
        case .glitch, .cyberGlitch: return "ladybug.fill"
        case .zoom: return "viewfinder"
        case .distort, .opticalFlow: return "waveform.path.ecg"
        case .wipe: return "squareshape.split.2x2"
        case .flip3d: return "cube.fill"
        case .light, .lightLeaks: return "sun.max.fill"
        case .fade, .atmosphericFade: return "circle.fill"
        case .mathMatrix: return "function"
        case .warpAdvanced: return "wand.and.stars"
        case .spinWarp: return "arrow.triangle.2.circlepath"
        case .cinematic: return "film"
        case .depthCard: return "square.stack.3d.up"
        case .glassSoft: return "drop.fill"
        case .editorial: return "text.alignleft"
        case .luxeLight: return "moon.stars.fill"
        case .rich: return "sparkles"
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
    case smooth, linear, snap, back, elastic, expoFast, bounce
    // Premium-кривые
    case silk, cinematic, expoInOut, cubicOut
    // Кубические кривые Безье (как cubic-bezier в CSS / CapCut curves)
    case bezierStd, bezierOut, bezierInOut

    var title: String {
        switch self {
        case .smooth: return "Плавно"
        case .linear: return "Ровно"
        case .snap: return "Резко"
        case .back: return "Пружина"
        case .elastic: return "Упруго"
        case .expoFast: return "Ускорение"
        case .bounce: return "Отскок"
        case .silk: return "Шёлк"
        case .cinematic: return "Кино"
        case .expoInOut: return "Волна"
        case .cubicOut: return "Мягкий финал"
        case .bezierStd: return "Классика"
        case .bezierOut: return "Плавный стоп"
        case .bezierInOut: return "Мягкий старт и стоп"
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
        case .expoFast:
            return x == 1 ? 1 : 1 - pow(2, -10 * x)
        case .bounce:
            let n1: CGFloat = 7.5625
            let d1: CGFloat = 2.75
            var v = x
            if v < 1 / d1 { return n1 * v * v }
            else if v < 2 / d1 { v -= 1.5 / d1; return n1 * v * v + 0.75 }
            else if v < 2.5 / d1 { v -= 2.25 / d1; return n1 * v * v + 0.9375 }
            else { v -= 2.625 / d1; return n1 * v * v + 0.984375 }
        case .silk:
            return -(cos(CGFloat.pi * x) - 1) / 2
        case .cinematic:
            return x < 0.5 ? 16 * pow(x, 5) : 1 - pow(-2 * x + 2, 5) / 2
        case .expoInOut:
            if x == 0 { return 0 }
            if x == 1 { return 1 }
            return x < 0.5 ? pow(2, 20 * x - 10) / 2 : (2 - pow(2, -20 * x + 10)) / 2
        case .cubicOut:
            return 1 - pow(1 - x, 3)
        case .bezierStd:
            return cubicBezierEase(0.4, 0.0, 0.2, 1.0, x)
        case .bezierOut:
            return cubicBezierEase(0.22, 1.0, 0.36, 1.0, x)
        case .bezierInOut:
            return cubicBezierEase(0.65, 0.0, 0.35, 1.0, x)
        }
    }
}

/// cubic-bezier(x1, y1, x2, y2): Ньютон + бисекция для обратной функции X(u) = x.
fileprivate func cubicBezierEase(_ x1: CGFloat, _ y1: CGFloat, _ x2: CGFloat, _ y2: CGFloat, _ x: CGFloat) -> CGFloat {
    func coord(_ u: CGFloat, _ a: CGFloat, _ b: CGFloat) -> CGFloat {
        let v = 1 - u
        return 3 * v * v * u * a + 3 * v * u * u * b + u * u * u
    }
    func slope(_ u: CGFloat) -> CGFloat {
        let v = 1 - u
        return 3 * v * v * x1 + 6 * v * u * (x2 - x1) + 3 * u * u * (1 - x2)
    }
    var u = x
    for _ in 0..<8 {
        let err = coord(u, x1, x2) - x
        if abs(err) < 1e-5 { return coord(u, y1, y2) }
        let d = slope(u)
        if abs(d) < 1e-6 { break }
        u = max(0, min(1, u - err / d))
    }
    var lo: CGFloat = 0, hi: CGFloat = 1
    u = x
    for _ in 0..<24 {
        let v = coord(u, x1, x2)
        if abs(v - x) < 1e-5 { break }
        if v < x { lo = u } else { hi = u }
        u = (lo + hi) / 2
    }
    return coord(u, y1, y2)
}

enum Fx: CaseIterable {
    case none, blur, zoomBlur, directionalBlur, rgb, shake, flash, goldFlash, cyberpunk, chromatic, tilt, dualAberration, filmBurn, neonFlare
    // Premium-эффекты (деликатные)
    case softBlur, zoomBlurSoft, bloom, softGlow, vignette, grain, exposure, mono, champagne, pearl, subtleChroma, lensBreath
}

enum MosaicKind { case pixel, hex, crystal }

/// Ядра флагманской коллекции RiCH (каждое = отдельный GPU-шейдер в TransitionRenderer)
enum RichKind: Hashable {
    case flowMorph, chromaBarrel, whipPro, orbitSpin, shardRefract, shockwave, smokeDissolve, tileCascade
    case lenticular, vortexPull, anamorphicFlare, depthParallax, lightLeak, aquaRefract, radialSweep, bokehRack
}

enum Base {
    // Базовые переходы (старые добрые)
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
    
    // Математика и ворпы
    case sineRipple(freq: CGFloat, amp: CGFloat)
    case hyperbolicSaddle(strength: CGFloat)
    case fibonacciSpiral(turns: CGFloat)
    case matrixQuantize(gridSize: CGFloat)
    case liquidWarp(frequency: CGFloat, amplitude: CGFloat)
    case perspectiveMorph(angle: CGFloat)
    case vortexSwirl(turns: CGFloat)
    case glassRefraction(strength: CGFloat)
    
    // Новые современные трендовые кейсы
    case whipPan(dir: Dir, blurStrength: CGFloat)
    case velocityZoom(inward: Bool, ramp: CGFloat)
    case bounceSnap(dir: Dir)
    case crossZoomSpeedRamp
    case spatial3DSpin(axisX: Bool, angle: CGFloat)
    case vortexSwirlZoom(turns: CGFloat)
    case fisheyeLens(strength: CGFloat)
    case warpSlide(dir: Dir, elasticity: CGFloat)
    case rgbAberrationSplit(shift: CGFloat)
    case displacementBlockGlitch(blockSize: CGFloat)
    case vhsScanlineStatic(noiseGrain: CGFloat)
    case cyberStrobeQuantize(bands: CGFloat)
    case filmBurnFlash(warmth: CGFloat)
    case whiteCameraFlash
    case cyberNeonFlare(color: CIColor)
    case lightLeakSweep(angle: CGFloat)
    case liquidRipple(frequency: CGFloat, amplitude: CGFloat)
    case glassRefractionMesh(refractIndex: CGFloat)
    case heatWaveMirage(distortion: CGFloat)
    case blackHolePinch(gravity: CGFloat)

    // Premium-коллекция
    case glide(dir: Dir, parallax: CGFloat, blur: CGFloat)
    case dolly(inward: Bool, depth: CGFloat)
    case blurDissolve(strength: CGFloat)
    case stretchSwap(vertical: Bool, amount: CGFloat)
    case driftRotate(angle: CGFloat, cw: Bool)
    case cardStack(dir: Dir, depth: CGFloat)
    case cardPeel(dir: Dir, depth: CGFloat)
    case featherWipe(angle: CGFloat, soft: CGFloat, blur: CGFloat)
    case glassSweep(angle: CGFloat, band: CGFloat, blur: CGFloat)
    case lineWipe(angle: CGFloat, width: CGFloat)
    case staggerPanels(count: Int, vertical: Bool, reverse: Bool)
    case dipHold(CIColor, hold: CGFloat)

    // RiCH: кастомные GPU-ядра (a, b - параметры ядра)
    case rich(RichKind, a: CGFloat, b: CGFloat)
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
        let neonMagenta = CIColor(red: 1, green: 0.0, blue: 0.7)
        let deepBlack = CIColor(red: 0, green: 0, blue: 0)
        let pureWhite = CIColor(red: 1, green: 1, blue: 1)

        // --- 1. Геометрия ---
        add("Зыбь на воде", .sineRipple(freq: 0.04, amp: 30), .mathMatrix, fx: .zoomBlur, ease: .elastic)
        add("Водоворот", .hyperbolicSaddle(strength: 1.8), .mathMatrix, fx: .chromatic, ease: .smooth)
        add("Золотая спираль", .fibonacciSpiral(turns: 3.5), .mathMatrix, fx: .goldFlash, ease: .back)
        add("Матрица", .matrixQuantize(gridSize: 24), .mathMatrix, fx: .cyberpunk, ease: .snap)

        // --- 2. Пластика ---
        add("Жидкое стекло", .liquidWarp(frequency: 0.05, amplitude: 35), .warpAdvanced, fx: .zoomBlur, ease: .elastic)
        add("Наклон кадра", .perspectiveMorph(angle: 1.2), .warpAdvanced, fx: .dualAberration, ease: .smooth)
        add("Тоннель", .vortexSwirl(turns: 4.0), .warpAdvanced, fx: .chromatic, ease: .back)
        add("Линза", .glassRefraction(strength: 45), .warpAdvanced, fx: .zoomBlur, ease: .snap)

        // --- 3. Движение ---
        let four: [(Dir, String)] = [(.left, "←"), (.right, "→"), (.up, "↑"), (.down, "↓")]
        for (d, a) in four {
            add("Быстй сдвиг \(a)", .push(d), .motion, fx: .zoomBlur, ease: .snap)
            add("Цветной рывок \(a)", .push(d), .motion, fx: .rgb, ease: .snap)
            add("Мягкий толчок \(a)", .push(d), .motion, fx: .blur, ease: .back)
        }
        add("Резкий наезд", .zoom(inward: true, strength: 0.95), .motion, fx: .zoomBlur, ease: .snap)
        add("Катапульта", .zoom(inward: true, strength: 0.8), .motion, fx: .rgb, ease: .elastic)
        add("Ударный фокус", .dissolve, .motion, fx: .zoomBlur, ease: .snap)

        // --- 4. Помехи ---
        add("Цветной сбой", .dissolve, .glitch, fx: .rgb, ease: .snap)
        add("Неоновый распад", .dissolve, .glitch, fx: .cyberpunk, ease: .snap)
        add("Тряска", .dissolve, .glitch, fx: .shake, ease: .snap)

        // --- 5. Приближение ---
        add("Приближение", .zoom(inward: true, strength: 0.6), .zoom, fx: .blur)
        add("Отдаление", .zoom(inward: false, strength: 0.6), .zoom, fx: .blur)
        add("Полный оборот", .spin(cw: true, angle: 2 * .pi), .zoom, fx: .zoomBlur, ease: .back)

        // --- 6. Волны ---
        add("Закручивание", .twirl(cw: true, strength: 4), .distort)
        add("Чёрная дыра", .pinch(sign: 1), .distort, fx: .zoomBlur)
        add("Рыбий глаз", .bump(sign: 1), .distort)

        // --- 7. Шторки ---
        for (deg, a) in [(0, "→"), (180, "←"), (90, "↑"), (270, "↓")] {
            add("Шторка \(a)", .wipe(angle: CGFloat(deg) * .pi / 180, soft: 0.15), .wipe, ease: .smooth)
        }
        add("Распашные двери", .doors(vertical: true, open: true), .wipe, ease: .back)
        add("Жалюзи", .blinds(count: 16, angle: 0, soft: 0.05), .wipe)

        // --- 8. Объём ---
        add("Куб влево", .cube(left: true), .flip3d, fx: .blur, ease: .smooth)
        add("Переворот", .flip(vertical: false), .flip3d, ease: .back)

        // --- 9. Вспышки и плавные ---
        add("Белая вспышка", .dissolve, .light, fx: .flash, ease: .snap)
        add("Золотая вспышка", .dissolve, .light, fx: .goldFlash, ease: .snap)
        add("Растворение", .dissolve, .fade, ease: .smooth)
        add("Через чёрный", .dip(deepBlack), .fade, ease: .smooth)

        // =====================================================================
        // 10. ТРЕНДОВЫЕ КАТЕГОРИИ
        // =====================================================================
        for d in Dir.allCases {
            add("Смазанный пролёт \(d.arrow)", .whipPan(dir: d, blurStrength: 1.0), .velocityMotion, fx: .directionalBlur, ease: .snap)
            add("Цветной пролёт \(d.arrow)", .whipPan(dir: d, blurStrength: 1.2), .velocityMotion, fx: .rgb, ease: .expoFast)
        }
        add("Мощный наезд", .velocityZoom(inward: true, ramp: 1.5), .velocityMotion, fx: .zoomBlur, ease: .expoFast)
        add("Мощный отлёт", .velocityZoom(inward: false, ramp: 1.5), .velocityMotion, fx: .zoomBlur, ease: .expoFast)
        for d in [Dir.left, Dir.right, Dir.up, Dir.down] {
            add("Прыжок \(d.arrow)", .bounceSnap(dir: d), .velocityMotion, fx: .shake, ease: .bounce)
        }
        add("Сквозной наезд", .crossZoomSpeedRamp, .velocityMotion, fx: .zoomBlur, ease: .snap)

        add("Разворот", .spatial3DSpin(axisX: false, angle: .pi), .spinWarp, fx: .blur, ease: .smooth)
        add("Кувырок", .spatial3DSpin(axisX: true, angle: .pi), .spinWarp, fx: .blur, ease: .smooth)
        add("Закрученный наезд", .vortexSwirlZoom(turns: 3.0), .spinWarp, fx: .chromatic, ease: .back)
        add("Широкий угол", .fisheyeLens(strength: 1.8), .spinWarp, fx: .zoomBlur, ease: .smooth)
        for d in Dir.allCases {
            add("Резиновый сдвиг \(d.arrow)", .warpSlide(dir: d, elasticity: 1.4), .spinWarp, fx: .dualAberration, ease: .elastic)
        }

        add("Сдвиг цветов", .rgbAberrationSplit(shift: 0.08), .cyberGlitch, fx: .rgb, ease: .snap)
        add("Квадратные помехи", .displacementBlockGlitch(blockSize: 24), .cyberGlitch, fx: .shake, ease: .snap)
        add("Старая кассета", .vhsScanlineStatic(noiseGrain: 2.5), .cyberGlitch, fx: .shake, ease: .linear)
        add("Стробоскоп", .cyberStrobeQuantize(bands: 16), .cyberGlitch, fx: .cyberpunk, ease: .snap)

        add("Ожог плёнки", .filmBurnFlash(warmth: 1.0), .lightLeaks, fx: .filmBurn, ease: .smooth)
        add("Фотовспышка", .whiteCameraFlash, .lightLeaks, fx: .flash, ease: .snap)
        add("Неоновый блик", .cyberNeonFlare(color: neonCyan), .lightLeaks, fx: .neonFlare, ease: .snap)
        for deg in [0, 90, 180, 270] {
            add("Луч света \(deg)°", .lightLeakSweep(angle: CGFloat(deg) * .pi / 180), .lightLeaks, fx: .goldFlash, ease: .smooth)
        }

        add("Круги на воде", .liquidRipple(frequency: 0.04, amplitude: 35), .opticalFlow, fx: .zoomBlur, ease: .elastic)
        add("Призма", .glassRefractionMesh(refractIndex: 35), .opticalFlow, fx: .dualAberration, ease: .smooth)
        add("Марево", .heatWaveMirage(distortion: 25), .opticalFlow, fx: .blur, ease: .smooth)
        add("Схлопывание", .blackHolePinch(gravity: 1.8), .opticalFlow, fx: .zoomBlur, ease: .expoFast)

        add("Лучевое размытие", .dissolve, .atmosphericFade, fx: .zoomBlur, ease: .smooth)
        add("Туман", .noise(grain: 1.5, cloud: true, soft: 0.3), .atmosphericFade, fx: .blur, ease: .smooth)
        add("Киноплёнка", .noise(grain: 2.5, cloud: false, soft: 0.1), .atmosphericFade, fx: .none, ease: .linear)

        // =====================================================================
        // 11. КИНЕМАТОГРАФИЧНЫЕ И ДЕЛИКАТНЫЕ
        // =====================================================================
        let ivory = CIColor(red: 0.96, green: 0.94, blue: 0.89)
        let charcoal = CIColor(red: 0.09, green: 0.09, blue: 0.10)
        let champagne = CIColor(red: 0.90, green: 0.80, blue: 0.62)
        let midnight = CIColor(red: 0.03, green: 0.05, blue: 0.11)
        let fourDirs: [Dir] = [.left, .right, .up, .down]
        let wipeAngles: [(Int, String)] = [(0, "→"), (180, "←"), (90, "↑"), (270, "↓")]

        // --- Кино ---
        for d in fourDirs {
            add("Скольжение \(d.arrow)", .glide(dir: d, parallax: 0.3, blur: 1.0), .cinematic, fx: .none, ease: .cinematic)
        }
        add("Плавный наезд", .dolly(inward: true, depth: 0.35), .cinematic, fx: .zoomBlurSoft, ease: .cinematic)
        add("Плавный отъезд", .dolly(inward: false, depth: 0.35), .cinematic, fx: .zoomBlurSoft, ease: .cinematic)
        add("Лёгкое приближение", .zoom(inward: true, strength: 0.22), .cinematic, fx: .bloom, ease: .silk)
        add("Лёгкое отдаление", .zoom(inward: false, strength: 0.22), .cinematic, fx: .softBlur, ease: .silk)
        add("Через размытие", .blurDissolve(strength: 1.0), .cinematic, fx: .none, ease: .silk)
        add("Мягкое свечение", .dissolve, .cinematic, fx: .bloom, ease: .silk)
        add("Засветка кадра", .dissolve, .cinematic, fx: .exposure, ease: .silk)
        add("Вытягивание", .stretchSwap(vertical: false, amount: 0.9), .cinematic, fx: .softBlur, ease: .cinematic)
        add("Вытягивание", .stretchSwap(vertical: true, amount: 0.9), .cinematic, fx: .softBlur, ease: .cinematic)
        add("Покачивание", .driftRotate(angle: 0.16, cw: true), .cinematic, fx: .softBlur, ease: .cinematic)
        add("Покачивание", .driftRotate(angle: 0.16, cw: false), .cinematic, fx: .softBlur, ease: .cinematic)

        // --- Карточки ---
        for d in fourDirs {
            add("Стопка кадров \(d.arrow)", .cardStack(dir: d, depth: 0.08), .depthCard, fx: .none, ease: .cinematic)
        }
        for d in fourDirs {
            add("Перелистывание \(d.arrow)", .cardPeel(dir: d, depth: 0.10), .depthCard, fx: .none, ease: .cinematic)
        }
        add("Куб вправо", .cube(left: false), .depthCard, fx: .softBlur, ease: .cinematic)
        add("Вертикальный переворот", .flip(vertical: true), .depthCard, fx: .softBlur, ease: .silk)
        add("Лёгкий вихрь", .twirl(cw: true, strength: 1.4), .depthCard, fx: .softBlur, ease: .silk)
        add("Лёгкий вихрь", .twirl(cw: false, strength: 1.4), .depthCard, fx: .softBlur, ease: .silk)
        add("Объёмная линза", .bump(sign: 0.6), .depthCard, fx: .softBlur, ease: .silk)

        // --- Стекло и дымка ---
        for (deg, a) in wipeAngles {
            add("Матовое стекло \(a)", .glassSweep(angle: CGFloat(deg) * .pi / 180, band: 0.28, blur: 1.0), .glassSoft, fx: .none, ease: .cinematic)
        }
        for (deg, a) in wipeAngles {
            add("Мягкая шторка \(a)", .featherWipe(angle: CGFloat(deg) * .pi / 180, soft: 0.45, blur: 1.0), .glassSoft, fx: .none, ease: .silk)
        }
        add("Мягкая шторка ↗", .featherWipe(angle: .pi / 4, soft: 0.45, blur: 1.0), .glassSoft, fx: .none, ease: .silk)
        add("Мягкая шторка ↙", .featherWipe(angle: .pi * 5 / 4, soft: 0.45, blur: 1.0), .glassSoft, fx: .none, ease: .silk)
        add("Дымка", .noise(grain: 10, cloud: true, soft: 0.5), .glassSoft, fx: .softBlur, ease: .silk)
        add("Лёгкий пар", .noise(grain: 22, cloud: true, soft: 0.65), .glassSoft, fx: .softGlow, ease: .silk)

        // --- Линии ---
        for (deg, a) in wipeAngles {
            add("Тонкая линия \(a)", .lineWipe(angle: CGFloat(deg) * .pi / 180, width: 0.008), .editorial, fx: .none, ease: .cinematic)
        }
        add("Полосы вверх", .staggerPanels(count: 6, vertical: true, reverse: false), .editorial, fx: .none, ease: .linear)
        add("Полосы вниз", .staggerPanels(count: 6, vertical: true, reverse: true), .editorial, fx: .none, ease: .linear)
        add("Полосы вправо", .staggerPanels(count: 5, vertical: false, reverse: false), .editorial, fx: .none, ease: .linear)
        add("Полосы влево", .staggerPanels(count: 5, vertical: false, reverse: true), .editorial, fx: .none, ease: .linear)
        add("Раскрытие круга", .iris(inward: false, scaleX: 1, soft: 0.04, cx: 0.5, cy: 0.5), .editorial, fx: .none, ease: .cinematic)
        add("Сужение круга", .iris(inward: true, scaleX: 1, soft: 0.04, cx: 0.5, cy: 0.5), .editorial, fx: .none, ease: .cinematic)
        add("Раскрытие овала", .iris(inward: false, scaleX: 1.7, soft: 0.06, cx: 0.5, cy: 0.5), .editorial, fx: .none, ease: .cinematic)
        add("Тонкие жалюзи", .blinds(count: 28, angle: 0, soft: 0.1), .editorial, fx: .none, ease: .silk)
        add("Тонкие жалюзи", .blinds(count: 28, angle: .pi / 2, soft: 0.1), .editorial, fx: .none, ease: .silk)
        add("Створки открыть", .doors(vertical: false, open: true), .editorial, fx: .softBlur, ease: .cinematic)
        add("Створки закрыть", .doors(vertical: true, open: false), .editorial, fx: .softBlur, ease: .cinematic)

        // --- Мягкий свет ---
        add("Чёрная пауза", .dipHold(deepBlack, hold: 0.18), .luxeLight, fx: .none, ease: .silk)
        add("Белая пауза", .dipHold(pureWhite, hold: 0.14), .luxeLight, fx: .none, ease: .silk)
        add("Слоновая кость", .dipHold(ivory, hold: 0.16), .luxeLight, fx: .none, ease: .silk)
        add("Графит", .dipHold(charcoal, hold: 0.18), .luxeLight, fx: .none, ease: .silk)
        add("Шампань", .dipHold(champagne, hold: 0.14), .luxeLight, fx: .none, ease: .silk)
        add("Полночь", .dipHold(midnight, hold: 0.18), .luxeLight, fx: .none, ease: .silk)
        add("Тёплое сияние", .dissolve, .luxeLight, fx: .champagne, ease: .silk)
        add("Жемчужный свет", .dissolve, .luxeLight, fx: .pearl, ease: .silk)
        add("Виньетка", .dissolve, .luxeLight, fx: .vignette, ease: .silk)
        add("Зерно плёнки", .dissolve, .luxeLight, fx: .grain, ease: .silk)
        add("Чёрно-белый миг", .dissolve, .luxeLight, fx: .mono, ease: .silk)
        add("Лёгкий сдвиг цвета", .dissolve, .luxeLight, fx: .subtleChroma, ease: .silk)
        add("Мягкий фокус", .dissolve, .luxeLight, fx: .softGlow, ease: .silk)
        add("Дыхание линзы", .dissolve, .luxeLight, fx: .lensBreath, ease: .silk)

        // =====================================================================
        // 12. ПРЕМИУМ-КОЛЛЕКЦИЯ
        // =====================================================================
        add("Плавное перетекание", .rich(.flowMorph, a: 2.2, b: 0.16), .rich, fx: .none, ease: .bezierStd)
        add("Объёмный наезд", .rich(.chromaBarrel, a: 1, b: 0.7), .rich, fx: .none, ease: .bezierStd)
        add("Объёмный отъезд", .rich(.chromaBarrel, a: 0, b: 0.7), .rich, fx: .none, ease: .bezierStd)
        add("Стремительный пролёт", .rich(.whipPro, a: 1, b: 0), .rich, fx: .none, ease: .bezierInOut)
        add("Стремительный пролёт", .rich(.whipPro, a: 0, b: 1), .rich, fx: .none, ease: .bezierInOut)
        add("Орбита", .rich(.orbitSpin, a: 0.9, b: 1), .rich, fx: .none, ease: .bezierStd)
        add("Осколки стекла", .rich(.shardRefract, a: 6, b: 3.7), .rich, fx: .none, ease: .silk)
        add("Ударная волна", .rich(.shockwave, a: 0.09, b: 0.14), .rich, fx: .none, ease: .bezierStd)
        add("Шёлковый дым", .rich(.smokeDissolve, a: 2.4, b: 0.55), .rich, fx: .none, ease: .bezierStd)
        add("Каскад плиток", .rich(.tileCascade, a: 9, b: 0), .rich, fx: .none, ease: .silk)
        add("Рифлёное стекло", .rich(.lenticular, a: 14, b: 0.06), .rich, fx: .none, ease: .silk)
        add("Воронка", .rich(.vortexPull, a: 4.0, b: 0.45), .rich, fx: .none, ease: .bezierStd)
        add("Киноблик", .rich(.anamorphicFlare, a: 0.3, b: 1.5), .rich, fx: .none, ease: .bezierStd)
        add("Глубина кадра", .rich(.depthParallax, a: 0.07, b: 1), .rich, fx: .none, ease: .bezierStd)
        add("Живая засветка", .rich(.lightLeak, a: 1.8, b: 1.0), .rich, fx: .none, ease: .bezierStd)
        add("Водная гладь", .rich(.aquaRefract, a: 6, b: 0.03), .rich, fx: .none, ease: .bezierStd)
        add("Круговой взмах", .rich(.radialSweep, a: 0.08, b: .pi / 2), .rich, fx: .none, ease: .bezierInOut)
        add("Перевод фокуса", .rich(.bokehRack, a: 0.045, b: 2.5), .rich, fx: .none, ease: .bezierStd)

        return list
    }
}
