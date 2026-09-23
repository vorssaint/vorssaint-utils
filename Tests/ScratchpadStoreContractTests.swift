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
import UniformTypeIdentifiers
import VMStatisticsCompat

enum ScratchpadStoreContractTests {
    static func run(_ suite: TestSuite) {
        ScratchpadExportContract.run(suite)
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

/// The production export method runs against inert window and panel doubles.
/// No system dialog opens, and writes stay inside a disposable directory.
enum ScratchpadExportContract {
    final class Window {
        struct Level { let rawValue: Int }
        var level = Level(rawValue: 26)
        var isVisible = true
        var focusCount = 0
        func makeKey() { focusCount += 1 }
    }
    final class Application {
        var keyWindow: Window?
        var currentEvent: Event?
        struct Event { let window: Window? }
        func activate(ignoringOtherApps: Bool) {}
    }
    final class Panel {
        static var latest: Panel?
        var allowedContentTypes: [UTType] = []
        var canCreateDirectories = false
        var isExtensionHidden = true
        var nameFieldStringValue = ""
        var url: URL?
        var parent: Window?
        var level = Window.Level(rawValue: 0)
        var standalone = false
        var focused = false
        var modalCalls = 0
        var response: NSApplication.ModalResponse = .cancel
        var completion: ((NSApplication.ModalResponse) -> Void)?
        init() { Self.latest = self }
        func runModal() -> NSApplication.ModalResponse { modalCalls += 1; return response }
        func beginSheetModal(for parent: Window,
                             completionHandler: @escaping (NSApplication.ModalResponse) -> Void) {
            self.parent = parent
            completion = completionHandler
        }
        func begin(completionHandler: @escaping (NSApplication.ModalResponse) -> Void) {
            standalone = true
            completion = completionHandler
        }
        func makeKeyAndOrderFront(_ sender: Any?) { focused = true }
        func finish(_ response: NSApplication.ModalResponse) {
            let callback = completion
            completion = nil
            callback?(response)
        }
    }
    enum Queue {
        static var main: Queue.Type { Self.self }
        static var jobs: [() -> Void] = []
        static func async(execute action: @escaping () -> Void) { jobs.append(action) }
        static func drain() { while !jobs.isEmpty { jobs.removeFirst()() } }
    }
    final class Island {
        static let shared = Island()
        var presentationWindow: Window?
    }
    enum HUD {
        static var errors = 0
        static func show(icon: String, message: String) { errors += 1 }
    }
    class Fixture {
        typealias NSSavePanel = Panel
        typealias NSWindow = Window
        typealias DispatchQueue = Queue
        typealias NotchService = Island
        typealias QuickToolHUD = HUD
        var NSApp = Application()
        var panel: Window?
        var text = "Notes to export"
        var modalInteractionActive = false
        var flushes = 0
        func flushSave() { flushes += 1 }
    }

    static func run(_ suite: TestSuite) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer {
            Queue.jobs = []
            Panel.latest = nil
            Island.shared.presentationWindow = nil
            try? FileManager.default.removeItem(at: root)
        }
        do {
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            for host in ["island key", "island event", "island menu", "floating", "floating while island key"] {
                for response in [NSApplication.ModalResponse.cancel, .OK] {
                    let service = Service()
                    let island = Window()
                    let floating = Window()
                    Island.shared.presentationWindow = island
                    service.panel = floating
                    service.NSApp.keyWindow = host == "island key" || host == "floating while island key" ? island : floating
                    if host == "island event" {
                        service.NSApp.currentEvent = Application.Event(window: island)
                    } else if host == "island menu" {
                        service.NSApp.currentEvent = Application.Event(window: Window())
                    }
                    let fromIsland = host.hasPrefix("island")
                    let destination = root.appendingPathComponent("notes.txt")
                    try "Previous file".write(to: destination, atomically: true, encoding: .utf8)
                    service.exportText(suggestedName: "Notes.txt", from: fromIsland ? island : nil)
                    guard let panel = Panel.latest else {
                        suite.expect(false, "export prepares its save panel")
                        continue
                    }
                    suite.expect(service.modalInteractionActive && service.flushes == 1,
                                 "export protects its document while a dialog is pending")
                    service.exportText(suggestedName: "Duplicate.txt")
                    suite.expect(Panel.latest === panel, "a pending export cannot open a second dialog")
                    panel.url = destination
                    panel.response = response
                    service.text = "A later edit"
                    if !fromIsland {
                        suite.expect(panel.parent == nil, "the floating pad retains its independent dialog")
                        Queue.drain()
                        suite.expect(panel.modalCalls == 1 && floating.focusCount == 1 && island.focusCount == 0,
                                     "floating-pad export returns focus only to its own host")
                    } else {
                        suite.expect(panel.parent == nil && panel.standalone && panel.focused && panel.modalCalls == 0
                                     && panel.level.rawValue > island.level.rawValue,
                                     "island export opens its own dialog above its host instead of attaching or opening behind it")
                        panel.finish(response)
                        suite.expect(island.focusCount == 0, "completion defers focus until dismissal finishes")
                        Queue.drain()
                        suite.expect(island.focusCount == 1 && floating.focusCount == 0,
                                     "island export returns focus to the island even when its menu supplied the event")
                    }
                    suite.expect(!service.modalInteractionActive, "completion releases the export guard")
                    let saved = try String(contentsOf: destination, encoding: .utf8)
                    suite.expect(saved == (response == .OK ? "Notes to export" : "Previous file"),
                                 "export preserves its captured text and cancellation never writes")
                }
            }
            let service = Service()
            let island = Window()
            Island.shared.presentationWindow = island
            service.NSApp.keyWindow = island
            service.exportText(suggestedName: "Notes.txt", from: island)
            island.isVisible = false
            Panel.latest?.finish(.cancel)
            Queue.drain()
            suite.expect(island.focusCount == 0 && !service.modalInteractionActive,
                         "closing the island during export does not resurrect its window")
            Panel.latest = nil
            service.exportText(suggestedName: "Hidden.txt", from: island)
            suite.expect(Panel.latest == nil && !service.modalInteractionActive,
                         "an action delivered after its host disappeared cannot open a dialog")
        } catch {
            suite.expect(false, "export fixture completes: \(error)")
        }
    }
}
