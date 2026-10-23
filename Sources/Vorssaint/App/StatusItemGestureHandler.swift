// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import Combine
import CoreGraphics
import os.log

/// Watches only the main status button. Returning every local event intact
/// preserves AppKit's own button tracking, Command-drag and every other
/// status item.
///
/// Left clicks use the button's frame, with the original click path as a
/// fallback when that frame cannot be trusted. The session-wide middle tap
/// also asks who owns the point, so a stale frame cannot claim another icon.
/// Where macOS 27 strands this item's frame at its birth slot (see
/// `StatusItemAnchorSupport`), the frame check refuses the drawn icon: the
/// gestures stay inactive there and a left click opens the panel as usual.
final class StatusItemGestureHandler {
    private static let log = Logger(subsystem: Bundle.main.bundleIdentifier ?? "vorssaint",
                                   category: "statusgesture")

    /// Some macOS versions report the press rather than the release. Watch
    /// the physical button every 40 ms while a hold is in flight.
    private static let releaseWatchInterval: TimeInterval = 0.04
    /// How long a press the watcher ended still waits for its own button
    /// action. A busy main thread can deliver that action late, but one that
    /// never comes (a release just off the button) must not hold back an
    /// accessibility press for long.
    private static let lateActionWindow: TimeInterval = 2
    /// How close two times are to be one event's: a press-time action and
    /// its own down, or a press and the down the event source recorded for it.
    private static let sameEventSlack: TimeInterval = 0.001
    /// Set on the main button so Accessibility can tell it from this app's
    /// other menu bar items, which answer with the same process.
    static let mainButtonIdentifier = "com.vorssaint.status-item.main"
    weak var owner: StatusItemController?
    private var gesture = StatusItemGesture()
    private var settings: StatusItemGesture.Settings
    private var monitor: Any?
    private var timer: Timer?
    private var generation = 0
    /// When the left press in flight went down.
    private var leftPressStart: TimeInterval?
    /// Where that press was last seen while the button was still down. The
    /// watcher notices a release on its next tick, when the pointer may
    /// already be on its way elsewhere.
    private var lastHeldPoint: CGPoint?
    /// When that point was seen.
    private var lastHeldTime: TimeInterval?
    /// Whether the latest left press's button action has arrived. Until it
    /// has, a late action for that press is still its own.
    private var leftActionSeen = true
    /// The latest Command or Control press the monitor turned away. Where the
    /// button reports its press, that press's action carries the same time.
    private var rejectedLeftDown: TimeInterval?
    /// Latest release handled by any path. Kept across cancellation so a
    /// delayed AppKit action cannot replay a click after its callback runs.
    private var handledLeftRelease: TimeInterval?
    /// The status button is an `NSStatusItem`, and macOS never delivers a
    /// middle-click on one to the owning app — no local monitor can see it.
    /// A passive session tap is therefore the only way to serve this gesture.
    private var middleTap: CFMachPort?
    private var middleRunLoopSource: CFRunLoopSource?
    private var accessibilityObserver: AnyCancellable?

    init(owner: StatusItemController, settings: StatusItemGesture.Settings) {
        self.owner = owner
        self.settings = settings
        // A local monitor runs before the event reaches the button, so it
        // records the real down timestamp a held button needs. It never
        // consumes anything: the event continues to AppKit untouched. Key
        // events and activation are left alone: this accessory app is rarely
        // active while its icon is pressed, and the release watcher ends every
        // press without them.
        monitor = NSEvent.addLocalMonitorForEvents(
            matching: [.leftMouseDown, .leftMouseUp, .leftMouseDragged,
                       .rightMouseDown]) { [weak self] event in
            self?.observe(event)
            return event
        }
        log("handler created middle=\(settings.middle.rawValue) hold=\(settings.hold.rawValue)")
        watchAccessibility()
        syncMiddleTap()
    }

    // MARK: - Middle-click tap

    private func watchAccessibility() {
        accessibilityObserver = Permissions.shared.$accessibility
            .dropFirst()
            .removeDuplicates()
            .sink { [weak self] granted in
                self?.syncMiddleTap(accessibilityGranted: granted)
            }
    }

    /// Installed only while a middle-click action is assigned, so a Mac that
    /// never uses this gesture pays neither the permission nor the tap.
    private func syncMiddleTap(accessibilityGranted: Bool = AXIsProcessTrusted()) {
        // A permission reset or an uninstall suspends the tap until it ends,
        // whatever the settings or the grant say meanwhile.
        guard settings.needsAccessibility, owner?.gestureTapSuspended != true else {
            tearDownMiddleTap()
            return
        }
        guard accessibilityGranted else {
            tearDownMiddleTap()
            // Launch, settings sync and grant changes are passive. Only the
            // middle-click picker (or an explicit permission button) asks.
            return
        }
        // A revoke/regrant between permission polls can leave the published
        // grant unchanged while the system has disabled the old tap.
        if let middleTap, !CGEvent.tapIsEnabled(tap: middleTap) {
            tearDownMiddleTap()
        }
        guard middleTap == nil else { return }
        installMiddleTap()
    }

    private func installMiddleTap() {
        // A listen-only tap never holds another app's event back, but the
        // system can still disable it; handleMiddleTap re-arms it.
        let mask = (CGEventMask(1) << CGEventType.otherMouseDown.rawValue)
            | (CGEventMask(1) << CGEventType.otherMouseUp.rawValue)
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            // Middle click (and any button remapper) turns a press into a
            // middle click before this tap sees it, whichever tap came first.
            place: .tailAppendEventTap,
            options: .listenOnly,
            eventsOfInterest: mask,
            callback: { _, type, event, userInfo in
                guard let userInfo else { return Unmanaged.passUnretained(event) }
                let handler = Unmanaged<StatusItemGestureHandler>.fromOpaque(userInfo).takeUnretainedValue()
                handler.handleMiddleTap(type: type, event: event)
                return Unmanaged.passUnretained(event)
            },
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            log("middle tap could not be created (permission?)")
            return
        }
        middleTap = tap
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        middleRunLoopSource = source
        // Served on the main run loop, the same as the project's other
        // button-shortcut tap: the callback must read AppKit geometry, and a
        // listen-only tap never blocks the events it observes.
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        log("middle tap installed")
    }

    private func tearDownMiddleTap() {
        gesture.cancelMiddle()
        if let middleTap {
            CGEvent.tapEnable(tap: middleTap, enable: false)
            CFMachPortInvalidate(middleTap)
        }
        if let middleRunLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), middleRunLoopSource, .commonModes)
        }
        middleTap = nil
        middleRunLoopSource = nil
    }

    /// Middle-click geometry arrives in display coordinates (origin at the top
    /// left of the primary display); AppKit screens put the origin at its
    /// bottom left. One flip maps between them for every display.
    private func handleMiddleTap(type: CGEventType, event: CGEvent) {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            gesture.cancelMiddle() // An observation gap breaks the down/up pair.
            if settings.needsAccessibility, AXIsProcessTrusted(), let middleTap {
                CGEvent.tapEnable(tap: middleTap, enable: true)
            } else {
                // Do not invalidate the port from its own callback stack.
                DispatchQueue.main.async { [weak self] in self?.syncMiddleTap() }
            }
            return
        }
        guard type == .otherMouseDown || type == .otherMouseUp,
              event.getIntegerValueField(.mouseEventButtonNumber) == 2 else { return }
        // A release with no press waiting has nothing to finish, and nothing
        // to ask anyone about.
        guard type == .otherMouseDown || gesture.awaitsMiddleRelease else { return }
        let appKitPoint = appKitPoint(fromDisplay: event.location)
        guard let frame = mainButtonFrame(),
              StatusItemGesture.claims(appKitPoint, frame: StatusItemGesture.pressArea(of: frame)),
              ownsClick(at: event.location,
                        probing: CGPoint(x: event.location.x, y: primaryScreenHeight - frame.midY)) else {
            gesture.cancelMiddle()
            return
        }
        if type == .otherMouseDown {
            // A left click that came up just before this middle press keeps
            // its outcome; one still held keeps the icon.
            finishIfReleased(before: ProcessInfo.processInfo.systemUptime)
            gesture.middleDown(settings: settings, within: hitArea ?? .null)
        } else {
            emit(gesture.middleUp(at: appKitPoint, settings: settings))
        }
        schedule()
    }

    /// Whether the item under `point` (display coordinates, as the tap
    /// reports them) is this icon. A reported frame can stay at the item's
    /// old slot after a move, so the frame alone cannot say.
    ///
    /// Where the button's own window takes the click, the window server names
    /// it, and any other window there takes the click itself. Where the
    /// system draws the menu bar (macOS 27), status items have no windows:
    /// over this app's item the hit test usually finds no window at all, and
    /// elsewhere on the bar it finds the bar's own. Accessibility, which the
    /// middle click already needs, then names the item, asked at `probe`: the
    /// same x, at the middle of the button, since the bar's outer rows
    /// belong to the bar.
    private func ownsClick(at point: CGPoint, probing probe: CGPoint) -> Bool {
        guard let number = mainButtonWindowNumber else { return false }
        if let receiving = WindowServerSupport.receivingWindow(at: point) {
            if receiving == CGWindowID(exactly: number) { return true }
            guard WindowServerSupport.isMenuBar(windowID: receiving) else { return false }
        }
        // A revoked grant makes an Accessibility hit test hang inside the tap
        // and freeze input, so never ask without it. Permission polling then
        // takes the listen-only tap down, and brings it back with the grant.
        guard AXIsProcessTrusted() else { return false }
        return accessibilityNamesMainButton(at: probe)
    }

    /// Whether the menu bar item Accessibility finds at `point` is this
    /// button. This app's other items answer with this process too, so the
    /// button's own identifier decides. This app's item answers in-process; a
    /// foreign one within the app-wide Accessibility wait, which an app that
    /// does not answer at all spends twice.
    private func accessibilityNamesMainButton(at point: CGPoint) -> Bool {
        var element: AXUIElement?
        var pid: pid_t = 0
        guard AXUIElementCopyElementAtPosition(AXUIElementCreateSystemWide(),
                                               Float(point.x), Float(point.y), &element) == .success,
              let element, AXUIElementGetPid(element, &pid) == .success, pid == getpid() else { return false }
        var identifier: AnyObject?
        guard AXUIElementCopyAttributeValue(element, kAXIdentifierAttribute as CFString,
                                            &identifier) == .success else { return false }
        return identifier as? String == Self.mainButtonIdentifier
    }

    /// The main button's window, or nil when the item is hidden or unplaced.
    private var mainButtonWindowNumber: Int? {
        guard let item = owner?.statusItem, item.isVisible,
              let number = item.button?.window?.windowNumber, number > 0 else { return nil }
        return number
    }

    private func log(_ message: String) {
        Self.log.notice("\(message, privacy: .public)")
    }

    deinit {
        tearDownMiddleTap()
        timer?.invalidate()
        if let monitor { NSEvent.removeMonitor(monitor) }
    }

    func sync(settings new: StatusItemGesture.Settings) {
        let changed = new != settings
        if changed {
            cancel()
            settings = new
        }
        syncMiddleTap()
    }

    func cancel() {
        gesture.cancel()
        timer?.invalidate()
        timer = nil
        generation &+= 1
        leftPressStart = nil
        lastHeldPoint = nil
        lastHeldTime = nil
    }

    /// Whether a button action belongs to the latest left press. After a busy
    /// main thread its event arrives late, and handing it to the plain click
    /// path would give that one press a second outcome. That holds after the
    /// watcher has ended the press too, until the press's own action arrives.
    func tracksPress(of event: NSEvent) -> Bool {
        guard let leftPressStart, event.timestamp >= leftPressStart else { return false }
        if gesture.watchesForRelease { return true }
        guard !leftActionSeen, let handledLeftRelease,
              ProcessInfo.processInfo.systemUptime - handledLeftRelease <= Self.lateActionWindow
        else { return false }
        return event.timestamp <= handledLeftRelease
    }

    /// Returns false when the click is not on the button, or when the button's
    /// frame cannot be trusted, so the caller can run the normal click instead
    /// of swallowing it.
    ///
    /// This is the guaranteed second path: AppKit's button action always fires
    /// once per left press, so a monitor event this handler never saw still
    /// produces exactly one outcome instead of a lost click.
    @discardableResult
    func buttonClick(_ event: NSEvent) -> Bool {
        guard settings.hold != .none else { return false }
        // An older press's action cannot answer for the latest one.
        if event.timestamp >= (leftPressStart ?? -.infinity) { leftActionSeen = true }
        if let handledLeftRelease, event.timestamp <= handledLeftRelease { return true }
        // The monitor turns a Command or Control press away; starting it
        // again here would let that press run the hold after all.
        let rejected = rejectedLeftDown.map { event.timestamp <= $0 } ?? false
        // AppKit sends this action for a click on its own button, so a press
        // already in flight needs no second look at where the pointer went.
        // A pending middle press is not a left press, so it cannot stand in
        // for the down this click's monitor event never delivered.
        let inFlight = gesture.watchesForRelease
        guard !rejected, event.modifierFlags.intersection([.command, .control]).isEmpty,
              let point = inFlight ? lastHeldPoint : pointer(in: hitArea) else {
            // The normal click runs instead, so nothing may finish here too.
            cancel()
            return false
        }
        if !inFlight {
            beginLeftPress(at: point, time: event.timestamp)
        }
        // A missed monitor down must still start the release watcher. Do not
        // finish a press while the physical button is held.
        if NSEvent.pressedMouseButtons & 0x1 != 0 {
            schedule()
            return true
        }
        // A release action carries its own exact time. Where the button
        // reports its press, a late action carries the press time instead,
        // while the press it belongs to ended when the button came up.
        let carriesPressTime = inFlight
            && event.timestamp <= (leftPressStart ?? -.infinity) + Self.sameEventSlack
        let released = carriesPressTime
            ? releaseTime(now: ProcessInfo.processInfo.systemUptime)
            : event.timestamp
        // A release action comes only for a release on the button, so the
        // press counts where it was last held, wherever the pointer went.
        finishLeftPress(releasedAt: released, handledThrough: max(event.timestamp, released),
                        at: carriesPressTime ? nil : point)
        return true
    }

    private func beginLeftPress(at point: NSPoint, time: TimeInterval) {
        leftPressStart = time
        lastHeldPoint = point
        lastHeldTime = time
        emit(gesture.leftDown(at: point, time: time, within: hitArea ?? .null))
    }

    /// Ends the left press in flight, released at `time` where it was last
    /// held. Actions up to `handled` belong to it; a newer one is a new click.
    /// A press that ends with no outcome lets go of everything, so no later
    /// action is mistaken for its own.
    private func finishLeftPress(releasedAt time: TimeInterval, handledThrough handled: TimeInterval,
                                 at known: CGPoint? = nil) {
        handledLeftRelease = handled
        let results = gesture.leftUp(at: known ?? releasePoint(releasedAt: time), time: time, settings: settings)
        if results.isEmpty {
            cancel()
        } else {
            emit(results)
            schedule()
        }
    }
    // MARK: - Geometry

    /// The main button's frame in screen coordinates, or nil when the item is
    /// hidden or has not been placed yet.
    private func mainButtonFrame() -> NSRect? {
        guard let item = owner?.statusItem, item.isVisible,
              let button = item.button, let window = button.window else { return nil }
        let frame = window.convertToScreen(button.convert(button.bounds, to: nil))
        guard frame.width > 0, frame.height > 0 else { return nil }
        return frame
    }

    /// Where a press on the button may stray and still count: the icon plus
    /// a little slack, whatever the item's title makes its width.
    private var hitArea: CGRect? {
        StatusItemGesture.hitArea(of: mainButtonFrame())
    }

    private var primaryScreenHeight: CGFloat {
        NSScreen.screens.first { $0.frame.origin == .zero }?.frame.height
            ?? NSScreen.screens.first?.frame.height ?? 0
    }

    private func appKitPoint(fromDisplay point: CGPoint) -> CGPoint {
        StatusItemGesture.appKitPoint(displayPoint: point, primaryHeight: primaryScreenHeight)
    }

    /// The pointer when it is in `area`. The decision itself is the pure
    /// `claims` predicate, so the tests exercise the real branch that decides
    /// whether a click is swallowed or runs normally.
    ///
    /// A press is claimed where the pointer is, never where its event says:
    /// AppKit relays a status item press as an event placed through the
    /// item's window, so that location follows the window's frame, which
    /// macOS 27 can leave stranded away from the drawn icon. Judged by the
    /// pointer, a press there is refused and the normal click still opens the
    /// panel. A release, which can be handled after the pointer moved on, is
    /// judged by `releasePoint(releasedAt:)` instead.
    private func pointer(in area: CGRect?) -> NSPoint? {
        let point = NSEvent.mouseLocation
        guard StatusItemGesture.claims(point, frame: area) else { return nil }
        return point
    }

    /// Where the press in flight came up. The last held sample is exact
    /// unless the pointer was dragged after it; the pointer itself then is,
    /// if it has not moved since the release. When it has, a hold, whose
    /// action must not run off the icon, is judged where the pointer is now,
    /// and a click, which must not be lost, where it was last held.
    private func releasePoint(releasedAt time: TimeInterval) -> CGPoint {
        guard let lastHeldPoint, let lastHeldTime else { return NSEvent.mouseLocation }
        let now = ProcessInfo.processInfo.systemUptime
        guard let dragged = eventTime(.leftMouseDragged, now: now),
              dragged > lastHeldTime + Self.sameEventSlack else { return lastHeldPoint }
        let movedSince = (eventTime(.mouseMoved, now: now) ?? -.infinity) > time
        return !movedSince || gesture.holds(releasedAt: time, settings: settings)
            ? NSEvent.mouseLocation : lastHeldPoint
    }

    // MARK: - Local monitor

    private func observe(_ event: NSEvent) {
        guard settings.hold != .none else { return }
        switch event.type {
        case .rightMouseDown:
            // A right click during a hold cancels it. One after the left
            // button came up, before a tick saw it, follows that click.
            finishIfReleased(before: event.timestamp)
            cancel()
        case .leftMouseDown where !event.modifierFlags.intersection([.command, .control]).isEmpty:
            // Command-drag reorders the icon; Control-click is a context menu.
            finishUnseenRelease(before: event.timestamp)
            rejectedLeftDown = event.timestamp
            cancel()
        case .leftMouseDown:
            finishUnseenRelease(before: event.timestamp)
            // A press on another window of this app, such as the Cleaning
            // Mode overlay above the menu bar, never reaches the button. A
            // windowless event is still a menu bar click.
            if let number = event.window?.windowNumber, number != mainButtonWindowNumber {
                cancel()
                return
            }
            guard let frame = mainButtonFrame(),
                  let point = pointer(in: StatusItemGesture.pressArea(of: frame)) else {
                cancel()
                return
            }
            leftActionSeen = false
            beginLeftPress(at: point, time: event.timestamp)
            schedule()
        case .leftMouseDragged:
            held(at: NSEvent.mouseLocation, time: event.timestamp)
        case .leftMouseUp:
            // A watcher may have already finished this press. Preserve its
            // release marker; an unobserved newer click can still fall back
            // through the button action.
            guard gesture.watchesForRelease else { return }
            finishLeftPress(releasedAt: event.timestamp, handledThrough: event.timestamp)
        default:
            break
        }
    }

    private func emit(_ results: [StatusItemGesture.Result]) {
        for result in results {
            switch result {
            case .single(let point):
                // The panel anchors at this point. A release in the slack
                // around the icon must not anchor it beside the icon, or on a
                // display arranged above the bar.
                owner?.onDelayedLeftClick?(onButton(point))
            case .quick(let action):
                owner?.onQuickAction?(action)
            }
        }
    }

    private func onButton(_ point: CGPoint) -> CGPoint {
        guard let frame = mainButtonFrame() else { return point }
        return CGPoint(x: min(max(point.x, frame.minX), frame.maxX),
                       y: min(max(point.y, frame.minY), frame.maxY))
    }

    /// Watch the physical button while a hold is in flight, including on
    /// macOS versions whose status button action does not report the release.
    private func schedule() {
        timer?.invalidate()
        timer = nil
        generation &+= 1
        guard gesture.watchesForRelease else { return }
        let scheduledGeneration = generation
        let watch = Timer(timeInterval: Self.releaseWatchInterval, repeats: true) { [weak self] _ in
            guard let self, self.generation == scheduledGeneration else { return }
            self.observeRelease()
        }
        timer = watch
        RunLoop.main.add(watch, forMode: .common)
    }

    /// Record a handled release before calling out: AppKit may send its
    /// release action later, with a timestamp no newer than this sample.
    private func observeRelease() {
        guard gesture.watchesForRelease else { return }
        let now = ProcessInfo.processInfo.systemUptime
        let start = leftPressStart ?? now
        // A press that began since this one means this one came up, even
        // when the button reads as held again. What the event source says
        // about releases now describes that press, not this one.
        if let newer = newerPress(than: start, now: now) {
            finishLeftPress(releasedAt: start, handledThrough: newer.nextDown)
            return
        }
        if NSEvent.pressedMouseButtons & 0x1 != 0 {
            held(at: NSEvent.mouseLocation, time: now)
            emit(gesture.expired(at: now, settings: settings))
            return
        }
        finishLeftPress(releasedAt: releaseTime(now: now), handledThrough: now)
    }

    /// A press still in flight when the next left press begins came up
    /// between two ticks: it ends first, as the click it was, and actions up
    /// to `time` stay its own. What the event source says about releases now
    /// describes the new press, so nothing past the press itself is assumed.
    private func finishUnseenRelease(before time: TimeInterval) {
        guard gesture.watchesForRelease else { return }
        finishLeftPress(releasedAt: leftPressStart ?? time, handledThrough: time.nextDown)
    }

    /// Ends the press in flight when the event source shows its button came
    /// up before `time`, released when the source says. Another button
    /// pressed then follows that click instead of cancelling it.
    private func finishIfReleased(before time: TimeInterval) {
        guard gesture.watchesForRelease, let start = leftPressStart else { return }
        let now = ProcessInfo.processInfo.systemUptime
        // A press elsewhere since this one: the source's last release may be
        // that press's own, so nothing past this press's start is assumed.
        if let newer = newerPress(than: start, now: now), newer <= time {
            finishLeftPress(releasedAt: start, handledThrough: time.nextDown)
            return
        }
        guard let released = eventTime(.leftMouseUp, now: now), released >= start, released <= time else { return }
        finishLeftPress(releasedAt: released, handledThrough: time.nextDown)
    }

    /// The pointer of a press still held. Leaving the icon cancels the press
    /// at once, the same from a drag event or from the watcher.
    private func held(at point: CGPoint, time: TimeInterval) {
        guard gesture.watchesForRelease else { return }
        lastHeldPoint = point
        lastHeldTime = time
        gesture.moved(to: point)
        if !gesture.watchesForRelease { cancel() }
    }

    /// When the press in flight came up, as the event source recorded it,
    /// kept between the press and `now`. A tick runs up to 40 ms after the
    /// release, and later still when the main thread is busy; judging the
    /// press by the tick would turn a short click into a hold. Once a newer
    /// press has begun, the source no longer describes this one, so nothing
    /// past the press itself is assumed: only a tick that saw it held past
    /// the threshold makes it a hold.
    private func releaseTime(now: TimeInterval) -> TimeInterval {
        let start = leftPressStart ?? now
        guard newerPress(than: start, now: now) == nil else { return start }
        let released = eventTime(.leftMouseUp, now: now) ?? start
        return min(now, max(start, released))
    }

    /// When a press after the one that began at `start` went down, if the
    /// hardware has seen one. Its own down shares its time.
    private func newerPress(than start: TimeInterval, now: TimeInterval) -> TimeInterval? {
        guard let down = eventTime(.leftMouseDown, now: now), down > start + Self.sameEventSlack else {
            return nil
        }
        return down
    }

    /// When the hardware last reported an event of `type`, or nil when the
    /// event source cannot say.
    private func eventTime(_ type: CGEventType, now: TimeInterval) -> TimeInterval? {
        let since = CGEventSource.secondsSinceLastEventType(.hidSystemState, eventType: type)
        return since.isFinite && since >= 0 ? now - since : nil
    }
}
