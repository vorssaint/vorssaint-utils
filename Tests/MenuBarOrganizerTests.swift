// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

enum MenuBarOrganizerTests {
    static func run(_ suite: TestSuite) {
        MenuBarOrganizerLifecycleTests.run(suite)
        let clockFrame = CGRect(x: 1300, y: 0, width: 170, height: 30)
        suite.expect(MenuBarItemSupport.cocoaFrame(accessibilityFrame: clockFrame, primaryTop: 956)
            == CGRect(x: 1300, y: 926, width: 170, height: 30),
                     "clock monitoring converts the primary display's AX frame to pointer coordinates")
        let upperDisplay = CGRect(x: -1200, y: -800, width: 150, height: 24)
        suite.expect(MenuBarItemSupport.cocoaFrame(accessibilityFrame: upperDisplay, primaryTop: 956)
            == CGRect(x: -1200, y: 1732, width: 150, height: 24),
                     "clock monitoring preserves negative origins and displays above the primary screen")
        suite.expect(!AppFeature.menuBarOrganizer.installedByDefault
                     && AppFeature.menuBarOrganizer.isBeta,
                     "the experimental organizer waits for an explicit feature install")
        suite.expect(AppFeature.menuBarOrganizer.enabledKeys == [DefaultsKey.menuBarOrganizerEnabled]
                     && AppFeature.menuBarOrganizer.permissions == [.accessibility],
                     "the organizer declares its enable switch and only Accessibility access")
        suite.expect(SettingsBackupSupport.exportKeys().isSuperset(of: [
            DefaultsKey.menuBarOrganizerEnabled, DefaultsKey.menuBarOrganizerSections,
            AppFeature.menuBarOrganizer.availabilityKey]),
                     "organizer installation, enabled state, and section preferences are portable")
        suite.expect(AppFeature.menuBarOrganizer.settingsDestination
                     == FeatureSettingsDestination(.general, sectionAnchor: .panelConfiguration),
                     "the feature hub routes the organizer to Menu Bar settings")
        func active(_ permission: AppPermission, installed: Bool = true, enabled: Bool = true) -> [AppFeature] {
            AppFeature.activeFeatures(using: permission,
                isAvailable: { installed && $0 == .menuBarOrganizer },
                boolFor: { enabled && $0 == DefaultsKey.menuBarOrganizerEnabled }, stringFor: { _ in nil })
        }
        suite.expect(active(.accessibility) == [.menuBarOrganizer] && active(.screenRecording).isEmpty,
                     "an enabled organizer uses Accessibility without screen recording")
        suite.expect(active(.accessibility, installed: false).isEmpty
                     && active(.accessibility, enabled: false).isEmpty,
                     "disabled or uninstalled organizers create no active permission demand")
        var state = MenuBarOrganizerVisibility()
        suite.expect(state.hiddenShown && state.alwaysShown, "new dividers start revealed for arranging")
        state.toggleHidden()
        suite.expect(!state.hiddenShown && !state.alwaysShown, "collapse hides both sections")
        state.toggleHidden()
        suite.expect(state.hiddenShown && !state.alwaysShown, "regular reveal preserves always-hidden icons")
        state.toggleHidden()
        state.toggleAlwaysHidden()
        suite.expect(state.hiddenShown && state.alwaysShown, "Option reveal opens both boundaries for recovery")
        state.toggleAlwaysHidden()
        suite.expect(state.hiddenShown && !state.alwaysShown, "closing always-hidden preserves the regular section")
        state.revealAll()
        suite.expect(state.hiddenShown && state.alwaysShown, "settings can always recover all icons")
        suite.expect(MenuBarOrganizerVisibility.collapsedLength(systemMajorVersion: 26, displayWidths: [1512]) == 10_000,
                     "earlier systems retain the original off-screen mechanism")
        var rules = MenuBarOrganizerRules()
        suite.expect(rules.section(for: "new-app") == .visible, "new apps are visible without an explicit rule")
        rules.set(.hidden, for: "hidden")
        rules.set(.alwaysHidden, for: "always")
        rules.set(.alwaysHidden, for: "own")
        rules.set(.alwaysHidden, for: "com.apple.controlcenter")
        func plan() -> Set<String> {
            rules.hiddenBundles(state: state, ownBundleID: "own")
        }
        suite.expect(plan().isEmpty, "revealing restores every bundle")
        state.toggleHidden()
        suite.expect(plan() == ["always", "hidden"], "collapse follows explicit rules and preserves recovery and system controls")
        state.toggleHidden()
        suite.expect(plan() == ["always"], "regular reveal leaves only the always-hidden owners hidden")
        state.toggleAlwaysHidden()
        suite.expect(plan().isEmpty, "Option reveal restores both configured sections")
        state.toggleHidden()
        state.toggleHidden()
        rules.set(.visible, for: "always")
        suite.expect(plan().isEmpty, "moving an always-hidden app to Visible immediately restores it")
        let restored = MenuBarOrganizerRules(storage: rules.storage)
        suite.expect(restored.section(for: "hidden") == .hidden && restored.section(for: "always") == .visible,
                     "saved sections survive relaunch without positional classification")
        suite.expect(MenuBarOrganizerRules(storage: ["broken": "unknown"]).section(for: "broken") == .visible,
                     "unrecognized saved values keep the app visible")
        let allowed = MenuBarOrganizerRules.allowedBundles(running: ["new-app", "hidden"], hidden: ["hidden", "own"], ownBundleID: "own")
        suite.expect(allowed.contains("own") && allowed.contains("com.apple.controlcenter") && allowed.contains("com.apple.MenuBarAgent"),
                     "recovery and system controls remain allowed when Workspace omits them")
        suite.expect(allowed.contains("new-app") && !allowed.contains("hidden"), "newly launched apps remain visible without changing hidden rules")
        let helperOwners: Set<String> = ["menu-helper", "visible-helper"]
        let helperHidden = MenuBarOrganizerRules.allowedBundles(running: ["main-app"],
            menuBarOwners: helperOwners, hidden: ["menu-helper"], ownBundleID: "own")
        suite.expect(!helperHidden.contains("menu-helper") && helperHidden.contains("visible-helper"),
                     "discovered menu bar helpers follow sections even when Workspace omits their processes")
        let helperRevealed = MenuBarOrganizerRules.allowedBundles(running: ["main-app"],
            menuBarOwners: helperOwners, hidden: ["main-app"], ownBundleID: "own")
        suite.expect(helperRevealed.contains("menu-helper") && !helperRevealed.contains("main-app"),
                     "temporarily revealing an omitted helper allows it while keeping other apps hidden")
        rules.set(.alwaysHidden, for: "always")
        state.revealHidden()
        suite.expect(plan() == ["always"], "native launch applies saved always-hidden choices while keeping the regular section shown")
        func item(_ id: String, bundle: String, pid: Int32 = 100) -> MenuBarItemDescriptor {
            .init(id: id, bundleID: bundle, pid: pid, title: id,
                  frame: CGRect(x: 200, y: 0, width: 24, height: 24))
        }
        let hiddenItem = item("hidden-1", bundle: "hidden")
        let visibleItem = item("visible-1", bundle: "visible")
        let secondIcon = item("hidden-2", bundle: "hidden")
        let oldProcess = item("old-process", bundle: "hidden", pid: 99)
        let rebuilt = item("new-identifier", bundle: "hidden")
        suite.expect(MenuBarItemSupport.activationIndex(for: hiddenItem, in: [visibleItem, hiddenItem]) == 1,
                     "activation resolves the original status item within the same process")
        suite.expect(MenuBarItemSupport.activationIndex(for: hiddenItem, in: [visibleItem, rebuilt]) == 1,
                     "a single status item remains usable when MenuBarAgent replaces its identifier and title")
        let rebuiltTitle = MenuBarItemDescriptor(id: "new-id", bundleID: "hidden", pid: 100,
            title: hiddenItem.title, frame: CGRect(x: 500, y: 0, width: 24, height: 24))
        suite.expect(MenuBarItemSupport.activationIndex(for: hiddenItem, in: [secondIcon, rebuiltTitle]) == 1,
                     "matching the unique title selects the intended rebuilt icon among multiple app icons")
        suite.expect(MenuBarItemSupport.activationIndex(for: hiddenItem, in: [oldProcess]) == nil,
                     "activation never clicks a different process even when its bundle matches")
        suite.expect(MenuBarItemSupport.activationIndex(for: hiddenItem, in: [visibleItem]) == nil,
                     "activation never substitutes an unrelated application's icon")
        suite.expect(MenuBarItemSupport.activationIndex(for: hiddenItem, in: []) == nil,
                     "activation waits when the revealed item has not reached Accessibility yet")
        suite.expect(MenuBarItemSupport.activationIndex(for: hiddenItem, in: [rebuilt, secondIcon]) == nil,
                     "activation does not guess among unmatched icons owned by the same process")
        let duplicateTitle = MenuBarItemDescriptor(id: "duplicate", bundleID: "hidden", pid: 100,
            title: hiddenItem.title, frame: CGRect(x: 550, y: 0, width: 24, height: 24))
        suite.expect(MenuBarItemSupport.activationIndex(for: hiddenItem, in: [rebuiltTitle, duplicateTitle]) == nil,
                     "activation does not guess when recreated items have identical titles")
        let statusFrame = CGRect(x: 200, y: 0, width: 24, height: 24)
        func hit(_ frame: CGRect, pid: Int32 = 100) -> Bool {
            MenuBarItemSupport.activationHitMatches(frame: statusFrame, itemPID: 100,
                hitFrame: frame, hitPID: pid, menuBarAgentPID: 200)
        }
        suite.expect(hit(statusFrame), "physical activation accepts the real status control")
        suite.expect(hit(statusFrame.insetBy(dx: 3, dy: 3), pid: 200),
                     "physical activation accepts a status glyph hosted by MenuBarAgent")
        suite.expect(!hit(statusFrame, pid: 300), "physical activation rejects a covering control from another app")
        suite.expect(!hit(statusFrame.offsetBy(dx: 24, dy: 0)), "physical activation rejects an adjacent status icon")
        suite.expect(!hit(CGRect(x: 0, y: 0, width: 1200, height: 800), pid: 200),
                     "physical activation rejects a broad host window instead of guessing its control")
        suite.expect(!hit(.zero), "physical activation rejects vanished or zero-size targets")
        let retained = MenuBarItemSupport.retainedItems(current: [visibleItem],
            previous: [hiddenItem, visibleItem, secondIcon, oldProcess],
            runningPIDs: [100, 101, 102], hiddenBundles: ["hidden"])
        suite.expect(retained == [visibleItem, hiddenItem, secondIcon],
                     "retain only previously observed hidden status items, including multiple icons per owner")
        suite.expect(MenuBarItemSupport.retainedItems(current: [], previous: [visibleItem],
            runningPIDs: [100], hiddenBundles: []).isEmpty,
                     "an app that removes its visible status item disappears even while its process runs")
        suite.expect(MenuBarItemSupport.retainedItems(current: [], previous: [hiddenItem],
            runningPIDs: [101], hiddenBundles: ["hidden"]).isEmpty,
                     "relaunching a hidden app does not retain an icon from its terminated process")
        suite.expect(MenuBarItemSupport.retainedItems(current: [hiddenItem], previous: [hiddenItem],
            runningPIDs: [100], hiddenBundles: ["hidden"]) == [hiddenItem],
                     "a rediscovered icon replaces its cache without duplication")
        suite.expect(MenuBarItemSupport.retainedItems(current: [rebuilt], previous: [hiddenItem],
            runningPIDs: [100], hiddenBundles: ["hidden"]) == [rebuilt],
                     "a recreated single icon replaces the stale cache even when its title changes")
        suite.expect(MenuBarItemSupport.retainedItems(current: [rebuiltTitle], previous: [hiddenItem, secondIcon],
            runningPIDs: [100], hiddenBundles: ["hidden"]) == [rebuiltTitle, secondIcon],
                     "a recreated named icon replaces its cache while retaining a distinct hidden icon")
        suite.expect(MenuBarItemSupport.section(at: 100, hiddenBoundary: 300, alwaysBoundary: 200) == .alwaysHidden
                     && MenuBarItemSupport.section(at: 250, hiddenBoundary: 300, alwaysBoundary: 200) == .hidden
                     && MenuBarItemSupport.section(at: 350, hiddenBoundary: 300, alwaysBoundary: 200) == .visible,
                     "legacy sections follow physical divider positions in either language")
        let bar = MenuBarItemSupport.barFrame(size: CGSize(width: 240, height: 44), anchorX: 600,
            screen: CGRect(x: 0, y: 0, width: 1200, height: 800), menuBarHeight: 24)
        suite.expect(bar == CGRect(x: 480, y: 726, width: 240, height: 44),
                     "hidden icons form a shelf centered below the menu bar anchor")
        let leftDisplay = CGRect(x: -1200, y: -200, width: 1200, height: 800)
        let edge = MenuBarItemSupport.barFrame(size: CGSize(width: 240, height: 44), anchorX: -5,
            screen: leftDisplay, menuBarHeight: 24)
        suite.expect(edge.minX == -248 && edge.maxX == -8 && edge.maxY == 570,
                     "the shelf remains inside a display with a negative origin")
        let wide = MenuBarItemSupport.barFrame(size: CGSize(width: 2000, height: 44), anchorX: -1200,
            screen: leftDisplay, menuBarHeight: 24)
        suite.expect(wide.width == 1184 && wide.minX == -1192,
                     "an overflowing shelf leaves margins and can scroll within the display")
        let installed = URL(fileURLWithPath: "/Applications/Vorssaint.app")
        suite.expect(MenuBarItemSupport.canKeepRecoveryIcon(bundleURL: installed, registeredURL: installed),
                     "the registered installed app can keep its own recovery arrow visible")
        suite.expect(!MenuBarItemSupport.canKeepRecoveryIcon(
            bundleURL: URL(fileURLWithPath: "/tmp/build/Vorssaint.app"), registeredURL: installed),
                     "a duplicate local build cannot hide icons and lose its own recovery arrow")
        suite.expect(!MenuBarItemSupport.canKeepRecoveryIcon(bundleURL: installed, registeredURL: nil),
                     "an unregistered app keeps every icon visible for recovery")
        LocalizationTests.check(MenuBarOrganizerStrings.ar, against: MenuBarOrganizerStrings.enUS,
                                name: "menu-bar-organizer/ar", suite: suite)
        suite.expect(Set(AppLanguage.allCases.map(\.rawValue)).isSubset(of: MenuBarOrganizerStrings.supportedLanguageCodes),
                     "the organizer provides copy for every upstream language")
        for language in AppLanguage.allCases {
            LocalizationTests.check(MenuBarOrganizerStrings.localized(language), against: MenuBarOrganizerStrings.enUS,
                                    name: "menu-bar-organizer/\(language.rawValue)", suite: suite)
        }
    }
}
