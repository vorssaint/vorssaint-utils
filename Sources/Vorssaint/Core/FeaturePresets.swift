// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// One-click starting points for the Features hub. A preset is a shape, not a
/// prison: applying one installs and engages its features and uninstalls the
/// rest, but nothing is deleted — every feature keeps its settings and comes
/// back with one click, exactly like any hub install.
enum FeaturePreset: String, CaseIterable, Identifiable {
    case essential, windows, battery

    var id: String { rawValue }

    /// The features the preset keeps installed.
    var features: Set<AppFeature> {
        switch self {
        case .essential:
            return [.mixer, .keepAwake,
                    .monitorCPU, .monitorGPU, .monitorMemory,
                    .monitorNetwork, .monitorDisk, .monitorPower]
        case .windows:
            return [.switcher, .windowLayout, .dockPreview, .dockClick, .windowMaximizer]
        case .battery:
            // The lean monitor: battery, memory pressure and the processor,
            // with nothing that listens to input events.
            return [.monitorCPU, .monitorMemory, .monitorPower]
        }
    }

    /// Enable keys switched on along with the install, so the preset's
    /// features actually work instead of arriving as more toggles to find.
    /// Presets whose features are on-demand need none.
    var enableKeys: [String] {
        switch self {
        case .essential, .battery:
            return []
        case .windows:
            return [DefaultsKey.switcherEnabled,
                    DefaultsKey.dockPreviewEnabled,
                    DefaultsKey.dockClickMinimize,
                    DefaultsKey.windowMaximizeEnabled]
        }
    }

    var symbolName: String {
        switch self {
        case .essential: return "star.fill"
        case .windows: return "macwindow.on.rectangle"
        case .battery: return "battery.75percent"
        }
    }
}

/// The honest, curated cost label each feature earns in the hub: what the
/// feature keeps alive WHILE IT IS ON. Uninstalled features load nothing at
/// all, which is the hub's own promise. Static by design — pretending to
/// measure per-feature cost live would be theater.
enum FeatureEnergyProfile: String {
    /// Nothing at rest: on-demand tools, shortcut-driven actions and
    /// system-notification listeners.
    case idle
    /// A mouse event tap (scrolls, clicks or pointer moves).
    case mouse
    /// A keyboard event tap.
    case keyboard
    /// Both input taps.
    case inputs
    /// Samples or polls on an interval while active or visible.
    case periodic
}

extension AppFeature {
    var energyProfile: FeatureEnergyProfile {
        switch self {
        case .scrollInverter, .smoothScroll, .windowMaximizer, .middleClick,
             .mouseNavigation, .dockPreview, .dockClick, .shelf:
            return .mouse
        case .switcher, .keyboardDebounce, .finderCutPaste:
            return .keyboard
        case .textSnippets, .autoQuit:
            return .inputs
        case .clipboardHistory, .urlCleaner, .extraBrightness,
             .monitorCPU, .monitorGPU, .monitorMemory,
             .monitorNetwork, .monitorDisk, .monitorPower:
            return .periodic
        case .windowLayout, .pastePlain, .mixer, .soundOutputSwitcher, .micMute,
             .musicBlock, .keepAwake, .brightness, .quickLauncher, .colorPicker, .screenOCR,
             .cleaningMode, .mediaTools, .cleaner, .uninstaller, .homebrew:
            return .idle
        }
    }
}
