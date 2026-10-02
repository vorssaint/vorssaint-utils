// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// Reads git and `gh` for the open Cursor chat. Commands are argument arrays
/// in the workspace folder. A remote session never runs them.
enum CursorGitService {
    static func refresh(root: String, remote: Bool) -> CursorGitSnapshot {
        guard !remote else { return CursorGitSnapshot() }
        guard !root.isEmpty, FileManager.default.fileExists(atPath: root) else { return CursorGitSnapshot() }
        let git = "/usr/bin/git"
        let inside = run(git, ["rev-parse", "--is-inside-work-tree"], root)
        guard inside.status == 0, inside.text.trimmingCharacters(in: .whitespacesAndNewlines) == "true" else {
            return CursorGitSnapshot()
        }
        var snapshot = CursorGitSnapshot(isRepository: true)
        let head = CursorGitPlan.branch(from: run(git, ["rev-parse", "--abbrev-ref", "HEAD"], root).text)
        snapshot.branch = head.name
        snapshot.detached = head.detached
        snapshot.dirty = CursorGitPlan.dirty(from: run(git, ["status", "--porcelain"], root).text)
        let ahead = run(git, ["rev-list", "--count", "@{u}..HEAD"], root)
        snapshot.ahead = ahead.status == 0 ? CursorGitPlan.ahead(from: ahead.text) : 0
        let upstream = run(git, ["rev-parse", "--abbrev-ref", "--symbolic-full-name", "@{u}"], root)
        snapshot.remote = upstream.status == 0 ? CursorGitPlan.remote(from: upstream.text) : "origin"
        guard let gh = executable() else {
            snapshot.ghMissing = true
            return snapshot
        }
        let auth = run(gh, ["auth", "status"], root)
        snapshot.authenticated = CursorGitPlan.authenticated(status: auth.status)
        guard snapshot.authenticated else { return snapshot }
        let repo = run(gh, ["repo", "view", "--json", "defaultBranchRef"], root)
        if repo.status == 0 { snapshot.defaultBranch = CursorGitPlan.defaultBranch(from: repo.text) }
        let pr = run(gh, ["pr", "view", "--json",
                          "number,title,url,state,isDraft,mergeable,mergeStateStatus,reviewDecision,statusCheckRollup,baseRefName,headRefName"], root)
        if pr.status == 0 { snapshot.pullRequest = CursorGitPlan.pullRequest(from: pr.text) }
        else if pr.status != 1 && !pr.text.isEmpty { snapshot.error = pr.text }
        return snapshot
    }

    static func pushAndCreate(root: String, remote: String, draft: Bool, base: String, title: String) -> String {
        let git = run("/usr/bin/git", CursorGitPlan.pushArguments(remote: remote), root)
        guard git.status == 0, let gh = executable() else { return git.text.isEmpty ? "git push failed" : git.text }
        let created = run(gh, CursorGitPlan.createArguments(draft: draft, base: base, title: title), root)
        return created.status == 0 ? "" : created.text
    }

    static func merge(root: String, number: Int, method: CursorNotchMergeMethod, deleteBranch: Bool) -> String {
        guard let gh = executable() else { return "gh" }
        let result = run(gh, CursorGitPlan.mergeArguments(number: number, method: method, deleteBranch: deleteBranch), root)
        return result.status == 0 ? "" : result.text
    }

    static func executable(home: String = NSHomeDirectory(),
                           searchPath: String? = loginPath()) -> String? {
        CursorGitPlan.candidates(home: home, searchPath: searchPath).first { path in
            FileManager.default.isExecutableFile(atPath: path)
        }
    }

    private static func loginPath() -> String? {
        let result = BoundedProcessRunner.run("/bin/zsh", ["-lc", "printenv PATH"], timeout: 5, maxOutputBytes: 8_192)
        guard result.status == 0 else { return nil }
        return String(data: result.output, encoding: .utf8)
    }

    private static func run(_ path: String, _ arguments: [String], _ root: String) -> (status: Int32, text: String) {
        guard !CursorGitPlan.refusesUnsafe(arguments) else { return (-1, "") }
        let result = BoundedProcessRunner.run(path, arguments, timeout: 60, maxOutputBytes: 256 * 1024, directory: root)
        let text = String(data: result.output, encoding: .utf8) ?? ""
        return (result.timedOut ? -1 : result.status, text.trimmingCharacters(in: .whitespacesAndNewlines))
    }
}
