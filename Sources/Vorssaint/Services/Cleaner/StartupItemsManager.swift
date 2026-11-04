// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// Lists the launch agents that start with your Mac and switches the ones in
/// your own Library on or off. Agents shared with all users are listed only.
final class StartupItemsManager: ObservableObject {
    static let shared = StartupItemsManager()

    struct Item: Identifiable, Equatable {
        var id: String { plistURL.path }
        let label: String
        let program: String
        let runAtLoad: Bool
        let plistURL: URL
        let isUserAgent: Bool
        var isEnabled: Bool
        /// The program file no longer exists (see `StartupItemSupport.isProgramMissing`).
        var programMissing = false
        /// When the agent file was created, a good guide to when it was installed.
        var added: Date?

        var displayName: String { StartupItemSupport.displayName(program: program, label: label) }
        var status: StartupItemSupport.Status {
            StartupItemSupport.status(programMissing: programMissing, runAtLoad: runAtLoad)
        }

        /// Whether the switch can be used: a user agent with a safe label
        /// that is not part of macOS or this app.
        var canToggle: Bool {
            isUserAgent && StartupItemSupport.isValidLabel(label) && !StartupItemSupport.isLocked(label)
        }
    }

    @Published private(set) var items: [Item] = []
    @Published private(set) var isLoading = false
    @Published private(set) var lastFailure: String?

    private init() {}

    func refresh() {
        guard !isLoading else { return }
        isLoading = true
        DispatchQueue.global(qos: .userInitiated).async {
            let found = Self.load()
            DispatchQueue.main.async {
                self.items = found
                self.isLoading = false
                self.lastFailure = nil
            }
        }
    }

    func setEnabled(_ enabled: Bool, for item: Item) {
        guard item.canToggle, !isLoading else { return }
        isLoading = true
        lastFailure = nil
        let uid = UInt32(getuid())
        DispatchQueue.global(qos: .userInitiated).async {
            let commands = enabled
                ? StartupItemSupport.enableCommands(uid: uid, label: item.label, plistPath: item.plistURL.path)
                : StartupItemSupport.disableCommands(uid: uid, label: item.label)
            // The first call records the choice; the second starts or stops
            // the job now. If recording fails nothing else runs, so the job
            // is never left stopped without the choice being saved. A job
            // that was not loaded makes the second call report an error,
            // which is expected, so only the first counts.
            var recorded = false
            for (index, arguments) in commands.enumerated() {
                let result = Self.launchctl(arguments)
                if index == 0 {
                    recorded = result.status == 0
                    if !recorded { break }
                }
            }
            // Switching on must really load the job: a start that failed
            // quietly would leave a switch that reads "on" with nothing running.
            // Switching off must really stop it: a job still loaded afterwards
            // is reported, since it keeps running until the next login.
            var succeeded = recorded
            if recorded {
                let loaded = Self.launchctl(["print", "gui/\(uid)/\(item.label)"]).status == 0
                succeeded = (loaded == enabled)
            }
            let found = Self.load()
            DispatchQueue.main.async {
                self.items = found
                self.isLoading = false
                self.lastFailure = succeeded ? nil : item.label
            }
        }
    }

    // MARK: - Loading

    private static func load() -> [Item] {
        let uid = getuid()
        let overrides = StartupItemSupport.overrides(
            fromPrintDisabled: launchctl(["print-disabled", "gui/\(uid)"]).output)
        let home = NSHomeDirectory()
        let folders: [(String, Bool)] = [("\(home)/Library/LaunchAgents", true),
                                         ("/Library/LaunchAgents", false)]
        var result: [Item] = []
        for (folder, isUser) in folders {
            let urls = (try? FileManager.default.contentsOfDirectory(
                at: URL(fileURLWithPath: folder, isDirectory: true),
                includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])) ?? []
            for url in urls where url.pathExtension == "plist" {
                guard let dictionary = NSDictionary(contentsOf: url) as? [String: Any],
                      let entry = StartupItemSupport.entry(from: dictionary) else { continue }
                let missing = StartupItemSupport.isProgramMissing(
                    entry.program, exists: FileManager.default.fileExists(atPath: entry.program))
                let added = (try? url.resourceValues(forKeys: [.creationDateKey]))?.creationDate
                result.append(Item(label: entry.label, program: entry.program, runAtLoad: entry.runAtLoad,
                                   plistURL: url, isUserAgent: isUser,
                                   isEnabled: !(overrides[entry.label] ?? entry.plistDisabled),
                                   programMissing: missing, added: added))
            }
        }
        return result.sorted { $0.label.localizedCaseInsensitiveCompare($1.label) == .orderedAscending }
    }

    /// Runs launchctl with the arguments as a list, never through a shell.
    private static func launchctl(_ arguments: [String]) -> (status: Int32, output: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        do { try process.run() } catch { return (-1, "") }
        // A launchctl call that stalls must not leave the tab loading forever:
        // ask it to stop after 10 seconds and force it 2 seconds later. The
        // watchdog is cancelled as soon as the call finishes normally.
        let pid = process.processIdentifier
        let watchdog = DispatchWorkItem {
            if process.isRunning {
                process.terminate()
                DispatchQueue.global().asyncAfter(deadline: .now() + 2) {
                    if process.isRunning { kill(pid, SIGKILL) }
                }
            }
        }
        DispatchQueue.global().asyncAfter(deadline: .now() + 10, execute: watchdog)
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        watchdog.cancel()
        return (process.terminationStatus, String(decoding: data.prefix(1_000_000), as: UTF8.self))
    }
}
