// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// Runs a saved script link's command in the background, debounced so typing
/// does not spawn a process per keystroke, and cached by exactly what was
/// typed so a later keystroke never overwrites the screen with a stale
/// answer meant for a different query.
///
/// The behavior here is a background process and a timer, not a
/// calculation, so the command bar tests run a copy of it against small
/// scripts they write instead of checking it as a pure function.
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
    /// What to do with a run's answer once it lands, keyed like the cache.
    /// It holds one at most: the bar copies one answer and closes once, so
    /// only the last Return on a script row decides what happens.
    private var answerHandlers: [String: (Result) -> Void] = [:]
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
        answerHandlers.removeAll()
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
    /// Return is pressed before a result exists yet. `whenAnswered` gets the
    /// result once it lands, also when that same run was already going. It
    /// takes the place of one given for an earlier run, and a Return that
    /// waits for the answer row instead drops that one; it is dropped with
    /// the rest of the session when the bar closes.
    func runNow(link: CommandBarLink, argument: String,
                whenAnswered: ((Result) -> Void)? = nil) {
        guard cachedResult(linkID: link.id, argument: argument) == nil else { return }
        let cacheKey = key(link.id, argument)
        answerHandlers = whenAnswered.map { [cacheKey: $0] } ?? [:]
        guard !inFlight.contains(cacheKey) else { return }
        cancelPending()
        execute(link: link, argument: argument)
    }

    /// A run waits out its debounce or is going.
    var isAwaiting: Bool { pendingWorkItem != nil || !inFlight.isEmpty }

    private func execute(link: CommandBarLink, argument: String) {
        pendingWorkItem = nil
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
                let whenAnswered = self.answerHandlers.removeValue(forKey: cacheKey)
                guard let text = text ?? (status == 0 ? nil : self.failureText) else { return }
                let result = Result(text: text)
                self.cache[cacheKey] = result
                self.onResult?()
                whenAnswered?(result)
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
