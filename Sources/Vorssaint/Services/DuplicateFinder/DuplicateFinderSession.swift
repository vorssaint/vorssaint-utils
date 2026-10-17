// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import Combine

final class DuplicateFinderSession: ObservableObject {
    @Published private(set) var roots: [URL] = []
    @Published private(set) var report: DuplicateFinderSupport.Report?
    @Published private(set) var progress: DuplicateFinderSupport.Progress?
    @Published private(set) var outcomes: [DuplicateFinderSupport.Outcome] = []
    @Published private(set) var busy = false
    @Published var selection: Set<URL> = []
    @Published var preview: DuplicateFinderSupport.File?
    @Published var confirmation = false
    private var confirmed: Set<URL> = []
    private var scopes: [URL] = []
    private var cancellation = DuplicateFinderSupport.Cancellation()
    private var closed = false
    private let queue = DispatchQueue(label: "com.vorssaint.duplicate-finder", qos: .userInitiated)

    var selectedFiles: [DuplicateFinderSupport.File] {
        (report?.groups ?? []).flatMap(\.files).filter { selection.contains($0.url) }
    }
    var selectedBytes: Int64 { selectedFiles.reduce(0) { DuplicateFinderSupport.saturatingAdd($0, $1.identity.size) } }
    var canTrash: Bool {
        !busy && !closed && AppFeature.duplicateFinder.isAvailable && DuplicateFinderSupport.validSelection(selection, groups: report?.groups ?? [])
    }
    func addFolders() {
        guard !busy, !closed, AppFeature.duplicateFinder.isAvailable else { return }
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true; panel.canChooseFiles = false
        panel.allowsMultipleSelection = true; panel.canCreateDirectories = false
        panel.prompt = FeatureStrings.duplicateFinder(L10n.shared.language).add
        if panel.runModal() == .OK, !closed, AppFeature.duplicateFinder.isAvailable {
            setRoots(roots + panel.urls)
        }
    }
    func setRoots(_ urls: [URL]) {
        guard !busy, !closed, AppFeature.duplicateFinder.isAvailable else { return }
        let normalized = DuplicateFinderSupport.normalizedRoots(urls)
        // Acquire new scope before releasing old scope when changing roots.
        let newScopes = normalized.filter { $0.startAccessingSecurityScopedResource() }
        scopes.forEach { $0.stopAccessingSecurityScopedResource() }
        scopes = newScopes; roots = normalized
        report = nil; selection = []; preview = nil; outcomes = []; confirmation = false; confirmed = []
    }
    func remove(_ root: URL) {
        guard !busy, !closed else { return }
        setRoots(roots.filter { $0 != root })
    }
    func select(_ file: DuplicateFinderSupport.File, enabled: Bool) {
        guard !busy, !closed, !confirmation else { return }
        var next = selection
        if enabled { next.insert(file.url) } else { next.remove(file.url) }
        guard next.isEmpty || DuplicateFinderSupport.validSelection(next, groups: report?.groups ?? []) else { return }
        selection = next
    }
    func scan() {
        guard !busy, !roots.isEmpty, !closed, AppFeature.duplicateFinder.isAvailable else { return }
        report = nil; selection = []; preview = nil; outcomes = []; confirmed = []; confirmation = false
        busy = true; progress = nil; cancellation = .init()
        let roots = roots, token = cancellation
        queue.async {
            let report = DuplicateFinderSupport.scan(roots: roots, cancellation: token) { value in
                DispatchQueue.main.async {
                    guard !self.closed, self.cancellation === token else { return }
                    self.progress = value
                }
            }
            DispatchQueue.main.async {
                self.busy = false; self.progress = nil
                if self.closed { self.releaseScopes() }
                else if AppFeature.duplicateFinder.isAvailable { self.report = report }
            }
        }
    }
    func review() {
        guard canTrash else { return }
        confirmed = selection; confirmation = true
    }
    func dismissReview() { confirmation = false; confirmed = [] }
    func trashConfirmed() {
        guard confirmation, confirmed == selection, canTrash else { dismissReview(); return }
        let groups = report?.groups ?? [], frozen = confirmed
        confirmation = false; confirmed = []; preview = nil; busy = true; cancellation = .init()
        let token = cancellation
        queue.async {
            let results = DuplicateFinderSupport.trash(selection: frozen, groups: groups, cancellation: token)
            DispatchQueue.main.async {
                self.busy = false
                if self.closed { self.releaseScopes(); return }
                guard AppFeature.duplicateFinder.isAvailable else { return }
                self.outcomes = results; self.selection = []
                let moved = Set(results.filter(\.moved).map { $0.file.url })
                // A failed or changed group must be rescanned before another move.
                let affected = Set(results.map { $0.file.url })
                self.report?.groups = groups.compactMap { group in
                    guard !group.files.contains(where: { affected.contains($0.url) && !moved.contains($0.url) }) else { return nil }
                    let remaining = group.files.filter { !moved.contains($0.url) }
                    return remaining.count > 1 ? .init(files: remaining) : nil
                }
            }
        }
    }
    func cancel() { cancellation.cancel() }
    func close() {
        closed = true; cancel(); dismissReview(); selection = []; preview = nil; report = nil; outcomes = []
        if !busy { releaseScopes() }
    }
    private func releaseScopes() {
        scopes.forEach { $0.stopAccessingSecurityScopedResource() }; scopes = []; roots = []
    }
}
