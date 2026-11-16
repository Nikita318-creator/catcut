// MARK: - Core/RetouchAnalyzer.swift

import UIKit
import AVFoundation
import Vision
import CoreImage

// =====================================================================
// MARK: - Геометрия, найденная Vision (нормализованная 0...1, origin снизу-слева, как у CIImage)
// =====================================================================

enum Joint: Int, CaseIterable {
    case neck, leftShoulder, rightShoulder, leftElbow, rightElbow, leftWrist, rightWrist
    case root, leftHip, rightHip, leftKnee, rightKnee, leftAnkle, rightAnkle

    var visionName: VNHumanBodyPoseObservation.JointName {
        switch self {
        case .neck: return .neck
        case .leftShoulder: return .leftShoulder
        case .rightShoulder: return .rightShoulder
        case .leftElbow: return .leftElbow
        case .rightElbow: return .rightElbow
        case .leftWrist: return .leftWrist
        case .rightWrist: return .rightWrist
        case .root: return .root
        case .leftHip: return .leftHip
        case .rightHip: return .rightHip
        case .leftKnee: return .leftKnee
        case .rightKnee: return .rightKnee
        case .leftAnkle: return .leftAnkle
        case .rightAnkle: return .rightAnkle
        }
    }
}

struct FaceGeo {
    static let regionCount = 8
    /// 0 contour, 1 leftEye, 2 rightEye, 3 leftBrow, 4 rightBrow, 5 nose, 6 outerLips, 7 innerLips
    var regions: [[CGPoint]] = Array(repeating: [], count: FaceGeo.regionCount)
    var contour: [CGPoint] { regions[0] }
    var leftEye: [CGPoint] { regions[1] }
    var rightEye: [CGPoint] { regions[2] }
    var leftBrow: [CGPoint] { regions[3] }
    var rightBrow: [CGPoint] { regions[4] }
    var nose: [CGPoint] { regions[5] }
    var outerLips: [CGPoint] { regions[6] }
    var innerLips: [CGPoint] { regions[7] }
}

struct BodyGeo {
    var joints: [CGPoint?] = Array(repeating: nil, count: Joint.allCases.count)
}

struct RetouchFrame {
    var faces: [FaceGeo] = []
    var bodies: [BodyGeo] = []
    var hasFace = false      // лица искали в этом кадре (даже если не нашли)
    var hasBody = false

    /// Взвешенное усреднение соседних кадров (сглаживает дрожание Vision).
    static func blend(_ items: [(RetouchFrame, Double)]) -> RetouchFrame? {
        guard let ref = items.first?.0 else { return nil }
        let usable = items.filter { $0.0.faces.count == ref.faces.count && $0.0.bodies.count == ref.bodies.count }
        guard !usable.isEmpty else { return ref }
        var out = ref

        for fi in ref.faces.indices {
            for ri in 0..<FaceGeo.regionCount {
                let n = ref.faces[fi].regions[ri].count
                guard n > 0 else { continue }
                let same = usable.filter { $0.0.faces[fi].regions[ri].count == n }
                let tw = same.reduce(0.0) { $0 + $1.1 }
                guard tw > 0 else { continue }
                out.faces[fi].regions[ri] = (0..<n).map { k in
                    var x = 0.0, y = 0.0
                    for (f, w) in same {
                        let p = f.faces[fi].regions[ri][k]
                        x += Double(p.x) * w; y += Double(p.y) * w
                    }
                    return CGPoint(x: x / tw, y: y / tw)
                }
            }
        }
        for bi in ref.bodies.indices {
            for j in 0..<Joint.allCases.count {
                guard ref.bodies[bi].joints[j] != nil else { continue }
                var x = 0.0, y = 0.0, tw = 0.0
                for (f, w) in usable {
                    if let p = f.bodies[bi].joints[j] { x += Double(p.x) * w; y += Double(p.y) * w; tw += w }
                }
                if tw > 0 { out.bodies[bi].joints[j] = CGPoint(x: x / tw, y: y / tw) }
            }
        }
        return out
    }
}

// =====================================================================
// MARK: - Трек: результаты анализа клипа по времени ИСХОДНИКА (12 выборок/сек)
// =====================================================================

final class RetouchTrack {
    static let rate = 12.0
    var isStill = false                       // клип-картинка: один кадр на всё время
    private var samples: [Int: RetouchFrame] = [:]
    private let lock = NSLock()

    func has(_ b: Int, face: Bool, body: Bool) -> Bool {
        lock.lock(); defer { lock.unlock() }
        guard let s = samples[b] else { return false }
        return (!face || s.hasFace) && (!body || s.hasBody)
    }

    func set(_ b: Int, _ f: RetouchFrame) {
        lock.lock(); defer { lock.unlock() }
        var n = f
        if let old = samples[b] {
            if !f.hasFace { n.faces = old.faces; n.hasFace = old.hasFace }
            if !f.hasBody { n.bodies = old.bodies; n.hasBody = old.hasBody }
        }
        samples[b] = n
    }

    var anyFace: Bool { lock.lock(); defer { lock.unlock() }; return samples.values.contains { !$0.faces.isEmpty } }
    var anyBody: Bool { lock.lock(); defer { lock.unlock() }; return samples.values.contains { !$0.bodies.isEmpty } }

    func frame(at t: Double) -> RetouchFrame? {
        lock.lock(); defer { lock.unlock() }
        if isStill { return samples.values.first }
        let x = t * RetouchTrack.rate
        let b0 = Int(floor(x))
        let fr = x - Double(b0)

        func smoothed(_ b: Int) -> RetouchFrame? {
            guard let c = samples[b] else { return nil }
            var items: [(RetouchFrame, Double)] = [(c, 0.5)]
            if let p = samples[b - 1] { items.append((p, 0.25)) }
            if let n = samples[b + 1] { items.append((n, 0.25)) }
            return RetouchFrame.blend(items)
        }
        let a = smoothed(b0), b = smoothed(b0 + 1)
        switch (a, b) {
        case let (a?, b?): return RetouchFrame.blend([(a, 1 - fr), (b, fr)])
        case let (a?, nil): return a
        case let (nil, b?): return b
        default: return nil
        }
    }
}

// =====================================================================
// MARK: - Vision
// =====================================================================

enum RetouchAnalyzer {

    static func analyze(cgImage: CGImage, face: Bool, body: Bool) -> RetouchFrame {
        var out = RetouchFrame()
        let faceReq = VNDetectFaceLandmarksRequest()
        let bodyReq = VNDetectHumanBodyPoseRequest()
        var reqs: [VNRequest] = []
        if face { reqs.append(faceReq) }
        if body { reqs.append(bodyReq) }
        guard !reqs.isEmpty else { return out }

        let handler = VNImageRequestHandler(cgImage: cgImage, orientation: .up, options: [:])
        try? handler.perform(reqs)
        let size = CGSize(width: cgImage.width, height: cgImage.height)

        if face {
            out.hasFace = true
            let obs = (faceReq.results ?? [])
                .sorted { $0.boundingBox.width * $0.boundingBox.height > $1.boundingBox.width * $1.boundingBox.height }
                .prefix(4)
            func pts(_ r: VNFaceLandmarkRegion2D?) -> [CGPoint] {
                guard let r = r else { return [] }
                return r.pointsInImage(imageSize: size).map { CGPoint(x: $0.x / size.width, y: $0.y / size.height) }
            }
            for o in obs {
                guard let lm = o.landmarks else { continue }
                var g = FaceGeo()
                g.regions[0] = pts(lm.faceContour)
                g.regions[1] = pts(lm.leftEye)
                g.regions[2] = pts(lm.rightEye)
                g.regions[3] = pts(lm.leftEyebrow)
                g.regions[4] = pts(lm.rightEyebrow)
                g.regions[5] = pts(lm.nose)
                g.regions[6] = pts(lm.outerLips)
                g.regions[7] = pts(lm.innerLips)
                if g.regions[0].count > 4 { out.faces.append(g) }
            }
            // стабильный порядок слева направо — иначе при усреднении лица «перескакивают»
            out.faces.sort { meanX($0.contour) < meanX($1.contour) }
        }

        if body {
            out.hasBody = true
            for o in bodyReq.results ?? [] {
                var g = BodyGeo()
                var count = 0
                for j in Joint.allCases {
                    if let p = try? o.recognizedPoint(j.visionName), p.confidence > 0.25 {
                        g.joints[j.rawValue] = p.location
                        count += 1
                    }
                }
                if count >= 4 { out.bodies.append(g) }
            }
            out.bodies.sort { bodyX($0) < bodyX($1) }
        }
        return out
    }

    private static func meanX(_ p: [CGPoint]) -> CGFloat {
        p.isEmpty ? 0 : p.reduce(0) { $0 + $1.x } / CGFloat(p.count)
    }
    private static func bodyX(_ b: BodyGeo) -> CGFloat {
        let xs = b.joints.compactMap { $0?.x }
        return xs.isEmpty ? 0 : xs.reduce(0, +) / CGFloat(xs.count)
    }

    /// Резервный путь (экспорт): анализ прямо на текущем кадре, если фоновый ещё не дошёл.
    static func analyzeInline(_ img: CIImage, face: Bool, body: Bool, context: CIContext,
                              track: RetouchTrack, sourceTime: Double) -> RetouchFrame? {
        let e = img.extent
        let k = min(1, 640 / max(e.width, e.height))
        let small = img.transformed(by: CGAffineTransform(scaleX: k, y: k))
        guard let cg = context.createCGImage(small, from: small.extent) else { return nil }
        let fr = analyze(cgImage: cg, face: face, body: body)
        let bucket = Int(floor(sourceTime * RetouchTrack.rate + 0.5))
        track.set(bucket, fr)
        return fr
    }
}

// =====================================================================
// MARK: - Хранилище треков + фоновый анализ
// =====================================================================

final class RetouchStore {
    static let shared = RetouchStore()

    enum Event {
        case updated
        case finished(foundFace: Bool, foundBody: Bool, askedFace: Bool, askedBody: Bool)
    }

    var onEvent: ((Event) -> Void)?
    /// true во время экспорта: недостающие кадры анализируются «на лету», чтобы в файле ничего не пропало.
    var blocking = false

    private var tracks: [String: RetouchTrack] = [:]
    private var inFlight: [String: (face: Bool, body: Bool)] = [:]
    private let lock = NSLock()
    private let queue = DispatchQueue(label: "retouch.analysis", qos: .utility)

    static func key(_ c: VideoClip) -> String? {
        c.file.isEmpty ? nil : "\(c.file)|\(c.sourceRange.start.value)|\(c.sourceRange.duration.value)"
    }

    func track(for c: VideoClip) -> RetouchTrack? {
        guard let k = RetouchStore.key(c) else { return nil }
        lock.lock(); defer { lock.unlock() }
        if let t = tracks[k] { return t }
        let t = RetouchTrack()
        t.isStill = c.isImage
        tracks[k] = t
        return t
    }

    func prepare(clip: VideoClip, face: Bool, body: Bool) {
        guard let k = RetouchStore.key(clip), let track = track(for: clip), face || body else { return }
        lock.lock()
        if let f = inFlight[k], (f.face || !face), (f.body || !body) { lock.unlock(); return }
        let old = inFlight[k] ?? (false, false)
        inFlight[k] = (old.face || face, old.body || body)
        lock.unlock()

        queue.async { [weak self] in
            self?.run(clip: clip, track: track, face: face, body: body, key: k)
        }
    }

    private func run(clip: VideoClip, track: RetouchTrack, face: Bool, body: Bool, key: String) {
        let gen = AVAssetImageGenerator(asset: clip.asset)
        gen.appliesPreferredTrackTransform = true
        gen.maximumSize = CGSize(width: 640, height: 640)
        let tol = CMTime(value: 1, timescale: 24)
        gen.requestedTimeToleranceBefore = tol
        gen.requestedTimeToleranceAfter = tol

        let start = clip.sourceRange.start.secs
        let end = clip.sourceRange.end.secs
        let rate = RetouchTrack.rate
        let first = Int(floor(start * rate))
        let last = clip.isImage ? first : Int(ceil(end * rate))
        var lastNotify = CACurrentMediaTime()

        if first <= last {
            for b in first...last {
                if track.has(b, face: face, body: body) { continue }
                let t = clip.isImage ? 0 : min(max(start, Double(b) / rate), max(start, end - 0.001))
                if let cg = try? gen.copyCGImage(at: CMTime(seconds: t, preferredTimescale: 600), actualTime: nil) {
                    track.set(b, RetouchAnalyzer.analyze(cgImage: cg, face: face, body: body))
                }
                let now = CACurrentMediaTime()
                if now - lastNotify > 1.0 {
                    lastNotify = now
                    DispatchQueue.main.async { [weak self] in self?.onEvent?(.updated) }
                }
            }
        }

        lock.lock(); inFlight[key] = nil; lock.unlock()
        let ff = track.anyFace, fb = track.anyBody
        DispatchQueue.main.async { [weak self] in
            self?.onEvent?(.finished(foundFace: ff, foundBody: fb, askedFace: face, askedBody: body))
        }
    }
}
