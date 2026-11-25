// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import AudioToolbox
import CoreAudio
import Foundation

/// Applies each available microphone's mute control and drops its input
/// volume to zero. The mute switch on its own does not zero capture on many
/// Macs, so the volume has to go with it — the same control System Settings
/// uses. Apps can select their own input, so this covers devices beyond the
/// system default. These controls are not a privacy lock: Siri and some
/// voice-processing paths may ignore them, even when the properties read muted.
/// It reports the feature state and whether the input controls confirmed mute.
/// No captured audio is inspected.
/// Device, default-input and per-device level changes reapply the request, and
/// the state survives relaunches. A device this app changed stays its to
/// restore even while unplugged: it gets its saved level back when it returns.
final class MicMuteService: ObservableObject {
    static let shared = MicMuteService()

    @Published private(set) var isMuted = false

    enum Warning {
        case muteUnconfirmed, restoreUnconfirmed, restoreExhausted, manualRestore

        var message: String {
            switch self {
            case .muteUnconfirmed: L10n.shared.s.micMutePartialHUD
            case .restoreUnconfirmed: L10n.shared.s.micUnmutePartialHUD
            case .restoreExhausted: L10n.shared.s.micRestoreExhaustedHUD
            case .manualRestore: L10n.shared.s.micManualRestore
            }
        }

        func showHUD() {
            QuickToolHUD.show(icon: "exclamationmark.triangle", message: message, showsFullMessage: true)
        }
    }
    @Published private(set) var warning: Warning?
    @Published private(set) var shortcutRegistrationFailed = false
    var hasUnconfirmedInputs: Bool { warning == .muteUnconfirmed }

    var controlSymbol: String {
        if warning != nil { return "exclamationmark.triangle" }
        return isMuted ? "mic.slash.fill" : "mic"
    }

    private let hotkey = QuickToolHotkey(id: 12)
    private var installedListeners: [AudioObjectPropertySelector: ListenerLifetime] = [:]
    private var wantsSystemListeners = false
    private var systemListenerRetry: DispatchWorkItem?
    private var systemListenerRetryIndex = 0
    private var systemListenerRetryGeneration: UInt64?
    /// Core Audio registers by object ID and property address. Keep the UID as
    /// well so an input that reuses a departed device's ID gets a fresh listener.
    private var deviceListeners: [DeviceListener: (uid: String, lifetime: ListenerLifetime)] = [:]
    private var listenersToRenew: Set<DeviceListener> = []
    private var topologyGaps: Set<AudioDeviceID> = []
    private var observedDeviceListChange: UInt64?
    /// Nil before the initial mute subscribes. After a topology change, an
    /// input becomes eligible for a quiet baseline only after registration.
    private var observedInputs: Set<InputDevice>?
    /// Reading or writing a device property can block for as long as the audio
    /// daemon holds the device (a headset connecting, an interface waking),
    /// and that is exactly the moment the listeners fire. Sweeping every
    /// device on the main thread would hand the app one hang per reconnection,
    /// so all of it happens here, one sweep at a time.
    private let halQueue = DispatchQueue(label: "com.vorssaint.utils.micmute.hal", qos: .userInitiated)
    /// A sweep that finished after a newer one started must not publish what
    /// it saw.
    private var applyGeneration = 0
    /// Only the serial audio queue updates retry state or runs the timer.
    private typealias ControlRetries = [InputDevice: [String: MicMuteSupport.Retry]]
    private var retries: ControlRetries = [:]
    /// A pending control gets a first check and up to two timed retries.
    private struct RestoreAttempt {
        let target: Double
        let count: Int
        let deadline: TimeInterval?
        let hasSubmitted: Bool
        var unknownAccessElements: Set<UInt32> = []

        init(target: Double, previous: Self?, submitted: Bool, now: TimeInterval) {
            self.target = target
            count = (previous?.count ?? 0) + 1
            deadline = count < 3 ? now + MicMuteService.recoveryDelays[count - 1] : nil
            hasSubmitted = submitted || previous?.hasSubmitted == true
        }

        func defersWrite(at now: TimeInterval) -> Bool {
            guard let deadline else { return true }
            // A control that first becomes readable can take its first Set
            // on that notification, without waiting for an outstanding timer.
            return (hasSubmitted || !unknownAccessElements.isEmpty) && now < deadline
        }
    }
    private var attemptedRestores: [InputDevice: [String: RestoreAttempt]] = [:]
    private var retryWork: DispatchWorkItem?
    private var retryDeadline: TimeInterval?
    /// Backoff for temporary Core Audio registration and discovery failures.
    private static let recoveryDelays: [TimeInterval] = [0.25, 1, 3, 8, 20]
    private var inventoryRetryIndex: Int?
    private var inventoryRetryWork: DispatchWorkItem?
    private var missingInputUIDs: Set<String> = []
    private let uptime: () -> TimeInterval
    // A call can release only the mute command it observed. Older installations
    // used a Boolean direction, or just the published active flag.
    private static var muteRequestID: String? {
        let defaults = UserDefaults.standard
        let direction = defaults.object(forKey: DefaultsKey.micMuteReleasePending)
        if let id = direction as? String { return id }
        if let release = direction as? Bool { return release ? nil : "legacy" }
        return defaults.bool(forKey: DefaultsKey.micMuteActive) ? "legacy" : nil
    }
    // Device UIDs are nonempty. This entry records the accepted call in the
    // same preference write as the first verified device's remaining controls.
    private static let callReleaseKey = ""
    private static var releasedRequestID: String? {
        UserDefaults.standard.dictionary(forKey: DefaultsKey.micMuteSavedControls)?[callReleaseKey] as? String
    }
    private static var releasePending: Bool {
        if let id = muteRequestID { return releasedRequestID == id }
        return UserDefaults.standard.object(forKey: DefaultsKey.micMuteReleasePending) as? Bool == true
    }
    private static var storedMuteRequest: Bool {
        guard let id = muteRequestID else { return false }
        return releasedRequestID != id
    }
    /// The direction of a queued request is available before its UI publication.
    private var wantsMute = MicMuteService.storedMuteRequest

    private static func setReleasePending(_ pending: Bool) {
        let defaults = UserDefaults.standard
        let direction = defaults.object(forKey: DefaultsKey.micMuteReleasePending)
        if pending {
            if direction as? Bool != true { defaults.set(true, forKey: DefaultsKey.micMuteReleasePending) }
        } else if direction != nil { defaults.removeObject(forKey: DefaultsKey.micMuteReleasePending) }
    }

    /// Defaults observers can start a new request while the previous one publishes.
    private func publishActive(_ active: Bool, generation: Int) -> Bool {
        guard generation == applyGeneration else { return false }
        let defaults = UserDefaults.standard
        // A rejected first mute may still owe a restore from the previous cycle.
        if !active && (hasOutstandingClaims || defaults.bool(forKey: DefaultsKey.micMuteActive)) {
            Self.setReleasePending(true)
            guard generation == applyGeneration else { return false }
        }
        if defaults.bool(forKey: DefaultsKey.micMuteActive) != active {
            defaults.set(active, forKey: DefaultsKey.micMuteActive)
            guard generation == applyGeneration else { return false }
        }
        if !active && !hasOutstandingClaims { Self.setReleasePending(false) }
        return generation == applyGeneration
    }

    /// Core Audio may call from multiple threads. A burst only needs one
    /// handoff to main, and all sweeps are still serialized on halQueue.
    private let callbackLock = NSLock()
    private var callbackQueued = false
    private var topologyRevision: UInt64 = 0
    private var callbackBindings: [UnsafeMutableRawPointer: DeviceListener] = [:]
    private var confirmedControlClients: Set<UnsafeMutableRawPointer> = []
    private typealias ControlNotices = [DeviceListener: UnsafeMutableRawPointer]
    private typealias ControlReader = (AudioDeviceID, AudioObjectPropertyAddress) -> Double?
    private struct InputNotices {
        var topology: Set<AudioObjectID> = []
        var controls: ControlNotices = [:]
    }
    private var pendingNotices = InputNotices()
    private var listObservationGeneration: UInt64?
    private var audioGeneration: UInt64 = 0
    private var lastConfirmedReset: UInt64 = 0
    private var resetObservationMissing = false
    private var currentAudioGeneration: UInt64 { callbackLock.withLock { audioGeneration } }

    /// Main thread. While a sweep is outstanding, keep one follow-up for
    /// changes it may already have read past.
    private var applyInFlight = false
    private var reapplyPending = false
    private typealias InputControls = MicMuteSupport.InputControls
    /// Restore claims survive disconnects by UID. Control observations on the
    /// serial audio queue belong only to the current device connection.
    private var quietInputs: [InputDevice: InputControls] = [:]
    /// An ignored mute write can echo through another control on the same
    /// input. Keep its UID and address until that control also reads closed.
    private struct UnverifiedWrite {
        let uid: String
        var observers: Set<UnsafeMutableRawPointer>
    }
    private var unverifiedWrites: [DeviceListener: UnverifiedWrite] = [:]
    private var observationGeneration: UInt64 = 0
    private let inputVolumeLock = NSLock()
    private var inputVolumeBlocked = MicMuteService.storedMuteRequest
    // An unmuted drag can span several release sweeps.
    private var inputVolumeLifetime = UUID()
    private var sweepRequest = UUID()

    private init(uptime: @escaping () -> TimeInterval = { ProcessInfo.processInfo.systemUptime }) {
        self.uptime = uptime
        if let id = Self.releasedRequestID, Self.muteRequestID == id { Self.setReleasePending(true) }
        Self.recoverControlRecords()
        Self.recoverFirstCaptures()
        if !wantsMute, Self.needsManualCheck {
            warning = .manualRestore
        }
        hotkey.onPress = { [weak self] in self?.toggle() }
    }

    /// The smallest possible answer to a change: the system decides which
    /// thread this arrives on, so it only asks the main thread to re-assert
    /// the mute and returns. Handing a closure back to be removed never
    /// matches the one that was registered, so the plain callback is what
    /// makes stopping work.
    private static let listenerCallback: AudioObjectPropertyListenerProc = { object, count, addresses, client in
        guard let client else { return noErr }
        // A retired token may still arrive. It can request enforcement of the
        // current intent, but it cannot supply a gain, topology or reset event.
        let service = AudioListenerClients.owner(of: client) as? MicMuteService ?? MicMuteService.shared
        let changed = UnsafeBufferPointer(start: addresses, count: Int(count))
        let restarted = service.callbackLock.withLock {
            guard let binding = service.callbackBindings[client], binding.device == object else { return false }
            let system = object == AudioObjectID(kAudioObjectSystemObject)
            if system && changed.contains(where: { $0.mSelector == kAudioHardwarePropertyServiceRestarted }) {
                service.audioGeneration &+= 1
                service.lastConfirmedReset = service.audioGeneration
                service.callbackBindings.removeAll()
                return true
            }
            // Any structural change in the batch invalidates the old reading.
            // Only the subscribed address can affirmatively report an opening.
            if changed.contains(where: { system ? $0.mSelector == kAudioHardwarePropertyDevices
                : MicMuteService.inputTopologySelectors.contains($0.mSelector) }) {
                service.topologyRevision &+= 1
                service.pendingNotices.topology.insert(object)
            } else if service.confirmedControlClients.contains(client), changed.contains(where: binding.matches) {
                service.pendingNotices.controls[binding] = client
            }
            return false
        }
        if restarted {
            DispatchQueue.main.async {
                guard service.wantsMute || service.wantsSystemListeners || service.applyInFlight else { return }
                service.reapplyIfNeeded()
                service.syncSystemListeners(wanted: service.wantsMute || service.wantsSystemListeners)
            }
        } else {
            service.scheduleReapply()
        }
        return noErr
    }

    private func scheduleReapply() {
        let needsHandoff = callbackLock.withLock {
            if callbackQueued || !wantsSystemListeners { return false }
            callbackQueued = true
            return true
        }
        guard needsHandoff else { return }
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            let pending = self.callbackLock.withLock {
                let pending = self.callbackQueued
                self.callbackQueued = false
                return pending
            }
            // A Core Audio delivery can already be in flight while teardown
            // unregisters the last listener, even if an unplugged device is
            // still recorded for restoration on a later launch.
            if pending && (self.wantsMute || self.wantsSystemListeners) {
                self.reapplyIfNeeded()
            }
        }
    }

    func syncWithPreferences() {
        let available = AppFeature.micMute.isAvailable
        let enabled = available
            && UserDefaults.standard.bool(forKey: DefaultsKey.micMuteShortcutEnabled)
        let shortcut = GlobalShortcut.saved(for: DefaultsKey.micMuteShortcut,
                                            fallback: .micMuteDefault)
        shortcutRegistrationFailed = !hotkey.sync(enabled: enabled, shortcut: shortcut,
                                                  storageKey: DefaultsKey.micMuteShortcut)

        if available {
            if !applyInFlight && wantsMute && !Self.releasePending && !isMuted
                && UserDefaults.standard.bool(forKey: DefaultsKey.micMuteActive) {
                // A persisted mute has no readings from this launch yet.
                // A pending release stays visible until the sweep completes.
                warning = .muteUnconfirmed
                isMuted = true
            }
            reapplyIfNeeded()
        } else {
            // Switching the feature off must not strand a muted microphone
            // with no control left to unmute it.
            if wantsMute { apply(muted: false, announce: false) }
            else { reapplyIfNeeded() }
            isMuted = false
            if warning == .muteUnconfirmed { warning = nil }
        }
        syncListeners()
    }

    /// The listeners exist to keep an active mute true while devices come and
    /// go, and to catch a claimed device coming back so it can be released;
    /// they live only as long as one of those is pending.
    private func syncListeners() {
        syncSystemListeners(wanted: wantsMute || isMuted || hasOutstandingClaims)
        let mode: DeviceObservation
        if wantsMute && !Self.releasePending { mode = isMuted ? .muted : .stopped }
        else { mode = .restoring }
        halQueue.async { [weak self] in
            if self?.syncDeviceListeners(mode) == true { self?.scheduleReapply() }
        }
    }

    /// Devices this app silenced and has not yet put back, present or not.
    private var hasOutstandingClaims: Bool {
        let defaults = UserDefaults.standard
        let claimed = defaults.stringArray(forKey: DefaultsKey.micMuteMutedDevices)
        if claimed?.isEmpty == false { return true }
        if Self.pendingLegacyRestore != nil { return true }
        return claimed == nil && defaults.bool(forKey: DefaultsKey.micMuteActive)
    }

    func suspend() {
        hotkey.unregister()
    }

    func toggle() {
        let muted = inputVolumeLock.withLock { inputVolumeBlocked }
        setMuted(!muted || Self.releasePending)
    }

    func setMuted(_ muted: Bool) {
        apply(muted: muted, announce: true, newMuteRequest: muted)
    }

    /// The user checked the input manually. This acknowledgement
    /// dismisses a reminder and never writes to an audio device.
    func acknowledgeManualRestore() {
        guard warning == .manualRestore else { return }
        halQueue.async { [weak self] in
            guard let self else { return }
            UserDefaults.standard.removeObject(forKey: DefaultsKey.micMuteManualCheckNeeded)
            self.refreshManualWarning()
        }
    }

    private static var needsManualCheck: Bool {
        let reminder = UserDefaults.standard.object(forKey: DefaultsKey.micMuteManualCheckNeeded)
        // An earlier build stored outstanding mixer readbacks under this key.
        return reminder as? Bool == true || (reminder as? [String: [String: Double]])?.isEmpty == false
    }

    private static func recoverFirstCaptures() {
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: DefaultsKey.micMuteActive) else { return }
        let recorded = defaults.stringArray(forKey: DefaultsKey.micMuteMutedDevices)
        var owners = Set(recorded ?? [])
        if recorded == nil {
            if let legacyUID = pendingLegacyRestore?.uid { owners.insert(legacyUID) }
            // v3.4.4 wrote both gain maps, then its exact snapshots, after
            // touching the HAL and before publishing the first list of UIDs.
            if let gains = defaults.dictionary(forKey: DefaultsKey.micMuteSavedVolumes) {
                owners.formUnion(gains.keys)
                if let channels = defaults.dictionary(forKey: DefaultsKey.micMuteSavedChannelVolumes) {
                    owners.formUnion(channels.keys)
                    if let snapshots = defaults.dictionary(forKey: DefaultsKey.micMuteSavedControls) {
                        owners.formUnion(snapshots.keys)
                    }
                }
                if !owners.isEmpty { defaults.set(owners.sorted(), forKey: DefaultsKey.micMuteMutedDevices) }
            }
        }
        // Modern preparation can straddle the HAL call. With no recorded
        // result, keep the live settings and let a new mute capture them.
        for key in [DefaultsKey.micMuteSavedControls, DefaultsKey.micMuteSavedVolumes, DefaultsKey.micMuteSavedChannelVolumes] {
            guard let records = defaults.dictionary(forKey: key) else { continue }
            let committed = records.filter { owners.contains($0.key) }
            guard committed.count != records.count else { continue }
            if !needsManualCheck { defaults.set(true, forKey: DefaultsKey.micMuteManualCheckNeeded) }
            defaults.set(committed, forKey: key)
        }
    }

    private func refreshManualWarning() {
        DispatchQueue.main.async {
            guard !self.wantsMute else { return }
            if self.hasOutstandingClaims || Self.releasePending { self.reapplyIfNeeded() }
            else if Self.needsManualCheck { self.warning = .manualRestore }
            else if self.warning == .manualRestore { self.warning = nil }
        }
    }

    var inputVolumeAdjustmentLifetime: UUID? {
        guard !Self.storedMuteRequest else { return nil }
        return inputVolumeLock.withLock { inputVolumeBlocked ? nil : inputVolumeLifetime }
    }

    private struct ReleaseCheckpoint: Codable {
        var controls: [String: Double]
        let protectedChannels: [UInt32]
        let legacy: LegacyDefaultRestore?
        // This process can keep checking a submitted Set. A later process cannot tell
        // whether the user changed that control after the last inconclusive read.
        var unverified: Set<String>?

        static func decode(_ value: Any) -> Self? {
            guard let data = value as? Data else { return nil }
            return try? PropertyListDecoder().decode(Self.self, from: data)
        }

        var storedValue: Any {
            if let data = try? PropertyListEncoder().encode(self) { return data }
            return MicMuteService.changingControls
        }
    }

    private static let changingControls = "changing"

    private static func setControlRecord(_ value: Any?, for uid: String, releasing requestID: String? = nil) {
        let defaults = UserDefaults.standard
        var records = defaults.dictionary(forKey: DefaultsKey.micMuteSavedControls) ?? [:]
        guard value != nil || records[uid] != nil else { return }
        records[uid] = value
        if let requestID { records[callReleaseKey] = requestID }
        defaults.set(records, forKey: DefaultsKey.micMuteSavedControls)
    }

    private static func recoverControlRecords() {
        let defaults = UserDefaults.standard
        setControlRecord(nil, for: callReleaseKey)
        // Earlier versions kept mixer writes and confirmed releases in separate keys.
        if let uid = defaults.string(forKey: DefaultsKey.micMuteMixerHandoffUID) {
            requireManualRestore(for: uid)
            defaults.removeObject(forKey: DefaultsKey.micMuteMixerHandoffUID)
        }
        if let released = defaults.stringArray(forKey: DefaultsKey.micMuteReleasedUIDs) {
            if !released.isEmpty { removeRestoreRecords(for: Set(released)) }
            defaults.removeObject(forKey: DefaultsKey.micMuteReleasedUIDs)
        }
        for (uid, value) in defaults.dictionary(forKey: DefaultsKey.micMuteSavedControls) ?? [:] {
            if let checkpoint = ReleaseCheckpoint.decode(value),
               checkpoint.legacy == nil || checkpoint.legacy?.uid == uid {
                recover(checkpoint, for: uid)
            } else if !(value is [String: Double]) {
                // The setter may already have opened this input before the process exited.
                requireManualRestore(for: uid)
            }
        }
    }

    private static func recover(_ checkpoint: ReleaseCheckpoint, for uid: String) {
        let defaults = UserDefaults.standard
        var controls = checkpoint.controls
        if let unverified = checkpoint.unverified, !unverified.isEmpty {
            defaults.set(true, forKey: DefaultsKey.micMuteManualCheckNeeded)
            for key in unverified { controls.removeValue(forKey: key) }
        }
        guard !controls.isEmpty || checkpoint.legacy != nil else {
            removeRestoreRecords(for: [uid])
            return
        }
        let recorded = defaults.stringArray(forKey: DefaultsKey.micMuteMutedDevices) ?? []
        if !recorded.contains(uid) { defaults.set(recorded + [uid], forKey: DefaultsKey.micMuteMutedDevices) }
        var protection = defaults.dictionary(forKey: DefaultsKey.micMuteProtectedChannels) as? [String: [UInt32]] ?? [:]
        let channels = checkpoint.protectedChannels.isEmpty ? nil : checkpoint.protectedChannels
        if protection[uid] != channels {
            protection[uid] = channels
            defaults.set(protection, forKey: DefaultsKey.micMuteProtectedChannels)
        }
        if let legacy = checkpoint.legacy {
            if pendingLegacyRestore != legacy {
                guard let data = try? JSONEncoder().encode(legacy) else {
                    requireManualRestore(for: uid)
                    return
                }
                defaults.set(data, forKey: DefaultsKey.micMutePendingLegacyControls)
            }
        } else if pendingLegacyRestore?.uid == uid {
            defaults.removeObject(forKey: DefaultsKey.micMutePendingLegacyControls)
        }
        // Keep the checkpoint until the claim, protection and legacy controls agree with it.
        setControlRecord(controls, for: uid)
    }

    /// Called from the input manager's audio queue, never the main thread.
    /// Sharing the mute queue prevents an older gain write from reopening a
    /// microphone after the mute sweep has already silenced it.
    func withUnmutedInput(lifetime: UUID, _ adjustment: () -> Void) {
        halQueue.sync {
            guard inputVolumeAdjustmentLifetime == lifetime else { return }
            adjustment()
        }
    }

    /// Mixer writes share the serial mute queue, so at most one UID can be
    /// between a submitted edit and its result. After an exit, that result is unknown.
    func writeMixerGain(for uid: String, isCurrent: () -> Bool, write: () -> OSStatus) -> OSStatus? {
        let defaults = UserDefaults.standard
        let recorded = defaults.stringArray(forKey: DefaultsKey.micMuteMutedDevices)
        guard recorded?.contains(uid) ?? (Self.pendingLegacyRestore?.uid == uid) else {
            return isCurrent() ? write() : nil
        }

        guard isCurrent() else { return nil }
        let previous = defaults.dictionary(forKey: DefaultsKey.micMuteSavedControls)?[uid]
        Self.setControlRecord(Self.changingControls, for: uid)
        let status = isCurrent() ? write() : nil
        if status == noErr {
            Self.requireManualRestore(for: uid)
            refreshManualWarning()
        } else {
            Self.setControlRecord(previous, for: uid)
        }
        return status
    }

    /// Replay the same cleanup on launch if any of these writes were interrupted.
    private static func requireManualRestore(for uid: String) {
        let defaults = UserDefaults.standard
        if defaults.object(forKey: DefaultsKey.micMuteManualCheckNeeded) as? Bool != true {
            defaults.set(true, forKey: DefaultsKey.micMuteManualCheckNeeded)
        }
        removeRestoreRecords(for: [uid])
    }

    private static func removeRestoreRecords(for uids: Set<String>) {
        let defaults = UserDefaults.standard
        if let uid = pendingLegacyRestore?.uid, uids.contains(uid) {
            defaults.removeObject(forKey: DefaultsKey.micMutePendingLegacyControls)
        }
        let recorded = defaults.stringArray(forKey: DefaultsKey.micMuteMutedDevices)
        let remaining = (recorded ?? []).filter { !uids.contains($0) }
        if remaining != recorded { defaults.set(remaining, forKey: DefaultsKey.micMuteMutedDevices) }
        for key in [DefaultsKey.micMuteSavedVolumes, DefaultsKey.micMuteSavedChannelVolumes,
                    DefaultsKey.micMuteProtectedChannels, DefaultsKey.micMuteSavedControls] {
            if let values = defaults.dictionary(forKey: key), !uids.isDisjoint(with: values.keys) {
                defaults.set(values.filter { !uids.contains($0.key) }, forKey: key)
            }
        }
    }

    /// Unmute for a caller that is about to tear the app down. The queue that
    /// carries a normal sweep may never be drained once the app is going away,
    /// and a microphone left cut by an app that no longer exists is the one
    /// failure this feature cannot afford, so this one waits.
    func unmuteForTeardown() {
        let defaults = UserDefaults.standard
        // A mute still being applied has not reached the flag yet, and a claim
        // is a device this app owes its level back whatever the flag says.
        let mustRestore = wantsMute || defaults.bool(forKey: DefaultsKey.micMuteActive) || hasOutstandingClaims
        guard mustRestore || applyInFlight else {
            halQueue.sync {
                self.updateRetries([:])
                self.cancelInventoryRecovery()
                self.syncDeviceListeners(.stopped)
            }
            syncSystemListeners(wanted: false)
            return
        }
        // Any sweep still in flight loses its right to publish, and this one
        // runs behind it on the same serial queue.
        applyGeneration += 1
        let generation = applyGeneration
        applyInFlight = false
        reapplyPending = false
        wantsMute = false
        let request = UUID()
        inputVolumeLock.withLock {
            inputVolumeBlocked = false
            sweepRequest = request
            inputVolumeLifetime = request
        }
        Self.setReleasePending(true)
        guard generation == applyGeneration else { return }
        halQueue.sync {
            self.attemptedRestores.removeAll()
            if mustRestore || self.hasOutstandingClaims {
                _ = self.sweep(muted: false, audioGeneration: self.currentAudioGeneration, request: request)
            }
            self.updateRetries([:])
            self.cancelInventoryRecovery()
            self.syncDeviceListeners(.stopped)
        }
        guard publishActive(false, generation: generation) else { return }
        let stillOwed = hasOutstandingClaims
        isMuted = false
        var nextWarning: Warning? = stillOwed ? .restoreUnconfirmed : nil
        if Self.needsManualCheck { nextWarning = .manualRestore }
        if nextWarning != warning {
            warning = nextWarning
            nextWarning?.showHUD()
        }
        inputVolumeLock.withLock {
            inputVolumeBlocked = false
            inputVolumeLifetime = UUID()
            sweepRequest = inputVolumeLifetime
        }
        syncSystemListeners(wanted: false)
        callbackLock.withLock { callbackQueued = false }
    }

    /// Silently re-asserts the wanted state; used when the set of input
    /// devices, or the default one, changes underneath us. Unmuted, the same
    /// change is the moment a device this app still has to release may have
    /// come back.
    private func reapplyIfNeeded() {
        if applyInFlight {
            reapplyPending = true
            return
        }
        if wantsMute {
            apply(muted: true, announce: false, followingCallApps: true)
        } else if hasOutstandingClaims || Self.releasePending {
            apply(muted: false, announce: false)
        }
    }

    private func callAppOpenings(in inventory: inout InputInventory?, owned: Set<String>,
                                 notices: ControlNotices, read: ControlReader,
                                 readings: inout [InputDevice: InputControls]) -> ControlNotices {
        func openings(_ device: InputDevice, from delivered: ControlNotices) -> ControlNotices {
            guard let previous = quietInputs[device], owned.contains(device.uid) else { return [:] }
            let current = Self.inputControls(device.id, readSwitch: true, read: read)
            readings[device] = current
            guard current.opened(since: previous) else { return [:] }
            return delivered.filter { listener, client in
                guard listener.device == device.id, let registration = deviceListeners[listener],
                      registration.uid == device.uid, registration.lifetime.client == client,
                      registration.lifetime.isCurrent(observationGeneration), listener.wasClosed(in: previous),
                      let value = read(device.id, listener.address) else { return false }
                if listener.selector == kAudioDevicePropertyMute {
                    return current.muteSwitch == 0 && value == 0
                }
                // A driver can notify a small positive residual after reading
                // back zero. Reassert mute without releasing the other inputs.
                return current.gain == .audible && value > Double(MicMuteSupport.residualGainLimit)
            }
        }
        var candidates: [InputDevice: ControlNotices] = [:]
        for device in inventory?.devices ?? [] {
            let found = openings(device, from: notices)
            if !found.isEmpty { candidates[device] = found }
        }
        guard !candidates.isEmpty else { return [:] }
        let captured = Self.devicesCapturedByOtherProcesses()
        // IDs can be reused while the audio server answers. Both the decision
        // and the subsequent writes must address the devices that are here now.
        inventory = Self.inputInventory()
        var confirmed: ControlNotices = [:]
        // Revalidate the same controls that opened before the process query.
        // New deliveries during that query get their own read.
        for device in inventory?.devices ?? [] where captured.contains(device.id) {
            if let found = candidates[device] {
                confirmed.merge(openings(device, from: found)) { current, _ in current }
            }
        }
        return confirmed
    }

    // MARK: - Applying

    /// Hands the sweep to the audio queue and keeps the published state, the
    /// wanted state and the HUD on the main thread, where they belong.
    private func apply(muted requestedMute: Bool, announce: Bool, followingCallApps: Bool = false,
                       newMuteRequest: Bool = false) {
        applyInFlight = true
        reapplyPending = false
        let request = UUID()
        let muted = requestedMute && (newMuteRequest || !Self.releasePending)
        inputVolumeLock.withLock {
            inputVolumeBlocked = muted
            if muted { inputVolumeLifetime = request }
            sweepRequest = request
        }
        wantsMute = muted
        applyGeneration += 1
        let generation = applyGeneration
        if newMuteRequest { UserDefaults.standard.set(request.uuidString, forKey: DefaultsKey.micMuteReleasePending) }
        if !requestedMute { Self.setReleasePending(true) }
        guard applyGeneration == generation else { return }
        let previouslyMuted = isMuted && AppFeature.micMute.isAvailable
        // A reset between the first mute sweep and publication invalidates
        // every device registration, even if the device IDs stay the same.
        if !wantsSystemListeners && (muted || hasOutstandingClaims) { syncSystemListeners(wanted: true) }
        halQueue.async { [weak self] in
            guard let self else { return }
            let connection = self.currentAudioGeneration
            let enforceMute = muted && !Self.releasePending
            if enforceMute && newMuteRequest && self.inputVolumeLock.withLock({ self.sweepRequest == request }) {
                Self.recoverControlRecords()
            }
            if enforceMute || announce { self.attemptedRestores.removeAll() }
            // Subscribe before checking an existing restore record. That
            // check covers installation without another Set on a refusing driver.
            if !enforceMute { self.syncDeviceListeners(.restoring) }
            let keepRetriesIfUnmuteFails = enforceMute && previouslyMuted
            let checkAfterRegistration = enforceMute && self.observedInputs == nil
            var outcome = self.sweep(muted: enforceMute, audioGeneration: connection, request: request,
                                     followingCallApps: followingCallApps,
                                     keepRetriesIfUnmuteFails: keepRetriesIfUnmuteFails)
            let effectiveMute = enforceMute && !outcome.followedCallApp
            // Losing the last input can leave nothing to mute. Its old
            // listeners still need to leave so a returning input is observed.
            let monitorMute = outcome.applied ? effectiveMute : keepRetriesIfUnmuteFails
            if self.syncDeviceListeners(monitorMute ? .muted : .restoring) { outcome.checkNewInputs = true }
            // Before announcing the first mute, establish call-following baselines
            // with listeners in place, or repair any reading invalidated before registration.
            if checkAfterRegistration && effectiveMute && !Self.releasePending,
               !outcome.quietInputs.isEmpty || !Self.readingsStillHold(outcome),
               connection == self.currentAudioGeneration,
               self.inputVolumeLock.withLock({ self.sweepRequest == request }) {
                let checked = self.sweep(muted: true, audioGeneration: connection, request: request)
                outcome.confirmedInputRevision = Self.readingsStillHold(checked) ? checked.confirmedInputRevision : nil
                outcome.failed = checked.failed
                outcome.checkNewInputs = outcome.checkNewInputs || checked.checkNewInputs
            }
            DispatchQueue.main.async { [outcome] in
                self.finish(outcome, muted: effectiveMute, announce: announce,
                            generation: generation, audioGeneration: connection)
            }
        }
    }

    /// Runs on `halQueue`. The record of what this app silenced is read here
    /// and written back here, so every sweep starts from what the one before
    /// it recorded. Two sweeps back to back are the normal case, not the
    /// exception: one headset connecting fires both listeners, and a quick
    /// double press queues two. Read on the main thread when each was asked
    /// for, both would start from the same record; the second would then find
    /// the devices the first had just silenced already quiet and unclaimed,
    /// leave them to "the user", and the unmute would never release them.
    private func sweep(muted requestedMute: Bool, audioGeneration: UInt64, request: UUID,
                       followingCallApps: Bool = false, keepRetriesIfUnmuteFails: Bool = false,
                       canRescan: Bool = true) -> MuteOutcome {
        let serviceRestarted = observationGeneration != audioGeneration
        let defaults = UserDefaults.standard
        let muteRequestID = followingCallApps ? Self.muteRequestID : nil
        let savedVolumes = defaults.dictionary(forKey: DefaultsKey.micMuteSavedVolumes) as? [String: Double]
        let savedChannelVolumes = defaults.dictionary(forKey: DefaultsKey.micMuteSavedChannelVolumes)
            as? [String: [String: Double]]
        let controlRecords = defaults.dictionary(forKey: DefaultsKey.micMuteSavedControls)
        var liveCheckpoints = controlRecords?.compactMapValues(ReleaseCheckpoint.decode) ?? [:]
        let savedControls = controlRecords.map {
            $0.compactMapValues { $0 as? [String: Double] }.merging(liveCheckpoints.mapValues(\.controls)) { _, live in live }
        }
        let savedProtection = defaults.dictionary(forKey: DefaultsKey.micMuteProtectedChannels) as? [String: [UInt32]] ?? [:]
        // Missing means never tracked; an empty list means tracked and
        // owning nothing, and the sweep must keep those two apart.
        let mutedDevices = defaults.stringArray(forKey: DefaultsKey.micMuteMutedDevices)
        let owners = mutedDevices.map(Set.init)
        if serviceRestarted {
            if observationGeneration < callbackLock.withLock({ lastConfirmedReset }) { attemptedRestores.removeAll() }
            quietInputs.removeAll()
            unverifiedWrites.removeAll()
            observedInputs = []
            topologyGaps.removeAll()
            observedDeviceListChange = nil
            updateRetries([:])
            observationGeneration = audioGeneration
            cancelInventoryRecovery()
            inventoryRetryIndex = 0
            missingInputUIDs = Set(deviceListeners.values.map { $0.uid }).union(mutedDevices ?? [])
        }
        let (revision, notices) = callbackLock.withLock {
            let notices = pendingNotices
            pendingNotices.controls.removeAll()
            if requestedMute { pendingNotices.topology.removeAll() }
            return (topologyRevision, notices)
        }
        // A change delivered during enumeration invalidates its IDs too.
        var inventory = Self.inputInventory()
        let renewingListeners = requestedMute && observeTopology(revision: revision, objects: notices.topology)
        var devices: [InputDevice] { inventory?.devices ?? [] }
        let trackControls = requestedMute && defaults.bool(forKey: DefaultsKey.micMuteFollowCallApps)
            && canFollowCallApps(in: audioGeneration)
        var initialClaims = mutedDevices ?? []
        var recoveredControls: [String: [String: Double]] = [:]
        var requiresManualCheck = false
        // Older mute sweeps saved the new input's levels before appending its
        // UID. An active, UID-tracked mute can recover those named records.
        if let owners, defaults.bool(forKey: DefaultsKey.micMuteActive) {
            let captures = Set((savedControls ?? [:]).keys).union((savedVolumes ?? [:]).keys)
                .union((savedChannelVolumes ?? [:]).keys)
            initialClaims += captures.subtracting(owners).sorted()
        }
        for uid in initialClaims {
            if var snapshot = savedControls?[uid] {
                // Earlier migrations could infer bare element 0 from the UID
                // level. A selector-qualified master has its own provenance.
                if snapshot.removeValue(forKey: "0") != nil {
                    if !snapshot.isEmpty { recoveredControls[uid] = snapshot }
                    requiresManualCheck = true
                }
                if snapshot.isEmpty { initialClaims.removeAll { $0 == uid } }
                continue
            }
            let channels = savedChannelVolumes?[uid]
            guard savedVolumes?[uid] != nil || channels != nil else { continue }
            // The UID level was the first readable gain. Those reads could
            // come from a virtual main, a scalar main, or any channel.
            if savedVolumes?[uid] != nil { requiresManualCheck = true }
            let named = channels?.filter { key, level in
                guard let element = UInt32(key), element > 0 else { return false }
                return String(element) == key && (0...1).contains(level)
            } ?? [:]
            if named.count != (channels?.count ?? 0) { requiresManualCheck = true }
            if !named.isEmpty {
                recoveredControls[uid] = named
            } else {
                initialClaims.removeAll { $0 == uid }
            }
        }
        let claimsWithRecords = Set(initialClaims)
        func claimed<Value>(_ records: [String: Value]?) -> [String: Value] {
            guard owners != nil else { return records ?? [:] }
            return records?.filter { claimsWithRecords.contains($0.key) } ?? [:]
        }
        let initialVolumes = claimed(savedVolumes)
        let initialChannelVolumes = claimed(savedChannelVolumes)
        var protectedChannels = claimed(savedProtection)
        var initialControls = claimed(savedControls).merging(recoveredControls) { _, recovered in recovered }
        let pending = Self.pendingLegacyRestore
        // Before 3.2 the default input had no persisted identity. Even the
        // first UID read after an upgrade could already belong to a replacement.
        let unidentified = pending.map { $0.uid == nil }
            ?? (mutedDevices == nil && defaults.bool(forKey: DefaultsKey.micMuteActive))
        if unidentified { requiresManualCheck = true }
        var remaining = unidentified ? nil : pending
        if let uid = remaining?.uid, owners?.contains(uid) == false { remaining = nil }
        if var legacy = remaining, let uid = legacy.uid, let device = devices.first(where: { $0.uid == uid }) {
            let controls = legacy.resolve(on: device.id)
            if Self.inputUID(of: device.id) == uid {
                remaining = legacy.isPending ? legacy : nil
                if !controls.isEmpty {
                    initialControls[uid, default: [:]].merge(controls) { saved, _ in saved }
                }
                if remaining != nil || initialControls[uid] != nil {
                    if !initialClaims.contains(uid) { initialClaims.append(uid) }
                } else {
                    initialClaims.removeAll { $0 == uid }
                }
            }
        }
        var evidence = notices.controls
        var checksLeft = trackControls && followingCallApps && observedInputs?.isEmpty == false ? 3 : 0
        var invalidated = false
        var follow = false
        func sameConnection(_ device: InputDevice) -> Bool {
            // An object ID can be recycled before the device-list notification arrives.
            Self.inputUID(of: device.id) == device.uid && callbackLock.withLock {
                self.audioGeneration == audioGeneration && topologyRevision == revision
            }
        }
        func isCurrent(_ device: InputDevice) -> Bool {
            guard !invalidated, (!requestedMute || follow || !Self.releasePending),
                  sameConnection(device), inputVolumeLock.withLock({ sweepRequest == request })
            else {
                invalidated = true
                return false
            }
            return true
        }
        // Only registrations suspended by our own writes can resume here.
        // A new listener still needs its first silent baseline after installation.
        var suspended: ControlNotices = [:]
        var writeObservers: [InputDevice: Set<UnsafeMutableRawPointer>]?
        var checking = false
        // Caller holds callbackLock. Only deliveries after this reading count.
        func confirmSilence(_ listener: DeviceListener) {
            guard self.audioGeneration == audioGeneration, topologyRevision == revision,
                  listObservationGeneration == audioGeneration, !resetObservationMissing else { return }
            unverifiedWrites[listener] = nil
            guard checking, !unverifiedWrites.keys.contains(where: { $0.device == listener.device }),
                  let token = suspended.removeValue(forKey: listener),
                  callbackBindings[token] == listener else { return }
            confirmedControlClients.insert(token)
        }
        func readForMute(_ device: AudioDeviceID, _ address: AudioObjectPropertyAddress) -> Double? {
            let value = Self.controlValue(of: device, at: address)
            guard (!suspended.isEmpty || !unverifiedWrites.isEmpty), let value else { return value }
            let listener = DeviceListener(device: device, selector: address.mSelector,
                                         scope: address.mScope, element: address.mElement)
            if listener.isClosed(value) && (suspended[listener] != nil || unverifiedWrites[listener] != nil) {
                callbackLock.withLock { confirmSilence(listener) }
            }
            return value
        }
        // Caller holds callbackLock. A master setter may also affect its aliases.
        func suspendControls(on device: AudioDeviceID, keeping quiet: Set<DeviceListener>) {
            confirmedControlClients = confirmedControlClients.filter { token in
                guard let binding = callbackBindings[token] else { return false }
                guard binding.device == device && !quiet.contains(binding) else { return true }
                suspended[binding] = token
                return false
            }
        }
        func didWrite(_ listener: DeviceListener, matchedTarget: Bool) {
            guard !matchedTarget || suspended[listener] != nil || unverifiedWrites[listener] != nil else { return }
            if !matchedTarget, let device = devices.first(where: { $0.id == listener.device }) {
                if writeObservers == nil { writeObservers = installedControlClients() }
                unverifiedWrites[listener] = UnverifiedWrite(uid: device.uid, observers: writeObservers?[device] ?? [])
            }
            callbackLock.withLock {
                if matchedTarget {
                    confirmSilence(listener)
                } else {
                    // A driver can echo an ignored setter through any alias.
                    suspendControls(on: listener.device, keeping: [])
                    pendingNotices.controls = pendingNotices.controls.filter { $0.key.device != listener.device }
                }
            }
        }
        func verifiedQuiet(_ device: InputDevice, _ quiet: InputControls) -> Bool {
            // The aggregate reading can skip a channel switch when the main
            // switch is engaged. Recheck any outstanding address directly.
            for (listener, write) in unverifiedWrites where listener.device == device.id && write.uid == device.uid {
                _ = readForMute(device.id, listener.address)
                if unverifiedWrites[listener] != nil { return false }
            }
            if observedInputs?.contains(device) == true && (quietInputs[device] == nil || !checking) {
                // A recovered input can receive a click while the HAL is
                // still preparing the mute of another input.
                quietInputs[device] = quiet
                confirmQuietControls(revision: revision, adding: device)
            }
            return true
        }
        // One budget covers both detection and the preparation of every HAL
        // write. At the limit enforce mute from a fresh read and re-arm only
        // after silence has been verified.
        func takeLateNotices(beforeWriting control: DeviceListener? = nil,
                             quiet: Set<DeviceListener>? = nil, checking: Bool = true) -> ControlNotices {
            let client = control.flatMap { deviceListeners[$0]?.lifetime.client }
            return callbackLock.withLock {
                // A structural delivery wins over a control delivery even after the UID read.
                if control != nil && (audioGeneration != self.audioGeneration || revision != topologyRevision) {
                    invalidated = true
                    return [:]
                }
                guard checking else { return [:] }
                let late = pendingNotices.controls
                pendingNotices.controls.removeAll()
                if late.isEmpty {
                    // A notification from our setter is not a call's unmute.
                    // A master or switch can also notify its channel aliases.
                    if let control, let quiet {
                        suspendControls(on: control.device, keeping: quiet)
                    }
                    if let control, let client, confirmedControlClients.remove(client) != nil {
                        suspended[control] = client
                    }
                } else if checksLeft == 0 {
                    confirmedControlClients.removeAll()
                }
                return late
            }
        }
        var partial: MuteOutcome?
        var callOpenings: Set<DeviceListener> = []
        var committedCallRelease = false
        var checkpointedRelease = false
        func recordRelease(_ value: Any, for uid: String, releasing id: String? = nil) {
            Self.setControlRecord(value, for: uid, releasing: id)
            checkpointedRelease = true
        }
        func acceptCallRelease() -> String? {
            guard follow && !committedCallRelease, let muteRequestID else { return nil }
            return inputVolumeLock.withLock {
                guard sweepRequest == request else { return nil }
                inputVolumeBlocked = false
                committedCallRelease = true
                return muteRequestID
            }
        }
        func recordReleaseProgress(_ uid: String, _ residual: [String: Double], _ protection: [UInt32]?,
                                   _ unverified: Set<String>, _ wrote: Bool, _ opened: Bool) {
            let released = opened ? acceptCallRelease() : nil
            guard released != nil || wrote || residual != savedControls?[uid] || protection != savedProtection[uid]
                    || unverified != (liveCheckpoints[uid]?.unverified ?? [])
                    || (pending?.uid == uid && remaining != pending) else { return }
            let checkpoint = ReleaseCheckpoint(controls: residual, protectedChannels: protection ?? [],
                                               legacy: remaining?.uid == uid ? remaining : nil,
                                               unverified: unverified.isEmpty ? nil : unverified)
            liveCheckpoints[uid] = unverified.isEmpty ? nil : checkpoint
            recordRelease(checkpoint.storedValue, for: uid, releasing: released)
        }
        var outcome: MuteOutcome
        var persistedControls = savedControls
        var persistedClaims = mutedDevices
        var claimsBeforeCapture = mutedDevices
        func persistClaims(_ owners: [String]?) {
            guard owners != persistedClaims else { return }
            if let owners { defaults.set(owners, forKey: DefaultsKey.micMuteMutedDevices) }
            else { defaults.removeObject(forKey: DefaultsKey.micMuteMutedDevices) }
            persistedClaims = owners
        }
        func persistControls(_ targets: [String: [String: Double]]?, replacingCheckpoint: Bool = false) {
            guard replacingCheckpoint || targets != persistedControls else { return }
            let released = Self.releasedRequestID
            if targets != nil || released != nil {
                var records: [String: Any] = targets ?? [:]
                records[Self.callReleaseKey] = released
                for (uid, var checkpoint) in liveCheckpoints {
                    guard let current = targets?[uid] else { continue }
                    guard let uncertain = checkpoint.unverified?.intersection(current.keys), !uncertain.isEmpty else { continue }
                    checkpoint.unverified = uncertain
                    checkpoint.controls = current
                    records[uid] = checkpoint.storedValue
                }
                defaults.set(records, forKey: DefaultsKey.micMuteSavedControls)
            } else { defaults.removeObject(forKey: DefaultsKey.micMuteSavedControls) }
            persistedControls = targets
        }
        let continuingMute = defaults.bool(forKey: DefaultsKey.micMuteActive)
        func claimCapture(_ device: InputDevice) {
            guard persistedClaims?.contains(device.uid) != true else { return }
            var owners = persistedClaims ?? initialClaims
            if !owners.contains(device.uid) { owners.append(device.uid) }
            persistClaims(owners)
        }
        func captureControls(_ device: InputDevice, _ snapshot: [String: Double]) -> Bool {
            guard persistedControls?[device.uid] != snapshot || persistedClaims?.contains(device.uid) != true else { return true }
            guard isCurrent(device) else { return false }
            // Start tracking before any modern snapshot can reach preferences.
            if persistedClaims == nil {
                var owners = initialClaims
                if let uid = remaining?.uid, !owners.contains(uid) { owners.append(uid) }
                claimsBeforeCapture = owners
                persistClaims(owners)
            }
            var captures = persistedControls ?? [:]
            captures[device.uid] = snapshot
            persistControls(captures)
            // Hot-plugged inputs join an active mute. On first activation a new
            // input joins only after a setter returns a possible change.
            if continuingMute { claimCapture(device) }
            return true
        }
        while true {
            let levels = partial?.savedVolumes ?? initialVolumes
            let channels = partial?.savedChannelVolumes ?? initialChannelVolumes
            var controls = partial?.savedControls ?? initialControls
            var claims = partial?.mutedDevices ?? initialClaims
            checking = checksLeft > 0
            var readings: [InputDevice: InputControls] = [:]
            if checking {
                checksLeft -= 1
                let opened = callAppOpenings(in: &inventory, owned: Set(mutedDevices ?? []), notices: evidence, read: readForMute,
                                             readings: &readings)
                evidence = takeLateNotices()
                if !evidence.isEmpty {
                    evidence.merge(opened) { delivered, _ in delivered }
                    continue
                }
                follow = !opened.isEmpty && defaults.bool(forKey: DefaultsKey.micMuteFollowCallApps)
                    && inputVolumeLock.withLock { sweepRequest == request }
                    && canFollowCallApps(in: audioGeneration, revision: revision)
                if follow { callOpenings = Set(opened.keys) }
            }
            // Call detection may refresh the inventory. Resolve the old
            // records against the devices present before either path writes.
            for device in devices where claims.contains(device.uid) {
                if let stereo = Self.classifyLegacyChannels(controls[device.uid], on: device.id) {
                    guard isCurrent(device) else { break }
                    controls[device.uid] = stereo.controls
                    if stereo.needsManualCheck { requiresManualCheck = true }
                    continue
                }
                // v3.4.3 could record only a UID after closing its master
                // switch. A gain cannot verify that switch's release.
                guard device.uid != remaining?.uid, controls[device.uid] == nil,
                      levels[device.uid] == nil, channels[device.uid] == nil else { continue }
                let native = Self.legacySwitchSnapshot(device)
                guard isCurrent(device) else { break }
                if let native {
                    controls[device.uid] = native
                } else {
                    claims.removeAll { $0 == device.uid }
                    requiresManualCheck = true
                }
            }
            // Keep the reminder before a verified release can retire its legacy evidence.
            if requiresManualCheck && defaults.object(forKey: DefaultsKey.micMuteManualCheckNeeded) as? Bool != true {
                defaults.set(true, forKey: DefaultsKey.micMuteManualCheckNeeded)
            }
            if !requestedMute || follow {
                // Known controls can be released even while another legacy
                // reading is pending. Never run a fallback for that unknown.
                let targets = remaining.map { pending in
                    devices.filter { $0.uid != pending.uid || controls[$0.uid] != nil }
                } ?? devices
                if let inventory {
                    // A global list echo can renew subscriptions on the same
                    // input. Only confirmed removal retires its write budget.
                    let connected = Set(inventory.devices)
                    attemptedRestores = attemptedRestores.filter { connected.contains($0.key) || inventory.unresolvedIDs.contains($0.key.id) }
                }
                outcome = Self.unmute(targets, savedVolumes: levels, savedChannelVolumes: channels, savedControls: controls,
                                      mutedDevices: claims, protectedChannels: &protectedChannels, attempts: &attemptedRestores,
                                      now: uptime(), callOpenings: callOpenings,
                                      unverifiedControls: liveCheckpoints.compactMapValues(\.unverified),
                                      willWrite: { recordRelease(Self.changingControls, for: $0) },
                                      didCheck: recordReleaseProgress,
                                      isCurrent: isCurrent, canVerify: sameConnection)
                if follow && !outcome.applied && inputVolumeLock.withLock({ sweepRequest == request }) {
                    // A rejected automatic release keeps mute active. A
                    // pending reapply still needs the complete pre-mute mix.
                    outcome.savedControls.merge(controls) { _, original in original }
                }
                outcome.followedCallApp = follow
                break
            }
            let authorize = MuteAuthorization(isCurrent: isCurrent, capture: captureControls, claim: claimCapture, beforeWrite: { listener, quiet in
                evidence = takeLateNotices(beforeWriting: listener, quiet: quiet, checking: checking)
                return !invalidated && evidence.isEmpty
            }, didWrite: didWrite, verifiedQuiet: verifiedQuiet)
            // Modern setters can move aliases on the same mic. Wait until
            // its legacy readings are resolved before making those writes.
            let targets = devices.filter { $0.uid != remaining?.uid }
            outcome = Self.mute(targets, retries: partial?.retries ?? retries, now: uptime(), savedVolumes: levels,
                                savedChannelVolumes: channels, savedControls: controls, mutedDevices: claims,
                                trackControls: trackControls, readings: readings,
                                read: readForMute, authorize: authorize)
            if invalidated {
                // The queued request must enumerate the new connection before
                // applying a saved level or closing another control.
                partial = outcome
                break
            }
            if !checking { break }
            // A control read as quiet needs no setter. A click delivered after
            // that read still belongs to the existing baseline until publication.
            if evidence.isEmpty { evidence = takeLateNotices() }
            if evidence.isEmpty { break }
            partial = outcome
        }
        let muted = requestedMute && !follow
        outcome.requiresManualLegacyRestore = requiresManualCheck
        if let uid = remaining?.uid {
            if !outcome.mutedDevices.contains(uid) { outcome.mutedDevices.append(uid) }
            outcome.failed = true
            if muted { outcome.applied = true }
        }
        if muted {
            if !outcome.failed, let inventory, !Self.coversInventory(inventory, confirmed: outcome.confirmedInputs) {
                outcome.failed = true
            }
            if outcome.applied && !outcome.failed && inventory?.unresolvedIDs.isEmpty == true {
                outcome.confirmedInputRevision = revision
            }
            // A control can open between the mute and its listener's installation
            // or renewal. Recheck once after subscribing to cover that interval.
            outcome.checkNewInputs = renewingListeners
            quietInputs = outcome.quietInputs.filter { observedInputs?.contains($0.key) == true }
        } else {
            if outcome.applied || !keepRetriesIfUnmuteFails {
                quietInputs.removeAll()
                unverifiedWrites.removeAll()
                observedInputs = nil
                observedDeviceListChange = nil
            } else {
                // A refused restore can still release a switch or change one
                // channel. Check what remains closed before showing active mute.
                var confirmedInputs: Set<InputDevice> = []
                quietInputs = devices.reduce(into: [:]) { result, device in
                    let current = Self.inputControls(device.id, readSwitch: true)
                    if current.isSilenced {
                        confirmedInputs.insert(device)
                        if quietInputs[device] != nil { result[device] = current }
                    }
                }
                if let inventory, !devices.isEmpty, inventory.unresolvedIDs.isEmpty,
                   Self.coversInventory(inventory, confirmed: confirmedInputs) {
                    outcome.confirmedInputRevision = revision
                }
            }
        }
        // A sweep that reached nothing leaves the record alone: it is what a
        // later unmute needs to put every level back. A record that did not
        // change is not written again: every write tells the whole app that
        // preferences changed, and a re-assert usually changes nothing.
        // An automatic release interrupted by a reset must not discard the
        // saved levels needed to reassert the user's original mute.
        if outcome.applied && !invalidated && audioGeneration == currentAudioGeneration, let id = acceptCallRelease() {
            recordRelease(id, for: Self.callReleaseKey)
        }
        let releaseInterrupted = follow && !committedCallRelease && !outcome.applied
            && (invalidated || audioGeneration != currentAudioGeneration) && inputVolumeLock.withLock({ sweepRequest == request })
        var record = partial
        let restoredControls = !muted && (outcome.savedControls != (savedControls ?? [:]) || protectedChannels != savedProtection)
        let migrationChanged = remaining != pending || requiresManualCheck
        if !releaseInterrupted && (outcome.applied || partial != nil || migrationChanged || restoredControls) {
            record = outcome
        }
        if let record {
            if let submitted = persistedClaims, submitted != claimsBeforeCapture {
                // Retire rejected captures before deleting their exact snapshot.
                // A bare UID was the old format for a native switch we closed.
                let keep = Set(record.mutedDevices).union(claimsBeforeCapture ?? [])
                persistClaims(submitted.filter { keep.contains($0) })
            }
            if !releaseInterrupted && protectedChannels != savedProtection {
                defaults.set(protectedChannels, forKey: DefaultsKey.micMuteProtectedChannels)
            }
            if !checkpointedRelease {
                persistControls(record.savedControls)
            }
            if remaining != pending {
                if let remaining {
                    if let data = try? JSONEncoder().encode(remaining) {
                        defaults.set(data, forKey: DefaultsKey.micMutePendingLegacyControls)
                    }
                } else {
                    defaults.removeObject(forKey: DefaultsKey.micMutePendingLegacyControls)
                }
            }
            persistClaims(record.mutedDevices)
            // Retire a UID before clearing the old gain maps. A UID alone
            // was also the on-disk record of a successful native switch mute.
            if savedVolumes != record.savedVolumes {
                defaults.set(record.savedVolumes, forKey: DefaultsKey.micMuteSavedVolumes)
            }
            if savedChannelVolumes != record.savedChannelVolumes {
                defaults.set(record.savedChannelVolumes, forKey: DefaultsKey.micMuteSavedChannelVolumes)
            }
            // The global level has no UID. Future devices must only use
            // their own saved controls and levels.
            if defaults.object(forKey: DefaultsKey.micMuteSavedVolume) != nil {
                defaults.removeObject(forKey: DefaultsKey.micMuteSavedVolume)
            }
            // Keep each UID's checkpoint until every map that could reconstruct its old claim is settled.
            if checkpointedRelease { persistControls(record.savedControls, replacingCheckpoint: true) }
        } else {
            // A completely rejected or superseded setter leaves no new claim.
            persistClaims(claimsBeforeCapture)
            persistControls(savedControls, replacingCheckpoint: checkpointedRelease)
        }
        // The old UID's snapshot is durable before the replacement is enumerated.
        // Limit this immediate retry even when a driver keeps changing its identity.
        if invalidated, canRescan, audioGeneration == currentAudioGeneration,
           inputVolumeLock.withLock({ sweepRequest == request }) {
            if requestedMute && !follow { updateRetries(outcome.retries) }
            var fresh = sweep(muted: requestedMute && !committedCallRelease && !Self.releasePending,
                              audioGeneration: audioGeneration, request: request,
                              followingCallApps: followingCallApps,
                              keepRetriesIfUnmuteFails: keepRetriesIfUnmuteFails, canRescan: false)
            if committedCallRelease {
                fresh.followedCallApp = true
                fresh.applied = true
            } else if !follow && !fresh.followedCallApp && outcome.applied {
                fresh.applied = true
            }
            return fresh
        }
        if releaseInterrupted {
            outcome.followedCallApp = false
            return outcome
        }
        // Only a wholly rejected call release can retain the active mute's retry.
        if muted || outcome.applied || !keepRetriesIfUnmuteFails {
            updateRetries(outcome.applied || keepRetriesIfUnmuteFails ? outcome.retries : [:],
                          restoreDeadline: outcome.restoreRetryDeadline)
        } else if follow {
            // A retry may have fired to discover this opening. Reassert the
            // still-active mute and let the refusing driver resume its backoff.
            scheduleReapply()
        }
        if audioGeneration == currentAudioGeneration {
            updateInventoryRecovery(inventory, wanted: muted || !outcome.mutedDevices.isEmpty,
                                    generation: audioGeneration)
        }
        return outcome
    }

    private func updateInventoryRecovery(_ inventory: InputInventory?, wanted: Bool, generation: UInt64) {
        guard let index = inventoryRetryIndex else { return }
        if let inventory {
            missingInputUIDs.subtract(inventory.devices.map(\.uid))
            if !inventory.devices.isEmpty && inventory.unresolvedIDs.isEmpty && missingInputUIDs.isEmpty {
                cancelInventoryRecovery()
                return
            }
        }
        guard wanted else {
            cancelInventoryRecovery()
            return
        }
        guard inventoryRetryWork == nil else { return }
        guard index < Self.recoveryDelays.count else {
            cancelInventoryRecovery()
            return
        }
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.inventoryRetryWork = nil
            if self.currentAudioGeneration == generation { self.scheduleReapply() }
        }
        inventoryRetryIndex = index + 1
        inventoryRetryWork = work
        halQueue.asyncAfter(deadline: .now() + Self.recoveryDelays[index], execute: work)
    }

    private func cancelInventoryRecovery() {
        inventoryRetryWork?.cancel()
        inventoryRetryWork = nil
        inventoryRetryIndex = nil
        missingInputUIDs.removeAll()
    }

    /// A driver may become writable without another notification. Retry on
    /// the audio queue, keeping a single timer for the earliest due device.
    private func updateRetries(_ updated: ControlRetries, restoreDeadline: TimeInterval? = nil) {
        retries = updated
        let next = restoreDeadline ?? updated.values.compactMap { $0.values.compactMap(\.scheduledDeadline).min() }.min()
        guard next != retryDeadline else { return }
        retryWork?.cancel()
        retryWork = nil
        retryDeadline = next
        guard let next else { return }
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.retryDeadline = nil
            self.retryWork = nil
            self.scheduleReapply()
        }
        retryWork = work
        halQueue.asyncAfter(deadline: .now() + max(0, next - uptime()), execute: work)
    }

    /// Main thread. Publishes one sweep.
    private func finish(_ outcome: MuteOutcome, muted: Bool, announce: Bool, generation: Int,
                        audioGeneration: UInt64) {
        guard generation == applyGeneration else { return }
        if muted && Self.releasePending {
            apply(muted: false, announce: announce)
            return
        }
        if audioGeneration != currentAudioGeneration {
            // Publish a manual request that already reached the hardware, or
            // a call unmute that already restored it. Recheck with this intent
            // even if the restarted server temporarily lists no inputs.
            guard outcome.applied && (announce || outcome.followedCallApp) else {
                apply(muted: wantsMute, announce: announce)
                return
            }
            reapplyPending = true
        }
        applyInFlight = false
        // A listener cannot supersede a manual action or swallow its warning.
        // Publish the result first, then recheck the latest desired state.
        defer {
            if generation == applyGeneration && (reapplyPending || outcome.checkNewInputs) {
                reapplyPending = false
                reapplyIfNeeded()
            }
        }
        let controlsConfirmed = callbackLock.withLock {
            audioGeneration == self.audioGeneration && outcome.confirmedInputRevision == topologyRevision
        }
        let failure = outcome.failed || (muted && !controlsConfirmed)
        if outcome.applied || (!muted && !outcome.followedCallApp) {
            wantsMute = muted
            inputVolumeLock.withLock { inputVolumeBlocked = muted }
            if isMuted != muted { isMuted = muted }
            guard publishActive(muted, generation: generation) else { return }
            if outcome.followedCallApp {
                halQueue.async { Self.setControlRecord(nil, for: Self.callReleaseKey) }
            }
            syncListeners()
        } else {
            // A failed reassertion or rejected call release keeps the published mute.
            wantsMute = isMuted
            inputVolumeLock.withLock { inputVolumeBlocked = isMuted }
            if !isMuted {
                guard publishActive(false, generation: generation) else { return }
                if hasOutstandingClaims { reapplyPending = true }
                else { syncSystemListeners(wanted: false) }
            }
        }
        let nextWarning: Warning?
        if isMuted {
            nextWarning = controlsConfirmed ? nil : .muteUnconfirmed
        } else if outcome.requiresManualLegacyRestore || Self.needsManualCheck {
            nextWarning = .manualRestore
        } else if outcome.restoreAttemptsExhausted {
            nextWarning = .restoreExhausted
        } else if (!muted && outcome.failed) || hasOutstandingClaims {
            nextWarning = .restoreUnconfirmed
        } else {
            nextWarning = nil
        }
        let changedWarning = warning != nextWarning
        if changedWarning { warning = nextWarning }
        if (changedWarning && warning != nil) || (failure && (announce || outcome.followedCallApp)) {
            NotchService.shared.retractMicrophoneNotice()
        }
        let manualNotice = warning == .manualRestore || warning == .restoreExhausted ? warning : nil
        guard announce || outcome.followedCallApp || (changedWarning && manualNotice != nil) else { return }
        // Report a known failure even when no device could be changed. The
        // whole sentence matters, and it is longer than the island's wings.
        if failure || warning != nil {
            let notice: Warning = muted ? .muteUnconfirmed : (manualNotice ?? .restoreUnconfirmed)
            notice.showHUD()
            return
        }
        guard outcome.applied else { return }
        // With Dynamic Island on, the switch reports there like the volume,
        // and the companion hushes or perks up, in its notice or where it is.
        let shownInIsland = NotchService.shared.showMicrophone(muted: muted)
        NotchService.shared.reactMascot(muted ? .hush : .perk)
        guard !shownInIsland else { return }
        QuickToolHUD.show(icon: muted ? "mic.slash.fill" : "mic.fill",
                          message: muted ? L10n.shared.s.micMutedHUD : L10n.shared.s.micUnmutedHUD)
    }

    // MARK: - CoreAudio

    private struct InputDevice: Hashable {
        let id: AudioDeviceID
        let uid: String
    }

    private struct MuteOutcome {
        var applied: Bool
        var savedVolumes: [String: Double]
        /// Channel levels by device and element, so an unmute puts back the
        /// balance between channels instead of one level everywhere.
        var savedChannelVolumes: [String: [String: Double]]
        /// Exact values of the controls this app may have changed. Zero gain
        /// and an existing mute are user choices, not missing restore data.
        /// Bare legacy stereo elements await classification before any write.
        var savedControls: [String: [String: Double]]
        var mutedDevices: [String]
        /// A device this sweep had to reach and could not, next to ones it did.
        var failed = false
        var requiresManualLegacyRestore = false
        var restoreRetryDeadline: TimeInterval?
        var restoreAttemptsExhausted = false
        var confirmedInputs: Set<InputDevice> = []
        /// A mute reading is valid only for the topology it covered.
        var confirmedInputRevision: UInt64?
        var followedCallApp = false
        var checkNewInputs = false
        var quietInputs: [InputDevice: InputControls] = [:]
        var retries: ControlRetries = [:]
    }

    private struct DeviceListener: Hashable {
        let device: AudioDeviceID
        let selector: AudioObjectPropertySelector
        let scope: AudioObjectPropertyScope
        let element: AudioObjectPropertyElement

        func matches(_ address: AudioObjectPropertyAddress) -> Bool {
            selector == address.mSelector && scope == address.mScope && element == address.mElement
        }

        func isClosed(_ value: Double) -> Bool {
            selector == kAudioDevicePropertyMute ? value == 1 : value == 0
        }

        func wasClosed(in controls: InputControls) -> Bool {
            if selector == kAudioDevicePropertyMute { return controls.mutedElements.contains(element) }
            return controls.silentGains.contains(MicMuteService.controlKey(address))
        }

        var address: AudioObjectPropertyAddress {
            AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: element)
        }
    }

    private struct MuteAuthorization {
        let isCurrent: (InputDevice) -> Bool
        let capture: (InputDevice, [String: Double]) -> Bool
        let claim: (InputDevice) -> Void
        let beforeWrite: (DeviceListener, Set<DeviceListener>?) -> Bool
        let didWrite: (DeviceListener, Bool) -> Void
        let verifiedQuiet: (InputDevice, InputControls) -> Bool
    }

    private static func mute(_ devices: [InputDevice],
                             retries: ControlRetries, now: TimeInterval,
                             savedVolumes: [String: Double],
                             savedChannelVolumes: [String: [String: Double]],
                             savedControls: [String: [String: Double]],
                             mutedDevices: [String]?,
                             trackControls: Bool,
                             readings: [InputDevice: InputControls],
                             read: ControlReader, authorize: MuteAuthorization) -> MuteOutcome {
        var outcome = MuteOutcome(applied: false,
                                  savedVolumes: savedVolumes,
                                  savedChannelVolumes: savedChannelVolumes,
                                  savedControls: savedControls,
                                  mutedDevices: MicMuteSupport.absentClaims(recorded: mutedDevices,
                                                                            present: devices.map(\.uid)))
        let owned = Set(mutedDevices ?? [])
        for (index, device) in devices.enumerated() {
            let previousRetries = retries[device] ?? [:]
            let initial = readings[device] ?? inputControls(device.id, readSwitch: trackControls, read: read)
            let silenced = initial.isSilenced
            if silenced { outcome.confirmedInputs.insert(device) }
            // Already quiet and not ours: a microphone the user muted
            // themselves is left alone, so unmuting later never opens
            // something this app did not close.
            if MicMuteSupport.shouldLeaveUntouched(owned: owned.contains(device.uid),
                                                   captureSilenced: silenced) {
                outcome.applied = true
                continue
            }
            if silenced {
                // A correcting Set may read zero twice before its delayed
                // rebound. Keep the burst history across those quiet reads.
                let recent = previousRetries.compactMapValues { $0.observingZero(now: now) }
                if !recent.isEmpty { outcome.retries[device] = recent }
                if trackControls && authorize.verifiedQuiet(device, initial) { outcome.quietInputs[device] = initial }
                outcome.applied = true
                outcome.mutedDevices.append(device.uid)
                continue
            }
            // Another microphone's gain change must not keep writing an
            // unresponsive control during its cooldown.
            let idleVirtual = isVirtualInput(device) && isIdleInput(device.id)
            let volume = inputVolume(of: device.id, read: read)
            let channels = channelVolumes(of: device.id, read: read)
            // Snapshot every writable control before any write: a virtual
            // main volume can also change its channel controls. Reapplying
            // keeps the first snapshot, including a user's mute or zero gain.
            let addresses = muteAddresses(of: device.id) + volumeAddresses(of: device.id)
            var snapshot = savedControls[device.uid] ?? [:]
            var writable: [AudioObjectPropertyAddress] = []
            var nextRetries: [String: MicMuteSupport.Retry] = [:]
            var quietBeforeWrite: Set<DeviceListener>? = readings[device] == nil ? nil : []
            for var address in addresses {
                var settable = DarwinBoolean(false)
                guard AudioObjectHasProperty(device.id, &address) else { continue }
                let canWrite = AudioObjectIsPropertySettable(device.id, &address, &settable) == noErr && settable.boolValue
                let key = controlKey(address)
                guard canWrite || quietBeforeWrite != nil, let current = read(device.id, address) else {
                    nextRetries[key] = previousRetries[key]?.waitingForReadableControl(now: now)
                    continue
                }
                let closed = address.mSelector == kAudioDevicePropertyMute ? current == 1 : current == 0
                if closed {
                    quietBeforeWrite?.insert(DeviceListener(device: device.id, selector: address.mSelector,
                                                            scope: address.mScope, element: address.mElement))
                    nextRetries[key] = previousRetries[key]?.observingZero(now: now)
                }
                guard canWrite else {
                    if !closed { nextRetries[key] = previousRetries[key]?.waitingForReadableControl(now: now) }
                    continue
                }
                if snapshot[key] == nil {
                    snapshot[key] = current
                }
                if !closed, let retry = previousRetries[key], retry.defers(current, idle: idleVirtual, now: now) {
                    nextRetries[key] = retry.observingOpen()
                } else {
                    writable.append(address)
                }
            }
            func recordClaim() {
                outcome.applied = true
                outcome.mutedDevices.append(device.uid)
                if MicMuteSupport.shouldReplaceSavedVolume(existing: outcome.savedVolumes[device.uid], current: volume),
                   let volume { outcome.savedVolumes[device.uid] = Double(volume) }
                if outcome.savedChannelVolumes[device.uid] == nil, !channels.isEmpty {
                    outcome.savedChannelVolumes[device.uid] = channels
                }
                if !snapshot.isEmpty { outcome.savedControls[device.uid] = snapshot }
            }
            var changed = false
            var captured = false
            var submitted: [String: (address: AudioObjectPropertyAddress, correctedSmallGain: Bool)] = [:]
            for address in writable {
                let target: Double = address.mSelector == kAudioDevicePropertyMute ? 1 : 0
                switch writeControl(target, of: device, at: address, isCurrent: authorize.isCurrent,
                                    prepare: {
                                        if !captured { captured = authorize.capture(device, snapshot) }
                                        return captured ? nil : .interrupted
                                    },
                                    quietBeforeWrite: quietBeforeWrite, read: read, authorize: authorize) {
                case .submitted(let possiblyChanged, let correctedSmallGain):
                    if possiblyChanged && !changed { authorize.claim(device) }
                    changed = changed || possiblyChanged
                    submitted[controlKey(address)] = (address, correctedSmallGain)
                    quietBeforeWrite = nil
                case .unchanged, .unavailable, .unclassifiedChannels: break
                case .interrupted:
                    // Earlier writes may already have changed this input or
                    // its aliases. Keep their original snapshot, along with
                    // claims and retries that this pass has not reached.
                    if changed { recordClaim() }
                    let recorded = Set(outcome.mutedDevices)
                    outcome.mutedDevices += (mutedDevices ?? []).filter { !recorded.contains($0) }
                    for remaining in devices[index...] { outcome.retries[remaining] = retries[remaining] }
                    return outcome
                }
            }
            // A driver may report the target to the setter and revert while
            // the other channels are being written. Use each address's final
            // reading for its retry, including addresses the device-level
            // check skips after finding a live channel or a master switch.
            var verifiedControls: [String: Bool] = [:]
            func verify(_ id: AudioDeviceID, _ address: AudioObjectPropertyAddress) -> Double? {
                let value = read(id, address)
                verifiedControls[controlKey(address)] = value == (address.mSelector == kAudioDevicePropertyMute ? 1 : 0)
                return value
            }
            let verified = inputControls(device.id, readSwitch: trackControls, read: verify)
            let quiet = verified.isSilenced
            if quiet { outcome.confirmedInputs.insert(device) }
            if changed || owned.contains(device.uid) {
                // A partially applied mute still owes its changes back.
                // Keep it operable and report the partial result, rather than
                // abandoning the microphone after one control refused a write.
                recordClaim()
                if quiet && trackControls && authorize.verifiedQuiet(device, verified) { outcome.quietInputs[device] = verified }
                if !quiet { outcome.failed = true }
            } else {
                if quiet { outcome.applied = true }
                outcome.savedVolumes.removeValue(forKey: device.uid)
                outcome.savedChannelVolumes.removeValue(forKey: device.uid)
                outcome.savedControls.removeValue(forKey: device.uid)
            }
            for (key, attempt) in submitted {
                if verifiedControls[key] == nil { _ = verify(device.id, attempt.address) }
                let reason: MicMuteSupport.Retry.Reason
                if verifiedControls[key] != true && !quiet {
                    reason = .unconfirmed
                } else if attempt.correctedSmallGain {
                    reason = .smallRebound
                } else if idleVirtual && quiet {
                    reason = .idleVirtual
                } else {
                    nextRetries[key] = nil
                    continue
                }
                nextRetries[key] = MicMuteSupport.Retry(reason: reason, smallGain: attempt.correctedSmallGain,
                                                       idleVirtual: idleVirtual, previous: previousRetries[key], now: now)
            }
            if !nextRetries.isEmpty { outcome.retries[device] = nextRetries }
        }
        return outcome
    }

    private static func unmute(_ devices: [InputDevice],
                               savedVolumes: [String: Double],
                               savedChannelVolumes: [String: [String: Double]],
                               savedControls: [String: [String: Double]],
                               mutedDevices: [String], protectedChannels: inout [String: [UInt32]],
                               attempts: inout [InputDevice: [String: RestoreAttempt]], now: TimeInterval,
                               callOpenings: Set<DeviceListener>, unverifiedControls: [String: Set<String>],
                               willWrite: (String) -> Void,
                               didCheck: (String, [String: Double], [UInt32]?, Set<String>, Bool, Bool) -> Void,
                               isCurrent: (InputDevice) -> Bool, canVerify: (InputDevice) -> Bool) -> MuteOutcome {
        let present = devices.map(\.uid)
        var outcome = MuteOutcome(applied: false,
                                  savedVolumes: savedVolumes,
                                  savedChannelVolumes: savedChannelVolumes,
                                  savedControls: savedControls,
                                  mutedDevices: MicMuteSupport.absentClaims(recorded: mutedDevices,
                                                                            present: present))
        let targets = Set(MicMuteSupport.restoreTargets(recorded: mutedDevices, present: present))
        attempts = attempts.filter { mutedDevices.contains($0.key.uid) }
        var attempted = false
        for device in devices where targets.contains(device.uid) {
            guard let saved = savedControls[device.uid] else {
                // A reset interrupted migration before this UID was resolved.
                outcome.mutedDevices.append(device.uid)
                continue
            }
            var channels = Set(protectedChannels[device.uid] ?? [])
            attempted = true
            var openings = Set(callOpenings.filter { $0.device == device.id }.map { controlKey($0.address) })
            var attemptedTargets = attempts[device] ?? [:]
            var writing = false
            var unverified = unverifiedControls[device.uid] ?? []
            func markBeforeFirstWrite() {
                guard !writing else { return }
                willWrite(device.uid)
                writing = true
            }
            let (outstanding, sameInput) = restoreControls(
                saved, on: device, protecting: &channels, openings: &openings, unverified: &unverified,
                attempts: &attemptedTargets, now: now, recordedLevels: savedChannelVolumes[device.uid],
                willWrite: markBeforeFirstWrite, isCurrent: isCurrent, canVerify: canVerify)
            attemptedTargets = attemptedTargets.filter { outstanding[$0.key] == $0.value.target }
            attempts[device] = attemptedTargets.isEmpty ? nil : attemptedTargets
            for attempt in attemptedTargets.values {
                if let deadline = attempt.deadline {
                    // If a due setter couldn't run (e.g. a missing sibling),
                    // its next topology event can retry without a timer loop.
                    if deadline > now {
                        outcome.restoreRetryDeadline = min(outcome.restoreRetryDeadline ?? deadline, deadline)
                    }
                } else {
                    outcome.restoreAttemptsExhausted = true
                }
            }
            let needsMaster = outstanding["0"] != nil || outstanding.keys.compactMap(controlAddress).contains(where: isMasterGain)
            protectedChannels[device.uid] = needsMaster && !channels.isEmpty ? channels.sorted() : nil
            let complete = outstanding.isEmpty && sameInput
            // One verified open control is progress even if another is still owed.
            let opened = complete || openings.contains { key in
                guard outstanding[key] == nil, let target = saved[key], let address = controlAddress(key) else { return false }
                return address.mSelector == kAudioDevicePropertyMute ? target == 0 : target > 0
            }
            if sameInput || writing {
                didCheck(device.uid, outstanding, protectedChannels[device.uid], unverified, writing, opened)
            }
            if opened { outcome.applied = true }
            if complete {
                outcome.savedControls.removeValue(forKey: device.uid)
                outcome.savedVolumes.removeValue(forKey: device.uid)
                outcome.savedChannelVolumes.removeValue(forKey: device.uid)
            } else {
                outcome.failed = true
                outcome.mutedDevices.append(device.uid)
                outcome.savedControls[device.uid] = outstanding
            }
        }
        // Nothing left silenced is a finished unmute; the user must never be
        // left holding a mute the app refuses to release.
        if !attempted { outcome.applied = true }
        return outcome
    }

    private static func inputControls(_ device: AudioDeviceID, readSwitch: Bool = false,
                                      read: ControlReader = MicMuteService.controlValue) -> InputControls {
        var gain: InputControls.Gain = .unavailable
        var silentGains: Set<String> = []
        var zeroElements: Set<UInt32> = []
        let count = readInputChannelCount(of: device)
        let addresses = volumeAddresses(of: device, channelCount: count ?? MicMuteSupport.minimumChannelCount)
        for var address in addresses where AudioObjectHasProperty(device, &address) {
            guard let value = read(device, address) else {
                gain = .unreadable
                continue
            }
            if !MicMuteSupport.isCaptureSilenced(muteSwitch: nil, volume: Float(value)) {
                gain = .audible
                break
            }
            if gain == .unavailable { gain = .silent }
            zeroElements.insert(address.mElement)
            if readSwitch { silentGains.insert(controlKey(address)) }
        }
        // A layout read failure can hide contradictory channel gains even
        // when the master reads zero. Keep trying the known controls.
        if (count ?? 0) == 0 && gain != .audible { gain = .unreadable }
        // A channel gain reaches only its own channel. A missing gain can
        // be covered by its native switch, but an exposed gain must read zero.
        var uncovered: Set<UInt32> = []
        if gain == .silent, !zeroElements.contains(kAudioObjectPropertyElementMain), let count, count > 0 {
            uncovered = Set(1...UInt32(count)).subtracting(zeroElements)
        }
        let muteSwitch = readSwitch || gain == .unavailable || !uncovered.isEmpty
            ? readMuteSwitch(of: device, channelCount: count, read: read) : nil
        let engaged = muteSwitch?.mutedElements ?? []
        if muteSwitch?.value != 1 && !uncovered.isSubset(of: engaged) {
            gain = .unreadable
        }
        let mutedElements = muteSwitch?.value == 1 ? engaged : uncovered.intersection(engaged)
        return InputControls(gain: gain, muteSwitch: muteSwitch?.value, silentGains: silentGains,
                             mutedElements: mutedElements)
    }

    private static func isVirtualInput(_ device: InputDevice) -> Bool {
        // This is the loopback UID from the Teams report. Other drivers must
        // identify their transport as virtual for the idle-device cooldown.
        if device.uid == "MSLoopbackDriverDevice_UID" { return true }
        var transport: UInt32 = 0
        return read(device.id, kAudioDevicePropertyTransportType, &transport)
            && transport == kAudioDeviceTransportTypeVirtual
    }

    private static func isIdleInput(_ device: AudioDeviceID) -> Bool {
        var running: UInt32 = 0
        return read(device, kAudioDevicePropertyDeviceIsRunningSomewhere, &running) && running == 0
    }

    /// Recheck the same inputs and any aggregate that depended on them.
    private static func readingsStillHold(_ outcome: MuteOutcome) -> Bool {
        guard !outcome.confirmedInputs.isEmpty else { return true }
        guard let inventory = inputInventory(), outcome.confirmedInputs.isSubset(of: inventory.devices),
              outcome.confirmedInputs.allSatisfy({ inputControls($0.id).isSilenced }) else { return false }
        return outcome.confirmedInputRevision == nil
            || (inventory.unresolvedIDs.isEmpty && coversInventory(inventory, confirmed: outcome.confirmedInputs))
    }

    /// A control-less aggregate can report coverage only through active input
    /// members accounted for in this sweep. Resolve nested aggregates from the
    /// inside out; missing members and cycles cannot establish coverage.
    private static func coversInventory(_ inventory: InputInventory, confirmed: Set<InputDevice>) -> Bool {
        var covered = confirmed
        var pending = Set(inventory.devices).subtracting(covered)
        while !pending.isEmpty {
            let resolved = pending.filter { aggregate($0.id, isCoveredBy: covered, inactiveIDs: inventory.inactiveIDs) }
            guard !resolved.isEmpty else { return false }
            pending.subtract(resolved)
            covered.formUnion(resolved)
        }
        return true
    }

    private static func aggregate(_ device: AudioDeviceID, isCoveredBy inputs: Set<InputDevice>,
                                  inactiveIDs: Set<AudioDeviceID>) -> Bool {
        var transport: UInt32 = 0
        guard read(device, kAudioDevicePropertyTransportType, &transport), transport == kAudioDeviceTransportTypeAggregate,
              let count = readInputChannelCount(of: device), count > 0 else { return false }
        for var address in muteAddresses(of: device, channelCount: count) + volumeAddresses(of: device, channelCount: count) {
            if AudioObjectHasProperty(device, &address) { return false }
        }
        let members = objectIDs(of: device, selector: kAudioAggregateDevicePropertyActiveSubDeviceList,
                                scope: kAudioObjectPropertyScopeGlobal)
        var channels = 0
        var seen: Set<String> = []
        for member in members {
            // The aggregate's sub-device objects may differ from the live
            // AudioDevices. Their UIDs identify the devices with the streams.
            guard let uid = inputUID(of: member), seen.insert(uid).inserted else { return false }
            if let input = inputs.first(where: { $0.uid == uid }),
               let memberChannels = readInputChannelCount(of: input.id), memberChannels > 0 {
                channels += memberChannels
            } else if !inactiveIDs.contains(where: { inputUID(of: $0) == uid && hasInputStreams($0) == false }) {
                return false
            }
        }
        return channels == count
    }

    private struct InputInventory {
        var devices: [InputDevice] = []
        var unresolvedIDs: Set<AudioDeviceID> = []
        var inactiveIDs: Set<AudioDeviceID> = []
    }

    private static func audioDeviceIDs() -> [AudioDeviceID]? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject),
                                             &address, 0, nil, &size) == noErr else { return nil }
        guard size > 0 else { return [] }
        var deviceIDs = [AudioDeviceID](repeating: 0, count: Int(size) / MemoryLayout<AudioDeviceID>.size)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject),
                                         &address, 0, nil, &size, &deviceIDs) == noErr else { return nil }

        return Array(deviceIDs.prefix(Int(size) / MemoryLayout<AudioDeviceID>.size))
    }

    private static func inputInventory() -> InputInventory? {
        guard let deviceIDs = audioDeviceIDs() else { return nil }
        var inventory = InputInventory()
        for deviceID in deviceIDs {
            guard let hasStreams = hasInputStreams(deviceID) else {
                inventory.unresolvedIDs.insert(deviceID)
                continue
            }
            var isAlive: UInt32 = 1
            if !hasStreams || (read(deviceID, kAudioDevicePropertyDeviceIsAlive, &isAlive) && isAlive == 0) {
                inventory.inactiveIDs.insert(deviceID)
                continue
            }

            guard let uid = inputUID(of: deviceID) else {
                inventory.unresolvedIDs.insert(deviceID)
                continue
            }

            var nameRef: CFString = "" as CFString
            let name = read(deviceID, kAudioObjectPropertyName, &nameRef) ? nameRef as String : uid
            guard !MicMuteSupport.isOwnDevice(name: name) else { continue }

            inventory.devices.append(InputDevice(id: deviceID, uid: uid))
        }
        return inventory
    }

    private static func inputUID(of device: AudioDeviceID) -> String? {
        var uidRef: CFString = "" as CFString
        guard read(device, kAudioDevicePropertyDeviceUID, &uidRef) else { return nil }
        let uid = uidRef as String
        return uid.isEmpty ? nil : uid
    }

    /// Input devices some process other than this app is recording from right
    /// now. Needs the per-process audio objects; without them nothing is
    /// reported and the mute is simply held as it always was.
    private static func devicesCapturedByOtherProcesses() -> Set<AudioDeviceID> {
        let system = AudioObjectID(kAudioObjectSystemObject)
        var devices = Set<AudioDeviceID>()
        let ownPID = ProcessInfo.processInfo.processIdentifier
        for process in objectIDs(of: system, selector: kAudioHardwarePropertyProcessObjectList,
                                 scope: kAudioObjectPropertyScopeGlobal) {
            var pid: pid_t = 0
            var running: UInt32 = 0
            guard read(process, kAudioProcessPropertyPID, &pid), pid != ownPID,
                  read(process, kAudioProcessPropertyIsRunningInput, &running), running != 0 else { continue }
            devices.formUnion(objectIDs(of: process, selector: kAudioProcessPropertyDevices,
                                        scope: kAudioObjectPropertyScopeInput))
        }
        return devices
    }

    private static func objectIDs(of object: AudioObjectID, selector: AudioObjectPropertySelector,
                                  scope: AudioObjectPropertyScope) -> [AudioObjectID] {
        var address = AudioObjectPropertyAddress(mSelector: selector, mScope: scope,
                                                 mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        let stride = UInt32(MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyDataSize(object, &address, 0, nil, &size) == noErr,
              size > 0, size.isMultiple(of: stride) else { return [] }
        let capacity = size
        var ids = [AudioObjectID](repeating: 0, count: Int(capacity / stride))
        guard AudioObjectGetPropertyData(object, &address, 0, nil, &size, &ids) == noErr,
              size <= capacity, size.isMultiple(of: stride) else { return [] }
        return Array(ids.prefix(Int(size / stride)))
    }

    private static func hasInputStreams(_ deviceID: AudioDeviceID) -> Bool? {
        var address = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyStreams,
                                                 mScope: kAudioDevicePropertyScopeInput,
                                                 mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(deviceID, &address, 0, nil, &size) == noErr else { return nil }
        return size >= MemoryLayout<AudioObjectID>.size
    }

    /// How many input channels the device actually has. Used so a mic array
    /// is muted on every element, not just the stereo pair.
    private static func inputChannelCount(of device: AudioDeviceID) -> Int {
        readInputChannelCount(of: device) ?? MicMuteSupport.minimumChannelCount
    }

    private static func readInputChannelCount(of device: AudioDeviceID) -> Int? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreamConfiguration,
            mScope: kAudioDevicePropertyScopeInput,
            mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(device, &address, 0, nil, &size) == noErr,
              size >= UInt32(MemoryLayout<AudioBufferList>.size) else { return nil }
        let capacity = size
        let storage = UnsafeMutableRawPointer.allocate(
            byteCount: Int(capacity), alignment: MemoryLayout<AudioBufferList>.alignment)
        defer { storage.deallocate() }
        // A route may change between the size query and the read. Validate
        // the count against the bytes actually returned before walking it.
        let list = storage.assumingMemoryBound(to: AudioBufferList.self)
        guard AudioObjectGetPropertyData(device, &address, 0, nil, &size, storage) == noErr, size <= capacity,
              let offset = MemoryLayout<AudioBufferList>.offset(of: \.mBuffers), Int(size) >= offset,
              Int(list.pointee.mNumberBuffers) <= (Int(size) - offset) / MemoryLayout<AudioBuffer>.stride
        else { return nil }
        return UnsafeMutableAudioBufferListPointer(list).reduce(0) { $0 + Int($1.mNumberChannels) }
    }

    private static func muteAddresses(of device: AudioDeviceID, channelCount: Int? = nil) -> [AudioObjectPropertyAddress] {
        MicMuteSupport.inputChannelElements(channelCount: channelCount ?? inputChannelCount(of: device)).map { element in
            AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyMute,
                                       mScope: kAudioDevicePropertyScopeInput,
                                       mElement: element)
        }
    }

    private static func readMuteSwitch(of device: AudioDeviceID, channelCount: Int?,
                                       read: ControlReader = MicMuteService.controlValue)
        -> (value: UInt32?, mutedElements: Set<UInt32>) {
        var main = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyMute,
                                               mScope: kAudioDevicePropertyScopeInput,
                                               mElement: kAudioObjectPropertyElementMain)
        var sawOpenSwitch = false
        var unreadable = false
        if AudioObjectHasProperty(device, &main) {
            if let value = read(device, main) {
                if value == 1 { return (1, [main.mElement]) }
                sawOpenSwitch = true
            } else {
                unreadable = true
            }
        }
        // A channel switch only silences that channel. Without an engaged
        // main switch, every input channel needs a readable, engaged switch.
        var mutedChannels: Set<UInt32> = []
        guard let channelCount, channelCount > 0 else { return (sawOpenSwitch ? 0 : nil, []) }
        for channel in 1...UInt32(clamping: channelCount) {
            var address = main
            address.mElement = AudioObjectPropertyElement(channel)
            guard AudioObjectHasProperty(device, &address) else { continue }
            guard let value = read(device, address) else {
                unreadable = true
                continue
            }
            if value == 0 {
                sawOpenSwitch = true
            } else {
                mutedChannels.insert(channel)
            }
        }
        if mutedChannels.count == channelCount { return (1, mutedChannels) }
        return (sawOpenSwitch && !unreadable ? 0 : nil, mutedChannels)
    }

    private static func volumeAddresses(of device: AudioDeviceID, channelCount: Int? = nil) -> [AudioObjectPropertyAddress] {
        let elements = MicMuteSupport.inputChannelElements(channelCount: channelCount ?? inputChannelCount(of: device))
        var addresses = [
            AudioObjectPropertyAddress(mSelector: kAudioHardwareServiceDeviceProperty_VirtualMainVolume,
                                       mScope: kAudioDevicePropertyScopeInput,
                                       mElement: kAudioObjectPropertyElementMain)
        ]
        addresses.append(contentsOf: elements.map { element in
            AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyVolumeScalar,
                                       mScope: kAudioDevicePropertyScopeInput,
                                       mElement: element)
        })
        return addresses
    }

    private static func inputVolume(of device: AudioDeviceID, read: ControlReader = MicMuteService.controlValue) -> Float? {
        for var address in volumeAddresses(of: device) where AudioObjectHasProperty(device, &address) {
            if let volume = read(device, address) {
                return Float(volume)
            }
        }
        return nil
    }

    /// Per-channel levels, keyed by element. A mute lowers them with the main
    /// level, and an unmute that wrote the main level into every channel would
    /// flatten the balance between them.
    private static func channelVolumes(of device: AudioDeviceID, read: ControlReader) -> [String: Double] {
        var levels: [String: Double] = [:]
        for var address in volumeAddresses(of: device) where address.mElement != kAudioObjectPropertyElementMain
            && AudioObjectHasProperty(device, &address) {
            if let volume = read(device, address) {
                levels[String(address.mElement)] = volume
            }
        }
        return levels
    }

    /// Gain records predating per-control snapshots addressed these three
    /// scalars, including the releases that saved the stereo balance.
    private static var legacyGainAddresses: [AudioObjectPropertyAddress] {
        [kAudioObjectPropertyElementMain, 1, 2].map {
            AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyVolumeScalar,
                                       mScope: kAudioDevicePropertyScopeInput, mElement: $0)
        }
    }

    /// Older captures stored channel readings before checking write access.
    /// Keep a missing channel by its element until it can be classified.
    private static func classifyLegacyChannels(_ existing: [String: Double]?, on device: AudioDeviceID)
        -> (controls: [String: Double], needsManualCheck: Bool)? {
        guard var controls = existing, controls.keys.contains(where: { UInt32($0) != nil }) else { return nil }
        var manual = false
        for (key, target) in controls {
            guard let element = UInt32(key) else { continue }
            guard element > 0 && String(element) == key && (0...1).contains(target) else {
                controls.removeValue(forKey: key)
                manual = true
                continue
            }
            var address = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyVolumeScalar,
                                                     mScope: kAudioObjectPropertyScopeInput, mElement: element)
            let qualified = controlKey(address)
            if controls[qualified] != nil {
                controls.removeValue(forKey: key)
                continue
            }
            guard AudioObjectHasProperty(device, &address) else { continue }
            controls.removeValue(forKey: key)
            switch controlAccess(device, at: address) {
            case .writable: controls[qualified] = target
            case .unknown: manual = true
            case .readOnly: break
            }
        }
        return (controls, manual)
    }

    private static func controlKey(_ address: AudioObjectPropertyAddress) -> String {
        "\(address.mSelector):\(address.mElement)"
    }

    private static func controlAddress(_ key: String) -> AudioObjectPropertyAddress? {
        let parts = key.split(separator: ":")
        guard parts.count == 2, let selector = UInt32(parts[0]), let element = UInt32(parts[1]),
              selector == kAudioDevicePropertyMute || selector == kAudioDevicePropertyVolumeScalar
                || selector == kAudioHardwareServiceDeviceProperty_VirtualMainVolume else { return nil }
        return AudioObjectPropertyAddress(mSelector: selector,
                                           mScope: kAudioDevicePropertyScopeInput,
                                           mElement: element)
    }

    private static func controlRestoreOrder(_ address: AudioObjectPropertyAddress) -> Int {
        if address.mSelector == kAudioHardwareServiceDeviceProperty_VirtualMainVolume { return 0 }
        return address.mSelector == kAudioDevicePropertyVolumeScalar ? 1 : 2
    }

    private static func isMasterGain(_ address: AudioObjectPropertyAddress) -> Bool {
        address.mElement == kAudioObjectPropertyElementMain && address.mSelector != kAudioDevicePropertyMute
    }

    /// Keep confirmed writable elements across attempts. A failed access
    /// query needs another check while that property is still present.
    private static func observeWritableChannels(on device: AudioDeviceID, into channels: inout Set<UInt32>,
                                                excluding known: Set<UInt32> = []) -> Set<UInt32> {
        var unclassified: Set<UInt32> = []
        for var address in volumeAddresses(of: device) where address.mElement != 0
            && !known.contains(address.mElement) && AudioObjectHasProperty(device, &address) {
            var settable = DarwinBoolean(false)
            if AudioObjectIsPropertySettable(device, &address, &settable) != noErr {
                unclassified.insert(address.mElement)
            } else if settable.boolValue {
                channels.insert(address.mElement)
            }
        }
        return unclassified
    }

    /// A released channel belongs to the user again. Remember its address
    /// across attempts, and capture its live value only when writing a master.
    private static func restoreControls(_ saved: [String: Double], on device: InputDevice,
                                        protecting channels: inout Set<UInt32>, openings: inout Set<String>,
                                        unverified: inout Set<String>,
                                        attempts: inout [String: RestoreAttempt], now: TimeInterval,
                                        recordedLevels: [String: Double]?,
                                        willWrite: () -> Void, isCurrent: (InputDevice) -> Bool,
                                        canVerify: (InputDevice) -> Bool) -> (outstanding: [String: Double], sameInput: Bool) {
        var submittedKeys: Set<String> = []
        func restore(_ target: Double, at address: AudioObjectPropertyAddress, prepare: () -> ControlWrite? = { nil }) -> Bool {
            let key = controlKey(address)
            let previous = attempts[key].flatMap { $0.target == target ? $0 : nil }
            var property = address
            guard AudioObjectHasProperty(device.id, &property) else {
                attempts[key] = nil
                return false
            }
            if let previous, !previous.unknownAccessElements.isEmpty && previous.defersWrite(at: now) { return false }
            var submitted = false
            var unknownAccessElements: Set<UInt32> = []
            var checkDue = previous?.deadline.map { $0 <= now } ?? false
            switch writeControl(target, of: device, at: address, isCurrent: isCurrent, prepare: {
                if let failure = prepare() { return failure }
                guard isCurrent(device) else { return .interrupted }
                willWrite()
                return nil
            },
                                deferRestore: previous?.defersWrite(at: now) == true) {
            case .submitted(let possiblyChanged, _):
                openings.insert(key)
                submittedKeys.insert(key)
                if possiblyChanged { unverified.insert(key) }
                submitted = true
            case .unavailable(let checkedAccess):
                let access = checkedAccess ?? controlAccess(device.id, at: address)
                if access == .readOnly {
                    attempts[key] = nil
                    return false
                }
                if access == .unknown { unknownAccessElements.insert(address.mElement) }
                if previous == nil { checkDue = isCurrent(device) }
            case .unclassifiedChannels(let elements):
                unknownAccessElements = elements
                if previous == nil { checkDue = isCurrent(device) }
            case .unchanged: break
            case .interrupted: return false
            }
            // A due check can fail before Set, or its final read can still
            // disagree. Each uses one opportunity on this present control.
            if submitted || checkDue {
                attempts[key] = RestoreAttempt(target: target, previous: previous, submitted: submitted, now: now)
            }
            if !unknownAccessElements.isEmpty { attempts[key]?.unknownAccessElements = unknownAccessElements }
            return submitted
        }
        var targets = saved
        let savedAddresses = saved.keys.compactMap(controlAddress)
        let masters = savedAddresses.filter(isMasterGain).sorted { controlRestoreOrder($0) < controlRestoreOrder($1) }
        let previousChannels = channels
        var wroteMaster = false
        // A sampled channel may be unreadable until the master setter runs.
        var beforeMaster: [String: Double?] = [:]
        if !masters.isEmpty || saved["0"] != nil {
            for address in savedAddresses where address.mElement != 0 && address.mSelector == kAudioDevicePropertyVolumeScalar {
                channels.insert(address.mElement)
            }
            // Keep discovering new writable siblings while a master waits.
            // Recheck previously indeterminate access only when a master can run.
            let deferred = masters.reduce(into: Set<UInt32>()) { result, master in
                let key = controlKey(master)
                if let retry = attempts[key], retry.target == saved[key], retry.defersWrite(at: now) {
                    result.formUnion(retry.unknownAccessElements)
                }
            }
            let known = channels.union(deferred)
            var unclassified = observeWritableChannels(on: device.id, into: &channels, excluding: known)
            // Earlier records included read-only meters among their levels.
            // Only an independently writable channel needs compensation.
            let newlyWritable = channels.subtracting(known)
            let candidates = channels.union(unclassified).union(deferred)
                .union(recordedLevels?.keys.compactMap { UInt32($0) } ?? [])
            func captureLiveChannels(into live: inout [String: Double], beforeWrite: inout [String: Double?]) -> ControlWrite? {
                for element in candidates where element != 0 {
                    var address = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyVolumeScalar,
                                                             mScope: kAudioDevicePropertyScopeInput, mElement: element)
                    let key = controlKey(address)
                    if targets[key] != nil {
                        if attempts[key] != nil && !beforeMaster.keys.contains(key) {
                            beforeWrite.updateValue(controlValue(of: device.id, at: address), forKey: key)
                        }
                        continue
                    }
                    guard AudioObjectHasProperty(device.id, &address) else {
                        if channels.contains(element) { return .interrupted }
                        continue
                    }
                    if unclassified.contains(element) { return .unclassifiedChannels(unclassified) }
                    let access = !wroteMaster && newlyWritable.contains(element) ? .writable : controlAccess(device.id, at: address)
                    if access == .unknown {
                        unclassified.insert(element)
                        return .unclassifiedChannels(unclassified)
                    }
                    if access == .readOnly {
                        if channels.contains(element) { return .interrupted }
                        continue
                    }
                    channels.insert(element)
                    guard let current = controlValue(of: device.id, at: address) else { return .unavailable(.writable) }
                    live[key] = current
                }
                return nil
            }
            for master in masters {
                let key = controlKey(master)
                guard let value = saved[key] else { continue }
                var live: [String: Double] = [:]
                var beforeWrite: [String: Double?] = [:]
                var exposedGains: Set<String> = []
                let submitted = restore(value, at: master) {
                    if let failure = captureLiveChannels(into: &live, beforeWrite: &beforeWrite) { return failure }
                    // Only gains exposed at the setter can move with this master.
                    for sibling in targets.keys where sibling != key {
                        var gain = controlAddress(sibling)
                        if let element = UInt32(sibling) {
                            gain = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyVolumeScalar,
                                                              mScope: kAudioObjectPropertyScopeInput, mElement: element)
                        }
                        if var gain, gain.mSelector != kAudioDevicePropertyMute && AudioObjectHasProperty(device.id, &gain) {
                            exposedGains.insert(sibling)
                        }
                    }
                    return nil
                }
                if submitted {
                    wroteMaster = true
                    beforeMaster.merge(beforeWrite) { first, _ in first }
                    targets.merge(live) { saved, _ in saved }
                    unverified.formUnion(exposedGains)
                    unverified.formUnion(live.keys)
                }
                // The master's access check can stop before prepare records
                // the channels whose access also failed in this sweep.
                if attempts[key]?.unknownAccessElements.isEmpty == false {
                    attempts[key]?.unknownAccessElements.formUnion(unclassified)
                }
            }
        }
        let addresses = targets.keys.compactMap(controlAddress).sorted {
            let left = controlRestoreOrder($0)
            let right = controlRestoreOrder($1)
            return left == right ? $0.mElement < $1.mElement : left < right
        }
        for address in addresses where !isMasterGain(address) {
            let key = controlKey(address)
            if let value = targets[key] {
                // A changed gain or a newly readable channel after a submitted
                // master can need compensation even after an earlier refusal.
                if let before = beforeMaster[key], let current = controlValue(of: device.id, at: address),
                   current != before {
                    attempts[key] = nil
                }
                _ = restore(value, at: address)
            }
        }
        var outstanding = targets
        unverified.formIntersection(targets.keys)
        var unread = unverified
        for address in addresses {
            let key = controlKey(address)
            if let expected = targets[key], let current = controlValue(of: device.id, at: address) {
                unread.remove(key)
                if controlValuesMatch(current, expected) { outstanding.removeValue(forKey: key) }
            }
        }
        // A replacement cannot discharge this UID's obligations. Only a
        // submitted master could also have changed its channels before unplug.
        guard isCurrent(device) || canVerify(device) else {
            unverified.formUnion(submittedKeys)
            if !wroteMaster { channels = previousChannels }
            return (wroteMaster ? targets : saved, false)
        }
        unverified = unread
        return (outstanding, true)
    }

    private static func controlValuesMatch(_ left: Double, _ right: Double) -> Bool {
        guard left.isFinite, right.isFinite else { return false }
        if left == 0 || right == 0 { return left == right }
        let target = Float(right)
        if left == Double(target) { return true }
        // A driver's scalar conversion can return the adjacent Float. Keep
        // this allowance proportional even for tiny gains, and zero exact.
        return left > 0 && target > 0 && (left == Double(target.nextUp) || left == Double(target.nextDown))
    }

    private static func controlValue(of device: AudioDeviceID,
                                     at address: AudioObjectPropertyAddress) -> Double? {
        var address = address
        guard AudioObjectHasProperty(device, &address) else { return nil }
        if address.mSelector == kAudioDevicePropertyMute {
            var value: UInt32 = 0
            var size = UInt32(MemoryLayout<UInt32>.size)
            guard AudioObjectGetPropertyData(device, &address, 0, nil, &size, &value) == noErr,
                  size == MemoryLayout<UInt32>.size, value <= 1 else { return nil }
            return Double(value)
        }
        var value: Float = 0
        var size = UInt32(MemoryLayout<Float>.size)
        guard AudioObjectGetPropertyData(device, &address, 0, nil, &size, &value) == noErr,
              size == MemoryLayout<Float>.size, value.isFinite, value >= 0, value <= 1 else { return nil }
        return Double(value)
    }

    private enum ControlAccess { case writable, readOnly, unknown }

    private static func controlAccess(_ device: AudioDeviceID, at address: AudioObjectPropertyAddress) -> ControlAccess {
        var address = address
        var settable = DarwinBoolean(false)
        guard AudioObjectIsPropertySettable(device, &address, &settable) == noErr else { return .unknown }
        return settable.boolValue ? .writable : .readOnly
    }

    private enum ControlWrite {
        case unavailable(ControlAccess?), unchanged, interrupted
        case unclassifiedChannels(Set<UInt32>)
        case submitted(possiblyChanged: Bool, correctedSmallGain: Bool)
    }

    /// Reports a possible change, not proof of the requested state. A driver
    /// may accept and ignore a write, or make the control unreadable afterwards.
    /// Callers keep the snapshot and verify the final state separately.
    private static func writeControl(_ value: Double, of input: InputDevice,
                                      at address: AudioObjectPropertyAddress,
                                      isCurrent: (InputDevice) -> Bool,
                                      prepare: () -> ControlWrite? = { nil },
                                      deferRestore: Bool = false,
                                      quietBeforeWrite: Set<DeviceListener>? = nil,
                                      read: ControlReader = MicMuteService.controlValue,
                                      authorize: MuteAuthorization? = nil) -> ControlWrite {
        let device = input.id
        guard value.isFinite, value >= 0, value <= 1,
              address.mSelector != kAudioDevicePropertyMute || value == 0 || value == 1,
              let current = read(device, address) else { return .unavailable(nil) }
        if current == Double(Float(value)) { return .unchanged }
        var address = address
        let access = controlAccess(device, at: address)
        guard access == .writable else { return .unavailable(access) }
        // A ControlList echo wakes verification. The same writable address
        // still owes the same target, even if its driver varies the readback.
        if deferRestore { return .unchanged }
        // This is the last software decision before either HAL setter. The
        // callback lock is released before calling a potentially reentrant driver.
        let listener = DeviceListener(device: device, selector: address.mSelector, scope: address.mScope, element: address.mElement)
        let preparationFailure = prepare()
        guard isCurrent(input) else { return .interrupted }
        if let preparationFailure { return preparationFailure }
        guard authorize?.beforeWrite(listener, quietBeforeWrite) != false else { return .interrupted }
        let status: OSStatus
        if address.mSelector == kAudioDevicePropertyMute {
            var target = UInt32(value)
            status = AudioObjectSetPropertyData(device, &address, 0, nil,
                                                UInt32(MemoryLayout<UInt32>.size), &target)
        } else {
            var target = Float(value)
            status = AudioObjectSetPropertyData(device, &address, 0, nil,
                                                UInt32(MemoryLayout<Float>.size), &target)
        }
        let readBack = controlValue(of: device, at: address)
        let matched = readBack.map { controlValuesMatch($0, value) } == true
        authorize?.didWrite(listener, matched)
        // Once submitted, an unreadable result cannot release our obligation
        // to restore the value saved before the call.
        let correctedSmallGain = address.mSelector != kAudioDevicePropertyMute && value == 0
            && MicMuteSupport.Retry.isSmallGain(current)
        return .submitted(possiblyChanged: status == noErr || readBack != current, correctedSmallGain: correctedSmallGain)
    }

    private static var pendingLegacyRestore: LegacyDefaultRestore? {
        UserDefaults.standard.data(forKey: DefaultsKey.micMutePendingLegacyControls)
            .flatMap { try? JSONDecoder().decode(LegacyDefaultRestore.self, from: $0) }
    }

    /// Before 3.2 only the default input was touched. A successful master
    /// mute ended the operation. Its fallback wrote scalar elements 0, 1, 2.
    private struct LegacyDefaultRestore: Codable, Equatable {
        let uid: String?
        let gain: Double?
        var checkSwitch = false
        var firstScalar: UInt32?
        var unreadScalars: Set<UInt32> = []
        var residualScalars: Set<UInt32> = []
        private static var mainSwitch: AudioObjectPropertyAddress {
            AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyMute, mScope: kAudioDevicePropertyScopeInput,
                                       mElement: kAudioObjectPropertyElementMain)
        }

        var isPending: Bool { checkSwitch || firstScalar != nil || !unreadScalars.isEmpty }

        mutating func resolve(on device: AudioDeviceID) -> [String: Double] {
            var main = Self.mainSwitch
            var settable = DarwinBoolean(false)
            if checkSwitch, AudioObjectHasProperty(device, &main),
               AudioObjectIsPropertySettable(device, &main, &settable) == noErr {
                if !settable.boolValue {
                    checkSwitch = false
                } else if let value = controlValue(of: device, at: main) {
                    checkSwitch = false
                    if value == 1 || gain == nil {
                        clear()
                        return value == 1 ? [controlKey(main): 0] : [:]
                    }
                }
            }

            let limit = gain == nil ? 0 : Double(MicMuteSupport.residualGainLimit)
            for var address in legacyGainAddresses {
                let element = address.mElement
                guard unreadScalars.contains(element) || residualScalars.contains(element) || firstScalar == element,
                      AudioObjectHasProperty(device, &address),
                      let current = controlValue(of: device, at: address) else { continue }
                if firstScalar == element {
                    firstScalar = nil
                    // The old gain came from the first scalar. A live master
                    // with a zero channel cannot authenticate the gain path.
                    if current > limit {
                        unreadScalars.removeAll()
                        residualScalars.removeAll()
                        break
                    }
                }
                guard AudioObjectIsPropertySettable(device, &address, &settable) == noErr else { continue }
                unreadScalars.remove(element)
                if settable.boolValue && current <= limit { residualScalars.insert(element) }
                else { residualScalars.remove(element) }
            }
            guard !checkSwitch, firstScalar == nil else { return [:] }
            // Turn confirmed controls into individual obligations immediately.
            // Unreadable siblings remain bound to this UID on the next launch.
            var snapshot: [String: Double] = [:]
            for address in legacyGainAddresses where residualScalars.contains(address.mElement) {
                snapshot[controlKey(address)] = gain ?? Double(MicMuteSupport.fallbackVolume)
            }
            residualScalars.removeAll()
            return snapshot
        }

        private mutating func clear() {
            checkSwitch = false
            firstScalar = nil
            unreadScalars.removeAll()
            residualScalars.removeAll()
        }
    }

    /// A UID without recorded gains can release an identifiable native
    /// master switch. An already open switch only needs a verified reading.
    private static func legacySwitchSnapshot(_ device: InputDevice) -> [String: Double]? {
        var main = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyMute,
                                              mScope: kAudioDevicePropertyScopeInput,
                                              mElement: kAudioObjectPropertyElementMain)
        guard let value = controlValue(of: device.id, at: main) else { return nil }
        var settable = DarwinBoolean(false)
        guard value == 0 || (AudioObjectIsPropertySettable(device.id, &main, &settable) == noErr && settable.boolValue)
        else { return nil }
        return [controlKey(main): 0]
    }

    @discardableResult
    private static func read<T>(_ object: AudioObjectID,
                                _ selector: AudioObjectPropertySelector,
                                _ value: inout T) -> Bool {
        var address = AudioObjectPropertyAddress(mSelector: selector,
                                                 mScope: kAudioObjectPropertyScopeGlobal,
                                                 mElement: kAudioObjectPropertyElementMain)
        var size = UInt32(MemoryLayout<T>.size)
        return withUnsafeMutablePointer(to: &value) { pointer in
            AudioObjectGetPropertyData(object, &address, 0, nil, &size,
                                       UnsafeMutableRawPointer(pointer)) == noErr
        }
    }

    // MARK: - Listeners

    /// Two changes can defeat an active mute: a device arriving (a headset
    /// connecting mid call) and the default input moving. Both re-assert it,
    /// and both are how a device still owed its level back announces itself.
    private static let watchedSelectors: [AudioObjectPropertySelector] = [
        kAudioHardwarePropertyServiceRestarted,
        kAudioHardwarePropertyDevices,
        kAudioHardwarePropertyDefaultInputDevice,
    ]

    private func canFollowCallApps(in generation: UInt64, revision: UInt64? = nil) -> Bool {
        callbackLock.withLock {
            audioGeneration == generation && listObservationGeneration == generation && !resetObservationMissing
                && (revision == nil || revision == topologyRevision)
        }
    }

    /// The opaque client names one HAL add, even when the address and server
    /// generation are reused. Keep its number for removal if the HAL refuses.
    /// A failed add or a disappearing owner also releases the registry entry.
    private final class ListenerLifetime {
        let client: UnsafeMutableRawPointer
        var start: UInt64
        var end: UInt64
        var retiring = false

        init(owner: MicMuteService, generation: UInt64) {
            client = AudioListenerClients.reserve(for: owner)
            start = generation
            end = generation
        }

        deinit { AudioListenerClients.forget(client) }

        func belongsTo(_ generation: UInt64) -> Bool { start == generation && end == generation }
        func isCurrent(_ generation: UInt64) -> Bool { !retiring && belongsTo(generation) }
    }

    private func addListener(_ object: AudioObjectID, _ address: inout AudioObjectPropertyAddress,
                             generation: UInt64) -> ListenerLifetime? {
        let lifetime = ListenerLifetime(owner: self, generation: generation)
        let binding = DeviceListener(device: object, selector: address.mSelector, scope: address.mScope, element: address.mElement)
        // A restart may already be delivered from inside the HAL's add.
        let current = callbackLock.withLock {
            guard generation == audioGeneration else { return false }
            callbackBindings[lifetime.client] = binding
            return true
        }
        guard current else { return nil }
        guard AudioObjectAddPropertyListener(object, &address, Self.listenerCallback, lifetime.client) == noErr else {
            callbackLock.withLock { callbackBindings[lifetime.client] = nil }
            return nil
        }
        lifetime.end = currentAudioGeneration
        return lifetime
    }

    private func retireListener(_ lifetime: ListenerLifetime, on object: AudioObjectID,
                                at address: inout AudioObjectPropertyAddress) -> Bool {
        lifetime.retiring = true
        let resetRemovedIt = callbackLock.withLock {
            if let binding = callbackBindings.removeValue(forKey: lifetime.client),
               pendingNotices.controls[binding] == lifetime.client {
                pendingNotices.controls[binding] = nil
            }
            confirmedControlClients.remove(lifetime.client)
            return lifetime.end < lastConfirmedReset
        }
        AudioListenerClients.forget(lifetime.client)
        if resetRemovedIt { return true }
        let status = AudioObjectRemovePropertyListener(object, &address, Self.listenerCallback, lifetime.client)
        // A transient error can leave the registration live. Keep it tracked
        // until the HAL accepts removal or confirms its object/property is gone.
        return status == noErr || status == kAudioHardwareBadObjectError
            || status == kAudioHardwareBadDeviceError || status == kAudioHardwareUnknownPropertyError
    }

    private func syncSystemListeners(wanted: Bool) {
        let wasWanted = wantsSystemListeners
        callbackLock.withLock { wantsSystemListeners = wanted }
        var generation = currentAudioGeneration
        for selector in Self.watchedSelectors {
            syncSystemListener(selector, wanted: wanted, generation: generation)
            if wanted, selector == kAudioHardwarePropertyServiceRestarted,
               let recovered = recoverResetObservation(in: generation) {
                // This listener is the first one known to exist after the gap.
                installedListeners[selector]?.start = recovered
                installedListeners[selector]?.end = recovered
                generation = recovered
                scheduleReapply()
            }
        }
        let hasList = installedListeners[kAudioHardwarePropertyDevices]?.isCurrent(generation) == true
        let recoveredList = callbackLock.withLock {
            let observing = wanted && hasList && generation == audioGeneration
            let recovered = observing && listObservationGeneration != generation
            listObservationGeneration = observing ? generation : nil
            if recovered {
                // The list can be unchanged after a gap that lost every
                // listener on one headset. Reconcile it as a new connection.
                topologyRevision &+= 1
                pendingNotices.topology.insert(AudioObjectID(kAudioObjectSystemObject))
            }
            return recovered
        }
        if wasWanted && recoveredList { scheduleReapply() }
        updateSystemListenerRetry(generation: wanted && !canFollowCallApps(in: generation) ? generation : nil)
    }

    /// Retry only during an observation gap. After the bounded attempts,
    /// hardware callbacks and preference changes can still recover without polling.
    private func updateSystemListenerRetry(generation: UInt64?) {
        if systemListenerRetryGeneration != generation {
            systemListenerRetry?.cancel()
            systemListenerRetry = nil
            systemListenerRetryIndex = 0
            systemListenerRetryGeneration = generation
        }
        guard generation != nil, systemListenerRetry == nil, systemListenerRetryIndex < Self.recoveryDelays.count else { return }
        let work = DispatchWorkItem { [weak self] in
            guard let self, self.wantsSystemListeners else { return }
            self.systemListenerRetry = nil
            self.syncSystemListeners(wanted: true)
            self.scheduleReapply()
        }
        systemListenerRetry = work
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.recoveryDelays[systemListenerRetryIndex], execute: work)
        systemListenerRetryIndex += 1
    }

    private func syncSystemListener(_ selector: AudioObjectPropertySelector, wanted: Bool, generation: UInt64) {
        var address = AudioObjectPropertyAddress(mSelector: selector, mScope: kAudioObjectPropertyScopeGlobal,
                                                 mElement: kAudioObjectPropertyElementMain)
        let system = AudioObjectID(kAudioObjectSystemObject)
        if let lifetime = installedListeners[selector] {
            if wanted && lifetime.isCurrent(generation) { return }
            guard retireListener(lifetime, on: system, at: &address) else { return }
            installedListeners.removeValue(forKey: selector)
        }
        if wanted, let lifetime = addListener(system, &address, generation: generation) {
            installedListeners[selector] = lifetime
        }
    }

    /// A reset may have gone undelivered while registration failed. Treat
    /// observations as new, but retire old listeners explicitly: the server
    /// may still have them when no reset actually happened.
    private func recoverResetObservation(in generation: UInt64) -> UInt64? {
        let listening = installedListeners[kAudioHardwarePropertyServiceRestarted]?.isCurrent(generation) == true
        return callbackLock.withLock {
            guard generation == audioGeneration else { return nil }
            let recovered = resetObservationMissing && listening
            resetObservationMissing = !listening
            guard recovered else { return nil }
            audioGeneration &+= 1
            return audioGeneration
        }
    }

    /// The controls an app can move to raise gain again while we are muted.
    /// The virtual main volume is a master-only control; mute and per-channel
    /// volume are watched on every input element we write.
    private static let watchedDeviceSelectors: [AudioObjectPropertySelector] = [
        kAudioHardwareServiceDeviceProperty_VirtualMainVolume,
        kAudioDevicePropertyMute,
        kAudioDevicePropertyVolumeScalar,
    ]

    private static let inputTopologySelectors: [AudioObjectPropertySelector] = [
        kAudioDevicePropertyDeviceIsAlive, kAudioDevicePropertyDeviceHasChanged,
        kAudioDevicePropertyStreams, kAudioDevicePropertyStreamConfiguration, kAudioObjectPropertyControlList,
        kAudioAggregateDevicePropertyActiveSubDeviceList,
    ]

    /// A list change can hide a same-ID reconnect anywhere. An input's own
    /// structural notification only invalidates observations on that device.
    private func observeTopology(revision: UInt64, objects: Set<AudioObjectID>) -> Bool {
        defer { observedDeviceListChange = revision }
        guard let previous = observedDeviceListChange, revision != previous else { return false }
        if objects.contains(AudioObjectID(kAudioObjectSystemObject)) {
            listenersToRenew.formUnion(deviceListeners.keys)
            observedInputs = []
            quietInputs.removeAll()
        } else {
            listenersToRenew.formUnion(deviceListeners.keys.filter { objects.contains($0.device) })
            observedInputs = observedInputs?.filter { !objects.contains($0.id) }
            quietInputs = quietInputs.filter { !objects.contains($0.key.id) }
        }
        return true
    }

    private enum DeviceObservation { case muted, restoring, stopped }

    private func pendingControlListListeners(generation: UInt64) -> [DeviceListener: String] {
        let selector = kAudioObjectPropertyControlList
        let system = AudioObjectID(kAudioObjectSystemObject)
        if callbackLock.withLock({ pendingNotices.topology.remove(system) != nil }) {
            // A coalesced reconnect can drop an existing registration. Newly
            // installed ones already belong to the updated list.
            listenersToRenew.formUnion(deviceListeners.keys.filter { $0.selector == selector })
        }
        let defaults = UserDefaults.standard
        guard let claims = defaults.stringArray(forKey: DefaultsKey.micMuteMutedDevices), !claims.isEmpty else { return [:] }
        let controls = defaults.dictionary(forKey: DefaultsKey.micMuteSavedControls)
        let channels = defaults.dictionary(forKey: DefaultsKey.micMuteSavedChannelVolumes) as? [String: [String: Double]]
        let owed = Set(claims.filter { uid in
            if let value = controls?[uid],
               let snapshot = value as? [String: Double] ?? ReleaseCheckpoint.decode(value)?.controls {
                return !snapshot.isEmpty
            }
            return channels?[uid]?.isEmpty == false
        })
        guard !owed.isEmpty else { return [:] }
        let ids = Self.audioDeviceIDs() ?? deviceListeners.keys.filter { $0.selector == selector }.map(\.device)
        var wanted: [DeviceListener: String] = [:]
        for id in ids {
            let listener = DeviceListener(device: id, selector: selector, scope: kAudioObjectPropertyScopeGlobal,
                                          element: kAudioObjectPropertyElementMain)
            if let uid = Self.inputUID(of: id) {
                var address = listener.address
                if owed.contains(uid) && AudioObjectHasProperty(id, &address) { wanted[listener] = uid }
            } else if let previous = deviceListeners[listener], previous.lifetime.isCurrent(generation), owed.contains(previous.uid) {
                wanted[listener] = previous.uid
            }
        }
        return wanted
    }

    /// Runs on `halQueue`. A new restore listener needs one read after
    /// registration in case the missing control returned during installation.
    @discardableResult
    private func syncDeviceListeners(_ mode: DeviceObservation) -> Bool {
        let generation = currentAudioGeneration
        let muted = mode == .muted
        defer { confirmQuietControls() }
        // Keep existing registrations on a failed read. A later successful
        // reconciliation and quiet reading must precede any automatic unmute.
        guard let inventory = muted ? Self.inputInventory() : InputInventory() else {
            observedInputs = []
            quietInputs.removeAll()
            return false
        }
        var wanted = mode == .restoring ? pendingControlListListeners(generation: generation) : [:]
        // A listed object whose input streams or identity cannot be read may
        // still be our microphone. Its next callback can complete discovery.
        if !inventory.unresolvedIDs.isEmpty {
            for (listener, registration) in deviceListeners where inventory.unresolvedIDs.contains(listener.device)
                && registration.lifetime.isCurrent(generation) {
                wanted[listener] = registration.uid
            }
        }
        var devicesToWatch = inventory.devices
        if !inventory.inactiveIDs.isEmpty {
            // An input can stop offering streams or go offline without leaving
            // the system device list. Keep a way to hear it become usable.
            var priorUIDs: [AudioDeviceID: String] = [:]
            for (listener, registration) in deviceListeners where inventory.inactiveIDs.contains(listener.device) {
                priorUIDs[listener.device] = registration.uid
            }
            for id in inventory.inactiveIDs where priorUIDs[id] != nil || !missingInputUIDs.isEmpty {
                let priorUID = priorUIDs[id]
                guard let uid = Self.inputUID(of: id) ?? priorUID,
                      uid == priorUID || missingInputUIDs.contains(uid) else { continue }
                devicesToWatch.append(InputDevice(id: id, uid: uid))
            }
        }
        for device in devicesToWatch {
            let inactive = inventory.inactiveIDs.contains(device.id)
            func watch(_ selector: AudioObjectPropertySelector, scope: AudioObjectPropertyScope,
                       element: AudioObjectPropertyElement = kAudioObjectPropertyElementMain) {
                let listener = DeviceListener(device: device.id, selector: selector, scope: scope, element: element)
                if inactive, let previous = deviceListeners[listener], previous.uid == device.uid,
                   previous.lifetime.isCurrent(generation) {
                    wanted[listener] = device.uid
                    return
                }
                var address = listener.address
                if AudioObjectHasProperty(device.id, &address) { wanted[listener] = device.uid }
            }
            // A route can expose a different set of controls or channels on
            // the same device. Listen for those changes even while gain is zero.
            watch(kAudioObjectPropertyControlList, scope: kAudioObjectPropertyScopeGlobal)
            watch(kAudioAggregateDevicePropertyActiveSubDeviceList, scope: kAudioObjectPropertyScopeGlobal)
            watch(kAudioDevicePropertyDeviceHasChanged, scope: kAudioObjectPropertyScopeGlobal)
            watch(kAudioDevicePropertyDeviceIsAlive, scope: kAudioObjectPropertyScopeGlobal)
            watch(kAudioDevicePropertyStreams, scope: kAudioDevicePropertyScopeInput)
            watch(kAudioDevicePropertyStreamConfiguration, scope: kAudioDevicePropertyScopeInput)
            if inactive { continue }
            let channelCount = Self.readInputChannelCount(of: device.id)
            if channelCount == nil {
                // A temporarily unreadable layout does not retire channels
                // already observed on this connection.
                for (listener, registration) in deviceListeners where listener.device == device.id
                    && registration.uid == device.uid && registration.lifetime.isCurrent(generation)
                    && listener.element != kAudioObjectPropertyElementMain {
                    wanted[listener] = device.uid
                }
            }
            let elements = MicMuteSupport.inputChannelElements(
                channelCount: channelCount ?? MicMuteSupport.minimumChannelCount)
            for selector in Self.watchedDeviceSelectors {
                let watchElements: [AudioObjectPropertyElement]
                if selector == kAudioHardwareServiceDeviceProperty_VirtualMainVolume {
                    watchElements = [kAudioObjectPropertyElementMain]
                } else {
                    watchElements = elements
                }
                for element in watchElements {
                    watch(selector, scope: kAudioDevicePropertyScopeInput, element: element)
                }
            }
            if retries[device]?.values.contains(where: \.wasIdleVirtual) == true {
                // A previously idle virtual input may now feed a call. Its
                // start must bypass the cooldown even if gain hasn't moved.
                watch(kAudioDevicePropertyDeviceIsRunningSomewhere, scope: kAudioObjectPropertyScopeGlobal)
            }
        }
        // Keep a listed but unreadable device's current listener until its
        // identity is known and its replacement can be registered.
        for (listener, registration) in deviceListeners {
            if inventory.unresolvedIDs.contains(listener.device) && registration.lifetime.belongsTo(generation) { continue }
            guard wanted[listener] != registration.uid || !registration.lifetime.isCurrent(generation)
                || listenersToRenew.contains(listener) else { continue }
            var address = listener.address
            if retireListener(registration.lifetime, on: listener.device, at: &address) {
                deviceListeners.removeValue(forKey: listener)
                listenersToRenew.remove(listener)
            }
        }
        // Keep a newly repaired topology listener in place. Only registrations
        // that survived the observation gap could belong to the old connection.
        let survivors = topologyGaps.isEmpty ? [] : deviceListeners.keys.filter { topologyGaps.contains($0.device) }
        var addedRestoreListener = false
        for (listener, uid) in wanted where deviceListeners[listener] == nil {
            if mode == .restoring && Self.inputUID(of: listener.device) != uid { continue }
            var address = listener.address
            if let lifetime = addListener(listener.device, &address, generation: generation) {
                deviceListeners[listener] = (uid, lifetime)
                if mode == .restoring { addedRestoreListener = true }
                // Even on an otherwise unchanged input, a gain read before this
                // registration cannot establish silence for its first callback.
                if Self.watchedDeviceSelectors.contains(listener.selector) {
                    let device = InputDevice(id: listener.device, uid: uid)
                    observedInputs?.remove(device)
                    quietInputs.removeValue(forKey: device)
                }
            }
        }
        // A missed registration, including a renewal whose removal failed,
        // cannot establish a connection for call following. After a repair,
        // read the gain again with the new listeners already installed.
        var observed = Set<AudioDeviceID>()
        var incomplete = Set<AudioDeviceID>()
        var missingTopology = Set<AudioDeviceID>()
        for (listener, uid) in wanted {
            guard let registration = deviceListeners[listener], registration.uid == uid,
                  registration.lifetime.isCurrent(generation), !listenersToRenew.contains(listener) else {
                incomplete.insert(listener.device)
                if Self.inputTopologySelectors.contains(listener.selector) { missingTopology.insert(listener.device) }
                continue
            }
            if Self.watchedDeviceSelectors.contains(listener.selector) {
                observed.insert(listener.device)
            }
        }
        let repaired = topologyGaps.intersection(inventory.devices.map(\.id)).subtracting(missingTopology)
        topologyGaps.formIntersection(inventory.unresolvedIDs.union(inventory.inactiveIDs))
        topologyGaps.formUnion(missingTopology)
        let stale = survivors.filter { repaired.contains($0.device) }
        if !stale.isEmpty {
            listenersToRenew.formUnion(stale)
            incomplete.formUnion(stale.map(\.device))
            scheduleReapply()
        }
        let ready = Set(inventory.devices.filter { observed.contains($0.id) && !incomplete.contains($0.id) })
        if !unverifiedWrites.isEmpty {
            // Losing just the refused property cannot retire a delayed echo
            // on a surviving gain listener. A wholly new set of observers can
            // establish its own baseline without the vanished control.
            let currentClients = installedControlClients()
            for (listener, write) in unverifiedWrites {
                let device = InputDevice(id: listener.device, uid: write.uid)
                if inventory.unresolvedIDs.contains(device.id) || inventory.inactiveIDs.contains(device.id) { continue }
                let observers = currentClients[device] ?? []
                if wanted[listener] == device.uid {
                    // The first mute may have preceded listener installation.
                    unverifiedWrites[listener]?.observers = observers
                } else if !inventory.devices.contains(device) || ready.contains(device) && write.observers.isDisjoint(with: observers) {
                    unverifiedWrites[listener] = nil
                }
            }
        }
        let needsCheck = observedInputs.map { !ready.isSubset(of: $0) } ?? false
        observedInputs = muted ? ready : nil
        quietInputs = quietInputs.filter { ready.contains($0.key) }
        if needsCheck { scheduleReapply() }
        return addedRestoreListener
    }

    private func installedControlClients() -> [InputDevice: Set<UnsafeMutableRawPointer>] {
        var clients: [InputDevice: Set<UnsafeMutableRawPointer>] = [:]
        for (listener, registration) in deviceListeners where Self.watchedDeviceSelectors.contains(listener.selector)
            && registration.lifetime.isCurrent(observationGeneration) {
            let device = InputDevice(id: listener.device, uid: registration.uid)
            clients[device, default: []].insert(registration.lifetime.client)
        }
        return clients
    }

    /// A callback may supply evidence only after its own registration was in
    /// place for a silent reading. Forget queued evidence when that proof lapses.
    private func confirmQuietControls(revision: UInt64? = nil, adding input: InputDevice? = nil) {
        var confirmed: Set<UnsafeMutableRawPointer> = []
        if !quietInputs.isEmpty {
            for (listener, registration) in deviceListeners where Self.watchedDeviceSelectors.contains(listener.selector) {
                let device = InputDevice(id: listener.device, uid: registration.uid)
                if (input == nil || device == input), let quiet = quietInputs[device],
                   registration.lifetime.isCurrent(observationGeneration), listener.wasClosed(in: quiet) {
                    confirmed.insert(registration.lifetime.client)
                }
            }
        }
        callbackLock.withLock {
            if let revision, revision != topologyRevision || observationGeneration != audioGeneration
                || listObservationGeneration != audioGeneration || resetObservationMissing { return }
            if input != nil {
                confirmedControlClients.formUnion(confirmed)
                return
            }
            guard confirmedControlClients != confirmed else { return }
            confirmedControlClients = confirmed
            pendingNotices.controls = pendingNotices.controls.filter { confirmed.contains($0.value) }
        }
    }
}
