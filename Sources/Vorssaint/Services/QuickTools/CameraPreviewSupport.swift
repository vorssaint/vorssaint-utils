// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// Queued capture configuration can be cancelled before it touches a device.
/// The serial capture queue still owns every actual session mutation.
final class CameraPreviewRequest: @unchecked Sendable {
    private let lock = NSLock()
    private var cancelled = false
    var isCancelled: Bool { lock.lock(); defer { lock.unlock() }; return cancelled }
    func cancel() { lock.lock(); cancelled = true; lock.unlock() }
}

enum NotchCameraSupport {
    static func isEnabled(in defaults: UserDefaults = .standard) -> Bool {
        NotchSupport.isEnabled(in: defaults) && AppFeature.cameraPreview.isAvailable(in: defaults)
            && defaults.bool(forKey: DefaultsKey.notchCameraEnabled)
            && NotchSupport.modules(in: defaults).contains(.camera)
    }

    static func canPresent(expanded: Bool, selected: NotchModule, appPanel: Bool,
                           captureControls: Bool, in defaults: UserDefaults = .standard) -> Bool {
        isEnabled(in: defaults) && expanded && selected == .camera && !appPanel && !captureControls
    }
}

/// The mirror's optional microphone ring. It listens only when the user
/// turned it on and already granted the microphone; the mirror never asks.
enum CameraMicActivitySupport {
    /// Quiet room noise stays below this, a normal speaking voice is well above.
    static let thresholdDB: Float = -45
    /// Keeps the ring lit across the short gaps between words.
    static let hold: TimeInterval = 0.4

    static func listens(microphoneAuthorized: Bool, in defaults: UserDefaults = .standard) -> Bool {
        microphoneAuthorized && defaults.bool(forKey: DefaultsKey.cameraPreviewMicActivity)
    }

    static func isLoud(_ levelDB: Float) -> Bool { levelDB > thresholdDB }

    static func isActive(lastLoudAt: Date?, now: Date) -> Bool {
        lastLoudAt.map { now.timeIntervalSince($0) < hold } ?? false
    }
}
