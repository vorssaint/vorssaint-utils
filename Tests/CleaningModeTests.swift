// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Darwin
import Foundation

enum CleaningModeTests {
    static func run(expect: (Bool, String) -> Void) {
        // MARK: Cleaning-mode unlock gesture

        let escapeKeyCode: Int64 = 53

        // Five deliberate Escape taps unlock, on the fifth.
        var taps = CleaningUnlockCounter(requiredKeyCode: escapeKeyCode, threshold: 5, pressWindow: 2.0)
        var tapUnlock = false
        for (i, t) in [0.0, 0.3, 0.6, 0.9, 1.2].enumerated() {
            tapUnlock = taps.registerKeyDown(code: escapeKeyCode, time: t, isRepeat: false)
            if i < 4 { expect(!tapUnlock, "no unlock before the fifth tap (\(i + 1))") }
        }
        expect(tapUnlock, "five Escape taps unlock")
        expect(taps.progress == 5, "progress reaches the threshold")

        // Wiping other keys cannot make progress toward unlock.
        var wipe = CleaningUnlockCounter(requiredKeyCode: escapeKeyCode, threshold: 5, pressWindow: 2.0)
        var wipeUnlock = false
        for (i, code) in [Int64(10), 11, 12, 13, 14, 15, 16, 17].enumerated() {
            if wipe.registerKeyDown(code: code, time: Double(i) * 0.1, isRepeat: false) { wipeUnlock = true }
        }
        expect(!wipeUnlock, "wiping other keys never unlocks")
        expect(wipe.progress == 0, "other keys make no unlock progress")

        // A different key mid-streak resets the count completely.
        var streak = CleaningUnlockCounter(requiredKeyCode: escapeKeyCode, threshold: 5, pressWindow: 2.0)
        _ = streak.registerKeyDown(code: escapeKeyCode, time: 0.0, isRepeat: false)
        _ = streak.registerKeyDown(code: escapeKeyCode, time: 0.2, isRepeat: false)
        _ = streak.registerKeyDown(code: escapeKeyCode, time: 0.4, isRepeat: false)
        _ = streak.registerKeyDown(code: 8, time: 0.6, isRepeat: false)
        expect(streak.progress == 0, "a different key mid-streak clears progress")

        // Auto-repeat (holding Escape) is ignored, so resting on it can't unlock.
        var held = CleaningUnlockCounter(requiredKeyCode: escapeKeyCode, threshold: 5, pressWindow: 2.0)
        var heldUnlock = false
        for i in 0..<10 {
            if held.registerKeyDown(code: escapeKeyCode, time: Double(i) * 0.1, isRepeat: true) { heldUnlock = true }
        }
        expect(!heldUnlock, "auto-repeat never unlocks")
        expect(held.progress == 0, "auto-repeat does not advance progress")

        // A pause longer than the window restarts the count.
        var paused = CleaningUnlockCounter(requiredKeyCode: escapeKeyCode, threshold: 5, pressWindow: 2.0)
        _ = paused.registerKeyDown(code: escapeKeyCode, time: 0.0, isRepeat: false)
        _ = paused.registerKeyDown(code: escapeKeyCode, time: 0.5, isRepeat: false)
        expect(paused.progress == 2, "presses within the window accumulate")
        _ = paused.registerKeyDown(code: escapeKeyCode, time: 10.0, isRepeat: false)
        expect(paused.progress == 1, "a pause beyond the window restarts the count")

        // reset() clears everything.
        var cleared = CleaningUnlockCounter(requiredKeyCode: escapeKeyCode, threshold: 5, pressWindow: 2.0)
        _ = cleared.registerKeyDown(code: escapeKeyCode, time: 0.0, isRepeat: false)
        _ = cleared.registerKeyDown(code: escapeKeyCode, time: 0.2, isRepeat: false)
        expect(cleared.progress == 2, "progress accumulates before reset")
        cleared.reset()
        expect(cleared.progress == 0, "reset clears progress")
        let afterReset2 = cleared.registerKeyDown(code: escapeKeyCode, time: 0.4, isRepeat: false)
        expect(!afterReset2 && cleared.progress == 1, "after reset Escape starts fresh at 1")

        // Modifiers are the keys nearest Escape, so a cloth reaches them first.
        // They arrive as flags-changed events, which the tap feeds here too, and
        // one physical press reports twice — once down, once up. Both are resets.
        var smeared = CleaningUnlockCounter(requiredKeyCode: escapeKeyCode, threshold: 5, pressWindow: 6.0)
        let leftShiftKeyCode: Int64 = 56
        var smearedUnlock = false
        for t in [0.0, 0.5, 1.0, 1.5] {
            if smeared.registerKeyDown(code: escapeKeyCode, time: t, isRepeat: false) { smearedUnlock = true }
        }
        expect(smeared.progress == 4, "four Escapes stop one short of the threshold")
        _ = smeared.registerKeyDown(code: leftShiftKeyCode, time: 2.0, isRepeat: false)
        expect(smeared.progress == 0, "a modifier going down clears the Escape count")
        _ = smeared.registerKeyDown(code: leftShiftKeyCode, time: 2.1, isRepeat: false)
        expect(smeared.progress == 0, "the modifier's release resets again, idempotently")
        if smeared.registerKeyDown(code: escapeKeyCode, time: 2.5, isRepeat: false) { smearedUnlock = true }
        expect(!smearedUnlock && smeared.progress == 1,
               "four Escapes with a modifier in between never unlock; the next Escape starts at 1")

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
        expect(!cleaningCode.isEmpty && cleaningCode.contains("pressWindow: 6.0"),
               "the shipped unlock counter keeps the forgiving 6s press window")

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
        var failOpenReturns = 0
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
                failOpenReturns += 1
            } else if line.contains("return"), !line.contains("return nil") {
                leakedEvents.append("CleaningModeManager.swift:\(number)")
            }
        }
        expect(modifiersReachCounter,
               "flags-changed events feed the unlock counter, so modifiers reset the Escape count")
        expect(handlerStart != nil && leakedEvents.isEmpty && failOpenReturns == 1,
               "the cleaning tap swallows normal input and keeps one disabled-session fail-open path: \(leakedEvents)")
        expect(cleaningCode.contains("self.deactivate(restoreSuspendedFeatures: false)")
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
        expect(brightnessDown?.isKeyDown == true && brightnessDown?.isRepeat == false,
               "brightness key down is decoded from system-defined events")

        let volumeUpRepeat = CleaningSystemKeyEvent.decode(
            subtype: CleaningSystemKeyEvent.auxiliaryControlButtonsSubtype,
            data1: systemKeyData(keyCode: 0, state: CleaningSystemKeyEvent.keyDownState, repeatFlag: true)
        )
        expect(volumeUpRepeat?.isKeyDown == true && volumeUpRepeat?.isRepeat == true,
               "system-defined auto-repeat is preserved")

        let mediaNextUp = CleaningSystemKeyEvent.decode(
            subtype: CleaningSystemKeyEvent.auxiliaryControlButtonsSubtype,
            data1: systemKeyData(keyCode: 17, state: CleaningSystemKeyEvent.keyUpState)
        )
        expect(mediaNextUp?.isKeyDown == false,
               "system-defined key up is decoded without advancing unlock")

        let powerKey = CleaningSystemKeyEvent.decode(
            subtype: CleaningSystemKeyEvent.powerKeySubtype,
            data1: 0
        )
        expect(powerKey?.isKeyDown == true && powerKey?.isRepeat == false,
               "power and lock key system events are recognized")

        let unrelatedSystemEvent = CleaningSystemKeyEvent.decode(subtype: 99, data1: 0)
        expect(unrelatedSystemEvent == nil, "unrelated system-defined events do not count as unlock keys")
    }
}
