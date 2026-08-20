// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// The small, explicit command used by the on-demand audio recovery action.
/// Keeping it in a pure helper makes the privileged operation easy to audit
/// and keeps the command-line test harness independent of AppKit.
enum AudioRecoverySupport {
    static let processName = "coreaudiod"
    static let resetCommand = "/usr/bin/killall \(processName)"
}
