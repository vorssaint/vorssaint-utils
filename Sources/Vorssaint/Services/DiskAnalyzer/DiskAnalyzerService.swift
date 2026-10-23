// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import Darwin
import Foundation

/// Owns one scan at a time and the tree it produced. Nothing is kept on disk:
/// closing the window or quitting forgets the map.
final class DiskAnalyzerService: ObservableObject {
    static let shared = DiskAnalyzerService()

    enum Phase: Equatable {
        case idle
        case scanning
        case results
        case failed
    }

    struct Target: Identifiable, Hashable {
        enum Kind: Hashable {
            case startupDisk
            case volume
            case folder
        }

        let kind: Kind
        let name: String
        let path: String
        /// Capacity and free space, when the target is a whole volume.
        let capacity: Int64
        let available: Int64

        var id: String { path }
        var used: Int64 { max(0, capacity - available) }
        var isVolume: Bool { kind != .folder }
    }

    @Published private(set) var phase = Phase.idle
    @Published private(set) var progress = DiskAnalyzerScanner.Progress()
    @Published private(set) var target: Target?
    @Published private(set) var root: DiskNode?
    @Published private(set) var focus: DiskNode?
    @Published private(set) var scanSeconds: TimeInterval = 0
    /// Bumped whenever the tree changes in place, so views redraw.
    @Published private(set) var revision = 0
    @Published private(set) var rescanning = false
    /// The item the action bar works on; nil means the focused folder.
    @Published var selected: DiskNode?
    /// Items set aside to go to the Trash together, never overlapping.
    @Published private(set) var marked: [DiskNode] = []
    /// The last move to the Trash, kept so it can be undone.
    @Published private(set) var lastTrash: TrashReceipt?

    struct TrashReceipt: Identifiable {
        struct Entry {
            let node: DiskNode
            let parent: DiskNode
            let original: URL
            let trashed: URL?
        }

        let id = UUID()
        let entries: [Entry]
        let failed: [String]
        var bytes: Int64 { entries.reduce(0) { $0 + $1.node.size } }
    }

    private var scanner: DiskAnalyzerScanner?
    private var rescanner: DiskAnalyzerScanner?
    private var largestCache: (focus: ObjectIdentifier, revision: Int, files: [DiskNode])?
    private var rebuildableCache: (focus: ObjectIdentifier, revision: Int,
                                   folders: [(node: DiskNode, kind: DiskAnalyzerSupport.Rebuildable)])?
    private var progressTimer: Timer?
    private var generation = 0

    private init() {}

    // MARK: - Targets

    /// The startup disk first, then other local volumes people can browse.
    func volumes() -> [Target] {
        let keys: [URLResourceKey] = [.volumeLocalizedNameKey, .volumeTotalCapacityKey,
                                      .volumeAvailableCapacityKey, .volumeIsBrowsableKey,
                                      .volumeIsRootFileSystemKey, .volumeIsLocalKey]
        let urls = FileManager.default.mountedVolumeURLs(includingResourceValuesForKeys: keys,
                                                         options: [.skipHiddenVolumes]) ?? []
        var result: [Target] = []
        for url in urls {
            guard let values = try? url.resourceValues(forKeys: Set(keys)),
                  values.volumeIsBrowsable != false,
                  values.volumeIsLocal != false else { continue }
            let isRoot = values.volumeIsRootFileSystem == true || url.path == "/"
            let space = Self.space(at: isRoot ? Self.dataVolumePath : url.path)
            let target = Target(kind: isRoot ? .startupDisk : .volume,
                                name: values.volumeLocalizedName ?? url.lastPathComponent,
                                path: url.path,
                                capacity: space?.capacity ?? Int64(values.volumeTotalCapacity ?? 0),
                                available: space?.available ?? Int64(values.volumeAvailableCapacity ?? 0))
            if isRoot { result.insert(target, at: 0) } else { result.append(target) }
        }
        return result
    }

    func homeTarget() -> Target {
        let home = NSHomeDirectory()
        return Target(kind: .folder, name: FileManager.default.displayName(atPath: home),
                      path: home, capacity: 0, available: 0)
    }

    func folderTarget(_ url: URL) -> Target {
        if let volume = volumes().first(where: { $0.path == url.standardizedFileURL.path }) {
            return volume
        }
        return Target(kind: .folder, name: FileManager.default.displayName(atPath: url.path),
                      path: url.standardizedFileURL.path, capacity: 0, available: 0)
    }

    // MARK: - Scanning

    func scan(_ target: Target) {
        guard AppFeature.diskAnalyzer.isAvailable else { return }
        cancelScanner()
        generation += 1
        let token = generation
        self.target = target
        root = nil
        focus = nil
        clearInteraction()
        progress = .init()
        phase = .scanning
        let started = Date()

        let options = Self.options(for: target, fullDiskAccess: Permissions.shared.fullDiskAccess)
        let scanner = DiskAnalyzerScanner(options: options)
        self.scanner = scanner
        startProgressTimer()

        DispatchQueue.global(qos: .userInitiated).async {
            let tree = scanner.scan(path: target.path, displayName: target.name)
            if let tree, target.isVolume {
                Self.addHiddenSpace(to: tree, target: target)
            }
            let final = scanner.snapshot()
            DispatchQueue.main.async {
                guard token == self.generation else { return }
                self.stopProgressTimer()
                self.scanner = nil
                self.progress = final
                self.scanSeconds = Date().timeIntervalSince(started)
                if let tree {
                    self.root = tree
                    self.focus = tree
                    self.phase = .results
                } else {
                    self.phase = scanner.isCancelled ? .idle : .failed
                }
            }
        }
    }

    func cancel() {
        cancelScanner()
        generation += 1
        stopProgressTimer()
        phase = root == nil ? .idle : .results
        rescanning = false
    }

    /// Forgets the map and returns to the volume picker.
    func reset() {
        cancel()
        clearInteraction()
        root = nil
        focus = nil
        target = nil
        phase = .idle
    }

    /// Scans the focused folder again and splices the result into the map,
    /// for after files were changed elsewhere.
    func rescanFocus() {
        guard let focus, let target, focus.kind == .directory, !rescanning else { return }
        if focus === root {
            scan(target)
            return
        }
        rescanning = true
        let token = generation
        let path = focus.path
        let name = focus.name
        let options = Self.options(for: target, fullDiskAccess: Permissions.shared.fullDiskAccess)
        let scanner = DiskAnalyzerScanner(options: options)
        rescanner = scanner
        DispatchQueue.global(qos: .userInitiated).async {
            let fresh = scanner.scan(path: path, displayName: name)
            DispatchQueue.main.async {
                guard token == self.generation else { return }
                self.rescanning = false
                self.rescanner = nil
                guard let fresh, focus.parent != nil else { return }
                let replacement = DiskNode(name: name, kind: .directory, size: fresh.size,
                                           fileCount: fresh.fileCount)
                replacement.children = fresh.children
                replacement.unreadable = fresh.unreadable
                for child in replacement.children { child.parent = replacement }
                // Keep whatever the person is looking at now: the same place
                // inside the fresh copy, or untouched when it is elsewhere.
                let current = self.focus
                let inside = current.map { $0 === focus || focus.isAncestor(of: $0) } == true
                let relative = inside ? current.map { Self.relativeNames(of: $0, below: focus) } ?? [] : []
                DiskAnalyzerSupport.replace(focus, with: replacement)
                if inside {
                    self.focus = Self.descend(replacement, through: relative)
                }
                self.revision += 1
                self.pruneDetached()
            }
        }
    }

    // MARK: - Navigation

    func focus(on node: DiskNode) {
        guard node.kind == .directory, node.size > 0 else { return }
        selected = nil
        focus = node
    }

    func focusParent() {
        guard let parent = focus?.parent else { return }
        selected = nil
        focus = parent
    }

    // MARK: - Actions

    func reveal(_ node: DiskNode) {
        guard node.isFileSystemItem else { return }
        NSWorkspace.shared.activateFileViewerSelecting([node.url])
    }

    func open(_ node: DiskNode) {
        guard node.isFileSystemItem else { return }
        NSWorkspace.shared.open(node.url)
    }

    func copyPath(_ node: DiskNode) {
        guard node.isFileSystemItem else { return }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(node.path, forType: .string)
    }

    /// Items the map refuses to trash: the scan root, anything above the home
    /// folder and the system's own trees.
    func canTrash(_ node: DiskNode) -> Bool {
        guard node.isFileSystemItem, node.parent != nil else { return false }
        return DiskAnalyzerSupport.isTrashable(path: node.path, home: NSHomeDirectory())
    }

    /// Opens Terminal in a folder, or in the folder holding a file.
    func openInTerminal(_ node: DiskNode) {
        guard node.isFileSystemItem,
              let terminal = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.Terminal")
        else { return }
        let folder = node.isDirectory ? node.url : node.url.deletingLastPathComponent()
        NSWorkspace.shared.open([folder], withApplicationAt: terminal, configuration: NSWorkspace.OpenConfiguration())
    }

    // MARK: - Marking

    func isMarked(_ node: DiskNode) -> Bool {
        marked.contains { $0 === node }
    }

    /// Inside a marked folder, so it already goes with it.
    func isCoveredByMark(_ node: DiskNode) -> Bool {
        marked.contains { $0.isAncestor(of: node) }
    }

    var markedBytes: Int64 { marked.reduce(0) { $0 + $1.size } }

    func toggleMark(_ node: DiskNode) {
        if isMarked(node) {
            marked.removeAll { $0 === node }
        } else if canTrash(node) {
            marked = DiskAnalyzerSupport.marking(node, in: marked)
        }
    }

    func clearMarks() {
        marked = []
    }

    // MARK: - Trash

    /// Moves items to the Trash, takes them off the map and keeps a receipt
    /// so the move can be undone.
    @discardableResult
    func moveToTrash(_ nodes: [DiskNode]) -> TrashReceipt {
        var entries: [TrashReceipt.Entry] = []
        var failed: [String] = []
        for node in nodes where canTrash(node) {
            guard let parent = node.parent else { continue }
            let original = node.url
            var resulting: NSURL?
            do {
                try FileManager.default.trashItem(at: original, resultingItemURL: &resulting)
                if focus.map({ $0 === node || node.isAncestor(of: $0) }) == true {
                    focus = parent
                }
                DiskAnalyzerSupport.detach(node)
                entries.append(.init(node: node, parent: parent, original: original,
                                     trashed: resulting as URL?))
            } catch {
                failed.append(node.name)
            }
        }
        let receipt = TrashReceipt(entries: entries, failed: failed)
        if !entries.isEmpty {
            revision += 1
            lastTrash = receipt
            pruneDetached()
        }
        return receipt
    }

    /// Puts the last trashed items back where they were and onto the map.
    /// Returns the names that could not be restored.
    @discardableResult
    func undoLastTrash() -> [String] {
        guard let receipt = lastTrash else { return [] }
        lastTrash = nil
        var failed: [String] = []
        for entry in receipt.entries.reversed() {
            guard let trashed = entry.trashed,
                  (try? FileManager.default.moveItem(at: trashed, to: entry.original)) != nil else {
                failed.append(entry.node.name)
                continue
            }
            if let root, DiskAnalyzerSupport.isAttached(entry.parent, to: root) {
                DiskAnalyzerSupport.attach(entry.node, to: entry.parent)
            }
        }
        revision += 1
        return failed
    }

    func dismissTrashReceipt() {
        lastTrash = nil
    }

    func openTrash() {
        let trash = FileManager.default.urls(for: .trashDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(".Trash")
        NSWorkspace.shared.open(trash)
    }

    /// Rebuildable developer folders below `node` that may be trashed,
    /// kept until the node or the tree changes.
    func rebuildableFolders(in node: DiskNode) -> [(node: DiskNode, kind: DiskAnalyzerSupport.Rebuildable)] {
        let key = ObjectIdentifier(node)
        if let cached = rebuildableCache, cached.focus == key, cached.revision == revision {
            return cached.folders
        }
        let folders = DiskAnalyzerSupport.rebuildableFolders(in: node).filter { canTrash($0.node) }
        rebuildableCache = (key, revision, folders)
        return folders
    }

    /// Drops marks and the selection that no longer hang from the map.
    private func pruneDetached() {
        guard let root else { return }
        marked.removeAll { !DiskAnalyzerSupport.isAttached($0, to: root) }
        if let selected, !DiskAnalyzerSupport.isAttached(selected, to: root) { self.selected = nil }
    }

    private func clearInteraction() {
        largestCache = nil
        rebuildableCache = nil
        selected = nil
        marked = []
        lastTrash = nil
    }

    // MARK: - Helpers

    private func cancelScanner() {
        scanner?.cancel()
        scanner = nil
        rescanner?.cancel()
        rescanner = nil
    }

    private static func relativeNames(of node: DiskNode, below ancestor: DiskNode) -> [String] {
        var names: [String] = []
        var current: DiskNode? = node
        while let step = current, step !== ancestor {
            names.append(step.name)
            current = step.parent
        }
        return names.reversed()
    }

    /// The deepest folder along `names` that still exists in the fresh tree.
    private static func descend(_ node: DiskNode, through names: [String]) -> DiskNode {
        var current = node
        for name in names {
            guard let next = current.children.first(where: { $0.kind == .directory && $0.name == name && $0.size > 0 })
            else { break }
            current = next
        }
        return current
    }

    /// The biggest files below `node`, kept until the node or the tree changes
    /// so redraws (hover, for one) do not walk the subtree again.
    func largestFiles(in node: DiskNode) -> [DiskNode] {
        let key = ObjectIdentifier(node)
        if let cached = largestCache, cached.focus == key, cached.revision == revision {
            return cached.files
        }
        let files = DiskAnalyzerSupport.largestFiles(in: node, limit: 60)
        largestCache = (key, revision, files)
        return files
    }

    private func startProgressTimer() {
        stopProgressTimer()
        let timer = Timer(timeInterval: 0.1, repeats: true) { [weak self] _ in
            guard let self, let scanner = self.scanner else { return }
            let snapshot = scanner.snapshot()
            if snapshot != self.progress { self.progress = snapshot }
        }
        RunLoop.main.add(timer, forMode: .common)
        progressTimer = timer
    }

    private func stopProgressTimer() {
        progressTimer?.invalidate()
        progressTimer = nil
    }

    private static let dataVolumePath = "/System/Volumes/Data"

    private static func space(at path: String) -> (capacity: Int64, available: Int64)? {
        var info = statfs()
        guard statfs(path, &info) == 0 else { return nil }
        let block = Int64(info.f_bsize)
        return (Int64(info.f_blocks) * block, Int64(info.f_bavail) * block)
    }

    private static func device(at path: String) -> dev_t? {
        var info = stat()
        return lstat(path, &info) == 0 ? info.st_dev : nil
    }

    static func options(for target: Target, fullDiskAccess: Bool) -> DiskAnalyzerScanner.Options {
        var options = DiskAnalyzerScanner.Options()
        let home = NSHomeDirectory()
        if !target.isVolume {
            // A chosen folder is usually small enough to keep in full detail,
            // where a whole disk needs the tiny folders folded away.
            options.collapseBelow = 64 << 10
            options.minimumListedFile = 16 << 10
        }
        if target.kind == .startupDisk {
            // The startup disk is two APFS volumes stitched together by
            // firmlinks: walk both, but not the volume list or the support
            // volumes under /System/Volumes, which the hidden slice covers.
            options.allowedDevices = Set([device(at: "/"), device(at: dataVolumePath)].compactMap { $0 })
            options.skippedPaths = DiskAnalyzerSupport.startupDiskSkippedPaths
        }
        if !fullDiskAccess {
            // Without Full Disk Access these ask about every app's private
            // data one prompt at a time; they stay on the map as hidden space.
            options.skippedPaths.formUnion(DiskAnalyzerSupport.containerPaths(home: home))
        }
        return options
    }

    private static func addHiddenSpace(to root: DiskNode, target: Target) {
        let space = space(at: target.kind == .startupDisk ? dataVolumePath : target.path)
        let used = space.map { $0.capacity - $0.available } ?? target.used
        let hidden = DiskAnalyzerSupport.hiddenBytes(volumeUsed: used, scanned: root.size)
        guard hidden > 0 else { return }
        let node = DiskNode(name: "", kind: .hidden, size: hidden)
        node.parent = root
        root.children.append(node)
        root.size += hidden
        root.children.sort(by: DiskAnalyzerSupport.ordered)
    }
}
