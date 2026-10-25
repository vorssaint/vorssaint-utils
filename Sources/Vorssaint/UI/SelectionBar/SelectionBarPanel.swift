// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import SwiftUI

/// One button on the selection bar.
struct SelectionBarAction: Identifiable {
    let id: String
    let title: String
    let symbol: String
    var glyph: String? = nil
    let run: () -> Void
}

/// A tool's icon: its symbol, or its text glyph when it has one.
struct SelectionBarToolIcon: View {
    let symbol: String
    let glyph: String?

    var body: some View {
        if let glyph {
            Text(glyph).font(.system(size: 15, weight: .regular))
        } else {
            Image(systemName: symbol)
        }
    }
}

/// The floating bar next to a selection. It never activates and never takes
/// the keyboard: the app in front keeps its focus and its selection, so the
/// actions can copy or type over that selection.
///
/// Any key, click, scroll or app switch closes it, in other apps and in this
/// one. It also closes on its own after a few seconds, unless the pointer is
/// on it.
final class SelectionBarPanel {
    private static let lifetime: TimeInterval = 5

    private var panel: NSPanel?
    private var monitors: [Any] = []
    private var activationObserver: NSObjectProtocol?
    private var closeWork: DispatchWorkItem?

    var isVisible: Bool { panel?.isVisible == true }

    func show(_ actions: [SelectionBarAction], selection: CGRect?, pointer: CGPoint, visible: CGRect) {
        guard !actions.isEmpty else { return }
        let view = SelectionBarView(actions: actions,
                                    choose: { [weak self] action in
                                        self?.close()
                                        action.run()
                                    },
                                    hover: { [weak self] inside in
                                        inside ? self?.closeWork?.cancel() : self?.scheduleClose()
                                    })
        let host = FirstMouseHostingView(rootView: view)
        host.layoutSubtreeIfNeeded()
        let size = host.fittingSize
        let panel = ensurePanel()
        panel.contentView = host
        panel.setFrame(SelectionBarSupport.frame(size: size,
                                                 selection: selection,
                                                 pointer: pointer,
                                                 visible: visible),
                       display: true)
        panel.orderFrontRegardless()
        installMonitors()
        scheduleClose()
    }

    func close() {
        closeWork?.cancel()
        closeWork = nil
        removeMonitors()
        panel?.orderOut(nil)
        // A tool's own click handler calls this method, so the view it runs
        // in is freed later. The content holds the selected text, which must
        // not stay in memory after the bar is gone.
        DispatchQueue.main.async { [weak self] in
            guard let panel = self?.panel, !panel.isVisible else { return }
            panel.contentView = nil
        }
    }

    private func scheduleClose() {
        closeWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.close() }
        closeWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.lifetime, execute: work)
    }

    private func ensurePanel() -> NSPanel {
        if let panel { return panel }
        let panel = SelectionBarWindow(contentRect: .zero,
                                       styleMask: [.borderless, .nonactivatingPanel],
                                       backing: .buffered,
                                       defer: true)
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]
        panel.hidesOnDeactivate = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        // The bar works while another app is in front, so its tooltips must
        // too: they name each tool.
        panel.allowsToolTipsWhenApplicationIsInactive = true
        self.panel = panel
        return panel
    }

    // MARK: - Closing on outside input

    private func installMonitors() {
        guard monitors.isEmpty else { return }
        let mask: NSEvent.EventTypeMask = [.keyDown, .leftMouseDown, .rightMouseDown, .otherMouseDown,
                                           .scrollWheel]
        if let global = NSEvent.addGlobalMonitorForEvents(matching: mask, handler: { [weak self] _ in
            self?.close()
        }) {
            monitors.append(global)
        }
        // Global monitors only see events for other apps. This one sees
        // typing and clicks in this app's own windows. A click on the bar
        // itself goes to its buttons.
        if let local = NSEvent.addLocalMonitorForEvents(matching: mask, handler: { [weak self] event in
            if let self, event.window !== self.panel || event.type == .keyDown {
                self.close()
            }
            return event
        }) {
            monitors.append(local)
        }
        activationObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.close()
        }
    }

    private func removeMonitors() {
        monitors.forEach(NSEvent.removeMonitor)
        monitors.removeAll()
        if let activationObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(activationObserver)
        }
        activationObserver = nil
    }
}

/// The bar never becomes key, so the app in front keeps the keyboard.
private final class SelectionBarWindow: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

/// The first click on the bar must reach its button, not only bring the
/// window forward.
private final class FirstMouseHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

private struct SelectionBarView: View {
    let actions: [SelectionBarAction]
    let choose: (SelectionBarAction) -> Void
    let hover: (Bool) -> Void

    var body: some View {
        HStack(spacing: 2) {
            ForEach(actions) { action in
                SelectionBarButton(action: action, choose: choose)
            }
        }
        .padding(4)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.12), lineWidth: 0.5)
        }
        .onHover(perform: hover)
    }
}

private struct SelectionBarButton: View {
    let action: SelectionBarAction
    let choose: (SelectionBarAction) -> Void
    @State private var hovering = false

    var body: some View {
        Button {
            choose(action)
        } label: {
            SelectionBarToolIcon(symbol: action.symbol, glyph: action.glyph)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.primary)
                .frame(width: 30, height: 26)
                .background(Color.primary.opacity(hovering ? 0.08 : 0),
                            in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help(action.title)
        .accessibilityLabel(action.title)
    }
}
