// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import Combine

/// Turns coarse hardware volume wheel bursts into macOS' fine volume step.
/// Active only while enabled and Accessibility is granted.
final class PreciseVolumeRollerService: ObservableObject {
    static let shared = PreciseVolumeRollerService()

    @Published private(set) var tapFailed = false

    private var tap: CFMachPort?
    private var source: CFRunLoopSource?
    private var gate = PreciseVolumeRollerGate()
    private var keyOwnership = PreciseVolumeKeyOwnership()
    private var notchKeyGate = NotchVolumeKeyGate()
    /// Island steps bypass the system, so its volume click plays on release here.
    /// Waits for both the release and the last step's adjustment, so a failed
    /// step forwarded to macOS never plays a second click.
    private var feedback: (key: Int32, step: Int, applied: Bool, released: Bool)?
    private var feedbackStep = 0
    private static let volumeFeedback = NSSound(
        contentsOfFile: "/System/Library/LoginPlugins/BezelServices.loginPlugin/Contents/Resources/volume.aiff",
        byReference: true)

    private init() {
        SessionActivity.shared.onChange { [weak self] _ in self?.syncWithPreferences() }
    }

    func syncWithPreferences() {
        let wanted = AppFeature.mixer.isAvailable
            && (UserDefaults.standard.bool(forKey: DefaultsKey.preciseVolumeRollerEnabled)
                || (NotchSupport.routes(.volume) && NotchService.shared.acceptsSystemFeedback))
        if SessionActivitySupport.tapShouldRun(featureWanted: wanted,
                                               accessibilityGranted: AXIsProcessTrusted(),
                                               sessionIsActive: SessionActivity.shared.isActive) {
            start()
        } else {
            stop()
        }
    }

    func suspend() {
        stop()
    }

    func stop() {
        removeTap()
        tapFailed = false
    }

    private func removeTap() {
        if let tap { CGEvent.tapEnable(tap: tap, enable: false) }
        if let source {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
        }
        if let tap { CFMachPortInvalidate(tap) }
        tap = nil
        source = nil
        gate.reset()
        notchKeyGate = NotchVolumeKeyGate()
        feedback = nil
        keyOwnership = PreciseVolumeKeyOwnership()
    }

    private func start() {
        guard AXIsProcessTrusted() else {
            removeTap()
            tapFailed = false
            return
        }
        if let tap, !CGEvent.tapIsEnabled(tap: tap) {
            CGEvent.tapEnable(tap: tap, enable: true)
        }
        guard tap == nil else { return }

        let systemDefined = CGEventType(rawValue: CleaningSystemKeyEvent.systemDefinedEventTypeRawValue)!
        let callback: CGEventTapCallBack = { _, type, event, userInfo in
            guard let userInfo else { return Unmanaged.passUnretained(event) }
            let service = Unmanaged<PreciseVolumeRollerService>
                .fromOpaque(userInfo)
                .takeUnretainedValue()
            return service.handle(type: type, event: event)
        }
        guard let created = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: CGEventMask(1 << systemDefined.rawValue),
            callback: callback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            tapFailed = true
            return
        }

        tap = created
        source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, created, 0)
        if let source {
            CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        }
        CGEvent.tapEnable(tap: created, enable: true)
        tapFailed = false
    }

    private func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if SessionActivity.shared.isActive, AXIsProcessTrusted(), let tap {
                CGEvent.tapEnable(tap: tap, enable: true)
            } else {
                DispatchQueue.main.async { [weak self] in self?.syncWithPreferences() }
            }
            return Unmanaged.passUnretained(event)
        }
        guard type.rawValue == CleaningSystemKeyEvent.systemDefinedEventTypeRawValue,
              let nsEvent = NSEvent(cgEvent: event),
              nsEvent.subtype.rawValue == 8 else { return Unmanaged.passUnretained(event) }
        if PreciseVolumeKeyEvents.isPosted(event) {
            return Unmanaged.passUnretained(event)
        }
        if routeNotchVolume(nsEvent, event: event) { return nil }
        guard UserDefaults.standard.bool(forKey: DefaultsKey.preciseVolumeRollerEnabled),
              let volumePress = Self.volumePress(fromData1: nsEvent.data1) else {
            return Unmanaged.passUnretained(event)
        }

        if keyOwnership.leavesToSystem(
            keyCode: volumePress.keyCode, isDown: volumePress.isDown, isRepeat: volumePress.isRepeat,
            option: event.flags.contains(.maskAlternate),
            commandOrControl: !event.flags.isDisjoint(with: [.maskCommand, .maskControl])) {
            return Unmanaged.passUnretained(event)
        }

        guard volumePress.isDown else { return nil }
        guard gate.accepts(volumePress.direction, at: ProcessInfo.processInfo.systemUptime) else {
            return nil
        }
        Self.postFineStep(volumePress.keyCode)
        return nil
    }

    private func routeNotchVolume(_ nsEvent: NSEvent, event: CGEvent) -> Bool {
        let code = Int32((nsEvent.data1 >> 16) & 0xffff)
        let state = (nsEvent.data1 >> 8) & 0xff
        guard let key = PreciseVolumeMediaKey(rawValue: code), key != .play else { return false }
        let mixer = AppVolumeMixer.shared
        let action = notchKeyGate.handle(
            keyCode: code, state: state, isRepeat: nsEvent.data1 & 1 != 0,
            enabled: NotchSupport.routes(.volume) && NotchService.shared.acceptsSystemFeedback,
            acceptsNewPress: NotchService.shared.showsSystemFeedback,
            hasVolume: mixer.systemOutputVolume != nil, hasMute: mixer.systemOutputMuted != nil,
            option: event.flags.contains(.maskAlternate), shift: event.flags.contains(.maskShift),
            commandOrControl: event.flags.contains(.maskCommand) || event.flags.contains(.maskControl))
        if action == .passThrough { return false }
        if action == .consume {
            if state == 0x0b, feedback?.key == code {
                feedback?.released = true
                playFeedbackIfReady()
            }
            return true
        }
        let precise = UserDefaults.standard.bool(forKey: DefaultsKey.preciseVolumeRollerEnabled)
        if precise, let direction = key.rollerDirection,
           !gate.accepts(direction, at: ProcessInfo.processInfo.systemUptime) { return true }
        feedbackStep &+= 1
        let step = feedbackStep
        // Like macOS, the mute key clicks only when it unmutes. The toggle
        // follows the output's own reading, so its result decides that below.
        feedback = NotchVolumeKeyGate.playsFeedback(
            setting: UserDefaults.standard.bool(forKey: "com.apple.sound.beep.feedback"),
            option: event.flags.contains(.maskAlternate), shift: event.flags.contains(.maskShift))
            ? (code, step, false, false) : nil
        let fine = precise || (event.flags.contains(.maskAlternate) && event.flags.contains(.maskShift))
        let fallback = event.copy()
        // CoreAudio can wait for a reconnecting device. Never hold the event
        // tap's reply while reading or writing the audio driver.
        DispatchQueue.main.async { [weak self] in
            let completion: (Bool) -> Void = { applied in
                if let self, self.feedback?.step == step {
                    // The forwarded native press plays its own feedback.
                    if applied { self.feedback?.applied = true; self.playFeedbackIfReady() }
                    else { self.feedback = nil }
                }
                if !applied, let fallback {
                    fallback.setIntegerValueField(.eventSourceUserData, value: PreciseVolumeKeyEvents.postedMarker)
                    fallback.post(tap: .cgSessionEventTap)
                    Self.postForwardedRelease(code)
                }
            }
            // Both keys start from the device's own reading, so the island
            // shows the result once it has been applied. A native fallback
            // publishes its state through the listeners.
            if key == .mute, mixer.systemOutputMuted != nil {
                mixer.requestOutputMuteToggle { applied in
                    if applied, mixer.systemOutputMuted == true, self?.feedback?.step == step {
                        self?.feedback = nil
                    }
                    completion(applied)
                    if applied { NotchService.shared.showCurrentVolume() }
                }
            } else if mixer.systemOutputVolume != nil {
                let direction = key == .volumeUp ? 1 : -1
                mixer.requestOutputStep(level: {
                    NotchSupport.volumeLevel(current: $0, direction: direction, fine: fine)
                }, completion: { applied in
                    completion(applied)
                    if applied { NotchService.shared.showCurrentVolume() }
                })
            } else { completion(false) }
        }
        return true
    }

    private func playFeedbackIfReady() {
        guard let feedback, feedback.applied, feedback.released else { return }
        self.feedback = nil
        Self.volumeFeedback?.stop()
        Self.volumeFeedback?.play()
    }

    private static func postForwardedRelease(_ code: Int32) {
        let event = NSEvent.otherEvent(with: .systemDefined, location: .zero,
                                      modifierFlags: NSEvent.ModifierFlags(rawValue: 0xB00),
                                      timestamp: 0, windowNumber: 0, context: nil,
                                      subtype: 8, data1: Int(code << 16) | 0xB00, data2: -1)?.cgEvent
        event?.setIntegerValueField(.eventSourceUserData, value: PreciseVolumeKeyEvents.postedMarker)
        event?.post(tap: .cgSessionEventTap)
    }

    private static func volumePress(fromData1 data1: Int) -> (keyCode: Int32,
                                                             direction: PreciseVolumeRollerDirection,
                                                             isDown: Bool,
                                                             isRepeat: Bool)? {
        let keyCode = Int32((data1 >> 16) & 0xffff)
        guard let mediaKey = PreciseVolumeMediaKey(rawValue: keyCode),
              let direction = mediaKey.rollerDirection else { return nil }
        let state = (data1 >> 8) & 0xff
        return (keyCode, direction, state == 0x0a, data1 & 1 != 0)
    }

    private static func postFineStep(_ keyCode: Int32) {
        PreciseVolumeKeyEvents.fineStep(keyCode).forEach { $0.post(tap: .cghidEventTap) }
    }
}
