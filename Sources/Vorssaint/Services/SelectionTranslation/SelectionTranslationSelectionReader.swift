// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import ApplicationServices

enum SelectionTranslationSelectionReader {
    static func read() async -> String {
        let direct = await Task.detached(priority: .userInitiated) {
            CommandBarSelectionReader.readSelectedText()
        }.value
        if !direct.isEmpty { return direct }
        return await withCheckedContinuation { continuation in
            GeneralPasteboardAccess.shared.async {
                let board = NSPasteboard.general
                let previous = board.string(forType: .string)
                let change = board.changeCount
                postCopy()
                var selected = ""
                let deadline = Date().addingTimeInterval(0.35)
                repeat {
                    if board.changeCount != change {
                        selected = board.string(forType: .string) ?? ""
                        break
                    }
                    usleep(20_000)
                } while Date() < deadline
                if let previous {
                    board.clearContents()
                    board.setString(previous, forType: .string)
                }
                let finalChange = board.changeCount
                DispatchQueue.main.async {
                    ClipboardHistoryService.shared.ignoreNextChange(upTo: finalChange)
                }
                return selected.trimmingCharacters(in: .whitespacesAndNewlines)
            } then: { continuation.resume(returning: $0) }
        }
    }

    private static func postCopy() {
        let source = CGEventSource(stateID: .combinedSessionState)
        let down = CGEvent(keyboardEventSource: source, virtualKey: 8, keyDown: true)
        let up = CGEvent(keyboardEventSource: source, virtualKey: 8, keyDown: false)
        down?.flags = .maskCommand
        up?.flags = .maskCommand
        down?.post(tap: .cghidEventTap)
        up?.post(tap: .cghidEventTap)
    }
}
