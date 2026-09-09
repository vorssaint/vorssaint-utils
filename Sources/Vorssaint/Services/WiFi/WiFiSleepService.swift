// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import CoreWLAN

/// Switches Wi-Fi off while the Mac sleeps, so a closed laptop goes dark on
/// networks it is not using instead of staying joined to them all night.
///
/// The restore is honest in exactly the way Bluetooth on sleep is: the state
/// found before sleep is remembered, so Wi-Fi the user had already turned off
/// is never switched back on for them. The memory is a preference rather than
/// a variable, so a Mac shut down while asleep still gets its Wi-Fi back on
/// the next launch instead of staying dark.
///
/// Nothing runs while the feature is off: no observers, no polling, no cost.
/// Unlike the Bluetooth power switch, the Wi-Fi calls cross to the Wi-Fi
/// daemon (airportd) and block, so they stay synchronous inside the sleep
/// handler: the system holds off on the will-sleep reply, and a toggle sent
/// async could otherwise land after the Mac is already asleep.
final class WiFiSleepService {
    static let shared = WiFiSleepService()

    /// A Mac either has a Wi-Fi adapter or it does not; the answer cannot
    /// change while the Mac is running, so resolve it once. Desktops without
    /// a card report no interface at all.
    static let isSupported: Bool = {
        CWWiFiClient.shared().interface() != nil
    }()

    private var observers: [NSObjectProtocol] = []

    private init() {}

    func syncWithPreferences() {
        guard Self.isSupported else { return }
        // A restore still owed here means an earlier run switched Wi-Fi
        // off and never saw the wake, because the Mac was shut down (or the
        // app quit) while it slept. The debt is paid before anything else,
        // and paid even when the feature has since been switched off, so
        // nothing Vorssaint took away is ever kept.
        restoreIfOwed()
        if AppFeature.wifiSleep.isAvailable,
           UserDefaults.standard.bool(forKey: DefaultsKey.wifiSleepEnabled) {
            start()
        } else {
            stop()
        }
    }

    private func start() {
        guard observers.isEmpty else { return }
        let center = NSWorkspace.shared.notificationCenter
        observers = [
            center.addObserver(forName: NSWorkspace.willSleepNotification,
                               object: nil, queue: .main) { [weak self] _ in
                self?.macWillSleep()
            },
            center.addObserver(forName: NSWorkspace.didWakeNotification,
                               object: nil, queue: .main) { [weak self] _ in
                self?.restoreIfOwed()
            },
        ]
    }

    func stop() {
        guard !observers.isEmpty else { return }
        let center = NSWorkspace.shared.notificationCenter
        for observer in observers { center.removeObserver(observer) }
        observers = []
    }

    private func macWillSleep() {
        let defaults = UserDefaults.standard
        let plan = WiFiSleepSupport.sleepPlan(
            isPoweredOn: Self.isPoweredOn,
            restoresOnWake: defaults.bool(forKey: DefaultsKey.wifiSleepRestoreOnWake))
        defaults.set(plan.owesRestore, forKey: DefaultsKey.wifiSleepRestorePending)
        if plan.powersOff { Self.setPowered(false) }
    }

    private func restoreIfOwed() {
        let defaults = UserDefaults.standard
        let restores = WiFiSleepSupport.restores(
            owesRestore: defaults.bool(forKey: DefaultsKey.wifiSleepRestorePending),
            isPoweredOn: Self.isPoweredOn)
        // The debt is settled either way: Wi-Fi the user switched on
        // themselves cancels it instead of waiting for the next sleep.
        defaults.set(false, forKey: DefaultsKey.wifiSleepRestorePending)
        if restores { Self.setPowered(true) }
    }

    // MARK: Radio power

    private static var isPoweredOn: Bool {
        guard let interface = CWWiFiClient.shared().interface() else { return false }
        return interface.powerOn()
    }

    private static func setPowered(_ on: Bool) {
        guard let interface = CWWiFiClient.shared().interface() else { return }
        try? interface.setPower(on)
    }
}
