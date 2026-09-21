// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Darwin
import Foundation

/// `canForceQuit` is all that stands between Backspace in the panel's process
/// list and killing WindowServer, so the real guard runs here verbatim. The
/// CPU/GPU rows can be named "pid N", which is why the guard has to resolve the
/// executable name itself instead of trusting the display name.
enum ProcessForceQuitTests {
    struct ProcessUsage {
        let pid: pid_t
        let name: String
    }

    static func run(_ suite: TestSuite) {
        let service = Service()
        suite.expect(!service.canForceQuit(ProcessUsage(pid: getpid(), name: "Whatever")),
                     "the app's own process stays protected")
        suite.expect(!service.canForceQuit(ProcessUsage(pid: 1, name: "pid 1")),
                     "launchd stays protected")
        for name in ["WindowServer", "loginwindow", "kernel_task"] {
            guard let pid = pid(named: name) else { continue }
            suite.expect(!service.canForceQuit(ProcessUsage(pid: pid, name: "pid \(pid)")),
                         "\(name) stays protected behind an unresolved display name")
            suite.expect(!service.canForceQuit(ProcessUsage(pid: pid, name: name)),
                         "\(name) stays protected under its own name")
        }

        let victim = Process()
        victim.executableURL = URL(fileURLWithPath: "/bin/sleep")
        victim.arguments = ["30"]
        try? victim.run()
        suite.expect(service.canForceQuit(ProcessUsage(pid: victim.processIdentifier, name: "sleep")),
                     "an ordinary process can be force quit")
        victim.terminate()
    }

    /// `ps` rather than `proc_name`, which returns nothing for processes owned
    /// by root — exactly the ones these assertions have to reach.
    private static func pid(named target: String) -> pid_t? {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/ps")
        task.arguments = ["-Aceo", "pid,comm"]
        let pipe = Pipe()
        task.standardOutput = pipe
        guard (try? task.run()) != nil else { return nil }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        task.waitUntilExit()
        for line in String(decoding: data, as: UTF8.self).split(separator: "\n") {
            let columns = line.split(separator: " ", omittingEmptySubsequences: true)
            guard columns.count == 2, columns[1] == target else { continue }
            return pid_t(columns[0])
        }
        return nil
    }
}
