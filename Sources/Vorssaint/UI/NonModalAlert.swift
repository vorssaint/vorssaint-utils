// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit

/// Shows an `NSAlert` in its own window, without a modal session.
///
/// `runModal()` keeps the main run loop in the modal panel mode until the
/// alert closes, so default-mode timers stop meanwhile and a running
/// recording's timer stops counting (issue #1665). The modal loop still runs
/// main-queue blocks in that mode, unless it was started inside a main-queue
/// block. The disk image installer opened both of its alerts inside such a
/// block (the hop after the mount check and the one after the install), and
/// that nesting held a global shortcut's work back until the alert was
/// dismissed. The alert keeps its buttons, key equivalents, accessory view
/// and the modal panel level; its response arrives in `completion` instead.
final class NonModalAlert: NSObject {
    /// Open alerts own their presentation until they answer.
    private static var open: [NonModalAlert] = []

    let alert: NSAlert
    private let retained: [AnyObject]
    private var completion: ((NSApplication.ModalResponse) -> Void)?

    private init(alert: NSAlert, retained: [AnyObject],
                 completion: @escaping (NSApplication.ModalResponse) -> Void) {
        self.alert = alert
        self.retained = retained
        self.completion = completion
    }

    /// `retaining` keeps objects the alert only references weakly, such as
    /// the target of an accessory checkbox, alive until the alert answers.
    @discardableResult
    static func present(_ alert: NSAlert,
                        retaining retained: [AnyObject] = [],
                        show: (NSWindow) -> Void = { window in
                            window.center()
                            window.makeKeyAndOrderFront(nil)
                        },
                        completion: @escaping (NSApplication.ModalResponse) -> Void) -> NonModalAlert {
        let presentation = NonModalAlert(alert: alert, retained: retained, completion: completion)
        // An alert without buttons shows an OK button that `buttons` may not
        // list, so nothing would point it at `respond`. Add that button here.
        if alert.buttons.isEmpty {
            alert.addButton(withTitle: Bundle(for: NSAlert.self)
                .localizedString(forKey: "OK", value: "OK", table: "Common"))
        }
        for button in alert.buttons {
            button.target = presentation
            button.action = #selector(respond(_:))
        }
        alert.layout()
        alert.window.level = .modalPanel
        alert.window.hidesOnDeactivate = false
        open.append(presentation)
        show(alert.window)
        return presentation
    }

    var isOpen: Bool { completion != nil }

    /// Closes the alert as if `response` had been chosen. An alert that
    /// already answered stays answered.
    func dismiss(with response: NSApplication.ModalResponse) {
        guard let completion else { return }
        self.completion = nil
        alert.window.orderOut(nil)
        Self.open.removeAll { $0 === self }
        completion(response)
    }

    @objc private func respond(_ sender: NSButton) {
        guard let index = alert.buttons.firstIndex(of: sender) else { return }
        dismiss(with: NSApplication.ModalResponse(
            rawValue: NSApplication.ModalResponse.alertFirstButtonReturn.rawValue + index))
    }
}
