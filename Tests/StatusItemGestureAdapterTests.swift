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
        var keyCode: UInt16 = 0
        var modifierFlags: AppKit.NSEvent.ModifierFlags = []
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
    enum NSWindow {
        static var receivingWindowNumber = 42
        static func windowNumber(at point: NSPoint, belowWindowWithWindowNumber: Int) -> Int {
            receivingWindowNumber
        }
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
        var owner: Owner? = Owner()
        var gesture = StatusItemGesture()
        var settings = StatusItemGesture.Settings(middle: .keepAwake, hold: .screenshot)
        var timer: Timer?
        var generation = 0
        var observedLeftDown: TimeInterval?
        var handledLeftRelease: TimeInterval?
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

    class SettingsFixture {
        var middleAction = StatusItemQuickAction.none.rawValue
        var permissions = Permissions.shared
    }

    class UsageFixture {
        struct Feature {
            func hubTitle(_ strings: Strings, hub: FeatureHubStrings) -> String { "Existing feature" }
        }
        var middleAction = StatusItemQuickAction.none.rawValue
        var permission = AppPermission.accessibility
        var activeFeatures: [Feature] = []
        let l10n = L10n.shared
        let hub = FeatureStrings.hub(.enUS)
    }

    class PollingFixture {
        let defaults = UserDefaults(suiteName: "vorss.tests.status-action-polling")!
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
            NSWindow.receivingWindowNumber = 42
            NSApp.currentEvent = nil
            ProcessInfo.processInfo.systemUptime = 0
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
                suite.expect(usage.usedByLine.contains("Menu bar icon quick actions — Middle-click"),
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
        suite.expect(revoked.gesture.phaseName == "held", "the watcher crosses the hold threshold before revocation")
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
        NSWindow.receivingWindowNumber = 42
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
        NSEvent.mouseLocation = CGPoint(x: 120, y: 300)
        for number in [0, 99] {
            NSWindow.receivingWindowNumber = number
            let stranger = Host()
            stranger.handleMiddleTap(type: .otherMouseDown, event: middleEvent(.otherMouseDown, x: 120))
            stranger.handleMiddleTap(type: .otherMouseUp, event: middleEvent(.otherMouseUp, x: 120))
            suite.expect(stranger.results.isEmpty && !stranger.gesture.isActive,
                         "a matching stale frame never claims another or unknown window")
        }
        NSWindow.receivingWindowNumber = 42
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
        NSWindow.receivingWindowNumber = 99
        changed.handleMiddleTap(type: .otherMouseUp, event: middleEvent(.otherMouseUp, x: 120))
        NSWindow.receivingWindowNumber = 42
        changed.handleMiddleTap(type: .otherMouseUp, event: middleEvent(.otherMouseUp, x: 120))
        suite.expect(changed.results.isEmpty && !changed.gesture.isActive,
                     "ownership lost at release cannot be completed by a later inside release")
        NSEvent.pressedMouseButtons = 1
        changed.observe(NSEvent(type: .leftMouseDown, timestamp: 350))
        NSWindow.receivingWindowNumber = 99
        changed.handleMiddleTap(type: .otherMouseUp, event: middleEvent(.otherMouseUp, x: 120))
        suite.expect(changed.gesture.watchesForRelease, "rejected middle ownership does not cancel a left hold")
        changed.cancel()
        NSEvent.pressedMouseButtons = 0
        NSWindow.receivingWindowNumber = 42
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
                      NSEvent(timestamp: 401.49), NSEvent(timestamp: 403),
                      NSEvent(type: .rightMouseUp, timestamp: 400)] {
            NSApp.currentEvent = event
            let before = controller.leftClicks
            controller.clicked()
            suite.expect(controller.leftClicks == before + 1,
                         "missing, keyboard, stale and future events remain plain accessibility activation")
        }
        NSApp.currentEvent = NSEvent(type: .rightMouseUp, timestamp: 402)
        controller.clicked()
        suite.expect(controller.rightClicks == 1, "a fresh physical right click still opens the context menu")
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
