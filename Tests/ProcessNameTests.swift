// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// Names in the resource lists run the production lookup against doubles, so
/// the fallbacks are checked whatever processes this Mac lets the tests read.
enum ProcessNameContract {
    enum Environment {
        static var appNames: [pid_t: String] = [:]
        static var kernelNames: [pid_t: String] = [:]
        static var paths: [pid_t: String] = [:]
    }
    final class NSRunningApplication {
        let localizedName: String?
        init?(processIdentifier: pid_t) {
            guard let name = Environment.appNames[processIdentifier] else { return nil }
            localizedName = name
        }
    }
    class Fixture {
        static func proc_name(_ pid: pid_t, _ buffer: UnsafeMutableRawPointer?, _ size: UInt32) -> Int32 {
            write(Environment.kernelNames[pid], to: buffer, size: size)
        }
        static func proc_pidpath(_ pid: pid_t, _ buffer: UnsafeMutableRawPointer?, _ size: UInt32) -> Int32 {
            write(Environment.paths[pid], to: buffer, size: size)
        }
        /// Like libproc: the C string lands in the buffer, a refusal returns 0.
        private static func write(_ text: String?, to buffer: UnsafeMutableRawPointer?, size: UInt32) -> Int32 {
            guard let text, let buffer else { return 0 }
            let bytes = Array(text.utf8CString)
            guard bytes.count <= Int(size) else { return 0 }
            bytes.withUnsafeBytes { buffer.copyMemory(from: $0.baseAddress!, byteCount: $0.count) }
            return Int32(bytes.count - 1)
        }
    }

    static func run(_ suite: TestSuite) {
        func name(_ pid: pid_t) -> String { Lookup.displayName(pid: pid, fallback: "pid \(pid)") }
        Environment.appNames = [501: "Safari"]
        Environment.kernelNames = [501: "Safari", 502: "loginwindow"]
        Environment.paths = [
            100: "/System/Library/PrivateFrameworks/SkyLight.framework/Versions/A/Resources/WindowServer",
            104: "/usr/libexec/runningboardd",
            502: "/System/Library/CoreServices/loginwindow.app/Contents/MacOS/loginwindow",
        ]
        suite.expect(name(501) == "Safari", "an app keeps its localized name")
        suite.expect(name(502) == "loginwindow", "a process of the same user keeps its kernel name")
        // The GPU list showed "pid 100" for WindowServer: macOS 27 refuses
        // proc_name for another user's process but still gives its path.
        suite.expect(name(100) == "WindowServer", "another user's process is named from its executable")
        suite.expect(name(104) == "runningboardd", "a daemon is named from its executable")
        suite.expect(name(999) == "pid 999", "a process that is gone keeps the caller's hint")
        Environment.appNames = [:]
        Environment.kernelNames = [:]
        Environment.paths = [:]
    }
}
