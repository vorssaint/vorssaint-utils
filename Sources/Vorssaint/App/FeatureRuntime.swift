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
        // Its own session: the reopen fires after we terminate, so the child
        // has to outlive the session it was started from.
        _ = try? DetachedProcess.spawn("/bin/sh", ["-c", "sleep 0.6; /usr/bin/open -b '\(bundleID)'"])
        NSApp.terminate(nil)
    }

    func isAvailable(_ feature: AppFeature) -> Bool { feature.isAvailable }

    var availableCount: Int { AppFeature.allCases.filter(\.isAvailable).count }

    /// How many features this Mac can end up with. Counting against the whole
    /// catalog instead would leave the hub's install-all button forever one
    /// short of its own disabled condition on a Mac missing some hardware.
    /// An install that predates the check still counts, so the tally can
    /// never read more installed than installable.
    var installableCount: Int {
        AppFeature.allCases.filter { $0.isHardwareSupported || $0.isAvailable }.count
    }

    /// The one gate every install passes, whichever surface asks: the hub
    /// row, the hub's install-all button, a preset and the first-run picker
    /// all decide here. A feature the Mac cannot run never installs, so a
    /// disabled row cannot be walked around from the button above it.
    ///
    /// Uninstalls are never refused and an existing install is never revoked:
    /// the check reads hardware and can be wrong, and a wrong answer that
    /// strands someone's settings costs far more than one that leaves a
    /// feature reporting itself unsupported.
    private func mayFlip(_ feature: AppFeature, to available: Bool) -> Bool {
        guard feature.isAvailable != available else { return false }
        return !available || feature.isHardwareSupported
    }

    /// Flipping availability runs the feature's binding immediately: off
    /// tears every resource down on the spot, on restores whatever enabled
    /// state the feature had (its own keys are never touched).
    func setAvailable(_ feature: AppFeature, _ available: Bool) {
        guard mayFlip(feature, to: available) else { return }
        UserDefaults.standard.set(available, forKey: feature.availabilityKey)
        if available { loadedThisSession.insert(feature) }
        Self.bindings[feature]?()
        finishAvailabilityChange()
    }

    /// Applies a hub preset: its features become the installed set, with
    /// their enable keys switched on so they work right away, and everything
    /// else uninstalls. Nothing is deleted, so any feature returns with one
    /// click, settings intact.
    func apply(_ preset: FeaturePreset) {
        replaceAvailable(with: preset.features, enabling: preset.enableKeys)
    }

    /// Replaces the installed set after the first-run picker. It uses the same
    /// availability layer as the hub, so unselected features disappear without
    /// losing any of their settings.
    func replaceAvailable(with selected: Set<AppFeature>, enabling keys: [String] = []) {
        for key in keys {
            UserDefaults.standard.set(true, forKey: key)
        }
        for feature in AppFeature.allCases
        where mayFlip(feature, to: selected.contains(feature)) {
            let joins = selected.contains(feature)
            UserDefaults.standard.set(joins, forKey: feature.availabilityKey)
            if joins { loadedThisSession.insert(feature) }
            Self.bindings[feature]?()
        }
        // Features that stayed installed still need a sync: their enable
        // keys may have just flipped on. Syncs are idempotent, so a repeat
        // for the ones handled above costs nothing. A selected feature the
        // gate refused is not installed, so it is skipped like any other
        // unavailable one and its service never comes to life.
        for feature in selected where feature.isAvailable {
            Self.bindings[feature]?()
        }
        finishAvailabilityChange()
    }

    /// Bulk install or uninstall for the hub's "all" buttons: one revision
    /// bump, every changed feature's binding run.
    func setAllAvailable(_ available: Bool) {
        var changed = false
        for feature in AppFeature.allCases where mayFlip(feature, to: available) {
            UserDefaults.standard.set(available, forKey: feature.availabilityKey)
            if available { loadedThisSession.insert(feature) }
            Self.bindings[feature]?()
            changed = true
        }
        if changed { finishAvailabilityChange() }
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

    /// One bump for Settings, and the Command Bar drops rows of features that
    /// just left the hub so a pin cannot linger as a bare id.
    private func finishAvailabilityChange() {
        revision += 1
        CommandBarService.shared.noteHubChange()
    }

    /// What each feature must re-evaluate when its availability (or a
    /// permission it depends on) changes. Most on-demand tools have no binding;
    /// Media only binds so uninstalling it can cancel work already in flight.
    private static let bindings: [AppFeature: () -> Void] = [
        .switcher: {
            WindowUseTracker.shared.syncWithFeatures()
            AppSwitcher.shared.syncWithPreferences()
        },
        .dockPreview: { DockPreviewService.shared.syncWithPreferences() },
        .dockClick: { DockClickService.shared.syncWithPreferences() },
        .windowMaximizer: { WindowMaximizer.shared.syncWithPreferences() },
        .windowLayout: {
            WindowUseTracker.shared.syncWithFeatures()
            WindowLayoutService.shared.syncWithPreferences()
        },
        .autoQuit: { AutoQuitService.shared.syncWithPreferences() },
        .scrollInverter: { ScrollInverter.shared.syncWithPreferences() },
        .focusFollowsMouse: { FocusFollowsMouseService.shared.syncWithPreferences() },
        .smoothScroll: { SmoothScrollService.shared.syncWithPreferences() },
        .mouseNavigation: { MouseNavigationService.shared.syncWithPreferences() },
        .mouseButtonShortcuts: { MouseButtonShortcutService.shared.syncWithPreferences() },
        .middleClick: { MiddleClickService.shared.syncWithPreferences() },
        .keyboardDebounce: { KeyboardDebounceService.shared.syncWithPreferences() },
        .superKey: { SuperKeyService.shared.syncWithPreferences() },
        .textSnippets: {
            TextSnippetService.shared.syncWithPreferences()
            SnippetLibraryService.shared.syncWithPreferences()
        },
        .clipboardHistory: {
            ClipboardHistoryService.shared.syncWithPreferences()
            // Auto clear rides the clipboard feature's availability but not its
            // capture toggle: uninstalling the feature stops it, turning history
            // off does not.
            ClipboardAutoClearService.shared.syncWithPreferences()
        },
        .mediaTools: {
            guard !AppFeature.mediaTools.isAvailable else { return }
            MediaService.shared.cancel()
            ScreenRecorderService.shared.closeEditors(ownedBy: .mediaTools)
        },
        .pastePlain: { PastePlainService.shared.syncWithPreferences() },
        .finderCutPaste: { FinderCutPaste.shared.syncWithPreferences() },
        .finderRename: { FinderRenameService.shared.syncWithPreferences() },
        .shelf: { ShelfService.shared.syncWithPreferences() },
        .urlCleaner: { URLCleanerService.shared.syncWithPreferences() },
        .diskImageInstaller: { DiskImageInstallerService.shared.syncWithPreferences() },
        .mixer: {
            PreciseVolumeRollerService.shared.syncWithPreferences()
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
        .bluetoothSleep: { BluetoothSleepService.shared.syncWithPreferences() },
        .quickLauncher: { QuickLauncherService.shared.syncWithPreferences() },
        .colorPicker: {
            ScreenCaptureService.shared.syncWithPreferences()
        },
        .screenOCR: {
            ScreenCaptureService.shared.syncWithPreferences()
            ScreenTextService.shared.syncWithPreferences()
        },
        .screenshot: {
            ScreenCaptureService.shared.syncWithPreferences()
            ScreenshotService.shared.syncWithPreferences()
        },
        .screenRecorder: {
            ScreenCaptureService.shared.syncWithPreferences()
            ScreenRecorderService.shared.syncWithPreferences()
        },
        .cameraPreview: { CameraPreviewService.shared.syncWithPreferences() },
        .radialMenu: { RadialMenuService.shared.syncWithPreferences() },
        .scratchpad: { ScratchpadService.shared.syncWithPreferences() },
        .commandBar: { CommandBarService.shared.syncWithPreferences() },
        .cleaner: {
            CleanerScheduler.shared.syncWithPreferences()
            WhatsAppDownloadScheduler.shared.syncWithPreferences()
            WhatsAppDownloadOrganizer.shared.syncWithPreferences()
            if !AppFeature.cleaner.isAvailable || !WhatsAppDownloadSupport.isEnabled {
                WhatsAppDownloadManager.shared.reset()
                WhatsAppDownloadOrganizer.shared.stop()
            }
        },
        .appUpdates: { AppUpdatesService.shared.syncWithPreferences() },
        .monitorCPU: { FeatureRuntime.syncMonitor() },
        .monitorGPU: { FeatureRuntime.syncMonitor() },
        .monitorMemory: { FeatureRuntime.syncMonitor() },
        .monitorNetwork: { FeatureRuntime.syncMonitor() },
        .monitorDisk: { FeatureRuntime.syncMonitor() },
        .monitorPower: { FeatureRuntime.syncMonitor() },
        .fanControl: {
            SystemMonitor.shared.planDidChange()
            let defaults = UserDefaults.standard
            let needsRecovery = defaults.bool(forKey: DefaultsKey.fanControlRecoveryNeeded)
            let hasRegisteredHelper = !(defaults.string(forKey: DefaultsKey.fanControlHelperVersion) ?? "").isEmpty
            if needsRecovery || (!AppFeature.fanControl.isAvailable && hasRegisteredHelper) {
                FanControlService.shared.syncWithPreferences()
            }
        },
    ]

    private static func syncMonitor() {
        SystemMonitor.shared.planDidChange()
        MonitorAlertService.shared.syncWithPreferences()
    }
}

/// Hardware a feature needs and this Mac may not have. One switch answers
/// both questions, so a feature can never be unsupported without a reason to
/// show for it, and a feature added here can never grey a row silently.
/// It lives beside the runtime rather than in the catalog because the answer
/// comes from a service, and the catalog stays a pure description.
extension AppFeature {
    /// Why this Mac cannot run the feature, ready to show. `nil` when it can,
    /// or when the feature depends on no hardware at all.
    var hardwareUnsupportedReason: String? {
        switch self {
        case .fanControl:
            return FanControlHardware.hasControllableFan
                ? nil : FeatureStrings.fanControl(L10n.shared.language).noFans
        default:
            return nil
        }
    }

    var isHardwareSupported: Bool { hardwareUnsupportedReason == nil }

    /// Why a feature list must refuse to install this feature, ready to show
    /// as a tooltip. `nil` once it is installed: the check reads hardware and
    /// can be wrong, so it is never allowed to strand an existing install
    /// behind a greyed row. Both the hub and the first-run picker read this,
    /// so neither can drift from the gate in `FeatureRuntime`.
    var installBlockedReason: String? {
        isAvailable ? nil : hardwareUnsupportedReason
    }
}
