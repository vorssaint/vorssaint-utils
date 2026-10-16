// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

enum FinderNewFileTemplatesTests {
    static func run(_ suite: TestSuite) {
        suite.run("Finder new file templates") {
            let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            do {
                try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
                defer { try? FileManager.default.removeItem(at: root) }
                for ext in ["docx", "xlsx", "pptx"] {
                    let file = try FinderFileActions.createFile(in: root, named: "Blank." + ext,
                        contents: FinderNewFileTemplates.contents(for: "Blank." + ext))
                    let verification = BoundedProcessRunner.run("/usr/bin/unzip",
                        ["-t", file.path], timeout: 10, maxOutputBytes: 64_000)
                    suite.expect(verification.status == 0, "\(ext) package passes independent ZIP CRC and directory validation")
                }
                let doc = root.appendingPathComponent("Blank.docx")
                let conversion = BoundedProcessRunner.run("/usr/bin/textutil",
                    ["-convert", "txt", "-stdout", doc.path], timeout: 10, maxOutputBytes: 64_000)
                suite.expect(conversion.status == 0, "macOS can read the generated Word document")
                let json = FinderNewFileTemplates.contents(for: "Blank.JSON")
                suite.expect((try JSONSerialization.jsonObject(with: json)) as? [String: String] == [:],
                             "JSON template is a valid empty object regardless of extension case")
                suite.expect(FinderNewFileTemplates.contents(for: "script.py").isEmpty,
                             "plain code templates do not inject executable behavior")
            } catch { suite.expect(false, "template fixture failed: \(error)") }
        }
    }
}
