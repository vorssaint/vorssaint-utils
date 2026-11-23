// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import UniformTypeIdentifiers

/// Paste-plain decisions and paste routing with an in-memory clipboard and
/// recorded shortcuts. Tests never read or replace the user's general
/// pasteboard: the decision matrix and the transforms run against the real
/// `PastePlainSupport`, and the service fixture is generated against the
/// doubles below.
enum PastePlainTests {
    final class NSPasteboard {
        typealias PasteboardType = AppKit.NSPasteboard.PasteboardType
        static let general = NSPasteboard()
        /// The items on the board, in order, as their declared data.
        private(set) var items: [[PasteboardType: Data]] = []
        /// Simulates promised content: types are advertised, but no item ever
        /// renders behind them.
        var phantomTypes: [PasteboardType]?
        var changeCount = 0
        var reads = 0
        var dataReads = 0
        var clears = 0
        var writeCount = 0

        var types: [PasteboardType]? {
            if let phantomTypes { return phantomTypes }
            return items.isEmpty ? nil : Array(Set(items.flatMap { Array($0.keys) }))
        }

        var pasteboardItems: [NSPasteboardItem]? {
            if phantomTypes != nil { return nil }
            return items.isEmpty ? nil : items.map { item in
                let copy = NSPasteboardItem()
                copy.contents = item
                return copy
            }
        }

        func setItems(_ value: [[PasteboardType: Data]]) {
            items = value
            changeCount += 1
        }

        /// Like the real convenience setters, these address the first item
        /// (creating one when the board is empty), which is how the strip
        /// re-adds markers beside its single written item.
        @discardableResult func setString(_ string: String, forType type: PasteboardType) -> Bool {
            reads += 1
            let data = Data(string.utf8)
            if !items.isEmpty {
                items[0][type] = data
            } else {
                items = [[type: data]]
            }
            return true
        }

        @discardableResult func setData(_ data: Data, forType type: PasteboardType) -> Bool {
            if !items.isEmpty {
                items[0][type] = data
            } else {
                items = [[type: data]]
            }
            return true
        }

        func string(forType type: PasteboardType) -> String? {
            reads += 1
            return items.first?[type].flatMap { String(data: $0, encoding: .utf8) }
        }

        func data(forType type: PasteboardType) -> Data? {
            reads += 1
            dataReads += 1
            return items.first?[type]
        }

        func clearContents() {
            items = []
            changeCount += 1
            clears += 1
        }

        func writeObjects(_ objects: [NSPasteboardItem]) {
            items = objects.map(\.contents)
            changeCount += 1
            writeCount += 1
        }
    }

    final class NSPasteboardItem {
        typealias PasteboardType = AppKit.NSPasteboard.PasteboardType
        var contents: [PasteboardType: Data] = [:]
        var types: [PasteboardType] { Array(contents.keys) }
        func data(forType type: PasteboardType) -> Data? {
            NSPasteboard.general.dataReads += 1
            return contents[type]
        }
        func string(forType type: PasteboardType) -> String? {
            NSPasteboard.general.reads += 1
            return contents[type].flatMap { String(data: $0, encoding: .utf8) }
        }
        @discardableResult func setString(_ string: String, forType type: PasteboardType) -> Bool {
            contents[type] = Data(string.utf8)
            return true
        }
        @discardableResult func setData(_ data: Data, forType type: PasteboardType) -> Bool {
            contents[type] = data
            return true
        }
    }

    final class GeneralPasteboardAccess {
        static let shared = GeneralPasteboardAccess()
        func async<T>(_ work: () -> T, then: (T) -> Void) { then(work()) }
        func async<T>(timeout: TimeInterval, _ work: (_ isExpired: () -> Bool) -> T?,
                      then: (T?) -> Void, didFinish: (T?) -> Void = { _ in }) {
            let result = work({ false })
            then(result)
            didFinish(result)
        }
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

    final class ClipboardHistoryService {
        static let shared = ClipboardHistoryService()
        var ignoredCounts: [Int] = []
        func ignoreNextChange(upTo changeCount: Int) { ignoredCounts.append(changeCount) }
    }

    final class TransientPaste {
        static let shared = TransientPaste()
        var pastedText: String?
        var originalPastes = 0
        var registeredDuringPost: Bool?
        weak var host: Service?
        func pasteCurrentContents(willPostShortcut: (() -> Void)?,
                                  didPostShortcut: (() -> Void)?,
                                  didFail: (() -> Void)? = nil) -> Bool {
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

    /// The service state the generated fixture methods reach through `self`:
    /// the same fields the real class owns, driven by hand.
    class Fixture {
        var accessibilityTrusted = true
        var promptedForAccessibility = false
        let hotkey = Hotkey()
        func AXIsProcessTrusted() -> Bool { accessibilityTrusted }
        func syncWithPreferences() { hotkey.registered = true }

        var lastChangeCount = 0
        var lastStrippedChangeCount = 0
        var lastFailedChangeCount: Int?
        var lastFailedAt = Date.distantPast
        var originalItems: [NSPasteboardItem]?
        var originalCapturedAt = Date()
        var isRichPasteInFlight = false
        var pendingRestripe = false
        var repasteWork: DispatchWorkItem?
        var pollInFlight = false
        var pollToken: PollToken?

        final class PollToken {
            var isCancelled = false
            func cancel() {}
        }

        static let pasteboardTimeout: TimeInterval = 5
        static let pollInterval: TimeInterval = 0.12
        static let retryBackoff: TimeInterval = 2
        // The generated methods post the re-strip with asyncAfter; a zero
        // delay lets the tests drain it by spinning the run loop.
        static var repasteRestripDelay: TimeInterval = 0
        static let snapshotLifetime: TimeInterval = 600
    }

    /// Mirrors the real nested transaction result, which the generator does
    /// not copy out of the class body.
    struct StripTransaction {
        let changeCount: Int
        let stripped: (originalItems: [NSPasteboardItem], plainText: String)?
        let aborted: Bool
    }

    /// Exercises the real forwarding method while the unchanged event-post
    /// helper is held pending, including its busy guard and completion.
    final class OriginalPasteHost {
        typealias NSPasteboard = PastePlainTests.NSPasteboard
        typealias GeneralPasteboardAccess = PastePlainTests.GeneralPasteboardAccess
        var isPerforming = false
        static var pending: (() -> Void)?
        static func postPasteWhenModifiersReleased(attempt: Int,
                                                  expectedChangeCount: Int,
                                                  willPost: (() -> Void)?,
                                                  didPost: (() -> Void)?,
                                                  didFail: (() -> Void)?,
                                                  completion: @escaping () -> Void) {
            pending = { willPost?(); didPost?(); completion() }
        }
    }

    static func run(_ suite: TestSuite) {
        // The Command Bar action gates on availability like the app does.
        // register() is volatile and covers only this feature's key, so no
        // other suite's saved-switch checks can see it.
        UserDefaults.standard.register(
            defaults: [AppFeature.pastePlain.availabilityKey: true])
        decisionMatrix(suite)
        transforms(suite)
        stripBehaviour(suite)
        pasteRouting(suite)
        NSPasteboard.general.setItems([])
    }

    // MARK: - Decision matrix

    private static func decisionMatrix(_ suite: TestSuite) {
        func decide(_ types: [String],
                    itemCount: Int = 1,
                    declaredSource: String? = nil,
                    ownBundleID: String? = "com.vorssaint.tests",
                    frontmost: String? = nil,
                    excluded: Set<String> = [],
                    isOwnLastWrite: Bool = false) -> PastePlainDecision {
            PastePlainSupport.decision(types: types, itemCount: itemCount,
                                       declaredSource: declaredSource,
                                       ownBundleID: ownBundleID,
                                       frontmostBundleID: frontmost,
                                       excludedApps: excluded,
                                       isOwnLastWrite: isOwnLastWrite)
        }
        let string = "public.utf8-plain-text"
        let rtf = "public.rtf"
        let html = "public.html"
        suite.expect(decide([]) == .leaveAlone(.empty), "an empty clipboard is left alone")
        // Files are hard-skipped before anything else, even when the name
        // they carry as text looks like text worth stripping.
        for file in ["public.file-url", "NSFilenamesPboardType", "NSFileContentsPboardType",
                     "com.apple.NSFilePromiseItemMetaData", "Apple files promise pasteboard type",
                     "com.apple.pasteboard.promised-file-url"] {
            suite.expect(decide([file, string]) == .leaveAlone(.protectedContent),
                         "\(file) is a file copy, not text")
        }
        for media in ["public.png", "public.tiff", "public.jpeg", "public.heic", "com.adobe.pdf",
                      "public.mp3", "public.mpeg-4", "com.apple.quicktime-movie", "public.movie"] {
            suite.expect(decide([media]) == .leaveAlone(.notText),
                         "\(media) alone has no text and is never read")
            // A picture beside its text is confirmed against the string: the
            // strip happens only when that text is real, not the media's own
            // link or file name.
            suite.expect(decide([media, string]) == .stripWhenTextIsReal,
                         "\(media) beside text is judged by the text")
        }
        suite.expect(decide([string]) == .leaveAlone(.alreadyPlain),
                     "plain text alone has nothing to lose")
        suite.expect(decide([string, rtf]) == .strip, "RTF beside text is stripped")
        suite.expect(decide([string, html]) == .strip, "HTML beside text is stripped")
        suite.expect(decide([rtf]) == .strip, "RTF alone still strips to its text")
        for legacy in ["NSRTFPboardType", "NSRTFDPboardType", "NSHTMLPboardType"] {
            suite.expect(decide([string, legacy]) == .strip, "\(legacy) is rich text")
        }
        for item in ["org.nspasteboard.ConcealedType"] {
            suite.expect(decide([string, rtf, item]) == .leaveAlone(.concealed),
                         "\(item) is a secret")
        }
        for item in ["org.nspasteboard.TransientType", "org.nspasteboard.AutoGeneratedType"] {
            suite.expect(decide([string, rtf, item]) == .leaveAlone(.transient),
                         "\(item) is content an app owns")
        }
        suite.expect(decide([string, rtf], isOwnLastWrite: true) == .leaveAlone(.ownWrite),
                     "the clipboard from our own last write is left alone")
        suite.expect(decide([string, rtf], declaredSource: "com.vorssaint.tests")
                     == .leaveAlone(.ownWrite),
                     "a copy that names this app as its source is our own")
        suite.expect(decide([string, rtf], declaredSource: "com.example.editor",
                            excluded: ["com.example.editor"]) == .leaveAlone(.excludedApp),
                     "a copy from an excluded app keeps its formatting")
        suite.expect(decide([string, rtf], frontmost: "com.example.editor",
                            excluded: ["com.example.editor"]) == .leaveAlone(.excludedApp),
                     "an excluded app in front with no declared source keeps its formatting")
        suite.expect(decide([string, rtf], declaredSource: "com.apple.Safari",
                            frontmost: "com.example.editor",
                            excluded: ["com.example.editor"]) == .strip,
                     "a named, unexcluded source is believed over the frontmost app")
        suite.expect(decide([string], itemCount: 2) == .strip,
                     "two plain items strip so their texts do not paste run together")
        suite.expect(decide([string, rtf], declaredSource: "com.example.files",
                            excluded: []) == .strip,
                     "a remote-clipboard copy strips locally like any other")
        // An excluded app's copy is skipped before its media text is read.
        suite.expect(decide(["public.png", string], declaredSource: "com.example.editor",
                            excluded: ["com.example.editor"]) == .leaveAlone(.excludedApp),
                     "an excluded app's media copy is not read either")
    }

    // MARK: - Transforms

    private static func transforms(_ suite: TestSuite) {
        // What a picture copied on its own carries as text, judged the way a
        // media copy's strip decision judges it.
        for fallback in ["", " \n", "https://example.com/a.png", "data:image/png;base64,AAAA",
                         "blob:https://example.com/1", "IMG_1234.HEIC", "photo.jpeg", "clip.mp4", "scan.pdf"] {
            suite.expect(PastePlainSupport.isMediaTextFallback(fallback),
                         "'\(fallback)' is the text a lone picture or clip carries")
            suite.expect(!PastePlainSupport.mediaCopyStrips(plain: fallback),
                         "'\(fallback)' beside a picture keeps the picture")
        }
        for text in ["Total", "Total:", "1.2.3", "3.14", "e.g.", "Item\tQty\nA\t1", "see https://example.com",
                     "two words", "U.S.", "example.com", "2.4GHz", "12.5kg", "config.yaml", "john@example.com"] {
            suite.expect(!PastePlainSupport.isMediaTextFallback(text),
                         "'\(text)' is copied text that came with a picture of itself")
            suite.expect(PastePlainSupport.mediaCopyStrips(plain: text),
                         "'\(text)' beside a picture strips to plain text")
        }

        let none = PastePlainSupport.TransformOptions()
        let code = "let greeting = \"héllo\"\nif greeting == \"héllo\" {\n    print(greeting)\n}"
        suite.expect(PastePlainSupport.applyTransforms(code, options: none) == code,
                     "the default transform set leaves a code snippet unchanged")
        // U+200B zero-width space, U+FEFF byte-order mark, U+2060 word joiner,
        // U+00AD soft hyphen, U+E0001 tag character and U+E0041..E0047 tag
        // letters: the watermark range.
        let watermarked = "w\u{200B}o\u{FEFF}rd\u{2060}s and\u{00AD} hy\u{E0001}\u{E0041}\u{E0047}phens"
        let cleaned = PastePlainSupport.removingInvisibleCharacters(watermarked)
        suite.expect(cleaned == "words and hyphens", "invisible characters come out: got '\(cleaned)'")
        suite.expect(PastePlainSupport.applyTransforms(watermarked, options: none) == watermarked,
                     "invisible removal stays off by default")
        let emoji = "👍🏽\u{200D}❤️\u{200C}text"
        suite.expect(PastePlainSupport.removingInvisibleCharacters(emoji) == emoji,
                     "emoji joiners and variation selectors survive")
        let trimmedOptions = PastePlainSupport.TransformOptions(trimWhitespace: true)
        suite.expect(PastePlainSupport.applyTransforms("\n  hi there  \n", options: trimmedOptions)
                     == "hi there", "whitespace is trimmed when asked")
        suite.expect(PastePlainSupport.applyTransforms("a\nb\n", options: trimmedOptions) == "a\nb",
                     "interior line breaks survive a trim")
        let link = "https://example.com/page?utm_source=rss&id=7"
        let linkOptions = PastePlainSupport.TransformOptions(cleanLinks: true)
        suite.expect(PastePlainSupport.applyTransforms(link, options: linkOptions)
                     == "https://example.com/page?id=7",
                     "a whole-copy link loses its trackers")
        suite.expect(PastePlainSupport.applyTransforms("see \(link) here", options: linkOptions)
                     == "see \(link) here",
                     "text that is not one link is never rewritten")
        suite.expect(PastePlainSupport.applyTransforms(code, options: linkOptions) == code,
                     "a multi-line snippet is not read as a link")
        // Order: an invisible character between the copy and its trailing
        // space would otherwise hide the whitespace from the trim.
        let padded = "\u{200B}  hello \u{FEFF}\n"
        let bothOptions = PastePlainSupport.TransformOptions(cleanInvisible: true, trimWhitespace: true)
        suite.expect(PastePlainSupport.applyTransforms(padded, options: bothOptions) == "hello",
                     "invisible characters go before the trim")
        suite.expect(PastePlainSupport.applyTransforms(
            PastePlainSupport.applyTransforms(watermarked, options: bothOptions),
            options: bothOptions) == "words and hyphens",
            "the transforms are idempotent")
    }

    // MARK: - Strip behaviour

    private static func stripBehaviour(_ suite: TestSuite) {
        let board = NSPasteboard.general
        func strip(since: Int? = nil,
                   ownWrite: Int = 0,
                   excluded: Set<String> = [],
                   failed: (count: Int, at: Date)? = nil,
                   transforms: PastePlainSupport.TransformOptions = .init()) -> StripTransaction? {
            board.reads = 0
            board.dataReads = 0
            board.writeCount = 0
            return Service.stripPasteboard(board, sinceChangeCount: since,
                                           ownLastWriteCount: ownWrite,
                                           ownBundleID: "com.vorssaint.tests",
                                           excludedApps: excluded,
                                           frontmostBundleID: nil,
                                           failedChangeCount: failed?.count,
                                           failedAt: failed?.at ?? .distantPast,
                                           transforms: transforms,
                                           isExpired: { false })
        }
        // A rich copy: rewritten as exactly one plain-text item, with the
        // source and remote markers kept and both strip markers added.
        board.setItems([[
            .string: Data("hello world".utf8),
            .rtf: Data(#"{\rtf1\ansi hello \b world\b0}"#.utf8),
            AppKit.NSPasteboard.PasteboardType("org.nspasteboard.source"): Data("com.apple.Safari".utf8),
            .remoteClipboard: Data(),
        ]])
        let before = board.changeCount
        let result = strip()
        suite.expect(result?.stripped?.plainText == "hello world"
                     && result?.changeCount == before + 2,
                     "a rich copy is stripped in one transaction")
        suite.expect(board.writeCount == 1 && board.items.count == 1,
                     "the strip writes exactly one item")
        let written = board.items[0]
        suite.expect(written[.string] == Data("hello world".utf8),
                     "the plain text replaces the formatting")
        suite.expect(written[AppKit.NSPasteboard.PasteboardType("org.nspasteboard.source")]
                     == Data("com.apple.Safari".utf8),
                     "the declared source survives the strip")
        suite.expect(written[.remoteClipboard] == Data(),
                     "the remote marker survives the strip")
        suite.expect(written[AppKit.NSPasteboard.PasteboardType("x.nspasteboard.ModifiedType")] == Data()
                     && written[AppKit.NSPasteboard.PasteboardType("com.vorssaint.PastePlain.hasRun")] == Data(),
                     "the strip markers are added")
        suite.expect(board.clears == 1, "the board is cleared before the write")

        // Media beside its text: a document's snapshot of a selection strips
        // to the text, while a picture copied on its own is left whole.
        let table = "Item\tQty\nA\t1"
        for media: AppKit.NSPasteboard.PasteboardType in [.tiff, .init("com.adobe.pdf"), .png] {
            board.setItems([[.string: Data(table.utf8), media: Data([1, 2, 3])]])
            let snapshot = strip()
            suite.expect(snapshot?.stripped?.plainText == table && board.writeCount == 1
                         && board.items.count == 1
                         && board.items[0][.string] == Data(table.utf8),
                         "\(media): a cell's text beside its picture strips to the text")
        }
        // A browser's "Copy Image" names the picture as text: the picture is
        // the copy, so nothing is rewritten.
        for fallback in ["https://example.com/image.png", "IMG_1234.HEIC"] {
            board.setItems([[.png: Data([1, 2, 3]), .string: Data(fallback.utf8),
                             .html: Data("<b>x</b>".utf8)]])
            let kept = strip()
            suite.expect(kept?.stripped == nil && board.writeCount == 0 && board.dataReads == 0,
                         "a picture whose text is its own '\(fallback)' stays whole")
        }
        // A picture on its own has no text at all and is never read.
        board.setItems([[.png: Data([1, 2, 3])]])
        suite.expect(strip()?.stripped == nil && board.writeCount == 0 && board.dataReads == 0,
                     "a picture alone is left alone without a single data read")

        // A file copy is left alone even when it also carries text.
        board.setItems([[.string: Data("Report.pdf".utf8),
                         AppKit.NSPasteboard.PasteboardType("public.file-url"): Data([1])]])
        suite.expect(strip()?.stripped == nil && board.writeCount == 0,
                     "a file copy with a name as text is never rewritten")

        // Secrets and transient content stay exactly as the app wrote them.
        for mark in ["org.nspasteboard.ConcealedType", "org.nspasteboard.TransientType",
                     "org.nspasteboard.AutoGeneratedType"] {
            board.setItems([[.string: Data("secret".utf8), .rtf: Data(#"{\rtf1 s}"#.utf8),
                             AppKit.NSPasteboard.PasteboardType(mark): Data()]])
            suite.expect(strip()?.stripped == nil && board.writeCount == 0,
                         "\(mark) is never rewritten")
        }

        // A flavor the pasteboard synthesizes for a string but no item can
        // produce, like the external UTF-16 form, is skipped rather than
        // aborting the strip of the whole copy.
        board.setItems([[.string: Data("hello world".utf8), .rtf: Data(#"{\rtf1\ansi h}"#.utf8),
                         AppKit.NSPasteboard.PasteboardType("public.utf16-external-plain-text"): Data()]])
        let synthesized = strip()
        suite.expect(synthesized?.stripped?.plainText == "hello world" && !synthesized!.aborted,
                     "a synthesized flavor does not abort the strip")

        // Promised content that never renders: types without items abort the
        // strip, and the change stays unconsumed so a later poll retries it.
        board.setItems([[.string: Data("gone".utf8)]])
        board.phantomTypes = [.string, .rtf]
        let unreadable = strip()
        suite.expect(unreadable?.aborted == true && unreadable?.stripped == nil,
                     "promised content that never renders aborts the strip")
        suite.expect(strip(failed: (count: unreadable!.changeCount, at: Date())) == nil,
                     "the retry is throttled to one attempt per backoff window")
        suite.expect(strip(failed: (count: unreadable!.changeCount,
                                    at: Date(timeIntervalSinceNow: -60)))!.aborted,
                     "after the backoff the same copy is attempted again")
        board.phantomTypes = nil

        // Nothing to read back: the strip aborts instead of clearing content.
        board.setItems([[.string: Data("  \n".utf8), .rtf: Data(#"{\rtf1 }"#.utf8)]])
        suite.expect(strip()?.stripped == nil && board.writeCount == 0 && !board.items.isEmpty,
                     "a strip with no usable text keeps the original")

        // Plain-only text: no write at all, so the change count never moves.
        board.setItems([[.string: Data("plain".utf8)]])
        let plainCount = board.changeCount
        suite.expect(strip()?.stripped == nil && board.changeCount == plainCount
                     && board.writeCount == 0,
                     "plain-only text is left without a write")

        // Our own last write, a copy from this app, an excluded app, and an
        // unchanged board are all left alone.
        board.setItems([[.string: Data("hello".utf8), .rtf: Data(#"{\rtf1 h}"#.utf8)]])
        let current = board.changeCount
        suite.expect(strip(ownWrite: current)?.stripped == nil && board.writeCount == 0,
                     "our own write is never stripped again")
        suite.expect(strip(since: current)?.stripped == nil && board.writeCount == 0,
                     "an unchanged board does nothing")
        board.setItems([[.string: Data("hello".utf8), .rtf: Data(#"{\rtf1 h}"#.utf8),
                         AppKit.NSPasteboard.PasteboardType("org.nspasteboard.source"):
                            Data("com.vorssaint.tests".utf8)]])
        suite.expect(strip()?.stripped == nil && board.writeCount == 0,
                     "a copy that names this app is our own")
        board.setItems([[.string: Data("hello".utf8), .rtf: Data(#"{\rtf1 h}"#.utf8),
                         AppKit.NSPasteboard.PasteboardType("org.nspasteboard.source"):
                            Data("com.example.editor".utf8)]])
        suite.expect(strip(excluded: ["com.example.editor"])?.stripped == nil
                     && board.writeCount == 0,
                     "an excluded app's copy is never rewritten")

        // Optional transforms run inside the strip.
        let dirty = "w\u{200B}ords"
        board.setItems([[.string: Data(dirty.utf8), .rtf: Data(#"{\rtf1 w}"#.utf8)]])
        _ = strip(transforms: .init(cleanInvisible: true))
        suite.expect(board.items.first?[.string] == Data("words".utf8),
                     "the enabled transforms shape the plain write")

        // Several plain items join in order.
        board.setItems([[.string: Data("first".utf8)], [.string: Data("second".utf8)]])
        let joined = strip()
        suite.expect(joined?.stripped?.plainText == "first\nsecond"
                     && board.items.count == 1,
                     "multiple items strip to one item joined with line breaks")
    }

    // MARK: - Paste routing

    private static func pasteRouting(_ suite: TestSuite) {
        let board = NSPasteboard.general
        let transient = TransientPaste.shared
        func service(_ contents: [AppKit.NSPasteboard.PasteboardType: Data]) -> Service {
            board.setItems([contents])
            board.reads = 0
            board.dataReads = 0
            board.writeCount = 0
            transient.pastedText = nil
            transient.originalPastes = 0
            transient.registeredDuringPost = nil
            ClipboardHistoryService.shared.ignoredCounts = []
            GlobalShortcut.standardPaste = true
            Fixture.repasteRestripDelay = 0
            let host = Service()
            host.lastStrippedChangeCount = 0
            host.originalItems = nil
            host.isRichPasteInFlight = false
            host.pendingRestripe = false
            host.lastChangeCount = board.changeCount
            transient.host = host
            return host
        }
        let rtfData = Data(#"{\rtf1\ansi hello \b world\b0}"#.utf8)

        // No snapshot: whatever is on the clipboard is what the user wants,
        // so the paste is only forwarded.
        for content: [AppKit.NSPasteboard.PasteboardType: Data] in [
            [.string: Data("hello world".utf8)],
            [.png: Data([1, 2])],
            [AppKit.NSPasteboard.PasteboardType("public.file-url"): Data([1])],
            [:],
        ] {
            let host = service(content)
            host.performPastePlain()
            suite.expect(transient.originalPastes == 1 && transient.pastedText == nil
                         && board.writeCount == 0,
                         "\(content): no snapshot forwards the original paste")
            suite.expect(transient.registeredDuringPost == false && host.hotkey.registered,
                         "\(content): a captured ⌘V is released for forwarding and registered afterward")
        }

        // With a snapshot valid for the current count: the original comes
        // back, the paste is posted, and the clipboard is stripped again.
        let sourceType = AppKit.NSPasteboard.PasteboardType("org.nspasteboard.source")
        let original: [AppKit.NSPasteboard.PasteboardType: Data] = [
            .string: Data("hello world".utf8), .rtf: rtfData,
            sourceType: Data("com.apple.Safari".utf8),
        ]
        board.setItems([original])
        let host = service(original)
        host.lastStrippedChangeCount = board.changeCount
        host.originalItems = board.pasteboardItems
        host.performPastePlain()
        suite.expect(transient.originalPastes == 1 && host.isRichPasteInFlight,
                     "a rich paste posts the paste while holding the watcher")
        suite.expect(board.items == [original] && board.writeCount == 1,
                     "the snapshot is written back before the paste")
        let restoredCount = board.changeCount
        let deadline = Date().addingTimeInterval(5)
        while host.isRichPasteInFlight, Date() < deadline {
            RunLoop.main.run(mode: .default, before: Date().addingTimeInterval(0.01))
        }
        suite.expect(ClipboardHistoryService.shared.ignoredCounts == [restoredCount],
                     "the restored rich content is not recorded as a second copy")
        suite.expect(!host.isRichPasteInFlight, "the re-strip completes after the paste")
        suite.expect(board.items == [[.string: Data("hello world".utf8),
                                       sourceType: Data("com.apple.Safari".utf8),
                                       AppKit.NSPasteboard.PasteboardType("x.nspasteboard.ModifiedType"): Data(),
                                       AppKit.NSPasteboard.PasteboardType("com.vorssaint.PastePlain.hasRun"): Data()]],
                     "the clipboard is plain again, with the source kept")
        suite.expect(host.lastStrippedChangeCount == board.changeCount
                     && host.originalItems?.first?.contents == original,
                     "the original stays restorable for the next press")
        suite.expect(transient.originalPastes == 1, "no second paste is posted")

        // A stale snapshot (the user copied since the strip) only forwards.
        board.setItems([original])
        let stale = service(original)
        stale.lastStrippedChangeCount = board.changeCount - 1
        stale.originalItems = [NSPasteboardItem()]
        stale.performPastePlain()
        suite.expect(transient.originalPastes == 1 && board.items == [original],
                     "a stale snapshot forwards instead of restoring")

        // Without Accessibility the shortcut says so instead of pasting.
        board.setItems([original])
        let untrusted = service(original)
        untrusted.accessibilityTrusted = false
        untrusted.performPastePlain()
        suite.expect(untrusted.promptedForAccessibility && transient.originalPastes == 0,
                     "a shortcut without Accessibility prompts once")
        untrusted.performPastePlain()
        suite.expect(transient.originalPastes == 0, "the prompt does not repeat")

        // A custom shortcut is not the plain ⌘V, so no hotkey release dance.
        let custom = service([.string: Data("hello".utf8)])
        GlobalShortcut.standardPaste = false
        custom.performPastePlain()
        suite.expect(transient.originalPastes == 1 && transient.registeredDuringPost == true,
                     "a custom shortcut forwards without releasing an unrelated hotkey")

        // Clear formatting now: strips the clipboard without pasting, and
        // does nothing to a clipboard that is already plain.
        board.setItems([original])
        let clearer = service(original)
        clearer.clearFormattingNow()
        suite.expect(transient.originalPastes == 0
                     && board.items == [[.string: Data("hello world".utf8),
                                         sourceType: Data("com.apple.Safari".utf8),
                                         AppKit.NSPasteboard.PasteboardType("x.nspasteboard.ModifiedType"): Data(),
                                         AppKit.NSPasteboard.PasteboardType("com.vorssaint.PastePlain.hasRun"): Data()]]
                     && clearer.lastStrippedChangeCount == board.changeCount,
                     "clear formatting strips without pasting")
        let afterClear = board.changeCount
        clearer.clearFormattingNow()
        suite.expect(board.changeCount == afterClear,
                     "an already plain clipboard is not rewritten again")

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
        board.setItems([])
        transient.host = nil
        GlobalShortcut.standardPaste = true
        Fixture.repasteRestripDelay = 0
    }
}
