// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

enum HermesInstalledVersionTests {
    static func run(_ suite: TestSuite) {
        let head = String(repeating: "a", count: 40)
        let original: [String: Any] = [
            "schemaVersion": 2, "commit": head, "source": "git",
            "updateMechanism": "self", "payload": "bootstrap", "baseVersion": "0.22.2"
        ]
        func data(_ changes: [String: Any] = [:]) -> Data {
            try! JSONSerialization.data(withJSONObject: original.merging(changes) { _, new in new })
        }
        suite.expect(HermesInstalledVersion.version(stamp: data(), head: head) == "0.22.2",
                     "bootstrap detection reads the agent release, not the fixed launcher version")
        suite.expect(HermesInstalledVersion.version(stamp: data(["baseVersion": "0.22.3"]), head: head) == "0.22.3",
                     "the next scan follows metadata written by hermes update")
        for changes: [String: Any] in [
            ["commit": String(repeating: "b", count: 40)], ["baseVersion": "unknown"],
            ["baseVersion": "0.22.2\n"], ["payload": "light"], ["source": "fallback"],
            ["updateMechanism": "external"], ["schemaVersion": 99]
        ] {
            suite.expect(HermesInstalledVersion.version(stamp: data(changes), head: head) == nil,
                         "stale, unsupported or malformed metadata cannot claim an installed version: \(changes)")
        }
        suite.expect(HermesInstalledVersion.version(stamp: Data("not json".utf8), head: head) == nil,
                     "corrupt metadata is uncomparable")
        suite.expect(HermesInstalledVersion.version(stamp: Data(repeating: 32, count: 65_537), head: head) == nil,
                     "oversized metadata is bounded")
        let home = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: home) }
        let repo = home.appendingPathComponent(".hermes/hermes-agent")
        try! FileManager.default.createDirectory(at: repo, withIntermediateDirectories: true)
        func git(_ arguments: [String]) -> String {
            let result = BoundedProcessRunner.run("/usr/bin/git", ["-C", repo.path] + arguments,
                                                  timeout: 2, maxOutputBytes: 4096)
            suite.expect(result.status == 0, "fixture git command succeeds: \(arguments)")
            return String(decoding: result.output, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        _ = git(["init", "--quiet"])
        _ = git(["-c", "user.name=Test", "-c", "user.email=test@example.com",
                 "-c", "commit.gpgsign=false", "commit", "--quiet", "--allow-empty", "-m", "fixture"])
        let liveHead = git(["rev-parse", "HEAD"])
        let stamp = repo.appendingPathComponent("install-stamp.json")
        try! data(["commit": liveHead]).write(to: stamp)
        let id = HermesInstalledVersion.bootstrapBundleID
        suite.expect(HermesInstalledVersion.resolve(bundleID: id, bundleVersion: "0.0.1", home: home) == "0.22.2",
                     "real filesystem and git scan resolve the installed agent")
        try! data(["commit": liveHead, "baseVersion": "0.22.3"]).write(to: stamp)
        suite.expect(HermesInstalledVersion.resolve(bundleID: id, bundleVersion: "0.0.1", home: home) == "0.22.3",
                     "no cached launcher value survives an agent update")
        try! data().write(to: stamp)
        suite.expect(HermesInstalledVersion.resolve(bundleID: id, bundleVersion: "0.0.1", home: home).isEmpty,
                     "a stale stamp becomes uncomparable instead of a false outdated result")
        try! FileManager.default.removeItem(at: stamp)
        suite.expect(HermesInstalledVersion.resolve(bundleID: id, bundleVersion: "0.0.1", home: home).isEmpty,
                     "missing metadata does not revert to bootstrap version")
        suite.expect(HermesInstalledVersion.resolve(bundleID: "com.nousresearch.hermes", bundleVersion: "0.22.2", home: home) == "0.22.2",
                     "ordinary Hermes Desktop bundles retain their own version")
        suite.expect(HermesInstalledVersion.resolve(bundleID: "com.example.other", bundleVersion: "3.4", home: home) == "3.4",
                     "unrelated apps retain their own version")
        let app = AppUpdatesSupport.InstalledApp(name: "Hermes", bundleID: id,
            path: "/Applications/Hermes.app", version: "0.22.2", isFromAppStore: false)
        func findings(_ latest: String) -> (items: [AppUpdatesSupport.Item], checkedPaths: Set<String>,
                                           uncomparableApps: [AppUpdatesSupport.InstalledApp]) {
            let entry = AppUpdatesSupport.CatalogEntry(token: "hermes", version: latest,
                appNames: ["Hermes.app"], bundleIDs: [id], minimumOSVersions: [],
                exactOSVersions: [], hasUnsupportedOSConstraint: false)
            return AppUpdatesSupport.onlineCatalogFindings(apps: [app], catalog: [entry],
                                                          operatingSystemVersion: "26.0")
        }
        let old = findings("0.21.2")
        suite.expect(old.items.isEmpty && old.checkedPaths.contains(app.path),
                     "the false update disappears while Hermes remains checked, with no exclusion rule")
        let next = findings("0.22.3")
        suite.expect(next.items.count == 1 && next.items.first?.installedVersion == "0.22.2"
                     && next.items.first?.latestVersion == "0.22.3",
                     "the normal catalog pipeline surfaces a real future release")
    }
}
