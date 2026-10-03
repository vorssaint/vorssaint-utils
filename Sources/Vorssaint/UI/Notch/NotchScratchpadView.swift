// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import SwiftUI

/// Both surfaces use the same editor and note actions. The island only adds
/// its host's load, close and find lifecycle.
struct NotchScratchpadView: View {
    @ObservedObject var service: NotchService
    @ObservedObject private var pad = ScratchpadService.shared
    @ObservedObject private var l10n = L10n.shared
    @State private var loadFailed = false
    private var text: ScratchpadFeatureStrings { FeatureStrings.scratchpad(l10n.language) }

    var body: some View {
        Group {
            if loadFailed {
                NotchEmptyView(symbol: "exclamationmark.triangle", message: text.loadFailed)
            } else {
                ScratchpadWorkspace(island: true)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear { loadFailed = !pad.loadForEmbedding() }
        .onDisappear { pad.commitEdits() }
        .onChange(of: service.scratchpadCloseSerial) { _, _ in
            if let id = pad.selectedPadID { _ = pad.closePad(id) }
        }
        .onChange(of: service.scratchpadFindSerial) { _, _ in
            NotificationCenter.default.post(name: .scratchpadFind, object: nil,
                                            userInfo: ["action": service.scratchpadFindAction])
        }
    }
}
