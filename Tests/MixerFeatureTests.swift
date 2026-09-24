// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import Carbon.HIToolbox
import Combine
import CoreAudio
import CoreGraphics
import Darwin
import Foundation
import ImageIO
import VMStatisticsCompat

enum MixerFeatureTests {
    static func run(_ suite: TestSuite) {
        suite.expectClose(Defaults.sanitizedAppVolume(1.5), 1.5, "valid app volume is preserved")
        suite.expectClose(Defaults.sanitizedAppVolume(3), 2, "high app volume clamps to boost maximum")
        suite.expectClose(Defaults.sanitizedAppVolume(-1), 0, "negative app volume clamps to mute")
        suite.expectClose(Defaults.sanitizedAppVolume(.infinity), 1, "non-finite app volume falls back to unity")
        suite.expectClose(MixerRoutingSupport.volumeFraction(fromPercentageText: "40",
                                                       maximumPercent: 200) ?? -1,
                    0.4,
                    "mixer percentage input becomes app gain")
        suite.expectClose(MixerRoutingSupport.volumeFraction(fromPercentageText: " 75% ",
                                                       maximumPercent: 100) ?? -1,
                    0.75,
                    "mixer percentage input accepts a percent sign")
        suite.expectClose(MixerRoutingSupport.volumeFraction(fromPercentageText: "250",
                                                       maximumPercent: 200) ?? -1,
                    2,
                    "mixer percentage input clamps to the row maximum")
        suite.expectClose(MixerRoutingSupport.volumeFraction(fromPercentageText: "-10",
                                                       maximumPercent: 100) ?? -1,
                    0,
                    "mixer percentage input clamps negative values")
        suite.expect(MixerRoutingSupport.volumeFraction(fromPercentageText: "loud",
                                                  maximumPercent: 100) == nil,
               "mixer percentage input rejects non-numbers")
        suite.expect(MixerRoutingSupport.volumeFraction(fromPercentageText: "nan",
                                                  maximumPercent: 100) == nil,
               "mixer percentage input rejects non-finite numbers")
        let percentWindow = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 80, height: 24),
                                     styleMask: .borderless,
                                     backing: .buffered,
                                     defer: false)
        let percentField = MixerPercentNativeTextField(frame: percentWindow.contentView!.bounds)
        percentField.stringValue = "37"
        var percentFieldAttached = false
        percentField.didAttachToWindow = { percentFieldAttached = true }
        percentWindow.contentView?.addSubview(percentField)
        suite.expect(percentFieldAttached,
               "mixer percentage field notices when it joins its popover window")
        suite.expect(percentField.focusAndSelectAll(),
               "mixer percentage field becomes the native first responder")
        suite.expect((percentField.currentEditor() as? NSTextView)?.selectedRange()
                == NSRange(location: 0, length: 2),
               "mixer percentage field selects its existing value for direct replacement")
        percentWindow.orderOut(nil)
        suite.expect(Defaults.sanitizedMixerHeadphonesDisconnectVolumePercent(35) == 35,
               "headphone disconnect volume preserves valid percentages")
        suite.expect(Defaults.sanitizedMixerHeadphonesDisconnectVolumePercent(-5)
               == Defaults.minimumMixerHeadphonesDisconnectVolumePercent,
               "headphone disconnect volume never drops below the audible floor")
        suite.expect(Defaults.sanitizedMixerHeadphonesDisconnectVolumePercent(0)
               == Defaults.minimumMixerHeadphonesDisconnectVolumePercent,
               "headphone disconnect protection lowers the speakers, it never silences them")
        suite.expect(Defaults.sanitizedMixerHeadphonesDisconnectVolumePercent(105) == 100,
               "headphone disconnect volume clamps high values")
        let headphonesSuite = "vorss.tests.mixer.headphones"
        if let silentHeadphoneVolume = UserDefaults(suiteName: headphonesSuite) {
            silentHeadphoneVolume.removePersistentDomain(forName: headphonesSuite)
            silentHeadphoneVolume.set(0, forKey: DefaultsKey.mixerHeadphonesDisconnectVolumePercent)
            Defaults.migrateSilentHeadphonesDisconnectVolume(in: silentHeadphoneVolume)
            suite.expect(silentHeadphoneVolume.integer(forKey: DefaultsKey.mixerHeadphonesDisconnectVolumePercent)
                   == Defaults.defaultMixerHeadphonesDisconnectVolumePercent,
                   "a stored volume of zero from the first release of the option migrates to the default")
            silentHeadphoneVolume.set(60, forKey: DefaultsKey.mixerHeadphonesDisconnectVolumePercent)
            Defaults.migrateSilentHeadphonesDisconnectVolume(in: silentHeadphoneVolume)
            suite.expect(silentHeadphoneVolume.integer(forKey: DefaultsKey.mixerHeadphonesDisconnectVolumePercent) == 60,
                   "a volume the user chose is never migrated")
            silentHeadphoneVolume.removePersistentDomain(forName: headphonesSuite)
        }
        suite.expect(Defaults.sanitizedAppOutputDeviceUID(" BuiltInSpeakerDevice ") == "BuiltInSpeakerDevice",
               "audio output device UIDs are trimmed")
        suite.expect(Defaults.sanitizedAppOutputDeviceUID("") == nil,
               "empty audio output device UIDs are ignored")
        suite.expect(Defaults.sanitizedAppOutputDeviceUID("bad\nuid") == nil,
               "control characters are rejected from audio output device UIDs")
        suite.expect(Defaults.sanitizedPreferredInputDeviceUID(" BuiltInMicrophoneDevice ") == "BuiltInMicrophoneDevice",
               "audio input device UIDs are trimmed")
        suite.expect(Defaults.sanitizedPreferredInputDeviceUID("") == nil,
               "empty audio input device UIDs are ignored")
        let savedRoutes = Defaults.sanitizedAppOutputDevices([
            "com.apple.Safari": "BuiltInSpeakerDevice",
            "bad\napp": "ExternalDisplay",
            "com.example.Empty": "",
        ])
        suite.expect(savedRoutes == ["com.apple.Safari": "BuiltInSpeakerDevice"],
               "app output device routes keep only valid app and device ids")
        suite.expect(Defaults.sanitizedSoundOutputSwitcherDeviceUIDs([
            " BuiltInSpeakerDevice ",
            "bad\nuid",
            "BuiltInSpeakerDevice",
            "ExternalDisplay",
            7,
        ]) == ["BuiltInSpeakerDevice", "ExternalDisplay"],
               "sound output switcher keeps valid unique device ids in order")
        let savedMixerVolumes = ["com.apple.Safari": 0.35, "com.apple.Music": 1.4]
        let successfulUniversalOutput = MixerRoutingSupport.preferencesAfterUniversalOutputSwitch(
            outputDeviceUIDs: savedRoutes,
            volumes: savedMixerVolumes,
            switchSucceeded: true)
        suite.expect(successfulUniversalOutput.outputDeviceUIDs.isEmpty,
               "universal output clears per-app routes after a successful switch")
        suite.expect(successfulUniversalOutput.volumes == savedMixerVolumes,
               "universal output preserves saved app volumes")
        let failedUniversalOutput = MixerRoutingSupport.preferencesAfterUniversalOutputSwitch(
            outputDeviceUIDs: savedRoutes,
            volumes: savedMixerVolumes,
            switchSucceeded: false)
        suite.expect(failedUniversalOutput.outputDeviceUIDs == savedRoutes,
               "failed universal output keeps per-app routes")
        suite.expect(failedUniversalOutput.volumes == savedMixerVolumes,
               "failed universal output keeps saved app volumes")
        suite.expect(MixerRoutingSupport.nextSelectedOutputDeviceUID(
            currentUID: "BuiltInSpeakerDevice",
            selectedUIDs: ["BuiltInSpeakerDevice", "ExternalDisplay"],
            availableUIDs: ["BuiltInSpeakerDevice", "ExternalDisplay"]) == "ExternalDisplay",
               "sound output switcher moves from the current selected output to the next")
        suite.expect(MixerRoutingSupport.nextSelectedOutputDeviceUID(
            currentUID: "ExternalDisplay",
            selectedUIDs: ["BuiltInSpeakerDevice", "ExternalDisplay"],
            availableUIDs: ["BuiltInSpeakerDevice", "ExternalDisplay"]) == "BuiltInSpeakerDevice",
               "sound output switcher wraps selected outputs")
        suite.expect(MixerRoutingSupport.nextSelectedOutputDeviceUID(
            currentUID: "USBHeadphones",
            selectedUIDs: ["BuiltInSpeakerDevice", "ExternalDisplay"],
            availableUIDs: ["BuiltInSpeakerDevice", "ExternalDisplay"]) == "BuiltInSpeakerDevice",
               "sound output switcher starts at the first selected output when current is outside the cycle")
        suite.expect(MixerRoutingSupport.nextSelectedOutputDeviceUID(
            currentUID: "BuiltInSpeakerDevice",
            selectedUIDs: ["BuiltInSpeakerDevice", "MissingDisplay", "ExternalDisplay"],
            availableUIDs: ["BuiltInSpeakerDevice", "ExternalDisplay"]) == "ExternalDisplay",
               "sound output switcher skips unavailable selected outputs")
        suite.expect(MixerRoutingSupport.nextSelectedOutputDeviceUID(
            currentUID: "BuiltInSpeakerDevice",
            selectedUIDs: ["BuiltInSpeakerDevice"],
            availableUIDs: ["BuiltInSpeakerDevice"]) == nil,
               "sound output switcher does nothing when the only selected output is already current")
        suite.expect(MixerRoutingSupport.outputLooksLikeHeadphones(name: "AirPods Pro",
                                                             uid: "",
                                                             dataSourceName: nil),
               "AirPods are treated as headphones")
        suite.expect(MixerRoutingSupport.outputLooksLikeHeadphones(name: "Built-in Output",
                                                             uid: "",
                                                             dataSourceName: "Headphones"),
               "wired headphone data source is treated as headphones")
        suite.expect(MixerRoutingSupport.outputLooksLikeHeadphones(name: "Sony WH-1000XM5",
                                                             uid: "",
                                                             dataSourceName: nil),
               "common Bluetooth headphone names are treated as headphones")
        suite.expect(!MixerRoutingSupport.outputLooksLikeHeadphones(name: "MacBook Pro Speakers",
                                                              uid: "BuiltInSpeakerDevice",
                                                              dataSourceName: nil),
               "built-in speakers are not treated as headphones")
        suite.expect(!MixerRoutingSupport.outputLooksLikeHeadphones(name: "JBL Flip",
                                                              uid: "",
                                                              dataSourceName: nil),
               "Bluetooth speakers are not treated as headphones")
        // Issue #256: some browsers' audio helpers answer for themselves, so
        // the mixer walks the parent chain to the nearest regular app.
        let helperParents: [pid_t: pid_t] = [500: 100, 100: 1, 700: 1,
                                             900: 901, 901: 902, 902: 903, 903: 904,
                                             904: 905, 905: 906, 906: 907, 907: 100]
        func owningApp(of responsible: pid_t, regularApps: Set<pid_t> = [100]) -> pid_t? {
            MixerRoutingSupport.owningRegularAppPid(
                responsiblePid: responsible,
                isRegularApp: { regularApps.contains($0) },
                parentPid: { helperParents[$0] ?? 0 })
        }
        suite.expect(owningApp(of: 100) == 100,
               "a responsible regular app is billed directly")
        suite.expect(owningApp(of: 500) == 100,
               "a helper answering for itself is billed to the app that spawned it")
        suite.expect(owningApp(of: 700) == nil,
               "daemons whose parent chain ends at launchd stay unlisted")
        suite.expect(owningApp(of: 42) == nil,
               "a failed parent lookup stops the walk")
        suite.expect(owningApp(of: 900) == nil,
               "the parent walk gives up beyond the depth cap")
        suite.expect(owningApp(of: 902) == 100,
               "a regular app within the depth cap is still found")
        suite.expect(owningApp(of: 0) == nil,
               "a missing responsible pid maps to no app")
        func resolvedOwningApp(responsible: pid_t, pid: pid_t, regularApps: Set<pid_t> = [100]) -> pid_t? {
            let isRegular: (pid_t) -> Bool = { regularApps.contains($0) }
            let parent: (pid_t) -> pid_t = { helperParents[$0] ?? 0 }
            return MixerRoutingSupport.owningRegularAppPid(
                responsiblePid: responsible,
                isRegularApp: isRegular,
                parentPid: parent
            ) ?? (responsible != pid ? MixerRoutingSupport.owningRegularAppPid(
                responsiblePid: pid,
                isRegularApp: isRegular,
                parentPid: parent
            ) : nil)
        }
        suite.expect(resolvedOwningApp(responsible: 700, pid: 500) == 100,
               "a helper whose responsibility returns a daemon still falls back to its parent app")
        suite.expect(!MixerRoutingSupport.requiresEngine(volume: 1,
                                                   selectedOutputDeviceUID: nil,
                                                   targetOutputDeviceUID: "BuiltInSpeakerDevice",
                                                   defaultOutputDeviceUID: "BuiltInSpeakerDevice"),
               "default output at 100 percent stays passthrough")
        suite.expect(MixerRoutingSupport.requiresEngine(volume: 0.5,
                                                  selectedOutputDeviceUID: nil,
                                                  targetOutputDeviceUID: "BuiltInSpeakerDevice",
                                                  defaultOutputDeviceUID: "BuiltInSpeakerDevice"),
               "default output with changed volume uses an engine")
        suite.expect(MixerRoutingSupport.requiresEngine(volume: 1,
                                                  selectedOutputDeviceUID: "ExternalDisplay",
                                                  targetOutputDeviceUID: "ExternalDisplay",
                                                  defaultOutputDeviceUID: "BuiltInSpeakerDevice"),
               "specific non-default output at 100 percent uses an engine")
        suite.expect(!MixerRoutingSupport.requiresEngine(hasAudioObjects: false,
                                                   volume: 0.5,
                                                   selectedOutputDeviceUID: nil,
                                                   targetOutputDeviceUID: "BuiltInSpeakerDevice",
                                                   defaultOutputDeviceUID: "BuiltInSpeakerDevice"),
               "a persistent mixer row waits for an audio connection before building a tap")
        suite.expect(MixerRoutingSupport.shouldShowApp(isPlaying: false,
                                                 volume: 1,
                                                 selectedOutputDeviceUID: nil,
                                                 hideInactiveApps: false),
               "the inactive-app filter changes nothing until the user enables it")
        suite.expect(!MixerRoutingSupport.shouldShowApp(isPlaying: false,
                                                  volume: 1,
                                                  selectedOutputDeviceUID: nil,
                                                  hideInactiveApps: true),
               "an idle uncustomized mixer app can be hidden")
        suite.expect(MixerRoutingSupport.shouldShowApp(isPlaying: true,
                                                 volume: 1,
                                                 selectedOutputDeviceUID: nil,
                                                 hideInactiveApps: true),
               "a playing mixer app remains visible")
        suite.expect(MixerRoutingSupport.shouldShowApp(isPlaying: false,
                                                 volume: 0.75,
                                                 selectedOutputDeviceUID: nil,
                                                 hideInactiveApps: true)
                && MixerRoutingSupport.shouldShowApp(isPlaying: false,
                                                     volume: 1,
                                                     selectedOutputDeviceUID: "ExternalDisplay",
                                                     hideInactiveApps: true),
               "custom volume and output choices keep inactive mixer apps visible")

        // Issue #296. A tap mutes the app on the real output, so which build
        // may be installed, when an engine is allowed to go away and who may
        // be tapped at all decide whether an app suddenly plays at full
        // volume, plays twice as loud, or goes silent.
        suite.expect(!MixerRoutingSupport.rowMayBeTapped(savedVolume: nil,
                                                   savedRouteUID: nil,
                                                   defaultOutputDeviceUID: "BuiltInSpeakerDevice"),
               "an app with no saved volume and no saved route is never tapped")
        suite.expect(!MixerRoutingSupport.rowMayBeTapped(savedVolume: 1,
                                                   savedRouteUID: nil,
                                                   defaultOutputDeviceUID: "BuiltInSpeakerDevice"),
               "a row saved at 100 percent is never tapped")
        suite.expect(!MixerRoutingSupport.rowMayBeTapped(savedVolume: nil,
                                                   savedRouteUID: "BuiltInSpeakerDevice",
                                                   defaultOutputDeviceUID: "BuiltInSpeakerDevice"),
               "a row routed to the device that is already the default is never tapped")
        suite.expect(MixerRoutingSupport.rowMayBeTapped(savedVolume: 0.4,
                                                  savedRouteUID: nil,
                                                  defaultOutputDeviceUID: "BuiltInSpeakerDevice"),
               "a row the user turned down is tapped")
        suite.expect(MixerRoutingSupport.rowMayBeTapped(savedVolume: nil,
                                                  savedRouteUID: "ExternalDisplay",
                                                  defaultOutputDeviceUID: "BuiltInSpeakerDevice"),
               "a row routed to another output is tapped")

        var mixerBuilds = MixerEngineBuilds()
        suite.expect(mixerBuilds.isEmpty, "a mixer with nothing being built has no builds in flight")
        // No real token is ever negative, so the sentinel cannot pass a check.
        let firstBuild = mixerBuilds.begin("com.example.Player") ?? -1
        suite.expect(firstBuild > 0, "the first engine build for a row starts")
        suite.expect(mixerBuilds.begin("com.example.Player") == nil,
               "a second engine build for the same row is refused while one is in flight")
        suite.expect(mixerBuilds.isCurrent("com.example.Player", token: firstBuild),
               "a build that nothing invalidated is the one to install")
        mixerBuilds.finish("com.example.Player", token: firstBuild)
        suite.expect(mixerBuilds.isEmpty,
               "finishing a build frees the row for the next one")
        let staleBuild = mixerBuilds.begin("com.example.Player") ?? -1
        mixerBuilds.invalidateAll()
        suite.expect(!mixerBuilds.isCurrent("com.example.Player", token: staleBuild),
               "an engine build that lands after everything was invalidated is discarded")
        let freshBuild = mixerBuilds.begin("com.example.Player") ?? -1
        suite.expect(freshBuild > 0 && freshBuild != staleBuild
               && mixerBuilds.isCurrent("com.example.Player", token: freshBuild),
               "the build started after an invalidation is the one to install")
        mixerBuilds.finish("com.example.Player", token: staleBuild)
        suite.expect(mixerBuilds.isCurrent("com.example.Player", token: freshBuild),
               "a stale build landing late leaves the current build alone")
        var manyBuilds = MixerEngineBuilds()
        let firstRow = manyBuilds.begin("com.example.Player") ?? -1
        let secondRow = manyBuilds.begin("com.example.Radio") ?? -1
        manyBuilds.invalidateAll()
        suite.expect(manyBuilds.isEmpty,
               "invalidating clears every engine build in flight")
        suite.expect(!manyBuilds.isCurrent("com.example.Player", token: firstRow)
               && !manyBuilds.isCurrent("com.example.Radio", token: secondRow),
               "one invalidation makes every row's build in flight stale")

        var mixerRecovery = MixerEngineRecovery()
        let firstAudioPath = MixerEngineRecovery.Configuration(objects: [41],
                                                                outputDeviceUID: "speaker-a")
        suite.expect(mixerRecovery.allowsBuild("player", configuration: firstAudioPath),
               "a new mixer audio path may build")
        suite.expect(mixerRecovery.recordFailure("player", configuration: firstAudioPath),
               "a dead mixer engine gets one replacement")
        suite.expect(mixerRecovery.allowsBuild("player", configuration: firstAudioPath),
               "the one replacement may build")
        suite.expect(!mixerRecovery.recordFailure("player", configuration: firstAudioPath)
               && !mixerRecovery.allowsBuild("player", configuration: firstAudioPath),
               "the same dead replacement stays untapped instead of muting forever")
        let changedAudioPath = MixerEngineRecovery.Configuration(objects: [42],
                                                                  outputDeviceUID: "speaker-a")
        suite.expect(mixerRecovery.allowsBuild("player", configuration: changedAudioPath),
               "a new audio object gets its own recovery attempt")
        mixerRecovery.clear("player")
        suite.expect(mixerRecovery.allowsBuild("player", configuration: firstAudioPath),
               "an explicit mixer change re-enables the audio path")

        var refreshes = MixerRefreshCoordinator()
        suite.expect(!refreshes.isReading, "a mixer that is not reading the audio devices holds no slot")
        // No real generation is ever negative, so the sentinel cannot pass.
        let firstRefresh = refreshes.begin() ?? -1
        suite.expect(firstRefresh > 0 && refreshes.isReading, "the first refresh takes the slot")
        suite.expect(refreshes.begin() == nil,
               "a second refresh is refused while one is still reading the audio devices")
        suite.expect(refreshes.takeRepeatRequest(),
               "the refused refresh is remembered so nothing asked for is lost")
        suite.expect(!refreshes.takeRepeatRequest(),
               "a remembered refresh runs once, not on every landing")
        suite.expect(refreshes.finish(firstRefresh), "the refresh that owns the slot publishes what it read")
        suite.expect(!refreshes.isReading, "finishing a refresh frees the slot for the next one")
        let secondRefresh = refreshes.begin() ?? -1
        suite.expect(secondRefresh > firstRefresh, "generations move forward, never repeat")
        suite.expect(!refreshes.finish(firstRefresh),
               "a refresh from an older generation never publishes")
        suite.expect(refreshes.isReading,
               "an older refresh landing late leaves the current one holding the slot")
        suite.expect(refreshes.finish(secondRefresh), "the current refresh still publishes after that")

        var discarded = MixerRefreshCoordinator()
        let staleRefresh = discarded.begin() ?? -1
        _ = discarded.begin()
        discarded.discardInFlight()
        suite.expect(!discarded.isReading, "discarding what is in flight frees the slot at once")
        suite.expect(!discarded.finish(staleRefresh),
               "a refresh reading while the output changed publishes nothing")
        suite.expect(!discarded.takeRepeatRequest(),
               "discarding also drops the repeat request, since a fresh refresh follows it")
        let afterDiscard = discarded.begin() ?? -1
        suite.expect(afterDiscard > staleRefresh && discarded.finish(afterDiscard),
               "the refresh started after a discard is the one that publishes")

        suite.expect(MixerRoutingSupport.engineTeardownDelay(hasAudioObjects: true,
                                                       lastChangeAt: nil,
                                                       now: 100) == nil,
               "a row that still has audio is never left waiting for its tap")
        suite.expect(MixerRoutingSupport.engineTeardownDelay(hasAudioObjects: true,
                                                       lastChangeAt: 99.9,
                                                       now: 100) == nil,
               "a row that got its audio back is handled at once")
        suite.expect(MixerRoutingSupport.engineTeardownDelay(hasAudioObjects: false,
                                                       lastChangeAt: nil,
                                                       now: 100,
                                                       window: 0.2) == 0.2,
               "a row that just lost its audio objects keeps its tap for one window")
        suite.expectClose(MixerRoutingSupport.engineTeardownDelay(hasAudioObjects: false,
                                                            lastChangeAt: 99.95,
                                                            now: 100,
                                                            window: 0.2) ?? -1,
                    0.15,
                    "repeated churn in one window waits out the remainder instead of acting again")
        suite.expect(MixerRoutingSupport.engineTeardownDelay(hasAudioObjects: false,
                                                       lastChangeAt: 99.5,
                                                       now: 100,
                                                       window: 0.2) == nil,
               "a row still without audio after the window loses its tap")
        suite.expect(MixerRoutingSupport.engineTeardownDelay(hasAudioObjects: false,
                                                       lastChangeAt: 101,
                                                       now: 100,
                                                       window: 0.2) == 0.2,
               "a clock that jumps backwards falls back to a full window")

        // Render health of a live engine (issue #341): a tap whose aggregate
        // stopped rendering after wake keeps muting the app and must be caught.
        typealias RenderLook = MixerRoutingSupport.EngineRenderObservation
        suite.expect(MixerRoutingSupport.engineRenderVerdict(previous: RenderLook(cycles: 7, at: 90),
                                                       cycles: 7,
                                                       isPlaying: false,
                                                       now: 100) == nil,
               "a silent app gives no render verdict and clears the observation")
        suite.expect(MixerRoutingSupport.engineRenderVerdict(previous: nil,
                                                       cycles: 7,
                                                       isPlaying: true,
                                                       now: 100,
                                                       window: 1.5)
               == .note(RenderLook(cycles: 7, at: 100), recheckAfter: 1.5),
               "the first look notes the count and schedules a conclusive recheck")
        suite.expect(MixerRoutingSupport.engineRenderVerdict(previous: RenderLook(cycles: 7, at: 100),
                                                       cycles: 9,
                                                       isPlaying: true,
                                                       now: 100.4,
                                                       window: 1.5)
               == .note(RenderLook(cycles: 9, at: 100.4), recheckAfter: nil),
               "an advancing count is healthy and needs no extra pass")
        suite.expect(MixerRoutingSupport.engineRenderVerdict(previous: RenderLook(cycles: 7, at: 100),
                                                       cycles: 7,
                                                       isPlaying: true,
                                                       now: 100.5,
                                                       window: 1.5)
               == .stalled(recheckAfter: 1.0),
               "a count at rest inside the window waits out the remainder")
        suite.expect(MixerRoutingSupport.engineRenderVerdict(previous: RenderLook(cycles: 7, at: 100),
                                                       cycles: 7,
                                                       isPlaying: true,
                                                       now: 102,
                                                       window: 1.5) == .wedged,
               "a count at rest for the whole window while the app plays is wedged")
        suite.expect(MixerRoutingSupport.engineRenderVerdict(previous: RenderLook(cycles: 7, at: 101),
                                                       cycles: 7,
                                                       isPlaying: true,
                                                       now: 100,
                                                       window: 1.5)
               == .stalled(recheckAfter: 1.5),
               "a clock that jumps backwards waits a full window before judging")

        // The wedged tap that verdict tears down is also the one whose
        // `AudioHardwareDestroyProcessTap` parks inside the HAL. Serialized,
        // that one parked call held every later engine's aggregate and tap
        // alive behind it; unbounded, each one strands a worker of the shared
        // pool, which is issue #971's exhaustion. Read as source text because
        // the engine lives in a file the test target does not compile.
        let mixerCode = (try? String(
            contentsOfFile: "Sources/Vorssaint/Services/Audio/AppVolumeMixer.swift",
            encoding: .utf8)) ?? ""
        let teardownQueueSetup = mixerCode.range(of: "let teardownQueue").flatMap { start in
            mixerCode.range(of: "}()", range: start.upperBound..<mixerCode.endIndex)
                .map { String(mixerCode[start.upperBound..<$0.lowerBound]) }
        } ?? ""
        suite.expect(teardownQueueSetup.contains("maxConcurrentOperationCount"),
               "engine teardown runs on a queue with a concurrency bound, not one thread and not one per engine")

        // The IO callback's two exits, read the same way: a cycle that never
        // found its tap must hand the device silence rather than what the HAL
        // left in the buffer (issue #326), and must leave without counting
        // itself alive — a callback that resolved no tap has done nothing for
        // the app that a callback which never ran would not have done, and
        // `tapChannels` is read once when the engine is built, so input that
        // never carried that shape never will. Ordering alone would not say
        // that: a count inside the missed-tap branch also reads as "after the
        // lookup". The branch is cut out by brace matching and the two halves
        // are checked apart.
        let mixerBody = mixerCode
            .components(separatedBy: "\n")
            .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }
            .joined(separator: "\n")
        let missedTapBrace = mixerBody
            .range(of: "MixerRender.tapBufferIndex(in: inputBuffers")
            .flatMap { mixerBody.range(of: "else {", range: $0.upperBound..<mixerBody.endIndex) }
        var missedTapBranch = ""
        var afterMissedTap = ""
        if let missedTapBrace {
            var depth = 1
            var index = missedTapBrace.upperBound
            while index < mixerBody.endIndex, depth > 0 {
                if mixerBody[index] == "{" { depth += 1 }
                if mixerBody[index] == "}" { depth -= 1 }
                index = mixerBody.index(after: index)
            }
            if depth == 0 {
                missedTapBranch = String(mixerBody[missedTapBrace.upperBound..<mixerBody.index(before: index)])
                afterMissedTap = String(mixerBody[index...])
            }
        }
        suite.expect(missedTapBranch.contains("MixerRender.silence(outputBuffers)")
               && missedTapBranch.contains("return"),
               "a callback that finds no tap silences the output before it leaves")
        suite.expect(!missedTapBranch.isEmpty && !missedTapBranch.contains("cycles.increment()"),
               "a callback that finds no tap leaves without counting a cycle")
        let framesGuard = afterMissedTap.range(of: "guard frames > 0 else")?.upperBound
        let cycleCount = afterMissedTap.range(of: "cycles.increment()")?.lowerBound
        suite.expect(framesGuard != nil && cycleCount != nil && framesGuard! < cycleCount!,
               "a cycle is counted only once the engine has handed the device audio")

        let identifiedRow = MixerRoutingSupport.rowIdentity(bundleIdentifier: "com.example.Player",
                                                           ownerPid: 501,
                                                           displayName: "Player")
        suite.expect(identifiedRow.rowID == "com.example.Player"
               && identifiedRow.persistenceID == "com.example.Player",
               "an app with a bundle id keeps it as both row and storage identity")
        let namedRow = MixerRoutingSupport.rowIdentity(bundleIdentifier: nil,
                                                       ownerPid: 501,
                                                       displayName: "Retro Game")
        let otherNamedRow = MixerRoutingSupport.rowIdentity(bundleIdentifier: nil,
                                                            ownerPid: 502,
                                                            displayName: "Retro Game")
        suite.expect(namedRow.persistenceID == "Retro Game",
               "an app without a bundle id saves its volume under its display name, the same key older versions used")
        suite.expect(!namedRow.rowID.isEmpty && namedRow.rowID != otherNamedRow.rowID,
               "two same-named processes without a bundle id stay separate rows")
        let namelessRow = MixerRoutingSupport.rowIdentity(bundleIdentifier: nil,
                                                          ownerPid: 501,
                                                          displayName: nil)
        suite.expect(!namelessRow.rowID.isEmpty && namelessRow.persistenceID == nil,
               "a process with neither bundle id nor name is still listable but stores nothing")
        suite.expect(MixerRoutingSupport.rowIdentity(bundleIdentifier: "   ",
                                               ownerPid: 501,
                                               displayName: "  ").persistenceID == nil,
               "blank identifiers are not identities")

        suite.expect(MixerRoutingSupport.restorableInputDeviceUID(originalUID: "BuiltInMicrophoneDevice",
                                                            appliedUID: "USBMicrophone",
                                                            currentUID: "USBMicrophone",
                                                            availableUIDs: ["BuiltInMicrophoneDevice",
                                                                            "USBMicrophone"])
               == "BuiltInMicrophoneDevice",
               "the microphone the system had before the app changed it is put back")
        suite.expect(MixerRoutingSupport.restorableInputDeviceUID(originalUID: "BuiltInMicrophoneDevice",
                                                            appliedUID: "USBMicrophone",
                                                            currentUID: "HeadsetMicrophone",
                                                            availableUIDs: ["BuiltInMicrophoneDevice",
                                                                            "USBMicrophone"]) == nil,
               "a microphone chosen elsewhere since is left alone")
        suite.expect(MixerRoutingSupport.restorableInputDeviceUID(originalUID: "BuiltInMicrophoneDevice",
                                                            appliedUID: "USBMicrophone",
                                                            currentUID: "USBMicrophone",
                                                            availableUIDs: ["USBMicrophone"]) == nil,
               "a microphone that is gone is not restored")
        suite.expect(MixerRoutingSupport.restorableInputDeviceUID(originalUID: nil,
                                                            appliedUID: nil,
                                                            currentUID: "USBMicrophone",
                                                            availableUIDs: ["USBMicrophone"]) == nil,
               "nothing is restored when the app never changed the microphone")
        suite.expect(MixerRoutingSupport.shouldRestoreOutputVolume(appliedVolume: 0.25, currentVolume: 0.25),
               "a volume still at the value the app set goes back to what it was")
        suite.expect(!MixerRoutingSupport.shouldRestoreOutputVolume(appliedVolume: 0.25, currentVolume: 0.6),
               "a volume changed since the app lowered it is left alone")
        suite.expect(!MixerRoutingSupport.shouldRestoreOutputVolume(appliedVolume: 0.25, currentVolume: nil),
               "a volume that cannot be read is left alone")
        suite.expect(!MixerRoutingSupport.isHiddenFromMixer(
                    persistenceID: "com.apple.finder",
                    hiddenIDs: MixerRoutingSupport.hiddenRowIDs(hiddenApps: [:], showFinder: true)),
               "Finder shows in the mixer when enabled")
        suite.expect(MixerRoutingSupport.isHiddenFromMixer(
                    persistenceID: "com.apple.finder",
                    hiddenIDs: MixerRoutingSupport.hiddenRowIDs(hiddenApps: [:], showFinder: false)),
               "Finder can be hidden from the mixer")
        suite.expect(MixerRoutingSupport.isHiddenFromMixer(
                    persistenceID: "com.example.Player",
                    hiddenIDs: MixerRoutingSupport.hiddenRowIDs(
                        hiddenApps: ["com.example.Player": "Player"], showFinder: true)),
               "any app the user hid stays out of the mixer list")
        suite.expect(!MixerRoutingSupport.isHiddenFromMixer(
                    persistenceID: "com.example.Player",
                    hiddenIDs: MixerRoutingSupport.hiddenRowIDs(hiddenApps: [:], showFinder: false)),
               "hiding Finder leaves every other app visible")
        suite.expect(MixerRoutingSupport.isHiddenFromMixer(
                    persistenceID: "Bare Tool",
                    hiddenIDs: MixerRoutingSupport.hiddenRowIDs(
                        hiddenApps: ["Bare Tool": "Bare Tool"], showFinder: true)),
               "apps saved under a display name can be hidden too")
        suite.expect(!MixerRoutingSupport.isHiddenFromMixer(persistenceID: nil,
                                                      hiddenIDs: ["com.example.Player"]),
               "a row with nothing to remember it by is always listed")
        let hiddenSanitized = MixerRoutingSupport.sanitizedHiddenApps([
            "com.example.Player": "Player",
            "com.apple.finder": "Finder",
            "": "Nameless",
            "com.example.Silent": "",
            "com.example.Broken": 3,
        ])
        suite.expect(hiddenSanitized == ["com.example.Player": "Player"],
               "the hidden map keeps only real entries and never carries the Finder")
        suite.expect(MixerRoutingSupport.needsPersistentFinderRow(showFinder: true,
                                                            hasFinderRow: false),
               "Finder gets a persistent row before Quick Look opens")
        suite.expect(!MixerRoutingSupport.needsPersistentFinderRow(showFinder: true,
                                                             hasFinderRow: true)
                && !MixerRoutingSupport.needsPersistentFinderRow(showFinder: false,
                                                                 hasFinderRow: false),
               "Finder is never duplicated and stays absent when hidden")
        suite.expect(MixerRoutingSupport.bypassesProcessTap(bundleIdentifier: "us.zoom.xos", name: "zoom.us"),
               "Zoom is kept out of process-tap audio routing")
        suite.expect(MixerRoutingSupport.bypassesProcessTap(bundleIdentifier: "us.zoom.ZoomAutoUpdater", name: "Zoom"),
               "Zoom helper bundle ids are kept out of process-tap audio routing")
        suite.expect(!MixerRoutingSupport.bypassesProcessTap(bundleIdentifier: "com.apple.Safari", name: "Safari"),
               "regular apps remain eligible for process-tap audio routing")
        suite.expect(!MixerRoutingSupport.bypassesProcessTap(bundleIdentifier: nil, name: "Zoomable Notes"),
               "unrelated app names are not treated as Zoom")
        suite.expect(MixerRoutingSupport.bypassesProcessTap(bundleIdentifier: "com.apple.logic10", name: "Logic Pro"),
               "Logic Pro is kept out of process-tap audio routing")
        suite.expect(MixerRoutingSupport.bypassesProcessTap(bundleIdentifier: "com.ableton.live", name: "Live"),
               "Ableton Live is kept out of process-tap audio routing")
        suite.expect(MixerRoutingSupport.bypassesProcessTap(bundleIdentifier: "com.steinberg.cubase13", name: "Cubase"),
               "Cubase is kept out of process-tap audio routing")
        suite.expect(MixerRoutingSupport.bypassesProcessTap(bundleIdentifier: "com.presonus.studioone6", name: "Studio One"),
               "Studio One is kept out of process-tap audio routing")
        suite.expect(!MixerRoutingSupport.bypassesProcessTap(bundleIdentifier: "com.spotify.client", name: "Spotify"),
               "music players remain eligible for process-tap audio routing")
        suite.expect(MixerRoutingSupport.effectiveDeviceUID(selectedUID: "ExternalDisplay",
                                                      availableUIDs: ["BuiltInSpeakerDevice"],
                                                      defaultUID: "BuiltInSpeakerDevice") == "BuiltInSpeakerDevice",
               "missing saved output falls back to default")
        suite.expect(MixerRoutingSupport.selectedDeviceUnavailable(selectedUID: "ExternalDisplay",
                                                             availableUIDs: ["BuiltInSpeakerDevice"]),
               "missing saved output is marked unavailable without deleting the preference")
        let defaultInput = MixerRoutingSupport.resolveInputDevice(
            preferredUID: nil,
            availableUIDs: ["BuiltInMicrophoneDevice"],
            currentUID: "BuiltInMicrophoneDevice")
        suite.expect(defaultInput == MixerInputRouteResolution(effectiveUID: "BuiltInMicrophoneDevice",
                                                         selectedUnavailable: false,
                                                         shouldApplyPreferred: false),
               "no preferred input follows the current system input")
        let connectedPreferredInput = MixerRoutingSupport.resolveInputDevice(
            preferredUID: "StudioMic",
            availableUIDs: ["BuiltInMicrophoneDevice", "StudioMic"],
            currentUID: "BuiltInMicrophoneDevice")
        suite.expect(connectedPreferredInput == MixerInputRouteResolution(effectiveUID: "StudioMic",
                                                                    selectedUnavailable: false,
                                                                    shouldApplyPreferred: true),
               "connected preferred input is applied when different from current")
        let alreadyCurrentInput = MixerRoutingSupport.resolveInputDevice(
            preferredUID: "StudioMic",
            availableUIDs: ["BuiltInMicrophoneDevice", "StudioMic"],
            currentUID: "StudioMic")
        suite.expect(!alreadyCurrentInput.shouldApplyPreferred,
               "preferred input is not reapplied when already current")
        let disconnectedPreferredInput = MixerRoutingSupport.resolveInputDevice(
            preferredUID: "StudioMic",
            availableUIDs: ["BuiltInMicrophoneDevice"],
            currentUID: "BuiltInMicrophoneDevice")
        suite.expect(disconnectedPreferredInput == MixerInputRouteResolution(effectiveUID: "BuiltInMicrophoneDevice",
                                                                       selectedUnavailable: true,
                                                                       shouldApplyPreferred: false),
               "missing preferred input falls back visually without deleting preference")
        do {
            let original = ["app.a", "app.b", "app.c", "app.d"]
            var layout = MixerAppArrangement()
            suite.expect(layout.ordered(original, identity: { $0 }) == original,
                   "mixer keeps alphabetical input until the user arranges it")
            layout.move("app.c", offset: -1, visibleIDs: original)
            let arranged = ["app.a", "app.c", "app.b", "app.d"]
            suite.expect(layout.ordered(original, identity: { $0 }) == arranged,
                   "mixer moves an app to its chosen position")
            let reopened = MixerAppArrangement(rawValue: layout.rawValue)
            suite.expect(reopened.ordered(["app.a", "app.b", "app.d"], identity: { $0 }) == ["app.a", "app.b", "app.d"]
                   && reopened.ordered(original, identity: { $0 }) == arranged,
                   "closing and reopening an app or mixer preserves its position")
            layout.move("app.d", offset: -1, visibleIDs: ["app.a", "app.b", "app.d"])
            suite.expect(layout.ordered(original, identity: { $0 }) == ["app.a", "app.c", "app.d", "app.b"],
                   "reordering live rows preserves the slot of a closed or hidden app")
            layout.togglePin("app.b")
            layout.togglePin("app.d")
            suite.expect(layout.ordered(original, identity: { $0 }) == ["app.d", "app.b", "app.a", "app.c"],
                   "pinned apps lead the list while keeping their chosen order")
            layout.move("app.b", offset: -1, visibleIDs: layout.ordered(original, identity: { $0 }))
            suite.expect(layout.ordered(original, identity: { $0 }) == ["app.b", "app.d", "app.a", "app.c"],
                   "pinned apps can be rearranged independently")
            suite.expect(layout.neighbor(of: "app.d", offset: 1, visibleIDs: ["app.b", "app.d", "app.a", "app.c"]) == nil
                   && layout.neighbor(of: "app.a", offset: -1, visibleIDs: ["app.b", "app.d", "app.a", "app.c"]) == nil,
                   "reordering does not cross the pinned boundary")
            let saved = layout
            layout.move("missing", offset: -1, visibleIDs: original)
            suite.expect(layout == saved, "a vanished row cannot overwrite the saved arrangement")
            layout.togglePin("app.b")
            suite.expect(!layout.isPinned("app.b") && layout.isPinned("app.d"), "unpinning affects only the chosen app")
            suite.expect(layout.ordered(original + ["app.e"], identity: { $0 }).last == "app.e",
                   "new apps follow the remembered order")
            var dragged = MixerAppArrangement()
            dragged.move("app.a", to: "app.d", after: true, visibleIDs: original)
            suite.expect(dragged.ordered(original, identity: { $0 }) == ["app.b", "app.c", "app.d", "app.a"],
                   "one drag can insert the first app below the last app")
            dragged.move("app.a", to: "app.b", after: false,
                         visibleIDs: dragged.ordered(original, identity: { $0 }))
            suite.expect(dragged.ordered(original, identity: { $0 }) == original,
                   "one drag can insert an app above the first row")
            dragged.move("app.d", to: "app.a", after: false, visibleIDs: ["app.a", "app.c", "app.d"])
            suite.expect(dragged.ordered(original, identity: { $0 }) == ["app.d", "app.b", "app.a", "app.c"],
                   "a long drag leaves a closed app's remembered slot intact")
            let beforeInvalidDrop = dragged
            dragged.move("app.a", to: "missing", after: false, visibleIDs: original)
            dragged.move("missing", to: "app.a", after: true, visibleIDs: original)
            dragged.move("app.a", to: "app.a", after: false, visibleIDs: original)
            suite.expect(dragged == beforeInvalidDrop, "missing or same-row drop targets do not change preferences")
            dragged.togglePin("app.d")
            let beforeCrossGroupDrop = dragged
            dragged.move("app.a", to: "app.d", after: false, visibleIDs: original)
            suite.expect(dragged == beforeCrossGroupDrop, "dragging does not silently pin or unpin an app")
            let malformed = MixerAppArrangement(rawValue: "invalid")
            suite.expect(malformed == MixerAppArrangement(), "invalid saved arrangement falls back safely")
            let duplicate = MixerAppArrangement(rawValue: #"{"order":["app.b","app.b","","app.a"],"pinned":["app.b","app.b",""]}"#)
            suite.expect(duplicate.order == ["app.b", "app.a"] && duplicate.pinned == ["app.b"],
                   "restored arrangement removes duplicate and empty identities")
            suite.expect(Defaults.registeredDefaults[DefaultsKey.mixerAppArrangement] as? String == ""
                   && SettingsBackupSupport.exportKeys().contains(DefaultsKey.mixerAppArrangement),
                   "mixer arrangement is opt-in and included in settings backups")
            let payload = SettingsBackupSupport.payload(appVersion: "test") { key in
                key == DefaultsKey.mixerAppArrangement ? saved.rawValue : nil
            }
            let data = try? PropertyListSerialization.data(fromPropertyList: payload, format: .xml, options: 0)
            let plist = data.flatMap { try? PropertyListSerialization.propertyList(from: $0, format: nil) } as? [String: Any]
            let restored = plist.flatMap { SettingsBackupSupport.sanitizedSettings(from: $0) }
            let restoredLayout = MixerAppArrangement(rawValue: restored?[DefaultsKey.mixerAppArrangement] as? String ?? "")
            suite.expect(restoredLayout == saved && restoredLayout.ordered(original, identity: { $0 }) == ["app.b", "app.d", "app.a", "app.c"],
                   "export and import preserve both pins and positions, including absent apps")
            suite.expect(!SettingsBackupSupport.valueLooksRight(DefaultsKey.mixerAppArrangement, ["invalid"]),
                   "backup rejects an arrangement with the wrong storage type")
        }

        suite.expect(MixerRoutingSupport.displayOrderedBefore(name: "Music", id: "com.apple.Music",
                                                        otherName: "Safari", otherID: "com.apple.Safari"),
               "mixer rows order by display name")
        suite.expect(MixerRoutingSupport.displayOrderedBefore(name: "safari", id: "a",
                                                        otherName: "Safari", otherID: "b")
                   && !MixerRoutingSupport.displayOrderedBefore(name: "Safari", id: "b",
                                                                otherName: "safari", otherID: "a"),
               "mixer rows with equal names order deterministically by id")
        suite.expect(MixerRoutingSupport.deviceDisplayOrderedBefore(isDefault: true, name: "Zeta", uid: "z",
                                                              otherIsDefault: false, otherName: "Alpha",
                                                              otherUID: "a"),
               "the default device orders before any other device")
        suite.expect(MixerRoutingSupport.deviceDisplayOrderedBefore(isDefault: false, name: "AirPods Pro", uid: "aa",
                                                              otherIsDefault: false, otherName: "AirPods Pro",
                                                              otherUID: "bb")
                   && !MixerRoutingSupport.deviceDisplayOrderedBefore(isDefault: false, name: "AirPods Pro",
                                                                      uid: "bb",
                                                                      otherIsDefault: false,
                                                                      otherName: "AirPods Pro",
                                                                      otherUID: "aa"),
               "identically named devices order deterministically by uid")

        // MARK: Boost limiter (issue #326)

        // A boost above 100% used to clamp overshooting samples, flattening
        // every peak into crackle. The limiter must cap peaks without touching
        // audio that already fits, and its gain must ride across buffers.

        func sine(amplitude: Float, frames: Int, channels: Int = 1) -> [Float] {
            var samples = [Float](repeating: 0, count: frames * channels)
            for frame in 0..<frames {
                let value = amplitude * Float(sin(2 * Double.pi * 440 * Double(frame) / 48000))
                for channel in 0..<channels { samples[frame * channels + channel] = value }
            }
            return samples
        }
        func limited(_ samples: [Float], channels: Int = 1,
                     release: Float = BoostLimiter.release(sampleRate: 48000),
                     with limiter: inout BoostLimiter) -> [Float] {
            var output = samples
            output.withUnsafeMutableBufferPointer { buffer in
                limiter.process(buffer.baseAddress!,
                                frames: samples.count / channels,
                                channels: channels,
                                release: release)
            }
            return output
        }

        var quietLimiter = BoostLimiter()
        let quiet = sine(amplitude: 0.6, frames: 4800)
        suite.expect(limited(quiet, with: &quietLimiter) == quiet,
               "audio inside the ceiling passes through bit-identical")

        var loudLimiter = BoostLimiter()
        let loud = limited(sine(amplitude: 1.5, frames: 9600), with: &loudLimiter)
        suite.expect(loud.allSatisfy { abs($0) <= BoostLimiter.ceiling + 0.0001 },
               "boosted peaks never leave the ceiling")
        let steady = loud.dropFirst(4800)
        let pinned = steady.filter { abs($0) >= BoostLimiter.ceiling - 0.001 }.count
        suite.expect(pinned < steady.count / 5,
               "the limiter rides the level instead of flattening the wave into clipping")

        var recoveryLimiter = BoostLimiter()
        _ = limited(sine(amplitude: 1.5, frames: 4800), with: &recoveryLimiter)
        let afterLoud = limited(sine(amplitude: 0.5, frames: 48000), with: &recoveryLimiter)
        suite.expect(afterLoud.prefix(480).max()! < 0.45,
               "right after a loud stretch the gain is still turned down")
        suite.expect(afterLoud.suffix(4800).max()! > 0.499,
               "the gain recovers to unity once the audio gets quiet")

        var wholeLimiter = BoostLimiter()
        var chunkedLimiter = BoostLimiter()
        let long = sine(amplitude: 1.5, frames: 2048)
        let whole = limited(long, with: &wholeLimiter)
        let chunked = limited(Array(long[0..<1024]), with: &chunkedLimiter)
            + limited(Array(long[1024...]), with: &chunkedLimiter)
        suite.expect(whole == chunked,
               "splitting the stream into buffers does not change the result")

        var stereoLimiter = BoostLimiter()
        var stereo = [Float](repeating: 0, count: 9600 * 2)
        for frame in 0..<9600 {
            let value = Float(sin(2 * Double.pi * 440 * Double(frame) / 48000))
            stereo[frame * 2] = 1.5 * value
            stereo[frame * 2 + 1] = 0.75 * value
        }
        let linked = limited(stereo, channels: 2, with: &stereoLimiter)
        var stereoLinked = true
        for frame in 0..<9600 where abs(linked[frame * 2 + 1] - linked[frame * 2] / 2) > 0.0001 {
            stereoLinked = false
            break
        }
        suite.expect(stereoLinked,
               "both channels of a frame share one gain so the stereo image stays put")

        var lookaheadInput = sine(amplitude: 1.5, frames: 9600)
        let lookahead = BoostLookaheadLimiter(channels: 1)
        _ = lookaheadInput.withUnsafeMutableBufferPointer { buffer in
            lookahead.process(buffer.baseAddress!, frames: buffer.count, channels: 1,
                              release: BoostLimiter.release(sampleRate: 48000))
        }
        let delayedSine = Array(repeating: Float(0), count: BoostLookaheadLimiter.lookaheadFrames)
            + Array(sine(amplitude: BoostLimiter.ceiling,
                         frames: 9600 - BoostLookaheadLimiter.lookaheadFrames))
        suite.expect(lookaheadInput.allSatisfy { abs($0) <= BoostLimiter.ceiling + 0.0001 },
               "lookahead keeps every boosted sample inside the output range")
        suite.expect(zip(lookaheadInput.dropFirst(960), delayedSine.dropFirst(960)).allSatisfy {
            abs($0 - $1) < 0.0001
        }, "lookahead preserves a steady loud waveform instead of reshaping its peaks")

        var quietLookahead = sine(amplitude: 0.6, frames: 2048)
        let quietLookaheadSource = quietLookahead
        let quietLookaheadLimiter = BoostLookaheadLimiter(channels: 1)
        _ = quietLookahead.withUnsafeMutableBufferPointer { buffer in
            quietLookaheadLimiter.process(buffer.baseAddress!, frames: buffer.count, channels: 1,
                                          release: BoostLimiter.release(sampleRate: 48000))
        }
        suite.expect(Array(quietLookahead.prefix(BoostLookaheadLimiter.lookaheadFrames))
                == Array(repeating: 0, count: BoostLookaheadLimiter.lookaheadFrames)
            && Array(quietLookahead.dropFirst(BoostLookaheadLimiter.lookaheadFrames))
                == Array(quietLookaheadSource.dropLast(BoostLookaheadLimiter.lookaheadFrames)),
               "quiet routed audio stays bit-identical after the fixed lookahead delay")

        let lookaheadSource = sine(amplitude: 1.5, frames: 4096)
        var wholeLookahead = lookaheadSource
        let wholeLookaheadLimiter = BoostLookaheadLimiter(channels: 1)
        _ = wholeLookahead.withUnsafeMutableBufferPointer { buffer in
            wholeLookaheadLimiter.process(buffer.baseAddress!, frames: buffer.count, channels: 1,
                                          release: BoostLimiter.release(sampleRate: 48000))
        }
        let chunkedLookaheadLimiter = BoostLookaheadLimiter(channels: 1)
        var chunkedLookahead = [Float]()
        for sourceChunk in [Array(lookaheadSource[0..<511]),
                            Array(lookaheadSource[511..<1537]),
                            Array(lookaheadSource[1537...])] {
            var chunk = sourceChunk
            _ = chunk.withUnsafeMutableBufferPointer { buffer in
                chunkedLookaheadLimiter.process(buffer.baseAddress!, frames: buffer.count,
                                                channels: 1,
                                                release: BoostLimiter.release(sampleRate: 48000))
            }
            chunkedLookahead += chunk
        }
        suite.expect(wholeLookahead == chunkedLookahead,
               "lookahead produces the same signal across realtime buffer boundaries")

        var impulseTrain = [Float](repeating: 0.2, count: 4096)
        for frame in stride(from: 256, to: impulseTrain.count, by: 173) {
            impulseTrain[frame] = frame.isMultiple(of: 2) ? 2 : -2
        }
        let impulseLimiter = BoostLookaheadLimiter(channels: 1)
        _ = impulseTrain.withUnsafeMutableBufferPointer { buffer in
            impulseLimiter.process(buffer.baseAddress!, frames: buffer.count, channels: 1,
                                   release: BoostLimiter.release(sampleRate: 48000))
        }
        suite.expect(impulseTrain.allSatisfy { abs($0) <= BoostLimiter.ceiling + 0.0001 },
               "overlapping future peaks are attenuated before they reach the output")

        var lookaheadStereo = [Float](repeating: 0, count: 4096 * 2)
        for frame in 0..<4096 {
            let value = Float(sin(2 * Double.pi * 440 * Double(frame) / 48000))
            lookaheadStereo[frame * 2] = 1.5 * value
            lookaheadStereo[frame * 2 + 1] = 0.75 * value
        }
        let stereoLookaheadLimiter = BoostLookaheadLimiter(channels: 2)
        _ = lookaheadStereo.withUnsafeMutableBufferPointer { buffer in
            stereoLookaheadLimiter.process(buffer.baseAddress!, frames: buffer.count / 2,
                                           channels: 2,
                                           release: BoostLimiter.release(sampleRate: 48000))
        }
        suite.expect((BoostLookaheadLimiter.lookaheadFrames..<4096).allSatisfy { frame in
            abs(lookaheadStereo[frame * 2 + 1] - lookaheadStereo[frame * 2] / 2) < 0.0001
        }, "lookahead applies one gain to every channel in a frame")

        func planarLookahead(_ sources: [[Float]], capacity: Int)
            -> (handled: Bool, output: [[Float]]) {
            let frames = sources.map(\.count).min() ?? 0
            let pointers = sources.map { source -> UnsafeMutablePointer<Float> in
                let pointer = UnsafeMutablePointer<Float>.allocate(capacity: max(1, source.count))
                pointer.update(from: source, count: source.count)
                return pointer
            }
            let list = AudioBufferList.allocate(maximumBuffers: max(1, sources.count))
            for index in sources.indices {
                list[index] = AudioBuffer(
                    mNumberChannels: 1,
                    mDataByteSize: UInt32(frames * MemoryLayout<Float>.size),
                    mData: pointers[index])
            }
            let limiter = BoostLookaheadBufferListLimiter(channelCapacity: capacity)
            let handled = limiter.process(list, frames: frames,
                                          release: BoostLimiter.release(sampleRate: 48_000))
            let output = pointers.map { Array(UnsafeBufferPointer(start: $0, count: frames)) }
            pointers.forEach { $0.deallocate() }
            free(list.unsafeMutablePointer)
            return (handled, output)
        }
        let planarFrames = 1_024
        let planarWave = (0..<planarFrames).map {
            Float(sin(2 * Double.pi * 440 * Double($0) / 48_000))
        }
        let planarStereo = planarLookahead(
            [planarWave.map { $0 * 1.5 }, planarWave.map { $0 * 0.5 }], capacity: 2)
        suite.expect(planarStereo.handled
                && (BoostLookaheadLimiter.lookaheadFrames..<planarFrames).allSatisfy { frame in
                    abs(planarStereo.output[1][frame] - planarStereo.output[0][frame] / 3) < 0.0001
                },
               "non-interleaved stereo buffers share one lookahead gain")
        let ninePlanar = planarLookahead(
            (1...9).map { channel in
                Array(repeating: Float(channel) / 20, count: 512)
            }, capacity: 9)
        let thirtyThreePlanar = planarLookahead(
            (1...33).map { _ in Array(repeating: Float(0.2), count: 300) }, capacity: 33)
        suite.expect(ninePlanar.handled && thirtyThreePlanar.handled
                && ninePlanar.output.allSatisfy {
                    Array($0.prefix(BoostLookaheadLimiter.lookaheadFrames))
                        == Array(repeating: 0, count: BoostLookaheadLimiter.lookaheadFrames)
                },
               "lookahead keeps one latency across nine buffers and 33 channels")

        var changedChannels = [Float](repeating: 0.4, count: 16)
        let adaptableLimiter = BoostLookaheadLimiter(channels: 2)
        let changedChannelsWereHandled = changedChannels.withUnsafeMutableBufferPointer { buffer in
            adaptableLimiter.process(
                buffer.baseAddress!, frames: 8, channels: 2,
                release: BoostLimiter.release(sampleRate: 48000))
        }
        suite.expect(changedChannelsWereHandled,
               "a stream shape change reuses the preallocated lookahead storage")

        var tooManyChannels = [Float](repeating: 1.2, count: 24)
        let overflowWasHandled = tooManyChannels.withUnsafeMutableBufferPointer { buffer in
            BoostLookaheadLimiter(channels: 2).process(
                buffer.baseAddress!, frames: 8, channels: 3,
                release: BoostLimiter.release(sampleRate: 48000))
        }
        suite.expect(!overflowWasHandled && tooManyChannels.allSatisfy { $0 == 1.2 },
               "a stream larger than the preallocated capacity falls through safely")

        var fallbackLimiter = BoostLimiter()
        let fallbackLimited = limited(sine(amplitude: 1.5, frames: 480),
                                      release: BoostLimiter.release(sampleRate: 0),
                                      with: &fallbackLimiter)
        suite.expect(fallbackLimited.allSatisfy { abs($0) <= BoostLimiter.ceiling + 0.0001 },
               "an unreadable sample rate still limits at the common device rate")

        // A headset that takes the microphone for a call changes the rate the
        // device runs at while the audio path stays up. The recovery has to
        // stay the same length of time, not the same number of samples.

        /// How many seconds the gain takes to come back after a loud stretch.
        func recoverySeconds(rate: Double, release: Float) -> Double {
            var limiter = BoostLimiter()
            let step = max(Int(rate / 1000), 1)
            func tone(_ amplitude: Float, seconds: Double) -> [Float] {
                let frames = Int(rate * seconds)
                var samples = [Float](repeating: 0, count: frames)
                for frame in 0..<frames {
                    samples[frame] = amplitude * Float(sin(2 * Double.pi * 440 * Double(frame) / rate))
                }
                return samples
            }
            _ = limited(tone(1.5, seconds: 0.1), release: release, with: &limiter)
            let quiet = limited(tone(0.5, seconds: 1.0), release: release, with: &limiter)
            let peaks = stride(from: 0, to: quiet.count, by: step).map { start in
                quiet[start..<min(start + step, quiet.count)].map { abs($0) }.max() ?? 0
            }
            guard let recovered = peaks.firstIndex(where: { $0 > 0.499 }) else { return .infinity }
            return Double(recovered) / 1000
        }

        let releaseAt48k = BoostLimiter.release(sampleRate: 48000)
        let releaseAt16k = BoostLimiter.release(sampleRate: 16000)
        suite.expect(releaseAt16k < releaseAt48k,
               "a slower rate keeps less of the previous level in each sample")

        let recoveryAt48k = recoverySeconds(rate: 48000, release: releaseAt48k)
        let recoveryAt16k = recoverySeconds(rate: 16000, release: releaseAt16k)
        suite.expect(abs(recoveryAt16k - recoveryAt48k) < 0.02,
               "the gain takes the same time to come back whatever rate the device runs at")

        // The defect this replaced: the figure was worked out once when the
        // engine was built, so a device that changed rate afterwards recovered
        // at the wrong speed for as long as it kept playing.
        let staleRecovery = recoverySeconds(rate: 16000, release: releaseAt48k)
        suite.expect(staleRecovery > recoveryAt16k * 2,
               "keeping the old rate's figure after a change drags the recovery out")

        // MARK: Mixer render (issue #397)

        // The tap always hands over two interleaved channels; the device on
        // the other side does not have to match. Pouring stereo into a
        // headset's single channel used to copy every sample straight across,
        // which plays the audio an octave low and half as long.

        /// Runs `render` over freshly allocated buffers and hands back what
        /// each output buffer received, plus the frame count it reported.
        var renderedFrames = 0
        func rendered(source: [Float], sourceChannels: UInt32,
                      outputs: [(channels: UInt32, frames: Int)],
                      gain: Float = 1) -> [[Float]] {
            let sourceStorage = UnsafeMutablePointer<Float>.allocate(capacity: max(source.count, 1))
            sourceStorage.update(from: source, count: source.count)
            var storages: [UnsafeMutablePointer<Float>] = []
            let list = AudioBufferList.allocate(maximumBuffers: max(outputs.count, 1))
            for (index, output) in outputs.enumerated() {
                let count = max(output.frames * Int(output.channels), 1)
                let storage = UnsafeMutablePointer<Float>.allocate(capacity: count)
                storage.update(repeating: -99, count: count)
                storages.append(storage)
                list[index] = AudioBuffer(
                    mNumberChannels: output.channels,
                    mDataByteSize: UInt32(output.frames * Int(output.channels) * MemoryLayout<Float>.size),
                    mData: UnsafeMutableRawPointer(storage))
            }
            let buffer = AudioBuffer(
                mNumberChannels: sourceChannels,
                mDataByteSize: UInt32(source.count * MemoryLayout<Float>.size),
                mData: UnsafeMutableRawPointer(sourceStorage))
            renderedFrames = MixerRender.render(source: buffer, into: list, gain: gain)
            var results: [[Float]] = []
            for (index, output) in outputs.enumerated() {
                let count = output.frames * Int(output.channels)
                results.append(Array(UnsafeBufferPointer(start: storages[index], count: count)))
            }
            storages.forEach { $0.deallocate() }
            sourceStorage.deallocate()
            free(list.unsafeMutablePointer)
            return results
        }

        /// Positive-going zero crossings, the cheap way to hear speed change.
        func crossings(_ samples: [Float], channels: Int) -> Int {
            var count = 0
            var previous: Float = 0
            for frame in 0..<(samples.count / channels) {
                let value = samples[frame * channels]
                if previous <= 0, value > 0 { count += 1 }
                previous = value
            }
            return count
        }

        suite.expect(MixerRender.frames(bytes: 4096, channels: 2) == 512,
               "a stereo buffer of 4096 bytes carries 512 frames")
        suite.expect(MixerRender.frames(bytes: 2048, channels: 1) == 512,
               "a mono buffer of 2048 bytes carries the same 512 frames")
        suite.expect(MixerRender.frames(bytes: 4096, channels: 0) == 0,
               "a buffer with no channels carries nothing")
        let missingOutputSource = UnsafeMutablePointer<Float>.allocate(capacity: 2)
        missingOutputSource.initialize(repeating: 0.5, count: 2)
        let missingOutputList = AudioBufferList.allocate(maximumBuffers: 1)
        missingOutputList[0] = AudioBuffer(mNumberChannels: 2,
                                           mDataByteSize: 2 * UInt32(MemoryLayout<Float>.size),
                                           mData: nil)
        let missingOutputFrames = MixerRender.render(
            source: AudioBuffer(mNumberChannels: 2,
                                mDataByteSize: 2 * UInt32(MemoryLayout<Float>.size),
                                mData: missingOutputSource),
            into: missingOutputList,
            gain: 1)
        suite.expect(missingOutputFrames == 0,
               "mixer progress advances only when a destination received audio")
        missingOutputSource.deallocate()
        free(missingOutputList.unsafeMutablePointer)

        let unmappedOutputSource = UnsafeMutablePointer<Float>.allocate(capacity: 2)
        unmappedOutputSource.initialize(repeating: 0.5, count: 2)
        let unmappedOutputDestination = UnsafeMutablePointer<Float>.allocate(capacity: 1)
        unmappedOutputDestination.initialize(to: -99)
        let unmappedOutputList = AudioBufferList.allocate(maximumBuffers: 2)
        unmappedOutputList[0] = AudioBuffer(
            mNumberChannels: 2,
            mDataByteSize: 2 * UInt32(MemoryLayout<Float>.size),
            mData: nil)
        unmappedOutputList[1] = AudioBuffer(
            mNumberChannels: 1,
            mDataByteSize: UInt32(MemoryLayout<Float>.size),
            mData: unmappedOutputDestination)
        let unmappedOutputFrames = MixerRender.render(
            source: AudioBuffer(mNumberChannels: 2,
                                mDataByteSize: 2 * UInt32(MemoryLayout<Float>.size),
                                mData: unmappedOutputSource),
            into: unmappedOutputList,
            gain: 1)
        suite.expect(unmappedOutputFrames == 0 && unmappedOutputDestination.pointee == 0,
               "a writable channel that can only receive silence does not advance mixer progress")
        unmappedOutputSource.deallocate()
        unmappedOutputDestination.deallocate()
        free(unmappedOutputList.unsafeMutablePointer)

        // MARK: Unwritten output frames (issue #326)

        // The output buffer arrives holding whatever CoreAudio last left in
        // that memory. A tap shorter than the buffer used to fill the front
        // and leave the rest, and a cycle that found no tap left the whole
        // buffer, so the device played back a fragment of older audio.
        let shortTap = rendered(source: [0.5, 0.5, 0.5, 0.5], sourceChannels: 2,
                                outputs: [(channels: 2, frames: 4)])[0]
        suite.expect(renderedFrames == 2,
               "a tap shorter than the output writes only the frames it has")
        suite.expect(shortTap == [0.5, 0.5, 0.5, 0.5, 0, 0, 0, 0],
               "the frames the tap could not fill are silenced, not left as the device found them")
        let splitTail = rendered(source: [0.5, 0.5], sourceChannels: 2,
                                 outputs: [(channels: 1, frames: 3), (channels: 1, frames: 3)])
        suite.expect(splitTail[0] == [0.5, 0, 0] && splitTail[1] == [0.5, 0, 0],
               "every buffer of a split output is silenced past the frames the tap filled")
        let staleOutput = UnsafeMutablePointer<Float>.allocate(capacity: 4)
        staleOutput.update(repeating: -99, count: 4)
        let staleList = AudioBufferList.allocate(maximumBuffers: 1)
        staleList[0] = AudioBuffer(mNumberChannels: 2,
                                   mDataByteSize: 4 * UInt32(MemoryLayout<Float>.size),
                                   mData: staleOutput)
        MixerRender.silence(staleList)
        suite.expect(Array(UnsafeBufferPointer(start: staleOutput, count: 4)) == [0, 0, 0, 0],
               "a cycle with no tap to read hands the device silence, not what it left behind")
        staleOutput.deallocate()
        free(staleList.unsafeMutablePointer)

        let toneFrames = 4800
        var toneStereo = [Float](repeating: 0, count: toneFrames * 2)
        for frame in 0..<toneFrames {
            let value = Float(sin(2 * Double.pi * 440 * Double(frame) / 48000))
            toneStereo[frame * 2] = value
            toneStereo[frame * 2 + 1] = value
        }
        let toneCrossings = crossings(toneStereo, channels: 2)

        let toMono = rendered(source: toneStereo, sourceChannels: 2,
                              outputs: [(channels: 1, frames: toneFrames)])[0]
        suite.expect(crossings(toMono, channels: 1) == toneCrossings,
               "a device with one channel plays the tapped audio at its own speed")
        var monoMatches = true
        for frame in 0..<toneFrames
        where abs(toMono[frame] - (toneStereo[frame * 2] + toneStereo[frame * 2 + 1]) / 2) > 0.0001 {
            monoMatches = false
            break
        }
        suite.expect(monoMatches, "one channel gets both sides of the stereo, averaged")

        let quieterMono = rendered(source: toneStereo, sourceChannels: 2,
                                   outputs: [(channels: 1, frames: toneFrames)], gain: 0.4)[0]
        var quieterMatches = true
        for frame in 0..<toneFrames where abs(quieterMono[frame] - toMono[frame] * 0.4) > 0.0001 {
            quieterMatches = false
            break
        }
        suite.expect(quieterMatches && quieterMono.map({ abs($0) }).max()! > 0.39,
               "the chosen volume still applies when the audio is folded to one channel")
        suite.expect(renderedFrames == toneFrames,
               "the fold reports every frame it wrote, which is what bounds the limiter")

        let toStereo = rendered(source: toneStereo, sourceChannels: 2,
                                outputs: [(channels: 2, frames: toneFrames)], gain: 0.5)[0]
        var stereoMatches = true
        for index in 0..<(toneFrames * 2) where abs(toStereo[index] - toneStereo[index] * 0.5) > 0.0001 {
            stereoMatches = false
            break
        }
        suite.expect(stereoMatches, "a stereo device still gets a plain scaled copy")

        let toSurround = rendered(source: [1, 2, 3, 4], sourceChannels: 2,
                                  outputs: [(channels: 4, frames: 2)])[0]
        suite.expect(toSurround == [1, 2, 0, 0, 3, 4, 0, 0],
               "a device with more channels than the tap fills the first pair and silences the rest")

        let split = rendered(source: [1, 2, 3, 4], sourceChannels: 2,
                             outputs: [(channels: 1, frames: 2), (channels: 1, frames: 2)])
        suite.expect(split == [[1, 3], [2, 4]],
               "a device that keeps its channels in separate buffers gets one channel each")

        let quieterSplit = rendered(source: [1, 2, 3, 4], sourceChannels: 2,
                                    outputs: [(channels: 1, frames: 2), (channels: 1, frames: 2)],
                                    gain: 0.5)
        suite.expect(quieterSplit == [[0.5, 1.5], [1, 2]],
               "the chosen volume applies to every channel a spread-out device carries")

        let quieterSurround = rendered(source: [1, 2, 3, 4], sourceChannels: 2,
                                       outputs: [(channels: 4, frames: 2)], gain: 0.5)[0]
        suite.expect(quieterSurround == [0.5, 1, 0, 0, 1.5, 2, 0, 0],
               "the chosen volume applies when the tap is spread over more channels")

        let fromMono = rendered(source: [1, 2], sourceChannels: 1,
                                outputs: [(channels: 2, frames: 2)])[0]
        suite.expect(fromMono == [1, 1, 2, 2],
               "a single-channel source is heard on both sides, not only the left")

        let shortOutput = rendered(source: [1, 2, 3, 4, 5, 6], sourceChannels: 2,
                                   outputs: [(channels: 2, frames: 2)])[0]
        suite.expect(shortOutput == [1, 2, 3, 4] && renderedFrames == 2,
               "an output buffer smaller than the tap's is filled without running past its end")

        let tapOnly = AudioBufferList.allocate(maximumBuffers: 2)
        let deviceInput = UnsafeMutablePointer<Float>.allocate(capacity: 1)
        let tapSamples = UnsafeMutablePointer<Float>.allocate(capacity: 2)
        defer {
            deviceInput.deallocate()
            tapSamples.deallocate()
        }
        tapOnly[0] = AudioBuffer(mNumberChannels: 1, mDataByteSize: 4,
                                 mData: UnsafeMutableRawPointer(deviceInput))
        tapOnly[1] = AudioBuffer(mNumberChannels: 2, mDataByteSize: 8,
                                 mData: UnsafeMutableRawPointer(tapSamples))
        suite.expect(MixerRender.tapBufferIndex(in: tapOnly, tapChannels: 2) == 1,
               "on an output device that also records, the tap is not the first buffer")
        suite.expect(MixerRender.tapBufferIndex(in: tapOnly, tapChannels: 1) == 0,
               "the tap is picked by the shape it announced, not by its position")
        suite.expect(MixerRender.tapBufferIndex(in: tapOnly, tapChannels: 7) == nil,
               "with nothing matching the tap, the microphone is never played out of the speakers")
        tapOnly[1] = AudioBuffer(mNumberChannels: 2, mDataByteSize: 8, mData: nil)
        suite.expect(MixerRender.tapBufferIndex(in: tapOnly, tapChannels: 2) == nil,
               "a buffer with no samples is never mistaken for the tap")
        free(tapOnly.unsafeMutablePointer)

        let lonely = AudioBufferList.allocate(maximumBuffers: 1)
        lonely[0] = AudioBuffer(mNumberChannels: 2, mDataByteSize: 8,
                                mData: UnsafeMutableRawPointer(tapSamples))
        suite.expect(MixerRender.tapBufferIndex(in: lonely, tapChannels: 7) == 0,
               "an output device with nothing of its own leaves only the tap to render")
        free(lonely.unsafeMutablePointer)

        suite.expect(MixerRender.sourceChannel(for: 0, sourceChannels: 2) == 0
            && MixerRender.sourceChannel(for: 1, sourceChannels: 2) == 1,
               "stereo feeds the first two channels in order")
        suite.expect(MixerRender.sourceChannel(for: 2, sourceChannels: 2) == nil,
               "channels the tap cannot fill stay silent")
        suite.expect(MixerRender.sourceChannel(for: 1, sourceChannels: 1) == 0,
               "a single channel is copied to the right as well as the left")


        // The rail's labels and glyphs name a screen direction, so a mirrored
        // rail has to move the opposite way through the order to obey them.
        suite.expect(MixerReorderDirection.offset(towardTrailingEdge: true, rightToLeft: false) == 1
                     && MixerReorderDirection.offset(towardTrailingEdge: true, rightToLeft: true) == -1,
                     "move right walks the order the way the rail is drawn")
        // The insertion marker is placed with .trailing and mirrors on its own,
        // so the drop side has to mirror with it or the two disagree.
        suite.expect(MixerReorderDirection.dropsAfter(pointerBeyondMidpoint: true, sideways: true, rightToLeft: true) == false
                     && MixerReorderDirection.dropsAfter(pointerBeyondMidpoint: false, sideways: true, rightToLeft: true) == true,
                     "a mirrored rail drops after on the leading half")
        suite.expect(MixerReorderDirection.dropsAfter(pointerBeyondMidpoint: true, sideways: false, rightToLeft: true) == true
                     && MixerReorderDirection.dropsAfter(pointerBeyondMidpoint: true, sideways: true, rightToLeft: false) == true,
                     "a vertical rail and an unmirrored one keep the side they had")
    }
}
