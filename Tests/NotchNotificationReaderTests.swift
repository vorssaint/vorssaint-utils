// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// The real reader runs on controlled trees. Opening and opted-in closing are
/// scoped to the original notification; there is no text mutation interface.
enum NotchNotificationReaderTests {
    private final class Node {
        let id = UUID()
        var strings: [String: String]
        var children: [Node]
        var actions: [String] = []
        var frame = CGRect(x: 0, y: 0, width: 1470, height: 956)
        var removed = false
        init(_ role: String, identifier: String? = nil, value: String? = nil,
             subrole: String? = nil, children: [Node] = []) {
            strings = ["AXRole": role]
            strings["AXIdentifier"] = identifier
            strings["AXValue"] = value
            strings["AXSubrole"] = subrole
            self.children = children
        }
    }

    private final class Access: NotchNotificationAccess {
        enum Failure: Error { case unavailable }
        var roots: [Node] = []
        var focused = false
        var allowed = true
        var time: TimeInterval = 0
        var failRead: String?
        var beforeRead: ((String, Node?) -> Void)?
        var pressSucceeds = true
        var presses: [UUID] = []
        var performed: [String] = []
        var allowClose = false
        var valueReads: [UUID] = []
        var movable = true
        var ignoresMove = false
        var moves = 0
        func reading(_ operation: String, _ node: Node? = nil) throws {
            beforeRead?(operation, node)
            if failRead == operation { throw Failure.unavailable }
        }
        func windows() throws -> [Node] { try reading("windows"); return roots }
        func hasFocusedWindow() throws -> Bool { try reading("focused"); return focused }
        func string(_ element: Node, _ attribute: String) throws -> String? {
            try reading(attribute, element)
            if attribute == "AXValue" { valueReads.append(element.id) }
            return element.strings[attribute]
        }
        func children(_ element: Node) throws -> [Node] { try reading("children", element); return element.children }
        func perform(_ action: String, on element: Node) -> Bool { performed.append(action); return pressSucceeds }
        func actions(_ element: Node) throws -> [String] { try reading("actions", element); return element.actions }
        func frame(_ element: Node) throws -> CGRect? {
            try reading("frame", element)
            return element.removed ? nil : element.frame
        }
        func move(_ element: Node, to origin: CGPoint) -> Bool {
            moves += 1
            guard movable else { return false }
            if !ignoresMove { element.frame.origin = origin }
            return true
        }
        func press(_ element: Node) -> Bool { presses.append(element.id); return pressSucceeds }
        func same(_ lhs: Node, _ rhs: Node) -> Bool { lhs === rhs }
        func reader() -> NotchNotificationReaderCore<Access> {
            NotchNotificationReaderCore(access: self, allowed: { self.allowed }, clock: { self.time },
                                        receivedDate: { Date(timeIntervalSince1970: 100) },
                                        sourceApplicationName: { labels in
                                            let applications = [(name: "Chat", bundleIdentifier: "test.chat"),
                                                                (name: "Mail", bundleIdentifier: "test.mail"),
                                                                (name: "Chat Notifications", bundleIdentifier: "test.chat")]
                                            guard let identifier = NotchNotificationSupport.sourceBundleIdentifier(for: labels, applications: applications) else { return nil }
                                            return applications.first { $0.bundleIdentifier == identifier }?.name
                                        }, allowsNativeClose: { self.allowClose }, nativeCloseTitle: "Close",
                                        displays: { NotchNotificationReaderTests.displays })
        }
    }

    /// A built-in display with a larger one to its right.
    private static let displays = [CGRect(x: 0, y: 0, width: 1470, height: 956), CGRect(x: 1470, y: 0, width: 1920, height: 1080)]
    private static let screens = CGRect(x: 0, y: 0, width: 3390, height: 1080)

    private static func card(identity: String = "request." + UUID().uuidString,
                             sender: String = "Alex", body: String = "Hello", legacy: Bool = false) -> Node {
        let texts = legacy
            ? [Node("AXStaticText", value: sender), Node("AXStaticText", value: body)]
            : [Node("AXStaticText", identifier: "header", value: "Chat"),
               Node("AXStaticText", identifier: "title", value: sender),
               Node("AXStaticText", identifier: "body", value: body)]
        let root = Node("AXGroup", identifier: identity,
                        subrole: legacy ? "AXNotificationCenterAlert" : nil, children: texts)
        root.actions = ["AXPress"]
        return root
    }

    private static func stack(_ cards: [Node]) -> Node {
        Node("AXGroup", identifier: "AXNotificationListItems", subrole: "AXNotificationCenterAlertStack", children: cards)
    }

    static func run(_ suite: TestSuite) {
        traversal(suite)
        opening(suite)
        interruption(suite)
        identity(suite)
        nativeClosing(suite)
        busyClosing(suite)
        nativeHiding(suite)
        hiddenWindowReturns(suite)
    }

    /// The center's window with one transient banner, read once.
    private static func hiddenFixture() -> (access: Access, reader: NotchNotificationReaderCore<Access>, window: Node, banner: Node, id: UUID)? {
        let access = Access(), banner = card()
        banner.strings["AXSubrole"] = "AXNotificationCenterBanner"
        let window = Node("AXWindow", subrole: "AXSystemDialog", children: [banner])
        access.roots = [window]
        let reader = access.reader()
        guard let id = reader.read()?.items.first?.id else { return nil }
        return (access, reader, window, banner, id)
    }

    private static func nativeHiding(_ suite: TestSuite) {
        guard let (access, reader, window, banner, id) = hiddenFixture() else {
            suite.expect(false, "the hiding fixture has a live banner"); return
        }
        let home = window.frame
        suite.expect(reader.hideNative([id]).isEmpty && access.moves == 0,
                     "mirroring cannot hide a native banner without a separate opt-in")
        access.allowClose = true
        suite.expect(reader.hideNative([]).isEmpty && access.moves == 0,
                     "a banner the island did not show stays on screen")
        suite.expect(reader.hideNative([id]).isEmpty && !window.frame.intersects(screens) && reader.hidesWindows
                     && access.performed.isEmpty && access.presses.isEmpty,
                     "a shown banner's window leaves every display without closing or opening the banner")
        let moves = access.moves
        suite.expect(reader.hideNative([id]).isEmpty && access.moves == moves,
                     "a window already out of sight is not moved again")
        suite.expect(reader.open(id) == .handedOff, "Open still reaches the hidden original")
        window.frame.origin = CGPoint(x: 1470, y: 0)
        suite.expect(reader.hideNative([id]).isEmpty && !window.frame.intersects(screens),
                     "a window the center placed again is hidden again while the island shows its banner")
        let other = card(sender: "Sam", body: "Second")
        other.strings["AXSubrole"] = "AXNotificationCenterBanner"
        window.children.append(other)
        _ = reader.read()
        suite.expect(reader.hideNative([id]).isEmpty && window.frame.origin == CGPoint(x: 1470, y: 0) && !reader.hidesWindows,
                     "a banner the island passed over brings its window back where the center last put it")
        window.children = [banner]
        banner.strings["AXSubrole"] = "AXNotificationCenterAlert"
        let alertID = reader.read()?.items.first?.id
        suite.expect(alertID == id && reader.hideNative([id]).isEmpty && window.frame.intersects(screens),
                     "a persistent alert stays in sight, so its buttons and alarm remain reachable")
        banner.strings["AXSubrole"] = "AXNotificationCenterBanner"
        window.frame = home
        _ = reader.read()
        banner.children[2].strings["AXValue"] = "Changed"
        suite.expect(reader.hideNative([id]).isEmpty && window.frame == home,
                     "changed native content is never hidden under a stale mirrored message")
        banner.children[2].strings["AXValue"] = "Hello"
        access.movable = false
        suite.expect(reader.hideNative([id]) == [id] && window.frame == home,
                     "a window that cannot be moved reports its banner so it is closed instead")
        access.movable = true; access.ignoresMove = true
        suite.expect(reader.hideNative([id]) == [id] && window.frame == home && !reader.hidesWindows,
                     "a move the window ignores is not mistaken for a hidden banner")
    }

    /// Every way out of hiding puts back only a window this reader moved, and
    /// never over a place the center chose since.
    private static func hiddenWindowReturns(_ suite: TestSuite) {
        if let (access, reader, window, _, id) = hiddenFixture() {
            access.allowClose = true
            let home = window.frame
            _ = reader.hideNative([id])
            access.focused = true
            suite.expect(reader.read() == nil && window.frame == home && !reader.hidesWindows,
                         "opening the center brings a hidden window back")
        }
        if let (access, reader, window, _, id) = hiddenFixture() {
            access.allowClose = true
            let home = window.frame
            _ = reader.hideNative([id])
            access.focused = true
            suite.expect(reader.hideNative([id]).isEmpty && window.frame == home && !reader.hidesWindows,
                         "the open center is never moved away, even with a shown banner still in it")
            access.focused = false; access.failRead = "focused"
            suite.expect(reader.hideNative([id]).isEmpty && window.frame == home,
                         "an unreadable focus state never hides the window")
        }
        if let (access, reader, window, _, id) = hiddenFixture() {
            access.allowClose = true
            let home = window.frame
            _ = reader.hideNative([id])
            access.allowClose = false
            suite.expect(reader.hideNative([id]).isEmpty && window.frame == home && !reader.hidesWindows,
                         "turning the option off brings a hidden window back")
        }
        if let (access, reader, window, _, id) = hiddenFixture() {
            access.allowClose = true
            let home = window.frame
            _ = reader.hideNative([id])
            window.children = []
            _ = reader.read()
            suite.expect(reader.hideNative([]).isEmpty && !window.frame.intersects(screens) && reader.hidesWindows,
                         "an emptied window stays out of sight, so the banner's exit never flashes on screen")
            access.allowed = false
            reader.showNative()
            suite.expect(window.frame == home && !reader.hidesWindows,
                         "stopping puts the window back even after reading is no longer allowed")
        }
        if let (access, reader, window, _, id) = hiddenFixture() {
            access.allowClose = true
            let home = window.frame
            _ = reader.hideNative([id])
            window.children = []
            _ = reader.read()
            access.failRead = "frame"
            reader.showNative()
            suite.expect(reader.hidesWindows && !window.frame.intersects(screens),
                         "a window that cannot be read right now stays on the list")
            access.failRead = nil
            reader.showNative()
            suite.expect(!reader.hidesWindows && window.frame == home,
                         "the next attempt puts a window back once it can be read again")
        }
        if let (access, reader, window, _, id) = hiddenFixture() {
            access.allowClose = true
            _ = reader.hideNative([id])
            window.children = []
            _ = reader.read()
            window.removed = true
            suite.expect(reader.hideNative([]).isEmpty && !reader.hidesWindows,
                         "a window the center removed is forgotten")
        }
        if let (access, reader, window, _, id) = hiddenFixture() {
            access.allowClose = true
            window.removed = true
            suite.expect(reader.hideNative([id]) == [id] && !reader.hidesWindows,
                         "a window without a position to move closes its banner instead")
        }
        // An alert naming two senders cannot be taken apart, so the island
        // never showed it.
        func untakenAlert() -> Node {
            let alert = card(sender: "Sam", body: "Alarm")
            alert.strings["AXSubrole"] = "AXNotificationCenterAlert"
            alert.children.append(Node("AXStaticText", identifier: "title", value: "Other sender"))
            return alert
        }
        if let (access, reader, window, _, id) = hiddenFixture() {
            access.allowClose = true
            let home = window.frame
            window.children.append(untakenAlert())
            _ = reader.read()
            suite.expect(reader.hideNative([id]).isEmpty && window.frame == home && !reader.hidesWindows,
                         "a shown banner beside an alert the reader cannot take apart stays in sight")
        }
        if let (access, reader, window, _, id) = hiddenFixture() {
            access.allowClose = true
            let home = window.frame
            _ = reader.hideNative([id])
            window.children = [untakenAlert()]
            _ = reader.read()
            suite.expect(reader.hideNative([]).isEmpty && window.frame == home && !reader.hidesWindows,
                         "a hidden window comes back when its banner leaves an alert the reader cannot take apart")
        }
        if let (access, reader, window, _, id) = hiddenFixture() {
            access.allowClose = true
            _ = reader.hideNative([id])
            let placed = CGRect(x: 1470, y: 0, width: 1920, height: 1080)
            window.frame = placed
            window.children = []
            _ = reader.read()
            reader.showNative()
            suite.expect(window.frame == placed && !reader.hidesWindows,
                         "a window the center placed again is never moved back over its new place")
        }
    }

    /// The refresh before a close can spend nearly the whole traversal on a
    /// large stack. Validation keeps headroom of its own, and a refresh that
    /// cannot finish still closes nothing.
    private static func busyClosing(_ suite: TestSuite) {
        let access = Access(), action = "Name:Close\nTarget:0x0\nSelector:(null)"
        access.allowClose = true
        let banners = (0..<22).map { _ in card() }
        for banner in banners { banner.actions.append(action) }
        let container = stack(banners)
        container.strings["AXSubrole"] = "AXNotificationCenterBannerStack"
        func center(padding: Int) -> [Node] {
            [container, Node("AXWindow", children: (0..<padding).map { _ in Node("AXGroup") })]
        }
        let reader = access.reader()
        // Plain nodes fill the rest until one more would fail the refresh itself.
        var padding = 0
        while padding < 64 {
            access.roots = center(padding: padding + 1)
            guard reader.read() != nil else { break }
            padding += 1
        }
        access.roots = center(padding: padding)
        guard padding < 64, let id = reader.read()?.items.last?.id else {
            suite.expect(false, "a large stack fills the refresh's traversal budget"); return
        }
        suite.expect(reader.closeNative(id) && access.performed == [action],
                     "a refresh that used nearly every node still leaves validation room to close the banner")
        access.performed = []
        access.roots = center(padding: padding + 1)
        suite.expect(!reader.closeNative(id) && access.performed.isEmpty,
                     "a refresh that runs out of nodes closes nothing")
    }

    private static func nativeClosing(_ suite: TestSuite) {
        let access = Access(), root = card(legacy: true)
        let action = "Name:Close\nTarget:0x0\nSelector:(null)"
        root.actions.append(action)
        root.strings["AXSubrole"] = "AXNotificationCenterBanner"
        access.roots = [root]
        let reader = access.reader()
        let id = reader.read()!.items[0].id
        suite.expect(!reader.closeNative(id) && access.performed.isEmpty,
               "mirroring cannot close a native notification without a separate opt-in")
        access.allowClose = true
        root.strings["AXSubrole"] = "AXNotificationCenterAlert"
        suite.expect(!reader.closeNative(id) && access.performed.isEmpty,
               "an alarm that becomes a persistent alert cannot be closed automatically")
        root.strings["AXSubrole"] = "AXNotificationCenterBanner"
        suite.expect(reader.closeNative(id) && access.performed == [action] && access.presses.isEmpty,
               "closing invokes only the original close action, never opens the notification")
        access.performed = []
        root.children[1].strings["AXValue"] = "Changed"
        suite.expect(!reader.closeNative(id) && access.performed.isEmpty,
               "changed native content cannot be closed using a stale mirrored message")
        let nextID = reader.read()!.items[0].id
        access.beforeRead = { operation, _ in if operation == "actions" { access.allowClose = false } }
        suite.expect(!reader.closeNative(nextID) && access.performed.isEmpty,
               "turning off native closing during validation prevents the final action")
        access.beforeRead = nil; access.allowClose = true
        root.actions = ["AXPress", "Name:Close All\nTarget:0x0\nSelector:(null)"]
        suite.expect(!reader.closeNative(nextID) && access.performed.isEmpty,
               "closing a single banner never falls back to clearing a group")
        for role in ["AXNotificationCenterAlert", "AXNotificationCenterAlertStack"] {
            let alert = card(legacy: true)
            alert.actions.append(action)
            access.roots = role.hasSuffix("Stack") ? [stack([alert])] : [alert]
            let alertID = reader.read()!.items[0].id
            suite.expect(!reader.closeNative(alertID) && access.performed.isEmpty,
                   "persistent alerts and alarm stacks stay mirrored without dismissing their native sound")
        }
        let banner = card()
        banner.actions.append(action)
        let container = stack([banner])
        container.strings["AXSubrole"] = "AXNotificationCenterBannerStack"
        access.roots = [container]
        let bannerID = reader.read()!.items[0].id
        suite.expect(reader.closeNative(bannerID) && access.performed == [action],
               "transient banners in modern stacks still honor native replacement")
    }

    private static func traversal(_ suite: TestSuite) {
        let access = Access(), first = card(), second = card(sender: "Sam", body: "Second")
        let reader = access.reader()
        access.roots = [Node("AXWindow", children: [stack([first, second])])]
        let items = reader.read()?.items ?? []
        suite.expect(items.count == 2 && Set(items.map(\.content.title)) == ["Alex", "Sam"],
               "the production traversal separates complete messages inside a modern stack")
        suite.expect(items.allSatisfy(\.canOpen) && access.presses.isEmpty,
               "mirroring can expose supported opening without performing any native action")
        access.roots = [stack([first])]
        suite.expect(reader.read()?.items.first?.content.body == "Hello",
               "a structural wrapper around one complete card preserves its message")
        let legacy = card(legacy: true)
        let editor = Node("AXTextField", identifier: "body", value: "Private editable text")
        legacy.children.append(editor)
        access.roots = [Node("AXWindow", children: [legacy])]
        suite.expect(reader.read()?.items.first?.content.body == "Hello" && !access.valueReads.contains(editor.id),
               "editable native fields are neither read as values nor copied into a mirrored message")
        let applicationImage = Node("AXImage")
        applicationImage.strings["AXDescription"] = "Chat"
        let contactImage = Node("AXImage")
        contactImage.strings["AXDescription"] = "Alex"
        legacy.children += [contactImage, applicationImage]
        suite.expect(reader.read()?.items.first?.content.app == "Chat",
               "the production reader recovers the app from image labels on banners without a header")
        suite.expect(reader.read()?.items.first?.content.title == "Alex"
               && reader.read()?.items.first?.content.body == "Hello",
               "recovering the app from its icon never reassigns sender or message text")
        let nestedText = Node("AXGroup", children: Array(legacy.children.prefix(2)))
        access.roots = [stack([applicationImage, nestedText])]
        suite.expect(reader.read()?.items.first?.content.app == "Chat",
               "stack traversal retains an app icon outside the inner sender-and-message group")
        access.roots = [legacy]
        access.failRead = "AXDescription"
        suite.expect(reader.read() == nil, "failed icon-label reads cannot produce a partly attributed notification")
        access.failRead = nil
        applicationImage.strings["AXDescription"] = "Unrecognized source"
        suite.expect(reader.read()?.items.first?.content.app.isEmpty == true,
               "unrecognized image descriptions never become invented source names")
        applicationImage.strings["AXDescription"] = "Chat"
        let noIcon = card(legacy: true)
        noIcon.strings["AXAttributedDescription"] = "Chat, Alex, Hello"
        access.roots = [noIcon]
        suite.expect(reader.read()?.items.first?.content.app == "Chat",
               "the native formatted description identifies a banner whose visible tree has no app image or header")
        let namedLikeApp = card(sender: "Chat", legacy: true)
        namedLikeApp.strings["AXTitle"] = "Chat"
        access.roots = [namedLikeApp]
        suite.expect(reader.read()?.items.first?.content.app.isEmpty == true,
               "a sender matching an application name cannot masquerade as the source")
        access.roots = [Node("AXWindow", children: [Node("AXGroup", children: [Node("AXStaticText", value: "Widget")])])]
        suite.expect(reader.read()?.items.isEmpty == true, "unrelated widgets are never interpreted as notifications")
        let malformed = card(legacy: false)
        malformed.strings["AXSubrole"] = "AXNotificationCenterAlert"
        malformed.children.append(Node("AXStaticText", identifier: "title", value: "Other sender"))
        access.roots = [malformed]
        suite.expect(reader.read()?.items.isEmpty == true, "two senders in one banner are never combined")
        access.roots = [legacy]; access.focused = true
        suite.expect(reader.read() == nil, "focused notification history is not imported as newly received messages")
        access.focused = false; access.failRead = "focused"
        suite.expect(reader.read() == nil, "an unreadable focus state cannot be mistaken for a closed center")
        access.failRead = "AXValue"
        suite.expect(reader.read() == nil, "failed message reads discard the incomplete snapshot")
        access.failRead = nil
        access.roots = [Node("AXWindow", children: (0..<65).map { _ in Node("AXGroup") })]
        suite.expect(reader.read() == nil, "oversized child arrays invalidate the traversal instead of omitting unknown messages")
        var deep = legacy
        for _ in 0..<12 { deep = Node("AXGroup", children: [deep]) }
        access.roots = [deep]
        suite.expect(reader.read() == nil, "depth-limited discovery is never presented as a complete snapshot")
    }

    private static func opening(_ suite: TestSuite) {
        let access = Access(), root = card(legacy: true), reader = access.reader()
        access.roots = [root]
        guard let id = reader.read()?.items.first?.id else { suite.expect(false, "opening fixture has a live notification"); return }
        suite.expect(reader.open(id) == .handedOff && access.presses == [root.id],
               "Open performs the original notification root's supported press exactly once")
        root.actions = []
        suite.expect(reader.open(id) == .unavailable && access.presses.count == 1,
               "an action removed from the live root cannot use cached capability")
        root.actions = ["AXCustomAction"]
        suite.expect(reader.read()?.items.first?.canOpen == false && reader.open(id) == .unavailable,
               "custom actions are never guessed as the notification's normal opening action")
        root.actions = ["AXPress"]
        access.pressSucceeds = false
        suite.expect(reader.open(id) == .uncertain, "an unsuccessful native opening reports an uncertain handoff")
        access.roots = []
        _ = reader.read()
        let before = access.presses.count
        suite.expect(reader.open(id) == .unavailable && access.presses.count == before,
               "a notification absent from the latest complete snapshot cannot be opened")
    }

    private static func interruption(_ suite: TestSuite) {
        for point in ["AXIdentifier", "AXValue", "actions"] {
            for expires in [false, true] {
                let access = Access(), root = card(legacy: true), reader = access.reader()
                access.roots = [root]
                guard let id = reader.read()?.items.first?.id else { suite.expect(false, "interruption fixture is live"); continue }
                access.beforeRead = { operation, _ in
                    if operation == point {
                        if expires { access.time += 1 } else { access.allowed = false }
                    }
                }
                suite.expect(reader.open(id) == .unavailable && access.presses.isEmpty,
                       "cancellation or timeout during \(point) cannot reach native opening")
            }
        }
        let access = Access(), root = card(legacy: true), reader = access.reader()
        access.roots = [root]
        guard let id = reader.read()?.items.first?.id else { suite.expect(false, "content fixture is live"); return }
        root.children[0].strings["AXValue"] = "Changed sender"
        suite.expect(reader.open(id) == .unavailable && access.presses.isEmpty,
               "a changed sender cannot inherit the old notification's opening action")
        root.children[0].strings["AXValue"] = "Alex"
        root.strings["AXIdentifier"] = "request." + UUID().uuidString
        suite.expect(reader.open(id) == .unavailable && access.presses.isEmpty,
               "a native root reassigned to another identity cannot open the old notification")
    }

    private static func identity(_ suite: TestSuite) {
        let access = Access(), original = card(legacy: true), reader = access.reader()
        access.roots = [original]
        guard let first = reader.read()?.items.first else { suite.expect(false, "identity fixture is live"); return }
        suite.expect(reader.read()?.items.first == first, "repeated snapshots preserve identity and receipt time")
        let rebuilt = card(identity: original.strings["AXIdentifier"]!, legacy: true)
        access.roots = [rebuilt]
        suite.expect(reader.read()?.items.first?.id == first.id && reader.open(first.id) == .handedOff
               && access.presses == [rebuilt.id],
               "native view reconstruction preserves mirror identity and opens the newly validated root")
        let duplicate = card(legacy: true)
        let conflict = card(identity: duplicate.strings["AXIdentifier"]!, sender: "Other", legacy: true)
        access.roots = [duplicate, conflict]
        let ambiguous = reader.read()?.items ?? []
        suite.expect(ambiguous.count == 2 && ambiguous.allSatisfy { !$0.canOpen },
               "two live roots claiming one native identity cannot authorize opening")
        for item in ambiguous { suite.expect(reader.open(item.id) == .unavailable, "ambiguous targets stay unavailable at action time") }
        access.roots = [duplicate]
        suite.expect(reader.read()?.items.first?.canOpen == true, "a later unambiguous snapshot restores normal opening")
        let independent = card(legacy: true)
        access.roots = [duplicate, independent]
        suite.expect(reader.read()?.items.count == 2, "identical visible text does not merge independent notification identities")
        duplicate.strings["AXIdentifier"] = "AXNotificationListItems"
        access.roots = [duplicate]
        guard let structural = reader.read()?.items.first else { suite.expect(false, "structural fixture is readable"); return }
        suite.expect(reader.read()?.items.first?.id == structural.id,
               "without a durable native identity, unchanged root identity still deduplicates visible notices")
    }
}
