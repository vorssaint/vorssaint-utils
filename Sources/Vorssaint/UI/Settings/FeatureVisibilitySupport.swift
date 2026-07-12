// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// The Settings pages. Lives here (Foundation-only) so the visibility rules
/// below and the unit tests can reason about pages without pulling SwiftUI in.
enum SettingsPage: Hashable {
    case general, features, energy, monitor
    case mouse, switcher, keyDebounce, cutPaste, autoQuit, uninstaller, urlCleaner, homebrew, media, clipboard, windowLayout, shelf, quickTools, textSnippets
    case shortcuts, advanced, about, releaseNotes, support
}

/// Which hub features keep each Settings page alive. A page with several
/// features only disappears when ALL of them are switched off in the hub.
enum FeatureVisibilitySupport {
    static let monitorFeatures: [AppFeature] = [
        .monitorCPU, .monitorGPU, .monitorMemory, .monitorNetwork, .monitorDisk, .monitorPower,
    ]

    /// Features gating a page; empty means the page is part of the app and
    /// always shows (General, Shortcuts, About and friends).
    static func features(for page: SettingsPage) -> [AppFeature] {
        switch page {
        case .energy: return [.keepAwake, .brightness, .extraBrightness]
        case .monitor: return monitorFeatures
        case .mouse: return [.scrollInverter, .smoothScroll, .mouseNavigation, .middleClick]
        case .switcher: return [.switcher, .dockPreview, .dockClick]
        case .windowLayout: return [.windowLayout]
        case .autoQuit: return [.autoQuit]
        case .clipboard: return [.clipboardHistory, .pastePlain]
        case .cutPaste: return [.finderCutPaste]
        case .shelf: return [.shelf]
        case .media: return [.mediaTools]
        case .quickTools: return [.quickLauncher, .colorPicker, .screenOCR, .micMute]
        case .urlCleaner: return [.urlCleaner]
        case .homebrew: return [.homebrew]
        case .uninstaller: return [.uninstaller]
        case .keyDebounce: return [.keyboardDebounce]
        case .textSnippets: return [.textSnippets]
        case .general, .features, .shortcuts, .advanced, .about, .releaseNotes, .support:
            return []
        }
    }

    static func isPageVisible(_ page: SettingsPage,
                              isAvailable: (AppFeature) -> Bool) -> Bool {
        let gate = features(for: page)
        return gate.isEmpty || gate.contains(where: isAvailable)
    }
}
