// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// One item in a scanned tree. Directories own their children, sorted from
/// largest to smallest once the scan finishes. Small files in a directory are
/// folded into a single `.smallFiles` entry so a whole-disk tree stays light.
///
/// A node is written only by the scanner job that owns it until the scan
/// completes; after that it is touched on the main thread only.
final class DiskNode: Identifiable, @unchecked Sendable {
    enum Kind: UInt8 {
        case directory
        case file
        /// Files too small to list one by one, folded into one entry.
        case smallFiles
        /// Space the volume reports as used that no readable item accounts
        /// for: system volumes, snapshots, purgeable space, protected folders.
        case hidden
    }

    let name: String
    let kind: Kind
    /// Allocated bytes, including every descendant.
    var size: Int64
    /// Regular files included in `size`.
    var fileCount: Int
    var children: [DiskNode] = []
    /// Parents own their children, so a back reference needs no retain and
    /// no weak side table; across millions of folders that adds up.
    unowned(unsafe) var parent: DiskNode?
    /// Subfolders still being scanned; only the scanner reads it.
    var pendingFolders = 0
    /// The directory exists but could not be listed, usually for privacy.
    var unreadable = false
    /// A cloud placeholder that was not downloaded and was not descended.
    var cloudOnly = false
    /// A folder too small to be worth mapping inside; its contents were
    /// counted and then dropped to keep a whole-disk map light.
    var collapsed = false
    /// Only the root carries an absolute path; the rest derive theirs.
    private let rootPath: String?

    var id: ObjectIdentifier { ObjectIdentifier(self) }

    init(name: String, kind: Kind, size: Int64 = 0, fileCount: Int = 0, rootPath: String? = nil) {
        self.name = name
        self.kind = kind
        self.size = size
        self.fileCount = fileCount
        self.rootPath = rootPath
    }

    var isDirectory: Bool { kind == .directory }
    /// Real items can be revealed, opened or moved to the Trash.
    var isFileSystemItem: Bool { kind == .directory || kind == .file }
    var canDrillDown: Bool { kind == .directory && !collapsed && children.contains { $0.size > 0 } }

    var path: String {
        if let rootPath { return rootPath }
        guard let parent else { return name }
        let base = parent.path
        return base.hasSuffix("/") ? base + name : base + "/" + name
    }

    var url: URL { URL(fileURLWithPath: path, isDirectory: isDirectory) }

    /// Root first, self last.
    var lineage: [DiskNode] {
        var chain: [DiskNode] = []
        var node: DiskNode? = self
        while let current = node {
            chain.append(current)
            node = current.parent
        }
        return chain.reversed()
    }

    func isAncestor(of other: DiskNode) -> Bool {
        var node = other.parent
        while let current = node {
            if current === self { return true }
            node = current.parent
        }
        return false
    }
}

enum DiskAnalyzerSupport {
    /// Files a directory lists one by one; the rest fold into one entry.
    static let listedFilesPerDirectory = 32

    /// Splits one directory's files into the ones worth listing and a single
    /// folded entry for the rest: everything past the largest `keep`, and
    /// anything under `minimumSize`. A lone leftover stays listed, since one
    /// folded file says less than its own name. `files` may arrive in any order.
    static func foldFiles(_ files: [DiskNode], keep: Int = listedFilesPerDirectory,
                          minimumSize: Int64 = 0) -> [DiskNode] {
        let sorted = files.sorted { $0.size > $1.size }
        let listed = sorted.prefix(keep).prefix { $0.size >= minimumSize }
        let rest = sorted.dropFirst(listed.count)
        guard rest.count > 1 else { return sorted }
        let folded = DiskNode(name: "",
                              kind: .smallFiles,
                              size: rest.reduce(0) { $0 + $1.size },
                              fileCount: rest.count)
        return Array(listed) + [folded]
    }

    /// Completes one folder once every subfolder has completed: adds their
    /// totals to the folder's own files, sorts the children and drops the
    /// insides of subfolders smaller than `collapseBelow`.
    static func settle(_ node: DiskNode, collapseBelow: Int64) {
        for child in node.children where child.kind == .directory {
            node.size += child.size
            node.fileCount += child.fileCount
            if child.size < collapseBelow, !child.children.isEmpty {
                child.children = []
                child.collapsed = true
            }
        }
        node.children.sort(by: ordered)
    }

    /// Largest first; folded and hidden entries sink below real items of the
    /// same size so the names people recognise come first.
    static func ordered(_ lhs: DiskNode, _ rhs: DiskNode) -> Bool {
        if lhs.size != rhs.size { return lhs.size > rhs.size }
        if (lhs.kind == .smallFiles || lhs.kind == .hidden) != (rhs.kind == .smallFiles || rhs.kind == .hidden) {
            return rhs.kind == .smallFiles || rhs.kind == .hidden
        }
        return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
    }

    /// Takes a removed item's bytes and files off every ancestor and drops it
    /// from its parent. Returns false when the node is not attached.
    @discardableResult
    static func detach(_ node: DiskNode) -> Bool {
        guard let parent = node.parent,
              let index = parent.children.firstIndex(where: { $0 === node }) else { return false }
        parent.children.remove(at: index)
        var ancestor: DiskNode? = parent
        while let current = ancestor {
            current.size = max(0, current.size - node.size)
            current.fileCount = max(0, current.fileCount - node.fileCount)
            if let grand = current.parent { grand.children.sort(by: ordered) }
            ancestor = current.parent
        }
        node.parent = nil
        return true
    }

    /// Puts a detached item back under `parent`, the inverse of `detach`,
    /// for when a move to the Trash is undone.
    static func attach(_ node: DiskNode, to parent: DiskNode) {
        node.parent = parent
        parent.children.append(node)
        parent.children.sort(by: ordered)
        var ancestor: DiskNode? = parent
        while let current = ancestor {
            current.size += node.size
            current.fileCount += node.fileCount
            if let grand = current.parent { grand.children.sort(by: ordered) }
            ancestor = current.parent
        }
    }

    /// Whether `node` still hangs from `root`, so actions on it reach the map.
    static func isAttached(_ node: DiskNode, to root: DiskNode) -> Bool {
        node === root || root.isAncestor(of: node)
    }

    /// Adds an item to a set of marked items without counting any byte twice:
    /// marking a folder absorbs marks inside it, and an item inside a marked
    /// folder is already covered.
    static func marking(_ node: DiskNode, in marked: [DiskNode]) -> [DiskNode] {
        guard !marked.contains(where: { $0 === node || $0.isAncestor(of: node) }) else { return marked }
        return marked.filter { !node.isAncestor(of: $0) } + [node]
    }

    // MARK: - Rebuildable folders

    /// Folders that developer tools recreate on their own, safe to remove
    /// while the project that owns them is not being built.
    enum Rebuildable: String, CaseIterable {
        case nodeModules, derivedData, dartTool, gradle, pods, pythonCache, webBuildCache, deviceSupport

        /// Matches by folder name, plus the parent where a name alone would
        /// be too common to trust.
        static func match(name: String, parentName: String?) -> Rebuildable? {
            switch name {
            case "node_modules": return .nodeModules
            case "DerivedData": return parentName == "Xcode" ? .derivedData : nil
            case ".dart_tool": return .dartTool
            case ".gradle": return .gradle
            case "Pods": return .pods
            case "__pycache__": return .pythonCache
            case ".next", ".nuxt", ".turbo", ".parcel-cache", ".svelte-kit", ".angular": return .webBuildCache
            case "iOS DeviceSupport", "watchOS DeviceSupport", "tvOS DeviceSupport", "visionOS DeviceSupport":
                return parentName == "Xcode" ? .deviceSupport : nil
            default: return nil
            }
        }
    }

    /// The outermost rebuildable folders below `root`, largest first. A match
    /// is not searched inside, so nested node_modules are not listed twice.
    static func rebuildableFolders(in root: DiskNode, minimumSize: Int64 = 1 << 20)
        -> [(node: DiskNode, kind: Rebuildable)] {
        var found: [(node: DiskNode, kind: Rebuildable)] = []
        var stack: [DiskNode] = [root]
        while let node = stack.popLast() {
            for child in node.children where child.kind == .directory && child.size >= minimumSize {
                if let kind = Rebuildable.match(name: child.name, parentName: node.name) {
                    found.append((child, kind))
                } else {
                    stack.append(child)
                }
            }
        }
        return found.sorted { $0.node.size > $1.node.size }
    }

    /// Swaps a freshly scanned copy of a directory into the tree in place.
    static func replace(_ old: DiskNode, with fresh: DiskNode) {
        guard let parent = old.parent,
              let index = parent.children.firstIndex(where: { $0 === old }) else { return }
        let sizeDelta = fresh.size - old.size
        let fileDelta = fresh.fileCount - old.fileCount
        parent.children[index] = fresh
        fresh.parent = parent
        old.parent = nil
        var ancestor: DiskNode? = parent
        while let current = ancestor {
            current.size = max(0, current.size + sizeDelta)
            current.fileCount = max(0, current.fileCount + fileDelta)
            current.children.sort(by: ordered)
            ancestor = current.parent
        }
    }

    /// The share of a volume the scan could not attribute to readable items.
    /// Small differences are rounding and allocation noise, not worth a slice.
    static func hiddenBytes(volumeUsed: Int64, scanned: Int64) -> Int64 {
        let difference = volumeUsed - scanned
        let noise = max(Int64(256 * 1024 * 1024), volumeUsed / 200)
        return difference > noise ? difference : 0
    }

    /// The largest items anywhere below `root`, files and leaf-like folders,
    /// useful as a "biggest offenders" shortlist.
    static func largestFiles(in root: DiskNode, limit: Int) -> [DiskNode] {
        guard limit > 0 else { return [] }
        var best: [DiskNode] = []
        var floor: Int64 = 0
        var stack: [DiskNode] = [root]
        while let node = stack.popLast() {
            for child in node.children {
                switch child.kind {
                case .directory:
                    // A folder smaller than the current floor cannot hold a
                    // file large enough to enter the list.
                    if best.count < limit || child.size > floor { stack.append(child) }
                case .file:
                    guard best.count < limit || child.size > floor else { continue }
                    let index = best.firstIndex { $0.size < child.size } ?? best.endIndex
                    best.insert(child, at: index)
                    if best.count > limit { best.removeLast() }
                    floor = best.count == limit ? best.last?.size ?? 0 : 0
                case .smallFiles, .hidden:
                    continue
                }
            }
        }
        return best
    }

    // MARK: - Scan scope

    /// Left out of a startup disk scan: the other APFS volumes of the
    /// container (counted as hidden space), mounted volumes and device nodes.
    static let startupDiskSkippedPaths: Set<String> = [
        "/System/Volumes", "/Volumes", "/dev", "/net", "/home", "/cores",
    ]

    /// Other apps' private data. Without Full Disk Access, reading these
    /// raises one privacy prompt per app, so the walk leaves them out.
    static func containerPaths(home: String) -> Set<String> {
        let library = (home as NSString).appendingPathComponent("Library")
        return [
            (library as NSString).appendingPathComponent("Containers"),
            (library as NSString).appendingPathComponent("Group Containers"),
        ]
    }

    /// Whether the map may offer to move an item to the Trash: things inside
    /// the home folder, apps in /Applications and items on other volumes.
    /// The home folder itself, its Library and the system stay off limits.
    static func isTrashable(path: String, home: String) -> Bool {
        let standardized = (path as NSString).standardizingPath
        let components = (standardized as NSString).pathComponents
        guard standardized.hasPrefix("/"), !components.contains("..") else { return false }
        let homeLibrary = (home as NSString).appendingPathComponent("Library")
        if standardized.hasPrefix(home + "/") && !home.isEmpty && home != "/" {
            return standardized != homeLibrary
        }
        if standardized.hasPrefix("/Applications/") {
            return components.count >= 3
        }
        if standardized.hasPrefix("/Volumes/") {
            return components.count >= 4
        }
        return false
    }

    // MARK: - Sunburst geometry

    /// One drawn segment. Angles are fractions of a full turn, clockwise from
    /// twelve o'clock; depth 1 is the ring touching the center disk.
    struct Arc {
        let node: DiskNode
        let depth: Int
        let start: Double
        let end: Double
    }

    /// Lays out `maxDepth` rings around `focus`. Segments thinner than
    /// `minimumSpan` (a fraction of a turn) are left out, along with their
    /// descendants, so the chart stays legible and cheap to draw.
    static func sunburst(focus: DiskNode, maxDepth: Int, minimumSpan: Double) -> [Arc] {
        guard focus.size > 0, maxDepth > 0 else { return [] }
        var arcs: [Arc] = []
        var stack: [(node: DiskNode, depth: Int, start: Double, span: Double)] = [(focus, 0, 0, 1)]
        while let (node, depth, start, span) = stack.popLast() {
            guard depth < maxDepth, node.size > 0 else { continue }
            var cursor = start
            for child in node.children where child.size > 0 {
                let childSpan = span * Double(child.size) / Double(node.size)
                // Children are sorted by size, so every later one is thinner.
                if childSpan < minimumSpan { break }
                arcs.append(Arc(node: child, depth: depth + 1, start: cursor, end: cursor + childSpan))
                if child.kind == .directory {
                    stack.append((child, depth + 1, cursor, childSpan))
                }
                cursor += childSpan
            }
        }
        return arcs
    }

    /// Where an arc of the current layout sits on screen while the chart
    /// zooms from `focus` into one of its children. `window` is the slice of
    /// the turn that will fill the circle; `progress` runs from 0 to 1.
    static func zoomed(start: Double, end: Double, window: ClosedRange<Double>, progress: Double)
        -> (start: Double, end: Double)? {
        let low = window.lowerBound * progress
        let high = 1 + (window.upperBound - 1) * progress
        let width = high - low
        guard width > 0 else { return nil }
        let mappedStart = (start - low) / width
        let mappedEnd = (end - low) / width
        guard mappedEnd > 0, mappedStart < 1 else { return nil }
        return (max(0, mappedStart), min(1, mappedEnd))
    }

    /// The arc under a polar position: `angle` as a fraction of a turn and
    /// `depth` as the ring index (1 = innermost ring).
    static func arc(at angle: Double, depth: Int, in arcs: [Arc]) -> Arc? {
        arcs.first { $0.depth == depth && angle >= $0.start && angle < $0.end }
    }
}
