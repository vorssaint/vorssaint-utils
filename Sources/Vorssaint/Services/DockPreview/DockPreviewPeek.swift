// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit

/// Shows a hovered Dock Preview card's window where it is, without touching
/// it: a full-size snapshot of the window drawn over its own frame and
/// outlined, above a dimmed screen. The real windows keep their order and
/// focus, so leaving the card puts everything back exactly, and nothing comes
/// forward until the card is clicked.
///
/// The cached thumbnail stands in until the full-resolution capture lands. A
/// window that cannot be captured whole, or while capture is paused for an
/// excluded app, is shown by its outline alone.
///
/// Main thread only, like the panels that drive it.
final class DockPreviewPeek {
    static let shared = DockPreviewPeek()

    private static let dimOpacity: CGFloat = 0.35
    private static let outlineWidth: CGFloat = 3
    private static let cornerRadius: CGFloat = 14
    private static let fadeDuration: TimeInterval = 0.1
    /// How long a peek outlives the card the pointer just left, so moving to
    /// the next card switches the peek instead of closing and reopening it.
    private static let leaveGrace: TimeInterval = 0.06
    /// Above every app window, below the Dock and the menu bar, which stay
    /// readable, and below the preview panels at `.statusBar`.
    private static let level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.dockWindow)) - 1)

    private struct Request {
        let windowID: CGWindowID
        let frame: CGRect
        var snapshot: CGImage?
    }

    private var request: Request?
    private var isShowing = false
    private var dimPanels: [NSPanel] = []
    private var windowPanel: NSPanel?
    private var pendingShow: DispatchWorkItem?
    private var pendingHide: DispatchWorkItem?
    private var captureTask: Task<Void, Never>?

    private init() {}

    /// The pointer entered `item`'s card.
    func hover(_ item: SwitcherItem) {
        guard UserDefaults.standard.bool(forKey: DefaultsKey.dockPreviewPeekWindows) else { return }
        let screenFrames = NSScreen.screens.map(\.frame)
        let frame = DockPreviewSupport.appKitFrame(
            fromTopLeft: item.frame,
            menuBarScreenTopY: DockPreviewSupport.menuBarScreenTopY(screenFrames: screenFrames,
                                                                    fallback: NSScreen.main?.frame))
        guard let windowID = item.windowID,
              DockPreviewSupport.canPeek(hasWindowID: true,
                                         isMinimized: item.isMinimized,
                                         isOnHiddenSpace: item.isOnHiddenSpace,
                                         frame: frame,
                                         screenFrames: screenFrames)
        else {
            dismiss()
            return
        }
        pendingHide?.cancel()
        pendingHide = nil
        guard request?.windowID != windowID else { return }

        pendingShow?.cancel()
        captureTask?.cancel()
        request = Request(windowID: windowID, frame: frame)

        let windowSize = item.frame.size
        captureTask = Task(priority: .userInitiated) { [weak self] in
            let snapshot = await Self.snapshot(of: windowID, windowSize: windowSize)
            guard let self else { return }
            await MainActor.run {
                guard !Task.isCancelled, self.request?.windowID == windowID else { return }
                self.request?.snapshot = snapshot
                if self.isShowing, let snapshot { self.peekView?.image = snapshot }
            }
        }

        let show = DispatchWorkItem { [weak self] in
            guard let self, let request = self.request, request.windowID == windowID else { return }
            self.show(request.snapshot ?? WindowPreviewProvider.shared.cachedPreview(for: windowID),
                      at: request.frame)
        }
        pendingShow = show
        DispatchQueue.main.asyncAfter(deadline: .now() + DockPreviewSupport.peekDelay(alreadyPeeking: isShowing),
                                      execute: show)
    }

    /// The pointer left `item`'s card. A card left after the next one was
    /// entered changes nothing.
    func leave(_ item: SwitcherItem) {
        guard let windowID = item.windowID, request?.windowID == windowID else { return }
        pendingHide?.cancel()
        let hide = DispatchWorkItem { [weak self] in
            guard let self, self.request?.windowID == windowID else { return }
            self.dismiss()
        }
        pendingHide = hide
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.leaveGrace, execute: hide)
    }

    /// Takes the peek down at once: the card was clicked, dragged, closed or
    /// minimized, or its panel went away.
    func dismiss() {
        pendingShow?.cancel()
        pendingShow = nil
        pendingHide?.cancel()
        pendingHide = nil
        captureTask?.cancel()
        captureTask = nil
        request = nil
        guard isShowing else { return }
        isShowing = false
        windowPanel?.orderOut(nil)
        dimPanels.forEach { $0.orderOut(nil) }
        // Displays can come and go between peeks; the next one covers
        // whatever is attached then.
        dimPanels = []
    }

    // MARK: - Drawing

    private var peekView: DockPreviewPeekView? {
        windowPanel?.contentView as? DockPreviewPeekView
    }

    private func show(_ image: CGImage?, at frame: CGRect) {
        let fadesIn = !isShowing && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        if dimPanels.isEmpty {
            dimPanels = NSScreen.screens.map { screen in
                let panel = Self.makePanel(frame: screen.frame, hasShadow: false)
                let view = NSView(frame: CGRect(origin: .zero, size: screen.frame.size))
                view.wantsLayer = true
                view.layer?.backgroundColor = NSColor.black.withAlphaComponent(Self.dimOpacity).cgColor
                panel.contentView = view
                return panel
            }
        }
        let windowPanel = self.windowPanel ?? {
            let panel = Self.makePanel(frame: frame, hasShadow: true)
            panel.contentView = DockPreviewPeekView(cornerRadius: Self.cornerRadius,
                                                    outlineWidth: Self.outlineWidth)
            self.windowPanel = panel
            return panel
        }()
        windowPanel.setFrame(frame, display: false)
        peekView?.image = image

        let panels = dimPanels + [windowPanel]
        for panel in panels {
            if fadesIn { panel.alphaValue = 0 }
            panel.orderFrontRegardless()
        }
        if fadesIn {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = Self.fadeDuration
                panels.forEach { $0.animator().alphaValue = 1 }
            }
        } else {
            panels.forEach { $0.alphaValue = 1 }
        }
        isShowing = true
    }

    private static func makePanel(frame: CGRect, hasShadow: Bool) -> NSPanel {
        let panel = NSPanel(contentRect: frame,
                            styleMask: [.borderless, .nonactivatingPanel],
                            backing: .buffered,
                            defer: false)
        panel.level = level
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = hasShadow
        panel.ignoresMouseEvents = true
        panel.hidesOnDeactivate = false
        panel.animationBehavior = .none
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]
        return panel
    }

    // MARK: - Capture

    /// The whole window at full resolution, or nil when a capture cannot show
    /// it as it is: Screen Recording off, capture paused for an excluded app
    /// like the thumbnails, a window hanging over a display edge (the window
    /// server returns only the part inside), or Stage Manager's tilted strip
    /// artwork.
    private static func snapshot(of windowID: CGWindowID, windowSize: CGSize) async -> CGImage? {
        let allowed = await MainActor.run {
            Permissions.shared.screenRecording
                && !WindowPreviewProvider.captureIsPaused(excludedAppsKey: DefaultsKey.windowPreviewExcludedApps)
        }
        guard allowed, let image = await WindowPreviewProvider.captureViaWindowServer(windowID) else { return nil }
        if let grid = SwitcherSupport.alphaGrid(of: image), SwitcherSupport.captureLooksTransformed(alphaGrid: grid) {
            return nil
        }
        guard SwitcherSupport.captureCoversWindow(imageWidth: image.width,
                                                  imageHeight: image.height,
                                                  windowSize: windowSize) else { return nil }
        return image
    }
}

/// The peeked window: its snapshot stretched over the window's frame, with
/// an accent outline drawn over the edge.
private final class DockPreviewPeekView: NSView {
    private let imageLayer = CALayer()
    private let outlineLayer = CALayer()

    var image: CGImage? {
        didSet { imageLayer.contents = image }
    }

    init(cornerRadius: CGFloat, outlineWidth: CGFloat) {
        super.init(frame: .zero)
        wantsLayer = true
        imageLayer.contentsGravity = .resize
        outlineLayer.borderWidth = outlineWidth
        outlineLayer.cornerRadius = cornerRadius
        outlineLayer.borderColor = NSColor.controlAccentColor.cgColor
        layer?.addSublayer(imageLayer)
        layer?.addSublayer(outlineLayer)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not used")
    }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        imageLayer.frame = bounds
        outlineLayer.frame = bounds
        CATransaction.commit()
    }
}
