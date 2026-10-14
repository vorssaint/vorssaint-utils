// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// Combo mode: the keymap tree, its sibling-key rule and edits, the stored
/// format and its trip through a settings backup, the overlay's navigation,
/// and how the feature is wired into the catalog.
enum ComboModeTests {
    static func run(_ suite: TestSuite) {
        keys(suite)
        lookup(suite)
        validation(suite)
        edits(suite)
        encoding(suite)
        backup(suite)
        navigation(suite)
        keyPresses(suite)
        apps(suite)
        presentation(suite)
        wiring(suite)
    }

    private static let safari = ComboAppReference(bundleID: "com.apple.Safari",
                                                  path: "/Applications/Safari.app")
    private static let notes = ComboAppReference(bundleID: "com.apple.Notes",
                                                 path: "/System/Applications/Notes.app")
    private static let slack = ComboAppReference(bundleID: "com.tinyspeck.slackmacgap",
                                                 path: "/Applications/Slack.app")

    /// root: a → group "Apps" { s → Safari, n → Notes, space → group "Chat" { s → Slack } },
    ///       s → Slack, ` → Notes
    private static func sample() -> ComboKeymap {
        ComboKeymap(nodes: [
            .group(key: "a", label: "Apps", symbol: "app.badge", children: [
                .action(key: "s", label: "Safari", .openApplication(safari)),
                .action(key: "n", label: "Notes", .openApplication(notes)),
                .group(key: " ", label: "Chat", children: [
                    .action(key: "s", label: "Slack", .openApplication(slack)),
                ]),
            ]),
            .action(key: "s", label: "Slack", .openApplication(slack)),
            .action(key: "`", label: "Notes", .openApplication(notes)),
        ])
    }

    // MARK: Keys

    private static func keys(_ suite: TestSuite) {
        suite.expect(["a", "Z", "1", "`", " ", "é", "/", "ß"].allSatisfy(ComboKey.isValid),
               "any single visible character, backtick and space included, is a combo key")
        suite.expect(!ComboKey.isValid("") && !ComboKey.isValid("ab") && !ComboKey.isValid("\t")
                && !ComboKey.isValid("\r") && !ComboKey.isValid("\n") && !ComboKey.isValid("\u{7F}")
                && !ComboKey.isValid("\u{F700}"),
               "empty, multi-character, whitespace other than space, control and arrow keys are refused")
        suite.expect(ComboKey.display(" ") == "␣" && ComboKey.display("a") == "a",
               "space shows as ␣ and other keys as themselves")
        suite.expect(ComboKey.normalized("x") == "x" && ComboKey.normalized(nil) == nil
                && ComboKey.normalized("xy") == nil,
               "a typed string is a key only when it is one valid character")
    }

    // MARK: Lookup

    private static func lookup(_ suite: TestSuite) {
        let keymap = sample()
        suite.expect(keymap.lookup(["s"])?.label == "Slack",
               "a root key reaches its action")
        suite.expect(keymap.lookup(["a", "s"])?.label == "Safari",
               "the same key inside a group reaches the group's own action")
        suite.expect(keymap.lookup(["a", " ", "s"])?.label == "Slack",
               "space works as a key at any depth")
        suite.expect(keymap.lookup(["a"])?.isGroup == true,
               "a key path can stop on a group")
        suite.expect(keymap.lookup(["x"]) == nil && keymap.lookup(["s", "s"]) == nil
                && keymap.lookup([]) == nil,
               "unknown keys, keys past an action and the empty path find nothing")
        suite.expect(keymap.lookup(["A"]) == nil,
               "keys are case sensitive: Shift gives a different key")
        suite.expect(ComboKeymap.match("`", in: keymap.nodes)?.label == "Notes",
               "backtick matches")
        let apps = keymap.lookup(["a"])!
        let chat = keymap.lookup(["a", " "])!
        suite.expect(keymap.parentID(of: chat.id) == .some(apps.id)
                && keymap.parentID(of: apps.id) == .some(nil)
                && keymap.parentID(of: UUID()) == nil,
               "a node's parent is its group, the root, or unknown")
        suite.expect(keymap.children(of: apps.id)?.count == 3 && keymap.children(of: nil)?.count == 3
                && keymap.children(of: keymap.lookup(["s"])!.id) == nil,
               "children are listed for the root and groups, not for actions")
        suite.expect(keymap.nodeCount == 7, "every node in the tree is counted")
    }

    // MARK: Validation

    private static func validation(_ suite: TestSuite) {
        let keymap = sample()
        let apps = keymap.lookup(["a"])!
        let safariNode = keymap.lookup(["a", "s"])!
        suite.expect(keymap.keyIssue("s", parentID: nil, excluding: nil) == .duplicate,
               "a key already used at the root is refused there")
        suite.expect(keymap.keyIssue("s", parentID: apps.id, excluding: safariNode.id) == nil,
               "a node keeps its own key")
        suite.expect(keymap.keyIssue("x", parentID: apps.id, excluding: nil) == nil,
               "a free key is accepted")
        suite.expect(keymap.keyIssue("a", parentID: apps.id, excluding: nil) == nil,
               "the same key may appear in a different group")
        suite.expect(keymap.keyIssue("", parentID: nil, excluding: nil) == .empty
                && keymap.keyIssue("ab", parentID: nil, excluding: nil) == .invalid,
               "empty and unusable keys are reported as such")
        suite.expect(keymap.nextFreeKey(parentID: nil) == "b"
                && keymap.nextFreeKey(parentID: apps.id) == "a",
               "new nodes get the first free suggested key in their level")
        let full = ComboKeymap(nodes: ComboKey.suggestions.map {
            .action(key: $0, label: $0, .openApplication(safari))
        })
        suite.expect(full.nextFreeKey(parentID: nil) == nil,
               "no suggestion is made when every suggested key is taken")
        suite.expect(keymap.nodesWithKeyIssues.isEmpty, "the sample keymap is clean")
        let clash = ComboKeymap(nodes: [
            .action(key: "q", label: "One", .openApplication(safari)),
            .action(key: "q", label: "Two", .openApplication(notes)),
            .action(key: "", label: "Three", .openApplication(notes)),
        ])
        suite.expect(clash.nodesWithKeyIssues == [clash.nodes[1].id, clash.nodes[2].id],
               "an imported clash flags the later sibling and a missing key, not the first holder")
    }

    // MARK: Edits

    private static func edits(_ suite: TestSuite) {
        var keymap = sample()
        let apps = keymap.lookup(["a"])!
        let chat = keymap.lookup(["a", " "])!

        suite.expect(!keymap.insert(.action(key: "s", label: "Dup", .openApplication(notes)), into: nil),
               "insert refuses a key a sibling uses")
        suite.expect(keymap.insert(.action(key: "t", label: "Terminal", .openApplication(notes)),
                                   into: nil, at: 0)
                && keymap.nodes.first?.key == "t",
               "insert places a node at the requested position")
        suite.expect(!keymap.insert(.action(key: "z", label: "Nowhere", .openApplication(notes)),
                                    into: keymap.lookup(["s"])!.id),
               "insert refuses an action as parent")
        suite.expect(!keymap.insert(.action(key: "z", label: "Ghost", .openApplication(notes)), into: UUID()),
               "insert refuses an unknown parent")
        let existing = keymap.lookup(["t"])!
        suite.expect(!keymap.insert(existing, into: apps.id),
               "insert refuses a node id already in the tree")

        suite.expect(keymap.update(id: existing.id) { $0.label = "Term" }
                && keymap.lookup(["t"])?.label == "Term",
               "update changes a label")
        suite.expect(!keymap.update(id: existing.id) { $0.key = "s" } && keymap.lookup(["t"]) != nil,
               "update refuses a key a sibling uses")
        suite.expect(!keymap.update(id: existing.id) { $0.id = UUID() },
               "update may not change a node's id")
        suite.expect(keymap.update(id: chat.id) { $0.key = "c" } && keymap.lookup(["a", "c", "s"]) != nil,
               "update reaches nested nodes")

        // Moves.
        suite.expect(!keymap.move(id: apps.id, to: chat.id),
               "a group cannot move into its own descendant")
        suite.expect(!keymap.move(id: apps.id, to: apps.id),
               "a group cannot move into itself")
        suite.expect(!keymap.move(id: existing.id, to: keymap.lookup(["s"])!.id),
               "nothing moves into an action")
        let slackRoot = keymap.lookup(["s"])!
        suite.expect(!keymap.move(id: slackRoot.id, to: apps.id),
               "a move refuses a key the destination already uses")
        let before = keymap
        suite.expect(keymap.move(id: existing.id, to: chat.id)
                && keymap.lookup(["a", "c", "t"])?.label == "Term"
                && keymap.lookup(["t"]) == nil
                && keymap.nodeCount == before.nodeCount,
               "a node moves into another group and leaves its old level")
        let rootKeys = keymap.nodes.map(\.key)
        let first = keymap.nodes[0]
        suite.expect(keymap.move(id: first.id, to: nil, at: rootKeys.count)
                && keymap.nodes.last?.id == first.id,
               "within a level, an index past the end moves the node last")
        let last = keymap.nodes[keymap.nodes.count - 1]
        suite.expect(keymap.move(id: last.id, to: nil, at: 0) && keymap.nodes.first?.id == last.id,
               "within a level, moving to the front works")
        let middle = keymap.nodes[1]
        suite.expect(keymap.move(id: middle.id, to: nil, at: 3) && keymap.nodes[2].id == middle.id,
               "moving down one place within a level counts the index before removal")

        // Removal.
        let removed = keymap.remove(id: apps.id)
        suite.expect(removed?.children.count == 3 && keymap.lookup(["a"]) == nil
                && keymap.node(id: chat.id) == nil,
               "removing a group removes everything under it")
        suite.expect(keymap.remove(id: UUID()) == nil, "removing an unknown id changes nothing")
    }

    // MARK: Encoding

    private static func encoding(_ suite: TestSuite) {
        let keymap = sample()
        guard let data = keymap.encoded() else {
            suite.expect(false, "the keymap encodes")
            return
        }
        suite.expect(ComboKeymap.decode(data) == keymap,
               "a keymap survives encoding unchanged, ids, keys, labels, icons and actions included")
        let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        suite.expect(json?["version"] as? Int == ComboKeymap.formatVersion,
               "the stored keymap carries its format version")
        let text = String(decoding: data, as: UTF8.self)
        suite.expect(text.contains("\"kind\":\"openApplication\"") && text.contains("com.apple.Safari"),
               "an action is stored by kind with its app")
        suite.expect(ComboKeymap.decode(nil) == nil && ComboKeymap.decode(Data("garbage".utf8)) == nil
                && ComboKeymap.decode(Data("{\"version\":99,\"nodes\":[]}".utf8)) == nil,
               "missing, unreadable and future keymaps are not decoded")
        let lossy = """
        {"version":1,"nodes":[
          {"id":"\(UUID().uuidString)","key":"a","label":"Ok","action":{"kind":"openApplication","app":{"path":"/Applications/Safari.app"}}},
          {"id":"\(UUID().uuidString)","key":"b","label":"Future","action":{"kind":"runShortcut","name":"x"}},
          {"key":"c"},
          {"id":"\(UUID().uuidString)","key":"g","label":"Group","symbol":"folder","children":[
            {"id":"\(UUID().uuidString)","key":"z","label":"Bad","action":{"kind":"nope"}},
            {"id":"\(UUID().uuidString)","key":"y","label":"Fine","action":{"kind":"openApplication","app":{"bundleID":" ","path":"/Applications/Notes.app"}}}
          ]}
        ]}
        """
        let decoded = ComboKeymap.decode(Data(lossy.utf8))
        suite.expect(decoded?.nodes.map(\.key) == ["a", "g"]
                && decoded?.nodes.last?.children.map(\.key) == ["y"],
               "unknown action kinds and broken nodes are skipped, the rest of the keymap is kept")
        if case .action(.openApplication(let app))? = decoded?.nodes.last?.children.first?.content {
            suite.expect(app.bundleID == nil && app.path == "/Applications/Notes.app",
                   "a blank bundle id decodes as none, keeping the path fallback")
        } else {
            suite.expect(false, "the surviving nested action decodes as an app")
        }
        let shared = UUID().uuidString
        let duplicated = """
        {"version":1,"nodes":[
          {"id":"\(shared)","key":"a","label":"One","action":{"kind":"openApplication","app":{"path":"/A.app"}}},
          {"id":"\(shared)","key":"b","label":"Two","action":{"kind":"openApplication","app":{"path":"/B.app"}}}
        ]}
        """
        let unique = ComboKeymap.decode(Data(duplicated.utf8))
        suite.expect(unique?.nodes.count == 2 && unique.map { Set($0.nodes.map(\.id)).count } == 2,
               "duplicate ids in an edited file are made unique so edits hit one node")
        var deep: ComboNode = .action(key: "x", label: "Leaf", .openApplication(safari))
        for _ in 0..<40 { deep = .group(key: "g", label: "Deep", children: [deep]) }
        let tooDeep = ComboKeymap(nodes: [deep]).encoded()
        suite.expect(ComboKeymap.decode(tooDeep).map { $0.nodeCount < 41 } ?? true,
               "absurdly deep nesting is cut off instead of decoded in full")
    }

    // MARK: Backup

    private static func backup(_ suite: TestSuite) {
        let keymap = sample()
        let stored: [String: Any] = [
            DefaultsKey.comboModeEnabled: true,
            DefaultsKey.comboModeTrigger: "control+option:49",
            DefaultsKey.comboModeKeymap: keymap.encoded() as Any,
        ]
        let payload = SettingsBackupSupport.payload(appVersion: "test") { stored[$0] }
        guard let file = try? PropertyListSerialization.data(fromPropertyList: payload, format: .xml, options: 0),
              let read = try? PropertyListSerialization.propertyList(from: file, format: nil) as? [String: Any],
              let restored = SettingsBackupSupport.sanitizedSettings(from: read)
        else {
            suite.expect(false, "a backup with a combo keymap writes and reads back")
            return
        }
        suite.expect(ComboKeymap.decode(restored[DefaultsKey.comboModeKeymap] as? Data) == keymap,
               "the keymap survives a settings backup unchanged")
        suite.expect(restored[DefaultsKey.comboModeTrigger] as? String == "control+option:49"
                && restored[DefaultsKey.comboModeEnabled] as? Bool == true,
               "the trigger and the switch survive a settings backup")
        var tampered = read
        var settings = tampered[SettingsBackupSupport.settingsKey] as? [String: Any] ?? [:]
        settings[DefaultsKey.comboModeKeymap] = Data("not a keymap".utf8)
        tampered[SettingsBackupSupport.settingsKey] = settings
        suite.expect(SettingsBackupSupport.sanitizedSettings(from: tampered)?[DefaultsKey.comboModeKeymap] == nil,
               "an unreadable keymap in a backup is dropped instead of restored")
        settings[DefaultsKey.comboModeKeymap] = "text"
        tampered[SettingsBackupSupport.settingsKey] = settings
        suite.expect(SettingsBackupSupport.sanitizedSettings(from: tampered)?[DefaultsKey.comboModeKeymap] == nil,
               "a keymap of the wrong type in a backup is dropped")
        let cleared = SettingsBackupSupport.payload(appVersion: "test") {
            $0 == DefaultsKey.comboModeTrigger ? ComboTrigger.clearedStorageValue : nil
        }
        let restoredCleared = SettingsBackupSupport.sanitizedSettings(from: cleared)
        suite.expect(restoredCleared?[DefaultsKey.comboModeTrigger] as? String == ComboTrigger.clearedStorageValue,
               "a cleared trigger restores as cleared")
    }

    // MARK: Navigation

    private static func navigation(_ suite: TestSuite) {
        var navigator = ComboNavigator(keymap: sample())
        suite.expect(navigator.currentChildren.count == 3 && navigator.typedKeys.isEmpty,
               "the overlay opens at the root")
        if case .descended(let group) = navigator.press("a") {
            suite.expect(group.label == "Apps" && navigator.typedKeys == ["a"]
                    && navigator.currentChildren.count == 3,
                   "a group key descends and shows the group's keys")
        } else {
            suite.expect(false, "a group key descends")
        }
        suite.expect(navigator.press(" ") == .descended(navigator.keymap.lookup(["a", " "])!)
                && navigator.typedKeys == ["a", " "],
               "space descends into a nested group")
        suite.expect(navigator.back() == .ascended && navigator.typedKeys == ["a"],
               "backspace goes up one level")
        if case .run(.openApplication(let app), let node) = navigator.press("s") {
            suite.expect(app == safari && node.label == "Safari",
                   "an action key in a group runs that group's action")
        } else {
            suite.expect(false, "an action key runs")
        }
        suite.expect(navigator.press("q") == .noMatch && navigator.typedKeys == ["a"],
               "a key with nothing on it is a miss and leaves the path alone")
        suite.expect(navigator.back() == .ascended && navigator.back() == .cancelled,
               "backspace at the root ends the combo")
        var empty = ComboNavigator(keymap: ComboKeymap())
        suite.expect(empty.press("a") == .noMatch && empty.currentChildren.isEmpty,
               "an empty keymap misses every key")
    }

    // MARK: Key presses

    private static func keyPresses(_ suite: TestSuite) {
        func press(_ code: UInt16, _ chars: String?, repeat isRepeat: Bool = false,
                   commandOrControl: Bool = false) -> ComboKeyPress {
            ComboKeyPress.classify(keyCode: code, characters: chars, isRepeat: isRepeat,
                                   hasCommandOrControl: commandOrControl)
        }
        suite.expect(press(ComboKeyPress.escapeKeyCode, "\u{1B}") == .cancel
                && press(ComboKeyPress.escapeKeyCode, "\u{1B}", commandOrControl: true) == .cancel,
               "Escape always cancels")
        suite.expect(press(ComboKeyPress.deleteKeyCode, "\u{7F}") == .back,
               "Backspace goes back")
        suite.expect(press(0, "a") == .key("a") && press(0, "A") == .key("A")
                && press(49, " ") == .key(" ") && press(50, "`") == .key("`"),
               "typed characters are keys as typed, Shift and space included")
        suite.expect(press(0, "a", repeat: true) == .ignore && press(0, "a", commandOrControl: true) == .ignore
                && press(0, "") == .ignore && press(0, nil) == .ignore,
               "key repeats, ⌘ or ⌃ combinations and dead keys are swallowed")
        suite.expect(press(36, "\r") == .unusable("\r") && press(126, "\u{F700}") == .unusable("\u{F700}"),
               "Return and arrows end the combo as misses")
        suite.expect(ComboKeyPress.displayName("\r") == "↩" && ComboKeyPress.displayName("\u{F702}") == "←",
               "unusable keys are named readably in the miss message")
    }

    // MARK: Apps

    private static func apps(_ suite: TestSuite) {
        let found = URL(fileURLWithPath: "/Applications/Safari.app")
        suite.expect(safari.resolvedURL(urlForBundleID: { _ in found }, fileExists: { _ in false }) == found,
               "an app is found by bundle id first")
        let moved = URL(fileURLWithPath: "/Users/me/Apps/Safari.app")
        suite.expect(safari.resolvedURL(urlForBundleID: { _ in moved }, fileExists: { _ in true }) == moved,
               "a moved app is still found by its bundle id")
        suite.expect(safari.resolvedURL(urlForBundleID: { _ in nil }, fileExists: { _ in true })?.path
                    == "/Applications/Safari.app",
               "the saved path is the fallback when the bundle id is unknown")
        suite.expect(safari.resolvedURL(urlForBundleID: { _ in nil }, fileExists: { _ in false }) == nil,
               "a missing app resolves to nothing")
        let noID = ComboAppReference(bundleID: "  ", path: "/Applications/Tool.app")
        suite.expect(noID.bundleID == nil && noID.fallbackName == "Tool",
               "an app without a bundle id keeps its path and file name")
    }

    // MARK: Presentation

    private static func presentation(_ suite: TestSuite) {
        suite.expect(Defaults.registeredDefaults[DefaultsKey.comboModePresentation] as? String
                    == ComboPresentation.centered.rawValue,
               "combo mode opens centered until another place is chosen")
        suite.expect(ComboPresentation.stored(nil) == .centered && ComboPresentation.stored("") == .centered
                && ComboPresentation.stored("sideways") == .centered,
               "a missing or unknown stored place reads as centered")
        suite.expect(ComboPresentation.allCases.allSatisfy { ComboPresentation.stored($0.rawValue) == $0 },
               "every place reads back as stored")
        suite.expect(ComboPresentation.resolved(.island, islandEnabled: true) == .island
                && ComboPresentation.resolved(.island, islandEnabled: false) == .centered,
               "the island is used only while Dynamic Island is on, and the combo is centered otherwise")
        suite.expect(ComboPresentation.resolved(.chip, islandEnabled: false) == .chip
                && ComboPresentation.resolved(.centered, islandEnabled: true) == .centered,
               "the centered panel and the pill do not depend on Dynamic Island")
        suite.expect(ComboPresentation.centered.drawsInKeyPanel
                && !ComboPresentation.island.drawsInKeyPanel && !ComboPresentation.chip.drawsInKeyPanel,
               "only the centered panel draws the keys itself; elsewhere an unseen panel holds the keyboard")

        suite.expect(ComboHintLayout.window(total: 4, limit: 6) == (4, 0)
                && ComboHintLayout.window(total: 6, limit: 6) == (6, 0),
               "a level that fits is listed in full")
        suite.expect(ComboHintLayout.window(total: 7, limit: 6) == (5, 2)
                && ComboHintLayout.window(total: 30, limit: 9) == (8, 22),
               "past the limit the last slot counts the keys left out, so the row keeps its size")
        suite.expect(ComboHintLayout.window(total: 0, limit: 6) == (0, 0)
                && ComboHintLayout.window(total: -3, limit: 6) == (0, 0)
                && ComboHintLayout.window(total: 3, limit: 0) == (0, 3),
               "empty levels and degenerate limits list nothing")

        for value in ComboPresentation.allCases.map(\.rawValue) {
            let payload = SettingsBackupSupport.payload(appVersion: "test") {
                $0 == DefaultsKey.comboModePresentation ? value : nil
            }
            suite.expect(SettingsBackupSupport.sanitizedSettings(from: payload)?[DefaultsKey.comboModePresentation]
                        as? String == value,
                   "the \(value) place survives a settings backup")
        }
        let unknown = SettingsBackupSupport.payload(appVersion: "test") {
            $0 == DefaultsKey.comboModePresentation ? "sideways" : nil
        }
        suite.expect(SettingsBackupSupport.sanitizedSettings(from: unknown)?[DefaultsKey.comboModePresentation] == nil,
               "an unknown place in a backup is dropped instead of restored")

        for language in AppLanguage.allCases {
            let strings = FeatureStrings.comboMode(language)
            suite.expect(![strings.presentationTitle, strings.presentationCentered, strings.presentationIsland,
                           strings.presentationChip, strings.presentationIslandOff].contains { $0.isEmpty },
                   "combo mode names every place in \(language)")
        }
    }

    // MARK: Wiring

    private static func wiring(_ suite: TestSuite) {
        let feature = AppFeature.comboMode
        suite.expect(!feature.installedByDefault, "combo mode is opt-in")
        suite.expect(feature.permissions.isEmpty,
               "combo mode needs no permission: its overlay reads keys itself")
        suite.expect(feature.group == .tools, "combo mode lives with the tools")
        suite.expect(feature.enabledKeys == [DefaultsKey.comboModeEnabled],
               "combo mode's switch is its enabled key")
        suite.expect(!feature.monitorsPermissionChanges(boolFor: { _ in true }),
               "combo mode never polls permissions")
        suite.expect(feature.settingsDestination.page == .comboMode
                && FeatureVisibilitySupport.features(for: .comboMode) == [.comboMode],
               "combo mode has its own Settings page")
        suite.expect(Defaults.registeredDefaults[DefaultsKey.comboModeTrigger] as? String
                    == ComboTrigger.clearedStorageValue
                && ComboTrigger.shortcut(storedValue: ComboTrigger.clearedStorageValue) == nil
                && ComboTrigger.shortcut(storedValue: nil) == nil
                && ComboTrigger.shortcut(storedValue: "garbage") == nil,
               "no trigger shortcut is set until one is recorded")
        suite.expect(ComboTrigger.shortcut(storedValue: "control+option:49") != nil,
               "a recorded trigger reads back")
        suite.expect(GlobalShortcutRole.featuresToSilenceWhileRecording.contains(.comboMode),
               "the trigger steps aside while any shortcut field is recording")
        for language in AppLanguage.allCases {
            let strings = FeatureStrings.comboMode(language)
            suite.expect(String(format: strings.noMatchFormat, "x").contains("x")
                    && String(format: strings.keyDuplicateFormat, "x").contains("x")
                    && String(format: strings.launchFailedFormat, "x").contains("x"),
                   "combo mode formats keep their argument in \(language)")
        }
    }
}
