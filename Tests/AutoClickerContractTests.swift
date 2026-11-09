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
        }

        suite.run("autoclicker-strings") {
            for lang in AppLanguage.allCases {
                let strings = FeatureStrings.autoClicker(lang)
                suite.expect(!strings.title.isEmpty, "\(lang) title not empty")
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
