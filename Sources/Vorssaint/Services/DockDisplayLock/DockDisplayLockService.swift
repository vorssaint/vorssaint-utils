// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import ApplicationServices
import Combine
import CoreGraphics
import Foundation

/// Keeps the Dock on one chosen display. Pointer moves and drags that press
/// on the Dock edge of any other display are held back from the event
/// stream, so the Dock never sees the request to move; everything else passes
/// untouched. The Dock can be called back to its display on demand, and
/// optionally after sleep or a display change. Requires Accessibility.
final class DockDisplayLockService: ObservableObject {
    static let shared = DockDisplayLockService()

    @Published private(set) var isRunning = false
    /// The connected displays, for the settings picker.
    @Published private(set) var displays: [DockDisplayLockDisplay] = []
    /// The display the Dock is held to right now: the chosen one, or the main
    /// display while the chosen one is away.
    @Published private(set) var anchorID: CGDirectDisplayID?
    /// Where the Dock sits, as last read through Accessibility.
    @Published private(set) var dockDisplayID: CGDirectDisplayID?
    @Published private(set) var isMovingDock = false

    private let zoneLock = NSLock()
    private let lifecycleLock = NSLock()
    private var tap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var tapRunLoop: CFRunLoop?
    private var tapThread: Thread?
    private var shouldStopTapThread = false
    private var pendingStartAfterStop = false
    private var lifecycleGeneration: UInt = 0
    // Read by the tap on every move, so kept behind `zoneLock`.
    private var zones = DockDisplayLockSupport.Zones.none
    private var inCorner = false
    private var holdsPointerForMove = false

    // Main thread only.
    private var orientation = DockPreviewOrientation.bottom
    private var hotCorners: Set<DockDisplayLockCorner> = []
    private var observers: [(center: NotificationCenter, token: NSObjectProtocol)] = []
    private var preferencesTimer: Timer?
    private var pendingReturn: DispatchWorkItem?
    private let moveQueue = DispatchQueue(label: "com.vorssaint.dock-display-lock.move", qos: .userInitiated)

    /// Marks the moves this service posts to call the Dock over, so its own
    /// tap lets them through while it holds the real pointer still.
    private static let syntheticEventMarker: Int64 = 0x444F434B // "DOCK"
    private static let dockBundleID = "com.apple.dock"

    private init() {
        SessionActivity.shared.onChange { [weak self] _ in self?.syncWithPreferences() }
    }

    // MARK: - Lifecycle

    private var isWanted: Bool {
        AppFeature.dockDisplayLock.isAvailable
            && UserDefaults.standard.bool(forKey: DefaultsKey.dockDisplayLockEnabled)
    }

    func syncWithPreferences() {
        if SessionActivitySupport.tapShouldRun(featureWanted: isWanted,
                                               accessibilityGranted: AXIsProcessTrusted(),
                                               sessionIsActive: SessionActivity.shared.isActive) {
            startObserving()
            refresh()
            start()
        } else {
            stop()
            stopObserving()
        }
    }

    func suspend() {
        stop()
        stopObserving()
    }

    private var target: DockDisplayLockTarget {
        DockDisplayLockTarget(storage: UserDefaults.standard.string(forKey: DefaultsKey.dockDisplayLockTarget))
    }

    private var returnsAutomatically: Bool {
        UserDefaults.standard.bool(forKey: DefaultsKey.dockDisplayLockReturns)
    }

    /// Reads the arrangement, the Dock's side and Hot Corners again and hands
    /// the tap the zones they make. `readingDock` also asks Accessibility
    /// where the Dock is, which only the settings card shows.
    func refresh(readingDock: Bool = true) {
        let displays = Self.readDisplays()
        let domain = UserDefaults.standard.persistentDomain(forName: Self.dockBundleID) ?? [:]
        orientation = DockPreviewOrientation.sanitized(domain["orientation"] as? String)
        hotCorners = DockDisplayLockCorner.actions(in: domain)
        let anchor = DockDisplayLockSupport.anchor(for: target, in: displays)
        // With one set of Spaces across all displays, macOS never moves the
        // Dock between them, so there is nothing to hold back. The setting
        // only changes with a new login.
        let next = NSScreen.screensHaveSeparateSpaces
            ? DockDisplayLockSupport.zones(displays: displays, anchorID: anchor?.id,
                                           orientation: orientation, hotCorners: hotCorners)
            : .none
        zoneLock.withLock {
            if zones != next { inCorner = false }
            zones = next
        }
        if self.displays != displays { self.displays = displays }
        if anchorID != anchor?.id { anchorID = anchor?.id }
        if readingDock { readDockDisplay() }
    }

    private func startObserving() {
        guard observers.isEmpty else { return }
        let center = NotificationCenter.default
        let workspace = NSWorkspace.shared.notificationCenter
        let distributed = DistributedNotificationCenter.default()
        observers = [
            (center, center.addObserver(forName: NSApplication.didChangeScreenParametersNotification,
                                        object: nil, queue: .main) { [weak self] _ in
                self?.refresh()
                self?.scheduleReturn(after: 1)
            }),
            // macOS can put the Dock back on the main display after a sleep.
            (workspace, workspace.addObserver(forName: NSWorkspace.didWakeNotification,
                                              object: nil, queue: .main) { [weak self] _ in
                self?.scheduleReturn(after: 3)
            }),
            // Only once someone is at the Mac: moving the pointer under the
            // lock screen would read as that someone (DockAnchor #39).
            (distributed, distributed.addObserver(forName: Notification.Name("com.apple.screenIsUnlocked"),
                                                  object: nil, queue: .main) { [weak self] _ in
                self?.scheduleReturn(after: 1)
            }),
        ]
        // Position, Hot Corners: changes made in System Settings, with no
        // notification of their own. The read is one preference domain.
        let timer = Timer(timeInterval: 10, repeats: true) { [weak self] _ in self?.refresh(readingDock: false) }
        timer.tolerance = 2.5
        RunLoop.main.add(timer, forMode: .common)
        preferencesTimer = timer
    }

    private func stopObserving() {
        for observer in observers {
            observer.center.removeObserver(observer.token)
        }
        observers = []
        preferencesTimer?.invalidate()
        preferencesTimer = nil
        pendingReturn?.cancel()
        pendingReturn = nil
    }

    private func start() {
        let startState = lifecycleLock.withLock { () -> (thread: Thread?, publishRunning: Bool, generation: UInt) in
            if tapThread != nil {
                if shouldStopTapThread {
                    pendingStartAfterStop = true
                    return (nil, false, lifecycleGeneration)
                }
                return (nil, true, lifecycleGeneration)
            }
            shouldStopTapThread = false
            pendingStartAfterStop = false
            lifecycleGeneration &+= 1
            let generation = lifecycleGeneration
            let thread = Thread { [weak self] in
                self?.runEventTap(generation: generation)
            }
            thread.name = "Vorssaint Dock Display Lock"
            thread.qualityOfService = .userInteractive
            tapThread = thread
            return (thread, false, generation)
        }

        if let thread = startState.thread {
            thread.start()
        } else if startState.publishRunning {
            publishRunning(true, generation: startState.generation)
        }
    }

    private func stop() {
        zoneLock.withLock {
            zones = .none
            inCorner = false
            holdsPointerForMove = false
        }

        let snapshot = lifecycleLock.withLock {
            () -> (runLoop: CFRunLoop?, tap: CFMachPort?, threadExists: Bool, generation: UInt) in
            shouldStopTapThread = true
            pendingStartAfterStop = false
            lifecycleGeneration &+= 1
            return (tapRunLoop, tap, tapThread != nil, lifecycleGeneration)
        }

        if let tap = snapshot.tap {
            CGEvent.tapEnable(tap: tap, enable: false)
            CFMachPortInvalidate(tap)
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
        publishRunning(false, generation: snapshot.generation)
    }

    private func runEventTap(generation: UInt) {
        autoreleasepool {
            let runLoop = CFRunLoopGetCurrent()
            lifecycleLock.withLock {
                tapRunLoop = runLoop
            }

            let shouldStopBeforeCreatingTap = lifecycleLock.withLock {
                shouldStopTapThread
            }
            guard !shouldStopBeforeCreatingTap else {
                let shouldRestart = clearEventTapThread()
                if shouldRestart {
                    start()
                } else {
                    publishRunning(false, generation: generation)
                }
                return
            }

            // Drags press on an edge just as moves do: a file carried to the
            // bottom of another display used to take the Dock with it
            // (DockAnchor #30).
            let mask = [CGEventType.mouseMoved, .leftMouseDragged, .rightMouseDragged, .otherMouseDragged]
                .reduce(CGEventMask(0)) { $0 | (CGEventMask(1) << $1.rawValue) }
            guard let tap = CGEvent.tapCreate(
                tap: .cgSessionEventTap,
                place: .headInsertEventTap,
                options: .defaultTap,
                eventsOfInterest: mask,
                callback: { _, type, event, userInfo in
                    guard let userInfo else { return Unmanaged.passUnretained(event) }
                    let service = Unmanaged<DockDisplayLockService>.fromOpaque(userInfo).takeUnretainedValue()
                    return service.handle(type: type, event: event)
                },
                userInfo: Unmanaged.passUnretained(self).toOpaque()
            ) else {
                _ = clearEventTapThread()
                publishRunning(false, generation: generation)
                return
            }

            let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
            lifecycleLock.withLock {
                self.tap = tap
                runLoopSource = source
            }
            CFRunLoopAddSource(runLoop, source, .commonModes)
            CGEvent.tapEnable(tap: tap, enable: true)

            let shouldStop = lifecycleLock.withLock {
                shouldStopTapThread
            }
            if shouldStop {
                CGEvent.tapEnable(tap: tap, enable: false)
            } else {
                publishRunning(true, generation: generation)
                CFRunLoopRun()
            }

            CGEvent.tapEnable(tap: tap, enable: false)
            CFRunLoopRemoveSource(runLoop, source, .commonModes)
            CFMachPortInvalidate(tap)
            let shouldRestart = clearEventTapThread()
            if shouldRestart {
                start()
            } else {
                publishRunning(false, generation: generation)
            }
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

    private func publishRunning(_ running: Bool, generation: UInt) {
        let update = { [weak self] in
            guard let self else { return }
            let isCurrent = self.lifecycleLock.withLock {
                generation == self.lifecycleGeneration
            }
            guard isCurrent else { return }
            self.isRunning = running
        }

        if Thread.isMainThread {
            update()
        } else {
            DispatchQueue.main.async(execute: update)
        }
    }

    private func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            // A stop under way switches the tap off itself; there is nothing
            // to recover then. Without Accessibility the tap must go, not
            // come back.
            let currentTap = lifecycleLock.withLock { shouldStopTapThread ? nil : tap }
            if SessionActivity.shared.isActive, AXIsProcessTrusted(), let currentTap {
                CGEvent.tapEnable(tap: currentTap, enable: true)
            } else if currentTap != nil {
                DispatchQueue.main.async { [weak self] in self?.syncWithPreferences() }
            }
            return Unmanaged.passUnretained(event)
        }

        let isOwnMove = event.getIntegerValueField(.eventSourceUserData) == Self.syntheticEventMarker
        let location = event.location
        let blocked = zoneLock.withLock { () -> Bool in
            // While the Dock is being called over, the real pointer waits so
            // it cannot pull the path off the edge.
            if holdsPointerForMove { return !isOwnMove }
            return DockDisplayLockSupport.blocks(location, zones: zones, inCorner: &inCorner)
        }
        return blocked ? nil : Unmanaged.passUnretained(event)
    }

    // MARK: - Displays and the Dock

    private static func readDisplays() -> [DockDisplayLockDisplay] {
        var ids = [CGDirectDisplayID](repeating: 0, count: 16)
        var count: UInt32 = 0
        guard CGGetActiveDisplayList(UInt32(ids.count), &ids, &count) == .success else { return [] }
        let screenNumber = NSDeviceDescriptionKey("NSScreenNumber")
        let names = Dictionary(NSScreen.screens.compactMap { screen -> (CGDirectDisplayID, String)? in
            guard let id = (screen.deviceDescription[screenNumber] as? NSNumber)?.uint32Value else { return nil }
            return (id, screen.localizedName)
        }, uniquingKeysWith: { first, _ in first })
        return ids.prefix(Int(count)).compactMap { id in
            // A display mirroring another shows the same desktop and has no
            // Dock edge of its own.
            guard CGDisplayMirrorsDisplay(id) == kCGNullDirectDisplay,
                  let uuid = CGDisplayCreateUUIDFromDisplayID(id)?.takeRetainedValue()
            else { return nil }
            return DockDisplayLockDisplay(id: id,
                                          uuid: CFUUIDCreateString(nil, uuid) as String,
                                          name: names[id] ?? "",
                                          frame: CGDisplayBounds(id),
                                          isMain: CGDisplayIsMain(id) != 0,
                                          isBuiltIn: CGDisplayIsBuiltin(id) != 0)
        }
    }

    /// Finds the Dock's icon list through Accessibility and the display it
    /// sits on.
    func readDockDisplay() {
        let found = Self.dockListFrame().flatMap {
            DockDisplayLockSupport.display(holdingDockFrame: $0, orientation: orientation, displays: displays)
        }
        if dockDisplayID != found { dockDisplayID = found }
    }

    private static func dockListFrame() -> CGRect? {
        guard AXIsProcessTrusted(),
              let pid = NSRunningApplication.runningApplications(withBundleIdentifier: dockBundleID)
                .first?.processIdentifier
        else { return nil }
        let dock = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(dock, 0.35)
        var children: CFTypeRef?
        guard AXUIElementCopyAttributeValue(dock, kAXChildrenAttribute as CFString, &children) == .success,
              let elements = children as? [AXUIElement]
        else { return nil }
        for element in elements {
            var role: CFTypeRef?
            guard AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &role) == .success,
                  role as? String == "AXList"
            else { continue }
            var positionValue: CFTypeRef?
            var sizeValue: CFTypeRef?
            guard AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString, &positionValue) == .success,
                  AXUIElementCopyAttributeValue(element, kAXSizeAttribute as CFString, &sizeValue) == .success,
                  let positionValue, let sizeValue,
                  CFGetTypeID(positionValue) == AXValueGetTypeID(), CFGetTypeID(sizeValue) == AXValueGetTypeID()
            else { continue }
            var position = CGPoint.zero
            var size = CGSize.zero
            guard AXValueGetValue(positionValue as! AXValue, .cgPoint, &position),
                  AXValueGetValue(sizeValue as! AXValue, .cgSize, &size)
            else { continue }
            return CGRect(origin: position, size: size)
        }
        return nil
    }

    // MARK: - Calling the Dock over

    /// After sleep, an unlock or a change of displays, the Dock goes back to
    /// its display when the user asked for that. Several triggers in a row
    /// end in one move.
    private func scheduleReturn(after delay: TimeInterval) {
        guard returnsAutomatically else { return }
        pendingReturn?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.pendingReturn = nil
            self.refresh()
            self.moveDockToAnchor()
        }
        pendingReturn = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    /// Calls the Dock to the display it is held to, by pressing the pointer
    /// against that display's Dock edge the way a person would, and puts the
    /// pointer back. Nothing happens when the Dock is already there.
    func moveDockToAnchor() {
        guard isWanted, !isMovingDock, SessionActivity.shared.isActive, AXIsProcessTrusted(),
              !Self.screenIsLocked, displays.count > 1,
              let anchor = displays.first(where: { $0.id == anchorID })
        else { return }
        readDockDisplay()
        guard dockDisplayID != anchor.id else { return }

        isMovingDock = true
        let path = DockDisplayLockSupport.summonPath(to: anchor, orientation: orientation)
        moveQueue.async { [weak self] in
            guard let self else { return }
            let source = CGEventSource(stateID: .hidSystemState)
            let original = CGEvent(source: nil)?.location
            self.zoneLock.withLock { self.holdsPointerForMove = true }
            for (index, step) in path.enumerated() {
                CGWarpMouseCursorPosition(step.point)
                self.postMove(to: step.point, delta: step.delta, source: source)
                Thread.sleep(forTimeInterval: index < path.count - 10 ? 0.015 : 0.025)
            }
            self.zoneLock.withLock { self.holdsPointerForMove = false }
            if let original {
                CGWarpMouseCursorPosition(original)
                // A warp alone moves no event past the Dock, which then keeps
                // its icons magnified under a pointer that left (DockAnchor #35).
                self.postMove(to: original, delta: .zero, source: source)
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                self.isMovingDock = false
                self.readDockDisplay()
            }
        }
    }

    /// The lock screen is up, or a Mac woke to it: no pointer moves there.
    private static var screenIsLocked: Bool {
        let session = CGSessionCopyCurrentDictionary() as? [String: Any]
        return (session?["CGSSessionScreenIsLocked"] as? NSNumber)?.boolValue ?? false
    }

    private func postMove(to point: CGPoint, delta: CGVector, source: CGEventSource?) {
        guard let event = CGEvent(mouseEventSource: source, mouseType: .mouseMoved,
                                  mouseCursorPosition: point, mouseButton: .left) else { return }
        event.setIntegerValueField(.eventSourceUserData, value: Self.syntheticEventMarker)
        event.setIntegerValueField(.mouseEventDeltaX, value: Int64(delta.dx))
        event.setIntegerValueField(.mouseEventDeltaY, value: Int64(delta.dy))
        event.post(tap: .cghidEventTap)
    }
}
