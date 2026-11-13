// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation
import Carbon.HIToolbox

/// The production dismissal methods run against plain doubles. No AppKit
/// windows, native monitors or input events are created by this contract.
enum RecentCapturePanelTests {
    static var calls: [String] = []

    final class NSPanel {
        var isVisible = true
        weak var sheetParent: NSPanel?
        var attachedSheet: NSPanel?
        func endSheet(_ sheet: NSPanel) {
            calls.append("endSheet")
            if attachedSheet === sheet { attachedSheet = nil; sheet.sheetParent = nil }
        }
        func orderOut(_ sender: Any?) { calls.append("orderOut"); isVisible = false }
    }

    final class NSEvent {
        struct EventTypeMask: OptionSet {
            let rawValue: Int
            static let keyDown = Self(rawValue: 1)
            static let leftMouseDown = Self(rawValue: 2)
            static let rightMouseDown = Self(rawValue: 4)
        }
        static var local: [Int: (EventTypeMask, (NSEvent) -> NSEvent?)] = [:]
        static var global: [Int: (EventTypeMask, (NSEvent) -> Void)] = [:]
        static var nextToken = 0
        let type: EventTypeMask
        let window: NSPanel?
        let keyCode: UInt16
        init(_ type: EventTypeMask, window: NSPanel?, keyCode: UInt16 = 0) {
            self.type = type; self.window = window; self.keyCode = keyCode
        }
        static func addLocalMonitorForEvents(matching mask: EventTypeMask,
                                            handler: @escaping (NSEvent) -> NSEvent?) -> Any? {
            nextToken += 1; local[nextToken] = (mask, handler); return nextToken
        }
        static func addGlobalMonitorForEvents(matching mask: EventTypeMask,
                                             handler: @escaping (NSEvent) -> Void) -> Any? {
            nextToken += 1; global[nextToken] = (mask, handler); return nextToken
        }
        static func removeMonitor(_ token: Any) {
            guard let token = token as? Int else { return }
            calls.append("removeMonitor")
            local.removeValue(forKey: token); global.removeValue(forKey: token)
        }
        static func sendLocal(_ event: NSEvent) -> NSEvent? {
            guard let monitor = local.values.first(where: { $0.0.contains(event.type) }) else { return event }
            return monitor.1(event)
        }
        static func sendGlobal(_ event: NSEvent) {
            global.values.first(where: { $0.0.contains(event.type) })?.1(event)
        }
    }

    struct NSRunningApplication { let bundleIdentifier: String? }
    enum Bundle { static let main = NSRunningApplication(bundleIdentifier: "com.vorssaint.tests.captures") }
    enum AssistiveKeyboard { static let bundleID = "com.apple.accessibility.Keyboard" }
    enum NSWorkspace {
        static let shared = Workspace()
        static let didActivateApplicationNotification = Notification.Name("didActivateApplication")
        static let applicationUserInfoKey = "application"
        final class Workspace { let notificationCenter = Center() }
        final class Center {
            var token: NSObject?
            var handler: ((Notification) -> Void)?
            func addObserver(forName name: Notification.Name, object: Any?, queue: OperationQueue?,
                             using handler: @escaping (Notification) -> Void) -> NSObjectProtocol {
                let token = NSObject()
                self.token = token; self.handler = handler
                return token
            }
            func removeObserver(_ observer: NSObjectProtocol) {
                guard let observer = observer as? NSObject, observer === token else { return }
                calls.append("removeObserver")
                token = nil; handler = nil
            }
            func activate(_ bundleID: String?) {
                let info: [AnyHashable: Any]? = bundleID.map {
                    [NSWorkspace.applicationUserInfoKey: NSRunningApplication(bundleIdentifier: $0)]
                }
                handler?(Notification(name: NSWorkspace.didActivateApplicationNotification, userInfo: info))
            }
        }
    }

    class Fixture {
        var panel: NSPanel?
        var panelKeyMonitor: Any?
        var panelLocalClickMonitor: Any?
        var panelGlobalClickMonitor: Any?
        var panelActivationObserver: NSObjectProtocol?
        var monitorsRemoved: Bool {
            panelKeyMonitor == nil && panelLocalClickMonitor == nil && panelGlobalClickMonitor == nil
                && panelActivationObserver == nil && NSEvent.local.isEmpty && NSEvent.global.isEmpty
                && NSWorkspace.shared.notificationCenter.handler == nil
        }
    }

    private static func reset() {
        NSEvent.local = [:]; NSEvent.global = [:]; NSEvent.nextToken = 0
        NSWorkspace.shared.notificationCenter.handler = nil
        NSWorkspace.shared.notificationCenter.token = nil
        calls = []
    }

    private static func open() -> (Service, NSPanel, NSPanel) {
        reset()
        let service = Service(), panel = NSPanel(), sheet = NSPanel()
        service.panel = panel
        panel.attachedSheet = sheet; sheet.sheetParent = panel
        service.installPanelMonitors(for: panel)
        return (service, panel, sheet)
    }

    static func run(_ suite: TestSuite) {
        defer { reset() }
        let dismissal = ["removeMonitor", "removeMonitor", "removeMonitor", "removeObserver", "endSheet", "orderOut"]
        for button: NSEvent.EventTypeMask in [.leftMouseDown, .rightMouseDown] {
            for destination in ["palette", "own sheet", "another window", "another sheet", "no window"] {
                let (service, panel, sheet) = open()
                let other = NSPanel(), otherSheet = NSPanel()
                other.attachedSheet = otherSheet; otherSheet.sheetParent = other
                let target: NSPanel?
                switch destination {
                case "palette": target = panel
                case "own sheet": target = sheet
                case "another window": target = other
                case "another sheet": target = otherSheet
                default: target = nil
                }
                let event = NSEvent(button, window: target)
                let stays = destination == "palette" || destination == "own sheet"
                suite.expect(NSEvent.sendLocal(event) === event,
                             "a recent capture click in \(destination) is forwarded unchanged")
                suite.expect(panel.isVisible == stays && (panel.attachedSheet === sheet) == stays,
                             "a recent capture click keeps only the palette and its own confirmation open")
                suite.expect(stays ? calls.isEmpty : calls == dismissal,
                             "an outside click removes monitors and ends the confirmation before hiding")
                suite.expect(stays ? !service.monitorsRemoved : service.monitorsRemoved,
                             "recent capture monitors stay installed only while the palette stays open")
            }
        }

        let (keys, keyPanel, keySheet) = open()
        let sheetEscape = NSEvent(.keyDown, window: keySheet, keyCode: UInt16(kVK_Escape))
        suite.expect(NSEvent.sendLocal(sheetEscape) === sheetEscape && keyPanel.isVisible && calls.isEmpty,
                     "Escape in the confirmation is forwarded without closing the palette")
        let ordinaryKey = NSEvent(.keyDown, window: keyPanel, keyCode: UInt16(kVK_ANSI_A))
        suite.expect(NSEvent.sendLocal(ordinaryKey) === ordinaryKey && keyPanel.isVisible,
                     "ordinary palette keys continue to their receiver")
        keyPanel.endSheet(keySheet)
        calls = []
        suite.expect(NSEvent.sendLocal(NSEvent(.keyDown, window: keyPanel, keyCode: UInt16(kVK_Escape))) == nil
                     && !keyPanel.isVisible && keys.monitorsRemoved && calls == Array(dismissal.prefix(4)) + ["orderOut"],
                     "Escape closes the palette and consumes the key after the confirmation has ended")

        for button: NSEvent.EventTypeMask in [.leftMouseDown, .rightMouseDown] {
            let (service, panel, _) = open()
            NSEvent.sendGlobal(NSEvent(button, window: nil))
            suite.expect(!panel.isVisible && service.monitorsRemoved && calls == dismissal,
                         "a click in another app ends the confirmation and removes all palette monitors")
        }

        let (service, panel, sheet) = open()
        for app in [Bundle.main.bundleIdentifier, AssistiveKeyboard.bundleID, nil] {
            NSWorkspace.shared.notificationCenter.activate(app)
            suite.expect(panel.isVisible && calls.isEmpty,
                         "own activation, the accessibility keyboard and missing activation data keep the palette open")
        }
        NSWorkspace.shared.notificationCenter.activate("com.example.other-app")
        suite.expect(!panel.isVisible && service.monitorsRemoved && calls == dismissal && sheet.sheetParent == nil,
                     "another app's activation closes the palette and detaches its confirmation")
        panel.isVisible = true
        service.installPanelMonitors(for: panel)
        suite.expect(panel.attachedSheet == nil && NSEvent.local.count == 2 && NSEvent.global.count == 1
                     && NSWorkspace.shared.notificationCenter.handler != nil,
                     "reusing the palette installs fresh monitors without carrying its old confirmation")
        service.hideHistoryWindow()
    }
}
