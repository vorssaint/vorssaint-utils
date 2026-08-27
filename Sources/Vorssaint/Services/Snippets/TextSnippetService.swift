// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import Carbon.HIToolbox
import CoreGraphics

/// Text snippets: typing a trigger replaces it with its expansion, with
/// {{date}}, {{time}}, {{datetime}} and {{clipboard}} filled in. The key tap,
/// the observers and the snippet cache only exist while the feature is on;
/// off means nothing lives. Requires Accessibility (the tap).
final class TextSnippetService {
    static let shared = TextSnippetService()

    /// Marks our own synthetic events so the tap never re-processes them.
    private static let syntheticMarker: Int64 = 0x564F5253 // "VORS"

    // The tap callback and its mutable text state live off the main thread so
    // demanding foreground apps cannot turn a main-thread stall into queued
    // keyboard input for the whole session.
    private let tapLifecycleLock = NSLock()
    private var tap: CFMachPort?
    private var tapRunLoop: CFRunLoop?
    private var tapThread: Thread?
    private var shouldStopTapThread = false
    private var pendingTapRestart = false
    private var activationObserver: NSObjectProtocol?
    private let inputLock = NSLock()
    private var buffer = ""
    private var libraryVisible = false
    private var commandBarVisible = false
    /// Split by expansion mode at load time; the tap callback only scans.
    private var immediateSnippets: [TextSnippet] = []
    private var delimiterSnippets: [TextSnippet] = []

    private init() {}

    var isRunning: Bool { tapLifecycleLock.withLock { tap != nil } }

    func syncWithPreferences() {
        let enabled = AppFeature.textSnippets.isAvailable
            && UserDefaults.standard.bool(forKey: DefaultsKey.textSnippetsEnabled)
        reloadSnippets()
        let hasWork = inputLock.withLock {
            !(immediateSnippets.isEmpty && delimiterSnippets.isEmpty)
        }
        if enabled, hasWork, Permissions.shared.accessibility {
            let libraryIsVisible = SnippetLibraryService.shared.isVisible
            let commandBarIsVisible = AppFeature.commandBar.isAvailable
                && CommandBarService.shared.isVisible
            inputLock.withLock {
                libraryVisible = libraryIsVisible
                commandBarVisible = commandBarIsVisible
            }
            start()
        } else {
            stop()
        }
    }

    func suspend() { stop() }

    func setLibraryVisible(_ visible: Bool) {
        inputLock.withLock {
            libraryVisible = visible
            if visible { buffer = "" }
        }
    }

    func setCommandBarVisible(_ visible: Bool) {
        inputLock.withLock {
            commandBarVisible = visible
            if visible { buffer = "" }
        }
    }

    /// Reloads the stored snippets; called by the settings page after edits.
    private func reloadSnippets() {
        let all = TextSnippetSupport.decode(
            UserDefaults.standard.data(forKey: DefaultsKey.textSnippets))
        inputLock.withLock {
            immediateSnippets = all.filter { $0.enabled && $0.expansion == .immediate }
            delimiterSnippets = all.filter { $0.enabled && $0.expansion == .afterDelimiter }
        }
    }

    private func start() {
        let thread = tapLifecycleLock.withLock { () -> Thread? in
            if tapThread != nil {
                if shouldStopTapThread { pendingTapRestart = true }
                return nil
            }
            shouldStopTapThread = false
            pendingTapRestart = false
            let thread = Thread { [weak self] in self?.runEventTap() }
            thread.name = "Vorssaint Text Expansion"
            thread.qualityOfService = .userInteractive
            tapThread = thread
            return thread
        }
        thread?.start()
    }

    private func stop() {
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
        if let activationObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(activationObserver)
            self.activationObserver = nil
        }
        resetBuffer()
    }

    private func runEventTap() {
        autoreleasepool {
            let runLoop = CFRunLoopGetCurrent()
            tapLifecycleLock.withLock { tapRunLoop = runLoop }
            guard !tapLifecycleLock.withLock({ shouldStopTapThread }) else {
                if clearEventTapThread() { startOnMain() }
                return
            }

            let mask: CGEventMask = (1 << CGEventType.keyDown.rawValue)
                | (1 << CGEventType.leftMouseDown.rawValue)
                | (1 << CGEventType.rightMouseDown.rawValue)
            guard let tap = CGEvent.tapCreate(
                tap: .cgSessionEventTap,
                place: .headInsertEventTap,
                options: .defaultTap,
                eventsOfInterest: mask,
                callback: { _, type, event, userInfo in
                    guard let userInfo else { return Unmanaged.passUnretained(event) }
                    let service = Unmanaged<TextSnippetService>.fromOpaque(userInfo)
                        .takeUnretainedValue()
                    return service.handle(type: type, event: event)
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
            DispatchQueue.main.async { [weak self] in self?.tapDidStart(tap) }

            if tapLifecycleLock.withLock({ shouldStopTapThread }) {
                CGEvent.tapEnable(tap: tap, enable: false)
            } else {
                CFRunLoopRun()
            }

            CGEvent.tapEnable(tap: tap, enable: false)
            CFRunLoopRemoveSource(runLoop, source, .commonModes)
            CFMachPortInvalidate(tap)
            if clearEventTapThread() { startOnMain() }
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

    private func startOnMain() {
        DispatchQueue.main.async { [weak self] in self?.start() }
    }

    private func tapDidStart(_ startedTap: CFMachPort) {
        let active = tapLifecycleLock.withLock {
            tap === startedTap && !shouldStopTapThread
        }
        guard active, activationObserver == nil else { return }
        // Switching apps invalidates whatever was half-typed there.
        activationObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.resetBuffer()
        }
    }

    private func resetBuffer() {
        inputLock.withLock { buffer = "" }
    }

    // MARK: - Tap

    private func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            let currentTap = tapLifecycleLock.withLock { shouldStopTapThread ? nil : tap }
            if let currentTap { CGEvent.tapEnable(tap: currentTap, enable: true) }
            return Unmanaged.passUnretained(event)
        }
        // Clicks move the caret somewhere unknown; the half-typed trigger is
        // no longer where the deletes would land.
        if type == .leftMouseDown || type == .rightMouseDown {
            resetBuffer()
            return Unmanaged.passUnretained(event)
        }
        guard type == .keyDown else { return Unmanaged.passUnretained(event) }
        // Never react to our own synthetic typing.
        guard event.getIntegerValueField(.eventSourceUserData) != Self.syntheticMarker else {
            return Unmanaged.passUnretained(event)
        }
        // Password fields: the system enables secure input; typing there must
        // stay exactly as typed, and the buffer must not remember any of it.
        guard !IsSecureEventInputEnabled() else {
            resetBuffer()
            return Unmanaged.passUnretained(event)
        }
        // Visibility is mirrored behind the same lock as the buffer, so this
        // callback never has to ask AppKit or wait for the main thread.
        guard !inputLock.withLock({ libraryVisible || commandBarVisible }) else {
            resetBuffer()
            return Unmanaged.passUnretained(event)
        }
        // Shortcuts are commands, not text.
        if !event.flags.intersection([.maskCommand, .maskControl]).isEmpty {
            resetBuffer()
            return Unmanaged.passUnretained(event)
        }

        let keyCode = Int(event.getIntegerValueField(.keyboardEventKeycode))
        switch keyCode {
        case kVK_Delete:
            inputLock.withLock {
                if !buffer.isEmpty { buffer.removeLast() }
            }
            return Unmanaged.passUnretained(event)
        case kVK_LeftArrow, kVK_RightArrow, kVK_UpArrow, kVK_DownArrow, kVK_Escape,
             kVK_Home, kVK_End, kVK_PageUp, kVK_PageDown, kVK_ForwardDelete:
            resetBuffer()
            return Unmanaged.passUnretained(event)
        default:
            break
        }

        var length = 0
        var characters = [UniChar](repeating: 0, count: 4)
        event.keyboardGetUnicodeString(maxStringLength: 4, actualStringLength: &length, unicodeString: &characters)
        guard length > 0 else { return Unmanaged.passUnretained(event) }
        let typed = String(utf16CodeUnits: characters, count: length)

        if let first = typed.first, TextSnippetSupport.delimiters.contains(first) {
            // A delimiter can complete an afterDelimiter trigger. The typed
            // delimiter is swallowed and re-posted after the replacement, so
            // it lands where the user expects: right after the expanded text.
            let matched = inputLock.withLock { () -> TextSnippet? in
                let match = TextSnippetSupport.match(buffer: buffer,
                                                     expansion: .afterDelimiter,
                                                     snippets: delimiterSnippets)
                buffer = ""
                return match
            }
            if let matched {
                expand(matched,
                       deleteCount: matched.trigger.count,
                       trailingKeyCode: CGKeyCode(keyCode),
                       trailingFlags: event.flags)
                return nil
            }
            return Unmanaged.passUnretained(event)
        }

        let matched = inputLock.withLock { () -> TextSnippet? in
            buffer = TextSnippetSupport.bufferAppending(buffer, typed: typed)
            let match = TextSnippetSupport.match(buffer: buffer,
                                                 expansion: .immediate,
                                                 snippets: immediateSnippets)
            if match != nil { buffer = "" }
            return match
        }
        if let matched {
            // Suppress the final trigger event. The replacement is posted
            // before this callback returns, so later typing cannot overtake it.
            expand(matched,
                   deleteCount: max(0, matched.trigger.count - typed.count),
                   trailingKeyCode: nil,
                   trailingFlags: [])
            return nil
        }
        return Unmanaged.passUnretained(event)
    }

    // MARK: - Expansion

    private func expand(_ snippet: TextSnippet,
                        deleteCount: Int,
                        trailingKeyCode: CGKeyCode?,
                        trailingFlags: CGEventFlags) {
        let post = {
            // The replacement has to be posted before this callback returns,
            // so later typing cannot overtake it — the read cannot move off
            // this thread. It can be skipped, though, and for every snippet
            // that does not name the clipboard it now is.
            let clipboard = TextSnippetSupport.needsClipboard(snippet.replacement)
                ? NSPasteboard.general.string(forType: .string)
                : nil
            let text = TextSnippetSupport.expand(
                snippet.replacement,
                date: Date(),
                clipboard: clipboard
            )
            Self.postExpansion(deleteCount: deleteCount,
                               text: text,
                               trailingKeyCode: trailingKeyCode,
                               trailingFlags: trailingFlags)
        }
        if Thread.isMainThread {
            post()
        } else {
            DispatchQueue.main.sync(execute: post)
        }
    }

    /// Also the snippet library's insertion path (deleteCount 0): one typing
    /// routine, one synthetic marker, one set of quirks.
    static func postExpansion(deleteCount: Int,
                              text: String,
                              trailingKeyCode: CGKeyCode?,
                              trailingFlags: CGEventFlags) {
        let source = CGEventSource(stateID: .hidSystemState)
        source?.userData = syntheticMarker

        func post(_ event: CGEvent?) {
            event?.post(tap: .cghidEventTap)
        }
        func postKey(_ keyCode: CGKeyCode, flags: CGEventFlags = []) {
            for down in [true, false] {
                let event = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: down)
                event?.flags = flags
                post(event)
            }
        }

        for _ in 0..<deleteCount {
            postKey(CGKeyCode(kVK_Delete))
        }

        // Typed injection instead of pasting: the clipboard stays untouched.
        // Keystroke events carry at most ~20 UTF-16 units reliably.
        let units = Array(text.utf16)
        var index = 0
        while index < units.count {
            var end = min(index + 20, units.count)
            // Never split a surrogate pair across chunks: two lone halves in
            // separate events render as replacement characters in some apps.
            if end < units.count, UTF16.isLeadSurrogate(units[end - 1]) {
                end -= 1
            }
            let chunk = Array(units[index..<end])
            for down in [true, false] {
                guard let event = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: down) else { continue }
                event.keyboardSetUnicodeString(stringLength: chunk.count, unicodeString: chunk)
                post(event)
            }
            index = end
        }

        if let trailingKeyCode {
            postKey(trailingKeyCode, flags: trailingFlags)
        }
    }
}
