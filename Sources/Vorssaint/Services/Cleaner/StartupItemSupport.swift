// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// Pure rules for the startup items list. Only per-user launch agents can be
/// switched; macOS's own entries and this app's are shown but locked. Labels
/// reach launchctl as separate arguments, never through a shell, and only
/// after passing a strict character check.
enum StartupItemSupport {
    struct Entry: Equatable {
        let label: String
        let program: String
        let runAtLoad: Bool
        let plistDisabled: Bool
    }

    /// A label that is safe to hand to launchctl as part of a service target.
    static func isValidLabel(_ label: String) -> Bool {
        guard !label.isEmpty, label.count <= 200 else { return false }
        return label.unicodeScalars.allSatisfy { scalar in
            (scalar.value < 128) && (CharacterSet.alphanumerics.contains(scalar) || "._-+".unicodeScalars.contains(scalar))
        }
    }

    /// Entries that belong to macOS or to this app are never switched here.
    static func isLocked(_ label: String) -> Bool {
        let lowered = label.lowercased()
        return lowered.hasPrefix("com.apple.") || lowered.hasPrefix("com.vorssaint")
    }

    /// The app bundle a program sits inside, if any: the first path part that
    /// ends in ".app", with the path up to and including it.
    static func owningApp(ofProgram program: String) -> (name: String, path: String)? {
        let parts = program.split(separator: "/", omittingEmptySubsequences: true).map(String.init)
        guard let index = parts.firstIndex(where: { $0.lowercased().hasSuffix(".app") && $0.count > 4 }) else {
            return nil
        }
        let name = String(parts[index].dropLast(4))
        let path = "/" + parts[...index].joined(separator: "/")
        return (name, path)
    }

    /// The name shown for a row: the owning app, else the program's file name,
    /// else the raw label as a last resort.
    static func displayName(program: String, label: String) -> String {
        if let app = owningApp(ofProgram: program) { return app.name }
        let file = (program as NSString).lastPathComponent
        return file.isEmpty ? label : file
    }

    /// A program can only be called missing when it is an absolute path that
    /// does not exist. A bare command name is looked up by launchd, so it is
    /// never judged here.
    static func isProgramMissing(_ program: String, exists: Bool) -> Bool {
        program.hasPrefix("/") && !exists
    }

    /// What the row says about when the entry runs.
    enum Status: Equatable {
        /// Its program is gone: most likely left behind by a removed app.
        case leftover
        case atLogin
        case onDemand
    }

    static func status(programMissing: Bool, runAtLoad: Bool) -> Status {
        if programMissing { return .leftover }
        return runAtLoad ? .atLogin : .onDemand
    }

    /// Reads one launch agent plist. Returns nil for anything without a
    /// usable label.
    static func entry(from plist: [String: Any]) -> Entry? {
        guard let label = plist["Label"] as? String, !label.isEmpty else { return nil }
        var program = (plist["Program"] as? String) ?? ""
        if program.isEmpty, let arguments = plist["ProgramArguments"] as? [String], let first = arguments.first {
            program = first
        }
        return Entry(label: label, program: program,
                     runAtLoad: (plist["RunAtLoad"] as? Bool) ?? false,
                     plistDisabled: (plist["Disabled"] as? Bool) ?? false)
    }

    /// What launchctl's override database says for each label it lists (true
    /// means disabled), read from `launchctl print-disabled gui/<uid>`. An
    /// explicit "enabled" entry matters: it beats a Disabled key in the plist.
    static func overrides(fromPrintDisabled output: String) -> [String: Bool] {
        var disabled: [String: Bool] = [:]
        for line in output.split(separator: "\n") {
            let text = String(line)
            guard let open = text.firstIndex(of: "\""),
                  let close = text[text.index(after: open)...].firstIndex(of: "\"") else { continue }
            let label = String(text[text.index(after: open)..<close])
            let state = text[text.index(after: close)...].lowercased()
            guard state.contains("=>") else { continue }
            if state.contains("disabled") || state.contains("true") {
                disabled[label] = true
            } else if state.contains("enabled") || state.contains("false") {
                disabled[label] = false
            }
        }
        return disabled
    }

    /// The launchctl calls that turn a user agent off, in order. Disabling
    /// persists across logins; booting out stops it now.
    static func disableCommands(uid: UInt32, label: String) -> [[String]] {
        [["disable", "gui/\(uid)/\(label)"], ["bootout", "gui/\(uid)/\(label)"]]
    }

    /// The calls that turn it back on and start it.
    static func enableCommands(uid: UInt32, label: String, plistPath: String) -> [[String]] {
        [["enable", "gui/\(uid)/\(label)"], ["bootstrap", "gui/\(uid)", plistPath]]
    }
}
