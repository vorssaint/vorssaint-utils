// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppIntents
import Foundation

struct StartPomodoroIntent: AppIntent {
    static let title = LocalizedStringResource("Start Pomodoro", table: "AppIntents")
    static let description = IntentDescription(
        LocalizedStringResource("Starts the Dynamic Island Pomodoro timer using your saved settings.", table: "AppIntents"))
    static let openAppWhenRun = false

    @MainActor
    func perform() async throws -> some IntentResult {
        await NotchTimerAutomation.shared.waitForStartup()
        try Task.checkCancellation()
        guard NotchTimerSupport.isEnabled(),
              NotchTimerService.shared.start(mode: .pomodoro) != .unavailable else {
            throw Failure.timerUnavailable
        }
        return .result()
    }

    private enum Failure: LocalizedError {
        case timerUnavailable

        var errorDescription: String? {
            String(localized: "The Dynamic Island timer is currently unavailable.", table: "AppIntents")
        }
    }
}
