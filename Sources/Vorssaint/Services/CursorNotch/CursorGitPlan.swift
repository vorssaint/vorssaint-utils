// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

struct CursorPullRequest: Equatable {
    var number: Int
    var title: String
    var url: String
    var state: String
    var isDraft: Bool
    var mergeable: String
    var base: String
    var head: String
    var checksFailed: Bool
    var checksPending: Bool
}

struct CursorGitSnapshot: Equatable {
    var isRepository = false
    var branch = ""
    var detached = false
    var dirty = false
    var ahead = 0
    var remote = "origin"
    var defaultBranch = ""
    var authenticated = false
    var ghMissing = false
    var pullRequest: CursorPullRequest?
    var error = ""

    var onDefaultBranch: Bool {
        !defaultBranch.isEmpty && branch == defaultBranch
    }

    var canCreate: Bool {
        isRepository && !detached && !onDefaultBranch && authenticated && !ghMissing && error.isEmpty
    }

    var canMerge: Bool {
        guard let pullRequest else { return false }
        return authenticated && pullRequest.mergeable == "MERGEABLE" && !pullRequest.checksFailed
    }
}

enum CursorGitPlan {
    static func candidates(home: String, searchPath: String?) -> [String] {
        let folders = [home + "/.local/bin", "/opt/homebrew/bin", "/usr/local/bin"]
            + (searchPath ?? "").split(separator: ":").map(String.init).filter { $0.hasPrefix("/") }
        return folders.map { $0 + "/gh" }
    }

    static func branch(from output: String) -> (name: String, detached: Bool) {
        let name = output.trimmingCharacters(in: .whitespacesAndNewlines)
        if name.isEmpty || name == "HEAD" { return ("", true) }
        return (name, false)
    }

    static func dirty(from porcelain: String) -> Bool {
        !porcelain.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    static func ahead(from output: String) -> Int {
        Int(output.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0
    }

    static func remote(from output: String) -> String {
        let name = output.trimmingCharacters(in: .whitespacesAndNewlines)
        if name.isEmpty || name == "@{u}" { return "origin" }
        let head = name.split(separator: "/").first.map(String.init) ?? ""
        return head.isEmpty ? "origin" : head
    }

    static func defaultBranch(from json: String) -> String {
        guard let object = jsonObject(json),
              let ref = object["defaultBranchRef"] as? [String: Any],
              let name = ref["name"] as? String else { return "" }
        return name
    }

    static func authenticated(status: Int32) -> Bool {
        status == 0
    }

    static func pullRequest(from json: String) -> CursorPullRequest? {
        guard let object = jsonObject(json), let number = int(object["number"]) else { return nil }
        let checks = object["statusCheckRollup"] as? [[String: Any]] ?? []
        let failed = checks.contains { conclusion($0) == "FAILURE" || conclusion($0) == "CANCELLED" || conclusion($0) == "TIMED_OUT" }
        let pending = checks.contains { conclusion($0) == nil || conclusion($0) == "" || conclusion($0) == "PENDING" }
        return CursorPullRequest(
            number: number,
            title: object["title"] as? String ?? "",
            url: object["url"] as? String ?? "",
            state: object["state"] as? String ?? "",
            isDraft: object["isDraft"] as? Bool ?? false,
            mergeable: object["mergeable"] as? String ?? "",
            base: (object["baseRefName"] as? String) ?? "",
            head: (object["headRefName"] as? String) ?? "",
            checksFailed: failed,
            checksPending: pending && !failed
        )
    }

    static func canOpen(url: String, expectedHost: String) -> Bool {
        guard let parsed = URL(string: url), parsed.scheme == "https",
              let host = parsed.host, !expectedHost.isEmpty, host == expectedHost else { return false }
        return true
    }

    static func host(of url: String) -> String {
        URL(string: url)?.host ?? ""
    }

    static func pushArguments(remote: String) -> [String] {
        ["push", "-u", remote.isEmpty ? "origin" : remote, "HEAD"]
    }

    static func createArguments(draft: Bool, base: String, title: String) -> [String] {
        var arguments = ["pr", "create", "--fill", "--base", base.isEmpty ? "main" : base]
        if draft { arguments.append("--draft") }
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { arguments.append(contentsOf: ["--title", trimmed]) }
        return arguments
    }

    static func mergeArguments(number: Int, method: CursorNotchMergeMethod, deleteBranch: Bool) -> [String] {
        var arguments = ["pr", "merge", String(number), "--" + method.rawValue]
        if deleteBranch { arguments.append("--delete-branch") }
        return arguments
    }

    static func refusesUnsafe(_ arguments: [String]) -> Bool {
        let blocked = ["--force", "--force-with-lease", "--admin", "--auto"]
        return arguments.contains { blocked.contains($0) }
    }

    private static func jsonObject(_ text: String) -> [String: Any]? {
        guard let data = text.data(using: .utf8) else { return nil }
        return try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    }

    private static func int(_ value: Any?) -> Int? {
        if let int = value as? Int { return int }
        if let number = value as? NSNumber { return number.intValue }
        return nil
    }

    private static func conclusion(_ check: [String: Any]) -> String? {
        if let conclusion = check["conclusion"] as? String { return conclusion }
        if let state = check["state"] as? String { return state }
        return nil
    }
}
