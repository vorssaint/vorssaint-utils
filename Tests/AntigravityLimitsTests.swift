// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// Antigravity's limits, read from what `agy` prints, kept in Tests/Fixtures/antigravity.
enum AntigravityLimitsTests {
    private static func fixture(_ name: String) -> String {
        (try? String(contentsOfFile: "Tests/Fixtures/antigravity/\(name)", encoding: .utf8)) ?? ""
    }

    private static let observed = Date(timeIntervalSince1970: 1_793_000_000)

    /// Answers each program in turn; records which ran.
    private final class Programs {
        var outputs: [AgentAntigravityAccount.Output]
        var ran: [AgentAntigravityAccount.Command] = []
        init(_ outputs: [AgentAntigravityAccount.Output]) { self.outputs = outputs }
        func run(_ command: AgentAntigravityAccount.Command) -> AgentAntigravityAccount.Output {
            ran.append(command)
            return outputs.isEmpty ? .failed : outputs.removeFirst()
        }
    }

    static func run(_ suite: TestSuite) {
        signIn(suite)
        version(suite)
        parsing(suite)
        flow(suite)
    }

    private static func signIn(_ suite: TestSuite) {
        suite.run("Antigravity sign-in") {
            // nil is a sign-in with a refresh token; anything else is why not.
            suite.expect(AgentAntigravityAccount.signIn(keychain: fixture("keychain_item.txt")) == nil,
                         "a refresh token means signed in")
            suite.expect(AgentAntigravityAccount.signIn(keychain: nil) == .notFound, "no item is not found")
            suite.expect(AgentAntigravityAccount.signIn(keychain: fixture("keychain_item_no_refresh.txt")) == .signedOut,
                         "no refresh token is signed out")
            suite.expect(AgentAntigravityAccount.signIn(keychain: "go-keyring-base64:!!!") == .unreadable,
                         "damaged base64 is unreadable")
            suite.expect(AgentAntigravityAccount.signIn(keychain: "not json") == .unreadable, "not JSON is unreadable")
            let plain = #"{"token":{"refresh_token":"r"}}"#
            suite.expect(AgentAntigravityAccount.signIn(keychain: plain) == nil, "a value without the prefix is read as is")
            suite.expect(AgentAntigravityAccount.signIn(keychain: #"{"token":{"refresh_token":"  "}}"#) == .signedOut,
                         "a blank refresh token is signed out")
        }
    }

    private static func version(_ suite: TestSuite) {
        suite.run("Antigravity version") {
            suite.expect(AgentAntigravityAccount.version(of: fixture("version.txt")) == [1, 4, 12], "reads the version")
            suite.expect(AgentAntigravityAccount.version(of: "agy version 1.1.11 (abc)\n") == [1, 1, 11], "finds it in a sentence")
            suite.expect(AgentAntigravityAccount.version(of: "no number") == nil, "no version")
            suite.expect(AgentAntigravityAccount.accepts([1, 1, 11]) && AgentAntigravityAccount.accepts([2, 0, 0])
                         && !AgentAntigravityAccount.accepts([1, 1, 10]) && !AgentAntigravityAccount.accepts([1, 0, 99]),
                         "1.1.11 is the first that answers /usage itself")
        }
    }

    private static func parsing(_ suite: TestSuite) {
        suite.run("Antigravity limits") {
            guard case .success(let limits) = AgentAntigravityAccount.limits(stdout: fixture("usage.json"), observed: observed) else {
                suite.expect(false, "usage.json should read"); return
            }
            suite.expect(limits.provider == .antigravity && limits.source == .account, "an account reading")
            // Four capped windows and one model's, with the unmetered bucket left out.
            suite.expect(limits.windows.count == 5, "five windows, got \(limits.windows.count)")
            let gemini = limits.windows.filter { $0.scope == "Gemini Models" }
            suite.expectClose(gemini.first { $0.kind == .session }?.usedPercent ?? -1, 20, "Gemini 5-hour used")
            suite.expectClose(gemini.first { $0.kind == .weekly }?.usedPercent ?? -1, 45, "Gemini weekly used")
            suite.expect(gemini.first { $0.kind == .session }?.minutes == 300, "5-hour length")
            suite.expect(gemini.first { $0.kind == .weekly }?.minutes == 10_080, "weekly length")
            suite.expect(gemini.first { $0.kind == .session }?.resetsAt == AgentTimestamp.parse("2026-10-31T12:08:50Z"), "reset time")
            let thirdParty = limits.windows.filter { $0.scope == "Claude and GPT models" }
            suite.expectClose(thirdParty.first { $0.kind == .session }?.usedPercent ?? -1, 0, "third-party 5-hour untouched")
            suite.expectClose(thirdParty.first { $0.kind == .weekly }?.usedPercent ?? -1, 75, "third-party weekly used")
            suite.expect(!limits.windows.contains { $0.id.contains("unmetered") }, "an unmetered bucket is not a window")
            suite.expect(Set(limits.windows.map(\.id)).count == limits.windows.count, "window ids are unique")

            suite.expect(AgentAntigravityAccount.limits(stdout: fixture("usage_prompt.json"), observed: observed) == .failure(.unreadable),
                         "a model turn means /usage went to the model: not the limits")
            suite.expect(AgentAntigravityAccount.limits(stdout: fixture("usage_empty.json"), observed: observed) == .failure(.unreadable),
                         "no groups is unreadable")
            suite.expect(AgentAntigravityAccount.limits(stdout: "garbage", observed: observed) == .failure(.unreadable),
                         "no answer line is unreadable")
        }
    }

    private static func flow(_ suite: TestSuite) {
        suite.run("Antigravity flow") {
            let item = fixture("keychain_item.txt")
            let good = Programs([.text(fixture("version.txt")), .text(fixture("usage.json"))])
            if case .success(let limits) = AgentAntigravityAccount.check(keychain: item, now: observed, run: good.run) {
                suite.expect(limits.windows.count == 5, "limits from /usage")
            } else { suite.expect(false, "a good run reads") }
            suite.expect(good.ran == [.version, .usage], "the version is checked before /usage runs")

            // Not signed in: nothing is run.
            let signedOut = Programs([])
            suite.expect(AgentAntigravityAccount.check(keychain: fixture("keychain_item_no_refresh.txt"), now: observed,
                                                       run: signedOut.run) == .failure(.signedOut), "signed out")
            suite.expect(signedOut.ran.isEmpty, "no program runs without a sign-in")

            // An old agy would send /usage to the model and spend quota: never run it.
            let old = Programs([.text("1.1.10"), .text(fixture("usage.json"))])
            suite.expect(AgentAntigravityAccount.check(keychain: item, now: observed, run: old.run) == .failure(.unreadable),
                         "too old to ask")
            suite.expect(old.ran == [.version], "/usage is not run on an old agy")

            // Not installed (the sign-in is from its IDE), or no version.
            let missing = Programs([.notInstalled])
            suite.expect(AgentAntigravityAccount.check(keychain: item, now: observed, run: missing.run) == .failure(.notFound),
                         "agy not installed")
            let silent = Programs([.text("hello")])
            suite.expect(AgentAntigravityAccount.check(keychain: item, now: observed, run: silent.run) == .failure(.unreadable),
                         "no version in the answer")
            let failed = Programs([.text("1.4.12"), .failed])
            suite.expect(AgentAntigravityAccount.check(keychain: item, now: observed, run: failed.run) == .failure(.unreadable),
                         "/usage failing is unreadable")
            suite.expect(AgentAntigravityAccount.minimumGap == 15 * 60, "agy runs at most every fifteen minutes")
        }
    }
}
