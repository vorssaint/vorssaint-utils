// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit

/// Watches for text selections made anywhere on the Mac and offers a small
/// floating bar of actions next to them — copy, search, translate, change
/// case, and so on. A global mouse monitor notices the end of a real
/// selection gesture (a drag, or a double/triple-click — never a plain
/// single click, which would otherwise misfire on things like clicking a
/// browser tab that still has old page text selected underneath);
/// Accessibility supplies the text and its screen position, the same way
/// the Command Bar already reads what is selected. A keyboard shortcut
/// offers the same read on demand, for a selection made without a fresh
/// mouse gesture (arrow-key selection, or re-summoning after the bar
/// auto-dismissed).
final class SelectionActionsService: ObservableObject {
    static let shared = SelectionActionsService()

    @Published private(set) var shortcutRegistrationFailed = false

    private var mouseMonitor: Any?
    /// `addGlobalMonitorForEvents` only delivers events bound for *other*
    /// processes — it never sees mouse events for this app's own windows, so
    /// without a matching local monitor the bar could never appear in the
    /// Scratchpad or any other in-app text view.
    private var localMouseMonitor: Any?
    private var mouseDownLocation: CGPoint?
    private var pendingRead: DispatchWorkItem?
    private var barController: SelectionActionBarController?
    private let hotkey = QuickToolHotkey(id: 21)
    /// Bumped on every read; a read that finishes after a newer one started
    /// (or after the feature was switched off) is discarded rather than
    /// popping a bar for a selection nobody cares about anymore.
    private var generation = 0

    /// A plain click without movement is not a selection gesture.
    private static let dragThreshold: CGFloat = 4

    private init() {
        hotkey.onPress = { [weak self] in self?.summon() }
    }

    func syncWithPreferences() {
        let available = AppFeature.selectionActions.isAvailable
        let enabled = available && UserDefaults.standard.bool(forKey: DefaultsKey.selectionActionsEnabled)
        if enabled {
            startMonitor()
        } else {
            stopMonitor()
        }
        let shortcutEnabled = enabled
            && UserDefaults.standard.bool(forKey: DefaultsKey.selectionActionsShortcutEnabled)
        let shortcut = GlobalShortcut.saved(for: DefaultsKey.selectionActionsShortcut,
                                            fallback: .selectionActionsDefault)
        shortcutRegistrationFailed = !hotkey.sync(enabled: shortcutEnabled, shortcut: shortcut)
    }

    func suspend() {
        stopMonitor()
        hotkey.unregister()
    }

    /// Reads whatever is selected right now and shows the bar for it,
    /// bypassing the mouse-gesture gate — the keyboard shortcut's whole
    /// point is to work without one.
    func summon() {
        performRead(expected: nextGeneration(), targetPID: nil, clickLocation: nil,
                   isLocal: false, allowsEmptySelection: true)
    }

    private func startMonitor() {
        guard mouseMonitor == nil else { return }
        mouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .leftMouseUp]) {
            [weak self] event in
            self?.handleMonitoredEvent(event, isLocal: false)
        }
        localMouseMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .leftMouseUp]) {
            [weak self] event in
            self?.handleMonitoredEvent(event, isLocal: true)
            return event
        }
    }

    /// `isLocal` tells us for certain whether this gesture happened inside
    /// our own app: for a local-monitor event the target process is always
    /// us, no need to infer it from "frontmost"/"focused" app bookkeeping,
    /// which a `.nonactivatingPanel` (the Scratchpad) never updates anyway.
    private func handleMonitoredEvent(_ event: NSEvent, isLocal: Bool) {
        switch event.type {
        case .leftMouseDown:
            mouseDownLocation = NSEvent.mouseLocation
        case .leftMouseUp:
            handleMouseUp(event, isLocal: isLocal)
        default: break
        }
    }

    private func stopMonitor() {
        if let mouseMonitor { NSEvent.removeMonitor(mouseMonitor) }
        mouseMonitor = nil
        if let localMouseMonitor { NSEvent.removeMonitor(localMouseMonitor) }
        localMouseMonitor = nil
        mouseDownLocation = nil
        pendingRead?.cancel()
        pendingRead = nil
        generation += 1
        barController?.close()
        barController = nil
    }

    /// Only a real selection gesture schedules a read: a drag past a few
    /// points, or a double/triple-click (`clickCount` catches word/line
    /// select, which has no drag at all). A plain single click — placing a
    /// cursor, clicking a button, switching a browser tab — is left alone,
    /// even when the app underneath still happens to report old selected
    /// text from before the click. A double-click *is* still ambiguous
    /// though: quickly double-clicking a browser tab to switch is a real
    /// double-click gesture too, and can surface text that was selected on
    /// that tab's page long before this click — `handleRead` throws that
    /// out by checking the click actually landed near the reported
    /// selection.
    private func handleMouseUp(_ event: NSEvent, isLocal: Bool) {
        defer { mouseDownLocation = nil }
        let isMultiClick = event.clickCount >= 2
        let up = NSEvent.mouseLocation
        let draggedFarEnough: Bool
        if let down = mouseDownLocation {
            draggedFarEnough = hypot(up.x - down.x, up.y - down.y) > Self.dragThreshold
        } else {
            draggedFarEnough = false
        }
        guard isMultiClick || draggedFarEnough else { return }
        // A local-monitor event is definitely ours; targeting our own
        // process directly sidesteps "frontmost"/"focused" app lookups
        // that a `.nonactivatingPanel` like the Scratchpad never satisfies.
        let targetPID = isLocal ? getpid() : nil
        // A drag that ends up selecting nothing shouldn't summon the
        // no-selection Paste bar — that fallback is only for a deliberate
        // double/triple-click landing on empty space, not an incidental
        // empty drag (e.g. clicking-and-dragging through blank canvas).
        scheduleRead(targetPID: targetPID, clickLocation: up, isLocal: isLocal, allowsEmptySelection: isMultiClick)
    }

    /// Coalesces a fast run of clicks (e.g. double/triple-click to select a
    /// word or line) into a single read, and gives the target app a beat to
    /// finish updating its own selection state after the mouse-up.
    private func scheduleRead(targetPID: pid_t?, clickLocation: CGPoint, isLocal: Bool, allowsEmptySelection: Bool) {
        pendingRead?.cancel()
        let expected = nextGeneration()
        let work = DispatchWorkItem { [weak self] in
            self?.performRead(expected: expected, targetPID: targetPID, clickLocation: clickLocation,
                              isLocal: isLocal, allowsEmptySelection: allowsEmptySelection)
        }
        pendingRead = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08, execute: work)
    }

    private func nextGeneration() -> Int {
        generation += 1
        return generation
    }

    private func performRead(expected: Int, targetPID: pid_t?, clickLocation: CGPoint?,
                             isLocal: Bool, allowsEmptySelection: Bool) {
        // Excluded-app/domain checks are about *other* apps and websites;
        // a local read is always us, which is never a meaningful exclusion
        // target, and the exclusion check itself would otherwise resolve to
        // whatever app was frontmost before Scratchpad's nonactivating
        // panel took focus — the wrong app entirely.
        guard isLocal || !isFrontmostAppExcluded() else {
            DispatchQueue.main.async { [weak self] in self?.dismiss() }
            return
        }
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            SelectionReader.read(pid: targetPID) { snapshot in
                DispatchQueue.main.async {
                    self?.handleRead(snapshot, expected: expected, clickLocation: clickLocation,
                                     isLocal: isLocal, allowsEmptySelection: allowsEmptySelection)
                }
            }
        }
    }

    /// The app and, for a handful of known browsers, the website the person
    /// is looking at right now — checked before Accessibility is ever
    /// touched, so an excluded app costs nothing beyond reading its bundle
    /// ID.
    private func isFrontmostAppExcluded() -> Bool {
        guard let front = SelectionReader.focusedApplication() else { return false }
        if SelectionActionsExcludedApps.shared.isExcluded(front.bundleIdentifier) { return true }
        let domainsRaw = UserDefaults.standard.string(forKey: DefaultsKey.selectionActionsExcludedDomains) ?? ""
        guard !domainsRaw.isEmpty else { return false }
        let domains = SelectionActionsExcludedDomains.decode(domainsRaw)
        return SelectionActionsExcludedDomains.matches(host: BrowserURLReader.currentHost(for: front),
                                                        domains: domains)
    }

    /// How far the reported selection may sit from where the click actually
    /// landed before it is treated as unrelated to this gesture — generous
    /// enough for a real selection ending a little past the pointer, tight
    /// enough to reject a page's stale selection sitting elsewhere in the
    /// window (e.g. a double-click that switched browser tabs instead of
    /// selecting a word). Only meaningful for a read from *another* app: a
    /// local-monitor read is guaranteed to come from whatever's actually
    /// focused in our own window, with no "wrong window's stale text" to
    /// guard against — applying it there was rejecting genuine Scratchpad
    /// selections outright.
    private static let staleSelectionTolerance: CGFloat = 60

    private func handleRead(_ snapshot: SelectionSnapshot?, expected: Int, clickLocation: CGPoint?,
                            isLocal: Bool, allowsEmptySelection: Bool) {
        guard expected == generation else { return }
        guard let snapshot else {
            dismiss()
            return
        }
        if snapshot.text.isEmpty, !allowsEmptySelection {
            dismiss()
            return
        }
        // `boundsInScreen` needs an actual selected range, so it's normally
        // nil for the empty-selection Paste bar — `elementFrame` (the
        // focused element's own position, not a range within it) covers
        // that case instead: an input clicked earlier, then still reported
        // as focused after clicking a browser tab far away, is caught here
        // the same way a stale *selection* is caught above.
        if !isLocal, let clickLocation, let compareFrame = snapshot.boundsInScreen ?? snapshot.elementFrame,
           !compareFrame.insetBy(dx: -Self.staleSelectionTolerance, dy: -Self.staleSelectionTolerance)
                .contains(clickLocation) {
            dismiss()
            return
        }
        let defaults = UserDefaults.standard
        let disabledRaw = defaults.string(forKey: DefaultsKey.selectionActionsDisabledActions) ?? ""
        let orderRaw = defaults.string(forKey: DefaultsKey.selectionActionsOrder) ?? ""
        let actions = SelectionActionCatalog.availableActions(for: snapshot.text,
                                                               isEditable: snapshot.isEditable,
                                                               disabledRaw: disabledRaw,
                                                               orderRaw: orderRaw)
        guard !actions.isEmpty else {
            dismiss()
            return
        }
        let maxVisible = defaults.object(forKey: DefaultsKey.selectionActionsMaxVisible) as? Int ?? 8
        present(snapshot: snapshot, actions: actions, maxVisible: maxVisible)
    }

    private func dismiss() {
        barController?.close()
        barController = nil
    }

    private func present(snapshot: SelectionSnapshot, actions: [SelectionAction], maxVisible: Int) {
        // Always fresh: the controller can close itself (auto-dismiss timer,
        // outside click, any keypress, app switch) without telling us, which
        // leaves it permanently `closed` — reusing that instance would make
        // every later `show()` silently no-op. One controller per
        // presentation, matching its own doc comment.
        barController?.close()
        let controller = SelectionActionBarController()
        barController = controller
        controller.show(snapshot: snapshot, actions: actions, maxVisible: maxVisible) { [weak self] action in
            self?.barController?.close()
            self?.barController = nil
            SelectionActionRunner.run(action, on: snapshot)
        }
    }
}
