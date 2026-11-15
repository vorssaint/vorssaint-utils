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

    /// Soft caps keep Home / startup-disk scans responsive: only the largest
    /// children stay expandable; the rest roll into an aggregate leaf.
    static let maxChildrenPerDirectory = 64
    /// Only fold tiny files when a folder has many of them — WizTree keeps
    /// individual files visible so their sizes show up in the map.
    static let smallFileByteThreshold: Int64 = 64 * 1024
    static let smallFileFoldCount = 40
    /// How deep to nest boxes inside the current zoom folder. Deeper levels
    /// remain reachable by zooming in (like WizTree drill-down).
    static let treemapNestingDepth = 3

    struct Node: Identifiable, Equatable {
        var id: String { path }
        let path: String
        let name: String
        var size: Int64
        let isDirectory: Bool
        /// Synthetic rolled-up buckets (smaller files / other items) are not
        /// real paths and cannot be trashed or revealed.
        let isAggregate: Bool
        var children: [Node]

        var url: URL { URL(fileURLWithPath: path, isDirectory: isDirectory) }

        init(path: String, name: String, size: Int64, isDirectory: Bool,
             isAggregate: Bool = false, children: [Node]) {
            self.path = path
            self.name = name
            self.size = size
            self.isDirectory = isDirectory
            self.isAggregate = isAggregate
            self.children = children
        }
    }

    struct TreemapCell: Equatable, Identifiable {
        var id: String { path }
        let path: String
        let name: String
        let size: Int64
        let parentSize: Int64
        let isDirectory: Bool
        let isAggregate: Bool
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
    /// does not walk every mount. Top-level directories are scanned in
    /// parallel. Returns nil when cancelled.
    static func scan(root: URL,
                     includeHidden: Bool,
                     cancellation: ScanCancellation,
                     progress: @escaping (Progress) -> Void,
                     smallerFilesName: String = "Smaller files",
                     otherItemsName: String = "Other items") -> Node? {
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

        let labels = AggregateLabels(smallerFiles: smallerFilesName, otherItems: otherItemsName)
        let state = ScanState(report: progress)
        guard let node = scanDirectory(root, includeHidden: includeHidden, rootDevice: rootDevice,
                                       parallelChildren: true, labels: labels,
                                       cancellation: cancellation, state: state)
        else { return nil }
        progress(state.snapshot(currentPath: root.path))
        return node
    }

    private struct AggregateLabels {
        let smallerFiles: String
        let otherItems: String
    }

    private final class ScanState: @unchecked Sendable {
        private let lock = NSLock()
        private var bytes: Int64 = 0
        private var files = 0
        private var lastReport = Date.distantPast
        private let report: (Progress) -> Void

        init(report: @escaping (Progress) -> Void) {
            self.report = report
        }

        func add(fileBytes: Int64, path: String) {
            lock.lock()
            bytes += fileBytes
            files += 1
            let shouldReport = files % 256 == 0 || Date().timeIntervalSince(lastReport) >= 0.2
            let snapshot = Progress(bytes: bytes, files: files, currentPath: path)
            if shouldReport { lastReport = Date() }
            lock.unlock()
            if shouldReport { report(snapshot) }
        }

        func snapshot(currentPath: String) -> Progress {
            lock.lock()
            defer { lock.unlock() }
            return Progress(bytes: bytes, files: files, currentPath: currentPath)
        }
    }

    private static let resourceKeys: [URLResourceKey] = [
        .isDirectoryKey, .isSymbolicLinkKey, .isVolumeKey,
        .totalFileAllocatedSizeKey, .fileAllocatedSizeKey
    ]

    private static func scanDirectory(_ url: URL,
                                      includeHidden: Bool,
                                      rootDevice: dev_t?,
                                      parallelChildren: Bool,
                                      labels: AggregateLabels,
                                      cancellation: ScanCancellation,
                                      state: ScanState) -> Node? {
        if cancellation.isCancelled { return nil }

        let fm = FileManager.default
        var options: FileManager.DirectoryEnumerationOptions = []
        if !includeHidden { options.insert(.skipsHiddenFiles) }
        let childrenURLs = (try? fm.contentsOfDirectory(at: url,
                                                        includingPropertiesForKeys: resourceKeys,
                                                        options: options)) ?? []
        if childrenURLs.isEmpty {
            return Node(path: url.path, name: url.lastPathComponent, size: 0,
                        isDirectory: true, children: [])
        }

        var collected: [Node] = []
        collected.reserveCapacity(childrenURLs.count)

        if parallelChildren, childrenURLs.count > 1 {
            let lock = NSLock()
            let group = DispatchGroup()
            let queue = DispatchQueue(label: "com.vorssaint.utils.disk-analyzer.scan",
                                      qos: .userInitiated, attributes: .concurrent)
            for childURL in childrenURLs {
                group.enter()
                queue.async {
                    defer { group.leave() }
                    guard !cancellation.isCancelled,
                          let node = scanEntry(childURL, parent: url, includeHidden: includeHidden,
                                               rootDevice: rootDevice, labels: labels,
                                               cancellation: cancellation, state: state)
                    else { return }
                    lock.lock()
                    collected.append(node)
                    lock.unlock()
                }
            }
            // Poll so Cancel / window close can return without waiting for
            // every top-level folder on a startup-disk scan to finish.
            while group.wait(timeout: .now() + 0.05) == .timedOut {
                if cancellation.isCancelled { return nil }
            }
            if cancellation.isCancelled { return nil }
        } else {
            for childURL in childrenURLs {
                if cancellation.isCancelled { return nil }
                if let node = scanEntry(childURL, parent: url, includeHidden: includeHidden,
                                        rootDevice: rootDevice, labels: labels,
                                        cancellation: cancellation, state: state) {
                    collected.append(node)
                }
            }
        }

        let capped = capChildren(collected, parentPath: url.path, labels: labels)
        let total = capped.reduce(Int64(0)) { $0 + $1.size }
        return Node(path: url.path, name: url.lastPathComponent, size: total,
                    isDirectory: true, children: capped)
    }

    private static func scanEntry(_ childURL: URL,
                                  parent: URL,
                                  includeHidden: Bool,
                                  rootDevice: dev_t?,
                                  labels: AggregateLabels,
                                  cancellation: ScanCancellation,
                                  state: ScanState) -> Node? {
        if cancellation.isCancelled { return nil }
        let name = childURL.lastPathComponent
        if !includeHidden && isHiddenName(name) { return nil }

        let values = try? childURL.resourceValues(forKeys: Set(resourceKeys))
        if values?.isSymbolicLink == true { return nil }
        // Prefer resource values; fall back to one lstat for device checks.
        if let rootDevice {
            let childDevice = deviceID(of: childURL)
            if let childDevice, childDevice != rootDevice { return nil }
        }
        if values?.isVolume == true, childURL.standardizedFileURL != parent.standardizedFileURL {
            return nil
        }

        if values?.isDirectory == true {
            return scanDirectory(childURL, includeHidden: includeHidden, rootDevice: rootDevice,
                                 parallelChildren: false, labels: labels,
                                 cancellation: cancellation, state: state)
        }

        let size = Int64(values?.totalFileAllocatedSize
                         ?? values?.fileAllocatedSize
                         ?? Int(allocatedSize(of: childURL)))
        state.add(fileBytes: size, path: childURL.path)
        guard size > 0 else { return nil }
        return Node(path: childURL.path, name: name, size: size,
                    isDirectory: false, children: [])
    }

    /// Keeps the largest children expandable; folds small files and overflow
    /// into aggregate leaves so the treemap stays interactive.
    static func capChildren(_ children: [Node],
                            parentPath: String,
                            smallerFilesName: String = "Smaller files",
                            otherItemsName: String = "Other items") -> [Node] {
        capChildren(children, parentPath: parentPath,
                    labels: AggregateLabels(smallerFiles: smallerFilesName,
                                            otherItems: otherItemsName))
    }

    private static func capChildren(_ children: [Node],
                                    parentPath: String,
                                    labels: AggregateLabels) -> [Node] {
        var large: [Node] = []
        var smallFilesSize: Int64 = 0
        var smallFilesCount = 0
        for child in children {
            if !child.isDirectory, !child.isAggregate, child.size < smallFileByteThreshold {
                smallFilesSize += child.size
                smallFilesCount += 1
            } else {
                large.append(child)
            }
        }
        large.sort { $0.size > $1.size }

        var result: [Node] = []
        if large.count > maxChildrenPerDirectory {
            let kept = Array(large.prefix(maxChildrenPerDirectory - 1))
            let overflow = Array(large.dropFirst(maxChildrenPerDirectory - 1))
            let overflowSize = overflow.reduce(Int64(0)) { $0 + $1.size }
            result = kept
            if overflowSize > 0 {
                result.append(Node(path: parentPath + "/.__vorssaint_other__",
                                   name: labels.otherItems,
                                   size: overflowSize,
                                   isDirectory: false,
                                   isAggregate: true,
                                   children: []))
            }
        } else {
            result = large
        }

        if smallFilesCount > 0, smallFilesSize > 0 {
            // Keep small files as their own leaves unless the folder is crowded.
            if smallFilesCount <= smallFileFoldCount || large.isEmpty {
                let small = children.filter {
                    !$0.isDirectory && !$0.isAggregate && $0.size < smallFileByteThreshold && $0.size > 0
                }
                result.append(contentsOf: small)
            } else {
                result.append(Node(path: parentPath + "/.__vorssaint_small__",
                                   name: labels.smallerFiles,
                                   size: smallFilesSize,
                                   isDirectory: false,
                                   isAggregate: true,
                                   children: []))
            }
        }
        return result.sorted { $0.size > $1.size }
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

    /// WizTree-style nested layout of the zoom folder: children fill the map
    /// by size, and directories nest their own children inside (up to
    /// `treemapNestingDepth`). Files appear as leaf boxes. Cells are ordered
    /// parents-then-children so hit-testing can take the deepest match.
    static func layoutTreemap(root: Node,
                              in bounds: CGRect,
                              minArea: CGFloat = 24) -> [TreemapCell] {
        guard bounds.width > 1, bounds.height > 1 else { return [] }
        var cells: [TreemapCell] = []
        layoutChildren(root.children,
                       in: bounds,
                       parentSize: max(root.size, 1),
                       colorBase: nil,
                       depth: 0,
                       maxDepth: treemapNestingDepth,
                       minArea: minArea,
                       into: &cells)
        return cells
    }

    private static func layoutChildren(_ children: [Node],
                                       in bounds: CGRect,
                                       parentSize: Int64,
                                       colorBase: Int?,
                                       depth: Int,
                                       maxDepth: Int,
                                       minArea: CGFloat,
                                       into cells: inout [TreemapCell]) {
        let positive = children.filter { $0.size > 0 }
        guard !positive.isEmpty, bounds.width > 1, bounds.height > 1 else { return }
        let placed = squarify(positive, in: bounds)
        for (index, pair) in placed.enumerated() {
            let node = pair.node
            let colorIndex = colorBase ?? index
            cells.append(TreemapCell(
                path: node.path,
                name: node.name,
                size: node.size,
                parentSize: parentSize,
                isDirectory: node.isDirectory,
                isAggregate: node.isAggregate,
                rect: pair.rect,
                colorIndex: colorIndex,
                depth: depth
            ))
            let area = pair.rect.width * pair.rect.height
            if node.isDirectory,
               !node.isAggregate,
               !node.children.isEmpty,
               depth + 1 < maxDepth,
               area >= minArea * 6 {
                // Leave a header strip so the folder name stays readable, like
                // WizTree / WinDirStat nested maps.
                let header: CGFloat = min(16, max(10, pair.rect.height * 0.18))
                let inset = CGRect(
                    x: pair.rect.minX + 1.5,
                    y: pair.rect.minY + header,
                    width: max(0, pair.rect.width - 3),
                    height: max(0, pair.rect.height - header - 1.5)
                )
                if inset.width > 4, inset.height > 4 {
                    layoutChildren(node.children,
                                   in: inset,
                                   parentSize: max(node.size, 1),
                                   colorBase: colorIndex,
                                   depth: depth + 1,
                                   maxDepth: maxDepth,
                                   minArea: minArea,
                                   into: &cells)
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
