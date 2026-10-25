// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import CoreGraphics

/// Runs the actions a radial-menu slice or a trackpad gesture is mapped to,
/// so both offer the same catalog with the same effect. Main thread.
enum TriggerActionRunner {
    /// What the caller knows about where and how the action was asked for.
    struct Context {
        /// Where a card the action presents (the now-playing details) appears,
        /// in the same screen coordinates the radial wheel uses.
        var anchor: CGPoint
        /// Answers whether Accessibility is granted, asking for it in context
        /// when it is not. Actions that post keys or move windows need it.
        var ensureAccessibility: () -> Bool
        /// Whether a keyboard chord may still be held when the action runs,
        /// as with a wheel summoned by a shortcut. A trackpad gesture involves
        /// no keys, and waiting there holds every quick second gesture back:
        /// the shortcut the first one posted stays on the session's modifier
        /// record for a second or more.
        var waitsForModifierRelease = true
    }

    static func run(_ action: TriggerAction, context: Context) {
        switch action {
        case .item(let item): run(item, context: context)
        case .navigation(let navigation): run(navigation, context: context)
        case .backForward(let direction):
            guard context.ensureAccessibility() else { return }
            MouseNavigationService.shared.navigate(direction)
        }
    }

    /// The system shortcut a navigation replays, or nil when the user switched
    /// it off in System Settings and there is nothing to press.
    static func systemShortcut(for navigation: SpaceNavigation) -> SpaceWindowBridge.SpaceShortcut? {
        switch navigation {
        case .spaceLeft: return SpaceWindowBridge.spaceShortcut(.left)
        case .spaceRight: return SpaceWindowBridge.spaceShortcut(.right)
        case .missionControl: return SpaceWindowBridge.overviewShortcut(.missionControl)
        case .appExpose: return SpaceWindowBridge.overviewShortcut(.appExpose)
        }
    }

    /// Why a saved action cannot run right now, read from the live app. It is
    /// what Settings shows under a gesture, and why that gesture stays quiet
    /// instead of failing out loud: macOS answers a missing application with
    /// an alert of its own.
    static func unavailability(_ action: TriggerAction) -> TriggerActionUnavailability? {
        TrackpadGestureMappingSupport.unavailability(
            action,
            isFeatureAvailable: { $0.isAvailable },
            boolFor: { UserDefaults.standard.bool(forKey: $0) },
            fileExists: { FileManager.default.fileExists(atPath: $0) },
            systemShortcutExists: { systemShortcut(for: $0) != nil })
    }

    /// Spaces and overviews open the way the keyboard opens them: the window
    /// server refuses simulated touch gestures (issue #1012).
    static func run(_ navigation: SpaceNavigation, context: Context) {
        guard let shortcut = systemShortcut(for: navigation) else {
            NSSound.beep()
            return
        }
        postWhenModifiersReleased(attempt: 0, context: context) {
            SpaceWindowBridge.pressSpaceShortcut(shortcut)
        }
    }

    static func run(_ item: RadialMenuItem, context: Context) {
        switch item.kind {
        case .app:
            let url = URL(fileURLWithPath: (item.payload as NSString).expandingTildeInPath)
            NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration()) { _, error in
                if error != nil { DispatchQueue.main.async { NSSound.beep() } }
            }
        case .file:
            let path = (item.payload as NSString).expandingTildeInPath
            guard FileManager.default.fileExists(atPath: path) else {
                NSSound.beep()
                return
            }
            NSWorkspace.shared.open(URL(fileURLWithPath: path))
        case .url:
            if let normalized = RadialMenuSupport.normalizedURL(item.payload),
               let url = URL(string: normalized) {
                NSWorkspace.shared.open(url)
            }
        case .shortcut:
            if let shortcut = GlobalShortcut(storageValue: item.payload) {
                postWhenModifiersReleased(attempt: 0, context: context) { postShortcut(shortcut) }
            }
        case .media:
            if let key = item.mediaKey {
                if key == .nowPlaying {
                    RadialNowPlayingService.shared.presentDetails(at: context.anchor)
                } else {
                    postWhenModifiersReleased(attempt: 0, context: context) { postMediaKey(key) }
                }
            }
        case .tool:
            if let tool = item.tool { run(tool) }
        case .quickToggle:
            if let action = item.quickToggle { run(action) }
        case .windowLayout:
            if let action = item.windowLayoutAction { run(action, context: context) }
        case .submenu:
            break
        }
    }

    static func run(_ tool: RadialMenuTool) {
        guard tool.isRunnable() else { return }
        // The same beat the quick panel gives screen-touching tools, so the
        // wheel is really gone before anything captures or presents.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            switch tool {
            case .screenshot: ScreenshotService.shared.capture()
            case .screenRecorder: ScreenRecorderService.shared.toggle()
            case .colorPicker: ColorSamplerService.shared.pick()
            case .screenOCR: ScreenTextService.shared.capture()
            case .micMute: MicMuteService.shared.toggle()
            case .clipboardHistory: ClipboardHistoryService.shared.showHistoryWindow()
            case .quickLauncher: QuickLauncherService.shared.show()
            case .cameraPreview: CameraPreviewService.shared.show()
            case .scratchpad: ScratchpadService.shared.show()
            case .shelf: ShelfService.shared.summon()
            case .cleaner: openSettings(at: .cleaner)
            case .uninstaller: openSettings(at: .uninstaller)
            case .appUpdates:
                AppUpdatesService.shared.check()
                openSettings(at: .appUpdates)
            case .cleaningMode: CleaningModeManager.shared.activate()
            case .keepAwake: KeepAwakeManager.shared.toggle()
            case .commandBar: CommandBarService.shared.toggle()
            }
        }
    }

    private static func openSettings(at page: SettingsPage) {
        SettingsRouter.shared.page = page
        appDelegate()?.openSettingsWindow()
    }

    static func run(_ action: RadialMenuQuickToggle) {
        guard AppFeature.quickToggles.isAvailable else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            let toggles = QuickTogglesService.shared
            switch action {
            case .darkMode: toggles.toggleDarkMode()
            case .emptyTrash: toggles.emptyTrash()
            case .ejectDisks: toggles.ejectAllDisks()
            case .hiddenFiles: toggles.toggleHiddenFiles()
            case .desktopIcons: toggles.toggleDesktopIcons()
            case .lockScreen: toggles.lockScreen()
            case .displayOff: toggles.turnDisplayOff()
            case .screenSaver: toggles.startScreenSaver()
            }
        }
    }

    static func run(_ action: WindowLayoutAction, context: Context) {
        guard AppFeature.windowLayout.isAvailable, context.ensureAccessibility() else { return }
        // Let the non-activating wheel disappear before resolving the window
        // that was active behind it, matching the delay used by visual tools.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            if case .failure = WindowLayoutService.shared.apply(action) { NSSound.beep() }
        }
    }

    /// Waits for the summoning chord to leave the keyboard before posting, or
    /// the synthetic key merges with the still-held modifiers (checked every
    /// 15 ms for up to ~1.5 s, with an extra beat once clean).
    static func postWhenModifiersReleased(attempt: Int, context: Context,
                                          then post: @escaping () -> Void) {
        guard context.ensureAccessibility() else { return }
        let held = context.waitsForModifierRelease
            ? CGEventSource.flagsState(.combinedSessionState)
                .intersection([.maskCommand, .maskAlternate, .maskShift, .maskControl])
            : []
        if held.isEmpty || attempt >= 100 {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.06, execute: post)
            return
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.015) {
            postWhenModifiersReleased(attempt: attempt + 1, context: context, then: post)
        }
    }

    static func postShortcut(_ shortcut: GlobalShortcut) {
        guard let keyDown = CGEvent(keyboardEventSource: nil,
                                    virtualKey: CGKeyCode(shortcut.keyCode), keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: nil,
                                  virtualKey: CGKeyCode(shortcut.keyCode), keyDown: false)
        else { return }
        // The flags a real press carries, so a shortcut on an arrow or an F
        // key is recognised beyond the app in front as well (issue #401).
        keyDown.flags = shortcut.syntheticEventFlags
        keyUp.flags = shortcut.syntheticEventFlags
        keyDown.post(tap: .cghidEventTap)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.04) {
            keyUp.post(tap: .cghidEventTap)
        }
    }

    /// Posts the aux-button pair the physical media keys produce, so whatever
    /// player owns the media keys reacts exactly as if F8 was pressed.
    static func postMediaKey(_ key: RadialMenuMediaKey) {
        guard let auxKeyType = key.auxKeyType else { return }
        postAuxKey(auxKeyType, down: true)
        postAuxKey(auxKeyType, down: false)
    }

    private static func postAuxKey(_ type: Int32, down: Bool) {
        let stateFlags: NSEvent.ModifierFlags = down
            ? NSEvent.ModifierFlags(rawValue: 0xA00)
            : NSEvent.ModifierFlags(rawValue: 0xB00)
        let data1 = (Int(type) << 16) | ((down ? 0xA : 0xB) << 8)
        guard let event = NSEvent.otherEvent(with: .systemDefined,
                                             location: .zero,
                                             modifierFlags: stateFlags,
                                             timestamp: ProcessInfo.processInfo.systemUptime,
                                             windowNumber: 0,
                                             context: nil,
                                             subtype: 8,
                                             data1: data1,
                                             data2: -1)
        else { return }
        event.cgEvent?.post(tap: .cghidEventTap)
    }
}
