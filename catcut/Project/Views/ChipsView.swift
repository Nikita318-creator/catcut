import UIKit
import SnapKit

final class ChipsView: UIView {
    private let scroll = UIScrollView()
    private let stack = UIStackView()
    private var buttons: [UIButton] = []
    var onSelect: ((Int) -> Void)?

    override init(frame: CGRect) {
        super.init(frame: frame)
        scroll.showsHorizontalScrollIndicator = false
        addSubview(scroll)
        scroll.snp.makeConstraints { $0.edges.equalToSuperview() }
        stack.axis = .horizontal
        stack.spacing = 8
        scroll.addSubview(stack)
        stack.snp.makeConstraints { make in
            make.edges.equalToSuperview().inset(UIEdgeInsets(top: 3, left: 14, bottom: 3, right: 14))
            make.height.equalToSuperview().offset(-6)
        }
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func configure(titles: [String], selected: Int) {
        if buttons.count != titles.count {
            buttons.forEach { $0.removeFromSuperview() }
            buttons = titles.enumerated().map { (i, t) -> UIButton in
                let b = UIButton(type: .system)
                b.setTitle(t, for: .normal)
                b.titleLabel?.font = .systemFont(ofSize: 12, weight: .semibold)
                b.layer.cornerRadius = 13
                b.contentEdgeInsets = UIEdgeInsets(top: 4, left: 12, bottom: 4, right: 12)
                b.tag = i
                b.addTarget(self, action: #selector(tapped(_:)), for: .touchUpInside)
                stack.addArrangedSubview(b)
                return b
            }
        }
        for (i, b) in buttons.enumerated() {
            let on = i == selected
            b.backgroundColor = on ? Theme.accent : Theme.surface
            b.setTitleColor(on ? .black : .white, for: .normal)
        }
        if selected < buttons.count {
            let f = buttons[selected].frame
            scroll.scrollRectToVisible(f.insetBy(dx: -30, dy: 0), animated: false)
        }
    }

    @objc private func tapped(_ b: UIButton) { onSelect?(b.tag) }
}
