// MARK: - Models/RetouchSettings.swift

import Foundation

// =====================================================================
// MARK: - Настройки ретуши (на клип). Все значения: 0 = выключено.
// Положительное значение = «больше / толще / шире / длиннее».
// =====================================================================

struct RetouchSettings: Codable, Equatable {
    // Кожа
    var smooth = 0.0          // 0...1   сглаживание
    var acne = 0.0            // 0...1   убрать акне / пятна
    var wrinkles = 0.0        // 0...1   морщины
    var darkCircles = 0.0     // 0...1   круги под глазами
    var shine = 0.0           // 0...1   убрать жирный блеск
    var evenTone = 0.0        // 0...1   выровнять тон (покраснения)
    // Лицо
    var faceWidth = 0.0       // -1...1  ширина лица
    var chin = 0.0            // -1...1  подбородок короче/длиннее
    var eyeSize = 0.0         // -1...1  глаза
    var noseWidth = 0.0       // -1...1  нос уже/шире
    var lips = 0.0            // -1...1  губы
    var smile = 0.0           // 0...1   улыбка (уголки губ вверх)
    // Зубы / волосы
    var teethWhiten = 0.0     // 0...1
    var hairVolume = 0.0      // 0...1
    // Тело
    var bodyFat = 0.0         // -1...1  худее ↔ толще
    var waist = 0.0           // -1...1  талия
    var hips = 0.0            // -1...1  бёдра
    var shoulders = 0.0       // -1...1  плечи
    var muscle = 0.0          // 0...1   накачанность
    // Ноги
    var legLength = 0.0       // -1...1  длина ног
    var legsThick = 0.0       // -1...1  ноги тоньше ↔ толще
    // Руки
    var armsThick = 0.0       // -1...1  плечи-руки тоньше ↔ толще
    var forearms = 0.0        // -1...1  предплечья

    var isIdentity: Bool { self == RetouchSettings() }

    var needsFace: Bool {
        [smooth, acne, wrinkles, darkCircles, shine, evenTone,
         faceWidth, chin, eyeSize, noseWidth, lips, smile, teethWhiten, hairVolume].contains { $0 != 0 }
    }
    var needsBody: Bool {
        [bodyFat, waist, hips, shoulders, muscle, legLength, legsThick, armsThick, forearms].contains { $0 != 0 }
    }
}

enum RetouchCategory: Int, CaseIterable {
    case skin, face, teeth, hair, body, legs, arms

    var title: String {
        switch self {
        case .skin: return "Кожа"
        case .face: return "Лицо"
        case .teeth: return "Зубы"
        case .hair: return "Волосы"
        case .body: return "Тело"
        case .legs: return "Ноги"
        case .arms: return "Руки"
        }
    }
}

struct RetouchParam {
    let title: String
    let symbol: String
    let path: WritableKeyPath<RetouchSettings, Double>
    let min: Double
    let max: Double
    let category: RetouchCategory

    var bipolar: Bool { min < 0 }

    static let all: [RetouchParam] = [
        // Кожа
        RetouchParam(title: "Сглаживание", symbol: "sparkles", path: \.smooth, min: 0, max: 1, category: .skin),
        RetouchParam(title: "Акне", symbol: "circle.dotted", path: \.acne, min: 0, max: 1, category: .skin),
        RetouchParam(title: "Морщины", symbol: "waveform", path: \.wrinkles, min: 0, max: 1, category: .skin),
        RetouchParam(title: "Круги", symbol: "eye", path: \.darkCircles, min: 0, max: 1, category: .skin),
        RetouchParam(title: "Блеск", symbol: "sun.max", path: \.shine, min: 0, max: 1, category: .skin),
        RetouchParam(title: "Тон кожи", symbol: "paintpalette", path: \.evenTone, min: 0, max: 1, category: .skin),
        // Лицо
        RetouchParam(title: "Ширина", symbol: "person.crop.circle", path: \.faceWidth, min: -1, max: 1, category: .face),
        RetouchParam(title: "Подбородок", symbol: "arrow.up.and.down", path: \.chin, min: -1, max: 1, category: .face),
        RetouchParam(title: "Глаза", symbol: "eye", path: \.eyeSize, min: -1, max: 1, category: .face),
        RetouchParam(title: "Нос", symbol: "nose", path: \.noseWidth, min: -1, max: 1, category: .face),
        RetouchParam(title: "Губы", symbol: "mouth", path: \.lips, min: -1, max: 1, category: .face),
        RetouchParam(title: "Улыбка", symbol: "face.smiling", path: \.smile, min: 0, max: 1, category: .face),
        // Зубы / волосы
        RetouchParam(title: "Отбелить", symbol: "sparkle", path: \.teethWhiten, min: 0, max: 1, category: .teeth),
        RetouchParam(title: "Объём", symbol: "wind", path: \.hairVolume, min: 0, max: 1, category: .hair),
        // Тело
        RetouchParam(title: "Худее/толще", symbol: "figure.stand", path: \.bodyFat, min: -1, max: 1, category: .body),
        RetouchParam(title: "Талия", symbol: "arrow.left.and.right", path: \.waist, min: -1, max: 1, category: .body),
        RetouchParam(title: "Бёдра", symbol: "arrow.left.and.right", path: \.hips, min: -1, max: 1, category: .body),
        RetouchParam(title: "Плечи", symbol: "arrow.left.and.right", path: \.shoulders, min: -1, max: 1, category: .body),
        RetouchParam(title: "Накачанность", symbol: "dumbbell", path: \.muscle, min: 0, max: 1, category: .body),
        // Ноги
        RetouchParam(title: "Длина ног", symbol: "arrow.up.and.down", path: \.legLength, min: -1, max: 1, category: .legs),
        RetouchParam(title: "Толщина ног", symbol: "figure.walk", path: \.legsThick, min: -1, max: 1, category: .legs),
        // Руки
        RetouchParam(title: "Руки", symbol: "hand.raised", path: \.armsThick, min: -1, max: 1, category: .arms),
        RetouchParam(title: "Предплечья", symbol: "hand.raised", path: \.forearms, min: -1, max: 1, category: .arms)
    ]

    static func params(in c: RetouchCategory) -> [RetouchParam] { all.filter { $0.category == c } }
}
