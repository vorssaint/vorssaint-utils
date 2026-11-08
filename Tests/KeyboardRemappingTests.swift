// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation
import Carbon.HIToolbox

enum KeyboardRemappingTests {
    static func run(_ suite: TestSuite) {
        suite.expect(KeyboardRemappingTapStatus.afterTapCreation(succeeded: false) == .failed,
                     "failed event-tap creation produces an actionable failure status")
        suite.expect(KeyboardRemappingTapStatus.afterTapCreation(succeeded: true) == .active,
                     "successful event-tap creation produces an active status")

        let globalRule = KeyboardRemappingRule(
            sourceKeyCode: 0,
            output: [KeyboardRemappingChord(keyCode: 11)]
        )
        let commandRule = KeyboardRemappingRule(
            sourceKeyCode: 0,
            sourceModifierMask: GlobalShortcutModifiers.command.rawValue,
            output: [KeyboardRemappingChord(
                keyCode: 7,
                modifierMask: GlobalShortcutModifiers.command.rawValue
            )]
        )
        let appRule = KeyboardRemappingRule(
            sourceKeyCode: 0,
            output: [KeyboardRemappingChord(keyCode: 8)],
            bundleIdentifier: "com.example.editor"
        )

        suite.expect(globalRule.isValid && commandRule.isValid && appRule.isValid,
                     "complete remapping rules validate")
        suite.expect(KeyboardRemappingConfig.matchingRule(
            keyCode: 0,
            modifiers: [.command],
            bundleIdentifier: "com.example.editor",
            rules: [globalRule, commandRule, appRule]
        ) == appRule,
        "an app-specific wildcard rule takes precedence within its app")
        suite.expect(KeyboardRemappingConfig.matchingRule(
            keyCode: 0,
            modifiers: [.command],
            bundleIdentifier: "com.example.other",
            rules: [globalRule, commandRule]
        ) == commandRule,
        "an exact shortcut takes precedence over a global single-key rule")
        suite.expect(KeyboardRemappingConfig.matchingRule(
            keyCode: 0,
            modifiers: [.shift],
            bundleIdentifier: "com.example.other",
            rules: [globalRule, commandRule]
        ) == globalRule,
        "a modifier-free source key matches while preserving other held modifiers")
        suite.expect(KeyboardRemappingConfig.matchingRule(
            keyCode: 0,
            modifiers: [],
            bundleIdentifier: "com.example.other",
            rules: [appRule]
        ) == nil,
        "app-scoped rules do not match a different frontmost app")

        let preserved = KeyboardRemappingConfig.outputModifiers(
            for: globalRule.output[0],
            matching: globalRule,
            incoming: [.shift]
        )
        suite.expect(preserved == [.shift],
                     "single-key remaps carry input modifiers to their output")
        suite.expect(KeyboardRemappingConfig.outputModifiers(
            for: commandRule.output[0],
            matching: commandRule,
            incoming: [.command]
        ) == [.command],
        "shortcut remaps use the explicitly configured output modifiers")

        let disabledKeyRule = KeyboardRemappingRule(sourceKeyCode: 53)
        suite.expect(disabledKeyRule.isValid && disabledKeyRule.output.isEmpty,
                     "an empty output sequence is a valid key-disable rule")
        suite.expect(KeyboardRemappingRisk.forSourceKeyCode(Int64(kVK_Command)) == .modifier
                     && KeyboardRemappingRisk.forSourceKeyCode(Int64(kVK_Option)) == .modifier
                     && KeyboardRemappingRisk.forSourceKeyCode(Int64(kVK_Shift)) == .modifier
                     && KeyboardRemappingRisk.forSourceKeyCode(Int64(kVK_Control)) == .modifier,
                     "common modifier keys are identified as risky remapping sources")
        suite.expect(KeyboardRemappingRisk.modifierForSourceKeyCode(Int64(kVK_Command)) == .command
                     && KeyboardRemappingRisk.modifierForSourceKeyCode(Int64(kVK_RightShift)) == .shift
                     && KeyboardRemappingRisk.modifierForSourceKeyCode(Int64(kVK_RightOption)) == .option
                     && KeyboardRemappingRisk.modifierForSourceKeyCode(Int64(kVK_RightControl)) == .control,
                     "modifier source keys map to their corresponding event flags")
        suite.expect(KeyboardRemappingRisk.handles(eventType: .flagsChanged, keyCode: Int64(kVK_Command))
                     && !KeyboardRemappingRisk.handles(eventType: .flagsChanged, keyCode: Int64(kVK_ANSI_A))
                     && KeyboardRemappingRisk.handles(eventType: .keyDown, keyCode: Int64(kVK_ANSI_A)),
                     "modifier sources accept flagsChanged events without treating ordinary flag changes as keys")
        suite.expect(KeyboardRemappingRisk.forSourceKeyCode(Int64(kVK_ANSI_Q)) == .letter
                     && KeyboardRemappingRisk.forSourceKeyCode(Int64(kVK_ANSI_A)) == .letter
                     && KeyboardRemappingRisk.forSourceKeyCode(Int64(kVK_ANSI_0)) == .number
                     && KeyboardRemappingRisk.forSourceKeyCode(Int64(kVK_ANSI_1)) == .number
                     && KeyboardRemappingRisk.forSourceKeyCode(53) == nil,
                     "letter and number keys warn while ordinary non-text keys remain unflagged")
        suite.expect(KeyboardRemappingRule(sourceKeyCode: 12).sourceRisk == .letter
                     && KeyboardRemappingRule(sourceKeyCode: 55).sourceRisk == .modifier,
                     "a rule exposes the risk of its captured source key")
        let textRule = KeyboardRemappingRule(sourceKeyCode: 53, actionKind: .typeText, text: "hello")
        let linkRule = KeyboardRemappingRule(sourceKeyCode: 36, actionKind: .openLink, link: "https://example.com")
        let appRuleWithAction = KeyboardRemappingRule(sourceKeyCode: 48, actionKind: .openApp,
                                                      appBundleIdentifier: "com.example.app")
        suite.expect(textRule.isValid && linkRule.isValid && appRuleWithAction.isValid
                     && KeyboardRemappingRule(sourceKeyCode: 53, actionKind: .disabled).isValid,
                     "text, link, app-launch and disabled actions validate")
        suite.expect(!KeyboardRemappingRule(sourceKeyCode: 53, actionKind: .typeText).isValid,
                     "a text action is not active until it has content")
        suite.expect(!KeyboardRemappingRule(sourceKeyCode: 53, actionKind: .openLink,
                                            link: "file:///etc/passwd").isValid
                     && !KeyboardRemappingRule(sourceKeyCode: 53, actionKind: .openApp,
                                               appBundleIdentifier: "invalid/bundle").isValid,
                     "link actions accept only web URLs and app actions require bundle identifiers")
        let draft = KeyboardRemappingRule()
        suite.expect(!draft.isValid && draft.canPersist
                && KeyboardRemappingConfig.decode(KeyboardRemappingConfig.encode([draft])) == [draft],
                     "incomplete editor rows persist without becoming active mappings")

        let encoded = KeyboardRemappingConfig.encode([globalRule, commandRule, appRule])
        suite.expect(KeyboardRemappingConfig.decode(encoded) == [globalRule, commandRule, appRule],
                     "valid rules survive JSON persistence")
        let legacy = #"{"sourceKeyCode":53,"output":[]}"#
        let decodedLegacy = KeyboardRemappingConfig.decode("[\(legacy)]")
        suite.expect(decodedLegacy.count == 1 && decodedLegacy[0].resolvedActionKind == .disabled,
                     "pre-action rules still decode as disabled shortcuts when their output is empty")
        suite.expect(KeyboardRemappingConfig.decode(KeyboardRemappingConfig.encode([textRule, linkRule,
                                                                                     appRuleWithAction]))
                        == [textRule, linkRule, appRuleWithAction],
                     "new action types survive JSON persistence")
        suite.expect(KeyboardRemappingConfig.decode("{invalid").isEmpty,
                     "malformed stored JSON safely yields no active rules")
        suite.expect(KeyboardRemappingConfig.decode(String(repeating: "x", count: 70_000)).isEmpty,
                     "oversized stored configuration is rejected")

        var invalidKey = globalRule
        invalidKey.sourceKeyCode = 128
        suite.expect(!invalidKey.isValid,
                     "key codes outside the macOS virtual-key range are rejected")
        var invalidBundle = appRule
        invalidBundle.bundleIdentifier = "com.example/editor"
        suite.expect(!invalidBundle.isValid,
                     "bundle identifiers with path separators are rejected")
    }
}
