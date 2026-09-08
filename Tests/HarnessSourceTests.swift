// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

enum HarnessSourceTests {
    static func run(expect: (Bool, String) -> Void) {
        let buildScript = (try? String(contentsOfFile: "build.sh", encoding: .utf8)) ?? ""
        let sweepBody = buildScript.components(separatedBy: "discard_test_preferences() {")
            .dropFirst().first?.components(separatedBy: "\n}").first ?? ""
        let sweptNamespaces = sweepBody.components(separatedBy: "\"")
            .enumerated().filter { $0.offset % 2 == 1 }.map(\.element)
            .filter { $0.hasSuffix(".") }
        expect(!sweptNamespaces.isEmpty, "the swept namespaces read back out of build.sh")
        expect(sweepBody.contains("rm -f \"$preferences\"/$name*.plist(N)"),
               "the defaults preference sweep tolerates an already-empty namespace")
        let buildCode = buildScript.components(separatedBy: "\n")
            .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("#") }
        expect(buildCode.contains { $0.trimmingCharacters(in: .whitespaces) == "Tests/*.swift \\" },
               "build.sh compiles the same Swift test corpus the namespace guard inspects")

        // cfprefsd can recreate these plists after exit, so the build script must
        // recognize every suite, including ones in extracted test files.
        let paths = ((try? FileManager.default.contentsOfDirectory(atPath: "Tests")) ?? [])
            .filter { $0.hasSuffix(".swift") }.sorted()
        expect(!paths.isEmpty, "the namespace guard discovers Swift test sources")
        var suiteCount = 0
        for path in paths {
            let source = (try? String(contentsOfFile: "Tests/" + path, encoding: .utf8)) ?? ""
            expect(!source.isEmpty, "Tests/\(path) reads back for namespace checks")
            for name in suiteNames(in: source) {
                suiteCount += 1
                expect(name.map { value in sweptNamespaces.contains { value.hasPrefix($0) } } == true,
                       "defaults suite \(name ?? "<unresolved>") in Tests/\(path) is named inside a namespace build.sh sweeps")
            }
        }
        expect(suiteCount > 0, "the namespace check finds the suites it guards")

        // Only main exits without unwinding. Cleanup defers in returning feature
        // suites are valid and must not be rejected by a whole-corpus text scan.
        let harness = (try? String(contentsOfFile: "Tests/MetricsTests.swift", encoding: .utf8)) ?? ""
        expect(!harness.isEmpty, "the exit-owning harness reads back for its cleanup check")
        expect(!harness.contains("defer {"), "the exit-owning harness leaves cleanup to returning suites")

        // Split the constructor so fixture text is not itself a source match.
        let constructor = "UserDefaults(suiteName" + ": "
        expect(suiteNames(in: constructor + "\"vorss.tests.literal\")") == ["vorss.tests.literal"],
               "the namespace scanner recognizes literal suite names")
        expect(suiteNames(in: "let suite = \"com.vorssaint.tests.first\"\n" + constructor + "suite)")
               == ["com.vorssaint.tests.first"], "the namespace scanner resolves a local suite name")
        let repeated = "let suite = \"vorss.tests.first\"\n" + constructor + "suite)\n"
            + "let suite = \"unsafe.second\"\n" + constructor + "suite)"
        expect(suiteNames(in: repeated) == ["vorss.tests.first", "unsafe.second"],
               "reused fixture variable names resolve at each call, not at the first declaration")
        expect(suiteNames(in: constructor + "suite)") == [nil],
               "a suite variable cannot borrow its declaration from another test file")
        expect(suiteNames(in: constructor + "makeSuite())") == [nil],
               "unresolved suite expressions fail closed")
        expect(suiteNames(in: "let suite = \"vorss.tests.original\"\n"
               + constructor + "suite.replacingOccurrences(of: \"vorss.tests.\", with: \"unsafe.\"))") == [nil],
               "a transformed suite expression cannot borrow the original literal's namespace")
        expect(suiteNames(in: "UserDefaults (\n suiteName:\n \"vorss.tests.multiline\")")
               == ["vorss.tests.multiline"], "the namespace scanner accepts multiline constructors")
        expect(suiteNames(in: "let suite = \"unsafe.name\"\n" + constructor + "suite)")
               .allSatisfy { name in name.map { value in sweptNamespaces.contains { value.hasPrefix($0) } } == true }
               == false, "an unswept namespace in an extracted suite is rejected")
    }

    private static func suiteNames(in source: String) -> [String?] {
        let calls = try! NSRegularExpression(pattern: #"\bUserDefaults\s*\(\s*suiteName\s*:\s*"#)
        return calls.matches(in: source, range: NSRange(source.startIndex..., in: source)).map { match in
            let range = Range(match.range, in: source)!
            let argument = source[range.upperBound...]
            if argument.first == "\"" {
                return String(argument.dropFirst().prefix { $0 != "\"" })
            }
            let variable = String(argument.prefix { $0.isLetter || $0.isNumber || $0 == "_" })
            guard !variable.isEmpty,
                  argument.dropFirst(variable.count).drop(while: { $0.isWhitespace }).first == ")"
            else { return nil }
            let declarations = try! NSRegularExpression(
                pattern: #"\blet\s+"# + NSRegularExpression.escapedPattern(for: variable) + #"\s*=\s*"([^"]*)""#)
            // Resolve in this file and before this call. Different suites often
            // use the same short fixture variable name.
            guard let declaration = declarations.matches(in: source,
                range: NSRange(source.startIndex..<range.lowerBound, in: source)).last,
                let nameRange = Range(declaration.range(at: 1), in: source) else { return nil }
            return String(source[nameRange])
        }
    }
}
