// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit

enum ClipboardPreviewLayoutTests {
    static func run(_ suite: TestSuite) {
        let screen = CGSize(width: 1440, height: 900)
        let square = ClipboardPreviewLayout.imageSize(CGSize(width: 1200, height: 1200),
                                                      available: screen, backingScale: 2)
        suite.expectClose(square.width - 24, square.height - 88,
                          "a square image gets a square image region instead of a fixed landscape canvas")
        let wide = ClipboardPreviewLayout.imageSize(CGSize(width: 2000, height: 400),
                                                    available: screen, backingScale: 2)
        suite.expect(wide.width > square.width && wide.height < square.height / 2,
                     "panoramic images produce a wider and much shallower popup")
        let small = ClipboardPreviewLayout.imageSize(CGSize(width: 80, height: 60),
                                                     available: screen, backingScale: 2)
        suite.expect(small == CGSize(width: 320, height: 118),
                     "a tiny image reserves only its natural height plus chrome and padding")
        let smallContent = ClipboardPreviewLayout.imageContentSize(CGSize(width: 80, height: 60),
            viewport: CGSize(width: small.width, height: small.height - 64), backingScale: 2)
        suite.expect(smallContent == CGSize(width: 40, height: 30),
                     "the toolbar minimum cannot enlarge a small image beyond its natural points")

        let tallPixels = CGSize(width: 1200, height: 6000)
        let tall = ClipboardPreviewLayout.imageSize(tallPixels, available: screen, backingScale: 2)
        let tallContent = ClipboardPreviewLayout.imageContentSize(tallPixels,
            viewport: CGSize(width: tall.width, height: tall.height - 64), backingScale: 2)
        suite.expect(tallContent.width == tall.width - 24 && tallContent.height > tall.height * 4,
                     "a long screenshot fills the viewport width while retaining scrollable height")
        suite.expectClose(tallContent.height / tallContent.width, 5,
                          "scrolling screenshot sizing preserves its full aspect ratio")
        for available in [CGSize(width: 1440, height: 900), CGSize(width: 640, height: 400),
                          CGSize(width: 300, height: 200)] {
            for pixels in [CGSize(width: 2000, height: 400), CGSize(width: 1200, height: 1200),
                           CGSize(width: 1200, height: 2000), tallPixels] {
                let size = ClipboardPreviewLayout.imageSize(pixels, available: available, backingScale: 2)
                let content = ClipboardPreviewLayout.imageContentSize(pixels,
                    viewport: CGSize(width: size.width, height: size.height - 64), backingScale: 2)
                suite.expect(size.width <= available.width * 0.8 && size.height <= available.height * 0.7,
                             "every image popup stays within its screen bounds")
                suite.expect(content.width <= pixels.width / 2 && content.height <= pixels.height / 2,
                             "image previews never exceed original resolution at the display scale")
                if pixels.height / pixels.width < 2 {
                    suite.expect(content.height <= max(0, size.height - 88),
                                 "ordinary image previews fit vertically without needless scrolling")
                }
                if content.width > 0 {
                    suite.expectClose(content.height / content.width, pixels.height / pixels.width,
                                      "image sizing retains its aspect ratio across screen sizes")
                }
            }
        }
        for invalid in [CGSize.zero, CGSize(width: -1, height: 100), CGSize(width: CGFloat.infinity, height: 100)] {
            let size = ClipboardPreviewLayout.imageSize(invalid, available: screen, backingScale: 2)
            suite.expect(size.width.isFinite && size.height.isFinite && size.width > 0 && size.height > 0,
                         "unavailable image dimensions give a bounded loading or failure surface")
        }

        let short = ClipboardPreviewLayout.textSize("Editable note", available: screen)
        let paragraphs = ClipboardPreviewLayout.textSize(String(repeating: "A paragraph to edit.\n", count: 12),
                                                         available: screen)
        let document = ClipboardPreviewLayout.textSize(String(repeating: "Text ", count: 200_000), available: screen)
        suite.expect(short.width >= 360 && short.height >= 198,
                     "short text keeps enough blank space to edit comfortably")
        suite.expect(paragraphs.height > short.height && paragraphs.height <= 420,
                     "text popup height grows with its visible content")
        suite.expect(document.width <= 480 && document.height == 420,
                     "a very large copied document uses a bounded scrolling popup")
        let constrained = ClipboardPreviewLayout.textSize(String(repeating: "Line\n", count: 100),
                                                          available: CGSize(width: 400, height: 300))
        suite.expect(constrained.width <= 320 && constrained.height <= 210,
                     "text's editing minimum yields to a small screen")
    }
}
