// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import ApplicationServices
import CoreWLAN
import os

enum ContinuityHotspotError: Error {
    case permission
    case unavailable
    case connectionFailed
}

/// Uses only the Personal Hotspot controls exposed by System Settings.
/// AX calls run off the main actor; no network passwords or private APIs are used.
@MainActor
final class ContinuityHotspotConnector {
    private let accessibility = HotspotAccessibility()

    func discover() async throws -> [String] {
        try await openSettings()
        let deadline = Date().addingTimeInterval(12)
        var names = Set<String>()
        repeat {
            try Task.checkCancellation()
            guard AXIsProcessTrusted() else { throw ContinuityHotspotError.permission }
            if let pid = settingsPID {
                let snapshot = try await accessibility.snapshot(pid: pid)
                names.formUnion(snapshot.hotspotNames)
                // Allow nearby Continuity devices time to advertise themselves.
                if !names.isEmpty { return names.sorted() }
            }
            try await Task.sleep(for: .milliseconds(500))
        } while Date() < deadline
        return names.sorted()
    }

    func connect(named name: String) async throws {
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ContinuityHotspotError.unavailable
        }
        try await openSettings()
        let deadline = Date().addingTimeInterval(30)
        var requested = false
        var diagnostic = "no snapshot"
        repeat {
            try Task.checkCancellation()
            guard AXIsProcessTrusted() else { throw ContinuityHotspotError.permission }
            if let pid = settingsPID {
                let snapshot = try await accessibility.snapshot(pid: pid)
                diagnostic = "nodes=\(snapshot.nodes.count);currentName=\(snapshot.nodes.contains { $0.identifier == "wifi-current-network-name" });currentStatus=\(snapshot.nodes.contains { $0.identifier == "wifi-current-network-status" });ssidAvailable=\(snapshot.ssid != nil)"
                if snapshot.isConnected(to: name) { return }
                if !requested, let target = snapshot.connectAction(for: name) {
                    try Task.checkCancellation()
                    try await accessibility.perform(target)
                    requested = true
                }
            }
            try await Task.sleep(for: .milliseconds(500))
        } while Date() < deadline
        Logger(subsystem: Bundle.main.bundleIdentifier ?? "vorssaint", category: "continuity")
            .error("Hotspot confirmation timed out: \(diagnostic, privacy: .public)")
        throw requested ? ContinuityHotspotError.connectionFailed : ContinuityHotspotError.unavailable
    }

    private var settingsPID: pid_t? {
        NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.systempreferences")
            .first?.processIdentifier
    }

    private func openSettings() async throws {
        try Task.checkCancellation()
        guard AXIsProcessTrusted() else { throw ContinuityHotspotError.permission }
        guard let url = URL(string: "x-apple.systempreferences:com.apple.wifi-settings-extension") else {
            throw ContinuityHotspotError.unavailable
        }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = false
        configuration.hides = true
        configuration.addsToRecentItems = false
        do {
            _ = try await NSWorkspace.shared.open(url, configuration: configuration)
        } catch {
            throw ContinuityHotspotError.unavailable
        }
        try Task.checkCancellation()
    }
}

/// Value-only snapshots keep selection deterministic and AX objects off the UI actor.
struct HotspotSnapshot: Sendable {
    struct Action: Sendable {
        let name: String
        let description: String
    }
    struct Node: Sendable {
        let parent: Int?
        let identifier: String
        let text: String
        let actions: [Action]
    }
    struct Target: Sendable {
        let index: Int
        let generation: UUID
        let action: String
    }
    let generation: UUID
    let nodes: [Node]
    let ssid: String?

    var hotspotNames: [String] {
        var names = nodes.compactMap { node -> String? in
            let prefix = "wifi-network-", suffix = "-hotspot"
            guard node.identifier.hasPrefix(prefix), node.identifier.hasSuffix(suffix) else { return nil }
            let name = String(node.identifier.dropFirst(prefix.count).dropLast(suffix.count))
            return name.isEmpty ? nil : name
        }
        if let current = connectedHotspotName { names.append(current) }
        return Array(Set(names)).sorted()
    }

    func isConnected(to name: String) -> Bool {
        connectedHotspotName.map(Self.normalizedWhitespace) == Self.normalizedWhitespace(name)
    }

    private var connectedHotspotName: String? {
        guard nodes.contains(where: { $0.identifier == "wifi-current-network-hotspot" }) else { return nil }
        let current = nodes.filter { $0.identifier == "wifi-current-network-name" }.map(\.text)
        let visibleSSID = ssid.flatMap { value -> String? in
            let normalized = Self.normalizedWhitespace(value)
            return normalized.isEmpty || normalized == "<redacted>" ? nil : normalized
        }
        // SwiftUI exposes the network name and status as separate siblings on
        // recent macOS versions, even though accessibility readers combine them.
        for node in nodes where node.identifier == "wifi-current-network-name" {
            let name = Self.normalizedWhitespace(node.text)
            let connected = nodes.contains {
                $0.identifier == "wifi-current-network-status" && $0.parent == node.parent
                    && Self.connectedLabels.contains(Self.normalizedWhitespace($0.text))
            }
            if connected, !name.isEmpty, visibleSSID == nil || visibleSSID == name { return name }
        }
        for rawText in current {
            let text = Self.normalizedWhitespace(rawText)
            // CoreWLAN may redact SSIDs without Location permission. When it is
            // available, reject a stale Settings snapshot naming another SSID.
            if let visibleSSID, text == visibleSSID { return ssid }
            for label in Self.connectedLabels {
                let suffix = " " + label
                guard text.hasSuffix(suffix) else { continue }
                let name = String(text.dropLast(suffix.count))
                guard !name.isEmpty, visibleSSID == nil || visibleSSID == name else { continue }
                return name
            }
        }
        return nil
    }

    private static func normalizedWhitespace(_ value: String) -> String {
        value.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    func connectAction(for name: String) -> Target? {
        let markerID = "wifi-network-\(name)-hotspot"
        guard let marker = nodes.firstIndex(where: { $0.identifier == markerID }) else { return nil }
        // The live Wi-Fi AX tree exposes Connect on the device-name static text,
        // next to its hotspot marker. Never press a generic network-row button.
        for (index, node) in nodes.enumerated() where node.text == name {
            guard index == marker || (node.parent != nil && node.parent == nodes[marker].parent) else { continue }
            if let action = node.actions.first(where: { Self.isConnect($0) }) {
                return Target(index: index, generation: generation, action: action.name)
            }
        }
        return nil
    }

    // Verified against the public Wi-Fi Settings Localizable.loctable on macOS.
    // Includes all 15 app locales (several share the same system translation).
    private static let connectedLabels = [
        "Connected", "Conectado", "Bağlandı", "Подключено", "Con conexión",
        "Pripojené", "Verbunden", "Connecté", "Connessione attiva", "接続済み",
        "연결됨", "Підʼєднано", "已连接", "已連線"
    ]
    private static let connectLabels = [
        "connect", "conectar", "bağlan", "подключиться", "pripojiť", "verbinden",
        "connecter", "connetti", "接続", "연결", "підʼєднатись", "连接", "連線"
    ]
    private static func isConnect(_ action: Action) -> Bool {
        // Read actual advertised actions, including their localized descriptions.
        let name = action.name.split(separator: ":").last.map(String.init) ?? action.name
        return [name, action.description].contains {
            connectLabels.contains($0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased())
        }
    }
}

/// A timeout can mean Settings received the action but is still joining.
/// Neither accepted result proves connectivity; both require snapshot polling.
enum HotspotActionResult {
    static func shouldPoll(_ result: AXError) -> Bool {
        result == .success || result == .cannotComplete
    }
}

private actor HotspotAccessibility {
    private var elements: [AXUIElement] = []
    private var generation = UUID()

    func snapshot(pid: pid_t) throws -> HotspotSnapshot {
        let root = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(root, 0.3)
        elements = []
        generation = UUID()
        var nodes: [HotspotSnapshot.Node] = []
        var queue: [(AXUIElement, Int?)] = [(root, nil)]
        var cursor = 0
        let deadline = Date().addingTimeInterval(2)
        while cursor < queue.count, cursor < 1200, Date() < deadline {
            try Task.checkCancellation()
            let (element, parent) = queue[cursor]
            cursor += 1
            AXUIElementSetMessagingTimeout(element, 0.3)
            let index = nodes.count
            let identifier = string(element, kAXIdentifierAttribute)
            let value = string(element, kAXValueAttribute)
            let title = value.isEmpty ? string(element, kAXTitleAttribute) : value
            var actions: [HotspotSnapshot.Action] = []
            if !title.isEmpty {
                var raw: CFArray?
                if AXUIElementCopyActionNames(element, &raw) == .success,
                   let names = raw as? [String] {
                    actions = try names.prefix(32).map { name in
                        try Task.checkCancellation()
                        var description: CFString?
                        AXUIElementCopyActionDescription(element, name as CFString, &description)
                        return .init(name: name, description: description as String? ?? "")
                    }
                }
            }
            nodes.append(.init(parent: parent, identifier: identifier, text: title, actions: actions))
            elements.append(element)
            var rawChildren: CFTypeRef?
            if AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &rawChildren) == .success,
               let children = rawChildren as? [AXUIElement] {
                queue.append(contentsOf: children.prefix(max(0, 1200 - queue.count)).map { ($0, index) })
            }
        }
        try Task.checkCancellation()
        let ssid = CWWiFiClient.shared().interface()?.ssid().flatMap { $0.isEmpty ? nil : $0 }
        try Task.checkCancellation()
        return HotspotSnapshot(generation: generation, nodes: nodes, ssid: ssid)
    }

    func perform(_ target: HotspotSnapshot.Target) throws {
        try Task.checkCancellation()
        guard AXIsProcessTrusted() else { throw ContinuityHotspotError.permission }
        guard target.generation == generation, elements.indices.contains(target.index) else {
            throw ContinuityHotspotError.connectionFailed
        }
        let result = AXUIElementPerformAction(elements[target.index], target.action as CFString)
        try Task.checkCancellation()
        guard HotspotActionResult.shouldPoll(result) else {
            throw ContinuityHotspotError.connectionFailed
        }
        // The caller marks this request as issued even when its AX response timed
        // out, then waits for confirmed connection without repeating the action.
    }

    private func string(_ element: AXUIElement, _ attribute: String) -> String {
        var result: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &result) == .success else { return "" }
        return result as? String ?? ""
    }
}
