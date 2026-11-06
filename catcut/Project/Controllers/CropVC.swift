// MARK: - Controllers/CropViewController.swift

import UIKit
import SnapKit

// =====================================================================
// MARK: - Рамка кадрирования: тянем края/углы/двигаем пальцем
// =====================================================================

final class CropOverlayView: UIView {
    var imageRect: CGRect = .zero
    private(set) var cropRect: CGRect = .zero
    /// nil — свободная рамка, иначе фиксированное соотношение (ширина / высота).
    var ratio: CGFloat?

    private let minSide: CGFloat = 60
    private var startRect = CGRect.zero
    private var startPoint = CGPoint.zero
    private var edges = (l: false, r: false, t: false, b: false)
    private var moving = false

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        isMultipleTouchEnabled = false
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func setCrop(normalized n: CGRect?) {
        if let n = n {
            cropRect = CGRect(x: imageRect.minX + n.minX * imageRect.width,
                              y: imageRect.minY + n.minY * imageRect.height,
                              width: n.width * imageRect.width,
                              height: n.height * imageRect.height)
        } else {
            cropRect = imageRect
        }
        setNeedsDisplay()
    }

    func normalized() -> CGRect {
        let c = cropRect, i = imageRect
        guard i.width > 0, i.height > 0 else { return CGRect(x: 0, y: 0, width: 1, height: 1) }
        let x = max(0, (c.minX - i.minX) / i.width)
        let y = max(0, (c.minY - i.minY) / i.height)
        let w = min(1 - x, c.width / i.width)
        let h = min(1 - y, c.height / i.height)
        return CGRect(x: x, y: y, width: w, height: h)
    }

    /// Подогнать рамку под соотношение сторон — максимально большую, по центру.
    func applyRatio(_ k: CGFloat?) {
        ratio = k
        guard let k = k, imageRect.width > 0 else { setNeedsDisplay(); return }
        var w = imageRect.width, h = w / k
        if h > imageRect.height { h = imageRect.height; w = h * k }
        cropRect = CGRect(x: imageRect.midX - w / 2, y: imageRect.midY - h / 2, width: w, height: h)
        setNeedsDisplay()
    }

    override func draw(_ rect: CGRect) {
        guard let ctx = UIGraphicsGetCurrentContext() else { return }

        // Затемнение вне рамки
        ctx.setFillColor(UIColor.black.withAlphaComponent(0.6).cgColor)
        ctx.addRect(imageRect)
        ctx.addRect(cropRect)
        ctx.drawPath(using: .eoFill)

        let r = cropRect

        // Сетка 3×3
        ctx.setStrokeColor(UIColor.white.withAlphaComponent(0.45).cgColor)
        ctx.setLineWidth(0.5)
        for i in 1...2 {
            let x = r.minX + r.width * CGFloat(i) / 3
            let y = r.minY + r.height * CGFloat(i) / 3
            ctx.move(to: CGPoint(x: x, y: r.minY)); ctx.addLine(to: CGPoint(x: x, y: r.maxY))
            ctx.move(to: CGPoint(x: r.minX, y: y)); ctx.addLine(to: CGPoint(x: r.maxX, y: y))
        }
        ctx.strokePath()

        // Рамка
        ctx.setStrokeColor(UIColor.white.cgColor)
        ctx.setLineWidth(1)
        ctx.stroke(r)

        // Уголки
        ctx.setLineWidth(4)
        ctx.setLineCap(.square)
        let L: CGFloat = 22
        let corners: [(CGFloat, CGFloat, CGFloat, CGFloat)] = [
            (r.minX, r.minY, 1, 1), (r.maxX, r.minY, -1, 1),
            (r.minX, r.maxY, 1, -1), (r.maxX, r.maxY, -1, -1)
        ]
        for (cx, cy, sx, sy) in corners {
            ctx.move(to: CGPoint(x: cx + sx * L, y: cy))
            ctx.addLine(to: CGPoint(x: cx, y: cy))
            ctx.addLine(to: CGPoint(x: cx, y: cy + sy * L))
        }
        ctx.strokePath()
    }

    // MARK: Touches

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let p = touches.first?.location(in: self) else { return }
        let th: CGFloat = 32
        let r = cropRect
        let inY = p.y > r.minY - th && p.y < r.maxY + th
        let inX = p.x > r.minX - th && p.x < r.maxX + th
        edges = (l: inY && abs(p.x - r.minX) < th,
                 r: inY && abs(p.x - r.maxX) < th,
                 t: inX && abs(p.y - r.minY) < th,
                 b: inX && abs(p.y - r.maxY) < th)
        if edges.l && edges.r { if abs(p.x - r.minX) < abs(p.x - r.maxX) { edges.r = false } else { edges.l = false } }
        if edges.t && edges.b { if abs(p.y - r.minY) < abs(p.y - r.maxY) { edges.b = false } else { edges.t = false } }
        moving = !(edges.l || edges.r || edges.t || edges.b) && r.contains(p)
        startRect = r
        startPoint = p
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let p = touches.first?.location(in: self) else { return }
        let dx = p.x - startPoint.x, dy = p.y - startPoint.y
        let b = imageRect

        if moving {
            var r = startRect.offsetBy(dx: dx, dy: dy)
            r.origin.x = min(max(r.origin.x, b.minX), b.maxX - r.width)
            r.origin.y = min(max(r.origin.y, b.minY), b.maxY - r.height)
            cropRect = r
        } else if edges.l || edges.r || edges.t || edges.b {
            var r = startRect
            if edges.l {
                let x = min(max(startRect.minX + dx, b.minX), startRect.maxX - minSide)
                r.origin.x = x; r.size.width = startRect.maxX - x
            }
            if edges.r {
                let x = max(min(startRect.maxX + dx, b.maxX), startRect.minX + minSide)
                r.size.width = x - startRect.minX
            }
            if edges.t {
                let y = min(max(startRect.minY + dy, b.minY), startRect.maxY - minSide)
                r.origin.y = y; r.size.height = startRect.maxY - y
            }
            if edges.b {
                let y = max(min(startRect.maxY + dy, b.maxY), startRect.minY + minSide)
                r.size.height = y - startRect.minY
            }

            if let k = ratio {
                // Фиксированное соотношение: якорь — противоположная сторона/угол
                var w = r.width, h = r.height
                if edges.l || edges.r { h = w / k } else { w = h * k }
                let ax = edges.l ? startRect.maxX : (edges.r ? startRect.minX : startRect.midX)
                let ay = edges.t ? startRect.maxY : (edges.b ? startRect.minY : startRect.midY)
                let maxW = edges.l ? ax - b.minX : (edges.r ? b.maxX - ax : 2 * min(ax - b.minX, b.maxX - ax))
                let maxH = edges.t ? ay - b.minY : (edges.b ? b.maxY - ay : 2 * min(ay - b.minY, b.maxY - ay))
                let s = min(1, maxW / w, maxH / h)
                w *= s; h *= s
                r = CGRect(x: edges.l ? ax - w : (edges.r ? ax : ax - w / 2),
                           y: edges.t ? ay - h : (edges.b ? ay : ay - h / 2),
                           width: w, height: h)
            }
            cropRect = r
        }
        setNeedsDisplay()
    }
}

// =====================================================================
// MARK: - Экран кадрирования
// =====================================================================

final class CropViewController: UIViewController {
    var image: UIImage!
    var initialCrop: CGRect?
    /// Вернёт нормализованную рамку (0...1, origin сверху-слева) или nil, если обрезка не нужна.
    var onApply: ((CGRect?) -> Void)?

    private let imageView = UIImageView()
    private let overlay = CropOverlayView()
    private let chipsScroll = UIScrollView()
    private var chipButtons: [UIButton] = []
    private var ratios: [(String, CGFloat?)] = []
    private var selectedRatio = 0
    private var didSetInitial = false

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = Theme.background

        ratios = [
            ("Свободно", nil),
            ("Оригинал", image.size.width / image.size.height),
            ("9:16", 9.0 / 16), ("1:1", 1), ("4:5", 4.0 / 5), ("3:4", 3.0 / 4), ("2:3", 2.0 / 3),
            ("16:9", 16.0 / 9), ("4:3", 4.0 / 3), ("3:2", 3.0 / 2), ("21:9", 21.0 / 9)
        ]

        // Верхняя панель
        let bar = UIView()
        view.addSubview(bar)
        bar.snp.makeConstraints { make in
            make.top.equalTo(view.safeAreaLayoutGuide)
            make.leading.trailing.equalToSuperview()
            make.height.equalTo(48)
        }
        let cancel = UIButton(type: .system)
        cancel.setTitle("Отмена", for: .normal)
        cancel.tintColor = .white
        cancel.addTarget(self, action: #selector(cancelTapped), for: .touchUpInside)
        let title = UILabel()
        title.text = "Кадрирование"
        title.textColor = .white
        title.font = .systemFont(ofSize: 17, weight: .bold)
        let apply = UIButton(type: .system)
        apply.setTitle("Готово", for: .normal)
        apply.titleLabel?.font = .boldSystemFont(ofSize: 17)
        apply.tintColor = Theme.accent
        apply.addTarget(self, action: #selector(applyTapped), for: .touchUpInside)
        [cancel, title, apply].forEach { bar.addSubview($0) }
        cancel.snp.makeConstraints { make in make.leading.equalToSuperview().offset(16); make.centerY.equalToSuperview() }
        title.snp.makeConstraints { $0.center.equalToSuperview() }
        apply.snp.makeConstraints { make in make.trailing.equalToSuperview().inset(16); make.centerY.equalToSuperview() }

        // Нижняя панель с форматами
        chipsScroll.showsHorizontalScrollIndicator = false
        view.addSubview(chipsScroll)
        chipsScroll.snp.makeConstraints { make in
            make.leading.trailing.equalToSuperview()
            make.bottom.equalTo(view.safeAreaLayoutGuide).inset(8)
            make.height.equalTo(40)
        }
        var prev: UIButton?
        for (i, r) in ratios.enumerated() {
            let b = UIButton(type: .system)
            b.setTitle(r.0, for: .normal)
            b.titleLabel?.font = .systemFont(ofSize: 14, weight: .semibold)
            b.layer.cornerRadius = 16
            b.contentEdgeInsets = UIEdgeInsets(top: 7, left: 14, bottom: 7, right: 14)
            b.tag = i
            b.addTarget(self, action: #selector(ratioTapped(_:)), for: .touchUpInside)
            chipsScroll.addSubview(b)
            b.snp.makeConstraints { make in
                make.centerY.equalToSuperview()
                if let p = prev { make.leading.equalTo(p.snp.trailing).offset(8) } else { make.leading.equalToSuperview().offset(16) }
                if i == ratios.count - 1 { make.trailing.equalToSuperview().inset(16) }
            }
            chipButtons.append(b)
            prev = b
        }

        // Картинка + рамка
        imageView.image = image
        imageView.contentMode = .scaleAspectFit
        view.addSubview(imageView)
        view.addSubview(overlay)
        imageView.snp.makeConstraints { make in
            make.top.equalTo(bar.snp.bottom).offset(8)
            make.leading.trailing.equalToSuperview().inset(16)
            make.bottom.equalTo(chipsScroll.snp.top).offset(-12)
        }
        overlay.snp.makeConstraints { $0.edges.equalTo(imageView) }

        updateChips()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        let c = imageView.bounds
        guard c.width > 0, c.height > 0, image.size.width > 0, image.size.height > 0 else { return }
        let s = min(c.width / image.size.width, c.height / image.size.height)
        let w = image.size.width * s, h = image.size.height * s
        let newRect = CGRect(x: (c.width - w) / 2, y: (c.height - h) / 2, width: w, height: h)

        if !didSetInitial {
            didSetInitial = true
            overlay.imageRect = newRect
            overlay.setCrop(normalized: initialCrop)
        } else if newRect != overlay.imageRect {
            let n = overlay.normalized()
            overlay.imageRect = newRect
            overlay.setCrop(normalized: n)
        }
    }

    private func updateChips() {
        for (i, b) in chipButtons.enumerated() {
            let on = i == selectedRatio
            b.backgroundColor = on ? Theme.accent : Theme.surface
            b.tintColor = on ? .black : .white
        }
    }

    @objc private func ratioTapped(_ b: UIButton) {
        selectedRatio = b.tag
        overlay.applyRatio(ratios[b.tag].1)
        updateChips()
    }

    @objc private func cancelTapped() { dismiss(animated: true) }

    @objc private func applyTapped() {
        let n = overlay.normalized()
        // Почти весь кадр выбран — обрезка не нужна
        let full = n.width > 0.995 && n.height > 0.995
        let result: CGRect? = full ? nil : n
        dismiss(animated: true) { [onApply] in onApply?(result) }
    }
}
