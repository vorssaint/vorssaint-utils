// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit

/// The macOS Services handler behind "Read with Fast Reader". `Info.plist`
/// declares the service unconditionally, so `NSApp.servicesProvider` is set
/// to an instance of this at launch whether or not the feature is
/// installed. It is deliberately a separate object from `FastReaderService`
/// itself: assigning `servicesProvider` must never be what brings the
/// feature's singleton to life. The availability gate lives inside
/// `FastReaderService.open(text:)`, which this only forwards to.
final class FastReaderServiceProvider: NSObject {
    @objc func readWithFastReader(_ pasteboard: NSPasteboard,
                                  userData: String?,
                                  error: AutoreleasingUnsafeMutablePointer<NSString>) {
        guard let text = pasteboard.string(forType: .string), !text.isEmpty else {
            error.pointee = FeatureStrings.fastReader(L10n.shared.language).noSelection as NSString
            return
        }
        FastReaderService.shared.open(text: text)
    }
}
