// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import LinkPresentation

enum URLCleanerMetadataTests {
    private typealias Host = ClipboardFeatureTests.URLCleanerHost
    private static let metadataType = URLCleanerLinkMetadata.pasteboardType

    static func run(_ suite: TestSuite) {
        let board = Host.NSPasteboard.general
        let tracked = "https://example.com/article?id=42&utm_source=news#section"
        let cleaned = "https://example.com/article?id=42#section"

        func metadata(original: String? = nil, destination: String? = nil) -> LPLinkMetadata {
            let value = LPLinkMetadata()
            value.originalURL = original.flatMap(URL.init(string:))
            value.url = destination.flatMap(URL.init(string:))
            value.title = "A page title"
            return value
        }
        func archive(_ value: NSObject & NSSecureCoding) -> Data {
            (try? NSKeyedArchiver.archivedData(withRootObject: value, requiringSecureCoding: true)) ?? Data()
        }
        func decoded(_ data: Data?) -> LPLinkMetadata? {
            guard let data else { return nil }
            return try? NSKeyedUnarchiver.unarchivedObject(ofClass: LPLinkMetadata.self, from: data)
        }
        func place(_ data: Data, text: String = tracked, textType: NSPasteboard.PasteboardType = .string) {
            board.clearContents()
            board.setString(text, forType: textType)
            board.setData(data, forType: metadataType)
        }
        func poll() -> Host.PollResult? {
            Host.pollPasteboard(sinceChangeCount: -1, token: Host.PollToken())
        }

        // LPMetadataProvider generated this archive from local synthetic HTML
        // with a red 32px icon and a 400px checkerboard picture. Its addresses
        // use example.com. A manually assigned NSItemProvider is not included
        // in LPLinkMetadata's secure archive, so it cannot test preservation.
        guard let richData = try? Data(contentsOf: URL(fileURLWithPath: "Tests/Fixtures/URLCleanerLinkMetadata.bplist")),
              let richLink = decoded(richData) else {
            suite.expect(false, "the native rich-link fixture decodes")
            return
        }
        place(richData)
        board.setString(tracked, forType: .URL)
        board.setString("com.apple.Safari", forType: .source)
        board.setData(Data(), forType: .remoteClipboard)
        board.setString("<a href='\(tracked.replacingOccurrences(of: "&", with: "&amp;"))'>A page title</a>",
                        forType: .html)
        let result = poll()
        let rewritten = decoded(board.data(forType: metadataType))
        suite.expect(result?.cleaned?.url == cleaned && board.string(forType: .string) == cleaned
                     && board.string(forType: .URL) == cleaned,
                     "a Safari rich copy cleans both plain-text and URL representations")
        suite.expect(rewritten?.originalURL?.absoluteString == cleaned && rewritten?.url?.absoluteString == cleaned,
                     "a rich paste cannot bring back tracking from either navigation URL")
        suite.expect(rewritten?.title == richLink.title,
                     "a cleaned Safari link retains its preview title")
        suite.expect(imageWidth(rewritten?.iconProvider) == 32 && imageWidth(rewritten?.imageProvider) == 400,
                     "a cleaned Safari link retains loadable icon and preview image data")
        suite.expect(board.string(forType: .source) == "com.apple.Safari"
                     && board.types?.contains(.remoteClipboard) == true && board.data(forType: .html) == nil,
                     "a rich rewrite preserves source and remote marks while dropping stale HTML")

        place(richData, textType: .URL)
        suite.expect(poll()?.cleaned?.url == cleaned && decoded(board.data(forType: metadataType))?.title == richLink.title,
                     "Safari copies carrying only a URL and metadata are also cleaned")

        let redirected = metadata(original: tracked, destination: "https://youtu.be/video?si=share&t=42")
        place(archive(redirected))
        _ = poll()
        let redirectResult = decoded(board.data(forType: metadataType))
        suite.expect(redirectResult?.originalURL?.absoluteString == cleaned
                     && redirectResult?.url?.absoluteString == "https://youtu.be/video?t=42",
                     "a redirect keeps its own destination and playback position, with host-specific tracking removed")

        let urlOnly = metadata(destination: tracked)
        place(archive(urlOnly))
        _ = poll()
        let urlOnlyResult = decoded(board.data(forType: metadataType))
        suite.expect(urlOnlyResult?.originalURL == nil && urlOnlyResult?.url?.absoluteString == cleaned,
                     "metadata with one navigation URL keeps the absent original URL absent")

        let customRules = URLCleaning.rules(globalNames: "id", siteNames: nil, disabledNames: "|utm_*")
        if case .preserved(let data) = URLCleanerLinkMetadata.rewrite(richData, matching: tracked, rules: customRules) {
            suite.expect(decoded(data)?.url?.absoluteString == "https://example.com/article?utm_source=news#section",
                         "preview URLs use the same added and disabled rules as the copied link")
        } else {
            suite.expect(false, "custom cleaning rules retain the preview")
        }

        for (label, data) in [
            ("invalid bytes", Data([0, 1, 2])),
            ("a different archived class", archive("not link metadata" as NSString)),
            ("an oversized preview", Data(repeating: 0, count: 2 * 1024 * 1024 + 1)),
        ] {
            place(data)
            suite.expect(poll()?.cleaned?.url == cleaned && board.data(forType: metadataType) == nil,
                         "\(label) falls back to a clean link without retaining stale metadata")
        }

        for (label, value) in [
            ("another link", metadata(original: "https://other.example/?utm_source=x", destination: "https://other.example/")),
            ("a differently cased path", metadata(original: tracked.replacingOccurrences(of: "article", with: "Article"))),
            ("a differently cased query", metadata(original: tracked.replacingOccurrences(of: "news", with: "NEWS"))),
        ] {
            let data = archive(value)
            place(data)
            let count = board.changeCount
            suite.expect(poll()?.cleaned == nil && board.changeCount == count
                         && board.data(forType: metadataType) == data,
                         "metadata for \(label) leaves the whole copy intact")
        }

        // LinkPresentation can discard a non-web destination while decoding.
        // Keep that absence; a destination that survives must block the rewrite.
        let nonWebData = archive(metadata(original: tracked, destination: "file:///tmp/example"))
        let decodedDestination = decoded(nonWebData)?.url
        place(nonWebData)
        let nonWebCount = board.changeCount
        let nonWebResult = poll()
        if decodedDestination == nil {
            let rewritten = decoded(board.data(forType: metadataType))
            suite.expect(nonWebResult?.cleaned?.url == cleaned && rewritten?.originalURL?.absoluteString == cleaned
                         && rewritten?.url == nil,
                         "a non-web destination omitted by LinkPresentation is not restored by cleaning")
        } else {
            suite.expect(nonWebResult?.cleaned == nil && board.changeCount == nonWebCount
                         && board.data(forType: metadataType) == nonWebData,
                         "metadata retaining a non-web destination leaves the whole copy intact")
        }
        place(archive(metadata(original: "https://EXAMPLE.com/article?id=42&utm_source=news#section")))
        suite.expect(poll()?.cleaned?.url == cleaned,
                     "metadata matching the copied address with a differently cased host can be cleaned")

        let untouchedData = archive(metadata(original: cleaned, destination: cleaned))
        place(untouchedData, text: cleaned)
        let untouchedCount = board.changeCount
        suite.expect(poll()?.cleaned == nil && board.changeCount == untouchedCount
                     && board.data(forType: metadataType) == untouchedData,
                     "a link without removable tracking keeps its original preview bytes")

        for type in ["public.data", "public.png", "public.file-url", "com.apple.pasteboard.promised-file-url",
                     "com.adobe.pdf", "org.nspasteboard.ConcealedType", "org.nspasteboard.TransientType"] {
            place(richData)
            board.setData(Data([1]), forType: NSPasteboard.PasteboardType(type))
            let count = board.changeCount
            suite.expect(poll()?.cleaned == nil && board.changeCount == count
                         && board.data(forType: metadataType) == richData,
                         "Safari metadata does not bypass the protection for \(type)")
        }
        place(richData)
        board.setString("<img src='\(tracked)'>", forType: .html)
        let imageCount = board.changeCount
        suite.expect(poll()?.cleaned == nil && board.changeCount == imageCount,
                     "Safari metadata does not bypass the protection for image markup")

        board.clearContents()
        let items = (0..<2).map { _ -> NSPasteboardItem in
            let item = NSPasteboardItem()
            item.setString(tracked, forType: .string)
            item.setData(richData, forType: metadataType)
            return item
        }
        board.writeObjects(items)
        let multipleCount = board.changeCount
        suite.expect(poll()?.cleaned == nil && board.changeCount == multipleCount && board.pasteboardItems?.count == 2,
                     "two rich links remain separate copied items")
    }

    private final class ImageRead: @unchecked Sendable {
        private let lock = NSLock()
        private var width: Int?
        func store(_ value: Int) { lock.withLock { width = value } }
        var value: Int? { lock.withLock { width } }
    }

    private static func imageWidth(_ provider: NSItemProvider?) -> Int? {
        guard let provider else { return nil }
        let result = ImageRead()
        provider.loadObject(ofClass: NSImage.self) { object, _ in
            let width = (object as? NSImage)?.tiffRepresentation
                .flatMap(NSBitmapImageRep.init(data:))?.pixelsWide
            result.store(width ?? 0)
        }
        let deadline = Date().addingTimeInterval(2)
        while result.value == nil, Date() < deadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.005))
        }
        return result.value
    }
}
