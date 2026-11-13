// MARK: - Views/ToolBar.swift

import UIKit
import AVFoundation
import CoreImage
import CoreMedia
import SnapKit

// =====================================================================
// MARK: - Main tools bar
// =====================================================================

enum EditorTool: CaseIterable {
    case addVideo, overlay, split, delete, duplicate, speed, filter, adjust, transition, animation, effects, frame, background, text, audio

    var title: String {
        switch self {
        case .addVideo: return "Добавить"
        case .overlay: return "Overlay" // <-- Новая кнопка на панели
        case .split: return "Разрезать"
        case .delete: return "Удалить"
        case .duplicate: return "Дубль"
        case .speed: return "Скорость"
        case .filter: return "Фильтры"
        case .adjust: return "Цвет"
        case .transition: return "Переходы"
        case .animation: return "Анимация"
        case .effects: return "Эффекты"
        case .frame: return "Кадр"
        case .background: return "Фон"
        case .text: return "Текст"
        case .audio: return "Аудио"
        }
    }

    var symbol: String {
        switch self {
        case .addVideo: return "plus.square"
        case .overlay: return "pip.enter" // <-- Иконка «картинка в картинке»
        case .split: return "scissors"
        case .delete: return "trash"
        case .duplicate: return "plus.square.on.square"
        case .speed: return "speedometer"
        case .filter: return "camera.filters"
        case .adjust: return "slider.horizontal.3"
        case .transition: return "rectangle.on.rectangle"
        case .animation: return "wand.and.stars"
        case .effects: return "sparkles"
        case .frame: return "crop"
        case .background: return "person.crop.square"
        case .text: return "textformat"
        case .audio: return "music.note"
        }
    }
}

final class ToolCell: UICollectionViewCell {
    static let reuseId = "ToolCell"
    private let iconView = UIImageView()
    private let titleLabel = UILabel()

    override init(frame: CGRect) {
        super.init(frame: frame)
        iconView.tintColor = .white
        iconView.contentMode = .scaleAspectFit
        titleLabel.textColor = .lightGray
        titleLabel.font = .systemFont(ofSize: 13, weight: .medium)
        titleLabel.textAlignment = .center
        titleLabel.adjustsFontSizeToFitWidth = true
        titleLabel.minimumScaleFactor = 0.8
        let stack = UIStackView(arrangedSubviews: [iconView, titleLabel])
        stack.axis = .vertical
        stack.spacing = 7
        stack.alignment = .center
        contentView.addSubview(stack)
        stack.snp.makeConstraints { make in
            make.center.equalToSuperview()
            make.leading.greaterThanOrEqualToSuperview().offset(2)
            make.trailing.lessThanOrEqualToSuperview().offset(-2)
        }
        iconView.snp.makeConstraints { $0.size.equalTo(34) }
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func configure(_ tool: EditorTool) {
        iconView.image = UIImage(systemName: tool.symbol)
        titleLabel.text = tool.title
    }
}
