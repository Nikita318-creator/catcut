// MARK: - Managers/SubtitleGenerator.swift

import UIKit
import AVFoundation
import CoreMedia
import Speech

enum SubtitleError: Error {
    case notAuthorized, languageUnavailable, noAudio, noSpeech, failed
    var message: String {
        switch self {
        case .notAuthorized: return "Разрешите распознавание речи в настройках"
        case .languageUnavailable: return "Этот язык не поддерживается распознаванием. Выберите другой"
        case .noAudio: return "В проекте нет звука для распознавания"
        case .noSpeech: return "Речь не найдена. Попробуйте другой язык"
        case .failed: return "Не удалось распознать речь"
        }
    }
}

final class SubtitleGenerator {
    static let shared = SubtitleGenerator()

    struct Word { let text: String; let start: Double; let end: Double }
    struct Phrase { let text: String; let start: Double; var end: Double }

    private let chunkSeconds = 50.0
    private var recognizer: SFSpeechRecognizer?
    private var task: SFSpeechRecognitionTask?
    private var exportSession: AVAssetExportSession?

    func generate(build: EditorBuild, locale: Locale,
                  progress: @escaping (Double) -> Void,
                  completion: @escaping (Result<[Phrase], SubtitleError>) -> Void) {
        SFSpeechRecognizer.requestAuthorization { status in
            DispatchQueue.main.async {
                guard status == .authorized else { completion(.failure(.notAuthorized)); return }
                guard let rec = SpeechDictation.recognizer(for: locale, allowFallback: false) else {
                    completion(.failure(.languageUnavailable)); return
                }
                let hasAudio = build.composition.tracks(withMediaType: .audio)
                    .contains { $0.segments.contains { !$0.isEmpty } }
                let total = build.layout.total.secs
                guard hasAudio, total > 0.3 else { completion(.failure(.noAudio)); return }
                self.recognizer = rec
                let ranges = stride(from: 0.0, to: total, by: self.chunkSeconds)
                    .map { ($0, min(self.chunkSeconds, total - $0)) }
                    .filter { $0.1 > 0.3 }
                self.run(build, ranges, 0, [], false, locale, progress, completion)
            }
        }
    }

    private func run(_ b: EditorBuild, _ ranges: [(Double, Double)], _ i: Int, _ words: [Word], _ hadError: Bool,
                     _ locale: Locale, _ progress: @escaping (Double) -> Void,
                     _ completion: @escaping (Result<[Phrase], SubtitleError>) -> Void) {
        guard i < ranges.count else {
            let phrases = SubtitleGenerator.phrases(from: words, locale: locale)
            if phrases.isEmpty { completion(.failure(hadError ? .failed : .noSpeech)) }
            else { completion(.success(phrases)) }
            return
        }
        if ranges.count > 1 { progress(Double(i) / Double(ranges.count)) }
        let (start, dur) = ranges[i]
        exportChunk(b, start: start, duration: dur) { [weak self] url in
            guard let self = self else { return }
            guard let url = url else {
                self.run(b, ranges, i + 1, words, true, locale, progress, completion)
                return
            }
            self.recognize(url: url, offset: start) { chunk, failed in
                try? FileManager.default.removeItem(at: url)
                self.run(b, ranges, i + 1, words + chunk, hadError || failed, locale, progress, completion)
            }
        }
    }

    /// Микс звука композиции (клипы + аудиодорожки) в m4a. Время внутри файла = время таймлайна минус start.
    private func exportChunk(_ b: EditorBuild, start: Double, duration: Double, completion: @escaping (URL?) -> Void) {
        guard let s = AVAssetExportSession(asset: b.composition, presetName: AVAssetExportPresetAppleM4A) else {
            completion(nil); return
        }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("sub-\(UUID().uuidString).m4a")
        s.outputURL = url
        s.outputFileType = .m4a
        s.audioMix = b.audioMix
        s.timeRange = CMTimeRange(start: ticks(start), duration: ticks(duration))
        exportSession = s
        s.exportAsynchronously {
            DispatchQueue.main.async { completion(s.status == .completed ? url : nil) }
        }
    }

    private func recognize(url: URL, offset: Double, completion: @escaping ([Word], Bool) -> Void) {
        guard let rec = recognizer else { completion([], true); return }
        let req = SFSpeechURLRecognitionRequest(url: url)
        req.shouldReportPartialResults = false
        if #available(iOS 16.0, *) { req.addsPunctuation = true }
        var finished = false
        task = rec.recognitionTask(with: req) { result, error in
            DispatchQueue.main.async {
                guard !finished else { return }
                if let r = result, r.isFinal {
                    finished = true
                    let words = r.bestTranscription.segments.map {
                        Word(text: $0.substring, start: offset + $0.timestamp, end: offset + $0.timestamp + $0.duration)
                    }
                    completion(words, false)
                } else if let e = error {
                    finished = true
                    completion([], (e as NSError).code != 1110)   // 1110 — «речь не обнаружена», это не сбой
                }
            }
        }
    }

    // MARK: Слова → фразы

    static func phrases(from words: [Word], locale: Locale) -> [Phrase] {
        let sep = ["zh", "ja", "th"].contains(locale.languageCode ?? "") ? "" : " "
        let maxChars = 32, maxDur = 4.0, maxGap = 0.7
        var result: [Phrase] = []
        var cur: [Word] = []

        func text(_ w: [Word]) -> String { w.map { $0.text }.joined(separator: sep) }
        func flush() {
            guard let f = cur.first, let l = cur.last else { return }
            result.append(Phrase(text: wrap(text(cur)), start: f.start, end: l.end))
            cur = []
        }

        for w in words {
            if let l = cur.last {
                let tooLong = text(cur + [w]).count > maxChars
                let tooSlow = w.end - cur[0].start > maxDur
                let gap = w.start - l.end > maxGap
                let sentenceEnd = l.text.last.map { ".!?…。！？".contains($0) } ?? false
                if tooLong || tooSlow || gap || sentenceEnd { flush() }
            }
            cur.append(w)
        }
        flush()

        // Субтитр держится до следующего (без мерцания на коротких паузах) и не накладывается на него
        for k in result.indices {
            if k + 1 < result.count {
                let next = result[k + 1].start
                result[k].end = (next - result[k].end < 0.4) ? next : min(result[k].end + 0.25, next)
            } else {
                result[k].end += 0.25
            }
        }
        return result
    }

    private static func wrap(_ s: String) -> String {
        guard s.count > 16 else { return s }
        let mid = s.count / 2
        let spaces = s.indices.filter { s[$0] == " " }
        guard let best = spaces.min(by: {
            abs(s.distance(from: s.startIndex, to: $0) - mid) < abs(s.distance(from: s.startIndex, to: $1) - mid)
        }) else { return s }
        var r = s
        r.replaceSubrange(best...best, with: "\n")
        return r
    }
}
