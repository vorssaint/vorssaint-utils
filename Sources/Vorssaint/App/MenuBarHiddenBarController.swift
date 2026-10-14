// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit

private final class OrganizerBarPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

private final class OrganizerBarButton: NSButton {
    var invoke: (() -> Void)?
    var contextMenuTracking: ((Bool) -> Void)?
    @objc func pressed() { invoke?() }
    override func rightMouseDown(with event: NSEvent) {
        guard let menu else { return }
        contextMenuTracking?(true)
        defer { contextMenuTracking?(false) }
        NSMenu.popUpContextMenu(menu, with: event, for: self)
    }
    override func mouseDown(with event: NSEvent) {
        if event.modifierFlags.contains(.control) { rightMouseDown(with: event) }
        else { super.mouseDown(with: event) }
    }
}

/// A small horizontal shelf anchored below the system menu bar. Its controls
/// open the real status items; it is not a launcher for ordinary applications.
final class MenuBarHiddenBarController {
    private var panel: NSPanel?
    private var barAppearance: MenuBarHiddenBarAppearance?
    private var localMonitor: Any?
    private var globalMonitor: Any?
    private var anchorFrame: CGRect?
    private var shownAt: TimeInterval = 0
    private var isTrackingContextMenu = false
    var onDismiss: (() -> Void)?

    func show(items: [OrganizerMenuBarItem], anchor: NSStatusBarButton?, message: String?,
              needsAccessibility: Bool, activate: @escaping (OrganizerMenuBarItem) -> Void,
              menu: (OrganizerMenuBarItem) -> NSMenu) {
        hide()
        let text = MenuBarOrganizerStrings.localized(L10n.shared.language)
        let anchorRect = anchor.flatMap { button in
            button.window.map { $0.convertToScreen(button.convert(button.bounds, to: nil)) }
        }.flatMap { StatusItemAnchorSupport.isTrustworthyStatusFrame($0) ? $0 : nil }
        let screen = anchorRect.flatMap { rect in NSScreen.screens.first { $0.frame.contains(CGPoint(x: rect.midX, y: rect.midY)) } }
            ?? NSScreen.screens.first { $0.frame.contains(NSEvent.mouseLocation) } ?? NSScreen.main
        guard let screen else { return }
        anchorFrame = anchorRect
        let row = NSStackView()
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 4
        // Status items keep their physical order on the right of macOS in
        // either language, just like the real bar and its Command-drag order.
        row.userInterfaceLayoutDirection = .leftToRight
        for item in items {
            let icon = item.application.icon?.copy() as? NSImage
            icon?.size = NSSize(width: 18, height: 18)
            let button = OrganizerBarButton(image: icon ?? NSImage(),
                                             target: nil, action: #selector(OrganizerBarButton.pressed))
            button.target = button
            button.invoke = { activate(item) }
            button.isBordered = false
            button.imageScaling = .scaleProportionallyDown
            button.toolTip = item.name
            button.setAccessibilityLabel(item.name)
            button.menu = menu(item)
            button.contextMenuTracking = { [weak self] in self?.isTrackingContextMenu = $0 }
            let width = min(max(item.descriptor.frame.width, 28), 100)
            button.widthAnchor.constraint(equalToConstant: width).isActive = true
            button.heightAnchor.constraint(equalToConstant: 30).isActive = true
            row.addArrangedSubview(button)
        }
        if items.isEmpty || message != nil {
            let label = NSTextField(labelWithString: message ?? text.noHiddenItems)
            label.font = .systemFont(ofSize: 12)
            label.textColor = .secondaryLabelColor
            label.maximumNumberOfLines = 2
            label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
            row.addArrangedSubview(label)
        }
        if needsAccessibility {
            let button = OrganizerBarButton(title: text.grantAccessibility, target: nil,
                                             action: #selector(OrganizerBarButton.pressed))
            button.target = button
            button.invoke = { Permissions.shared.requestAccessibility() }
            button.bezelStyle = .rounded
            row.addArrangedSubview(button)
        }
        let contentWidth = max(48, row.fittingSize.width)
        let size = CGSize(width: min(contentWidth + 16, screen.frame.width - 16), height: 44)
        let frame = MenuBarItemSupport.barFrame(size: size,
            anchorX: anchorRect?.midX ?? min(max(NSEvent.mouseLocation.x, screen.frame.minX), screen.frame.maxX),
            screen: screen.frame, menuBarHeight: max(NSStatusBar.system.thickness, screen.frame.maxY - screen.visibleFrame.maxY))
        let panel = OrganizerBarPanel(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel],
                                      backing: .buffered, defer: false)
        panel.title = text.hiddenBar
        panel.setAccessibilityLabel(text.hiddenBar)
        panel.isReleasedWhenClosed = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = .popUpMenu
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]
        let barAppearance = MenuBarHiddenBarAppearance(frame: frame, anchor: anchor)
        let background = barAppearance.view
        let scroll = NSScrollView(frame: background.bounds.insetBy(dx: 8, dy: 6))
        scroll.drawsBackground = false
        scroll.hasHorizontalScroller = false
        scroll.hasVerticalScroller = false
        row.frame = CGRect(x: 0, y: 0, width: contentWidth, height: 32)
        scroll.documentView = row
        barAppearance.contentView.addSubview(scroll)
        panel.contentView = background
        self.panel = panel
        self.barAppearance = barAppearance
        barAppearance.follow(panel: panel)
        shownAt = ProcessInfo.processInfo.systemUptime
        panel.makeKeyAndOrderFront(nil)
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .keyDown]) { [weak self] event in
            guard let self else { return event }
            if event.type == .keyDown, event.keyCode == 53 {
                self.dismiss()
                return nil
            }
            if event.type != .keyDown { self.dismissIfOutside(event) }
            return event
        }
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
            self?.dismissIfOutside(event)
        }
    }

    func hide() {
        barAppearance?.stop()
        barAppearance = nil
        if let localMonitor { NSEvent.removeMonitor(localMonitor) }
        if let globalMonitor { NSEvent.removeMonitor(globalMonitor) }
        localMonitor = nil
        globalMonitor = nil
        panel?.orderOut(nil)
        panel = nil
        anchorFrame = nil
    }

    private func dismissIfOutside(_ event: NSEvent) {
        // The click that opened a menu can reach a global monitor after the
        // menu's action presents this panel. Ignore that older event.
        guard event.timestamp > shownAt, !isTrackingContextMenu, let panel else { return }
        // Local mouse events carry the destination window and their original
        // position. The current cursor may already have moved elsewhere by the
        // time a monitor runs; never dismiss a click delivered to this panel.
        guard event.window !== panel else { return }
        let point = event.window.map { $0.convertPoint(toScreen: event.locationInWindow) }
            ?? event.locationInWindow
        guard !panel.frame.contains(point), anchorFrame?.contains(point) != true else { return }
        dismiss()
    }

    private func dismiss() {
        hide()
        onDismiss?()
    }

    deinit { hide() }
}
