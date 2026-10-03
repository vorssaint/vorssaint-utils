// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import SwiftUI

/// Exercise the production owner with real, hidden windows. No media or network.
enum GeminiLiveWindowTests {
    enum AppFeature {
        case geminiLive
        static var available = true
        var isAvailable: Bool { Self.available }
    }
    final class SessionActivity {
        static let shared = SessionActivity()
        var isActive = true
    }
    @MainActor final class GeminiLiveService {
        static let shared = GeminiLiveService()
        enum State { case idle, live }
        var state = State.idle
        var stops = 0
        func start(apiKey: String) { state = .live }
        func stop() { stops += 1; state = .idle }
    }
    enum WindowActivationPolicy {
        static var retained = 0
        static func retain() { retained += 1 }
        static func release() { retained -= 1 }
    }
    enum GeminiLiveKeyStore { static func load() throws -> String { "synthetic-test-key" } }
    struct GeminiLiveSetupView: View {
        let initialKey: String?
        var body: some View { EmptyView() }
    }
    static func run(_ suite: TestSuite) {
        MainActor.assumeIsolated {
            let owner = GeminiLiveController()
            AppFeature.available = false
            owner.show()
            suite.expect(owner.window == nil, "disabled Gemini cannot open a conversation")
            AppFeature.available = true
            SessionActivity.shared.isActive = false
            owner.show()
            suite.expect(owner.window == nil, "locked sessions cannot open Gemini")
            SessionActivity.shared.isActive = true
            owner.toggle()
            suite.expect(owner.window == nil && GeminiLiveService.shared.state == .live,
                         "a saved key starts voice without opening a chat window")
            owner.toggle()
            suite.expect(owner.window == nil && GeminiLiveService.shared.state == .idle,
                         "clicking Gemini again stops voice with the launcher collapsed")
            let window = NSWindow()
            window.isReleasedWhenClosed = false
            window.delegate = owner
            owner.window = window
            WindowActivationPolicy.retain()
            let stops = GeminiLiveService.shared.stops
            owner.windowWillClose(Notification(name: NSWindow.willCloseNotification, object: NSWindow()))
            suite.expect(owner.window === window && GeminiLiveService.shared.stops == stops,
                         "unrelated window closure does not end the conversation")
            owner.start(apiKey: "synthetic-test-key")
            suite.expect(owner.window == nil && GeminiLiveService.shared.state == .live
                         && WindowActivationPolicy.retained == 0 && GeminiLiveService.shared.stops == stops,
                         "starting from key setup closes the window and keeps voice running")
            owner.close()
            suite.expect(owner.window == nil && GeminiLiveService.shared.stops == stops + 1
                         && WindowActivationPolicy.retained == 0,
                         "native conversation close stops media and releases window retention")
            owner.windowWillClose(Notification(name: NSWindow.willCloseNotification, object: window))
            suite.expect(WindowActivationPolicy.retained == 0 && GeminiLiveService.shared.stops == stops + 1,
                         "duplicate close notifications cannot release another window's retention")
        }
    }
}
