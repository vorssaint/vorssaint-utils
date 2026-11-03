// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// The duplicate finder's pure rules: one copy always stays, the oldest copy is
/// the default keeper, and a copy edited after the scan is never removed.
enum DuplicateFileSupportTests {
    static func run(_ suite: TestSuite) {
        suite.expect(DuplicateFileSupport.mayTick(tickedCount: 0, groupCount: 2)
                     && DuplicateFileSupport.mayTick(tickedCount: 1, groupCount: 3),
                     "a copy may be ticked while another stays unticked")
        suite.expect(!DuplicateFileSupport.mayTick(tickedCount: 1, groupCount: 2)
                     && !DuplicateFileSupport.mayTick(tickedCount: 2, groupCount: 3)
                     && !DuplicateFileSupport.mayTick(tickedCount: 0, groupCount: 1),
                     "the last remaining copy can never be ticked")

        let early = Date(timeIntervalSince1970: 1_000)
        let late = Date(timeIntervalSince1970: 2_000)
        suite.expect(DuplicateFileSupport.defaultKeepIndex(modified: [late, early, late]) == 1,
                     "the oldest copy is kept by default")
        suite.expect(DuplicateFileSupport.defaultKeepIndex(modified: [nil, late, early]) == 2
                     && DuplicateFileSupport.defaultKeepIndex(modified: [nil, nil]) == 0
                     && DuplicateFileSupport.defaultKeepIndex(modified: [early, early]) == 0,
                     "a copy with no date loses to a dated one, and ties keep the first")

        suite.expect(DuplicateFileSupport.unchanged(scannedSize: 10, scannedModified: early,
                                                    currentSize: 10, currentModified: early),
                     "an untouched copy still matches the scan")
        suite.expect(!DuplicateFileSupport.unchanged(scannedSize: 10, scannedModified: early,
                                                     currentSize: 11, currentModified: early)
                     && !DuplicateFileSupport.unchanged(scannedSize: 10, scannedModified: early,
                                                        currentSize: 10, currentModified: late)
                     && !DuplicateFileSupport.unchanged(scannedSize: 10, scannedModified: early,
                                                        currentSize: nil, currentModified: nil),
                     "a copy that changed size or date, or vanished, no longer matches")

        let home = URL(fileURLWithPath: "/Users/someone", isDirectory: true)
        func at(_ path: String) -> URL { home.appendingPathComponent(path) }
        func copy(_ path: String, _ date: Date? = nil) -> DuplicateFileSupport.Copy {
            DuplicateFileSupport.Copy(url: at(path), modified: date)
        }

        let drop = DuplicateFileSupport.placement(of: at("Dropbox/Work/a.pdf"), home: home)
        let node = DuplicateFileSupport.placement(of: at("dev/site/node_modules/lib/a.js"), home: home)
        let vm = DuplicateFileSupport.placement(of: at("Parallels/Win11.pvm/disk.hdd"), home: home)
        let dl = DuplicateFileSupport.placement(of: at("Downloads/a.pdf"), home: home)
        suite.expect(drop.risk == .synced && drop.tiedTo == "Dropbox"
                     && DuplicateFileSupport.placement(of: at("OneDrive - Acme/a.pdf"), home: home).risk == .synced
                     && DuplicateFileSupport.placement(of: at("Google Drive/a.pdf"), home: home).risk == .synced,
                     "files inside cloud folders are marked as risky because deleting syncs everywhere")
        suite.expect(node.risk == .project && node.tiedTo == "site" && vm.risk == .virtualMachine
                     && vm.tiedTo == "Parallels",
                     "dependency folders and virtual machine folders are marked risky and name what they belong to")
        suite.expect(dl.isTemporary && dl.risk == nil && dl.tiedTo == "Downloads"
                     && DuplicateFileSupport.placement(of: at("Documents/a.pdf"), home: home).isOrganized
                     && DuplicateFileSupport.placement(of: at("Projects/a.pdf"), home: home).risk == nil
                     && DuplicateFileSupport.placement(of: URL(fileURLWithPath: "/Volumes/x/a.pdf"), home: home).tiedTo.isEmpty,
                     "Downloads is temporary, Documents is organised, and outside home is unclassified")
        suite.expect(DuplicateFileSupport.placement(of: at("Dropbox (Personal)/a.pdf"), home: home).risk == .synced
                     && DuplicateFileSupport.placement(of: at("Box Sync/a.pdf"), home: home).risk == .synced
                     && DuplicateFileSupport.placement(of: at("Boxes/a.pdf"), home: home).risk == nil
                     && DuplicateFileSupport.placement(of: at("work/app/venv/lib/x.so"), home: home).risk == .project
                     && DuplicateFileSupport.placement(of: at("Disks/old.VDI"), home: home).risk == .virtualMachine,
                     "cloud folder variants, virtual environments and loose VM disks are risky, lookalikes are not")
        suite.expect(DuplicateFileSupport.looksLikeCopy("report copy.pdf")
                     && DuplicateFileSupport.looksLikeCopy("Report Copy 2.pdf")
                     && DuplicateFileSupport.looksLikeCopy("photo (1).jpg")
                     && !DuplicateFileSupport.looksLikeCopy("photocopy.jpg")
                     && !DuplicateFileSupport.looksLikeCopy("report.pdf"),
                     "names made by duplicating are recognised without catching ordinary words")

        let tidy = copy("Documents/report.pdf", late)
        let messy = copy("Downloads/report (1).pdf", early)
        suite.expect(DuplicateFileSupport.bestIndex(of: [messy, tidy], home: home) == 1
                     && DuplicateFileSupport.bestIndex(of: [tidy, messy], home: home) == 0,
                     "the best copy is the tidy one in an organised folder, not the oldest download")
        suite.expect(DuplicateFileSupport.bestIndex(of: [copy("a/x.bin", late), copy("b/x.bin", early)], home: home) == 1
                     && DuplicateFileSupport.newestIndex(of: [copy("a", early), copy("b", late), copy("c", nil)]) == 1,
                     "equal copies fall back to the oldest, and newest picks the latest date")

        let set = [tidy, messy, copy("Desktop/report.pdf", late), copy("Dropbox/report.pdf", late)]
        suite.expect(DuplicateFileSupport.indicesToTick(.keepBest, copies: set, home: home) == [0, 1, 2],
                     "the copy in a cloud folder is the one that stays, because it is the risky one to touch")
        suite.expect(DuplicateFileSupport.indicesToTick(
                        .keepBest, copies: [copy("Dropbox/a.bin", early), copy("OneDrive/a.bin", late)], home: home).isEmpty,
                     "a risky copy that is not the keeper is still never ticked for the person")
        suite.expect(DuplicateFileSupport.indicesToTick(.keep(1), copies: set, home: home) == [0, 2],
                     "keeping one named copy ticks the others, still skipping risky ones")
        suite.expect(DuplicateFileSupport.indicesToTick(.temporaryOnly, copies: set, home: home) == [1, 2],
                     "temporary only ticks the Downloads and Desktop copies")
        suite.expect(DuplicateFileSupport.indicesToTick(.temporaryOnly,
                                                        copies: [copy("Downloads/a"), copy("Desktop/a")], home: home).isEmpty
                     && DuplicateFileSupport.indicesToTick(.keepBest, copies: [copy("a/x")], home: home).isEmpty,
                     "when every copy is temporary, or there is only one, nothing is ticked")

        // Two names for one file are one identity; a separate file is another.
        let fm = FileManager.default
        let box = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("vorssaint-identity-\(UUID().uuidString)", isDirectory: true)
        try? fm.createDirectory(at: box, withIntermediateDirectories: true)
        let first = box.appendingPathComponent("a.bin"), linked = box.appendingPathComponent("b.bin")
        let other = box.appendingPathComponent("c.bin")
        try? Data("same".utf8).write(to: first)
        try? Data("same".utf8).write(to: other)
        try? fm.linkItem(at: first, to: linked)
        func identity(_ url: URL) -> DuplicateFileSupport.FileIdentity? {
            let keys: Set<URLResourceKey> = [.fileResourceIdentifierKey, .volumeIdentifierKey]
            return (try? url.resourceValues(forKeys: keys)).flatMap { DuplicateFileSupport.identity(of: $0) }
        }
        suite.expect(identity(first) != nil && identity(first) == identity(linked) && identity(first) != identity(other),
                     "hard links share one file identity, and a separate file with equal content does not")
        try? fm.removeItem(at: box)

        struct G { let size: Int64; let copies: Int }
        let ranked = DuplicateFileSupport.ranked([G(size: 10, copies: 2), G(size: 5, copies: 10), G(size: 100, copies: 1)],
                                                 size: { $0.size }, copies: { $0.copies })
        suite.expect(ranked.map(\.size) == [5, 10, 100],
                     "groups are ordered by space that removing the extras would free")
    }
}
