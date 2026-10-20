// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import ApplicationServices
import Darwin
import Security

/// Reads the menu bar items of the main display from MenuBarAgent's
/// Accessibility tree. On macOS 27 the agent composites the bar itself, so the
/// window list no longer shows status items and this tree is the only inventory.
///
/// Shape, one group per item:
///
///     AXApplication(MenuBarAgent)
///       AXWindow                         one per display
///         AXGroup                        the item's frame
///           AXButton pid=<app>           third-party item, owned by its app
///           (or AXApplication on macOS 27.0; resolve its AXExtrasMenuBar item)
///         AXGroup
///           AXGroup pid=<MenuBarAgent>
///             AXMenuBarItem id=com.apple.menuextra.…    system item
///
/// Hidden items leave the tree, and frames read while icons are hidden are
/// stale: walk an unrestricted bar when the layout matters.
enum MenuBarAccessibilityInventory {
    private static let queue = DispatchQueue(label: "com.vorssaint.menu-bar-organizer.inventory",
                                             qos: .userInitiated)
    /// A stuck agent must not wedge a walk for the default six seconds.
    private static let messagingTimeout: Float = 0.25
    private static let systemIdentifierPrefix = "com.apple.menuextra."

    /// Walks off the main thread and answers on it, left to right.
    static func walk(completion: @escaping ([MenuBarItemSnapshot]) -> Void) {
        queue.async {
            let items = walkNow()
            DispatchQueue.main.async { completion(items) }
        }
    }

    /// Blocking walk for callers that already run in the background.
    static func walkNow() -> [MenuBarItemSnapshot] {
        walkElements().map(\.item)
    }

    /// The Accessibility element behind one item of the main bar: the app-owned
    /// leaf of a third-party item, the AXMenuBarItem of a system item. Walks off
    /// the main thread and answers on it; nil when the item is not in the bar.
    static func locate(_ identity: MenuBarItemIdentity, completion: @escaping (AXUIElement?) -> Void) {
        queue.async {
            let element = walkElements().first { $0.item.identity == identity }?.element
            DispatchQueue.main.async { completion(element) }
        }
    }

    /// The walk itself, each item with the element it was named after, so the
    /// walk and the locator classify a group the same way.
    private static func walkElements() -> [(item: MenuBarItemSnapshot, element: AXUIElement)] {
        guard AXIsProcessTrusted(),
              let agent = NSRunningApplication
                  .runningApplications(withBundleIdentifier: MenuBarOrganizerPolicy.agentBundleID).first
        else { return [] }
        let agentPID = agent.processIdentifier
        let application = AXUIElementCreateApplication(agentPID)
        AXUIElementSetMessagingTimeout(application, messagingTimeout)

        // Every display has a bar window. Only the main one counts: mixing
        // displays would compare frames from different bars.
        let origin = CGDisplayBounds(CGMainDisplayID()).origin
        guard let window = children(of: application).first(where: {
            role(of: $0) == kAXWindowRole && frame(of: $0)?.origin == origin
        }) else { return [] }

        // Left to right before anything is named: an unnamed item is numbered
        // by its place among its app's items.
        let groups = children(of: window)
            .compactMap { group in frame(of: group).map { (group: group, frame: $0) } }
            .filter { $0.frame.width > 0 }
            .sorted { $0.frame.minX < $1.frame.minX }
        var items: [(item: MenuBarItemSnapshot, element: AXUIElement)] = []
        var taken = Set<MenuBarItemIdentity>()
        var hosts: [pid_t: Host?] = [:]
        var appItems: [pid_t: [AXUIElement]] = [:]
        for (group, frame) in groups {
            guard let described = describe(group, frame: frame, agentPID: agentPID, taken: taken,
                                           hosts: &hosts, appItems: &appItems)
            else { continue }
            taken.insert(described.item.identity)
            items.append(described)
        }
        return items
    }

    // MARK: - Classification

    /// The item a group stands for and the leaf that names it, the one a
    /// press goes to.
    private static func describe(_ group: AXUIElement, frame: CGRect, agentPID: pid_t,
                                 taken: Set<MenuBarItemIdentity>,
                                 hosts: inout [pid_t: Host?],
                                 appItems: inout [pid_t: [AXUIElement]]) -> (item: MenuBarItemSnapshot, element: AXUIElement)? {
        let leaves = children(of: group)
        // Usually an AXButton, but a custom status view can surface as static
        // text or an unknown role: whatever the agent does not own names its app.
        for leaf in leaves {
            guard let pid = pid(of: leaf), pid != agentPID else { continue }
            if hosts[pid] == nil { hosts[pid] = .some(host(of: pid)) }
            guard let host = hosts[pid] ?? nil else { continue }
            guard let element = statusElement(leaf, groupFrame: frame, ownerPID: pid, appItems: &appItems)
            else { continue }
            // Not the title: apps rewrite it, and the identity must not change.
            let identity = MenuBarItemIdentity.make(
                bundleID: host.bundleID, identifier: string(element, kAXIdentifierAttribute),
                description: string(element, kAXDescriptionAttribute), taken: taken)
            return (MenuBarItemSnapshot(identity: identity, frame: frame, pid: pid,
                                        appName: host.name, hostIsBundleless: host.isBundleless,
                                        hostIsAppleSigned: host.isAppleSigned), element)
        }
        for leaf in leaves where role(of: leaf) == kAXGroupRole {
            for extra in children(of: leaf) where role(of: extra) == kAXMenuBarItemRole {
                guard let identifier = string(extra, kAXIdentifierAttribute),
                      identifier.hasPrefix(systemIdentifierPrefix) else { continue }
                let identity = MenuBarItemIdentity.make(bundleID: MenuBarOrganizerPolicy.agentBundleID,
                                                        identifier: identifier, description: nil, taken: taken)
                return (MenuBarItemSnapshot(identity: identity, frame: frame, pid: agentPID,
                                            appName: string(extra, kAXDescriptionAttribute),
                                            hostIsBundleless: false, hostIsAppleSigned: true), extra)
            }
        }
        return nil
    }

    /// macOS 27.0 puts the owning application inside an agent group rather
    /// than the status control itself. Its extras bar contains every icon of
    /// that app, so choose the unique control centered inside this group.
    /// Keep the agent's frame for layout; return the real control for AXPress.
    private static func statusElement(_ leaf: AXUIElement, groupFrame: CGRect, ownerPID: pid_t,
                                      appItems: inout [pid_t: [AXUIElement]]) -> AXUIElement? {
        guard role(of: leaf) == kAXApplicationRole else { return leaf }
        if appItems[ownerPID] == nil {
            appItems[ownerPID] = elementAttribute(leaf, "AXExtrasMenuBar").map { children(of: $0) } ?? []
        }
        let matches = appItems[ownerPID, default: []].filter { element in
            guard let frame = frame(of: element), frame.width > 0, frame.height > 0 else { return false }
            return groupFrame.contains(CGPoint(x: frame.midX, y: frame.midY))
        }
        guard matches.count == 1 else { return nil }
        return matches[0]
    }

    // MARK: - Host attribution

    private struct Host {
        let bundleID: String
        let name: String?
        /// The process has no bundle id of its own; `bundleID` belongs to the
        /// app that encloses its executable.
        let isBundleless: Bool
        let isAppleSigned: Bool
    }

    /// Files a process under an app. One registered with LaunchServices is its
    /// own host. A helper living inside another app's bundle has no bundle id,
    /// so the app around it stands in: that names the item for the editor,
    /// though the allowlist addresses processes by their own id only and such
    /// an item therefore cannot be hidden.
    private static func host(of pid: pid_t) -> Host? {
        let application = NSRunningApplication(processIdentifier: pid)
        let isAppleSigned = isAppleSigned(pid)
        if let bundleID = application?.bundleIdentifier, !bundleID.isEmpty {
            return Host(bundleID: bundleID, name: application?.localizedName, isBundleless: false,
                        isAppleSigned: isAppleSigned)
        }
        guard let executable = application?.executableURL ?? executableURL(of: pid) else { return nil }
        let enclosing = enclosingApp(of: executable)
        // Outside any app the executable's name is all there is to go by.
        let fallback = executable.lastPathComponent
        return Host(bundleID: enclosing?.bundleID ?? fallback,
                    name: application?.localizedName ?? enclosing?.displayName ?? fallback,
                    isBundleless: true, isAppleSigned: isAppleSigned)
    }

    /// The innermost `.app` bundle with a bundle id among the directories above
    /// `executable`: for a helper app nested in a main app, the helper app.
    private static func enclosingApp(of executable: URL) -> (bundleID: String, displayName: String)? {
        let directories = executable.standardizedFileURL.pathComponents.dropLast()
        for index in directories.indices.reversed() where directories[index].hasSuffix(".app") {
            let path = NSString.path(withComponents: Array(directories[...index]))
            guard let bundleID = Bundle(path: path)?.bundleIdentifier, !bundleID.isEmpty else { continue }
            return (bundleID, FileManager.default.displayName(atPath: path))
        }
        return nil
    }

    /// Developer ID, App Store and Apple Development signatures, and Apple's own.
    private static let appleAnchor: SecRequirement? = {
        var requirement: SecRequirement?
        guard SecRequirementCreateWithString("anchor apple generic" as CFString, [], &requirement) == errSecSuccess
        else { return nil }
        return requirement
    }()

    /// Whether the running process is signed with an Apple-issued certificate,
    /// which is what makes the agent record it as the owner of its items.
    /// Ad-hoc and self-signed code is not, and neither is anything that cannot
    /// be checked. Vorssaint's own items count as signed whatever the build:
    /// the process holding the restriction is assumed to keep its icons.
    private static func isAppleSigned(_ pid: pid_t) -> Bool {
        if pid == getpid() { return true }
        var code: SecCode?
        let attributes = [kSecGuestAttributePid: pid] as CFDictionary
        guard let appleAnchor,
              SecCodeCopyGuestWithAttributes(nil, attributes, [], &code) == errSecSuccess,
              let code else { return false }
        return SecCodeCheckValidity(code, [], appleAnchor) == errSecSuccess
    }

    private static func executableURL(of pid: pid_t) -> URL? {
        var buffer = [CChar](repeating: 0, count: 4 * Int(MAXPATHLEN))
        guard proc_pidpath(pid, &buffer, UInt32(buffer.count)) > 0 else { return nil }
        return URL(fileURLWithPath: String(cString: buffer))
    }

    // MARK: - Accessibility reads

    private static func value(_ element: AXUIElement, _ attribute: String) -> CFTypeRef? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else { return nil }
        return value
    }

    private static func string(_ element: AXUIElement, _ attribute: String) -> String? {
        value(element, attribute) as? String
    }

    private static func elementAttribute(_ element: AXUIElement, _ attribute: String) -> AXUIElement? {
        guard let value = value(element, attribute), CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        return unsafeDowncast(value, to: AXUIElement.self)
    }

    private static func role(of element: AXUIElement) -> String? {
        string(element, kAXRoleAttribute)
    }

    private static func children(of element: AXUIElement) -> [AXUIElement] {
        value(element, kAXChildrenAttribute) as? [AXUIElement] ?? []
    }

    private static func pid(of element: AXUIElement) -> pid_t? {
        var pid: pid_t = 0
        guard AXUIElementGetPid(element, &pid) == .success, pid > 0 else { return nil }
        return pid
    }

    private static func frame(of element: AXUIElement) -> CGRect? {
        guard let value = value(element, "AXFrame"), CFGetTypeID(value) == AXValueGetTypeID() else { return nil }
        var rect = CGRect.zero
        // The type id was checked above, so this downcast cannot fail.
        guard AXValueGetValue(unsafeDowncast(value, to: AXValue.self), .cgRect, &rect) else { return nil }
        return rect
    }
}
