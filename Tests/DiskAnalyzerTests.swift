// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Darwin
import Foundation

enum DiskAnalyzerTests {
    static func run(_ suite: TestSuite) {
        folding(suite)
        settling(suite)
        editing(suite)
        geometry(suite)
        marking(suite)
        rebuildable(suite)
        scope(suite)
        scanning(suite)
        strings(suite)
    }

    private static func file(_ name: String, _ size: Int64) -> DiskNode {
        DiskNode(name: name, kind: .file, size: size, fileCount: 1)
    }

    /// A folder as the scanner leaves it before settling: holding only its
    /// own files' totals.
    private static func folder(_ name: String, _ children: [DiskNode]) -> DiskNode {
        let files = children.filter { $0.kind == .file }
        let node = DiskNode(name: name, kind: .directory, size: files.reduce(0) { $0 + $1.size },
                            fileCount: files.count)
        node.children = children
        for child in children { child.parent = node }
        return node
    }

    /// Settles a hand-built tree from the leaves up, as the scanner does.
    private static func settleAll(_ node: DiskNode, collapseBelow: Int64 = 0) {
        for child in node.children where child.kind == .directory { settleAll(child, collapseBelow: collapseBelow) }
        DiskAnalyzerSupport.settle(node, collapseBelow: collapseBelow)
    }

    private static func folding(_ suite: TestSuite) {
        let files = (1...10).map { file("f\($0)", Int64($0) * 100) }
        let folded = DiskAnalyzerSupport.foldFiles(files.shuffled(), keep: 3)
        suite.expect(folded.map(\.name) == ["f10", "f9", "f8", ""],
                     "the largest files stay listed, largest first, and the rest fold into one entry")
        suite.expect(folded.last?.kind == .smallFiles && folded.last?.fileCount == 7
                     && folded.last?.size == (1...7).reduce(0) { $0 + Int64($1) * 100 },
                     "the folded entry carries the count and bytes of every file it replaces")
        suite.expect(folded.reduce(0) { $0 + $1.size } == files.reduce(0) { $0 + $1.size },
                     "folding never loses bytes")
        let thresholded = DiskAnalyzerSupport.foldFiles(files, keep: 10, minimumSize: 801)
        suite.expect(thresholded.map(\.name) == ["f10", "f9", ""],
                     "files below the minimum size fold even when the listed count has room")
        let lone = DiskAnalyzerSupport.foldFiles([file("a", 900), file("b", 10)], keep: 1)
        suite.expect(lone.map(\.name) == ["a", "b"] && !lone.contains { $0.kind == .smallFiles },
                     "a single leftover stays listed by name instead of becoming a one-file fold")
    }

    private static func settling(_ suite: TestSuite) {
        let deep = folder("deep", [file("movie.mov", 5000)])
        let tiny = folder("tiny", [file("note.txt", 40), file("todo.txt", 20)])
        let root = folder("root", [tiny, deep, file("a.zip", 700)])
        settleAll(root, collapseBelow: 100)
        suite.expect(root.size == 5760 && root.fileCount == 4,
                     "a folder's size and file count include every subfolder once settled")
        suite.expect(root.children.map(\.name) == ["deep", "a.zip", "tiny"],
                     "children are sorted from largest to smallest")
        suite.expect(tiny.collapsed && tiny.children.isEmpty && tiny.size == 60 && !tiny.canDrillDown,
                     "a folder under the collapse size keeps its total but drops its contents")
        suite.expect(!deep.collapsed && deep.canDrillDown, "a large enough folder keeps its contents")
        suite.expect(deep.children.first?.path == "root/deep/movie.mov" && root.children.first === deep,
                     "paths are derived from the chain of parents")

        let hidden = DiskNode(name: "", kind: .hidden, size: 10)
        let named = file("same", 10)
        suite.expect(DiskAnalyzerSupport.ordered(named, hidden) && !DiskAnalyzerSupport.ordered(hidden, named),
                     "named items come before hidden space of the same size")
    }

    private static func editing(_ suite: TestSuite) {
        let victim = file("big.iso", 4000)
        let inner = folder("Downloads", [victim, file("small.pdf", 100)])
        let other = folder("Music", [file("song.mp3", 3000)])
        let root = folder("home", [inner, other])
        settleAll(root)
        suite.expect(root.children.first === inner, "the larger folder leads before the removal")
        suite.expect(DiskAnalyzerSupport.detach(victim), "an attached item can be detached")
        suite.expect(inner.size == 100 && root.size == 3100 && inner.fileCount == 1 && root.fileCount == 2,
                     "removing an item takes its bytes and files off every ancestor")
        suite.expect(root.children.first === other, "ancestors re-sort after a removal")
        suite.expect(!DiskAnalyzerSupport.detach(victim), "a detached item cannot be detached twice")

        let fresh = folder("Music", [file("song.mp3", 3000), file("album.flac", 2000)])
        settleAll(fresh)
        DiskAnalyzerSupport.replace(other, with: fresh)
        suite.expect(root.size == 5100 && root.fileCount == 3 && fresh.parent === root && root.children.first === fresh,
                     "a rescanned folder replaces the old one and updates every ancestor")

        let lineage = fresh.children[0].lineage
        suite.expect(lineage.first === root && lineage.last === fresh.children[0] && root.isAncestor(of: lineage[2]),
                     "lineage runs from the root to the item")

        suite.expect(DiskAnalyzerSupport.hiddenBytes(volumeUsed: 500_000_000_000, scanned: 430_000_000_000)
                     == 70_000_000_000, "unaccounted volume space becomes hidden space")
        suite.expect(DiskAnalyzerSupport.hiddenBytes(volumeUsed: 500_000_000_000, scanned: 499_000_000_000) == 0,
                     "rounding-sized differences do not become a slice")
        suite.expect(DiskAnalyzerSupport.hiddenBytes(volumeUsed: 100, scanned: 200) == 0,
                     "a scan larger than the volume's report never yields negative space")

        let big = file("big", 900)
        let tree = folder("t", [folder("a", [big, file("x", 5)]), folder("b", [file("mid", 400), file("y", 1)]),
                                file("top", 600)])
        settleAll(tree)
        let largest = DiskAnalyzerSupport.largestFiles(in: tree, limit: 3)
        suite.expect(largest.map(\.name) == ["big", "top", "mid"],
                     "the largest-files list searches the whole subtree, biggest first")
        suite.expect(DiskAnalyzerSupport.largestFiles(in: tree, limit: 0).isEmpty, "a zero limit lists nothing")
    }

    private static func marking(_ suite: TestSuite) {
        let movie = file("movie.mov", 5000)
        let note = file("note.txt", 100)
        let inner = folder("Projects", [movie, note])
        let other = file("other.zip", 900)
        let root = folder("home", [inner, other])
        settleAll(root)

        DiskAnalyzerSupport.detach(movie)
        suite.expect(!DiskAnalyzerSupport.isAttached(movie, to: root) && root.size == 1000,
                     "a trashed item leaves the map")
        DiskAnalyzerSupport.attach(movie, to: inner)
        suite.expect(DiskAnalyzerSupport.isAttached(movie, to: root) && root.size == 6000
                     && inner.size == 5100 && root.fileCount == 3 && inner.children.first === movie
                     && root.children.first === inner,
                     "undoing a removal puts the bytes back on every ancestor in size order")

        var marked = DiskAnalyzerSupport.marking(note, in: [])
        marked = DiskAnalyzerSupport.marking(other, in: marked)
        suite.expect(marked.count == 2, "separate items can be marked together")
        marked = DiskAnalyzerSupport.marking(inner, in: marked)
        suite.expect(marked.count == 2 && marked.contains { $0 === inner } && !marked.contains { $0 === note },
                     "marking a folder absorbs the marks inside it, so no byte counts twice")
        suite.expect(DiskAnalyzerSupport.marking(movie, in: marked).count == 2,
                     "an item inside a marked folder is already covered")
        suite.expect(DiskAnalyzerSupport.marking(other, in: marked).count == 2,
                     "marking an item twice keeps one mark")
    }

    private static func rebuildable(_ suite: TestSuite) {
        typealias R = DiskAnalyzerSupport.Rebuildable
        suite.expect(R.match(name: "node_modules", parentName: "app") == .nodeModules
                     && R.match(name: ".next", parentName: "site") == .webBuildCache
                     && R.match(name: "__pycache__", parentName: "pkg") == .pythonCache,
                     "well-known tool folders are recognised by name")
        suite.expect(R.match(name: "DerivedData", parentName: "Xcode") == .derivedData
                     && R.match(name: "DerivedData", parentName: "Backups") == nil
                     && R.match(name: "iOS DeviceSupport", parentName: "Xcode") == .deviceSupport
                     && R.match(name: "iOS DeviceSupport", parentName: "Docs") == nil,
                     "names that could mean anything only count in their usual parent")
        suite.expect(R.match(name: "build", parentName: "app") == nil && R.match(name: "Documents", parentName: nil) == nil,
                     "ambiguous or personal folder names are never suggested")

        let big = Int64(4 << 20)
        let nested = folder("node_modules", [file("x.js", big)])
        let outer = folder("node_modules", [folder("dep", [nested]), file("y.js", big)])
        let cache = folder(".dart_tool", [file("z", big * 3)])
        let tiny = folder("__pycache__", [file("c.pyc", 10)])
        let project = folder("app", [outer, cache, tiny, file("main.dart", big)])
        let root = folder("code", [project])
        settleAll(root)
        let found = DiskAnalyzerSupport.rebuildableFolders(in: root)
        suite.expect(found.map(\.node.name) == [".dart_tool", "node_modules"] && found.first?.kind == .dartTool,
                     "suggestions list the outermost matches, largest first")
        suite.expect(!found.contains { $0.node === nested } && !found.contains { $0.node === tiny },
                     "nested matches and folders under the minimum size are left out")
    }

    private static func geometry(_ suite: TestSuite) {
        let a = folder("a", [file("a1", 300), file("a2", 100)])
        let root = folder("r", [a, file("b", 400), file("crumb", 1)])
        settleAll(root)
        let arcs = DiskAnalyzerSupport.sunburst(focus: root, maxDepth: 2, minimumSpan: 0.01)
        let first = arcs.filter { $0.depth == 1 }
        guard first.count == 2, arcs.filter({ $0.depth == 2 }).count == 2 else {
            suite.expect(false, "the layout has two segments in each ring")
            return
        }
        suite.expect(first[0].start == 0, "the first ring starts at twelve o’clock")
        suite.expect(abs(first[0].end - 400.0 / 801.0) < 1e-9 && abs(first[1].start - first[0].end) < 1e-9,
                     "segments are proportional to size and touch without gaps")
        suite.expect(!arcs.contains { $0.node.name == "crumb" },
                     "segments thinner than the minimum span are left out")
        let second = arcs.filter { $0.depth == 2 }
        suite.expect(second.map(\.node.name) == ["a1", "a2"]
                     && abs(second[1].end - first[0].end) < 1e-9,
                     "a folder's contents fill exactly the folder's own slice")
        suite.expect(DiskAnalyzerSupport.sunburst(focus: root, maxDepth: 1, minimumSpan: 0).allSatisfy { $0.depth == 1 },
                     "the layout stops at the requested number of rings")
        suite.expect(DiskAnalyzerSupport.arc(at: 0.2, depth: 1, in: arcs)?.node === a
                     && DiskAnalyzerSupport.arc(at: 0.7, depth: 1, in: arcs)?.node.name == "b"
                     && DiskAnalyzerSupport.arc(at: 0.2, depth: 3, in: arcs) == nil,
                     "hit testing finds the segment under an angle and ring")

        let window = 0.25...0.5
        let start = DiskAnalyzerSupport.zoomed(start: 0.25, end: 0.5, window: window, progress: 0)
        let end = DiskAnalyzerSupport.zoomed(start: 0.25, end: 0.5, window: window, progress: 1)
        suite.expect(start.map { $0.start == 0.25 && $0.end == 0.5 } == true,
                     "a zoom starts from the unchanged layout")
        suite.expect(end.map { $0.start == 0 && $0.end == 1 } == true,
                     "a zoom ends with the target filling the whole turn")
        suite.expect(DiskAnalyzerSupport.zoomed(start: 0.6, end: 0.9, window: window, progress: 1) == nil,
                     "segments outside the zoomed slice leave the chart")
    }

    private static func scope(_ suite: TestSuite) {
        let home = "/Users/someone"
        suite.expect(DiskAnalyzerSupport.isTrashable(path: "/Users/someone/Downloads/big.iso", home: home)
                     && DiskAnalyzerSupport.isTrashable(path: "/Users/someone/Library/Caches/x", home: home),
                     "items inside the home folder can be moved to the Trash")
        suite.expect(!DiskAnalyzerSupport.isTrashable(path: "/Users/someone", home: home)
                     && !DiskAnalyzerSupport.isTrashable(path: "/Users/someone/Library", home: home)
                     && !DiskAnalyzerSupport.isTrashable(path: "/Users/someone/../other/file", home: home)
                     && !DiskAnalyzerSupport.isTrashable(path: "/Users/someoneelse/file", home: home),
                     "the home folder, its Library, escapes and look-alike homes stay protected")
        suite.expect(DiskAnalyzerSupport.isTrashable(path: "/Applications/Big.app", home: home)
                     && !DiskAnalyzerSupport.isTrashable(path: "/Applications", home: home)
                     && DiskAnalyzerSupport.isTrashable(path: "/Volumes/Backup/old", home: home)
                     && !DiskAnalyzerSupport.isTrashable(path: "/Volumes/Backup", home: home),
                     "apps and items on other volumes can go, their containers cannot")
        suite.expect(!DiskAnalyzerSupport.isTrashable(path: "/System/Library/Fonts", home: home)
                     && !DiskAnalyzerSupport.isTrashable(path: "/usr/local/bin/tool", home: home)
                     && !DiskAnalyzerSupport.isTrashable(path: "relative/path", home: home),
                     "system paths and relative paths are never offered")
        suite.expect(DiskAnalyzerSupport.containerPaths(home: home)
                     == ["/Users/someone/Library/Containers", "/Users/someone/Library/Group Containers"],
                     "other apps' containers are the folders skipped without Full Disk Access")
        suite.expect(DiskAnalyzerSupport.startupDiskSkippedPaths.contains("/System/Volumes")
                     && DiskAnalyzerSupport.startupDiskSkippedPaths.contains("/Volumes"),
                     "a startup disk scan leaves out the support volumes and other mounted volumes")
    }

    private static func scanning(_ suite: TestSuite) {
        let fm = FileManager.default
        let base = fm.temporaryDirectory.appendingPathComponent("vorssaint-disk-analyzer-\(UUID().uuidString)")
        defer { try? fm.removeItem(at: base) }
        func write(_ relative: String, bytes: Int) {
            let url = base.appendingPathComponent(relative)
            try? fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            fm.createFile(atPath: url.path, contents: Data(repeating: 7, count: bytes))
        }
        write("a/big.bin", bytes: 3 << 20)
        write("a/b/c/deep.bin", bytes: 1 << 20)
        write("small/one.txt", bytes: 10)
        write("skip/hidden.bin", bytes: 2 << 20)
        try? fm.createSymbolicLink(atPath: base.appendingPathComponent("loop").path, withDestinationPath: base.path)
        try? fm.linkItem(at: base.appendingPathComponent("a/big.bin"), to: base.appendingPathComponent("hardlink.bin"))

        var options = DiskAnalyzerScanner.Options()
        options.skippedPaths = [base.appendingPathComponent("skip").path]
        options.collapseBelow = 64 << 10
        options.minimumListedFile = 0
        let scanner = DiskAnalyzerScanner(options: options)
        guard let root = scanner.scan(path: base.path, displayName: "test") else {
            suite.expect(false, "the scanner reads a temporary folder")
            return
        }
        func child(_ node: DiskNode?, _ name: String) -> DiskNode? { node?.children.first { $0.name == name } }
        let a = child(root, "a")
        let big = child(a, "big.bin")
        // The hard-linked twin may be read first and carry the bytes instead.
        let linked = max(big?.size ?? 0, child(root, "hardlink.bin")?.size ?? 0)
        suite.expect(linked >= 3 << 20 && child(child(child(a, "b"), "c"), "deep.bin").map { $0.size >= 1 << 20 } == true,
                     "files are found at every depth with their allocated size")
        suite.expect(root.size == (a?.size ?? 0) + (child(root, "small")?.size ?? 0)
                     + (child(root, "skip")?.size ?? 0) + (child(root, "hardlink.bin")?.size ?? 0),
                     "the root's size is the sum of its children")
        suite.expect(child(root, "skip").map { $0.size == 0 && $0.children.isEmpty } == true,
                     "skipped paths are listed but never entered")
        suite.expect(child(root, "loop") == nil, "symbolic links are not followed or counted")
        suite.expect(child(root, "hardlink.bin")?.size == 0 || big?.size == 0,
                     "a file with two hard links is counted once")
        suite.expect(child(root, "small")?.collapsed == true, "tiny folders collapse during the scan")
        suite.expect(root.fileCount == 4 && scanner.snapshot().files == 4 && scanner.snapshot().folders == 5,
                     "progress counts every file and folder read")
        suite.expect(DiskAnalyzerScanner(options: .init()).scan(path: base.appendingPathComponent("a/big.bin").path,
                                                               displayName: "x") == nil,
                     "a file is not a scan root")

        let cancelled = DiskAnalyzerScanner(options: .init())
        cancelled.cancel()
        suite.expect(cancelled.scan(path: base.path, displayName: "x") == nil, "a cancelled scan returns nothing")
    }

    private static func strings(_ suite: TestSuite) {
        for language in AppLanguage.allCases {
            let strings = FeatureStrings.diskAnalyzer(language)
            suite.expect(!strings.title.isEmpty && !strings.hubDescription.isEmpty && !strings.panelCaption.isEmpty,
                         "the disk analyzer is named and described in \(language.rawValue)")
            if language != .enUS {
                suite.expect(strings.hiddenSpaceHelp != DiskAnalyzerFeatureStrings.enUS.hiddenSpaceHelp
                             && strings.fullDiskAccessReason != DiskAnalyzerFeatureStrings.enUS.fullDiskAccessReason,
                             "the disk analyzer explanations are translated in \(language.rawValue)")
            }
        }
        suite.expect(Defaults.registeredDefaults[DefaultsKey.panelUtilityDiskAnalyzer] as? Bool == true,
                     "the disk analyzer panel row ships visible like its siblings and travels in backups")
    }
}
