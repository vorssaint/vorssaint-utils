// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation
import CoreGraphics

enum AutoClickerContractTests {
    static func run(_ suite: TestSuite) {
        suite.run("autoclicker-buttons") {
            suite.expect(AutoClickerButton.allCases.count == 3, "3 buttons")
            suite.expect(AutoClickerButton.left.buttonNumber == 0, "left button 0")
            suite.expect(AutoClickerButton.right.buttonNumber == 1, "right button 1")
            suite.expect(AutoClickerButton.middle.buttonNumber == 2, "middle button 2")
            suite.expect(AutoClickerButton.left.cgMouseButton == .left, "left cgMouseButton")
            suite.expect(AutoClickerButton.right.cgMouseButton == .right, "right cgMouseButton")
            suite.expect(AutoClickerButton.middle.cgMouseButton == .center, "middle cgMouseButton")
            suite.expect(AutoClickerButton.left.cgEventTypeDown == .leftMouseDown, "left down")
            suite.expect(AutoClickerButton.right.cgEventTypeDown == .rightMouseDown, "right down")
            suite.expect(AutoClickerButton.middle.cgEventTypeDown == .otherMouseDown, "middle down")
            suite.expect(AutoClickerButton.left.cgEventTypeUp == .leftMouseUp, "left up")
            suite.expect(AutoClickerButton.right.cgEventTypeUp == .rightMouseUp, "right up")
            suite.expect(AutoClickerButton.middle.cgEventTypeUp == .otherMouseUp, "middle up")
        }

        suite.run("autoclicker-modes-and-models") {
            suite.expect(AutoClickerMode.allCases == [.single, .macro], "2 modes")
            suite.expect(AutoClickerTargetMode.allCases == [.cursor, .fixedPoint], "2 target modes")

            let clampedStep = AutoClickerMacroStep(
                x: 320,
                y: 480,
                button: .right,
                delayAfterMs: 2,
                clickCount: 5
            )
            suite.expect(clampedStep.delayAfterMs == 10, "delay clamped to >= 10ms")
            suite.expect(clampedStep.clickCount == 2, "clickCount clamped to 1...2")

            let macro = AutoClickerMacro(
                name: "Farm Loop",
                steps: [
                    AutoClickerMacroStep(x: 100, y: 200, button: .left, delayAfterMs: 150, clickCount: 1),
                    clampedStep,
                ],
                repeatCount: -3
            )
            suite.expect(macro.repeatCount == 0, "repeatCount clamped to >= 0")

            let encoded = AutoClickerMacroStore.encode([macro])
            suite.expect(!encoded.isEmpty, "encoded JSON not empty")
            let decoded = AutoClickerMacroStore.decode(encoded)
            suite.expect(decoded == [macro], "round-trip macro encoding")
            suite.expect(AutoClickerMacroStore.decode("").isEmpty, "empty string decodes to empty")
            suite.expect(AutoClickerMacroStore.decode("not-json").isEmpty, "invalid JSON decodes to empty")
        }

        suite.run("autoclicker-coordinates") {
            let maxY: CGFloat = 1080
            let cg = AutoClickerCoordinates.cgPoint(fromAppKitPoint: CGPoint(x: 250, y: 880), primaryScreenMaxY: maxY)
            suite.expect(cg.x == 250 && cg.y == 200, "AppKit to CGPoint flips Y around primaryScreenMaxY")
            let appKit = AutoClickerCoordinates.appKitPoint(fromCGPoint: cg, primaryScreenMaxY: maxY)
            suite.expect(appKit.x == 250 && appKit.y == 880, "CGPoint to AppKit round-trips")
            suite.expect(AutoClickerCoordinates.clampedDelayMs(0) == 10, "delay min 10")
            suite.expect(AutoClickerCoordinates.clampedDelayMs(250) == 250, "delay preserves >= 10")
        }

        suite.run("autoclicker-feature-catalog") {
            suite.expect(AppFeature.autoClicker.group == .mouseKeyboard, "group is mouseKeyboard")
            suite.expect(AppFeature.autoClicker.permissions == [.accessibility], "permission is accessibility")
            suite.expect(AppFeature.autoClicker.enabledKeys == [DefaultsKey.autoClickerEnabled], "enabledKeys")
            suite.expect(AppFeature.autoClicker.symbolName == "cursorarrow.click.2", "symbolName")
            suite.expect(!AppFeature.autoClicker.installedByDefault, "installedByDefault is false (opt-in)")
        }

        suite.run("autoclicker-shortcut-role") {
            let role = GlobalShortcutRole.autoClicker
            suite.expect(role.storageKey == DefaultsKey.autoClickerShortcut, "storageKey")
            suite.expect(role.supportsClearing, "supportsClearing")
            suite.expect(role.requiredEnableKeys == [DefaultsKey.autoClickerEnabled], "requiredEnableKeys")
            suite.expect(role.feature == .autoClicker, "feature")
        }

        suite.run("autoclicker-defaults") {
            suite.expect(Defaults.registeredDefaults[DefaultsKey.autoClickerEnabled] as? Bool == false, "default enabled false")
            suite.expect(Defaults.registeredDefaults[DefaultsKey.autoClickerButton] as? String == "left", "default button left")
            suite.expect(Defaults.registeredDefaults[DefaultsKey.autoClickerIntervalMs] as? Int == 100, "default interval 100")
            suite.expect(Defaults.registeredDefaults[DefaultsKey.autoClickerRepeatLimit] as? Int == 0, "default repeat limit 0")
            suite.expect(Defaults.registeredDefaults[DefaultsKey.autoClickerMode] as? String == "single", "default mode single")
            suite.expect(Defaults.registeredDefaults[DefaultsKey.autoClickerTargetMode] as? String == "cursor", "default target mode cursor")
            suite.expect(Defaults.registeredDefaults[DefaultsKey.autoClickerTargetX] as? Double == 0.0, "default targetX 0.0")
            suite.expect(Defaults.registeredDefaults[DefaultsKey.autoClickerTargetY] as? Double == 0.0, "default targetY 0.0")
            suite.expect(Defaults.registeredDefaults[DefaultsKey.autoClickerMacros] as? String == "", "default macros empty")
            suite.expect(Defaults.registeredDefaults[DefaultsKey.autoClickerSelectedMacroId] as? String == "", "default selectedMacroId empty")
        }

        suite.run("autoclicker-strings") {
            for lang in AppLanguage.allCases {
                let strings = FeatureStrings.autoClicker(lang)
                suite.expect(!strings.title.isEmpty, "\(lang) title not empty")
                suite.expect(!strings.modeSingle.isEmpty, "\(lang) modeSingle not empty")
                suite.expect(!strings.modeMacro.isEmpty, "\(lang) modeMacro not empty")
                suite.expect(!strings.targetCursor.isEmpty, "\(lang) targetCursor not empty")
                suite.expect(!strings.targetFixedPoint.isEmpty, "\(lang) targetFixedPoint not empty")
                suite.expect(!strings.pickLocationAction.isEmpty, "\(lang) pickLocationAction not empty")
                suite.expect(!strings.macroRecordStepsAction.isEmpty, "\(lang) macroRecordStepsAction not empty")
                suite.expect(!strings.buttonLeft.isEmpty, "\(lang) buttonLeft not empty")
                suite.expect(!strings.buttonRight.isEmpty, "\(lang) buttonRight not empty")
                suite.expect(!strings.buttonMiddle.isEmpty, "\(lang) buttonMiddle not empty")
                suite.expect(!strings.startAction.isEmpty, "\(lang) startAction not empty")
                suite.expect(!strings.stopAction.isEmpty, "\(lang) stopAction not empty")
                suite.expect(!strings.emergencyStopHint.isEmpty, "\(lang) emergencyStopHint not empty")
            }
        }
    }
}
