// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

enum FinderFileActionsTests {
    static func run(_ suite: TestSuite) {
        suite.run("Finder file actions") {
            creationContracts(suite)
            collisionPreservesSources(suite)
            inspectionContracts(suite)
            folderAndRenameContracts(suite)
            aliasAndAttributeContracts(suite)
        }
    }

    private static func creationContracts(_ suite: TestSuite) {
        withTemporaryDirectory(suite, label: "finder-actions-create") { root in
            let original = try FinderFileActions.createFile(in: root, named: "Résumé.md",
                                                            contents: Data("original".utf8))
            let next = try FinderFileActions.createFile(in: root, named: "Résumé.md",
                                                        contents: Data("second".utf8),
                                                        collisionPolicy: .makeUnique)
            suite.expect(original.lastPathComponent == "Résumé.md"
                         && next.lastPathComponent == "Résumé 2.md",
                         "unique creation preserves Unicode and chooses the next unused name")
            let originalBytes = try Data(contentsOf: original)
            let nextBytes = try Data(contentsOf: next)
            suite.expect(originalBytes == Data("original".utf8) && nextBytes == Data("second".utf8),
                         "collision-safe creation leaves both file contents intact")

            var rejected = false
            do { _ = try FinderFileActions.createFile(in: root, named: "../escape") }
            catch FinderFileActionError.invalidName { rejected = true }
            suite.expect(rejected && !FileManager.default.fileExists(atPath: root.deletingLastPathComponent()
                .appendingPathComponent("escape").path),
                "traversal names fail before creating a file outside the selected folder")
        }
    }

    private static func collisionPreservesSources(_ suite: TestSuite) {
        withTemporaryDirectory(suite, label: "finder-actions-collision") { root in
            let source = try FinderFileActions.createFile(in: root, named: "source.txt",
                                                          contents: Data("source".utf8))
            let destination = try FinderFileActions.createFile(in: root, named: "destination.txt",
                                                               contents: Data("keep me".utf8))
            var copyFailed = false
            do { _ = try FinderFileActions.copyItem(at: source, to: destination) }
            catch FinderFileActionError.destinationExists { copyFailed = true }
            suite.expect(copyFailed, "copy reports a destination collision")

            var moveFailed = false
            do { _ = try FinderFileActions.moveItem(at: source, to: destination) }
            catch FinderFileActionError.destinationExists { moveFailed = true }
            suite.expect(moveFailed, "move reports a destination collision")
            let sourceBytes = try Data(contentsOf: source)
            let destinationBytes = try Data(contentsOf: destination)
            suite.expect(sourceBytes == Data("source".utf8) && destinationBytes == Data("keep me".utf8),
                         "failed copy and move preserve both source and destination bytes")

            let copied = try FinderFileActions.copyItem(at: source, to: root.appendingPathComponent("copy.txt"))
            suite.expect(FileManager.default.fileExists(atPath: source.path)
                         && (try? Data(contentsOf: copied)) == Data("source".utf8),
                         "successful copy creates a distinct destination and keeps the source")
            let moved = try FinderFileActions.moveItem(at: source, to: root.appendingPathComponent("moved.txt"))
            suite.expect(!FileManager.default.fileExists(atPath: source.path)
                         && (try? Data(contentsOf: moved)) == Data("source".utf8),
                         "successful move relocates the source contents")
        }
    }

    private static func inspectionContracts(_ suite: TestSuite) {
        withTemporaryDirectory(suite, label: "finder-actions-inspection") { root in
            let file = try FinderFileActions.createFile(in: root, named: "café [draft].txt",
                                                        contents: Data("hello".utf8))
            let link = root.appendingPathComponent("alias-to-file")
            try FileManager.default.createSymbolicLink(at: link, withDestinationURL: file)

            let tree = try FinderFileActions.fileTree(at: root)
            suite.expect(tree.entries.map(\.name).contains("café [draft].txt")
                         && tree.entries.first(where: { $0.name == "alias-to-file" })?.kind == .symbolicLink,
                         "tree inspection reports Unicode files and symbolic links without following them")
            let folderSize = try FinderFileActions.size(of: root)
            let fileSize = try FinderFileActions.size(of: file)
            suite.expect(folderSize == 5 && fileSize == 5,
                         "folder and file size count file bytes and ignore symbolic-link targets")
            let digest = try FinderFileActions.sha256(of: file)
            suite.expect(digest == "2cf24dba5fb0a30e26e83b2ac5b9e29e1b161e5c1fa7425e73043362938b9824",
                         "streaming SHA-256 matches the known digest for hello")
            suite.expect(FinderFileActions.name(of: file) == "café [draft].txt"
                         && FinderFileActions.path(of: file) == file.standardizedFileURL.path
                         && FinderFileActions.markdownLink(to: file).contains("\\[draft\\]"),
                         "path, name and Markdown formatting preserve the file's Unicode name safely")

            var symlinkHashRejected = false
            do { _ = try FinderFileActions.sha256(of: link) }
            catch FinderFileActionError.unsupported { symlinkHashRejected = true }
            suite.expect(symlinkHashRejected, "hashing a symbolic link is rejected instead of reading its target")
        }
    }

    private static func folderAndRenameContracts(_ suite: TestSuite) {
        withTemporaryDirectory(suite, label: "finder-actions-folders") { root in
            let first = try FinderFileActions.createFile(in: root, named: "first.txt",
                                                         contents: Data("one".utf8))
            let grouped = try FinderFileActions.group([first], in: root, named: "Grouped")
            suite.expect(FileManager.default.fileExists(atPath: grouped.appendingPathComponent("first.txt").path)
                         && !FileManager.default.fileExists(atPath: first.path),
                         "group moves selected files into a new folder")

            let stack = try FinderFileActions.createFolder(in: root, named: "Stack")
            let inner = try FinderFileActions.createFile(in: stack, named: "inner.txt",
                                                         contents: Data("two".utf8))
            let flattened = try FinderFileActions.flattenContents(of: stack)
            suite.expect(flattened == [root.appendingPathComponent("inner.txt")]
                         && FileManager.default.fileExists(atPath: flattened[0].path)
                         && !FileManager.default.fileExists(atPath: stack.path)
                         && !FileManager.default.fileExists(atPath: inner.path),
                         "flatten moves direct children to the parent and removes the empty source folder")

            let planned = try FinderFileActions.planRenames([
                .init(source: grouped.appendingPathComponent("first.txt"), newName: "renamed.txt")
            ])
            suite.expect(planned.renames.first?.destination.lastPathComponent == "renamed.txt"
                         && FileManager.default.fileExists(atPath: grouped.appendingPathComponent("first.txt").path),
                         "batch rename planning returns a destination without changing the source")

            let blocker = try FinderFileActions.createFile(in: grouped, named: "occupied.txt")
            var collisionRejected = false
            do {
                _ = try FinderFileActions.planRenames([
                    .init(source: grouped.appendingPathComponent("first.txt"), newName: blocker.lastPathComponent)
                ])
            } catch FinderFileActionError.destinationExists { collisionRejected = true }
            suite.expect(collisionRejected, "rename planning rejects a destination owned by an outside source")

            let conflictFolder = try FinderFileActions.createFolder(in: root, named: "Conflict")
            let conflictChild = try FinderFileActions.createFile(in: conflictFolder, named: "blocked.txt",
                                                                 contents: Data("inside".utf8))
            let conflict = try FinderFileActions.createFile(in: root, named: "blocked.txt",
                                                            contents: Data("outside".utf8))
            var flattenRejected = false
            do { _ = try FinderFileActions.flattenContents(of: conflictFolder) }
            catch FinderFileActionError.destinationExists { flattenRejected = true }
            let conflictChildStillExists = FileManager.default.fileExists(atPath: conflictChild.path)
            let conflictBytes = try Data(contentsOf: conflict)
            suite.expect(flattenRejected && conflictChildStillExists
                         && conflictBytes == Data("outside".utf8),
                         "flatten rejects ambiguous destinations before moving or replacing any files")

            let parent = try FinderFileActions.createFolder(in: root, named: "Parent")
            let child = try FinderFileActions.createFolder(in: parent, named: "Child")
            var descendantMoveRejected = false
            do { _ = try FinderFileActions.moveItem(at: parent, to: child.appendingPathComponent("Parent")) }
            catch FinderFileActionError.invalidRequest { descendantMoveRejected = true }
            suite.expect(descendantMoveRejected && FileManager.default.fileExists(atPath: child.path),
                         "moving a folder into its descendant is rejected without changing the tree")
        }
    }

    private static func aliasAndAttributeContracts(_ suite: TestSuite) {
        withTemporaryDirectory(suite, label: "finder-actions-alias") { root in
            let target = try FinderFileActions.createFile(in: root, named: "target.txt",
                                                          contents: Data("target".utf8))
            let alias = try FinderFileActions.createAlias(to: target, at: root.appendingPathComponent("target.alias"))
            let bookmark = try URL.bookmarkData(withContentsOf: alias)
            var stale = false
            let resolved = try URL(resolvingBookmarkData: bookmark, options: [], relativeTo: nil,
                                   bookmarkDataIsStale: &stale)
            suite.expect(resolved.standardizedFileURL == target.standardizedFileURL && !stale,
                         "created alias bookmark resolves to its original target")
            let aliasValues = try alias.resourceValues(forKeys: [.isAliasFileKey])
            suite.expect(aliasValues.isAliasFile == true, "Finder recognizes the created file as an alias")

            try FinderFileActions.setHidden(true, at: target)
            let hidden = try target.resourceValues(forKeys: [.isHiddenKey]).isHidden
            try FinderFileActions.setHidden(false, at: target)
            let unhidden = try target.resourceValues(forKeys: [.isHiddenKey]).isHidden
            suite.expect(hidden == true && unhidden == false, "hide and unhide toggle the Finder hidden attribute")

            try FinderFileActions.setLocked(true, at: target)
            try FinderFileActions.setLocked(false, at: target)
            let bytes = try Data(contentsOf: target)
            suite.expect(bytes == Data("target".utf8),
                         "lock and unlock preserve the file and restore access")
        }
    }

    private static func withTemporaryDirectory(_ suite: TestSuite,
                                               label: String,
                                               body: (URL) throws -> Void) {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(label)-\(UUID().uuidString)", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
            defer { try? FileManager.default.removeItem(at: root) }
            try body(root)
        } catch {
            suite.expect(false, "temporary file-action fixture failed: \(error.localizedDescription)")
        }
    }
}
