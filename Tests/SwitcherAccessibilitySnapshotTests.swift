// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import ApplicationServices
import CoreGraphics
import Foundation

/// Exercises the production snapshot collector with simulated AX replies.
/// WindowServer identifiers and remote window reads are the only test doubles.
enum SwitcherAccessibilitySnapshotTests {
    final class Window: NSObject {
        let id: CGWindowID?
        let reading: Reader.WindowReading
        var reads = 0

        init(_ id: CGWindowID?, _ reading: Reader.WindowReading) {
            self.id = id
            self.reading = reading
        }
    }

    enum Reader {
        typealias AXUIElement = Window
        static let messagingTimeout: Float = 0.35
        static var windows: [Window] = []
        static var focused: Window?
        static var listResult: AXError = .success

        enum AXWindowResolver {
            static func windowID(for window: Window) -> CGWindowID? { window.id }
        }

        static func AXUIElementCreateApplication(_ pid: pid_t) -> Window { Window(nil, .notUserFacing) }
        static func AXUIElementSetMessagingTimeout(_ window: Window, _ timeout: Float) {}
        static func AXUIElementCopyAttributeValue(_ app: Window, _ attribute: CFString,
                                                  _ value: inout CFTypeRef?) -> AXError {
            value = windows as NSArray
            return listResult
        }

        static func userFacingReading(of window: Window, bundleIdentifier: String?,
                                      acceptsUndescribedSubroles: Bool,
                                      normalLevelWindowIDs: Set<CGWindowID>, screenFrames: [CGRect],
                                      isCancelled: () -> Bool) -> WindowReading {
            window.reads += 1
            return window.reading
        }

        static func accessibilityWindowAttribute(_ app: Window, _ attribute: String) -> Window? { focused }
        static func accessibilityFrame(for window: Window, isCancelled: () -> Bool) -> CGRect? {
            CGRect(x: 0, y: 0, width: 600, height: 400)
        }
        static func accessibilityTitle(for window: Window) -> String { "Workspace" }
        static func boolAttribute(_ window: Window, _ attribute: String) -> Bool { false }
        static func isFullscreenWindow(_ window: Window, isCancelled: () -> Bool) -> Bool { false }
        static func frameLooksFullscreen(_ frame: CGRect?, screenFrames: [CGRect]) -> Bool { false }
    }

    static func run(_ suite: TestSuite) {
        defer {
            Reader.windows = []
            Reader.focused = nil
            Reader.listResult = .success
        }
        func snapshot(_ windows: [Window]) -> Reader.AccessibilityWindowSnapshotList? {
            Reader.windows = windows
            return Reader.accessibilityWindows(for: 1, normalLevelWindowIDs: [1, 2, 3],
                                                screenFrames: [], isCancelled: { false })
        }
        func keeps(_ id: CGWindowID, in answer: Reader.AccessibilityWindowSnapshotList?,
                   excluded: Bool = false) -> Bool {
            let witness = answer.map {
                SwitcherSupport.accessibilityWitness(isDescribed: $0.byID[id] != nil,
                    isUnanswered: $0.everyWindowUnanswered || $0.unansweredIDs.contains(id))
            }
            return SwitcherSupport.keepsSurface(witness: witness, keepsUnmatched: {
                SwitcherSupport.keepsUnmatchedWindow(isOnHiddenSpace: false,
                    isConfirmedHiddenAppWindow: false, isExcludedFromWindowCycle: excluded,
                    isOrderedIn: nil, allowsUnverifiedHiddenSpace: answer?.ordered.isEmpty == true)
            }, isExcludedFromWindowCycle: { excluded }, isLeftover: { false })
        }

        let described = Window(1, .userFacing)
        let unanswered = Window(nil, .unanswered)
        Reader.focused = unanswered
        let partial = snapshot([described, unanswered, Window(3, .notUserFacing)])
        suite.expect(partial?.everyWindowUnanswered == true && keeps(2, in: partial),
                     "an unresolved timed-out window stays visible beside a described sibling")
        suite.expect(keeps(1, in: partial) && !keeps(3, in: partial, excluded: true),
                     "the partial-answer fallback preserves described windows and rejects cycle-excluded helpers")
        suite.expect(unanswered.reads == 1,
                     "main and focused aliases do not repeat a timed-out window read")

        Reader.focused = nil
        let resolved = snapshot([Window(1, .userFacing), Window(2, .unanswered), Window(3, .notUserFacing)])
        suite.expect(resolved?.everyWindowUnanswered == false && keeps(2, in: resolved)
                        && !keeps(3, in: resolved),
                     "resolved timeouts retain each sibling's rejection instead of broadening the fallback")
        let empty = snapshot([Window(nil, .unanswered)])
        suite.expect(empty?.everyWindowUnanswered == true && keeps(2, in: empty)
                        && !keeps(3, in: empty, excluded: true),
                     "a wholly unanswered snapshot keeps the same cycle-filtered fallback")
        let ordinary = snapshot([Window(1, .userFacing)])
        suite.expect(ordinary?.everyWindowUnanswered == false && keeps(1, in: ordinary)
                        && !keeps(2, in: ordinary),
                     "fully answered snapshots still reject unmatched current-space surfaces")
        suite.expect(Reader.accessibilityWindows(for: 1, normalLevelWindowIDs: [], screenFrames: [],
                                                isCancelled: { true }) == nil,
                     "a cancelled snapshot does not publish a partial answer")
        Reader.listResult = .cannotComplete
        suite.expect(snapshot([]) == nil, "an unanswered app keeps its existing no-snapshot path")
    }
}
