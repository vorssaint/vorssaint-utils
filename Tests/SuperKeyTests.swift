// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import CoreGraphics
import Foundation

enum SuperKeyTests {
    static func run(expect: (Bool, String) -> Void) {
        // MARK: Super key (issue #330)

        expect(Defaults.registeredDefaults[DefaultsKey.superKeyEnabled] as? Bool == false,
               "the super key ships off by default")
        expect(Defaults.registeredDefaults[DefaultsKey.superKeySource] as? String
                == SuperKeySource.capsLock.rawValue,
               "the super key keeps Caps Lock as its default source")
        expect(Defaults.registeredDefaults[DefaultsKey.superKeyModifiers] as? String
                == SuperKeySupport.defaultModifierStorageValue,
               "the super key starts with all four modifiers")
        expect(Defaults.registeredDefaults[DefaultsKey.superKeySoloAction] as? String
                == SuperKeySoloAction.none.rawValue,
               "a tap on its own does nothing until the user picks something")
        expect(Defaults.registeredDefaults[DefaultsKey.panelControlSuperKey] as? Bool == true,
               "the super key panel row ships visible like its siblings")
        expect(Defaults.registeredDefaults[DefaultsKey.superKeyMappingApplied] == nil
                && Defaults.registeredDefaults[DefaultsKey.superKeyMappedSource] == nil,
               "mapping recovery state is never registered or backed up")
        expect(!SettingsBackupSupport.exportKeys().contains(DefaultsKey.superKeyMappingApplied)
                && !SettingsBackupSupport.exportKeys().contains(DefaultsKey.superKeyMappedSource)
                && SettingsBackupSupport.exportKeys().contains(DefaultsKey.superKeyEnabled)
                && SettingsBackupSupport.exportKeys().contains(DefaultsKey.superKeySource)
                && SettingsBackupSupport.exportKeys().contains(DefaultsKey.superKeyModifiers)
                && SettingsBackupSupport.exportKeys().contains(DefaultsKey.superKeySoloAction),
               "the Super key preferences travel in a backup, the mapping state stays behind")
        expect(AppFeature.superKey.enabledKeys == [DefaultsKey.superKeyEnabled]
                && AppFeature.superKey.permissions == [.accessibility]
                && AppFeature.superKey.group == .mouseKeyboard
                && AppFeature.superKey.energyProfile == .keyboard,
               "the hub knows the super key's switch and native input switching needs no Automation")
        expect(FeatureVisibilitySupport.features(for: .superKey) == [.superKey]
                && !FeatureVisibilitySupport.isPageVisible(.superKey, isAvailable: { _ in false }),
               "the page leaves the sidebar when the feature is off in the hub")
        expect(SuperKeySoloAction.sanitized("escape") == .escape
                && SuperKeySoloAction.sanitized("capsLock") == .capsLock
                && SuperKeySoloAction.sanitized("inputSource") == .inputSource
                && SuperKeySoloAction.sanitized("nonsense") == SuperKeySoloAction.none
                && SuperKeySoloAction.sanitized(nil) == SuperKeySoloAction.none,
               "a stored solo action is trusted only when the app still knows it")
        expect(SuperKeySource.sanitized("rightCommand") == .rightCommand
                && SuperKeySource.sanitized("nonsense") == .capsLock
                && SuperKeySource.sanitized(nil) == .capsLock
                && SuperKeySource.capsLock.usage == 0x700000039
                && SuperKeySource.rightControl.usage == 0x7000000E4
                && SuperKeySource.rightShift.usage == 0x7000000E5
                && SuperKeySource.rightOption.usage == 0x7000000E6
                && SuperKeySource.rightCommand.usage == 0x7000000E7
                && Set(SuperKeySource.allCases.map(\.usage)).count == SuperKeySource.allCases.count
                && Set(SuperKeySource.allCases.map(\.keyCode)).count == SuperKeySource.allCases.count,
               "stored sources are validated and each supported key has distinct HID data")
        expect(SuperKeySource.capsLock.systemImage == "capslock"
                && SuperKeySource.rightCommand.systemImage == "command"
                && SuperKeySource.rightOption.systemImage == "option"
                && SuperKeySource.rightControl.systemImage == "control"
                && SuperKeySource.rightShift.systemImage == "shift",
               "each super key source has a matching system image")
        expect(SuperKeySupport.modifiers(from: "control+option+command")
                == [.control, .option, .command]
                && SuperKeySupport.modifiers(from: "shift") == .validMask
                && SuperKeySupport.modifiers(from: "control+") == .validMask
                && SuperKeySupport.modifiers(from: "") == .validMask
                && SuperKeySupport.modifiers(from: "invalid") == .validMask
                && SuperKeySupport.modifiers(from: nil) == .validMask,
               "stored Super key modifiers require a shortcut modifier or use the default")
        expect(SuperKeySupport.storageValue(for: [.control, .option, .command])
                == "control+option+command"
                && SuperKeySupport.storageValue(for: [])
                    == SuperKeySupport.defaultModifierStorageValue,
               "Super key modifiers keep stable storage and never save an empty combination")
        expect(SuperKeySupport.soloEffect(action: .none,
                                          longHold: false,
                                          repeated: false) == .none
                && SuperKeySupport.soloEffect(action: .escape,
                                              longHold: false,
                                              repeated: false) == .escape
                && SuperKeySupport.soloEffect(action: .escape,
                                              longHold: true,
                                              repeated: true) == .none
                && SuperKeySupport.soloEffect(action: .capsLock,
                                              longHold: true,
                                              repeated: false) == .capsLock
                && SuperKeySupport.soloEffect(action: .capsLock,
                                              longHold: false,
                                              repeated: true) == .none,
               "existing solo actions keep their tap, hold and repeat behavior")
        expect(SuperKeySupport.soloEffect(action: .inputSource,
                                          longHold: false,
                                          repeated: false) == .inputSource
                && SuperKeySupport.soloEffect(action: .inputSource,
                                              longHold: false,
                                              repeated: true) == .inputSource
                && SuperKeySupport.soloEffect(action: .inputSource,
                                              longHold: true,
                                              repeated: false) == .capsLock
                && SuperKeySupport.soloEffect(action: .inputSource,
                                              longHold: true,
                                              repeated: true) == .capsLock,
               "the input-source action switches on a quick press and reserves a hold for Caps Lock")
        expect(SuperKeySupport.nextInputSourceID(currentID: "abc",
                                                 enabledIDs: ["abc", "pinyin", "kana"]) == "pinyin"
                && SuperKeySupport.nextInputSourceID(currentID: "kana",
                                                     enabledIDs: ["abc", "pinyin", "kana"]) == "abc"
                && SuperKeySupport.nextInputSourceID(currentID: "missing",
                                                     enabledIDs: ["abc", "pinyin"]) == "abc"
                && SuperKeySupport.nextInputSourceID(currentID: nil,
                                                     enabledIDs: ["abc"]) == nil,
               "input sources cycle through the enabled system list without a hard-coded shortcut")

        let capsMapping = SuperKeyMapping(source: SuperKeySource.capsLock.usage,
                                          destination: SuperKeySupport.triggerUsage)
        let rightCommandMapping = SuperKeyMapping(source: SuperKeySource.rightCommand.usage,
                                                  destination: SuperKeySupport.triggerUsage)
        let foreignMapping = SuperKeyMapping(source: 0x700000064, destination: 0x700000035)
        expect(SuperKeySupport.mappings(enablingSuperKey: true, existing: []) == [capsMapping],
               "turning the key on maps caps lock to the key it arrives as")
        expect(SuperKeySupport.mappings(enablingSuperKey: true, existing: [foreignMapping])
                == [capsMapping, foreignMapping],
               "a mapping the user set up elsewhere survives turning the feature on")
        expect(SuperKeySupport.mappings(enablingSuperKey: true,
                                        existing: [capsMapping, foreignMapping],
                                        source: .rightCommand,
                                        ownedSource: .capsLock)
                == [rightCommandMapping, foreignMapping],
               "changing sources removes the old owned mapping before adding the new one")
        expect(SuperKeySupport.mappings(enablingSuperKey: false,
                                        existing: [capsMapping, foreignMapping],
                                        ownedSource: .capsLock)
                == [foreignMapping],
               "turning it off removes only the entry this feature owns")
        let foreignCapsMapping = SuperKeyMapping(source: SuperKeySource.capsLock.usage,
                                                 destination: 0x700000029)
        let foreignRightCommandMapping = SuperKeyMapping(source: SuperKeySource.rightCommand.usage,
                                                         destination: 0x700000029)
        expect(SuperKeySupport.hasMappingConflict(in: [foreignCapsMapping])
                && SuperKeySupport.mappings(enablingSuperKey: true,
                                            existing: [foreignCapsMapping]) == [foreignCapsMapping]
                && SuperKeySupport.mappings(enablingSuperKey: false,
                                            existing: [foreignCapsMapping]) == [foreignCapsMapping],
               "an existing Caps Lock mapping is refused and preserved in both directions")
        expect(SuperKeySupport.hasMappingConflict(in: [foreignRightCommandMapping],
                                                  source: .rightCommand),
               "an existing mapping on a selected right-side source blocks activation")
        expect(SuperKeySupport.hasMappingConflict(in: [capsMapping])
                && !SuperKeySupport.hasMappingConflict(in: [capsMapping],
                                                       ownedSource: .capsLock)
                && SuperKeySupport.mappings(enablingSuperKey: true,
                                            existing: [capsMapping]) == [capsMapping],
               "an identical external Caps Lock mapping is not claimed without ownership proof")
        expect(SuperKeySupport.mappingArgument([capsMapping])
                == "{\"UserKeyMapping\":[{\"HIDKeyboardModifierMappingSrc\":30064771129,\"HIDKeyboardModifierMappingDst\":30064771181}]}",
               "the mapping table goes out in the form the system takes")
        expect(SuperKeySupport.mappingArgument([]) == "{\"UserKeyMapping\":[]}",
               "an empty table clears the mapping")
        expect(SuperKeySupport.mappingsMatch([capsMapping, foreignMapping],
                                             [foreignMapping, capsMapping])
                && !SuperKeySupport.mappingsMatch([capsMapping], [foreignMapping]),
               "mapping readback compares the complete table without depending on its order")
        expect(SuperKeySupport.mappingMarkerAfterClear(previous: true,
                                                       readbackConfirmed: false)
                && !SuperKeySupport.mappingMarkerAfterClear(previous: true,
                                                            readbackConfirmed: true)
                && !SuperKeySupport.mappingMarkerAfterClear(previous: false,
                                                            readbackConfirmed: false),
               "only confirmed clear readback removes the write-ahead mapping marker")
        expect(SuperKeySupport.mappingRequestIsAuthorized(
            requestGeneration: 4,
            currentGeneration: 4,
            tapIsCurrent: true,
            stopping: false
        )
                && !SuperKeySupport.mappingRequestIsAuthorized(
                    requestGeneration: 4,
                    currentGeneration: 5,
                    tapIsCurrent: true,
                    stopping: false
                )
                && !SuperKeySupport.mappingRequestIsAuthorized(
                    requestGeneration: 4,
                    currentGeneration: 4,
                    tapIsCurrent: false,
                    stopping: false
                ),
               "a stop or replaced event tap invalidates a queued Super key mapping")
        expect(SuperKeyMappingGuard.cleanupSource(in: [
            "Vorssaint", SuperKeyMappingGuard.cleanupArgument, "capsLock",
        ]) == .capsLock
                && SuperKeyMappingGuard.cleanupSource(in: [
                    "Vorssaint", SuperKeyMappingGuard.cleanupArgument, "rightCommand",
                ]) == .rightCommand
                && SuperKeyMappingGuard.cleanupSource(in: [
                    "Vorssaint", SuperKeyMappingGuard.cleanupArgument, "invalid",
                ]) == nil,
               "the crash guard accepts only a real Super key source")

        let mappingReport = """
        RegistryID  Key                   Value
        100000a84   UserKeyMapping   (
                {
                HIDKeyboardModifierMappingDst = 30064771181;
                HIDKeyboardModifierMappingSrc = 30064771129;
            }
        )
        100000a85   UserKeyMapping   (
                {
                HIDKeyboardModifierMappingDst = 30064771181;
                HIDKeyboardModifierMappingSrc = 30064771129;
            }
        )
        """
        expect(SuperKeySupport.parseMappings(mappingReport) == [capsMapping],
               "the same entry on two keyboards is read once")
        expect(SuperKeySupport.mappingReportConfirms(mappingReport, expected: [capsMapping]),
               "mapping readback confirms the requested table on every keyboard")
        let partiallyMappedReport = mappingReport + """

        100000a86   UserKeyMapping   (
        )
        """
        expect(!SuperKeySupport.mappingReportConfirms(partiallyMappedReport,
                                                      expected: [capsMapping])
                && !SuperKeySupport.mappingReportConfirms("", expected: []),
               "one unmapped keyboard or a missing readback cannot confirm a global write")
        expect(SuperKeySupport.parseMappings("RegistryID  Key  Value\n100000a84 UserKeyMapping (null)").isEmpty
                && SuperKeySupport.parseMappings("").isEmpty,
               "a keyboard with no mapping reads as none")
        let heterogeneousUserMappingReport = """
        RegistryID  Key                   Value
        100000a84   UserKeyMapping   (
                {
                HIDKeyboardModifierMappingDst = 30064771125;
                HIDKeyboardModifierMappingSrc = 30064771172;
            }
        )
        100000a85   UserKeyMapping   (
        )
        """
        expect(SuperKeySupport.consistentMappings(
            heterogeneousUserMappingReport,
            property: SuperKeySupport.userMappingProperty
        ) == nil, "device-specific key mappings are never copied onto every keyboard")
        let ownedDifferenceReport = """
        RegistryID  Key                   Value
        100000a84   UserKeyMapping   (
                {
                HIDKeyboardModifierMappingDst = 30064771181;
                HIDKeyboardModifierMappingSrc = 30064771129;
            }
                {
                HIDKeyboardModifierMappingDst = 30064771125;
                HIDKeyboardModifierMappingSrc = 30064771172;
            }
        )
        100000a85   UserKeyMapping   (
                {
                HIDKeyboardModifierMappingDst = 30064771125;
                HIDKeyboardModifierMappingSrc = 30064771172;
            }
        )
        """
        expect(SuperKeySupport.consistentMappings(
            ownedDifferenceReport,
            property: SuperKeySupport.userMappingProperty,
            ownedSource: .capsLock
        ) == [foreignMapping], "a newly connected keyboard can converge when only the owned mapping differs")
        expect(SuperKeyMappingGuard.mappingsAfterCleanup(
            ownedDifferenceReport,
            source: .capsLock
        ) == [foreignMapping],
               "the crash guard removes only the mapping owned by the Super key")

        let noActionReport = """
        HIDKeyboardModifierMappingPairs = {
          HIDKeyboardModifierMappingSrc = 30064771129;
          HIDKeyboardModifierMappingDst = "-1";
        }
        """
        expect(SuperKeySupport.parseMappings(noActionReport)
                == [SuperKeyMapping(source: SuperKeySource.capsLock.usage,
                                    destination: UInt64.max)],
               "hidutil's signed no-action value keeps its unsigned HID meaning")
        // The page is the only place a refused mapping is visible, so the
        // reason has to reach it and be spelled out there.
        let superKeySettingsSource = (try? String(
            contentsOfFile: "Sources/Vorssaint/UI/Settings/SuperKeySettings.swift",
            encoding: .utf8)) ?? ""
        let failureMark = superKeySettingsSource.range(of: "superKey.mappingFailure")
        let runningMark = superKeySettingsSource.range(of: "superKey.isRunning")
        expect(failureMark != nil && runningMark != nil
                && failureMark!.lowerBound < runningMark!.lowerBound
                && superKeySettingsSource.contains("text.mappingFailure(failure)"),
               "the Super key page names a refused mapping ahead of the working state")

        var superKeyState = SuperKeySupport.State()
        expect(superKeyState.decide(.otherKey) == .pass,
               "with the key up, typing is untouched")
        expect(superKeyState.decide(.triggerDown(
            isRepeat: false, hasPrimaryModifiers: false, timestamp: 0
        )) == .swallow,
               "the key itself never reaches an app")
        expect(superKeyState.isHeld
                && superKeyState.decide(.otherKey) == .addModifiers
                && superKeyState.decide(.otherKey) == .addModifiers,
               "every key pressed while it is held carries the configured modifiers")
        expect(superKeyState.decide(.triggerUp(timestamp: 1)) == .swallow && !superKeyState.isHeld,
               "releasing after a combination does nothing on its own")

        // What the watchdog leans on: a press whose release never arrived is
        // let go of, and typing goes back to normal without the key being
        // touched again.
        var lostReleaseState = SuperKeySupport.State()
        _ = lostReleaseState.decide(.triggerDown(
            isRepeat: false, hasPrimaryModifiers: false, timestamp: 0
        ))
        expect(lostReleaseState.decide(.otherKey) == .addModifiers,
               "a press with no release still carries the modifiers while it stands")
        lostReleaseState.reset()
        expect(lostReleaseState.decide(.otherKey) == .pass,
               "letting go of a press whose release was lost gives typing back")
        expect(lostReleaseState.decide(.triggerUp(timestamp: 1)) == .swallow,
               "a release arriving after the press was let go does nothing")

        var soloState = SuperKeySupport.State()
        _ = soloState.decide(.triggerDown(
            isRepeat: false, hasPrimaryModifiers: false, timestamp: 1_000_000_000
        ))
        expect(soloState.decide(.triggerUp(timestamp: 1_499_999_999)) == .soloTap(repeated: false),
               "a quick no-repeat press is the solo tap")
        _ = soloState.decide(.triggerDown(
            isRepeat: false, hasPrimaryModifiers: false, timestamp: 2_000_000_000
        ))
        expect(soloState.decide(.triggerDown(
            isRepeat: true, hasPrimaryModifiers: false, timestamp: 2_100_000_000
        )) == .swallow
                && soloState.decide(.triggerUp(timestamp: 2_500_000_000)) == .soloHold(repeated: true),
               "a repeated press held long enough is a repeated solo hold")
        _ = soloState.decide(.triggerDown(
            isRepeat: false, hasPrimaryModifiers: false, timestamp: 3_000_000_000
        ))
        _ = soloState.decide(.otherModifier)
        expect(soloState.decide(.triggerUp(timestamp: 4_000_000_000)) == .swallow,
               "holding it together with another modifier is not a tap either")

        // Drag chords read their modifiers off the mouse-down, not off any
        // keyboard event (#888), so the service must classify mouse presses
        // like other keys and stamp them from a tap at the HID stage — the
        // one place guaranteed to run before every session tap that reads
        // the flags. The service file is not in this binary; pin the shape.
        let superKeyServiceSource = (try? String(
            contentsOfFile: "Sources/Vorssaint/Services/SuperKey/SuperKeyService.swift",
            encoding: .utf8)) ?? ""
        let superKeyServiceCode = superKeyServiceSource
            .split(separator: "\n", omittingEmptySubsequences: false)
            .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }
            .joined(separator: "\n")
        expect(superKeyServiceCode.contains(".leftMouseDown, .rightMouseDown, .otherMouseDown")
               && superKeyServiceCode.contains("mouseDownTypes.reduce(CGEventMask(0))")
               && superKeyServiceCode.contains("mouseDownTypes.contains(type) { return .otherKey }")
               && superKeyServiceCode.range(of: "tap: .cghidEventTap") != nil,
               "every mouse press while the super key is held carries the modifiers, stamped at the HID stage")
        // A mouse event carries no keycode of its own: the field reads back as
        // 0 on one, which is the keycode for A. The read lives inside classify,
        // below the line that answers the mouse types, so no caller holds a
        // phantom key it could hand to something that looks keys up.
        let keycodeReads = superKeyServiceCode
            .components(separatedBy: ".keyboardEventKeycode").count - 1
        let mouseAnswer = superKeyServiceCode.range(of: "mouseDownTypes.contains(type)")?.lowerBound
        let keycodeRead = superKeyServiceCode.range(of: ".keyboardEventKeycode")?.lowerBound
        expect(keycodeReads == 1
               && mouseAnswer.flatMap({ answer in keycodeRead.map { answer < $0 } }) == true,
               "a mouse press is answered before the super key ever reads a keycode")
        // A refused mouse tap counts as dead so the health check rebuilds it,
        // but exactly once: the rebuild takes the healthy keyboard tap down
        // with it, and a system that refuses refuses the retry too, so an
        // unbounded flag would hiccup super-key input at whatever rate
        // syncWithPreferences fires. The count has to outlive the teardown its
        // own value asked for, so the only place it is put back to zero is its
        // own declaration — never the tap thread's reset block, which the
        // rebuild runs and which would start the loop over.
        let refusalResets = superKeyServiceCode
            .components(separatedBy: "mouseTapRefusals = 0").count - 1
        expect(superKeyServiceCode.contains("?? (mouseTapRefusals == 1)")
               && superKeyServiceCode.contains(
                   "mouseTapRefusals = mouseTap == nil ? self.mouseTapRefusals + 1 : 0")
               && refusalResets == 1,
               "a refused mouse tap is worth one rebuild, and the count survives it")

        var noRepeatHoldState = SuperKeySupport.State()
        _ = noRepeatHoldState.decide(.triggerDown(
            isRepeat: false, hasPrimaryModifiers: false, timestamp: 6_000_000_000
        ))
        expect(noRepeatHoldState.decide(.triggerUp(timestamp: 6_500_000_000)) == .soloHold(repeated: false),
               "a no-repeat press at the hold threshold is a solo hold")

        var fastRepeatState = SuperKeySupport.State()
        _ = fastRepeatState.decide(.triggerDown(
            isRepeat: false, hasPrimaryModifiers: false, timestamp: 8_000_000_000
        ))
        expect(fastRepeatState.decide(.triggerDown(
            isRepeat: true, hasPrimaryModifiers: false, timestamp: 8_100_000_000
        )) == .swallow
                && fastRepeatState.decide(.triggerUp(timestamp: 8_499_999_999)) == .soloTap(repeated: true),
               "a fast repeat remains a quick press and records the repeat")

        var preheldModifierState = SuperKeySupport.State()
        _ = preheldModifierState.decide(.triggerDown(
            isRepeat: false, hasPrimaryModifiers: true, timestamp: 7_000_000_000
        ))
        expect(preheldModifierState.isHeld
                && !preheldModifierState.isAlone
                && preheldModifierState.decide(.triggerUp(timestamp: 7_500_000_000)) == .swallow,
               "a pre-held modifier cancels solo action while keeping Superkey held")

        var resetSoloState = SuperKeySupport.State()
        _ = resetSoloState.decide(.triggerDown(
            isRepeat: false, hasPrimaryModifiers: false, timestamp: 0
        ))
        _ = resetSoloState.decide(.triggerDown(
            isRepeat: true, hasPrimaryModifiers: false, timestamp: 1
        ))
        resetSoloState.reset()
        _ = resetSoloState.decide(.triggerDown(
            isRepeat: false, hasPrimaryModifiers: false, timestamp: 5_000_000_000
        ))
        expect(resetSoloState.decide(.triggerUp(timestamp: 5_499_999_999)) == .soloTap(repeated: false),
               "reset clears the previous press timestamp and repeat state")

        var lateRepeatState = SuperKeySupport.State()
        _ = lateRepeatState.decide(.triggerDown(
            isRepeat: false, hasPrimaryModifiers: false, timestamp: 0
        ))
        lateRepeatState.reset()
        expect(lateRepeatState.decide(.triggerDown(
            isRepeat: true, hasPrimaryModifiers: false, timestamp: 1_000_000_000
        )) == .swallow
                && !lateRepeatState.isHeld
                && lateRepeatState.decide(.triggerUp(timestamp: 1_500_000_000)) == .swallow,
               "a repeat after reset cannot revive a solo press")

        var strandedState = SuperKeySupport.State()
        _ = strandedState.decide(.triggerDown(
            isRepeat: false, hasPrimaryModifiers: false, timestamp: 0
        ))
        strandedState.reset()
        expect(strandedState.decide(.otherKey) == .pass,
               "a key held while the tap goes away cannot leave typing stuck in modifiers")
        var unmappedKeyboardState = SuperKeySupport.State()
        expect(unmappedKeyboardState.decide(.sourceKey) == .interceptAndRemap,
               "a raw source key is intercepted while that keyboard's mapping is repaired")
    }
}
