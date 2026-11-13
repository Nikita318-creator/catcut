// MARK: - Views/EditPanelView.swift

import UIKit
import AVFoundation
import CoreImage
import CoreMedia
import SnapKit

// =====================================================================
// MARK: - Bottom panel (как в нормальных видеоредакторах)
// =====================================================================

struct PanelItem {
    var title: String
    var symbol: String? = nil
    var badge: String? = nil
    var image: UIImage? = nil
    var swatch: UIColor? = nil
    var on: Bool? = nil            // для переключателей (курсив, подчёркивание…)
    var fit: Bool = false          // картинка вписывается целиком (превью текста)
    var previewKey: String? = nil  // ленивое превью (переходы)
    var favorite: Bool? = nil      // nil — без сердечка
}

typealias PreviewProvider = (String, @escaping () -> Bool, @escaping (UIImage?) -> Void) -> Void

struct SliderConfig {
    var title: String
    var min: Float
    var max: Float
    var value: Float
    var format: (Float) -> String
}

final class PanelItemCell: UICollectionViewCell {
    static let reuseId = "PanelItemCell"

    private let box = UIView()
    private let imageView = UIImageView()
    private let iconView = UIImageView()
    private let badgeLabel = UILabel()
    private let swatchView = UIView()
    private let titleLabel = UILabel()
    private let heartButton = UIButton(type: .system)
    var onHeart: (() -> Void)?

    override init(frame: CGRect) {
        super.init(frame: frame)

        box.backgroundColor = Theme.surface
        box.layer.cornerRadius = 10
        box.clipsToBounds = true
        box.layer.borderColor = Theme.accent.cgColor
        contentView.addSubview(box)

        imageView.contentMode = .scaleAspectFill
        imageView.clipsToBounds = true
        box.addSubview(imageView)

        iconView.tintColor = .white
        iconView.contentMode = .scaleAspectFit
        box.addSubview(iconView)

        badgeLabel.textColor = .white
        badgeLabel.font = .systemFont(ofSize: 15, weight: .bold)
        badgeLabel.textAlignment = .center
        box.addSubview(badgeLabel)

        swatchView.layer.cornerRadius = 14
        swatchView.layer.borderWidth = 1
        swatchView.layer.borderColor = UIColor(white: 1, alpha: 0.4).cgColor
        box.addSubview(swatchView)

        titleLabel.font = .systemFont(ofSize: 10, weight: .medium)
        titleLabel.textColor = .lightGray
        titleLabel.textAlignment = .center
        titleLabel.numberOfLines = 2
        titleLabel.adjustsFontSizeToFitWidth = true
        titleLabel.minimumScaleFactor = 0.8
        contentView.addSubview(titleLabel)

        box.snp.makeConstraints { make in
            make.top.centerX.equalToSuperview()
            make.size.equalTo(56)
        }
        heartButton.addTarget(self, action: #selector(heartTapped), for: .touchUpInside)
        contentView.addSubview(heartButton)
        heartButton.snp.makeConstraints { make in
            make.top.equalTo(box).offset(-6)
            make.trailing.equalTo(box).offset(6)
            make.size.equalTo(26)
        }
        imageView.snp.makeConstraints { $0.edges.equalToSuperview() }
        iconView.snp.makeConstraints { make in make.center.equalToSuperview(); make.size.equalTo(24) }
        badgeLabel.snp.makeConstraints { $0.edges.equalToSuperview() }
        swatchView.snp.makeConstraints { make in make.center.equalToSuperview(); make.size.equalTo(28) }
        titleLabel.snp.makeConstraints { make in
            make.top.equalTo(box.snp.bottom).offset(5)
            make.leading.trailing.equalToSuperview()
        }
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private(set) var currentKey: String?

    @objc private func heartTapped() { onHeart?() }

    override func prepareForReuse() {
        super.prepareForReuse()
        currentKey = nil
        imageView.image = nil
    }

    func configure(_ item: PanelItem, selected: Bool, provider: PreviewProvider?) {
        titleLabel.text = item.title
        currentKey = item.previewKey
        imageView.contentMode = item.fit ? .scaleAspectFit : .scaleAspectFill
        imageView.image = item.image
        let hasImage = item.image != nil
        imageView.isHidden = !(hasImage || item.previewKey != nil)
        iconView.image = item.symbol.flatMap { UIImage(systemName: $0) }
        iconView.isHidden = item.symbol == nil || hasImage
        badgeLabel.text = item.badge
        badgeLabel.isHidden = item.badge == nil
        swatchView.backgroundColor = item.swatch
        swatchView.isHidden = item.swatch == nil
        heartButton.isHidden = item.favorite == nil
        let fav = item.favorite == true
        heartButton.setImage(UIImage(systemName: fav ? "heart.fill" : "heart"), for: .normal)
        heartButton.tintColor = fav ? .systemPink : UIColor(white: 1, alpha: 0.85)
        let hi = selected || item.on == true
        box.layer.borderWidth = hi ? 2.5 : 0
        titleLabel.textColor = hi ? Theme.accent : .lightGray

        if item.image == nil, let key = item.previewKey, let provider = provider {
            provider(key, { [weak self] in self?.currentKey == key }) { [weak self] img in
                guard let self = self, self.currentKey == key else { return }
                self.imageView.image = img
                self.imageView.isHidden = img == nil
                self.iconView.isHidden = img != nil
            }
        }
    }
}

final class EditPanelView: UIView, UICollectionViewDataSource, UICollectionViewDelegate {

    private let titleLabel = UILabel()
    private let closeButton = UIButton(type: .system)
    private let sliderRow = UIView()
    private let sliderCaption = UILabel()
    private let slider = UISlider()
    private let sliderValue = UILabel()
    private var collectionView: UICollectionView!

    private var items: [PanelItem] = []
    private var selectedIndex: Int?
    private var sliderConfig: SliderConfig?

    private let extraButton = UIButton(type: .system)
    private let chipsView = ChipsView()
    private var hasChips = false

    var onClose: (() -> Void)?
    var onExtra: (() -> Void)?
    var onChip: ((Int) -> Void)?
    var onSelect: ((Int) -> Void)?
    var previewProvider: PreviewProvider?
    var onFavorite: ((Int) -> Void)?
    var onSliderBegan: (() -> Void)?
    var onSliderChanged: ((Float) -> Void)?
    var onSliderEnded: ((Float) -> Void)?

    var preferredHeight: CGFloat { 38 + 106 + (sliderConfig == nil ? 0 : 34) + (hasChips ? 36 : 0) }

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = Theme.panel

        titleLabel.textColor = .white
        titleLabel.font = .systemFont(ofSize: 13, weight: .semibold)
        closeButton.setImage(UIImage(systemName: "checkmark"), for: .normal)
        closeButton.tintColor = .white
        closeButton.addTarget(self, action: #selector(closeTapped), for: .touchUpInside)

        sliderCaption.textColor = .lightGray
        sliderCaption.font = .systemFont(ofSize: 12)
        sliderValue.textColor = .white
        sliderValue.font = .monospacedDigitSystemFont(ofSize: 12, weight: .medium)
        sliderValue.textAlignment = .right
        slider.minimumTrackTintColor = Theme.accent
        slider.addTarget(self, action: #selector(sliderDown), for: .touchDown)
        slider.addTarget(self, action: #selector(sliderMoved), for: .valueChanged)
        slider.addTarget(self, action: #selector(sliderUp), for: [.touchUpInside, .touchUpOutside, .touchCancel])

        let layout = UICollectionViewFlowLayout()
        layout.scrollDirection = .horizontal
        layout.itemSize = CGSize(width: 66, height: 96)
        layout.minimumLineSpacing = 8
        layout.sectionInset = UIEdgeInsets(top: 4, left: 14, bottom: 0, right: 14)
        collectionView = UICollectionView(frame: .zero, collectionViewLayout: layout)
        collectionView.backgroundColor = .clear
        collectionView.showsHorizontalScrollIndicator = false
        collectionView.dataSource = self
        collectionView.delegate = self
        collectionView.register(PanelItemCell.self, forCellWithReuseIdentifier: PanelItemCell.reuseId)

        let header = UIView()
        header.addSubview(titleLabel)
        header.addSubview(closeButton)
        extraButton.setTitleColor(Theme.accent, for: .normal)
        extraButton.titleLabel?.font = .systemFont(ofSize: 13, weight: .semibold)
        extraButton.addTarget(self, action: #selector(extraTapped), for: .touchUpInside)
        extraButton.isHidden = true
        header.addSubview(extraButton)
        extraButton.snp.makeConstraints { make in
            make.trailing.equalTo(closeButton.snp.leading).offset(-4)
            make.centerY.equalToSuperview()
        }
        titleLabel.snp.makeConstraints { make in
            make.leading.equalToSuperview().offset(16)
            make.centerY.equalToSuperview()
            make.trailing.lessThanOrEqualTo(extraButton.snp.leading).offset(-8)
        }
        closeButton.snp.makeConstraints { make in
            make.trailing.equalToSuperview().inset(8)
            make.centerY.equalToSuperview()
            make.size.equalTo(40)
        }

        sliderRow.addSubview(sliderCaption)
        sliderRow.addSubview(slider)
        sliderRow.addSubview(sliderValue)
        sliderCaption.snp.makeConstraints { make in
            make.leading.equalToSuperview().offset(16)
            make.centerY.equalToSuperview()
            make.width.equalTo(60)
        }
        sliderValue.snp.makeConstraints { make in
            make.trailing.equalToSuperview().inset(16)
            make.centerY.equalToSuperview()
            make.width.equalTo(52)
        }
        slider.snp.makeConstraints { make in
            make.leading.equalTo(sliderCaption.snp.trailing).offset(4)
            make.trailing.equalTo(sliderValue.snp.leading).offset(-8)
            make.centerY.equalToSuperview()
        }

        let stack = UIStackView(arrangedSubviews: [header, chipsView, sliderRow, collectionView])
        stack.axis = .vertical
        addSubview(stack)
        stack.snp.makeConstraints { $0.edges.equalToSuperview() }
        header.snp.makeConstraints { $0.height.equalTo(38) }
        sliderRow.snp.makeConstraints { $0.height.equalTo(34) }
        chipsView.snp.makeConstraints { $0.height.equalTo(36) }
        chipsView.isHidden = true
        chipsView.onSelect = { [weak self] i in self?.onChip?(i) }
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func configure(title: String, items: [PanelItem], selected: Int?, slider cfg: SliderConfig?,
                   chips: [String]? = nil, selectedChip: Int = 0, extra: String? = nil, keepScroll: Bool = true) {
        titleLabel.text = title
        
        let itemsChanged = self.items.count != items.count
        self.items = items
        self.selectedIndex = selected
        self.sliderConfig = cfg
        sliderRow.isHidden = (cfg == nil)
        if let cfg = cfg {
            sliderCaption.text = cfg.title
            slider.minimumValue = cfg.min
            slider.maximumValue = cfg.max
            slider.value = cfg.value
            sliderValue.text = cfg.format(cfg.value)
        }
        hasChips = (chips != nil)
        chipsView.isHidden = (chips == nil)
        if let chips = chips { chipsView.configure(titles: chips, selected: selectedChip) }
        extraButton.isHidden = (extra == nil)
        extraButton.setTitle(extra, for: .normal)
        
        // ФИКС: Если количество элементов не изменилось, обновляем видимые ячейки «на лету»
        // без тяжелого reloadData(), который сбивает скролл нижней панели в ноль.
        if !itemsChanged {
            for cell in collectionView.visibleCells {
                if let indexPath = collectionView.indexPath(for: cell) {
                    (cell as? PanelItemCell)?.configure(items[indexPath.item], selected: indexPath.item == selectedIndex, provider: previewProvider)
                }
            }
        } else {
            collectionView.reloadData()
        }
        
        if !keepScroll {
            if let s = selected, s < items.count, s >= 0 {
                let maxPossibleIndex = max(0, items.count - 1)
                let targetIndex = min(s, maxPossibleIndex)
                collectionView.scrollToItem(at: IndexPath(item: targetIndex, section: 0), at: .centeredHorizontally, animated: false)
            } else {
                collectionView.setContentOffset(.zero, animated: false)
            }
        }
    }

    @objc private func extraTapped() { onExtra?() }
    @objc private func closeTapped() { onClose?() }
    @objc private func sliderDown() { onSliderBegan?() }
    @objc private func sliderMoved() {
        sliderValue.text = sliderConfig?.format(slider.value)
        onSliderChanged?(slider.value)
    }
    @objc private func sliderUp() { onSliderEnded?(slider.value) }

    // MARK: Collection

    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int { items.count }

    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(withReuseIdentifier: PanelItemCell.reuseId, for: indexPath) as! PanelItemCell
        cell.configure(items[indexPath.item], selected: indexPath.item == selectedIndex, provider: previewProvider)
        let index = indexPath.item
        cell.onHeart = { [weak self] in self?.onFavorite?(index) }
        return cell
    }

    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        onSelect?(indexPath.item)
    }
}
