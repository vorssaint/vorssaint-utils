// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import Carbon.HIToolbox
import Combine
import CoreGraphics
import CryptoKit
import Foundation
import ImageIO
import SwiftUI

enum ClipboardHistoryMoveDirection {
    case up
    case down
}

/// Opt-in clipboard history. It records plain text and, optionally, copied
/// images and files; keeps a small local history and avoids obvious
/// secret-looking strings by default.
final class ClipboardHistoryService: ObservableObject {
    static let shared = ClipboardHistoryService()
    static let quickPanelCompactSize = NSSize(width: 560, height: 420)
    static let quickPanelPreviewSize = NSSize(width: 840, height: 500)

    @Published private(set) var entries: [ClipboardHistoryEntry] = [] {
        didSet { entriesStamp &+= 1 }
    }
    @Published private(set) var isRunning = false
    @Published private(set) var shortcutRegistrationFailed = false
    @Published private(set) var quickBatchEntryIDs: Set<UUID> = []
    @Published var quickQuery = "" {
        didSet {
            if quickQuery != oldValue {
                resetQuickSelection()
            }
        }
    }
    @Published private(set) var quickSelectionIndex = 0
    @Published private(set) var quickSelectionIsVisible = false
    @Published private(set) var quickWindowPresentationID = UUID()
    @Published private(set) var quickPreviewPresented = UserDefaults.standard.bool(
        forKey: DefaultsKey.clipboardHistoryQuickPreview
    )

    private var timer: Timer?
    private var lastChangeCount = 0
    /// The poll reads the pasteboard off the main thread: while a password
    /// prompt is up the pasteboard server can take seconds to answer, and a
    /// blocked main thread stalls every event tap with it, so typing freezes
    /// system wide (issue #189). The shared access lane also keeps the URL
    /// cleaner from touching AppKit's mutable pasteboard cache concurrently.
    private var captureInFlight = false
    /// Each capture attempt carries a token so a read that wedged behind a
    /// password prompt can be abandoned without a stale completion (or a stuck
    /// in-flight flag) ever disabling history for good.
    private var captureGeneration = 0
    private var panel: NSPanel?
    private var keyMonitor: Any?
    private var localClickMonitor: Any?
    private var outsideClickMonitor: Any?
    private var activationObserver: NSObjectProtocol?
    private var hotKeyRef: EventHotKeyRef?
    private var hotKeyHandler: EventHandlerRef?
    private var registeredShortcut: GlobalShortcut?
    private var pasteTargetApp: NSRunningApplication?
    /// Writes coalesce per mutation cycle; the JSON encode and the disk write
    /// stay off the main thread (a full history of long texts is real work),
    /// serialized so blobs land in mutation order.
    private static let persistQueue = DispatchQueue(label: "com.vorssaint.utils.clipboard-persist",
                                                    qos: .utility)
    private var persistScheduled = false
    private var persistenceGeneration = 0
    /// True while the history still lives in the legacy UserDefaults blob;
    /// only a store-file write that really landed retires that blob, so a
    /// crash mid-migration never loses entries.
    private var migrateLegacyBlob = false

    private init() {
        load()
    }

    func syncWithPreferences() {
        if AppFeature.clipboardHistory.isAvailable,
           UserDefaults.standard.bool(forKey: DefaultsKey.clipboardHistoryEnabled) {
            start()
            syncHotkey()
        } else {
            stop()
            unregisterHotkey()
        }
    }

    /// Skips capturing pasteboard changes up to the given change count. Quick
    /// tools that rewrite the pasteboard transiently (paste as plain text)
    /// use this so their intermediate writes never churn the history.
    func ignoreNextChange(upTo changeCount: Int) {
        lastChangeCount = max(lastChangeCount, changeCount)
    }

    func copy(_ entry: ClipboardHistoryEntry, completion: @escaping (Bool) -> Void) {
        writeToPasteboard([entry]) { [weak self] copied in
            if copied { self?.touch([entry.id]) }
            completion(copied)
        }
    }

    func copy(_ selectedEntries: [ClipboardHistoryEntry], completion: @escaping (Bool) -> Void) {
        guard !selectedEntries.isEmpty else {
            completion(false)
            return
        }
        writeToPasteboard(selectedEntries) { [weak self] copied in
            if copied { self?.touch(selectedEntries.map(\.id)) }
            completion(copied)
        }
    }

    /// Puts the entries on the general pasteboard through the shared lane and
    /// reports on the main queue. The caller never waits: a lane wedged behind
    /// an app that promised pasteboard content and stopped answering delays
    /// the copy instead of freezing the app (issue #887).
    private func writeToPasteboard(_ list: [ClipboardHistoryEntry],
                                   completion: @escaping (Bool) -> Void) {
        guard let write = Self.plannedWrite(for: list) else {
            completion(false)
            return
        }
        GeneralPasteboardAccess.shared.async({ () -> Int in
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            write(pasteboard)
            return pasteboard.changeCount
        }, then: { [weak self] changeCount in
            // lastChangeCount stays owned by the main queue, where the capture
            // poll compares against it. Assigning it on the lane would let a
            // copy's own change count land after the poll had already read the
            // old one, and history would record the app's own write as a new
            // copy by the user.
            if let self { self.lastChangeCount = max(self.lastChangeCount, changeCount) }
            completion(true)
        })
    }

    /// What to put on the pasteboard once it is cleared, or nil when the
    /// content is gone (image purged from the store, files deleted or on an
    /// ejected volume) and the copy must abort with the user's clipboard
    /// intact. Resolving on the caller's thread also keeps the AppKit work a
    /// write may need — RTFD attachments, TIFF rendering — on the main thread
    /// it has always run on; only the pasteboard calls move to the lane.
    private static func plannedWrite(for list: [ClipboardHistoryEntry])
        -> ((NSPasteboard) -> Void)? {
        if list.count == 1, let entry = list.first {
            switch entry.kind {
            case .text:
                return { $0.setString(entry.text, forType: .string) }
            case .image:
                guard let name = entry.imageFile,
                      let data = ClipboardImageStore.imageData(named: name) else { return nil }
                // TIFF alongside PNG: some paste targets only take TIFF.
                let tiff = NSBitmapImageRep(data: data)?.tiffRepresentation
                return { pasteboard in
                    pasteboard.setData(data, forType: .png)
                    if let tiff { pasteboard.setData(tiff, forType: .tiff) }
                }
            case .files:
                let urls = entry.filePaths
                    .map { URL(fileURLWithPath: $0) }
                    .filter { FileManager.default.fileExists(atPath: $0.path) }
                guard !urls.isEmpty else { return nil }
                return { $0.writeObjects(urls as [NSURL]) }
            }
        }

        // Batches: an all-files selection pastes as the files themselves; a
        // selection with images pastes as rich text with the images embedded;
        // anything else combines as text (files contribute paths).
        switch ClipboardHistoryBatch.pasteMode(for: list) {
        case let .files(paths):
            let urls = paths.map { URL(fileURLWithPath: $0) }
                .filter { FileManager.default.fileExists(atPath: $0.path) }
            guard !urls.isEmpty else { return nil }
            return { $0.writeObjects(urls as [NSURL]) }
        case let .text(combined):
            return { $0.setString(combined, forType: .string) }
        case let .rich(parts):
            guard let rich = richBatchAttributedString(parts) else { return nil }
            let plain = ClipboardHistoryBatch.richPlainText(parts)
            return { pasteboard in
                pasteboard.writeObjects([rich])
                if !plain.isEmpty { pasteboard.setString(plain, forType: .string) }
            }
        case nil:
            guard let first = list.first else { return nil }
            return plannedWrite(for: [first])
        }
    }

    /// Text and images interleaved in list order, as one attributed string:
    /// rich targets (Notes, Mail, TextEdit) paste everything together. Image
    /// attachments travel as PNG file wrappers, which RTFD serializes intact.
    /// A selected image whose stored payload is gone aborts the whole write
    /// (returns nil), keeping the same invariant as the single-entry path:
    /// stale content never silently vanishes from a paste after the user's
    /// clipboard was already overwritten.
    private static func richBatchAttributedString(_ parts: [ClipboardHistoryBatch.RichPart])
        -> NSAttributedString? {
        let result = NSMutableAttributedString()
        for part in parts {
            switch part {
            case let .text(text):
                result.append(NSAttributedString(string: text + "\n"))
            case let .image(name):
                guard let data = ClipboardImageStore.imageData(named: name) else { return nil }
                let wrapper = FileWrapper(regularFileWithContents: data)
                wrapper.preferredFilename = name
                let attachment = NSTextAttachment(fileWrapper: wrapper)
                result.append(NSAttributedString(attachment: attachment))
                result.append(NSAttributedString(string: "\n"))
            }
        }
        return result.length > 0 ? result : nil
    }

    private func touch(_ entryIDs: [UUID]) {
        var didUpdate = false
        let now = Date()
        for entryID in entryIDs {
            if let index = entries.firstIndex(where: { $0.id == entryID }) {
                entries[index].copiedAt = now
                didUpdate = true
            }
        }
        if didUpdate {
            save()
        }
    }

    func togglePin(_ entry: ClipboardHistoryEntry) {
        guard let index = entries.firstIndex(where: { $0.id == entry.id }) else { return }
        let previousEntries = entries
        var updated = entries.remove(at: index)
        if updated.isPinned {
            updated.pinnedAt = nil
            entries.insert(updated, at: firstRecentIndex)
        } else {
            updated.pinnedAt = Date()
            entries.insert(updated, at: 0)
        }
        normalizeEntryOrder()
        trimToLimit()
        guard entries.contains(where: { $0.id == entry.id }),
              ClipboardHistoryEditing.preservesPinnedEntries(from: previousEntries, in: entries)
        else {
            entries = previousEntries
            return
        }
        save()
    }

    func remove(_ entry: ClipboardHistoryEntry) {
        entries.removeAll { $0.id == entry.id }
        var selected = quickBatchEntryIDs
        selected.remove(entry.id)
        quickBatchEntryIDs = selected
        save()
    }

    @discardableResult
    func updateText(_ entry: ClipboardHistoryEntry, to draft: String) -> Bool {
        guard entry.kind == .text,
              let text = ClipboardHistoryEditing.storableText(draft),
              let index = entries.firstIndex(where: { $0.id == entry.id })
        else { return false }
        if entries[index].text == text { return true }
        let previousEntries = entries
        entries[index].text = text
        trimToLimit()
        guard entries.contains(where: { $0.id == entry.id }),
              ClipboardHistoryEditing.preservesPinnedEntries(from: previousEntries, in: entries)
        else {
            entries = previousEntries
            return false
        }
        save()
        return true
    }

    func clearRecent() {
        entries.removeAll { !$0.isPinned }
        pruneQuickBatchSelection()
        save()
    }

    func clearAll() {
        clearRecent()
    }

    func canMove(_ entry: ClipboardHistoryEntry, _ direction: ClipboardHistoryMoveDirection) -> Bool {
        moveDestination(for: entry, direction) != nil
    }

    func move(_ entry: ClipboardHistoryEntry, _ direction: ClipboardHistoryMoveDirection) {
        guard let from = entries.firstIndex(where: { $0.id == entry.id }),
              let to = moveDestination(for: entry, direction)
        else { return }
        entries.swapAt(from, to)
        save()
    }

    var pinnedEntries: [ClipboardHistoryEntry] {
        entries.filter(\.isPinned)
    }

    var recentEntries: [ClipboardHistoryEntry] {
        entries.filter { !$0.isPinned }
    }

    var filteredQuickEntries: [ClipboardHistoryEntry] {
        filteredEntries(matching: quickQuery)
    }

    var selectedQuickEntryID: UUID? {
        selectedQuickEntry?.id
    }

    var quickBatchCount: Int {
        quickBatchEntries.count
    }

    var selectedQuickEntry: ClipboardHistoryEntry? {
        let matches = filteredQuickEntries
        guard !matches.isEmpty else { return nil }
        return matches[clampedQuickSelectionIndex(for: matches.count)]
    }

    func isQuickBatchSelected(_ entry: ClipboardHistoryEntry) -> Bool {
        quickBatchEntryIDs.contains(entry.id)
    }

    func toggleQuickBatchSelection(_ entry: ClipboardHistoryEntry) {
        if let index = filteredQuickEntries.firstIndex(where: { $0.id == entry.id }) {
            quickSelectionIndex = index
        }
        var selected = quickBatchEntryIDs
        if selected.contains(entry.id) {
            selected.remove(entry.id)
        } else {
            selected.insert(entry.id)
        }
        quickBatchEntryIDs = selected
    }

    /// Finder-style shift-click: selects everything between the last row the
    /// user touched and the clicked one.
    func extendQuickBatchSelection(to entry: ClipboardHistoryEntry) {
        let matches = filteredQuickEntries
        guard let target = matches.firstIndex(where: { $0.id == entry.id }) else { return }
        let anchor = clampedQuickSelectionIndex(for: matches.count)
        let ids = ClipboardHistoryBatch.rangeSelectionIDs(allIDs: matches.map(\.id),
                                                          anchor: anchor,
                                                          target: target)
        quickBatchEntryIDs = quickBatchEntryIDs.union(ids)
        quickSelectionIndex = target
        quickSelectionIsVisible = true
    }

    /// Selects every visible result, so "search, select all, copy" works.
    func selectAllQuickEntries() {
        let visible = filteredQuickEntries.map(\.id)
        guard !visible.isEmpty else { return }
        quickBatchEntryIDs = quickBatchEntryIDs.union(visible)
    }

    func toggleSelectedQuickEntryBatchSelection() {
        guard let entry = selectedQuickEntry else { return }
        toggleQuickBatchSelection(entry)
    }

    func clearQuickBatchSelection() {
        quickBatchEntryIDs = []
    }

    /// Bumped by the `entries` didSet; lets the search cache below notice any
    /// mutation without every mutating site having to remember it.
    private var entriesStamp = 0
    private var filterCache: (query: String, stamp: Int, imageLabel: String,
                              result: [ClipboardHistoryEntry])?

    func filteredEntries(matching query: String) -> [ClipboardHistoryEntry] {
        // One ranking pass over a large history of long texts costs real
        // time, and SwiftUI asks for the filtered list many times per
        // render. The last result is reused until the query, the language
        // or the history itself changes.
        let imageLabel = FeatureStrings.clipboard(L10n.shared.language).imageEntryLabel
        if let cache = filterCache, cache.query == query,
           cache.stamp == entriesStamp, cache.imageLabel == imageLabel {
            return cache.result
        }
        let candidates = entries.enumerated().map { index, entry in
            ClipboardHistorySearchCandidate(index: index,
                                            text: entry.searchableText(imageLabel: imageLabel),
                                            isPinned: entry.isPinned)
        }
        let result = ClipboardHistorySearch.rankedIndexes(candidates: candidates, matching: query)
            .map { entries[$0] }
        filterCache = (query, entriesStamp, imageLabel, result)
        return result
    }

    func copyQuickEntry(at index: Int) {
        let matches = filteredQuickEntries
        guard matches.indices.contains(index) else { return }
        copyQuickEntry(matches[index])
    }

    func copySelectedQuickEntry() {
        let selectedEntries = quickEntriesForPrimaryAction()
        guard !selectedEntries.isEmpty else { return }
        if selectedEntries.count == 1 {
            copyQuickEntry(selectedEntries[0])
        } else {
            copyQuickEntries(selectedEntries)
        }
    }

    func copySelectedQuickEntryOnly() {
        let selectedEntries = quickEntriesForPrimaryAction()
        guard !selectedEntries.isEmpty else { return }
        if selectedEntries.count == 1 {
            copyOnlyQuickEntry(selectedEntries[0])
        } else {
            copyOnlyQuickEntries(selectedEntries)
        }
    }

    func togglePinSelectedQuickEntry() {
        guard let entry = selectedQuickEntry else { return }
        togglePin(entry)
        quickSelectionIndex = clampedQuickSelectionIndex(for: filteredQuickEntries.count)
    }

    func removeSelectedQuickEntry() {
        guard let entry = selectedQuickEntry else { return }
        remove(entry)
        quickSelectionIndex = clampedQuickSelectionIndex(for: filteredQuickEntries.count)
    }

    /// Where the pointer sat when the keyboard last moved the selection. Rows
    /// scrolling under a still pointer report hover, and hover would otherwise
    /// take the preview back from the row the arrow keys chose.
    private(set) var keyboardSelectionPointer: NSPoint?

    func moveQuickSelection(_ delta: Int) {
        // Out of the way while the keys drive, back at the first real move.
        NSCursor.setHiddenUntilMouseMoves(true)
        keyboardSelectionPointer = NSEvent.mouseLocation
        let count = filteredQuickEntries.count
        guard count > 0 else {
            quickSelectionIndex = 0
            quickSelectionIsVisible = false
            return
        }
        if !quickSelectionIsVisible {
            quickSelectionIndex = clampedQuickSelectionIndex(for: count)
            quickSelectionIsVisible = true
            return
        }
        quickSelectionIndex = min(max(quickSelectionIndex + delta, 0), count - 1)
    }

    /// The window leaves the screen at once; the paste waits for the write,
    /// because pasting before it lands would paste whatever the user had
    /// copied before. A stale entry leaves the clipboard untouched and pastes
    /// nothing at all.
    func copyQuickEntry(_ entry: ClipboardHistoryEntry) {
        let target = pasteTargetApp
        hideHistoryWindow()
        pasteTargetApp = nil
        copy(entry) { [weak self] copied in
            guard copied else { return }
            self?.pasteIntoPreviousApp(target)
        }
    }

    func copyQuickEntries(_ selectedEntries: [ClipboardHistoryEntry]) {
        let target = pasteTargetApp
        hideHistoryWindow()
        pasteTargetApp = nil
        copy(selectedEntries) { [weak self] copied in
            guard copied else { return }
            self?.pasteIntoPreviousApp(target)
        }
    }

    /// No paste follows these two, so nothing has to wait for the write: the
    /// window closes now and a stale entry simply leaves the clipboard as the
    /// user left it.
    func copyOnlyQuickEntry(_ entry: ClipboardHistoryEntry) {
        copy(entry) { _ in }
        hideHistoryWindow()
        pasteTargetApp = nil
    }

    func copyOnlyQuickEntries(_ selectedEntries: [ClipboardHistoryEntry]) {
        copy(selectedEntries) { _ in }
        hideHistoryWindow()
        pasteTargetApp = nil
    }

    private func start() {
        guard timer == nil else {
            isRunning = true
            return
        }
        let timer = Timer(timeInterval: 0.8, repeats: true) { [weak self] _ in
            self?.captureIfChanged()
        }
        timer.tolerance = 0.25
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
        isRunning = true
        ClipboardIgnoredApps.shared.setHistoryRunning(true)
        baselinePasteboard()
    }

    private func stop() {
        timer?.invalidate()
        timer = nil
        isRunning = false
        ClipboardIgnoredApps.shared.setHistoryRunning(false)
        captureGeneration &+= 1
        captureInFlight = false
    }

    /// What the background pasteboard read hands back to the main thread.
    private enum CapturedContent {
        case files([String])
        case image((data: Data, width: Int, height: Int))
        case text(String)
    }

    /// Establishes the starting change count on the same background lane used
    /// by later reads. Existing clipboard content is not added just because
    /// history was enabled, matching the previous synchronous baseline.
    private func baselinePasteboard() {
        guard !captureInFlight else { return }
        captureInFlight = true
        captureGeneration &+= 1
        let generation = captureGeneration
        scheduleCaptureTimeout(generation: generation)
        GeneralPasteboardAccess.shared.async { [weak self] in
            let changeCount = NSPasteboard.general.changeCount
            DispatchQueue.main.async {
                guard let self, self.captureGeneration == generation else { return }
                self.captureInFlight = false
                guard self.isRunning else { return }
                self.lastChangeCount = max(self.lastChangeCount, changeCount)
            }
        }
    }

    private func scheduleCaptureTimeout(generation: Int) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) { [weak self] in
            guard let self, self.captureGeneration == generation, self.captureInFlight else { return }
            self.captureInFlight = false
        }
    }

    private func captureIfChanged() {
        // Only ever one read in flight: while a password prompt holds the
        // pasteboard server, a read can take seconds, and letting ticks pile
        // up would spawn a thread each time.
        guard !captureInFlight else { return }
        let sinceChangeCount = lastChangeCount
        let includeImagesFiles = UserDefaults.standard.bool(
            forKey: DefaultsKey.clipboardHistoryIncludeImagesFiles)
        captureInFlight = true
        captureGeneration &+= 1
        let generation = captureGeneration
        // If the read wedges (a pasteboard server stuck behind a lingering
        // password prompt), free the flag so later copies are still recorded;
        // the abandoned read is ignored by its stale generation when it ends.
        scheduleCaptureTimeout(generation: generation)
        GeneralPasteboardAccess.shared.async { [weak self] in
            let changeCount = NSPasteboard.general.changeCount
            let content: CapturedContent? = changeCount != sinceChangeCount
                ? Self.readPasteboard(includeImagesFiles: includeImagesFiles)
                : nil
            DispatchQueue.main.async {
                guard let self, self.captureGeneration == generation else { return }
                self.captureInFlight = false
                // Asked once per check and before anything can return early,
                // so the window it answers for always ends here: whether a
                // listed app could be the one that copied since the last look.
                let excludedSource = ClipboardIgnoredApps.shared.excludedSourceSinceLastCheck()
                // Strictly forward: never re-capture a change that
                // ignoreNextChange() consumed while the read was running.
                guard changeCount > self.lastChangeCount else { return }
                self.lastChangeCount = changeCount
                guard self.isRunning, !excludedSource, let content else { return }
                switch content {
                case .files(let paths): self.promoteFiles(paths)
                case .image(let image): self.promoteImage(image)
                case .text(let text): self.promote(text)
                }
            }
        }
    }

    /// Runs on the shared pasteboard lane: everything in here may block behind
    /// the pasteboard server, which is exactly why it stays off the main thread.
    private static func readPasteboard(includeImagesFiles: Bool) -> CapturedContent? {
        let pasteboard = NSPasteboard.general
        // An app can mark what it puts on the pasteboard as a secret, which is
        // what the apps that keep passwords do when they hand one over. Said
        // that plainly by the app itself, it is taken at its word and the
        // content is never even read, whatever the other options say.
        if ClipboardHistorySensitiveText.isConcealed((pasteboard.types ?? []).map(\.rawValue)) {
            return nil
        }
        // Files first: a Finder copy also carries name strings, and a browser
        // image copy also carries URL text, so richer content wins over its
        // own textual fallbacks.
        if includeImagesFiles {
            if let paths = copiedFilePaths(from: pasteboard) {
                if ClipboardHistoryCapturePolicy.isCopiedScreenshot(
                    paths, in: ScreenshotSupport.copiedFilesDirectory()) {
                    guard let image = copiedPNGImage(from: pasteboard) else { return nil }
                    return .image(image)
                }
                return .files(paths)
            }
            if let image = copiedPNGImage(from: pasteboard) { return .image(image) }
        }
        guard let text = ClipboardHistoryPasteboardText.preferredText(
            webURLString: webURLString(from: pasteboard),
            plainText: pasteboard.string(forType: .string)
        ) else { return nil }
        return .text(text)
    }

    private static let maxCopiedFiles = 100
    private static let maxImageBytes = 16 * 1024 * 1024
    private static let maxRawImageBytes = 64 * 1024 * 1024

    private static func copiedFilePaths(from pasteboard: NSPasteboard) -> [String]? {
        guard let urls = pasteboard.readObjects(forClasses: [NSURL.self],
                                                options: [.urlReadingFileURLsOnly: true]) as? [URL],
              !urls.isEmpty,
              urls.count <= maxCopiedFiles
        else { return nil }
        return urls.map { $0.standardizedFileURL.path }
    }

    private static func copiedPNGImage(from pasteboard: NSPasteboard)
        -> (data: Data, width: Int, height: Int)? {
        let png = pasteboard.data(forType: .png)
        guard let source = png ?? pasteboard.data(forType: .tiff),
              source.count <= maxRawImageBytes,
              let rep = NSBitmapImageRep(data: source),
              rep.pixelsWide > 0, rep.pixelsHigh > 0
        else { return nil }
        let data: Data
        if let png {
            data = png
        } else if let converted = rep.representation(using: .png, properties: [:]) {
            data = converted
        } else {
            return nil
        }
        guard data.count <= maxImageBytes else { return nil }
        return (data, rep.pixelsWide, rep.pixelsHigh)
    }

    private func promoteImage(_ image: (data: Data, width: Int, height: Int)) {
        let hash = Self.sha256Hex(image.data)
        if let existing = entries.first(where: { $0.kind == .image && $0.imageHash == hash }) {
            entries.removeAll { $0.id == existing.id }
            insertPromoted(ClipboardHistoryEntry(id: existing.id,
                                                 text: "",
                                                 copiedAt: Date(),
                                                 pinnedAt: existing.pinnedAt,
                                                 kind: .image,
                                                 imageFile: existing.imageFile,
                                                 imageHash: hash,
                                                 imageWidth: existing.imageWidth,
                                                 imageHeight: existing.imageHeight))
        } else {
            guard let name = ClipboardImageStore.store(image.data) else { return }
            insertPromoted(ClipboardHistoryEntry(text: "",
                                                 kind: .image,
                                                 imageFile: name,
                                                 imageHash: hash,
                                                 imageWidth: image.width,
                                                 imageHeight: image.height))
        }
        normalizeEntryOrder()
        trimToLimit()
        save()
    }

    private func promoteFiles(_ paths: [String]) {
        let existing = entries.first(where: { $0.kind == .files && $0.filePaths == paths })
        entries.removeAll { $0.kind == .files && $0.filePaths == paths }
        if let existing {
            insertPromoted(ClipboardHistoryEntry(id: existing.id,
                                                 text: "",
                                                 copiedAt: Date(),
                                                 pinnedAt: existing.pinnedAt,
                                                 kind: .files,
                                                 filePaths: paths))
        } else {
            insertPromoted(ClipboardHistoryEntry(text: "", kind: .files, filePaths: paths))
        }
        normalizeEntryOrder()
        trimToLimit()
        save()
    }

    private static func sha256Hex(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    private static func webURLString(from pasteboard: NSPasteboard) -> String? {
        let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: nil) as? [URL]
        if let url = urls?.first(where: { isWebURL($0) }) {
            return url.absoluteString
        }
        for type in [NSPasteboard.PasteboardType("public.url"),
                     NSPasteboard.PasteboardType("NSURLPboardType")] {
            if let value = pasteboard.string(forType: type),
               let url = URL(string: value),
               isWebURL(url) {
                return url.absoluteString
            }
        }
        return nil
    }

    private static func isWebURL(_ url: URL) -> Bool {
        guard let scheme = url.scheme?.lowercased() else { return false }
        return (scheme == "http" || scheme == "https") && url.host != nil
    }

    private func promote(_ raw: String) {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, text.count <= ClipboardHistoryEditing.maxCharacters else { return }
        if UserDefaults.standard.bool(forKey: DefaultsKey.clipboardHistorySkipSensitive),
           looksSensitive(text) {
            return
        }

        let existing = entries.first(where: { $0.kind == .text && $0.text == text })
        entries.removeAll { $0.kind == .text && $0.text == text }
        if let existing {
            insertPromoted(ClipboardHistoryEntry(id: existing.id,
                                                 text: text,
                                                 copiedAt: Date(),
                                                 pinnedAt: existing.pinnedAt))
        } else {
            insertPromoted(ClipboardHistoryEntry(text: text))
        }
        normalizeEntryOrder()
        trimToLimit()
        save()
    }

    func trimToLimit() {
        let limit = Defaults.sanitizedClipboardHistoryLimit(
            UserDefaults.standard.integer(forKey: DefaultsKey.clipboardHistoryLimit)
        )
        let trimmed = ClipboardHistoryEditing.retainedEntries(entries, recentLimit: limit)
        if trimmed != entries {
            entries = trimmed
            save()
        }
    }

    private var firstRecentIndex: Int {
        entries.firstIndex { !$0.isPinned } ?? entries.endIndex
    }

    private func insertPromoted(_ entry: ClipboardHistoryEntry) {
        if entry.isPinned {
            entries.insert(entry, at: 0)
        } else {
            entries.insert(entry, at: firstRecentIndex)
        }
    }

    private func normalizeEntryOrder() {
        let pinned = entries.filter(\.isPinned)
        let recent = entries.filter { !$0.isPinned }
        entries = pinned + recent
    }

    private func moveDestination(for entry: ClipboardHistoryEntry,
                                 _ direction: ClipboardHistoryMoveDirection) -> Int? {
        let groupIndices = entries.indices.filter { entries[$0].isPinned == entry.isPinned }
        guard let groupPosition = groupIndices.firstIndex(where: { entries[$0].id == entry.id }) else {
            return nil
        }
        switch direction {
        case .up:
            guard groupPosition > groupIndices.startIndex else { return nil }
            return groupIndices[groupIndices.index(before: groupPosition)]
        case .down:
            let next = groupIndices.index(after: groupPosition)
            guard next < groupIndices.endIndex else { return nil }
            return groupIndices[next]
        }
    }

    private func looksSensitive(_ text: String) -> Bool {
        ClipboardHistorySensitiveText.looksSensitive(text)
    }

    /// The history file. Entries used to live as one blob inside UserDefaults,
    /// but the preferences plist is rewritten whole on every copy and macOS
    /// pushes back past a few megabytes, which a large history of long texts
    /// can reach. Without a resolvable home the blob stays in UserDefaults.
    private static var storeURL: URL? {
        PrivateFileStore.containerURL?.appendingPathComponent("ClipboardHistory.json")
    }

    private static func storedHistoryData(at url: URL) -> Data? {
        guard let values = try? url.resourceValues(
            forKeys: [.fileSizeKey, .isRegularFileKey, .isSymbolicLinkKey]),
              values.isRegularFile == true,
              values.isSymbolicLink != true,
              ClipboardHistoryEditing.canLoadEncodedHistory(byteCount: values.fileSize),
              let data = try? Data(contentsOf: url, options: .mappedIfSafe),
              ClipboardHistoryEditing.canLoadEncodedHistory(byteCount: data.count)
        else { return nil }
        return data
    }

    private func load() {
        let fileData = Self.storeURL.flatMap { Self.storedHistoryData(at: $0) }
        var data = fileData
        if data == nil,
           let legacy = UserDefaults.standard.data(forKey: DefaultsKey.clipboardHistoryEntries) {
            data = legacy
            migrateLegacyBlob = Self.storeURL != nil
        }
        guard let data,
              ClipboardHistoryEditing.canLoadEncodedHistory(byteCount: data.count),
              let decoded = try? JSONDecoder().decode([ClipboardHistoryEntry].self, from: data)
        else { return }
        if fileData != nil,
           UserDefaults.standard.object(forKey: DefaultsKey.clipboardHistoryEntries) != nil {
            // The file decoded and is the durable source. A legacy blob still
            // around (a kill inside the migration window, or a downgrade
            // round trip) would sit in the preferences plist forever.
            UserDefaults.standard.removeObject(forKey: DefaultsKey.clipboardHistoryEntries)
        }
        entries = decoded
        normalizeEntryOrder()
        trimToLimit()
        // Sweep image files that lost their entry (crash between write and save).
        ClipboardImageStore.cleanup(keeping: Set(entries.compactMap(\.imageFile)))
        // A history read from the legacy blob migrates right away instead of
        // waiting for the next copy: launching once is enough to leave
        // UserDefaults behind.
        if migrateLegacyBlob {
            save()
        }
    }

    /// Coalesces the saves of one mutation cycle into a single persist.
    private func save() {
        persistenceGeneration &+= 1
        guard !persistScheduled else { return }
        persistScheduled = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.persistScheduled = false
            self.persist()
        }
    }

    private func persist() {
        let snapshot = entries
        let generation = persistenceGeneration
        let retireLegacyBlob = migrateLegacyBlob
        Self.persistQueue.async { [weak self] in
            guard let encoded = ClipboardHistoryEditing.encodedHistory(snapshot) else { return }
            let data = encoded.data
            // The PNG sweep waits for the JSON to land and runs back on the
            // main thread against the list as it is then. Sweeping first
            // could strand an entry whose PNG died if the process fell in
            // between; the reverse at worst leaves an orphaned PNG that the
            // launch sweep heals. The main thread also keeps it from racing
            // a just-stored PNG whose entry has not landed in the list yet.
            func finishPersist() {
                DispatchQueue.main.async {
                    guard let self else { return }
                    if self.persistenceGeneration == generation,
                       encoded.entries != snapshot {
                        self.entries = encoded.entries
                    }
                    ClipboardImageStore.cleanup(keeping: Set(self.entries.compactMap(\.imageFile)))
                }
            }
            guard let url = Self.storeURL else {
                UserDefaults.standard.set(data, forKey: DefaultsKey.clipboardHistoryEntries)
                finishPersist()
                return
            }
            PrivateFileStore.createDirectory(at: url.deletingLastPathComponent())
            // Only a write that really landed retires the legacy blob, so a
            // failed save leaves the history readable from somewhere.
            guard PrivateFileStore.write(data, to: url) else { return }
            finishPersist()
            if retireLegacyBlob {
                UserDefaults.standard.removeObject(forKey: DefaultsKey.clipboardHistoryEntries)
                DispatchQueue.main.async { self?.migrateLegacyBlob = false }
            }
        }
    }

    /// Runs any deferred persist right now and waits for the write to land.
    /// Quit must not race the async pipeline: the last mutation of a session
    /// (often a privacy minded Clear) has to be durable before the process
    /// dies.
    func flushBeforeTermination() {
        if persistScheduled {
            persistScheduled = false
            persist()
        }
        Self.persistQueue.sync {}
    }

    // MARK: - Shortcut

    func syncHotkey() {
        let wanted = UserDefaults.standard.bool(forKey: DefaultsKey.clipboardHistoryEnabled)
            && UserDefaults.standard.bool(forKey: DefaultsKey.clipboardHistoryShortcutEnabled)
        wanted ? registerHotkey() : unregisterHotkey()
    }

    private func registerHotkey() {
        let shortcut = GlobalShortcut.saved(for: DefaultsKey.clipboardHistoryShortcut,
                                            fallback: .clipboardDefault)
        if hotKeyRef != nil, registeredShortcut == shortcut { return }
        unregisterHotkey()
        if hotKeyHandler == nil {
            var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                     eventKind: UInt32(kEventHotKeyPressed))
            InstallEventHandler(GetEventDispatcherTarget(), { _, event, userData -> OSStatus in
                guard let userData else { return OSStatus(eventNotHandledErr) }
                var id = EventHotKeyID()
                if let event {
                    GetEventParameter(event, EventParamName(kEventParamDirectObject),
                                      EventParamType(typeEventHotKeyID), nil,
                                      MemoryLayout<EventHotKeyID>.size, nil, &id)
                }
                guard id.signature == 0x5655_434C, id.id == 3
                else { return OSStatus(eventNotHandledErr) }
                let service = Unmanaged<ClipboardHistoryService>.fromOpaque(userData).takeUnretainedValue()
                DispatchQueue.main.async { service.toggleHistoryWindow() }
                return noErr
            }, 1, &spec, Unmanaged.passUnretained(self).toOpaque(), &hotKeyHandler)
        }
        let id = EventHotKeyID(signature: 0x5655_434C, id: 3) // 'VUCL'
        var ref: EventHotKeyRef?
        let status = RegisterEventHotKey(shortcut.carbonKeyCode,
                                         shortcut.carbonModifiers,
                                         id, GetEventDispatcherTarget(), 0, &ref)
        if status == noErr, let ref {
            hotKeyRef = ref
            registeredShortcut = shortcut
            shortcutRegistrationFailed = false
        } else {
            hotKeyRef = nil
            registeredShortcut = nil
            shortcutRegistrationFailed = true
        }
    }

    /// Lets go of the global key while a shortcut field is listening, so the
    /// user can record the very combination this feature uses. The next
    /// `syncWithPreferences` takes it back.
    func suspendShortcut() { unregisterHotkey() }

    private func unregisterHotkey() {
        if let hotKeyRef { UnregisterEventHotKey(hotKeyRef) }
        hotKeyRef = nil
        registeredShortcut = nil
        shortcutRegistrationFailed = false
    }

    // MARK: - Quick window

    func toggleQuickPreview() {
        setQuickPreviewPresented(!quickPreviewPresented)
    }

    func setQuickPreviewPresented(_ presented: Bool) {
        guard presented != quickPreviewPresented else { return }
        quickPreviewPresented = presented
        UserDefaults.standard.set(presented, forKey: DefaultsKey.clipboardHistoryQuickPreview)
        guard let panel, panel.isVisible else { return }
        resize(panel,
               to: presented ? Self.quickPanelPreviewSize : Self.quickPanelCompactSize,
               animated: true)
    }

    func toggleHistoryWindow() {
        if panel?.isVisible == true {
            hideHistoryWindow()
        } else {
            showHistoryWindow()
        }
    }

    func showHistoryWindow() {
        let panel = ensurePanel()
        rememberPasteTarget()
        quickWindowPresentationID = UUID()
        quickQuery = ""
        clearQuickBatchSelection()
        resetQuickSelection()
        position(panel)
        installKeyMonitor(for: panel)
        installDismissMonitors(for: panel)
        panel.alphaValue = 1
        panel.orderFrontRegardless()
        panel.makeKey()
    }

    func hideHistoryWindow() {
        removeKeyMonitor()
        removeDismissMonitors()
        panel?.orderOut(nil)
        clearQuickBatchSelection()
    }

    private func rememberPasteTarget() {
        let ownBundleID = Bundle.main.bundleIdentifier
        guard let app = NSWorkspace.shared.frontmostApplication,
              app.bundleIdentifier != ownBundleID,
              app.activationPolicy == .regular,
              !app.isTerminated
        else {
            pasteTargetApp = nil
            return
        }
        pasteTargetApp = app
    }

    private func pasteIntoPreviousApp(_ app: NSRunningApplication?) {
        guard let app, !app.isTerminated else { return }
        app.activate(options: [])
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
            Self.postPasteShortcut()
        }
    }

    private static func postPasteShortcut() {
        guard let source = CGEventSource(stateID: .hidSystemState),
              let keyDown = CGEvent(keyboardEventSource: source,
                                    virtualKey: CGKeyCode(kVK_ANSI_V),
                                    keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: source,
                                  virtualKey: CGKeyCode(kVK_ANSI_V),
                                  keyDown: false)
        else { return }
        keyDown.flags = .maskCommand
        keyUp.flags = .maskCommand
        keyDown.post(tap: .cghidEventTap)
        keyUp.post(tap: .cghidEventTap)
    }

    private func ensurePanel() -> NSPanel {
        if let panel { return panel }
        let initialSize = quickPreviewPresented ? Self.quickPanelPreviewSize : Self.quickPanelCompactSize
        let panel = NSPanel(contentRect: NSRect(origin: .zero, size: initialSize),
                            styleMask: [.titled, .closable, .fullSizeContentView, .nonactivatingPanel],
                            backing: .buffered,
                            defer: false)
        panel.title = FeatureStrings.clipboard(L10n.shared.language).title
        panel.titlebarAppearsTransparent = true
        panel.titleVisibility = .hidden
        panel.standardWindowButton(.closeButton)?.isHidden = true
        panel.standardWindowButton(.miniaturizeButton)?.isHidden = true
        panel.standardWindowButton(.zoomButton)?.isHidden = true
        panel.isReleasedWhenClosed = false
        // Movable-by-background turns ⌘-click into a window-background grab
        // before any row sees it, which silently broke modifier clicks on
        // rows. The title bar strip still drags the window.
        panel.isMovableByWindowBackground = false
        panel.hidesOnDeactivate = false
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        let host = NSHostingController(rootView: ClipboardQuickPanelView())
        // The SwiftUI root owns the exact compact/preview frames and extends
        // under the title bar, so preferred-size tracking would add that bar
        // to the panel height a second time.
        host.sizingOptions = []
        panel.contentViewController = host
        panel.setFrame(NSRect(origin: .zero, size: initialSize),
                       display: false)
        self.panel = panel
        return panel
    }

    private func position(_ panel: NSPanel) {
        let size = quickPreviewPresented ? Self.quickPanelPreviewSize : Self.quickPanelCompactSize
        let screen = NSScreen.pointerVisibleFrame
        let x = screen.midX - size.width / 2
        let y = min(screen.maxY - size.height - 54, screen.midY - size.height / 2)
        panel.setFrame(NSRect(x: max(screen.minX + 16, min(x, screen.maxX - size.width - 16)),
                              y: max(screen.minY + 16, y),
                              width: size.width,
                              height: size.height),
                       display: true,
                       animate: false)
    }

    private func resize(_ panel: NSPanel, to contentSize: NSSize, animated: Bool) {
        let current = panel.frame
        var target = NSRect(origin: .zero, size: contentSize)
        target.origin.x = current.midX - target.width / 2
        target.origin.y = current.midY - target.height / 2

        let visibleFrame = panel.screen?.visibleFrame ?? NSScreen.pointerVisibleFrame
        target.origin.x = max(visibleFrame.minX + 16,
                              min(target.origin.x, visibleFrame.maxX - target.width - 16))
        target.origin.y = max(visibleFrame.minY + 16,
                              min(target.origin.y, visibleFrame.maxY - target.height - 16))
        panel.setFrame(target,
                       display: true,
                       animate: animated && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion)
    }

    private func installKeyMonitor(for panel: NSPanel) {
        removeKeyMonitor()
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self, weak panel] event in
            guard let self, let panel, event.window === panel else { return event }
            // A multiline editor owns its normal editing keys. The search box
            // uses a field editor, so its existing list shortcuts stay intact.
            // The read-only preview is a text view too, but the list keeps
            // the keys over it: only ⌘C and ⌘A, which the list declines below
            // when nothing is batch-selected, reach it.
            if let textView = panel.firstResponder as? NSTextView,
               !textView.isFieldEditor, textView.isEditable {
                return event
            }
            let modifiers = event.modifierFlags.intersection([.command, .option, .shift, .control])
            if event.keyCode == UInt16(kVK_Escape) {
                switch ClipboardHistoryEscape.action(batchCount: self.quickBatchCount) {
                case .clearBatchSelection: self.clearQuickBatchSelection()
                case .hideWindow: self.hideHistoryWindow()
                }
                return nil
            }
            // Finder-style Quick Look without stealing ordinary spaces typed
            // into search: the list claims Space only after arrow navigation.
            if event.keyCode == UInt16(kVK_Space),
               ClipboardHistoryPreview.handlesSpace(selectionIsVisible: self.quickSelectionIsVisible,
                                                     hasModifiers: !modifiers.isEmpty) {
                self.toggleQuickPreview()
                return nil
            }
            if event.keyCode == UInt16(kVK_Return) || event.keyCode == UInt16(kVK_ANSI_KeypadEnter) {
                if modifiers == [.command] {
                    self.toggleSelectedQuickEntryBatchSelection()
                    return nil
                }
                if modifiers == [.shift] {
                    self.copySelectedQuickEntryOnly()
                    return nil
                }
                if modifiers.isEmpty {
                    self.copySelectedQuickEntry()
                    return nil
                }
                return event
            }
            // Matched by typed character, not physical key code, so AZERTY,
            // Dvorak and friends keep their real ⌘C/⌘A (and nothing else is
            // mistaken for them). The list only claims them over the search
            // field per the support predicates.
            let key = event.charactersIgnoringModifiers?.lowercased()
            if modifiers == [.command], key == "c",
               ClipboardHistoryBatch.listOwnsCopyShortcut(batchCount: self.quickBatchCount) {
                self.copySelectedQuickEntryOnly()
                return nil
            }
            if modifiers == [.command], key == "a",
               ClipboardHistoryBatch.listOwnsSelectAllShortcut(
                   batchCount: self.quickBatchCount,
                   queryIsEmpty: self.quickQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) {
                self.selectAllQuickEntries()
                return nil
            }
            if modifiers == [.option], event.keyCode == UInt16(kVK_ANSI_P) {
                self.togglePinSelectedQuickEntry()
                return nil
            }
            if modifiers == [.option],
               event.keyCode == UInt16(kVK_Delete) || event.keyCode == UInt16(kVK_ForwardDelete) {
                self.removeSelectedQuickEntry()
                return nil
            }
            if event.keyCode == UInt16(kVK_DownArrow) {
                self.moveQuickSelection(1)
                return nil
            }
            if event.keyCode == UInt16(kVK_UpArrow) {
                self.moveQuickSelection(-1)
                return nil
            }
            if modifiers == [.command],
               let index = Self.digitIndex(for: event.keyCode) {
                self.copyQuickEntry(at: index)
                return nil
            }
            return event
        }
    }

    private func installDismissMonitors(for panel: NSPanel) {
        removeDismissMonitors()
        let mouseEvents: NSEvent.EventTypeMask = [.leftMouseDown, .rightMouseDown, .otherMouseDown]
        localClickMonitor = NSEvent.addLocalMonitorForEvents(matching: mouseEvents) { [weak self, weak panel] event in
            guard let self, let panel, panel.isVisible else { return event }
            if event.window !== panel, !Self.mouseIsInside(panel) {
                self.hideHistoryWindow()
            }
            return event
        }
        outsideClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: mouseEvents) { [weak self, weak panel] event in
            guard let self, let panel, panel.isVisible else { return }
            if event.windowNumber != panel.windowNumber, !Self.mouseIsInside(panel) {
                self.hideHistoryWindow()
            }
        }
        activationObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let self,
                  let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                  app.bundleIdentifier != Bundle.main.bundleIdentifier
            else { return }
            self.hideHistoryWindow()
        }
    }

    private static func mouseIsInside(_ panel: NSPanel) -> Bool {
        panel.frame.insetBy(dx: -2, dy: -2).contains(NSEvent.mouseLocation)
    }

    private func removeDismissMonitors() {
        if let localClickMonitor {
            NSEvent.removeMonitor(localClickMonitor)
            self.localClickMonitor = nil
        }
        if let outsideClickMonitor {
            NSEvent.removeMonitor(outsideClickMonitor)
            self.outsideClickMonitor = nil
        }
        if let activationObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(activationObserver)
            self.activationObserver = nil
        }
    }

    private func removeKeyMonitor() {
        if let keyMonitor {
            NSEvent.removeMonitor(keyMonitor)
            self.keyMonitor = nil
        }
    }

    private func resetQuickSelection() {
        quickSelectionIndex = ClipboardHistorySelection.initialIndex(totalCount: filteredQuickEntries.count)
        quickSelectionIsVisible = false
    }

    private var quickBatchEntries: [ClipboardHistoryEntry] {
        let allIDs = entries.map(\.id)
        let indexes = ClipboardHistoryBatch.orderedSelectedIndexes(allIDs: allIDs,
                                                                  selectedIDs: quickBatchEntryIDs)
        return indexes.map { entries[$0] }
    }

    private func quickEntriesForPrimaryAction() -> [ClipboardHistoryEntry] {
        let batch = quickBatchEntries
        if !batch.isEmpty { return batch }
        guard let entry = selectedQuickEntry else { return [] }
        return [entry]
    }

    private func pruneQuickBatchSelection() {
        let validIDs = Set(entries.map(\.id))
        quickBatchEntryIDs = Set(quickBatchEntryIDs.filter { validIDs.contains($0) })
    }

    private static func digitIndex(for keyCode: UInt16) -> Int? {
        switch Int(keyCode) {
        case kVK_ANSI_1: return 0
        case kVK_ANSI_2: return 1
        case kVK_ANSI_3: return 2
        case kVK_ANSI_4: return 3
        case kVK_ANSI_5: return 4
        case kVK_ANSI_6: return 5
        case kVK_ANSI_7: return 6
        case kVK_ANSI_8: return 7
        case kVK_ANSI_9: return 8
        default: return nil
        }
    }

    private func clampedQuickSelectionIndex(for count: Int) -> Int {
        min(max(quickSelectionIndex, 0), max(count - 1, 0))
    }
}

/// File-backed storage for copied images: PNGs live in Application Support
/// (UserDefaults would balloon with base64), named by UUID and swept against
/// the live entry list after every save.
enum ClipboardImageStore {
    /// Explicit limits: NSCache only sheds under system memory pressure, so
    /// without them a history full of screenshots quietly holds every decoded
    /// thumbnail at once.
    private static let thumbnails: NSCache<NSString, NSImage> = {
        let cache = NSCache<NSString, NSImage>()
        cache.countLimit = 120
        cache.totalCostLimit = 48 * 1024 * 1024
        return cache
    }()

    static var directory: URL? {
        PrivateFileStore.containerURL?
            .appendingPathComponent("ClipboardImages", isDirectory: true)
    }

    static func store(_ data: Data) -> String? {
        guard let directory else { return nil }
        PrivateFileStore.createDirectory(at: directory)
        let name = UUID().uuidString + ".png"
        guard PrivateFileStore.write(data, to: directory.appendingPathComponent(name)) else {
            return nil
        }
        return name
    }

    static func imageData(named name: String) -> Data? {
        guard let directory else { return nil }
        return try? Data(contentsOf: directory.appendingPathComponent(name))
    }

    /// Downsampled preview for list rows, cached; loading full PNGs per row
    /// would drag the quick window.
    static func thumbnail(named name: String) -> NSImage? {
        if let cached = thumbnails.object(forKey: name as NSString) {
            return cached
        }
        guard let directory else { return nil }
        let url = directory.appendingPathComponent(name)
        let options = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: 480,
        ] as CFDictionary
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options)
        else { return nil }
        let image = NSImage(cgImage: cgImage, size: .zero)
        thumbnails.setObject(image, forKey: name as NSString,
                             cost: cgImage.bytesPerRow * cgImage.height)
        return image
    }

    /// The Finder icon for a path, cached: the workspace lookup is a round
    /// trip, and a list row asks for it every time it is drawn.
    static func fileIcon(atPath path: String) -> NSImage {
        if let cached = fileIcons.object(forKey: path as NSString) { return cached }
        let icon = NSWorkspace.shared.icon(forFile: path)
        fileIcons.setObject(icon, forKey: path as NSString)
        return icon
    }

    private static let fileIcons = NSCache<NSString, NSImage>()

    static func isImageFile(atPath path: String) -> Bool {
        ClipboardHistoryImageSupport.isImageFilePath(path)
    }

    /// Downsampled preview for a copied image file on disk, cached.
    static func fileThumbnail(atPath path: String, maxPixelSize: CGFloat = 480) -> NSImage? {
        let key = "file:\(path):\(Int(maxPixelSize))" as NSString
        if let cached = thumbnails.object(forKey: key) {
            return cached
        }
        guard isImageFile(atPath: path) else { return nil }
        let url = URL(fileURLWithPath: path)
        let options = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
        ] as CFDictionary
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options)
        else { return nil }
        let image = NSImage(cgImage: cgImage, size: .zero)
        thumbnails.setObject(image, forKey: key,
                             cost: cgImage.bytesPerRow * cgImage.height)
        return image
    }

    static func imageDimensions(atPath path: String) -> (width: Int, height: Int)? {
        guard isImageFile(atPath: path) else { return nil }
        let url = URL(fileURLWithPath: path)
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        else { return nil }
        guard let rawWidth = (properties[kCGImagePropertyPixelWidth] as? NSNumber)?.intValue,
              let rawHeight = (properties[kCGImagePropertyPixelHeight] as? NSNumber)?.intValue,
              rawWidth > 0, rawHeight > 0
        else { return nil }
        let orientation = (properties[kCGImagePropertyOrientation] as? NSNumber)?.uint32Value ?? 1
        if (5...8).contains(orientation) {
            return (rawHeight, rawWidth)
        }
        return (rawWidth, rawHeight)
    }

    static func imageDimensionsLabel(atPath path: String) -> String? {
        guard let dim = imageDimensions(atPath: path) else { return nil }
        return "\(dim.width)×\(dim.height)"
    }

    static func fileSizeString(atPath path: String) -> String? {
        guard let values = try? URL(fileURLWithPath: path).resourceValues(forKeys: [.fileSizeKey]),
              let bytes = values.fileSize, bytes >= 0 else { return nil }
        return ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
    }

    static func cleanup(keeping names: Set<String>) {
        guard let directory,
              let files = try? FileManager.default.contentsOfDirectory(at: directory,
                                                                       includingPropertiesForKeys: nil)
        else { return }
        for file in files where !names.contains(file.lastPathComponent) {
            try? FileManager.default.removeItem(at: file)
            thumbnails.removeObject(forKey: file.lastPathComponent as NSString)
        }
    }
}
