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
        let succeeded: Bool
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
        pendingWorkItem?.cancel()
        execute(link: link, argument: argument)
    }

    private func execute(link: CommandBarLink, argument: String) {
        let cacheKey = key(link.id, argument)
        inFlight.insert(cacheKey)
        DispatchQueue.global(qos: .userInitiated).async {
            let (status, output) = Shell.run(link.destination, [argument])
            let text = CommandBarLinks.resultText(output)
            // The hop back happens whatever the script printed: a run that
            // ends with nothing to show still has to stop counting as one in
            // flight, or that key would never be runnable again.
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.inFlight.remove(cacheKey)
                guard let text else { return }
                self.cache[cacheKey] = Result(text: text, succeeded: status == 0)
                self.onResult?()
            }
        }
    }

    private func key(_ linkID: UUID, _ argument: String) -> String {
        "\(linkID.uuidString)|\(argument)"
    }
}
