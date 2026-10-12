// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit

/// Lazily starts only requested additions, and immediately releases resources
/// on uninstall, preference changes, sleep, or leaving the console session.
final class DockAdditionsRuntime {
    static let shared = DockAdditionsRuntime()
    private var loaded = Set<String>()
    private var sleeping = false
    private var observers: [NSObjectProtocol] = []
    private var pending: DispatchWorkItem?
    private var captureSettings: [String]?
    private init() {
        SessionActivity.shared.onChange { [weak self] _ in self?.sync() }
        let center = NSWorkspace.shared.notificationCenter
        observers.append(center.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in self?.sleeping = true; self?.stop() })
        observers.append(center.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in self?.sleeping = false; self?.sync() })
        observers.append(NotificationCenter.default.addObserver(forName: UserDefaults.didChangeNotification, object: UserDefaults.standard, queue: .main) { [weak self] _ in
            guard let self else { return }
            self.pending?.cancel()
            let work = DispatchWorkItem { [weak self] in self?.sync() }
            self.pending = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2, execute: work)
        })
    }
    func sync() {
        let active = SessionActivity.shared.isActive && !sleeping && Permissions.shared.accessibility
        let dock = active && AppFeature.dockPreview.isAvailable && UserDefaults.standard.bool(forKey: DefaultsKey.dockPreviewEnabled)
        let switcher = active && AppFeature.switcher.isAvailable && UserDefaults.standard.bool(forKey: DefaultsKey.switcherEnabled)
        let freshCaptureSettings = [DockOption.livePreviews, .switcherLivePreviews, .liveFrameRate, .liveQuality, .compact, .compactThreshold].map {
            String(describing: UserDefaults.standard.object(forKey: $0.key) ?? $0.defaultValue)
        } + [String(Permissions.shared.screenRecording),
             String(describing: UserDefaults.standard.stringArray(forKey: DefaultsKey.windowPreviewExcludedApps) ?? []),
             String(describing: UserDefaults.standard.stringArray(forKey: DefaultsKey.switcherPreviewExcludedApps) ?? [])]
        if let captureSettings, captureSettings != freshCaptureSettings {
            if loaded.contains("dockSurface") { DockPreviewService.shared.hideAllPreviews() }
            if switcher { AppSwitcher.shared.cancelExternalSession(); AppSwitcher.shared.syncWithPreferences() }
        }
        captureSettings = freshCaptureSettings
        run("indicator", wanted: active && AppFeature.dockIndicator.isAvailable && DockOption.indicatorEnabled.bool,
            start: { DockIndicatorService.shared.syncWithPreferences() }, stop: { DockIndicatorService.shared.stop() })
        run("lock", wanted: active && AppFeature.dockLock.isAvailable && DockOption.lockEnabled.bool,
            start: { DockLockService.shared.syncWithPreferences() }, stop: { DockLockService.shared.stop() })
        run("widgets", wanted: dock && (DockOption.folders.bool || DockOption.mediaWidget.bool || DockOption.calendarWidget.bool),
            start: { DockWidgetService.shared.syncWithPreferences() }, stop: { DockWidgetService.shared.stop() })
        run("input", wanted: dock && (DockOption.quickQuit.bool || DockOption.dockScroll.bool || DockOption.titleBarScroll.bool || DockOption.trigger.string != "hover"),
            start: { DockInputService.shared.start() }, stop: { DockInputService.shared.stop() })
        run("cmdtab", wanted: dock && DockOption.nativeCmdTab.bool,
            start: { CmdTabPreviewService.shared.start() }, stop: { CmdTabPreviewService.shared.stop() })
        run("trackpad", wanted: switcher && DockOption.trackpadSwitcher.bool,
            start: { TrackpadWindowSwitcher.shared.start() }, stop: { TrackpadWindowSwitcher.shared.stop() })
        // Permission changes must also cancel streams on existing surfaces.
        if !dock, loaded.remove("dockSurface") != nil { DockPreviewService.shared.hideAllPreviews() }
        if dock { loaded.insert("dockSurface") }
    }
    private func run(_ id: String, wanted: Bool, start: () -> Void, stop: () -> Void) {
        if wanted { loaded.insert(id); start() }
        else if loaded.remove(id) != nil { stop() }
    }
    func dismissWidget() { if loaded.contains("widgets") { DockWidgetService.shared.dismiss() } }
    func stop() {
        pending?.cancel(); pending = nil
        if loaded.contains("indicator") { DockIndicatorService.shared.stop() }
        if loaded.contains("lock") { DockLockService.shared.stop() }
        if loaded.contains("widgets") { DockWidgetService.shared.stop() }
        if loaded.contains("input") { DockInputService.shared.stop() }
        if loaded.contains("cmdtab") { CmdTabPreviewService.shared.stop() }
        if loaded.contains("trackpad") { TrackpadWindowSwitcher.shared.stop() }
        if loaded.contains("dockSurface") { DockPreviewService.shared.hideAllPreviews() }
        loaded.removeAll()
        captureSettings = nil
    }
}
