// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import SwiftUI

// Stand-ins for the services the window controller talks to. The probe
// compiles the production controller itself, not a copy of it.
enum AppLanguage { case enUS }

final class L10n {
    static let shared = L10n()
    var language: AppLanguage = .enUS
}

struct CommandBarFeatureStrings {
    let appCenterTitle: String
}

enum FeatureStrings {
    static func commandBar(_ language: AppLanguage) -> CommandBarFeatureStrings {
        CommandBarFeatureStrings(appCenterTitle: "App shortcuts")
    }
}

final class CommandBarService {
    static let shared = CommandBarService()
    private(set) var refreshCount = 0

    func refreshApplications() {
        refreshCount += 1
    }
}

enum WindowActivationPolicy {
    private(set) static var retentionCount = 0

    static func retain() { retentionCount += 1 }
    static func release() { retentionCount -= 1 }
}

struct CommandBarAppShortcutsView: View {
    static var lastOnClose: (() -> Void)?
    let onClose: () -> Void

    init(onClose: @escaping () -> Void) {
        self.onClose = onClose
        Self.lastOnClose = onClose
    }

    var body: some View {
        Text("probe").frame(minWidth: 780, minHeight: 560)
    }
}

@main
struct CommandBarAppShortcutsWindowProbe {
    static func main() {
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.accessory)

        guard let visible = NSScreen.main?.visibleFrame else {
            fail("no main screen")
        }
        let parent = NSWindow(
            contentRect: NSRect(x: visible.midX - 500, y: visible.midY - 350,
                                width: 1000, height: 700),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false)
        parent.isReleasedWhenClosed = false

        let controller = CommandBarAppShortcutsWindowController.shared
        controller.show(relativeTo: parent)
        settle()
        guard let window = controller.window else {
            fail("show did not create a window")
        }

        check(window.isVisible, "first show orders a visible window")
        check(window.styleMask.contains(.titled), "window is titled")
        check(window.styleMask.contains(.closable), "window is closable")
        check(window.styleMask.contains(.miniaturizable), "window is miniaturizable")
        check(window.styleMask.contains(.resizable), "window is resizable")
        check(!(window is NSPanel), "window is not a floating panel")
        check(window.level == .normal, "window is at the normal level")
        check(!window.isReleasedWhenClosed, "closing keeps the window instance")
        check(window.title == "App shortcuts", "window carries the localized title")
        check(window.contentMinSize == NSSize(width: 780, height: 560),
              "window keeps the table's minimum content size")
        check(CommandBarService.shared.refreshCount == 1,
              "first presentation refreshes the application list")
        check(WindowActivationPolicy.retentionCount == 1,
              "first presentation retains regular app activation once")
        check(abs(window.frame.midX - parent.frame.midX) <= 1,
              "first open is centered horizontally over Settings")
        check(abs(window.frame.midY - parent.frame.midY) <= 1,
              "first open is centered vertically over Settings")

        let identity = ObjectIdentifier(window)
        controller.show(relativeTo: parent)
        check(controller.window.map(ObjectIdentifier.init) == identity,
              "reopening brings the same instance back")
        check(window.isVisible, "reopening keeps the same window visible")
        check(WindowActivationPolicy.retentionCount == 1,
              "repeated show does not retain app activation twice")

        CommandBarAppShortcutsView.lastOnClose?()
        check(!window.isVisible, "the view's Done action closes this window")
        check(WindowActivationPolicy.retentionCount == 0,
              "closing releases regular app activation")
        check(controller.window.map(ObjectIdentifier.init) == identity,
              "closing retains the window for reuse")

        controller.show(relativeTo: parent)
        check(controller.window.map(ObjectIdentifier.init) == identity && window.isVisible,
              "Done closes only the table window and it can reopen")
        check(WindowActivationPolicy.retentionCount == 1,
              "reopening after Done retains app activation again")

        window.performClose(nil)
        check(!window.isVisible, "the standard close path orders the window out")
        check(WindowActivationPolicy.retentionCount == 0,
              "the standard close path releases app activation")

        controller.show(relativeTo: parent)
        check(window.isVisible, "the standard close path can be reopened")
        check(WindowActivationPolicy.retentionCount == 1,
              "reopening after the standard close retains app activation again")

        controller.dismiss()
        check(WindowActivationPolicy.retentionCount == 0,
              "final close leaves the app in its original activation policy")
        parent.close()
        print("COMMAND BAR APP SHORTCUTS PROBE OK")
    }

    private static func settle() {
        RunLoop.current.run(until: Date().addingTimeInterval(0.1))
    }

    private static func check(_ condition: Bool, _ message: String) {
        if !condition {
            fail(message)
        }
        print("ok: \(message)")
    }

    private static func fail(_ message: String) -> Never {
        fputs("FAIL: \(message)\n", stderr)
        exit(1)
    }
}
