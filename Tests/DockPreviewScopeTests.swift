// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// Production observation methods, with an isolated notification center. No
/// windows, system notifications, desktop changes or synthetic input are used.
enum DockPreviewScopeTests {
    struct SwitcherItem { let windowID: UInt32? }
    enum WindowEnumerator {
        typealias SwitcherItem = DockPreviewScopeTests.SwitcherItem
        typealias UserDefaults = DockPreviewScopeTests.UserDefaults
        typealias DefaultsKey = DockPreviewScopeTests.DefaultsKey
        typealias SpaceWindowBridge = DockPreviewScopeTests.SpaceWindowBridge
    }
    enum DefaultsKey { static let dockPreviewCurrentSpaceOnly = "scope" }
    final class UserDefaults {
        static let standard = UserDefaults()
        var scope = false
        func bool(forKey key: String) -> Bool { scope }
    }
    enum SpaceWindowBridge {
        static var hidden = false
        static var queries = 0
        static func isParkedOnHiddenSpace(_ id: UInt32) -> Bool {
            queries += 1
            return hidden
        }
    }

    enum NSWorkspace {
        static let shared = Workspace()
        static let activeSpaceDidChangeNotification = Notification.Name("test.desktop.changed")
    }

    final class Workspace {
        let notificationCenter = NotificationCenter()
    }

    final class Service {
        typealias NSWorkspace = DockPreviewScopeTests.NSWorkspace
        var isRunning = false
        var currentSpaceOnly = false
        var isDraggingWindow = false
        var spaceChangeObserver: NSObjectProtocol?
        var sessionEnds = 0
        var pendingHover = false
        var windows = [1]

        func endSession() {
            sessionEnds += 1
            pendingHover = false
            windows = []
        }
    }

    static func run(_ expect: (Bool, String) -> Void) {
        let item = SwitcherItem(windowID: 1)
        UserDefaults.standard.scope = true
        SpaceWindowBridge.hidden = false
        expect(WindowEnumerator.dockPreviewMayActivate(item), "a current-desktop window can be selected")
        SpaceWindowBridge.hidden = true
        expect(!WindowEnumerator.dockPreviewMayActivate(item),
               "a window moved off desktop cannot be selected before the panel refreshes")
        UserDefaults.standard.scope = false
        SpaceWindowBridge.queries = 0
        expect(WindowEnumerator.dockPreviewMayActivate(item) && SpaceWindowBridge.queries == 0,
               "all-desktop mode allows travel without an extra scope query")
        UserDefaults.standard.scope = true
        SpaceWindowBridge.hidden = false
        expect(WindowEnumerator.dockPreviewMayActivate(item),
               "returning to the window's desktop restores selection without stale history")

        let service = Service()
        let center = NSWorkspace.shared.notificationCenter
        func changeDesktop() {
            center.post(name: NSWorkspace.activeSpaceDidChangeNotification, object: nil)
        }
        service.currentSpaceOnly = true
        service.syncSpaceObservation()
        expect(service.spaceChangeObserver == nil, "a disabled preview does not observe desktop changes")
        service.isRunning = true
        service.syncSpaceObservation()
        service.syncSpaceObservation()
        service.pendingHover = true
        changeDesktop()
        expect(service.sessionEnds == 1 && service.windows.isEmpty && !service.pendingHover,
               "one desktop change dismisses the old list and invalidates its prefetched hover exactly once")
        service.windows = [2]
        service.syncSpaceObservation()
        changeDesktop()
        expect(service.sessionEnds == 2 && service.windows.isEmpty,
               "changing another preference cannot leave the next desktop list stale")
        service.isDraggingWindow = true
        changeDesktop()
        expect(service.sessionEnds == 2, "a window being dragged can still be carried to another desktop")
        service.isDraggingWindow = false
        service.currentSpaceOnly = false
        service.syncSpaceObservation()
        changeDesktop()
        expect(service.spaceChangeObserver == nil && service.sessionEnds == 2,
               "all-desktop previews keep their session and stop observing desktop changes")
        service.currentSpaceOnly = true
        service.syncSpaceObservation()
        service.isRunning = false
        changeDesktop()
        expect(service.sessionEnds == 2, "a queued desktop notification cannot act after disabling previews")
        service.stopSpaceObservation()
        expect(service.spaceChangeObserver == nil, "stopping the tap removes desktop observation")
        service.isRunning = true
        service.syncSpaceObservation()
        changeDesktop()
        expect(service.sessionEnds == 3, "re-enabling scoped previews restores exactly one observer")
        service.stopSpaceObservation()
    }
}
