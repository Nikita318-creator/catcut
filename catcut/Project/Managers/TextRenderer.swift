// MARK: - Managers/TextRenderer.swift

import UIKit
import CoreImage

// =====================================================================
// MARK: - Text renderer (одинаковый код для превью и экспорта)
// =====================================================================

enum TextRenderer {
    private static let cache = NSCache<NSString, CIImage>()

    struct Layout {
        let size: CGSize
        let bound: CGSize
        let pad: CGFloat
        let fontSize: CGFloat
    }

    private static func attributed(_ o: TextOverlay, fontSize fs: CGFloat, fill: UIColor, stroke: UIColor? = nil,
                                   strokeWidth: CGFloat = 0, visible: Int? = nil, shadow: NSShadow? = nil) -> NSAttributedString {
        let para = NSMutableParagraphStyle()
        para.alignment = o.alignment == 0 ? .left : (o.alignment == 2 ? .right : .center)

        func attrs(_ color: UIColor) -> [NSAttributedString.Key: Any] {
            var a: [NSAttributedString.Key: Any] = [
                .font: TextFonts.font(o, size: fs),
                .foregroundColor: color,
                .paragraphStyle: para
            ]
            if o.letterSpacing != 0 { a[.kern] = o.letterSpacing * fs }
            if o.italic { a[.obliqueness] = 0.22 }
            if o.underline { a[.underlineStyle] = NSUnderlineStyle.single.rawValue }
            if o.strike { a[.strikethroughStyle] = NSUnderlineStyle.single.rawValue }
            if let st = stroke {
                // отрицательная ширина = заливка + обводка; foreground должен быть цвета обводки
                a[.strokeColor] = st
                a[.strokeWidth] = -(strokeWidth * 200)
            }
            if let sh = shadow { a[.shadow] = sh }
            return a
        }

        let result = NSMutableAttributedString(string: o.text, attributes: attrs(fill))
        if let v = visible {
            let chars = Array(o.text)
            if v < chars.count {
                let prefix = String(chars[0..<max(0, v)])
                let start = (prefix as NSString).length
                let total = (o.text as NSString).length
                if start < total {
                    var hidden = attrs(.clear)
                    if stroke != nil { hidden[.strokeColor] = UIColor.clear }
                    result.setAttributes(hidden, range: NSRange(location: start, length: total - start))
                }
            }
        }
        return result
    }

    static func layout(_ o: TextOverlay, canvas: CGSize) -> Layout {
        let fs = max(8, o.size * canvas.height)
        let attr = attributed(o, fontSize: fs, fill: .white)
        let rect = attr.boundingRect(with: CGSize(width: canvas.width * 0.9, height: .greatestFiniteMagnitude),
                                     options: [.usesLineFragmentOrigin, .usesFontLeading], context: nil)
        let bound = CGSize(width: ceil(rect.width) + 2, height: ceil(rect.height))
        let pad = fs * 0.9
        return Layout(size: CGSize(width: bound.width + pad * 2, height: bound.height + pad * 2),
                      bound: bound, pad: pad, fontSize: fs)
    }

    static func pixelSize(for o: TextOverlay, canvas: CGSize) -> CGSize { layout(o, canvas: canvas).size }

    private static func shadowObject(_ o: TextOverlay, fs: CGFloat) -> NSShadow? {
        guard let style = TextShadow(rawValue: o.shadow), style != .none else { return nil }
        let base = TextPalette.color(o.shadowColorIndex)
        let sh = NSShadow()
        switch style {
        case .none: return nil
        case .soft:
            sh.shadowOffset = CGSize(width: 0, height: fs * 0.05); sh.shadowBlurRadius = fs * 0.12
            sh.shadowColor = base.withAlphaComponent(0.7)
        case .hard:
            sh.shadowOffset = CGSize(width: fs * 0.06, height: fs * 0.06); sh.shadowBlurRadius = 0
            sh.shadowColor = base
        case .far:
            sh.shadowOffset = CGSize(width: fs * 0.12, height: fs * 0.12); sh.shadowBlurRadius = 0
            sh.shadowColor = base
        case .deep:
            sh.shadowOffset = CGSize(width: 0, height: fs * 0.12); sh.shadowBlurRadius = fs * 0.25
            sh.shadowColor = base.withAlphaComponent(0.85)
        case .lift:
            sh.shadowOffset = CGSize(width: fs * 0.03, height: fs * 0.1); sh.shadowBlurRadius = fs * 0.18
            sh.shadowColor = base.withAlphaComponent(0.5)
        case .halo:
            sh.shadowOffset = .zero; sh.shadowBlurRadius = fs * 0.28
            sh.shadowColor = base
        }
        return sh
    }

    static func uiImage(for o: TextOverlay, canvas: CGSize, visible: Int? = nil) -> UIImage {
        let l = layout(o, canvas: canvas)
        let fs = l.fontSize
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = false
        let opts: NSStringDrawingOptions = [.usesLineFragmentOrigin, .usesFontLeading]

        return UIGraphicsImageRenderer(size: l.size, format: format).image { ctx in
            let cg = ctx.cgContext
            let textRect = CGRect(x: l.pad, y: l.pad, width: l.bound.width, height: l.bound.height)

            if o.boxIndex >= 0 {
                let r = textRect.insetBy(dx: -fs * 0.4, dy: -fs * 0.18)
                cg.setFillColor(TextPalette.color(o.boxIndex).withAlphaComponent(CGFloat(o.boxOpacity)).cgColor)
                cg.addPath(UIBezierPath(roundedRect: r, cornerRadius: fs * 0.28).cgPath)
                cg.fillPath()
            }

            if o.glowIndex >= 0 {
                let gc = TextPalette.color(o.glowIndex)
                for k in [CGFloat(0.7), 0.35, 0.12] {
                    let sh = NSShadow()
                    sh.shadowOffset = .zero
                    sh.shadowBlurRadius = fs * k
                    sh.shadowColor = gc
                    attributed(o, fontSize: fs, fill: gc, visible: visible, shadow: sh)
                        .draw(with: textRect, options: opts, context: nil)
                }
            }

            let fillColor = TextPalette.color(o.fillIndex)
            let shadow = shadowObject(o, fs: fs)
            if o.strokeIndex >= 0 {
                let sc = TextPalette.color(o.strokeIndex)
                attributed(o, fontSize: fs, fill: sc, stroke: sc, strokeWidth: o.strokeWidth, visible: visible, shadow: shadow)
                    .draw(with: textRect, options: opts, context: nil)
                attributed(o, fontSize: fs, fill: fillColor, visible: visible)
                    .draw(with: textRect, options: opts, context: nil)
            } else {
                attributed(o, fontSize: fs, fill: fillColor, visible: visible, shadow: shadow)
                    .draw(with: textRect, options: opts, context: nil)
            }
        }
    }

    private static func key(_ o: TextOverlay, canvas: CGSize, visible: Int?) -> NSString {
        "\(o.text)|\(o.size)|\(o.fillIndex)|\(o.strokeIndex)|\(o.strokeWidth)|\(o.shadow)|\(o.shadowColorIndex)|\(o.glowIndex)|\(o.boxIndex)|\(o.boxOpacity)|\(o.fontIndex)|\(o.weight)|\(o.italic)|\(o.underline)|\(o.strike)|\(o.alignment)|\(o.letterSpacing)|\(Int(canvas.width))x\(Int(canvas.height))|\(visible ?? -1)" as NSString
    }

    static func image(for o: TextOverlay, canvas: CGSize, visible: Int? = nil) -> CIImage? {
        let k = key(o, canvas: canvas, visible: visible)
        if let cached = cache.object(forKey: k) { return cached }
        guard let cg = uiImage(for: o, canvas: canvas, visible: visible).cgImage else { return nil }
        let ci = CIImage(cgImage: cg)
        cache.setObject(ci, forKey: k)
        return ci
    }
}
