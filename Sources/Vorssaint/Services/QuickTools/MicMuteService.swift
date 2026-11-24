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
    /// The feature is on, but the last sweep could not confirm all input controls.
    @Published private(set) var hasUnconfirmedInputs = false
    @Published private(set) var shortcutRegistrationFailed = false

    var controlSymbol: String {
        if hasUnconfirmedInputs { return "exclamationmark.triangle" }
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
    private var retryWork: DispatchWorkItem?
    private var retryDeadline: TimeInterval?
    /// Backoff for temporary Core Audio registration and discovery failures.
    private static let recoveryDelays: [TimeInterval] = [0.25, 1, 3, 8, 20]
    private var inventoryRetryIndex: Int?
    private var inventoryRetryWork: DispatchWorkItem?
    private var missingInputUIDs: Set<String> = []
    private let uptime: () -> TimeInterval
    /// What the last request asked for, kept from the moment it is queued.
    /// `isMuted` and the persisted flag only follow once the sweep has
    /// published, so a device change or a preference sync that lands while a
    /// sweep is still running must re-assert the request in flight, never the
    /// state it is replacing: read from the flag, a mute still being applied
    /// looked like "unmuted, with claims to release" and was silently undone.
    private var wantsMute = UserDefaults.standard.bool(forKey: DefaultsKey.micMuteActive)
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
    private var inputVolumeBlocked = false
    private var inputVolumeLifetime = UUID()

    private init(uptime: @escaping () -> TimeInterval = { ProcessInfo.processInfo.systemUptime }) {
        self.uptime = uptime
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
            if !applyInFlight && wantsMute && !isMuted {
                // A persisted mute has no readings from this launch yet.
                // A pending release stays visible until the sweep completes.
                hasUnconfirmedInputs = true
                isMuted = true
            }
            reapplyIfNeeded()
        } else {
            // Switching the feature off must not strand a muted microphone
            // with no control left to unmute it.
            if wantsMute || hasOutstandingClaims {
                if wantsMute {
                    apply(muted: false, announce: false)
                } else {
                    reapplyIfNeeded()
                }
            }
            isMuted = false
            hasUnconfirmedInputs = false
        }
        syncListeners()
    }

    /// The listeners exist to keep an active mute true while devices come and
    /// go, and to catch a claimed device coming back so it can be released;
    /// they live only as long as one of those is pending.
    private func syncListeners() {
        syncSystemListeners(wanted: wantsMute || isMuted || hasOutstandingClaims)
        let watchDevices = isMuted
        halQueue.async { [weak self] in
            self?.syncDeviceListeners(muted: watchDevices)
        }
    }

    /// Devices this app silenced and has not yet put back, present or not.
    private var hasOutstandingClaims: Bool {
        let defaults = UserDefaults.standard
        let claimed = defaults.stringArray(forKey: DefaultsKey.micMuteMutedDevices)
        return (claimed.map { !$0.isEmpty } ?? defaults.bool(forKey: DefaultsKey.micMuteActive))
            || defaults.data(forKey: DefaultsKey.micMutePendingLegacyControls) != nil
    }

    func suspend() {
        hotkey.unregister()
    }

    func toggle() {
        // An in-flight request can be reversed. Once a release is waiting
        // for the legacy default, pressing its still-active button retries it.
        setMuted(!(wantsMute || (!applyInFlight && isMuted)))
    }

    func setMuted(_ muted: Bool) {
        apply(muted: muted, announce: true)
    }

    var inputVolumeAdjustmentLifetime: UUID? {
        guard !UserDefaults.standard.bool(forKey: DefaultsKey.micMuteActive) else { return nil }
        return inputVolumeLock.withLock { inputVolumeBlocked ? nil : inputVolumeLifetime }
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
                self.cancelInventoryRecovery()
                self.syncDeviceListeners(muted: false)
            }
            syncSystemListeners(wanted: false)
            return
        }
        // Any sweep still in flight loses its right to publish, and this one
        // runs behind it on the same serial queue.
        applyGeneration += 1
        applyInFlight = false
        reapplyPending = false
        wantsMute = false
        let request = UUID()
        inputVolumeLock.withLock { inputVolumeLifetime = request }
        let waitingForLegacyDefault = halQueue.sync {
            let outcome = mustRestore || self.hasOutstandingClaims
                ? self.sweep(muted: false, audioGeneration: self.currentAudioGeneration, request: request) : nil
            self.cancelInventoryRecovery()
            self.syncDeviceListeners(muted: false)
            return outcome?.waitingForLegacyDefault == true
        }
        if !waitingForLegacyDefault { defaults.set(false, forKey: DefaultsKey.micMuteActive) }
        isMuted = false
        hasUnconfirmedInputs = false
        inputVolumeLock.withLock {
            inputVolumeBlocked = false
            inputVolumeLifetime = UUID()
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
        } else if hasOutstandingClaims {
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
    private func apply(muted: Bool, announce: Bool, followingCallApps: Bool = false) {
        applyInFlight = true
        reapplyPending = false
        wantsMute = muted
        let request = UUID()
        inputVolumeLock.withLock {
            inputVolumeBlocked = muted
            inputVolumeLifetime = request
        }
        applyGeneration += 1
        let generation = applyGeneration
        let keepRetriesIfUnmuteFails = isMuted && AppFeature.micMute.isAvailable
        // A reset between the first mute sweep and publication invalidates
        // every device registration, even if the device IDs stay the same.
        if muted && !wantsSystemListeners { syncSystemListeners(wanted: true) }
        halQueue.async { [weak self] in
            guard let self else { return }
            let connection = self.currentAudioGeneration
            let checkAfterRegistration = muted && self.observedInputs == nil
            var outcome = self.sweep(muted: muted, audioGeneration: connection, request: request,
                                     followingCallApps: followingCallApps,
                                     keepRetriesIfUnmuteFails: keepRetriesIfUnmuteFails)
            let effectiveMute = muted && !outcome.followedCallApp
            // Losing the last input can leave nothing to mute. Its old
            // listeners still need to leave so a returning input is observed.
            self.syncDeviceListeners(muted: outcome.applied ? effectiveMute : keepRetriesIfUnmuteFails)
            // Before announcing the first mute, establish call-following baselines
            // with listeners in place, or repair any reading invalidated before registration.
            if checkAfterRegistration, !outcome.quietInputs.isEmpty || !Self.readingsStillHold(outcome),
               connection == self.currentAudioGeneration,
               self.inputVolumeLock.withLock({ self.inputVolumeLifetime == request }) {
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
        let savedVolumes = defaults.dictionary(forKey: DefaultsKey.micMuteSavedVolumes) as? [String: Double]
        let savedChannelVolumes = defaults.dictionary(forKey: DefaultsKey.micMuteSavedChannelVolumes)
            as? [String: [String: Double]]
        let savedControls = defaults.dictionary(forKey: DefaultsKey.micMuteSavedControls)
            as? [String: [String: Double]]
        let savedProtection = defaults.dictionary(forKey: DefaultsKey.micMuteProtectedChannels) as? [String: [UInt32]] ?? [:]
        var protectedChannels = savedProtection
        // Missing means never tracked; an empty list means tracked and
        // owning nothing, and the sweep must keep those two apart.
        let mutedDevices = defaults.stringArray(forKey: DefaultsKey.micMuteMutedDevices)
        if serviceRestarted {
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
        // Convert the old default-input record once, before another input
        // can become the default. Later sweeps restore by UID and control.
        let storedVolume = defaults.double(forKey: DefaultsKey.micMuteSavedVolume)
        // 3.1.15 only saved a scalar above 0.01. Smaller modern per-UID
        // snapshots are valid, but cannot authenticate an old global record.
        let legacyVolume = storedVolume > 0.01 && storedVolume <= 1 ? storedVolume : nil
        var initialControls = savedControls ?? [:]
        var initialClaims = mutedDevices ?? []
        let pending = defaults.data(forKey: DefaultsKey.micMutePendingLegacyControls)
            .flatMap { try? JSONDecoder().decode(LegacyDefaultRestore.self, from: $0) }
        var remaining = pending
        let untrackedLegacyMute = mutedDevices == nil && (pending != nil || defaults.bool(forKey: DefaultsKey.micMuteActive))
        var legacyDefault: InputDevice?
        if let uid = pending?.uid {
            legacyDefault = devices.first { $0.uid == uid }
        } else if untrackedLegacyMute || (!initialClaims.isEmpty && legacyVolume != nil) {
            var id = AudioDeviceID(kAudioObjectUnknown)
            let readDefault = Self.read(AudioObjectID(kAudioObjectSystemObject), kAudioHardwarePropertyDefaultInputDevice, &id)
            if let originalID = pending?.observedDefaultID ?? (readDefault ? id : nil), originalID != kAudioObjectUnknown {
                // Until the UID is known, a different route is a veto. Also
                // remember UIDs seen on other objects in case one reuses this ID.
                var excluded = pending?.excludedUIDs ?? []
                if untrackedLegacyMute {
                    excluded.formUnion(devices.lazy.filter { $0.id != originalID }.map(\.uid))
                }
                if readDefault && id == originalID {
                    if let device = devices.first(where: { $0.id == id }) {
                        if !excluded.contains(device.uid) { legacyDefault = device }
                    } else if untrackedLegacyMute, inventory == nil || inventory?.unresolvedIDs.contains(id) == true,
                              let uid = Self.inputUID(of: id), !excluded.contains(uid) {
                        // Stream enumeration can fail while the default's UID
                        // and controls remain readable. Bind them before a move.
                        let candidate = LegacyDefaultRestore(InputDevice(id: id, uid: uid), gain: pending?.gain ?? legacyVolume)
                        if candidate.isPending && Self.inputUID(of: id) == uid { remaining = candidate }
                    }
                }
                if untrackedLegacyMute, legacyDefault == nil, remaining?.uid == nil {
                    remaining = LegacyDefaultRestore(observedDefaultID: originalID, excludedUIDs: excluded,
                                                     gain: pending?.gain ?? legacyVolume)
                }
            }
        }
        if untrackedLegacyMute && legacyDefault == nil {
            if let remaining, remaining != pending, let data = try? JSONEncoder().encode(remaining) {
                defaults.set(data, forKey: DefaultsKey.micMutePendingLegacyControls)
            }
            // A sweep of other inputs would replace the missing UID list,
            // destroying the only record of which device should be restored.
            return MuteOutcome(applied: false, savedVolumes: savedVolumes ?? [:],
                               savedChannelVolumes: savedChannelVolumes ?? [:], savedControls: initialControls,
                               mutedDevices: [], failed: true, waitingForLegacyDefault: true)
        }
        var migratedDefault = false
        if let device = legacyDefault, pending != nil || mutedDevices == nil || initialClaims.contains(device.uid) {
            if pending != nil || (initialControls[device.uid] == nil && savedVolumes?[device.uid] == nil
                                  && savedChannelVolumes?[device.uid] == nil) {
                var legacy = pending.flatMap { $0.uid == device.uid ? $0 : nil }
                    ?? LegacyDefaultRestore(device, gain: pending?.gain ?? legacyVolume)
                let controls = legacy.resolve(on: device.id, recorded: mutedDevices != nil && pending == nil)
                remaining = legacy.isPending ? legacy : nil
                if !controls.isEmpty {
                    initialControls[device.uid, default: [:]].merge(controls) { saved, _ in saved }
                    migratedDefault = true
                }
                if remaining != nil || initialControls[device.uid] != nil {
                    if !initialClaims.contains(device.uid) { initialClaims.append(device.uid) }
                } else if pending != nil {
                    initialClaims.removeAll { $0 == device.uid }
                }
            }
        }
        // Convert the stereo record before any subset of its controls can
        // finish restoring. The old UID level came from the first readable
        // scalar: master, then channels 1 and 2. A level distinct from the
        // first saved channel identifies the master even while it is absent.
        for device in devices where initialClaims.contains(device.uid) && initialControls[device.uid] == nil {
            guard let channels = savedChannelVolumes?[device.uid],
                  let firstChannel = channels["1"] ?? channels["2"] else { continue }
            var controls: [String: Double] = [:]
            for address in Self.legacyGainAddresses {
                if let channel = channels[String(address.mElement)] {
                    controls[Self.controlKey(address)] = channel
                } else if address.mElement == kAudioObjectPropertyElementMain, let master = savedVolumes?[device.uid] {
                    // A channel-only input saved that same channel as its UID
                    // level. An unrelated live master must keep its own gain.
                    if Self.controlValuesMatch(master, firstChannel) {
                        guard let current = Self.controlValue(of: device.id, at: address),
                              current <= Double(MicMuteSupport.residualGainLimit) else { continue }
                    }
                    controls[Self.controlKey(address)] = master
                }
            }
            initialControls[device.uid] = controls
        }
        var evidence = notices.controls
        var checksLeft = trackControls && followingCallApps && observedInputs?.isEmpty == false ? 3 : 0
        var invalidated = false
        func isCurrent(_ device: InputDevice) -> Bool {
            // An object ID can be recycled before the device-list notification arrives.
            guard !invalidated, Self.inputUID(of: device.id) == device.uid,
                  inputVolumeLock.withLock({ inputVolumeLifetime == request }),
                  callbackLock.withLock({ self.audioGeneration == audioGeneration && topologyRevision == revision })
            else {
                invalidated = true
                return false
            }
            return true
        }
        var waitingForLegacyGains: Set<String> = []
        if requestedMute, let savedVolumes {
            for device in devices where initialClaims.contains(device.uid) && initialControls[device.uid] == nil {
                guard let previous = protectedChannels[device.uid], savedVolumes[device.uid] != nil else { continue }
                var elements = Set(previous)
                // An earlier unmute found an unreadable legacy channel. A
                // reapply must resolve its original gain before zeroing aliases.
                let volume = MicMuteSupport.volumeToRestore(uid: device.uid, saved: savedVolumes)
                let snapshot = Self.legacyGainSnapshot(volume, on: device.id, observed: &elements)
                guard isCurrent(device) else { break }
                if let snapshot {
                    if !snapshot.isEmpty { initialControls[device.uid] = snapshot }
                    elements.remove(kAudioObjectPropertyElementMain)
                } else {
                    waitingForLegacyGains.insert(device.uid)
                }
                protectedChannels[device.uid] = elements.isEmpty ? nil : elements.sorted()
            }
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
        var follow = false
        var outcome: MuteOutcome
        while true {
            let levels = partial?.savedVolumes ?? savedVolumes ?? [:]
            let channels = partial?.savedChannelVolumes ?? savedChannelVolumes ?? [:]
            let controls = partial?.savedControls ?? initialControls
            let claims = partial?.mutedDevices ?? initialClaims
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
                    && inputVolumeLock.withLock { inputVolumeLifetime == request }
                    && canFollowCallApps(in: audioGeneration, revision: revision)
            }
            if !requestedMute || follow {
                // Known controls can be released even while another legacy
                // reading is pending. Never run a fallback for that unknown.
                let targets = remaining.map { pending in
                    devices.filter { $0.uid != pending.uid || controls[$0.uid] != nil }
                } ?? devices
                outcome = Self.unmute(targets, savedVolumes: levels, savedChannelVolumes: channels, savedControls: controls,
                                      mutedDevices: claims, protectedChannels: &protectedChannels, isCurrent: isCurrent)
                if follow && !outcome.applied {
                    // A rejected automatic release keeps mute active. A
                    // pending reapply still needs the complete pre-mute mix.
                    outcome.savedControls.merge(controls) { _, original in original }
                }
                outcome.followedCallApp = follow
                break
            }
            let authorize = MuteAuthorization(isCurrent: isCurrent, beforeWrite: { listener, quiet in
                evidence = takeLateNotices(beforeWriting: listener, quiet: quiet, checking: checking)
                return !invalidated && evidence.isEmpty
            }, didWrite: didWrite, verifiedQuiet: verifiedQuiet)
            // Modern setters can move aliases on the same mic. Wait until
            // its legacy readings are resolved before making those writes.
            let targets = devices.filter { $0.uid != remaining?.uid && !waitingForLegacyGains.contains($0.uid) }
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
        if muted && !waitingForLegacyGains.isEmpty {
            outcome.failed = true
            outcome.applied = true
        }
        if let uid = remaining?.uid {
            if !outcome.mutedDevices.contains(uid) { outcome.mutedDevices.append(uid) }
            if devices.contains(where: { $0.uid == uid }) {
                outcome.failed = true
                if muted { outcome.applied = true }
            }
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
        let releaseInterrupted = follow && (invalidated || audioGeneration != currentAudioGeneration)
        var record = partial
        let restoredControls = !muted && (outcome.savedControls != (savedControls ?? [:]) || protectedChannels != savedProtection)
        let migrationChanged = migratedDefault || remaining != pending
        if !releaseInterrupted && (outcome.applied || partial != nil || migrationChanged || restoredControls) {
            record = outcome
        }
        if let record {
            if savedVolumes != record.savedVolumes {
                defaults.set(record.savedVolumes, forKey: DefaultsKey.micMuteSavedVolumes)
            }
            if savedChannelVolumes != record.savedChannelVolumes {
                defaults.set(record.savedChannelVolumes, forKey: DefaultsKey.micMuteSavedChannelVolumes)
            }
            if !releaseInterrupted && protectedChannels != savedProtection {
                defaults.set(protectedChannels, forKey: DefaultsKey.micMuteProtectedChannels)
            }
            if savedControls != record.savedControls {
                defaults.set(record.savedControls, forKey: DefaultsKey.micMuteSavedControls)
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
            if mutedDevices != record.mutedDevices {
                defaults.set(record.mutedDevices, forKey: DefaultsKey.micMuteMutedDevices)
            }
            // A more specific record or a completed restore can also retire
            // the old gain. A returning microphone may become the next default.
            if legacyVolume != nil, let uid = legacyDefault?.uid, remaining?.uid != uid,
               migratedDefault || record.savedControls[uid] != nil || record.savedVolumes[uid] != nil
                || record.savedChannelVolumes[uid] != nil || !record.mutedDevices.contains(uid) {
                defaults.removeObject(forKey: DefaultsKey.micMuteSavedVolume)
            }
        }
        // The old UID's snapshot is durable before the replacement is enumerated.
        // Limit this immediate retry even when a driver keeps changing its identity.
        if invalidated, canRescan, audioGeneration == currentAudioGeneration,
           inputVolumeLock.withLock({ inputVolumeLifetime == request }) {
            if requestedMute && !follow { updateRetries(outcome.retries) }
            var fresh = sweep(muted: requestedMute, audioGeneration: audioGeneration, request: request,
                              followingCallApps: followingCallApps,
                              keepRetriesIfUnmuteFails: keepRetriesIfUnmuteFails, canRescan: false)
            if !follow && !fresh.followedCallApp && outcome.applied { fresh.applied = true }
            return fresh
        }
        if releaseInterrupted {
            outcome.followedCallApp = false
            return outcome
        }
        // A failed manual unmute keeps the active mute's retry. Disabling
        // the feature and teardown always cancel it, even if restoration fails.
        if muted || outcome.applied || !keepRetriesIfUnmuteFails {
            updateRetries(outcome.applied || keepRetriesIfUnmuteFails ? outcome.retries : [:])
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
    private func updateRetries(_ updated: ControlRetries) {
        retries = updated
        let next = updated.values.compactMap { $0.values.compactMap(\.scheduledDeadline).min() }.min()
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
            if reapplyPending || outcome.checkNewInputs {
                reapplyPending = false
                reapplyIfNeeded()
            }
        }
        let controlsConfirmed = callbackLock.withLock {
            audioGeneration == self.audioGeneration && outcome.confirmedInputRevision == topologyRevision
        }
        let failure = outcome.failed || (muted && !controlsConfirmed)
        // A disabled feature clears its active flag after the restore has
        // read it. That flag can be the only record left by an older version.
        if outcome.waitingForLegacyDefault {
            // The pre-UID active flag is still the restore record. Keep an
            // available feature visibly unconfirmed and watch for recovery.
            let available = AppFeature.micMute.isAvailable
            wantsMute = muted && available
            if isMuted != available { isMuted = available }
            inputVolumeLock.withLock { inputVolumeBlocked = isMuted }
            syncListeners()
        } else if outcome.applied || (!muted && !AppFeature.micMute.isAvailable) {
            wantsMute = muted
            inputVolumeLock.withLock { inputVolumeBlocked = muted }
            if isMuted != muted { isMuted = muted }
            if UserDefaults.standard.bool(forKey: DefaultsKey.micMuteActive) != muted {
                UserDefaults.standard.set(muted, forKey: DefaultsKey.micMuteActive)
            }
            syncListeners()
        } else {
            // Nothing was reached, so the request is dropped as it always was:
            // the published state stays what it is, and so does the wanted one.
            wantsMute = isMuted
            inputVolumeLock.withLock { inputVolumeBlocked = isMuted }
            if !isMuted && !hasOutstandingClaims { syncSystemListeners(wanted: false) }
        }
        let unconfirmed = isMuted && !controlsConfirmed
        let newlyUnconfirmed = unconfirmed && !hasUnconfirmedInputs
        if hasUnconfirmedInputs != unconfirmed { hasUnconfirmedInputs = unconfirmed }
        if newlyUnconfirmed || (failure && (announce || outcome.followedCallApp)) {
            NotchService.shared.retractMicrophoneNotice()
        }
        guard announce || outcome.followedCallApp else { return }
        // Report a known failure even when no device could be changed. The
        // whole sentence matters, and it is longer than the island's wings.
        if failure {
            QuickToolHUD.show(icon: "exclamationmark.triangle",
                              message: muted ? L10n.shared.s.micMutePartialHUD : L10n.shared.s.micUnmutePartialHUD)
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
        var savedControls: [String: [String: Double]]
        var mutedDevices: [String]
        /// A device this sweep had to reach and could not, next to ones it did.
        var failed = false
        var waitingForLegacyDefault = false
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
            let migrating = owned.contains(device.uid) && savedControls[device.uid] == nil
            let switchSnapshot = migrating ? legacySwitchSnapshot(device, savedVolumes, savedChannelVolumes) : nil
            var snapshot = savedControls[device.uid] ?? switchSnapshot ?? [:]
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
                    snapshot[key] = migrating && switchSnapshot == nil
                        ? legacyRestoreValue(current, at: address, uid: device.uid,
                                             savedVolumes: savedVolumes,
                                             savedChannelVolumes: savedChannelVolumes)
                        : current
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
            var submitted: [String: (address: AudioObjectPropertyAddress, correctedSmallGain: Bool)] = [:]
            for address in writable {
                let target: Double = address.mSelector == kAudioDevicePropertyMute ? 1 : 0
                switch writeControl(target, of: device, at: address, isCurrent: authorize.isCurrent,
                                    quietBeforeWrite: quietBeforeWrite, read: read, authorize: authorize) {
                case .submitted(let possiblyChanged, let correctedSmallGain):
                    changed = changed || possiblyChanged
                    submitted[controlKey(address)] = (address, correctedSmallGain)
                    quietBeforeWrite = nil
                case .unchanged: break
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
                               isCurrent: (InputDevice) -> Bool) -> MuteOutcome {
        let present = devices.map(\.uid)
        var outcome = MuteOutcome(applied: false,
                                  savedVolumes: savedVolumes,
                                  savedChannelVolumes: savedChannelVolumes,
                                  savedControls: savedControls,
                                  mutedDevices: MicMuteSupport.absentClaims(recorded: mutedDevices,
                                                                            present: present))
        let targets = Set(MicMuteSupport.restoreTargets(recorded: mutedDevices, present: present))
        var attempted = false
        for device in devices where targets.contains(device.uid) {
            let saved: [String: Double]
            var channels = Set(protectedChannels[device.uid] ?? [])
            if let snapshot = savedControls[device.uid] ?? legacySwitchSnapshot(device, savedVolumes, savedChannelVolumes) {
                saved = snapshot
            } else {
                let hasLevel = savedVolumes[device.uid] != nil || savedChannelVolumes[device.uid] != nil
                if !hasLevel {
                    let muteSwitch = readMuteSwitch(of: device.id, channelCount: readInputChannelCount(of: device.id)).value
                    switch MicMuteSupport.restoreNeed(muteSwitch: muteSwitch, volume: inputVolume(of: device.id)) {
                    case .unreadable:
                        outcome.mutedDevices.append(device.uid)
                        continue
                    case .alreadyAudible, .restore(_, false):
                        if isCurrent(device) {
                            protectedChannels[device.uid] = nil
                            outcome.applied = true
                        } else {
                            outcome.mutedDevices.append(device.uid)
                        }
                        continue
                    case .restore(_, true): break
                    }
                }
                let volume = MicMuteSupport.volumeToRestore(uid: device.uid, saved: savedVolumes)
                let snapshot = legacyGainSnapshot(volume, on: device.id, observed: &channels)
                guard isCurrent(device) else {
                    outcome.mutedDevices.append(device.uid)
                    continue
                }
                guard let snapshot else {
                    attempted = true
                    outcome.failed = true
                    outcome.mutedDevices.append(device.uid)
                    if !channels.isEmpty { protectedChannels[device.uid] = channels.sorted() }
                    continue
                }
                channels.remove(kAudioObjectPropertyElementMain)
                // A channel-only input can already be open at its user's levels.
                if snapshot.isEmpty {
                    outcome.applied = true
                    outcome.savedVolumes.removeValue(forKey: device.uid)
                    outcome.savedChannelVolumes.removeValue(forKey: device.uid)
                    protectedChannels[device.uid] = nil
                    continue
                }
                saved = snapshot
            }
            attempted = true
            let outstanding = restoreControls(saved, on: device, protecting: &channels,
                                              recordedLevels: savedChannelVolumes[device.uid], isCurrent: isCurrent)
            let needsMaster = outstanding.keys.compactMap(controlAddress).contains(where: isMasterGain)
            protectedChannels[device.uid] = needsMaster && !channels.isEmpty ? channels.sorted() : nil
            if !saved.isEmpty && outstanding.isEmpty {
                outcome.applied = true
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

    private static func inputInventory() -> InputInventory? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject),
                                             &address, 0, nil, &size) == noErr else { return nil }
        var inventory = InputInventory()
        guard size > 0 else { return inventory }
        var deviceIDs = [AudioDeviceID](repeating: 0, count: Int(size) / MemoryLayout<AudioDeviceID>.size)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject),
                                         &address, 0, nil, &size, &deviceIDs) == noErr else { return nil }

        for deviceID in deviceIDs.prefix(Int(size) / MemoryLayout<AudioDeviceID>.size) {
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

    /// The UID-only gain format lowered scalars 0, 1 and 2. Before we can
    /// assign a target to an unreadable channel, keep the observed elements,
    /// including 0 for a master that can disappear between attempts.
    private static func legacyGainSnapshot(_ volume: Float, on device: AudioDeviceID,
                                           observed: inout Set<UInt32>) -> [String: Double]? {
        observeWritableChannels(on: device, into: &observed)
        var master = legacyGainAddresses[0]
        if AudioObjectHasProperty(device, &master) { observed.insert(master.mElement) }
        let addresses = legacyGainAddresses.filter { observed.contains($0.mElement) }
        guard !addresses.isEmpty else { return nil }
        var targets: [String: Double] = [:]
        for address in addresses {
            if !isMasterGain(address) {
                guard let current = controlValue(of: device, at: address) else { return nil }
                if current > Double(MicMuteSupport.residualGainLimit) { continue }
            }
            targets[controlKey(address)] = Double(volume)
        }
        return targets
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

    private static func observeWritableChannels(on device: AudioDeviceID, into channels: inout Set<UInt32>) {
        for var address in volumeAddresses(of: device) where address.mElement != 0 && AudioObjectHasProperty(device, &address) {
            var settable = DarwinBoolean(false)
            if AudioObjectIsPropertySettable(device, &address, &settable) != noErr || settable.boolValue {
                channels.insert(address.mElement)
            }
        }
    }

    /// A released channel belongs to the user again. Remember its address
    /// across attempts, and capture its live value only when writing a master.
    private static func restoreControls(_ saved: [String: Double], on device: InputDevice,
                                        protecting channels: inout Set<UInt32>, recordedLevels: [String: Double]?,
                                        isCurrent: (InputDevice) -> Bool) -> [String: Double] {
        var targets = saved
        let savedAddresses = saved.keys.compactMap(controlAddress)
        let masters = savedAddresses.filter(isMasterGain).sorted { controlRestoreOrder($0) < controlRestoreOrder($1) }
        let previousChannels = channels
        var wroteMaster = false
        if !masters.isEmpty {
            for address in savedAddresses where address.mElement != 0 && address.mSelector == kAudioDevicePropertyVolumeScalar {
                channels.insert(address.mElement)
            }
            observeWritableChannels(on: device.id, into: &channels)
            // Earlier records included read-only meters among their levels.
            // Only an independently writable channel needs compensation.
            let candidates = channels.union(recordedLevels?.keys.compactMap { UInt32($0) } ?? [])
            func captureLiveChannels(into live: inout [String: Double]) -> Bool {
                for element in candidates where element != 0 {
                    var address = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyVolumeScalar,
                                                             mScope: kAudioDevicePropertyScopeInput, mElement: element)
                    let key = controlKey(address)
                    guard targets[key] == nil else { continue }
                    var settable = DarwinBoolean(false)
                    guard AudioObjectHasProperty(device.id, &address),
                          AudioObjectIsPropertySettable(device.id, &address, &settable) == noErr else { return false }
                    if !settable.boolValue && !channels.contains(element) { continue }
                    guard settable.boolValue, let current = controlValue(of: device.id, at: address) else { return false }
                    live[key] = current
                }
                return true
            }
            for master in masters {
                guard let value = saved[controlKey(master)] else { continue }
                var live: [String: Double] = [:]
                let write = writeControl(value, of: device, at: master, isCurrent: isCurrent,
                                         prepare: { captureLiveChannels(into: &live) })
                if case .submitted = write {
                    wroteMaster = true
                    targets.merge(live) { saved, _ in saved }
                }
            }
        }
        let addresses = targets.keys.compactMap(controlAddress).sorted {
            let left = controlRestoreOrder($0)
            let right = controlRestoreOrder($1)
            return left == right ? $0.mElement < $1.mElement : left < right
        }
        for address in addresses where !isMasterGain(address) {
            if let value = targets[controlKey(address)] {
                _ = writeControl(value, of: device, at: address, isCurrent: isCurrent)
            }
        }
        var outstanding = targets
        for address in addresses {
            let key = controlKey(address)
            if let expected = targets[key], let current = controlValue(of: device.id, at: address),
               controlValuesMatch(current, expected) { outstanding.removeValue(forKey: key) }
        }
        // A replacement cannot discharge this UID's obligations. Only a
        // submitted master could also have changed its channels before unplug.
        guard isCurrent(device) else {
            if !wroteMaster { channels = previousChannels }
            return wroteMaster ? targets : saved
        }
        return outstanding
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

    private enum ControlWrite {
        case unchanged, interrupted
        case submitted(possiblyChanged: Bool, correctedSmallGain: Bool)
    }

    /// Reports a possible change, not proof of the requested state. A driver
    /// may accept and ignore a write, or make the control unreadable afterwards.
    /// Callers keep the snapshot and verify the final state separately.
    private static func writeControl(_ value: Double, of input: InputDevice,
                                      at address: AudioObjectPropertyAddress,
                                      isCurrent: (InputDevice) -> Bool,
                                      prepare: () -> Bool = { true },
                                      quietBeforeWrite: Set<DeviceListener>? = nil,
                                      read: ControlReader = MicMuteService.controlValue,
                                      authorize: MuteAuthorization? = nil) -> ControlWrite {
        let device = input.id
        guard value.isFinite, value >= 0, value <= 1,
              address.mSelector != kAudioDevicePropertyMute || value == 0 || value == 1,
              let current = read(device, address) else { return .unchanged }
        if current == Double(Float(value)) { return .unchanged }
        var address = address
        var settable = DarwinBoolean(false)
        guard AudioObjectIsPropertySettable(device, &address, &settable) == noErr,
              settable.boolValue else { return .unchanged }
        // This is the last software decision before either HAL setter. The
        // callback lock is released before calling a potentially reentrant driver.
        let listener = DeviceListener(device: device, selector: address.mSelector, scope: address.mScope, element: address.mElement)
        guard prepare(), isCurrent(input), authorize?.beforeWrite(listener, quietBeforeWrite) != false else { return .interrupted }
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

    /// Before 3.2 only the default input was touched. A successful master
    /// mute ended the operation. Its fallback wrote scalar elements 0, 1, 2.
    private struct LegacyDefaultRestore: Codable, Equatable {
        let uid: String?
        let observedDefaultID: AudioDeviceID?
        let excludedUIDs: Set<String>?
        let gain: Double?
        var checkSwitch: Bool
        var firstScalar: UInt32?
        var unreadScalars: Set<UInt32>
        var residualScalars: Set<UInt32> = []

        init(observedDefaultID: AudioDeviceID, excludedUIDs: Set<String>, gain: Double?) {
            uid = nil
            self.observedDefaultID = observedDefaultID
            self.excludedUIDs = excludedUIDs
            self.gain = gain
            checkSwitch = false
            unreadScalars = []
        }

        init(_ device: InputDevice, gain: Double?) {
            uid = device.uid
            observedDefaultID = nil
            excludedUIDs = nil
            self.gain = gain
            var main = Self.mainSwitch
            checkSwitch = AudioObjectHasProperty(device.id, &main)
            let elements = legacyGainAddresses.compactMap { address -> UInt32? in
                var address = address
                return AudioObjectHasProperty(device.id, &address) ? address.mElement : nil
            }
            firstScalar = elements.first
            unreadScalars = Set(elements)
        }

        private static var mainSwitch: AudioObjectPropertyAddress {
            AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyMute, mScope: kAudioDevicePropertyScopeInput,
                                       mElement: kAudioObjectPropertyElementMain)
        }

        var isPending: Bool { checkSwitch || firstScalar != nil || !unreadScalars.isEmpty }

        mutating func resolve(on device: AudioDeviceID, recorded: Bool) -> [String: Double] {
            // Only the default switch was changed if the native setter worked.
            // v3.4.3 recorded its UID alone, never a global gain for that mute.
            var main = Self.mainSwitch
            var settable = DarwinBoolean(false)
            if checkSwitch, recorded {
                clear()
                return [controlKey(main): 0]
            }
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

    /// Versions that tracked UIDs but no control snapshots tried the master
    /// switch first. A claimed native mic without saved levels only owes that
    /// switch, even when another client has already released it.
    private static func legacySwitchSnapshot(_ device: InputDevice, _ savedVolumes: [String: Double],
                                             _ savedChannelVolumes: [String: [String: Double]]) -> [String: Double]? {
        guard savedVolumes[device.uid] == nil, savedChannelVolumes[device.uid] == nil else { return nil }
        var main = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyMute,
                                              mScope: kAudioDevicePropertyScopeInput,
                                              mElement: kAudioObjectPropertyElementMain)
        guard AudioObjectHasProperty(device.id, &main) else { return nil }
        return [controlKey(main): 0]
    }

    /// An already-owned device may have been muted by a version without
    /// control snapshots. Carry its old restore obligation into the first
    /// snapshot instead of saving the mute or zero gain left by that version.
    private static func legacyRestoreValue(_ current: Double, at address: AudioObjectPropertyAddress,
                                           uid: String, savedVolumes: [String: Double],
                                           savedChannelVolumes: [String: [String: Double]]) -> Double {
        guard address.mSelector == kAudioDevicePropertyVolumeScalar, address.mElement <= 2 else { return current }
        if address.mElement != kAudioObjectPropertyElementMain {
            if let channels = savedChannelVolumes[uid] {
                // A pre-snapshot stereo record omitted channels already at zero.
                return channels[String(address.mElement)] ?? current
            }
            if current > Double(MicMuteSupport.residualGainLimit) { return current }
        }
        if let saved = savedVolumes[uid], MicMuteSupport.shouldSaveVolume(Float(saved)) { return saved }
        return current > 0 ? current : Double(MicMuteSupport.fallbackVolume)
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

    /// Runs on `halQueue`. Between device-list notifications, leave working
    /// listeners in place when the input and its controls stay the same.
    private func syncDeviceListeners(muted: Bool) {
        let generation = currentAudioGeneration
        defer { confirmQuietControls() }
        // Keep existing registrations on a failed read. A later successful
        // reconciliation and quiet reading must precede any automatic unmute.
        guard let inventory = muted ? Self.inputInventory() : InputInventory() else {
            observedInputs = []
            quietInputs.removeAll()
            return
        }
        var wanted: [DeviceListener: String] = [:]
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
        for (listener, uid) in wanted where deviceListeners[listener] == nil {
            var address = listener.address
            if let lifetime = addListener(listener.device, &address, generation: generation) {
                deviceListeners[listener] = (uid, lifetime)
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
