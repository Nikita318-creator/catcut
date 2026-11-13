// MARK: - Managers/SpeechDictation.swift

import UIKit
import AVFoundation
import CoreMedia
import Speech

final class SpeechDictation {
    var onText: ((String) -> Void)?
    var onStateChange: ((Bool) -> Void)?
    var onError: ((String) -> Void)?
    /// Язык речи (раскладка клавиатуры). nil — язык устройства.
    var locale: Locale?

    private let engine = AVAudioEngine()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private var session = 0
    private(set) var isRunning = false

    /// Подбор распознавателя: переданный язык → языки устройства → Locale.current.
    /// allowFallback = false — только запрошенный язык (для субтитров).
    static func recognizer(for locale: Locale?, allowFallback: Bool = true) -> SFSpeechRecognizer? {
        var candidates: [Locale] = []
        if let l = locale { candidates.append(l) }
        if allowFallback || locale == nil {
            candidates += Locale.preferredLanguages.map { Locale(identifier: $0) }
            candidates.append(Locale.current)
        }
        let supported = SFSpeechRecognizer.supportedLocales()
        for c in candidates {
            if let r = SFSpeechRecognizer(locale: c), r.isAvailable { return r }
            if let code = c.languageCode,
               let m = supported.filter({ $0.languageCode == code }).sorted(by: { $0.identifier < $1.identifier }).first,
               let r = SFSpeechRecognizer(locale: m), r.isAvailable { return r }
        }
        return nil
    }

    func start() {
        SFSpeechRecognizer.requestAuthorization { [weak self] status in
            DispatchQueue.main.async {
                guard let self = self else { return }
                guard status == .authorized else {
                    self.onError?("Разрешите распознавание речи в настройках")
                    return
                }
                AVAudioSession.sharedInstance().requestRecordPermission { granted in
                    DispatchQueue.main.async {
                        guard granted else { self.onError?("Разрешите доступ к микрофону в настройках"); return }
                        self.begin()
                    }
                }
            }
        }
    }

    private func begin() {
        guard !isRunning, let recognizer = SpeechDictation.recognizer(for: locale) else {
            onError?("Распознавание речи недоступно для этого языка")
            return
        }
        do {
            let audio = AVAudioSession.sharedInstance()
            try audio.setCategory(.playAndRecord, mode: .measurement, options: [.defaultToSpeaker, .duckOthers])
            try audio.setActive(true, options: .notifyOthersOnDeactivation)

            let req = SFSpeechAudioBufferRecognitionRequest()
            req.shouldReportPartialResults = true
            request = req

            let node = engine.inputNode
            node.removeTap(onBus: 0)
            node.installTap(onBus: 0, bufferSize: 1024, format: node.outputFormat(forBus: 0)) { buffer, _ in
                req.append(buffer)
            }
            engine.prepare()
            try engine.start()

            session += 1
            let sid = session
            task = recognizer.recognitionTask(with: req) { [weak self] result, error in
                DispatchQueue.main.async {
                    // Запоздалые результаты остановленной сессии игнорируем —
                    // иначе они затирают правки пользователя.
                    guard let self = self, sid == self.session, self.isRunning else { return }
                    if let r = result { self.onText?(r.bestTranscription.formattedString) }
                    if error != nil || result?.isFinal == true { self.stop() }
                }
            }
            isRunning = true
            onStateChange?(true)
        } catch {
            onError?("Не удалось включить микрофон")
            stop()
        }
    }

    func stop() {
        guard isRunning || engine.isRunning else { return }
        session += 1                      // инвалидируем все ещё летящие колбэки
        engine.stop()
        engine.inputNode.removeTap(onBus: 0)
        request?.endAudio()
        task?.cancel()
        request = nil
        task = nil
        isRunning = false
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback, options: [])
        try? AVAudioSession.sharedInstance().setActive(true)
        onStateChange?(false)
    }
}
