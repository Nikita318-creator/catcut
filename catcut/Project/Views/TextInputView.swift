// MARK: - Views/TextInputView.swift

import UIKit
import AVFoundation
import CoreImage
import CoreMedia
import SnapKit

// =====================================================================
// MARK: - Text input (современный ввод текста, несколько строк)
// =====================================================================

final class TextInputView: UIView, UITextViewDelegate {
    var onDone: ((String) -> Void)?

    private let dim = UIView()
    private let card = UIView()
    private let textView = UITextView()
    private let placeholder = UILabel()
    private let doneButton = UIButton(type: .system)
    private let micButton = UIButton(type: .system)
    private let dictation = SpeechDictation()
    private var baseText = ""
    private var cardBottom: Constraint!
    private weak var parent: UIView?

    override init(frame: CGRect) {
        super.init(frame: frame)

        dim.backgroundColor = UIColor.black.withAlphaComponent(0.45)
        dim.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(cancelTapped)))
        addSubview(dim)
        dim.snp.makeConstraints { $0.edges.equalToSuperview() }

        card.backgroundColor = UIColor(white: 0.12, alpha: 1)
        card.layer.cornerRadius = 18
        card.layer.maskedCorners = [.layerMinXMinYCorner, .layerMaxXMinYCorner]
        addSubview(card)
        card.snp.makeConstraints { make in
            make.leading.trailing.equalToSuperview()
            cardBottom = make.bottom.equalToSuperview().constraint
        }

        let cancel = UIButton(type: .system)
        cancel.setTitle("Отмена", for: .normal)
        cancel.tintColor = .lightGray
        cancel.addTarget(self, action: #selector(cancelTapped), for: .touchUpInside)
        let title = UILabel()
        title.text = "Текст"
        title.textColor = .white
        title.font = .systemFont(ofSize: 16, weight: .semibold)
        doneButton.setTitle("Готово", for: .normal)
        doneButton.tintColor = Theme.accent
        doneButton.titleLabel?.font = .systemFont(ofSize: 16, weight: .bold)
        doneButton.addTarget(self, action: #selector(doneTapped), for: .touchUpInside)

        textView.backgroundColor = UIColor(white: 0.2, alpha: 1)
        textView.textColor = .white
        textView.tintColor = Theme.accent
        textView.font = .systemFont(ofSize: 20, weight: .medium)
        textView.layer.cornerRadius = 12
        textView.textContainerInset = UIEdgeInsets(top: 12, left: 10, bottom: 12, right: 10)
        textView.returnKeyType = .default      // Enter = новая строка
        textView.delegate = self

        placeholder.text = "Введите текст…\nEnter — новая строка"
        placeholder.numberOfLines = 2
        placeholder.textColor = UIColor(white: 1, alpha: 0.35)
        placeholder.font = .systemFont(ofSize: 17)
        placeholder.isUserInteractionEnabled = false

        micButton.setImage(UIImage(systemName: "mic.fill"), for: .normal)
        micButton.tintColor = .white
        micButton.backgroundColor = UIColor(white: 0.32, alpha: 1)
        micButton.layer.cornerRadius = 20
        micButton.addTarget(self, action: #selector(micTapped), for: .touchUpInside)
        dictation.onText = { [weak self] spoken in
            guard let self = self else { return }
            self.textView.text = self.baseText.isEmpty ? spoken : self.baseText + " " + spoken
            self.updateState()
        }
        dictation.onStateChange = { [weak self] running in
            self?.micButton.backgroundColor = running ? .systemRed : UIColor(white: 0.32, alpha: 1)
            self?.micButton.setImage(UIImage(systemName: running ? "stop.fill" : "mic.fill"), for: .normal)
        }
        dictation.onError = { [weak self] message in
            self?.placeholder.text = message
            self?.placeholder.isHidden = false
        }

        [cancel, title, doneButton, textView].forEach { card.addSubview($0) }
        card.addSubview(micButton)
        textView.addSubview(placeholder)
        cancel.snp.makeConstraints { make in make.top.equalToSuperview().offset(6); make.leading.equalToSuperview().offset(12); make.height.equalTo(40) }
        title.snp.makeConstraints { make in make.centerY.equalTo(cancel); make.centerX.equalToSuperview() }
        doneButton.snp.makeConstraints { make in make.centerY.equalTo(cancel); make.trailing.equalToSuperview().inset(12) }
        textView.snp.makeConstraints { make in
            make.top.equalTo(cancel.snp.bottom).offset(6)
            make.leading.trailing.equalToSuperview().inset(14)
            make.height.equalTo(130)
            make.bottom.equalToSuperview().inset(14)
        }
        placeholder.snp.makeConstraints { make in make.top.equalToSuperview().offset(12); make.leading.equalToSuperview().offset(15) }
        micButton.snp.makeConstraints { make in
            make.trailing.equalTo(textView).inset(8)
            make.bottom.equalTo(textView).inset(8)
            make.size.equalTo(40)
        }
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func show(in parent: UIView, text: String) {
        self.parent = parent
        frame = parent.bounds
        autoresizingMask = [.flexibleWidth, .flexibleHeight]
        parent.addSubview(self)
        textView.text = text
        updateState()
        NotificationCenter.default.addObserver(self, selector: #selector(keyboardChanged(_:)),
                                               name: UIResponder.keyboardWillChangeFrameNotification, object: nil)
        alpha = 0
        UIView.animate(withDuration: 0.2) { self.alpha = 1 }
        textView.becomeFirstResponder()
        textView.selectedTextRange = textView.textRange(from: textView.endOfDocument, to: textView.endOfDocument)
    }

    private func updateState() {
        placeholder.isHidden = !textView.text.isEmpty
        let empty = textView.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        doneButton.isEnabled = !empty
        doneButton.alpha = empty ? 0.4 : 1
    }

    func textViewDidChange(_ textView: UITextView) {
        if dictation.isRunning { dictation.stop() }   // пользователь печатает — диктовка не должна перезаписывать
        updateState()
    }
    
    @objc private func keyboardChanged(_ n: Notification) {
        guard let end = (n.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? NSValue)?.cgRectValue else { return }
        let inSelf = convert(end, from: nil)
        let h = max(0, bounds.maxY - inSelf.minY)
        let d = (n.userInfo?[UIResponder.keyboardAnimationDurationUserInfoKey] as? Double) ?? 0.25
        cardBottom.update(offset: -h)
        UIView.animate(withDuration: d) { self.layoutIfNeeded() }
    }

    @objc private func micTapped() {
        if dictation.isRunning {
            dictation.stop()
        } else {
            baseText = textView.text.trimmingCharacters(in: .whitespacesAndNewlines)
            dictation.locale = keyboardLocale()
            dictation.start()
        }
    }
    
    private func keyboardLocale() -> Locale? {
        guard let lang = textView.textInputMode?.primaryLanguage,
              lang != "emoji", lang != "dictation" else { return nil }
        return Locale(identifier: lang)
    }

    @objc private func cancelTapped() { close() }

    @objc private func doneTapped() {
        let text = textView.text.trimmingCharacters(in: .whitespacesAndNewlines)
        close()
        if !text.isEmpty { onDone?(text) }
    }

    private func close() {
        dictation.stop()
        NotificationCenter.default.removeObserver(self)
        textView.resignFirstResponder()
        UIView.animate(withDuration: 0.2, animations: { self.alpha = 0 }) { _ in self.removeFromSuperview() }
    }
}
