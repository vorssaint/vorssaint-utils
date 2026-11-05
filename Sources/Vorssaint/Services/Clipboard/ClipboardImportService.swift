// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import UniformTypeIdentifiers

enum ClipboardImportOutcome: Equatable {
    case imported
    case failed(ClipboardImportFailure)
}

enum ClipboardImportFailure: Equatable {
    case empty
    case incompatible
}

enum ClipboardSnapshot {
    case compatible(NSPasteboard)
    case empty
    case incompatible
}

final class ClipboardImportService {
    static let shared = ClipboardImportService()

    private init() {}

    func fetchSnapshot(completion: @escaping (ClipboardSnapshot) -> Void) {
        GeneralPasteboardAccess.shared.async({ Self.snapshotGeneralPasteboard() }, then: completion)
    }

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

    private static func snapshotGeneralPasteboard() -> ClipboardSnapshot {
        let source = NSPasteboard.general
        guard let entries = source.pasteboardItems, !entries.isEmpty else { return .empty }

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
