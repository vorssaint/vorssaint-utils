// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import CoreServices

final class TrashSuggestionService {
    static let shared = TrashSuggestionService()

    private let trashURL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".Trash", isDirectory: true)
    private var stream: FSEventStreamRef?
    private var knownPaths = Set<String>()
    private var rescanWork: DispatchWorkItem?
    private var isStarted = false

    private init() {}

    func start() {
        guard !isStarted,
              AppFeature.uninstaller.isAvailable,
              UserDefaults.standard.bool(forKey: DefaultsKey.uninstallerTrashDetectionEnabled) else { return }
        isStarted = true
        knownPaths = Set(TrashSuggestionSupport.appURLs(in: trashURL).map {
            $0.standardizedFileURL.path
        })

        var context = FSEventStreamContext(
            version: 0,
            info: Unmanaged.passUnretained(self).toOpaque(),
            retain: nil,
            release: nil,
            copyDescription: nil
        )
        stream = FSEventStreamCreate(
            nil,
            { _, info, _, _, _, _ in
                guard let info else { return }
                let service = Unmanaged<TrashSuggestionService>
                    .fromOpaque(info)
                    .takeUnretainedValue()
                DispatchQueue.main.async { service.scheduleRescan() }
            },
            &context,
            [trashURL.path] as CFArray,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            0.25,
            FSEventStreamCreateFlags(
                kFSEventStreamCreateFlagFileEvents
                    | kFSEventStreamCreateFlagNoDefer
                    | kFSEventStreamCreateFlagWatchRoot
            )
        )
        guard let stream else {
            isStarted = false
            return
        }
        FSEventStreamSetDispatchQueue(stream, .main)
        FSEventStreamStart(stream)
    }

    func setEnabled(_ enabled: Bool) {
        if enabled {
            start()
        } else {
            stop()
        }
    }

    func stop() {
        rescanWork?.cancel()
        rescanWork = nil
        guard let stream else {
            isStarted = false
            return
        }
        FSEventStreamStop(stream)
        FSEventStreamInvalidate(stream)
        FSEventStreamRelease(stream)
        self.stream = nil
        isStarted = false
    }

    private func scheduleRescan() {
        guard isStarted else { return }
        rescanWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.rescan() }
        rescanWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35, execute: work)
    }

    private func rescan() {
        guard isStarted else { return }
        let apps = TrashSuggestionSupport.appURLs(in: trashURL)
        let newApps = TrashSuggestionSupport.newlyTrashedApps(current: apps, knownPaths: knownPaths)
        knownPaths = Set(apps.map { $0.standardizedFileURL.path })
        for appURL in newApps {
            guard UninstallerSupport.selection(for: appURL) != nil else { continue }
            presentSuggestion(for: appURL)
        }
    }

    private func presentSuggestion(for appURL: URL) {
        guard AppUninstaller.shared.phase == .empty else { return }
        switch TrashSuggestionPresentation.current {
        case .window:
            (NSApp.delegate as? AppDelegate)?.openUninstaller(for: appURL)
        case .notch:
            let name = appURL.deletingPathExtension().lastPathComponent
            let content = NotchNotificationContent(
                app: L10n.shared.s.uninstallerName,
                title: name,
                subtitle: L10n.shared.s.uninstallerName,
                body: L10n.shared.s.uninstallerEmptyNote
            )
            _ = NotchService.shared.show(NotchNotice(
                event: .systemNotification,
                title: name,
                detail: L10n.shared.s.uninstallerName,
                symbol: "trash",
                notification: content,
                action: appURL
            ))
        }
    }
}
