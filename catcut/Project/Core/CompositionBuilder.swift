// MARK: - Core/CompositionBuilder.swift

import UIKit
import AVFoundation
import CoreImage
import CoreMedia

// =====================================================================
// MARK: - Composition builder
// =====================================================================

final class EditorBuild {
    let composition: AVMutableComposition
    let audioMix: AVMutableAudioMix?
    let layout: TimelineLayout
    let renderSize: CGSize
    let trackIDs: [CMPersistentTrackID]
    let orientations: [CGImagePropertyOrientation]
    let overlayLayerInfos: [OverlayLayerInfo] // Сохраняем инфо об оверлеях и их треках
    private var bgImages: [String: CIImage] = [:]

    init(composition: AVMutableComposition, audioMix: AVMutableAudioMix?, layout: TimelineLayout,
         renderSize: CGSize, trackIDs: [CMPersistentTrackID], orientations: [CGImagePropertyOrientation], overlayLayerInfos: [OverlayLayerInfo]) {
        self.composition = composition
        self.audioMix = audioMix
        self.layout = layout
        self.renderSize = renderSize
        self.trackIDs = trackIDs
        self.orientations = orientations
        self.overlayLayerInfos = overlayLayerInfos
    }

    private func bgImage(for file: String) -> CIImage? {
        if let c = bgImages[file] { return c }
        let url = DraftStore.shared.mediaURL(file)
        guard var img = CIImage(contentsOf: url, options: [.applyOrientationProperty: true]) else { return nil }
        let e = img.extent
        img = img.transformed(by: CGAffineTransform(translationX: -e.minX, y: -e.minY))
        bgImages[file] = img
        return img
    }

    static func orientedSize(of clip: VideoClip) -> CGSize? {
        guard let t = clip.asset.tracks(withMediaType: .video).first else { return nil }
        let r = CGRect(origin: .zero, size: t.naturalSize).applying(t.preferredTransform)
        let w = abs(r.width), h = abs(r.height)
        return (w > 1 && h > 1) ? CGSize(width: w, height: h) : nil
    }

    static func frameSize(for project: ProjectSettings, firstClip: VideoClip) -> CGSize {
        if let c = project.crop, let src = orientedSize(of: firstClip) {
            var w = src.width * c.width, h = src.height * c.height
            let k = min(1, 1920 / max(w, h))
            w *= k; h *= k
            return CGSize(width: max(2, floor(w / 2) * 2), height: max(2, floor(h / 2) * 2))
        }
        if let r = project.ratio {
            let longSide: CGFloat = 1920
            var w: CGFloat, h: CGFloat
            if r >= 1 { w = longSide; h = longSide / CGFloat(r) } else { h = longSide; w = longSide * CGFloat(r) }
            return CGSize(width: max(2, floor(w / 2) * 2), height: max(2, floor(h / 2) * 2))
        }
        var size = CGSize(width: 1080, height: 1920)
        if let t = firstClip.asset.tracks(withMediaType: .video).first {
            let r = CGRect(origin: .zero, size: t.naturalSize).applying(t.preferredTransform)
            var w = abs(r.width), h = abs(r.height)
            if w > 1 && h > 1 {
                let maxSide: CGFloat = 1920
                if max(w, h) > maxSide {
                    let k = maxSide / max(w, h)
                    w *= k; h *= k
                }
                size = CGSize(width: floor(w / 2) * 2, height: floor(h / 2) * 2)
            }
        }
        return size
    }

    static func make(clips: [VideoClip], audios: [AudioClip], overlays: [VideoOverlay], project: ProjectSettings) -> EditorBuild? {
        guard !clips.isEmpty else { return nil }

        let comp = AVMutableComposition()
        guard let vA = comp.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid),
              let vB = comp.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid),
              let aA = comp.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid),
              let aB = comp.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid)
        else { return nil }

        // Создаем динамические треки под каждый оверлей и сохраняем их маппинг
        var overlayLayerInfos: [OverlayLayerInfo] = []
        for o in overlays {
            guard o.duration > 0.05,
                  let media = OverlayMedia.info(for: o.file),
                  let src = media.asset.tracks(withMediaType: .video).first,
                  let oTrack = comp.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid)
            else { continue }
            let startT = ticks(o.start)
            let want = floorTicks(o.duration)
            if o.isImage {
                // картинка = короткое «видео» из одного кадра: берём сколько есть и растягиваем до нужной длины
                let avail = min(floorTicks(media.duration), want)
                guard avail > .zero else { continue }
                try? oTrack.insertTimeRange(CMTimeRange(start: .zero, duration: avail), of: src, at: startT)
                if avail < want {
                    oTrack.scaleTimeRange(CMTimeRange(start: startT, duration: avail), toDuration: want)
                }
            } else {
                let avail = floorTicks(max(0, media.duration - o.sourceStart))
                let d = min(want, avail)
                guard d > .zero else { continue }
                try? oTrack.insertTimeRange(CMTimeRange(start: ticks(o.sourceStart), duration: d), of: src, at: startT)
            }
            let orient = imageOrientation(for: src.preferredTransform)
            overlayLayerInfos.append(OverlayLayerInfo(trackID: oTrack.trackID, orientation: orient, overlay: o))
        }

        let layout = TimelineLayout(clips: clips)
        let videoTracks = [vA, vB]
        let audioTracks = [aA, aB]
        let audioParams = [AVMutableAudioMixInputParameters(track: aA), AVMutableAudioMixInputParameters(track: aB)]
        var orientations: [CGImagePropertyOrientation] = []

        for (i, clip) in clips.enumerated() {
            let slot = i % 2
            let start = layout.starts[i]
            let dur = layout.durations[i]

            if let src = clip.asset.tracks(withMediaType: .video).first {
                try? videoTracks[slot].insertTimeRange(clip.sourceRange, of: src, at: start)
                if clip.speed != 1 {
                    videoTracks[slot].scaleTimeRange(CMTimeRange(start: start, duration: clip.sourceRange.duration), toDuration: dur)
                }
                orientations.append(imageOrientation(for: src.preferredTransform))
            } else {
                orientations.append(.up)
            }

            let audioAsset = clip.processedAudio ?? clip.asset
            if clip.volume > 0.001, let srcA = audioAsset.tracks(withMediaType: .audio).first {
                try? audioTracks[slot].insertTimeRange(clip.sourceRange, of: srcA, at: start)
                if clip.speed != 1 {
                    audioTracks[slot].scaleTimeRange(CMTimeRange(start: start, duration: clip.sourceRange.duration), toDuration: dur)
                }
                let p = audioParams[slot]
                let half = dur.secs / 2
                let inD = floorTicks(min(clip.fadeIn, half))
                let outD = floorTicks(min(clip.fadeOut, half))
                if inD > .zero {
                    p.setVolumeRamp(fromStartVolume: 0, toEndVolume: clip.volume, timeRange: CMTimeRange(start: start, duration: inD))
                } else {
                    p.setVolume(clip.volume, at: start)
                }
                if outD > .zero {
                    p.setVolumeRamp(fromStartVolume: clip.volume, toEndVolume: 0,
                                    timeRange: CMTimeRange(start: start + dur - outD, duration: outD))
                }
            }
        }

        var params: [AVMutableAudioMixInputParameters] = audioParams

        for a in audios {
            let asset = a.processed ?? a.asset
            guard let src = asset.tracks(withMediaType: .audio).first,
                  let tr = comp.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid)
            else { continue }
            let dur = min(a.duration, layout.total.secs - a.start, a.sourceDuration - a.sourceOffset)
            guard dur > 0.05 else { continue }
            let startT = ticks(a.start)
            try? tr.insertTimeRange(CMTimeRange(start: ticks(a.sourceOffset), duration: floorTicks(dur)), of: src, at: startT)
            let mp = AVMutableAudioMixInputParameters(track: tr)
            let half = dur / 2
            let inD = floorTicks(min(a.fadeIn, half)), outD = floorTicks(min(a.fadeOut, half))
            if inD > .zero {
                mp.setVolumeRamp(fromStartVolume: 0, toEndVolume: a.volume, timeRange: CMTimeRange(start: startT, duration: inD))
            } else {
                mp.setVolume(a.volume, at: startT)
            }
            if outD > .zero {
                mp.setVolumeRamp(fromStartVolume: a.volume, toEndVolume: 0,
                                 timeRange: CMTimeRange(start: startT + floorTicks(dur) - outD, duration: outD))
            }
            params.append(mp)
        }

        let mix = AVMutableAudioMix()
        mix.inputParameters = params

        return EditorBuild(composition: comp, audioMix: mix, layout: layout,
                           renderSize: frameSize(for: project, firstClip: clips[0]),
                           trackIDs: [vA.trackID, vB.trackID], orientations: orientations, overlayLayerInfos: overlayLayerInfos)
    }

    func makeVideoComposition(clips: [VideoClip], texts: [TextOverlay], overlays: [VideoOverlay], project: ProjectSettings) -> AVMutableVideoComposition {
        enum Seg { case solo(Int), trans(Int) }
        var segs: [(CMTime, CMTime, Seg)] = []

        for i in 0..<layout.starts.count {
            let soloStart = layout.starts[i] + layout.overlapIn(i)
            let soloEnd = layout.starts[i] + layout.durations[i] - layout.overlapOut(i)
            if soloEnd > soloStart { segs.append((soloStart, soloEnd, .solo(i))) }
            if i < layout.starts.count - 1, layout.overlapAfter[i] > .zero {
                let ts = layout.starts[i] + layout.durations[i] - layout.overlapAfter[i]
                segs.append((ts, ts + layout.overlapAfter[i], .trans(i)))
            }
        }

        func layer(_ i: Int) -> LayerInfo {
            let safeIdx = min(max(0, i), clips.count - 1)
            let c = clips[safeIdx]
            var bgImg: CIImage? = nil
            var bgCol: CIColor? = nil
            if c.bgMode == 1, let f = c.bgFile { bgImg = bgImage(for: f) }
            if c.bgMode == 3 { bgCol = CIColor(color: TextPalette.color(c.bgColor)) }
            return LayerInfo(trackID: trackIDs[i % 2], orientation: orientations[safeIdx],
                             preset: FilterCatalog.preset(c.filterID)?.adjust, intensity: c.filterIntensity,
                             custom: c.adjust, look: VideoLook(rawValue: c.look) ?? .none,
                             flipH: c.flipH, flipV: c.flipV, rotation: c.rotation, zoom: c.zoom,
                             bgMode: c.bgMode, bgImage: bgImg, bgColor: bgCol,
                             bgDepthThreshold: c.bgDepthThreshold)
        }

        let info = ProjectInfo(fillMode: project.fillMode, blurBackground: project.blurBackground,
                               introID: project.introID, introDuration: project.introDuration,
                               outroID: project.outroID, outroDuration: project.outroDuration,
                               total: layout.total.secs, crop: project.crop)
        // Живые параметры оверлеев (позиция/размер/поворот/прозрачность) берём из актуального массива,
        // а не из снимка на момент сборки треков — так жесты работают без полной пересборки.
        let liveOverlays: [OverlayLayerInfo] = overlayLayerInfos.compactMap { i in
            guard let o = overlays.first(where: { $0.id == i.overlay.id }) else { return nil }
            return OverlayLayerInfo(trackID: i.trackID, orientation: i.orientation, overlay: o)
        }
        let endTime = max(layout.total, composition.duration)
        var instructions: [AVVideoCompositionInstructionProtocol] = []

        for (idx, seg) in segs.enumerated() {
            var e = seg.1
            if idx == segs.count - 1 { e = max(e, endTime) }
            let range = CMTimeRange(start: seg.0, end: e)
            switch seg.2 {
            case .solo(let i):
                instructions.append(EditorInstruction(timeRange: range, from: layer(i), to: nil, transitionID: 0, texts: texts, overlays: liveOverlays, project: info))
            case .trans(let i):
                instructions.append(EditorInstruction(timeRange: range, from: layer(i), to: layer(i + 1),
                                                      transitionID: clips[i].transitionID, texts: texts, overlays: liveOverlays, project: info))
            }
        }

        let vc = AVMutableVideoComposition()
        vc.customVideoCompositorClass = EditorCompositor.self
        vc.frameDuration = CMTime(value: 1, timescale: 30)
        vc.renderSize = renderSize
        vc.instructions = instructions
        return vc
    }
}
