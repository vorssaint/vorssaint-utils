// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import Combine
import SwiftUI

/// Production action and view bodies. No network, download, visible window,
/// screenshot or input event is used by this contract.
enum NotchUpdateTests {
    final class Delegate {
        var previews = 0
        func showUpdatePreview() { previews += 1 }
    }
    class State {
        var running = true
        var suspended = false
        var expanded = false
        var collapses = 0
        let delegate = Delegate()
        func collapse() { collapses += 1; expanded = false }
        func appDelegate() -> Delegate? { delegate }
    }

    static func run(_ suite: TestSuite) {
        let updates = UpdateService.shared
        let service = Service()
        defer { updates.state = .idle }
        let states: [UpdateService.State] = [.idle, .checking, .upToDate, .failed("offline"),
            .available(version: "3.4.0"), .available(version: "3.4.0-beta.3"),
            .downloading(progress: nil), .downloading(progress: 0.5), .installing]
        for state in states {
            updates.state = state
            for running in [false, true] {
                for suspended in [false, true] {
                    for expanded in [false, true] {
                        service.running = running
                        service.suspended = suspended
                        service.expanded = expanded
                        let before = service.delegate.previews
                        let collapsed = service.collapses
                        service.showUpdate()
                        let offered: Bool
                        if case .available = state { offered = true } else { offered = false }
                        let opens = running && !suspended && expanded && offered
                        suite.expect(service.delegate.previews == before + (opens ? 1 : 0)
                               && service.collapses == collapsed + (opens ? 1 : 0),
                               "only a current offer in the open, running island can open release notes")
                    }
                }
            }
        }
        service.running = true; service.suspended = false; service.expanded = false
        updates.state = .available(version: "3.4.0-beta.3")
        let before = service.delegate.previews
        service.showUpdate()
        suite.expect(service.delegate.previews == before && !service.expanded,
               "an update cannot open or activate the resting island")
        service.expanded = true
        service.showUpdate()
        suite.expect(service.delegate.previews == before + 1 && !service.expanded,
               "opening the island makes the existing offer actionable and the action closes it for release notes")
        service.showUpdate()
        suite.expect(service.delegate.previews == before + 1,
               "a delayed second action after collapse cannot reopen the update preview")
        layout(suite)
    }

    private static func layout(_ suite: TestSuite) {
        let samples: [UpdateService.State] = [.available(version: "3.4.0-beta.3"),
                                             .available(version: "3.4.0"), .downloading(progress: nil),
                                             .downloading(progress: 0.63), .installing]
        for language in AppLanguage.allCases {
            L10n.shared.language = language
            for state in samples {
                UpdateService.shared.state = state
                let host = NSHostingView(rootView: NotchUpdateControl(action: {})
                    .environment(\.colorScheme, .dark))
                host.layoutSubtreeIfNeeded()
                let size = host.fittingSize
                suite.expect(size.width.isFinite && size.width > 0 && size.width <= 150
                       && size.height > 0 && size.height <= NotchLayout.headerHeight,
                       "\(language.rawValue) update action and progress fit the existing header budget (\(size))")
            }
        }
    }
}
