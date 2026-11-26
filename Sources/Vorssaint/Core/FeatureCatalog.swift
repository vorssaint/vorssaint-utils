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
/// feature back on restores saved enable choices. A first install turns on its
/// primary control when no enable choice was saved before.
enum AppFeature: String, CaseIterable {
    // Windows and Dock
    case switcher, dockPreview, dockClick, windowMaximizer, windowLayout, autoQuit, spacesOrder
    // Mouse and keyboard
    case scrollInverter, scrollHorizontal, scrollZoom, focusFollowsMouse, smoothScroll, linearScroll, scrollSpeed, mouseAcceleration, mouseNavigation, mouseButtonShortcuts, middleClick,
         mouseClickDebounce, keyboardDebounce, textSnippets, superKey, quitWindowProtection
    // Clipboard and files
    case clipboardHistory, pastePlain, finderCutPaste, finderRename, shelf, urlCleaner,
         diskImageInstaller
    // Sound
    case mixer, soundOutputSwitcher, audioPriority, micMute, musicBlock
    // Energy and display
    case keepAwake, brightness, extraBrightness, bluetoothSleep
    // Tools
    case quickLauncher, quickToggles, quitApps, colorPicker, screenOCR, cleaningMode, mediaTools,
         cleaner, uninstaller, homebrew, appUpdates, screenshot, cameraPreview, radialMenu, scratchpad,
         commandBar, screenRecorder, wallpaper, killProcess, portManager
    // Dynamic Island, then its extensions
    case notch, notchCalendar, notchNotifications, notchGestures, notchTimer, notchAccessories, notchLyrics,
         notchQueue, notchLiveEqualizer, notchDownloads, notchAgents, notchWatch, notchMascot
    // System monitor, one entry per metric family (temperatures live with
    // their parent metric: CPU temp with CPU, battery temp with power).
    case monitorCPU, monitorGPU, monitorMemory, monitorNetwork, monitorDisk, monitorPower, connectedDevices, fanControl
}

/// Hub sections, in display order.
enum FeatureGroup: String, CaseIterable {
    case windowsDock, mouseKeyboard, clipboardFiles, sound, energyDisplay, tools, dynamicIsland, monitor
}

/// Everything the hub knows about a feature that is description rather than
/// behaviour: its group, its glyph, whether an update installs it, and which
/// monitor alerts belong to it. One record per `AppFeature` case lives in
/// `AppFeature.metadataTable`, so adding a feature means adding one row there
/// instead of touching every table in this file.
struct AppFeatureMetadata {
    let group: FeatureGroup
    let symbol: String
    /// A glyph that follows a setting instead of a fixed name, such as the
    /// Super key's chosen symbol.
    var symbolFromSetting: (() -> String)?
    /// An update leaves opt-in features uninstalled and lets the Features hub
    /// install them. New features are opt-in on purpose.
    var optIn = false
    /// Shown with a beta warning and kept out of presets.
    var beta = false
    /// Monitor alert keys whose reading belongs to this metric feature. Only a
    /// monitor metric carries any.
    var monitorAlertKeys: [String] = []
}

/// System permissions surfaced by the hub's transparency portal.
enum AppPermission: String, CaseIterable {
    case accessibility, screenRecording, fullDiskAccess, filesAndFolders, notifications,
         automationFinder, automationPlayback, audioCapture, microphone, camera, appManagement, calendar
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
    func monitorsPermissionChanges(edgeSnapDisabledZones: String? = nil,
                                   boolFor: (String) -> Bool) -> Bool {
        switch self {
        case .windowLayout:
            return boolFor(DefaultsKey.windowLayoutShortcutsEnabled)
                || boolFor(DefaultsKey.windowGestureEnabled)
                || (boolFor(DefaultsKey.windowEdgeSnapEnabled)
                    && !WindowEdgeSnapZone.enabledZones(
                        from: edgeSnapDisabledZones
                    ).isEmpty)
        // Watch asks when an area is chosen and checks on every reading. The
        // companion uses no permission at all.
        case .screenOCR, .cleaningMode, .screenshot, .commandBar, .screenRecorder, .wallpaper, .notchWatch,
             .notchMascot:
            return false
        default:
            return true
        }
    }

    var monitorsPermissionChanges: Bool {
        monitorsPermissionChanges(
            edgeSnapDisabledZones: UserDefaults.standard.string(
                forKey: DefaultsKey.windowEdgeSnapDisabledZones
            ),
            boolFor: UserDefaults.standard.bool(forKey:)
        )
    }

    /// The description table; behaviour tables (`enabledKeys`, `permissions`,
    /// `activeFeatures`) stay separate on purpose.
    var metadata: AppFeatureMetadata {
        guard let metadata = Self.metadataTable[self] else {
            preconditionFailure("missing metadata for feature \(rawValue)")
        }
        return metadata
    }

    /// The one row every description of a feature comes from: group, glyph,
    /// install default, beta flag and monitor alerts. Adding a case means
    /// adding a row here; no other table in this file has to learn about it.
    private static let metadataTable: [AppFeature: AppFeatureMetadata] = [
        // Windows and Dock
        .switcher: AppFeatureMetadata(group: .windowsDock, symbol: "rectangle.on.rectangle"),
        .dockPreview: AppFeatureMetadata(group: .windowsDock, symbol: "dock.rectangle"),
        .dockClick: AppFeatureMetadata(group: .windowsDock, symbol: "dock.arrow.down.rectangle"),
        .windowMaximizer: AppFeatureMetadata(group: .windowsDock, symbol: "arrow.up.left.and.arrow.down.right"),
        .windowLayout: AppFeatureMetadata(group: .windowsDock, symbol: "rectangle.3.group"),
        .autoQuit: AppFeatureMetadata(group: .windowsDock, symbol: "xmark.rectangle"),
        .spacesOrder: AppFeatureMetadata(group: .windowsDock, symbol: "rectangle.split.3x1", optIn: true),
        // Mouse and keyboard
        .scrollInverter: AppFeatureMetadata(group: .mouseKeyboard, symbol: "arrow.up.arrow.down"),
        .scrollHorizontal: AppFeatureMetadata(group: .mouseKeyboard, symbol: "arrow.triangle.swap", optIn: true),
        .scrollZoom: AppFeatureMetadata(group: .mouseKeyboard, symbol: "plus.magnifyingglass", optIn: true),
        .focusFollowsMouse: AppFeatureMetadata(group: .mouseKeyboard, symbol: "cursorarrow.and.square.on.square.dashed", optIn: true),
        .smoothScroll: AppFeatureMetadata(group: .mouseKeyboard, symbol: "cursorarrow.motionlines"),
        .linearScroll: AppFeatureMetadata(group: .mouseKeyboard, symbol: "arrow.up.and.down.text.horizontal", optIn: true),
        .scrollSpeed: AppFeatureMetadata(group: .mouseKeyboard, symbol: "gauge.with.dots.needle.67percent", optIn: true),
        .mouseAcceleration: AppFeatureMetadata(group: .mouseKeyboard, symbol: "cursorarrow.rays"),
        .mouseNavigation: AppFeatureMetadata(group: .mouseKeyboard, symbol: "arrow.left.arrow.right"),
        .mouseButtonShortcuts: AppFeatureMetadata(group: .mouseKeyboard, symbol: "button.programmable"),
        .middleClick: AppFeatureMetadata(group: .mouseKeyboard, symbol: "hand.tap"),
        .keyboardDebounce: AppFeatureMetadata(group: .mouseKeyboard, symbol: "keyboard"),
        .textSnippets: AppFeatureMetadata(group: .mouseKeyboard, symbol: "text.append"),
        .superKey: AppFeatureMetadata(
            group: .mouseKeyboard, symbol: "",
            symbolFromSetting: {
                SuperKeySource.sanitized(
                    UserDefaults.standard.string(forKey: DefaultsKey.superKeySource)
                ).systemImage
            }),
        .quitWindowProtection: AppFeatureMetadata(group: .mouseKeyboard, symbol: "shield.lefthalf.filled"),
        .mouseClickDebounce: AppFeatureMetadata(group: .mouseKeyboard, symbol: "cursorarrow.click"),
        // Clipboard and files
        .clipboardHistory: AppFeatureMetadata(group: .clipboardFiles, symbol: "doc.on.clipboard"),
        .pastePlain: AppFeatureMetadata(group: .clipboardFiles, symbol: "doc.plaintext"),
        .finderCutPaste: AppFeatureMetadata(group: .clipboardFiles, symbol: "scissors"),
        .finderRename: AppFeatureMetadata(group: .clipboardFiles, symbol: "pencil"),
        .shelf: AppFeatureMetadata(group: .clipboardFiles, symbol: "tray.full"),
        .urlCleaner: AppFeatureMetadata(group: .clipboardFiles, symbol: "link"),
        .diskImageInstaller: AppFeatureMetadata(group: .clipboardFiles, symbol: "externaldrive.badge.plus", optIn: true),
        // Sound
        .mixer: AppFeatureMetadata(group: .sound, symbol: "speaker.wave.2"),
        .soundOutputSwitcher: AppFeatureMetadata(group: .sound, symbol: "hifispeaker"),
        .audioPriority: AppFeatureMetadata(group: .sound, symbol: "list.number", optIn: true),
        .micMute: AppFeatureMetadata(group: .sound, symbol: "mic.slash"),
        .musicBlock: AppFeatureMetadata(group: .sound, symbol: "music.note"),
        // Energy and display
        .keepAwake: AppFeatureMetadata(group: .energyDisplay, symbol: "moon.zzz.fill"),
        .brightness: AppFeatureMetadata(group: .energyDisplay, symbol: "display.2"),
        .extraBrightness: AppFeatureMetadata(group: .energyDisplay, symbol: "sun.max.fill"),
        .bluetoothSleep: AppFeatureMetadata(group: .energyDisplay, symbol: "wave.3.right.circle"),
        // Tools
        .quickLauncher: AppFeatureMetadata(group: .tools, symbol: "wand.and.rays"),
        .quickToggles: AppFeatureMetadata(group: .tools, symbol: "togglepower"),
        .quitApps: AppFeatureMetadata(group: .tools, symbol: "xmark.app", optIn: true),
        .colorPicker: AppFeatureMetadata(group: .tools, symbol: "eyedropper"),
        .screenOCR: AppFeatureMetadata(group: .tools, symbol: "text.viewfinder"),
        .cleaningMode: AppFeatureMetadata(group: .tools, symbol: "bubbles.and.sparkles"),
        .mediaTools: AppFeatureMetadata(group: .tools, symbol: "photo.on.rectangle.angled"),
        .cleaner: AppFeatureMetadata(group: .tools, symbol: "sparkles"),
        .uninstaller: AppFeatureMetadata(group: .tools, symbol: "trash"),
        .homebrew: AppFeatureMetadata(group: .tools, symbol: "shippingbox"),
        .appUpdates: AppFeatureMetadata(group: .tools, symbol: "arrow.down.app"),
        .screenshot: AppFeatureMetadata(group: .tools, symbol: "camera.viewfinder"),
        .cameraPreview: AppFeatureMetadata(group: .tools, symbol: "web.camera"),
        .radialMenu: AppFeatureMetadata(group: .tools, symbol: "circle.grid.cross"),
        .scratchpad: AppFeatureMetadata(group: .tools, symbol: "note.text"),
        .commandBar: AppFeatureMetadata(group: .tools, symbol: "command"),
        .screenRecorder: AppFeatureMetadata(group: .tools, symbol: "record.circle"),
        .wallpaper: AppFeatureMetadata(group: .tools, symbol: "photo.on.rectangle", optIn: true),
        .killProcess: AppFeatureMetadata(group: .tools, symbol: "xmark.octagon", optIn: true, beta: true),
        .portManager: AppFeatureMetadata(group: .tools, symbol: "network", optIn: true),
        // Dynamic Island, then its extensions
        .notch: AppFeatureMetadata(group: .dynamicIsland, symbol: "macbook"),
        .notchCalendar: AppFeatureMetadata(group: .dynamicIsland, symbol: "calendar"),
        .notchNotifications: AppFeatureMetadata(group: .dynamicIsland, symbol: "bell"),
        .notchGestures: AppFeatureMetadata(group: .dynamicIsland, symbol: "hand.draw"),
        .notchTimer: AppFeatureMetadata(group: .dynamicIsland, symbol: "timer"),
        .notchAccessories: AppFeatureMetadata(group: .dynamicIsland, symbol: "battery.25percent"),
        .notchLyrics: AppFeatureMetadata(group: .dynamicIsland, symbol: "quote.bubble"),
        .notchQueue: AppFeatureMetadata(group: .dynamicIsland, symbol: "list.bullet"),
        .notchLiveEqualizer: AppFeatureMetadata(group: .dynamicIsland, symbol: "waveform"),
        .notchDownloads: AppFeatureMetadata(group: .dynamicIsland, symbol: "arrow.down.circle"),
        .notchAgents: AppFeatureMetadata(group: .dynamicIsland, symbol: "sparkles"),
        .notchWatch: AppFeatureMetadata(group: .dynamicIsland, symbol: "eye"),
        .notchMascot: AppFeatureMetadata(group: .dynamicIsland, symbol: "face.smiling", optIn: true),
        // System monitor
        .monitorCPU: AppFeatureMetadata(group: .monitor, symbol: "cpu", monitorAlertKeys: [
            DefaultsKey.monitorAlertCPU, DefaultsKey.monitorAlertCPUTemperature,
        ]),
        .monitorGPU: AppFeatureMetadata(group: .monitor, symbol: "rectangle.connected.to.line.below"),
        .monitorMemory: AppFeatureMetadata(group: .monitor, symbol: "memorychip", monitorAlertKeys: [
            DefaultsKey.monitorAlertMemory,
        ]),
        .monitorNetwork: AppFeatureMetadata(group: .monitor, symbol: "network"),
        .monitorDisk: AppFeatureMetadata(group: .monitor, symbol: "internaldrive", monitorAlertKeys: [
            DefaultsKey.monitorAlertDisk,
        ]),
        .monitorPower: AppFeatureMetadata(group: .monitor, symbol: "bolt.fill", monitorAlertKeys: [
            DefaultsKey.monitorAlertBatteryTemperature, DefaultsKey.monitorAlertBattery,
        ]),
        .connectedDevices: AppFeatureMetadata(group: .monitor, symbol: "cable.connector"),
        .fanControl: AppFeatureMetadata(group: .monitor, symbol: "fanblades.fill", optIn: true, beta: true),
    ]

    var group: FeatureGroup { metadata.group }

    var symbolName: String { metadata.symbolFromSetting?() ?? metadata.symbol }

    var availabilityKey: String { DefaultsKey.featureAvailable(rawValue) }

    var isBeta: Bool { metadata.beta }

    /// Availability read straight from defaults. Existing features stay
    /// available on update; explicit beta opt-ins may start unavailable.
    var isAvailable: Bool {
        isAvailable(in: .standard)
    }

    func isAvailable(in defaults: UserDefaults) -> Bool {
        defaults.bool(forKey: availabilityKey)
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
        case .spacesOrder: return [DefaultsKey.spacesOrderEnabled]
        case .scrollInverter: return [DefaultsKey.scrollInverterEnabled,
                                      DefaultsKey.scrollInverterHorizontalEnabled]
        case .scrollHorizontal: return [DefaultsKey.scrollHorizontalEnabled]
        case .scrollZoom: return [DefaultsKey.pinchZoomEnabled]
        case .focusFollowsMouse: return [DefaultsKey.focusFollowsMouseEnabled]
        case .smoothScroll: return [DefaultsKey.smoothScrollEnabled]
        case .linearScroll: return [DefaultsKey.linearScrollEnabled]
        case .scrollSpeed: return [DefaultsKey.scrollSpeedEnabled]
        case .mouseAcceleration: return [DefaultsKey.mouseAccelerationDisabled]
        case .mouseNavigation: return [DefaultsKey.mouseNavigationEnabled]
        case .mouseButtonShortcuts: return [DefaultsKey.mouseButtonShortcutsEnabled,
                                            DefaultsKey.mouseSpacesGestureEnabled]
        case .middleClick: return [DefaultsKey.middleClickEnabled]
        case .keyboardDebounce: return [DefaultsKey.keyboardDebounceEnabled]
        case .quitWindowProtection:
            return [DefaultsKey.quitProtectionQuitEnabled, DefaultsKey.quitProtectionCloseEnabled]
        case .textSnippets: return [DefaultsKey.textSnippetsEnabled, DefaultsKey.snippetLibraryEnabled]
        case .superKey: return [DefaultsKey.superKeyEnabled]
        case .mouseClickDebounce: return [DefaultsKey.mouseClickDebounceEnabled]
        case .notchGestures: return [DefaultsKey.notchGesturesEnabled]
        case .notchTimer: return [DefaultsKey.notchTimerEnabled]
        case .notchAccessories: return [DefaultsKey.notchAccessoriesEnabled]
        case .notchLyrics: return [DefaultsKey.notchLyricsEnabled]
        case .notchQueue: return [DefaultsKey.notchQueueEnabled]
        case .notchLiveEqualizer: return [DefaultsKey.notchLiveEqualizer]
        case .notchDownloads: return [DefaultsKey.notchDownloadsEnabled]
        case .notchNotifications: return [DefaultsKey.notchNotificationsEnabled]
        case .notchCalendar: return [DefaultsKey.notchCalendarEnabled]
        case .notchAgents: return [DefaultsKey.notchAgentsEnabled]
        case .notchWatch: return [DefaultsKey.notchWatchEnabled]
        case .notchMascot: return [DefaultsKey.notchMascotEnabled]
        case .notch: return [DefaultsKey.notchEnabled]
        case .radialMenu: return [DefaultsKey.radialMenuEnabled]
        case .clipboardHistory: return [DefaultsKey.clipboardHistoryEnabled]
        case .pastePlain: return [DefaultsKey.pastePlainEnabled]
        case .finderCutPaste: return [DefaultsKey.finderCutPasteEnabled,
                                      DefaultsKey.finderPasteImageAsFile]
        case .finderRename: return [DefaultsKey.finderRenameEnabled]
        case .shelf: return [DefaultsKey.shelfEnabled]
        case .urlCleaner: return [DefaultsKey.urlCleanerEnabled]
        case .soundOutputSwitcher: return [DefaultsKey.soundOutputSwitcherEnabled]
        case .audioPriority: return [DefaultsKey.audioPriorityOutputEnabled,
                                     DefaultsKey.audioPriorityInputEnabled]
        case .musicBlock: return [DefaultsKey.musicBlockEnabled]
        case .brightness: return [DefaultsKey.brightnessControlEnabled]
        case .extraBrightness: return [DefaultsKey.extraBrightnessEnabled]
        case .bluetoothSleep: return [DefaultsKey.bluetoothSleepEnabled]
        case .windowLayout, .diskImageInstaller, .mixer, .micMute, .keepAwake,
             .quickLauncher, .quickToggles, .quitApps, .colorPicker, .screenOCR, .cleaningMode, .mediaTools,
             .cleaner, .uninstaller, .homebrew, .appUpdates, .screenshot, .cameraPreview, .scratchpad,
             .commandBar, .screenRecorder, .wallpaper, .killProcess, .portManager,
             .monitorCPU, .monitorGPU, .monitorMemory, .monitorNetwork, .monitorDisk, .monitorPower,
             .connectedDevices, .fanControl:
            return []
        }
    }

    /// Turn on the feature's main behavior at install time. Features with
    /// several independent controls start with one useful behavior, except
    /// audio priority, whose output and input controls work together. The
    /// live equalizer stays off: it asks for system audio recording on the
    /// first song, so only the user's own switch turns it on.
    private var initialEnableKeys: [String] {
        switch self {
        case .windowLayout: return [DefaultsKey.windowLayoutShortcutsEnabled]
        case .audioPriority: return enabledKeys
        case .notchLiveEqualizer: return []
        default: return enabledKeys.first.map { [$0] } ?? []
        }
    }

    /// Registered defaults are visible through `object(forKey:)`, so only the
    /// persistent domain can tell a fresh install from a saved off choice.
    func enableOnFirstInstall(in defaults: UserDefaults, savedValues: [String: Any]) {
        let choices = self == .windowLayout
            ? [DefaultsKey.windowLayoutShortcutsEnabled, DefaultsKey.windowDirectionalEnabled,
               DefaultsKey.pointerDisplayEnabled, DefaultsKey.windowEdgeSnapEnabled,
               DefaultsKey.windowGestureEnabled]
            : enabledKeys
        guard !choices.contains(where: { savedValues[$0] != nil }) else { return }
        for key in initialEnableKeys {
            defaults.set(true, forKey: key)
        }
    }

    /// Which permissions the feature can use at all. Whether it is using them
    /// RIGHT NOW is answered by `activeFeatures(using:)`, which also applies
    /// the dynamic rules (simple-mode switcher needs no screen recording, the
    /// monitor only notifies when an alert is on, and so on).
    var permissions: [AppPermission] {
        switch self {
        case .notchGestures: return []
        case .notchTimer, .notchAccessories: return []
        case .notchLyrics, .notchQueue: return []
        // Session logs and the saved limits sit in the home folder, outside
        // every protected location, and no sign-in or keychain item is used.
        case .notchAgents: return []
        // It only draws, and hears of what happens from the island itself.
        case .notchMascot: return []
        // The bars read the player's own audio output, which macOS gates
        // behind the same permission the mixer and the recorder ask for.
        case .notchLiveEqualizer: return [.audioCapture]
        case .notchDownloads: return [.filesAndFolders]
        // The chosen area is read with the screen capture other tools use,
        // and the alert becomes a notification where the island is hidden.
        case .notchWatch: return [.screenRecording, .notifications]
        case .notchNotifications: return [.accessibility]
        case .notchCalendar: return [.calendar]
        case .notch: return [.accessibility, .automationPlayback]
        case .mouseAcceleration, .spacesOrder:
            return []
        case .scrollInverter, .scrollHorizontal, .scrollZoom, .focusFollowsMouse, .smoothScroll, .linearScroll, .scrollSpeed, .mouseNavigation, .mouseButtonShortcuts, .middleClick,
             .keyboardDebounce, .textSnippets, .superKey, .mouseClickDebounce,
             .dockClick, .windowMaximizer, .windowLayout,
             .autoQuit, .quitWindowProtection, .cleaningMode, .pastePlain, .radialMenu,
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
        // The sound of the Mac is read through an audio grant of its own.
        // Microphone access stays contextual, and Accessibility only keeps
        // typing timing.
        case .screenRecorder: return [.screenRecording, .accessibility, .audioCapture, .microphone]
        case .cameraPreview: return [.camera]
        case .keepAwake: return [.accessibility]
        case .brightness: return [.accessibility]
        case .cleaner: return [.fullDiskAccess, .filesAndFolders, .notifications]
        case .uninstaller: return [.fullDiskAccess, .automationFinder]
        case .homebrew: return [.appManagement]
        case .appUpdates: return [.notifications, .appManagement]
        case .diskImageInstaller: return [.appManagement]
        case .mixer: return [.audioCapture, .accessibility]
        case .musicBlock: return [.accessibility]
        case .monitorCPU, .monitorMemory, .monitorDisk, .monitorPower: return [.notifications]
        case .clipboardHistory, .shelf, .urlCleaner,
             .soundOutputSwitcher, .audioPriority,
             .extraBrightness, .bluetoothSleep, .quickLauncher, .colorPicker, .micMute, .mediaTools,
             .scratchpad, .wallpaper, .monitorGPU, .monitorNetwork, .connectedDevices, .fanControl, .killProcess,
             .portManager,
             // Each app gets the ordinary quit request it would from its own menu.
             .quitApps:
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
             .micMute, .musicBlock, .notchWatch:
            return []
        default:
            return permissions.filter { $0 == .accessibility || $0 == .screenRecording }
        }
    }

    static func features(in group: FeatureGroup) -> [AppFeature] {
        allCases.filter { $0.group == group }
    }

    /// The Dynamic Island's extensions: everything else in its group. They
    /// do nothing without the island, so uninstalling it offers to take them
    /// along.
    static var dynamicIslandExtensions: [AppFeature] {
        features(in: .dynamicIsland).filter { $0 != .notch }
    }

    /// Agents reads local session histories, and the companion changes the
    /// resting island. Both are separate choices when installing the island.
    static var dynamicIslandInitialExtensions: [AppFeature] {
        dynamicIslandExtensions.filter { $0 != .notchMascot && $0 != .notchAgents }
    }

    var initialInstallGroup: [AppFeature] {
        self == .notch ? [self] + Self.dynamicIslandInitialExtensions : [self]
    }

    /// Switches the Features page may offer to uninstall once they turn out
    /// never used. Each one does nothing until its own switch is on, and no
    /// other feature leans on it while it is off. Features that lend a part
    /// of themselves elsewhere stay out even when off: the Dynamic Island,
    /// the shelf behind the island's file tray, the radial menu, and the
    /// switcher and text snippets that feed the Command Bar.
    static let offeredWhenNeverSwitchedOn: [AppFeature] = [
        .dockPreview, .dockClick, .windowMaximizer, .autoQuit,
        .scrollInverter, .linearScroll, .focusFollowsMouse, .mouseAcceleration, .mouseNavigation,
        .mouseButtonShortcuts, .middleClick, .keyboardDebounce, .mouseClickDebounce, .superKey,
        .finderCutPaste,
    ]

    /// Installed features from that list whose switches are off and were never
    /// saved on this Mac: installed, but not once turned on. A switch turned
    /// on and back off is saved, so a feature someone used keeps its place.
    static func neverSwitchedOn(isAvailable: (AppFeature) -> Bool,
                                boolFor: (String) -> Bool,
                                isSaved: (String) -> Bool) -> [AppFeature] {
        offeredWhenNeverSwitchedOn.filter { feature in
            isAvailable(feature)
                && !feature.enabledKeys.isEmpty
                && !feature.enabledKeys.contains(where: boolFor)
                && !feature.enabledKeys.contains { isSaved($0) && !savedOnEveryMac.contains($0) }
        }
    }

    /// Switches a launch migration saves on every Mac, the horizontal scroll
    /// direction copying the vertical one, so a saved value there says
    /// nothing about use. Only one that is on counts.
    private static let savedOnEveryMac: Set<String> = [DefaultsKey.scrollInverterHorizontalEnabled]

    /// Whether a Mac that never chose this feature has it installed. Most
    /// people updating never saved an availability, so this list IS their
    /// install: moving a feature out of it uninstalls it for all of them,
    /// which is why a test pins it. `optIn` has no default on purpose, so
    /// every new feature is placed here by decision. New features belong on
    /// the opt-in side: an update should never grow the panel and Settings on
    /// its own, and the Features page and release notes are where they get
    /// installed. A feature split out of an existing one needs a migration
    /// that copies its parent's availability instead.
    var installedByDefault: Bool { !metadata.optIn }

    /// Registered defaults keep every feature an update already had and leave
    /// opt-in features and explicit betas uninstalled.
    static var availabilityDefaults: [String: Any] {
        Dictionary(uniqueKeysWithValues: allCases.map { ($0.availabilityKey, $0.installedByDefault) })
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
            case (.notch, .automationPlayback):
                return !(stringFor(DefaultsKey.notchHiddenModules) ?? "").split(separator: ",").contains("music")
            case (.switcher, .screenRecording):
                return !boolFor(DefaultsKey.switcherSimpleMode)
            case (.notchWatch, .screenRecording):
                return isAvailable(.notch) && boolFor(DefaultsKey.notchEnabled)
                    && !(stringFor(DefaultsKey.notchHiddenModules) ?? "").split(separator: ",").contains("watch")
            case (.notchNotifications, .accessibility):
                return isAvailable(.notch) && boolFor(DefaultsKey.notchEnabled)
                    && !(stringFor(DefaultsKey.notchHiddenModules) ?? "").split(separator: ",").contains("notifications")
            case (.notchDownloads, .filesAndFolders):
                return isAvailable(.notch) && boolFor(DefaultsKey.notchEnabled)
                    && dataFor(DefaultsKey.notchDownloadsFolderBookmark) != nil
                    && !(stringFor(DefaultsKey.notchHiddenModules) ?? "").split(separator: ",").contains("downloads")
            case (.notchCalendar, .calendar):
                return isAvailable(.notch) && boolFor(DefaultsKey.notchEnabled)
                    && !(stringFor(DefaultsKey.notchHiddenModules) ?? "").split(separator: ",").contains("calendar")
            case (.notch, .accessibility):
                return (boolFor(DefaultsKey.notchVolume) && isAvailable(.mixer))
                    || (boolFor(DefaultsKey.notchKeyboardLight) && isAvailable(.brightness))
                    || (boolFor(DefaultsKey.notchBrightness) && isAvailable(.brightness)
                        && boolFor(DefaultsKey.brightnessControlEnabled))
                    || (boolFor(DefaultsKey.notchClipboardWindow) && isAvailable(.clipboardHistory))
            case (.radialMenu, .accessibility):
                if let profiles = dataFor(DefaultsKey.radialMenuProfiles) {
                    return RadialMenuSupport.needsAccessibility(RadialMenuSupport.decodeProfiles(profiles))
                }
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
                    || (boolFor(DefaultsKey.displayVolumeEnabled) && boolFor(DefaultsKey.displayVolumeKeysEnabled))
                    || BrightnessSupport.KeyStep.sanitized(stringFor(DefaultsKey.brightnessKeyStep)) != .standard
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
            case (.notchLiveEqualizer, .audioCapture):
                return isAvailable(.notch) && boolFor(DefaultsKey.notchEnabled)
                    && !(stringFor(DefaultsKey.notchHiddenModules) ?? "").split(separator: ",").contains("music")
            case (.screenRecorder, .audioCapture):
                return boolFor(DefaultsKey.recorderSystemAudio)
            case (.screenRecorder, .microphone):
                return boolFor(DefaultsKey.recorderMicrophone)
            default:
                return true
            }
        }
    }

    /// Monitor alert keys and the metric feature each one belongs to. An
    /// alert only counts while its metric is available in the hub.
    static let monitorAlertPairs: [(key: String, feature: AppFeature)] =
        allCases.flatMap { feature in
            feature.metadata.monitorAlertKeys.map { (key: $0, feature: feature) }
        }

    static func anyMonitorAlertEnabled(includingDisk: Bool = true,
                                       isAvailable: (AppFeature) -> Bool,
                                       boolFor: (String) -> Bool) -> Bool {
        monitorAlertPairs.contains {
            (includingDisk || $0.feature != .monitorDisk) && boolFor($0.key) && isAvailable($0.feature)
        }
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
        case .automationFinder, .automationPlayback: return "gearshape.2"
        case .audioCapture: return "waveform"
        case .microphone: return "mic"
        case .calendar: return "calendar"
        case .camera: return "camera"
        case .appManagement: return "app.badge"
        }
    }
}
