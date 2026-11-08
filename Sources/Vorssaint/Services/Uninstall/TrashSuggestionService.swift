// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import Combine
import CoreServices

final class TrashSuggestionService: ObservableObject {
    static let shared = TrashSuggestionService()

    @Published private(set) var monitoringState: TrashSuggestionMonitoringState = .disabled

    private let trashURL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".Trash", isDirectory: true)
    private var stream: FSEventStreamRef?
    private var knownPaths = Set<String>()
    private var rescanWork: DispatchWorkItem?
    private var deferredSuggestions: [URL] = []
    private var notchChangeObservation: AnyCancellable?
    private var isStarted = false

    private init() {}

    func start() {
        guard AppFeature.uninstaller.isAvailable,
              UserDefaults.standard.bool(forKey: DefaultsKey.uninstallerTrashDetectionEnabled) else {
            stop()
            return
        }
        guard Permissions.shared.fullDiskAccess else {
            stop()
            monitoringState = TrashSuggestionSupport.monitoringState(
                enabled: true, hasFullDiskAccess: false, streamStarted: false)
            return
        }
        guard !isStarted else { return }
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
        guard let stream = FSEventStreamCreate(
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
        ) else {
            reportStartupFailure()
            return
        }
        FSEventStreamSetDispatchQueue(stream, .main)
        guard FSEventStreamStart(stream) else {
            FSEventStreamInvalidate(stream)
            FSEventStreamRelease(stream)
            reportStartupFailure()
            return
        }
        self.stream = stream
        isStarted = true
        monitoringState = TrashSuggestionSupport.monitoringState(
            enabled: true, hasFullDiskAccess: true, streamStarted: true)
    }

    private func reportStartupFailure() {
        isStarted = false
        monitoringState = TrashSuggestionSupport.monitoringState(
            enabled: true, hasFullDiskAccess: true, streamStarted: false)
        QuickToolHUD.show(icon: "trash", message: L10n.shared.s.uninstallerTrashDetectionFailed)
    }

    func setEnabled(_ enabled: Bool) {
        if enabled {
            start()
        } else {
            stop()
        }
    }

    func refreshPermissionState() {
        guard UserDefaults.standard.bool(forKey: DefaultsKey.uninstallerTrashDetectionEnabled) else {
            stop()
            return
        }
        start()
    }

    func stop() {
        rescanWork?.cancel()
        rescanWork = nil
        notchChangeObservation?.cancel()
        notchChangeObservation = nil
        deferredSuggestions.removeAll()
        if let stream {
            FSEventStreamStop(stream)
            FSEventStreamInvalidate(stream)
            FSEventStreamRelease(stream)
            self.stream = nil
        }
        isStarted = false
        monitoringState = .disabled
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
        let installedBundleIDs = InstalledApps.installedApplications(includeSystemApplications: true)
            .compactMap(\.bundleID)
        for appURL in newApps {
            guard UninstallerSupport.selection(for: appURL) != nil,
                  TrashSuggestionSupport.shouldSuggestCleanup(
                    for: TrashSuggestionSupport.bundleIdentifierOnDisk(at: appURL),
                    installedBundleIDs: installedBundleIDs) else { continue }
            presentSuggestion(for: appURL)
        }
    }

    private func presentSuggestion(for appURL: URL) {
        guard AppUninstaller.shared.phase == .empty else { return }
        switch TrashSuggestionPresentation.current {
        case .window:
            openUninstaller(for: appURL)
        case .notch:
            switch NotchService.shared.trashSuggestionAvailability {
            case .deferUntilAvailable:
                if !deferredSuggestions.contains(appURL) { deferredSuggestions.append(appURL) }
                scheduleDeferredSuggestionCheck()
                return
            case .unavailable:
                openUninstaller(for: appURL)
                return
            case .available:
                break
            }
            let name = appURL.deletingPathExtension().lastPathComponent
            let content = NotchNotificationContent(
                app: L10n.shared.s.uninstallerName,
                title: name,
                subtitle: L10n.shared.s.uninstallerName,
                body: L10n.shared.s.uninstallerEmptyNote
            )
            if !NotchService.shared.show(NotchNotice(
                event: .systemNotification,
                title: name,
                detail: L10n.shared.s.uninstallerName,
                symbol: "trash",
                notification: content,
                action: appURL
            )) {
                openUninstaller(for: appURL)
            }
        }
    }

    private func openUninstaller(for appURL: URL) {
        (NSApp.delegate as? AppDelegate)?.openUninstaller(for: appURL)
    }

    private func scheduleDeferredSuggestionCheck() {
        guard notchChangeObservation == nil else { return }
        notchChangeObservation = NotchService.shared.objectWillChange.sink { [weak self] _ in
            DispatchQueue.main.async { self?.presentDeferredSuggestionsIfAvailable() }
        }
    }

    private func presentDeferredSuggestionsIfAvailable() {
        guard !deferredSuggestions.isEmpty else {
            notchChangeObservation?.cancel()
            notchChangeObservation = nil
            return
        }
        guard NotchService.shared.trashSuggestionAvailability != .deferUntilAvailable else { return }
        let pending = deferredSuggestions
        deferredSuggestions.removeAll()
        notchChangeObservation?.cancel()
        notchChangeObservation = nil
        for appURL in pending { presentSuggestion(for: appURL) }
    }
}
