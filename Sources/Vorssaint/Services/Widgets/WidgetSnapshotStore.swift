// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// The metrics the desktop widgets draw, and the file they travel through.
///
/// Widget extensions are sandboxed and run in their own process, so they can
/// read neither the SMC nor the volumes Vorssaint samples. The app does the
/// sampling and drops a snapshot here; the extension only renders it.
///
/// The path is fixed and absolute on purpose: a sandbox temporary exception
/// cannot express `~`, so a directory under the home folder is unreachable
/// from the extension's entitlement. It is still per account, and private to
/// it (0700), so living outside `$HOME` costs no privacy.
struct WidgetSnapshot: Codable, Equatable {
    var capturedAt: Date

    var cpuUsage: Double?          // 0...1
    var gpuUsage: Double?          // 0...1
    var memoryUsed: UInt64?
    var memoryTotal: UInt64?
    var memoryPressure: String?    // MemoryPressure.rawValue-ish, already localized upstream
    var diskUsed: UInt64?
    var diskTotal: UInt64?

}

enum WidgetSnapshotStore {
    /// Identifies which install this file belongs to. The official app and the
    /// local Developer build run side by side on the same Mac and share
    /// `/Users/Shared`, so one directory for both would have them overwriting
    /// each other's snapshot and — worse — consuming each other's commands,
    /// since consuming one deletes it.
    ///
    /// The extension derives its container's id by dropping its own `.widgets`
    /// suffix, which is how both ends land on the same directory without the
    /// app having to tell it.
    static let containerIdentifier: String = {
        guard let identifier = Bundle.main.bundleIdentifier else {
            // No bundle: the test harness, or the bare binary being probed.
            // Deliberately not the release id — that is a live install's
            // directory, and a test run must never write into, or clean up
            // after, the app someone is actually using.
            return "com.vorssaint.utils.no-bundle"
        }
        if identifier.hasSuffix(".widgets") {
            return String(identifier.dropLast(".widgets".count))
        }
        return identifier
    }()

    /// Per install *and* per account. `/Users/Shared` is one directory for the
    /// whole Mac, so a single path per install would be created by whichever
    /// user logged in first and left every other account unable to write to
    /// it — their widget would sit empty forever. The uid in the path gives
    /// each account its own, and lets it be private (0700) rather than
    /// world-readable, since nobody else has any reason to read it.
    ///
    /// The sandbox exception covers the parent, so the extra level needs no
    /// entitlement change; the extension runs as the user whose widget it is,
    /// and so resolves the same path the app wrote.
    static let directory = URL(fileURLWithPath: "/Users/Shared/Vorssaint", isDirectory: true)
        .appendingPathComponent("\(containerIdentifier)-\(getuid())", isDirectory: true)
    static let snapshotURL = directory.appendingPathComponent("widget-snapshot.json")

    /// A snapshot older than this is stale: Vorssaint is not running, or its
    /// monitor stopped. The widget says so instead of showing frozen numbers.
    static let staleAfter: TimeInterval = 10 * 60

    static func read() -> WidgetSnapshot? {
        guard let data = try? Data(contentsOf: snapshotURL) else { return nil }
        return try? JSONDecoder().decode(WidgetSnapshot.self, from: data)
    }

    /// Writes atomically so a widget reading mid-write never sees half a file.
    @discardableResult
    static func write(_ snapshot: WidgetSnapshot) -> Bool {
        guard let data = try? JSONEncoder().encode(snapshot) else { return false }
        do {
            try FileManager.default.createDirectory(at: directory,
                                                    withIntermediateDirectories: true,
                                                    attributes: [.posixPermissions: 0o700])
            try data.write(to: snapshotURL, options: .atomic)
            // .atomic replaces the file, so the mode has to be reapplied.
            try? FileManager.default.setAttributes([.posixPermissions: 0o600],
                                                   ofItemAtPath: snapshotURL.path)
            return true
        } catch {
            return false
        }
    }
}

/// How a widget says "I exist" across the sandbox.
///
/// The app cannot be notified by the system when a widget is placed, and a
/// widget cannot reach the app except through the shared directory it may not
/// yet have a reason to watch. A distributed notification crosses the sandbox
/// in one hop and costs nothing when no widget is around to send it.
///
/// It only ever turns sampling *on*. Turning it off stays with
/// `WidgetCenter.getCurrentConfigurations`, which is the authoritative answer:
/// a removed widget sends nothing, and silence is not proof on its own.
enum WidgetPresenceSignal {
    /// Namespaced per install, so the Developer build's widgets do not wake the
    /// official app into sampling for widgets that are not its own.
    static let name = Notification.Name(
        "\(WidgetSnapshotStore.containerIdentifier).widget-present")

    static func post() {
        DistributedNotificationCenter.default().postNotificationName(name,
                                                                     object: nil,
                                                                     userInfo: nil,
                                                                     deliverImmediately: true)
    }
}
