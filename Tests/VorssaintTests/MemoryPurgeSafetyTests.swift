import Foundation
import XCTest
@testable import Vorssaint

final class MemoryPurgeSafetyTests: XCTestCase {
    func testAutoPurgeDefaultsToDisabled() {
        Defaults.register()
        XCTAssertFalse(UserDefaults.standard.bool(forKey: DefaultsKey.autoPurgeEnabled))
    }

    func testLaunchDoesNotInvokePurge() throws {
        let source = try readSource("Sources/Vorssaint/App/AppDelegate.swift")
        let launch = try functionBody(named: "func applicationDidFinishLaunching(_ notification: Notification)", in: source)
        XCTAssertFalse(launch.contains("MemoryPurgeService.purge"), "Launch must not trigger any purge path.")
    }

    func testStandardAndAutoPathsNeverReferenceAdminShellOrPurgeBinaries() throws {
        let source = try readSource("Sources/Vorssaint/Services/Memory/MemoryPurgeService.swift")
        let purge = try functionBody(named: "static func purge(mode: Mode, trigger: Trigger = .manual, confirmationText: String? = nil, completion: @escaping (Result) -> Void)", in: source)
        let standard = try snippet(from: purge, startingAt: "case .standard:", endingAt: "case .deep:")
        let autoPurger = try readSource("Sources/Vorssaint/Services/Memory/MemoryAutoPurger.swift")

        XCTAssertTrue(standard.contains("triggerPressureRelief"))
        XCTAssertFalse(standard.contains("AdminShell"))
        XCTAssertFalse(standard.contains("/usr/bin/purge"))
        XCTAssertFalse(standard.contains("/usr/sbin/purge"))
        XCTAssertFalse(autoPurger.contains("AdminShell.runSync"))
        XCTAssertFalse(autoPurger.contains("/usr/bin/purge"))
        XCTAssertFalse(autoPurger.contains("/usr/sbin/purge"))
    }

    func testDeepAndMaxPathsAreConfirmationGated() throws {
        let source = try readSource("Sources/Vorssaint/Services/Memory/MemoryPurgeService.swift")
        let deep = try snippet(from: source, startingAt: "case .deep:", endingAt: "case .max:")
        let max = try snippet(from: source, startingAt: "case .max:", endingAt: "Thread.sleep(forTimeInterval: 1.0)")

        XCTAssertTrue(deep.contains("confirmationText == requiredDeepConfirmation"))
        XCTAssertTrue(deep.contains(#""/usr/bin/purge""#))
        XCTAssertFalse(deep.contains("AdminShell"))

        XCTAssertTrue(max.contains("confirmationText == requiredDeepConfirmation"))
        XCTAssertTrue(max.contains(#"AdminShell.runSync("/usr/sbin/purge""#))
    }

    private func readSource(_ relativePath: String) throws -> String {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        return try String(contentsOf: root.appendingPathComponent(relativePath), encoding: .utf8)
    }

    private func functionBody(named signature: String, in source: String) throws -> String {
        guard let signatureRange = source.range(of: signature) else {
            throw NSError(domain: "MemoryPurgeSafetyTests", code: 1, userInfo: [NSLocalizedDescriptionKey: "Missing signature: \(signature)"])
        }
        guard let brace = source[signatureRange.upperBound...].firstIndex(of: "{") else {
            throw NSError(domain: "MemoryPurgeSafetyTests", code: 2, userInfo: [NSLocalizedDescriptionKey: "Missing body start: \(signature)"])
        }
        return try extractBracedBody(from: source, openingBrace: brace)
    }

    private func snippet(from source: String, startingAt startNeedle: String, endingAt endNeedle: String) throws -> String {
        guard let start = source.range(of: startNeedle) else {
            throw NSError(domain: "MemoryPurgeSafetyTests", code: 3, userInfo: [NSLocalizedDescriptionKey: "Missing needle: \(startNeedle)"])
        }
        guard let end = source.range(of: endNeedle, range: start.upperBound..<source.endIndex) else {
            throw NSError(domain: "MemoryPurgeSafetyTests", code: 4, userInfo: [NSLocalizedDescriptionKey: "Missing end needle: \(endNeedle)"])
        }
        return String(source[start.upperBound..<end.lowerBound])
    }

    private func extractBracedBody(from source: String, openingBrace: String.Index) throws -> String {
        var depth = 0
        var index = openingBrace
        while index < source.endIndex {
            let ch = source[index]
            if ch == "{" {
                depth += 1
            } else if ch == "}" {
                depth -= 1
                if depth == 0 {
                    let start = source.index(after: openingBrace)
                    return String(source[start..<index])
                }
            }
            index = source.index(after: index)
        }
        throw NSError(domain: "MemoryPurgeSafetyTests", code: 5, userInfo: [NSLocalizedDescriptionKey: "Unterminated body"])
    }
}
