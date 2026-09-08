// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Darwin
import Foundation

enum KillProcessTests {
    static func run(expect: (Bool, String) -> Void) {
        // MARK: Kill Process safety
        expect(KillProcessSupport.isProtected(pid: 0, name: "kernel_task", path: "/System/Library/"),
               "PID 0 is protected")
        expect(KillProcessSupport.isProtected(pid: 1, name: "launchd", path: "/sbin/launchd"),
               "PID 1 is protected")
        expect(KillProcessSupport.isProtected(pid: 9999, name: "WindowServer", path: "/System/Library/Frameworks/WindowServer"),
               "WindowServer is protected")
        expect(KillProcessSupport.isProtected(pid: 9999, name: "loginwindow", path: "/System/Library/CoreServices/loginwindow.app/Contents/MacOS/loginwindow"),
               "loginwindow is protected")
        expect(KillProcessSupport.isProtected(pid: ProcessInfo.processInfo.processIdentifier, name: "Vorssaint"),
               "current app PID is protected")
        expect(!KillProcessSupport.isProtected(pid: 12345, name: "Safari", path: "/Applications/Safari.app/Contents/MacOS/Safari"),
               "ordinary user app is not protected")
        expect(KillProcessSupport.numberComesBefore(90, 10, lhsPID: 2, rhsPID: 1,
                                                    ascending: false)
               && KillProcessSupport.numberComesBefore(10, 90, lhsPID: 2, rhsPID: 1,
                                                       ascending: true)
               && !KillProcessSupport.numberComesBefore(10, 10, lhsPID: 2, rhsPID: 1,
                                                        ascending: true),
               "Kill Process numeric sorting is strict and follows the selected direction")
        expect(KillProcessSupport.nameComesBefore("Alpha", "Zulu", lhsPID: 2, rhsPID: 1,
                                                  ascending: true)
               && KillProcessSupport.nameComesBefore("Zulu", "Alpha", lhsPID: 2, rhsPID: 1,
                                                     ascending: false)
               && !KillProcessSupport.nameComesBefore("Same", "same", lhsPID: 2, rhsPID: 1,
                                                      ascending: true),
               "Kill Process name sorting is A to Z by default and strict for ties")
        expect(KillProcessSupport.normalizedStartDescription(" Thu  Aug 27  10:20:30 2026 \n")
                == "Thu Aug 27 10:20:30 2026"
               && KillProcessSupport.normalizedStartDescription("bad'; kill 1") == nil,
               "Kill Process accepts only safe normalized start identities for the admin command")
        // pid 1 -> 10 -> {20, 21} -> 30, with 40 on an unrelated branch, 50
        // its own parent and 21 <-> 22 pointing at each other.
        let processTable: [(pid: pid_t, ppid: pid_t)] = [
            (10, 1), (20, 10), (21, 10), (30, 20), (40, 1), (50, 50), (22, 21), (21, 22),
        ]
        let treeBelowTen = KillProcessSupport.descendants(of: 10, parents: processTable)
        expect(treeBelowTen == [20, 21, 30, 22],
               "Kill Process collects a whole process tree breadth first so the caller kills deepest first")
        expect(KillProcessSupport.descendants(of: 30, parents: processTable).isEmpty
               && KillProcessSupport.descendants(of: 50, parents: processTable).isEmpty,
               "Kill Process reports no descendants for a leaf and never follows a self-parenting row")
    }
}
