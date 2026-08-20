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

    // An active keyboard tap makes the window server wait for its callback
    // before delivering the key. Keep that callback on a user-interactive
    // run loop so unrelated typing never queues behind the app's main thread.
    private let tapLifecycleLock = NSLock()
    private var tap: CFMachPort?
    private var tapRunLoop: CFRunLoop?
    private var tapThread: Thread?
    private var shouldStopTapThread = false
    private var pendingTapRestart = false
    private var panel: NSPanel?
    private var resultDismiss: DispatchWorkItem?
    private var operationGeneration = 0
    private var moveInProgress = false
    private var cutPasteEnabled = false
    private var pasteImageAsFileEnabled = false
    private var imagePasteInProgress = false

    private static let finderBundleID = "com.apple.finder"
    private static let syntheticPasteMarker: Int64 = 0x564F5249
    private static let maxRawImageBytes = 64 * 1024 * 1024

    // ANSI virtual key codes.
    private enum Key {
        static let x: Int64 = 7
        static let c: Int64 = 8
        static let v: Int64 = 9
    }

    private init() {}

    var isRunning: Bool { tapLifecycleLock.withLock { tap != nil } }

    /// Applies the persisted preference; safe to call repeatedly.
    func syncWithPreferences() {
        let available = AppFeature.finderCutPaste.isAvailable
        cutPasteEnabled = available
            && UserDefaults.standard.bool(forKey: DefaultsKey.finderCutPasteEnabled)
        pasteImageAsFileEnabled = available
            && UserDefaults.standard.bool(forKey: DefaultsKey.finderPasteImageAsFile)
        if (cutPasteEnabled || pasteImageAsFileEnabled), Permissions.shared.accessibility {
            installTap()
        } else {
            removeTap()
        }
        if !cutPasteEnabled {
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
        let thread = tapLifecycleLock.withLock { () -> Thread? in
            if tapThread != nil {
                if shouldStopTapThread { pendingTapRestart = true }
                return nil
            }
            shouldStopTapThread = false
            pendingTapRestart = false
            let thread = Thread { [weak self] in self?.runEventTap() }
            thread.name = "Vorssaint File Shortcuts"
            thread.qualityOfService = .userInteractive
            tapThread = thread
            return thread
        }
        thread?.start()
    }

    private func removeTap() {
        let snapshot = tapLifecycleLock.withLock {
            () -> (runLoop: CFRunLoop?, tap: CFMachPort?, threadExists: Bool) in
            shouldStopTapThread = true
            pendingTapRestart = false
            return (tapRunLoop, tap, tapThread != nil)
        }
        if let tap = snapshot.tap { CGEvent.tapEnable(tap: tap, enable: false) }
        if let runLoop = snapshot.runLoop {
            CFRunLoopPerformBlock(runLoop, CFRunLoopMode.commonModes.rawValue) {
                CFRunLoopStop(runLoop)
            }
            CFRunLoopWakeUp(runLoop)
        } else if !snapshot.threadExists {
            tapLifecycleLock.withLock {
                shouldStopTapThread = false
                tapThread = nil
            }
        }
    }

    private func runEventTap() {
        autoreleasepool {
            let runLoop = CFRunLoopGetCurrent()
            tapLifecycleLock.withLock { tapRunLoop = runLoop }
            guard !tapLifecycleLock.withLock({ shouldStopTapThread }) else {
                if clearEventTapThread() { installTap() }
                return
            }

            let mask = CGEventMask(1 << CGEventType.keyDown.rawValue)
            guard let tap = CGEvent.tapCreate(
                tap: .cgSessionEventTap,
                place: .headInsertEventTap,
                options: .defaultTap,
                eventsOfInterest: mask,
                callback: { _, type, event, userInfo in
                    guard let userInfo else { return Unmanaged.passUnretained(event) }
                    let service = Unmanaged<FinderCutPaste>.fromOpaque(userInfo).takeUnretainedValue()
                    return service.route(type: type, event: event)
                },
                userInfo: Unmanaged.passUnretained(self).toOpaque()
            ) else {
                _ = clearEventTapThread()
                return
            }

            let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
            tapLifecycleLock.withLock { self.tap = tap }
            CFRunLoopAddSource(runLoop, source, .commonModes)
            CGEvent.tapEnable(tap: tap, enable: true)

            if tapLifecycleLock.withLock({ shouldStopTapThread }) {
                CGEvent.tapEnable(tap: tap, enable: false)
            } else {
                CFRunLoopRun()
            }

            CGEvent.tapEnable(tap: tap, enable: false)
            CFRunLoopRemoveSource(runLoop, source, .commonModes)
            CFMachPortInvalidate(tap)
            if clearEventTapThread() { installTap() }
        }
    }

    private func clearEventTapThread() -> Bool {
        tapLifecycleLock.withLock {
            let shouldRestart = pendingTapRestart
            tap = nil
            tapRunLoop = nil
            tapThread = nil
            shouldStopTapThread = false
            pendingTapRestart = false
            return shouldRestart
        }
    }

    /// Runs on the tap thread. Every key except plain Command-X/C/V returns
    /// after reading only the event itself; the rare candidate is handed to
    /// the main thread where the service's UI and pasteboard state live.
    private func route(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            let currentTap = tapLifecycleLock.withLock { shouldStopTapThread ? nil : tap }
            if let currentTap { CGEvent.tapEnable(tap: currentTap, enable: true) }
            return Unmanaged.passUnretained(event)
        }
        guard type == .keyDown,
              event.getIntegerValueField(.eventSourceUserData) != Self.syntheticPasteMarker
        else { return Unmanaged.passUnretained(event) }

        let flags = event.flags
        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
        guard flags.contains(.maskCommand),
              !flags.contains(.maskControl), !flags.contains(.maskAlternate),
              keyCode == Key.x || keyCode == Key.c || keyCode == Key.v
        else { return Unmanaged.passUnretained(event) }

        var verdict: Unmanaged<CGEvent>?
        DispatchQueue.main.sync {
            verdict = self.handle(event: event)
        }
        return verdict
    }

    /// Runs on the main thread, so reading `marked` and the pasteboard here is
    /// race-free.
    private func handle(event: CGEvent) -> Unmanaged<CGEvent>? {
        // Accessibility gone (e.g. reset): the AX focus check below would hang
        // inside the tap and freeze the keyboard, so pass the keystroke through.
        // Cached here to keep a live TCC round-trip off the per-keystroke path;
        // the live check sits right before the AX focus lookup, where it runs
        // only for an actual ⌘X/C/V in Finder.
        guard Permissions.shared.accessibility else { return Unmanaged.passUnretained(event) }

        let flags = event.flags
        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)

        guard NSWorkspace.shared.frontmostApplication?.bundleIdentifier == Self.finderBundleID,
              AXIsProcessTrusted(),
              !isEditingText()
        else { return Unmanaged.passUnretained(event) }

        switch keyCode {
        case Key.x:
            guard cutPasteEnabled else { return Unmanaged.passUnretained(event) }
            // Finder has no native cut for files, so swallowing ⌘X is safe.
            cutAsync()
            return nil
        case Key.c:
            // Copying something else supersedes a pending cut; let Finder copy.
            if cutPasteEnabled, !marked.isEmpty { clearMarks() }
            return Unmanaged.passUnretained(event)
        case Key.v:
            if cutPasteEnabled, !marked.isEmpty {
                if NSPasteboard.general.changeCount == markedChangeCount {
                    guard !moveInProgress else { return nil }
                    pasteAsync()
                    return nil
                }
                // Something else wrote to the pasteboard since the cut. Drop
                // the marks, then let the image path below inspect that new
                // content before falling back to Finder's normal paste.
                clearMarks()
            }
            guard pasteImageAsFileEnabled,
                  !flags.contains(.maskShift),
                  !imagePasteInProgress,
                  let targetPID = NSWorkspace.shared.frontmostApplication?.processIdentifier
            else {
                return Unmanaged.passUnretained(event)
            }
            pasteImageAsync(targetPID: targetPID,
                            expectedChangeCount: NSPasteboard.general.changeCount)
            return nil
        default:
            return Unmanaged.passUnretained(event)
        }
    }

    // MARK: - Paste image as file

    /// The event tap only queues the work. Pasteboard decoding, Finder IPC and
    /// disk writes stay off the main run loop; non-image content is handed
    /// back to Finder as the same standard paste shortcut.
    private func pasteImageAsync(targetPID: pid_t, expectedChangeCount: Int) {
        imagePasteInProgress = true
        GeneralPasteboardAccess.shared.async { [weak self] in
            let pasteboard = NSPasteboard.general
            guard pasteboard.changeCount == expectedChangeCount else {
                DispatchQueue.main.async {
                    self?.finishImagePaste(targetPID: targetPID, result: .notImage)
                }
                return
            }
            let identifiers = (pasteboard.types ?? []).map(\.rawValue)
            guard let identifier = FinderPasteImageSupport.preferredImageType(in: identifiers) else {
                DispatchQueue.main.async {
                    self?.finishImagePaste(targetPID: targetPID, result: .notImage)
                }
                return
            }
            guard let source = pasteboard.data(forType: NSPasteboard.PasteboardType(identifier)),
                  source.count <= Self.maxRawImageBytes,
                  let bitmap = NSBitmapImageRep(data: source),
                  let png = identifier == NSPasteboard.PasteboardType.png.rawValue
                    ? source
                    : bitmap.representation(using: .png, properties: [:]),
                  png.count <= Self.maxRawImageBytes
            else {
                DispatchQueue.main.async {
                    self?.finishImagePaste(targetPID: targetPID, result: .failed)
                }
                return
            }

            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                guard let path = FinderBridge.insertionLocationPath() else {
                    DispatchQueue.main.async {
                        self?.finishImagePaste(targetPID: targetPID, result: .failed)
                    }
                    return
                }
                let directory = URL(fileURLWithPath: path, isDirectory: true)
                let name = FinderPasteImageSupport.fileName(for: Date())
                let destination = Self.uniqueDestination(for: name, in: directory,
                                                         fm: FileManager.default)
                do {
                    try png.write(to: destination, options: .atomic)
                    DispatchQueue.main.async {
                        self?.finishImagePaste(targetPID: targetPID, result: .saved)
                    }
                } catch {
                    DispatchQueue.main.async {
                        self?.finishImagePaste(targetPID: targetPID, result: .failed)
                    }
                }
            }
        }
    }

    private enum ImagePasteResult {
        case notImage, saved, failed
    }

    private func finishImagePaste(targetPID: pid_t, result: ImagePasteResult) {
        imagePasteInProgress = false
        switch result {
        case .notImage:
            postNormalPaste(ifStillFrontmost: targetPID)
        case .saved:
            break
        case .failed:
            NSSound.beep()
        }
    }

    private func postNormalPaste(ifStillFrontmost targetPID: pid_t) {
        guard NSWorkspace.shared.frontmostApplication?.processIdentifier == targetPID else { return }
        let source = CGEventSource(stateID: .hidSystemState)
        source?.userData = Self.syntheticPasteMarker
        guard let keyDown = CGEvent(keyboardEventSource: source,
                                    virtualKey: CGKeyCode(Key.v), keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: source,
                                  virtualKey: CGKeyCode(Key.v), keyDown: false)
        else { return }
        keyDown.flags = .maskCommand
        keyUp.flags = .maskCommand
        keyDown.post(tap: .cghidEventTap)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.04) {
            keyUp.post(tap: .cghidEventTap)
        }
    }

    /// True when the keyboard focus is in an editable text control, so cut/copy/
    /// paste shortcuts must be left to the system (e.g. renaming a file).
    private func isEditingText() -> Bool {
        let system = AXUIElementCreateSystemWide()
        // The whole session's typing waits for this tap to answer, and this
        // question goes to whichever app is in front. A file browser reading a
        // share that went away is exactly the app that stops answering, so the
        // wait is kept short enough not to be felt.
        AXUIElementSetMessagingTimeout(system, 0.15)
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
        let screen = NSScreen.pointerVisibleFrame
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
enum FinderBridge {
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
