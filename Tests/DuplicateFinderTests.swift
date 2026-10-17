// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Darwin
import Foundation

enum DuplicateFinderTests {
    typealias Support = DuplicateFinderSupport
    static func run(_ suite: TestSuite) {
        let fm = FileManager.default
        let base = URL(fileURLWithPath: "/private/tmp").appendingPathComponent("duplicate-finder-tests-\(UUID().uuidString)")
        defer { try? fm.removeItem(at: base) }
        do {
            try fm.createDirectory(at: base, withIntermediateDirectories: true)
            func folder(_ name: String) throws -> URL {
                let url = base.appendingPathComponent(name)
                try fm.createDirectory(at: url, withIntermediateDirectories: true); return url
            }
            func file(_ root: URL, _ name: String, _ bytes: Data = Data("same".utf8)) throws -> URL {
                let url = root.appendingPathComponent(name); try bytes.write(to: url); return url
            }
            func scan(_ roots: [URL]) -> Support.Report { Support.scan(roots: roots, cancellation: .init()) }
            let a = try folder("one"), b = try folder("two"), other = try folder("one-extra")
            let first = try file(a, "photo.jpg"), second = try file(b, "document.bin")
            _ = try file(a, "different.jpg", Data("diff".utf8))
            var report = scan([a, b])
            suite.expect(report.groups.count == 1 && Set(report.groups[0].files.map(\.url)) == [first, second], "exact contents match across names, extensions and selected roots")
            suite.expect(report.groups.first?.duplicateBytes == 4, "logical duplicate size counts redundant copies only")
            suite.expect(!Support.validSelection([], groups: report.groups), "nothing is selected by default")
            suite.expect(Support.validSelection([first], groups: report.groups), "one selected copy is eligible while another remains")
            suite.expect(!Support.validSelection([first, second], groups: report.groups), "selection cannot remove every copy")
            suite.expect(!Support.validSelection([other], groups: report.groups), "unknown paths cannot become cleanup targets")
            suite.expect(Support.normalizedRoots([a, a, a.appendingPathComponent("sub"), other]).map(\.path) == [a.path, other.path], "overlapping roots are collapsed with component boundaries")
            let rootLink = base.appendingPathComponent("root-link")
            try fm.createSymbolicLink(at: rootLink, withDestinationURL: a)
            suite.expect(Support.normalizedRoots([rootLink, a]).map(\.path) == [a.path], "chosen root links are resolved once and deduplicated")
            let zeroA = try file(a, "zero", Data()), zeroB = try file(b, "empty", Data())
            report = scan([a, b])
            suite.expect(report.groups.contains { Set($0.files.map(\.url)) == [zeroA, zeroB] }, "empty ordinary files compare exactly")
            let large = Data(repeating: 42, count: Support.chunkSize * 3 + 17)
            let largeA = try file(a, "large-a", large), largeB = try file(b, "large-b", large)
            report = scan([a, b])
            suite.expect(report.groups.first?.files.contains { $0.url == largeA } == true, "largest logical duplicate group sorts first")
            suite.expect(try Support.equal(Support.snapshot(largeA)!, Support.snapshot(largeB)!, cancellation: .init()), "multi-chunk files compare without whole-file allocation")
            let readRoot = try folder("mutating-read")
            let readURL = try file(readRoot, "large", large)
            let readSnapshot = Support.snapshot(readURL)!
            var editedDuringRead = false
            do {
                _ = try Support.digest(readSnapshot, cancellation: .init()) {
                    if !editedDuringRead {
                        editedDuringRead = true
                        let writer = try FileHandle(forWritingTo: readURL)
                        try writer.seekToEnd(); try writer.write(contentsOf: Data([99])); try writer.close()
                    }
                }
                suite.expect(false, "file changing during a streaming read must be rejected")
            } catch {
                suite.expect(editedDuringRead && (error as? Support.Failure) != nil, "file changing during a streaming read is rejected")
            }
            let readToken = Support.Cancellation()
            do {
                _ = try Support.digest(Support.snapshot(readURL)!, cancellation: readToken) { readToken.cancel() }
                suite.expect(false, "streaming read must honor cancellation between chunks")
            } catch {
                suite.expect(readToken.isCancelled, "streaming read honors cancellation between chunks")
            }
            let collision = Support.scan(roots: [a, b], cancellation: .init(), hash: { _, _ in Data([0]) })
            suite.expect(collision.groups.allSatisfy { group in group.files.allSatisfy { candidate in
                (try? Support.equal(candidate, group.files[0], cancellation: .init())) == true
            } }, "injected hash collisions never substitute for byte equality")
            suite.expect(collision.groups.count == 3, "hash-collision buckets partition different sizes and contents")

            let exclusions = try folder("exclusions")
            _ = try file(exclusions, "visible")
            _ = try file(exclusions, ".hidden")
            let hiddenDir = exclusions.appendingPathComponent(".hidden-dir")
            try fm.createDirectory(at: hiddenDir, withIntermediateDirectories: true)
            _ = try file(hiddenDir, "inside")
            let package = exclusions.appendingPathComponent("Example.app")
            try fm.createDirectory(at: package, withIntermediateDirectories: true)
            _ = try file(package, "inside")
            let trashDir = exclusions.appendingPathComponent(".Trash")
            try fm.createDirectory(at: trashDir, withIntermediateDirectories: true)
            _ = try file(trashDir, "inside")
            let link = exclusions.appendingPathComponent("link")
            try fm.createSymbolicLink(at: link, withDestinationURL: first)
            let dangling = exclusions.appendingPathComponent("dangling")
            try fm.createSymbolicLink(at: dangling, withDestinationURL: base.appendingPathComponent("missing"))
            let hardA = try file(exclusions, "hard-a"), hardB = exclusions.appendingPathComponent("hard-b")
            try fm.linkItem(at: hardA, to: hardB)
            let fork = try file(exclusions, "fork")
            let forkData = Data("resource".utf8)
            let forkResult = forkData.withUnsafeBytes { bytes in
                fork.withUnsafeFileSystemRepresentation { path in setxattr(path!, "com.apple.ResourceFork", bytes.baseAddress, bytes.count, 0, XATTR_NOFOLLOW) }
            }
            suite.expect(forkResult == 0, "fixture contains a real resource fork")
            let alias = exclusions.appendingPathComponent("alias")
            let bookmark = try first.bookmarkData(options: .suitableForBookmarkFile)
            try URL.writeBookmarkData(bookmark, to: alias)
            let denied = try file(exclusions, "denied")
            try fm.setAttributes([.posixPermissions: 0], ofItemAtPath: denied.path)
            defer { try? fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: denied.path) }
            let packageReport = scan([package, b])
            suite.expect(!packageReport.groups.flatMap(\.files).contains { Support.contains($0.url, in: package) }, "explicit package roots do not expose package contents")
            let innerPackage = package.appendingPathComponent("nested")
            try fm.createDirectory(at: innerPackage, withIntermediateDirectories: true)
            _ = try file(innerPackage, "copy")
            suite.expect(scan([innerPackage, b]).issues.contains { $0.reason == .package }, "selecting a folder inside a package cannot bypass its exclusion")
            suite.expect(scan([trashDir, b]).issues.contains { $0.reason == .trash }, "explicit Trash roots remain excluded")
            let excludedReport = scan([exclusions, b])
            for reason in [Support.Reason.hidden, .package, .trash, .symbolicLink, .alias, .hardLink, .resourceFork] {
                suite.expect(excludedReport.issues.contains { $0.reason == reason }, "scan reports exclusion: \(reason)")
            }
            suite.expect(excludedReport.groups.flatMap(\.files).allSatisfy { ![$0.url].contains(link) && $0.url != dangling && $0.url != hardA && $0.url != hardB && $0.url != fork && $0.url != alias && $0.url != denied }, "excluded or unreadable files never reach actionable results")
            suite.expect(excludedReport.issues.contains { $0.url == denied && $0.reason == .inaccessible }, "unreadable content is reported as inaccessible without a removal target")
            let temporary = fm.temporaryDirectory.appendingPathComponent("duplicate-finder-canonical-\(UUID())")
            try fm.createDirectory(at: temporary, withIntermediateDirectories: true)
            defer { try? fm.removeItem(at: temporary) }
            _ = try file(temporary, "first"); _ = try file(temporary, "second")
            suite.expect(scan([temporary]).groups.count == 1, "Foundation's abbreviated temporary paths resolve to real directory ancestry")
            var dataless = Support.info(first)!
            dataless.st_flags |= UInt32(SF_DATALESS)
            suite.expect(Support.exclusion(first, info: dataless) == .cloud, "dataless detection rejects content before any read")
            let unavailable = scan([base.appendingPathComponent("unmounted"), a, b])
            suite.expect(unavailable.issues.contains { $0.reason == .inaccessible } && !unavailable.groups.isEmpty, "unavailable roots do not discard other readable roots")

            let cancelled = Support.Cancellation(); cancelled.cancel()
            suite.expect(Support.scan(roots: [a, b], cancellation: cancelled).cancelled, "cancelled scans are explicitly marked")
            suite.expect(Support.scan(roots: [a, b], cancellation: cancelled).groups.isEmpty, "cancelled scans have no actionable results")
            let midway = Support.Cancellation()
            let midReport = Support.scan(roots: [a, b], cancellation: midway, hash: { candidate, token in
                let digest = try Support.digest(candidate, cancellation: token); token.cancel(); return digest
            })
            suite.expect(midReport.cancelled && midReport.groups.isEmpty, "cancellation during comparison discards incomplete groups")
            let changeRoot = try folder("change")
            let changeA = try file(changeRoot, "a"), changeB = try file(changeRoot, "b")
            let changed = Support.scan(roots: [changeRoot], cancellation: .init(), hash: { candidate, token in
                let digest = try Support.digest(candidate, cancellation: token)
                if candidate.url == changeA { try Data("edit".utf8).write(to: changeA) }
                return digest
            })
            suite.expect(changed.groups.isEmpty, "files edited after hashing cannot appear as duplicates")
            let before = Support.snapshot(changeB)!
            try fm.removeItem(at: changeB); _ = try file(changeRoot, "b")
            suite.expect(!Support.stillMatches(before), "same-path replacements invalidate a file snapshot")
            let parentRoot = try folder("ancestry")
            let nested = parentRoot.appendingPathComponent("nested")
            try fm.createDirectory(at: nested, withIntermediateDirectories: true)
            let nestedFile = try file(nested, "a"), nestedSnapshot = Support.snapshot(nestedFile)!
            let movedDir = parentRoot.appendingPathComponent("moved")
            try fm.moveItem(at: nested, to: movedDir)
            try fm.createSymbolicLink(at: nested, withDestinationURL: movedDir)
            suite.expect(!Support.stillMatches(nestedSnapshot), "replacing a parent with a symlink blocks stale operations")

            func cleanupFixture(_ name: String) throws -> (Support.Group, URL, URL, URL) {
                let root = try folder(name)
                let x = try file(root, "a"), y = try file(root, "b"), z = try file(root, "keeper")
                return (scan([root]).groups[0], x, y, z)
            }
            let (group, x, y, keeper) = try cleanupFixture("cleanup")
            var calls: [URL] = []
            let outcomes = Support.trash(selection: [x, y], groups: [group], cancellation: .init()) { url in
                calls.append(url)
                if url == x { throw CocoaError(.fileWriteNoPermission) }
                try fm.moveItem(at: url, to: base.appendingPathComponent("fake-trash-\(UUID().uuidString)"))
            }
            suite.expect(calls == [x, y] && outcomes.count == 2 && !outcomes[0].moved && outcomes[1].moved, "partial Trash failure reports each outcome and continues safely")
            suite.expect(fm.fileExists(atPath: keeper.path) && fm.fileExists(atPath: x.path), "keeper and failed file are preserved")
            let (invalid, ix, iy, ik) = try cleanupFixture("invalid-selection")
            calls = []
            suite.expect(Support.trash(selection: [ix, iy, ik], groups: [invalid], cancellation: .init(), move: { calls.append($0) }).isEmpty && calls.isEmpty, "invalid full-group selection never invokes Trash")
            let (stale, sx, sy, sk) = try cleanupFixture("stale-keeper")
            try Data("edit".utf8).write(to: sk)
            calls = []
            let staleOutcomes = Support.trash(selection: [sx, sy], groups: [stale], cancellation: .init(), move: { calls.append($0) })
            suite.expect(calls.isEmpty && staleOutcomes.allSatisfy { $0.reason == .keepCopy }, "changed keeper blocks the entire selected group")
            let (replaced, rx, ry, _) = try cleanupFixture("replaced")
            try fm.removeItem(at: rx); _ = try file(rx.deletingLastPathComponent(), "a")
            calls = []
            let replacedOutcomes = Support.trash(selection: [rx, ry], groups: [replaced], cancellation: .init(), move: { calls.append($0) })
            suite.expect(!calls.contains(rx) && replacedOutcomes.first?.reason == .changed, "replaced target cannot be moved based on prior contents")
            let (stop, tx, ty, _) = try cleanupFixture("cancel-trash")
            let token = Support.Cancellation(); calls = []
            let stopped = Support.trash(selection: [tx, ty], groups: [stop], cancellation: token) { calls.append($0); token.cancel() }
            suite.expect(calls == [tx] && stopped.last?.reason == .cancelled, "batch cancellation stops subsequent moves")
            let (vanish, vx, vy, vk) = try cleanupFixture("vanishing-keeper")
            calls = []
            let lost = Support.trash(selection: [vx, vy], groups: [vanish], cancellation: .init()) { url in
                calls.append(url); try fm.removeItem(at: vk)
            }
            suite.expect(calls == [vx] && lost.last?.reason == .keepCopy, "keeper loss after a move blocks the remaining group")
            suite.expect(!AppFeature.duplicateFinder.installedByDefault && AppFeature.duplicateFinder.group == .clipboardFiles, "finder is an opt-in file feature")
            suite.expect(AppFeature.duplicateFinder.permissions == [.filesAndFolders] && !AppFeature.duplicateFinder.monitorsPermissionChanges, "folder access is contextual without background permission polling")
            suite.expect(!FeatureVisibilitySupport.isPageVisible(.duplicateFinder, isAvailable: { _ in false }), "uninstalled finder has no Settings page")
            suite.expect(AppFeature.duplicateFinder.settingsDestination.page == .duplicateFinder, "search destination routes to the finder settings page")
            let key = AppFeature.duplicateFinder.availabilityKey
            let savedAvailability = UserDefaults.standard.object(forKey: key)
            UserDefaults.standard.set(true, forKey: key)
            defer {
                if let savedAvailability { UserDefaults.standard.set(savedAvailability, forKey: key) }
                else { UserDefaults.standard.removeObject(forKey: key) }
            }
            func waitForSession(_ session: DuplicateFinderSession) {
                let deadline = Date().addingTimeInterval(5)
                while session.busy && Date() < deadline { RunLoop.current.run(until: Date().addingTimeInterval(0.01)) }
            }
            let session = DuplicateFinderSession()
            session.setRoots([a, b]); session.scan(); waitForSession(session)
            suite.expect(!session.busy && session.report?.groups.isEmpty == false && session.selection.isEmpty, "production session publishes results with no automatic selections")
            if let group = session.report?.groups.first {
                let target = group.files[0]
                session.select(target, enabled: true); session.review()
                suite.expect(session.confirmation && session.canTrash, "review opens only for a valid manual selection")
                session.dismissReview()
                suite.expect(!session.confirmation && session.outcomes.isEmpty && Support.stillMatches(target), "cancelling confirmation does not touch files")
                session.trashConfirmed()
                suite.expect(!session.busy && Support.stillMatches(target), "unconfirmed cleanup is refused")
                session.setRoots([a])
                suite.expect(session.report == nil && session.selection.isEmpty, "changing folders invalidates old results and selections")
            }
            session.setRoots([a, b]); session.scan(); session.close(); waitForSession(session)
            suite.expect(session.roots.isEmpty && session.report == nil && session.preview == nil && session.selection.isEmpty, "closing during work releases folders and discards late results")
            session.setRoots([a]); session.scan()
            suite.expect(session.roots.isEmpty && !session.busy, "closed session cannot restart work")
            let absent = DuplicateFinderSession()
            UserDefaults.standard.set(false, forKey: key)
            absent.setRoots([a]); absent.scan(); absent.review()
            suite.expect(absent.roots.isEmpty && !absent.busy && !absent.confirmation, "uninstalled feature refuses folder access, scans and review")
            absent.close()
            for language in AppLanguage.allCases {
                let text = FeatureStrings.duplicateFinder(language)
                let values = Mirror(reflecting: text).children.compactMap { $0.value as? String }
                suite.expect(values.count == 39 && values.allSatisfy { !$0.isEmpty }, "finder strings cover every field in \(language)")
                suite.expect(Support.Reason.allCases.allSatisfy { !text.reason($0).isEmpty }, "skip and operation reasons are translated for \(language)")
            }
        } catch { suite.expect(false, "duplicate finder fixture error: \(error)") }
    }
}
