// MARK: - Managers/AudioFXStore.swift

import UIKit
import AVFoundation
import CoreImage
import CoreMedia

// =====================================================================
// MARK: - Audio effects (эхо, реверб, голос…)
// =====================================================================

enum AudioEffect: Int, CaseIterable {
    case none, echo, hall, cathedral, robot, chipmunk, deep, phone, megaphone, underwater, bass, loud

    var title: String {
        switch self {
        case .none: return "Нет"
        case .echo: return "Эхо"
        case .hall: return "Зал"
        case .cathedral: return "Собор"
        case .robot: return "Робот"
        case .chipmunk: return "Высокий"
        case .deep: return "Низкий"
        case .phone: return "Телефон"
        case .megaphone: return "Мегафон"
        case .underwater: return "Под водой"
        case .bass: return "Бас"
        case .loud: return "Усиление"
        }
    }

    var symbol: String {
        switch self {
        case .none: return "xmark"
        case .echo: return "dot.radiowaves.left.and.right"
        case .hall: return "building.columns"
        case .cathedral: return "building.2"
        case .robot: return "cpu"
        case .chipmunk: return "hare"
        case .deep: return "tortoise"
        case .phone: return "phone"
        case .megaphone: return "megaphone"
        case .underwater: return "drop"
        case .bass: return "speaker.wave.3"
        case .loud: return "speaker.plus"
        }
    }
}

enum AudioFXStore {

    private static func nodes(for effect: AudioEffect) -> [AVAudioNode] {
        switch effect {
        case .none:
            return []
        case .echo:
            let d = AVAudioUnitDelay()
            d.delayTime = 0.28; d.feedback = 45; d.wetDryMix = 40; d.lowPassCutoff = 8000
            return [d]
        case .hall:
            let r = AVAudioUnitReverb(); r.loadFactoryPreset(.largeHall); r.wetDryMix = 45
            return [r]
        case .cathedral:
            let r = AVAudioUnitReverb(); r.loadFactoryPreset(.cathedral); r.wetDryMix = 60
            return [r]
        case .robot:
            let d = AVAudioUnitDelay()
            d.delayTime = 0.015; d.feedback = 70; d.wetDryMix = 55
            let p = AVAudioUnitTimePitch(); p.pitch = -200
            return [d, p]
        case .chipmunk:
            let p = AVAudioUnitTimePitch(); p.pitch = 800
            return [p]
        case .deep:
            let p = AVAudioUnitTimePitch(); p.pitch = -600
            return [p]
        case .phone:
            let eq = AVAudioUnitEQ(numberOfBands: 2)
            eq.bands[0].filterType = .highPass; eq.bands[0].frequency = 500; eq.bands[0].bypass = false
            eq.bands[1].filterType = .lowPass; eq.bands[1].frequency = 3400; eq.bands[1].bypass = false
            return [eq]
        case .megaphone:
            let eq = AVAudioUnitEQ(numberOfBands: 2)
            eq.bands[0].filterType = .highPass; eq.bands[0].frequency = 700; eq.bands[0].bypass = false
            eq.bands[1].filterType = .lowPass; eq.bands[1].frequency = 4500; eq.bands[1].bypass = false
            let dist = AVAudioUnitDistortion(); dist.loadFactoryPreset(.speechGoldenPi); dist.wetDryMix = 25
            return [eq, dist]
        case .underwater:
            let eq = AVAudioUnitEQ(numberOfBands: 1)
            eq.bands[0].filterType = .lowPass; eq.bands[0].frequency = 500; eq.bands[0].bypass = false
            let d = AVAudioUnitDelay(); d.delayTime = 0.06; d.feedback = 35; d.wetDryMix = 25
            return [eq, d]
        case .bass:
            let eq = AVAudioUnitEQ(numberOfBands: 1)
            eq.bands[0].filterType = .lowShelf; eq.bands[0].frequency = 140; eq.bands[0].gain = 12; eq.bands[0].bypass = false
            return [eq]
        case .loud:
            let eq = AVAudioUnitEQ(numberOfBands: 1)
            eq.globalGain = 10
            eq.bands[0].filterType = .parametric; eq.bands[0].frequency = 2500; eq.bands[0].bandwidth = 1; eq.bands[0].gain = 3
            eq.bands[0].bypass = false
            return [eq]
        }
    }

    private static func renderOffline(input: URL, effect: AudioEffect, output: URL) throws {
        let file = try AVAudioFile(forReading: input)
        let format = file.processingFormat
        let engine = AVAudioEngine()
        let player = AVAudioPlayerNode()
        engine.attach(player)
        let fx = nodes(for: effect)
        fx.forEach { engine.attach($0) }
        let chain: [AVAudioNode] = [player] + fx
        for i in 0..<(chain.count - 1) { engine.connect(chain[i], to: chain[i + 1], format: format) }
        engine.connect(chain[chain.count - 1], to: engine.mainMixerNode, format: format)

        try engine.enableManualRenderingMode(.offline, format: format, maximumFrameCount: 4096)
        try engine.start()
        player.scheduleFile(file, at: nil)
        player.play()

        let outFile = try AVAudioFile(forWriting: output, settings: format.settings)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: engine.manualRenderingFormat,
                                            frameCapacity: engine.manualRenderingMaximumFrameCount) else { return }
        let total = file.length
        var guardCounter = 0
        while engine.manualRenderingSampleTime < total && guardCounter < 1_000_000 {
            guardCounter += 1
            let remaining = total - engine.manualRenderingSampleTime
            let frames = AVAudioFrameCount(min(AVAudioFramePosition(buffer.frameCapacity), remaining))
            let status = try engine.renderOffline(frames, to: buffer)
            switch status {
            case .success: try outFile.write(from: buffer)
            case .cannotDoInCurrentContext: continue
            default: guardCounter = Int.max / 2
            }
        }
        player.stop()
        engine.stop()
    }

    /// Обрабатывает звук файла эффектом. Результат кэшируется (имя = файл + эффект).
    static func process(asset: AVAsset, effect: AudioEffect, completion: @escaping (AVAsset?) -> Void) {
        guard effect != .none, let urlAsset = asset as? AVURLAsset,
              asset.tracks(withMediaType: .audio).first != nil else { completion(nil); return }
        let base = urlAsset.url.deletingPathExtension().lastPathComponent
        let outURL = DraftStore.shared.mediaDir.appendingPathComponent("fx_\(base)_\(effect.rawValue).caf")
        if FileManager.default.fileExists(atPath: outURL.path) {
            completion(AVAsset(url: outURL))
            return
        }
        DispatchQueue.global(qos: .userInitiated).async {
            let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).m4a")
            var result: AVAsset?
            if let export = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetAppleM4A) {
                export.outputURL = tmp
                export.outputFileType = .m4a
                let sem = DispatchSemaphore(value: 0)
                export.exportAsynchronously { sem.signal() }
                sem.wait()
                if export.status == .completed {
                    do {
                        try renderOffline(input: tmp, effect: effect, output: outURL)
                        result = AVAsset(url: outURL)
                    } catch {
                        try? FileManager.default.removeItem(at: outURL)
                    }
                }
            }
            try? FileManager.default.removeItem(at: tmp)
            DispatchQueue.main.async { completion(result) }
        }
    }
}
