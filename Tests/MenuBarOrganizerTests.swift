// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import CoreGraphics
import Foundation

enum MenuBarOrganizerTests {
    private static let own = "com.vorssaint.app"
    private static let collapser = MenuBarItemIdentity(bundleID: own, title: "VorssaintMenuBarOrganizer")

    private static func identity(_ bundle: String, _ title: String = "Item-0") -> MenuBarItemIdentity {
        MenuBarItemIdentity(bundleID: bundle, title: title)
    }

    private static func item(_ bundle: String, _ title: String = "Item-0", x: CGFloat,
                             width: CGFloat = 30, bundleless: Bool = false,
                             appleSigned: Bool = true) -> MenuBarItemSnapshot {
        MenuBarItemSnapshot(identity: identity(bundle, title),
                            frame: CGRect(x: x, y: 0, width: width, height: 33),
                            pid: 100, appName: bundle, hostIsBundleless: bundleless,
                            hostIsAppleSigned: appleSigned)
    }

    private static func system(_ suffix: String) -> MenuBarItemIdentity {
        identity(MenuBarOrganizerPolicy.agentBundleID, "com.apple.menuextra." + suffix)
    }

    /// A bar with two hideable apps and a helper left of the collapser, one app,
    /// Vorssaint's main icon and the battery right of it.
    private static let bar: [MenuBarItemSnapshot] = [
        item("com.example.alpha", x: 1000),
        item("com.example.helper", x: 1030, bundleless: true),
        item("com.example.beta", x: 1060),
        item(own, "VorssaintMenuBarOrganizer", x: 1090),
        item("com.example.gamma", x: 1120),
        item(own, "Vorssaint", x: 1150),
        item(MenuBarOrganizerPolicy.agentBundleID, "com.apple.menuextra.battery", x: 1180)
    ]

    static func run(_ suite: TestSuite) {
        icons(suite)
        identities(suite)
        inventoryElements(suite)
        settingsActions(suite)
        revealActions(suite)
        systemItems(suite)
        availability(suite)
        partition(suite)
        allowlist(suite)
        peekSets(suite)
        movePlanner(suite)
        dropPoints(suite)
        quietGate(suite)
        hiddenRecords(suite)
        editor(suite)
        tierMoves(suite)
        managers(suite)
    }

    /// The production resolver is compiled against this read-only AX tree.
    enum InventoryReader {
        final class Element {
            let role: String
            let frame: CGRect?
            var extras: Element?
            var children: [Element] = []
            var extrasReads = 0
            init(_ role: String, frame: CGRect? = nil) {
                self.role = role
                self.frame = frame
            }
        }
        typealias AXUIElement = Element
        static func role(of element: Element) -> String { element.role }
        static func frame(of element: Element) -> CGRect? { element.frame }
        static func children(of element: Element) -> [Element] { element.children }
        static func elementAttribute(_ element: Element, _ attribute: String) -> Element? {
            precondition(attribute == "AXExtrasMenuBar")
            element.extrasReads += 1
            return element.extras
        }
    }

    private static func inventoryElements(_ suite: TestSuite) {
        typealias Reader = InventoryReader
        let group = CGRect(x: 100, y: 0, width: 38, height: 33)
        let button = Reader.Element("AXButton", frame: CGRect(x: 107, y: 4.5, width: 24, height: 24))
        let sibling = Reader.Element("AXMenuBarItem", frame: CGRect(x: 150, y: 4.5, width: 44, height: 24))
        let extras = Reader.Element("AXMenuBar")
        extras.children = [sibling, button]
        let app = Reader.Element("AXApplication")
        app.extras = extras
        var cache: [pid_t: [Reader.Element]] = [:]
        suite.expect(Reader.statusElement(button, groupFrame: group, ownerPID: 100, appItems: &cache) === button,
                     "a direct status button is kept without reading an application extras bar")
        suite.expect(Reader.statusElement(app, groupFrame: group, ownerPID: 100, appItems: &cache) === button,
                     "the macOS 27.0 application wrapper resolves to its actual status button")
        suite.expect(Reader.statusElement(app, groupFrame: CGRect(x: 148, y: 0, width: 48, height: 33),
                     ownerPID: 100, appItems: &cache) === sibling && app.extrasReads == 1,
                     "two groups of one app resolve distinct controls from one cached extras-bar read")
        suite.expect(Reader.statusElement(app, groupFrame: CGRect(x: 500, y: 0, width: 38, height: 33),
                     ownerPID: 100, appItems: &cache) == nil,
                     "an unmatched frame never substitutes a sibling or the application wrapper")
        let unavailable = Reader.Element("AXApplication")
        suite.expect(Reader.statusElement(unavailable, groupFrame: group, ownerPID: 200, appItems: &cache) == nil,
                     "a missing extras bar fails closed and cannot reuse another app's cached controls")
        extras.children = [button, Reader.Element("AXMenuBarItem", frame: button.frame)]
        cache = [:]
        suite.expect(Reader.statusElement(app, groupFrame: group, ownerPID: 100, appItems: &cache) == nil,
                     "overlapping candidate controls are rejected instead of guessing the boundary")
        extras.children = [Reader.Element("AXMenuBarItem"), Reader.Element("AXMenuBarItem", frame: .zero)]
        cache = [:]
        suite.expect(Reader.statusElement(app, groupFrame: group, ownerPID: 100, appItems: &cache) == nil,
                     "missing and zero-size control frames cannot identify a status icon")
    }

    enum SettingsActions {
        typealias Editor = MenuBarOrganizerEditorSupport
        final class Service {
            enum State { case expanded, collapsed, applying }
            var state = State.expanded
            var calls: [(MenuBarLayout, Bool)] = []
            func apply(_ target: MenuBarLayout, collapseAfterApplying: Bool) {
                calls.append((target, collapseAfterApplying))
            }
        }
        class Fixture {
            let service = Service()
            var baseline = MenuBarLayout(hidden: [], visible: [])
            var locked = Set<MenuBarItemIdentity>()
            func lockReason(_ identity: MenuBarItemIdentity) -> String? {
                locked.contains(identity) ? "locked" : nil
            }
        }
        struct DropInfo {}
        class DropFixture {
            var dragging: MenuBarItemIdentity?
            var moves: [MenuBarItemIdentity] = []
            func moved(_ identity: MenuBarItemIdentity) { moves.append(identity) }
        }
    }

    private static func settingsActions(_ suite: TestSuite) {
        let alpha = identity("com.example.alpha")
        let beta = identity("com.example.beta")
        let view = SettingsActions.View()
        view.baseline = MenuBarLayout(hidden: [], visible: [alpha, beta])
        view.move(alpha, to: .hide, before: nil)
        suite.expect(view.service.calls.count == 1 && view.service.calls[0].0.hidden == [alpha]
                     && view.service.calls[0].0.visible == [beta] && view.service.calls[0].1,
                     "choosing Hide submits the change immediately and collapses an expanded bar")
        view.service.calls = []
        view.baseline = MenuBarLayout(hidden: [alpha], visible: [beta])
        view.move(alpha, to: .show, before: nil)
        suite.expect(view.service.calls.count == 1 && !view.service.calls[0].0.hidden.contains(alpha)
                     && view.service.calls[0].0.visible.contains(alpha) && !view.service.calls[0].1,
                     "choosing Show always submits immediately without forcing a new collapse")
        view.service.calls = []
        view.move(alpha, to: .never, before: nil)
        suite.expect(view.service.calls.count == 1 && view.service.calls[0].0.neverShown == [alpha],
                     "choosing Never show also submits immediately")
        view.service.calls = []
        view.service.state = .applying
        view.move(beta, to: .hide, before: nil)
        suite.expect(view.service.calls.isEmpty, "a change already in flight cannot be superseded by another row action")
        view.service.state = .expanded
        view.locked = [beta]
        view.move(beta, to: .hide, before: nil)
        suite.expect(view.service.calls.isEmpty, "locked rows do not trigger an automatic apply")

        let drop = SettingsActions.Drop()
        drop.dragging = alpha
        suite.expect(drop.performDrop(info: .init()) && drop.moves == [alpha] && drop.dragging == nil,
                     "a completed drop commits once and clears the dragged row")
        suite.expect(!drop.performDrop(info: .init()) && drop.moves == [alpha],
                     "a missing or already-consumed drag does not commit another change")
    }

    enum RevealActions {
        enum State { case off, expanded, collapsed, applying }
        final class Collapser {
            var collapsed = true
            func setCollapsed(_ collapsed: Bool, shelfOpen: Bool) { self.collapsed = collapsed }
        }
        final class RehideTimer {
            var invalidated = false
            func invalidate() { invalidated = true }
        }
        class Fixture {
            var state: State = .collapsed
            var epoch = 0
            let collapser = Collapser()
            var releases: [String] = []
            var expandedRestrictions = 0
            var rehideTimer: RehideTimer?
            var scheduledTimers = 0
            var restorations: [(Int, Bool)] = []
            func advance() { epoch += 1 }
            func release(_ reason: String) { releases.append(reason) }
            func restrictExpanded() { expandedRestrictions += 1 }
            func scheduleAutoRehide() { scheduledTimers += 1 }
            func restoreOrderAfterReveal(token: Int, collapseAfterwards: Bool) {
                restorations.append((token, collapseAfterwards))
                state = .applying
            }
        }
    }

    private static func revealActions(_ suite: TestSuite) {
        let service = RevealActions.Service()
        service.expand()
        suite.expect(service.expandedRestrictions == 1 && service.restorations.count == 1
                     && service.restorations[0].0 == service.epoch && !service.restorations[0].1
                     && service.state == .applying && !service.collapser.collapsed,
                     "expanding keeps never-shown icons restricted and restores order before reading the returning bar")
        service.expand()
        suite.expect(service.restorations.count == 1,
                     "another expand cannot adopt a partially restored bar")
        service.state = .expanded
        service.expand()
        suite.expect(service.releases.last == "expand while settling" && service.restorations.count == 1,
                     "cancelling a pending collapse leaves a bar that was never hidden alone")
        service.state = .off
        let epoch = service.epoch
        service.expand()
        suite.expect(service.epoch == epoch, "an inactive organizer cannot start restoring icons")

        let oldTimer = RevealActions.RehideTimer()
        service.rehideTimer = oldTimer
        service.state = .expanded
        service.refreshAutoRehide()
        suite.expect(oldTimer.invalidated && service.rehideTimer == nil && service.scheduledTimers == 1,
                     "changing the delay while icons are shown cancels the old timer and reschedules immediately")
        service.state = .collapsed
        service.refreshAutoRehide()
        suite.expect(service.scheduledTimers == 1, "a collapsed bar does not start an unnecessary rehide timer")
    }

    private static func icons(_ suite: TestSuite) {
        suite.expect(MenuBarOrganizerIcon.stored("dots") == .dots
                        && MenuBarOrganizerIcon.stored("sparkles") == .chevron
                        && MenuBarOrganizerIcon.stored(nil) == .chevron,
                     "an unknown or missing stored icon falls back to the chevron")
        suite.expect(MenuBarOrganizerReveal.stored("shelf") == .shelf
                        && MenuBarOrganizerReveal.stored("drawer") == .menuBar
                        && MenuBarOrganizerReveal.stored(nil) == .menuBar,
                     "an unknown or missing stored reveal falls back to the menu bar")

        let chevron = MenuBarOrganizerIcon.chevron
        suite.expect(chevron.symbol(collapsed: true, reveal: .menuBar, shelfOpen: false) == "chevron.left"
                        && chevron.symbol(collapsed: false, reveal: .menuBar, shelfOpen: false) == "chevron.right"
                        && chevron.symbol(collapsed: true, reveal: .menuBar, shelfOpen: true) == "chevron.left",
                     "in the bar the chevron points at the hidden icons while they are hidden")
        suite.expect(chevron.symbol(collapsed: true, reveal: .shelf, shelfOpen: false) == "chevron.down"
                        && chevron.symbol(collapsed: true, reveal: .shelf, shelfOpen: true) == "chevron.up"
                        && chevron.symbol(collapsed: false, reveal: .shelf, shelfOpen: false) == "chevron.down",
                     "with a shelf the chevron points down while it is closed and up while it is open")
        let states = [false, true].flatMap { collapsed in
            MenuBarOrganizerReveal.allCases.flatMap { reveal in
                [false, true].map { (collapsed, reveal, $0) }
            }
        }
        suite.expect(MenuBarOrganizerIcon.allCases.filter { $0 != .chevron }.allSatisfy { icon in
                        Set(states.map { icon.symbol(collapsed: $0.0, reveal: $0.1, shelfOpen: $0.2) }).count == 1
                     },
                     "the other icons ignore the state, the reveal and the shelf")
    }

    private static func identities(_ suite: TestSuite) {
        let first = MenuBarItemIdentity.make(bundleID: "a", identifier: "ident", description: "desc", taken: [])
        suite.expect(first.title == "ident", "the identifier names the item")
        let described = MenuBarItemIdentity.make(bundleID: "a", identifier: "  ", description: "desc", taken: [])
        suite.expect(described.title == "desc", "the description names an item without an identifier")
        // What an app that only sets a title looks like: the title, which it
        // rewrites at will, is not among the strings an identity is made of.
        let unnamed = MenuBarItemIdentity.make(bundleID: "a", identifier: nil, description: "", taken: [])
        suite.expect(unnamed.title == "Item-0", "an item with neither is Item-0, whatever its title says")
        let second = MenuBarItemIdentity.make(bundleID: "a", identifier: nil, description: nil, taken: [unnamed])
        suite.expect(second.title == "Item-1", "a second unnamed item of one app stays distinct")
        let repeated = MenuBarItemIdentity.make(bundleID: "a", identifier: "ident", description: nil, taken: [first])
        suite.expect(repeated != first && repeated.title == "ident-1", "a repeated name stays distinct")
        let other = MenuBarItemIdentity.make(bundleID: "b", identifier: "ident", description: nil, taken: [first])
        suite.expect(other.title == "ident", "names only collide within one bundle")
    }

    private static func systemItems(_ suite: TestSuite) {
        let rows: [(String, MenuBarSystemItem)] = [
            ("battery", .battery), ("bluetooth", .bluetooth), ("clock", .clock), ("display", .displays),
            ("displays", .displays), ("textinput", .keyboard), ("keyboard", .keyboard), ("sound", .sound),
            ("wifi", .wifi), ("screen-mirroring", .screenMirroring), ("controlcenter", .controlCenter)
        ]
        for (suffix, expected) in rows {
            suite.expect(MenuBarSystemItem.item(for: system(suffix)) == expected, "\(suffix) is system item \(expected.rawValue)")
        }
        suite.expect(MenuBarSystemItem.allCases.map(\.rawValue) == Array(0...8)
                        && MenuBarSystemItem.wifi.rawValue == 6 && MenuBarSystemItem.controlCenter.rawValue == 8,
                     "the raw values are the indices the allowlist takes")
        suite.expect(MenuBarSystemItem.item(for: identity("com.apple.TextInputMenuAgent", "Item-0")) == .keyboard,
                     "the input menu's own process is the keyboard item whatever it is called")
        suite.expect(MenuBarSystemItem.item(for: system("focus")) == nil
                        && MenuBarSystemItem.item(for: identity("com.example.alpha", "com.apple.menuextra.battery")) == nil,
                     "an unknown extra and an app borrowing a system name are no system items")

        func snapshot(_ identity: MenuBarItemIdentity) -> MenuBarItemSnapshot {
            MenuBarItemSnapshot(identity: identity, frame: .zero, pid: 1, appName: nil, hostIsBundleless: false,
                                hostIsAppleSigned: true)
        }
        func verdict(_ identity: MenuBarItemIdentity) -> [Bool] {
            [MenuBarOrganizerPolicy.canHide(snapshot(identity), ownBundleID: own), MenuBarOrganizerPolicy.isMovable(identity)]
        }
        suite.expect(verdict(system("wifi")) == [true, true]
                        && verdict(identity("com.apple.TextInputMenuAgent")) == [true, true],
                     "a system item with an index hides and moves")
        suite.expect(verdict(system("clock")) == [false, false] && verdict(system("controlcenter")) == [false, false],
                     "the items macOS pins neither hide nor move")
        suite.expect(verdict(system("focus")) == [false, false], "a system item without an index neither hides nor moves")
        suite.expect(verdict(identity("com.example.alpha")) == [true, true] && verdict(collapser) == [false, true],
                     "apps are judged as before")

        func opens(_ bundleID: String?, backgroundOnly: Bool = false) -> Bool {
            MenuBarOrganizerPolicy.launchMayAddIcon(bundleID: bundleID, backgroundOnly: backgroundOnly, ownBundleID: own)
        }
        suite.expect(opens("com.example.alpha") && opens("com.apple.TextInputMenuAgent"),
                     "an app or agent launch opens the bar for its icon")
        suite.expect(!opens("com.apple.screencaptureui"),
                     "the screenshot helper never brings an icon, so the shortcut leaves the bar collapsed")
        suite.expect(!opens(nil) && !opens(own) && !opens("com.example.alpha", backgroundOnly: true),
                     "no bundle, Vorssaint itself and background-only processes do not open the bar")
    }

    private static func availability(_ suite: TestSuite) {
        typealias Gate = MenuBarOrganizerAvailability
        suite.expect(Gate.unsupportedReason(majorVersion: 26, versionString: "26.4", bridgeAvailable: true)
                         == .requiresMacOS27(current: "26.4"),
                     "macOS 26 is refused with its own version, even if the API were there")
        suite.expect(Gate.unsupportedReason(majorVersion: 27, versionString: "27.2", bridgeAvailable: false)
                         == .apiMissing,
                     "macOS 27 without the private API reports the missing API")
        suite.expect(Gate.unsupportedReason(majorVersion: 27, versionString: "27.2", bridgeAvailable: true) == nil,
                     "macOS 27 with the API is supported")
        suite.expect(Gate.unsupportedReason(majorVersion: 28, versionString: "28.0", bridgeAvailable: true) == nil,
                     "later versions stay supported")
    }

    private static func partition(_ suite: TestSuite) {
        let layout = MenuBarOrganizerLayout.partition(bar.reversed(), collapser: collapser)
        suite.expect(layout?.hidden == [identity("com.example.alpha"), identity("com.example.helper"),
                                        identity("com.example.beta")],
                     "items left of the collapser are hidden, in visual order whatever the input order")
        suite.expect(layout?.visible == [identity("com.example.gamma"), identity(own, "Vorssaint"),
                                         identity(MenuBarOrganizerPolicy.agentBundleID, "com.apple.menuextra.battery")],
                     "items right of the collapser are visible and the collapser is on neither side")
        suite.expect(MenuBarOrganizerLayout.partition(bar.filter { $0.identity != collapser }, collapser: collapser) == nil,
                     "a missing collapser yields no layout")
        suite.expect(MenuBarOrganizerLayout.partition([], collapser: collapser) == nil,
                     "an empty walk yields no layout")
    }

    private static func allowlist(_ suite: TestSuite) {
        guard let layout = MenuBarOrganizerLayout.partition(bar, collapser: collapser) else {
            suite.expect(false, "the reference bar partitions")
            return
        }
        typealias Hidden = MenuBarHiddenSet
        func bundles(_ ids: String...) -> Hidden { Hidden(ids.map { identity($0) }) }
        let hidden = MenuBarOrganizerLayout.hidden(in: layout, items: bar, ownBundleID: own)
        suite.expect(hidden == bundles("com.example.alpha", "com.example.beta"),
                     "only addressable hosts left of the collapser are hidden")

        let running: Set<String> = ["com.example.alpha", "com.example.gamma", "com.example.windowed"]
        let list = MenuBarOrganizerLayout.allowlist(hidden: hidden, neverShown: Hidden(), observed: bar,
                                                    running: running, ownBundleID: own)
        suite.expect(list?.bundles == ["com.example.gamma", "com.example.helper", "com.example.windowed", own].sorted(),
                     "everything running or observed stays allowed except the hidden bundles")
        suite.expect(list?.systemItems == Array(0...8), "with no system item hidden all nine stay allowed")

        // Vorssaint's own icon, a helper and the pinned clock dragged left of
        // the collapser must not turn into hide requests; the battery does.
        let clock = item(MenuBarOrganizerPolicy.agentBundleID, "com.apple.menuextra.clock", x: 1210)
        let dragged = MenuBarLayout(hidden: [identity(own, "Vorssaint"), identity("com.example.helper"),
                                             clock.identity, system("battery")],
                                    visible: [])
        let onlyBattery = MenuBarOrganizerLayout.hidden(in: dragged, items: bar + [clock], ownBundleID: own)
        suite.expect(onlyBattery == Hidden([system("battery")]) && onlyBattery.bundles.isEmpty,
                     "own, pinned and bundleless items are never hidden, a system item is hidden by index")
        let withoutBattery = MenuBarOrganizerLayout.allowlist(hidden: onlyBattery, neverShown: Hidden([system("wifi")]),
                                                              observed: bar, running: running, ownBundleID: own)
        suite.expect(withoutBattery?.systemItems == [1, 2, 3, 4, 5, 7, 8],
                     "a hidden and a never-shown system item are left out of the allowed indices")
        suite.expect(withoutBattery?.bundles == (running.union(bar.map(\.identity.bundleID))
                                                    .subtracting([MenuBarOrganizerPolicy.agentBundleID])).sorted(),
                     "hiding only system items still restricts the bar, with every app allowed")
        let withoutKeyboard = MenuBarOrganizerLayout.allowlist(
            hidden: Hidden([identity("com.apple.TextInputMenuAgent")]), neverShown: Hidden(), observed: bar,
            running: running.union(["com.apple.TextInputMenuAgent"]), ownBundleID: own)
        suite.expect(withoutKeyboard?.systemItems == [0, 1, 2, 3, 5, 6, 7, 8]
                        && withoutKeyboard?.bundles.contains("com.apple.TextInputMenuAgent") == false,
                     "a hidden input menu loses its index and its process is not allowed either")
        suite.expect(MenuBarOrganizerLayout.allowlist(hidden: Hidden(), neverShown: Hidden(), observed: bar,
                                                      running: running, ownBundleID: own) == nil,
                     "nothing to hide means no assertion")
        suite.expect(MenuBarOrganizerLayout.allowlist(
                         hidden: Hidden([identity(own), identity("com.example.helper"), system("clock")]),
                         neverShown: Hidden([system("focus"), identity(own), system("controlcenter")]),
                         observed: bar, running: running, ownBundleID: own) == nil,
                     "a request naming only protected bundles and pinned items hides nothing")

        let expanded = MenuBarOrganizerLayout.allowlist(hidden: Hidden(), neverShown: bundles("com.example.gamma"),
                                                        observed: bar, running: running, ownBundleID: own)
        suite.expect(expanded?.bundles == ["com.example.alpha", "com.example.beta", "com.example.helper",
                                           "com.example.windowed", own].sorted(),
                     "an expanded bar keeps only the never-shown bundles out")
        let both = MenuBarOrganizerLayout.allowlist(hidden: hidden, neverShown: bundles("com.example.gamma"),
                                                    observed: bar, running: running, ownBundleID: own)
        suite.expect(both?.bundles == ["com.example.helper", "com.example.windowed", own].sorted(),
                     "a collapsed bar keeps the hidden and the never-shown bundles out")

        let delta = identity("com.example.delta")
        let never = MenuBarLayout(hidden: [], visible: [],
                                  neverShown: [delta, identity("com.example.gamma"), identity("com.example.helper"),
                                               identity("com.example.unknown"), system("battery")])
        var keptOut = bundles("com.example.delta", "com.example.gamma")
        keptOut.systemItems = [.battery]
        suite.expect(MenuBarOrganizerLayout.neverShown(
                         in: never, items: bar, known: [MenuBarHiddenRecord(identity: delta, appName: "Delta")],
                         ownBundleID: own) == keptOut,
                     "a never-shown item gone from the bar is taken from its record, one in the bar must be hideable")

        let everything = MenuBarOrganizerLayout.allowlist(hidden: bundles("com.example.alpha", own),
                                                          neverShown: Hidden(), observed: [item("com.example.alpha", x: 0)],
                                                          running: [], ownBundleID: own)
        suite.expect(everything?.bundles == [own],
                     "the allowlist is never empty: the own bundle is always on it")
        suite.expect(MenuBarOrganizerLayout.allowlist(hidden: bundles("com.example.alpha"), neverShown: Hidden(), observed: [],
                                                      running: [], ownBundleID: "") == nil,
                     "without an own bundle id there is nothing safe to allow")
    }

    private static func peekSets(_ suite: TestSuite) {
        let set = MenuBarHiddenSet([identity("com.example.alpha", "first"), identity("com.example.alpha", "second"),
                                    identity("com.example.beta"), system("wifi"), system("battery")])
        var withoutAlpha = set
        withoutAlpha.bundles.remove("com.example.alpha")
        suite.expect(set.excluding(identity("com.example.alpha", "second")) == withoutAlpha,
                     "peeking at an app's icon reveals its bundle and keeps everything else hidden")
        var withoutWiFi = set
        withoutWiFi.systemItems.remove(.wifi)
        suite.expect(set.excluding(system("wifi")) == withoutWiFi,
                     "peeking at a system item reveals that item only, not the agent's bundle")
        suite.expect(set.excluding(identity("com.example.gamma")) == set && set.excluding(system("sound")) == set,
                     "an item that is not hidden changes nothing")
    }

    private static func movePlanner(_ suite: TestSuite) {
        let a = identity("a"), b = identity("b"), c = identity("c"), d = identity("d"), e = identity("e")

        func check(_ current: [MenuBarItemIdentity], _ target: [MenuBarItemIdentity],
                   moves expected: Int, gives result: [MenuBarItemIdentity]? = nil, _ label: String) {
            let plan = MenuBarMovePlanner.plan(current: current, target: target)
            var order = current
            var landed = true
            for move in plan {
                order = MenuBarMovePlanner.applying(move, to: order)
                landed = landed && MenuBarMovePlanner.isSatisfied(move, in: order)
            }
            suite.expect(plan.count == expected, "\(label): \(plan.count) moves, expected \(expected)")
            suite.expect(order == (result ?? target), "\(label): the moves produce the target order")
            suite.expect(landed, "\(label): every move reads as landed right after it is applied")
        }

        check([a, b, c], [a, b, c], moves: 0, "unchanged order")
        check([a, b, c, d], [d, a, b, c], moves: 1, "one item to the left end")
        check([a, b, c, d], [b, c, d, a], moves: 1, "one item to the right end")
        check([a, b, c, d, e], [a, d, c, b, e], moves: 2, "swapping two items around a third")
        check([a, b, c, d], [d, c, b, a], moves: 3, "a full reversal keeps one item in place")
        check([a, b, c], [c, d, a, b], moves: 1, gives: [c, a, b], "a target item that is gone is skipped")
        check([e, a, b], [b, a], moves: 1, gives: [e, b, a], "an unmentioned item keeps the left end")
        check([c, a, b, collapser, d], [a, b, c, collapser, d], moves: 1,
              "a returning hidden icon regains its former slot rather than staying first")
        check([a, b, collapser, d, c], [a, b, c, collapser, d], moves: 1,
              "a returning hidden icon stays on its original side of the collapser")
        check([e, c, a, b, collapser, d], [a, b, c, collapser, d], moves: 1,
              gives: [e, a, b, c, collapser, d], "launch reveal restores existing positions and keeps the new icon")

        suite.expect(MenuBarMovePlanner.plan(current: [a, b, c, d], target: [d, a, b, c])
                         == [MenuBarMove(item: d, after: nil)],
                     "a leftmost placement has no anchor")
        suite.expect(MenuBarMovePlanner.plan(current: [a, b, c, d], target: [a, c, d, b])
                         == [MenuBarMove(item: b, after: d)],
                     "the one displaced item moves, not the run it jumped")
        suite.expect(!MenuBarMovePlanner.isSatisfied(MenuBarMove(item: d, after: a), in: [a, b, d]),
                     "an item one slot off has not landed")
        suite.expect(!MenuBarMovePlanner.isSatisfied(MenuBarMove(item: e, after: nil), in: [a, b]),
                     "an item that vanished has not landed")
    }

    private static func dropPoints(_ suite: TestSuite) {
        let a = identity("a"), b = identity("b"), c = identity("c")
        let frames: [MenuBarItemIdentity: CGRect] = [
            a: CGRect(x: 100, y: 0, width: 30, height: 33),
            b: CGRect(x: 130, y: 0, width: 40, height: 33),
            c: CGRect(x: 170, y: 0, width: 20, height: 33)
        ]
        let order = [a, b, c]

        let between = MenuBarMovePlanner.dropPoint(for: MenuBarMove(item: c, after: a), frames: frames, order: order)
        suite.expect(between == CGPoint(x: 132.5, y: 16.5),
                     "between two items the drop lands halfway between their centers")
        let leftmost = MenuBarMovePlanner.dropPoint(for: MenuBarMove(item: c, after: nil), frames: frames, order: order)
        suite.expect(leftmost == CGPoint(x: 88, y: 16.5),
                     "a leftmost placement drops clear of the first item's left edge")
        let rightmost = MenuBarMovePlanner.dropPoint(for: MenuBarMove(item: a, after: c), frames: frames, order: order)
        suite.expect(rightmost == CGPoint(x: 207, y: 16.5),
                     "after the last item the drop lands clear of its right edge")
        let skipsSelf = MenuBarMovePlanner.dropPoint(for: MenuBarMove(item: b, after: a), frames: frames, order: order)
        suite.expect(skipsSelf == CGPoint(x: 147.5, y: 16.5),
                     "the dragged item is not its own right neighbour")
        suite.expect(MenuBarMovePlanner.dropPoint(for: MenuBarMove(item: c, after: a),
                                                  frames: frames.filter { $0.key != a }, order: order) == nil,
                     "a missing anchor frame yields no drop point")
        suite.expect(MenuBarMovePlanner.dropPoint(for: MenuBarMove(item: a, after: nil),
                                                  frames: [a: CGRect(x: 100, y: 0, width: 30, height: 33)],
                                                  order: [a]) == nil,
                     "a lone item has nowhere to go")
    }

    private static func quietGate(_ suite: TestSuite) {
        let a = identity("a"), b = identity("b")
        var gate = MenuBarQuietGate()
        suite.expect(!gate.observe([a]) && !gate.observe([a]), "two matching walks are not quiet yet")
        suite.expect(gate.observe([a]), "the third matching walk is quiet")
        var restless = MenuBarQuietGate()
        _ = restless.observe([a])
        _ = restless.observe([a])
        suite.expect(!restless.observe([a, b]) && !restless.observe([a, b]),
                     "a late icon restarts the count")
        suite.expect(restless.observe([a, b]), "and the bar is quiet three walks later")
    }

    private static func hiddenRecords(_ suite: TestSuite) {
        guard let layout = MenuBarOrganizerLayout.partition(bar, collapser: collapser) else {
            suite.expect(false, "the reference bar partitions")
            return
        }
        let records = MenuBarHiddenRecord.records(for: layout, items: bar, neverShown: [], ownBundleID: own)
        suite.expect(records.map(\.identity) == [identity("com.example.alpha"), identity("com.example.beta")],
                     "only items that really hide are remembered")
        let never = [MenuBarHiddenRecord(identity: identity("com.example.alpha"), appName: "Alpha")]
        suite.expect(MenuBarHiddenRecord.records(for: layout, items: bar, neverShown: never, ownBundleID: own)
                        .map(\.identity) == [identity("com.example.beta")],
                     "an app kept out for good is not remembered as hidden, so the shelf never lists it")
        suite.expect(MenuBarHiddenRecord.decode(MenuBarHiddenRecord.encode(records)) == records,
                     "hidden records survive their stored form")
        suite.expect(MenuBarHiddenRecord.decode(Data("not json".utf8)).isEmpty && MenuBarHiddenRecord.decode(nil).isEmpty,
                     "unreadable stored records read as none")
    }

    private static func editor(_ suite: TestSuite) {
        guard let layout = MenuBarOrganizerLayout.partition(bar, collapser: collapser) else {
            suite.expect(false, "the reference bar partitions")
            return
        }
        typealias Editor = MenuBarOrganizerEditorSupport
        let alpha = identity("com.example.alpha")
        let gamma = identity("com.example.gamma")
        let delta = identity("com.example.delta")
        let remembered = [MenuBarHiddenRecord(identity: alpha, appName: "Alpha"),
                          MenuBarHiddenRecord(identity: delta, appName: "Delta")]
        suite.expect(Editor.baseline(layout: layout, lastHidden: remembered, neverShown: [], collapsed: false) == layout,
                     "an open bar is drawn as it was read")
        suite.expect(Editor.note(for: item("com.example.adhoc", x: 0, appleSigned: false)) == .unsigned
                        && Editor.note(for: item("com.example.alpha", x: 0)) == nil,
                     "only an item macOS cannot attribute to its app carries the unsigned note")
        suite.expect(Editor.baseline(layout: layout, lastHidden: remembered, neverShown: [], collapsed: true).hidden
                        == layout.hidden + [delta],
                     "a collapsed bar adds only the remembered items the partition lacks")
        suite.expect(Editor.baseline(layout: nil, lastHidden: remembered, neverShown: [], collapsed: true)
                        == MenuBarLayout(hidden: remembered.map(\.identity), visible: []),
                     "without a partition a collapsed bar is drawn from memory")

        // Delta is gone from the bar; gamma was seen by a walk of a bar that
        // was open for a moment.
        let never = [MenuBarHiddenRecord(identity: delta, appName: "Delta"),
                     MenuBarHiddenRecord(identity: gamma, appName: "Gamma")]
        let drawn = Editor.baseline(layout: layout, lastHidden: [], neverShown: never, collapsed: false)
        suite.expect(drawn.neverShown == [delta, gamma], "never-shown items are drawn from memory, expanded too")
        suite.expect(drawn.hidden == layout.hidden && drawn.visible == Array(layout.visible.dropFirst()),
                     "a never-shown item a walk happened to see is on neither side")

        let battery = system("battery"), clock = system("clock")

        // The agent draws every system item, yet each is kept out alone.
        var systems = layout
        systems.visible += [system("wifi"), clock]
        let banished = Editor.moving(battery, to: .never, before: nil, in: systems) { $0 == clock }
        suite.expect(banished.neverShown == [battery] && banished.visible == systems.visible.filter { $0 != battery },
                     "never show takes a system item alone, not the agent's other items")
        suite.expect(Editor.baseline(layout: systems, lastHidden: [],
                                     neverShown: [MenuBarHiddenRecord(identity: battery, appName: nil)], collapsed: false)
                        == banished,
                     "a never-shown system item does not draw the other system items as never shown")
    }

    private static func tierMoves(_ suite: TestSuite) {
        typealias Editor = MenuBarOrganizerEditorSupport
        let a = identity("a"), b = identity("b"), c = identity("c"), d = identity("d")
        let twinOne = identity("twin", "One"), twinTwo = identity("twin", "Two")
        let locked = identity(own, "Vorssaint"), ownSecond = identity(own, "Second")
        let layout = MenuBarLayout(hidden: [a, twinOne, b], visible: [c, twinTwo, locked], neverShown: [d])

        func move(_ identity: MenuBarItemIdentity, to tier: Editor.Tier, before target: MenuBarItemIdentity?,
                  in layout: MenuBarLayout = layout) -> MenuBarLayout {
            Editor.moving(identity, to: tier, before: target, in: layout) { $0 == locked }
        }

        suite.expect(Editor.tier(of: c, in: layout) == .show && Editor.tier(of: a, in: layout) == .hide
                        && Editor.tier(of: d, in: layout) == .never && Editor.tier(of: identity("gone"), in: layout) == nil,
                     "an item is in the tier whose list holds it")
        suite.expect(move(b, to: .hide, before: a).hidden == [b, a, twinOne],
                     "a row dragged up lands in front of the row it reached")
        suite.expect(move(a, to: .hide, before: twinOne).hidden == [twinOne, a, b],
                     "a row dragged down lands behind the row it reached")
        suite.expect(move(a, to: .hide, before: nil).hidden == [twinOne, b, a]
                        && move(a, to: .show, before: nil).visible == [c, twinTwo, locked, a],
                     "without a target an item goes to the end of the tier")
        let crossed = move(a, to: .show, before: twinTwo)
        suite.expect(crossed.hidden == [twinOne, b] && crossed.visible == [c, a, twinTwo, locked]
                        && crossed.neverShown == [d],
                     "a move across tiers lands in front of its target and takes nothing else along")
        suite.expect(move(a, to: .hide, before: a) == layout && move(identity("gone"), to: .show, before: nil) == layout,
                     "a row over itself and an unknown item change nothing")

        let banished = move(twinTwo, to: .never, before: d)
        suite.expect(banished == MenuBarLayout(hidden: [a, b], visible: [c, locked], neverShown: [twinOne, twinTwo, d]),
                     "never show takes every icon of the app along")
        suite.expect(move(twinOne, to: .show, before: c, in: banished)
                        == MenuBarLayout(hidden: [a, b], visible: [twinOne, twinTwo, c, locked], neverShown: [d]),
                     "leaving never show brings every icon of the app back")
        suite.expect(move(locked, to: .never, before: nil) == layout, "a locked item is never kept out of the bar")
        let siblings = MenuBarLayout(hidden: [ownSecond], visible: [locked])
        suite.expect(move(ownSecond, to: .never, before: nil, in: siblings)
                        == MenuBarLayout(hidden: [], visible: [locked], neverShown: [ownSecond]),
                     "a locked sibling stays behind when its app goes to never show")
    }

    private static func managers(_ suite: TestSuite) {
        for bundle in ["com.surteesstudios.Bartender", "com.surteesstudios.Bartender-setapp",
                       "com.jordanbaird.Ice", "com.dragonapp.ice", "com.dragonapp.ice.MenuBarItemService",
                       "com.stonerl.Thaw", "app.fif7y.Pelmet", "app.fif7y.Pelmet.items.hidden",
                       "com.dwarvesv.minimalbar", "com.mortennn.Dozer", "br.tec.sparrow.menubarhide"] {
            suite.expect(MenuBarManagerDetection.isKnownManager(bundleIdentifier: bundle),
                         "\(bundle) is a known menu bar manager")
        }
        for bundle in ["com.jordanbaird.IceCream", "com.apple.MenuBarAgent", "com.vorssaint.app", ""] {
            suite.expect(!MenuBarManagerDetection.isKnownManager(bundleIdentifier: bundle),
                         "\(bundle) is not a menu bar manager")
        }
    }
}
