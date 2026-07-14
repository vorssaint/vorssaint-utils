// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import ApplicationServices
import Combine
import CoreGraphics
import SwiftUI

/// Cut and paste for files in Finder: ⌘X marks the current selection, ⌘V moves
/// it into the folder you're viewing. A global event tap claims those two
/// shortcuts only while Finder is frontmost and no text field is being edited,
/// so renaming and text editing keep working untouched.
///
/// The decision to swallow a keystroke is made synchronously (in-memory marks +
/// the pasteboard change count + a fast Accessibility role check); the slow
/// parts (reading the Finder selection, moving files) run off the tap thread.
/// Requires Accessibility, and Automation consent for Finder on first use.
final class FinderCutPaste: ObservableObject {
    static let shared = FinderCutPaste()

    struct MarkedItem: Identifiable, Equatable {
        let id = UUID()
        let url: URL
        let icon: NSImage
        var name: String { url.lastPathComponent }

        // NSImage isn't Equatable; identity + path is enough to diff the list.
        static func == (lhs: MarkedItem, rhs: MarkedItem) -> Bool {
            lhs.id == rhs.id && lhs.url == rhs.url
        }
    }

    struct MoveResult: Equatable {
        let moved: Int
        let failed: Int
    }

    /// Live state of a move that left its volume (a real copy, not a rename),
    /// so the HUD can show a progress bar for large transfers (issue #168).
    /// `fraction` is nil when the batch's byte total is unknown (directories
    /// in the mix), which the HUD renders as an indeterminate bar.
    struct MoveProgress: Equatable {
        let completed: Int
        let total: Int
        let currentName: String
        let fraction: Double?
    }

    /// Files currently held for a move; drives the feedback HUD.
    @Published private(set) var marked: [MarkedItem] = []
    /// Set briefly after a paste so the HUD can confirm the move.
    @Published private(set) var lastResult: MoveResult?
    /// Set only while a cross-volume move is running; nil for instant moves.
    @Published private(set) var moveProgress: MoveProgress?

    /// Pasteboard change count captured when the cut was made. A ⌘V only turns
    /// into a move while this still matches — if anything else wrote to the
    /// pasteboard since, ⌘V is left as a normal paste.
    private var markedChangeCount = 0

    private var tap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var panel: NSPanel?
    private var resultDismiss: DispatchWorkItem?
    private var operationGeneration = 0
    private var moveInProgress = false

    private static let finderBundleID = "com.apple.finder"

    // ANSI virtual key codes.
    private enum Key {
        static let x: Int64 = 7
        static let c: Int64 = 8
        static let v: Int64 = 9
    }

    private init() {}

    var isRunning: Bool { tap != nil }

    /// Applies the persisted preference; safe to call repeatedly.
    func syncWithPreferences() {
        let enabled = AppFeature.finderCutPaste.isAvailable
            && UserDefaults.standard.bool(forKey: DefaultsKey.finderCutPasteEnabled)
        if enabled, Permissions.shared.accessibility {
            installTap()
        } else {
            removeTap()
            clearMarks()
        }
    }

    /// Force-stops the tap regardless of the preference. Used before the app
    /// resets its own permissions, so a revoked Accessibility grant can never
    /// leave a live tap behind.
    func suspend() {
        removeTap()
        clearMarks()
    }

    // MARK: - Event tap

    private func installTap() {
        guard tap == nil else { return }
        let mask = CGEventMask(1 << CGEventType.keyDown.rawValue)
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: { _, type, event, userInfo in
                guard let userInfo else { return Unmanaged.passUnretained(event) }
                let service = Unmanaged<FinderCutPaste>.fromOpaque(userInfo).takeUnretainedValue()
                return service.handle(type: type, event: event)
            },
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else { return }

        self.tap = tap
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        runLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
    }

    private func removeTap() {
        if let tap { CGEvent.tapEnable(tap: tap, enable: false) }
        if let runLoopSource { CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes) }
        tap = nil
        runLoopSource = nil
    }

    /// Runs on the main thread (the tap source lives on the main run loop), so
    /// reading `marked` and the pasteboard here is race-free.
    private func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return Unmanaged.passUnretained(event)
        }
        // Accessibility gone (e.g. reset): the AX focus check below would hang
        // inside the tap and freeze the keyboard, so pass the keystroke through.
        // Cached here to keep a live TCC round-trip off the per-keystroke path;
        // the live check sits right before the AX focus lookup, where it runs
        // only for an actual ⌘X/C/V in Finder.
        guard Permissions.shared.accessibility else { return Unmanaged.passUnretained(event) }
        guard type == .keyDown else { return Unmanaged.passUnretained(event) }

        let flags = event.flags
        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)

        // Only plain ⌘ + X/C/V, with Finder frontmost and no text being edited.
        guard flags.contains(.maskCommand),
              !flags.contains(.maskControl), !flags.contains(.maskAlternate),
              keyCode == Key.x || keyCode == Key.c || keyCode == Key.v,
              NSWorkspace.shared.frontmostApplication?.bundleIdentifier == Self.finderBundleID,
              AXIsProcessTrusted(),
              !isEditingText()
        else { return Unmanaged.passUnretained(event) }

        switch keyCode {
        case Key.x:
            // Finder has no native cut for files, so swallowing ⌘X is safe.
            cutAsync()
            return nil
        case Key.c:
            // Copying something else supersedes a pending cut; let Finder copy.
            if !marked.isEmpty { clearMarks() }
            return Unmanaged.passUnretained(event)
        case Key.v:
            guard !marked.isEmpty else {
                return Unmanaged.passUnretained(event) // nothing of ours to move → normal paste
            }
            guard NSPasteboard.general.changeCount == markedChangeCount else {
                // Something else wrote to the pasteboard since the cut — the
                // cut is dead, so drop the marks (and the HUD) and let the
                // normal paste happen.
                clearMarks()
                return Unmanaged.passUnretained(event)
            }
            guard !moveInProgress else {
                return nil
            }
            pasteAsync()
            return nil
        default:
            return Unmanaged.passUnretained(event)
        }
    }

    /// True when the keyboard focus is in an editable text control, so cut/copy/
    /// paste shortcuts must be left to the system (e.g. renaming a file).
    private func isEditingText() -> Bool {
        let system = AXUIElementCreateSystemWide()
        var focused: CFTypeRef?
        guard AXUIElementCopyAttributeValue(system, "AXFocusedUIElement" as CFString, &focused) == .success,
              let focused,
              // Type-check before casting: this runs inside the event tap, so
              // an unexpected CF type must degrade gracefully, never crash.
              CFGetTypeID(focused) == AXUIElementGetTypeID() else { return false }
        let element = focused as! AXUIElement
        var roleRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, "AXRole" as CFString, &roleRef) == .success,
              let role = roleRef as? String else { return false }
        // Stable public AX role strings; literals dodge CFString/String import quirks.
        return ["AXTextField", "AXTextArea", "AXComboBox", "AXSecureTextField"].contains(role)
    }

    // MARK: - Cut

    private func cutAsync() {
        operationGeneration += 1
        let generation = operationGeneration
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let urls = FinderBridge.selectionURLs()
            DispatchQueue.main.async {
                guard let self, generation == self.operationGeneration else { return }
                self.applyCut(urls)
            }
        }
    }

    private func applyCut(_ urls: [URL]) {
        guard !urls.isEmpty else { clearMarks(); return }
        moveInProgress = false
        moveProgress = nil
        marked = urls.map { MarkedItem(url: $0, icon: NSWorkspace.shared.icon(forFile: $0.path)) }
        // Also place the files on the pasteboard so a normal ⌘V elsewhere still
        // works as a copy, and so the move guard has a change count to anchor to.
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.writeObjects(urls as [NSURL])
        markedChangeCount = pb.changeCount
        lastResult = nil
        refreshPanel()
    }

    // MARK: - Paste (move)

    private func pasteAsync() {
        guard !moveInProgress else { return }
        moveInProgress = true
        operationGeneration += 1
        let generation = operationGeneration
        let urls = marked.map(\.url)
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let destPath = FinderBridge.insertionLocationPath() else {
                DispatchQueue.main.async {
                    self?.finishPaste(generation: generation, moved: 0, failed: urls.count)
                }
                return
            }
            let dir = URL(fileURLWithPath: destPath, isDirectory: true)
            let fm = FileManager.default
            let plan = Self.progressPlan(urls: urls, dir: dir)
            var moved = 0, failed = 0
            var finishedBytes: Int64 = 0
            for (index, src) in urls.enumerated() {
                if plan.showsProgress {
                    self?.publishProgress(generation: generation,
                                          completed: index, total: urls.count,
                                          name: src.lastPathComponent,
                                          fraction: CutPasteProgressSupport.fraction(
                                              finishedBytes: finishedBytes,
                                              currentBytes: 0,
                                              totalBytes: plan.totalBytes))
                }
                var poller: DispatchSourceTimer?
                let success = Self.move(src, into: dir, fm: fm) { dest in
                    guard plan.showsProgress, plan.totalBytes > 0 else { return }
                    poller = self?.makeBytePoller(destination: dest,
                                                  generation: generation,
                                                  completed: index, total: urls.count,
                                                  name: src.lastPathComponent,
                                                  finishedBytes: finishedBytes,
                                                  totalBytes: plan.totalBytes)
                }
                poller?.cancel()
                finishedBytes += plan.sizes[index] ?? 0
                if success { moved += 1 } else { failed += 1 }
            }
            DispatchQueue.main.async {
                self?.finishPaste(generation: generation, moved: moved, failed: failed)
            }
        }
    }

    /// Sizes up a batch before moving it. Progress only shows when at least
    /// one item leaves its volume — everything else is a rename and finishes
    /// before a bar could even appear. Byte totals only count regular files;
    /// a directory in the batch makes the total unknowable cheaply, so the
    /// bar falls back to indeterminate while the item counter keeps moving.
    private static func progressPlan(urls: [URL],
                                     dir: URL) -> (showsProgress: Bool, totalBytes: Int64, sizes: [Int64?]) {
        let destVolume = volumeIdentity(of: dir)
        var anyCross = false
        var allRegular = true
        var sizes: [Int64?] = []
        var total: Int64 = 0
        for src in urls {
            if CutPasteProgressSupport.isCrossVolume(source: volumeIdentity(of: src),
                                                     destination: destVolume) {
                anyCross = true
            }
            let values = try? src.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
            if values?.isRegularFile == true, let size = values?.fileSize {
                sizes.append(Int64(size))
                total += Int64(size)
            } else {
                sizes.append(nil)
                allRegular = false
            }
        }
        return (anyCross, allRegular ? total : 0, sizes)
    }

    private static func volumeIdentity(of url: URL) -> NSObject? {
        (try? url.resourceValues(forKeys: [.volumeIdentifierKey]))?.volumeIdentifier as? NSObject
    }

    /// Samples the growing destination file while `FileManager` copies it, so
    /// the bar advances within a single large file. Reading the size is one
    /// stat call and can never disturb the move itself.
    private func makeBytePoller(destination: URL,
                                generation: Int,
                                completed: Int, total: Int,
                                name: String,
                                finishedBytes: Int64,
                                totalBytes: Int64) -> DispatchSourceTimer {
        let timer = DispatchSource.makeTimerSource(queue: .global(qos: .utility))
        timer.schedule(deadline: .now() + CutPasteProgressSupport.pollInterval,
                       repeating: CutPasteProgressSupport.pollInterval)
        timer.setEventHandler { [weak self] in
            let attributes = try? FileManager.default.attributesOfItem(atPath: destination.path)
            let current = (attributes?[.size] as? NSNumber)?.int64Value ?? 0
            self?.publishProgress(generation: generation,
                                  completed: completed, total: total,
                                  name: name,
                                  fraction: CutPasteProgressSupport.fraction(
                                      finishedBytes: finishedBytes,
                                      currentBytes: current,
                                      totalBytes: totalBytes))
        }
        timer.resume()
        return timer
    }

    private func publishProgress(generation: Int,
                                 completed: Int, total: Int,
                                 name: String,
                                 fraction: Double?) {
        DispatchQueue.main.async { [weak self] in
            guard let self, generation == self.operationGeneration, self.moveInProgress else { return }
            self.moveProgress = MoveProgress(completed: completed, total: total,
                                             currentName: name, fraction: fraction)
            self.refreshPanel()
        }
    }

    private func finishPaste(generation: Int, moved: Int, failed: Int) {
        guard generation == operationGeneration else { return }
        // Invalidate the generation so a progress publish still in flight from
        // a just-cancelled poller can't revive the moving state after this.
        operationGeneration += 1
        moveInProgress = false
        moveProgress = nil
        marked = []
        markedChangeCount = 0
        lastResult = MoveResult(moved: moved, failed: failed)
        refreshPanel()
        scheduleResultDismiss()
    }

    /// `willCopy` fires with the final destination just before the actual
    /// move, and only when one happens (not for no-op moves into the same
    /// folder), so the caller can watch the destination grow.
    private static func move(_ src: URL, into dir: URL, fm: FileManager,
                             willCopy: (URL) -> Void = { _ in }) -> Bool {
        // A no-op move (already in the destination) counts as success.
        if src.deletingLastPathComponent().standardizedFileURL.path == dir.standardizedFileURL.path {
            return true
        }
        guard fm.fileExists(atPath: src.path) else { return false }
        let dest = uniqueDestination(for: src.lastPathComponent, in: dir, fm: fm)
        willCopy(dest)
        do {
            try fm.moveItem(at: src, to: dest)
            return true
        } catch {
            return false
        }
    }

    /// Appends " 2", " 3"… before the extension when a name already exists,
    /// matching how Finder de-duplicates.
    private static func uniqueDestination(for name: String, in dir: URL, fm: FileManager) -> URL {
        var candidate = dir.appendingPathComponent(name)
        guard fm.fileExists(atPath: candidate.path) else { return candidate }
        let base = (name as NSString).deletingPathExtension
        let ext = (name as NSString).pathExtension
        var n = 2
        repeat {
            let next = ext.isEmpty ? "\(base) \(n)" : "\(base) \(n).\(ext)"
            candidate = dir.appendingPathComponent(next)
            n += 1
        } while fm.fileExists(atPath: candidate.path)
        return candidate
    }

    // MARK: - Marks / panel

    func clearMarks() {
        guard !marked.isEmpty || lastResult != nil else { return }
        resetCutState(clearOwnedPasteboard: false)
    }

    func cancelPendingCut() {
        guard !marked.isEmpty || lastResult != nil else { return }
        resetCutState(clearOwnedPasteboard: true)
    }

    private func resetCutState(clearOwnedPasteboard: Bool) {
        resultDismiss?.cancel()
        resultDismiss = nil
        let shouldClearPasteboard = clearOwnedPasteboard
            && !marked.isEmpty
            && NSPasteboard.general.changeCount == markedChangeCount
        operationGeneration += 1
        moveInProgress = false
        moveProgress = nil
        marked = []
        markedChangeCount = 0
        lastResult = nil
        if shouldClearPasteboard {
            NSPasteboard.general.clearContents()
        }
        refreshPanel()
    }

    private func scheduleResultDismiss() {
        resultDismiss?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.lastResult = nil
            self?.refreshPanel()
        }
        resultDismiss = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.8, execute: work)
    }

    private func refreshPanel() {
        if marked.isEmpty, lastResult == nil {
            panel?.orderOut(nil)
        } else {
            showPanel()
        }
    }

    private func showPanel() {
        let panel = ensurePanel()
        let view = panel.contentViewController!.view
        view.layoutSubtreeIfNeeded()
        let size = view.fittingSize
        let screen = NSScreen.withMouse.visibleFrame
        let frame = NSRect(x: screen.midX - size.width / 2,
                           y: screen.maxY - size.height - 14,
                           width: size.width, height: size.height)
        panel.setFrame(frame, display: true)
        panel.orderFrontRegardless()
    }

    private func ensurePanel() -> NSPanel {
        if let panel { return panel }
        let panel = NSPanel(contentRect: .zero,
                            styleMask: [.borderless, .nonactivatingPanel],
                            backing: .buffered, defer: false)
        panel.level = .statusBar
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        let host = NSHostingController(rootView: CutFeedbackView().environmentObject(self))
        host.sizingOptions = .preferredContentSize
        panel.contentViewController = host
        self.panel = panel
        return panel
    }
}

/// Reads the current Finder selection and the folder a paste would land in,
/// sending the Apple Events IN-PROCESS (see `AppleScriptRunner`) so the Finder
/// Automation consent is attributed to this app — stable across updates and
/// re-requested if it was lost — which is why the cut HUD had stopped appearing
/// for some users. Same Finder Automation permission as before; nothing new.
/// Callers run this off the main thread so a slow Finder never blocks the UI or
/// the event taps.
private enum FinderBridge {
    private static let finderBundleID = "com.apple.finder"

    static func selectionURLs() -> [URL] {
        guard AppleScriptRunner.consentToAutomate(bundleID: finderBundleID) else { return [] }
        let script = """
        tell application "Finder"
            set out to ""
            repeat with f in (get selection)
                set out to out & (POSIX path of (f as alias)) & linefeed
            end repeat
            return out
        end tell
        """
        let result = AppleScriptRunner.run(script)
        guard result.ok else { return [] }
        return result.output.split(whereSeparator: \.isNewline)
            .map { URL(fileURLWithPath: String($0)) }
    }

    static func insertionLocationPath() -> String? {
        guard AppleScriptRunner.consentToAutomate(bundleID: finderBundleID) else { return nil }
        let script = """
        tell application "Finder"
            return POSIX path of (insertion location as alias)
        end tell
        """
        let result = AppleScriptRunner.run(script)
        guard result.ok else { return nil }
        let path = result.output.trimmingCharacters(in: .whitespacesAndNewlines)
        return path.isEmpty ? nil : path
    }
}
