// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint Audio contributors
import AppKit
import Combine
import CoreAudio

/// Owns one virtual-output session. HAL calls and bridge construction serialize
/// off-main; only published presentation state is changed on the main queue.
final class VirtualOutputService: ObservableObject {
    static let shared = VirtualOutputService()
    @Published private(set) var isActive = false
    @Published private(set) var isStarting = false
    @Published private(set) var componentReady = false
    @Published private(set) var componentPresent = false
    @Published private(set) var componentNeedsUpdate = false
    @Published private(set) var isRemoving = false
    @Published private(set) var physicalOutputUID: String?
    @Published private(set) var requestedOutputUID: String?
    private let outputRequests = VirtualOutputSupport.OutputRequests()
    private var acceptsOutputSelections = false // Main thread, like the published state.
    @Published private(set) var error: String?
    var isInstalled: Bool { VirtualOutputHAL.componentDevice() != nil }
    private let queue = DispatchQueue(label: "com.vorssaint.utils.software-volume.lifecycle", qos: .userInitiated)
    private var bridge: VirtualOutputBridge?
    private var timer: DispatchSourceTimer?
    private var virtual: AudioObjectID?
    private var virtualUID = VirtualOutputSupport.deviceUID
    private var ownsVirtualOutput = false
    private var previousOutput: String?
    private var previousSystemOutput: String?
    private var lastCycles: Int64 = 0
    private var lastProgress = ProcessInfo.processInfo.systemUptime
    private var suspended = false
    private var installerOpened = false
    private var updateOffered = false
    private var updateAlert: NonModalAlert?

    func sync(enabled: Bool) {
        acceptsOutputSelections = enabled
        if !enabled {
            updateAlert?.dismiss(with: .alertSecondButtonReturn); updateAlert = nil
            installerOpened = false
            requestedOutputUID = nil; _ = outputRequests.next()
        }
        queue.async { [self] in
            let device = VirtualOutputHAL.componentDevice()
            let present = VirtualOutputHAL.installedComponentExists()
            let needsUpdate = VirtualOutputSupport.needsComponentUpdate(installed: present,
                build: VirtualOutputHAL.installedComponentBuild, required: VirtualOutputHAL.requiredComponentBuild)
            DispatchQueue.main.async {
                if self.componentReady != (device != nil) { self.componentReady = device != nil }
                if self.componentPresent != present { self.componentPresent = present }
                if self.componentNeedsUpdate != needsUpdate { self.componentNeedsUpdate = needsUpdate }
                self.offerComponentUpdateIfNeeded(enabled: enabled && self.acceptsOutputSelections, needsUpdate: needsUpdate)
                if device != nil { self.installerOpened = false }
            }
            guard enabled else {
                suspended = false
                if bridge != nil || virtual != nil { deactivate() }
                return
            }
            guard let device else {
                if bridge != nil || virtual != nil { deactivate() }
                return
            }
            if let bridge {
                let current = VirtualOutputHAL.defaultUID()
                if current != virtualUID {
                    if let current, VirtualOutputHAL.physicalDevices().contains(where: { $0.uid == current }) {
                        previousOutput = current
                        previousSystemOutput = current
                        if VirtualOutputHAL.hasHardwareVolume(current) {
                            deactivate()
                        } else {
                            replaceBridge(physicalUID: current)
                        }
                    } else {
                        deactivate(); suspended = false
                    }
                } else if !bridge.configurationIsCurrent() {
                    if VirtualOutputHAL.physicalDevices().contains(where: { $0.uid == bridge.physicalUID }) {
                        replaceBridge(physicalUID: bridge.physicalUID)
                    } else {
                        deactivate(); suspended = false
                        publish(error: .outputUnavailable)
                    }
                }
                return
            }
            let physicals = VirtualOutputHAL.physicalDevices()
            let current = VirtualOutputHAL.defaultUID()
            if let current, !VirtualOutputSupport.isSoftwareOutput(current) {
                if VirtualOutputHAL.hasHardwareVolume(current) { suspended = false; return }
                // A different virtual device belongs to another audio app.
                guard physicals.contains(where: { $0.uid == current }) else { return }
            }
            guard !suspended else { return }
            let saved = UserDefaults.standard.string(forKey: DefaultsKey.softwareVolumePhysicalOutputUID)
            guard let target = physicals.first(where: { $0.uid == current })?.uid
                    ?? physicals.first(where: { $0.uid == saved })?.uid
                    ?? physicals.first?.uid else {
                publish(error: .outputUnavailable); return
            }
            guard VirtualOutputSupport.usesVirtualOutput(enabled: enabled,
                hardwareVolume: VirtualOutputHAL.hasHardwareVolume(target)) else { return }
            virtual = device
            virtualUID = VirtualOutputHAL.uid(device) ?? VirtualOutputSupport.deviceUID
            previousOutput = VirtualOutputSupport.isSoftwareOutput(current) ? target : current
            previousSystemOutput = VirtualOutputHAL.defaultUID(kAudioHardwarePropertyDefaultSystemOutputDevice)
            replaceBridge(physicalUID: target)
        }
    }
    @discardableResult func selectOutput(_ uid: String) -> Bool {
        guard acceptsOutputSelections, !isRemoving, VirtualOutputHAL.componentDevice() != nil,
              VirtualOutputHAL.restorableOutputs(systemSounds: false).contains(uid) else { return false }
        let request = outputRequests.next()
        requestedOutputUID = uid
        queue.async { [self] in
            if outputRequests.isCurrent(request) { routeOutput(uid) }
            DispatchQueue.main.async {
                if self.outputRequests.isCurrent(request) { self.requestedOutputUID = nil }
            }
        }
        return true
    }
    private func routeOutput(_ uid: String) {
        guard VirtualOutputHAL.restorableOutputs(systemSounds: false).contains(uid) else {
            publish(error: .outputUnavailable); return
        }
        let physical = VirtualOutputHAL.physicalDevices().contains(where: { $0.uid == uid })
        let hadSession = bridge != nil || virtual != nil
        suspended = false
        if bridge?.physicalUID == uid, VirtualOutputHAL.defaultUID() == virtualUID { return }
        previousOutput = uid
        if physical {
            previousSystemOutput = hadSession ? uid : VirtualOutputHAL.defaultUID(kAudioHardwarePropertyDefaultSystemOutputDevice)
        }
        if !physical || VirtualOutputHAL.hasHardwareVolume(uid) {
            deactivate()
            // An earlier queued choice may already have released the virtual
            // owner, so restoring on deactivation alone is insufficient.
            guard VirtualOutputHAL.select(uid) else { publish(error: .outputUnavailable); return }
            if physical && hadSession { _ = VirtualOutputHAL.select(uid, selector: kAudioHardwarePropertyDefaultSystemOutputDevice) }
        } else {
            if virtual == nil {
                guard let device = VirtualOutputHAL.componentDevice() else { publish(error: .setupFailed); return }
                virtual = device
                virtualUID = VirtualOutputHAL.uid(device) ?? VirtualOutputSupport.deviceUID
            }
            replaceBridge(physicalUID: uid)
        }
    }
    func stop() {
        acceptsOutputSelections = false
        updateAlert?.dismiss(with: .alertSecondButtonReturn); updateAlert = nil
        installerOpened = false
        requestedOutputUID = nil; _ = outputRequests.next()
        queue.sync { deactivate() }
    }
    /// Main queue; one offer per app launch, never for an unused optional package.
    private func offerComponentUpdateIfNeeded(enabled: Bool, needsUpdate: Bool) {
        guard VirtualOutputSupport.shouldOfferComponentUpdate(enabled: enabled, needsUpdate: needsUpdate,
            offered: updateOffered, installing: installerOpened, removing: isRemoving) else { return }
        updateOffered = true
        let strings = VirtualOutputStrings.localized(L10n.shared.language)
        let alert = NSAlert()
        alert.messageText = strings.updateTitle
        alert.informativeText = strings.updateBody
        alert.addButton(withTitle: strings.update)
        alert.addButton(withTitle: L10n.shared.s.uninstallerCancel)
        updateAlert = NonModalAlert.present(alert) { [weak self] response in
            guard let self else { return }
            self.updateAlert = nil
            guard self.acceptsOutputSelections,
                  UserDefaults.standard.bool(forKey: DefaultsKey.mixerSoftwareVolumeEnabled) else { return }
            if response == .alertFirstButtonReturn { self.installForFallback() }
        }
    }
    func installForFallback() {
        guard !isRemoving else { return }
        updateOffered = true
        guard openInstaller() else { installerOpened = false; return }
        installerOpened = !isInstalled
        // Store the user's desired state now, so Off remains authoritative.
        // A later HAL notification never changes this preference.
        UserDefaults.standard.set(true, forKey: DefaultsKey.mixerSoftwareVolumeEnabled)
        AppVolumeMixer.shared.syncSoftwareOutputWithPreferences()
    }
    @discardableResult func openInstaller() -> Bool {
        // The offer may have stayed open while another installer completed.
        guard VirtualOutputSupport.shouldOpenBundledInstaller(
            installedBuild: VirtualOutputHAL.installedComponentBuild,
            bundledBuild: VirtualOutputHAL.requiredComponentBuild, ready: isInstalled) else { return true }
        guard let installer = Bundle.main.url(forResource: "VorssaintAudio", withExtension: "pkg") else {
            error = VirtualOutputStrings.localized(L10n.shared.language).message(.installerMissing)
            return false
        }
        return NSWorkspace.shared.open(installer)
    }
    /// Disable and restore playback before requesting root removal. Cancelling
    /// authorization keeps the driver installed and the ordinary mixer usable.
    func removeComponent(completion: ((Bool) -> Void)? = nil) {
        guard !isRemoving else { completion?(false); return }
        requestedOutputUID = nil; _ = outputRequests.next()
        installerOpened = false
        guard let script = Bundle.main.url(forResource: "uninstall-software-volume-driver", withExtension: "sh") else {
            error = VirtualOutputStrings.localized(L10n.shared.language).message(.removalFailed)
            completion?(false)
            return
        }
        isRemoving = true
        UserDefaults.standard.set(false, forKey: DefaultsKey.mixerSoftwareVolumeEnabled)
        let command = "/bin/zsh '" + script.path.replacingOccurrences(of: "'", with: "'\\''") + "'"
        queue.async { [self] in
            deactivate()
            DispatchQueue.main.async {
                AdminShell.run(command, prompt: VirtualOutputStrings.localized(L10n.shared.language).removeTitle) { success in
                    DispatchQueue.main.async {
                        self.isRemoving = false
                        self.componentReady = self.isInstalled
                        self.componentPresent = VirtualOutputHAL.installedComponentExists()
                        let removed = success && !self.componentPresent
                        self.error = removed ? nil : VirtualOutputStrings.localized(L10n.shared.language).message(.removalFailed)
                        if removed {
                            UserDefaults.standard.removeObject(forKey: DefaultsKey.mixerSoftwareVolumes)
                            UserDefaults.standard.removeObject(forKey: DefaultsKey.softwareVolumePhysicalOutputUID)
                        }
                        completion?(removed)
                    }
                }
            }
        }
    }
    private func publish(error issue: VirtualOutputSupport.Issue? = nil) {
        let active = bridge != nil, uid = bridge?.physicalUID
        DispatchQueue.main.async {
            self.isActive = active
            self.isStarting = false
            self.physicalOutputUID = uid
            self.error = issue.map { VirtualOutputStrings.localized(L10n.shared.language).message($0) }
            AppVolumeMixer.shared.refreshApps()
        }
    }
    private func replaceBridge(physicalUID: String) {
        guard let virtual else { return }
        DispatchQueue.main.async { self.isStarting = true; self.error = nil }
        rememberLevel()
        timer?.cancel(); timer = nil
        // Keep the virtual default during a format change. It stays silent
        // until the replacement bridge is ready, avoiding a raw-volume spike.
        bridge?.stop(); bridge = nil
        let ownerStatus = VirtualOutputHAL.write(virtual, VirtualOutputSupport.ownerSelector, value: kCFBooleanTrue!)
        guard ownerStatus == noErr else {
            deactivate(); suspended = true
            publish(error: ownerStatus == kAudioDevicePermissionsError ? .privacyUnverified : .inUse)
            return
        }
        ownsVirtualOutput = true
        do {
            let levels = UserDefaults.standard.dictionary(forKey: DefaultsKey.mixerSoftwareVolumes)
            let level = MixerSoftwareVolumeSupport.savedLevel(levels?[physicalUID])
            // The virtual default may already carry playback from another
            // physical destination. Its pump must see the new controls before
            // the bridge constructor starts physical IO, including mute.
            guard VirtualOutputHAL.setOutputLevel(virtual, level: level) else {
                throw VirtualOutputBridge.Failure("Could not initialize native master volume")
            }
            let muted: UInt32 = level == 0 ? 1 : 0
            var actualMuted: UInt32 = 0
            guard VirtualOutputHAL.write(virtual, kAudioDevicePropertyMute, value: muted, scope: kAudioObjectPropertyScopeOutput) == noErr,
                  VirtualOutputHAL.read(virtual, kAudioDevicePropertyMute, into: &actualMuted, scope: kAudioObjectPropertyScopeOutput),
                  actualMuted == muted,
                  let actualLevel = VirtualOutputHAL.outputLevel(virtual), abs(actualLevel - level) < 0.0001 else {
                throw VirtualOutputBridge.Failure("Could not verify native master volume and mute")
            }
            let next = try VirtualOutputBridge(virtual: virtual, physicalUID: physicalUID)
            bridge = next
            guard VirtualOutputHAL.select(virtualUID) else {
                throw VirtualOutputBridge.Failure("Could not select the Vorssaint Audio system output")
            }
            // Route alerts and sound effects through the same native mute.
            guard VirtualOutputHAL.select(virtualUID, selector: kAudioHardwarePropertyDefaultSystemOutputDevice) else {
                throw VirtualOutputBridge.Failure("Could not route system sound effects")
            }
            UserDefaults.standard.set(physicalUID, forKey: DefaultsKey.softwareVolumePhysicalOutputUID)
            lastCycles = next.progress.cycles
            lastProgress = ProcessInfo.processInfo.systemUptime
            let timer = DispatchSource.makeTimerSource(queue: queue)
            timer.schedule(deadline: .now() + 1, repeating: 1)
            timer.setEventHandler { [weak self] in self?.heartbeat() }
            self.timer = timer
            timer.resume()
            publish()
        } catch {
            deactivate(); suspended = true
            publish(error: (error as? VirtualOutputBridge.Failure)?.issue ?? .setupFailed)
        }
    }
    private func heartbeat() {
        guard let bridge, let virtual else { return }
        let now = ProcessInfo.processInfo.systemUptime, cycles = bridge.progress.cycles
        guard bridge.configurationIsCurrent() else {
            // The next sync either rebuilds for a changed format or restores
            // a remaining physical output after a disconnection.
            DispatchQueue.main.async { self.sync(enabled: true) }
            return
        }
        rememberLevel()
        if cycles != lastCycles {
            lastCycles = cycles; lastProgress = now
            guard VirtualOutputHAL.write(virtual, VirtualOutputSupport.ownerSelector, value: kCFBooleanTrue!) == noErr else {
                deactivate(); suspended = true
                publish(error: .stopped)
                return
            }
        } else if now - lastProgress > 3 {
            deactivate(); suspended = true
            publish(error: .stopped)
        }
    }
    private func rememberLevel() {
        guard ownsVirtualOutput, let virtual, let uid = bridge?.physicalUID,
              let level = VirtualOutputHAL.outputLevel(virtual) else { return }
        var muted: UInt32 = 0
        _ = VirtualOutputHAL.read(virtual, kAudioDevicePropertyMute, into: &muted, scope: kAudioObjectPropertyScopeOutput)
        let value = muted != 0 ? 0 : level
        var saved = UserDefaults.standard.dictionary(forKey: DefaultsKey.mixerSoftwareVolumes) ?? [:]
        if (saved[uid] as? NSNumber)?.doubleValue != value {
            saved[uid] = value
            UserDefaults.standard.set(saved, forKey: DefaultsKey.mixerSoftwareVolumes)
        }
    }
    private func deactivate() {
        rememberLevel()
        timer?.cancel(); timer = nil
        let physicals = VirtualOutputHAL.physicalDevices().map(\.uid)
        if let restore = VirtualOutputSupport.restoreUID(current: VirtualOutputHAL.defaultUID(), virtual: virtualUID,
                                                        previous: previousOutput, available: VirtualOutputHAL.restorableOutputs(systemSounds: false),
                                                        fallback: physicals, owned: ownsVirtualOutput) {
            _ = VirtualOutputHAL.select(restore)
        }
        if let restore = VirtualOutputSupport.restoreUID(current: VirtualOutputHAL.defaultUID(kAudioHardwarePropertyDefaultSystemOutputDevice),
                                                        virtual: virtualUID, previous: previousSystemOutput,
                                                        available: VirtualOutputHAL.restorableOutputs(systemSounds: true), fallback: physicals, owned: ownsVirtualOutput) {
            _ = VirtualOutputHAL.select(restore, selector: kAudioHardwarePropertyDefaultSystemOutputDevice)
        }
        bridge?.stop(); bridge = nil
        if ownsVirtualOutput, let virtual {
            _ = VirtualOutputHAL.write(virtual, VirtualOutputSupport.ownerSelector, value: kCFBooleanFalse!)
        }
        ownsVirtualOutput = false
        virtual = nil
        previousOutput = nil; previousSystemOutput = nil
        publish()
    }
}
