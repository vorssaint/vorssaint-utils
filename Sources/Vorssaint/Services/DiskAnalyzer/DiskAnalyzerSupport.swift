// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import CoreGraphics
import Darwin
import Foundation

/// Pure sizing, tree, and treemap helpers for Disk Analyzer. Views and the
/// ObservableObject service call into here so layout and scan rules stay
/// testable without AppKit windows.
enum DiskAnalyzerSupport {
    final class ScanCancellation {
        private let lock = NSLock()
        private var cancelled = false

        var isCancelled: Bool {
            lock.lock()
            defer { lock.unlock() }
            return cancelled
        }

        func cancel() {
            lock.lock()
            cancelled = true
            lock.unlock()
        }
    }

    struct Progress: Equatable {
        var bytes: Int64
        var files: Int
        var currentPath: String
    }

    struct Node: Identifiable, Equatable {
        var id: String { path }
        let path: String
        let name: String
        var size: Int64
        let isDirectory: Bool
        var children: [Node]

        var url: URL { URL(fileURLWithPath: path, isDirectory: isDirectory) }
    }

    struct TreemapCell: Equatable, Identifiable {
        var id: String { path }
        let path: String
        let name: String
        let size: Int64
        let isDirectory: Bool
        let rect: CGRect
        /// Index among the zoom root's immediate children; descendants inherit
        /// the ancestor's index so a folder keeps one hue through nesting.
        let colorIndex: Int
        let depth: Int
    }

    // MARK: - File rules

    static func allocatedSize(of url: URL) -> Int64 {
        let values = try? url.resourceValues(forKeys: [.totalFileAllocatedSizeKey, .fileAllocatedSizeKey])
        return Int64(values?.totalFileAllocatedSize ?? values?.fileAllocatedSize ?? 0)
    }

    static func isSymbolicLink(_ url: URL) -> Bool {
        var info = stat()
        guard lstat(url.path, &info) == 0 else { return false }
        return (info.st_mode & S_IFMT) == S_IFLNK
    }

    static func deviceID(of url: URL) -> dev_t? {
        var info = stat()
        guard lstat(url.path, &info) == 0 else { return nil }
        return info.st_dev
    }

    static func isHiddenName(_ name: String) -> Bool {
        name.hasPrefix(".")
    }

    static func canTrash(_ url: URL) -> Bool {
        FileManager.default.isDeletableFile(atPath: url.path)
    }

    // MARK: - Scan

    /// Builds a size tree under `root`. Symlinks are skipped. Children on a
    /// different device (another volume) are skipped so a startup-disk scan
    /// does not walk every mount. Returns nil when cancelled.
    static func scan(root: URL,
                     includeHidden: Bool,
                     cancellation: ScanCancellation,
                     progress: (Progress) -> Void) -> Node? {
        let fm = FileManager.default
        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: root.path, isDirectory: &isDir) else { return nil }
        let rootDevice = deviceID(of: root)
        var seen = Progress(bytes: 0, files: 0, currentPath: root.path)
        progress(seen)

        if !isDir.boolValue {
            if isSymbolicLink(root) { return nil }
            let size = allocatedSize(of: root)
            seen.bytes = size
            seen.files = 1
            progress(seen)
            return Node(path: root.path, name: root.lastPathComponent, size: size,
                        isDirectory: false, children: [])
        }

        return scanDirectory(root, includeHidden: includeHidden, rootDevice: rootDevice,
                             cancellation: cancellation, progress: &seen, report: progress)
    }

    private static func scanDirectory(_ url: URL,
                                      includeHidden: Bool,
                                      rootDevice: dev_t?,
                                      cancellation: ScanCancellation,
                                      progress: inout Progress,
                                      report: (Progress) -> Void) -> Node? {
        if cancellation.isCancelled { return nil }
        progress.currentPath = url.path
        report(progress)

        let fm = FileManager.default
        let keys: [URLResourceKey] = [
            .isDirectoryKey, .isSymbolicLinkKey, .isVolumeKey,
            .totalFileAllocatedSizeKey, .fileAllocatedSizeKey, .isHiddenKey
        ]
        let childrenURLs = (try? fm.contentsOfDirectory(at: url,
                                                        includingPropertiesForKeys: keys,
                                                        options: [])) ?? []
        var children: [Node] = []
        var total: Int64 = 0

        for childURL in childrenURLs.sorted(by: { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }) {
            if cancellation.isCancelled { return nil }
            let name = childURL.lastPathComponent
            if !includeHidden && isHiddenName(name) { continue }
            if isSymbolicLink(childURL) { continue }
            if let rootDevice, let childDevice = deviceID(of: childURL), childDevice != rootDevice {
                continue
            }

            let values = try? childURL.resourceValues(forKeys: Set(keys))
            let isDirectory = values?.isDirectory == true
            // A nested volume mount appears as a directory on a different
            // device; the device check above already skipped those. isVolume
            // catches the rare case where device IDs match but the entry is
            // still a volume root we should not recurse into from Home.
            if isDirectory, values?.isVolume == true, childURL.standardizedFileURL != url.standardizedFileURL {
                if let rootDevice, let childDevice = deviceID(of: childURL), childDevice != rootDevice {
                    continue
                }
            }

            if isDirectory {
                guard let node = scanDirectory(childURL, includeHidden: includeHidden,
                                               rootDevice: rootDevice,
                                               cancellation: cancellation,
                                               progress: &progress, report: report)
                else { return nil }
                if node.size > 0 || !node.children.isEmpty {
                    children.append(node)
                    total += node.size
                }
            } else {
                let size = Int64(values?.totalFileAllocatedSize
                                 ?? values?.fileAllocatedSize
                                 ?? Int(allocatedSize(of: childURL)))
                progress.bytes += size
                progress.files += 1
                progress.currentPath = childURL.path
                if progress.files % 64 == 0 { report(progress) }
                if size > 0 {
                    children.append(Node(path: childURL.path, name: name, size: size,
                                         isDirectory: false, children: []))
                    total += size
                }
            }
        }

        children.sort { $0.size > $1.size }
        report(progress)
        return Node(path: url.path, name: url.lastPathComponent, size: total,
                    isDirectory: true, children: children)
    }

    // MARK: - Tree edits

    /// Removes the node at `path` and subtracts its size from ancestors.
    /// Returns nil when the removed node was the root itself.
    static func removing(path: String, from root: Node) -> Node? {
        if root.path == path { return nil }
        return removeChild(path: path, from: root)
    }

    private static func removeChild(path: String, from node: Node) -> Node {
        var copy = node
        if let index = copy.children.firstIndex(where: { $0.path == path }) {
            copy.children.remove(at: index)
            copy.size = copy.children.reduce(Int64(0)) { $0 + $1.size }
            return copy
        }
        var newChildren: [Node] = []
        newChildren.reserveCapacity(copy.children.count)
        var changed = false
        for child in copy.children {
            if path.hasPrefix(child.path + "/") {
                newChildren.append(removeChild(path: path, from: child))
                changed = true
            } else {
                newChildren.append(child)
            }
        }
        if changed {
            copy.children = newChildren
            copy.size = copy.children.reduce(Int64(0)) { $0 + $1.size }
        }
        return copy
    }

    static func node(at path: String, in root: Node) -> Node? {
        if root.path == path { return root }
        for child in root.children {
            if child.path == path { return child }
            if path.hasPrefix(child.path + "/"), let found = node(at: path, in: child) {
                return found
            }
        }
        return nil
    }

    static func breadcrumb(to path: String, in root: Node) -> [Node] {
        var chain: [Node] = [root]
        guard path != root.path else { return chain }
        var current = root
        let parts = path.dropFirst(root.path == "/" ? 0 : root.path.count)
            .split(separator: "/")
            .map(String.init)
        var built = root.path == "/" ? "" : root.path
        for part in parts {
            built += "/" + part
            if built.hasPrefix("//") { built = String(built.dropFirst()) }
            guard let next = current.children.first(where: { $0.path == built || $0.name == part })
                    ?? node(at: built, in: current)
            else { break }
            chain.append(next)
            current = next
        }
        return chain
    }

    // MARK: - Treemap (squarified)

    /// Lays out `root`'s descendants into nested rectangles. Empty / zero-size
    /// children are omitted. Nesting stops when a cell's area is below
    /// `minArea` so tiny boxes do not explode the cell count.
    static func layoutTreemap(root: Node,
                              in bounds: CGRect,
                              minArea: CGFloat = 36) -> [TreemapCell] {
        guard bounds.width > 1, bounds.height > 1, root.size > 0 else { return [] }
        var cells: [TreemapCell] = []
        layoutChildren(root.children, in: bounds, colorBase: nil, depth: 0,
                       minArea: minArea, into: &cells)
        return cells
    }

    private static func layoutChildren(_ children: [Node],
                                       in bounds: CGRect,
                                       colorBase: Int?,
                                       depth: Int,
                                       minArea: CGFloat,
                                       into cells: inout [TreemapCell]) {
        let positive = children.filter { $0.size > 0 }
        guard !positive.isEmpty else { return }
        let rects = squarify(positive, in: bounds)
        for (index, pair) in rects.enumerated() {
            let node = pair.node
            let rect = pair.rect
            let colorIndex = colorBase ?? index
            cells.append(TreemapCell(path: node.path, name: node.name, size: node.size,
                                     isDirectory: node.isDirectory, rect: rect,
                                     colorIndex: colorIndex, depth: depth))
            let area = rect.width * rect.height
            if node.isDirectory, !node.children.isEmpty, area >= minArea * 4 {
                let inset = rect.insetBy(dx: 1.5, dy: 1.5)
                if inset.width > 2, inset.height > 2 {
                    layoutChildren(node.children, in: inset, colorBase: colorIndex,
                                   depth: depth + 1, minArea: minArea, into: &cells)
                }
            }
        }
    }

    struct Placed {
        let node: Node
        let rect: CGRect
    }

    /// Squarified treemap (Bruls, Huizing, van Wijk). Children must be sorted
    /// largest-first for stable packing; callers already sort by size.
    static func squarify(_ children: [Node], in bounds: CGRect) -> [Placed] {
        let total = children.reduce(Int64(0)) { $0 + $1.size }
        guard total > 0, bounds.width > 0, bounds.height > 0 else { return [] }

        var remaining = children
        var free = bounds
        var result: [Placed] = []

        while !remaining.isEmpty {
            let vertical = free.width >= free.height
            let side = vertical ? free.height : free.width
            guard side > 0 else { break }

            var row: [Node] = []
            var rowSize: Int64 = 0
            var bestWorst = CGFloat.greatestFiniteMagnitude

            while !remaining.isEmpty {
                let candidate = remaining[0]
                let nextSize = rowSize + candidate.size
                let nextRow = row + [candidate]
                let worst = worstAspect(sizes: nextRow.map(\.size),
                                        rowSize: nextSize,
                                        side: side,
                                        total: total,
                                        freeArea: free.width * free.height)
                if row.isEmpty || worst <= bestWorst {
                    row = nextRow
                    rowSize = nextSize
                    bestWorst = worst
                    remaining.removeFirst()
                } else {
                    break
                }
            }

            let isLast = remaining.isEmpty
            let rowArea = CGFloat(rowSize) / CGFloat(total) * (free.width * free.height)
            if vertical {
                let rowWidth = isLast ? free.width : rowArea / max(free.height, 0.0001)
                var y = free.minY
                for (index, node) in row.enumerated() {
                    let isLastItem = index == row.count - 1
                    let h = isLastItem
                        ? free.maxY - y
                        : CGFloat(node.size) / CGFloat(rowSize) * free.height
                    result.append(Placed(node: node,
                                         rect: CGRect(x: free.minX, y: y,
                                                      width: rowWidth, height: max(0, h))))
                    y += h
                }
                free.origin.x += rowWidth
                free.size.width = max(0, free.width - rowWidth)
            } else {
                let rowHeight = isLast ? free.height : rowArea / max(free.width, 0.0001)
                var x = free.minX
                for (index, node) in row.enumerated() {
                    let isLastItem = index == row.count - 1
                    let w = isLastItem
                        ? free.maxX - x
                        : CGFloat(node.size) / CGFloat(rowSize) * free.width
                    result.append(Placed(node: node,
                                         rect: CGRect(x: x, y: free.minY,
                                                      width: max(0, w), height: rowHeight)))
                    x += w
                }
                free.origin.y += rowHeight
                free.size.height = max(0, free.height - rowHeight)
            }
        }
        return result
    }

    private static func worstAspect(sizes: [Int64],
                                    rowSize: Int64,
                                    side: CGFloat,
                                    total: Int64,
                                    freeArea: CGFloat) -> CGFloat {
        guard rowSize > 0, total > 0, side > 0, freeArea > 0 else {
            return CGFloat.greatestFiniteMagnitude
        }
        let rowArea = CGFloat(rowSize) / CGFloat(total) * freeArea
        let rowOther = rowArea / side
        guard rowOther > 0 else { return CGFloat.greatestFiniteMagnitude }
        var worst: CGFloat = 1
        for size in sizes {
            let itemSide = CGFloat(size) / CGFloat(rowSize) * side
            guard itemSide > 0 else { continue }
            let ratio = max(rowOther / itemSide, itemSide / rowOther)
            worst = max(worst, ratio)
        }
        return worst
    }

    static func color(for index: Int, depth: Int) -> NSColor {
        let hue = CGFloat((index * 47) % 360) / 360.0
        let saturation = max(0.35, 0.72 - CGFloat(depth) * 0.08)
        let brightness = max(0.45, 0.88 - CGFloat(depth) * 0.06)
        return NSColor(calibratedHue: hue, saturation: saturation,
                       brightness: brightness, alpha: 1)
    }

    static func formatBytes(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
}
