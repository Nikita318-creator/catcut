// MARK: - Managers/FilterCatalog.swift

import UIKit
import CoreImage

// =====================================================================
// MARK: - Color adjustments (общий «движок» и для фильтров, и для ручной настройки)
// =====================================================================

struct Adjustments: Codable, Equatable {
    var brightness: Double = 0        // -1...1
    var contrast: Double = 0          // -1...1
    var saturation: Double = 0        // -1...1
    var vibrance: Double = 0          // -1...1
    var warmth: Double = 0            // -1...1 (холоднее ↔ теплее)
    var tint: Double = 0              // -1...1 (зелёный ↔ пурпурный)
    var highlights: Double = 0        // -1...1
    var shadows: Double = 0           // -1...1
    var hue: Double = 0               // -1...1  (±180°)
    var fade: Double = 0              // 0...1   (матовые чёрные)
    var sharpen: Double = 0           // 0...1
    var vignette: Double = 0          // 0...1
    var grain: Double = 0             // 0...1
    var retouch: Double = 0           // 0...1   (смягчение кожи)
    var glow: Double = 0              // 0...1
    var blur: Double = 0              // 0...1
    var curveShadows: Double = 0      // -1...1
    var curveMid: Double = 0          // -1...1
    var curveHigh: Double = 0         // -1...1
    var shadowTone: Double = 0        // оттенок в тенях 0...1 (круг цветов)
    var shadowToneAmount: Double = 0  // 0...1
    var highTone: Double = 0          // оттенок в светах
    var highToneAmount: Double = 0
    /// 8 каналов (красный, оранжевый, жёлтый, зелёный, голубой, синий, фиолетовый, розовый) × (оттенок, насыщенность, яркость)
    var hsl: [Double] = Array(repeating: 0, count: 24)

    var isIdentity: Bool { self == Adjustments() }
    var needsCube: Bool { shadowToneAmount != 0 || highToneAmount != 0 || hsl.contains { $0 != 0 } }
}

enum HSLChannel {
    static let titles = ["Красный", "Оранж.", "Жёлтый", "Зелёный", "Голубой", "Синий", "Фиолет.", "Розовый"]
    static let degrees: [Double] = [0, 30, 60, 120, 180, 225, 275, 320]
    static let colors: [UIColor] = degrees.map { UIColor(hue: CGFloat($0 / 360), saturation: 0.85, brightness: 1, alpha: 1) }
}

/// Цветовой куб для HSL и тонирования теней/светов. Считается один раз на набор параметров.
enum ColorCube {
    private static let cache = NSCache<NSString, NSData>()
    static let dimension = 24

    static func data(for a: Adjustments) -> Data {
        let key = "\(a.shadowTone)|\(a.shadowToneAmount)|\(a.highTone)|\(a.highToneAmount)|\(a.hsl)" as NSString
        if let cached = cache.object(forKey: key) { return cached as Data }

        let n = dimension
        var out = [Float](repeating: 0, count: n * n * n * 4)
        var idx = 0

        func hsvToRgb(_ h: Double, _ s: Double, _ v: Double) -> (Double, Double, Double) {
            let hh = (h - floor(h)) * 6
            let i = floor(hh), f = hh - i
            let p = v * (1 - s), q = v * (1 - s * f), t = v * (1 - s * (1 - f))
            switch Int(i) % 6 {
            case 0: return (v, t, p)
            case 1: return (q, v, p)
            case 2: return (p, v, t)
            case 3: return (p, q, v)
            case 4: return (t, p, v)
            default: return (v, p, q)
            }
        }

        let shadowRGB = hsvToRgb(a.shadowTone, 1, 1)
        let highRGB = hsvToRgb(a.highTone, 1, 1)
        let hslActive = a.hsl.contains { $0 != 0 }

        for bi in 0..<n {
            for gi in 0..<n {
                for ri in 0..<n {
                    var r = Double(ri) / Double(n - 1)
                    var g = Double(gi) / Double(n - 1)
                    var b = Double(bi) / Double(n - 1)

                    if hslActive {
                        let mx = max(r, g, b), mn = min(r, g, b), d = mx - mn
                        var h = 0.0
                        if d > 0.0001 {
                            if mx == r { h = ((g - b) / d).truncatingRemainder(dividingBy: 6) }
                            else if mx == g { h = (b - r) / d + 2 }
                            else { h = (r - g) / d + 4 }
                            h /= 6
                            if h < 0 { h += 1 }
                        }
                        var s = mx > 0.0001 ? d / mx : 0
                        var v = mx
                        let hueDeg = h * 360
                        var dh = 0.0, ds = 0.0, dv = 0.0
                        for k in 0..<8 {
                            var dist = abs(hueDeg - HSLChannel.degrees[k])
                            if dist > 180 { dist = 360 - dist }
                            let w = max(0, 1 - dist / 45) * min(1, s * 3)
                            if w > 0 {
                                dh += w * a.hsl[k * 3] * 40 / 360
                                ds += w * a.hsl[k * 3 + 1]
                                dv += w * a.hsl[k * 3 + 2]
                            }
                        }
                        h += dh
                        s = max(0, min(1, s * (1 + ds)))
                        v = max(0, min(1, v * (1 + dv * 0.6)))
                        (r, g, b) = hsvToRgb(h, s, v)
                    }

                    if a.shadowToneAmount != 0 || a.highToneAmount != 0 {
                        let lum = 0.2126 * r + 0.7152 * g + 0.0722 * b
                        let sw = pow(1 - lum, 2) * a.shadowToneAmount * 0.5
                        let hw = pow(lum, 2) * a.highToneAmount * 0.5
                        r += (shadowRGB.0 - 0.5) * sw + (highRGB.0 - 0.5) * hw
                        g += (shadowRGB.1 - 0.5) * sw + (highRGB.1 - 0.5) * hw
                        b += (shadowRGB.2 - 0.5) * sw + (highRGB.2 - 0.5) * hw
                    }

                    out[idx] = Float(max(0, min(1, r)))
                    out[idx + 1] = Float(max(0, min(1, g)))
                    out[idx + 2] = Float(max(0, min(1, b)))
                    out[idx + 3] = 1
                    idx += 4
                }
            }
        }
        let d = out.withUnsafeBufferPointer { Data(buffer: $0) }
        cache.setObject(d as NSData, forKey: key)
        return d
    }
}

extension Adjustments {

    /// Применяет настройки. time нужен только для «живого» зерна.
    func apply(to input: CIImage, time: Double = 0) -> CIImage {
        guard !isIdentity else { return input }
        let extent = input.extent
        var img = input

        func f(_ name: String, _ params: [String: Any]) {
            guard let flt = CIFilter(name: name) else { return }
            flt.setValue(img, forKey: kCIInputImageKey)
            for (k, v) in params where flt.inputKeys.contains(k) { flt.setValue(v, forKey: k) }
            if let o = flt.outputImage { img = o.cropped(to: extent) }
        }
        func vec(_ x: Double, _ y: Double) -> CIVector { CIVector(x: CGFloat(x), y: CGFloat(y)) }

        // Баланс белого
        if warmth != 0 || tint != 0 {
            f("CITemperatureAndTint", [
                "inputNeutral": CIVector(x: 6500 + CGFloat(warmth) * 2200, y: CGFloat(tint) * 80),
                "inputTargetNeutral": CIVector(x: 6500, y: 0)
            ])
        }

        // Света / тени
        if highlights < 0 || shadows != 0 {
            f("CIHighlightShadowAdjust", ["inputHighlightAmount": 1 + min(0, highlights), "inputShadowAmount": shadows])
        }

        // Кривая (3 точки)
        let ch = curveHigh + max(0, highlights) * 0.8
        if curveShadows != 0 || curveMid != 0 || ch != 0 {
            func c(_ v: Double) -> Double { max(0, min(1, v)) }
            f("CIToneCurve", [
                "inputPoint0": vec(0, 0),
                "inputPoint1": vec(0.25, c(0.25 + curveShadows * 0.15)),
                "inputPoint2": vec(0.5, c(0.5 + curveMid * 0.2)),
                "inputPoint3": vec(0.75, c(0.75 + ch * 0.15)),
                "inputPoint4": vec(1, 1)
            ])
        }

        // Яркость / контраст / насыщенность
        if brightness != 0 || contrast != 0 || saturation != 0 {
            f("CIColorControls", [
                kCIInputBrightnessKey: brightness * 0.4,
                kCIInputContrastKey: 1 + contrast * 0.6,
                kCIInputSaturationKey: max(0, 1 + saturation)
            ])
        }
        if vibrance != 0 { f("CIVibrance", ["inputAmount": vibrance]) }
        if hue != 0 { f("CIHueAdjustment", [kCIInputAngleKey: hue * Double.pi]) }

        // HSL + тонирование
        if needsCube {
            f("CIColorCube", ["inputCubeDimension": ColorCube.dimension, "inputCubeData": ColorCube.data(for: self)])
        }

        // Матовость
        if fade > 0 {
            let k = CGFloat(1 - fade * 0.25), bias = CGFloat(fade * 0.1)
            f("CIColorMatrix", [
                "inputRVector": CIVector(x: k, y: 0, z: 0, w: 0),
                "inputGVector": CIVector(x: 0, y: k, z: 0, w: 0),
                "inputBVector": CIVector(x: 0, y: 0, z: k, w: 0),
                "inputAVector": CIVector(x: 0, y: 0, z: 0, w: 1),
                "inputBiasVector": CIVector(x: bias, y: bias, z: bias, w: 0)
            ])
        }

        // Ретушь (мягкая кожа): смесь с размытием
        if retouch > 0 {
            let sigma = Double(extent.height) * 0.003 * (1 + retouch * 2)
            let soft = img.clampedToExtent().applyingGaussianBlur(sigma: sigma).cropped(to: extent)
            let a = CGFloat(min(0.85, retouch * 0.8))
            img = soft.applyingFilter("CIColorMatrix", parameters: [
                "inputRVector": CIVector(x: 1, y: 0, z: 0, w: 0),
                "inputGVector": CIVector(x: 0, y: 1, z: 0, w: 0),
                "inputBVector": CIVector(x: 0, y: 0, z: 1, w: 0),
                "inputAVector": CIVector(x: 0, y: 0, z: 0, w: a),
                "inputBiasVector": CIVector(x: 0, y: 0, z: 0, w: 0)
            ]).composited(over: img).cropped(to: extent)
        }

        if blur > 0 {
            img = img.clampedToExtent().applyingGaussianBlur(sigma: Double(extent.height) * 0.02 * blur).cropped(to: extent)
        }
        if glow > 0 {
            f("CIBloom", [kCIInputRadiusKey: Double(extent.height) * 0.02, kCIInputIntensityKey: glow])
        }
        if sharpen > 0 { f("CISharpenLuminance", ["inputSharpness": sharpen * 1.5]) }
        if vignette > 0 { f("CIVignette", [kCIInputIntensityKey: vignette * 1.6, kCIInputRadiusKey: 1.6]) }

        // Зерно (живое — меняется каждый кадр)
        if grain > 0, let rg = CIFilter(name: "CIRandomGenerator")?.outputImage {
            let frame = floor(time * 24)
            let jitter = CGAffineTransform(translationX: CGFloat(frame.truncatingRemainder(dividingBy: 97)) * 37,
                                           y: CGFloat(frame.truncatingRemainder(dividingBy: 89)) * 53)
            let k = CGFloat(grain * 0.9)
            let noise = rg.transformed(by: jitter)
                .transformed(by: CGAffineTransform(scaleX: 1.4, y: 1.4))
                .applyingFilter("CIColorMatrix", parameters: [
                    "inputRVector": CIVector(x: k, y: 0, z: 0, w: 0),
                    "inputGVector": CIVector(x: k, y: 0, z: 0, w: 0),
                    "inputBVector": CIVector(x: k, y: 0, z: 0, w: 0),
                    "inputAVector": CIVector(x: 0, y: 0, z: 0, w: 0),
                    "inputBiasVector": CIVector(x: 0.5 - 0.5 * k, y: 0.5 - 0.5 * k, z: 0.5 - 0.5 * k, w: 1)
                ]).cropped(to: extent)
            img = noise.applyingFilter("CISoftLightBlendMode", parameters: [kCIInputBackgroundImageKey: img]).cropped(to: extent)
        }
        return img
    }
}

// =====================================================================
// MARK: - Filter presets (мягкие, «дорогие»)
// =====================================================================

enum FilterCategory: Int, CaseIterable {
    case all, favorites, soft, cinema, portrait, retro, bw, vivid

    var title: String {
        switch self {
        case .all: return "Все"
        case .favorites: return "♥ Избранное"
        case .soft: return "Нежные"
        case .cinema: return "Кино"
        case .portrait: return "Портрет"
        case .retro: return "Ретро"
        case .bw: return "Ч/Б"
        case .vivid: return "Яркие"
        }
    }
}

struct FilterPreset {
    let name: String
    let category: FilterCategory
    let adjust: Adjustments
}

enum FilterCatalog {
    /// id фильтра = номер в списке (с 1). 0 = без фильтра.
    static let all: [FilterPreset] = {
        var list: [FilterPreset] = []
        func p(_ name: String, _ cat: FilterCategory, _ f: (inout Adjustments) -> Void) {
            var a = Adjustments()
            f(&a)
            list.append(FilterPreset(name: name, category: cat, adjust: a))
        }

        // Нежные
        p("Нежность", .soft) { $0.contrast = -0.06; $0.saturation = -0.08; $0.fade = 0.22; $0.warmth = 0.08; $0.glow = 0.25; $0.highlights = -0.15 }
        p("Сливки", .soft) { $0.brightness = 0.04; $0.contrast = -0.08; $0.saturation = -0.12; $0.warmth = 0.25; $0.fade = 0.2; $0.shadows = 0.15; $0.glow = 0.15 }
        p("Пастель", .soft) { $0.brightness = 0.08; $0.contrast = -0.12; $0.saturation = -0.18; $0.fade = 0.3; $0.vibrance = 0.1 }
        p("Дымка", .soft) { $0.brightness = 0.06; $0.contrast = -0.18; $0.fade = 0.38; $0.glow = 0.35; $0.saturation = -0.1 }
        p("Персик", .soft) { $0.warmth = 0.22; $0.tint = 0.12; $0.brightness = 0.05; $0.fade = 0.18; $0.glow = 0.2; $0.retouch = 0.2 }
        p("Облако", .soft) { $0.brightness = 0.1; $0.contrast = -0.1; $0.saturation = -0.25; $0.warmth = -0.05; $0.fade = 0.25; $0.glow = 0.2 }
        p("Молоко", .soft) { $0.brightness = 0.12; $0.contrast = -0.15; $0.saturation = -0.3; $0.fade = 0.3 }

        // Кино
        p("Кино", .cinema) { $0.contrast = 0.15; $0.saturation = -0.08; $0.fade = 0.12; $0.shadowTone = 0.52; $0.shadowToneAmount = 0.28; $0.highTone = 0.08; $0.highToneAmount = 0.22; $0.vignette = 0.25; $0.grain = 0.12 }
        p("Тил и оранж", .cinema) { $0.contrast = 0.18; $0.saturation = 0.05; $0.shadowTone = 0.5; $0.shadowToneAmount = 0.4; $0.highTone = 0.07; $0.highToneAmount = 0.35; $0.vignette = 0.15 }
        p("Ночной город", .cinema) { $0.brightness = -0.05; $0.contrast = 0.2; $0.saturation = 0.1; $0.shadowTone = 0.62; $0.shadowToneAmount = 0.4; $0.highTone = 0.88; $0.highToneAmount = 0.25; $0.glow = 0.3; $0.vignette = 0.3 }
        p("Драма", .cinema) { $0.contrast = 0.3; $0.saturation = -0.2; $0.shadows = -0.2; $0.vignette = 0.4; $0.fade = 0.08; $0.grain = 0.15 }
        p("Блокбастер", .cinema) { $0.contrast = 0.22; $0.saturation = 0.1; $0.warmth = -0.05; $0.shadowTone = 0.55; $0.shadowToneAmount = 0.3; $0.highTone = 0.08; $0.highToneAmount = 0.2; $0.sharpen = 0.3 }
        p("Мрак", .cinema) { $0.brightness = -0.1; $0.contrast = 0.25; $0.saturation = -0.3; $0.vignette = 0.5; $0.shadowTone = 0.6; $0.shadowToneAmount = 0.25 }

        // Портрет
        p("Глянец", .portrait) { $0.retouch = 0.55; $0.glow = 0.3; $0.brightness = 0.05; $0.warmth = 0.1; $0.saturation = 0.05; $0.contrast = 0.05 }
        p("Кожа", .portrait) { $0.retouch = 0.6; $0.warmth = 0.12; $0.tint = 0.05; $0.vibrance = 0.15; $0.brightness = 0.04; $0.highlights = -0.1 }
        p("Свежесть", .portrait) { $0.vibrance = 0.3; $0.brightness = 0.06; $0.warmth = -0.04; $0.retouch = 0.3; $0.glow = 0.15 }
        p("Румянец", .portrait) { $0.warmth = 0.15; $0.tint = 0.15; $0.saturation = 0.05; $0.retouch = 0.4; $0.glow = 0.2 }
        p("Гламур", .portrait) { $0.retouch = 0.5; $0.glow = 0.45; $0.brightness = 0.07; $0.contrast = 0.08; $0.vibrance = 0.2 }
        p("Студия", .portrait) { $0.contrast = 0.12; $0.sharpen = 0.3; $0.retouch = 0.25; $0.brightness = 0.03; $0.warmth = 0.05 }

        // Ретро
        p("Плёнка 90-х", .retro) { $0.warmth = 0.2; $0.fade = 0.32; $0.grain = 0.35; $0.saturation = -0.12; $0.contrast = 0.1; $0.vignette = 0.22; $0.highlights = -0.15 }
        p("Полароид", .retro) { $0.warmth = 0.15; $0.tint = 0.06; $0.fade = 0.28; $0.contrast = -0.05; $0.saturation = -0.05; $0.vignette = 0.3; $0.grain = 0.15 }
        p("Винтаж", .retro) { $0.warmth = 0.3; $0.saturation = -0.25; $0.fade = 0.35; $0.contrast = 0.05; $0.grain = 0.25; $0.vignette = 0.3 }
        p("VHS", .retro) { $0.saturation = 0.1; $0.warmth = 0.05; $0.fade = 0.15; $0.grain = 0.4; $0.blur = 0.08; $0.contrast = 0.1 }
        p("70-е", .retro) { $0.warmth = 0.35; $0.tint = 0.1; $0.saturation = 0.15; $0.fade = 0.2; $0.contrast = 0.1; $0.grain = 0.2 }
        p("Кодак", .retro) { $0.warmth = 0.15; $0.saturation = 0.12; $0.contrast = 0.12; $0.fade = 0.1; $0.grain = 0.2; $0.highlights = -0.1 }
        p("Выцветшее фото", .retro) { $0.saturation = -0.3; $0.fade = 0.45; $0.warmth = 0.15; $0.contrast = -0.1; $0.vignette = 0.2 }

        // Ч/Б
        p("Ч/Б мягкий", .bw) { $0.saturation = -1; $0.fade = 0.2; $0.contrast = -0.05; $0.grain = 0.1 }
        p("Ч/Б контраст", .bw) { $0.saturation = -1; $0.contrast = 0.4; $0.vignette = 0.25 }
        p("Ч/Б плёнка", .bw) { $0.saturation = -1; $0.contrast = 0.15; $0.fade = 0.15; $0.grain = 0.45; $0.vignette = 0.25 }
        p("Серебро", .bw) { $0.saturation = -1; $0.brightness = 0.05; $0.contrast = 0.1; $0.glow = 0.2 }
        p("Графит", .bw) { $0.saturation = -1; $0.contrast = 0.3; $0.brightness = -0.1; $0.vignette = 0.4 }

        // Яркие
        p("Яркий день", .vivid) { $0.vibrance = 0.3; $0.saturation = 0.15; $0.contrast = 0.1; $0.brightness = 0.03 }
        p("Сочный", .vivid) { $0.saturation = 0.35; $0.contrast = 0.12; $0.vibrance = 0.2 }
        p("Лето", .vivid) { $0.warmth = 0.2; $0.saturation = 0.2; $0.brightness = 0.05; $0.contrast = 0.08; $0.glow = 0.12 }
        p("Осень", .vivid) { $0.warmth = 0.35; $0.saturation = 0.1; $0.highTone = 0.08; $0.highToneAmount = 0.2; $0.contrast = 0.1; $0.vignette = 0.15 }
        p("Лес", .vivid) {
            $0.contrast = 0.1; $0.vignette = 0.2
            $0.hsl[9 + 1] = 0.4; $0.hsl[6 + 1] = 0.2
        }
        p("Море", .vivid) {
            $0.warmth = -0.15; $0.saturation = 0.15; $0.contrast = 0.1
            $0.hsl[12 + 1] = 0.4; $0.hsl[15 + 1] = 0.3
        }
        p("Закат", .vivid) { $0.warmth = 0.45; $0.tint = 0.12; $0.saturation = 0.15; $0.contrast = 0.1; $0.highTone = 0.05; $0.highToneAmount = 0.3; $0.vignette = 0.25; $0.glow = 0.2 }
        p("Неон", .vivid) { $0.saturation = 0.3; $0.contrast = 0.2; $0.shadowTone = 0.75; $0.shadowToneAmount = 0.4; $0.highTone = 0.9; $0.highToneAmount = 0.3; $0.glow = 0.35; $0.vignette = 0.2 }
        p("Лёд", .vivid) { $0.warmth = -0.35; $0.saturation = -0.05; $0.brightness = 0.05; $0.contrast = 0.1; $0.glow = 0.15 }
        return list
    }()

    static func preset(_ id: Int) -> FilterPreset? {
        guard id > 0, id <= all.count else { return nil }
        return all[id - 1]
    }

    static func ids(for category: FilterCategory) -> [Int] {
        switch category {
        case .all:
            return Array(1...max(1, all.count)).filter { $0 <= all.count }
        case .favorites:
            return all.indices.map { $0 + 1 }.filter { FilterFavorites.contains($0) }
        default:
            return all.enumerated().filter { $0.element.category == category }.map { $0.offset + 1 }
        }
    }
}

// =====================================================================
// MARK: - Video looks (живые эффекты на клип)
// =====================================================================

enum VideoLook: Int, CaseIterable {
    case none, glitch, shake, vhs, grain, flicker, pulse, pixel, glow, softFocus, mirror, rainbow

    var title: String {
        switch self {
        case .none: return "Нет"
        case .glitch: return "Глитч RGB"
        case .shake: return "Тряска"
        case .vhs: return "VHS"
        case .grain: return "Плёнка"
        case .flicker: return "Мерцание"
        case .pulse: return "Пульс"
        case .pixel: return "Пиксели"
        case .glow: return "Свечение"
        case .softFocus: return "Мягкий фокус"
        case .mirror: return "Зеркало"
        case .rainbow: return "Радуга"
        }
    }

    var symbol: String {
        switch self {
        case .none: return "xmark"
        case .glitch: return "waveform"
        case .shake: return "iphone.radiowaves.left.and.right"
        case .vhs: return "tv"
        case .grain: return "film"
        case .flicker: return "bolt.fill"
        case .pulse: return "heart.fill"
        case .pixel: return "square.grid.3x3.fill"
        case .glow: return "sun.max.fill"
        case .softFocus: return "circle.dotted"
        case .mirror: return "rectangle.split.2x1"
        case .rainbow: return "paintpalette"
        }
    }

    func apply(to input: CIImage, time: Double) -> CIImage {
        let e = input.extent
        let W = e.width, H = e.height
        func channelShift(_ img: CIImage, _ d: CGFloat) -> CIImage {
            func ch(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat) -> CIImage {
                img.applyingFilter("CIColorMatrix", parameters: [
                    "inputRVector": CIVector(x: r, y: 0, z: 0, w: 0),
                    "inputGVector": CIVector(x: 0, y: g, z: 0, w: 0),
                    "inputBVector": CIVector(x: 0, y: 0, z: b, w: 0),
                    "inputAVector": CIVector(x: 0, y: 0, z: 0, w: 1),
                    "inputBiasVector": CIVector(x: 0, y: 0, z: 0, w: 0)
                ])
            }
            let red = ch(1, 0, 0).transformed(by: CGAffineTransform(translationX: d, y: 0))
            let green = ch(0, 1, 0)
            let blue = ch(0, 0, 1).transformed(by: CGAffineTransform(translationX: -d, y: 0))
            let rg = green.applyingFilter("CIAdditionCompositing", parameters: [kCIInputBackgroundImageKey: red])
            return blue.applyingFilter("CIAdditionCompositing", parameters: [kCIInputBackgroundImageKey: rg]).cropped(to: e)
        }
        func scaled(_ img: CIImage, _ s: CGFloat) -> CIImage {
            let t = CGAffineTransform(translationX: -e.midX, y: -e.midY)
                .concatenating(CGAffineTransform(scaleX: s, y: s))
                .concatenating(CGAffineTransform(translationX: e.midX, y: e.midY))
            return img.transformed(by: t).cropped(to: e)
        }

        switch self {
        case .none:
            return input
        case .glitch:
            let burst = CGFloat(pow(max(0, sin(time * 9)), 6))
            return channelShift(input, W * 0.025 * burst + W * 0.002)
        case .shake:
            let s = scaled(input, 1.06)
            return s.transformed(by: CGAffineTransform(translationX: CGFloat(sin(time * 31)) * W * 0.012,
                                                       y: CGFloat(cos(time * 27)) * H * 0.008)).cropped(to: e)
        case .vhs:
            var img = channelShift(input, W * 0.006)
            img = img.applyingFilter("CIColorControls", parameters: [kCIInputSaturationKey: 0.85, kCIInputContrastKey: 1.08])
            if let stripes = CIFilter(name: "CIStripesGenerator") {
                stripes.setValue(CIVector(x: e.midX, y: e.midY), forKey: "inputCenter")
                stripes.setValue(CIColor(red: 0, green: 0, blue: 0, alpha: 0.18), forKey: "inputColor0")
                stripes.setValue(CIColor(red: 0, green: 0, blue: 0, alpha: 0), forKey: "inputColor1")
                stripes.setValue(max(1, H / 360), forKey: "inputWidth")
                stripes.setValue(0.7, forKey: "inputSharpness")
                if let s = stripes.outputImage?.transformed(by: CGAffineTransform(rotationAngle: .pi / 2)).cropped(to: e) {
                    img = s.composited(over: img)
                }
            }
            return Adjustments(grain: 0.35).apply(to: img, time: time)
        case .grain:
            var a = Adjustments()
            a.grain = 0.6; a.fade = 0.15; a.vignette = 0.2
            return a.apply(to: input, time: time)
        case .flicker:
            let b = 0.07 * sin(time * 53) + 0.04 * sin(time * 17)
            return input.applyingFilter("CIColorControls", parameters: [kCIInputBrightnessKey: b])
        case .pulse:
            return scaled(input, 1 + 0.045 * CGFloat(max(0, sin(time * 8))))
        case .pixel:
            return input.clampedToExtent()
                .applyingFilter("CIPixellate", parameters: [kCIInputScaleKey: max(4, W * 0.012), kCIInputCenterKey: CIVector(x: 0, y: 0)])
                .cropped(to: e)
        case .glow:
            return input.applyingFilter("CIBloom", parameters: [kCIInputRadiusKey: Double(H) * 0.025, kCIInputIntensityKey: 1.0]).cropped(to: e)
        case .softFocus:
            let blurred = input.clampedToExtent().applyingGaussianBlur(sigma: Double(H) * 0.008).cropped(to: e)
            return blurred.applyingFilter("CIColorMatrix", parameters: [
                "inputRVector": CIVector(x: 1, y: 0, z: 0, w: 0), "inputGVector": CIVector(x: 0, y: 1, z: 0, w: 0),
                "inputBVector": CIVector(x: 0, y: 0, z: 1, w: 0), "inputAVector": CIVector(x: 0, y: 0, z: 0, w: 0.6),
                "inputBiasVector": CIVector(x: 0, y: 0, z: 0, w: 0)
            ]).composited(over: input).cropped(to: e)
        case .mirror:
            let left = input.cropped(to: CGRect(x: e.minX, y: e.minY, width: W / 2, height: H))
            let flipped = left.transformed(by: CGAffineTransform(scaleX: -1, y: 1).concatenating(CGAffineTransform(translationX: e.minX + W, y: 0)))
            return flipped.composited(over: left.composited(over: input)).cropped(to: e)
        case .rainbow:
            return input.applyingFilter("CIHueAdjustment", parameters: [kCIInputAngleKey: time * 2.2])
        }
    }
}
