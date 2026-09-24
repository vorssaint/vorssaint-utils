// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import SwiftUI

/// The tool picker must never make the Screen capture page wider than its
/// column: a wider page is centered and cut on both sides, under the sidebar.
enum ScreenCaptureToolPickerTests {
    static func run(_ suite: TestSuite) {
        // The narrowest page row: the Settings window's 772-point minimum, less
        // the sidebar at its widest and the grouped form's insets.
        let narrowestRow: CGFloat = 772 - 240 - 60
        for (language, strings) in LocalizationTests.languages {
            let picker = NSHostingController(rootView: ScreenCaptureToolPicker(
                tools: ScreenCaptureTool.allCases, strings: strings, language: language,
                selection: .constant(.screenshot)))
            let narrow = picker.sizeThatFits(in: CGSize(width: narrowestRow, height: 200)).width
            suite.expect(narrow > 0 && narrow <= narrowestRow,
                         "\(language.rawValue): the four capture tools fit the narrowest Settings page "
                         + "(\(Int(narrow)) of \(Int(narrowestRow)) points)")
            if language == .enUS {
                let roomy = picker.sizeThatFits(in: CGSize(width: 2000, height: 200)).width
                suite.expect(roomy > narrowestRow,
                             "the capture tools stay segmented where the segments fit")
            }
        }
    }
}
