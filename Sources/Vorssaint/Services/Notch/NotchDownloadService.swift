// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import Combine
import Darwin

final class NotchDownloadService: ObservableObject {
    static let shared = NotchDownloadService()

    /// Progress may unpublish on any queue. Only this main-actor boundary
    /// holds the weak UI owner; native callbacks carry a Sendable reference.
    @MainActor private final class ProgressCallbacks {
        weak var owner: NotchDownloadService?
        let generation: UUID

        init(owner: NotchDownloadService, generation: UUID) {
            self.owner = owner
            self.generation = generation
        }

        func published(_ progress: Progress, id: UUID) {
            guard let owner, owner.generation == generation else { return }
            owner.progressObserver?.add(progress, id: id)
        }

        func unpublished(_ id: UUID) {
            guard let owner, owner.generation == generation else { return }
            owner.progressObserver?.remove(id)
        }
    }
    @Published private(set) var items: [NotchDownloadItem] = []
    @Published private(set) var folderName: String?
    @Published private(set) var folderUnavailable = false
    var onArrival: ((NotchDownloadItem) -> Void)?

    private var folder: URL?
    private var securityScope = false
    private var directorySource: DispatchSourceFileSystemObject?
    private var fileSources: [URL: DispatchSourceFileSystemObject] = [:]
    private var subscriber: Any?
    private var progressObserver: NotchDownloadProgressObserver?
    private var progressItems: [NotchDownloadItem] = []
    private var folderItems: [NotchDownloadItem] = []
    private var partials: [URL: NotchPartialDownload] = [:]
    private var finished: [NotchDownloadItem] = []
    private var expiry: DispatchWorkItem?
    private var inactivityExpiry: DispatchWorkItem?
    private var scanWork: DispatchWorkItem?
    private var generation = UUID()
    private var scanning = false
    private var rescan = false
    private var chooser: NSOpenPanel?
    private var chooserID = UUID()
    private let queue = DispatchQueue(label: "com.vorssaint.notch.downloads", qos: .utility)

    private init() {}

    func syncWithPreferences() {
        guard NotchSupport.isEnabled(), AppFeature.notchDownloads.isAvailable,
              UserDefaults.standard.bool(forKey: DefaultsKey.notchDownloadsEnabled),
              NotchSupport.modules().contains(.downloads) else { stop(); return }
        guard folder == nil else { return }
        guard let bookmark = UserDefaults.standard.data(forKey: DefaultsKey.notchDownloadsFolderBookmark) else {
            folderName = nil
            folderUnavailable = false
            return
        }
        var stale = false
        guard let url = try? URL(resolvingBookmarkData: bookmark,
                                 options: [.withSecurityScope, .withoutUI, .withoutMounting],
                                 relativeTo: nil, bookmarkDataIsStale: &stale), !stale else {
            folderUnavailable = true
            return
        }
        start(url)
    }

    func chooseFolder() {
        guard chooser == nil, AppFeature.notchDownloads.isAvailable else { return }
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.directoryURL = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
        panel.message = FeatureStrings.notchFiles(L10n.shared.language).downloadsHint
        let parent = folderPickerParent()
        let beganInNotch = parent != nil
        let requested = UUID()
        chooserID = requested
        chooser = panel
        let completed: (NSApplication.ModalResponse) -> Void = { [weak self, weak panel, weak parent] response in
            guard let self, let panel, self.chooser === panel, self.chooserID == requested else { return }
            self.chooser = nil
            guard !beganInNotch || parent.map(self.canReturnToDownloads) == true else { return }
            if response == .OK, let url = panel.url, AppFeature.notchDownloads.isAvailable {
                do {
                    let data = try url.bookmarkData(options: .withSecurityScope,
                                                    includingResourceValuesForKeys: nil, relativeTo: nil)
                    self.stop()
                    UserDefaults.standard.set(data, forKey: DefaultsKey.notchDownloadsFolderBookmark)
                    UserDefaults.standard.set(true, forKey: DefaultsKey.notchDownloadsEnabled)
                    self.syncWithPreferences()
                    NotchService.shared.syncWithPreferences()
                } catch { self.folderUnavailable = true }
            }
            guard let parent else { return }
            let returnID = self.chooserID
            // Native panel dismissal restores its previous key window after the
            // completion callback. Return on the next turn without changing pin.
            DispatchQueue.main.async { [weak self, weak parent] in
                guard let self, let parent, self.chooserID == returnID, self.chooser == nil,
                      self.canReturnToDownloads(parent) else { return }
                NotchService.shared.open(.downloads, feedback: false)
            }
        }
        if let parent {
            // Attach before activation so the notch's existing sheet handling
            // protects the working surface when another app gives up focus.
            panel.beginSheetModal(for: parent, completionHandler: completed)
            NSApp.activate(ignoringOtherApps: true)
        } else {
            NSApp.activate(ignoringOtherApps: true)
            panel.begin(completionHandler: completed)
        }
    }

    private func folderPickerParent() -> NSWindow? {
        guard let window = NotchService.shared.presentationWindow, canReturnToDownloads(window),
              NSApp.currentEvent?.window === window || NSApp.keyWindow === window else { return nil }
        return window
    }

    private func canReturnToDownloads(_ window: NSWindow) -> Bool {
        let notch = NotchService.shared
        return AppFeature.notchDownloads.isAvailable && NotchSupport.isEnabled()
            && NotchSupport.modules().contains(.downloads) && notch.acceptsSystemFeedback
            && notch.presentationWindow === window && window.isVisible
            && notch.expanded && notch.selected == .downloads && !notch.showingAppPanel
            && notch.selectedMetric == nil && notch.captureControls == nil
    }

    func forgetFolder() {
        stop()
        UserDefaults.standard.removeObject(forKey: DefaultsKey.notchDownloadsFolderBookmark)
        UserDefaults.standard.set(false, forKey: DefaultsKey.notchDownloadsEnabled)
        folderName = nil
        folderUnavailable = false
    }

    private func cancelFolderChoice() {
        chooserID = UUID()
        chooser?.cancel(nil)
        chooser = nil
    }

    func stop() {
        cancelFolderChoice()
        generation = UUID()
        scanWork?.cancel(); scanWork = nil
        expiry?.cancel(); expiry = nil
        inactivityExpiry?.cancel(); inactivityExpiry = nil
        directorySource?.cancel(); directorySource = nil
        fileSources.values.forEach { $0.cancel() }
        fileSources.removeAll()
        progressObserver?.stop(); progressObserver = nil
        progressItems = []
        if let subscriber { Progress.removeSubscriber(subscriber) }
        subscriber = nil
        if let folder, securityScope {
            // Let an already-running file read finish before releasing its scope.
            queue.async { folder.stopAccessingSecurityScopedResource() }
        }
        folder = nil
        securityScope = false
        folderItems.removeAll()
        partials.removeAll()
        finished.removeAll()
        items = []
        scanning = false
        rescan = false
    }

    private func start(_ url: URL) {
        guard url.isFileURL else { folderUnavailable = true; return }
        securityScope = url.startAccessingSecurityScopedResource()
        guard let source = watch(url, directory: true) else {
            if securityScope { url.stopAccessingSecurityScopedResource() }
            securityScope = false
            folderUnavailable = true
            return
        }
        folder = url.standardizedFileURL
        folderName = url.lastPathComponent
        folderUnavailable = false
        directorySource = source
        let requested = generation
        progressObserver = NotchDownloadProgressObserver(folder: url.standardizedFileURL, queue: queue) { [weak self] items, completed in
            DispatchQueue.main.async {
                guard let self, self.generation == requested else { return }
                self.progressItems = items
                completed.forEach(self.recordCompletion)
                self.refreshItems()
            }
        }
        let callbacks = MainActor.assumeIsolated { ProgressCallbacks(owner: self, generation: generation) }
        subscriber = Progress.addSubscriber(forFileURL: url) { published in
            let id = UUID()
            DispatchQueue.main.async {
                callbacks.published(published, id: id)
            }
            return {
                DispatchQueue.main.async {
                    callbacks.unpublished(id)
                }
            }
        }
        scheduleScan()
    }

    private func watch(_ url: URL, directory: Bool) -> DispatchSourceFileSystemObject? {
        let descriptor = open(url.path, O_EVTONLY | O_NOFOLLOW | O_CLOEXEC)
        guard descriptor >= 0 else { return nil }
        let source = DispatchSource.makeFileSystemObjectSource(fileDescriptor: descriptor,
            eventMask: [.write, .extend, .attrib, .rename, .delete, .revoke], queue: .main)
        source.setEventHandler { [weak self] in
            guard let self else { return }
            if directory, let source = self.directorySource,
               !source.data.intersection([.rename, .delete, .revoke]).isEmpty {
                self.stop()
                self.folderUnavailable = true
            } else { self.scheduleScan() }
        }
        source.setCancelHandler { close(descriptor) }
        source.resume()
        return source
    }

    private func scheduleScan() {
        guard folder != nil, scanWork == nil else { return }
        let work = DispatchWorkItem { [weak self] in
            self?.scanWork = nil
            self?.scan()
        }
        scanWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: work)
    }

    private func scan() {
        guard let folder else { return }
        guard !scanning else { rescan = true; return }
        scanning = true
        let id = generation
        let previous = partials
        queue.async { [weak self] in
            let current = NotchDownloadSupport.scanFolder(folder)
            let completed = previous.values.compactMap { old -> NotchDownloadItem? in
                guard current?.partials[old.url] == nil,
                      !FileManager.default.fileExists(atPath: old.url.path),
                      let values = try? old.expectedURL.resourceValues(forKeys: NotchDownloadSupport.keys),
                      values.isRegularFile == true,
                      NotchDownloadSupport.didFinish(old, at: old.expectedURL,
                          resourceID: NotchDownloadSupport.fileIdentity(at: old.expectedURL)) else { return nil }
                return NotchDownloadItem(id: old.expectedURL.path, url: old.expectedURL,
                    name: old.expectedURL.lastPathComponent, receivedBytes: Int64(values.fileSize ?? 0),
                    fraction: 1, completed: true, active: false, date: Date())
            }
            DispatchQueue.main.async {
                guard let self, self.generation == id else { return }
                self.scanning = false
                guard let current else {
                    self.stop(); self.folderUnavailable = true; return
                }
                self.partials = current.partials
                self.folderItems = current.files
                let watched = Set(current.partials.values.flatMap { [$0.url] + [$0.contentURL].compactMap { $0 } })
                let removed = Set(self.fileSources.keys).subtracting(watched)
                for url in removed { self.fileSources.removeValue(forKey: url)?.cancel() }
                for url in watched where self.fileSources[url] == nil {
                    self.fileSources[url] = self.watch(url, directory: false)
                }
                completed.forEach(self.recordCompletion)
                self.progressObserver?.requestRefresh()
                self.refreshItems()
                if self.rescan { self.rescan = false; self.scheduleScan() }
            }
        }
    }

    private func recordCompletion(_ item: NotchDownloadItem) {
        guard !finished.contains(where: { $0.id == item.id }) else { return }
        finished.insert(item, at: 0)
        finished = Array(finished.prefix(5))
        onArrival?(item)
        expiry?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.finished.removeAll(); self?.expiry = nil; self?.refreshItems()
        }
        expiry = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 15, execute: work)
    }

    private func refreshItems() {
        guard folder != nil else { return }
        inactivityExpiry?.cancel(); inactivityExpiry = nil
        if let next = partials.values.map({ $0.modified.addingTimeInterval(120) })
            .filter({ $0 > Date() }).min() {
            let work = DispatchWorkItem { [weak self] in self?.refreshItems() }
            inactivityExpiry = work
            DispatchQueue.main.asyncAfter(deadline: .now() + max(0.1, next.timeIntervalSinceNow), execute: work)
        }
        var active = progressItems
        var seen = Set<String>()
        active = active.filter { seen.insert($0.id).inserted }
        let represented = Set(active.map { $0.url.standardizedFileURL })
        for partial in partials.values where !represented.contains(partial.url.standardizedFileURL)
            && !represented.contains(partial.expectedURL.standardizedFileURL) {
            active.append(NotchDownloadItem(id: partial.url.path, url: partial.url,
                name: partial.expectedURL.lastPathComponent, receivedBytes: partial.bytes,
                fraction: nil, completed: false, active: Date().timeIntervalSince(partial.modified) < 120,
                date: partial.modified))
        }
        let updated = NotchDownloadSupport.mergedItems(active: active, files: folderItems, finished: finished)
        if items != updated { items = updated }
    }
}
