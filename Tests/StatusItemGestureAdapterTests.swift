// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import Combine
import CoreGraphics

/// Production adapter methods are compiled verbatim by generate_sources.py.
/// Only OS inputs, the controller and the permission/tap boundary are doubled;
/// event routing, permission subscriptions and the release timer are real.
enum StatusItemGestureAdapterTests {
    final class Permissions {
        static let shared = Permissions()
        @Published var accessibility = false
        var requests = 0
        func requestAccessibility() { requests += 1 }
    }

    static func AXIsProcessTrusted() -> Bool { Permissions.shared.accessibility }

    struct NSEvent {
        static var pressedMouseButtons = 0
        static var mouseLocation = CGPoint(x: 120, y: 300)
        var type: AppKit.NSEvent.EventType = .leftMouseUp
        var timestamp: TimeInterval
        var modifierFlags: AppKit.NSEvent.ModifierFlags = []
        var window: Window?
        /// The event's own location, in display coordinates.
        var cgEvent: CGEvent?
    }

    /// The event source's record of the last physical release and press.
    /// Unset, the release is reported at the current uptime, the latest a
    /// tick can see, and no press is known.
    enum CGEventSource {
        static var releasedAt: TimeInterval?
        static var pressedAt: TimeInterval?
        static func secondsSinceLastEventType(_ state: CGEventSourceStateID,
                                              eventType: CGEventType) -> CFTimeInterval {
            let now = ProcessInfo.processInfo.systemUptime
            if eventType == .leftMouseDown { return pressedAt.map { now - $0 } ?? .infinity }
            return releasedAt.map { now - $0 } ?? 0
        }
    }

    struct NSScreen {
        static let screens = [NSScreen()]
        let frame = CGRect(x: 0, y: 0, width: 1000, height: 800)
    }

    struct ProcessInfo {
        static var processInfo = ProcessInfo()
        var systemUptime: TimeInterval = 0
    }

    struct Window { var windowNumber = 42 }
    struct Button { var window: Window? = Window() }
    struct Item {
        var isVisible = true
        var button: Button? = Button()
    }
    enum WindowServerSupport {
        static var receivingWindowNumber = 42
        static var menuBars: Set<CGWindowID> = []
        static var lastPoint: CGPoint?
        static func receivingWindow(at point: CGPoint) -> CGWindowID? {
            lastPoint = point
            return receivingWindowNumber > 0 ? CGWindowID(receivingWindowNumber) : nil
        }
        static func isMenuBar(windowID: CGWindowID) -> Bool { menuBars.contains(windowID) }
    }
    enum NSApp { static var currentEvent: NSEvent? }

    final class Tap {
        var enabled = true
        var valid = true
        var enables = 0
    }
    static func CFMachPortInvalidate(_ tap: Tap) { tap.valid = false }

    final class Owner {
        var statusItem: Item? = Item()
        var gestureTapSuspended = false
        var onDelayedLeftClick: ((NSPoint) -> Void)?
        var onQuickAction: ((StatusItemQuickAction) -> Void)?
    }

    class ControllerFixture: NSObject {
        var gestureHandler: Host?
        var statusItem = Item()
        var leftClicks = 0
        var rightClicks = 0
        var onLeftClick: (() -> Void)?
        var onRightClick: ((Button?) -> Void)?
        override init() {
            super.init()
            onLeftClick = { [weak self] in self?.leftClicks += 1 }
            onRightClick = { [weak self] _ in self?.rightClicks += 1 }
        }
        func cancelGesture() { gestureHandler?.cancel() }
    }

    class Fixture {
        static let releaseWatchInterval: TimeInterval = 0.04
        static let lateActionWindow: TimeInterval = 2
        static let sameEventSlack: TimeInterval = 0.001
        var owner: Owner? = Owner()
        var gesture = StatusItemGesture()
        var settings = StatusItemGesture.Settings(middle: .keepAwake, hold: .screenshot)
        var timer: Timer?
        var generation = 0
        var leftPressStart: TimeInterval?
        var lastHeldPoint: CGPoint?
        var leftActionSeen = true
        var rejectedLeftDown: TimeInterval?
        var handledLeftRelease: TimeInterval?
        /// Whether Accessibility names the main button where the window
        /// server cannot: never, unless a test says so. Every question asked
        /// is recorded.
        var accessibilityNamesButton = false
        var accessibilityQueries: [CGPoint] = []
        var middleTap: Tap?
        var middleRunLoopSource: CFRunLoopSource?
        var accessibilityObserver: AnyCancellable?
        var frame: CGRect? = CGRect(x: 105, y: 288, width: 30, height: 24)
        var installations = 0
        var installAttempts = 0
        var failsInstallation = false
        var taps: [Tap] = []
        var removals: Int { taps.filter { !$0.valid }.count }
        var results: [StatusItemGesture.Result] = []

        init() {
            owner?.onDelayedLeftClick = { [weak self] in self?.results.append(.single($0)) }
            owner?.onQuickAction = { [weak self] in self?.results.append(.quick($0)) }
        }

        deinit { timer?.invalidate() }
        func mainButtonFrame() -> NSRect? { frame }
        func accessibilityNamesMainButton(at point: CGPoint) -> Bool {
            accessibilityQueries.append(point)
            return accessibilityNamesButton
        }
        func log(_ message: String) {}
        func installMiddleTap() {
            installAttempts += 1
            guard !failsInstallation else { return }
            let tap = Tap()
            taps.append(tap)
            middleTap = tap
            installations += 1
        }
    }

    /// Every feature installed, unless a test takes one away.
    static func installingEveryFeature(in defaults: UserDefaults) -> UserDefaults {
        for feature in AppFeature.allCases { defaults.set(true, forKey: feature.availabilityKey) }
        return defaults
    }

    class SettingsFixture {
        let defaults = installingEveryFeature(in: UserDefaults(suiteName: "vorss.tests.status-action-settings")!)
        var middleAction = StatusItemQuickAction.none.rawValue
        var permissions = Permissions.shared
        deinit { defaults.removePersistentDomain(forName: "vorss.tests.status-action-settings") }
    }

    class UsageFixture {
        struct Feature {
            func hubTitle(_ strings: Strings, hub: FeatureHubStrings) -> String { "Existing feature" }
        }
        let defaults = installingEveryFeature(in: UserDefaults(suiteName: "vorss.tests.status-action-usage")!)
        var middleAction = StatusItemQuickAction.none.rawValue
        var permission = AppPermission.accessibility
        var activeFeatures: [Feature] = []
        let l10n = L10n.shared
        let hub = FeatureStrings.hub(.enUS)
        deinit { defaults.removePersistentDomain(forName: "vorss.tests.status-action-usage") }
    }

    /// The services each action calls, recorded instead of run.
    final class Service {
        static var calls: [String] = []
        let name: String
        init(_ name: String) { self.name = name }
        func toggle() { Self.calls.append(name) }
        func capture() { Self.calls.append(name) }
    }
    enum KeepAwakeManager { static let shared = Service("keepAwake") }
    enum MicMuteService { static let shared = Service("micMute") }
    enum ScreenRecorderService { static let shared = Service("screenRecorder") }
    enum ScreenshotService { static let shared = Service("screenshot") }
    enum AppVolumeMixer {
        static var muted: Bool?
        static func systemOutputIsMuted() -> Bool? { muted }
        static func setSystemOutputMuted(_ muted: Bool) -> Bool {
            Service.calls.append(muted ? "mute" : "unmute")
            return true
        }
    }

    class DispatchFixture {
        static let defaults = installingEveryFeature(in: UserDefaults(suiteName: "vorss.tests.status-action-dispatch")!)
        var pendingClose: (() -> Void)?
        var failures: [String] = []
        func closePopover(animated: Bool, completion: @escaping () -> Void) { pendingClose = completion }
        func reportStatusItemActionFailure(icon: String) { failures.append(icon) }
    }

    class PollingFixture {
        let defaults = installingEveryFeature(in: UserDefaults(suiteName: "vorss.tests.status-action-polling")!)
        var permissionSurfaceDemands: Set<UUID> = []
        var accessibility = false
        var screenRecording = false
        deinit { defaults.removePersistentDomain(forName: "vorss.tests.status-action-polling") }
    }

    static func run(_ suite: TestSuite) {
        defer {
            NSEvent.pressedMouseButtons = 0
            NSEvent.mouseLocation = CGPoint(x: 120, y: 300)
            Permissions.shared.accessibility = false
            Permissions.shared.requests = 0
            WindowServerSupport.receivingWindowNumber = 42
            WindowServerSupport.menuBars = []
            WindowServerSupport.lastPoint = nil
            NSApp.currentEvent = nil
            ProcessInfo.processInfo.systemUptime = 0
            CGEventSource.releasedAt = nil
            CGEventSource.pressedAt = nil
            AppVolumeMixer.muted = nil
            Service.calls = []
        }
        testMissingDown(suite)
        testMiddleRelease(suite)
        testReleaseOrdering(suite)
        testMiddleOnly(suite)
        testPermissionChanges(suite)
        testPermissionUI(suite)
        testHoldDuringMiddleSync(suite)
        testDisabledTapRecovery(suite)
        testWindowOwnershipAndTopEdge(suite)
        testControllerActivation(suite)
        testClickFreshnessBoundary(suite)
        testLateButtonAction(suite)
        testModifiedPress(suite)
        testMissingDownBesideMiddle(suite)
        testPressOnOwnWindow(suite)
        testLateReleaseTick(suite)
        testDragAndCancel(suite)
        testLateActionAfterRelease(suite)
        testReleaseWhereHeld(suite)
        testMiddleDuringLeftPress(suite)
        testSystemHostedMenuBar(suite)
        testActionDispatch(suite)
        testSuspendedTap(suite)
        testQueuedEventLocation(suite)
        testReleaseTimeSources(suite)
        testSecondPress(suite)
        testPanelAnchor(suite)
    }

    private static func testPermissionUI(_ suite: TestSuite) {
        Permissions.shared.accessibility = false
        Permissions.shared.requests = 0
        let settings = SettingsHost()
        settings.setMiddleAction(StatusItemQuickAction.keepAwake.rawValue)
        suite.expect(Permissions.shared.requests == 1, "the first explicit middle-click choice asks for permission")
        let handler = Host()
        handler.watchAccessibility()
        handler.syncMiddleTap()
        handler.sync(settings: .init(middle: .keepAwake, hold: .soundMute))
        suite.expect(Permissions.shared.requests == 1 && handler.middleTap == nil,
                     "handler startup and a hold-only change never ask again")
        settings.setMiddleAction(settings.middleAction)
        settings.setMiddleAction(StatusItemQuickAction.none.rawValue)
        suite.expect(Permissions.shared.requests == 1, "unchanged and off choices do not ask")
        settings.setMiddleAction(StatusItemQuickAction.micMute.rawValue)
        suite.expect(Permissions.shared.requests == 2, "another explicit middle-click choice may ask again")
        Permissions.shared.accessibility = true
        settings.setMiddleAction(StatusItemQuickAction.soundMute.rawValue)
        suite.expect(Permissions.shared.requests == 2 && handler.middleTap != nil,
                     "an existing grant needs no request and restores the tap quietly")

        Permissions.shared.accessibility = false
        Permissions.shared.requests = 0
        for _ in 0..<2 {
            let launched = Host()
            launched.watchAccessibility()
            launched.syncMiddleTap()
            launched.sync(settings: launched.settings)
            suite.expect(Permissions.shared.requests == 0 && launched.middleTap == nil,
                         "relaunching with a saved action and no grant stays silent")
        }

        let usage = UsageHost()
        let polling = PollingHost()
        for action in StatusItemQuickAction.allCases {
            usage.middleAction = action.rawValue
            polling.defaults.set(action.rawValue, forKey: DefaultsKey.statusItemMiddleClickAction)
            let needed = action != .none
            suite.expect(!usage.activeUsageNames.isEmpty == needed
                         && (polling.desiredPollInterval != nil) == needed,
                         "permission usage and polling agree for \(action.rawValue)")
            if needed {
                let name = StatusItemQuickActionStrings.localized(L10n.shared.language).middleClickUsage
                suite.expect(usage.usedByLine.contains(name),
                             "the permission row names middle-click even with no active features")
            }
        }
        usage.activeFeatures = [.init()]
        suite.expect(usage.activeUsageNames.count == 2, "middle-click preserves existing permission users")
        usage.permission = .screenRecording
        suite.expect(usage.activeUsageNames == ["Existing feature"], "middle-click only counts for Accessibility")
        usage.permission = .accessibility
        usage.activeFeatures = []
        for value in [StatusItemQuickAction.none.rawValue, "futureAction"] {
            usage.middleAction = value
            polling.defaults.set(value, forKey: DefaultsKey.statusItemMiddleClickAction)
            polling.defaults.set(StatusItemQuickAction.screenshot.rawValue, forKey: DefaultsKey.statusItemLongPressAction)
            suite.expect(usage.activeUsageNames.isEmpty && usage.usedByLine == usage.hub.usedByNone
                         && polling.desiredPollInterval == nil,
                         "off or unknown middle actions, even with hold enabled, need no Accessibility")
        }

        // A middle action whose feature is uninstalled is inert until it returns.
        let uninstalled = SettingsHost()
        Permissions.shared.requests = 0
        for defaults in [uninstalled.defaults, usage.defaults, polling.defaults] {
            defaults.set(false, forKey: AppFeature.keepAwake.availabilityKey)
        }
        uninstalled.setMiddleAction(StatusItemQuickAction.keepAwake.rawValue)
        usage.middleAction = StatusItemQuickAction.keepAwake.rawValue
        polling.defaults.set(StatusItemQuickAction.keepAwake.rawValue, forKey: DefaultsKey.statusItemMiddleClickAction)
        suite.expect(Permissions.shared.requests == 0 && usage.activeUsageNames.isEmpty
                     && polling.desiredPollInterval == nil,
                     "an uninstalled middle action asks for, polls and lists no Accessibility")
        polling.defaults.set(true, forKey: AppFeature.keepAwake.availabilityKey)
        usage.defaults.set(true, forKey: AppFeature.keepAwake.availabilityKey)
        suite.expect(polling.desiredPollInterval != nil && !usage.activeUsageNames.isEmpty,
                     "reinstalling the feature brings the saved assignment back")
    }

    private static func testMissingDown(_ suite: TestSuite) {
        let point = CGPoint(x: 120, y: 300)
        for duration in [0.1, 1.0] {
            let host = Host()
            NSEvent.mouseLocation = point
            NSEvent.pressedMouseButtons = 1
            suite.expect(host.buttonClick(NSEvent(timestamp: 10)),
                         "the adapter claims a valid press even when the monitor missed down")
            suite.expect(host.gesture.watchesForRelease && host.timer?.isValid == true,
                         "the missing-down fallback starts the real release watcher")
            suite.expect(host.results.isEmpty, "a held physical button emits nothing yet")
            ProcessInfo.processInfo.systemUptime = 10 + duration
            host.timer?.fire()
            suite.expect(host.results.isEmpty, "even a long press waits for release")
            NSEvent.pressedMouseButtons = 0
            host.timer?.fire()
            let expected: StatusItemGesture.Result = duration < 0.5 ? .single(point) : .quick(.screenshot)
            suite.expect(host.results == [expected],
                         "the adapter delivers exactly one short-click or hold after a missed down")
            suite.expect(host.timer == nil && !host.gesture.isActive,
                         "the release watcher stops when the fallback press ends")
            host.observeRelease()
            suite.expect(host.results == [expected], "a repeated release cannot emit twice")
        }

        let released = Host()
        suite.expect(released.buttonClick(NSEvent(timestamp: 20))
                     && released.results == [.single(point)],
                     "a missing-down action delivered after release still opens the panel")
        for frame in [nil, CGRect.zero, CGRect(x: 500, y: 500, width: 30, height: 24)] {
            let host = Host()
            host.frame = frame
            NSEvent.pressedMouseButtons = 1
            suite.expect(!host.buttonClick(NSEvent(timestamp: 30))
                         && host.timer == nil && !host.gesture.isActive,
                         "unplaceable presses remain unclaimed for the normal click path")
        }

        let observed = Host()
        NSEvent.pressedMouseButtons = 1
        observed.observe(NSEvent(type: .leftMouseDown, timestamp: 40))
        _ = observed.buttonClick(NSEvent(timestamp: 40.4))
        NSEvent.pressedMouseButtons = 0
        ProcessInfo.processInfo.systemUptime = 40.6
        observed.timer?.fire()
        suite.expect(observed.results == [.quick(.screenshot)],
                     "the button fallback does not reset a press the monitor already started")
    }

    private static func testReleaseOrdering(_ suite: TestSuite) {
        let point = CGPoint(x: 120, y: 300)
        for duration in [0.1, 1.0] {
            for watcherFirst in [false, true] {
                for monitorSeesUp in [false, true] {
                    let host = Host()
                    NSEvent.mouseLocation = point
                    NSEvent.pressedMouseButtons = 1
                    host.observe(NSEvent(type: .leftMouseDown, timestamp: 100))
                    NSEvent.pressedMouseButtons = 0
                    let release = NSEvent(timestamp: 100 + duration)
                    ProcessInfo.processInfo.systemUptime = release.timestamp + 0.02
                    if watcherFirst { host.timer?.fire() }
                    if monitorSeesUp { host.observe(release) }
                    _ = host.buttonClick(release)
                    host.timer?.fire()
                    let expected: StatusItemGesture.Result = duration < 0.5 ? .single(point) : .quick(.screenshot)
                    suite.expect(host.results == [expected] && host.timer == nil,
                                 "release ordering delivers one outcome (hold=\(duration), watcher=\(watcherFirst), monitor=\(monitorSeesUp))")
                    // Equal and older actions are duplicates, even if no monitor saw the up.
                    _ = host.buttonClick(release)
                    suite.expect(host.results == [expected], "a repeated button action cannot reopen the panel")
                    // No monitor down for the next real click: it must still work.
                    _ = host.buttonClick(NSEvent(timestamp: 102))
                    suite.expect(host.results == [expected, .single(point)],
                                 "a newer button action is not swallowed by release deduplication")
                }
            }
        }
    }

    private static func testMiddleOnly(_ suite: TestSuite) {
        let host = Host()
        host.settings = .init(middle: .keepAwake)
        NSEvent.pressedMouseButtons = 1
        host.observe(NSEvent(type: .leftMouseDown, timestamp: 200))
        suite.expect(host.timer == nil && !host.gesture.isActive,
                     "middle-only settings never start a left-click watcher")
        NSEvent.pressedMouseButtons = 0
        host.observe(NSEvent(timestamp: 200.1))
        suite.expect(!host.buttonClick(NSEvent(timestamp: 200.1)) && host.results.isEmpty,
                     "middle-only settings leave the left click to the controller's normal path")
        host.handleMiddleTap(type: .otherMouseDown, event: middleEvent(.otherMouseDown, x: 120))
        host.handleMiddleTap(type: .otherMouseUp, event: middleEvent(.otherMouseUp, x: 120))
        suite.expect(host.results == [.quick(.keepAwake)], "bypassing left clicks preserves middle-click actions")
    }

    private static func middleEvent(_ type: CGEventType, x positionX: CGFloat,
                                    y positionY: CGFloat = 500, button: Int64 = 2) -> CGEvent {
        let event = CGEvent(mouseEventSource: nil, mouseType: type,
                            mouseCursorPosition: CGPoint(x: positionX, y: positionY), mouseButton: .center)!
        event.setIntegerValueField(.mouseEventButtonNumber, value: button)
        return event
    }

    private static func testMiddleRelease(_ suite: TestSuite) {
        let host = Host()
        host.handleMiddleTap(type: .otherMouseDown, event: middleEvent(.otherMouseDown, x: 120))
        suite.expect(host.gesture.isActive, "an inside middle down reaches the adapter")
        host.handleMiddleTap(type: .otherMouseUp, event: middleEvent(.otherMouseUp, x: 150))
        suite.expect(!host.gesture.isActive && host.results.isEmpty,
                     "an outside middle release cancels its pending press")
        host.handleMiddleTap(type: .otherMouseDown, event: middleEvent(.otherMouseDown, x: 150))
        host.handleMiddleTap(type: .otherMouseUp, event: middleEvent(.otherMouseUp, x: 120))
        suite.expect(host.results.isEmpty && !host.gesture.isActive,
                     "outside down then inside up cannot complete an old middle gesture")
        host.handleMiddleTap(type: .otherMouseDown, event: middleEvent(.otherMouseDown, x: 120))
        host.handleMiddleTap(type: .otherMouseUp, event: middleEvent(.otherMouseUp, x: 120))
        host.handleMiddleTap(type: .otherMouseUp, event: middleEvent(.otherMouseUp, x: 120))
        suite.expect(host.results == [.quick(.keepAwake)], "a fresh middle click still fires exactly once")

        host.results = []
        host.handleMiddleTap(type: .otherMouseDown, event: middleEvent(.otherMouseDown, x: 120))
        host.frame = nil
        host.handleMiddleTap(type: .otherMouseUp, event: middleEvent(.otherMouseUp, x: 120))
        suite.expect(!host.gesture.isActive && host.results.isEmpty,
                     "losing the icon frame before release also cancels the press")
    }

}

extension StatusItemGestureAdapterTests {
    private static func testHoldDuringMiddleSync(_ suite: TestSuite) {
        let point = CGPoint(x: 120, y: 300)
        Permissions.shared.accessibility = false
        for duration in [0.1, 1.0] {
            for actionAtPress in [false, true] {
                let host = Host()
                NSEvent.mouseLocation = point
                NSEvent.pressedMouseButtons = 1
                host.observe(NSEvent(type: .leftMouseDown, timestamp: 300))
                if actionAtPress { _ = host.buttonClick(NSEvent(timestamp: 300)) }
                let watch = host.timer
                host.sync(settings: host.settings)
                host.sync(settings: host.settings)
                suite.expect(host.gesture.watchesForRelease && host.timer === watch,
                             "denied middle permission and unrelated sync preserve a left press and its watcher")
                NSEvent.pressedMouseButtons = 0
                ProcessInfo.processInfo.systemUptime = 300 + duration
                host.timer?.fire()
                if !actionAtPress { _ = host.buttonClick(NSEvent(timestamp: 300 + duration)) }
                let expected: StatusItemGesture.Result = duration < 0.5 ? .single(point) : .quick(.screenshot)
                suite.expect(host.results == [expected] && host.timer == nil,
                             "a left press overlapping denied middle sync produces exactly one outcome")
            }
        }
        let revoked = Host()
        Permissions.shared.accessibility = true
        revoked.syncMiddleTap()
        NSEvent.pressedMouseButtons = 1
        revoked.observe(NSEvent(type: .leftMouseDown, timestamp: 310))
        ProcessInfo.processInfo.systemUptime = 310.6
        revoked.timer?.fire()
        suite.expect(revoked.gesture.deadline(revoked.settings) == nil && revoked.gesture.watchesForRelease,
                     "the watcher crosses the hold threshold before revocation")
        revoked.syncMiddleTap(accessibilityGranted: false)
        suite.expect(revoked.middleTap == nil && revoked.gesture.watchesForRelease,
                     "removing a middle tap does not cancel a left hold")
        NSEvent.pressedMouseButtons = 0
        ProcessInfo.processInfo.systemUptime = 311
        revoked.timer?.fire()
        suite.expect(revoked.results == [.quick(.screenshot)], "a left hold survives middle tap removal")

        let outside = Host()
        NSEvent.pressedMouseButtons = 1
        outside.observe(NSEvent(type: .leftMouseDown, timestamp: 320))
        outside.handleMiddleTap(type: .otherMouseUp, event: middleEvent(.otherMouseUp, x: 500))
        suite.expect(outside.gesture.watchesForRelease, "unrelated session-wide middle input preserves a left hold")
        outside.handleMiddleTap(type: .otherMouseUp, event: middleEvent(.otherMouseUp, x: 120))
        suite.expect(outside.gesture.watchesForRelease,
                     "an unmatched middle release on the icon also preserves a left hold")
        outside.sync(settings: .init(middle: .keepAwake, hold: .soundMute))
        suite.expect(!outside.gesture.isActive && outside.timer == nil,
                     "an actual assignment change still cancels a left press")
        NSEvent.pressedMouseButtons = 0
    }

    private static func testDisabledTapRecovery(_ suite: TestSuite) {
        Permissions.shared.accessibility = true
        Permissions.shared.requests = 0
        for type in [CGEventType.tapDisabledByTimeout, .tapDisabledByUserInput] {
            let host = Host()
            host.syncMiddleTap()
            let tap = host.middleTap!
            host.handleMiddleTap(type: .otherMouseDown, event: middleEvent(.otherMouseDown, x: 120))
            tap.enabled = false
            // Disabled notifications carry no useful mouse button field.
            host.handleMiddleTap(type: type, event: middleEvent(.otherMouseUp, x: 120, button: 0))
            suite.expect(tap.enabled && tap.enables == 1 && !host.gesture.isActive,
                         "a disabled notification re-arms the tap and drops its pre-gap middle press")
            host.handleMiddleTap(type: .otherMouseUp, event: middleEvent(.otherMouseUp, x: 120))
            suite.expect(host.results.isEmpty, "a post-gap release cannot replay the old middle press")
            host.handleMiddleTap(type: .otherMouseDown, event: middleEvent(.otherMouseDown, x: 120))
            host.handleMiddleTap(type: .otherMouseUp, event: middleEvent(.otherMouseUp, x: 120))
            suite.expect(host.results == [.quick(.keepAwake)], "a fresh middle pair works after tap recovery")

            NSEvent.pressedMouseButtons = 1
            host.observe(NSEvent(type: .leftMouseDown, timestamp: 330))
            ProcessInfo.processInfo.systemUptime = 330.6
            host.timer?.fire()
            tap.enabled = false
            host.handleMiddleTap(type: type, event: middleEvent(.otherMouseUp, x: 120))
            suite.expect(host.gesture.watchesForRelease && host.timer?.isValid == true,
                         "tap recovery leaves a left hold and its watcher intact")
            NSEvent.pressedMouseButtons = 0
            ProcessInfo.processInfo.systemUptime = 331
            host.timer?.fire()
            suite.expect(host.results == [.quick(.keepAwake), .quick(.screenshot)],
                         "the left hold still fires once after tap recovery")
        }
        let host = Host()
        host.syncMiddleTap()
        let old = host.middleTap!
        host.handleMiddleTap(type: .otherMouseDown, event: middleEvent(.otherMouseDown, x: 120))
        old.enabled = false
        // A revoke/regrant between polls can leave the published grant unchanged.
        host.sync(settings: host.settings)
        suite.expect(!old.valid && host.middleTap !== old && host.installations == 2
                     && host.removals == 1 && !host.gesture.isActive,
                     "unchanged settings rebuild a tap the system disabled without a published grant change")
        host.sync(settings: host.settings)
        suite.expect(host.installations == 2, "sync never duplicates an enabled tap")
        host.tearDownMiddleTap()
        host.failsInstallation = true
        host.sync(settings: host.settings)
        suite.expect(host.middleTap == nil, "failed tap creation stays passive")
        host.failsInstallation = false
        host.sync(settings: host.settings)
        suite.expect(host.installations == 3 && host.installAttempts == 4,
                     "a later unchanged sync retries a failed installation")

        Permissions.shared.accessibility = false
        let denied = Host()
        denied.installMiddleTap()
        let deniedTap = denied.middleTap!
        deniedTap.enabled = false
        denied.handleMiddleTap(type: .tapDisabledByUserInput, event: middleEvent(.otherMouseUp, x: 120))
        suite.expect(!deniedTap.enabled && deniedTap.enables == 0,
                     "a disabled notification never re-arms a revoked grant")
        denied.syncMiddleTap()
        suite.expect(denied.middleTap == nil && !deniedTap.valid, "passive sync removes a revoked disabled tap")
        Permissions.shared.accessibility = true
        let off = Host()
        off.installMiddleTap()
        let offTap = off.middleTap!
        off.settings = .init(hold: .screenshot)
        offTap.enabled = false
        off.handleMiddleTap(type: .tapDisabledByTimeout, event: middleEvent(.otherMouseUp, x: 120))
        suite.expect(offTap.enables == 0, "a disabled notification never restores an unassigned middle tap")
        off.syncMiddleTap()
        suite.expect(off.middleTap == nil && Permissions.shared.requests == 0,
                     "tap recovery and teardown never prompt for permission")
    }

    private static func testWindowOwnershipAndTopEdge(_ suite: TestSuite) {
        WindowServerSupport.receivingWindowNumber = 42
        let top = CGPoint(x: 120, y: 312)
        let host = Host()
        host.handleMiddleTap(type: .otherMouseDown, event: middleEvent(.otherMouseDown, x: top.x, y: 488))
        host.handleMiddleTap(type: .otherMouseUp, event: middleEvent(.otherMouseUp, x: top.x, y: 488))
        suite.expect(host.results == [.quick(.keepAwake)], "middle-click accepts the exact top row of the icon")
        NSEvent.mouseLocation = top
        NSEvent.pressedMouseButtons = 1
        host.observe(NSEvent(type: .leftMouseDown, timestamp: 340))
        NSEvent.pressedMouseButtons = 0
        ProcessInfo.processInfo.systemUptime = 341
        host.timer?.fire()
        suite.expect(host.results == [.quick(.keepAwake), .quick(.screenshot)],
                     "a monitored left hold starting on the top row works with release-time button actions")
        // A press counts over the bar's height above the button, never beside it.
        let above = Host()
        NSEvent.mouseLocation = CGPoint(x: 120, y: 316)
        NSEvent.pressedMouseButtons = 1
        above.observe(NSEvent(type: .leftMouseDown, timestamp: 345))
        suite.expect(above.gesture.watchesForRelease, "a press above the button's top edge is still on the icon")
        above.cancel()
        NSEvent.pressedMouseButtons = 0
        let beside = Host()
        beside.handleMiddleTap(type: .otherMouseDown, event: middleEvent(.otherMouseDown, x: 103))
        beside.handleMiddleTap(type: .otherMouseUp, event: middleEvent(.otherMouseUp, x: 103))
        suite.expect(beside.results.isEmpty, "a middle click just beside the icon is not on it")
        NSEvent.mouseLocation = CGPoint(x: 120, y: 300)
        for number in [0, 99] {
            WindowServerSupport.receivingWindowNumber = number
            let stranger = Host()
            stranger.handleMiddleTap(type: .otherMouseDown, event: middleEvent(.otherMouseDown, x: 120))
            stranger.handleMiddleTap(type: .otherMouseUp, event: middleEvent(.otherMouseUp, x: 120))
            suite.expect(stranger.results.isEmpty && !stranger.gesture.isActive,
                         "a matching stale frame never claims another or unknown window")
        }
        WindowServerSupport.receivingWindowNumber = 42
        for invalid in 0..<4 {
            let missing = Host()
            switch invalid {
            case 0: missing.owner?.statusItem = nil
            case 1: missing.owner?.statusItem?.isVisible = false
            case 2: missing.owner?.statusItem?.button?.window = nil
            default: missing.owner?.statusItem?.button?.window?.windowNumber = 0
            }
            missing.handleMiddleTap(type: .otherMouseDown, event: middleEvent(.otherMouseDown, x: 120))
            missing.handleMiddleTap(type: .otherMouseUp, event: middleEvent(.otherMouseUp, x: 120))
            suite.expect(missing.results.isEmpty, "missing, hidden or unplaced status windows fail closed")
        }
        let changed = Host()
        changed.handleMiddleTap(type: .otherMouseDown, event: middleEvent(.otherMouseDown, x: 120))
        WindowServerSupport.receivingWindowNumber = 99
        changed.handleMiddleTap(type: .otherMouseUp, event: middleEvent(.otherMouseUp, x: 120))
        WindowServerSupport.receivingWindowNumber = 42
        changed.handleMiddleTap(type: .otherMouseUp, event: middleEvent(.otherMouseUp, x: 120))
        suite.expect(changed.results.isEmpty && !changed.gesture.isActive,
                     "ownership lost at release cannot be completed by a later inside release")
        NSEvent.pressedMouseButtons = 1
        changed.observe(NSEvent(type: .leftMouseDown, timestamp: 350))
        WindowServerSupport.receivingWindowNumber = 99
        changed.handleMiddleTap(type: .otherMouseUp, event: middleEvent(.otherMouseUp, x: 120))
        suite.expect(changed.gesture.watchesForRelease, "rejected middle ownership does not cancel a left hold")
        changed.cancel()
        NSEvent.pressedMouseButtons = 0
        WindowServerSupport.receivingWindowNumber = 42
    }

    private static func testControllerActivation(_ suite: TestSuite) {
        let controller = ControllerHost()
        let host = Host()
        host.settings = .init(hold: .keepAwake)
        controller.gestureHandler = host
        NSEvent.mouseLocation = CGPoint(x: 120, y: 300)
        NSEvent.pressedMouseButtons = 1
        host.observe(NSEvent(type: .leftMouseDown, timestamp: 400))
        NSEvent.pressedMouseButtons = 0
        ProcessInfo.processInfo.systemUptime = 401
        NSApp.currentEvent = NSEvent(timestamp: 401)
        controller.clicked()
        suite.expect(host.results == [.quick(.keepAwake)], "controller dispatch completes a physical hold once")
        controller.clicked()
        suite.expect(host.results == [.quick(.keepAwake)] && controller.leftClicks == 0,
                     "a fresh already handled physical release stays deduplicated")
        ProcessInfo.processInfo.systemUptime = 402
        controller.clicked()
        controller.clicked()
        suite.expect(controller.leftClicks == 2 && host.results == [.quick(.keepAwake)],
                     "repeated accessibility activation after a hold ignores the old mouse-up and opens normally")
        for event in [nil, NSEvent(type: .keyDown, timestamp: 402),
                      NSEvent(timestamp: 402 - StatusItemAnchorSupport.statusClickFreshness - 0.01),
                      NSEvent(timestamp: 403)] {
            NSApp.currentEvent = event
            let before = controller.leftClicks
            controller.clicked()
            suite.expect(controller.leftClicks == before + 1,
                         "missing, keyboard, stale and future events remain plain accessibility activation")
        }
        // Right clicks route exactly as they do with no gesture assigned.
        for timestamp in [402.0, 400.0] {
            NSApp.currentEvent = NSEvent(type: .rightMouseUp, timestamp: timestamp)
            let before = controller.leftClicks
            controller.clicked()
            suite.expect(controller.leftClicks == before,
                         "a right click never opens the panel, however old its event")
        }
        suite.expect(controller.rightClicks == 2, "a physical right click still opens the context menu")
        NSApp.currentEvent = NSEvent(timestamp: 402)
        controller.clicked()
        suite.expect(host.results == [.quick(.keepAwake), .single(CGPoint(x: 120, y: 300))],
                     "a fresh newer physical release is not blocked by accessibility fallback")
        host.settings = .init(middle: .keepAwake)
        NSApp.currentEvent = NSEvent(timestamp: 402)
        let before = controller.leftClicks
        controller.clicked()
        suite.expect(controller.leftClicks == before + 1, "middle-only controller actions bypass the left gesture")
        host.frame = nil
        host.settings = .init(hold: .keepAwake)
        NSApp.currentEvent = NSEvent(timestamp: 402.1)
        ProcessInfo.processInfo.systemUptime = 402.1
        controller.clicked()
        suite.expect(controller.leftClicks == before + 2, "unknown left geometry still falls back to the panel")
        NSApp.currentEvent = nil
    }

    /// The freshness window is shared with the panel's anchor capture and is
    /// inclusive at its edge: inside it, a release a hold already handled
    /// stays the duplicate it is; just past it the activation opens the panel
    /// like any other click.
    private static func testClickFreshnessBoundary(_ suite: TestSuite) {
        let freshness = StatusItemAnchorSupport.statusClickFreshness
        for (age, opens) in [(freshness - 0.01, false), (freshness, false), (freshness + 0.01, true)] {
            let controller = ControllerHost()
            let host = Host()
            host.settings = .init(hold: .keepAwake)
            controller.gestureHandler = host
            NSEvent.mouseLocation = CGPoint(x: 120, y: 300)
            NSEvent.pressedMouseButtons = 1
            host.observe(NSEvent(type: .leftMouseDown, timestamp: 499.4))
            NSEvent.pressedMouseButtons = 0
            ProcessInfo.processInfo.systemUptime = 500
            host.timer?.fire()
            suite.expect(host.results == [.quick(.keepAwake)],
                         "the hold runs before the freshness boundary is judged")
            // The press's own action arrives with its release.
            NSApp.currentEvent = NSEvent(timestamp: 500)
            controller.clicked()
            ProcessInfo.processInfo.systemUptime = 500 + age
            NSApp.currentEvent = NSEvent(timestamp: 500)
            controller.clicked()
            suite.expect(controller.leftClicks == (opens ? 1 : 0)
                         && host.results == [.quick(.keepAwake)],
                         "a handled release at age \(age) \(opens ? "opens" : "stays handled")")
        }
        NSApp.currentEvent = nil
    }

}

extension StatusItemGestureAdapterTests {
    private static func testPermissionChanges(_ suite: TestSuite) {
        Permissions.shared.accessibility = false
        Permissions.shared.requests = 0
        let host = Host()
        host.watchAccessibility()
        let assigned = host.settings
        host.settings = .init(hold: .screenshot)
        host.sync(settings: assigned)
        suite.expect(host.middleTap == nil && Permissions.shared.requests == 0,
                     "syncing saved middle-click settings never requests permission")
        Permissions.shared.accessibility = true
        suite.expect(host.middleTap != nil && host.installations == 1,
                     "granting permission installs the tap without reassigning the action")
        Permissions.shared.accessibility = true
        host.sync(settings: host.settings)
        suite.expect(host.installations == 1, "unchanged settings or grants never duplicate a tap")
        host.handleMiddleTap(type: .otherMouseDown, event: middleEvent(.otherMouseDown, x: 120))
        Permissions.shared.accessibility = false
        suite.expect(host.middleTap == nil && host.removals == 1 && !host.gesture.isActive,
                     "revocation removes the tap and clears an in-flight middle press")
        suite.expect(Permissions.shared.requests == 0, "revocation never opens the permission prompt")
        Permissions.shared.accessibility = true
        suite.expect(host.installations == 2, "regranting permission restores the tap")
        host.sync(settings: .init(hold: .screenshot))
        Permissions.shared.accessibility = false
        Permissions.shared.accessibility = true
        suite.expect(host.middleTap == nil && host.installations == 2,
                     "hold-only settings never install a middle tap on permission changes")

        Permissions.shared.requests = 0
        let alreadyGranted = Host()
        alreadyGranted.watchAccessibility()
        alreadyGranted.sync(settings: alreadyGranted.settings)
        Permissions.shared.accessibility = false
        suite.expect(alreadyGranted.middleTap == nil && Permissions.shared.requests == 0,
                     "revoking a preexisting grant tears down quietly, without a new prompt")
        alreadyGranted.sync(settings: alreadyGranted.settings)
        alreadyGranted.sync(settings: alreadyGranted.settings)
        suite.expect(alreadyGranted.middleTap == nil && Permissions.shared.requests == 0,
                     "unrelated settings changes after revocation do not reopen the permission guide")
        Permissions.shared.accessibility = true
        suite.expect(alreadyGranted.middleTap != nil && alreadyGranted.installations == 2,
                     "regranting a preexisting permission restores the tap without a prompt")
        alreadyGranted.tearDownMiddleTap()
        alreadyGranted.sync(settings: alreadyGranted.settings)
        suite.expect(alreadyGranted.middleTap != nil && alreadyGranted.installations == 3
                     && Permissions.shared.requests == 0,
                     "unchanged settings still retry a missing tap silently when permission is available")
    }
}

// OS-boundary overloads only. Production recovery methods compile unchanged.
extension CGEvent {
    static func tapIsEnabled(tap: StatusItemGestureAdapterTests.Tap) -> Bool { tap.enabled }
    static func tapEnable(tap: StatusItemGestureAdapterTests.Tap, enable: Bool) {
        tap.enabled = enable
        if enable { tap.enables += 1 }
    }
}

extension StatusItemGestureAdapterTests {
    /// A busy main thread can deliver the button action after the freshness
    /// window. If the monitor already started that press, the action still
    /// belongs to it: one press, one outcome.
    private static func testLateButtonAction(_ suite: TestSuite) {
        let point = CGPoint(x: 120, y: 300)
        // Released during the stall after a click or a hold, or still held.
        for (released, stillHeld) in [(700.1, false), (700.6, false), (700.9, true)] {
            let controller = ControllerHost()
            let host = Host()
            controller.gestureHandler = host
            NSEvent.mouseLocation = point
            NSEvent.pressedMouseButtons = 1
            host.observe(NSEvent(type: .leftMouseDown, timestamp: 700))
            NSEvent.pressedMouseButtons = stillHeld ? 1 : 0
            if !stillHeld { CGEventSource.releasedAt = released }
            ProcessInfo.processInfo.systemUptime = 700.7
            // The action carries the press time, as it does where the button
            // reports its press.
            NSApp.currentEvent = NSEvent(timestamp: 700)
            controller.clicked()
            NSEvent.pressedMouseButtons = 0
            ProcessInfo.processInfo.systemUptime = 701
            CGEventSource.releasedAt = released
            host.timer?.fire()
            host.observe(NSEvent(timestamp: released))
            let expected: StatusItemGesture.Result = released - 700 < 0.5 ? .single(point) : .quick(.screenshot)
            suite.expect(host.results == [expected] && controller.leftClicks == 0 && host.timer == nil,
                         "a late action for a monitored press is judged by its release at \(released)")
            CGEventSource.releasedAt = nil
        }

        let stray = ControllerHost()
        let host = Host()
        stray.gestureHandler = host
        NSEvent.pressedMouseButtons = 1
        host.observe(NSEvent(type: .leftMouseDown, timestamp: 710))
        ProcessInfo.processInfo.systemUptime = 711
        NSApp.currentEvent = NSEvent(timestamp: 705)
        stray.clicked()
        NSEvent.pressedMouseButtons = 0
        host.timer?.fire()
        suite.expect(stray.leftClicks == 1 && host.results.isEmpty && host.timer == nil,
                     "an older event than the press in flight opens the panel and ends that press")
        NSApp.currentEvent = nil
    }

    /// The monitor cancels a Command or Control press. The button action for
    /// that same press must not start it again.
    private static func testModifiedPress(_ suite: TestSuite) {
        for flag in [AppKit.NSEvent.ModifierFlags.control, .command] {
            let controller = ControllerHost()
            let host = Host()
            controller.gestureHandler = host
            NSEvent.mouseLocation = CGPoint(x: 120, y: 300)
            NSEvent.pressedMouseButtons = 1
            host.observe(NSEvent(type: .leftMouseDown, timestamp: 720, modifierFlags: flag))
            ProcessInfo.processInfo.systemUptime = 720
            NSApp.currentEvent = NSEvent(timestamp: 720, modifierFlags: flag)
            controller.clicked()
            suite.expect(controller.leftClicks == 1 && host.timer == nil && !host.gesture.isActive,
                         "a modified press opens the panel as before and starts no hold")
            NSEvent.pressedMouseButtons = 0
            ProcessInfo.processInfo.systemUptime = 721
            host.timer?.fire()
            suite.expect(host.results.isEmpty, "a modified press held past the threshold runs nothing")
        }

        // The press-time action may carry no modifiers of its own; the
        // monitor's refusal still holds for that same press.
        let unflagged = Host()
        NSEvent.pressedMouseButtons = 1
        unflagged.observe(NSEvent(type: .leftMouseDown, timestamp: 725, modifierFlags: .control))
        suite.expect(!unflagged.buttonClick(NSEvent(timestamp: 725)) && unflagged.timer == nil,
                     "a refused press is not started again by its own unmodified action")
        suite.expect(unflagged.buttonClick(NSEvent(timestamp: 726)) && unflagged.gesture.watchesForRelease,
                     "the next press is accepted")
        unflagged.cancel()

        // A modifier pressed during the hold, seen only on the release action.
        let host = Host()
        NSEvent.pressedMouseButtons = 1
        host.observe(NSEvent(type: .leftMouseDown, timestamp: 730))
        NSEvent.pressedMouseButtons = 0
        ProcessInfo.processInfo.systemUptime = 730.1
        suite.expect(!host.buttonClick(NSEvent(timestamp: 730.1, modifierFlags: .control))
                     && host.timer == nil && !host.gesture.isActive,
                     "a click handed back to the normal path ends the press it was part of")
        host.timer?.fire()
        suite.expect(host.results.isEmpty, "that press then has no second outcome")
    }

    /// A middle press waiting on the icon is not a left press. A left click
    /// whose down the monitor missed still starts its own press and watcher.
    private static func testMissingDownBesideMiddle(_ suite: TestSuite) {
        let point = CGPoint(x: 120, y: 300)
        for held in [true, false] {
            let host = Host()
            host.handleMiddleTap(type: .otherMouseDown, event: middleEvent(.otherMouseDown, x: 120))
            NSEvent.mouseLocation = point
            NSEvent.pressedMouseButtons = held ? 1 : 0
            ProcessInfo.processInfo.systemUptime = 740.1
            suite.expect(host.buttonClick(NSEvent(timestamp: 740.1)), "the left click is claimed")
            if held {
                suite.expect(host.gesture.watchesForRelease && host.timer?.isValid == true,
                             "a held left press gets its watcher beside a pending middle press")
                NSEvent.pressedMouseButtons = 0
                host.timer?.fire()
            }
            host.handleMiddleTap(type: .otherMouseUp, event: middleEvent(.otherMouseUp, x: 120))
            suite.expect(host.results == [.single(point)],
                         "the left click opens the panel once and the stale middle press runs nothing")
        }
    }

    /// The Cleaning Mode overlay covers the menu bar. A press on it is not a
    /// press on the icon, even where the points line up.
    private static func testPressOnOwnWindow(_ suite: TestSuite) {
        let point = CGPoint(x: 120, y: 300)
        for duration in [0.1, 1.0] {
            let host = Host()
            NSEvent.mouseLocation = point
            NSEvent.pressedMouseButtons = 1
            host.observe(NSEvent(type: .leftMouseDown, timestamp: 750, window: Window(windowNumber: 99)))
            suite.expect(!host.gesture.isActive && host.timer == nil,
                         "a press on another window of this app starts nothing")
            NSEvent.pressedMouseButtons = 0
            ProcessInfo.processInfo.systemUptime = 750 + duration
            host.observe(NSEvent(timestamp: 750 + duration, window: Window(windowNumber: 99)))
            suite.expect(host.results.isEmpty, "and its release runs nothing (held \(duration))")
        }
        let host = Host()
        NSEvent.pressedMouseButtons = 1
        host.observe(NSEvent(type: .leftMouseDown, timestamp: 760, window: Window()))
        suite.expect(host.gesture.watchesForRelease, "a press on the icon's own window is still watched")
        host.cancel()
        NSEvent.pressedMouseButtons = 0
    }

    /// The watcher samples every 40 ms and can run late. A short click is
    /// judged by when the button came up, not by when the tick noticed.
    private static func testLateReleaseTick(_ suite: TestSuite) {
        let point = CGPoint(x: 120, y: 300)
        for (released, expected) in [(770.1, StatusItemGesture.Result.single(point)),
                                     (770.8, .quick(.screenshot))] {
            let host = Host()
            NSEvent.mouseLocation = point
            NSEvent.pressedMouseButtons = 1
            host.observe(NSEvent(type: .leftMouseDown, timestamp: 770))
            NSEvent.pressedMouseButtons = 0
            CGEventSource.releasedAt = released
            ProcessInfo.processInfo.systemUptime = 770.9
            host.timer?.fire()
            suite.expect(host.results == [expected],
                         "a late tick judges the release at \(released), not at 770.9")
            _ = host.buttonClick(NSEvent(timestamp: released))
            suite.expect(host.results == [expected], "the release-time action stays a duplicate")
        }
        let host = Host()
        NSEvent.pressedMouseButtons = 1
        host.observe(NSEvent(type: .leftMouseDown, timestamp: 780))
        NSEvent.pressedMouseButtons = 0
        CGEventSource.releasedAt = 779
        ProcessInfo.processInfo.systemUptime = 780.9
        host.timer?.fire()
        suite.expect(host.results == [.single(point)],
                     "a recorded release older than the press never stretches it into a hold")

        // A second click before the late tick: the last release is its own.
        let twice = Host()
        NSEvent.pressedMouseButtons = 1
        twice.observe(NSEvent(type: .leftMouseDown, timestamp: 790))
        NSEvent.pressedMouseButtons = 0
        CGEventSource.pressedAt = 790.2
        CGEventSource.releasedAt = 790.6
        ProcessInfo.processInfo.systemUptime = 790.9
        twice.timer?.fire()
        suite.expect(twice.results == [.single(point)],
                     "a later click's release never stretches an earlier click into a hold")
        CGEventSource.releasedAt = nil
        CGEventSource.pressedAt = nil
    }

    /// The icon's half-width is the drift a held press may make. Leaving it,
    /// or a right click, ends the press with no outcome.
    private static func testDragAndCancel(_ suite: TestSuite) {
        let start = CGPoint(x: 120, y: 300)
        // The fixture icon spans 105...135 x 288...312: a 12 pt drift is past
        // the old 4 pt box and still on it; 140 is off it.
        let drift = CGPoint(x: 132, y: 308)
        let away = CGPoint(x: 140, y: 300)

        let dragged = Host()
        NSEvent.mouseLocation = start
        NSEvent.pressedMouseButtons = 1
        dragged.observe(NSEvent(type: .leftMouseDown, timestamp: 800))
        NSEvent.mouseLocation = drift
        dragged.observe(NSEvent(type: .leftMouseDragged, timestamp: 800.3))
        ProcessInfo.processInfo.systemUptime = 800.6
        dragged.timer?.fire()
        NSEvent.pressedMouseButtons = 0
        ProcessInfo.processInfo.systemUptime = 801
        dragged.timer?.fire()
        suite.expect(dragged.results == [.quick(.screenshot)],
                     "a drag that stays on the icon keeps the hold")

        // Drift the watcher alone sees, into the slack just past the edge.
        let drifted = Host()
        NSEvent.mouseLocation = start
        NSEvent.pressedMouseButtons = 1
        drifted.observe(NSEvent(type: .leftMouseDown, timestamp: 810))
        NSEvent.mouseLocation = CGPoint(x: 137, y: 314)
        ProcessInfo.processInfo.systemUptime = 810.6
        drifted.timer?.fire()
        NSEvent.pressedMouseButtons = 0
        ProcessInfo.processInfo.systemUptime = 811
        drifted.timer?.fire()
        suite.expect(drifted.results == [.quick(.screenshot)],
                     "a hold held just past the icon's edge still commits")

        let left = Host()
        NSEvent.mouseLocation = start
        NSEvent.pressedMouseButtons = 1
        left.observe(NSEvent(type: .leftMouseDown, timestamp: 820))
        NSEvent.mouseLocation = away
        left.observe(NSEvent(type: .leftMouseDragged, timestamp: 820.3))
        suite.expect(!left.gesture.isActive && left.timer == nil, "dragging off the icon cancels the press")
        NSEvent.pressedMouseButtons = 0
        ProcessInfo.processInfo.systemUptime = 821
        left.observe(NSEvent(timestamp: 821))
        suite.expect(left.results.isEmpty, "a release after dragging away runs nothing")

        let right = Host()
        NSEvent.mouseLocation = start
        NSEvent.pressedMouseButtons = 1
        right.observe(NSEvent(type: .leftMouseDown, timestamp: 830))
        ProcessInfo.processInfo.systemUptime = 830.6
        right.timer?.fire()
        right.observe(NSEvent(type: .rightMouseDown, timestamp: 830.7))
        NSEvent.pressedMouseButtons = 0
        ProcessInfo.processInfo.systemUptime = 831
        right.timer?.fire()
        right.observe(NSEvent(timestamp: 831))
        suite.expect(right.results.isEmpty && right.timer == nil, "a right click cancels a hold in flight")

        let middle = Host()
        middle.handleMiddleTap(type: .otherMouseDown, event: middleEvent(.otherMouseDown, x: 120))
        middle.handleMiddleTap(type: .otherMouseUp, event: middleEvent(.otherMouseUp, x: 132))
        suite.expect(middle.results == [.quick(.keepAwake)],
                     "a middle release that drifted within the icon still fires")
        NSEvent.mouseLocation = start
    }
}

extension StatusItemGestureAdapterTests {
    /// The watcher can end a press before its release-time action is
    /// dequeued. If a busy main thread then delivers that action late, it is
    /// still the same press: one outcome. Once that action has arrived, the
    /// same old event is an accessibility press again.
    private static func testLateActionAfterRelease(_ suite: TestSuite) {
        let point = CGPoint(x: 120, y: 300)
        let controller = ControllerHost()
        let host = Host()
        controller.gestureHandler = host
        NSEvent.mouseLocation = point
        NSEvent.pressedMouseButtons = 1
        host.observe(NSEvent(type: .leftMouseDown, timestamp: 850))
        NSEvent.pressedMouseButtons = 0
        CGEventSource.releasedAt = 850.1
        ProcessInfo.processInfo.systemUptime = 850.14
        host.timer?.fire()
        suite.expect(host.results == [.single(point)], "the watcher ends the click")
        ProcessInfo.processInfo.systemUptime = 851
        NSApp.currentEvent = NSEvent(timestamp: 850.1)
        controller.clicked()
        suite.expect(host.results == [.single(point)] && controller.leftClicks == 0,
                     "the click's own late action does not open or close the panel again")
        controller.clicked()
        suite.expect(controller.leftClicks == 1, "after that, the old event is a plain activation")

        let unanswered = ControllerHost()
        let quiet = Host()
        unanswered.gestureHandler = quiet
        NSEvent.pressedMouseButtons = 1
        quiet.observe(NSEvent(type: .leftMouseDown, timestamp: 860))
        NSEvent.pressedMouseButtons = 0
        CGEventSource.releasedAt = 860.1
        ProcessInfo.processInfo.systemUptime = 860.14
        quiet.timer?.fire()
        ProcessInfo.processInfo.systemUptime = 863
        NSApp.currentEvent = NSEvent(timestamp: 860.1)
        unanswered.clicked()
        suite.expect(unanswered.leftClicks == 1,
                     "an action that never came stops holding back an accessibility press")
        CGEventSource.releasedAt = nil
        NSApp.currentEvent = nil
    }

    /// The watcher sees a release on its next tick. Where the pointer went
    /// after the release does not decide whether the press was on the icon.
    private static func testReleaseWhereHeld(_ suite: TestSuite) {
        let point = CGPoint(x: 120, y: 300)
        let below = CGPoint(x: 120, y: 260)
        for (duration, expected) in [(0.1, StatusItemGesture.Result.single(point)), (0.7, .quick(.screenshot))] {
            let host = Host()
            NSEvent.mouseLocation = point
            NSEvent.pressedMouseButtons = 1
            host.observe(NSEvent(type: .leftMouseDown, timestamp: 870))
            ProcessInfo.processInfo.systemUptime = 870 + duration - 0.02
            host.timer?.fire()
            NSEvent.pressedMouseButtons = 0
            NSEvent.mouseLocation = below
            CGEventSource.releasedAt = 870 + duration
            ProcessInfo.processInfo.systemUptime = 870 + duration + 0.03
            host.timer?.fire()
            suite.expect(host.results == [expected],
                         "a release judged where the press was held (\(duration) s), not where the pointer went")
        }
        let host = Host()
        NSEvent.mouseLocation = point
        NSEvent.pressedMouseButtons = 1
        host.observe(NSEvent(type: .leftMouseDown, timestamp: 880))
        NSEvent.mouseLocation = below
        ProcessInfo.processInfo.systemUptime = 880.3
        host.timer?.fire()
        suite.expect(!host.gesture.isActive && host.timer == nil,
                     "the watcher cancels a press held off the icon")
        NSEvent.pressedMouseButtons = 0
        NSEvent.mouseLocation = point
        ProcessInfo.processInfo.systemUptime = 880.6
        host.timer?.fire()
        suite.expect(host.results.isEmpty, "and its release runs nothing")
        CGEventSource.releasedAt = nil
    }

    /// A middle press on the icon while the left button is down leaves the
    /// left press, which the button has already taken, to finish.
    private static func testMiddleDuringLeftPress(_ suite: TestSuite) {
        let point = CGPoint(x: 120, y: 300)
        for actionAtPress in [false, true] {
            let host = Host()
            NSEvent.mouseLocation = point
            NSEvent.pressedMouseButtons = 1
            host.observe(NSEvent(type: .leftMouseDown, timestamp: 890))
            if actionAtPress { _ = host.buttonClick(NSEvent(timestamp: 890)) }
            host.handleMiddleTap(type: .otherMouseDown, event: middleEvent(.otherMouseDown, x: 120))
            suite.expect(host.gesture.watchesForRelease && host.timer?.isValid == true,
                         "a middle press keeps the left press and its watcher")
            host.handleMiddleTap(type: .otherMouseUp, event: middleEvent(.otherMouseUp, x: 120))
            NSEvent.pressedMouseButtons = 0
            ProcessInfo.processInfo.systemUptime = 890.1
            host.timer?.fire()
            if !actionAtPress { _ = host.buttonClick(NSEvent(timestamp: 890.1)) }
            suite.expect(host.results == [.single(point)],
                         "the left click opens the panel once and the middle press runs nothing")
        }
    }

    /// Where the system draws the menu bar itself, the button's window is no
    /// window-server window and a click lands on the bar's own window, or on
    /// none. Only Accessibility can then say the item is this button. It is
    /// asked at the button's middle row, so the screen's top row counts.
    private static func testSystemHostedMenuBar(_ suite: TestSuite) {
        let systemBar = 30967
        Permissions.shared.accessibility = true
        for receiving in [systemBar, 0] {
            WindowServerSupport.receivingWindowNumber = receiving
            WindowServerSupport.menuBars = [CGWindowID(systemBar)]
            for names in [true, false] {
                let host = Host()
                host.owner?.statusItem?.button?.window?.windowNumber = 1 << 32
                host.accessibilityNamesButton = names
                // The screen's top row, above the 312 pt top of the button.
                host.handleMiddleTap(type: .otherMouseDown, event: middleEvent(.otherMouseDown, x: 120, y: 484))
                host.handleMiddleTap(type: .otherMouseUp, event: middleEvent(.otherMouseUp, x: 120, y: 484))
                suite.expect(host.results == (names ? [.quick(.keepAwake)] : []),
                             "a system-drawn bar defers to Accessibility (window \(receiving), names \(names))")
                suite.expect(host.accessibilityQueries.allSatisfy { $0 == CGPoint(x: 120, y: 500) }
                             && WindowServerSupport.lastPoint == CGPoint(x: 120, y: 484),
                             "the window server is asked where the click was, Accessibility at the button's middle")
            }
        }

        // Any other window over the bar, this app's own Cleaning Mode overlay
        // included, takes the click itself; nobody is asked.
        WindowServerSupport.receivingWindowNumber = 77
        let overlay = Host()
        overlay.accessibilityNamesButton = true
        overlay.handleMiddleTap(type: .otherMouseDown, event: middleEvent(.otherMouseDown, x: 120))
        overlay.handleMiddleTap(type: .otherMouseUp, event: middleEvent(.otherMouseUp, x: 120))
        suite.expect(overlay.results.isEmpty && overlay.accessibilityQueries.isEmpty,
                     "a middle click on another window runs nothing and asks nobody")

        // Without the grant, the hit test would hang inside the tap.
        WindowServerSupport.receivingWindowNumber = 0
        Permissions.shared.accessibility = false
        let revoked = Host()
        revoked.accessibilityNamesButton = true
        revoked.handleMiddleTap(type: .otherMouseDown, event: middleEvent(.otherMouseDown, x: 120))
        suite.expect(revoked.results.isEmpty && revoked.accessibilityQueries.isEmpty,
                     "a revoked grant never reaches Accessibility from the tap")

        // A release with no press waiting asks nobody.
        Permissions.shared.accessibility = true
        let idle = Host()
        idle.owner?.statusItem?.button?.window?.windowNumber = 1 << 32
        idle.accessibilityNamesButton = true
        idle.handleMiddleTap(type: .otherMouseUp, event: middleEvent(.otherMouseUp, x: 120))
        suite.expect(idle.results.isEmpty && idle.accessibilityQueries.isEmpty,
                     "a stray middle release asks nothing")
        Permissions.shared.accessibility = false
        WindowServerSupport.receivingWindowNumber = 42
        WindowServerSupport.menuBars = []
    }

    /// The dispatcher runs each action through its own feature, and only
    /// while that feature is installed. A capture waits for the panel to
    /// close, so it cannot photograph it.
    private static func testActionDispatch(_ suite: TestSuite) {
        _ = installingEveryFeature(in: DispatchFixture.defaults)
        let services: [StatusItemQuickAction: String] = [
            .keepAwake: "keepAwake", .micMute: "micMute", .screenRecorder: "screenRecorder",
            .screenshot: "screenshot",
        ]
        for (action, service) in services {
            let host = DispatchHost()
            Service.calls = []
            host.performStatusItemAction(action)
            let waits = action == .screenshot || action == .screenRecorder
            suite.expect(Service.calls == (waits ? [] : [service]) && (host.pendingClose != nil) == waits,
                         "\(action.rawValue) runs at once unless it captures the screen")
            host.pendingClose?()
            suite.expect(Service.calls == [service] && host.failures.isEmpty,
                         "\(action.rawValue) runs its own feature exactly once")

            DispatchFixture.defaults.set(false, forKey: action.feature.availabilityKey)
            Service.calls = []
            host.performStatusItemAction(action)
            host.pendingClose?()
            suite.expect(Service.calls.isEmpty && host.failures == [action.symbolName],
                         "an uninstalled \(action.rawValue) runs nothing and says so")
        }

        let sound = DispatchHost()
        Service.calls = []
        AppVolumeMixer.muted = false
        sound.performStatusItemAction(.soundMute)
        AppVolumeMixer.muted = true
        sound.performStatusItemAction(.soundMute)
        AppVolumeMixer.muted = nil
        sound.performStatusItemAction(.soundMute)
        suite.expect(Service.calls == ["mute", "unmute"] && sound.failures == ["speaker.slash"],
                     "sound mute flips the state read at the gesture, and an unreadable state says so")
        let none = DispatchHost()
        Service.calls = []
        none.performStatusItemAction(.none)
        suite.expect(Service.calls.isEmpty && none.failures.isEmpty && none.pendingClose == nil,
                     "Off runs nothing")
        Service.calls = []
        DispatchFixture.defaults.removePersistentDomain(forName: "vorss.tests.status-action-dispatch")
    }
}

extension StatusItemGestureAdapterTests {
    /// A permission reset takes the tap down with the other input taps.
    /// Nothing brings it back until the reset ends: not a settings sync, a
    /// grant change or a disabled-tap notice.
    private static func testSuspendedTap(_ suite: TestSuite) {
        Permissions.shared.accessibility = true
        let host = Host()
        host.watchAccessibility()
        host.syncMiddleTap()
        let tap = host.middleTap
        host.owner?.gestureTapSuspended = true
        host.sync(settings: host.settings)
        suite.expect(host.middleTap == nil && tap?.valid == false, "suspension removes the tap")
        host.sync(settings: host.settings)
        Permissions.shared.accessibility = false
        Permissions.shared.accessibility = true
        host.handleMiddleTap(type: .tapDisabledByUserInput, event: middleEvent(.otherMouseUp, x: 120))
        host.syncMiddleTap() // what the notice defers to the main queue
        suite.expect(host.middleTap == nil && host.installations == 1,
                     "syncs, grant changes and disabled notices stay suspended")
        host.owner?.gestureTapSuspended = false
        host.sync(settings: host.settings)
        suite.expect(host.middleTap != nil && host.installations == 2, "the end of the reset restores the tap")
        Permissions.shared.accessibility = false
    }

    /// A press is claimed where the pointer is: AppKit places a status item
    /// press through the item's window, which macOS 27 can leave stranded
    /// away from the drawn icon. A release, which can be handled after the
    /// pointer moved on, counts where the press was last seen held.
    private static func testQueuedEventLocation(_ suite: TestSuite) {
        let point = CGPoint(x: 120, y: 300)
        let away = CGPoint(x: 120, y: 200)
        let monitored = Host()
        NSEvent.mouseLocation = point
        NSEvent.pressedMouseButtons = 1
        monitored.observe(NSEvent(type: .leftMouseDown, timestamp: 940))
        NSEvent.pressedMouseButtons = 0
        NSEvent.mouseLocation = away
        monitored.observe(NSEvent(timestamp: 940.1))
        suite.expect(monitored.results == [.single(point)],
                     "a queued release counts where the press was held, not where the pointer went")

        let acted = Host()
        NSEvent.mouseLocation = point
        NSEvent.pressedMouseButtons = 1
        acted.observe(NSEvent(type: .leftMouseDown, timestamp: 950))
        NSEvent.pressedMouseButtons = 0
        NSEvent.mouseLocation = away
        ProcessInfo.processInfo.systemUptime = 950.1
        suite.expect(acted.buttonClick(NSEvent(timestamp: 950.1)) && acted.results == [.single(point)],
                     "the button's own action finishes its press wherever the pointer went")

        // The item's frame is stranded far from where the icon is drawn and
        // clicked: the press is refused, and the normal click still runs.
        let controller = ControllerHost()
        let stranded = Host()
        controller.gestureHandler = stranded
        stranded.frame = CGRect(x: 805, y: 288, width: 30, height: 24)
        // AppKit places the relayed press inside the item's window.
        let relayed = CGEvent(mouseEventSource: nil, mouseType: .leftMouseDown,
                              mouseCursorPosition: CGPoint(x: 820, y: 500), mouseButton: .left)
        NSEvent.mouseLocation = point
        NSEvent.pressedMouseButtons = 1
        stranded.observe(NSEvent(type: .leftMouseDown, timestamp: 960, cgEvent: relayed))
        ProcessInfo.processInfo.systemUptime = 960
        NSApp.currentEvent = NSEvent(timestamp: 960, cgEvent: relayed)
        controller.clicked()
        suite.expect(!stranded.gesture.isActive && stranded.timer == nil && controller.leftClicks == 1,
                     "a stranded frame refuses the press and the panel still opens")
        NSEvent.pressedMouseButtons = 0
        NSApp.currentEvent = nil
    }

    /// Which time a release is judged by: the release action's own, or the
    /// event source's record; never a newer press's.
    private static func testReleaseTimeSources(_ suite: TestSuite) {
        let point = CGPoint(x: 120, y: 300)
        // A release action carries its exact time, even when the event source
        // already records a later press and its release.
        let controller = ControllerHost()
        let exact = Host()
        controller.gestureHandler = exact
        NSEvent.mouseLocation = point
        NSEvent.pressedMouseButtons = 1
        exact.observe(NSEvent(type: .leftMouseDown, timestamp: 970))
        NSEvent.pressedMouseButtons = 0
        CGEventSource.pressedAt = 970.8
        CGEventSource.releasedAt = 970.9
        ProcessInfo.processInfo.systemUptime = 971
        NSApp.currentEvent = NSEvent(timestamp: 970.7)
        controller.clicked()
        suite.expect(exact.results == [.quick(.screenshot)] && controller.leftClicks == 0,
                     "a release action's own time decides")

        // A press-time action delivered late, after a newer press and its
        // release: nothing past the press itself is assumed.
        let late = ControllerHost()
        let stalled = Host()
        late.gestureHandler = stalled
        NSEvent.pressedMouseButtons = 1
        stalled.observe(NSEvent(type: .leftMouseDown, timestamp: 975))
        NSEvent.pressedMouseButtons = 0
        CGEventSource.pressedAt = 975.6
        CGEventSource.releasedAt = 975.7
        ProcessInfo.processInfo.systemUptime = 975.8
        NSApp.currentEvent = NSEvent(timestamp: 975)
        late.clicked()
        suite.expect(stalled.results == [.single(point)] && late.leftClicks == 0,
                     "a later press's release never stretches this click into a hold")
        NSApp.currentEvent = nil
        CGEventSource.pressedAt = nil
        CGEventSource.releasedAt = nil

        // The press's own down is not a newer press.
        let own = Host()
        NSEvent.pressedMouseButtons = 1
        own.observe(NSEvent(type: .leftMouseDown, timestamp: 980))
        CGEventSource.pressedAt = 980
        ProcessInfo.processInfo.systemUptime = 980.6
        own.timer?.fire()
        NSEvent.pressedMouseButtons = 0
        CGEventSource.releasedAt = 980.7
        ProcessInfo.processInfo.systemUptime = 980.75
        own.timer?.fire()
        suite.expect(own.results == [.quick(.screenshot)], "a hold is not cut short by its own down")

        // A newer press held at the tick: this press came up before it.
        let newer = Host()
        NSEvent.pressedMouseButtons = 1
        newer.observe(NSEvent(type: .leftMouseDown, timestamp: 990))
        CGEventSource.pressedAt = 990.6
        CGEventSource.releasedAt = 990.3
        ProcessInfo.processInfo.systemUptime = 990.7
        newer.timer?.fire()
        suite.expect(newer.results == [.single(point)] && !newer.gesture.isActive,
                     "a newer press ends this one as the click it was, not a hold")
        _ = newer.buttonClick(NSEvent(timestamp: 990.3))
        suite.expect(newer.results == [.single(point)], "this press's late action stays its own")
        CGEventSource.releasedAt = nil
        CGEventSource.pressedAt = nil
        NSEvent.pressedMouseButtons = 0
    }

    /// A second press can begin before a tick saw the first come up. The
    /// first ends as the click it was, and the second starts on its own. A
    /// right click or a modified press right after a release does the same.
    private static func testSecondPress(_ suite: TestSuite) {
        let point = CGPoint(x: 120, y: 300)
        let host = Host()
        NSEvent.mouseLocation = point
        NSEvent.pressedMouseButtons = 1
        host.observe(NSEvent(type: .leftMouseDown, timestamp: 1000))
        ProcessInfo.processInfo.systemUptime = 1000
        _ = host.buttonClick(NSEvent(timestamp: 1000))
        host.observe(NSEvent(type: .leftMouseDown, timestamp: 1000.03))
        ProcessInfo.processInfo.systemUptime = 1000.03
        _ = host.buttonClick(NSEvent(timestamp: 1000.03))
        suite.expect(host.results == [.single(point)] && host.gesture.watchesForRelease,
                     "the first press opens the panel and the second is watched")
        NSEvent.pressedMouseButtons = 0
        ProcessInfo.processInfo.systemUptime = 1000.1
        host.timer?.fire()
        suite.expect(host.results == [.single(point), .single(point)], "the second press has its own outcome")

        for (type, flags) in [(AppKit.NSEvent.EventType.rightMouseDown, AppKit.NSEvent.ModifierFlags()),
                              (.leftMouseDown, .command)] {
            let next = Host()
            NSEvent.pressedMouseButtons = 1
            next.observe(NSEvent(type: .leftMouseDown, timestamp: 1010))
            ProcessInfo.processInfo.systemUptime = 1010
            _ = next.buttonClick(NSEvent(timestamp: 1010))
            NSEvent.pressedMouseButtons = type == .rightMouseDown ? 0 : 1
            next.observe(NSEvent(type: type, timestamp: 1010.03, modifierFlags: flags))
            suite.expect(next.results == [.single(point)] && !next.gesture.isActive,
                         "a click released just before a \(type == .rightMouseDown ? "right click" : "⌘ press") keeps its outcome")
        }
        NSEvent.pressedMouseButtons = 0
    }

    /// The panel anchors at the click. A release in the slack around the icon
    /// anchors it on the icon, never beside or above it.
    private static func testPanelAnchor(_ suite: TestSuite) {
        let host = Host()
        NSEvent.mouseLocation = CGPoint(x: 120, y: 300)
        NSEvent.pressedMouseButtons = 1
        host.observe(NSEvent(type: .leftMouseDown, timestamp: 1010))
        NSEvent.mouseLocation = CGPoint(x: 138, y: 318)
        ProcessInfo.processInfo.systemUptime = 1010.05
        host.timer?.fire()
        NSEvent.pressedMouseButtons = 0
        ProcessInfo.processInfo.systemUptime = 1010.1
        host.timer?.fire()
        suite.expect(host.results == [.single(CGPoint(x: 135, y: 312))],
                     "a release in the slack anchors the panel on the icon")
        NSEvent.mouseLocation = CGPoint(x: 120, y: 300)
    }
}
