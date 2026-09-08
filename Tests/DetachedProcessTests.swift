// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Darwin
import Foundation

enum DetachedProcessTests {
    static func run(expect: (Bool, String) -> Void) -> ((Bool, String) -> Void) -> Void {
        // The fallback branch has to be chosen on whether perl is there, never
        // on an exit code: perl execs the payload, so the status the shell sees
        // is the payload's own. Every `exit 1` inside the installer script would
        // otherwise start the whole installer a second time, as root.
        let detachRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("VorssaintDetachTests-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: detachRoot, withIntermediateDirectories: true)
        let detachPayload = detachRoot.appendingPathComponent("payload.sh")
        let detachLedger = detachRoot.appendingPathComponent("runs")
        try? "#!/bin/sh\n/bin/echo ran >> \"$1\"\nexit 1\n"
            .write(to: detachPayload, atomically: true, encoding: .utf8)
        let detachCommand = DetachedProcess.detachedShellCommand(
            quotedArgv: ["/bin/sh", detachPayload.path, detachLedger.path]
                .map(UpdateInstallerSupport.shellSingleQuoted)
                .joined(separator: " "))
        let detachShell = Process()
        detachShell.executableURL = URL(fileURLWithPath: "/bin/sh")
        detachShell.arguments = ["-c", detachCommand]
        try? detachShell.run()
        detachShell.waitUntilExit()
        func detachedRunCount() -> Int {
            (try? String(contentsOf: detachLedger, encoding: .utf8))?
                .split(separator: "\n").count ?? 0
        }
        for _ in 0..<300 where detachedRunCount() == 0 { usleep(10_000) }
        expect(detachedRunCount() == 1, "a detached command starts its payload once")
        // The harness invokes the returned check late, after intervening suites:
        // a second run arriving after a short fixed wait must not read as a pass.

        // A detached spawn is only detached if the child really is its own
        // session leader; `nohup` alone leaves it in ours.
        do {
            let child = try DetachedProcess.spawn("/bin/sleep", ["30"])
            expect(getsid(child) == child,
                   "a detached child is its own session leader")
            expect(getsid(child) != getsid(0),
                   "a detached child is not in this process's session")
            kill(child, SIGKILL)
            var reaped: Int32 = 0
            waitpid(child, &reaped, 0)
        } catch {
            expect(false, "detached spawn failed: \(error.localizedDescription)")
        }

        // A child built to outlive this app must not carry this app's open
        // descriptors with it: the app is gone before the child does its work,
        // so anything it inherited is held open by a process nobody can see or
        // close. `Process` gave its children a clean table; these children get
        // the same. 0/1/2 must still be open (on /dev/null), or the child's
        // first open() takes stdout's slot.
        let fdRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("VorssaintDetachFDTests-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: fdRoot, withIntermediateDirectories: true)
        let fdHolder = fdRoot.appendingPathComponent("holder")
        let fdReport = fdRoot.appendingPathComponent("report")
        // Opened WITHOUT O_CLOEXEC, the way a plain open() anywhere in the app
        // leaves it — that is the descriptor that must not travel.
        let holderDescriptor = open(fdHolder.path, O_RDWR | O_CREAT | O_TRUNC, 0o644)
        expect(holderDescriptor >= 3, "fd probe holds a descriptor above stdio")
        do {
            let probe = "{ /bin/echo leaked >&\(holderDescriptor); } 2>/dev/null; INHERITED=$?; "
                + "{ /bin/echo stdio; } 2>/dev/null; STDIO=$?; "
                + "/bin/echo \"$INHERITED $STDIO\" > \(UpdateInstallerSupport.shellSingleQuoted(fdReport.path))"
            let child = try DetachedProcess.spawn("/bin/sh", ["-c", probe])
            var reaped: Int32 = 0
            waitpid(child, &reaped, 0)
            let report = ((try? String(contentsOf: fdReport, encoding: .utf8)) ?? "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let status = report.split(separator: " ").map(String.init)
            expect(status.count == 2 && status[0] != "0",
                   "a detached child does not inherit this app's open descriptors (probe: \"\(report)\")")
            expect(((try? String(contentsOf: fdHolder, encoding: .utf8)) ?? "").isEmpty,
                   "a detached child cannot write through a descriptor this app opened")
            expect(status.count == 2 && status[1] == "0",
                   "a detached child still has stdout open (probe: \"\(report)\")")
        } catch {
            expect(false, "detached fd probe failed: \(error.localizedDescription)")
        }
        close(holderDescriptor)
        try? FileManager.default.removeItem(at: fdRoot)

        return { expect in
            // MARK: Detached command reruns (counted last, so a late rerun still fails)
            // The `||` form reran the whole installer — as root — on every non-zero
            // payload exit. Counting here rather than after a fixed wait leaves the
            // check no window a second run can arrive behind.
            let detachedRuns = detachedRunCount()
            expect(detachedRuns == 1,
                   "a detached command runs its payload once whatever the payload exits with "
                   + "(ran \(detachedRuns) time(s))")
            try? FileManager.default.removeItem(at: detachRoot)

        }
    }
}
