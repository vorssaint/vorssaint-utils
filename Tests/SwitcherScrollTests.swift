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

    private enum ObservationPolicy {
        static let floor = 0.5
        static let deadline = 2.0
        static let stableDuration = 0.15
        static let stableSamples = 3
        static let pumpSlice = 0.012
    }

    private struct ObservationGeometry: Equatable {
        let clip: CGRect
        let clipFrame: CGRect
        let documentBounds: CGRect?
        let documentFrame: CGRect?
        let expectedViewport: CGFloat
        let start: CGFloat
        let width: CGFloat
        let spacing: CGFloat
        let padding: CGFloat
        let naturalPreviewWidth: CGFloat
    }

    /// Native layout output stays observable even before a scroll view exists.
    private struct ObservationOutput: Equatable {
        let windowFrame: CGRect
        let geometry: ObservationGeometry?

        var windowFrameValid: Bool {
            windowFrame.origin.x.isFinite && windowFrame.origin.y.isFinite
                && windowFrame.size.width.isFinite && windowFrame.size.height.isFinite
                && windowFrame.maxX.isFinite && windowFrame.maxY.isFinite
                && windowFrame.size.width > 0 && windowFrame.size.height > 0
        }
    }

    private struct ObservationSample {
        let elapsed: Double
        let output: ObservationOutput
        var geometry: ObservationGeometry? { output.geometry }
        let selectedIndex: Int
        let selectedID: String?
        let drainGeneration: Int
        let selectionMatches: Bool
        let inputsUnchanged: Bool
        let viewportMatches: Bool
        let selectedVisible: Bool
        let pairVisible: Bool
        let allPreviewsVisible: Bool
        let windowUnordered: Bool
        let activationProhibited: Bool

        var valid: Bool {
            output.windowFrameValid && geometry?.documentFrame != nil && geometry?.documentBounds != nil
                && selectionMatches && inputsUnchanged
                && viewportMatches && selectedVisible && pairVisible && allPreviewsVisible
                && windowUnordered && activationProhibited && drainGeneration == 2
        }
    }

    /// Consumes observations only; it cannot select or scroll a native view.
    private struct ObservationState {
        private(set) var last: ObservationSample?
        private(set) var oldBoundary: ObservationSample?
        private(set) var beforeBoundary: ObservationSample?
        var beforeBoundaryElapsed: Double? { beforeBoundary?.elapsed }
        private(set) var firstVisible: Double?
        private(set) var firstValid: Double?
        private(set) var firstStable: Double?
        private(set) var stableSince: Double?
        private(set) var stableSamples = 0
        private(set) var samples = 0
        private(set) var largestGap = 0.0
        private(set) var qualifiedOnce = false
        private(set) var regressionLatched = false
        private(set) var identityChanged = false
        private(set) var clockInvalid = false
        private(set) var terminalInvalid = false
        private(set) var geometryChanges = 0
        private(set) var transitions: [(Double, ObservationOutput)] = []

        var stableFor: Double {
            guard let last, let stableSince else { return 0 }
            return max(0, last.elapsed - stableSince)
        }
        var currentlyStable: Bool {
            last?.valid == true && stableSamples >= ObservationPolicy.stableSamples
                && stableFor >= ObservationPolicy.stableDuration
        }
        var canFinish: Bool {
            guard let last else { return false }
            return last.elapsed >= ObservationPolicy.floor && last.elapsed < ObservationPolicy.deadline
                && currentlyStable && !regressionLatched && !identityChanged && !clockInvalid && !terminalInvalid
        }
        var boundaryGap: Double? {
            guard let oldBoundary, let beforeBoundaryElapsed else { return nil }
            return oldBoundary.elapsed - beforeBoundaryElapsed
        }
        // A gap longer than the requested pump slice is reported conservatively
        // for interpretation; it is never an interpolated observation at 0.500.
        var boundaryUncertain: Bool {
            guard let oldBoundary, let boundaryGap else { return true }
            return oldBoundary.elapsed >= ObservationPolicy.deadline
                || boundaryGap > ObservationPolicy.pumpSlice
                || oldBoundary.elapsed - ObservationPolicy.floor > ObservationPolicy.pumpSlice
        }
        var lateAssessmentRequired: Bool {
            oldBoundary?.valid != true || firstVisible.map { $0 > ObservationPolicy.floor } != false
                || firstValid.map { $0 > ObservationPolicy.floor } != false || boundaryUncertain
        }

        mutating func consumeFinal(_ sample: ObservationSample) {
            if last?.valid != true || !sample.valid || last?.output != sample.output {
                terminalInvalid = true
            }
            consume(sample)
        }

        mutating func consume(_ sample: ObservationSample) {
            samples += 1
            if !sample.elapsed.isFinite || sample.elapsed < 0
                || last.map({ sample.elapsed < $0.elapsed }) == true { clockInvalid = true }
            if let last { largestGap = max(largestGap, sample.elapsed - last.elapsed) }
            if oldBoundary == nil && sample.elapsed >= ObservationPolicy.floor {
                oldBoundary = sample
                beforeBoundary = last
            }
            if firstVisible == nil && sample.selectedVisible && sample.selectionMatches {
                firstVisible = sample.elapsed
            }
            if firstValid == nil && sample.valid { firstValid = sample.elapsed }
            if !sample.selectionMatches || !sample.inputsUnchanged { identityChanged = true }
            if qualifiedOnce && !sample.valid { regressionLatched = true }
            if let last, last.output != sample.output {
                geometryChanges += 1
                transitions.append((sample.elapsed, sample.output))
                if transitions.count > 16 { transitions.remove(at: 8) }
            }
            if sample.valid {
                if last?.valid == true && last?.output == sample.output {
                    stableSamples += 1
                } else {
                    stableSince = sample.elapsed
                    stableSamples = 1
                }
            } else {
                stableSince = nil
                stableSamples = 0
            }
            last = sample
            if currentlyStable && sample.elapsed < ObservationPolicy.deadline && !clockInvalid {
                qualifiedOnce = true
                if firstStable == nil { firstStable = sample.elapsed }
            }
        }
    }

    private struct ObservationInputs: Equatable {
        let items: [String]
        let sessionItems: [String]
        let selectedIndex: Int
        let selectedID: String?
        let simple: Bool
        let instant: Bool
        let scope: SwitcherSessionScope
        let screenWidth: CGFloat
        let previewSizeLookup: String
        let search: String
        let previews: [String]
        let layout: SwitcherIconRowLayout
    }

    /// Primitive samples exercise the reducer, separately from native geometry.
    private static func observationStateContracts(_ suite: TestSuite) {
        let geometry = ObservationGeometry(clip: CGRect(x: 0, y: 0, width: 200, height: 30),
            clipFrame: CGRect(x: 0, y: 0, width: 200, height: 30),
            documentBounds: CGRect(x: 0, y: 0, width: 500, height: 30),
            documentFrame: CGRect(x: 0, y: 0, width: 500, height: 30),
            expectedViewport: 200, start: 1, width: 100, spacing: 3, padding: 1, naturalPreviewWidth: 0)
        func sample(_ time: Double, visible: Bool = true, selection: Bool = true,
                    inputs: Bool = true, drain: Int = 2, present: Bool = true, offset: CGFloat = 0,
                    windowFrame: CGRect = CGRect(x: 0, y: 0, width: 500, height: 100)) -> ObservationSample {
            let measured = ObservationGeometry(clip: geometry.clip.offsetBy(dx: offset, dy: 0),
                clipFrame: geometry.clipFrame, documentBounds: geometry.documentBounds,
                documentFrame: geometry.documentFrame, expectedViewport: geometry.expectedViewport,
                start: geometry.start, width: geometry.width, spacing: geometry.spacing,
                padding: geometry.padding, naturalPreviewWidth: geometry.naturalPreviewWidth)
            return ObservationSample(elapsed: time,
                output: ObservationOutput(windowFrame: windowFrame, geometry: present ? measured : nil),
                selectedIndex: selection ? 0 : 1, selectedID: selection ? "0" : "1",
                drainGeneration: drain, selectionMatches: selection, inputsUnchanged: inputs,
                viewportMatches: true, selectedVisible: visible, pairVisible: true,
                allPreviewsVisible: true, windowUnordered: true, activationProhibited: true)
        }
        func check(_ name: String, _ samples: [ObservationSample], accepted: Bool,
                   regression: Bool = false, late: Bool? = nil, final: ObservationSample? = nil,
                   recovery: [ObservationSample] = [], terminal: Bool? = nil, currentStable: Bool? = nil) {
            var state = ObservationState()
            samples.forEach { state.consume($0) }
            if let final { state.consumeFinal(final) }
            recovery.forEach { state.consume($0) }
            let terminalMatches = terminal.map { state.terminalInvalid == $0 } ?? true
            let stabilityMatches = currentStable.map { state.currentlyStable == $0 } ?? true
            let lateMatches = late.map { state.lateAssessmentRequired == $0 } ?? true
            suite.expect(state.canFinish == accepted && state.regressionLatched == regression
                   && lateMatches && terminalMatches && stabilityMatches,
                   "scroll observation reducer \(name): accepted=\(state.canFinish), regression=\(state.regressionLatched), late=\(state.lateAssessmentRequired), terminal=\(state.terminalInvalid), currently-stable=\(state.currentlyStable)")
            print("SWITCHER SCROLL REDUCER case=\(name), accepted=\(state.canFinish), expected=\(accepted), regression=\(state.regressionLatched), late=\(state.lateAssessmentRequired), terminal=\(state.terminalInvalid), currently-stable=\(state.currentlyStable)")
        }
        check("never-visible", [sample(0, visible: false), sample(0.5, visible: false),
                               sample(2, visible: false)], accepted: false)
        check("single-transient", [sample(0, visible: false), sample(0.2),
                                  sample(0.3, visible: false), sample(2, visible: false)], accepted: false)
        let stable = [sample(0), sample(0.08), sample(0.16)]
        check("stable-then-hidden", stable + [sample(0.3, visible: false), sample(0.5),
                                             sample(0.6), sample(0.76)], accepted: false, regression: true)
        check("selected-id-change", stable + [sample(0.3, selection: false), sample(0.5),
                                             sample(0.66)], accepted: false, regression: true)
        check("input-change", stable + [sample(0.3, inputs: false), sample(0.5),
                                       sample(0.66)], accepted: false, regression: true)
        check("missing-scroll", stable + [sample(0.3, present: false), sample(0.5),
                                         sample(0.66)], accepted: false, regression: true)
        check("incomplete-drain", [sample(0, drain: 1), sample(0.2, drain: 1),
                                  sample(0.5, drain: 1), sample(1.99, drain: 1)], accepted: false)
        check("first-valid-after-deadline", [sample(0, visible: false), sample(2.01),
                                           sample(2.1), sample(2.3)], accepted: false)
        check("stable-positive", stable + [sample(0.49), sample(0.5), sample(0.501)],
              accepted: true, late: false)
        check("final-fresh-geometry-change", stable + [sample(0.49), sample(0.5)],
              accepted: false, final: sample(0.501, offset: 1),
              recovery: [sample(0.6, offset: 1), sample(0.7, offset: 1), sample(0.8, offset: 1)],
              terminal: true, currentStable: true)
        check("late-recovery", [sample(0, visible: false), sample(0.5, visible: false),
                               sample(0.7), sample(0.78), sample(0.86)], accepted: true, late: true)

        let frameA = CGRect(x: 0, y: 0, width: 500, height: 100)
        let frameB = CGRect(x: 7, y: 9, width: 452, height: 164)
        var autosize = ObservationState()
        [sample(0, windowFrame: frameA), sample(0.08, windowFrame: frameA)].forEach { autosize.consume($0) }
        let beforeResize = autosize.last
        autosize.consume(sample(0.1, windowFrame: frameB))
        let resizeReset = autosize.stableSince == 0.1 && autosize.stableSamples == 1
            && autosize.geometryChanges == 1 && !autosize.qualifiedOnce && !autosize.canFinish
            && autosize.last?.geometry == beforeResize?.geometry && !autosize.identityChanged
        autosize.consume(sample(0.18, windowFrame: frameB))
        let twoSamplesInsufficient = !autosize.currentlyStable && !autosize.canFinish
        autosize.consume(sample(0.26, windowFrame: frameB))
        let newFrameEarnedStability = autosize.currentlyStable && autosize.stableSince == 0.1
            && autosize.stableSamples == 3 && !autosize.canFinish
        autosize.consume(sample(0.49, windowFrame: frameB))
        let floorPreserved = !autosize.canFinish
        autosize.consume(sample(0.5, windowFrame: frameB))
        let autosizeAccepted = resizeReset && twoSamplesInsufficient && newFrameEarnedStability
            && floorPreserved && autosize.canFinish && !autosize.identityChanged
        suite.expect(autosizeAccepted, "scroll observation reducer native-output-autosize-before-qualification: new frame earns exact stability and floor without changing logical inputs")
        print("SWITCHER SCROLL REDUCER case=native-output-autosize-before-qualification, accepted=\(autosize.canFinish), expected=true, reset=\(resizeReset), two-samples-insufficient=\(twoSamplesInsufficient), new-frame-stable=\(newFrameEarnedStability), floor-preserved=\(floorPreserved), identity-changed=\(autosize.identityChanged), geometry-changes=\(autosize.geometryChanges), contract=\(autosizeAccepted)")

        var unsettled = ObservationState()
        let changingTimes = [0.0, 0.1, 0.2, 0.3, 0.4, 0.5, 0.6, 0.7, 0.8, 0.9,
                             1.0, 1.1, 1.2, 1.3, 1.4, 1.5, 1.6, 1.7, 1.8, 1.9, 1.99]
        for (index, elapsed) in changingTimes.enumerated() {
            unsettled.consume(sample(elapsed, windowFrame: index.isMultiple(of: 2) ? frameA : frameB))
        }
        let neverSettled = !unsettled.canFinish && !unsettled.qualifiedOnce && !unsettled.currentlyStable
            && !unsettled.identityChanged && unsettled.last?.valid == true
            && unsettled.last?.elapsed == 1.99 && unsettled.stableSamples == 1
            && unsettled.stableSince == 1.99 && unsettled.geometryChanges == changingTimes.count - 1
        suite.expect(neverSettled, "scroll observation reducer native-output-frame-never-settles: frame-only changes cannot qualify before the deadline")
        print("SWITCHER SCROLL REDUCER case=native-output-frame-never-settles, accepted=\(unsettled.canFinish), expected=false, qualified=\(unsettled.qualifiedOnce), currently-stable=\(unsettled.currentlyStable), identity-changed=\(unsettled.identityChanged), elapsed=\(unsettled.last?.elapsed ?? -1), geometry-changes=\(unsettled.geometryChanges), contract=\(neverSettled)")

        var finalFrame = ObservationState()
        (stable + [sample(0.49), sample(0.5)]).forEach { finalFrame.consume($0) }
        let finishBeforeFrameChange = finalFrame.canFinish
        let priorClipGeometry = finalFrame.last?.geometry
        finalFrame.consumeFinal(sample(0.501, windowFrame: frameB))
        let frameOnlyFinalRejected = finalFrame.terminalInvalid && !finalFrame.canFinish
            && finalFrame.last?.geometry == priorClipGeometry && finalFrame.last?.valid == true
            && !finalFrame.identityChanged
        [sample(0.6, windowFrame: frameB), sample(0.7, windowFrame: frameB),
         sample(0.8, windowFrame: frameB)].forEach { finalFrame.consume($0) }
        let finalFrameRejected = finishBeforeFrameChange && frameOnlyFinalRejected
            && finalFrame.currentlyStable && finalFrame.terminalInvalid && !finalFrame.canFinish
        suite.expect(finalFrameRejected, "scroll observation reducer fresh-final-window-frame-only-change: terminal movement remains rejected after stable recovery")
        print("SWITCHER SCROLL REDUCER case=fresh-final-window-frame-only-change, accepted=\(finalFrame.canFinish), expected=false, qualified-before-final=\(finishBeforeFrameChange), frame-only-rejected=\(frameOnlyFinalRejected), terminal=\(finalFrame.terminalInvalid), currently-stable=\(finalFrame.currentlyStable), identity-changed=\(finalFrame.identityChanged), contract=\(finalFrameRejected)")
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
        let instantSelection: Bool
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
        observationStateContracts(suite)
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
        var visibilityChecks: [String: Int] = [:]
        var wrapChecks: [String: Int] = [:]
        var drainOnlyChecks = 0
        func decimal(_ value: Double) -> String { String(format: "%.3f", value) }
        func rect(_ value: CGRect?) -> String {
            guard let value else { return "none" }
            return "(\(decimal(Double(value.minX))),\(decimal(Double(value.minY))),\(decimal(Double(value.width))),\(decimal(Double(value.height))))"
        }
        func time(_ value: Double?) -> String { value.map(decimal) ?? "none" }
        func describe(_ sample: ObservationSample?) -> String {
            guard let sample else { return "none" }
            let g = sample.geometry
            return [
                "elapsed=\(decimal(sample.elapsed))", "selected-index=\(sample.selectedIndex)",
                "selected-id=\(sample.selectedID ?? "none")",
                "output-window-frame=\(rect(sample.output.windowFrame))",
                "output-window-frame-valid=\(sample.output.windowFrameValid)", "clip=\(rect(g?.clip))",
                "clip-frame=\(rect(g?.clipFrame))", "document=\(rect(g?.documentFrame))",
                "document-bounds=\(rect(g?.documentBounds))",
                "expected-viewport=\(g.map { decimal(Double($0.expectedViewport)) } ?? "none")",
                "card-start=\(g.map { decimal(Double($0.start)) } ?? "none")",
                "card-width=\(g.map { decimal(Double($0.width)) } ?? "none")",
                "spacing=\(g.map { decimal(Double($0.spacing)) } ?? "none")",
                "padding=\(g.map { decimal(Double($0.padding)) } ?? "none")",
                "selection=\(sample.selectionMatches)", "inputs=\(sample.inputsUnchanged)",
                "viewport=\(sample.viewportMatches)", "visible=\(sample.selectedVisible)",
                "pair=\(sample.pairVisible)", "all-previews=\(sample.allPreviewsVisible)",
                "unordered=\(sample.windowUnordered)", "prohibited=\(sample.activationProhibited)",
                "fixture-drain=\(sample.drainGeneration)", "valid=\(sample.valid)",
            ].joined(separator: ", ")
        }
        func run(_ name: String, instantSelection: Bool = false,
                 _ body: (Model, (String) -> Void, () -> Void, (Int, String) -> Void) -> Void) {
            let model = Model()
            let hosting = NSHostingView(rootView: Strip(switcher: model,
                                                      instantSelection: instantSelection))
            let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 1600, height: 300),
                                  styleMask: [.borderless], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            window.contentView = hosting
            defer { window.close() }
            func findScroll(_ view: NSView) -> NSScrollView? {
                if let scroll = view as? NSScrollView { return scroll }
                return view.subviews.compactMap { findScroll($0) }.first
            }
            func drainOnly() {
                drainOnlyChecks += 1
                let began = ProcessInfo.processInfo.systemUptime
                var drainGeneration = 0
                DispatchQueue.main.async {
                    drainGeneration = 1
                    DispatchQueue.main.async { drainGeneration = 2 }
                }
                repeat {
                    hosting.layoutSubtreeIfNeeded()
                    let elapsed = ProcessInfo.processInfo.systemUptime - began
                    if drainGeneration == 2 || elapsed >= ObservationPolicy.deadline { break }
                    RunLoop.current.run(until: Date().addingTimeInterval(
                        min(ObservationPolicy.pumpSlice, ObservationPolicy.deadline - elapsed)))
                } while true
                let elapsed = ProcessInfo.processInfo.systemUptime - began
                let valid = drainGeneration == 2 && elapsed < ObservationPolicy.deadline
                    && model.windows.isEmpty && !window.isVisible && NSApp.activationPolicy() == .prohibited
                print("SWITCHER SCROLL DRAIN scenario=\(name), elapsed=\(decimal(elapsed)), deadline=2.000, fixture-drain=\(drainGeneration), items=\(model.windows.count), valid=\(valid)")
                suite.expect(valid, "\(name): empty-session drain finishes without selected-card visibility")
            }
            func inputs() -> ObservationInputs {
                ObservationInputs(items: model.windows.map { "\($0.id)@\($0.pid)" },
                    sessionItems: model.sessionItems.map { "\($0.id)@\($0.pid)" },
                    selectedIndex: model.selectedIndex,
                    selectedID: model.windows.indices.contains(model.selectedIndex) ? model.windows[model.selectedIndex].id : nil,
                    simple: model.simple, instant: instantSelection, scope: model.sessionScope,
                    screenWidth: model.screenWidth,
                    previewSizeLookup: String(reflecting: UserDefaults.standard.object(forKey: DefaultsKey.switcherPreviewSize)),
                    search: model.searchQuery,
                    previews: model.previews.sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value)" },
                    layout: model.iconRowLayout)
            }
            func capture(began: Double, expected: ObservationInputs, drain: Int) -> ObservationSample {
                let current = inputs()
                // Read native frame in the same synchronous capture as scroll geometry.
                // It is layout output, including while scroll geometry is missing.
                let nativeWindowFrame = window.frame
                let scroll = findScroll(hosting)
                var geometry: ObservationGeometry?
                var viewport = false, visible = false, pair = false, previews = false
                if let scroll, model.windows.indices.contains(model.selectedIndex) {
                    let selected = model.windows[model.selectedIndex]
                    let appWindows = model.windows.filter { $0.pid == selected.pid }
                    if let localIndex = appWindows.firstIndex(where: { $0.id == selected.id }) {
                        let width = model.simple ? SwitcherIconRowLayout.simpleTitleChipMaxWidth : SwitcherIconRowLayout.previewCardWidth
                        let spacing = model.simple ? SwitcherIconRowLayout.simpleTitleSpacing : SwitcherIconRowLayout.spacing
                        let padding = model.simple ? SwitcherIconRowLayout.simpleTitleScrollPadding : 0
                        let start = padding + CGFloat(localIndex) * (width + spacing)
                        let clip = scroll.contentView.bounds
                        let expectedWidth = model.simple
                            ? model.iconRowLayout.contentWidth(simpleMode: true, windowRow: false)
                                - 2 * SwitcherIconRowLayout.simpleTitlePanelPadding
                            : model.iconRowLayout.previewContentWidth
                        let natural = SwitcherIconRowLayout.naturalPreviewWidth(cardCount: appWindows.count)
                        viewport = abs(clip.width - expectedWidth) <= 1
                        visible = start >= clip.minX - 0.5 && start + width <= clip.maxX + 0.5
                        pair = model.simple || appWindows.count != 2 || model.screenWidth < 800
                            || (clip.minX <= 0.5 && clip.maxX >= width * 2 + spacing - 0.5)
                        previews = model.simple || model.sessionScope != .frontmostApp || model.screenWidth < 1440
                            || (clip.minX <= 0.5 && clip.maxX >= natural - 0.5)
                        geometry = ObservationGeometry(clip: clip, clipFrame: scroll.contentView.frame,
                            documentBounds: scroll.documentView?.bounds, documentFrame: scroll.documentView?.frame,
                            expectedViewport: expectedWidth, start: start, width: width,
                            spacing: spacing, padding: padding, naturalPreviewWidth: natural)
                    }
                }
                return ObservationSample(elapsed: ProcessInfo.processInfo.systemUptime - began,
                    output: ObservationOutput(windowFrame: nativeWindowFrame, geometry: geometry),
                    selectedIndex: current.selectedIndex, selectedID: current.selectedID,
                    drainGeneration: drain,
                    selectionMatches: expected.selectedID != nil && current.selectedIndex == expected.selectedIndex
                        && current.selectedID == expected.selectedID,
                    inputsUnchanged: current == expected, viewportMatches: viewport, selectedVisible: visible,
                    pairVisible: pair, allPreviewsVisible: previews,
                    windowUnordered: !window.isVisible, activationProhibited: NSApp.activationPolicy() == .prohibited)
            }
            func inputDescription(_ value: ObservationInputs) -> String {
                [
                    "items=\(value.items.joined(separator: "|"))",
                    "session-items=\(value.sessionItems.joined(separator: "|"))",
                    "selected-index=\(value.selectedIndex)", "selected-id=\(value.selectedID ?? "none")",
                    "simple=\(value.simple)", "instant=\(value.instant)",
                    "scope=\(String(describing: value.scope))", "screen=\(decimal(Double(value.screenWidth)))",
                    "preview-size-lookup=\(value.previewSizeLookup)", "search=\(String(reflecting: value.search))",
                    "previews=\(value.previews.joined(separator: "|"))",
                    "layout=\(String(reflecting: value.layout))",
                ].joined(separator: ", ")
            }
            var previousSample: ObservationSample?
            var previousAccepted = false
            func wrapPrecondition(_ targetIndex: Int, _ step: String) {
                let key = "\(name)/\(step)"
                wrapChecks[key, default: 0] += 1
                let current = capture(began: ProcessInfo.processInfo.systemUptime,
                                      expected: inputs(), drain: previousSample?.drainGeneration ?? 0)
                guard let g = current.geometry, model.windows.indices.contains(targetIndex) else {
                    suite.expect(false, "\(key): wrap precondition needs the current scroll and target")
                    return
                }
                let target = model.windows[targetIndex]
                let appWindows = model.windows.filter { $0.pid == target.pid }
                let localIndex = appWindows.firstIndex { $0.id == target.id }
                let start = localIndex.map { g.padding + CGFloat($0) * (g.width + g.spacing) }
                let targetVisible = start.map { $0 >= g.clip.minX - 0.5 && $0 + g.width <= g.clip.maxX + 0.5 } ?? true
                let targetOffscreen = start.map { $0 + g.width < g.clip.minX - 0.5 || $0 > g.clip.maxX + 0.5 } ?? false
                let valid = previousAccepted && previousSample?.selectedID == current.selectedID
                    && current.valid && localIndex != nil && !targetVisible && targetOffscreen
                    && g.documentFrame.map({ $0.width > g.clip.width }) == true
                    && model.screenWidth == 640 && !instantSelection && appWindows.count == 8
                    && model.windows.count == 15 && (targetIndex == 0 || targetIndex == 7)
                    && target.pid == model.windows[model.selectedIndex].pid
                    && model.selectedIndex == (targetIndex == 0 ? 7 : 0)
                print("SWITCHER SCROLL WRAP PRECONDITION scenario=\(name), step=\(step), prior-accepted=\(previousAccepted), prior-id=\(current.selectedID ?? "none"), prior-visible=\(current.selectedVisible), target-index=\(targetIndex), target-id=\(target.id), target-start=\(start.map { decimal(Double($0)) } ?? "none"), target-visible=\(targetVisible), target-offscreen=\(targetOffscreen), clip=\(rect(g.clip)), valid=\(valid)")
                suite.expect(valid, "\(key): the prior card is visible and the wrap target is offscreen before selecting it")
            }
            func check(_ step: String) {
                let key = "\(name)/\(step)"
                visibilityChecks[key, default: 0] += 1
                let expected = inputs()
                let expectedAppCount = model.windows.indices.contains(expected.selectedIndex)
                    ? model.windows.filter { $0.pid == model.windows[expected.selectedIndex].pid }.count : 0
                let requiresPair = !expected.simple && expectedAppCount == 2 && expected.screenWidth >= 800
                let requiresAllPreviews = !expected.simple && expected.scope == .frontmostApp && expected.screenWidth >= 1440
                let began = ProcessInfo.processInfo.systemUptime
                var drainGeneration = 0
                DispatchQueue.main.async {
                    drainGeneration = 1
                    DispatchQueue.main.async { drainGeneration = 2 }
                }
                var state = ObservationState()
                let initial = capture(began: began, expected: expected, drain: drainGeneration)
                state.consume(initial)
                var observedSuccess = false
                repeat {
                    if state.canFinish {
                        // The fresh read may invalidate an earlier successful sample.
                        state.consumeFinal(capture(began: began, expected: expected, drain: drainGeneration))
                        if state.canFinish { observedSuccess = true; break }
                    }
                    let elapsed = ProcessInfo.processInfo.systemUptime - began
                    if elapsed >= ObservationPolicy.deadline { break }
                    var slice = min(ObservationPolicy.pumpSlice, ObservationPolicy.deadline - elapsed)
                    if elapsed < ObservationPolicy.floor { slice = min(slice, ObservationPolicy.floor - elapsed) }
                    RunLoop.current.run(until: Date().addingTimeInterval(slice))
                    hosting.layoutSubtreeIfNeeded()
                    state.consume(capture(began: began, expected: expected, drain: drainGeneration))
                } while true
                let final = capture(began: began, expected: expected, drain: drainGeneration)
                if observedSuccess { state.consumeFinal(final) } else { state.consume(final) }
                let terminalInputs = inputs()
                let accepted = observedSuccess && state.canFinish && terminalInputs == expected
                    && ProcessInfo.processInfo.systemUptime - began < ObservationPolicy.deadline
                let reason = state.clockInvalid ? "clock-invalid" : state.identityChanged ? "identity-changed"
                    : state.regressionLatched ? "regression-latched" : state.terminalInvalid ? "final-fresh-invalid" : accepted
                        ? (state.lateAssessmentRequired ? "stable-late-assessment" : "stable")
                        : final.elapsed >= ObservationPolicy.deadline ? "deadline" : "final-fresh-invalid"
                let changes = state.transitions.map {
                    "\(decimal($0.0)):{output-window-frame=\(rect($0.1.windowFrame)), clip=\(rect($0.1.geometry?.clip))}"
                }.joined(separator: "|")
                let diagnostics = [
                    "scenario=\(name)", "step=\(step)", "simple=\(expected.simple)", "instant=\(instantSelection)",
                    "os=\(ProcessInfo.processInfo.operatingSystemVersionString)",
                    "screen=\(decimal(Double(expected.screenWidth)))", "scope=\(String(describing: expected.scope))",
                    "preview-size-lookup=\(expected.previewSizeLookup)", "items=\(expected.items.joined(separator: "|"))",
                    "item-count=\(expected.items.count)", "intended-index=\(expected.selectedIndex)",
                    "intended-id=\(expected.selectedID ?? "none")", "elapsed=\(decimal(final.elapsed))",
                    "floor=0.500", "deadline=2.000", "stable-required=0.150", "samples-required=3",
                    "samples=\(state.samples)", "fixture-drain=\(drainGeneration)",
                    "first-visible=\(time(state.firstVisible))", "first-valid=\(time(state.firstValid))",
                    "first-stable=\(time(state.firstStable))", "stable-for=\(decimal(state.stableFor))",
                    "stable-samples=\(state.stableSamples)", "largest-gap=\(decimal(state.largestGap))",
                    "old-boundary-before=\(time(state.beforeBoundaryElapsed))", "old-boundary-gap=\(time(state.boundaryGap))",
                    "boundary-uncertain=\(state.boundaryUncertain)", "late-assessment=\(state.lateAssessmentRequired)",
                    "regression=\(state.regressionLatched)", "identity-changed=\(state.identityChanged)",
                    "terminal-invalid=\(state.terminalInvalid)", "geometry-changes=\(state.geometryChanges)", "transitions=\(changes)",
                    "reason=\(reason)", "accepted=\(accepted)",
                    "expected-inputs={\(inputDescription(expected))}", "terminal-inputs={\(inputDescription(terminalInputs))}",
                    "initial={\(describe(initial))}",
                    "old-boundary-predecessor={\(describe(state.beforeBoundary))}", "old-boundary={\(describe(state.oldBoundary))}",
                    "final={\(describe(final))}",
                ].joined(separator: ", ")
                print("SWITCHER SCROLL OBSERVATION \(diagnostics)")
                suite.expect(accepted, "\(key): bounded stable native observation: \(diagnostics)")
                suite.expect(final.inputsUnchanged && final.selectionMatches && !state.identityChanged && terminalInputs == expected,
                             "\(key): intended selection and geometry inputs stay unchanged")
                suite.expect(final.viewportMatches, "\(key): the viewport keeps its original expected-width tolerance")
                if requiresPair {
                    suite.expect(final.pairVisible, "\(key): both windows must be visible together")
                }
                if requiresAllPreviews {
                    suite.expect(final.allPreviewsVisible, "\(key): all focused-app previews fit together")
                }
                suite.expect(!window.isVisible, "scroll tests never show a window")
                if let g = final.geometry {
                    suite.expect(g.start >= g.clip.minX - 0.5 && g.start + g.width <= g.clip.maxX + 0.5,
                                 "\(key): selected \(final.selectedID ?? "none") at \(g.start)...\(g.start + g.width) must fit \(g.clip.minX)...\(g.clip.maxX)")
                } else {
                    suite.expect(false, "\(key): missing scroll content in the final fresh sample")
                }
                previousSample = final
                previousAccepted = accepted
            }
            body(model, check, drainOnly, wrapPrecondition)
        }
        for simple in [false, true] {
            let mode = simple ? "titles" : "previews"
            run("\(mode) instant navigation", instantSelection: true) { model, check, _, _ in
                model.screenWidth = 640
                model.seed([8, 7], selected: 7, simple: simple); check("initial overflow")
                model.select(index: 0); check("first")
                model.select(index: 7); check("last")
                model.select(index: 8); check("next app")
                model.select(index: 14); check("next app last")
            }
            run("\(mode) search") { model, check, _, _ in
                model.seed([3,1,1,1,1,1,1], selected: 2, simple: simple); check("initial")
                model.search("a"); check("narrowed without changing selection")
                model.search(""); check("cleared search")
                model.select(index: 0); check("first")
                model.select(index: 2); check("last")
            }
            run("\(mode) boundary close") { model, check, _, _ in
                model.screenWidth = 640
                model.seed([8,8], selected: 7, simple: simple); check("initial")
                model.closeWindow(model.windows[7]); check("next app at unchanged index")
            }
            run("\(mode) replacing search result") { model, check, _, _ in
                model.screenWidth = 640
                model.seed([8,8], selected: 7, simple: simple); check("initial")
                model.search("keep"); check("new selection at unchanged index")
            }
            run("\(mode) navigation") { model, check, _, beforeWrap in
                model.screenWidth = 640
                model.seed([8,7], selected: 7, simple: simple); check("initial overflow")
                beforeWrap(0, "wrap first")
                model.select(index: 0); check("wrap first")
                beforeWrap(7, "wrap last")
                model.select(index: 7); check("wrap last")
                model.select(index: 8); check("second app first")
                model.select(index: 14); check("second app last")
                model.closeWindow(model.windows[10]); check("remove earlier card")
            }
            run("\(mode) pending reveal") { model, check, settle, _ in
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
                    run("focused app \(size)") { model, check, _, _ in
                        model.sessionScope = .frontmostApp
                        model.seed([4], selected: 1); check("four previews")
                        model.select(index: 3); check("last window")
                        model.screenWidth = 640
                        model.recompute(); check("narrow display overflow")
                        model.select(index: 0); check("overflow wraps to first")
                    }
                }
                run("\(mode) \(size)") { model, check, _, _ in
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
        let expectedVisibilityChecks = 46 + 14 * Defaults.allowedPreviewSizes.count
        let expectedWraps: Set<String> = ["previews navigation/wrap first", "previews navigation/wrap last",
                                          "titles navigation/wrap first", "titles navigation/wrap last"]
        suite.expect(visibilityChecks.count == expectedVisibilityChecks && visibilityChecks.values.allSatisfy { $0 == 1 }
               && drainOnlyChecks == 2 && Set(wrapChecks.keys) == expectedWraps && wrapChecks.values.allSatisfy { $0 == 1 },
               "scroll observation coverage keeps every native case and both noninstant wrap directions")
        print("SWITCHER SCROLL COVERAGE visibility=\(visibilityChecks.count), expected=\(expectedVisibilityChecks), drain-only=\(drainOnlyChecks), wrap=\(wrapChecks.count), sizes=\(Defaults.allowedPreviewSizes.joined(separator: "|")), all-once=\(visibilityChecks.values.allSatisfy { $0 == 1 } && wrapChecks.values.allSatisfy { $0 == 1 })")
    }
}
