// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import Carbon.HIToolbox
import SwiftUI

struct ShortcutRecorderButton: NSViewRepresentable {
    let shortcut: GlobalShortcut
    let isEnabled: Bool
    /// Shown inside the field while it is listening. Short on purpose: the
    /// sentence explaining what to do lives in the caption under the row, so
    /// the field never has to grow to fit it.
    let waitingTitle: String
    /// When set, the button shows this instead of the shortcut, meaning "no
    /// shortcut assigned"; clicking still records a new one.
    var emptyTitle: String? = nil
    /// Set by rows whose shortcut may be removed. Delete on its own then takes
    /// the shortcut off instead of trying to record.
    var clearAction: (() -> Void)? = nil
    /// Fired when the combination never reached us, so the row can say why.
    var notCapturedAction: (() -> Void)? = nil
    /// Lets the row show its caption exactly while the field is listening.
    var recordingChanged: ((Bool) -> Void)? = nil
    let invalidAction: () -> Void
    let captureAction: (GlobalShortcut) -> Void

    func makeNSView(context: Context) -> RecorderButton {
        let button = RecorderButton()
        button.bezelStyle = .rounded
        button.setButtonType(.momentaryPushIn)
        // One font in every state. The field used to swap a monospaced cap for
        // a proportional sentence, which changed its width mid-interaction.
        button.font = .systemFont(ofSize: 13, weight: .medium)
        // A translation longer than the field trims instead of spilling over
        // the label beside it.
        button.cell?.lineBreakMode = .byTruncatingTail
        button.target = button
        button.action = #selector(RecorderButton.beginRecording)
        apply(to: button)
        return button
    }

    func updateNSView(_ nsView: RecorderButton, context: Context) {
        apply(to: nsView)
    }

    /// The SwiftUI frame decides the width, never the title. An AppKit view's
    /// intrinsic size otherwise wins over the frame, so the field grew with
    /// its own text and slid over the column beside it (issue #308). The
    /// height is the bezel's own, so the control is never drawn short.
    func sizeThatFits(_ proposal: ProposedViewSize,
                      nsView: RecorderButton,
                      context: Context) -> CGSize? {
        let intrinsic = nsView.intrinsicContentSize
        return CGSize(width: proposal.width ?? intrinsic.width, height: intrinsic.height)
    }

    static func dismantleNSView(_ nsView: RecorderButton, coordinator: ()) {
        // The view can go away mid-recording (a sheet closing, a page swap).
        // Nothing else would give the app's own shortcuts back. The row is
        // going away with it, so drop the callback first rather than touch its
        // state while SwiftUI is taking it apart.
        nsView.recordingChanged = nil
        nsView.stopRecording()
    }

    private func apply(to button: RecorderButton) {
        button.shortcut = shortcut
        button.waitingTitle = waitingTitle
        button.emptyTitle = emptyTitle
        button.clearAction = clearAction
        button.notCapturedAction = notCapturedAction
        button.recordingChanged = recordingChanged
        button.invalidAction = invalidAction
        button.captureAction = captureAction
        button.isEnabled = isEnabled
        button.refreshTitle()
    }
}

final class RecorderButton: NSButton {
    var shortcut = GlobalShortcut.keepAwakeDefault
    var waitingTitle = ""
    var emptyTitle: String?
    var clearAction: (() -> Void)?
    var notCapturedAction: (() -> Void)?
    var recordingChanged: ((Bool) -> Void)?
    var invalidAction: (() -> Void)?
    var captureAction: ((GlobalShortcut) -> Void)?
    private var isRecording = false
    /// True once a Control, Option or Command combination went down while the
    /// field was listening and no key has arrived since. If the modifiers then
    /// come all the way back up with nothing in between, the key never reached
    /// us: something upstream consumed it.
    private var awaitingKeyForHeldModifiers = false
    private var observers: [NSObjectProtocol] = []

    override var acceptsFirstResponder: Bool { true }

    deinit {
        for observer in observers { NotificationCenter.default.removeObserver(observer) }
        guard isRecording else { return }
        // Last resort. Leaving the app's shortcuts suspended, or the
        // recording tap eating the keyboard, would be worse than the bug
        // this fixes, so give both back even from here.
        if Thread.isMainThread {
            ShortcutRecordingTap.end()
            ShortcutCapture.end()
        } else {
            DispatchQueue.main.async {
                ShortcutRecordingTap.end()
                ShortcutCapture.end()
            }
        }
    }

    @objc func beginRecording() {
        guard isEnabled, !isRecording else { return }
        // Take the keyboard first: a field that believes it is listening while
        // some other view holds the keys would suspend the app's shortcuts and
        // never see the press that gives them back.
        if window?.firstResponder !== self {
            guard window?.makeFirstResponder(self) == true else { return }
        }
        isRecording = true
        awaitingKeyForHeldModifiers = false
        ShortcutCapture.begin()
        // The tap keeps the typed combination to the field: without it, a
        // combination the system or another app answers to performs that
        // action while being recorded. When the tap cannot exist (no
        // Accessibility), the view events below still record as before.
        ShortcutRecordingTap.begin { [weak self] keyCode, modifiers in
            guard let self, self.isRecording else { return }
            self.handleRecordingKey(keyCode: keyCode, modifiers: modifiers)
        }
        observeExits()
        refreshTitle()
        recordingChanged?(true)
    }

    /// Every route out of recording lands here, and it is safe to call when
    /// nothing is being recorded.
    func stopRecording() {
        guard isRecording else { return }
        isRecording = false
        awaitingKeyForHeldModifiers = false
        for observer in observers { NotificationCenter.default.removeObserver(observer) }
        observers.removeAll()
        ShortcutRecordingTap.end()
        ShortcutCapture.end()
        refreshTitle()
        recordingChanged?(false)
    }

    /// Combinations built with Control, Option or Command are offered to the
    /// view hierarchy before the app's own menu, so this is where nearly every
    /// recordable press arrives. Without it the menu answered first and the
    /// app closed its window on Command W or quit on Command Q instead of
    /// recording them (issue #308).
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard isRecording, window?.firstResponder === self else {
            return super.performKeyEquivalent(with: event)
        }
        handleRecordingKey(event)
        return true
    }

    /// Keys with no Control, Option or Command never reach the key equivalent
    /// path, so Escape, Delete and plain keys land here.
    override func keyDown(with event: NSEvent) {
        guard isRecording else {
            super.keyDown(with: event)
            return
        }
        handleRecordingKey(event)
    }

    override func flagsChanged(with event: NSEvent) {
        guard isRecording else {
            super.flagsChanged(with: event)
            return
        }
        let modifiers = GlobalShortcutModifiers(eventFlags: event.modifierFlags)
        if modifiers.hasPrimaryModifier {
            awaitingKeyForHeldModifiers = true
        } else if modifiers.isEmpty, awaitingKeyForHeldModifiers {
            awaitingKeyForHeldModifiers = false
            notCapturedAction?()
        }
    }

    override func resignFirstResponder() -> Bool {
        stopRecording()
        return super.resignFirstResponder()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window == nil { stopRecording() }
    }

    private func handleRecordingKey(_ event: NSEvent) {
        handleRecordingKey(keyCode: Int64(event.keyCode),
                           modifiers: GlobalShortcutModifiers(eventFlags: event.modifierFlags))
    }

    /// The one recording path, fed by the swallowing tap or, without it, by
    /// the view events above.
    private func handleRecordingKey(keyCode: Int64, modifiers: GlobalShortcutModifiers) {
        // A key arrived, so the modifiers being held did produce something.
        awaitingKeyForHeldModifiers = false

        if keyCode == Int64(kVK_Escape), !modifiers.hasPrimaryModifier {
            stopRecording()
            return
        }
        if GlobalShortcut.clearsShortcut(keyCode: keyCode, modifiers: modifiers) {
            guard let clearAction else { return }
            stopRecording()
            clearAction()
            return
        }
        let captured = GlobalShortcut(keyCode: keyCode, modifiers: modifiers)
        guard captured.isValid else {
            NSSound.beep()
            invalidAction?()
            return
        }
        shortcut = captured
        stopRecording()
        captureAction?(captured)
    }

    /// Watchers that exist only while the field is listening. Each one is a
    /// way out of recording that no key press would announce.
    private func observeExits() {
        let center = NotificationCenter.default
        observers.append(center.addObserver(forName: NSApplication.didResignActiveNotification,
                                            object: nil, queue: .main) { [weak self] _ in
            self?.stopRecording()
        })
        if let window {
            observers.append(center.addObserver(forName: NSWindow.willCloseNotification,
                                                object: window, queue: .main) { [weak self] _ in
                self?.stopRecording()
            })
        }
    }

    func refreshTitle() {
        if isRecording {
            title = waitingTitle
        } else {
            title = emptyTitle ?? shortcut.displayString
        }
    }
}

struct ShortcutPreferenceRow: View {
    @ObservedObject private var l10n = L10n.shared

    private let role: GlobalShortcutRole
    private let isEnabled: Bool
    private let label: String?
    private let onChange: () -> Void
    private let additionalConflict: (GlobalShortcut) -> String?
    @AppStorage private var rawValue: String
    @State private var errorText: String?
    @State private var isRecording = false

    init(role: GlobalShortcutRole,
         isEnabled: Bool = true,
         label: String? = nil,
         additionalConflict: @escaping (GlobalShortcut) -> String? = { _ in nil },
         onChange: @escaping () -> Void) {
        self.role = role
        self.isEnabled = isEnabled
        self.label = label
        self.additionalConflict = additionalConflict
        self.onChange = onChange
        _rawValue = AppStorage(wrappedValue: role.defaultShortcut.storageValue, role.storageKey)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 8) {
                Text(label ?? l10n.s.shelfHotkeyLabel)
                Spacer()
                ShortcutRecorderButton(shortcut: shortcut,
                                       isEnabled: isEnabled,
                                       waitingTitle: l10n.s.shortcutPressKeys,
                                       notCapturedAction: { errorText = l10n.s.shortcutNotCaptured },
                                       recordingChanged: { recording in
                                           isRecording = recording
                                           if recording { errorText = nil }
                                       },
                                       invalidAction: {
                                           errorText = l10n.s.shortcutInvalid
                                       },
                                       captureAction: save)
                    .frame(width: 108)
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
            } else if isRecording {
                Text(ShortcutRecordingCaption.text(l10n.s, canClear: false))
                    .font(.caption)
                    .foregroundStyle(.secondary)
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
        if let conflict = additionalConflict(shortcut) {
            errorText = String(format: l10n.s.shortcutConflictFormat, conflict)
            return
        }
        rawValue = shortcut.storageValue
        errorText = nil
        onChange()
    }
}
