// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Darwin
import Foundation

/// Starting something that has to outlive this app: the update installer, the
/// uninstall and rename scripts, and the relaunch helpers — every one of them
/// waits for this process to go away before it does its work.
///
/// `nohup` is not enough: it only makes the child ignore SIGHUP. The child
/// stays in this app's session and launchd job, so whatever tears that job
/// down takes the installer with it, and the swap never happens (issue #731,
/// reported under Endpoint Privilege Management). Leaving the session is the
/// property that makes the child survive, and setsid(2) is the only way to
/// get it.
enum DetachedProcess {
    /// POSIX_SPAWN_SETSID: the kernel makes the child its own session leader
    /// before it execs, so there is no window where it belongs to us.
    /// CLOEXEC_DEFAULT keeps this app's other descriptors out of a child that
    /// outlives it, as `Process` already did for the children it spawned.
    /// Returns the child pid, or throws the spawn errno.
    @discardableResult
    static func spawn(_ executablePath: String, _ arguments: [String]) throws -> pid_t {
        var attributes: posix_spawnattr_t?
        posix_spawnattr_init(&attributes)
        defer { posix_spawnattr_destroy(&attributes) }
        posix_spawnattr_setflags(&attributes,
                                 Int16(POSIX_SPAWN_SETSID | POSIX_SPAWN_CLOEXEC_DEFAULT))

        // CLOEXEC_DEFAULT closes 0/1/2 as well, and the child's first open()
        // would take one of them — stdout landing inside a data file. Give
        // those three /dev/null, the stdio the elevated command redirects to
        // itself.
        var fileActions: posix_spawn_file_actions_t?
        posix_spawn_file_actions_init(&fileActions)
        defer { posix_spawn_file_actions_destroy(&fileActions) }
        posix_spawn_file_actions_addopen(&fileActions, 0, "/dev/null", O_RDONLY, 0)
        posix_spawn_file_actions_addopen(&fileActions, 1, "/dev/null", O_WRONLY, 0)
        posix_spawn_file_actions_addopen(&fileActions, 2, "/dev/null", O_WRONLY, 0)

        let argv: [UnsafeMutablePointer<CChar>?] =
            ([executablePath] + arguments).map { strdup($0) } + [nil]
        defer { for argument in argv { free(argument) } }

        var pid: pid_t = 0
        let status = posix_spawn(&pid, executablePath, &fileActions, &attributes, argv, environ)
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
    /// The branch is taken on whether perl is *there*, never on an exit code:
    /// perl execs the payload, so the status the shell sees is the payload's
    /// own, and an `||` fallback would rerun the whole installer — as root —
    /// every time it exited non-zero. perl therefore carries the setsid(2)
    /// failure case itself, degrading to nohup's ignored SIGHUP (a signal
    /// disposition survives exec) instead of handing the decision back.
    ///
    /// `quotedArgv` is the program and its arguments, already quoted for sh.
    static func detachedShellCommand(quotedArgv: String) -> String {
        let setsid = "/usr/bin/perl -e 'use POSIX (); "
            + "POSIX::setsid(); $SIG{HUP} = \"IGNORE\"; exec @ARGV; exit 127'"
        return "set -- \(quotedArgv); { if [ -x /usr/bin/perl ]; then exec \(setsid) \"$@\"; "
            + "else exec /usr/bin/nohup \"$@\"; fi; } >/dev/null 2>&1 &"
    }
}
