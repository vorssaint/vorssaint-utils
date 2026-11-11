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
import SwiftUI
import VMStatisticsCompat

enum QuickToolFeatureTests {
    static func run(_ suite: TestSuite) {
        let registrationDomain = UserDefaults.standard.volatileDomain(
            forName: UserDefaults.registrationDomain)
        defer {
            UserDefaults.standard.setVolatileDomain(registrationDomain,
                                                    forName: UserDefaults.registrationDomain)
        }

        var linkEvents: [String] = []
        linkEvents.removeAll()
        let uploadDefaultsName = "com.vorssaint.tests.screenshot-upload.\(UUID().uuidString)"
        let uploadDefaults = UserDefaults(suiteName: uploadDefaultsName)!
        defer { uploadDefaults.removePersistentDomain(forName: uploadDefaultsName) }
        var unmatchedScrollPixels = [UInt8](repeating: 0, count: 16 * 120)
        for index in unmatchedScrollPixels.indices {
            unmatchedScrollPixels[index] = UInt8((index * 47 + index / 11) % 253)
        }
        var patternParts = DateComponents()
        patternParts.year = 2026
        patternParts.month = 7
        patternParts.day = 24
        patternParts.hour = 15
        patternParts.minute = 4
        patternParts.second = 9
        let focusDefaultsDomain = "com.vorssaint.tests.screenshot-preview-focus.\(UUID().uuidString)"
        let focusDefaults = UserDefaults(suiteName: focusDefaultsDomain)!
        defer { focusDefaults.removePersistentDomain(forName: focusDefaultsDomain) }
        // The decision route makes after the action ran, read from settings.
        let routeDefaultsDomain = "com.vorssaint.tests.screenshot-preview-route.\(UUID().uuidString)"
        let routeDefaults = UserDefaults(suiteName: routeDefaultsDomain)!
        defer { routeDefaults.removePersistentDomain(forName: routeDefaultsDomain) }
        let captureMenuSuite = "com.vorssaint.tests.capture-menu.\(UUID().uuidString)"
        let captureMenuDefaults = UserDefaults(suiteName: captureMenuSuite)!
        defer { captureMenuDefaults.removePersistentDomain(forName: captureMenuSuite) }
        captureMenuDefaults.register(defaults: Defaults.registeredDefaults)
        // A menu row says where the command lives. Every Mac app has a menu
        // named after itself, so the app menu read its own name twice.
        suite.expect(CommandBarMenuPath.crumb(appName: "Notes", path: ["Notes"]) == "Notes",
               "the app menu does not say the app name twice")
        suite.expect(CommandBarMenuPath.crumb(appName: "Notes", path: ["File", "Export"])
                == "Notes \u{203A} File \u{203A} Export",
               "a real trail keeps every step")
        suite.expect(CommandBarMenuPath.crumb(appName: "Notes", path: []) == "Notes",
               "a command straight off the app names only the app")
        suite.expect(CommandBarMenuPath.crumb(appName: "Notes", path: ["", "View"])
                == "Notes \u{203A} View",
               "an empty step leaves no dangling separator")
        let capture = CGSize(width: 1920, height: 1080)
        let retinaContext = CGContext(data: nil, width: 8, height: 6, bitsPerComponent: 8,
                                      bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        retinaContext?.setFillColor(CGColor(gray: 0.5, alpha: 1))
        retinaContext?.fill(CGRect(x: 0, y: 0, width: 8, height: 6))
        let retinaCapture = retinaContext?.makeImage()
        suite.expect(retinaCapture != nil, "a Retina test capture can be drawn")
        let captureShelfSuite = "com.vorssaint.tests.capture-shelf.\(UUID().uuidString)"
        let captureShelfDefaults = UserDefaults(suiteName: captureShelfSuite)!
        defer { captureShelfDefaults.removePersistentDomain(forName: captureShelfSuite) }
        suite.expect(Defaults.registeredDefaults[DefaultsKey.panelUtilityScreenshot] as? Bool == true,
               "the panel row ships visible like its siblings")
        suite.expect(Defaults.registeredDefaults[DefaultsKey.cameraPreviewShortcutEnabled] as? Bool == false,
               "the camera preview shortcut ships off like the other quick tools")
        suite.expect(Defaults.registeredDefaults[DefaultsKey.cameraPreviewShortcut] as? String
                == "control+option+command:13",
               "the default camera preview shortcut is control option command W")
        suite.expect(Defaults.registeredDefaults[DefaultsKey.panelUtilityCameraPreview] as? Bool == true,
               "the camera preview panel row ships visible like its siblings")
        suite.expect(GlobalShortcutRole.cameraPreview.requiredEnableKeys == [DefaultsKey.cameraPreviewShortcutEnabled]
                && GlobalShortcutRole.cameraPreview.feature == .cameraPreview,
               "the camera preview shortcut role gates on its toggle and feature")

        suite.expect(Defaults.registeredDefaults[DefaultsKey.scratchpadShortcutEnabled] as? Bool == false,
               "the scratchpad shortcut ships off like the other quick tools")
        suite.expect(Defaults.registeredDefaults[DefaultsKey.scratchpadShortcut] as? String
                == "control+option+command:45",
               "the default scratchpad shortcut is control option command N")
        suite.expect(Defaults.registeredDefaults[DefaultsKey.panelUtilityScratchpad] as? Bool == true,
               "the scratchpad panel row ships visible like its siblings")
        suite.expect(Defaults.registeredDefaults[DefaultsKey.scratchpadRetention] as? String == "never",
               "the scratchpad keeps text until cleared by default")
        suite.expect(Defaults.registeredDefaults[DefaultsKey.scratchpadCloseOnClickOutside] as? Bool == true,
               "a click outside puts the scratchpad away unless the user keeps it floating")
        suite.expect(SettingsBackupSupport.exportKeys().contains(DefaultsKey.scratchpadCloseOnClickOutside),
               "the scratchpad dismissal choice travels with the settings backup")
        suite.expect(GlobalShortcutRole.scratchpad.requiredEnableKeys == [DefaultsKey.scratchpadShortcutEnabled]
                && GlobalShortcutRole.scratchpad.feature == .scratchpad,
               "the scratchpad shortcut role gates on its toggle and feature")
        let scratchpadViewSource = (try? String(
            contentsOfFile: "Sources/Vorssaint/UI/Scratchpad/ScratchpadView.swift",
            encoding: .utf8)) ?? ""
        let scratchpadHitTargetContracts = [
            "Image(systemName: \"plus\")\n                    .font(.system(size: 12, weight: .semibold))\n                    .frame(width: 22, height: 22)\n                    .contentShape(Rectangle())",
            "Image(systemName: \"ellipsis\")\n                    .font(.system(size: 12, weight: .semibold))\n                    .frame(width: 22, height: 22)\n                    .contentShape(Rectangle())",
            ".fill(selected ? Color.accentColor.opacity(0.16) : Color.clear)\n                }\n                .contentShape(RoundedRectangle(cornerRadius: 6, style: .continuous))",
            "Image(systemName: service.isPinned ? \"pin.fill\" : \"pin\")\n                    .font(.system(size: 12, weight: .semibold))\n                    .frame(width: 22, height: 22)\n                    .contentShape(Rectangle())",
            "Image(systemName: \"xmark.circle.fill\")\n                    .font(.system(size: 14))\n                    .foregroundStyle(.secondary)\n                    .frame(width: 22, height: 22)\n                    .contentShape(Rectangle())",
        ]
        suite.expect(scratchpadHitTargetContracts.allSatisfy { scratchpadViewSource.contains($0) },
               "the scratchpad tab bar and header controls keep their full padded hit targets")
        // The island's toggle runs in NotchCompactTests; the floating pad hands
        // its checkboxes to the same service method, which edits through the
        // registered text view.
        suite.expect(scratchpadViewSource.contains("onToggleTask: { service.toggleTask(box: $0) }"),
               "the floating pad's checkboxes edit through the service, so a click is one undoable edit")
        suite.expect(ScratchpadRetention.sanitized("day") == .day
                && ScratchpadRetention.sanitized("week") == .week
                && ScratchpadRetention.sanitized("month") == .month
                && ScratchpadRetention.sanitized(nil) == .never
                && ScratchpadRetention.sanitized("yesterday") == .never,
               "scratchpad retention sanitizes to the allowed periods and falls back to never")
        suite.expect(ScratchpadRetention.never.maxIdleInterval == nil
                && ScratchpadRetention.day.maxIdleInterval == 86_400
                && ScratchpadRetention.week.maxIdleInterval == 7 * 86_400
                && ScratchpadRetention.month.maxIdleInterval == 30 * 86_400,
               "scratchpad retention periods are a day, a week and thirty days")
        suite.expect(ScratchpadSupport.dismissesOnOutsideClick(isPinned: false, exportModalActive: false)
                && !ScratchpadSupport.dismissesOnOutsideClick(isPinned: true, exportModalActive: false)
                && !ScratchpadSupport.dismissesOnOutsideClick(isPinned: false, exportModalActive: true),
               "the scratchpad pin and export dialog both block outside-click dismissal")
        let markdownPreview = ScratchpadSupport.markdownPreview(
            "# Heading\n\n**Bold** and *italic* with [link](https://example.com)\n\n- First\n- Second\n\n1. Third\n\n```\ncode\n```")
        suite.expect(markdownPreview.map(\.kind) == [
                    .heading(1), .paragraph,
                    .unorderedListItem(depth: 1), .unorderedListItem(depth: 1),
                    .orderedListItem(ordinal: 1, depth: 1), .code
                ]
                && String(markdownPreview[0].text.characters) == "Heading"
                && String(markdownPreview[2].text.characters) == "First"
                && String(markdownPreview[5].text.characters) == "code"
                && markdownPreview[2].containerID == markdownPreview[3].containerID
                && markdownPreview[2].containerID != nil
                && markdownPreview[3].containerID != markdownPreview[4].containerID
                && markdownPreview[1].text.runs.contains {
                    $0.inlinePresentationIntent?.contains(.stronglyEmphasized) == true
                }
                && markdownPreview[1].text.runs.contains {
                    $0.inlinePresentationIntent?.contains(.emphasized) == true
                }
                && markdownPreview[1].text.runs.contains { $0.link != nil },
               "the scratchpad preview renders semantic blocks and inline formatting")
        suite.expect(Defaults.registeredDefaults[DefaultsKey.scratchpadBackgroundOpacity] as? Double == 0.0,
               "the scratchpad keeps its familiar translucent background by default")
        suite.expect(SettingsBackupSupport.exportKeys().contains(DefaultsKey.scratchpadBackgroundOpacity),
               "the scratchpad background choice travels with the settings backup")
        suite.expect(ScratchpadSupport.sanitizedBackgroundOpacity(0.7) == 0.7,
               "a scratchpad background opacity inside the range is kept")
        suite.expect(ScratchpadSupport.sanitizedBackgroundOpacity(0)
                == ScratchpadSupport.backgroundOpacityRange.lowerBound
                && ScratchpadSupport.sanitizedBackgroundOpacity(-3)
                == ScratchpadSupport.backgroundOpacityRange.lowerBound,
               "the scratchpad background never goes below the familiar translucent style")
        suite.expect(ScratchpadSupport.sanitizedBackgroundOpacity(4) == 1.0
                && ScratchpadSupport.sanitizedBackgroundOpacity(.nan) == 1.0
                && ScratchpadSupport.sanitizedBackgroundOpacity(.infinity) == 1.0,
               "a high or broken scratchpad opacity falls back to fully opaque")
        let scratchpadNow = Date(timeIntervalSince1970: 1_784_000_000)
        suite.expect(!ScratchpadSupport.shouldClear(lastEdited: nil, now: scratchpadNow, retention: .day)
                && !ScratchpadSupport.shouldClear(lastEdited: scratchpadNow.addingTimeInterval(-90_000),
                                                  now: scratchpadNow, retention: .never)
                && !ScratchpadSupport.shouldClear(lastEdited: scratchpadNow.addingTimeInterval(-3_600),
                                                  now: scratchpadNow, retention: .day)
                && ScratchpadSupport.shouldClear(lastEdited: scratchpadNow.addingTimeInterval(-90_000),
                                                 now: scratchpadNow, retention: .day)
                && !ScratchpadSupport.shouldClear(lastEdited: scratchpadNow.addingTimeInterval(-90_000),
                                                  now: scratchpadNow, retention: .week)
                && ScratchpadSupport.shouldClear(lastEdited: scratchpadNow.addingTimeInterval(-8 * 86_400),
                                                 now: scratchpadNow, retention: .week)
                && !ScratchpadSupport.shouldClear(lastEdited: scratchpadNow.addingTimeInterval(60),
                                                  now: scratchpadNow, retention: .day),
               "the scratchpad only clears when a period is chosen and the last edit is older than it")
        let scratchpadExportName = ScratchpadSupport.exportFileName(title: "Scratchpad",
                                                                    date: scratchpadNow)
        suite.expect(scratchpadExportName.hasPrefix("Scratchpad 20")
                && scratchpadExportName.hasSuffix(".txt")
                && scratchpadExportName.count == "Scratchpad ".count + 14,
               "scratchpad export file name is the title plus the local date")
        let firstPadID = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
        let secondPadID = UUID(uuidString: "00000000-0000-0000-0000-000000000002")!
        let thirdPadID = UUID(uuidString: "00000000-0000-0000-0000-000000000003")!
        let migratedScratchpad = ScratchpadDocument.initial(
            defaultName: "Scratchpad", id: firstPadID, text: "existing text",
            modifiedAt: scratchpadNow.addingTimeInterval(-120))
        let twoPads = migratedScratchpad.addingPad(defaultName: "Scratchpad", id: secondPadID)
        let threePads = twoPads?.addingPad(defaultName: "Scratchpad", id: thirdPadID)
        suite.expect(threePads?.pads.map(\.name) == ["Scratchpad 1", "Scratchpad 2", "Scratchpad 3"]
                && threePads?.pads.map(\.id) == [firstPadID, secondPadID, thirdPadID]
                && threePads?.selectedID == thirdPadID,
               "new scratchpads append in order, receive clear names and become selected")
        suite.expect(ScratchpadSupport.nextPadName(defaultName: "Scratchpad",
                                             existingNames: ["Scratchpad"]) == "Scratchpad 2",
               "an existing unnumbered scratchpad still occupies the first numbered slot")
        let renamedPad = threePads?.renaming(secondPadID, to: "  Work\nideas  ")
        suite.expect(renamedPad?.pads[1].name == "Work ideas"
                && ScratchpadSupport.sanitizedPadName(String(repeating: "x", count: 50)).count
                    == ScratchpadDocument.maximumNameLength
                && threePads?.renaming(secondPadID, to: "   ") == nil,
               "scratchpad names stay single-line, bounded and never empty")
        let selectedFirst = renamedPad?.selecting(firstPadID)
        let removedFirst = selectedFirst?.removing(firstPadID)
        suite.expect(removedFirst?.pads.map(\.id) == [secondPadID, thirdPadID]
                && removedFirst?.selectedID == secondPadID,
               "closing the selected scratchpad keeps order and selects its nearest neighbor")
        suite.expect(migratedScratchpad.removing(firstPadID) == nil,
               "the last scratchpad cannot be closed")
        suite.expect(ScratchpadSupport.requiresCloseConfirmation(migratedScratchpad.pads[0])
                && !ScratchpadSupport.requiresCloseConfirmation(
                    ScratchpadDocument.initial(defaultName: "Scratchpad").pads[0]),
               "only closing a scratchpad with content needs destructive confirmation")

        suite.expect(ScratchpadFocusedShortcut.action(charactersIgnoringModifiers: "t",
                                                   commandOnly: true,
                                                   canCreatePad: true,
                                                   canClosePad: true) == .createPad,
               "Command-T creates a scratchpad tab while the pad is focused")
        suite.expect(ScratchpadFocusedShortcut.action(charactersIgnoringModifiers: "t",
                                                   commandOnly: true,
                                                   canCreatePad: false,
                                                   canClosePad: true) == nil,
               "Command-T is idle at the scratchpad tab limit")
        suite.expect(ScratchpadFocusedShortcut.action(charactersIgnoringModifiers: "w",
                                                   commandOnly: true,
                                                   canCreatePad: true,
                                                   canClosePad: true) == .closeSelectedPad,
               "Command-W closes the selected scratchpad tab when more than one remains")
        suite.expect(ScratchpadFocusedShortcut.action(charactersIgnoringModifiers: "w",
                                                   commandOnly: true,
                                                   canCreatePad: true,
                                                   canClosePad: false) == .hidePad,
               "Command-W on the last scratchpad tab hides the pad")
        suite.expect(ScratchpadFocusedShortcut.action(charactersIgnoringModifiers: "t",
                                                   commandOnly: false,
                                                   canCreatePad: true,
                                                   canClosePad: true) == nil
                && ScratchpadFocusedShortcut.action(charactersIgnoringModifiers: "w",
                                                       commandOnly: false,
                                                       canCreatePad: true,
                                                       canClosePad: true) == nil
                && ScratchpadFocusedShortcut.action(charactersIgnoringModifiers: "a",
                                                       commandOnly: true,
                                                       canCreatePad: true,
                                                       canClosePad: true) == nil,
               "scratchpad tab shortcuts need Command alone on T or W")
        suite.expect(ScratchpadFocusedShortcut.action(charactersIgnoringModifiers: "W",
                                                   commandOnly: true,
                                                   canCreatePad: true,
                                                   canClosePad: true) == .closeSelectedPad,
               "Caps Lock preserves the scratchpad close shortcut")
        suite.expect(ScratchpadFocusedShortcut.action(charactersIgnoringModifiers: "z",
                                                   commandOnly: true,
                                                   canCreatePad: true,
                                                   canClosePad: true) == nil,
               "the AZERTY Z at the US W position must not close a scratchpad")
        suite.expect(ScratchpadFocusedShortcut.action(charactersIgnoringModifiers: nil,
                                                   commandOnly: true,
                                                   canCreatePad: true,
                                                   canClosePad: true) == nil,
               "events without a character do not trigger scratchpad tab shortcuts")
        var limitedScratchpads = migratedScratchpad
        for _ in 2...ScratchpadDocument.maximumPadCount {
            limitedScratchpads = limitedScratchpads.addingPad(defaultName: "Scratchpad")!
        }
        suite.expect(limitedScratchpads.pads.count == ScratchpadDocument.maximumPadCount
                && limitedScratchpads.addingPad(defaultName: "Scratchpad") == nil,
               "scratchpads keep a small fixed upper bound")
        var retainedScratchpads = ScratchpadDocument.initial(
            defaultName: "Scratchpad",
            id: firstPadID,
            text: "expired text",
            modifiedAt: scratchpadNow.addingTimeInterval(-90_000))
        retainedScratchpads = retainedScratchpads.addingPad(defaultName: "Scratchpad",
                                                             id: secondPadID)!
        retainedScratchpads.updateSelectedText("recent text",
                                               modifiedAt: scratchpadNow.addingTimeInterval(-300))
        retainedScratchpads.applyRetention(.day, now: scratchpadNow)
        suite.expect(retainedScratchpads.pads[0].text.isEmpty
                && retainedScratchpads.pads[1].text == "recent text",
               "retention clears only scratchpads whose own text expired")
        let scratchpadDocumentData = renamedPad?.encoded()
        let decodedScratchpads = ScratchpadDocument.decoded(scratchpadDocumentData,
                                                            defaultName: "Scratchpad")
        suite.expect(decodedScratchpads == renamedPad,
               "scratchpad text, names, order and selection round-trip together")
        let scratchpadBackup = SettingsBackupSupport.payload(appVersion: "test") { key in
            key == DefaultsKey.scratchpadDocument ? scratchpadDocumentData : nil
        }
        let restoredScratchpadSettings = SettingsBackupSupport.sanitizedSettings(from: scratchpadBackup)
        suite.expect(restoredScratchpadSettings?[DefaultsKey.scratchpadDocument] == nil,
               "the scratchpad's own text stays out of a settings backup people copy around")
        let safeScratchpadExportName = ScratchpadSupport.exportFileName(
            title: "Work/Ideas: 1", date: scratchpadNow)
        suite.expect(safeScratchpadExportName.hasPrefix("Work-Ideas- 1 ")
                && !safeScratchpadExportName.contains("/")
                && !safeScratchpadExportName.contains(":"),
               "scratchpad export names cannot turn tab names into path components")

        // Muting every microphone, not just the one the Mac is set to: an app
        // pointed at a device of its own has to go silent too.
        suite.expect(MicMuteSupport.isOwnDevice(name: "Vorssaint Mixer")
                && MicMuteSupport.isOwnDevice(name: "Vorssaint AirPlay")
                && MicMuteSupport.isOwnDevice(name: "Vorssaint Island Levels")
                && MicMuteSupport.isOwnDevice(name: "Vorssaint Recorder")
                && !MicMuteSupport.isOwnDevice(name: "MacBook Air Microphone"),
               "the mute skips the app's own aggregate devices and no other")
        suite.expect(!MicMuteSupport.shouldSaveVolume(nil)
                && !MicMuteSupport.shouldSaveVolume(0)
                && !MicMuteSupport.shouldSaveVolume(0.005)
                && MicMuteSupport.shouldSaveVolume(0.4),
               "a level worth restoring is remembered and a silent one never is")
        suite.expect(MicMuteSupport.volumeToRestore(uid: "mic-a",
                                              saved: ["mic-a": 0.4, "mic-b": 0.9],
                                              legacy: 0.6) == 0.4
                && MicMuteSupport.volumeToRestore(uid: "mic-c",
                                                  saved: ["mic-a": 0.4],
                                                  legacy: 0.6) == 0.6
                && MicMuteSupport.volumeToRestore(uid: "mic-c", saved: [:], legacy: 0)
                    == MicMuteSupport.fallbackVolume
                && MicMuteSupport.volumeToRestore(uid: "mic-a",
                                                  saved: ["mic-a": 0],
                                                  legacy: 0) == MicMuteSupport.fallbackVolume,
               "each microphone gets its own level back, then the older single level, then a usable one")
        suite.expect(MicMuteSupport.restoreTargets(recorded: ["mic-a", "gone"],
                                             present: ["mic-a", "mic-b"]) == ["mic-a"]
                && MicMuteSupport.restoreTargets(recorded: nil,
                                                 present: ["mic-a", "mic-b"]) == ["mic-a", "mic-b"]
                && MicMuteSupport.restoreTargets(recorded: [],
                                                 present: ["mic-a", "mic-b"]).isEmpty
                && MicMuteSupport.restoreTargets(recorded: ["mic-a"], present: []).isEmpty,
               "unmuting touches the microphones this app muted, every one with no record, and none when the record is empty")
        suite.expect(MicMuteSupport.absentClaims(recorded: ["mic-a", "headset"],
                                           present: ["mic-a"]) == ["headset"]
                && MicMuteSupport.absentClaims(recorded: ["mic-a"],
                                               present: ["mic-a", "mic-b"]).isEmpty
                && MicMuteSupport.absentClaims(recorded: nil, present: ["mic-a"]).isEmpty
                && MicMuteSupport.absentClaims(recorded: ["headset"], present: []) == ["headset"],
               "a sweep keeps the claim on a microphone this app muted that is unplugged right now, so it is released when it returns")
        let micMuteServiceSource = (try? String(
            contentsOfFile: "Sources/Vorssaint/Services/QuickTools/MicMuteService.swift",
            encoding: .utf8)) ?? ""
        let reapply = micMuteServiceSource.range(of: "private func reapplyIfNeeded() {")
            .map { micMuteServiceSource[$0.lowerBound...] }
            .flatMap { body in body.range(of: "\n    }\n").map { body[..<$0.lowerBound] } }
            .map(String.init) ?? ""
        suite.expect(reapply.contains("if wantsMute {") && !reapply.contains("micMuteActive")
                && micMuteServiceSource.contains(
                    "private func apply(muted: Bool, announce: Bool) {\n        wantsMute = muted"),
               "a device change re-asserts the mute request in flight, never the persisted flag it is about to replace")

        suite.expect(Defaults.registeredDefaults[DefaultsKey.radialMenuEnabled] as? Bool == false,
               "the radial menu ships off by default")
        RadialMenuProfileDeletionContract.run(suite)
        suite.expect(Defaults.registeredDefaults[DefaultsKey.radialMenuShortcut] as? String
                == "control+option+command:49",
               "the default radial menu shortcut is control option command space")
        suite.expect(Defaults.registeredDefaults[DefaultsKey.radialMenuAtPointer] as? Bool == true,
               "the radial menu opens at the pointer by default")
        suite.expect(Defaults.registeredDefaults[DefaultsKey.radialMenuMouseButton] as? String == "off",
               "the side button trigger ships off")
        suite.expect(Defaults.registeredDefaults[DefaultsKey.radialMenuActivationMode] as? String == "pressOrHold",
               "the radial menu preserves its adaptive gesture by default")
        suite.expect(RadialMenuActivationMode.sanitized("press") == .press
                && RadialMenuActivationMode.sanitized("hold") == .hold
                && RadialMenuActivationMode.sanitized(nil) == .pressOrHold
                && RadialMenuActivationMode.sanitized("future-mode") == .pressOrHold,
               "the radial activation mode decodes known values and safely falls back")
        suite.expect(!RadialMenuActivationMode.press.startsHeld(
                    requestedHold: true, hasHeldButton: false, shortcutHasModifiers: true)
                && RadialMenuActivationMode.hold.startsHeld(
                    requestedHold: true, hasHeldButton: false, shortcutHasModifiers: true)
                && RadialMenuActivationMode.pressOrHold.startsHeld(
                    requestedHold: false, hasHeldButton: true, shortcutHasModifiers: false)
                && !RadialMenuActivationMode.hold.startsHeld(
                    requestedHold: false, hasHeldButton: false, shortcutHasModifiers: true),
               "only hold-capable summons enter the held phase")
        suite.expect(RadialMenuActivationMode.pressOrHold.releaseAction(hasSelection: false) == .stayOpen
                && RadialMenuActivationMode.hold.releaseAction(hasSelection: false) == .dismiss
                && RadialMenuActivationMode.hold.releaseAction(hasSelection: true) == .select,
               "release keeps the adaptive wheel, dismisses an empty strict hold, or selects its target")
        suite.expect(RadialMenuSupport.shortcutIsStillHeld(modifiersHeld: true, superKeyHeld: false)
                && RadialMenuSupport.shortcutIsStillHeld(modifiersHeld: false, superKeyHeld: true)
                && !RadialMenuSupport.shortcutIsStillHeld(modifiersHeld: false, superKeyHeld: false),
               "the radial hold follows physical modifiers or the virtual super key")
        suite.expect(RadialMenuMouseTrigger.sanitized("back") == .back
                && RadialMenuMouseTrigger.sanitized("forward").buttonNumber == 4
                && RadialMenuMouseTrigger.back.buttonNumber == 3
                && MouseButtonShortcutSupport.buttonRange.allSatisfy {
                    RadialMenuMouseTrigger.sanitized(
                        RadialMenuMouseTrigger.button($0).rawValue).buttonNumber == $0
                }
                && RadialMenuMouseTrigger.sanitized(nil) == .off
                && RadialMenuMouseTrigger.sanitized("teleport") == .off
                && RadialMenuMouseTrigger.sanitized("button:2") == .off
                && RadialMenuMouseTrigger.sanitized("button:32") == .off
                && RadialMenuMouseTrigger.off.buttonNumber == nil,
               "the mouse trigger round-trips every extra button and falls back to off")
        suite.expect(RadialMenuMouseTrigger.back.buttonNumber == MouseNavigationSupport.backButtonNumber
                && RadialMenuMouseTrigger.forward.buttonNumber == MouseNavigationSupport.forwardButtonNumber,
               "the wheel and mouse navigation agree on which button is which")
        suite.expect(!RadialMenuSupport.claimsMouseButton(3) && !RadialMenuSupport.claimsMouseButton(4),
               "with the feature off no side button is claimed away from navigation")
        suite.expect(Defaults.registeredDefaults[DefaultsKey.panelControlRadialMenu] as? Bool == true,
               "the radial menu panel row ships visible like its siblings")
        suite.expect(Defaults.registeredDefaults[DefaultsKey.radialMenuItems] == nil,
               "the items blob has no registered default so a fresh install detects the starter wheel")
        suite.expect(GlobalShortcutRole.radialMenu.requiredEnableKeys == [DefaultsKey.radialMenuEnabled]
                && GlobalShortcutRole.radialMenu.feature == .radialMenu,
               "the radial menu shortcut role gates on the feature toggle")

        GlobalShortcut.refreshLayoutLabels()
    }

    /// The island follows "Show in screenshots and videos" in Vorssaint's own
    /// captures too, area selections included, except while it is the tool
    /// taking the picture.
}

/// Runs the production profile deletion from Settings with its view state
/// held by a plain fixture.
enum RadialMenuProfileDeletionContract {
    class Fixture {
        var profiles: [RadialMenuProfile] = []
        var selectedProfileID: UUID?
        var openSubmenuID: UUID?
        var dragging: RadialMenuItem?
        var persisted = 0
        func persist() { persisted += 1 }
    }

    static func run(_ suite: TestSuite) {
        let settings = Settings()
        let first = RadialMenuProfile(name: "First")
        let second = RadialMenuProfile(name: "Second")
        let third = RadialMenuProfile(name: "Third")
        settings.profiles = [first, second, third]
        settings.selectedProfileID = third.id
        settings.deleteProfile(id: first.id)
        suite.expect(settings.profiles.map(\.id) == [second.id, third.id] && settings.persisted == 1,
                     "the confirmed profile is deleted even after the selection moved to another one")
        settings.deleteProfile(id: first.id)
        suite.expect(settings.profiles.count == 2 && settings.persisted == 1,
                     "a confirmation for a profile that is already gone deletes nothing")
        settings.deleteProfile(id: second.id)
        settings.deleteProfile(id: third.id)
        suite.expect(settings.profiles.map(\.id) == [third.id] && settings.selectedProfileID == third.id,
                     "the last profile is never deleted and stays selected")
    }
}
