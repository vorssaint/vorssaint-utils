// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// Combo mode's keymap: a tree of single keys. A group opens the next level,
/// an action runs and ends the combo. Everything here is plain data and pure
/// rules, so the overlay, Settings and the tests share one definition.

/// What a key does when it ends a combo. Encoded with a `kind` tag so new
/// kinds can be added without breaking keymaps saved by earlier versions.
enum ComboAction: Equatable, Hashable {
    case openApplication(ComboAppReference)

    var kind: String {
        switch self {
        case .openApplication: return "openApplication"
        }
    }
}

/// An app chosen by the user. The bundle identifier survives the app moving
/// or being reinstalled elsewhere; the path covers apps without one.
struct ComboAppReference: Codable, Equatable, Hashable {
    var bundleID: String?
    var path: String

    init(bundleID: String?, path: String) {
        let trimmed = bundleID?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.bundleID = trimmed?.isEmpty == false ? trimmed : nil
        self.path = path
    }

    private enum CodingKeys: String, CodingKey { case bundleID, path }

    /// Through the trimming initializer, so a hand-edited blank bundle id
    /// reads as none and the path fallback is used.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(bundleID: try container.decodeIfPresent(String.self, forKey: .bundleID),
                  path: (try container.decodeIfPresent(String.self, forKey: .path)) ?? "")
    }

    /// The app's display name when nothing else is known: its file name
    /// without the extension.
    var fallbackName: String {
        let name = ((path as NSString).lastPathComponent as NSString).deletingPathExtension
        return name.isEmpty ? (bundleID ?? "") : name
    }

    /// Where the app lives now: the bundle identifier first, then the saved
    /// path when it still exists.
    func resolvedURL(urlForBundleID: (String) -> URL?,
                     fileExists: (String) -> Bool) -> URL? {
        if let bundleID, let url = urlForBundleID(bundleID) { return url }
        guard !path.isEmpty, fileExists(path) else { return nil }
        return URL(fileURLWithPath: path)
    }
}

extension ComboAction: Codable {
    private enum CodingKeys: String, CodingKey { case kind, app }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try container.decode(String.self, forKey: .kind)
        switch kind {
        case "openApplication":
            let app = try container.decode(ComboAppReference.self, forKey: .app)
            guard !app.path.isEmpty || app.bundleID != nil else {
                throw DecodingError.dataCorruptedError(forKey: .app, in: container,
                                                       debugDescription: "An app needs a path or a bundle identifier")
            }
            self = .openApplication(app)
        default:
            throw DecodingError.dataCorruptedError(forKey: .kind, in: container,
                                                   debugDescription: "Unknown combo action \(kind)")
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(kind, forKey: .kind)
        switch self {
        case .openApplication(let app):
            try container.encode(app, forKey: .app)
        }
    }
}

/// The single character a node answers to.
enum ComboKey {
    /// One printable character. Space is allowed (it shows as ␣); other
    /// whitespace and control characters are not, since they cannot be
    /// told apart on screen.
    static func isValid(_ key: String) -> Bool {
        guard key.count == 1, let character = key.first else { return false }
        if key == " " { return true }
        return !character.unicodeScalars.contains {
            CharacterSet.whitespacesAndNewlines.contains($0)
                || CharacterSet.controlCharacters.contains($0)
                // Arrow and function keys arrive as private-use characters.
                || (0xF700...0xF8FF).contains($0.value)
        }
    }

    static func display(_ key: String) -> String {
        key == " " ? "␣" : key
    }

    /// The key a typed string stands for, or nil when it is not one key.
    static func normalized(_ typed: String?) -> String? {
        guard let typed, isValid(typed) else { return nil }
        return typed
    }

    /// Candidates offered for a new node, in order.
    static let suggestions: [String] = Array("abcdefghijklmnopqrstuvwxyz0123456789").map(String.init)
}

/// One row of the keymap: a key, a label and either more keys or an action.
struct ComboNode: Equatable, Identifiable {
    enum Content: Equatable {
        case group(symbol: String, children: [ComboNode])
        case action(ComboAction)
    }

    var id: UUID
    var key: String
    var label: String
    var content: Content

    init(id: UUID = UUID(), key: String, label: String, content: Content) {
        self.id = id
        self.key = key
        self.label = label
        self.content = content
    }

    static func group(key: String, label: String, symbol: String = ComboNode.defaultGroupSymbol,
                      children: [ComboNode] = [], id: UUID = UUID()) -> ComboNode {
        ComboNode(id: id, key: key, label: label, content: .group(symbol: symbol, children: children))
    }

    static func action(key: String, label: String, _ action: ComboAction, id: UUID = UUID()) -> ComboNode {
        ComboNode(id: id, key: key, label: label, content: .action(action))
    }

    static let defaultGroupSymbol = "folder"
    /// Symbols offered for a group's icon.
    static let groupSymbols = ["folder", "square.grid.2x2", "app.badge", "hammer", "globe",
                               "message", "music.note", "paintbrush", "doc.text", "terminal",
                               "gamecontroller", "star"]

    var isGroup: Bool {
        if case .group = content { return true }
        return false
    }

    var children: [ComboNode] {
        if case .group(_, let children) = content { return children }
        return []
    }

    var action: ComboAction? {
        if case .action(let action) = content { return action }
        return nil
    }

    var groupSymbol: String? {
        if case .group(let symbol, _) = content { return symbol }
        return nil
    }
}

extension ComboNode: Codable {
    private enum CodingKeys: String, CodingKey { case id, key, label, symbol, children, action }

    /// Nesting a tampered or hand-edited file can ask for before decoding
    /// stops; the editor never builds anything near this deep.
    static let maxDepth = 16

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        // Each level adds two path components: "children" and the index.
        guard decoder.codingPath.count <= Self.maxDepth * 2 + 2 else {
            throw DecodingError.dataCorruptedError(forKey: .children, in: container,
                                                   debugDescription: "Combo keymap nested too deeply")
        }
        id = (try? container.decode(UUID.self, forKey: .id)) ?? UUID()
        key = try container.decode(String.self, forKey: .key)
        label = (try? container.decode(String.self, forKey: .label)) ?? ""
        if container.contains(.action) {
            content = .action(try container.decode(ComboAction.self, forKey: .action))
        } else if !container.contains(.children) {
            // Neither an action nor a group: nothing this build can show.
            throw DecodingError.keyNotFound(CodingKeys.children, .init(
                codingPath: decoder.codingPath, debugDescription: "A combo node is an action or a group"))
        } else {
            let symbol = (try? container.decode(String.self, forKey: .symbol)) ?? Self.defaultGroupSymbol
            let children = (try? container.decode(LossyNodes.self, forKey: .children))?.nodes ?? []
            content = .group(symbol: symbol.isEmpty ? Self.defaultGroupSymbol : symbol, children: children)
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(key, forKey: .key)
        try container.encode(label, forKey: .label)
        switch content {
        case .group(let symbol, let children):
            try container.encode(symbol, forKey: .symbol)
            try container.encode(children, forKey: .children)
        case .action(let action):
            try container.encode(action, forKey: .action)
        }
    }
}

/// Decodes a list while dropping the entries this build cannot read (an
/// action kind added by a later version), so one of them never costs the
/// whole keymap.
private struct LossyNodes: Decodable {
    let nodes: [ComboNode]

    private struct Skip: Decodable {}

    init(from decoder: Decoder) throws {
        var container = try decoder.unkeyedContainer()
        var nodes: [ComboNode] = []
        while !container.isAtEnd {
            if let node = try? container.decode(ComboNode.self) {
                nodes.append(node)
            } else {
                _ = try? container.decode(Skip.self)
            }
        }
        self.nodes = nodes
    }
}

/// The whole tree, with its lookups, the sibling-key rule and the edits the
/// Settings editor makes.
struct ComboKeymap: Equatable {
    var nodes: [ComboNode]

    init(nodes: [ComboNode] = []) {
        self.nodes = nodes
    }

    static let formatVersion = 1

    // MARK: Encoding

    private struct Envelope: Codable {
        var version: Int
        var nodes: [ComboNode]
    }

    private struct LossyEnvelope: Decodable {
        var version: Int
        var nodes: LossyNodes
    }

    func encoded() -> Data? {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try? encoder.encode(Envelope(version: Self.formatVersion, nodes: nodes))
    }

    /// Nil when the data is not a keymap at all; a keymap with entries this
    /// build does not know keeps every entry it does know.
    static func decode(_ data: Data?) -> ComboKeymap? {
        guard let data, !data.isEmpty,
              let envelope = try? JSONDecoder().decode(LossyEnvelope.self, from: data),
              // A new action kind is skipped entry by entry and needs no new
              // version; a bump means the format itself changed, which this
              // build cannot read safely.
              (1...formatVersion).contains(envelope.version)
        else { return nil }
        var seen: Set<UUID> = []
        return ComboKeymap(nodes: uniquingIDs(envelope.nodes.nodes, seen: &seen))
    }

    /// Edits address nodes by id, so a hand-edited file that repeats one
    /// gets fresh ids for the repeats.
    private static func uniquingIDs(_ level: [ComboNode], seen: inout Set<UUID>) -> [ComboNode] {
        level.map { node in
            var node = node
            if !seen.insert(node.id).inserted {
                node.id = UUID()
                seen.insert(node.id)
            }
            if case .group(let symbol, let children) = node.content {
                node.content = .group(symbol: symbol, children: uniquingIDs(children, seen: &seen))
            }
            return node
        }
    }

    // MARK: Lookup

    /// The children shown at a level: the root for nil, a group's children
    /// otherwise, nil when the id is unknown or not a group.
    func children(of parentID: UUID?) -> [ComboNode]? {
        guard let parentID else { return nodes }
        guard let parent = node(id: parentID), parent.isGroup else { return nil }
        return parent.children
    }

    func node(id: UUID) -> ComboNode? {
        Self.find(id, in: nodes)
    }

    private static func find(_ id: UUID, in nodes: [ComboNode]) -> ComboNode? {
        for node in nodes {
            if node.id == id { return node }
            if let found = find(id, in: node.children) { return found }
        }
        return nil
    }

    /// The child of a level that answers a key.
    static func match(_ key: String, in siblings: [ComboNode]) -> ComboNode? {
        siblings.first { $0.key == key && ComboKey.isValid($0.key) }
    }

    /// The node a full sequence of keys reaches from the root.
    func lookup(_ keys: [String]) -> ComboNode? {
        var level = nodes
        var reached: ComboNode?
        for key in keys {
            guard reached == nil || reached?.isGroup == true,
                  let next = Self.match(key, in: level) else { return nil }
            reached = next
            level = next.children
        }
        return reached
    }

    /// The parent group's id (nil for the root) of a node, or `.none` when
    /// the id is unknown.
    func parentID(of id: UUID) -> UUID?? {
        Self.parent(of: id, in: nodes, parent: nil)
    }

    private static func parent(of id: UUID, in nodes: [ComboNode], parent: UUID?) -> UUID?? {
        for node in nodes {
            if node.id == id { return .some(parent) }
            if let found = Self.parent(of: id, in: node.children, parent: node.id) { return found }
        }
        return nil
    }

    // MARK: Sibling keys

    enum KeyIssue: Equatable {
        case empty
        case invalid
        case duplicate
    }

    /// Whether a key can be given to a node in a level: one valid character
    /// no sibling uses. The same key in another group is fine.
    func keyIssue(_ key: String, parentID: UUID?, excluding id: UUID?) -> KeyIssue? {
        if key.isEmpty { return .empty }
        if !ComboKey.isValid(key) { return .invalid }
        let siblings = children(of: parentID) ?? []
        if siblings.contains(where: { $0.id != id && $0.key == key }) { return .duplicate }
        return nil
    }

    /// The first suggested key no sibling uses yet, or nil when all are taken.
    func nextFreeKey(parentID: UUID?) -> String? {
        let used = Set((children(of: parentID) ?? []).map(\.key))
        return ComboKey.suggestions.first { !used.contains($0) }
    }

    /// Nodes whose key is missing, unusable, or shared with an earlier
    /// sibling, anywhere in the tree. A keymap from a backup or an older
    /// build is shown with these marked instead of being rewritten.
    var nodesWithKeyIssues: Set<UUID> {
        var result: Set<UUID> = []
        Self.collectIssues(in: nodes, into: &result)
        return result
    }

    private static func collectIssues(in level: [ComboNode], into result: inout Set<UUID>) {
        var seen: Set<String> = []
        for node in level {
            if !ComboKey.isValid(node.key) || !seen.insert(node.key).inserted {
                result.insert(node.id)
            }
            collectIssues(in: node.children, into: &result)
        }
    }

    var nodeCount: Int {
        func count(_ level: [ComboNode]) -> Int { level.reduce(level.count) { $0 + count($1.children) } }
        return count(nodes)
    }

    // MARK: Edits

    /// Adds a node to a level (the end by default). Refuses an unknown or
    /// non-group parent and a key a sibling already answers to.
    @discardableResult
    mutating func insert(_ node: ComboNode, into parentID: UUID?, at index: Int? = nil) -> Bool {
        guard keyIssue(node.key, parentID: parentID, excluding: nil) != .duplicate,
              self.node(id: node.id) == nil
        else { return false }
        return Self.mutateLevel(parentID, in: &nodes) { level in
            let position = min(max(index ?? level.count, 0), level.count)
            level.insert(node, at: position)
            return true
        }
    }

    /// Removes a node and everything under it.
    @discardableResult
    mutating func remove(id: UUID) -> ComboNode? {
        Self.remove(id, from: &nodes)
    }

    private static func remove(_ id: UUID, from level: inout [ComboNode]) -> ComboNode? {
        if let index = level.firstIndex(where: { $0.id == id }) {
            return level.remove(at: index)
        }
        for index in level.indices {
            guard case .group(let symbol, var children) = level[index].content else { continue }
            if let removed = remove(id, from: &children) {
                level[index].content = .group(symbol: symbol, children: children)
                return removed
            }
        }
        return nil
    }

    /// Moves a node to another level or position. Refuses moving a group
    /// into itself or its own descendants, and a key the destination
    /// already uses.
    @discardableResult
    mutating func move(id: UUID, to parentID: UUID?, at index: Int? = nil) -> Bool {
        guard let moving = node(id: id) else { return false }
        if let parentID {
            if parentID == id || Self.find(parentID, in: moving.children) != nil { return false }
            guard node(id: parentID)?.isGroup == true else { return false }
        }
        guard keyIssue(moving.key, parentID: parentID, excluding: id) != .duplicate else { return false }
        var copy = self
        guard let currentParent = copy.parentID(of: id) else { return false }
        let sourceIndex = (copy.children(of: currentParent) ?? []).firstIndex { $0.id == id }
        guard let removed = copy.remove(id: id) else { return false }
        var target = index
        // Within the same level, an index counted before the removal shifts.
        if currentParent == parentID, let sourceIndex, let wanted = index, wanted > sourceIndex {
            target = wanted - 1
        }
        guard copy.insert(removed, into: parentID, at: target) else { return false }
        self = copy
        return true
    }

    /// Changes one node in place. The change may not alter its id, and a
    /// new key must stay unique among its siblings.
    @discardableResult
    mutating func update(id: UUID, _ change: (inout ComboNode) -> Void) -> Bool {
        guard let original = node(id: id), let parent = parentID(of: id) else { return false }
        var edited = original
        change(&edited)
        guard edited.id == id else { return false }
        if edited.key != original.key,
           keyIssue(edited.key, parentID: parent, excluding: id) == .duplicate {
            return false
        }
        return Self.mutateLevel(parent, in: &nodes) { level in
            guard let index = level.firstIndex(where: { $0.id == id }) else { return false }
            level[index] = edited
            return true
        }
    }

    private static func mutateLevel(_ parentID: UUID?, in level: inout [ComboNode],
                                    _ body: (inout [ComboNode]) -> Bool) -> Bool {
        guard let parentID else { return body(&level) }
        for index in level.indices {
            guard case .group(let symbol, var children) = level[index].content else { continue }
            if level[index].id == parentID {
                let changed = body(&children)
                level[index].content = .group(symbol: symbol, children: children)
                return changed
            }
            if mutateLevel(parentID, in: &children, body) {
                level[index].content = .group(symbol: symbol, children: children)
                return true
            }
        }
        return false
    }
}

/// The overlay's state while a combo is typed: where in the tree it stands
/// and what each key does. Kept apart from the panel so it can be tested.
struct ComboNavigator: Equatable {
    let keymap: ComboKeymap
    /// The groups entered so far, outermost first.
    private(set) var path: [ComboNode] = []

    init(keymap: ComboKeymap) {
        self.keymap = keymap
    }

    enum Outcome: Equatable {
        /// A group opened; the overlay shows its children.
        case descended(ComboNode)
        /// An action was chosen; the combo ends and the action runs.
        case run(ComboAction, ComboNode)
        /// Nothing at this level answers the key; the combo ends.
        case noMatch
        /// Backspace went up one level.
        case ascended
        /// The combo ends without doing anything.
        case cancelled
    }

    var currentChildren: [ComboNode] {
        path.last?.children ?? keymap.nodes
    }

    /// The keys typed so far, as shown in the breadcrumb.
    var typedKeys: [String] {
        path.map(\.key)
    }

    mutating func press(_ key: String) -> Outcome {
        guard let node = ComboKeymap.match(key, in: currentChildren) else { return .noMatch }
        switch node.content {
        case .group:
            path.append(node)
            return .descended(node)
        case .action(let action):
            return .run(action, node)
        }
    }

    /// Backspace: up one level, or the end of the combo at the root.
    mutating func back() -> Outcome {
        guard !path.isEmpty else { return .cancelled }
        path.removeLast()
        return .ascended
    }
}

/// The trigger shortcut has no default: the registered value is the cleared
/// marker, so nothing is registered until the user records a shortcut.
enum ComboTrigger {
    static let clearedStorageValue = "none"

    /// The recorded shortcut, or nil when none was recorded, it was cleared,
    /// or the stored value is unreadable.
    static func shortcut(storedValue: String?) -> GlobalShortcut? {
        guard let storedValue, storedValue != clearedStorageValue else { return nil }
        return GlobalShortcut(storageValue: storedValue)
    }
}

/// What one key press means to the open overlay. Kept apart from AppKit so
/// the rules are testable: the service passes the event's fields in.
enum ComboKeyPress: Equatable {
    /// Escape: close without doing anything.
    case cancel
    /// Backspace: up one level, or close at the root.
    case back
    /// A character to look up among the current keys.
    case key(String)
    /// Swallowed with no effect: key repeats, dead keys and ⌘ or ⌃
    /// combinations, which belong to no combo.
    case ignore
    /// A key that can never be a combo key (an arrow, Return, Tab…): it
    /// ends the combo like a key with nothing on it.
    case unusable(String)

    static let escapeKeyCode: UInt16 = 0x35
    static let deleteKeyCode: UInt16 = 0x33

    static func classify(keyCode: UInt16, characters: String?, isRepeat: Bool,
                         hasCommandOrControl: Bool) -> ComboKeyPress {
        if keyCode == escapeKeyCode { return .cancel }
        if isRepeat || hasCommandOrControl { return .ignore }
        if keyCode == deleteKeyCode { return .back }
        guard let characters, !characters.isEmpty else { return .ignore }
        if let key = ComboKey.normalized(characters) { return .key(key) }
        return .unusable(characters)
    }

    /// How an unusable key is named in the "nothing on" message.
    static func displayName(_ characters: String) -> String {
        switch characters.unicodeScalars.first?.value {
        case 0x0D, 0x03: return "↩"
        case 0x09: return "⇥"
        case 0xF700: return "↑"
        case 0xF701: return "↓"
        case 0xF702: return "←"
        case 0xF703: return "→"
        default: return "?"
        }
    }
}
