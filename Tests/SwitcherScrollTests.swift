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
        var sessionScope: SwitcherSessionScope = .allApps
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
                                    maximumWindowCount: Dictionary(grouping: windows, by: \.pid).values.map(\.count).max() ?? 1,
                                    sessionScope: sessionScope,
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
        let previousSize = UserDefaults.standard.object(forKey: DefaultsKey.switcherPreviewSize)
        UserDefaults.standard.set("normal", forKey: DefaultsKey.switcherPreviewSize)
        defer {
            if let previousSize { UserDefaults.standard.set(previousSize, forKey: DefaultsKey.switcherPreviewSize) }
            else { UserDefaults.standard.removeObject(forKey: DefaultsKey.switcherPreviewSize) }
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
            func settle(until condition: () -> Bool = { true }) {
                var drainGeneration = 0
                DispatchQueue.main.async {
                    drainGeneration = 1
                    DispatchQueue.main.async { drainGeneration = 2 }
                }
                let deadline = Date().addingTimeInterval(0.5)
                repeat {
                    hosting.layoutSubtreeIfNeeded()
                    if drainGeneration == 2 && condition() { return }
                    RunLoop.current.run(until: min(deadline, Date().addingTimeInterval(0.012)))
                } while Date() < deadline
                hosting.layoutSubtreeIfNeeded()
            }
            func findScroll(_ view: NSView) -> NSScrollView? {
                if let scroll = view as? NSScrollView { return scroll }
                return view.subviews.compactMap { findScroll($0) }.first
            }
            func check(_ step: String) {
                settle {
                    guard let scroll = findScroll(hosting),
                          model.windows.indices.contains(model.selectedIndex) else { return false }
                    let selected = model.windows[model.selectedIndex]
                    let appWindows = model.windows.filter { $0.pid == selected.pid }
                    guard let localIndex = appWindows.firstIndex(where: { $0.id == selected.id }) else {
                        return false
                    }
                    let width = model.simple ? SwitcherIconRowLayout.simpleTitleChipMaxWidth
                        : SwitcherIconRowLayout.previewCardWidth
                    let spacing = model.simple ? SwitcherIconRowLayout.simpleTitleSpacing
                        : SwitcherIconRowLayout.spacing
                    let padding = model.simple ? SwitcherIconRowLayout.simpleTitleScrollPadding : 0
                    let clip = scroll.contentView.bounds
                    let expectedWidth = model.simple
                        ? model.iconRowLayout.contentWidth(simpleMode: true, windowRow: false)
                            - 2 * SwitcherIconRowLayout.simpleTitlePanelPadding
                        : model.iconRowLayout.previewContentWidth
                    guard abs(clip.width - expectedWidth) <= 1 else { return false }
                    if !model.simple && appWindows.count == 2 && model.screenWidth >= 800 {
                        return clip.minX <= 0.5 && clip.maxX >= width * 2 + spacing - 0.5
                    }
                    let start = padding + CGFloat(localIndex) * (width + spacing)
                    return start >= clip.minX - 0.5 && start + width <= clip.maxX + 0.5
                }
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
                if !model.simple && model.windows.filter({ $0.pid == selected.pid }).count == 2
                    && model.screenWidth >= 800 {
                    suite.expect(clip.minX <= 0.5 && clip.maxX >= width * 2 + spacing - 0.5,
                                 "\(name)/\(step): both windows must be visible together")
                }
                if !model.simple && model.sessionScope == .frontmostApp && model.screenWidth >= 1440 {
                    let count = model.windows.filter { $0.pid == selected.pid }.count
                    let naturalWidth = SwitcherIconRowLayout.naturalPreviewWidth(cardCount: count)
                    suite.expect(clip.minX <= 0.5 && clip.maxX >= naturalWidth - 0.5,
                                 "\(name)/\(step): all focused-app previews fit together")
                }
                suite.expect(!window.isVisible, "scroll tests never show a window")
                suite.expect(start >= clip.minX - 0.5 && start + width <= clip.maxX + 0.5,
                             "\(name)/\(step): selected \(selected.id) at \(start)...\(start + width) must fit \(clip.minX)...\(clip.maxX)")
            }
            body(model, check, { settle() })
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
                UserDefaults.standard.set(size, forKey: DefaultsKey.switcherPreviewSize)
                if !simple {
                    run("focused app \(size)") { model, check, _ in
                        model.sessionScope = .frontmostApp
                        model.seed([4], selected: 1); check("four previews")
                        model.select(index: 3); check("last window")
                        model.screenWidth = 640
                        model.recompute(); check("narrow display overflow")
                        model.select(index: 0); check("overflow wraps to first")
                    }
                }
                run("\(mode) \(size)") { model, check, _ in
                    model.screenWidth = 800
                    model.seed([2], selected: 1, simple: simple); check("single app pair")
                    model.select(index: 0); check("pair first")
                    model.seed([3,1,1,1,1,1,1], selected: 2, simple: simple); check("initial")
                    model.search("a"); check("narrowed")
                    model.screenWidth = 640
                    model.recompute(); check("smaller display")
                }
            }
            UserDefaults.standard.set("normal", forKey: DefaultsKey.switcherPreviewSize)
        }

        // Arrows name a screen direction; the grid is drawn in reverse in a
        // mirrored interface, so the index they step to is reversed with it.
        // Shortcut cycling names next and previous and is deliberately not
        // routed through this.
        suite.expect(SwitcherSupport.horizontalArrowDelta(towardTrailingEdge: true, rightToLeft: false) == 1
                     && SwitcherSupport.horizontalArrowDelta(towardTrailingEdge: false, rightToLeft: false) == -1,
                     "left to right, the right arrow advances the selection")
        suite.expect(SwitcherSupport.horizontalArrowDelta(towardTrailingEdge: true, rightToLeft: true) == -1
                     && SwitcherSupport.horizontalArrowDelta(towardTrailingEdge: false, rightToLeft: true) == 1,
                     "mirrored, each arrow picks the neighbour it points at")
    }
}
