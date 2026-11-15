// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import Combine
import Foundation

/// Scans a chosen folder into a size tree and owns selection / zoom / trash
/// for the Disk Analyzer panel workspace.
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
    /// Bumped when Command Bar (or another launcher) should open the panel host.
    @Published private(set) var panelPresentationID = 0
    /// Non-nil while Utilities hosts Disk Analyzer in the Dynamic Island and
    /// a scan has results, so the island can grow past the usual page budget.
    @Published private(set) var islandContentHeight: CGFloat?
    @Published var includeHidden: Bool {
        didSet { UserDefaults.standard.set(includeHidden, forKey: DefaultsKey.diskAnalyzerIncludeHidden) }
    }
    @Published var confirmTrash: Bool {
        didSet { UserDefaults.standard.set(confirmTrash, forKey: DefaultsKey.diskAnalyzerConfirmTrash) }
    }
    @Published var showItemList: Bool {
        didSet { UserDefaults.standard.set(showItemList, forKey: DefaultsKey.diskAnalyzerShowItemList) }
    }
    /// How many nested box levels the treemap draws under the current folder.
    @Published var nestingDepth: Int {
        didSet {
            let clamped = min(4, max(1, nestingDepth))
            if clamped != nestingDepth { nestingDepth = clamped; return }
            UserDefaults.standard.set(clamped, forKey: DefaultsKey.diskAnalyzerNestingDepth)
        }
    }

    private var cancellation: DiskAnalyzerSupport.ScanCancellation?
    private let worker = DispatchQueue(label: "com.vorssaint.utils.disk-analyzer", qos: .userInitiated)
    private var lastRootURL: URL?
    /// True while Utilities is showing Disk Analyzer (island or menu panel).
    /// Lives on the service so island resizes that recreate SwiftUI state
    /// cannot drop the open tool or clear the taller content height.
    @Published private(set) var isPresentedInUtilities = false

    private init() {
        let defaults = UserDefaults.standard
        includeHidden = defaults.object(forKey: DefaultsKey.diskAnalyzerIncludeHidden) as? Bool ?? false
        confirmTrash = defaults.object(forKey: DefaultsKey.diskAnalyzerConfirmTrash) as? Bool ?? true
        showItemList = defaults.object(forKey: DefaultsKey.diskAnalyzerShowItemList) as? Bool ?? true
        let depth = defaults.object(forKey: DefaultsKey.diskAnalyzerNestingDepth) as? Int ?? 3
        nestingDepth = min(4, max(1, depth))
    }

    /// Ask the menu panel / island to host Disk Analyzer in Utilities.
    func presentInMenuPanel() {
        panelPresentationID &+= 1
        appDelegate()?.openUtilitiesPanel()
    }

    /// Open or close Disk Analyzer inside Utilities. Growing the island is
    /// gated separately on `NotchService.showingAppPanel`.
    func setPresentedInUtilities(_ presented: Bool) {
        guard isPresentedInUtilities != presented else {
            publishIslandContentHeight()
            return
        }
        isPresentedInUtilities = presented
        publishIslandContentHeight()
    }

    private func publishIslandContentHeight() {
        let notch = NotchService.shared
        let hostedInIsland = isPresentedInUtilities && notch.expanded && notch.showingAppPanel
        let next: CGFloat?
        if hostedInIsland, phase == .ready, root != nil {
            next = DiskAnalyzerSupport.islandResultsContentHeight
        } else {
            next = nil
        }
        guard islandContentHeight != next else { return }
        islandContentHeight = next
        notch.refreshPresentation()
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
        publishIslandContentHeight()

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
                    self.publishIslandContentHeight()
                    return
                }
                guard let tree else {
                    self.phase = .failed(FeatureStrings.diskAnalyzer(L10n.shared.language).scanFailed)
                    self.publishIslandContentHeight()
                    return
                }
                self.progress.bytes = tree.size
                self.root = tree
                self.zoomPath = tree.path
                self.phase = .ready
                self.publishIslandContentHeight()
            }
        }
    }

    func rescan() {
        guard let lastRootURL else { return }
        scan(url: lastRootURL)
    }

    /// Return to the folder / drive picker without keeping the current tree.
    func startNewScan() {
        cancellation?.cancel()
        cancellation = nil
        lastRootURL = nil
        root = nil
        selectedPath = nil
        zoomPath = nil
        trashError = nil
        progress = DiskAnalyzerSupport.Progress(bytes: 0, files: 0, currentPath: "")
        phase = .idle
        publishIslandContentHeight()
    }

    func cancel() {
        cancellation?.cancel()
        cancellation = nil
        if phase == .scanning {
            phase = root == nil ? .idle : .ready
            publishIslandContentHeight()
        }
    }

    func select(path: String?) {
        selectedPath = path
        trashError = nil
    }

    func zoom(to path: String?) {
        guard let root else { return }
        if let path,
           let node = DiskAnalyzerSupport.node(at: path, in: root),
           node.isDirectory,
           !node.isAggregate {
            zoomPath = path
            selectedPath = path
        } else if path == nil {
            zoomPath = root.path
            selectedPath = nil
        }
    }

    func zoomIntoSelection() {
        guard let node = selectedNode, node.isDirectory, !node.isAggregate else { return }
        zoom(to: node.path)
    }

    func revealSelection() {
        guard let node = selectedNode, !node.isAggregate else { return }
        NSWorkspace.shared.activateFileViewerSelecting([node.url])
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
        publishIslandContentHeight()
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
        publishIslandContentHeight()
    }
}
