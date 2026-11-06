// MARK: - Managers/WaveformStore.swift

import UIKit
import AVFoundation
import CoreImage
import CoreMedia

// =====================================================================
// MARK: - Waveform (волна аудио на таймлайне)
// =====================================================================

final class WaveformStore {
    static let shared = WaveformStore()
    static let peaksPerSecond = 20

    var onUpdate: (() -> Void)?
    private var cache: [ObjectIdentifier: [Float]] = [:]
    private var pending = Set<ObjectIdentifier>()

    func peaks(for asset: AVAsset) -> [Float]? {
        let key = ObjectIdentifier(asset)
        if let p = cache[key] { return p }
        if !pending.contains(key) {
            pending.insert(key)
            DispatchQueue.global(qos: .utility).async { [weak self] in
                let result = WaveformStore.compute(asset)
                DispatchQueue.main.async {
                    self?.cache[key] = result ?? []
                    self?.pending.remove(key)
                    self?.onUpdate?()
                }
            }
        }
        return nil
    }

    private static func compute(_ asset: AVAsset) -> [Float]? {
        guard let track = asset.tracks(withMediaType: .audio).first,
              let reader = try? AVAssetReader(asset: asset) else { return nil }
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false,
            AVNumberOfChannelsKey: 1,
            AVSampleRateKey: 8000
        ]
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: settings)
        guard reader.canAdd(output) else { return nil }
        reader.add(output)
        guard reader.startReading() else { return nil }

        let window = 8000 / peaksPerSecond
        var peaks: [Float] = []
        var curMax: Int32 = 0
        var count = 0

        while let sb = output.copyNextSampleBuffer() {
            guard let block = CMSampleBufferGetDataBuffer(sb) else { continue }
            let length = CMBlockBufferGetDataLength(block)
            var data = Data(count: length)
            data.withUnsafeMutableBytes { raw in
                if let base = raw.baseAddress {
                    _ = CMBlockBufferCopyDataBytes(block, atOffset: 0, dataLength: length, destination: base)
                }
            }
            data.withUnsafeBytes { (buf: UnsafeRawBufferPointer) in
                let samples = buf.bindMemory(to: Int16.self)
                for s in samples {
                    let v = abs(Int32(s))
                    if v > curMax { curMax = v }
                    count += 1
                    if count >= window {
                        peaks.append(Float(curMax) / 32768)
                        curMax = 0
                        count = 0
                    }
                }
            }
            CMSampleBufferInvalidate(sb)
        }
        guard !peaks.isEmpty else { return nil }
        let top = max(0.05, peaks.max() ?? 1)
        return peaks.map { $0 / top }
    }
}
