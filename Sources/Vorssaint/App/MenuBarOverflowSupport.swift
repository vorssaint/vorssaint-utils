// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint
import Foundation

enum MenuBarOverflowSupport {
    enum Layout: String, CaseIterable {
        case dropdown
        case menuBar

        static func resolved(_ value: String) -> Self { Self(rawValue: value) ?? .dropdown }
    }

    struct InlinePlan {
        let visibleCount: Int
        let hasMore: Bool
        let usesMenuOnly: Bool
        var pageSize: Int { visibleCount }
        var extraWidth: CGFloat { usesMenuOnly ? 0 : CGFloat(visibleCount) * 24 + (hasMore ? 32 : 0) }
    }

    /// Keep icons in the right safe segment; reserve one slot for paging
    /// when they do not all fit. The camera and app menus stay unobstructed.
    static func inlinePlan(itemCount: Int, freeWidth: CGFloat) -> InlinePlan {
        func slots(_ width: CGFloat) -> Int { width.isFinite ? max(0, Int(max(0, width) / 24)) : 0 }
        let right = slots(freeWidth)
        let count = max(0, itemCount)
        let paged = count > right
        let rightCount = min(count, paged ? slots(freeWidth - 32) : right)
        return InlinePlan(visibleCount: rightCount, hasMore: paged,
                          usesMenuOnly: right == 0 || (paged && rightCount == 0))
    }

    static func nextPageStart(current: Int, pageSize: Int, count: Int) -> Int {
        let next = current + max(1, pageSize)
        return next >= max(0, count) ? 0 : next
    }

    static func inlineFreeWidth(rightArea: CGRect, arrowFrame: CGRect) -> CGFloat {
        guard rightArea.width > 0, arrowFrame.width > 0,
              arrowFrame.minX >= rightArea.minX, arrowFrame.maxX <= rightArea.maxX else { return 0 }
        return max(0, arrowFrame.minX - rightArea.minX - 12)
    }

    struct SystemControl: Sendable {
        let id: Int
        let identifier: String
        let name: String
        let symbol: String
        var selectionKey: String { "system:\(id)" }
    }

    // Clock and Control Center remain available as navigation anchors. IDs
    // match MenuBarClientCore's MBSystemItemIdentifier on macOS 27.
    static let systemControls: [SystemControl] = [
        .init(id: 0, identifier: "com.apple.menuextra.battery", name: "Battery", symbol: "battery.100"),
        .init(id: 1, identifier: "com.apple.menuextra.bluetooth", name: "Bluetooth", symbol: "antenna.radiowaves.left.and.right"),
        .init(id: 3, identifier: "com.apple.menuextra.displays", name: "Displays", symbol: "display"),
        .init(id: 4, identifier: "com.apple.menuextra.keyboard", name: "Keyboard", symbol: "keyboard"),
        .init(id: 5, identifier: "com.apple.menuextra.volume", name: "Sound", symbol: "speaker.wave.2"),
        .init(id: 6, identifier: "com.apple.menuextra.wifi", name: "Wi-Fi", symbol: "wifi"),
        .init(id: 7, identifier: "com.apple.menuextra.screen-mirroring", name: "Screen Mirroring", symbol: "rectangle.on.rectangle")
    ]

    static func systemControl(identifier: String?) -> SystemControl? {
        systemControls.first { $0.identifier == identifier }
    }

    static func systemControl(selectionKey: String) -> SystemControl? {
        systemControls.first { $0.selectionKey == selectionKey }
    }

    static func allowedBundles(running: Set<String>, selection: Set<String>, ownBundle: String?) -> [String] {
        var allowed = running.subtracting(selection)
        if let ownBundle { allowed.insert(ownBundle) }
        return allowed.sorted()
    }

    /// Keep unknown system controls visible when macOS adds new identifiers.
    /// Only explicitly selected system keys remove an item from the allowlist.
    static func allowedSystemItems(selection: Set<String>) -> [NSNumber] {
        let hidden = Set(systemControls.filter { selection.contains($0.selectionKey) }.map(\.id))
        return (0...255).filter { !hidden.contains($0) }.map { NSNumber(value: $0) }
    }

    /// Geometry changes when icons hide. Preserve existing chooser rows while
    /// refreshing their data; append new icons and discard departed ones.
    static func stableOrder(previous: [String], current: [String]) -> [String] {
        let present = Set(current)
        var seen = Set<String>()
        return (previous.filter { present.contains($0) } + current).filter { seen.insert($0).inserted }
    }

}
