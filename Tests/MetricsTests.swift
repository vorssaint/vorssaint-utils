// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import CoreGraphics
import Foundation

// Standalone unit tests for pure helpers. Compiled without IOKit or UI by
// `./build.sh --test`, so they run fast and deterministically on any machine.
//
// A tiny @main harness instead of XCTest: the Command Line Tools cannot run
// `swift test`, and these checks need nothing more than equality assertions.
@main
struct MetricsTests {
    static func main() {
        var failures: [String] = []
        var checks = 0

        func expect(_ condition: Bool, _ message: @autoclosure () -> String) {
            checks += 1
            if !condition { failures.append(message()) }
        }
        func expectEqual(_ actual: String, _ expected: String, _ label: String) {
            checks += 1
            if actual != expected { failures.append("\(label): got \"\(actual)\", expected \"\(expected)\"") }
        }
        func expectClose(_ actual: Double, _ expected: Double, _ label: String, tol: Double = 0.0001) {
            checks += 1
            if abs(actual - expected) > tol { failures.append("\(label): got \(actual), expected \(expected)") }
        }
        func expectFormat(_ format: String, _ expected: [String], _ label: String) {
            checks += 1
            let actual = formatSpecifiers(in: format)
            if actual != expected { failures.append("\(label): got \(actual), expected \(expected)") }
        }

        // MARK: Byte / rate formatting

        expectEqual(MetricFormat.bytes(0), "0 B", "bytes zero")
        expectEqual(MetricFormat.bytes(512), "512 B", "bytes < 1K")
        expectEqual(MetricFormat.bytes(1024), "1.0 KB", "bytes 1K")
        expectEqual(MetricFormat.bytes(1536), "1.5 KB", "bytes 1.5K")
        expectEqual(MetricFormat.bytes(10 * 1024), "10 KB", "bytes 10K drops decimal")
        expectEqual(MetricFormat.bytes(1024 * 1024), "1.0 MB", "bytes 1M")
        expectEqual(MetricFormat.bytes(3 * 1024 * 1024 * 1024), "3.0 GB", "bytes 3G")

        expectEqual(MetricFormat.bytesPerSec(0), "0 B/s", "rate zero")
        expectEqual(MetricFormat.bytesPerSec(2 * 1024 * 1024), "2.0 MB/s", "rate 2M")
        expectEqual(MetricFormat.bytesPerSec(1500 * 1024), "1.5 MB/s", "rate 1.5M")

        expectEqual(MetricFormat.bytesPerSecCompact(0), "0B", "compact zero")
        expectEqual(MetricFormat.bytesPerSecCompact(320 * 1024), "320K", "compact 320K")
        expectEqual(MetricFormat.bytesPerSecCompact(1.2 * 1024 * 1024), "1.2M", "compact 1.2M")

        // MARK: Watts & percent

        expectEqual(MetricFormat.watts(8.5), "8.5 W", "watts under 10")
        expectEqual(MetricFormat.watts(23.4), "23 W", "watts over 10 rounds")
        expectEqual(MetricFormat.wattsCompact(8.6), "9W", "watts compact rounds")
        expectEqual(MetricFormat.percent(0), "0%", "percent 0")
        expectEqual(MetricFormat.percent(0.125), "13%", "percent rounds")
        expectEqual(MetricFormat.percent(1), "100%", "percent full")
        expectEqual(MetricFormat.percent(1.4), "100%", "percent clamps high")
        expectEqual(MetricFormat.percent(-0.2), "0%", "percent clamps low")
        expectClose(MetricFormat.stabilizedGPUUsage(previous: 0.03, current: 0.80), 0.23,
                    "GPU usage readout caps one-tick upward spikes")
        expectClose(MetricFormat.stabilizedGPUUsage(previous: 0.23, current: 0.80), 0.43,
                    "GPU usage readout still climbs during sustained load")
        expectClose(MetricFormat.stabilizedGPUUsage(previous: 0.60, current: 0.10), 0.275,
                    "GPU usage readout falls quickly after transient load")
        expectClose(MetricFormat.stabilizedGPUUsage(previous: nil, current: 1.4), 1.0,
                    "GPU usage readout clamps first sample")
        expectEqual(MetricFormat.temperature(0, unit: .celsius), "0 °C", "celsius freezing")
        expectEqual(MetricFormat.temperature(0, unit: .fahrenheit), "32 °F", "fahrenheit freezing")
        expectEqual(MetricFormat.temperature(41, unit: .fahrenheit), "106 °F", "fahrenheit rounds")
        expectEqual(MetricFormat.temperatureCompact(49.6, unit: .celsius), "50°", "compact celsius rounds")
        expectEqual(MetricFormat.temperatureCompact(49.6, unit: .fahrenheit), "121°", "compact fahrenheit rounds")
        expectEqual(MetricFormat.temperatureUnitSuffix(.celsius), "°C", "celsius suffix is explicit")
        expectEqual(MetricFormat.temperatureUnitSuffix(.fahrenheit), "°F", "fahrenheit suffix is explicit")

        // MARK: Temperature sensor selection

        expect(TemperatureSensorSelector.platform(brandString: "Apple M1") == .appleM1Family,
               "Apple M1 uses the mapped CPU core sensor set")
        expect(TemperatureSensorSelector.platform(brandString: "Apple M2 Pro") == .appleM2Family,
               "Apple M2 Pro uses the mapped CPU core sensor set")
        expect(TemperatureSensorSelector.platform(brandString: "Apple M3 Max") == .appleM3Family,
               "Apple M3 Max uses the mapped CPU core sensor set")
        expect(TemperatureSensorSelector.platform(brandString: "Apple M4 Ultra") == .appleM4Family,
               "Apple M4 Ultra uses the mapped CPU core sensor set")
        expect(TemperatureSensorSelector.platform(brandString: "Apple M5") == .appleM5Family,
               "Apple M5 uses the mapped CPU core sensor set")
        expect(TemperatureSensorSelector.platform(brandString: "Apple M10") == .generic,
               "future unmapped Apple Silicon generations keep the generic CPU sensor path")
        let m1CPU = TemperatureSensorSelector.displayedCPUTemperature(
            readings: [("Tp09", 43.0), ("Tp01", 49.0), ("Tp02", 70.0)],
            platform: .appleM1Family
        )
        expectClose(m1CPU ?? -1, 49.0, "M1 family uses hottest mapped CPU core")
        let m2CPU = TemperatureSensorSelector.displayedCPUTemperature(
            readings: [("Tp1h", 42.0), ("Tp0j", 52.0), ("Tp0k", 75.0)],
            platform: .appleM2Family
        )
        expectClose(m2CPU ?? -1, 52.0, "M2 family uses hottest mapped CPU core")
        let m3CPU = TemperatureSensorSelector.displayedCPUTemperature(
            readings: [("Te05", 44.0), ("Tf4E", 53.0), ("Tf4F", 76.0)],
            platform: .appleM3Family
        )
        expectClose(m3CPU ?? -1, 53.0, "M3 family uses hottest mapped CPU core")
        let m4CPU = TemperatureSensorSelector.displayedCPUTemperature(
            readings: [("Tp00", 44.5), ("Tp01", 51.6), ("Tp0W", 67.0), ("Te04", 43.2)],
            platform: .appleM4Family
        )
        expectClose(m4CPU ?? -1, 51.6, "M4 family uses hottest mapped CPU core instead of auxiliary hotspots")
        let m5CPU = TemperatureSensorSelector.displayedCPUTemperature(
            readings: [("Tp00", 45.0), ("Tp0y", 54.0), ("Tp0z", 80.0)],
            platform: .appleM5Family
        )
        expectClose(m5CPU ?? -1, 54.0, "M5 family uses hottest mapped CPU core")
        let m4InvalidCPU = TemperatureSensorSelector.displayedCPUTemperature(
            readings: [("Tp01", 0.5), ("Tp05", 130.0), ("Tp09", 49.25), ("Tp0W", 67.0)],
            platform: .appleM4Family
        )
        expectClose(m4InvalidCPU ?? -1, 49.25, "mapped CPU core selection ignores invalid temperatures")
        let m4FallbackCPU = TemperatureSensorSelector.displayedCPUTemperature(
            readings: [("Tp00", 44.5), ("Tp0W", 67.0)],
            platform: .appleM4Family
        )
        expectClose(m4FallbackCPU ?? -1, 67.0, "mapped CPU core selection falls back when no mapped sensor is available")
        let genericCPU = TemperatureSensorSelector.displayedCPUTemperature(
            readings: [("Tp00", 44.5), ("Tp01", 51.6)],
            platform: .generic
        )
        expectClose(genericCPU ?? -1, 51.6, "generic CPU sensor selection preserves previous hottest behavior")

        // MARK: Uptime formatting

        expectEqual(MetricFormat.uptime(0), "0min", "uptime zero")
        expectEqual(MetricFormat.uptime(59), "0min", "uptime under one minute")
        expectEqual(MetricFormat.uptime(60), "1min", "uptime one minute")
        expectEqual(MetricFormat.uptime(3_600), "1h 0min", "uptime one hour")
        expectEqual(MetricFormat.uptime(93_600), "1d 2h", "uptime days and hours")
        expectEqual(MetricFormat.uptime(8 * 86_400 + 21 * 3_600 + 8 * 60), "8d 21h",
                    "uptime keeps days compact")

        // MARK: Memory used

        let used = MetricFormat.memoryUsed(totalBytes: 16 * 1024,
                                           pageSize: 1024,
                                           freePages: 1,
                                           speculativePages: 2,
                                           fileBackedPages: 3)
        expect(used == 10 * 1024, "memory used excludes free, speculative and file-backed pages")
        expect(MetricFormat.memoryUsed(totalBytes: 16, pageSize: 1,
                                       freePages: 20, speculativePages: 0, fileBackedPages: 0) == 0,
               "memory used clamps impossible available memory")

        // MARK: Registered defaults

        let registeredDefaults = Defaults.registeredDefaults
        expect(registeredDefaults[DefaultsKey.hotkeyEnabled] as? Bool == true,
               "global hotkey is on for clean installs")
        expect(registeredDefaults[DefaultsKey.keepAwakeShortcut] as? String == "control+option+command:40",
               "keep awake shortcut defaults to Ctrl+Opt+Cmd+K")
        expect(registeredDefaults[DefaultsKey.switcherEnabled] as? Bool == true,
               "window switcher is on for clean installs")
        expect(registeredDefaults[DefaultsKey.switcherShortcut] as? String == "command:48",
               "switcher shortcut defaults to Cmd+Tab")
        expect(registeredDefaults[DefaultsKey.dockPreviewEnabled] as? Bool == false,
               "Dock Preview is opt-in for clean installs")
        expect(registeredDefaults[DefaultsKey.autoCheckUpdates] as? Bool == true,
               "update checks are on for clean installs")
        expect(registeredDefaults[DefaultsKey.shelfShortcutEnabled] as? Bool == true,
               "shelf shortcut is on by default once shelf is enabled")
        expect(registeredDefaults[DefaultsKey.shelfShortcut] as? String == "control+option+command:2",
               "shelf shortcut defaults to Ctrl+Opt+Cmd+D")
        expect(registeredDefaults[DefaultsKey.shelfShakeToOpen] as? Bool == true,
               "shelf shake opens by default once shelf is enabled")
        expect(registeredDefaults[DefaultsKey.urlCleanerEnabled] as? Bool == false,
               "URL cleaner clipboard watching is opt-in")
        expect(registeredDefaults[DefaultsKey.windowMaximizeEnabled] as? Bool == false,
               "green button maximize override is opt-in")
        expect(registeredDefaults[DefaultsKey.panelUtilityCleaning] as? Bool == true,
               "panel cleaning utility is visible by default")
        expect(registeredDefaults[DefaultsKey.panelUtilityURLCleaner] as? Bool == true,
               "panel URL cleaner utility is visible by default")
        expect(registeredDefaults[DefaultsKey.panelUtilityUninstaller] as? Bool == true,
               "panel uninstaller utility is visible by default")
        expect(registeredDefaults[DefaultsKey.panelUtilityHomebrew] as? Bool == true,
               "panel Homebrew utility is visible by default")
        expect(registeredDefaults[DefaultsKey.panelUtilityMedia] as? Bool == true,
               "panel Media utility is visible by default")
        expect(registeredDefaults[DefaultsKey.panelControlMouseScroll] as? Bool == true,
               "panel mouse scroll control is visible by default")
        expect(registeredDefaults[DefaultsKey.panelControlSwitcher] as? Bool == true,
               "panel switcher control is visible by default")
        expect(registeredDefaults[DefaultsKey.panelControlDockPreview] as? Bool == true,
               "panel Dock Preview control is visible by default")
        expect(registeredDefaults[DefaultsKey.panelControlCutPaste] as? Bool == true,
               "panel cut and paste control is visible by default")
        expect(registeredDefaults[DefaultsKey.panelControlAutoQuit] as? Bool == true,
               "panel auto quit control is visible by default")
        expect(registeredDefaults[DefaultsKey.panelControlShelf] as? Bool == true,
               "panel shelf control is visible by default")
        expect(registeredDefaults[DefaultsKey.panelControlWindowMaximize] as? Bool == true,
               "panel window maximize control is visible by default")
        expect(registeredDefaults[DefaultsKey.panelShowKeepAwake] as? Bool == true,
               "Keep Awake panel section is shown by default")
        expect(registeredDefaults[DefaultsKey.panelShowUtilities] as? Bool == true,
               "Utilities panel section is shown by default")
        expect(registeredDefaults[DefaultsKey.panelShowControls] as? Bool == true,
               "Quick Controls panel section is shown by default")
        expect(registeredDefaults[DefaultsKey.monitorInterval] as? Int == 2,
               "monitor default interval stays at 2 seconds")
        expect(registeredDefaults[DefaultsKey.temperatureUnit] as? String == TemperatureUnit.celsius.rawValue,
               "temperature defaults to Celsius")
        expect(registeredDefaults[DefaultsKey.menuBarCPUTemperature] as? Bool == false,
               "menu bar CPU temperature is opt-in")
        expect(registeredDefaults[DefaultsKey.menuBarGPUTemperature] as? Bool == false,
               "menu bar GPU temperature is opt-in")
        expect(registeredDefaults[DefaultsKey.menuBarBatteryTemperature] as? Bool == false,
               "menu bar battery temperature is opt-in")
        expect(registeredDefaults[DefaultsKey.menuBarMetricOrder] as? String
               == "cpu,cpuTemperature,gpu,gpuTemperature,memory,battery,batteryTemperature,network,power",
               "menu bar metric order keeps temperature sensors next to their components")
        expect(registeredDefaults[DefaultsKey.menuBarCombineTemperatures] as? Bool == true,
               "menu bar combines usage and temperature by default")
        expect(registeredDefaults[DefaultsKey.menuBarLabelStyle] as? String == "compact",
               "menu bar label style defaults to compact")
        expect(registeredDefaults[DefaultsKey.menuBarMemoryStyle] as? String == "percent",
               "memory menu bar style defaults to percent")
        expect(registeredDefaults[DefaultsKey.mediaLastTool] as? String == MediaTool.videoCompressor.rawValue,
               "Media defaults to video compressor")
        expect(registeredDefaults[DefaultsKey.mediaVideoCodec] as? String == MediaVideoCodec.h264.rawValue,
               "Media video codec defaults to H.264")
        expect(registeredDefaults[DefaultsKey.mediaImageFormat] as? String == MediaImageFormat.jpeg.rawValue,
               "Media image format defaults to JPEG")
        expect((registeredDefaults[DefaultsKey.autoQuitExceptions] as? [String]) == Defaults.mandatoryAutoQuitExceptionBundleIDs,
               "Finder stays in the default auto-quit exception list")
        expect(registeredDefaults[DefaultsKey.panelCollapsedSections] == nil,
               "panel collapsed sections intentionally has no registered default")
        expect(registeredDefaults[DefaultsKey.panelUtilityOrder] == nil,
               "panel utility order intentionally has no registered default")
        expect(Defaults.sanitizedDefaultDuration(60) == 60, "valid default duration is preserved")
        expect(Defaults.sanitizedDefaultDuration(999) == 0, "invalid default duration falls back to indefinite")
        expect(Defaults.sanitizedBatteryLimit(15) == 15, "valid battery limit is preserved")
        expect(Defaults.sanitizedBatteryLimit(100) == 10, "invalid battery limit falls back to default")
        expect(Defaults.sanitizedMonitorInterval(5) == 5, "valid monitor interval is preserved")
        expect(Defaults.sanitizedMonitorInterval(7) == 2, "invalid monitor interval falls back to default")
        expect(Defaults.sanitizedMenuBarLabelStyle("classic") == "classic", "valid label style is preserved")
        expect(Defaults.sanitizedMenuBarLabelStyle("bad") == "compact", "invalid label style falls back to compact")
        expect(Defaults.sanitizedMenuBarMemoryStyle("dot") == "dot", "valid memory style is preserved")
        expect(Defaults.sanitizedMenuBarMemoryStyle("bad") == "percent", "invalid memory style falls back to percent")
        expect(Defaults.sanitizedMenuBarMetricOrder("cpu,gpu,memory,network,battery,power")
               == ["cpu", "gpu", "memory", "network", "battery", "power",
                   "cpuTemperature", "gpuTemperature", "batteryTemperature"],
               "menu bar metric order appends temperature sensors without rewriting existing saved order")
        expect(Defaults.sanitizedMenuBarMetricOrder("temperature,cpu,cpu,bad")
               == ["cpuTemperature", "gpuTemperature", "batteryTemperature",
                   "cpu", "gpu", "memory", "battery", "network", "power"],
               "menu bar metric order migrates the old generic temperature value")
        expect(Defaults.sanitizedBundleIdentifierList([" com.example.One ", "", "com.example.One", "com.example.Two"])
               == ["com.example.One", "com.example.Two"],
               "bundle id lists are trimmed and deduplicated")
        expect(Defaults.sanitizedAutoQuitExceptions(["com.example.One", Defaults.finderBundleIdentifier])
               == [Defaults.finderBundleIdentifier, "com.example.One"],
               "Finder is mandatory in the auto-quit exception list")
        expect(Defaults.sanitizedPanelItemOrder("uninstaller,homebrew,homebrew,bad",
                                                defaultOrder: ["homebrew", "media", "uninstaller", "cleanURL", "cleaning"])
               == ["uninstaller", "homebrew", "media", "cleanURL", "cleaning"],
               "panel item order keeps saved valid items first and appends defaults")
        let trim = MediaSupport.sanitizedTrim(start: -5, end: 3, assetDuration: 10)
        expect(trim == MediaTrimRange(start: 0, end: 3),
               "Media trim clamps negative start")
        let fullTrim = MediaSupport.sanitizedTrim(start: 2, end: 0, assetDuration: 10)
        expect(fullTrim == MediaTrimRange(start: 2, end: 10),
               "Media trim treats zero end as the source duration")
        expectClose(MediaSupport.sanitizedQuality(.infinity), 0.7,
                    "Media invalid quality falls back")
        expectClose(MediaSupport.sanitizedQuality(0.02), 0.1,
                    "Media quality clamps low")
        expectClose(MediaSupport.sanitizedQuality(2), 1,
                    "Media quality clamps high")
        expectClose(MediaSupport.sanitizedFPS(90), 60,
                    "Media FPS clamps high")
        expectClose(MediaSupport.sanitizedFPS(-1), 12,
                    "Media FPS falls back when invalid")
        expect(MediaSupport.sanitizedPixelDimension(641, fallback: 1280) == 640,
               "Media pixel dimensions stay even")
        expect(MediaSupport.scaledEvenSize(source: CGSize(width: 1920, height: 1080), maxDimension: 1000)
               == CGSize(width: 1000, height: 562),
               "Media scaling keeps aspect ratio with even dimensions")
        expect(MediaSupport.scaledVideoSize(source: CGSize(width: 320, height: 180), maxDimension: 180)
               == CGSize(width: 176, height: 96),
               "Media video scaling uses encoder-friendly dimensions")
        let mediaInput = URL(fileURLWithPath: "/tmp/Clip.mov")
        expect(MediaSupport.outputURL(for: mediaInput, suffix: "-compressed", fileExtension: "mp4").path
               == "/tmp/Clip-compressed.mp4",
               "Media output names keep clear suffixes")
        expect(MediaSupport.recognitionLanguages(for: "pt-BR") == ["pt-BR", "en-US"],
               "Media OCR language defaults include the app language and English")
        expectClose(Defaults.sanitizedAppVolume(1.5), 1.5, "valid app volume is preserved")
        expectClose(Defaults.sanitizedAppVolume(3), 2, "high app volume clamps to boost maximum")
        expectClose(Defaults.sanitizedAppVolume(-1), 0, "negative app volume clamps to mute")
        expectClose(Defaults.sanitizedAppVolume(.infinity), 1, "non-finite app volume falls back to unity")
        expect(Defaults.sanitizedAppOutputDeviceUID(" BuiltInSpeakerDevice ") == "BuiltInSpeakerDevice",
               "audio output device UIDs are trimmed")
        expect(Defaults.sanitizedAppOutputDeviceUID("") == nil,
               "empty audio output device UIDs are ignored")
        expect(Defaults.sanitizedAppOutputDeviceUID("bad\nuid") == nil,
               "control characters are rejected from audio output device UIDs")
        expect(Defaults.sanitizedPreferredInputDeviceUID(" BuiltInMicrophoneDevice ") == "BuiltInMicrophoneDevice",
               "audio input device UIDs are trimmed")
        expect(Defaults.sanitizedPreferredInputDeviceUID("") == nil,
               "empty audio input device UIDs are ignored")
        let savedRoutes = Defaults.sanitizedAppOutputDevices([
            "com.apple.Safari": "BuiltInSpeakerDevice",
            "bad\napp": "ExternalDisplay",
            "com.example.Empty": "",
        ])
        expect(savedRoutes == ["com.apple.Safari": "BuiltInSpeakerDevice"],
               "app output device routes keep only valid app and device ids")
        let savedMixerVolumes = ["com.apple.Safari": 0.35, "com.apple.Music": 1.4]
        let successfulUniversalOutput = MixerRoutingSupport.preferencesAfterUniversalOutputSwitch(
            outputDeviceUIDs: savedRoutes,
            volumes: savedMixerVolumes,
            switchSucceeded: true)
        expect(successfulUniversalOutput.outputDeviceUIDs.isEmpty,
               "universal output clears per-app routes after a successful switch")
        expect(successfulUniversalOutput.volumes == savedMixerVolumes,
               "universal output preserves saved app volumes")
        let failedUniversalOutput = MixerRoutingSupport.preferencesAfterUniversalOutputSwitch(
            outputDeviceUIDs: savedRoutes,
            volumes: savedMixerVolumes,
            switchSucceeded: false)
        expect(failedUniversalOutput.outputDeviceUIDs == savedRoutes,
               "failed universal output keeps per-app routes")
        expect(failedUniversalOutput.volumes == savedMixerVolumes,
               "failed universal output keeps saved app volumes")
        expect(!MixerRoutingSupport.requiresEngine(volume: 1,
                                                   selectedOutputDeviceUID: nil,
                                                   targetOutputDeviceUID: "BuiltInSpeakerDevice",
                                                   defaultOutputDeviceUID: "BuiltInSpeakerDevice"),
               "default output at 100 percent stays passthrough")
        expect(MixerRoutingSupport.requiresEngine(volume: 0.5,
                                                  selectedOutputDeviceUID: nil,
                                                  targetOutputDeviceUID: "BuiltInSpeakerDevice",
                                                  defaultOutputDeviceUID: "BuiltInSpeakerDevice"),
               "default output with changed volume uses an engine")
        expect(MixerRoutingSupport.requiresEngine(volume: 1,
                                                  selectedOutputDeviceUID: "ExternalDisplay",
                                                  targetOutputDeviceUID: "ExternalDisplay",
                                                  defaultOutputDeviceUID: "BuiltInSpeakerDevice"),
               "specific non-default output at 100 percent uses an engine")
        expect(MixerRoutingSupport.effectiveDeviceUID(selectedUID: "ExternalDisplay",
                                                      availableUIDs: ["BuiltInSpeakerDevice"],
                                                      defaultUID: "BuiltInSpeakerDevice") == "BuiltInSpeakerDevice",
               "missing saved output falls back to default")
        expect(MixerRoutingSupport.selectedDeviceUnavailable(selectedUID: "ExternalDisplay",
                                                             availableUIDs: ["BuiltInSpeakerDevice"]),
               "missing saved output is marked unavailable without deleting the preference")
        let defaultInput = MixerRoutingSupport.resolveInputDevice(
            preferredUID: nil,
            availableUIDs: ["BuiltInMicrophoneDevice"],
            currentUID: "BuiltInMicrophoneDevice")
        expect(defaultInput == MixerInputRouteResolution(effectiveUID: "BuiltInMicrophoneDevice",
                                                         selectedUnavailable: false,
                                                         shouldApplyPreferred: false),
               "no preferred input follows the current system input")
        let connectedPreferredInput = MixerRoutingSupport.resolveInputDevice(
            preferredUID: "StudioMic",
            availableUIDs: ["BuiltInMicrophoneDevice", "StudioMic"],
            currentUID: "BuiltInMicrophoneDevice")
        expect(connectedPreferredInput == MixerInputRouteResolution(effectiveUID: "StudioMic",
                                                                    selectedUnavailable: false,
                                                                    shouldApplyPreferred: true),
               "connected preferred input is applied when different from current")
        let alreadyCurrentInput = MixerRoutingSupport.resolveInputDevice(
            preferredUID: "StudioMic",
            availableUIDs: ["BuiltInMicrophoneDevice", "StudioMic"],
            currentUID: "StudioMic")
        expect(!alreadyCurrentInput.shouldApplyPreferred,
               "preferred input is not reapplied when already current")
        let disconnectedPreferredInput = MixerRoutingSupport.resolveInputDevice(
            preferredUID: "StudioMic",
            availableUIDs: ["BuiltInMicrophoneDevice"],
            currentUID: "BuiltInMicrophoneDevice")
        expect(disconnectedPreferredInput == MixerInputRouteResolution(effectiveUID: "BuiltInMicrophoneDevice",
                                                                       selectedUnavailable: true,
                                                                       shouldApplyPreferred: false),
               "missing preferred input falls back visually without deleting preference")

        // MARK: Dock Preview helpers

        let dockPrefs = DockPreviewPreferences.sanitized(orientation: "left",
                                                         autohide: true,
                                                         tileSize: 81,
                                                         magnification: false)
        expect(dockPrefs == DockPreviewPreferences(orientation: .left,
                                                   autohide: true,
                                                   tileSize: 81,
                                                   magnification: false),
               "Dock Preview preferences preserve valid Dock values")
        let fallbackDockPrefs = DockPreviewPreferences.sanitized(orientation: "bad",
                                                                 autohide: nil,
                                                                 tileSize: 999,
                                                                 magnification: nil)
        expect(fallbackDockPrefs == DockPreviewPreferences(orientation: .bottom,
                                                           autohide: false,
                                                           tileSize: 256,
                                                           magnification: false),
               "Dock Preview preferences sanitize missing and out-of-range values")
        expect(DockPreviewSupport.availability(enabled: false,
                                               hasAccessibility: true,
                                               hasScreenRecording: true,
                                               preferences: dockPrefs)
               == DockPreviewAvailability(canRun: false, blockedReason: nil),
               "disabled Dock Preview does not report an error")
        expect(DockPreviewSupport.availability(enabled: true,
                                               hasAccessibility: false,
                                               hasScreenRecording: true,
                                               preferences: dockPrefs).blockedReason == .missingAccessibility,
               "Dock Preview requires Accessibility")
        expect(DockPreviewSupport.availability(enabled: true,
                                               hasAccessibility: true,
                                               hasScreenRecording: false,
                                               preferences: dockPrefs).blockedReason == .missingScreenRecording,
               "Dock Preview requires Screen Recording")
        let magnifiedPrefs = DockPreviewPreferences(orientation: .bottom,
                                                    autohide: false,
                                                    tileSize: 64,
                                                    magnification: true)
        expect(DockPreviewSupport.availability(enabled: true,
                                               hasAccessibility: true,
                                               hasScreenRecording: true,
                                               preferences: magnifiedPrefs).blockedReason == .magnification,
               "Dock Preview blocks Dock magnification")
        expect(DockPreviewSupport.availability(enabled: true,
                                               hasAccessibility: true,
                                               hasScreenRecording: true,
                                               preferences: dockPrefs).canRun,
               "Dock Preview can run when enabled, permitted and not magnified")

        let screen = CGRect(x: 0, y: 0, width: 1440, height: 900)
        let iconBottom = CGRect(x: 660, y: 0, width: 80, height: 80)
        let panelSize = CGSize(width: 400, height: 160)
        let bottomFrame = DockPreviewSupport.panelFrame(anchor: iconBottom,
                                                        panelSize: panelSize,
                                                        screenVisibleFrame: screen,
                                                        orientation: .bottom)
        expectClose(Double(bottomFrame.midX), Double(iconBottom.midX), "Dock Preview bottom panel centers on icon")
        expect(bottomFrame.minY > iconBottom.maxY,
               "Dock Preview bottom panel sits above the Dock icon")
        let leftFrame = DockPreviewSupport.panelFrame(anchor: CGRect(x: 0, y: 380, width: 80, height: 80),
                                                      panelSize: panelSize,
                                                      screenVisibleFrame: screen,
                                                      orientation: .left)
        expect(leftFrame.minX > 80,
               "Dock Preview left panel sits to the right of the Dock")
        let rightFrame = DockPreviewSupport.panelFrame(anchor: CGRect(x: 1360, y: 380, width: 80, height: 80),
                                                       panelSize: panelSize,
                                                       screenVisibleFrame: screen,
                                                       orientation: .right)
        expect(rightFrame.maxX < 1360,
               "Dock Preview right panel sits to the left of the Dock")
        let corridor = DockPreviewSupport.hoverCorridor(iconFrame: iconBottom,
                                                        panelFrame: bottomFrame,
                                                        orientation: .bottom)
        expect(corridor.contains(CGPoint(x: iconBottom.midX, y: (iconBottom.maxY + bottomFrame.minY) / 2)),
               "Dock Preview corridor keeps the path from Dock icon to panel alive")
        // A neighbouring Dock icon, one tile to the side, must fall OUTSIDE the
        // corridor; otherwise returning to the Dock can never hand the session to
        // another app and the panel stays stuck on the previous one.
        let neighborIcon = CGRect(x: iconBottom.maxX + 8, y: 0, width: 80, height: 80)
        expect(!corridor.contains(CGPoint(x: neighborIcon.midX, y: neighborIcon.midY)),
               "Dock Preview corridor excludes the neighbouring Dock icon so app switching works")
        expect(DockPreviewSupport.shouldRestoreOnEnd(committed: false),
               "Dock Preview restores the previous window when cancelled")
        expect(!DockPreviewSupport.shouldRestoreOnEnd(committed: true),
               "Dock Preview does not restore after a confirmed click")
        expect(DockPreviewSupport.dockProximityBand(tileSize: 64) >= 160,
               "Dock proximity band covers a default-size Dock")
        expect(DockPreviewSupport.dockProximityBand(tileSize: 200)
               > DockPreviewSupport.dockProximityBand(tileSize: 64),
               "Dock proximity band grows with the Dock tile size")
        let onePreviewSize = DockPreviewSupport.panelSize(itemCount: 1, screenVisibleFrame: screen)
        let twoPreviewSize = DockPreviewSupport.panelSize(itemCount: 2, screenVisibleFrame: screen)
        expect(twoPreviewSize.width > onePreviewSize.width,
               "Dock Preview panel size shrinks when a card is removed")
        let closeMiddle = DockPreviewSupport.closeState(afterRemoving: 22,
                                                        windowIDs: [11, 22, 33],
                                                        selectedWindowID: 22,
                                                        activePeekWindowID: 22,
                                                        desiredWindowID: 22)
        expect(closeMiddle.remainingWindowIDs == [11, 33],
               "Dock Preview close removes only the closed window")
        expect(closeMiddle.selectedWindowID == nil
               && closeMiddle.activePeekWindowID == nil
               && closeMiddle.desiredWindowID == nil,
               "Dock Preview close clears selection and peek for the closed window")
        expect(!closeMiddle.shouldEndSession,
               "Dock Preview close keeps the panel open when other windows remain")
        let closeUnselected = DockPreviewSupport.closeState(afterRemoving: 22,
                                                            windowIDs: [11, 22, 33],
                                                            selectedWindowID: 11,
                                                            activePeekWindowID: 33,
                                                            desiredWindowID: 33)
        expect(closeUnselected.selectedWindowID == 11
               && closeUnselected.activePeekWindowID == 33
               && closeUnselected.desiredWindowID == 33,
               "Dock Preview close preserves selection and peek for other windows")
        let closeLast = DockPreviewSupport.closeState(afterRemoving: 44,
                                                      windowIDs: [44],
                                                      selectedWindowID: 44,
                                                      activePeekWindowID: nil,
                                                      desiredWindowID: nil)
        expect(closeLast.shouldEndSession && closeLast.remainingWindowIDs.isEmpty,
               "Dock Preview close ends the panel when the last window is removed")
        // MARK: Release notes parsing

        let changelog = """
        # Changelog

        ## [2.17.2] - 2026-06-17

        ### Fixed
        - **Shelf** no longer shows an extra outline.
        - The update window opens centered
          on the visible screen.

        ### Added
        - Coffee shortcut in the menu panel.
        ![Menu bar temperature metrics](Resources/Images/menu-bar-temperature-metrics.png)

        ### Website
        - Official site: [vorssaint.com](https://vorssaint.com).

        ## [2.17.1] - 2026-06-17

        ### Fixed
        - Older release note.
        """
        let notes = ReleaseNotes.notes(for: "2.17.2", changelog: changelog)
        expect(notes.version == "2.17.2", "release notes version is parsed")
        expect(notes.date == "2026-06-17", "release notes date is parsed")
        expect(notes.sections.count == 2, "release notes keep sections for the requested version")
        expect(notes.sections.first?.title == "Fixed", "release notes first section title is parsed")
        expect(notes.sections.first?.bulletItems.first == "Shelf no longer shows an extra outline.",
               "release notes strip simple markdown emphasis")
        expect(notes.sections.first?.bulletItems.dropFirst().first == "The update window opens centered on the visible screen.",
               "release notes join continuation lines")
        expect(notes.sections.last?.bulletItems == ["Coffee shortcut in the menu panel."],
               "release notes stop before the next version")
        expect(notes.sections.last?.items.last == .image(ReleaseNoteImage(alt: "Menu bar temperature metrics",
                                                                          path: "Resources/Images/menu-bar-temperature-metrics.png")),
               "release notes parse changelog images")
        expect(!notes.sections.contains(where: { $0.title == "Website" }),
               "release notes hide website sections from the feature list")

        // MARK: URL cleaning

        expectEqual(URLCleaning.cleanedString(from: "https://example.com/path?utm_source=news&id=42&fbclid=abc") ?? "",
                    "https://example.com/path?id=42",
                    "URL cleaner removes tracking and preserves useful query")
        expectEqual(URLCleaning.cleanedString(from: " https://example.com/?GCLID=one&utm_campaign=x#section ") ?? "",
                    "https://example.com/#section",
                    "URL cleaner is case-insensitive and preserves fragments")
        expectEqual(URLCleaning.cleanedString(from: "https://example.com/?id=42") ?? "",
                    "https://example.com/?id=42",
                    "URL cleaner leaves clean URLs alone")
        expect(URLCleaning.cleanedString(from: "not a url") == nil,
               "URL cleaner rejects plain text")

        // MARK: Homebrew command building and parsing

        expect(HomebrewPackageKind.allCases == [.cask, .formula],
               "Homebrew package kinds keep casks before formulae")
        expect(HomebrewCommandBuilder.isValidToken("jq"), "simple Homebrew token is valid")
        expect(HomebrewCommandBuilder.isValidToken("python@3.14"), "versioned formula token is valid")
        expect(HomebrewCommandBuilder.isValidToken("visual-studio-code"), "cask token is valid")
        expect(HomebrewCommandBuilder.isValidToken("homebrew/cask-fonts/font-iosevka"), "tapped token is valid")
        expect(!HomebrewCommandBuilder.isValidToken(""), "empty Homebrew token is invalid")
        expect(!HomebrewCommandBuilder.isValidToken("-bad"), "leading dash Homebrew token is invalid")
        expect(!HomebrewCommandBuilder.isValidToken("../bad"), "path traversal Homebrew token is invalid")
        expect(!HomebrewCommandBuilder.isValidToken("bad token"), "spaced Homebrew token is invalid")

        let brewPath = "/opt/homebrew/bin/brew"
        let cask = HomebrewPackage(kind: .cask, name: "visual-studio-code",
                                   displayName: "Visual Studio Code", desc: nil,
                                   installedVersion: nil, stableVersion: nil, homepage: nil)
        expect(HomebrewCommandBuilder.search(brewPath: brewPath, kind: .formula, query: "jq").arguments
               == ["search", "--formula", "jq"],
               "formula search command uses separated arguments")
        expect(HomebrewCommandBuilder.install(brewPath: brewPath, package: cask).arguments
               == ["install", "--cask", "visual-studio-code"],
               "cask install command uses --cask")
        expect(HomebrewCommandBuilder.uninstall(brewPath: brewPath, package: cask).arguments
               == ["uninstall", "--cask", "visual-studio-code"],
               "cask uninstall command uses --cask")
        expect(HomebrewCommandBuilder.needsTerminalFallback(output: "sudo: a terminal is required to read the password"),
               "sudo terminal error triggers Homebrew terminal fallback")
        expect(HomebrewCommandBuilder.installerCommand == #"/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)""#,
               "Homebrew installer command matches the official install script entrypoint")
        expectEqual(HomebrewCommandBuilder.shellProfilePath(homeDirectory: "/Users/test", shellPath: "/bin/zsh"),
                    "/Users/test/.zprofile",
                    "Homebrew shell setup uses zprofile for zsh")
        expectEqual(HomebrewCommandBuilder.shellProfilePath(homeDirectory: "/Users/test", shellPath: "/bin/bash"),
                    "/Users/test/.bash_profile",
                    "Homebrew shell setup uses bash_profile for bash")
        expectEqual(HomebrewCommandBuilder.shellEnvLine(brewPath: brewPath),
                    #"eval "$(/opt/homebrew/bin/brew shellenv)""#,
                    "Homebrew shell setup line uses brew shellenv")
        expectEqual(HomebrewAnalytics.url(kind: .formula).absoluteString,
                    "https://formulae.brew.sh/api/analytics/install-on-request/homebrew-core/30d.json",
                    "Homebrew formula popularity uses install-on-request analytics")
        expectEqual(HomebrewAnalytics.url(kind: .cask).absoluteString,
                    "https://formulae.brew.sh/api/analytics/cask-install/homebrew-cask/30d.json",
                    "Homebrew cask popularity uses cask install analytics")
        expectEqual(HomebrewAnalytics.compactCount(999), "999", "Homebrew popularity under 1K stays plain")
        expectEqual(HomebrewAnalytics.compactCount(1_250), "1.2K", "Homebrew popularity compacts thousands")
        expectEqual(HomebrewAnalytics.compactCount(1_200_000), "1.2M", "Homebrew popularity compacts millions")
        let shellSetupCommand = HomebrewCommandBuilder.shellConfigCommand(brewPath: brewPath,
                                                                          homeDirectory: "/Users/test",
                                                                          shellPath: "/bin/zsh")
        expect(shellSetupCommand.contains("PROFILE=/Users/test/.zprofile"),
               "Homebrew shell setup command targets the detected profile")
        expect(shellSetupCommand.contains(#"grep -qxF "$LINE""#),
               "Homebrew shell setup command avoids duplicate profile lines")
        expectClose(HomebrewProgressParser.progressFraction(in: "######## 42.5%") ?? -1,
                    0.425,
                    "Homebrew progress parser reads percentage output")
        expect(HomebrewProgressParser.phase(in: "==> Downloading https://example.com/file",
                                            action: .install) == .downloading,
               "Homebrew progress parser detects downloads")
        expect(HomebrewProgressParser.phase(in: "==> Installing Cask google-chrome",
                                            action: .install) == .installing,
               "Homebrew progress parser detects installs")
        expect(HomebrewProgressParser.phase(in: "==> Uninstalling Cask google-chrome",
                                            action: .uninstall) == .uninstalling,
               "Homebrew progress parser detects uninstalls")
        expect(HomebrewProgressParser.activity(in: "\u{001B}[32m==> Moving App 'Chrome.app'\u{001B}[0m")
               == "Moving App 'Chrome.app'",
               "Homebrew progress parser cleans activity lines")
        expect(HomebrewProgressParser.visibleError(from: "$ brew install x\nError: Cask failed")
               == "Error: Cask failed",
               "Homebrew progress parser hides command lines from visible errors")

        let homebrewJSON = """
        {
          "formulae": [
            {
              "name": "jq",
              "full_name": "jq",
              "desc": "Command-line JSON processor",
              "homepage": "https://jqlang.github.io/jq/",
              "versions": { "stable": "1.8.1" },
              "installed": [{ "version": "1.8.1" }]
            }
          ],
          "casks": [
            {
              "token": "visual-studio-code",
              "name": ["Visual Studio Code"],
              "desc": "Code editor",
              "homepage": "https://code.visualstudio.com/",
              "version": "1.108.1",
              "installed": "1.107.0"
            }
          ]
        }
        """
        let homebrewPackages = (try? HomebrewParser.parseInfoJSON(Data(homebrewJSON.utf8))) ?? []
        expect(homebrewPackages.count == 2, "Homebrew JSON parser keeps formulae and casks")
        expect(homebrewPackages.first?.kind == .cask,
               "Homebrew JSON parser sorts casks before formulae")
        expect(homebrewPackages.first(where: { $0.name == "jq" })?.installedVersion == "1.8.1",
               "Homebrew parser reads installed formula version")
        expect(homebrewPackages.first(where: { $0.name == "visual-studio-code" })?.displayName == "Visual Studio Code",
               "Homebrew parser reads cask display name")
        let searchPackages = HomebrewParser.parseSearchOutput("jq\nbad token\nwget\nvisual-studio-code\n",
                                                              kind: .formula,
                                                              installed: homebrewPackages)
        expect(searchPackages.map(\.name) == ["jq", "wget", "visual-studio-code"],
               "Homebrew search parser keeps valid one-token results")
        let analyticsJSON = """
        {
          "category": "formula_install_on_request",
          "formulae": {
            "jq": [
              { "formula": "jq", "count": "21,557" },
              { "formula": "jq --HEAD", "count": "30" }
            ],
            "wget": [
              { "formula": "wget", "count": "42,001" }
            ]
          }
        }
        """
        let popularity = (try? HomebrewAnalytics.parse(Data(analyticsJSON.utf8), kind: .formula)) ?? [:]
        expect(popularity["jq"]?.count == 21_557,
               "Homebrew analytics parser prefers the exact formula count")
        expect(popularity["wget"]?.rank == 1,
               "Homebrew analytics parser ranks by count")
        let rankedPackages = HomebrewAnalytics.enrichAndSort(searchPackages, popularity: popularity)
        expect(rankedPackages.map(\.name) == ["wget", "jq", "visual-studio-code"],
               "Homebrew search results sort by popularity first")
        expect(rankedPackages.first?.popularity?.compactCount == "42K",
               "Homebrew search results keep compact popularity")

        // MARK: Localization format contracts

        let localizedStrings: [(AppLanguage, Strings)] = [
            (.enUS, .enUS),
            (.ptBR, .ptBR),
            (.es, .es),
            (.de, .de),
            (.fr, .fr),
            (.it, .it),
            (.ja, .ja),
            (.zhHans, .zhHans),
        ]
        expect(localizedStrings.count == AppLanguage.allCases.count, "all app languages are covered by tests")
        for (language, strings) in localizedStrings {
            let prefix = "localization \(language.rawValue)"
            expectFormat(strings.cutMovedPluralFormat, ["d"], "\(prefix) cut plural format")
            expectFormat(strings.uninstallerSelectedFormat, ["d", "d"], "\(prefix) uninstaller selected format")
            expectFormat(strings.uninstallerFreedFormat, ["@"], "\(prefix) uninstaller freed format")
            expectFormat(strings.shelfSelectedFormat, ["d"], "\(prefix) shelf selection format")
            expectFormat(strings.powerAdapterMaxFormat, ["@"], "\(prefix) adapter max format")
            expectFormat(strings.mixerInputErrorFormat, ["@"], "\(prefix) mixer input error format")
            expectFormat(strings.homebrewConfirmInstallBodyFormat, ["@"], "\(prefix) Homebrew install format")
            expectFormat(strings.homebrewConfirmUninstallBodyFormat, ["@"], "\(prefix) Homebrew uninstall format")
            expectFormat(strings.homebrewPopularityFormat, ["@", "@"], "\(prefix) Homebrew popularity format")
            expectFormat(strings.homebrewOperationInstallFormat, ["@"], "\(prefix) Homebrew operation install format")
            expectFormat(strings.homebrewOperationUninstallFormat, ["@"], "\(prefix) Homebrew operation uninstall format")
            expectFormat(strings.homebrewOperationInstalledFormat, ["@"], "\(prefix) Homebrew operation installed format")
            expectFormat(strings.homebrewOperationUninstalledFormat, ["@"], "\(prefix) Homebrew operation uninstalled format")
            expectFormat(strings.homebrewOperationFailedFormat, ["@"], "\(prefix) Homebrew operation failed format")
            expectFormat(strings.homebrewOperationElapsedFormat, ["@"], "\(prefix) Homebrew operation elapsed format")

            let rendered = [
                String(format: strings.cutMovedPluralFormat, 2),
                String(format: strings.uninstallerSelectedFormat, 1, 3),
                String(format: strings.uninstallerFreedFormat, "1 MB"),
                String(format: strings.shelfSelectedFormat, 2),
                String(format: strings.powerAdapterMaxFormat, "30 W"),
                String(format: strings.mixerInputErrorFormat, "OSStatus -1"),
                String(format: strings.homebrewConfirmInstallBodyFormat, "jq"),
                String(format: strings.homebrewConfirmUninstallBodyFormat, "jq"),
                String(format: strings.homebrewPopularityFormat, "1,234", "30"),
                String(format: strings.homebrewOperationInstallFormat, "jq"),
                String(format: strings.homebrewOperationUninstallFormat, "jq"),
                String(format: strings.homebrewOperationInstalledFormat, "jq"),
                String(format: strings.homebrewOperationUninstalledFormat, "jq"),
                String(format: strings.homebrewOperationFailedFormat, "jq"),
                String(format: strings.homebrewOperationElapsedFormat, "10s"),
            ]
            for value in rendered {
                expect(!value.isEmpty && !value.contains("%"), "\(prefix) renders format strings")
            }
        }

        // MARK: Network speed math

        let slow = NetworkCounters(received: 1000, sent: 500)
        let fast = NetworkCounters(received: 1000 + 2048, sent: 500 + 1024)
        let speed = MetricFormat.netSpeed(previous: slow, current: fast, elapsed: 2)
        expectClose(speed.down, 1024, "down speed over 2s")
        expectClose(speed.up, 512, "up speed over 2s")

        let zeroElapsed = MetricFormat.netSpeed(previous: slow, current: fast, elapsed: 0)
        expect(zeroElapsed.down == 0 && zeroElapsed.up == 0, "zero elapsed yields zero")

        // Counter reset (interface went down) must not produce a negative/huge spike.
        let afterReset = MetricFormat.netSpeed(previous: fast, current: slow, elapsed: 2)
        expect(afterReset.down == 0 && afterReset.up == 0, "counter reset yields zero")

        // MARK: Interface filtering

        expect(MetricFormat.includeNetworkInterface("en0"), "en0 included")
        expect(MetricFormat.includeNetworkInterface("en12"), "en12 included")
        expect(!MetricFormat.includeNetworkInterface("lo0"), "lo0 excluded")
        expect(!MetricFormat.includeNetworkInterface("awdl0"), "awdl0 excluded")
        expect(!MetricFormat.includeNetworkInterface("nan0"), "nan0 excluded")
        expect(!MetricFormat.includeNetworkInterface("utun3"), "utun3 (VPN) excluded")
        expect(!MetricFormat.includeNetworkInterface("bridge0"), "bridge0 excluded")
        expect(!MetricFormat.includeNetworkInterface(""), "empty excluded")

        // MARK: History ring buffer

        var history = MetricHistory(capacity: 3)
        history.push(1)
        history.push(2)
        expect(history.values == [1, 2], "history keeps order under capacity")
        history.push(3)
        history.push(4)
        expect(history.values == [2, 3, 4], "history drops oldest at capacity")
        expect(history.values.count == 3, "history never exceeds capacity")

        var single = MetricHistory(capacity: 1)
        single.push(5)
        single.push(6)
        expect(single.values == [6], "capacity 1 keeps only newest")

        // MARK: Cleaning-mode unlock gesture

        // Five deliberate taps of the same key unlock, on the fifth.
        var taps = CleaningUnlockCounter(threshold: 5, pressWindow: 2.0)
        var tapUnlock = false
        for (i, t) in [0.0, 0.3, 0.6, 0.9, 1.2].enumerated() {
            tapUnlock = taps.registerKeyDown(code: 0, time: t, isRepeat: false)
            if i < 4 { expect(!tapUnlock, "no unlock before the fifth tap (\(i + 1))") }
        }
        expect(tapUnlock, "five same-key taps unlock")
        expect(taps.progress == 5, "progress reaches the threshold")

        // Wiping the keyboard hits many different keys: it must never unlock.
        var wipe = CleaningUnlockCounter(threshold: 5, pressWindow: 2.0)
        var wipeUnlock = false
        for (i, code) in [Int64(10), 11, 12, 13, 14, 15, 16, 17].enumerated() {
            if wipe.registerKeyDown(code: code, time: Double(i) * 0.1, isRepeat: false) { wipeUnlock = true }
        }
        expect(!wipeUnlock, "wiping different keys never unlocks")
        expect(wipe.progress == 1, "different keys keep progress at 1")

        // A different key mid-streak resets the count.
        var streak = CleaningUnlockCounter(threshold: 5, pressWindow: 2.0)
        _ = streak.registerKeyDown(code: 9, time: 0.0, isRepeat: false)
        _ = streak.registerKeyDown(code: 9, time: 0.2, isRepeat: false)
        _ = streak.registerKeyDown(code: 9, time: 0.4, isRepeat: false)
        _ = streak.registerKeyDown(code: 8, time: 0.6, isRepeat: false)
        expect(streak.progress == 1, "a different key mid-streak resets to 1")

        // Auto-repeat (holding a key) is ignored, so resting on a key can't unlock.
        var held = CleaningUnlockCounter(threshold: 5, pressWindow: 2.0)
        var heldUnlock = false
        for i in 0..<10 {
            if held.registerKeyDown(code: 7, time: Double(i) * 0.1, isRepeat: true) { heldUnlock = true }
        }
        expect(!heldUnlock, "auto-repeat never unlocks")
        expect(held.progress == 0, "auto-repeat does not advance progress")

        // A pause longer than the window restarts the count.
        var paused = CleaningUnlockCounter(threshold: 5, pressWindow: 2.0)
        _ = paused.registerKeyDown(code: 3, time: 0.0, isRepeat: false)
        _ = paused.registerKeyDown(code: 3, time: 0.5, isRepeat: false)
        expect(paused.progress == 2, "presses within the window accumulate")
        _ = paused.registerKeyDown(code: 3, time: 10.0, isRepeat: false)
        expect(paused.progress == 1, "a pause beyond the window restarts the count")

        // reset() clears everything.
        var cleared = CleaningUnlockCounter(threshold: 5, pressWindow: 2.0)
        _ = cleared.registerKeyDown(code: 1, time: 0.0, isRepeat: false)
        _ = cleared.registerKeyDown(code: 1, time: 0.2, isRepeat: false)
        expect(cleared.progress == 2, "progress accumulates before reset")
        cleared.reset()
        expect(cleared.progress == 0, "reset clears progress")
        let afterReset2 = cleared.registerKeyDown(code: 1, time: 0.4, isRepeat: false)
        expect(!afterReset2 && cleared.progress == 1, "after reset the same key starts fresh at 1")

        // MARK: Result

        if failures.isEmpty {
            print("TESTS OK (\(checks) checks)")
            exit(0)
        } else {
            print("TESTS FAILED (\(failures.count) of \(checks)):")
            failures.forEach { print("  - \($0)") }
            exit(1)
        }
    }

    private static func formatSpecifiers(in format: String) -> [String] {
        var specifiers: [String] = []
        var index = format.startIndex
        while index < format.endIndex {
            guard format[index] == "%" else {
                index = format.index(after: index)
                continue
            }
            index = format.index(after: index)
            if index < format.endIndex, format[index] == "%" {
                index = format.index(after: index)
                continue
            }
            while index < format.endIndex {
                let character = format[index]
                if character.isLetter || character == "@" {
                    specifiers.append(String(character))
                    index = format.index(after: index)
                    break
                }
                index = format.index(after: index)
            }
        }
        return specifiers
    }

}
