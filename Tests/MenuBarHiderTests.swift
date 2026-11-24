// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit

enum MenuBarHiderTests {
    static func run(_ suite: TestSuite) {
        let domain = "com.vorssaint.tests.menu-bar-hider.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: domain)!
        defer { defaults.removePersistentDomain(forName: domain) }
        Defaults.migrateMenuBarHiderAvailability(in: defaults)
        suite.expect(defaults.object(forKey: AppFeature.menuBarHider.availabilityKey) == nil,
                     "new installs leave the hider opt-in")
        defaults.set(true, forKey: DefaultsKey.menuBarHiderEnabled)
        Defaults.migrateMenuBarHiderAvailability(in: defaults)
        suite.expect(AppFeature.menuBarHider.isAvailable(in: defaults),
                     "updating an enabled development hider keeps it installed")
        defaults.set(false, forKey: AppFeature.menuBarHider.availabilityKey)
        Defaults.migrateMenuBarHiderAvailability(in: defaults)
        suite.expect(!AppFeature.menuBarHider.isAvailable(in: defaults),
                     "an explicit uninstall survives migration")

        suite.expect(MenuBarHiderSupport.statusWindowID(-1) == nil,
                     "a placeholder status window cannot trap on unsigned conversion")
        suite.expect(MenuBarHiderSupport.statusWindowID(0) == nil,
                     "the null window cannot be queried as a separator")
        suite.expect(MenuBarHiderSupport.statusWindowID(Int.max) == nil,
                     "an out-of-range window number is rejected without trapping")
        suite.expect(MenuBarHiderSupport.statusWindowID(42) == 42,
                     "valid window identifiers remain queryable")

        let normalPositionKey = "NSStatusItem Preferred Position \(MenuBarHiderSupport.separatorAutosaveName)"
        let permanentPositionKey = "NSStatusItem Preferred Position \(MenuBarHiderSupport.alwaysHiddenAutosaveName)"
        suite.expect(MenuBarHiderSupport.preferredSeparatorRolesSwapped(in: defaults) == nil,
                     "missing positions do not invent a separator order")
        defaults.set(651.0, forKey: normalPositionKey)
        defaults.set(357.0, forKey: permanentPositionKey)
        suite.expect(MenuBarHiderSupport.preferredSeparatorRolesSwapped(in: defaults) == true,
                     "the reported crossed placement is recognized even when windows are hidden")
        defaults.set(300.0, forKey: normalPositionKey)
        suite.expect(MenuBarHiderSupport.preferredSeparatorRolesSwapped(in: defaults) == false,
                     "moving the normal slot right of the permanent slot restores its role")
        defaults.set(357.0, forKey: normalPositionKey)
        suite.expect(MenuBarHiderSupport.preferredSeparatorRolesSwapped(in: defaults) == nil,
                     "equal remembered positions cannot produce oscillating role assignments")
        defaults.set(-1.0, forKey: normalPositionKey)
        suite.expect(MenuBarHiderSupport.preferredSeparatorRolesSwapped(in: defaults) == nil,
                     "invalid remembered positions do not hide a separator")
        defaults.removeObject(forKey: normalPositionKey)
        defaults.removeObject(forKey: permanentPositionKey)

        let resting = CGRect(x: 900, y: 0, width: 10, height: 24)
        let crossed = CGRect(x: 1000, y: 0, width: 12, height: 24)
        suite.expect(MenuBarHiderSupport.renderedSeparatorRolesSwapped(normal: resting, permanent: crossed) == true,
                     "resting separators crossed by a drag swap their roles")
        // An expanded separator relocated past the notch reads as crossed.
        let relocated = CGRect(x: 1020, y: 0, width: 798, height: 24)
        suite.expect(MenuBarHiderSupport.renderedSeparatorRolesSwapped(normal: resting, permanent: relocated) == nil,
                     "an expanded separator cannot swap roles and start a flicker loop")

        // MARK: Menu Bar Hider calculations and localization
        suite.expect(MenuBarHiderSupport.sanitizeAutoCollapseDelay(5) == 5, "auto-collapse delay 5 is valid")
        suite.expect(MenuBarHiderSupport.sanitizeAutoCollapseDelay(30) == 30, "auto-collapse delay 30 is valid")
        suite.expect(MenuBarHiderSupport.sanitizeAutoCollapseDelay(99) == MenuBarHiderSupport.defaultAutoCollapseDelay, "invalid auto-collapse delay resets to default")
        suite.expect(MenuBarHiderSupport.sanitizeAutoCollapseDelay(-5) == MenuBarHiderSupport.defaultAutoCollapseDelay, "negative auto-collapse delay resets to default")

        // The expansion covers the strip the items live in and no more. A 14"
        // MacBook Pro has 790 pt left of the notch on an 1800 pt display, so
        // sizing off the full screen asks for an item far wider than its bar.
        suite.expect(MenuBarHiderSupport.expansionLength(for: 790) > 790,
               "expansion clears the usable width it was given")
        suite.expect(MenuBarHiderSupport.expansionLength(for: 790) < 1800,
               "expansion off a notched strip stays under the full screen width")
        suite.expect(MenuBarHiderSupport.expansionLength(for: 1920) == 1920 + MenuBarHiderSupport.expansionMargin,
               "expansion is the usable width plus the margin")
        suite.expect(MenuBarHiderSupport.expansionLength(for: nil)
                == MenuBarHiderSupport.fallbackUsableWidth + MenuBarHiderSupport.expansionMargin,
               "expansion falls back when no width can be measured")
        suite.expect(MenuBarHiderSupport.expansionLength(for: -50) == MenuBarHiderSupport.expansionMargin,
               "a nonsensical negative width cannot produce a negative length")

        suite.expect(MenuBarHiderSupport.separatorLength(state: .collapsed, usableWidth: 790)
                == MenuBarHiderSupport.expansionLength(for: 790), "collapsed separator is expanded")
        suite.expect(MenuBarHiderSupport.separatorLength(state: .expanded, usableWidth: 1920) == MenuBarHiderSupport.normalSeparatorWidth, "expanded separator has normal width")
        suite.expect(MenuBarHiderSupport.separatorLength(state: .showAll, usableWidth: 1920) == MenuBarHiderSupport.normalSeparatorWidth, "showAll separator has normal width")

        suite.expect(MenuBarHiderSupport.alwaysHiddenLength(state: .showAll, usableWidth: 1920, isEnabled: false) == 0.0, "disabled always-hidden item has zero length")
        suite.expect(MenuBarHiderSupport.alwaysHiddenLength(state: .expanded, usableWidth: 790, isEnabled: true)
                == MenuBarHiderSupport.expansionLength(for: 790), "always-hidden stays collapsed during normal expansion")
        suite.expect(MenuBarHiderSupport.alwaysHiddenLength(state: .showAll, usableWidth: 1920, isEnabled: true) == MenuBarHiderSupport.normalAlwaysHiddenWidth, "always-hidden shows normal width on showAll")

        suite.expect(MenuBarHiderSupport.toggleSymbolName(isCollapsed: true, style: .chevron) == "chevron.left", "collapsed chevron toggle shows chevron.left")
        suite.expect(MenuBarHiderSupport.toggleSymbolName(isCollapsed: false, style: .chevron) == "chevron.right", "expanded chevron toggle shows chevron.right")
        suite.expect(MenuBarHiderSupport.toggleSymbolName(isCollapsed: true, style: .dots) == "ellipsis.circle", "collapsed dots toggle shows ellipsis.circle")
        suite.expect(MenuBarHiderSupport.toggleSymbolName(isCollapsed: false, style: .dots) == "ellipsis.circle.fill", "expanded dots toggle shows ellipsis.circle.fill")
        suite.expect(MenuBarHiderSupport.toggleSymbolName(isCollapsed: true, style: .eye) == "eye.slash", "collapsed eye toggle shows eye.slash")
        suite.expect(MenuBarHiderSupport.toggleSymbolName(isCollapsed: false, style: .eye) == "eye", "expanded eye toggle shows eye")
        // The tooltip picks a localized string rather than building English, so
        // the check is which field each state selects, in every language.
        for lang in AppLanguage.allCases {
            let t = FeatureStrings.menuBarHider(lang)
            suite.expect(MenuBarHiderSupport.toggleTooltip(isCollapsed: true, isShowingAll: false, alwaysHiddenEnabled: false, strings: t) == t.tooltipExpand,
                   "collapsed toggle uses the expand tooltip for \(lang)")
            suite.expect(MenuBarHiderSupport.toggleTooltip(isCollapsed: true, isShowingAll: false, alwaysHiddenEnabled: true, strings: t) == t.tooltipExpand,
                   "collapsed toggle uses the expand tooltip with always-hidden on for \(lang)")
            suite.expect(MenuBarHiderSupport.toggleTooltip(isCollapsed: false, isShowingAll: false, alwaysHiddenEnabled: false, strings: t) == t.tooltipCollapse,
                   "expanded toggle uses the plain collapse tooltip for \(lang)")
            suite.expect(MenuBarHiderSupport.toggleTooltip(isCollapsed: false, isShowingAll: false, alwaysHiddenEnabled: true, strings: t) == t.tooltipCollapseShowAll,
                   "expanded toggle offers show-all when always-hidden is on for \(lang)")
            suite.expect(MenuBarHiderSupport.toggleTooltip(isCollapsed: false, isShowingAll: true, alwaysHiddenEnabled: true, strings: t) == t.tooltipCollapseHideAlways,
                   "showing-all toggle offers hiding the always-hidden section for \(lang)")
        }

        for interval in [0.18, 0.5, 1.2] {
            suite.expect(MenuBarHiderSupport.revealGestureInterval(systemDoubleClickInterval: interval) == interval,
                         "reveal honors the user's system double-click interval")
        }
        suite.expect(MenuBarHiderSupport.revealGestureInterval(systemDoubleClickInterval: -1) == 0,
                     "negative intervals cannot create a reveal window")

        // Every style's symbols must resolve on the running system: a nil image
        // leaves the variable-length toggle with no image and no title, which
        // collapses it to zero width and makes the button disappear.
        for style in MenuBarHiderIconStyle.allCases {
            for collapsed in [true, false] {
                let name = MenuBarHiderSupport.toggleSymbolName(isCollapsed: collapsed, style: style)
                suite.expect(NSImage(systemSymbolName: name, accessibilityDescription: nil) != nil,
                       "toggle symbol \(name) exists for style \(style.rawValue) collapsed=\(collapsed)")
            }
        }

        let screens = [CGRect(x: 0, y: 0, width: 1512, height: 982),
                       CGRect(x: -1920, y: 250, width: 1920, height: 1080)]
        suite.expect(MenuBarHiderSupport.pointerIsOnMenuBar(CGPoint(x: 100, y: 970), screenFrames: screens, barHeight: 24),
                     "hover stays open while reaching another icon on the main menu bar")
        suite.expect(MenuBarHiderSupport.pointerIsOnMenuBar(CGPoint(x: -100, y: 1320), screenFrames: screens, barHeight: 24),
                     "hover recognizes an offset external display menu bar")
        suite.expect(!MenuBarHiderSupport.pointerIsOnMenuBar(CGPoint(x: 100, y: 900), screenFrames: screens, barHeight: 24),
                     "leaving the menu bar allows hover collapse")
        suite.expect(!MenuBarHiderSupport.pointerIsOnMenuBar(CGPoint(x: 1600, y: 970), screenFrames: screens, barHeight: 24),
                     "a point outside all displays does not hold hover open")


        for lang in AppLanguage.allCases {
            let hiderStrings = FeatureStrings.menuBarHider(lang)
            suite.expect(!hiderStrings.pageTitle.isEmpty, "menu bar hider page title is localized for \(lang)")
            suite.expect(!hiderStrings.hubDescription.isEmpty, "menu bar hider hub description is localized for \(lang)")
            suite.expect(!hiderStrings.enable.isEmpty, "menu bar hider enable toggle is localized for \(lang)")
            suite.expect(!hiderStrings.howToUseTitle.isEmpty, "menu bar hider guide title is localized for \(lang)")
            suite.expect(!hiderStrings.alwaysHiddenSection.isEmpty, "menu bar hider always-hidden section is localized for \(lang)")
            suite.expect(!hiderStrings.autoCollapseSection.isEmpty, "menu bar hider auto-collapse section is localized for \(lang)")
            suite.expect(!hiderStrings.interactionSection.isEmpty, "menu bar hider interaction section is localized for \(lang)")
            suite.expect(!hiderStrings.scrollToToggle.isEmpty, "menu bar hider scrollToToggle is localized for \(lang)")
            suite.expect(!hiderStrings.scrollToToggleCaption.isEmpty, "menu bar hider scrollToToggleCaption is localized for \(lang)")
            suite.expect(!hiderStrings.hapticFeedback.isEmpty, "menu bar hider hapticFeedback is localized for \(lang)")
            suite.expect(!hiderStrings.hapticFeedbackCaption.isEmpty, "menu bar hider hapticFeedbackCaption is localized for \(lang)")
            suite.expect(!hiderStrings.iconStyleTitle.isEmpty, "menu bar hider iconStyleTitle is localized for \(lang)")
            suite.expect(!hiderStrings.styleChevron.isEmpty, "menu bar hider styleChevron is localized for \(lang)")
            suite.expect(!hiderStrings.styleDots.isEmpty, "menu bar hider styleDots is localized for \(lang)")
            suite.expect(!hiderStrings.styleEye.isEmpty, "menu bar hider styleEye is localized for \(lang)")
            suite.expect(!hiderStrings.styleSlash.isEmpty, "menu bar hider styleSlash is localized for \(lang)")
            suite.expect(!hiderStrings.resetPositionsButton.isEmpty, "menu bar hider resetPositionsButton is localized for \(lang)")
            suite.expect(!hiderStrings.resetPositionsSuccess.isEmpty, "menu bar hider resetPositionsSuccess is localized for \(lang)")
            suite.expect(!hiderStrings.resetPositionsCaption.isEmpty, "menu bar hider resetPositionsCaption is localized for \(lang)")
            suite.expect(!hiderStrings.shortcutSection.isEmpty, "menu bar hider shortcut section is localized for \(lang)")
            suite.expect(!hiderStrings.contextMenuExpand.isEmpty, "menu bar hider contextMenuExpand is localized for \(lang)")
            suite.expect(!hiderStrings.contextMenuCollapse.isEmpty, "menu bar hider contextMenuCollapse is localized for \(lang)")
            suite.expect(!hiderStrings.contextMenuShowAll.isEmpty, "menu bar hider contextMenuShowAll is localized for \(lang)")
            suite.expect(!hiderStrings.contextMenuHideAlways.isEmpty, "menu bar hider contextMenuHideAlways is localized for \(lang)")
            suite.expect(!hiderStrings.contextMenuSettings.isEmpty, "menu bar hider contextMenuSettings is localized for \(lang)")
            suite.expect(!hiderStrings.tooltipExpand.isEmpty, "menu bar hider tooltipExpand is localized for \(lang)")
            suite.expect(!hiderStrings.tooltipCollapse.isEmpty, "menu bar hider tooltipCollapse is localized for \(lang)")
            suite.expect(!hiderStrings.tooltipCollapseShowAll.isEmpty, "menu bar hider tooltipCollapseShowAll is localized for \(lang)")
            suite.expect(!hiderStrings.tooltipCollapseHideAlways.isEmpty, "menu bar hider tooltipCollapseHideAlways is localized for \(lang)")
            suite.expect(!hiderStrings.tooltipSeparator.isEmpty, "menu bar hider tooltipSeparator is localized for \(lang)")
            suite.expect(!hiderStrings.tooltipAlwaysHidden.isEmpty, "menu bar hider tooltipAlwaysHidden is localized for \(lang)")
            suite.expect(!hiderStrings.diagramAlwaysHidden.isEmpty, "menu bar hider diagramAlwaysHidden is localized for \(lang)")
            suite.expect(!hiderStrings.diagramHidden.isEmpty, "menu bar hider diagramHidden is localized for \(lang)")
            suite.expect(!hiderStrings.diagramVisible.isEmpty, "menu bar hider diagramVisible is localized for \(lang)")
            suite.expect(hiderStrings.secondsFormat.contains("%d"), "menu bar hider secondsFormat contains %d for \(lang)")
        }

    }
}
