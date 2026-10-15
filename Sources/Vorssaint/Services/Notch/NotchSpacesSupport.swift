// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation
import CoreGraphics
import AppKit

struct NotchSpace: Equatable, Identifiable {
    let id: UInt64
    let uuid: String?
    let desktopNumber: Int?
    let current: Bool
    let name: String?
    var fallbackNameKey: String? = nil
    var displayID: CGDirectDisplayID? = nil
    var displayName: String = ""

    var nameKey: String? { uuid ?? fallbackNameKey }

    func currentLabel(_ strings: NotchSpacesStrings) -> String {
        let label = desktopNumber.map { String(format: strings.spaceFormat, $0) } ?? strings.fullscreen
        return name.map { "\(label) - \($0)" } ?? label
    }

    var compactLabel: String {
        name ?? desktopNumber.map { "\($0)" } ?? "▣"
    }

    func title(_ strings: NotchSpacesStrings) -> String {
        name ?? desktopNumber.map { String(format: strings.desktopFormat, $0) } ?? strings.fullscreen
    }
}

enum NotchSpacesSupport {
    static func isEnabled(in defaults: UserDefaults = .standard) -> Bool {
        NotchSupport.isEnabled(in: defaults)
            && NotchSupport.modules(in: defaults).contains(.spaces)
    }

    static func isExternalDisplay(frame: CGRect) -> Bool {
        guard let screen = NSScreen.screens.first(where: { $0.frame == frame }),
              let id = (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value
        else { return false }
        return CGDisplayIsBuiltin(id) == 0
    }

    static func restingChoice(in defaults: UserDefaults = .standard) -> NotchIdleContent {
        if defaults.bool(forKey: DefaultsKey.notchSpacesIdleEnabled), NotchSupport.canRest(with: .spaces, in: defaults) {
            return .spaces
        }
        return NotchSupport.idleContent(in: defaults)
    }

    static func selectResting(_ content: NotchIdleContent, in defaults: UserDefaults = .standard) {
        if content == .spaces {
            guard NotchSupport.canRest(with: .spaces, in: defaults) else { return }
            defaults.set(true, forKey: DefaultsKey.notchSpacesIdleEnabled)
        } else {
            defaults.set(false, forKey: DefaultsKey.notchSpacesIdleEnabled)
            defaults.set(content.rawValue, forKey: DefaultsKey.notchIdleContent)
        }
    }

    static func orderedByDisplayPosition(_ spaces: [NotchSpace], frames: [CGDirectDisplayID: CGRect]) -> [NotchSpace] {
        spaces.enumerated().sorted { left, right in
            let lhs = left.element.displayID.flatMap { frames[$0] }
            let rhs = right.element.displayID.flatMap { frames[$0] }
            switch (lhs, rhs) {
            case let (lhs?, rhs?):
                if lhs.minX != rhs.minX { return lhs.minX < rhs.minX }
                if lhs.maxY != rhs.maxY { return lhs.maxY > rhs.maxY }
            case (_?, nil): return true
            case (nil, _?): return false
            case (nil, nil): break
            }
            return left.offset < right.offset
        }.map(\.element)
    }

    static func visibleSpaces(_ spaces: [NotchSpace], on displayID: CGDirectDisplayID?,
                              allDisplays: Bool) -> [NotchSpace] {
        spaces.filter { allDisplays || $0.displayID == displayID }
    }

    static func normalizedName(_ text: String) -> String? {
        let text = String(text.trimmingCharacters(in: .whitespacesAndNewlines).prefix(80))
        return text.isEmpty ? nil : text
    }

    static func row(ids: [UInt64], fullscreen: Set<UInt64>, current: UInt64?,
                    uuids: [UInt64: String], names: [String: String],
                    desktopOffset: Int = 0, displayIdentifier: String? = nil) -> [NotchSpace] {
        var number = desktopOffset
        var seen = Set<UInt64>()
        return ids.compactMap { id in
            guard seen.insert(id).inserted else { return nil }
            let isDesktop = !fullscreen.contains(id)
            if isDesktop { number += 1 }
            let uuid = uuids[id].flatMap { UUID(uuidString: $0)?.uuidString }
            let fallback = isDesktop ? displayIdentifier.map { "display:\($0):desktop:\(number)" } : nil
            let key = uuid ?? fallback
            return NotchSpace(id: id, uuid: uuid, desktopNumber: isDesktop ? number : nil,
                              current: current == id, name: key.flatMap { names[$0] }.flatMap(normalizedName),
                              fallbackNameKey: fallback)
        }
    }

    static func adjacent(to id: UInt64?, in row: [NotchSpace], forward: Bool) -> UInt64? {
        guard let id, let index = row.firstIndex(where: { $0.id == id }) else { return nil }
        let next = index + (forward ? 1 : -1)
        return row.indices.contains(next) ? row[next].id : nil
    }
}

enum NotchSpacesLayout {
    static let badgeFontSize: CGFloat = 11
    static let titleWidth: CGFloat = 150
    static let badgeWidth: CGFloat = 72
    static let spacing: CGFloat = 4
    static let maximumWidth: CGFloat = 360

    static func badgeHeight(contentHeight: CGFloat) -> CGFloat {
        max(14, min(20, contentHeight - 8))
    }

    static func edgeGap(contentHeight: CGFloat) -> CGFloat {
        max(0, (contentHeight - badgeHeight(contentHeight: contentHeight)) / 2)
    }

    static func capsuleContentWidth(spaces: [NotchSpace], external: Bool) -> CGFloat {
        if external {
            return spaces.reduce(0) { $0 + max(44, labelWidth($1.compactLabel)) }
                + CGFloat(max(0, spaces.count - 1)) * spacing
        }
        let gap = spaces.count > 1 ? NotchCapsuleLayout.spacing : 0
        return arrangements(spaces: spaces).map { $0.current + gap + $0.others }.max() ?? labelWidth("")
    }

    static func expandedPillWidth(available: CGFloat, count: Int, scale: CGFloat = 1) -> CGFloat {
        guard available.isFinite, count > 0 else { return 0 }
        let scale = scale.isFinite && scale > 0 ? scale : 1
        let width = (max(0, available) - CGFloat(count - 1) * spacing) / CGFloat(count)
        return max(44, (width * scale).rounded(.down) / scale)
    }

    static func labelWidth(_ label: String, maximum: CGFloat = titleWidth) -> CGFloat {
        let font = NSFont.monospacedDigitSystemFont(ofSize: badgeFontSize, weight: .semibold)
        return min(maximum, max(20, (label as NSString).size(withAttributes: [.font: font]).width.rounded(.up) + 14))
    }

    static func listWidth(spaces: [NotchSpace]) -> CGFloat {
        min(150, spaces.reduce(0) { $0 + labelWidth($1.compactLabel, maximum: badgeWidth) }
            + CGFloat(max(0, spaces.count - 1)) * spacing)
    }

    static func wingWidth(spaces: [NotchSpace]) -> CGFloat {
        (arrangements(spaces: spaces).map { max($0.current, $0.others) }.max() ?? 20) + 24
    }

    private static func arrangements(spaces: [NotchSpace]) -> [(current: CGFloat, others: CGFloat)] {
        let widths = spaces.map { labelWidth($0.compactLabel) }
        let badges = widths.map { min(badgeWidth, $0) }
        let total = badges.reduce(0, +)
        let gaps = CGFloat(max(0, spaces.count - 2)) * spacing
        return widths.indices.map { index in
            (current: widths[index], others: min(150, total - badges[index] + gaps))
        }
    }

    static func listWidth(count: Int) -> CGFloat {
        min(150, CGFloat(max(0, count)) * (badgeWidth + spacing))
    }
}
