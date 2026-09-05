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
    /// One retained instance so back-to-back expansions can stop and
    /// restart it, and so no expansion pays for the first lookup's disk
    /// read. nil means no sound plays.
    private var expansionSound: NSSound?
    /// Split by expansion mode at load time; the tap callback only scans.
    private var immediateSnippets: [TextSnippet] = []
    private var delimiterSnippets: [TextSnippet] = []

    private init() {
        SessionActivity.shared.onChange { [weak self] _ in self?.syncWithPreferences() }
    }

    var isRunning: Bool { tapLifecycleLock.withLock { tap != nil } }

    func syncWithPreferences() {
        let enabled = AppFeature.textSnippets.isAvailable
            && UserDefaults.standard.bool(forKey: DefaultsKey.textSnippetsEnabled)
        reloadSnippets()
        let hasWork = inputLock.withLock {
            !(immediateSnippets.isEmpty && delimiterSnippets.isEmpty)
        }
        syncExpansionSound(featureEnabled: enabled)
        if SessionActivitySupport.tapShouldRun(featureWanted: enabled && hasWork,
                                               accessibilityGranted: AXIsProcessTrusted(),
                                               sessionIsActive: SessionActivity.shared.isActive) {
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

    /// Plays the sound an expansion would play, for the picker's preview.
    /// Plays the retained one, so the preview cannot demonstrate a sound
    /// other than the one that will fire; it resolves for itself only
    /// when nothing is retained, which is when the feature is off.
    func previewExpansionSound() {
        let retained = inputLock.withLock { expansionSound }
        let stored = UserDefaults.standard.string(forKey: DefaultsKey.snippetSoundName)
        guard let sound = retained
                ?? TextSnippetSupport.resolvedSoundName(stored: stored).flatMap({ NSSound(named: $0) })
        else { return }
        sound.stop()
        sound.play()
    }

    /// Picks up a change to the sound preferences on their own. The picker
    /// fires on every arrow-key move through the list, and going through
    /// syncWithPreferences would reload every snippet and tear down and
    /// rebuild the event tap each time.
    ///
    /// `featureEnabled` is whether text snippets are on at all. Passed in
    /// by syncWithPreferences, which has already worked it out, so the two
    /// cannot answer that question differently.
    func syncExpansionSound(featureEnabled: Bool? = nil) {
        let featureOn = featureEnabled ?? (AppFeature.textSnippets.isAvailable
            && UserDefaults.standard.bool(forKey: DefaultsKey.textSnippetsEnabled))
        let soundEnabled = featureOn
            && UserDefaults.standard.bool(forKey: DefaultsKey.snippetSoundEnabled)
        let stored = UserDefaults.standard.string(forKey: DefaultsKey.snippetSoundName)
        let name = TextSnippetSupport.resolvedSoundName(stored: stored)
        let sound = soundEnabled ? name.flatMap { NSSound(named: $0) } : nil
        inputLock.withLock { expansionSound = sound }
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
        ) { [weak self] note in
            // Not when the Accessibility Keyboard itself comes forward: pressing
            // one of its keys is typing into the app you were already in, so the
            // buffer has to survive it. Otherwise this clears what the mouse-down
            // branch above just took care to keep.
            if let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
               app.bundleIdentifier == AssistiveKeyboard.bundleID {
                return
            }
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
            if SessionActivity.shared.isActive, AXIsProcessTrusted(), let currentTap {
                CGEvent.tapEnable(tap: currentTap, enable: true)
            } else {
                DispatchQueue.main.async { [weak self] in self?.syncWithPreferences() }
            }
            return Unmanaged.passUnretained(event)
        }
        // Clicks move the caret somewhere unknown; the half-typed trigger is
        // no longer where the deletes would land. A click on the Accessibility
        // Keyboard is the exception: there the mouse is how a key is pressed,
        // so the click types a character and leaves the caret alone. That check
        // costs a nil test unless that keyboard is actually running.
        if type == .leftMouseDown || type == .rightMouseDown {
            if !AssistiveKeyboard.ownsPoint(event.location) { resetBuffer() }
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
            // delimiter is swallowed and kept after the replacement, either
            // in the same paste or as the original key after typed injection.
            let matched = inputLock.withLock { () -> TextSnippet? in
                let match = TextSnippetSupport.match(buffer: buffer,
                                                     expansion: .afterDelimiter,
                                                     snippets: delimiterSnippets)
                buffer = ""
                return match
            }
            if let matched {
                return expand(matched,
                              deleteCount: matched.trigger.count,
                              trailingKeyCode: CGKeyCode(keyCode),
                              trailingFlags: event.flags,
                              trailingText: typed,
                              failureKeyCode: CGKeyCode(keyCode))
                    ? nil
                    : Unmanaged.passUnretained(event)
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
            // Suppress the final trigger event once the replacement path has
            // accepted it. A busy transient paste fails open to normal typing.
            return expand(matched,
                          deleteCount: max(0, matched.trigger.count - typed.count),
                          trailingKeyCode: nil,
                          trailingFlags: [],
                          trailingText: "",
                          failureKeyCode: CGKeyCode(keyCode),
                          failureFlags: event.flags)
                ? nil
                : Unmanaged.passUnretained(event)
        }
        return Unmanaged.passUnretained(event)
    }

    // MARK: - Expansion

    @discardableResult
    private func expand(_ snippet: TextSnippet,
                        deleteCount: Int,
                        trailingKeyCode: CGKeyCode?,
                        trailingFlags: CGEventFlags,
                        trailingText: String,
                        failureKeyCode: CGKeyCode?,
                        failureFlags: CGEventFlags = []) -> Bool {
        let didExpand = expansionSoundCue()
        let post = { () -> Bool in
            // Variable expansion is decided while the triggering event still
            // belongs to this callback. Only an explicit clipboard variable
            // pays for a synchronous read; the multiline write itself runs on
            // the shared pasteboard lane.
            let clipboard = TextSnippetSupport.needsClipboard(snippet.replacement)
                ? NSPasteboard.general.string(forType: .string)
                : nil
            let text = TextSnippetSupport.expand(
                snippet.replacement,
                date: Date(),
                clipboard: clipboard
            )
            return Self.postExpansion(deleteCount: deleteCount,
                                      text: text,
                                      trailingKeyCode: trailingKeyCode,
                                      trailingFlags: trailingFlags,
                                      trailingText: trailingText,
                                      failureKeyCode: failureKeyCode,
                                      failureFlags: failureFlags,
                                      didExpand: didExpand)
        }
        return Thread.isMainThread ? post() : DispatchQueue.main.sync(execute: post)
    }

    /// Hung off the replacement going out rather than off `postExpansion`'s
    /// return value: a transient paste reports success as soon as it reaches
    /// the pasteboard lane, so its return cannot tell a paste that went out
    /// from one that failed open to typing. It also keeps the sound behind
    /// the paste instead of ahead of it, since the shortcut waits for the
    /// modifiers to come up.
    ///
    /// Nil when no sound is retained, which is when the feature is off.
    private func expansionSoundCue() -> (() -> Void)? {
        guard let sound = inputLock.withLock({ expansionSound }) else { return nil }
        return {
            // Async because the typed path calls this while the tap callback
            // may still be blocked on the main queue, and starting playback
            // can take long enough to push that callback past the timeout
            // macOS disables the tap for.
            DispatchQueue.main.async {
                // play() is a no-op while this instance is still playing:
                // stop it first so back-to-back expansions inside one
                // sound's duration are still audible.
                sound.stop()
                sound.play()
            }
        }
    }

    /// Also the snippet library's insertion path (deleteCount 0): one typing
    /// routine, one synthetic marker, one set of quirks.
    @discardableResult
    static func postExpansion(deleteCount: Int,
                              text: String,
                              trailingKeyCode: CGKeyCode?,
                              trailingFlags: CGEventFlags,
                              trailingText: String = "",
                              failureKeyCode: CGKeyCode? = nil,
                              failureFlags: CGEventFlags = [],
                              didExpand: (() -> Void)? = nil) -> Bool {
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

        if TextSnippetSupport.requiresPaste(text) {
            let payload = TextSnippetSupport.pastePayload(text: text, trailingText: trailingText)
            return TransientPaste.shared.paste(
                payload,
                willPostShortcut: {
                    for _ in 0..<deleteCount { postKey(CGKeyCode(kVK_Delete)) }
                },
                didPostShortcut: { didExpand?() },
                didFail: {
                    if let failureKeyCode { postKey(failureKeyCode, flags: failureFlags) }
                }
            )
        }

        for _ in 0..<deleteCount { postKey(CGKeyCode(kVK_Delete)) }

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
        didExpand?()
        return true
    }
}
