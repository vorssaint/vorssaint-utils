// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import ApplicationServices
import CoreGraphics
import Foundation
import IOKit

final class TrackpadEdgeService: ObservableObject {
    static let shared = TrackpadEdgeService()

    static let replayedClickMarker: Int64 = 0x5654_5045

    @Published private(set) var isRunning = false
    @Published private(set) var touchDeviceMissing = false
    @Published private(set) var activeEdge: TrackpadEdge?
    @Published private(set) var flashedTarget: TrackpadTapTarget?

    private struct HeldClick {
        let generation: Int
        let location: CGPoint
        var released: Bool
    }

    private enum Haptic {
        case tick, limit, action, mute
    }

    private let stateLock = NSLock()
    private var recognizer = TrackpadEdgeRecognizer(configuration: .standard)
    private var modifier = TrackpadEdgeModifier.none
    private var freezeCursor = true
    private var cursorAnchor: CGPoint?
    private var pointerDetached = false
    private var swallowingButton = false
    private var heldClick: HeldClick?
    private var activeDevice: UnsafeMutableRawPointer?

    private let tapLock = NSLock()
    private var tap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?

    private var deviceList: CFArray?
    private var observers: [Any] = []
    private var hotplugPort: IONotificationPortRef?
    private var hotplugIterators: [io_iterator_t] = []

    private var configuration = TrackpadEdgeConfiguration.standard
    private var hapticsEnabled = true
    private var level: Double?
    private var levelGeneration = 0
    private var atBound = false
    private var mutedNoticeShown = false
    private var flashWork: DispatchWorkItem?
    private let levelQueue = DispatchQueue(label: "com.vorssaint.utils.trackpad-edges.level", qos: .userInitiated)

    private init() {
        SessionActivity.shared.onChange { [weak self] _ in
            self?.syncWithPreferences()
        }
    }

    var strings: TrackpadEdgeStrings { FeatureStrings.trackpadEdges(L10n.shared.language) }

    func syncWithPreferences() {
        let defaults = UserDefaults.standard
        let enabled = AppFeature.trackpadEdges.isAvailable
            && defaults.bool(forKey: DefaultsKey.trackpadEdgesEnabled)
        let loaded = TrackpadEdgeConfiguration.load(from: defaults)
        configuration = loaded
        hapticsEnabled = defaults.bool(forKey: DefaultsKey.trackpadEdgeHaptics)
        let wantsModifier = TrackpadEdgeModifier.sanitized(defaults.string(forKey: DefaultsKey.trackpadEdgeModifier))
        let freezes = defaults.bool(forKey: DefaultsKey.trackpadEdgeFreezeCursor)
        stateLock.withLock {
            recognizer.configuration = loaded
            modifier = wantsModifier
            freezeCursor = freezes
            updatePointerDetachmentLocked()
        }
        if SessionActivitySupport.tapShouldRun(
            featureWanted: enabled && loaded.hasAnyGesture,
            accessibilityGranted: AXIsProcessTrusted(),
            sessionIsActive: SessionActivity.shared.isActive
        ) {
            start()
        } else {
            stop()
        }
    }

    func suspend() { stop() }

    private func start() {
        guard tapLock.withLock({ tap }) == nil else { return }
        guard TrackpadMultitouch.available else {
            touchDeviceMissing = true
            return
        }
        let mask = CGEventMask(1 << CGEventType.mouseMoved.rawValue)
            | CGEventMask(1 << CGEventType.leftMouseDown.rawValue)
            | CGEventMask(1 << CGEventType.leftMouseUp.rawValue)
            | CGEventMask(1 << CGEventType.leftMouseDragged.rawValue)
        guard let created = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: { _, type, event, userInfo in
                guard let userInfo else { return Unmanaged.passUnretained(event) }
                let service = Unmanaged<TrackpadEdgeService>.fromOpaque(userInfo).takeUnretainedValue()
                return service.handle(type: type, event: event)
            },
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else { return }
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, created, 0)
        tapLock.withLock {
            tap = created
            runLoopSource = source
        }
        if let source {
            PointerTapRunLoop.add(source)
        }
        CGEvent.tapEnable(tap: created, enable: true)
        startMultitouch()
        installObservers()
        isRunning = true
    }

    private func stop() {
        let (port, source) = tapLock.withLock { () -> (CFMachPort?, CFRunLoopSource?) in
            let current = (tap, runLoopSource)
            tap = nil
            runLoopSource = nil
            return current
        }
        if let port {
            CGEvent.tapEnable(tap: port, enable: false)
        }
        if let source {
            PointerTapRunLoop.remove(source, invalidating: port)
        }
        stopMultitouch()
        removeObservers()
        stateLock.withLock {
            recognizer.reset()
            cursorAnchor = nil
            swallowingButton = false
            heldClick = nil
            activeDevice = nil
            updatePointerDetachmentLocked()
        }
        level = nil
        levelGeneration &+= 1
        flashWork?.cancel()
        flashWork = nil
        if activeEdge != nil { activeEdge = nil }
        if flashedTarget != nil { flashedTarget = nil }
        if isRunning { isRunning = false }
        if touchDeviceMissing { touchDeviceMissing = false }
    }

    private func restartMultitouch() {
        guard tapLock.withLock({ tap }) != nil else { return }
        stopMultitouch()
        startMultitouch()
    }

    private func startMultitouch() {
        guard deviceList == nil else { return }
        guard let list = TrackpadMultitouch.deviceList() else {
            touchDeviceMissing = true
            return
        }
        var started = false
        for index in 0..<CFArrayGetCount(list) {
            guard let raw = CFArrayGetValueAtIndex(list, index) else { continue }
            let device = UnsafeMutableRawPointer(mutating: raw)
            guard TrackpadMultitouch.isTrackpad(device) else { continue }
            TrackpadMultitouch.register(device, trackpadEdgeContactCallback)
            TrackpadMultitouch.start(device)
            started = true
        }
        deviceList = list
        touchDeviceMissing = !started
    }

    private func stopMultitouch() {
        guard let list = deviceList else { return }
        for index in 0..<CFArrayGetCount(list) {
            guard let raw = CFArrayGetValueAtIndex(list, index) else { continue }
            let device = UnsafeMutableRawPointer(mutating: raw)
            guard TrackpadMultitouch.isTrackpad(device) else { continue }
            TrackpadMultitouch.unregister(device, trackpadEdgeContactCallback)
            TrackpadMultitouch.stop(device)
        }
        deviceList = nil
        stateLock.withLock {
            recognizer.reset()
            activeDevice = nil
            updatePointerDetachmentLocked()
        }
    }

    private func installObservers() {
        guard observers.isEmpty else { return }
        let center = NSWorkspace.shared.notificationCenter
        observers.append(center.addObserver(forName: NSWorkspace.didWakeNotification,
                                            object: nil,
                                            queue: .main) { [weak self] _ in
            self?.restartMultitouch()
        })
        installHotplugObserver()
    }

    private func installHotplugObserver() {
        guard hotplugPort == nil else { return }
        guard let port = IONotificationPortCreate(kIOMainPortDefault) else { return }
        IONotificationPortSetDispatchQueue(port, DispatchQueue.main)
        let context = Unmanaged.passUnretained(self).toOpaque()
        var iterators: [io_iterator_t] = []
        for notification in [kIOFirstMatchNotification, kIOTerminatedNotification] {
            var iterator: io_iterator_t = 0
            let result = IOServiceAddMatchingNotification(
                port,
                notification,
                IOServiceMatching("AppleMultitouchDevice"),
                { context, iterator in
                    guard let context else { return }
                    while case let entry = IOIteratorNext(iterator), entry != 0 {
                        IOObjectRelease(entry)
                    }
                    let service = Unmanaged<TrackpadEdgeService>.fromOpaque(context).takeUnretainedValue()
                    service.restartMultitouch()
                },
                context,
                &iterator
            )
            guard result == KERN_SUCCESS else {
                if iterator != 0 { IOObjectRelease(iterator) }
                for registered in iterators { IOObjectRelease(registered) }
                IONotificationPortDestroy(port)
                return
            }
            while case let entry = IOIteratorNext(iterator), entry != 0 {
                IOObjectRelease(entry)
            }
            iterators.append(iterator)
        }
        hotplugPort = port
        hotplugIterators = iterators
    }

    private func removeObservers() {
        let center = NSWorkspace.shared.notificationCenter
        for observer in observers {
            center.removeObserver(observer)
        }
        observers = []
        for iterator in hotplugIterators { IOObjectRelease(iterator) }
        hotplugIterators.removeAll()
        if let hotplugPort {
            IONotificationPortDestroy(hotplugPort)
            self.hotplugPort = nil
        }
    }

    fileprivate func contactFrame(device: UnsafeMutableRawPointer?,
                                  touches: UnsafeMutableRawPointer?,
                                  count: Int) {
        guard let contacts = TrackpadMultitouch.contacts(touches: touches, count: count) else {
            stateLock.withLock {
                recognizer.reset()
                activeDevice = nil
                updatePointerDetachmentLocked()
            }
            return
        }
        let now = ProcessInfo.processInfo.systemUptime
        stateLock.lock()
        if recognizer.phase != .idle, let activeDevice, activeDevice != device {
            stateLock.unlock()
            return
        }
        if recognizer.phase == .idle {
            activeDevice = contacts.isEmpty ? nil : device
        }
        let required = modifier
        let events = recognizer.process(contacts, at: now) {
            let flags = CGEventSource.flagsState(.combinedSessionState)
            guard required.isSatisfied(by: flags),
                  !CGEventSource.buttonState(.combinedSessionState, button: .left) else { return false }
            cursorAnchor = CGEvent(source: nil)?.location
            return true
        }
        if events.contains(where: \.beginsSlide) {
            heldClick = nil
        }
        updatePointerDetachmentLocked()
        if recognizer.phase == .idle {
            activeDevice = nil
            cursorAnchor = nil
        }
        stateLock.unlock()
        guard !events.isEmpty else { return }
        DispatchQueue.main.async { [weak self] in
            self?.handle(events)
        }
    }

    private func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if SessionActivity.shared.isActive, AXIsProcessTrusted(), let tap = tapLock.withLock({ tap }) {
                CGEvent.tapEnable(tap: tap, enable: true)
            }
            return Unmanaged.passUnretained(event)
        }
        if event.getIntegerValueField(.eventSourceUserData) == Self.replayedClickMarker {
            return Unmanaged.passUnretained(event)
        }
        let now = ProcessInfo.processInfo.systemUptime
        stateLock.lock()
        defer { stateLock.unlock() }
        switch type {
        case .mouseMoved:
            return holdPointerLocked() ? nil : Unmanaged.passUnretained(event)
        case .leftMouseDragged:
            if swallowingButton { return nil }
            return holdPointerLocked() ? nil : Unmanaged.passUnretained(event)
        case .leftMouseDown:
            if recognizer.isSliding {
                swallowingButton = true
                return nil
            }
            switch recognizer.tapClickRole(at: now) {
            case .none:
                swallowingButton = false
                return Unmanaged.passUnretained(event)
            case .secondTap:
                swallowingButton = true
                return nil
            case .firstTap(let generation):
                swallowingButton = true
                if heldClick?.generation != generation {
                    heldClick = HeldClick(generation: generation, location: event.location, released: false)
                }
                return nil
            }
        case .leftMouseUp:
            guard swallowingButton else { return Unmanaged.passUnretained(event) }
            swallowingButton = false
            heldClick?.released = true
            return nil
        default:
            return Unmanaged.passUnretained(event)
        }
    }

    private func holdPointerLocked() -> Bool {
        guard freezeCursor, recognizer.isSliding, let anchor = cursorAnchor else { return false }
        CGWarpMouseCursorPosition(anchor)
        CGAssociateMouseAndMouseCursorPosition(pointerDetached ? 0 : 1)
        return true
    }

    private func updatePointerDetachmentLocked() {
        let detach = freezeCursor && recognizer.isSliding && cursorAnchor != nil
        guard detach != pointerDetached else { return }
        pointerDetached = detach
        if detach, let anchor = cursorAnchor {
            CGWarpMouseCursorPosition(anchor)
        }
        CGAssociateMouseAndMouseCursorPosition(detach ? 0 : 1)
    }

    private func handle(_ events: [TrackpadEdgeEvent]) {
        guard isRunning else { return }
        for event in events {
            switch event {
            case .slideBegan(let edge, let action):
                activeEdge = edge
                beginLevel(for: action)
            case .step(let action, let direction):
                step(action, direction: direction)
            case .slideEnded:
                activeEdge = nil
                level = nil
                levelGeneration &+= 1
            case .trackSkip(let direction):
                post(direction > 0 ? .nextTrack : .previousTrack)
                haptic(.action)
            case .firstTap(_, let generation):
                scheduleClickReplay(generation, after: TrackpadEdgeRecognizer.doubleTapGap + 0.02)
            case .doubleTap(let target, let generation):
                stateLock.withLock {
                    if heldClick?.generation == generation { heldClick = nil }
                }
                perform(target)
                flash(target)
            }
        }
    }

    private func beginLevel(for action: TrackpadSlideAction) {
        level = nil
        atBound = false
        mutedNoticeShown = false
        levelGeneration &+= 1
        let generation = levelGeneration
        switch action {
        case .volume:
            if AppFeature.mixer.isAvailable, let current = AppVolumeMixer.shared.systemOutputVolume {
                level = AppVolumeMixer.shared.systemOutputMuted == true ? 0 : current
                return
            }
            levelQueue.async { [weak self] in
                let muted = AppVolumeMixer.systemOutputIsMuted() == true
                let read = AppVolumeMixer.systemOutputLevel().map { muted ? 0 : $0 }
                DispatchQueue.main.async { self?.adoptLevel(read, generation: generation) }
            }
        case .brightness:
            levelQueue.async { [weak self] in
                let read = TrackpadEdgeService.builtInBrightness()
                DispatchQueue.main.async { self?.adoptLevel(read, generation: generation) }
            }
        case .microphoneVolume:
            level = AppFeature.mixer.isAvailable ? AudioInputDeviceManager.shared.inputVolume : nil
        case .keyboardBrightness:
            if AppFeature.brightness.isAvailable, BrightnessService.keyboardLightIsSupported,
               let current = BrightnessService.shared.keyboardLightLevel {
                level = Double(current)
            }
        case .off, .tracks:
            break
        }
    }

    private func adoptLevel(_ read: Double?, generation: Int) {
        guard generation == levelGeneration, level == nil, let read, read.isFinite else { return }
        level = min(max(read, 0), 1)
    }

    private func step(_ action: TrackpadSlideAction, direction: Int) {
        guard action.isStepped else { return }
        let before = level
        let after = before.map {
            TrackpadEdgeLevel.stepped($0, direction: direction, stepSize: configuration.stepSize)
        }
        if let before, let after, before == after {
            if !atBound {
                atBound = true
                haptic(.limit)
            }
        } else {
            atBound = false
            haptic(.tick)
        }
        level = after
        let fine = configuration.precise
        switch action {
        case .volume:
            stepVolume(direction: direction, fine: fine)
        case .brightness:
            post(direction > 0 ? .brightnessUp : .brightnessDown, fine: fine)
        case .keyboardBrightness:
            post(direction > 0 ? .illuminationUp : .illuminationDown, fine: fine)
        case .microphoneVolume:
            stepMicrophone(to: after)
        case .off, .tracks:
            break
        }
    }

    private func stepVolume(direction: Int, fine: Bool) {
        let islandShowsVolume = NotchSupport.routes(.volume)
            && NotchService.shared.acceptsSystemFeedback
            && AppVolumeMixer.shared.systemOutputVolume != nil
        guard islandShowsVolume else {
            postSystemVolume(direction: direction, fine: fine)
            return
        }
        AppVolumeMixer.shared.requestOutputStep(level: {
            NotchSupport.volumeLevel(current: $0, direction: direction, fine: fine)
        }, completion: { [weak self] result in
            switch result {
            case .applied: NotchService.shared.showCurrentVolume()
            case .fallback: self?.postSystemVolume(direction: direction, fine: fine)
            case .superseded, .unconfirmed: break
            }
        })
    }

    private func postSystemVolume(direction: Int, fine: Bool) {
        let key: TrackpadMediaKey = direction > 0 ? .volumeUp : .volumeDown
        for event in key.events(fine: fine, marker: PreciseVolumeKeyEvents.postedMarker) {
            event.post(tap: .cghidEventTap)
        }
    }

    private func stepMicrophone(to target: Double?) {
        guard AppFeature.mixer.isAvailable else { return }
        if AppFeature.micMute.isAvailable, MicMuteService.shared.isMuted {
            guard !mutedNoticeShown else { return }
            mutedNoticeShown = true
            QuickToolHUD.show(icon: "mic.slash.fill", message: strings.microphoneMutedNotice)
            return
        }
        let manager = AudioInputDeviceManager.shared
        guard let target = target ?? manager.inputVolume else { return }
        manager.setInputVolume(target)
        QuickToolHUD.show(icon: target > 0 ? "mic.fill" : "mic.slash", message: strings.microphoneLevel(target))
    }

    private func perform(_ target: TrackpadTapTarget) {
        let action: TrackpadCornerAction
        switch target {
        case .mediaStrip: action = .playPause
        case .corner(let corner): action = configuration.cornerAction(corner)
        }
        guard action != .off else { return }
        if let feature = action.requiredFeature, !feature.isAvailable { return }
        haptic(action.isMute ? .mute : .action)
        switch action {
        case .off:
            break
        case .microphoneMute:
            MicMuteService.shared.toggle()
        case .outputMute:
            post(.mute)
        case .playPause:
            post(.playPause)
        case .nextTrack:
            post(.nextTrack)
        case .previousTrack:
            post(.previousTrack)
        case .missionControl:
            if let shortcut = SpaceWindowBridge.overviewShortcut(.missionControl) {
                SpaceWindowBridge.pressSpaceShortcut(shortcut)
            }
        case .appExpose:
            if let shortcut = SpaceWindowBridge.overviewShortcut(.appExpose) {
                SpaceWindowBridge.pressSpaceShortcut(shortcut)
            }
        case .nextSoundOutput:
            _ = SoundOutputSwitcher.shared.switchToNextOutput()
        case .lockScreen:
            QuickTogglesService.shared.lockScreen()
        case .closeWindow, .minimizeWindow, .fillScreen, .fullScreen, .hideApp, .quitApp:
            TrackpadWindowActions.shared.perform(action)
        }
    }

    private func post(_ key: TrackpadMediaKey, fine: Bool = false) {
        for event in key.events(fine: fine) {
            event.post(tap: .cghidEventTap)
        }
    }

    private func flash(_ target: TrackpadTapTarget) {
        flashWork?.cancel()
        flashedTarget = target
        let work = DispatchWorkItem { [weak self] in
            self?.flashedTarget = nil
            self?.flashWork = nil
        }
        flashWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6, execute: work)
    }

    private func haptic(_ kind: Haptic) {
        guard hapticsEnabled else { return }
        let performer = NSHapticFeedbackManager.defaultPerformer
        switch kind {
        case .tick:
            performer.perform(.alignment, performanceTime: .now)
        case .limit, .action:
            performer.perform(.levelChange, performanceTime: .now)
        case .mute:
            performer.perform(.levelChange, performanceTime: .now)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
                performer.perform(.levelChange, performanceTime: .now)
            }
        }
    }

    private func scheduleClickReplay(_ generation: Int, after delay: TimeInterval) {
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self else { return }
            let decision = self.stateLock.withLock { () -> (click: HeldClick?, retry: Bool) in
                if self.recognizer.isAwaitingSecondTap(generation: generation) { return (nil, true) }
                guard let held = self.heldClick, held.generation == generation else { return (nil, false) }
                if !held.released, self.swallowingButton { return (nil, true) }
                self.heldClick = nil
                return (held, false)
            }
            if decision.retry {
                self.scheduleClickReplay(generation, after: 0.05)
                return
            }
            guard let click = decision.click, self.isRunning else { return }
            Self.replayClick(at: click.location)
        }
    }

    private static func replayClick(at location: CGPoint) {
        let source = CGEventSource(stateID: .hidSystemState)
        guard let down = CGEvent(mouseEventSource: source, mouseType: .leftMouseDown,
                                 mouseCursorPosition: location, mouseButton: .left),
              let up = CGEvent(mouseEventSource: source, mouseType: .leftMouseUp,
                               mouseCursorPosition: location, mouseButton: .left)
        else { return }
        for event in [down, up] {
            event.setIntegerValueField(.eventSourceUserData, value: replayedClickMarker)
            event.setIntegerValueField(.mouseEventClickState, value: 1)
            event.post(tap: .cgSessionEventTap)
        }
    }

    private static func builtInBrightness() -> Double? {
        guard let read = BrightnessBridge.getBrightness else { return nil }
        var count: UInt32 = 0
        guard CGGetOnlineDisplayList(0, nil, &count) == .success, count > 0 else { return nil }
        var displays = [CGDirectDisplayID](repeating: 0, count: Int(count))
        guard CGGetOnlineDisplayList(count, &displays, &count) == .success else { return nil }
        guard let builtIn = displays.prefix(Int(count)).first(where: { CGDisplayIsBuiltin($0) != 0 }),
              CGDisplayIsAsleep(builtIn) == 0 else { return nil }
        var value: Float = -1
        guard read(builtIn, &value) == 0, value >= 0, value <= 1 else { return nil }
        return Double(value)
    }
}

private func trackpadEdgeContactCallback(_ device: UnsafeMutableRawPointer?,
                                         _ touches: UnsafeMutableRawPointer?,
                                         _ count: Int32,
                                         _ timestamp: Double,
                                         _ frame: Int32) -> Int32 {
    TrackpadEdgeService.shared.contactFrame(device: device, touches: touches, count: Int(count))
    return 0
}

private enum TrackpadMultitouch {
    typealias ContactCallback = @convention(c) (
        UnsafeMutableRawPointer?, UnsafeMutableRawPointer?, Int32, Double, Int32
    ) -> Int32
    private typealias CreateListFn = @convention(c) () -> Unmanaged<CFArray>?
    private typealias RegisterFn = @convention(c) (UnsafeMutableRawPointer, ContactCallback?) -> Void
    private typealias StartFn = @convention(c) (UnsafeMutableRawPointer, Int32) -> Void
    private typealias StopFn = @convention(c) (UnsafeMutableRawPointer) -> Void
    private typealias FamilyFn = @convention(c) (UnsafeMutableRawPointer, UnsafeMutablePointer<Int32>) -> Int32

    private static let handle: UnsafeMutableRawPointer? = dlopen(
        "/System/Library/PrivateFrameworks/MultitouchSupport.framework/MultitouchSupport",
        RTLD_NOW
    )

    private static let createListFn: CreateListFn? = symbol("MTDeviceCreateList")
    private static let registerFn: RegisterFn? = symbol("MTRegisterContactFrameCallback")
    private static let unregisterFn: RegisterFn? = symbol("MTUnregisterContactFrameCallback")
    private static let startFn: StartFn? = symbol("MTDeviceStart")
    private static let stopFn: StopFn? = symbol("MTDeviceStop")
    private static let familyFn: FamilyFn? = symbol("MTDeviceGetFamilyID")

    private static let magicMouseFamilies: Set<Int32> = [112, 113]
    private static let touchStride = 96
    private static let identifierOffset = 16
    private static let stateOffset = 20
    private static let positionXOffset = 32
    private static let positionYOffset = 36
    private static let contactStates: ClosedRange<Int32> = 3...4

    static var available: Bool {
        createListFn != nil && registerFn != nil && unregisterFn != nil && startFn != nil && stopFn != nil
    }

    static func deviceList() -> CFArray? {
        guard let createListFn else { return nil }
        let list = createListFn()?.takeRetainedValue()
        guard let list, CFArrayGetCount(list) > 0 else { return nil }
        return list
    }

    static func isTrackpad(_ device: UnsafeMutableRawPointer) -> Bool {
        guard let familyFn else { return true }
        var family: Int32 = 0
        guard familyFn(device, &family) == 0 else { return true }
        return !magicMouseFamilies.contains(family)
    }

    static func register(_ device: UnsafeMutableRawPointer, _ callback: ContactCallback) {
        registerFn?(device, callback)
    }

    static func unregister(_ device: UnsafeMutableRawPointer, _ callback: ContactCallback) {
        unregisterFn?(device, callback)
    }

    static func start(_ device: UnsafeMutableRawPointer) {
        startFn?(device, 0)
    }

    static func stop(_ device: UnsafeMutableRawPointer) {
        stopFn?(device)
    }

    static func contacts(touches: UnsafeMutableRawPointer?, count: Int) -> [TrackpadContact]? {
        guard count > 0 else { return [] }
        guard let touches, count <= 20 else { return nil }
        var contacts: [TrackpadContact] = []
        contacts.reserveCapacity(count)
        for index in 0..<count {
            let base = touches.advanced(by: index * touchStride)
            let state = base.loadUnaligned(fromByteOffset: stateOffset, as: Int32.self)
            guard (0...7).contains(state) else { return nil }
            guard contactStates.contains(state) else { continue }
            let x = base.loadUnaligned(fromByteOffset: positionXOffset, as: Float.self)
            let y = base.loadUnaligned(fromByteOffset: positionYOffset, as: Float.self)
            guard x.isFinite, y.isFinite, x >= -0.2, x <= 1.2, y >= -0.2, y <= 1.2 else { return nil }
            let identifier = base.loadUnaligned(fromByteOffset: identifierOffset, as: Int32.self)
            contacts.append(TrackpadContact(id: identifier, x: min(max(x, 0), 1), y: min(max(y, 0), 1)))
        }
        return contacts
    }

    private static func symbol<T>(_ name: String) -> T? {
        guard let handle, let raw = dlsym(handle, name) else { return nil }
        return unsafeBitCast(raw, to: T.self)
    }
}
