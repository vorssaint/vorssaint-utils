// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import Foundation

/// The sizes the floating mirror offers from its right-click menu. The
/// notch-embedded camera keeps the notch's geometry, so only the floating
/// panel reads this.
enum CameraPreviewWindowSize: String, CaseIterable {
    case small, medium, large

    /// Every size keeps the 4-to-3 shape the mirror ships as, so the image
    /// crops the same way at all of them.
    var pixelSize: CGSize {
        switch self {
        case .small: return CGSize(width: 240, height: 180)
        case .medium: return CGSize(width: 320, height: 240)
        case .large: return CGSize(width: 480, height: 360)
        }
    }

    static func saved(in defaults: UserDefaults = .standard) -> CameraPreviewWindowSize {
        CameraPreviewWindowSize(rawValue: defaults.string(forKey: DefaultsKey.cameraPreviewWindowSize) ?? "") ?? .medium
    }

    func save(in defaults: UserDefaults = .standard) {
        defaults.set(rawValue, forKey: DefaultsKey.cameraPreviewWindowSize)
    }

    func menuTitle(_ text: CameraPreviewFeatureStrings) -> String {
        switch self {
        case .small: return text.sizeSmall
        case .medium: return text.sizeMedium
        case .large: return text.sizeLarge
        }
    }

    /// The frame for a new mirror size, keeping the horizontal center and the
    /// top edge of the old frame: the mirror lives near the top of the screen
    /// next to the camera, so a bigger choice grows downward, never upward
    /// past the menu bar. Clamped with the same 16 pt margin the first
    /// placement uses.
    static func adjustedFrame(from current: NSRect, to size: CGSize, in screen: NSRect) -> NSRect {
        let x = max(screen.minX + 16, min(current.midX - size.width / 2, screen.maxX - size.width - 16))
        let y = max(screen.minY + 16, current.maxY - size.height)
        return NSRect(x: x, y: y, width: size.width, height: size.height)
    }
}

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
