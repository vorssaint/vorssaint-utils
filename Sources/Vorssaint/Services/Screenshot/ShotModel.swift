// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

enum ShotTool: CaseIterable {
    case none, pen, line, arrow, rectangle, circle, marker, text, blur
}

/// One point of an annotation, in the overlay's shared screen points.
struct ShotPoint: Equatable {
    var x: Double
    var y: Double
}

/// One annotation. Pen and marker keep every point; the other tools use the
/// first and last.
final class ShotShape {
    let tool: ShotTool
    var points: [ShotPoint] = []
    /// RRGGBB.
    let color: UInt32
    /// 0...1; the marker is see-through.
    let opacity: Double
    let width: Double
    var text = ""
    let fontSize: Double

    init(tool: ShotTool, color: UInt32, opacity: Double = 1, width: Double = 0, fontSize: Double = 0) {
        self.tool = tool
        self.color = color
        self.opacity = opacity
        self.width = width
        self.fontSize = fontSize
    }

    var start: ShotPoint { points[0] }
    var end: ShotPoint { points[points.count - 1] }

    /// The rectangle spanned by the first and last points (rectangle, circle, blur).
    var bounds: ShotRect {
        ShotRect.fromCorners(Int(start.x.rounded()), Int(start.y.rounded()),
                             Int(end.x.rounded()), Int(end.y.rounded()))
    }

    /// A shape too small to keep (a click without a drag). Text is kept if it has any.
    var isEmpty: Bool {
        switch tool {
        case .text:
            return text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .pen, .marker:
            return points.isEmpty
        default:
            return points.count < 2 || (abs(end.x - start.x) < 2 && abs(end.y - start.y) < 2)
        }
    }
}

/// The annotations on a capture, oldest first, with undo.
struct ShotShapes {
    private(set) var items: [ShotShape] = []
    var count: Int { items.count }

    mutating func add(_ shape: ShotShape) {
        if !shape.isEmpty { items.append(shape) }
    }

    /// Removes the newest annotation. False when there is nothing to undo.
    @discardableResult
    mutating func undo() -> Bool {
        guard !items.isEmpty else { return false }
        items.removeLast()
        return true
    }
}

enum ShotImage {
    /// Pixelates a region of a 32-bit image for the blur tool: each block of
    /// `block`×`block` pixels becomes its average colour. Returns the
    /// region's own pixels (stride = width × 4). The region must lie inside
    /// the image.
    static func pixelate(_ pixels: [UInt8], stride: Int, region: ShotRect, block: Int) -> [UInt8] {
        let block = max(1, block)
        let w = region.width, h = region.height
        guard w > 0, h > 0 else { return [] }
        var out = [UInt8](repeating: 0, count: w * h * 4)
        var by = 0
        while by < h {
            var bx = 0
            while bx < w {
                let bw = min(block, w - bx), bh = min(block, h - by)
                var s0 = 0, s1 = 0, s2 = 0, s3 = 0
                for y in 0..<bh {
                    let row = (region.y + by + y) * stride + (region.x + bx) * 4
                    for x in 0..<bw {
                        let i = row + x * 4
                        s0 += Int(pixels[i]); s1 += Int(pixels[i + 1])
                        s2 += Int(pixels[i + 2]); s3 += Int(pixels[i + 3])
                    }
                }
                let n = bw * bh
                let c0 = UInt8(s0 / n), c1 = UInt8(s1 / n), c2 = UInt8(s2 / n), c3 = UInt8(s3 / n)
                for y in 0..<bh {
                    for x in 0..<bw {
                        let o = ((by + y) * w + bx + x) * 4
                        out[o] = c0; out[o + 1] = c1; out[o + 2] = c2; out[o + 3] = c3
                    }
                }
                bx += block
            }
            by += block
        }
        return out
    }
}

/// File names and formats for saved screenshots.
enum ShotFiles {
    static let defaultPattern = "Screenshot {yyyy-MM-dd HH.mm.ss}"
    static let formats = ["png", "jpg", "bmp"]

    static func sanitizedFormat(_ format: String) -> String {
        switch format.lowercased() {
        case "jpg", "jpeg": return "jpg"
        case "bmp": return "bmp"
        default: return "png"
        }
    }

    static func fileExtension(_ format: String) -> String {
        "." + sanitizedFormat(format)
    }

    /// The format a file name asks for by its extension, or `fallback`.
    static func format(fromPath path: String, fallback: String) -> String {
        switch (path as NSString).pathExtension.lowercased() {
        case "jpg", "jpeg": return "jpg"
        case "png": return "png"
        case "bmp": return "bmp"
        default: return fallback
        }
    }

    /// Expands a pattern into a file name (without extension). Text in braces
    /// is a date format for the capture time ({yyyy-MM-dd}), except {n}, a
    /// number that makes the name unused in `exists`. Characters a file name
    /// cannot hold are replaced with "-".
    static func name(pattern: String?, time: Date, fileExtension: String,
                     timeZone: TimeZone = .current,
                     exists: (String) -> Bool) -> String {
        var pattern = pattern ?? ""
        if pattern.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { pattern = defaultPattern }
        let hasCounter = pattern.range(of: "{n}", options: .caseInsensitive) != nil
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone

        func build(_ n: Int) -> String {
            var result = ""
            var rest = Substring(pattern)
            while let open = rest.firstIndex(of: "{"),
                  let close = rest[rest.index(after: open)...].firstIndex(of: "}") {
                result += rest[..<open]
                let token = String(rest[rest.index(after: open)..<close])
                if token.lowercased() == "n" {
                    result += String(n)
                } else {
                    formatter.dateFormat = token
                    result += formatter.string(from: time)
                }
                rest = rest[rest.index(after: close)...]
            }
            result += rest
            var name = String(result.map { $0 == "/" || $0 == ":" || $0 == "\0" ? "-" : $0 })
            name = name.trimmingCharacters(in: .whitespacesAndNewlines)
            while name.hasSuffix(".") { name.removeLast() }
            while name.hasPrefix(".") { name.removeFirst() }
            return name.isEmpty ? "Screenshot" : name
        }

        if hasCounter {
            var n = 1
            while true {
                let candidate = build(n)
                if !exists(candidate + fileExtension) { return candidate }
                n += 1
            }
        }
        let plain = build(1)
        if !exists(plain + fileExtension) { return plain }
        var n = 2
        while exists("\(plain) (\(n))\(fileExtension)") { n += 1 }
        return "\(plain) (\(n))"
    }
}

/// The macOS screenshot shortcuts, as System Settings lists them under
/// Keyboard Shortcuts, Screenshots. The numbers are the system's own ids.
enum ShotSystemShortcut: Int, CaseIterable {
    case saveScreen = 28          // ⇧⌘3
    case copyScreen = 29          // ⌃⇧⌘3
    case saveArea = 30            // ⇧⌘4
    case copyArea = 31            // ⌃⇧⌘4
    case options = 184            // ⇧⌘5

    /// Which of the system's screenshot shortcuts are on, read from the
    /// system's own shortcut table. An entry the table does not list has
    /// never been changed, and those are on from the factory.
    static func enabled(in table: [String: Any]?) -> [ShotSystemShortcut] {
        allCases.filter { shortcut in
            guard let entry = table?[String(shortcut.rawValue)] as? [String: Any] else { return true }
            if let flag = entry["enabled"] as? Bool { return flag }
            if let flag = entry["enabled"] as? NSNumber { return flag.boolValue }
            return true
        }
    }
}
