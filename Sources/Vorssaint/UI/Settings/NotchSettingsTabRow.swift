// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import SwiftUI

enum NotchSettingsTab: CaseIterable {
    case layout, content, activity, behavior
}

/// The Dynamic Island page's tabs, with the button that opens the island.
/// Four tab names can need more room than the narrowest window leaves the
/// page in longer languages, and a page wider than its column is centered and
/// cut on both sides, under the sidebar. The segments give way to a menu
/// whenever they don't fit beside the button.
struct NotchSettingsTabRow: View {
    @Binding var tab: NotchSettingsTab
    let language: AppLanguage
    let canOpen: Bool
    let open: () -> Void

    var body: some View {
        let text = FeatureStrings.notch(language)
        HStack {
            ViewThatFits(in: .horizontal) {
                picker.pickerStyle(.segmented)
                picker.pickerStyle(.menu)
            }
            Button(action: open) { Image(systemName: "arrow.up.forward.app") }
                .buttonStyle(.bordered).disabled(!canOpen).help(text.open).accessibilityLabel(text.open)
        }
    }

    private var picker: some View {
        let editor = FeatureStrings.notchEditor(language)
        return Picker(FeatureStrings.notch(language).title, selection: $tab) {
            Text(editor.layout).tag(NotchSettingsTab.layout)
            Text(editor.content).tag(NotchSettingsTab.content)
            Text(editor.activity).tag(NotchSettingsTab.activity)
            Text(editor.behavior).tag(NotchSettingsTab.behavior)
        }
        .labelsHidden()
    }
}
