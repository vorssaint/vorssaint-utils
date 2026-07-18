// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

enum MouseNavigationDirection: Equatable {
    case back
    case forward
}

enum MouseNavigationSupport {
    /// CoreGraphics numbers the first two side buttons after left, right and
    /// middle as 3 and 4. These are what standard Back and Forward buttons on
    /// multi-button mice expose when another driver has not remapped them.
    static let backButtonNumber: Int64 = 3
    static let forwardButtonNumber: Int64 = 4

    static func direction(forButtonNumber buttonNumber: Int64) -> MouseNavigationDirection? {
        switch buttonNumber {
        case backButtonNumber: return .back
        case forwardButtonNumber: return .forward
        default: return nil
        }
    }

    static func commandCharacter(for direction: MouseNavigationDirection) -> String {
        direction == .back ? "[" : "]"
    }

    /// Apps whose side buttons must reach them untouched. These handle Back
    /// and Forward themselves (or forward the raw press to a guest system),
    /// and none of them exposes the command as a menu bar item the AX path
    /// could press, so swallowing the click would silently drop navigation
    /// the user already had.
    static let passThroughBundleIDs: Set<String> = [
        // Virtualization and remote screens: the press belongs to the guest
        // or remote machine, not to a local menu command.
        "com.parallels.desktop.console",
        "com.vmware.fusion",
        "com.utmapp.UTM",
        "org.virtualbox.app.VirtualBoxVM",
        "com.apple.ScreenSharing",
        "com.microsoft.rdc.macos",
        "com.codeweavers.CrossOver",
        "com.isaacmarovitz.Whisky",
        "com.moonlight-stream.Moonlight",
    ]

    /// The browser family behind this prefix navigates with the side
    /// buttons natively on macOS and keeps Back and Forward out of the
    /// menu bar entirely. One prefix covers every release channel of the
    /// family, including its mail client.
    static let passThroughBundleIDPrefixes = ["org.mozilla."]

    static func shouldPassThrough(bundleIdentifier: String?) -> Bool {
        guard let bundleIdentifier else { return false }
        if passThroughBundleIDs.contains(bundleIdentifier) { return true }
        return passThroughBundleIDPrefixes.contains { bundleIdentifier.hasPrefix($0) }
    }
}
