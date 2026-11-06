// MARK: - Managers/SpeechDictation.swift

import UIKit
import AVFoundation
import CoreImage
import CoreMedia
import Speech

// =====================================================================
// MARK: - Speech dictation (наговорить текст)
// =====================================================================

final class SpeechDictation {
    var onText: ((String) -> Void)?
    var onStateChange: ((Bool) -> Void)?
    var onError: ((String) -> Void)?

    private let engine = AVAudioEngine()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private(set) var isRunning = false

    private func makeRecognizer() -> SFSpeechRecognizer? {
        if let r = SFSpeechRecognizer(locale: Locale.current), r.isAvailable { return r }
        return SFSpeechRecognizer(locale: Locale(identifier: "ru-RU"))
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
        guard !isRunning, let recognizer = makeRecognizer() else {
            onError?("Распознавание речи недоступно")
            return
        }
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playAndRecord, mode: .measurement, options: [.defaultToSpeaker, .duckOthers])
            try session.setActive(true, options: .notifyOthersOnDeactivation)

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

            task = recognizer.recognitionTask(with: req) { [weak self] result, error in
                DispatchQueue.main.async {
                    guard let self = self else { return }
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
        engine.stop()
        engine.inputNode.removeTap(onBus: 0)
        request?.endAudio()
        task?.cancel()
        request = nil
        task = nil
        isRunning = false
        // Возвращаем звук воспроизведения (работает и в беззвучном режиме)
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback, options: [])
        try? AVAudioSession.sharedInstance().setActive(true)
        onStateChange?(false)
    }
}
