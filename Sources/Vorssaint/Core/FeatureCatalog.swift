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
    case scrollInverter, focusFollowsMouse, smoothScroll, mouseNavigation, mouseButtonShortcuts, middleClick,
         keyboardDebounce, textSnippets, superKey
    // Clipboard and files
    case clipboardHistory, pastePlain, finderCutPaste, finderRename, shelf, urlCleaner,
         diskImageInstaller
    // Sound
    case mixer, soundOutputSwitcher, micMute, musicBlock
    // Energy and display
    case keepAwake, brightness, extraBrightness, bluetoothSleep
    // Tools
    case quickLauncher, quickToggles, colorPicker, screenOCR, cleaningMode, mediaTools,
         cleaner, uninstaller, homebrew, appUpdates, screenshot, cameraPreview, radialMenu, scratchpad,
         commandBar, screenRecorder, killProcess
    // System monitor, one entry per metric family (temperatures live with
    // their parent metric: CPU temp with CPU, battery temp with power).
    case monitorCPU, monitorGPU, monitorMemory, monitorNetwork, monitorDisk, monitorPower, fanControl
}

/// Hub sections, in display order.
enum FeatureGroup: String, CaseIterable {
    case windowsDock, mouseKeyboard, clipboardFiles, sound, energyDisplay, tools, monitor
}

/// System permissions surfaced by the hub's transparency portal.
enum AppPermission: String, CaseIterable {
    case accessibility, screenRecording, fullDiskAccess, filesAndFolders, notifications,
         automationFinder, automationTerminal, audioCapture, microphone, camera, appManagement
}

enum PermissionPollingSupport {
    static func interval(visibleSurfaceCount: Int,
                         accessibilityIsNeeded: Bool,
                         screenRecordingIsNeeded: Bool,
                         accessibilityIsGranted: Bool,
                         screenRecordingIsGranted: Bool) -> TimeInterval? {
        guard visibleSurfaceCount > 0 || accessibilityIsNeeded || screenRecordingIsNeeded else {
            return nil
        }
        if visibleSurfaceCount > 0
            || (accessibilityIsNeeded && !accessibilityIsGranted)
            || (screenRecordingIsNeeded && !screenRecordingIsGranted) {
            return 2.5
        }
        return 60
    }
}

extension AppFeature {
    /// Whether an engaged feature needs permission changes while it sits in
    /// the background. One-shot tools ask and refresh at the moment they run;
    /// polling for those just because their tile is installed wastes wakeups.
    func monitorsPermissionChanges(boolFor: (String) -> Bool) -> Bool {
        switch self {
        case .windowLayout:
            return boolFor(DefaultsKey.windowLayoutShortcutsEnabled)
                || boolFor(DefaultsKey.windowGestureEnabled)
                || boolFor(DefaultsKey.windowEdgeSnapEnabled)
        case .screenOCR, .cleaningMode, .screenshot, .commandBar, .screenRecorder:
            return false
        default:
            return true
        }
    }

    var monitorsPermissionChanges: Bool {
        monitorsPermissionChanges(boolFor: UserDefaults.standard.bool(forKey:))
    }

    var group: FeatureGroup {
        switch self {
        case .switcher, .dockPreview, .dockClick, .windowMaximizer, .windowLayout, .autoQuit:
            return .windowsDock
        case .scrollInverter, .focusFollowsMouse, .smoothScroll, .mouseNavigation, .mouseButtonShortcuts, .middleClick,
             .keyboardDebounce, .textSnippets, .superKey:
            return .mouseKeyboard
        case .clipboardHistory, .pastePlain, .finderCutPaste, .finderRename, .shelf, .urlCleaner,
             .diskImageInstaller:
            return .clipboardFiles
        case .mixer, .soundOutputSwitcher, .micMute, .musicBlock:
            return .sound
        case .keepAwake, .brightness, .extraBrightness, .bluetoothSleep:
            return .energyDisplay
        case .quickLauncher, .quickToggles, .colorPicker, .screenOCR, .cleaningMode, .mediaTools,
             .cleaner, .uninstaller, .homebrew, .appUpdates, .screenshot, .cameraPreview, .radialMenu,
             .scratchpad, .commandBar, .screenRecorder, .killProcess:
            return .tools
        case .monitorCPU, .monitorGPU, .monitorMemory, .monitorNetwork, .monitorDisk, .monitorPower,
             .fanControl:
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
        case .focusFollowsMouse: return "cursorarrow.and.square.on.square.dashed"
        case .smoothScroll: return "cursorarrow.motionlines"
        case .mouseNavigation: return "arrow.left.arrow.right"
        case .mouseButtonShortcuts: return "button.programmable"
        case .middleClick: return "computermouse"
        case .keyboardDebounce: return "keyboard"
        case .textSnippets: return "text.append"
        case .superKey:
            return SuperKeySource.sanitized(
                UserDefaults.standard.string(forKey: DefaultsKey.superKeySource)
            ).systemImage
        case .clipboardHistory: return "doc.on.clipboard"
        case .pastePlain: return "doc.plaintext"
        case .finderCutPaste: return "scissors"
        case .finderRename: return "pencil"
        case .shelf: return "tray.full"
        case .urlCleaner: return "link"
        case .diskImageInstaller: return "externaldrive.badge.plus"
        case .mixer: return "slider.horizontal.3"
        case .soundOutputSwitcher: return "hifispeaker"
        case .micMute: return "mic.slash"
        case .musicBlock: return "music.note"
        case .keepAwake: return "moon.zzz.fill"
        case .brightness: return "display.2"
        case .extraBrightness: return "sun.max.fill"
        case .bluetoothSleep: return "wave.3.right.circle"
        case .quickLauncher: return "wand.and.rays"
        case .quickToggles: return "togglepower"
        case .colorPicker: return "eyedropper"
        case .screenOCR: return "text.viewfinder"
        case .cleaningMode: return "bubbles.and.sparkles"
        case .mediaTools: return "photo.on.rectangle.angled"
        case .cleaner: return "sparkles"
        case .uninstaller: return "trash"
        case .homebrew: return "shippingbox"
        case .appUpdates: return "arrow.down.app"
        case .screenshot: return "camera.viewfinder"
        case .screenRecorder: return "record.circle"
        case .cameraPreview: return "web.camera"
        case .radialMenu: return "circle.grid.cross"
        case .scratchpad: return "note.text"
        case .commandBar: return "command"
        case .killProcess: return "xmark.octagon"
        case .monitorCPU: return "cpu"
        case .monitorGPU: return "rectangle.connected.to.line.below"
        case .monitorMemory: return "memorychip"
        case .monitorNetwork: return "network"
        case .monitorDisk: return "internaldrive"
        case .monitorPower: return "bolt.fill"
        case .fanControl: return "fanblades.fill"
        }
    }

    var availabilityKey: String { DefaultsKey.featureAvailable(rawValue) }

    var isBeta: Bool { self == .fanControl || self == .killProcess }

    /// Availability read straight from defaults. Existing features stay
    /// available on update; explicit beta opt-ins may start unavailable.
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
        case .dockClick: return [DefaultsKey.dockClickMinimize,
                                 DefaultsKey.dockClickHide,
                                 DefaultsKey.dockClickCycleWindows]
        case .windowMaximizer: return [DefaultsKey.windowMaximizeEnabled]
        case .autoQuit: return [DefaultsKey.autoQuitEnabled]
        case .scrollInverter: return [DefaultsKey.scrollInverterEnabled,
                                      DefaultsKey.scrollInverterHorizontalEnabled]
        case .focusFollowsMouse: return [DefaultsKey.focusFollowsMouseEnabled]
        case .smoothScroll: return [DefaultsKey.smoothScrollEnabled]
        case .mouseNavigation: return [DefaultsKey.mouseNavigationEnabled]
        case .mouseButtonShortcuts: return [DefaultsKey.mouseButtonShortcutsEnabled]
        case .middleClick: return [DefaultsKey.middleClickEnabled]
        case .keyboardDebounce: return [DefaultsKey.keyboardDebounceEnabled]
        case .textSnippets: return [DefaultsKey.textSnippetsEnabled, DefaultsKey.snippetLibraryEnabled]
        case .superKey: return [DefaultsKey.superKeyEnabled]
        case .radialMenu: return [DefaultsKey.radialMenuEnabled]
        case .clipboardHistory: return [DefaultsKey.clipboardHistoryEnabled]
        case .pastePlain: return [DefaultsKey.pastePlainEnabled]
        case .finderCutPaste: return [DefaultsKey.finderCutPasteEnabled,
                                      DefaultsKey.finderPasteImageAsFile]
        case .finderRename: return [DefaultsKey.finderRenameEnabled]
        case .shelf: return [DefaultsKey.shelfEnabled]
        case .urlCleaner: return [DefaultsKey.urlCleanerEnabled]
        case .soundOutputSwitcher: return [DefaultsKey.soundOutputSwitcherEnabled]
        case .musicBlock: return [DefaultsKey.musicBlockEnabled]
        case .brightness: return [DefaultsKey.brightnessControlEnabled]
        case .extraBrightness: return [DefaultsKey.extraBrightnessEnabled]
        case .bluetoothSleep: return [DefaultsKey.bluetoothSleepEnabled]
        case .windowLayout, .diskImageInstaller, .mixer, .micMute, .keepAwake,
             .quickLauncher, .quickToggles, .colorPicker, .screenOCR, .cleaningMode, .mediaTools,
             .cleaner, .uninstaller, .homebrew, .appUpdates, .screenshot, .cameraPreview, .scratchpad,
             .commandBar, .screenRecorder, .killProcess,
             .monitorCPU, .monitorGPU, .monitorMemory, .monitorNetwork, .monitorDisk, .monitorPower,
             .fanControl:
            return []
        }
    }

    /// Which permissions the feature can use at all. Whether it is using them
    /// RIGHT NOW is answered by `activeFeatures(using:)`, which also applies
    /// the dynamic rules (simple-mode switcher needs no screen recording, the
    /// monitor only notifies when an alert is on, and so on).
    var permissions: [AppPermission] {
        switch self {
        case .scrollInverter, .focusFollowsMouse, .smoothScroll, .mouseNavigation, .mouseButtonShortcuts, .middleClick,
             .keyboardDebounce, .textSnippets, .superKey, .dockClick, .windowMaximizer, .windowLayout,
             .autoQuit, .cleaningMode, .pastePlain, .radialMenu,
             // The bar reads other apps' menus and windows and types at the
             // caret, all of it through Accessibility.
             .commandBar:
            return [.accessibility]
        case .finderCutPaste: return [.accessibility, .automationFinder]
        case .finderRename: return [.accessibility]
        // Only emptying the Trash asks the Finder; every other quick toggle
        // (dark mode included) works without a permission.
        case .quickToggles: return [.automationFinder]
        case .switcher: return [.accessibility, .screenRecording]
        case .dockPreview: return [.accessibility, .screenRecording]
        case .screenOCR: return [.screenRecording]
        case .screenshot: return [.screenRecording]
        // The sound of the Mac rides the same grant the pixels do. Microphone
        // access stays contextual, and Accessibility only keeps typing timing.
        case .screenRecorder: return [.screenRecording, .accessibility, .microphone]
        case .cameraPreview: return [.camera]
        case .keepAwake: return [.accessibility]
        case .brightness: return [.accessibility]
        case .cleaner: return [.fullDiskAccess, .filesAndFolders, .notifications]
        case .uninstaller: return [.fullDiskAccess, .automationFinder]
        case .homebrew: return [.automationTerminal, .appManagement]
        case .appUpdates: return [.notifications, .appManagement]
        case .diskImageInstaller: return [.appManagement]
        case .mixer: return [.audioCapture, .accessibility]
        case .monitorCPU, .monitorMemory, .monitorDisk, .monitorPower: return [.notifications]
        case .clipboardHistory, .shelf, .urlCleaner,
             .soundOutputSwitcher, .musicBlock,
             .extraBrightness, .bluetoothSleep, .quickLauncher, .colorPicker, .micMute, .mediaTools,
             .scratchpad, .monitorGPU, .monitorNetwork, .fanControl, .killProcess:
            return []
        }
    }

    /// Broad grants worth explaining during first run. Permissions used only
    /// by an optional sub-feature stay contextual, at the moment that control
    /// is actually used.
    var onboardingPermissions: [AppPermission] {
        switch self {
        case .keepAwake, .brightness, .radialMenu, .quickToggles, .cleaner,
             .uninstaller, .homebrew, .appUpdates, .mixer, .cameraPreview,
             .micMute:
            return []
        default:
            return permissions.filter { $0 == .accessibility || $0 == .screenRecording }
        }
    }

    static func features(in group: FeatureGroup) -> [AppFeature] {
        allCases.filter { $0.group == group }
    }

    /// Registered defaults preserve existing features on update. New opt-in
    /// features and explicit betas ship uninstalled.
    static var availabilityDefaults: [String: Any] {
        Dictionary(uniqueKeysWithValues: allCases.map {
            ($0.availabilityKey,
             $0 != .focusFollowsMouse && $0 != .fanControl && $0 != .diskImageInstaller
                && $0 != .killProcess)
        })
    }

    /// Features that are available, engaged and using `permission` right now.
    /// Readers are injectable so the logic stays testable without touching
    /// real UserDefaults.
    static func activeFeatures(using permission: AppPermission,
                               isAvailable: (AppFeature) -> Bool,
                               boolFor: (String) -> Bool,
                               stringFor: (String) -> String?,
                               dataFor: (String) -> Data? = { _ in nil }) -> [AppFeature] {
        allCases.filter { feature in
            guard feature.permissions.contains(permission), isAvailable(feature) else { return false }
            let keys = feature.enabledKeys
            guard keys.isEmpty || keys.contains(where: boolFor) else { return false }
            switch (feature, permission) {
            case (.switcher, .screenRecording):
                return !boolFor(DefaultsKey.switcherSimpleMode)
            case (.radialMenu, .accessibility):
                return RadialMenuSupport.needsAccessibility(
                    RadialMenuSupport.decode(dataFor(DefaultsKey.radialMenuItems)))
                    || RadialMenuMouseTrigger.sanitized(
                        stringFor(DefaultsKey.radialMenuMouseButton)) != .off
            case (.keepAwake, .accessibility):
                return boolFor(DefaultsKey.keepAwakeMouseJiggleEnabled)
            case (.mixer, .accessibility):
                return boolFor(DefaultsKey.preciseVolumeRollerEnabled)
            case (.brightness, .accessibility):
                return boolFor(DefaultsKey.brightnessKeysEnabled)
                    || boolFor(DefaultsKey.brightnessOSDEnabled)
            case (.monitorCPU, .notifications):
                return boolFor(DefaultsKey.monitorAlertCPU) || boolFor(DefaultsKey.monitorAlertCPUTemperature)
            case (.monitorMemory, .notifications):
                return boolFor(DefaultsKey.monitorAlertMemory)
            case (.monitorDisk, .notifications):
                return boolFor(DefaultsKey.monitorAlertDisk)
            case (.monitorPower, .notifications):
                return boolFor(DefaultsKey.monitorAlertBattery)
                    || boolFor(DefaultsKey.monitorAlertBatteryTemperature)
            case (.appUpdates, .notifications):
                return AppUpdatesSupport.CheckFrequency
                    .sanitized(stringFor(DefaultsKey.appUpdatesCheckFrequency)) != .off
                    && boolFor(DefaultsKey.appUpdatesNotify)
            case (.cleaner, .filesAndFolders):
                return boolFor(DefaultsKey.whatsAppDownloadsEnabled)
            case (.cleaner, .notifications):
                let cleanerNotifies = (stringFor(DefaultsKey.cleanerScheduleFrequency) ?? "off") != "off"
                    && boolFor(DefaultsKey.cleanerScheduleNotify)
                let whatsAppNotifies = boolFor(DefaultsKey.whatsAppDownloadsEnabled)
                    && (boolFor(DefaultsKey.whatsAppDownloadsAutomaticEnabled)
                        || boolFor(DefaultsKey.whatsAppOrganizerEnabled))
                    && boolFor(DefaultsKey.whatsAppDownloadsNotify)
                return cleanerNotifies || whatsAppNotifies
            case (.screenRecorder, .microphone):
                return boolFor(DefaultsKey.recorderMicrophone)
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
        (DefaultsKey.monitorAlertBatteryTemperature, .monitorPower),
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
                       stringFor: { defaults.string(forKey: $0) },
                       dataFor: { defaults.data(forKey: $0) })
    }
}

extension AppPermission {
    var symbolName: String {
        switch self {
        case .accessibility: return "accessibility"
        case .screenRecording: return "rectangle.dashed.badge.record"
        case .fullDiskAccess: return "externaldrive.badge.person.crop"
        case .filesAndFolders: return "folder.badge.person.crop"
        case .notifications: return "bell.badge"
        case .automationFinder, .automationTerminal: return "gearshape.2"
        case .audioCapture: return "waveform"
        case .microphone: return "mic"
        case .camera: return "camera"
        case .appManagement: return "app.badge"
        }
    }
}
