// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import ApplicationServices
import Foundation

/// Measures labelled controls in their app or system host rather than placeholder
/// NSWindows. Never requests permission, reads menu contents or sends input.
enum MenuBarHiderAccessibility {
    /// Native status items may be in their creating app or a system host,
    /// depending on macOS. Measure our labelled controls wherever they live.
    static func hostPIDs(currentPID: pid_t, runningPIDs: (String) -> [pid_t]) -> [pid_t] {
        let candidates = [currentPID] + ["com.apple.controlcenter", "com.apple.MenuBarAgent"]
            .flatMap(runningPIDs)
        var seen = Set<pid_t>()
        return candidates.filter { $0 > 0 && seen.insert($0).inserted }
    }

    static func separatorPositions(pids: [pid_t], normalHelp: String,
                                   permanentHelp: String) -> (normal: CGRect, permanent: CGRect)? {
        for pid in pids {
            if let positions = separatorPositions(pid: pid, normalHelp: normalHelp,
                                                  permanentHelp: permanentHelp) {
                return positions
            }
        }
        return nil
    }

    private static func separatorPositions(pid: pid_t, normalHelp: String,
                                          permanentHelp: String) -> (normal: CGRect, permanent: CGRect)? {
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, 0.03)
        // Status items have their own AX root. Searching windows first can
        // exhaust the budget in our Settings tree before reaching the bar.
        if let extras = value(app, "AXExtrasMenuBar"), CFGetTypeID(extras) == AXUIElementGetTypeID(),
           let positions = search(roots: [unsafeBitCast(extras, to: AXUIElement.self)],
                                  normalHelp: normalHelp, permanentHelp: permanentHelp,
                                  deadline: Date().addingTimeInterval(0.5)) {
            return positions
        }
        return search(roots: [app], normalHelp: normalHelp, permanentHelp: permanentHelp,
                      deadline: Date().addingTimeInterval(0.2))
    }

    private static func search(roots: [AXUIElement], normalHelp: String,
                               permanentHelp: String, deadline: Date) -> (normal: CGRect, permanent: CGRect)? {
        findSeparators(roots: roots, normalHelp: normalHelp, permanentHelp: permanentHelp,
                       canContinue: { !Task.isCancelled && Date() < deadline },
                       labels: { element in
                           AXUIElementSetMessagingTimeout(element, 0.03)
                           return [kAXHelpAttribute, kAXDescriptionAttribute, kAXTitleAttribute]
                               .compactMap { value(element, $0) as? String }
                       }, frame: frame,
                       children: { value($0, kAXChildrenAttribute) as? [AXUIElement] ?? [] })
    }

    /// Breadth-first traversal prevents a deep Settings window from starving
    /// sibling menu-bar controls. Kept bounded even for malformed AX trees.
    static func findSeparators<Node>(roots: [Node], normalHelp: String, permanentHelp: String,
                                     canContinue: () -> Bool, labels: (Node) -> [String],
                                     frame: (Node) -> CGRect?, children: (Node) -> [Node])
        -> (normal: CGRect, permanent: CGRect)? {
        var pending = roots
        var visited = 0
        var normal: CGRect?
        var permanent: CGRect?
        while !pending.isEmpty, visited < 160, canContinue() {
            let element = pending.removeFirst()
            visited += 1
            let labels = labels(element)
            if labels.contains(normalHelp) || labels.contains(permanentHelp),
               let frame = frame(element) {
                if labels.contains(normalHelp) { normal = frame }
                if labels.contains(permanentHelp) { permanent = frame }
                if let normal, let permanent, normal != permanent { return (normal, permanent) }
            }
            pending.append(contentsOf: children(element).prefix(64))
        }
        return nil
    }

    private static func value(_ element: AXUIElement, _ attribute: String) -> CFTypeRef? {
        var result: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &result) == .success else { return nil }
        return result
    }

    private static func frame(_ element: AXUIElement) -> CGRect? {
        guard let raw = value(element, kAXPositionAttribute), CFGetTypeID(raw) == AXValueGetTypeID(),
              let sizeRaw = value(element, kAXSizeAttribute), CFGetTypeID(sizeRaw) == AXValueGetTypeID() else { return nil }
        let position = unsafeBitCast(raw, to: AXValue.self)
        let size = unsafeBitCast(sizeRaw, to: AXValue.self)
        var point = CGPoint.zero
        var dimensions = CGSize.zero
        guard AXValueGetValue(position, .cgPoint, &point), AXValueGetValue(size, .cgSize, &dimensions),
              point.x.isFinite, point.y.isFinite, dimensions.width > 0, dimensions.height > 0 else { return nil }
        return CGRect(origin: point, size: dimensions)
    }
}
