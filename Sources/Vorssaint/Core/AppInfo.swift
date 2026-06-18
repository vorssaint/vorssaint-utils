// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// Static identity of the app, shared by UI, notifications and tooling.
enum AppInfo {
    static let name = "MemoryKill"
    static let copyright = "© 2026 MemoryKill (fork of Vorssaint)"
    static let repositoryURL = URL(string: "https://github.com/vorssaint/vorssaint-utils")!
    /// Buy Me a Coffee page. The project stays free; donations and stars are how
    /// the community keeps it alive. Confirm the handle is exactly right before
    /// shipping to main.
    static let donateURL = URL(string: "https://buymeacoffee.com/vorssaint")!

    /// The bundle version. The fallback only applies to the bare binary
    /// (e.g. `--selftest`), never the shipped app, which reads its Info.plist.
    static var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev"
    }

    /// True for the local "Vorssaint (Developer)" build (bundle id ends in `.dev`).
    /// It is never published and never auto-updates; all work is tested here first.
    static var isDeveloperBuild: Bool {
        (Bundle.main.bundleIdentifier ?? "").hasSuffix(".dev")
    }

    /// The git commit a Developer build was compiled from, e.g. "ed2ebba · 2026-06-15 21:30"
    /// (or with a "-dirty" suffix on the SHA for uncommitted changes). build.sh stamps
    /// this into the Developer bundle only, so you can confirm at a glance that the
    /// running dev app matches the source you are about to change. nil in the official app.
    static var buildCommit: String? {
        Bundle.main.object(forInfoDictionaryKey: "VorssaintBuildCommit") as? String
    }
}
