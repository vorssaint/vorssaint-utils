// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import ApplicationServices

/// The snapshot is created and consumed on `GeneralPasteboardAccess`'s serial
/// lane. It only crosses the main queue while waiting for the physical shortcut
/// modifiers to clear, and is never read there.
private final class SelectionTranslationPasteboardContext: @unchecked Sendable {
    let snapshot: [NSPasteboardItem]
    let originalChangeCount: Int

    init(snapshot: [NSPasteboardItem], originalChangeCount: Int) {
        self.snapshot = snapshot
        self.originalChangeCount = originalChangeCount
    }
}

private final class SelectionTranslationCaptureDeferralBox: @unchecked Sendable {
    var token: ClipboardHistoryCaptureDeferral?
}

enum SelectionTranslationSelectionReader {
    static func read() async -> String {
        let direct = await Task.detached(priority: .userInitiated) {
            CommandBarSelectionReader.readSelectedText()
        }.value
        if !direct.isEmpty { return direct }
        return await readViaPasteboard()
    }

    private static func readViaPasteboard() async -> String {
        await withCheckedContinuation { continuation in
            GeneralPasteboardAccess.shared.async {
                let board = NSPasteboard.general
                let originalChangeCount = board.changeCount
                guard let snapshot = TransientPaste.snapshot(of: board),
                      board.changeCount == originalChangeCount else {
                    continuation.resume(returning: "")
                    return
                }
                let context = SelectionTranslationPasteboardContext(
                    snapshot: snapshot,
                    originalChangeCount: originalChangeCount)

                // Posting from the main queue is intentional: the helper
                // polls the physical modifier state before it synthesizes C.
                let captureDeferralBox = SelectionTranslationCaptureDeferralBox()
                DispatchQueue.main.async {
                    TransientPaste.postKeyWhenModifiersReleased(
                        keyCode: SelectionTranslationPasteboardSupport.copyKeyCode,
                        flags: .maskCommand,
                        timeoutBehavior: .failOnTimeout,
                        willPost: {
                            captureDeferralBox.token = ClipboardHistoryService.shared.beginCaptureDeferral()
                        }
                    ) { succeeded in
                        guard let captureDeferral = captureDeferralBox.token else {
                            continuation.resume(returning: "")
                            return
                        }
                        guard succeeded else {
                            ClipboardHistoryService.shared.endCaptureDeferral(captureDeferral)
                            continuation.resume(returning: "")
                            return
                        }
                        GeneralPasteboardAccess.shared.async {
                            let board = NSPasteboard.general
                            let originalChangeCount = context.originalChangeCount
                            var selected = ""
                            var copyChangeCount: Int?
                            let deadline = Date().addingTimeInterval(0.35)
                            repeat {
                                let changeCount = board.changeCount
                                if changeCount != originalChangeCount {
                                    copyChangeCount = changeCount
                                    selected = board.string(forType: .string) ?? ""
                                    break
                                }
                                usleep(20_000)
                            } while Date() < deadline

                            var ignoredThrough: Int?
                            if let copyChangeCount {
                                ignoredThrough = copyChangeCount
                                let currentChangeCount = board.changeCount
                                if SelectionTranslationPasteboardSupport.shouldRestore(
                                    originalChangeCount: originalChangeCount,
                                    copyChangeCount: copyChangeCount,
                                    currentChangeCount: currentChangeCount
                                ) {
                                    board.clearContents()
                                    if !context.snapshot.isEmpty { board.writeObjects(context.snapshot) }
                                    let restoredChangeCount = board.changeCount
                                    ignoredThrough = restoredChangeCount
                                }
                            }
                            let trimmed = selected.trimmingCharacters(in: .whitespacesAndNewlines)
                            let result = trimmed.count <= CommandBarSelectionReader.maximumLength ? trimmed : ""
                            DispatchQueue.main.async {
                                ClipboardHistoryService.shared.endCaptureDeferral(
                                    captureDeferral,
                                    ignoringUpTo: ignoredThrough
                                )
                                continuation.resume(returning: result)
                            }
                        }
                    }
                }
            }
        }
    }
}
