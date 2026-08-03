// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation
import UniformTypeIdentifiers

enum FinderPasteImageSupport {
    private static let fileURLType = "public.file-url"
    private static let pngType = "public.png"

    /// A copied image file can also advertise image data. File URLs win so a
    /// normal Finder paste is never turned into a newly rendered PNG.
    static func preferredImageType(in typeIdentifiers: [String]) -> String? {
        guard !typeIdentifiers.contains(fileURLType) else { return nil }
        if typeIdentifiers.contains(pngType) { return pngType }
        return typeIdentifiers.first {
            UTType($0)?.conforms(to: .image) == true
        }
    }

    static func fileName(for date: Date, timeZone: TimeZone = .current) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = timeZone
        formatter.dateFormat = "'Pasted_Image_'yyyyMMdd_HHmmss'.png'"
        return formatter.string(from: date)
    }
}
