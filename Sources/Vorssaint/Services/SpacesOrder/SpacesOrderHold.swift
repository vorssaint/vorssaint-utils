// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import Darwin
import Foundation
import os

/// How the Dock arranges Spaces, as its `mru-spaces` preference reads.
/// A missing key is the system default, which rearranges by most recent use.
enum SpacesRearrangeSetting: Equatable {
    case absent, on, off
    /// Forced by a management profile or stored as something other than a
    /// Boolean. The feature never writes over it.
    case unsupported
    /// Synchronization failed, so the stored value is not known yet.
    case unreadable
}

/// The decisions behind keeping Spaces in a fixed order, kept apart from the
/// system calls so every case can be walked without touching the Dock.
enum SpacesOrderSupport {
    static let dockDomain = "com.apple.dock"
    static let preferenceKey = "mru-spaces"
    /// Marker values: the state to put back when the feature lets go.
    static let restoreAbsent = "absent"
    static let restoreOn = "on"
    /// Rearranging was already off when the feature turned on, so nothing is
    /// put back. The marker still shows that the feature holds it.
    static let restoreOff = "off"

    static func setting(raw: Any?, isForced: Bool) -> SpacesRearrangeSetting {
        if isForced { return .unsupported }
        guard let raw else { return .absent }
        guard let number = raw as? NSNumber else { return .unsupported }
        return number.boolValue ? .on : .off
    }

    enum Step: Equatable {
        /// Nothing to change.
        case none
        /// Save `marker`, then turn rearranging off.
        case hold(marker: String)
        /// Rearranging is already off: save `restoreOff` without touching the
        /// Dock, so turning it back on later still lets go.
        case remember
        /// Turn rearranging back on, removing the key when it was missing
        /// before, then clear the marker.
        case release(removeKey: Bool)
        /// The user already turned rearranging back on themselves: clear the
        /// marker and leave their choice alone.
        case forget
        /// The user turned rearranging back on while the feature held it off:
        /// clear the marker and turn the feature off, so their choice stands
        /// and the toggle shows it.
        case letGo
        /// The preference already reads as wanted and only the Dock still has
        /// to read it: restart the Dock, then settle as usual.
        case restart
    }

    /// What the Dock keeps doing while a restart is owed. It reads the
    /// preference only when it starts, so until then it runs what it ran
    /// before the preference was written.
    enum DockState: String {
        case rearranging, fixed

        init?(_ setting: SpacesRearrangeSetting) {
            switch setting {
            case .absent, .on: self = .rearranging
            case .off: self = .fixed
            case .unsupported, .unreadable: return nil
            }
        }
    }

    /// A restart the Dock still owes: the Dock process that has not read the
    /// preference since the feature wrote it, what that process runs, and every
    /// value written to the preference while it ran. Saved before each write.
    struct RestartJournal: Equatable {
        var dockPID: pid_t
        var dockRuns: DockState
        var wrote: [SpacesRearrangeSetting]

        /// Only what can still be checked counts: the same Dock process has to
        /// be running and the preference has to read as one of these writes. A
        /// Dock that restarted since has read the preference, and any other
        /// value is a change made through the Dock's own call, which the Dock
        /// applied itself, or a write that never landed.
        func holds(dockPID current: pid_t?, reads: SpacesRearrangeSetting) -> Bool {
            dockPID > 0 && current == dockPID && wrote.contains(reads)
        }

        private static let tokens: [SpacesRearrangeSetting: String] = [.absent: "absent", .on: "on", .off: "off"]

        /// `<pid> <fixed|rearranging> <absent|on|off>…`, also read by
        /// Tools/uninstall.sh.
        var encoded: String {
            ([String(dockPID), dockRuns.rawValue] + wrote.compactMap { Self.tokens[$0] }).joined(separator: " ")
        }

        init(dockPID: pid_t, dockRuns: DockState, wrote: [SpacesRearrangeSetting]) {
            self.dockPID = dockPID
            self.dockRuns = dockRuns
            self.wrote = wrote
        }

        init?(encoded: String) {
            let parts = encoded.split(separator: " ").map(String.init)
            guard parts.count > 2, let pid = pid_t(parts[0]), let runs = DockState(rawValue: parts[1]) else { return nil }
            let values = parts.dropFirst(2).map { token in Self.tokens.first { $0.value == token }?.key }
            guard values.allSatisfy({ $0 != nil }) else { return nil }
            self.init(dockPID: pid, dockRuns: runs, wrote: values.compactMap { $0 })
        }
    }

    /// One step toward the wanted state. A marker means the feature holds
    /// rearranging off, whether it turned it off or found it off, so finding it
    /// on again while the feature is on is the user taking back control in
    /// System Settings. The feature then lets go instead of turning it off over
    /// their choice.
    ///
    /// `dockRuns` is set while a Dock restart is owed and its journal still
    /// holds. The preference is then the feature's own write, which the Dock
    /// never read, so it is never taken for a change made in System Settings:
    /// the restart runs only when the preference already says what is wanted,
    /// and otherwise the latest toggle is applied over it.
    static func step(wanted: Bool, current: SpacesRearrangeSetting, marker: String?,
                     dockRuns: DockState? = nil) -> Step {
        guard current != .unreadable else { return .none }
        if let dockRuns {
            let reads = DockState(current)
            // Without a marker, or with one that put nothing aside, nothing is
            // owed back, so the Dock only has to catch up with the preference.
            let owesBack = marker != nil && marker != restoreOff
            let target: DockState? = wanted ? .fixed : (owesBack ? .rearranging : reads)
            if let reads, reads != dockRuns, reads == target { return .restart }
            let next = step(wanted: wanted, current: current, marker: marker)
            if next == .letGo, let marker { return .hold(marker: marker) }
            return next
        }
        if wanted {
            switch current {
            case .off: return marker == nil ? .remember : .none
            case .unsupported, .unreadable: return .none
            case .absent, .on:
                guard marker == nil else { return .letGo }
                return .hold(marker: current == .absent ? restoreAbsent : restoreOn)
            }
        }
        guard let marker else { return .none }
        // Rearranging was already off when the feature turned on, so whatever
        // it reads now is the user's own.
        guard marker != restoreOff else { return .forget }
        return current == .off ? .release(removeKey: marker == restoreAbsent) : .forget
    }
}

/// Every system touch point, injected. No defaults on the init, so a test can
/// never reach the real Dock.
struct SpacesOrderSystem {
    /// The current `mru-spaces` state.
    var read: () -> SpacesRearrangeSetting
    /// Writes `mru-spaces` to the preference file; nil removes the key.
    var write: (Bool?) -> Bool
    /// Restarts the Dock so it reads a written preference.
    var restartDock: () -> Bool
    /// The running Dock's process, nil when none runs. A restart replaces it.
    var dockPID: () -> pid_t?
}

extension SpacesOrderSystem {
    static let live = SpacesOrderSystem(
        read: {
            let key = SpacesOrderSupport.preferenceKey as CFString
            let domain = SpacesOrderSupport.dockDomain as CFString
            guard CFPreferencesSynchronize(domain, kCFPreferencesCurrentUser, kCFPreferencesAnyHost)
            else { return .unreadable }
            let raw = CFPreferencesCopyValue(key, domain, kCFPreferencesCurrentUser, kCFPreferencesAnyHost)
            return SpacesOrderSupport.setting(raw: raw,
                                              isForced: CFPreferencesAppValueIsForced(key, domain))
        },
        write: { value in
            let domain = SpacesOrderSupport.dockDomain as CFString
            CFPreferencesSetValue(SpacesOrderSupport.preferenceKey as CFString,
                                  value.map { NSNumber(value: $0) },
                                  domain, kCFPreferencesCurrentUser, kCFPreferencesAnyHost)
            return CFPreferencesSynchronize(domain, kCFPreferencesCurrentUser, kCFPreferencesAnyHost)
        },
        // A terminated Dock counts as an unexpected exit, so the system
        // starts it again at once; a clean quit would leave it closed.
        restartDock: { Shell.run("/usr/bin/killall", ["Dock"]).status == 0 },
        // The preference domain is the Dock's bundle identifier.
        dockPID: {
            NSRunningApplication.runningApplications(withBundleIdentifier: SpacesOrderSupport.dockDomain)
                .first?.processIdentifier
        }
    )
}

/// Keeps Spaces in a fixed order by turning off the Dock's rearranging by
/// recent use, and puts the user's own setting back when the feature lets go.
///
/// What to put back is saved before the first change, so a crash or an
/// uninstall from the Features hub is recovered by the next sync. An ordinary
/// quit restores nothing: the setting lives on disk, and restoring it on every
/// quit would change the Dock twice per session. Rearranging turned back on in
/// System Settings turns the feature off, noticed at the next Space change or
/// when the app comes forward.
final class SpacesOrderHold {
    static let shared = SpacesOrderHold(defaults: .standard, system: .live)

    private static let log = Logger(subsystem: Bundle.main.bundleIdentifier ?? "vorssaint",
                                    category: "spaces-order")
    private let defaults: UserDefaults
    private let system: SpacesOrderSystem
    /// Serial, so preference writes and a restart never overlap.
    private let queue = DispatchQueue(label: "com.vorssaint.spaces-order")
    private let queueKey = DispatchSpecificKey<Bool>()
    /// A newer request invalidates a reply before its queued work starts. The
    /// main-thread toggle write can notify observers that request another sync.
    private let requestLock = NSRecursiveLock()
    private var requestGeneration: UInt64 = 0
    /// A cached off value is not enough to release recovery. This remains set
    /// until that off value has synchronized or a newer choice starts a hold.
    private var pendingLetGoOwner: UInt64?
    /// Only the serial queue changes recovery ownership. Equal marker strings
    /// from different holds must still have different identities.
    private var markerGeneration: UInt64 = 0
    /// Observers for the moments a change made in System Settings shows up:
    /// a Space change and the app coming forward. Touched only on `queue`.
    private var watchTokens: [(center: NotificationCenter, token: NSObjectProtocol)] = []

    init(defaults: UserDefaults, system: SpacesOrderSystem) {
        self.defaults = defaults
        self.system = system
        queue.setSpecific(key: queueKey, value: true)
    }

    private func onQueue<T>(_ work: () -> T) -> T {
        if DispatchQueue.getSpecific(key: queueKey) == true { return work() }
        return queue.sync(execute: work)
    }

    private func newRequest() -> UInt64 {
        requestLock.lock()
        defer { requestLock.unlock() }
        requestGeneration &+= 1
        return requestGeneration
    }

    private func currentRequest() -> UInt64 {
        requestLock.lock()
        defer { requestLock.unlock() }
        return requestGeneration
    }

    private func awaitingLetGoPersistence() -> Bool {
        requestLock.lock()
        defer { requestLock.unlock() }
        return pendingLetGoOwner == markerGeneration
    }

    deinit {
        watchTokens.forEach { $0.center.removeObserver($0.token) }
    }

    /// True while the feature holds the setting, whether or not anything is
    /// owed back to the user, or the Dock still owes the restart that reads a
    /// written one.
    static var hasPendingRestore: Bool { isOwed(in: .standard) }

    private static func isOwed(in defaults: UserDefaults) -> Bool {
        defaults.string(forKey: DefaultsKey.spacesOrderRestore) != nil
            || defaults.string(forKey: DefaultsKey.spacesOrderRestartPending) != nil
    }

    private var journal: SpacesOrderSupport.RestartJournal? {
        defaults.string(forKey: DefaultsKey.spacesOrderRestartPending)
            .flatMap(SpacesOrderSupport.RestartJournal.init(encoded:))
    }

    /// The saved journal, only while the Dock and the preference still bear
    /// it out.
    private func heldJournal(reads current: SpacesRearrangeSetting) -> SpacesOrderSupport.RestartJournal? {
        journal.flatMap { $0.holds(dockPID: system.dockPID(), reads: current) ? $0 : nil }
    }

    private var isWanted: Bool {
        AppFeature.spacesOrder.isAvailable(in: defaults)
            && defaults.bool(forKey: DefaultsKey.spacesOrderEnabled)
    }

    /// Follows the toggle and the hub's availability. The wanted state is read
    /// when the work runs, so rapid toggles settle on the last one.
    func syncWithPreferences() {
        let generation = newRequest()
        queue.async { [self] in
            guard generation == currentRequest() else { return }
            let wanted = isWanted
            let completed = reconcileOnQueue(wanted: wanted, generation: generation)
            guard generation == currentRequest() else { return }
            if !completed {
                Self.log.error("Space rearranging did not change (fixed order wanted: \(wanted, privacy: .public))")
            }
            // Read again: the toggle may have changed while the work ran. A
            // let-go handed to the main thread settles the watch once the
            // toggle is off.
            watch(isWanted)
        }
    }

    /// Lets go when the user has turned rearranging back on while the feature
    /// held it off. It never turns rearranging off itself, so a hold still
    /// waiting for its sync is left to that sync. True when it let go or
    /// handed the let-go to the main thread.
    @discardableResult
    func letGoIfRearrangingReturned() -> Bool {
        let generation = currentRequest()
        return onQueue { letGoIfRearrangingReturnedOnQueue(generation: generation) }
    }

    private func letGoIfRearrangingReturnedOnQueue(generation: UInt64) -> Bool {
        guard generation == currentRequest() else { return false }
        guard isWanted, let marker = defaults.string(forKey: DefaultsKey.spacesOrderRestore) else { return false }
        let current = system.read()
        guard SpacesOrderSupport.step(wanted: true, current: current, marker: marker,
                                      dockRuns: heldJournal(reads: current)?.dockRuns) == .letGo
        else { return false }
        letGo(generation: generation)
        return true
    }

    private func watch(_ enabled: Bool) {
        guard enabled == watchTokens.isEmpty else { return }
        guard enabled else {
            watchTokens.forEach { $0.center.removeObserver($0.token) }
            watchTokens = []
            return
        }
        let moments: [(NotificationCenter, Notification.Name)] = [
            (NSWorkspace.shared.notificationCenter, NSWorkspace.activeSpaceDidChangeNotification),
            (NotificationCenter.default, NSApplication.didBecomeActiveNotification),
        ]
        watchTokens = moments.map { center, name in
            (center: center, token: center.addObserver(forName: name, object: nil, queue: nil) { [weak self] _ in
                guard let self else { return }
                let generation = self.currentRequest()
                self.queue.async { [weak self] in
                    guard let self, !self.watchTokens.isEmpty else { return }
                    // Keep watching until the reply is accepted. A newer
                    // request may discard a reply already waiting on main.
                    _ = self.letGoIfRearrangingReturnedOnQueue(generation: generation)
                }
            })
        }
    }

    /// A marker left behind while the feature is uninstalled, for instance by
    /// a crash during its removal from the hub, is settled at launch. An
    /// installed feature is synced by its own binding.
    static func recoverIfNeeded() {
        guard hasPendingRestore, !AppFeature.spacesOrder.isAvailable else { return }
        shared.syncWithPreferences()
    }

    /// Puts the user's setting back before the app's preferences are deleted,
    /// waiting for the change. False when rearranging is still off.
    static func restoreForRemoval() -> Bool {
        shared.restoreForRemoval()
    }

    /// Puts this hold's owed setting back, waiting for the change. True when
    /// nothing was owed, without touching the Dock.
    func restoreForRemoval() -> Bool {
        // Checked on the queue, behind any sync still waiting to hold, so a
        // marker that sync is about to write is seen and put back too.
        let generation = newRequest()
        return onQueue {
            guard generation == currentRequest() else { return false }
            guard Self.isOwed(in: defaults) else { return true }
            return reconcileOnQueue(wanted: false, generation: generation)
        }
    }

    /// Takes one step toward the wanted state. False when a system change
    /// failed; the marker and an owed restart then still describe what is
    /// owed.
    @discardableResult
    func reconcile(wanted: Bool) -> Bool {
        let generation = newRequest()
        return onQueue { reconcileOnQueue(wanted: wanted, generation: generation) }
    }

    private func reconcileOnQueue(wanted: Bool, generation: UInt64) -> Bool {
        guard generation == currentRequest() else { return false }
        let resumesAfterFailedPublication = awaitingLetGoPersistence()
        if resumesAfterFailedPublication && !wanted {
            letGo(generation: generation)
            return false
        }
        let current = system.read()
        guard generation == currentRequest(), current != .unreadable else { return false }
        if resumesAfterFailedPublication {
            // Turning the feature back on is a new choice. Retire only the
            // unfinished handoff, then preserve the setting this hold finds.
            requestLock.lock()
            guard generation == requestGeneration else {
                requestLock.unlock()
                return false
            }
            pendingLetGoOwner = nil
            requestLock.unlock()
            clearMarker()
        }
        let marker = defaults.string(forKey: DefaultsKey.spacesOrderRestore)
        let held = heldJournal(reads: current)
        // A journal the Dock and the preference no longer bear out owes
        // nothing: the Dock restarted and read the preference, or it applied a
        // later change itself. That change is then read like any other.
        if held == nil, defaults.object(forKey: DefaultsKey.spacesOrderRestartPending) != nil { saveJournal(nil) }
        switch SpacesOrderSupport.step(wanted: wanted, current: current, marker: marker, dockRuns: held?.dockRuns) {
        case .restart:
            guard system.restartDock() else { return false }
            saveJournal(nil)
            // The Dock now runs what the preference says, so the usual step
            // finishes the change.
            return reconcileOnQueue(wanted: wanted, generation: generation)
        case .none:
            // The preference already says what the Dock runs, so a restart is
            // not owed either.
            if held != nil { saveJournal(nil) }
            return true
        case .hold(let restore):
            // Saved before the system setting changes, so a crash in between
            // still knows what to put back.
            guard saveMarker(restore) else { return false }
            let result = apply(rearranging: false, removeKey: false, current: current, held: held)
            guard result.done else {
                // A failed synchronization can still have changed the value.
                // Only a confirmed unchanged value lets this new marker go.
                if marker == nil, result.unchanged { clearMarker() }
                return false
            }
            return true
        case .remember:
            guard saveMarker(SpacesOrderSupport.restoreOff) else { return false }
            // The Dock already runs a fixed order, or the step would have
            // restarted it first, so no restart is owed.
            if held != nil { saveJournal(nil) }
            return true
        case .release(let removeKey):
            let result = apply(rearranging: true, removeKey: removeKey, current: current, held: held)
            // Once the user's setting is back in the preference nothing more is
            // owed to them, so a later change of theirs stands. A restart the
            // Dock still owes is left to the journal. Without the write the
            // marker stays, so the next sync tries again.
            if result.wrote { clearMarker() }
            return result.done
        case .forget:
            clearMarker()
            if held != nil { saveJournal(nil) }
            return true
        case .letGo:
            letGo(generation: generation)
            return true
        }
    }

    /// Only the toggle is published on main. Recovery stays on the serial
    /// queue, and its identity keeps an accepted reply from clearing a newer
    /// hold. No worker waits for this reply, including during removal.
    private func letGo(generation: UInt64) {
        let owner = markerGeneration
        DispatchQueue.main.async { [self] in
            requestLock.lock()
            defer { requestLock.unlock() }
            guard generation == requestGeneration else { return }
            pendingLetGoOwner = owner
            defaults.set(false, forKey: DefaultsKey.spacesOrderEnabled)
            let persisted = defaults.synchronize()
            // A reentrant observer can request another sync or change the
            // toggle. Never clear recovery for a different current choice.
            guard !defaults.bool(forKey: DefaultsKey.spacesOrderEnabled) else {
                if pendingLetGoOwner == owner { pendingLetGoOwner = nil }
                return
            }
            guard persisted else { return }
            if pendingLetGoOwner == owner { pendingLetGoOwner = nil }
            // New syncs requested during publication wait on requestLock at
            // admission. They cannot forget recovery using an unpersisted off.
            queue.async { [self] in
                if markerGeneration == owner {
                    clearMarker()
                    watch(false)
                } else {
                    watch(isWanted)
                }
            }
            Self.log.info("Space rearranging was turned back on outside Vorssaint; fixed order turned off")
        }
    }

    /// Write the preference before restarting the Dock. Avoid an unconfirmed
    /// live request that could arrive after restoration or removal completed.
    private func apply(rearranging: Bool, removeKey: Bool, current: SpacesRearrangeSetting,
                       held: SpacesOrderSupport.RestartJournal?) -> (done: Bool, wrote: Bool, unchanged: Bool) {
        let value: SpacesRearrangeSetting = removeKey ? .absent : (rearranging ? .on : .off)
        // Saved before the preference changes, so an interruption before the
        // write or before the restart is still recovered by the next sync. A
        // Dock that still owes a restart runs what it ran; any other runs what
        // the preference says now, the opposite of this change.
        let dockRuns = held?.dockRuns ?? (rearranging ? .fixed : .rearranging)
        guard saveJournal(SpacesOrderSupport.RestartJournal(dockPID: held?.dockPID ?? system.dockPID() ?? 0,
                                                            dockRuns: dockRuns, wrote: (held?.wrote ?? []) + [value]))
        else { return (false, false, true) }
        guard system.write(removeKey ? nil : rearranging) else {
            // A false synchronization result does not undo SetValue. Read it
            // back before deciding whether this attempt changed anything.
            let after = system.read()
            if after == current { saveJournal(held) }
            return (false, after == value, after == current)
        }
        // A Dock that still runs this change needs no restart to read it.
        guard SpacesOrderSupport.DockState(value) != dockRuns else {
            saveJournal(nil)
            return (true, true, false)
        }
        guard system.restartDock() else { return (false, true, false) }
        saveJournal(nil)
        return (true, true, false)
    }

    private func saveMarker(_ value: String) -> Bool {
        markerGeneration &+= 1
        defaults.set(value, forKey: DefaultsKey.spacesOrderRestore)
        return defaults.synchronize()
    }

    private func clearMarker() {
        markerGeneration &+= 1
        defaults.removeObject(forKey: DefaultsKey.spacesOrderRestore)
        defaults.synchronize()
    }

    @discardableResult
    private func saveJournal(_ journal: SpacesOrderSupport.RestartJournal?) -> Bool {
        if let journal {
            defaults.set(journal.encoded, forKey: DefaultsKey.spacesOrderRestartPending)
        } else {
            defaults.removeObject(forKey: DefaultsKey.spacesOrderRestartPending)
        }
        return defaults.synchronize()
    }
}
