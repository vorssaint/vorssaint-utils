// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// what the first check found for a tool
enum CompanionHealth: Equatable {
    case ready
    case notInstalled
    case notSignedIn
    /// installed + signed in but test q got no answer, reason is the tools own words (short)
    case noAnswer(blocked: Bool, reason: String)
}

/// plain rules for self setup, how each tool says its signed in, which env vars flip it from
/// subscription to api key, + the fix msg per failure
enum CompanionSetupSupport {
    static let testQuestion = "Reply with one word: ready"

    /// subscription first. these vars make a tool bill an api acct so 1st try runs w/o them
    static func apiKeyVariables(for tool: String) -> [String] {
        switch tool {
        case "claude": return ["ANTHROPIC_API_KEY", "ANTHROPIC_AUTH_TOKEN"]
        case "codex": return ["OPENAI_API_KEY"]
        case "cursor-agent": return ["CURSOR_API_KEY"]
        default: return []
        }
    }

    static func environment(_ base: [String: String], tool: String, allowAPIKey: Bool) -> [String: String] {
        guard !allowAPIKey else { return base }
        let blocked = Set(apiKeyVariables(for: tool))
        return base.filter { !blocked.contains($0.key) }
    }

    static func hasAPIKey(_ base: [String: String], tool: String) -> Bool {
        apiKeyVariables(for: tool).contains { !(base[$0] ?? "").isEmpty }
    }

    static func statusArguments(for tool: String) -> [String] {
        switch tool {
        case "claude": return ["auth", "status"]
        case "codex": return ["login", "status"]
        default: return ["status"]
        }
    }

    static func isSignedIn(tool: String, status: Int32, output: String) -> Bool {
        let text = output.lowercased()
        guard status == 0 else { return false }
        switch tool {
        case "claude":
            return text.contains("\"loggedin\": true") || text.contains("\"loggedin\":true")
        case "codex":
            return text.contains("logged in") && !text.contains("not logged in")
        default:
            return !text.contains("not logged in") && !text.contains("login required")
        }
    }

    /// output saying the account itself refused, not a network/timing thing
    static func looksBlocked(_ output: String) -> Bool {
        let text = output.lowercased()
        return ["subscription access", "third-party", "extra usage", "use an anthropic api key",
                "organization has been disabled", "invalid api key", "unauthorized", "oauth token"]
            .contains { text.contains($0) }
    }

    /// tools own explanation, last error line or first line, colors stripped, max 200 chars
    static func reason(from output: String) -> String {
        let clean = output.replacingOccurrences(of: "\u{1B}\\[[0-9;]*[A-Za-z]", with: "", options: .regularExpression)
        let lines = clean.split(whereSeparator: \.isNewline).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        let line = lines.last { $0.lowercased().hasPrefix("error") } ?? lines.first ?? ""
        let text = line.replacingOccurrences(of: "ERROR: ", with: "")
        return String(text.prefix(200))
    }

    /// opens in terminal so user sees it + finishes it
    static func loginArguments(for tool: String) -> [String] {
        switch tool {
        case "claude": return ["auth", "login"]
        case "codex": return ["login"]
        default: return ["login"]
        }
    }

    static func installCommand(for tool: String) -> String? {
        switch tool {
        case "claude": return "curl -fsSL https://claude.ai/install.sh | bash"
        case "codex": return "npm install -g @openai/codex"
        case "cursor-agent": return "curl https://cursor.com/install -fsS | bash"
        default: return nil
        }
    }

    /// label of the one button a failure gets (if any)
    static func actionLabel(_ health: CompanionHealth?, language: AppLanguage = L10n.shared.language) -> String? {
        switch health {
        case .notSignedIn?: return CompanionSetupText.text(.signIn, language)
        case .notInstalled?: return CompanionSetupText.text(.install, language)
        default: return nil
        }
    }

    /// verified once a test q passed on this mac, not asked again unless one fails or check now
    static func isVerified(_ verified: [String: Double], tool: String) -> Bool { verified[tool] != nil }

    /// short word for the last check, for settings
    static func statusLabel(_ health: CompanionHealth?, checking: Bool, language: AppLanguage = L10n.shared.language) -> String {
        let key: CompanionSetupText.Key
        if checking { key = .checking } else {
            switch health {
            case nil: key = .notChecked
            case .ready?: key = .ready
            case .notInstalled?: key = .notInstalledShort
            case .notSignedIn?: key = .notSignedInShort
            case .noAnswer?: key = .noAnswerShort
            }
        }
        return CompanionSetupText.text(key, language)
    }

    static func displayName(tool: String) -> String {
        switch tool {
        case "claude": return "Claude"
        case "cursor-agent": return "Cursor"
        case "codex": return "Codex"
        default: return tool
        }
    }

    /// the one fix shown in chat w/ the command to run
    static func fix(tool: String, _ health: CompanionHealth, language: AppLanguage = L10n.shared.language) -> String? {
        let name = displayName(tool: tool)
        func text(_ key: CompanionSetupText.Key, cmd: String = "", said: String = "") -> String {
            CompanionSetupText.text(key, language, ai: name, cmd: cmd, said: said)
        }
        switch health {
        case .ready: return nil
        case .notInstalled:
            return installCommand(for: tool).map { text(.fixNotInstalled, cmd: $0) }
        case .notSignedIn:
            let login = (tool == "cursor-agent" ? "agent" : tool) + " " + loginArguments(for: tool).joined(separator: " ")
            return text(.fixNotSignedIn, cmd: login)
        case .noAnswer(let blocked, let reason):
            if blocked, tool == "claude" {
                return text(.claudeBlocked, cmd: "launchctl setenv ANTHROPIC_API_KEY <your key>")
            }
            let said = reason.isEmpty ? CompanionSetupText.text(.emptySaid, language)
                : CompanionSetupText.text(.said, language, reason: reason)
            return text(.fixNoAnswer, said: said)
        }
    }
}
