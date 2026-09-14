// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import SwiftUI

/// The generated strips, reveal method and search pipeline come from production.
/// Synthetic entries and same-sized empty tiles isolate native scrolling. Windows
/// stay unordered; no screenshots, key events, capture or real app actions occur.
enum SwitcherScrollContract {
    typealias SwitcherItem = Item

    struct Item: Identifiable {
        let id: String
        let pid: Int
        var previewWindowID: Int? { nil }
        var title: String { pid == 0 && id.hasSuffix("-7") ? "discard" : "keep" }
        var appName: String { pid == 0 ? "Alpha" : "Other" }
    }
    final class Model: ObservableObject {
        @Published var windows: [Item] = []
        @Published var selectedIndex = 0
        @Published var iconRowLayout: SwitcherIconRowLayout = .empty
        @Published var simple = false
        @Published var previews: [Int: Int] = [:]
        var sessionItems: [Item] = []
        var searchQuery = ""
        var screenWidth: CGFloat = 1440
        func seed(_ counts: [Int], selected: Int, simple: Bool = false) {
            windows = counts.enumerated().flatMap { p, n in (0..<n).map { Item(id: "\(p)-\($0)", pid: p) } }
            sessionItems = windows
            selectedIndex = selected
            self.simple = simple
            recompute()
        }
        func recompute() {
            let count = windows.indices.contains(selectedIndex) ? windows.filter { $0.pid == windows[selectedIndex].pid }.count : 1
            iconRowLayout = .compute(appCount: Set(windows.map(\.pid)).count, selectedWindowCount: count,
                                    screenVisibleFrame: CGRect(x: 0, y: 0, width: screenWidth, height: 900))
        }
        func recomputeLayouts(for items: [Item]) { recompute() }
        func resizePanel() {}
        func select(index: Int) { selectedIndex = index; recompute() }
        func closeWindow(_ item: Item) {
            let state = SwitcherSupport.closeState(afterRemoving: item.id, itemIDs: windows.map(\.id), selectedIndex: selectedIndex)
            sessionItems.removeAll { $0.id == item.id }
            windows = windows.filter { state.remainingItemIDs.contains($0.id) }
            selectedIndex = state.selectedIndex
            recompute()
        }
        func commitSession() {}
        func hoverSelect(index: Int) {}
        func hoverSelectEnded(index: Int) {}
    }
    struct SwitcherWindowPreviewTile: View {
        let window: Item
        let preview: Int?
        let isSelected: Bool
        let onCommit: () -> Void
        let onClose: () -> Void
        var body: some View { Color.clear.frame(width: SwitcherIconRowLayout.previewCardWidth, height: SwitcherIconRowLayout.previewCardHeight) }
    }
    struct SwitcherWindowTitleChip: View {
        let window: Item
        let isSelected: Bool
        let onSelect: () -> Void
        let onHover: (Bool) -> Void
        var body: some View { Color.clear.frame(width: SwitcherIconRowLayout.simpleTitleChipMaxWidth, height: 25 * SwitcherIconRowLayout.scale) }
    }
    static func run(_ suite: TestSuite) {
        MainActor.assumeIsolated { runOnMain(suite) }
    }

    @MainActor private static func runOnMain(_ suite: TestSuite) {
        _ = NSApplication.shared
        let previousPolicy = NSApp.activationPolicy()
        NSApp.setActivationPolicy(.prohibited)
        let previousSize = UserDefaults.standard.object(forKey: DefaultsKey.previewSize)
        UserDefaults.standard.set("normal", forKey: DefaultsKey.previewSize)
        defer {
            if let previousSize { UserDefaults.standard.set(previousSize, forKey: DefaultsKey.previewSize) }
            else { UserDefaults.standard.removeObject(forKey: DefaultsKey.previewSize) }
            NSApp.setActivationPolicy(previousPolicy)
        }
        func run(_ name: String, _ body: (Model, (String) -> Void, () -> Void) -> Void) {
            let model = Model()
            let hosting = NSHostingView(rootView: Strip(switcher: model))
            let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 1600, height: 300),
                                  styleMask: [.borderless], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            window.contentView = hosting
            defer { window.close() }
            func settle() {
                for _ in 0..<25 {
                    hosting.layoutSubtreeIfNeeded()
                    RunLoop.current.run(until: Date().addingTimeInterval(0.012))
                }
            }
            func findScroll(_ view: NSView) -> NSScrollView? {
                if let scroll = view as? NSScrollView { return scroll }
                return view.subviews.compactMap { findScroll($0) }.first
            }
            func check(_ step: String) {
                settle()
                guard let scroll = findScroll(hosting), model.windows.indices.contains(model.selectedIndex) else {
                    suite.expect(false, "\(name)/\(step): missing scroll content")
                    return
                }
                let selected = model.windows[model.selectedIndex]
                let localIndex = model.windows.filter { $0.pid == selected.pid }.firstIndex { $0.id == selected.id }!
                let width = model.simple ? SwitcherIconRowLayout.simpleTitleChipMaxWidth : SwitcherIconRowLayout.previewCardWidth
                let spacing = model.simple ? SwitcherIconRowLayout.simpleTitleSpacing : SwitcherIconRowLayout.spacing
                let padding = model.simple ? SwitcherIconRowLayout.simpleTitleScrollPadding : 0
                let start = padding + CGFloat(localIndex) * (width + spacing)
                let clip = scroll.contentView.bounds
                suite.expect(!window.isVisible, "scroll tests never show a window")
                suite.expect(start >= clip.minX - 0.5 && start + width <= clip.maxX + 0.5,
                             "\(name)/\(step): selected \(selected.id) at \(start)...\(start + width) must fit \(clip.minX)...\(clip.maxX)")
            }
            body(model, check, settle)
        }
        for simple in [false, true] {
            let mode = simple ? "titles" : "previews"
            run("\(mode) search") { model, check, _ in
                model.seed([3,1,1,1,1,1,1], selected: 2, simple: simple); check("initial")
                model.search("a"); check("narrowed without changing selection")
                model.search(""); check("cleared search")
                model.select(index: 0); check("first")
                model.select(index: 2); check("last")
            }
            run("\(mode) boundary close") { model, check, _ in
                model.screenWidth = 640
                model.seed([8,8], selected: 7, simple: simple); check("initial")
                model.closeWindow(model.windows[7]); check("next app at unchanged index")
            }
            run("\(mode) replacing search result") { model, check, _ in
                model.screenWidth = 640
                model.seed([8,8], selected: 7, simple: simple); check("initial")
                model.search("keep"); check("new selection at unchanged index")
            }
            run("\(mode) navigation") { model, check, _ in
                model.screenWidth = 640
                model.seed([8,7], selected: 7, simple: simple); check("initial overflow")
                model.select(index: 0); check("wrap first")
                model.select(index: 7); check("wrap last")
                model.select(index: 8); check("second app first")
                model.select(index: 14); check("second app last")
                model.closeWindow(model.windows[10]); check("remove earlier card")
            }
            run("\(mode) pending reveal") { model, check, settle in
                model.seed([3,1,1,1,1,1,1], selected: 2, simple: simple); check("initial")
                model.search("a")
                model.select(index: 0); check("new selection wins")
                model.search("")
                model.windows = []
                model.selectedIndex = 0
                settle()
                model.seed([8], selected: 7, simple: simple); check("new session wins")
            }
            for size in Defaults.allowedPreviewSizes {
                UserDefaults.standard.set(size, forKey: DefaultsKey.previewSize)
                run("\(mode) \(size)") { model, check, _ in
                    model.screenWidth = 800
                    model.seed([3,1,1,1,1,1,1], selected: 2, simple: simple); check("initial")
                    model.search("a"); check("narrowed")
                    model.screenWidth = 640
                    model.recompute(); check("smaller display")
                }
            }
            UserDefaults.standard.set("normal", forKey: DefaultsKey.previewSize)
        }
    }
}
