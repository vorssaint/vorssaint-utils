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
                  progress[id] == nil,
                  let publication = NotchDownloadPublication(initial, folder: folder) else { return }
            progress[id] = value
            publications[id] = publication
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
            var completed: [NotchDownloadItem] = []
            if var publication = publications.removeValue(forKey: id),
               let item = publication.item(NotchDownloadProgressSnapshot(removed), folder: folder), item.completed {
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
            guard var publication = publications[id],
                  let item = publication.item(NotchDownloadProgressSnapshot(value), folder: folder) else {
                invalid.append(id)
                continue
            }
            publications[id] = publication
            items.append(item)
        }
        for id in invalid {
            observations.removeValue(forKey: id)
            publications.removeValue(forKey: id)
            progress.removeValue(forKey: id)
        }
        guard !cancellation.isCancelled else { return }
        changed(items, completed)
    }

    func stop() {
        cancellation.cancel()
        queue.async { [self] in
            observations.removeAll()
            progress.removeAll()
            publications.removeAll()
        }
    }
}
