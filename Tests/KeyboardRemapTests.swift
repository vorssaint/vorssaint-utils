// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Carbon.HIToolbox
import CoreGraphics
import Foundation

enum KeyboardRemapTests {
    static var fullConfiguration: KeyboardRemapConfiguration {
        var config = KeyboardRemapPreset.fnLanguages.configuration
        config.shortcutRules += KeyboardRemapPreset.saferQuit.configuration.shortcutRules
        config.shortcutRules.append(.init(.init(17, .option, character: "t"), .application("com.apple.Terminal")))
        return config
    }

    static func run(_ suite: TestSuite) {
        for language in AppLanguage.allCases {
            suite.expect(KeyboardRemapStrings.isComplete(for: language), "Keyboard remap strings cover \(language.rawValue)")
        }
        suite.expect(!SettingsBackupSupport.exportKeys().contains(DefaultsKey.keyboardRemapOwnedMappings),
                     "HID ownership marker never travels in settings backups")
        suite.expect(SettingsBackupSupport.exportKeys().contains(DefaultsKey.keyboardRemapKeyRules),
                     "Keyboard remap preferences are backed up")
        let domain = "vorss.tests.keyboard-remap.\(UUID().uuidString)"
        if let defaults = UserDefaults(suiteName: domain) {
            defer { defaults.removePersistentDomain(forName: domain) }
            AppFeature.keyboardRemap.enableOnFirstInstall(in: defaults, savedValues: [:])
            suite.expect(!defaults.bool(forKey: DefaultsKey.keyboardRemapEnabled),
                         "Feature installation leaves remaps off until preview is reviewed")
        } else { suite.expect(false, "Keyboard remap test preference domain opens") }
        var state = KeyboardRemapSupport.State()
        suite.expect(KeyboardRemapConfiguration().isEmpty, "Fresh configurations start without remaps")
        var config = fullConfiguration
        func key(_ code: Int64, _ flags: CGEventFlags = [], down: Bool = true, repeatKey: Bool = false) -> KeyboardRemapSupport.Action {
            state.decide(key: code, down: down, repeatKey: repeatKey, flags: flags,
                         commandLabel: code == 12 ? "q" : (code == 17 ? "t" : nil), config: config)
        }
        suite.expect(key(12, .maskCommand) == .swallow, "Command-Q is blocked")
        suite.expect(key(12, [], down: false) == .swallow, "Blocked Q release is swallowed after Command releases")
        suite.expect(key(12, .maskAlternate) == .key(12, .maskCommand), "Option-Q sends Command-Q")
        suite.expect(key(12, [], down: false) == .key(12, .maskCommand), "Alternate quit release retains translated modifiers")
        suite.expect(key(12, [.maskCommand, .maskShift]) == .pass, "Command-Shift-Q is unchanged")
        suite.expect(key(12, [.maskCommand, .maskAlternate]) == .pass, "Command-Option-Q is unchanged")
        suite.expect(key(12) == .pass, "Typing Q is unchanged")
        suite.expect(key(0, .maskCommand) == .pass, "Other Command shortcuts are unchanged")
        suite.expect(key(17, .maskAlternate) == .application("com.apple.Terminal"), "Option-T opens Terminal")
        suite.expect(key(17, .maskAlternate, repeatKey: true) == .swallow, "Holding terminal shortcut launches only once")
        suite.expect(key(17, [], down: false) == .swallow, "Terminal release does not type T")
        let caps = KeyboardRemapSupport.capsTriggerKey
        suite.expect(key(caps) == .inputSource, "Caps Lock cycles language")
        suite.expect(key(caps, repeatKey: true) == .swallow, "Holding Caps does not keep cycling language")
        suite.expect(key(caps, [], down: false) == .swallow, "Caps language trigger release is swallowed")
        suite.expect(key(caps, .maskShift) == .capsLock, "Shift-Caps toggles actual Caps Lock")
        _ = key(caps, [], down: false)
        suite.expect(key(caps, .maskAlphaShift) == .inputSource, "Language switch still works with Caps Lock on")
        _ = key(caps, [], down: false)
        suite.expect(key(Int64(kVK_Home)) == .pass, "Home-End is unchanged before adding a navigation rule")
        config.shortcutRules.append(.init(.init(Int64(kVK_Home), .shift), .shortcut(.init(Int64(kVK_LeftArrow), [.shift, .command]))))
        suite.expect(key(Int64(kVK_Home), .maskShift) == .key(Int64(kVK_LeftArrow), [.maskShift, .maskCommand]), "Shift-Home selects to line start")
        suite.expect(key(Int64(kVK_Home), [], down: false) == .key(Int64(kVK_LeftArrow), [.maskShift, .maskCommand]), "Home release matches translated down")
        suite.expect(key(Int64(kVK_End), .maskControl) == .pass, "Control-End is unchanged")
        config.shortcutRules.removeAll { $0.source.character == "q" && $0.source.modifiers == GlobalShortcutModifiers.command.rawValue }
        suite.expect(key(12, .maskCommand) == .pass, "Disabling safe quit restores Command-Q")
        suite.expect(!fullConfiguration.keyRules.contains { $0.source == "rightCommand" },
                     "Custom routing fixture does not require a right Command mapping")
        let mappings = config.mappings
        let fn = KeyboardRemapKey.named("fn")!.usage
        let capsUsage = KeyboardRemapKey.named("capsLock")!.usage
        suite.expect(KeyboardRemapSupport.hasModifierConflict([[.init(source: fn, destination: 0x7000000E7)]], wanted: mappings),
                     "Existing macOS Fn mapping is detected before claiming active")
        suite.expect(KeyboardRemapSupport.hasModifierConflict([[.init(source: capsUsage, destination: fn)]], wanted: mappings),
                     "Existing macOS Caps mapping consumes our physical source")
        suite.expect(KeyboardRemapSupport.hasModifierConflict([[.init(source: 0x7000000E4, destination: 0xFF0100000003)]], wanted: mappings),
                     "Alternative Apple Fn usage is normalized for conflict detection")
        suite.expect(!KeyboardRemapSupport.hasModifierConflict([[.init(source: fn, destination: fn), .init(source: 0x7000000E4, destination: 0x7000000E6)]], wanted: mappings),
                     "Identity and unrelated macOS modifier mappings remain supported")
        suite.expect(mappings.count == 2, "Routing fixture uses two HID mappings")
        suite.expect(KeyboardRemapSupport.storedMappings(KeyboardRemapSupport.storage(mappings)) == mappings,
                     "Recovery marker round trips every exact mapping")
        let foreign = SuperKeyMapping(source: 0x700000004, destination: 0x700000005)
        func report(_ tables: [[SuperKeyMapping]]) -> String {
            tables.enumerated().map { index, table in
                "\(index) UserKeyMapping (\n" + table.map {
                    "{ HIDKeyboardModifierMappingSrc = \($0.source); HIDKeyboardModifierMappingDst = \($0.destination); }"
                }.joined(separator: "\n") + "\n)"
            }.joined(separator: "\n")
        }
        let hotplug = report([mappings + [foreign], [foreign]])
        suite.expect(KeyboardRemapSupport.remainingMappings(hotplug, owned: mappings) == [foreign], "Cleanup preserves unrelated mappings across hot plug")
        suite.expect(KeyboardRemapSupport.mergedMappings(hotplug, owned: mappings, wanted: mappings) == [foreign] + mappings,
                     "Repair converges only our missing mappings")
        suite.expect(KeyboardRemapSupport.mergedMappings(report([mappings]), owned: [], wanted: mappings) == nil,
                     "Do not claim another remapper's identical mappings")
        suite.expect(KeyboardRemapSupport.remainingMappings(report([[foreign], []]), owned: mappings) == nil,
                     "Do not overwrite different external tables on different keyboards")
        suite.expect(KeyboardRemapSupport.remainingMappings("invalid", owned: mappings) == nil, "Invalid report is refused")
        state.reset()
        config.keyRules.removeAll { $0.source == "capsLock" }
        config.shortcutRules.removeAll { $0.source.keyCode == Int64(kVK_CapsLock) }
        suite.expect(key(caps) == .pass, "Disabled Caps remap leaves physical F19 alone")
        var generic = KeyboardRemapConfiguration()
        generic.keyRules = [.init("rightOption", .key("rightCommand")), .init("escape", .key("delete"))]
        suite.expect(generic.validationKey == nil, "Users can choose different modifiers and ordinary keys")
        suite.expect(generic.mappings.contains(.init(source: 0x7000000E6, destination: 0x7000000E7)), "Generic modifier mappings use chosen HID keys")
        generic.shortcutRules = [.init(.init(38, [.control, .option]), .shortcut(.init(53))),
                                 .init(.init(6, [.command, .shift]), .application("com.apple.calculator"))]
        suite.expect(generic.validationKey == nil, "Generic shortcuts can send a bare key or launch a chosen app")
        state.reset()
        suite.expect(state.decide(key: 38, down: true, repeatKey: false, flags: [.maskControl, .maskAlternate], commandLabel: "j", config: generic) == .key(53, []), "Custom Control-Option-J sends Escape")
        suite.expect(state.decide(key: 38, down: false, repeatKey: false, flags: [], commandLabel: "j", config: generic) == .key(53, []), "Custom shortcut release retains chosen output")
        suite.expect(state.decide(key: 6, down: true, repeatKey: false, flags: [.maskCommand, .maskShift], commandLabel: "z", config: generic) == .application("com.apple.calculator"), "App action is independent of Terminal and Option-T")
        suite.expect(state.decide(key: 6, down: true, repeatKey: true, flags: [.maskCommand, .maskShift], commandLabel: "z", config: generic) == .swallow, "Custom application action is not repeated")
        generic.shortcutRules.append(.init(.init(38, [.control, .option]), .none))
        suite.expect(generic.validationKey == "duplicateRule", "Duplicate active shortcut sources are rejected")
        generic.shortcutRules[2].enabled = false
        suite.expect(generic.validationKey == nil, "Disabled rule alternatives may share a source")
        generic.keyRules.append(.init("escape", .inputSource))
        suite.expect(generic.validationKey == "duplicateRule", "Duplicate active physical sources are rejected")
        generic.keyRules.removeLast()
        let encodedKeys = KeyboardRemapConfiguration.encode(generic.keyRules)
        let decodedKeys: [KeyboardRemapKeyRule]? = KeyboardRemapConfiguration.decode(encodedKeys)
        suite.expect(decodedKeys == generic.keyRules, "Key rules and IDs round trip")
        let encodedShortcuts = KeyboardRemapConfiguration.encode(generic.shortcutRules)
        let decodedShortcuts: [KeyboardRemapShortcutRule]? = KeyboardRemapConfiguration.decode(encodedShortcuts)
        suite.expect(decodedShortcuts == generic.shortcutRules, "Shortcut rules, apps, and enabled choices round trip")
        generic.addSuggestion(.fnLanguages)
        suite.expect(generic.keyRules.first?.source == "rightOption", "Suggestion preserves custom key ordering")
        let count = generic.keyRules.count + generic.shortcutRules.count
        generic.addSuggestion(.fnLanguages)
        suite.expect(generic.keyRules.count + generic.shortcutRules.count == count, "Adding suggestion twice does not duplicate rules")
        var customized = KeyboardRemapConfiguration()
        customized.keyRules = [.init("fn", .key("leftControl")), .init("capsLock", .key("escape"))]
        var customQuit = KeyboardRemapShortcutRule(.init(12, .command), .shortcut(.init(53)))
        customQuit.enabled = false
        customized.shortcutRules = [customQuit]
        customized.addSuggestion(.fnLanguages)
        suite.expect(customized.keyRules.first?.target == .key("leftControl"), "Suggestion does not replace a different Fn destination")
        suite.expect(customized.shortcutRules.first == customQuit, "Suggestion preserves disabled choices")
        suite.expect(customized.shortcutRules.filter { $0.source.keyCode == 12 && $0.source.modifiers == GlobalShortcutModifiers.command.rawValue }.count == 1, "Adding a preset leaves custom quitting rules untouched")
        suite.expect(customized.validationKey == nil, "Suggestion respects existing Caps-to-Escape mapping")
        var capsOnly = KeyboardRemapConfiguration()
        capsOnly.shortcutRules = [.init(.init(Int64(kVK_CapsLock), .shift), .inputSource)]
        suite.expect(capsOnly.triggers.count == 1, "Caps shortcut alone receives a releasable trigger")
        state.reset()
        let trigger = capsOnly.triggers[0].trigger.code
        suite.expect(state.decide(key: trigger, down: true, repeatKey: false, flags: [], commandLabel: nil, config: capsOnly) == .capsLock, "A shifted-only Caps action preserves plain Caps Lock")
        _ = state.decide(key: trigger, down: false, repeatKey: false, flags: [], commandLabel: nil, config: capsOnly)
        suite.expect(state.decide(key: trigger, down: true, repeatKey: false, flags: .maskShift, commandLabel: nil, config: capsOnly) == .inputSource, "Caps shifted action is configurable")
        var tooMany = KeyboardRemapConfiguration()
        tooMany.keyRules = Array(KeyboardRemapKey.all.prefix(8)).map { .init($0.id, .inputSource) }
        suite.expect(tooMany.validationKey == "tooManyActions", "Reject exhaustion of reserved trigger keys")
        var functionAction = KeyboardRemapConfiguration()
        functionAction.keyRules = [.init("f19", .application("com.apple.calculator"))]
        suite.expect(functionAction.validationKey == nil && functionAction.triggers.first?.trigger.id == "f20",
                     "Action trigger allocation avoids a user's physical F19 action")
        functionAction.keyRules = KeyboardRemapConfiguration.triggerKeys.map { .init($0.id, .key("escape")) }
        functionAction.keyRules.append(.init("capsLock", .inputSource))
        suite.expect(functionAction.validationKey == "reservedKey", "No available internal trigger is refused before changing keys")
        for preset in KeyboardRemapPreset.allCases {
            let suggestion = preset.configuration
            suite.expect(suggestion.validationKey == nil, "Every preset is independently valid: \(preset.id)")
            suite.expect(!suggestion.keyRules.contains { $0.source == "rightCommand" }, "No preset includes a Latvian-specific right Command rule")
            suite.expect(preset == .saferQuit || !suggestion.shortcutRules.contains { $0.source.character == "q" || $0.source.character == "t" },
                         "Only the explicit safer-quitting preset changes quitting shortcuts")
            for language in AppLanguage.allCases {
                suite.expect(KeyboardRemapStrings.text(preset.titleKey, language: language) != preset.titleKey
                    && KeyboardRemapStrings.text(preset.noteKey, language: language) != preset.noteKey,
                    "Every preset has localized name and explanation")
            }
            var merged = KeyboardRemapConfiguration()
            merged.addSuggestion(preset)
            let first = merged
            merged.addSuggestion(preset)
            suite.expect(merged == first, "Every preset preserves IDs and ordering on repeated additions")
        }
        suite.expect(KeyboardRemapPreset.capsEscape.configuration.keyRules.first?.target == .key("escape"), "Editor preset moves Escape to Caps Lock")
        suite.expect(KeyboardRemapPreset.capsControl.configuration.keyRules.first?.target == .key("leftControl"), "Terminal preset moves Control to Caps Lock")
        let navigation = KeyboardRemapPreset.lineNavigation.configuration
        state.reset()
        suite.expect(state.decide(key: Int64(kVK_Home), down: true, repeatKey: false, flags: [], commandLabel: nil, config: navigation)
                     == .key(Int64(kVK_LeftArrow), .maskCommand), "Home preset moves to line start")
        _ = state.decide(key: Int64(kVK_Home), down: false, repeatKey: false, flags: [], commandLabel: nil, config: navigation)
        suite.expect(state.decide(key: Int64(kVK_End), down: true, repeatKey: false, flags: .maskShift, commandLabel: nil, config: navigation)
                     == .key(Int64(kVK_RightArrow), [.maskCommand, .maskShift]), "Shift-End preset selects to line end")
        let safeQuit = KeyboardRemapPreset.saferQuit.configuration
        state.reset()
        suite.expect(state.decide(key: 12, down: true, repeatKey: false, flags: .maskCommand, commandLabel: "q", config: safeQuit) == .swallow,
                     "Safer quitting blocks Command-Q")
        _ = state.decide(key: 12, down: false, repeatKey: false, flags: [], commandLabel: "q", config: safeQuit)
        suite.expect(state.decide(key: 12, down: true, repeatKey: false, flags: .maskAlternate, commandLabel: "q", config: safeQuit) == .key(12, .maskCommand),
                     "Safer quitting sends Command-Q from Option-Q")
        suite.expect(KeyboardRemapChord(Int64(kVK_Home)).readableLabel == "Home", "Preview spells out Home instead of its arrow glyph")
        suite.expect(KeyboardRemapChord(Int64(kVK_LeftArrow), [.command, .shift]).readableLabel == "Shift + Command + Left Arrow",
                     "Preview spells out shortcut names with separators")
        let savedDomain = "vorss.tests.keyboard-remap.\(UUID().uuidString)"
        if let defaults = UserDefaults(suiteName: savedDomain) {
            defer { defaults.removePersistentDomain(forName: savedDomain) }
            defaults.register(defaults: Defaults.registeredDefaults)
            suite.expect(KeyboardRemapConfiguration(defaults: defaults).isEmpty, "New users receive no suggested rules")
            suite.expect(!defaults.bool(forKey: DefaultsKey.keyboardRemapEnabled), "New users start with remapping disabled")
            generic.save(to: defaults)
            suite.expect(KeyboardRemapConfiguration(defaults: defaults) == generic, "Saved custom rules preserve enabled choices and ordering")
        }
    }
}
