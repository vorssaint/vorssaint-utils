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
    /// Writes a value, such as a reply's text into its field.
    func setString(_ value: String, _ attribute: String, on element: Element) -> Bool
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
    /// "Reply" and "Send" as macOS names them in the person's language, and in English.
    private let replyTitles: [String]
    private let sendTitles: [String]
    /// Notifications with their reply box open. Opening it empties the banner's own text,
    /// so these are held as they were, and matched by their element rather than their content.
    private var replying: [UUID: Target] = [:]
    private let displays: () -> [CGRect]
    private var targets: [Target] = []
    /// Windows moved off screen, with the place the center had given them.
    /// An unconfirmed move or return keeps restoring set until it is visible.
    private var hiddenWindows: [(window: Access.Element, origin: CGPoint, restoring: Bool)] = []
    /// Windows that also hold an alert the reader could not take apart. The
    /// island never showed it, so such a window stays in sight.
    private var untakenWindows: [Access.Element] = []
    /// Windows moved away the moment the center made them, before anyone
    /// read what they hold. The next placing pass keeps the ones the island
    /// took and puts every other one back; one still empty gets a short
    /// grace for its banner to lay out.
    private var prehiddenWindows: [(window: Access.Element, since: TimeInterval)] = []
    static var prehideGrace: TimeInterval { 0.5 }
    private var liveIDs = Set<UUID>()
    private var ambiguousIdentities = Set<String>()
    private var deadline: TimeInterval = 0
    private var remainingNodes = 0
    private var incomplete = false
    private var lastFocusedAt: TimeInterval?

    init(access: Access,
         allowed: @escaping () -> Bool,
         clock: @escaping () -> TimeInterval = { ProcessInfo.processInfo.systemUptime },
         receivedDate: @escaping () -> Date = Date.init,
         sourceApplicationName: @escaping ([String]) -> String? = { _ in nil },
         allowsNativeClose: @escaping () -> Bool = { false }, nativeCloseTitle: String = "",
         replyTitles: [String] = ["Reply"], sendTitles: [String] = ["Send"],
         displays: @escaping () -> [CGRect] = { [] }) {
        self.access = access
        self.allowed = allowed
        self.clock = clock
        self.receivedDate = receivedDate
        self.sourceApplicationName = sourceApplicationName
        self.allowsNativeClose = allowsNativeClose
        self.nativeCloseTitle = nativeCloseTitle
        self.replyTitles = replyTitles
        self.sendTitles = sendTitles
        self.displays = displays
    }

    var hidesWindows: Bool { !hiddenWindows.isEmpty }

    /// A failed query is unknown, never a cached answer from an earlier read.
    /// Settling arrivals only needs this query, not another tree traversal.
    func centerIsFocused() -> Bool? {
        beginRead()
        guard let focused = fetch({ try access.hasFocusedWindow() }) else { showNative(); return nil }
        if focused {
            lastFocusedAt = clock()
            showNative()
        }
        return focused
    }

    /// A quick open and close may end before the delayed check. The list
    /// still belongs to the center if a scan saw it focused during this opening.
    func centerWasFocused(since opening: TimeInterval) -> Bool? {
        let current = centerIsFocused()
        if let lastFocusedAt, lastFocusedAt >= opening { return true }
        return current
    }

    /// Measured after the actual move, not when its work entered the queue.
    /// Failed moves and restorations retry without another AX event.
    var prehideRetryDelay: TimeInterval? {
        if hiddenWindows.contains(where: { $0.restoring }) { return 0.1 }
        let now = clock()
        return prehiddenWindows.map { max(0.1, $0.since + Self.prehideGrace - now) }.min()
    }

    /// A focused center is not a passive banner surface. Its existing
    /// notifications must not be imported as newly received messages.
    func read() -> Snapshot? {
        guard let focused = centerIsFocused(), !focused else { return nil }
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
            // A reply box being typed into keeps its message, whatever the banner now shows.
            if let held = replying.values.first(where: { access.same($0.root, root) }) {
                guard currentIDs.insert(held.item.id).inserted else { continue }
                nextTargets.removeAll { $0.item.id == held.item.id }
                nextTargets.append(held)
                items.append(held.item)
                continue
            }
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
                canOpen: rootActions.contains("AXPress"),
                canReply: NotchNotificationSupport.namedAction(in: rootActions, titles: replyTitles) != nil)
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

    // MARK: Replies

    /// Opens the notification's own reply box. It keeps the banner from expiring while the
    /// reply is written on the island. True once the box is there to type into.
    func beginReply(_ id: UUID) -> Bool {
        if let held = replying[id] { beginRead(); return replyField(in: held.root) != nil }
        beginRead()
        guard let target = validatedTarget(id) else { Self.logReply("beginReply: target no longer on screen"); return false }
        let available = actions(target.root)
        guard let action = NotchNotificationSupport.namedAction(in: available, titles: replyTitles), usable else {
            Self.logReply("beginReply: no single Reply action among \(available.map { $0.replacingOccurrences(of: "\n", with: "/") })")
            return false
        }
        // macOS reports a failure for this action even when the box opens, so the box itself is the answer.
        _ = access.perform(action, on: target.root)
        // A slow Mac or a sender that animates its box open needs more than a moment.
        for attempt in 0..<25 {
            beginRead()
            if replyField(in: target.root) != nil {
                replying[id] = target
                Self.logReply("beginReply: box open after \(attempt + 1) tries")
                return true
            }
            Thread.sleep(forTimeInterval: 0.12)
        }
        Self.logReply("beginReply: pressed Reply but no text box appeared in 3 s")
        return false
    }

    /// Types the reply into the notification's box and presses its Send. True when it was sent.
    func sendReply(_ id: UUID, text: String) -> Bool {
        let message = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !message.isEmpty, let target = replying[id] else { return false }
        beginRead()
        guard let field = replyField(in: target.root) else { Self.logReply("sendReply: box is gone"); return false }
        guard access.setString(message, "AXValue", on: field) else { Self.logReply("sendReply: could not type into the box"); return false }
        let available = actions(target.root)
        guard let send = NotchNotificationSupport.namedAction(in: available, titles: sendTitles), usable else {
            Self.logReply("sendReply: no single Send action among \(available.map { $0.replacingOccurrences(of: "\n", with: "/") })")
            return false
        }
        let sent = access.perform(send, on: target.root)
        Self.logReply("sendReply: Send performed \(sent)")
        if sent { replying[id] = nil }
        return sent
    }

    /// Closes a reply box that was not sent; the notification goes back to how it was.
    func cancelReply(_ id: UUID) {
        guard let target = replying.removeValue(forKey: id) else { return }
        beginRead()
        let hide = actions(target.root).first {
            ($0.components(separatedBy: "\n").first ?? "").localizedCaseInsensitiveContains("Hide")
        }
        if let hide { _ = access.perform(hide, on: target.root) }
    }

    /// Why a reply did not go, kept in a small file so it can be looked at.
    private static func logReply(_ line: String) {
        let url = URL(fileURLWithPath: "/tmp/vorssaint-reply.log")
        let text = ISO8601DateFormatter().string(from: Date()) + " " + line + "\n"
        if let handle = try? FileHandle(forWritingTo: url) {
            handle.seekToEndOfFile(); handle.write(Data(text.utf8)); try? handle.close()
        } else { try? text.write(to: url, atomically: true, encoding: .utf8) }
    }

    private func replyField(in root: Access.Element) -> Access.Element? {
        var field: Access.Element?
        walk(root, depth: 0) { node, role in
            if field == nil, role == "AXTextArea" || role == "AXTextField" { field = node }
        }
        return usable ? field : nil
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
    /// Unconfirmed arrivals stay hidden through their focus decision, even
    /// when a slow read or a second window outlasts the initial arrival grace.
    /// Returns the shown banners that could not be hidden.
    func hideNative(_ shown: Set<UUID>, holding: Set<UUID> = []) -> Set<UUID> {
        // A failed rollback is still ours to restore, even when no complete
        // read ever produced a notification target for that window.
        for window in hiddenWindows.filter(\.restoring).map(\.window) { show(window) }
        guard allowsNativeClose() else { showNative(); return [] }
        // The open center keeps its banners in the same window as its list.
        guard centerIsFocused() == false else { return [] }
        var groups: [(window: Access.Element, targets: [Target])] = []
        for target in targets where liveIDs.contains(target.item.id) {
            if let index = groups.firstIndex(where: { access.same($0.window, target.window) }) {
                groups[index].targets.append(target)
            } else {
                groups.append((target.window, [target]))
            }
        }
        var failed = Set<UUID>()
        var kept: [Access.Element] = []
        for group in groups {
            guard !untakenWindows.contains(where: { access.same($0, group.window) }),
                  group.targets.allSatisfy({ $0.transient && (shown.contains($0.item.id) || holding.contains($0.item.id)) }) else {
                show(group.window); continue
            }
            // Every message in the window must still be the one the island took.
            guard group.targets.allSatisfy({ validatedTarget($0.item.id) != nil }), usable else { continue }
            switch hide(group.window) {
            case true?: kept.append(group.window)
            case false?: failed.formUnion(group.targets.map(\.item.id).filter { shown.contains($0) })
            case nil: break
            }
        }
        // A window moved on arrival whose banner the island did not take
        // comes back now; one still holding no banner, once its grace is over.
        let now = clock()
        prehiddenWindows.removeAll { record in
            if kept.contains(where: { access.same($0, record.window) }) { return true }
            let holdsBanner = groups.contains { access.same($0.window, record.window) }
            guard holdsBanner || now - record.since >= Self.prehideGrace else { return false }
            return show(record.window)
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

    /// Moves a window the center just made off screen at once, so a banner
    /// the island goes on to show never draws its first frames.
    func prehide(_ window: Access.Element) {
        guard allowsNativeClose() else { return }
        guard centerIsFocused() == false else { return }
        guard allowsNativeClose(), hide(window) == true,
              hiddenWindows.contains(where: { access.same($0.window, window) }) else { return }
        prehiddenWindows.removeAll { access.same($0.window, window) }
        prehiddenWindows.append((window, clock()))
    }

    /// Shutdown drains every queued move, even when a main-thread result
    /// still describes the state before the most recent arrival.
    func restoreNativeSynchronously(on queue: DispatchQueue) {
        queue.sync { showNative() }
    }

    /// Puts back every window this reader moved. Stopping or turning the
    /// option off runs this after the reader is no longer allowed to read.
    func showNative() {
        for window in hiddenWindows.map(\.window) { show(window) }
        prehiddenWindows.removeAll { record in
            !hiddenWindows.contains { access.same($0.window, record.window) }
        }
    }

    /// False when the window cannot be moved. A pass that ran out of time
    /// tries again on the next one instead of closing the banner.
    private func hide(_ window: Access.Element) -> Bool? {
        guard !hiddenWindows.contains(where: { $0.restoring && access.same($0.window, window) }) else { return nil }
        let screens = displays().reduce(CGRect.null) { $0.union($1) }
        guard !screens.isNull, let read = fetch({ try access.frame(window) }), usable else { return nil }
        guard let frame = read else { return false }
        // Already out of sight.
        guard frame.intersects(screens) else { return true }
        let away = CGPoint(x: screens.minX - frame.width - 1_000, y: screens.minY - frame.height - 1_000)
        guard access.move(window, to: away) else { return false }
        // The move already happened. Keep its origin before any fallible
        // confirmation, so an unsuccessful rollback cannot lose the window.
        hiddenWindows.removeAll { access.same($0.window, window) }
        hiddenWindows.append((window, frame.origin, restoring: true))
        // A window that ignores the move, or lands on a display anyway, goes
        // back to where it was, and its banners are closed instead.
        let moved = fetch({ try access.frame(window) }) ?? nil
        guard let moved, !moved.intersects(screens) else {
            _ = access.move(window, to: frame.origin)
            if [.onScreen, .gone].contains(placement(of: window)) {
                hiddenWindows.removeAll { access.same($0.window, window) }
            }
            // A failed confirmation cannot authorize closing a banner. Its
            // pending restoration is retried outside the traversal budget.
            return moved == nil ? nil : false
        }
        hiddenWindows[hiddenWindows.count - 1].restoring = false
        return true
    }

    /// Only windows this reader moved come back, and only while the center
    /// has not placed them again itself. A window it cannot read right now
    /// stays on the list for the next attempt.
    @discardableResult
    private func show(_ window: Access.Element) -> Bool {
        guard let index = hiddenWindows.firstIndex(where: { access.same($0.window, window) }) else { return true }
        hiddenWindows[index].restoring = true
        switch placement(of: window) {
        case .unknown: return false
        case .offScreen:
            guard access.move(window, to: hiddenWindows[index].origin),
                  [.onScreen, .gone].contains(placement(of: window)) else { return false }
        case .onScreen, .gone: break
        }
        hiddenWindows.remove(at: index)
        return true
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
