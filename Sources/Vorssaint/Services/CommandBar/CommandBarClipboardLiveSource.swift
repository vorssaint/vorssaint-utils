// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Combine
import Foundation

/// Clipboard history as a command bar live source: a new copy or an edit
/// changes the rows, and the history's deeper scan can replace the quick
/// ranking a moment later.
final class CommandBarClipboardLiveSource: CommandBarLiveSource {
    private let history: ClipboardHistoryService
    private var subscription: AnyCancellable?
    private var onChange: (() -> Void)?

    init(history: ClipboardHistoryService) {
        self.history = history
    }

    func start(onChange: @escaping () -> Void) {
        self.onChange = onChange
        // Published entries change before their didSet invalidates the search
        // caches; the bar's debounce delivers the refresh after that turn.
        subscription = history.$entries.dropFirst()
            .sink { [weak self] _ in self?.onChange?() }
    }

    func cancel() {
        onChange = nil
        subscription = nil
        history.cancelSearch(on: .commandBar)
    }

    /// The history found a fuller result for the same query off-main.
    func notifyChange() {
        onChange?()
    }
}
