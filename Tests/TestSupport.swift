// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Carbon.HIToolbox
import Foundation

/// The placeholders a format string carries, sorted, so two languages can
/// be compared without caring about the order they read in.
func placeholderShape(_ value: String) -> [String] {
    formatSpecifiers(in: value).sorted()
}

func formatSpecifiers(in format: String) -> [String] {
    var specifiers: [String] = []
    var index = format.startIndex
    while index < format.endIndex {
        guard format[index] == "%" else {
            index = format.index(after: index)
            continue
        }
        index = format.index(after: index)
        if index < format.endIndex, format[index] == "%" {
            index = format.index(after: index)
            continue
        }
        while index < format.endIndex {
            let character = format[index]
            if character.isLetter || character == "@" {
                specifiers.append(String(character))
                index = format.index(after: index)
                break
            }
            index = format.index(after: index)
        }
    }
    return specifiers
}

func testLayoutData(for idString: String) -> Data? {
    let layoutDict = [kTISPropertyInputSourceType: kTISTypeKeyboardLayout] as CFDictionary
    let allLayoutSources = (TISCreateInputSourceList(layoutDict, true)?.takeRetainedValue() as? [TISInputSource]) ?? []
    guard let src = allLayoutSources.first(where: {
        guard let id = TISGetInputSourceProperty($0, kTISPropertyInputSourceID) else { return false }
        let str = Unmanaged<CFString>.fromOpaque(id).takeUnretainedValue() as String
        return str == idString
    }), let ptr = TISGetInputSourceProperty(src, kTISPropertyUnicodeKeyLayoutData) else {
        return nil
    }
    return Unmanaged<CFData>.fromOpaque(ptr).takeUnretainedValue() as Data
}

func sourceBody(of source: String, from opening: String, to closing: String) -> String {
    guard let start = source.range(of: opening),
          let end = source.range(of: closing, range: start.upperBound..<source.endIndex)
    else { return "" }
    return String(source[start.upperBound..<end.lowerBound])
}

func pageVisible(_ page: SettingsPage, available: Set<AppFeature>) -> Bool {
    FeatureVisibilitySupport.isPageVisible(page) { available.contains($0) }
}

func isCodeLine(_ line: String) -> Bool {
    !line.trimmingCharacters(in: .whitespaces).hasPrefix("//")
}

func activeSet(_ permission: AppPermission,
               available: Set<AppFeature> = Set(AppFeature.allCases),
               on: Set<String> = [],
               strings: [String: String] = [:]) -> Set<AppFeature> {
    Set(AppFeature.activeFeatures(using: permission,
                                  isAvailable: { available.contains($0) },
                                  boolFor: { on.contains($0) },
                                  stringFor: { strings[$0] }))
}
