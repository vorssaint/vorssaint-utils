// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import CoreServices

/// Offers to review an app moved from an Applications folder to the local Trash.
/// Builds on the approach first proposed by ilim-cell in #3755.
final class TrashAppWatcher {
    static let shared = TrashAppWatcher()

    private let home = FileManager.default.homeDirectoryForCurrentUser
    private var stream: FSEventStreamRef?
    private var renames = UninstallerSupport.TrashRenames()

    private init() {}

    func syncWithPreferences() {
        precondition(Thread.isMainThread)
        let wanted = AppFeature.uninstaller.isAvailable
            && UserDefaults.standard.bool(forKey: DefaultsKey.uninstallerWatchesTrash)
            && Permissions.shared.fullDiskAccess
        wanted ? start() : stop()
    }

    private func start() {
        guard stream == nil else { return }
        let roots = ["/Applications", home.appendingPathComponent("Applications").path,
                     UninstallerSupport.trashURL(home: home).path]
        let flags = FSEventStreamCreateFlags(kFSEventStreamCreateFlagFileEvents
            | kFSEventStreamCreateFlagUseCFTypes | kFSEventStreamCreateFlagUseExtendedData)
        let callback: FSEventStreamCallback = { stream, _, count, paths, flags, ids in
            let watcher = TrashAppWatcher.shared
            guard stream == watcher.stream,
                  let records = unsafeBitCast(paths, to: NSArray.self) as? [[String: Any]],
                  records.count == count else { return }
            let lost = FSEventStreamEventFlags(kFSEventStreamEventFlagMustScanSubDirs
                | kFSEventStreamEventFlagUserDropped | kFSEventStreamEventFlagKernelDropped
                | kFSEventStreamEventFlagEventIdsWrapped)
            guard !(0..<count).contains(where: { flags[$0] & lost != 0 }) else {
                watcher.renames = UninstallerSupport.TrashRenames()
                return
            }
            let rename = FSEventStreamEventFlags(kFSEventStreamEventFlagItemRenamed | kFSEventStreamEventFlagItemIsDir)
            for index in 0..<count where flags[index] & rename == rename {
                guard let path = records[index]["path"] as? String,
                      let inode = records[index]["fileID"] as? NSNumber else { continue }
                if let move = watcher.renames.accept(URL(fileURLWithPath: path, isDirectory: true),
                                                     inode: inode.uint64Value, eventID: ids[index], home: watcher.home) {
                    watcher.offer(move)
                }
            }
        }
        guard let created = FSEventStreamCreate(nil, callback, nil, roots as CFArray,
                                                FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
                                                0.15, flags) else { return }
        FSEventStreamSetDispatchQueue(created, .main)
        guard FSEventStreamStart(created) else {
            FSEventStreamInvalidate(created)
            FSEventStreamRelease(created)
            return
        }
        stream = created
    }

    private func stop() {
        guard let stream else { return }
        FSEventStreamStop(stream)
        FSEventStreamInvalidate(stream)
        FSEventStreamRelease(stream)
        self.stream = nil
        renames = UninstallerSupport.TrashRenames()
    }

    private func offer(_ move: UninstallerSupport.TrashMove) {
        guard NSWorkspace.shared.frontmostApplication?.bundleIdentifier == "com.apple.finder",
              AppUninstaller.shared.canOfferTrashCleanup(of: move) else { return }
        appDelegate()?.openUninstaller(for: move.selection.url, trashMove: move)
    }
}
