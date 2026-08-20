// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// Pure parsing and formatting helpers for the Quarantine Manager. No file
/// access, no shelling out - everything here is testable on plain strings.
enum QuarantineManagerSupport {
    static let maxScanEntries = 500

    struct ParsedQuarantine: Equatable {
        let source: String
        let date: String
        let flags: [String]
        let rawFlags: String
        let epoch: Int?
    }

    struct XattrInfo: Identifiable, Equatable {
        let id = UUID()
        let name: String
        let value: String
        let isQuarantine: Bool
        /// True when `value` is a hex dump or a `plutil`-pretty-printed plist
        /// rather than the attribute's literal text - the detail view labels
        /// these so a hex string never reads as a display bug.
        let isBinaryDisplay: Bool

        static func == (lhs: XattrInfo, rhs: XattrInfo) -> Bool {
            lhs.name == rhs.name && lhs.value == rhs.value
        }
    }

    /// True if a decoded attribute value contains non-printable control bytes
    /// or the Unicode replacement char - i.e. it is raw binary that should be
    /// shown as hex rather than printed directly (which would render as a
    /// string of replacement glyphs).
    static func looksBinary(_ value: String) -> Bool {
        for scalar in value.unicodeScalars {
            if scalar == "\t" || scalar == "\n" || scalar == "\r" { continue }
            if scalar.value < 0x20 || scalar.value == 0xfffd { return true }
        }
        return false
    }

    /// Decodes an `xattr -px` hex dump (whitespace-separated byte pairs) back
    /// into raw bytes, for handing a binary plist attribute to `plutil`.
    static func data(fromHex hex: String) -> Data? {
        let cleaned = hex.filter { !$0.isWhitespace }
        guard cleaned.count % 2 == 0 else { return nil }
        var bytes = [UInt8]()
        bytes.reserveCapacity(cleaned.count / 2)
        var index = cleaned.startIndex
        while index < cleaned.endIndex {
            let next = cleaned.index(index, offsetBy: 2)
            guard let byte = UInt8(cleaned[index..<next], radix: 16) else { return nil }
            bytes.append(byte)
            index = next
        }
        return Data(bytes)
    }

    static func isApp(_ path: String) -> Bool {
        path.hasSuffix(".app") || path.contains(".app/")
    }

    /// Attributes the kernel refuses to remove regardless of privilege.
    /// `com.apple.provenance` (Gatekeeper's record of a quarantine-clearance
    /// event, introduced in Ventura) is SIP-protected and kernel-managed -
    /// even `sudo xattr -d` silently no-ops on it, with no error. The app
    /// must not let the user attempt this (or prompt for an admin password
    /// for something guaranteed to fail); the UI should mark it as
    /// non-removable up front instead.
    static let nonRemovableAttributes: Set<String> = ["com.apple.provenance"]

    static func isRemovable(_ attributeName: String) -> Bool {
        !nonRemovableAttributes.contains(attributeName)
    }

    static func formatFileSize(_ bytes: Int64) -> String {
        let kb = 1024.0
        let mb = kb * 1024
        let gb = mb * 1024
        let value = Double(bytes)
        switch value {
        case ..<kb: return "\(bytes) B"
        case ..<mb: return String(format: "%.1f KB", value / kb)
        case ..<gb: return String(format: "%.1f MB", value / mb)
        default: return String(format: "%.1f GB", value / gb)
        }
    }

    /// Expands `\xNN` escapes some downloaders write into the quarantine
    /// record (Free Download Manager stores its name as
    /// `Free\x20Download\x20Manager`). Only printable results are
    /// substituted, so a decoded control byte never ends up in a title.
    static func decodeXattrEscapes(_ value: String) -> String {
        guard value.contains("\\x") else { return value }
        guard let regex = try? NSRegularExpression(pattern: "\\\\x([0-9a-fA-F]{2})") else { return value }
        let full = NSRange(value.startIndex..., in: value)
        var result = ""
        var lastEnd = value.startIndex
        for match in regex.matches(in: value, range: full) {
            guard let matchRange = Range(match.range, in: value),
                  let hexRange = Range(match.range(at: 1), in: value),
                  let code = UInt32(value[hexRange], radix: 16) else { continue }
            result += value[lastEnd..<matchRange.lowerBound]
            if code >= 0x20, code != 0x7f, let scalar = Unicode.Scalar(code) {
                result.append(Character(scalar))
            } else {
                result += value[matchRange]
            }
            lastEnd = matchRange.upperBound
        }
        result += value[lastEnd...]
        return result
    }

    /// Format: FLAGHEX;TIMESTAMP_HEX;APPNAME;UUID. Timestamp is hex seconds
    /// since the Unix epoch, not Mac absolute time (2001-01-01) - the
    /// original Raycast extension verified this against real records.
    static func parseQuarantineValue(_ rawValue: String) -> ParsedQuarantine? {
        let parts = rawValue.split(separator: ";", omittingEmptySubsequences: false).map(String.init)
        guard parts.count >= 2 else { return nil }

        let flagHex = parts[0]
        let timestamp = parts[1]
        let appName = parts.count > 2 ? decodeXattrEscapes(parts[2]) : ""

        var flags: [String] = []
        if let flagInt = UInt32(flagHex, radix: 16) {
            if flagInt & 0x0001 != 0 { flags.append("Downloaded from Internet") }
            if flagInt & 0x0002 != 0 { flags.append("Sandbox") }
            if flagInt & 0x0040 != 0 { flags.append("User-approved") }
            if flagInt & 0x0080 != 0 { flags.append("Gatekeeper passed") }
        }
        if flags.isEmpty { flags.append("Quarantined") }

        var dateStr = "Unknown"
        var epoch: Int?
        if timestamp.count == 8, let ts = Int(timestamp, radix: 16) {
            epoch = ts
            let date = Date(timeIntervalSince1970: TimeInterval(ts))
            let formatter = DateFormatter()
            formatter.dateStyle = .medium
            formatter.timeStyle = .short
            dateStr = formatter.string(from: date)
        }

        return ParsedQuarantine(source: appName.isEmpty ? "Unknown" : appName,
                                date: dateStr,
                                flags: flags,
                                rawFlags: flagHex,
                                epoch: epoch)
    }

    /// Splits one `xattr -p com.apple.quarantine -r <root>` output line
    /// (`<path>: <value>`) into its path and value. A path can itself
    /// contain ": " (a file may legitimately be named "a: b"), so the split
    /// anchors on the quarantine value's shape - `<flags>;<timestamp>;` -
    /// with a greedy path match, landing on the last viable separator. Lines
    /// that don't match this shape (e.g. `xattr`'s own "No such xattr" error
    /// text for a file that was never quarantined - which on some systems is
    /// itself prefixed with the literal program name) are rejected outright
    /// rather than guessed at, so an error line can never be mistaken for a
    /// real entry.
    static func parseQuarantineLine(_ line: String) -> (path: String, value: String)? {
        guard let regex = try? NSRegularExpression(pattern: "^(.*): ([0-9a-fA-F]*;[0-9a-fA-F]*;.*)$"),
              let match = regex.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)),
              let pathRange = Range(match.range(at: 1), in: line),
              let valueRange = Range(match.range(at: 2), in: line) else {
            return nil
        }
        return (String(line[pathRange]), String(line[valueRange]))
    }
}
