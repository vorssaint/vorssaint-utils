// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

typealias EmojiQueryHabits = CommandBarQueryHabits

/// Catalog, action and learning bodies are extracted from production. Only
/// permissions, panel visibility, typing and the installation key are replaced;
/// no keyboard events are sent and preferences live in a disposable domain.
enum CommandBarEmojiContract {
    enum UserDefaults { static var standard: Foundation.UserDefaults! }
    final class Permissions {
        static let shared = Permissions()
        var accessibility = true
    }
    struct CommandBarEntry {
        enum Icon { case symbol(String) }
        enum Trouble { case needsPermission }
        let id: String
        let title: String
        let subtitle: String
        let keywords: String
        let icon: Icon
        let trouble: Trouble?
        let matchTitle: String?
        let run: (Int?) -> Void
        var countsUsage = true
        var keepsBarOpen = false
    }
    enum Catalog {
        typealias CommandBarEntry = CommandBarEmojiContract.CommandBarEntry
        typealias UserDefaults = CommandBarEmojiContract.UserDefaults
        typealias Permissions = CommandBarEmojiContract.Permissions
        static var typed: [String] = []
        static func typeAtCursor(_ text: String) { typed.append(text) }
    }
    typealias CommandBarCatalog = Catalog
    enum CommandBarQueryHabits {
        typealias PreparationCache = EmojiQueryHabits.PreparationCache
        static let key = Data(repeating: 7, count: 32)
        static func prepare(_ query: String, cache: inout PreparationCache) -> EmojiQueryHabits.PreparedQuery {
            EmojiQueryHabits.prepare(query, key: key, cache: &cache)
        }
        static func encode(_ store: EmojiQueryHabits.Store) -> String? { EmojiQueryHabits.encode(store) }
    }
    final class Service {
        typealias CommandBarEntry = CommandBarEmojiContract.CommandBarEntry
        typealias UserDefaults = CommandBarEmojiContract.UserDefaults
        typealias CommandBarCatalog = CommandBarEmojiContract.Catalog
        typealias CommandBarQueryHabits = CommandBarEmojiContract.CommandBarQueryHabits
        enum Mode { case search, argument, actions }
        var mode = Mode.search
        var query = ":thumb"
        var savedQuery = ""
        var queryBeforeCompletion: String?
        var queryMemoryStep = 0
        var queryMemory = CommandBarQueryMemory()
        var queryHabitStore = CommandBarQueryHabitStoreCache()
        var preparedHabitQuery = CommandBarQueryHabits.PreparationCache()
        var isVisible = true
        var usageCache: [String: CommandBarUse] = [:]
        var queryWhenRun = ""
        var selectionWhenRun = ""
        var selectedText = ""
        func hide() { isVisible = false; query = ""; savedQuery = "" }
    }

    static func run(_ suite: TestSuite) {
        let domain = "com.vorssaint.tests.command-bar-emoji"
        let defaults = Foundation.UserDefaults(suiteName: domain)!
        defaults.removePersistentDomain(forName: domain)
        UserDefaults.standard = defaults
        defer {
            UserDefaults.standard = nil
            defaults.removePersistentDomain(forName: domain)
            Catalog.typed = []
        }
        let tones = CommandBarEmoji.SkinTone.allCases
        suite.expect(!CommandBarEmoji.acceptsSkinTone("👪")
                     && tones.allSatisfy { CommandBarEmoji.applying($0, to: "👪") == "👪" },
                     "family stays unchanged instead of offering unsupported skin tones")
        suite.expect(["👍", "☝️", "🤝", "👫", "👬", "👭", "💏", "💑"].allSatisfy {
            CommandBarEmoji.acceptsSkinTone($0)
        }, "excluding family preserves supported single-person and multi-person tones")

        // Exercise actual row construction, not just the helper used for IDs.
        let originalIDs = CommandBarEmoji.emoji.map { "emoji." + $0.identity }
        let thumbID = "emoji.👍"
        defaults.set(CommandBarPreferences.encodePins([thumbID]), forKey: DefaultsKey.commandBarPins)
        let pins = defaults.string(forKey: DefaultsKey.commandBarPins)
        for tone in tones {
            defaults.set(tone.rawValue, forKey: DefaultsKey.commandBarEmojiSkinTone)
            let rows = Catalog.emojiEntries(bar: .enUS)
            suite.expect(rows.map(\.id) == originalIDs,
                         "\(tone.rawValue) keeps every stored row identity")
            Catalog.typed = []
            rows.forEach { $0.run(nil) }
            suite.expect(zip(rows, Catalog.typed).allSatisfy { $0.title.hasPrefix($1 + "  ") },
                         "\(tone.rawValue) inserts exactly the emoji shown by each row")
            let family = rows.first { $0.id == "emoji.👪" }!
            suite.expect(Service().skinToneActions(for: family).isEmpty,
                         "family has no unsupported alternate actions")
            let thumb = rows.first { $0.id == thumbID }!
            let service = Service()
            let actions = service.skinToneActions(for: thumb)
            suite.expect(actions.count == 5 && Set(actions.map(\.title)).count == 5,
                         "each default offers the other five distinct tones")
            suite.expect(!actions.contains { $0.title == CommandBarEmoji.applying(tone, to: "👍") },
                         "the current default is not duplicated as an alternate")
            for action in actions {
                defaults.removeObject(forKey: DefaultsKey.commandBarUsage)
                defaults.removeObject(forKey: DefaultsKey.commandBarQueryHabits)
                service.mode = .actions
                service.savedQuery = ":thumb"
                service.query = ""
                service.isVisible = true
                action.run()
                let usage = CommandBarUsage.decode(defaults.string(forKey: DefaultsKey.commandBarUsage))
                suite.expect(usage[thumbID]?.count == 1 && usage.count == 1,
                             "a one-off tone records exactly one use under the original emoji")
                suite.expect(service.queryMemory.boost(query: "thumb", id: thumbID) > 0,
                             "a one-off tone learns the search saved before opening actions")
                let habits = EmojiQueryHabits.decode(defaults.string(forKey: DefaultsKey.commandBarQueryHabits))
                suite.expect(EmojiQueryHabits.boost(
                    for: thumbID,
                    preparedQuery: EmojiQueryHabits.prepare("thumb", key: CommandBarQueryHabits.key),
                    store: habits, now: Date().timeIntervalSince1970) > 0,
                             "a one-off tone persists learned searches when the installation key is ready")
                suite.expect(!service.isVisible && Catalog.typed.last == action.title,
                             "the one-off action closes the bar and inserts the chosen tone")
                suite.expect(defaults.string(forKey: DefaultsKey.commandBarEmojiSkinTone) == tone.rawValue
                             && defaults.string(forKey: DefaultsKey.commandBarPins) == pins,
                             "one-off insertion preserves the default tone and stored pins")
            }
            // A different preference may change after the one-off insertion.
            defaults.set("emoji", forKey: DefaultsKey.commandBarDisabledSources)
            defaults.set("", forKey: DefaultsKey.commandBarDisabledSources)
            let reopened = Catalog.emojiEntries(bar: .enUS).first { $0.id == thumbID }!
            reopened.run(nil)
            suite.expect(Catalog.typed.last == CommandBarEmoji.applying(tone, to: "👍"),
                         "reopening after another preference change still uses the saved default")
        }

        defaults.removeObject(forKey: DefaultsKey.commandBarUsage)
        let row = Catalog.emojiEntries(bar: .enUS).first { $0.id == thumbID }!
        let normal = Service()
        normal.finish(row, value: nil)
        suite.expect(CommandBarUsage.decode(defaults.string(forKey: DefaultsKey.commandBarUsage))[thumbID]?.count == 1
                     && normal.queryMemory.boost(query: "thumb", id: thumbID) == 1
                     && !normal.isVisible,
                     "normal insertion still records usage and learning once before closing")
        let shortcut = Service()
        shortcut.isVisible = false
        shortcut.query = ""
        shortcut.finish(row, value: nil)
        suite.expect(shortcut.queryMemory == CommandBarQueryMemory()
                     && CommandBarUsage.decode(defaults.string(forKey: DefaultsKey.commandBarUsage))[thumbID]?.count == 2,
                     "a hidden shortcut counts usage without learning an unseen search")
        let argument = Service()
        argument.mode = .argument
        argument.savedQuery = "original"
        argument.query = "42"
        argument.finish(row, value: 42)
        suite.expect(argument.queryMemory.boost(query: "original", id: thumbID) == 1
                     && argument.queryMemory.boost(query: "42", id: thumbID) == 0,
                     "argument execution keeps learning from the saved search")
        var transient = row
        transient.countsUsage = false
        transient.keepsBarOpen = true
        let before = defaults.string(forKey: DefaultsKey.commandBarUsage)
        let open = Service()
        open.finish(transient, value: nil)
        suite.expect(open.isVisible && open.queryMemoryStep == 0
                     && defaults.string(forKey: DefaultsKey.commandBarUsage) == before,
                     "non-learning rows and commands that keep the bar open retain their behavior")

        let payload = SettingsBackupSupport.payload(appVersion: "test", valueFor: defaults.object(forKey:))
        let restored = SettingsBackupSupport.sanitizedSettings(from: payload)
        suite.expect(restored?[DefaultsKey.commandBarEmojiSkinTone] as? String == "dark",
                     "the chosen tone survives backup export and restore validation")
    }
}
