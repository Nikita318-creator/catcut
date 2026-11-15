// MARK: - Managers/TransitionCatalog.swift

import UIKit
import CoreImage

// =====================================================================
// MARK: - Transition catalog (Mega Unified CapCut-Grade Engine)
// =====================================================================

enum TransitionCategory: Int, CaseIterable {
    case favorites, all, motion, glitch, zoom, distort, wipe, flip3d, light, fade, mathMatrix, warpAdvanced, velocityMotion, spinWarp, cyberGlitch, lightLeaks, opticalFlow, atmosphericFade
    // Премиум-коллекция
    case cinematic, depthCard, glassSoft, editorial, luxeLight
    // Флагманская коллекция на кастомных GPU-ядрах
    case rich
    // Новая современная трендовая категория по идеям Вики
    case new2

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
        case .new2: return "New2"
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
        case .rich, .new2: return "sparkles"
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
    case softBlur, zoomBlurSoft, bloom, softGlow, vignette, grain, exposure, mono, champagne, pearl, subtleChroma, lensBreath
}

enum MosaicKind { case pixel, hex, crystal }

enum RichKind: Hashable {
    case flowMorph, chromaBarrel, whipPro, orbitSpin, shardRefract, shockwave, smokeDissolve, tileCascade
    case lenticular, vortexPull, anamorphicFlare, depthParallax, lightLeak, aquaRefract, radialSweep, bokehRack
    case hyperbolicLens, kineticSlices, organicVortex, directionalSlash, kineticGlitchSlice, radialZoomBlurWhip
}

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
    
    case sineRipple(freq: CGFloat, amp: CGFloat)
    case hyperbolicSaddle(strength: CGFloat)
    case fibonacciSpiral(turns: CGFloat)
    case matrixQuantize(gridSize: CGFloat)
    case liquidWarp(frequency: CGFloat, amplitude: CGFloat)
    case perspectiveMorph(angle: CGFloat)
    case vortexSwirl(turns: CGFloat)
    case glassRefraction(strength: CGFloat)
    
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

    case rich(RichKind, a: CGFloat, b: CGFloat)
    
    // Новые трендовые кейсы для New2
    case tiktokPunchZoom(strength: CGFloat)
    case liquidWarpMorph(frequency: CGFloat, amplitude: CGFloat)
    case spinBounce(turns: CGFloat)
    case cinematicLightSweep(intensity: CGFloat)
    case shakeWithGoldFlash(intensity: CGFloat) // Тряска со вспышками
    case pointBlurStrobe(strength: CGFloat)     // Точечное размытие + покадровая вспышка
    case foggyVibrate(amplitude: CGFloat)       // Вибрирующий с туманом
    case barrelDrift(intensity: CGFloat)
    case multiFrameBlurStagger(count: Int)
    case handheldOrganicDrift(amplitude: CGFloat)
    case rackFocusMotionSlash(strength: CGFloat)
    case lightFlashOverexposure
    case laserLightSweep
    case organicLightLeak
    case neonRgbSplit
    case neonBokehLeak
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

        let neonCyan = CIColor(red: 0, green: 0.9, blue: 1)
        let deepBlack = CIColor(red: 0, green: 0, blue: 0)
        let pureWhite = CIColor(red: 1, green: 1, blue: 1)
        let fourDirs: [Dir] = [.left, .right, .up, .down]

        // --- 1. Геометрия ---
        add("Тоннель", .vortexSwirl(turns: 4.0), .warpAdvanced, fx: .chromatic, ease: .back)

        // --- 2. Пластика ---
        add("Жидкое стекло", .liquidWarp(frequency: 0.05, amplitude: 35), .warpAdvanced, fx: .zoomBlur, ease: .elastic)
        add("Зыбь на воде", .liquidRipple(frequency: 0.04, amplitude: 28), .distort, fx: .zoomBlur, ease: .silk)
        add("Наклон кадра", .perspectiveMorph(angle: 1.2), .warpAdvanced, fx: .dualAberration, ease: .smooth)

        // --- 3. Движение ---
        let four: [(Dir, String)] = [(.left, "←"), (.right, "→"), (.up, "↑"), (.down, "↓")]
        for (d, a) in four {
            add("Быстрый сдвиг \(a)", .push(d), .motion, fx: .zoomBlur, ease: .snap)
            add("Цветной рывок \(a)", .push(d), .motion, fx: .rgb, ease: .snap)
            add("Мягкий толчок \(a)", .push(d), .motion, fx: .blur, ease: .back)
        }
        add("Катапульта", .zoom(inward: true, strength: 0.8), .motion, fx: .rgb, ease: .elastic)

        // --- 4. Помехи ---
        add("Цветной сбой", .dissolve, .glitch, fx: .rgb, ease: .snap)
        add("Тряска", .dissolve, .glitch, fx: .shake, ease: .snap)

        // --- 5. Приближение ---
        add("Приближение", .zoom(inward: true, strength: 0.6), .zoom, fx: .blur)
        add("Отдаление", .zoom(inward: false, strength: 0.5), .zoom, fx: .zoomBlurSoft, ease: .silk)
        add("Полный оборот", .spin(cw: true, angle: 2 * .pi), .zoom, fx: .zoomBlur, ease: .back)

        // --- 6. Волны ---
        add("Закручивание", .twirl(cw: true, strength: 4), .distort)
        add("Чёрная дыра", .pinch(sign: 1), .distort, fx: .zoomBlur)

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
        add("Растворение", .dissolve, .fade, ease: .smooth)
        add("Через чёрный", .dip(deepBlack), .fade, ease: .smooth)

        // =====================================================================
        // 10. ТРЕНДОВЫЕ КАТЕГОРИИ
        // =====================================================================
        for d in [Dir.left, Dir.right] {
            add("Смазанный пролёт \(d.arrow)", .whipPan(dir: d, blurStrength: 0.8), .velocityMotion, fx: .directionalBlur, ease: .silk)
            add("Цветной пролёт \(d.arrow)", .whipPan(dir: d, blurStrength: 1.0), .velocityMotion, fx: .rgb, ease: .expoFast)
        }
        add("Мощный наезд", .velocityZoom(inward: true, ramp: 1.5), .velocityMotion, fx: .zoomBlur, ease: .expoFast)
        add("Мощный отлёт", .velocityZoom(inward: false, ramp: 1.5), .velocityMotion, fx: .zoomBlur, ease: .expoFast)
        add("Прыжок →", .bounceSnap(dir: .right), .velocityMotion, fx: .softBlur, ease: .silk)
        add("Сквозной наезд", .crossZoomSpeedRamp, .velocityMotion, fx: .zoomBlur, ease: .snap)

        add("Разворот", .spatial3DSpin(axisX: false, angle: .pi), .spinWarp, fx: .blur, ease: .smooth)
        add("Кувырок", .spatial3DSpin(axisX: true, angle: .pi), .spinWarp, fx: .blur, ease: .smooth)
        add("Закрученный наезд", .vortexSwirlZoom(turns: 3.0), .spinWarp, fx: .chromatic, ease: .back)
        add("Широкий угол", .fisheyeLens(strength: 1.8), .spinWarp, fx: .zoomBlur, ease: .smooth)
        add("Резиновый сдвиг →", .warpSlide(dir: .right, elasticity: 1.2), .spinWarp, fx: .dualAberration, ease: .silk)

        add("Сдвиг цветов", .rgbAberrationSplit(shift: 0.08), .cyberGlitch, fx: .rgb, ease: .snap)
        add("Квадратные помехи", .displacementBlockGlitch(blockSize: 24), .cyberGlitch, fx: .shake, ease: .snap)
        add("Старая кассета", .vhsScanlineStatic(noiseGrain: 2.5), .cyberGlitch, fx: .shake, ease: .linear)

        add("Фотовспышка", .whiteCameraFlash, .lightLeaks, fx: .flash, ease: .snap)
        add("Призма", .glassRefractionMesh(refractIndex: 35), .opticalFlow, fx: .dualAberration, ease: .smooth)
        add("Марево", .heatWaveMirage(distortion: 25), .opticalFlow, fx: .blur, ease: .smooth)

        add("Туман", .noise(grain: 1.5, cloud: true, soft: 0.3), .atmosphericFade, fx: .blur, ease: .smooth)
        add("Киноплёнка", .noise(grain: 2.5, cloud: false, soft: 0.1), .atmosphericFade, fx: .none, ease: .linear)

        // =====================================================================
        // 11. КИНЕМАТОГРАФИЧНЫЕ И ДЕЛИКАТНЫЕ
        // =====================================================================
        for d in fourDirs {
            add("Скольжение \(d.arrow)", .glide(dir: d, parallax: 0.2, blur: 1.5), .cinematic, fx: .softBlur, ease: .silk)
        }
        add("Плавный наезд", .dolly(inward: true, depth: 0.35), .cinematic, fx: .zoomBlurSoft, ease: .cinematic)
        add("Плавный отъезд", .dolly(inward: false, depth: 0.35), .cinematic, fx: .zoomBlurSoft, ease: .cinematic)
        add("Лёгкое приближение", .zoom(inward: true, strength: 0.22), .cinematic, fx: .bloom, ease: .silk)
        add("Лёгкое отдаление", .zoom(inward: false, strength: 0.22), .cinematic, fx: .softBlur, ease: .silk)
        add("Через размытие", .blurDissolve(strength: 1.0), .cinematic, fx: .none, ease: .silk)
        add("Засветка кадра", .dissolve, .cinematic, fx: .exposure, ease: .silk)
        add("Покачивание ↻", .driftRotate(angle: 0.28, cw: true), .cinematic, fx: .softBlur, ease: .cinematic)
        add("Покачивание ↺", .driftRotate(angle: 0.28, cw: false), .cinematic, fx: .softBlur, ease: .cinematic)

        for d in fourDirs {
            add("Стопка кадров \(d.arrow)", .cardStack(dir: d, depth: 0.08), .depthCard, fx: .none, ease: .cinematic)
        }
        for d in [Dir.left, Dir.right] {
            add("Перелистывание \(d.arrow)", .cardPeel(dir: d, depth: 0.08), .depthCard, fx: .softBlur, ease: .cinematic)
        }
        add("Лёгкий вихрь", .twirl(cw: true, strength: 1.4), .depthCard, fx: .softBlur, ease: .silk)
        add("Лёгкий вихрь", .twirl(cw: false, strength: 1.4), .depthCard, fx: .softBlur, ease: .silk)

        add("Дымка", .noise(grain: 10, cloud: true, soft: 0.5), .glassSoft, fx: .softBlur, ease: .silk)
        add("Лёгкий пар", .noise(grain: 22, cloud: true, soft: 0.65), .glassSoft, fx: .softGlow, ease: .silk)

        for (deg, a) in [(0, "→"), (180, "←"), (90, "↑"), (270, "↓")] {
            add("Тонкая линия \(a)", .lineWipe(angle: CGFloat(deg) * .pi / 180, width: 0.008), .editorial, fx: .none, ease: .cinematic)
        }
        add("Раскрытие круга", .iris(inward: false, scaleX: 1, soft: 0.04, cx: 0.5, cy: 0.5), .editorial, fx: .none, ease: .cinematic)
        add("Сужение круга", .iris(inward: true, scaleX: 1, soft: 0.04, cx: 0.5, cy: 0.5), .editorial, fx: .none, ease: .cinematic)
        add("Тонкие жалюзи", .blinds(count: 28, angle: 0, soft: 0.1), .editorial, fx: .none, ease: .silk)
        add("Тонкие жалюзи", .blinds(count: 28, angle: .pi / 2, soft: 0.1), .editorial, fx: .none, ease: .silk)

        add("Чёрная пауза", .dipHold(deepBlack, hold: 0.18), .luxeLight, fx: .blur, ease: .silk)
        add("Белая пауза", .dipHold(pureWhite, hold: 0.14), .luxeLight, fx: .blur, ease: .silk)
        add("Жемчужный свет", .dissolve, .luxeLight, fx: .pearl, ease: .silk)
        add("Виньетка", .dissolve, .luxeLight, fx: .vignette, ease: .silk)
        add("Зерно плёнки", .dissolve, .luxeLight, fx: .grain, ease: .silk)
        add("Чёрно-белый миг", .dissolve, .luxeLight, fx: .mono, ease: .silk)
        add("Лёгкий сдвиг цвета", .dissolve, .luxeLight, fx: .subtleChroma, ease: .silk)
        add("Дыхание линзы", .dissolve, .luxeLight, fx: .lensBreath, ease: .silk)

        // =====================================================================
        // 12. ПРЕМИУМ-КОЛЛЕКЦИЯ
        // =====================================================================
        add("Плавное перетекание", .rich(.flowMorph, a: 2.2, b: 0.16), .rich, fx: .none, ease: .bezierStd)
        add("Объёмный наезд", .rich(.chromaBarrel, a: 1, b: 0.7), .rich, fx: .none, ease: .bezierStd)
        add("Объёмный отъезд", .rich(.chromaBarrel, a: 0, b: 0.7), .rich, fx: .none, ease: .bezierStd)
        add("Орбита", .rich(.orbitSpin, a: 0.9, b: 1), .rich, fx: .none, ease: .bezierStd)
        add("Ударная волна", .rich(.shockwave, a: 0.09, b: 0.14), .rich, fx: .none, ease: .bezierStd)
        add("Киноблик", .rich(.anamorphicFlare, a: 0.4, b: 1.2), .rich, fx: .none, ease: .bezierStd)
        add("Перевод фокуса", .rich(.bokehRack, a: 0.045, b: 2.5), .rich, fx: .none, ease: .bezierStd)

        // =====================================================================
        // 13. NEW2 — СОВРЕМЕННЫЕ ТРЕНДОВЫЕ ПЕРЕХОДЫ ПО ИДЕЯМ ВИКИ
        // =====================================================================
        
        add("Чёрная вспышка-взрыв", .dipHold(deepBlack, hold: 0.04), .new2, fx: .flash, ease: .snap)
        add("Белая вспышка-взрыв", .dipHold(pureWhite, hold: 0.04), .new2, fx: .flash, ease: .snap)
        add("Затухание с размытием", .blurDissolve(strength: 1.8), .new2, fx: .softBlur, ease: .silk)
        
        add("Тикток-удар с зумом", .tiktokPunchZoom(strength: 1.8), .new2, fx: .rgb, ease: .expoFast)
        add("Жидкий морф-перелив", .liquidWarpMorph(frequency: 0.06, amplitude: 40), .new2, fx: .zoomBlurSoft, ease: .silk)
        add("Вращение с отскоком", .spinBounce(turns: 1.0), .new2, fx: .shake, ease: .back)
        add("Кино-пролёт со светом", .cinematicLightSweep(intensity: 1.5), .new2, fx: .bloom, ease: .cinematic)
        
        add("Тряска со вспышками", .shakeWithGoldFlash(intensity: 2.0), .new2, fx: .goldFlash, ease: .snap)
        add("Точечный зум-строб", .pointBlurStrobe(strength: 2.2), .new2, fx: .flash, ease: .expoFast)
        add("Вибрирующий туман", .foggyVibrate(amplitude: 35), .new2, fx: .softBlur, ease: .elastic)
        
        // 4 любимых перехода Вики (Swift-версии с внутренним зумом без рамок):
        add("Объёмный дрифт линзы", .barrelDrift(intensity: 1.5), .new2, fx: .zoomBlurSoft, ease: .silk)
        add("Шёлковый сдвиг слоев", .multiFrameBlurStagger(count: 4), .new2, fx: .none, ease: .bezierStd)
        add("Живая камера", .handheldOrganicDrift(amplitude: 1.2), .new2, fx: .none, ease: .cinematic)
        add("Резкий фокусный пролёт", .rackFocusMotionSlash(strength: 2.0), .new2, fx: .none, ease: .expoFast)
        
        // 4 новых уникальных GPU-ядра на Metal (твои функции):
        add("Гиперболическая линза", .rich(.hyperbolicLens, a: 1.2, b: 0.8), .new2, fx: .none, ease: .bezierStd)
        add("Кинетичные слайсы", .rich(.kineticSlices, a: 1.5, b: 1.0), .new2, fx: .none, ease: .expoFast)
        add("Органический вихрь", .rich(.organicVortex, a: 2.2, b: 0.6), .new2, fx: .none, ease: .silk)
        add("Скоростной слэш", .rich(.directionalSlash, a: 1.8, b: 1.2), .new2, fx: .none, ease: .bezierOut)
        
        // 4 световых тренда:
        add("Световой удар", .lightFlashOverexposure, .new2, fx: .none, ease: .snap)
        add("Лазерный световой меч", .laserLightSweep, .new2, fx: .none, ease: .expoFast)
        add("Утечка тёплого света", .organicLightLeak, .new2, fx: .none, ease: .silk)
        add("Неоновый RGB-сплит", .neonRgbSplit, .new2, fx: .none, ease: .bezierOut)
        add("Неоновое боке-перелив", .neonBokehLeak, .new2, fx: .none, ease: .silk)
        
        return list
    }
}
