// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit

/// The system alerts Privacy Lock asks its questions with: the same panels
/// every Mac app uses, so a password prompt looks like what a person trusts.
@MainActor
enum PrivacyLockPrompts {
    struct NewPassword {
        let password: String
        let remember: Bool
        let applyToRest: Bool
    }

    private static var text: PrivacyLockFeatureStrings { FeatureStrings.privacyLock(L10n.shared.language) }

    /// Asks for the password of an item about to be locked, twice, until the
    /// two agree. Nil when the person cancels.
    static func askNewPassword(itemName: String, canRemember: Bool, hasMore: Bool) -> NewPassword? {
        var problem: String?
        while true {
            let alert = NSAlert()
            alert.alertStyle = .informational
            alert.messageText = String(format: text.lockPromptTitleFormat, itemName)
            alert.informativeText = problem ?? text.lockPromptMessage
            alert.icon = NSImage(systemSymbolName: "lock.fill", accessibilityDescription: nil)

            let password = field(placeholder: text.passwordField)
            let repeated = field(placeholder: text.repeatField)
            let remember = checkbox(text.rememberCheckbox)
            let rest = checkbox(text.applyAllCheckbox)
            var views: [NSView] = [password, repeated]
            if canRemember { views.append(remember) }
            if hasMore { views.append(rest) }
            alert.accessoryView = stack(views)
            alert.addButton(withTitle: text.lockButton)
            alert.addButton(withTitle: text.cancel)
            alert.window.initialFirstResponder = password
            NSApp.activate(ignoringOtherApps: true)
            guard alert.runModal() == .alertFirstButtonReturn else { return nil }

            switch PrivacyLockSupport.passwordProblem(password.stringValue, confirmation: repeated.stringValue) {
            case .tooShort: problem = String(format: text.shortPasswordFormat, PrivacyLockSupport.minimumPasswordLength)
            case .tooLong: problem = String(format: text.shortPasswordFormat, PrivacyLockSupport.minimumPasswordLength)
            case .mismatch: problem = text.mismatch
            case nil:
                return NewPassword(password: password.stringValue, remember: canRemember && remember.state == .on,
                                   applyToRest: hasMore && rest.state == .on)
            }
        }
    }

    /// Asks for the password of a locked item. Nil when the person cancels.
    static func askPassword(itemName: String, wrong: Bool) -> String? {
        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = String(format: text.unlockPromptTitleFormat, itemName)
        alert.informativeText = wrong ? text.wrongPassword : text.unlockPromptMessage
        alert.icon = NSImage(systemSymbolName: "lock.fill", accessibilityDescription: nil)
        let password = field(placeholder: text.passwordField)
        alert.accessoryView = stack([password])
        alert.addButton(withTitle: text.unlockButton)
        alert.addButton(withTitle: text.cancel)
        alert.window.initialFirstResponder = password
        NSApp.activate(ignoringOtherApps: true)
        guard alert.runModal() == .alertFirstButtonReturn, !password.stringValue.isEmpty else { return nil }
        return password.stringValue
    }

    /// A password for the app lock itself, set or changed from Settings.
    static func askAppLockPassword() -> String? {
        var problem: String?
        while true {
            let alert = NSAlert()
            alert.alertStyle = .informational
            alert.messageText = text.appLockTitle
            alert.informativeText = problem ?? text.lockPromptMessage
            alert.icon = NSImage(systemSymbolName: "lock.shield", accessibilityDescription: nil)
            let password = field(placeholder: text.newPasswordPlaceholder)
            let repeated = field(placeholder: text.repeatPlaceholder)
            alert.accessoryView = stack([password, repeated])
            alert.addButton(withTitle: text.lockButton)
            alert.addButton(withTitle: text.cancel)
            alert.window.initialFirstResponder = password
            NSApp.activate(ignoringOtherApps: true)
            guard alert.runModal() == .alertFirstButtonReturn else { return nil }
            switch PrivacyLockSupport.passwordProblem(password.stringValue, confirmation: repeated.stringValue) {
            case .tooShort, .tooLong: problem = String(format: text.shortPasswordFormat, PrivacyLockSupport.minimumPasswordLength)
            case .mismatch: problem = text.mismatch
            case nil: return password.stringValue
            }
        }
    }

    static func showError(_ message: String) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = text.errorTitle
        alert.informativeText = message
        alert.addButton(withTitle: "OK")
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }

    // MARK: Pieces

    private static func field(placeholder: String) -> NSSecureTextField {
        let field = NSSecureTextField(frame: NSRect(x: 0, y: 0, width: 280, height: 24))
        field.placeholderString = placeholder
        return field
    }

    private static func checkbox(_ title: String) -> NSButton {
        let button = NSButton(checkboxWithTitle: title, target: nil, action: nil)
        button.lineBreakMode = .byWordWrapping
        return button
    }

    private static func stack(_ views: [NSView]) -> NSView {
        let stack = NSStackView(views: views)
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 8
        stack.frame = NSRect(x: 0, y: 0, width: 280, height: CGFloat(views.count) * 32)
        return stack
    }
}
