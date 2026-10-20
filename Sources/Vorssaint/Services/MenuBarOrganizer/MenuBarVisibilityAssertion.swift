// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation
import MenuBarVisibilityBridge

/// Swift face of the private menu bar assessment mode: an allowlist of bundle
/// ids and system items, everything else hidden while a handle is alive. The
/// system drops the restriction by itself when the process ends, so a crash
/// can never leave icons hidden. Main thread only.
final class MenuBarVisibilityAssertion {
    static var isAvailable: Bool { VSMenuBarVisibilityAvailable() }

    private var handle: Any?
    /// Advances on every activate and release, so an answer that arrives
    /// after the caller moved on is recognised and its handle given back.
    private var generation = 0

    var isActive: Bool { handle != nil }

    /// Hides everything outside the allowlist. While another restriction is
    /// held it stays until the new one is live, so icons never flash in
    /// between; on failure both are dropped and the bar is shown (fail open).
    /// `completion` gets nil on success, otherwise the reason. It is not called
    /// when a later activate or release superseded this request.
    func activate(bundles: [String], systemItems: [Int], completion: @escaping (String?) -> Void) {
        generation += 1
        let requested = generation
        // An empty bundle list would hide every third-party icon, including
        // the collapser that brings them back.
        guard !bundles.isEmpty else {
            release()
            completion("empty allowlist")
            return
        }
        VSMenuBarVisibilityActivate(bundles, systemItems.map { NSNumber(value: $0) }) { [weak self] new, error in
            guard let self, self.generation == requested else {
                if let new { VSMenuBarVisibilityRelease(new) }
                return
            }
            let previous = self.handle
            self.handle = new
            if let previous { VSMenuBarVisibilityRelease(previous) }
            completion(new == nil ? (error?.localizedDescription ?? "unknown error") : nil)
        }
    }

    /// Shows the bar again and abandons any activation still in flight.
    func release() {
        generation += 1
        guard let handle else { return }
        self.handle = nil
        VSMenuBarVisibilityRelease(handle)
    }

    deinit {
        if let handle { VSMenuBarVisibilityRelease(handle) }
    }
}
