// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// A tool's mark and name as the Tools page draws them, shared with Home's
/// tile for the last tool opened. A toggle names what a click will do.
extension QuickLauncherItem {
    func symbol(keepAwake: Bool, muted: Bool, recording: Bool) -> String {
        switch self {
        case .keepAwake: return keepAwake ? "bolt.fill" : "bolt"
        case .toggles: return "togglepower"
        case .micMute: return muted ? "mic.slash.fill" : "mic"
        case .screenOCR: return "text.viewfinder"
        case .colorPicker: return "eyedropper"
        case .clipboard: return "doc.on.clipboard"
        case .windowLayout: return "rectangle.3.group"
        case .cleaning: return "keyboard"
        case .homebrew: return "shippingbox"
        case .media: return "photo.on.rectangle.angled"
        case .urlCleaner: return "link"
        case .uninstaller: return "trash"
        case .cleaner: return "sparkle"
        case .screenshot: return "camera.viewfinder"
        case .screenRecorder: return recording ? "stop.circle" : "record.circle"
        case .cameraPreview: return "web.camera"
        case .scratchpad: return "note.text"
        }
    }

    func title(_ l10n: L10n, muted: Bool, recording: Bool) -> String {
        switch self {
        case .keepAwake: return l10n.s.keepAwakeTitle
        case .toggles: return FeatureStrings.quickToggles(l10n.language).pageTitle
        case .micMute: return muted ? l10n.s.micUnmuteName : l10n.s.micMuteName
        case .screenOCR: return l10n.s.ocrName
        case .colorPicker: return l10n.s.colorPickerName
        case .clipboard: return FeatureStrings.clipboard(l10n.language).title
        case .windowLayout: return FeatureStrings.windowLayout(l10n.language).title
        case .cleaning: return l10n.s.cleaningMenuItem
        case .homebrew: return l10n.s.homebrewName
        case .media: return l10n.s.mediaName
        case .urlCleaner: return l10n.s.urlCleanerName
        case .uninstaller: return l10n.s.uninstallerName
        case .cleaner: return l10n.s.cleanerName
        case .screenshot: return FeatureStrings.screenshot(l10n.language).pageTitle
        case .screenRecorder:
            let strings = FeatureStrings.recorder(l10n.language)
            return recording ? strings.stopButton : strings.pageTitle
        case .cameraPreview: return FeatureStrings.cameraPreview(l10n.language).pageTitle
        case .scratchpad: return FeatureStrings.scratchpad(l10n.language).pageTitle
        }
    }
}
