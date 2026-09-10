// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit

/// Handles side buttons before the hosted SwiftUI controls can consume them.
final class SettingsWindow: NSWindow {
    var router = SettingsRouter.shared
    // The app supplies capture state without making the window own a global input service.
    var isMouseButtonCaptureActive: () -> Bool = { false }
    private var navigationButtons: Set<Int> = []

    static func navigationMenu(language: AppLanguage) -> NSMenu {
        let strings = SettingsNavigationStrings.localized(language)
        let menu = NSMenu(title: strings.go)
        menu.addItem(NSMenuItem(title: strings.back, action: #selector(goBack(_:)), keyEquivalent: "["))
        menu.addItem(NSMenuItem(title: strings.forward, action: #selector(goForward(_:)), keyEquivalent: "]"))
        return menu
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
