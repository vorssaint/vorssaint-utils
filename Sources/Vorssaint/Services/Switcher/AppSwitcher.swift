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

/// The window switcher: a global event tap takes over the configured shortcut,
/// and while its modifiers are held a non-activating panel cycles through real
/// windows. Releasing commits, W closes the highlighted window, and Q quits
/// its app. When the optional pin-search preference is enabled, S pins the
/// search field open (so typing no longer needs the modifier held). Esc and a
/// click outside cancel. The panel joins every Space and
/// fullscreen app, so the switcher is available wherever the user is.
final class AppSwitcher: ObservableObject {
    static let shared = AppSwitcher()

    @Published private(set) var windows: [SwitcherItem] = []
    @Published private(set) var previews: [CGWindowID: CGImage] = [:]
    @Published private(set) var selectedIndex = 0 {
        didSet {
            guard oldValue != selectedIndex else { return }
            updateIconRowLayoutForCurrentSelection()
            if sessionActive, usesIconRowLayout {
                resizePanel()
            }
        }
    }
    @Published private(set) var grid = SwitcherGrid.empty
    @Published private(set) var iconRowLayout = SwitcherIconRowLayout.empty
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
    private var sessionActive: Bool {
        get { routeLock.withLock { routeOwnership.hasSessionLifecycle } }
    }
    private var panel: NSPanel?
    private var sessionItems: [SwitcherItem] = []
    private var sessionGeneration: UInt64?

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
    private var routeOwnership = SwitcherRouteOwnership()
    private var routeShortcut = GlobalShortcut.switcherDefault
    private var routeWindowShortcut = GlobalShortcut.switcherWindowDefault
    private var routeSearchPinEnabled = false

    /// Enumeration touches every regular app through Accessibility. A cheap
    /// WindowServer fingerprint proves this warmed result still describes the
    /// current desktop before a shortcut is allowed to reuse it.
    private var cachedWindowItems: [SwitcherItem] = []
    private var cachedWindowFingerprint: SwitcherWindowFingerprint?
    private var cachedWindowStoredUptime: TimeInterval?
    private var windowCacheEnabled = false
    private var pendingCacheRefresh: DispatchWorkItem?
    private var cacheRefreshOwnership = SwitcherCacheRefreshOwnership()
    private let cacheRefreshQueue = DispatchQueue(label: "com.vorssaint.switcher-window-cache",
                                                  qos: .userInitiated)
    private let activationProbeQueue = DispatchQueue(label: "com.vorssaint.switcher-activation-probe",
                                                     qos: .userInitiated,
                                                     attributes: .concurrent)
    private var cacheRefreshRetryCount = 0
    private var workspaceTokens: [NSObjectProtocol] = []
    private static let maximumWindowCacheAge: TimeInterval = 2

    /// The panel appears only after this delay, like the system switcher: a
    /// quick ⌘Tab flick switches with no UI at all, which is what makes rapid
    /// toggling feel instant instead of flashing a window.
    private static let appearanceDelay: TimeInterval = 0.1
    private var pendingShow: DispatchWorkItem?
    /// True once the user moved the selection themselves.
    private var userNavigated = false
    /// Mouse position when the panel appeared; hover is inert until it moves.
    private var hoverAnchor: NSPoint?

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
        let searchPinEnabled = UserDefaults.standard.bool(
            forKey: DefaultsKey.switcherSearchPinEnabled
        )
        routeLock.withLock {
            routeShortcut = shortcut
            routeWindowShortcut = windowShortcut
            routeSearchPinEnabled = searchPinEnabled
        }
        let enabled = AppFeature.switcher.isAvailable
            && UserDefaults.standard.bool(forKey: DefaultsKey.switcherEnabled)
        if enabled, Permissions.shared.accessibility {
            startObservingKeyboardLayout()
            startObservingWake()
            installTap()
            // Build the panel and its SwiftUI tree now: the first hosting-view
            // render costs hundreds of milliseconds, far too slow to pay on
            // the first ⌘Tab.
            let panel = ensurePanel()
            panel.contentViewController?.view.layoutSubtreeIfNeeded()
            startWindowCache()
            if !capturesPreviews {
                WindowPreviewProvider.shared.stopWarming()
            } else {
                WindowPreviewProvider.shared.startWarming()
            }
        } else {
            stopObservingKeyboardLayout()
            stopObservingWake()
            removeTap()
            stopWindowCache()
            WindowPreviewProvider.shared.stopWarming()
        }
    }

    /// Force-stops the tap regardless of the preference. Used before the app
    /// resets its own permissions, so a revoked Accessibility grant can never
    /// leave a live tap behind.
    func suspend() {
        stopObservingWake()
        removeTap()
        stopWindowCache()
    }

    /// While a shortcut field is listening, every key has to reach it, even
    /// the switcher's own combination. This is a flag the routing reads, not a
    /// teardown: tearing the tap down and rebuilding it per recording would
    /// churn the window server's keyboard path for no reason (issue #275).
    /// Main thread only, like every other write to the routing state.
    func setCapturingShortcut(_ capturing: Bool) {
        routeLock.withLock { routeOwnership.setCapturing(capturing) }
        if capturing { clearSessionState() }
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
        let snapshot = lifecycleLock.withLock {
            () -> (runLoop: CFRunLoop?, tap: CFMachPort?, threadExists: Bool) in
            shouldStopTapThread = true
            pendingStartAfterStop = false
            routeLock.withLock { routeOwnership.setTapLive(false) }
            return (tapRunLoop, tap, tapThread != nil)
        }
        clearSessionState()
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
            let canRoute = lifecycleLock.withLock { () -> Bool in
                self.tap = tap
                runLoopSource = source
                guard !shouldStopTapThread else { return false }
                routeLock.withLock { routeOwnership.setTapLive(true) }
                return true
            }
            CFRunLoopAddSource(runLoop, source, .commonModes)
            CGEvent.tapEnable(tap: tap, enable: canRoute)

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
            routeLock.withLock { routeOwnership.setTapLive(false) }
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
            routeLock.withLock { routeOwnership.invalidateLifecycle() }
            // Never resurrect a tap that removeTap is already tearing down.
            let currentTap = lifecycleLock.withLock { shouldStopTapThread ? nil : tap }
            if let currentTap { CGEvent.tapEnable(tap: currentTap, enable: true) }
            DispatchQueue.main.async { [weak self] in
                self?.clearSessionState()
            }
            return Unmanaged.passUnretained(event)
        }

        if type == .leftMouseDown || type == .rightMouseDown || type == .otherMouseDown,
           routeLock.withLock({ routeOwnership.invalidateColdPendingRoutesForMouseDown() }) {
            return Unmanaged.passUnretained(event)
        }

        let (shortcut, windowShortcut, routingShortcut, pinSearchEnabled,
             capturing, pendingFlagsConsumed, releasedSession) = routeLock.withLock {
            let pendingFlagsObservation = type == .flagsChanged
                ? routeOwnership.observePendingModifierFlags(event.flags)
                : .none
            let released = type == .flagsChanged
                ? routeOwnership.releaseActiveSession(for: event.flags)
                : nil
            return (routeShortcut, routeWindowShortcut, routeOwnership.routingShortcut,
                    routeSearchPinEnabled, routeOwnership.capturing,
                    pendingFlagsObservation.consumesEvent, released)
        }
        // A shortcut field in Settings has the keyboard: hand every key
        // straight through so the user can record this feature's own
        // combination instead of opening the switcher with it.
        if capturing { return Unmanaged.passUnretained(event) }
        if let releasedSession {
            DispatchQueue.main.async { [weak self] in
                self?.commitReleasedSession(generation: releasedSession)
            }
            return Unmanaged.passUnretained(event)
        }
        if pendingFlagsConsumed { return nil }
        let initialActiveState = routeLock.withLock {
            (routeOwnership.routableActiveToken, routeOwnership.activeTerminalPending)
        }
        if initialActiveState.1, type == .flagsChanged {
            return Unmanaged.passUnretained(event)
        }
        var activeToken = initialActiveState.0
        var routeIsActive = activeToken != nil
        if !routeIsActive {
            guard type == .keyDown else { return Unmanaged.passUnretained(event) }
            let heldModifiers = routingShortcut?.modifiers ?? []
            let matchesApps = shortcut.matches(event: event,
                                                allowingExtraShift: true,
                                                tolerating: heldModifiers)
            let windowPositionalMatch = windowShortcut.matches(event: event,
                                                                allowingExtraShift: true,
                                                                tolerating: heldModifiers)
            let matchesWindows = !matchesApps
                && (windowPositionalMatch
                    || windowShortcut.matchesByCharacter(event: event,
                                                         tolerating: heldModifiers))
            let pendingInput = SwitcherPendingKeyInput(
                keyCode: event.getIntegerValueField(.keyboardEventKeycode),
                text: printableSearchText(from: event),
                isRepeat: event.getIntegerValueField(.keyboardEventAutorepeat) != 0
            )
            if matchesWindows,
               routeLock.withLock({
                   routeOwnership.queuePendingWindowShortcutAsSearch(pendingInput)
               }) {
                return nil
            }
            guard let initialRoute = SwitcherSupport.initialRoute(
                appsShortcut: shortcut,
                windowShortcut: windowShortcut,
                matchesApps: matchesApps,
                matchesWindows: matchesWindows,
                windowPositionalMatch: windowPositionalMatch,
                shiftHeld: event.flags.contains(.maskShift)
            ) else {
                let letterAction = SwitcherSupport.letterAction(
                    typedCharacter: pendingInput.text,
                    keyCode: pendingInput.keyCode,
                    pinSearchEnabled: pinSearchEnabled
                )
                let terminal: SwitcherPendingTerminal?
                switch pendingInput.keyCode {
                case KeyCode.enter: terminal = .commit
                case KeyCode.escape: terminal = .cancel
                default: terminal = nil
                }
                if routeLock.withLock({
                    routeOwnership.queuePendingKeyInput(
                        pendingInput,
                        letterAction: letterAction,
                        deletesSearchCharacter: pendingInput.keyCode == KeyCode.delete,
                        terminal: terminal
                    )
                }) {
                    return nil
                }
                // Session ownership may have changed after the first snapshot.
                // Recheck before deciding that an unrelated key passes through.
                activeToken = routeLock.withLock { routeOwnership.routableActiveToken }
                routeIsActive = activeToken != nil
                if !routeIsActive { return Unmanaged.passUnretained(event) }
                return routeActiveEvent(type: type, event: event,
                                        expectedSessionToken: activeToken)
            }

            let isRepeat = event.getIntegerValueField(.keyboardEventAutorepeat) != 0
            var decision = routeLock.withLock {
                routeOwnership.decideMatchedRoute(initialRoute,
                                                  isRepeat: isRepeat,
                                                  allowingNewRoute: false)
            }
            if decision == .needsAccessibility {
                // Live check at the one point that starts AX work: with the grant
                // revoked, the session lookups would hang and freeze input. The
                // TCC round-trip is an IPC, so it runs once per shortcut press,
                // never once per key.
                guard AXIsProcessTrusted() else { return Unmanaged.passUnretained(event) }
                decision = routeLock.withLock {
                    routeOwnership.decideMatchedRoute(initialRoute,
                                                      isRepeat: isRepeat,
                                                      allowingNewRoute: true)
                }
            }
            switch decision {
            case .activeSession:
                let token = routeLock.withLock { routeOwnership.routableActiveToken }
                return routeActiveEvent(type: type, event: event,
                                        expectedSessionToken: token)
            case let .accepted(token):
                DispatchQueue.main.async { [weak self] in
                    self?.handleAcceptedInitialRoute(token: token)
                }
                return nil
            case .coalesced:
                return nil
            case .needsAccessibility, .rejected:
                return Unmanaged.passUnretained(event)
            }
        }

        return routeActiveEvent(type: type, event: event,
                                expectedSessionToken: activeToken)
    }

    private func routeActiveEvent(type: CGEventType,
                                  event: CGEvent,
                                  expectedSessionToken: UInt64?) -> Unmanaged<CGEvent>? {
        if type == .keyDown,
           event.getIntegerValueField(.keyboardEventKeycode) == KeyCode.enter {
            guard let expectedSessionToken else { return Unmanaged.passUnretained(event) }
            let released = routeLock.withLock {
                routeOwnership.releaseActiveSession(expectedToken: expectedSessionToken)
            }
            if let released {
                DispatchQueue.main.async { [weak self] in
                    self?.commitReleasedSession(generation: released)
                }
            }
            // The tap already observed an owned session. A stale Enter is
            // consumed too, but cannot release the replacement generation.
            return nil
        }
        var verdict: Unmanaged<CGEvent>?
        DispatchQueue.main.sync {
            verdict = self.handle(type: type,
                                  event: event,
                                  expectedSessionToken: expectedSessionToken)
        }
        return verdict
    }

    /// Main-thread side of the tap; reached only for events `route` decided
    /// the switcher may care about.
    private func handle(type: CGEventType,
                        event: CGEvent,
                        expectedSessionToken: UInt64?) -> Unmanaged<CGEvent>? {
        // With Accessibility revoked the AX lookups behind a session would hang
        // and freeze input; pass events through and drop any session that was
        // open. Cached flag: a live TCC round-trip is too heavy per key.
        guard Permissions.shared.accessibility else {
            if sessionActive { cancelSession() }
            return Unmanaged.passUnretained(event)
        }

        switch type {
        case .keyDown:
            return handleKeyDown(event, expectedSessionToken: expectedSessionToken)
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
            dismissForClickOutsidePanel(expectedToken: expectedSessionToken)
            return Unmanaged.passUnretained(event)
        default:
            return Unmanaged.passUnretained(event)
        }
    }

    /// Honors the immutable routing decision made before the event tap
    /// swallowed the press. Preferences and lifecycle may change while this
    /// block waits for main, but rejecting it then cannot give the key back.
    private func handleAcceptedInitialRoute(token: UInt64) {
        invalidateCacheRefreshWork()
        guard Permissions.shared.accessibility, AXIsProcessTrusted(),
              routeLock.withLock({ routeOwnership.claim(token) }) != nil
        else {
            routeLock.withLock {
                routeOwnership.invalidatePendingRoute(token: token)
            }
            return
        }
        prepareClaimedSession(token: token)
    }

    private func prepareClaimedSession(token: UInt64) {
        let capturedFingerprint = WindowEnumerator.captureSwitcherFingerprint()
        if capturedFingerprint.preferences.currentSpaceOnly {
            cacheRefreshQueue.async { [weak self] in
                let fingerprint = WindowEnumerator.resolveSwitcherFingerprint(capturedFingerprint)
                DispatchQueue.main.async { [weak self] in
                    self?.beginClaimedSession(token: token, fingerprint: fingerprint)
                }
            }
        } else {
            beginClaimedSession(
                token: token,
                fingerprint: WindowEnumerator.resolveSwitcherFingerprint(capturedFingerprint)
            )
        }
    }

    private func beginClaimedSession(token: UInt64,
                                     fingerprint: SwitcherWindowFingerprint) {
        guard Permissions.shared.accessibility, AXIsProcessTrusted() else {
            routeLock.withLock { routeOwnership.invalidatePendingRoute(token: token) }
            return
        }
        guard case .valid = routeLock.withLock({
            routeOwnership.resolveClaimedSession(token)
        }) else { return }
        let cacheDisposition = SwitcherSupport.cacheDisposition(
            fingerprintMatches: cachedWindowFingerprint == fingerprint,
            storedAt: cachedWindowStoredUptime,
            now: ProcessInfo.processInfo.systemUptime,
            maximumAge: Self.maximumWindowCacheAge
        )
        switch cacheDisposition {
        case .reuse, .reuseAndRefresh:
            installClaimedSession(token: token,
                                  allWindows: cachedWindowItems,
                                  cacheDisposition: cacheDisposition)
        case .rebuild:
            let snapshot = WindowEnumerator.captureSwitcherSnapshot()
            cacheRefreshQueue.async { [weak self] in
                let items = WindowEnumerator.listWindows(from: snapshot)
                DispatchQueue.main.async { [weak self] in
                    self?.installClaimedSession(token: token,
                                                allWindows: items,
                                                cacheDisposition: .rebuild)
                }
            }
        }
    }

    private func handleKeyDown(_ event: CGEvent,
                               expectedSessionToken: UInt64?) -> Unmanaged<CGEvent>? {
        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
        let flags = event.flags

        guard routeLock.withLock({ routeOwnership.sessionActive }) else {
            // The same cached shortcuts route() matched, so the two threads can
            // never disagree about one press; syncWithPreferences refreshes them
            // on every settings change.
            let (appsShortcut, windowShortcut) = routeLock.withLock {
                (routeShortcut, routeWindowShortcut)
            }
            let isAppsShortcut = appsShortcut.matches(event: event, allowingExtraShift: true)
            let windowShortcutMatchesPosition = windowShortcut.matches(event: event,
                                                                        allowingExtraShift: true)
            let isWindowShortcut = !isAppsShortcut
                && (windowShortcutMatchesPosition
                    || windowShortcut.matchesByCharacter(event: event))
            guard isAppsShortcut || isWindowShortcut else {
                return Unmanaged.passUnretained(event)
            }

            // This press was routed against an active session but reached main
            // after that session ended. It may start a replacement only when
            // the route owner still recognizes the exact observed generation.
            guard AXIsProcessTrusted() else { return Unmanaged.passUnretained(event) }
            guard let expectedSessionToken else { return Unmanaged.passUnretained(event) }
            let route: SwitcherInitialRoute
            if isWindowShortcut {
                route = SwitcherInitialRoute(
                    shortcut: windowShortcut,
                    scope: .frontmostApp,
                    reversed: SwitcherSupport.windowNavigationDelta(
                    positionalMatch: windowShortcutMatchesPosition,
                    shiftIsNavigationModifier: windowShortcut.shiftIsNavigationModifier,
                    shiftHeld: flags.contains(.maskShift)
                ) < 0)
            } else {
                route = SwitcherInitialRoute(
                    shortcut: appsShortcut,
                    scope: .allApps,
                    reversed: appsShortcut.shiftIsNavigationModifier && flags.contains(.maskShift))
            }
            guard let handoff = routeLock.withLock({
                routeOwnership.claimHandoff(route, expectedSessionToken: expectedSessionToken)
            }) else { return Unmanaged.passUnretained(event) }
            prepareClaimedSession(token: handoff.token)
            // The shortcut belongs to the switcher while the feature is on, so
            // the press is always consumed. With every window closed there is
            // nothing to switch to and nothing appears at all, instead of the
            // system switcher taking the press back.
            return nil
        }

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
                    case .pinSearch:
                        if let expectedSessionToken,
                           routeLock.withLock({
                               routeOwnership.pinActiveSession(expectedToken: expectedSessionToken)
                           }) {
                            isSearchPinned = true
                        }
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

    /// Atomically accepts the exact claimed token before installing rebuilt
    /// data or UI state. A stale worker completion returns without side effects.
    private func installClaimedSession(token: UInt64,
                                       allWindows: [SwitcherItem],
                                       cacheDisposition: SwitcherCacheDisposition) {
        guard let accepted = routeLock.withLock({ routeOwnership.beginSession(token) })
        else { return }
        invalidateCacheRefreshWork()
        let route = accepted.route
        let logicalSource = accepted.source
        if cacheDisposition == .reuseAndRefresh {
            cachedWindowFingerprint = nil
            scheduleWindowCacheRefresh()
        } else if cacheDisposition == .rebuild {
            cachedWindowItems = allWindows
            cachedWindowFingerprint = nil
        }
        guard let reportedFrontPID = logicalSource?.pid
            ?? NSWorkspace.shared.frontmostApplication?.processIdentifier
        else {
            _ = routeLock.withLock {
                routeOwnership.cancelSessionAfterPendingAction(expectedToken: token)
            }
            scheduleWindowCacheRefresh()
            return
        }
        let windows: [SwitcherItem]
        switch route.scope {
        case .allApps:
            guard !allWindows.isEmpty else {
                _ = routeLock.withLock {
                    routeOwnership.cancelSessionAfterPendingAction(expectedToken: token)
                }
                scheduleWindowCacheRefresh()
                return
            }
            windows = allWindows
        case .frontmostApp:
            let scoped = SwitcherSupport.frontmostAppWindows(allItems: allWindows,
                                                             frontmostPID: reportedFrontPID)
            guard !scoped.isEmpty else {
                _ = routeLock.withLock {
                    routeOwnership.cancelSessionAfterPendingAction(expectedToken: token)
                }
                scheduleWindowCacheRefresh()
                return
            }
            windows = scoped
        }
        let focusedSourceWindowID = logicalSource?.windowID
            ?? (SwitcherSupport.needsFocusedWindowLookup(
                frontmostPID: reportedFrontPID,
                items: windows
            ) ? focusedWindowID(for: reportedFrontPID) : nil)
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
        sessionGeneration = accepted.token

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
        selectedIndex = route.scope == .frontmostApp
            ? SwitcherSupport.initialWindowScopedSelectionIndex(itemCount: list.count,
                                                                hasForegroundItem: source != nil,
                                                                reversed: route.reversed)
            : initialSelectionIndex(in: list,
                                    reversed: route.reversed,
                                    hasForegroundItem: source != nil,
                                    frontmostPID: SwitcherSupport.appPID(forFrontmost: reportedFrontPID,
                                                                         items: list))
        sessionShortcut = route.shortcut
        sessionScope = route.scope
        shiftBackNavigationHeld = route.reversed && route.shortcut.shiftIsNavigationModifier
        applyPendingOperations(accepted.operations, expectedSessionToken: accepted.token)

        // Escape, Enter, W, or Q can end the session while queued input is
        // replayed. Do not start preview or panel work for that old token.
        guard sessionGeneration == accepted.token, sessionActive else { return }

        if capturesPreviews {
            WindowPreviewProvider.shared.refreshPreviews(for: list, maxPixelSize: 640 * PreviewSizing.scale) { [weak self] windowID, image in
                guard let self,
                      self.sessionActive,
                      self.sessionItems.contains(where: { $0.previewWindowID == windowID }) else { return }
                self.previews[windowID] = image
            }
        }
        // A cache miss is rebuilt after the tap callback returns. Unpinned
        // quick flicks commit without flashing; pinned search always stays up.
        if SwitcherSupport.shouldShowPanelAfterStartup(
            searchPinned: accepted.searchPinned,
            gestureEnded: accepted.gestureEnded,
            requiredModifiersHeld: route.shortcut.requiredModifiersHeld(
                in: CGEventSource.flagsState(.combinedSessionState)
            )
        ) {
            scheduleShowPanel()
        } else {
            if let sessionGeneration {
                commitReleasedSession(generation: sessionGeneration)
            }
        }
    }

    // MARK: - Window cache

    /// Keeps the expensive Accessibility walk off the shortcut callback. App
    /// lifecycle changes invalidate it, and a WindowServer fingerprint catches
    /// window and Space changes that have no workspace notification.
    private func startWindowCache() {
        windowCacheEnabled = true
        cacheRefreshOwnership.setEnabled(true)
        cacheRefreshRetryCount = 0
        invalidateWindowCache()
        WindowUseTracker.shared.setWindowChangeHandler { [weak self] in
            DispatchQueue.main.async {
                guard let self, self.windowCacheEnabled else { return }
                self.invalidateCacheRefreshWork()
                self.cachedWindowFingerprint = nil
                self.cacheRefreshRetryCount = 0
                self.scheduleWindowCacheRefresh(after: 0.12)
            }
        }
        if workspaceTokens.isEmpty {
            let center = NSWorkspace.shared.notificationCenter
            let names: [Notification.Name] = [
                NSWorkspace.didActivateApplicationNotification,
                NSWorkspace.didLaunchApplicationNotification,
                NSWorkspace.didTerminateApplicationNotification
            ]
            workspaceTokens = names.map { name in
                center.addObserver(forName: name, object: nil, queue: .main) { [weak self] note in
                    guard let self else { return }
                    if name == NSWorkspace.didActivateApplicationNotification,
                       let app = note.userInfo?[NSWorkspace.applicationUserInfoKey]
                            as? NSRunningApplication {
                        self.routeLock.withLock {
                            self.routeOwnership.confirmAppActivation(pid: app.processIdentifier)
                        }
                    }
                    self.invalidateCacheRefreshWork()
                    self.cachedWindowFingerprint = nil
                    self.cacheRefreshRetryCount = 0
                    self.scheduleWindowCacheRefresh()
                }
            }
        }
        scheduleWindowCacheRefresh()
    }

    private func stopWindowCache() {
        WindowUseTracker.shared.setWindowChangeHandler(nil)
        let center = NSWorkspace.shared.notificationCenter
        for token in workspaceTokens { center.removeObserver(token) }
        workspaceTokens = []
        windowCacheEnabled = false
        cacheRefreshOwnership.setEnabled(false)
        pendingCacheRefresh?.cancel()
        pendingCacheRefresh = nil
        cacheRefreshRetryCount = 0
        invalidateWindowCache()
    }

    private func scheduleWindowCacheRefresh(after delay: TimeInterval = 0) {
        guard let token = cacheRefreshOwnership.schedule(sessionActive: sessionActive) else { return }
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.pendingCacheRefresh = nil
            guard self.cacheRefreshOwnership.beginWorker(token,
                                                         sessionActive: self.sessionActive) else { return }
            let beforeCapture = WindowEnumerator.captureSwitcherFingerprint()
            let snapshot = WindowEnumerator.captureSwitcherSnapshot()
            self.cacheRefreshQueue.async { [weak self] in
                let before = WindowEnumerator.resolveSwitcherFingerprint(beforeCapture)
                let items = WindowEnumerator.listWindows(from: snapshot)
                DispatchQueue.main.async {
                    guard let self else { return }
                    let afterCapture = WindowEnumerator.captureSwitcherFingerprint()
                    self.cacheRefreshQueue.async { [weak self] in
                        let after = WindowEnumerator.resolveSwitcherFingerprint(afterCapture)
                        DispatchQueue.main.async {
                            self?.completeWindowCacheRefresh(token: token,
                                                             items: items,
                                                             before: before,
                                                             after: after)
                        }
                    }
                }
            }
        }
        pendingCacheRefresh = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    private func completeWindowCacheRefresh(token: UInt64,
                                            items: [SwitcherItem],
                                            before: SwitcherWindowFingerprint,
                                            after: SwitcherWindowFingerprint) {
        guard let completion = cacheRefreshOwnership.completeWorker(
            token,
            sessionActive: sessionActive
        ) else { return }
        if completion.installsResult {
            if before == after {
                storeCachedWindows(items, fingerprint: after)
                cacheRefreshRetryCount = 0
            } else {
                cachedWindowItems = items
                cachedWindowFingerprint = nil
                let retry = cacheRefreshRetryCount
                cacheRefreshRetryCount += 1
                if let delay = SwitcherSupport.cacheRefreshRetryDelay(
                    stable: false,
                    retryCount: retry,
                    sessionActive: sessionActive
                ) {
                    scheduleWindowCacheRefresh(after: delay)
                }
            }
        }
        if completion.schedulesRerun {
            scheduleWindowCacheRefresh()
        }
    }

    private func invalidateCacheRefreshWork() {
        pendingCacheRefresh?.cancel()
        pendingCacheRefresh = nil
        cacheRefreshOwnership.invalidate()
    }

    private func invalidateWindowCache() {
        cachedWindowItems = []
        cachedWindowFingerprint = nil
        cachedWindowStoredUptime = nil
    }

    private func storeCachedWindows(_ items: [SwitcherItem],
                                    fingerprint: SwitcherWindowFingerprint) {
        cachedWindowItems = items
        cachedWindowFingerprint = fingerprint
        cachedWindowStoredUptime = ProcessInfo.processInfo.systemUptime
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
    private func recordUse(_ activated: SwitcherItem,
                           previousWindowID: CGWindowID?,
                           previousItemID: String?) {
        WindowUseTracker.shared.recordSwitch(to: activated.windowID, from: previousWindowID)
        cachedWindowItems = SwitcherSupport.cachedItemsAfterSwitch(
            cachedWindowItems,
            targetID: activated.id,
            previousID: previousItemID
        )
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
              !closingItemIDs.contains(item.id),
              let windowID = item.windowID,
              WindowActivator.closeWindow(windowID: windowID,
                                           appPID: item.pid,
                                           windowOwnerPID: item.windowOwnerPID)
        else { return }

        closingItemIDs.insert(item.id)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) { [weak self] in
            self?.finishClosingWindow(itemID: item.id,
                                      windowID: windowID,
                                      pid: item.pid,
                                      attempt: 0)
        }
    }

    private func advanceSelection(by delta: Int, wrapping: Bool = true) {
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
        selectedIndex = wrapping
            ? (next + windows.count) % windows.count
            : SwitcherSupport.nonWrappingSelectionIndex(itemCount: windows.count,
                                                        selectedIndex: selectedIndex,
                                                        delta: delta)
    }

    private func advanceAppSelection(by delta: Int, wrapping: Bool = true) {
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

    private func applyPendingNavigation(_ operation: SwitcherPendingNavigation) {
        if sessionScope == .frontmostApp || operation.command == .allApps {
            advanceSelection(by: operation.delta, wrapping: operation.wrapping)
            return
        }
        let step = operation.delta < 0 ? -1 : 1
        for _ in 0..<abs(operation.delta) {
            advanceWindowInSelectedApp(by: step)
        }
    }

    private func applyPendingOperations(_ operations: [SwitcherPendingOperation],
                                        expectedSessionToken: UInt64) {
        for operation in operations {
            guard sessionGeneration == expectedSessionToken, sessionActive else { return }
            switch operation {
            case let .navigation(navigation):
                applyPendingNavigation(navigation)
            case let .keyCommand(input):
                applyPendingKeyCommand(input)
            case let .letterAction(action):
                applyPendingLetterAction(action, expectedSessionToken: expectedSessionToken)
            case let .searchText(text):
                appendSearchText(text)
            case let .terminal(terminal):
                switch terminal {
                case .commit: commitSession()
                case .cancel: cancelSession(expectedToken: expectedSessionToken)
                }
            }
        }
    }

    private func applyPendingKeyCommand(_ input: SwitcherPendingKeyInput) {
        switch input.keyCode {
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
            break
        }
    }

    private func applyPendingLetterAction(_ action: SwitcherLetterAction,
                                          expectedSessionToken: UInt64) {
        switch action {
        case .closeWindow: closeSelectedWindow()
        case .quitApp: quitSelectedApp(expectedSessionToken: expectedSessionToken)
        case .pinSearch:
            isSearchPinned = true
        }
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
    private func quitSelectedApp(expectedSessionToken: UInt64? = nil) {
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
            if let expectedSessionToken {
                guard routeLock.withLock({
                    routeOwnership.cancelSessionAfterPendingAction(
                        expectedToken: expectedSessionToken
                    )
                }) else { return }
                clearSessionState(preservingRouteLifecycle: true)
            } else {
                cancelSession()
            }
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
            // Still there after the retries: the app kept it, so it is a
            // normal entry again and the release may raise it.
            guard attempt < 2 else {
                closingItemIDs.remove(itemID)
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
        guard state.didRemove else { return }

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
                cancelSession()
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
        guard sessionActive, let generation = sessionGeneration else { return }
        guard routeLock.withLock({ routeOwnership.releaseActiveSession() }) == generation else { return }
        commitReleasedSession(generation: generation)
    }

    /// Release routing reaches here asynchronously after the tap has already
    /// relinquished the old session. AX validation may be slow, but subsequent
    /// switcher presses are owned and queued while it runs.
    private func commitReleasedSession(generation: UInt64) {
        guard sessionGeneration == generation,
              routeLock.withLock({ routeOwnership.claimReleasedSession(generation) })
        else { return }
        // A window that was just closed is still listed for a moment; letting
        // go right after must land on what takes its place, never on it.
        let selection = SwitcherSupport.liveCommitTarget(items: windows,
                                                         selectedIndex: selectedIndex,
                                                         closingItemIDs: closingItemIDs,
                                                         resolve: WindowEnumerator.refreshedSwitcherCandidate)
        let source = sessionSourceContext
        let previousWindowID = sessionStartWindowID
        if let selection {
            let sourcePublished = routeLock.withLock {
                routeOwnership.publishActivationSource(SwitcherRouteSource(selection),
                                                       generation: generation)
            }
            guard sourcePublished else {
                clearSessionState()
                return
            }
            clearSessionState(preservingRouteLifecycle: true)
            recordUse(selection,
                      previousWindowID: previousWindowID,
                      previousItemID: source?.itemID)
            WindowActivator.activate(selection,
                                     sourceWasFullscreen: source?.isFullscreen ?? false,
                                     sourcePID: source?.pid,
                                     sourceWindowID: source?.isFullscreen == true ? nil : source?.windowID,
                                     sourceWindowOwnerPID: source?.windowOwnerPID)
            scheduleActivationConfirmationProbes(generation: generation)
            DispatchQueue.main.asyncAfter(
                deadline: .now() + SwitcherActivationConfirmation.timeout
            ) { [weak self] in
                guard let self else { return }
                self.routeLock.withLock { self.routeOwnership.finishActivation(generation) }
            }
        } else {
            routeLock.withLock { routeOwnership.completeReleasedSession(generation) }
            clearSessionState(preservingRouteLifecycle: true)
        }
    }

    /// Exact-window activation cannot be inferred from an app notification.
    /// Probe around the activator's ordinary and fullscreen focus passes, then
    /// let the bounded activation timeout retire a target that never confirms.
    private func scheduleActivationConfirmationProbes(generation: UInt64) {
        for delay in SwitcherActivationConfirmation.probeDelays {
            activationProbeQueue.asyncAfter(deadline: .now() + delay) { [weak self] in
                guard let self,
                      let target = self.routeLock.withLock({
                          self.routeOwnership.windowActivationTarget(generation: generation)
                      })
                else { return }
                let focusedWindowID = WindowActivator.focusedWindowID(for: target.windowOwnerPID)
                self.routeLock.withLock {
                    self.routeOwnership.confirmWindowActivation(
                        generation: target.generation,
                        focusedWindowID: focusedWindowID
                    )
                }
            }
        }
    }

    private func cancelSession() {
        routeLock.withLock { routeOwnership.invalidateLifecycle() }
        clearSessionState(preservingRouteLifecycle: true)
    }

    private func cancelSession(expectedToken: UInt64) {
        guard routeLock.withLock({
            routeOwnership.cancelActiveSession(expectedToken: expectedToken)
        }) else { return }
        clearSessionState(preservingRouteLifecycle: true)
    }

    private func clearSessionState(preservingRouteLifecycle: Bool = false) {
        if !preservingRouteLifecycle {
            routeLock.withLock { routeOwnership.invalidateLifecycle() }
        }
        sessionGeneration = nil
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
        userNavigated = false
        sessionStartWindowID = nil
        sessionSourceContext = nil
        sessionShortcut = nil
        sessionScope = .allApps
        shiftBackNavigationHeld = false
        closingItemIDs = []
        if cachedWindowFingerprint == nil {
            scheduleWindowCacheRefresh()
        }
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
    private func dismissForClickOutsidePanel(expectedToken: UInt64?) {
        guard sessionActive, let expectedToken else { return }
        let shouldDismiss = panel.map {
            SwitcherSupport.shouldDismissForClick(panelIsVisible: $0.isVisible,
                                                  panelFrame: $0.frame,
                                                  location: NSEvent.mouseLocation)
        } ?? true
        guard shouldDismiss
        else { return }
        guard routeLock.withLock({
            routeOwnership.cancelActiveSessionForMouseDown(expectedToken: expectedToken)
        }) else { return }
        clearSessionState(preservingRouteLifecycle: true)
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
