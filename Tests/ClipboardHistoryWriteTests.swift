// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit

struct ClipboardHistoryWriteTests {
    static func run(_ suite: TestSuite) {
        let png = Data([1, 2, 3])
        let tiff = Data([4, 5, 6])
        let rich = NSAttributedString(string: "saved rich text")
        let writes: [(String, ClipboardHistoryWrite, String)] = [
            ("text", .text("saved text"), "string"),
            ("files", .files([NSURL(fileURLWithPath: "/tmp/saved-file")]), "objects"),
            ("rich", .rich(rich, plain: "fallback"), "objects"),
            ("PNG", .image(png: png, tiff: tiff), "png"),
        ]
        for (name, write, requiredOperation) in writes {
            let pasteboard = FakeHistoryPasteboard()
            pasteboard.rejectedOperations = [requiredOperation]
            let result = write.write(to: pasteboard, isExpired: { false })
            suite.expect(result?.succeeded == false, "failed \(name) write reports failure")
            suite.expect(result?.changeCount == 11, "failed \(name) preserves the acquired change count")
            suite.expect(pasteboard.operations == ["clear", requiredOperation, "count"],
                   "failed \(name) skips optional representations")
        }

        for (name, write, optionalOperation) in [
            ("PNG", ClipboardHistoryWrite.image(png: png, tiff: tiff), "tiff"),
            ("rich", ClipboardHistoryWrite.rich(rich, plain: "fallback"), "string"),
        ] {
            let pasteboard = FakeHistoryPasteboard()
            pasteboard.rejectedOperations = [optionalOperation]
            let result = write.write(to: pasteboard, isExpired: { false })
            suite.expect(result?.succeeded == true,
                   "successful \(name) remains successful if optional representation fails")
            suite.expect(pasteboard.operations.contains(optionalOperation),
                   "successful \(name) attempts optional representation")
            suite.expect(result?.changeCount == 11, "\(name) retains its acquired count after optional writes")
        }

        for (name, write, _) in writes {
            let pasteboard = FakeHistoryPasteboard()
            let result = write.write(to: pasteboard, isExpired: { false })
            suite.expect(result?.succeeded == true, "successful \(name) reports success")
        }

        // Expire before clear, after each mutation, and during the final
        // ownership check. Timed-out mutations still need history bookkeeping.
        for (name, write, requiredOperation) in writes {
            var mutations = ["clear", requiredOperation]
            if name == "PNG" { mutations.append("tiff") }
            if name == "rich" { mutations.append("string") }
            for allowedCalls in 0...(mutations.count + 1) {
                let pasteboard = FakeHistoryPasteboard()
                let result = write.write(to: pasteboard) {
                    pasteboard.operations.count >= allowedCalls
                }
                if allowedCalls == 0 {
                    suite.expect(result == nil && pasteboard.operations.isEmpty,
                           "expired \(name) leaves clipboard untouched before clear")
                } else {
                    let expectedMutations = Array(mutations.prefix(allowedCalls))
                    suite.expect(result?.succeeded == false,
                           "expired \(name) reports failure at boundary \(allowedCalls)")
                    suite.expect(result?.changeCount == 11,
                           "expired \(name) retains its acquired count at boundary \(allowedCalls)")
                    suite.expect(pasteboard.operations == expectedMutations + ["count"],
                           "expired \(name) only reads count after boundary \(allowedCalls)")
                }
            }
        }

        let replaced = FakeHistoryPasteboard()
        replaced.replacedBeforeCountRead = true
        let interrupted = ClipboardHistoryWrite.text("our clip").write(to: replaced, isExpired: { false })
        suite.expect(interrupted?.succeeded == false && interrupted?.changeCount == 11,
                     "a replacement after writing cannot be mistaken for the history write")

        let textPasteboard = FakeHistoryPasteboard()
        _ = ClipboardHistoryWrite.text("exact saved text").write(to: textPasteboard, isExpired: { false })
        suite.expect(textPasteboard.strings == ["exact saved text"], "text write preserves saved text")
        let imagePasteboard = FakeHistoryPasteboard()
        _ = ClipboardHistoryWrite.image(png: png, tiff: tiff).write(to: imagePasteboard, isExpired: { false })
        suite.expect(imagePasteboard.data == [png, tiff], "image write preserves PNG and TIFF payloads")
    }
}

private final class FakeHistoryPasteboard: ClipboardHistoryPasteboard {
    var operations: [String] = []
    var rejectedOperations: Set<String> = []
    var strings: [String] = []
    var data: [Data] = []
    var replacedBeforeCountRead = false
    private var count = 10

    var changeCount: Int {
        operations.append("count")
        if replacedBeforeCountRead { count += 1 }
        return count
    }

    func clearContents() -> Int {
        _ = mutate("clear")
        count += 1
        return count
    }

    func setString(_ string: String, forType type: NSPasteboard.PasteboardType) -> Bool {
        strings.append(string)
        return mutate("string")
    }

    func setData(_ value: Data?, forType type: NSPasteboard.PasteboardType) -> Bool {
        if let value { data.append(value) }
        return mutate(type == .png ? "png" : "tiff")
    }

    func writeObjects(_ objects: [NSPasteboardWriting]) -> Bool {
        mutate("objects")
    }

    private func mutate(_ operation: String) -> Bool {
        operations.append(operation)
        return !rejectedOperations.contains(operation)
    }
}
