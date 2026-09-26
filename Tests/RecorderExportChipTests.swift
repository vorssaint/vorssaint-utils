// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import SwiftUI

/// Lays out the production export chip inside a band like the editor's top
/// band, without a window or any input, and reads the size the chip settles at.
enum RecorderExportChipTests {
    enum Phase { case saving, compressing, uploading }
    final class Model: ObservableObject {
        @Published var exportPhase = Phase.saving
        @Published var exportProgress = 0.4
        func cancelExport() {}
    }
    struct Strings {
        let exportingLabel = "Saving…"
        let cancelButton = "Cancel"
    }

    private struct Band: View {
        @ObservedObject var model: Model
        let report: (CGSize) -> Void

        var body: some View {
            HStack(spacing: 8) {
                Color.clear.frame(width: 60, height: 20)
                Spacer(minLength: 10)
                Chip(model: model).background(GeometryReader { proxy in
                    Color.clear
                        .onAppear { report(proxy.size) }
                        .onChange(of: proxy.size) { report(proxy.size) }
                })
                Color.clear.frame(width: 60, height: 20)
            }
        }
    }

    private static func chipSize(bandWidth: CGFloat) -> CGSize {
        var reported = CGSize.zero
        let host = NSHostingView(rootView: Band(model: Model(), report: { reported = $0 }))
        host.sizingOptions = []
        host.frame = CGRect(x: 0, y: 0, width: bandWidth, height: 60)
        host.layoutSubtreeIfNeeded()
        let deadline = Date().addingTimeInterval(2)
        while reported == .zero, Date() < deadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.01))
        }
        return reported
    }

    static func run(expect: (Bool, String) -> Void) {
        let roomy = chipSize(bandWidth: 500)
        let squeezed = chipSize(bandWidth: 330)
        expect(roomy != .zero && squeezed != .zero, "the export chip reports its laid-out size")
        expect(squeezed.width < roomy.width && squeezed.width <= 176,
               "a narrow band shrinks the chip into the room the band leaves it")
        expect(squeezed.height == roomy.height,
               "the squeezed chip keeps one line of text: the progress bar gives way instead of the words wrapping")
    }
}
