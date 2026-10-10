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

    /// A clean install starts from the small Essential set before any feature
    /// binding runs. Updates keep every existing availability choice, and an
    /// interrupted setup keeps the selection already applied on its purpose
    /// step.
    static func prepareFirstRunAvailability(in defaults: UserDefaults = .standard) {
        guard !defaults.bool(forKey: DefaultsKey.hasOnboarded),
              defaults.integer(forKey: DefaultsKey.onboardingStep) == 0
        else { return }
        let selected = FeaturePreset.essential.features
        for feature in AppFeature.allCases {
            defaults.set(selected.contains(feature), forKey: feature.availabilityKey)
        }
    }

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
    /// A pointer gesture that works with either a trackpad or mouse.
    case pointer
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
        case .scrollInverter, .scrollHorizontal, .focusFollowsMouse, .smoothScroll, .linearScroll, .windowMaximizer, .middleClick,
             .mouseNavigation, .mouseButtonShortcuts, .mouseClickDebounce,
             .dockPreview, .dockClick, .shelf:
            return .mouse
        case .keyboardDebounce, .finderCutPaste, .finderRename, .quitWindowProtection, .musicBlock:
            return .keyboard
        // The switcher's tap also takes clicks and scrolls, and the Super key
        // stamps its modifiers on mouse presses from a second tap.
        case .switcher, .superKey, .textSnippets, .autoQuit:
            return .inputs
        case .windowLayout:
            let edgeSnapRuns = UserDefaults.standard.bool(forKey: DefaultsKey.windowEdgeSnapEnabled)
                && !WindowEdgeSnapZone.enabledZones(
                    from: UserDefaults.standard.string(
                        forKey: DefaultsKey.windowEdgeSnapDisabledZones)
                ).isEmpty
            let pointerTapRuns = UserDefaults.standard.bool(forKey: DefaultsKey.windowGestureEnabled)
                || edgeSnapRuns
            let modifierTapRuns = UserDefaults.standard.bool(forKey: DefaultsKey.windowDirectionalEnabled)
                && UserDefaults.standard.string(forKey: DefaultsKey.windowDirectionalShortcut)
                    .flatMap(WindowDirectionalTrigger.init(storageValue:))
                    .map { if case .modifiers = $0 { return true }; return false } == true
            if modifierTapRuns { return .inputs }
            return pointerTapRuns ? .pointer : .idle
        case .radialMenu:
            // A side button or the trackpad tap on any wheel keeps an input
            // tap running; shortcut-only costs nothing at rest.
            return RadialMenuSupport.opensFromMouseOrTrackpad(
                UserDefaults.standard.data(forKey: DefaultsKey.radialMenuProfiles))
                ? .mouse : .idle
        case .notchNotifications, .notchGestures, .notchTimer, .notchQueue, .notchDownloads: return .idle
        // It reads only while something is being watched, and stops on its own.
        case .notchWatch: return .idle
        // A blink every few seconds and a visit every few minutes, both
        // drawn by Core Animation, with one timer waiting for the next visit.
        case .notchMascot: return .periodic
        case .notchAccessories: return .periodic
        // Log changes arrive as file events; a timer keeps countdowns and
        // limits current while the section is on.
        case .notch, .notchCalendar, .notchLyrics, .notchLiveEqualizer, .notchAgents: return .periodic
        case .clipboardHistory, .urlCleaner, .extraBrightness,
             .monitorCPU, .monitorGPU, .monitorMemory,
             .monitorNetwork, .monitorDisk, .monitorPower, .connectedDevices:
            return .periodic
        case .mixer:
            return UserDefaults.standard.bool(forKey: DefaultsKey.preciseVolumeRollerEnabled)
                ? .keyboard : .idle
        case .brightness:
            // Following the pointer, the overlay and a finer step answer the
            // brightness keys from a tap. Like Accessibility, the island's own
            // notices are counted under the island.
            let defaults = UserDefaults.standard
            return defaults.bool(forKey: DefaultsKey.brightnessKeysEnabled)
                || defaults.bool(forKey: DefaultsKey.brightnessOSDEnabled)
                || BrightnessSupport.KeyStep.sanitized(
                    defaults.string(forKey: DefaultsKey.brightnessKeyStep)) != .standard
                ? .keyboard : .idle
        case .mouseAcceleration, .spacesOrder, .pastePlain, .soundOutputSwitcher, .audioPriority, .micMute,
             .bluetoothSleep, .keepAwake, .quickLauncher, .quickToggles, .colorPicker,
             .screenOCR, .cleaningMode, .mediaTools, .cleaner, .uninstaller, .homebrew, .screenshot,
             .cameraPreview, .scratchpad, .commandBar, .screenRecorder, .wallpaper, .fanControl,
             .diskImageInstaller, .killProcess, .portManager:
            return .idle
        case .appUpdates:
            // The list is on demand; only a background schedule keeps a timer.
            return AppUpdatesSupport.CheckFrequency.sanitized(
                UserDefaults.standard.string(forKey: DefaultsKey.appUpdatesCheckFrequency)) == .off
                ? .idle : .periodic
        }
    }
}

/// Discovery views only change presentation; switching views never changes
/// feature availability, behavior settings or running services.
enum SettingsExperience: String, CaseIterable, Identifiable {
    case simple, advanced, expert
    var id: String { rawValue }

    static func sanitized(_ raw: String) -> Self { Self(rawValue: raw) ?? .expert }

    var features: Set<AppFeature> {
        switch self {
        case .simple:
            return Set<AppFeature>([.mixer, .micMute, .keepAwake, .brightness, .screenshot, .screenRecorder,
                    .clipboardHistory, .pastePlain, .windowLayout, .switcher, .dockPreview,
                    .notch, .notchTimer]).union(AppFeature.features(in: .monitor))
        case .advanced:
            return Self.simple.features.union([
                .dockClick, .windowMaximizer, .scrollInverter, .smoothScroll, .mouseNavigation,
                .middleClick, .textSnippets, .quitWindowProtection, .finderCutPaste, .finderRename,
                .shelf, .urlCleaner, .soundOutputSwitcher, .audioPriority, .quickLauncher,
                .quickToggles, .colorPicker, .screenOCR, .mediaTools, .cleaner, .uninstaller,
                .appUpdates, .scratchpad, .commandBar, .notchCalendar, .notchNotifications,
                .notchGestures, .notchAccessories, .notchLyrics, .notchQueue, .notchDownloads,
                .monitorGPU, .monitorNetwork, .monitorDisk, .connectedDevices])
        case .expert:
            return Set(AppFeature.allCases)
        }
    }

    /// The selector is a presentation filter. A requested search destination
    /// can be revealed without switching profiles or changing availability.
    func shows(_ feature: AppFeature, revealing requested: AppFeature? = nil) -> Bool {
        features.contains(feature) || feature == requested
    }

    func hiddenFeatureCount(revealing requested: AppFeature? = nil) -> Int {
        AppFeature.allCases.filter { !shows($0, revealing: requested) }.count
    }
}

extension FeatureGroup {
    func title(_ language: AppLanguage, hub: FeatureHubStrings) -> String {
        switch self {
        case .windowsDock: return hub.groupWindowsDock
        case .mouseKeyboard: return hub.groupMouseKeyboard
        case .clipboardFiles: return hub.groupClipboardFiles
        case .capture: return SettingsDiscoveryStrings.localized(language).capture
        case .applications: return SettingsDiscoveryStrings.localized(language).applications
        case .sound: return hub.groupSound
        case .energyDisplay: return hub.groupEnergyDisplay
        case .tools: return hub.groupTools
        case .dynamicIsland: return FeatureStrings.notch(language).title
        case .monitor: return hub.groupMonitor
        }
    }

    var symbolName: String {
        switch self {
        case .windowsDock: return "macwindow.on.rectangle"
        case .mouseKeyboard: return "computermouse"
        case .clipboardFiles: return "doc.on.clipboard"
        case .capture: return "camera.viewfinder"
        case .applications: return "shippingbox"
        case .sound: return "speaker.wave.2.fill"
        case .energyDisplay: return "bolt.fill"
        case .tools: return "wrench.and.screwdriver.fill"
        case .dynamicIsland: return AppFeature.notch.symbolName
        case .monitor: return "chart.line.uptrend.xyaxis"
        }
    }
}

/// The visible state of a feature's availability and saved behavior, not a
/// claim about permissions or whether a timer/on-demand tool is active now.
enum FeatureConfigurationState {
    case excluded, parentRequired, configuredOff, configuredOn, onDemand
}

extension AppFeature {
    func configurationState(isAvailable: (AppFeature) -> Bool,
                            boolFor: (String) -> Bool) -> FeatureConfigurationState {
        guard isAvailable(self) else { return .excluded }
        if group == .dynamicIsland && self != .notch,
           !isAvailable(.notch) || !boolFor(DefaultsKey.notchEnabled) { return .parentRequired }
        guard !enabledKeys.isEmpty else { return .onDemand }
        return enabledKeys.contains(where: boolFor) ? .configuredOn : .configuredOff
    }

    /// Stable alphabetical order shared by the sidebar and discovery catalog.
    static func sorted(_ features: [AppFeature], title: (AppFeature) -> String) -> [AppFeature] {
        features.sorted {
            let comparison = title($0).localizedStandardCompare(title($1))
            return comparison == .orderedSame ? $0.rawValue < $1.rawValue : comparison == .orderedAscending
        }
    }
}
