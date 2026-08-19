// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import Foundation

/// Wipes the system pasteboard on four independent, opt-in triggers: a delay
/// after the last copy, computer sleep, display sleep, and screen lock.
/// Independent of clipboard history: someone who keeps no history at all is
/// exactly the person who wants a copied password gone.
///
/// Saved history entries are never touched, only the pasteboard.
final class ClipboardAutoClearService {
    static let shared = ClipboardAutoClearService()

    private var timer: Timer?
    /// The change count last acted on, and when it first appeared. The date is
    /// wall clock rather than a count of ticks: timers do not fire while the
    /// Mac sleeps, so a machine asleep past the delay clears on the first tick
    /// after waking instead of starting the wait over.
    private var lastChangeCount = 0
    private var lastChangeDate = Date()
    /// The count our own clear produced, so a clear is never mistaken for a copy.
    private var lastClearedChangeCount = -1
    /// Only ever one read in flight, mirroring the history poll: while a
    /// password prompt holds the pasteboard server a read can take seconds, and
    /// letting ticks pile up would spawn a thread each time.
    private var readInFlight = false
    /// Each read carries a token, so one that wedged behind a password prompt
    /// can be abandoned without a stale completion ever landing.
    private var readGeneration = 0
    private let configurationLock = NSLock()
    private var configurationGeneration = 0

    private var sleepObserver: NSObjectProtocol?
    private var displaySleepObserver: NSObjectProtocol?
    private var screenLockObserver: NSObjectProtocol?
    /// The app is not sandboxed, so the lock notification is delivered. There is
    /// no AppKit constant for it.
    private static let screenLockNotification = Notification.Name("com.apple.screenIsLocked")

    private init() {}

    func syncWithPreferences() {
        configurationLock.lock()
        configurationGeneration &+= 1
        configurationLock.unlock()
        let defaults = UserDefaults.standard
        let isAvailable = AppFeature.clipboardHistory.isAvailable
        if isAvailable, defaults.bool(forKey: DefaultsKey.clipboardAutoClearOnDelay) {
            startTimer()
        } else {
            stopTimer()
        }
        let workspaceCenter = NSWorkspace.shared.notificationCenter
        syncObserver(&sleepObserver,
                     isWanted: isAvailable && defaults.bool(forKey: DefaultsKey.clipboardAutoClearOnSleep),
                     preferenceKey: DefaultsKey.clipboardAutoClearOnSleep,
                     name: NSWorkspace.willSleepNotification,
                     center: workspaceCenter)
        syncObserver(&displaySleepObserver,
                     isWanted: isAvailable && defaults.bool(forKey: DefaultsKey.clipboardAutoClearOnDisplaySleep),
                     preferenceKey: DefaultsKey.clipboardAutoClearOnDisplaySleep,
                     name: NSWorkspace.screensDidSleepNotification,
                     center: workspaceCenter)
        syncObserver(&screenLockObserver,
                     isWanted: isAvailable && defaults.bool(forKey: DefaultsKey.clipboardAutoClearOnScreenLock),
                     preferenceKey: DefaultsKey.clipboardAutoClearOnScreenLock,
                     name: Self.screenLockNotification,
                     center: DistributedNotificationCenter.default())
    }

    /// Each trigger holds its own observer, so it works with the others (and
    /// with the delay) switched off.
    private func syncObserver(_ token: inout NSObjectProtocol?,
                              isWanted: Bool,
                              preferenceKey: String,
                              name: Notification.Name,
                              center: NotificationCenter) {
        if isWanted {
            guard token == nil else { return }
            token = center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                self?.clearNow(triggerPreferenceKey: preferenceKey)
            }
        } else if let existing = token {
            center.removeObserver(existing)
            token = nil
        }
    }

    private func startTimer() {
        guard timer == nil else { return }
        baseline()
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            self?.tick()
        }
        timer.tolerance = 0.2
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
        readGeneration &+= 1
        readInFlight = false
    }

    /// Starts the clock now, so whatever is already on the pasteboard gets a
    /// full delay: turning the setting on, or launching the app, never wipes
    /// something copied seconds earlier.
    private func baseline() {
        lastChangeDate = Date()
        readChangeCount { [weak self] count in
            self?.lastChangeCount = count
        }
    }

    private func tick() {
        let delay = Defaults.sanitizedClipboardAutoClearDelay(
            UserDefaults.standard.integer(forKey: DefaultsKey.clipboardAutoClearDelay))
        readChangeCount { [weak self] count in
            guard let self else { return }
            switch ClipboardAutoClearSupport.decide(changeCount: count,
                                                    lastChangeCount: self.lastChangeCount,
                                                    lastClearedChangeCount: self.lastClearedChangeCount,
                                                    lastChangeDate: self.lastChangeDate,
                                                    now: Date(),
                                                    delay: TimeInterval(delay)) {
            case .noteChange:
                self.lastChangeCount = count
                self.lastChangeDate = Date()
            case .clear:
                self.clearNow(expecting: count,
                              triggerPreferenceKey: DefaultsKey.clipboardAutoClearOnDelay)
            case .wait:
                break
            }
        }
    }

    /// Reads the change count on the shared pasteboard lane and answers on the
    /// main thread. Never reads on the main thread: a blocked main thread stalls
    /// every event tap with it, which is what froze typing system wide in #189.
    private func readChangeCount(_ completion: @escaping (Int) -> Void) {
        guard !readInFlight else { return }
        readInFlight = true
        readGeneration &+= 1
        let generation = readGeneration
        // If a read wedges behind a lingering password prompt, free the flag so
        // later ticks still clear; the abandoned read is dropped by its stale
        // generation whenever it finally returns.
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) { [weak self] in
            guard let self, self.readGeneration == generation, self.readInFlight else { return }
            self.readInFlight = false
        }
        GeneralPasteboardAccess.shared.async { [weak self] in
            let count = NSPasteboard.general.changeCount
            DispatchQueue.main.async { [weak self] in
                guard let self, self.readGeneration == generation else { return }
                self.readInFlight = false
                completion(count)
            }
        }
    }

    /// Clears the pasteboard and records the count the clear produced, which is
    /// what keeps the delay from reading its own clear as fresh content.
    /// `expectedChangeCount` lets a caller clear only if the pasteboard state
    /// still matches; leaving it nil means clear whatever is on the pasteboard
    /// right now, which is what the event triggers want.
    private func clearNow(expecting expectedChangeCount: Int? = nil,
                          triggerPreferenceKey: String) {
        let alreadyCleared = lastClearedChangeCount
        configurationLock.lock()
        let generation = configurationGeneration
        configurationLock.unlock()
        GeneralPasteboardAccess.shared.async { [weak self] in
            guard let self else { return }
            self.configurationLock.lock()
            let currentGeneration = self.configurationGeneration
            self.configurationLock.unlock()
            guard ClipboardAutoClearSupport.clearIsAuthorized(
                enqueuedGeneration: generation,
                currentGeneration: currentGeneration,
                featureIsAvailable: AppFeature.clipboardHistory.isAvailable,
                triggerIsEnabled: UserDefaults.standard.bool(forKey: triggerPreferenceKey)) else {
                return
            }
            let pasteboard = NSPasteboard.general
            let changeCount = pasteboard.changeCount
            // Locking a Mac fires display sleep and screen lock together: with
            // nothing copied since our last clear there is nothing to clear.
            guard changeCount != alreadyCleared else { return }
            // Between the tick's read and this one there are queue hops, and a
            // copy that lands in that window is owed its own full delay, not
            // an immediate wipe just because it shares the moment of a clear
            // that was decided on older content.
            if let expectedChangeCount, changeCount != expectedChangeCount { return }
            let count = pasteboard.clearContents()
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.lastChangeCount = count
                self.lastClearedChangeCount = count
                self.lastChangeDate = Date()
                // Keeps the history poll from reading the empty pasteboard as
                // a copy, the same handshake a history paste performs.
                ClipboardHistoryService.shared.ignoreNextChange(upTo: count)
            }
        }
    }
}
