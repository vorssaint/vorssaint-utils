// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// Only the notification reader's native operations cross this boundary. Missing
/// attributes are optional; a failed read throws so a partial tree cannot authorize
/// an action or silently become a complete inbox snapshot.
protocol NotchNotificationAccess {
    associatedtype Element
    func windows() throws -> [Element]
    func hasFocusedWindow() throws -> Bool
    func string(_ element: Element, _ attribute: String) throws -> String?
    func children(_ element: Element) throws -> [Element]
    func actions(_ element: Element) throws -> [String]
    func frame(_ element: Element) throws -> CGRect?
    func press(_ element: Element) -> Bool
    func perform(_ action: String, on element: Element) -> Bool
    func move(_ element: Element, to origin: CGPoint) -> Bool
    func same(_ lhs: Element, _ rhs: Element) -> Bool
}

/// The production traversal and action sequence also run against synthetic trees.
/// The service confines this object and its native adapter to one serial queue.
final class NotchNotificationReaderCore<Access: NotchNotificationAccess> {
    struct Snapshot { let items: [NotchSystemNotification] }
    enum ActionResult { case handedOff, openedApplication, unavailable, uncertain }

    private struct Target {
        let root: Access.Element
        let window: Access.Element
        let transient: Bool
        let nativeIdentity: String?
        let item: NotchSystemNotification
    }

    private let access: Access
    private let allowed: () -> Bool
    private let clock: () -> TimeInterval
    private let receivedDate: () -> Date
    private let sourceApplicationName: ([String]) -> String?
    private let allowsNativeClose: () -> Bool
    private let nativeCloseTitle: String
    private let displays: () -> [CGRect]
    private var targets: [Target] = []
    /// Windows moved off screen, with the place the center had given them.
    private var hiddenWindows: [(window: Access.Element, origin: CGPoint)] = []
    /// Windows that also hold an alert the reader could not take apart. The
    /// island never showed it, so such a window stays in sight.
    private var untakenWindows: [Access.Element] = []
    private var liveIDs = Set<UUID>()
    private var ambiguousIdentities = Set<String>()
    private var deadline: TimeInterval = 0
    private var remainingNodes = 0
    private var incomplete = false

    init(access: Access,
         allowed: @escaping () -> Bool,
         clock: @escaping () -> TimeInterval = { ProcessInfo.processInfo.systemUptime },
         receivedDate: @escaping () -> Date = Date.init,
         sourceApplicationName: @escaping ([String]) -> String? = { _ in nil },
         allowsNativeClose: @escaping () -> Bool = { false }, nativeCloseTitle: String = "",
         displays: @escaping () -> [CGRect] = { [] }) {
        self.access = access
        self.allowed = allowed
        self.clock = clock
        self.receivedDate = receivedDate
        self.sourceApplicationName = sourceApplicationName
        self.allowsNativeClose = allowsNativeClose
        self.nativeCloseTitle = nativeCloseTitle
        self.displays = displays
    }

    var hidesWindows: Bool { !hiddenWindows.isEmpty }

    /// A focused center is not a passive banner surface. Its existing
    /// notifications must not be imported as newly received messages.
    func read() -> Snapshot? {
        beginRead()
        guard let focused = fetch({ try access.hasFocusedWindow() }) else { return nil }
        // Someone opened the center. Nothing it lays out may stay off screen.
        guard !focused else { showNative(); return nil }
        guard let windows = fetch({ try access.windows() }), windows.count <= 32 else { return nil }
        var roots: [(root: Access.Element, window: Access.Element, transient: Bool)] = []
        for window in windows {
            var found: [(root: Access.Element, transient: Bool)] = []
            findBanners(window, depth: 0, into: &found)
            roots += found.map { ($0.root, window, $0.transient) }
        }
        guard usable else { return nil }
        var items: [NotchSystemNotification] = []
        var nextTargets = targets
        var currentIDs = Set<UUID>()
        var identityCounts: [String: Int] = [:]
        var untaken: [Access.Element] = []
        for candidate in roots {
            let root = candidate.root
            guard let content = content(root) else {
                if !candidate.transient, !untaken.contains(where: { access.same($0, candidate.window) }) {
                    untaken.append(candidate.window)
                }
                continue
            }
            let identity = NotchNotificationSupport.nativeIdentity(string(root, "AXIdentifier"))
            if let identity { identityCounts[identity, default: 0] += 1 }
            let old = nextTargets.first {
                $0.nativeIdentity == identity && $0.item.content == content
                    && (identity != nil || access.same($0.root, root))
            }
            let id = old?.item.id ?? UUID()
            guard currentIDs.insert(id).inserted else { continue }
            let rootActions = actions(root)
            let item = NotchSystemNotification(id: id, content: content, received: old?.item.received ?? receivedDate(),
                canOpen: rootActions.contains("AXPress"))
            nextTargets.removeAll { $0.item.id == id }
            nextTargets.append(Target(root: root, window: candidate.window, transient: candidate.transient,
                                      nativeIdentity: identity, item: item))
            items.append(item)
        }
        guard usable else { return nil }
        ambiguousIdentities = Set(identityCounts.filter { $0.value > 1 }.map(\.key))
        items = items.map { item in
            guard let target = nextTargets.first(where: { $0.item.id == item.id }),
                  let identity = target.nativeIdentity, ambiguousIdentities.contains(identity) else { return item }
            var ambiguous = item; ambiguous.canOpen = false
            return ambiguous
        }
        targets = Array(nextTargets.suffix(100))
        liveIDs = currentIDs
        untakenWindows = untaken
        return Snapshot(items: items)
    }

    func open(_ id: UUID) -> ActionResult {
        beginRead()
        guard let target = validatedTarget(id), actions(target.root).contains("AXPress"), usable else { return .unavailable }
        return access.press(target.root) ? .handedOff : .uncertain
    }

    func closeNative(_ id: UUID) -> Bool {
        // Closing persistent alerts can stop alarms. Only transient banners
        // may be replaced automatically; validate their current container too.
        guard allowsNativeClose(), read() != nil else { return false }
        // The refresh can spend nearly the whole traversal on a large stack.
        // Validation gets a budget of its own so a busy center does not leave
        // the banner open; a check it cannot finish still closes nothing.
        beginRead()
        guard let target = validatedTarget(id), target.transient,
              let action = NotchNotificationSupport.closeAction(in: actions(target.root), title: nativeCloseTitle),
              usable, allowsNativeClose() else { return false }
        return access.perform(action, on: target.root)
    }

    /// Moves the windows holding banners the island shows off screen. Unlike
    /// closing, the originals keep playing their sound and still reach the
    /// center when they expire. A window that also holds a persistent alert
    /// or a banner the island passed over stays in place, or comes back.
    /// Returns the shown banners that could not be hidden.
    func hideNative(_ shown: Set<UUID>) -> Set<UUID> {
        guard allowsNativeClose() else { showNative(); return [] }
        beginRead()
        // The open center keeps its banners in the same window as its list.
        guard let focused = fetch({ try access.hasFocusedWindow() }) else { return [] }
        guard !focused else { showNative(); return [] }
        var groups: [(window: Access.Element, targets: [Target])] = []
        for target in targets where liveIDs.contains(target.item.id) {
            if let index = groups.firstIndex(where: { access.same($0.window, target.window) }) {
                groups[index].targets.append(target)
            } else {
                groups.append((target.window, [target]))
            }
        }
        var failed = Set<UUID>()
        for group in groups {
            guard !untakenWindows.contains(where: { access.same($0, group.window) }),
                  group.targets.allSatisfy({ $0.transient && shown.contains($0.item.id) }) else {
                show(group.window); continue
            }
            // Every message in the window must still be the one the island took.
            guard group.targets.allSatisfy({ validatedTarget($0.item.id) != nil }), usable else { continue }
            if hide(group.window) == false { failed.formUnion(group.targets.map(\.item.id)) }
        }
        // Also once its banners are gone and only such an alert is left.
        for window in untakenWindows { show(window) }
        // An emptied window is left to the center, which places it again
        // before showing anything else. Forget the ones it placed or removed.
        hiddenWindows.removeAll { record in
            !groups.contains { access.same($0.window, record.window) }
                && [.onScreen, .gone].contains(placement(of: record.window))
        }
        return failed
    }

    /// Puts back every window this reader moved. Stopping or turning the
    /// option off runs this after the reader is no longer allowed to read.
    func showNative() {
        for window in hiddenWindows.map(\.window) { show(window) }
    }

    /// False when the window cannot be moved. A pass that ran out of time
    /// tries again on the next one instead of closing the banner.
    private func hide(_ window: Access.Element) -> Bool? {
        let screens = displays().reduce(CGRect.null) { $0.union($1) }
        guard !screens.isNull, let read = fetch({ try access.frame(window) }), usable else { return nil }
        guard let frame = read else { return false }
        // Already out of sight.
        guard frame.intersects(screens) else { return true }
        let away = CGPoint(x: screens.minX - frame.width - 1_000, y: screens.minY - frame.height - 1_000)
        guard access.move(window, to: away) else { return false }
        // A window that ignores the move, or lands on a display anyway, goes
        // back to where it was, and its banners are closed instead.
        guard let moved = fetch({ try access.frame(window) }) ?? nil, !moved.intersects(screens) else {
            _ = access.move(window, to: frame.origin)
            return false
        }
        hiddenWindows.removeAll { access.same($0.window, window) }
        hiddenWindows.append((window, frame.origin))
        return true
    }

    /// Only windows this reader moved come back, and only while the center
    /// has not placed them again itself. A window it cannot read right now
    /// stays on the list for the next attempt.
    private func show(_ window: Access.Element) {
        guard let index = hiddenWindows.firstIndex(where: { access.same($0.window, window) }) else { return }
        switch placement(of: window) {
        case .unknown: return
        case .offScreen: guard access.move(window, to: hiddenWindows[index].origin) else { return }
        case .onScreen, .gone: break
        }
        hiddenWindows.remove(at: index)
    }

    private enum Placement { case onScreen, offScreen, gone, unknown }

    /// Reads outside the traversal budget, so putting windows back never
    /// depends on the reader still being allowed to run.
    private func placement(of window: Access.Element) -> Placement {
        let screens = displays().reduce(CGRect.null) { $0.union($1) }
        guard !screens.isNull else { return .unknown }
        do {
            guard let frame = try access.frame(window) else { return .gone }
            return frame.intersects(screens) ? .onScreen : .offScreen
        } catch {
            return .unknown
        }
    }

    private var usable: Bool {
        !incomplete && allowed() && clock() < deadline && remainingNodes > 0
    }
    private func beginRead() { deadline = clock() + 0.8; remainingNodes = 384; incomplete = false }

    private func fetch<Value>(_ body: () throws -> Value) -> Value? {
        guard usable else { return nil }
        do {
            let value = try body()
            guard usable else { return nil }
            return value
        } catch {
            incomplete = true
            return nil
        }
    }

    private func validatedTarget(_ id: UUID) -> Target? {
        guard usable, liveIDs.contains(id), let target = targets.first(where: { $0.item.id == id }),
              target.nativeIdentity.map({ !ambiguousIdentities.contains($0) }) ?? true,
              target.nativeIdentity == NotchNotificationSupport.nativeIdentity(string(target.root, "AXIdentifier")),
              content(target.root) == target.item.content, usable else { return nil }
        return target
    }

    private func findBanners(_ node: Access.Element, depth: Int, into roots: inout [(root: Access.Element, transient: Bool)]) {
        guard visit(depth: depth) else { return }
        let subrole = string(node, "AXSubrole") ?? ""
        if NotchNotificationSupport.bannerRoles.contains(subrole) {
            roots.append((node, subrole == "AXNotificationCenterBanner")); return
        }
        if NotchNotificationSupport.stackRoles.contains(subrole) {
            findStackCards(node, depth: depth, transient: subrole == "AXNotificationCenterBannerStack", into: &roots)
            return
        }
        for child in children(node) { findBanners(child, depth: depth + 1, into: &roots) }
    }

    private func findStackCards(_ node: Access.Element, depth: Int, transient: Bool, into roots: inout [(root: Access.Element, transient: Bool)]) {
        guard usable else { return }
        if let card = content(node), !card.body.isEmpty || !card.app.isEmpty {
            // Modern stacks can be a structural wrapper around one complete
            // card. Descend only when the entire message is preserved; selecting
            // a title-only subgroup would lose its sender/body boundary.
            let completeChildren = children(node).filter { content($0) == card }
            if completeChildren.isEmpty { roots.append((node, transient)) }
            else {
                for child in completeChildren {
                    guard visit(depth: depth + 1) else { return }
                    findStackCards(child, depth: depth + 1, transient: transient, into: &roots)
                }
            }
            return
        }
        for child in children(node) {
            guard visit(depth: depth + 1) else { return }
            findStackCards(child, depth: depth + 1, transient: transient, into: &roots)
        }
    }

    private func content(_ root: Access.Element) -> NotchNotificationContent? {
        var texts: [NotchNotificationSupport.Text] = []
        var imageLabels: [String] = []
        walk(root, depth: 0) { node, role in
            if role == "AXImage", let label = string(node, "AXDescription"),
               !label.isEmpty, label.utf8.count <= 256 {
                imageLabels.append(label)
            }
            guard role == "AXStaticText" else { return }
            let identifier = string(node, "AXIdentifier") ?? ""
            guard ["", "header", "title", "subtitle", "body"].contains(identifier),
                  let text = string(node, "AXValue") else { return }
            texts.append(.init(identifier: identifier, value: text))
        }
        guard usable, let content = NotchNotificationSupport.content(from: texts) else { return nil }
        guard content.app.isEmpty else { return content }
        if let description = string(root, "AXAttributedDescription"),
           let label = NotchNotificationSupport.applicationLabel(from: description, content: content),
           let source = sourceApplicationName([label]), usable {
            return NotchNotificationContent(app: source, title: content.title, subtitle: content.subtitle, body: content.body)
        }
        let messageText = [content.title, content.subtitle, content.body]
        let sourceLabels = imageLabels.filter { label in
            !messageText.contains { $0.compare(label, options: .caseInsensitive) == .orderedSame }
        }
        guard usable, let source = sourceApplicationName(sourceLabels) else { return usable ? content : nil }
        return NotchNotificationContent(app: source, title: content.title, subtitle: content.subtitle, body: content.body)
    }

    private func visit(depth: Int) -> Bool {
        guard usable else { return false }
        guard depth <= 10 else { incomplete = true; return false }
        remainingNodes -= 1
        return usable
    }

    private func walk(_ node: Access.Element, depth: Int, visit action: (Access.Element, String) -> Void) {
        guard visit(depth: depth) else { return }
        action(node, string(node, "AXRole") ?? "")
        for child in children(node) { walk(child, depth: depth + 1, visit: action) }
    }

    private func children(_ node: Access.Element) -> [Access.Element] {
        guard let children = fetch({ try access.children(node) }) else { return [] }
        guard children.count <= 64 else { incomplete = true; return [] }
        return children
    }

    private func string(_ node: Access.Element, _ attribute: String) -> String? {
        fetch({ try access.string(node, attribute) }) ?? nil
    }
    private func actions(_ node: Access.Element) -> [String] { fetch({ try access.actions(node) }) ?? [] }
}
