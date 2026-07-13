// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit

/// Everything the quick toggles tab can do. Raw values are storage ids for
/// the user's order and the per-item visibility keys.
enum QuickToggleAction: String, PanelOrderItem, Identifiable {
    // Case order is the default panel order: the appearance switch leads
    // because it is the tab's headline action (issue request).
    case darkMode, emptyTrash, ejectDisks, hiddenFiles, desktopIcons,
         lockScreen, displayOff, screenSaver

    var id: String { rawValue }
}

/// One-click system actions, all on demand: nothing runs, observes or polls
/// while the panel is closed. Each action reports a short-lived state so the
/// row can show progress and the outcome.
final class QuickTogglesService: ObservableObject {
    static let shared = QuickTogglesService()

    enum RunState: Equatable {
        case running, failed
        /// The action needs an Automation consent the user declined; the row
        /// turns into a permission prompt until the grant shows up.
        case needsPermission
    }

    @Published private(set) var states: [QuickToggleAction: RunState] = [:]

    private let workQueue = DispatchQueue(label: "com.vorssaint.utils.quick-toggles", qos: .userInitiated)

    private init() {}

    func state(for action: QuickToggleAction) -> RunState? {
        states[action]
    }

    // MARK: - Current system state (read on demand, never observed)

    var hiddenFilesShown: Bool {
        finderFlag(QuickTogglesSupport.showAllFilesKey, default: false)
    }

    var desktopIconsShown: Bool {
        finderFlag(QuickTogglesSupport.createDesktopKey, default: true)
    }

    func ejectableVolumeCount() -> Int {
        Self.ejectableVolumeURLs().count
    }

    // MARK: - Appearance (issue #205)

    /// Flips the system between light and dark mode through the WindowServer,
    /// the same switch System Settings flips: instant, system wide and with
    /// no Automation consent involved. The symbol is resolved lazily and
    /// guarded; without it the row reports the failure instead of crashing.
    func toggleDarkMode() {
        guard available, beginRun(.darkMode) else { return }
        guard let theme = Self.appearanceTheme else {
            finishRun(.darkMode, state: .failed)
            return
        }
        theme.set(!theme.get())
        finishRun(.darkMode, state: nil)
    }

    // MARK: - Trash

    /// Asks first (emptying is permanent), then tells the Finder to empty
    /// the Trash. Runs on the main thread up to the confirmation; the Apple
    /// Event goes to the work queue.
    func emptyTrash() {
        guard available, states[.emptyTrash] != .running else { return }
        let strings = FeatureStrings.quickToggles(L10n.shared.language)
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = strings.emptyTrashConfirmTitle
        alert.informativeText = strings.emptyTrashConfirmMessage
        alert.addButton(withTitle: strings.emptyTrashConfirmButton)
        alert.addButton(withTitle: L10n.shared.s.uninstallerCancel)
        NSApp.activate(ignoringOtherApps: true)
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        runAppleScript(.emptyTrash,
                       target: .finder,
                       source: QuickTogglesSupport.emptyTrashSource)
    }

    // MARK: - Finder flags

    /// Writes the Finder preference and restarts the Finder to apply it;
    /// launchd brings it right back with the new value in effect.
    func toggleHiddenFiles() {
        toggleFinderFlag(.hiddenFiles,
                         key: QuickTogglesSupport.showAllFilesKey,
                         to: !hiddenFilesShown)
    }

    func toggleDesktopIcons() {
        toggleFinderFlag(.desktopIcons,
                         key: QuickTogglesSupport.createDesktopKey,
                         to: !desktopIconsShown)
    }

    // MARK: - Disks

    /// Safely ejects every external volume, the on-demand cousin of the disk
    /// monitor's "Eject all". Enumerated fresh on each click, so the action
    /// never keeps a disk list alive.
    func ejectAllDisks() {
        guard available, beginRun(.ejectDisks) else { return }
        workQueue.async {
            let volumes = Self.ejectableVolumeURLs()
            guard !volumes.isEmpty else {
                self.finishRun(.ejectDisks, state: nil)
                return
            }
            var failures = 0
            for url in volumes {
                do {
                    try NSWorkspace.shared.unmountAndEjectDevice(at: url)
                } catch {
                    failures += 1
                }
            }
            self.finishRun(.ejectDisks, state: failures == 0 ? nil : .failed)
        }
    }

    // MARK: - Screen

    /// The same immediate lock as the system's own shortcut. The symbol is
    /// resolved lazily and guarded; when it is unavailable the screen saver
    /// path stands in (with a password required, it locks too).
    func lockScreen() {
        guard available else { return }
        if let lock = Self.lockScreenFunction {
            _ = lock()
        } else {
            startScreenSaver()
        }
    }

    func turnDisplayOff() {
        guard available, beginRun(.displayOff) else { return }
        workQueue.async {
            let result = Shell.run("/usr/bin/pmset", ["displaysleepnow"])
            self.finishRun(.displayOff, state: result.status == 0 ? nil : .failed)
        }
    }

    func startScreenSaver() {
        guard available else { return }
        let url = URL(fileURLWithPath: "/System/Library/CoreServices/ScreenSaverEngine.app")
        NSWorkspace.shared.openApplication(at: url,
                                           configuration: NSWorkspace.OpenConfiguration())
    }

    // MARK: - Permission refresh

    /// Clears a stale "needs permission" mark once the grant shows up in
    /// System Settings, so the row goes back to being clickable. Called when
    /// the list appears; checked off the main thread (the AE check blocks).
    func refreshPermissionStates() {
        let marked = states.filter { $0.value == .needsPermission }.map(\.key)
        guard !marked.isEmpty else { return }
        workQueue.async {
            for action in marked {
                guard let target = Self.automationTarget(for: action) else { continue }
                if Permissions.automationStatus(for: target) == .granted {
                    DispatchQueue.main.async {
                        if self.states[action] == .needsPermission {
                            self.states[action] = nil
                        }
                    }
                }
            }
        }
    }

    // MARK: - Internals

    private var available: Bool {
        AppFeature.quickToggles.isAvailable
    }

    private static func automationTarget(for action: QuickToggleAction) -> Permissions.AutomationTarget? {
        switch action {
        case .emptyTrash: return .finder
        default: return nil
        }
    }

    private func runAppleScript(_ action: QuickToggleAction,
                                target: Permissions.AutomationTarget,
                                source: String) {
        guard available, beginRun(action) else { return }
        workQueue.async {
            // Denied consent never re-prompts by itself: surface the grant
            // button instead of a silent failure. Undetermined runs straight
            // into the script, which is what triggers the system prompt.
            if Permissions.automationStatus(for: target) == .denied {
                self.finishRun(action, state: .needsPermission, resets: false)
                return
            }
            let result = AppleScriptRunner.runDetailed(source)
            if result.ok {
                self.finishRun(action, state: nil)
            } else if QuickTogglesSupport.isPermissionError(result.errorNumber) {
                self.finishRun(action, state: .needsPermission, resets: false)
            } else {
                self.finishRun(action, state: .failed)
            }
        }
    }

    private func toggleFinderFlag(_ action: QuickToggleAction, key: String, to value: Bool) {
        guard available, beginRun(action) else { return }
        workQueue.async {
            CFPreferencesSetAppValue(key as CFString,
                                     value as CFBoolean,
                                     QuickTogglesSupport.finderDomain as CFString)
            CFPreferencesAppSynchronize(QuickTogglesSupport.finderDomain as CFString)
            self.finishRun(action, state: self.restartFinder() ? nil : .failed)
        }
    }

    /// The Finder only reads these preferences at launch, so it has to
    /// restart. When the Finder Automation grant is already in (the Trash
    /// and cut and paste share it), the restart is polite: a regular quit
    /// followed by our own relaunch, which keeps launchd out of it and
    /// avoids its "running in background" churn. Without the grant, or when
    /// the Finder will not quit (an operation in progress), the classic
    /// killall does it; never prompts either way. Work-queue only: the exit
    /// poll blocks.
    private func restartFinder() -> Bool {
        if Permissions.automationStatus(for: .finder) == .granted,
           AppleScriptRunner.runDetailed(QuickTogglesSupport.quitFinderSource).ok,
           waitForFinderExit() {
            let url = URL(fileURLWithPath: "/System/Library/CoreServices/Finder.app")
            let configuration = NSWorkspace.OpenConfiguration()
            configuration.activates = false
            NSWorkspace.shared.openApplication(at: url, configuration: configuration)
            return true
        }
        return Shell.run("/usr/bin/killall", ["Finder"]).status == 0
    }

    /// A quit Finder stays quit (nothing relaunches it), so the poll only
    /// confirms the exit before the relaunch; a Finder that is still around
    /// after the timeout is busy and falls back to killall.
    private func waitForFinderExit() -> Bool {
        for _ in 0..<30 {
            if Shell.run("/usr/bin/pgrep", ["-x", "Finder"]).status != 0 {
                return true
            }
            usleep(100_000)
        }
        return false
    }

    /// Marks the action as running; a second click while it runs is ignored.
    private func beginRun(_ action: QuickToggleAction) -> Bool {
        guard states[action] != .running else { return false }
        setState(action, .running)
        return true
    }

    /// Success clears the state right away (the row itself is the feedback,
    /// no caption flash); a failure shows briefly, a permission mark stays.
    private func finishRun(_ action: QuickToggleAction, state: RunState?, resets: Bool = true) {
        setState(action, state)
        guard state != nil, resets else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.4) { [weak self] in
            guard let self, self.states[action] == state else { return }
            self.states[action] = nil
        }
    }

    /// Applies synchronously on the main thread so beginRun's double-click
    /// guard reads the value it just wrote.
    private func setState(_ action: QuickToggleAction, _ state: RunState?) {
        if Thread.isMainThread {
            states[action] = state
        } else {
            DispatchQueue.main.async {
                self.states[action] = state
            }
        }
    }

    private func finderFlag(_ key: String, default defaultValue: Bool) -> Bool {
        let value = CFPreferencesCopyAppValue(key as CFString,
                                              QuickTogglesSupport.finderDomain as CFString)
        return QuickTogglesSupport.finderFlag(value, default: defaultValue)
    }

    private static func ejectableVolumeURLs() -> [URL] {
        let keys: Set<URLResourceKey> = [
            .volumeIsInternalKey, .volumeIsRemovableKey,
            .volumeIsEjectableKey, .volumeIsLocalKey,
        ]
        guard let urls = FileManager.default.mountedVolumeURLs(
            includingResourceValuesForKeys: Array(keys),
            options: [.skipHiddenVolumes]) else { return [] }
        return urls.filter { url in
            guard let values = try? url.resourceValues(forKeys: keys) else { return false }
            return QuickTogglesSupport.shouldOfferEject(isInternal: values.volumeIsInternal ?? false,
                                                        isRemovable: values.volumeIsRemovable ?? false,
                                                        isEjectable: values.volumeIsEjectable ?? false,
                                                        isLocal: values.volumeIsLocal ?? false)
        }
    }

    /// SACLockScreenImmediate from the login framework, resolved once and
    /// guarded: a missing symbol just means the screen saver fallback.
    private static let lockScreenFunction: (@convention(c) () -> Int32)? = {
        let path = "/System/Library/PrivateFrameworks/login.framework/login"
        guard let handle = dlopen(path, RTLD_LAZY),
              let symbol = dlsym(handle, "SACLockScreenImmediate") else { return nil }
        return unsafeBitCast(symbol, to: (@convention(c) () -> Int32).self)
    }()

    private typealias AppearanceGet = @convention(c) () -> Bool
    private typealias AppearanceSet = @convention(c) (Bool) -> Void

    /// The WindowServer's appearance switch (SkyLight), resolved once and
    /// guarded like the lock above. Stable across many macOS releases; if it
    /// ever leaves, toggleDarkMode degrades to a visible failure.
    private static let appearanceTheme: (get: AppearanceGet, set: AppearanceSet)? = {
        let path = "/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight"
        guard let handle = dlopen(path, RTLD_LAZY),
              let getSymbol = dlsym(handle, "SLSGetAppearanceThemeLegacy"),
              let setSymbol = dlsym(handle, "SLSSetAppearanceThemeLegacy") else { return nil }
        return (unsafeBitCast(getSymbol, to: AppearanceGet.self),
                unsafeBitCast(setSymbol, to: AppearanceSet.self))
    }()
}
