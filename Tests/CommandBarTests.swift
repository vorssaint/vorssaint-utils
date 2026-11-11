// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

enum CommandBarTests {
    static func run(_ suite: TestSuite) {
        // Trailing argument extraction with non-alphanumeric separators (issue #4012).
        suite.expect(CommandBarLinks.trailingArgument(query: "go/mr", name: "go/") == "mr",
                     "saved search ending with slash fires without a space")
        suite.expect(CommandBarLinks.trailingArgument(query: "go/mr", name: "go") == "mr",
                     "slash immediately following link name acts as separator")
        suite.expect(CommandBarLinks.trailingArgument(query: "GO/Mr", name: "go") == "Mr",
                     "delimiter matching is case-insensitive and preserves argument case")
        suite.expect(CommandBarLinks.trailingArgument(query: "GO/Mr", name: "go/") == "Mr",
                     "slash-suffixed name matches case-insensitively and preserves argument case")
        suite.expect(CommandBarLinks.trailingArgument(query: "go:mr", name: "go") == "mr",
                     "colon acts as separator when query follows name")
        suite.expect(CommandBarLinks.trailingArgument(query: "go:mr", name: "go:") == "mr",
                     "colon-suffixed name fires without a space")
        suite.expect(CommandBarLinks.trailingArgument(query: "go/a/b", name: "go") == "a/b",
                     "only the first separator is stripped; nested slashes remain in argument")
        suite.expect(CommandBarLinks.trailingArgument(query: "go/a/b", name: "go/") == "a/b",
                     "nested slashes remain in argument for slash-suffixed name")
        suite.expect(CommandBarLinks.trailingArgument(query: "go/ mr", name: "go") == "mr",
                     "space after separator is trimmed from argument")
        suite.expect(CommandBarLinks.trailingArgument(query: "go/ mr", name: "go/") == "mr",
                     "space after slash-suffixed name is trimmed from argument")
        suite.expect(CommandBarLinks.trailingArgument(query: "go/mr and more", name: "go") == "mr and more",
                     "multi-word arguments after slash separator are preserved")

        // Existing whitespace-separated searches continue to work.
        suite.expect(CommandBarLinks.trailingArgument(query: "gh vorssaint utils", name: "gh") == "vorssaint utils",
                     "standard space-delimited search extracts argument")
        suite.expect(CommandBarLinks.trailingArgument(query: "go   mr", name: "go") == "mr",
                     "multiple spaces between name and argument are collapsed")
        suite.expect(CommandBarLinks.trailingArgument(query: "bd\u{3000}123", name: "bd") == "123",
                     "full-width space acts as delimiter")

        // Non-matches: alphanumeric suffixes and bare names without arguments.
        suite.expect(CommandBarLinks.trailingArgument(query: "going", name: "go") == nil,
                     "alphanumeric continuation is not a separator")
        suite.expect(CommandBarLinks.trailingArgument(query: "go123", name: "go") == nil,
                     "numeric continuation is not a separator")
        suite.expect(CommandBarLinks.trailingArgument(query: "ghost writer", name: "gh") == nil,
                     "prefix of a different word does not match")
        suite.expect(CommandBarLinks.trailingArgument(query: "go", name: "go") == nil,
                     "bare name without argument produces no trailing argument")
        suite.expect(CommandBarLinks.trailingArgument(query: "go/", name: "go") == nil,
                     "name followed by separator alone has no argument yet")
        suite.expect(CommandBarLinks.trailingArgument(query: "go/", name: "go/") == nil,
                     "slash-suffixed name alone has no argument yet")
        suite.expect(CommandBarLinks.trailingArgument(query: "go/ ", name: "go") == nil,
                     "separator followed by whitespace alone has no argument")
        suite.expect(CommandBarLinks.trailingArgument(query: "go/ ", name: "go/") == nil,
                     "slash-suffixed name followed by whitespace alone has no argument")

        // Ranking title: keeps the candidate visible when separator is typed.
        suite.expect(CommandBarLinks.rankingTitle(name: "go", query: "go/mr") == "go/mr",
                     "ranking title matches query when argument is present")
        suite.expect(CommandBarLinks.rankingTitle(name: "go", query: "go/") == "go/",
                     "ranking title matches query when separator is typed so row does not sink")
        suite.expect(CommandBarLinks.rankingTitle(name: "go/", query: "go/") == "go/",
                     "ranking title matches query for slash-suffixed name")
        suite.expect(CommandBarLinks.rankingTitle(name: "go", query: "going") == "go",
                     "ranking title stays as name for non-matching alphanumeric continuation")
        suite.expect(CommandBarLinks.rankingTitle(name: "go", query: "go123") == "go",
                     "ranking title stays as name for numeric continuation")

        // Script argument extraction and matching.
        let scriptGo = CommandBarLink(name: "go", kind: .script, destination: "/bin/echo")
        let scriptGoSlash = CommandBarLink(name: "go/", kind: .script, destination: "/bin/echo")
        var scriptBare = CommandBarLink(name: "go", kind: .script, destination: "/bin/echo")
        scriptBare.runsWithoutArgument = true

        suite.expect(CommandBarLinks.scriptArgument(for: scriptGo, query: "go/mr") == "mr",
                     "script answers to slash-delimited query")
        suite.expect(CommandBarLinks.scriptArgument(for: scriptGoSlash, query: "go/mr") == "mr",
                     "slash-suffixed script answers to query")
        suite.expect(CommandBarLinks.scriptArgument(for: scriptGo, query: "go") == nil,
                     "script needing argument returns nil for bare name")
        suite.expect(CommandBarLinks.scriptArgument(for: scriptBare, query: "go") == "",
                     "script running without argument returns empty string for bare name")
        suite.expect(CommandBarLinks.scriptArgument(for: scriptBare, query: "go/") == nil,
                     "script running without argument does not fire on bare separator")

        // Most specific script link wins (longer name).
        if let match = CommandBarLinks.matchingScriptLink(in: [scriptGo, scriptGoSlash], query: "go/mr") {
            suite.expect(match.link.name == "go/" && match.argument == "mr",
                         "longer matching script link name wins")
        } else {
            suite.expect(false, "matching script link should be found")
        }
    }
}
