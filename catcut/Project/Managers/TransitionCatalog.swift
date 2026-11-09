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
        case .favorites: return "♥ Избранное"
        case .all: return "Все (150+)"
        case .motion: return "⚡️ Рывки & Движение"
        case .glitch: return "👾 Глитч & Кибер"
        case .zoom: return "🌀 Зум & Наезд"
        case .distort: return "🌊 Искажения"
        case .wipe: return "🪟 Шторки & Сетки"
        case .flip3d: return "🧊 3D Куб"
        case .light: return "✨ Свет & Вспышки"
        case .fade: return "💧 Фейды"
        case .mathMatrix: return "📐 Квант & Математика"
        case .warpAdvanced: return "🧬 Меш & Ворп"
        case .velocityMotion: return "⚡️ Whip Pan & Velocity"
        case .spinWarp: return "🌀 Spin & Spatial"
        case .cyberGlitch: return "👾 Glitch & Cyber VFX"
        case .lightLeaks: return "✨ Light Leaks & Film"
        case .opticalFlow: return "🌊 Optical Flow & Liquid"
        case .atmosphericFade: return "🎬 Film Grain & Fades"
        case .cinematic: return "Cinematic"
        case .depthCard: return "Depth & Cards"
        case .glassSoft: return "Glass & Soft Focus"
        case .editorial: return "Editorial Lines"
        case .luxeLight: return "Luxe Dips & Light"
        case .rich: return "RiCH"
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
        case .smooth: return "плавно"
        case .linear: return "линейно"
        case .snap: return "резко"
        case .back: return "пружина"
        case .elastic: return "упругость"
        case .expoFast: return "экспонента"
        case .bounce: return "отскок"
        case .silk: return "шёлк"
        case .cinematic: return "кино"
        case .expoInOut: return "экспо in-out"
        case .cubicOut: return "мягкий выход"
        case .bezierStd: return "безье 0.4/0/0.2/1"
        case .bezierOut: return "безье мягкий выход"
        case .bezierInOut: return "безье in-out"
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

        // --- 1. Старая база: Квант & Математика ---
        add("Квантовая синусоида 🌊", .sineRipple(freq: 0.04, amp: 30), .mathMatrix, fx: .zoomBlur, ease: .elastic)
        add("Гиперболический вихрь 🌀", .hyperbolicSaddle(strength: 1.8), .mathMatrix, fx: .chromatic, ease: .smooth)
        add("Спираль Фибоначчи ✨", .fibonacciSpiral(turns: 3.5), .mathMatrix, fx: .goldFlash, ease: .back)
        add("Матричный квантовый сдвиг 🔢", .matrixQuantize(gridSize: 24), .mathMatrix, fx: .cyberpunk, ease: .snap)

        // --- 2. Старая база: Меш & Ворп ---
        add("Жидкостный ворп 🌊", .liquidWarp(frequency: 0.05, amplitude: 35), .warpAdvanced, fx: .zoomBlur, ease: .elastic)
        add("Перспективный морфинг 📐", .perspectiveMorph(angle: 1.2), .warpAdvanced, fx: .dualAberration, ease: .smooth)
        add("Вихревой тоннель 🌀", .vortexSwirl(turns: 4.0), .warpAdvanced, fx: .chromatic, ease: .back)
        add("Стеклянная преломляющая линза 🔍", .glassRefraction(strength: 45), .warpAdvanced, fx: .zoomBlur, ease: .snap)

        // --- 3. Старая база: Рывки & Движение ---
        let four: [(Dir, String)] = [(.left, "←"), (.right, "→"), (.up, "↑"), (.down, "↓")]
        for (d, a) in four {
            add("Турбо-рывок \(a)", .push(d), .motion, fx: .zoomBlur, ease: .snap)
            add("Рывок + RGB \(a)", .push(d), .motion, fx: .rgb, ease: .snap)
            add("Пружинный сдвиг \(a)", .push(d), .motion, fx: .blur, ease: .back)
        }
        add("Кибер-наезд 🚀", .zoom(inward: true, strength: 0.95), .motion, fx: .zoomBlur, ease: .snap)
        add("Катапульта 💥", .zoom(inward: true, strength: 0.8), .motion, fx: .rgb, ease: .elastic)
        add("Ударный расфокус", .dissolve, .motion, fx: .zoomBlur, ease: .snap)

        // --- 4. Старая база: Глитч ---
        add("Кибер-глитч RGB", .dissolve, .glitch, fx: .rgb, ease: .snap)
        add("Неоновый распад", .dissolve, .glitch, fx: .cyberpunk, ease: .snap)
        add("Тряска с помехами", .dissolve, .glitch, fx: .shake, ease: .snap)

        // --- 5. Старая база: Зум & Вращение ---
        add("Динамический зум IN", .zoom(inward: true, strength: 0.6), .zoom, fx: .blur)
        add("Динамический зум OUT", .zoom(inward: false, strength: 0.6), .zoom, fx: .blur)
        add("Вращение 360° Turbo", .spin(cw: true, angle: 2 * .pi), .zoom, fx: .zoomBlur, ease: .back)

        // --- 6. Старая база: Искажения ---
        add("Вихрь пространственный", .twirl(cw: true, strength: 4), .distort)
        add("Черная дыра (Сжатие)", .pinch(sign: 1), .distort, fx: .zoomBlur)
        add("Выпуклость линзы", .bump(sign: 1), .distort)

        // --- 7. Старая база: Шторки & Геометрия ---
        for (deg, a) in [(0, "→"), (180, "←"), (90, "↑"), (270, "↓")] {
            add("Стильная шторка \(a)", .wipe(angle: CGFloat(deg) * .pi / 180, soft: 0.15), .wipe, ease: .smooth)
        }
        add("Элегантные двери ↔", .doors(vertical: true, open: true), .wipe, ease: .back)
        add("Жалюзи динамические 16", .blinds(count: 16, angle: 0, soft: 0.05), .wipe)

        // --- 8. Старая база: 3D Куб ---
        add("3D Куб влево (Pro)", .cube(left: true), .flip3d, fx: .blur, ease: .smooth)
        add("Флип горизонтальный", .flip(vertical: false), .flip3d, ease: .back)

        // --- 9. Старая база: Свет и Фейды ---
        add("Белая вспышка 🔥", .dissolve, .light, fx: .flash, ease: .snap)
        add("Золотая вспышка ✨", .dissolve, .light, fx: .goldFlash, ease: .snap)
        add("Шелковый фейд", .dissolve, .fade, ease: .smooth)
        add("Кинематографичный ч/ч", .dip(deepBlack), .fade, ease: .smooth)

        // =====================================================================
        // 10. НОВЫЕ ТРЕНДОВЫЕ КАТЕГОРИИ (Добавленные CapCut VFX)
        // =====================================================================
        for d in Dir.allCases {
            add("Whip Pan \(d.arrow)", .whipPan(dir: d, blurStrength: 1.0), .velocityMotion, fx: .directionalBlur, ease: .snap)
            add("Whip Pan + RGB \(d.arrow)", .whipPan(dir: d, blurStrength: 1.2), .velocityMotion, fx: .rgb, ease: .expoFast)
        }
        add("Velocity Zoom IN 🚀", .velocityZoom(inward: true, ramp: 1.5), .velocityMotion, fx: .zoomBlur, ease: .expoFast)
        add("Velocity Zoom OUT 💥", .velocityZoom(inward: false, ramp: 1.5), .velocityMotion, fx: .zoomBlur, ease: .expoFast)
        for d in [Dir.left, Dir.right, Dir.up, Dir.down] {
            add("Bounce Snap \(d.arrow)", .bounceSnap(dir: d), .velocityMotion, fx: .shake, ease: .bounce)
        }
        add("Speed Ramp Cross Zoom", .crossZoomSpeedRamp, .velocityMotion, fx: .zoomBlur, ease: .snap)

        add("3D Flip Horizontal ↻", .spatial3DSpin(axisX: false, angle: .pi), .spinWarp, fx: .blur, ease: .smooth)
        add("3D Flip Vertical ↺", .spatial3DSpin(axisX: true, angle: .pi), .spinWarp, fx: .blur, ease: .smooth)
        add("Vortex Swirl IN 🌀", .vortexSwirlZoom(turns: 3.0), .spinWarp, fx: .chromatic, ease: .back)
        add("Fisheye Distortion 👁", .fisheyeLens(strength: 1.8), .spinWarp, fx: .zoomBlur, ease: .smooth)
        for d in Dir.allCases {
            add("Warp Slide Plastic \(d.arrow)", .warpSlide(dir: d, elasticity: 1.4), .spinWarp, fx: .dualAberration, ease: .elastic)
        }

        add("RGB Aberration Blast", .rgbAberrationSplit(shift: 0.08), .cyberGlitch, fx: .rgb, ease: .snap)
        add("Cyber Block Glitch 24px", .displacementBlockGlitch(blockSize: 24), .cyberGlitch, fx: .shake, ease: .snap)
        add("VHS Retro Static Tape", .vhsScanlineStatic(noiseGrain: 2.5), .cyberGlitch, fx: .shake, ease: .linear)
        add("Cyber Strobe Quantize", .cyberStrobeQuantize(bands: 16), .cyberGlitch, fx: .cyberpunk, ease: .snap)

        add("Warm Film Burn 🔥", .filmBurnFlash(warmth: 1.0), .lightLeaks, fx: .filmBurn, ease: .smooth)
        add("White Camera Flash 📸", .whiteCameraFlash, .lightLeaks, fx: .flash, ease: .snap)
        add("Neon Cyan Flare 💎", .cyberNeonFlare(color: neonCyan), .lightLeaks, fx: .neonFlare, ease: .snap)
        for deg in [0, 90, 180, 270] {
            add("Light Sweep \(deg)°", .lightLeakSweep(angle: CGFloat(deg) * .pi / 180), .lightLeaks, fx: .goldFlash, ease: .smooth)
        }

        add("Liquid Ripple Wave 🌊", .liquidRipple(frequency: 0.04, amplitude: 35), .opticalFlow, fx: .zoomBlur, ease: .elastic)
        add("Glass Refraction Prism 🔍", .glassRefractionMesh(refractIndex: 35), .opticalFlow, fx: .dualAberration, ease: .smooth)
        add("Heat Wave Mirage ♨️", .heatWaveMirage(distortion: 25), .opticalFlow, fx: .blur, ease: .smooth)
        add("Black Hole Collapse 🕳", .blackHolePinch(gravity: 1.8), .opticalFlow, fx: .zoomBlur, ease: .expoFast)

        add("Radial Blur Dissolve 🌀", .dissolve, .atmosphericFade, fx: .zoomBlur, ease: .smooth)
        add("Soft Fog Cloud Fade 🌫", .noise(grain: 1.5, cloud: true, soft: 0.3), .atmosphericFade, fx: .blur, ease: .smooth)
        add("Vintage Film Grain Fade 🎞", .noise(grain: 2.5, cloud: false, soft: 0.1), .atmosphericFade, fx: .none, ease: .linear)

        // =====================================================================
        // 11. PREMIUM-КОЛЛЕКЦИЯ: сдержанные, дорогие, «кинематографичные»
        //     (нейтральные цвета, мягкие кривые, никаких кислотных эффектов)
        // =====================================================================
        let ivory = CIColor(red: 0.96, green: 0.94, blue: 0.89)
        let charcoal = CIColor(red: 0.09, green: 0.09, blue: 0.10)
        let champagne = CIColor(red: 0.90, green: 0.80, blue: 0.62)
        let midnight = CIColor(red: 0.03, green: 0.05, blue: 0.11)
        let fourDirs: [Dir] = [.left, .right, .up, .down]
        let wipeAngles: [(Int, String)] = [(0, "→"), (180, "←"), (90, "↑"), (270, "↓")]

        // --- Cinematic ---
        for d in fourDirs {
            add("Glide \(d.arrow)", .glide(dir: d, parallax: 0.3, blur: 1.0), .cinematic, fx: .none, ease: .cinematic)
        }
        add("Dolly In", .dolly(inward: true, depth: 0.35), .cinematic, fx: .zoomBlurSoft, ease: .cinematic)
        add("Dolly Out", .dolly(inward: false, depth: 0.35), .cinematic, fx: .zoomBlurSoft, ease: .cinematic)
        add("Gentle Push-in", .zoom(inward: true, strength: 0.22), .cinematic, fx: .bloom, ease: .silk)
        add("Gentle Pull-out", .zoom(inward: false, strength: 0.22), .cinematic, fx: .softBlur, ease: .silk)
        add("Blur Dissolve", .blurDissolve(strength: 1.0), .cinematic, fx: .none, ease: .silk)
        add("Bloom Dissolve", .dissolve, .cinematic, fx: .bloom, ease: .silk)
        add("Exposure Dissolve", .dissolve, .cinematic, fx: .exposure, ease: .silk)
        add("Stretch Swap ↔", .stretchSwap(vertical: false, amount: 0.9), .cinematic, fx: .softBlur, ease: .cinematic)
        add("Stretch Swap ↕", .stretchSwap(vertical: true, amount: 0.9), .cinematic, fx: .softBlur, ease: .cinematic)
        add("Drift Rotate ↻", .driftRotate(angle: 0.16, cw: true), .cinematic, fx: .softBlur, ease: .cinematic)
        add("Drift Rotate ↺", .driftRotate(angle: 0.16, cw: false), .cinematic, fx: .softBlur, ease: .cinematic)

        // --- Depth & Cards ---
        for d in fourDirs {
            add("Card Stack \(d.arrow)", .cardStack(dir: d, depth: 0.08), .depthCard, fx: .none, ease: .cinematic)
        }
        for d in fourDirs {
            add("Card Peel \(d.arrow)", .cardPeel(dir: d, depth: 0.10), .depthCard, fx: .none, ease: .cinematic)
        }
        add("3D Куб вправо Soft", .cube(left: false), .depthCard, fx: .softBlur, ease: .cinematic)
        add("Flip Vertical Soft", .flip(vertical: true), .depthCard, fx: .softBlur, ease: .silk)
        add("Soft Twist ↻", .twirl(cw: true, strength: 1.4), .depthCard, fx: .softBlur, ease: .silk)
        add("Soft Twist ↺", .twirl(cw: false, strength: 1.4), .depthCard, fx: .softBlur, ease: .silk)
        add("Lens Swell", .bump(sign: 0.6), .depthCard, fx: .softBlur, ease: .silk)

        // --- Glass & Soft Focus ---
        for (deg, a) in wipeAngles {
            add("Frosted Sweep \(a)", .glassSweep(angle: CGFloat(deg) * .pi / 180, band: 0.28, blur: 1.0), .glassSoft, fx: .none, ease: .cinematic)
        }
        for (deg, a) in wipeAngles {
            add("Feather Wipe \(a)", .featherWipe(angle: CGFloat(deg) * .pi / 180, soft: 0.45, blur: 1.0), .glassSoft, fx: .none, ease: .silk)
        }
        add("Feather Wipe ↗", .featherWipe(angle: .pi / 4, soft: 0.45, blur: 1.0), .glassSoft, fx: .none, ease: .silk)
        add("Feather Wipe ↙", .featherWipe(angle: .pi * 5 / 4, soft: 0.45, blur: 1.0), .glassSoft, fx: .none, ease: .silk)
        add("Smoke Dissolve", .noise(grain: 10, cloud: true, soft: 0.5), .glassSoft, fx: .softBlur, ease: .silk)
        add("Mist Dissolve", .noise(grain: 22, cloud: true, soft: 0.65), .glassSoft, fx: .softGlow, ease: .silk)

        // --- Editorial Lines ---
        for (deg, a) in wipeAngles {
            add("Line Wipe \(a)", .lineWipe(angle: CGFloat(deg) * .pi / 180, width: 0.008), .editorial, fx: .none, ease: .cinematic)
        }
        add("Stagger Panels ↑", .staggerPanels(count: 6, vertical: true, reverse: false), .editorial, fx: .none, ease: .linear)
        add("Stagger Panels ↓", .staggerPanels(count: 6, vertical: true, reverse: true), .editorial, fx: .none, ease: .linear)
        add("Stagger Panels →", .staggerPanels(count: 5, vertical: false, reverse: false), .editorial, fx: .none, ease: .linear)
        add("Stagger Panels ←", .staggerPanels(count: 5, vertical: false, reverse: true), .editorial, fx: .none, ease: .linear)
        add("Aperture Open", .iris(inward: false, scaleX: 1, soft: 0.04, cx: 0.5, cy: 0.5), .editorial, fx: .none, ease: .cinematic)
        add("Aperture Close", .iris(inward: true, scaleX: 1, soft: 0.04, cx: 0.5, cy: 0.5), .editorial, fx: .none, ease: .cinematic)
        add("Oval Open", .iris(inward: false, scaleX: 1.7, soft: 0.06, cx: 0.5, cy: 0.5), .editorial, fx: .none, ease: .cinematic)
        add("Fine Blinds ‖", .blinds(count: 28, angle: 0, soft: 0.1), .editorial, fx: .none, ease: .silk)
        add("Fine Blinds ═", .blinds(count: 28, angle: .pi / 2, soft: 0.1), .editorial, fx: .none, ease: .silk)
        add("Doors ↕ Open", .doors(vertical: false, open: true), .editorial, fx: .softBlur, ease: .cinematic)
        add("Doors ↔ Close", .doors(vertical: true, open: false), .editorial, fx: .softBlur, ease: .cinematic)

        // --- Luxe Dips & Light ---
        add("Black Hold", .dipHold(deepBlack, hold: 0.18), .luxeLight, fx: .none, ease: .silk)
        add("White Hold", .dipHold(pureWhite, hold: 0.14), .luxeLight, fx: .none, ease: .silk)
        add("Ivory Hold", .dipHold(ivory, hold: 0.16), .luxeLight, fx: .none, ease: .silk)
        add("Charcoal Hold", .dipHold(charcoal, hold: 0.18), .luxeLight, fx: .none, ease: .silk)
        add("Champagne Hold", .dipHold(champagne, hold: 0.14), .luxeLight, fx: .none, ease: .silk)
        add("Midnight Hold", .dipHold(midnight, hold: 0.18), .luxeLight, fx: .none, ease: .silk)
        add("Champagne Glow", .dissolve, .luxeLight, fx: .champagne, ease: .silk)
        add("Pearl Glow", .dissolve, .luxeLight, fx: .pearl, ease: .silk)
        add("Soft Vignette Dissolve", .dissolve, .luxeLight, fx: .vignette, ease: .silk)
        add("Film Grain Dissolve", .dissolve, .luxeLight, fx: .grain, ease: .silk)
        add("Mono Pulse", .dissolve, .luxeLight, fx: .mono, ease: .silk)
        add("Chroma Whisper", .dissolve, .luxeLight, fx: .subtleChroma, ease: .silk)
        add("Soft Focus Glow", .dissolve, .luxeLight, fx: .softGlow, ease: .silk)
        add("Lens Breath", .dissolve, .luxeLight, fx: .lensBreath, ease: .silk)

        // =====================================================================
        // 12. RiCH: тяжёлая артиллерия на кастомных GPU-шейдерах
        //     (поля смещения, Вороной, multi-tap blur, покадровая хроматика, кривые Безье)
        // =====================================================================
        add("Liquid Flow Morph", .rich(.flowMorph, a: 2.2, b: 0.16), .rich, fx: .none, ease: .bezierStd)
        add("Chroma Barrel Push", .rich(.chromaBarrel, a: 1, b: 0.7), .rich, fx: .none, ease: .bezierStd)
        add("Chroma Barrel Pull", .rich(.chromaBarrel, a: 0, b: 0.7), .rich, fx: .none, ease: .bezierStd)
        add("Velocity Whip →", .rich(.whipPro, a: 1, b: 0), .rich, fx: .none, ease: .bezierInOut)
        add("Velocity Whip ↑", .rich(.whipPro, a: 0, b: 1), .rich, fx: .none, ease: .bezierInOut)
        add("Orbit Spin Blur", .rich(.orbitSpin, a: 0.9, b: 1), .rich, fx: .none, ease: .bezierStd)
        add("Shard Refraction", .rich(.shardRefract, a: 6, b: 3.7), .rich, fx: .none, ease: .silk)
        add("Shockwave Lens", .rich(.shockwave, a: 0.09, b: 0.14), .rich, fx: .none, ease: .bezierStd)
        add("Silk Smoke Dissolve", .rich(.smokeDissolve, a: 2.4, b: 0.55), .rich, fx: .none, ease: .bezierStd)
        add("Tile Cascade", .rich(.tileCascade, a: 9, b: 0), .rich, fx: .none, ease: .silk)
        add("Lenticular Glass", .rich(.lenticular, a: 14, b: 0.06), .rich, fx: .none, ease: .silk)
        add("Vortex Pull", .rich(.vortexPull, a: 4.0, b: 0.45), .rich, fx: .none, ease: .bezierStd)
        add("Anamorphic Flare", .rich(.anamorphicFlare, a: 0.3, b: 1.5), .rich, fx: .none, ease: .bezierStd)
        add("Depth Parallax", .rich(.depthParallax, a: 0.07, b: 1), .rich, fx: .none, ease: .bezierStd)
        add("Organic Light Leak", .rich(.lightLeak, a: 1.8, b: 1.0), .rich, fx: .none, ease: .bezierStd)
        add("Aqua Refraction", .rich(.aquaRefract, a: 6, b: 0.03), .rich, fx: .none, ease: .bezierStd)
        add("Radial Sweep ↻", .rich(.radialSweep, a: 0.08, b: .pi / 2), .rich, fx: .none, ease: .bezierInOut)
        add("Bokeh Rack Focus", .rich(.bokehRack, a: 0.045, b: 2.5), .rich, fx: .none, ease: .bezierStd)

        return list
    }
}
