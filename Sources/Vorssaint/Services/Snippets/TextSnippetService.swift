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

    private var tap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var activationObserver: NSObjectProtocol?
    private var buffer = ""
    /// Split by expansion mode at load time; the tap callback only scans.
    private var immediateSnippets: [TextSnippet] = []
    private var delimiterSnippets: [TextSnippet] = []

    private init() {}

    var isRunning: Bool { tap != nil }

    func syncWithPreferences() {
        let enabled = AppFeature.textSnippets.isAvailable
            && UserDefaults.standard.bool(forKey: DefaultsKey.textSnippetsEnabled)
        reloadSnippets()
        let hasWork = !(immediateSnippets.isEmpty && delimiterSnippets.isEmpty)
        if enabled, hasWork, Permissions.shared.accessibility {
            start()
        } else {
            stop()
        }
    }

    func suspend() { stop() }

    /// Reloads the stored snippets; called by the settings page after edits.
    private func reloadSnippets() {
        let all = TextSnippetSupport.decode(
            UserDefaults.standard.data(forKey: DefaultsKey.textSnippets))
        immediateSnippets = all.filter { $0.enabled && $0.expansion == .immediate }
        delimiterSnippets = all.filter { $0.enabled && $0.expansion == .afterDelimiter }
    }

    private func start() {
        guard tap == nil else { return }
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
                let service = Unmanaged<TextSnippetService>.fromOpaque(userInfo).takeUnretainedValue()
                return service.handle(type: type, event: event)
            },
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else { return }

        self.tap = tap
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        runLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)

        // Switching apps invalidates whatever was half-typed there.
        activationObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil, queue: .main) { [weak self] _ in
            self?.buffer = ""
        }
    }

    private func stop() {
        if let tap {
            CGEvent.tapEnable(tap: tap, enable: false)
        }
        if let runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        }
        tap = nil
        runLoopSource = nil
        if let activationObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(activationObserver)
            self.activationObserver = nil
        }
        buffer = ""
    }

    // MARK: - Tap

    private func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return Unmanaged.passUnretained(event)
        }
        // Clicks move the caret somewhere unknown; the half-typed trigger is
        // no longer where the deletes would land.
        if type == .leftMouseDown || type == .rightMouseDown {
            buffer = ""
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
            buffer = ""
            return Unmanaged.passUnretained(event)
        }
        // Typing in the library's own search field must never expand a
        // trigger: the deletes would land in the search box. Tap and panel
        // both live on the main run loop, so the check is safe here.
        guard !SnippetLibraryService.shared.isVisible else {
            buffer = ""
            return Unmanaged.passUnretained(event)
        }
        // Shortcuts are commands, not text.
        if !event.flags.intersection([.maskCommand, .maskControl]).isEmpty {
            buffer = ""
            return Unmanaged.passUnretained(event)
        }

        let keyCode = Int(event.getIntegerValueField(.keyboardEventKeycode))
        switch keyCode {
        case kVK_Delete:
            if !buffer.isEmpty { buffer.removeLast() }
            return Unmanaged.passUnretained(event)
        case kVK_LeftArrow, kVK_RightArrow, kVK_UpArrow, kVK_DownArrow, kVK_Escape,
             kVK_Home, kVK_End, kVK_PageUp, kVK_PageDown, kVK_ForwardDelete:
            buffer = ""
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
            let matched = TextSnippetSupport.match(buffer: buffer,
                                                   expansion: .afterDelimiter,
                                                   snippets: delimiterSnippets)
            buffer = ""
            if let matched {
                expand(matched,
                       deleteCount: matched.trigger.count,
                       trailingKeyCode: CGKeyCode(keyCode),
                       trailingFlags: event.flags)
                return nil
            }
            return Unmanaged.passUnretained(event)
        }

        buffer = TextSnippetSupport.bufferAppending(buffer, typed: typed)
        if let matched = TextSnippetSupport.match(buffer: buffer,
                                                  expansion: .immediate,
                                                  snippets: immediateSnippets) {
            buffer = ""
            // The final trigger character passes through (it is on screen by
            // the time the deletes land), so it counts toward the deletes.
            expand(matched, deleteCount: matched.trigger.count, trailingKeyCode: nil, trailingFlags: [])
        }
        return Unmanaged.passUnretained(event)
    }

    // MARK: - Expansion

    private func expand(_ snippet: TextSnippet,
                        deleteCount: Int,
                        trailingKeyCode: CGKeyCode?,
                        trailingFlags: CGEventFlags) {
        let text = TextSnippetSupport.expand(snippet.replacement,
                                             date: Date(),
                                             clipboard: NSPasteboard.general.string(forType: .string))
        // Outside the tap callback: posting from inside it would reorder the
        // synthetic events around the one still in flight.
        DispatchQueue.main.async {
            Self.postExpansion(deleteCount: deleteCount,
                               text: text,
                               trailingKeyCode: trailingKeyCode,
                               trailingFlags: trailingFlags)
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
