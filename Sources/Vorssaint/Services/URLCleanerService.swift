// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import Combine
import UniformTypeIdentifiers

final class URLCleanerService: ObservableObject {
    static let shared = URLCleanerService()
    private static let automaticRewriteTypes: Set<NSPasteboard.PasteboardType> = [
        .string,
        NSPasteboard.PasteboardType(UTType.url.identifier),
        NSPasteboard.PasteboardType("public.url-name"),
        NSPasteboard.PasteboardType("NSStringPboardType"),
        NSPasteboard.PasteboardType("NSURLPboardType"),
    ]

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

        guard let text = pasteboard.string(forType: .string),
              let cleaned = URLCleaning.clean(text, rules: rules),
              cleaned.url != text.trimmingCharacters(in: .whitespacesAndNewlines),
              canSafelyRewriteAutomatically(pasteboard),
              !token.isCancelled else {
            return PollResult(changeCount: changeCount, cleaned: nil)
        }

        let rewrittenChangeCount = writeToPasteboard(cleaned.url)
        return PollResult(changeCount: rewrittenChangeCount, cleaned: cleaned)
    }

    private static func canSafelyRewriteAutomatically(_ pasteboard: NSPasteboard) -> Bool {
        guard let types = pasteboard.types, !types.isEmpty else { return false }
        return Set(types).isSubset(of: automaticRewriteTypes)
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
        pasteboard.setString(urlString, forType: NSPasteboard.PasteboardType(UTType.url.identifier))
        return pasteboard.changeCount
    }

    private func cancelPoll() {
        pollToken?.cancel()
        pollToken = nil
        pollInFlight = false
    }
}
