// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit

/// Captured before the temporary Dock preference can change any window bounds.
/// Keep all visible windows so moving between Dock icons retains the same baseline.
struct DockPreviewFrameRestoration {
    private let windows: [[String: Any]]
    private let screens: [Screen]

    private struct Screen {
        let id: CGDirectDisplayID
        let frame: CGRect
        let visibleFrame: CGRect
    }

    init() {
        windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements],
                                             kCGNullWindowID) as? [[String: Any]] ?? []
        screens = NSScreen.screens.compactMap { screen in
            guard let id = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber
            else { return nil }
            return Screen(id: id.uint32Value, frame: Self.axFrame(screen.frame),
                          visibleFrame: Self.axFrame(screen.visibleFrame))
        }
    }

    func restoration(for item: SwitcherItem, isCurrent: @escaping () -> Bool) -> (() -> Void)? {
        guard let windowID = item.windowID, !item.isFullscreen, !item.isMinimized,
              !item.isOnHiddenSpace,
              let window = windows.first(where: {
                  ($0[kCGWindowNumber as String] as? NSNumber)?.uint32Value == windowID
                      && ($0[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value == item.windowOwnerPID
              }),
              let bounds = window[kCGWindowBounds as String] as? [String: Any],
              let original = CGRect(dictionaryRepresentation: bounds as CFDictionary),
              let screen = screens.first(where: { $0.visibleFrame.contains(original) }),
              let currentScreen = Self.screen(screen.id)
        else { return nil }
        let heldVisibleFrame = Self.axFrame(currentScreen.visibleFrame)
        guard heldVisibleFrame != screen.visibleFrame,
              !heldVisibleFrame.contains(original) else { return nil }

        // Activation is immediate. Repair only after the work area has recovered,
        // and only if this exact window still owns focus and was Dock-constrained.
        return {
            Self.restore(item, original: original, screen: screen,
                         heldVisibleFrame: heldVisibleFrame, isCurrent: isCurrent, attempt: 0)
        }
    }

    private static func restore(_ item: SwitcherItem, original: CGRect, screen: Screen,
                                heldVisibleFrame: CGRect, isCurrent: @escaping () -> Bool, attempt: Int) {
        DispatchQueue.main.asyncAfter(deadline: .now() + (attempt == 0 ? 0.15 : 0.05)) {
            guard isCurrent(), let currentScreen = Self.screen(screen.id),
                  axFrame(currentScreen.frame) == screen.frame,
                  NSWorkspace.shared.frontmostApplication?.processIdentifier == item.pid,
                  WindowActivator.focusedWindowID(for: item.windowOwnerPID) == item.windowID
            else { return }
            guard axFrame(currentScreen.visibleFrame) == screen.visibleFrame else {
                if attempt < 15 {
                    restore(item, original: original, screen: screen,
                            heldVisibleFrame: heldVisibleFrame, isCurrent: isCurrent, attempt: attempt + 1)
                }
                return
            }
            WindowActivator.restoreFrameAfterDockHold(item, original: original,
                                                      heldVisibleFrame: heldVisibleFrame)
        }
    }

    private static func screen(_ id: CGDirectDisplayID) -> NSScreen? {
        NSScreen.screens.first {
            ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value == id
        }
    }

    private static func axFrame(_ rect: CGRect) -> CGRect {
        let top = NSScreen.screens.first?.frame.maxY ?? 0
        return CGRect(x: rect.minX, y: top - rect.maxY, width: rect.width, height: rect.height)
    }
}
