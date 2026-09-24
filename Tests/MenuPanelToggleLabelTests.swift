// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// A switch with a hidden label still gives VoiceOver its title, so an empty
/// one is read as an unnamed switch.
enum MenuPanelToggleLabelContract {
    static func run(_ suite: TestSuite) {
        let source = (try? String(contentsOfFile:
                "Sources/Vorssaint/UI/MenuPanel/MenuPanelView.swift", encoding: .utf8)) ?? ""
        let code = source.components(separatedBy: "\n")
            .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }
            .joined(separator: "\n")
        suite.expect(!code.isEmpty, "the menu panel source is readable from the repo root")
        let unnamed = code.components(separatedBy: "Toggle(\"\", isOn:").count - 1
        suite.expect(unnamed == 0, "every menu panel switch has a name for VoiceOver, found \(unnamed) unnamed")
    }
}
