// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// The decisions behind Bluetooth on sleep, kept free of AppKit and IOKit so
/// they can be tested directly.
///
/// The rule the whole feature turns on: Vorssaint only ever puts back what it
/// took away. Bluetooth already off when the Mac went to sleep is never
/// switched on for the user, which is the part a plain sleep-and-wake toggle
/// gets wrong.
enum BluetoothSleepSupport {
    enum Mode: String, CaseIterable {
        case powerOff, selectedDevices

        init(storageValue: String?) {
            self = storageValue.flatMap(Self.init(rawValue:)) ?? .powerOff
        }
    }

    struct Device: Identifiable, Equatable {
        let id: String
        let name: String
        let isConnected: Bool
    }

    /// A device is selected by its Bluetooth address, never its display name.
    /// Accept the two address spellings returned by macOS and discard garbage.
    static func normalizedAddress(_ address: String) -> String? {
        let parts = address.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: ":", with: "-").split(separator: "-", omittingEmptySubsequences: false)
        guard parts.count == 6, parts.allSatisfy({
            $0.count == 2 && $0.utf8.allSatisfy { (48...57).contains($0) || (65...70).contains($0) || (97...102).contains($0) }
        }) else { return nil }
        return parts.joined(separator: "-").uppercased()
    }

    static func selectedAddresses(_ addresses: [String]) -> Set<String> {
        Set(addresses.compactMap(normalizedAddress))
    }

    /// Explicit opt-in only: an empty/stale selection never means all devices.
    static func disconnectTargets(selected: [String], devices: [Device]) -> [String] {
        let selection = selectedAddresses(selected)
        return Set(devices.filter(\.isConnected).compactMap { device -> String? in
            guard let address = normalizedAddress(device.id), selection.contains(address) else { return nil }
            return address
        }).sorted()
    }
    /// What to do as the Mac goes to sleep.
    struct SleepPlan: Equatable {
        /// Whether Bluetooth should be switched off now.
        let powersOff: Bool
        /// Whether a later wake owes the user a restore.
        let owesRestore: Bool
    }

    static func sleepPlan(isPoweredOn: Bool, restoresOnWake: Bool) -> SleepPlan {
        guard isPoweredOn else { return SleepPlan(powersOff: false, owesRestore: false) }
        return SleepPlan(powersOff: true, owesRestore: restoresOnWake)
    }

    /// Whether waking (or a launch that finds a restore still owed, because
    /// the Mac was shut down while asleep) should switch Bluetooth back on.
    /// Bluetooth the user turned on themselves in the meantime is left alone.
    /// Every launch asks, so the controller is read only when a restore is owed.
    static func restores(owesRestore: Bool, isPoweredOn: @autoclosure () -> Bool) -> Bool {
        owesRestore && !isPoweredOn()
    }
}

/// One sleep's bounded work. Wake, disable, uninstall, or a mode change cancels
/// the operation. Native closeConnection calls already in progress cannot be
/// interrupted, but no subsequent call starts after cancellation or expiry.
final class BluetoothSleepDisconnectOperation {
    private let lock = NSLock()
    private var cancelled = false
    private let deadline: Date
    private let now: () -> Date

    init(deadline: Date, now: @escaping () -> Date = Date.init) {
        self.deadline = deadline
        self.now = now
    }

    func cancel() { lock.withLock { cancelled = true } }

    func run(targets: [String], disconnect: (String) -> Bool) -> [String] {
        var failed: [String] = []
        for (index, address) in targets.enumerated() {
            guard lock.withLock({ !cancelled }), now() < deadline else {
                failed.append(contentsOf: targets[index...])
                break
            }
            if !disconnect(address) { failed.append(address) }
        }
        return failed
    }
}
