// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit

/// Production paste routing with an in-memory clipboard and recorded
/// shortcuts. Tests never read or replace the user's general pasteboard.
enum PastePlainTests {
    final class NSPasteboard {
        typealias PasteboardType = AppKit.NSPasteboard.PasteboardType
        static let general = NSPasteboard()
        var contents: [PasteboardType: Data] = [:]
        var reads = 0
        var types: [PasteboardType]? { Array(contents.keys) }
        func string(forType type: PasteboardType) -> String? {
            reads += 1
            return contents[type].flatMap { String(data: $0, encoding: .utf8) }
        }
        func data(forType type: PasteboardType) -> Data? {
            reads += 1
            return contents[type]
        }
    }
    final class GeneralPasteboardAccess {
        static let shared = GeneralPasteboardAccess()
        func async<T>(_ work: () -> T, then: (T) -> Void) { then(work()) }
    }
    struct GlobalShortcut {
        static var standardPaste = true
        static let pastePlainDefault = GlobalShortcut()
        static func saved(for key: String, fallback: GlobalShortcut) -> GlobalShortcut { GlobalShortcut() }
        var isStandardPasteCommand: Bool { Self.standardPaste }
    }
    final class Permissions {
        static let shared = Permissions()
        func requestAccessibility() {}
    }
    enum NSSound { static func beep() {} }
    final class Hotkey {
        var registered = true
        func unregister() { registered = false }
    }
    final class TransientPaste {
        static let shared = TransientPaste()
        var pastedText: String?
        var originalPastes = 0
        var registeredDuringPost: Bool?
        weak var host: Service?
        func paste(_ text: String, willPostShortcut: (() -> Void)?,
                   didPostShortcut: (() -> Void)?) -> Bool {
            pastedText = text
            return post(willPostShortcut, didPostShortcut)
        }
        func pasteCurrentContents(willPostShortcut: (() -> Void)?,
                                  didPostShortcut: (() -> Void)?) -> Bool {
            originalPastes += 1
            return post(willPostShortcut, didPostShortcut)
        }
        private func post(_ willPost: (() -> Void)?, _ didPost: (() -> Void)?) -> Bool {
            willPost?()
            registeredDuringPost = host?.hotkey.registered
            didPost?()
            return true
        }
    }
    class Fixture {
        var promptedForAccessibility = false
        let hotkey = Hotkey()
        var hasNativeMatchStyle = false
        var nativeAttempts = 0
        func AXIsProcessTrusted() -> Bool { true }
        func syncWithPreferences() { hotkey.registered = true }
        func pressNativeMatchStyleItem() -> Bool {
            nativeAttempts += 1
            return hasNativeMatchStyle
        }
    }

    /// Exercises the real forwarding method while the unchanged event-post
    /// helper is held pending, including its busy guard and completion.
    final class OriginalPasteHost {
        var isPerforming = false
        static var pending: (() -> Void)?
        static func postPasteWhenModifiersReleased(attempt: Int,
                                                  willPost: (() -> Void)?,
                                                  didPost: (() -> Void)?,
                                                  didFail: (() -> Void)?,
                                                  completion: @escaping () -> Void) {
            pending = { willPost?(); didPost?(); completion() }
        }
    }

    static func run(_ suite: TestSuite) {
        let board = NSPasteboard.general
        let transient = TransientPaste.shared
        func service(_ contents: [AppKit.NSPasteboard.PasteboardType: Data]) -> Service {
            board.contents = contents
            board.reads = 0
            transient.pastedText = nil
            transient.originalPastes = 0
            transient.registeredDuringPost = nil
            GlobalShortcut.standardPaste = true
            let host = Service()
            transient.host = host
            return host
        }
        // The alternate string is common for images copied in a browser and
        // files copied in Finder. It must not replace the image or file.
        let mediaTypes = ["public.png", "public.tiff", "public.jpeg", "public.heic",
                          "public.mpeg-4", "public.video", "com.apple.quicktime-movie", "public.file-url",
                          "public.mp3", "com.adobe.pdf", "NSFilenamesPboardType",
                          "NSFileContentsPboardType", "com.apple.NSFilePromiseItemMetaData",
                          "Apple files promise pasteboard type", "com.apple.pasteboard.promised-file-url"]
        for type in mediaTypes {
            for textFallback in [false, true] {
                var content = [AppKit.NSPasteboard.PasteboardType(type): Data([0, 1, 2, 3])]
                if textFallback { content[.string] = Data("https://example.com/image.png".utf8) }
                let host = service(content)
                host.hasNativeMatchStyle = true
                host.performPastePlain()
                suite.expect(transient.originalPastes == 1 && transient.pastedText == nil
                             && host.nativeAttempts == 0,
                             "\(type), text=\(textFallback): media bypasses text conversion and matching-style paste")
                suite.expect(board.contents == content && board.reads == 0,
                             "\(type): media and promised contents are neither fetched nor rewritten")
                suite.expect(transient.registeredDuringPost == false && host.hotkey.registered,
                             "\(type): a captured Cmd-V is released for forwarding and registered afterward")
            }
        }

        for content: [AppKit.NSPasteboard.PasteboardType: Data] in [[:], [.string: Data()]] {
            let host = service(content)
            host.performPastePlain()
            suite.expect(transient.originalPastes == 1 && transient.pastedText == nil,
                         "an empty or non-text result still forwards the original paste")
        }
        let richText = Data(#"{\rtf1\ansi hello \b world\b0}"#.utf8)
        for content: [AppKit.NSPasteboard.PasteboardType: Data] in [
            [.string: Data("hello world".utf8)], [.rtf: richText],
            [.string: Data("hello world".utf8), .rtf: richText],
        ] {
            let host = service(content)
            host.performPastePlain()
            suite.expect(transient.pastedText == "hello world" && transient.originalPastes == 0
                         && host.nativeAttempts == 1,
                         "plain and formatted text keep the existing text-only paste")
            suite.expect(transient.registeredDuringPost == false && host.hotkey.registered,
                         "text fallback still releases Cmd-V while posting the paste")
        }
        let native = service([.string: Data("hello".utf8)])
        native.hasNativeMatchStyle = true
        native.performPastePlain()
        suite.expect(native.nativeAttempts == 1 && transient.originalPastes == 0
                     && transient.pastedText == nil && native.hotkey.registered,
                     "text still prefers the destination's native matching-style command")

        let custom = service([.png: Data([0, 1])])
        GlobalShortcut.standardPaste = false
        custom.performPastePlain()
        suite.expect(transient.originalPastes == 1 && transient.registeredDuringPost == true,
                     "a custom plain-text shortcut forwards media without releasing an unrelated hotkey")

        let forwarding = OriginalPasteHost()
        var events: [String] = []
        suite.expect(forwarding.pasteCurrentContents(willPostShortcut: { events.append("will") },
                                                     didPostShortcut: { events.append("did") })
                     && forwarding.isPerforming && events.isEmpty,
                     "forwarding waits for the shared modifier-release path before posting")
        suite.expect(!forwarding.pasteCurrentContents(),
                     "an in-flight paste cannot be overlapped by another forwarding request")
        OriginalPasteHost.pending?()
        OriginalPasteHost.pending = nil
        suite.expect(events == ["will", "did"] && !forwarding.isPerforming,
                     "forwarding brackets the post and clears its busy state on completion")
        board.contents = [:]
        transient.host = nil
    }
}
