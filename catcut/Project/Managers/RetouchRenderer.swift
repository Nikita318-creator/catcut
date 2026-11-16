// MARK: - Core/RetouchRenderer.swift

import UIKit
import CoreImage
import CoreVideo
import Metal

// =====================================================================
// MARK: - Мелкие геометрические помощники (fileprivate, чтобы не пересекаться с проектом)
// Все расчёты — в пикселях кадра, y ВНИЗ (как в Metal-шейдере).
// =====================================================================

fileprivate func rtCentroid(_ p: [CGPoint]) -> CGPoint {
    guard !p.isEmpty else { return .zero }
    let s = p.reduce(CGPoint.zero) { CGPoint(x: $0.x + $1.x, y: $0.y + $1.y) }
    return CGPoint(x: s.x / CGFloat(p.count), y: s.y / CGFloat(p.count))
}
fileprivate func rtBounds(_ p: [CGPoint]) -> CGRect {
    guard let f = p.first else { return .null }
    var minX = f.x, maxX = f.x, minY = f.y, maxY = f.y
    for q in p { minX = min(minX, q.x); maxX = max(maxX, q.x); minY = min(minY, q.y); maxY = max(maxY, q.y) }
    return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
}
fileprivate func rtDist(_ a: CGPoint, _ b: CGPoint) -> CGFloat { hypot(a.x - b.x, a.y - b.y) }
fileprivate func rtMix(_ a: CGPoint, _ b: CGPoint, _ t: CGFloat) -> CGPoint {
    CGPoint(x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t)
}
fileprivate func rtUnit(from a: CGPoint, to b: CGPoint) -> CGVector {
    let dx = b.x - a.x, dy = b.y - a.y
    let l = max(0.0001, hypot(dx, dy))
    return CGVector(dx: dx / l, dy: dy / l)
}
fileprivate func rtShift(_ p: CGPoint, _ v: CGVector, _ k: CGFloat) -> CGPoint {
    CGPoint(x: p.x + v.dx * k, y: p.y + v.dy * k)
}
fileprivate func rtExpand(_ pts: [CGPoint], _ k: CGFloat) -> [CGPoint] {
    let c = rtCentroid(pts)
    return pts.map { CGPoint(x: c.x + ($0.x - c.x) * k, y: c.y + ($0.y - c.y) * k) }
}

// =====================================================================
// MARK: - Warp (Metal compute)
// =====================================================================

struct WarpOp {
    var center = SIMD2<Float>(0, 0)
    var axis = SIMD2<Float>(1, 0)
    var radii = SIMD2<Float>(1, 1)
    var vec = SIMD2<Float>(0, 0)
    var strength: Float = 0
    var kind: Int32 = 0

    static func make(_ kind: Int32, c: CGPoint, axis: CGVector, ra: CGFloat, rb: CGFloat,
                     strength: Double = 0, vec: CGVector = .zero) -> WarpOp {
        WarpOp(center: SIMD2(Float(c.x), Float(c.y)),
               axis: SIMD2(Float(axis.dx), Float(axis.dy)),
               radii: SIMD2(Float(max(1, ra)), Float(max(1, rb))),
               vec: SIMD2(Float(vec.dx), Float(vec.dy)),
               strength: Float(strength), kind: kind)
    }
}

final class MetalWarp {
    static let shared = MetalWarp()

    private let device: MTLDevice?
    private let queue: MTLCommandQueue?
    private let pipeline: MTLComputePipelineState?
    private var cache: CVMetalTextureCache?
    private let lock = NSLock()
    private var pin: CVPixelBuffer?
    private var pool: CVPixelBufferPool?
    private var poolW = 0, poolH = 0

    private init() {
        let d = MTLCreateSystemDefaultDevice()
        device = d
        queue = d?.makeCommandQueue()
        var pso: MTLComputePipelineState?
        if let d = d, let lib = d.makeDefaultLibrary(), let fn = lib.makeFunction(name: "retouchWarp") {
            pso = try? d.makeComputePipelineState(function: fn)
        }
        pipeline = pso
        var c: CVMetalTextureCache?
        if let d = d { CVMetalTextureCacheCreate(kCFAllocatorDefault, nil, d, nil, &c) }
        cache = c
        if pso == nil { print("⚠️ Retouch.metal не найден в таргете — деформация формы отключена") }
    }

    private func prepareBuffers(_ w: Int, _ h: Int) -> Bool {
        if pool != nil, pin != nil, poolW == w, poolH == h { return true }
        let attrs: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: w,
            kCVPixelBufferHeightKey as String: h,
            kCVPixelBufferMetalCompatibilityKey as String: true,
            kCVPixelBufferIOSurfacePropertiesKey as String: [String: Any]()
        ]
        var p: CVPixelBufferPool?
        guard CVPixelBufferPoolCreate(kCFAllocatorDefault, nil, attrs as CFDictionary, &p) == kCVReturnSuccess,
              let pl = p else { return false }
        var b: CVPixelBuffer?
        guard CVPixelBufferCreate(kCFAllocatorDefault, w, h, kCVPixelFormatType_32BGRA, attrs as CFDictionary, &b) == kCVReturnSuccess
        else { return false }
        pool = pl; pin = b; poolW = w; poolH = h
        return true
    }

    private func texture(_ pb: CVPixelBuffer, _ cache: CVMetalTextureCache) -> (MTLTexture, CVMetalTexture)? {
        var t: CVMetalTexture?
        let usage = MTLTextureUsage([.shaderRead, .shaderWrite]).rawValue
        let attrs = [kCVMetalTextureUsage as String: NSNumber(value: usage)] as CFDictionary
        let st = CVMetalTextureCacheCreateTextureFromImage(kCFAllocatorDefault, cache, pb, attrs, .bgra8Unorm,
                                                           CVPixelBufferGetWidth(pb), CVPixelBufferGetHeight(pb), 0, &t)
        guard st == kCVReturnSuccess, let cv = t, let tex = CVMetalTextureGetTexture(cv) else { return nil }
        return (tex, cv)
    }

    func warp(_ image: CIImage, ops: [WarpOp], context: CIContext) -> CIImage {
        guard !ops.isEmpty, let queue = queue, let pipeline = pipeline, let cache = cache else { return image }
        let e = image.extent
        let w = Int(e.width.rounded()), h = Int(e.height.rounded())
        guard w > 16, h > 16 else { return image }

        lock.lock(); defer { lock.unlock() }
        guard prepareBuffers(w, h), let pin = pin, let pool = pool else { return image }
        var outBuf: CVPixelBuffer?
        guard CVPixelBufferPoolCreatePixelBuffer(kCFAllocatorDefault, pool, &outBuf) == kCVReturnSuccess,
              let pout = outBuf else { return image }

        let cs = CGColorSpace(name: CGColorSpace.sRGB)!
        context.render(image, to: pin, bounds: CGRect(x: e.minX, y: e.minY, width: CGFloat(w), height: CGFloat(h)), colorSpace: cs)

        guard let (tin, keepIn) = texture(pin, cache), let (tout, keepOut) = texture(pout, cache),
              let cb = queue.makeCommandBuffer(), let enc = cb.makeComputeCommandEncoder() else { return image }

        var list = Array(ops.prefix(24))
        var count = UInt32(list.count)
        enc.setComputePipelineState(pipeline)
        enc.setTexture(tin, index: 0)
        enc.setTexture(tout, index: 1)
        enc.setBytes(&list, length: MemoryLayout<WarpOp>.stride * list.count, index: 0)
        enc.setBytes(&count, length: MemoryLayout<UInt32>.size, index: 1)
        enc.dispatchThreads(MTLSize(width: w, height: h, depth: 1),
                            threadsPerThreadgroup: MTLSize(width: 16, height: 16, depth: 1))
        enc.endEncoding()
        cb.commit()
        cb.waitUntilCompleted()
        withExtendedLifetime((keepIn, keepOut)) {}

        // outBuf берётся из пула и держится CIImage до конца рендера кадра — перезаписи не будет.
        return CIImage(cvPixelBuffer: pout, options: [.colorSpace: cs])
    }
}

// =====================================================================
// MARK: - Геометрия лица в пикселях
// =====================================================================

fileprivate struct FaceM {
    let c: [CGPoint]
    let eyeA: [CGPoint], eyeB: [CGPoint]
    let browA: [CGPoint], browB: [CGPoint]
    let nose: [CGPoint], lipsOut: [CGPoint], lipsIn: [CGPoint]
    let fw: CGFloat
    let chin: CGPoint
    let eyeMid: CGPoint
    let across: CGVector      // от левого глаза к правому
    let along: CGVector       // «вниз по лицу»
    let noseC: CGPoint
    var up: CGVector { CGVector(dx: -along.dx, dy: -along.dy) }

    init?(_ f: FaceGeo, _ W: CGFloat, _ H: CGFloat) {
        func px(_ a: [CGPoint]) -> [CGPoint] { a.map { CGPoint(x: $0.x * W, y: (1 - $0.y) * H) } }
        let contour = px(f.contour)
        guard contour.count > 4 else { return nil }
        var a = px(f.leftEye), b = px(f.rightEye)
        var ba = px(f.leftBrow), bb = px(f.rightBrow)
        if !a.isEmpty, !b.isEmpty, rtCentroid(a).x > rtCentroid(b).x { swap(&a, &b); swap(&ba, &bb) }
        c = contour
        eyeA = a; eyeB = b; browA = ba; browB = bb
        nose = px(f.nose); lipsOut = px(f.outerLips); lipsIn = px(f.innerLips)

        let box = rtBounds(contour)
        fw = box.width
        var ac = CGVector(dx: 1, dy: 0)
        var em = CGPoint(x: box.midX, y: box.minY + box.height * 0.4)
        if !a.isEmpty, !b.isEmpty {
            let ca = rtCentroid(a), cb = rtCentroid(b)
            em = rtMix(ca, cb, 0.5)
            ac = rtUnit(from: ca, to: cb)
        }
        across = ac
        eyeMid = em
        along = CGVector(dx: -ac.dy, dy: ac.dx)
        let al = along
        chin = contour.max { ($0.x - em.x) * al.dx + ($0.y - em.y) * al.dy < ($1.x - em.x) * al.dx + ($1.y - em.y) * al.dy } ?? contour[0]
        noseC = nose.isEmpty ? rtMix(em, chin, 0.5) : rtCentroid(nose)
    }
}

// =====================================================================
// MARK: - Рендер ретуши
// =====================================================================

enum RetouchRenderer {

    /// Все «магические» числа цветовой ретуши — здесь. Их придётся подкрутить на реальных лицах.
    enum Tuning {
        static let smoothGain: CGFloat = 12        // чем больше — тем сильнее сохраняются края
        static let wrinkleGain: CGFloat = 8
        static let acneGain: CGFloat = 10
        static let acneBias: CGFloat = -0.12
    }

    /// Вызывается из EditorCompositor.frame(...) сразу после нормализации origin (кадр уже «стоит прямо»).
    static func apply(_ s: RetouchSettings, to input: CIImage, track: RetouchTrack?, sourceTime: Double,
                      context: CIContext) -> CIImage {
        guard !s.isIdentity, let track = track else { return input }
        let ext = input.extent
        guard ext.width > 16, ext.height > 16 else { return input }

        var frame = track.frame(at: sourceTime)
        if frame == nil, RetouchStore.shared.blocking {
            frame = RetouchAnalyzer.analyzeInline(input, face: s.needsFace, body: s.needsBody,
                                                  context: context, track: track, sourceTime: sourceTime)
        }
        guard let f = frame else { return input }

        let W = ext.width, H = ext.height
        let faces = s.needsFace ? f.faces.compactMap { FaceM($0, W, H) } : []

        var img = input
        if !faces.isEmpty { img = colorPass(img, faces: faces, s: s) }

        var ops: [WarpOp] = []
        for m in faces { faceOps(m, s, into: &ops) }
        if s.needsBody { for b in f.bodies { bodyOps(b, s, W, H, into: &ops) } }
        if !ops.isEmpty { img = MetalWarp.shared.warp(img, ops: ops, context: context) }
        return img
    }

    // MARK: Маски

    private static func makeMask(_ W: CGFloat, _ H: CGFloat, _ draw: (CGContext, (CGPoint) -> CGPoint) -> Void) -> CIImage? {
        let mw = 384
        let mh = max(8, Int((CGFloat(mw) * H / W).rounded()))
        guard let ctx = CGContext(data: nil, width: mw, height: mh, bitsPerComponent: 8, bytesPerRow: mw,
                                  space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue)
        else { return nil }
        ctx.setFillColor(gray: 0, alpha: 1)
        ctx.fill(CGRect(x: 0, y: 0, width: mw, height: mh))
        let kx = CGFloat(mw) / W, ky = CGFloat(mh) / H
        // пиксели кадра (y вниз) -> пиксели маски (y вверх, как у CG/CI)
        draw(ctx) { CGPoint(x: $0.x * kx, y: (H - $0.y) * ky) }
        guard let cg = ctx.makeImage() else { return nil }
        return CIImage(cgImage: cg, options: [.colorSpace: NSNull()])
            .transformed(by: CGAffineTransform(scaleX: W / CGFloat(mw), y: H / CGFloat(mh)))
    }

    private static func fillPoly(_ ctx: CGContext, _ pts: [CGPoint], _ mp: (CGPoint) -> CGPoint) {
        guard pts.count > 2 else { return }
        ctx.addLines(between: pts.map(mp))
        ctx.closePath()
        ctx.fillPath()
    }

    private static func scaled(_ m: CIImage, _ k: Double) -> CIImage {
        let k = CGFloat(max(0, min(1, k)))
        return m.applyingFilter("CIColorMatrix", parameters: [
            "inputRVector": CIVector(x: k, y: 0, z: 0, w: 0),
            "inputGVector": CIVector(x: 0, y: k, z: 0, w: 0),
            "inputBVector": CIVector(x: 0, y: 0, z: k, w: 0),
            "inputAVector": CIVector(x: 0, y: 0, z: 0, w: 1),
            "inputBiasVector": CIVector(x: 0, y: 0, z: 0, w: 0)
        ])
    }

    private static func mul(_ a: CIImage, _ b: CIImage) -> CIImage {
        a.applyingFilter("CIMultiplyCompositing", parameters: [kCIInputBackgroundImageKey: b])
    }

    // MARK: Цветовая ретушь (в пределах прямоугольника лица — быстро)

    private static func colorPass(_ input: CIImage, faces: [FaceM], s: RetouchSettings) -> CIImage {
        let ext = input.extent, W = ext.width, H = ext.height
        let colorNeeded = s.smooth != 0 || s.acne != 0 || s.wrinkles != 0 || s.darkCircles != 0
            || s.shine != 0 || s.evenTone != 0 || s.teethWhiten != 0
        guard colorNeeded else { return input }

        // Прямоугольник работы: все лица + лоб
        var region = CGRect.null
        for m in faces {
            region = region.union(rtBounds(m.c))
            let top = rtShift(m.eyeMid, m.up, m.fw * 0.85)
            region = region.union(CGRect(x: top.x - 2, y: top.y - 2, width: 4, height: 4))
        }
        region = region.insetBy(dx: -region.width * 0.12, dy: -region.height * 0.1)
        let flipped = CGRect(x: region.minX, y: H - region.maxY, width: region.width, height: region.height)
        let rect = flipped.intersection(ext).integral.intersection(ext)
        guard !rect.isNull, rect.width > 16, rect.height > 16 else { return input }

        let fw = faces.map { $0.fw }.max() ?? 100
        var work = input.cropped(to: rect)

        func blur(_ i: CIImage, _ sigma: Double) -> CIImage {
            i.clampedToExtent().applyingGaussianBlur(sigma: max(0.5, sigma)).cropped(to: rect)
        }
        func blend(_ top: CIImage, _ bg: CIImage, _ mask: CIImage, _ k: Double) -> CIImage {
            top.applyingFilter("CIBlendWithMask", parameters: [
                kCIInputBackgroundImageKey: bg, kCIInputMaskImageKey: scaled(mask, k)
            ]).cropped(to: rect)
        }

        // Маска кожи: контур лица + лоб, минус глаза / брови / губы
        let skinRaw = makeMask(W, H) { ctx, mp in
            for m in faces {
                var poly = m.c
                let side: CGFloat = ((m.c.last!.x - m.c[0].x) * m.across.dx + (m.c.last!.y - m.c[0].y) * m.across.dy) >= 0 ? 1 : -1
                let top = rtShift(m.eyeMid, m.up, m.fw * 0.62)
                poly.append(rtShift(m.c.last!, m.up, m.fw * 0.3))
                poly.append(rtShift(top, m.across, m.fw * 0.32 * side))
                poly.append(top)
                poly.append(rtShift(top, m.across, -m.fw * 0.32 * side))
                poly.append(rtShift(m.c[0], m.up, m.fw * 0.3))
                ctx.setFillColor(gray: 1, alpha: 1)
                fillPoly(ctx, poly, mp)
                ctx.setFillColor(gray: 0, alpha: 1)
                fillPoly(ctx, rtExpand(m.eyeA, 1.6), mp)
                fillPoly(ctx, rtExpand(m.eyeB, 1.6), mp)
                fillPoly(ctx, rtExpand(m.browA, 1.25), mp)
                fillPoly(ctx, rtExpand(m.browB, 1.25), mp)
                fillPoly(ctx, rtExpand(m.lipsOut, 1.25), mp)
            }
        }
        let skin = skinRaw.map { blur($0.cropped(to: ext), Double(fw) * 0.025) }

        if let skin = skin {
            // Акне: локальные красные/тёмные пятна размазываем окружающей кожей
            if s.acne > 0 {
                let big = blur(work, Double(H) * 0.012)
                func redness(_ i: CIImage) -> CIImage {
                    i.applyingFilter("CIColorMatrix", parameters: [
                        "inputRVector": CIVector(x: 4, y: -4, z: 0, w: 0),
                        "inputGVector": CIVector(x: 4, y: -4, z: 0, w: 0),
                        "inputBVector": CIVector(x: 4, y: -4, z: 0, w: 0),
                        "inputAVector": CIVector(x: 0, y: 0, z: 0, w: 1),
                        "inputBiasVector": CIVector(x: 0.5, y: 0.5, z: 0.5, w: 0)
                    ])
                }
                func gray(_ i: CIImage) -> CIImage {
                    i.applyingFilter("CIColorMatrix", parameters: [
                        "inputRVector": CIVector(x: 0.33, y: 0.33, z: 0.33, w: 0),
                        "inputGVector": CIVector(x: 0.33, y: 0.33, z: 0.33, w: 0),
                        "inputBVector": CIVector(x: 0.33, y: 0.33, z: 0.33, w: 0),
                        "inputAVector": CIVector(x: 0, y: 0, z: 0, w: 1),
                        "inputBiasVector": CIVector(x: 0, y: 0, z: 0, w: 0)
                    ])
                }
                let dR = redness(work).applyingFilter("CIDifferenceBlendMode", parameters: [kCIInputBackgroundImageKey: redness(big)])
                let dL = gray(work).applyingFilter("CIDifferenceBlendMode", parameters: [kCIInputBackgroundImageKey: gray(big)])
                let g = Tuning.acneGain
                let spots = dR.applyingFilter("CIMaximumCompositing", parameters: [kCIInputBackgroundImageKey: dL])
                    .applyingFilter("CIColorMatrix", parameters: [
                        "inputRVector": CIVector(x: g, y: 0, z: 0, w: 0),
                        "inputGVector": CIVector(x: g, y: 0, z: 0, w: 0),
                        "inputBVector": CIVector(x: g, y: 0, z: 0, w: 0),
                        "inputAVector": CIVector(x: 0, y: 0, z: 0, w: 1),
                        "inputBiasVector": CIVector(x: Tuning.acneBias, y: Tuning.acneBias, z: Tuning.acneBias, w: 0)
                    ])
                    .applyingFilter("CIColorClamp", parameters: [
                        "inputMinComponents": CIVector(x: 0, y: 0, z: 0, w: 0),
                        "inputMaxComponents": CIVector(x: 1, y: 1, z: 1, w: 1)
                    ])
                    .applyingFilter("CIMorphologyMaximum", parameters: [kCIInputRadiusKey: 2])
                    .cropped(to: rect)
                let heal = blur(work, Double(H) * 0.006)
                work = blend(heal, work, mul(blur(spots, 1.5), skin.cropped(to: rect)), min(1, s.acne * 1.2))
            }

            // Мягкое сглаживание с сохранением краёв: размываем только там, где «детали» слабые
            func soften(_ img: CIImage, sigma: Double, gain: CGFloat, amount: Double) -> CIImage {
                let b = blur(img, sigma)
                let diff = img.applyingFilter("CIDifferenceBlendMode", parameters: [kCIInputBackgroundImageKey: b])
                let k = gain / 3
                let weight = diff.applyingFilter("CIColorMatrix", parameters: [
                    "inputRVector": CIVector(x: -k, y: -k, z: -k, w: 0),
                    "inputGVector": CIVector(x: -k, y: -k, z: -k, w: 0),
                    "inputBVector": CIVector(x: -k, y: -k, z: -k, w: 0),
                    "inputAVector": CIVector(x: 0, y: 0, z: 0, w: 1),
                    "inputBiasVector": CIVector(x: 1, y: 1, z: 1, w: 0)
                ]).applyingFilter("CIColorClamp", parameters: [
                    "inputMinComponents": CIVector(x: 0, y: 0, z: 0, w: 0),
                    "inputMaxComponents": CIVector(x: 1, y: 1, z: 1, w: 1)
                ])
                return blend(b, img, mul(weight, skin.cropped(to: rect)), amount)
            }
            if s.wrinkles > 0 {
                work = soften(work, sigma: Double(H) * 0.006, gain: Tuning.wrinkleGain, amount: s.wrinkles)
            }
            if s.smooth > 0 {
                work = soften(work, sigma: Double(H) * 0.004 * (0.6 + s.smooth), gain: Tuning.smoothGain, amount: s.smooth)
            }
            // Ровный тон: оставляем яркость, цвет берём из сильно размытого кадра
            if s.evenTone > 0 {
                let heavy = blur(work, Double(H) * 0.02)
                let toned = heavy.applyingFilter("CIColorBlendMode", parameters: [kCIInputBackgroundImageKey: work]).cropped(to: rect)
                work = blend(toned, work, skin.cropped(to: rect), s.evenTone * 0.85)
            }
            // Блеск: гасим света только на коже
            if s.shine > 0 {
                let calm = work.applyingFilter("CIHighlightShadowAdjust", parameters: [
                    "inputHighlightAmount": 1 - 0.7 * s.shine, "inputShadowAmount": 0
                ]).cropped(to: rect)
                work = blend(calm, work, skin.cropped(to: rect), s.shine)
            }
        }

        // Круги под глазами
        if s.darkCircles > 0, let raw = makeMask(W, H, { ctx, mp in
            let k = mp(CGPoint(x: 1, y: 0)).x - mp(CGPoint(x: 0, y: 0)).x
            ctx.setFillColor(gray: 1, alpha: 1)
            for m in faces {
                for eye in [m.eyeA, m.eyeB] where !eye.isEmpty {
                    let ew = rtBounds(eye).width
                    let p = mp(rtShift(rtCentroid(eye), m.along, ew * 0.8))
                    ctx.saveGState()
                    ctx.translateBy(x: p.x, y: p.y)
                    ctx.rotate(by: -CGFloat(atan2(m.across.dy, m.across.dx)))
                    ctx.fillEllipse(in: CGRect(x: -ew * 0.75 * k, y: -ew * 0.3 * k, width: ew * 1.5 * k, height: ew * 0.6 * k))
                    ctx.restoreGState()
                }
            }
        }) {
            let m = blur(raw.cropped(to: ext), Double(fw) * 0.05)
            let lifted = work.applyingFilter("CIColorControls", parameters: [
                kCIInputBrightnessKey: 0.08 * s.darkCircles, kCIInputSaturationKey: 1 - 0.15 * s.darkCircles
            ]).cropped(to: rect)
            work = blend(lifted, work, m, s.darkCircles)
        }

        // Зубы: внутренняя часть рта, только «не красное» (не язык и не губы)
        if s.teethWhiten > 0, let raw = makeMask(W, H, { ctx, mp in
            ctx.setFillColor(gray: 1, alpha: 1)
            for m in faces { fillPoly(ctx, rtExpand(m.lipsIn, 0.85), mp) }
        }) {
            let a = s.teethWhiten
            let m = blur(raw.cropped(to: ext), Double(fw) * 0.006)
            let gate = work.applyingFilter("CIColorMatrix", parameters: [
                "inputRVector": CIVector(x: -6, y: 6, z: 0, w: 0),
                "inputGVector": CIVector(x: -6, y: 6, z: 0, w: 0),
                "inputBVector": CIVector(x: -6, y: 6, z: 0, w: 0),
                "inputAVector": CIVector(x: 0, y: 0, z: 0, w: 1),
                "inputBiasVector": CIVector(x: 1, y: 1, z: 1, w: 0)
            ]).applyingFilter("CIColorClamp", parameters: [
                "inputMinComponents": CIVector(x: 0, y: 0, z: 0, w: 0),
                "inputMaxComponents": CIVector(x: 1, y: 1, z: 1, w: 1)
            ]).cropped(to: rect)
            let white = work.applyingFilter("CIColorControls", parameters: [
                kCIInputSaturationKey: 1 - 0.7 * a, kCIInputBrightnessKey: 0.07 * a
            ]).applyingFilter("CIColorMatrix", parameters: [
                "inputRVector": CIVector(x: 1, y: 0, z: 0, w: 0),
                "inputGVector": CIVector(x: 0, y: 1, z: 0, w: 0),
                "inputBVector": CIVector(x: 0, y: 0, z: CGFloat(1 + 0.12 * a), w: 0),
                "inputAVector": CIVector(x: 0, y: 0, z: 0, w: 1),
                "inputBiasVector": CIVector(x: 0, y: 0, z: 0, w: 0)
            ]).cropped(to: rect)
            work = blend(white, work, mul(m.cropped(to: rect), gate), 1)
        }

        return work.composited(over: input).cropped(to: ext)
    }

    // MARK: Деформация лица

    private static func faceOps(_ m: FaceM, _ s: RetouchSettings, into ops: inout [WarpOp]) {
        let fw = m.fw
        let up = m.up

        // Ширина лица (нижняя часть: скулы и челюсть)
        if s.faceWidth != 0 {
            ops.append(.make(1, c: rtMix(m.noseC, m.chin, 0.5), axis: m.along,
                             ra: rtDist(m.chin, m.noseC) * 1.3, rb: fw * 0.75, strength: -s.faceWidth * 0.16))
        }
        // Подбородок
        if s.chin != 0 {
            ops.append(.make(3, c: m.chin, axis: m.along, ra: fw * 0.3, rb: fw * 0.3,
                             vec: CGVector(dx: m.along.dx * fw * 0.08 * s.chin, dy: m.along.dy * fw * 0.08 * s.chin)))
        }
        // Глаза
        if s.eyeSize != 0 {
            for eye in [m.eyeA, m.eyeB] where !eye.isEmpty {
                let r = max(6, rtBounds(eye).width * 0.9)
                ops.append(.make(0, c: rtCentroid(eye), axis: m.along, ra: r, rb: r, strength: s.eyeSize * 0.35))
            }
        }
        // Нос
        if s.noseWidth != 0, !m.nose.isEmpty {
            let b = rtBounds(m.nose)
            ops.append(.make(1, c: rtCentroid(m.nose), axis: m.along, ra: max(8, b.height * 0.8), rb: max(8, b.width * 0.9),
                             strength: -s.noseWidth * 0.3))
        }
        // Губы
        if s.lips != 0, !m.lipsOut.isEmpty {
            let b = rtBounds(m.lipsOut)
            ops.append(.make(0, c: rtCentroid(m.lipsOut), axis: m.along, ra: b.width * 0.45, rb: b.width * 0.7,
                             strength: s.lips * 0.3))
        }
        // Улыбка: уголки губ вверх
        if s.smile != 0, !m.lipsOut.isEmpty {
            let b = rtBounds(m.lipsOut)
            let corners = [m.lipsOut.min { $0.x < $1.x }!, m.lipsOut.max { $0.x < $1.x }!]
            for p in corners {
                ops.append(.make(3, c: p, axis: m.along, ra: b.width * 0.3, rb: b.width * 0.3,
                                 vec: CGVector(dx: up.dx * b.width * 0.1 * s.smile, dy: up.dy * b.width * 0.1 * s.smile)))
            }
        }
        // Объём волос: приближение деформацией — вытягиваем контур головы наружу
        if s.hairVolume != 0 {
            ops.append(.make(0, c: rtShift(m.eyeMid, up, fw * 0.8), axis: m.along, ra: fw * 0.75, rb: fw * 0.95,
                             strength: s.hairVolume * 0.22))
            ops.append(.make(1, c: rtShift(m.eyeMid, up, fw * 0.35), axis: m.along, ra: fw * 0.6, rb: fw * 1.35,
                             strength: -s.hairVolume * 0.07))
        }
    }

    // MARK: Деформация тела

    private static func bodyOps(_ b: BodyGeo, _ s: RetouchSettings, _ W: CGFloat, _ H: CGFloat, into ops: inout [WarpOp]) {
        func J(_ j: Joint) -> CGPoint? { b.joints[j.rawValue].map { CGPoint(x: $0.x * W, y: (1 - $0.y) * H) } }
        let shL = J(.leftShoulder), shR = J(.rightShoulder), hpL = J(.leftHip), hpR = J(.rightHip)

        var sw: CGFloat = 0
        if let a = shL, let c = shR { sw = rtDist(a, c) }
        else if let a = hpL, let c = hpR { sw = rtDist(a, c) * 1.15 }
        guard sw > 12 else { return }

        /// Сужение/утолщение поперёк конечности.
        func limb(_ a: CGPoint?, _ c: CGPoint?, rb: CGFloat, k: Double) {
            guard k != 0, let a = a, let c = c else { return }
            let len = rtDist(a, c)
            guard len > 4 else { return }
            ops.append(.make(1, c: rtMix(a, c, 0.5), axis: rtUnit(from: a, to: c), ra: len * 0.6, rb: rb, strength: k))
        }

        // Торс
        if let a = shL, let c = shR, let d = hpL, let e = hpR {
            let shMid = rtMix(a, c, 0.5), hpMid = rtMix(d, e, 0.5)
            let ax = rtUnit(from: shMid, to: hpMid)
            let len = rtDist(shMid, hpMid)
            let hipW = rtDist(d, e)

            if s.bodyFat != 0 {
                ops.append(.make(1, c: rtMix(shMid, hpMid, 0.5), axis: ax, ra: len * 0.75, rb: max(sw, hipW) * 1.0,
                                 strength: -s.bodyFat * 0.25))
            }
            if s.waist != 0 {
                ops.append(.make(1, c: rtMix(shMid, hpMid, 0.62), axis: ax, ra: len * 0.28, rb: sw * 0.9,
                                 strength: -s.waist * 0.3))
            }
            if s.hips != 0 {
                ops.append(.make(1, c: hpMid, axis: ax, ra: len * 0.3, rb: max(hipW * 1.25, sw * 0.9),
                                 strength: -s.hips * 0.25))
            }
            let shK = -(s.shoulders * 0.2 + s.muscle * 0.12)
            if shK != 0 {
                ops.append(.make(1, c: rtShift(shMid, ax, len * 0.08), axis: ax, ra: len * 0.25, rb: sw * 1.0, strength: shK))
            }
            if s.muscle != 0 {
                ops.append(.make(1, c: rtMix(shMid, hpMid, 0.2), axis: ax, ra: len * 0.3, rb: sw * 0.95,
                                 strength: -s.muscle * 0.08))
            }
            // Длина ног: растягиваем зону бёдра → щиколотки
            if s.legLength != 0, let la = J(.leftAnkle), let ra = J(.rightAnkle) {
                let anMid = rtMix(la, ra, 0.5)
                let l = rtDist(hpMid, anMid)
                if l > 10 {
                    ops.append(.make(2, c: rtMix(hpMid, anMid, 0.5), axis: rtUnit(from: hpMid, to: anMid),
                                     ra: l * 0.6, rb: sw * 1.1, strength: s.legLength * 0.14))
                }
            }
        }

        // Руки
        let arms: [(Joint, Joint, Joint)] = [(.leftShoulder, .leftElbow, .leftWrist), (.rightShoulder, .rightElbow, .rightWrist)]
        for (sh, el, wr) in arms {
            limb(J(sh), J(el), rb: sw * 0.28, k: -(s.armsThick * 0.4 + s.muscle * 0.3))
            limb(J(el), J(wr), rb: sw * 0.24, k: -(s.forearms * 0.4 + s.muscle * 0.15))
        }
        // Ноги
        let legs: [(Joint, Joint, Joint)] = [(.leftHip, .leftKnee, .leftAnkle), (.rightHip, .rightKnee, .rightAnkle)]
        for (hp, kn, an) in legs {
            limb(J(hp), J(kn), rb: sw * 0.42, k: -s.legsThick * 0.3)
            limb(J(kn), J(an), rb: sw * 0.32, k: -s.legsThick * 0.3)
        }
    }
}
