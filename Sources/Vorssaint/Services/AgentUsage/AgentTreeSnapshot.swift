// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// Agent Tree, a separate app, follows which agents spawned which in a thread
/// and keeps a small summary of it in `~/.agent-tree/live.json` after every
/// scan. That file is all Vorssaint reads from it, and it never writes there.
/// The format belongs to Agent Tree, so a schema this reader does not know,
/// or a node it cannot read, is left out rather than guessed.
struct AgentTreeSnapshot: Decodable, Equatable {
    struct Node: Decodable, Equatable, Identifiable {
        let id: String
        let parentID: String?
        let depth: Int
        let label: String
        let model: String
        /// "anthropic", "openai" or another maker; empty when unknown.
        let family: String
        let status: String
        let running: Bool
        /// Tokens of the node and everything it spawned.
        let tokens: Int
        /// Estimated in US dollars; nil when no price is known.
        let cost: Double?

        enum CodingKeys: String, CodingKey {
            case id, depth, label, model, family, status, running, tokens, cost
            case parentID = "parent_id"
        }

        init(id: String, parentID: String? = nil, depth: Int = 0, label: String = "", model: String = "",
             family: String = "", status: String = "", running: Bool = false, tokens: Int = 0, cost: Double? = nil) {
            self.id = id
            self.parentID = parentID
            self.depth = depth
            self.label = label
            self.model = model
            self.family = family
            self.status = status
            self.running = running
            self.tokens = tokens
            self.cost = cost
        }

        init(from decoder: Decoder) throws {
            let values = try decoder.container(keyedBy: CodingKeys.self)
            let id = try values.decode(String.self, forKey: .id)
            self.init(id: id,
                      parentID: (try? values.decodeIfPresent(String.self, forKey: .parentID)),
                      depth: min(AgentTreeLive.deepest, max(0, (try? values.decodeIfPresent(Int.self, forKey: .depth)) ?? 0)),
                      label: ((try? values.decodeIfPresent(String.self, forKey: .label)) ?? "")
                        .trimmingCharacters(in: .whitespacesAndNewlines),
                      model: (try? values.decodeIfPresent(String.self, forKey: .model)) ?? "",
                      family: (try? values.decodeIfPresent(String.self, forKey: .family)) ?? "",
                      status: (try? values.decodeIfPresent(String.self, forKey: .status)) ?? "",
                      running: (try? values.decodeIfPresent(Bool.self, forKey: .running)) ?? false,
                      tokens: AgentTreeLive.count((try? values.decodeIfPresent(Double.self, forKey: .tokens))),
                      cost: AgentTreeLive.money((try? values.decodeIfPresent(Double.self, forKey: .cost))))
        }

        var failed: Bool { ["error", "failed", "failure", "aborted", "cancelled", "canceled", "interrupted", "killed"].contains(status) }
    }

    struct Tree: Decodable, Equatable {
        let threadID: String
        let title: String
        /// Whether a thread is running now; otherwise this is the most recent one.
        let live: Bool
        let nodeCount: Int
        let maxDepth: Int
        let tokens: Int
        let cost: Double?
        /// Depth first, as Agent Tree lists them, and at most a few dozen.
        /// Each has an id of its own: one without an id, or repeating one
        /// listed earlier, is left out.
        let nodes: [Node]

        enum CodingKeys: String, CodingKey {
            case title, live, tokens, cost, nodes
            case threadID = "thread_id"
            case nodeCount = "node_count"
            case maxDepth = "max_depth"
        }

        init(threadID: String = "", title: String = "", live: Bool = false, nodeCount: Int? = nil, maxDepth: Int? = nil,
             tokens: Int = 0, cost: Double? = nil, nodes: [Node]) {
            self.threadID = threadID
            self.title = title
            self.live = live
            var seen = Set<String>()
            let nodes = Array(nodes.filter { !$0.id.isEmpty && seen.insert($0.id).inserted }
                .prefix(AgentTreeLive.maximumNodes))
            self.nodes = nodes
            self.nodeCount = max(nodeCount ?? 0, nodes.count)
            self.maxDepth = max(maxDepth ?? 0, nodes.map(\.depth).max() ?? 0)
            self.tokens = tokens
            self.cost = cost
        }

        init(from decoder: Decoder) throws {
            let values = try decoder.container(keyedBy: CodingKeys.self)
            // One node this reader cannot read leaves the others in place.
            let nodes = ((try? values.decodeIfPresent([Lossy<Node>].self, forKey: .nodes)) ?? []).compactMap(\.value)
            self.init(threadID: (try? values.decodeIfPresent(String.self, forKey: .threadID)) ?? "",
                      title: (try? values.decodeIfPresent(String.self, forKey: .title)) ?? "",
                      live: (try? values.decodeIfPresent(Bool.self, forKey: .live)) ?? false,
                      nodeCount: AgentTreeLive.count((try? values.decodeIfPresent(Double.self, forKey: .nodeCount))),
                      maxDepth: min(AgentTreeLive.deepest,
                                    AgentTreeLive.count((try? values.decodeIfPresent(Double.self, forKey: .maxDepth)))),
                      tokens: AgentTreeLive.count((try? values.decodeIfPresent(Double.self, forKey: .tokens))),
                      cost: AgentTreeLive.money((try? values.decodeIfPresent(Double.self, forKey: .cost))),
                      nodes: nodes)
        }

        /// The same tree with nothing working, for a snapshot too old to vouch for that.
        var settled: Tree {
            Tree(threadID: threadID, title: title, live: false, nodeCount: nodeCount, maxDepth: maxDepth,
                 tokens: tokens, cost: cost,
                 nodes: nodes.map { Node(id: $0.id, parentID: $0.parentID, depth: $0.depth, label: $0.label, model: $0.model,
                                         family: $0.family, status: $0.status, running: false, tokens: $0.tokens, cost: $0.cost) })
        }

        /// Whether every node has a known price, so the costs are not a minimum.
        var fullyPriced: Bool { cost != nil && nodes.allSatisfy { $0.cost != nil } }
    }

    let schema: Int
    let generatedAt: Date
    let tree: Tree?

    enum CodingKeys: String, CodingKey {
        case schema, tree
        case generatedAt = "generated_at"
    }

    init(schema: Int = AgentTreeLive.schema, generatedAt: Date, tree: Tree?) {
        self.schema = schema
        self.generatedAt = generatedAt
        self.tree = tree
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        let schema = try values.decode(Int.self, forKey: .schema)
        let text = try values.decode(String.self, forKey: .generatedAt)
        guard let date = AgentTimestamp.parse(text) else {
            throw DecodingError.dataCorruptedError(forKey: .generatedAt, in: values, debugDescription: "Unknown time")
        }
        self.init(schema: schema, generatedAt: date,
                  tree: (try? values.decodeIfPresent(Tree.self, forKey: .tree)))
    }

    private struct Lossy<Value: Decodable>: Decodable {
        let value: Value?
        init(from decoder: Decoder) throws { value = try? Value(from: decoder) }
    }
}

enum AgentTreeLive {
    static let bundleIdentifier = "io.github.whyater.agent-tree"
    static let schema = 1
    /// Agent Tree writes after every scan; a snapshot older than a day
    /// belongs to an app no longer running.
    static let freshness: TimeInterval = 86_400
    /// Agent Tree rewrites the file at least every ten minutes while it runs.
    static let liveFreshness: TimeInterval = 900
    /// Agent Tree writes the file on this Mac, so a date further ahead than
    /// rounding allows means the clock was set back since.
    static let clockSlack: TimeInterval = 2
    static let maximumSize = 1 << 20
    static let maximumNodes = 200
    static let deepest = 32

    static func url(home: URL) -> URL {
        home.appending(path: ".agent-tree/live.json", directoryHint: .notDirectory)
    }

    /// Agent Tree's app when it is on this Mac, so its card offers to open it
    /// only when a click would. Launch Services can still name a bundle that
    /// has since been replaced, so the bundle there must answer to the
    /// identifier too. The card asks once when it appears, not every redraw.
    static func application(locate: (String) -> URL? = InstalledApps.url(for:),
                             identify: (URL) -> String? = { Bundle(url: $0)?.bundleIdentifier }) -> URL? {
        guard let url = locate(bundleIdentifier), identify(url) == bundleIdentifier else { return nil }
        return url
    }

    /// The file's snapshot; nil for a missing, oversized or unknown file, or
    /// anything other than a regular file, such as a symbolic link. The open
    /// itself refuses a link, so one swapped in after a check is refused too,
    /// and a file still growing is read only up to the limit.
    static func load(from url: URL) -> AgentTreeSnapshot? {
        let descriptor = open(url.path, O_RDONLY | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC)
        guard descriptor >= 0 else { return nil }
        let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
        var status = stat()
        guard fstat(descriptor, &status) == 0, status.st_mode & S_IFMT == S_IFREG,
              let data = readAll(upTo: maximumSize + 1, read: { count in
                  // FileHandle answers nil at the end of the file and throws on a failed read.
                  do { return try handle.read(upToCount: count) ?? Data() } catch { return nil }
              }) else { return nil }
        return decode(data)
    }

    /// Reads until the end or `limit` bytes, as one read may return less than
    /// asked. Nil when a read fails.
    static func readAll(upTo limit: Int, read: (Int) -> Data?) -> Data? {
        var data = Data()
        while data.count < limit {
            guard let chunk = read(limit - data.count) else { return nil }
            if chunk.isEmpty { break }
            data.append(chunk)
        }
        return data
    }

    static func decode(_ data: Data) -> AgentTreeSnapshot? {
        guard data.count <= maximumSize,
              let snapshot = try? JSONDecoder().decode(AgentTreeSnapshot.self, from: data),
              snapshot.schema == schema else { return nil }
        return snapshot
    }

    /// The tree worth a card: from a recent snapshot, with at least one node.
    /// Past `liveFreshness` nothing in it is shown as working any more, so a
    /// tree left behind when Agent Tree quits reads as the last thread. A file
    /// dated more than `clockSlack` ahead of the clock (the clock was set
    /// back) can't vouch for work either.
    static func current(_ snapshot: AgentTreeSnapshot?, now: Date) -> AgentTreeSnapshot.Tree? {
        let age = snapshot.map { now.timeIntervalSince($0.generatedAt) } ?? .infinity
        guard let snapshot, abs(age) < freshness, let tree = snapshot.tree, !tree.nodes.isEmpty else { return nil }
        return (-clockSlack..<liveFreshness).contains(age) ? tree : tree.settled
    }

    /// Up to `limit` nodes in their own order, and how many were left out.
    /// Working nodes come first, with every node above them so the branch
    /// still reads; the rest fill in under nodes already shown, from the
    /// latest while some work and from the top once all have finished. A
    /// branch longer than the room keeps its top and the levels just above
    /// the working node, so the work itself is never the part left out.
    static func rows(_ nodes: [AgentTreeSnapshot.Node], limit: Int) -> (rows: [AgentTreeSnapshot.Node], hidden: Int) {
        guard nodes.count > limit else { return (nodes, 0) }
        guard limit > 0 else { return ([], nodes.count) }
        let index = Dictionary(nodes.enumerated().map { ($1.id, $0) }, uniquingKeysWith: { first, _ in first })
        var kept: [Int] = []
        var chosen = Set<Int>()
        for (position, node) in nodes.enumerated() where node.running {
            // The branch from the top down, so a deep node never pushes out its parents.
            var branch = [position]
            var parent = node.parentID
            while let id = parent, let above = index[id], !branch.contains(above) {
                branch.append(above)
                parent = nodes[above].parentID
            }
            var missing = branch.reversed().filter { !chosen.contains($0) }
            let room = limit - kept.count
            if missing.count > room {
                // The top only when it is new and leaves room for the working node.
                let top = room > 1 && missing.first == branch.last ? [missing[0]] : []
                missing = top + missing.suffix(room - top.count)
            }
            for position in missing {
                chosen.insert(position)
                kept.append(position)
            }
        }
        let rest = nodes.indices.filter { !chosen.contains($0) }
        let order = kept.isEmpty ? rest : Array(rest.reversed())
        // Only under a node already shown, so no row hangs from nothing;
        // each pass can open the way for the children of the last.
        var grew = true
        while grew, kept.count < limit {
            grew = false
            for position in order where kept.count < limit && !chosen.contains(position) {
                let parent = nodes[position].parentID.flatMap { index[$0] }
                guard parent.map(chosen.contains) ?? true else { continue }
                chosen.insert(position)
                kept.append(position)
                grew = true
            }
        }
        return (kept.sorted().map { nodes[$0] }, nodes.count - kept.count)
    }

    /// Where each row shown sits: one level under the nearest node above it
    /// that is shown, and whether levels between the two were left out. A
    /// node with nothing above it shown keeps its own depth.
    static func levels(_ rows: [AgentTreeSnapshot.Node], in nodes: [AgentTreeSnapshot.Node]) -> [(depth: Int, gap: Bool)] {
        let parents = Dictionary(nodes.map { ($0.id, $0.parentID) }, uniquingKeysWith: { first, _ in first })
        var placed: [String: Int] = [:]
        return rows.map { node in
            var parent = node.parentID
            var steps = 0
            var seen: Set<String> = [node.id]
            while let id = parent, placed[id] == nil, seen.insert(id).inserted, let above = parents[id] {
                parent = above
                steps += 1
            }
            let level = parent.flatMap { placed[$0] }.map { (depth: $0 + 1, gap: steps > 0) } ?? (depth: node.depth, gap: false)
            placed[node.id] = level.depth
            return level
        }
    }

    /// The lines a row draws to join its node to the rest, from the depths
    /// of the rows shown: a column for each level above the node.
    struct Branch: Equatable {
        /// Columns the line of an earlier level crosses on its way down.
        var through: [Bool]
        /// Another node at the same level follows, so the elbow continues down.
        var more: Bool
        /// The next row hangs from this one.
        var children: Bool
        /// Levels between this node and the one it hangs from are left out.
        var gap = false
    }

    static func branches(_ depths: [Int], gaps: [Bool] = []) -> [Branch] {
        depths.indices.map { row in
            let depth = depths[row]
            // A column's line goes on while a later row returns to its level
            // before anything shallower.
            func continues(_ level: Int) -> Bool {
                depths[(row + 1)...].first { $0 <= level } == level
            }
            return Branch(through: (0..<max(0, depth - 1)).map { continues($0 + 1) },
                          more: depth > 0 && continues(depth),
                          children: row + 1 < depths.count && depths[row + 1] > depth,
                          gap: depth > 0 && gaps.indices.contains(row) && gaps[row])
        }
    }

    static func count(_ value: Double?) -> Int {
        guard let value, value.isFinite, value > 0 else { return 0 }
        return Int(min(value, Double(Int.max / 2)))
    }

    static func money(_ value: Double?) -> Double? {
        guard let value, value.isFinite, value >= 0 else { return nil }
        return value
    }
}
