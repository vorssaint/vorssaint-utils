// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation
import CoreGraphics

enum DockScriptSupport {
    static let maximumArgumentBytes = 16_384
    static func identifier(_ value: Any?) -> UInt32? {
        guard let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID() else { return nil }
        let raw = number.doubleValue
        guard raw.isFinite, raw > 0, raw <= Double(UInt32.max), raw.rounded(.towardZero) == raw else { return nil }
        return UInt32(raw)
    }
    static func arguments(_ string: String) throws -> [String: Any] {
        guard string.utf8.count <= maximumArgumentBytes,
              let data = string.data(using: .utf8), let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw NSError(domain: "Vorssaint.WindowAPI", code: -1700, userInfo: [NSLocalizedDescriptionKey: "Expected a JSON object of at most 16 KiB."])
        }
        return object
    }
    static func frame(_ arguments: [String: Any]) -> CGRect? {
        let numbers = ["x", "y", "width", "height"].compactMap { arguments[$0] as? NSNumber }
        guard numbers.count == 4, numbers.allSatisfy({ CFGetTypeID($0) != CFBooleanGetTypeID() }) else { return nil }
        let values = numbers.map(\.doubleValue)
        guard values.count == 4, values.allSatisfy({ $0.isFinite && abs($0) <= 100_000 }),
              values[2] >= 16, values[3] >= 16, values[2] <= 16_384, values[3] <= 16_384 else { return nil }
        return CGRect(x: values[0], y: values[1], width: values[2], height: values[3])
    }
}
