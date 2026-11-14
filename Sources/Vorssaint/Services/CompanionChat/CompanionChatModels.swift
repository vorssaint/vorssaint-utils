// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// one line in the chat, memory only
struct CompanionMessage: Identifiable, Equatable {
    let id: String
    let isUser: Bool
    let text: String
}

enum CompanionFailure: Error { case missing, unavailable, uncertain, malformed }

/// where checks look + what they read, real mac in the app, fake stuff in tests
struct CompanionContext {
    var home = FileManager.default.homeDirectoryForCurrentUser
    var defaults = UserDefaults.standard
    var environment = ProcessInfo.processInfo.environment
}
