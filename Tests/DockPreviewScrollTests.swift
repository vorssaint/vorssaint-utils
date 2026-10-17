// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import CoreFoundation
import SwiftUI

/// The production panel is hosted offscreen with empty, same-sized cards.
/// Button doubles expose its real actions without sending input to the desktop.
enum DockPreviewScrollTests {
    struct SwitcherItem: Identifiable {
        let id: CGWindowID
        var windowID: CGWindowID? { id }
        var previewWindowID: CGWindowID? { nil }
        var appIcon: NSImage? { nil }
    }

    final class Model: ObservableObject {
        let windows = (1...12).map { SwitcherItem(id: CGWindowID($0)) }
        @Published var selectedWindowID: CGWindowID?
        func preview(_ item: SwitcherItem) { selectedWindowID = item.windowID }
        func select(_ offset: Int) -> CGWindowID? {
            selectedWindowID = DockPreviewSupport.adjacentWindowID(
                selectedWindowID: selectedWindowID, windowIDs: windows.map(\.id), offset: offset)
            return selectedWindowID
        }
    }

    struct Host: View {
        @ObservedObject var model: Model
        let orientation: DockPreviewOrientation
        let isPinned: Bool
        var body: some View {
            DockPreviewPanelContent(
                windows: model.windows, previews: [:], selectedWindowID: model.selectedWindowID,
                currentAppName: "Test", isPinned: isPinned, orientation: orientation,
                onPreview: model.preview,
                onEndPreview: { _ in if !isPinned { model.selectedWindowID = nil } },
                onCommit: { _ in }, onCloseWindow: { _ in }, onMiddleClick: { _ in },
                onToggleMinimized: { _ in }, onTogglePinned: {}, onClosePanel: {},
                onSelectPrevious: { model.select(-1) }, onSelectNext: { model.select(1) },
                onBeginDrag: { _ in }, onUpdateDrag: {}, onEndDrag: { _ in })
        }
    }

    struct DockPreviewCard: View {
        let window: SwitcherItem
        let preview: CGImage?
        let isSelected: Bool
        let isPanelPinned: Bool
        let onTogglePinned: () -> Void
        let closeActionTitle: String
        let onCommit: () -> Void
        let onClose: () -> Void
        let onMiddleClick: () -> Void
        let onToggleMinimized: () -> Void
        var body: some View {
            Color.clear.frame(width: DockPreviewSupport.cardWidth, height: DockPreviewSupport.cardHeight)
        }
    }

    struct HUDBackdrop: View {
        let cornerRadius: CGFloat
        let opacity: Double
        var body: some View { Color.clear }
    }
    struct NativeWindowDragHandle: View {
        var body: some View { Color.clear }
    }
    final class L10n: ObservableObject {
        static let shared = L10n()
        var s: L10n { self }
        let panelQuit = "Quit"
        let dockPreviewCloseWindow = "Close window"
        let dockPreviewUnpinPanel = "Unpin"
        let dockPreviewClosePanel = "Close panel"
        let dockPreviewPinned = "Pinned"
        let dockPreviewPreviousWindow = "Previous window"
        let dockPreviewNextWindow = "Next window"
    }
    static var buttonActions: [String: () -> Void] = [:]
    struct Button<Label: View>: View {
        let action: () -> Void
        let label: Label
        init(action: @escaping () -> Void, @ViewBuilder label: () -> Label) {
            self.action = action
            self.label = label()
        }
        var body: some View { label }
        func help(_ title: String) -> Self {
            buttonActions[title] = action
            return self
        }
    }

    static func run(_ suite: TestSuite) {
        MainActor.assumeIsolated {
            _ = NSApplication.shared
            let previousPolicy = NSApp.activationPolicy()
            NSApp.setActivationPolicy(.prohibited)
            defer { NSApp.setActivationPolicy(previousPolicy) }
            for (orientation, pinned): (DockPreviewOrientation, Bool) in [
                (.bottom, false), (.left, false), (.right, false), (.bottom, true)
            ] {
                check(suite, orientation: orientation, pinned: pinned)
            }
        }
    }

    @MainActor private static func check(_ suite: TestSuite, orientation: DockPreviewOrientation, pinned: Bool) {
        struct GeometryInputs: Equatable {
            let previewSizeLookup: String
            let minimalPreviewsLookup: String
            let scale: CGFloat
            let minimalPreviews: Bool
        }
        func primitiveLookup(_ key: String) -> String {
            // This lookup includes registration fallbacks, not just persisted values.
            guard let value = UserDefaults.standard.object(forKey: key) else { return "absent effective lookup" }
            if let string = value as? String { return "String:\(String(reflecting: string))" }
            if let number = value as? NSNumber {
                let kind = CFGetTypeID(number) == CFBooleanGetTypeID()
                    ? "Bool" : "Number(\(String(cString: number.objCType)))"
                return "\(kind):\(number.stringValue)"
            }
            return "\(String(reflecting: type(of: value))):\(String(reflecting: value))"
        }
        func geometryInputs() -> GeometryInputs {
            GeometryInputs(previewSizeLookup: primitiveLookup(DefaultsKey.previewSize),
                           minimalPreviewsLookup: primitiveLookup(DefaultsKey.minimalWindowPreviews),
                           scale: PreviewSizing.scale,
                           minimalPreviews: UserDefaults.standard.bool(forKey: DefaultsKey.minimalWindowPreviews))
        }
        func decimal(_ value: Double) -> String { String(format: "%.3f", value) }
        func inputText(_ inputs: GeometryInputs) -> String {
            "effectivePreviewSizeLookup=\(inputs.previewSizeLookup), "
                + "effectiveMinimalPreviewsLookup=\(inputs.minimalPreviewsLookup), "
                + "scale=\(decimal(Double(inputs.scale))), minimalPreviews=\(inputs.minimalPreviews)"
        }
        func rectText(_ rect: NSRect?) -> String {
            guard let rect else { return "none" }
            return "(\(decimal(Double(rect.origin.x))),\(decimal(Double(rect.origin.y))),"
                + "\(decimal(Double(rect.size.width))),\(decimal(Double(rect.size.height))))"
        }
        let fixtureInputs = geometryInputs()
        let model = Model()
        let vertical = DockPreviewSupport.stacksVertically(orientation: orientation, isPinned: pinned)
        let size = CGSize(width: vertical ? DockPreviewSupport.cardWidth + 2 * DockPreviewSupport.panelPadding : 760,
                          height: vertical ? 560 : DockPreviewSupport.cardHeight + 2 * DockPreviewSupport.panelPadding
                            + (pinned ? DockPreviewSupport.panelHeaderHeight : 0))
        let hosting = NSHostingView(rootView: Host(model: model, orientation: orientation, isPinned: pinned))
        let window = NSWindow(contentRect: CGRect(origin: .zero, size: size),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = hosting
        defer {
            buttonActions.removeAll()
            window.close()
        }
        func settle() {
            let deadline = Date().addingTimeInterval(0.25)
            repeat {
                hosting.layoutSubtreeIfNeeded()
                RunLoop.current.run(until: min(deadline, Date().addingTimeInterval(0.01)))
            } while Date() < deadline
        }
        func findScroll(_ view: NSView) -> NSScrollView? {
            if let scroll = view as? NSScrollView { return scroll }
            return view.subviews.compactMap { findScroll($0) }.first
        }
        settle()
        guard let scroll = findScroll(hosting) else {
            suite.expect(false, "Dock preview must contain a native scroll view")
            return
        }
        let name = "Dock preview \(orientation), pinned=\(pinned)"
        let extent = vertical ? DockPreviewSupport.cardHeight : DockPreviewSupport.cardWidth
        let navigationPadding = DockPreviewSupport.panelPadding
        let navigationSpacing = DockPreviewSupport.cardSpacing
        for index in [2, 3, 4, 3, 2] {
            let offset = CGFloat(index - 1) * (extent + DockPreviewSupport.cardSpacing) + 35
            scroll.contentView.scroll(to: vertical ? NSPoint(x: 0, y: offset) : NSPoint(x: offset, y: 0))
            scroll.reflectScrolledClipView(scroll.contentView)
            settle()
            let before = scroll.contentView.bounds.origin
            model.preview(model.windows[index])
            settle()
            let after = scroll.contentView.bounds.origin
            suite.expect(model.selectedWindowID == model.windows[index].windowID,
                         "\(name): hover still highlights the window")
            suite.expect(abs(before.x - after.x) < 0.5 && abs(before.y - after.y) < 0.5,
                         "\(name): hover during scrolling must not move content from \(before) to \(after)")
        }
        if pinned {
            func scrollSnapshot() -> String {
                let insets = scroll.contentInsets
                return "clipBounds=\(rectText(scroll.contentView.bounds)), "
                    + "clipFrame=\(rectText(scroll.contentView.frame)), "
                    + "documentBounds=\(rectText(scroll.documentView?.bounds)), "
                    + "documentFrame=\(rectText(scroll.documentView?.frame)), "
                    + "viewport=(\(decimal(Double(scroll.contentSize.width))),"
                    + "\(decimal(Double(scroll.contentSize.height)))), "
                    + "contentInsets=(\(decimal(Double(insets.top))),\(decimal(Double(insets.left))),"
                    + "\(decimal(Double(insets.bottom))),\(decimal(Double(insets.right))))"
            }
            func navigate(_ title: String, expectedIndex: Int) -> Bool {
                let expectedID = model.windows[expectedIndex].windowID
                let start = navigationPadding + CGFloat(expectedIndex) * (extent + navigationSpacing)
                func visible(in clip: NSRect) -> Bool {
                    start >= clip.minX - 0.5 && start + extent <= clip.maxX + 0.5
                }
                let navigationInputs = geometryInputs()
                let initialClip = scroll.contentView.bounds
                let initialSnapshot = scrollSnapshot()
                guard let action = buttonActions[title] else {
                    let snapshot = scrollSnapshot()
                    let inputs = geometryInputs()
                    let missingAction = [
                        "orientation=\(orientation), pinned=\(pinned), action=\(String(reflecting: title)), missingAction=true",
                        "expectedIndex=\(expectedIndex), expectedID=\(String(describing: expectedID)), selectedID=\(String(describing: model.selectedWindowID))",
                        "arithmeticTargetStart=\(decimal(Double(start))), arithmeticTargetExtent=\(decimal(Double(extent)))",
                        "panelPadding=\(decimal(Double(navigationPadding))), cardSpacing=\(decimal(Double(navigationSpacing)))",
                        "elapsed=0.000, firstVisible=none, lastBoundsChange=0.000, stableFor=0.000, samples=0, stableSamples=0",
                        "deadline=2.000, deadlineReached=false, observationStarted=false, stableObservation=false",
                        "selection=\(model.selectedWindowID == expectedID), visible=\(visible(in: scroll.contentView.bounds)), inputsUnchanged=\(inputs == navigationInputs && inputs == fixtureInputs)",
                        "fixtureInputs={\(inputText(fixtureInputs))}, navigationInputs={\(inputText(navigationInputs))}, terminalInputs={\(inputText(inputs))}",
                        "initial={\(initialSnapshot)}, currentAtOrAfter025=none, final={\(snapshot)}",
                    ].joined(separator: ", ")
                    print("DOCK NAV OBS \(missingAction)")
                    suite.expect(false, "\(name): missing navigation action \(title)")
                    return false
                }
                let began = ProcessInfo.processInfo.systemUptime
                let observationLimit = 2.0
                let deadline = began + observationLimit
                let observationFloor = 0.25
                let requiredStableDuration = 0.10
                var lastClip = initialClip
                var lastBoundsChange = began
                var unchangedClipSamples = 0
                var samples = 0
                var firstVisible: Double?
                var firstFloorSample: String?
                var inputsUnchanged = navigationInputs == fixtureInputs
                var firstInputChange: Double? = inputsUnchanged ? nil : 0
                var terminalInputs = navigationInputs
                var clip = initialClip
                var selectedID = model.selectedWindowID
                var selectionMatches = selectedID == expectedID
                var isVisible = visible(in: clip)
                var terminalSnapshot = initialSnapshot
                var elapsed = 0.0
                var stableDuration = 0.0
                var deadlineReached = false
                var observedStable = false

                // The actual captured production action runs once. Observation
                // below never scrolls, selects, or retries that action.
                action()
                repeat {
                    if ProcessInfo.processInfo.systemUptime < deadline {
                        hosting.layoutSubtreeIfNeeded()
                        let remaining = deadline - ProcessInfo.processInfo.systemUptime
                        if remaining > 0 {
                            RunLoop.current.run(until: Date().addingTimeInterval(min(0.01, remaining)))
                        }
                    }
                    let sampledAt = ProcessInfo.processInfo.systemUptime
                    elapsed = sampledAt - began
                    samples += 1
                    clip = scroll.contentView.bounds
                    if clip == lastClip {
                        unchangedClipSamples += 1
                    } else {
                        lastClip = clip
                        lastBoundsChange = sampledAt
                        unchangedClipSamples = 0
                    }
                    stableDuration = sampledAt - lastBoundsChange
                    terminalInputs = geometryInputs()
                    if terminalInputs != navigationInputs || terminalInputs != fixtureInputs {
                        inputsUnchanged = false
                        if firstInputChange == nil { firstInputChange = elapsed }
                    }
                    selectedID = model.selectedWindowID
                    selectionMatches = selectedID == expectedID
                    isVisible = visible(in: clip)
                    terminalSnapshot = scrollSnapshot()
                    if isVisible && firstVisible == nil { firstVisible = elapsed }
                    if elapsed >= observationFloor && firstFloorSample == nil {
                        firstFloorSample = "elapsed=\(decimal(elapsed)), selected=\(String(describing: selectedID)), "
                            + "selection=\(selectionMatches), visible=\(isVisible), "
                            + "stableFor=\(decimal(stableDuration)), stableSamples=\(unchangedClipSamples), "
                            + "inputsUnchanged=\(inputsUnchanged), "
                            + terminalSnapshot
                    }
                    deadlineReached = sampledAt >= deadline
                    observedStable = !deadlineReached && elapsed >= observationFloor
                        && selectionMatches && isVisible && inputsUnchanged
                        && stableDuration >= requiredStableDuration && unchangedClipSamples >= 2
                } while !deadlineReached && !observedStable
                let firstVisibleText = firstVisible.map { decimal($0) } ?? "none"
                let firstInputChangeText = firstInputChange.map { decimal($0) } ?? "none"
                let diagnostics = "orientation=\(orientation), pinned=\(pinned), action=\(String(reflecting: title)), "
                    + "expectedIndex=\(expectedIndex), expectedID=\(String(describing: expectedID)), "
                    + "selectedID=\(String(describing: selectedID)), arithmeticTargetStart=\(decimal(Double(start))), "
                    + "arithmeticTargetExtent=\(decimal(Double(extent))), panelPadding=\(decimal(Double(navigationPadding))), "
                    + "cardSpacing=\(decimal(Double(navigationSpacing))), elapsed=\(decimal(elapsed)), "
                    + "firstVisible=\(firstVisibleText), lastBoundsChange=\(decimal(lastBoundsChange - began)), "
                    + "stableFor=\(decimal(stableDuration)), stableSamples=\(unchangedClipSamples), samples=\(samples), "
                    + "deadline=\(decimal(observationLimit)), deadlineReached=\(deadlineReached), "
                    + "selection=\(selectionMatches), visible=\(isVisible), stableObservation=\(observedStable), "
                    + "inputsUnchanged=\(inputsUnchanged), firstInputChange=\(firstInputChangeText), "
                    + "fixtureInputs={\(inputText(fixtureInputs))}, navigationInputs={\(inputText(navigationInputs))}, "
                    + "terminalInputs={\(inputText(terminalInputs))}, initial={\(initialSnapshot)}, "
                    + "currentAtOrAfter025={\(firstFloorSample ?? "none")}, final={\(terminalSnapshot)}"
                print("DOCK NAV OBS \(diagnostics)")
                suite.expect(selectionMatches,
                             "\(name): navigation selects window \(expectedIndex + 1)")
                suite.expect(start >= clip.minX - 0.5 && start + extent <= clip.maxX + 0.5,
                             "\(name): navigation reveals window \(expectedIndex + 1), including wraparound")
                suite.expect(observedStable,
                             "\(name): navigation reaches a bounded stable observation: \(diagnostics)")
                suite.expect(inputsUnchanged,
                             "\(name): geometry input lookups stay unchanged during navigation: \(diagnostics)")
                return observedStable && inputsUnchanged
            }
            model.preview(model.windows[0])
            settle()
            let previousRevealed = navigate(L10n.shared.dockPreviewPreviousWindow, expectedIndex: 11)
            let wrapClip = scroll.contentView.bounds
            let firstStart = navigationPadding
            let firstVisible = firstStart >= wrapClip.minX - 0.5 && firstStart + extent <= wrapClip.maxX + 0.5
            let wrapPrecondition = previousRevealed && model.selectedWindowID == model.windows[11].windowID
                && !firstVisible
            print("DOCK WRAP PRECONDITION \(name), previousStable=\(previousRevealed), "
                + "firstArithmeticStart=\(decimal(Double(firstStart))), arithmeticExtent=\(decimal(Double(extent))), "
                + "clip=\(rectText(wrapClip)), firstVisible=\(firstVisible), valid=\(wrapPrecondition)")
            suite.expect(wrapPrecondition,
                         "\(name): wrapping Next starts with the first card outside the stably revealed last card's clip")
            _ = navigate(L10n.shared.dockPreviewNextWindow, expectedIndex: 0)
            _ = navigate(L10n.shared.dockPreviewNextWindow, expectedIndex: 1)
            model.preview(model.windows[10])
            settle()
            _ = navigate(L10n.shared.dockPreviewNextWindow, expectedIndex: 11)
        }
        let terminalFixtureInputs = geometryInputs()
        print("DOCK FIXTURE INPUTS \(name), before={\(inputText(fixtureInputs))}, "
            + "terminal={\(inputText(terminalFixtureInputs))}, "
            + "lookupsIncludeRegistrationFallbacks=true, persistedPresenceClaimed=false")
        suite.expect(terminalFixtureInputs == fixtureInputs,
                     "\(name): geometry input lookups stay unchanged across the fixture")
        suite.expect(!window.isVisible, "\(name): tests never show a window")
    }
}
