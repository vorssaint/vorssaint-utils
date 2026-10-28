// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

enum TrackpadGuardSupport {
    /// Uses the shared app picker identities. Wine's temporary executable path
    /// changes at launch, so selected .exe paths also match by file name.
    static func matches(apps: [String], identities: [String], executablePath: String?) -> Bool {
        let selected = Set(apps)
        if identities.contains(where: selected.contains) { return true }
        guard let executablePath else { return false }
        let name = URL(fileURLWithPath: executablePath).lastPathComponent.lowercased()
        guard name.hasSuffix(".exe") else { return false }
        return apps.contains {
            $0.hasPrefix("/") && URL(fileURLWithPath: $0).lastPathComponent.lowercased() == name
        }
    }

    static func shouldIgnore(enabled: Bool, selectedAppInFront: Bool,
                             mousePresent: Bool, sessionActive: Bool, awake: Bool) -> Bool {
        enabled && selectedAppInFront && mousePresent && sessionActive && awake
    }

    /// An explicit system preference changed during a lease wins over the
    /// captured baseline. A runtime value of 0 already restored usable input.
    static func restorationTarget(original: Int, current: Int,
                                  savedAtCapture: Int?, savedNow: Int?) -> Int? {
        guard current == 1 else { return nil }
        if savedAtCapture != savedNow, let savedNow { return savedNow }
        return original
    }

    /// Transport is not enough: a built-in trackpad also conforms to Mouse,
    /// and a virtual mouse must not make the user's only trackpad unusable.
    static func isExternalMouse(conformsToMouse: Bool, builtIn: Bool,
                                accelerationType: String?, transport: String?) -> Bool {
        guard conformsToMouse, !builtIn, accelerationType != "HIDTrackpadAcceleration",
              let transport else { return false }
        return ["usb", "bluetooth", "bluetooth low energy"].contains(transport.lowercased())
    }
}

/// The service's actual lease boundary, injectable without changing live input
/// in unit tests. Failure latches until an explicit preference sync retries it.
protocol TrackpadGuardLeaseHandle: AnyObject {
    func heartbeat() -> Bool
    func stop() -> Bool
}

final class TrackpadGuardSession {
    private let acquire: () -> TrackpadGuardLeaseHandle?
    private var lease: TrackpadGuardLeaseHandle?
    private var restored = true
    private(set) var failed = false
    var isIgnoring: Bool { lease != nil }

    init(acquire: @escaping () -> TrackpadGuardLeaseHandle?) { self.acquire = acquire }

    func update(shouldIgnore: Bool) {
        guard shouldIgnore else { stop(); return }
        guard !failed, lease == nil else { return }
        guard let acquired = acquire() else { failed = true; return }
        lease = acquired
    }

    func heartbeat() {
        guard let lease else { return }
        if !lease.heartbeat() {
            stop()
            failed = true
        }
    }

    @discardableResult
    func stop() -> Bool {
        guard let lease else { return restored }
        self.lease = nil
        restored = lease.stop()
        failed = failed || !restored
        return restored
    }

    func retry() {
        guard lease == nil else { return }
        failed = false
        restored = true
    }
}

/// Raw MultitouchSupport contacts can still reach Vorssaint while macOS ignores
/// the native trackpad. Its own tap actions must observe the same boundary.
enum TrackpadGuardInputGate {
    private static let lock = NSLock()
    private static var active = false
    static var isActive: Bool { lock.withLock { active } }
    static func setActive(_ value: Bool) { lock.withLock { active = value } }
}
