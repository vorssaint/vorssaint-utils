// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// The startup items list's pure rules: which labels may reach launchctl, which
/// entries are locked, how launch agent files and launchctl output are read, and
/// the exact commands used to switch an agent.
enum StartupItemSupportTests {
    static func run(_ suite: TestSuite) {
        suite.expect(StartupItemSupport.isValidLabel("com.vendor.helper-2_x+y"),
                     "an ordinary reverse-domain label is accepted")
        suite.expect(!StartupItemSupport.isValidLabel("")
                     && !StartupItemSupport.isValidLabel("a/b")
                     && !StartupItemSupport.isValidLabel("a b")
                     && !StartupItemSupport.isValidLabel("a;b")
                     && !StartupItemSupport.isValidLabel("../x")
                     && !StartupItemSupport.isValidLabel("caf\u{00E9}")
                     && !StartupItemSupport.isValidLabel(String(repeating: "a", count: 201)),
                     "empty, long, spaced, path-like or non-ASCII labels never reach launchctl")

        suite.expect(StartupItemSupport.isLocked("com.apple.Finder")
                     && StartupItemSupport.isLocked("COM.APPLE.thing")
                     && StartupItemSupport.isLocked("com.vorssaint.utils")
                     && !StartupItemSupport.isLocked("com.apple2.vendor")
                     && !StartupItemSupport.isLocked("com.vendor.helper"),
                     "macOS and Vorssaint entries are locked, lookalikes are not")

        let entry = StartupItemSupport.entry(from: ["Label": "com.vendor.helper",
                                                    "ProgramArguments": ["/usr/local/bin/helper", "--run"],
                                                    "RunAtLoad": true])
        suite.expect(entry == StartupItemSupport.Entry(label: "com.vendor.helper", program: "/usr/local/bin/helper",
                                                       runAtLoad: true, plistDisabled: false),
                     "an agent plist is read into a label, program and flags")
        suite.expect(StartupItemSupport.entry(from: ["Program": "/bin/x"]) == nil
                     && StartupItemSupport.entry(from: ["Label": ""]) == nil,
                     "a plist without a usable label is ignored")
        suite.expect(StartupItemSupport.entry(from: ["Label": "a.b", "Program": "/p", "ProgramArguments": ["/q"],
                                                     "Disabled": true])?.program == "/p"
                     && StartupItemSupport.entry(from: ["Label": "a.b", "Disabled": true])?.plistDisabled == true,
                     "Program wins over ProgramArguments and a Disabled key is honored")

        let printed = """
        disabled services = {
            "com.vendor.off" => disabled
            "com.vendor.on" => enabled
            "com.vendor.legacy" => true
            "com.vendor.legacyoff" => false
        }
        """
        suite.expect(StartupItemSupport.disabledLabels(fromPrintDisabled: printed)
                     == ["com.vendor.off", "com.vendor.legacy"],
                     "launchctl's disabled list is read in both wordings")

        suite.expect(StartupItemSupport.disableCommands(uid: 501, label: "com.vendor.helper")
                     == [["disable", "gui/501/com.vendor.helper"], ["bootout", "gui/501/com.vendor.helper"]]
                     && StartupItemSupport.enableCommands(uid: 501, label: "com.vendor.helper", plistPath: "/p/a.plist")
                     == [["enable", "gui/501/com.vendor.helper"], ["bootstrap", "gui/501", "/p/a.plist"]],
                     "switching an agent uses exactly these launchctl calls")
    }
}
