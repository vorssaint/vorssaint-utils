// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import CoreGraphics

/// Runs the production paste and restore sequence on a private pasteboard.
/// Held modifiers and key delivery are simulated; no system keys are posted.
enum TransientPasteTests {
    static let pasteboard = NSPasteboard(name: NSPasteboard.Name("VorssaintTransientPasteTests-" + UUID().uuidString))

    enum CGEventSource {
        static var held: CGEventFlags = []
        static func flagsState(_ state: CGEventSourceStateID) -> CGEventFlags { held }
    }

    final class CGEvent {
        static var inserted: [String] = []
        static var keyUps = 0
        var flags: CGEventFlags = []
        let isKeyDown: Bool
        init?(keyboardEventSource: Any?, virtualKey: CGKeyCode, keyDown: Bool) {
            isKeyDown = keyDown
        }
        func post(tap: CGEventTapLocation) {
            if isKeyDown { Self.inserted.append(pasteboard.string(forType: .string) ?? "") }
            else { Self.keyUps += 1 }
        }
    }

    /// Keep the private AppKit pasteboard on one lane, like production does.
    /// The test lane uses main so the run-loop assertions share its type cache.
    final class GeneralPasteboardAccess {
        static let shared = GeneralPasteboardAccess()
        func async(_ work: @escaping () -> Void) { DispatchQueue.main.async(execute: work) }
        func async<T>(_ work: @escaping () -> T, then completion: @escaping (T) -> Void) {
            DispatchQueue.main.async { completion(work()) }
        }
    }

    enum ClipboardHistoryService {
        static let shared = History()
        struct History { func ignoreNextChange(upTo: Int) {} }
    }

    private static func pump(until condition: () -> Bool) {
        let deadline = Date(timeIntervalSinceNow: 3)
        while !condition(), Date() < deadline {
            RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.005))
        }
    }

    static func run(_ suite: TestSuite) {
        defer { pasteboard.releaseGlobally() }
        let host = TransientPaste.shared
        let rich = Data("{\\rtf1 original}".utf8)
        func reset() {
            CGEvent.inserted = []
            CGEvent.keyUps = 0
            CGEventSource.held = .maskCommand
            pasteboard.clearContents()
            pasteboard.setString("original", forType: .string)
            pasteboard.setData(rich, forType: .rtf)
        }

        reset()
        var before = 0, posted = 0, failed = 0
        suite.expect(host.paste("requested", willPostShortcut: { before += 1 },
                                didPostShortcut: { posted += 1 }, didFail: { failed += 1 }),
                     "the first paste is admitted")
        suite.expect(!host.paste("second"), "a pending paste rejects another insertion")
        pump { pasteboard.string(forType: .string) == "requested" }
        pasteboard.clearContents()
        pasteboard.setString("new copy", forType: .string)
        CGEventSource.held = []
        pump { posted + failed == 1 }
        suite.expect(CGEvent.inserted.isEmpty && CGEvent.keyUps == 0,
                     "a copy made while modifiers are held cancels both synthetic paste keys")
        suite.expect(before == 0 && posted == 0 && failed == 1,
                     "cancellation reports failure once without deleting a snippet trigger")
        RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.6))
        suite.expect(pasteboard.string(forType: .string) == "new copy",
                     "a cancelled paste does not restore over the newer copy")

        reset()
        before = 0; posted = 0; failed = 0
        suite.expect(host.paste("requested", willPostShortcut: { before += 1 },
                                didPostShortcut: { posted += 1 }, didFail: { failed += 1 }),
                     "cancellation releases the paste admission flag")
        pump { pasteboard.string(forType: .string) == "requested" }
        CGEventSource.held = []
        pump { posted + failed == 1 }
        suite.expect(CGEvent.inserted == ["requested"] && CGEvent.keyUps == 1,
                     "an unchanged pasteboard delivers the requested text and a balanced key pair")
        suite.expect(before == 1 && posted == 1 && failed == 0,
                     "a successful paste invokes its callbacks once")
        pump { pasteboard.string(forType: .string) == "original" }
        suite.expect(pasteboard.string(forType: .string) == "original",
                     "successful paste still restores the original clipboard")

        suite.expect(pasteboard.data(forType: .rtf) == rich,
                     "successful paste preserves the original rich-text flavor")

        reset()
        posted = 0; failed = 0
        suite.expect(host.paste("requested", didPostShortcut: { posted += 1 }, didFail: { failed += 1 }),
                     "another normal paste is admitted")
        pump { pasteboard.string(forType: .string) == "requested" }
        CGEventSource.held = []
        pump { posted == 1 }
        pasteboard.clearContents()
        pasteboard.setString("copy after paste", forType: .string)
        RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.6))
        suite.expect(CGEvent.inserted == ["requested"] && failed == 0
                     && pasteboard.string(forType: .string) == "copy after paste",
                     "a copy after delivery is preserved by the existing restore guard")
    }
}
