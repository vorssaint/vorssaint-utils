// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit

/// Drives the production cache with synthetic pixels. Never requests a real
/// permission, captures a screen/window, or creates a status item.
enum MenuBarItemPreviewTests {
    static func run(_ suite: TestSuite) {
        MainActor.assumeIsolated {
            func settle(_ condition: () -> Bool) -> Bool {
                let deadline = Date().addingTimeInterval(3)
                while !condition(), Date() < deadline {
                    RunLoop.current.run(until: Date().addingTimeInterval(0.01))
                }
                return condition()
            }
            let context = CGContext(data: nil, width: 48, height: 48, bitsPerComponent: 8,
                                    bytesPerRow: 192, space: CGColorSpaceCreateDeviceRGB(),
                                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
            let pixels = context.makeImage()!
            let item = ManagedMenuBarItem(id: .init(bundleIdentifier: "test.app", title: "icon", occurrence: 0),
                windowID: 1, ownerPID: 42, ownerBundleIdentifier: "test.app", sourcePID: 42,
                ownerName: "Test", sourceName: "Test", bundleIdentifier: "test.app", title: "icon",
                frame: CGRect(x: 500, y: 0, width: 24, height: 24), section: .visible,
                identityState: .stable, isMovable: true, isProtected: false)
            var allowed = false
            var valid = true
            var calls = 0
            var pending: CheckedContinuation<CGImage?, Never>?
            var block = false
            var returned = 0
            let provider = MenuBarItemPreviewProvider(permitted: { allowed }, validate: { _ in valid }, capture: { _ in
                calls += 1
                defer { returned += 1 }
                if block { return await withCheckedContinuation { pending = $0 } }
                return pixels
            })
            provider.refresh([item])
            suite.expect(calls == 0 && provider.images.isEmpty, "permission denial never invokes capture")
            allowed = true
            provider.refresh([item])
            suite.expect(settle { provider.images[1] != nil }, "runtime pixels populate the matching status item")
            suite.expect(provider.images[1]?.size == item.frame.size, "preview retains native menu-bar proportions")
            allowed = false
            provider.refresh([item])
            suite.expect(provider.images.isEmpty, "permission revocation immediately discards captured pixels")

            allowed = true
            block = true
            provider.refresh([item])
            suite.expect(settle { pending != nil }, "capture can be suspended deterministically")
            provider.stop()
            let previousReturns = returned
            pending?.resume(returning: pixels)
            pending = nil
            suite.expect(settle { returned > previousReturns }, "cancelled capture may finish without blocking teardown")
            suite.expect(provider.images.isEmpty, "late capture cannot repopulate a closed editor")

            provider.refresh([item])
            suite.expect(settle { pending != nil }, "new capture starts after teardown")
            valid = false // Window ID was recycled while capture was in flight.
            let returnsBeforeReuse = returned
            pending?.resume(returning: pixels)
            pending = nil
            suite.expect(settle { returned > returnsBeforeReuse }, "recycled-window capture completes")
            suite.expect(provider.images.isEmpty, "ownership is validated again before publishing pixels")
            provider.stop()
            let callsBeforeInvalid = calls
            provider.refresh([item])
            var drained = false
            Task { @MainActor in await Task.yield(); drained = true }
            suite.expect(settle { drained }, "invalid-target task drains")
            suite.expect(calls == callsBeforeInvalid, "invalid status windows are never captured")
            provider.stop()
        }
    }
}
