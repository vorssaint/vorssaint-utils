// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import Carbon.HIToolbox
import Combine
import IOKit

/// Watches macOS Secure Event Input and reports who holds it.
///
/// There is no notification for a secure input state change, so the state has
/// to be sampled, and it is sampled only while a surface that shows it
/// registers a demand.
final class SecureInputMonitor: ObservableObject {
    static let shared = SecureInputMonitor()

    @Published private(set) var holder: SecureInputSupport.Holder = .off

    private var observingSurfaces: Set<UUID> = []
    private var timer: Timer?

    private static let pollInterval: TimeInterval = 2

    private init() {}

    /// Visible UI owns a stable identifier so repeated SwiftUI appearances
    /// cannot leave an unbalanced timer, matching `Permissions`.
    func setObservingSurface(_ id: UUID, visible: Bool) {
        if visible {
            observingSurfaces.insert(id)
        } else {
            observingSurfaces.remove(id)
        }
        if visible {
            refresh()
        } else if observingSurfaces.isEmpty {
            // Clearing without a read: a stale `.app(X)` would keep warning
            // about a holder that released while nobody was watching.
            publish(.off)
        }
        schedulePolling()
    }

    /// Brings the holding app forward so the user can dismiss its password
    /// field. Nothing to reveal when the holder is gone or unknown.
    func revealHolder() {
        guard case .app(_, let pid) = holder,
              let app = NSRunningApplication(processIdentifier: pid) else { return }
        NSApp.yieldActivation(to: app)
        if !app.activate(from: NSRunningApplication.current, options: []) {
            app.activate(options: [])
        }
    }

    private func schedulePolling() {
        let shouldPoll = SecureInputSupport.shouldPoll(
            observingSurfaceCount: observingSurfaces.count)
        guard shouldPoll != (timer != nil) else { return }
        guard shouldPoll else {
            timer?.invalidate()
            timer = nil
            return
        }
        let timer = Timer(timeInterval: Self.pollInterval, repeats: true) { [weak self] _ in
            self?.refresh()
        }
        timer.tolerance = Self.pollInterval * 0.4
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private func refresh() {
        let isEnabled = IsSecureEventInputEnabled()
        // The registry traversal is skipped while the flag is off, the
        // overwhelmingly common poll outcome; `holder` decides on `isEnabled`
        // first, so the read would be discarded there anyway.
        let next = SecureInputSupport.holder(
            isEnabled: isEnabled,
            read: isEnabled ? Self.recordedHolder() : .noHolder,
            runningApp: {
                // Named the way every other surface names a process. The
                // owner is already known to be a regular app, so the kernel
                // fallback only covers one without a localized name; an empty
                // fallback leaves the genuinely nameless unattributed.
                guard let app = ResponsibleProcess.regularAppOwner(of: $0) else { return nil }
                return (ResponsibleProcess.displayName(pid: app.processIdentifier, fallback: ""),
                        app.processIdentifier)
            },
            isProcessAlive: { pid in
                // EPERM means the holder exists but is not ours to signal,
                // which is what a system holder is; same shape as
                // `AssistiveKeyboard`.
                kill(pid, 0) == 0 || errno == EPERM
            })
        publish(next)
    }

    private func publish(_ next: SecureInputSupport.Holder) {
        DispatchQueue.main.async {
            if self.holder != next { self.holder = next }
        }
    }

    /// What the window server records about this session's secure input
    /// holder.
    ///
    /// Three details are load-bearing. The property hangs off `IOResources`,
    /// not the service plane root, which answers nil. The key is absent, not
    /// zero, whenever secure input is off. And the value bridges as
    /// `NSNumber`, so a direct `pid_t` cast fails and silently reads as "no
    /// holder" on a session that has one.
    private static func recordedHolder() -> SecureInputSupport.RegistryRead {
        let entry = IORegistryEntryFromPath(kIOMainPortDefault, "IOService:/IOResources")
        guard entry != MACH_PORT_NULL else { return .unavailable }
        defer { IOObjectRelease(entry) }
        guard let sessions = IORegistryEntryCreateCFProperty(
            entry, "IOConsoleUsers" as CFString, kCFAllocatorDefault, 0)?
            .takeRetainedValue() as? [[String: Any]] else { return .unavailable }
        // The property lists every login session on the machine, which is what
        // fast user switching produces; only this one's holder can be blocking
        // the flag this process reads.
        let uid = getuid()
        guard let session = sessions.first(where: {
            ($0["kCGSSessionUserIDKey"] as? NSNumber)?.uint32Value == uid
        }) else { return .unavailable }
        guard let number = session["kCGSSessionSecureInputPID"] as? NSNumber,
              number.int32Value > 0 else { return .noHolder }
        return .holder(number.int32Value)
    }
}
