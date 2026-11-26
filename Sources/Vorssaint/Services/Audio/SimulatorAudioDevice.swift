// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Darwin
import Foundation

/// Simulator apps and system services connect to Core Audio from inside their
/// device's launchd_sim tree. Their macOS responsible process can be an XPC
/// service, even while Device Hub is displaying the simulator.
struct SimulatorAudioDevice {
    let ownerPid: pid_t
    let id: String
    let name: String

    /// Used for one HAL snapshot. Several audio clients can share a supervisor.
    struct Discovery {
        private var supervisors: [pid_t: SimulatorAudioDevice?] = [:]

        mutating func device(for pid: pid_t) -> SimulatorAudioDevice? {
            var current = pid
            for _ in 0..<MixerRoutingSupport.owningAppSearchDepth {
                current = ResponsibleProcess.parent(of: current)
                guard current > 1 else { return nil }
                if supervisors[current] == nil {
                    supervisors[current] = .some(SimulatorAudioDevice(supervisor: current))
                }
                if let device = supervisors[current] ?? nil { return device }
            }
            return nil
        }
    }

    private init?(supervisor: pid_t) {
        var path = [CChar](repeating: 0, count: Int(MAXPATHLEN) * 4)
        guard proc_pidpath(supervisor, &path, UInt32(path.count)) > 0,
              String(cString: path).hasSuffix("/RuntimeRoot/sbin/launchd_sim"),
              let bootstrapPath = Self.bootstrapPath(for: supervisor) else { return nil }

        let deviceDirectory = URL(fileURLWithPath: bootstrapPath).deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let deviceSet = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Developer/CoreSimulator/Devices")
        guard deviceDirectory.deletingLastPathComponent().standardizedFileURL.path == deviceSet.standardizedFileURL.path,
              let uuid = UUID(uuidString: deviceDirectory.lastPathComponent),
              let data = try? Data(contentsOf: deviceDirectory.appendingPathComponent("device.plist")),
              let device = try? PropertyListDecoder().decode(DeviceInfo.self, from: data),
              UUID(uuidString: device.UDID) == uuid, !device.name.isEmpty else { return nil }

        ownerPid = supervisor
        id = MixerRoutingSupport.simulatorRowPrefix + uuid.uuidString
        name = device.name
    }

    private struct DeviceInfo: Decodable {
        let UDID: String
        let name: String
    }

    /// KERN_PROCARGS2 starts with argc, the executable path, padding and then
    /// argv. Inspect only through argv[1], which is launchd_sim's bootstrap file.
    private static func bootstrapPath(for pid: pid_t) -> String? {
        var mib = [CTL_KERN, KERN_PROCARGS2, pid]
        var size = 0
        guard sysctl(&mib, 3, nil, &size, nil, 0) == 0, size >= MemoryLayout<Int32>.size else { return nil }
        var bytes = [UInt8](repeating: 0, count: size)
        guard sysctl(&mib, 3, &bytes, &size, nil, 0) == 0, size >= MemoryLayout<Int32>.size,
              bytes.withUnsafeBytes({ $0.loadUnaligned(as: Int32.self) }) >= 2 else { return nil }
        let fields = bytes[MemoryLayout<Int32>.size..<size].split(separator: 0, maxSplits: 3)
        guard fields.count >= 3 else { return nil }
        let path = String(decoding: fields[2], as: UTF8.self)
        return path.hasPrefix("/") && path.hasSuffix("/data/var/run/launchd_bootstrap.plist") ? path : nil
    }
}
