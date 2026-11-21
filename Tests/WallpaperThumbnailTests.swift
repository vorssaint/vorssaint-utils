// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import SwiftUI

enum WallpaperThumbnailTests {
    private struct Gallery: View {
        let images: [NSImage?]
        let report: (Int, CGRect) -> Void

        var body: some View {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3), spacing: 8) {
                ForEach(images.indices, id: \.self) { index in
                    WallpaperThumbnailView(image: images[index])
                        .background(GeometryReader { proxy in
                            Color.clear.onAppear {
                                report(index, proxy.frame(in: .named("gallery")))
                            }
                        })
                }
            }
            .coordinateSpace(name: "gallery")
        }
    }

    static func run(_ suite: TestSuite) {
        // Match the cache's 160-pixel maximum dimension. Include a placeholder
        // to prove that loading an image cannot change the column's bounds.
        let images: [NSImage?] = [
            NSImage(size: NSSize(width: 160, height: 90)),
            NSImage(size: NSSize(width: 160, height: 67)),
            NSImage(size: NSSize(width: 160, height: 45)),
            NSImage(size: NSSize(width: 160, height: 160)),
            NSImage(size: NSSize(width: 90, height: 160)),
            nil,
        ]
        for width: CGFloat in [240, 320, 440] {
            var frames: [Int: CGRect] = [:]
            let host = NSHostingView(rootView: Gallery(images: images) { frames[$0] = $1 })
            host.sizingOptions = []
            host.frame = CGRect(x: 0, y: 0, width: width, height: 116)
            host.layoutSubtreeIfNeeded()
            let deadline = Date().addingTimeInterval(2)
            while frames.count < images.count, Date() < deadline {
                RunLoop.current.run(until: Date().addingTimeInterval(0.01))
                host.layoutSubtreeIfNeeded()
            }
            suite.expect(frames.count == images.count,
                         "wallpaper grid lays out all images and its placeholder at width \(width)")
            let cellWidth = (width - 16) / 3
            for index in images.indices {
                guard let frame = frames[index] else { continue }
                let expectedX = CGFloat(index % 3) * (cellWidth + 8)
                let expectedY = CGFloat(index / 3) * 62
                suite.expect(abs(frame.width - cellWidth) < 1 && abs(frame.height - 54) < 1,
                             "wallpaper \(index) keeps its column width and 54-point height at \(width)")
                suite.expect(abs(frame.minX - expectedX) < 1 && abs(frame.minY - expectedY) < 1,
                             "wallpaper \(index) stays in its grid slot at \(width)")
            }
        }
    }
}
