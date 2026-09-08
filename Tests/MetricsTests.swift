// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

// Standalone helper, fixture, and source-contract suites compiled by ./build.sh --test.
// Keep execution serial: AppKit, keyboard layouts, and shared preferences are process-wide.
@main
struct MetricsTests {
    static func main() {
        var failures: [String] = []
        var checks = 0

        func expect(_ condition: Bool, _ message: String) {
            checks += 1
            if !condition { failures.append(message) }
        }

        MetricFormat.locale = Locale(identifier: "en_US_POSIX")

        MetricFormatTests.run(expect: expect)
        ClipboardTests.run(expect: expect)
        BatteryMetricTests.run(expect: expect)
        KeyboardDebounceTests.run(expect: expect)
        PointerInputTests.run(expect: expect)
        SmoothScrollTests.run(expect: expect)
        MetricFormatTests.runSensorsAndMemory(expect: expect)
        DefaultsTests.run(expect: expect)
        SwitcherTests.run(expect: expect)
        DefaultsTests.runVisibilityMigration(expect: expect)
        DockPreviewTests.run(expect: expect)
        ReleaseTests.run(expect: expect)
        DefaultsTests.runFeatureDefaults(expect: expect)
        MenuBarTests.run(expect: expect)
        ShortcutTests.runDefaults(expect: expect)
        ShortcutTests.run(expect: expect)
        CleanerScheduleTests.run(expect: expect)
        BrightnessTests.runExtraBrightness(expect: expect)
        UninstallerTests.run(expect: expect)
        DefaultsTests.runSanitization(expect: expect)
        AutoQuitTests.run(expect: expect)
        WindowLayoutTests.run(expect: expect)
        MediaTests.run(expect: expect)
        MixerTests.run(expect: expect)
        BoostLimiterTests.run(expect: expect)
        MixerRenderTests.run(expect: expect)
        ShelfTests.run(expect: expect)
        MiddleClickTests.run(expect: expect)
        FinderTests.run(expect: expect)
        ShortcutTests.runSystemConflicts(expect: expect)
        UpdateInstallerTests.runProgress(expect: expect)
        SettingsSearchTests.run(expect: expect)
        UpdateInstallerTests.run(expect: expect)
        let finishDetachedProcess = DetachedProcessTests.run(expect: expect)
        UpdateInstallerTests.runReconciliation(expect: expect)
        DockPreviewTests.runGeometry(expect: expect)
        DockClickTests.run(expect: expect)
        MiddleClickTests.runTransforms(expect: expect)
        QuickToolsTests.run(expect: expect)
        SwitcherTests.runGroupingAndSearch(expect: expect)
        ReleaseTests.runNotes(expect: expect)
        URLCleanerTests.run(expect: expect)
        HomebrewTests.run(expect: expect)
        LocalizationTests.run(expect: expect)
        RepositoryContractTests.runResources(expect: expect)
        NetworkMetricTests.run(expect: expect)
        CleaningModeTests.run(expect: expect)
        MusicLaunchTests.run(expect: expect)
        FeatureCatalogTests.run(expect: expect)
        LocalizationTests.runDeviceStrings(expect: expect)
        FanControlTests.run(expect: expect)
        FeatureCatalogTests.runPermissions(expect: expect)
        LocalizationTests.runFeatureStrings(expect: expect)
        KillProcessTests.run(expect: expect)
        FeatureCatalogTests.runPresetsAndStrings(expect: expect)
        SettingsNavigationTests.run(expect: expect)
        BrightnessTests.run(expect: expect)
        SnippetTests.run(expect: expect)
        RadialMenuTests.run(expect: expect)
        DockClickTests.runRestoreOrder(expect: expect)
        QuickToolsTests.runToggles(expect: expect)
        ScreenshotTests.run(expect: expect)
        RepositoryContractTests.runDrawing(expect: expect)
        ScreenshotTests.runEditor(expect: expect)
        ScratchpadTests.runDefaults(expect: expect)
        RepositoryContractTests.runConcurrencyAndAccessibility(expect: expect)
        ScratchpadTests.run(expect: expect)
        QuickToolsTests.runMicrophone(expect: expect)
        RadialMenuTests.runActivation(expect: expect)
        MouseButtonTests.run(expect: expect)
        SuperKeyTests.run(expect: expect)
        MouseExceptionTests.run(expect: expect)
        SettingsBackupTests.run(expect: expect)
        MixerTests.runPreciseVolume(expect: expect)
        AppUpdateTests.run(expect: expect)
        BrightnessTests.runKeyTiming(expect: expect)
        CommandBarTests.run(expect: expect)
        RecorderTests.run(expect: expect)
        CommandBarLocalizationTests.run(expect: expect)
        CommandBarLifecycleTests.run(expect: expect)
        CommandBarSearchTests.run(expect: expect)
        ScreenshotTests.runDedicatedShortcuts(expect: expect)
        UninstallerTests.runFailurePresentation(expect: expect)
        PrivateFileStoreTests.run(expect: expect)
        BuildContractTests.run(expect: expect)
        RepositoryContractTests.runLifecycle(expect: expect)
        finishDetachedProcess(expect)
        QuitProtectionTests.run(expect: expect)
        ShelfTests.runPersistence(expect: expect)
        CommandBarSearchTests.runNormalization(expect: expect)
        ScreenshotTests.runShareExpiry(expect: expect)
        QuitProtectionTests.runHUD(expect: expect)
        QuickToolsTests.runDiskExclusions(expect: expect)

        if failures.isEmpty {
            print("TESTS OK (\(checks) checks)")
            exit(0)
        } else {
            print("TESTS FAILED (\(failures.count) of \(checks)):")
            failures.forEach { print("  - \($0)") }
            exit(1)
        }
    }
}
