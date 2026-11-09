// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import Combine
import Foundation

@MainActor
public protocol NotchPlugin {
    var identifier: String { get }
    var title: String { get }
    var symbol: String { get }
    func perform()
}

@MainActor
public final class NotchPluginRegistry: ObservableObject {
    public static let shared = NotchPluginRegistry()
    public static let maximumIdentifierBytes = 128
    public static let maximumTitleBytes = 96
    public static let maximumSymbolBytes = 64

    @Published public private(set) var plugins: [any NotchPlugin] = []

    public init() {}

    @discardableResult
    public func register(_ plugin: any NotchPlugin) -> Bool {
        guard Self.isValidIdentifier(plugin.identifier),
              Self.isValidTitle(plugin.title),
              Self.isValidSymbol(plugin.symbol),
              !plugins.contains(where: { $0.identifier == plugin.identifier }) else { return false }
        plugins.append(plugin)
        return true
    }

    private static func isValidIdentifier(_ value: String) -> Bool {
        !value.isEmpty && value.utf8.count <= maximumIdentifierBytes
            && value.unicodeScalars.allSatisfy {
                CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789.-_")
                    .contains($0)
            }
    }

    private static func isValidTitle(_ value: String) -> Bool {
        !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && value.utf8.count <= maximumTitleBytes
            && !value.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains)
    }

    private static func isValidSymbol(_ value: String) -> Bool {
        !value.isEmpty && value.utf8.count <= maximumSymbolBytes
            && value.unicodeScalars.allSatisfy {
                CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789.-")
                    .contains($0)
            }
            && NSImage(systemSymbolName: value, accessibilityDescription: nil) != nil
    }
}
