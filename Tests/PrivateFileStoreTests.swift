// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

enum PrivateFileStoreTests {
    static func run(expect: (Bool, String) -> Void) {
        // MARK: Private file store

        let privateRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("PrivateFileStoreTests-\(UUID().uuidString)", isDirectory: true)
        let privateLeaf = privateRoot.appendingPathComponent("Sub", isDirectory: true)
        expect(PrivateFileStore.directoriesToTighten(from: privateLeaf, container: privateRoot)
                .map(\.lastPathComponent) == ["Sub", privateRoot.lastPathComponent],
               "tightening walks a container path up to the container itself")
        expect(PrivateFileStore.directoriesToTighten(from: privateRoot, container: privateRoot)
                .map(\.lastPathComponent) == [privateRoot.lastPathComponent],
               "the container is tightened without climbing past it")
        expect(PrivateFileStore.directoriesToTighten(
                from: privateLeaf,
                container: FileManager.default.temporaryDirectory
                    .appendingPathComponent(privateRoot.lastPathComponent + "-other",
                                            isDirectory: true)).count == 1,
               "a path outside the container tightens only itself, never a sibling's parents")

        // A container an earlier version created world readable, and a file
        // written into it, both end up owner-only.
        try? FileManager.default.createDirectory(at: privateRoot,
                                                 withIntermediateDirectories: true,
                                                 attributes: [.posixPermissions: 0o755])
        let privateFile = privateLeaf.appendingPathComponent("records.json")
        let privateCreated = PrivateFileStore.createDirectory(at: privateLeaf,
                                                              container: privateRoot)
        let privateWritten = PrivateFileStore.write(Data([0x7B, 0x7D]), to: privateFile)
        func privateMode(_ url: URL) -> Int? {
            (try? FileManager.default.attributesOfItem(atPath: url.path))?[.posixPermissions]
                .flatMap { ($0 as? NSNumber)?.intValue }
        }
        expect(privateCreated && privateMode(privateLeaf) == 0o700,
               "a created store directory is owner-only")
        expect(privateWritten
                && privateMode(privateFile) == 0o600
                && (try? Data(contentsOf: privateFile)) == Data([0x7B, 0x7D]),
               "a stored file lands complete and owner-only")
        expect(privateMode(privateRoot) == 0o700,
               "a container an earlier version left world readable is tightened on the next write")
        try? FileManager.default.removeItem(at: privateRoot)
    }
}
