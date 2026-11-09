//
//  FilterFavorites.swift
//  catcut

import Foundation

// MARK: - FilterFavorites
struct FilterFavorites {
    private static let key = "favorite_video_filters_v1"
    static var all: [Int] {
        get { UserDefaults.standard.array(forKey: key) as? [Int] ?? [] }
        set { UserDefaults.standard.set(newValue, forKey: key) }
    }
    static func contains(_ id: Int) -> Bool { all.contains(id) }
    @discardableResult
    static func toggle(_ id: Int) -> Bool {
        var list = all
        if let idx = list.firstIndex(of: id) {
            list.remove(at: idx)
            all = list
            return false
        } else {
            list.append(id)
            all = list
            return true
        }
    }
}
