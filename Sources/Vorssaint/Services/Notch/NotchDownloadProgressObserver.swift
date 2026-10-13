// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// Native observations and file evidence share the existing download queue.
/// Only immutable display values leave it; stopping never waits for file I/O.
final class NotchDownloadProgressObserver {
    private let folder: URL
    private let queue: DispatchQueue
    private let changed: ([NotchDownloadItem], [NotchDownloadItem]) -> Void
    private let cancellation = DispatchWorkItem {}
    private let refreshLock = NSLock()
    private var refreshQueued = false // Protected by refreshLock, including native callbacks.
    // Everything below is confined to queue.
    private var progress: [UUID: Progress] = [:]
    private var publications: [UUID: NotchDownloadPublication] = [:]
    private var observations: [UUID: [NSKeyValueObservation]] = [:]
    private var sources: [UUID: NotchDownloadSource] = [:]
    private var finishedSources: [NotchDownloadSource: Date] = [:]

    init(folder: URL, queue: DispatchQueue,
         changed: @escaping ([NotchDownloadItem], [NotchDownloadItem]) -> Void) {
        self.folder = folder
        self.queue = queue
        self.changed = changed
    }

    func add(_ value: Progress, id: UUID) {
        let initial = NotchDownloadProgressSnapshot(value)
        queue.async { [self] in
            guard !cancellation.isCancelled, progress.count < NotchDownloadSupport.maximumObservedFiles,
                  progress[id] == nil else { return }
            if initial.fileURL != nil, initial.fileOperationKind != nil {
                guard let publication = NotchDownloadPublication(initial, folder: folder) else { return }
                publications[id] = publication
                sources[id] = source(of: value, matching: initial)
            }
            progress[id] = value
            let update: () -> Void = { [weak self] in self?.requestRefresh() }
            observations[id] = [
                value.observe(\.fractionCompleted) { _, _ in update() },
                value.observe(\.isPaused) { _, _ in update() },
                value.observe(\.isCancelled) { _, _ in update() },
                value.observe(\.isFinished) { _, _ in update() },
                // File metadata lives in userInfo. Foundation notifies the
                // dependent descriptions, not the fileURL convenience getter.
                value.observe(\.localizedDescription) { _, _ in update() },
                value.observe(\.localizedAdditionalDescription) { _, _ in update() },
            ]
            requestRefresh()
        }
    }

    func requestRefresh() {
        refreshLock.lock()
        guard !cancellation.isCancelled, !refreshQueued else { refreshLock.unlock(); return }
        refreshQueued = true
        refreshLock.unlock()
        queue.asyncAfter(deadline: .now() + 0.05) { [weak self] in
            guard let self else { return }
            self.refreshLock.lock()
            self.refreshQueued = false
            self.refreshLock.unlock()
            self.refresh()
        }
    }

    func remove(_ id: UUID) {
        queue.async { [self] in
            guard !cancellation.isCancelled, let removed = progress.removeValue(forKey: id) else { return }
            observations.removeValue(forKey: id)
            let snapshot = NotchDownloadProgressSnapshot(removed)
            rememberCompletion(id, snapshot: snapshot)
            var completed: [NotchDownloadItem] = []
            if var publication = publications.removeValue(forKey: id),
               let item = publication.item(snapshot, folder: folder), item.completed {
                completed = [item]
            }
            refresh(completed: completed)
        }
    }

    private func refresh(completed: [NotchDownloadItem] = []) {
        var items: [NotchDownloadItem] = []
        var invalid: [UUID] = []
        for (id, value) in progress {
            guard !cancellation.isCancelled else { return }
            let snapshot = NotchDownloadProgressSnapshot(value)
            if publications[id] == nil {
                // A publication from another app, like Safari, arrives a moment
                // before its file URL and kind. Judge it once they are here.
                guard snapshot.fileURL != nil, snapshot.fileOperationKind != nil else {
                    if snapshot.isFinished || snapshot.isCancelled { invalid.append(id) }
                    continue
                }
                publications[id] = NotchDownloadPublication(snapshot, folder: folder)
                if publications[id] != nil {
                    sources[id] = source(of: value, matching: snapshot)
                }
            }
            guard var publication = publications[id],
                  let item = publication.item(snapshot, folder: folder) else {
                invalid.append(id)
                continue
            }
            publications[id] = publication
            items.append(item)
        }
        for id in invalid {
            if let value = progress[id] {
                rememberCompletion(id, snapshot: NotchDownloadProgressSnapshot(value))
            }
            observations.removeValue(forKey: id)
            publications.removeValue(forKey: id)
            progress.removeValue(forKey: id)
        }
        guard !cancellation.isCancelled else { return }
        changed(items, completed)
    }

    /// Called by the folder scan on this same queue. A browser's final path
    /// can name an extracted folder, so only the original publisher can prove
    /// that its missing partial finished instead of being cancelled.
    func didFinish(_ partial: NotchPartialDownload, at now: Date = Date()) -> Bool {
        dispatchPrecondition(condition: .onQueue(queue))
        guard !cancellation.isCancelled, let source = partial.source else { return false }
        finishedSources = finishedSources.filter { now.timeIntervalSince($0.value) < 5 }
        var observed = false
        for (id, original) in sources where original == source {
            guard let value = progress[id] else { continue }
            observed = true
            guard finished(NotchDownloadProgressSnapshot(value)) else { return false }
        }
        return observed || finishedSources[source] != nil
    }

    private func finished(_ snapshot: NotchDownloadProgressSnapshot) -> Bool {
        snapshot.isFinished && !snapshot.isCancelled
            && NotchDownloadSupport.publishedURL(snapshot, folder: folder) != nil
    }

    private func source(of value: Progress, matching initial: NotchDownloadProgressSnapshot) -> NotchDownloadSource? {
        let current = NotchDownloadProgressSnapshot(value)
        guard !current.isFinished, !current.isCancelled,
              let url = NotchDownloadSupport.publishedURL(current, folder: folder),
              url == NotchDownloadSupport.publishedURL(initial, folder: folder) else { return nil }
        let source = NotchDownloadSupport.partialSource(at: url)
        let latest = NotchDownloadProgressSnapshot(value)
        guard !latest.isFinished, !latest.isCancelled,
              NotchDownloadSupport.publishedURL(latest, folder: folder) == url else { return nil }
        return source
    }

    private func rememberCompletion(_ id: UUID, snapshot: NotchDownloadProgressSnapshot) {
        guard let source = sources.removeValue(forKey: id) else { return }
        finishedSources.removeValue(forKey: source)
        guard finished(snapshot) else { return }
        let now = Date()
        finishedSources = finishedSources.filter { now.timeIntervalSince($0.value) < 5 }
        finishedSources[source] = now
        if finishedSources.count > NotchDownloadSupport.maximumObservedFiles,
           let oldest = finishedSources.min(by: { $0.value < $1.value })?.key {
            finishedSources.removeValue(forKey: oldest)
        }
    }

    func stop() {
        cancellation.cancel()
        queue.async { [self] in
            observations.removeAll()
            progress.removeAll()
            publications.removeAll()
            sources.removeAll()
            finishedSources.removeAll()
        }
    }
}
