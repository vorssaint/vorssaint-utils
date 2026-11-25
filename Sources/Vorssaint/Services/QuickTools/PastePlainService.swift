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
    /// How long a failed strip waits before the same copy is attempted again.
    private static let retryBackoff: TimeInterval = 2

    private final class PollToken {
        private let lock = NSLock()
        private var cancelled = false
        /// Main-thread only: this transaction already handed its admission
        /// back, whichever answer came first.
        var hasFinished = false

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
    /// clipboard was left alone or the transaction expired; `aborted` marks a
    /// copy that could not be read back and must be retried, not consumed.
    struct StripTransaction {
        let changeCount: Int
        let stripped: (originalItems: [NSPasteboardItem], plainText: String)?
        let aborted: Bool
    }

    private var timer: Timer?
    private var pollInFlight = false
    private var pollToken: PollToken?
    private var lastChangeCount = 0
    /// The change count of the write this service made last, so its own plain
    /// text is never stripped again and the shortcut knows the clipboard is
    /// still the stripped one.
    private var lastStrippedChangeCount = 0
    /// The copy the last strip could not read back, with when it was last
    /// attempted: the change stays unconsumed so a later poll retries it,
    /// but no more often than one attempt per backoff window.
    private var lastFailedChangeCount: Int?
    private var lastFailedAt = Date.distantPast
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
    /// The change count of the snapshot written back for a rich paste, so the
    /// re-strip that follows only takes what this paste restored: a copy made
    /// in the meantime belongs to the next poll, which strips it like any
    /// other copy.
    private var restoredChangeCount: Int?
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
            if changeCount == self.lastStrippedChangeCount,
               let original = self.originalItems,
               Date().timeIntervalSince(self.originalCapturedAt) <= Self.snapshotLifetime {
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
    private func forwardPaste(attempt: Int = 0) {
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
        let posted = TransientPaste.shared.pasteCurrentContents(willPostShortcut: willPostShortcut,
                                                                didPostShortcut: didPostShortcut)
        // A transient paste of our own — a snippet, a history entry — can be
        // between its write and its key-up. It clears in a fraction of a
        // second, so the press is tried again instead of being swallowed.
        guard !posted, attempt < 2 else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
            self?.forwardPaste(attempt: attempt + 1)
        }
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
            DispatchQueue.main.async { [weak self] in
                // The history already holds the plain copy this strip
                // produced; the restored content is that same copy coming
                // back with its formatting, not a new one.
                ClipboardHistoryService.shared.ignoreNextChange(upTo: restoredCount)
                self?.restoredChangeCount = restoredCount
            }
            return true
        }, then: { (restored: Bool) in
            guard restored else {
                didFail()
                return
            }
            let posted = TransientPaste.shared.pasteCurrentContents(willPostShortcut: willPostShortcut,
                                                                   didPostShortcut: didPostShortcut,
                                                                   didFail: didFail)
            // Another transient paste holds the lane right now. The restored
            // content stays on the clipboard, so releasing the guard is the
            // whole fix: the watcher strips it again on its next look.
            guard posted else {
                didFail()
                return
            }
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
        stripOnce(sinceChangeCount: nil, onlyIfChangeCount: restoredChangeCount) { [weak self] in
            self?.isRichPasteInFlight = false
        }
    }

    // MARK: - Stripping

    /// Command Bar action: takes the formatting out of the current clipboard
    /// without pasting. A clipboard the watcher already stripped is plain
    /// only, so the decision leaves it alone and this does nothing.
    func clearFormattingNow(attempt: Int = 0) {
        guard AppFeature.pastePlain.isAvailable else { return }
        // A poll in flight owns the lane for a moment; a press that lands in
        // that window is retried rather than dropped in silence.
        guard !pollInFlight else {
            guard attempt < 4 else { return }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
                self?.clearFormattingNow(attempt: attempt + 1)
            }
            return
        }
        stripOnce(sinceChangeCount: nil)
    }

    /// Runs one strip transaction on the lane. `sinceChangeCount` nil makes
    /// the strip run regardless of whether anything changed since the last
    /// look ("Clear formatting now", the re-strip after a rich paste).
    private func stripOnce(sinceChangeCount: Int?,
                           onlyIfChangeCount: Int? = nil,
                           then: (() -> Void)? = nil) {
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
        let failedCount = lastFailedChangeCount
        let failedAt = lastFailedAt
        // Admission is released exactly once per transaction, whichever
        // arrives first: the lane's own finish, or the deadline when a
        // provider that never renders holds it. A lane held for good would
        // otherwise stop every later strip until the app is relaunched.
        let finish = { [weak self] in
            guard let self, !token.hasFinished else { return }
            token.hasFinished = true
            self.pollToken = nil
            self.pollInFlight = false
            then?()
            if self.pendingRestripe { self.runPendingRestripe() }
        }
        GeneralPasteboardAccess.shared.async(timeout: Self.pasteboardTimeout, { isExpired in
            guard !token.isCancelled, !isExpired() else { return nil }
            return Self.stripPasteboard(NSPasteboard.general,
                                        sinceChangeCount: sinceChangeCount,
                                        onlyIfChangeCount: onlyIfChangeCount,
                                        ownLastWriteCount: ownWrite,
                                        ownBundleID: ownBundleID,
                                        excludedApps: excluded,
                                        frontmostBundleID: frontmost,
                                        failedChangeCount: failedCount,
                                        failedAt: failedAt,
                                        transforms: transforms,
                                        isExpired: isExpired)
        }, then: { [weak self] (result: StripTransaction?) in
            guard let self, !token.isCancelled else { return }
            self.applyStrip(result)
            // Nil is the deadline's answer, or a transaction that had
            // nothing to do and left without touching anything: either way
            // the lane is owed no more waiting.
            if result == nil { finish() }
        }, didFinish: { [weak self] (_: StripTransaction?) in
            // Only the transaction that still owns the admission releases it:
            // a fallback may already have handed it to a newer one.
            guard let self, self.pollToken === token else { return }
            finish()
        })
        // A provider that never renders keeps the lane busy past the
        // deadline, and the deadline only stops the answer, not the work.
        // Without this the admission would stay taken and every later strip
        // would be dropped until the app was relaunched.
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.pasteboardTimeout + 1) { [weak self] in
            guard let self, self.pollToken === token else { return }
            token.cancel()
            finish()
        }
    }

    /// Applies a finished transaction on the main thread: remembers the write
    /// the watcher must ignore, keeps the original restorable while the
    /// clipboard still holds the plain text that replaced it, and forgets the
    /// original when someone else copied since.
    private func applyStrip(_ result: StripTransaction?) {
        guard let result else { return }
        if result.aborted {
            // The copy could not be read back and stays rich on the
            // clipboard. The change is deliberately not consumed, so a later
            // poll retries it; `failedAt` keeps that retry bounded to one
            // attempt per backoff window until the copy is replaced.
            lastFailedChangeCount = result.changeCount
            lastFailedAt = Date()
            return
        }
        lastFailedChangeCount = nil
        lastChangeCount = max(lastChangeCount, result.changeCount)
        if let stripped = result.stripped {
            lastStrippedChangeCount = result.changeCount
            originalItems = stripped.originalItems
            originalCapturedAt = Date()
            restoredChangeCount = nil
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
    /// before any content is read: a file copy is never fetched only to be
    /// left alone, and a media copy is asked about its text before its
    /// picture is fetched.
    private static func stripPasteboard(_ pasteboard: NSPasteboard,
                                        sinceChangeCount: Int?,
                                        onlyIfChangeCount: Int?,
                                        ownLastWriteCount: Int,
                                        ownBundleID: String?,
                                        excludedApps: Set<String>,
                                        frontmostBundleID: String?,
                                        failedChangeCount: Int?,
                                        failedAt: Date,
                                        transforms: PastePlainSupport.TransformOptions,
                                        isExpired: () -> Bool) -> StripTransaction? {
        let changeCount = pasteboard.changeCount
        guard !isExpired() else { return nil }
        // A re-strip after a rich paste only takes back what that paste put
        // there. Anything copied since is left for the poll, which would
        // otherwise read it as already seen and leave it formatted.
        if let onlyIfChangeCount, changeCount != onlyIfChangeCount { return nil }
        if let sinceChangeCount, changeCount == sinceChangeCount {
            return StripTransaction(changeCount: changeCount, stripped: nil, aborted: false)
        }
        // A copy that failed to read back is retried, but no more often than
        // one attempt per backoff window: a provider that never answers must
        // not turn the poll into a read loop.
        if changeCount == failedChangeCount,
           Date().timeIntervalSince(failedAt) < Self.retryBackoff {
            return nil
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
        guard !isExpired() else { return nil }
        // A picture beside its text is confirmed against the copy's plain
        // string before anything is read: real text means the picture is a
        // preview of it and the copy strips; a link or file name means the
        // picture is the copy and it stays whole.
        if case .stripWhenTextIsReal = decision {
            let strings = (pasteboard.pasteboardItems ?? [])
                .compactMap { $0.string(forType: .string) }
            guard PastePlainSupport.mediaCopyStrips(plain: strings.joined(separator: "\n")),
                  !isExpired() else {
                return StripTransaction(changeCount: changeCount, stripped: nil, aborted: false)
            }
        } else if case .strip = decision {
            // Formatting the copy can lose: proceed to the snapshot and write.
        } else {
            return StripTransaction(changeCount: changeCount, stripped: nil, aborted: false)
        }
        // Snapshot the original next: the shortcut restores this exact
        // content later. A flavor the item cannot produce — a synthesized
        // stand-in like the external UTF-16 form of a string — is skipped,
        // because a restore never needs it; an item that yields no readable
        // flavor at all aborts the strip, which is retried on a later poll
        // instead of clearing incomplete user data.
        guard let items = pasteboard.pasteboardItems, !items.isEmpty else {
            return StripTransaction(changeCount: changeCount, stripped: nil, aborted: true)
        }
        var snapshot: [NSPasteboardItem] = []
        for item in items {
            let copy = NSPasteboardItem()
            for type in item.types {
                if let data = item.data(forType: type) {
                    copy.setData(data, forType: type)
                }
            }
            guard !copy.types.isEmpty else {
                return StripTransaction(changeCount: changeCount, stripped: nil, aborted: true)
            }
            snapshot.append(copy)
        }
        let plain = snapshot.compactMap(plainText(of:)).joined(separator: "\n")
        guard !plain.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            // Nothing to write: the copy is left as it is and the change
            // counts as seen. Retrying could not produce text either.
            return StripTransaction(changeCount: changeCount, stripped: nil, aborted: false)
        }
        let transformed = PastePlainSupport.applyTransforms(plain, options: transforms)
        // Another app may have copied since the read. Nothing compares and
        // swaps across processes, so this narrows the window, not closes it.
        guard pasteboard.changeCount == changeCount, !isExpired() else {
            return StripTransaction(changeCount: pasteboard.changeCount, stripped: nil, aborted: false)
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
        return StripTransaction(changeCount: pasteboard.changeCount, stripped: (snapshot, transformed),
                                aborted: false)
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
        // The change count alone decides whether there is anything to strip,
        // and it is read on the lane instead of the main thread. Asking first
        // keeps an idle poll to one cheap pasteboard query: the context a
        // strip needs — the app in front through LaunchServices, the excluded
        // list, the transforms — is gathered only for a copy that actually
        // arrived, not eight times a second for an answer that is thrown away.
        pollInFlight = true
        let token = PollToken()
        pollToken = token
        GeneralPasteboardAccess.shared.async { [weak self] in
            let changeCount = NSPasteboard.general.changeCount
            DispatchQueue.main.async {
                guard let self, self.pollToken === token else { return }
                // The watcher stopped since this query was queued, and the
                // answer belongs to the session that closed.
                self.pollToken = nil
                self.pollInFlight = false
                guard self.clipboardNeedsStrip(changeCount: changeCount) else { return }
                self.stripOnce(sinceChangeCount: self.lastChangeCount)
            }
        }
    }

    /// True when the clipboard holds something the watcher has not settled: a
    /// copy it has not seen yet, or one the last attempt could not read back
    /// and whose backoff window has passed. A copy that stayed unreadable is
    /// not asked about on every tick: the retry it deserves is the one
    /// `retryBackoff` schedules, and the lane is left free in between.
    private func clipboardNeedsStrip(changeCount: Int) -> Bool {
        guard changeCount != lastChangeCount else { return false }
        if changeCount == lastFailedChangeCount,
           Date().timeIntervalSince(lastFailedAt) < Self.retryBackoff {
            return false
        }
        return true
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
        restoredChangeCount = nil
        originalItems = nil
        lastStrippedChangeCount = 0
        lastFailedChangeCount = nil
        lastFailedAt = .distantPast
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
