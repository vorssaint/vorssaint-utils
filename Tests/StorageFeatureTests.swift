// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import Carbon.HIToolbox
import Combine
import CoreAudio
import CoreGraphics
import Darwin
import Foundation
import ImageIO
import VMStatisticsCompat

enum StorageFeatureTests {
    static func run(_ suite: TestSuite) {
        // MARK: A failed removal explains itself where it failed
        // A green tick above "some items couldn't be moved to the Trash" told
        // nobody that sandboxed app data needs Full Disk Access, and the note
        // offering the permission only ever appeared before an app was picked.
        suite.expect(UninstallerSupport.doneSymbol(hasLeftovers: false) == "checkmark.circle.fill",
               "a removal that took everything ends on a tick")
        suite.expect(UninstallerSupport.doneSymbol(hasLeftovers: true)
                != UninstallerSupport.doneSymbol(hasLeftovers: false),
               "a removal that left something behind does not end on the same mark")
        // The permission note has to be true when it appears: only sandboxed
        // container data is gated by Full Disk Access, so a failure list made
        // of ownership or identity refusals must not offer it.
        let fdaHome = "/Users/someone"
        suite.expect(UninstallerSupport.failureNeedsFullDiskAccess(
                   paths: [fdaHome + "/Library/Containers/com.vendor.editor"]),
               "a failed container is the case Full Disk Access would have changed")
        suite.expect(UninstallerSupport.failureNeedsFullDiskAccess(
                   paths: [fdaHome + "/Library/Application Support/Editor",
                           fdaHome + "/Library/Group Containers/group.com.vendor.editor",
                           fdaHome + "/Library/Caches/com.vendor.editor"]),
               "one failed container among others is enough to offer the permission")
        suite.expect(UninstallerSupport.failureNeedsFullDiskAccess(
                   paths: [fdaHome + "/Library/Application Scripts/com.vendor.editor"]),
               "application scripts sit behind the same permission as containers")
        suite.expect(!UninstallerSupport.failureNeedsFullDiskAccess(
                   paths: ["/Applications/Editor.app",
                           fdaHome + "/Library/Application Support/Editor",
                           fdaHome + "/Library/Preferences/com.vendor.editor.plist",
                           "/Library/LaunchAgents/com.vendor.editor.plist"]),
               "failures outside containers never offer a permission that would not help")
        suite.expect(!UninstallerSupport.failureNeedsFullDiskAccess(paths: []),
               "no failure, no permission note")
        // Both done states have to route through that decision and name what
        // survived; neither may spell a tick of its own.
        for path in ["Sources/Vorssaint/UI/Uninstall/UninstallerView.swift",
                     "Sources/Vorssaint/UI/MenuPanel/PanelUninstallerView.swift"] {
            let source = (try? String(contentsOfFile: path, encoding: .utf8)) ?? ""
            suite.expect(source.contains("UninstallFailureNote(items:"),
                   "\(path) names what the removal left behind")
            suite.expect(!source.contains("\"checkmark.circle.fill\""),
                   "\(path) takes its done symbol from UninstallerSupport")
        }
        let sharedUISource = (try? String(contentsOfFile: "Sources/Vorssaint/UI/SharedUI.swift",
                                          encoding: .utf8)) ?? ""
        suite.expect(sharedUISource.contains("uninstallerFailedNeedsFDA"),
               "the failure note explains the permission the removal needed")

        // MARK: Private file store

        let privateRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("PrivateFileStoreTests-\(UUID().uuidString)", isDirectory: true)
        let privateLeaf = privateRoot.appendingPathComponent("Sub", isDirectory: true)
        suite.expect(PrivateFileStore.directoriesToTighten(from: privateLeaf, container: privateRoot)
                .map(\.lastPathComponent) == ["Sub", privateRoot.lastPathComponent],
               "tightening walks a container path up to the container itself")
        suite.expect(PrivateFileStore.directoriesToTighten(from: privateRoot, container: privateRoot)
                .map(\.lastPathComponent) == [privateRoot.lastPathComponent],
               "the container is tightened without climbing past it")
        suite.expect(PrivateFileStore.directoriesToTighten(
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
        suite.expect(privateCreated && privateMode(privateLeaf) == 0o700,
               "a created store directory is owner-only")
        suite.expect(privateWritten
                && privateMode(privateFile) == 0o600
                && (try? Data(contentsOf: privateFile)) == Data([0x7B, 0x7D]),
               "a stored file lands complete and owner-only")
        suite.expect(privateMode(privateRoot) == 0o700,
               "a container an earlier version left world readable is tightened on the next write")
        try? FileManager.default.removeItem(at: privateRoot)

    }
}
