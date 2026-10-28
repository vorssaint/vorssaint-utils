// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import SwiftUI

/// Production panel and search bodies, with inert content of the same size.
/// Geometry is measured without presenting a window or sending desktop input;
/// the actual materials and foreground contrast still need visual validation.
enum SwitcherSearchLayoutTests {
    enum Mode: CaseIterable { case grid, icons, simpleApps, simpleWindows }
    struct NSScreen { let visibleFrame: CGRect }

    final class Model: ObservableObject {
        let mode: Mode
        let showsHints: Bool
        @Published var windows = [1]
        @Published var searchQuery = ""
        @Published var isSearchPinned = false
        var totalWindowCount = 987
        var grid = SwitcherGrid.empty
        var iconRowLayout = SwitcherIconRowLayout.empty
        var recomputations = 0
        var resizes = 0
        var resizedTo = CGSize.zero
        var usesIconRowLayout: Bool { mode != .grid }
        var simpleModeEnabled: Bool { mode == .simpleApps || mode == .simpleWindows }
        var usesWindowRow: Bool { mode == .simpleWindows }

        init(mode: Mode, showsHints: Bool) {
            self.mode = mode
            self.showsHints = showsHints
            recomputeLayouts(for: windows)
        }

        func recomputeLayouts(for items: [Int]) {
            recomputations += 1
            let screen = NSScreen(visibleFrame: CGRect(x: 0, y: 0, width: 1440, height: 900))
            grid = .compute(count: max(1, items.count), on: screen, searchTopInset: searchTopInset)
            iconRowLayout = .compute(appCount: items.count, selectedWindowCount: 1,
                                     screenVisibleFrame: screen.visibleFrame, showsShortcutHints: showsHints,
                                     tileWidth: usesWindowRow ? SwitcherIconRowLayout.windowTileWidth
                                         : SwitcherIconRowLayout.appTileWidth,
                                     searchTopInset: searchTopInset)
        }

        func resizePanel() { resizes += 1; resizedTo = currentPanelSize }

        func search(_ query: String, results: [Int] = [1]) {
            searchQuery = query
            windows = results
            recomputeLayouts(for: windows)
            resizePanel()
        }

        var contentSize: CGSize {
            guard !windows.isEmpty else { return grid.panelSize }
            switch mode {
            case .grid: return grid.panelSize
            case .icons: return iconRowLayout.panelSize
            case .simpleApps: return iconRowLayout.simplePanelSize
            case .simpleWindows: return iconRowLayout.simpleWindowPanelSize
            }
        }
    }

    final class Measurements: ObservableObject {
        var frames: [String: CGRect] = [:]
        var searchContrast: HUDBackdrop.Contrast?
    }

    struct Probe: View {
        let name: String
        var contrast: HUDBackdrop.Contrast? = nil
        @EnvironmentObject var measurements: Measurements
        var body: some View {
            GeometryReader { proxy in
                let frame = proxy.frame(in: .named("switcher-search-test"))
                Color.clear
                    .onAppear { report(frame) }
                    .onChange(of: frame) { _, newFrame in report(newFrame) }
            }
        }
        func report(_ frame: CGRect) {
            measurements.frames[name] = frame
            if let contrast { measurements.searchContrast = contrast }
        }
    }

    struct HUDBackdrop: View {
        enum Contrast { case standard, high }
        let cornerRadius: CGFloat
        var body: some View { Color.clear }
    }

    struct SwitcherIconRowSurface: View {
        let cornerRadius: CGFloat
        let fill: Color
        var contrast: HUDBackdrop.Contrast = .standard
        var body: some View { Probe(name: "search", contrast: contrast) }
    }

    struct Strings {
        var s: Self { self }
        let switcherSearchPin = "Search windows"
    }

    struct Host: View {
        @ObservedObject var switcher: Model
        let l10n = Strings()
        let minimalPreviews = false
        var iconRowMode: Bool { switcher.usesIconRowLayout }
        var simpleMode: Bool { switcher.simpleModeEnabled }
        var usesWindowRow: Bool { switcher.usesWindowRow }
        var cardGrid: some View { Probe(name: "content") }
        var emptyState: some View { Probe(name: "content") }
        var iconRowSwitcher: some View {
            Probe(name: "content")
                .frame(width: iconRowPanelSize.width - 2 * SwitcherIconRowLayout.padding,
                       height: iconRowPanelSize.height - 2 * SwitcherIconRowLayout.padding)
                .padding(SwitcherIconRowLayout.padding)
        }
    }

    static func run(_ suite: TestSuite) {
        MainActor.assumeIsolated {
            let previousSize = UserDefaults.standard.object(forKey: DefaultsKey.switcherPreviewSize)
            defer {
                if let previousSize { UserDefaults.standard.set(previousSize, forKey: DefaultsKey.switcherPreviewSize) }
                else { UserDefaults.standard.removeObject(forKey: DefaultsKey.switcherPreviewSize) }
            }
            for size in Defaults.allowedPreviewSizes {
                UserDefaults.standard.set(size, forKey: DefaultsKey.switcherPreviewSize)
                for mode in Mode.allCases {
                    for hints in [false, true] {
                        let name = "Switcher search \(mode), \(size), hints=\(hints)"
                        let model = Model(mode: mode, showsHints: hints)
                        let original = model.currentPanelSize
                        suite.expect(original == model.contentSize && model.searchTopInset == 0,
                                     "\(name): no search preserves the content's original size")
                        checkLayout(suite, model: model, name: name, visible: false)
                        model.search("spot")
                        suite.expect(model.currentPanelSize.width == original.width
                                     && model.currentPanelSize.height > original.height,
                                     "\(name): typing reserves a header without changing content width")
                        checkLayout(suite, model: model, name: name, visible: true)
                        model.search("")
                        suite.expect(model.currentPanelSize == original,
                                     "\(name): clearing an unpinned query restores the original size")
                        let before = (model.recomputations, model.resizes)
                        model.pinSearch()
                        suite.expect(model.isSearchPinned && model.recomputations == before.0 + 1
                                     && model.resizes == before.1 + 1 && model.resizedTo == model.currentPanelSize
                                     && model.currentPanelSize.height > original.height,
                                     "\(name): pinning an empty query recomputes and resizes immediately")
                        checkLayout(suite, model: model, name: name + " pinned", visible: true)
                        model.search(String(repeating: "long query ", count: 6))
                        checkLayout(suite, model: model, name: name + " long query", visible: true)
                        let pinnedSize = model.currentPanelSize
                        model.search("")
                        suite.expect(model.currentPanelSize == pinnedSize,
                                     "\(name): clearing a pinned query keeps the search header")
                        model.search("missing", results: [])
                        suite.expect(model.currentPanelSize.width == model.grid.panelSize.width,
                                     "\(name): no results use the same grid width as the empty-state view")
                        checkLayout(suite, model: model, name: name + " no results", visible: true)
                    }
                }
                checkScreenBudget(suite, size: size)
            }
        }
    }

    @MainActor private static func checkLayout(_ suite: TestSuite, model: Model,
                                               name: String, visible: Bool) {
        let measurements = Measurements()
        let size = model.currentPanelSize
        let host = NSHostingView(rootView: Host(switcher: model)
            .frame(width: size.width, height: size.height)
            .coordinateSpace(name: "switcher-search-test")
            .environmentObject(measurements))
        host.sizingOptions = []
        host.frame = CGRect(origin: .zero, size: size)
        let deadline = Date().addingTimeInterval(0.5)
        var layoutPasses = 0
        repeat {
            host.layoutSubtreeIfNeeded()
            RunLoop.current.run(until: min(deadline, Date().addingTimeInterval(0.01)))
            layoutPasses += 1
        } while (layoutPasses < 2 || measurements.frames["content"] == nil
                 || (visible && measurements.frames["search"] == nil))
                    && Date() < deadline
        guard let content = measurements.frames["content"] else {
            suite.expect(false, "\(name): content reports its geometry")
            return
        }
        let bounds = CGRect(origin: .zero, size: size).insetBy(dx: -0.5, dy: -0.5)
        suite.expect(bounds.contains(content), "\(name): preview or empty content stays inside the panel")
        guard visible else {
            suite.expect(measurements.frames["search"] == nil, "\(name): no search surface is drawn")
            return
        }
        guard let search = measurements.frames["search"] else {
            suite.expect(false, "\(name): the search surface reports its geometry")
            return
        }
        suite.expect(bounds.contains(search) && search.width > 0
                     && abs(search.height - SwitcherSearchLayout.chipHeight) < 0.5,
                     "\(name): the entire search surface fits inside the panel")
        suite.expect(content.minY - search.maxY >= SwitcherSearchLayout.contentGap - 0.5,
                     "\(name): the search surface leaves a gap above previews (\(search), \(content))")
        suite.expect(measurements.searchContrast == .high,
                     "\(name): the separate search surface requests readable foreground contrast")
    }

    private static func checkScreenBudget(_ suite: TestSuite, size: String) {
        for height in stride(from: 650, through: 1050, by: 25) {
            let screen = NSScreen(visibleFrame: CGRect(x: 0, y: 0, width: 1440, height: CGFloat(height)))
            let gridInset = SwitcherSearchLayout.topInset(query: "spot", isPinned: false,
                                                          contentPadding: SwitcherGrid.padding)
            let grid = SwitcherGrid.compute(count: 60, on: screen, maxColumns: 2, searchTopInset: gridInset)
            suite.expect(grid.panelSize.height + gridInset <= screen.visibleFrame.height * 0.85 + 0.5,
                         "Switcher \(size): search and grid rows share the \(height)-point screen budget")
            let iconInset = SwitcherSearchLayout.topInset(query: "", isPinned: true,
                                                          contentPadding: SwitcherIconRowLayout.padding)
            let icons = SwitcherIconRowLayout.compute(appCount: 60, selectedWindowCount: 1,
                                                       screenVisibleFrame: screen.visibleFrame,
                                                       maxColumns: 2, searchTopInset: iconInset)
            suite.expect(icons.panelSize.height + iconInset <= screen.visibleFrame.height * 0.85 + 0.5,
                         "Switcher \(size): pinned search and wrapped icons share the \(height)-point screen budget")
        }
    }
}
