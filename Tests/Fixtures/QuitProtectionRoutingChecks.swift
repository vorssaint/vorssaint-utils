// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

// Appended beside the production service to exercise its private event routing.
extension QuitProtectionRoutingContract.QuitProtectionService {
    static func routingChecks(_ suite: TestSuite) {
        typealias Contract = QuitProtectionRoutingContract
        let defaults = Contract.UserDefaults.standard
        defaults.removePersistentDomain(forName: "vorss.tests.quit-routing")
        defer { defaults.removePersistentDomain(forName: "vorss.tests.quit-routing") }
        defaults.set(true, forKey: DefaultsKey.quitProtectionQuitEnabled)
        defaults.set("selectedOnly", forKey: DefaultsKey.quitProtectionQuitScope)
        defaults.set(["com.google.Chrome"], forKey: DefaultsKey.quitProtectionQuitExceptions)
        defaults.set(true, forKey: DefaultsKey.quitProtectionQuitShowFeedback)
        defaults.set(true, forKey: DefaultsKey.quitProtectionCloseEnabled)

        let factorySwitcher = [
            LiveSystemShortcut(id: 1, keyCode: 48, flags: .maskCommand, enabled: true),
            LiveSystemShortcut(id: 2, keyCode: 48, flags: [.maskCommand, .maskShift], enabled: true),
        ]
        Contract.SymbolicHotKeys.snapshot = factorySwitcher
        defer {
            Contract.SymbolicHotKeys.snapshot = nil
            Contract.SymbolicHotKeys.readCount = 0
            Contract.SymbolicHotKeys.requestedIDs = []
            Contract.AppSwitcher.shared.keyboardInputOwnership = (false, 0)
        }

        let service = Self()
        service.isRunning = true
        service.frontmostProcessIdentifier = 100
        service.frontmostBundleIdentifier = "com.google.Chrome"
        defer { service.stop() }

        @discardableResult
        func send(_ key: CGKeyCode, _ type: CGEventType = .keyDown,
                  flags: CGEventFlags = .maskCommand, repeatKey: Bool = false) -> Bool {
            let event = CGEvent(keyboardEventSource: nil, virtualKey: key, keyDown: type == .keyDown)!
            event.flags = flags
            event.setIntegerValueField(.keyboardEventAutorepeat, value: repeatKey ? 1 : 0)
            return service.handle(type: type, event: event) != nil
        }

        // Chrome stays frontmost while the native switcher selects another app.
        // A held Q must reach the switcher, with no termination of Chrome.
        for mode in QuitProtectionMode.allCases {
            defaults.set(mode.rawValue, forKey: DefaultsKey.quitProtectionQuitMode)
            Contract.NSRunningApplication.terminated = []
            send(48)
            send(48, .keyUp)
            let passed = send(12)
            let repeated = send(12, repeatKey: true)
            let secondPress = send(12)
            let extraModifier = send(12, flags: [.maskCommand, .maskShift])
            service.holdTimer?.fire()
            let released = send(12, .keyUp)
            suite.expect(passed && repeated && secondPress && extraModifier && released && service.pending == nil
                         && !service.hud.visible && Contract.NSRunningApplication.terminated.isEmpty,
                         "native Command-Tab owns Q in \(mode.rawValue) mode without quitting the foreground app")
            send(55, .flagsChanged, flags: [])
        }

        send(48)
        suite.expect(send(13) && send(13, .keyUp) && service.pending == nil,
                     "native Command-Tab also receives W without starting foreground-window protection")
        send(55, .flagsChanged, flags: [])

        // Change the real routing's table without restarting the service.
        // Old combinations must protect Q/W; new ones must leave them to macOS.
        let remappings: [(CGKeyCode, CGEventFlags)] = [
            (38, .maskCommand),
            (38, [.maskCommand, .maskControl]),
            (38, [.maskCommand, .maskSecondaryFn]),
        ]
        for mode in QuitProtectionMode.allCases {
            defaults.set(mode.rawValue, forKey: DefaultsKey.quitProtectionQuitMode)
            defaults.set(mode.rawValue, forKey: DefaultsKey.quitProtectionCloseMode)
            for (key, flags) in remappings {
                Contract.SymbolicHotKeys.snapshot = factorySwitcher
                send(48)
                send(55, .flagsChanged, flags: [])
                Contract.SymbolicHotKeys.snapshot = [
                    LiveSystemShortcut(id: 1, keyCode: Int64(key), flags: flags, enabled: true),
                ]
                for protectedKey: CGKeyCode in [12, 13] {
                    // Tab was the previous mapping; the bare new key must
                    // also stay unclaimed when its row requires Control or Fn.
                    for obsoleteKey in (flags == .maskCommand ? [48] : [48, key]) {
                        send(obsoleteKey)
                        suite.expect(!send(protectedKey) && service.pending != nil,
                                     "an obsolete or incomplete native chord keeps \(mode.rawValue) protection for key \(protectedKey)")
                        send(protectedKey, .keyUp)
                        send(55, .flagsChanged, flags: [])
                    }

                    Contract.NSRunningApplication.terminated = []
                    send(protectedKey)
                    let oldTimer = service.holdTimer
                    send(key, flags: flags)
                    oldTimer?.fire()
                    suite.expect(send(protectedKey) && send(protectedKey, .keyUp)
                                 && service.pending == nil && !service.hud.visible
                                 && Contract.NSRunningApplication.terminated.isEmpty,
                                 "a live remapping cancels pending \(mode.rawValue) protection and passes key \(protectedKey) to macOS")
                    send(55, .flagsChanged, flags: [])
                }
            }
        }
        defaults.set("hold", forKey: DefaultsKey.quitProtectionQuitMode)
        defaults.set("hold", forKey: DefaultsKey.quitProtectionCloseMode)

        // Take-over changes the enabled state while the service stays up.
        // Return/click can end the custom session without releasing Command.
        for dismissalKey: CGKeyCode? in [36, nil] {
            Contract.SymbolicHotKeys.snapshot = factorySwitcher
            send(48)
            send(55, .flagsChanged, flags: [])
            Contract.SymbolicHotKeys.snapshot = factorySwitcher.map {
                LiveSystemShortcut(id: $0.id, shortcut: $0.shortcut, enabled: false)
            }
            send(48)
            suite.expect(!service.nativeSwitcherSessionActive,
                         "a disabled native row never opens a native session")
            Contract.AppSwitcher.shared.keyboardInputOwnership = (true, 1)
            if let dismissalKey { send(dismissalKey) }
            Contract.AppSwitcher.shared.keyboardInputOwnership = (false, 1)
            suite.expect(!send(12) && service.pending != nil,
                         "ending a take-over session with Command held keeps quit protection")
            send(12, .keyUp)
            send(55, .flagsChanged, flags: [])
        }
        Contract.SymbolicHotKeys.snapshot = nil
        send(48)
        suite.expect(send(12) && service.pending == nil,
                     "missing private readers retain native Command-Tab routing")
        send(55, .flagsChanged, flags: [])
        Contract.SymbolicHotKeys.snapshot = factorySwitcher
        let readsBeforeTyping = Contract.SymbolicHotKeys.readCount
        send(6, flags: [])
        send(6, .keyUp, flags: .maskCommand)
        send(55, .flagsChanged)
        suite.expect(Contract.SymbolicHotKeys.readCount == readsBeforeTyping
                     && Contract.SymbolicHotKeys.requestedIDs == [1, 2],
                     "only Command key downs read the two native app-switcher rows")

        // Each mode still protects and confirms the intended foreground app
        // after Command is released.
        for mode in QuitProtectionMode.allCases {
            defaults.set(mode.rawValue, forKey: DefaultsKey.quitProtectionQuitMode)
            Contract.NSRunningApplication.terminated = []
            suite.expect(!send(12) && service.pending != nil,
                         "ordinary Command-Q still starts \(mode.rawValue) protection")
            switch mode {
            case .hold: service.holdTimer?.fire()
            case .doublePress:
                send(12, .keyUp)
                send(12)
            case .extraModifier: send(12, flags: [.maskCommand, .maskShift])
            }
            suite.expect(Contract.NSRunningApplication.terminated == [100],
                         "an ordinary \(mode.rawValue) confirmation still quits its protected target")
            send(12, .keyUp)
        }
        defaults.set("hold", forKey: DefaultsKey.quitProtectionQuitMode)

        // A confirmation started before Command-Tab must not survive it.
        Contract.NSRunningApplication.terminated = []
        send(12)
        let oldTimer = service.holdTimer
        send(48, flags: [.maskCommand, .maskShift])
        oldTimer?.fire()
        suite.expect(service.pending == nil && !service.hud.visible
                     && Contract.NSRunningApplication.terminated.isEmpty,
                     "reverse Command-Tab cancels an existing hold before its timer can quit the foreground app")
        send(12, .keyUp)
        send(55, .flagsChanged, flags: [])

        // Both Escape and Command-period dismiss the native switcher even
        // while Command stays down. Every mode must protect the next quit.
        for mode in QuitProtectionMode.allCases {
            defaults.set(mode.rawValue, forKey: DefaultsKey.quitProtectionQuitMode)
            for dismissKey: CGKeyCode in [53, 47] {
                send(48)
                suite.expect(send(dismissKey) && !send(12) && service.pending != nil,
                             "dismissal key \(dismissKey) restores \(mode.rawValue) protection while Command stays held")
                send(12, .keyUp)
                send(55, .flagsChanged, flags: [])
                suite.expect(!service.hud.visible, "cancelling an unconfirmed press still hides its HUD")
            }
        }
        defaults.set("hold", forKey: DefaultsKey.quitProtectionQuitMode)

        // Command-period follows the active keyboard layout, not the US
        // period key's physical position.
        Contract.GlobalShortcut.keyLabels[47] = ";"
        Contract.GlobalShortcut.keyLabels[44] = "."
        send(48)
        suite.expect(send(47) && send(12) && service.pending == nil,
                     "a physical period key with another label keeps native switcher ownership")
        suite.expect(send(44) && !send(12) && service.pending != nil,
                     "the layout's Command-period restores ordinary protection")
        send(12, .keyUp)
        Contract.GlobalShortcut.keyLabels[47] = "."
        Contract.GlobalShortcut.keyLabels[44] = nil

        // Modified Tab shortcuts that do not open the native switcher must
        // leave ordinary protection available.
        for flags: CGEventFlags in [[.maskCommand, .maskAlternate], [.maskCommand, .maskControl]] {
            send(48, flags: flags)
            suite.expect(!send(12) && service.pending != nil,
                         "a non-switcher modified Tab does not bypass quit protection")
            send(12, .keyUp)
        }

        // A key event without Command also ends the chord if its modifier
        // release event was missed.
        send(48)
        send(48, .keyUp, flags: [])
        suite.expect(!send(12), "a later event with Command released ends native switcher ownership")
        send(12, .keyUp)

        // Custom switcher ownership remains authoritative in either tap order.
        send(48)
        Contract.AppSwitcher.shared.keyboardInputOwnership = (true, 1)
        suite.expect(send(12) && service.pending == nil, "the custom switcher still receives its selection keys")
        Contract.AppSwitcher.shared.keyboardInputOwnership = (false, 1)
        suite.expect(!send(12), "a custom switcher session does not leave stale native ownership")
        send(12, .keyUp)

        // A click on a native switcher icon ends the session with Command
        // still held. The app it activates must be protected again.
        send(48)
        service.applicationDidActivate(Contract.NSRunningApplication(processIdentifier: 200)!)
        suite.expect(!send(12) && service.pending != nil,
                     "an app activated while Command stays held ends native switcher ownership")
        send(12, .keyUp)
        send(55, .flagsChanged, flags: [])
        service.frontmostProcessIdentifier = 100

        send(48)
        service.stop()
        service.isRunning = true
        suite.expect(!send(12), "stopping the service clears native switcher ownership before a restart")
        send(12, .keyUp)
    }
}
