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
    class ServiceState {
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
        // The bell shares the narrowest wing beside the camera
        // with the header menu. The menu, its indicator and the spacing
        // between them take 44 points.
        let wing = narrowestCameraWing()
        suite.expect(wing.isFinite && wing > 44, "some island layout places the header beside the camera")
        let samples: [UpdateService.State] = [.idle, .checking, .upToDate, .failed("offline"),
                                             .available(version: "3.4.0-beta.3"),
                                             .available(version: "3.4.0"), .downloading(progress: nil),
                                             .downloading(progress: 0.63), .installing]
        for language in AppLanguage.allCases {
            L10n.shared.language = language
            for state in samples {
                UpdateService.shared.state = state
                let control = NotchUpdateControl(action: {})
                let offered: Bool
                if case .available = state { offered = true } else { offered = false }
                suite.expect(control.hasOffer == offered,
                       "only an available update adds an unread badge")
                let host = NSHostingView(rootView: control
                    .environment(\.colorScheme, .dark))
                host.layoutSubtreeIfNeeded()
                let size = host.fittingSize
                let maximumWidth: CGFloat = wing - 44
                suite.expect(size.width.isFinite && size.width > 0 && size.width <= maximumWidth
                       && size.height > 0 && size.height <= NotchLayout.headerHeight,
                       "\(language.rawValue) update bell and progress fit beside the camera (\(size))")
            }
        }
    }

    /// The narrowest trailing wing any preset or custom width leaves beside a
    /// camera, read from the geometry instead of assumed.
    private static func narrowestCameraWing() -> CGFloat {
        let screen = CGRect(x: 0, y: 0, width: 1512, height: 982)
        let widths = stride(from: NotchSize.widthRange.lowerBound, through: NotchSize.widthRange.upperBound, by: 1)
        var narrowest = CGFloat.infinity
        for camera: CGFloat in [180, 185, 210, 240] {
            for layout in NotchSize.allCases {
                for width in widths {
                    let geometry = NotchGeometry(screen: screen, safeAreaTop: 32, cameraWidth: camera,
                                                 layout: layout, customWidth: width)
                    guard geometry.headerCameraGap > 0 else { continue }
                    narrowest = min(narrowest, (geometry.contentWidth - geometry.headerCameraGap) / 2)
                }
            }
        }
        return narrowest
    }
}
