// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import Combine
import Foundation

/// Scans a chosen folder into a size tree and owns selection / zoom / trash
/// for the Disk Analyzer workspace window.
final class DiskAnalyzerService: ObservableObject {
    static let shared = DiskAnalyzerService()

    enum Phase: Equatable {
        case idle
        case scanning
        case ready
        case failed(String)
    }

    enum RootKind: String, CaseIterable, Identifiable {
        case home
        case startupDisk
        case folder

        var id: String { rawValue }
    }

    @Published private(set) var phase: Phase = .idle
    @Published private(set) var root: DiskAnalyzerSupport.Node?
    @Published private(set) var progress = DiskAnalyzerSupport.Progress(bytes: 0, files: 0, currentPath: "")
    @Published var selectedPath: String?
    @Published private(set) var zoomPath: String?
    @Published private(set) var trashError: String?
    @Published var includeHidden: Bool {
        didSet { UserDefaults.standard.set(includeHidden, forKey: DefaultsKey.diskAnalyzerIncludeHidden) }
    }

    private var cancellation: DiskAnalyzerSupport.ScanCancellation?
    private let worker = DispatchQueue(label: "com.vorssaint.utils.disk-analyzer", qos: .userInitiated)
    private var lastRootURL: URL?

    private init() {
        includeHidden = UserDefaults.standard.object(forKey: DefaultsKey.diskAnalyzerIncludeHidden) as? Bool ?? false
    }

    func showWindow() {
        DiskAnalyzerWindowController.shared.show()
    }

    var selectedNode: DiskAnalyzerSupport.Node? {
        guard let root, let selectedPath else { return nil }
        return DiskAnalyzerSupport.node(at: selectedPath, in: root)
    }

    var zoomNode: DiskAnalyzerSupport.Node? {
        guard let root else { return nil }
        guard let zoomPath else { return root }
        return DiskAnalyzerSupport.node(at: zoomPath, in: root) ?? root
    }

    var breadcrumbs: [DiskAnalyzerSupport.Node] {
        guard let root else { return [] }
        return DiskAnalyzerSupport.breadcrumb(to: zoomPath ?? root.path, in: root)
    }

    /// Children of the current zoom folder, largest first — the cleanup list.
    var listedItems: [DiskAnalyzerSupport.Node] {
        zoomNode?.children ?? []
    }

    var canTrashSelection: Bool {
        guard let node = selectedNode, !node.isAggregate else { return false }
        return DiskAnalyzerSupport.canTrash(node.url)
    }

    func url(for kind: RootKind) -> URL? {
        switch kind {
        case .home:
            return FileManager.default.homeDirectoryForCurrentUser
        case .startupDisk:
            return URL(fileURLWithPath: "/", isDirectory: true)
        case .folder:
            if let saved = UserDefaults.standard.string(forKey: DefaultsKey.diskAnalyzerLastRootPath),
               !saved.isEmpty,
               FileManager.default.fileExists(atPath: saved) {
                return URL(fileURLWithPath: saved, isDirectory: true)
            }
            return nil
        }
    }

    func scanHome() {
        scan(url: FileManager.default.homeDirectoryForCurrentUser)
    }

    func scanStartupDisk() {
        scan(url: URL(fileURLWithPath: "/", isDirectory: true))
    }

    func chooseFolderAndScan() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = FeatureStrings.diskAnalyzer(L10n.shared.language).chooseFolder
        panel.directoryURL = url(for: .folder)
            ?? FileManager.default.homeDirectoryForCurrentUser
        guard panel.runModal() == .OK, let url = panel.url else { return }
        scan(url: url)
    }

    func scan(url: URL) {
        cancel()
        let standardized = url.standardizedFileURL
        lastRootURL = standardized
        UserDefaults.standard.set(standardized.path, forKey: DefaultsKey.diskAnalyzerLastRootPath)
        phase = .scanning
        root = nil
        selectedPath = nil
        zoomPath = nil
        trashError = nil
        progress = DiskAnalyzerSupport.Progress(bytes: 0, files: 0, currentPath: standardized.path)

        let token = DiskAnalyzerSupport.ScanCancellation()
        cancellation = token
        let includeHidden = self.includeHidden

        let strings = FeatureStrings.diskAnalyzer(L10n.shared.language)
        worker.async {
            var lastPublish = Date.distantPast
            let tree = DiskAnalyzerSupport.scan(
                root: standardized,
                includeHidden: includeHidden,
                cancellation: token,
                progress: { snapshot in
                    let now = Date()
                    guard now.timeIntervalSince(lastPublish) >= 0.12 else { return }
                    lastPublish = now
                    DispatchQueue.main.async {
                        guard self.cancellation === token else { return }
                        self.progress = snapshot
                    }
                },
                smallerFilesName: strings.smallerFiles,
                otherItemsName: strings.otherItems
            )

            DispatchQueue.main.async {
                guard self.cancellation === token else { return }
                self.cancellation = nil
                if token.isCancelled {
                    if self.phase == .scanning { self.phase = .idle }
                    return
                }
                guard let tree else {
                    self.phase = .failed(FeatureStrings.diskAnalyzer(L10n.shared.language).scanFailed)
                    return
                }
                self.progress.bytes = tree.size
                self.root = tree
                self.zoomPath = tree.path
                self.phase = .ready
            }
        }
    }

    func rescan() {
        guard let lastRootURL else { return }
        scan(url: lastRootURL)
    }

    func cancel() {
        cancellation?.cancel()
        cancellation = nil
        if phase == .scanning {
            phase = root == nil ? .idle : .ready
        }
    }

    func select(path: String?) {
        selectedPath = path
        trashError = nil
    }

    func zoom(to path: String?) {
        guard let root else { return }
        if let path, DiskAnalyzerSupport.node(at: path, in: root)?.isDirectory == true {
            zoomPath = path
            selectedPath = path
        } else if path == nil {
            zoomPath = root.path
        }
    }

    func zoomIntoSelection() {
        guard let node = selectedNode, node.isDirectory else { return }
        zoom(to: node.path)
    }

    func revealSelection() {
        guard let node = selectedNode, !node.isAggregate else { return }
        NSWorkspace.shared.activateFileViewerSelecting([node.url])
    }

    func openSelection() {
        guard let node = selectedNode, !node.isAggregate else { return }
        NSWorkspace.shared.open(node.url)
    }

    func copySelectionPath() {
        guard let node = selectedNode, !node.isAggregate else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(node.path, forType: .string)
    }

    /// Moves the selection to the Trash and prunes it from the in-memory tree.
    /// Returns false when trash is unavailable or fails.
    @discardableResult
    func trashSelection() -> Bool {
        trashError = nil
        guard let node = selectedNode, !node.isAggregate, let current = root else { return false }
        guard DiskAnalyzerSupport.canTrash(node.url) else {
            trashError = FeatureStrings.diskAnalyzer(L10n.shared.language).trashUnavailable
            return false
        }
        do {
            try FileManager.default.trashItem(at: node.url, resultingItemURL: nil)
        } catch {
            trashError = error.localizedDescription
            return false
        }
        let removedPath = node.path
        if let updated = DiskAnalyzerSupport.removing(path: removedPath, from: current) {
            root = updated
            if let zoomPath,
               zoomPath == removedPath || zoomPath.hasPrefix(removedPath + "/") {
                // Land on the deepest surviving ancestor instead of jumping
                // all the way back to the scan root.
                self.zoomPath = DiskAnalyzerSupport.breadcrumb(to: removedPath, in: updated)
                    .last(where: { $0.path != removedPath })?.path
                    ?? updated.path
            }
            selectedPath = nil
        } else {
            root = nil
            zoomPath = nil
            selectedPath = nil
            phase = .idle
        }
        return true
    }

    func reset() {
        cancel()
        root = nil
        selectedPath = nil
        zoomPath = nil
        trashError = nil
        progress = DiskAnalyzerSupport.Progress(bytes: 0, files: 0, currentPath: "")
        phase = .idle
    }
}
