// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit

/// Drives the real resolver actor with a scanner that never reads Accessibility.
/// In particular it can finish after cancellation to exercise stale completion.
enum MenuBarItemSourceResolverTests {
    actor Scanner {
        var calls = 0
        var blockNext = false
        var pending: CheckedContinuation<[CGWindowID: MenuBarItemSourceIdentity], Never>?
        var blockedResult: [CGWindowID: MenuBarItemSourceIdentity] = [:]
        func block() { blockNext = true }
        func scan(_ records: [MenuBarOrganizerWindowRecord]) async -> [CGWindowID: MenuBarItemSourceIdentity] {
            calls += 1
            let matches = Dictionary(uniqueKeysWithValues: records.map { record in
                (record.windowID, MenuBarItemSourceIdentity(pid: pid_t(100 + calls), bundleIdentifier: "test.source",
                    name: "Source", axIdentifier: "item", axTitle: nil))
            })
            if blockNext {
                blockNext = false
                blockedResult = matches
                return await withCheckedContinuation { pending = $0 }
            }
            return matches
        }
        func waitForBlock() async {
            while pending == nil { await Task.yield() }
        }
        func release() { pending?.resume(returning: blockedResult); pending = nil }
    }

    static func run(_ suite: TestSuite) {
        let done = DispatchSemaphore(value: 0)
        let task = Task.detached {
            await exercise(suite)
            done.signal()
        }
        let completed = done.wait(timeout: .now() + 10) == .success
        suite.expect(completed, "resolver concurrency checks complete within their bounded deadline")
        if !completed { task.cancel() }
    }

    private static func exercise(_ suite: TestSuite) async {
        let scanner = Scanner()
        let resolver = MenuBarItemSourceResolver(isTrusted: { true }, scanner: { await scanner.scan($0) })
        let original = record()
        let first = await resolver.resolve(records: [original])
        suite.expect(first[1]?.pid == 101, "hosted items use the injected source scan")
        _ = await resolver.resolve(records: [original])
        _ = await resolver.resolve(records: [record(x: 400)])
        let reusedCalls = await scanner.calls
        suite.expect(reusedCalls == 1, "polling and moving the same window reuse its identity")
        _ = await resolver.resolve(records: [record(owner: 20)])
        let replacedCalls = await scanner.calls
        suite.expect(replacedCalls == 2, "a reused window ID with a different host is resolved afresh")
        _ = await resolver.resolve(records: [record(owner: 20)], refresh: true)
        let forcedCalls = await scanner.calls
        suite.expect(forcedCalls == 3, "a new operation can force a fresh identity scan")

        await scanner.block()
        let old = Task { await resolver.resolve(records: [original], refresh: true) }
        await scanner.waitForBlock()
        await resolver.invalidate()
        await scanner.release()
        let invalidated = await old.value
        suite.expect(invalidated.isEmpty, "invalidated in-flight results are neither returned nor cached")
        let fresh = await resolver.resolve(records: [original])
        suite.expect(fresh[1]?.pid == 105, "the next request scans instead of reusing the invalidated identity")

        await scanner.block()
        let cancelled = Task { await resolver.resolve(records: [original], refresh: true) }
        await scanner.waitForBlock()
        cancelled.cancel()
        await scanner.release()
        let cancelledResult = await cancelled.value
        suite.expect(cancelledResult.isEmpty, "a cancelled caller cannot publish late scanner results")
        let afterCancellation = await resolver.resolve(records: [original])
        suite.expect(afterCancellation[1]?.pid == 107, "cancellation cannot populate the next request's cache")
        _ = await resolver.resolve(records: [])
        _ = await resolver.resolve(records: [original])
        let afterRemoval = await scanner.calls
        suite.expect(afterRemoval == 8, "disappearing windows lose cached identities")

        await scanner.block()
        let disappeared = Task { await resolver.resolve(records: [original], refresh: true) }
        await scanner.waitForBlock()
        _ = await resolver.resolve(records: [])
        await scanner.release()
        let staleRemoval = await disappeared.value
        suite.expect(staleRemoval.isEmpty, "an empty inventory invalidates a pending scan")
        let reappeared = await resolver.resolve(records: [original])
        suite.expect(reappeared[1]?.pid == 110, "a reappearing window cannot reuse a removed scan result")
    }

    private static func record(owner: pid_t = 10, x: CGFloat = 100) -> MenuBarOrganizerWindowRecord {
        .init(windowID: 1, ownerPID: owner, ownerName: "Control Center",
              ownerBundleIdentifier: MenuBarOrganizerSupport.controlCenterBundleIdentifier,
              title: "Item-1", frame: CGRect(x: x, y: 0, width: 20, height: 24),
              layer: 25, alpha: 1, isOnScreen: true)
    }
}
