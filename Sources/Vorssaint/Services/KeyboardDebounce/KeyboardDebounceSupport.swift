// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

struct KeyboardDebounceConfig: Equatable {
    var enabled: Bool
    var globalWindowMs: Int
    var keyWindows: [Int64: Int]

    func windowMs(for keyCode: Int64) -> Int {
        keyWindows[keyCode] ?? globalWindowMs
    }

    static func decodeKeyWindows(_ raw: String) -> [Int64: Int] {
        var result: [Int64: Int] = [:]
        for part in raw.split(separator: ",") {
            let pieces = part.split(separator: ":", maxSplits: 1).map(String.init)
            guard pieces.count == 2,
                  let keyCode = Int64(pieces[0]),
                  let window = Int(pieces[1]) else { continue }
            result[keyCode] = Defaults.sanitizedKeyboardDebounceWindow(window)
        }
        return result
    }

    static func encodeKeyWindows(_ windows: [Int64: Int]) -> String {
        windows
            .map { (key: $0.key, value: Defaults.sanitizedKeyboardDebounceWindow($0.value)) }
            .sorted { $0.key < $1.key }
            .map { "\($0.key):\($0.value)" }
            .joined(separator: ",")
    }
}

struct KeyboardDebounceState {
    private var lastAcceptedByKey: [Int64: TimeInterval] = [:]

    mutating func reset() {
        lastAcceptedByKey.removeAll()
    }

    mutating func shouldSuppress(keyCode: Int64,
                                 isAutoRepeat: Bool,
                                 time: TimeInterval,
                                 config: KeyboardDebounceConfig) -> Bool {
        guard config.enabled, !isAutoRepeat else { return false }
        let window = Double(config.windowMs(for: keyCode)) / 1000.0
        guard window > 0 else {
            lastAcceptedByKey[keyCode] = time
            return false
        }

        if let last = lastAcceptedByKey[keyCode],
           time >= last,
           time - last < window {
            return true
        }

        lastAcceptedByKey[keyCode] = time
        return false
    }
}

struct KeyboardDebounceKey: Identifiable, Hashable {
    let code: Int64
    let label: String

    var id: Int64 { code }
}

enum KeyboardDebounceKeyCatalog {
    static let common: [KeyboardDebounceKey] = [
        KeyboardDebounceKey(code: 0, label: "A"),
        KeyboardDebounceKey(code: 11, label: "B"),
        KeyboardDebounceKey(code: 8, label: "C"),
        KeyboardDebounceKey(code: 2, label: "D"),
        KeyboardDebounceKey(code: 14, label: "E"),
        KeyboardDebounceKey(code: 3, label: "F"),
        KeyboardDebounceKey(code: 5, label: "G"),
        KeyboardDebounceKey(code: 4, label: "H"),
        KeyboardDebounceKey(code: 34, label: "I"),
        KeyboardDebounceKey(code: 38, label: "J"),
        KeyboardDebounceKey(code: 40, label: "K"),
        KeyboardDebounceKey(code: 37, label: "L"),
        KeyboardDebounceKey(code: 46, label: "M"),
        KeyboardDebounceKey(code: 45, label: "N"),
        KeyboardDebounceKey(code: 31, label: "O"),
        KeyboardDebounceKey(code: 35, label: "P"),
        KeyboardDebounceKey(code: 12, label: "Q"),
        KeyboardDebounceKey(code: 15, label: "R"),
        KeyboardDebounceKey(code: 1, label: "S"),
        KeyboardDebounceKey(code: 17, label: "T"),
        KeyboardDebounceKey(code: 32, label: "U"),
        KeyboardDebounceKey(code: 9, label: "V"),
        KeyboardDebounceKey(code: 13, label: "W"),
        KeyboardDebounceKey(code: 7, label: "X"),
        KeyboardDebounceKey(code: 16, label: "Y"),
        KeyboardDebounceKey(code: 6, label: "Z"),
        KeyboardDebounceKey(code: 29, label: "0"),
        KeyboardDebounceKey(code: 18, label: "1"),
        KeyboardDebounceKey(code: 19, label: "2"),
        KeyboardDebounceKey(code: 20, label: "3"),
        KeyboardDebounceKey(code: 21, label: "4"),
        KeyboardDebounceKey(code: 23, label: "5"),
        KeyboardDebounceKey(code: 22, label: "6"),
        KeyboardDebounceKey(code: 26, label: "7"),
        KeyboardDebounceKey(code: 28, label: "8"),
        KeyboardDebounceKey(code: 25, label: "9"),
        KeyboardDebounceKey(code: 49, label: "Space"),
        KeyboardDebounceKey(code: 36, label: "Return"),
        KeyboardDebounceKey(code: 48, label: "Tab"),
        KeyboardDebounceKey(code: 51, label: "Delete"),
        KeyboardDebounceKey(code: 53, label: "Escape"),
        KeyboardDebounceKey(code: 43, label: ","),
        KeyboardDebounceKey(code: 47, label: "."),
        KeyboardDebounceKey(code: 44, label: "/"),
        KeyboardDebounceKey(code: 41, label: ";"),
        KeyboardDebounceKey(code: 39, label: "'"),
        KeyboardDebounceKey(code: 27, label: "-"),
        KeyboardDebounceKey(code: 24, label: "="),
        KeyboardDebounceKey(code: 33, label: "["),
        KeyboardDebounceKey(code: 30, label: "]"),
        KeyboardDebounceKey(code: 42, label: "\\"),
        KeyboardDebounceKey(code: 50, label: "`"),
    ]

    private static let labelsByCode = Dictionary(uniqueKeysWithValues: common.map { ($0.code, $0.label) })

    static func label(for keyCode: Int64) -> String {
        labelsByCode[keyCode] ?? "#\(keyCode)"
    }
}
