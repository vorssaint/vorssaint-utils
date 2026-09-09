// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import SwiftUI

/// Dedicated Settings surface for the screen annotation overlay.
/// The overlay itself is native AppKit; this page is the discoverable control
/// surface in the sidebar and provides the immediate actions users need.
struct ScreenAnnotationSettings: View {
    @ObservedObject private var l10n = L10n.shared
    @ObservedObject private var annotation = ScreenAnnotationService.shared
    @AppStorage(DefaultsKey.screenAnnotationShortcutEnabled) private var shortcutEnabled = false

    private var strings: ScreenAnnotationStrings { FeatureStrings.annotation(l10n.language) }

    var body: some View {
        Form {
            Section {
                Button {
                    ScreenAnnotationService.shared.toggleDrawing()
                } label: {
                    Label(strings.openOverlay, systemImage: "pencil.and.outline")
                }
                Text(strings.settingsDescription)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Toggle(l10n.s.quickToolShortcutToggle, isOn: $shortcutEnabled)
                    .onChange(of: shortcutEnabled) { _, _ in
                        ScreenAnnotationService.shared.syncShortcut()
                    }
                ShortcutPreferenceRow(role: .screenAnnotation,
                                      isEnabled: shortcutEnabled) {
                    ScreenAnnotationService.shared.syncShortcut()
                }
                if shortcutEnabled, annotation.shortcutRegistrationFailed {
                    Text(l10n.s.shortcutUnavailable)
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            } header: {
                Text(strings.title)
            }

            Section {
                LabeledContent(strings.pen, value: strings.penDescription)
                LabeledContent(strings.highlighter, value: strings.highlighterDescription)
                LabeledContent(strings.undo, value: strings.undoDescription)
                LabeledContent(strings.clear, value: strings.clearDescription)
            } header: {
                Text(strings.controls)
            }
        }
        .formStyle(.grouped)
    }
}
