// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import Carbon.HIToolbox
import SwiftUI

/// Shows what a scanned QR code actually holds before anything is copied: the
/// decoded content is spelled out, with a copy action and, for a plain web
/// link, an open action. Shared by the screen text tool and the screenshot
/// preview and editor so a code reads the same everywhere.
final class QRResultController {
    static let shared = QRResultController()

    private var panel: QRResultPanel?
    private var keyMonitor: Any?
    private var localMonitor: Any?
    private var globalMonitor: Any?

    private init() {}

    func show(reading: BarcodeDetector.Reading) {
        guard Thread.isMainThread else {
            DispatchQueue.main.async { self.show(reading: reading) }
            return
        }
        close()

        let strings = L10n.shared.s
        let content = QRResultView(
            payload: reading.payload,
            url: reading.url,
            strings: strings,
            copy: { [weak self] in self?.copy(reading.payload) },
            open: { [weak self] in reading.url.map { self?.open($0) } })
        let host = NSHostingController(rootView: content)
        host.view.layoutSubtreeIfNeeded()
        let size = host.view.fittingSize

        let panel = QRResultPanel(
            contentRect: CGRect(origin: .zero, size: size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false)
        panel.contentViewController = host
        panel.isReleasedWhenClosed = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary,
                                    .transient, .ignoresCycle]

        let visible = NSScreen.pointerVisibleFrame
        let pointer = NSEvent.mouseLocation
        // Sit just below the pointer, clamped fully on screen.
        var origin = CGPoint(x: pointer.x - size.width / 2, y: pointer.y - size.height - 18)
        origin.x = min(max(origin.x, visible.minX + 12), visible.maxX - size.width - 12)
        origin.y = min(max(origin.y, visible.minY + 12), visible.maxY - size.height - 12)
        panel.setFrame(CGRect(origin: origin, size: size), display: false)
        self.panel = panel

        installMonitors(for: panel)
        panel.alphaValue = 0
        panel.orderFrontRegardless()
        panel.makeKey()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.12
            panel.animator().alphaValue = 1
        }
    }

    func close() {
        if let keyMonitor {
            NSEvent.removeMonitor(keyMonitor)
            self.keyMonitor = nil
        }
        if let localMonitor {
            NSEvent.removeMonitor(localMonitor)
            self.localMonitor = nil
        }
        if let globalMonitor {
            NSEvent.removeMonitor(globalMonitor)
            self.globalMonitor = nil
        }
        panel?.orderOut(nil)
        panel = nil
    }

    private func copy(_ payload: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(payload, forType: .string)
        close()
        QuickToolHUD.show(icon: "qrcode", message: L10n.shared.s.ocrQRCopied)
    }

    private func open(_ url: URL) {
        close()
        NSWorkspace.shared.open(url)
    }

    private func installMonitors(for panel: NSPanel) {
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard event.window === panel else { return event }
            if Int(event.keyCode) == kVK_Escape {
                self?.close()
                return nil
            }
            return event
        }
        // A click anywhere outside the panel dismisses it. The global
        // monitor covers other apps; clicks on our own windows (the
        // screenshot editor under this panel) only reach the local one.
        localMonitor = NSEvent.addLocalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
            if event.window !== self?.panel { self?.close() }
            return event
        }
        globalMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            self?.close()
        }
    }
}

/// A non-activating panel that can still take key focus so its buttons and
/// selectable text respond without bringing the whole app forward.
private final class QRResultPanel: NSPanel {
    override var canBecomeKey: Bool { true }
}

private struct QRResultView: View {
    let payload: String
    let url: URL?
    let strings: Strings
    let copy: () -> Void
    let open: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 7) {
                Image(systemName: "qrcode")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
                Text(strings.qrResultTitle)
                    .font(.system(size: 13, weight: .semibold))
            }

            ScrollView(.vertical) {
                Text(payload)
                    .font(.system(size: 12.5))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(10)
            }
            .frame(maxHeight: 132)
            .fixedSize(horizontal: false, vertical: true)
            .background(Color.primary.opacity(0.05),
                        in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.1), lineWidth: 1)
            )

            HStack(spacing: 8) {
                Spacer(minLength: 0)
                if url != nil {
                    Button(strings.qrResultCopy, action: copy)
                        .buttonStyle(.bordered)
                    Button(strings.qrResultOpen, action: open)
                        .buttonStyle(.borderedProminent)
                        .keyboardShortcut(.defaultAction)
                } else {
                    Button(strings.qrResultCopy, action: copy)
                        .buttonStyle(.borderedProminent)
                        .keyboardShortcut(.defaultAction)
                }
            }
        }
        .padding(16)
        .frame(width: 320)
        .background(.regularMaterial,
                    in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.1), lineWidth: 1)
        )
    }
}

/// Erases the two button styles used above so they can share one modifier.
private struct AnyButtonStyle: PrimitiveButtonStyle {
    private let make: (Configuration) -> AnyView
    init(_ style: some PrimitiveButtonStyle) {
        make = { AnyView(Button($0).buttonStyle(style)) }
    }
    func makeBody(configuration: Configuration) -> some View { make(configuration) }
}
