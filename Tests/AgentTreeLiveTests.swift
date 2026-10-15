// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// Agent Tree's snapshot: only the schema it knows, only while recent, and a
/// short tree that keeps working agents and the branch above them.
enum AgentTreeLiveTests {
    static func run(_ suite: TestSuite) {
        decoding(suite)
        freshness(suite)
        truncation(suite)
        branches(suite)
        cards(suite)
        application(suite)
        boundedRead(suite)
    }

    private static func node(_ id: String, parent: String? = nil, depth: Int, running: Bool = false) -> String {
        let parentText = parent.map { "\"\($0)\"" } ?? "null"
        return """
        {"id":"\(id)","parent_id":\(parentText),"depth":\(depth),"label":" \(id) ","model":"claude-opus-5-5",\
        "family":"anthropic","status":"\(running ? "running" : "done")","running":\(running),\
        "tokens":1200,"cost":0.5}
        """
    }

    private static func file(schema: Int = 1, generated: String = "2026-10-13T17:44:34.000Z", nodes: [String]) -> Data {
        Data("""
        {"schema":\(schema),"generated_at":"\(generated)","totals":{},"flags":{},"running":[],\
        "tree":{"thread_id":"t1","title":"Build","project_name":"app","live":true,"node_count":40,\
        "max_depth":2,"tokens":5000,"cost":null,"nodes":[\(nodes.joined(separator: ","))]}}
        """.utf8)
    }

    private static func decoding(_ suite: TestSuite) {
        let snapshot = AgentTreeLive.decode(file(nodes: [node("root", depth: 0), node("child", parent: "root", depth: 1)]))
        let tree = snapshot?.tree
        suite.expect(tree?.nodes.map(\.id) == ["root", "child"] && tree?.nodes[1].parentID == "root"
                        && tree?.nodes[0].label == "root" && tree?.nodeCount == 40 && tree?.live == true
                        && tree?.cost == nil && tree?.fullyPriced == false,
                     "a snapshot reads its tree in Agent Tree's order, with an unknown cost left unknown")
        suite.expect(AgentTreeLive.decode(file(schema: 2, nodes: [node("root", depth: 0)])) == nil,
                     "a schema this reader does not know is left out")
        suite.expect(AgentTreeLive.decode(Data("not json".utf8)) == nil
                        && AgentTreeLive.decode(file(generated: "yesterday", nodes: [])) == nil,
                     "an unreadable file or time is left out")
        let odd = AgentTreeLive.decode(file(nodes: [node("root", depth: 0), "{\"label\":\"no id\"}", "7",
                                                    #"{"id":"deep","parent_id":"root","depth":-3,"tokens":-5,"cost":-1,"surprise":[1]}"#]))
        suite.expect(odd?.tree?.nodes.map(\.id) == ["root", "deep"] && odd?.tree?.nodes[1].depth == 0
                        && odd?.tree?.nodes[1].tokens == 0 && odd?.tree?.nodes[1].cost == nil,
                     "a node it cannot read is skipped and odd numbers are kept in range")
        var large = file(nodes: [node("root", depth: 0)])
        large.append(Data(repeating: 0x20, count: AgentTreeLive.maximumSize))
        suite.expect(AgentTreeLive.decode(large) == nil, "a file over the size limit is not decoded")

        let directory = FileManager.default.temporaryDirectory
            .appending(path: "vorss-agent-tree-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = AgentTreeLive.url(home: directory)
        suite.expect(AgentTreeLive.load(from: url) == nil, "a missing file reads as no snapshot")
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? file(nodes: [node("root", depth: 0)]).write(to: url)
        suite.expect(AgentTreeLive.load(from: url)?.tree?.nodes.count == 1
                        && url.path.hasSuffix("/.agent-tree/live.json"),
                     "the snapshot is read from Agent Tree's folder")
        var grown = file(nodes: [node("root", depth: 0)])
        grown.append(Data(repeating: 0x20, count: AgentTreeLive.maximumSize))
        try? grown.write(to: url)
        suite.expect(AgentTreeLive.load(from: url) == nil, "a file over the size limit is not read")
        let elsewhere = directory.appending(path: "elsewhere.json", directoryHint: .notDirectory)
        try? file(nodes: [node("root", depth: 0)]).write(to: elsewhere)
        try? FileManager.default.removeItem(at: url)
        try? FileManager.default.createSymbolicLink(at: url, withDestinationURL: elsewhere)
        suite.expect(AgentTreeLive.decode((try? Data(contentsOf: url)) ?? Data()) != nil
                        && AgentTreeLive.load(from: url) == nil,
                     "a symbolic link in place of the file is not followed")
        try? FileManager.default.removeItem(at: url)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: false)
        suite.expect(AgentTreeLive.load(from: url) == nil, "a folder in place of the file reads as no snapshot")

        let repeated = AgentTreeLive.decode(file(nodes: [node("root", depth: 0), node("", parent: "root", depth: 1),
                                                         node("a", parent: "root", depth: 1), node("a", parent: "a", depth: 2),
                                                         node("root", parent: "a", depth: 2), node("b", parent: "a", depth: 2)]))
        suite.expect(repeated?.tree?.nodes.map(\.id) == ["root", "a", "b"]
                        && repeated?.tree?.nodes[1].parentID == "root",
                     "a node without an id, or repeating an earlier one, is left out and the first one kept")
        typealias Node = AgentTreeSnapshot.Node
        let looped = AgentTreeSnapshot.Tree(nodes: [Node(id: "x", parentID: "y", depth: 1), Node(id: "y", parentID: "x", depth: 1),
                                                    Node(id: "z", parentID: "z", depth: 1, running: true), Node(id: "", depth: 0),
                                                    Node(id: "x", depth: 0)])
        let loopedRows = AgentTreeLive.rows(looped.nodes, limit: 2)
        suite.expect(looped.nodes.map(\.id) == ["x", "y", "z"]
                        && loopedRows.rows.map(\.id) == ["z"] && loopedRows.hidden == 2
                        && AgentTreeLive.levels(looped.nodes, in: looped.nodes).count == 3,
                     "nodes that name each other or themselves as parent still lay out")
    }

    private static func freshness(_ suite: TestSuite) {
        let generated = Date(timeIntervalSince1970: 1_800_000_000)
        let tree = AgentTreeSnapshot.Tree(nodes: [AgentTreeSnapshot.Node(id: "root")])
        let snapshot = AgentTreeSnapshot(generatedAt: generated, tree: tree)
        suite.expect(AgentTreeLive.current(snapshot, now: generated.addingTimeInterval(3600)) == tree
                        && AgentTreeLive.current(snapshot, now: generated.addingTimeInterval(86_400)) == nil,
                     "a snapshot a day old no longer shows a card")
        suite.expect(AgentTreeLive.current(AgentTreeSnapshot(generatedAt: generated, tree: nil), now: generated) == nil
                        && AgentTreeLive.current(AgentTreeSnapshot(generatedAt: generated, tree: .init(nodes: [])),
                                                 now: generated) == nil,
                     "a snapshot without agents shows no card")
        let live = AgentTreeSnapshot.Tree(live: true, nodes: [AgentTreeSnapshot.Node(id: "root", running: true)])
        let working = AgentTreeSnapshot(generatedAt: generated, tree: live)
        suite.expect(AgentTreeLive.current(working, now: generated.addingTimeInterval(60)) == live
                        && AgentTreeLive.current(working, now: generated) == live
                        && AgentTreeLive.current(working, now: generated.addingTimeInterval(-1)) == live,
                     "a fresh snapshot, even one just written, keeps its working agents")
        let stale = AgentTreeLive.current(working, now: generated.addingTimeInterval(600 + AgentTreeLive.liveFreshness))
        suite.expect(stale?.live == false && stale?.nodes.contains(where: \.running) == false,
                     "a snapshot too old to vouch for work shows its tree as finished")
        let ahead = AgentTreeLive.current(working, now: generated.addingTimeInterval(-7200))
        suite.expect(ahead != nil && ahead?.live == false && ahead?.nodes.contains(where: \.running) == false,
                     "a file dated ahead of the clock still shows its tree, but nothing as working")
        let soon = AgentTreeLive.current(working, now: generated.addingTimeInterval(-30))
        suite.expect(soon != nil && soon?.live == false && soon?.nodes.contains(where: \.running) == false,
                     "a file written on this Mac but dated seconds ahead shows nothing as working")
    }

    private static func truncation(_ suite: TestSuite) {
        typealias Node = AgentTreeSnapshot.Node
        let nodes = [Node(id: "root", depth: 0), Node(id: "a", parentID: "root", depth: 1),
                     Node(id: "a1", parentID: "a", depth: 2), Node(id: "a2", parentID: "a", depth: 2),
                     Node(id: "b", parentID: "root", depth: 1), Node(id: "b1", parentID: "b", depth: 2),
                     Node(id: "b1x", parentID: "b1", depth: 3, running: true), Node(id: "c", parentID: "root", depth: 1)]
        let short = AgentTreeLive.rows(Array(nodes.prefix(3)), limit: 5)
        suite.expect(short.rows.map(\.id) == ["root", "a", "a1"] && short.hidden == 0, "a tree that fits is shown whole")
        let working = AgentTreeLive.rows(nodes, limit: 5)
        suite.expect(working.rows.map(\.id) == ["root", "b", "b1", "b1x", "c"] && working.hidden == 3,
                     "a working agent keeps the branch above it, and the latest nodes fill the rest")
        suite.expect(AgentTreeLive.rows(nodes, limit: 6).rows.map(\.id) == ["root", "a", "b", "b1", "b1x", "c"],
                     "a node fills in only under one already shown, never hanging from a hidden parent")
        let tight = AgentTreeLive.rows(nodes, limit: 2)
        suite.expect(tight.rows.map(\.id) == ["root", "b1x"] && tight.hidden == 6,
                     "a branch longer than the room keeps its top and the working node")
        suite.expect(AgentTreeLive.rows(nodes, limit: 1).rows.map(\.id) == ["b1x"],
                     "with room for one row the working node is the one shown")
        // root > L1 > ... > L6, with only the deepest at work.
        let chain = (0...6).map { Node(id: "L\($0)", parentID: $0 == 0 ? nil : "L\($0 - 1)", depth: $0, running: $0 == 6) }
        let deep = AgentTreeLive.rows(chain, limit: 5)
        suite.expect(deep.rows.map(\.id) == ["L0", "L3", "L4", "L5", "L6"] && deep.hidden == 2,
                     "a working node deeper than the room shows under its root, with the levels between left out")
        let levels = AgentTreeLive.levels(deep.rows, in: chain)
        suite.expect(levels.map(\.depth) == [0, 1, 2, 3, 4] && levels.map(\.gap) == [false, true, false, false, false],
                     "rows past left-out levels sit one under the nearest shown, marked as a gap")
        let whole = AgentTreeLive.levels(Array(nodes.prefix(4)), in: nodes)
        suite.expect(whole.map(\.depth) == [0, 1, 2, 2] && !whole.contains(where: \.gap),
                     "a tree shown without gaps keeps its own depths")
        let finished = nodes.map { Node(id: $0.id, parentID: $0.parentID, depth: $0.depth) }
        suite.expect(AgentTreeLive.rows(finished, limit: 4).rows.map(\.id) == ["root", "a", "a1", "a2"],
                     "once all have finished the tree is shown from the top")
        suite.expect(AgentTreeLive.rows(nodes, limit: 0).rows.isEmpty, "no room shows no rows")
    }

    private static func branches(_ suite: TestSuite) {
        // root, a, a1, a2, b, b1
        let lines = AgentTreeLive.branches([0, 1, 2, 2, 1, 2])
        suite.expect(lines[0] == .init(through: [], more: false, children: true)
                        && lines[1] == .init(through: [], more: true, children: true)
                        && lines[2] == .init(through: [true], more: true, children: false)
                        && lines[3] == .init(through: [true], more: false, children: false)
                        && lines[4] == .init(through: [], more: false, children: true)
                        && lines[5] == .init(through: [false], more: false, children: false),
                     "each row joins its parent and carries on the lines of later siblings")
        let gapped = AgentTreeLive.branches([0, 1, 2], gaps: [false, true, false])
        suite.expect(gapped[1] == .init(through: [], more: false, children: true, gap: true) && !gapped[2].gap,
                     "a row past left-out levels draws its joining line as a gap")
    }

    private static func cards(_ suite: TestSuite) {
        let tree = NotchAgentTile(card: .agentTree, provider: nil)
        let spend = NotchAgentTile(card: .spend, provider: nil)
        suite.expect(NotchAgentSupport.tiles(cards: [.agentTree, .spend], providers: [.claude]) == [spend]
                        && NotchAgentSupport.tiles(cards: [.agentTree, .spend], providers: [.claude], agentTree: true)
                        == [tree, spend],
                     "the tree card shows only while Agent Tree keeps a recent snapshot")
        suite.expect(NotchAgentSupport.tiles(cards: [.agentTree, .spend], providers: [], agentTree: true) == [tree]
                        && NotchAgentSupport.tiles(cards: [.agentTree, .spend], providers: []).isEmpty,
                     "with no agent logs the tree card still shows, and nothing else does")
        typealias Node = AgentTreeSnapshot.Node
        let one = AgentTreeSnapshot.Tree(nodes: [Node(id: "root")])
        let big = AgentTreeSnapshot.Tree(nodeCount: 40, nodes: (0..<8).map { Node(id: "n\($0)", parentID: $0 == 0 ? nil : "n0", depth: $0 == 0 ? 0 : 1) })
        let row = NotchAgentSupport.treeRowHeight
        suite.expect(NotchAgentSupport.rows([spend, tree], width: 424) == [[spend], [tree]]
                        && NotchAgentSupport.contentHeight([[tree]], tree: big) == NotchAgentSupport.treeHeight(big),
                     "the tree takes the whole row and its own height")
        suite.expect(NotchAgentSupport.treeHeight(big) - NotchAgentSupport.treeHeight(one)
                        == row * CGFloat(NotchAgentSupport.treeRows - 1) + NotchAgentSupport.treeSpacing + NotchAgentSupport.treeLineHeight
                        && NotchAgentSupport.treeHeight(big) == 142 && NotchAgentSupport.treeShown(big).hidden == 35,
                     "a tree card is as tall as its rows, with a line only when agents are left out")
        suite.expect(FeatureStrings.notchAgents(.enUS).agentTreeSummaryOne == "1 agent",
                     "a single agent is not counted as agents")
        suite.expect(NotchAgentCard.allCases.firstIndex(of: .agentTree) == NotchAgentCard.allCases.firstIndex(of: .live).map { $0 + 1 },
                     "by default the tree follows the card about work in progress")
    }

    private static func application(_ suite: TestSuite) {
        let app = URL(fileURLWithPath: "/Applications/Agent Tree.app")
        var asked: [String] = []
        let found = AgentTreeLive.application(locate: { asked.append($0); return app },
                                              identify: { _ in AgentTreeLive.bundleIdentifier })
        suite.expect(found == app && asked == [AgentTreeLive.bundleIdentifier],
                     "an installed Agent Tree is found by its bundle identifier, asked once")
        suite.expect(AgentTreeLive.application(locate: { _ in nil }, identify: { _ in AgentTreeLive.bundleIdentifier }) == nil,
                     "without Agent Tree on this Mac the card has nothing to open")
        suite.expect(AgentTreeLive.application(locate: { _ in app }, identify: { _ in "com.example.other" }) == nil
                        && AgentTreeLive.application(locate: { _ in app }, identify: { _ in nil }) == nil,
                     "a bundle that no longer answers to Agent Tree's identifier is not opened")
    }

    private static func boundedRead(_ suite: TestSuite) {
        let file = Data("0123456789".utf8)
        func reader(chunk: Int) -> (Int) -> Data? {
            var offset = 0
            return { count in
                let end = min(file.count, offset + min(count, chunk))
                defer { offset = end }
                return file.subdata(in: offset..<end)
            }
        }
        suite.expect(AgentTreeLive.readAll(upTo: 100, read: reader(chunk: 3)) == file,
                     "a file that arrives in short reads is read to its end")
        suite.expect(AgentTreeLive.readAll(upTo: 4, read: reader(chunk: 3)) == file.prefix(4),
                     "reading stops at the limit")
        suite.expect(AgentTreeLive.readAll(upTo: 100, read: { _ in nil }) == nil,
                     "a failed read gives nothing")
    }
}
