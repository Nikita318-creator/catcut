// MARK: - Views/ExportOverlay.swift

import UIKit
import AVFoundation
import CoreImage
import CoreMedia
import SnapKit

// =====================================================================
// MARK: - Export overlay
// =====================================================================

final class ExportOverlay: UIView {
    private let card = UIView()
    private let label = UILabel()
    private let progress = UIProgressView(progressViewStyle: .default)
    private let cancel = UIButton(type: .system)
    var onCancel: (() -> Void)?

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = UIColor.black.withAlphaComponent(0.6)
        card.backgroundColor = UIColor(white: 0.15, alpha: 1)
        card.layer.cornerRadius = 16
        addSubview(card)

        label.text = "Экспорт видео…"
        label.textColor = .white
        label.font = .systemFont(ofSize: 16, weight: .semibold)
        label.textAlignment = .center
        progress.progressTintColor = Theme.accent
        cancel.setTitle("Отмена", for: .normal)
        cancel.addTarget(self, action: #selector(cancelTapped), for: .touchUpInside)

        let stack = UIStackView(arrangedSubviews: [label, progress, cancel])
        stack.axis = .vertical
        stack.spacing = 16
        card.addSubview(stack)

        card.snp.makeConstraints { make in
            make.center.equalToSuperview()
            make.width.equalTo(260)
        }
        stack.snp.makeConstraints { $0.edges.equalToSuperview().inset(20) }
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func setProgress(_ p: Float) {
        progress.progress = p
        label.text = "Экспорт видео… \(Int(p * 100))%"
    }
    @objc private func cancelTapped() { onCancel?() }
}
