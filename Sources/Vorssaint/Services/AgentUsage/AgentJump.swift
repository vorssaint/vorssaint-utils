// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import Darwin

/// Brings a board session's terminal forward, down to the tab where the
/// terminal can be scripted. Reads the process's tty and owning app at click
/// time and keeps nothing.
enum AgentJump {
    /// Main thread. Collapses the island once the terminal is on its way,
    /// unless `collapse` is false (an approval card must stay answerable).
    static func open(_ session: AgentSessionRow, collapse: Bool = true) {
        guard let (pid, cwd) = process(of: session), let app = ResponsibleProcess.regularAppOwner(of: pid) else { return }
        let kind = AgentTerminalKind(bundleIdentifier: app.bundleIdentifier)
        if collapse { NotchService.shared.collapse() }
        if kind == .vscode {
            guard let cwd else { return activate(app) }
            if let window = vsCodeWindow(app, cwd: cwd) {
                WindowActivator.activate(pid: app.processIdentifier, windowID: window, appName: app.localizedName ?? "")
            } else if !Permissions.shared.accessibility, let bundle = app.bundleURL {
                // Without window titles, opening the folder brings the window holding it
                // forward; a folder below the workspace root would open a new window.
                ActivationHandoff.yield(to: app)
                NSWorkspace.shared.open([URL(fileURLWithPath: cwd, isDirectory: true)], withApplicationAt: bundle,
                                        configuration: NSWorkspace.OpenConfiguration())
            } else {
                activate(app)
            }
            return
        }
        guard let script = AgentJumpSupport.script(for: kind, tty: tty(of: pid), cwd: cwd) else {
            return activate(app)
        }
        // The script blocks until the terminal replies, and a consent prompt
        // can keep it waiting; a miss or a declined consent still activates.
        DispatchQueue.global(qos: .userInitiated).async {
            let found = AppleScriptRunner.runDetailed(script).output == "yes"
            if !found { DispatchQueue.main.async { activate(app) } }
        }
    }

    /// Claude rows carry their pid; a Codex row finds its process from the
    /// rollout's first line.
    private static func process(of session: AgentSessionRow) -> (pid: pid_t, cwd: String?)? {
        if let pid = session.pid { return (pid, session.cwd) }
        guard session.provider == .codex,
              let handle = FileHandle(forReadingAtPath: session.id) else { return nil }
        defer { try? handle.close() }
        // session_meta carries the instructions, so its line can run long.
        guard let head = try? handle.read(upToCount: 1 << 20),
              let meta = AgentJumpSupport.codexMeta(firstLine: head.prefix { $0 != 0x0A }),
              let match = AgentJumpSupport.codexProcess(cwd: meta.cwd, started: meta.started, among: codexProcesses())
        else { return nil }
        return (match.pid, match.cwd)
    }

    private static func codexProcesses() -> [AgentSessionProcess] {
        let estimated = max(1, Int(proc_listallpids(nil, 0)))
        var pids = [pid_t](repeating: 0, count: estimated + 32)
        let count = pids.withUnsafeMutableBytes { proc_listallpids($0.baseAddress, Int32($0.count)) }
        guard count > 0 else { return [] }
        return pids.prefix(min(Int(count), pids.count)).compactMap { pid in
            var path = [CChar](repeating: 0, count: Int(MAXPATHLEN) * 4)
            var info = proc_bsdinfo()
            var vnode = proc_vnodepathinfo()
            guard pid > 0, proc_pidpath(pid, &path, UInt32(path.count)) > 0,
                  // The npm package runs a native binary named codex too.
                  (String(cString: path) as NSString).lastPathComponent == "codex",
                  proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, Int32(MemoryLayout<proc_bsdinfo>.size)) > 0
            else { return nil }
            let cwd = proc_pidinfo(pid, PROC_PIDVNODEPATHINFO, 0, &vnode, Int32(MemoryLayout<proc_vnodepathinfo>.size)) > 0
                ? withUnsafeBytes(of: vnode.pvi_cdir.vip_path) { String(cString: $0.bindMemory(to: CChar.self).baseAddress!) }
                : nil
            let started = Date(timeIntervalSince1970: TimeInterval(info.pbi_start_tvsec) + TimeInterval(info.pbi_start_tvusec) / 1e6)
            return AgentSessionProcess(pid: pid, cwd: cwd, started: started)
        }
    }

    private static func activate(_ app: NSRunningApplication) {
        WindowActivator.activate(pid: app.processIdentifier, windowID: nil, appName: app.localizedName ?? "")
    }

    /// Window titles come from Accessibility, which the window switcher
    /// already asks for.
    private static func vsCodeWindow(_ app: NSRunningApplication, cwd: String) -> CGWindowID? {
        guard Permissions.shared.accessibility else { return nil }
        let axApp = AXUIElementCreateApplication(app.processIdentifier)
        AXUIElementSetMessagingTimeout(axApp, 0.35)
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(axApp, kAXWindowsAttribute as CFString, &value) == .success,
              let windows = value as? [AXUIElement] else { return nil }
        let titles = windows.map { window -> String in
            var title: CFTypeRef?
            AXUIElementCopyAttributeValue(window, kAXTitleAttribute as CFString, &title)
            return title as? String ?? ""
        }
        return AgentJumpSupport.vsCodeWindow(titles: titles, cwd: cwd).flatMap { AXWindowResolver.windowID(for: windows[$0]) }
    }

    private static func tty(of pid: pid_t) -> String? {
        var info = proc_bsdinfo()
        let size = Int32(MemoryLayout<proc_bsdinfo>.size)
        guard proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, size) == size,
              info.e_tdev != UInt32(bitPattern: -1),
              let name = devname(dev_t(bitPattern: info.e_tdev), S_IFCHR)
        else { return nil }
        return String(cString: name)
    }
}
