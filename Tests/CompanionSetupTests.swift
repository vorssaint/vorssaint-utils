// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

enum CompanionSetupTests {
    static func run(_ suite: TestSuite) {
        suite.run("companion-setup") {
            let base = ["ANTHROPIC_API_KEY": "x", "PATH": "/bin", "OPENAI_API_KEY": "y"]
            suite.expect(CompanionSetupSupport.environment(base, tool: "claude", allowAPIKey: false)["ANTHROPIC_API_KEY"] == nil,
                         "subscription pass hides the Claude API key")
            suite.expect(CompanionSetupSupport.environment(base, tool: "claude", allowAPIKey: false)["OPENAI_API_KEY"] == "y",
                         "only the tool's own key is hidden")
            suite.expect(CompanionSetupSupport.environment(base, tool: "claude", allowAPIKey: true) == base, "fallback keeps the key")
            suite.expect(CompanionSetupSupport.hasAPIKey(base, tool: "claude") && !CompanionSetupSupport.hasAPIKey(base, tool: "cursor-agent"),
                         "API key detection is per tool")

            suite.expect(CompanionSetupSupport.isSignedIn(tool: "claude", status: 0, output: "{\n  \"loggedIn\": true,\n}"), "Claude subscription login")
            suite.expect(!CompanionSetupSupport.isSignedIn(tool: "claude", status: 0, output: "{\"loggedIn\": false}"), "Claude logged out")
            suite.expect(CompanionSetupSupport.isSignedIn(tool: "codex", status: 0, output: "Logged in using ChatGPT"), "Codex ChatGPT login")
            suite.expect(!CompanionSetupSupport.isSignedIn(tool: "codex", status: 1, output: "Not logged in"), "Codex logged out")
            suite.expect(!CompanionSetupSupport.isSignedIn(tool: "cursor-agent", status: 0, output: "Not logged in"), "Cursor logged out")
            suite.expect(CompanionSetupSupport.isSignedIn(tool: "cursor-agent", status: 0, output: "Logged in as someone"), "Cursor logged in")

            suite.expect(CompanionSetupSupport.fix(tool: "cursor-agent", .notSignedIn, language: .enUS)?.contains("`agent login`") == true, "Cursor fix")
            suite.expect(CompanionSetupSupport.fix(tool: "codex", .notInstalled, language: .enUS)?.contains("Codex isn't installed") == true, "Codex fix")
            suite.expect(CompanionSetupSupport.fix(tool: "claude", .noAnswer(blocked: true, reason: ""), language: .enUS)?.contains("API key") == true, "blocked Claude points to an API key")
            suite.expect(CompanionSetupSupport.fix(tool: "claude", .noAnswer(blocked: false, reason: ""), language: .enUS)?.contains("API key") == false, "other failures do not")
            suite.expect(CompanionSetupSupport.fix(tool: "claude", .ready, language: .enUS) == nil, "ready shows no fix")
            suite.expect(CompanionSetupSupport.looksBlocked("Third-party apps now draw from extra usage"), "blocked subscription text")

            suite.expect(CompanionSetupSupport.statusLabel(nil, checking: false, language: .enUS) == "Not checked yet"
                         && CompanionSetupSupport.statusLabel(.ready, checking: false, language: .enUS) == "Ready"
                         && CompanionSetupSupport.statusLabel(.ready, checking: true, language: .enUS) == "Checking…"
                         && CompanionSetupSupport.statusLabel(.notSignedIn, checking: false, language: .enUS) == "Not signed in",
                         "status labels")
            let limit = "reasoning effort: medium\nuser\nReply\nERROR: You've hit your usage limit. Try again at 3:40 PM.\nERROR: You've hit your usage limit. Try again at 3:40 PM."
            suite.expect(CompanionSetupSupport.reason(from: limit) == "You've hit your usage limit. Try again at 3:40 PM.", "tool's own error line is shown")
            suite.expect(!CompanionSetupSupport.looksBlocked(limit), "a usage limit is not a refused subscription")
            suite.expect(CompanionSetupSupport.looksBlocked("Your organization has disabled Claude subscription access for Claude Code"), "org-disabled subscription")
            suite.expect(CompanionSetupSupport.fix(tool: "codex", .noAnswer(blocked: false, reason: "usage limit"), language: .enUS)?.contains("usage limit") == true, "Codex fix quotes the reason")
            suite.expect(CompanionSetupSupport.actionLabel(.notSignedIn, language: .enUS) == "Sign in" && CompanionSetupSupport.actionLabel(.notInstalled, language: .enUS) == "Install"
                         && CompanionSetupSupport.actionLabel(.ready, language: .enUS) == nil, "action buttons")
            suite.expect(CompanionSetupSupport.loginArguments(for: "cursor-agent") == ["login"], "Cursor sign-in command")
            for language in AppLanguage.allCases {
                let chat = CompanionChatText.values(language)
                suite.expect(chat.count == 5 && chat.allSatisfy { !$0.isEmpty }
                             && chat[0].contains("{ai}") && chat[2].contains("{ai}"), "\(language) has the chat strings")
                let keys = CompanionSetupText.values(language)
                suite.expect(keys.count == 23, "\(language) has every companion setup string")
                suite.expect(keys[CompanionSetupText.Key.fixNotInstalled.rawValue].contains("{ai}")
                             && keys[CompanionSetupText.Key.fixNotInstalled.rawValue].contains("{cmd}")
                             && keys[CompanionSetupText.Key.claudeBlocked.rawValue].contains("{cmd}")
                             && keys[CompanionSetupText.Key.fixNoAnswer.rawValue].contains("{said}")
                             && keys[CompanionSetupText.Key.said.rawValue].contains("{reason}"),
                             "\(language) keeps the placeholders")
                suite.expect(!keys.contains { $0.isEmpty || $0.contains("Grok") }, "\(language) strings are filled in")
                let fix = CompanionSetupSupport.fix(tool: "codex", .noAnswer(blocked: false, reason: "usage limit"), language: language) ?? ""
                suite.expect(fix.contains("Codex") && fix.contains("usage limit") && !fix.contains("{"),
                             "\(language) fix fills every placeholder")
            }
            suite.expect(!SettingsBackupSupport.exportKeys().contains(DefaultsKey.companionChatVerified)
                         && SettingsBackupSupport.exportKeys().contains(DefaultsKey.companionChatAgent),
                         "the pick travels in a backup, the per-Mac verified record does not")
            suite.expect(CompanionSetupSupport.isVerified(["claude": 1], tool: "claude")
                         && !CompanionSetupSupport.isVerified(["claude": 1], tool: "codex")
                         && !CompanionSetupSupport.isVerified([:], tool: "claude"), "a passed test question is remembered per tool")
        }
    }
}
