// MARK: - Controllers/DraftsViewController.swift

import UIKit
import AVFoundation
import CoreImage
import CoreMedia
import SnapKit

final class DraftCell: UITableViewCell {
    static let reuseId = "DraftCell"
    let cover = UIImageView()
    let titleLabel = UILabel()
    let subLabel = UILabel()

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        backgroundColor = Theme.background
        contentView.backgroundColor = Theme.background
        cover.contentMode = .scaleAspectFill
        cover.clipsToBounds = true
        cover.layer.cornerRadius = 8
        cover.backgroundColor = Theme.surface
        titleLabel.textColor = .white
        titleLabel.font = .systemFont(ofSize: 16, weight: .semibold)
        subLabel.textColor = .lightGray
        subLabel.font = .systemFont(ofSize: 13)
        contentView.addSubview(cover)
        contentView.addSubview(titleLabel)
        contentView.addSubview(subLabel)
        cover.snp.makeConstraints { make in
            make.leading.equalToSuperview().offset(16)
            make.top.bottom.equalToSuperview().inset(10)
            make.size.equalTo(76)
        }
        titleLabel.snp.makeConstraints { make in
            make.leading.equalTo(cover.snp.trailing).offset(14)
            make.trailing.equalToSuperview().inset(16)
            make.bottom.equalTo(contentView.snp.centerY).offset(-2)
        }
        subLabel.snp.makeConstraints { make in
            make.leading.equalTo(titleLabel)
            make.trailing.equalToSuperview().inset(16)
            make.top.equalTo(contentView.snp.centerY).offset(2)
        }
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
}

final class DraftsViewController: UIViewController, UITableViewDataSource, UITableViewDelegate {
    var onOpen: ((Draft) -> Void)?
    var onNew: (() -> Void)?
    var onDeleted: ((UUID) -> Void)?
    var currentDraftID: UUID?

    private let tableView = UITableView()
    private let emptyLabel = UILabel()
    private var drafts: [Draft] = []

    private lazy var formatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "ru_RU")
        f.dateFormat = "d MMM, HH:mm"
        return f
    }()

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = Theme.background

        let bar = UIView()
        view.addSubview(bar)
        bar.snp.makeConstraints { make in
            make.top.equalTo(view.safeAreaLayoutGuide)
            make.leading.trailing.equalToSuperview()
            make.height.equalTo(48)
        }
        let close = UIButton(type: .system)
        close.setTitle("Закрыть", for: .normal)
        close.tintColor = .white
        close.addTarget(self, action: #selector(closeTapped), for: .touchUpInside)
        let title = UILabel()
        title.text = "Черновики"
        title.textColor = .white
        title.font = .systemFont(ofSize: 17, weight: .bold)
        let new = UIButton(type: .system)
        new.setTitle("＋ Новый", for: .normal)
        new.tintColor = Theme.accent
        new.addTarget(self, action: #selector(newTapped), for: .touchUpInside)
        [close, title, new].forEach { bar.addSubview($0) }
        close.snp.makeConstraints { make in make.leading.equalToSuperview().offset(16); make.centerY.equalToSuperview() }
        title.snp.makeConstraints { $0.center.equalToSuperview() }
        new.snp.makeConstraints { make in make.trailing.equalToSuperview().inset(16); make.centerY.equalToSuperview() }

        tableView.backgroundColor = Theme.background
        tableView.separatorColor = UIColor(white: 1, alpha: 0.08)
        tableView.dataSource = self
        tableView.delegate = self
        tableView.register(DraftCell.self, forCellReuseIdentifier: DraftCell.reuseId)
        view.addSubview(tableView)
        tableView.snp.makeConstraints { make in
            make.top.equalTo(bar.snp.bottom)
            make.leading.trailing.bottom.equalToSuperview()
        }

        emptyLabel.text = "Пока нет черновиков.\nНажмите «сохранить» в редакторе —\nи они появятся здесь."
        emptyLabel.numberOfLines = 0
        emptyLabel.textAlignment = .center
        emptyLabel.textColor = .gray
        view.addSubview(emptyLabel)
        emptyLabel.snp.makeConstraints { $0.center.equalToSuperview() }

        reload()
    }

    private func reload() {
        let allDrafts = DraftStore.shared.list()
        // Сортировка: автосохраненный всегда первый (isAutoSaved == true), остальные по дате (updated)
        drafts = allDrafts.sorted { d1, d2 in
            if d1.isAutoSaved == true && d2.isAutoSaved != true { return true }
            if d1.isAutoSaved != true && d2.isAutoSaved == true { return false }
            return d1.updated > d2.updated
        }
        emptyLabel.isHidden = !drafts.isEmpty
        tableView.reloadData()
    }

    @objc private func closeTapped() { dismiss(animated: true) }
    @objc private func newTapped() {
        dismiss(animated: true) { [onNew] in onNew?() }
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int { drafts.count }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: DraftCell.reuseId, for: indexPath) as! DraftCell
        let d = drafts[indexPath.row]
        cell.cover.image = UIImage(contentsOfFile: DraftStore.shared.coverURL(d.id).path)
        let isCurrent = d.id == currentDraftID
        
        let prefix = (d.isAutoSaved == true ? "💾 [Авто] " : "") + (isCurrent ? "● " : "")
        cell.titleLabel.text = prefix + formatter.string(from: d.updated)
        
        let total = Int(d.duration)
        cell.subLabel.text = String(format: "%d клип., %d:%02d", d.clips.count, total / 60, total % 60)
            + (d.texts.isEmpty ? "" : " · текст \(d.texts.count)")
            + (d.audios.isEmpty ? "" : " · аудио \(d.audios.count)")
        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        let d = drafts[indexPath.row]
        onOpen?(d)
    }

    func tableView(_ tableView: UITableView, commit editingStyle: UITableViewCell.EditingStyle, forRowAt indexPath: IndexPath) {
        guard editingStyle == .delete else { return }
        let d = drafts[indexPath.row]
        DraftStore.shared.delete(d.id)
        drafts.remove(at: indexPath.row)
        tableView.deleteRows(at: [indexPath], with: .automatic)
        emptyLabel.isHidden = !drafts.isEmpty
        onDeleted?(d.id)
    }
}
