// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

// The runner lists every independently selectable suite. A filtered run says
// exactly which suites ran; an unknown or empty selection is an error.
@main
struct MetricsTests {
    static func main() {
        let suite = TestSuite()
        let groups: [(String, () -> Void)] = [
            ("harness", {
                TestHarnessTests.run(suite)
                PreferenceNamespaceTests.run(suite)
            }),
            ("metrics", {
                MetricsFeatureTests.run(suite)
                ProcessNameContract.run(suite)
            }),
            ("clipboard", { ClipboardFeatureTests.run(suite) }),
            ("pointer-input", {
                PointerOnDisplayContract.run(suite)
                PointerInputFeatureTests.run(suite)
                SuperKeyTapContract.run(suite)
            }),
            ("scroll-modifier", { ScrollHorizontalModifierTests.run(suite) }),
            ("preferences", { PreferencesFeatureTests.run(suite) }),
            ("app-management", { AppManagementFeatureTests.run(suite) }),
            ("window-layout", { WindowLayoutFeatureTests.run(suite) }),
            ("media", { MediaFeatureTests.run(suite) }),
            ("mixer", {
                MixerNativeDragTests.run(suite)
                MixerOutputAdjustmentContract.run(suite)
                SoundOutputSwitchContract.run(suite)
                MixerInputVolumeContract.run(suite)
                MixerFeatureTests.run(suite)
            }),
            ("shelf", { ShelfFeatureTests.run(suite) }),
            ("updates", {
                UpdateFeatureTests.run(suite)
                PostUpdateStatusItemRecoveryTests.run(suite)
            }),
            ("repository", { RepositoryFeatureTests.run(suite) }),
            ("screenshots", {
                ScreenshotPreviewHoverTests.run(suite)
                ScreenshotWatermarkTests.run(suite)
                ScreenshotFeatureTests.run(suite)
            }),
            ("recorder", {
                RecorderFeatureTests.run(suite)
                RecorderZoomAimingTests.run(suite)
                RecorderExportSpeedTests.run(suite)
                RecorderExportRenderingTests.run(suite)
            }),
            ("command-bar", { CommandBarFeatureTests.run(suite) }),
            ("notch", {
                NotchTests.run(suite)
                NotchCompactTests.run(suite)
                NotchVolumeKeyTests.run(suite)
            }),
            ("switcher-model", { SwitcherModelFeatureTests.run(suite) }),
            ("agents", { NotchAgentTests.run(suite) }),
            ("features", { FeatureCatalogTests.run(suite) }),
            ("utilities", {
                UtilitiesFeatureTests.run(suite)
                PortManagerRefreshTests.run(suite)
            }),
            ("settings", {
                SettingsFeatureTests.run(suite)
                SettingsWindowTests.run { suite.expect($0, $1) }
            }),
            ("display-restoration", { DisplayRestorationTests.run(suite) }),
            ("software-dimming", { SoftwareDimmingRouteTests.run { suite.expect($0, $1) } }),
            ("capture", { ScreenshotSelectionRefreshContract.run(suite) }),
            ("keyboard", {
                KeyboardFeatureTests.run(suite)
                AssistiveKeyboardTests.run(suite)
                ScreenshotToolShortcutTests.run(suite)
            }),
            ("storage", {
                RecentCaptureStoreTests.run(suite)
                RecorderPresetImageStoreTests.run(suite)
                StorageFeatureTests.run(suite)
                ScratchpadStoreContractTests.run(suite)
            }),
            ("quit-protection", { QuitProtectionHUD.progressChecks(suite) }),
            ("recording", {
                RecorderSampleTimingTests.run(suite)
                RecorderWriterTests.run(suite)
                RecorderExportChipTests.run { suite.expect($0, $1) }
            }),
            ("network", {
                NetworkFeatureTests.run(suite)
                SpeedTestTests.run(suite)
                NetworkAddressTests.run { suite.expect($0, $1) }
            }),
            ("app-updates", { AppUpdatesContract.run(suite) }),
            ("localization", {
                LocalizationTests.run(suite)
                LocalizationFeatureContractTests.run(suite)
            }),
            ("cleaner", {
                CleanerEligibilityTests.run(suite)
                CleanerLastRunContract.run(suite)
            }),
            ("uninstaller", {
                UninstallerFlowTests.run(suite)
                SelfUninstallContract.run(suite)
            }),
            ("launcher", { QuickLauncherContract.run(suite) }),
            ("dock-autohide", {
                DockAutohideHoldTests.run(suite)
                DockPreviewFrameRestorationTests.run(suite)
            }),
            ("switcher", {
                SwitcherScrollContract.run(suite)
                SwitcherActivationTests.run(suite)
            }),
            ("keep-awake", {
                KeepAwakeCatalogContract.run(suite)
                MenuPanelToggleLabelContract.run(suite)
                KeepAwakeLidSleepTests.run { suite.expect($0, $1) }
                KeepAwakeTimerHandoffTests.run { suite.expect($0, $1) }
            }),
            ("emoji", { CommandBarEmojiContract.run(suite) }),
        ]
        var selected = Set<String>()
        var listOnly = false
        for argument in CommandLine.arguments.dropFirst() {
            if argument == "--list" {
                listOnly = true
                continue
            }
            guard argument.hasPrefix("--suite="),
                  groups.contains(where: { $0.0 == String(argument.dropFirst(8)) }) else {
                fputs("Unknown test selection: \(argument)\n", stderr)
                exit(2)
            }
            selected.insert(String(argument.dropFirst(8)))
        }
        if listOnly {
            groups.forEach { print($0.0) }
            exit(0)
        }
        for (name, body) in groups where selected.isEmpty || selected.contains(name) {
            suite.run(name, body)
        }
        suite.finish()
    }
}
