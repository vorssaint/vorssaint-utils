// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation
import ServiceManagement

/// Launch at login, remembered and self-repairing.
///
/// All UI goes through here so the choice stored in preferences and the real
/// registration never drift apart. `LaunchAtLoginSupport` explains why the
/// system record alone cannot be trusted across relaunches.
enum LaunchAtLogin {
    /// Service Management can stall while answering, so every read and
    /// change runs here, off the main thread. The queue is serial, so a change
    /// made in Settings always runs after the startup repair.
    private static let operationQueue = DispatchQueue(
        label: "com.vorssaint.utils.launch-at-login", qos: .userInitiated)

    /// What the system holds for this app right now.
    static var registration: LaunchAtLoginSupport.Registration {
        switch SMAppService.mainApp.status {
        case .enabled: return .enabled
        case .requiresApproval: return .needsApproval
        default: return .off
        }
    }

    /// What the system will actually do at the next login.
    static var isEnabled: Bool { registration == .enabled }

    /// Thrown when the app runs from a place whose registration cannot
    /// survive a relaunch; the message tells the user how to fix it.
    struct UnstableLocationError: LocalizedError {
        var errorDescription: String? { L10n.shared.s.launchAtLoginNeedsApplications }
    }

    /// Registration can succeed while macOS still denies permission, including
    /// when Allow in the Background is off. Only the user can approve it.
    struct NeedsApprovalError: LocalizedError {
        var errorDescription: String? { L10n.shared.s.launchAtLoginNeedsApproval }
    }

    /// Reads the registration once any repair or change queued before it is
    /// done, and answers on the main thread.
    static func refresh(_ completion: @escaping (LaunchAtLoginSupport.Registration) -> Void) {
        operationQueue.async {
            let current = registration
            DispatchQueue.main.async { completion(current) }
        }
    }

    /// Reports the registration the change left behind, since a register call
    /// that succeeds can still leave the item waiting for approval. The answer
    /// arrives on the main thread, where the error's message reads the
    /// current language.
    static func setEnabled(_ enabled: Bool,
                           completion: @escaping (LaunchAtLoginSupport.Registration, Error?) -> Void) {
        operationQueue.async {
            let failure: Error?
            do {
                try setEnabledNow(enabled)
                failure = nil
            } catch {
                failure = error
            }
            let current = registration
            DispatchQueue.main.async { completion(current, failure) }
        }
    }

    private static func setEnabledNow(_ enabled: Bool) throws {
        if enabled, locationIsUnstable { throw UnstableLocationError() }
        UserDefaults.standard.set(enabled, forKey: DefaultsKey.launchAtLoginWanted)
        var failure: Error?
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            failure = error
        }
        // Registering over an item the user switched off in System Settings
        // leaves the app closed at login whether or not the call reports an
        // error. Only the user can approve it there, so the wish stays stored
        // and the message says where to finish the job.
        if enabled, registration == .needsApproval { throw NeedsApprovalError() }
        // Only surface failures that leave the system out of step with the
        // user's choice. Unregistering an item that was already gone reports
        // an error even though the end state is exactly what the user asked
        // for.
        if let failure, isEnabled != enabled {
            // The stored intent must match what the user actually got;
            // keeping the failed wish would make the startup repair register
            // an item the UI showed as off.
            UserDefaults.standard.set(isEnabled, forKey: DefaultsKey.launchAtLoginWanted)
            throw failure
        }
    }

    /// Redoes a registration the system lost and adopts an enable made in
    /// the system's own settings. Called once at startup.
    static func repairAtStartup() {
        operationQueue.async { repairNow() }
    }

    private static func repairNow() {
        let defaults = UserDefaults.standard
        switch LaunchAtLoginSupport.startupAction(
            wanted: defaults.bool(forKey: DefaultsKey.launchAtLoginWanted),
            registration: registration,
            locationIsUnstable: locationIsUnstable) {
        case .none:
            break
        case .adoptEnabled:
            defaults.set(true, forKey: DefaultsKey.launchAtLoginWanted)
        case .register:
            try? SMAppService.mainApp.register()
        }
    }

    private static var locationIsUnstable: Bool {
        UpdateInstallerSupport.runsFromImmutableLocation(
            appPath: Bundle.main.bundlePath,
            volumeIsReadOnly: { path in
                let values = try? URL(fileURLWithPath: path)
                    .resourceValues(forKeys: [.volumeIsReadOnlyKey])
                return values?.volumeIsReadOnly ?? true
            })
    }
}
