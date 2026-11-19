// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import ApplicationServices
import Combine

/// Main-run-loop input taps. Keyboard matching reads live system bindings;
/// only matching shortcuts and horizontal DockSwipes query Space topology.
final class InstantSpacesService: ObservableObject {
    static let shared = InstantSpacesService()

    @Published private(set) var isRunning = false

    private struct Tap {
        let port: CFMachPort
        let source: CFRunLoopSource
    }

    private var keyboardTap: Tap?
    private var swipeTap: Tap?
    private var envelopeTap: Tap?
    private var wakeObserver: NSObjectProtocol?
    private var sleepObserver: NSObjectProtocol?
    private var claimedKeys: Set<Int64> = []
    private var swipe: InstantSpacesSupport.Swipe?
    private var pendingEvents: [CGEvent] = []
    private var swipeCommitted = false
    private var replacementEvent: CGEvent?
    private var travel: DispatchWorkItem?
    private var travelGeneration = 0

    private init() {
        SessionActivity.shared.onChange { [weak self] _ in self?.syncWithPreferences() }
        sleepObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.willSleepNotification, object: nil, queue: .main
        ) { [weak self] _ in self?.suspend() }
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            // Sleep can invalidate a Mach port without delivering a timeout.
            self?.suspend()
            self?.syncWithPreferences()
        }
    }

    private var keyboardEnabled: Bool {
        UserDefaults.standard.bool(forKey: DefaultsKey.instantSpacesKeyboard)
    }

    private var swipeEnabled: Bool {
        UserDefaults.standard.bool(forKey: DefaultsKey.instantSpacesTrackpad)
    }

    private var canRun: Bool {
        SessionActivitySupport.tapShouldRun(
            featureWanted: AppFeature.instantSpaces.isAvailable
                && (keyboardEnabled || swipeEnabled) && InstantSpacesGesture.isSupported,
            accessibilityGranted: AXIsProcessTrusted(),
            sessionIsActive: SessionActivity.shared.isActive)
    }

    func syncWithPreferences() {
        guard canRun else { suspend(); return }
        if !keyboardEnabled {
            removeTap(&keyboardTap)
            claimedKeys.removeAll()
            cancelTravel()
        } else if keyboardTap == nil {
            keyboardTap = makeTap(types: [10, 11])
        }
        if !swipeEnabled {
            resetSwipe()
            removeTap(&swipeTap)
            removeTap(&envelopeTap)
        } else if swipeTap == nil {
            swipeTap = makeTap(types: [30])
            envelopeTap = makeTap(types: [29])
            if envelopeTap == nil { removeTap(&swipeTap) }
            if swipeTap == nil { removeTap(&envelopeTap) }
            setEnvelopeEnabled(false)
        }
        isRunning = (!keyboardEnabled || keyboardTap != nil) && (!swipeEnabled || swipeTap != nil)
    }

    func suspend() {
        cancelTravel()
        resetSwipe()
        removeTap(&keyboardTap)
        removeTap(&swipeTap)
        removeTap(&envelopeTap)
        claimedKeys.removeAll()
        isRunning = false
    }

    private func makeTap(types: [UInt32]) -> Tap? {
        let mask = types.reduce(CGEventMask(0)) { $0 | (CGEventMask(1) << $1) }
        guard let port = CGEvent.tapCreate(
            tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap,
            eventsOfInterest: mask,
            callback: { proxy, type, event, context in
                guard let context else { return Unmanaged.passUnretained(event) }
                return Unmanaged<InstantSpacesService>.fromOpaque(context).takeUnretainedValue()
                    .handle(proxy: proxy, type: type, event: event)
            }, userInfo: Unmanaged.passUnretained(self).toOpaque()),
              let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, port, 0)
        else { return nil }
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: port, enable: true)
        return Tap(port: port, source: source)
    }

    private func removeTap(_ tap: inout Tap?) {
        guard let value = tap else { return }
        CGEvent.tapEnable(tap: value.port, enable: false)
        CFRunLoopRemoveSource(CFRunLoopGetMain(), value.source, .commonModes)
        CFMachPortInvalidate(value.port)
        tap = nil
    }

    private func setEnvelopeEnabled(_ enabled: Bool) {
        guard let envelopeTap, CGEvent.tapIsEnabled(tap: envelopeTap.port) != enabled else { return }
        CGEvent.tapEnable(tap: envelopeTap.port, enable: enabled)
    }

    private func handle(proxy: CGEventTapProxy, type: CGEventType,
                        event: CGEvent) -> Unmanaged<CGEvent>? {
        let pass = Unmanaged.passUnretained(event)
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            // Disabling the on-demand envelope tap also delivers this notice.
            // Recheck the live ports after the callback: rebuilding healthy
            // taps here would turn each intentional disable into a restart loop.
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                guard self.canRun else { self.suspend(); return }
                let required = [self.keyboardTap, self.swipeTap,
                                self.swipe == nil ? nil : self.envelopeTap].compactMap { $0 }
                guard required.contains(where: {
                    !CFMachPortIsValid($0.port) || !CGEvent.tapIsEnabled(tap: $0.port)
                }) else { return }
                self.suspend()
                self.syncWithPreferences()
            }
            return pass
        }
        guard event.getIntegerValueField(.eventSourceUserData) != InstantSpacesGesture.marker else {
            return pass
        }
        if type == .keyUp {
            return claimedKeys.remove(event.getIntegerValueField(.keyboardEventKeycode)) != nil ? nil : pass
        }
        if type == .keyDown {
            let key = event.getIntegerValueField(.keyboardEventKeycode)
            if claimedKeys.contains(key), travel != nil { return nil }
            // System Settings can remap or disable a binding while it stays
            // foreground. Read the known IDs before deciding to intercept.
            guard keyboardEnabled, canRun, !ShortcutCapture.isCapturing,
                  let shortcuts = SymbolicHotKeys.entries(for: InstantSpacesSupport.shortcutIDs),
                  let action = InstantSpacesSupport.action(keyCode: key, flags: event.flags,
                                                           shortcuts: shortcuts),
                  !CGEventSource.buttonState(.combinedSessionState, button: .left),
                  overviewIsActive() == false,
                  perform(action) else { return claimedKeys.contains(key) ? nil : pass }
            claimedKeys.insert(key)
            return nil
        }
        return handleSwipe(proxy: proxy, type: type, event: event)
    }

    private func pointerDisplay(_ topology: SpaceWindowBridge.Topology)
        -> SpaceWindowBridge.Topology.DisplayInfo? {
        guard let point = CGEvent(source: nil)?.location else { return nil }
        if let display = topology.displays.first(where: {
            $0.displayID.map { CGDisplayBounds($0).contains(point) } ?? false
        }) { return display }
        // With shared Spaces, WindowServer may expose one logical display
        // without a physical UUID. Never guess between several displays.
        return topology.displays.count == 1 ? topology.displays.first : nil
    }

    private func perform(_ action: InstantSpacesSupport.Action) -> Bool {
        guard let topology = SpaceWindowBridge.topology(),
              let display = pointerDisplay(topology), let current = display.currentSpace,
              let currentIndex = display.spaces.firstIndex(of: current) else { return false }
        let target: UInt64
        switch action {
        case .step(let direction):
            guard let destination = InstantSpacesSupport.destination(
                in: display.spaces, current: current, direction: direction) else {
                cancelTravel()
                return true
            }
            target = destination
        case .desktop(let index):
            let rows = topology.displays.compactMap(\.desktopSpaces)
            guard rows.count == topology.displays.count else { return false }
            let desktops = rows.flatMap { $0 }
            // Keep native handling for a target on another display. Moving
            // the pointer to steer the Dock would interfere with user input.
            guard desktops.indices.contains(index), display.spaces.contains(desktops[index]) else { return false }
            target = desktops[index]
        }
        cancelTravel()
        guard target != current else { return true }
        guard let targetIndex = display.spaces.firstIndex(of: target),
              post(direction: targetIndex > currentIndex ? 1 : -1) else { return false }
        waitForArrival(target: target, previous: current, generation: travelGeneration,
                       deadline: .now() + 1.2, remaining: display.spaces.count)
        return true
    }

    private func waitForArrival(target: UInt64, previous: UInt64, generation: Int,
                                deadline: DispatchTime, remaining: Int) {
        let work = DispatchWorkItem { [weak self] in
            guard let self, self.travelGeneration == generation else { return }
            self.travel = nil
            guard self.canRun, self.keyboardEnabled, !ShortcutCapture.isCapturing, remaining > 0,
                  !CGEventSource.buttonState(.combinedSessionState, button: .left),
                  self.overviewIsActive() == false,
                  let topology = SpaceWindowBridge.topology(),
                  let display = self.pointerDisplay(topology), let current = display.currentSpace,
                  let from = display.spaces.firstIndex(of: current),
                  let to = display.spaces.firstIndex(of: target), current != target else { return }
            if current == previous {
                guard DispatchTime.now() < deadline else { return }
                self.waitForArrival(target: target, previous: previous, generation: generation,
                                    deadline: deadline, remaining: remaining)
            } else if self.post(direction: to > from ? 1 : -1) {
                self.waitForArrival(target: target, previous: current, generation: generation,
                                    deadline: .now() + 1.2, remaining: remaining - 1)
            }
        }
        travel = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.025, execute: work)
    }

    private func cancelTravel() {
        travelGeneration += 1
        travel?.cancel()
        travel = nil
    }

    private func post(direction: Int) -> Bool {
        guard let events = InstantSpacesGesture.events(direction: direction) else { return false }
        for event in events { event.post(tap: .cgSessionEventTap) }
        return true
    }

    private func handleSwipe(proxy: CGEventTapProxy, type: CGEventType,
                             event: CGEvent) -> Unmanaged<CGEvent>? {
        let pass = Unmanaged.passUnretained(event)
        if type.rawValue == 29, swipe != nil {
            if !swipeCommitted { return hold(event, proxy: proxy) ? nil : pass }
            return nil
        }
        guard type.rawValue == 30,
              event.getIntegerValueField(CGEventField(rawValue: 110)!) == 23,
              event.getIntegerValueField(CGEventField(rawValue: 123)!) == 1 else { return pass }
        let phase = event.getIntegerValueField(CGEventField(rawValue: 132)!)
        if phase == 1 {
            guard swipeEnabled, canRun, overviewIsActive() == false,
                  let topology = SpaceWindowBridge.topology(),
                  let display = pointerDisplay(topology), let current = display.currentSpace,
                  display.spaces.contains(current),
                  InstantSpacesGesture.events(direction: -1) != nil,
                  InstantSpacesGesture.events(direction: 1) != nil else { return pass }
            cancelTravel()
            resetSwipe()
            swipe = InstantSpacesSupport.Swipe()
            setEnvelopeEnabled(true)
            return hold(event, proxy: proxy) ? nil : pass
        }
        guard swipe != nil else { return pass }
        var direction: Int?
        if phase == 2 {
            direction = swipe?.update(progress: event.getDoubleValueField(CGEventField(rawValue: 124)!))
        } else if phase == 4 {
            direction = swipe?.finish(velocity: event.getDoubleValueField(CGEventField(rawValue: 129)!))
        }
        if let direction {
            if perform(.step(direction)) {
                swipeCommitted = true
                pendingEvents.removeAll(keepingCapacity: true)
            } else if !swipeCommitted {
                replay(proxy: proxy)
                resetSwipe()
                return pass
            }
        }
        if phase == 4 || phase == 8 {
            let committed = swipeCommitted
            if !committed { replay(proxy: proxy) }
            resetSwipe()
            guard committed else { return pass }
            if InstantSpacesGesture.augmented {
                // Close the physical stream without another movement; both
                // the CG fields and the mirrored HID payload must agree.
                replacementEvent = InstantSpacesGesture.cleanup(event)
                if let replacementEvent { return Unmanaged.passUnretained(replacementEvent) }
                event.setDoubleValueField(CGEventField(rawValue: 124)!, value: 0)
                event.setDoubleValueField(CGEventField(rawValue: 129)!, value: 0)
                event.setDoubleValueField(CGEventField(rawValue: 130)!, value: 0)
                return pass
            }
            return nil
        }
        return swipeCommitted || hold(event, proxy: proxy) ? nil : pass
    }

    private func hold(_ event: CGEvent, proxy: CGEventTapProxy) -> Bool {
        guard pendingEvents.count < 128, let copy = event.copy() else {
            replay(proxy: proxy)
            resetSwipe()
            return false
        }
        pendingEvents.append(copy)
        return true
    }

    private func replay(proxy: CGEventTapProxy) {
        for event in pendingEvents {
            event.setIntegerValueField(.eventSourceUserData, value: InstantSpacesGesture.marker)
            event.tapPostEvent(proxy)
        }
    }

    private func resetSwipe() {
        swipe = nil
        swipeCommitted = false
        pendingEvents.removeAll(keepingCapacity: true)
        setEnvelopeEnabled(false)
    }

    /// Window names require Screen Recording; owner, layer and bounds do not.
    /// An unreadable overview state leaves the native input path intact.
    private func overviewIsActive() -> Bool? {
        guard let windows = CGWindowListCopyWindowInfo(.optionOnScreenOnly, kCGNullWindowID)
            as? [[String: Any]] else { return nil }
        let modern = InstantSpacesGesture.augmented
        return windows.contains { window in
            guard let owner = window[kCGWindowOwnerName as String] as? String,
                  let layer = window[kCGWindowLayer as String] as? Int else { return false }
            if !modern { return owner == "Dock" && layer == 18 }
            guard owner == "WindowManager", layer == 18 || layer == 19,
                  let rawBounds = window[kCGWindowBounds as String] as? [String: Any],
                  let bounds = CGRect(dictionaryRepresentation: rawBounds as CFDictionary) else { return false }
            return NSScreen.screens.contains {
                abs($0.frame.width - bounds.width) <= 1 && abs($0.frame.height - bounds.height) <= 1
            }
        }
    }
}
