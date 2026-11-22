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
    private var nativeOutputKeysHeld: [Int32: NativeVolumeKeyPress] = [:]
    private var drainingNativeKeys = false
    /// Includes presses waiting for their main-queue dispatch or native replay.
    private var pendingNotchKeys = 0
    /// Monitor volume presses this tap claimed and has not yet seen released,
    /// so their key-ups are consumed too. Main thread only: the tap runs there.
    private var monitorVolumeKeysHeld: [BrightnessSupport.VolumeKeyAction: BrightnessSupport.SpeakerTarget] = [:]
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
        let wanted = (AppFeature.mixer.isAvailable
            && (UserDefaults.standard.bool(forKey: DefaultsKey.preciseVolumeRollerEnabled)
                || (NotchSupport.routes(.volume) && NotchService.shared.acceptsSystemFeedback)))
            || (AppFeature.brightness.isAvailable && BrightnessService.shared.wantsMonitorVolumeKeys)
        drainingNativeKeys = !wanted && nativeOutputKeysHeld.values.contains { $0 != .unchanged }
        if SessionActivitySupport.tapShouldRun(featureWanted: wanted || drainingNativeKeys,
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
        nativeOutputKeysHeld.removeAll()
        drainingNativeKeys = false
        monitorVolumeKeysHeld = [:]
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
        let consumed = routeVolumeKey(nsEvent, event: event)
        if drainingNativeKeys, nativeOutputKeysHeld.values.allSatisfy({ $0 == .unchanged }) {
            drainingNativeKeys = false
            DispatchQueue.main.async { [weak self] in self?.syncWithPreferences() }
        }
        return consumed ? nil : Unmanaged.passUnretained(event)
    }

    private func routeVolumeKey(_ nsEvent: NSEvent, event: CGEvent) -> Bool {
        if routeMonitorVolume(nsEvent, flags: event.flags) {
            nativeOutputKeysHeld[Int32((nsEvent.data1 >> 16) & 0xffff)] = nil
            return true
        }
        if let consumed = routeNativeOutputKey(nsEvent, event: event) { return consumed }
        guard AppFeature.mixer.isAvailable else { return false }
        if routeNotchVolume(nsEvent, event: event) { return true }
        guard UserDefaults.standard.bool(forKey: DefaultsKey.preciseVolumeRollerEnabled),
              let volumePress = Self.volumePress(fromData1: nsEvent.data1) else {
            return false
        }

        if keyOwnership.leavesToSystem(
            keyCode: volumePress.keyCode, isDown: volumePress.isDown, isRepeat: volumePress.isRepeat,
            option: event.flags.contains(.maskAlternate),
            commandOrControl: !event.flags.isDisjoint(with: [.maskCommand, .maskControl])) {
            return false
        }

        guard volumePress.isDown else { return true }
        guard gate.accepts(volumePress.direction, at: ProcessInfo.processInfo.systemUptime) else {
            return true
        }
        Self.postFineStep(volumePress.keyCode)
        return true
    }

    /// Keep the original HID press together. Only a fresh down can choose this
    /// route; repeats and releases from the island or roller return to their owner.
    private func routeNativeOutputKey(_ nsEvent: NSEvent, event: CGEvent) -> Bool? {
        let code = Int32((nsEvent.data1 >> 16) & 0xffff)
        guard let key = PreciseVolumeMediaKey(rawValue: code), key != .play else { return nil }
        let state = (nsEvent.data1 >> 8) & 0xff
        guard state == 0x0a || state == 0x0b else { return nil }
        let startsPress = state == 0x0a && nsEvent.data1 & 1 == 0
        if startsPress {
            nativeOutputKeysHeld[code] = nil
            guard AppFeature.mixer.isAvailable, pendingNotchKeys == 0 else { return nil }
            let precise = key.rollerDirection != nil
                && UserDefaults.standard.bool(forKey: DefaultsKey.preciseVolumeRollerEnabled)
            guard precise || (NotchSupport.routes(.volume) && NotchService.shared.showsSystemFeedback),
                  AppVolumeMixer.shared.prefersNativeOutputKey(key) else { return nil }
            let addsFine = precise && event.flags.isDisjoint(with: [.maskAlternate, .maskCommand, .maskControl])
            nativeOutputKeysHeld[code] = addsFine ? .fine : .unchanged
        }
        guard let press = nativeOutputKeysHeld[code] else { return nil }
        if state == 0x0b { nativeOutputKeysHeld[code] = nil }
        switch press {
        case .unchanged: return false
        case .suppressed: return true
        case .fine:
            if state == 0x0a, let direction = key.rollerDirection,
               !gate.accepts(direction, at: ProcessInfo.processInfo.systemUptime) {
                // A filtered down has no native counterpart to repeat or release.
                if startsPress { nativeOutputKeysHeld[code] = .suppressed }
                return true
            }
            event.flags.formUnion([.maskAlternate, .maskShift])
            return false
        }
    }

    /// Routes a volume press to the monitor the sound plays through, when macOS
    /// cannot set that output's volume. Every other press keeps its path. The
    /// tap only queues the change. All device I/O happens on the DDC queue.
    private func routeMonitorVolume(_ nsEvent: NSEvent, flags: CGEventFlags) -> Bool {
        guard let press = BrightnessSupport.volumeKeyEvent(
            subtype: Int(nsEvent.subtype.rawValue), data1: nsEvent.data1) else { return false }
        let code = Int32((nsEvent.data1 >> 16) & 0xffff)
        if !press.isKeyDown {
            guard monitorVolumeKeysHeld.removeValue(forKey: press.action) != nil else { return false }
            if feedback?.key == code {
                feedback?.released = true
                playFeedbackIfReady()
            }
            return true
        }
        let held = monitorVolumeKeysHeld[press.action]
        if !press.isRepeat { monitorVolumeKeysHeld[press.action] = nil }
        if press.isRepeat && held == nil { return false }
        guard let fine = BrightnessSupport.volumeKeyFineness(
            option: flags.contains(.maskAlternate), shift: flags.contains(.maskShift),
            commandOrControl: !flags.isDisjoint(with: [.maskCommand, .maskControl])),
              BrightnessService.shared.wantsMonitorVolumeKeys,
              let output = AppVolumeMixer.shared.monitorOutput,
              press.action != .toggleMute || output.muted != nil else {
            if !press.isRepeat {
                DispatchQueue.main.async { BrightnessService.shared.rescanForUnclaimedVolumeKey() }
            }
            return press.isRepeat && held != nil
        }
        if press.isRepeat, held != output.target || press.action == .toggleMute { return true }
        monitorVolumeKeysHeld[press.action] = output.target
        let action = press.action
        // The precise volume setting applies to the monitor as it does to any
        // other output: wheel bursts are thinned by the same gate and each
        // accepted click takes the fine step.
        let precise = AppFeature.mixer.isAvailable
            && UserDefaults.standard.bool(forKey: DefaultsKey.preciseVolumeRollerEnabled)
        if precise, case let .step(direction) = action,
           !gate.accepts(direction > 0 ? .up : .down, at: ProcessInfo.processInfo.systemUptime) {
            return true
        }
        let target = output.target
        // The monitor's speakers click like the system's own outputs: on
        // release, once the step landed, under the same feedback setting.
        feedbackStep &+= 1
        let step = feedbackStep
        feedback = NotchVolumeKeyGate.playsFeedback(
            setting: UserDefaults.standard.bool(forKey: "com.apple.sound.beep.feedback"),
            option: flags.contains(.maskAlternate), shift: flags.contains(.maskShift))
            ? (code, step, false, false) : nil
        DispatchQueue.main.async { [weak self] in
            self?.applyMonitorVolumeKey(action, target: target, fine: fine || precise, step: step)
        }
        return true
    }

    /// Applies a press that routeMonitorVolume claimed. Main thread only, where
    /// the mixer's monitor output and its request path live.
    private func applyMonitorVolumeKey(_ action: BrightnessSupport.VolumeKeyAction,
                                       target: BrightnessSupport.SpeakerTarget, fine: Bool, step: Int) {
        let mixer = AppVolumeMixer.shared
        guard mixer.monitorOutput?.target == target else {
            if feedback?.step == step { feedback = nil }
            return
        }
        func landed(_ result: AppVolumeMixer.OutputKeyResult) {
            let applied = result == .applied && mixer.monitorOutput?.target == target
            if applied { Self.showMonitorFeedback() }
            guard feedback?.step == step else { return }
            // Like macOS, the mute key clicks only when it unmutes.
            if applied, action != .toggleMute || mixer.monitorOutput?.muted == false {
                feedback?.applied = true
            } else {
                feedback = nil
            }
            playFeedbackIfReady()
        }
        switch action {
        case let .step(direction):
            let settings = BrightnessService.shared.monitorVolumeKeySettings
            mixer.requestOutputStep(level: {
                settings.requestedLevel(from: $0, direction: direction, fine: fine)
            }, raises: direction > 0, completion: landed)
        case .toggleMute:
            mixer.requestOutputMuteToggle(completion: landed)
        }
    }

    /// Shows the monitor's level after a key moved it. The island takes the
    /// notice when it can; the brightness overlay is the fallback.
    private static func showMonitorFeedback() {
        if NotchService.shared.showCurrentVolume() { return }
        guard let output = AppVolumeMixer.shared.monitorOutput else { return }
        BrightnessOSD.show(displayID: output.target.displayID, level: output.volume,
                           kind: output.muted == true ? .mutedVolume : .volume)
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
            hasVolume: mixer.systemOutputVolume != nil && !mixer.outputIsMonitorSpeakers,
            hasMute: mixer.systemOutputMuted != nil && !mixer.outputIsMonitorSpeakers,
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
        let lifetime = mixer.currentOutputControlLifetime
        // CoreAudio can wait for a reconnecting device. Never hold the event
        // tap's reply while reading or writing the audio driver.
        pendingNotchKeys += 1
        DispatchQueue.main.async { [weak self] in
            guard mixer.currentOutputControlLifetime == lifetime, !mixer.outputIsMonitorSpeakers else {
                self?.pendingNotchKeys -= 1
                return
            }
            let completion: (AppVolumeMixer.OutputKeyResult) -> Void = { result in
                defer { self?.pendingNotchKeys -= 1 }
                let applied = result == .applied
                if let self, self.feedback?.step == step {
                    // The forwarded native press plays its own feedback.
                    if applied { self.feedback?.applied = true; self.playFeedbackIfReady() }
                    else { self.feedback = nil }
                }
                if result == .fallback, let fallback {
                    if precise, key.rollerDirection != nil {
                        fallback.flags.formUnion([.maskAlternate, .maskShift])
                    }
                    fallback.setIntegerValueField(.eventSourceUserData, value: PreciseVolumeKeyEvents.postedMarker)
                    fallback.post(tap: .cgSessionEventTap)
                    Self.postForwardedRelease(code)
                }
            }
            // Both keys start from the device's own reading, so the island
            // shows the result once it has been applied. A native fallback
            // publishes its state through the listeners.
            if key == .mute {
                mixer.requestOutputMuteToggle { result in
                    if result == .applied, mixer.systemOutputMuted == true, self?.feedback?.step == step {
                        self?.feedback = nil
                    }
                    completion(result)
                    if result == .applied { NotchService.shared.showCurrentVolume() }
                }
            } else if mixer.systemOutputVolume != nil {
                let direction = key == .volumeUp ? 1 : -1
                mixer.requestOutputStep(level: {
                    NotchSupport.volumeLevel(current: $0, direction: direction, fine: fine)
                }, completion: { result in
                    completion(result)
                    if result == .applied { NotchService.shared.showCurrentVolume() }
                })
            } else { completion(.fallback) }
        }
        return true
    }

    /// The click macOS plays after a volume change, under its "Play feedback
    /// when volume is changed" setting.
    static func playVolumeFeedback() {
        guard UserDefaults.standard.bool(forKey: "com.apple.sound.beep.feedback") else { return }
        volumeFeedback?.stop()
        volumeFeedback?.play()
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
