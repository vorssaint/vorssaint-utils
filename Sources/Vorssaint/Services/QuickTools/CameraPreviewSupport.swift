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
