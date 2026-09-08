// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import Foundation

enum MixerTests {
    static func run(expect: (Bool, String) -> Void) {
        func expectClose(_ actual: Double, _ expected: Double, _ label: String, tol: Double = 0.0001) {
            expect(!(abs(actual - expected) > tol), "\(label): got \(actual), expected \(expected)")
        }

        expectClose(Defaults.sanitizedAppVolume(1.5), 1.5, "valid app volume is preserved")
        expectClose(Defaults.sanitizedAppVolume(3), 2, "high app volume clamps to boost maximum")
        expectClose(Defaults.sanitizedAppVolume(-1), 0, "negative app volume clamps to mute")
        expectClose(Defaults.sanitizedAppVolume(.infinity), 1, "non-finite app volume falls back to unity")
        expectClose(MixerRoutingSupport.volumeFraction(fromPercentageText: "40",
                                                       maximumPercent: 200) ?? -1,
                    0.4,
                    "mixer percentage input becomes app gain")
        expectClose(MixerRoutingSupport.volumeFraction(fromPercentageText: " 75% ",
                                                       maximumPercent: 100) ?? -1,
                    0.75,
                    "mixer percentage input accepts a percent sign")
        expectClose(MixerRoutingSupport.volumeFraction(fromPercentageText: "250",
                                                       maximumPercent: 200) ?? -1,
                    2,
                    "mixer percentage input clamps to the row maximum")
        expectClose(MixerRoutingSupport.volumeFraction(fromPercentageText: "-10",
                                                       maximumPercent: 100) ?? -1,
                    0,
                    "mixer percentage input clamps negative values")
        expect(MixerRoutingSupport.volumeFraction(fromPercentageText: "loud",
                                                  maximumPercent: 100) == nil,
               "mixer percentage input rejects non-numbers")
        expect(MixerRoutingSupport.volumeFraction(fromPercentageText: "nan",
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
        expect(percentFieldAttached,
               "mixer percentage field notices when it joins its popover window")
        expect(percentField.focusAndSelectAll(),
               "mixer percentage field becomes the native first responder")
        expect((percentField.currentEditor() as? NSTextView)?.selectedRange()
                == NSRange(location: 0, length: 2),
               "mixer percentage field selects its existing value for direct replacement")
        percentWindow.orderOut(nil)
        expect(Defaults.sanitizedMixerHeadphonesDisconnectVolumePercent(35) == 35,
               "headphone disconnect volume preserves valid percentages")
        expect(Defaults.sanitizedMixerHeadphonesDisconnectVolumePercent(-5)
               == Defaults.minimumMixerHeadphonesDisconnectVolumePercent,
               "headphone disconnect volume never drops below the audible floor")
        expect(Defaults.sanitizedMixerHeadphonesDisconnectVolumePercent(0)
               == Defaults.minimumMixerHeadphonesDisconnectVolumePercent,
               "headphone disconnect protection lowers the speakers, it never silences them")
        expect(Defaults.sanitizedMixerHeadphonesDisconnectVolumePercent(105) == 100,
               "headphone disconnect volume clamps high values")
        let headphonesSuite = "vorss.tests.mixer.headphones"
        if let silentHeadphoneVolume = UserDefaults(suiteName: headphonesSuite) {
            silentHeadphoneVolume.removePersistentDomain(forName: headphonesSuite)
            silentHeadphoneVolume.set(0, forKey: DefaultsKey.mixerHeadphonesDisconnectVolumePercent)
            Defaults.migrateSilentHeadphonesDisconnectVolume(in: silentHeadphoneVolume)
            expect(silentHeadphoneVolume.integer(forKey: DefaultsKey.mixerHeadphonesDisconnectVolumePercent)
                   == Defaults.defaultMixerHeadphonesDisconnectVolumePercent,
                   "a stored volume of zero from the first release of the option migrates to the default")
            silentHeadphoneVolume.set(60, forKey: DefaultsKey.mixerHeadphonesDisconnectVolumePercent)
            Defaults.migrateSilentHeadphonesDisconnectVolume(in: silentHeadphoneVolume)
            expect(silentHeadphoneVolume.integer(forKey: DefaultsKey.mixerHeadphonesDisconnectVolumePercent) == 60,
                   "a volume the user chose is never migrated")
            silentHeadphoneVolume.removePersistentDomain(forName: headphonesSuite)
        }
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
        expect(Defaults.sanitizedSoundOutputSwitcherDeviceUIDs([
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
        expect(MixerRoutingSupport.nextSelectedOutputDeviceUID(
            currentUID: "BuiltInSpeakerDevice",
            selectedUIDs: ["BuiltInSpeakerDevice", "ExternalDisplay"],
            availableUIDs: ["BuiltInSpeakerDevice", "ExternalDisplay"]) == "ExternalDisplay",
               "sound output switcher moves from the current selected output to the next")
        expect(MixerRoutingSupport.nextSelectedOutputDeviceUID(
            currentUID: "ExternalDisplay",
            selectedUIDs: ["BuiltInSpeakerDevice", "ExternalDisplay"],
            availableUIDs: ["BuiltInSpeakerDevice", "ExternalDisplay"]) == "BuiltInSpeakerDevice",
               "sound output switcher wraps selected outputs")
        expect(MixerRoutingSupport.nextSelectedOutputDeviceUID(
            currentUID: "USBHeadphones",
            selectedUIDs: ["BuiltInSpeakerDevice", "ExternalDisplay"],
            availableUIDs: ["BuiltInSpeakerDevice", "ExternalDisplay"]) == "BuiltInSpeakerDevice",
               "sound output switcher starts at the first selected output when current is outside the cycle")
        expect(MixerRoutingSupport.nextSelectedOutputDeviceUID(
            currentUID: "BuiltInSpeakerDevice",
            selectedUIDs: ["BuiltInSpeakerDevice", "MissingDisplay", "ExternalDisplay"],
            availableUIDs: ["BuiltInSpeakerDevice", "ExternalDisplay"]) == "ExternalDisplay",
               "sound output switcher skips unavailable selected outputs")
        expect(MixerRoutingSupport.nextSelectedOutputDeviceUID(
            currentUID: "BuiltInSpeakerDevice",
            selectedUIDs: ["BuiltInSpeakerDevice"],
            availableUIDs: ["BuiltInSpeakerDevice"]) == nil,
               "sound output switcher does nothing when the only selected output is already current")
        expect(MixerRoutingSupport.outputLooksLikeHeadphones(name: "AirPods Pro",
                                                             uid: "",
                                                             dataSourceName: nil),
               "AirPods are treated as headphones")
        expect(MixerRoutingSupport.outputLooksLikeHeadphones(name: "Built-in Output",
                                                             uid: "",
                                                             dataSourceName: "Headphones"),
               "wired headphone data source is treated as headphones")
        expect(MixerRoutingSupport.outputLooksLikeHeadphones(name: "Sony WH-1000XM5",
                                                             uid: "",
                                                             dataSourceName: nil),
               "common Bluetooth headphone names are treated as headphones")
        expect(!MixerRoutingSupport.outputLooksLikeHeadphones(name: "MacBook Pro Speakers",
                                                              uid: "BuiltInSpeakerDevice",
                                                              dataSourceName: nil),
               "built-in speakers are not treated as headphones")
        expect(!MixerRoutingSupport.outputLooksLikeHeadphones(name: "JBL Flip",
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
        expect(owningApp(of: 100) == 100,
               "a responsible regular app is billed directly")
        expect(owningApp(of: 500) == 100,
               "a helper answering for itself is billed to the app that spawned it")
        expect(owningApp(of: 700) == nil,
               "daemons whose parent chain ends at launchd stay unlisted")
        expect(owningApp(of: 42) == nil,
               "a failed parent lookup stops the walk")
        expect(owningApp(of: 900) == nil,
               "the parent walk gives up beyond the depth cap")
        expect(owningApp(of: 902) == 100,
               "a regular app within the depth cap is still found")
        expect(owningApp(of: 0) == nil,
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
        expect(resolvedOwningApp(responsible: 700, pid: 500) == 100,
               "a helper whose responsibility returns a daemon still falls back to its parent app")
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
        expect(!MixerRoutingSupport.requiresEngine(hasAudioObjects: false,
                                                   volume: 0.5,
                                                   selectedOutputDeviceUID: nil,
                                                   targetOutputDeviceUID: "BuiltInSpeakerDevice",
                                                   defaultOutputDeviceUID: "BuiltInSpeakerDevice"),
               "a persistent mixer row waits for an audio connection before building a tap")
        expect(MixerRoutingSupport.shouldShowApp(isPlaying: false,
                                                 volume: 1,
                                                 selectedOutputDeviceUID: nil,
                                                 hideInactiveApps: false),
               "the inactive-app filter changes nothing until the user enables it")
        expect(!MixerRoutingSupport.shouldShowApp(isPlaying: false,
                                                  volume: 1,
                                                  selectedOutputDeviceUID: nil,
                                                  hideInactiveApps: true),
               "an idle uncustomized mixer app can be hidden")
        expect(MixerRoutingSupport.shouldShowApp(isPlaying: true,
                                                 volume: 1,
                                                 selectedOutputDeviceUID: nil,
                                                 hideInactiveApps: true),
               "a playing mixer app remains visible")
        expect(MixerRoutingSupport.shouldShowApp(isPlaying: false,
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
        expect(!MixerRoutingSupport.rowMayBeTapped(savedVolume: nil,
                                                   savedRouteUID: nil,
                                                   defaultOutputDeviceUID: "BuiltInSpeakerDevice"),
               "an app with no saved volume and no saved route is never tapped")
        expect(!MixerRoutingSupport.rowMayBeTapped(savedVolume: 1,
                                                   savedRouteUID: nil,
                                                   defaultOutputDeviceUID: "BuiltInSpeakerDevice"),
               "a row saved at 100 percent is never tapped")
        expect(!MixerRoutingSupport.rowMayBeTapped(savedVolume: nil,
                                                   savedRouteUID: "BuiltInSpeakerDevice",
                                                   defaultOutputDeviceUID: "BuiltInSpeakerDevice"),
               "a row routed to the device that is already the default is never tapped")
        expect(MixerRoutingSupport.rowMayBeTapped(savedVolume: 0.4,
                                                  savedRouteUID: nil,
                                                  defaultOutputDeviceUID: "BuiltInSpeakerDevice"),
               "a row the user turned down is tapped")
        expect(MixerRoutingSupport.rowMayBeTapped(savedVolume: nil,
                                                  savedRouteUID: "ExternalDisplay",
                                                  defaultOutputDeviceUID: "BuiltInSpeakerDevice"),
               "a row routed to another output is tapped")

        var mixerBuilds = MixerEngineBuilds()
        expect(mixerBuilds.isEmpty, "a mixer with nothing being built has no builds in flight")
        // No real token is ever negative, so the sentinel cannot pass a check.
        let firstBuild = mixerBuilds.begin("com.example.Player") ?? -1
        expect(firstBuild > 0, "the first engine build for a row starts")
        expect(mixerBuilds.begin("com.example.Player") == nil,
               "a second engine build for the same row is refused while one is in flight")
        expect(mixerBuilds.isCurrent("com.example.Player", token: firstBuild),
               "a build that nothing invalidated is the one to install")
        mixerBuilds.finish("com.example.Player", token: firstBuild)
        expect(mixerBuilds.isEmpty,
               "finishing a build frees the row for the next one")
        let staleBuild = mixerBuilds.begin("com.example.Player") ?? -1
        mixerBuilds.invalidateAll()
        expect(!mixerBuilds.isCurrent("com.example.Player", token: staleBuild),
               "an engine build that lands after everything was invalidated is discarded")
        let freshBuild = mixerBuilds.begin("com.example.Player") ?? -1
        expect(freshBuild > 0 && freshBuild != staleBuild
               && mixerBuilds.isCurrent("com.example.Player", token: freshBuild),
               "the build started after an invalidation is the one to install")
        mixerBuilds.finish("com.example.Player", token: staleBuild)
        expect(mixerBuilds.isCurrent("com.example.Player", token: freshBuild),
               "a stale build landing late leaves the current build alone")
        var manyBuilds = MixerEngineBuilds()
        let firstRow = manyBuilds.begin("com.example.Player") ?? -1
        let secondRow = manyBuilds.begin("com.example.Radio") ?? -1
        manyBuilds.invalidateAll()
        expect(manyBuilds.isEmpty,
               "invalidating clears every engine build in flight")
        expect(!manyBuilds.isCurrent("com.example.Player", token: firstRow)
               && !manyBuilds.isCurrent("com.example.Radio", token: secondRow),
               "one invalidation makes every row's build in flight stale")

        var mixerRecovery = MixerEngineRecovery()
        let firstAudioPath = MixerEngineRecovery.Configuration(objects: [41],
                                                                outputDeviceUID: "speaker-a")
        expect(mixerRecovery.allowsBuild("player", configuration: firstAudioPath),
               "a new mixer audio path may build")
        expect(mixerRecovery.recordFailure("player", configuration: firstAudioPath),
               "a dead mixer engine gets one replacement")
        expect(mixerRecovery.allowsBuild("player", configuration: firstAudioPath),
               "the one replacement may build")
        expect(!mixerRecovery.recordFailure("player", configuration: firstAudioPath)
               && !mixerRecovery.allowsBuild("player", configuration: firstAudioPath),
               "the same dead replacement stays untapped instead of muting forever")
        let changedAudioPath = MixerEngineRecovery.Configuration(objects: [42],
                                                                  outputDeviceUID: "speaker-a")
        expect(mixerRecovery.allowsBuild("player", configuration: changedAudioPath),
               "a new audio object gets its own recovery attempt")
        mixerRecovery.clear("player")
        expect(mixerRecovery.allowsBuild("player", configuration: firstAudioPath),
               "an explicit mixer change re-enables the audio path")

        var refreshes = MixerRefreshCoordinator()
        expect(!refreshes.isReading, "a mixer that is not reading the audio devices holds no slot")
        // No real generation is ever negative, so the sentinel cannot pass.
        let firstRefresh = refreshes.begin() ?? -1
        expect(firstRefresh > 0 && refreshes.isReading, "the first refresh takes the slot")
        expect(refreshes.begin() == nil,
               "a second refresh is refused while one is still reading the audio devices")
        expect(refreshes.takeRepeatRequest(),
               "the refused refresh is remembered so nothing asked for is lost")
        expect(!refreshes.takeRepeatRequest(),
               "a remembered refresh runs once, not on every landing")
        expect(refreshes.finish(firstRefresh), "the refresh that owns the slot publishes what it read")
        expect(!refreshes.isReading, "finishing a refresh frees the slot for the next one")
        let secondRefresh = refreshes.begin() ?? -1
        expect(secondRefresh > firstRefresh, "generations move forward, never repeat")
        expect(!refreshes.finish(firstRefresh),
               "a refresh from an older generation never publishes")
        expect(refreshes.isReading,
               "an older refresh landing late leaves the current one holding the slot")
        expect(refreshes.finish(secondRefresh), "the current refresh still publishes after that")

        var discarded = MixerRefreshCoordinator()
        let staleRefresh = discarded.begin() ?? -1
        _ = discarded.begin()
        discarded.discardInFlight()
        expect(!discarded.isReading, "discarding what is in flight frees the slot at once")
        expect(!discarded.finish(staleRefresh),
               "a refresh reading while the output changed publishes nothing")
        expect(!discarded.takeRepeatRequest(),
               "discarding also drops the repeat request, since a fresh refresh follows it")
        let afterDiscard = discarded.begin() ?? -1
        expect(afterDiscard > staleRefresh && discarded.finish(afterDiscard),
               "the refresh started after a discard is the one that publishes")

        expect(MixerRoutingSupport.engineTeardownDelay(hasAudioObjects: true,
                                                       lastChangeAt: nil,
                                                       now: 100) == nil,
               "a row that still has audio is never left waiting for its tap")
        expect(MixerRoutingSupport.engineTeardownDelay(hasAudioObjects: true,
                                                       lastChangeAt: 99.9,
                                                       now: 100) == nil,
               "a row that got its audio back is handled at once")
        expect(MixerRoutingSupport.engineTeardownDelay(hasAudioObjects: false,
                                                       lastChangeAt: nil,
                                                       now: 100,
                                                       window: 0.2) == 0.2,
               "a row that just lost its audio objects keeps its tap for one window")
        expectClose(MixerRoutingSupport.engineTeardownDelay(hasAudioObjects: false,
                                                            lastChangeAt: 99.95,
                                                            now: 100,
                                                            window: 0.2) ?? -1,
                    0.15,
                    "repeated churn in one window waits out the remainder instead of acting again")
        expect(MixerRoutingSupport.engineTeardownDelay(hasAudioObjects: false,
                                                       lastChangeAt: 99.5,
                                                       now: 100,
                                                       window: 0.2) == nil,
               "a row still without audio after the window loses its tap")
        expect(MixerRoutingSupport.engineTeardownDelay(hasAudioObjects: false,
                                                       lastChangeAt: 101,
                                                       now: 100,
                                                       window: 0.2) == 0.2,
               "a clock that jumps backwards falls back to a full window")

        // Render health of a live engine (issue #341): a tap whose aggregate
        // stopped rendering after wake keeps muting the app and must be caught.
        typealias RenderLook = MixerRoutingSupport.EngineRenderObservation
        expect(MixerRoutingSupport.engineRenderVerdict(previous: RenderLook(cycles: 7, at: 90),
                                                       cycles: 7,
                                                       isPlaying: false,
                                                       now: 100) == nil,
               "a silent app gives no render verdict and clears the observation")
        expect(MixerRoutingSupport.engineRenderVerdict(previous: nil,
                                                       cycles: 7,
                                                       isPlaying: true,
                                                       now: 100,
                                                       window: 1.5)
               == .note(RenderLook(cycles: 7, at: 100), recheckAfter: 1.5),
               "the first look notes the count and schedules a conclusive recheck")
        expect(MixerRoutingSupport.engineRenderVerdict(previous: RenderLook(cycles: 7, at: 100),
                                                       cycles: 9,
                                                       isPlaying: true,
                                                       now: 100.4,
                                                       window: 1.5)
               == .note(RenderLook(cycles: 9, at: 100.4), recheckAfter: nil),
               "an advancing count is healthy and needs no extra pass")
        expect(MixerRoutingSupport.engineRenderVerdict(previous: RenderLook(cycles: 7, at: 100),
                                                       cycles: 7,
                                                       isPlaying: true,
                                                       now: 100.5,
                                                       window: 1.5)
               == .stalled(recheckAfter: 1.0),
               "a count at rest inside the window waits out the remainder")
        expect(MixerRoutingSupport.engineRenderVerdict(previous: RenderLook(cycles: 7, at: 100),
                                                       cycles: 7,
                                                       isPlaying: true,
                                                       now: 102,
                                                       window: 1.5) == .wedged,
               "a count at rest for the whole window while the app plays is wedged")
        expect(MixerRoutingSupport.engineRenderVerdict(previous: RenderLook(cycles: 7, at: 101),
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
        expect(teardownQueueSetup.contains("maxConcurrentOperationCount"),
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
        expect(missedTapBranch.contains("MixerRender.silence(outputBuffers)")
               && missedTapBranch.contains("return"),
               "a callback that finds no tap silences the output before it leaves")
        expect(!missedTapBranch.isEmpty && !missedTapBranch.contains("cycles.increment()"),
               "a callback that finds no tap leaves without counting a cycle")
        let framesGuard = afterMissedTap.range(of: "guard frames > 0 else")?.upperBound
        let cycleCount = afterMissedTap.range(of: "cycles.increment()")?.lowerBound
        expect(framesGuard != nil && cycleCount != nil && framesGuard! < cycleCount!,
               "a cycle is counted only once the engine has handed the device audio")

        let identifiedRow = MixerRoutingSupport.rowIdentity(bundleIdentifier: "com.example.Player",
                                                           ownerPid: 501,
                                                           displayName: "Player")
        expect(identifiedRow.rowID == "com.example.Player"
               && identifiedRow.persistenceID == "com.example.Player",
               "an app with a bundle id keeps it as both row and storage identity")
        let namedRow = MixerRoutingSupport.rowIdentity(bundleIdentifier: nil,
                                                       ownerPid: 501,
                                                       displayName: "Retro Game")
        let otherNamedRow = MixerRoutingSupport.rowIdentity(bundleIdentifier: nil,
                                                            ownerPid: 502,
                                                            displayName: "Retro Game")
        expect(namedRow.persistenceID == "Retro Game",
               "an app without a bundle id saves its volume under its display name, the same key older versions used")
        expect(!namedRow.rowID.isEmpty && namedRow.rowID != otherNamedRow.rowID,
               "two same-named processes without a bundle id stay separate rows")
        let namelessRow = MixerRoutingSupport.rowIdentity(bundleIdentifier: nil,
                                                          ownerPid: 501,
                                                          displayName: nil)
        expect(!namelessRow.rowID.isEmpty && namelessRow.persistenceID == nil,
               "a process with neither bundle id nor name is still listable but stores nothing")
        expect(MixerRoutingSupport.rowIdentity(bundleIdentifier: "   ",
                                               ownerPid: 501,
                                               displayName: "  ").persistenceID == nil,
               "blank identifiers are not identities")

        expect(MixerRoutingSupport.restorableInputDeviceUID(originalUID: "BuiltInMicrophoneDevice",
                                                            appliedUID: "USBMicrophone",
                                                            currentUID: "USBMicrophone",
                                                            availableUIDs: ["BuiltInMicrophoneDevice",
                                                                            "USBMicrophone"])
               == "BuiltInMicrophoneDevice",
               "the microphone the system had before the app changed it is put back")
        expect(MixerRoutingSupport.restorableInputDeviceUID(originalUID: "BuiltInMicrophoneDevice",
                                                            appliedUID: "USBMicrophone",
                                                            currentUID: "HeadsetMicrophone",
                                                            availableUIDs: ["BuiltInMicrophoneDevice",
                                                                            "USBMicrophone"]) == nil,
               "a microphone chosen elsewhere since is left alone")
        expect(MixerRoutingSupport.restorableInputDeviceUID(originalUID: "BuiltInMicrophoneDevice",
                                                            appliedUID: "USBMicrophone",
                                                            currentUID: "USBMicrophone",
                                                            availableUIDs: ["USBMicrophone"]) == nil,
               "a microphone that is gone is not restored")
        expect(MixerRoutingSupport.restorableInputDeviceUID(originalUID: nil,
                                                            appliedUID: nil,
                                                            currentUID: "USBMicrophone",
                                                            availableUIDs: ["USBMicrophone"]) == nil,
               "nothing is restored when the app never changed the microphone")
        expect(MixerRoutingSupport.shouldRestoreOutputVolume(appliedVolume: 0.25, currentVolume: 0.25),
               "a volume still at the value the app set goes back to what it was")
        expect(!MixerRoutingSupport.shouldRestoreOutputVolume(appliedVolume: 0.25, currentVolume: 0.6),
               "a volume changed since the app lowered it is left alone")
        expect(!MixerRoutingSupport.shouldRestoreOutputVolume(appliedVolume: 0.25, currentVolume: nil),
               "a volume that cannot be read is left alone")
        expect(!MixerRoutingSupport.isHiddenFromMixer(
                    persistenceID: "com.apple.finder",
                    hiddenIDs: MixerRoutingSupport.hiddenRowIDs(hiddenApps: [:], showFinder: true)),
               "Finder shows in the mixer when enabled")
        expect(MixerRoutingSupport.isHiddenFromMixer(
                    persistenceID: "com.apple.finder",
                    hiddenIDs: MixerRoutingSupport.hiddenRowIDs(hiddenApps: [:], showFinder: false)),
               "Finder can be hidden from the mixer")
        expect(MixerRoutingSupport.isHiddenFromMixer(
                    persistenceID: "com.example.Player",
                    hiddenIDs: MixerRoutingSupport.hiddenRowIDs(
                        hiddenApps: ["com.example.Player": "Player"], showFinder: true)),
               "any app the user hid stays out of the mixer list")
        expect(!MixerRoutingSupport.isHiddenFromMixer(
                    persistenceID: "com.example.Player",
                    hiddenIDs: MixerRoutingSupport.hiddenRowIDs(hiddenApps: [:], showFinder: false)),
               "hiding Finder leaves every other app visible")
        expect(MixerRoutingSupport.isHiddenFromMixer(
                    persistenceID: "Bare Tool",
                    hiddenIDs: MixerRoutingSupport.hiddenRowIDs(
                        hiddenApps: ["Bare Tool": "Bare Tool"], showFinder: true)),
               "apps saved under a display name can be hidden too")
        expect(!MixerRoutingSupport.isHiddenFromMixer(persistenceID: nil,
                                                      hiddenIDs: ["com.example.Player"]),
               "a row with nothing to remember it by is always listed")
        let hiddenSanitized = MixerRoutingSupport.sanitizedHiddenApps([
            "com.example.Player": "Player",
            "com.apple.finder": "Finder",
            "": "Nameless",
            "com.example.Silent": "",
            "com.example.Broken": 3,
        ])
        expect(hiddenSanitized == ["com.example.Player": "Player"],
               "the hidden map keeps only real entries and never carries the Finder")
        expect(MixerRoutingSupport.needsPersistentFinderRow(showFinder: true,
                                                            hasFinderRow: false),
               "Finder gets a persistent row before Quick Look opens")
        expect(!MixerRoutingSupport.needsPersistentFinderRow(showFinder: true,
                                                             hasFinderRow: true)
                && !MixerRoutingSupport.needsPersistentFinderRow(showFinder: false,
                                                                 hasFinderRow: false),
               "Finder is never duplicated and stays absent when hidden")
        expect(MixerRoutingSupport.bypassesProcessTap(bundleIdentifier: "us.zoom.xos", name: "zoom.us"),
               "Zoom is kept out of process-tap audio routing")
        expect(MixerRoutingSupport.bypassesProcessTap(bundleIdentifier: "us.zoom.ZoomAutoUpdater", name: "Zoom"),
               "Zoom helper bundle ids are kept out of process-tap audio routing")
        expect(!MixerRoutingSupport.bypassesProcessTap(bundleIdentifier: "com.apple.Safari", name: "Safari"),
               "regular apps remain eligible for process-tap audio routing")
        expect(!MixerRoutingSupport.bypassesProcessTap(bundleIdentifier: nil, name: "Zoomable Notes"),
               "unrelated app names are not treated as Zoom")
        expect(MixerRoutingSupport.bypassesProcessTap(bundleIdentifier: "com.apple.logic10", name: "Logic Pro"),
               "Logic Pro is kept out of process-tap audio routing")
        expect(MixerRoutingSupport.bypassesProcessTap(bundleIdentifier: "com.ableton.live", name: "Live"),
               "Ableton Live is kept out of process-tap audio routing")
        expect(MixerRoutingSupport.bypassesProcessTap(bundleIdentifier: "com.steinberg.cubase13", name: "Cubase"),
               "Cubase is kept out of process-tap audio routing")
        expect(MixerRoutingSupport.bypassesProcessTap(bundleIdentifier: "com.presonus.studioone6", name: "Studio One"),
               "Studio One is kept out of process-tap audio routing")
        expect(!MixerRoutingSupport.bypassesProcessTap(bundleIdentifier: "com.spotify.client", name: "Spotify"),
               "music players remain eligible for process-tap audio routing")
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
        expect(MixerRoutingSupport.displayOrderedBefore(name: "Music", id: "com.apple.Music",
                                                        otherName: "Safari", otherID: "com.apple.Safari"),
               "mixer rows order by display name")
        expect(MixerRoutingSupport.displayOrderedBefore(name: "safari", id: "a",
                                                        otherName: "Safari", otherID: "b")
                   && !MixerRoutingSupport.displayOrderedBefore(name: "Safari", id: "b",
                                                                otherName: "safari", otherID: "a"),
               "mixer rows with equal names order deterministically by id")
        expect(MixerRoutingSupport.deviceDisplayOrderedBefore(isDefault: true, name: "Zeta", uid: "z",
                                                              otherIsDefault: false, otherName: "Alpha",
                                                              otherUID: "a"),
               "the default device orders before any other device")
        expect(MixerRoutingSupport.deviceDisplayOrderedBefore(isDefault: false, name: "AirPods Pro", uid: "aa",
                                                              otherIsDefault: false, otherName: "AirPods Pro",
                                                              otherUID: "bb")
                   && !MixerRoutingSupport.deviceDisplayOrderedBefore(isDefault: false, name: "AirPods Pro",
                                                                      uid: "bb",
                                                                      otherIsDefault: false,
                                                                      otherName: "AirPods Pro",
                                                                      otherUID: "aa"),
               "identically named devices order deterministically by uid")
    }

    static func runPreciseVolume(expect: (Bool, String) -> Void) {
        // MARK: Precise volume roller

        var volumeGate = PreciseVolumeRollerGate()
        expect(volumeGate.accepts(.up, at: 100.00),
               "precise volume accepts the first wheel step")
        expect(!volumeGate.accepts(.up, at: 100.01),
               "precise volume drops repeats that arrive inside the spacing window")
        expect(volumeGate.accepts(.up, at: 100.05),
               "precise volume accepts a later step in the same direction")

        var reversalGate = PreciseVolumeRollerGate()
        expect(reversalGate.accepts(.up, at: 200.00),
               "precise volume reversal setup accepts the initial direction")
        expect(!reversalGate.accepts(.down, at: 200.08),
               "precise volume ignores the first opposite pulse inside the reversal window")
        expect(!reversalGate.accepts(.down, at: 200.16),
               "precise volume waits for a stable opposite direction")
        expect(reversalGate.accepts(.down, at: 200.24),
               "precise volume accepts the confirmed opposite direction")

        var oldDirectionGate = PreciseVolumeRollerGate()
        expect(oldDirectionGate.accepts(.up, at: 300.00),
               "precise volume accepts first old-direction step")
        expect(oldDirectionGate.accepts(.down, at: 300.40),
               "precise volume accepts an opposite step after the reversal window")
        var fastStreamGate = PreciseVolumeRollerGate()
        let fastAccepted = stride(from: 400.00, through: 400.10, by: 0.02)
            .filter { fastStreamGate.accepts(.up, at: $0) }
        expect(fastAccepted.count == 3,
               "precise volume rate-limits sustained fast input instead of starving it")
        expect(PreciseVolumeMediaKey.volumeUp.rollerDirection == .up
                && PreciseVolumeMediaKey.volumeDown.rollerDirection == .down
                && PreciseVolumeMediaKey.mute.rollerDirection == nil,
               "precise volume only remaps volume up and down media keys")
    }
}
