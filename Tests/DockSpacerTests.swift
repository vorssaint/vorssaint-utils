// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

enum DockSpacerTests {
    static func run(_ suite: TestSuite) {
        suite.run("small Dock spacer without automatic restart") {
            withDomain(suite) { domain, original in
                let probe = RestartProbe()
                let service = DockSpacerService(domain: domain, restartDock: {
                    probe.record(domain: domain)
                    return true
                })

                let result = service.perform(.addSmall, restartAfterAdding: false)
                suite.expect(result == .added && result.succeeded,
                             "adding a small spacer reports success without requiring a restart")
                expectAppend(suite, domain: domain, original: original, tileType: "small-spacer-tile")
                suite.expect(probe.snapshots.isEmpty,
                             "adding with automatic restart disabled never invokes the restart callback")
            }
        }

        suite.run("large Dock spacer persists before automatic restart") {
            withDomain(suite) { domain, original in
                let probe = RestartProbe()
                let service = DockSpacerService(domain: domain, restartDock: {
                    probe.record(domain: domain)
                    return true
                })

                let result = service.perform(.addLarge, restartAfterAdding: true)
                suite.expect(result == .restarted && result.succeeded,
                             "adding with a successful automatic restart reports restarted")
                expectAppend(suite, domain: domain, original: original, tileType: "spacer-tile")
                let snapshots = probe.snapshots
                suite.expect(snapshots.count == 1, "automatic restart runs exactly once")
                suite.expect(snapshots.first.flatMap { $0 }.map {
                    NSDictionary(dictionary: $0).isEqual(to: readDomain(domain) ?? [:])
                } == true, "restart observes the already persisted appended tile and unchanged settings")
            }
        }

        suite.run("Dock spacer append survives restart failure") {
            withDomain(suite) { domain, original in
                let probe = RestartProbe()
                let service = DockSpacerService(domain: domain, restartDock: {
                    probe.record(domain: domain)
                    return false
                })

                let result = service.perform(.addSmall, restartAfterAdding: true)
                suite.expect(result == .addedButRestartFailed && !result.succeeded,
                             "a successful append and failed restart report partial success")
                expectAppend(suite, domain: domain, original: original, tileType: "small-spacer-tile")
                suite.expect(probe.snapshots.count == 1,
                             "a failed automatic restart is attempted once without retrying the append")
                suite.expect(probe.snapshots.first.flatMap { $0 }.map {
                    NSDictionary(dictionary: $0).isEqual(to: readDomain(domain) ?? [:])
                } == true, "restart failure leaves the exact persisted state observed before restart")
            }
        }

        suite.run("manual Dock restart ignores automatic restart preference") {
            withDomain(suite) { domain, original in
                let probe = RestartProbe()
                let service = DockSpacerService(domain: domain, restartDock: {
                    probe.record(domain: domain)
                    return true
                })

                let result = service.perform(.restart, restartAfterAdding: false)
                suite.expect(result == .restarted && result.succeeded,
                             "manual restart succeeds while automatic restart is disabled")
                suite.expect(probe.snapshots.count == 1, "manual restart invokes the callback exactly once")
                suite.expect(readDomain(domain).map {
                    NSDictionary(dictionary: $0).isEqual(to: original)
                } == true, "manual restart neither appends a tile nor changes unrelated preferences")
            }
        }
    }

    private static func withDomain(_ suite: TestSuite,
                                   _ body: (String, [String: Any]) -> Void) {
        let domain = "vorss.tests.dock-spacers.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: domain) else {
            suite.expect(false, "isolated Dock preference domain opens")
            return
        }
        defer {
            defaults.removePersistentDomain(forName: domain)
            defaults.synchronize()
        }
        let original: [String: Any] = [
            "persistent-apps": [[
                "GUID": 314159,
                "tile-type": "file-tile",
                "tile-data": ["bundle-identifier": "vorss.tests.existing-app"],
            ]],
            "unrelated-setting": "keep-me",
        ]
        defaults.setPersistentDomain(original, forName: domain)
        guard defaults.synchronize(),
              let persisted = readDomain(domain),
              NSDictionary(dictionary: persisted).isEqual(to: original) else {
            suite.expect(false, "isolated Dock preferences persist before the action")
            return
        }
        body(domain, original)
    }

    // Export through a separate defaults process so a cached UserDefaults value
    // cannot hide either a missing write or a write that happens after restart.
    private static func readDomain(_ domain: String) -> [String: Any]? {
        let result = Shell.run("/usr/bin/defaults", ["export", domain, "-"])
        guard result.status == 0,
              let data = result.output.data(using: .utf8) else { return nil }
        return (try? PropertyListSerialization.propertyList(from: data, options: [], format: nil))
            as? [String: Any]
    }

    private static func expectAppend(_ suite: TestSuite, domain: String,
                                     original: [String: Any], tileType: String) {
        guard let persisted = readDomain(domain),
              let tiles = persisted["persistent-apps"] as? [[String: Any]],
              let originalTiles = original["persistent-apps"] as? [[String: Any]] else {
            suite.expect(false, "spacer action leaves a readable persistent-apps array")
            return
        }
        suite.expect(tiles.count == originalTiles.count + 1,
                     "exactly one spacer is appended to existing Dock items")
        suite.expect(tiles.first.map {
            NSDictionary(dictionary: $0).isEqual(to: originalTiles[0])
        } == true, "the existing Dock app sentinel remains unchanged and in place")
        suite.expect(tiles.last?["tile-type"] as? String == tileType,
                     "the appended tile persists the requested Dock spacer type")
        var unrelated = persisted
        unrelated.removeValue(forKey: "persistent-apps")
        var expectedUnrelated = original
        expectedUnrelated.removeValue(forKey: "persistent-apps")
        suite.expect(NSDictionary(dictionary: unrelated).isEqual(to: expectedUnrelated),
                     "adding a spacer preserves all unrelated preference keys")
    }

    private final class RestartProbe: @unchecked Sendable {
        private let lock = NSLock()
        private var recorded: [[String: Any]?] = []

        var snapshots: [[String: Any]?] {
            lock.withLock { recorded }
        }

        func record(domain: String) {
            let snapshot = DockSpacerTests.readDomain(domain)
            lock.withLock { recorded.append(snapshot) }
        }
    }
}
