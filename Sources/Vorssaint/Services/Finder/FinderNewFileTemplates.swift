// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// Independently authored empty documents. Office formats contain a complete
/// minimal Open XML package; changing an empty file's extension is not enough.
enum FinderNewFileTemplates {
    static let extensions = ["txt", "rtf", "json", "md", "docx", "xlsx", "pptx", "html", "xml", "css", "js", "py", "sh"]

    static func contents(for name: String) -> Data {
        let ext = (name as NSString).pathExtension.lowercased()
        switch ext {
        case "rtf": return Data(#"{\rtf1\ansi\deff0 {\fonttbl {\f0 Helvetica;}}\f0\fs24\par}"#.utf8)
        case "json": return Data("{}\n".utf8)
        case "html": return Data("<!doctype html>\n<html lang=\"en\"><head><meta charset=\"utf-8\"><title></title></head><body></body></html>\n".utf8)
        case "xml": return Data("<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n<document/>\n".utf8)
        case "sh": return Data("#!/bin/sh\n".utf8)
        case "docx", "xlsx", "pptx": return officeDocument(ext)
        default: return Data()
        }
    }

    private static let relationshipNamespace = "http://schemas.openxmlformats.org/package/2006/relationships"
    private static let officeNamespace = "http://schemas.openxmlformats.org/officeDocument/2006/relationships"

    private static func officeDocument(_ ext: String) -> Data {
        let root: String
        let contentType: String
        var entries: [(String, String)]
        switch ext {
        case "docx":
            root = "word/document.xml"
            contentType = "wordprocessingml.document.main+xml"
            entries = [(root, #"<w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main"><w:body><w:p/><w:sectPr/></w:body></w:document>"#)]
        case "xlsx":
            root = "xl/workbook.xml"
            contentType = "spreadsheetml.sheet.main+xml"
            entries = [(root, "<workbook xmlns=\"http://schemas.openxmlformats.org/spreadsheetml/2006/main\" xmlns:r=\"\(officeNamespace)\"><sheets><sheet name=\"Sheet 1\" sheetId=\"1\" r:id=\"rId1\"/></sheets></workbook>"),
                       ("xl/_rels/workbook.xml.rels", relationships(type: "worksheet", target: "worksheets/sheet1.xml")),
                       ("xl/worksheets/sheet1.xml", #"<worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main"><sheetData/></worksheet>"#)]
        default:
            root = "ppt/presentation.xml"
            contentType = "presentationml.presentation.main+xml"
            entries = [(root, #"<p:presentation xmlns:p="http://schemas.openxmlformats.org/presentationml/2006/main"><p:sldSz cx="9144000" cy="6858000"/><p:notesSz cx="6858000" cy="9144000"/></p:presentation>"#)]
        }
        let sheetType = ext == "xlsx" ? "<Override PartName=\"/xl/worksheets/sheet1.xml\" ContentType=\"application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml\"/>" : ""
        entries.append(("[Content_Types].xml", "<Types xmlns=\"http://schemas.openxmlformats.org/package/2006/content-types\"><Default Extension=\"rels\" ContentType=\"application/vnd.openxmlformats-package.relationships+xml\"/><Default Extension=\"xml\" ContentType=\"application/xml\"/><Override PartName=\"/\(root)\" ContentType=\"application/vnd.openxmlformats-officedocument.\(contentType)\"/>\(sheetType)</Types>"))
        entries.append(("_rels/.rels", relationships(type: "officeDocument", target: root)))
        return storedZIP(entries.map { ($0.0, Data(("<?xml version=\"1.0\" encoding=\"UTF-8\"?>" + $0.1).utf8)) })
    }

    private static func relationships(type: String, target: String) -> String {
        "<Relationships xmlns=\"\(relationshipNamespace)\"><Relationship Id=\"rId1\" Type=\"\(officeNamespace)/\(type)\" Target=\"\(target)\"/></Relationships>"
    }

    /// Only used for the small static templates above. No external paths, ZIP64,
    /// compression, or user-controlled archive entries are accepted here.
    private static func storedZIP(_ entries: [(String, Data)]) -> Data {
        var archive = Data()
        var directory = Data()
        func append(_ value: UInt32, bytes: Int, to data: inout Data) {
            for shift in 0..<bytes { data.append(UInt8(truncatingIfNeeded: value >> (shift * 8))) }
        }
        for (path, contents) in entries {
            let name = Data(path.utf8)
            let offset = UInt32(archive.count)
            var crc: UInt32 = 0xffffffff
            for byte in contents {
                crc ^= UInt32(byte)
                for _ in 0..<8 { crc = crc & 1 == 1 ? (crc >> 1) ^ 0xedb88320 : crc >> 1 }
            }
            crc ^= 0xffffffff
            append(0x04034b50, bytes: 4, to: &archive)
            for value: UInt32 in [20, 0, 0, 0, 33] { append(value, bytes: 2, to: &archive) }
            for value in [crc, UInt32(contents.count), UInt32(contents.count)] { append(value, bytes: 4, to: &archive) }
            append(UInt32(name.count), bytes: 2, to: &archive)
            append(0, bytes: 2, to: &archive)
            archive.append(name)
            archive.append(contents)
            append(0x02014b50, bytes: 4, to: &directory)
            for value: UInt32 in [20, 20, 0, 0, 0, 33] { append(value, bytes: 2, to: &directory) }
            for value in [crc, UInt32(contents.count), UInt32(contents.count)] { append(value, bytes: 4, to: &directory) }
            for value: UInt32 in [UInt32(name.count), 0, 0, 0, 0] { append(value, bytes: 2, to: &directory) }
            append(0, bytes: 4, to: &directory)
            append(offset, bytes: 4, to: &directory)
            directory.append(name)
        }
        let directoryOffset = UInt32(archive.count)
        archive.append(directory)
        append(0x06054b50, bytes: 4, to: &archive)
        for value: UInt32 in [0, 0, UInt32(entries.count), UInt32(entries.count)] { append(value, bytes: 2, to: &archive) }
        append(UInt32(directory.count), bytes: 4, to: &archive)
        append(directoryOffset, bytes: 4, to: &archive)
        append(0, bytes: 2, to: &archive)
        return archive
    }
}
