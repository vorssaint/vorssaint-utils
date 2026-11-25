// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import CoreGraphics

/// Makes Vorssaint's own Command-Q wait for a hold when the user asks for it,
/// with the same reminder Quit Protection shows for other apps.
///
/// It sees only key presses sent to this app's own windows, so it needs no
/// Accessibility permission and costs nothing while the user types elsewhere.
/// The setting is read on each Command-Q rather than synced, so a restored
/// backup applies at once. Choosing Quit from the menu with the mouse still
/// quits straight away.
final class OwnQuitGuard {
    static let shared = OwnQuitGuard()

    /// How often a running hold checks the keys are still down. The deadline
    /// is read from the clock, so this only bounds how late it is noticed.
    private static let pollInterval: TimeInterval = 0.03
    /// How long the reminder stays after an early release.
    private static let lingerDuration: TimeInterval = 1.5

    private var monitor: Any?
    private var hold = OwnQuitHold()
    private var heldKeyCode: CGKeyCode = 0
    private var poll: Timer?
    private var hideReminder: DispatchWorkItem?
    private let hud = QuitProtectionHUD()

    private init() {}

    func install() {
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            return self.handle(event)
        }
    }

    private func handle(_ event: NSEvent) -> NSEvent? {
        // A hold already running finishes even if the setting just went off,
        // so its repeats never fall through to the Quit menu item.
        guard hold.isHolding || UserDefaults.standard.bool(forKey: DefaultsKey.holdCommandQToQuit) else {
            return event
        }
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let keyCode = Int64(event.keyCode)
        let isCommandQ = QuitProtectionSupport.isBaseShortcut(
            keyCharacter: event.charactersIgnoringModifiers?.lowercased(),
            keyCode: keyCode,
            commandLabel: GlobalShortcut.layoutKeyLabel(for: keyCode, usesCommand: true),
            command: flags.contains(.command),
            control: flags.contains(.control),
            option: flags.contains(.option),
            shift: flags.contains(.shift),
            shortcut: .quit
        )
        let confirmedElsewhere = event.cgEvent?.getIntegerValueField(.eventSourceUserData)
            == OwnKeyEvent.quitProtectionMarker

        switch hold.keyDown(isCommandQ: isCommandQ,
                            isRepeat: event.isARepeat,
                            confirmedElsewhere: confirmedElsewhere,
                            at: ProcessInfo.processInfo.systemUptime) {
        case .pass:
            return event
        case .swallow:
            return nil
        case .begin:
            heldKeyCode = CGKeyCode(event.keyCode)
            begin()
            return nil
        }
    }

    private func begin() {
        hideReminder?.cancel()
        hideReminder = nil
        hud.show(title: reminderTitle, detail: AppInfo.name,
                 holdDeadline: Date().addingTimeInterval(OwnQuitHold.duration))
        let timer = Timer(timeInterval: Self.pollInterval, repeats: true) { [weak self] _ in
            self?.tick()
        }
        // Common modes, so an open menu or a live resize cannot stall the hold.
        RunLoop.main.add(timer, forMode: .common)
        poll = timer
    }

    private func tick() {
        // The key's own state rather than its key up: the release may go to
        // another app if focus moves during the hold.
        let stillHeld = CGEventSource.keyState(.combinedSessionState, key: heldKeyCode)
            && CGEventSource.flagsState(.combinedSessionState).contains(.maskCommand)
        switch hold.tick(stillHeld: stillHeld, at: ProcessInfo.processInfo.systemUptime) {
        case .wait:
            return
        case .cancel:
            stopPolling()
            // Like the browser it copies, the reminder stays long enough to
            // read after a quick press.
            hud.show(title: reminderTitle, detail: AppInfo.name)
            let work = DispatchWorkItem { [weak self] in self?.hud.hide() }
            hideReminder = work
            DispatchQueue.main.asyncAfter(deadline: .now() + Self.lingerDuration, execute: work)
        case .quit:
            stopPolling()
            hud.hide()
            NSApp.terminate(nil)
        }
    }

    private func stopPolling() {
        poll?.invalidate()
        poll = nil
    }

    private var reminderTitle: String {
        let strings = FeatureStrings.quitProtection(L10n.shared.language)
        return String(format: strings.holdHUDFormat(for: .quit), QuitProtectionShortcut.quit.symbol)
    }
}
