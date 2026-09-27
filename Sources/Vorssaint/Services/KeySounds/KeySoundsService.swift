// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import ApplicationServices
import Carbon.HIToolbox
import Combine
import CoreGraphics
import Foundation

/// Mechanical keyboard sounds: a listen-only key tap picks the
/// sound family from the key, and the built-in accelerometer picks how hard
/// the switch "bottomed out". Events are only observed, never changed.
final class KeySoundsService: ObservableObject {
    static let shared = KeySoundsService()

    @Published private(set) var isRunning = false
    @Published private(set) var sensorState: KeyVelocitySensor.State = .off
    @Published private(set) var packs: [KeySoundPackInfo] = []
    @Published private(set) var lastStrength: KeySoundStrength?
    @Published private(set) var shortcutRegistrationFailed = false

    private let engine = KeySoundEngine()
    private let sensor = KeyVelocitySensor()
    private var classifier = KeyVelocityClassifier()   // engine.queue only

    private let lock = NSLock()
    private var tap: CFMachPort?
    private var tapRunLoop: CFRunLoop?
    private var tapThread: Thread?
    private var settings = Settings()
    private var lastPress: (code: Int64, at: UInt64) = (-1, 0)

    private var hotKeyRef: EventHotKeyRef?
    private var hotKeyHandler: EventHandlerRef?
    private var registeredShortcut: GlobalShortcut?

    private struct Settings {
        var velocity = true
        var sensitivity = 1.0
        var release = true
        var muteModifiers = false
    }

    private init() {
        packs = KeySoundPackCatalog.available()
        SessionActivity.shared.onChange { [weak self] _ in self?.syncWithPreferences() }
    }

    // MARK: Preferences

    var isEnabled: Bool {
        AppFeature.keySounds.isAvailable && UserDefaults.standard.bool(forKey: DefaultsKey.keySoundsEnabled)
    }

    func syncWithPreferences() {
        let defaults = UserDefaults.standard
        let available = AppFeature.keySounds.isAvailable
        syncShortcut(available: available)

        let wanted = available && defaults.bool(forKey: DefaultsKey.keySoundsEnabled)
        let shouldRun = SessionActivitySupport.tapShouldRun(featureWanted: wanted,
                                                            accessibilityGranted: AXIsProcessTrusted(),
                                                            sessionIsActive: SessionActivity.shared.isActive)
        let next = Settings(
            velocity: defaults.bool(forKey: DefaultsKey.keySoundsVelocityEnabled),
            sensitivity: Defaults.sanitizedKeySoundsSensitivity(
                defaults.double(forKey: DefaultsKey.keySoundsSensitivity)),
            release: defaults.bool(forKey: DefaultsKey.keySoundsReleaseEnabled),
            muteModifiers: defaults.bool(forKey: DefaultsKey.keySoundsMuteModifiers)
        )
        lock.withLock { settings = next }

        guard shouldRun else {
            stopTap()
            sensor.stop()
            engine.queue.async { [engine] in engine.unload() }
            sensorState = sensor.state
            isRunning = false
            return
        }

        let volume = Float(Defaults.sanitizedKeySoundsVolume(defaults.double(forKey: DefaultsKey.keySoundsVolume)))
        let builtInOnly = defaults.bool(forKey: DefaultsKey.keySoundsBuiltInSpeakersOnly)
        let pack = selectedPack()
        engine.queue.async { [engine] in
            engine.volume = volume
            engine.builtInSpeakersOnly = builtInOnly
            if let pack { engine.load(pack: pack) }
            engine.start()
        }
        if next.velocity { sensor.start() } else { sensor.stop() }
        sensorState = sensor.state
        startTap()
    }

    func suspend() {
        stopTap()
        sensor.stop()
        unregisterShortcut()
        engine.queue.async { [engine] in engine.unload() }
        isRunning = false
    }

    func setEnabled(_ enabled: Bool) {
        UserDefaults.standard.set(enabled, forKey: DefaultsKey.keySoundsEnabled)
        syncWithPreferences()
        if enabled, !AXIsProcessTrusted() {
            Permissions.shared.requestAccessibility()
            Permissions.shared.openAccessibilitySettings()
        }
    }

    func toggle() { setEnabled(!UserDefaults.standard.bool(forKey: DefaultsKey.keySoundsEnabled)) }

    func selectedPack() -> KeySoundPackInfo? {
        if packs.isEmpty { packs = KeySoundPackCatalog.available() }
        let id = UserDefaults.standard.string(forKey: DefaultsKey.keySoundsPack) ?? Defaults.defaultKeySoundsPack
        return packs.first { $0.id == id } ?? packs.first { $0.id == Defaults.defaultKeySoundsPack } ?? packs.first
    }

    func reloadPacks() { packs = KeySoundPackCatalog.available() }

    /// Plays a short phrase with the chosen pack, even while switched off.
    func preview(_ pack: KeySoundPackInfo) {
        let volume = Float(Defaults.sanitizedKeySoundsVolume(
            UserDefaults.standard.double(forKey: DefaultsKey.keySoundsVolume)))
        engine.queue.async { [weak self, engine] in
            engine.volume = volume
            engine.builtInSpeakersOnly = false
            guard engine.load(pack: pack) else { return }
            engine.start()
            let phrase: [(KeySoundGroup, KeySoundStrength, Double)] = [
                (.alpha, .soft, 0), (.alpha, .medium, 0.11), (.alpha, .medium, 0.2), (.alpha, .hard, 0.3),
                (.space, .medium, 0.45), (.alpha, .medium, 0.6), (.alpha, .soft, 0.7),
                (.delete, .medium, 0.85), (.enter, .slam, 1.05),
            ]
            for (group, strength, delay) in phrase {
                engine.queue.asyncAfter(deadline: .now() + delay) { engine.playPress(group, strength) }
            }
            engine.queue.asyncAfter(deadline: .now() + 2.5) {
                DispatchQueue.main.async { self?.syncWithPreferences() }
            }
        }
    }

    // MARK: Key events

    private func handle(type: CGEventType, event: CGEvent) {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap = lock.withLock({ tap }) { CGEvent.tapEnable(tap: tap, enable: true) }
            return
        }
        let code = event.getIntegerValueField(.keyboardEventKeycode)
        let now = DispatchTime.now().uptimeNanoseconds
        let current = lock.withLock { settings }

        switch type {
        case .keyDown:
            guard event.getIntegerValueField(.keyboardEventAutorepeat) == 0 else { return }
            let bounce = lock.withLock { () -> Bool in
                defer { lastPress = (code, now) }
                return lastPress.code == code && now - lastPress.at < 15_000_000
            }
            guard !bounce else { return }
            press(KeySoundGroup.group(forKeyCode: code), at: now, settings: current)
        case .keyUp:
            guard current.release else { return }
            let group = KeySoundGroup.group(forKeyCode: code)
            engine.queue.async { [engine] in engine.playRelease(group) }
        case .flagsChanged:
            guard KeySoundGroup.isModifier(keyCode: code), !current.muteModifiers else { return }
            if Self.modifierIsDown(code: code, flags: event.flags) {
                press(.modifier, at: now, settings: current)
            } else if current.release {
                engine.queue.async { [engine] in engine.playRelease(.modifier) }
            }
        default:
            return
        }
    }

    private func press(_ group: KeySoundGroup, at time: UInt64, settings: Settings) {
        guard settings.velocity, sensor.state == .running else {
            engine.queue.async { [engine] in engine.playPress(group, .medium) }
            return
        }
        // Wait for the jolt to reach the accelerometer, then judge it.
        engine.queue.asyncAfter(deadline: .now() + .milliseconds(22)) { [weak self] in
            guard let self else { return }
            let strength: KeySoundStrength
            if let peak = self.sensor.peak(around: time) {
                strength = self.classifier.classify(peak: peak, sensitivity: settings.sensitivity)
            } else {
                strength = .medium
            }
            self.engine.playPress(group, strength)
            DispatchQueue.main.async { self.lastStrength = strength }
        }
    }

    private static func modifierIsDown(code: Int64, flags: CGEventFlags) -> Bool {
        switch code {
        case 56, 60: return flags.contains(.maskShift)
        case 59, 62: return flags.contains(.maskControl)
        case 58, 61: return flags.contains(.maskAlternate)
        case 54, 55: return flags.contains(.maskCommand)
        case 63: return flags.contains(.maskSecondaryFn)
        default: return true   // Caps Lock: every change is a press
        }
    }

    // MARK: Event tap lifecycle

    private func startTap() {
        let alreadyRunning = lock.withLock { tapThread != nil }
        guard !alreadyRunning else { isRunning = true; return }
        let thread = Thread { [weak self] in self?.runTap() }
        thread.name = "Vorssaint Key Sounds"
        thread.qualityOfService = .userInteractive
        lock.withLock { tapThread = thread }
        thread.start()
    }

    private func stopTap() {
        let (tap, loop) = lock.withLock { () -> (CFMachPort?, CFRunLoop?) in
            defer { self.tap = nil; tapRunLoop = nil; tapThread = nil }
            return (self.tap, tapRunLoop)
        }
        if let tap {
            CGEvent.tapEnable(tap: tap, enable: false)
            CFMachPortInvalidate(tap)
        }
        if let loop {
            CFRunLoopPerformBlock(loop, CFRunLoopMode.commonModes.rawValue) { CFRunLoopStop(loop) }
            CFRunLoopWakeUp(loop)
        }
    }

    private func runTap() {
        let mask = CGEventMask(1 << CGEventType.keyDown.rawValue)
            | CGEventMask(1 << CGEventType.keyUp.rawValue)
            | CGEventMask(1 << CGEventType.flagsChanged.rawValue)
        guard let tap = CGEvent.tapCreate(
            tap: .cghidEventTap,
            place: .tailAppendEventTap,
            options: .listenOnly,
            eventsOfInterest: mask,
            callback: { _, type, event, userInfo in
                if let userInfo {
                    Unmanaged<KeySoundsService>.fromOpaque(userInfo).takeUnretainedValue()
                        .handle(type: type, event: event)
                }
                return Unmanaged.passUnretained(event)
            },
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            lock.withLock { tapThread = nil }
            DispatchQueue.main.async { self.isRunning = false }
            return
        }
        let loop = CFRunLoopGetCurrent()
        let stillWanted = lock.withLock { () -> Bool in
            guard tapThread === Thread.current else { return false }
            self.tap = tap
            tapRunLoop = loop
            return true
        }
        guard stillWanted else { CFMachPortInvalidate(tap); return }
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(loop, source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        DispatchQueue.main.async { self.isRunning = true }
        CFRunLoopRun()
        CFRunLoopRemoveSource(loop, source, .commonModes)
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            if self.lock.withLock({ self.tapThread == nil }) { self.isRunning = false }
        }
    }

    // MARK: Toggle shortcut

    private func syncShortcut(available: Bool) {
        guard available, UserDefaults.standard.bool(forKey: DefaultsKey.keySoundsShortcutEnabled) else {
            unregisterShortcut()
            return
        }
        let shortcut = GlobalShortcutRole.keySounds.savedShortcut
        if hotKeyRef != nil, registeredShortcut == shortcut { return }
        unregisterShortcut()
        if hotKeyHandler == nil {
            var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
            InstallEventHandler(GetEventDispatcherTarget(), { _, event, userData -> OSStatus in
                guard let userData else { return OSStatus(eventNotHandledErr) }
                var id = EventHotKeyID()
                if let event {
                    GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                                      nil, MemoryLayout<EventHotKeyID>.size, nil, &id)
                }
                guard id.signature == 0x564B_534E, id.id == 1 else { return OSStatus(eventNotHandledErr) }
                let service = Unmanaged<KeySoundsService>.fromOpaque(userData).takeUnretainedValue()
                DispatchQueue.main.async { service.toggleFromShortcut() }
                return noErr
            }, 1, &spec, Unmanaged.passUnretained(self).toOpaque(), &hotKeyHandler)
        }
        var ref: EventHotKeyRef?
        let status = RegisterEventHotKey(shortcut.carbonKeyCode, shortcut.carbonModifiers,
                                         EventHotKeyID(signature: 0x564B_534E, id: 1), // 'VKSN'
                                         GetEventDispatcherTarget(), 0, &ref)
        if status == noErr, let ref {
            hotKeyRef = ref
            registeredShortcut = shortcut
            shortcutRegistrationFailed = false
            SystemShortcutTakeover.claim(DefaultsKey.keySoundsShortcut, shortcut: shortcut)
        } else {
            shortcutRegistrationFailed = true
        }
    }

    /// Lets go of the key while the settings field records a new one.
    func suspendShortcut() { unregisterShortcut() }

    private func unregisterShortcut() {
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
            SystemShortcutTakeover.release(DefaultsKey.keySoundsShortcut)
        }
        hotKeyRef = nil
        registeredShortcut = nil
    }

    private func toggleFromShortcut() {
        toggle()
        // Audible confirmation: a click when on, a soft system tick when off.
        if isEnabled {
            engine.queue.asyncAfter(deadline: .now() + 0.05) { [engine] in engine.playPress(.enter, .medium) }
        } else {
            NSSound(named: "Tink")?.play()
        }
    }
}
