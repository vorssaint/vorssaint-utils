// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Carbon.HIToolbox
import Foundation

enum FeatureCatalogTests {
    static func run(expect: (Bool, String) -> Void) {
        // MARK: Features hub catalog

        expect(AppFeature.allCases.count == 57, "feature catalog has 57 features")
        expect(Set(AppFeature.allCases.map(\.rawValue)).count == AppFeature.allCases.count,
               "feature ids are unique")
        expect(AppFeature.allCases.map(\.rawValue) == [
            "switcher", "dockPreview", "dockClick", "windowMaximizer", "windowLayout", "autoQuit",
            "scrollInverter", "focusFollowsMouse", "smoothScroll", "mouseAcceleration", "mouseNavigation", "mouseButtonShortcuts", "middleClick",
            "mouseClickDebounce", "keyboardDebounce", "textSnippets", "superKey", "quitWindowProtection",
            "clipboardHistory", "pastePlain", "finderCutPaste", "finderRename", "shelf", "urlCleaner",
            "diskImageInstaller",
            "mixer", "soundOutputSwitcher", "micMute", "musicBlock",
            "keepAwake", "brightness", "extraBrightness", "bluetoothSleep",
            "quickLauncher", "quickToggles", "colorPicker", "screenOCR", "cleaningMode", "mediaTools",
            "cleaner", "uninstaller", "homebrew", "appUpdates", "screenshot", "cameraPreview",
            "radialMenu", "scratchpad", "commandBar", "screenRecorder", "killProcess",
            "monitorCPU", "monitorGPU", "monitorMemory", "monitorNetwork", "monitorDisk", "monitorPower",
            "fanControl",
        ], "feature ids are stable (they persist inside availability keys)")
        expect(MouseAccelerationSupport.validatedRegistryID(nil) == nil
                && MouseAccelerationSupport.validatedRegistryID(0) == nil
                && MouseAccelerationSupport.validatedRegistryID(42) == 42,
               "mouse acceleration never turns a missing registry id into shared identity zero")
        let mouseIdentity = MouseAccelerationDeviceIdentity(
            vendorID: 1,
            productID: 2,
            locationID: 3,
            transport: "USB",
            physicalUniqueID: "physical",
            serialNumber: "serial"
        )
        let mouseRecovery = MouseAccelerationRecoveryEntry(
            registryID: 42,
            identity: mouseIdentity,
            key: MouseAccelerationSupport.mouseAccelerationKey,
            original: MouseAccelerationStoredValue(rawValue: 45_056, isBoolean: false)
        )
        var mouseJournal = MouseAccelerationRecoveryJournal(bootTime: 7, entries: [])
        mouseJournal.upsert(mouseRecovery)
        expect(mouseJournal.entry(registryID: 42, identity: mouseIdentity) == mouseRecovery,
               "mouse acceleration keeps one exact restorable value per live service")
        let reusedRegistryIdentity = MouseAccelerationDeviceIdentity(
            vendorID: 9,
            productID: 9,
            locationID: 9,
            transport: "USB",
            physicalUniqueID: nil,
            serialNumber: nil
        )
        expect(mouseJournal.entry(registryID: 42, identity: reusedRegistryIdentity) == nil,
               "a reused registry id can never receive another mouse's saved value")
        expect(mouseJournal.entriesToRestore(preserving: [42: mouseIdentity]).isEmpty
                && mouseJournal.entry(registryID: 42, identity: mouseIdentity) == mouseRecovery,
               "hotplug retries preserve a connected mouse's original value without restoring acceleration between attempts")
        expect(mouseJournal.entriesToRestore(preserving: [43: mouseIdentity]) == [mouseRecovery],
               "a reconnected mouse with a new registry id still needs recovery before recapture")
        expect(mouseJournal.entriesToRestore(preserving: [42: reusedRegistryIdentity]) == [mouseRecovery],
               "an unrelated mouse reusing a registry id cannot hide a pending recovery")
        expect(mouseJournal.entriesToRestore(preserving: [:]) == [mouseRecovery],
               "stopping acceleration control still restores every saved entry")

        var mouseReapplication = MouseAccelerationReapplySchedule()
        let initialMouseConnection = mouseReapplication.restart()
        expect(mouseReapplication.nextDelay(for: initialMouseConnection) == 0,
               "hotplug requests the first acceleration refresh without blocking the device callback")
        let reconnectedMouse = mouseReapplication.restart()
        expect(!mouseReapplication.isCurrent(initialMouseConnection)
                && mouseReapplication.nextDelay(for: initialMouseConnection) == nil,
               "a newer hotplug event invalidates the previous retry window")

        var mouseReapplyTime: TimeInterval = 0
        var mouseReapplyAttempts = 0
        var lateMouseValue: MouseAccelerationStoredValue?
        var lateMouseReset = false
        for _ in 0..<20 {
            guard let delay = mouseReapplication.nextDelay(for: reconnectedMouse) else { break }
            mouseReapplyTime += delay
            mouseReapplyAttempts += 1
            // The event-system service appears after the physical callback, then
            // receives the system's initial acceleration setting later still.
            if mouseReapplyTime >= 0.75, lateMouseValue == nil {
                lateMouseValue = mouseRecovery.original
            }
            if mouseReapplyTime >= 2, !lateMouseReset {
                lateMouseValue = mouseRecovery.original
                lateMouseReset = true
            }
            if lateMouseValue != nil {
                lateMouseValue = MouseAccelerationSupport.targetValue(
                    for: mouseRecovery.key, originalIsBoolean: mouseRecovery.original.isBoolean)
            }
        }
        expect(lateMouseReset && lateMouseValue?.rawValue == -1,
               "acceleration is reapplied when a mouse service and its settings arrive after the physical callback")
        expect(mouseReapplyAttempts > 1 && mouseReapplyAttempts < 20
                && mouseReapplyTime > 2 && mouseReapplyTime <= 5
                && !mouseReapplication.isCurrent(reconnectedMouse),
               "hotplug reapplication finishes within five seconds and leaves no idle retry")
        let cancelledMouseConnection = mouseReapplication.restart()
        _ = mouseReapplication.nextDelay(for: cancelledMouseConnection)
        mouseReapplication.cancel()
        expect(!mouseReapplication.isCurrent(cancelledMouseConnection)
                && mouseReapplication.nextDelay(for: cancelledMouseConnection) == nil,
               "turning the feature off or pausing the session invalidates queued acceleration writes")
        let resumedMouseConnection = mouseReapplication.restart()
        expect(mouseReapplication.nextDelay(for: resumedMouseConnection) == 0
                && !mouseReapplication.isCurrent(cancelledMouseConnection),
               "resuming creates a fresh retry window without reviving cancelled callbacks")
        expect(mouseIdentity.canMatchAcrossRegistryIDs,
               "a stable physical identity can recover after a device receives a new registry id")
        let anonymousMouseIdentity = MouseAccelerationDeviceIdentity(
            vendorID: nil,
            productID: nil,
            locationID: nil,
            transport: "USB",
            physicalUniqueID: nil,
            serialNumber: nil
        )
        expect(!anonymousMouseIdentity.canMatchAcrossRegistryIDs,
               "an anonymous device can never inherit another registry id's saved value")
        expect(MouseAccelerationSupport.isRestorableKey(MouseAccelerationSupport.linearScalingKey)
                && MouseAccelerationSupport.isRestorableKey(MouseAccelerationSupport.mouseAccelerationKey)
                && !MouseAccelerationSupport.isRestorableKey("UserKeyMapping"),
               "mouse acceleration recovery accepts only its own HID properties")
        expect(MouseAccelerationSupport.targetValue(
            for: MouseAccelerationSupport.linearScalingKey,
            originalIsBoolean: true
        ) == MouseAccelerationStoredValue(rawValue: 1, isBoolean: true)
            && MouseAccelerationSupport.targetValue(
                for: MouseAccelerationSupport.mouseAccelerationKey,
                originalIsBoolean: false
            ) == MouseAccelerationStoredValue(rawValue: -1, isBoolean: false),
               "mouse acceleration uses linear mode when supported and the legacy fallback otherwise")
        expect(AppFeature.switcher.availabilityKey == "featureAvailable.switcher",
               "availability key derives from the raw value")
        expect(AppFeature.availabilityDefaults.count == AppFeature.allCases.count
                && (AppFeature.availabilityDefaults[AppFeature.fanControl.availabilityKey] as? Bool) == false
                && (AppFeature.availabilityDefaults[AppFeature.diskImageInstaller.availabilityKey] as? Bool) == false
                && (AppFeature.availabilityDefaults[AppFeature.focusFollowsMouse.availabilityKey] as? Bool) == false
                && (AppFeature.availabilityDefaults[AppFeature.killProcess.availabilityKey] as? Bool) == false
                && AppFeature.allCases.filter {
                    $0 != .focusFollowsMouse && $0 != .fanControl && $0 != .diskImageInstaller
                        && $0 != .killProcess
                }.allSatisfy {
                    (AppFeature.availabilityDefaults[$0.availabilityKey] as? Bool) == true
                },
               "new opt-in features ship uninstalled while existing features remain available")
        expect(FeatureGroup.allCases.map { AppFeature.features(in: $0).count }.reduce(0, +)
                == AppFeature.allCases.count,
               "every feature belongs to exactly one group")
        expect(!FeatureGroup.allCases.contains { AppFeature.features(in: $0).isEmpty },
               "no hub group is empty")
        expect(AppPermission.allCases.map(\.rawValue) == [
            "accessibility", "screenRecording", "fullDiskAccess", "filesAndFolders", "notifications",
            "automationFinder", "automationTerminal", "audioCapture", "microphone", "camera",
            "appManagement",
        ], "permission portal contains every supported permission")
        let onboardingViewSource = (try? String(
            contentsOfFile: "Sources/Vorssaint/UI/Onboarding/OnboardingView.swift",
            encoding: .utf8)) ?? ""
        let additionalPermissionsAlignment =
            #"DisclosureGroup\(isExpanded: \$showingOtherPermissions\) \{\s+"#
            + #"VStack\(alignment: \.leading, spacing: 14\)"#
        expect(onboardingViewSource.range(
            of: additionalPermissionsAlignment,
            options: .regularExpression) != nil,
               "the additional onboarding permission rows share one leading edge")
        expect(FeaturePreset.essential.features.flatMap(\.onboardingPermissions).isEmpty,
               "the essential first-run choice asks for no broad permission")
        expect(Set(FeaturePreset.windows.features.flatMap(\.onboardingPermissions))
                == [.accessibility, .screenRecording],
               "the windows first-run choice explains exactly its two broad permissions")
        expect(AppFeature.screenshot.permissions == [.screenRecording]
                && AppFeature.screenshot.onboardingPermissions == [.screenRecording],
               "screenshots only need the screen recording grant")
        expect(AppFeature.screenRecorder.onboardingPermissions
                == [.screenRecording, .accessibility],
               "the recorder choice explains both permissions it needs")
        expect(AppFeature.cleaner.onboardingPermissions.isEmpty
                && AppFeature.cameraPreview.onboardingPermissions.isEmpty,
               "contextual grants are not requested during first setup")
        expect(AppFeature.fanControl.group == .monitor
                && AppFeature.fanControl.enabledKeys.isEmpty
                && AppFeature.fanControl.permissions.isEmpty
                && AppFeature.fanControl.energyProfile == .idle
                && AppFeature.fanControl.isBeta
                && !AppFeature.monitorPower.isBeta,
               "fan control is an on-demand beta with no broad permission")

        // MARK: Hardware-gated installs

        // Availability is only ever written by the runtime that gates it, so
        // a new install surface cannot walk around the hardware check the way
        // the hub's install-all button and the first-run picker once did.
        // Two files are allowed to write the key directly, and both run where
        // the gate cannot matter: the first-run seed writes a preset holding
        // no hardware-dependent feature (pinned below), and the fan control
        // migration restores an install that already existed, which the gate
        // never revokes. A third entry here is a bug, not a new allowance.
        var availabilityWriters: Set<String> = []
        if let sources = FileManager.default.enumerator(atPath: "Sources") {
            for case let path as String in sources where path.hasSuffix(".swift") {
                let text = (try? String(contentsOfFile: "Sources/" + path, encoding: .utf8)) ?? ""
                let writes = text.split(separator: "\n").contains {
                    $0.contains(".set(") && $0.contains("availabilityKey")
                }
                if writes { availabilityWriters.insert((path as NSString).lastPathComponent) }
            }
        }
        expect(availabilityWriters == ["FeatureRuntime.swift",
                                       "FeaturePresets.swift",
                                       "Defaults.swift"],
               "feature availability is written only where the hardware gate runs, "
               + "found \(availabilityWriters.sorted())")
        expect(FeaturePreset.allCases.allSatisfy { !$0.features.contains(.fanControl) },
               "no first-run preset installs a feature whose hardware the Mac may lack")

        let featureHubSource = (try? String(
            contentsOfFile: "Sources/Vorssaint/UI/Settings/FeatureHubSettings.swift",
            encoding: .utf8)) ?? ""
        let onboardingFeatureSource = (try? String(
            contentsOfFile: "Sources/Vorssaint/UI/Onboarding/OnboardingView.swift",
            encoding: .utf8)) ?? ""
        expect(featureHubSource.contains("installBlockedReason")
                && onboardingFeatureSource.contains("installBlockedReason"),
               "both feature pickers refuse an unsupported install from the same rule")
        expect(featureHubSource.contains("installableCount"),
               "the hub counts against what this Mac can install, so install-all can finish")
        expect(AppFeature.diskImageInstaller.group == .clipboardFiles
                && AppFeature.diskImageInstaller.enabledKeys.isEmpty
                && AppFeature.diskImageInstaller.permissions == [.appManagement]
                && AppFeature.diskImageInstaller.energyProfile == .idle,
               "the disk image installer is an event-driven file feature with contextual app access")
        expect(AppFeature.bluetoothSleep.group == .energyDisplay
                && AppFeature.bluetoothSleep.enabledKeys == [DefaultsKey.bluetoothSleepEnabled]
                && AppFeature.bluetoothSleep.permissions.isEmpty
                && AppFeature.bluetoothSleep.energyProfile == .idle
                && !AppFeature.bluetoothSleep.isBeta,
               "Bluetooth on sleep is an energy feature that costs nothing at rest")
        expect((AppFeature.availabilityDefaults[AppFeature.bluetoothSleep.availabilityKey] as? Bool) == true,
               "Bluetooth on sleep ships installed, switched off, so its section is findable")
        expect(AppFeature.bluetoothSleep.settingsDestination
                == FeatureSettingsDestination(.energy, sectionAnchor: .bluetoothSleep)
                && AppFeature.bluetoothSleep.settingsDestination.hasValidSectionAnchor
                && FeatureVisibilitySupport.features(for: .energy).contains(.bluetoothSleep),
               "Bluetooth on sleep owns a section of the Energy page and can keep it alive alone")
    }

    static func runPermissions(expect: (Bool, String) -> Void) {
        expect(PermissionPollingSupport.interval(visibleSurfaceCount: 0,
                                                 accessibilityIsNeeded: false,
                                                 screenRecordingIsNeeded: false,
                                                 accessibilityIsGranted: false,
                                                 screenRecordingIsGranted: false) == nil,
               "permissions keep no background timer without a live feature or visible surface")
        expect(PermissionPollingSupport.interval(visibleSurfaceCount: 1,
                                                 accessibilityIsNeeded: false,
                                                 screenRecordingIsNeeded: false,
                                                 accessibilityIsGranted: true,
                                                 screenRecordingIsGranted: true) == 2.5,
               "a visible permission surface refreshes grants promptly")
        expect(PermissionPollingSupport.interval(visibleSurfaceCount: 0,
                                                 accessibilityIsNeeded: true,
                                                 screenRecordingIsNeeded: false,
                                                 accessibilityIsGranted: false,
                                                 screenRecordingIsGranted: true) == 2.5,
               "a live feature waiting for its grant refreshes promptly")
        expect(PermissionPollingSupport.interval(visibleSurfaceCount: 0,
                                                 accessibilityIsNeeded: true,
                                                 screenRecordingIsNeeded: false,
                                                 accessibilityIsGranted: true,
                                                 screenRecordingIsGranted: true) == 60,
               "a granted live feature keeps only the slow revocation watch")
        let windowLayoutPollingKeys = [
            DefaultsKey.windowLayoutShortcutsEnabled,
            DefaultsKey.windowGestureEnabled,
            DefaultsKey.windowEdgeSnapEnabled,
        ]
        expect(!AppFeature.windowLayout.monitorsPermissionChanges(boolFor: { _ in false })
               && !AppFeature.windowLayout.monitorsPermissionChanges {
                   $0 == DefaultsKey.screenshotShortcutEnabled
               }
               && windowLayoutPollingKeys.allSatisfy { enabledKey in
                   AppFeature.windowLayout.monitorsPermissionChanges {
                       $0 == enabledKey
                   }
               }
               && !AppFeature.screenshot.monitorsPermissionChanges
               && !AppFeature.screenRecorder.monitorsPermissionChanges
               && AppFeature.switcher.monitorsPermissionChanges
               && AppFeature.focusFollowsMouse.monitorsPermissionChanges
               && AppFeature.mouseNavigation.monitorsPermissionChanges,
               "only active Window Layout hooks and live features keep the permission watcher alive")
        expect(!AppFeature.windowLayout.monitorsPermissionChanges(
                   edgeSnapDisabledZones: WindowEdgeSnapZone.disabledZonesStorageValue(
                       WindowEdgeSnapZone.allEnabled
                   ),
                   boolFor: { $0 == DefaultsKey.windowEdgeSnapEnabled }
               ),
               "Window Layout does not poll permissions when every snap zone is off")

        expect(activeSet(.accessibility)
                == [.windowLayout, .cleaningMode, .commandBar, .screenRecorder],
               "with nothing enabled only on-demand features use accessibility")
        expect(activeSet(.accessibility, on: [DefaultsKey.scrollInverterEnabled]).contains(.scrollInverter),
               "an enabled feature counts as using its permission")
        expect(activeSet(.accessibility, on: [DefaultsKey.scrollInverterHorizontalEnabled])
                .contains(.scrollInverter),
               "horizontal-only inversion counts as using accessibility")
        expect(AppFeature.scrollInverter.enabledKeys == [DefaultsKey.scrollInverterEnabled,
                                                          DefaultsKey.scrollInverterHorizontalEnabled],
               "the scroll direction feature tracks both independent axes")
        expect(activeSet(.accessibility, on: [DefaultsKey.focusFollowsMouseEnabled])
                .contains(.focusFollowsMouse),
               "focus follows mouse reports its live accessibility use")
        expect(activeSet(.accessibility, on: [DefaultsKey.mouseClickDebounceEnabled])
                .contains(.mouseClickDebounce)
                && AppFeature.mouseClickDebounce.enabledKeys
                    == [DefaultsKey.mouseClickDebounceEnabled]
                && AppFeature.mouseClickDebounce.permissions == [.accessibility]
                && AppFeature.mouseClickDebounce.group == .mouseKeyboard,
               "mouse click debounce reports its switch, permission and feature group")
        expect(activeSet(.accessibility, on: [DefaultsKey.finderRenameEnabled]).contains(.finderRename),
               "the enabled Finder rename shortcut uses accessibility")
        expect(!activeSet(.accessibility, available: [], on: [DefaultsKey.scrollInverterEnabled])
                .contains(.scrollInverter),
               "an unavailable feature never uses a permission")
        expect(activeSet(.accessibility, on: [DefaultsKey.keepAwakeMouseJiggleEnabled]).contains(.keepAwake),
               "keep awake uses accessibility only with the mouse jiggle on")
        expect(!activeSet(.accessibility).contains(.keepAwake),
               "keep awake without jiggle does not use accessibility")
        expect(activeSet(.accessibility, on: [DefaultsKey.brightnessControlEnabled,
                                              DefaultsKey.brightnessKeysEnabled]).contains(.brightness),
               "brightness uses accessibility only for the key option")
        expect(activeSet(.accessibility, on: [DefaultsKey.brightnessControlEnabled,
                                              DefaultsKey.brightnessOSDEnabled]).contains(.brightness),
               "brightness uses accessibility for the adjustment overlay")
        expect(!activeSet(.accessibility, on: [DefaultsKey.brightnessControlEnabled])
                .contains(.brightness),
               "brightness sliders alone never use accessibility")
        expect(activeSet(.accessibility).contains(.screenRecorder),
               "the recorder uses accessibility for anonymous typing timing while active")
        expect(activeSet(.accessibility, on: [DefaultsKey.preciseVolumeRollerEnabled]).contains(.mixer),
               "mixer uses accessibility only for precise volume roller")
        expect(!activeSet(.accessibility).contains(.mixer),
               "mixer without precise volume roller does not use accessibility")

        expect(activeSet(.screenRecording, on: [DefaultsKey.switcherEnabled])
                == [.switcher, .screenOCR, .screenshot, .screenRecorder],
               "switcher with previews uses screen recording; OCR, screenshots and recordings are on demand")
        expect(activeSet(.screenRecording,
                         on: [DefaultsKey.switcherEnabled, DefaultsKey.switcherSimpleMode])
                == [.screenOCR, .screenshot, .screenRecorder],
               "simple-mode switcher stops using screen recording")
        expect(activeSet(.screenRecording,
                         on: [DefaultsKey.switcherSimpleMode, DefaultsKey.dockPreviewEnabled])
                .contains(.dockPreview),
               "dock preview keeps screen recording in use regardless of switcher mode")
        expect(AppFeature.dockClick.enabledKeys == [DefaultsKey.dockClickMinimize,
                                                    DefaultsKey.dockClickHide,
                                                    DefaultsKey.dockClickCycleWindows],
               "the Dock click feature tracks every action that can keep its shared tap alive")

        expect(activeSet(.notifications) == [],
               "no alerts and no schedule means notifications are unused")
        expect(activeSet(.notifications, on: [DefaultsKey.monitorAlertCPUTemperature]) == [.monitorCPU],
               "a CPU temperature alert marks the CPU monitor as notifying")
        expect(activeSet(.notifications, on: [DefaultsKey.monitorAlertBatteryTemperature]) == [.monitorPower],
               "a battery temperature alert marks the power monitor as notifying")
        expect(activeSet(.notifications,
                         available: Set(AppFeature.allCases).subtracting([.monitorCPU]),
                         on: [DefaultsKey.monitorAlertCPU]) == [],
               "an alert whose metric is unavailable does not notify")
        expect(activeSet(.notifications, on: [DefaultsKey.cleanerScheduleNotify],
                         strings: [DefaultsKey.cleanerScheduleFrequency: "weekly"]) == [.cleaner],
               "a scheduled cleaner with notice enabled uses notifications")
        expect(activeSet(.notifications, on: [DefaultsKey.cleanerScheduleNotify],
                         strings: [DefaultsKey.cleanerScheduleFrequency: "off"]) == [],
               "an unscheduled cleaner does not use notifications")
        expect(activeSet(.notifications,
                         on: [DefaultsKey.whatsAppDownloadsAutomaticEnabled,
                              DefaultsKey.whatsAppDownloadsNotify]) == [],
               "WhatsApp cleanup notifications stay unused until that cleaner is turned on")
        expect(activeSet(.notifications,
                         on: [DefaultsKey.whatsAppDownloadsEnabled,
                              DefaultsKey.whatsAppDownloadsAutomaticEnabled,
                              DefaultsKey.whatsAppDownloadsNotify]) == [.cleaner],
               "WhatsApp cleanup only uses notifications for an opted-in automatic summary")
        expect(activeSet(.notifications,
                         on: [DefaultsKey.whatsAppOrganizerEnabled,
                              DefaultsKey.whatsAppDownloadsNotify]) == [],
               "the experimental WhatsApp organizer stays silent until that cleaner is turned on")
        expect(activeSet(.notifications,
                         on: [DefaultsKey.whatsAppDownloadsEnabled,
                              DefaultsKey.whatsAppOrganizerEnabled,
                              DefaultsKey.whatsAppDownloadsNotify]) == [.cleaner],
               "the experimental WhatsApp organizer can offer an undo notification")
        expect(activeSet(.filesAndFolders) == [],
               "WhatsApp Downloads folder access stays unused until that cleaner is turned on")
        expect(activeSet(.filesAndFolders, on: [DefaultsKey.whatsAppDownloadsEnabled]) == [.cleaner],
               "the cleaner owns WhatsApp Downloads folder access")

        expect(activeSet(.fullDiskAccess) == [.cleaner, .uninstaller],
               "cleaner and uninstaller are on-demand full disk users")
        expect(activeSet(.automationFinder, on: [DefaultsKey.finderCutPasteEnabled])
                == [.finderCutPaste, .uninstaller, .quickToggles],
               "finder automation is used by cut and paste, the uninstaller and the quick toggles")
        expect(activeSet(.automationFinder, on: [DefaultsKey.finderPasteImageAsFile])
                == [.finderCutPaste, .uninstaller, .quickToggles],
               "pasting copied images as files engages the shared Finder feature")
        expect(AppFeature.quickToggles.permissions == [.automationFinder],
               "the quick toggles need no permission beyond the Trash's Finder ask")
        expect(activeSet(.automationTerminal) == [.homebrew], "homebrew drives the Terminal")
        expect(activeSet(.appManagement) == [.homebrew, .appUpdates, .diskImageInstaller],
               "package, update and disk-image installs declare App Management access")
        expect(AppFeature.homebrew.permissions == [.automationTerminal, .appManagement],
               "the package manager declares both permissions used by its operations")
        expect(activeSet(.audioCapture) == [.mixer], "the mixer is the only audio capture user")
        expect(activeSet(.audioCapture, available: Set(AppFeature.allCases).subtracting([.mixer])) == [],
               "audio capture reads as unused once the mixer is off in the hub")
        expect(activeSet(.audioCapture, on: [DefaultsKey.recorderSystemAudio]) == [.mixer, .screenRecorder],
               "the recorder uses audio capture only while the Mac's sound is a chosen source")
        expect(activeSet(.microphone).isEmpty
                && activeSet(.microphone, on: [DefaultsKey.recorderMicrophone]) == [.screenRecorder],
               "the recorder uses microphone access only when that optional source is on")
        expect(activeSet(.camera) == [.cameraPreview],
               "the camera preview is the only on-demand camera user")
        expect(activeSet(.camera, available: Set(AppFeature.allCases).subtracting([.cameraPreview])) == [],
               "the camera reads as unused once the preview is off in the hub")
        expect(AppFeature.cameraPreview.permissions == [.camera]
                && AppFeature.cameraPreview.enabledKeys.isEmpty,
               "the camera preview works on demand and only ever asks for the camera")

        expect(!AppFeature.anyMonitorAlertEnabled(isAvailable: { _ in true }, boolFor: { _ in false }),
               "no alert keys means no monitor alerts")
        expect(AppFeature.anyMonitorAlertEnabled(isAvailable: { _ in true },
                                                 boolFor: { $0 == DefaultsKey.monitorAlertDisk }),
               "one alert on an available metric arms the alert service")
        expect(AppFeature.anyMonitorAlertEnabled(isAvailable: { _ in true },
                                                 boolFor: {
                                                     $0 == DefaultsKey.monitorAlertBatteryTemperature
                                                 }),
               "a battery temperature alert arms the alert service")
        expect(!AppFeature.anyMonitorAlertEnabled(isAvailable: { $0 != .monitorPower },
                                                  boolFor: {
                                                      $0 == DefaultsKey.monitorAlertBatteryTemperature
                                                  }),
               "a battery temperature alert stays disarmed without the power metric")
        expect(!AppFeature.anyMonitorAlertEnabled(isAvailable: { $0 != .monitorDisk },
                                                  boolFor: { $0 == DefaultsKey.monitorAlertDisk }),
               "an alert with its metric off in the hub stays disarmed")

        expect(GlobalShortcutRole.activeRoles(isOn: { _ in true }).count
                == GlobalShortcutRole.allCases.count,
               "the availability-free overload keeps every enabled current role")
        expect(!GlobalShortcutRole.activeRoles(isOn: { _ in true },
                                               isAvailable: { $0 != .shelf }).contains(.shelf),
               "a role leaves the shortcuts page when its feature is off in the hub")
        expect(GlobalShortcutRole.activeRoles(isOn: { _ in true },
                                              isAvailable: { $0 != .switcher })
                .allSatisfy { $0 != .switcher && $0 != .switcherWindow },
               "both switcher roles follow the switcher feature")
        expect(GlobalShortcutRole.availableRoles(isAvailable: { $0 != .switcher })
                .allSatisfy { $0 != .switcher && $0 != .switcherWindow },
               "the shortcut editor lists installed roles even without reading enable keys")
        expect(GlobalShortcutRole.keyboardBrightnessDecrease.feature == .brightness
                && GlobalShortcutRole.keyboardBrightnessIncrease.feature == .brightness
                && GlobalShortcutRole.keyboardBrightnessDecrease.group == .mouseKeyboard
                && GlobalShortcutRole.keyboardBrightnessIncrease.group == .mouseKeyboard,
               "keyboard brightness stays owned by the brightness service but appears with keyboard controls")
        expect(GlobalShortcutRole.keyboardBrightnessDecrease.requiredEnableKeys
                == [DefaultsKey.keyboardBrightnessShortcutsEnabled]
                && GlobalShortcutRole.keyboardBrightnessIncrease.requiredEnableKeys
                == [DefaultsKey.keyboardBrightnessShortcutsEnabled],
               "keyboard brightness shortcuts require explicit opt-in")
        expect(!GlobalShortcutRole.activeRoles(isOn: { _ in false })
                .contains(where: \.isKeyboardBrightness),
               "keyboard brightness shortcuts reserve no combination before opt-in")
        expect(!GlobalShortcutRole.activeRoles(isOn: { _ in true }, isAvailable: { $0 != .brightness })
                .contains(where: \.isKeyboardBrightness),
               "removing the brightness feature releases both keyboard shortcuts")

        let superSpace = GlobalShortcut(keyCode: Int64(kVK_Space), modifiers: .validMask)
        let customSuperSpace = GlobalShortcut(keyCode: Int64(kVK_Space),
                                              modifiers: [.control, .option, .command])
        expect(superSpace.superKeyAlternative(sourceLabel: "Right ⌘",
                                              superKeyModifiers: .validMask) == "Right ⌘ + Space"
                && customSuperSpace.superKeyAlternative(
                    sourceLabel: "Right ⌘",
                    superKeyModifiers: [.control, .option, .command]) == "Right ⌘ + Space"
                && GlobalShortcut.commandBarDefault.superKeyAlternative(
                    sourceLabel: "Right ⌘",
                    superKeyModifiers: [.control, .option, .command]) == nil,
               "the shortcut editor follows the configured Super key modifiers")

        // MARK: Super key held-key watchdog
        // The source key (F18) does not autorepeat, so a steadily-held key
        // reaches the watchdog just like a lost release. The physical key state
        // is what tells them apart.
        expect(SuperKeySupport.heldKeyWatchdogOutcome(physicalKeyDown: true, stateThinksHeld: true, tapAlive: true)
                == .reArm,
               "a key still physically down keeps the hold alive")
        expect(SuperKeySupport.heldKeyWatchdogOutcome(physicalKeyDown: false, stateThinksHeld: true, tapAlive: true)
                == .forget,
               "a key that has come up ends the hold (its release was missed)")
        expect(SuperKeySupport.heldKeyWatchdogOutcome(physicalKeyDown: true, stateThinksHeld: false, tapAlive: true)
                == .forget,
               "nothing to keep alive once the state is no longer held")
        expect(SuperKeySupport.heldKeyWatchdogOutcome(physicalKeyDown: true, stateThinksHeld: true, tapAlive: false)
                == .forget,
               "a torn-down tap cannot stamp modifiers, so the hold is dropped")
    }

    static func runPresetsAndStrings(expect: (Bool, String) -> Void) {
        for language in AppLanguage.allCases {
            let categoryValues = Mirror(reflecting: FeatureStrings.settingsCategories(language)).children
                .compactMap { $0.value as? String }
            expect(categoryValues.count == 6 && categoryValues.allSatisfy { !$0.isEmpty },
                   "every Settings category name is set for \(language.rawValue)")
            let superKeyValues = Mirror(reflecting: FeatureStrings.superKey(language)).children
                .compactMap { $0.value as? String }
            expect(superKeyValues.count == 20 && superKeyValues.allSatisfy { !$0.isEmpty },
                   "every super key string is set for \(language.rawValue)")
            let refusals = SuperKeyMappingFailure.allCases.map {
                FeatureStrings.superKey(language).mappingFailure($0)
            }
            expect(Set(refusals).count == SuperKeyMappingFailure.allCases.count
                    && refusals.allSatisfy { !$0.isEmpty },
                   "every reason the key mapping is refused reads differently (\(language.rawValue))")
            let superKeyStrings = FeatureStrings.superKey(language)
            expect(superKeyValues.allSatisfy { !$0.contains("—") }
                    && superKeyStrings.enableToggle != superKeyStrings.pageTitle
                    && superKeyStrings.rightKeyFormat.contains("%@")
                    && superKeyStrings.panelCaptionFormat.contains("%1$@")
                    && superKeyStrings.panelCaptionFormat.contains("%2$@")
                    && SuperKeySource.allCases.allSatisfy {
                        !superKeyStrings.sourceLabel($0).isEmpty
                    },
                   "super key strings keep their format and avoid em-dashes (\(language.rawValue))")
            let shortcutValues = Mirror(reflecting: FeatureStrings.shortcuts(language)).children
                .compactMap { $0.value as? String }
            expect(shortcutValues.count == 3 && shortcutValues.allSatisfy { !$0.isEmpty },
                   "every shortcut editor string is set for \(language.rawValue)")
            expect(shortcutValues.allSatisfy { !$0.contains("—") }
                    && FeatureStrings.shortcuts(language).superKeyAlternativeFormat.contains("%@"),
                   "shortcut editor strings keep their format and avoid em-dashes (\(language.rawValue))")
            let appearanceValues = Mirror(reflecting: FeatureStrings.appearance(language)).children
                .compactMap { $0.value as? String }
            expect(appearanceValues.count == 5 && appearanceValues.allSatisfy { !$0.isEmpty },
                   "every appearance string is set for \(language.rawValue)")
            expect(appearanceValues.allSatisfy { !$0.contains("—") },
                   "no em-dash in visible appearance strings (\(language.rawValue))")
            let screenshotValues = Mirror(reflecting: FeatureStrings.screenshot(language)).children
                .compactMap { $0.value as? String }
            expect(!screenshotValues.isEmpty && screenshotValues.allSatisfy { !$0.isEmpty },
                   "every screenshot string is set for \(language.rawValue)")
            expect(screenshotValues.allSatisfy { !$0.contains("—") },
                   "no em-dash in visible screenshot strings (\(language.rawValue))")
            let recentCaptureValues = Mirror(
                reflecting: FeatureStrings.recentCaptures(language)).children
                .compactMap { $0.value as? String }
            expect(recentCaptureValues.count == 8
                    && recentCaptureValues.allSatisfy { !$0.isEmpty },
                   "every recent capture string is set for \(language.rawValue)")
            expect(recentCaptureValues.allSatisfy { !$0.contains("—") },
                   "no em-dash in recent capture strings (\(language.rawValue))")
            let feedbackValues = Mirror(reflecting: FeatureStrings.feedback(language)).children
                .compactMap { $0.value as? String }
            expect(feedbackValues.count == 29 && feedbackValues.allSatisfy { !$0.isEmpty },
                   "every feedback string is set for \(language.rawValue)")
            expect(feedbackValues.allSatisfy { !$0.contains("—") },
                   "no em-dash in visible feedback strings (\(language.rawValue))")
            expect(FeatureStrings.feedback(language).charactersFormat.contains("%d"),
                   "feedback character format keeps its placeholder (\(language.rawValue))")
            let cameraPreviewValues = Mirror(reflecting: FeatureStrings.cameraPreview(language)).children
                .compactMap { $0.value as? String }
            expect(!cameraPreviewValues.isEmpty && cameraPreviewValues.allSatisfy { !$0.isEmpty },
                   "every camera preview string is set for \(language.rawValue)")
            expect(cameraPreviewValues.allSatisfy { !$0.contains("—") },
                   "no em-dash in visible camera preview strings (\(language.rawValue))")
            let radialMenuValues = Mirror(reflecting: FeatureStrings.radialMenu(language)).children
                .compactMap { $0.value as? String }
            expect(radialMenuValues.count == 97 && radialMenuValues.allSatisfy { !$0.isEmpty },
                   "every radial menu string is set for \(language.rawValue)")
            expect(radialMenuValues.allSatisfy { !$0.contains("—") },
                   "no em-dash in visible radial menu strings (\(language.rawValue))")
            expect(FeatureStrings.radialMenu(language).mediaOpenAppFormat.contains("%@"),
                   "Now Playing keeps the app-name placeholder (\(language.rawValue))")
            let scratchpadValues = Mirror(reflecting: FeatureStrings.scratchpad(language)).children
                .compactMap { $0.value as? String }
            expect(scratchpadValues.count == 32 && scratchpadValues.allSatisfy { !$0.isEmpty },
                   "every scratchpad string is set for \(language.rawValue)")
            expect(scratchpadValues.allSatisfy { !$0.contains("—") },
                   "no em-dash in visible scratchpad strings (\(language.rawValue))")
            expect(FeatureStrings.scratchpad(language).deletePadMessageFormat.contains("%@")
                    && FeatureStrings.scratchpad(language).padLimitFormat.contains("%d"),
                   "scratchpad dialog formats keep their placeholders (\(language.rawValue))")
            let finderRenameValues = Mirror(
                reflecting: FeatureStrings.finderRename(language)).children
                .compactMap { $0.value as? String }
            expect(finderRenameValues.count == 6
                    && finderRenameValues.allSatisfy { !$0.isEmpty },
                   "every Finder rename string is set for \(language.rawValue)")
            expect(finderRenameValues.allSatisfy { !$0.contains("—") },
                   "no em-dash in visible Finder rename strings (\(language.rawValue))")
            let whatsAppValues = Mirror(reflecting: FeatureStrings.whatsAppDownloads(language)).children
                .compactMap { $0.value as? String }
            expect(whatsAppValues.count == 40 && whatsAppValues.allSatisfy { !$0.isEmpty },
                   "every WhatsApp downloads string is set for \(language.rawValue)")
            expect(whatsAppValues.allSatisfy { !$0.contains("—") },
                   "no em-dash in WhatsApp downloads strings (\(language.rawValue))")
            let organizerValues = Mirror(
                reflecting: WhatsAppOrganizerStrings.localized(language)).children
                .compactMap { $0.value as? String }
            expect(organizerValues.count == 30 && organizerValues.allSatisfy { !$0.isEmpty },
                   "every WhatsApp organizer string is set for \(language.rawValue)")
            expect(organizerValues.allSatisfy { !$0.contains("—") },
                   "no em-dash in WhatsApp organizer strings (\(language.rawValue))")
            let recorderValues = Mirror(reflecting: FeatureStrings.recorder(language)).children
                .compactMap { $0.value as? String }
            expect(recorderValues.count == 135 && recorderValues.allSatisfy { !$0.isEmpty },
                   "every screen recorder string is set for \(language.rawValue)")
            expect(recorderValues.allSatisfy { !$0.contains("—") },
                   "no em-dash in visible screen recorder strings (\(language.rawValue))")
            expect(FeatureStrings.recorder(language).countdownSecondsFormat.contains("%d"),
                   "recorder countdown format keeps its specifier (\(language.rawValue))")
            expect(FeatureStrings.recorder(language).frameRateFormat.contains("%d"),
                   "recorder frame rate format keeps its specifier (\(language.rawValue))")
            expect(FeatureStrings.recorder(language).savedHUDFormat.contains("%@"),
                   "recorder saved format keeps its specifier (\(language.rawValue))")
            expect(FeatureStrings.screenshot(language).delaySecondsFormat.contains("%d"),
                   "screenshot delay format keeps its specifier (\(language.rawValue))")
            expect(FeatureStrings.screenshot(language).savedHUDFormat.contains("%@"),
                   "screenshot saved format keeps its specifier (\(language.rawValue))")
            expect(FeatureStrings.screenshot(language).savedAndCopiedHUDFormat.contains("%@"),
                   "screenshot saved-and-copied format keeps its specifier (\(language.rawValue))")
            expect(FeatureStrings.screenshot(language).fileNumberNextFormat.contains("%d"),
                   "screenshot next-number format keeps its specifier (\(language.rawValue))")
            let mouseClickDebounceValues = Mirror(
                reflecting: FeatureStrings.mouseClickDebounce(language)
            ).children.compactMap { $0.value as? String }
            expect(mouseClickDebounceValues.count == 5
                    && mouseClickDebounceValues.allSatisfy { !$0.isEmpty },
                   "every mouse click debounce string is set for \(language.rawValue)")
            expect(mouseClickDebounceValues.allSatisfy { !$0.contains("—") },
                   "no em-dash in mouse click debounce strings (\(language.rawValue))")
            let strings: Strings = {
                switch language {
                case .enUS: return .enUS
                case .ptBR: return .ptBR
                case .tr: return .tr
                case .ru: return .ru
                case .es: return .es
                case .de: return .de
                case .fr: return .fr
                case .it: return .it
                case .ja: return .ja
                case .ko: return .ko
                case .zhHans: return .zhHans
                case .zhTW: return .zhTW
                case .zhHK: return .zhHK
                }
            }()
            expect(!strings.obPurposeTitle.isEmpty && !strings.obPurposeBody.isEmpty
                    && !strings.obPurposeSkip.isEmpty,
                   "the purpose step speaks \(language.rawValue)")
            expect(!strings.urlCleanerRulesTitle.isEmpty
                    && !strings.urlCleanerRulesAllSites.isEmpty
                    && !strings.urlCleanerRulesCaption.isEmpty
                    && !strings.urlCleanerRulesAddSite.isEmpty
                    && !strings.urlCleanerRulesParameterPlaceholder.isEmpty
                    && !strings.urlCleanerRulesAddButton.isEmpty
                    && !strings.urlCleanerRulesRemoveButton.isEmpty
                    && !strings.urlCleanerRulesCountSingular.isEmpty
                    && strings.urlCleanerRulesCountPluralFormat.contains("%d")
                    && strings.urlCleanerRemovedFormat.contains("%@"),
                   "the URL cleaner rule list speaks \(language.rawValue)")
        }

        // MARK: Hub presets and energy badges

        expect(FeaturePreset.allCases.count == 3,
               "three starting points, not another wall of decisions")
        expect(FeaturePreset.allCases.allSatisfy { !$0.features.isEmpty },
               "every preset installs something")
        expect(FeaturePreset.essential.features.contains(.mixer)
                && FeaturePreset.essential.features.contains(.keepAwake)
                && FeaturePreset.essential.features.contains(.monitorPower),
               "the essential preset covers mixer, monitor and keep awake")
        expect(FeaturePreset.windows.features.allSatisfy { $0.group == .windowsDock },
               "the windows preset stays inside the windows and Dock group")
        expect(FeaturePreset.battery.features.allSatisfy {
                   $0.energyProfile != .mouse && $0.energyProfile != .pointer
                       && $0.energyProfile != .keyboard
                       && $0.energyProfile != .inputs
               },
               "battery and quiet installs nothing that listens to input")
        expect(FeaturePreset.battery.features.allSatisfy {
                   !$0.permissions.contains(.accessibility)
               },
               "battery and quiet needs no accessibility permission at all")
        let firstRunSuiteName = "com.vorssaint.tests.first-run.\(UUID().uuidString)"
        if let firstRunDefaults = UserDefaults(suiteName: firstRunSuiteName) {
            firstRunDefaults.register(defaults: AppFeature.availabilityDefaults)
            FeaturePreset.prepareFirstRunAvailability(in: firstRunDefaults)
            expect(Set(AppFeature.allCases.filter {
                firstRunDefaults.bool(forKey: $0.availabilityKey)
            }) == FeaturePreset.essential.features,
            "a clean install loads only the essential feature set before onboarding")

            for feature in AppFeature.allCases {
                firstRunDefaults.set(true, forKey: feature.availabilityKey)
            }
            firstRunDefaults.set(2, forKey: DefaultsKey.onboardingStep)
            FeaturePreset.prepareFirstRunAvailability(in: firstRunDefaults)
            expect(AppFeature.allCases.allSatisfy {
                firstRunDefaults.bool(forKey: $0.availabilityKey)
            }, "an interrupted onboarding keeps the feature selection already applied")
            firstRunDefaults.removePersistentDomain(forName: firstRunSuiteName)
        } else {
            expect(false, "first-run defaults suite can be created")
        }
        for preset in FeaturePreset.allCases {
            expect(preset.enableKeys.allSatisfy { key in
                       preset.features.contains { $0.enabledKeys.contains(key) }
                   },
                   "preset enable keys belong to its own features (\(preset.rawValue))")
        }
        expect(AppFeature.monitorCPU.energyProfile == .periodic
                && AppFeature.clipboardHistory.energyProfile == .periodic
                && AppFeature.mouseAcceleration.energyProfile == .idle
                && AppFeature.textSnippets.energyProfile == .inputs
                && AppFeature.dockPreview.energyProfile == .mouse
                && AppFeature.mouseClickDebounce.energyProfile == .mouse
                && AppFeature.switcher.energyProfile == .keyboard
                && AppFeature.finderRename.energyProfile == .keyboard
                && AppFeature.colorPicker.energyProfile == .idle
                && AppFeature.keepAwake.energyProfile == .idle
                && AppFeature.brightness.energyProfile == .idle
                && AppFeature.scratchpad.energyProfile == .idle,
               "energy badges tell the honest mechanism per feature")
        let previousWindowGestureEnergy = UserDefaults.standard.object(
            forKey: DefaultsKey.windowGestureEnabled
        )
        UserDefaults.standard.set(true, forKey: DefaultsKey.windowGestureEnabled)
        expect(AppFeature.windowLayout.energyProfile == .pointer,
               "window dragging reports trackpad and mouse pointer input")
        if let previousWindowGestureEnergy {
            UserDefaults.standard.set(previousWindowGestureEnergy,
                                      forKey: DefaultsKey.windowGestureEnabled)
        } else {
            UserDefaults.standard.removeObject(forKey: DefaultsKey.windowGestureEnabled)
        }
        let previousWindowEdgeSnapEnergy = UserDefaults.standard.object(
            forKey: DefaultsKey.windowEdgeSnapEnabled
        )
        let previousWindowEdgeSnapZones = UserDefaults.standard.object(
            forKey: DefaultsKey.windowEdgeSnapDisabledZones
        )
        UserDefaults.standard.set(false, forKey: DefaultsKey.windowGestureEnabled)
        UserDefaults.standard.set(true, forKey: DefaultsKey.windowEdgeSnapEnabled)
        UserDefaults.standard.set("", forKey: DefaultsKey.windowEdgeSnapDisabledZones)
        expect(AppFeature.windowLayout.energyProfile == .pointer,
               "edge snapping reports its trackpad and mouse listener")
        UserDefaults.standard.set(
            WindowEdgeSnapZone.disabledZonesStorageValue(WindowEdgeSnapZone.allEnabled),
            forKey: DefaultsKey.windowEdgeSnapDisabledZones
        )
        expect(AppFeature.windowLayout.energyProfile == .idle,
               "edge snapping keeps no pointer listener when every visual zone is off")
        if let previousWindowEdgeSnapZones {
            UserDefaults.standard.set(previousWindowEdgeSnapZones,
                                      forKey: DefaultsKey.windowEdgeSnapDisabledZones)
        } else {
            UserDefaults.standard.removeObject(forKey: DefaultsKey.windowEdgeSnapDisabledZones)
        }
        if let previousWindowEdgeSnapEnergy {
            UserDefaults.standard.set(previousWindowEdgeSnapEnergy,
                                      forKey: DefaultsKey.windowEdgeSnapEnabled)
        } else {
            UserDefaults.standard.removeObject(forKey: DefaultsKey.windowEdgeSnapEnabled)
        }
        if let previousWindowGestureEnergy {
            UserDefaults.standard.set(previousWindowGestureEnergy,
                                      forKey: DefaultsKey.windowGestureEnabled)
        } else {
            UserDefaults.standard.removeObject(forKey: DefaultsKey.windowGestureEnabled)
        }
    }
}
