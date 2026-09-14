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
                                        }, allowsNativeClose: { self.allowClose }, nativeCloseTitle: "Close")
        }
    }

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

    static func run(expect: (Bool, String) -> Void) {
        traversal(expect: expect)
        opening(expect: expect)
        interruption(expect: expect)
        identity(expect: expect)
        nativeClosing(expect: expect)
    }

    private static func nativeClosing(expect: (Bool, String) -> Void) {
        let access = Access(), root = card(legacy: true)
        let action = "Name:Close\nTarget:0x0\nSelector:(null)"
        root.actions.append(action)
        access.roots = [root]
        let reader = access.reader()
        let id = reader.read()!.items[0].id
        expect(!reader.closeNative(id) && access.performed.isEmpty,
               "mirroring cannot close a native notification without a separate opt-in")
        access.allowClose = true
        expect(reader.closeNative(id) && access.performed == [action] && access.presses.isEmpty,
               "closing invokes only the original close action, never opens the notification")
        access.performed = []
        root.children[1].strings["AXValue"] = "Changed"
        expect(!reader.closeNative(id) && access.performed.isEmpty,
               "changed native content cannot be closed using a stale mirrored message")
        let nextID = reader.read()!.items[0].id
        access.beforeRead = { operation, _ in if operation == "actions" { access.allowClose = false } }
        expect(!reader.closeNative(nextID) && access.performed.isEmpty,
               "turning off native closing during validation prevents the final action")
        access.beforeRead = nil; access.allowClose = true
        root.actions = ["AXPress", "Name:Close All\nTarget:0x0\nSelector:(null)"]
        expect(!reader.closeNative(nextID) && access.performed.isEmpty,
               "closing a single banner never falls back to clearing a group")
    }

    private static func traversal(expect: (Bool, String) -> Void) {
        let access = Access(), first = card(), second = card(sender: "Sam", body: "Second")
        let reader = access.reader()
        access.roots = [Node("AXWindow", children: [stack([first, second])])]
        let items = reader.read()?.items ?? []
        expect(items.count == 2 && Set(items.map(\.content.title)) == ["Alex", "Sam"],
               "the production traversal separates complete messages inside a modern stack")
        expect(items.allSatisfy(\.canOpen) && access.presses.isEmpty,
               "mirroring can expose supported opening without performing any native action")
        access.roots = [stack([first])]
        expect(reader.read()?.items.first?.content.body == "Hello",
               "a structural wrapper around one complete card preserves its message")
        let legacy = card(legacy: true)
        let editor = Node("AXTextField", identifier: "body", value: "Private editable text")
        legacy.children.append(editor)
        access.roots = [Node("AXWindow", children: [legacy])]
        expect(reader.read()?.items.first?.content.body == "Hello" && !access.valueReads.contains(editor.id),
               "editable native fields are neither read as values nor copied into a mirrored message")
        let applicationImage = Node("AXImage")
        applicationImage.strings["AXDescription"] = "Chat"
        let contactImage = Node("AXImage")
        contactImage.strings["AXDescription"] = "Alex"
        legacy.children += [contactImage, applicationImage]
        expect(reader.read()?.items.first?.content.app == "Chat",
               "the production reader recovers the app from image labels on banners without a header")
        expect(reader.read()?.items.first?.content.title == "Alex"
               && reader.read()?.items.first?.content.body == "Hello",
               "recovering the app from its icon never reassigns sender or message text")
        let nestedText = Node("AXGroup", children: Array(legacy.children.prefix(2)))
        access.roots = [stack([applicationImage, nestedText])]
        expect(reader.read()?.items.first?.content.app == "Chat",
               "stack traversal retains an app icon outside the inner sender-and-message group")
        access.roots = [legacy]
        access.failRead = "AXDescription"
        expect(reader.read() == nil, "failed icon-label reads cannot produce a partly attributed notification")
        access.failRead = nil
        applicationImage.strings["AXDescription"] = "Unrecognized source"
        expect(reader.read()?.items.first?.content.app.isEmpty == true,
               "unrecognized image descriptions never become invented source names")
        applicationImage.strings["AXDescription"] = "Chat"
        let noIcon = card(legacy: true)
        noIcon.strings["AXAttributedDescription"] = "Chat, Alex, Hello"
        access.roots = [noIcon]
        expect(reader.read()?.items.first?.content.app == "Chat",
               "the native formatted description identifies a banner whose visible tree has no app image or header")
        let namedLikeApp = card(sender: "Chat", legacy: true)
        namedLikeApp.strings["AXTitle"] = "Chat"
        access.roots = [namedLikeApp]
        expect(reader.read()?.items.first?.content.app.isEmpty == true,
               "a sender matching an application name cannot masquerade as the source")
        access.roots = [Node("AXWindow", children: [Node("AXGroup", children: [Node("AXStaticText", value: "Widget")])])]
        expect(reader.read()?.items.isEmpty == true, "unrelated widgets are never interpreted as notifications")
        let malformed = card(legacy: false)
        malformed.strings["AXSubrole"] = "AXNotificationCenterAlert"
        malformed.children.append(Node("AXStaticText", identifier: "title", value: "Other sender"))
        access.roots = [malformed]
        expect(reader.read()?.items.isEmpty == true, "two senders in one banner are never combined")
        access.roots = [legacy]; access.focused = true
        expect(reader.read() == nil, "focused notification history is not imported as newly received messages")
        access.focused = false; access.failRead = "focused"
        expect(reader.read() == nil, "an unreadable focus state cannot be mistaken for a closed center")
        access.failRead = "AXValue"
        expect(reader.read() == nil, "failed message reads discard the incomplete snapshot")
        access.failRead = nil
        access.roots = [Node("AXWindow", children: (0..<65).map { _ in Node("AXGroup") })]
        expect(reader.read() == nil, "oversized child arrays invalidate the traversal instead of omitting unknown messages")
        var deep = legacy
        for _ in 0..<12 { deep = Node("AXGroup", children: [deep]) }
        access.roots = [deep]
        expect(reader.read() == nil, "depth-limited discovery is never presented as a complete snapshot")
    }

    private static func opening(expect: (Bool, String) -> Void) {
        let access = Access(), root = card(legacy: true), reader = access.reader()
        access.roots = [root]
        guard let id = reader.read()?.items.first?.id else { expect(false, "opening fixture has a live notification"); return }
        expect(reader.open(id) == .handedOff && access.presses == [root.id],
               "Open performs the original notification root's supported press exactly once")
        root.actions = []
        expect(reader.open(id) == .unavailable && access.presses.count == 1,
               "an action removed from the live root cannot use cached capability")
        root.actions = ["AXCustomAction"]
        expect(reader.read()?.items.first?.canOpen == false && reader.open(id) == .unavailable,
               "custom actions are never guessed as the notification's normal opening action")
        root.actions = ["AXPress"]
        access.pressSucceeds = false
        expect(reader.open(id) == .uncertain, "an unsuccessful native opening reports an uncertain handoff")
        access.roots = []
        _ = reader.read()
        let before = access.presses.count
        expect(reader.open(id) == .unavailable && access.presses.count == before,
               "a notification absent from the latest complete snapshot cannot be opened")
    }

    private static func interruption(expect: (Bool, String) -> Void) {
        for point in ["AXIdentifier", "AXValue", "actions"] {
            for expires in [false, true] {
                let access = Access(), root = card(legacy: true), reader = access.reader()
                access.roots = [root]
                guard let id = reader.read()?.items.first?.id else { expect(false, "interruption fixture is live"); continue }
                access.beforeRead = { operation, _ in
                    if operation == point {
                        if expires { access.time += 1 } else { access.allowed = false }
                    }
                }
                expect(reader.open(id) == .unavailable && access.presses.isEmpty,
                       "cancellation or timeout during \(point) cannot reach native opening")
            }
        }
        let access = Access(), root = card(legacy: true), reader = access.reader()
        access.roots = [root]
        guard let id = reader.read()?.items.first?.id else { expect(false, "content fixture is live"); return }
        root.children[0].strings["AXValue"] = "Changed sender"
        expect(reader.open(id) == .unavailable && access.presses.isEmpty,
               "a changed sender cannot inherit the old notification's opening action")
        root.children[0].strings["AXValue"] = "Alex"
        root.strings["AXIdentifier"] = "request." + UUID().uuidString
        expect(reader.open(id) == .unavailable && access.presses.isEmpty,
               "a native root reassigned to another identity cannot open the old notification")
    }

    private static func identity(expect: (Bool, String) -> Void) {
        let access = Access(), original = card(legacy: true), reader = access.reader()
        access.roots = [original]
        guard let first = reader.read()?.items.first else { expect(false, "identity fixture is live"); return }
        expect(reader.read()?.items.first == first, "repeated snapshots preserve identity and receipt time")
        let rebuilt = card(identity: original.strings["AXIdentifier"]!, legacy: true)
        access.roots = [rebuilt]
        expect(reader.read()?.items.first?.id == first.id && reader.open(first.id) == .handedOff
               && access.presses == [rebuilt.id],
               "native view reconstruction preserves mirror identity and opens the newly validated root")
        let duplicate = card(legacy: true)
        let conflict = card(identity: duplicate.strings["AXIdentifier"]!, sender: "Other", legacy: true)
        access.roots = [duplicate, conflict]
        let ambiguous = reader.read()?.items ?? []
        expect(ambiguous.count == 2 && ambiguous.allSatisfy { !$0.canOpen },
               "two live roots claiming one native identity cannot authorize opening")
        for item in ambiguous { expect(reader.open(item.id) == .unavailable, "ambiguous targets stay unavailable at action time") }
        access.roots = [duplicate]
        expect(reader.read()?.items.first?.canOpen == true, "a later unambiguous snapshot restores normal opening")
        let independent = card(legacy: true)
        access.roots = [duplicate, independent]
        expect(reader.read()?.items.count == 2, "identical visible text does not merge independent notification identities")
        duplicate.strings["AXIdentifier"] = "AXNotificationListItems"
        access.roots = [duplicate]
        guard let structural = reader.read()?.items.first else { expect(false, "structural fixture is readable"); return }
        expect(reader.read()?.items.first?.id == structural.id,
               "without a durable native identity, unchanged root identity still deduplicates visible notices")
    }
}
