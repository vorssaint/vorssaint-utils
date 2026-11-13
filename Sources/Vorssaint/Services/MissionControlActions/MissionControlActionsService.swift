// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import ApplicationServices
import Carbon.HIToolbox
import CoreGraphics
import Darwin
import Foundation

/// Adds opt-in actions to the Mission Control tile under the pointer. The
/// expensive AX and WindowServer snapshot is built away from the event-tap
/// thread. The callback reads only that immutable snapshot and fails open.
final class MissionControlActionsService {
    static let shared = MissionControlActionsService()

    private struct CachedSnapshot {
        let detection: MissionControlDetectionSnapshot
        let hoveredTarget: MissionControlValidatedTarget?
        let timing: MissionControlSnapshotTiming
    }

    private struct PendingKey {
        let down: CGEvent
        let pendingAction: MissionControlPendingAction
        let startedAt: TimeInterval
    }

    private struct EventState {
        var settings = MissionControlActionSettings(
            rightClick: .terminateApp, middleClick: .none,
            keyboardShortcutsEnabled: false
        )
        var monitorWanted = false
        var snapshot: CachedSnapshot?
        var pointerGesture = MissionControlPointerGesture()
        var pendingDown: CGEvent?
        var pendingButton: MissionControlPointerButton?
        var pendingKeys: [Int64: PendingKey] = [:]
    }

    private struct AXDisplay {
        let frame: CGRect
        let childrenCount: Int
        let tiles: [MissionControlTileSnapshot]
    }

    private struct AXDisplayResult {
        let displays: [AXDisplay]
        let complete: Bool
    }

    private struct AXChildrenResult {
        let children: [AXUIElement]
        let complete: Bool
    }

    private static let replayedPressMarker: Int64 = 0x564D_4341
    private static let snapshotInterval: TimeInterval = 0.2
    private static let axMessagingTimeout: Float = 0.1

    private let stateLock = NSLock()
    private var eventState = EventState()
    private let lifecycleLock = NSLock()
    private var tap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var snapshotTimer: Timer?
    private var snapshotGeneration: UInt = 0
    private var snapshotInFlightGeneration: UInt?
    private let snapshotQueue = DispatchQueue(
        label: "com.vorssaint.mission-control-actions.snapshot",
        qos: .userInitiated
    )

    private init() {
        SessionActivity.shared.onChange { [weak self] _ in
            self?.syncWithPreferences()
        }
    }

    func syncWithPreferences() {
        let defaults = UserDefaults.standard
        let settings = MissionControlActionSettings(
            rightClick: MissionControlAction.sanitized(
                defaults.string(forKey: DefaultsKey.missionControlRightClickAction)
            ),
            middleClick: MissionControlAction.sanitized(
                defaults.string(forKey: DefaultsKey.missionControlMiddleClickAction)
            ),
            keyboardShortcutsEnabled: defaults.bool(
                forKey: DefaultsKey.missionControlKeyboardShortcutsEnabled
            )
        )
        let hasAction = settings.rightClick != .none || settings.middleClick != .none
            || settings.keyboardShortcutsEnabled
        let wanted = AppFeature.missionControlActions.isAvailable
            && defaults.bool(forKey: DefaultsKey.missionControlActionsEnabled)
            && hasAction
        let shouldMonitor = MissionControlRuntimeConditions(
            featureWanted: wanted,
            accessibilityGranted: AXIsProcessTrusted(),
            sessionIsActive: SessionActivity.shared.isActive,
            stageManagerEnabled: stageManagerEnabled(),
            cgWindowSignaturePresent: false,
            axGatePositive: false,
            snapshotFresh: false
        ).decision.monitor
        stateLock.withLock {
            eventState.settings = settings
            eventState.monitorWanted = shouldMonitor
        }
        if shouldMonitor {
            startMonitoring()
        } else {
            stop()
        }
    }

    func suspend() {
        stateLock.withLock { eventState.monitorWanted = false }
        stop()
    }

    // MARK: - Lifecycle

    private func startMonitoring() {
        startSnapshotTimer()
    }

    private func startEventTap() {
        guard lifecycleLock.withLock({ tap }) == nil else {
            return
        }
        let mask = [
            CGEventType.rightMouseDown, .rightMouseDragged, .rightMouseUp,
            .otherMouseDown, .otherMouseDragged, .otherMouseUp,
            .keyDown, .keyUp,
        ].reduce(CGEventMask(0)) { $0 | (CGEventMask(1) << $1.rawValue) }
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: { proxy, type, event, userInfo in
                guard let userInfo else { return Unmanaged.passUnretained(event) }
                let service = Unmanaged<MissionControlActionsService>
                    .fromOpaque(userInfo).takeUnretainedValue()
                return service.handle(proxy: proxy, type: type, event: event)
            },
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else { return }

        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        lifecycleLock.withLock {
            self.tap = tap
            runLoopSource = source
        }
        if let source { PointerTapRunLoop.add(source) }
        CGEvent.tapEnable(tap: tap, enable: true)
    }

    private func stop() {
        stopSnapshotTimer()
        stopEventTap()
        stateLock.withLock { eventState.snapshot = nil }
    }

    private func stopEventTap() {
        let pending = stateLock.withLock {
            () -> (CGEvent?, MissionControlPointerButton?, [Int64: PendingKey]) in
            let result = (eventState.pendingDown, eventState.pendingButton, eventState.pendingKeys)
            eventState.pointerGesture = MissionControlPointerGesture()
            eventState.pendingDown = nil
            eventState.pendingButton = nil
            eventState.pendingKeys = [:]
            return result
        }
        replayIfStillHeld(pending.0, button: pending.1, proxy: nil, point: nil)
        replayKeysIfStillHeld(pending.2)
        let (port, source) = lifecycleLock.withLock { () -> (CFMachPort?, CFRunLoopSource?) in
            let result = (tap, runLoopSource)
            tap = nil
            runLoopSource = nil
            return result
        }
        if let port { CGEvent.tapEnable(tap: port, enable: false) }
        if let source { PointerTapRunLoop.remove(source, invalidating: port) }
    }

    private func startSnapshotTimer() {
        guard snapshotTimer == nil else { return }
        stateLock.withLock { snapshotGeneration &+= 1 }
        let timer = Timer(timeInterval: Self.snapshotInterval, repeats: true) { [weak self] _ in
            self?.expirePendingPress()
            self?.expireTapIfSnapshotStale()
            self?.refreshSnapshot()
        }
        snapshotTimer = timer
        RunLoop.main.add(timer, forMode: .common)
        refreshSnapshot()
    }

    private func stopSnapshotTimer() {
        snapshotTimer?.invalidate()
        snapshotTimer = nil
        stateLock.withLock {
            snapshotGeneration &+= 1
            snapshotInFlightGeneration = nil
        }
    }

    private func refreshSnapshot() {
        let generation = stateLock.withLock { () -> UInt? in
            guard eventState.monitorWanted, snapshotInFlightGeneration == nil else { return nil }
            snapshotInFlightGeneration = snapshotGeneration
            return snapshotGeneration
        }
        guard let generation else { return }
        guard !stageManagerEnabled(), let windowManagerPID = currentWindowManagerPID() else {
            finishSnapshot(nil, generation: generation)
            return
        }
        snapshotQueue.async { [weak self] in
            guard let self else { return }
            let snapshot = self.captureSnapshot(windowManagerPID: windowManagerPID)
            DispatchQueue.main.async { [weak self] in
                self?.finishSnapshot(snapshot, generation: generation)
            }
        }
    }

    private func finishSnapshot(_ snapshot: CachedSnapshot?, generation: UInt) {
        let stageManagerIsEnabled = stageManagerEnabled()
        let accessibilityGranted = AXIsProcessTrusted()
        let sessionIsActive = SessionActivity.shared.isActive
        let shouldHoldTap = stateLock.withLock { () -> Bool? in
            guard snapshotInFlightGeneration == generation else { return nil }
            snapshotInFlightGeneration = nil
            guard snapshotGeneration == generation, eventState.monitorWanted else { return nil }
            eventState.snapshot = snapshot
            let fresh = snapshot?.timing.isUsable(
                now: ProcessInfo.processInfo.systemUptime
            ) == true
            return MissionControlRuntimeConditions(
                featureWanted: eventState.monitorWanted,
                accessibilityGranted: accessibilityGranted,
                sessionIsActive: sessionIsActive,
                stageManagerEnabled: stageManagerIsEnabled,
                cgWindowSignaturePresent: snapshot != nil,
                axGatePositive: snapshot?.hoveredTarget != nil,
                snapshotFresh: fresh
            ).decision.holdEventTap
        }
        guard let shouldHoldTap else { return }
        if shouldHoldTap {
            startEventTap()
        } else {
            stopEventTap()
        }
    }

    // MARK: - Snapshot (never on the tap thread)

    private func captureSnapshot(windowManagerPID: pid_t) -> CachedSnapshot? {
        let startedAt = ProcessInfo.processInfo.systemUptime
        guard !stageManagerEnabled() else { return nil }
        let windows = copyWindows(windowManagerPID: windowManagerPID)
        let cgSignature = MissionControlActionsSupport.cgWindowSignaturePresent(in: windows)
        guard MissionControlRuntimeConditions(
            featureWanted: true,
            accessibilityGranted: AXIsProcessTrusted(),
            sessionIsActive: true,
            stageManagerEnabled: false,
            cgWindowSignaturePresent: cgSignature,
            axGatePositive: false,
            snapshotFresh: false
        ).decision.captureAX,
              let pointer = CGEvent(source: nil)?.location else { return nil }
        let displayResult = copyAXDisplays(windowManagerPID: windowManagerPID)
        let display = displayResult.displays.filter { $0.frame.contains(pointer) }
        guard display.count == 1, let selectedDisplay = display.first else { return nil }
        let detection = MissionControlDetectionSnapshot(
            windowManagerBundleIdentifier: MissionControlActionsSupport.windowManagerBundleIdentifier,
            displayIdentifier: MissionControlActionsSupport.displayIdentifier,
            displayFrame: selectedDisplay.frame,
            displayChildrenCount: selectedDisplay.childrenCount,
            tiles: selectedDisplay.tiles,
            windows: windows,
            screenFrames: activeDisplayFrames(),
            axTreeComplete: displayResult.complete,
            stageManagerEnabled: false,
            ownPID: getpid()
        )
        let target = MissionControlActionsSupport.target(at: pointer, in: detection)
        let validatedTarget = target.flatMap(validatedTarget)
        let finishedAt = ProcessInfo.processInfo.systemUptime
        let timing = MissionControlSnapshotTiming(startedAt: startedAt, finishedAt: finishedAt)
        guard timing.isUsable(now: finishedAt) else { return nil }
        return CachedSnapshot(detection: detection,
                              hoveredTarget: validatedTarget,
                              timing: timing)
    }

    private func copyAXDisplays(windowManagerPID: pid_t) -> AXDisplayResult {
        let root = AXUIElementCreateApplication(windowManagerPID)
        _ = AXUIElementSetMessagingTimeout(root, Self.axMessagingTimeout)
        var displays: [AXDisplay] = []
        var visited: Set<CFHashCode> = []
        var nodes = 0
        var complete = true

        func walk(_ element: AXUIElement, depth: Int) {
            guard depth <= 5, nodes < 500 else {
                complete = false
                return
            }
            nodes += 1
            let identity = CFHash(element)
            guard visited.insert(identity).inserted else { return }
            _ = AXUIElementSetMessagingTimeout(element, Self.axMessagingTimeout)
            let childrenResult = axChildren(element)
            if !childrenResult.complete { complete = false }
            let children = childrenResult.children
            if axString(element, attribute: kAXIdentifierAttribute as String)
                == MissionControlActionsSupport.displayIdentifier,
               let frame = axFrame(element) {
                var tiles: [MissionControlTileSnapshot] = []
                var tileNodes = 0
                func collectTiles(_ candidate: AXUIElement, depth: Int) {
                    guard depth <= 3, tileNodes < 300 else {
                        complete = false
                        return
                    }
                    tileNodes += 1
                    _ = AXUIElementSetMessagingTimeout(candidate, Self.axMessagingTimeout)
                    if axString(candidate, attribute: kAXRoleAttribute as String) == "AXButton",
                       let tileFrame = axFrame(candidate),
                       let windowID = axWindowID(candidate) {
                        tiles.append(MissionControlTileSnapshot(
                            frame: tileFrame, role: "AXButton", windowID: windowID
                        ))
                    }
                    let result = axChildren(candidate)
                    if !result.complete { complete = false }
                    if depth == 3, !result.children.isEmpty { complete = false }
                    for child in result.children where depth < 3 {
                        collectTiles(child, depth: depth + 1)
                    }
                }
                for child in children { collectTiles(child, depth: 0) }
                displays.append(AXDisplay(frame: frame,
                                          childrenCount: children.count,
                                          tiles: tiles))
            }
            if depth == 5, !children.isEmpty { complete = false }
            for child in children where depth < 5 { walk(child, depth: depth + 1) }
        }
        walk(root, depth: 0)
        return AXDisplayResult(displays: displays, complete: complete)
    }

    private func copyWindows(windowManagerPID: pid_t) -> [MissionControlWindowSnapshot] {
        guard let rawWindows = CGWindowListCopyWindowInfo(.optionAll, kCGNullWindowID)
                as? [[String: Any]] else { return [] }
        return rawWindows.compactMap { window in
            guard let number = (window[kCGWindowNumber as String] as? NSNumber)?.uint32Value,
                  let ownerPID = (window[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value,
                  let layer = (window[kCGWindowLayer as String] as? NSNumber)?.intValue,
                  let bounds = WindowServerSupport.bounds(from: window) else { return nil }
            let onScreen = (window[kCGWindowIsOnscreen as String] as? NSNumber)?.boolValue ?? false
            let alpha = (window[kCGWindowAlpha as String] as? NSNumber)?.doubleValue ?? 1
            return MissionControlWindowSnapshot(
                windowID: CGWindowID(number), ownerPID: ownerPID,
                ownerIsWindowManager: ownerPID == windowManagerPID,
                layer: layer, bounds: bounds, onScreen: onScreen, alpha: alpha
            )
        }
    }

    private func activeDisplayFrames() -> [CGRect] {
        var count: UInt32 = 0
        guard CGGetActiveDisplayList(0, nil, &count) == .success, count > 0 else { return [] }
        var displays = [CGDirectDisplayID](repeating: 0, count: Int(count))
        guard CGGetActiveDisplayList(count, &displays, &count) == .success else { return [] }
        return displays.prefix(Int(count)).map(CGDisplayBounds)
    }

    private func axChildren(_ element: AXUIElement) -> AXChildrenResult {
        var rawNames: CFArray?
        guard AXUIElementCopyAttributeNames(element, &rawNames) == .success,
              let names = rawNames as? [String] else {
            return AXChildrenResult(children: [], complete: false)
        }
        guard names.contains(kAXChildrenAttribute as String) else {
            return AXChildrenResult(children: [], complete: true)
        }
        var value: CFTypeRef?
        let error = AXUIElementCopyAttributeValue(
            element, kAXChildrenAttribute as CFString, &value
        )
        switch error {
        case .success:
            guard let children = value as? [AXUIElement] else {
                return AXChildrenResult(children: [], complete: false)
            }
            return AXChildrenResult(children: children, complete: true)
        default:
            return AXChildrenResult(children: [], complete: false)
        }
    }

    private func axString(_ element: AXUIElement, attribute: String) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success
        else { return nil }
        return value as? String
    }

    private func axFrame(_ element: AXUIElement) -> CGRect? {
        var positionValue: CFTypeRef?
        var sizeValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
                element, kAXPositionAttribute as CFString, &positionValue
              ) == .success,
              AXUIElementCopyAttributeValue(
                element, kAXSizeAttribute as CFString, &sizeValue
              ) == .success,
              let rawPosition = positionValue, let rawSize = sizeValue,
              CFGetTypeID(rawPosition) == AXValueGetTypeID(),
              CFGetTypeID(rawSize) == AXValueGetTypeID() else { return nil }
        let positionAX = unsafeDowncast(rawPosition, to: AXValue.self)
        let sizeAX = unsafeDowncast(rawSize, to: AXValue.self)
        var point = CGPoint.zero
        var size = CGSize.zero
        guard AXValueGetType(positionAX) == .cgPoint,
              AXValueGetType(sizeAX) == .cgSize,
              AXValueGetValue(positionAX, .cgPoint, &point),
              AXValueGetValue(sizeAX, .cgSize, &size) else { return nil }
        return CGRect(origin: point, size: size)
    }

    private func axWindowID(_ element: AXUIElement) -> CGWindowID? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, "wid" as CFString, &value) == .success,
              let value, CFGetTypeID(value) == CFNumberGetTypeID() else { return nil }
        var number: Int64 = 0
        guard CFNumberGetValue(unsafeDowncast(value, to: CFNumber.self), .sInt64Type, &number),
              number > 0, let result = CGWindowID(exactly: number) else { return nil }
        return result
    }

    private func validatedTarget(_ target: MissionControlTarget) -> MissionControlValidatedTarget? {
        guard target.ownerPID != getpid(),
              let app = NSRunningApplication(processIdentifier: target.ownerPID),
              !app.isTerminated,
              let launchDate = app.launchDate else { return nil }
        let appElement = AXUIElementCreateApplication(target.ownerPID)
        _ = AXUIElementSetMessagingTimeout(appElement, Self.axMessagingTimeout)
        guard let window = AXWindowResolver.element(
            for: target.windowID, in: appElement, pid: target.ownerPID
        ) else { return nil }
        _ = AXUIElementSetMessagingTimeout(window, Self.axMessagingTimeout)
        return MissionControlValidatedTarget(
            target: target,
            processIdentity: MissionControlProcessIdentity(
                processIdentifier: target.ownerPID,
                launchTime: launchDate.timeIntervalSinceReferenceDate
            ),
            windowResolved: true
        )
    }

    private func currentWindowManagerPID() -> pid_t? {
        NSRunningApplication.runningApplications(
            withBundleIdentifier: MissionControlActionsSupport.windowManagerBundleIdentifier
        ).first(where: { !$0.isTerminated })?.processIdentifier
    }

    private func stageManagerEnabled() -> Bool {
        UserDefaults(suiteName: MissionControlActionsSupport.windowManagerBundleIdentifier)?
            .bool(forKey: "GloballyEnabled") == true
    }

    // MARK: - Event callback (cached values only)

    private func handle(proxy: CGEventTapProxy?, type: CGEventType,
                        event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            return recoverDisabledTap(proxy: proxy, event: event)
        }
        if event.getIntegerValueField(.eventSourceUserData) == Self.replayedPressMarker {
            return Unmanaged.passUnretained(event)
        }
        switch type {
        case .rightMouseDown, .otherMouseDown:
            return handlePointerDown(type: type, event: event)
        case .rightMouseDragged, .otherMouseDragged:
            return handlePointerDrag(type: type, proxy: proxy, event: event)
        case .rightMouseUp, .otherMouseUp:
            return handlePointerUp(type: type, proxy: proxy, event: event)
        case .keyDown, .keyUp:
            return handleKey(type: type, event: event)
        default:
            return Unmanaged.passUnretained(event)
        }
    }

    private func handlePointerDown(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        guard let button = pointerButton(type: type, event: event) else {
            return Unmanaged.passUnretained(event)
        }
        let input: MissionControlInput = button == .right ? .rightClick : .middleClick
        guard let down = event.copy() else { return Unmanaged.passUnretained(event) }
        let result = stateLock.withLock {
            () -> (MissionControlPointerDecision, CGEvent?, MissionControlPointerButton?) in
            let staleDown = eventState.pendingDown
            let staleButton = eventState.pendingButton
            _ = eventState.pointerGesture.resolveBeforeNewDown()
            eventState.pendingDown = nil
            eventState.pendingButton = nil
            let action = MissionControlActionsSupport.action(
                for: input, settings: eventState.settings
            ) ?? .none
            let target = cachedTarget(at: event.location, action: action)
            let decision = eventState.pointerGesture.beginDown(
                button: button, point: event.location, target: target, action: action,
                now: ProcessInfo.processInfo.systemUptime
            )
            if decision == .suppress {
                eventState.pendingDown = down
                eventState.pendingButton = button
            }
            return (decision, staleDown, staleButton)
        }
        // A same-button down proves the old press was released and its up was
        // lost, so replaying its old coordinates would invent a click. A
        // different still-held button can safely regain its native down.
        if result.2 != button {
            replayIfStillHeld(result.1, button: result.2, proxy: nil, point: nil)
        }
        return result.0 == .suppress ? nil : Unmanaged.passUnretained(event)
    }

    private func handlePointerDrag(type: CGEventType, proxy: CGEventTapProxy?,
                                   event: CGEvent) -> Unmanaged<CGEvent>? {
        guard let button = pointerButton(type: type, event: event) else {
            return Unmanaged.passUnretained(event)
        }
        let result = stateLock.withLock {
            () -> (MissionControlPointerDecision, CGEvent?) in
            let decision = eventState.pointerGesture.drag(button: button, point: event.location)
            let down = decision == .replayDownAndPass ? eventState.pendingDown : nil
            if decision == .replayDownAndPass {
                eventState.pendingDown = nil
                eventState.pendingButton = nil
            }
            return (decision, down)
        }
        switch result.0 {
        case .suppress:
            return nil
        case .replayDownAndPass:
            replay(result.1, proxy: proxy, point: nil)
            return Unmanaged.passUnretained(event)
        case .passThrough, .revalidate, .replayPairNoAction:
            return Unmanaged.passUnretained(event)
        }
    }

    private func handlePointerUp(type: CGEventType, proxy _: CGEventTapProxy?,
                                 event: CGEvent) -> Unmanaged<CGEvent>? {
        guard let button = pointerButton(type: type, event: event) else {
            return Unmanaged.passUnretained(event)
        }
        guard let up = event.copy() else { return Unmanaged.passUnretained(event) }
        let result = stateLock.withLock {
            () -> (MissionControlPointerDecision, CGEvent?) in
            let decision = eventState.pointerGesture.endUp(
                button: button, point: event.location,
                now: ProcessInfo.processInfo.systemUptime
            )
            switch decision {
            case .revalidate, .replayPairNoAction:
                let down = eventState.pendingDown
                eventState.pendingDown = nil
                eventState.pendingButton = nil
                return (decision, down)
            case .passThrough, .suppress, .replayDownAndPass:
                return (decision, nil)
            }
        }
        switch result.0 {
        case .revalidate(let pending):
            guard let down = result.1 else { return Unmanaged.passUnretained(event) }
            revalidate(pending, replayEvents: [down, up])
            return nil
        case .replayPairNoAction:
            replayPair(result.1, up)
            return nil
        case .passThrough, .suppress, .replayDownAndPass:
            return Unmanaged.passUnretained(event)
        }
    }

    private func handleKey(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
        if type == .keyUp {
            guard let up = event.copy() else { return Unmanaged.passUnretained(event) }
            let pending = stateLock.withLock { eventState.pendingKeys.removeValue(forKey: keyCode) }
            guard let pending else { return Unmanaged.passUnretained(event) }
            if ProcessInfo.processInfo.systemUptime - pending.startedAt
                > MissionControlPointerGesture.maximumHoldDuration {
                replayPair(pending.down, up)
            } else {
                revalidate(pending.pendingAction, replayEvents: [pending.down, up])
            }
            return nil
        }
        let relevantFlags = event.flags.intersection([
            .maskCommand, .maskControl, .maskAlternate, .maskShift
        ])
        guard relevantFlags == .maskCommand,
              let input = keyInput(keyCode) else { return Unmanaged.passUnretained(event) }
        guard let down = event.copy() else { return Unmanaged.passUnretained(event) }
        return stateLock.withLock {
            if eventState.pendingKeys[keyCode] != nil { return nil }
            guard let action = MissionControlActionsSupport.action(
                    for: input, settings: eventState.settings
                  ), action != .none,
                  let target = cachedTarget(at: event.location, action: action) else {
                return Unmanaged.passUnretained(event)
            }
            eventState.pendingKeys[keyCode] = PendingKey(
                down: down,
                pendingAction: MissionControlPendingAction(target: target, action: action),
                startedAt: ProcessInfo.processInfo.systemUptime
            )
            return nil
        }
    }

    private func recoverDisabledTap(proxy: CGEventTapProxy?,
                                    event: CGEvent) -> Unmanaged<CGEvent>? {
        let pending = stateLock.withLock {
            () -> (CGEvent?, MissionControlPointerButton?, [Int64: PendingKey]) in
            let result = (eventState.pendingDown, eventState.pendingButton, eventState.pendingKeys)
            _ = eventState.pointerGesture.reset()
            eventState.pendingDown = nil
            eventState.pendingButton = nil
            eventState.pendingKeys = [:]
            return result
        }
        replayIfStillHeld(pending.0, button: pending.1, proxy: proxy, point: nil)
        replayKeysIfStillHeld(pending.2)
        let (heldTap, shouldRun) = (
            lifecycleLock.withLock { tap },
            stateLock.withLock {
                guard eventState.monitorWanted, let snapshot = eventState.snapshot,
                      snapshot.hoveredTarget != nil else { return false }
                return MissionControlRuntimeConditions(
                    featureWanted: true,
                    accessibilityGranted: AXIsProcessTrusted(),
                    sessionIsActive: SessionActivity.shared.isActive,
                    stageManagerEnabled: stageManagerEnabled(),
                    cgWindowSignaturePresent: true,
                    axGatePositive: true,
                    snapshotFresh: snapshot.timing.isUsable(
                        now: ProcessInfo.processInfo.systemUptime
                    )
                ).decision.holdEventTap
            }
        )
        switch SessionActivitySupport.disabledTapRecovery(
            tapHeld: heldTap != nil, tapShouldRun: shouldRun
        ) {
        case .rearm:
            if let heldTap { CGEvent.tapEnable(tap: heldTap, enable: true) }
        case .tearDown:
            DispatchQueue.main.async { [weak self] in self?.syncWithPreferences() }
        case .leaveStopped:
            break
        }
        return Unmanaged.passUnretained(event)
    }

    private func cachedTarget(at point: CGPoint,
                              action: MissionControlAction) -> MissionControlValidatedTarget? {
        guard action != .none, let snapshot = eventState.snapshot,
              snapshot.timing.isUsable(now: ProcessInfo.processInfo.systemUptime),
              let target = MissionControlActionsSupport.target(
                at: point, in: snapshot.detection
              ), let hovered = snapshot.hoveredTarget,
              target == hovered.target,
              hovered.windowResolved else { return nil }
        return hovered
    }

    private func pointerButton(type: CGEventType,
                               event: CGEvent) -> MissionControlPointerButton? {
        if type == .rightMouseDown || type == .rightMouseDragged || type == .rightMouseUp {
            return .right
        }
        guard event.getIntegerValueField(.mouseEventButtonNumber) == 2 else { return nil }
        return .middle
    }

    private func keyInput(_ keyCode: Int64) -> MissionControlInput? {
        switch Int(keyCode) {
        case kVK_ANSI_W: return .commandW
        case kVK_ANSI_Q: return .commandQ
        case kVK_ANSI_H: return .commandH
        case kVK_ANSI_M: return .commandM
        default: return nil
        }
    }

    private func revalidate(_ pending: MissionControlPendingAction,
                            replayEvents: [CGEvent]) {
        let generation = stateLock.withLock { snapshotGeneration }
        snapshotQueue.async { [weak self] in
            guard let self else { return }
            let fresh: MissionControlValidatedTarget?
            if AXIsProcessTrusted(), !self.stageManagerEnabled(),
               let windowManagerPID = self.currentWindowManagerPID() {
                fresh = self.captureSnapshot(windowManagerPID: windowManagerPID)?.hoveredTarget
            } else {
                fresh = nil
            }
            let decision = MissionControlRevalidationSupport.decision(
                original: pending, freshTarget: fresh, ownPID: getpid()
            )
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                let runtimeStillValid = self.stateLock.withLock {
                    self.snapshotGeneration == generation && self.eventState.monitorWanted
                } && AXIsProcessTrusted()
                    && SessionActivity.shared.isActive
                    && !self.stageManagerEnabled()
                guard runtimeStillValid, decision == .perform,
                      self.perform(pending) else {
                    self.replay(replayEvents)
                    return
                }
            }
        }
    }

    private func perform(_ pending: MissionControlPendingAction) -> Bool {
        let target = pending.target.target
        guard target.ownerPID != getpid(),
              let app = NSRunningApplication(processIdentifier: target.ownerPID),
              !app.isTerminated,
              let launchDate = app.launchDate,
              MissionControlProcessIdentity(
                processIdentifier: app.processIdentifier,
                launchTime: launchDate.timeIntervalSinceReferenceDate
              ) == pending.target.processIdentity else { return false }

        let appElement = AXUIElementCreateApplication(target.ownerPID)
        _ = AXUIElementSetMessagingTimeout(appElement, Self.axMessagingTimeout)
        guard let window = AXWindowResolver.element(
            for: target.windowID, in: appElement, pid: target.ownerPID
        ) else { return false }
        _ = AXUIElementSetMessagingTimeout(window, Self.axMessagingTimeout)

        switch pending.action {
        case .none:
            return false
        case .closeWindow:
            return WindowActivator.closeWindow(
                windowID: target.windowID,
                appPID: target.ownerPID,
                windowOwnerPID: target.ownerPID
            )
        case .minimizeWindow:
            return WindowActivator.setWindowMinimized(
                true, windowID: target.windowID, pid: target.ownerPID
            )
        case .terminateApp:
            return app.terminate()
        case .hideApp:
            return app.hide()
        }
    }

    private func expirePendingPress() {
        let pending = stateLock.withLock { () -> (CGEvent?, MissionControlPointerButton?) in
            guard eventState.pointerGesture.expire(
                now: ProcessInfo.processInfo.systemUptime
            ) == .replayIfStillHeld else { return (nil, nil) }
            let result = (eventState.pendingDown, eventState.pendingButton)
            eventState.pendingDown = nil
            eventState.pendingButton = nil
            return result
        }
        replayIfStillHeld(pending.0, button: pending.1, proxy: nil, point: nil)
    }

    private func expireTapIfSnapshotStale() {
        let expired = stateLock.withLock { () -> Bool in
            guard let snapshot = eventState.snapshot,
                  !snapshot.timing.isUsable(now: ProcessInfo.processInfo.systemUptime) else {
                return false
            }
            eventState.snapshot = nil
            return true
        }
        if expired { stopEventTap() }
    }

    private func replayIfStillHeld(_ event: CGEvent?,
                                   button: MissionControlPointerButton?,
                                   proxy: CGEventTapProxy?, point: CGPoint?) {
        guard let button else { return }
        let cgButton: CGMouseButton = button == .right ? .right : .center
        guard CGEventSource.buttonState(.combinedSessionState, button: cgButton) else { return }
        replay(event, proxy: proxy, point: point)
    }

    private func replayKeysIfStillHeld(_ pending: [Int64: PendingKey]) {
        for (rawKeyCode, key) in pending {
            guard let keyCode = CGKeyCode(exactly: rawKeyCode),
                  CGEventSource.keyState(.combinedSessionState, key: keyCode) else { continue }
            replay(key.down, proxy: nil, point: nil)
        }
    }

    private func replay(_ event: CGEvent?, proxy: CGEventTapProxy?, point: CGPoint?) {
        guard let event else { return }
        if let point { event.location = point }
        event.setIntegerValueField(.eventSourceUserData, value: Self.replayedPressMarker)
        if let proxy {
            event.tapPostEvent(proxy)
        } else {
            event.post(tap: .cgSessionEventTap)
        }
    }

    private func replayPair(_ down: CGEvent?, _ up: CGEvent?) {
        replay([down, up].compactMap { $0 })
    }

    private func replay(_ events: [CGEvent]) {
        for event in events {
            replay(event, proxy: nil, point: nil)
        }
    }
}
