// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit

/// Arc keeps a profile per Space and offers its Spaces, not its profiles, to
/// AppleScript, so a Space is how a link reaches one of Arc's profiles. Every
/// call sends Apple Events and blocks until Arc answers: call them off the
/// main thread.
enum BrowserPickerArc {
    static let bundleID = BrowserPickerTarget.arcBundleID

    struct Space: Codable, Hashable {
        let id: String
        let title: String
    }

    /// Whether this app may script Arc. macOS can only answer, or ask, about
    /// a running Arc; for a closed one the answer is unknown.
    enum Access: Equatable {
        case allowed, notAsked, denied, unknown
    }

    enum Failure: Error, Equatable {
        /// Automation for Arc was declined, or has not been asked yet.
        case notAllowed
        /// The Space was deleted in Arc.
        case spaceMissing
        case failed
    }

    static var isInstalled: Bool {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) != nil
    }

    static var isRunning: Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).isEmpty
    }

    /// Asks macOS only when `prompt` is set: the question belongs to the
    /// moment someone turns Spaces on or asks for access.
    static func access(prompt: Bool) -> Access {
        var target = AEAddressDesc()
        let created = bundleID.withCString {
            AECreateDesc(typeApplicationBundleID, $0, bundleID.utf8.count, &target)
        }
        guard created == noErr else { return .unknown }
        defer { AEDisposeDesc(&target) }
        return access(status: AEDeterminePermissionToAutomateTarget(&target, typeWildCard, typeWildCard, prompt))
    }

    /// -1743 is a declined consent, -1744 one never asked; anything else, such
    /// as -600 for a closed Arc, says nothing about it.
    static func access(status: OSStatus) -> Access {
        switch status {
        case noErr: return .allowed
        case -1743: return .denied
        case -1744: return .notAsked
        default: return .unknown
        }
    }

    /// Opens Arc without bringing it forward, so macOS can ask about it.
    static func launchIfNeeded() -> Bool {
        guard !isRunning else { return true }
        guard let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return false }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = false
        let launched = DispatchSemaphore(value: 0)
        NSWorkspace.shared.openApplication(at: appURL, configuration: configuration) { _, _ in launched.signal() }
        _ = launched.wait(timeout: .now() + 15)
        return isRunning
    }

    /// The Spaces of Arc's front window, in sidebar order. Arc is not launched
    /// just to list them; a closed Arc reports nothing new.
    static func spaces() -> Result<[Space], Failure> {
        guard isRunning else { return .failure(.failed) }
        let result = AppleScriptRunner.runDetailed("""
            tell application id "\(bundleID)"
                if (count of windows) is 0 then return ""
                set output to ""
                repeat with aSpace in spaces of front window
                    set output to output & (id of aSpace) & tab & (title of aSpace) & linefeed
                end repeat
                return output
            end tell
            """)
        guard result.ok else { return .failure(failure(result.errorNumber)) }
        return .success(parseSpaces(result.output))
    }

    static func parseSpaces(_ output: String) -> [Space] {
        var seen = Set<String>()
        return output.split(whereSeparator: \.isNewline).compactMap { line in
            let fields = line.split(separator: "\t", maxSplits: 1, omittingEmptySubsequences: false)
            guard let id = fields.first.map(String.init), !id.isEmpty, seen.insert(id).inserted else { return nil }
            let title = fields.count > 1 ? String(fields[1]).trimmingCharacters(in: .whitespaces) : ""
            return Space(id: id, title: title)
        }
    }

    /// Opens the link in a new tab of one Space and brings Arc forward,
    /// launching it and opening a window first when needed.
    static func open(_ url: URL, inSpace id: String) -> Result<Void, Failure> {
        let result = AppleScriptRunner.runDetailed(openSource(url: url, spaceID: id))
        return result.ok ? .success(()) : .failure(failure(result.errorNumber))
    }

    static func openSource(url: URL, spaceID: String) -> String {
        """
        tell application id "\(bundleID)"
            if (count of windows) is 0 then make new window
            tell front window
                tell space id \(AppleScriptRunner.literal(spaceID)) to focus
                make new tab with properties {URL:\(AppleScriptRunner.literal(url.absoluteString))}
            end tell
            activate
        end tell
        """
    }

    /// -1743 is a declined Automation consent and -1744 one that would need
    /// asking; -1728 and -1719 mean the Space is no longer there.
    static func failure(_ errorNumber: Int?) -> Failure {
        switch errorNumber {
        case -1743, -1744: return .notAllowed
        case -1728, -1719: return .spaceMissing
        default: return .failed
        }
    }
}
