// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Darwin
import Foundation

/// Starting something that has to outlive this app — the update installer,
/// which replaces the very bundle we are running from.
///
/// `nohup` is not enough: it only makes the child ignore SIGHUP. The child
/// stays in this app's session and launchd job, so whatever tears that job
/// down takes the installer with it, and the swap never happens (issue #731,
/// reported under Endpoint Privilege Management). Leaving the session is the
/// property that makes the child survive, and setsid(2) is the only way to
/// get it.
enum DetachedProcess {
    /// posix_spawn with POSIX_SPAWN_SETSID: the kernel makes the child its own
    /// session leader before it execs, so there is no window where it belongs
    /// to us. Returns the child pid. Throws the spawn errno so callers can
    /// report the failure the same way `Process.run()` let them.
    @discardableResult
    static func spawn(_ executablePath: String, _ arguments: [String]) throws -> pid_t {
        var attributes: posix_spawnattr_t?
        posix_spawnattr_init(&attributes)
        defer { posix_spawnattr_destroy(&attributes) }
        posix_spawnattr_setflags(&attributes, Int16(POSIX_SPAWN_SETSID))

        let argv: [UnsafeMutablePointer<CChar>?] =
            ([executablePath] + arguments).map { strdup($0) } + [nil]
        defer { for argument in argv { free(argument) } }

        var pid: pid_t = 0
        let status = posix_spawn(&pid, executablePath, nil, &attributes, argv, environ)
        guard status == 0 else {
            throw NSError(domain: NSPOSIXErrorDomain, code: Int(status),
                          userInfo: [NSLocalizedDescriptionKey: String(cString: strerror(status))])
        }
        return pid
    }

    /// The same detachment for a command that can only travel as a shell
    /// string: the elevated installer goes through the system administrator
    /// prompt, which takes one command, not an argument vector.
    ///
    /// macOS ships no setsid(1), so the session is left by the smallest tool
    /// present on every macOS that can call setsid(2). If it is ever missing,
    /// the command falls back to the previous nohup form — a child that may
    /// still be swept away beats an update that cannot start at all.
    ///
    /// `quotedArgv` is the program and its arguments, already quoted for sh.
    static func detachedShellCommand(quotedArgv: String) -> String {
        let setsid = "/usr/bin/perl -e 'use POSIX (); POSIX::setsid() > 0 or exit 127; exec @ARGV; exit 127'"
        return "set -- \(quotedArgv); { \(setsid) \"$@\" || /usr/bin/nohup \"$@\"; } >/dev/null 2>&1 &"
    }
}
