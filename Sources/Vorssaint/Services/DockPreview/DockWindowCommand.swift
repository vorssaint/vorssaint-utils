// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import ApplicationServices

@objc(DockWindowCommand)
final class DockWindowCommand: NSScriptCommand {
    override func performDefaultImplementation() -> Any? {
        do {
            guard Thread.isMainThread, AppFeature.dockPreview.isAvailable, DockOption.automation.bool,
                  UserDefaults.standard.bool(forKey: DefaultsKey.dockPreviewEnabled), SessionActivity.shared.isActive else {
                throw failure(-1708, "Enable Dock previews and the AppleScript API before using window commands.")
            }
            guard AXIsProcessTrusted() else { throw failure(-1743, "Accessibility permission is required.") }
            guard let command = directParameter as? String else { throw failure(-1700, "Expected a command name.") }
            let arguments = try DockScriptSupport.arguments(evaluatedArguments?["parameters"] as? String ?? "{}")
            let result = try execute(command, arguments: arguments)
            let data = try JSONSerialization.data(withJSONObject: result, options: [.sortedKeys])
            return String(decoding: data, as: UTF8.self)
        } catch let error as NSError {
            scriptErrorNumber = error.code; scriptErrorString = error.localizedDescription; return nil
        }
    }
    private func failure(_ code: Int, _ text: String) -> NSError {
        NSError(domain: "Vorssaint.WindowAPI", code: code, userInfo: [NSLocalizedDescriptionKey: text])
    }
    private func windows() -> [SwitcherItem] {
        WindowEnumerator.listWindowsForCommandBar(snapshot: WindowEnumerator.snapshot()).filter { $0.windowID != nil && $0.pid != getpid() }
    }
    private func record(_ item: SwitcherItem) -> [String: Any] {
        ["id": item.windowID ?? 0, "pid": item.pid, "ownerPID": item.windowOwnerPID,
         "title": item.title, "app": item.appName, "minimized": item.isMinimized,
         "fullscreen": item.isFullscreen, "hidden": item.isAppHidden, "onScreen": item.isOnScreen,
         "spaces": item.windowID.map { SpaceWindowBridge.spaces(of: $0) } ?? [],
         "frame": ["x": item.frame.minX, "y": item.frame.minY, "width": item.frame.width, "height": item.frame.height]]
    }
    private func execute(_ command: String, arguments: [String: Any]) throws -> [String: Any] {
        switch command {
        case "windows": return ["windows": windows().map(record)]
        case "apps":
            return ["apps": NSWorkspace.shared.runningApplications.filter { $0.activationPolicy == .regular && !$0.isTerminated && $0.processIdentifier != getpid() }.map {
                ["pid": $0.processIdentifier, "name": $0.localizedName ?? "", "bundleIdentifier": $0.bundleIdentifier ?? "", "active": $0.isActive, "hidden": $0.isHidden] as [String: Any]
            }]
        case "activeWindow":
            let front = NSWorkspace.shared.frontmostApplication?.processIdentifier
            let focused = front.flatMap { WindowActivator.focusedWindowID(for: $0) }
            return ["window": windows().first(where: { $0.windowID == focused }).map(record) ?? [:]]
        case "showSwitcher":
            guard AppFeature.switcher.isAvailable, AppSwitcher.shared.openExternalSession() else { throw failure(-1708, "Enable the window switcher first.") }
        case "cycleSwitcher":
            guard let delta = arguments["delta"] as? Int, [-1, 1].contains(delta), AppFeature.switcher.isAvailable, AppSwitcher.shared.keyboardInputOwnership.isOwned else { throw failure(-1700, "delta must be -1 or 1.") }
            AppSwitcher.shared.cycleExternalSession(by: delta)
        case "commitSwitcher":
            guard AppFeature.switcher.isAvailable, AppSwitcher.shared.keyboardInputOwnership.isOwned else { throw failure(-1708, "The window switcher is unavailable or closed.") }; AppSwitcher.shared.commitExternalSession()
        case "hidePreviews": DockPreviewService.shared.hideAllPreviews(); DockAdditionsRuntime.shared.dismissWidget()
        case "showPreview":
            guard let id = DockScriptSupport.identifier(arguments["pid"]), id <= UInt32(Int32.max),
                  let app = NSRunningApplication(processIdentifier: pid_t(id)), !app.isTerminated, app.activationPolicy == .regular, id != UInt32(getpid()),
                  let screen = NSScreen.main else { throw failure(-1728, "The requested app is not running.") }
            let dockAnchor = DockAccessibility.items().first(where: { DockAccessibility.application(for: $0)?.processIdentifier == app.processIdentifier })?.frame
            let anchor = dockAnchor ?? CGRect(x: screen.visibleFrame.midX - 20, y: screen.visibleFrame.minY + 20, width: 40, height: 40)
            DockPreviewService.shared.show(for: app, anchor: anchor, external: true, centeredPlacement: dockAnchor == nil)
        default:
            guard let id = DockScriptSupport.identifier(arguments["id"]), let item = windows().first(where: { $0.windowID == id }) else { throw failure(-1728, "The requested window no longer exists.") }
            if command == "window" { return ["window": record(item)] }
            if command == "focus" { WindowEnhancementActions.focus(item) }
            else if command == "move" {
                guard let frame = DockScriptSupport.frame(arguments), let window = WindowEnhancementActions.element(item),
                      NSScreen.screens.contains(where: { $0.frame.intersects(DockAccessibility.appKit(frame)) }),
                      WindowEnhancementActions.setFrame(DockAccessibility.appKit(frame), of: window) else { throw failure(-1700, "Expected an on-screen x/y/width/height frame.") }
            } else if command == "previewImage" {
                guard Permissions.shared.screenRecording, !WindowPreviewProvider.captureIsPaused(excludedAppsKey: DefaultsKey.windowPreviewExcludedApps),
                      !(UserDefaults.standard.stringArray(forKey: DefaultsKey.windowPreviewExcludedApps) ?? []).contains(NSRunningApplication(processIdentifier: item.pid)?.bundleIdentifier ?? ""),
                      let image = WindowPreviewProvider.shared.cachedPreview(for: id),
                      let data = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]), data.count <= 8_388_608 else { throw failure(-1743, "An allowed cached preview and Screen Recording permission are required.") }
                return ["pngBase64": data.base64EncodedString()]
            } else if let action = WindowEnhancementAction(rawValue: command) {
                guard WindowEnhancementActions.perform(action, on: item) else { throw failure(-1708, "The app refused the window action.") }
            } else { throw failure(-1708, "Unknown window command.") }
        }
        return ["accepted": true]
    }
}
