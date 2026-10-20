// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit

/// Handles side buttons before the hosted SwiftUI controls can consume them.
class SettingsWindow: NSWindow, NSToolbarDelegate {
    var router = SettingsRouter.shared
    // The app supplies capture state without making the window own a global input service.
    var isMouseButtonCaptureActive: () -> Bool = { false }
    private var navigationButtons: Set<Int> = []
    private var sidebarAction: (() -> Void)?
    private var toolbarState = ""
    private var sidebarItem: NSToolbarItem?
    private var backItem: NSToolbarItem?
    private var forwardItem: NSToolbarItem?
    private var titleItem: NSToolbarItem?
    private var toolbarIsRTL = false
    private static let sidebarIdentifier = NSToolbarItem.Identifier("VorssaintSettingsSidebar")
    private static let backIdentifier = NSToolbarItem.Identifier("VorssaintSettingsBack")
    private static let forwardIdentifier = NSToolbarItem.Identifier("VorssaintSettingsForward")
    private static let titleIdentifier = NSToolbarItem.Identifier("VorssaintSettingsTitle")

    /// AppKit owns the window chrome. Explicit physical item order prevents
    /// SwiftUI's RTL toolbar placement from leaving the header on the left.
    func configureToolbar(language: AppLanguage, sidebarShown: Bool,
                          canGoBack: Bool, canGoForward: Bool, toggleSidebar: @escaping () -> Void) {
        sidebarAction = toggleSidebar
        let state = "\(language.rawValue)/\(sidebarShown)/\(canGoBack)/\(canGoForward)"
        guard toolbarState != state else { return }
        toolbarState = state
        let directionChanged = toolbarIsRTL != language.isRightToLeft
        toolbarIsRTL = language.isRightToLeft
        let strings = SettingsNavigationStrings.localized(language)
        let titleString = Strings.localized(language).settingsTitle
        func item(_ identifier: NSToolbarItem.Identifier, action: Selector) -> NSToolbarItem {
            let item = NSToolbarItem(itemIdentifier: identifier)
            item.target = self
            item.action = action
            item.autovalidates = false
            return item
        }
        let isNewToolbar = sidebarItem == nil
        if isNewToolbar {
            // Let AppKit size and draw the controls, as it does for the original
            // SwiftUI toolbar. Custom button frames change the native chrome.
            sidebarItem = item(Self.sidebarIdentifier, action: #selector(toggleToolbarSidebar(_:)))
            backItem = item(Self.backIdentifier, action: #selector(goBack(_:)))
            forwardItem = item(Self.forwardIdentifier, action: #selector(goForward(_:)))
            let titleItem = NSToolbarItem(itemIdentifier: Self.titleIdentifier)
            titleItem.view = NSTextField(labelWithString: titleString)
            self.titleItem = titleItem
            let toolbar = NSToolbar(identifier: "VorssaintSettingsToolbar")
            toolbar.delegate = self
            toolbar.displayMode = .iconOnly
            toolbar.allowsUserCustomization = false
            self.toolbar = toolbar
        }
        guard let sidebarItem, let back = backItem, let forward = forwardItem,
              let title = titleItem?.view as? NSTextField else { return }
        func update(_ item: NSToolbarItem, symbol: String, label: String, enabled: Bool = true) {
            item.image = NSImage(systemSymbolName: symbol, accessibilityDescription: label)
            item.label = label
            item.toolTip = label
            item.isEnabled = enabled
        }
        update(sidebarItem, symbol: toolbarIsRTL ? "sidebar.right" : "sidebar.left",
               label: sidebarShown ? strings.hideSidebar : strings.showSidebar)
        update(back, symbol: toolbarIsRTL ? "chevron.right" : "chevron.left",
               label: strings.back, enabled: canGoBack)
        update(forward, symbol: toolbarIsRTL ? "chevron.left" : "chevron.right",
               label: strings.forward, enabled: canGoForward)
        for item in [sidebarItem, back, forward] { item.isNavigational = !toolbarIsRTL }
        title.stringValue = titleString
        title.setAccessibilityLabel(titleString)
        title.font = .titleBarFont(ofSize: 0)
        title.alignment = toolbarIsRTL ? .right : .left
        let paragraph = NSMutableParagraphStyle()
        paragraph.baseWritingDirection = toolbarIsRTL ? .rightToLeft : .leftToRight
        paragraph.alignment = title.alignment
        title.attributedStringValue = NSAttributedString(string: title.stringValue,
            attributes: [.paragraphStyle: paragraph, .font: title.font!])
        titleItem?.label = titleString
        // Replacing NSToolbar on every history update interrupts native titlebar
        // layout. Keep it alive and reorder only when the language changes direction.
        if directionChanged && !isNewToolbar, let toolbar {
            for index in toolbar.items.indices.reversed() { toolbar.removeItem(at: index) }
            for (index, identifier) in toolbarDefaultItemIdentifiers(toolbar).enumerated() {
                toolbar.insertItem(withItemIdentifier: identifier, at: index)
            }
        }
        titleVisibility = toolbarIsRTL ? .hidden : .visible
    }

    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        toolbarIsRTL
            ? [.flexibleSpace, Self.titleIdentifier, Self.forwardIdentifier, Self.backIdentifier, Self.sidebarIdentifier]
            : [Self.sidebarIdentifier, Self.backIdentifier, Self.forwardIdentifier, .flexibleSpace]
    }

    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [Self.sidebarIdentifier, Self.backIdentifier, Self.forwardIdentifier, Self.titleIdentifier, .flexibleSpace]
    }

    func toolbar(_ toolbar: NSToolbar, itemForItemIdentifier itemIdentifier: NSToolbarItem.Identifier,
                 willBeInsertedIntoToolbar flag: Bool) -> NSToolbarItem? {
        switch itemIdentifier {
        case Self.sidebarIdentifier: return sidebarItem
        case Self.backIdentifier: return backItem
        case Self.forwardIdentifier: return forwardItem
        case Self.titleIdentifier: return titleItem
        default: return nil
        }
    }

    @objc private func toggleToolbarSidebar(_ sender: Any?) { sidebarAction?() }

    static func navigationMenu(language: AppLanguage) -> NSMenu {
        let strings = SettingsNavigationStrings.localized(language)
        let menu = NSMenu(title: strings.go)
        // The commands other apps declare for Back and Forward, so the key macOS
        // moves them to on this keyboard is the one the side buttons look for.
        menu.addItem(NSMenuItem(title: strings.back, action: #selector(goBack(_:)),
                                keyEquivalent: MouseNavigationSupport.commandCharacter(for: .back)))
        menu.addItem(NSMenuItem(title: strings.forward, action: #selector(goForward(_:)),
                                keyEquivalent: MouseNavigationSupport.commandCharacter(for: .forward)))
        return menu
    }

    /// The Go item for a direction, wherever `navigationMenu` sits in `mainMenu`.
    static func navigationItem(for direction: MouseNavigationDirection, in mainMenu: NSMenu) -> NSMenuItem? {
        let action = direction == .back ? #selector(goBack(_:)) : #selector(goForward(_:))
        for menu in mainMenu.items.compactMap(\.submenu) {
            if let item = menu.items.first(where: { $0.action == action }) { return item }
        }
        return nil
    }

    private var canNavigate: Bool {
        isKeyWindow && attachedSheet == nil && NSApp.modalWindow == nil && !isMouseButtonCaptureActive()
    }

    private func isPageVisible(_ page: SettingsPage) -> Bool {
        FeatureVisibilitySupport.isPageVisible(page, isAvailable: { $0.isAvailable })
    }

    override func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        switch menuItem.action {
        case #selector(goBack(_:)): return canNavigate && router.canGoBack(isPageVisible: isPageVisible)
        case #selector(goForward(_:)): return canNavigate && router.canGoForward(isPageVisible: isPageVisible)
        default: return super.validateMenuItem(menuItem)
        }
    }

    @objc func goBack(_ sender: Any?) {
        guard canNavigate else { return }
        router.goBack(isPageVisible: isPageVisible)
    }

    @objc func goForward(_ sender: Any?) {
        guard canNavigate else { return }
        router.goForward(isPageVisible: isPageVisible)
    }

    override func sendEvent(_ event: NSEvent) {
        switch event.type {
        case .otherMouseDown:
            let button = Int64(event.buttonNumber)
            guard canNavigate,
                  let direction = MouseNavigationSupport.direction(forButtonNumber: button),
                  !RadialMenuSupport.claimsMouseButton(button),
                  !MouseButtonShortcutSupport.claimsButton(button) else {
                super.sendEvent(event)
                return
            }
            navigationButtons.insert(event.buttonNumber)
            switch direction {
            case .back: goBack(nil)
            case .forward: goForward(nil)
            }
        case .otherMouseUp:
            // Keep the entire gesture together, even if navigation changes focus.
            if navigationButtons.remove(event.buttonNumber) != nil { return }
            super.sendEvent(event)
        case .otherMouseDragged:
            if navigationButtons.contains(event.buttonNumber) { return }
            super.sendEvent(event)
        default:
            super.sendEvent(event)
        }
    }
}
