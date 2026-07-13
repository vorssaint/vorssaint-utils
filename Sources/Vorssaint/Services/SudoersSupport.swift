// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

enum SudoersSupport {
    /// A successful `sudo -l` only means that a command is allowed. The verbose
    /// listing must also include sudoers' `!authenticate` option to prove that
    /// the command can run without prompting for a password.
    static func allowsWithoutPassword(status: Int32, output: String) -> Bool {
        guard status == 0 else { return false }
        return output
            .split { $0.isWhitespace || $0 == "," }
            .contains("!authenticate")
    }
}
