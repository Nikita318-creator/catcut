// MARK: - Models/Models.swift

import UIKit
import AVFoundation
import CoreImage
import CoreMedia
import Vision

// =====================================================================
// MARK: - Theme & helpers
// =====================================================================


/// Всё время внутри редактора живёт в одной шкале (600 тиков/сек),
/// иначе на стыках клипов появляются микро-щели и AVFoundation ругается.
let kTimescale: CMTimeScale = 600

func ticks(_ seconds: Double) -> CMTime {
    CMTime(value: Int64((max(0, seconds) * Double(kTimescale)).rounded()), timescale: kTimescale)
}

func floorTicks(_ seconds: Double) -> CMTime {
    CMTime(value: Int64((max(0, seconds) * Double(kTimescale)).rounded(.down)), timescale: kTimescale)
}

extension CMTime {
    var secs: Double {
        let s = CMTimeGetSeconds(self)
        return s.isFinite ? s : 0
    }
}

func imageOrientation(for t: CGAffineTransform) -> CGImagePropertyOrientation {
    let a = Int(t.a.rounded()), b = Int(t.b.rounded()), c = Int(t.c.rounded()), d = Int(t.d.rounded())
    switch (a, b, c, d) {
    case (0, 1, -1, 0): return .right
    case (0, -1, 1, 0): return .left
    case (-1, 0, 0, -1): return .down
    default: return .up
    }
}


// =====================================================================
// MARK: - Models
// =====================================================================

struct VideoClip {
    var id = UUID()
    var asset: AVAsset
    /// Имя файла в постоянном хранилище (нужно для черновиков).
    var file: String = ""
    /// Клип-картинка (внутри — «видео» из одного кадра, поэтому её тоже можно растягивать).
    var isImage: Bool = false
    /// Какой кусок исходника используем (в шкале 600).
    var sourceRange: CMTimeRange
    var speed: Float = 1.0

    // Цвет
    var filterID: Int = 0                 // 0 — без фильтра, иначе номер из FilterCatalog
    var filterIntensity: Float = 1.0
    var adjust = Adjustments()            // ручная настройка поверх фильтра
    var look: Int = 0                     // живой эффект (VideoLook)

    // Геометрия
    var flipH = false
    var flipV = false
    var rotation: Double = 0              // градусы по часовой
    var zoom: Double = 1

    // Фон (вырезание человека)
    var bgMode: Int = 0                   // 0 нет, 1 фото, 2 размытие, 3 цвет
    var bgFile: String? = nil
    var bgColor: Int = 0

    // Переход ПОСЛЕ этого клипа (между ним и следующим). 0 = нет.
    var transitionID: Int = 0
    var transitionDuration: Double = 0.6

    // Звук клипа (у каждого куска свой)
    var volume: Float = 1.0               // 0 = без звука, до 3 = усиление
    var audioEffect: Int = 0
    var fadeIn: Double = 0
    var fadeOut: Double = 0
    var processedAudio: AVAsset? = nil    // звук после эффекта (не сохраняется, пересоздаётся)

    /// Длительность клипа на таймлайне (с учётом скорости).
    var displayDuration: CMTime {
        ticks(sourceRange.duration.secs / Double(speed))
    }
}

/// Аудио-дорожка: живёт на таймлайне независимо от видео, но только в пределах видео.
struct AudioClip {
    var id = UUID()
    let asset: AVAsset
    var file: String
    var title: String
    /// Где начинается на общем таймлайне (сек).
    var start: Double
    /// С какого места исходного аудио играем (сек).
    var sourceOffset: Double = 0
    /// Сколько играем (сек).
    var duration: Double
    var volume: Float = 1.0               // до 3 = усиление
    var effect: Int = 0
    var fadeIn: Double = 0
    var fadeOut: Double = 0
    var processed: AVAsset? = nil
    /// Полная длина исходного файла.
    let sourceDuration: Double
}

// MARK: Формат кадра и настройки проекта

struct AspectPreset {
    let title: String
    let w: Double
    let h: Double
}

enum AspectPresets {
    /// w = 0 — взять формат первого клипа.
    static let all: [AspectPreset] = [
        AspectPreset(title: "Оригинал", w: 0, h: 0),
        AspectPreset(title: "9:16", w: 9, h: 16),
        AspectPreset(title: "16:9", w: 16, h: 9),
        AspectPreset(title: "1:1", w: 1, h: 1),
        AspectPreset(title: "4:5", w: 4, h: 5),
        AspectPreset(title: "5:4", w: 5, h: 4),
        AspectPreset(title: "3:4", w: 3, h: 4),
        AspectPreset(title: "4:3", w: 4, h: 3),
        AspectPreset(title: "2:3", w: 2, h: 3),
        AspectPreset(title: "3:2", w: 3, h: 2),
        AspectPreset(title: "21:9", w: 21, h: 9),
        AspectPreset(title: "2.35:1", w: 2.35, h: 1),
        AspectPreset(title: "1.91:1", w: 1.91, h: 1)
    ]
}

struct ProjectSettings: Codable, Equatable {
    var aspectIndex = 0
    var customW: Double = 0
    var customH: Double = 0
    var fillMode = 0                  // 0 вписать, 1 заполнить (с обрезкой)
    var blurBackground = false        // размытый фон при «вписать» (по умолчанию выкл.)
    /// Обрезка краёв, нормализованная 0...1 (origin сверху-слева). nil — без обрезки.
    var crop: CGRect? = nil
    var introID = 0
    var introDuration = 0.6
    var outroID = 0
    var outroDuration = 0.6

    var customActive: Bool { customW > 0 && customH > 0 }

    /// nil — «оригинал».
    var ratio: Double? {
        if customActive { return customW / customH }
        let p = AspectPresets.all[max(0, min(aspectIndex, AspectPresets.all.count - 1))]
        return p.w > 0 ? p.w / p.h : nil
    }
}

struct TextOverlay: Codable {
    var id = UUID()
    var text: String
    var start: Double
    var duration: Double
    /// Центр текста, 0...1 (y считается сверху).
    var position = CGPoint(x: 0.5, y: 0.5)
    /// Размер шрифта как доля высоты кадра.
    var size: CGFloat = 0.05
    /// Поворот по часовой стрелке (радианы).
    var rotation: CGFloat = 0

    var fillIndex: Int = 0
    var strokeIndex: Int = -1
    var strokeWidth: CGFloat = 0.08
    var shadow: Int = 1
    var shadowColorIndex: Int = 5
    var glowIndex: Int = -1
    var boxIndex: Int = -1
    var boxOpacity: Double = 0.9
    var fontIndex: Int = 0
    var weight: Int = 6
    var italic = false
    var underline = false
    var strike = false
    /// 0 — слева, 1 — по центру, 2 — справа
    var alignment: Int = 1
    var letterSpacing: CGFloat = 0
    var animIn: Int = 0
    var animOut: Int = 0
    var animDuration: Double = 0.5
}

/// Раскладка клипов на таймлайне: старты, длительности и перекрытия под переходы.
struct TimelineLayout {
    var starts: [CMTime] = []
    var durations: [CMTime] = []
    /// overlapAfter[i] — на сколько клип i перекрывается со следующим (переход).
    var overlapAfter: [CMTime] = []
    var total: CMTime = .zero

    init(clips: [VideoClip]) {
        guard !clips.isEmpty else { return }
        durations = clips.map { $0.displayDuration }

        for i in 0..<clips.count {
            if i < clips.count - 1, clips[i].transitionID != 0 {
                let maxAllowed = 0.5 * min(durations[i].secs, durations[i + 1].secs)
                let d = min(clips[i].transitionDuration, maxAllowed)
                overlapAfter.append(d >= 0.1 ? floorTicks(d) : .zero)
            } else {
                overlapAfter.append(.zero)
            }
        }

        var cursor = CMTime.zero
        for i in 0..<clips.count {
            starts.append(cursor)
            cursor = cursor + durations[i] - overlapAfter[i]
        }
        total = starts[clips.count - 1] + durations[clips.count - 1]
    }

    func overlapIn(_ i: Int) -> CMTime { i > 0 ? overlapAfter[i - 1] : .zero }
    func overlapOut(_ i: Int) -> CMTime { overlapAfter[i] }

    func end(of i: Int) -> CMTime { starts[i] + durations[i] }

    /// Какой клип сейчас под красной палкой.
    func index(at t: CMTime) -> Int? {
        guard !starts.isEmpty else { return nil }
        let ts = t.secs
        var best: Int?
        var bestScore = -Double.infinity
        for i in 0..<starts.count {
            let s = starts[i].secs
            let e = end(of: i).secs
            if ts >= s - 0.0005 && ts <= e + 0.0005 {
                let score = min(ts - s, e - ts)
                if score > bestScore { bestScore = score; best = i }
            }
        }
        if best == nil { return ts <= 0 ? 0 : starts.count - 1 }
        return best
    }
}
