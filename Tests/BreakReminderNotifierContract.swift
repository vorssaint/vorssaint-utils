// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// setNotificationCategories replaces every category, so it may be called
/// from exactly one place, which registers WhatsApp and break categories together.
enum BreakReminderNotifierContract {
    static func run(_ suite: TestSuite) {
        let source = (try? String(contentsOfFile: "Sources/Vorssaint/Services/Notifier.swift", encoding: .utf8)) ?? ""
        suite.expect(!source.isEmpty, "Notifier.swift is readable from the repo root")
        let calls = source.components(separatedBy: "setNotificationCategories(").count - 1
        suite.expect(calls == 1, "setNotificationCategories is called exactly once")
        guard let range = source.range(of: "static func registerCategories(") else {
            suite.expect(false, "registerCategories exists"); return
        }
        let body = source[range.lowerBound...].prefix(1500)
        suite.expect(body.contains("setNotificationCategories(") && body.contains("whatsAppOrganizerCategoryIdentifier")
                     && body.contains("breakCategoryIdentifier"),
                     "registerCategories registers both categories")
        suite.expect(body.contains(".customDismissAction"), "the break category reports swipe-away dismissals")
    }
}
