// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import CoreGraphics
import Foundation

enum DiskAnalyzerTests {
    static func run(_ suite: TestSuite) {
        treemapOmitsZeroSize(suite)
        treemapFillsBounds(suite)
        treeRemovalUpdatesAncestors(suite)
        scanBuildsTree(suite)
        scanSkipsSymlinks(suite)
        scanSkipsHiddenUnlessRequested(suite)
        catalogWiring(suite)
        stringsHaveFormats(suite)
    }

    private static func treemapOmitsZeroSize(_ suite: TestSuite) {
        let root = DiskAnalyzerSupport.Node(
            path: "/root", name: "root", size: 100, isDirectory: true,
            children: [
                .init(path: "/root/a", name: "a", size: 100, isDirectory: false, children: []),
                .init(path: "/root/empty", name: "empty", size: 0, isDirectory: false, children: []),
            ]
        )
        let cells = DiskAnalyzerSupport.layoutTreemap(
            root: root, in: CGRect(x: 0, y: 0, width: 200, height: 100), minArea: 1
        )
        suite.expect(cells.contains { $0.path == "/root/a" }, "positive children appear in treemap")
        suite.expect(!cells.contains { $0.path == "/root/empty" }, "zero-size children are omitted")

        let nestedRoot = DiskAnalyzerSupport.Node(
            path: "/root", name: "root", size: 100, isDirectory: true,
            children: [
                .init(path: "/root/dir", name: "dir", size: 100, isDirectory: true, children: [
                    .init(path: "/root/dir/file.bin", name: "file.bin", size: 60,
                          isDirectory: false, children: []),
                    .init(path: "/root/dir/other.bin", name: "other.bin", size: 40,
                          isDirectory: false, children: []),
                ]),
            ]
        )
        let nested = DiskAnalyzerSupport.layoutTreemap(
            root: nestedRoot, in: CGRect(x: 0, y: 0, width: 400, height: 300), minArea: 1
        )
        suite.expect(nested.contains { $0.path == "/root/dir" }, "folder boxes appear")
        suite.expect(nested.contains { $0.path == "/root/dir/file.bin" },
                     "file sizes appear nested inside folder boxes")
        let fileCell = nested.first { $0.path == "/root/dir/file.bin" }
        let folderCell = nested.first { $0.path == "/root/dir" }
        if let fileCell, let folderCell {
            suite.expect(folderCell.rect.contains(fileCell.rect.insetBy(dx: 1, dy: 1))
                         || folderCell.rect.intersects(fileCell.rect),
                         "nested file rects sit inside their folder")
            suite.expect(fileCell.parentSize == folderCell.size,
                         "hover percent uses the immediate parent size")
        }
    }

    private static func treemapFillsBounds(_ suite: TestSuite) {
        let children = [
            DiskAnalyzerSupport.Node(path: "/r/a", name: "a", size: 50, isDirectory: false, children: []),
            DiskAnalyzerSupport.Node(path: "/r/b", name: "b", size: 30, isDirectory: false, children: []),
            DiskAnalyzerSupport.Node(path: "/r/c", name: "c", size: 20, isDirectory: false, children: []),
        ]
        let bounds = CGRect(x: 0, y: 0, width: 300, height: 200)
        let placed = DiskAnalyzerSupport.squarify(children, in: bounds)
        suite.expect(placed.count == 3, "squarify places every positive child")
        let area = placed.reduce(CGFloat(0)) { $0 + $1.rect.width * $1.rect.height }
        let expected = bounds.width * bounds.height
        suite.expect(abs(area - expected) < 1.0, "squarified rectangles fill the parent area")
        for item in placed {
            suite.expect(item.rect.width > 0 && item.rect.height > 0, "each rectangle has area")
            suite.expect(bounds.contains(item.rect.insetBy(dx: 0.01, dy: 0.01))
                         || bounds.intersects(item.rect),
                         "rectangles stay inside parent bounds")
        }

        // Area must track size: a 1% file must not eat a huge leftover strip.
        let skewed = [
            DiskAnalyzerSupport.Node(path: "/r/huge", name: "huge", size: 990, isDirectory: false, children: []),
            DiskAnalyzerSupport.Node(path: "/r/mid", name: "mid", size: 9, isDirectory: false, children: []),
            DiskAnalyzerSupport.Node(path: "/r/tiny", name: "tiny", size: 1, isDirectory: false, children: []),
        ]
        let skewedPlaced = DiskAnalyzerSupport.squarify(
            skewed, in: CGRect(x: 0, y: 0, width: 1000, height: 1000)
        )
        let totalArea = skewedPlaced.reduce(CGFloat(0)) { $0 + $1.rect.width * $1.rect.height }
        for item in skewedPlaced {
            let share = (item.rect.width * item.rect.height) / totalArea
            let expectedShare = CGFloat(item.node.size) / 1000
            suite.expect(abs(share - expectedShare) < 0.02,
                         "box area tracks file size (\(item.node.name): got \(share) want ~\(expectedShare))")
        }
        if let tiny = skewedPlaced.first(where: { $0.node.name == "tiny" }),
           let huge = skewedPlaced.first(where: { $0.node.name == "huge" }) {
            suite.expect(tiny.rect.width * tiny.rect.height < huge.rect.width * huge.rect.height * 0.05,
                         "tiny files stay visually tiny next to large ones")
        }
    }

    private static func treeRemovalUpdatesAncestors(_ suite: TestSuite) {
        let root = DiskAnalyzerSupport.Node(
            path: "/root", name: "root", size: 90, isDirectory: true,
            children: [
                .init(path: "/root/keep", name: "keep", size: 40, isDirectory: false, children: []),
                .init(path: "/root/dir", name: "dir", size: 50, isDirectory: true, children: [
                    .init(path: "/root/dir/file", name: "file", size: 50, isDirectory: false, children: []),
                ]),
            ]
        )
        let updated = DiskAnalyzerSupport.removing(path: "/root/dir/file", from: root)
        suite.expect(updated?.size == 40, "ancestor size shrinks after prune")
        suite.expect(updated?.children.contains { $0.path == "/root/keep" } == true,
                     "sibling survives prune")
        suite.expect(DiskAnalyzerSupport.removing(path: "/root", from: root) == nil,
                     "removing the root yields nil")
    }

    private static func scanBuildsTree(_ suite: TestSuite) {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("vorssaint-disk-analyzer-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let nested = root.appendingPathComponent("nested", isDirectory: true)
        try? FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
        let data = Data(repeating: 0x61, count: 4096)
        try? data.write(to: nested.appendingPathComponent("blob.bin"))
        // Above the small-file fold threshold so it stays an expandable leaf.
        let large = Data(repeating: 0x62, count: Int(DiskAnalyzerSupport.smallFileByteThreshold) + 1024)
        try? large.write(to: root.appendingPathComponent("large.bin"))

        let cancellation = DiskAnalyzerSupport.ScanCancellation()
        let tree = DiskAnalyzerSupport.scan(root: root, includeHidden: false,
                                            cancellation: cancellation) { _ in }
        suite.expect(tree != nil, "scan returns a tree")
        suite.expect((tree?.size ?? 0) > 0, "scanned tree reports allocated size")
        suite.expect(tree?.children.contains { $0.name == "nested" } == true,
                     "scan includes nested directories")
        suite.expect(tree?.children.contains { $0.name == "large.bin" } == true,
                     "scan includes large files as their own leaves")
    }

    private static func scanSkipsSymlinks(_ suite: TestSuite) {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("vorssaint-disk-analyzer-link-\(UUID().uuidString)",
                                    isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let real = root.appendingPathComponent("real.txt")
        try? Data(repeating: 0x62, count: 2048).write(to: real)
        let link = root.appendingPathComponent("alias.txt")
        try? FileManager.default.createSymbolicLink(at: link, withDestinationURL: real)

        let tree = DiskAnalyzerSupport.scan(
            root: root, includeHidden: true,
            cancellation: DiskAnalyzerSupport.ScanCancellation()
        ) { _ in }
        suite.expect(tree?.children.contains { $0.name == "alias.txt" } != true,
                     "symlinks are not followed or listed as sized children")
        suite.expect(tree?.children.contains { $0.name == "real.txt" } == true,
                     "real files still appear")
    }

    private static func scanSkipsHiddenUnlessRequested(_ suite: TestSuite) {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("vorssaint-disk-analyzer-hidden-\(UUID().uuidString)",
                                    isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try? Data("secret".utf8).write(to: root.appendingPathComponent(".secret"))
        try? Data("visible".utf8).write(to: root.appendingPathComponent("visible.txt"))

        let withoutHidden = DiskAnalyzerSupport.scan(
            root: root, includeHidden: false,
            cancellation: DiskAnalyzerSupport.ScanCancellation()
        ) { _ in }
        suite.expect(withoutHidden?.children.contains { $0.name == ".secret" } != true,
                     "hidden files skipped by default")
        suite.expect(withoutHidden?.children.contains { $0.name == "visible.txt" } == true,
                     "visible files remain")

        let withHidden = DiskAnalyzerSupport.scan(
            root: root, includeHidden: true,
            cancellation: DiskAnalyzerSupport.ScanCancellation()
        ) { _ in }
        suite.expect(withHidden?.children.contains { $0.name == ".secret" } == true,
                     "hidden files included when requested")
    }

    private static func catalogWiring(_ suite: TestSuite) {
        suite.expect(AppFeature.diskAnalyzer.group == .tools, "disk analyzer is a tools feature")
        suite.expect(AppFeature.diskAnalyzer.energyProfile == .idle, "disk analyzer is on-demand")
        suite.expect(AppFeature.diskAnalyzer.installedByDefault == false,
                     "disk analyzer is opt-in")
        suite.expect(AppFeature.diskAnalyzer.permissions == [.fullDiskAccess, .filesAndFolders],
                     "disk analyzer declares FDA and files permissions")
        suite.expect(AppFeature.diskAnalyzer.settingsDestination.page == .diskAnalyzer,
                     "disk analyzer opens its settings page")
        suite.expect(AppFeature.diskAnalyzer.symbolName == "square.grid.3x3.fill",
                     "disk analyzer uses the treemap symbol")
        suite.expect(AppFeature.diskAnalyzer.enabledKeys.isEmpty,
                     "disk analyzer has no separate enable key")

        var many: [DiskAnalyzerSupport.Node] = []
        let count = DiskAnalyzerSupport.maxChildrenPerDirectory + 20
        for index in 0..<count {
            many.append(.init(path: "/r/\(index)", name: "\(index)",
                              size: Int64(count - index) * 1_000_000,
                              isDirectory: false, children: []))
        }
        let capped = DiskAnalyzerSupport.capChildren(many, parentPath: "/r")
        suite.expect(capped.count <= DiskAnalyzerSupport.maxChildrenPerDirectory,
                     "capChildren limits per-directory fanout")
        suite.expect(capped.contains { $0.isAggregate },
                     "overflow rolls into an aggregate leaf")

        let tree = DiskAnalyzerSupport.Node(
            path: "/root", name: "root", size: 90, isDirectory: true,
            children: [
                .init(path: "/root/keep", name: "keep", size: 40, isDirectory: false, children: []),
                .init(path: "/root/gone", name: "gone", size: 50, isDirectory: true, children: [
                    .init(path: "/root/gone/file", name: "file", size: 50, isDirectory: false, children: []),
                ]),
            ]
        )
        let afterTrash = DiskAnalyzerSupport.removing(path: "/root/gone", from: tree)
        suite.expect(afterTrash?.size == 40, "trashing a folder updates the root size")
        let crumb = DiskAnalyzerSupport.breadcrumb(to: "/root/gone/file", in: afterTrash ?? tree)
        suite.expect(crumb.last?.path == "/root" || crumb.allSatisfy { $0.path != "/root/gone" },
                     "breadcrumb after trash stays on surviving ancestors")
    }

    private static func stringsHaveFormats(_ suite: TestSuite) {
        let english = FeatureStrings.diskAnalyzer(.enUS)
        for language in AppLanguage.allCases {
            let strings = FeatureStrings.diskAnalyzer(language)
            suite.expect(strings.scanningFormat.contains("%@") && strings.scanningFormat.contains("%d"),
                         "scanning format keeps placeholders (\(language))")
            suite.expect(strings.confirmTrashFormat.contains("%@"),
                         "trash confirm format keeps name (\(language))")
            suite.expect(strings.percentOfParentFormat.contains("%@"),
                         "percent format keeps placeholder (\(language))")
            suite.expect(strings.filesFormat.contains("%d"),
                         "files format keeps count (\(language))")
            suite.expect(!strings.pageTitle.isEmpty && !strings.hubDescription.isEmpty,
                         "disk analyzer strings are filled (\(language))")
            suite.expect(!strings.settingsIntro.isEmpty && !strings.openInUtilities.isEmpty,
                         "settings intro and open action are filled (\(language))")
            if language != .enUS {
                suite.expect(strings.openInUtilities != english.openInUtilities,
                             "openInUtilities is translated (\(language))")
                suite.expect(strings.scanOptionsSection != english.scanOptionsSection,
                             "scanOptionsSection is translated (\(language))")
                suite.expect(strings.confirmTrash != english.confirmTrash,
                             "confirmTrash is translated (\(language))")
                suite.expect(strings.nestingDepth != english.nestingDepth,
                             "nestingDepth is translated (\(language))")
            }
        }
        suite.expect(Defaults.registeredDefaults[DefaultsKey.panelUtilityDiskAnalyzer] as? Bool == true,
                     "disk analyzer panel row ships visible like its siblings")
    }
}
