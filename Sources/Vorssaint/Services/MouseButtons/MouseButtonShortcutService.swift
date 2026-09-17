// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import ApplicationServices
import Combine
import CoreGraphics

/// Types a keyboard shortcut when an extra mouse button is pressed. The
/// mapped button's click is the shortcut's alone: the whole gesture is
/// consumed, so the app under the pointer never sees the press it used to
/// get (the Settings caption promises exactly that). Nothing is installed
/// while the feature is off or while no button is mapped. Requires
/// Accessibility for the modifying event tap and the posted keys.
///
/// One button may instead hold and drag for Spaces and Mission Control
/// (issue #1012). That press is only held back, not taken: it becomes the
/// app's ordinary click again the moment the release arrives without the
/// pointer having gone anywhere. Same tap, because the drags it measures are
/// events this one already receives.
final class MouseButtonShortcutService: ObservableObject {
    static let shared = MouseButtonShortcutService()
    /// Marks the press this service hands back to the system, so the tap it
    /// re-enters does not take it straight back. The window gesture tags its
    /// own replayed presses the same way.
    private static let replayedPressMarker: Int64 = 0x564F5253
    /// Read by Smooth Scroll before it touches any side-wheel fields. False
    /// while this feature is off, unavailable, untrusted or has no wheel map.
    private(set) static var hasActiveSideWheelInterest = false

    /// True while the tap is up and the mapped buttons actually fire.
    @Published private(set) var isRunning = false
    /// The last extra button or side-wheel direction that arrived while
    /// Settings was asking for one. Nil means nothing has arrived yet.
    @Published private(set) var lastInputSeen: Int64?

    /// True while the Settings capture row is listening for a press. The
    /// other button-owning taps (navigation at the HID level, the radial
    /// menu's summoner) read this and let every extra button through, so the
    /// press being captured reaches this service instead of navigating or
    /// opening the wheel. Main thread only, like the taps that read it.
    private(set) static var isCaptureActive = false

    private var mappings: [Int64: GlobalShortcut] = [:]
    private var tap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var tapIncludesSideWheel = false
    /// Set only while the Settings capture row is on screen. The tap stays up
    /// during capture even with no mappings yet, so the row can see the press.
    private var isCapturing = false
    /// Buttons whose current press was consumed. The Up and Drag of a gesture
    /// must follow its Down: a mapping removed mid-press must not let half a
    /// gesture leak to the app underneath. Only touched from the tap
    /// callback, which runs on the main run loop.
    private var consumedButtons: Set<Int64> = []
    /// True while the tap only exists to swallow the pending Up of a button
    /// whose Down it consumed; no new press is claimed in this state.
    private var isDraining = false
    /// A tap whose event mask changed is rebuilt after its already-consumed
    /// buttons release. Rebuilding before then would leak unmatched Up events.
    private var restartAfterDrain = false
    /// Timestamp (ns, event clock) of the last touch gesture phase. This keeps
    /// side-wheel capture from claiming a trackpad's phaseless tail.
    private var lastGesturePhaseTimestamp: UInt64?
    private var wantsSideWheelEvents = false
    private var sideWheelGesture = MouseButtonShortcutSupport.SideWheelGestureGate()
    /// Smooth Scroll checks the exception before passing this exact event to
    /// the session tap. Matching its timestamp avoids doing that lookup twice.
    private var preflightedSideWheelTimestamp: UInt64?
    private var preflightedSideWheelInput: Int64?
    /// The button the Spaces and Mission Control drag is bound to, or nil.
    private var spacesButton: Int64?
    /// The held press being watched for such a drag. Only touched from the tap
    /// callback and from preference changes, both on the main thread.
    private var spacesGesture: SpacesGesturePress?

    /// A press on the bound button while it may still turn out to be a drag.
    /// The copy is what goes back to the app when it never does.
    private struct SpacesGesturePress {
        let button: Int64
        let down: CGEvent
        /// Read once, at the press: a direction flipped halfway through a drag
        /// would send the hand back over Spaces it just left.
        let followsDrag: Bool
        var tracker: MouseSpacesGestureSupport.Tracker
    }

    private init() {
        // A switched-away session cannot keep a filter tap alive just to drain
        // a button: WindowServer would make the session on screen wait for it.
        // Tear down immediately on resign and rebuild from preferences on return.
        SessionActivity.shared.onChange { [weak self] active in
            guard let self else { return }
            if active {
                self.syncWithPreferences()
            } else {
                self.tearDownTap(replayPendingSpacesPress: false)
            }
        }
    }

    func syncWithPreferences() {
        let defaults = UserDefaults.standard
        let enabled = AppFeature.mouseButtonShortcuts.isAvailable
            && defaults.bool(forKey: DefaultsKey.mouseButtonShortcutsEnabled)
        mappings = MouseButtonShortcutSupport.decode(
            defaults.dictionary(forKey: DefaultsKey.mouseButtonShortcuts) as? [String: String])
        wantsSideWheelEvents = enabled && (isCapturing
            || mappings[MouseButtonShortcutSupport.sideWheelLeftInput] != nil
            || mappings[MouseButtonShortcutSupport.sideWheelRightInput] != nil)
        spacesButton = MouseButtonShortcutSupport.spacesGestureButton()
        let canOwnTap = SessionActivitySupport.tapShouldRun(
            featureWanted: true,
            accessibilityGranted: AXIsProcessTrusted(),
            sessionIsActive: SessionActivity.shared.isActive
        )
        guard canOwnTap else {
            // Neither a switched-away nor an untrusted session may wait for a
            // future Up. Clear custody and hand the event chain back now.
            tearDownTap(replayPendingSpacesPress: false)
            return
        }
        // A press held for a button that just stopped being the gesture's is
        // owed back to the app, whatever happens to the tap next.
        if let spacesGesture, spacesGesture.button != spacesButton {
            flushSpacesPress(proxy: nil, at: nil)
        }
        // Capture holds the tap up by itself: the press being asked for may
        // be the drag's, and the drag's switch is not the shortcut switch.
        // Either capture row only exists while its own switch is on.
        let wanted = (enabled && !mappings.isEmpty) || isCapturing || spacesButton != nil
        guard wanted else {
            stop()
            return
        }
        // A tap the system disabled (Accessibility revoked and regranted)
        // never revives on its own; rebuild it instead of keeping the corpse.
        // Torn down directly, not through stop(): a dead tap can no longer
        // deliver the pending Up of a held button, so draining for it would
        // only keep the corpse and leave every mapped button silent.
        if let tap, !CGEvent.tapIsEnabled(tap: tap) {
            tearDownTap(replayPendingSpacesPress: false)
        }
        if isDraining, tap != nil {
            // The feature was turned back on before the old consumed press
            // released. Finish that pair first, then rebuild with current prefs.
            restartAfterDrain = true
            return
        }
        start()
    }

    /// Force-stops the tap regardless of preferences. Unlike a normal toggle
    /// off, an app/session teardown cannot wait indefinitely for a future Up.
    func suspend() {
        let mayReplayPendingPress = SessionActivity.shared.isActive && AXIsProcessTrusted()
        tearDownTap(replayPendingSpacesPress: mayReplayPendingPress)
    }

    /// Starts and stops reporting which extra button arrives, for the
    /// Settings capture row. Syncs on both edges: the way in may need to
    /// raise the tap before the first mapping exists, and the way out drops
    /// it again when nothing is mapped.
    func setCapturing(_ capturing: Bool) {
        guard isCapturing != capturing else { return }
        isCapturing = capturing
        Self.isCaptureActive = capturing
        lastInputSeen = nil
        syncWithPreferences()
    }

    /// Smooth scrolling runs at the HID level before this service's session
    /// tap. It leaves a side-wheel event untouched only when this service is
    /// alive and will really consume it; otherwise the normal glide remains.
    static func claimsSideWheel(_ input: Int64,
                                at location: CGPoint,
                                sourceProcessID: Int64,
                                eventTimestamp: UInt64) -> Bool {
        guard hasActiveSideWheelInterest else { return false }
        let service = shared
        guard service.isRunning,
              service.isCapturing || service.mappings[input] != nil else { return false }
        guard service.isCapturing
            || !MouseAppExceptions.shared.excludesActionTarget(
                .buttonShortcuts, at: location, sourceProcessID: sourceProcessID
            ) else { return false }
        service.preflightedSideWheelTimestamp = eventTimestamp
        service.preflightedSideWheelInput = input
        return true
    }

    private func start() {
        if tap != nil, tapIncludesSideWheel != wantsSideWheelEvents {
            if !consumedButtons.isEmpty {
                Self.hasActiveSideWheelInterest = false
                MouseAppExceptions.shared.setSourceTracking(false, for: .buttonShortcuts)
                isDraining = true
                restartAfterDrain = true
                isRunning = false
                return
            }
            tearDownTap()
        }
        guard tap == nil else {
            Self.hasActiveSideWheelInterest = wantsSideWheelEvents
            MouseAppExceptions.shared.setSourceTracking(wantsSideWheelEvents, for: .buttonShortcuts)
            isRunning = true
            return
        }
        guard AXIsProcessTrusted() else {
            Self.hasActiveSideWheelInterest = false
            MouseAppExceptions.shared.setSourceTracking(false, for: .buttonShortcuts)
            isRunning = false
            return
        }
        // The session tap runs after the HID-level navigation tap, which
        // already lets a button this feature claims pass through whole.
        var mask = (CGEventMask(1) << CGEventType.otherMouseDown.rawValue)
            | (CGEventMask(1) << CGEventType.otherMouseUp.rawValue)
            | (CGEventMask(1) << CGEventType.otherMouseDragged.rawValue)
        if wantsSideWheelEvents {
            mask |= CGEventMask(1) << CGEventType.scrollWheel.rawValue
        }
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: { proxy, type, event, userInfo in
                guard let userInfo else { return Unmanaged.passUnretained(event) }
                let service = Unmanaged<MouseButtonShortcutService>.fromOpaque(userInfo).takeUnretainedValue()
                return service.handle(proxy: proxy, type: type, event: event)
            },
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            tapIncludesSideWheel = false
            Self.hasActiveSideWheelInterest = false
            MouseAppExceptions.shared.setSourceTracking(false, for: .buttonShortcuts)
            isRunning = false
            return
        }
        self.tap = tap
        tapIncludesSideWheel = wantsSideWheelEvents
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        runLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        Self.hasActiveSideWheelInterest = wantsSideWheelEvents
        MouseAppExceptions.shared.setSourceTracking(wantsSideWheelEvents, for: .buttonShortcuts)
        isRunning = true
    }

    private func stop() {
        Self.hasActiveSideWheelInterest = false
        MouseAppExceptions.shared.setSourceTracking(false, for: .buttonShortcuts)
        restartAfterDrain = false
        // A button whose Down this tap consumed must have its Up consumed by
        // the same tap, or the app under the pointer receives half a click.
        // With a claimed button still physically held, the tap stays alive
        // in drain mode until the release arrives (handle() finishes the
        // teardown), instead of dying between the halves. This also covers
        // ending a capture right after the first press.
        if !consumedButtons.isEmpty, tap != nil {
            isDraining = true
            isRunning = false
            return
        }
        tearDownTap()
    }

    private func tearDownTap(replayPendingSpacesPress: Bool = true) {
        Self.hasActiveSideWheelInterest = false
        MouseAppExceptions.shared.setSourceTracking(false, for: .buttonShortcuts)
        // A press still held back has to go back to the app before the tap
        // holding it disappears, or that click is simply lost.
        if replayPendingSpacesPress {
            flushSpacesPress(proxy: nil, at: nil)
        } else {
            spacesGesture = nil
        }
        if let tap {
            CGEvent.tapEnable(tap: tap, enable: false)
            CFMachPortInvalidate(tap)
        }
        if let runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        }
        tap = nil
        runLoopSource = nil
        tapIncludesSideWheel = false
        consumedButtons.removeAll()
        lastGesturePhaseTimestamp = nil
        sideWheelGesture.reset()
        preflightedSideWheelTimestamp = nil
        preflightedSideWheelInput = nil
        isDraining = false
        restartAfterDrain = false
        isRunning = false
    }

    private func handle(proxy: CGEventTapProxy?, type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            sideWheelGesture.reset()
            preflightedSideWheelTimestamp = nil
            preflightedSideWheelInput = nil
            // While the tap was off the rest of that press went straight to
            // the app. Keep custody only for buttons that are still physically
            // held; a released button's Up has already bypassed this tap.
            flushSpacesPress(proxy: nil, at: nil)
            consumedButtons = consumedButtons.filter {
                MouseButtonShortcutSupport.isPressed(
                    $0, pressedButtons: NSEvent.pressedMouseButtons)
            }

            let enabled = AppFeature.mouseButtonShortcuts.isAvailable
                && UserDefaults.standard.bool(forKey: DefaultsKey.mouseButtonShortcutsEnabled)
            let wanted = (enabled && !mappings.isEmpty) || isCapturing || spacesButton != nil
            let shouldRun = SessionActivitySupport.tapShouldRun(
                featureWanted: wanted || !consumedButtons.isEmpty,
                accessibilityGranted: AXIsProcessTrusted(),
                sessionIsActive: SessionActivity.shared.isActive
            )
            if shouldRun, let tap,
               !restartAfterDrain || !consumedButtons.isEmpty {
                if !wanted || restartAfterDrain {
                    isDraining = true
                    isRunning = false
                }
                CGEvent.tapEnable(tap: tap, enable: true)
            } else {
                // Invalidating a tap from its own callback stack is unsafe.
                DispatchQueue.main.async { [weak self] in
                    guard let self else { return }
                    self.tearDownTap(replayPendingSpacesPress: false)
                    self.syncWithPreferences()
                }
            }
            return Unmanaged.passUnretained(event)
        }
        if type == .scrollWheel {
            return handleSideWheel(event)
        }
        // The press this service gave back to the system. Looking at it again
        // would take it right back and never let go.
        if event.getIntegerValueField(.eventSourceUserData) == Self.replayedPressMarker {
            return Unmanaged.passUnretained(event)
        }
        let button = event.getIntegerValueField(.mouseEventButtonNumber)

        if type == .otherMouseDown {
            if isDraining {
                return Unmanaged.passUnretained(event)
            }
            if isCapturing {
                // The capture row reports every extra button, even one it
                // will refuse, so it can explain instead of leaving the user
                // guessing. The press itself belongs to the capture: letting
                // it through would navigate, open a system overlay bound to
                // that button, or fire its old mapping while the user is
                // rearranging buttons. Only the middle button, which cannot
                // be captured, keeps working.
                lastInputSeen = button
                guard MouseButtonShortcutSupport.canMap(button) else {
                    return Unmanaged.passUnretained(event)
                }
                consumedButtons.insert(button)
                return nil
            }
            // An app on the exception list keeps its buttons: the press goes
            // through whole and no shortcut is sent (issue #358). Capture is
            // above on purpose, so a button can still be added from Settings
            // while such an app is in front.
            guard !MouseAppExceptions.shared.excludesActionTarget(.buttonShortcuts, at: event.location) else {
                return Unmanaged.passUnretained(event)
            }
            if button == spacesButton {
                return armSpacesGesture(event, button: button)
            }
            guard let shortcut = MouseButtonShortcutSupport.firesShortcut(
                for: button,
                isAvailable: AppFeature.mouseButtonShortcuts.isAvailable,
                isEnabled: UserDefaults.standard.bool(forKey: DefaultsKey.mouseButtonShortcutsEnabled),
                mappings: mappings,
                claimedByWheel: RadialMenuSupport.claimsMouseButton)
            else { return Unmanaged.passUnretained(event) }
            consumedButtons.insert(button)
            post(shortcut)
            return nil
        }

        if let gesture = spacesGesture, gesture.button == button {
            switch type {
            case .otherMouseDragged:
                advanceSpacesGesture(to: event.location)
                return nil
            case .otherMouseUp:
                spacesGesture = nil
                guard gesture.tracker.didFire else {
                    // The pointer never went far enough to mean anything, so
                    // the press was only a click: hand it back first and let
                    // this release close the pair. Below the thresholds this
                    // feature costs the app nothing at all.
                    replaySpacesPress(gesture.down, proxy: proxy, at: event.location)
                    return Unmanaged.passUnretained(event)
                }
                // A press that did fire is already held in consumedButtons,
                // and the release below belongs to it.
            default:
                return nil
            }
        }

        // Up and Drag follow their Down's decision, so a mapping edited
        // mid-press can never split a gesture in half.
        guard consumedButtons.contains(button) else {
            return Unmanaged.passUnretained(event)
        }
        if type == .otherMouseUp {
            consumedButtons.remove(button)
            // The drain existed only for this release; finishing outside the
            // callback keeps the mach port teardown off the tap's own stack.
            if isDraining, consumedButtons.isEmpty {
                let shouldRestart = restartAfterDrain
                DispatchQueue.main.async { [weak self] in
                    guard let self, self.isDraining, self.consumedButtons.isEmpty else { return }
                    self.tearDownTap()
                    if shouldRestart {
                        self.syncWithPreferences()
                    }
                }
            }
        }
        return nil
    }

    // MARK: - Spaces and Mission Control drag

    /// Holds the bound button's press back while it may still become a drag.
    /// Without a copy there is nothing to give back, and keeping a press that
    /// can never be returned is worse than not holding it at all. A press
    /// arriving while one is still held means that release never came, so the
    /// stale copy is dropped rather than replayed at a spot the pointer left.
    private func armSpacesGesture(_ event: CGEvent, button: Int64) -> Unmanaged<CGEvent>? {
        guard let down = event.copy() else { return Unmanaged.passUnretained(event) }
        spacesGesture = SpacesGesturePress(
            button: button,
            down: down,
            followsDrag: UserDefaults.standard.bool(forKey: DefaultsKey.mouseSpacesGestureFollowsDrag),
            tracker: .init(origin: event.location))
        return nil
    }

    private func advanceSpacesGesture(to point: CGPoint) {
        guard var gesture = spacesGesture else { return }
        let action = gesture.tracker.advance(to: point,
                                             now: ProcessInfo.processInfo.systemUptime)
        spacesGesture = gesture
        guard let action else { return }
        // The press has done something, so its release belongs here too and
        // the app never receives half a click.
        consumedButtons.insert(gesture.button)
        perform(MouseSpacesGestureSupport.resolved(action, followsDrag: gesture.followsDrag))
    }

    /// Spaces and the overviews are asked for the way the keyboard asks for
    /// them. The window server refuses software-simulated touch gestures, and
    /// the combination it registered for that command is the one thing it
    /// still accepts (issue #1012). A command whose shortcut the user switched
    /// off in System Settings reads as nil, and the gesture stays silent
    /// rather than pressing something else.
    private func perform(_ action: MouseSpacesGestureSupport.Action) {
        let shortcut: SpaceWindowBridge.SpaceShortcut?
        switch action {
        case .spaceLeft: shortcut = SpaceWindowBridge.spaceShortcut(.left)
        case .spaceRight: shortcut = SpaceWindowBridge.spaceShortcut(.right)
        case .missionControl: shortcut = SpaceWindowBridge.overviewShortcut(.missionControl)
        case .appExpose: shortcut = SpaceWindowBridge.overviewShortcut(.appExpose)
        }
        guard let shortcut else { return }
        SpaceWindowBridge.pressSpaceShortcut(shortcut)
    }

    /// Gives up a held press outside the release that would normally close it.
    private func flushSpacesPress(proxy: CGEventTapProxy?, at point: CGPoint?) {
        guard let gesture = spacesGesture else { return }
        spacesGesture = nil
        // Handing the press back only closes into a whole click while a
        // release is still coming. With the button already up, that release
        // reached the app on its own, and the press would be left down with
        // nothing to lift it. A press that already fired owes nothing back.
        guard !gesture.tracker.didFire,
              MouseButtonShortcutSupport.isPressed(
                  gesture.button, pressedButtons: NSEvent.pressedMouseButtons
              ) else { return }
        replaySpacesPress(gesture.down, proxy: proxy, at: point)
    }

    /// Puts a held press back into the stream. It carries the release point
    /// and the current time, so the app reads the pair as one short click on
    /// one element however long the button was held.
    private func replaySpacesPress(_ down: CGEvent, proxy: CGEventTapProxy?, at point: CGPoint?) {
        if let point { down.location = point }
        down.timestamp = clock_gettime_nsec_np(CLOCK_UPTIME_RAW)
        down.setIntegerValueField(.eventSourceUserData, value: Self.replayedPressMarker)
        if let proxy {
            // Posted through the tap it is leaving, which places it ahead of
            // the event this callback is about to return.
            down.tapPostEvent(proxy)
        } else {
            down.post(tap: .cgSessionEventTap)
        }
    }

    private func handleSideWheel(_ event: CGEvent) -> Unmanaged<CGEvent>? {
        guard Self.hasActiveSideWheelInterest,
              !isDraining,
              event.getIntegerValueField(.eventSourceUserData) != ScrollWheelSupport.syntheticTag,
              let input = sideWheelInput(for: event) else {
            return Unmanaged.passUnretained(event)
        }
        let timestamp = UInt64(event.timestamp)
        let wasPreflighted = preflightedSideWheelTimestamp == timestamp
            && preflightedSideWheelInput == input
        preflightedSideWheelTimestamp = nil
        preflightedSideWheelInput = nil
        if isCapturing {
            guard sideWheelGesture.shouldFire(input, at: timestamp) else { return nil }
            // Report after the tap callback returns so Settings can stop and
            // tear down this tap without invalidating its current stack.
            DispatchQueue.main.async { [weak self] in
                guard let self, self.isCapturing else { return }
                self.lastInputSeen = input
            }
            return nil
        }
        guard let shortcut = mappings[input] else { return Unmanaged.passUnretained(event) }
        let sourceProcessID = event.getIntegerValueField(.eventSourceUnixProcessID)
        if !wasPreflighted,
           MouseAppExceptions.shared.excludesActionTarget(
            .buttonShortcuts, at: event.location, sourceProcessID: sourceProcessID
           ) {
            return Unmanaged.passUnretained(event)
        }
        guard sideWheelGesture.shouldFire(input, at: timestamp) else { return nil }
        post(shortcut)
        return nil
    }

    private func sideWheelInput(for event: CGEvent) -> Int64? {
        let traits = ScrollWheelEventTraits(
            isContinuous: event.getIntegerValueField(.scrollWheelEventIsContinuous) != 0,
            momentumPhase: event.getIntegerValueField(.scrollWheelEventMomentumPhase),
            scrollPhase: event.getIntegerValueField(.scrollWheelEventScrollPhase),
            scrollCount: event.getIntegerValueField(.scrollWheelEventScrollCount)
        )
        let timestamp = UInt64(event.timestamp)
        let secondsSinceGesturePhase = lastGesturePhaseTimestamp.map {
            Double(timestamp &- $0) / 1_000_000_000.0
        }
        if traits.momentumPhase != 0 || traits.scrollPhase != 0 {
            lastGesturePhaseTimestamp = timestamp
        }
        guard ScrollWheelSupport.isMouseWheel(
            traits,
            secondsSinceLastGesturePhase: secondsSinceGesturePhase) else { return nil }
        return MouseButtonShortcutSupport.sideWheelInput(
            isContinuous: traits.isContinuous,
            vertical: (
                line: Double(event.getIntegerValueField(.scrollWheelEventDeltaAxis1)),
                fixedPoint: event.getDoubleValueField(.scrollWheelEventFixedPtDeltaAxis1),
                point: Double(event.getIntegerValueField(.scrollWheelEventPointDeltaAxis1))
            ),
            horizontal: (
                line: Double(event.getIntegerValueField(.scrollWheelEventDeltaAxis2)),
                fixedPoint: event.getDoubleValueField(.scrollWheelEventFixedPtDeltaAxis2),
                point: Double(event.getIntegerValueField(.scrollWheelEventPointDeltaAxis2))
            )
        )
    }

    /// The shortcut goes out as a virtual key plus the flags a real press of
    /// it carries, nothing more. No keyboardSetUnicodeString: a forced
    /// character string on a shortcut event breaks menu key equivalent
    /// dispatch in the target app, so the combination would arrive and still
    /// do nothing.
    ///
    /// It enters where the keyboard's own presses enter, so every listener on
    /// the way sees the same press a finger would have made. Sent further
    /// along, it would still reach the app in front but stay invisible to
    /// anything watching the keyboard, which is why a shortcut belonging to
    /// the system or to another app did nothing at all (issue #401).
    private func post(_ shortcut: GlobalShortcut) {
        guard shortcut.hasUsableKeyCode else { return }
        let source = CGEventSource(stateID: .hidSystemState)
        guard let down = CGEvent(keyboardEventSource: source,
                                 virtualKey: CGKeyCode(shortcut.keyCode),
                                 keyDown: true),
              let up = CGEvent(keyboardEventSource: source,
                               virtualKey: CGKeyCode(shortcut.keyCode),
                               keyDown: false) else { return }
        let flags = shortcut.syntheticEventFlags
        down.flags = flags
        up.flags = flags
        down.post(tap: .cghidEventTap)
        up.post(tap: .cghidEventTap)
    }
}
