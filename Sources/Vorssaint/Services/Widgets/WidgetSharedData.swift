// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// The six desktop widgets. The raw values are the WidgetKit kinds; the host
/// uses the same set to decide which timelines to reload.
enum VorssaintWidgetKind: String, CaseIterable, Codable {
    case cpu = "VorssaintCPUWidget"
    case gpu = "VorssaintGPUWidget"
    case memory = "VorssaintRAMWidget"
    case disk = "VorssaintDiskWidget"
    case network = "VorssaintNetworkWidget"
    case united = "VorssaintUnitedWidget"

    /// Kinds that render a monitor reading. The United widget only combines
    /// these, so it never needs a sampler of its own.
    static var readings: [VorssaintWidgetKind] { [.cpu, .gpu, .memory, .disk, .network] }
}

struct WidgetCPUReading: Codable, Equatable {
    var total: Double
    var system: Double
    var user: Double
    var idle: Double

    static let empty = WidgetCPUReading(total: 0, system: 0, user: 0, idle: 0)
}

struct WidgetGPUReading: Codable, Equatable {
    var usage: Double
    var renderer: Double?
    var tiler: Double?

    static let empty = WidgetGPUReading(usage: 0, renderer: 0, tiler: 0)
}

struct WidgetMemoryReading: Codable, Equatable {
    var used: UInt64
    var total: UInt64
    var app: UInt64
    var pressureLevel: Int

    var usedFraction: Double {
        guard total > 0 else { return 0 }
        return min(1, max(0, Double(used) / Double(total)))
    }

    var free: UInt64 { total > used ? total - used : 0 }

    static let empty = WidgetMemoryReading(used: 0, total: 0, app: 0, pressureLevel: 0)
}

struct WidgetDiskReading: Codable, Equatable {
    var used: UInt64
    var free: UInt64
    var total: UInt64

    var usedFraction: Double {
        guard total > 0 else { return 0 }
        return min(1, max(0, Double(used) / Double(total)))
    }

    static let empty = WidgetDiskReading(used: 0, free: 0, total: 0)
}

struct WidgetNetworkReading: Codable, Equatable {
    var downBytesPerSec: Double
    var upBytesPerSec: Double
    var isConnected: Bool
    var usesBits: Bool
    var interfaceName: String?
    var localAddress: String?

    var downText: String { WidgetFormat.rate(downBytesPerSec, inBits: usesBits) }
    var upText: String { WidgetFormat.rate(upBytesPerSec, inBits: usesBits) }

    static let empty = WidgetNetworkReading(downBytesPerSec: 0, upBytesPerSec: 0,
                                            isConnected: false, usesBits: false,
                                            interfaceName: nil, localAddress: nil)
}

/// Everything the extension needs for one timeline. Its own timestamp makes
/// an unchanged snapshot easy to skip and lets a future version judge age.
struct WidgetSnapshot: Codable, Equatable {
    var capturedAt: Date
    var cpu: WidgetCPUReading?
    var gpu: WidgetGPUReading?
    var memory: WidgetMemoryReading?
    var disk: WidgetDiskReading?
    var network: WidgetNetworkReading?

    func hasReading(for kind: VorssaintWidgetKind) -> Bool {
        switch kind {
        case .cpu: return cpu != nil
        case .gpu: return gpu != nil
        case .memory: return memory != nil
        case .disk: return disk != nil
        case .network: return network != nil
        case .united: return cpu != nil || gpu != nil || memory != nil || disk != nil
        }
    }

    /// Rendered while the app has not published anything yet. It uses the
    /// widget's real layout with empty gauges and zero values rather than a
    /// message, so adding a widget never shows a blank card.
    static let placeholder = WidgetSnapshot(
        capturedAt: Date(timeIntervalSince1970: 0),
        cpu: .empty,
        gpu: .empty,
        memory: .empty,
        disk: .empty,
        network: .empty
    )

    /// Shown in the widget gallery so a widget reads as itself before the app
    /// has ever published a real reading.
    static let preview = WidgetSnapshot(
        capturedAt: Date(),
        cpu: WidgetCPUReading(total: 0.34, system: 0.11, user: 0.23, idle: 0.66),
        gpu: WidgetGPUReading(usage: 0.41, renderer: 0.44, tiler: 0.18),
        memory: WidgetMemoryReading(used: 12_800_000_000, total: 24_000_000_000,
                                    app: 9_600_000_000, pressureLevel: 1),
        disk: WidgetDiskReading(used: 274_000_000_000, free: 226_000_000_000,
                                total: 500_000_000_000),
        network: WidgetNetworkReading(downBytesPerSec: 18_700_000, upBytesPerSec: 1_240_000,
                                      isConnected: true, usesBits: false,
                                      interfaceName: "Wi-Fi", localAddress: "192.168.1.24")
    )
}

/// Pure formatting shared by the host and the extension, so a widget reads a
/// value the same way the app does.
enum WidgetFormat {
    static func percent(_ fraction: Double) -> String {
        guard fraction.isFinite else { return "0%" }
        return "\(Int((min(1, max(0, fraction)) * 100).rounded()))%"
    }

    static func bytes(_ bytes: UInt64) -> String {
        let (value, unit) = byteScale(Double(bytes))
        return "\(byteNumber(value, unit: unit)) \(unit)"
    }

    static func rate(_ bytesPerSecond: Double, inBits: Bool) -> String {
        guard bytesPerSecond.isFinite, bytesPerSecond > 0 else {
            return inBits ? "0 bps" : "0 B/s"
        }
        if inBits {
            let (value, unit) = bitScale(bytesPerSecond * 8)
            return "\(bitNumber(value, unit: unit)) \(unit)"
        }
        let (value, unit) = byteScale(bytesPerSecond)
        return "\(byteNumber(value, unit: unit)) \(unit)/s"
    }

    /// Byte sizes use the same 1024 steps as the monitor's memory and disk
    /// readouts, while network bits use decimal steps like link speeds.
    private static func byteScale(_ value: Double) -> (Double, String) {
        let units = ["B", "KB", "MB", "GB", "TB", "PB"]
        var scaled = max(0, value)
        var index = 0
        while scaled >= 1024, index < units.count - 1 {
            scaled /= 1024
            index += 1
        }
        return (scaled, units[index])
    }

    private static func bitScale(_ value: Double) -> (Double, String) {
        let units = ["bps", "Kbps", "Mbps", "Gbps", "Tbps", "Pbps"]
        var scaled = max(0, value)
        var index = 0
        while scaled >= 1_000, index < units.count - 1 {
            scaled /= 1_000
            index += 1
        }
        return (scaled, units[index])
    }

    private static func byteNumber(_ value: Double, unit: String) -> String {
        if unit == "B" { return String(format: "%.0f", locale: .current, value) }
        return value < 10
            ? String(format: "%.1f", locale: .current, value)
            : String(format: "%.0f", locale: .current, value)
    }

    private static func bitNumber(_ value: Double, unit: String) -> String {
        if unit == "bps" { return String(format: "%.0f", locale: .current, value) }
        return value < 10
            ? String(format: "%.1f", locale: .current, value)
            : String(format: "%.0f", locale: .current, value)
    }
}

/// Storage shared by the app and its WidgetKit extension. Developer ID builds
/// use an app-group `UserDefaults` suite plus a JSON file in the same group
/// container. Local builds have no provisioned group, so both processes use a
/// folder in the real Application Support directory instead, which the
/// extension's sandbox reaches through its temporary exception.
enum WidgetSharedData {
    static let defaultGroupID = "com.vorssaint.utils.widgets"
    static let snapshotKey = "VorssaintWidgetSnapshot"
    /// A widget asks for a timeline every few seconds while it is on screen,
    /// so this only has to outlast the monitor's slowest wake cadence.
    static let activityWindow: TimeInterval = 90

    private static let snapshotFile = "snapshot.json"
    private static let languageFile = "language"

    static func groupID(bundle: Bundle = .main) -> String {
        (bundle.object(forInfoDictionaryKey: "VorssaintAppGroup") as? String) ?? defaultGroupID
    }

    /// `true` only when the build injected a real, provisioned app group. The
    /// local build ships an unprefixed name in the plist for the JSON folder
    /// but does not claim the entitlement.
    static func usesAppGroup(bundle: Bundle = .main) -> Bool {
        bundle.object(forInfoDictionaryKey: "VorssaintUsesAppGroup") as? Bool ?? false
    }

    /// The suite only helps when both processes are entitled for the same
    /// group container. Without that, the file below is the channel.
    static func sharedDefaults(bundle: Bundle = .main) -> UserDefaults? {
        guard usesAppGroup(bundle: bundle), appGroupURL(bundle: bundle) != nil else { return nil }
        return UserDefaults(suiteName: groupID(bundle: bundle))
    }

    static func appGroupURL(bundle: Bundle = .main) -> URL? {
        guard usesAppGroup(bundle: bundle) else { return nil }
        return FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: groupID(bundle: bundle))
    }

    /// Creates the shared folder up front. The app owns the folder, so the
    /// sandboxed extension only ever has to write inside it.
    static func prepareStorage(bundle: Bundle = .main) {
        guard let directory = storageDirectory(bundle: bundle) else { return }
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    /// The app writes its chosen interface language here so the extension can
    /// pick the same catalog. The extension's own defaults are its sandbox
    /// container, not the app's.
    static func language(bundle: Bundle = .main) -> AppLanguage {
        guard let data = readFile(languageFile, bundle: bundle),
              let code = String(data: data, encoding: .utf8),
              let language = AppLanguage(rawValue: code) else { return .systemDefault }
        return language
    }

    static func setLanguage(_ language: AppLanguage, bundle: Bundle = .main) {
        writeFile(Data(language.rawValue.utf8), name: languageFile, bundle: bundle)
    }

    static func loadSnapshot(bundle: Bundle = .main) -> WidgetSnapshot? {
        if let data = sharedDefaults(bundle: bundle)?.data(forKey: snapshotKey),
           let snapshot = try? JSONDecoder().decode(WidgetSnapshot.self, from: data) {
            return snapshot
        }
        guard let data = readFile(snapshotFile, bundle: bundle) else { return nil }
        return try? JSONDecoder().decode(WidgetSnapshot.self, from: data)
    }

    static func writeSnapshot(_ snapshot: WidgetSnapshot, bundle: Bundle = .main) {
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        sharedDefaults(bundle: bundle)?.set(data, forKey: snapshotKey)
        writeFile(data, name: snapshotFile, bundle: bundle)
    }

    /// Written by the extension from `getTimeline`, read by the app to keep
    /// the monitor alive only while a widget is actually on a desktop.
    static func recordRequest(_ kind: VorssaintWidgetKind, bundle: Bundle = .main) {
        let now = Date().timeIntervalSince1970
        sharedDefaults(bundle: bundle)?.set(now, forKey: requestKey(kind))
        writeFile(Data(String(now).utf8), name: requestFile(kind), bundle: bundle)
    }

    static func lastRequest(_ kind: VorssaintWidgetKind, bundle: Bundle = .main) -> TimeInterval {
        if let defaults = sharedDefaults(bundle: bundle) {
            let value = defaults.double(forKey: requestKey(kind))
            if value > 0 { return value }
        }
        guard let data = readFile(requestFile(kind), bundle: bundle),
              let text = String(data: data, encoding: .utf8),
              let value = TimeInterval(text) else { return 0 }
        return value
    }

    static func isKindActive(_ kind: VorssaintWidgetKind,
                             now: TimeInterval = Date().timeIntervalSince1970,
                             bundle: Bundle = .main) -> Bool {
        isRecentlyRequested(lastRequest(kind, bundle: bundle), now: now)
    }

    /// A heartbeat older than the window, or one that was never written,
    /// stops the feed instead of keeping the monitor awake forever.
    static func isRecentlyRequested(_ last: TimeInterval, now: TimeInterval) -> Bool {
        last > 0 && now - last < activityWindow
    }

    static func clearSnapshot(bundle: Bundle = .main) {
        sharedDefaults(bundle: bundle)?.removeObject(forKey: snapshotKey)
        guard let url = storageDirectory(bundle: bundle)?.appendingPathComponent(snapshotFile) else { return }
        try? FileManager.default.removeItem(at: url)
    }

    /// Removes the snapshot and heartbeats an uninstall would otherwise leave
    /// behind in the app group or the shared Application Support folder.
    static func removeStoredData(bundle: Bundle = .main) {
        if let defaults = sharedDefaults(bundle: bundle) {
            defaults.removeObject(forKey: snapshotKey)
            for kind in VorssaintWidgetKind.allCases {
                defaults.removeObject(forKey: requestKey(kind))
            }
        }
        if let directory = storageDirectory(bundle: bundle) {
            try? FileManager.default.removeItem(at: directory)
        }
    }

    private static func requestKey(_ kind: VorssaintWidgetKind) -> String {
        "VorssaintWidgetRequest-\(kind.rawValue)"
    }

    private static func requestFile(_ kind: VorssaintWidgetKind) -> String {
        "request-\(kind.rawValue)"
    }

    static func storageDirectory(bundle: Bundle = .main) -> URL? {
        if let container = appGroupURL(bundle: bundle) {
            return container.appendingPathComponent("Widgets", isDirectory: true)
        }
        // Local builds have no provisioned app group. Both the app and the
        // sandboxed extension write to the app's ordinary Application Support
        // folder; the extension reaches the real home through its temporary
        // exception, and the app creates the folder before the first read.
        guard let hostID = hostBundleIdentifier(bundle: bundle) else { return nil }
        return realHomeDirectory()
            .appendingPathComponent("Library/Application Support/\(hostID)/Widgets", isDirectory: true)
    }

    /// The extension's bundle identifier is always the host's plus `.widget`,
    /// so it can find the app's own Application Support folder.
    private static func hostBundleIdentifier(bundle: Bundle) -> String? {
        guard var identifier = bundle.bundleIdentifier else { return nil }
        let suffix = ".widget"
        if identifier.hasSuffix(suffix) {
            identifier.removeLast(suffix.count)
        }
        return identifier
    }

    /// A sandboxed extension sees its container as `homeDirectoryForCurrentUser`,
    /// so ask the account database for the real home instead.
    private static func realHomeDirectory() -> URL {
        if let entry = getpwuid(getuid()) {
            return URL(fileURLWithPath: String(cString: entry.pointee.pw_dir), isDirectory: true)
        }
        return FileManager.default.homeDirectoryForCurrentUser
    }

    private static func writeFile(_ data: Data, name: String, bundle: Bundle) {
        guard let directory = storageDirectory(bundle: bundle) else { return }
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try? data.write(to: directory.appendingPathComponent(name), options: .atomic)
    }

    private static func readFile(_ name: String, bundle: Bundle) -> Data? {
        guard let directory = storageDirectory(bundle: bundle) else { return nil }
        return try? Data(contentsOf: directory.appendingPathComponent(name))
    }
}
