// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Carbon.HIToolbox
import CoreGraphics
import Foundation

enum FnLockTests {
    static func run(_ suite: TestSuite) {
        suite.run("FnLockSupport.translationTableBijective") {
            // Every function key maps to at least one media form, and every
            // reverse entry answers in the forward table. Measured on the
            // Apple-silicon function row with the development probe
            // (`--fn-probe`, 2026-10): F3-F6 post as plain key-downs
            // (Mission Control 160, Spotlight 177, Dictation 176, Focus 178),
            // brightness and volume as NX system-defined ids, and F4 has a
            // second Intel form (Launchpad 161) that only the forward table
            // carries.
            for functionKey in FnLockSupport.functionRowKeyCodes {
                let media = FnLockSupport.functionToMediaKeyDown[functionKey]
                let nx = FnLockSupport.functionToNXKey[functionKey]
                suite.expect(media != nil || nx != nil,
                              "F\(functionKey) has at least one media form")
                if let media, let back = FnLockSupport.mediaKeyDownToFunction[media] {
                    suite.expect(back == functionKey,
                                  "media \(media) maps back to F\(functionKey), got F\(back)")
                }
                if let nx, let back = FnLockSupport.nxKeyToFunction[nx] {
                    suite.expect(back == functionKey,
                                  "nx \(nx) maps back to F\(functionKey), got F\(back)")
                }
            }
        }

        suite.run("FnLockSupport.probeMeasuredKeyCodes") {
            // The Apple-silicon function row as the probe measured it.
            suite.expect(FnLockSupport.mediaKeyDownToFunction[160] == Int(kVK_F3),
                          "Mission Control 160 -> F3")
            suite.expect(FnLockSupport.mediaKeyDownToFunction[177] == Int(kVK_F4),
                          "Spotlight 177 -> F4")
            suite.expect(FnLockSupport.mediaKeyDownToFunction[176] == Int(kVK_F5),
                          "Dictation 176 -> F5")
            suite.expect(FnLockSupport.mediaKeyDownToFunction[178] == Int(kVK_F6),
                          "Focus 178 -> F6")
            suite.expect(FnLockSupport.mediaKeyDownToFunction[161] == Int(kVK_F4),
                          "Intel Launchpad 161 -> F4")
            suite.expect(FnLockSupport.functionToMediaKeyDown[Int(kVK_F4)] == 177,
                          "reverse F4 rewrites to Spotlight 177")
            suite.expect(FnLockSupport.functionToMediaKeyDown[Int(kVK_F5)] == 176,
                          "reverse F5 rewrites to Dictation 176")
            suite.expect(FnLockSupport.functionToMediaKeyDown[Int(kVK_F6)] == 178,
                          "reverse F6 rewrites to Focus 178")
            suite.expect(FnLockSupport.functionToNXKey[Int(kVK_F5)] == nil,
                          "F5 posts no NX id on a row without a backlight")
        }

        suite.run("FnLockSupport.systemFunctionKeysDefault") {
            suite.expect(!FnLockSupport.systemFunctionKeysDefault(read: { _ in nil }),
                          "absent preference means off (factory default)")
            suite.expect(FnLockSupport.systemFunctionKeysDefault(read: { _ in true }),
                          "fnState true means on")
            suite.expect(!FnLockSupport.systemFunctionKeysDefault(read: { _ in false }),
                          "fnState false means off")
        }

        suite.run("FnLockSupport.keyDownAction.forwardDirection") {
            // System setting OFF (media keys win): a listed app's F1 (arriving
            // as media keycode 145) is rewritten to the function keycode 122.
            let action = FnLockSupport.keyDownAction(keyCode: 145, isKeyDown: true,
                                                     systemFunctionKeysDefault: false)
            guard case .rewrite(let target) = action else {
                suite.expect(false, "expected .rewrite, got \(action)")
                return
            }
            suite.expect(target == Int(kVK_F1), "145 -> F1 (122), got \(target)")
        }

        suite.run("FnLockSupport.keyDownAction.forwardAppleSiliconRow") {
            // System setting OFF, probe-measured Apple-silicon row: the F4
            // key arrives as Spotlight 177, F5 as Dictation 176, F6 as Focus
            // 178, all rewritten to their function keys.
            for (functionKey, mediaKey, label) in [
                (Int(kVK_F4), 177, "Spotlight 177 -> F4"),
                (Int(kVK_F5), 176, "Dictation 176 -> F5"),
                (Int(kVK_F6), 178, "Focus 178 -> F6"),
            ] {
                let action = FnLockSupport.keyDownAction(keyCode: mediaKey, isKeyDown: true,
                                                         systemFunctionKeysDefault: false)
                guard case .rewrite(let target) = action else {
                    suite.expect(false, "\(label): expected .rewrite, got \(action)")
                    return
                }
                suite.expect(target == functionKey, "\(label), got \(target)")
            }
        }

        suite.run("FnLockSupport.keyDownAction.reverseDirection") {
            // System setting ON (function keys win): a listed app's F1 (arriving
            // as keycode 122) is swallowed and posted as NX brightness down (3).
            let downAction = FnLockSupport.keyDownAction(keyCode: Int(kVK_F1), isKeyDown: true,
                                                          systemFunctionKeysDefault: true)
            guard case .postMediaDown(let nxKey) = downAction else {
                suite.expect(false, "expected .postMediaDown, got \(downAction)")
                return
            }
            suite.expect(nxKey == 3, "F1 -> NX brightness down (3), got \(nxKey)")

            let upAction = FnLockSupport.keyDownAction(keyCode: Int(kVK_F1), isKeyDown: false,
                                                        systemFunctionKeysDefault: true)
            guard case .postMediaUp(let nxKey) = upAction else {
                suite.expect(false, "expected .postMediaUp, got \(upAction)")
                return
            }
            suite.expect(nxKey == 3, "F1 up -> NX brightness down (3), got \(nxKey)")
        }

        suite.run("FnLockSupport.keyDownAction.reversePlainKeyForms") {
            // F3-F6 have no NX id on this row; in the reverse direction they
            // rewrite to their probe-measured plain media keycodes.
            for (function, media, label) in [
                (Int(kVK_F3), 160, "F3 -> 160 (Mission Control)"),
                (Int(kVK_F4), 177, "F4 -> 177 (Spotlight)"),
                (Int(kVK_F5), 176, "F5 -> 176 (Dictation)"),
                (Int(kVK_F6), 178, "F6 -> 178 (Focus)"),
            ] {
                let action = FnLockSupport.keyDownAction(keyCode: function, isKeyDown: true,
                                                         systemFunctionKeysDefault: true)
                guard case .rewrite(let target) = action else {
                    suite.expect(false, "\(label): expected .rewrite, got \(action)")
                    return
                }
                suite.expect(target == media, "\(label), got \(target)")
            }
        }

        suite.run("FnLockSupport.keyDownAction.passThrough") {
            // A non-F key is never translated.
            let action = FnLockSupport.keyDownAction(keyCode: 0, isKeyDown: true,
                                                     systemFunctionKeysDefault: false)
            suite.expect(action == .passThrough, "non-F key passes through")
        }

        suite.run("FnLockSupport.systemDefinedAction.forward") {
            // System setting OFF: an NX brightness-down event (key 3, state
            // down) is swallowed and posted as the function keycode.
            let action = FnLockSupport.systemDefinedAction(nxKey: 3, state: FnLockSupport.nxKeyDownState,
                                                            systemFunctionKeysDefault: false)
            guard case .postFunctionKey(let keyCode) = action else {
                suite.expect(false, "expected .postFunctionKey, got \(action)")
                return
            }
            suite.expect(keyCode == Int(kVK_F1), "NX 3 -> F1 (122), got \(keyCode)")
        }

        suite.run("FnLockSupport.systemDefinedAction.reversePasses") {
            // System setting ON: an NX event already carries the media action
            // the listed app asked for, so it passes.
            let action = FnLockSupport.systemDefinedAction(nxKey: 3, state: FnLockSupport.nxKeyDownState,
                                                            systemFunctionKeysDefault: true)
            suite.expect(action == .passThrough, "NX event passes in reverse direction")
        }

        suite.run("FnLockSupport.systemDefinedAction.nonKeyState") {
            // Only press (0x0a) and release (0x0b) are key states.
            let action = FnLockSupport.systemDefinedAction(nxKey: 3, state: 0,
                                                            systemFunctionKeysDefault: false)
            suite.expect(action == .passThrough, "non-key-state passes through")
        }

        suite.run("FnLockSupport.TranslationDedup") {
            var dedup = FnLockSupport.TranslationDedup()
            let now = ProcessInfo.processInfo.systemUptime
            dedup.record(functionKey: 122, at: now)
            suite.expect(dedup.blocks(functionKey: 122, at: now + 0.01),
                         "same key inside the window is blocked")
            suite.expect(!dedup.blocks(functionKey: 122, at: now + FnLockSupport.TranslationDedup.window + 0.01),
                         "same key after the window is not blocked")
            suite.expect(!dedup.blocks(functionKey: 120, at: now),
                         "different key is not blocked")
            dedup.reset()
            suite.expect(!dedup.blocks(functionKey: 122, at: now),
                         "reset clears the record")
        }

        suite.run("FnLockKeyEvents.marker") {
            suite.expect(FnLockKeyEvents.postedMarker == 0x464E4C4B,
                         "posted marker is 'FNLK' in hex")
        }

        suite.run("FnLockSupport.keyNames") {
            // The names the settings page's key test shows, so a user can read
            // "Spotlight (177) -> F4 (118)" and check it against what the app
            // actually did.
            suite.expect(FnLockSupport.functionKeyName(keyCode: Int(kVK_F4)) == "F4", "F4 names itself")
            suite.expect(FnLockSupport.functionKeyName(keyCode: Int(kVK_F12)) == "F12", "F12 names itself")
            suite.expect(FnLockSupport.functionKeyName(keyCode: 0) == nil,
                         "a non-row key has no name")
            suite.expect(FnLockSupport.mediaKeyDownName(keyCode: 177) == "Spotlight",
                         "177 is Spotlight, the probe-measured Apple silicon form")
            suite.expect(FnLockSupport.mediaKeyDownName(keyCode: 176) == "Dictation",
                         "176 is Dictation")
            suite.expect(FnLockSupport.mediaKeyDownName(keyCode: 161) == "Launchpad",
                         "161 is the Intel Launchpad form")
            suite.expect(FnLockSupport.nxKeyName(nxKey: 3) == "Brightness down",
                         "NX 3 is brightness down")
            suite.expect(FnLockSupport.nxKeyName(nxKey: 0) == "Volume up",
                         "NX 0 is volume up")
        }

        suite.run("FnLockSupport.displayName") {
            suite.expect(FnLockSupport.displayName(for: .keyCode(177)) == "Spotlight (177)",
                         "media keycode shows name and code")
            suite.expect(FnLockSupport.displayName(for: .keyCode(Int(kVK_F4))) == "F4 (118)",
                         "function keycode shows name and code")
            suite.expect(FnLockSupport.displayName(for: .nxKey(3)) == "Brightness down (NX 3)",
                         "NX id shows name and id")
            suite.expect(FnLockSupport.displayName(for: .keyCode(42)) == "Key 42",
                         "an unnamed keycode still shows its number")
        }
    }
}
