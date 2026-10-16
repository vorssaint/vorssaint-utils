// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import SwiftUI

/// Shows the prompt as a pinned capture card in the notch island. Main thread only.
final class NotchBreakDelivery: BreakDelivery {
    static let shared = NotchBreakDelivery()
    static let height: CGFloat = 110
    private(set) var liveID: UUID?

    func present(_ prompt: BreakPrompt, respond: @escaping (BreakAction) -> Void) -> Bool {
        let notch = NotchService.shared
        guard notch.showsSystemFeedback else { return false }
        let text = FeatureStrings.breakReminders(L10n.shared.language)
        let generic = prompt.kind == .eyes ? text.eyesGeneric : text.movementGeneric
        let id = prompt.id
        let shown = notch.presentCapture(
            id: id,
            content: AnyView(NotchBreakView(title: prompt.activity?.text ?? generic, seconds: prompt.seconds,
                                            shownAt: Date())),
            actions: AnyView(NotchBreakActions(text: text, respond: respond)),
            height: Self.height, route: .breakReminder, takeFocus: false, pinIsland: true,
            fallback: { [weak self] in
                self?.forget(id)
                BreakReminderService.shared.sinkFailed(id: id, via: .notch)
            },
            close: { [weak self] in
                self?.forget(id)
                BreakReminderService.shared.sinkClosed(id: id)
            },
            hover: { _ in },
            collapsed: { [weak self] in
                self?.forget(id)
                respond(.snooze)
            },
            displaced: { [weak self] in
                self?.forget(id)
                BreakReminderService.shared.sinkDisplaced(id: id, via: .notch)
            })
        if shown { liveID = id }
        return shown
    }

    func dismiss(id: UUID) {
        guard liveID == id else { return }
        liveID = nil
        NotchService.shared.removeCapture(id: id)
    }

    /// The island already let go of the capture; nothing is left to remove.
    private func forget(_ id: UUID) {
        if liveID == id { liveID = nil }
    }
}
