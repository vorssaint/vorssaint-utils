// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import ApplicationServices
import Carbon.HIToolbox
import Combine
import CoreGraphics
import SwiftUI

private struct SwitcherSourceContext {
    let itemID: String?
    let pid: pid_t
    let windowID: CGWindowID?
    let windowOwnerPID: pid_t?
    let isFullscreen: Bool
}

/// A shortcut press already owned by the switcher while the window list is
/// being assembled. The tap thread can cancel or add repeated navigation
/// without ever waiting for the main thread or Accessibility.
private struct SwitcherPendingSessionStart {
    let generation: UInt64
    let shortcut: GlobalShortcut
    let scope: SwitcherSessionScope
    let reversed: Bool
    var additionalNavigation = 0
    var commitWhenReady = false
}

/// The window switcher: a global event tap takes over the configured shortcut,
/// and while its modifiers are held a non-activating panel cycles through real
/// windows. Releasing commits, middle-clicking a card or pressing W closes the
/// highlighted window, and Q quits its app. When the optional pin-search
/// preference is enabled, S pins the search field open (so typing no longer
/// needs the modifier held). Esc and a click outside cancel. The panel joins
/// every Space and fullscreen app, so the switcher is available wherever the
/// user is.
final class AppSwitcher: ObservableObject {
    static let shared = AppSwitcher()

    @Published private(set) var windows: [SwitcherItem] = []
    @Published private(set) var previews: [CGWindowID: CGImage] = [:]
    @Published private(set) var selectedIndex = 0 {
        didSet {
            guard oldValue != selectedIndex else { return }
            updateIconRowLayoutForCurrentSelection()
            revealSelectedIconInVisibleRow()
            if sessionActive, usesIconRowLayout {
                resizePanel()
            }
        }
    }
    @Published private(set) var grid = SwitcherGrid.empty
    @Published private(set) var iconRowLayout = SwitcherIconRowLayout.empty
    /// First icon currently shown in an overflow row. The row steps this
    /// index by one when the pointer parks on the last visible icon.
    @Published private(set) var iconRowFirstVisibleIndex = 0
    @Published private(set) var searchQuery = ""
    /// True once S pinned the search field open. While set, releasing the
    /// session's modifier no longer commits — search text can then be typed
    /// with no modifier held, so a letter never comes out as the modifier's
    /// special character (⌥ on its own types symbols on layouts like US,
    /// e.g. ⌥S types "ß").
    @Published private(set) var isSearchPinned = false
    @Published private(set) var totalWindowCount = 0

    /// Single source of truth for "a session is open": the stored value lives
    /// under `routeLock` because the tap thread routes every keystroke by it.
    /// Written only on the main thread.
    private var sessionActive: Bool {
        get { routeLock.withLock { routeSessionActive } }
        set { routeLock.withLock { routeSessionActive = newValue } }
    }
    private var panel: NSPanel?
    private var sessionItems: [SwitcherItem] = []

    // The tap lives on a dedicated thread: an active keyDown tap makes the
    // window server hold every keystroke in the login session until this
    // process answers, so the callback must never queue behind main-thread
    // work. On the main run loop, any stall here delayed keys system-wide
    // and then released them in a burst (issue #275). Same lifecycle shape
    // as the keyboard debounce tap.
    private let lifecycleLock = NSLock()
    private var tap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var tapRunLoop: CFRunLoop?
    private var tapThread: Thread?
    private var shouldStopTapThread = false
    private var pendingStartAfterStop = false
    /// Alive only while the Switcher's tap needs layout labels off main.
    private var keyboardLayoutObserver: NSObjectProtocol?
    private var wakeObserver: NSObjectProtocol?
    private var wakeRetry: DispatchWorkItem?

    /// The little state the tap thread needs to route an event without
    /// touching the main thread; mutated only under `routeLock`.
    private let routeLock = NSLock()
    private var routeSessionActive = false
    private var routeShortcut = GlobalShortcut.switcherDefault
    private var routeWindowShortcut = GlobalShortcut.switcherWindowDefault
    private var routeCapturing = false
    private var routeCanStartSession = false
    private var routePendingSessionStart: SwitcherPendingSessionStart?
    private var sessionStartGeneration: UInt64 = 0

    /// The panel appears only after this delay, like the system switcher: a
    /// quick ⌘Tab flick switches with no UI at all, which is what makes rapid
    /// toggling feel instant instead of flashing a window.
    private static let appearanceDelay: TimeInterval = 0.1
    private var pendingShow: DispatchWorkItem?
    /// True once the user moved the selection themselves.
    private var userNavigated = false
    /// Mouse position when the panel appeared; hover is inert until it moves.
    private var hoverAnchor: NSPoint?
    /// Fires while the pointer stays on the last visible overflow icon.
    private var iconRowEdgeHoverWork: DispatchWorkItem?
    private var iconRowEdgeHoverIndex: Int?

    /// The on-screen window when the current session opened — becomes the
    /// second-most-recent window on commit, so a flick toggles straight back.
    /// Cleared if that window is closed during the session: a window the user
    /// just got rid of is not somewhere to send them back to.
    private var sessionStartWindowID: CGWindowID?
    private var sessionSourceContext: SwitcherSourceContext?
    private var sessionShortcut: GlobalShortcut?
    private var sessionScope: SwitcherSessionScope = .allApps
    private var shiftBackNavigationHeld = false

    /// Windows already asked to close, still listed until they are really
    /// gone. Releasing the shortcut skips them, so they are never raised on
    /// the way out.
    private var closingItemIDs: Set<String> = []
    private var commitPendingForClose = false

    // Virtual key codes handled during a session.
    private enum KeyCode {
        static let tab: Int64 = 48
        static let delete: Int64 = 51
        static let escape: Int64 = 53
        static let enter: Int64 = 36
        static let leftArrow: Int64 = 123
        static let rightArrow: Int64 = 124
        static let downArrow: Int64 = 125
        static let upArrow: Int64 = 126
    }

    private init() {}

    /// True while the event tap is installed.
    var isRunning: Bool { lifecycleLock.withLock { tap != nil } }

    /// Applies the persisted preference; safe to call repeatedly.
    func syncWithPreferences() {
        let shortcut = GlobalShortcut.saved(for: DefaultsKey.switcherShortcut,
                                            fallback: .switcherDefault)
        let windowShortcut = GlobalShortcut.saved(for: DefaultsKey.switcherWindowShortcut,
                                                  fallback: .switcherWindowDefault)
        routeLock.withLock {
            routeShortcut = shortcut
            routeWindowShortcut = windowShortcut
        }
        let enabled = AppFeature.switcher.isAvailable
            && UserDefaults.standard.bool(forKey: DefaultsKey.switcherEnabled)
        let canStartSession = enabled && Permissions.shared.accessibility
        routeLock.withLock { routeCanStartSession = canStartSession }
        if canStartSession {
            startObservingKeyboardLayout()
            startObservingWake()
            installTap()
            // Build the panel and its SwiftUI tree now: the first hosting-view
            // render costs hundreds of milliseconds, far too slow to pay on
            // the first ⌘Tab.
            let panel = ensurePanel()
            panel.contentViewController?.view.layoutSubtreeIfNeeded()
            if !capturesPreviews {
                WindowPreviewProvider.shared.stopWarming()
            } else {
                WindowPreviewProvider.shared.startWarming()
            }
        } else {
            stopObservingKeyboardLayout()
            stopObservingWake()
            removeTap()
            WindowPreviewProvider.shared.stopWarming()
        }
    }

    /// Force-stops the tap regardless of the preference. Used before the app
    /// resets its own permissions, so a revoked Accessibility grant can never
    /// leave a live tap behind.
    func suspend() {
        stopObservingWake()
        routeLock.withLock { routeCanStartSession = false }
        removeTap()
    }

    /// While a shortcut field is listening, every key has to reach it, even
    /// the switcher's own combination. This is a flag the routing reads, not a
    /// teardown: tearing the tap down and rebuilding it per recording would
    /// churn the window server's keyboard path for no reason (issue #275).
    /// Main thread only, like every other write to the routing state.
    func setCapturingShortcut(_ capturing: Bool) {
        if capturing, sessionActive { cancelSession() }
        routeLock.withLock {
            routeCapturing = capturing
            if capturing {
                routePendingSessionStart = nil
            }
        }
    }

    // MARK: - Event tap

    private func startObservingKeyboardLayout() {
        GlobalShortcut.refreshLayoutLabels()
        guard keyboardLayoutObserver == nil else { return }
        keyboardLayoutObserver = DistributedNotificationCenter.default().addObserver(
            forName: NSNotification.Name(kTISNotifySelectedKeyboardInputSourceChanged as String),
            object: nil,
            queue: .main
        ) { _ in GlobalShortcut.refreshLayoutLabels() }
    }

    private func stopObservingKeyboardLayout() {
        if let keyboardLayoutObserver {
            DistributedNotificationCenter.default().removeObserver(keyboardLayoutObserver)
        }
        keyboardLayoutObserver = nil
    }

    private func startObservingWake() {
        guard wakeObserver == nil else { return }
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in self?.recoverTapAfterWake() }
    }

    private func stopObservingWake() {
        if let wakeObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(wakeObserver)
        }
        wakeObserver = nil
        wakeRetry?.cancel()
        wakeRetry = nil
    }

    private func recoverTapAfterWake() {
        recoverTapIfNeeded()
        wakeRetry?.cancel()
        // Input services can settle after the workspace wake itself. Recheck
        // once so a tap disabled during that window never stays silent.
        let retry = DispatchWorkItem { [weak self] in self?.recoverTapIfNeeded() }
        wakeRetry = retry
        DispatchQueue.main.asyncAfter(deadline: .now() + 3, execute: retry)
    }

    private func recoverTapIfNeeded() {
        guard AppFeature.switcher.isAvailable,
              UserDefaults.standard.bool(forKey: DefaultsKey.switcherEnabled),
              Permissions.shared.accessibility else { return }
        let needsRecovery = lifecycleLock.withLock {
            guard !shouldStopTapThread else { return false }
            guard let tap else { return true }
            return !CFMachPortIsValid(tap) || !CGEvent.tapIsEnabled(tap: tap)
        }
        guard needsRecovery else { return }
        removeTap()
        installTap()
    }

    private func installTap() {
        // Thread creation and the tapThread assignment share one critical
        // section with the decision, so a concurrent stop can never observe
        // a committed start without its thread.
        let thread = lifecycleLock.withLock { () -> Thread? in
            if tapThread != nil {
                if shouldStopTapThread { pendingStartAfterStop = true }
                return nil
            }
            shouldStopTapThread = false
            pendingStartAfterStop = false
            let thread = Thread { [weak self] in
                self?.runEventTap()
            }
            thread.name = "Vorssaint Switcher"
            thread.qualityOfService = .userInteractive
            tapThread = thread
            return thread
        }
        thread?.start()
    }

    private func removeTap() {
        if sessionActive { cancelSession() }
        routeLock.withLock { routePendingSessionStart = nil }
        let snapshot = lifecycleLock.withLock {
            () -> (runLoop: CFRunLoop?, tap: CFMachPort?, threadExists: Bool) in
            shouldStopTapThread = true
            pendingStartAfterStop = false
            return (tapRunLoop, tap, tapThread != nil)
        }
        if let tap = snapshot.tap {
            CGEvent.tapEnable(tap: tap, enable: false)
        }
        if let runLoop = snapshot.runLoop {
            CFRunLoopPerformBlock(runLoop, CFRunLoopMode.commonModes.rawValue) {
                CFRunLoopStop(runLoop)
            }
            CFRunLoopWakeUp(runLoop)
        } else if !snapshot.threadExists {
            lifecycleLock.withLock {
                shouldStopTapThread = false
                tapThread = nil
            }
        }
    }

    private func runEventTap() {
        autoreleasepool {
            let runLoop = CFRunLoopGetCurrent()
            lifecycleLock.withLock { tapRunLoop = runLoop }

            let shouldStopBeforeCreatingTap = lifecycleLock.withLock { shouldStopTapThread }
            guard !shouldStopBeforeCreatingTap else {
                if clearEventTapThread() { installTap() }
                return
            }

            let mask = CGEventMask(1 << CGEventType.keyDown.rawValue)
                | CGEventMask(1 << CGEventType.flagsChanged.rawValue)
                | CGEventMask(1 << CGEventType.leftMouseDown.rawValue)
                | CGEventMask(1 << CGEventType.rightMouseDown.rawValue)
                | CGEventMask(1 << CGEventType.otherMouseDown.rawValue)
                | CGEventMask(1 << CGEventType.otherMouseUp.rawValue)
            guard let tap = CGEvent.tapCreate(
                tap: .cgSessionEventTap,
                place: .headInsertEventTap,
                options: .defaultTap,
                eventsOfInterest: mask,
                callback: { _, type, event, userInfo in
                    guard let userInfo else { return Unmanaged.passUnretained(event) }
                    let switcher = Unmanaged<AppSwitcher>.fromOpaque(userInfo).takeUnretainedValue()
                    return switcher.route(type: type, event: event)
                },
                userInfo: Unmanaged.passUnretained(self).toOpaque()
            ) else {
                _ = clearEventTapThread()
                return
            }

            let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
            lifecycleLock.withLock {
                self.tap = tap
                runLoopSource = source
            }
            CFRunLoopAddSource(runLoop, source, .commonModes)
            CGEvent.tapEnable(tap: tap, enable: true)

            let shouldStop = lifecycleLock.withLock { shouldStopTapThread }
            if shouldStop {
                CGEvent.tapEnable(tap: tap, enable: false)
            } else {
                CFRunLoopRun()
            }

            CGEvent.tapEnable(tap: tap, enable: false)
            CFRunLoopRemoveSource(runLoop, source, .commonModes)
            if clearEventTapThread() { installTap() }
        }
    }

    private func clearEventTapThread() -> Bool {
        lifecycleLock.withLock {
            let shouldRestart = pendingStartAfterStop
            tap = nil
            runLoopSource = nil
            tapRunLoop = nil
            tapThread = nil
            shouldStopTapThread = false
            pendingStartAfterStop = false
            return shouldRestart
        }
    }

    /// Runs on the tap thread. The window server holds every keystroke in
    /// the login session until this returns, so the common case — no session
    /// open, key is not the shortcut — must stay pure math and never wait on
    /// the main thread. Only events the switcher may actually consume hop to
    /// the main thread, and those are rare by definition: one shortcut press,
    /// then the handful of keys typed while the panel is up.
    private func route(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            // Never resurrect a tap that removeTap is already tearing down.
            let currentTap = lifecycleLock.withLock { shouldStopTapThread ? nil : tap }
            if let currentTap { CGEvent.tapEnable(tap: currentTap, enable: true) }
            routeLock.withLock { routePendingSessionStart = nil }
            DispatchQueue.main.async { [weak self] in
                guard let self, self.sessionActive else { return }
                self.cancelSession()
            }
            return Unmanaged.passUnretained(event)
        }

        let (active, shortcut, windowShortcut, capturing, canStartSession, hasPendingStart) = routeLock.withLock {
            (routeSessionActive, routeShortcut, routeWindowShortcut, routeCapturing,
             routeCanStartSession, routePendingSessionStart != nil)
        }
        // A shortcut field in Settings has the keyboard: hand every key
        // straight through so the user can record this feature's own
        // combination instead of opening the switcher with it.
        if capturing { return Unmanaged.passUnretained(event) }
        if !active {
            guard canStartSession else { return Unmanaged.passUnretained(event) }
            if type == .flagsChanged {
                let stillInactive = routeLock.withLock { () -> Bool in
                    guard !routeSessionActive else { return false }
                    if var pending = routePendingSessionStart,
                       !pending.shortcut.requiredModifiersHeld(in: event.flags) {
                        // A quick flick still commits once enumeration finishes,
                        // but can never flash a panel after the key was released.
                        pending.commitWhenReady = true
                        routePendingSessionStart = pending
                    }
                    return true
                }
                if stillInactive { return Unmanaged.passUnretained(event) }
                var verdict: Unmanaged<CGEvent>?
                DispatchQueue.main.sync {
                    verdict = self.handle(type: type, event: event)
                }
                return verdict
            }
            if type == .leftMouseDown || type == .rightMouseDown || type == .otherMouseDown || type == .otherMouseUp {
                let stillInactive = routeLock.withLock { () -> Bool in
                    guard !routeSessionActive else { return false }
                    routePendingSessionStart = nil
                    return true
                }
                if stillInactive { return Unmanaged.passUnretained(event) }
                var verdict: Unmanaged<CGEvent>?
                DispatchQueue.main.sync {
                    verdict = self.handle(type: type, event: event)
                }
                return verdict
            }
            guard type == .keyDown else { return Unmanaged.passUnretained(event) }
            let matchesApps = shortcut.matches(event: event, allowingExtraShift: true)
            let matchesWindows = !matchesApps
                && (windowShortcut.matches(event: event, allowingExtraShift: true)
                    || windowShortcut.matchesByCharacter(event: event))
            let matchesShortcut = matchesApps || matchesWindows
            guard matchesShortcut || hasPendingStart else {
                return Unmanaged.passUnretained(event)
            }
            let pendingKeyDecision = routeLock.withLock { () -> SwitcherPendingKeyDecision in
                let decision = SwitcherSupport.pendingKeyDecision(
                    sessionIsActive: routeSessionActive,
                    hasPendingStart: routePendingSessionStart != nil,
                    commitWhenReady: routePendingSessionStart?.commitWhenReady ?? false,
                    matchesShortcut: matchesShortcut
                )
                if decision == .cancelAndSwallow {
                    routePendingSessionStart = nil
                }
                return decision
            }
            switch pendingKeyDecision {
            case .swallow, .cancelAndSwallow:
                return nil
            case .handleActiveSession:
                break
            case .routeShortcut:
                guard matchesShortcut else { return Unmanaged.passUnretained(event) }

                let requestedShortcut = matchesWindows ? windowShortcut : shortcut
                let requestedScope: SwitcherSessionScope = matchesWindows ? .frontmostApp : .allApps
                let reversed: Bool
                if matchesWindows {
                    let positional = windowShortcut.matches(event: event, allowingExtraShift: true)
                    reversed = SwitcherSupport.windowNavigationDelta(
                        positionalMatch: positional,
                        shiftIsNavigationModifier: windowShortcut.shiftIsNavigationModifier,
                        shiftHeld: event.flags.contains(.maskShift)
                    ) < 0
                } else {
                    reversed = shortcut.shiftIsNavigationModifier && event.flags.contains(.maskShift)
                }

                var generationToSchedule: UInt64?
                let claimedWhileInactive = routeLock.withLock { () -> Bool in
                    guard !routeSessionActive else { return false }
                    if var pending = routePendingSessionStart {
                        if pending.commitWhenReady {
                            sessionStartGeneration &+= 1
                            let generation = sessionStartGeneration
                            routePendingSessionStart = SwitcherPendingSessionStart(
                                generation: generation,
                                shortcut: requestedShortcut,
                                scope: requestedScope,
                                reversed: reversed
                            )
                            generationToSchedule = generation
                            return true
                        }
                        if pending.scope == requestedScope {
                            let next = pending.additionalNavigation + (reversed ? -1 : 1)
                            pending.additionalNavigation = max(-64, min(64, next))
                            routePendingSessionStart = pending
                        }
                        return true
                    }
                    sessionStartGeneration &+= 1
                    let generation = sessionStartGeneration
                    routePendingSessionStart = SwitcherPendingSessionStart(
                        generation: generation,
                        shortcut: requestedShortcut,
                        scope: requestedScope,
                        reversed: reversed
                    )
                    generationToSchedule = generation
                    return true
                }
                if claimedWhileInactive {
                    if let generationToSchedule {
                        // The active tap returns before the main queue performs
                        // any TCC, window-server or Accessibility work.
                        DispatchQueue.main.async { [weak self] in
                            self?.beginPendingSession(generation: generationToSchedule)
                        }
                    }
                    return nil
                }
            }
        }

        var verdict: Unmanaged<CGEvent>?
        DispatchQueue.main.sync {
            verdict = self.handle(type: type, event: event)
        }
        return verdict
    }

    /// Main-thread side of the tap; reached only for events `route` decided
    /// the switcher may care about.
    private func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        // With Accessibility revoked the AX lookups behind a session would hang
        // and freeze input; pass events through and drop any session that was
        // open. Cached flag: a live TCC round-trip is too heavy per key.
        guard Permissions.shared.accessibility else {
            if sessionActive { cancelSession() }
            return Unmanaged.passUnretained(event)
        }

        switch type {
        case .keyDown:
            return handleKeyDown(event)
        case .flagsChanged:
            if sessionActive, !isSearchPinned {
                if let shortcut = sessionShortcut,
                   !shortcut.requiredModifiersHeld(in: event.flags) {
                    commitSession()
                } else if handleShiftBackNavigation(flags: event.flags) {
                    return nil
                }
            }
            return Unmanaged.passUnretained(event)
        case .leftMouseDown, .rightMouseDown, .otherMouseDown:
            if type == .otherMouseDown,
               let panel,
               SwitcherSupport.isMiddleClickInsidePanel(
                   eventType: type,
                   buttonNumber: event.getIntegerValueField(.mouseEventButtonNumber),
                   panelIsVisible: panel.isVisible,
                   panelFrame: panel.frame,
                   location: NSEvent.mouseLocation
               ) {
                closeSelectedWindow()
                return nil
            }
            dismissForClickOutsidePanel()
            return Unmanaged.passUnretained(event)
        case .otherMouseUp:
            if let panel,
               SwitcherSupport.shouldSwallowMiddleMouseUp(
                   eventType: type,
                   buttonNumber: event.getIntegerValueField(.mouseEventButtonNumber),
                   panelIsVisible: panel.isVisible,
                   panelFrame: panel.frame,
                   location: NSEvent.mouseLocation
               ) {
                return nil
            }
            return Unmanaged.passUnretained(event)
        default:
            return Unmanaged.passUnretained(event)
        }
    }

    private func handleKeyDown(_ event: CGEvent) -> Unmanaged<CGEvent>? {
        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
        let flags = event.flags

        // Initial presses are claimed directly on the tap thread and queued
        // asynchronously. Reaching main after that session ended is only a
        // race with teardown; the already-claimed key must stay swallowed.
        guard sessionActive else { return nil }

        let (appsShortcut, windowShortcut) = routeLock.withLock {
            (routeShortcut, routeWindowShortcut)
        }
        let shortcut = sessionShortcut ?? appsShortcut
        switch keyCode {
        case _ where keyCode == shortcut.keyCode && shortcut.matches(event: event, allowingExtraShift: true):
            if shortcut.shiftIsNavigationModifier, flags.contains(.maskShift), shiftBackNavigationHeld {
                break
            }
            let delta = shortcut.shiftIsNavigationModifier && flags.contains(.maskShift) ? -1 : 1
            // Holding the key stops at the list's end instead of wrapping, like
            // the system switcher; a fresh press wraps around (issue #187).
            let isRepeat = event.getIntegerValueField(.keyboardEventAutorepeat) != 0
            advanceSelection(by: delta, wrapping: !isRepeat)
        case _ where sessionScope == .frontmostApp
            && keyCode == appsShortcut.keyCode
            && appsShortcut.matches(event: event,
                                    allowingExtraShift: true,
                                    tolerating: shortcut.modifiers):
            // A window-scoped session keeps its list when the Apps shortcut is
            // pressed with overlapping modifiers instead of expanding to all apps.
            if appsShortcut.shiftIsNavigationModifier, flags.contains(.maskShift), shiftBackNavigationHeld {
                break
            }
            let delta = appsShortcut.shiftIsNavigationModifier && flags.contains(.maskShift) ? -1 : 1
            let isRepeat = event.getIntegerValueField(.keyboardEventAutorepeat) != 0
            advanceSelection(by: delta, wrapping: !isRepeat)
        case _ where searchQuery.isEmpty
            && (windowShortcut.matches(event: event, allowingExtraShift: true,
                                       tolerating: shortcut.modifiers)
                || windowShortcut.matchesByCharacter(event: event,
                                                     tolerating: shortcut.modifiers)):
            // Jumps between the selected app's windows. In the icon row mode
            // that is the grouped app; in the plain grid it hops across the
            // same app's thumbnails, so the key works in both looks. The
            // session shortcut's modifiers are necessarily held while the
            // panel is up, so they never disqualify the window key (a window
            // shortcut like ⌥Tab works during a ⌘Tab session). Matching by
            // character too keeps the default ⌘` on the key that actually
            // types ` on ABNT2, German and other non-US layouts (#187). Shift
            // only means "backward" on a positional match: on a character
            // match it may be part of typing the character itself.
            let positional = windowShortcut.matches(event: event, allowingExtraShift: true,
                                                    tolerating: shortcut.modifiers)
            let delta = SwitcherSupport.windowNavigationDelta(
                positionalMatch: positional,
                shiftIsNavigationModifier: windowShortcut.shiftIsNavigationModifier,
                shiftHeld: flags.contains(.maskShift)
            )
            if sessionScope == .frontmostApp {
                let isRepeat = event.getIntegerValueField(.keyboardEventAutorepeat) != 0
                advanceSelection(by: delta, wrapping: !isRepeat)
            } else {
                advanceWindowInSelectedApp(by: delta)
            }
        case KeyCode.rightArrow:
            advanceSelection(by: 1)
        case KeyCode.leftArrow:
            advanceSelection(by: -1)
        case KeyCode.downArrow:
            moveSelection(by: grid.columns)
        case KeyCode.upArrow:
            moveSelection(by: -grid.columns)
        case KeyCode.delete:
            removeLastSearchCharacter()
        case KeyCode.escape:
            cancelSession()
        case KeyCode.enter:
            commitSession()
        default:
            let text = printableSearchText(from: event)
            // The first letter typed is a command: W closes the highlighted
            // window, Q quits its app, S pins the search field open so typing
            // no longer needs the session's modifier held. Once a search is
            // under way (or already pinned) every key belongs to the query,
            // so all three letters can still be typed.
            if searchQuery.isEmpty, !isSearchPinned,
               let action = SwitcherSupport.letterAction(typedCharacter: text, keyCode: keyCode, pinSearchEnabled: searchPinEnabled) {
                // One window per press: holding the key down must never walk
                // through the list closing or quitting everything on the way.
                if event.getIntegerValueField(.keyboardEventAutorepeat) == 0 {
                    switch action {
                    case .closeWindow: closeSelectedWindow()
                    case .quitApp: quitSelectedApp()
                    case .pinSearch: isSearchPinned = true
                    }
                }
            } else if let text {
                appendSearchText(text)
            }
            // Swallow stray keys so they never leak into the focused app.
        }
        return nil
    }

    // MARK: - Session lifecycle

    /// Runs only after the tap callback has returned. Window enumeration may
    /// wait on bounded AX calls, while modifier-up turns the pending result
    /// into a no-panel commit without waiting for this work to finish.
    private func beginPendingSession(generation: UInt64) {
        guard routeLock.withLock({
            SwitcherSupport.isCurrentSessionStart(
                generation: generation,
                pendingGeneration: routePendingSessionStart?.generation
            )
        }) else { return }
        guard Permissions.shared.accessibility,
              AXIsProcessTrusted(),
              lifecycleLock.withLock({ tap != nil && !shouldStopTapThread }),
              let reportedFrontPID = NSWorkspace.shared.frontmostApplication?.processIdentifier
        else {
            discardPendingSessionStart(generation: generation)
            return
        }

        guard let requested = routeLock.withLock({ () -> SwitcherPendingSessionStart? in
            guard SwitcherSupport.isCurrentSessionStart(
                generation: generation,
                pendingGeneration: routePendingSessionStart?.generation
            ) else { return nil }
            return routePendingSessionStart
        }) else { return }
        let allApps = requested.scope == .allApps
        let mergeWindowsByApp = UserDefaults.standard.bool(forKey: DefaultsKey.switcherMergeTabs)
        let allWindows = WindowEnumerator.listWindows(
            groupByApp: allApps && mergeWindowsByApp,
            preservingGroupedWindows: SwitcherSupport.preservesGroupedWindowsDuringEnumeration(
                allApps: allApps,
                mergeWindowsByApp: mergeWindowsByApp,
                simpleMode: simpleModeEnabled
            )
        )
        let windows: [SwitcherItem]
        switch requested.scope {
        case .allApps:
            guard !allWindows.isEmpty else {
                discardPendingSessionStart(generation: generation)
                return
            }
            windows = allWindows
        case .frontmostApp:
            let scoped = SwitcherSupport.frontmostAppWindows(allItems: allWindows,
                                                             frontmostPID: reportedFrontPID)
            guard !scoped.isEmpty else {
                discardPendingSessionStart(generation: generation)
                return
            }
            windows = scoped
        }
        let focusedSourceWindowID = focusedWindowID(for: reportedFrontPID)
        // The foreground window is what a session is measured against, and it
        // does not always exist: an app left with no windows, or with all of
        // them minimized or on another Space, still owns the keyboard. The
        // switcher opens either way. Bailing out here handed ⌘Tab back to the
        // system, so the shortcut looked dead until it was pressed a second
        // time (issue #324).
        let source = SwitcherSupport.sessionSourceItem(frontmostPID: reportedFrontPID,
                                                       focusedWindowID: focusedSourceWindowID,
                                                       items: windows)

        let list = orderedForSession(windows, currentID: source?.id)
        guard let pending = routeLock.withLock({ () -> SwitcherPendingSessionStart? in
            guard SwitcherSupport.isCurrentSessionStart(
                generation: generation,
                pendingGeneration: routePendingSessionStart?.generation
            ) else { return nil }
            let pending = routePendingSessionStart
            routePendingSessionStart = nil
            routeSessionActive = true
            return pending
        }) else { return }
        sessionItems = list
        totalWindowCount = list.count
        searchQuery = ""
        isSearchPinned = false
        self.windows = list
        sessionSourceContext = source.map { source in
            SwitcherSourceContext(itemID: source.id,
                                  pid: source.pid,
                                  windowID: source.windowID,
                                  windowOwnerPID: source.windowOwnerPID,
                                  isFullscreen: source.isFullscreen)
        }
        sessionStartWindowID = source?.windowID
        recomputeLayouts(for: list)
        if !capturesPreviews {
            previews = [:]
        } else {
            previews = Dictionary(uniqueKeysWithValues: list.compactMap { item in
                item.previewWindowID.flatMap { id in
                    WindowPreviewProvider.shared.cachedPreview(for: id).map { (id, $0) }
                }
            })
        }
        userNavigated = false
        // Index 0 is the on-screen window; index 1 is the most-recently-used
        // other window — the toggle target, which may be another window of the
        // same app. Shift starts from the far end. With no on-screen window
        // the session opens on the first entry from another app.
        selectedIndex = pending.scope == .frontmostApp
            ? SwitcherSupport.initialWindowScopedSelectionIndex(itemCount: list.count,
                                                                hasForegroundItem: source != nil,
                                                                reversed: pending.reversed)
            : initialSelectionIndex(in: list,
                                    reversed: pending.reversed,
                                    hasForegroundItem: source != nil,
                                    frontmostPID: SwitcherSupport.appPID(forFrontmost: reportedFrontPID,
                                                                         items: list))
        sessionShortcut = pending.shortcut
        sessionScope = pending.scope
        shiftBackNavigationHeld = pending.reversed && pending.shortcut.shiftIsNavigationModifier

        if pending.additionalNavigation != 0 {
            let delta = pending.additionalNavigation < 0 ? -1 : 1
            for _ in 0..<abs(pending.additionalNavigation) {
                advanceSelection(by: delta)
            }
        }

        if pending.commitWhenReady {
            commitSession()
        } else if capturesPreviews {
            WindowPreviewProvider.shared.refreshPreviews(for: list, maxPixelSize: 640 * PreviewSizing.scale) { [weak self] windowID, image in
                guard let self,
                      self.sessionActive,
                      self.sessionItems.contains(where: { $0.previewWindowID == windowID }) else { return }
                self.previews[windowID] = image
            }
        }
        if !pending.commitWhenReady {
            scheduleShowPanel()
        }
    }

    private func discardPendingSessionStart(generation: UInt64) {
        routeLock.withLock {
            guard SwitcherSupport.isCurrentSessionStart(
                generation: generation,
                pendingGeneration: routePendingSessionStart?.generation
            ) else { return }
            routePendingSessionStart = nil
        }
    }

    private func handleShiftBackNavigation(flags: CGEventFlags) -> Bool {
        let shiftHeld = flags.contains(.maskShift)
        defer { shiftBackNavigationHeld = shiftHeld }
        guard let shortcut = sessionShortcut,
              SwitcherSupport.shouldNavigateBackwardOnShiftPress(shiftIsNavigationModifier: shortcut.shiftIsNavigationModifier,
                                                                  wasShiftHeld: shiftBackNavigationHeld,
                                                                  isShiftHeld: shiftHeld)
        else { return false }
        advanceSelection(by: -1)
        return true
    }

    /// Puts the window the user is looking at first. The enumerator already
    /// ordered everything else by how recently it was used, so the entry right
    /// after the current one is the window they came from — this only has to
    /// make sure the current one leads, even in the moment right after a
    /// switch, when the window server has not caught up yet.
    private func orderedForSession(_ items: [SwitcherItem], currentID: String?) -> [SwitcherItem] {
        guard let currentID, let index = items.firstIndex(where: { $0.id == currentID }) else { return items }
        var ordered = items
        ordered.insert(ordered.remove(at: index), at: 0)
        return ordered
    }

    private func initialSelectionIndex(in items: [SwitcherItem],
                                       reversed: Bool,
                                       hasForegroundItem: Bool,
                                       frontmostPID: pid_t) -> Int {
        guard !items.isEmpty else { return 0 }
        guard SwitcherSupport.usesAppGroupsForMainShortcut(
            iconRowLayout: usesIconRowLayout,
            windowRow: usesWindowRow
        ) else {
            return SwitcherSupport.initialSelectionPosition(pids: items.map(\.pid),
                                                            hasForegroundEntry: hasForegroundItem,
                                                            frontmostPID: frontmostPID,
                                                            reversed: reversed)
        }

        // The icon row steps app by app, so the same rule runs over the groups
        // and lands on the chosen group's representative window.
        let groups = SwitcherSupport.appGroups(items: items)
        guard !groups.isEmpty else { return 0 }
        let groupIndex = SwitcherSupport.initialSelectionPosition(pids: groups.map(\.pid),
                                                                  hasForegroundEntry: hasForegroundItem,
                                                                  frontmostPID: frontmostPID,
                                                                  reversed: reversed)
        return groups[groupIndex].representativeIndex
    }

    private func focusedWindowID(for pid: pid_t) -> CGWindowID? {
        guard Permissions.shared.accessibility else { return nil }
        let app = AXUIElementCreateApplication(pid)
        // The tap thread waits on the session start, so a hung frontmost app
        // must not hold the keyboard hostage for the 6s default AX timeout.
        AXUIElementSetMessagingTimeout(app, 0.35)
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(app, kAXFocusedWindowAttribute as CFString, &value) == .success,
              let value,
              CFGetTypeID(value) == AXUIElementGetTypeID()
        else { return nil }
        let window = value as! AXUIElement
        return AXWindowResolver.windowID(for: window)
    }

    /// Records a switch straight away instead of waiting for the window server
    /// and Accessibility to report it: a flick of the shortcut is faster than
    /// either, and it is exactly the moment the toggle has to be right.
    private func recordUse(_ activated: SwitcherItem, previous: CGWindowID?) {
        WindowUseTracker.shared.recordSwitch(to: activated.windowID, from: previous)
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

    /// Icon-row hover. Selects the tile, then only the last visible overflow
    /// icon may start the one-by-one slide.
    func hoverSelectIconRow(index: Int) {
        hoverSelect(index: index)
        guard hoverAnchor == nil else { return }
        beginIconRowEdgeHoverIfNeeded(at: index)
    }

    func hoverSelectIconRowEnded(index: Int) {
        guard iconRowEdgeHoverIndex == iconRowIndex(forSelectionIndex: index) else { return }
        cancelIconRowEdgeHover()
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
              !closingItemIDs.contains(item.id),
              let windowID = item.windowID
        else { return }

        closingItemIDs.insert(item.id)
        WindowActivator.closeWindowIncludingHiddenState(item) { [weak self] didClose in
            guard let self else { return }
            guard didClose else {
                self.closingItemIDs.remove(item.id)
                self.resumePendingCommitAfterClose()
                return
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) { [weak self] in
                self?.finishClosingWindow(itemID: item.id,
                                          windowID: windowID,
                                          pid: item.pid,
                                          attempt: 0)
            }
        }
    }

    private func advanceSelection(by delta: Int, wrapping: Bool = true) {
        cancelIconRowEdgeHover()
        guard !windows.isEmpty else { return }
        if SwitcherSupport.usesAppGroupsForMainShortcut(
            iconRowLayout: usesIconRowLayout,
            windowRow: usesWindowRow
        ), sessionScope == .allApps {
            advanceAppSelection(by: delta, wrapping: wrapping)
            return
        }
        userNavigated = true
        let next = selectedIndex + delta
        if !wrapping, !windows.indices.contains(next) { return }
        selectedIndex = (next + windows.count) % windows.count
    }

    private func advanceAppSelection(by delta: Int, wrapping: Bool = true) {
        cancelIconRowEdgeHover()
        userNavigated = true
        selectedIndex = SwitcherSupport.nextAppSelectionIndex(items: windows,
                                                              selectedIndex: selectedIndex,
                                                              delta: delta,
                                                              wrapping: wrapping)
    }

    private func advanceWindowInSelectedApp(by delta: Int) {
        userNavigated = true
        selectedIndex = SwitcherSupport.nextWindowSelectionIndexWithinApp(items: windows,
                                                                          selectedIndex: selectedIndex,
                                                                          delta: delta)
    }

    /// Closes the highlighted window (⌘Tab → W) and keeps the session open, so
    /// the app stays running and the panel moves on to the next window. Same
    /// path as the card's close button.
    private func closeSelectedWindow() {
        guard windows.indices.contains(selectedIndex) else { return }
        closeWindow(windows[selectedIndex])
    }

    /// Quits the app owning the selected window (⌘Tab → Q), removes its windows
    /// from the grid and keeps the session open — mirroring the system switcher.
    private func quitSelectedApp() {
        guard windows.indices.contains(selectedIndex) else { return }
        let pid = windows[selectedIndex].pid
        guard let app = NSRunningApplication(processIdentifier: pid),
              app.bundleIdentifier != Defaults.finderBundleIdentifier else { return }
        app.terminate()

        let removedIDs = Set(sessionItems.lazy.filter { $0.pid == pid }.map(\.id))
        closingItemIDs.subtract(removedIDs)
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
            resumePendingCommitAfterClose()
            return
        }
        selectedIndex = min(max(0, selectedIndex - removedBeforeSelection), windows.count - 1)
        recomputeLayouts(for: windows)
        resizePanel()
        resumePendingCommitAfterClose()
    }

    private func finishClosingWindow(itemID: String, windowID: CGWindowID, pid: pid_t, attempt: Int) {
        guard sessionActive else { return }
        guard sessionItems.contains(where: { $0.id == itemID }) else {
            finishTrackingClose(itemID: itemID)
            return
        }

        let refreshed = WindowEnumerator.listWindows(for: pid, maximumCount: 64)
        guard !refreshed.contains(where: { $0.windowID == windowID }) else {
            // Still there after the retries: the app kept it, so it is a
            // normal entry again and the release may raise it.
            guard attempt < 2 else {
                closingItemIDs.remove(itemID)
                resumePendingCommitAfterClose()
                return
            }
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
        guard state.didRemove else {
            sessionItems.removeAll { $0.id == itemID }
            totalWindowCount = sessionItems.count
            previews.removeValue(forKey: windowID)
            closingItemIDs.remove(itemID)
            if sessionSourceContext?.itemID == itemID {
                sessionStartWindowID = nil
            }
            guard !sessionItems.isEmpty else {
                endSession()
                return
            }
            applySearchFilter(preferredItemID: selectedItemID)
            resumePendingCommitAfterClose()
            return
        }

        sessionItems.removeAll { $0.id == itemID }
        totalWindowCount = sessionItems.count
        let remaining = Set(state.remainingItemIDs)
        windows = windows.filter { remaining.contains($0.id) }
        let remainingPreviews = Set(windows.compactMap(\.previewWindowID))
        previews = previews.filter { remainingPreviews.contains($0.key) && $0.key != windowID }
        closingItemIDs.remove(itemID)
        if sessionSourceContext?.itemID == itemID {
            sessionStartWindowID = nil
        }

        guard !state.shouldEndSession else {
            if sessionItems.isEmpty || searchQuery.isEmpty {
                endSession()
            } else {
                selectedIndex = 0
                recomputeLayouts(for: windows)
                resizePanel()
                resumePendingCommitAfterClose()
            }
            return
        }

        selectedIndex = state.selectedIndex
        recomputeLayouts(for: windows)
        resizePanel()
        resumePendingCommitAfterClose()
    }

    private func finishTrackingClose(itemID: String) {
        closingItemIDs.remove(itemID)
        resumePendingCommitAfterClose()
    }

    /// Row jump (↑/↓): moves without wrapping so the selection stays put at
    /// the grid edges.
    private func moveSelection(by delta: Int) {
        if usesIconRowLayout {
            advanceWindowInSelectedApp(by: delta < 0 ? -1 : 1)
            return
        }
        guard delta != 0 else { return }
        let target = SwitcherSupport.gridSelectionIndex(after: selectedIndex,
                                                        itemCount: windows.count,
                                                        columns: grid.columns,
                                                        movingDown: delta > 0)
        guard target != selectedIndex else { return }
        userNavigated = true
        selectedIndex = target
    }

    /// Activates the current selection. Also used by the panel on click.
    func commitSession() {
        guard sessionActive else { return }
        guard closingItemIDs.isEmpty else {
            commitPendingForClose = true
            return
        }
        // A window that was just closed is still listed for a moment; letting
        // go right after must land on what takes its place, never on it.
        let selection = SwitcherSupport.commitTargetID(itemIDs: windows.map(\.id),
                                                       selectedIndex: selectedIndex,
                                                       closingItemIDs: closingItemIDs)
            .flatMap { id in windows.first { $0.id == id } }
        let source = sessionSourceContext
        let previousWindowID = sessionStartWindowID
        endSession()
        if let selection {
            recordUse(selection, previous: previousWindowID)
            WindowActivator.activate(selection,
                                     sourceWasFullscreen: source?.isFullscreen ?? false,
                                     sourcePID: source?.pid,
                                     sourceWindowID: source?.isFullscreen == true ? nil : source?.windowID,
                                     sourceWindowOwnerPID: source?.windowOwnerPID)
        }
    }

    private func resumePendingCommitAfterClose() {
        guard commitPendingForClose, closingItemIDs.isEmpty, sessionActive else { return }
        commitPendingForClose = false
        commitSession()
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
        isSearchPinned = false
        totalWindowCount = 0
        hoverAnchor = nil
        cancelIconRowEdgeHover()
        iconRowFirstVisibleIndex = 0
        userNavigated = false
        sessionStartWindowID = nil
        sessionSourceContext = nil
        sessionShortcut = nil
        sessionScope = .allApps
        shiftBackNavigationHeld = false
        closingItemIDs = []
        commitPendingForClose = false
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
        panel.hasShadow = !usesIconRowLayout
        hoverAnchor = NSEvent.mouseLocation
        panel.setFrame(centeredFrame(for: currentPanelSize), display: true)
        panel.invalidateShadow()
        let animationBehavior = panel.animationBehavior
        panel.animationBehavior = .none
        panel.orderFrontRegardless()
        panel.animationBehavior = animationBehavior
    }

    /// A click outside cancels before the event continues through the session
    /// tap. This preserves the click and prevents a nearly simultaneous Command
    /// release from committing the highlighted window first (issues #384 and
    /// #539).
    private func dismissForClickOutsidePanel() {
        guard sessionActive, let panel else { return }
        guard SwitcherSupport.shouldDismissForClick(panelIsVisible: panel.isVisible,
                                                    panelFrame: panel.frame,
                                                    location: NSEvent.mouseLocation)
        else { return }
        cancelSession()
    }

    /// Re-fits the panel after the grid changed mid-session (e.g. an app quit
    /// with Q). Animated only when already on screen, so the size change reads
    /// as intentional instead of a flash.
    private func resizePanel() {
        guard let panel else { return }
        let frame = centeredFrame(for: currentPanelSize)
        panel.hasShadow = !usesIconRowLayout
        panel.setFrame(frame, display: true, animate: panel.isVisible)
        panel.invalidateShadow()
    }

    private var currentPanelSize: CGSize {
        usesIconRowLayout
            ? (simpleModeEnabled
                ? (usesWindowRow ? iconRowLayout.simpleWindowPanelSize : iconRowLayout.simplePanelSize)
                : iconRowLayout.panelSize)
            : grid.panelSize
    }

    private var iconRowModeEnabled: Bool {
        UserDefaults.standard.bool(forKey: DefaultsKey.switcherIconRowMode)
    }

    private var simpleModeEnabled: Bool {
        UserDefaults.standard.bool(forKey: DefaultsKey.switcherSimpleMode)
    }

    private var usesWindowRow: Bool {
        SwitcherSupport.usesWindowRow(
            simpleMode: simpleModeEnabled,
            mergeWindowsByApp: UserDefaults.standard.bool(forKey: DefaultsKey.switcherMergeTabs)
        )
    }

    private var searchPinEnabled: Bool {
        UserDefaults.standard.bool(forKey: DefaultsKey.switcherSearchPinEnabled)
    }

    private var showsShortcutHints: Bool {
        UserDefaults.standard.bool(forKey: DefaultsKey.switcherShowShortcutHints)
    }

    private var usesIconRowLayout: Bool {
        SwitcherSupport.usesIconRowLayout(iconRowMode: iconRowModeEnabled,
                                          simpleMode: simpleModeEnabled)
    }

    private var capturesPreviews: Bool {
        SwitcherSupport.capturesPreviews(simpleMode: simpleModeEnabled)
    }

    private func recomputeLayouts(for items: [SwitcherItem]) {
        guard let screen = NSScreen.withMouse ?? NSScreen.screens.first else { return }
        grid = SwitcherGrid.compute(count: max(items.count, 1), on: screen)
        let appGroups = SwitcherSupport.appGroups(items: items)
        iconRowLayout = SwitcherIconRowLayout.compute(
            appCount: usesWindowRow ? items.count : appGroups.count,
            selectedWindowCount: usesWindowRow ? 1 : selectedAppWindowCount(in: items),
            screenVisibleFrame: screen.visibleFrame,
            showsShortcutHints: showsShortcutHints,
            tileWidth: usesWindowRow ? SwitcherIconRowLayout.windowTileWidth
                                     : SwitcherIconRowLayout.appTileWidth
        )
    }

    private func updateIconRowLayoutForCurrentSelection() {
        guard !windows.isEmpty else { return }
        let appGroups = SwitcherSupport.appGroups(items: windows)
        iconRowLayout = SwitcherIconRowLayout.compute(
            appCount: usesWindowRow ? windows.count : appGroups.count,
            selectedWindowCount: usesWindowRow ? 1 : selectedAppWindowCount(in: windows),
            screenVisibleFrame: NSScreen.pointerVisibleFrame,
            showsShortcutHints: showsShortcutHints,
            tileWidth: usesWindowRow ? SwitcherIconRowLayout.windowTileWidth
                                     : SwitcherIconRowLayout.appTileWidth
        )
        revealSelectedIconInVisibleRow()
    }

    private var iconRowItemCount: Int {
        usesWindowRow ? windows.count : SwitcherSupport.appGroups(items: windows).count
    }

    private func iconRowIndex(forSelectionIndex selectionIndex: Int) -> Int? {
        guard windows.indices.contains(selectionIndex) else { return nil }
        if usesWindowRow { return selectionIndex }
        let groups = SwitcherSupport.appGroups(items: windows)
        return groups.firstIndex { $0.pid == windows[selectionIndex].pid }
    }

    private func selectionIndex(forIconRowIndex iconIndex: Int) -> Int? {
        if usesWindowRow {
            return windows.indices.contains(iconIndex) ? iconIndex : nil
        }
        let groups = SwitcherSupport.appGroups(items: windows)
        return groups.indices.contains(iconIndex) ? groups[iconIndex].representativeIndex : nil
    }

    private func revealSelectedIconInVisibleRow() {
        guard usesIconRowLayout,
              let iconIndex = iconRowIndex(forSelectionIndex: selectedIndex)
        else { return }
        iconRowFirstVisibleIndex = SwitcherSupport.iconRowFirstVisibleIndex(
            revealing: iconIndex,
            itemCount: iconRowItemCount,
            visibleCount: iconRowLayout.visibleIconCount,
            currentFirstVisibleIndex: iconRowFirstVisibleIndex
        )
    }

    private func beginIconRowEdgeHoverIfNeeded(at selectionIndex: Int) {
        guard usesIconRowLayout,
              let iconIndex = iconRowIndex(forSelectionIndex: selectionIndex),
              SwitcherSupport.iconRowEdgeHoverDelta(
                hoveredIndex: iconIndex,
                firstVisibleIndex: iconRowFirstVisibleIndex,
                visibleCount: iconRowLayout.visibleIconCount,
                itemCount: iconRowItemCount
              ) != nil
        else {
            cancelIconRowEdgeHover()
            return
        }
        guard iconRowEdgeHoverIndex != iconIndex else { return }
        cancelIconRowEdgeHover()
        iconRowEdgeHoverIndex = iconIndex
        let work = DispatchWorkItem { [weak self] in
            self?.stepIconRowFromEdgeHover()
        }
        iconRowEdgeHoverWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + SwitcherSupport.iconRowEdgeHoverInterval,
                                      execute: work)
    }

    private func stepIconRowFromEdgeHover() {
        guard sessionActive, usesIconRowLayout,
              let hovered = iconRowEdgeHoverIndex,
              let delta = SwitcherSupport.iconRowEdgeHoverDelta(
                hoveredIndex: hovered,
                firstVisibleIndex: iconRowFirstVisibleIndex,
                visibleCount: iconRowLayout.visibleIconCount,
                itemCount: iconRowItemCount
              )
        else {
            cancelIconRowEdgeHover()
            return
        }

        let nextFirst = SwitcherSupport.clampedIconRowFirstVisibleIndex(
            itemCount: iconRowItemCount,
            visibleCount: iconRowLayout.visibleIconCount,
            firstVisibleIndex: iconRowFirstVisibleIndex + delta
        )
        guard nextFirst != iconRowFirstVisibleIndex else {
            cancelIconRowEdgeHover()
            return
        }

        let nextIcon = SwitcherSupport.iconRowIndexAfterEdgeHoverStep(
            firstVisibleIndex: nextFirst,
            visibleCount: iconRowLayout.visibleIconCount,
            itemCount: iconRowItemCount,
            delta: delta
        )
        // Publish the new hover target first. Sliding the row fires a hover-end
        // on the previous last icon, and that must not cancel this step.
        iconRowEdgeHoverIndex = nextIcon
        iconRowFirstVisibleIndex = nextFirst
        if let nextSelection = selectionIndex(forIconRowIndex: nextIcon) {
            userNavigated = true
            selectedIndex = nextSelection
        }

        let work = DispatchWorkItem { [weak self] in
            self?.stepIconRowFromEdgeHover()
        }
        iconRowEdgeHoverWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + SwitcherSupport.iconRowEdgeHoverRepeatInterval,
                                      execute: work)
    }

    private func cancelIconRowEdgeHover() {
        iconRowEdgeHoverWork?.cancel()
        iconRowEdgeHoverWork = nil
        iconRowEdgeHoverIndex = nil
    }

    private func selectedAppWindowCount(in items: [SwitcherItem]) -> Int {
        guard items.indices.contains(selectedIndex) else { return 1 }
        let pid = items[selectedIndex].pid
        return max(1, items.filter { $0.pid == pid }.count)
    }

    private func centeredFrame(for size: CGSize) -> NSRect {
        let screen = NSScreen.pointerVisibleFrame
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

    // Base sizes and breathing room scale together, so making previews smaller
    // also keeps the panel from spending that saved space on empty gaps.
    static var cardWidth: CGFloat { 288 * PreviewSizing.scale }
    static var cardHeight: CGFloat { 214 * PreviewSizing.scale }
    static var spacing: CGFloat { 12 * PreviewSizing.scale }
    static var padding: CGFloat { 20 * PreviewSizing.scale }

    static let empty = SwitcherGrid(columns: 1, rows: 1, visibleRows: 1, panelSize: .zero)

    static func compute(count: Int, on screen: NSScreen) -> SwitcherGrid {
        let usableWidth = screen.visibleFrame.width * 0.92
        let usableHeight = screen.visibleFrame.height * 0.85

        let maxColumns = max(1, Int((usableWidth - padding * 2 + spacing) / (cardWidth + spacing)))
        let columns = SwitcherSupport.gridColumnCount(itemCount: count, maxColumns: maxColumns)
        let rows = Int(ceil(Double(count) / Double(columns)))

        let maxRows = max(1, Int((usableHeight - padding * 2 + spacing) / (cardHeight + spacing)))
        let visibleRows = min(rows, maxRows)

        let width = CGFloat(columns) * cardWidth + CGFloat(columns - 1) * spacing + padding * 2
        let height = CGFloat(visibleRows) * cardHeight + CGFloat(visibleRows - 1) * spacing + padding * 2
        return SwitcherGrid(columns: columns, rows: rows, visibleRows: visibleRows,
                            panelSize: CGSize(width: width, height: height))
    }
}
