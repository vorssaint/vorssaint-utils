// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import SwiftUI

// Split out of PanelLayout so the panel keyboard navigator, which is keyed by
// section, can compile into the standalone test harness without the panel view
// layer coming with it.

protocol PanelOrderItem: RawRepresentable, CaseIterable, Hashable where RawValue == String {}

/// The major, user-customizable sections of the menu panel. Raw values are the
/// stable identifiers persisted in the saved order and the collapsed set, so
/// renaming a case would orphan a user's stored layout — keep them stable.
enum PanelSectionID: String, CaseIterable, Identifiable, Hashable {
    case keepAwake, brightness, mixer, system, network, disk, power, fanControl, utilities, controls,
         toggles

    var id: String { rawValue }

    /// Localized display name, reused from the existing section titles.
    func title(_ s: Strings) -> String {
        switch self {
        case .keepAwake: return s.keepAwakeTitle
        case .brightness: return FeatureStrings.brightness(L10n.shared.language).pageTitle
        case .mixer: return s.mixerSection
        case .system: return s.systemSection
        case .network: return s.networkSection
        case .disk: return s.diskSection
        case .power: return s.powerSection
        case .fanControl: return FeatureStrings.fanControl(L10n.shared.language).title
        case .utilities: return s.utilitiesSection
        case .controls: return s.quickControlsSection
        case .toggles: return FeatureStrings.quickToggles(L10n.shared.language).pageTitle
        }
    }

    var symbolName: String {
        switch self {
        case .keepAwake: return "moon.zzz.fill"
        case .brightness: return "display.2"
        case .mixer: return "slider.horizontal.3"
        case .system: return "cpu"
        case .network: return "network"
        case .disk: return "internaldrive"
        case .power: return "bolt.fill"
        case .fanControl: return "fanblades.fill"
        case .utilities: return "wrench.and.screwdriver.fill"
        case .controls: return "switch.2"
        case .toggles: return "togglepower"
        }
    }

    /// The UserDefaults key that controls whether this section shows in the panel.
    /// The monitoring blocks reuse their existing `monitorShow*` keys; the rest
    /// get a dedicated `panelShow*` key so every section is hideable.
    var visibilityKey: String {
        switch self {
        case .keepAwake: return DefaultsKey.panelShowKeepAwake
        case .brightness: return DefaultsKey.panelShowBrightness
        case .mixer: return DefaultsKey.monitorShowMixer
        case .system: return DefaultsKey.monitorShowSystem
        case .network: return DefaultsKey.monitorShowNetwork
        case .disk: return DefaultsKey.monitorShowDisk
        case .power: return DefaultsKey.monitorShowPower
        case .fanControl: return DefaultsKey.panelShowFanControl
        case .utilities: return DefaultsKey.panelShowUtilities
        case .controls: return DefaultsKey.panelShowControls
        case .toggles: return DefaultsKey.panelShowToggles
        }
    }

    /// Installed sections show by default and remain individually hideable.
    var shownByDefault: Bool { true }

    /// Hub features that keep this section alive: with all of them off, the
    /// section leaves the panel, the section navigation and the layout
    /// editors, regardless of its visibility key (which is preserved for the
    /// feature's return).
    var featureGate: [AppFeature] {
        switch self {
        case .keepAwake: return [.keepAwake]
        case .brightness: return [.brightness]
        case .mixer: return [.mixer]
        case .system: return [.monitorCPU, .monitorGPU, .monitorMemory]
        case .network: return [.monitorNetwork]
        case .disk: return [.monitorDisk]
        case .power: return [.monitorPower]
        case .fanControl: return [.fanControl]
        case .utilities: return [.quickLauncher, .cleaner, .homebrew, .appUpdates, .mediaTools,
                                 .clipboardHistory,
                                 .windowLayout, .uninstaller, .urlCleaner, .cleaningMode, .screenOCR,
                                 .colorPicker, .screenshot, .screenRecorder,
                                 .cameraPreview, .scratchpad, .commandBar]
        case .controls: return [.scrollInverter, .mouseAcceleration, .mouseNavigation, .mouseButtonShortcuts, .switcher,
                                .finderCutPaste, .autoQuit,
                                .shelf, .windowMaximizer, .dockPreview, .keyboardDebounce, .dockClick,
                                .middleClick, .textSnippets, .superKey, .radialMenu, .mouseClickDebounce]
        case .toggles: return [.quickToggles, .micMute]
        }
    }

    var isAvailable: Bool { featureGate.contains(where: \.isAvailable) }
}
