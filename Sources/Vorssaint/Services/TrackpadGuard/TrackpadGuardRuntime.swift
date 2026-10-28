// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Darwin
import Foundation
import IOKit.hidsystem

/// The same runtime parameter behind macOS's trackpad-ignore setting. This
/// never writes the saved preference. An unknown parameter/value fails closed.
enum TrackpadGuardRuntime {
    private static let key = "USBMouseStopsTrackpad" as CFString

    private static func withConnection<T>(_ body: (io_connect_t) -> T?) -> T? {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("IOHIDSystem"))
        guard service != 0 else { return nil }
        defer { IOObjectRelease(service) }
        var connection: io_connect_t = 0
        guard IOServiceOpen(service, mach_task_self_, UInt32(kIOHIDParamConnectType), &connection) == KERN_SUCCESS else {
            return nil
        }
        defer { IOServiceClose(connection) }
        return body(connection)
    }

    static func read() -> Int? {
        withConnection { connection in
            var raw: Unmanaged<CFTypeRef>?
            guard IOHIDCopyCFTypeParameter(connection, key, &raw) == KERN_SUCCESS,
                  let number = raw?.takeRetainedValue() as? NSNumber,
                  number == 0 || number == 1 else { return nil }
            return number.intValue
        }
    }

    static func savedPreference() -> Int? {
        let domain = "com.apple.AppleMultitouchTrackpad" as CFString
        _ = CFPreferencesAppSynchronize(domain)
        guard let number = CFPreferencesCopyAppValue(key, domain) as? NSNumber,
              number == 0 || number == 1 else { return nil }
        return number.intValue
    }

    static func set(_ value: Int) -> Bool {
        guard value == 0 || value == 1 else { return false }
        return (withConnection { IOHIDSetCFTypeParameter($0, key, NSNumber(value: value)) == KERN_SUCCESS } ?? false)
            && read() == value
    }
}

/// Shared by release and Developer apps because they change the same runtime
/// parameter. The lock serializes ownership; a boot-scoped journal repairs a
/// simultaneous app/helper kill on the next launch. None of this is a preference
/// or travels in a backup, and no process arguments or selected apps are stored.
enum TrackpadGuardRecovery {
    struct Entry: Codable {
        let bootTime: Int64
        let token: UUID
        let original: Int
        let savedPreference: Int?
    }

    private static var directory: URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("com.vorssaint.trackpad-guard", isDirectory: true)
    }
    private static var journal: URL { directory.appendingPathComponent("restore.json") }

    static var hasPendingEntry: Bool { FileManager.default.fileExists(atPath: journal.path) }

    static func withLock<T>(_ body: () -> T) -> T? {
        guard PrivateFileStore.createDirectory(at: directory, container: directory) else { return nil }
        let descriptor = open(directory.appendingPathComponent("owner.lock").path,
                              O_CREAT | O_RDWR | O_NOFOLLOW | O_CLOEXEC, 0o600)
        guard descriptor >= 0 else { return nil }
        defer { close(descriptor) }
        guard flock(descriptor, LOCK_EX | LOCK_NB) == 0 else { return nil }
        defer { _ = flock(descriptor, LOCK_UN) }
        return body()
    }

    static func record(original: Int, token: UUID) -> Bool {
        guard let bootTime = bootTime(), original == 0 || original == 1,
              let data = try? JSONEncoder().encode(Entry(bootTime: bootTime, token: token, original: original,
                                                        savedPreference: TrackpadGuardRuntime.savedPreference())) else {
            return false
        }
        return PrivateFileStore.write(data, to: journal)
    }

    /// Caller owns the lock. A new helper must restore a predecessor before
    /// capturing a baseline; a different token's live lease is never released.
    static func restoreLocked(expectedToken: UUID? = nil) -> Bool {
        guard hasPendingEntry else { return true }
        guard let data = try? Data(contentsOf: journal),
              let entry = try? JSONDecoder().decode(Entry.self, from: data),
              entry.original == 0 || entry.original == 1,
              let currentBoot = bootTime() else { return false }
        if let expectedToken, expectedToken != entry.token { return true }
        if entry.bootTime == currentBoot {
            // A user/system change to 0 has already restored usable input.
            // Do not overwrite it with a captured global-on preference.
            guard let current = TrackpadGuardRuntime.read() else { return false }
            if let target = TrackpadGuardSupport.restorationTarget(
                original: entry.original, current: current, savedAtCapture: entry.savedPreference,
                savedNow: TrackpadGuardRuntime.savedPreference()), !TrackpadGuardRuntime.set(target) {
                return false
            }
        }
        do { try FileManager.default.removeItem(at: journal); return true }
        catch { return false }
    }

    static func restorePending(expectedToken: UUID? = nil) -> Bool {
        guard hasPendingEntry else { return true }
        return withLock { restoreLocked(expectedToken: expectedToken) } ?? false
    }

    private static func bootTime() -> Int64? {
        var value = timeval()
        var count = MemoryLayout<timeval>.stride
        guard sysctlbyname("kern.boottime", &value, &count, nil, 0) == 0, value.tv_sec > 0 else { return nil }
        return Int64(value.tv_sec)
    }
}
