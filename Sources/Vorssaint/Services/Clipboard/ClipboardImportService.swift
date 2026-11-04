// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import UniformTypeIdentifiers

/// How a clipboard paste into the shelf ended, so the caller can decide
/// whether to surface feedback. Success is silent on purpose: the item
/// appearing on the shelf (and the docked shelf's green tick) is the
/// feedback, exactly as it is after a drop.
enum ClipboardImportOutcome: Equatable {
    case imported
    case failed(ClipboardImportFailure)
}

enum ClipboardImportFailure: Equatable {
    /// The general pasteboard has nothing readable on it.
    case empty
    /// It has content, but none of it maps to a file, image, link or text.
    case incompatible
}

/// The general pasteboard, read off the main thread and copied into a private
/// board whose content is already rendered. Callers import from the private
/// board on the main thread, so no paste path ever blocks on a third-party app.
enum ClipboardSnapshot {
    case compatible(NSPasteboard)
    case empty
    case incompatible
}

/// Centralized clipboard paste support for the app's file-capable input
/// surfaces (the shelf and the notch's Files/Media module). It mirrors the drop
/// path (same accepted types, same capacity and thumbnail rules) but reads the
/// *general* pasteboard instead of the drag pasteboard, so Cmd+V works wherever
/// files are accepted.
///
/// The read is serialized through `GeneralPasteboardAccess`: AppKit pasteboard
/// reads can block on promised content, so everything that touches the general
/// pasteboard happens off the main thread. What comes back is a private
/// pasteboard whose contents are already rendered, so an ordinary
/// `accept(pasteboard:)` (which runs on main) never blocks.
final class ClipboardImportService {
    static let shared = ClipboardImportService()

    private init() {}

    /// Reads the general clipboard off the main thread and hands the snapshot
    /// back on the main thread. The caller keeps the private pasteboard and is
    /// responsible for `releaseGlobally()` after importing from it.
    func fetchSnapshot(completion: @escaping (ClipboardSnapshot) -> Void) {
        GeneralPasteboardAccess.shared.async({ Self.snapshotGeneralPasteboard() }, then: completion)
    }

    /// Reads the clipboard and, when it carries something the shelf can hold,
    /// imports it. Always reports the outcome back on the main thread; the
    /// import itself reuses `ShelfService.accept(pasteboard:)`, so capacity,
    /// validation and payload persistence behave exactly like a drop.
    func pasteIntoCurrentShelf(completion: @escaping (ClipboardImportOutcome) -> Void = { _ in }) {
        let shelf = ShelfService.shared
        guard AppFeature.shelf.isAvailable,
              UserDefaults.standard.bool(forKey: DefaultsKey.shelfEnabled) else {
            completion(.failed(.incompatible))
            return
        }
        fetchSnapshot { result in
            switch result {
            case let .compatible(board):
                defer { board.releaseGlobally() }
                let accepted = shelf.accept(pasteboard: board)
                completion(accepted ? .imported : .failed(.incompatible))
            case .empty:
                completion(.failed(.empty))
            case .incompatible:
                completion(.failed(.incompatible))
            }
        }
    }

    /// Materializes a raw clipboard image into a temporary PNG so file-based
    /// importers (the media tool) can use it. Nil when the board carries no
    /// raw image or the write fails. The caller owns the returned file.
    static func materializedImageURL(from pasteboard: NSPasteboard) -> URL? {
        guard let image = NSImage(pasteboard: pasteboard) else { return nil }
        guard let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let png = rep.representation(using: .png, properties: [:]) else { return nil }
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("VorssaintClipboard-\(UUID().uuidString).png", isDirectory: false)
        do {
            try png.write(to: url)
            return url
        } catch {
            return nil
        }
    }

    /// Copies every droppable, already-rendered type off the general
    /// pasteboard into a fresh private board. Copying `data(forType:)` here is
    /// what forces any promised content to render off the main thread; file
    /// promises themselves are not cloned (they have no data to copy and are
    /// not how clipboard file copies arrive — those come as file URLs).
    private static func snapshotGeneralPasteboard() -> ClipboardSnapshot {
        let source = NSPasteboard.general
        guard let entries = source.pasteboardItems, !entries.isEmpty else { return .empty }

        // `writeObjects` replaces the board's contents rather than appending,
        // so build every cloned item first and write them all in one call.
        var copies: [NSPasteboardItem] = []
        for entry in entries {
            let copy = NSPasteboardItem()
            for type in entry.types where ShelfPasteboardSupport.isDroppablePasteboardType(type.rawValue)
                && !ShelfPasteboardSupport.isFilePromiseType(type.rawValue) {
                guard let data = entry.data(forType: type), !data.isEmpty else { continue }
                copy.setData(data, forType: type)
            }
            if !copy.types.isEmpty { copies.append(copy) }
        }
        guard !copies.isEmpty else { return .incompatible }

        let board = NSPasteboard.withUniqueName()
        guard board.writeObjects(copies) else {
            board.releaseGlobally()
            return .incompatible
        }
        return .compatible(board)
    }
}
