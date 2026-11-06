// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import SwiftUI

/// The keyboard typer inside the island, as the scratchpad's page: the text
/// fills the page, the saved snippets can open beside it, and the delay,
/// layout and Send sit under both. The text is the floating pad's own, so
/// either one picks up where the other left off. The island never activates
/// the app, so the app behind keeps its place and Send folds the island to
/// type into it.
struct NotchKeyboardTyperView: View {
    @ObservedObject private var service = KeyboardTyperService.shared
    @ObservedObject private var l10n = L10n.shared
    @AppStorage(DefaultsKey.keyboardTyperSnippetsShown) private var snippetsShown = false
    private static let editorInset = NSSize(width: 6, height: 6)

    var body: some View {
        VStack(spacing: 6) {
            HStack(spacing: 6) {
                editor
                if snippetsShown {
                    KeyboardTyperSnippetPanel()
                        .padding(8)
                        .frame(width: 170)
                        .modifier(NotchControlSurface(cornerRadius: 12, interactive: false))
                }
            }
            KeyboardTyperControls()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .notchBand(trailing: { SnippetsToggle() })
    }

    private var editor: some View {
        ZStack(alignment: .topLeading) {
            PlainTextEditor(text: $service.text,
                            textColor: .white,
                            textContainerInset: Self.editorInset,
                            onCommandReturn: { service.send() }) { view in
                view.insertionPointColor = .white
                // The caret lands in the text as the page opens, as the
                // scratchpad's does, once the island holds the keyboard.
                DispatchQueue.main.async {
                    guard let window = view.window, window.isKeyWindow else { return }
                    window.makeFirstResponder(view)
                }
            }
            if service.text.isEmpty {
                Text(FeatureStrings.keyboardTyper(l10n.language).placeholder)
                    .font(.system(size: PlainTextEditor.defaultFontSize))
                    .foregroundStyle(.white.opacity(0.35))
                    .padding(.leading, Self.editorInset.width + PlainTextEditor.lineFragmentPadding)
                    .padding(.trailing, 12)
                    .padding(.top, Self.editorInset.height)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .modifier(NotchControlSurface(cornerRadius: 12, interactive: false))
    }
}
