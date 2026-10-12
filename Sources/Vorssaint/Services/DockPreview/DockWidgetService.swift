// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import SwiftUI

final class DockWidgetService: ObservableObject {
    static let shared = DockWidgetService()
    enum Kind: Equatable { case folder(URL), music(pid_t), calendar }
    @Published private(set) var kind: Kind?
    @Published var pinned = false
    private var panel: NSPanel?
    private var timer: Timer?
    private var iconFrame = CGRect.zero
    private var candidate: Kind?
    private var candidateAt: TimeInterval = 0
    private var leaveAt: TimeInterval?
    private var musicWanted = false
    weak var lyricSession: NotchLyricsService?
    var presentationWindow: NSWindow? { panel }
    private init() {}
    func syncWithPreferences() {
        guard AppFeature.dockPreview.isAvailable, UserDefaults.standard.bool(forKey: DefaultsKey.dockPreviewEnabled),
              Permissions.shared.accessibility, SessionActivity.shared.isActive,
              DockOption.folders.bool || DockOption.mediaWidget.bool || DockOption.calendarWidget.bool else { stop(); return }
        if DockOption.mediaWidget.bool {
            musicWanted = true; NotchMusicService.shared.start(consumer: .dock)
        } else if musicWanted { musicWanted = false; NotchMusicService.shared.stop(consumer: .dock) }
        if let kind, !allows(kind) { dismiss() }
        guard timer == nil else { return }
        let timer = Timer(timeInterval: 0.15, repeats: true) { [weak self] _ in self?.sample() }
        timer.tolerance = 0.04; RunLoop.main.add(timer, forMode: .common); self.timer = timer
    }
    func isMediaApp(_ pid: pid_t) -> Bool {
        musicWanted && NotchMusicService.shared.playback?.track.appPID == pid
    }
    func panelCovers(_ point: CGPoint) -> Bool { panel?.isVisible == true && panel?.frame.contains(point) == true }
    private func allows(_ kind: Kind) -> Bool {
        switch kind { case .folder: return DockOption.folders.bool; case .music: return DockOption.mediaWidget.bool; case .calendar: return DockOption.calendarWidget.bool }
    }
    private func sample() {
        guard SessionActivity.shared.isActive, AXIsProcessTrusted() else { dismiss(); return }
        let point = NSEvent.mouseLocation, now = ProcessInfo.processInfo.systemUptime
        if panel?.isVisible == true, pinned || lyricSession?.isImporting == true || corridorContains(point) { leaveAt = nil; return }
        let nearEdge = NSScreen.screens.contains { screen in
            guard screen.frame.contains(point) else { return false }
            switch DockAccessibility.orientation {
            case .bottom: return point.y < screen.frame.minY + 160
            case .left: return point.x < screen.frame.minX + 160
            case .right: return point.x > screen.frame.maxX - 160
            }
        }
        if nearEdge, let tile = DockAccessibility.items().first(where: { $0.frame.contains(point) }), let next = widget(for: tile) {
            leaveAt = nil
            if candidate != next { candidate = next; candidateAt = now }
            if now - candidateAt >= 0.35, kind != next || panel?.isVisible != true { show(next, anchor: tile.frame) }
        } else {
            candidate = nil
            if panel?.isVisible == true {
                if let leaveAt, now - leaveAt > 0.35 { dismiss() }
                else if leaveAt == nil { leaveAt = now }
            }
        }
    }
    private func widget(for tile: DockAccessibility.Item) -> Kind? {
        if DockOption.folders.bool, let url = tile.url, url.isFileURL, !url.pathExtension.lowercased().hasSuffix("app"),
           (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true { return .folder(url) }
        if DockOption.calendarWidget.bool, let url = tile.url, Bundle(url: url)?.bundleIdentifier == "com.apple.iCal" { return .calendar }
        if let app = DockAccessibility.application(for: tile) {
            if DockOption.calendarWidget.bool, app.bundleIdentifier == "com.apple.iCal" { return .calendar }
            if isMediaApp(app.processIdentifier) { return .music(app.processIdentifier) }
        }
        return nil
    }
    private func corridorContains(_ point: CGPoint) -> Bool {
        guard let frame = panel?.frame else { return false }
        if frame.contains(point) || iconFrame.contains(point) { return true }
        // Existing corridor geometry limits the bridge to the actual tile and
        // panel instead of holding a large bounding box over adjacent apps.
        return DockPreviewSupport.hoverCorridor(iconFrame: iconFrame, panelFrame: frame, orientation: DockAccessibility.orientation).contains(point)
    }
    private func show(_ kind: Kind, anchor: CGRect) {
        DockPreviewService.shared.closePreviewPanel()
        self.kind = kind; iconFrame = anchor; pinned = false
        let panel = self.panel ?? NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.level = .floating; panel.hidesOnDeactivate = false; panel.isOpaque = false; panel.backgroundColor = .clear
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        let size = CGSize(width: 400, height: kind == .calendar ? 360 : 460)
        let screen = NSScreen.screens.first(where: { $0.frame.intersects(anchor) }) ?? NSScreen.main
        guard let screen else { return }
        let frame = DockPreviewSupport.panelFrame(anchor: anchor, panelSize: size, screenVisibleFrame: screen.visibleFrame, orientation: DockAccessibility.orientation, gap: 10)
        self.panel = panel
        panel.contentView = NSHostingView(rootView: DockWidgetView(service: self, kind: kind))
        panel.setFrame(frame, display: true); panel.orderFrontRegardless()
    }
    func dismiss() { panel?.orderOut(nil); panel?.contentView = nil; kind = nil; pinned = false; leaveAt = nil }
    func stop() {
        timer?.invalidate(); timer = nil; candidate = nil; dismiss(); panel = nil
        if musicWanted { musicWanted = false; NotchMusicService.shared.stop(consumer: .dock) }
    }
}
