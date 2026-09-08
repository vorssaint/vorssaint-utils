// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

enum ScratchpadTests {
    static func runDefaults(expect: (Bool, String) -> Void) {
        expect(Defaults.registeredDefaults[DefaultsKey.cameraPreviewShortcutEnabled] as? Bool == false,
               "the camera preview shortcut ships off like the other quick tools")
        expect(Defaults.registeredDefaults[DefaultsKey.cameraPreviewShortcut] as? String
                == "control+option+command:13",
               "the default camera preview shortcut is control option command W")
        expect(Defaults.registeredDefaults[DefaultsKey.panelUtilityCameraPreview] as? Bool == true,
               "the camera preview panel row ships visible like its siblings")
        expect(GlobalShortcutRole.cameraPreview.requiredEnableKeys == [DefaultsKey.cameraPreviewShortcutEnabled]
                && GlobalShortcutRole.cameraPreview.feature == .cameraPreview,
               "the camera preview shortcut role gates on its toggle and feature")

        expect(Defaults.registeredDefaults[DefaultsKey.scratchpadShortcutEnabled] as? Bool == false,
               "the scratchpad shortcut ships off like the other quick tools")
        expect(Defaults.registeredDefaults[DefaultsKey.scratchpadShortcut] as? String
                == "control+option+command:45",
               "the default scratchpad shortcut is control option command N")
        expect(Defaults.registeredDefaults[DefaultsKey.panelUtilityScratchpad] as? Bool == true,
               "the scratchpad panel row ships visible like its siblings")
        expect(Defaults.registeredDefaults[DefaultsKey.scratchpadRetention] as? String == "never",
               "the scratchpad keeps text until cleared by default")
        expect(Defaults.registeredDefaults[DefaultsKey.scratchpadCloseOnClickOutside] as? Bool == true,
               "a click outside puts the scratchpad away unless the user keeps it floating")
        expect(SettingsBackupSupport.exportKeys().contains(DefaultsKey.scratchpadCloseOnClickOutside),
               "the scratchpad dismissal choice travels with the settings backup")
        expect(GlobalShortcutRole.scratchpad.requiredEnableKeys == [DefaultsKey.scratchpadShortcutEnabled]
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
        expect(scratchpadHitTargetContracts.allSatisfy { scratchpadViewSource.contains($0) },
               "the scratchpad tab bar and header controls keep their full padded hit targets")
    }

    static func run(expect: (Bool, String) -> Void) {
        expect(ScratchpadRetention.sanitized("day") == .day
                && ScratchpadRetention.sanitized("week") == .week
                && ScratchpadRetention.sanitized("month") == .month
                && ScratchpadRetention.sanitized(nil) == .never
                && ScratchpadRetention.sanitized("yesterday") == .never,
               "scratchpad retention sanitizes to the allowed periods and falls back to never")
        expect(ScratchpadRetention.never.maxIdleInterval == nil
                && ScratchpadRetention.day.maxIdleInterval == 86_400
                && ScratchpadRetention.week.maxIdleInterval == 7 * 86_400
                && ScratchpadRetention.month.maxIdleInterval == 30 * 86_400,
               "scratchpad retention periods are a day, a week and thirty days")
        expect(ScratchpadSupport.dismissesOnOutsideClick(isPinned: false, exportModalActive: false)
                && !ScratchpadSupport.dismissesOnOutsideClick(isPinned: true, exportModalActive: false)
                && !ScratchpadSupport.dismissesOnOutsideClick(isPinned: false, exportModalActive: true),
               "the scratchpad pin and export dialog both block outside-click dismissal")
        let markdownPreview = ScratchpadSupport.markdownPreview(
            "# Heading\n\n**Bold** and *italic* with [link](https://example.com)\n\n- First\n- Second\n\n1. Third\n\n```\ncode\n```")
        expect(markdownPreview.map(\.kind) == [
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
        expect(Defaults.registeredDefaults[DefaultsKey.scratchpadBackgroundOpacity] as? Double == 0.0,
               "the scratchpad keeps its familiar translucent background by default")
        expect(SettingsBackupSupport.exportKeys().contains(DefaultsKey.scratchpadBackgroundOpacity),
               "the scratchpad background choice travels with the settings backup")
        expect(ScratchpadSupport.sanitizedBackgroundOpacity(0.7) == 0.7,
               "a scratchpad background opacity inside the range is kept")
        expect(ScratchpadSupport.sanitizedBackgroundOpacity(0)
                == ScratchpadSupport.backgroundOpacityRange.lowerBound
                && ScratchpadSupport.sanitizedBackgroundOpacity(-3)
                == ScratchpadSupport.backgroundOpacityRange.lowerBound,
               "the scratchpad background never goes below the familiar translucent style")
        expect(ScratchpadSupport.sanitizedBackgroundOpacity(4) == 1.0
                && ScratchpadSupport.sanitizedBackgroundOpacity(.nan) == 1.0
                && ScratchpadSupport.sanitizedBackgroundOpacity(.infinity) == 1.0,
               "a high or broken scratchpad opacity falls back to fully opaque")
        let scratchpadNow = Date(timeIntervalSince1970: 1_784_000_000)
        expect(!ScratchpadSupport.shouldClear(lastEdited: nil, now: scratchpadNow, retention: .day)
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
        expect(scratchpadExportName.hasPrefix("Scratchpad 20")
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
        expect(threePads?.pads.map(\.name) == ["Scratchpad 1", "Scratchpad 2", "Scratchpad 3"]
                && threePads?.pads.map(\.id) == [firstPadID, secondPadID, thirdPadID]
                && threePads?.selectedID == thirdPadID,
               "new scratchpads append in order, receive clear names and become selected")
        expect(ScratchpadSupport.nextPadName(defaultName: "Scratchpad",
                                             existingNames: ["Scratchpad"]) == "Scratchpad 2",
               "an existing unnumbered scratchpad still occupies the first numbered slot")
        let renamedPad = threePads?.renaming(secondPadID, to: "  Work\nideas  ")
        expect(renamedPad?.pads[1].name == "Work ideas"
                && ScratchpadSupport.sanitizedPadName(String(repeating: "x", count: 50)).count
                    == ScratchpadDocument.maximumNameLength
                && threePads?.renaming(secondPadID, to: "   ") == nil,
               "scratchpad names stay single-line, bounded and never empty")
        let selectedFirst = renamedPad?.selecting(firstPadID)
        let removedFirst = selectedFirst?.removing(firstPadID)
        expect(removedFirst?.pads.map(\.id) == [secondPadID, thirdPadID]
                && removedFirst?.selectedID == secondPadID,
               "closing the selected scratchpad keeps order and selects its nearest neighbor")
        expect(migratedScratchpad.removing(firstPadID) == nil,
               "the last scratchpad cannot be closed")
        expect(ScratchpadSupport.requiresCloseConfirmation(migratedScratchpad.pads[0])
                && !ScratchpadSupport.requiresCloseConfirmation(
                    ScratchpadDocument.initial(defaultName: "Scratchpad").pads[0]),
               "only closing a scratchpad with content needs destructive confirmation")

        expect(ScratchpadFocusedTabShortcut.action(charactersIgnoringModifiers: "t",
                                                   commandOnly: true,
                                                   canCreatePad: true,
                                                   canClosePad: true) == .createPad,
               "Command-T creates a scratchpad tab while the pad is focused")
        expect(ScratchpadFocusedTabShortcut.action(charactersIgnoringModifiers: "t",
                                                   commandOnly: true,
                                                   canCreatePad: false,
                                                   canClosePad: true) == nil,
               "Command-T is idle at the scratchpad tab limit")
        expect(ScratchpadFocusedTabShortcut.action(charactersIgnoringModifiers: "w",
                                                   commandOnly: true,
                                                   canCreatePad: true,
                                                   canClosePad: true) == .closeSelectedPad,
               "Command-W closes the selected scratchpad tab when more than one remains")
        expect(ScratchpadFocusedTabShortcut.action(charactersIgnoringModifiers: "w",
                                                   commandOnly: true,
                                                   canCreatePad: true,
                                                   canClosePad: false) == .hidePad,
               "Command-W on the last scratchpad tab hides the pad")
        expect(ScratchpadFocusedTabShortcut.action(charactersIgnoringModifiers: "t",
                                                   commandOnly: false,
                                                   canCreatePad: true,
                                                   canClosePad: true) == nil
                && ScratchpadFocusedTabShortcut.action(charactersIgnoringModifiers: "w",
                                                       commandOnly: false,
                                                       canCreatePad: true,
                                                       canClosePad: true) == nil
                && ScratchpadFocusedTabShortcut.action(charactersIgnoringModifiers: "a",
                                                       commandOnly: true,
                                                       canCreatePad: true,
                                                       canClosePad: true) == nil,
               "scratchpad tab shortcuts need Command alone on T or W")
        expect(ScratchpadFocusedTabShortcut.action(charactersIgnoringModifiers: "W",
                                                   commandOnly: true,
                                                   canCreatePad: true,
                                                   canClosePad: true) == .closeSelectedPad,
               "Caps Lock preserves the scratchpad close shortcut")
        expect(ScratchpadFocusedTabShortcut.action(charactersIgnoringModifiers: "z",
                                                   commandOnly: true,
                                                   canCreatePad: true,
                                                   canClosePad: true) == nil,
               "the AZERTY Z at the US W position must not close a scratchpad")
        expect(ScratchpadFocusedTabShortcut.action(charactersIgnoringModifiers: nil,
                                                   commandOnly: true,
                                                   canCreatePad: true,
                                                   canClosePad: true) == nil,
               "events without a character do not trigger scratchpad tab shortcuts")
        var limitedScratchpads = migratedScratchpad
        for _ in 2...ScratchpadDocument.maximumPadCount {
            limitedScratchpads = limitedScratchpads.addingPad(defaultName: "Scratchpad")!
        }
        expect(limitedScratchpads.pads.count == ScratchpadDocument.maximumPadCount
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
        expect(retainedScratchpads.pads[0].text.isEmpty
                && retainedScratchpads.pads[1].text == "recent text",
               "retention clears only scratchpads whose own text expired")
        scratchpadStoreChecks { expect($0, $1) }
        let scratchpadDocumentData = renamedPad?.encoded()
        let decodedScratchpads = ScratchpadDocument.decoded(scratchpadDocumentData,
                                                            defaultName: "Scratchpad")
        expect(decodedScratchpads == renamedPad,
               "scratchpad text, names, order and selection round-trip together")
        let scratchpadBackup = SettingsBackupSupport.payload(appVersion: "test") { key in
            key == DefaultsKey.scratchpadDocument ? scratchpadDocumentData : nil
        }
        let restoredScratchpadSettings = SettingsBackupSupport.sanitizedSettings(from: scratchpadBackup)
        expect(restoredScratchpadSettings?[DefaultsKey.scratchpadDocument] == nil,
               "the scratchpad's own text stays out of a settings backup people copy around")
        let safeScratchpadExportName = ScratchpadSupport.exportFileName(
            title: "Work/Ideas: 1", date: scratchpadNow)
        expect(safeScratchpadExportName.hasPrefix("Work-Ideas- 1 ")
                && !safeScratchpadExportName.contains("/")
                && !safeScratchpadExportName.contains(":"),
               "scratchpad export names cannot turn tab names into path components")
    }

    private static func scratchpadStoreChecks(_ expect: (Bool, String) -> Void) {
        let manager = FileManager.default
        let now = Date(timeIntervalSince1970: 1_784_000_000)
        let original = ScratchpadDocument.initial(defaultName: "Scratchpad", text: "Keep these notes",
                                                   modifiedAt: now.addingTimeInterval(-90_000))
        let originalData = original.encoded()!
        let empty = ScratchpadDocument.initial(defaultName: "Scratchpad")

        func fixture(_ check: (URL, UserDefaults, inout ScratchpadStore) throws -> Void) {
            let directory = manager.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            let suite = "com.vorssaint.tests.scratchpad.\(UUID().uuidString)"
            let defaults = UserDefaults(suiteName: suite)!
            defer {
                try? manager.removeItem(at: directory)
                defaults.removePersistentDomain(forName: suite)
            }
            do {
                try manager.createDirectory(at: directory, withIntermediateDirectories: true)
                var store = ScratchpadStore(directoryURL: directory, defaults: defaults)
                try check(directory, defaults, &store)
            } catch {
                expect(false, "scratchpad fixture completes: \(error)")
            }
        }

        fixture { directory, _, store in
            expect(!store.save(empty), "scratchpad cannot save before its first successful read")
            let loaded = try store.load(defaultName: "Scratchpad", retention: .never, now: now)
            expect(loaded.pads.count == 1 && loaded.pads[0].text.isEmpty,
                   "a scratchpad with no files or preferences starts empty")
            expect(store.save(original), "a new scratchpad saves edits after a successful read")
            let reopened = try store.load(defaultName: "Scratchpad", retention: .never, now: now)
            expect(reopened == original, "scratchpad edits survive reopening")
            let url = directory.appendingPathComponent("Scratchpad.json")
            let permissions = try manager.attributesOfItem(atPath: url.path)[.posixPermissions] as? NSNumber
            expect(permissions?.intValue == 0o600, "scratchpad content remains owner-only")
        }

        for damaged in [Data(), Data("{broken".utf8), Data("{}".utf8)] {
            fixture { directory, defaults, store in
                let url = directory.appendingPathComponent("Scratchpad.json")
                let legacyURL = directory.appendingPathComponent("Scratchpad.txt")
                try damaged.write(to: url)
                try Data("Older notes".utf8).write(to: legacyURL)
                defaults.set(originalData, forKey: DefaultsKey.scratchpadDocument)
                expect((try? store.load(defaultName: "Scratchpad", retention: .day, now: now)) == nil,
                       "damaged scratchpad data fails without applying retention or falling back")
                expect(!store.save(empty) && !store.save(original),
                       "a damaged scratchpad blocks subsequent saves of empty and nonempty documents")
                expect(try Data(contentsOf: url) == damaged,
                       "damaged scratchpad bytes are preserved exactly")
                expect(defaults.data(forKey: DefaultsKey.scratchpadDocument) == originalData
                        && (try? String(contentsOf: legacyURL, encoding: .utf8)) == "Older notes",
                       "a damaged current file keeps both older copies")
                try originalData.write(to: url)
                let retried = try store.load(defaultName: "Scratchpad", retention: .never, now: now)
                expect(retried == original && store.save(original),
                       "retrying after the file becomes readable re-enables normal saving")
            }
        }

        fixture { directory, defaults, store in
            let url = directory.appendingPathComponent("Scratchpad.json")
            try originalData.write(to: url)
            _ = try store.load(defaultName: "Scratchpad", retention: .never, now: now)
            defaults.set(originalData, forKey: DefaultsKey.scratchpadDocument)
            try manager.setAttributes([.posixPermissions: 0], ofItemAtPath: url.path)
            defer { try? manager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path) }
            expect((try? store.load(defaultName: "Scratchpad", retention: .day, now: now)) == nil,
                   "a read permission failure after a successful opening is not treated as a missing file")
            expect(!store.save(empty) && !store.save(original),
                   "a failed reload revokes saving even for the previously saved document")
            try manager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
            expect(try Data(contentsOf: url) == originalData,
                   "a read permission failure preserves the original file")
            expect(defaults.data(forKey: DefaultsKey.scratchpadDocument) == originalData,
                   "a read permission failure preserves a valid preference copy")
        }

        for preference: Any in [Data("{broken".utf8), "unexpected preference type"] {
            fixture { directory, defaults, store in
                defaults.set(preference, forKey: DefaultsKey.scratchpadDocument)
                let legacyURL = directory.appendingPathComponent("Scratchpad.txt")
                try Data("Older notes".utf8).write(to: legacyURL)
                expect((try? store.load(defaultName: "Scratchpad", retention: .never, now: now)) == nil
                        && !store.save(empty), "an invalid preference blocks replacement and legacy migration")
                expect(defaults.object(forKey: DefaultsKey.scratchpadDocument) != nil
                        && !manager.fileExists(atPath: directory.appendingPathComponent("Scratchpad.json").path)
                        && (try? String(contentsOf: legacyURL, encoding: .utf8)) == "Older notes",
                       "invalid preferences and older notes survive a failed load")
            }
        }

        fixture { directory, defaults, store in
            defaults.set(originalData, forKey: DefaultsKey.scratchpadDocument)
            let migrated = try store.load(defaultName: "Scratchpad", retention: .never, now: now)
            let saved = try Data(contentsOf: directory.appendingPathComponent("Scratchpad.json"))
            expect(migrated == original && ScratchpadDocument.decoded(saved, defaultName: "Scratchpad") == original,
                   "valid preferences migrate with all note content intact")
            expect(defaults.object(forKey: DefaultsKey.scratchpadDocument) == nil,
                   "a migrated preference is removed after the replacement is verified")
        }

        for legacy in [false, true] {
            fixture { directory, defaults, store in
                let legacyURL = directory.appendingPathComponent("Scratchpad.txt")
                if legacy {
                    try Data("Older notes".utf8).write(to: legacyURL)
                } else {
                    defaults.set(originalData, forKey: DefaultsKey.scratchpadDocument)
                }
                try manager.setAttributes([.immutable: true], ofItemAtPath: directory.path)
                defer { try? manager.setAttributes([.immutable: false], ofItemAtPath: directory.path) }
                let loaded = try store.load(defaultName: "Scratchpad", retention: .never, now: now)
                expect(store.lastSavedDocument == nil
                        && !manager.fileExists(atPath: directory.appendingPathComponent("Scratchpad.json").path),
                       "a blocked migration never counts as a saved document")
                expect(legacy
                        ? (try? String(contentsOf: legacyURL, encoding: .utf8)) == "Older notes"
                        : defaults.data(forKey: DefaultsKey.scratchpadDocument) == originalData,
                       "a failed migration write keeps the source copy")
                try manager.setAttributes([.immutable: false], ofItemAtPath: directory.path)
                expect(store.save(loaded), "migration can retry saving once storage becomes writable")
            }
        }

        for unreadable in [false, true] {
            fixture { directory, _, store in
                let legacyURL = directory.appendingPathComponent("Scratchpad.txt")
                let legacyData = unreadable ? Data("Keep these notes".utf8) : Data([0xff, 0xfe, 0xff])
                try legacyData.write(to: legacyURL)
                if unreadable { try manager.setAttributes([.posixPermissions: 0], ofItemAtPath: legacyURL.path) }
                defer { try? manager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: legacyURL.path) }
                expect((try? store.load(defaultName: "Scratchpad", retention: .day, now: now)) == nil
                        && !store.save(empty), "unreadable or invalid legacy text blocks saving")
                try manager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: legacyURL.path)
                expect(try Data(contentsOf: legacyURL) == legacyData,
                       "failed legacy reads preserve the exact original bytes")
                expect(!manager.fileExists(atPath: directory.appendingPathComponent("Scratchpad.json").path),
                       "failed legacy reads never create an empty replacement")
            }
        }

        fixture { directory, _, store in
            let legacyURL = directory.appendingPathComponent("Scratchpad.txt")
            try Data("Older notes".utf8).write(to: legacyURL)
            let migrated = try store.load(defaultName: "Scratchpad", retention: .never, now: now)
            let saved = try Data(contentsOf: directory.appendingPathComponent("Scratchpad.json"))
            expect(migrated.pads[0].text == "Older notes"
                    && ScratchpadDocument.decoded(saved, defaultName: "Scratchpad") == migrated
                    && !manager.fileExists(atPath: legacyURL.path),
                   "valid legacy text is removed only after its replacement is verified")
        }

        fixture { directory, _, store in
            let url = directory.appendingPathComponent("Scratchpad.json")
            try originalData.write(to: url)
            let loaded = try store.load(defaultName: "Scratchpad", retention: .day, now: now)
            let saved = try Data(contentsOf: url)
            expect(loaded.pads[0].text.isEmpty
                    && ScratchpadDocument.decoded(saved, defaultName: "Scratchpad") == loaded,
                   "retention still clears expired notes after a successful read")
        }

        fixture { _, defaults, _ in
            defaults.set(originalData, forKey: DefaultsKey.scratchpadDocument)
            var unavailable = ScratchpadStore(directoryURL: nil, defaults: defaults)
            expect((try? unavailable.load(defaultName: "Scratchpad", retention: .never, now: now)) == nil
                    && !unavailable.save(empty)
                    && defaults.data(forKey: DefaultsKey.scratchpadDocument) == originalData,
                   "an unavailable private container never discards stored notes")
        }
    }
}
