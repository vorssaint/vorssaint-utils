import AppKit
import ScreenCaptureKit

/// Shows the selected app's windows as if the app were already in front:
/// snapshots drawn at their real place, above every other window and below
/// the switcher panel. No real window moves, so the stacking order of the
/// others is untouched when the session ends or the selection moves on.
@MainActor
final class SwitcherSelectionPeek {
    static let shared = SwitcherSelectionPeek()

    /// One panel per window, so each sits on its own display at the window's
    /// own frame: a single panel spanning displays shows on only one of them
    /// when displays have separate Spaces.
    private var panels: [NSPanel] = []
    private var generation = 0

    /// Kept for the session: going back to an app shows it at once, and the
    /// shareable-content listing, the slow part, is asked for only once.
    private var content: SCShareableContent?
    private var cache: [CGWindowID: (CGRect, CGImage)] = [:]
    private var highlightedID: CGWindowID?

    /// `upcoming` are the windows of the apps the next presses land on,
    /// captured once the selected app's are, so stepping on finds them ready.
    func show(_ items: [SwitcherItem], upcoming: [SwitcherItem] = [], highlightsSelected: Bool = false) {
        generation += 1
        highlightedID = highlightsSelected ? items.first?.windowID : nil
        let current = generation
        guard !items.isEmpty else { return hide(bumping: false) }
        let ids = items.compactMap(\.windowID)
        present(ids.compactMap { id in cache[id].map { (id, $0.0, $0.1) } })
        let prefetch = upcoming.compactMap(\.windowID).filter { !ids.contains($0) }
        guard (ids + prefetch).contains(where: { cache[$0] == nil }) else { return }
        Task { @MainActor in
            if self.content == nil {
                self.content = await WindowPreviewProvider.captureViaScreenCaptureKit({
                    try? await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)
                })
            }
            guard let content = self.content else { return }
            for id in ids + prefetch where self.cache[id] == nil {
                guard current == self.generation else { return }
                guard let scWindow = content.windows.first(where: { $0.windowID == id }) else { continue }
                let scale = NSScreen.screens.first { $0.frame.intersects(Self.appKitRect(scWindow.frame)) }?
                    .backingScaleFactor ?? 2
                let configuration = SCStreamConfiguration()
                configuration.width = Int(scWindow.frame.width * scale)
                configuration.height = Int(scWindow.frame.height * scale)
                configuration.showsCursor = false
                configuration.ignoreShadowsSingleWindow = true
                let filter = SCContentFilter(desktopIndependentWindow: scWindow)
                guard let image = await WindowPreviewProvider.captureViaScreenCaptureKit({
                    try? await SCScreenshotManager.captureImage(contentFilter: filter, configuration: configuration)
                }) else { continue }
                self.cache[id] = (scWindow.frame, image)
                // Each window shows as soon as it is ready, the selected one first.
                guard current == self.generation else { return }
                if ids.contains(id) { self.present(ids.compactMap { id in self.cache[id].map { (id, $0.0, $0.1) } }) }
            }
        }
    }

    /// Set when a session commits: the next hide waits for the chosen app to
    /// come forward. Hidden at once, the peek uncovered the old front window
    /// for a moment before the real one was raised, which read as a flicker.
    private var lingers = false

    func lingerOnNextHide() { lingers = true }

    func hide() {
        content = nil
        cache = [:]
        guard lingers else { return hide(bumping: true) }
        lingers = false
        generation += 1
        let current = generation
        // ponytail: fixed wait, long enough for a normal activation; tie it to
        // the activation finishing if a slow app still shows the gap.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            guard let self, current == self.generation else { return }
            self.hide(bumping: false)
        }
    }

    private func hide(bumping: Bool) {
        if bumping { generation += 1 }
        panels.forEach { $0.orderOut(nil) }
    }

    /// Window-server frame (top-left origin) to AppKit (bottom-left).
    private static func appKitRect(_ frame: CGRect) -> NSRect {
        let primaryHeight = NSScreen.screens.first?.frame.maxY ?? 0
        return NSRect(x: frame.minX, y: primaryHeight - frame.maxY, width: frame.width, height: frame.height)
    }

    private func present(_ captured: [(CGWindowID, CGRect, CGImage)]) {
        while panels.count < captured.count { panels.append(makePanel()) }
        for panel in panels.dropFirst(captured.count) { panel.orderOut(nil) }
        // Back-most first, so each later window orders above the previous one.
        for (panel, (id, frame, image)) in zip(panels, captured.reversed()) {
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            let layer = panel.contentView?.layer
            layer?.contents = image
            layer?.borderWidth = id == highlightedID ? 4 : 0
            layer?.borderColor = NSColor.controlAccentColor.cgColor
            CATransaction.commit()
            panel.setFrame(Self.appKitRect(frame), display: true)
            panel.orderFrontRegardless()
            panel.invalidateShadow()
        }
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel],
                            backing: .buffered, defer: true)
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue - 1)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        // Drawn from the capture's own alpha, like the real window's shadow.
        panel.hasShadow = true
        panel.ignoresMouseEvents = true
        panel.animationBehavior = .none
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.contentView?.wantsLayer = true
        panel.contentView?.layer?.contentsGravity = .resize
        // Rounds the highlight like the window's own corners.
        panel.contentView?.layer?.cornerRadius = 12
        panel.contentView?.layer?.masksToBounds = true
        return panel
    }
}
