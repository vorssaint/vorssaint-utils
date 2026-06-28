// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import ApplicationServices
import Combine
import CoreGraphics
import SwiftUI

private struct SwitcherSourceContext {
    let itemID: String?
    let pid: pid_t
    let windowID: CGWindowID?
    let isFullscreen: Bool
}

/// The window switcher: a global event tap takes over the configured shortcut,
/// and while its modifiers are held a non-activating panel cycles through real
/// windows. Releasing commits, Q quits the highlighted app, Esc cancels. The
/// panel joins every Space and fullscreen app, so the switcher is available
/// wherever the user is.
final class AppSwitcher: ObservableObject {
    static let shared = AppSwitcher()

    @Published private(set) var windows: [SwitcherItem] = []
    @Published private(set) var previews: [CGWindowID: CGImage] = [:]
    @Published private(set) var selectedIndex = 0 {
        didSet {
            guard oldValue != selectedIndex else { return }
            updateIconRowLayoutForCurrentSelection()
            if sessionActive, iconRowModeEnabled {
                resizePanel()
            }
        }
    }
    @Published private(set) var grid = SwitcherGrid.empty
    @Published private(set) var iconRowLayout = SwitcherIconRowLayout.empty
    @Published private(set) var searchQuery = ""
    @Published private(set) var totalWindowCount = 0

    private var sessionActive = false
    private var tap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var panel: NSPanel?
    private var sessionItems: [SwitcherItem] = []

    /// The panel appears only after this delay, like the system switcher: a
    /// quick ⌘Tab flick switches with no UI at all, which is what makes rapid
    /// toggling feel instant instead of flashing a window.
    private static let appearanceDelay: TimeInterval = 0.1
    private var pendingShow: DispatchWorkItem?
    /// True once the user moved the selection themselves.
    private var userNavigated = false
    /// Mouse position when the panel appeared; hover is inert until it moves.
    private var hoverAnchor: NSPoint?

    /// Most-recently-used order of windows, most recent first. This is what lets
    /// ⌘Tab toggle to the last window used, even another window of the same app.
    /// Driven by the switcher's own commits (see `recordUse`).
    private var itemMRU: [String] = []
    /// The on-screen window when the current session opened — becomes the
    /// second-most-recent window on commit, so a flick toggles straight back.
    private var sessionStartItemID: String?
    private var sessionSourceContext: SwitcherSourceContext?
    private var sessionShortcut: GlobalShortcut?

    // Virtual key codes handled during a session.
    private enum KeyCode {
        static let tab: Int64 = 48
        static let delete: Int64 = 51
        static let escape: Int64 = 53
        static let enter: Int64 = 36
        static let q: Int64 = 12
        static let grave: Int64 = 50
        static let leftArrow: Int64 = 123
        static let rightArrow: Int64 = 124
        static let downArrow: Int64 = 125
        static let upArrow: Int64 = 126
    }

    private init() {}

    /// True while the event tap is installed.
    var isRunning: Bool { tap != nil }

    /// Applies the persisted preference; safe to call repeatedly.
    func syncWithPreferences() {
        let enabled = UserDefaults.standard.bool(forKey: DefaultsKey.switcherEnabled)
        if enabled, Permissions.shared.accessibility {
            installTap()
            // Build the panel and its SwiftUI tree now: the first hosting-view
            // render costs hundreds of milliseconds, far too slow to pay on
            // the first ⌘Tab.
            let panel = ensurePanel()
            panel.contentViewController?.view.layoutSubtreeIfNeeded()
        } else {
            removeTap()
        }
    }

    /// Force-stops the tap regardless of the preference. Used before the app
    /// resets its own permissions, so a revoked Accessibility grant can never
    /// leave a live tap behind.
    func suspend() { removeTap() }

    // MARK: - Event tap

    private func installTap() {
        guard tap == nil else { return }
        let mask = CGEventMask(1 << CGEventType.keyDown.rawValue) | CGEventMask(1 << CGEventType.flagsChanged.rawValue)
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: { _, type, event, userInfo in
                guard let userInfo else { return Unmanaged.passUnretained(event) }
                let switcher = Unmanaged<AppSwitcher>.fromOpaque(userInfo).takeUnretainedValue()
                return switcher.handle(type: type, event: event)
            },
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else { return }

        self.tap = tap
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        runLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
    }

    private func removeTap() {
        if sessionActive { cancelSession() }
        if let tap {
            CGEvent.tapEnable(tap: tap, enable: false)
        }
        if let runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        }
        tap = nil
        runLoopSource = nil
    }

    private func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return Unmanaged.passUnretained(event)
        }

        // With Accessibility revoked the AX lookups behind a session would hang
        // inside the tap and freeze input; pass events through and drop any
        // session that was open.
        guard AXIsProcessTrusted() else {
            if sessionActive { cancelSession() }
            return Unmanaged.passUnretained(event)
        }

        switch type {
        case .keyDown:
            return handleKeyDown(event)
        case .flagsChanged:
            if sessionActive,
               let shortcut = sessionShortcut,
               !shortcut.requiredModifiersHeld(in: event.flags) {
                commitSession()
            }
            return Unmanaged.passUnretained(event)
        default:
            return Unmanaged.passUnretained(event)
        }
    }

    private func handleKeyDown(_ event: CGEvent) -> Unmanaged<CGEvent>? {
        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
        let flags = event.flags

        guard sessionActive else {
            let shortcut = GlobalShortcut.saved(for: DefaultsKey.switcherShortcut,
                                                fallback: .switcherDefault)
            guard shortcut.matches(event: event, allowingExtraShift: true)
            else { return Unmanaged.passUnretained(event) }

            let reversed = shortcut.shiftIsNavigationModifier && flags.contains(.maskShift)
            return beginSession(reversed: reversed, shortcut: shortcut)
                ? nil
                : Unmanaged.passUnretained(event)
        }

        let shortcut = sessionShortcut ?? GlobalShortcut.saved(for: DefaultsKey.switcherShortcut,
                                                               fallback: .switcherDefault)
        switch keyCode {
        case _ where keyCode == shortcut.keyCode && shortcut.matches(event: event, allowingExtraShift: true):
            let delta = shortcut.shiftIsNavigationModifier && flags.contains(.maskShift) ? -1 : 1
            advanceSelection(by: delta)
        case KeyCode.rightArrow:
            advanceSelection(by: 1)
        case KeyCode.leftArrow:
            advanceSelection(by: -1)
        case KeyCode.downArrow:
            moveSelection(by: grid.columns)
        case KeyCode.upArrow:
            moveSelection(by: -grid.columns)
        case KeyCode.q where searchQuery.isEmpty:
            quitSelectedApp()
        case KeyCode.grave where iconRowModeEnabled && searchQuery.isEmpty:
            let delta = flags.contains(.maskShift) ? -1 : 1
            advanceWindowInSelectedApp(by: delta)
        case KeyCode.delete:
            removeLastSearchCharacter()
        case KeyCode.escape:
            cancelSession()
        case KeyCode.enter:
            commitSession()
        default:
            if let text = printableSearchText(from: event) {
                appendSearchText(text)
            }
            // Swallow stray keys so they never leak into the focused app.
        }
        return nil
    }

    // MARK: - Session lifecycle

    private func beginSession(reversed: Bool, shortcut: GlobalShortcut) -> Bool {
        let windows = WindowEnumerator.listWindows()
        guard !windows.isEmpty else { return false }

        let list = orderedForSession(windows)
        sessionItems = list
        totalWindowCount = list.count
        searchQuery = ""
        self.windows = list
        sessionSourceContext = sourceContext(in: list)
        sessionStartItemID = sessionSourceContext?.itemID ?? currentItemID(in: list)
        recomputeLayouts(for: list)
        previews = Dictionary(uniqueKeysWithValues: list.compactMap { item in
            item.previewWindowID.flatMap { id in
                WindowPreviewProvider.shared.cachedPreview(for: id).map { (id, $0) }
            }
        })
        userNavigated = false
        // Index 0 is the on-screen window; index 1 is the most-recently-used
        // other window — the toggle target, which may be another window of the
        // same app. Shift starts from the far end.
        selectedIndex = initialSelectionIndex(in: list, reversed: reversed)
        sessionActive = true
        sessionShortcut = shortcut

        WindowPreviewProvider.shared.refreshPreviews(for: list, maxPixelSize: 640 * PreviewSizing.scale) { [weak self] windowID, image in
            guard let self,
                  self.sessionActive,
                  self.sessionItems.contains(where: { $0.previewWindowID == windowID }) else { return }
            self.previews[windowID] = image
        }
        scheduleShowPanel()
        return true
    }

    /// Orders a session's windows so the on-screen window is first and the rest
    /// follow most-recently-used order, falling back to the app-activation
    /// order the enumerator already applied. This is what lets ⌘Tab toggle
    /// between two windows of the same app, not just two apps.
    private func orderedForSession(_ items: [SwitcherItem]) -> [SwitcherItem] {
        let currentID = currentItemID(in: items)
        return items.enumerated()
            .sorted { lhs, rhs in
                sortKey(lhs.element, currentID: currentID, original: lhs.offset)
                    < sortKey(rhs.element, currentID: currentID, original: rhs.offset)
            }
            .map(\.element)
    }

    /// Sort key: on-screen item first (0), then items seen in the MRU by
    /// recency (1, rank), then everything else in its incoming order (2).
    private func sortKey(_ item: SwitcherItem, currentID: String?, original: Int) -> (Int, Int, Int) {
        if item.id == currentID { return (0, 0, 0) }
        if let rank = itemMRU.firstIndex(of: item.id) { return (1, rank, 0) }
        return (2, 0, original)
    }

    private func initialSelectionIndex(in items: [SwitcherItem], reversed: Bool) -> Int {
        guard !items.isEmpty else { return 0 }
        guard iconRowModeEnabled else {
            return reversed ? max(0, items.count - 1) : (items.count > 1 ? 1 : 0)
        }

        let groups = SwitcherSupport.appGroups(items: items)
        guard !groups.isEmpty else { return 0 }
        let groupIndex = reversed ? max(0, groups.count - 1) : (groups.count > 1 ? 1 : 0)
        return groups[groupIndex].representativeIndex
    }

    /// The id of the window on screen right now. Prefer the Accessibility
    /// focused window so the first ⌘Tab never targets the window the user is
    /// already in when the frontmost app has more than one window.
    private func currentItemID(in items: [SwitcherItem]) -> String? {
        let frontPid = NSWorkspace.shared.frontmostApplication?.processIdentifier
            ?? AppActivationTracker.shared.frontmostPid
        if let frontPid,
           let focusedID = focusedWindowID(for: frontPid),
           items.contains(where: { $0.windowID == focusedID }) {
            return "w:\(focusedID)"
        }
        let current = items.first { frontPid == nil || $0.pid == frontPid }
        return current?.id ?? items.first?.id
    }

    private func sourceContext(in items: [SwitcherItem]) -> SwitcherSourceContext? {
        guard let frontPid = NSWorkspace.shared.frontmostApplication?.processIdentifier
                ?? AppActivationTracker.shared.frontmostPid else { return nil }

        let focusedID = focusedWindowID(for: frontPid)
        let source = items.first { item in
            guard item.pid == frontPid else { return false }
            if let focusedID {
                return item.windowID == focusedID
            }
            return true
        } ?? items.first { $0.pid == frontPid }

        return SwitcherSourceContext(itemID: source?.id,
                                     pid: frontPid,
                                     windowID: focusedID ?? source?.windowID,
                                     isFullscreen: source?.isFullscreen ?? false)
    }

    private func focusedWindowID(for pid: pid_t) -> CGWindowID? {
        guard Permissions.shared.accessibility else { return nil }
        let app = AXUIElementCreateApplication(pid)
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(app, kAXFocusedWindowAttribute as CFString, &value) == .success,
              let value,
              CFGetTypeID(value) == AXUIElementGetTypeID()
        else { return nil }
        let window = value as! AXUIElement
        return AXWindowResolver.windowID(for: window)
    }

    /// Records a switch into the window MRU: the activated window moves to the
    /// front and the window the user came from becomes second, so the very next
    /// ⌘Tab toggles straight back — the standard most-recently-used behavior,
    /// at window granularity (including two windows of the same app).
    private func recordUse(_ activatedID: String) {
        itemMRU.removeAll { $0 == activatedID }
        itemMRU.insert(activatedID, at: 0)
        if let previous = sessionStartItemID, previous != activatedID {
            itemMRU.removeAll { $0 == previous }
            itemMRU.insert(previous, at: 1)
        }
        // Bound the history so closed windows don't accumulate forever.
        if itemMRU.count > 64 { itemMRU.removeLast(itemMRU.count - 64) }
    }

    func select(index: Int) {
        guard sessionActive, windows.indices.contains(index) else { return }
        userNavigated = true
        selectedIndex = index
    }

    /// Hover-selection from the panel. Ignored until the mouse really moves:
    /// the panel opens centered on the cursor's screen, and the card that
    /// happens to sit under a stationary pointer must not steal the selection.
    func hoverSelect(index: Int) {
        guard sessionActive else { return }
        let mouse = NSEvent.mouseLocation
        if let anchor = hoverAnchor {
            guard hypot(mouse.x - anchor.x, mouse.y - anchor.y) > 4 else { return }
            hoverAnchor = nil
        }
        select(index: index)
    }

    private var selectedItemID: String? {
        guard windows.indices.contains(selectedIndex) else { return nil }
        return windows[selectedIndex].id
    }

    private func appendSearchText(_ text: String) {
        let clean = sanitizedSearchInput(text)
        guard !clean.isEmpty else { return }
        let preferredID = selectedItemID
        let remaining = max(0, 64 - searchQuery.count)
        guard remaining > 0 else { return }
        searchQuery += String(clean.prefix(remaining))
        applySearchFilter(preferredItemID: preferredID)
    }

    private func removeLastSearchCharacter() {
        guard !searchQuery.isEmpty else { return }
        let preferredID = selectedItemID
        searchQuery.removeLast()
        applySearchFilter(preferredItemID: preferredID)
    }

    private func printableSearchText(from event: CGEvent) -> String? {
        var length = 0
        var chars = [UniChar](repeating: 0, count: 16)
        event.keyboardGetUnicodeString(maxStringLength: chars.count,
                                       actualStringLength: &length,
                                       unicodeString: &chars)
        guard length > 0 else { return nil }
        return sanitizedSearchInput(String(utf16CodeUnits: chars, count: length))
    }

    private func sanitizedSearchInput(_ text: String) -> String {
        String(String.UnicodeScalarView(text.unicodeScalars.filter { scalar in
            !CharacterSet.controlCharacters.contains(scalar)
                && !CharacterSet.newlines.contains(scalar)
        }))
    }

    private func applySearchFilter(preferredItemID: String?) {
        let records = sessionItems.map { item in
            SwitcherSearchRecord(id: item.id, title: item.title, appName: item.appName)
        }
        let visibleIDs = Set(SwitcherSupport.filteredSearchIDs(records: records, query: searchQuery))
        windows = sessionItems.filter { visibleIDs.contains($0.id) }
        selectedIndex = SwitcherSupport.searchSelectionIndex(itemIDs: windows.map(\.id),
                                                             preferredID: preferredItemID,
                                                             previousIndex: selectedIndex)
        recomputeLayouts(for: windows)
        resizePanel()
    }

    func closeWindow(_ item: SwitcherItem) {
        guard sessionActive,
              windows.contains(where: { $0.id == item.id }),
              let windowID = item.windowID,
              WindowActivator.closeWindow(windowID: windowID, pid: item.pid)
        else { return }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) { [weak self] in
            self?.finishClosingWindow(itemID: item.id,
                                      windowID: windowID,
                                      pid: item.pid,
                                      attempt: 0)
        }
    }

    private func advanceSelection(by delta: Int) {
        guard !windows.isEmpty else { return }
        if iconRowModeEnabled {
            advanceAppSelection(by: delta)
            return
        }
        userNavigated = true
        selectedIndex = (selectedIndex + delta + windows.count) % windows.count
    }

    private func advanceAppSelection(by delta: Int) {
        userNavigated = true
        selectedIndex = SwitcherSupport.nextAppSelectionIndex(items: windows,
                                                              selectedIndex: selectedIndex,
                                                              delta: delta)
    }

    private func advanceWindowInSelectedApp(by delta: Int) {
        userNavigated = true
        selectedIndex = SwitcherSupport.nextWindowSelectionIndexWithinApp(items: windows,
                                                                          selectedIndex: selectedIndex,
                                                                          delta: delta)
    }

    /// Quits the app owning the selected window (⌘Tab → Q), removes its windows
    /// from the grid and keeps the session open — mirroring the system switcher.
    private func quitSelectedApp() {
        guard windows.indices.contains(selectedIndex) else { return }
        let pid = windows[selectedIndex].pid
        guard let app = NSRunningApplication(processIdentifier: pid),
              app.bundleIdentifier != Defaults.finderBundleIdentifier else { return }
        app.terminate()

        let removedBeforeSelection = windows[..<selectedIndex].filter { $0.pid == pid }.count
        sessionItems.removeAll { $0.pid == pid }
        totalWindowCount = sessionItems.count
        windows.removeAll { $0.pid == pid }
        let remaining = Set(windows.compactMap(\.previewWindowID))
        previews = previews.filter { remaining.contains($0.key) }

        guard !sessionItems.isEmpty else {
            endSession()
            return
        }
        guard !windows.isEmpty else {
            selectedIndex = 0
            recomputeLayouts(for: windows)
            resizePanel()
            return
        }
        selectedIndex = min(max(0, selectedIndex - removedBeforeSelection), windows.count - 1)
        recomputeLayouts(for: windows)
        resizePanel()
    }

    private func finishClosingWindow(itemID: String, windowID: CGWindowID, pid: pid_t, attempt: Int) {
        guard sessionActive,
              windows.contains(where: { $0.id == itemID })
        else { return }

        let refreshed = WindowEnumerator.listWindows(for: pid, maximumCount: 64)
        guard !refreshed.contains(where: { $0.windowID == windowID }) else {
            guard attempt < 2 else { return }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in
                self?.finishClosingWindow(itemID: itemID,
                                          windowID: windowID,
                                          pid: pid,
                                          attempt: attempt + 1)
            }
            return
        }

        applyClosedWindowRemoval(itemID: itemID, windowID: windowID)
    }

    private func applyClosedWindowRemoval(itemID: String, windowID: CGWindowID) {
        let state = SwitcherSupport.closeState(afterRemoving: itemID,
                                               itemIDs: windows.map(\.id),
                                               selectedIndex: selectedIndex)
        guard state.didRemove else { return }

        sessionItems.removeAll { $0.id == itemID }
        totalWindowCount = sessionItems.count
        let remaining = Set(state.remainingItemIDs)
        windows = windows.filter { remaining.contains($0.id) }
        let remainingPreviews = Set(windows.compactMap(\.previewWindowID))
        previews = previews.filter { remainingPreviews.contains($0.key) && $0.key != windowID }
        itemMRU.removeAll { $0 == itemID }
        if sessionStartItemID == itemID {
            sessionStartItemID = nil
        }

        guard !state.shouldEndSession else {
            if sessionItems.isEmpty || searchQuery.isEmpty {
                endSession()
            } else {
                selectedIndex = 0
                recomputeLayouts(for: windows)
                resizePanel()
            }
            return
        }

        selectedIndex = state.selectedIndex
        recomputeLayouts(for: windows)
        resizePanel()
    }

    /// Row jump (↑/↓): moves without wrapping so the selection stays put at
    /// the grid edges.
    private func moveSelection(by delta: Int) {
        if iconRowModeEnabled {
            advanceWindowInSelectedApp(by: delta < 0 ? -1 : 1)
            return
        }
        let target = selectedIndex + delta
        guard windows.indices.contains(target) else { return }
        userNavigated = true
        selectedIndex = target
    }

    /// Activates the current selection. Also used by the panel on click.
    func commitSession() {
        guard sessionActive else { return }
        let selection = windows.indices.contains(selectedIndex) ? windows[selectedIndex] : nil
        let source = sessionSourceContext
        endSession()
        if let selection {
            recordUse(selection.id)
            WindowActivator.activate(selection,
                                     sourceWasFullscreen: source?.isFullscreen ?? false,
                                     sourcePID: source?.pid,
                                     sourceWindowID: source?.isFullscreen == true ? nil : source?.windowID)
        }
    }

    private func cancelSession() {
        guard sessionActive else { return }
        endSession()
    }

    private func endSession() {
        sessionActive = false
        pendingShow?.cancel()
        pendingShow = nil
        WindowPreviewProvider.shared.cancel()
        panel?.orderOut(nil)
        sessionItems = []
        windows = []
        previews = [:]
        selectedIndex = 0
        grid = .empty
        iconRowLayout = .empty
        searchQuery = ""
        totalWindowCount = 0
        hoverAnchor = nil
        userNavigated = false
        sessionStartItemID = nil
        sessionSourceContext = nil
        sessionShortcut = nil
    }

    // MARK: - Panel

    /// Shows the panel after a short delay — quick flicks commit before it
    /// fires and never see any UI, exactly like the system switcher.
    private func scheduleShowPanel() {
        pendingShow?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self, self.sessionActive else { return }
            self.showPanel()
        }
        pendingShow = work
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.appearanceDelay, execute: work)
    }

    private func showPanel() {
        let panel = ensurePanel()
        hoverAnchor = NSEvent.mouseLocation
        panel.setFrame(centeredFrame(for: currentPanelSize), display: true)
        panel.orderFrontRegardless()
    }

    /// Re-fits the panel after the grid changed mid-session (e.g. an app quit
    /// with Q). Animated only when already on screen, so the size change reads
    /// as intentional instead of a flash.
    private func resizePanel() {
        guard let panel else { return }
        let frame = centeredFrame(for: currentPanelSize)
        panel.setFrame(frame, display: true, animate: panel.isVisible)
    }

    private var currentPanelSize: CGSize {
        iconRowModeEnabled
            ? iconRowLayout.panelSize
            : grid.panelSize
    }

    private var iconRowModeEnabled: Bool {
        UserDefaults.standard.bool(forKey: DefaultsKey.switcherIconRowMode)
    }

    private func recomputeLayouts(for items: [SwitcherItem]) {
        let screen = NSScreen.withMouse
        grid = SwitcherGrid.compute(count: max(items.count, 1), on: screen)
        let appGroups = SwitcherSupport.appGroups(items: items)
        iconRowLayout = SwitcherIconRowLayout.compute(
            appCount: appGroups.count,
            selectedWindowCount: selectedAppWindowCount(in: items),
            screenVisibleFrame: screen.visibleFrame
        )
    }

    private func updateIconRowLayoutForCurrentSelection() {
        guard !windows.isEmpty else { return }
        let screen = NSScreen.withMouse
        let appGroups = SwitcherSupport.appGroups(items: windows)
        iconRowLayout = SwitcherIconRowLayout.compute(
            appCount: appGroups.count,
            selectedWindowCount: selectedAppWindowCount(in: windows),
            screenVisibleFrame: screen.visibleFrame
        )
    }

    private func selectedAppWindowCount(in items: [SwitcherItem]) -> Int {
        guard items.indices.contains(selectedIndex) else { return 1 }
        let pid = items[selectedIndex].pid
        return max(1, items.filter { $0.pid == pid }.count)
    }

    private func centeredFrame(for size: CGSize) -> NSRect {
        let screen = NSScreen.withMouse.visibleFrame
        return NSRect(x: screen.midX - size.width / 2,
                      y: screen.midY - size.height / 2,
                      width: size.width,
                      height: size.height)
    }

    private func ensurePanel() -> NSPanel {
        if let panel { return panel }

        let panel = NSPanel(contentRect: .zero,
                            styleMask: [.borderless, .nonactivatingPanel],
                            backing: .buffered,
                            defer: false)
        panel.level = .statusBar
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]
        panel.contentViewController = NSHostingController(rootView: SwitcherView().environmentObject(self))
        self.panel = panel
        return panel
    }
}

/// Grid metrics for one switcher session: large cards laid out in as many
/// rows as needed, sized to the screen under the cursor — no sideways
/// scrolling, no squinting.
struct SwitcherGrid: Equatable {
    let columns: Int
    let rows: Int
    let visibleRows: Int
    let panelSize: CGSize

    // Base sizes scaled by the user's preview-size preference (Normal/Large/
    // Extra), so one setting grows the switcher and the Dock preview together.
    static var cardWidth: CGFloat { 288 * PreviewSizing.scale }
    static var cardHeight: CGFloat { 214 * PreviewSizing.scale }
    static let spacing: CGFloat = 12
    static let padding: CGFloat = 20

    static let empty = SwitcherGrid(columns: 1, rows: 1, visibleRows: 1, panelSize: .zero)

    static func compute(count: Int, on screen: NSScreen) -> SwitcherGrid {
        let usableWidth = screen.visibleFrame.width * 0.92
        let usableHeight = screen.visibleFrame.height * 0.85

        let maxColumns = max(1, Int((usableWidth - padding * 2 + spacing) / (cardWidth + spacing)))
        let columns = min(count, maxColumns)
        let rows = Int(ceil(Double(count) / Double(columns)))

        let maxRows = max(1, Int((usableHeight - padding * 2 + spacing) / (cardHeight + spacing)))
        let visibleRows = min(rows, maxRows)

        let width = CGFloat(columns) * cardWidth + CGFloat(columns - 1) * spacing + padding * 2
        let height = CGFloat(visibleRows) * cardHeight + CGFloat(visibleRows - 1) * spacing + padding * 2
        return SwitcherGrid(columns: columns, rows: rows, visibleRows: visibleRows,
                            panelSize: CGSize(width: width, height: height))
    }
}
