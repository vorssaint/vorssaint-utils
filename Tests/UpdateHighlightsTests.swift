// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import SwiftUI

/// Lay out the production tour, including its bundled GIF and native buttons,
/// on short displays in every language. No visible window or app settings change.
enum UpdateHighlightsTests {
    final class L10n: ObservableObject {
        static let shared = L10n()
        @Published var language = AppLanguage.enUS
        var s: Strings { LocalizationTests.languages.first { $0.0 == language }!.1 }
    }

    enum NSScreen {
        static let pointerVisibleFrame = CGRect(x: 0, y: 0, width: 1440, height: 900)
    }

    struct Bundle {
        static let main = Bundle()
        func url(forResource name: String, withExtension ext: String, subdirectory: String) -> URL? {
            URL(fileURLWithPath: "Resources/\(subdirectory)/\(name).\(ext)")
        }
    }

    final class FeatureRuntime {
        static let shared = FeatureRuntime()
        func setAvailable(_ features: [AppFeature], _ available: Bool) {}
    }

    final class Delegate {
        func openSettingsFromHighlights() {}
    }

    static func run(_ suite: TestSuite) {
        let displays = [CGSize(width: 1440, height: 900), CGSize(width: 1024, height: 640),
                        CGSize(width: 800, height: 480), CGSize(width: 520, height: 360)]
        for language in AppLanguage.allCases {
            L10n.shared.language = language
            for display in displays {
                autoreleasepool {
                    let controller = NSHostingController(rootView: UpdateHighlightsView(availableSize: display, onFinish: {}))
                    controller.sizingOptions = .preferredContentSize
                    let window = NSPanel(contentViewController: controller)
                    window.styleMask = [.titled, .closable, .fullSizeContentView]
                    window.titlebarAppearsTransparent = true
                    window.titleVisibility = .hidden
                    window.isReleasedWhenClosed = false
                    defer { window.close() }
                    let host = controller.view
                    host.layoutSubtreeIfNeeded()
                    window.setContentSize(host.fittingSize)
                    host.layoutSubtreeIfNeeded()
                    let context = "\(language.rawValue), \(display)"
                    suite.expect(host.frame.width > 0 && host.frame.height > 0
                                 && window.frame.width <= display.width
                                 && window.frame.height <= display.height,
                                 "the whole tour window, including its title bar, fits the usable display: \(context)")
                    let views = descendants(of: host)
                    let buttons = views.filter { $0 is NSButton || String(describing: type(of: $0)).contains("FocusRing") }
                    suite.expect(buttons.count == 2 && buttons.allSatisfy {
                        let frame = $0.convert($0.bounds, to: host)
                        return frame.width > 0 && frame.height > 0 && host.bounds.contains(frame)
                    }, "both tour actions remain inside the window: \(context)")
                    let image = views.compactMap { $0 as? NSImageView }.first
                    suite.expect(image?.image != nil
                                 && image?.animates == !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion,
                                 "the bundled tour animates only when motion is allowed: \(context)")
                }
            }
        }
        let url = URL(fileURLWithPath: "Resources/Gifs/highlights-notch.gif")
        let host = NSHostingView(rootView: UpdateHighlightsGIF(url: url, animates: true))
        host.frame.size = CGSize(width: 500, height: 400)
        for animates in [true, false, true] {
            host.rootView = UpdateHighlightsGIF(url: url, animates: animates)
            host.layoutSubtreeIfNeeded()
            let image = descendants(of: host).compactMap { $0 as? NSImageView }.first
            suite.expect(image?.animates == animates, "the existing GIF updates its animation when motion changes")
        }
    }

    private static func descendants(of view: NSView) -> [NSView] {
        view.subviews.flatMap { [$0] + descendants(of: $0) }
    }
}

extension UpdateHighlightsTests.UpdateHighlightsView {
    func appDelegate() -> UpdateHighlightsTests.Delegate? { nil }
}
