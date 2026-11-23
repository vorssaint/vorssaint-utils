// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// Pure rules for Quit all apps exceptions, targeting and window focus (issue #855).
enum QuickTogglesQuitAllTests {
    static func run(_ suite: TestSuite) {
        let regular = QuickTogglesSupport.regularActivationPolicy
        let vorssaint = QuickTogglesSupport.vorssaintBundleIdentifiers
        let (finder, phone) = (Defaults.finderBundleIdentifier, Defaults.phoneBundleIdentifier)

        suite.expect(
            QuickTogglesSupport.sanitizedQuitAllExceptions([
                "  com.apple.Safari  ", "com.apple.Safari", finder, "",
                "com.vorssaint.utils", "com.example.Keep", "com.vorssaint.utils.dev",
            ]) == [finder, phone, "com.apple.Safari", "com.example.Keep"],
            "quit-all exceptions lead with Finder and Phone, trim, dedupe and drop Vorssaint ids")

        let exceptions = Set(QuickTogglesSupport.sanitizedQuitAllExceptions(["com.apple.Safari"]))
        func quits(_ id: String?, policy: Int? = nil, terminated: Bool = false) -> Bool {
            QuickTogglesSupport.shouldQuitApp(bundleIdentifier: id, activationPolicyRawValue: policy ?? regular,
                                              isTerminated: terminated, exceptions: exceptions)
        }
        suite.expect(
            quits("com.apple.TextEdit") && !quits("com.apple.Safari") && !quits(finder) && !quits(phone),
            "a regular app outside the list is quit; user exceptions, Finder and Phone are skipped")
        suite.expect(vorssaint.allSatisfy { !exceptions.contains($0) && !quits($0) },
                     "Vorssaint never quits itself, even though it is not in the exception list")
        suite.expect(
            !quits("com.apple.TextEdit", policy: 1) && !quits("com.apple.TextEdit", policy: 2)
                && !quits("com.apple.TextEdit", terminated: true) && !quits(nil) && !quits(""),
            "background, terminated and anonymous apps are skipped")

        func lists(_ id: String?, policy: Int? = nil, terminated: Bool = false) -> Bool {
            QuickTogglesSupport.listsApp(bundleIdentifier: id, activationPolicyRawValue: policy ?? regular,
                                         isTerminated: terminated)
        }
        suite.expect(
            lists("com.apple.Safari") && lists(phone) && !lists(finder)
                && vorssaint.allSatisfy { !lists($0) }
                && !lists("com.apple.TextEdit", policy: 1)
                && !lists("com.apple.TextEdit", terminated: true) && !lists(nil),
            "the window lists regular apps and kept exceptions, never Finder, Vorssaint or hidden apps")

        func app(_ pid: Int32, _ id: String, policy: Int? = nil) -> QuitAppsCandidate {
            QuitAppsCandidate(pid: pid, bundleIdentifier: id, activationPolicyRawValue: policy ?? regular,
                              isTerminated: false)
        }
        let candidates = [
            app(10, "com.apple.TextEdit"), app(11, "com.apple.Safari"), app(12, "com.apple.Notes"),
            app(13, finder), app(14, "com.example.Agent", policy: 1), app(15, "com.vorssaint.utils"),
        ]
        func targets(keeping pid: Int32?) -> [Int32] {
            QuickTogglesSupport.batchQuitTargets(candidates, exceptions: exceptions, keepingPID: pid)
        }
        suite.expect(
            targets(keeping: nil) == [10, 12] && targets(keeping: 12) == [10]
                && targets(keeping: 13) == [10, 12],
            "batch quit hits regular non-exceptions; keeping the front app drops only that process")

        suite.expect(
            [(GlobalShortcutRole.quitAll, DefaultsKey.quitAppsShortcutEnabled),
             (GlobalShortcutRole.quitAllExceptFront, DefaultsKey.quitAppsExceptFrontShortcutEnabled)]
                .allSatisfy { role, enableKey in
                    role.feature == .quitApps && role.requiredEnableKeys == [enableKey]
                        && Defaults.registeredDefaults[enableKey] as? Bool == false
                },
            "both Quit apps shortcuts belong to the feature, have their own enable flag and start off")
        suite.expect(!AppFeature.quitApps.installedByDefault, "Quit apps is not installed by default")
        suite.expect(
            RadialMenuQuickToggle.quitAllApps.feature == .quitApps
                && RadialMenuQuickToggle.emptyTrash.feature == .quickToggles,
            "the Radial slice follows the Quit apps feature, not Quick toggles")
        let exportKeys = SettingsBackupSupport.exportKeys()
        suite.expect(
            [DefaultsKey.quitAppsKeptApps, DefaultsKey.quitAppsShortcut,
             DefaultsKey.quitAppsExceptFrontShortcut].allSatisfy { exportKeys.contains($0) },
            "kept apps and both shortcuts travel in backups")

        // Window buttons and keyboard focus.
        let allButtons: [QuitAppsButton] = [.cancel, .allExceptFront, .all]
        func buttons(_ exceptFront: Bool, _ all: Bool) -> [QuitAppsButton] {
            QuickTogglesSupport.quitAppsButtons(offersExceptFront: exceptFront, canQuitAll: all)
        }
        suite.expect(
            buttons(true, true) == allButtons && buttons(false, true) == [.cancel, .all]
                && buttons(false, false) == [.cancel],
            "Cancel is always offered; batch buttons only when they would do something")
        suite.expect(
            QuickTogglesSupport.restingQuitAppsButton(scope: .allExceptFront, buttons: allButtons)
                == .allExceptFront
                && QuickTogglesSupport.restingQuitAppsButton(scope: .allExceptFront, buttons: [.cancel, .all])
                == .cancel
                && QuickTogglesSupport.restingQuitAppsButton(scope: nil, buttons: allButtons) == .cancel,
            "Return rests on the scope's button, else Cancel")

        let rows: [Int32] = [1, 2, 3]
        let resting = QuitAppsButton.allExceptFront
        func move(_ focus: QuitAppsFocus, _ step: QuitAppsMove, rows moveRows: [Int32]? = nil) -> QuitAppsFocus {
            QuickTogglesSupport.movedQuitAppsFocus(
                focus, step, rows: moveRows ?? rows, buttons: allButtons, resting: resting)
        }
        suite.expect(
            move(.row(1), .up) == .row(1) && move(.row(2), .up) == .row(1) && move(.row(2), .down) == .row(3),
            "Up and Down move one row and stop at the top")
        suite.expect(
            move(.row(3), .down) == .button(resting) && move(.row(1), .next) == .button(resting),
            "Down past the last row, or Tab from a row, lands on the resting button")
        suite.expect(
            move(.button(.cancel), .right) == .button(.allExceptFront)
                && move(.button(.cancel), .left) == .button(.cancel)
                && move(.button(.all), .right) == .button(.all),
            "Left and Right step between buttons and clamp at the ends")
        suite.expect(
            move(.button(.all), .next) == .button(.cancel) && move(.button(.cancel), .previous) == .button(.all),
            "Tab and Shift-Tab wrap around the button row")
        suite.expect(
            move(.button(.all), .up) == .row(3) && move(.button(.cancel), .up, rows: []) == .button(.cancel),
            "Up from a button goes to the last row, or stays put with no rows")

        func afterChange(_ focus: QuitAppsFocus, to newRows: [Int32],
                         buttons newButtons: [QuitAppsButton]? = nil) -> QuitAppsFocus {
            QuickTogglesSupport.quitAppsFocusAfterListChange(
                focus, previousRows: rows, rows: newRows, buttons: newButtons ?? allButtons,
                resting: newButtons == nil ? resting : .cancel)
        }
        suite.expect(
            afterChange(.row(2), to: [2, 3]) == .row(2) && afterChange(.row(2), to: [1, 3]) == .row(3)
                && afterChange(.row(3), to: [1, 2]) == .row(2),
            "a listed row keeps focus; a vanished one hands it to the row now at its index")
        suite.expect(afterChange(.row(2), to: []) == .button(resting), "with no rows left, Return rests on a button")
        suite.expect(
            afterChange(.button(.allExceptFront), to: rows, buttons: [.cancel, .all]) == .button(.cancel)
                && afterChange(.button(.all), to: [1]) == .button(.all),
            "a focused button keeps focus while offered, else hands it to the resting button")

        let named: [(pid: Int32, name: String)] = [
            (pid: 1, name: "Safari"), (pid: 2, name: "Zen"), (pid: 3, name: "\u{00C9}clair"),
            (pid: 4, name: "Notes"), (pid: 5, name: "Numbers"), (pid: 6, name: "zed"),
        ]
        func jump(_ prefix: String, in list: [(pid: Int32, name: String)]? = nil) -> Int32? {
            QuickTogglesSupport.quitAppsRow(matching: prefix, in: list ?? named)
        }
        suite.expect(jump("SAF") == 1 && jump("ecl") == 3 && jump("nu") == 5,
                     "type-to-jump matches a prefix ignoring case and diacritics")
        suite.expect(jump("z") == 2 && jump("n") == 4, "with several matches the first row in list order wins")
        suite.expect(
            jump("x") == nil && jump("") == nil && jump("s", in: []) == nil,
            "no match, an empty prefix or an empty list jumps nowhere")
    }
}
