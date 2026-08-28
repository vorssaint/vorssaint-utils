// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import ApplicationServices
import Carbon.HIToolbox
import CoreGraphics

/// Adds optional actions when the active app's Dock icon is clicked: minimize
/// its windows, hide the app, or cycle its windows. The Dock's native behavior
/// remains untouched for every other click. Requires Accessibility.
final class DockClickService {
    static let shared = DockClickService()

    private struct ActionRecord {
        let kind: DockClickAction
        let time: CFAbsoluteTime
        /// The windows the action targeted, so a follow-up toggle can undo
        /// exactly them even while the AX state is still settling.
        let targets: [AXUIElement]
    }

    /// A click decided on mouse down, waiting for its mouse up. Acting on the
    /// down used to swallow the very event the Dock needs to start an icon
    /// drag, so the icon of any app the click would act on could never be
    /// reordered (reported with Terminal and Activity Monitor). The action
    /// now commits on a clean mouse up, and movement past the slop replays
    /// the down so the press turns back into a native Dock drag.
    private struct PendingClick {
        let pid: pid_t
        let app: NSRunningApplication
        let origin: CGPoint
        let action: DockClickAction
        let unminimized: [AXUIElement]
        let minimized: [AXUIElement]
        let priorRecord: ActionRecord?
    }

    private var tap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var dockPIDCache: pid_t?
    private var pendingClick: PendingClick?
    /// Last handled click per app: follow-up clicks toggle from this record
    /// instead of re-deriving from ambiguous mid-animation AX state. The tap
    /// runs on the main run loop, so both dictionaries are main-thread-only.
    private var lastAction: [pid_t: ActionRecord] = [:]
    /// Each app's windows front-to-back the instant before we minimized them.
    /// A restore cannot recover this later — minimized windows are off screen
    /// and carry no z-order — and it is what tells the restore which window to
    /// bring back last (issue #357). Kept OUTSIDE `lastAction` on purpose:
    /// that dictionary is pruned to `toggleIntentWindow`, and a user who
    /// watches the animation finish before clicking again (well over 1.5 s,
    /// the ordinary case) would otherwise never get the captured order. Held
    /// until the matching restore consumes it, so any later click still
    /// rebuilds the stacking the user last saw.
    private var minimizeZOrder: [pid_t: [CGWindowID]] = [:]

    /// Marks the replayed mouse down so the tap lets its own event through
    /// (same magic the snippets tap uses for its synthetic events).
    private static let syntheticEventMarker: Int64 = 0x564F5253
    private var pendingSweeps: [pid_t: DispatchWorkItem] = [:]

    private init() {}

    func syncWithPreferences() {
        let minimizeEnabled = UserDefaults.standard.bool(forKey: DefaultsKey.dockClickMinimize)
        let hideEnabled = UserDefaults.standard.bool(forKey: DefaultsKey.dockClickHide)
        let cycleEnabled = UserDefaults.standard.bool(forKey: DefaultsKey.dockClickCycleWindows)
        if AppFeature.dockClick.isAvailable,
           (minimizeEnabled || hideEnabled || cycleEnabled),
           Permissions.shared.accessibility {
            start()
        } else {
            stop()
        }
    }

    /// Force-stops the tap regardless of the preference. Used before the app
    /// resets its own permissions, so a revoked Accessibility grant can never
    /// leave a live tap behind.
    func suspend() { stop() }

    private func start() {
        guard tap == nil else { return }
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: CGEventMask(1 << CGEventType.leftMouseDown.rawValue)
                | CGEventMask(1 << CGEventType.leftMouseDragged.rawValue)
                | CGEventMask(1 << CGEventType.leftMouseUp.rawValue),
            callback: { _, type, event, userInfo in
                guard let userInfo else { return Unmanaged.passUnretained(event) }
                let service = Unmanaged<DockClickService>.fromOpaque(userInfo).takeUnretainedValue()
                return service.handle(type: type, event: event)
            },
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else { return }

        self.tap = tap
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        runLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
    }

    private func stop() {
        if let tap {
            CGEvent.tapEnable(tap: tap, enable: false)
        }
        if let runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        }
        tap = nil
        runLoopSource = nil
        for (_, sweep) in pendingSweeps { sweep.cancel() }
        pendingSweeps = [:]
        lastAction = [:]
        minimizeZOrder = [:]
        pendingClick = nil
    }

    private func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return Unmanaged.passUnretained(event)
        }
        // The replayed down of a press that became a drag: the Dock must
        // receive it untouched.
        if event.getIntegerValueField(.eventSourceUserData) == Self.syntheticEventMarker {
            return Unmanaged.passUnretained(event)
        }
        switch type {
        case .leftMouseDragged:
            return handleDragged(event)
        case .leftMouseUp:
            return handleUp(event)
        case .leftMouseDown:
            break
        default:
            return Unmanaged.passUnretained(event)
        }

        // A fresh press always starts clean; a stale pending click (the tap
        // missed an up during a timeout) must never block the new one.
        pendingClick = nil

        // Modifier clicks keep the Dock's native shortcuts (⌘ reveal, ⌥ hide…).
        guard event.flags.intersection([.maskCommand, .maskControl, .maskAlternate, .maskShift]).isEmpty
        else { return Unmanaged.passUnretained(event) }

        let point = event.location
        guard Self.insideDockStrip(point) else {
            return Unmanaged.passUnretained(event)
        }

        // A Dock Preview panel can dip into the Dock's edge band; those clicks
        // belong to its cards, not to the icons underneath.
        guard !DockPreviewService.shared.panelCovers(axPoint: point) else {
            return Unmanaged.passUnretained(event)
        }

        // The edge band exists on every display and with auto-hide even while
        // the Dock is off screen, but the AX item frames below keep reporting
        // the parked layout and only match along the Dock's long axis — a
        // click near the edge of a Dock-less display whose long-axis
        // coordinate lines up with an icon would minimize or restore apps out
        // of thin air. Only clicks inside the Dock strip that is actually on
        // screen, with nothing drawn over it, can mean an icon.
        guard let dockPID = dockProcessID(),
              DockClickSupport.dockOwnsPoint(
                point,
                windows: Self.onScreenWindows(),
                dockProcessID: dockPID,
                dockLayer: Int(CGWindowLevelForKey(.dockWindow)),
                ownProcessID: getpid()) else {
            return Unmanaged.passUnretained(event)
        }

        // Accessibility gone (e.g. reset): the AX hit-test below would hang
        // inside the tap and freeze clicks, so let the click through untouched.
        guard AXIsProcessTrusted() else { return Unmanaged.passUnretained(event) }

        let hit = dockApplication(at: point)
        guard let app = hit,
              app.processIdentifier != getpid(),
              !DockClickSupport.isOwnBundleIdentifier(app.bundleIdentifier)
        else { return Unmanaged.passUnretained(event) }

        let pid = app.processIdentifier
        let now = CFAbsoluteTimeGetCurrent()
        lastAction = lastAction.filter { now - $0.value.time < DockClickSupport.toggleIntentWindow }
        let record = lastAction[pid]
        let decision = DockClickSupport.repeatDecision(lastAction: record?.kind,
                                                       elapsed: record.map { now - $0.time })
        if decision == .swallow { return nil }

        let cycleEnabled = UserDefaults.standard.bool(forKey: DefaultsKey.dockClickCycleWindows)
        let minimizeEnabled = UserDefaults.standard.bool(forKey: DefaultsKey.dockClickMinimize)
        let hideEnabled = UserDefaults.standard.bool(forKey: DefaultsKey.dockClickHide)
        // Launcher-style apps can misreport isActive; the workspace's idea of
        // the frontmost app is the tiebreaker.
        let frontmost = !app.isHidden && (app.isActive
            || NSWorkspace.shared.frontmostApplication?.processIdentifier == pid
        )
        var windows = (unminimized: [AXUIElement](),
                       minimized: [AXUIElement](),
                       hasFullscreen: false)
        var windowServerSeesWindows = false
        let action: DockClickAction
        if case .toggle(let toggled) = decision {
            windows = Self.standardWindows(pid: pid)
            action = toggled
        } else if hideEnabled, !cycleEnabled {
            // Hiding is an app-level AppKit action. It needs no AX window walk,
            // keeping this common path out of the event tap's timeout budget.
            action = frontmost ? .hide : .passThrough
        } else {
            windows = Self.standardWindows(pid: pid)
            if windows.unminimized.isEmpty, windows.minimized.isEmpty {
                // The AX list came back empty; the window server is the cheap,
                // AX-free truth about whether the app really is windowless.
                // Some compatibility layers regularly fail or time out here
                // while their windows remain plainly visible (#200).
                windowServerSeesWindows = Self.windowServerHasStandardWindows(pid: pid)
                if windowServerSeesWindows {
                    // One slower retry: a busy JVM often just missed the 0.35 s
                    // leash. Rare path, so the extra wait never taxes normal apps.
                    windows = Self.standardWindows(pid: pid, timeout: 0.7)
                }
            }
            let hasUnminimized = DockClickSupport.effectiveHasUnminimized(
                unminimizedCount: windows.unminimized.count,
                minimizedCount: windows.minimized.count,
                windowServerSeesWindows: windowServerSeesWindows)
            action = DockClickSupport.action(appIsFrontmost: frontmost,
                                             hasUnminimizedWindows: hasUnminimized,
                                             hasMinimizedWindows: !windows.minimized.isEmpty,
                                             hasFullscreenWindows: windows.hasFullscreen,
                                             hasModifiers: false,
                                             minimizeEnabled: minimizeEnabled,
                                             hideEnabled: hideEnabled,
                                             cycleWindowsEnabled: cycleEnabled,
                                             unminimizedWindowCount: windows.unminimized.count,
                                             ownsMinimize: ownsMinimize(pid: pid,
                                                                        minimized: windows.minimized))
        }

        // Handled clicks are swallowed (or the Dock would fight us:
        // re-activate on minimize, open a brand-new window on restore), but
        // the action only commits when the button lifts without moving: the
        // press may still turn out to be the start of an icon drag.
        guard action != .passThrough else { return Unmanaged.passUnretained(event) }
        pendingClick = PendingClick(pid: pid, app: app, origin: point, action: action,
                                    unminimized: windows.unminimized,
                                    minimized: windows.minimized,
                                    priorRecord: record)
        return nil
    }

    /// Movement while a click is pending: past the slop the press is a Dock
    /// icon drag, so the swallowed down is replayed (marked, letting it
    /// through) and the Dock takes over; jitter below the slop stays part of
    /// the pending click.
    private func handleDragged(_ event: CGEvent) -> Unmanaged<CGEvent>? {
        guard let pending = pendingClick else { return Unmanaged.passUnretained(event) }
        let point = event.location
        if DockClickSupport.isDragMovement(from: pending.origin, to: point) {
            pendingClick = nil
            guard let down = CGEvent(mouseEventSource: CGEventSource(stateID: .hidSystemState),
                                     mouseType: .leftMouseDown,
                                     mouseCursorPosition: point,
                                     mouseButton: .left) else { return nil }
            down.setIntegerValueField(.eventSourceUserData, value: Self.syntheticEventMarker)
            down.post(tap: .cghidEventTap)
        }
        return nil
    }

    /// A clean release commits the pending action; the up is swallowed like
    /// the down was, so the Dock never sees half a click.
    private func handleUp(_ event: CGEvent) -> Unmanaged<CGEvent>? {
        guard let pending = pendingClick else { return Unmanaged.passUnretained(event) }
        pendingClick = nil
        commit(pending)
        return nil
    }

    /// Applies a decided click. A Dock Preview panel keeps a pre-click idea
    /// of which windows are minimized, and a swallowed click never reaches
    /// its listen-only tap, so it is told directly.
    private func commit(_ pending: PendingClick) {
        let pid = pending.pid
        let now = CFAbsoluteTimeGetCurrent()
        switch pending.action {
        case .cycleWindows:
            lastAction[pid] = ActionRecord(kind: .cycleWindows, time: now, targets: [])
            let unminimized = pending.unminimized
            DispatchQueue.main.async {
                DockPreviewService.shared.dockClickWasHandled()
                Self.cycleWindows(pid: pid, windows: unminimized)
            }
        case .minimize:
            lastAction[pid] = ActionRecord(kind: .minimize, time: now, targets: pending.unminimized)
            // Captured while the windows are still up: this is the last
            // moment their stacking exists anywhere.
            minimizeZOrder[pid] = Self.onScreenWindowIDs(pid: pid)
            // Entries normally leave when their restore consumes them; this
            // clears the ones left by apps minimized from the Dock and then
            // restored some other way. The bound is high enough that the
            // lookups effectively never run on the tap.
            if minimizeZOrder.count > 32 {
                minimizeZOrder = minimizeZOrder.filter {
                    NSRunningApplication(processIdentifier: $0.key) != nil
                }
            }
            // The menu's Minimize All batches every window into one
            // simultaneous animation, so it must act alone: an eager
            // per-window set claims the app's main thread first and the menu
            // action only lands after that window's genie finishes, which
            // visibly minimized multi-window apps one window at a time. Apps
            // whose menu action lies (reports success, windows untouched —
            // the reason the sets used to fire eagerly) get the per-window
            // pass a beat later; the settling sweep stays the last resort.
            let targets = pending.unminimized
            DispatchQueue.main.async { [weak self] in
                DockPreviewService.shared.dockClickWasHandled()
                self?.postMinimizeAll(pid: pid, fallbackWindows: targets, actionTime: now)
            }
            scheduleSweep(pid: pid, targets: targets, minimized: true,
                          delay: DockClickSupport.minimizeSweepDelay)
        case .restore:
            // A toggle right after a minimize also re-opens the captured
            // windows whose AX state hasn't flipped yet, so those go in the
            // batch too. Their position here carries no meaning: the batch is
            // a set, and which window ends up on top is decided further down
            // from the WindowServer stacking captured at minimize time.
            var targets = pending.minimized
            if let record = pending.priorRecord, record.kind == .minimize {
                targets = record.targets + targets
            }
            let frontToBack = minimizeZOrder.removeValue(forKey: pid) ?? []
            lastAction[pid] = ActionRecord(kind: .restore, time: now, targets: targets)
            // The armed minimize sweep has to die with this click, not when
            // the background walk finally gets around to arming the restore
            // sweep — it would otherwise fire mid-walk and re-minimize the
            // windows this click just brought back.
            cancelSweep(pid: pid)
            restoreBackToFront(targets, pid: pid, frontToBack: frontToBack, actionTime: now)
            DispatchQueue.main.async {
                DockPreviewService.shared.dockClickWasHandled()
            }
        case .hide:
            lastAction[pid] = ActionRecord(kind: .hide, time: now, targets: [])
            DispatchQueue.main.async {
                DockPreviewService.shared.dockClickWasHandled()
                _ = pending.app.hide()
            }
        case .passThrough:
            break
        }
    }

    // MARK: - Settling sweep

    /// Re-asserts the action once the animation settles: windows the batched
    /// Minimize All left behind (apps without the standard binding) get
    /// minimized individually, and a restore that clicked in while minimizes
    /// were still in flight re-opens the stragglers. Only the windows captured
    /// at click time are swept — re-querying at fire time would grab windows
    /// the user changed in the meantime — and each new action for the same app
    /// cancels the previous sweep, so exactly one direction wins.
    private func scheduleSweep(pid: pid_t,
                               targets: [AXUIElement],
                               minimized: Bool,
                               delay: TimeInterval,
                               refocus: AXUIElement? = nil) {
        cancelSweep(pid: pid)
        let work = DispatchWorkItem { [weak self] in
            self?.pendingSweeps.removeValue(forKey: pid)
            // Read before hopping off the main thread: whether the app kept
            // the front seat decides if a swept straggler may take focus.
            let appIsFrontmost = NSWorkspace.shared.frontmostApplication?.processIdentifier == pid
            let value: CFBoolean = minimized ? kCFBooleanTrue : kCFBooleanFalse
            DispatchQueue.global(qos: .userInteractive).async {
                // != also sweeps windows whose state cannot be read (nil):
                // setting an already-correct state is a no-op, while skipping
                // an unreadable one leaves Java app windows behind (#200).
                var sweptRestoreStraggler = false
                for window in targets where Self.isMinimized(window) != minimized {
                    AXUIElementSetAttributeValue(window, kAXMinimizedAttribute as CFString, value)
                    sweptRestoreStraggler = !minimized
                }
                // A straggler the sweep re-opened animates in on top of the
                // window the restore pinned focus to, splitting stacking and
                // focus again (issue #357) — re-pin, but only while the app is
                // still frontmost, so a user who moved elsewhere during the
                // settle delay is never yanked back. `refocus` is nil when the
                // restore could not name a front window; correcting toward a
                // guess would be the same mistake, so the stacking is left
                // alone.
                guard sweptRestoreStraggler, appIsFrontmost,
                      let front = refocus, Self.isMinimized(front) == false else { return }
                let app = AXUIElementCreateApplication(pid)
                AXUIElementSetMessagingTimeout(app, 0.35)
                AXUIElementSetAttributeValue(app, kAXFocusedWindowAttribute as CFString, front)
                AXUIElementPerformAction(front, kAXRaiseAction as CFString)
            }
        }
        pendingSweeps[pid] = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    /// Disarms the app's pending sweep and drops it, so a cancelled work item
    /// stops holding on to the window elements it captured.
    private func cancelSweep(pid: pid_t) {
        pendingSweeps.removeValue(forKey: pid)?.cancel()
    }

    private enum MinimizeMenuOutcome {
        /// A menu action ran: the app is animating its own batch.
        case performed
        /// Nothing ran and the synthetic shortcut is unsafe (conflicting or
        /// disabled item); only per-window sets may proceed.
        case shortcutUnsafe
        /// The menu hierarchy exposed no usable action; the shortcut is a
        /// safe last resort alongside the per-window sets.
        case unavailable
    }

    private func postMinimizeAll(pid: pid_t, fallbackWindows: [AXUIElement], actionTime: CFAbsoluteTime) {
        DispatchQueue.global(qos: .userInteractive).async { [weak self] in
            // Pressing the app's own Minimize All menu item beats synthesizing
            // ⌥⌘M: it targets the right app even if focus shifts, skips every
            // event tap in between, and is layout-independent (kVK_ANSI_M is a
            // physical key — on AZERTY it doesn't type an M at all).
            switch Self.handleMinimizeMenu(pid: pid) {
            case .performed:
                // A short beat later, windows an untruthful or plain-Minimize
                // action left up get the per-window set after all. The menu
                // walk above can take longer than the whole toggle gap, so
                // this has to re-check that the minimize is still the app's
                // current action: firing it blind would re-minimize a batch a
                // restore click had already brought back, with nothing left
                // to undo it.
                DispatchQueue.main.asyncAfter(deadline: .now() + DockClickSupport.minimizeMenuVerifyDelay) {
                    guard let self, self.lastAction[pid]?.time == actionTime else { return }
                    DispatchQueue.global(qos: .userInteractive).async {
                        for window in fallbackWindows where Self.isMinimized(window) != true {
                            AXUIElementSetAttributeValue(window, kAXMinimizedAttribute as CFString,
                                                         kCFBooleanTrue)
                        }
                    }
                }
            case .shortcutUnsafe:
                Self.setMinimized(true, windows: fallbackWindows)
            case .unavailable:
                Self.setMinimized(true, windows: fallbackWindows)
                DispatchQueue.main.async {
                    Self.postMinimizeAllShortcut()
                }
            }
        }
    }

    /// Finds and presses the menu item bound to ⌥⌘M (Minimize All) by scanning
    /// the app's menu bar two levels deep — the item lives directly in the
    /// Window menu, so submenus are never entered. Matching by command
    /// character + modifiers instead of the localized title works in every
    /// language the target app ships. Apps without a Minimize All (Java and
    /// Eclipse apps like DBeaver, issue #200) fall back to their plain
    /// Minimize item (⌘M): one window per click, but the click works. This
    /// runs off the tap, so it can afford a longer leash than the tap-side
    /// window enumeration — busy JVMs routinely need it.
    private static func handleMinimizeMenu(pid: pid_t) -> MinimizeMenuOutcome {
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, 1.0)
        guard let menuBar = elementAttribute(app, kAXMenuBarAttribute as String),
              let topLevel = elementArray(menuBar, kAXChildrenAttribute as String)
        else { return .unavailable }

        var plainMinimize: AXUIElement?
        var minimizeAll: AXUIElement?
        var hasConflictingOptionM = false
        // The Window menu sits near the end of the menu bar.
        for barItem in topLevel.reversed() {
            guard let menus = elementArray(barItem, kAXChildrenAttribute as String) else { continue }
            for menu in menus {
                guard let items = elementArray(menu, kAXChildrenAttribute as String) else { continue }
                for item in items {
                    let commandCharacter = stringAttribute(item, "AXMenuItemCmdChar")
                    let modifiers = intAttribute(item, "AXMenuItemCmdModifiers")
                    let isVerifiedMinimizeAll = DockClickSupport.isVerifiedMinimizeAll(
                        commandCharacter: commandCharacter,
                        modifiers: modifiers,
                        identifier: stringAttribute(item, kAXIdentifierAttribute as String)
                    )
                    if isVerifiedMinimizeAll, minimizeAll == nil {
                        minimizeAll = item
                    } else if commandCharacter?.uppercased() == "M", modifiers == 2 {
                        hasConflictingOptionM = true
                    }
                    if commandCharacter?.uppercased() == "M",
                       modifiers == 0, plainMinimize == nil { // ⌘M: plain Minimize
                        plainMinimize = item
                    }
                }
            }
        }
        if let minimizeAll {
            guard boolAttribute(minimizeAll, kAXEnabledAttribute as String) != false else {
                return .shortcutUnsafe
            }
            if AXUIElementPerformAction(minimizeAll, kAXPressAction as CFString) == .success {
                return .performed
            }
        }
        if let plainMinimize,
           boolAttribute(plainMinimize, kAXEnabledAttribute as String) != false {
            if AXUIElementPerformAction(plainMinimize, kAXPressAction as CFString) == .success {
                return .performed
            }
        }
        return hasConflictingOptionM ? .shortcutUnsafe : .unavailable
    }

    private static func postMinimizeAllShortcut() {
        // The modifier KEYS must be pressed and released explicitly, mirroring
        // real typing. Posting only the M events with ⌘⌥ flags latches those
        // modifiers into the session's flag state — every later click becomes
        // a ⌘⌥-click system-wide until the user physically presses them.
        let source = CGEventSource(stateID: .hidSystemState)
        let sequence: [(key: Int, down: Bool, flags: CGEventFlags)] = [
            (kVK_Command, true, [.maskCommand]),
            (kVK_Option, true, [.maskCommand, .maskAlternate]),
            (kVK_ANSI_M, true, [.maskCommand, .maskAlternate]),
            (kVK_ANSI_M, false, [.maskCommand, .maskAlternate]),
            (kVK_Option, false, [.maskCommand]),
            (kVK_Command, false, []),
        ]
        for step in sequence {
            guard let event = CGEvent(keyboardEventSource: source,
                                      virtualKey: CGKeyCode(step.key),
                                      keyDown: step.down) else { continue }
            event.flags = step.flags
            event.post(tap: .cghidEventTap)
        }
    }

    private static func setMinimized(_ minimized: Bool, windows: [AXUIElement]) {
        let value: CFBoolean = minimized ? kCFBooleanTrue : kCFBooleanFalse
        for window in windows {
            DispatchQueue.global(qos: .userInteractive).async {
                AXUIElementSetAttributeValue(window, kAXMinimizedAttribute as CFString, value)
            }
        }
    }

    /// Whether the pending click may reclaim this app's minimized windows.
    ///
    /// The capture written at minimize time is the only claim this feature has
    /// on them. It survives until a restore consumes it, so a user who brought
    /// the windows back another way leaves it behind; a leftover is dropped
    /// here rather than carried, so the next click starts from the truth.
    private func ownsMinimize(pid: pid_t, minimized: [AXUIElement]) -> Bool {
        guard let captured = minimizeZOrder[pid] else { return false }
        let stillDown = Set(minimized.compactMap(AXWindowResolver.windowID))
        guard DockClickSupport.capturedMinimizeStillHolds(captured: captured,
                                                          stillMinimized: stillDown) else {
            minimizeZOrder.removeValue(forKey: pid)
            return false
        }
        return true
    }

    /// Brings a minimized batch back rearmost first, so the window that was
    /// frontmost when they went down is the last one to animate in and lands
    /// on top by itself. Nothing is raised or re-stacked afterwards: pulling
    /// the right window to the front after the fact is precisely the flick
    /// the user sees (issue #357), so the order has to be right instead.
    ///
    /// Each window is read back and retried once before moving on. The set is
    /// a fire-and-forget AX write, and a window whose write the app dropped
    /// while still settling its own minimize would otherwise come back later
    /// — out of order, on top of the window that should own the top slot.
    ///
    /// The app is activated only once the rear windows are up. Activating
    /// while everything is still minimized invites macOS to bring the app's
    /// main window back on its own, ahead of the batch, which buries the
    /// window the user actually wants at the bottom of the pile.
    private func restoreBackToFront(_ targets: [AXUIElement],
                                    pid: pid_t,
                                    frontToBack: [CGWindowID],
                                    actionTime: CFAbsoluteTime) {
        guard !targets.isEmpty else {
            // An AX-blind app (issue #200) reaches a restore with nothing to
            // restore: its windows never made it into either list. The click
            // was swallowed, so the Dock will not act either — bring the app
            // forward or the icon looks dead.
            Self.activate(pid: pid)
            return
        }
        DispatchQueue.global(qos: .userInteractive).async { [weak self] in
            let axApp = AXUIElementCreateApplication(pid)
            AXUIElementSetMessagingTimeout(axApp, 0.35)
            let ids = targets.map { AXWindowResolver.windowID(for: $0) }
            // Without a captured order (the app was minimized by other means)
            // the app's own main window is the best guess at where the user
            // left off.
            let preferredFront = frontToBack.isEmpty
                ? Self.elementAttribute(axApp, kAXMainWindowAttribute as String)
                    .flatMap(AXWindowResolver.windowID)
                : nil
            let sequence = DockClickSupport.restoreSequence(ids: ids,
                                                            frontToBack: frontToBack,
                                                            preferredFront: preferredFront)
            let ordered = sequence.map { targets[$0] }
            guard let frontSlot = sequence.last else {
                Self.activate(pid: pid)
                return
            }
            let front = targets[frontSlot]
            // Which window belongs on top, when it can be named: the frontmost
            // captured window still in this batch, else the app's own main
            // one. With neither — nothing captured and no main window, which
            // is the normal reading while every window is minimized — the
            // batch order is a guess, and forcing focus onto a guess is worse
            // than leaving it to activation, which usually lands on the
            // window the user left.
            let knownFront = frontToBack.first { id in ids.contains { $0 == id } } ?? preferredFront
            let pinnedFront: AXUIElement? = knownFront != nil && ids[frontSlot] == knownFront
                ? front
                : nil

            for window in ordered.dropLast() {
                Self.restore(window)
            }
            Self.activate(pid: pid)
            Self.restore(front)
            if let pinnedFront {
                AXUIElementSetAttributeValue(axApp, kAXMainWindowAttribute as CFString, pinnedFront)
                AXUIElementSetAttributeValue(axApp, kAXFocusedWindowAttribute as CFString, pinnedFront)
            }

            DispatchQueue.main.async {
                // Only the click that started this walk may schedule its
                // sweep: if another action for the app clicked in meanwhile,
                // its sweep owns the direction now.
                guard let self, self.lastAction[pid]?.time == actionTime else { return }
                self.scheduleSweep(pid: pid, targets: ordered, minimized: false,
                                   delay: DockClickSupport.restoreSweepDelay, refocus: pinnedFront)
            }
        }
    }

    /// Brings an app forward from whatever queue the caller is on.
    ///
    /// A bare `activate()` is not enough here. Since macOS 14 an app that is
    /// not itself frontmost cannot raise another one, and this tap swallowed
    /// the click precisely so the Dock would not act — so nobody else is going
    /// to. The restore then half-lands: unminimizing needs no activation
    /// rights, so the windows come back and are immediately stacked under
    /// whichever app is still active. Yielding this app's activation first is
    /// what makes the request cooperative, the same sequence the Switcher,
    /// Space hop and process list already use.
    ///
    /// Options stay empty on purpose: `restoreBackToFront` earns the batch's
    /// stacking one window at a time, and `.activateAllWindows` would re-raise
    /// the whole app over it — the flick issue #357 was about.
    private static func activate(pid: pid_t) {
        DispatchQueue.main.async {
            guard let app = NSRunningApplication(processIdentifier: pid), !app.isTerminated else { return }
            NSApp.yieldActivation(to: app)
            if !app.activate(from: NSRunningApplication.current, options: []) {
                app.activate(options: [])
            }
        }
    }

    /// Unminimizes one window and confirms it took, retrying once. Blocking on
    /// the read keeps the batch in step: the next window must not start its
    /// animation until this one has actually begun its own.
    private static func restore(_ window: AXUIElement) {
        guard isMinimized(window) != false else { return }
        AXUIElementSetAttributeValue(window, kAXMinimizedAttribute as CFString, kCFBooleanFalse)
        guard isMinimized(window) == true else { return }
        AXUIElementSetAttributeValue(window, kAXMinimizedAttribute as CFString, kCFBooleanFalse)
    }

    /// Cycles through an app's unminimized windows by raising the rearmost one
    /// to the front, mimicking ⌘` (Command-Tilde) behavior.
    ///
    /// The rearmost window comes from the WindowServer's real z-order, not the
    /// AX windows array: that array keeps the focused window first, so
    /// "advance from the focused one" degenerates into flipping between the
    /// two frontmost windows and the rest are never visited. Raising the true
    /// rearmost window walks every window in round-robin order.
    private static func cycleWindows(pid: pid_t, windows: [AXUIElement]) {
        guard windows.count > 1 else { return }

        let rearWindow: AXUIElement
        if let rear = rearmostByZOrder(pid: pid, windows: windows) {
            rearWindow = rear
        } else {
            // No z-order available (window ids unresolved): the AX array is
            // focused-first, so its last element is still the best rear guess.
            rearWindow = windows[windows.count - 1]
        }

        AXUIElementPerformAction(rearWindow, kAXRaiseAction as CFString)
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetAttributeValue(app, kAXFocusedWindowAttribute as CFString, rearWindow)
    }

    /// The candidate that sits deepest in the WindowServer's front-to-back
    /// on-screen list. Windows on other Spaces are not in that list, which is
    /// wanted: cycling from the Dock must not yank the user across Spaces.
    private static func rearmostByZOrder(pid: pid_t, windows: [AXUIElement]) -> AXUIElement? {
        let orderedIDs = onScreenWindowIDs(pid: pid)
        guard orderedIDs.count > 1 else { return nil }
        var rear: (window: AXUIElement, depth: Int)?
        for window in windows {
            guard let id = AXWindowResolver.windowID(for: window),
                  let depth = orderedIDs.firstIndex(of: id) else { continue }
            if rear == nil || depth > rear!.depth {
                rear = (window, depth)
            }
        }
        return rear?.window
    }

    // MARK: - Geometry

    private static func onScreenWindows() -> [MouseAppExceptionSupport.Window] {
        guard let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements],
                                                    kCGNullWindowID) as? [[String: Any]] else {
            return []
        }
        return MouseAppExceptionSupport.windows(from: list)
    }

    /// Cheap pre-filter before any AX call, in the event's top-left-origin
    /// global coordinates. With magnification the hovered icon can grow above
    /// the reserved strip; such clicks fall back to the Dock's native handling.
    private static func insideDockStrip(_ point: CGPoint) -> Bool {
        let primaryHeight = NSScreen.screens.first?.frame.maxY ?? 0
        for screen in NSScreen.screens {
            let frame = axRect(screen.frame, primaryHeight: primaryHeight)
            let visible = axRect(screen.visibleFrame, primaryHeight: primaryHeight)
            if DockClickSupport.dockStripContains(point, screenFrame: frame, visibleFrame: visible) {
                return true
            }
        }
        return false
    }

    private static func axRect(_ rect: CGRect, primaryHeight: CGFloat) -> CGRect {
        CGRect(x: rect.minX,
               y: primaryHeight - rect.maxY,
               width: rect.width,
               height: rect.height)
    }

    // MARK: - Dock hit test

    /// Resolves which Dock app icon a click landed on by walking the Dock's
    /// item list and matching along the Dock's LONG axis only. Position-based
    /// AX hit-testing is useless here: macOS reports the Dock strip's AX
    /// frames shifted on the short axis (observed ~72 pt on macOS 27), while
    /// the long-axis coordinates stay truthful. The strip gate above already
    /// bounded the short axis.
    private func dockApplication(at point: CGPoint) -> NSRunningApplication? {
        guard let dockPID = dockProcessID() else { return nil }
        let dockElement = AXUIElementCreateApplication(dockPID)
        AXUIElementSetMessagingTimeout(dockElement, 0.35)
        guard let children = Self.elementArray(dockElement, kAXChildrenAttribute as String) else { return nil }

        for child in children where Self.roleString(child) == "AXList" {
            guard let items = Self.elementArray(child, kAXChildrenAttribute as String),
                  let listFrame = Self.axFrame(child)
            else { continue }
            let horizontal = listFrame.width >= listFrame.height
            for item in items {
                guard let frame = Self.axFrame(item) else { continue }
                let hit = horizontal
                    ? (point.x >= frame.minX && point.x <= frame.maxX)
                    : (point.y >= frame.minY && point.y <= frame.maxY)
                guard hit, let url = Self.urlAttribute(item) else { continue }
                let standardized = url.standardizedFileURL.path
                return NSWorkspace.shared.runningApplications.first {
                    $0.activationPolicy == .regular && !$0.isTerminated
                        && $0.bundleURL?.standardizedFileURL.path == standardized
                }
            }
        }
        return nil
    }

    private static func elementArray(_ element: AXUIElement, _ attribute: String) -> [AXUIElement]? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success,
              let array = value as? [AXUIElement]
        else { return nil }
        return array
    }

    private static func elementAttribute(_ element: AXUIElement, _ attribute: String) -> AXUIElement? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success,
              let value,
              CFGetTypeID(value) == AXUIElementGetTypeID()
        else { return nil }
        return (value as! AXUIElement)
    }

    private static func roleString(_ element: AXUIElement) -> String? {
        stringAttribute(element, kAXRoleAttribute as String)
    }

    private static func stringAttribute(_ element: AXUIElement, _ attribute: String) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success
        else { return nil }
        return value as? String
    }

    private static func intAttribute(_ element: AXUIElement, _ attribute: String) -> Int? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success
        else { return nil }
        return (value as? NSNumber)?.intValue
    }

    private static func boolAttribute(_ element: AXUIElement, _ attribute: String) -> Bool? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success
        else { return nil }
        return value as? Bool
    }

    private static func axFrame(_ element: AXUIElement) -> CGRect? {
        var positionValue: CFTypeRef?
        var sizeValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString, &positionValue) == .success,
              AXUIElementCopyAttributeValue(element, kAXSizeAttribute as CFString, &sizeValue) == .success,
              let positionValue, let sizeValue,
              CFGetTypeID(positionValue) == AXValueGetTypeID(),
              CFGetTypeID(sizeValue) == AXValueGetTypeID()
        else { return nil }
        var position = CGPoint.zero
        var size = CGSize.zero
        guard AXValueGetValue((positionValue as! AXValue), .cgPoint, &position),
              AXValueGetValue((sizeValue as! AXValue), .cgSize, &size),
              size.width > 0, size.height > 0
        else { return nil }
        return CGRect(origin: position, size: size)
    }

    private func dockProcessID() -> pid_t? {
        if let dockPIDCache,
           NSRunningApplication(processIdentifier: dockPIDCache)?.isTerminated == false {
            return dockPIDCache
        }
        let pid = NSWorkspace.shared.runningApplications.first {
            $0.bundleIdentifier == "com.apple.dock"
        }?.processIdentifier
        dockPIDCache = pid
        return pid
    }

    private static func urlAttribute(_ element: AXUIElement) -> URL? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXURLAttribute as CFString, &value) == .success,
              let value,
              CFGetTypeID(value) == CFURLGetTypeID()
        else { return nil }
        return (value as! CFURL) as URL
    }

    // MARK: - Windows

    private static func isMinimized(_ window: AXUIElement) -> Bool? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(window, kAXMinimizedAttribute as CFString, &value) == .success
        else { return nil }
        return value as? Bool
    }

    /// The pid's normal on-screen windows in the WindowServer's front-to-back
    /// order. AX-free and cheap, and the only place the real stacking can be
    /// read: the AX windows array does not reliably report it.
    private static func onScreenWindowIDs(pid: pid_t) -> [CGWindowID] {
        guard let info = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements],
                                                    kCGNullWindowID) as? [[String: Any]] else { return [] }
        return info.compactMap { entry -> CGWindowID? in
            guard entry[kCGWindowOwnerPID as String] as? pid_t == pid,
                  entry[kCGWindowLayer as String] as? Int == 0,
                  let number = entry[kCGWindowNumber as String] as? CGWindowID else { return nil }
            return number
        }
    }

    /// Whether the window server lists any normal on-screen window for the
    /// pid. AX-free, so it stays truthful for apps whose accessibility side
    /// is busy or unresponsive.
    private static func windowServerHasStandardWindows(pid: pid_t) -> Bool {
        !onScreenWindowIDs(pid: pid).isEmpty
    }

    /// The app's standard windows split by minimized state, plus whether any
    /// window is fullscreen (those can't minimize and must veto the action).
    private static func standardWindows(pid: pid_t, timeout: Float = 0.35)
        -> (unminimized: [AXUIElement], minimized: [AXUIElement], hasFullscreen: Bool) {
        let appElement = AXUIElementCreateApplication(pid)
        // This runs inside the tap callback against the app the user just
        // clicked — often one that is busy or hung. Without an explicit
        // timeout every call here would wait out the multi-second AX default
        // and stall click delivery system-wide.
        AXUIElementSetMessagingTimeout(appElement, timeout)
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(appElement, kAXWindowsAttribute as CFString, &value) == .success,
              let windows = value as? [AXUIElement]
        else { return ([], [], false) }
        var unminimized: [AXUIElement] = []
        var minimized: [AXUIElement] = []
        var hasFullscreen = false
        for window in windows {
            AXUIElementSetMessagingTimeout(window, timeout)
            // Role must be a real window: Finder also lists the desktop here
            // (an AXScrollArea) and it would otherwise count as a window.
            guard Self.roleString(window) == (kAXWindowRole as String) else { continue }
            // An unreadable minimized state (busy JVM, SWT quirks) must not
            // erase the window from BOTH lists — a frontmost app whose
            // windows all fail this read would look windowless and the click
            // would do nothing (issue #200). Unknown reads as "not
            // minimized": over-including a minimize target is harmless, and
            // the restore action never fires while one exists.
            let isWindowMinimized = isMinimized(window) ?? false
            if isWindowMinimized {
                // No subrole check: macOS flips a minimized window's subrole
                // from AXStandardWindow to AXDialog.
                minimized.append(window)
                continue
            }
            if boolAttribute(window, "AXFullScreen") == true {
                hasFullscreen = true
                continue
            }
            if let subroleString = stringAttribute(window, kAXSubroleAttribute as String),
               subroleString != "AXStandardWindow" {
                continue
            }
            unminimized.append(window)
        }
        return (unminimized, minimized, hasFullscreen)
    }
}
