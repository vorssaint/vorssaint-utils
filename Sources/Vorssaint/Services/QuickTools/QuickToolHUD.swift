// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import SwiftUI

/// Small floating confirmation used by the quick tools (color picked, text
/// copied, mic muted): a non-activating panel near the top of the screen with
/// the mouse, fading out on its own. Purely visual; never takes focus.
enum QuickToolHUD {
    private static var panel: NSPanel?
    private static var scrollingPanel: ScrollingCapturePanel?
    private static var scrollingModel: ScrollingCaptureHUDModel?
    private static var dismissWork: DispatchWorkItem?
    /// Confirmations size to their text up to this width. Persistent capture
    /// instructions wrap at this width and grow vertically to remain readable.
    fileprivate static let messageWidthLimit: CGFloat = 360
    /// Bumped by every show(). A dismiss whose fade-out was overtaken by a
    /// newer show() must not order the panel out from its completion handler.
    private static var generation = 0
    private static var collapsesOnDismiss = false

    /// The confirmation panel, when one is on screen. A recording in progress
    /// leaves it out of the picture; nothing else needs to know it exists.
    static var currentWindowNumber: Int? {
        guard let panel, panel.isVisible else { return nil }
        return panel.windowNumber
    }

    /// The scrolling capture controls, when they are on screen. They belong to
    /// the capture in progress and must stay out of its own pictures.
    static var currentScrollingWindowNumber: Int? {
        guard let scrollingPanel, scrollingPanel.isVisible else { return nil }
        return scrollingPanel.windowNumber
    }

    /// The screen-text and QR confirmation. The title says the copy succeeded
    /// and the detail is the text or link that landed on the clipboard. It
    /// stays long enough to read, then folds away on its own.
    static func showCopied(title: String, detail: String, openURL: URL? = nil) {
        guard Thread.isMainThread else {
            DispatchQueue.main.async { showCopied(title: title, detail: detail, openURL: openURL) }
            return
        }
        let screenWidth = NSScreen.pointerVisibleFrame.width
        let layout = CopiedCardLayout.measure(title: title,
                                              detail: detail,
                                              showsOpen: openURL != nil,
                                              screenWidth: screenWidth)
        let content = CopiedConfirmationView(title: title,
                                             detail: detail,
                                             openURL: openURL,
                                             layout: layout) {
            if let openURL { NSWorkspace.shared.open(openURL) }
            dismiss()
        }
        present(AnyView(content), dismissAfter: 5, acceptsMouse: true, collapses: true)
    }

    static func show(icon: String, message: String, swatch: NSColor? = nil) {
        guard Thread.isMainThread else {
            DispatchQueue.main.async { show(icon: icon, message: message, swatch: swatch) }
            return
        }
        let content = HStack(spacing: 8) {
            if let swatch {
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(Color(nsColor: swatch))
                    .frame(width: 18, height: 18)
                    .overlay(
                        RoundedRectangle(cornerRadius: 5, style: .continuous)
                            .strokeBorder(Color.primary.opacity(0.2), lineWidth: 0.5)
                    )
            } else {
                Image(systemName: icon)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
            }
            Text(message)
                .font(.system(size: 12, weight: .semibold))
                // What was copied can be a whole paragraph, and the panel is
                // laid out at whatever the text asks for. Unbounded, one long
                // line measures wider than the screen and the panel, centred on
                // that width, hangs off both edges with nothing readable left.
                //
                // Truncating at the tail rather than the middle so that the
                // ellipsis is always drawn: a value whose first paragraph ends
                // on the second line is cut at a line break, not inside one,
                // and middle truncation leaves no mark at all there — the
                // preview then reads as the whole of what was copied.
                .lineLimit(2)
                .truncationMode(.tail)
                .frame(maxWidth: messageWidthLimit, alignment: .leading)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10, style: .continuous))

        present(AnyView(content), dismissAfter: 1.5)
    }

    static func showCountdown(_ value: Int) {
        guard Thread.isMainThread else {
            DispatchQueue.main.async { showCountdown(value) }
            return
        }
        let startedAt = Date()
        let content = TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { context in
            let progress = ScreenshotSupport.countdownRingProgress(
                elapsed: context.date.timeIntervalSince(startedAt))
            QuickToolCountdownView(value: value, progress: progress)
        }
        .frame(width: 82, height: 82)
        .background(.regularMaterial, in: Circle())
        .padding(12)

        present(AnyView(content), dismissAfter: 0.92, windowShadow: false)
    }

    /// The scrolling capture stays visible while the person moves the target.
    /// Its non-activating panel takes key focus only so Return and Escape do
    /// not leak into the page being captured.
    static func showScrollingCapture(message: String,
                                     finishTitle: String,
                                     cancelTitle: String,
                                     avoiding scrollPoint: CGPoint?,
                                     onFinish: @escaping () -> Void,
                                     onCancel: @escaping () -> Void) {
        guard Thread.isMainThread else {
            DispatchQueue.main.async {
                showScrollingCapture(message: message,
                                     finishTitle: finishTitle,
                                     cancelTitle: cancelTitle,
                                     avoiding: scrollPoint,
                                     onFinish: onFinish,
                                     onCancel: onCancel)
            }
            return
        }
        let model = ScrollingCaptureHUDModel(message: message)
        scrollingModel = model
        let content = ScrollingCaptureHUDView(model: model,
                                              finishTitle: finishTitle,
                                              cancelTitle: cancelTitle,
                                              onFinish: {
                                                  guard !model.isFinishing else { return }
                                                  model.isFinishing = true
                                                  onFinish()
                                              },
                                              onCancel: onCancel)
        let host = ScrollingCaptureHostingView(rootView: AnyView(content))
        host.layoutSubtreeIfNeeded()
        let size = host.fittingSize
        let panel = ensureScrollingPanel()
        panel.contentView = host
        panel.setFrame(ScreenshotSupport.scrollingControlsFrame(
            size: size, visibleFrame: NSScreen.pointerVisibleFrame, avoiding: scrollPoint), display: true)
        panel.orderFrontRegardless()
        panel.makeKey()
    }

    static func updateScrollingCapture(height: Int) {
        guard Thread.isMainThread else {
            DispatchQueue.main.async { updateScrollingCapture(height: height) }
            return
        }
        scrollingModel?.height = height
    }

    static func markScrollingCaptureFinishing() {
        scrollingModel?.isFinishing = true
    }

    static func dismissScrollingCapture() {
        guard Thread.isMainThread else {
            DispatchQueue.main.async { dismissScrollingCapture() }
            return
        }
        scrollingPanel?.orderOut(nil)
        scrollingPanel?.contentView = nil
        scrollingModel = nil
    }

    private static func present(_ content: AnyView,
                                dismissAfter: Double,
                                windowShadow: Bool = true,
                                acceptsMouse: Bool = false,
                                collapses: Bool = false) {
        let host = NSHostingController(rootView: content)
        host.view.layoutSubtreeIfNeeded()
        let size = host.view.fittingSize

        let panel = ensurePanel()
        panel.hasShadow = windowShadow
        panel.ignoresMouseEvents = !acceptsMouse
        collapsesOnDismiss = collapses
        panel.contentViewController = host

        let frame = NSScreen.pointerVisibleFrame
        panel.setFrame(NSRect(x: frame.midX - size.width / 2,
                              y: frame.maxY - size.height - 24,
                              width: size.width,
                              height: size.height),
                       display: true)
        generation += 1
        panel.alphaValue = 0
        panel.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.12
            panel.animator().alphaValue = 1
        }

        dismissWork?.cancel()
        let work = DispatchWorkItem { dismiss() }
        dismissWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + dismissAfter, execute: work)
    }

    private static func dismiss() {
        guard let panel else { return }
        let dismissed = generation
        let collapse = collapsesOnDismiss
        let start = panel.frame
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = collapse ? 0.28 : 0.22
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            panel.animator().alphaValue = 0
            if collapse {
                panel.animator().setFrame(NSRect(x: start.minX,
                                                 y: start.maxY - 8,
                                                 width: start.width,
                                                 height: 8),
                                          display: true)
            }
        }, completionHandler: {
            guard generation == dismissed else { return }
            panel.orderOut(nil)
            panel.contentViewController = nil
            panel.ignoresMouseEvents = true
            collapsesOnDismiss = false
            dismissWork = nil
        })
    }

    private static func ensurePanel() -> NSPanel {
        if let panel { return panel }
        let panel = makePanel()
        self.panel = panel
        return panel
    }

    private static func ensureScrollingPanel() -> ScrollingCapturePanel {
        if let scrollingPanel { return scrollingPanel }
        let panel = ScrollingCapturePanel(contentRect: .zero,
                                          styleMask: [.borderless, .nonactivatingPanel],
                                          backing: .buffered,
                                          defer: false)
        configure(panel)
        panel.ignoresMouseEvents = false
        scrollingPanel = panel
        return panel
    }

    private static func makePanel() -> NSPanel {
        let panel = OverlayPanel(contentRect: .zero,
                                 styleMask: [.borderless, .nonactivatingPanel],
                                 backing: .buffered,
                                 defer: false)
        configure(panel)
        return panel
    }

    private static func configure(_ panel: NSPanel) {
        panel.level = .statusBar
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.ignoresMouseEvents = true
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]
    }
}

/// Success line plus the value that was copied. The success line stays
/// centered. The value keeps its own alignment and grows only up to a small
/// cap, then scrolls so the start and the end both remain reachable.
private struct CopiedConfirmationView: View {
    let title: String
    let detail: String
    let openURL: URL?
    let layout: CopiedCardLayout.Measurement
    let open: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: CopiedCardLayout.spacing) {
            HStack(spacing: 6) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color.green)
                Text(title)
                    .font(.system(size: 12, weight: .semibold))
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity)

            ScrollView {
                Text(detail)
                    .font(.system(size: 12))
                    .foregroundStyle(.primary.opacity(0.86))
                    .textSelection(.enabled)
                    .multilineTextAlignment(.leading)
                    .frame(width: layout.contentWidth, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(width: layout.contentWidth, height: layout.detailHeight)
            .scrollDisabled(!layout.scrolls)

            if openURL != nil {
                HStack {
                    Spacer(minLength: 0)
                    Button(L10n.shared.s.qrResultOpen, action: open)
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(width: layout.cardSize.width, height: layout.cardSize.height)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

private struct QuickToolCountdownView: View {
    let value: Int
    let progress: CGFloat

    var body: some View {
        ZStack {
            Circle()
                .strokeBorder(Color.white.opacity(0.12), lineWidth: 1)
            Circle()
                .trim(from: 0.04, to: 0.04 + progress * 0.92)
                .stroke(Color.accentColor,
                        style: StrokeStyle(lineWidth: 3, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .padding(6)
            Text("\(value)")
                .font(.system(size: 32, weight: .bold, design: .rounded))
                .monospacedDigit()
        }
    }
}

/// A non-activating panel that can still own Return and Escape while the
/// underlying window continues receiving pointer and scrolling events.
private final class ScrollingCapturePanel: OverlayPanel {
    override var canBecomeKey: Bool { true }
}

private final class ScrollingCaptureHostingView: NSHostingView<AnyView> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

private final class ScrollingCaptureHUDModel: ObservableObject {
    let message: String
    @Published var height = 0
    @Published var isFinishing = false

    init(message: String) {
        self.message = message
    }
}

private struct ScrollingCaptureHUDView: View {
    @ObservedObject var model: ScrollingCaptureHUDModel
    let finishTitle: String
    let cancelTitle: String
    let onFinish: () -> Void
    let onCancel: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            ZStack {
                if model.isFinishing {
                    ProgressView().controlSize(.small)
                } else {
                    Image(systemName: "rectangle.stack.fill")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Color.accentColor)
                }
            }
            .frame(width: 16, height: 16)
            VStack(alignment: .leading, spacing: 1) {
                Text(model.message)
                    .font(.system(size: 12, weight: .semibold))
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(width: QuickToolHUD.messageWidthLimit, alignment: .leading)
                Text("\(model.height) px")
                    .font(.system(size: 10, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            Button(cancelTitle, action: onCancel)
                .controlSize(.small)
                .keyboardShortcut(.cancelAction)
            Button(finishTitle, action: onFinish)
                .disabled(model.isFinishing)
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .keyboardShortcut(.defaultAction)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}
