// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// Something that can change the bar's rows after they were built: a new
/// clipboard copy, a finished file search. The bar owns the subscription and
/// the debounce; a source only says when its rows changed and how to stop.
protocol CommandBarLiveSource: AnyObject {
    /// Starts watching and calls `onChange` whenever the rows may differ.
    /// Called once each time the source is registered.
    func start(onChange: @escaping () -> Void)
    /// Stops watching and any work the source started. Called exactly once per
    /// registration, so a missed hook cannot leave it running after the bar.
    func cancel()
}

/// Every live source the open bar has, in one list, behind one debounce and
/// one refresh. Closing the bar or changing the query calls `stopAll()`, which
/// cancels each registered source once; a late change afterwards is ignored.
final class CommandBarLiveSources {
    /// What the per-source clipboard debounce was: changes that arrive
    /// together (one copy, one edit) refresh the list once.
    static let debounce: TimeInterval = 0.015

    typealias Scheduler = (_ delay: TimeInterval, _ work: @escaping () -> Void) -> Void

    private let debounce: TimeInterval
    private let scheduler: Scheduler
    private let refresh: () -> Void
    private var sources: [CommandBarLiveSource] = []
    private var generation = 0
    private var pendingGeneration = 0

    init(debounce: TimeInterval = CommandBarLiveSources.debounce,
         scheduler: @escaping Scheduler = CommandBarLiveSources.scheduleOnMain,
         refresh: @escaping () -> Void) {
        self.debounce = debounce
        self.scheduler = scheduler
        self.refresh = refresh
    }

    var registeredCount: Int { sources.count }
    var isEmpty: Bool { sources.isEmpty }

    /// One source per feature: registering the same one again is a no-op, so
    /// rebuilding the rows on every keystroke does not resubscribe it.
    func register(_ source: CommandBarLiveSource) {
        guard !sources.contains(where: { $0 === source }) else { return }
        sources.append(source)
        source.start { [weak self] in self?.changed() }
    }

    /// A source says its rows may differ now. Only the newest change in a
    /// burst reaches `refresh`, and only while the source is registered.
    func changed() {
        guard !sources.isEmpty else { return }
        generation &+= 1
        let token = generation
        pendingGeneration = token
        scheduler(debounce) { [weak self] in
            guard let self, self.pendingGeneration == token else { return }
            self.pendingGeneration = 0
            self.refresh()
        }
    }

    /// Stops every registered source exactly once. Pending debounce work and
    /// any change a source still delivers afterwards do nothing.
    func stopAll() {
        generation &+= 1
        pendingGeneration = 0
        let stopped = sources
        sources.removeAll()
        stopped.forEach { $0.cancel() }
    }

    private static func scheduleOnMain(_ delay: TimeInterval, _ work: @escaping () -> Void) {
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }
}
