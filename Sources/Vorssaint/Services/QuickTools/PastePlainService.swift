// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import ApplicationServices
import UniformTypeIdentifiers

/// Keeps the clipboard plain at all times: every rich text copy is rewritten
/// to its plain text as it happens, so the system-wide ⌘V — and the paste
/// command of any app — pastes plain without depending on a "Paste and Match
/// Style" menu item. The global shortcut does the opposite: it restores the
/// formatting the last strip set aside, pastes it, and lets the watcher strip
/// the clipboard again afterwards. Files, images, video, audio, PDFs and
/// marked secrets are never touched.
final class PastePlainService: ObservableObject {
    static let shared = PastePlainService()

    @Published private(set) var shortcutRegistrationFailed = false

    private let hotkey = QuickToolHotkey(id: 10)

    /// The permission prompt fires at most once per launch, so a shortcut
    /// mashed without Accessibility nags once instead of five times.
    private var promptedForAccessibility = false

    // MARK: - Clipboard watching

    /// Pure Paste's cadence: a copy is noticed almost immediately, while
    /// staying cheap enough to run beside the clipboard history's own poll.
    private static let pollInterval: TimeInterval = 0.12
    private static let pollTolerance: TimeInterval = 0.05
    /// How long a promise to render pasteboard content may hold the lane
    /// before the transaction is abandoned. A wedged provider delays the
    /// strip, it never wedges the watcher.
    private static let pasteboardTimeout: TimeInterval = 5
    /// How long the original of the last strip stays restorable on the
    /// shortcut. A strip's plain text lives on the clipboard, so an original
    /// nobody pastes for ten minutes is memory kept for nothing.
    private static let snapshotLifetime: TimeInterval = 600
    /// How long after a rich paste was posted the clipboard is stripped
    /// again: long enough for the destination to have read the restored
    /// content, short enough that a following copy still owns the clipboard.
    private static let repasteRestripDelay: TimeInterval = 0.5

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

    /// What one lane transaction decided and did. `stripped` is nil when the
    /// clipboard was left alone or the transaction expired.
    struct StripTransaction {
        let changeCount: Int
        let stripped: (originalItems: [NSPasteboardItem], plainText: String)?
    }

    private var timer: Timer?
    private var pollInFlight = false
    private var pollToken: PollToken?
    private var lastChangeCount = 0
    /// The change count of the write this service made last, so its own plain
    /// text is never stripped again and the shortcut knows the clipboard is
    /// still the stripped one.
    private var lastStrippedChangeCount = 0
    /// The rich content the last strip set aside, restorable on the shortcut
    /// while the clipboard still holds the plain text that replaced it.
    private var originalItems: [NSPasteboardItem]?
    private var originalCapturedAt = Date.distantPast
    /// True while a rich paste is under way: the restored snapshot must reach
    /// the destination before the watcher is allowed to strip it again.
    private var isRichPasteInFlight = false
    /// Set when a re-strip is owed after a rich paste, and consumed as soon
    /// as the lane admission is free.
    private var pendingRestripe = false
    private var repasteWork: DispatchWorkItem?

    private init() {
        hotkey.onPress = { [weak self] in self?.performPastePlain() }
    }

    func syncWithPreferences() {
        let enabled = AppFeature.pastePlain.isAvailable
            && UserDefaults.standard.bool(forKey: DefaultsKey.pastePlainEnabled)
        let shortcut = GlobalShortcut.saved(for: DefaultsKey.pastePlainShortcut,
                                            fallback: .pastePlainDefault)
        shortcutRegistrationFailed = !hotkey.sync(enabled: enabled, shortcut: shortcut,
                                                  storageKey: DefaultsKey.pastePlainShortcut)
        if enabled {
            startWatching()
        } else {
            stopWatching()
        }
    }

    func suspend() {
        hotkey.unregister()
        stopWatching()
    }

    // MARK: - The shortcut: paste with the original formatting

    func performPastePlain() {
        // Without Accessibility the synthesized ⌘V can never be posted: say so
        // (system prompt once, a beep after) instead of silently swallowing the
        // shortcut, which reads as "the feature does nothing" (issue #186).
        guard AXIsProcessTrusted() else {
            if promptedForAccessibility {
                NSSound.beep()
            } else {
                promptedForAccessibility = true
                Permissions.shared.requestAccessibility()
            }
            return
        }
        guard !isRichPasteInFlight else { return }
        // The lane answers back on main: a promised read must never hold the
        // main thread (issue #887).
        GeneralPasteboardAccess.shared.async({ NSPasteboard.general.changeCount },
                                            then: { [weak self] changeCount in
            guard let self, !self.isRichPasteInFlight else { return }
            if changeCount == self.lastStrippedChangeCount, let original = self.originalItems {
                self.pasteRich(original: original, changeCount: changeCount)
            } else {
                self.forwardPaste()
            }
        })
    }

    /// No original to restore: the clipboard already holds what the user
    /// wants — plain text after a strip, a picture, a file, or a copy from an
    /// excluded app — so the paste is only forwarded, without reading or
    /// replacing anything.
    private func forwardPaste() {
        var releaseHotkey = false
        let willPostShortcut = { [weak self] in
            guard let self else { return }
            let shortcut = GlobalShortcut.saved(for: DefaultsKey.pastePlainShortcut,
                                                fallback: .pastePlainDefault)
            releaseHotkey = shortcut.isStandardPasteCommand
            if releaseHotkey { self.hotkey.unregister() }
        }
        let didPostShortcut = { [weak self] in
            if releaseHotkey { self?.syncWithPreferences() }
        }
        _ = TransientPaste.shared.pasteCurrentContents(willPostShortcut: willPostShortcut,
                                                       didPostShortcut: didPostShortcut)
    }

    /// Restores the original the last strip set aside, pastes it, and lets
    /// the watcher strip the clipboard again once the paste can have landed.
    private func pasteRich(original items: [NSPasteboardItem], changeCount: Int) {
        isRichPasteInFlight = true
        var releaseHotkey = false
        let willPostShortcut = { [weak self] in
            guard let self else { return }
            let shortcut = GlobalShortcut.saved(for: DefaultsKey.pastePlainShortcut,
                                                fallback: .pastePlainDefault)
            releaseHotkey = shortcut.isStandardPasteCommand
            if releaseHotkey { self.hotkey.unregister() }
        }
        let didPostShortcut = { [weak self] in
            if releaseHotkey { self?.syncWithPreferences() }
            self?.scheduleRestripe()
        }
        let didFail = { [weak self] in
            self?.pendingRestripe = false
            self?.isRichPasteInFlight = false
        }
        GeneralPasteboardAccess.shared.async({ () -> Bool in
            let pasteboard = NSPasteboard.general
            guard pasteboard.changeCount == changeCount else { return false }
            pasteboard.clearContents()
            pasteboard.writeObjects(items)
            let restoredCount = pasteboard.changeCount
            DispatchQueue.main.async {
                // The history already holds the plain copy this strip
                // produced; the restored content is that same copy coming
                // back with its formatting, not a new one.
                ClipboardHistoryService.shared.ignoreNextChange(upTo: restoredCount)
            }
            return true
        }, then: { (restored: Bool) in
            guard restored else {
                didFail()
                return
            }
            _ = TransientPaste.shared.pasteCurrentContents(willPostShortcut: willPostShortcut,
                                                           didPostShortcut: didPostShortcut,
                                                           didFail: didFail)
        })
    }

    /// The destination reads the restored content as it processes the
    /// synthesized ⌘V, so the re-strip waits until that paste can have
    /// landed before taking the formatting away again.
    private func scheduleRestripe() {
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.repasteWork = nil
            self.restripeAfterPaste()
        }
        repasteWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.repasteRestripDelay, execute: work)
    }

    private func restripeAfterPaste() {
        pendingRestripe = true
        // Runs now when the lane admission is free; otherwise the poll that is
        // in flight hands over when it finishes.
        runPendingRestripe()
    }

    private func runPendingRestripe() {
        guard pendingRestripe, !pollInFlight else { return }
        pendingRestripe = false
        stripOnce(sinceChangeCount: nil) { [weak self] in
            self?.isRichPasteInFlight = false
        }
    }

    // MARK: - Stripping

    /// Command Bar action: takes the formatting out of the current clipboard
    /// without pasting. A clipboard the watcher already stripped is plain
    /// only, so the decision leaves it alone and this does nothing.
    func clearFormattingNow() {
        guard AppFeature.pastePlain.isAvailable else { return }
        stripOnce(sinceChangeCount: nil)
    }

    /// Runs one strip transaction on the lane. `sinceChangeCount` nil makes
    /// the strip run regardless of whether anything changed since the last
    /// look ("Clear formatting now", the re-strip after a rich paste).
    private func stripOnce(sinceChangeCount: Int?, then: (() -> Void)? = nil) {
        guard !pollInFlight else { return }
        pollInFlight = true
        let token = PollToken()
        pollToken = token
        // Read on main, before the transaction: these are either cheap or
        // AppKit calls that belong on the main thread.
        let ownWrite = lastStrippedChangeCount
        let excluded = Set(Defaults.sanitizedBundleIdentifierList(
            UserDefaults.standard.stringArray(forKey: DefaultsKey.pastePlainExcludedApps) ?? []))
        let frontmost = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        let ownBundleID = Bundle.main.bundleIdentifier
        let transforms = Self.readTransformOptions()
        GeneralPasteboardAccess.shared.async(timeout: Self.pasteboardTimeout, { isExpired in
            guard !token.isCancelled, !isExpired() else { return nil }
            return Self.stripPasteboard(NSPasteboard.general,
                                        sinceChangeCount: sinceChangeCount,
                                        ownLastWriteCount: ownWrite,
                                        ownBundleID: ownBundleID,
                                        excludedApps: excluded,
                                        frontmostBundleID: frontmost,
                                        transforms: transforms,
                                        isExpired: isExpired)
        }, then: { [weak self] (result: StripTransaction?) in
            guard let self, !token.isCancelled else { return }
            self.applyStrip(result)
        }, didFinish: { [weak self] (_: StripTransaction?) in
            guard let self, self.pollToken === token else { return }
            self.pollToken = nil
            self.pollInFlight = false
            then?()
            if self.pendingRestripe { self.runPendingRestripe() }
        })
    }

    /// Applies a finished transaction on the main thread: remembers the write
    /// the watcher must ignore, keeps the original restorable while the
    /// clipboard still holds the plain text that replaced it, and forgets the
    /// original when someone else copied since.
    private func applyStrip(_ result: StripTransaction?) {
        guard let result else { return }
        lastChangeCount = max(lastChangeCount, result.changeCount)
        if let stripped = result.stripped {
            lastStrippedChangeCount = result.changeCount
            originalItems = stripped.originalItems
            originalCapturedAt = Date()
        } else if result.changeCount != lastStrippedChangeCount {
            originalItems = nil
        }
        if originalItems != nil,
           Date().timeIntervalSince(originalCapturedAt) > Self.snapshotLifetime {
            originalItems = nil
        }
    }

    /// Runs only on GeneralPasteboardAccess. The change count, the types and
    /// the rewrite are one serialized transaction, and the types decide
    /// before any content is read: a picture or a file is never fetched only
    /// to be left alone.
    private static func stripPasteboard(_ pasteboard: NSPasteboard,
                                        sinceChangeCount: Int?,
                                        ownLastWriteCount: Int,
                                        ownBundleID: String?,
                                        excludedApps: Set<String>,
                                        frontmostBundleID: String?,
                                        transforms: PastePlainSupport.TransformOptions,
                                        isExpired: () -> Bool) -> StripTransaction? {
        let changeCount = pasteboard.changeCount
        guard !isExpired() else { return nil }
        if let sinceChangeCount, changeCount == sinceChangeCount {
            return StripTransaction(changeCount: changeCount, stripped: nil)
        }
        let rawTypes = (pasteboard.types ?? []).map(\.rawValue)
        let decision = PastePlainSupport.decision(
            types: rawTypes,
            itemCount: pasteboard.pasteboardItems?.count ?? 0,
            declaredSource: pasteboard.string(forType: .source),
            ownBundleID: ownBundleID,
            frontmostBundleID: frontmostBundleID,
            excludedApps: excludedApps,
            isOwnLastWrite: changeCount == ownLastWriteCount)
        guard case .strip = decision, !isExpired() else {
            return StripTransaction(changeCount: changeCount, stripped: nil)
        }
        // Snapshot the original first: a strip may only happen when every
        // advertised flavor can be read back, because the shortcut restores
        // this exact content later. A promised flavor that fails to render
        // aborts the strip instead of clearing incomplete user data.
        guard let items = pasteboard.pasteboardItems else {
            return StripTransaction(changeCount: changeCount, stripped: nil)
        }
        var snapshot: [NSPasteboardItem] = []
        for item in items {
            let copy = NSPasteboardItem()
            for type in item.types {
                guard let data = item.data(forType: type) else {
                    return StripTransaction(changeCount: changeCount, stripped: nil)
                }
                copy.setData(data, forType: type)
            }
            snapshot.append(copy)
        }
        let plain = snapshot.compactMap(plainText(of:)).joined(separator: "\n")
        guard !plain.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return StripTransaction(changeCount: changeCount, stripped: nil)
        }
        let transformed = PastePlainSupport.applyTransforms(plain, options: transforms)
        // Another app may have copied since the read. Nothing compares and
        // swaps across processes, so this narrows the window, not closes it.
        guard pasteboard.changeCount == changeCount, !isExpired() else {
            return StripTransaction(changeCount: pasteboard.changeCount, stripped: nil)
        }
        let source = pasteboard.string(forType: .source)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        pasteboard.clearContents()
        let item = NSPasteboardItem()
        item.setString(transformed, forType: .string)
        pasteboard.writeObjects([item])
        // The app the copy named as its source stays named, and a copy from
        // another device stays marked as one, so the history does not credit
        // the stripped text to the app in front.
        if let source, !source.isEmpty { pasteboard.setString(source, forType: .source) }
        if rawTypes.contains("com.apple.is-remote-clipboard") {
            pasteboard.setData(Data(), forType: .remoteClipboard)
        }
        pasteboard.setData(Data(), forType: .init(PastePlainSupport.modifiedTypeMarker))
        pasteboard.setData(Data(), forType: .init(PastePlainSupport.hasRunMarker))
        return StripTransaction(changeCount: pasteboard.changeCount, stripped: (snapshot, transformed))
    }

    /// The text one item carries without formatting: its plain string when
    /// present, else the text of its RTF or HTML content.
    private static func plainText(of item: NSPasteboardItem) -> String? {
        if let plain = item.string(forType: .string) { return plain }
        if let rtf = item.data(forType: .rtf),
           let attributed = NSAttributedString(rtf: rtf, documentAttributes: nil) {
            return attributed.string
        }
        if let html = item.data(forType: .html),
           let attributed = NSAttributedString(html: html, documentAttributes: nil) {
            return attributed.string
        }
        return nil
    }

    private static func readTransformOptions() -> PastePlainSupport.TransformOptions {
        let defaults = UserDefaults.standard
        return PastePlainSupport.TransformOptions(
            cleanInvisible: defaults.bool(forKey: DefaultsKey.pastePlainCleanInvisible),
            trimWhitespace: defaults.bool(forKey: DefaultsKey.pastePlainTrimWhitespace),
            cleanLinks: defaults.bool(forKey: DefaultsKey.pastePlainCleanLinks))
    }

    // MARK: - Watching lifecycle

    private func startWatching() {
        guard timer == nil else { return }
        let timer = Timer(timeInterval: Self.pollInterval, repeats: true) { [weak self] _ in
            self?.poll()
        }
        timer.tolerance = Self.pollTolerance
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
        // The clipboard as found at startup belongs to whoever copied before
        // the app launched; only changes from here on are stripped, so
        // nothing is rewritten before the watcher has even looked once.
        pollInFlight = true
        let token = PollToken()
        pollToken = token
        GeneralPasteboardAccess.shared.async { [weak self] in
            let changeCount = NSPasteboard.general.changeCount
            DispatchQueue.main.async {
                guard let self, self.pollToken === token else { return }
                self.pollToken = nil
                self.pollInFlight = false
                self.lastChangeCount = changeCount
            }
        }
    }

    private func poll() {
        guard !isRichPasteInFlight, !pollInFlight else { return }
        stripOnce(sinceChangeCount: lastChangeCount)
    }

    private func stopWatching() {
        timer?.invalidate()
        timer = nil
        repasteWork?.cancel()
        repasteWork = nil
        pollToken?.cancel()
        pollToken = nil
        pollInFlight = false
        pendingRestripe = false
        isRichPasteInFlight = false
        originalItems = nil
        lastStrippedChangeCount = 0
    }
}

/// The apps whose copies keep their formatting instead of being stripped.
/// Kept like the clipboard history's ignored-apps list: the pasteboard says
/// what was copied, never who copied it, so the decision matches the app that
/// named itself on the pasteboard and falls back to the app in front when
/// none did.
final class PastePlainExcludedApps: ObservableObject {
    static let shared = PastePlainExcludedApps()

    @Published private(set) var apps: [String] = []

    private init() {
        reload()
    }

    func reload() {
        let defaults = UserDefaults.standard
        let raw = defaults.stringArray(forKey: DefaultsKey.pastePlainExcludedApps) ?? []
        let sanitized = Defaults.sanitizedBundleIdentifierList(raw)
        if raw != sanitized {
            defaults.set(sanitized, forKey: DefaultsKey.pastePlainExcludedApps)
        }
        apps = sanitized
    }

    func add(_ bundleID: String) {
        let bundleID = bundleID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !bundleID.isEmpty, !apps.contains(bundleID) else { return }
        UserDefaults.standard.set(apps + [bundleID], forKey: DefaultsKey.pastePlainExcludedApps)
        reload()
    }

    func remove(_ bundleID: String) {
        guard apps.contains(bundleID) else { return }
        UserDefaults.standard.set(apps.filter { $0 != bundleID },
                                  forKey: DefaultsKey.pastePlainExcludedApps)
        reload()
    }
}
