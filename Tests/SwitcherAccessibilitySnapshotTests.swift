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
        var attributes: [String: Any]
        var batchResult: AXError
        var batchValues: [Any]?
        var reads = 0
        var singleReads: [String: Int] = [:]
        var minimizeButton: Window?
        var afterBatchRead: (() -> Void)?
        var isApplication = false

        init(_ id: CGWindowID?, _ reading: Reader.WindowReading = .userFacing,
             attributes: [String: Any] = [:], batchResult: AXError = .success) {
            self.id = id
            self.batchResult = reading == .unanswered ? .cannotComplete : batchResult
            self.attributes = [
                kAXRoleAttribute as String: reading == .notUserFacing ? "AXButton" : "AXWindow",
                kAXSubroleAttribute as String: reading == .notUserFacing ? "AXUnknown" : "AXStandardWindow",
                "AXFullScreen": false,
                kAXMinimizedAttribute as String: false,
                kAXPositionAttribute as String: SwitcherAccessibilitySnapshotTests.pointValue(CGPoint(x: 20, y: 30)),
                kAXSizeAttribute as String: SwitcherAccessibilitySnapshotTests.sizeValue(CGSize(width: 600, height: 400)),
                kAXTitleAttribute as String: "Workspace"
            ].merging(attributes) { _, replacement in replacement }
        }
    }

    enum Reader {
        typealias AXUIElement = Window
        static let messagingTimeout: Float = 0.35
        static var windows: [Window] = []
        static var focused: Window?
        static var listResult: AXError = .success
        static var batchRequests: [[String]] = []
        static var batchOptions: [AXCopyMultipleAttributeOptions] = []
        static let elementType = CFGetTypeID(Window(nil))

        enum AXWindowResolver {
            static func windowID(for window: Window) -> CGWindowID? { window.id }
        }

        enum SpaceWindowBridge {
            static func isExcludedFromWindowCycle(_ id: CGWindowID) -> Bool { false }
        }

        static func AXUIElementCreateApplication(_ pid: pid_t) -> Window {
            let app = Window(nil, .notUserFacing)
            app.isApplication = true
            return app
        }
        static func AXUIElementGetTypeID() -> CFTypeID { elementType }
        static func AXUIElementSetMessagingTimeout(_ window: Window, _ timeout: Float) {}
        static func AXUIElementCopyAttributeValue(_ window: Window, _ attribute: CFString,
                                                  _ value: inout CFTypeRef?) -> AXError {
            let name = attribute as String
            window.singleReads[name, default: 0] += 1
            if window.isApplication {
                if name == kAXWindowsAttribute as String {
                    value = windows as NSArray
                    return listResult
                }
                value = focused
                return focused == nil ? .noValue : .success
            }
            if name == kAXMinimizeButtonAttribute as String {
                value = window.minimizeButton
                return window.minimizeButton == nil ? .noValue : .success
            }
            value = window.attributes[name] as AnyObject?
            return value == nil ? .attributeUnsupported : .success
        }

        static func AXUIElementCopyMultipleAttributeValues(_ window: Window, _ attributes: CFArray,
                                                           _ options: AXCopyMultipleAttributeOptions,
                                                           _ values: inout CFArray?) -> AXError {
            window.reads += 1
            let names = attributes as? [String] ?? []
            batchRequests.append(names)
            batchOptions.append(options)
            if window.batchResult == .success {
                values = (window.batchValues ?? names.map { window.attributes[$0] ?? NSNull() }) as CFArray
            }
            window.afterBatchRead?()
            return window.batchResult
        }
    }

    private static func pointValue(_ value: CGPoint) -> AXValue {
        var value = value
        return AXValueCreate(.cgPoint, &value)!
    }

    private static func sizeValue(_ value: CGSize) -> AXValue {
        var value = value
        return AXValueCreate(.cgSize, &value)!
    }

    private static func errorValue(_ error: AXError) -> AXValue {
        var error = error
        return AXValueCreate(.axError, &error)!
    }

    static func run(_ suite: TestSuite) {
        defer {
            Reader.windows = []
            Reader.focused = nil
            Reader.listResult = .success
            Reader.batchRequests = []
            Reader.batchOptions = []
        }
        func snapshot(_ windows: [Window], screenFrames: [CGRect] = [],
                      isCancelled: () -> Bool = { false }) -> Reader.AccessibilityWindowSnapshotList? {
            Reader.windows = windows
            return Reader.accessibilityWindows(for: 1,
                                                normalLevelWindowIDs: Set(windows.compactMap(\.id)),
                                                screenFrames: screenFrames, isCancelled: isCancelled)
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
        let maximized = snapshot([Window(1)],
                                 screenFrames: [CGRect(x: 0, y: 0, width: 600, height: 400)])?.byID[1]
        suite.expect(maximized?.isFullscreen == true && maximized?.isNativeFullscreen == false,
                     "a screen-sized AX window keeps the frame hint separate from native fullscreen state")
        let fullscreen = snapshot([Window(1, attributes: ["AXFullScreen": true])])?.byID[1]
        suite.expect(fullscreen?.isFullscreen == true && fullscreen?.isNativeFullscreen == true,
                     "an AX fullscreen flag survives in both fullscreen metadata fields")

        // Normal, fullscreen and minimized windows share the same one-read
        // path, including the metadata that used to be fetched a second time.
        Reader.batchRequests = []
        Reader.batchOptions = []
        let manyWindows = (1...48).map { (index: Int) -> Window in
            let attributes: [String: Any] = [
                kAXTitleAttribute as String: "Window \(index)",
                "AXFullScreen": index % 3 == 1,
                kAXMinimizedAttribute as String: index % 3 == 2
            ]
            return Window(CGWindowID(index), attributes: attributes)
        }
        Reader.focused = manyWindows[0]
        let many = snapshot(manyWindows)
        suite.expect(many?.ordered.count == 48 && manyWindows.allSatisfy { $0.reads == 1 },
                     "48 normal, fullscreen and minimized windows each need only one attribute round trip")
        suite.expect(manyWindows.allSatisfy { $0.singleReads.isEmpty }
                        && Reader.batchRequests.count == 48
                        && Reader.batchRequests.allSatisfy {
                            Set($0) == Set([kAXRoleAttribute as String, kAXSubroleAttribute as String,
                                           "AXFullScreen", kAXMinimizedAttribute as String,
                                           kAXPositionAttribute as String, kAXSizeAttribute as String,
                                           kAXTitleAttribute as String]) && $0.count == 7
                        } && Reader.batchOptions.allSatisfy { $0.isEmpty },
                     "the shared read requests every snapshot field without stopping at an unsupported attribute")
        suite.expect(manyWindows.allSatisfy { window in
            guard let id = window.id, let entry = many?.byID[id] else { return false }
            return entry.title == "Window \(id)"
                && entry.frame == CGRect(x: 20, y: 30, width: 600, height: 400)
                && entry.isMinimized == (id % 3 == 2)
                && entry.isNativeFullscreen == (id % 3 == 1)
        }, "batch snapshots retain each window's title, frame, minimized and fullscreen state")

        let rejectedAlias = Window(3, .notUserFacing)
        Reader.focused = rejectedAlias
        let duplicate = snapshot([Window(1), rejectedAlias, rejectedAlias])
        suite.expect(duplicate?.ordered.count == 1 && rejectedAlias.reads == 1,
                     "rejected aliases in the list, main and focused attributes are read only once")
        Reader.focused = nil

        let unsupportedFullscreen = Window(1, attributes: ["AXFullScreen": errorValue(.attributeUnsupported)])
        let missingOptional = Window(2, attributes: [
            "AXFullScreen": NSNull(),
            kAXPositionAttribute as String: NSNull(),
            kAXSizeAttribute as String: errorValue(.noValue),
            kAXTitleAttribute as String: errorValue(.cannotComplete)
        ])
        let optional = snapshot([unsupportedFullscreen, missingOptional])
        suite.expect(optional?.byID.count == 2 && optional?.byID[1]?.isNativeFullscreen == false
                        && optional?.byID[2]?.frame == nil && optional?.byID[2]?.title == "",
                     "unsupported, missing and timed-out optional fields do not reject a standard window")

        let subroleTimeout = Window(1, attributes: [kAXSubroleAttribute as String: errorValue(.cannotComplete)])
        let roleTimeout = Window(2, attributes: [
            kAXRoleAttribute as String: errorValue(.cannotComplete),
            kAXSubroleAttribute as String: NSNull()
        ])
        let subroleMissing = Window(3, attributes: [kAXSubroleAttribute as String: NSNull()])
        let partialErrors = snapshot([subroleTimeout, roleTimeout, subroleMissing])
        suite.expect(partialErrors?.unansweredIDs == [1, 2]
                        && partialErrors?.byID[3] != nil && keeps(1, in: partialErrors) && keeps(2, in: partialErrors),
                     "partial role and subrole timeouts remain unanswered while a missing subrole still accepts AXWindow")

        let independentFields = snapshot([
            Window(1, attributes: [
                "AXFullScreen": true,
                kAXRoleAttribute as String: errorValue(.cannotComplete),
                kAXSubroleAttribute as String: errorValue(.cannotComplete)
            ]),
            Window(2, attributes: [
                kAXMinimizedAttribute as String: true,
                kAXSubroleAttribute as String: errorValue(.cannotComplete)
            ]),
            Window(3, attributes: [kAXRoleAttribute as String: errorValue(.cannotComplete)]),
            Window(4, attributes: [
                "AXFullScreen": errorValue(.attributeUnsupported),
                kAXRoleAttribute as String: errorValue(.cannotComplete),
                kAXSubroleAttribute as String: "AXFullScreenWindow"
            ])
        ])
        suite.expect(independentFields?.byID.count == 4 && independentFields?.unansweredIDs.isEmpty == true
                        && independentFields?.byID[4]?.isNativeFullscreen == true,
                     "fullscreen, minimized and standard windows keep their independent classification evidence")

        let shortResponse = Window(1)
        shortResponse.batchValues = ["AXWindow", "AXStandardWindow"]
        let wrongTypes = Window(2, attributes: [
            "AXFullScreen": "unsupported",
            kAXMinimizedAttribute as String: NSNull(),
            kAXSizeAttribute as String: pointValue(CGPoint(x: 600, y: 400)),
            kAXTitleAttribute as String: NSNumber(value: 42)
        ])
        let malformed = snapshot([shortResponse, wrongTypes])
        suite.expect(malformed?.byID.count == 2 && malformed?.byID[1]?.title == ""
                        && malformed?.byID[1]?.frame == nil && malformed?.byID[2]?.frame == nil
                        && malformed?.byID[2]?.isMinimized == false && malformed?.byID[2]?.title == "",
                     "short or mistyped optional values keep safe metadata defaults without additional reads")

        let hung = Window(1, .unanswered)
        Reader.focused = hung
        let hungAnswer = snapshot([hung])
        suite.expect(hungAnswer?.unansweredIDs == [1] && hung.reads == 1 && hung.singleReads.isEmpty,
                     "a failed batch remains unanswered without repeating individual attribute timeouts")
        Reader.focused = nil

        let dialog = Window(1, attributes: [kAXSubroleAttribute as String: "AXDialog"])
        dialog.minimizeButton = Window(nil, attributes: [kAXEnabledAttribute as String: true])
        let alert = Window(2, attributes: [kAXSubroleAttribute as String: "AXDialog"])
        let dialogs = snapshot([dialog, alert])
        suite.expect(dialogs?.byID[1] != nil && dialogs?.byID[2] == nil
                        && dialog.reads == 1 && dialog.singleReads[kAXMinimizeButtonAttribute as String] == 1
                        && dialog.minimizeButton?.singleReads[kAXEnabledAttribute as String] == 1,
                     "normal-level dialogs still require a working minimize button after their shared attribute read")

        suite.expect(Reader.accessibilityWindows(for: 1, normalLevelWindowIDs: [], screenFrames: [],
                                                isCancelled: { true }) == nil,
                     "a cancelled snapshot does not publish a partial answer")
        var cancelled = false
        let cancelDuringRead = Window(1)
        let unread = Window(2)
        cancelDuringRead.afterBatchRead = { cancelled = true }
        let cancelledAnswer = snapshot([cancelDuringRead, unread], isCancelled: { cancelled })
        suite.expect(cancelledAnswer == nil && cancelDuringRead.reads == 1 && unread.reads == 0,
                     "cancellation during a batch stops later windows and never publishes a partial snapshot")
        Reader.listResult = .cannotComplete
        suite.expect(snapshot([]) == nil, "an unanswered app keeps its existing no-snapshot path")
    }
}
