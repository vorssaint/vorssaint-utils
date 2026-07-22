// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import SwiftUI

/// Settings > Mouse > Mouse button shortcuts: the switch, one row per mapped
/// button with its recorded combination, and a capture flow that asks for a
/// real press instead of making the user guess button numbers.
struct MouseButtonShortcutsSection: View {
    @ObservedObject private var l10n = L10n.shared
    @ObservedObject private var permissions = Permissions.shared
    @ObservedObject private var service = MouseButtonShortcutService.shared
    @AppStorage(DefaultsKey.mouseButtonShortcutsEnabled) private var enabled = false

    @State private var mappings = MouseButtonShortcutSupport.decode(
        UserDefaults.standard.dictionary(forKey: DefaultsKey.mouseButtonShortcuts) as? [String: String])
    /// A button that was just captured and is waiting for its first key
    /// combination. Nothing persists until the combination lands, so backing
    /// out leaves no half-made row behind.
    @State private var pendingButton: Int64?
    @State private var capturing = false
    @State private var captureFeedback: String?
    @State private var recordingButton: Int64?
    /// The recorder's complaint and the row it belongs to; it stays visible
    /// until that row records again, the same way the shortcut rows behave.
    @State private var recordError: String?
    @State private var recordErrorButton: Int64?

    private var text: MouseButtonFeatureStrings { FeatureStrings.mouseButtons(l10n.language) }

    var body: some View {
        Section(text.pageTitle) {
            Toggle(text.enableLabel, isOn: $enabled)
                .onChange(of: enabled) { _, on in
                    if !on { stopCapture() }
                    MouseButtonShortcutService.shared.syncWithPreferences()
                    if on, !permissions.accessibility {
                        permissions.requestAccessibility()
                    }
                }
            Text(text.enableCaption)
                .font(.caption)
                .foregroundStyle(.secondary)
            if enabled {
                if mappings.isEmpty, pendingButton == nil {
                    Text(text.emptyCaption)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                ForEach(MouseButtonShortcutSupport.sortedButtons(mappings), id: \.self) { button in
                    mappingRow(button, shortcut: mappings[button])
                }
                if let pendingButton {
                    mappingRow(pendingButton, shortcut: nil)
                }
                captureRow
            }
        }
        .onDisappear {
            stopCapture()
        }
    }

    // MARK: - Rows

    private func mappingRow(_ button: Int64, shortcut: GlobalShortcut?) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 8) {
                Text(MouseButtonShortcutSupport.buttonName(for: button, strings: text))
                Spacer()
                ShortcutRecorderButton(shortcut: shortcut ?? GlobalShortcut.keepAwakeDefault,
                                       isEnabled: true,
                                       waitingTitle: l10n.s.shortcutPressKeys,
                                       emptyTitle: shortcut == nil ? text.setShortcutButton : nil,
                                       notCapturedAction: { setRecordError(l10n.s.shortcutNotCaptured, button) },
                                       recordingChanged: { recording in
                                           recordingButton = recording ? button : nil
                                           if recording { setRecordError(nil, button) }
                                       },
                                       invalidAction: { setRecordError(l10n.s.shortcutInvalid, button) },
                                       captureAction: { save(button: button, shortcut: $0) })
                    .frame(width: 108)
                Button {
                    remove(button)
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                        .frame(width: 22, height: 22)
                }
                .buttonStyle(.plain)
                .help(text.removeButton)
                .accessibilityLabel(text.removeButton)
            }
            if let recordError, recordErrorButton == button {
                Text(recordError)
                    .font(.caption)
                    .foregroundStyle(.orange)
            } else if recordingButton == button {
                Text(ShortcutRecordingCaption.text(l10n.s, canClear: false))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if shortcut != nil, RadialMenuSupport.claimsMouseButton(button) {
                Text(text.rowWheelNote)
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }
    }

    @ViewBuilder
    private var captureRow: some View {
        if capturing {
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 8) {
                    if service.isRunning {
                        Image(systemName: "circle.dashed")
                            .foregroundStyle(.secondary)
                        Text(text.captureWaiting)
                    } else {
                        Image(systemName: "exclamationmark.circle.fill")
                            .foregroundStyle(.orange)
                        Text(text.captureBlind)
                    }
                    Spacer()
                    Button(text.captureCancel) { stopCapture() }
                }
                if let captureFeedback {
                    Text(captureFeedback)
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
                Text(text.captureHint)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .onReceive(service.$lastButtonSeen) { seen in
                handleCapture(seen)
            }
        } else {
            Button {
                startCapture()
            } label: {
                Label(text.addButton, systemImage: "plus")
            }
        }
    }

    // MARK: - Capture

    private func startCapture() {
        captureFeedback = nil
        capturing = true
        MouseButtonShortcutService.shared.setCapturing(true)
        if !permissions.accessibility {
            permissions.requestAccessibility()
        }
    }

    private func stopCapture() {
        guard capturing else { return }
        capturing = false
        captureFeedback = nil
        MouseButtonShortcutService.shared.setCapturing(false)
    }

    private func handleCapture(_ seen: Int64?) {
        guard capturing, let seen else { return }
        if !MouseButtonShortcutSupport.canMap(seen) {
            captureFeedback = text.captureUnsupported
        } else if RadialMenuSupport.claimsMouseButton(seen) {
            captureFeedback = text.captureWheel
        } else if mappings[seen] != nil || pendingButton == seen {
            captureFeedback = text.captureExists
        } else {
            pendingButton = seen
            recordError = nil
            stopCapture()
        }
    }

    // MARK: - Persistence

    private func setRecordError(_ message: String?, _ button: Int64) {
        recordError = message
        recordErrorButton = message == nil ? nil : button
    }

    private func save(button: Int64, shortcut: GlobalShortcut) {
        mappings[button] = shortcut
        if pendingButton == button { pendingButton = nil }
        setRecordError(nil, button)
        persist()
    }

    private func remove(_ button: Int64) {
        if recordErrorButton == button { setRecordError(nil, button) }
        if pendingButton == button {
            pendingButton = nil
            return
        }
        mappings.removeValue(forKey: button)
        persist()
    }

    private func persist() {
        UserDefaults.standard.set(MouseButtonShortcutSupport.encode(mappings),
                                  forKey: DefaultsKey.mouseButtonShortcuts)
        MouseButtonShortcutService.shared.syncWithPreferences()
    }
}
