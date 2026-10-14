// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit

/// These tests use only isolated preferences and in-memory windows. They never
/// write global spacing, synthesize input, or change the real menu bar.
enum MenuBarOrganizerTests {
    static func run(_ suite: TestSuite) {
        suite.expect(!MenuBarOrganizerPolicy.isOpenMenuWindow(level: 24, popupLevel: 101, isStatusItem: false, alpha: 1),
                     "the persistent main menu bar does not block native moves")
        suite.expect(!MenuBarOrganizerPolicy.isOpenMenuWindow(level: 101, popupLevel: 101, isStatusItem: true, alpha: 1),
                     "a known hosted status item is not an open popup")
        suite.expect(MenuBarOrganizerPolicy.isOpenMenuWindow(level: 101, popupLevel: 101, isStatusItem: false, alpha: 1),
                     "an actual visible popup still blocks movement")
        suite.expect(!MenuBarOrganizerPolicy.isOpenMenuWindow(level: 101, popupLevel: 101, isStatusItem: false, alpha: 0),
                     "a transparent dismissed popup does not block movement")
        let screen = CGRect(x: 0, y: 0, width: 1_920, height: 1_080)
        let leftScreen = CGRect(x: -1_920, y: 0, width: 1_920, height: 1_080)
        let upperScreen = CGRect(x: 0, y: -1_080, width: 1_920, height: 1_080)
        let divider = CGRect(x: -1_100, y: 0, width: 2_000, height: 24)
        func record(_ id: UInt32, x: CGFloat, y: CGFloat = 0, onScreen: Bool = true) -> MenuBarOrganizerWindowRecord {
            .init(windowID: id, ownerPID: 1, ownerName: "Test", ownerBundleIdentifier: "test.app",
                  title: "same", frame: CGRect(x: x, y: y, width: 24, height: 24),
                  layer: 25, alpha: 1, isOnScreen: onScreen)
        }
        let visible = record(1, x: 1_200)
        let mirrored = record(2, x: -800)
        let offscreen = record(3, x: -2_500, onScreen: false)
        let upper = record(4, x: 1_200, y: -1_080)
        suite.expect(MenuBarOrganizerPolicy.recordsOnDividerDisplay([visible, mirrored, offscreen],
            divider: divider, displays: [screen, leftScreen])?.map(\.windowID) == [1],
            "aligned displays never classify their neighbor's visible or ambiguous offscreen icons")
        suite.expect(MenuBarOrganizerPolicy.recordsOnDividerDisplay([record(5, x: 1_200, onScreen: false)],
            divider: divider, displays: [screen, leftScreen])?.isEmpty == true,
            "an offscreen replica projected inside a neighboring display is still ambiguous")
        suite.expect(MenuBarOrganizerPolicy.recordsOnDividerDisplay([visible, offscreen, upper],
            divider: divider, displays: [screen, upperScreen])?.map(\.windowID) == [1, 3],
            "vertical displays retain the target bar's unambiguous offscreen items")
        suite.expect(MenuBarOrganizerPolicy.recordsOnDividerDisplay([visible], divider: divider,
            displays: []) == nil, "missing divider display fails closed")
        let duplicates = MenuBarOrganizerSupport.identities(for: [visible, mirrored], sources: [:])
        suite.expect(duplicates.values.allSatisfy { $0.state == .provisional },
                     "duplicate source identities cannot advertise movable items")
        for bundle in [MenuBarOrganizerSupport.controlCenterBundleIdentifier,
                       MenuBarOrganizerSupport.systemUIServerBundleIdentifier] {
            for title in ["Часы", "Uhr", "月曜日", "12 octobre", ""] {
                suite.expect(MenuBarOrganizerSupport.isSystemImmovable(bundleIdentifier: bundle, title: title),
                             "system controls stay protected independently of language")
            }
        }
        suite.expect(!MenuBarOrganizerSupport.isSystemImmovable(bundleIdentifier: "test.thirdparty", title: "Clock"),
                     "a resolved third-party source is not protected solely by its displayed name")
        let normalFrame = CGRect(x: 80, y: 0, width: 8, height: 24)
        let permanentFrame = CGRect(x: -2_400, y: 0, width: 2_468, height: 24)
        var scanned = 0
        let positions = MenuBarHiderAccessibility.findSeparators(
            roots: [0], normalHelp: "normal", permanentHelp: "permanent", canContinue: { true },
            labels: { node in
                scanned += 1
                return node == 2 ? ["normal"] : node == 3 ? ["permanent"] : []
            }, frame: { $0 == 2 ? normalFrame : $0 == 3 ? permanentFrame : nil },
            children: { $0 == 0 ? [1, 2, 3] : $0 == 1 || $0 >= 10 ? [$0 + 10] : [] })
        suite.expect(positions?.normal == normalFrame && positions?.permanent == permanentFrame && scanned == 4,
                     "deep Settings descendants cannot starve sibling separator discovery")
        scanned = 0
        let cycle = MenuBarHiderAccessibility.findSeparators(
            roots: [0], normalHelp: "normal", permanentHelp: "permanent", canContinue: { true },
            labels: { _ in scanned += 1; return [] }, frame: { _ in nil }, children: { [$0] })
        suite.expect(cycle == nil && scanned == 160, "cyclic AX trees remain bounded")
        let cancelled = MenuBarHiderAccessibility.findSeparators(
            roots: [0], normalHelp: "normal", permanentHelp: "permanent", canContinue: { false },
            labels: { _ in suite.expect(false, "cancelled scans do not query AX"); return [] },
            frame: { _ in nil }, children: { _ in [] })
        suite.expect(cancelled == nil, "cancelled scans fail closed")
        if let event = CGEvent(mouseEventSource: nil, mouseType: .leftMouseUp,
                               mouseCursorPosition: .zero, mouseButton: .left) {
            event.flags = [.maskCommand, .maskShift]
            MenuBarOrganizerSupport.routeEvent(event, to: 123, pid: 456, command: false)
            suite.expect(event.flags.isEmpty, "release events clear synthetic modifiers")
            suite.expect(event.getIntegerValueField(.eventTargetUnixProcessID) == 456
                         && event.getIntegerValueField(.mouseEventWindowUnderMousePointer) == 123
                         && event.getIntegerValueField(.mouseEventWindowUnderMousePointerThatCanHandleThisEvent) == 123,
                         "hosted event routing retains the exact process and status window")
        } else { suite.expect(false, "test event can be constructed without posting input") }
        for version in 10...30 {
            suite.expect(MenuBarOrganizerPolicy.supportsAdvancedBackend(majorVersion: version) == (14...26).contains(version),
                         "the advanced WindowServer backend fails closed outside macOS 14–26")
        }
        for bad in [CGRect.zero, CGRect(x: CGFloat.infinity, y: 0, width: 24, height: 24),
                    CGRect(x: 0, y: CGFloat.nan, width: 24, height: 24), CGRect(x: 0, y: 0, width: 3_000, height: 24),
                    CGRect(x: 0, y: 0, width: 24, height: 80)] {
            suite.expect(!MenuBarOrganizerPolicy.validFrame(bad), "invalid geometry never authorizes input")
        }
        for width: CGFloat in [2_568, 6_024, 7_688] {
            let spacer = CGRect(x: -width, y: 0, width: width, height: 24)
            suite.expect(MenuBarOrganizerPolicy.validSpacerFrame(spacer, maximumWidth: width),
                         "a full-width display spacer is valid independently of ordinary items")
            suite.expect(!MenuBarOrganizerPolicy.validFrame(spacer), "wide spacers never become movable app tiles")
            for after in [false, true] {
                let insertion = MenuBarOrganizerPolicy.insertionFrame(spacer, after: after)
                suite.expect(MenuBarOrganizerPolicy.validFrame(insertion)
                             && (after ? insertion.maxX == spacer.maxX : insertion.minX == spacer.minX),
                             "spacer insertion targets preserve the intended edge with narrow valid bounds")
            }
            suite.expect(!MenuBarOrganizerPolicy.validSpacerFrame(spacer, maximumWidth: width - 1),
                         "spacers wider than the measured screen limit are rejected")
        }
        suite.expect(!MenuBarOrganizerPolicy.validSpacerFrame(CGRect(x: 0, y: 0, width: CGFloat.infinity, height: 24), maximumWidth: 8_000),
                     "non-finite spacers fail closed")
        suite.expect(MenuBarOrganizerPolicy.validFrame(CGRect(x: -1_920, y: -24, width: 24, height: 24)),
                     "negative coordinates on an external display remain valid")
        suite.expect(MenuBarOrganizerPolicy.searchScore(query: "", name: "Wi-Fi") == 0, "empty query shows inventory")
        suite.expect(MenuBarOrganizerPolicy.searchScore(query: "cafe", name: "Café helper") == 0, "search ignores accents")
        suite.expect(MenuBarOrganizerPolicy.searchScore(query: "wm", name: "Window Manager") != nil, "search accepts ordered fuzzy matches")
        suite.expect(MenuBarOrganizerPolicy.searchScore(query: "mw", name: "Window Manager") == nil, "reversed fuzzy characters do not match")
        suite.expect(MenuBarOrganizerPolicy.searchScore(query: "xyz", name: "Bluetooth") == nil, "unmatched query is excluded")

        suite.expect(MenuBarOrganizerSupport.sourceIdentifier(nil, siblingCount: 1)
                     == MenuBarOrganizerSupport.singleItemIdentifier,
                     "a single AX-proven untitled app item has a stable slot")
        suite.expect(MenuBarOrganizerSupport.sourceIdentifier(nil, siblingCount: 2) == nil,
                     "multiple untitled app items are not guessed by index")
        suite.expect(MenuBarOrganizerSupport.sourceIdentifier("named", siblingCount: 2) == "named",
                     "explicit AX identifiers take precedence over singleton fallback")
        let hosted = MenuBarOrganizerWindowRecord(windowID: 999, ownerPID: 1,
            ownerName: "Control Center", ownerBundleIdentifier: MenuBarOrganizerSupport.controlCenterBundleIdentifier,
            title: "Item-1", frame: CGRect(x: 10, y: 0, width: 24, height: 24), layer: 25, alpha: 1, isOnScreen: true)
        let singleton = MenuBarItemSourceIdentity(pid: 2, bundleIdentifier: "test.single", name: "Single",
            axIdentifier: MenuBarOrganizerSupport.sourceIdentifier(nil, siblingCount: 1), axTitle: nil)
        suite.expect(MenuBarOrganizerSupport.identities(for: [hosted], sources: [999: singleton])[999]?.state == .stable,
                     "resolved single-item app becomes movable despite an empty AX title")

        let a = item(id: "a", window: 1, x: 10)
        let b = item(id: "b", window: 2, x: 40)
        let c = item(id: "c", window: 3, x: 70)
        suite.expect(MenuBarOrganizerPolicy.verifiedMove(windowID: 1, before: 2, section: .hidden, items: [c, a, b]),
                     "exact neighbor verification uses rendered order")
        suite.expect(!MenuBarOrganizerPolicy.verifiedMove(windowID: 1, before: 3, section: .hidden, items: [a, b, c]),
                     "merely moving somewhere left of a target is not successful insertion")
        suite.expect(!MenuBarOrganizerPolicy.verifiedMove(windowID: 1, before: nil, section: .visible, items: [a]),
                     "a move to the wrong section fails verification")
        suite.expect(!MenuBarOrganizerPolicy.verifiedMove(windowID: 99, before: nil, section: .hidden, items: [a]),
                     "a vanished item cannot pass verification")
        suite.expect(MenuBarOrganizerPolicy.uniquelyIdentified(a.id, in: [a, b])?.windowID == 1,
                     "a stable unique item remains usable")
        let duplicate = item(id: "a", window: 4, x: 100, occurrence: 1)
        suite.expect(MenuBarOrganizerPolicy.uniquelyIdentified(a.id, in: [a, duplicate]) == nil,
                     "duplicate identities refuse a guessed selection even with distinct occurrence numbers")
        let provisional = item(id: "p", window: 5, x: 10, provisional: true)
        suite.expect(MenuBarOrganizerPolicy.uniquelyIdentified(provisional.id, in: [provisional]) == nil,
                     "a generic host identity never authorizes a click")
        let anchor = MenuBarItemAnchor(provisional)
        suite.expect(anchor.resolve(in: [provisional])?.windowID == 5,
                     "Undo may use an unnamed neighbor as a position without moving that neighbor")
        suite.expect(anchor.resolve(in: []) == nil && anchor.resolve(in: [provisional, provisional]) == nil,
                     "missing or duplicated destination windows cannot authorize insertion")
        let protected = item(id: "clock", window: 6, x: 10, protected: true)
        suite.expect(MenuBarOrganizerPolicy.uniquelyIdentified(protected.id, in: [protected]) == nil,
                     "protected recovery and system items cannot be selected")

        suite.expect(MenuBarOrganizerPolicy.uniquelyIdentified(protected.id, in: [protected], allowProtected: true) != nil,
                     "a protected item can be a destination anchor without moving it")
        suite.expect(!MenuBarOrganizerPolicy.verifiedMove(windowID: 1, before: nil, section: .hidden, items: [a, b]),
                     "an end-of-section drop verifies the final position rather than membership alone")
        suite.expect(MenuBarOrganizerPolicy.verifiedMove(windowID: 2, before: nil, section: .hidden, items: [a, b]),
                     "a verified end-of-section drop remains successful")

        suite.expect(MenuBarOrganizerPolicy.isOwnItem(ownerPID: 100, sourcePID: 100,
                                                      bundleIdentifier: "com.vorssaint.utils.dev",
                                                      currentPID: 42, currentBundleIdentifier: "com.vorssaint.utils.dev"),
                     "Control Center hosting cannot make Vorssaint's own recovery icon movable")
        suite.expect(!MenuBarOrganizerPolicy.isOwnItem(ownerPID: 100, sourcePID: 101,
                                                       bundleIdentifier: "other.app", currentPID: 42,
                                                       currentBundleIdentifier: "com.vorssaint.utils.dev"),
                     "protecting hosted recovery icons does not block unrelated apps")
        suite.expect(MenuBarOrganizerPolicy.isOwnItem(ownerPID: 42, sourcePID: nil,
                                                      bundleIdentifier: "", currentPID: 42,
                                                      currentBundleIdentifier: nil),
                     "an item directly owned by the current process is always protected")

        let input = MenuBarInputCleanup()
        var releaseCount = 0
        var cursorCount = 0
        input.release = { releaseCount += 1 }
        input.restoreCursor = { cursorCount += 1 }
        input.finish()
        input.finish() // Cancellation followed by an asynchronous defer.
        suite.expect(releaseCount == 1 && cursorCount == 1,
                     "disable synchronously releases input and a later defer cannot release twice")
        input.release = { releaseCount += 1 }
        input.finish()
        suite.expect(releaseCount == 2 && cursorCount == 1,
                     "a click without cursor suppression still releases normally")

        let domain = "com.vorssaint.tests.organizer.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: domain)!
        defer { defaults.removePersistentDomain(forName: domain) }
        let initial = MenuBarGlobalSpacing.Saved(spacing: nil, padding: 23)
        var current = initial
        var writes: [MenuBarGlobalSpacing.Saved] = []
        let write: (MenuBarGlobalSpacing.Saved) -> Bool = { value in current = value; writes.append(value); return true }
        suite.expect(MenuBarGlobalSpacing.apply(spacing: 10, defaults: defaults, read: { current }, write: write),
                     "explicit Apply stores the original values")
        suite.expect(current == .init(spacing: 10, padding: 10), "Apply sets both native spacing preferences")
        suite.expect(MenuBarGlobalSpacing.apply(spacing: 999, defaults: defaults, read: { current }, write: write),
                     "a subsequent Apply keeps the first restore snapshot")
        suite.expect(current == .init(spacing: 32, padding: 32), "spacing inputs are bounded")
        suite.expect(MenuBarGlobalSpacing.restore(defaults: defaults, read: { current }, write: write),
                     "Restore succeeds with an absent original key")
        suite.expect(current == initial && defaults.data(forKey: MenuBarGlobalSpacing.restoreKey) == nil,
                     "Restore removes absent keys and clears the completed local transaction")
        var failedOnce = false
        let failingWrite: (MenuBarGlobalSpacing.Saved) -> Bool = { value in
            current = value
            if !failedOnce { failedOnce = true; return false }
            return true
        }
        suite.expect(!MenuBarGlobalSpacing.apply(spacing: 4, defaults: defaults, read: { current }, write: failingWrite)
                     && current == initial, "failed synchronization rolls back both original values")
        suite.expect(defaults.data(forKey: MenuBarGlobalSpacing.restoreKey) == nil,
                     "a first Apply with successful rollback leaves no phantom recovery transaction")
        suite.expect(!MenuBarGlobalSpacing.apply(spacing: 4, defaults: defaults, read: { current }, write: { _ in false })
                     && defaults.data(forKey: MenuBarGlobalSpacing.restoreKey) != nil,
                     "failed Apply and failed rollback keep the only recovery snapshot")
        _ = MenuBarGlobalSpacing.apply(spacing: 12, defaults: defaults, read: { current }, write: write)
        let applied = current
        failedOnce = false
        suite.expect(!MenuBarGlobalSpacing.restore(defaults: defaults, read: { current }, write: failingWrite)
                     && current == applied && defaults.data(forKey: MenuBarGlobalSpacing.restoreKey) != nil,
                     "failed Restore retains the snapshot and rolls back partial writes")
        failedOnce = false
        suite.expect(!MenuBarGlobalSpacing.restoreForRemoval(defaults: defaults, read: { current }, write: failingWrite)
                     && current == applied && defaults.data(forKey: MenuBarGlobalSpacing.restoreKey) != nil,
                     "uninstall restoration failure keeps recovery and rolls back partially written global values")
        suite.expect(MenuBarGlobalSpacing.restoreForRemoval(defaults: defaults, read: { current }, write: write)
                     && current == initial && defaults.object(forKey: MenuBarGlobalSpacing.restoreKey) == nil,
                     "uninstall restores custom and absent original values before clearing recovery")
        writes = []
        suite.expect(MenuBarGlobalSpacing.restoreForRemoval(defaults: defaults, read: { current }, write: write)
                     && writes.isEmpty, "uninstall with no spacing transaction never changes global preferences")
        for malformed: Any in [Data("broken".utf8), "not data", 42] {
            defaults.set(malformed, forKey: MenuBarGlobalSpacing.restoreKey)
            suite.expect(!MenuBarGlobalSpacing.apply(spacing: 7, defaults: defaults, read: { current }, write: write)
                         && writes.isEmpty,
                         "Apply refuses malformed existing recovery instead of overwriting it or changing global values")
            suite.expect(!MenuBarGlobalSpacing.restoreForRemoval(defaults: defaults, read: { current }, write: write)
                         && defaults.object(forKey: MenuBarGlobalSpacing.restoreKey) != nil && writes.isEmpty,
                         "malformed recovery stops uninstall without clearing evidence or guessing global values")
        }
        defaults.removeObject(forKey: MenuBarGlobalSpacing.restoreKey)
        let original = item(id: "hidden", window: 10, x: 700)
        suite.expect(!MenuBarOrganizerPolicy.canActivate(item(id: "permanent", window: 99, x: 0, section: .alwaysHidden)),
                     "Always Hidden cannot be activated through the drawer or search")
        suite.expect(MenuBarOrganizerPolicy.canActivate(original), "Hidden items remain available for activation")
        let crowded = item(id: "edge", window: 11, x: 1010, section: .visible)
        let reachable = item(id: "right", window: 12, x: 1500, protected: true, section: .visible)
        let strip = CGRect(x: 1010, y: 0, width: 790, height: 24)
        suite.expect(MenuBarOrganizerPolicy.activationTarget(for: original, in: [original, crowded, reachable], strip: strip)?.id == reachable.id,
                     "crowded notch activation uses a reachable right-hand neighbor, including a protected anchor")
        suite.expect(MenuBarOrganizerPolicy.activationTarget(for: original, in: [original, crowded], strip: strip) == nil,
                     "activation refuses an insertion overlapping the notch")
        let otherDisplay = item(id: "other", window: 13, x: 2200, section: .visible)
        suite.expect(MenuBarOrganizerPolicy.activationTarget(for: original, in: [original, otherDisplay], strip: strip) == nil,
                     "a same-height item on another display is not an activation destination")
        let duplicateTarget = item(id: "right", window: 14, x: 1600, occurrence: 1, section: .visible)
        suite.expect(MenuBarOrganizerPolicy.activationTarget(for: original, in: [original, reachable, duplicateTarget], strip: strip) == nil,
                     "ambiguous neighbors cannot authorize an activation drag")
        suite.expect(MenuBarHiderAccessibility.hostPIDs(currentPID: 10, runningPIDs: {
            $0 == "com.apple.controlcenter" ? [20] : [30, 20]
        }) == [10, 20, 30], "separator lookup covers native and system-hosted controls without duplicate scans")
        suite.expect(MenuBarHiderAccessibility.hostPIDs(currentPID: 10, runningPIDs: { _ in [] }) == [10],
                     "separator measurement still supports macOS versions with native app-owned status items")
        suite.expect(!SettingsBackupSupport.exportKeys().contains(MenuBarGlobalSpacing.restoreKey),
                     "another Mac's global spacing transaction is never imported")
        for key in [DefaultsKey.menuBarOrganizerAdvanced, DefaultsKey.menuBarOrganizerSpacing,
                    DefaultsKey.menuBarOrganizerAppearance, DefaultsKey.menuBarOrganizerGradient,
                    DefaultsKey.menuBarOrganizerFirstColor, DefaultsKey.menuBarOrganizerSecondColor] {
            suite.expect(SettingsBackupSupport.exportKeys().contains(key), "organizer preferences participate in backup: \(key)")
        }
        suite.expect(AppFeature.menuBarHider.onboardingPermissions.isEmpty,
                     "installing the basic hider does not demand Accessibility")
        func users(_ advanced: Bool) -> [AppFeature] {
            AppFeature.activeFeatures(using: .accessibility, isAvailable: { $0 == .menuBarHider },
                                      boolFor: { $0 == DefaultsKey.menuBarHiderEnabled || (advanced && $0 == DefaultsKey.menuBarOrganizerAdvanced) },
                                      stringFor: { _ in nil }, dataFor: { _ in nil })
        }
        suite.expect(users(false) == [.menuBarHider] && users(true) == [.menuBarHider],
                     "permission status follows the enabled organizer, independent of the old advanced switch")
        for language in AppLanguage.allCases {
            let strings = FeatureStrings.menuBarOrganizer(language)
            for field in Mirror(reflecting: strings).children {
                suite.expect(!(field.value as! String).isEmpty, "every organizer label is localized for \(language): \(field.label ?? "")")
            }
        }
    }

    private static func item(id: String, window: CGWindowID, x: CGFloat, occurrence: Int = 0,
                             provisional: Bool = false, protected: Bool = false,
                             section: MenuBarOrganizerSection = .hidden) -> ManagedMenuBarItem {
        ManagedMenuBarItem(id: .init(bundleIdentifier: "test.app", title: id, occurrence: occurrence),
                           windowID: window, ownerPID: 42, ownerBundleIdentifier: "test.app", sourcePID: 42,
                           ownerName: "Test", sourceName: "Test", bundleIdentifier: "test.app", title: id,
                           frame: CGRect(x: x, y: 0, width: 20, height: 24), section: section,
                           identityState: provisional ? .provisional : .stable, isMovable: !protected,
                           isProtected: protected)
    }
}
