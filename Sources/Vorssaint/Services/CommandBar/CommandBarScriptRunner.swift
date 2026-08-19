// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// Runs a saved script link's command in the background, debounced so typing
/// does not spawn a process per keystroke, and cached by exactly what was
/// typed so a later keystroke never overwrites the screen with a stale
/// answer meant for a different query.
///
/// Not part of the pure-function test harness (`./build.sh --test`): the
/// behavior here is a background process and a timer, not a calculation.
/// Verified by hand against a real saved script link instead.
final class CommandBarScriptRunner {
    struct Result: Equatable {
        let text: String
    }

    /// How long the query has to sit still before a script actually runs.
    static let debounce: TimeInterval = 0.25

    /// Called on the main thread whenever a result becomes ready, so the
    /// caller can refresh what is on screen.
    var onResult: (() -> Void)?

    private var cache: [String: Result] = [:]
    /// The keys whose process is running right now. Without it, a script
    /// slower than the debounce would be launched again by the next refresh
    /// while the first one is still going, since nothing is cached yet.
    /// Touched only from the main thread, like the cache, so it needs no lock.
    private var inFlight: Set<String> = []
    private var pendingWorkItem: DispatchWorkItem?
    private var generation = 0

    /// A result only belongs to the current opening of the bar. Clearing the
    /// session also prevents delayed work from a closed bar from publishing a
    /// stale answer when it opens again.
    func reset() {
        generation &+= 1
        cancelPending()
        cache.removeAll()
        inFlight.removeAll()
    }

    /// A query that no longer names a script must not leave its delayed run
    /// behind. Work already executing is bounded by Shell's timeout and its
    /// result is ignored unless this opening still owns it.
    func cancelPending() {
        pendingWorkItem?.cancel()
        pendingWorkItem = nil
    }

    /// The answer for this exact link and argument, if the script already
    /// ran for it.
    func cachedResult(linkID: UUID, argument: String) -> Result? {
        cache[key(linkID, argument)]
    }

    /// Schedules a debounced run, replacing whatever was pending. Does
    /// nothing when a result is already cached for this exact link and
    /// argument, or when that same run is still going.
    func schedule(link: CommandBarLink, argument: String) {
        guard cachedResult(linkID: link.id, argument: argument) == nil,
              !inFlight.contains(key(link.id, argument)) else { return }
        pendingWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in self?.execute(link: link, argument: argument) }
        pendingWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.debounce, execute: workItem)
    }

    /// Runs at once instead of waiting out the debounce, for the moment
    /// Return is pressed before a result exists yet.
    func runNow(link: CommandBarLink, argument: String) {
        guard cachedResult(linkID: link.id, argument: argument) == nil,
              !inFlight.contains(key(link.id, argument)) else { return }
        cancelPending()
        execute(link: link, argument: argument)
    }

    private func execute(link: CommandBarLink, argument: String) {
        let cacheKey = key(link.id, argument)
        let runGeneration = generation
        let path = (link.destination as NSString).expandingTildeInPath
        inFlight.insert(cacheKey)
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let (status, output) = Shell.run(path, [argument], maxOutputBytes: 64 * 1024)
            let text = CommandBarLinks.resultText(output)
            // The hop back happens whatever the script printed: a run that
            // ends with nothing to show still has to stop counting as one in
            // flight, or that key would never be runnable again.
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                guard self.generation == runGeneration else { return }
                self.inFlight.remove(cacheKey)
                guard let text = text ?? (status == 0 ? nil : self.failureText) else { return }
                self.cache[cacheKey] = Result(text: text)
                self.onResult?()
            }
        }
    }

    private var failureText: String {
        FeatureStrings.commandBar(L10n.shared.language).scriptRunFailed
    }

    private func key(_ linkID: UUID, _ argument: String) -> String {
        "\(linkID.uuidString)|\(argument)"
    }
}
