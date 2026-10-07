// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import Combine
import UniformTypeIdentifiers

final class URLCleanerService: ObservableObject {
    static let shared = URLCleanerService()
    private static let urlType = NSPasteboard.PasteboardType(UTType.url.identifier)

    @Published private(set) var isRunning = false
    @Published private(set) var lastCleaned: String?
    /// Names the last automatic clean took out, so Settings can say what the
    /// silent rewrite did rather than only that it is running.
    @Published private(set) var lastRemoved: [String] = []

    private final class PollToken {
        private let lock = NSLock()
        private var cancelled = false

        func cancel() {
            lock.lock()
            cancelled = true
            lock.unlock()
        }

        var isCancelled: Bool {
            lock.lock()
            defer { lock.unlock() }
            return cancelled
        }
    }

    private struct PollResult {
        let changeCount: Int
        let cleaned: URLCleaning.Result?
    }

    private var timer: Timer?
    private var lastChangeCount = 0
    private var pollInFlight = false
    private var pollToken: PollToken?

    private init() {}

    func syncWithPreferences() {
        if AppFeature.urlCleaner.isAvailable, UserDefaults.standard.bool(forKey: DefaultsKey.urlCleanerEnabled) {
            start()
        } else {
            stop()
        }
    }

    func clean(_ text: String) -> URLCleaning.Result? {
        URLCleaning.clean(text, rules: Self.rules)
    }

    /// Writes on the shared lane and settles the change count on the main
    /// queue, where the poll compares against it. The caller never waits: the
    /// lane can be wedged behind an app that promised pasteboard content and
    /// stopped answering (issue #887).
    func copy(_ urlString: String) {
        cancelPoll()
        lastCleaned = urlString
        GeneralPasteboardAccess.shared.async({
            Self.writeToPasteboard(urlString)
        }, then: { [weak self] changeCount in
            guard let self else { return }
            self.lastChangeCount = max(self.lastChangeCount, changeCount)
        })
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        cancelPoll()
        isRunning = false
    }

    private func start() {
        guard timer == nil else {
            isRunning = true
            return
        }
        let timer = Timer(timeInterval: 0.8, repeats: true) { [weak self] _ in
            self?.cleanClipboardIfNeeded()
        }
        timer.tolerance = 0.25
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
        isRunning = true
        baselinePasteboard()
    }

    /// Reads the initial change count away from the main thread. It shares the
    /// same serial lane as Clipboard History, so neither service can race
    /// AppKit's pasteboard type cache while starting up.
    private func baselinePasteboard() {
        guard !pollInFlight else { return }
        let token = PollToken()
        pollToken = token
        pollInFlight = true
        GeneralPasteboardAccess.shared.async { [weak self] in
            guard !token.isCancelled else { return }
            let changeCount = NSPasteboard.general.changeCount
            DispatchQueue.main.async {
                guard let self, self.pollToken === token else { return }
                self.pollToken = nil
                self.pollInFlight = false
                guard self.isRunning else { return }
                self.lastChangeCount = changeCount
            }
        }
    }

    private func cleanClipboardIfNeeded() {
        guard !pollInFlight else { return }
        let sinceChangeCount = lastChangeCount
        let token = PollToken()
        pollToken = token
        pollInFlight = true
        GeneralPasteboardAccess.shared.async { [weak self] in
            guard !token.isCancelled else { return }
            let result = Self.pollPasteboard(sinceChangeCount: sinceChangeCount, token: token)
            DispatchQueue.main.async {
                guard let self, self.pollToken === token else { return }
                self.pollToken = nil
                self.pollInFlight = false
                guard self.isRunning, let result else { return }
                self.lastChangeCount = result.changeCount
                if let cleaned = result.cleaned {
                    self.lastCleaned = cleaned.url
                    self.lastRemoved = cleaned.removed
                }
            }
        }
    }

    /// Runs only on GeneralPasteboardAccess. Reading the change count, types
    /// and payload plus any rewrite is one serialized transaction.
    private static func pollPasteboard(sinceChangeCount: Int, token: PollToken) -> PollResult? {
        let pasteboard = NSPasteboard.general
        let changeCount = pasteboard.changeCount
        guard !token.isCancelled else { return nil }
        guard changeCount != sinceChangeCount else {
            return PollResult(changeCount: changeCount, cleaned: nil)
        }

        // The types decide before any content is read: a picture or a file
        // is never fetched only to be left alone. Some "copy link" commands
        // put the link on the pasteboard only as a URL, with no text next
        // to it.

        // The rewrite is for a link something was actually taken out of. A
        // copy with nothing to remove is left exactly as the user put it,
        // because writing to the pasteboard discards whatever else the copy
        // carried, and a link the cleaner did not need to touch is the one
        // most likely to come back spelled differently.
        let types = (pasteboard.types ?? []).map(\.rawValue)
        guard URLCleaning.canRewritePasteboard(types: types),
              // The rewrite writes one item, so a copy of several is left alone.
              pasteboard.pasteboardItems?.count == 1,
              let text = pasteboard.string(forType: .string) ?? pasteboard.string(forType: urlType),
              let cleaned = URLCleaning.clean(text, rules: rules),
              !cleaned.removed.isEmpty,
              !token.isCancelled else {
            return PollResult(changeCount: changeCount, cleaned: nil)
        }
        // The rewrite drops the HTML, which is only right when the HTML adds
        // nothing to the link but formatting. When every anchor leads to this
        // link, whatever the copy shows, such as the page title, goes like any
        // formatting of it (#1760). A picture's markup, an anchor to another
        // address, or markup without anchors that shows more than the link is
        // left alone, as the bare link would lose it (#1432).
        if types.contains("public.html") {
            let rawHTML = pasteboard.string(forType: .html) ?? ""
            // A copy of one link is a few hundred bytes. Far larger markup is
            // left alone rather than searched on the shared pasteboard queue.
            guard rawHTML.utf8.count <= 64 * 1024 else {
                return PollResult(changeCount: changeCount, cleaned: nil)
            }
            // Browsers write the address they resolved, percent-encoded and
            // with a slash for an empty path, so links compare as addresses.
            // Case folds after parsing, which writes its escapes in upper case.
            func address(_ string: String) -> String {
                guard let url = URL(string: string),
                      var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
                    return string.lowercased()
                }
                if components.path.isEmpty { components.path = "/" }
                return (components.string ?? string).lowercased()
            }
            let link = text.trimmingCharacters(in: .whitespacesAndNewlines)
            let linkAddress = address(link)
            // Head, style, script and title are never shown, and a head links
            // the document's own files, not the copy. One left open ends at
            // the body or the end, and a tag never spans a '<', so markup that
            // never closes is read once instead of once per '<'.
            let shown = rawHTML.replacingOccurrences(
                of: #"<(head|style|script|title)\b[^<>]*>[\s\S]*?(?:</\1\s*>|(?=<body\b)|\z)"#,
                with: "", options: [.regularExpression, .caseInsensitive])
            let targets = shown.replacingOccurrences(of: "href=", with: "href=", options: .caseInsensitive)
                .components(separatedBy: "href=").dropFirst()
                .map { address(String($0.dropFirst().prefix { $0 != "\"" && $0 != "'" })
                    .replacingOccurrences(of: "&amp;", with: "&")) }
            let html = rawHTML.lowercased()
            let visible = shown.lowercased().replacingOccurrences(of: "&amp;", with: "&")
                .replacingOccurrences(of: "<[^<>]*>", with: "", options: .regularExpression)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let media = ["<img", "<video", "<audio", "<picture", "<svg", "<iframe", "<object", "<embed"]
            guard !media.contains(where: html.contains), targets.allSatisfy({ $0 == linkAddress }),
                  !targets.isEmpty || visible.isEmpty || visible == link.lowercased() else {
                return PollResult(changeCount: changeCount, cleaned: nil)
            }
        }
        // Another app may have copied since the read. Nothing compares and
        // swaps across processes, so this narrows the window, not closes it.
        guard pasteboard.changeCount == changeCount else {
            return PollResult(changeCount: changeCount, cleaned: nil)
        }

        let rewrittenChangeCount = writeToPasteboard(cleaned.url)
        return PollResult(changeCount: rewrittenChangeCount, cleaned: cleaned)
    }

    private static var rules: URLCleaning.Rules {
        let defaults = UserDefaults.standard
        return URLCleaning.rules(
            globalNames: defaults.string(forKey: DefaultsKey.urlCleanerCustomParameters),
            siteNames: defaults.string(forKey: DefaultsKey.urlCleanerSiteParameters),
            disabledNames: defaults.string(forKey: DefaultsKey.urlCleanerDisabledParameters))
    }

    @discardableResult
    private static func writeToPasteboard(_ urlString: String) -> Int {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(urlString, forType: .string)
        pasteboard.setString(urlString, forType: urlType)
        return pasteboard.changeCount
    }

    private func cancelPoll() {
        pollToken?.cancel()
        pollToken = nil
        pollInFlight = false
    }
}
