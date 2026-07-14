// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit

/// Bridges the pure feature catalog to the live singletons. Every binding is
/// a closure, so merely mentioning a feature never instantiates its service:
/// a service only comes to life when its binding runs, and syncAtLaunch skips
/// unavailable features entirely — switched off in the hub means nothing
/// loads and nothing runs after the next launch. Main thread only, like the
/// services it drives.
final class FeatureRuntime: ObservableObject {
    static let shared = FeatureRuntime()

    /// Bumped on every availability change; views observing the runtime
    /// re-read the catalog when it moves.
    @Published private(set) var revision = 0

    /// Every feature that came to life in THIS process: available at launch
    /// or installed later in the session. A feature uninstalled mid-session
    /// stops working immediately, but its (inert) singleton only leaves
    /// memory on the next launch — this set is what the hub's restart banner
    /// keys off, including the install-then-uninstall-again case.
    private var loadedThisSession = Set(AppFeature.allCases.filter(\.isAvailable))

    private init() {}

    /// True while something that loaded this session is now uninstalled, so
    /// a restart would actually unload it. Features already uninstalled when
    /// the app came up never loaded, so they need no restart.
    var needsRestartToUnload: Bool {
        loadedThisSession.contains { !$0.isAvailable }
    }

    /// Relaunches the app in place: a detached `open` fires after the process
    /// exits, so the fresh instance starts without the uninstalled features.
    func relaunchApp() {
        guard let bundleID = Bundle.main.bundleIdentifier else { return }
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/sh")
        task.arguments = ["-c", "sleep 0.6; /usr/bin/open -b '\(bundleID)'"]
        try? task.run()
        NSApp.terminate(nil)
    }

    func isAvailable(_ feature: AppFeature) -> Bool { feature.isAvailable }

    var availableCount: Int { AppFeature.allCases.filter(\.isAvailable).count }

    /// Flipping availability runs the feature's binding immediately: off
    /// tears every resource down on the spot, on restores whatever enabled
    /// state the feature had (its own keys are never touched).
    func setAvailable(_ feature: AppFeature, _ available: Bool) {
        guard feature.isAvailable != available else { return }
        UserDefaults.standard.set(available, forKey: feature.availabilityKey)
        if available { loadedThisSession.insert(feature) }
        Self.bindings[feature]?()
        revision += 1
    }

    /// Applies a hub preset: its features become the installed set, with
    /// their enable keys switched on so they work right away, and everything
    /// else uninstalls. Nothing is deleted, so any feature returns with one
    /// click, settings intact.
    func apply(_ preset: FeaturePreset) {
        for key in preset.enableKeys {
            UserDefaults.standard.set(true, forKey: key)
        }
        for feature in AppFeature.allCases
        where feature.isAvailable != preset.features.contains(feature) {
            let joins = preset.features.contains(feature)
            UserDefaults.standard.set(joins, forKey: feature.availabilityKey)
            if joins { loadedThisSession.insert(feature) }
            Self.bindings[feature]?()
        }
        // Features that stayed installed still need a sync: their enable
        // keys may have just flipped on. Syncs are idempotent, so a repeat
        // for the ones handled above costs nothing.
        for feature in preset.features {
            Self.bindings[feature]?()
        }
        revision += 1
    }

    /// Bulk install or uninstall for the hub's "all" buttons: one revision
    /// bump, every changed feature's binding run.
    func setAllAvailable(_ available: Bool) {
        var changed = false
        for feature in AppFeature.allCases where feature.isAvailable != available {
            UserDefaults.standard.set(available, forKey: feature.availabilityKey)
            if available { loadedThisSession.insert(feature) }
            Self.bindings[feature]?()
            changed = true
        }
        if changed { revision += 1 }
    }

    /// Launch path: replaces the old unconditional sync block. Only available
    /// features get their binding run, so nothing else even instantiates.
    func syncAtLaunch() {
        for feature in AppFeature.allCases where feature.isAvailable {
            Self.bindings[feature]?()
        }
    }

    /// Re-syncs a set of features (used by the permission sinks); skips
    /// unavailable ones so their singletons never come to life.
    func sync(_ features: [AppFeature]) {
        for feature in features where feature.isAvailable {
            Self.bindings[feature]?()
        }
    }

    /// What each feature must re-evaluate when its availability (or a
    /// permission it depends on) changes. On-demand tools (media, uninstaller,
    /// homebrew, cleaning mode) hold no resources, so they have no binding —
    /// their surfaces simply follow availability in the UI.
    private static let bindings: [AppFeature: () -> Void] = [
        .switcher: {
            AppActivationTracker.shared.syncWithFeatures()
            AppSwitcher.shared.syncWithPreferences()
        },
        .dockPreview: { DockPreviewService.shared.syncWithPreferences() },
        .dockClick: { DockClickService.shared.syncWithPreferences() },
        .windowMaximizer: { WindowMaximizer.shared.syncWithPreferences() },
        .windowLayout: {
            AppActivationTracker.shared.syncWithFeatures()
            WindowLayoutService.shared.syncWithPreferences()
        },
        .autoQuit: { AutoQuitService.shared.syncWithPreferences() },
        .scrollInverter: { ScrollInverter.shared.syncWithPreferences() },
        .smoothScroll: { SmoothScrollService.shared.syncWithPreferences() },
        .mouseNavigation: { MouseNavigationService.shared.syncWithPreferences() },
        .middleClick: { MiddleClickService.shared.syncWithPreferences() },
        .keyboardDebounce: { KeyboardDebounceService.shared.syncWithPreferences() },
        .textSnippets: { TextSnippetService.shared.syncWithPreferences() },
        .clipboardHistory: { ClipboardHistoryService.shared.syncWithPreferences() },
        .pastePlain: { PastePlainService.shared.syncWithPreferences() },
        .finderCutPaste: { FinderCutPaste.shared.syncWithPreferences() },
        .shelf: { ShelfService.shared.syncWithPreferences() },
        .urlCleaner: { URLCleanerService.shared.syncWithPreferences() },
        .mixer: {
            AppVolumeMixer.shared.syncWithPreferences()
            AudioInputDeviceManager.shared.syncWithPreferences()
        },
        .soundOutputSwitcher: { SoundOutputSwitcher.shared.syncWithPreferences() },
        .micMute: { MicMuteService.shared.syncWithPreferences() },
        .musicBlock: { MusicLaunchBlocker.shared.syncWithPreferences() },
        .keepAwake: {
            KeepAwakeManager.shared.syncWithFeatures()
            HotkeyManager.shared.syncWithPreferences()
        },
        .brightness: { BrightnessService.shared.syncWithPreferences() },
        .extraBrightness: { ExtraBrightnessService.shared.syncWithPreferences() },
        .quickLauncher: { QuickLauncherService.shared.syncWithPreferences() },
        .colorPicker: { ColorSamplerService.shared.syncWithPreferences() },
        .screenOCR: { ScreenTextService.shared.syncWithPreferences() },
        .cleaner: { CleanerScheduler.shared.syncWithPreferences() },
        .monitorCPU: { FeatureRuntime.syncMonitor() },
        .monitorGPU: { FeatureRuntime.syncMonitor() },
        .monitorMemory: { FeatureRuntime.syncMonitor() },
        .monitorNetwork: { FeatureRuntime.syncMonitor() },
        .monitorDisk: { FeatureRuntime.syncMonitor() },
        .monitorPower: { FeatureRuntime.syncMonitor() },
    ]

    private static func syncMonitor() {
        SystemMonitor.shared.planDidChange()
        MonitorAlertService.shared.syncWithPreferences()
    }
}
