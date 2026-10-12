// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation
import CoreGraphics

/// Lock the gesture to its first dominant axis, so card actions coexist with
/// scrolling through overflowing windows. Momentum is handled by the reader.
struct PreviewSwipeGesture {
    enum Result { case passThrough, consume, maximize, minimize }
    private var perpendicular: Bool?
    private var travel: CGFloat = 0
    private var spent = false
    mutating func reset() { self = PreviewSwipeGesture() }
    mutating func sample(x: CGFloat, y: CGFloat, orientation: DockPreviewOrientation) -> Result {
        let actionDelta = orientation == .bottom ? y : x
        let scrollDelta = orientation == .bottom ? x : y
        if perpendicular == nil {
            guard abs(actionDelta) + abs(scrollDelta) > 0 else { return .passThrough }
            perpendicular = abs(actionDelta) > abs(scrollDelta)
        }
        guard perpendicular == true else { return .passThrough }
        travel += actionDelta
        guard abs(travel) > 50, !spent else { return .consume }
        spent = true
        let away = orientation == .left ? travel < 0 : travel > 0
        return away ? .maximize : .minimize
    }
}

/// Additions are opt-in. Registry membership also makes each portable choice
/// available to Settings Backup; display identifiers are excluded separately.
enum DockOption: String, CaseIterable {
    case indicatorEnabled, indicatorStyle, indicatorColor, indicatorThickness, indicatorLength, indicatorOffset
    case lockEnabled, lockDisplay, lockModifier
    case folders, folderSort, folderDescending, folderHiddenFiles, folderRememberSort, folderSortChoices
    case mediaWidget, calendarWidget, widgetLyrics
    case livePreviews, liveFrameRate, liveQuality, switcherLivePreviews
    case compact, compactThreshold, trigger, triggerModifier, hoverAction, hoverDelay
    case gestures, shakeAction, middleClickAction, dockScroll, titleBarScroll, quickQuit
    case cornerRadius, spacing, maxRows, maxColumns, controlsPosition, spaceNumbers
    case sortOrder, groupInstances, windowTitleFilters
    case nativeCmdTab, trackpadDirection, minimizeKey
    case trackpadSwitcher, trackpadFingers, vimNavigation, searchFuzziness, pointerFollowsFocus, automation

    var key: String { "windowEnhancements." + rawValue }
    var bool: Bool { (UserDefaults.standard.object(forKey: key) as? Bool) ?? (defaultValue as? Bool ?? false) }
    var int: Int { (UserDefaults.standard.object(forKey: key) as? NSNumber)?.intValue ?? (defaultValue as? Int ?? 0) }
    var double: Double { (UserDefaults.standard.object(forKey: key) as? NSNumber)?.doubleValue ?? (defaultValue as? Double ?? 0) }
    var string: String {
        sanitizedString(UserDefaults.standard.string(forKey: key))
    }
    func sanitizedString(_ stored: String?) -> String {
        let fallback = defaultValue as? String ?? ""
        let value = stored ?? fallback
        guard let choices = allowedStrings else { return value }
        return choices.contains(value) ? value : fallback
    }
    private var allowedStrings: [String]? {
        switch self {
        case .indicatorStyle: return ["line", "dots"]
        case .lockModifier, .triggerModifier: return ["option", "command", "control", "shift"]
        case .folderSort: return ["name", "modified", "size"]
        case .trigger: return ["hover", "middle", "modifier"]
        case .hoverAction: return ["off", "activate", "full"]
        case .shakeAction: return ["off", "minimizeOthers"]
        case .middleClickAction: return ["off", "close", "minimize", "maximize", "fullscreen", "quit", "hide", "center", "restore"]
        case .controlsPosition: return ["top", "bottom"]
        case .sortOrder: return ["recent", "creation", "app", "title"]
        case .pointerFollowsFocus: return ["off", "display", "always"]
        case .trackpadDirection: return ["horizontal", "vertical"]
        default: return nil
        }
    }
    var defaultValue: Any {
        switch self {
        case .indicatorStyle: return "line"
        case .indicatorColor: return "4C8DFF"
        case .indicatorThickness: return 3.0
        case .indicatorLength: return 32.0
        case .indicatorOffset: return 3.0
        case .lockDisplay: return "main"
        case .lockModifier, .triggerModifier: return "option"
        case .folderSort: return "modified"
        case .folderDescending, .folderRememberSort: return true
        case .folderSortChoices: return [String: String]()
        case .liveFrameRate: return 24
        case .liveQuality: return 640
        case .compactThreshold, .searchFuzziness: return 0
        case .trigger: return "hover"
        case .hoverAction, .shakeAction, .pointerFollowsFocus: return "off"
        case .hoverDelay: return 0.8
        case .middleClickAction: return "close"
        case .cornerRadius: return 18.0
        case .spacing: return 8.0
        case .maxRows: return 1
        case .maxColumns: return 1
        case .controlsPosition: return "bottom"
        case .sortOrder: return "recent"
        case .windowTitleFilters: return ""
        case .trackpadFingers: return 3
        case .trackpadDirection: return "horizontal"
        case .minimizeKey: return -1
        default: return false
        }
    }
    static var defaults: [String: Any] {
        Dictionary(uniqueKeysWithValues: allCases.map { ($0.key, $0.defaultValue) })
    }
}

enum DockEnhancementSupport {
    static func bounded(_ value: Double, fallback: Double, range: ClosedRange<Double>) -> Double {
        value.isFinite ? min(max(value, range.lowerBound), range.upperBound) : fallback
    }

    static func isCompact(count: Int, forced: Bool, threshold: Int, canCapture: Bool) -> Bool {
        forced || !canCapture || (threshold > 0 && count >= threshold)
    }

    static func titleIsExcluded(_ title: String, filters: String) -> Bool {
        filters.split(separator: "\n").contains {
            let term = $0.trimmingCharacters(in: .whitespacesAndNewlines)
            return !term.isEmpty && title.range(of: term, options: [.caseInsensitive, .diacriticInsensitive]) != nil
        }
    }

    /// Bounded edit distance supplements the existing exact, tokenized search.
    /// A typo budget is optional; long strings never allocate a quadratic table.
    static func fuzzyMatches(_ query: String, in text: String, tolerance: Int) -> Bool {
        let fold: (String) -> String = { $0.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil) }
        let tokens = fold(query).split(whereSeparator: \.isWhitespace).map(String.init)
        let haystack = fold(text)
        let words = haystack.split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map(String.init)
        let budget = min(max(tolerance, 0), 3)
        return tokens.allSatisfy { token in
            if haystack.contains(token) { return true }
            guard budget > 0, token.count > 2, token.count <= 64 else { return false }
            return words.contains { word in
                guard abs(word.count - token.count) <= budget, word.count <= 64 else { return false }
                let a = Array(token), b = Array(word)
                var previous = Array(0...b.count)
                for (i, char) in a.enumerated() {
                    var row = [i + 1]
                    for (j, other) in b.enumerated() {
                        row.append(min(row[j] + 1, previous[j + 1] + 1, previous[j] + (char == other ? 0 : 1)))
                    }
                    previous = row
                }
                return previous.last! <= budget
            }
        }
    }

    static func usableLanes(requested: Int, count: Int, available: Double, cardSize: Double,
                            spacing: Double, padding: Double, header: Double) -> Int {
        guard [available, cardSize, spacing, padding, header].allSatisfy(\.isFinite), cardSize > 0 else { return 1 }
        let ratio = max(0, available * 0.9 - padding * 2 - header + spacing) / max(1, cardSize + spacing)
        let capacity = Int(min(4, max(1, ratio)))
        return min(max(1, requested), max(1, count), capacity, 4)
    }
    static func hexRGB(_ string: String) -> UInt32 {
        let raw = string.trimmingCharacters(in: .whitespacesAndNewlines)
        let value = raw.hasPrefix("#") ? String(raw.dropFirst()) : raw
        guard value.count == 6 else { return 0x4C8DFF }
        return UInt32(value, radix: 16) ?? 0x4C8DFF
    }

    static func indicatorFrame(icon: CGRect, orientation: DockPreviewOrientation,
                               thickness: Double, length: Double, offset: Double) -> CGRect {
        let thick = bounded(thickness, fallback: 3, range: 1...12)
        let size = min(bounded(length, fallback: 32, range: 4...128),
                       orientation == .bottom ? icon.width : icon.height)
        let gap = bounded(offset, fallback: 3, range: -20...20)
        switch orientation {
        case .bottom: return CGRect(x: icon.midX - size / 2, y: icon.minY + gap, width: size, height: thick)
        case .left: return CGRect(x: icon.minX + gap, y: icon.midY - size / 2, width: thick, height: size)
        case .right: return CGRect(x: icon.maxX - gap - thick, y: icon.midY - size / 2, width: thick, height: size)
        }
    }
}
