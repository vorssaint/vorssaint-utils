// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import ApplicationServices
import Carbon.HIToolbox
import Foundation

/// Copies text to the pasteboard as soon as it is selected with the mouse, the
/// way a terminal does: a drag, a double click or a triple click, with no
/// Command-C.
///
/// The selection is read through Accessibility first. Many apps do not report
/// it: a Chromium browser or an Electron app, for one, needs an accessibility
/// mode it avoids on purpose (issue #953). When the read finds no text, a
/// Command-C is sent, but only if the pointer showed the text cursor at some
/// point in the gesture. Outside text the shortcut can copy something that was
/// never selected, such as files in the Finder or the current line in a code
/// editor. Watching the mouse needs no permission of its own.
///
/// Rides the clipboard feature's availability like auto clear does, and the
/// text it writes is an ordinary copy: history records it.
final class CopyOnSelectService {
    static let shared = CopyOnSelectService()

    /// How long to wait after the button comes up before asking for the
    /// selection, so the app has finished updating it.
    private static let settleDelay: TimeInterval = 0.08
    /// How often the cursor is looked at during a drag, which sends events far
    /// faster than the cursor can change.
    private static let cursorSampleInterval: TimeInterval = 0.05

    private var monitor: Any?
    private var gesture = CopyOnSelectGesture()
    private var sawTextCursor = false
    private var lastCursorSample: TimeInterval = 0
    /// The last text this service read and copied, kept only in memory.
    private var lastCopiedSelection: String?
    /// Only ever one read in flight: it asks another app, which can be slow.
    private var readInFlight = false
    /// Bumped whenever the service stops, so a read that outlives the setting
    /// can never write.
    private var generation = 0
    private let readQueue = DispatchQueue(label: "Vorssaint.CopyOnSelect.read", qos: .userInitiated)

    private init() {}

    func syncWithPreferences() {
        let isWanted = AppFeature.clipboardHistory.isAvailable
            && UserDefaults.standard.bool(forKey: DefaultsKey.clipboardCopyOnSelect)
        if isWanted {
            start()
        } else {
            stop()
        }
    }

    private func start() {
        guard monitor == nil else { return }
        monitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .leftMouseDragged, .leftMouseUp]
        ) { [weak self] event in
            self?.handle(event)
        }
    }

    private func stop() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        gesture = CopyOnSelectGesture()
        generation &+= 1
        readInFlight = false
        lastCopiedSelection = nil
    }

    private func handle(_ event: NSEvent) {
        switch event.type {
        case .leftMouseDown:
            gesture.press(at: NSEvent.mouseLocation)
            sawTextCursor = Self.pointerShowsTextCursor()
            lastCursorSample = event.timestamp
        case .leftMouseDragged:
            gesture.drag(to: NSEvent.mouseLocation)
            if !sawTextCursor, event.timestamp - lastCursorSample >= Self.cursorSampleInterval {
                lastCursorSample = event.timestamp
                sawTextCursor = Self.pointerShowsTextCursor()
            }
        case .leftMouseUp:
            if !sawTextCursor { sawTextCursor = Self.pointerShowsTextCursor() }
            if gesture.release(at: NSEvent.mouseLocation, clickCount: event.clickCount) {
                copySelectionAfterSettling(sawTextCursor: sawTextCursor)
            }
        default:
            break
        }
    }

    /// The system hands back its own cursor object, never the shared one, so the
    /// two are compared by what they draw.
    private static func pointerShowsTextCursor() -> Bool {
        guard let current = NSCursor.currentSystem else { return false }
        let textCursor = NSCursor.iBeam
        return current.hotSpot == textCursor.hotSpot
            && current.image.size == textCursor.image.size
            && current.image.tiffRepresentation == textCursor.image.tiffRepresentation
    }

    private func copySelectionAfterSettling(sawTextCursor: Bool) {
        guard AXIsProcessTrusted() else { return }
        let generation = generation
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.settleDelay) { [weak self] in
            guard let self, self.generation == generation, !self.readInFlight,
                  let app = NSWorkspace.shared.frontmostApplication,
                  app.processIdentifier != ProcessInfo.processInfo.processIdentifier else { return }
            self.readInFlight = true
            let processID = app.processIdentifier
            // Reading blocks on the other app, which can be slow to answer, so
            // never on the main thread: a stalled main thread stalls every
            // event tap in the app with it.
            self.readQueue.async { [weak self] in
                let text = SelectedTextReader.read(processID: processID)?.text
                let sendsShortcut = CopyOnSelectSupport.shouldSendCopyShortcut(readText: text,
                                                                               sawTextCursor: sawTextCursor)
                DispatchQueue.main.async { [weak self] in
                    guard let self, self.generation == generation else { return }
                    self.readInFlight = false
                    if sendsShortcut {
                        self.postCopyShortcut(generation: generation)
                    } else if let text, !text.isEmpty,
                              CopyOnSelectSupport.isNewSelection(text,
                                                                 lastCopied: self.lastCopiedSelection,
                                                                 sawTextCursor: sawTextCursor) {
                        self.lastCopiedSelection = text
                        self.write(text)
                    }
                }
            }
        }
    }

    /// Sends Command-C to the app in front. Skipped while a modifier is held,
    /// such as Shift extending a selection, which would turn it into another
    /// shortcut.
    private func postCopyShortcut(generation: Int) {
        guard self.generation == generation,
              CGEventSource.flagsState(.combinedSessionState)
                  .intersection([.maskCommand, .maskAlternate, .maskShift, .maskControl]).isEmpty,
              let keyDown = CGEvent(keyboardEventSource: nil,
                                    virtualKey: CGKeyCode(kVK_ANSI_C),
                                    keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: nil,
                                  virtualKey: CGKeyCode(kVK_ANSI_C),
                                  keyDown: false)
        else { return }
        keyDown.flags = .maskCommand
        // Only the press carries Command. A release that carries it too leaves
        // the system reporting Command as held, and the next click then acts as
        // a Command-click.
        keyUp.flags = []
        keyDown.post(tap: .cghidEventTap)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.04) {
            keyUp.post(tap: .cghidEventTap)
        }
    }

    private func write(_ text: String) {
        GeneralPasteboardAccess.shared.async {
            // The setting can be switched off while the read was in flight.
            guard AppFeature.clipboardHistory.isAvailable,
                  UserDefaults.standard.bool(forKey: DefaultsKey.clipboardCopyOnSelect) else { return }
            let pasteboard = NSPasteboard.general
            guard CopyOnSelectSupport.shouldCopy(selected: text,
                                                 pasteboardText: pasteboard.string(forType: .string)) else { return }
            pasteboard.clearContents()
            pasteboard.setString(text, forType: .string)
        }
    }
}
