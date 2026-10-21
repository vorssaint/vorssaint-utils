// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

enum FinderBatchToolsTests {
    static func run(_ suite: TestSuite) {
        suite.run("Finder search and filename repair") {
            let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            do {
                try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
                defer { try? FileManager.default.removeItem(at: root) }
                let report = try FinderFileActions.createFile(in: root, named: "Relatório.txt")
                let nested = try FinderFileActions.createFolder(in: root, named: "Nested")
                try FileManager.default.createSymbolicLink(at: nested.appendingPathComponent("loop"), withDestinationURL: root)
                let found = try FinderSearchTools.search(in: [root, nested], query: "relatorio", cancellation: FinderToolsCancellation())
                suite.expect(found.count == 1 && found[0].resolvingSymlinksInPath().path.precomposedStringWithCanonicalMapping == report.resolvingSymlinksInPath().path.precomposedStringWithCanonicalMapping, "filename search ignores accents, avoids symlink loops and deduplicates overlapping roots: \(found.map(\.path))")
                let garbled = try FinderFileActions.createFile(in: root, named: "cafÃ©.txt", contents: Data("original".utf8))
                let changes = try FinderSearchTools.repairedNames([garbled], encoding: .windowsCP1252)
                suite.expect(changes.first?.newName == "café.txt" && FileManager.default.fileExists(atPath: garbled.path),
                             "encoding repair provides a lossless preview without modifying the source")
                let plan = try FinderFileActions.planRenames(changes)
                let repaired = try FinderBatchTools.rename(plan, cancellation: FinderToolsCancellation())
                let bytes = try Data(contentsOf: repaired[0])
                suite.expect(bytes == Data("original".utf8), "confirmed encoding repair preserves file contents")
                do {
                    _ = try FinderSearchTools.repairedNames([report], encoding: .windowsCP1252)
                    suite.expect(false, "an already-correct accented filename is not valid UTF-8 under this repair")
                } catch { suite.expect(FileManager.default.fileExists(atPath: report.path), "invalid repair leaves an existing name intact") }
            } catch { suite.expect(false, "search fixture failed: \(error)") }
        }
        suite.run("Finder batch tools") {
            let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            do {
                try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
                defer { try? FileManager.default.removeItem(at: root) }
                let first = try FinderFileActions.createFile(in: root, named: "one.txt", contents: Data("one".utf8))
                let second = try FinderFileActions.createFile(in: root, named: "two.txt", contents: Data("two".utf8))
                let plan = try FinderFileActions.planRenames([.init(source: first, newName: "two.txt"),
                                                             .init(source: second, newName: "one.txt")])
                let token = FinderToolsCancellation()
                _ = try FinderBatchTools.rename(plan, cancellation: token)
                let swappedFirst = try Data(contentsOf: first)
                let swappedSecond = try Data(contentsOf: second)
                suite.expect(swappedFirst == Data("two".utf8) && swappedSecond == Data("one".utf8),
                             "two-phase rename swaps names without losing either file")
                let unusual = root.appendingPathComponent("{n}.txt")
                let names = FinderBatchTools.renameChanges([unusual], pattern: "{n}-{name}")
                suite.expect(names.first?.newName == "1-{n}.txt", "rename tokens inside a filename are literal data")
                let same = try FinderFileActions.createFile(in: root, named: "same.txt", contents: Data("one".utf8))
                try FileManager.default.createSymbolicLink(at: root.appendingPathComponent("link"), withDestinationURL: same)
                let duplicates = try FinderBatchTools.duplicates(in: [root, same], cancellation: token)
                suite.expect(duplicates.count == 1 && Set(duplicates[0]) == Set([second, same].map { $0.resolvingSymlinksInPath().standardizedFileURL }),
                             "duplicate scan compares contents and ignores links and repeated paths; got \(duplicates.map { $0.map(\.path) }) expected \([second.path, same.path])")
                let failPlan = try FinderFileActions.planRenames([.init(source: first, newName: "renamed-one"),
                                                                 .init(source: second, newName: "renamed-two")])
                try FinderFileActions.setLocked(true, at: second)
                defer { try? FinderFileActions.setLocked(false, at: second) }
                do {
                    _ = try FinderBatchTools.rename(failPlan, cancellation: token)
                    suite.expect(false, "locked source must fail renaming")
                } catch {
                    let restored = try Data(contentsOf: first)
                    suite.expect(restored == swappedFirst && FileManager.default.fileExists(atPath: second.path),
                                 "failed staging restores earlier source names")
                }
                try FinderFileActions.setLocked(false, at: second)
                token.cancel()
                do {
                    _ = try FinderBatchTools.rename(failPlan, cancellation: token)
                    suite.expect(false, "cancelled rename must not start")
                } catch is CancellationError {
                    suite.expect(FileManager.default.fileExists(atPath: first.path), "cancelled rename leaves source names intact")
                }
            } catch { suite.expect(false, "batch fixture failed: \(error)") }
        }
    }
}
