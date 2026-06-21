// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import Carbon.HIToolbox
import SwiftUI

struct ShortcutRecorderButton: NSViewRepresentable {
    let shortcut: GlobalShortcut
    let isEnabled: Bool
    let recordingTitle: String
    let invalidAction: () -> Void
    let captureAction: (GlobalShortcut) -> Void

    func makeNSView(context: Context) -> RecorderButton {
        let button = RecorderButton()
        button.bezelStyle = .rounded
        button.setButtonType(.momentaryPushIn)
        button.target = button
        button.action = #selector(RecorderButton.beginRecording)
        apply(to: button)
        return button
    }

    func updateNSView(_ nsView: RecorderButton, context: Context) {
        apply(to: nsView)
    }

    private func apply(to button: RecorderButton) {
        button.shortcut = shortcut
        button.recordingTitle = recordingTitle
        button.invalidAction = invalidAction
        button.captureAction = captureAction
        button.isEnabled = isEnabled
        button.refreshTitle()
    }
}

final class RecorderButton: NSButton {
    var shortcut = GlobalShortcut.keepAwakeDefault
    var recordingTitle = ""
    var invalidAction: (() -> Void)?
    var captureAction: ((GlobalShortcut) -> Void)?
    private var isRecording = false

    override var acceptsFirstResponder: Bool { true }

    @objc func beginRecording() {
        guard isEnabled else { return }
        isRecording = true
        window?.makeFirstResponder(self)
        refreshTitle()
    }

    override func keyDown(with event: NSEvent) {
        guard isRecording else {
            super.keyDown(with: event)
            return
        }
        if Int(event.keyCode) == kVK_Escape {
            isRecording = false
            refreshTitle()
            return
        }
        guard let shortcut = GlobalShortcut(event: event) else {
            NSSound.beep()
            invalidAction?()
            return
        }
        isRecording = false
        self.shortcut = shortcut
        captureAction?(shortcut)
        refreshTitle()
    }

    override func resignFirstResponder() -> Bool {
        isRecording = false
        refreshTitle()
        return super.resignFirstResponder()
    }

    func refreshTitle() {
        title = isRecording ? recordingTitle : shortcut.displayString
    }
}

struct ShortcutPreferenceRow: View {
    @ObservedObject private var l10n = L10n.shared

    private let role: GlobalShortcutRole
    private let isEnabled: Bool
    private let onChange: () -> Void
    @AppStorage private var rawValue: String
    @State private var errorText: String?

    init(role: GlobalShortcutRole, isEnabled: Bool = true, onChange: @escaping () -> Void) {
        self.role = role
        self.isEnabled = isEnabled
        self.onChange = onChange
        _rawValue = AppStorage(wrappedValue: role.defaultShortcut.storageValue, role.storageKey)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 8) {
                Text(l10n.s.shelfHotkeyLabel)
                Spacer()
                ShortcutRecorderButton(shortcut: shortcut,
                                       isEnabled: isEnabled,
                                       recordingTitle: l10n.s.shortcutRecording,
                                       invalidAction: {
                                           errorText = l10n.s.shortcutInvalid
                                       },
                                       captureAction: save)
                    .frame(width: 108, height: 28)
                    .disabled(!isEnabled)
                Button(l10n.s.shortcutReset) {
                    rawValue = role.defaultShortcut.storageValue
                    errorText = nil
                    onChange()
                }
                .disabled(!isEnabled || shortcut == role.defaultShortcut)
            }

            if let errorText {
                Text(errorText)
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }
    }

    private var shortcut: GlobalShortcut {
        GlobalShortcut(storageValue: rawValue) ?? role.defaultShortcut
    }

    private func save(_ shortcut: GlobalShortcut) {
        if let conflict = GlobalShortcutRole.conflict(for: shortcut, excluding: role) {
            errorText = String(format: l10n.s.shortcutConflictFormat, conflict.title(l10n.s))
            return
        }
        rawValue = shortcut.storageValue
        errorText = nil
        onChange()
    }
}
