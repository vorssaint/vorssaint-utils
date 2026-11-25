// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit

/// Loaded only when the installed Quick Toggles settings section is opened.
/// Recovery is private, machine-local data, not a portable preference.
final class PasswordLengthService: ObservableObject {
    @Published private(set) var snapshot: PasswordLengthPolicy.Snapshot?
    @Published private(set) var saved: PasswordLengthPolicy.Snapshot?
    @Published private(set) var busy = false
    @Published private(set) var failed = false

    private var journalURL: URL? {
        PrivateFileStore.containerURL?.appendingPathComponent("password-length-recovery.json")
    }

    func refresh() {
        guard !busy else { return }
        busy = true
        failed = false
        load { self.busy = false }
    }

    private func load(completion: @escaping () -> Void) {
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                try PasswordLengthDirectory.checkManagement()
                let current = try PasswordLengthDirectory(user: NSUserName()).snapshot()
                _ = try current.rules()
                var recovery: PasswordLengthPolicy.Snapshot?
                if let url = self.journalURL, FileManager.default.fileExists(atPath: url.path) {
                    let data = try Data(contentsOf: url)
                    guard data.count <= 256 * 1024 else { throw PasswordLengthPolicy.Failure.invalid }
                    recovery = try JSONDecoder().decode(PasswordLengthPolicy.Snapshot.self, from: data)
                    _ = try PasswordLengthPolicy.plan(current: current, action: .restore, saved: recovery, minimum: nil)
                }
                DispatchQueue.main.async {
                    self.snapshot = current
                    self.saved = recovery
                    completion()
                }
            } catch {
                DispatchQueue.main.async {
                    self.snapshot = nil
                    self.saved = nil
                    self.failed = true
                    completion()
                }
            }
        }
    }

    func perform(_ action: PasswordLengthPolicy.Action, minimum: Int?, prompt: String) {
        guard AppFeature.quickToggles.isAvailable, !busy, let current = snapshot,
              let executable = Bundle.main.executableURL, let journal = journalURL else { return }
        do {
            guard PrivateFileStore.createDirectory(at: journal.deletingLastPathComponent()) else {
                throw PasswordLengthPolicy.Failure.unavailable
            }
            let recovery = try PasswordLengthRecovery(url: journal)
            let onDisk = try recovery.read()
            if let onDisk, let saved {
                guard try onDisk.equivalent(to: saved) else { throw PasswordLengthPolicy.Failure.conflict }
            } else if onDisk != nil || saved != nil {
                throw PasswordLengthPolicy.Failure.conflict
            }
            let request = PasswordLengthPolicy.Request(action: action, expected: current, saved: saved, minimum: minimum)
            let payload = try request.preparedPayload()
            if action == .disable {
                try recovery.create(current)
            }
            func quote(_ value: String) -> String { "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'" }
            let command = [executable.path, PasswordLengthDirectory.commandFlag, payload].map(quote).joined(separator: " ")
            busy = true
            failed = false
            AdminShell.run(command, prompt: prompt) { succeeded in
                // A failed or interrupted operation retains recovery. Restore only
                // adds missing original rules, so partial removal is recoverable.
                var cleaned = true
                if succeeded, action == .restore {
                    do {
                        guard let saved = request.saved else { throw PasswordLengthPolicy.Failure.invalid }
                        try recovery.remove(matching: saved)
                    } catch { cleaned = false }
                }
                let completed = succeeded && cleaned
                DispatchQueue.main.async {
                    withExtendedLifetime(recovery) {}
                    self.load {
                        self.failed = self.failed || !completed
                        self.busy = false
                    }
                }
            }
        } catch { failed = true }
    }
}
