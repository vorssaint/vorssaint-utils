// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit

/// The vorssaint:// scheme is how things outside the app ask it to run one of
/// its own tools. The parser is the only gate on that door, so every rule
/// about what gets in and what stays out is pinned here. The production
/// bodies that run a link (generated into DeepLinkDispatch.swift) run against
/// the doubles below.
enum DeepLinkTests {
    static var defaults: UserDefaults!
    static var beeps = 0

    enum NSSound { static func beep() { DeepLinkTests.beeps += 1 } }
    enum CommandBarCatalog { static func runScriptDirectly(_ link: CommandBarLink) {} }

    /// What the row saw when it ran: its number, and whether the bar was
    /// still on screen. The bar learns typed text only while it is visible.
    struct Ran: Equatable {
        let key: String
        let value: Int?
        let barVisible: Bool
    }

    class BarFixture {
        var entries: [String: CommandBarEntry] = [:]
        var rebuilds = 0
        var isVisible = false
        var hiddenCache: Set<String> = []
        var prompted: [String?] = []
        var ran: [Ran] = []
        func freshFullEntry(forStableKey key: String) -> CommandBarEntry? {
            rebuilds += 1
            return entries[key]
        }
        func isEnabled(_ source: CommandBarSource) -> Bool { true }
        func show(promptingFor stableKey: String?) {
            prompted.append(stableKey)
            isVisible = true
        }
        func hide() { isVisible = false }
        func finish(_ entry: CommandBarEntry, value: Int?) {
            ran.append(Ran(key: entry.stableKey, value: value, barVisible: isVisible))
        }
        func installedApp(for entry: CommandBarEntry) -> InstalledApps.InstalledApp? { nil }
        func runningApplication(for app: InstalledApps.InstalledApp) -> NSRunningApplication? { nil }
    }

    final class Application {}
    final class Rows {
        var ran: [DeepLinkSupport.Request] = []
        func runExternalRow(withStableKey key: String, argument: Int?) {
            ran.append(DeepLinkSupport.Request(stableKey: key, argument: argument))
        }
    }
    enum Commands { static var shared = Rows() }
    class DelegateFixture {
        typealias NSApplication = Application
        typealias CommandBarService = Commands
    }

    static func run(_ suite: TestSuite) {
        parsing(suite)
        uninstalledCommandBar(suite)
        numberedLinkWithBarOpen(suite)
        linkThatLaunchesTheApp(suite)
    }

    private static func parsing(_ suite: TestSuite) {
        func link(_ string: String) -> DeepLinkSupport.Request? {
            guard let url = URL(string: string) else {
                suite.expect(false, "deep link test URL failed to parse itself: \(string)")
                return nil
            }
            return DeepLinkSupport.parse(url)
        }

        suite.expect(link("vorssaint://run/action.screenshot")?.stableKey == "action.screenshot",
                     "a plain run link carries its action id")
        suite.expect(link("VORSSAINT://Run/action.screenshot")?.stableKey == "action.screenshot",
                     "the scheme and the verb are case insensitive")
        suite.expect(link("vorssaint://run/action.soundOutput.ABC-012")?.stableKey == "action.soundOutput.ABC-012",
                     "an action id keeps its case, so device uid keys survive")
        suite.expect(link("vorssaint://run/action.brightness?v=40")
                         == DeepLinkSupport.Request(stableKey: "action.brightness", argument: 40),
                     "v arrives as the numeric argument")
        suite.expect(link("vorssaint://run/action.brightness?v=-30")?.argument == -30,
                     "a negative v parses")
        suite.expect(link("vorssaint://run/action.volume?other=1")
                         == DeepLinkSupport.Request(stableKey: "action.volume", argument: nil),
                     "a query key other than v is not an argument")
        suite.expect(link("vorssaint://run/action.brightness?v=abc")
                         == DeepLinkSupport.Request(stableKey: "action.brightness", argument: nil),
                     "garbage v counts as absent, so the row can still ask for a number itself")
        for rejected in ["https://run/action.screenshot", "vorssaint://settings/page",
                         "vorssaint://run", "vorssaint://run/action/screenshot"] {
            suite.expect(link(rejected) == nil, "\(rejected) is rejected")
        }
    }

    private static func row(_ key: String, numericRange: ClosedRange<Int>? = nil,
                            confirmationPrompt: String? = nil) -> CommandBarEntry {
        CommandBarEntry(id: key, title: key, subtitle: "", icon: .symbol("bolt"),
                        numericRange: numericRange, confirmationPrompt: confirmationPrompt,
                        run: { _ in })
    }

    /// A fresh bar over a private defaults domain, with the Command Bar
    /// installed or not in the features hub.
    private static func bar(installed: Bool, shortcutEnabled: Bool = true, visible: Bool = false) -> Bar {
        let name = "com.vorssaint.tests.deep-links"
        defaults = UserDefaults(suiteName: name)
        defaults.removePersistentDomain(forName: name)
        defaults.set(installed, forKey: AppFeature.commandBar.availabilityKey)
        defaults.set(shortcutEnabled, forKey: DefaultsKey.commandBarShortcutEnabled)
        beeps = 0
        let bar = Bar()
        bar.isVisible = visible
        for entry in [row("action.keepAwake.60"), row("action.brightness", numericRange: 0...100),
                      row("action.emptyTrash", confirmationPrompt: "Empty the Trash?")] {
            bar.entries[entry.stableKey] = entry
        }
        return bar
    }

    /// Review point 1: an uninstalled Command Bar has no rows, so a link beeps
    /// and runs nothing. A closed bar or a disabled bar shortcut is not
    /// uninstalled, and links keep working there.
    private static func uninstalledCommandBar(_ suite: TestSuite) {
        for key in ["action.keepAwake.60", "action.emptyTrash", "action.missing"] {
            let uninstalled = bar(installed: false)
            uninstalled.runExternalRow(withStableKey: key, argument: nil)
            suite.expect(beeps == 1 && uninstalled.ran.isEmpty && uninstalled.prompted.isEmpty,
                         "with the Command Bar uninstalled, a link to \(key) beeps and runs nothing")
            suite.expect(uninstalled.rebuilds == 0,
                         "with the Command Bar uninstalled, a link to \(key) does not rebuild its rows")
        }
        let numbered = bar(installed: false)
        numbered.runExternalRow(withStableKey: "action.brightness", argument: 40)
        suite.expect(beeps == 1 && numbered.ran.isEmpty && numbered.rebuilds == 0,
                     "with the Command Bar uninstalled, a numbered link beeps and runs nothing")

        let closed = bar(installed: true, shortcutEnabled: false)
        closed.runExternalRow(withStableKey: "action.keepAwake.60", argument: nil)
        suite.expect(beeps == 0 && closed.ran == [Ran(key: "action.keepAwake.60", value: nil, barVisible: false)],
                     "a link runs its row with the bar closed and the bar shortcut off")
        let asks = bar(installed: true, shortcutEnabled: false)
        asks.runExternalRow(withStableKey: "action.emptyTrash", argument: nil)
        suite.expect(beeps == 0 && asks.prompted == ["action.emptyTrash"] && asks.ran.isEmpty,
                     "a link to a row that confirms opens the bar to ask, even with the bar shortcut off")
        let unknown = bar(installed: true)
        unknown.runExternalRow(withStableKey: "action.missing", argument: nil)
        suite.expect(beeps == 1 && unknown.ran.isEmpty && unknown.prompted.isEmpty,
                     "a link to an id no row answers beeps and runs nothing")
    }

    /// Review point 2: a numbered link that arrives while the bar is open with
    /// typed text closes the bar before the row runs. recordUsage learns the
    /// typed text only while the bar is visible, so it learns nothing here.
    private static func numberedLinkWithBarOpen(_ suite: TestSuite) {
        let open = bar(installed: true, visible: true)
        open.runExternalRow(withStableKey: "action.brightness", argument: 40)
        suite.expect(open.ran == [Ran(key: "action.brightness", value: 40, barVisible: false)],
                     "a numbered link closes an open bar before its row runs")
        let clamped = bar(installed: true, visible: true)
        clamped.runExternalRow(withStableKey: "action.brightness", argument: 140)
        suite.expect(clamped.ran == [Ran(key: "action.brightness", value: 100, barVisible: false)],
                     "a numbered link is clamped to the row's range")
        let plain = bar(installed: true, visible: true)
        plain.runExternalRow(withStableKey: "action.keepAwake.60", argument: nil)
        suite.expect(plain.ran == [Ran(key: "action.keepAwake.60", value: nil, barVisible: false)],
                     "a link without a number also closes an open bar before its row runs")
        let missingNumber = bar(installed: true)
        missingNumber.runExternalRow(withStableKey: "action.brightness", argument: nil)
        suite.expect(missingNumber.prompted == ["action.brightness"] && missingNumber.ran.isEmpty,
                     "a link without the number its row needs opens the bar to ask for it")
        let confirms = bar(installed: true, visible: true)
        confirms.runExternalRow(withStableKey: "action.emptyTrash", argument: 1)
        suite.expect(confirms.prompted == ["action.emptyTrash"] && confirms.ran.isEmpty,
                     "a number does not answer a row's confirmation")
    }

    /// Review point 3: AppKit can deliver the link that launches the app before
    /// applicationDidFinishLaunching. The link waits through any main-queue
    /// turns during startup and runs once when startup calls
    /// runDeepLinksFromLaunch().
    private static func linkThatLaunchesTheApp(_ suite: TestSuite) {
        Commands.shared = Rows()
        beeps = 0
        let delegate = Delegate()
        let launching = [URL(string: "vorssaint://run/action.keepAwake.60")!,
                         URL(string: "vorssaint://run/action.brightness?v=40")!]
        delegate.application(Application(), open: launching)
        _ = RunLoop.main.run(mode: .default, before: Date(timeIntervalSinceNow: 0.05))
        suite.expect(Commands.shared.ran.isEmpty,
                     "a link that arrives during startup does not run before startup finishes")
        delegate.runDeepLinksFromLaunch()
        suite.expect(Commands.shared.ran == [DeepLinkSupport.Request(stableKey: "action.keepAwake.60", argument: nil),
                                             DeepLinkSupport.Request(stableKey: "action.brightness", argument: 40)],
                     "links that launched the app run in order once startup finishes")
        delegate.runDeepLinksFromLaunch()
        suite.expect(Commands.shared.ran.count == 2, "a link from launch runs only once")
        delegate.application(Application(), open: [URL(string: "vorssaint://run/action.darkMode")!])
        suite.expect(Commands.shared.ran.last == DeepLinkSupport.Request(stableKey: "action.darkMode", argument: nil)
                         && Commands.shared.ran.count == 3,
                     "after startup a link runs as soon as it arrives")
        delegate.application(Application(), open: [URL(string: "vorssaint://settings/page")!])
        suite.expect(beeps == 1 && Commands.shared.ran.count == 3, "a link the parser rejects beeps")
    }
}
