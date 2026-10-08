// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Carbon.HIToolbox
import Foundation
import SwiftUI

typealias EmojiQueryHabits = CommandBarQueryHabits

/// Catalog, action and learning bodies are extracted from production. Only
/// permissions, panel visibility, typing and the session key are replaced;
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
    }
    final class NotchService {
        static let shared = NotchService()
        var reactions: [NotchMascotReaction] = []
        func reactMascot(_ reaction: NotchMascotReaction, after delay: TimeInterval = 0) { reactions.append(reaction) }
    }
    final class Service {
        typealias NotchService = CommandBarEmojiContract.NotchService
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
        var farewell = NotchMascotMood.idle
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
                service.queryHabitStore.forgetAll()
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
                suite.expect(EmojiQueryHabits.boost(
                    for: thumbID,
                    preparedQuery: EmojiQueryHabits.prepare("thumb", key: CommandBarQueryHabits.key),
                    store: service.queryHabitStore.store, now: Date().timeIntervalSince1970) > 0,
                             "a one-off tone learns searches in memory for the current session")
                suite.expect(defaults.object(forKey: DefaultsKey.commandBarQueryHabits) == nil,
                             "a one-off tone never persists query learning in preferences")
                suite.expect(Service().queryHabitStore.store.isEmpty,
                             "a new service starts without the previous session's query learning")
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
        NotchService.shared.reactions = []
        normal.finish(row, value: nil)
        suite.expect(CommandBarUsage.decode(defaults.string(forKey: DefaultsKey.commandBarUsage))[thumbID]?.count == 1
                     && normal.queryMemory.boost(query: "thumb", id: thumbID) == 1
                     && !normal.isVisible,
                     "normal insertion still records usage and learning once before closing")
        suite.expect(normal.farewell == .happy && NotchService.shared.reactions == [.celebrate],
                     "a command run from the bar sends the companion home smiling, to hop for it")
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
        NotchService.shared.reactions = []
        open.finish(transient, value: nil)
        suite.expect(NotchService.shared.reactions.isEmpty,
                     "a command that keeps the bar open sends the companion nowhere")
        suite.expect(open.isVisible && open.queryMemoryStep == 0
                     && defaults.string(forKey: DefaultsKey.commandBarUsage) == before,
                     "non-learning rows and commands that keep the bar open retain their behavior")

        let payload = SettingsBackupSupport.payload(appVersion: "test", valueFor: defaults.object(forKey:))
        let restored = SettingsBackupSupport.sanitizedSettings(from: payload)
        suite.expect(restored?[DefaultsKey.commandBarEmojiSkinTone] as? String == "dark",
                     "the chosen tone survives backup export and restore validation")

        EmojiGridContract.run(suite)
    }
}

/// The grid's own arithmetic, pinned without touching the real service: the
/// tile sizes a preference reads back as, the column counts the layout
/// derives from them, and the two-dimensional walk the arrow keys ride.
enum EmojiGridContract {
    static func run(_ suite: TestSuite) {
        suite.run("emoji grid sizes") {
            suite.expect(CommandBarEmojiTileSize.resolved(raw: nil) == .medium,
                         "a missing tile size reads as the medium default")
            suite.expect(CommandBarEmojiTileSize.resolved(raw: "") == .medium,
                         "an empty tile size reads as the medium default")
            suite.expect(CommandBarEmojiTileSize.resolved(raw: "bogus") == .medium,
                         "an unknown tile size reads as the medium default")
            suite.expect(CommandBarEmojiTileSize.resolved(raw: "large") == .large
                         && CommandBarEmojiTileSize.resolved(raw: "small") == .small,
                         "a known tile size reads back as itself")
            suite.expect(CommandBarEmojiTileSize.allCases.allSatisfy { $0.tileSize > $0.glyphSize },
                         "every tile leaves room for its caption beside the glyph")
            let columns = CommandBarEmojiTileSize.allCases.map { size in
                CommandBarEmojiTileSize.columns(availableWidth: 560, tileSize: size)
            }
            suite.expect(columns == [7, 5, 4],
                         "the panel fits fewer columns as the tiles grow: got \(columns)")
            let smallWithLegacyScroller = CommandBarEmojiTileSize.columns(
                availableWidth: 545, tileSize: .small)
            suite.expect(smallWithLegacyScroller == 6,
                         "small tiles use the viewport width left by a legacy scroller")
            let mediumTileHeight = CommandBarEmojiTileSize.medium.glyphSize + 49
            let height14 = CommandBarEmojiTileSize.contentHeight(
                itemCount: 14, columns: 5, tileHeight: mediumTileHeight)
            let height15 = CommandBarEmojiTileSize.contentHeight(
                itemCount: 15, columns: 5, tileHeight: mediumTileHeight)
            let height25 = CommandBarEmojiTileSize.contentHeight(
                itemCount: 25, columns: 5, tileHeight: mediumTileHeight)
            let height15WithPermissionHint = CommandBarEmojiTileSize.contentHeight(
                itemCount: 15, columns: 5, tileHeight: mediumTileHeight, headerHeight: 24)
            suite.expect(height14 == height15 && height15 < height25 && height25 < 452,
                         "14–25 medium matches size the panel by three to five tile rows")
            suite.expect(height15WithPermissionHint == height15 + 24,
                         "the permission notice is included in the grid's measured height")
            suite.expect(CommandBarEmojiTileSize.contentHeight(
                             itemCount: 26, columns: 5, tileHeight: mediumTileHeight) > 452,
                         "a grid taller than the ceiling scrolls instead of growing the panel")
        }

        suite.run("emoji grid arrow modifiers") {
            suite.expect(CommandBarEmojiGridNavigation.consumesHorizontalArrow(
                             gridIsNavigable: true, modifiersPresent: false,
                             queryIsEmpty: true),
                         "bare horizontal arrows walk the grid")
            suite.expect(CommandBarEmojiGridNavigation.consumesHorizontalArrow(
                             gridIsNavigable: true, modifiersPresent: true,
                             queryIsEmpty: true),
                         "modified arrows walk an empty grid while shortcut modifiers are released")
            suite.expect(CommandBarEmojiGridNavigation.consumesHorizontalArrow(
                             gridIsNavigable: true, modifiersPresent: false,
                             queryIsEmpty: false),
                         "bare arrows keep walking a filtered grid")
            suite.expect(!CommandBarEmojiGridNavigation.consumesHorizontalArrow(
                             gridIsNavigable: true, modifiersPresent: true,
                             queryIsEmpty: false)
                         && !CommandBarEmojiGridNavigation.consumesHorizontalArrow(
                             gridIsNavigable: false, modifiersPresent: false,
                             queryIsEmpty: true),
                         "modified arrows edit populated text, and a closed grid does not consume arrows")
        }

        suite.run("emoji grid walk") {
            let columns = 5
            let count = 13 // five, five, three: the last row stops early.
            // Straight line moves.
            suite.expect(CommandBarEmojiTileSize.gridTarget(from: 7, dx: 1, dy: 0, columns: columns, count: count) == 8,
                         "Right steps over one tile")
            suite.expect(CommandBarEmojiTileSize.gridTarget(from: 7, dx: -1, dy: 0, columns: columns, count: count) == 6,
                         "Left steps back one tile")
            suite.expect(CommandBarEmojiTileSize.gridTarget(from: 4, dx: 1, dy: 0, columns: columns, count: count) == 4,
                         "Right at the row's end holds instead of wrapping")
            suite.expect(CommandBarEmojiTileSize.gridTarget(from: 5, dx: -1, dy: 0, columns: columns, count: count) == 5,
                         "Left at the row's start holds instead of wrapping")
            suite.expect(CommandBarEmojiTileSize.gridTarget(from: 7, dx: 0, dy: -1, columns: columns, count: count) == 2,
                         "Up jumps a whole row, column-true")
            suite.expect(CommandBarEmojiTileSize.gridTarget(from: 7, dx: 0, dy: 1, columns: columns, count: count) == 12,
                         "Down into a short last row lands on its own column")
            suite.expect(CommandBarEmojiTileSize.gridTarget(from: 11, dx: 0, dy: 1, columns: columns, count: count) == 12,
                         "Down from the last row's middle stops at its last tile, column-true")
            suite.expect(CommandBarEmojiTileSize.gridTarget(from: 2, dx: 0, dy: -1, columns: columns, count: count) == 0,
                         "Up from the first row stops at the top")
            suite.expect(CommandBarEmojiTileSize.gridTarget(from: 12, dx: 0, dy: 1, columns: columns, count: count) == 12,
                         "Down at the bottom holds")
            suite.expect(CommandBarEmojiTileSize.gridTarget(from: 11, dx: 1, dy: 0, columns: columns, count: count) == 12,
                         "Right within the short last row reaches its own end")
            suite.expect(CommandBarEmojiTileSize.gridTarget(from: 12, dx: 1, dy: 0, columns: columns, count: count) == 12,
                         "Right at the short last row's end holds instead of naming an absent tile")
            suite.expect(CommandBarEmojiTileSize.gridTarget(from: 10, dx: -1, dy: 0, columns: columns, count: count) == 10,
                         "Left at the short last row's start holds, as at any row's start")
            // The degenerate inputs the walk tolerates.
            suite.expect(CommandBarEmojiTileSize.gridTarget(from: 7, dx: 0, dy: 0, columns: columns, count: count) == 7,
                         "no step lands nowhere")
            suite.expect(CommandBarEmojiTileSize.gridTarget(from: 7, dx: 1, dy: 1, columns: columns, count: count) == 13 - 1,
                         "a diagonal is clamped into the row range")
            suite.expect(CommandBarEmojiTileSize.gridTarget(from: 0, dx: 1, dy: 0, columns: 0, count: count) == 0,
                         "a zero-column layout never moves the selection")
            suite.expect(CommandBarEmojiTileSize.gridTarget(from: 0, dx: 1, dy: 0, columns: columns, count: 0) == 0,
                         "an empty grid never moves the selection")
        }

        suite.run("emoji take-over") {
            let space = GlobalShortcut.commandBarEmojiDefault
            // The picker's own ⌃⌘Space is macOS's until the person agrees to
            // have it: the recorder must ask, never save it as an ordinary key.
            let pickerLive = [LiveSystemShortcut(id: 50, shortcut: space, enabled: true)]
            let pickerIsMacOS = SystemShortcutTakeoverSupport.conflictsWithMacOS(
                space, liveEntries: pickerLive, symbolicHotKeys: nil, held: [],
                role: .commandBarEmoji)
            suite.expect(pickerIsMacOS
                         && GlobalShortcut.conflictsWithSystemShortcut(
                            space, liveEntries: pickerLive, symbolicHotKeys: nil,
                            role: .commandBarEmoji),
                         "the system picker's combination is macOS's until a take-over is agreed")
            suite.expect(SystemShortcutTakeoverSupport.recorderDecision(
                          shortcut: space, conflictsWithMacOS: pickerIsMacOS,
                          takenOver: false, current: space) == .offer,
                          "recording the picker's combination is always an offer, never a silent save")
            let custom = GlobalShortcut(keyCode: Int64(kVK_ANSI_A), modifiers: [.command])
            suite.expect(SystemShortcutTakeoverSupport.recorderDecision(
                          shortcut: space, conflictsWithMacOS: pickerIsMacOS,
                          takenOver: false, current: custom) == .offer,
                          "resetting a custom key to the picker default asks before taking it over")
            suite.expect(GlobalShortcutRole.commandBarEmoji.supportsTakeOver,
                         "the emoji row is a claimant, so it may take a macOS key over")
            // Once accepted, the key the claim holds stays the row's own: a
            // re-recording of the same combination asks nothing and keeps the
            // opt-in, and the claim still names the picker's id so release
            // hands ⌃⌘Space back.
            let pickerHeld = [LiveSystemShortcut(id: 50, shortcut: space, enabled: false)]
            suite.expect(SystemShortcutTakeoverSupport.conflictsWithMacOS(
                         space, liveEntries: pickerHeld, symbolicHotKeys: nil, held: [50],
                         role: .commandBarEmoji),
                         "a picker key this app holds still counts as macOS's for a fresh recording")
            suite.expect(SystemShortcutTakeoverSupport.recorderDecision(
                         shortcut: space, conflictsWithMacOS: true, takenOver: true,
                         current: space) == .save(clearTakeOver: false),
                         "re-recording the accepted key keeps the take-over instead of dropping it")
            suite.expect(SystemShortcutTakeoverSupport.ids(matching: space, in: pickerHeld) == [50],
                         "the emoji claim resolves to exactly the picker's id, so release restores it")
        }

        suite.run("emoji arming") {
            let space = GlobalShortcut.commandBarEmojiDefault
            // The rule the recorder's offer and the sync path share: a
            // combination macOS answers arms only through an agreed take-over,
            // whatever surface asks for the key.
            suite.expect(!SystemShortcutTakeoverSupport.emojiShortcutMayArm(
                         conflictsWithMacOS: true, takenOver: false),
                         "a macOS key never arms without the agreed take-over")
            suite.expect(SystemShortcutTakeoverSupport.emojiShortcutMayArm(
                         conflictsWithMacOS: true, takenOver: true),
                         "an agreed take-over keeps the key armed")
            suite.expect(SystemShortcutTakeoverSupport.emojiShortcutMayArm(
                         conflictsWithMacOS: false, takenOver: false),
                         "a key macOS does not answer arms freely")
            // The bare table check is what made the two arming paths disagree:
            // a key the app itself holds reads free there, while the
            // take-over-aware question — the one the sync path must ask —
            // still names it macOS's.
            let held = [LiveSystemShortcut(id: 50, shortcut: space, enabled: false)]
            suite.expect(!GlobalShortcut.conflictsWithSystemShortcut(
                             space, liveEntries: held, symbolicHotKeys: nil,
                             role: .commandBarEmoji)
                         && SystemShortcutTakeoverSupport.conflictsWithMacOS(
                             space, liveEntries: held, symbolicHotKeys: nil,
                             held: [50], role: .commandBarEmoji),
                         "a held system key reads free to the bare table check, and macOS's to the armed one")
        }

        suite.run("emoji drain snapshot race") {
            // The real tap bodies run against a stub state: no tap, no
            // keyboard, no run loop. A captured key must stay drained after
            // its handler ends, until its repeat/release or a watchdog answer.
            func key(_ down: Bool, _ code: Int64) -> CGEvent {
                CGEvent(keyboardEventSource: nil, virtualKey: CGKeyCode(code), keyDown: down)!
            }
            let returnCode = Int64(kVK_Return)
            let escapeCode = Int64(kVK_Escape)

            let tap = ShortcutRecordingTapContract.Host()
            var capturedKeys: [Int64] = []
            tap.handler = { keyCode, _, _ in
                capturedKeys.append(keyCode)
                tap.end()
            }
            let escapeDown = key(true, escapeCode)
            let escapeUp = key(false, escapeCode)
            suite.expect(
                tap.handle(type: .keyDown, event: escapeDown) == nil
                    && capturedKeys == [escapeCode]
                    && tap.drainingKeyCode == escapeCode,
                "the capture handles Escape and keeps its held key inside the tap")
            let escapeRepeat = key(true, escapeCode)
            escapeRepeat.setIntegerValueField(.keyboardEventAutorepeat, value: 1)
            suite.expect(
                tap.handle(type: .keyDown, event: escapeRepeat) == nil
                    && tap.drainingKeyCode == escapeCode
                    && tap.handle(type: .keyUp, event: escapeUp) == nil
                    && tap.drainingKeyCode == nil
                    && tap.tearDownCalls == 1,
                "the recorded key's repeat and release drain before the tap is removed")

            // A fresh held-key event invalidates the watchdog's in-flight
            // snapshot; a stale answer must not end the drain mid-hold.
            let racingTap = ShortcutRecordingTapContract.Host()
            racingTap.handler = { _, _, _ in racingTap.end() }
            racingTap.handle(type: .keyDown, event: key(true, returnCode))
            let asked = racingTap.drainGeneration
            let repeatDown = key(true, returnCode)
            repeatDown.setIntegerValueField(.keyboardEventAutorepeat, value: 1)
            suite.expect(
                racingTap.handle(type: .keyDown, event: repeatDown) == nil
                    && racingTap.drainGeneration == asked + 1,
                "a repeat of the draining key re-earns the drain and invalidates a snapshot")
            racingTap.applyKeyboardSnapshot(
                keyIsDown: [returnCode: false], draining: returnCode,
                generation: asked)
            suite.expect(
                racingTap.drainingKeyCode == returnCode && racingTap.watchdogArms >= 2,
                "a stale answer cannot clear a key that was pressed again")
            racingTap.applyKeyboardSnapshot(
                keyIsDown: [returnCode: false], draining: returnCode,
                generation: asked + 1)
            suite.expect(
                racingTap.drainingKeyCode == nil && racingTap.tap == nil
                    && racingTap.drainGeneration == asked + 2,
                "the current snapshot clears the lost release and stands the tap down")

            // An unrelated key never changes the held key's snapshot.
            let bystander = ShortcutRecordingTapContract.Host()
            bystander.drainingKeyCode = returnCode
            let askedBystander = bystander.drainGeneration
            suite.expect(
                bystander.handle(type: .keyDown, event: key(true, Int64(kVK_ANSI_A))) != nil
                    && bystander.drainGeneration == askedBystander,
                "a press the drain does not owe passes through without changing its snapshot")
        }

        suite.run("emoji fallback drain") {
            // The panel-monitor twin of the tap drain, used when Accessibility
            // does not allow the event tap to exist.
            let returnCode = Int64(kVK_Return)
            var router = CommandBarRowShortcuts.FallbackKeyRouter()
            suite.expect(
                router.routeDown(keyCode: returnCode, captureIsActive: true,
                                 isRepeat: false) == .record && !router.isEmpty,
                "the capture handles a fresh press and records its held-key debt")
            suite.expect(
                router.routeDown(keyCode: returnCode, captureIsActive: false,
                                 isRepeat: true) == .swallow,
                "a held key's repeat stays suppressed after capture ends")
            suite.expect(
                router.swallowsUp(returnCode) && router.isEmpty,
                "the held key's release is swallowed and settles its debt")

            // The debt crosses a second capture if the key is still held.
            var carried = CommandBarRowShortcuts.FallbackKeyRouter()
            carried.routeDown(keyCode: returnCode, captureIsActive: true, isRepeat: false)
            suite.expect(
                carried.routeDown(keyCode: returnCode, captureIsActive: true,
                                  isRepeat: true) == .swallow
                    && carried.swallowsUp(returnCode) && carried.isEmpty,
                "the repeat and release remain paired across a new capture")
            suite.expect(
                carried.routeDown(keyCode: returnCode, captureIsActive: true,
                                  isRepeat: false) == .record,
                "a fresh press after the release belongs to the new capture")

            // If a keyUp was lost, a new press is fresh and clears only its
            // stale debt rather than being swallowed.
            var lost = CommandBarRowShortcuts.FallbackKeyRouter()
            lost.routeDown(keyCode: returnCode, captureIsActive: true, isRepeat: false)
            suite.expect(
                lost.routeDown(keyCode: returnCode, captureIsActive: false,
                               isRepeat: false) == .record && lost.isEmpty,
                "a fresh press steps aside from a stale held-key debt")

            var twoHeld = CommandBarRowShortcuts.FallbackKeyRouter()
            let leftCode = Int64(kVK_LeftArrow)
            twoHeld.routeDown(keyCode: returnCode, captureIsActive: true, isRepeat: false)
            twoHeld.routeDown(keyCode: leftCode, captureIsActive: true, isRepeat: false)
            suite.expect(
                twoHeld.swallowsUp(returnCode) && !twoHeld.isEmpty
                    && twoHeld.swallowsUp(leftCode) && twoHeld.isEmpty,
                "each release settles only its own captured key")
        }
    }
}
