// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

enum FinderTests {
    static func run(expect: (Bool, String) -> Void) {
        // MARK: Cut and paste move progress (issue #168)

        expect(!CutPasteProgressSupport.isCrossVolume(source: NSNumber(value: 1),
                                                      destination: NSNumber(value: 1)),
               "a move inside one volume never shows progress")
        expect(CutPasteProgressSupport.isCrossVolume(source: NSNumber(value: 1),
                                                     destination: NSNumber(value: 2)),
               "a move between volumes is recognized as a real copy")
        expect(!CutPasteProgressSupport.isCrossVolume(source: nil,
                                                      destination: NSNumber(value: 2)),
               "unknown volume identities fall back to the silent same-volume path")
        expect(CutPasteProgressSupport.fraction(finishedBytes: 0, currentBytes: 0, totalBytes: 0) == nil,
               "an unknown byte total yields an indeterminate bar, not a broken fraction")
        expect(CutPasteProgressSupport.fraction(finishedBytes: 50, currentBytes: 25, totalBytes: 150) == 0.5,
               "progress combines finished files with the growing destination")
        expect(CutPasteProgressSupport.fraction(finishedBytes: 100, currentBytes: 200, totalBytes: 150) == 1.0,
               "progress clamps at full when the destination briefly over-reports")
        expect(CutPasteProgressSupport.fraction(finishedBytes: -5, currentBytes: -5, totalBytes: 100) == 0.0,
               "negative byte readings clamp to an empty bar")
        expect(CutPasteProgressSupport.displayPosition(completed: 1, total: 5) == 2,
               "the counter shows the item currently moving, one past the finished count")
        expect(CutPasteProgressSupport.displayPosition(completed: 5, total: 5) == 5,
               "the counter never runs past the batch size")

        expect(CutPastePrivilegeSupport.needsPrivileges(
            NSError(domain: NSCocoaErrorDomain, code: NSFileWriteNoPermissionError)),
               "a destination the account cannot write is worth handing to Finder")
        expect(CutPastePrivilegeSupport.needsPrivileges(
            NSError(domain: NSPOSIXErrorDomain, code: Int(EACCES))),
               "a POSIX permission refusal reaches the same retry")
        expect(CutPastePrivilegeSupport.needsPrivileges(
            NSError(domain: NSCocoaErrorDomain, code: NSFileWriteFileExistsError,
                    userInfo: [NSUnderlyingErrorKey: NSError(domain: NSPOSIXErrorDomain,
                                                             code: Int(EPERM))])),
               "the refusal is found in the underlying error too")
        expect(!CutPastePrivilegeSupport.needsPrivileges(
            NSError(domain: NSCocoaErrorDomain, code: NSFileWriteOutOfSpaceError)),
               "a full disk fails the same way for Finder, so it never asks")
        expect(!CutPastePrivilegeSupport.needsPrivileges(
            NSError(domain: NSCocoaErrorDomain, code: NSFileWriteVolumeReadOnlyError)),
               "a read-only volume never raises a dialog it cannot use")
        expect(!CutPastePrivilegeSupport.needsPrivileges(
            NSError(domain: NSURLErrorDomain, code: NSURLErrorCannotWriteToFile)),
               "an unrelated error domain stays a plain failure")
        do {
            let fm = FileManager.default
            let root = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            let destination = root.appendingPathComponent("destination")
            try fm.createDirectory(at: destination, withIntermediateDirectories: true)
            defer { try? fm.removeItem(at: root) }
            let first = root.appendingPathComponent("first")
            let second = root.appendingPathComponent("second")
            try Data([1]).write(to: first)
            try Data([2]).write(to: second)
            let canceled = CutPastePrivilegeSupport.reconcile(
                [first, second], into: destination, canceled: true, fm: fm)
            expect(canceled.moved == 0 && canceled.failed == 0
                && canceled.stillCut == [first, second],
                   "canceling before a move keeps the whole selection")
            try fm.moveItem(at: first, to: destination.appendingPathComponent("first"))
            let partial = CutPastePrivilegeSupport.reconcile(
                [first, second], into: destination, canceled: true, fm: fm)
            expect(partial.moved == 1 && partial.failed == 0 && partial.stillCut == [second],
                   "canceling after a partial move retains only the unmoved file")
            let failure = CutPastePrivilegeSupport.reconcile(
                [first, second], into: destination, canceled: false, fm: fm)
            expect(failure.moved == 1 && failure.failed == 1 && failure.stillCut.isEmpty,
                   "a partial failure reports the files that actually landed")
            try fm.removeItem(at: second)
            let vanished = CutPastePrivilegeSupport.reconcile(
                [second], into: destination, canceled: false, fm: fm)
            expect(vanished.moved == 0 && vanished.failed == 1,
                   "a missing source without a destination is not a successful move")
            try Data([2]).write(to: destination.appendingPathComponent("second"))
            let success = CutPastePrivilegeSupport.reconcile(
                [first, second], into: destination, canceled: false, fm: fm)
            expect(success.moved == 2 && success.failed == 0 && success.stillCut.isEmpty,
                   "a completed batch clears every cut mark")
        } catch {
            expect(false, "protected-folder move fixtures: \(error)")
        }

        // MARK: Paste copied image as file (issue #429)

        expect(FinderPasteImageSupport.preferredImageType(in: ["public.utf8-plain-text"]) == nil,
               "text never replaces Finder's normal paste")
        expect(FinderPasteImageSupport.preferredImageType(in: ["public.tiff", "public.png"])
                == "public.png",
               "PNG wins when the pasteboard offers several image representations")
        expect(FinderPasteImageSupport.preferredImageType(
            in: ["public.file-url", "public.png"]
        ) == nil, "a copied image file stays a normal Finder file paste")
        expect(FinderPasteImageSupport.preferredImageType(in: ["public.jpeg"])
                == "public.jpeg",
               "a non-PNG image representation can be converted")
        expect(FinderPasteImageSupport.fileName(
            for: Date(timeIntervalSince1970: 0),
            timeZone: TimeZone(secondsFromGMT: 0)!
        ) == "Pasted_Image_19700101_000000.png",
               "pasted images receive the stable timestamped PNG name")
    }
}
