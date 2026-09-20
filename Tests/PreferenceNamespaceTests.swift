// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

enum PreferenceNamespaceTests {
    static func run(_ suite: TestSuite) {
        let buildScript = (try? String(contentsOfFile: "build.sh", encoding: .utf8)) ?? ""
        let sweepBody = buildScript
            .components(separatedBy: "discard_test_preferences() {")
            .dropFirst().first?
            .components(separatedBy: "\n}").first ?? ""
        let sweptNamespaces = sweepBody
            .components(separatedBy: "\"")
            .enumerated()
            .filter { $0.offset % 2 == 1 }
            .map(\.element)
            .filter { $0.hasSuffix(".") }

        suite.expect(!sweptNamespaces.isEmpty,
                     "the preference cleanup namespaces read back out of build.sh")
        suite.expect(sweepBody.contains(#"rm -f "$preferences"/$name*.plist(N)"#),
                     "the preference cleanup removes every plist in each swept namespace")
        suite.expect(buildScript.range(of: #"(?m)^\s*Tests/\*\.swift\s*\\?\s*$"#,
                                       options: .regularExpression) != nil,
                     "build.sh compiles every Swift test file inspected by the namespace guard")

        let paths = ((try? FileManager.default.contentsOfDirectory(atPath: "Tests")) ?? [])
            .filter { $0.hasSuffix(".swift") }
            .sorted()
        suite.expect(!paths.isEmpty, "the preference namespace guard discovers Swift test files")

        func isSwept(_ name: String?) -> Bool {
            guard let name else { return false }
            return sweptNamespaces.contains { name.hasPrefix($0) }
        }

        var declarationCount = 0
        for path in paths {
            let source = (try? String(contentsOfFile: "Tests/" + path, encoding: .utf8)) ?? ""
            suite.expect(!source.isEmpty, "Tests/\(path) reads for preference namespace checks")
            for name in suiteNames(in: source) {
                declarationCount += 1
                suite.expect(isSwept(name),
                             "defaults suite \(name ?? "<unresolved>") in Tests/\(path) is swept")
            }
        }
        suite.expect(declarationCount > 0,
                     "the preference namespace guard discovers suite declarations")

        let constructor = "UserDefaults(suiteName" + ": "
        suite.expect(suiteNames(in: constructor + #""vorss.tests.literal")"#)
                         == ["vorss.tests.literal"],
                     "literal preference suite names are recognized")
        suite.expect(suiteNames(in: #"let name = "com.vorssaint.tests.local""# + "\n"
                         + constructor + "name)") == ["com.vorssaint.tests.local"],
                     "locally declared literal preference suite names are resolved")
        let reusedName = #"let name = "vorss.tests.first""# + "\n"
            + constructor + "name)\n"
            + #"let name = "unsafe.temporary""# + "\n"
            + constructor + "name)"
        suite.expect(suiteNames(in: reusedName) == ["vorss.tests.first", "unsafe.temporary"],
                     "reused local preference suite names resolve at each call")
        suite.expect(!suiteNames(in: reusedName).allSatisfy(isSwept),
                     "a temporary unswept preference namespace fails the guard")
        suite.expect(suiteNames(in: constructor + "computedName())") == [nil],
                     "computed preference suite names fail closed")
    }

    private static func suiteNames(in source: String) -> [String?] {
        let calls = try! NSRegularExpression(pattern: #"\bUserDefaults\s*\(\s*suiteName\s*:\s*"#)
        let fullRange = NSRange(source.startIndex..., in: source)
        return calls.matches(in: source, range: fullRange).map { match in
            let matchRange = Range(match.range, in: source)!
            let argument = source[matchRange.upperBound...]
            if argument.first == "\"" {
                return String(argument.dropFirst().prefix { $0 != "\"" })
            }

            let variable = String(argument.prefix { $0.isLetter || $0.isNumber || $0 == "_" })
            guard !variable.isEmpty,
                  argument.dropFirst(variable.count).drop(while: \.isWhitespace).first == ")" else {
                return nil
            }
            let declarations = try! NSRegularExpression(
                pattern: #"\blet\s+"# + NSRegularExpression.escapedPattern(for: variable)
                    + #"\s*=\s*"([^"]*)""#
            )
            guard let declaration = declarations.matches(
                in: source,
                range: NSRange(source.startIndex..<matchRange.lowerBound, in: source)
            ).last,
                  let nameRange = Range(declaration.range(at: 1), in: source) else {
                return nil
            }
            return String(source[nameRange])
        }
    }
}
