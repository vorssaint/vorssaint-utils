// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import Combine

/// Explicit, text-only capture. No timer or pasteboard reads exist until start.
final class ScratchpadClipboardCollector {
    private let pasteboard: () -> NSPasteboard
    private let access: GeneralPasteboardAccess
    private let sources: ClipboardIgnoredApps
    private let defaults: UserDefaults
    private var exclusions: AnyCancellable?
    private var timer: Timer?
    private var capture = ClipboardHistoryCaptureState()
    private var lastChangeCount = 0
    private var lastText: String?
    private var receive: ((String) -> Bool)?
    private var ownUIActive: () -> Bool = { false }

    init(pasteboard: @escaping () -> NSPasteboard = { .general },
         access: GeneralPasteboardAccess = .shared,
         defaults: UserDefaults = .standard) {
        self.pasteboard = pasteboard
        self.access = access
        self.defaults = defaults
        self.sources = ClipboardIgnoredApps(defaults: defaults)
    }

    func start(ownUIActive: @escaping () -> Bool, receive: @escaping (String) -> Bool) {
        stop()
        self.ownUIActive = ownUIActive
        self.receive = receive
        lastText = nil
        capture.restart()
        sources.reload()
        sources.setHistoryRunning(true)
        exclusions = ClipboardIgnoredApps.shared.$apps.dropFirst().sink { [weak self] _ in self?.sources.reload() }
        poll()
        let timer = Timer(timeInterval: 0.3, repeats: true) { [weak self] _ in self?.poll() }
        self.timer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        receive = nil
        ownUIActive = { false }
        capture.invalidate()
        exclusions = nil
        sources.setHistoryRunning(false)
    }

    deinit { stop() }

    func poll() {
        guard receive != nil, let generation = capture.begin() else { return }
        let baseline = capture.needsBaseline
        let since = lastChangeCount
        let ownUI = ownUIActive()
        let pasteboard = self.pasteboard
        access.async(timeout: 1, { expired -> Snapshot? in
            let board = pasteboard()
            let count = board.changeCount
            guard !expired() else { return nil }
            // Starting establishes a count only: pre-existing content is not collected.
            if baseline { return Snapshot(count: count) }
            if count == since { return Snapshot(count: count) }
            let types = (board.types ?? []).map(\.rawValue)
            let blocked = ClipboardHistorySensitiveText.isConcealed(types)
                || ClipboardHistorySensitiveText.isTransient(types)
                || types.contains(NSPasteboard.PasteboardType.fileURL.rawValue)
                || types.contains(NSPasteboard.PasteboardType.png.rawValue)
                || types.contains(NSPasteboard.PasteboardType.tiff.rawValue)
            let text = blocked ? nil : board.string(forType: .string)
            let source = board.string(forType: .source)
            let remote = types.contains(NSPasteboard.PasteboardType.remoteClipboard.rawValue)
            // Promised data can change while being read; never combine two copies.
            guard !expired(), board.changeCount == count else { return nil }
            return Snapshot(count: count, text: text, source: source, remote: remote)
        }, then: { [weak self] result in
            guard let self, self.receive != nil, self.capture.accepts(generation) else { return }
            guard let result else { self.capture.expire(generation); return }
            let source = self.sources.sourceSinceLastCheck(declared: result.source, remote: result.remote,
                historyPanelIsKey: ownUI || self.ownUIActive(), historyPanelClosing: false)
            if baseline {
                self.lastChangeCount = result.count
                self.capture.didBaseline()
                return
            }
            guard result.count != self.lastChangeCount else { return }
            let ownWrite = Bundle.main.bundleIdentifier.map { result.source == $0 } ?? false
            guard !source.excluded, !source.fromHistoryPanel, !ownWrite,
                  let text = result.text, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  text.count <= ClipboardHistoryEditing.maxCharacters,
                  !(self.defaults.bool(forKey: DefaultsKey.clipboardHistoryFilterSensitiveText)
                    && ClipboardHistorySensitiveText.looksSensitive(text)), text != self.lastText else {
                self.lastChangeCount = result.count
                return
            }
            // A composing editor can decline delivery. Retry without consuming the copy.
            if self.receive?(text) == true {
                self.lastText = text
                self.lastChangeCount = result.count
            }
        }, didFinish: { [weak self] _ in self?.capture.finish() })
    }

    private struct Snapshot {
        let count: Int
        var text: String? = nil
        var source: String? = nil
        var remote = false
    }
}
