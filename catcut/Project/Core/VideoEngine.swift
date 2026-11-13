// MARK: - Core/VideoEngine.swift

import UIKit
import AVFoundation
import CoreImage
import CoreMedia
import Vision

// =====================================================================
// MARK: - Custom compositor: цвет, эффекты, фон, переходы, текст
// =====================================================================

struct LayerInfo {
    let trackID: CMPersistentTrackID
    let orientation: CGImagePropertyOrientation
    let preset: Adjustments?
    let intensity: Float
    let custom: Adjustments
    let look: VideoLook
    let flipH: Bool
    let flipV: Bool
    let rotation: Double
    let zoom: Double
    let bgMode: Int
    let bgImage: CIImage?
    let bgColor: CIColor?
    let bgDepthThreshold: Float
}

struct ProjectInfo {
    let fillMode: Int
    let blurBackground: Bool
    let introID: Int
    let introDuration: Double
    let outroID: Int
    let outroDuration: Double
    let total: Double
    /// Нормализованная обрезка (0...1, origin сверху-слева). nil — без обрезки.
    let crop: CGRect?
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
    let project: ProjectInfo

    init(timeRange: CMTimeRange, from: LayerInfo, to: LayerInfo?, transitionID: Int, texts: [TextOverlay], project: ProjectInfo) {
        self.timeRange = timeRange
        self.from = from
        self.to = to
        self.transitionID = transitionID
        self.texts = texts
        self.project = project
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
                let proj = instruction.project

                var output: CIImage
                if let toLayer = instruction.to {
                    let a = self.frame(for: instruction.from, request: request, rect: rect, time: time, project: proj)
                    let b = self.frame(for: toLayer, request: request, rect: rect, time: time, project: proj)
                    let start = instruction.timeRange.start.secs
                    let dur = max(0.001, instruction.timeRange.duration.secs)
                    let p = CGFloat(min(1, max(0, (time - start) / dur)))
                    output = TransitionRenderer.render(id: instruction.transitionID, from: a, to: b, t: p, rect: rect)
                } else {
                    output = self.frame(for: instruction.from, request: request, rect: rect, time: time, project: proj)
                }

                // Анимация появления в самом начале и затухания в самом конце
                let black = CIImage(color: CIColor.black).cropped(to: rect)
                if proj.introID != 0, proj.introDuration > 0.01, time < proj.introDuration {
                    output = TransitionRenderer.render(id: proj.introID, from: black, to: output,
                                                       t: CGFloat(time / proj.introDuration), rect: rect)
                }
                if proj.outroID != 0, proj.outroDuration > 0.01, time > proj.total - proj.outroDuration {
                    let p = (time - (proj.total - proj.outroDuration)) / proj.outroDuration
                    output = TransitionRenderer.render(id: proj.outroID, from: output, to: black,
                                                       t: CGFloat(min(1, max(0, p))), rect: rect)
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

    /// Маска человека (Vision). Работает на iOS 15+.
    /// Принимает уже ориентированный кадр (origin 0,0) — маска сразу совпадает с картинкой.
    private func personMask(_ img: CIImage) -> CIImage? {
        if #available(iOS 15.0, *) {
            let req = VNGeneratePersonSegmentationRequest()
            req.qualityLevel = .balanced
            req.outputPixelFormat = kCVPixelFormatType_OneComponent8
            let handler = VNImageRequestHandler(ciImage: img, options: [:])
            do { try handler.perform([req]) } catch { return nil }
            guard let obs = req.results?.first as? VNPixelBufferObservation else { return nil }
            return CIImage(cvPixelBuffer: obs.pixelBuffer)
        }
        return nil
    }

    /// Средняя яркость маски 0...1 — сколько кадра занимает человек.
    private func maskCoverage(_ mask: CIImage, extent e: CGRect) -> Double {
        let avg = mask.applyingFilter("CIAreaAverage", parameters: [kCIInputExtentKey: CIVector(cgRect: e)])
        var px = [UInt8](repeating: 0, count: 4)
        EditorCompositor.ciContext.render(avg, toBitmap: &px, rowBytes: 4,
                                          bounds: CGRect(x: 0, y: 0, width: 1, height: 1),
                                          format: .RGBA8, colorSpace: nil)
        return Double(px[0]) / 255
    }

    private func replaceBackground(_ img: CIImage, layer: LayerInfo) -> CIImage {
        guard let rawMask = personMask(img) else { return img }
        let e = img.extent
        let m0 = rawMask.extent
        guard m0.width > 0, m0.height > 0 else { return img }
        
        let mBase = CGRect(x: 0, y: 0, width: m0.width, height: m0.height)
        let t = Double(max(0, min(1, layer.bgDepthThreshold)))

        // 1) Блюр в родном разрешении маски: усредняет покадровый шум Vision
        //    и даёт градиент, по которому можно двигать границу.
        var mask = rawMask
            .transformed(by: CGAffineTransform(translationX: -m0.minX, y: -m0.minY))
            .clampedToExtent()
            .applyingGaussianBlur(sigma: Double(max(m0.width, m0.height)) * 0.04)
            .cropped(to: mBase)
            .transformed(by: CGAffineTransform(scaleX: e.width / m0.width, y: e.height / m0.height))
            .clampedToExtent()
        
        // 2) Порог. 0.5 = граница ровно там, где определил Vision.
        //    Вправо: порог ниже, область человека шире. Влево: порог выше, область уже.
        let cut = 0.5 - (t - 0.5) * 0.8
        let k = 12.0                       // резкость края: больше значение, резче край
        let b = CGFloat(0.5 - k * cut)
        
        mask = mask
            .applyingFilter("CIColorMatrix", parameters: [
                "inputRVector": CIVector(x: CGFloat(k), y: 0, z: 0, w: 0),
                "inputGVector": CIVector(x: CGFloat(k), y: 0, z: 0, w: 0),
                "inputBVector": CIVector(x: CGFloat(k), y: 0, z: 0, w: 0),
                "inputAVector": CIVector(x: 0, y: 0, z: 0, w: 1),
                "inputBiasVector": CIVector(x: b, y: b, z: b, w: 0)
            ])
            .applyingFilter("CIColorClamp", parameters: [
                "inputMinComponents": CIVector(x: 0, y: 0, z: 0, w: 0),
                "inputMaxComponents": CIVector(x: 1, y: 1, z: 1, w: 1)
            ])
            .cropped(to: e)
        
        // Человека в кадре нет — оставляем кадр как есть
        if maskCoverage(mask, extent: e) < 0.01 { return img }
        
        var bg: CIImage
        switch layer.bgMode {
        case 1:
            if let b = layer.bgImage {
                let be = b.extent
                let s = max(e.width / be.width, e.height / be.height)
                bg = b.transformed(by: CGAffineTransform(scaleX: s, y: s))
                let se = bg.extent
                bg = bg.transformed(by: CGAffineTransform(translationX: e.midX - se.midX, y: e.midY - se.midY)).cropped(to: e)
            } else {
                bg = img
            }
        case 2:
            bg = img.clampedToExtent().applyingGaussianBlur(sigma: Double(e.height) * 0.035).cropped(to: e)
        default:
            bg = CIImage(color: layer.bgColor ?? CIColor.black).cropped(to: e)
        }
        return img.applyingFilter("CIBlendWithMask", parameters: [
            kCIInputBackgroundImageKey: bg, kCIInputMaskImageKey: mask
        ]).cropped(to: e)
    }

    private func frame(for layer: LayerInfo, request: AVAsynchronousVideoCompositionRequest,
                       rect: CGRect, time: Double, project: ProjectInfo) -> CIImage {
        guard let pb = request.sourceFrame(byTrackID: layer.trackID) else { return black(rect) }

        var img = CIImage(cvPixelBuffer: pb).oriented(layer.orientation)
        let e0 = img.extent
        img = img.transformed(by: CGAffineTransform(translationX: -e0.origin.x, y: -e0.origin.y))

        // Обрезка краёв (кадрирование): режем исходник, разрешение = размер обрезанной области
        if let c = project.crop {
            let e = img.extent
            let r = CGRect(x: e.width * c.minX, y: e.height * (1 - c.maxY),
                           width: e.width * c.width, height: e.height * c.height)
            if r.width > 1, r.height > 1 {
                img = img.cropped(to: r).transformed(by: CGAffineTransform(translationX: -r.minX, y: -r.minY))
            }
        }
        let isFill = project.fillMode == 1 || project.crop != nil

        // Вырезаем человека и подставляем фон
        if layer.bgMode != 0 { img = replaceBackground(img, layer: layer) }

        // Фильтр (пресет с силой) + ручная настройка + живой эффект
        if let preset = layer.preset {
            let filtered = preset.apply(to: img, time: time)
            img = layer.intensity >= 0.99 ? filtered
                : opacity(filtered, CGFloat(layer.intensity)).composited(over: img).cropped(to: img.extent)
        }
        if !layer.custom.isIdentity { img = layer.custom.apply(to: img, time: time) }
        if layer.look != .none { img = layer.look.apply(to: img, time: time) }

        // Формат кадра: вписать или заполнить
        let w = img.extent.width, h = img.extent.height
        guard w > 0, h > 0 else { return black(rect) }
        let fit = min(rect.width / w, rect.height / h)
        let fill = max(rect.width / w, rect.height / h)
        let s = isFill ? fill : fit

        var placed = img.transformed(by: CGAffineTransform(scaleX: s, y: s))
        let pe = placed.extent
        placed = placed.transformed(by: CGAffineTransform(translationX: rect.midX - pe.midX, y: rect.midY - pe.midY))

        // Отражение / поворот / масштаб (вокруг центра кадра)
        if layer.flipH || layer.flipV || layer.rotation != 0 || layer.zoom != 1 {
            // при повороте в режиме «вписать» сами уменьшаем, чтобы картинка не обрезалась
            var auto: CGFloat = 1
            if !isFill && layer.rotation != 0 {
                let th = CGFloat(layer.rotation) * .pi / 180
                let bw = abs(pe.width * cos(th)) + abs(pe.height * sin(th))
                let bh = abs(pe.width * sin(th)) + abs(pe.height * cos(th))
                if bw > 0 && bh > 0 { auto = min(1, rect.width / bw, rect.height / bh) }
            }
            let z = CGFloat(layer.zoom) * auto
            var t = CGAffineTransform(translationX: -rect.midX, y: -rect.midY)
            t = t.concatenating(CGAffineTransform(scaleX: layer.flipH ? -z : z, y: layer.flipV ? -z : z))
            t = t.concatenating(CGAffineTransform(rotationAngle: -CGFloat(layer.rotation) * .pi / 180))
            t = t.concatenating(CGAffineTransform(translationX: rect.midX, y: rect.midY))
            placed = placed.transformed(by: t)
        }

        // Фон кадра: чёрный или размытая копия видео
        var base = black(rect)
        if !isFill && project.blurBackground {
            let sf = fill
            var bgImg = img.transformed(by: CGAffineTransform(scaleX: sf, y: sf))
            let be = bgImg.extent
            bgImg = bgImg.transformed(by: CGAffineTransform(translationX: rect.midX - be.midX, y: rect.midY - be.midY))
            base = bgImg.clampedToExtent()
                .applyingGaussianBlur(sigma: Double(rect.height) * 0.03)
                .applyingFilter("CIColorControls", parameters: [kCIInputBrightnessKey: -0.18])
                .cropped(to: rect)
        }
        return placed.composited(over: base).cropped(to: rect)
    }
}
