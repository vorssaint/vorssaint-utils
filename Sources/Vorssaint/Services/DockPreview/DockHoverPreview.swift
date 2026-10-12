// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit

final class DockHoverPreview {
    private var pending: DispatchWorkItem?
    private var panel: NSPanel?
    private var token = UUID()
    private let provider = WindowPreviewProvider()
    init() {}
    func begin(_ item: SwitcherItem, activate: @escaping () -> Void) {
        end()
        let action = DockOption.hoverAction.string
        guard action != "off" else { return }
        let requested = token
        let work = DispatchWorkItem { [weak self] in
            guard let self, self.token == requested, AXIsProcessTrusted() else { return }
            if action == "activate" { activate(); return }
            guard Permissions.shared.screenRecording, !WindowPreviewProvider.captureIsPaused(excludedAppsKey: DefaultsKey.windowPreviewExcludedApps),
                  let id = item.previewWindowID else { return }
            let excluded = Defaults.sanitizedBundleIdentifierList(UserDefaults.standard.stringArray(forKey: DefaultsKey.windowPreviewExcludedApps) ?? [])
            guard !excluded.contains(NSRunningApplication(processIdentifier: item.pid)?.bundleIdentifier ?? "") else { return }
            let image = WindowPreviewProvider.shared.cachedPreview(for: id)
            guard let image else { return }
            let frame = DockAccessibility.appKit(item.frame)
            let panel = NSPanel(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
            panel.level = .floating; panel.ignoresMouseEvents = true; panel.hidesOnDeactivate = false
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]
            let view = NSImageView(frame: CGRect(origin: .zero, size: frame.size))
            view.image = NSImage(cgImage: image, size: frame.size); view.imageScaling = .scaleProportionallyUpOrDown
            panel.contentView = view; self.panel = panel; panel.orderFrontRegardless()
            self.provider.refreshPreviews(for: [item], maxPixelSize: min(4096, max(frame.width, frame.height) * 2),
                excludedAppsKey: DefaultsKey.windowPreviewExcludedApps) { [weak self, weak view] windowID, image in
                guard let self, self.token == requested, windowID == id else { return }
                view?.image = NSImage(cgImage: image, size: frame.size)
            }
        }
        pending = work
        let delay = DockEnhancementSupport.bounded(DockOption.hoverDelay.double, fallback: 0.8, range: 0...3)
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }
    func end() { provider.cancel(); token = UUID(); pending?.cancel(); pending = nil; panel?.orderOut(nil); panel = nil }
}
