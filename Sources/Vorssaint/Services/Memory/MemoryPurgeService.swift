// Fork of vorssaint-utils — memory purge/kill actions for MemoryKill.

import AppKit
import Darwin
import Foundation

enum MemoryPurgeService {
    enum Mode {
        case standard
        case deep
        case max
    }

    enum Trigger: String, Codable {
        case manual
        case auto
    }

    struct Result {
        let freedBytes: Int64
        let message: String
    }

    struct Receipt: Codable {
        let timestamp: String
        let mode: String
        let manualOrAuto: String
        let commandUsed: String
        let success: Bool
        let beforeReclaimableEstimate: UInt64?
        let afterReclaimableEstimate: UInt64?
        let durationSeconds: Double
        let note: String?
    }

    static let requiredDeepConfirmation = "I understand deep purge may request administrator password and run /usr/bin/purge"

    static func reclaimableBytes() -> UInt64 {
        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64>.stride / MemoryLayout<integer_t>.stride)
        let host = mach_host_self()
        defer { mach_port_deallocate(mach_task_self_, host) }
        let kr = withUnsafeMutablePointer(to: &stats) { ptr in
            ptr.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(host, HOST_VM_INFO64, $0, &count)
            }
        }
        guard kr == KERN_SUCCESS else { return availableMemoryBytes() }
        let page = UInt64(vm_kernel_page_size)
        return (UInt64(stats.free_count) + UInt64(stats.inactive_count) + UInt64(stats.purgeable_count)) * page
    }

    static func availableMemoryBytes() -> UInt64 {
        reclaimableBytes()
    }

    static func purge(mode: Mode, trigger: Trigger = .manual, confirmationText: String? = nil, completion: @escaping (Result) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async {
            let before = reclaimableBytes()
            let started = Date()
            var commandUsed = "simulation_only"
            var success = true
            var note: String? = "pressure_relief_simulation_only"
            switch mode {
            case .standard:
                triggerPressureRelief(passes: 2)
            case .deep:
                guard confirmationText == requiredDeepConfirmation else {
                    success = false
                    note = "confirmation_mismatch"
                    commandUsed = "none"
                    let after = reclaimableBytes()
                    writeReceipt(.init(timestamp: timestampString(from: started),
                                       mode: "deep",
                                       manualOrAuto: trigger.rawValue,
                                       commandUsed: commandUsed,
                                       success: success,
                                       beforeReclaimableEstimate: before,
                                       afterReclaimableEstimate: after,
                                       durationSeconds: Date().timeIntervalSince(started),
                                       note: note))
                    DispatchQueue.main.async {
                        completion(Result(freedBytes: 0, message: "Deep purge confirmation did not match."))
                    }
                    return
                }
                commandUsed = "/usr/bin/purge"
                let result = Shell.run("/usr/bin/purge", [])
                success = result.status == 0
                note = result.output.trimmingCharacters(in: .whitespacesAndNewlines)
            case .max:
                guard confirmationText == requiredDeepConfirmation else {
                    success = false
                    note = "confirmation_mismatch"
                    commandUsed = "none"
                    let after = reclaimableBytes()
                    writeReceipt(.init(timestamp: timestampString(from: started),
                                       mode: "max",
                                       manualOrAuto: trigger.rawValue,
                                       commandUsed: commandUsed,
                                       success: success,
                                       beforeReclaimableEstimate: before,
                                       afterReclaimableEstimate: after,
                                       durationSeconds: Date().timeIntervalSince(started),
                                       note: note))
                    DispatchQueue.main.async {
                        completion(Result(freedBytes: 0, message: "MAX purge confirmation did not match."))
                    }
                    return
                }
                _ = clearUserCaches()
                triggerPressureRelief(passes: 4)
                _ = flushDNS()
                commandUsed = "/usr/sbin/purge"
                success = AdminShell.runSync("/usr/sbin/purge",
                                              prompt: "MemoryKill needs your password for MAX purge.")
                triggerPressureRelief(passes: 2)
            }
            Thread.sleep(forTimeInterval: 1.0)
            let after = reclaimableBytes()
            let freed = Int64(after) &- Int64(before)
            let message: String
            if mode == .standard {
                message = "Standard pressure relief simulated."
            } else if freed > 32 * 1024 * 1024 {
                message = "\(modeLabel(mode)): freed \(formatBytes(freed))."
            } else {
                message = "\(modeLabel(mode)) complete."
            }
            writeReceipt(.init(timestamp: timestampString(from: started),
                               mode: String(describing: mode),
                               manualOrAuto: trigger.rawValue,
                               commandUsed: commandUsed,
                               success: success,
                               beforeReclaimableEstimate: before,
                               afterReclaimableEstimate: after,
                               durationSeconds: Date().timeIntervalSince(started),
                               note: note?.isEmpty == true ? nil : note))
            DispatchQueue.main.async {
                completion(Result(freedBytes: max(freed, 0), message: message))
            }
        }
    }

    static func flushDNS() -> String {
        let flush = Shell.run("/usr/bin/dscacheutil", ["-flushcache"])
        let mdns = Shell.run("/usr/bin/killall", ["-HUP", "mDNSResponder"])
        if flush.status == 0 {
            return mdns.status == 0 ? "DNS cache flushed." : "DNS flushed (mDNSResponder was not running)."
        }
        return "DNS flush failed."
    }

    @discardableResult
    static func clearUserCaches() -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let targets = [
            "\(home)/Library/Caches",
            "\(home)/Library/Logs/DiagnosticReports",
            "\(home)/Library/Developer/Xcode/DerivedData"
        ]
        var removed = 0
        var bytes: Int64 = 0

        for target in targets {
            guard let entries = try? FileManager.default.contentsOfDirectory(atPath: target) else { continue }
            for entry in entries {
                let path = "\(target)/\(entry)"
                let size = pathSize(path)
                if (try? FileManager.default.removeItem(atPath: path)) != nil {
                    removed += 1
                    bytes += size
                }
            }
        }

        if removed == 0 { return "No removable user caches found." }
        return "Removed \(removed) cache folders (\(formatBytes(bytes)))."
    }

    @discardableResult
    static func killProcess(pid: pid_t, name: String) -> String {
        if isProtected(pid: pid, name: name) {
            return "Refusing to kill protected process: \(name)."
        }
        if kill(pid, SIGTERM) != 0 {
            if kill(pid, SIGKILL) != 0 {
                return "Failed to kill \(name): \(String(cString: strerror(errno)))"
            }
            return "Force quit \(name)."
        }
        return "Quit signal sent to \(name)."
    }

    @discardableResult
    static func killTopMemoryHog() -> String {
        let hogs = ProcessUsageService.shared.topMemory(limit: 15)
        guard !hogs.isEmpty else { return "No memory hogs found." }

        let skipped = hogs.filter { isProtected(pid: $0.pid, name: $0.name) }
        guard let hog = hogs.first(where: { !isProtected(pid: $0.pid, name: $0.name) }) else {
            let names = skipped.prefix(3).map(\.name).joined(separator: ", ")
            return "Only protected processes on top (\(names)). MemoryKill won't suicide."
        }

        if let selfHog = skipped.first {
            let result = killProcess(pid: hog.pid, name: hog.name)
            return "Skipped \(selfHog.name) (that's us). \(result)"
        }
        return killProcess(pid: hog.pid, name: hog.name)
    }

    static func isProtected(pid: pid_t, name: String) -> Bool {
        if pid <= 1 || pid == getpid() { return true }

        if let app = NSRunningApplication(processIdentifier: pid),
           let bundleID = app.bundleIdentifier {
            if bundleID == Bundle.main.bundleIdentifier { return true }
            if bundleID.hasPrefix("com.apple.") {
                let allowed = ["com.apple.Safari", "com.apple.dt.Xcode", "com.apple.Notes"]
                if !allowed.contains(bundleID) { return true }
            }
        }

        let lowered = name.lowercased()
        let protectedNames = ["memorykill", "vorssaint", "kernel_task", "launchd",
                              "windowserver", "loginwindow", "sysmond", "mds", "mds_stores"]
        if protectedNames.contains(where: { lowered.contains($0) }) { return true }

        return false
    }

    private static func triggerPressureRelief(passes: Int) {
        for _ in 0..<max(1, passes) {
            _ = malloc_zone_pressure_relief(nil, 0)
            runMemoryPressureTool()
        }
    }

    private static func runMemoryPressureTool() {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/memory_pressure")
        process.arguments = ["-l", "critical", "-Q", "-s", "1"]
        process.standardOutput = Pipe()
        process.standardError = Pipe()
        do {
            try process.run()
            let deadline = Date().addingTimeInterval(5)
            while process.isRunning, Date() < deadline {
                Thread.sleep(forTimeInterval: 0.1)
            }
            if process.isRunning { process.terminate() }
        } catch {
            // memory_pressure unavailable; malloc relief still ran.
        }
    }

    private static func modeLabel(_ mode: Mode) -> String {
        switch mode {
        case .standard: return "Standard"
        case .deep: return "Deep purge"
        case .max: return "MAX purge"
        }
    }

    private static func timestampString(from date: Date = Date()) -> String {
        ISO8601DateFormatter().string(from: date)
    }

    private static func writeReceipt(_ receipt: Receipt) {
        let directory = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first?
            .appendingPathComponent(AppInfo.name, isDirectory: true)
            .appendingPathComponent("PurgeReceipts", isDirectory: true)
        guard let directory else { return }
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(receipt)
            let name = receipt.timestamp.replacingOccurrences(of: ":", with: "") + ".json"
            try data.write(to: directory.appendingPathComponent(name), options: [.atomic])
        } catch {
            print("PURGE RECEIPT WRITE FAILED: \(error)")
        }
    }

    private static func pathSize(_ path: String) -> Int64 {
        let manager = FileManager.default
        var isDir: ObjCBool = false
        guard manager.fileExists(atPath: path, isDirectory: &isDir) else { return 0 }
        if !isDir.boolValue {
            let attrs = try? manager.attributesOfItem(atPath: path)
            return (attrs?[.size] as? NSNumber)?.int64Value ?? 0
        }
        guard let children = manager.enumerator(atPath: path) else { return 0 }
        var total: Int64 = 0
        for case let child as String in children {
            let attrs = try? manager.attributesOfItem(atPath: "\(path)/\(child)")
            total += (attrs?[.size] as? NSNumber)?.int64Value ?? 0
        }
        return total
    }

    private static func formatBytes(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .memory)
    }
}
