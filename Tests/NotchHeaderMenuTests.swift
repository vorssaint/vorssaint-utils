// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import SwiftUI

/// The open header, compiled from the island's header and service. Where the
/// title sits beside the camera the header shows only a menu, so a page's own
/// header buttons must be reachable from it, and the title fits there only
/// with everything drawn beside it, which must draw no wider than counted.
/// Below the camera the title shares its row with the buttons, which must
/// leave it its room.
enum NotchHeaderMenuTests {
    final class Service {
        var pinned = false
        var clipboardPinnedOnly = false
        var selected = NotchModule.clipboard
        var showingSections = false
        var showingAppPanel = false
        var selectedMetric: Int?
        var modules: [NotchModule] = NotchModule.allCases
        var contentSize = CGSize(width: 304, height: 240)
        var clipboardHeaderShowsSearch = true
        var searches = 0
        var performed = 0
        func perform(_ action: @escaping () -> Void) {
            performed += 1
            action()
        }
        func openSettings() {}
        func collapse() {}
        func toggleSections() {}
        func requestClipboardSearch() { searches += 1 }
        func showUpdate() {}
    }
    final class Launcher {
        var isEditing = false
        var activeUtility: Int?
    }
    /// No update on offer, so its control draws nothing, as in the island.
    enum UpdateState {
        case idle, available(version: String)
        var isInProgress: Bool { false }
    }
    final class Updates { var state = UpdateState.idle }
    struct NotchUpdateControl: View {
        let action: () -> Void
        var body: some View { EmptyView() }
    }
    struct NotchClearCapturesButton: View { var body: some View { EmptyView() } }
    struct Language {
        var language = AppLanguage.enUS
        var s: Strings { Strings.localized(language) }
    }
    enum RecentCapturesView {
        static func visible(_ entries: [Int]) -> [Int] { entries }
        static func confirmClearAboveIsland() {}
    }
    final class RecentCaptureService {
        static let shared = RecentCaptureService()
        var entries: [Int] = []
    }
    final class NotchNotificationService {
        static let shared = NotchNotificationService()
        var items: [Int] = []
        var openingID: Int?
    }
    struct NotchClearNotificationsButton: View {
        var body: some View { EmptyView() }
        static func confirmClearAboveIsland() {}
    }
    final class ClipboardHistoryService {
        static let shared = ClipboardHistoryService()
        var recentEntries: [Int] = []
        var windows = 0
        func showHistoryWindow(preferNotch: Bool) { if !preferNotch { windows += 1 } }
    }
    final class L10n {
        static let shared = L10n()
        var language = AppLanguage.enUS
    }

    static func run(_ suite: TestSuite) {
        let service = Service()
        let header = Header(service: service)
        let text = FeatureStrings.clipboard(.enUS)
        let clipboardTitles = [text.pinned, text.clearRecent, text.title]
        let history = ClipboardHistoryService.shared
        history.recentEntries = []
        var items = header.overflowItems(tools: false, clear: false, clipboard: true)
        suite.expect(Array(items.prefix(3).map(\.title)) == clipboardTitles && items[3].isSeparator,
                     "the clipboard's filter, clearing and history window lead the header menu beside the camera")
        suite.expect(!header.overflowItems(tools: false, clear: false).contains { clipboardTitles.contains($0.title) },
                     "other pages' header menus leave the clipboard's entries out")
        suite.expect(!items[0].checked && !items[1].enabled, "the clipboard menu reads the filter off and nothing to clear")
        // Keep open wears the pin, here and in the header beside it.
        suite.expect(items[0].symbol != nil && !items.contains { $0.title == header.text.pin && $0.symbol == items[0].symbol },
                     "the clipboard's pinned filter wears a glyph of its own, not Keep open's pin")
        items[0].action()
        history.recentEntries = [1]
        items = header.overflowItems(tools: false, clear: false, clipboard: true)
        suite.expect(service.clipboardPinnedOnly && items[0].checked && items[1].enabled,
                     "the clipboard menu switches the pinned filter on and offers clearing recent entries")
        let clears = NotchClipboardHeaderActions.clears
        items[1].action()
        items[2].action()
        suite.expect(NotchClipboardHeaderActions.clears == clears + 1 && service.performed == 1 && history.windows == 1,
                     "the clipboard menu asks before clearing and opens the history window")
        history.recentEntries = []

        // Whether the title sits beside the camera is decided from its width,
        // which on the clipboard page includes the magnifier after it where
        // it shows. A title with room beside the camera for itself alone
        // stays there without the magnifier, and the menu there offers Search:
        // in every language, at the default and the 480-point sizes, beside
        // 185 and 200-point cameras.
        let island = Island()
        let screen = CGRect(x: 0, y: 0, width: 1710, height: 1112)
        var magnifierLeftOut = 0, magnifierKept = 0
        for layout in [NotchSize.spacious, .compact] {
            for camera: CGFloat in [185, 200] {
                island.geometry = NotchGeometry(screen: screen, safeAreaTop: 37.5, cameraWidth: camera, layout: layout)
                let side = (island.geometry.contentWidth - island.geometry.cameraWidth) / 2
                for language in AppLanguage.allCases {
                    L10n.shared.language = language
                    let clipboard = NotchModule.clipboard.title(language)
                    for button in [false, true] {
                        island.headerShowsSectionsButton = button
                        var open = island.geometry
                        open.headerTitleWidth = island.headerTitleWidth
                        let preview = island.previewGeometry(for: .clipboard, sectionsButton: button)
                        let alone = NotchLayout.headerTitleWidth(clipboard, button: button)
                        let search = island.clipboardHeaderShowsSearch
                        let place = "the \(language.rawValue) clipboard title" + (button ? " and the sections button" : "")
                            + " beside a \(Int(camera))-point camera at the \(layout.rawValue) size"
                        suite.expect(alone > side || (open.headerCameraGap == camera && preview.headerCameraGap == camera),
                                     "the header stays beside the camera wherever \(place) fits alone")
                        suite.expect(search == (alone + NotchLayout.headerSearchWidth <= side || alone > side)
                                     && open.headerTitleWidth == alone + (search ? NotchLayout.headerSearchWidth : 0)
                                     && preview.headerTitleWidth == open.headerTitleWidth,
                                     "the island and its preview count the magnifier after \(place) only where it shows")
                        let page = Service()
                        page.clipboardHeaderShowsSearch = search
                        var beside = Header(service: page)
                        beside.l10n.language = language
                        let searchEntries = beside.overflowItems(tools: false, clear: false, clipboard: true)
                            .filter { $0.title == FeatureStrings.clipboard(language).search }
                        searchEntries.first?.action()
                        suite.expect(search ? searchEntries.isEmpty : searchEntries.count == 1 && page.searches == 1,
                                     "the menu beside the camera offers Search only where the header leaves \(place) without its magnifier")
                        if search { magnifierKept += 1 } else { magnifierLeftOut += 1 }
                    }
                }
            }
        }
        L10n.shared.language = .enUS
        suite.expect(magnifierLeftOut > 0 && magnifierKept > 0,
                     "the clipboard header keeps its magnifier beside the camera where it fits and leaves it to the menu elsewhere")

        // Beside the camera the title's side is exactly as wide as counted, so
        // the row must draw as wide and no wider: a spacer's spacing would cut
        // the title. Text measured by AppKit and rounded up may draw a little
        // narrower, never by a button.
        func drawnWidth(_ header: Header, explore: Bool) -> CGFloat {
            let host = NSHostingView(rootView: header.pageTitle(quickActions: explore ? [.explore] : []).fixedSize())
            host.layoutSubtreeIfNeeded()
            return host.fittingSize.width
        }
        // Below the camera, and beside it at the default and 480-point sizes,
        // where the clipboard title may go without its magnifier.
        let headers = [NotchGeometry(screen: screen, safeAreaTop: 0, cameraWidth: 0)]
            + [NotchSize.spacious, .compact].map {
                NotchGeometry(screen: screen, safeAreaTop: 37.5, cameraWidth: 200, layout: $0)
            }
        for language in AppLanguage.allCases {
            for module in [NotchModule.clipboard, .files] {
                suite.expect(headers.allSatisfy { geometry in
                    [false, true].allSatisfy { explore in
                        let title = module.title(language)
                        let titled = Service()
                        titled.selected = module
                        titled.clipboardHeaderShowsSearch = NotchLayout.pageShowsSearch(title, module: module, button: !explore,
                                                                                        in: geometry)
                        var header = Header(service: titled)
                        header.l10n.language = language
                        header.showsClipboardActions = module == .clipboard
                        let counted = NotchLayout.pageTitleWidth(title, module: module, button: !explore, in: geometry)
                        let drawn = drawnWidth(header, explore: explore)
                        return drawn <= counted && drawn > counted - 4
                    }
                }, "the \(language.rawValue) \(module.rawValue) title row draws as wide as the island counts it")
            }
        }

        // Below the camera the header's buttons keep their room while out of
        // sight. The clipboard's three join them, so where all of them would cut
        // the title they gather in the menu: in every language and island
        // width, whichever of Explore, Settings and Keep open float beside it.
        func drawn<Content: View>(_ view: Content) -> CGFloat {
            let host = NSHostingView(rootView: view.fixedSize())
            host.layoutSubtreeIfNeeded()
            return host.fittingSize.width
        }
        let floating: [[NotchQuickAction]] = [[], [.explore], [.settings], [.pin], [.explore, .settings],
                                              [.explore, .pin], [.settings, .pin], [.explore, .settings, .pin]]
        let widths = stride(from: NotchSize.widthRange.lowerBound, through: NotchSize.widthRange.upperBound, by: 40).map {
            NotchGeometry(screen: CGRect(x: 0, y: 0, width: 1710, height: 1112), safeAreaTop: 0, cameraWidth: 0,
                          layout: .custom, customWidth: $0).contentWidth
        }
        for language in AppLanguage.allCases {
            let page = Service()
            var below = Header(service: page)
            below.l10n.language = language
            below.showsClipboardActions = true
            suite.expect(floating.allSatisfy { actions in
                let title = drawn(below.pageTitle(quickActions: actions))
                return widths.allSatisfy { width in
                    page.contentSize.width = width
                    return title + 6 + drawn(below.headerActions(quickActions: actions)) <= width
                }
            }, "the \(language.rawValue) clipboard title keeps its room beside the header's buttons in every island")
        }
        let roomy = Service()
        roomy.contentSize.width = widths.last ?? 0
        var english = Header(service: roomy)
        english.showsClipboardActions = true
        suite.expect(drawn(english.headerActions(quickActions: [])) > 3 * 28,
                     "a header with room beside the clipboard title keeps its filter, clearing and history window in view")
        let inline = drawn(english.headerActions(quickActions: []))
        english.updates.state = .available(version: "9.9")
        suite.expect(drawn(english.headerActions(quickActions: [])) < inline - 2 * 28,
                     "an offered update moves the clipboard's filter, clearing and history window into the menu")
    }
}
