// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit

/// Starts an agent's command-line tool in the terminal the person chose.
enum AgentLauncher {
    enum Outcome { case started, copied, failed }

    /// Main thread. `board` gives the terminal of the newest session when
    /// Settings leaves the choice to the app.
    static func run(_ command: String, cwd: String, board: [AgentSessionRow]) -> Outcome {
        var directory: ObjCBool = false
        guard NotchAgentSupport.isEnabled(), FileManager.default.fileExists(atPath: cwd, isDirectory: &directory),
              directory.boolValue else { return .failed }
        let terminal = AgentLaunchSupport.destination(setting: NotchAgentSupport.openIn(), detected: detected(board),
                                                      installed: installed)
        switch AgentLaunchSupport.plan(command, cwd: cwd, in: terminal) {
        case .script(_, let source):
            NotchService.shared.collapse()
            // The script waits on the terminal, and on a consent prompt the first time.
            DispatchQueue.global(qos: .userInitiated).async {
                let result = AppleScriptRunner.runDetailed(source)
                if result.errorNumber == -1743 || result.errorNumber == -1744 {
                    DispatchQueue.main.async { Permissions.shared.openAutomationSettings() }
                }
            }
            return .started
        case .openFolder(let bundleID, let folder, let command):
            guard let app = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return .failed }
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(command, forType: .string)
            NSWorkspace.shared.open([URL(fileURLWithPath: folder, isDirectory: true)], withApplicationAt: app,
                                    configuration: NSWorkspace.OpenConfiguration())
            return .copied
        }
    }

    static func installed(_ terminal: AgentLaunchTerminal) -> Bool {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: terminal.bundleID) != nil
    }

    /// The app that owns the newest Claude session with a process.
    private static func detected(_ board: [AgentSessionRow]) -> AgentLaunchTerminal? {
        board.filter { $0.pid != nil }.sorted { $0.since > $1.since }.lazy
            .compactMap { ResponsibleProcess.regularAppOwner(of: $0.pid!) }
            .compactMap { AgentLaunchTerminal(bundleIdentifier: $0.bundleIdentifier) }.first
    }
}
