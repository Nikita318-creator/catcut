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

    private static func nodes(for effect: AudioEffect, intensity: Float) -> [AVAudioNode] {
        let wetMix = CGFloat(intensity) * 100.0 // от 0 до 100%
        switch effect {
        case .none:
            return []
        case .echo:
            let d = AVAudioUnitDelay()
            d.delayTime = TimeInterval(0.1 + 0.3 * intensity)
            d.feedback = 20 + 60 * intensity
            d.wetDryMix = Float(wetMix)
            return [d]
        case .hall:
            let r = AVAudioUnitReverb()
            r.loadFactoryPreset(.largeHall)
            r.wetDryMix = Float(wetMix)
            return [r]
        case .cathedral:
            let r = AVAudioUnitReverb()
            r.loadFactoryPreset(.cathedral)
            r.wetDryMix = Float(wetMix)
            return [r]
        case .robot:
            let d = AVAudioUnitDelay()
            d.delayTime = 0.015
            d.feedback = 40 + 40 * intensity
            d.wetDryMix = Float(wetMix)
            let p = AVAudioUnitTimePitch()
            p.pitch = -200 * intensity
            return [d, p]
        case .chipmunk:
            let p = AVAudioUnitTimePitch()
            p.pitch = 200 + 800 * intensity
            return [p]
        case .deep:
            let p = AVAudioUnitTimePitch()
            p.pitch = -200 - 600 * intensity
            return [p]
        case .phone:
            let eq = AVAudioUnitEQ(numberOfBands: 2)
            eq.bands[0].filterType = .highPass; eq.bands[0].frequency = 300 + 300 * (1 - intensity); eq.bands[0].bypass = false
            eq.bands[1].filterType = .lowPass; eq.bands[1].frequency = 4000 - 1000 * (1 - intensity); eq.bands[1].bypass = false
            return [eq]
        case .megaphone:
            let eq = AVAudioUnitEQ(numberOfBands: 2)
            eq.bands[0].filterType = .highPass; eq.bands[0].frequency = 500; eq.bands[0].bypass = false
            eq.bands[1].filterType = .lowPass; eq.bands[1].frequency = 4500; eq.bands[1].bypass = false
            let dist = AVAudioUnitDistortion(); dist.loadFactoryPreset(.speechGoldenPi); dist.wetDryMix = Float(wetMix)
            return [eq, dist]
        case .underwater:
            let eq = AVAudioUnitEQ(numberOfBands: 1)
            eq.bands[0].filterType = .lowPass; eq.bands[0].frequency = 200 + 800 * (1 - intensity); eq.bands[0].bypass = false
            return [eq]
        case .bass:
            let eq = AVAudioUnitEQ(numberOfBands: 1)
            eq.bands[0].filterType = .lowShelf; eq.bands[0].frequency = 140; eq.bands[0].gain = 6 + 12 * intensity; eq.bands[0].bypass = false
            return [eq]
        case .loud:
            let eq = AVAudioUnitEQ(numberOfBands: 1)
            eq.globalGain = 5 + 15 * intensity
            return [eq]
        }
    }

    private static func renderOffline(input: URL, effect: AudioEffect, intensity: Float, output: URL) throws {
        let file = try AVAudioFile(forReading: input)
        let format = file.processingFormat
        let engine = AVAudioEngine()
        let player = AVAudioPlayerNode()
        engine.attach(player)
        let fx = nodes(for: effect, intensity: intensity) // <--- Теперь передаем интенсивность сюда!
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

    /// Обрабатывает звук файла эффектом. Результат кэшируется.
    static func process(asset: AVAsset, effect: AudioEffect, intensity: Float, completion: @escaping (AVAsset?) -> Void) {
        guard effect != .none, let urlAsset = asset as? AVURLAsset,
              asset.tracks(withMediaType: .audio).first != nil else { completion(nil); return }
        let base = urlAsset.url.deletingPathExtension().lastPathComponent
        let intKey = Int(intensity * 10)
        let outURL = DraftStore.shared.mediaDir.appendingPathComponent("fx_\(base)_\(effect.rawValue)_\(intKey).caf")
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
                        try renderOffline(input: tmp, effect: effect, intensity: intensity, output: outURL)
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
