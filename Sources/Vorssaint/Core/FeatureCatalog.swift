// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// Every feature the Features hub can switch off entirely. The raw value is
/// the stable identity persisted inside the availability key, so cases can be
/// added but never renamed.
///
/// Availability is a layer ABOVE each feature's own enable key: an unavailable
/// feature disappears from Settings, the menu panel and the menu bar, and its
/// service tears down (and never instantiates on the next launch). Turning a
/// feature back on restores whatever enabled state it had, because the enable
/// keys are never touched.
enum AppFeature: String, CaseIterable {
    // Windows and Dock
    case switcher, dockPreview, dockClick, windowMaximizer, windowLayout, autoQuit
    // Mouse and keyboard
    case scrollInverter, smoothScroll, mouseNavigation, middleClick, keyboardDebounce, textSnippets
    // Clipboard and files
    case clipboardHistory, pastePlain, finderCutPaste, shelf, urlCleaner
    // Sound
    case mixer, soundOutputSwitcher, micMute, musicBlock
    // Energy and display
    case keepAwake, brightness, extraBrightness
    // Tools
    case quickLauncher, colorPicker, screenOCR, cleaningMode, mediaTools,
         cleaner, uninstaller, homebrew
    // System monitor, one entry per metric family (temperatures live with
    // their parent metric: CPU temp with CPU, battery temp with power).
    case monitorCPU, monitorGPU, monitorMemory, monitorNetwork, monitorDisk, monitorPower
}

/// Hub sections, in display order.
enum FeatureGroup: String, CaseIterable {
    case windowsDock, mouseKeyboard, clipboardFiles, sound, energyDisplay, tools, monitor
}

/// System permissions surfaced by the hub's transparency portal.
enum AppPermission: String, CaseIterable {
    case accessibility, screenRecording, fullDiskAccess, notifications,
         automationFinder, automationTerminal, audioCapture
}

extension AppFeature {
    var group: FeatureGroup {
        switch self {
        case .switcher, .dockPreview, .dockClick, .windowMaximizer, .windowLayout, .autoQuit:
            return .windowsDock
        case .scrollInverter, .smoothScroll, .mouseNavigation, .middleClick, .keyboardDebounce,
             .textSnippets:
            return .mouseKeyboard
        case .clipboardHistory, .pastePlain, .finderCutPaste, .shelf, .urlCleaner:
            return .clipboardFiles
        case .mixer, .soundOutputSwitcher, .micMute, .musicBlock:
            return .sound
        case .keepAwake, .brightness, .extraBrightness:
            return .energyDisplay
        case .quickLauncher, .colorPicker, .screenOCR, .cleaningMode, .mediaTools,
             .cleaner, .uninstaller, .homebrew:
            return .tools
        case .monitorCPU, .monitorGPU, .monitorMemory, .monitorNetwork, .monitorDisk, .monitorPower:
            return .monitor
        }
    }

    var symbolName: String {
        switch self {
        case .switcher: return "rectangle.on.rectangle"
        case .dockPreview: return "dock.rectangle"
        case .dockClick: return "dock.arrow.down.rectangle"
        case .windowMaximizer: return "arrow.up.left.and.arrow.down.right"
        case .windowLayout: return "rectangle.3.group"
        case .autoQuit: return "xmark.rectangle"
        case .scrollInverter: return "arrow.up.arrow.down"
        case .smoothScroll: return "cursorarrow.motionlines"
        case .mouseNavigation: return "arrow.left.arrow.right"
        case .middleClick: return "computermouse"
        case .keyboardDebounce: return "keyboard"
        case .textSnippets: return "text.append"
        case .clipboardHistory: return "doc.on.clipboard"
        case .pastePlain: return "doc.plaintext"
        case .finderCutPaste: return "scissors"
        case .shelf: return "tray.full"
        case .urlCleaner: return "link"
        case .mixer: return "slider.horizontal.3"
        case .soundOutputSwitcher: return "hifispeaker"
        case .micMute: return "mic.slash"
        case .musicBlock: return "music.note"
        case .keepAwake: return "moon.zzz.fill"
        case .brightness: return "sun.max"
        case .extraBrightness: return "sun.max.fill"
        case .quickLauncher: return "wand.and.rays"
        case .colorPicker: return "eyedropper"
        case .screenOCR: return "text.viewfinder"
        case .cleaningMode: return "bubbles.and.sparkles"
        case .mediaTools: return "photo.on.rectangle.angled"
        case .cleaner: return "sparkles"
        case .uninstaller: return "trash"
        case .homebrew: return "shippingbox"
        case .monitorCPU: return "cpu"
        case .monitorGPU: return "rectangle.connected.to.line.below"
        case .monitorMemory: return "memorychip"
        case .monitorNetwork: return "network"
        case .monitorDisk: return "internaldrive"
        case .monitorPower: return "bolt.fill"
        }
    }

    var availabilityKey: String { DefaultsKey.featureAvailable(rawValue) }

    /// Availability read straight from defaults (registered true, so updates
    /// change nothing for existing users).
    var isAvailable: Bool {
        UserDefaults.standard.bool(forKey: availabilityKey)
    }

    /// The feature's own enable keys; any one being true means the feature is
    /// engaged. Empty means the feature works on demand (a panel tile, a
    /// context-menu action), so being available already counts as engaged for
    /// the permissions portal.
    var enabledKeys: [String] {
        switch self {
        case .switcher: return [DefaultsKey.switcherEnabled]
        case .dockPreview: return [DefaultsKey.dockPreviewEnabled]
        case .dockClick: return [DefaultsKey.dockClickMinimize, DefaultsKey.dockClickCycleWindows]
        case .windowMaximizer: return [DefaultsKey.windowMaximizeEnabled]
        case .autoQuit: return [DefaultsKey.autoQuitEnabled]
        case .scrollInverter: return [DefaultsKey.scrollInverterEnabled]
        case .smoothScroll: return [DefaultsKey.smoothScrollEnabled]
        case .mouseNavigation: return [DefaultsKey.mouseNavigationEnabled]
        case .middleClick: return [DefaultsKey.middleClickEnabled]
        case .keyboardDebounce: return [DefaultsKey.keyboardDebounceEnabled]
        case .textSnippets: return [DefaultsKey.textSnippetsEnabled]
        case .clipboardHistory: return [DefaultsKey.clipboardHistoryEnabled]
        case .pastePlain: return [DefaultsKey.pastePlainEnabled]
        case .finderCutPaste: return [DefaultsKey.finderCutPasteEnabled]
        case .shelf: return [DefaultsKey.shelfEnabled]
        case .urlCleaner: return [DefaultsKey.urlCleanerEnabled]
        case .soundOutputSwitcher: return [DefaultsKey.soundOutputSwitcherEnabled]
        case .musicBlock: return [DefaultsKey.musicBlockEnabled]
        case .brightness: return [DefaultsKey.brightnessControlEnabled]
        case .extraBrightness: return [DefaultsKey.extraBrightnessEnabled]
        case .windowLayout, .mixer, .micMute, .keepAwake,
             .quickLauncher, .colorPicker, .screenOCR, .cleaningMode, .mediaTools,
             .cleaner, .uninstaller, .homebrew,
             .monitorCPU, .monitorGPU, .monitorMemory, .monitorNetwork, .monitorDisk, .monitorPower:
            return []
        }
    }

    /// Which permissions the feature can use at all. Whether it is using them
    /// RIGHT NOW is answered by `activeFeatures(using:)`, which also applies
    /// the dynamic rules (simple-mode switcher needs no screen recording, the
    /// monitor only notifies when an alert is on, and so on).
    var permissions: [AppPermission] {
        switch self {
        case .scrollInverter, .smoothScroll, .mouseNavigation, .middleClick, .keyboardDebounce,
             .textSnippets, .dockClick, .windowMaximizer, .windowLayout, .autoQuit,
             .cleaningMode, .pastePlain:
            return [.accessibility]
        case .finderCutPaste: return [.accessibility, .automationFinder]
        case .switcher: return [.accessibility, .screenRecording]
        case .dockPreview: return [.accessibility, .screenRecording]
        case .screenOCR: return [.screenRecording]
        case .keepAwake: return [.accessibility]
        case .brightness: return [.accessibility]
        case .cleaner: return [.fullDiskAccess, .notifications]
        case .uninstaller: return [.fullDiskAccess, .automationFinder]
        case .homebrew: return [.automationTerminal]
        case .mixer: return [.audioCapture]
        case .monitorCPU, .monitorMemory, .monitorDisk, .monitorPower: return [.notifications]
        case .clipboardHistory, .shelf, .urlCleaner, .soundOutputSwitcher, .musicBlock,
             .extraBrightness, .quickLauncher, .colorPicker, .micMute, .mediaTools,
             .monitorGPU, .monitorNetwork:
            return []
        }
    }

    static func features(in group: FeatureGroup) -> [AppFeature] {
        allCases.filter { $0.group == group }
    }

    /// Registered defaults: every feature ships available, so an update is a
    /// no-op for existing users. Generated from allCases so a new case can
    /// never be forgotten.
    static var availabilityDefaults: [String: Any] {
        Dictionary(uniqueKeysWithValues: allCases.map { ($0.availabilityKey, true) })
    }

    /// Features that are available, engaged and using `permission` right now.
    /// Readers are injectable so the logic stays testable without touching
    /// real UserDefaults.
    static func activeFeatures(using permission: AppPermission,
                               isAvailable: (AppFeature) -> Bool,
                               boolFor: (String) -> Bool,
                               stringFor: (String) -> String?) -> [AppFeature] {
        allCases.filter { feature in
            guard feature.permissions.contains(permission), isAvailable(feature) else { return false }
            let keys = feature.enabledKeys
            guard keys.isEmpty || keys.contains(where: boolFor) else { return false }
            switch (feature, permission) {
            case (.switcher, .screenRecording):
                return !boolFor(DefaultsKey.switcherSimpleMode)
            case (.keepAwake, .accessibility):
                return boolFor(DefaultsKey.keepAwakeMouseJiggleEnabled)
            case (.brightness, .accessibility):
                return boolFor(DefaultsKey.brightnessKeysEnabled)
            case (.monitorCPU, .notifications):
                return boolFor(DefaultsKey.monitorAlertCPU) || boolFor(DefaultsKey.monitorAlertCPUTemperature)
            case (.monitorMemory, .notifications):
                return boolFor(DefaultsKey.monitorAlertMemory)
            case (.monitorDisk, .notifications):
                return boolFor(DefaultsKey.monitorAlertDisk)
            case (.monitorPower, .notifications):
                return boolFor(DefaultsKey.monitorAlertBattery)
            case (.cleaner, .notifications):
                return (stringFor(DefaultsKey.cleanerScheduleFrequency) ?? "off") != "off"
                    && boolFor(DefaultsKey.cleanerScheduleNotify)
            default:
                return true
            }
        }
    }

    /// Monitor alert keys and the metric feature each one belongs to. An
    /// alert only counts while its metric is available in the hub.
    static let monitorAlertPairs: [(key: String, feature: AppFeature)] = [
        (DefaultsKey.monitorAlertCPU, .monitorCPU),
        (DefaultsKey.monitorAlertCPUTemperature, .monitorCPU),
        (DefaultsKey.monitorAlertMemory, .monitorMemory),
        (DefaultsKey.monitorAlertDisk, .monitorDisk),
        (DefaultsKey.monitorAlertBattery, .monitorPower),
    ]

    static func anyMonitorAlertEnabled(isAvailable: (AppFeature) -> Bool,
                                       boolFor: (String) -> Bool) -> Bool {
        monitorAlertPairs.contains { boolFor($0.key) && isAvailable($0.feature) }
    }

    /// Runtime convenience over the injectable core.
    static func activeFeatures(using permission: AppPermission,
                               defaults: UserDefaults = .standard) -> [AppFeature] {
        activeFeatures(using: permission,
                       isAvailable: { defaults.bool(forKey: $0.availabilityKey) },
                       boolFor: { defaults.bool(forKey: $0) },
                       stringFor: { defaults.string(forKey: $0) })
    }
}

extension AppPermission {
    var symbolName: String {
        switch self {
        case .accessibility: return "accessibility"
        case .screenRecording: return "rectangle.dashed.badge.record"
        case .fullDiskAccess: return "externaldrive.badge.person.crop"
        case .notifications: return "bell.badge"
        case .automationFinder, .automationTerminal: return "gearshape.2"
        case .audioCapture: return "waveform"
        }
    }
}
