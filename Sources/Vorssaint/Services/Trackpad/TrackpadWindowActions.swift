// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import ApplicationServices

final class TrackpadWindowActions {
    static let shared = TrackpadWindowActions()

    private struct FilledWindow {
        let window: AXUIElement
        let filled: CGRect
        let previous: CGRect
    }

    private static let messagingTimeout: Float = 0.5
    private static let unquittableBundleIDs: Set<String> = ["com.apple.finder"]

    private var filledWindow: FilledWindow?

    private init() {}

    @discardableResult
    func perform(_ action: TrackpadCornerAction) -> Bool {
        guard AXIsProcessTrusted(), let app = NSWorkspace.shared.frontmostApplication, !app.isTerminated else {
            return false
        }
        switch action {
        case .hideApp:
            return app.hide()
        case .quitApp:
            guard app.processIdentifier != ProcessInfo.processInfo.processIdentifier,
                  !Self.unquittableBundleIDs.contains(app.bundleIdentifier ?? "") else { return false }
            return app.terminate()
        case .closeWindow:
            guard let window = focusedWindow(of: app),
                  let button = element(window, kAXCloseButtonAttribute) else { return false }
            return AXUIElementPerformAction(button, kAXPressAction as CFString) == .success
        case .minimizeWindow:
            guard let window = focusedWindow(of: app) else { return false }
            return AXUIElementSetAttributeValue(window, kAXMinimizedAttribute as CFString,
                                                kCFBooleanTrue) == .success
        case .fullScreen:
            guard let window = focusedWindow(of: app) else { return false }
            let isFullScreen = bool(window, "AXFullScreen")
            let flipped = (isFullScreen ? kCFBooleanFalse : kCFBooleanTrue) as CFTypeRef
            return AXUIElementSetAttributeValue(window, "AXFullScreen" as CFString, flipped) == .success
        case .fillScreen:
            guard let window = focusedWindow(of: app) else { return false }
            return toggleFill(window)
        default:
            return false
        }
    }

    private func toggleFill(_ window: AXUIElement) -> Bool {
        guard !bool(window, "AXFullScreen"), let current = frame(of: window),
              let primaryHeight = NSScreen.screens.first?.frame.height else { return false }
        let center = CGPoint(x: current.midX, y: primaryHeight - current.midY)
        guard let screen = NSScreen.screens.first(where: { $0.frame.contains(center) }) ?? NSScreen.main else {
            return false
        }
        let filled = TrackpadWindowFrames.axFrame(fromAppKit: screen.visibleFrame, primaryScreenHeight: primaryHeight)
        let remembered = filledWindow.flatMap { CFEqual($0.window, window) ? $0 : nil }
        let target = TrackpadWindowFrames.fillTarget(current: current, screenFill: filled,
                                                     rememberedFill: remembered?.filled,
                                                     previous: remembered?.previous)
        guard setFrame(target, on: window) else { return false }
        if let remembered, target == remembered.previous {
            filledWindow = nil
        } else {
            filledWindow = FilledWindow(window: window, filled: frame(of: window) ?? target, previous: current)
        }
        return true
    }

    private func focusedWindow(of app: NSRunningApplication) -> AXUIElement? {
        let element = AXUIElementCreateApplication(app.processIdentifier)
        AXUIElementSetMessagingTimeout(element, Self.messagingTimeout)
        return self.element(element, kAXFocusedWindowAttribute) ?? self.element(element, kAXMainWindowAttribute)
    }

    private func element(_ element: AXUIElement, _ attribute: String) -> AXUIElement? {
        var raw: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &raw) == .success,
              let raw, CFGetTypeID(raw) == AXUIElementGetTypeID() else { return nil }
        return unsafeDowncast(raw, to: AXUIElement.self)
    }

    private func bool(_ element: AXUIElement, _ attribute: String) -> Bool {
        var raw: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &raw) == .success else { return false }
        return (raw as? NSNumber)?.boolValue ?? false
    }

    private func frame(of window: AXUIElement) -> CGRect? {
        var positionRaw: CFTypeRef?
        var sizeRaw: CFTypeRef?
        guard AXUIElementCopyAttributeValue(window, kAXPositionAttribute as CFString, &positionRaw) == .success,
              AXUIElementCopyAttributeValue(window, kAXSizeAttribute as CFString, &sizeRaw) == .success,
              let positionRaw, let sizeRaw,
              CFGetTypeID(positionRaw) == AXValueGetTypeID(), CFGetTypeID(sizeRaw) == AXValueGetTypeID()
        else { return nil }
        var origin = CGPoint.zero
        var size = CGSize.zero
        guard AXValueGetValue(unsafeDowncast(positionRaw, to: AXValue.self), .cgPoint, &origin),
              AXValueGetValue(unsafeDowncast(sizeRaw, to: AXValue.self), .cgSize, &size) else { return nil }
        return CGRect(origin: origin, size: size)
    }

    private func setFrame(_ rect: CGRect, on window: AXUIElement) -> Bool {
        var origin = rect.origin
        var size = rect.size
        guard let position = AXValueCreate(.cgPoint, &origin), let dimensions = AXValueCreate(.cgSize, &size) else {
            return false
        }
        let moved = AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, position) == .success
        let resized = AXUIElementSetAttributeValue(window, kAXSizeAttribute as CFString, dimensions) == .success
        _ = AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, position)
        return moved || resized
    }
}
