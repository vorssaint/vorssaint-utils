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
/// No captured audio is inspected, and the published state reports this
/// feature's state, not proof that every app receives silence.
/// Device, default-input and per-device level changes reapply the request, and
/// the state survives relaunches. A device this app changed stays its to
/// restore even while unplugged: it gets its saved level back when it returns.
final class MicMuteService: ObservableObject {
    static let shared = MicMuteService()

    @Published private(set) var isMuted = false
    @Published private(set) var shortcutRegistrationFailed = false

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
    private var retries: [String: MicMuteSupport.Retry] = [:]
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
            if !applyInFlight { isMuted = wantsMute }
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
                UserDefaults.standard.set(false, forKey: DefaultsKey.micMuteActive)
            }
            isMuted = false
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
        !(UserDefaults.standard.stringArray(forKey: DefaultsKey.micMuteMutedDevices) ?? []).isEmpty
    }

    func suspend() {
        hotkey.unregister()
    }

    func toggle() {
        setMuted(!wantsMute)
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
        halQueue.sync {
            if mustRestore || self.hasOutstandingClaims {
                _ = self.sweep(muted: false, audioGeneration: self.currentAudioGeneration)
            }
            self.cancelInventoryRecovery()
            self.syncDeviceListeners(muted: false)
        }
        defaults.set(false, forKey: DefaultsKey.micMuteActive)
        isMuted = false
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

    private func callAppOpenings(in devices: inout [InputDevice], owned: Set<String>,
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
                return current.gain == .audible && value > Double(MicMuteSupport.silenceThreshold)
            }
        }
        var candidates: [InputDevice: ControlNotices] = [:]
        for device in devices {
            let found = openings(device, from: notices)
            if !found.isEmpty { candidates[device] = found }
        }
        guard !candidates.isEmpty else { return [:] }
        let captured = Self.devicesCapturedByOtherProcesses()
        // IDs can be reused while the audio server answers. Both the decision
        // and the subsequent writes must address the devices that are here now.
        devices = Self.inputDevices()
        var confirmed: ControlNotices = [:]
        // Revalidate the same controls that opened before the process query.
        // New deliveries during that query get their own read.
        for device in devices where captured.contains(device.id) {
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
            let outcome = self.sweep(muted: muted, audioGeneration: connection,
                                     followRequest: followingCallApps ? request : nil,
                                     keepRetriesIfUnmuteFails: keepRetriesIfUnmuteFails)
            let effectiveMute = muted && !outcome.followedCallApp
            // Losing the last input can leave nothing to mute. Its old
            // listeners still need to leave so a returning input is observed.
            self.syncDeviceListeners(muted: outcome.applied ? effectiveMute : keepRetriesIfUnmuteFails)
            DispatchQueue.main.async {
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
    private func sweep(muted requestedMute: Bool, audioGeneration: UInt64, followRequest: UUID? = nil,
                       keepRetriesIfUnmuteFails: Bool = false) -> MuteOutcome {
        let serviceRestarted = observationGeneration != audioGeneration
        let defaults = UserDefaults.standard
        let savedVolumes = defaults.dictionary(forKey: DefaultsKey.micMuteSavedVolumes) as? [String: Double]
        let savedChannelVolumes = defaults.dictionary(forKey: DefaultsKey.micMuteSavedChannelVolumes)
            as? [String: [String: Double]]
        let savedControls = defaults.dictionary(forKey: DefaultsKey.micMuteSavedControls)
            as? [String: [String: Double]]
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
        let inventory = Self.inputInventory()
        let initialMute = requestedMute && observedDeviceListChange == nil && observedInputs == nil
        let renewingListeners = requestedMute && observeTopology(revision: revision, objects: notices.topology)
        var devices = inventory?.devices ?? []
        let trackControls = requestedMute && defaults.bool(forKey: DefaultsKey.micMuteFollowCallApps)
            && canFollowCallApps(in: audioGeneration)
        let legacyVolume = defaults.double(forKey: DefaultsKey.micMuteSavedVolume)
        var evidence = notices.controls
        var checksLeft = trackControls && followRequest != nil && observedInputs?.isEmpty == false ? 3 : 0
        var invalidated = false
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
        func didWrite(_ listener: DeviceListener, readBack: Double?, matchedTarget: Bool) {
            guard !matchedTarget || suspended[listener] != nil || unverifiedWrites[listener] != nil else { return }
            if !matchedTarget, let device = devices.first(where: { $0.id == listener.device }) {
                if writeObservers == nil { writeObservers = installedControlClients() }
                unverifiedWrites[listener] = UnverifiedWrite(uid: device.uid, observers: writeObservers?[device] ?? [])
            }
            callbackLock.withLock {
                if !matchedTarget {
                    // A driver can echo an ignored setter through any alias.
                    suspendControls(on: listener.device, keeping: [])
                    pendingNotices.controls = pendingNotices.controls.filter { $0.key.device != listener.device }
                }
                // A small residual can establish silence on this control even
                // when the driver did not apply the exact value we requested.
                if let readBack, listener.isClosed(readBack) { confirmSilence(listener) }
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
            let superseded = control != nil && inputVolumeLock.withLock { inputVolumeLifetime != followRequest }
            return callbackLock.withLock {
                if control != nil && (superseded || audioGeneration != self.audioGeneration || revision != topologyRevision) {
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
            let controls = partial?.savedControls ?? savedControls ?? [:]
            let claims = partial?.mutedDevices ?? mutedDevices
            checking = checksLeft > 0
            var readings: [InputDevice: InputControls] = [:]
            if checking, let followRequest {
                checksLeft -= 1
                let opened = callAppOpenings(in: &devices, owned: Set(mutedDevices ?? []), notices: evidence, read: readForMute,
                                             readings: &readings)
                evidence = takeLateNotices()
                if !evidence.isEmpty {
                    evidence.merge(opened) { delivered, _ in delivered }
                    continue
                }
                follow = !opened.isEmpty && defaults.bool(forKey: DefaultsKey.micMuteFollowCallApps)
                    && inputVolumeLock.withLock { inputVolumeLifetime == followRequest }
                    && canFollowCallApps(in: audioGeneration, revision: revision)
            }
            if !requestedMute || follow {
                outcome = Self.unmute(devices, savedVolumes: levels, savedChannelVolumes: channels, savedControls: controls,
                                      mutedDevices: claims, legacyVolume: legacyVolume)
                outcome.followedCallApp = follow
                break
            }
            let authorize = MuteAuthorization(beforeWrite: { listener, quiet in
                guard followRequest != nil else { return true }
                evidence = takeLateNotices(beforeWriting: listener, quiet: quiet, checking: checking)
                return !invalidated && evidence.isEmpty
            }, didWrite: didWrite, verifiedQuiet: verifiedQuiet)
            outcome = Self.mute(devices, retries: partial?.retries ?? retries, now: uptime(), savedVolumes: levels,
                                savedChannelVolumes: channels, savedControls: controls, mutedDevices: claims,
                                legacyVolume: legacyVolume, trackControls: trackControls, readings: readings,
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
        if muted {
            // A control can open between the mute and its listener's installation
            // or renewal. Recheck once after subscribing to cover that interval.
            outcome.checkNewInputs = invalidated || renewingListeners || (initialMute && !outcome.quietInputs.isEmpty)
            quietInputs = outcome.quietInputs.filter { observedInputs?.contains($0.key) == true }
        } else {
            if outcome.applied || !keepRetriesIfUnmuteFails {
                quietInputs.removeAll()
                unverifiedWrites.removeAll()
                observedInputs = nil
                observedDeviceListChange = nil
            } else {
                // A failed restore can still change individual controls. Keep
                // only quiet inputs still present, with their actual switch state.
                quietInputs = devices.reduce(into: [:]) { result, device in
                    guard quietInputs[device] != nil else { return }
                    let current = Self.inputControls(device.id, readSwitch: true)
                    if current.isSilenced { result[device] = current }
                }
            }
        }
        // A sweep that reached nothing leaves the record alone: it is what a
        // later unmute needs to put every level back. A record that did not
        // change is not written again: every write tells the whole app that
        // preferences changed, and a re-assert usually changes nothing.
        // An automatic release interrupted by a reset must not discard the
        // saved levels needed to reassert the user's original mute.
        let releaseInterrupted = follow && audioGeneration != currentAudioGeneration
        var record = partial
        if !releaseInterrupted && (outcome.applied || partial != nil) { record = outcome }
        if let record {
            if savedVolumes != record.savedVolumes {
                defaults.set(record.savedVolumes, forKey: DefaultsKey.micMuteSavedVolumes)
            }
            if savedChannelVolumes != record.savedChannelVolumes {
                defaults.set(record.savedChannelVolumes, forKey: DefaultsKey.micMuteSavedChannelVolumes)
            }
            if savedControls != record.savedControls {
                defaults.set(record.savedControls, forKey: DefaultsKey.micMuteSavedControls)
            }
            if mutedDevices != record.mutedDevices {
                defaults.set(record.mutedDevices, forKey: DefaultsKey.micMuteMutedDevices)
            }
        }
        if releaseInterrupted {
            outcome.followedCallApp = false
            return outcome
        }
        // A failed manual unmute keeps the active mute's retry. Disabling
        // the feature and teardown always cancel it, even if restoration fails.
        if muted || outcome.applied || !keepRetriesIfUnmuteFails {
            updateRetries(outcome.retries)
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
    private func updateRetries(_ updated: [String: MicMuteSupport.Retry]) {
        retries = updated
        let next = updated.values.compactMap(\.deadline).min()
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
        if outcome.applied {
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
        guard announce || outcome.followedCallApp else { return }
        // Report a known failure even when no device could be changed. The
        // whole sentence matters, and it is longer than the island's wings.
        if outcome.failed {
            NotchService.shared.retractMicrophoneNotice()
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
        var followedCallApp = false
        var checkNewInputs = false
        var quietInputs: [InputDevice: InputControls] = [:]
        var retries: [String: MicMuteSupport.Retry] = [:]
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
            selector == kAudioDevicePropertyMute ? value == 1 : value <= Double(MicMuteSupport.silenceThreshold)
        }

        func wasClosed(in controls: InputControls) -> Bool {
            if selector == kAudioDevicePropertyMute { return controls.mutedElements?.contains(element) == true }
            return controls.silentGains.contains(MicMuteService.controlKey(address))
        }

        var address: AudioObjectPropertyAddress {
            AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: element)
        }
    }

    private struct MuteAuthorization {
        let beforeWrite: (DeviceListener, Set<DeviceListener>?) -> Bool
        let didWrite: (DeviceListener, Double?, Bool) -> Void
        let verifiedQuiet: (InputDevice, InputControls) -> Bool
    }

    private static func mute(_ devices: [InputDevice],
                             retries: [String: MicMuteSupport.Retry], now: TimeInterval,
                             savedVolumes: [String: Double],
                             savedChannelVolumes: [String: [String: Double]],
                             savedControls: [String: [String: Double]],
                             mutedDevices: [String]?,
                             legacyVolume: Double, trackControls: Bool,
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
            let initial = readings[device] ?? inputControls(device.id, readSwitch: trackControls, read: read)
            let silenced = initial.isSilenced
            // Already quiet and not ours: a microphone the user muted
            // themselves is left alone, so unmuting later never opens
            // something this app did not close.
            if MicMuteSupport.shouldLeaveUntouched(owned: owned.contains(device.uid),
                                                   captureSilenced: silenced) {
                outcome.applied = true
                continue
            }
            if silenced {
                if trackControls && authorize.verifiedQuiet(device, initial) { outcome.quietInputs[device] = initial }
                outcome.applied = true
                outcome.mutedDevices.append(device.uid)
                continue
            }
            // Keep listening: if a slow driver finally reports silence, the
            // path above clears its backoff immediately. Another microphone's
            // gain change must not keep writing this unresponsive control.
            let retry = retries[device.uid]
            if let retry, retry.deviceID == device.id, let deadline = retry.deadline, now < deadline,
               isVirtualInput(device), !retry.onlyWhileIdle || isIdleInput(device.id) {
                outcome.retries[device.uid] = retry
                outcome.applied = true
                outcome.failed = true
                outcome.mutedDevices.append(device.uid)
                continue
            }
            let volume = inputVolume(of: device.id, read: read)
            let channels = channelVolumes(of: device.id, read: read)
            // Snapshot every writable control before any write: a virtual
            // main volume can also change its channel controls. Reapplying
            // keeps the first snapshot, including a user's mute or zero gain.
            let addresses = muteAddresses(of: device.id) + volumeAddresses(of: device.id)
            let migrating = owned.contains(device.uid) && savedControls[device.uid] == nil
            let switchSnapshot = migrating ? legacySwitchSnapshot(device, savedVolumes, savedChannelVolumes, read: read) : nil
            var snapshot = savedControls[device.uid] ?? switchSnapshot ?? [:]
            var writable: [AudioObjectPropertyAddress] = []
            var quietBeforeWrite: Set<DeviceListener>? = readings[device] == nil ? nil : []
            for var address in addresses {
                var settable = DarwinBoolean(false)
                guard AudioObjectHasProperty(device.id, &address) else { continue }
                let canWrite = AudioObjectIsPropertySettable(device.id, &address, &settable) == noErr && settable.boolValue
                guard canWrite || quietBeforeWrite != nil, let current = read(device.id, address) else { continue }
                let closed = address.mSelector == kAudioDevicePropertyMute
                    ? current == 1 : current <= Double(MicMuteSupport.silenceThreshold)
                if closed {
                    quietBeforeWrite?.insert(DeviceListener(device: device.id, selector: address.mSelector,
                                                            scope: address.mScope, element: address.mElement))
                }
                guard canWrite else { continue }
                let key = controlKey(address)
                if snapshot[key] == nil {
                    snapshot[key] = migrating && switchSnapshot == nil
                        ? legacyRestoreValue(current, at: address, uid: device.uid,
                                             savedVolumes: savedVolumes,
                                             savedChannelVolumes: savedChannelVolumes,
                                             legacyVolume: legacyVolume)
                        : current
                }
                writable.append(address)
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
            for address in writable {
                let target: Double = address.mSelector == kAudioDevicePropertyMute ? 1 : 0
                switch writeControl(target, of: device.id, at: address, quietBeforeWrite: quietBeforeWrite,
                                    read: read, authorize: authorize) {
                case .possiblyChanged:
                    changed = true
                    quietBeforeWrite = nil
                case .unchanged: break
                case .interrupted:
                    // Earlier writes may already have changed this input or
                    // its aliases. Keep their original snapshot, along with
                    // claims and retries that this pass has not reached.
                    if changed { recordClaim() }
                    let recorded = Set(outcome.mutedDevices)
                    outcome.mutedDevices += (mutedDevices ?? []).filter { !recorded.contains($0) }
                    for remaining in devices[index...] { outcome.retries[remaining.uid] = retries[remaining.uid] }
                    return outcome
                }
            }
            let verified = inputControls(device.id, readSwitch: trackControls, read: read)
            let quiet = verified.isSilenced
            if changed || owned.contains(device.uid) {
                // A partially applied mute still owes its changes back.
                // Keep it operable and report the partial result, rather than
                // abandoning the microphone after one control refused a write.
                recordClaim()
                if quiet && trackControls && authorize.verifiedQuiet(device, verified) { outcome.quietInputs[device] = verified }
                if !quiet { outcome.failed = true }
                // Virtual drivers can confirm zero, revert immediately and
                // notify. Count their successive writes until a later sweep
                // finds them quiet. Ordinary gain adjustments on physical
                // microphones are reasserted immediately.
                if (changed || retry != nil) && isVirtualInput(device) && (!quiet || isIdleInput(device.id)) {
                    outcome.retries[device.uid] = MicMuteSupport.Retry(
                        deviceID: device.id, onlyWhileIdle: quiet, previous: retry, now: now)
                }
            } else {
                if quiet { outcome.applied = true }
                outcome.savedVolumes.removeValue(forKey: device.uid)
                outcome.savedChannelVolumes.removeValue(forKey: device.uid)
                outcome.savedControls.removeValue(forKey: device.uid)
                // Only a microphone some app records from is left open. An aggregate
                // has no switch or level of its own; the microphones under it are
                // swept and reported on their own.
                var transport: UInt32 = 0
                var running: UInt32 = 0
                Self.read(device.id, kAudioDevicePropertyTransportType, &transport)
                Self.read(device.id, kAudioDevicePropertyDeviceIsRunningSomewhere, &running)
                if !quiet, transport != kAudioDeviceTransportTypeAggregate, running != 0 {
                    outcome.failed = true
                }
            }
        }
        return outcome
    }

    private static func unmute(_ devices: [InputDevice],
                               savedVolumes: [String: Double],
                               savedChannelVolumes: [String: [String: Double]],
                               savedControls: [String: [String: Double]],
                               mutedDevices: [String]?,
                               legacyVolume: Double) -> MuteOutcome {
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
            let snapshot = savedControls[device.uid] ?? (mutedDevices != nil
                ? legacySwitchSnapshot(device, savedVolumes, savedChannelVolumes) : nil)
            if let snapshot {
                attempted = true
                let addresses = snapshot.keys.compactMap(controlAddress).sorted {
                    let left = controlRestoreOrder($0)
                    let right = controlRestoreOrder($1)
                    return left == right ? $0.mElement < $1.mElement : left < right
                }
                for address in addresses {
                    guard let value = snapshot[controlKey(address)] else { continue }
                    _ = writeControl(value, of: device.id, at: address)
                }
                // Check the final state after all writes. Later writes can
                // affect earlier controls through a driver's master/channel
                // aliases. Missing or unreadable controls stay ours to retry.
                let restored = !snapshot.isEmpty && addresses.count == snapshot.count
                    && addresses.allSatisfy { address in
                        guard let expected = snapshot[controlKey(address)],
                              let current = controlValue(of: device.id, at: address) else { return false }
                        return controlValuesMatch(current, expected)
                    }
                if restored {
                    outcome.applied = true
                    outcome.savedControls.removeValue(forKey: device.uid)
                    outcome.savedVolumes.removeValue(forKey: device.uid)
                    outcome.savedChannelVolumes.removeValue(forKey: device.uid)
                } else {
                    outcome.failed = true
                    outcome.mutedDevices.append(device.uid)
                }
                continue
            }
            // A saved level only leaves once the device really opened: a
            // restore that failed keeps the claim and the level, so the next
            // attempt still knows the device is this app's to release.
            switch MicMuteSupport.restoreNeed(muteSwitch: readMuteSwitch(of: device.id).value,
                                              volume: inputVolume(of: device.id),
                                              hasSavedVolume: savedVolumes[device.uid] != nil
                                                || savedChannelVolumes[device.uid] != nil) {
            case .alreadyAudible:
                outcome.savedVolumes.removeValue(forKey: device.uid)
                outcome.savedChannelVolumes.removeValue(forKey: device.uid)
            case .unreadable:
                outcome.mutedDevices.append(device.uid)
            case .restore(let clearMute, let restoreVolume):
                attempted = true
                var failed = false
                if clearMute, !setMuteSwitch(false, of: device.id) {
                    failed = true
                }
                if restoreVolume {
                    let restore = MicMuteSupport.volumeToRestore(uid: device.uid,
                                                                 saved: savedVolumes,
                                                                 legacy: legacyVolume)
                    // A channel with no level of its own, as after a mute from
                    // before channels were saved, takes the main level back.
                    if !setInputVolume(restore, of: device.id,
                                       channels: savedChannelVolumes[device.uid] ?? [:]) {
                        failed = true
                    }
                }
                if failed {
                    outcome.mutedDevices.append(device.uid)
                    outcome.failed = true
                } else {
                    outcome.applied = true
                    outcome.savedVolumes.removeValue(forKey: device.uid)
                    outcome.savedChannelVolumes.removeValue(forKey: device.uid)
                }
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
        for var address in volumeAddresses(of: device) where AudioObjectHasProperty(device, &address) {
            guard let value = read(device, address) else {
                gain = .unreadable
                continue
            }
            if !MicMuteSupport.isCaptureSilenced(muteSwitch: nil, volume: Float(value)) {
                gain = .audible
                break
            }
            if gain == .unavailable { gain = .silent }
            if readSwitch { silentGains.insert(controlKey(address)) }
        }
        let muteSwitch = readSwitch || gain == .unavailable ? readMuteSwitch(of: device, read: read) : nil
        return InputControls(gain: gain, muteSwitch: muteSwitch?.value, silentGains: silentGains,
                             mutedElements: muteSwitch?.mutedElements)
    }

    private static func isVirtualInput(_ device: InputDevice) -> Bool {
        // This is the loopback UID from the Teams report. Other drivers must
        // identify their transport as virtual before writes can be deferred.
        if device.uid == "MSLoopbackDriverDevice_UID" { return true }
        var transport: UInt32 = 0
        return read(device.id, kAudioDevicePropertyTransportType, &transport)
            && transport == kAudioDeviceTransportTypeVirtual
    }

    private static func isIdleInput(_ device: AudioDeviceID) -> Bool {
        var running: UInt32 = 0
        return read(device, kAudioDevicePropertyDeviceIsRunningSomewhere, &running) && running == 0
    }

    /// Every device that can capture audio, skipping the app's own mixing
    /// device and the ones the system is not really offering.
    private static func inputDevices() -> [InputDevice] {
        inputInventory()?.devices ?? []
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
        guard AudioObjectGetPropertyDataSize(object, &address, 0, nil, &size) == noErr, size > 0 else { return [] }
        var ids = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(object, &address, 0, nil, &size, &ids) == noErr else { return [] }
        return ids
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
        let storage = UnsafeMutableRawPointer.allocate(
            byteCount: Int(size), alignment: MemoryLayout<AudioBufferList>.alignment)
        defer { storage.deallocate() }
        guard AudioObjectGetPropertyData(device, &address, 0, nil, &size, storage) == noErr else { return nil }
        let buffers = UnsafeMutableAudioBufferListPointer(
            storage.assumingMemoryBound(to: AudioBufferList.self))
        return buffers.reduce(0) { $0 + Int($1.mNumberChannels) }
    }

    private static func inputElements(of device: AudioDeviceID) -> [AudioObjectPropertyElement] {
        MicMuteSupport.inputChannelElements(channelCount: inputChannelCount(of: device))
    }

    private static func muteAddresses(of device: AudioDeviceID) -> [AudioObjectPropertyAddress] {
        inputElements(of: device).map { element in
            AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyMute,
                                       mScope: kAudioDevicePropertyScopeInput,
                                       mElement: element)
        }
    }

    private static func readMuteSwitch(of device: AudioDeviceID, read: ControlReader = MicMuteService.controlValue)
        -> (value: UInt32?, mutedElements: ClosedRange<UInt32>?) {
        var main = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyMute,
                                               mScope: kAudioDevicePropertyScopeInput,
                                               mElement: kAudioObjectPropertyElementMain)
        var sawOpenSwitch = false
        var unreadable = false
        if AudioObjectHasProperty(device, &main) {
            if let value = read(device, main) {
                if value == 1 { return (1, main.mElement...main.mElement) }
                sawOpenSwitch = true
            } else {
                unreadable = true
            }
        }
        // A channel switch only silences that channel. Without an engaged
        // main switch, every input channel needs a readable, engaged switch.
        var allMuted = true
        let channels = 1...UInt32(clamping: max(inputChannelCount(of: device), 1))
        for channel in channels {
            var address = main
            address.mElement = AudioObjectPropertyElement(channel)
            guard AudioObjectHasProperty(device, &address) else {
                allMuted = false
                continue
            }
            guard let value = read(device, address) else {
                allMuted = false
                unreadable = true
                continue
            }
            if value == 0 {
                sawOpenSwitch = true
                allMuted = false
            }
        }
        if allMuted { return (1, channels) }
        return (sawOpenSwitch && !unreadable ? 0 : nil, nil)
    }

    /// Legacy restores have no per-control snapshot. Even then, success
    /// requires every exposed switch to read back the requested value.
    @discardableResult
    private static func setMuteSwitch(_ muted: Bool, of device: AudioDeviceID) -> Bool {
        var addresses: [AudioObjectPropertyAddress] = []
        for var address in muteAddresses(of: device) {
            guard AudioObjectHasProperty(device, &address) else { continue }
            addresses.append(address)
            _ = writeControl(muted ? 1 : 0, of: device, at: address)
        }
        return !addresses.isEmpty && addresses.allSatisfy {
            controlValue(of: device, at: $0) == (muted ? 1 : 0)
        }
    }

    private static func volumeAddresses(of device: AudioDeviceID) -> [AudioObjectPropertyAddress] {
        let elements = inputElements(of: device)
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

    /// Writes the virtual main level and every input channel, each channel
    /// taking its own entry in `channels` when there is one.
    private static func setInputVolume(_ volume: Float, of device: AudioDeviceID,
                                       channels: [String: Double] = [:]) -> Bool {
        var addresses: [AudioObjectPropertyAddress] = []
        for var address in volumeAddresses(of: device) where AudioObjectHasProperty(device, &address) {
            addresses.append(address)
            let value = channels[String(address.mElement)] ?? Double(volume)
            _ = writeControl(value, of: device, at: address)
        }
        return !addresses.isEmpty && addresses.allSatisfy { address in
            guard let current = controlValue(of: device, at: address) else { return false }
            return controlValuesMatch(current, channels[String(address.mElement)] ?? Double(volume))
        }
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

    private static func controlValuesMatch(_ left: Double, _ right: Double) -> Bool {
        left.isFinite && right.isFinite && abs(left - right) <= 0.0001
    }

    private static func controlValue(of device: AudioDeviceID,
                                     at address: AudioObjectPropertyAddress) -> Double? {
        var address = address
        guard AudioObjectHasProperty(device, &address) else { return nil }
        if address.mSelector == kAudioDevicePropertyMute {
            var value: UInt32 = 0
            var size = UInt32(MemoryLayout<UInt32>.size)
            guard AudioObjectGetPropertyData(device, &address, 0, nil, &size, &value) == noErr,
                  value <= 1 else { return nil }
            return Double(value)
        }
        var value: Float = 0
        var size = UInt32(MemoryLayout<Float>.size)
        guard AudioObjectGetPropertyData(device, &address, 0, nil, &size, &value) == noErr,
              value.isFinite, value >= 0, value <= 1 else { return nil }
        return Double(value)
    }

    private enum ControlWrite { case unchanged, possiblyChanged, interrupted }

    /// Reports a possible change, not proof of the requested state. A driver
    /// may accept and ignore a write, or make the control unreadable afterwards.
    /// Callers keep the snapshot and verify the final state separately.
    private static func writeControl(_ value: Double, of device: AudioDeviceID,
                                      at address: AudioObjectPropertyAddress,
                                      quietBeforeWrite: Set<DeviceListener>? = nil,
                                      read: ControlReader = MicMuteService.controlValue,
                                      authorize: MuteAuthorization? = nil) -> ControlWrite {
        guard value.isFinite, value >= 0, value <= 1,
              address.mSelector != kAudioDevicePropertyMute || value == 0 || value == 1,
              let current = read(device, address) else { return .unchanged }
        if controlValuesMatch(current, value) { return .unchanged }
        var address = address
        var settable = DarwinBoolean(false)
        guard AudioObjectIsPropertySettable(device, &address, &settable) == noErr,
              settable.boolValue else { return .unchanged }
        // This is the last software decision before either HAL setter. The
        // callback lock is released before calling a potentially reentrant driver.
        let listener = DeviceListener(device: device, selector: address.mSelector, scope: address.mScope, element: address.mElement)
        if let authorize, !authorize.beforeWrite(listener, quietBeforeWrite) {
            return .interrupted
        }
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
        authorize?.didWrite(listener, readBack, readBack.map { controlValuesMatch($0, value) } == true)
        if status != noErr, let readBack, controlValuesMatch(readBack, current) { return .unchanged }
        // Once submitted, an unreadable result cannot release our obligation
        // to restore the value saved before the call.
        return .possiblyChanged
    }

    /// 3.4.3 only flipped the main switch when it worked. No gain or channel
    /// mute belongs to that restore, even if one happens to be zero.
    private static func legacySwitchSnapshot(_ device: InputDevice, _ savedVolumes: [String: Double],
                                             _ savedChannelVolumes: [String: [String: Double]],
                                             read: ControlReader = MicMuteService.controlValue) -> [String: Double]? {
        guard savedVolumes[device.uid] == nil, savedChannelVolumes[device.uid] == nil else { return nil }
        let main = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyMute,
                                              mScope: kAudioDevicePropertyScopeInput,
                                              mElement: kAudioObjectPropertyElementMain)
        guard let mainMute = read(device.id, main) else { return nil }
        // Another client may already have released the switch. With gain
        // still live and no saved levels, keep the channel mix as found.
        // Fully zeroed, switch-off devices can still need a legacy gain restore.
        guard mainMute == 1 || volumeAddresses(of: device.id).contains(where: { address in
            guard let gain = read(device.id, address) else { return false }
            return gain > Double(MicMuteSupport.silenceThreshold)
        }) else { return nil }
        return [controlKey(main): 0]
    }

    /// An already-owned device may have been muted by a version without
    /// control snapshots. Carry its old restore obligation into the first
    /// snapshot instead of saving the mute or zero gain left by that version.
    private static func legacyRestoreValue(_ current: Double, at address: AudioObjectPropertyAddress,
                                           uid: String, savedVolumes: [String: Double],
                                           savedChannelVolumes: [String: [String: Double]],
                                           legacyVolume: Double) -> Double {
        if address.mSelector == kAudioDevicePropertyMute {
            return address.mElement == kAudioObjectPropertyElementMain ? 0 : current
        }
        if current > Double(MicMuteSupport.silenceThreshold) { return current }
        if address.mElement != kAudioObjectPropertyElementMain,
           let channel = savedChannelVolumes[uid]?[String(address.mElement)] { return channel }
        return Double(MicMuteSupport.volumeToRestore(uid: uid, saved: savedVolumes, legacy: legacyVolume))
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
            if retries[device.uid]?.onlyWhileIdle == true {
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
