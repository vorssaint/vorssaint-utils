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

enum ScratchpadStoreContractTests {
    static func run(_ suite: TestSuite) {
        let manager = FileManager.default
        let now = Date(timeIntervalSince1970: 1_784_000_000)
        let original = ScratchpadDocument.initial(defaultName: "Scratchpad", text: "Keep these notes",
                                                   modifiedAt: now.addingTimeInterval(-90_000))
        let originalData = original.encoded()!
        let empty = ScratchpadDocument.initial(defaultName: "Scratchpad")

        func fixture(_ check: (URL, UserDefaults, inout ScratchpadStore) throws -> Void) {
            let directory = manager.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            let suiteName = "com.vorssaint.tests.scratchpad.\(UUID().uuidString)"
            let defaults = UserDefaults(suiteName: suiteName)!
            defer {
                try? manager.removeItem(at: directory)
                defaults.removePersistentDomain(forName: suiteName)
            }
            do {
                try manager.createDirectory(at: directory, withIntermediateDirectories: true)
                var store = ScratchpadStore(directoryURL: directory, defaults: defaults)
                try check(directory, defaults, &store)
            } catch {
                suite.expect(false, "scratchpad fixture completes: \(error)")
            }
        }

        fixture { directory, _, store in
            suite.expect(!store.save(empty), "scratchpad cannot save before its first successful read")
            let loaded = try store.load(defaultName: "Scratchpad", retention: .never, now: now)
            suite.expect(loaded.pads.count == 1 && loaded.pads[0].text.isEmpty,
                   "a scratchpad with no files or preferences starts empty")
            suite.expect(store.save(original), "a new scratchpad saves edits after a successful read")
            let reopened = try store.load(defaultName: "Scratchpad", retention: .never, now: now)
            suite.expect(reopened == original, "scratchpad edits survive reopening")
            let url = directory.appendingPathComponent("Scratchpad.json")
            let permissions = try manager.attributesOfItem(atPath: url.path)[.posixPermissions] as? NSNumber
            suite.expect(permissions?.intValue == 0o600, "scratchpad content remains owner-only")
        }

        for damaged in [Data(), Data("{broken".utf8), Data("{}".utf8)] {
            fixture { directory, defaults, store in
                let url = directory.appendingPathComponent("Scratchpad.json")
                let legacyURL = directory.appendingPathComponent("Scratchpad.txt")
                try damaged.write(to: url)
                try Data("Older notes".utf8).write(to: legacyURL)
                defaults.set(originalData, forKey: DefaultsKey.scratchpadDocument)
                suite.expect((try? store.load(defaultName: "Scratchpad", retention: .day, now: now)) == nil,
                       "damaged scratchpad data fails without applying retention or falling back")
                suite.expect(!store.save(empty) && !store.save(original),
                       "a damaged scratchpad blocks subsequent saves of empty and nonempty documents")
                suite.expect(try Data(contentsOf: url) == damaged,
                       "damaged scratchpad bytes are preserved exactly")
                suite.expect(defaults.data(forKey: DefaultsKey.scratchpadDocument) == originalData
                        && (try? String(contentsOf: legacyURL, encoding: .utf8)) == "Older notes",
                       "a damaged current file keeps both older copies")
                try originalData.write(to: url)
                let retried = try store.load(defaultName: "Scratchpad", retention: .never, now: now)
                suite.expect(retried == original && store.save(original),
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
            suite.expect((try? store.load(defaultName: "Scratchpad", retention: .day, now: now)) == nil,
                   "a read permission failure after a successful opening is not treated as a missing file")
            suite.expect(!store.save(empty) && !store.save(original),
                   "a failed reload revokes saving even for the previously saved document")
            try manager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
            suite.expect(try Data(contentsOf: url) == originalData,
                   "a read permission failure preserves the original file")
            suite.expect(defaults.data(forKey: DefaultsKey.scratchpadDocument) == originalData,
                   "a read permission failure preserves a valid preference copy")
        }

        for preference: Any in [Data("{broken".utf8), "unexpected preference type"] {
            fixture { directory, defaults, store in
                defaults.set(preference, forKey: DefaultsKey.scratchpadDocument)
                let legacyURL = directory.appendingPathComponent("Scratchpad.txt")
                try Data("Older notes".utf8).write(to: legacyURL)
                suite.expect((try? store.load(defaultName: "Scratchpad", retention: .never, now: now)) == nil
                        && !store.save(empty), "an invalid preference blocks replacement and legacy migration")
                suite.expect(defaults.object(forKey: DefaultsKey.scratchpadDocument) != nil
                        && !manager.fileExists(atPath: directory.appendingPathComponent("Scratchpad.json").path)
                        && (try? String(contentsOf: legacyURL, encoding: .utf8)) == "Older notes",
                       "invalid preferences and older notes survive a failed load")
            }
        }

        fixture { directory, defaults, store in
            defaults.set(originalData, forKey: DefaultsKey.scratchpadDocument)
            let migrated = try store.load(defaultName: "Scratchpad", retention: .never, now: now)
            let saved = try Data(contentsOf: directory.appendingPathComponent("Scratchpad.json"))
            suite.expect(migrated == original && ScratchpadDocument.decoded(saved, defaultName: "Scratchpad") == original,
                   "valid preferences migrate with all note content intact")
            suite.expect(defaults.object(forKey: DefaultsKey.scratchpadDocument) == nil,
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
                suite.expect(store.lastSavedDocument == nil
                        && !manager.fileExists(atPath: directory.appendingPathComponent("Scratchpad.json").path),
                       "a blocked migration never counts as a saved document")
                suite.expect(legacy
                        ? (try? String(contentsOf: legacyURL, encoding: .utf8)) == "Older notes"
                        : defaults.data(forKey: DefaultsKey.scratchpadDocument) == originalData,
                       "a failed migration write keeps the source copy")
                try manager.setAttributes([.immutable: false], ofItemAtPath: directory.path)
                suite.expect(store.save(loaded), "migration can retry saving once storage becomes writable")
            }
        }

        for unreadable in [false, true] {
            fixture { directory, _, store in
                let legacyURL = directory.appendingPathComponent("Scratchpad.txt")
                let legacyData = unreadable ? Data("Keep these notes".utf8) : Data([0xff, 0xfe, 0xff])
                try legacyData.write(to: legacyURL)
                if unreadable { try manager.setAttributes([.posixPermissions: 0], ofItemAtPath: legacyURL.path) }
                defer { try? manager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: legacyURL.path) }
                suite.expect((try? store.load(defaultName: "Scratchpad", retention: .day, now: now)) == nil
                        && !store.save(empty), "unreadable or invalid legacy text blocks saving")
                try manager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: legacyURL.path)
                suite.expect(try Data(contentsOf: legacyURL) == legacyData,
                       "failed legacy reads preserve the exact original bytes")
                suite.expect(!manager.fileExists(atPath: directory.appendingPathComponent("Scratchpad.json").path),
                       "failed legacy reads never create an empty replacement")
            }
        }

        fixture { directory, _, store in
            let legacyURL = directory.appendingPathComponent("Scratchpad.txt")
            try Data("Older notes".utf8).write(to: legacyURL)
            let migrated = try store.load(defaultName: "Scratchpad", retention: .never, now: now)
            let saved = try Data(contentsOf: directory.appendingPathComponent("Scratchpad.json"))
            suite.expect(migrated.pads[0].text == "Older notes"
                    && ScratchpadDocument.decoded(saved, defaultName: "Scratchpad") == migrated
                    && !manager.fileExists(atPath: legacyURL.path),
                   "valid legacy text is removed only after its replacement is verified")
        }

        fixture { directory, _, store in
            let url = directory.appendingPathComponent("Scratchpad.json")
            try originalData.write(to: url)
            let loaded = try store.load(defaultName: "Scratchpad", retention: .day, now: now)
            let saved = try Data(contentsOf: url)
            suite.expect(loaded.pads[0].text.isEmpty
                    && ScratchpadDocument.decoded(saved, defaultName: "Scratchpad") == loaded,
                   "retention still clears expired notes after a successful read")
        }

        fixture { _, defaults, _ in
            defaults.set(originalData, forKey: DefaultsKey.scratchpadDocument)
            var unavailable = ScratchpadStore(directoryURL: nil, defaults: defaults)
            suite.expect((try? unavailable.load(defaultName: "Scratchpad", retention: .never, now: now)) == nil
                    && !unavailable.save(empty)
                    && defaults.data(forKey: DefaultsKey.scratchpadDocument) == originalData,
                   "an unavailable private container never discards stored notes")
        }
    }
}
