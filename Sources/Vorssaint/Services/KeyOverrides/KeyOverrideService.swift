// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import Combine
import CoreGraphics
import Foundation

/// Runs the key overrides. The keyboard mapping makes special keys send plain function keys. Carbon hotkeys bind those keys to actions. The mapping is removed when the feature stops or the app quits.
final class KeyOverrideService: ObservableObject {
    static let shared = KeyOverrideService()

    /// True while the remap is confirmed, or not needed, and one or more overrides are live.
    @Published private(set) var isRunning = false
    /// The keyboard refused the mapping. Another remap tool possibly owns one of the keys.
    @Published private(set) var mappingFailed = false
    /// Overrides whose key macOS refused to register.
    @Published private(set) var registrationFailed: Set<UUID> = []

    private let hidutilPath = "/usr/bin/hidutil"
    /// Matches every keyboard, also one connected later.
    private let keyboardMatch = "keyboard"
    /// The queue shared with the Super key. Both features read, compose, and write the same UserKeyMapping property, so their cycles must never interleave.
    private let mappingQueue = SuperKeySupport.mappingWriteQueue
    private let stateLock = NSLock()
    /// A stop that comes while an apply is queued must add a clear after it.
    private var pendingMappingEnableCount = 0
    /// A sync that finished after a newer one started must not publish.
    private var syncGeneration = 0
    private var wakeObserver: NSObjectProtocol?

    /// One Carbon hotkey per bound override. The ids start at 300, clear of the other id ranges, and return to a free list when a row unbinds.
    private var hotkeys: [UUID: QuickToolHotkey] = [:]
    private var hotkeyIDs: [UUID: UInt32] = [:]
    private var freeHotkeyIDs: [UInt32] = []
    private var nextHotkeyID: UInt32 = 300

    private init() {}

    func syncWithPreferences() {
        let defaults = UserDefaults.standard
        let enabled = AppFeature.keyOverrides.isAvailable
            && defaults.bool(forKey: DefaultsKey.keyOverridesEnabled)
        let overrides = enabled
            ? KeyOverrideSupport.decode(defaults.data(forKey: DefaultsKey.keyOverrides))
            : []
        let active = overrides.filter(\.isEnabled)

        // The mic-mute action needs the Microphone Mute feature, whichever
        // path the list arrived by — a row added in Settings or a restored
        // backup. Installing here keeps the hub state a function of the list.
        if active.contains(where: { $0.action.kind == .micMute }),
           !AppFeature.micMute.isAvailable {
            FeatureRuntime.shared.setAvailable(.micMute, true)
        }

        syncHotkeys(for: active)

        syncGeneration += 1
        let generation = syncGeneration
        let reclaimed = KeyOverrideSupport.reclaimedKeys(in: active)
        guard !reclaimed.isEmpty else {
            clearLeftoverMapping()
            removeWakeObserver()
            mappingFailed = false
            isRunning = !active.isEmpty
            return
        }
        applyMapping(reclaiming: reclaimed) { [weak self] confirmed in
            guard let self, generation == self.syncGeneration else { return }
            self.mappingFailed = !confirmed
            self.isRunning = confirmed
            if confirmed { self.observeWake() }
        }
    }

    /// Removes the mapping before the app quits. A mapping left behind makes the keys dead.
    func suspend() {
        for hotkey in hotkeys.values { hotkey.unregister() }
        hotkeys.removeAll()
        registrationFailed = []
        removeWakeObserver()
        clearLeftoverMapping(synchronously: true)
        isRunning = false
    }

    // MARK: - The key bindings

    private func syncHotkeys(for active: [KeyOverride]) {
        let bound = KeyOverrideSupport.boundOverrides(
            in: active, micMuteAvailable: AppFeature.micMute.isAvailable)
        let boundIDs = Set(bound.map(\.id))
        for (id, hotkey) in hotkeys where !boundIDs.contains(id) {
            hotkey.unregister()
            hotkeys.removeValue(forKey: id)
            if let freed = hotkeyIDs.removeValue(forKey: id) { freeHotkeyIDs.append(freed) }
        }
        var failures: Set<UUID> = []
        for override in bound {
            let hotkey = hotkeys[override.id] ?? makeHotkey(for: override.id)
            let action = override.action
            hotkey.onPress = { [weak self] in self?.perform(action) }
            if !hotkey.sync(enabled: true, shortcut: override.key.triggerShortcut) {
                failures.insert(override.id)
            }
        }
        registrationFailed = failures
    }

    private func makeHotkey(for id: UUID) -> QuickToolHotkey {
        let hotkeyID = hotkeyIDs[id] ?? freeHotkeyIDs.popLast() ?? {
            let assigned = nextHotkeyID
            nextHotkeyID += 1
            return assigned
        }()
        hotkeyIDs[id] = hotkeyID
        let hotkey = QuickToolHotkey(id: hotkeyID)
        hotkeys[id] = hotkey
        return hotkey
    }

    private func perform(_ action: KeyOverrideAction) {
        switch action.kind {
        case .remapOnly:
            break
        case .micMute:
            guard AppFeature.micMute.isAvailable else { return }
            MicMuteService.shared.toggle()
        case .pressShortcut:
            guard let shortcut = action.shortcut,
                  Permissions.shared.accessibility else { return }
            Self.post(shortcut)
        }
    }

    /// Posts the press where the keyboard posts it. Then all listeners see it (issue #401).
    private static func post(_ shortcut: GlobalShortcut) {
        guard shortcut.hasUsableKeyCode else { return }
        let source = CGEventSource(stateID: .hidSystemState)
        guard let down = CGEvent(keyboardEventSource: source,
                                 virtualKey: CGKeyCode(shortcut.keyCode),
                                 keyDown: true),
              let up = CGEvent(keyboardEventSource: source,
                               virtualKey: CGKeyCode(shortcut.keyCode),
                               keyDown: false) else { return }
        let flags = shortcut.syntheticEventFlags
        down.flags = flags
        up.flags = flags
        down.post(tap: .cghidEventTap)
        up.post(tap: .cghidEventTap)
    }

    // MARK: - The keyboard mapping

    /// Clears a mapping from this run, or one that a killed run left behind.
    private func clearLeftoverMapping(synchronously: Bool = false) {
        let mappingMayBeApplied = UserDefaults.standard.bool(
            forKey: DefaultsKey.keyOverridesMappingApplied
        ) || stateLock.withLock { pendingMappingEnableCount > 0 }
        if mappingMayBeApplied {
            applyMapping(reclaiming: [], synchronously: synchronously)
        }
    }

    private func applyMapping(reclaiming keys: [KeyOverrideKey],
                              synchronously: Bool = false,
                              completion: ((Bool) -> Void)? = nil) {
        stateLock.withLock {
            if !keys.isEmpty { pendingMappingEnableCount += 1 }
        }
        let work = { [weak self] in
            guard let self else { return }
            let defaults = UserDefaults.standard
            let previousMarker = defaults.bool(forKey: DefaultsKey.keyOverridesMappingApplied)
            let confirmed = self.performMapping(
                reclaiming: keys,
                ownsExistingMapping: previousMarker
            )
            if keys.isEmpty {
                // An unconfirmed clear keeps the marker. The next sync can retry.
                let marker = SuperKeySupport.mappingMarkerAfterClear(
                    previous: previousMarker,
                    readbackConfirmed: confirmed
                )
                defaults.set(marker, forKey: DefaultsKey.keyOverridesMappingApplied)
            } else {
                self.stateLock.withLock { self.pendingMappingEnableCount -= 1 }
            }
            if let completion {
                DispatchQueue.main.async { completion(confirmed) }
            }
        }
        if synchronously {
            mappingQueue.sync(execute: work)
        } else {
            mappingQueue.async(execute: work)
        }
    }

    /// Runs on mappingQueue. Reads and composes; writes and reads back only when the table differs. Refuses a table that another tool remaps.
    private func performMapping(reclaiming keys: [KeyOverrideKey],
                                ownsExistingMapping: Bool) -> Bool {
        let report = Shell.run(
            hidutilPath,
            ["property", "--matching", keyboardMatch,
             "--get", SuperKeySupport.userMappingProperty]
        )
        guard report.status == 0 else { return false }
        // The Super key's entries ride along only while its marker says a
        // confirmed write made them; an unmarked entry of that shape is
        // external and stays the user's.
        let partnerApplied = UserDefaults.standard.bool(
            forKey: DefaultsKey.superKeyMappingApplied
        )
        guard let existing = KeyOverrideSupport.consistentMappings(
            report.output,
            ownsExistingMapping: ownsExistingMapping,
            partnerMappingApplied: partnerApplied
        ) else { return false }
        guard keys.isEmpty || !KeyOverrideSupport.hasMappingConflict(
            in: existing, reclaiming: keys
        ) else { return false }
        let wanted = KeyOverrideSupport.mappings(reclaiming: keys, existing: existing)
        if keys.isEmpty, !ownsExistingMapping,
           SuperKeySupport.mappingsMatch(existing, wanted) { return true }
        if !keys.isEmpty {
            // Set the marker before the write. After a crash, the next launch can then remove a partial mapping.
            UserDefaults.standard.set(true, forKey: DefaultsKey.keyOverridesMappingApplied)
            // Every keyboard already carrying the wanted table makes the write
            // and its readback pure cost: ending a shortcut recording re-syncs
            // this path on every capture, escape, focus loss and window close.
            if SuperKeySupport.mappingReportConfirms(report.output, expected: wanted) {
                return true
            }
        }
        let write = Shell.run(
            hidutilPath,
            ["property", "--matching", keyboardMatch,
             "--set", SuperKeySupport.mappingArgument(wanted)]
        )
        guard write.status == 0 else { return false }
        let readback = Shell.run(
            hidutilPath,
            ["property", "--matching", keyboardMatch,
             "--get", SuperKeySupport.userMappingProperty]
        )
        guard readback.status == 0 else { return false }
        return SuperKeySupport.mappingReportConfirms(readback.output, expected: wanted)
    }

    /// After wake, a keyboard can return without the mapping. This puts the mapping back.
    private func observeWake() {
        guard wakeObserver == nil else { return }
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.syncWithPreferences()
        }
    }

    private func removeWakeObserver() {
        if let wakeObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(wakeObserver)
            self.wakeObserver = nil
        }
    }
}
