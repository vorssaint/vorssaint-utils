// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

struct ClipboardTextCaseTransformTests {
    static func run(_ suite: TestSuite) {
        suite.expect(ClipboardTextCaseTransform.allCases.count == 4, "four transforms are offered")
        suite.expect(ClipboardTextCaseTransform.uppercase.apply("mixed Case text") == "MIXED CASE TEXT",
                     "uppercase applies localizedUppercase")
        suite.expect(ClipboardTextCaseTransform.lowercase.apply("Mixed CASE Text") == "mixed case text",
                     "lowercase applies localizedLowercase")
        suite.expect(ClipboardTextCaseTransform.titleCase.apply("mixed case text") == "Mixed Case Text",
                     "title case applies localizedCapitalized")

        let sentences: [(String, String)] = [
            ("", ""),
            ("hello world. how are you? fine! go on", "Hello world. How are you? Fine! Go on"),
            ("first line\nsecond line", "First line\nSecond line"),
            ("version 1.2 works", "Version 1.2 works"),
            ("he said. \"go on\"", "He said. \"Go on\""),
            ("end.\tnew row", "End.\tNew row"),
            ("Already fine.", "Already fine."),
            ("HELLO WORLD. MORE.", "Hello world. More."),
            ("你好。世界", "你好。世界"),
        ]
        for (input, expected) in sentences {
            suite.expect(ClipboardTextCaseTransform.sentenceCase(input) == expected,
                         "sentence case of \(input) is \(expected)")
        }

        suite.expect(ClipboardTextCaseTransform.uppercase.menuTitle(.enUS) == "UPPERCASE"
                     && ClipboardTextCaseTransform.sentenceCase.menuTitle(.enUS) == "Sentence case",
                     "menu titles come from the clipboard strings")
    }
}
