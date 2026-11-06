// MARK: - Managers/TransitionRenderer.swift

import UIKit
import CoreImage

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
