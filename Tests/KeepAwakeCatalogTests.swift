// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// Keep awake turns any duration outside its presets into an indefinite
/// session. The Command Bar must therefore never hand it a typed number, and
/// every preset must stay reachable as a row of its own.
enum KeepAwakeCatalogContract {
    static func run(_ suite: TestSuite) {
        let source = (try? String(contentsOfFile:
                "Sources/Vorssaint/Services/CommandBar/CommandBarCatalog.swift", encoding: .utf8)) ?? ""
        let code = source.components(separatedBy: "\n")
            .map { line in line.range(of: "//").map { String(line[..<$0.lowerBound]) } ?? line }
            .joined(separator: "\n")
        suite.expect(!code.isEmpty, "the Command Bar catalog is readable from the repo root")
        guard let start = code.range(of: "id: \"action.keepAwake\","),
              let end = code.range(of: "let durations", range: start.upperBound..<code.endIndex) else {
            suite.expect(false, "the plain keep awake row and its preset list are still found")
            return
        }
        let plainRow = code[start.lowerBound..<end.lowerBound]
        suite.expect(!plainRow.contains("numericRange"),
                     "the plain keep awake row takes no number that could become indefinite")

        for minutes in Defaults.allowedDurations where minutes > 0 {
            let id = "\"action.keepAwake.\(minutes)\""
            suite.expect(code.contains("(" + id + ", ") && code.contains(", \(minutes)),"),
                         "keep awake for \(minutes) minutes has its own Command Bar row")
        }
    }
}
