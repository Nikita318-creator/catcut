// MARK: - Controllers/ViewController+Subtitles.swift

import UIKit
import Speech

extension ViewController {

    static let subtitleLocaleKey = "subtitleLocaleID"

    /// Последний выбранный язык, иначе язык устройства.
    var subtitleLocale: Locale {
        if let id = UserDefaults.standard.string(forKey: ViewController.subtitleLocaleKey) { return Locale(identifier: id) }
        return Locale.preferredLanguages.first.map { Locale(identifier: $0) } ?? Locale.current
    }

    func languageName(_ l: Locale) -> String {
        (Locale.current.localizedString(forIdentifier: l.identifier) ?? l.identifier).capitalized
    }

    func didTapAutoSubtitles() {
        guard requireClips(), build != nil else { return }
        pausePlayback()
        let loc = subtitleLocale
        let name = languageName(loc)
        let sheet = UIAlertController(title: "Автосубтитры",
                                      message: "Язык речи: \(name)\nТекст распознаётся из звука видео и аудиодорожек",
                                      preferredStyle: .actionSheet)
        sheet.addAction(UIAlertAction(title: "Распознать (\(name))", style: .default) { [weak self] _ in
            self?.startAutoSubtitles(locale: loc)
        })
        sheet.addAction(UIAlertAction(title: "Выбрать другой язык…", style: .default) { [weak self] _ in
            self?.pickSubtitleLanguage(current: loc)
        })
        sheet.addAction(UIAlertAction(title: "Отмена", style: .cancel))
        sheet.popoverPresentationController?.sourceView = view
        sheet.popoverPresentationController?.sourceRect = CGRect(x: view.bounds.midX, y: view.bounds.maxY - 80, width: 1, height: 1)
        present(sheet, animated: true)
    }

    func pickSubtitleLanguage(current: Locale) {
        let vc = SubtitleLanguageViewController(current: current)
        vc.onPick = { [weak self] locale in self?.startAutoSubtitles(locale: locale) }
        let nav = UINavigationController(rootViewController: vc)
        nav.overrideUserInterfaceStyle = .dark
        present(nav, animated: true)
    }

    func startAutoSubtitles(locale: Locale) {
        guard let b = build else { return }
        let key = "subtitles"
        guard !processingKeys.contains(key) else { showToast("Субтитры уже создаются…"); return }
        processingKeys.insert(key)
        UserDefaults.standard.set(locale.identifier, forKey: ViewController.subtitleLocaleKey)
        pausePlayback()
        loader.startAnimating()
        view.isUserInteractionEnabled = false      // таймлайн не должен меняться, пока идёт распознавание
        showToast("Распознаю речь…")

        SubtitleGenerator.shared.generate(build: b, locale: locale, progress: { [weak self] p in
            self?.showToast("Распознавание речи: \(Int(p * 100))%")
        }, completion: { [weak self] result in
            guard let self = self else { return }
            self.processingKeys.remove(key)
            self.loader.stopAnimating()
            self.view.isUserInteractionEnabled = true
            switch result {
            case .failure(let e): self.showToast(e.message)
            case .success(let phrases): self.applySubtitles(phrases)
            }
        })
    }

    func applySubtitles(_ phrases: [SubtitleGenerator.Phrase]) {
        pushUndo()
        texts.removeAll { $0.isAutoSubtitle == true }     // повторный запуск заменяет прошлые автосубтитры
        let total = totalSeconds
        for p in phrases {
            let start = min(p.start, max(0, total - 0.5))
            let end = min(p.end, total)
            var o = TextOverlay(text: p.text, start: start, duration: max(0.3, end - start))
            o.size = 0.04
            o.position = CGPoint(x: 0.5, y: 0.82)
            o.isAutoSubtitle = true
            texts.append(o)
        }
        clearSelection()
        focusLane = .text
        textsChanged()
        showToast("Субтитры добавлены: \(phrases.count)")
    }
}

// MARK: - Выбор языка

final class SubtitleLanguageViewController: UITableViewController, UISearchResultsUpdating {
    var onPick: ((Locale) -> Void)?
    private let all: [(id: String, name: String)]
    private var shown: [(id: String, name: String)]
    private let currentID: String

    init(current: Locale) {
        currentID = current.identifier
        all = SFSpeechRecognizer.supportedLocales()
            .map { ($0.identifier, Locale.current.localizedString(forIdentifier: $0.identifier) ?? $0.identifier) }
            .sorted { $0.1.localizedCaseInsensitiveCompare($1.1) == .orderedAscending }
        shown = all
        super.init(style: .plain)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Язык речи"
        navigationItem.leftBarButtonItem = UIBarButtonItem(title: "Отмена", style: .plain, target: self, action: #selector(cancel))
        let search = UISearchController(searchResultsController: nil)
        search.searchResultsUpdater = self
        search.obscuresBackgroundDuringPresentation = false
        navigationItem.searchController = search
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "c")
    }

    @objc private func cancel() { dismiss(animated: true) }

    func updateSearchResults(for searchController: UISearchController) {
        let q = (searchController.searchBar.text ?? "").trimmingCharacters(in: .whitespaces)
        shown = q.isEmpty ? all : all.filter { $0.name.localizedCaseInsensitiveContains(q) || $0.id.localizedCaseInsensitiveContains(q) }
        tableView.reloadData()
    }

    override func tableView(_ tv: UITableView, numberOfRowsInSection section: Int) -> Int { shown.count }

    override func tableView(_ tv: UITableView, cellForRowAt ip: IndexPath) -> UITableViewCell {
        let cell = tv.dequeueReusableCell(withIdentifier: "c", for: ip)
        let item = shown[ip.row]
        cell.textLabel?.text = item.name
        cell.accessoryType = item.id == currentID ? .checkmark : .none
        return cell
    }

    override func tableView(_ tv: UITableView, didSelectRowAt ip: IndexPath) {
        let id = shown[ip.row].id
        dismiss(animated: true) { [weak self] in self?.onPick?(Locale(identifier: id)) }
    }
}
