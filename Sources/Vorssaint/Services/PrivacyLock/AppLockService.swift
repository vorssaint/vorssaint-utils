// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint
//
// Derived from Glance's LockedAppsManager (MIT, Copyright (c) Jonathan Zhou). See THIRD-PARTY-NOTICES.md.

import AppKit
import Combine
import SwiftUI

/// What the shield shows, read by its view.
@MainActor
final class AppLockShieldState: ObservableObject {
    @Published var appName = ""
    @Published var appIcon: NSImage?
    @Published var method: AppLockMethod = .biometric
    @Published var isAuthenticating = false
    @Published var errorMessage: String?
    @Published var isScanningFace = false
}

enum AppLockSupport {
    static func lockedBundleIDs(in defaults: UserDefaults = .standard) -> [String] {
        PrivacyLockSupport.lockedBundleIDs(from: defaults.string(forKey: DefaultsKey.appLockedApps),
                                           ownBundleID: Bundle.main.bundleIdentifier)
    }

    static func isActive(in defaults: UserDefaults = .standard) -> Bool {
        AppFeature.privacyLock.isAvailable(in: defaults)
            && defaults.bool(forKey: DefaultsKey.privacyLockEnabled)
            && defaults.bool(forKey: DefaultsKey.appLockEnabled)
            && !lockedBundleIDs(in: defaults).isEmpty
    }
}

/// Puts a shield over chosen apps until the person proves it is them.
///
/// When a locked app launches or comes to the front, its windows are hidden,
/// every display is covered and Touch ID (or the app lock's own password) is
/// asked for. On success the shield drops and the app returns.
///
/// This keeps people away from an app on a Mac that was left unlocked. It is
/// not a sandbox: the locked app's process keeps running, and Vorssaint has to
/// be running to enforce it.
@MainActor
final class AppLockService {
    static let shared = AppLockService()

    private var unlocked: Set<String> = []
    private var leftAt: [String: Date] = [:]
    private var lastFrontmostID: String?
    private var shields: [ShieldWindow] = []
    private var shieldedBundleID: String?
    private let state = AppLockShieldState()
    private var observers: [NSObjectProtocol] = []
    private var distributedObserver: NSObjectProtocol?
    private var failures = 0
    private var lockedUntil: Date?
    private var isRunning = false

    private init() {}

    // MARK: - Lifecycle

    func syncWithPreferences() {
        if AppLockSupport.isActive() { start() } else { stop() }
        settingsDidChange()
    }

    private func start() {
        guard !isRunning else { return }
        isRunning = true
        let center = NSWorkspace.shared.notificationCenter
        observers.append(center.addObserver(forName: NSWorkspace.didLaunchApplicationNotification,
                                            object: nil, queue: .main) { [weak self] note in
            let running = Self.runningApp(note)
            Task { @MainActor in if let running { self?.gate(running, isActivation: false) } }
        })
        observers.append(center.addObserver(forName: NSWorkspace.didActivateApplicationNotification,
                                            object: nil, queue: .main) { [weak self] note in
            let running = Self.runningApp(note)
            Task { @MainActor in if let running { self?.gate(running, isActivation: true) } }
        })
        observers.append(center.addObserver(forName: NSWorkspace.didTerminateApplicationNotification,
                                            object: nil, queue: .main) { [weak self] note in
            let id = Self.runningApp(note)?.bundleIdentifier
            Task { @MainActor in if let id { self?.appDidQuit(id) } }
        })
        // Sleep or a locked screen always locks everything again.
        for name in [NSWorkspace.willSleepNotification, NSWorkspace.screensDidSleepNotification] {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.relockAll() }
            })
        }
        distributedObserver = DistributedNotificationCenter.default().addObserver(
            forName: Notification.Name("com.apple.screenIsLocked"), object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.relockAll() }
        }
        if let front = NSWorkspace.shared.frontmostApplication { gate(front, isActivation: true) }
    }

    private nonisolated static func runningApp(_ note: Notification) -> NSRunningApplication? {
        note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
    }

    private func stop() {
        guard isRunning else { return }
        isRunning = false
        let center = NSWorkspace.shared.notificationCenter
        observers.forEach(center.removeObserver)
        observers = []
        if let distributedObserver { DistributedNotificationCenter.default().removeObserver(distributedObserver) }
        distributedObserver = nil
        dismissShield()
        relockAll()
    }

    // MARK: - From Finder and Settings

    /// Adds apps to the lock list; locking needs no proof. Turns the app lock
    /// on, since asking to lock an app means wanting it locked.
    func lock(appsAt urls: [URL]) {
        let defaults = UserDefaults.standard
        var ids = AppLockSupport.lockedBundleIDs(in: defaults)
        var added = 0
        for url in urls {
            guard let id = Bundle(url: url)?.bundleIdentifier,
                  PrivacyLockSupport.canLock(bundleID: id, ownBundleID: Bundle.main.bundleIdentifier),
                  !ids.contains(id) else { continue }
            ids.append(id)
            added += 1
        }
        guard added > 0 else { return }
        defaults.set(PrivacyLockSupport.storedValue(for: ids), forKey: DefaultsKey.appLockedApps)
        defaults.set(true, forKey: DefaultsKey.appLockEnabled)
        syncWithPreferences()
        NSSound(named: "Pop")?.play()
    }

    /// Locks the apps that are open and, after proof, unlocks the ones already locked.
    func toggle(appsAt urls: [URL]) async {
        let locked = Set(AppLockSupport.lockedBundleIDs())
        var toLock: [URL] = []
        var toUnlock: [URL] = []
        for url in urls {
            guard let id = Bundle(url: url)?.bundleIdentifier else { continue }
            if locked.contains(id) { toUnlock.append(url) } else { toLock.append(url) }
        }
        if !toLock.isEmpty { lock(appsAt: toLock) }
        if !toUnlock.isEmpty { await unlock(appsAt: toUnlock) }
    }

    /// Takes apps off the lock list after the same proof that opens them.
    func unlock(appsAt urls: [URL]) async {
        let ids = Set(urls.compactMap { Bundle(url: $0)?.bundleIdentifier })
        await removeLock(forBundleIDs: ids)
    }

    func removeLock(forBundleIDs removed: Set<String>) async {
        let defaults = UserDefaults.standard
        let current = AppLockSupport.lockedBundleIDs(in: defaults)
        guard !removed.isDisjoint(with: current) else { return }
        guard await Self.authorize() else { return }
        defaults.set(PrivacyLockSupport.storedValue(for: current.filter { !removed.contains($0) }),
                     forKey: DefaultsKey.appLockedApps)
        syncWithPreferences()
        NSSound(named: "Pop")?.play()
    }

    /// The proof that weakening a lock needs: the lock's own password when that
    /// is the chosen method, else Touch ID or the Mac password. Nothing to
    /// prove while no app is locked.
    static func authorize() async -> Bool {
        let text = FeatureStrings.privacyLock(L10n.shared.language)
        guard AppLockSupport.isActive() else { return true }
        if method == .password {
            var wrong = false
            while true {
                guard let password = PrivacyLockPrompts.askPassword(itemName: text.appLockTitle, wrong: wrong) else {
                    return false
                }
                if await Task.detached(priority: .userInitiated, operation: {
                    PrivacyLockKeychain.verifyAppLockPassword(password)
                }).value { return true }
                wrong = true
            }
        }
        do {
            try await PrivacyLockAuthenticator.authenticate(
                reason: String(format: text.shieldReasonFormat, text.title), allowPassword: true)
            return true
        } catch {
            return false
        }
    }

    /// The list or a switch changed: a shield for an app no longer locked goes.
    func settingsDidChange() {
        guard let id = shieldedBundleID else { return }
        if !AppLockSupport.isActive() || !AppLockSupport.lockedBundleIDs().contains(id) { dismissShield() }
    }

    // MARK: - Gating

    private func gate(_ app: NSRunningApplication, isActivation: Bool) {
        guard app.processIdentifier != ProcessInfo.processInfo.processIdentifier,
              let id = app.bundleIdentifier else { return }
        if isActivation {
            if let previous = lastFrontmostID, previous != id { leftAt[previous] = Date() }
            lastFrontmostID = id
            // Moving to another app abandons a pending shield; the locked app stays hidden.
            if let shielded = shieldedBundleID, shielded != id { dismissShield() }
        }
        guard AppLockSupport.lockedBundleIDs().contains(id), !isCurrentlyUnlocked(id) else { return }
        presentShield(for: app, bundleID: id)
    }

    private func isCurrentlyUnlocked(_ id: String) -> Bool {
        guard unlocked.contains(id) else { return false }
        let relock = AppLockRelock.sanitized(UserDefaults.standard.string(forKey: DefaultsKey.appLockRelock))
        guard let seconds = relock.seconds else { return true }
        if let left = leftAt[id], Date().timeIntervalSince(left) >= seconds {
            unlocked.remove(id)
            return false
        }
        return true
    }

    private func appDidQuit(_ id: String) {
        unlocked.remove(id)
        leftAt[id] = nil
        if lastFrontmostID == id { lastFrontmostID = nil }
        if shieldedBundleID == id { dismissShield() }
    }

    private func relockAll() {
        unlocked.removeAll()
        leftAt.removeAll()
    }

    // MARK: - Shield

    private func presentShield(for app: NSRunningApplication, bundleID: String) {
        guard shieldedBundleID != bundleID else { return }
        dismissShield()
        shieldedBundleID = bundleID
        state.appName = app.localizedName ?? bundleID
        state.appIcon = app.icon
        state.method = Self.method
        state.errorMessage = nil
        state.isAuthenticating = false

        // Cover first, hide second: the app's windows are never the last thing on screen.
        for screen in NSScreen.screens {
            let window = ShieldWindow(screen: screen, content: AppLockShieldView(
                state: state,
                unlockWithTouchID: { [weak self] in self?.authenticateBiometric(bundleID: bundleID) },
                unlockWithPassword: { [weak self] password in self?.verify(password, bundleID: bundleID) },
                dismiss: { [weak self] in self?.dismissShield() }))
            window.orderFrontRegardless()
            shields.append(window)
        }
        app.hide()
        NSApp.activate(ignoringOtherApps: true)
        shields.first?.makeKey()
        if state.method == .biometric { authenticateBiometric(bundleID: bundleID) }
    }

    private static var method: AppLockMethod {
        // A password method with no password set cannot be answered; Touch ID stands in.
        let chosen = AppLockMethod.sanitized(UserDefaults.standard.string(forKey: DefaultsKey.appLockMethod))
        return chosen == .password && !PrivacyLockKeychain.hasAppLockPassword ? .biometric : chosen
    }

    private func dismissShield() {
        FaceUnlockService.shared.cancelVerify()
        state.isScanningFace = false
        for window in shields { window.orderOut(nil) }
        shields.removeAll()
        shieldedBundleID = nil
    }

    private func authenticateBiometric(bundleID: String) {
        guard !state.isAuthenticating, shieldedBundleID == bundleID else { return }
        state.isAuthenticating = true
        state.errorMessage = nil
        let reason = String(format: FeatureStrings.privacyLock(L10n.shared.language).shieldReasonFormat, state.appName)
        Task {
            defer { state.isAuthenticating = false; state.isScanningFace = false }
            // A face that matches opens it; otherwise Touch ID or the Mac password asks.
            if UserDefaults.standard.bool(forKey: DefaultsKey.appLockUseFace), FaceUnlockService.shared.canVerifyFace() {
                state.isScanningFace = true
                let seen = await FaceUnlockService.shared.verifyFace()
                state.isScanningFace = false
                guard shieldedBundleID == bundleID else { return }
                if seen { grant(bundleID); return }
            }
            do {
                try await PrivacyLockAuthenticator.authenticate(reason: reason, allowPassword: true)
                grant(bundleID)
            } catch PrivacyLockAuthError.cancelled {
                // The shield stays, with its button.
            } catch {
                state.errorMessage = error.localizedDescription
            }
        }
    }

    private func verify(_ password: String, bundleID: String) {
        guard shieldedBundleID == bundleID, !password.isEmpty else { return }
        let text = FeatureStrings.privacyLock(L10n.shared.language)
        if let until = lockedUntil, until > Date() {
            state.errorMessage = String(format: text.shieldWaitFormat, Int(until.timeIntervalSinceNow.rounded(.up)))
            return
        }
        state.isAuthenticating = true
        Task {
            // The hash takes a moment on purpose; keep it off the main thread.
            let correct = await Task.detached(priority: .userInitiated) {
                PrivacyLockKeychain.verifyAppLockPassword(password)
            }.value
            state.isAuthenticating = false
            guard shieldedBundleID == bundleID else { return }
            if correct {
                failures = 0
                lockedUntil = nil
                grant(bundleID)
            } else {
                failures += 1
                let wait = PrivacyLockSupport.lockoutSeconds(afterFailures: failures)
                if wait > 0 { lockedUntil = Date().addingTimeInterval(wait) }
                state.errorMessage = wait > 0
                    ? String(format: text.shieldWaitFormat, Int(wait))
                    : text.shieldWrongPassword
            }
        }
    }

    private func grant(_ bundleID: String) {
        guard shieldedBundleID == bundleID else { return }
        unlocked.insert(bundleID)
        leftAt[bundleID] = nil
        dismissShield()
        if let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first {
            app.unhide()
            app.activate()
        }
    }
}

private final class ShieldWindow: NSWindow {
    init<Content: View>(screen: NSScreen, content: Content) {
        super.init(contentRect: screen.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        level = .screenSaver
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        isReleasedWhenClosed = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        contentView = NSHostingView(rootView: content)
        setFrame(screen.frame, display: true)
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}
