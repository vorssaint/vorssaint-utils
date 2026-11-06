// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint
// Based on Textream by Fatih Kadir Akın (MIT License)

import AppKit
import Foundation

enum PresentationNotesExtractor {

    enum ExtractionError: LocalizedError {
        case unsupportedFormat
        case extractionFailed(String)
        case noNotesFound

        var errorDescription: String? {
            switch self {
            case .unsupportedFormat:
                return "Unsupported file format. Please drop a .pptx file."
            case .extractionFailed(let detail):
                return "Failed to extract notes: \(detail)"
            case .noNotesFound:
                return "No presenter notes found in this presentation."
            }
        }
    }

    static func extractNotes(from url: URL) throws -> [String] {
        let ext = url.pathExtension.lowercased()
        switch ext {
        case "pptx":
            return try extractPPTXNotes(from: url)
        default:
            throw ExtractionError.unsupportedFormat
        }
    }

    // MARK: - PPTX Extraction

    private static func extractPPTXNotes(from url: URL) throws -> [String] {
        let fileManager = FileManager.default
        let tempDir = fileManager.temporaryDirectory.appendingPathComponent("vorssaint-pptx-" + UUID().uuidString)
        try fileManager.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: tempDir) }

        let localArchive = tempDir.appendingPathComponent("presentation.pptx")
        do {
            try fileManager.copyItem(at: url, to: localArchive)
        } catch {
            throw ExtractionError.extractionFailed("Could not read PPTX file.")
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
        process.arguments = ["-o", "-q", localArchive.path, "-d", tempDir.path]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            throw ExtractionError.extractionFailed("Could not unzip PPTX file.")
        }

        let notesDir = tempDir.appendingPathComponent("ppt/notesSlides")
        guard fileManager.fileExists(atPath: notesDir.path) else {
            throw ExtractionError.noNotesFound
        }

        let noteFiles = try fileManager.contentsOfDirectory(at: notesDir, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "xml" && $0.lastPathComponent.hasPrefix("notesSlide") }
            .sorted { file1, file2 in
                let n1 = extractNumber(from: file1.lastPathComponent) ?? 0
                let n2 = extractNumber(from: file2.lastPathComponent) ?? 0
                return n1 < n2
            }

        var pages: [String] = []
        for noteFile in noteFiles {
            let data = try Data(contentsOf: noteFile)
            let text = parsePPTXNoteXML(data: data)
            pages.append(text)
        }

        pages = pages.compactMap { page in
            let trimmed = page.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty && Int(trimmed) == nil else { return nil }
            return trimmed
        }

        guard !pages.isEmpty else {
            throw ExtractionError.noNotesFound
        }

        return pages
    }

    private static func extractNumber(from filename: String) -> Int? {
        let digits = filename.filter { $0.isNumber }
        return Int(digits)
    }

    private static func parsePPTXNoteXML(data: Data) -> String {
        let parser = PPTXNoteXMLParser(data: data)
        return parser.parse()
    }
}

// MARK: - PPTX Notes XML Parser

private class PPTXNoteXMLParser: NSObject, XMLParserDelegate {
    private let data: Data
    private var paragraphs: [String] = []
    private var currentParagraph = ""
    private var currentText = ""
    private var insideBody = false
    private var insideTextRun = false
    private var insideParagraph = false
    private var skipPlaceholder = false
    private var currentPlaceholderType: String?

    init(data: Data) {
        self.data = data
    }

    func parse() -> String {
        let parser = XMLParser(data: data)
        parser.delegate = self
        parser.parse()
        return paragraphs.joined(separator: "\n")
    }

    func parser(_ parser: XMLParser, didStartElement elementName: String,
                namespaceURI: String?, qualifiedName: String?,
                attributes: [String: String]) {
        if elementName.hasSuffix(":sp") || elementName == "sp" {
            skipPlaceholder = false
            currentPlaceholderType = nil
        }

        if elementName.hasSuffix(":ph") || elementName == "ph" {
            let type = attributes["type"] ?? ""
            currentPlaceholderType = type
            if type == "sldNum" || type == "sldImg" || type == "dt" || type == "hdr" || type == "ftr" {
                skipPlaceholder = true
            }
        }

        if elementName.hasSuffix(":txBody") || elementName == "txBody" {
            insideBody = true
        }

        if (elementName.hasSuffix(":p") || elementName == "p") && insideBody && !skipPlaceholder {
            insideParagraph = true
            currentParagraph = ""
        }

        if (elementName.hasSuffix(":t") || elementName == "t") && insideParagraph {
            insideTextRun = true
            currentText = ""
        }

        if (elementName.hasSuffix(":br") || elementName == "br") && insideParagraph {
            currentParagraph += "\n"
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        if insideTextRun {
            currentText += string
        }
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String,
                namespaceURI: String?, qualifiedName: String?) {
        if (elementName.hasSuffix(":t") || elementName == "t") && insideTextRun {
            insideTextRun = false
            currentParagraph += currentText
        }

        if (elementName.hasSuffix(":p") || elementName == "p") && insideParagraph {
            insideParagraph = false
            paragraphs.append(currentParagraph)
        }

        if elementName.hasSuffix(":txBody") || elementName == "txBody" {
            insideBody = false
        }

        if elementName.hasSuffix(":sp") || elementName == "sp" {
            skipPlaceholder = false
            currentPlaceholderType = nil
        }
    }
}
