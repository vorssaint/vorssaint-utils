// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit

/// The preview wraps ordinary images; only long captures need a scrolling viewport.
enum ClipboardPreviewLayout {
    static let imagePadding: CGFloat = 24
    static let imageChromeHeight: CGFloat = 64
    static let textChromeHeight: CGFloat = 78

    static func imageSize(_ imageSize: CGSize, available: CGSize, backingScale: CGFloat) -> CGSize {
        let maximum = bounds(available, width: 520, height: 520)
        guard imageSize.width.isFinite, imageSize.height.isFinite,
              imageSize.width > 0, imageSize.height > 0 else {
            return CGSize(width: min(480, maximum.width), height: min(360, maximum.height))
        }
        let content = imageContentSize(imageSize,
            viewport: CGSize(width: maximum.width, height: max(1, maximum.height - imageChromeHeight)),
            backingScale: backingScale)
        let width = min(maximum.width, max(320, ceil(content.width + imagePadding)))
        let height = content.height + imagePadding + imageChromeHeight
        return CGSize(width: width, height: min(maximum.height, ceil(height)))
    }

    /// `viewport` is the image region, including its padding but excluding toolbar/footer.
    static func imageContentSize(_ imageSize: CGSize, viewport: CGSize, backingScale: CGFloat) -> CGSize {
        guard imageSize.width.isFinite, imageSize.height.isFinite,
              imageSize.width > 0, imageSize.height > 0 else { return .zero }
        let scale = backingScale.isFinite && backingScale > 0 ? backingScale : 1
        let aspect = imageSize.height / imageSize.width
        var width = min(imageSize.width / scale, max(0, viewport.width - imagePadding))
        if aspect < 2 {
            width = min(width, max(0, viewport.height - imagePadding) / aspect)
        }
        return CGSize(width: width, height: width * aspect)
    }

    static func textSize(_ text: String, available: CGSize) -> CGSize {
        let maximum = bounds(available, width: 480, height: 420)
        // Measuring a complete copied document would block the popup. A longer
        // entry will scroll anyway, so only its first few kilobytes need layout.
        let prefix = text.prefix(4_096)
        let sample = String(prefix) as NSString
        let attributes: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 12)]
        let naturalWidth = sample.size(withAttributes: attributes).width
        let width = min(maximum.width, max(360, ceil(naturalWidth + 24)))
        let textBounds = sample.boundingRect(with: CGSize(width: max(1, width - 24), height: .greatestFiniteMagnitude),
                                             options: [.usesLineFragmentOrigin, .usesFontLeading],
                                             attributes: attributes)
        let height = prefix.endIndex == text.endIndex
            ? max(120, ceil(textBounds.height) + 24) + textChromeHeight
            : maximum.height
        return CGSize(width: width, height: min(maximum.height, height))
    }

    private static func bounds(_ available: CGSize, width: CGFloat, height: CGFloat) -> CGSize {
        let screenWidth = available.width.isFinite && available.width > 0 ? available.width : width
        let screenHeight = available.height.isFinite && available.height > 0 ? available.height : height
        return CGSize(width: max(1, min(width, floor(screenWidth * 0.8))),
                      height: max(1, min(height, floor(screenHeight * 0.7))))
    }
}
