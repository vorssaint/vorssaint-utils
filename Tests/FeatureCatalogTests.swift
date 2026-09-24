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

enum FeatureCatalogTests {
    private final class InstallerFileManager: FileManager, @unchecked Sendable {
        let localApplications: URL
        var userApplications: URL?

        init(root: URL) {
            localApplications = root.appendingPathComponent("System/Applications", isDirectory: true)
            userApplications = root.appendingPathComponent("Home/Applications", isDirectory: true)
            super.init()
        }

        override func urls(for directory: SearchPathDirectory, in domain: SearchPathDomainMask) -> [URL] {
            guard directory == .applicationDirectory else { return [] }
            if domain == .localDomainMask { return [localApplications] }
            return userApplications.map { [$0] } ?? []
        }
    }

    static func run(_ suite: TestSuite) {
        func expectFormat(_ format: String, _ expected: [String], _ label: String,
                          file: StaticString = #filePath, line: UInt = #line) {
            let actual = TestFormat.parse(format)?.conversions ?? ["invalid format"]
            suite.expect(actual == expected, "\(label): got \(actual), expected \(expected)",
                         file: file, line: line)
        }
        // MARK: Cleaning-mode unlock gesture

        let escapeKeyCode: Int64 = 53

        // Five deliberate Escape taps unlock, on the fifth.
        var taps = CleaningUnlockCounter(requiredKeyCode: escapeKeyCode, threshold: 5, pressWindow: 2.0)
        var tapUnlock = false
        for (i, t) in [0.0, 0.3, 0.6, 0.9, 1.2].enumerated() {
            tapUnlock = taps.registerKeyDown(code: escapeKeyCode, time: t, isRepeat: false)
            if i < 4 { suite.expect(!tapUnlock, "no unlock before the fifth tap (\(i + 1))") }
        }
        suite.expect(tapUnlock, "five Escape taps unlock")
        suite.expect(taps.progress == 5, "progress reaches the threshold")

        // Wiping other keys cannot make progress toward unlock.
        var wipe = CleaningUnlockCounter(requiredKeyCode: escapeKeyCode, threshold: 5, pressWindow: 2.0)
        var wipeUnlock = false
        for (i, code) in [Int64(10), 11, 12, 13, 14, 15, 16, 17].enumerated() {
            if wipe.registerKeyDown(code: code, time: Double(i) * 0.1, isRepeat: false) { wipeUnlock = true }
        }
        suite.expect(!wipeUnlock, "wiping other keys never unlocks")
        suite.expect(wipe.progress == 0, "other keys make no unlock progress")

        // A different key mid-streak resets the count completely.
        var streak = CleaningUnlockCounter(requiredKeyCode: escapeKeyCode, threshold: 5, pressWindow: 2.0)
        _ = streak.registerKeyDown(code: escapeKeyCode, time: 0.0, isRepeat: false)
        _ = streak.registerKeyDown(code: escapeKeyCode, time: 0.2, isRepeat: false)
        _ = streak.registerKeyDown(code: escapeKeyCode, time: 0.4, isRepeat: false)
        _ = streak.registerKeyDown(code: 8, time: 0.6, isRepeat: false)
        suite.expect(streak.progress == 0, "a different key mid-streak clears progress")

        // Auto-repeat (holding Escape) is ignored, so resting on it can't unlock.
        var held = CleaningUnlockCounter(requiredKeyCode: escapeKeyCode, threshold: 5, pressWindow: 2.0)
        var heldUnlock = false
        for i in 0..<10 {
            if held.registerKeyDown(code: escapeKeyCode, time: Double(i) * 0.1, isRepeat: true) { heldUnlock = true }
        }
        suite.expect(!heldUnlock, "auto-repeat never unlocks")
        suite.expect(held.progress == 0, "auto-repeat does not advance progress")

        // A pause longer than the window restarts the count.
        var paused = CleaningUnlockCounter(requiredKeyCode: escapeKeyCode, threshold: 5, pressWindow: 2.0)
        _ = paused.registerKeyDown(code: escapeKeyCode, time: 0.0, isRepeat: false)
        _ = paused.registerKeyDown(code: escapeKeyCode, time: 0.5, isRepeat: false)
        suite.expect(paused.progress == 2, "presses within the window accumulate")
        _ = paused.registerKeyDown(code: escapeKeyCode, time: 10.0, isRepeat: false)
        suite.expect(paused.progress == 1, "a pause beyond the window restarts the count")

        // reset() clears everything.
        var cleared = CleaningUnlockCounter(requiredKeyCode: escapeKeyCode, threshold: 5, pressWindow: 2.0)
        _ = cleared.registerKeyDown(code: escapeKeyCode, time: 0.0, isRepeat: false)
        _ = cleared.registerKeyDown(code: escapeKeyCode, time: 0.2, isRepeat: false)
        suite.expect(cleared.progress == 2, "progress accumulates before reset")
        cleared.reset()
        suite.expect(cleared.progress == 0, "reset clears progress")
        let afterReset2 = cleared.registerKeyDown(code: escapeKeyCode, time: 0.4, isRepeat: false)
        suite.expect(!afterReset2 && cleared.progress == 1, "after reset Escape starts fresh at 1")

        // Modifiers are the keys nearest Escape, so a cloth reaches them first.
        // They arrive as flags-changed events, which the tap feeds here too, and
        // one physical press reports twice — once down, once up. Both are resets.
        var smeared = CleaningUnlockCounter(requiredKeyCode: escapeKeyCode, threshold: 5, pressWindow: 6.0)
        let leftShiftKeyCode: Int64 = 56
        var smearedUnlock = false
        for t in [0.0, 0.5, 1.0, 1.5] {
            if smeared.registerKeyDown(code: escapeKeyCode, time: t, isRepeat: false) { smearedUnlock = true }
        }
        suite.expect(smeared.progress == 4, "four Escapes stop one short of the threshold")
        _ = smeared.registerKeyDown(code: leftShiftKeyCode, time: 2.0, isRepeat: false)
        suite.expect(smeared.progress == 0, "a modifier going down clears the Escape count")
        _ = smeared.registerKeyDown(code: leftShiftKeyCode, time: 2.1, isRepeat: false)
        suite.expect(smeared.progress == 0, "the modifier's release resets again, idempotently")
        if smeared.registerKeyDown(code: escapeKeyCode, time: 2.5, isRepeat: false) { smearedUnlock = true }
        suite.expect(!smearedUnlock && smeared.progress == 1,
               "four Escapes with a modifier in between never unlock; the next Escape starts at 1")

        // User-requested teardown waits only for real releases corresponding
        // to mouse-down events observed while Cleaning Mode was active.
        var cleaningMouseGate = CleaningMouseReleaseGate()
        cleaningMouseGate.buttonDown(0)
        suite.expect(!cleaningMouseGate.requestDeactivation(),
               "cleaning teardown waits when the primary button went down while the overlay was active")
        suite.expect(!cleaningMouseGate.buttonUp(1),
               "an unrelated release cannot complete a pending cleaning teardown")
        suite.expect(cleaningMouseGate.buttonUp(0),
               "the matching physical release completes the pending cleaning teardown")
        suite.expect(cleaningMouseGate.deactivationPending,
               "the cleaning unlock request remains pending until teardown runs")
        suite.expect(cleaningMouseGate.requestDeactivation(),
               "cleaning teardown is immediate when no tracked button is held")

        cleaningMouseGate.reset()
        cleaningMouseGate.buttonDown(0)
        cleaningMouseGate.buttonDown(2)
        suite.expect(!cleaningMouseGate.requestDeactivation(),
               "cleaning teardown waits for every tracked mouse button")
        suite.expect(!cleaningMouseGate.buttonUp(0),
               "releasing one of several held buttons keeps cleaning teardown pending")
        suite.expect(cleaningMouseGate.buttonUp(2),
               "the last matching release completes a multi-button cleaning teardown")

        cleaningMouseGate.reset()
        cleaningMouseGate.buttonDown(0)
        suite.expect(!cleaningMouseGate.buttonUp(0),
               "a normal click completed before deactivation never schedules teardown by itself")
        suite.expect(cleaningMouseGate.requestDeactivation(),
               "a completed click leaves no stale held-button state")
        cleaningMouseGate.buttonDown(0)
        _ = cleaningMouseGate.requestDeactivation()
        cleaningMouseGate.reset()
        suite.expect(cleaningMouseGate.pressedButtons.isEmpty && !cleaningMouseGate.deactivationPending,
               "forced cleaning teardown clears tracked mouse lifecycle state")

        var queuedCleaningMouseGate = CleaningMouseReleaseGate()
        suite.expect(queuedCleaningMouseGate.requestDeactivation(),
               "cleaning teardown can be queued when no button is held")
        queuedCleaningMouseGate.buttonDown(0)
        suite.expect(queuedCleaningMouseGate.deactivationPending
                && !queuedCleaningMouseGate.pressedButtons.isEmpty,
               "a new press before queued teardown is still tracked")
        suite.expect(!queuedCleaningMouseGate.buttonUp(1),
               "an unrelated release cannot finish a newly tracked press")
        suite.expect(queuedCleaningMouseGate.buttonUp(0),
               "the new press must receive its matching release")
        queuedCleaningMouseGate.buttonDown(2)
        suite.expect(queuedCleaningMouseGate.deactivationPending
                && !queuedCleaningMouseGate.pressedButtons.isEmpty,
               "a press after the last release still postpones queued teardown")
        suite.expect(queuedCleaningMouseGate.buttonUp(2),
               "the final new press also needs its matching release")

        var disabledTapMouseGate = CleaningMouseReleaseGate()
        disabledTapMouseGate.buttonDown(0)
        _ = disabledTapMouseGate.requestDeactivation()
        disabledTapMouseGate.invalidateTrackedPresses()
        suite.expect(disabledTapMouseGate.pressedButtons.isEmpty
                && disabledTapMouseGate.deactivationPending,
               "a tap gap forgets stale presses without losing the unlock request")
        disabledTapMouseGate.buttonDown(1)
        suite.expect(!disabledTapMouseGate.buttonUp(0),
               "a release from before the tap gap cannot finish a new press")
        suite.expect(disabledTapMouseGate.buttonUp(1),
               "a fresh press after the tap gap still needs its own release")

        var expiredWaitGate = CleaningMouseReleaseGate()
        expiredWaitGate.buttonDown(1)
        suite.expect(!expiredWaitGate.requestDeactivation() && expiredWaitGate.releaseWaitExpired()
                && expiredWaitGate.pressedButtons.isEmpty && expiredWaitGate.deactivationPending,
               "an unlock stops waiting for a release that never arrives once the wait runs out")
        var idleWaitGate = CleaningMouseReleaseGate()
        idleWaitGate.buttonDown(0)
        suite.expect(!idleWaitGate.releaseWaitExpired() && idleWaitGate.pressedButtons == [0],
               "the wait limit leaves presses alone when no unlock was asked for")
        suite.expect(CleaningMouseReleaseGate.releaseWaitLimit > 0 && CleaningMouseReleaseGate.releaseWaitLimit <= 10,
               "a pending cleaning unlock has a short maximum wait")

        // The counters above build their own windows, so nothing else here
        // fails if the shipped constant regresses. Pin it at the source: the
        // 2s window made the gesture impossible for anyone pressing Escape
        // slower than once per two seconds (#697).
        let cleaningSource = (try? String(
            contentsOfFile: "Sources/Vorssaint/Services/CleaningMode/CleaningModeManager.swift",
            encoding: .utf8)) ?? ""
        let cleaningCode = cleaningSource
            .components(separatedBy: "\n")
            .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }
            .joined(separator: "\n")
        suite.expect(!cleaningCode.isEmpty && cleaningCode.contains("pressWindow: 6.0"),
               "the shipped unlock counter keeps the forgiving 6s press window")

        suite.expect(!cleaningCode.contains("CGEvent(mouseEventSource:"),
               "Cleaning Mode never synthesizes a global mouse release")
        suite.expect(!cleaningCode.contains("pressedMouseButtons")
                && !cleaningCode.contains("CGEventSource.buttonState"),
               "Cleaning Mode does not infer ownership from a global button-state snapshot")
        suite.expect(cleaningCode.contains("let shouldFinishUserDeactivation = mouseReleaseGate.deactivationPending")
                && cleaningCode.contains("mouseReleaseGate.invalidateTrackedPresses()")
                && cleaningCode.contains("if shouldFinishUserDeactivation {"),
               "disabled-tap recovery invalidates stale mouse state and preserves a pending user unlock")
        suite.expect(cleaningCode.contains("self.mouseReleaseGate.deactivationPending,")
                && cleaningCode.contains("self.mouseReleaseGate.pressedButtons.isEmpty else { return }"),
               "queued cleaning teardown rechecks the current press state")
        suite.expect(cleaningCode.contains("armReleaseDeadline()\n        guard mouseReleaseGate.requestDeactivation()")
                && cleaningCode.contains("releaseDeadline?.cancel()"),
               "every user unlock arms the release deadline and teardown cancels it")

        // The counter above cannot see how events reach it, and the real HID
        // gesture is not reproducible headlessly. Pin the two properties of the
        // tap's handler the counter depends on: modifiers reach it (they arrive
        // as .flagsChanged, never as key-downs, and are the keys nearest
        // Escape), and every ordinary event is still swallowed. The sole
        // fail-open return belongs to a disabled tap in an inactive or
        // untrusted session, where keeping input locked would strand the user.
        let cleaningLines = cleaningSource.components(separatedBy: "\n")
        let handlerStart = cleaningLines.firstIndex { $0.contains("private func handle(type:") }
        let handlerEnd = handlerStart.flatMap { start in
            cleaningLines[(start + 1)...].firstIndex { $0.hasPrefix("    private func ") }
        } ?? cleaningLines.count
        var modifiersReachCounter = false
        var leakedEvents: [String] = []
        var passThroughReturns = 0
        for (index, line) in cleaningLines[(handlerStart ?? handlerEnd)..<handlerEnd].enumerated()
        where !line.trimmingCharacters(in: .whitespaces).hasPrefix("//") {
            let number = (handlerStart ?? 0) + index + 1
            if line.contains("type == .flagsChanged") {
                // Read to the end of that branch: the call has to be inside it.
                var cursor = (handlerStart ?? 0) + index + 1
                while cursor < handlerEnd, !cleaningLines[cursor].trimmingCharacters(in: .whitespaces).hasPrefix("}") {
                    if cleaningLines[cursor].contains("registerUnlockKeyDown(") { modifiersReachCounter = true }
                    cursor += 1
                }
            }
            if line.contains("return Unmanaged.passUnretained(event)") {
                passThroughReturns += 1
            } else if line.contains("return"), !line.contains("return nil") {
                leakedEvents.append("CleaningModeManager.swift:\(number)")
            }
        }
        suite.expect(modifiersReachCounter,
               "flags-changed events feed the unlock counter, so modifiers reset the Escape count")
        suite.expect(handlerStart != nil
               && leakedEvents.isEmpty
               && passThroughReturns == 2
               && cleaningCode.contains("if handleMouseButton(type: type, event: event)"),
               "the cleaning tap swallows locked input while mouse events and disabled-session recovery pass through: \(leakedEvents)")
        suite.expect(cleaningCode.contains("self.deactivate(restoreSuspendedFeatures: false)")
                && cleaningCode.contains("shouldRestoreSuspendedFeaturesOnSessionReturn = true")
                && cleaningCode.contains("self.resumeSuspendedFeatures()")
                && cleaningCode.contains("guard restoreSuspendedFeatures else {"),
               "Cleaning Mode restores suspended taps only after its login session returns")

        func systemKeyData(keyCode: Int, state: Int, repeatFlag: Bool = false) -> Int {
            Int((UInt32(keyCode) << 16) | (UInt32(state) << 8) | (repeatFlag ? 1 : 0))
        }

        let brightnessDown = CleaningSystemKeyEvent.decode(
            subtype: CleaningSystemKeyEvent.auxiliaryControlButtonsSubtype,
            data1: systemKeyData(keyCode: 3, state: CleaningSystemKeyEvent.keyDownState)
        )
        suite.expect(brightnessDown?.isKeyDown == true && brightnessDown?.isRepeat == false,
               "brightness key down is decoded from system-defined events")

        let volumeUpRepeat = CleaningSystemKeyEvent.decode(
            subtype: CleaningSystemKeyEvent.auxiliaryControlButtonsSubtype,
            data1: systemKeyData(keyCode: 0, state: CleaningSystemKeyEvent.keyDownState, repeatFlag: true)
        )
        suite.expect(volumeUpRepeat?.isKeyDown == true && volumeUpRepeat?.isRepeat == true,
               "system-defined auto-repeat is preserved")

        let mediaNextUp = CleaningSystemKeyEvent.decode(
            subtype: CleaningSystemKeyEvent.auxiliaryControlButtonsSubtype,
            data1: systemKeyData(keyCode: 17, state: CleaningSystemKeyEvent.keyUpState)
        )
        suite.expect(mediaNextUp?.isKeyDown == false,
               "system-defined key up is decoded without advancing unlock")

        let powerKey = CleaningSystemKeyEvent.decode(
            subtype: CleaningSystemKeyEvent.powerKeySubtype,
            data1: 0
        )
        suite.expect(powerKey?.isKeyDown == true && powerKey?.isRepeat == false,
               "power and lock key system events are recognized")

        let unrelatedSystemEvent = CleaningSystemKeyEvent.decode(subtype: 99, data1: 0)
        suite.expect(unrelatedSystemEvent == nil, "unrelated system-defined events do not count as unlock keys")

        // MARK: Music launch blocker

        func musicKeyData(keyCode: Int, state: Int = 10, repeatFlag: Bool = false) -> Int {
            Int((UInt32(keyCode) << 16) | (UInt32(state) << 8) | (repeatFlag ? 1 : 0))
        }
        suite.expect(MusicLaunchSupport.isMusicLaunchTrigger(
            subtype: MusicLaunchSupport.auxiliaryControlButtonsSubtype,
            data1: musicKeyData(keyCode: Int(MusicLaunchSupport.playPauseKeyCode))),
               "play/pause arms the music-app blocker")
        suite.expect(MusicLaunchSupport.isMusicLaunchTrigger(
            subtype: MusicLaunchSupport.auxiliaryControlButtonsSubtype,
            data1: musicKeyData(keyCode: Int(MusicLaunchSupport.nextTrackKeyCode))),
               "next track arms the music-app blocker")
        suite.expect(MusicLaunchSupport.isMusicLaunchTrigger(
            subtype: MusicLaunchSupport.auxiliaryControlButtonsSubtype,
            data1: musicKeyData(keyCode: Int(MusicLaunchSupport.previousTrackKeyCode))),
               "previous track arms the music-app blocker")
        suite.expect(MusicLaunchSupport.isMusicLaunchTrigger(
            subtype: MusicLaunchSupport.auxiliaryControlButtonsSubtype,
            data1: musicKeyData(keyCode: Int(MusicLaunchSupport.fastForwardKeyCode))),
               "fast-forward arms the music-app blocker")
        suite.expect(MusicLaunchSupport.isMusicLaunchTrigger(
            subtype: MusicLaunchSupport.auxiliaryControlButtonsSubtype,
            data1: musicKeyData(keyCode: Int(MusicLaunchSupport.rewindKeyCode))),
               "rewind arms the music-app blocker")
        suite.expect(!MusicLaunchSupport.isMusicLaunchTrigger(
            subtype: MusicLaunchSupport.auxiliaryControlButtonsSubtype,
            data1: musicKeyData(keyCode: Int(MusicLaunchSupport.playPauseKeyCode), state: 11)),
               "a media-key release does not arm the blocker")
        suite.expect(!MusicLaunchSupport.isMusicLaunchTrigger(
            subtype: MusicLaunchSupport.auxiliaryControlButtonsSubtype,
            data1: musicKeyData(keyCode: Int(MusicLaunchSupport.playPauseKeyCode), repeatFlag: true)),
               "auto-repeat does not re-arm the blocker")
        suite.expect(!MusicLaunchSupport.isMusicLaunchTrigger(
            subtype: MusicLaunchSupport.auxiliaryControlButtonsSubtype,
            data1: musicKeyData(keyCode: 0)),
               "volume keys do not arm the blocker")
        suite.expect(!MusicLaunchSupport.isMusicLaunchTrigger(
            subtype: MusicLaunchSupport.auxiliaryControlButtonsSubtype,
            data1: musicKeyData(keyCode: 2)),
               "brightness keys do not arm the blocker")
        suite.expect(!MusicLaunchSupport.isMusicLaunchTrigger(subtype: 1, data1: musicKeyData(keyCode: 16)),
               "other system-defined subtypes do not arm the blocker")
        suite.expect(MusicLaunchSupport.shouldBlockLaunch(
            now: 10, lastTriggerAt: 9.5, secondsSinceUserGesture: 1),
               "an observed media key newer than the user's last gesture can block a launch")
        suite.expect(MusicLaunchSupport.shouldBlockLaunch(
            now: 10, lastTriggerAt: 8, secondsSinceUserGesture: 3),
               "a media key on the arm-window edge is still evidence")
        for age in [0.0, 0.3, 2, 2.1, 100, .infinity] {
            suite.expect(!MusicLaunchSupport.shouldBlockLaunch(
                now: 10, lastTriggerAt: nil, secondsSinceUserGesture: age),
                   "voice, automation, login and unobserved headphone commands remain open without a media key")
        }
        suite.expect(!MusicLaunchSupport.shouldBlockLaunch(
            now: 10, lastTriggerAt: 7.9, secondsSinceUserGesture: 100),
               "idle time cannot revive an expired media key")
        for age in [0.0, 0.1, 0.5] {
            suite.expect(!MusicLaunchSupport.shouldBlockLaunch(
                now: 10, lastTriggerAt: 9.5, secondsSinceUserGesture: age),
                   "a newer or simultaneous click or ordinary key takes precedence over the media key")
        }
        suite.expect(MusicLaunchSupport.shouldBlockLaunch(
            now: 10, lastTriggerAt: 9.5, secondsSinceUserGesture: .infinity),
               "a real media key is still useful before the session's first ordinary gesture")
        for now in [-1.0, .nan, .infinity, -.infinity] {
            suite.expect(!MusicLaunchSupport.shouldBlockLaunch(
                now: now, lastTriggerAt: 0, secondsSinceUserGesture: .infinity),
                   "an invalid current clock cannot justify terminating an app")
        }
        for trigger in [-1.0, 11, .nan, .infinity, -.infinity] {
            suite.expect(!MusicLaunchSupport.shouldBlockLaunch(
                now: 10, lastTriggerAt: trigger, secondsSinceUserGesture: 100),
                   "invalid or future trigger timestamps cannot justify terminating an app")
        }
        for age in [-1.0, .nan, -.infinity] {
            suite.expect(!MusicLaunchSupport.shouldBlockLaunch(
                now: 10, lastTriggerAt: 9.5, secondsSinceUserGesture: age),
                   "an invalid gesture age preserves the launch")
        }
        MusicLaunchBlockerContract.run(suite)

        // MARK: Features hub catalog

        suite.expect(AppFeature.allCases.count == 70, "feature catalog has 70 features")
        suite.expect(Set(AppFeature.allCases.map(\.rawValue)).count == AppFeature.allCases.count,
               "feature ids are unique")
        suite.expect(AppFeature.allCases.map(\.rawValue) == [
            "switcher", "dockPreview", "dockClick", "windowMaximizer", "windowLayout", "autoQuit",
            "scrollInverter", "scrollHorizontal", "focusFollowsMouse", "smoothScroll", "mouseAcceleration", "mouseNavigation", "mouseButtonShortcuts", "middleClick",
            "mouseClickDebounce", "keyboardDebounce", "textSnippets", "superKey", "quitWindowProtection",
            "clipboardHistory", "pastePlain", "finderCutPaste", "finderRename", "shelf", "urlCleaner",
            "diskImageInstaller",
            "mixer", "soundOutputSwitcher", "micMute", "musicBlock",
            "keepAwake", "brightness", "extraBrightness", "bluetoothSleep",
            "quickLauncher", "quickToggles", "colorPicker", "screenOCR", "cleaningMode", "mediaTools",
            "cleaner", "uninstaller", "homebrew", "appUpdates", "screenshot", "cameraPreview",
            "radialMenu", "scratchpad", "commandBar", "screenRecorder", "killProcess", "portManager", "notch", "notchCalendar", "notchNotifications", "notchGestures", "notchTimer", "notchAccessories", "notchLyrics", "notchQueue", "notchLiveEqualizer", "notchDownloads", "notchAgents",
            "monitorCPU", "monitorGPU", "monitorMemory", "monitorNetwork", "monitorDisk", "monitorPower",
            "fanControl",
        ], "feature ids are stable (they persist inside availability keys)")
        suite.expect(MouseAccelerationSupport.validatedRegistryID(nil) == nil
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
        suite.expect(mouseJournal.entry(registryID: 42, identity: mouseIdentity) == mouseRecovery,
               "mouse acceleration keeps one exact restorable value per live service")
        let reusedRegistryIdentity = MouseAccelerationDeviceIdentity(
            vendorID: 9,
            productID: 9,
            locationID: 9,
            transport: "USB",
            physicalUniqueID: nil,
            serialNumber: nil
        )
        suite.expect(mouseJournal.entry(registryID: 42, identity: reusedRegistryIdentity) == nil,
               "a reused registry id can never receive another mouse's saved value")
        suite.expect(mouseJournal.entriesToRestore(preserving: [42: mouseIdentity]).isEmpty
                && mouseJournal.entry(registryID: 42, identity: mouseIdentity) == mouseRecovery,
               "hotplug retries preserve a connected mouse's original value without restoring acceleration between attempts")
        suite.expect(mouseJournal.entriesToRestore(preserving: [43: mouseIdentity]) == [mouseRecovery],
               "a reconnected mouse with a new registry id still needs recovery before recapture")
        suite.expect(mouseJournal.entriesToRestore(preserving: [42: reusedRegistryIdentity]) == [mouseRecovery],
               "an unrelated mouse reusing a registry id cannot hide a pending recovery")
        suite.expect(mouseJournal.entriesToRestore(preserving: [:]) == [mouseRecovery],
               "stopping acceleration control still restores every saved entry")

        var mouseReapplication = MouseAccelerationReapplySchedule()
        let initialMouseConnection = mouseReapplication.restart()
        suite.expect(mouseReapplication.nextDelay(for: initialMouseConnection) == 0,
               "hotplug requests the first acceleration refresh without blocking the device callback")
        let reconnectedMouse = mouseReapplication.restart()
        suite.expect(!mouseReapplication.isCurrent(initialMouseConnection)
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
        suite.expect(lateMouseReset && lateMouseValue?.rawValue == -1,
               "acceleration is reapplied when a mouse service and its settings arrive after the physical callback")
        suite.expect(mouseReapplyAttempts > 1 && mouseReapplyAttempts < 20
                && mouseReapplyTime > 2 && mouseReapplyTime <= 5
                && !mouseReapplication.isCurrent(reconnectedMouse),
               "hotplug reapplication finishes within five seconds and leaves no idle retry")
        let cancelledMouseConnection = mouseReapplication.restart()
        _ = mouseReapplication.nextDelay(for: cancelledMouseConnection)
        mouseReapplication.cancel()
        suite.expect(!mouseReapplication.isCurrent(cancelledMouseConnection)
                && mouseReapplication.nextDelay(for: cancelledMouseConnection) == nil,
               "turning the feature off or pausing the session invalidates queued acceleration writes")
        let resumedMouseConnection = mouseReapplication.restart()
        suite.expect(mouseReapplication.nextDelay(for: resumedMouseConnection) == 0
                && !mouseReapplication.isCurrent(cancelledMouseConnection),
               "resuming creates a fresh retry window without reviving cancelled callbacks")
        suite.expect(mouseIdentity.canMatchAcrossRegistryIDs,
               "a stable physical identity can recover after a device receives a new registry id")
        let anonymousMouseIdentity = MouseAccelerationDeviceIdentity(
            vendorID: nil,
            productID: nil,
            locationID: nil,
            transport: "USB",
            physicalUniqueID: nil,
            serialNumber: nil
        )
        suite.expect(!anonymousMouseIdentity.canMatchAcrossRegistryIDs,
               "an anonymous device can never inherit another registry id's saved value")
        suite.expect(MouseAccelerationSupport.isRestorableKey(MouseAccelerationSupport.linearScalingKey)
                && MouseAccelerationSupport.isRestorableKey(MouseAccelerationSupport.mouseAccelerationKey)
                && !MouseAccelerationSupport.isRestorableKey("UserKeyMapping"),
               "mouse acceleration recovery accepts only its own HID properties")
        suite.expect(MouseAccelerationSupport.targetValue(
            for: MouseAccelerationSupport.linearScalingKey,
            originalIsBoolean: true
        ) == MouseAccelerationStoredValue(rawValue: 1, isBoolean: true)
            && MouseAccelerationSupport.targetValue(
                for: MouseAccelerationSupport.mouseAccelerationKey,
                originalIsBoolean: false
            ) == MouseAccelerationStoredValue(rawValue: -1, isBoolean: false),
               "mouse acceleration uses linear mode when supported and the legacy fallback otherwise")
        suite.expect(AppFeature.switcher.availabilityKey == "featureAvailable.switcher",
               "availability key derives from the raw value")
        suite.expect(AppFeature.availabilityDefaults.count == AppFeature.allCases.count
                && (AppFeature.availabilityDefaults[AppFeature.fanControl.availabilityKey] as? Bool) == false
                && (AppFeature.availabilityDefaults[AppFeature.diskImageInstaller.availabilityKey] as? Bool) == false
                && (AppFeature.availabilityDefaults[AppFeature.focusFollowsMouse.availabilityKey] as? Bool) == false
                && (AppFeature.availabilityDefaults[AppFeature.killProcess.availabilityKey] as? Bool) == false
                && (AppFeature.availabilityDefaults[AppFeature.portManager.availabilityKey] as? Bool) == false
                && AppFeature.allCases.filter {
                    $0 != .focusFollowsMouse && $0 != .fanControl && $0 != .diskImageInstaller
                        && $0 != .killProcess && $0 != .scrollHorizontal && $0 != .portManager
                }.allSatisfy {
                    (AppFeature.availabilityDefaults[$0.availabilityKey] as? Bool) == true
                },
               "new opt-in features ship uninstalled while existing features remain available")
        suite.expect(FeatureGroup.allCases.map { AppFeature.features(in: $0).count }.reduce(0, +)
                == AppFeature.allCases.count,
               "every feature belongs to exactly one group")
        suite.expect(!FeatureGroup.allCases.contains { AppFeature.features(in: $0).isEmpty },
               "no hub group is empty")
        suite.expect(AppFeature.features(in: .dynamicIsland) == [
            .notch, .notchCalendar, .notchNotifications, .notchGestures, .notchTimer,
            .notchAccessories, .notchLyrics, .notchQueue, .notchLiveEqualizer, .notchDownloads, .notchAgents,
        ], "the Dynamic Island heads its own hub section, followed by its extensions")
        suite.expect(AppFeature.dynamicIslandExtensions
                == Array(AppFeature.features(in: .dynamicIsland).dropFirst()),
               "the Dynamic Island's extensions are every other feature of its section")
        suite.expect(AppPermission.allCases.map(\.rawValue) == [
            "accessibility", "screenRecording", "fullDiskAccess", "filesAndFolders", "notifications",
            "automationFinder", "automationTerminal", "automationPlayback", "audioCapture", "microphone", "camera",
            "appManagement", "calendar",
        ], "permission portal contains every supported permission")
        let onboardingViewSource = (try? String(
            contentsOfFile: "Sources/Vorssaint/UI/Onboarding/OnboardingView.swift",
            encoding: .utf8)) ?? ""
        let additionalPermissionsAlignment =
            #"DisclosureGroup\(isExpanded: \$showingOtherPermissions\) \{\s+"#
            + #"VStack\(alignment: \.leading, spacing: 14\)"#
        suite.expect(onboardingViewSource.range(
            of: additionalPermissionsAlignment,
            options: .regularExpression) != nil,
               "the additional onboarding permission rows share one leading edge")
        suite.expect(FeaturePreset.essential.features.flatMap(\.onboardingPermissions).isEmpty,
               "the essential first-run choice asks for no broad permission")
        suite.expect(Set(FeaturePreset.windows.features.flatMap(\.onboardingPermissions))
                == [.accessibility, .screenRecording],
               "the windows first-run choice explains exactly its two broad permissions")
        suite.expect(AppFeature.musicBlock.permissions == [.accessibility]
                && AppFeature.musicBlock.onboardingPermissions.isEmpty,
               "music launch blocking declares its required Accessibility access contextually")
        suite.expect(AppFeature.screenshot.permissions == [.screenRecording]
                && AppFeature.screenshot.onboardingPermissions == [.screenRecording],
               "screenshots only need the screen recording grant")
        suite.expect(AppFeature.screenRecorder.onboardingPermissions
                == [.screenRecording, .accessibility],
               "the recorder choice explains both permissions it needs")
        suite.expect(AppFeature.cleaner.onboardingPermissions.isEmpty
                && AppFeature.cameraPreview.onboardingPermissions.isEmpty,
               "contextual grants are not requested during first setup")
        suite.expect(AppFeature.fanControl.group == .monitor
                && AppFeature.fanControl.enabledKeys.isEmpty
                && AppFeature.fanControl.permissions.isEmpty
                && AppFeature.fanControl.energyProfile == .idle
                && AppFeature.fanControl.isBeta
                && !AppFeature.monitorPower.isBeta,
               "fan control is an on-demand beta with no broad permission")

        // MARK: Hardware-gated installs

        suite.expect(FeaturePreset.allCases.allSatisfy { !$0.features.contains(.fanControl) },
               "no first-run preset installs a feature whose hardware the Mac may lack")

        let featureHubSource = (try? String(
            contentsOfFile: "Sources/Vorssaint/UI/Settings/FeatureHubSettings.swift",
            encoding: .utf8)) ?? ""
        let onboardingFeatureSource = (try? String(
            contentsOfFile: "Sources/Vorssaint/UI/Onboarding/OnboardingView.swift",
            encoding: .utf8)) ?? ""
        suite.expect(featureHubSource.contains("installBlockedReason")
                && onboardingFeatureSource.contains("installBlockedReason"),
               "both feature pickers refuse an unsupported install from the same rule")
        suite.expect(featureHubSource.contains("installableCount"),
               "the hub counts against what this Mac can install, so install-all can finish")
        suite.expect(AppFeature.diskImageInstaller.group == .clipboardFiles
                && AppFeature.diskImageInstaller.enabledKeys.isEmpty
                && AppFeature.diskImageInstaller.permissions == [.appManagement]
                && AppFeature.diskImageInstaller.energyProfile == .idle,
               "the disk image installer is an event-driven file feature with contextual app access")
        suite.expect(AppFeature.bluetoothSleep.group == .energyDisplay
                && AppFeature.bluetoothSleep.enabledKeys == [DefaultsKey.bluetoothSleepEnabled]
                && AppFeature.bluetoothSleep.permissions.isEmpty
                && AppFeature.bluetoothSleep.energyProfile == .idle
                && !AppFeature.bluetoothSleep.isBeta,
               "Bluetooth on sleep is an energy feature that costs nothing at rest")
        suite.expect((AppFeature.availabilityDefaults[AppFeature.bluetoothSleep.availabilityKey] as? Bool) == true,
               "Bluetooth on sleep ships installed, switched off, so its section is findable")
        suite.expect(AppFeature.bluetoothSleep.settingsDestination
                == FeatureSettingsDestination(.energy, sectionAnchor: .bluetoothSleep)
                && AppFeature.bluetoothSleep.settingsDestination.hasValidSectionAnchor
                && FeatureVisibilitySupport.features(for: .energy).contains(.bluetoothSleep),
               "Bluetooth on sleep owns a section of the Energy page and can keep it alive alone")
        suite.expect(BluetoothSleepSupport.sleepPlan(isPoweredOn: true, restoresOnWake: true)
                == BluetoothSleepSupport.SleepPlan(powersOff: true, owesRestore: true),
               "Bluetooth on before sleep is switched off and owed back")
        suite.expect(BluetoothSleepSupport.sleepPlan(isPoweredOn: true, restoresOnWake: false)
                == BluetoothSleepSupport.SleepPlan(powersOff: true, owesRestore: false),
               "without the restore option, sleep switches Bluetooth off for good")
        suite.expect(BluetoothSleepSupport.sleepPlan(isPoweredOn: false, restoresOnWake: true)
                == BluetoothSleepSupport.SleepPlan(powersOff: false, owesRestore: false),
               "Bluetooth already off before sleep is left alone, so the wake never turns it on")
        suite.expect(BluetoothSleepSupport.restores(owesRestore: true, isPoweredOn: false),
               "a wake that still owes a restore switches Bluetooth back on")
        suite.expect(!BluetoothSleepSupport.restores(owesRestore: false, isPoweredOn: false),
               "a wake owing nothing leaves Bluetooth off")
        suite.expect(!BluetoothSleepSupport.restores(owesRestore: true, isPoweredOn: true),
               "Bluetooth the user switched on first is left alone")
        var readControllerPower = false
        func controllerPower() -> Bool { readControllerPower = true; return false }
        _ = BluetoothSleepSupport.restores(owesRestore: false, isPoweredOn: controllerPower())
        suite.expect(!readControllerPower,
               "a launch owing no restore never reads the Bluetooth controller")

        suite.expect((Defaults.registeredDefaults[DefaultsKey.panelShowFanControl] as? Bool) == true,
               "installing fan control reveals its panel section by default")

        for language in AppLanguage.allCases {
            let strings = FeatureStrings.diskImageInstaller(language)
            expectFormat(strings.promptBodyFormat, ["@", "@"],
                         "\(language.rawValue) installer prompt format")
            expectFormat(strings.installedBodyFormat, ["@", "@"],
                         "\(language.rawValue) installer success format")
            expectFormat(strings.installedKeepingMountBodyFormat, ["@", "@"],
                         "\(language.rawValue) installer mounted-image format")
            expectFormat(strings.installedKeepingDownloadBodyFormat, ["@", "@"],
                         "\(language.rawValue) installer kept-download format")
            expectFormat(strings.alreadyInstalledBodyFormat, ["@"],
                         "\(language.rawValue) installer existing-app format")
            expectFormat(strings.installedKeptDownloadBodyFormat, ["@", "@"],
                         "\(language.rawValue) installer kept-by-choice format")
            expectFormat(strings.installingFormat, ["@"],
                         "\(language.rawValue) installer progress format")
        }

        let installerInfo: [String: Any] = [
            "images": [[
                "image-path": "/Users/test/Downloads/App.dmg",
                "system-entities": [[
                    "dev-entry": "/dev/disk9s1",
                    "mount-point": "/private/tmp/Installer Mount",
                ]],
            ]],
        ]
        if let installerData = try? PropertyListSerialization.data(fromPropertyList: installerInfo,
                                                                    format: .xml,
                                                                    options: 0) {
            suite.expect(DiskImageInstallerSupport.imageURL(
                mountedAt: URL(fileURLWithPath: "/tmp/Installer Mount"),
                hdiutilInfo: installerData)?.path == "/Users/test/Downloads/App.dmg",
                "hdiutil plist maps the canonical mount path back to its disk image")
            suite.expect(DiskImageInstallerSupport.imageURL(
                mountedAt: URL(fileURLWithPath: "/tmp/Other Mount"),
                hdiutilInfo: installerData) == nil,
                "an unrelated mounted volume is never treated as the disk image")
        } else {
            suite.expect(false, "disk image installer plist fixture can be encoded")
        }
        suite.expect(DiskImageInstallerSupport.destinationURL(
            for: URL(fileURLWithPath: "/Volumes/Installer/Example.app"),
            applicationsURL: URL(fileURLWithPath: "/Applications", isDirectory: true))?.path
            == "/Applications/Example.app",
            "a top-level app gets one fixed Applications destination")
        suite.expect(DiskImageInstallerSupport.destinationURL(
            for: URL(fileURLWithPath: "/Volumes/Installer/Example.app"),
            applicationsURL: URL(fileURLWithPath: "/Users/test/Applications",
                                 isDirectory: true))?.path
            == "/Users/test/Applications/Example.app",
            "the installer support accepts the current user's Applications directory")
        suite.expect(DiskImageInstallerSupport.applicationsDomain(useUserApplications: false)
                == .localDomainMask
                && DiskImageInstallerSupport.applicationsDomain(useUserApplications: true)
                == .userDomainMask,
               "the disk image setting selects the system or user application domain")
        suite.expect(DiskImageInstallerSupport.collisionDomains(useUserApplications: false)
                == [.localDomainMask]
                && DiskImageInstallerSupport.collisionDomains(useUserApplications: true)
                == [.localDomainMask, .userDomainMask],
               "only the opt-in installer checks both application domains for collisions")
        let installerDestinations = DiskImageInstallerSupport.destinationURLs(
            for: URL(fileURLWithPath: "/Volumes/Installer/Example.app"),
            applicationsURLs: [
                URL(fileURLWithPath: "/Applications", isDirectory: true),
                URL(fileURLWithPath: "/Users/test/Applications", isDirectory: true),
            ])
        suite.expect(installerDestinations?.map(\.path) == [
            "/Applications/Example.app",
            "/Users/test/Applications/Example.app",
        ], "the already-installed guard covers both application directories")
        suite.expect(DiskImageInstallerSupport.destinationURLs(
            for: URL(fileURLWithPath: "/Volumes/Installer/Example.app"),
            applicationsURLs: []) == nil,
            "missing application-domain resolutions fail closed")
        let installerFixture = FileManager.default.temporaryDirectory
            .appendingPathComponent("vorss-installer-\(UUID().uuidString)", isDirectory: true)
        let installerFM = InstallerFileManager(root: installerFixture)
        let installerApp = URL(fileURLWithPath: "/Volumes/Installer/Example.app")
        let missingUserDestination = installerFM.userApplications!
            .appendingPathComponent("Example.app", isDirectory: true)
        let missingFolderCollisions = DiskImageInstallerSupport.collisionURLs(
            for: installerApp, useUserApplications: true, fileManager: installerFM)
        suite.expect(missingFolderCollisions?.contains(missingUserDestination) == true
                && missingFolderCollisions?.allSatisfy { !installerFM.fileExists(atPath: $0.path) } == true,
               "a missing home Applications folder still allows an install candidate")
        suite.expect(!installerFM.fileExists(atPath: installerFixture.path),
               "detecting an install candidate never creates the home Applications folder")
        installerFM.userApplications = nil
        suite.expect(DiskImageInstallerSupport.collisionURLs(
            for: installerApp, useUserApplications: true, fileManager: installerFM) == nil,
            "an unavailable user search path fails closed for opted-in installs")
        suite.expect(DiskImageInstallerSupport.collisionURLs(
            for: installerApp, useUserApplications: false, fileManager: installerFM)?.count == 1,
            "default installs do not depend on the user's application search path")
        suite.expect(DiskImageInstallerSupport.destinationURL(
            for: URL(fileURLWithPath: "/Volumes/Installer/.Hidden.app"),
            applicationsURL: URL(fileURLWithPath: "/Applications", isDirectory: true)) == nil,
            "hidden app bundles cannot create hidden Applications entries")
        suite.expect(DiskImageInstallerSupport.displayName(
            preferred: "  Example\nApp\u{0007}  ",
            appURL: URL(fileURLWithPath: "/Volumes/Installer/Fallback.app")) == "Example App",
            "untrusted bundle names are flattened before entering an alert")

        // MARK: Fan Control safety policy

        suite.expect(FanControlPolicy.coolingDuration == 15 * 60
                && FanControlPolicy.heartbeatLimit < 10,
               "the legacy session stays bounded while current control loses ownership quickly")
        suite.expect(FanControlPolicy.isAutomaticMode(0)
                && FanControlPolicy.isAutomaticMode(3)
                && !FanControlPolicy.isAutomaticMode(1)
                && !FanControlPolicy.isAutomaticMode(2)
                && !FanControlPolicy.isAutomaticMode(.max),
               "fan ownership accepts firmware automatic modes and rejects manual or unknown modes")
        suite.expect(FanControlPolicy.fanCount(from: 1) == 1
                && FanControlPolicy.fanCount(from: 8) == 8
                && FanControlPolicy.fanCount(from: 0) == nil
                && FanControlPolicy.fanCount(from: 9) == nil
                && FanControlPolicy.fanCount(from: 1.5) == nil
                && FanControlPolicy.fanCount(from: .nan) == nil,
               "fan discovery accepts only a small integral hardware count")
        suite.expect(FanControlPolicy.validBounds(minimum: 1_200, maximum: 5_800)
                && !FanControlPolicy.validBounds(minimum: -1, maximum: 5_800)
                && !FanControlPolicy.validBounds(minimum: 5_800, maximum: 5_800)
                && !FanControlPolicy.validBounds(minimum: 1_200, maximum: 25_000),
               "fan bounds must be finite, ordered and physically sane")
        suite.expect(FanControlPolicy.validReading(0)
                && FanControlPolicy.validReading(8_000)
                && !FanControlPolicy.validReading(-1)
                && !FanControlPolicy.validReading(.infinity),
               "fan readings stay within a safe display and verification range")
        suite.expect(FanControlPolicy.minimumCoolingLevel == 0
                && FanControlPolicy.maximumCoolingLevel == 100
                && FanControlPolicy.defaultCoolingLevel == 100
                && FanControlPolicy.validCoolingLevel(0)
                && FanControlPolicy.validCoolingLevel(55)
                && FanControlPolicy.validCoolingLevel(100)
                && !FanControlPolicy.validCoolingLevel(-5)
                && !FanControlPolicy.validCoolingLevel(26),
               "manual cooling accepts the full bounded five-percent scale")
        suite.expect(FanControlPolicy.coolingTargetRPM(minimum: 1_200, maximum: 5_800,
                                                 level: 0) == 1_200
                && FanControlPolicy.coolingTargetRPM(minimum: 1_200, maximum: 5_800,
                                                     level: 25) == 2_350
                && FanControlPolicy.coolingTargetRPM(minimum: 1_200, maximum: 5_800,
                                                     level: 100) == 5_800
                && FanControlPolicy.coolingTargetRPM(minimum: 5_800, maximum: 5_800,
                                                     level: 100) == nil,
               "manual targets map the full percentage scale into reported hardware bounds")
        suite.expect(FanControlPolicy.targetRPMMatches(target: 3_121, expected: 3_121)
                && FanControlPolicy.targetRPMMatches(target: 3_122, expected: 3_121)
                && FanControlPolicy.targetRPMMatches(target: 1_201.5, expected: 1_200)
                && !FanControlPolicy.targetRPMMatches(target: 3_500, expected: 3_121)
                && !FanControlPolicy.targetRPMMatches(target: 1_205, expected: 1_200)
                && !FanControlPolicy.targetRPMMatches(target: .nan, expected: 1_200),
               "fan target verification allows a narrow tolerance and rejects stale or malformed targets")
        suite.expect(FanControlPolicy.forceTestSatisfied(keyExists: false, writeSucceeded: false)
                && FanControlPolicy.forceTestSatisfied(keyExists: false, writeSucceeded: true)
                && FanControlPolicy.forceTestSatisfied(keyExists: true, writeSucceeded: true)
                && !FanControlPolicy.forceTestSatisfied(keyExists: true, writeSucceeded: false),
               "the manual-mode fallback needs the force-test override only where the Mac exposes it")

        let defaultCurve = FanControlConfiguration.defaultCurve
        suite.expect(FanControlPolicy.validConfiguration(.manual(level: 0))
                && FanControlPolicy.validConfiguration(.manual(level: 100))
                && FanControlPolicy.validConfiguration(.curve([defaultCurve]))
                && FanControlPolicy.interpolatedCoolingLevel(points: defaultCurve.points,
                                                             temperature: 40) == 0
                && FanControlPolicy.interpolatedCoolingLevel(points: defaultCurve.points,
                                                             temperature: 60) == 50
                && FanControlPolicy.interpolatedCoolingLevel(points: defaultCurve.points,
                                                             temperature: 61) == 55
                && FanControlPolicy.interpolatedCoolingLevel(points: defaultCurve.points,
                                                             temperature: 80) == 100,
               "the default curve starts at 50 degrees, reaches maximum at 70 and rounds safely up")
        let coolingTemperature = [
            FanControlTemperatureReading(source: .hottestSoC, celsius: 59),
        ]
        suite.expect(FanControlPolicy.curveCoolingLevel(curves: [defaultCurve],
                                                  temperatures: coolingTemperature,
                                                  previousLevel: 50) == 50
                && FanControlPolicy.curveCoolingLevel(
                    curves: [defaultCurve],
                    temperatures: [.init(source: .hottestSoC, celsius: 57)],
                    previousLevel: 50
                ) == 45,
               "a cooling curve uses two-degree hysteresis before lowering fan speed")
        let cpuCurve = FanControlCurve(
            sensor: .averageCPU,
            points: [FanControlCurvePoint(temperature: 40, coolingLevel: 0),
                     FanControlCurvePoint(temperature: 80, coolingLevel: 80)]
        )
        let curveTemperatures = [
            FanControlTemperatureReading(source: .hottestSoC, celsius: 54),
            FanControlTemperatureReading(source: .averageCPU, celsius: 70),
        ]
        suite.expect(FanControlPolicy.curveCoolingLevel(curves: [defaultCurve, cpuCurve],
                                                  temperatures: curveTemperatures) == 60
                && FanControlPolicy.curveCoolingLevel(curves: [defaultCurve, cpuCurve],
                                                      temperatures: [curveTemperatures[0]]) == nil,
               "several temperature rules use their highest demand and require every selected sensor")
        let duplicateCurves = [defaultCurve,
                               FanControlCurve(sensor: .hottestSoC, points: cpuCurve.points)]
        let descendingCurve = FanControlCurve(
            sensor: .averageCPU,
            points: [FanControlCurvePoint(temperature: 50, coolingLevel: 80),
                     FanControlCurvePoint(temperature: 70, coolingLevel: 40)]
        )
        suite.expect(!FanControlPolicy.validCurves(duplicateCurves)
                && !FanControlPolicy.validCurves([descendingCurve])
                && FanControlConfiguration.decodeCurves(
                    FanControlConfiguration.encodeCurves([defaultCurve]) ?? "") == [defaultCurve]
                && FanControlConfiguration.decodeCurves("not json") == nil,
               "stored curves reject duplicate sensors, unsafe slopes and malformed data")
        let resumedManual = FanControlConfiguration.manual(level: 100)
        let resumedCurves = FanControlConfiguration.curve([defaultCurve, cpuCurve])
        suite.expect(FanControlConfiguration.decodeResume(
                    FanControlConfiguration.encodeResume(resumedManual) ?? "") == resumedManual
                && FanControlConfiguration.decodeResume(
                    FanControlConfiguration.encodeResume(resumedCurves) ?? "") == resumedCurves,
               "a resumed manual speed or curve comes back exactly as the user applied it")
        suite.expect(FanControlConfiguration.encodeResume(
                    FanControlConfiguration(mode: .system, manualLevel: 100, curves: [])) == nil
                && FanControlConfiguration.encodeResume(.manual(level: 37)) == nil
                && FanControlConfiguration.encodeResume(.curve([descendingCurve])) == nil
                && FanControlConfiguration.decodeResume(
                    #"{"curves":[],"manualLevel":100,"mode":"system"}"#) == nil
                && FanControlConfiguration.decodeResume(
                    #"{"curves":[],"manualLevel":37,"mode":"manual"}"#) == nil
                && FanControlConfiguration.decodeResume("") == nil
                && FanControlConfiguration.decodeResume("not json") == nil,
               "only a valid manual speed or curve is ever kept or brought back after a restart")
        FanControlResumeContract.run(suite)
        let addedPoints = FanControlPolicy.addingCurvePoint(to: defaultCurve.points)
        suite.expect(FanControlPolicy.nextCurvePoint(for: defaultCurve.points) == FanControlCurvePoint(temperature: 60, coolingLevel: 50)
                && addedPoints == [
                    FanControlCurvePoint(temperature: 50, coolingLevel: 0),
                    FanControlCurvePoint(temperature: 60, coolingLevel: 50),
                    FanControlCurvePoint(temperature: 70, coolingLevel: 100),
                ]
                && FanControlPolicy.validCurve(FanControlCurve(sensor: .hottestSoC, points: addedPoints ?? [])),
               "adding a fan curve point calculates the intermediate point and produces a valid sorted curve")
        var iterativePoints = defaultCurve.points
        while let next = FanControlPolicy.addingCurvePoint(to: iterativePoints) {
            iterativePoints = next
        }
        suite.expect(iterativePoints.count == FanControlPolicy.maximumCurvePointCount
                && FanControlPolicy.validCurve(FanControlCurve(sensor: .hottestSoC, points: iterativePoints))
                && FanControlPolicy.nextCurvePoint(for: iterativePoints) == nil
                && FanControlPolicy.addingCurvePoint(to: iterativePoints) == nil,
               "adding fan curve points fills up to the maximum point limit with strictly valid curves")
        let secondCurve = FanControlCurve(sensor: .averageCPU,
                                          points: defaultCurve.points)
        var updatedCurves = [defaultCurve, secondCurve]
        if let secondPoints = FanControlPolicy.addingCurvePoint(to: updatedCurves[1].points) {
            updatedCurves[1].points = secondPoints
        }
        let storedUpdatedCurves = FanControlConfiguration.decodeCurves(
            FanControlConfiguration.encodeCurves(updatedCurves) ?? ""
        )
        suite.expect(updatedCurves.count == 2
                && updatedCurves.first == defaultCurve
                && updatedCurves[1].points == addedPoints
                && storedUpdatedCurves == updatedCurves,
               "adding a point to the second fan curve preserves every valid stored curve")
        let m3FanTemperatures = FanControlPolicy.aggregatedTemperatures(
            cpuReadings: [("Te05", 44), ("Tf4E", 53), ("Tf4F", 76)],
            gpuReadings: [48],
            platform: .appleM3Family
        )
        suite.expectClose(m3FanTemperatures.first { $0.source == .hottestCPU }?.celsius ?? -1,
                    53,
                    "M3 fan curves include the hottest mapped Tf CPU core")
        suite.expectClose(m3FanTemperatures.first { $0.source == .averageCPU }?.celsius ?? -1,
                    48.5,
                    "M3 fan curves exclude auxiliary Tf readings from the CPU average")
        let unmappedFanTemperatures = FanControlPolicy.aggregatedTemperatures(
            cpuReadings: [("Tp00", 48), ("Tp0W", 113)],
            gpuReadings: [],
            platform: .unmappedAppleSilicon
        )
        suite.expect(unmappedFanTemperatures.isEmpty,
               "fan curves reject unknown Apple Silicon sensors instead of treating them as CPU")
        suite.expect(FanControlPolicy.telemetryReadings(expectedCount: 1, readings: [1_200]) == [1_200]
                && FanControlPolicy.telemetryReadings(expectedCount: 2,
                                                      readings: [1_200, 1_350]) == [1_200, 1_350],
               "fan telemetry preserves one or several ordered readings")
        suite.expect(FanControlPolicy.telemetryReadings(expectedCount: 0, readings: []) == nil
                && FanControlPolicy.telemetryReadings(expectedCount: 2, readings: [1_200]) == nil
                && FanControlPolicy.telemetryReadings(expectedCount: 2, readings: [1_200, nil]) == nil
                && FanControlPolicy.telemetryReadings(expectedCount: 1, readings: [.infinity]) == nil
                && FanControlPolicy.telemetryReadings(expectedCount: 1, readings: [-1]) == nil,
               "fan telemetry rejects no-fan, missing and malformed sensor sets")
        suite.expect(FanControlPolicy.menuBarValue(for: [1_249.6]) == "1250"
                && FanControlPolicy.menuBarValue(for: [1_200, 1_350]) == "1200/1350"
                && FanControlPolicy.menuBarValue(for: []) == nil
                && FanControlPolicy.menuBarValue(for: [.infinity]) == nil,
               "fan RPM menu bar text supports one or several validated fans")
        suite.expect(FanControlPolicy.menuBarWidthUnits(fanCount: 1) == 12
                && FanControlPolicy.menuBarWidthUnits(fanCount: 2) == 18
                && FanControlPolicy.menuBarWidthUnits(fanCount: 0) == 0,
               "fan RPM menu bar width reserves one or several five-digit readings")

        let floatRPM = SMCValueCodec.encode(4_850, type: "flt ", size: 4)
        suite.expect(floatRPM.flatMap { SMCValueCodec.decode($0, type: "flt ") } == 4_850,
               "native fan RPM floats round-trip exactly")
        let fixedRPM = SMCValueCodec.encode(4_850.25, type: "fpe2", size: 2)
        suite.expect(fixedRPM.flatMap { SMCValueCodec.decode($0, type: "fpe2") } == 4_850.25,
               "fixed-point fan RPM values round-trip at quarter-RPM precision")
        suite.expect(SMCValueCodec.decode([0x12, 0x34], type: "ui16") == 0x1234
                && SMCValueCodec.decode([0, 0, 1, 2], type: "ui32") == 258
                && SMCValueCodec.encode(1, type: "ui8 ", size: 1) == [1],
               "SMC integer types preserve their documented byte order")
        suite.expect(SMCValueCodec.encode(-1, type: "flt ", size: 4) == nil
                && SMCValueCodec.encode(30_000, type: "fpe2", size: 2) == nil
                && SMCValueCodec.encode(1, type: "myst", size: 1) == nil,
               "SMC writes reject negative, overflowing and unknown encodings")

        let watchdogEnd = Date(timeIntervalSince1970: 2_000)
        suite.expect(FanControlPolicy.restoreReason(now: watchdogEnd,
                                              endsAt: watchdogEnd,
                                              heartbeatAge: 0,
                                              verificationFailures: 0,
                                              thermalState: .nominal) == .timeLimit,
               "the watchdog still honors a deadline from a legacy helper request")
        suite.expect(FanControlPolicy.restoreReason(now: watchdogEnd,
                                              endsAt: nil,
                                              heartbeatAge: 0,
                                              verificationFailures: 0,
                                              thermalState: .nominal) == nil,
               "current manual and curve control have no arbitrary time limit")
        suite.expect(FanControlPolicy.restoreReason(now: Date(timeIntervalSince1970: 1_900),
                                              endsAt: watchdogEnd,
                                              heartbeatAge: FanControlPolicy.heartbeatLimit + 0.1,
                                              verificationFailures: 0,
                                              thermalState: .nominal) == .heartbeatLost,
               "the watchdog restores when the app heartbeat stops")
        suite.expect(FanControlPolicy.restoreReason(now: Date(timeIntervalSince1970: 1_900),
                                              endsAt: watchdogEnd,
                                              heartbeatAge: 0,
                                              verificationFailures: FanControlPolicy.verificationFailureLimit,
                                              thermalState: .nominal) == .hardwareChanged,
               "the watchdog restores after repeated hardware verification failures")
        suite.expect(FanControlPolicy.restoreReason(now: Date(timeIntervalSince1970: 1_900),
                                              endsAt: watchdogEnd,
                                              heartbeatAge: 0,
                                              verificationFailures: 0,
                                              temperatureFailures: FanControlPolicy.temperatureFailureLimit,
                                              thermalState: .nominal) == .temperatureUnavailable,
               "a curve returns control after repeated missing temperature readings")
        suite.expect(FanControlPolicy.restoreReason(now: Date(timeIntervalSince1970: 1_900),
                                              endsAt: watchdogEnd,
                                              heartbeatAge: 0,
                                              verificationFailures: 0,
                                              thermalState: .serious) == .thermalPressure,
               "the watchdog returns control to the system under thermal pressure")
        suite.expect(FanControlPolicy.restoreReason(now: Date(timeIntervalSince1970: 1_900),
                                              endsAt: watchdogEnd,
                                              heartbeatAge: 0,
                                              verificationFailures: 0,
                                              thermalState: .fair) == nil,
               "a fair thermal state does not cancel the user's selected control")
        suite.expect(FanControlPolicy.restoreReason(now: Date(timeIntervalSince1970: 1_900),
                                              endsAt: watchdogEnd,
                                              heartbeatAge: 0,
                                              verificationFailures: 0,
                                              thermalState: .nominal) == nil,
               "a healthy maximum-cooling session remains active")

        for language in AppLanguage.allCases {
            let strings = FeatureStrings.fanControl(language)
            expectFormat(strings.fanNameFormat, ["d"],
                         "fan name format stays valid for \(language.rawValue)")
            expectFormat(strings.rpmFormat, ["d"],
                         "fan speed format stays valid for \(language.rawValue)")
            expectFormat(strings.currentRPMFormat, ["d"],
                         "current fan speed format stays valid for \(language.rawValue)")
            expectFormat(strings.targetRPMFormat, ["d"],
                         "target fan speed format stays valid for \(language.rawValue)")
        }
        suite.expect(FanControlFeatureStrings.ru.rpmFormat == "%d об/мин"
                && FanControlFeatureStrings.de.rpmFormat == "%d U/min"
                && FanControlFeatureStrings.fr.rpmFormat == "%d tr/min",
               "existing localized RPM units stay intact")

        let legacyFanSnapshot = Data(#"{"fans":[],"isCooling":false}"#.utf8)
        let decodedLegacyFanSnapshot = try? JSONDecoder().decode(FanControlSnapshot.self,
                                                                  from: legacyFanSnapshot)
        suite.expect(decodedLegacyFanSnapshot != nil
                && decodedLegacyFanSnapshot?.coolingLevel == nil
                && decodedLegacyFanSnapshot?.configuration == nil
                && decodedLegacyFanSnapshot?.temperatures == nil,
               "fan snapshots remain compatible with an older installed helper")

        let fanMigrationSuite = "com.vorssaint.tests.fan-migration.\(UUID().uuidString)"
        if let fanMigration = UserDefaults(suiteName: fanMigrationSuite) {
            fanMigration.set(true, forKey: DefaultsKey.monitorShowFanControlBeta)
            Defaults.migrateFanControlVisibility(in: fanMigration)
            suite.expect(fanMigration.bool(forKey: DefaultsKey.panelShowFanControl)
                    && fanMigration.bool(forKey: AppFeature.fanControl.availabilityKey)
                    && fanMigration.object(forKey: DefaultsKey.monitorShowFanControlBeta) == nil,
                   "an old fan opt-in keeps the feature installed and visible")

            fanMigration.removePersistentDomain(forName: fanMigrationSuite)
            fanMigration.set(false, forKey: DefaultsKey.monitorShowFanControlBeta)
            Defaults.migrateFanControlVisibility(in: fanMigration)
            suite.expect(!fanMigration.bool(forKey: DefaultsKey.panelShowFanControl)
                    && fanMigration.object(forKey: AppFeature.fanControl.availabilityKey) == nil,
                   "an old fan opt-out does not install the feature")

            fanMigration.removePersistentDomain(forName: fanMigrationSuite)
            fanMigration.set(false, forKey: DefaultsKey.panelShowFanControl)
            fanMigration.set(false, forKey: AppFeature.fanControl.availabilityKey)
            fanMigration.set(true, forKey: DefaultsKey.monitorShowFanControlBeta)
            Defaults.migrateFanControlVisibility(in: fanMigration)
            suite.expect(!fanMigration.bool(forKey: DefaultsKey.panelShowFanControl)
                    && !fanMigration.bool(forKey: AppFeature.fanControl.availabilityKey),
                   "newer fan choices win over the legacy opt-in")
            fanMigration.removePersistentDomain(forName: fanMigrationSuite)
        } else {
            suite.expect(false, "fan visibility migration suite can be created")
        }

        func activeSet(_ permission: AppPermission,
                       available: Set<AppFeature> = Set(AppFeature.allCases),
                       on: Set<String> = [],
                       strings: [String: String] = [:]) -> Set<AppFeature> {
            Set(AppFeature.activeFeatures(using: permission,
                                          isAvailable: { available.contains($0) },
                                          boolFor: { on.contains($0) },
                                          stringFor: { strings[$0] }))
        }

        suite.expect(PermissionPollingSupport.interval(visibleSurfaceCount: 0,
                                                 accessibilityIsNeeded: false,
                                                 screenRecordingIsNeeded: false,
                                                 accessibilityIsGranted: false,
                                                 screenRecordingIsGranted: false) == nil,
               "permissions keep no background timer without a live feature or visible surface")
        suite.expect(PermissionPollingSupport.interval(visibleSurfaceCount: 1,
                                                 accessibilityIsNeeded: false,
                                                 screenRecordingIsNeeded: false,
                                                 accessibilityIsGranted: true,
                                                 screenRecordingIsGranted: true) == 2.5,
               "a visible permission surface refreshes grants promptly")
        suite.expect(PermissionPollingSupport.interval(visibleSurfaceCount: 0,
                                                 accessibilityIsNeeded: true,
                                                 screenRecordingIsNeeded: false,
                                                 accessibilityIsGranted: false,
                                                 screenRecordingIsGranted: true) == 2.5,
               "a live feature waiting for its grant refreshes promptly")
        suite.expect(PermissionPollingSupport.interval(visibleSurfaceCount: 0,
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
        suite.expect(!AppFeature.windowLayout.monitorsPermissionChanges(boolFor: { _ in false })
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
        suite.expect(!AppFeature.windowLayout.monitorsPermissionChanges(
                   edgeSnapDisabledZones: WindowEdgeSnapZone.disabledZonesStorageValue(
                       WindowEdgeSnapZone.allEnabled
                   ),
                   boolFor: { $0 == DefaultsKey.windowEdgeSnapEnabled }
               ),
               "Window Layout does not poll permissions when every snap zone is off")

        suite.expect(activeSet(.accessibility)
                == [.windowLayout, .cleaningMode, .commandBar, .screenRecorder],
               "with nothing enabled only on-demand features use accessibility")
        func radialMenuUsesAccessibility(_ profile: RadialMenuProfile, legacyItems: [RadialMenuItem]) -> Bool {
            let stored = [DefaultsKey.radialMenuProfiles: RadialMenuSupport.encodeProfiles([profile]),
                          DefaultsKey.radialMenuItems: RadialMenuSupport.encode(legacyItems)]
            return AppFeature.activeFeatures(using: .accessibility,
                                             isAvailable: { _ in true },
                                             boolFor: { $0 == DefaultsKey.radialMenuEnabled },
                                             stringFor: { _ in nil },
                                             dataFor: { stored[$0] ?? nil })
                .contains(.radialMenu)
        }
        let appItem = RadialMenuItem(kind: .app, payload: "/Applications/Safari.app")
        let shortcutItem = RadialMenuItem(kind: .shortcut, payload: "control+option+command:49")
        suite.expect(radialMenuUsesAccessibility(
                    RadialMenuProfile(mouseButton: RadialMenuMouseTrigger.back.rawValue, items: [appItem]),
                    legacyItems: [appItem])
                && !radialMenuUsesAccessibility(RadialMenuProfile(items: [appItem]), legacyItems: [shortcutItem]),
               "radial menu accessibility follows the saved profiles, not the pre-profile wheel")
        suite.expect(activeSet(.accessibility, on: [DefaultsKey.scrollInverterEnabled]).contains(.scrollInverter),
               "an enabled feature counts as using its permission")
        suite.expect(activeSet(.accessibility, on: [DefaultsKey.scrollInverterHorizontalEnabled])
                .contains(.scrollInverter),
               "horizontal-only inversion counts as using accessibility")
        suite.expect(AppFeature.scrollInverter.enabledKeys == [DefaultsKey.scrollInverterEnabled,
                                                           DefaultsKey.scrollInverterHorizontalEnabled],
               "the inversion feature tracks only its own axes")
        suite.expect(activeSet(.accessibility, on: [DefaultsKey.focusFollowsMouseEnabled])
                .contains(.focusFollowsMouse),
               "focus follows mouse reports its live accessibility use")
        suite.expect(activeSet(.accessibility, on: [DefaultsKey.mouseClickDebounceEnabled])
                .contains(.mouseClickDebounce)
                && AppFeature.mouseClickDebounce.enabledKeys
                    == [DefaultsKey.mouseClickDebounceEnabled]
                && AppFeature.mouseClickDebounce.permissions == [.accessibility]
                && AppFeature.mouseClickDebounce.group == .mouseKeyboard,
               "mouse click debounce reports its switch, permission and feature group")
        suite.expect(activeSet(.accessibility, available: [.musicBlock], on: [DefaultsKey.musicBlockEnabled]) == [.musicBlock]
                && activeSet(.accessibility, available: [.musicBlock]).isEmpty
                && activeSet(.accessibility, available: [], on: [DefaultsKey.musicBlockEnabled]).isEmpty,
               "music blocking requires access only while both enabled and installed")
        suite.expect(activeSet(.accessibility, on: [DefaultsKey.finderRenameEnabled]).contains(.finderRename),
               "the enabled Finder rename shortcut uses accessibility")
        suite.expect(!activeSet(.accessibility, available: [], on: [DefaultsKey.scrollInverterEnabled])
                .contains(.scrollInverter),
               "an unavailable feature never uses a permission")
        suite.expect(activeSet(.accessibility, on: [DefaultsKey.keepAwakeMouseJiggleEnabled]).contains(.keepAwake),
               "keep awake uses accessibility only with the mouse jiggle on")
        suite.expect(!activeSet(.accessibility).contains(.keepAwake),
               "keep awake without jiggle does not use accessibility")
        suite.expect(activeSet(.accessibility, on: [DefaultsKey.brightnessControlEnabled,
                                              DefaultsKey.brightnessKeysEnabled]).contains(.brightness),
               "brightness uses accessibility only for the key option")
        suite.expect(activeSet(.accessibility, on: [DefaultsKey.brightnessControlEnabled,
                                              DefaultsKey.brightnessOSDEnabled]).contains(.brightness),
               "brightness uses accessibility for the adjustment overlay")
        suite.expect(!activeSet(.accessibility, on: [DefaultsKey.brightnessControlEnabled])
                .contains(.brightness),
               "brightness sliders alone never use accessibility")
        suite.expect(activeSet(.accessibility).contains(.screenRecorder),
               "the recorder uses accessibility for anonymous typing timing while active")
        suite.expect(activeSet(.accessibility, on: [DefaultsKey.preciseVolumeRollerEnabled]).contains(.mixer),
               "mixer uses accessibility only for precise volume roller")
        suite.expect(!activeSet(.accessibility).contains(.mixer),
               "mixer without precise volume roller does not use accessibility")

        suite.expect(activeSet(.screenRecording, on: [DefaultsKey.switcherEnabled])
                == [.switcher, .screenOCR, .screenshot, .screenRecorder],
               "switcher with previews uses screen recording; OCR, screenshots and recordings are on demand")
        suite.expect(activeSet(.screenRecording,
                         on: [DefaultsKey.switcherEnabled, DefaultsKey.switcherSimpleMode])
                == [.screenOCR, .screenshot, .screenRecorder],
               "simple-mode switcher stops using screen recording")
        suite.expect(activeSet(.screenRecording,
                         on: [DefaultsKey.switcherSimpleMode, DefaultsKey.dockPreviewEnabled])
                .contains(.dockPreview),
               "dock preview keeps screen recording in use regardless of switcher mode")
        suite.expect(AppFeature.dockClick.enabledKeys == [DefaultsKey.dockClickMinimize,
                                                    DefaultsKey.dockClickHide,
                                                    DefaultsKey.dockClickCycleWindows],
               "the Dock click feature tracks every action that can keep its shared tap alive")

        suite.expect(activeSet(.notifications) == [],
               "no alerts and no schedule means notifications are unused")
        suite.expect(activeSet(.notifications, on: [DefaultsKey.monitorAlertCPUTemperature]) == [.monitorCPU],
               "a CPU temperature alert marks the CPU monitor as notifying")
        suite.expect(activeSet(.notifications, on: [DefaultsKey.monitorAlertBatteryTemperature]) == [.monitorPower],
               "a battery temperature alert marks the power monitor as notifying")
        suite.expect(activeSet(.notifications,
                         available: Set(AppFeature.allCases).subtracting([.monitorCPU]),
                         on: [DefaultsKey.monitorAlertCPU]) == [],
               "an alert whose metric is unavailable does not notify")
        suite.expect(activeSet(.notifications, on: [DefaultsKey.cleanerScheduleNotify],
                         strings: [DefaultsKey.cleanerScheduleFrequency: "weekly"]) == [.cleaner],
               "a scheduled cleaner with notice enabled uses notifications")
        suite.expect(activeSet(.notifications, on: [DefaultsKey.cleanerScheduleNotify],
                         strings: [DefaultsKey.cleanerScheduleFrequency: "off"]) == [],
               "an unscheduled cleaner does not use notifications")
        suite.expect(activeSet(.notifications,
                         on: [DefaultsKey.whatsAppDownloadsAutomaticEnabled,
                              DefaultsKey.whatsAppDownloadsNotify]) == [],
               "WhatsApp cleanup notifications stay unused until that cleaner is turned on")
        suite.expect(activeSet(.notifications,
                         on: [DefaultsKey.whatsAppDownloadsEnabled,
                              DefaultsKey.whatsAppDownloadsAutomaticEnabled,
                              DefaultsKey.whatsAppDownloadsNotify]) == [.cleaner],
               "WhatsApp cleanup only uses notifications for an opted-in automatic summary")
        suite.expect(activeSet(.notifications,
                         on: [DefaultsKey.whatsAppOrganizerEnabled,
                              DefaultsKey.whatsAppDownloadsNotify]) == [],
               "the experimental WhatsApp organizer stays silent until that cleaner is turned on")
        suite.expect(activeSet(.notifications,
                         on: [DefaultsKey.whatsAppDownloadsEnabled,
                              DefaultsKey.whatsAppOrganizerEnabled,
                              DefaultsKey.whatsAppDownloadsNotify]) == [.cleaner],
               "the experimental WhatsApp organizer can offer an undo notification")
        suite.expect(activeSet(.filesAndFolders) == [],
               "WhatsApp Downloads folder access stays unused until that cleaner is turned on")
        suite.expect(activeSet(.filesAndFolders, on: [DefaultsKey.whatsAppDownloadsEnabled]) == [.cleaner],
               "the cleaner owns WhatsApp Downloads folder access")

        suite.expect(activeSet(.fullDiskAccess) == [.cleaner, .uninstaller],
               "cleaner and uninstaller are on-demand full disk users")
        suite.expect(activeSet(.automationFinder, on: [DefaultsKey.finderCutPasteEnabled])
                == [.finderCutPaste, .uninstaller, .quickToggles],
               "finder automation is used by cut and paste, the uninstaller and the quick toggles")
        suite.expect(activeSet(.automationFinder, on: [DefaultsKey.finderPasteImageAsFile])
                == [.finderCutPaste, .uninstaller, .quickToggles],
               "pasting copied images as files engages the shared Finder feature")
        suite.expect(AppFeature.quickToggles.permissions == [.automationFinder],
               "the quick toggles need no permission beyond the Trash's Finder ask")
        suite.expect(activeSet(.automationTerminal) == [.homebrew], "homebrew drives the Terminal")
        suite.expect(activeSet(.appManagement) == [.homebrew, .appUpdates, .diskImageInstaller],
               "package, update and disk-image installs declare App Management access")
        suite.expect(AppFeature.homebrew.permissions == [.automationTerminal, .appManagement],
               "the package manager declares both permissions used by its operations")
        suite.expect(activeSet(.audioCapture) == [.mixer], "the mixer is the only audio capture user")
        suite.expect(activeSet(.audioCapture, available: Set(AppFeature.allCases).subtracting([.mixer])) == [],
               "audio capture reads as unused once the mixer is off in the hub")
        suite.expect(activeSet(.audioCapture, on: [DefaultsKey.recorderSystemAudio]) == [.mixer, .screenRecorder],
               "the recorder uses audio capture only while the Mac's sound is a chosen source")
        suite.expect(activeSet(.microphone).isEmpty
                && activeSet(.microphone, on: [DefaultsKey.recorderMicrophone]) == [.screenRecorder],
               "the recorder uses microphone access only when that optional source is on")
        suite.expect(activeSet(.camera) == [.cameraPreview],
               "the camera preview is the only on-demand camera user")
        suite.expect(activeSet(.camera, available: Set(AppFeature.allCases).subtracting([.cameraPreview])) == [],
               "the camera reads as unused once the preview is off in the hub")
        suite.expect(AppFeature.cameraPreview.permissions == [.camera]
                && AppFeature.cameraPreview.enabledKeys.isEmpty,
               "the camera preview works on demand and only ever asks for the camera")

        suite.expect(!AppFeature.anyMonitorAlertEnabled(isAvailable: { _ in true }, boolFor: { _ in false }),
               "no alert keys means no monitor alerts")
        suite.expect(AppFeature.anyMonitorAlertEnabled(isAvailable: { _ in true },
                                                 boolFor: { $0 == DefaultsKey.monitorAlertDisk }),
               "one alert on an available metric arms the alert service")
        suite.expect(AppFeature.anyMonitorAlertEnabled(isAvailable: { _ in true },
                                                 boolFor: {
                                                     $0 == DefaultsKey.monitorAlertBatteryTemperature
                                                 }),
               "a battery temperature alert arms the alert service")
        suite.expect(!AppFeature.anyMonitorAlertEnabled(isAvailable: { $0 != .monitorPower },
                                                  boolFor: {
                                                      $0 == DefaultsKey.monitorAlertBatteryTemperature
                                                  }),
               "a battery temperature alert stays disarmed without the power metric")
        suite.expect(!AppFeature.anyMonitorAlertEnabled(isAvailable: { $0 != .monitorDisk },
                                                  boolFor: { $0 == DefaultsKey.monitorAlertDisk }),
               "an alert with its metric off in the hub stays disarmed")

        suite.expect(GlobalShortcutRole.activeRoles(isOn: { _ in true }).count
                == GlobalShortcutRole.allCases.count,
               "the availability-free overload keeps every enabled current role")
        suite.expect(!GlobalShortcutRole.activeRoles(isOn: { _ in true },
                                               isAvailable: { $0 != .shelf }).contains(.shelf),
               "a role leaves the shortcuts page when its feature is off in the hub")
        suite.expect(GlobalShortcutRole.activeRoles(isOn: { _ in true },
                                              isAvailable: { $0 != .switcher })
                .allSatisfy { $0 != .switcher && $0 != .switcherWindow },
               "both switcher roles follow the switcher feature")
        suite.expect(GlobalShortcutRole.availableRoles(isAvailable: { $0 != .switcher })
                .allSatisfy { $0 != .switcher && $0 != .switcherWindow },
               "the shortcut editor lists installed roles even without reading enable keys")
        for role in [GlobalShortcutRole.displayBrightnessDecrease, .displayBrightnessIncrease] {
            suite.expect(role.feature == .brightness && role.group == .energyDisplay,
                   "display shortcuts appear with display controls")
            for disabled in [DefaultsKey.brightnessControlEnabled, DefaultsKey.displayBrightnessShortcutsEnabled] {
                suite.expect(!GlobalShortcutRole.activeRoles(isOn: { $0 != disabled }).contains(role),
                       "display shortcuts release their keys when either toggle is off")
            }
            suite.expect(!GlobalShortcutRole.activeRoles(isOn: { _ in true },
                        isAvailable: { $0 != .brightness }).contains(role),
                   "display shortcuts follow feature availability")
            suite.expect((Defaults.registeredDefaults[role.storageKey] as? String)
                    == role.defaultShortcut.storageValue,
                   "display shortcut defaults match their registered preferences")
        }
        suite.expect(BrightnessSupport.shortcutDisplay(followsPointer: true, pointerDisplay: 2,
                   primaryDisplay: 1, eligible: [1, 2]) == 2,
               "display shortcuts follow the pointer onto an external monitor")
        suite.expect(BrightnessSupport.shortcutDisplay(followsPointer: false, pointerDisplay: 2,
                   primaryDisplay: 1, eligible: [1, 2]) == 1,
               "display shortcuts use the primary display when pointer routing is off")
        suite.expect(BrightnessSupport.shortcutDisplay(followsPointer: true, pointerDisplay: 2,
                   primaryDisplay: 1, eligible: [1]) == nil,
               "an unavailable pointer target never changes a different display")
        suite.expect(BrightnessSupport.shortcutDisplay(followsPointer: true, pointerDisplay: nil,
                   primaryDisplay: 1, eligible: [1]) == nil,
               "a missing pointer target does not dim the primary display")
        suite.expect(BrightnessSupport.shortcutDisplay(followsPointer: false, pointerDisplay: 2,
                   primaryDisplay: 1, eligible: [2]) == nil,
               "an unavailable primary display never redirects the shortcut")

        suite.expect(GlobalShortcutRole.keyboardBrightnessDecrease.feature == .brightness
                && GlobalShortcutRole.keyboardBrightnessIncrease.feature == .brightness
                && GlobalShortcutRole.keyboardBrightnessDecrease.group == .mouseKeyboard
                && GlobalShortcutRole.keyboardBrightnessIncrease.group == .mouseKeyboard,
               "keyboard brightness stays owned by the brightness service but appears with keyboard controls")
        let shortcutsPage = ShortcutsPage(state: Expansion())
        let displayBrightness = shortcutsPage.expansionBinding(for: .brightness, in: .energyDisplay)
        let keyboardLight = shortcutsPage.expansionBinding(for: .brightness, in: .mouseKeyboard)
        displayBrightness.wrappedValue = true
        suite.expect(displayBrightness.wrappedValue && !keyboardLight.wrappedValue,
               "opening brightness in one shortcut group leaves its row in the other group closed")
        keyboardLight.wrappedValue = true
        displayBrightness.wrappedValue = false
        suite.expect(!displayBrightness.wrappedValue && keyboardLight.wrappedValue,
               "closing brightness in one shortcut group leaves an open row in the other group open")
        suite.expect(GlobalShortcutRole.keyboardBrightnessDecrease.requiredEnableKeys
                == [DefaultsKey.keyboardBrightnessShortcutsEnabled]
                && GlobalShortcutRole.keyboardBrightnessIncrease.requiredEnableKeys
                == [DefaultsKey.keyboardBrightnessShortcutsEnabled],
               "keyboard brightness shortcuts require explicit opt-in")
        suite.expect(!GlobalShortcutRole.activeRoles(isOn: { _ in false })
                .contains(where: \.isKeyboardBrightness),
               "keyboard brightness shortcuts reserve no combination before opt-in")
        suite.expect(!GlobalShortcutRole.activeRoles(isOn: { _ in true }, isAvailable: { $0 != .brightness })
                .contains(where: \.isKeyboardBrightness),
               "removing the brightness feature releases both keyboard shortcuts")

        let superSpace = GlobalShortcut(keyCode: Int64(kVK_Space), modifiers: .validMask)
        let customSuperSpace = GlobalShortcut(keyCode: Int64(kVK_Space),
                                              modifiers: [.control, .option, .command])
        suite.expect(superSpace.superKeyAlternative(sourceLabel: "Right ⌘",
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
        suite.expect(SuperKeySupport.heldKeyWatchdogOutcome(physicalKeyDown: true, stateThinksHeld: true, tapAlive: true)
                == .reArm,
               "a key still physically down keeps the hold alive")
        suite.expect(SuperKeySupport.heldKeyWatchdogOutcome(physicalKeyDown: false, stateThinksHeld: true, tapAlive: true)
                == .forget,
               "a key that has come up ends the hold (its release was missed)")
        suite.expect(SuperKeySupport.heldKeyWatchdogOutcome(physicalKeyDown: true, stateThinksHeld: false, tapAlive: true)
                == .forget,
               "nothing to keep alive once the state is no longer held")
        suite.expect(SuperKeySupport.heldKeyWatchdogOutcome(physicalKeyDown: true, stateThinksHeld: true, tapAlive: false)
                == .forget,
               "a torn-down tap cannot stamp modifiers, so the hold is dropped")

        // MARK: Features hub strings

        for language in AppLanguage.allCases {
            let hub = FeatureStrings.hub(language)
            suite.expect(hub.activeCountFormat.contains("%1$d") && hub.activeCountFormat.contains("%2$d"),
                   "count format keeps positional specifiers (\(language.rawValue))")
        }
        for language in AppLanguage.allCases {
            let clipboard = FeatureStrings.clipboard(language)
            expectFormat(clipboard.deleteSelectedFormat, ["d"],
                         "\(language.rawValue) clipboard bulk-delete format")
        }
        suite.expect(FeatureStrings.hub(.ptBR).pageTitle == "Recursos"
                && FeatureStrings.hub(.enUS).pageTitle == "Features",
               "hub page title reads naturally in the owner languages")
        for language in AppLanguage.allCases {
            suite.expect(FeatureStrings.backup(language).description.contains(
                FeatureStrings.scratchpad(language).pageTitle),
                   "every backup description accounts for the Scratchpad text (\(language.rawValue))")
            suite.expect(FeatureStrings.appUpdates(language).updateSelectedFormat.contains("%d")
                    && FeatureStrings.appUpdates(language).lastCheckFormat.contains("%@")
                    && FeatureStrings.appUpdates(language).nextCheckFormat.contains("%@")
                    && FeatureStrings.appUpdates(language).notificationBodyFormat.contains("%@"),
                   "app update formats keep their placeholders (\(language.rawValue))")
            suite.expect(!FeatureStrings.appUpdates(language).notificationBodyOne.contains("%"),
                   "the single-app note carries no placeholder (\(language.rawValue))")
            suite.expect(FeatureStrings.killProcess(language).pidLabelFormat.contains("%d")
                    && FeatureStrings.killProcess(language).processCountFormat.contains("%d")
                    && FeatureStrings.killProcess(language).killAllFormat.contains("%@")
                    && FeatureStrings.killProcess(language).confirmKillFormat.contains("%@")
                    && FeatureStrings.killProcess(language).confirmForceKillFormat.contains("%@")
                    && FeatureStrings.killProcess(language).confirmKillAllFormat.contains("%@")
                    && FeatureStrings.killProcess(language).confirmKillTreeFormat.contains("%@")
                    && FeatureStrings.killProcess(language).adminPromptFormat.contains("%@"),
                   "kill process formats keep their placeholders (\(language.rawValue))")
        }

        // MARK: Kill Process safety
        suite.expect(KillProcessSupport.isProtected(pid: 0, name: "kernel_task", path: "/System/Library/"),
               "PID 0 is protected")
        suite.expect(KillProcessSupport.isProtected(pid: 1, name: "launchd", path: "/sbin/launchd"),
               "PID 1 is protected")
        suite.expect(KillProcessSupport.isProtected(pid: 9999, name: "WindowServer", path: "/System/Library/Frameworks/WindowServer"),
               "WindowServer is protected")
        suite.expect(KillProcessSupport.isProtected(pid: 9999, name: "loginwindow", path: "/System/Library/CoreServices/loginwindow.app/Contents/MacOS/loginwindow"),
               "loginwindow is protected")
        suite.expect(KillProcessSupport.isProtected(pid: ProcessInfo.processInfo.processIdentifier, name: "Vorssaint"),
               "current app PID is protected")
        suite.expect(!KillProcessSupport.isProtected(pid: 12345, name: "Safari", path: "/Applications/Safari.app/Contents/MacOS/Safari"),
               "ordinary user app is not protected")
        suite.expect(KillProcessSupport.numberComesBefore(90, 10, lhsPID: 2, rhsPID: 1,
                                                    ascending: false)
               && KillProcessSupport.numberComesBefore(10, 90, lhsPID: 2, rhsPID: 1,
                                                       ascending: true)
               && !KillProcessSupport.numberComesBefore(10, 10, lhsPID: 2, rhsPID: 1,
                                                        ascending: true),
               "Kill Process numeric sorting is strict and follows the selected direction")
        suite.expect(KillProcessSupport.nameComesBefore("Alpha", "Zulu", lhsPID: 2, rhsPID: 1,
                                                  ascending: true)
               && KillProcessSupport.nameComesBefore("Zulu", "Alpha", lhsPID: 2, rhsPID: 1,
                                                     ascending: false)
               && !KillProcessSupport.nameComesBefore("Same", "same", lhsPID: 2, rhsPID: 1,
                                                      ascending: true),
               "Kill Process name sorting is A to Z by default and strict for ties")
        suite.expect(KillProcessSupport.normalizedStartDescription(" Thu  Aug 27  10:20:30 2026 \n")
                == "Thu Aug 27 10:20:30 2026"
               && KillProcessSupport.normalizedStartDescription("bad'; kill 1") == nil,
               "Kill Process accepts only safe normalized start identities for the admin command")
        // pid 1 -> 10 -> {20, 21} -> 30, with 40 on an unrelated branch, 50
        // its own parent and 21 <-> 22 pointing at each other.
        let processTable: [(pid: pid_t, ppid: pid_t)] = [
            (10, 1), (20, 10), (21, 10), (30, 20), (40, 1), (50, 50), (22, 21), (21, 22),
        ]
        let treeBelowTen = KillProcessSupport.descendants(of: 10, parents: processTable)
        suite.expect(treeBelowTen == [20, 21, 30, 22],
               "Kill Process collects a whole process tree breadth first so the caller kills deepest first")
        suite.expect(KillProcessSupport.descendants(of: 30, parents: processTable).isEmpty
               && KillProcessSupport.descendants(of: 50, parents: processTable).isEmpty,
               "Kill Process reports no descendants for a leaf and never follows a self-parenting row")

        for language in AppLanguage.allCases {
            let superKeyValues = Mirror(reflecting: FeatureStrings.superKey(language)).children
                .compactMap { $0.value as? String }
            let refusals = SuperKeyMappingFailure.allCases.map {
                FeatureStrings.superKey(language).mappingFailure($0)
            }
            suite.expect(Set(refusals).count == SuperKeyMappingFailure.allCases.count
                    && refusals.allSatisfy { !$0.isEmpty },
                   "every reason the key mapping is refused reads differently (\(language.rawValue))")
            let superKeyStrings = FeatureStrings.superKey(language)
            suite.expect(superKeyValues.allSatisfy { !$0.contains("—") }
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
            suite.expect(shortcutValues.allSatisfy { !$0.contains("—") }
                    && FeatureStrings.shortcuts(language).superKeyAlternativeFormat.contains("%@"),
                   "shortcut editor strings keep their format and avoid em-dashes (\(language.rawValue))")
            suite.expect(FeatureStrings.feedback(language).charactersFormat.contains("%d"),
                   "feedback character format keeps its placeholder (\(language.rawValue))")
            suite.expect(FeatureStrings.radialMenu(language).mediaOpenAppFormat.contains("%@"),
                   "Now Playing keeps the app-name placeholder (\(language.rawValue))")
            suite.expect(FeatureStrings.scratchpad(language).deletePadMessageFormat.contains("%@")
                    && FeatureStrings.scratchpad(language).padLimitFormat.contains("%d"),
                   "scratchpad dialog formats keep their placeholders (\(language.rawValue))")
            suite.expect(FeatureStrings.recorder(language).countdownSecondsFormat.contains("%d"),
                   "recorder countdown format keeps its specifier (\(language.rawValue))")
            suite.expect(FeatureStrings.recorder(language).frameRateFormat.contains("%d"),
                   "recorder frame rate format keeps its specifier (\(language.rawValue))")
            suite.expect(FeatureStrings.recorder(language).savedHUDFormat.contains("%@"),
                   "recorder saved format keeps its specifier (\(language.rawValue))")
            suite.expect(FeatureStrings.screenshot(language).delaySecondsFormat.contains("%d"),
                   "screenshot delay format keeps its specifier (\(language.rawValue))")
            suite.expect(FeatureStrings.screenshot(language).savedHUDFormat.contains("%@"),
                   "screenshot saved format keeps its specifier (\(language.rawValue))")
            suite.expect(FeatureStrings.screenshot(language).savedAndCopiedHUDFormat.contains("%@"),
                   "screenshot saved-and-copied format keeps its specifier (\(language.rawValue))")
            suite.expect(FeatureStrings.screenshot(language).fileNumberNextFormat.contains("%d"),
                   "screenshot next-number format keeps its specifier (\(language.rawValue))")
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
            suite.expect(!strings.obPurposeTitle.isEmpty && !strings.obPurposeBody.isEmpty
                    && !strings.obPurposeSkip.isEmpty,
                   "the purpose step speaks \(language.rawValue)")
            suite.expect(!strings.urlCleanerRulesTitle.isEmpty
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

        suite.expect(FeaturePreset.allCases.count == 3,
               "three starting points, not another wall of decisions")
        suite.expect(FeaturePreset.allCases.allSatisfy { !$0.features.isEmpty },
               "every preset installs something")
        suite.expect(FeaturePreset.essential.features.contains(.mixer)
                && FeaturePreset.essential.features.contains(.keepAwake)
                && FeaturePreset.essential.features.contains(.monitorPower),
               "the essential preset covers mixer, monitor and keep awake")
        suite.expect(FeaturePreset.windows.features.allSatisfy { $0.group == .windowsDock },
               "the windows preset stays inside the windows and Dock group")
        suite.expect(FeaturePreset.battery.features.allSatisfy {
                   $0.energyProfile != .mouse && $0.energyProfile != .pointer
                       && $0.energyProfile != .keyboard
                       && $0.energyProfile != .inputs
               },
               "battery and quiet installs nothing that listens to input")
        suite.expect(FeaturePreset.battery.features.allSatisfy {
                   !$0.permissions.contains(.accessibility)
               },
               "battery and quiet needs no accessibility permission at all")
        let firstRunSuiteName = "com.vorssaint.tests.first-run.\(UUID().uuidString)"
        if let firstRunDefaults = UserDefaults(suiteName: firstRunSuiteName) {
            firstRunDefaults.register(defaults: AppFeature.availabilityDefaults)
            FeaturePreset.prepareFirstRunAvailability(in: firstRunDefaults)
            suite.expect(Set(AppFeature.allCases.filter {
                firstRunDefaults.bool(forKey: $0.availabilityKey)
            }) == FeaturePreset.essential.features,
            "a clean install loads only the essential feature set before onboarding")

            for feature in AppFeature.allCases {
                firstRunDefaults.set(true, forKey: feature.availabilityKey)
            }
            firstRunDefaults.set(2, forKey: DefaultsKey.onboardingStep)
            FeaturePreset.prepareFirstRunAvailability(in: firstRunDefaults)
            suite.expect(AppFeature.allCases.allSatisfy {
                firstRunDefaults.bool(forKey: $0.availabilityKey)
            }, "an interrupted onboarding keeps the feature selection already applied")
            firstRunDefaults.removePersistentDomain(forName: firstRunSuiteName)
        } else {
            suite.expect(false, "first-run defaults suite can be created")
        }
        for preset in FeaturePreset.allCases {
            suite.expect(preset.enableKeys.allSatisfy { key in
                       preset.features.contains { $0.enabledKeys.contains(key) }
                   },
                   "preset enable keys belong to its own features (\(preset.rawValue))")
        }
        suite.expect(AppFeature.monitorCPU.energyProfile == .periodic
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
        suite.expect(AppFeature.windowLayout.energyProfile == .pointer,
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
        suite.expect(AppFeature.windowLayout.energyProfile == .pointer,
               "edge snapping reports its trackpad and mouse listener")
        UserDefaults.standard.set(
            WindowEdgeSnapZone.disabledZonesStorageValue(WindowEdgeSnapZone.allEnabled),
            forKey: DefaultsKey.windowEdgeSnapDisabledZones
        )
        suite.expect(AppFeature.windowLayout.energyProfile == .idle,
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

        // MARK: Settings page visibility

        func pageVisible(_ page: SettingsPage, available: Set<AppFeature>) -> Bool {
            FeatureVisibilitySupport.isPageVisible(page) { available.contains($0) }
        }
        let allFeatures = Set(AppFeature.allCases)
        suite.expect(pageVisible(.mouse, available: allFeatures), "mouse page shows with everything available")
        suite.expect(pageVisible(.mouse, available: [.middleClick]),
               "one remaining mouse feature keeps the mouse page")
        suite.expect(pageVisible(.mouse, available: [.mouseAcceleration]),
               "mouse acceleration alone keeps the mouse page")
        suite.expect(pageVisible(.mouse, available: [.mouseClickDebounce]),
               "mouse click debounce alone keeps its Settings page reachable")
        suite.expect(!pageVisible(.mouse, available: []),
               "the mouse page hides only with all eight mouse features off")
        suite.expect(!pageVisible(.energy, available: allFeatures.subtracting([.keepAwake, .brightness,
                                                                         .extraBrightness,
                                                                         .bluetoothSleep])),
               "energy hides when all four of its features are off")
        suite.expect(pageVisible(.energy, available: [.extraBrightness]), "XDR alone keeps the energy page")
        suite.expect(pageVisible(.energy, available: [.brightness]),
               "brightness control alone keeps the energy page")
        suite.expect(!pageVisible(.monitor, available: allFeatures.subtracting(Set(FeatureVisibilitySupport.monitorFeatures))),
               "monitor page hides with every metric off")
        suite.expect(pageVisible(.monitor, available: [.monitorNetwork]), "one metric keeps the monitor page")
        suite.expect(pageVisible(.general, available: []) && pageVisible(.about, available: [])
                && pageVisible(.shortcuts, available: []),
               "app pages never hide")
        suite.expect(!pageVisible(.shelf, available: allFeatures.subtracting([.shelf])),
               "single-feature pages follow their feature")
        suite.expect(pageVisible(.cutPaste, available: [.finderRename])
                && pageVisible(.cutPaste, available: [.finderCutPaste])
                && !pageVisible(.cutPaste, available: []),
               "either Finder shortcut keeps their shared page visible")
        suite.expect(!pageVisible(.cleaner,
                            available: allFeatures.subtracting([.cleaner])),
               "cleaner settings, including WhatsApp downloads, follow the cleaner module")
        suite.expect(pageVisible(.quickTools, available: [.quickToggles]),
               "the quick toggles alone keep the quick tools page")
        suite.expect(pageVisible(.clipboard, available: [.finderCutPaste]),
               "the image paste option keeps the Clipboard page available")
        suite.expect(AppFeature.allCases.allSatisfy { feature in
            let destination = feature.settingsDestination
            let gate = FeatureVisibilitySupport.features(for: destination.page)
            return gate.isEmpty || gate.contains(feature)
        }, "every feature destination is either always visible or gated by that feature")
        suite.expect(AppFeature.allCases.allSatisfy { $0.settingsDestination.hasValidSectionAnchor },
               "every feature anchor belongs to its destination page")
        suite.expect(Set(AppFeature.allCases.compactMap(\.settingsDestination.sectionAnchor))
                == Set(SettingsSectionAnchor.allCases),
               "every declared Settings section anchor is used by a feature destination")
        suite.expect(AppFeature.dockPreview.settingsDestination
                == FeatureSettingsDestination(.dock, sectionAnchor: .dock)
                && AppFeature.dockClick.settingsDestination
                == FeatureSettingsDestination(.dock, sectionAnchor: .dockClick)
                && FeatureVisibilitySupport.features(for: .switcher) == [.switcher]
                && pageVisible(.dock, available: [.dockClick])
                && !pageVisible(.switcher, available: [.dockPreview, .dockClick]),
               "Dock Preview and Dock clicks have their own page, apart from the switcher")
        func dockNeedsAccessibility(available: Set<AppFeature>, on: Set<String>) -> Bool {
            FeatureVisibilitySupport.isPermissionNeeded(
                on: .dock, activeFeatures: Array(activeSet(.accessibility, available: available, on: on)))
        }
        suite.expect([DefaultsKey.dockClickMinimize, DefaultsKey.dockClickHide, DefaultsKey.dockClickCycleWindows]
                .allSatisfy { dockNeedsAccessibility(available: [.dockClick], on: [$0]) }
                && dockNeedsAccessibility(available: [.dockPreview], on: [DefaultsKey.dockPreviewEnabled])
                && !dockNeedsAccessibility(available: [.dockPreview], on: [DefaultsKey.dockClickMinimize])
                && !dockNeedsAccessibility(available: allFeatures, on: [DefaultsKey.switcherEnabled]),
               "the Dock page asks for Accessibility while Dock Preview or any Dock click action is on")
        suite.expect(AppFeature.mixer.settingsDestination
                == FeatureSettingsDestination(.general, sectionAnchor: .panelConfiguration),
               "panel-oriented features land on General panel configuration")
        suite.expect(AppFeature.windowMaximizer.settingsDestination
                == FeatureSettingsDestination(.windowLayout, sectionAnchor: .windowMaximizer)
                && pageVisible(.windowLayout, available: [.windowMaximizer])
                && !pageVisible(.windowLayout,
                                available: allFeatures.subtracting([.windowLayout, .windowMaximizer])),
               "the green button override and its exception list keep the window layout page on their own")
        suite.expect(AppFeature.cleaningMode.settingsDestination
                == FeatureSettingsDestination(.quickTools, sectionAnchor: .cleaningMode),
               "cleaning mode lands on Quick Tools cleaning mode section")
        suite.expect(AppFeature.musicBlock.settingsDestination
                == FeatureSettingsDestination(.general, sectionAnchor: .musicBlocking)
                && AppFeature.soundOutputSwitcher.settingsDestination
                == FeatureSettingsDestination(.shortcuts, sectionAnchor: .soundOutputSwitcher)
                && AppFeature.diskImageInstaller.settingsDestination
                == FeatureSettingsDestination(.features),
               "features without dedicated pages use explicit nearest Settings destinations")
        suite.expect(!AppFeature.diskImageInstaller.hasNavigableSettingsDestination
                && AppFeature.allCases.filter { $0 != .diskImageInstaller }
                    .allSatisfy(\.hasNavigableSettingsDestination),
               "a feature without a separate configuration surface does not show a dead-end link")
        suite.expect(AppFeature.monitorCPU.settingsDestination == FeatureSettingsDestination(.monitor)
                && AppFeature.fanControl.settingsDestination
                == FeatureSettingsDestination(.monitor, sectionAnchor: .fanControl),
               "shared monitor destinations distinguish the dedicated fan controls")
        let settingsRouter = SettingsRouter.shared
        var settingsRequestCount = 0
        var settingsRequestsPublishedReady = true
        let settingsRequestObservation = settingsRouter.$requestID
            .dropFirst()
            .sink { requestID in
                settingsRequestCount += 1
                settingsRequestsPublishedReady =
                    settingsRequestsPublishedReady
                    && settingsRouter.pendingDestinationRequest?.id == requestID
            }
        let repeatedDestination = FeatureSettingsDestination(.mouse, sectionAnchor: .middleClick)
        settingsRouter.request(repeatedDestination)
        let firstSettingsRequestID = settingsRouter.requestID
        settingsRouter.request(repeatedDestination)
        suite.expect(settingsRouter.destination == repeatedDestination
                && settingsRouter.page == repeatedDestination.page,
               "a Settings destination request selects its page and preserves its anchor")
        suite.expect(settingsRequestCount == 2 && settingsRouter.requestID != firstSettingsRequestID,
               "repeated requests for the same Settings destination remain observable")
        suite.expect(settingsRequestsPublishedReady,
               "a Settings request is ready to consume when its request identity is published")
        let repeatedSettingsRequestID = settingsRouter.requestID
        settingsRouter.consumeDestinationRequest(id: firstSettingsRequestID)
        suite.expect(settingsRouter.pendingDestinationRequest?.id == repeatedSettingsRequestID,
               "consuming an older Settings request cannot clear a newer request")
        settingsRouter.consumeDestinationRequest(id: repeatedSettingsRequestID)
        suite.expect(settingsRouter.pendingDestinationRequest == nil,
               "a handled Settings destination request is cleared")

        let featuresDestination = FeatureSettingsDestination(.features)
        settingsRouter.request(featuresDestination, targetFeature: .homebrew)
        let firstFeatureTargetRequestID = settingsRouter.requestID
        suite.expect(settingsRouter.pendingFeatureTarget?.id == firstFeatureTargetRequestID
                && settingsRouter.pendingFeatureTarget?.feature == .homebrew,
               "requesting Features with a target feature publishes a matching feature-target request")
        settingsRouter.request(featuresDestination, targetFeature: .homebrew)
        let secondFeatureTargetRequestID = settingsRouter.requestID
        suite.expect(secondFeatureTargetRequestID != firstFeatureTargetRequestID
                && settingsRouter.pendingFeatureTarget?.id == secondFeatureTargetRequestID,
               "repeated requests for the same target feature remain observable")
        settingsRouter.consumeFeatureTarget(id: firstFeatureTargetRequestID)
        suite.expect(settingsRouter.pendingFeatureTarget?.id == secondFeatureTargetRequestID,
               "consuming an older feature-target request cannot clear a newer target")
        settingsRouter.consumeFeatureTarget(id: secondFeatureTargetRequestID)
        suite.expect(settingsRouter.pendingFeatureTarget == nil,
               "a handled feature-target request is cleared")
        settingsRouter.request(featuresDestination, targetFeature: .diskImageInstaller)
        suite.expect(settingsRouter.pendingFeatureTarget?.feature == .diskImageInstaller,
               "requesting a different target feature is observable")
        settingsRouter.request(repeatedDestination)
        suite.expect(settingsRouter.pendingFeatureTarget == nil,
               "a later generic request clears any unconsumed feature target so it cannot leak into unrelated navigation")

        settingsRouter.cleanerTool = "tool-id"
        settingsRouter.request(FeatureSettingsDestination(.cleaner))
        suite.expect(settingsRouter.page == .cleaner && settingsRouter.cleanerTool == "tool-id",
               "requesting Cleaner Settings preserves its one-shot tool hint")
        settingsRouter.consumeDestinationRequest(id: settingsRouter.requestID)
        settingsRouter.cleanerTool = nil
        settingsRouter.page = .general
        withExtendedLifetime(settingsRequestObservation) {}

        let historyRouter = SettingsRouter()
        let initialHistoryRequestID = historyRouter.requestID
        historyRouter.goBack()
        historyRouter.goForward()
        suite.expect(historyRouter.page == .general
                && historyRouter.requestID == initialHistoryRequestID,
               "an empty Settings history does not navigate or publish requests")
        historyRouter.page = .about
        historyRouter.request(repeatedDestination)
        historyRouter.goBack()
        suite.expect(historyRouter.page == .about
                && historyRouter.destination == FeatureSettingsDestination(.about),
               "Settings Back includes direct sidebar-style page assignments")
        historyRouter.goBack()
        suite.expect(historyRouter.page == .general,
               "Settings Back reaches the initial page")
        let oldestHistoryRequestID = historyRouter.requestID
        historyRouter.goBack()
        suite.expect(historyRouter.requestID == oldestHistoryRequestID,
               "Settings Back stops at the oldest visit")
        historyRouter.goForward()
        suite.expect(historyRouter.page == .about,
               "Settings Forward retraces the visited pages")
        historyRouter.goForward()
        suite.expect(historyRouter.destination == repeatedDestination
                && historyRouter.pendingDestinationRequest?.destination == repeatedDestination,
               "Settings history restores section anchors with a fresh focus request")
        let newestHistoryRequestID = historyRouter.requestID
        historyRouter.goForward()
        suite.expect(historyRouter.requestID == newestHistoryRequestID,
               "Settings Forward stops at the newest visit")

        historyRouter.page = .mouse
        let refinedDestination = FeatureSettingsDestination(.mouse, sectionAnchor: .smoothScroll)
        historyRouter.request(refinedDestination)
        historyRouter.request(refinedDestination)
        historyRouter.goBack()
        suite.expect(historyRouter.page == .about,
               "repeated page selections and same-page section requests do not duplicate history")
        historyRouter.goForward()
        suite.expect(historyRouter.destination == refinedDestination,
               "same-page section requests refine the destination restored by history")
        historyRouter.goBack()
        historyRouter.page = .support
        let branchedHistoryRequestID = historyRouter.requestID
        historyRouter.goForward()
        suite.expect(historyRouter.page == .support
                && historyRouter.requestID == branchedHistoryRequestID,
               "a new sidebar visit after Back discards forward history")
        historyRouter.goBack()
        historyRouter.request(FeatureSettingsDestination(.features), targetFeature: .homebrew)
        historyRouter.goForward()
        suite.expect(historyRouter.page == .features,
               "a destination request after Back also discards forward history")
        historyRouter.page = .advanced
        suite.expect(historyRouter.destination == FeatureSettingsDestination(.advanced)
                && historyRouter.pendingDestinationRequest == nil
                && historyRouter.pendingFeatureTarget == nil,
               "direct page navigation synchronizes the destination and clears stale reveal requests")

        let hiddenHistoryRouter = SettingsRouter()
        hiddenHistoryRouter.page = .mouse
        hiddenHistoryRouter.page = .about
        hiddenHistoryRouter.goBack(isPageVisible: { $0 != .mouse })
        suite.expect(hiddenHistoryRouter.page == .general,
               "Settings Back skips pages whose features are no longer available")
        hiddenHistoryRouter.goForward(isPageVisible: { $0 != .mouse })
        suite.expect(hiddenHistoryRouter.page == .about,
               "skipping a hidden page preserves forward history")
        let visibleHistoryRequestID = hiddenHistoryRouter.requestID
        hiddenHistoryRouter.goBack(isPageVisible: { _ in false })
        suite.expect(hiddenHistoryRouter.page == .about
                && hiddenHistoryRouter.requestID == visibleHistoryRequestID,
               "Settings history stays put when no earlier page is visible")
        hiddenHistoryRouter.cleanerTool = "stale-tool"
        hiddenHistoryRouter.goBack()
        suite.expect(hiddenHistoryRouter.page == .mouse
                && hiddenHistoryRouter.cleanerTool == nil,
               "history can revisit re-enabled pages without replaying a stale Cleaner tool hint")

        // MARK: Display brightness (DDC/CI helpers)

        // Every section of the service below its "Rebuild (work queue)" MARK
        // runs on the private work queue, so a display's user-facing name is
        // read from NSScreen on the main thread and handed to the rebuild.
        // AppKit reached from below the line would be a main thread violation
        // on every hotplug, wake and panel open.
        let brightnessSource = (try? String(
            contentsOfFile: "Sources/Vorssaint/Services/Display/BrightnessService.swift",
            encoding: .utf8)) ?? ""
        let brightnessWorkQueueHalf = brightnessSource
            .components(separatedBy: "// MARK: - Rebuild (work queue)").last ?? ""
        // Comments are stripped first: a note naming the symbol it bans is not
        // a call, and a check that cannot tell them apart goes red for prose.
        let brightnessWorkQueueCode = brightnessWorkQueueHalf
            .components(separatedBy: "\n")
            .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }
            .joined(separator: "\n")
        suite.expect(!brightnessWorkQueueHalf.isEmpty && !brightnessWorkQueueCode.contains("NSScreen"),
               "the brightness work queue resolves display names without touching NSScreen")
        // Display numbers are reissued after a reconnection, so the gamma
        // restore before a switch-off must check the monitor like the others.
        suite.expect(brightnessSource.contains("baseline.fingerprint == Self.displayFingerprint(display.id)"),
               "the pre-switch-off gamma restore checks the display fingerprint")

        let ddcWrite = BrightnessSupport.writePacket(code: 0x10, value: 0x1234)
        let expectedDDCWrite: [UInt8] = [0x84, 0x03, 0x10, 0x12, 0x34, 0x8E]
        suite.expect(ddcWrite == expectedDDCWrite,
               "DDC write packet carries the set opcode, big-endian value and checksum")
        let ddcRead = BrightnessSupport.readRequestPacket(code: 0x10)
        let expectedDDCRead: [UInt8] = [0x82, 0x01, 0x10, 0xFD]
        suite.expect(ddcRead == expectedDDCRead,
               "DDC read request omits the sub-address from its checksum seed")
        suite.expect(Array(BrightnessSupport.writePacket(code: 0x10, value: 100)[3...4]) == [0x00, 0x64],
               "DDC values split into high and low bytes")

        var ddcReply: [UInt8] = [0x6E, 0x88, 0x02, 0x00, 0x10, 0x00, 0x00, 0x64, 0x00, 0x32]
        ddcReply.append(ddcReply.reduce(UInt8(0x50)) { $0 ^ $1 })
        suite.expect(BrightnessSupport.parseReply(ddcReply)?.current == 0x32
                && BrightnessSupport.parseReply(ddcReply)?.maximum == 0x64,
               "a valid DDC reply yields the current and maximum values")
        var corrupted = ddcReply
        corrupted[7] ^= 0xFF
        suite.expect(BrightnessSupport.parseReply(corrupted) == nil,
               "a corrupted DDC reply fails its checksum and reads as no reply")
        suite.expect(BrightnessSupport.parseReply([0x6E, 0x88]) == nil,
               "a short DDC reply reads as no reply")

        suite.expect(BrightnessSupport.sanitizedMaximum(0) == 100 && BrightnessSupport.sanitizedMaximum(255) == 255,
               "a display reporting no range falls back to the conventional scale")
        suite.expect(BrightnessSupport.normalized(current: 50, maximum: 100) == 0.5,
               "DDC values normalize to the slider scale")
        suite.expect(BrightnessSupport.normalized(current: 120, maximum: 0) == 1.0,
               "normalization clamps against the fallback range")
        suite.expect(BrightnessSupport.deviceValue(for: 0.5, maximum: 100) == 50
                && BrightnessSupport.deviceValue(for: 1.0, maximum: 255) == 255
                && BrightnessSupport.deviceValue(for: -0.2, maximum: 100) == 0
                && BrightnessSupport.deviceValue(for: 1.7, maximum: 100) == 100,
               "slider values map onto the display's own scale with clamping")
        suite.expect(BrightnessSupport.steppedKeyboardLightLevel(current: 0.5, direction: -1)
                == 0.5 - BrightnessSupport.keyboardLightStep
                && BrightnessSupport.steppedKeyboardLightLevel(current: 0.5, direction: 1)
                == 0.5 + BrightnessSupport.keyboardLightStep,
               "keyboard brightness shortcuts move by one system-sized step")
        suite.expect(BrightnessSupport.steppedKeyboardLightLevel(current: 0, direction: -1) == 0
                && BrightnessSupport.steppedKeyboardLightLevel(current: 1, direction: 1) == 1,
               "keyboard brightness shortcut steps clamp to the supported range")
        suite.expect(BrightnessSupport.steppedKeyboardLightLevel(current: .nan, direction: 1) == 0,
               "an invalid keyboard brightness reading never reaches the private setter")

        // EDID UUID chunks at fixed positions: vendor, product (little endian),
        // manufacture date, image size.
        var serviceIdentity = BrightnessSupport.ServiceIdentity()
        serviceIdentity.edidUUID = "10AC5FA0-0000-0000-1E19-0000003C2200"
        serviceIdentity.ordinal = 1
        var displayIdentity = BrightnessSupport.DisplayIdentity()
        displayIdentity.vendorID = 0x10AC
        displayIdentity.productID = 0xA05F
        displayIdentity.weekOfManufacture = 30
        displayIdentity.yearOfManufacture = 2015
        displayIdentity.horizontalImageSize = 600
        displayIdentity.verticalImageSize = 340
        suite.expect(BrightnessSupport.matchScore(service: serviceIdentity, display: displayIdentity) == 4,
               "every EDID identity chunk scores one point")
        serviceIdentity.ioDisplayLocation = "IOService:/some/path"
        displayIdentity.ioDisplayLocation = "IOService:/some/path"
        suite.expect(BrightnessSupport.matchScore(service: serviceIdentity, display: displayIdentity) == 14,
               "a registry path match is decisive on top of the EDID chunks")
        suite.expect(BrightnessSupport.matchScore(service: BrightnessSupport.ServiceIdentity(),
                                            display: BrightnessSupport.DisplayIdentity()) == 0,
               "empty identities never match")

        let assignment = BrightnessSupport.assignServices(scores: [
            (displayIndex: 0, serviceOrdinal: 1, score: 2),
            (displayIndex: 0, serviceOrdinal: 2, score: 11),
            (displayIndex: 1, serviceOrdinal: 1, score: 3),
            (displayIndex: 1, serviceOrdinal: 2, score: 4),
        ])
        suite.expect(assignment == [0: 2, 1: 1],
               "greedy assignment gives each display its best free service")
        suite.expect(BrightnessSupport.assignServices(scores: [(displayIndex: 0, serviceOrdinal: 1, score: 0)])
                .isEmpty,
               "zero-score pairs never pair up")

        suite.expect(BrightnessSupport.channelOutcome(writeAccepted: true, replyParsed: true) == .live,
               "a parsed reply means a live DDC channel")
        suite.expect(BrightnessSupport.channelOutcome(writeAccepted: true, replyParsed: false) == .writeOnly,
               "accepted writes without replies keep a blind slider")
        suite.expect(BrightnessSupport.channelOutcome(writeAccepted: false, replyParsed: false) == .dead,
               "rejected writes mean no DDC reaches the display (HDMI conversion)")
        suite.expect(BrightnessSupport.ddcProbeAttempts()
                == BrightnessSupport.retryAttempts + 1
                && BrightnessSupport.ddcProbeWriteCycles(classifyingChannel: true) == 1,
               "channel discovery keeps its reply chances but sends one spaced write each")
        suite.expect(BrightnessSupport.ddcProbeWriteCycles(classifyingChannel: true,
                                                     isFinalAttempt: true)
                == BrightnessSupport.writeCycles,
               "discovery pairs its requests once before writing a channel off as unreadable")
        suite.expect(BrightnessSupport.ddcProbeWriteCycles(classifyingChannel: false,
                                                     isFinalAttempt: true)
                == BrightnessSupport.writeCycles,
               "a classified channel keeps its paired requests on every attempt")
        suite.expect(BrightnessSupport.ddcProbeAttempts()
                == BrightnessSupport.retryAttempts + 1
                && BrightnessSupport.ddcProbeWriteCycles(classifyingChannel: false)
                == BrightnessSupport.writeCycles,
               "answering channels retain their field-proven read and write retries")
        let ddcPath = BrightnessSupport.ddcPathKey(
            displayFingerprint: "1507:9218:245",
            ioDisplayLocation: "IOService:/port/1")
        suite.expect(ddcPath == "1507:9218:245|IOService:/port/1",
               "a DDC capability cache key binds the physical display to its connection path")
        suite.expect(BrightnessSupport.ddcPathKey(displayFingerprint: "1507:9218:245",
                                            ioDisplayLocation: "") == nil,
               "a display without a stable connection path is never cached")
        let rememberedPaths = BrightnessSupport.updatedWriteOnlyDDCPaths(
            ["old", "same", "other", "same"], path: "same", isWriteOnly: true, limit: 3)
        suite.expect(rememberedPaths == ["old", "other", "same"],
               "remembering a write-only path deduplicates it and makes it newest")
        suite.expect(BrightnessSupport.updatedWriteOnlyDDCPaths(
            rememberedPaths, path: "other", isWriteOnly: false, limit: 3) == ["old", "same"],
               "a changed DDC result invalidates the remembered path")
        suite.expect(BrightnessSupport.updatedWriteOnlyDDCPaths(
            ["one", "two", "three"], path: "four", isWriteOnly: true, limit: 3)
            == ["two", "three", "four"],
               "the write-only path cache remains bounded")
        suite.expect(!BrightnessSupport.shouldProbeDDC(
            pathKey: ddcPath, writeOnlyPaths: [ddcPath!])
                && BrightnessSupport.shouldProbeDDC(
                    pathKey: "another", writeOnlyPaths: [ddcPath!])
                && BrightnessSupport.shouldProbeDDC(
                    pathKey: nil, writeOnlyPaths: [ddcPath!]),
               "only the same physical display path skips future DDC probes")
        suite.expect(!SettingsBackupSupport.exportKeys().contains(
            DefaultsKey.brightnessDDCWriteOnlyPaths),
               "per-monitor DDC capability never travels in a settings backup")
        suite.expect(SettingsBackupSupport.machineStateKeys.contains(
            DefaultsKey.brightnessForcedSoftwarePaths)
                && !SettingsBackupSupport.exportKeys().contains(
                    DefaultsKey.brightnessForcedSoftwarePaths),
               "a hand-picked software dimming route never travels in a settings backup")
        for surface in ["Sources/Vorssaint/UI/Settings/EnergySettings.swift",
                        "Sources/Vorssaint/UI/MenuPanel/BrightnessSection.swift"] {
            let source = (try? String(contentsOfFile: surface, encoding: .utf8)) ?? ""
            suite.expect(source.contains("SoftwareDimmingButton(display: display"),
                   "\(surface) offers the software dimming choice on its display rows")
        }
        let oneDisplay = BrightnessSupport.DisplayTopology(online: [1], active: [1])
        let twoDisplays = BrightnessSupport.DisplayTopology(online: [1, 2], active: [1, 2])
        suite.expect(!BrightnessSupport.shouldQueueRebuild(topology: oneDisplay, pending: oneDisplay),
               "opening Displays does not queue the same monitor scan twice")
        suite.expect(BrightnessSupport.shouldQueueRebuild(topology: twoDisplays, pending: oneDisplay),
               "a connected monitor always queues a fresh display scan")
        suite.expect(BrightnessSupport.shouldQueueRebuild(topology: oneDisplay, pending: oneDisplay,
                                                    force: true),
               "wake recovery can rebuild unchanged display ids")
        suite.expect(BrightnessSupport.brightnessAfterRebuild(probed: 0.3, pending: 0.8) == 0.8,
               "a brightness change made during discovery survives the final probe")
        suite.expect(BrightnessSupport.brightnessAfterRebuild(probed: 0.3, pending: nil) == 0.3,
               "a rebuild keeps the monitor reading when no change is waiting")
        suite.expect(!BrightnessSupport.canConfigureDisplay(enabled: true, isBuiltIn: true,
                                                     lidClosed: true),
               "a closed lid prevents enabling the built-in display")
        for lidClosed: Bool? in [true, false, nil] {
            suite.expect(BrightnessSupport.canConfigureDisplay(enabled: true, isBuiltIn: false,
                                                         lidClosed: lidClosed),
                   "external display enables ignore lid state")
            for isBuiltIn in [true, false] {
                suite.expect(BrightnessSupport.canConfigureDisplay(enabled: false,
                                                             isBuiltIn: isBuiltIn,
                                                             lidClosed: lidClosed),
                       "display disables ignore lid state")
            }
        }
        for lidClosed: Bool? in [false, nil] {
            suite.expect(BrightnessSupport.canConfigureDisplay(enabled: true, isBuiltIn: true,
                                                         lidClosed: lidClosed),
                   "an open or unavailable lid reading preserves built-in restoration")
        }
        suite.expect(BrightnessSupport.canDisableDisplay(drawableDisplayIDs: [1, 3], target: 3),
               "one display can be disabled while another remains active")
        suite.expect(!BrightnessSupport.canDisableDisplay(drawableDisplayIDs: [1], target: 1),
               "the final active display can never be disabled")
        suite.expect(!BrightnessSupport.canDisableDisplay(drawableDisplayIDs: [1, 3], target: 8),
               "an inactive display cannot enter the disable path")
        suite.expect(BrightnessSupport.drawableDisplayIDs(
            onlineDisplayIDs: [1, 2], activeDisplayIDs: [1, 2, 9], virtualDisplayIDs: [2]) == [1],
               "only online active displays with a visible picture prevent recovery")
        suite.expect(BrightnessSupport.drawableDisplayIDs(
            onlineDisplayIDs: [2], activeDisplayIDs: [2], virtualDisplayIDs: [2]).isEmpty,
               "a virtual-only active display leaves the machine effectively headless")
        let onePhysicalOneVirtual = BrightnessSupport.drawableDisplayIDs(
            onlineDisplayIDs: [1, 2], activeDisplayIDs: [1, 2], virtualDisplayIDs: [2])
        suite.expect(!BrightnessSupport.canDisableDisplay(drawableDisplayIDs: onePhysicalOneVirtual,
                                                    target: 1),
               "a virtual display never makes it safe to disable the last physical display")
        suite.expect(BrightnessSupport.headlessRecoveryCandidates(
            drawableDisplayIDs: [3], managedDisabledIDs: [1], builtInDisabledIDs: [1]).isEmpty,
               "an active external display preserves an intentionally disabled built-in panel")
        suite.expect(BrightnessSupport.headlessRecoveryCandidates(
            drawableDisplayIDs: [], managedDisabledIDs: [1, 4], builtInDisabledIDs: [1]) == [1, 4],
               "losing the last active display tries the built-in panel before other managed displays")
        suite.expect(BrightnessSupport.headlessRecoveryCandidates(
            drawableDisplayIDs: [], managedDisabledIDs: [7, 4], builtInDisabledIDs: []) == [4, 7],
               "a headless desktop Mac can recover one display switched off by this app")
        suite.expect(BrightnessSupport.headlessRecoveryCandidates(
            drawableDisplayIDs: [], managedDisabledIDs: [], builtInDisabledIDs: [1]).isEmpty,
               "a display disabled elsewhere is never changed during headless recovery")
        // CoreGraphics runs a reconfiguration's callbacks inline on the driving
        // thread, and in this process those callbacks are AppKit's, so the
        // transaction belongs to the main thread. Getting it wrong hangs the
        // app rather than returning a wrong answer, and no pure helper can
        // carry that, so it is pinned against the CoreGraphics symbols.
        suite.expect(brightnessSource.components(separatedBy: "CGBeginDisplayConfiguration(").count == 2
               && brightnessSource.components(separatedBy: "CGCompleteDisplayConfiguration(").count == 2,
               "every display power change goes through the one reconfiguration transaction")
        let beforeDisplayConfiguration = brightnessSource
            .components(separatedBy: "CGBeginDisplayConfiguration(").first ?? ""
        suite.expect((beforeDisplayConfiguration.components(separatedBy: "func ").last ?? "")
                .contains("Thread.isMainThread"),
               "the display reconfiguration transaction refuses to start off the main thread")
        let configurationEntry = (beforeDisplayConfiguration
            .components(separatedBy: "func ").last ?? "")
            .replacingOccurrences(of: #"(?s)/\*.*?\*/|//[^\n]*"#, with: "",
                                  options: .regularExpression)
        suite.expect(configurationEntry.range(
                    of: #"\bBrightnessSupport\s*\.\s*canConfigureDisplay\s*\("#,
                    options: .regularExpression) != nil
                && configurationEntry.range(of: #"\bCGDisplayIsBuiltin\s*\("#,
                                            options: .regularExpression) != nil,
               "the shared transaction checks the live built-in and lid state before beginning")

        // A `UserDefaults` write posts `didChangeNotification`, and the
        // observers registered with `queue: .main` make that post wait for the
        // main thread. Held under `stateLock` it waits on a main thread that
        // can itself be waiting for the same lock inside `canToggleDisplay`,
        // called from a SwiftUI body, and the app hangs with nothing left that
        // can end it (issue #647). Which thread the write happens to run on
        // does not change that, so it is the locked region that is pinned.
        let lockedRegions = brightnessSource.components(separatedBy: "stateLock.lock()")
            .dropFirst()
            .map { $0.components(separatedBy: "stateLock.unlock()").first ?? $0 }
        suite.expect(!lockedRegions.isEmpty
               && lockedRegions.allSatisfy { !$0.contains("SwitchedOff(") },
               "the list of displays switched off is never written while stateLock is held")

        // The same transaction relays its screen change to AppKit inline, and
        // switching off the display the panel is on makes AppKit lay that panel
        // out again right there: the power button's body is evaluated while
        // this app holds the display server busy, so anything it asks the
        // display server is a question the same thread is still answering, and
        // the app freezes with nothing left that can end it (issue #969). The
        // body decides from the published snapshot instead, and the live
        // reading stays where it guards the switch itself. Comments are
        // stripped first: a note naming what it bans is not a call.
        let canToggleCode = ((brightnessSource
            .components(separatedBy: "func canToggleDisplay(").last ?? "")
            .components(separatedBy: "\n    }").first ?? "")
            .components(separatedBy: "\n")
            .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }
            .joined(separator: "\n")
        suite.expect(!canToggleCode.isEmpty
               && canToggleCode.contains("drawableDisplays")
               && !canToggleCode.contains("Self.drawableDisplayIDs(")
               && !canToggleCode.contains("stateLock"),
               "the panel reads whether a display can be switched off without asking the display server")

        suite.expect(BrightnessSupport.ddcCommandDelay(nowMicroseconds: 1_000_000,
                                                 lastCommandEndMicroseconds: nil) == 0,
               "the first DDC command to a display waits nothing")
        suite.expect(BrightnessSupport.ddcCommandDelay(nowMicroseconds: 1_010_000,
                                                 lastCommandEndMicroseconds: 1_000_000) == 40_000,
               "a command chasing another waits out the standard's interval")
        suite.expect(BrightnessSupport.ddcCommandDelay(nowMicroseconds: 1_050_000,
                                                 lastCommandEndMicroseconds: 1_000_000) == 0
                && BrightnessSupport.ddcCommandDelay(nowMicroseconds: 2_000_000,
                                                     lastCommandEndMicroseconds: 1_000_000) == 0,
               "an elapsed interval clears the wait entirely")
        suite.expect(BrightnessSupport.ddcCommandDelay(nowMicroseconds: 1_000_000,
                                                 lastCommandEndMicroseconds: 2_000_000) == 0,
               "a clock that moved backwards never blocks the bus")

        suite.expect(BrightnessSupport.reconnectedDimLevel(0.0) == BrightnessSupport.reconnectionDimFloor
                && BrightnessSupport.reconnectedDimLevel(0.1) == BrightnessSupport.reconnectionDimFloor,
               "a near-black dim returns from a connection gap at the visible floor")
        suite.expect(BrightnessSupport.reconnectedDimLevel(0.7) == 0.7
                && BrightnessSupport.reconnectedDimLevel(1.0) == 1.0
                && BrightnessSupport.reconnectedDimLevel(1.4) == 1.0,
               "visible dim levels return from a gap untouched, clamped to the range")

        suite.expect(BrightnessSupport.softwareDimToRestore(remembered: 0.7, appliedByApp: false) == 1.0
                && BrightnessSupport.softwareDimToRestore(remembered: nil, appliedByApp: true) == 1.0,
               "a level read from the monitor is never replayed as a gamma dim")
        suite.expect(BrightnessSupport.softwareDimToRestore(remembered: 0.4, appliedByApp: true) == 0.4,
               "a dim this app applied is restored when the routes are rebuilt")

        suite.expect(BrightnessSupport.softwareDimFactor(for: 1.0) == 1.0
                && BrightnessSupport.softwareDimFactor(for: 0.0) == 0.0,
               "software dimming spans the whole range and zero really is black")
        suite.expect(BrightnessSupport.softwareDimFactor(for: 0.5) == 0.5
                && BrightnessSupport.softwareDimFactor(for: -0.3) == 0.0
                && BrightnessSupport.softwareDimFactor(for: 1.4) == 1.0,
               "software dimming is linear with clamping")
        suite.expect(BrightnessSupport.scaledGammaTable([0.0, 0.5, 1.0], factor: 0.5) == [0.0, 0.25, 0.5],
               "gamma tables scale toward black by the dim factor")
        let untouched: [Float] = [0.0, 0.3, 1.0]
        suite.expect(BrightnessSupport.scaledGammaTable(untouched, factor: 1.0) == untouched,
               "factor one returns the exact original table for bit-exact restores")

        // Brightness keys arrive as system-defined auxiliary control events;
        // data1 packs key code, press state and the repeat bit.
        func brightnessData1(keyCode: Int, state: Int, repeated: Bool = false) -> Int {
            (keyCode << 16) | (state << 8) | (repeated ? 1 : 0)
        }
        suite.expect(BrightnessSupport.brightnessKeyEvent(subtype: 8,
                                                    data1: brightnessData1(keyCode: 2, state: 10))
                == BrightnessSupport.BrightnessKeyEvent(delta: BrightnessSupport.brightnessKeyStep,
                                                        isKeyDown: true, isRepeat: false),
               "brightness up decodes with a positive step")
        suite.expect(BrightnessSupport.brightnessKeyEvent(subtype: 8,
                                                    data1: brightnessData1(keyCode: 3, state: 10, repeated: true))
                == BrightnessSupport.BrightnessKeyEvent(delta: -BrightnessSupport.brightnessKeyStep,
                                                        isKeyDown: true, isRepeat: true),
               "brightness down decodes with a negative step and the repeat bit")
        suite.expect(BrightnessSupport.brightnessKeyEvent(subtype: 8,
                                                    data1: brightnessData1(keyCode: 3, state: 11))?
                .isKeyDown == false,
               "the key release decodes too, so a handled press swallows both halves")
        suite.expect(BrightnessSupport.brightnessKeyEvent(subtype: 8,
                                                    data1: brightnessData1(keyCode: 16, state: 10)) == nil,
               "other media keys never decode as brightness")
        suite.expect(BrightnessSupport.brightnessKeyEvent(subtype: 1, data1: 0) == nil,
               "other system-defined subtypes never decode as brightness")
        suite.expect(BrightnessSupport.keyboardLightOnLevel(lastNonzero: nil) == 0.5
                && BrightnessSupport.keyboardLightOnLevel(lastNonzero: 0) == 0.5
                && BrightnessSupport.keyboardLightOnLevel(lastNonzero: 0.7) == 0.7
                && BrightnessSupport.keyboardLightOnLevel(lastNonzero: 2) == 1,
               "keyboard light restores its last level or starts halfway")
        suite.expect(BrightnessSupport.steppedBrightness(0.97, delta: BrightnessSupport.brightnessKeyStep) == 1.0
                && BrightnessSupport.steppedBrightness(0.03, delta: -BrightnessSupport.brightnessKeyStep) == 0.0,
               "key steps clamp at both ends of the range")

        // Keyboards other than the built-in one send brightness as a plain
        // key press, which is why the pointer never got a say on them
        // (issue #287). Codes measured against the display server.
        func functionKey(_ code: Int,
                         down: Bool = true,
                         modifiers: Bool = false,
                         functionKeys: Bool = true) -> BrightnessSupport.BrightnessKeyEvent? {
            BrightnessSupport.brightnessFunctionKeyEvent(keyCode: code,
                                                         isKeyDown: down,
                                                         isRepeat: false,
                                                         hasModifiers: modifiers,
                                                         functionKeysAdjustBrightness: functionKeys)
        }
        suite.expect(functionKey(144)?.delta == BrightnessSupport.brightnessKeyStep,
               "the dedicated brightness up code steps up by one sixteenth")
        suite.expect(functionKey(145)?.delta == -BrightnessSupport.brightnessKeyStep,
               "the dedicated brightness down code steps down by one sixteenth")
        suite.expect(functionKey(113)?.delta == BrightnessSupport.brightnessKeyStep,
               "F15 steps up while the system still offers it as a brightness key")
        suite.expect(functionKey(107)?.delta == -BrightnessSupport.brightnessKeyStep,
               "F14 steps down while the system still offers it as a brightness key")
        suite.expect(functionKey(113, functionKeys: false) == nil
                && functionKey(107, functionKeys: false) == nil,
               "the function keys are left alone once the system stops using them")
        suite.expect(functionKey(144, functionKeys: false)?.delta == BrightnessSupport.brightnessKeyStep,
               "the dedicated codes mean brightness whatever the function keys do")
        suite.expect(functionKey(144, modifiers: true) == nil,
               "a modified press belongs to the system, not to us")
        suite.expect(functionKey(0) == nil && functionKey(53) == nil,
               "ordinary typing never decodes as brightness")
        suite.expect(functionKey(145, down: false)?.isKeyDown == false,
               "the release decodes too, so a consumed press consumes both halves")
        suite.expect(BrightnessSupport.isBrightnessKeyCode(144)
                && BrightnessSupport.isBrightnessKeyCode(145)
                && BrightnessSupport.isBrightnessKeyCode(107)
                && BrightnessSupport.isBrightnessKeyCode(113),
               "the four brightness codes are recognized on the fast path")
        suite.expect(!BrightnessSupport.isBrightnessKeyCode(0)
                && !BrightnessSupport.isBrightnessKeyCode(36),
               "letters and Return leave the fast path immediately")
        suite.expect(BrightnessSupport.functionKeysAdjustBrightness(symbolicHotKeys: nil),
               "the system ships the function keys as brightness keys")
        suite.expect(BrightnessSupport.functionKeysAdjustBrightness(symbolicHotKeys: [:]),
               "an untouched shortcut list means the defaults are in force")
        suite.expect(!BrightnessSupport.functionKeysAdjustBrightness(
            symbolicHotKeys: ["53": ["enabled": false]]),
               "turning the system shortcut off gives the function key back")
        suite.expect(!BrightnessSupport.functionKeysAdjustBrightness(
            symbolicHotKeys: ["54": ["enabled": NSNumber(value: false)]]),
               "the shortcut flag is read whichever way it was stored")
        suite.expect(BrightnessSupport.functionKeysAdjustBrightness(
            symbolicHotKeys: ["53": ["enabled": true], "54": ["enabled": true]]),
               "shortcuts left switched on keep the function keys as brightness")

        // Pointer routing on system-routed displays (issue #268): the system
        // only ever steps its native target, so any other display the
        // pointer picks must be stepped by the app.
        suite.expect(BrightnessSupport.stepsSystemRoutedDisplay(followsPointer: true,
                                                          displayIsBuiltIn: false,
                                                          overlayReplacesNative: false),
               "pointer on an Apple pipeline external display steps here even without the overlay")
        suite.expect(!BrightnessSupport.stepsSystemRoutedDisplay(followsPointer: true,
                                                           displayIsBuiltIn: true,
                                                           overlayReplacesNative: false),
               "pointer on the built-in panel keeps the system's native handling")
        suite.expect(BrightnessSupport.stepsSystemRoutedDisplay(followsPointer: true,
                                                          displayIsBuiltIn: true,
                                                          overlayReplacesNative: true),
               "the opt-in overlay replaces native handling on the built-in panel")
        suite.expect(!BrightnessSupport.stepsSystemRoutedDisplay(followsPointer: false,
                                                           displayIsBuiltIn: false,
                                                           overlayReplacesNative: false),
               "with pointer routing off and no overlay, the press stays with the system")
        suite.expect(BrightnessSupport.stepsSystemRoutedDisplay(followsPointer: false,
                                                          displayIsBuiltIn: false,
                                                          overlayReplacesNative: true),
               "with the overlay on, the system target is stepped here so only one OSD draws")
        // An external keyboard's plain brightness keys must reach the island
        // or the overlay too, not only the pointer routing (beta feedback).
        suite.expect(BrightnessSupport.answersPlainBrightnessKeys(followsPointer: false, overlayReplacesNative: true)
                && BrightnessSupport.answersPlainBrightnessKeys(followsPointer: true, overlayReplacesNative: false)
                && !BrightnessSupport.answersPlainBrightnessKeys(followsPointer: false, overlayReplacesNative: false),
               "plain brightness keys are answered here whenever the app replaces the system's handling")
        suite.expect(BrightnessSupport.plainKeyTarget(followsPointer: false, pointerDisplay: 2, systemTarget: 1) == 1
                && BrightnessSupport.plainKeyTarget(followsPointer: true, pointerDisplay: 2, systemTarget: 1) == 2
                && BrightnessSupport.plainKeyTarget(followsPointer: true, pointerDisplay: nil, systemTarget: 1) == nil
                && BrightnessSupport.plainKeyTarget(followsPointer: false, pointerDisplay: 2, systemTarget: nil) == nil,
               "without pointer routing a plain key moves the system's own target, never the pointer's display")
        suite.expect(BrightnessSupport.filledBrightnessSegments(0) == 0
                && BrightnessSupport.filledBrightnessSegments(0.01) == 1
                && BrightnessSupport.filledBrightnessSegments(0.5) == 8
                && BrightnessSupport.filledBrightnessSegments(1.2) == 16,
               "brightness overlay segments clamp and preserve non-zero levels")
        suite.expect(BrightnessSupport.wholePercent(-0.2) == 0
                && BrightnessSupport.wholePercent(0.634) == 63
                && BrightnessSupport.wholePercent(0.999) == 100
                && BrightnessSupport.wholePercent(1.2) == 100
                && BrightnessSupport.wholePercent(.infinity) == 0,
               "brightness overlay percentage rounds and clamps safely")
        // Show brightness when adjusting governs the app's overlay. The island
        // stands in for the system only while it shows notices.
        suite.expect(BrightnessSupport.overlayReplacesNative(overlayEnabled: true, islandRoutes: false,
                                                             islandShowsNotices: false),
               "the opt-in overlay replaces the system's brightness feedback")
        suite.expect(BrightnessSupport.overlayReplacesNative(overlayEnabled: false, islandRoutes: true,
                                                             islandShowsNotices: true),
               "an island that shows notices stands in for the system's brightness feedback")
        let hiddenIsland = BrightnessSupport.overlayReplacesNative(overlayEnabled: false, islandRoutes: true,
                                                                   islandShowsNotices: false)
        suite.expect(!hiddenIsland && !BrightnessSupport.stepsSystemRoutedDisplay(followsPointer: false,
                                                                                  displayIsBuiltIn: true,
                                                                                  overlayReplacesNative: hiddenIsland),
               "with the overlay off, an island hidden until hover leaves the built-in panel's key to the system")
        suite.expect(!BrightnessSupport.overlayReplacesNative(overlayEnabled: false, islandRoutes: false,
                                                              islandShowsNotices: true),
               "an island without brightness leaves the key to the system")
        suite.expect(!brightnessWorkQueueCode.contains("NotchSupport.routes(.brightness)"),
               "the app's overlay appears only with its own option, never in place of an island that shows nothing")

    }
}

/// The production lifecycle and event handlers are extracted into Service.
/// These doubles replace the workspace, permission, event tap and application
/// endpoints; no test observes real input, opens an app or terminates a process.
enum MusicLaunchBlockerContract {
    enum Environment {
        static var enabled = true
        static var available = true
        static var trusted = true
        static var createsTap = true
        static var enablesTap = true
        static var now: TimeInterval = 10
        static var gestureAge: TimeInterval = 3
        static var running: [NSRunningApplication] = []
    }
    enum AppFeature {
        case musicBlock
        var isAvailable: Bool { Environment.available }
    }
    enum UserDefaults {
        static let standard = Store()
        final class Store {
            func bool(forKey key: String) -> Bool { Environment.enabled }
        }
    }
    static func AXIsProcessTrusted() -> Bool { Environment.trusted }
    enum ProcessInfo {
        static let processInfo = Clock()
        struct Clock { var systemUptime: TimeInterval { Environment.now } }
    }
    final class Tap { var enabled = true }
    final class CGEvent {
        let timestamp: TimeInterval
        let subtype: Int
        let data1: Int
        init(at timestamp: TimeInterval, subtype: Int = 8, key: UInt16 = 16,
             state: Int = 10, repeats: Bool = false) {
            self.timestamp = timestamp
            self.subtype = subtype
            data1 = Int((UInt32(key) << 16) | (UInt32(state) << 8) | (repeats ? 1 : 0))
        }
        static func tapIsEnabled(tap: Tap) -> Bool { tap.enabled }
        static func tapEnable(tap: Tap, enable: Bool) { tap.enabled = enable && Environment.enablesTap }
    }
    struct NSEvent {
        struct Subtype { let rawValue: Int }
        let subtype: Subtype
        let data1: Int
        let timestamp: TimeInterval
        init?(cgEvent: CGEvent) {
            subtype = Subtype(rawValue: cgEvent.subtype)
            data1 = cgEvent.data1
            timestamp = cgEvent.timestamp
        }
    }
    final class NSRunningApplication {
        let bundleIdentifier: String?
        let processIdentifier: pid_t
        var forceSucceeds = true
        var terminateSucceeds = true
        var forceCalls = 0
        var terminateCalls = 0
        init(_ pid: pid_t, bundle: String? = "com.apple.Music") {
            processIdentifier = pid
            bundleIdentifier = bundle
        }
        static func runningApplications(withBundleIdentifier bundle: String) -> [NSRunningApplication] {
            Environment.running.filter { $0.bundleIdentifier == bundle }
        }
        func forceTerminate() -> Bool { forceCalls += 1; return forceSucceeds }
        func terminate() -> Bool { terminateCalls += 1; return terminateSucceeds }
    }
    enum NSWorkspace {
        static let shared = Workspace()
        static let willLaunchApplicationNotification = Notification.Name("fixture.willLaunch")
        static let didLaunchApplicationNotification = Notification.Name("fixture.didLaunch")
        static let applicationUserInfoKey = "application"
        final class Workspace { let notificationCenter = NotificationCenter() }
    }
    class Fixture {
        static let blockedBundleIDs: Set<String> = ["com.apple.Music", "com.apple.iTunes"]
        static var secondsSinceUserGesture: TimeInterval { Environment.gestureAge }
        var isEnabled: Bool { Environment.enabled && Environment.available }
        var isMonitoring = false
        var observers: [NSObjectProtocol] = []
        var mediaKeyTap: Tap?
        var lastMediaKeyAt: TimeInterval?
        var lastMediaKeyCode: UInt16?
        var judgedLaunchPID: pid_t?
        var replacementCalls = 0
        var replacementPlays: [Bool] = []
        func installMediaKeyTap() {
            if mediaKeyTap == nil, Environment.createsTap { mediaKeyTap = Tap() }
        }
        func removeMediaKeyTap() { mediaKeyTap?.enabled = false; mediaKeyTap = nil }
        func openReplacementIfConfigured(startingPlayback: Bool) {
            replacementCalls += 1
            replacementPlays.append(startingPlayback)
        }
    }

    static func run(_ suite: TestSuite) {
        let service = Service()
        defer { service.stop() }
        func reset() {
            service.stop()
            service.replacementCalls = 0
            service.replacementPlays = []
            Environment.enabled = true
            Environment.available = true
            Environment.trusted = true
            Environment.createsTap = true
            Environment.enablesTap = true
            Environment.now = 10
            Environment.gestureAge = 3
            Environment.running = []
        }
        func launch(_ app: NSRunningApplication, did: Bool = false) {
            service.handleLaunch(Notification(name: did ? NSWorkspace.didLaunchApplicationNotification
                                                : NSWorkspace.willLaunchApplicationNotification,
                                               userInfo: [NSWorkspace.applicationUserInfoKey: app]))
        }
        func key(at: TimeInterval = 9.5, code: UInt16 = 16, state: Int = 10, repeats: Bool = false,
                 type: CGEventType = CGEventType(rawValue: 14)!) {
            let event = CGEvent(at: at, key: code, state: state, repeats: repeats)
            let passed = service.handleMediaKeyEvent(type: type, event: event)?.takeUnretainedValue()
            suite.expect(passed === event, "the blocker observes events without swallowing or replacing them")
        }
        reset()
        Environment.trusted = false
        service.syncWithPreferences()
        suite.expect(!service.isMonitoring && service.mediaKeyTap == nil && service.observers.isEmpty,
                     "without Accessibility the blocker has no tap, observer or claimed protection")
        launch(NSRunningApplication(1))
        Environment.trusted = true
        Environment.createsTap = false
        service.syncWithPreferences()
        suite.expect(!service.isMonitoring && service.observers.isEmpty,
                     "a failed tap cannot leave a launch observer making unsupported decisions")
        Environment.createsTap = true
        service.syncWithPreferences()
        let installed = service.observers.count
        service.syncWithPreferences()
        suite.expect(service.isMonitoring && service.mediaKeyTap != nil && installed == 2
                     && service.observers.count == installed,
                     "granting access starts one observer pair and repeated syncs do not duplicate it")
        let automatic = NSRunningApplication(2)
        key()
        launch(automatic)
        launch(automatic, did: true)
        suite.expect(automatic.forceCalls == 1 && automatic.terminateCalls == 0 && service.replacementCalls == 1,
                     "a detected key blocks one launch and its did-launch cannot repeat termination or replacement")
        key(code: MusicLaunchSupport.nextTrackKeyCode)
        launch(NSRunningApplication(50))
        suite.expect(service.replacementPlays == [true, false],
                     "only Play/Pause asks the replacement to play; the other media keys only open it")
        let second = NSRunningApplication(3)
        launch(second)
        suite.expect(second.forceCalls == 0 && service.lastMediaKeyAt == nil,
                     "the same media key cannot terminate a second launch within its arm window")
        let manual = NSRunningApplication(4)
        key()
        Environment.gestureAge = 0.1
        launch(manual)
        Environment.gestureAge = 100
        launch(manual, did: true)
        suite.expect(manual.forceCalls == 0 && service.lastMediaKeyAt == nil,
                     "a later deliberate gesture wins and did-launch cannot reverse that decision")
        for pid: pid_t in 5...7 {
            let deliberate = NSRunningApplication(pid)
            launch(deliberate)
            suite.expect(deliberate.forceCalls == 0, "voice, automation and login without a media key are left alone")
        }
        let delayed = NSRunningApplication(8)
        key(at: 7)
        launch(delayed)
        suite.expect(delayed.forceCalls == 0, "delayed event delivery does not refresh an expired trigger")
        Environment.running = [NSRunningApplication(40)]
        key()
        Environment.running = []
        let afterExistingPlayer = NSRunningApplication(41)
        launch(afterExistingPlayer)
        suite.expect(afterExistingPlayer.forceCalls == 0 && service.lastMediaKeyAt == nil,
                     "a key sent to a running player cannot arm its later deliberate relaunch")
        for type in [CGEventType.tapDisabledByTimeout, .tapDisabledByUserInput] {
            key()
            service.mediaKeyTap?.enabled = false
            key(type: type)
            let afterGap = NSRunningApplication(type == .tapDisabledByTimeout ? 9 : 10)
            launch(afterGap)
            suite.expect(afterGap.forceCalls == 0 && service.lastMediaKeyAt == nil && service.isMonitoring,
                         "recovering a disabled tap starts with no stale key evidence")
        }
        key()
        service.mediaKeyTap?.enabled = false
        let disabled = NSRunningApplication(11)
        launch(disabled)
        suite.expect(disabled.forceCalls == 0 && !service.isMonitoring && service.lastMediaKeyAt == nil,
                     "an untrusted gap detected at launch drops the trigger and reports unavailable")
        Environment.enablesTap = false
        key(type: .tapDisabledByTimeout)
        suite.expect(!service.isMonitoring && service.lastMediaKeyAt == nil,
                     "a failed recovery never advertises active protection")
        for missing in ["preference", "feature", "permission"] {
            reset()
            service.syncWithPreferences()
            key()
            if missing == "preference" { Environment.enabled = false }
            if missing == "feature" { Environment.available = false }
            if missing == "permission" { Environment.trusted = false }
            let afterDisable = NSRunningApplication(20)
            launch(afterDisable)
            key()
            suite.expect(afterDisable.forceCalls == 0 && service.observers.isEmpty
                         && service.mediaKeyTap == nil && service.lastMediaKeyAt == nil && !service.isMonitoring,
                         "losing the \(missing) prevents queued launch/event callbacks and tears down resources")
        }
        reset()
        service.syncWithPreferences()
        key()
        service.stop()
        service.syncWithPreferences()
        let restarted = NSRunningApplication(30)
        launch(restarted)
        suite.expect(restarted.forceCalls == 0, "reenabling the feature cannot reuse the prior activation's trigger")
        for event in [(UInt16(0), 10, false), (16, 11, false), (16, 10, true)] {
            key(code: event.0, state: event.1, repeats: event.2)
            suite.expect(service.lastMediaKeyAt == nil, "volume, release and repeat events do not arm a launch")
        }
        key()
        let unrelated = NSRunningApplication(31, bundle: "org.example.other")
        launch(unrelated)
        suite.expect(unrelated.forceCalls == 0 && service.lastMediaKeyAt != nil,
                     "another app's launch is never terminated and does not consume the music trigger")
        let failed = NSRunningApplication(32)
        failed.forceSucceeds = false
        failed.terminateSucceeds = false
        launch(failed)
        suite.expect(failed.forceCalls == 1 && failed.terminateCalls == 1 && service.replacementCalls == 0,
                     "a failed termination does not open a competing replacement app")
        key()
        let fallback = NSRunningApplication(33, bundle: "com.apple.iTunes")
        fallback.forceSucceeds = false
        launch(fallback)
        suite.expect(fallback.forceCalls == 1 && fallback.terminateCalls == 1 && service.replacementCalls == 1,
                     "a successful normal termination still opens the configured replacement once")
    }
}
