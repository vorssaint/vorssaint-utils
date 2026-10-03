// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import CoreFoundation
import Foundation

enum SpacesOrderTests {
    /// A Dock that only exists in memory. The live system is never built here,
    /// so nothing in this suite can reach the real preference or the Dock.
    final class FakeDock {
        var value: SpacesRearrangeSetting
        var liveAvailable = true
        var liveApplies = true
        var writable = true
        var restartSucceeds = true
        /// The running Dock's process; a restart that succeeds replaces it.
        var dockPID: pid_t? = 500
        var events: [String] = []
        var reads = 0
        var pauses = 0
        /// The user's own change in System Settings, landing right after the
        /// first read, on the same thread as that read.
        var changeAfterFirstRead: SpacesRearrangeSetting?
        /// The saved marker at the first call that could change the setting.
        var markerAtFirstCall: String?
        /// The restart journal the hold had saved, at each write.
        var journalAtWrites: [String?] = []
        /// One signal per recorded event, for the syncs that run on the
        /// hold's own queue.
        let signals = DispatchSemaphore(value: 0)
        /// One signal per read, for the decisions made off the main thread.
        let readSignals = DispatchSemaphore(value: 0)
        /// How long the first read takes, so a sync can be held on the hold's
        /// queue while the test calls in from the main thread.
        var firstReadDelay: useconds_t = 0
        private var sawFirstCall = false
        private let defaults: UserDefaults

        init(_ value: SpacesRearrangeSetting, defaults: UserDefaults) {
            self.value = value
            self.defaults = defaults
        }

        private func record(_ event: String) {
            if !sawFirstCall {
                sawFirstCall = true
                markerAtFirstCall = defaults.string(forKey: DefaultsKey.spacesOrderRestore)
            }
            events.append(event)
            signals.signal()
        }

        var system: SpacesOrderSystem {
            SpacesOrderSystem(
                read: {
                    if self.reads == 0, self.firstReadDelay > 0 { usleep(self.firstReadDelay) }
                    let current = self.value
                    if self.reads == 0, let change = self.changeAfterFirstRead { self.value = change }
                    self.reads += 1
                    self.readSignals.signal()
                    return current
                },
                setLive: { rearranging in
                    guard self.liveAvailable else { return false }
                    self.record("live(\(rearranging))")
                    if self.liveApplies { self.value = rearranging ? .on : .off }
                    return true
                },
                write: { rearranging in
                    self.record("write(\(rearranging.map { String($0) } ?? "nil"))")
                    self.journalAtWrites.append(self.defaults.string(forKey: DefaultsKey.spacesOrderRestartPending))
                    guard self.writable else { return false }
                    self.value = rearranging.map { $0 ? .on : .off } ?? .absent
                    return true
                },
                restartDock: {
                    self.record("restart")
                    if self.restartSucceeds { self.dockPID = (self.dockPID ?? 0) + 1 }
                    return self.restartSucceeds
                },
                dockPID: { self.dockPID },
                pause: { self.pauses += 1 }
            )
        }
    }

    static func run(_ suite: TestSuite) {
        let name = "com.vorssaint.tests.spaces-order.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        let marker = DefaultsKey.spacesOrderRestore
        let restartPending = DefaultsKey.spacesOrderRestartPending
        let absent = SpacesOrderSupport.restoreAbsent
        let on = SpacesOrderSupport.restoreOn
        let off = SpacesOrderSupport.restoreOff

        func setMarker(_ value: String?) {
            if let value {
                defaults.set(value, forKey: marker)
            } else {
                defaults.removeObject(forKey: marker)
            }
        }
        typealias Journal = SpacesOrderSupport.RestartJournal
        /// A journal saved by the fake Dock's first process, 500.
        func owedBy500(_ runs: SpacesOrderSupport.DockState, _ wrote: SpacesRearrangeSetting...) -> Journal {
            Journal(dockPID: 500, dockRuns: runs, wrote: wrote)
        }
        func make(_ value: SpacesRearrangeSetting, marker saved: String? = nil,
                  journal preset: Journal? = nil) -> (SpacesOrderHold, FakeDock) {
            setMarker(saved)
            if let preset {
                defaults.set(preset.encoded, forKey: restartPending)
            } else {
                defaults.removeObject(forKey: restartPending)
            }
            let dock = FakeDock(value, defaults: defaults)
            return (SpacesOrderHold(defaults: defaults, system: dock.system), dock)
        }
        func journal() -> Journal? {
            defaults.string(forKey: restartPending).flatMap(Journal.init(encoded:))
        }
        /// What the saved journal says the Dock still runs; nil when no restart is owed.
        func owed() -> SpacesOrderSupport.DockState? { journal()?.dockRuns }

        // MARK: Reading the preference

        suite.expect(SpacesOrderSupport.setting(raw: nil, isForced: false) == .absent
                     && SpacesOrderSupport.setting(raw: true, isForced: false) == .on
                     && SpacesOrderSupport.setting(raw: false, isForced: false) == .off
                     && SpacesOrderSupport.setting(raw: NSNumber(value: 0), isForced: false) == .off
                     && SpacesOrderSupport.setting(raw: kCFBooleanFalse as CFTypeRef, isForced: false) == .off
                     && SpacesOrderSupport.setting(raw: kCFBooleanTrue as CFTypeRef, isForced: false) == .on,
                     "a missing key reads as the default and Booleans read as on or off")
        suite.expect(SpacesOrderSupport.setting(raw: "NO", isForced: false) == .unsupported
                     && SpacesOrderSupport.setting(raw: true, isForced: true) == .unsupported
                     && SpacesOrderSupport.setting(raw: nil, isForced: true) == .unsupported,
                     "a managed value or one that is not a Boolean is never treated as the user's own")

        // MARK: Planning

        let plan = SpacesOrderSupport.step
        let step: (Bool, SpacesRearrangeSetting, String?) -> SpacesOrderSupport.Step = { plan($0, $1, $2, nil) }
        suite.expect(step(true, .off, absent) == .none && step(true, .off, off) == .none
                     && step(true, .unsupported, nil) == .none && step(true, .unsupported, on) == .none,
                     "a setting already off or managed is left alone, so launch never restarts the Dock")
        suite.expect(step(true, .off, nil) == .remember,
                     "rearranging found already off is remembered as held, with nothing to put back")
        suite.expect(step(true, .on, off) == .letGo && step(true, .absent, off) == .letGo,
                     "rearranging turned back on over a hold that found it off lets go like any other")
        suite.expect(step(false, .off, off) == .forget && step(false, .on, off) == .forget
                     && step(false, .absent, off) == .forget && step(false, .unsupported, off) == .forget,
                     "a hold that found rearranging off never turns it on when it lets go")
        suite.expect(step(true, .absent, nil) == .hold(marker: absent)
                     && step(true, .on, nil) == .hold(marker: on),
                     "turning the feature on saves exactly the state it found")
        suite.expect(step(true, .absent, on) == .letGo && step(true, .on, absent) == .letGo
                     && step(true, .on, on) == .letGo && step(true, .absent, absent) == .letGo,
                     "rearranging turned back on while the feature held it off is the user's choice, never undone")
        suite.expect([SpacesRearrangeSetting.absent, .on, .off, .unsupported].allSatisfy {
                         step(false, $0, nil) == .none
                     },
                     "without a marker nothing is restored, so an original off setting stays off")
        suite.expect(step(false, .off, absent) == .release(removeKey: true)
                     && step(false, .off, on) == .release(removeKey: false),
                     "turning the feature off returns to a missing key or an explicit on")
        suite.expect(step(false, .absent, absent) == .forget && step(false, .on, absent) == .forget
                     && step(false, .on, on) == .forget && step(false, .unsupported, on) == .forget,
                     "a setting the user already changed is never undone")
        suite.expect(plan(true, .off, absent, .rearranging) == .restart
                     && plan(false, .absent, absent, .fixed) == .restart
                     && plan(false, .on, on, .fixed) == .restart
                     && plan(false, .absent, nil, .fixed) == .restart,
                     "an owed restart runs once the preference already says what is wanted")
        suite.expect(plan(true, .absent, absent, .fixed) == .hold(marker: absent)
                     && plan(true, .on, on, .fixed) == .hold(marker: on)
                     && plan(true, .absent, absent, .rearranging) == .hold(marker: absent),
                     "a preference the Dock has not read yet is never taken for rearranging turned back on")
        suite.expect(plan(true, .off, absent, .fixed) == .none
                     && plan(false, .off, absent, .fixed) == .release(removeKey: true)
                     && plan(false, .off, on, .rearranging) == .release(removeKey: false)
                     && plan(false, .absent, absent, .rearranging) == .forget,
                     "the latest toggle is applied over a change still waiting for its restart")
        let sample = Journal(dockPID: 500, dockRuns: .fixed, wrote: [.absent, .off])
        suite.expect(sample.encoded == "500 fixed absent off" && Journal(encoded: sample.encoded) == sample
                     && Journal(encoded: "500 fixed") == nil && Journal(encoded: "dock fixed off") == nil
                     && Journal(encoded: "500 moving off") == nil && Journal(encoded: "500 fixed maybe") == nil,
                     "a restart journal reads back exactly as saved and nothing else passes for one")
        suite.expect(sample.holds(dockPID: 500, reads: .absent) && sample.holds(dockPID: 500, reads: .off)
                     && !sample.holds(dockPID: 501, reads: .absent) && !sample.holds(dockPID: nil, reads: .absent)
                     && !sample.holds(dockPID: 500, reads: .on)
                     && !Journal(dockPID: 0, dockRuns: .fixed, wrote: [.absent]).holds(dockPID: 0, reads: .absent),
                     "a journal holds only for the same Dock process and a preference it wrote")

        // MARK: Turning rearranging off

        var (hold, dock) = make(.absent)
        suite.expect(hold.reconcile(wanted: true) && dock.events == ["live(false)"]
                     && dock.value == .off && defaults.string(forKey: marker) == absent,
                     "the Dock's own call turns rearranging off without a write or a restart")
        suite.expect(dock.markerAtFirstCall == absent,
                     "the state to put back is saved before the system setting changes")

        (hold, dock) = make(.on)
        suite.expect(hold.reconcile(wanted: true) && defaults.string(forKey: marker) == on,
                     "an explicit on is remembered as on")

        (hold, dock) = make(.off)
        suite.expect(hold.reconcile(wanted: true) && dock.events.isEmpty
                     && defaults.string(forKey: marker) == off,
                     "a user who already keeps a fixed order gets no Dock change, only a marker that the feature holds it")
        (hold, dock) = make(.off, marker: absent)
        suite.expect(hold.reconcile(wanted: true) && dock.events.isEmpty
                     && defaults.string(forKey: marker) == absent,
                     "a relaunch with the setting already applied never touches or restarts the Dock")

        (hold, dock) = make(.absent)
        dock.liveAvailable = false
        suite.expect(hold.reconcile(wanted: true) && dock.events == ["write(false)", "restart"]
                     && dock.value == .off && defaults.string(forKey: marker) == absent,
                     "without the Dock's call the preference is written and the Dock restarts once")

        (hold, dock) = make(.absent)
        dock.liveApplies = false
        suite.expect(hold.reconcile(wanted: true)
                     && dock.events == ["live(false)", "write(false)", "restart"]
                     && dock.reads == 1 + SpacesOrderSupport.confirmAttempts
                     && dock.pauses == SpacesOrderSupport.confirmAttempts,
                     "an unconfirmed live call waits out its checks, then writes and restarts exactly once")

        (hold, dock) = make(.absent)
        dock.liveAvailable = false
        dock.writable = false
        suite.expect(!hold.reconcile(wanted: true) && dock.events == ["write(false)"]
                     && defaults.object(forKey: marker) == nil && owed() == nil,
                     "a hold that changed nothing removes the marker it created and never restarts the Dock")
        (hold, dock) = make(.absent)
        dock.liveAvailable = false
        dock.restartSucceeds = false
        suite.expect(!hold.reconcile(wanted: true) && dock.value == .off
                     && defaults.string(forKey: marker) == absent && owed() == .rearranging,
                     "a written preference whose restart failed keeps its marker and the owed restart")
        suite.expect(dock.journalAtWrites == [owedBy500(.rearranging, .off).encoded],
                     "the Dock process, what it runs and the value are saved before a hold writes the preference")
        // The preference already reads off, so only the owed restart keeps the
        // next sync from taking it for what the Dock does.
        dock.events = []
        suite.expect(!hold.reconcile(wanted: true) && dock.events == ["restart"]
                     && defaults.string(forKey: marker) == absent && owed() == .rearranging,
                     "the next sync retries a failed restart instead of trusting the written preference")
        dock.restartSucceeds = true
        dock.events = []
        suite.expect(hold.reconcile(wanted: true) && dock.events == ["restart"]
                     && dock.value == .off && defaults.string(forKey: marker) == absent && owed() == nil,
                     "a restart that finally runs finishes the hold and keeps what to put back")

        // A live call the Dock accepted can still land after its checks ran
        // out, so a failed hold that made one still owes the user's setting.
        for start in [SpacesRearrangeSetting.absent, .on] {
            (hold, dock) = make(start)
            dock.liveApplies = false
            dock.writable = false
            suite.expect(!hold.reconcile(wanted: true) && dock.events == ["live(false)", "write(false)"]
                         && dock.value == start
                         && defaults.string(forKey: marker) == (start == .absent ? absent : on),
                         "an accepted but unconfirmed live call whose write also failed keeps its marker (from: \(start))")
        }
        dock.value = .off
        dock.liveApplies = true
        dock.events = []
        suite.expect(hold.reconcile(wanted: false) && dock.events == ["live(true)"]
                     && dock.value == .on && defaults.object(forKey: marker) == nil,
                     "a live change that lands after a failed hold is still put back by the kept marker")

        // MARK: Putting the user's setting back

        (hold, dock) = make(.off, marker: absent)
        suite.expect(hold.reconcile(wanted: false) && dock.events == ["live(true)", "write(nil)"]
                     && dock.value == .absent && defaults.object(forKey: marker) == nil,
                     "a setting that started missing is turned back on and its key removed, without a restart")
        (hold, dock) = make(.off, marker: on)
        suite.expect(hold.reconcile(wanted: false) && dock.events == ["live(true)"]
                     && dock.value == .on && defaults.object(forKey: marker) == nil,
                     "a setting that started on is turned back on and left explicit")

        (hold, dock) = make(.off, marker: absent)
        dock.liveAvailable = false
        suite.expect(hold.reconcile(wanted: false) && dock.events == ["write(nil)", "restart"]
                     && dock.value == .absent && defaults.object(forKey: marker) == nil,
                     "without the Dock's call a missing key is restored with one restart")
        (hold, dock) = make(.off, marker: on)
        dock.liveAvailable = false
        suite.expect(hold.reconcile(wanted: false) && dock.events == ["write(true)", "restart"]
                     && dock.value == .on,
                     "without the Dock's call an explicit on is restored with one restart")

        (hold, dock) = make(.off, marker: absent)
        dock.liveAvailable = false
        dock.writable = false
        suite.expect(!hold.reconcile(wanted: false) && dock.value == .off
                     && defaults.string(forKey: marker) == absent,
                     "a failed restore keeps its marker so the next sync tries again")
        dock.writable = true
        suite.expect(hold.reconcile(wanted: false) && dock.value == .absent
                     && defaults.object(forKey: marker) == nil,
                     "the next sync finishes an interrupted restore")

        // A restore whose restart failed already reads back on, which alone
        // would pass for a setting the Dock already runs.
        (hold, dock) = make(.off, marker: absent)
        dock.liveAvailable = false
        dock.restartSucceeds = false
        suite.expect(!hold.reconcile(wanted: false) && dock.events == ["write(nil)", "restart"]
                     && dock.value == .absent && defaults.object(forKey: marker) == nil && owed() == .fixed,
                     "a restored preference whose restart failed owes the user nothing more, only the Dock its restart")
        suite.expect(dock.journalAtWrites == [owedBy500(.fixed, .absent).encoded],
                     "the Dock process, what it runs and the value are saved before a restore writes the preference")
        dock.events = []
        suite.expect(!hold.reconcile(wanted: false) && dock.events == ["restart"] && owed() == .fixed,
                     "the next sync retries the restart instead of trusting the restored preference")
        dock.restartSucceeds = true
        dock.events = []
        suite.expect(hold.reconcile(wanted: false) && dock.events == ["restart"]
                     && dock.value == .absent && defaults.object(forKey: marker) == nil && owed() == nil,
                     "a restart that finally runs finishes the restore and clears the marker")

        // Turning fixed order back on while a restore still waits for its
        // restart is the latest toggle, not rearranging turned back on in
        // System Settings: the Dock never left its fixed order.
        defaults.set(true, forKey: DefaultsKey.spacesOrderEnabled)
        defaults.set(true, forKey: AppFeature.spacesOrder.availabilityKey)
        (hold, dock) = make(.off, marker: absent)
        dock.liveAvailable = false
        dock.restartSucceeds = false
        suite.expect(!hold.reconcile(wanted: false) && owed() == .fixed
                     && !hold.letGoIfRearrangingReturned() && defaults.bool(forKey: DefaultsKey.spacesOrderEnabled),
                     "a restore still waiting for its restart is never taken for rearranging turned back on")
        dock.events = []
        suite.expect(hold.reconcile(wanted: true) && dock.events == ["write(false)"]
                     && dock.value == .off && defaults.string(forKey: marker) == absent && owed() == nil
                     && defaults.bool(forKey: DefaultsKey.spacesOrderEnabled),
                     "turning fixed order back on over an owed restore writes rearranging off again, with no restart for a Dock that never left its fixed order")
        dock.events = []
        suite.expect(hold.reconcile(wanted: true) && dock.events.isEmpty
                     && defaults.string(forKey: marker) == absent && defaults.bool(forKey: DefaultsKey.spacesOrderEnabled),
                     "a later sync finds nothing left to change")
        (hold, dock) = make(.absent, journal: owedBy500(.fixed, .absent))
        suite.expect(hold.reconcile(wanted: true) && dock.events == ["live(false)"]
                     && dock.value == .off && defaults.string(forKey: marker) == absent && owed() == nil
                     && defaults.bool(forKey: DefaultsKey.spacesOrderEnabled),
                     "the Dock's own call applies the latest toggle over an owed restore")

        // A restart owed by one Dock process is not owed by the next: after a
        // hold's restart failed, the Dock can restart on its own, read the
        // preference and keep a fixed order.
        (hold, dock) = make(.absent)
        dock.liveAvailable = false
        dock.restartSucceeds = false
        _ = hold.reconcile(wanted: true)
        dock.dockPID = 900
        dock.events = []
        suite.expect(!hold.reconcile(wanted: false) && dock.events == ["write(nil)", "restart"]
                     && dock.value == .absent && defaults.object(forKey: marker) == nil
                     && journal() == Journal(dockPID: 900, dockRuns: .fixed, wrote: [.absent]),
                     "a restore after the Dock restarted on its own is owed by the Dock now running, which keeps a fixed order")
        dock.events = []
        suite.expect(!hold.reconcile(wanted: false) && dock.events == ["restart"] && owed() == .fixed,
                     "the next sync retries that restart instead of clearing it")
        dock.restartSucceeds = true
        dock.events = []
        suite.expect(hold.reconcile(wanted: false) && dock.events == ["restart"] && owed() == nil,
                     "the restart that finally runs settles the restore")

        // Rearranging turned back on in System Settings after a hold's restart
        // failed is applied by the Dock itself, and stays the user's choice.
        for check in ["watch", "sync"] {
            defaults.set(true, forKey: DefaultsKey.spacesOrderEnabled)
            (hold, dock) = make(.absent)
            dock.liveAvailable = false
            dock.restartSucceeds = false
            _ = hold.reconcile(wanted: true)
            dock.value = .on
            dock.events = []
            let letGo = check == "watch" ? hold.letGoIfRearrangingReturned() : hold.reconcile(wanted: true)
            suite.expect(letGo && dock.events.isEmpty && dock.value == .on
                         && defaults.object(forKey: marker) == nil && !defaults.bool(forKey: DefaultsKey.spacesOrderEnabled),
                         "a change made in System Settings after a failed restart lets go instead of holding again (\(check))")
        }
        suite.expect(owed() == nil, "the sync drops a restart the Dock no longer owes")
        defaults.set(true, forKey: DefaultsKey.spacesOrderEnabled)

        // The app can stop right after saving what the Dock still runs, before
        // the preference is written, or right after that write, before the
        // restart. Either way the next launch finishes the change.
        (hold, dock) = make(.off, marker: absent, journal: owedBy500(.fixed, .absent))
        suite.expect(hold.reconcile(wanted: false) && dock.events == ["live(true)", "write(nil)"]
                     && dock.value == .absent && defaults.object(forKey: marker) == nil && owed() == nil,
                     "a restore stopped before its write is written again at the next launch")
        (hold, dock) = make(.absent, marker: absent, journal: owedBy500(.fixed, .absent))
        suite.expect(hold.reconcile(wanted: false) && dock.events == ["restart"]
                     && defaults.object(forKey: marker) == nil && owed() == nil,
                     "a restore stopped after its write restarts the Dock instead of forgetting it")
        // Nothing shows that a hold's write never landed rather than being
        // undone in System Settings, so the user's choice wins.
        (hold, dock) = make(.absent, marker: absent, journal: owedBy500(.rearranging, .off))
        suite.expect(hold.reconcile(wanted: true) && dock.events.isEmpty && dock.value == .absent
                     && defaults.object(forKey: marker) == nil && owed() == nil
                     && !defaults.bool(forKey: DefaultsKey.spacesOrderEnabled),
                     "a hold stopped before its write lets go like any rearranging found back on")
        defaults.set(true, forKey: DefaultsKey.spacesOrderEnabled)
        (hold, dock) = make(.off, marker: absent, journal: owedBy500(.rearranging, .off))
        suite.expect(hold.reconcile(wanted: true) && dock.events == ["restart"]
                     && defaults.string(forKey: marker) == absent && owed() == nil,
                     "a hold stopped after its write restarts the Dock at the next launch")
        defaults.removeObject(forKey: DefaultsKey.spacesOrderEnabled)
        defaults.removeObject(forKey: AppFeature.spacesOrder.availabilityKey)

        (hold, dock) = make(.on, marker: absent)
        suite.expect(hold.reconcile(wanted: false) && dock.events.isEmpty
                     && dock.value == .on && defaults.object(forKey: marker) == nil,
                     "rearranging the user turned back on themselves is kept and the marker forgotten")
        (hold, dock) = make(.absent, marker: on)
        suite.expect(hold.reconcile(wanted: false) && dock.events.isEmpty && dock.value == .absent,
                     "a key the user removed themselves is never written back")

        // MARK: Putting the setting back before removal

        (hold, dock) = make(.off)
        suite.expect(hold.restoreForRemoval() && dock.events.isEmpty && dock.reads == 0
                     && dock.value == .off && defaults.object(forKey: marker) == nil,
                     "removal with nothing owed succeeds without touching the Dock")
        // A hold that found rearranging already off put nothing aside, so
        // turning the feature off or removing the app leaves the user's own
        // setting as it reads and reports nothing failed.
        for start in [SpacesRearrangeSetting.off, .on, .absent] {
            (hold, dock) = make(start, marker: off)
            suite.expect(hold.reconcile(wanted: false) && dock.events.isEmpty && dock.value == start
                         && defaults.object(forKey: marker) == nil,
                         "turning off a hold that found rearranging off leaves the setting alone (reads: \(start))")
            (hold, dock) = make(start, marker: off)
            suite.expect(hold.restoreForRemoval() && dock.events.isEmpty && dock.value == start
                         && defaults.object(forKey: marker) == nil,
                         "removal over a hold that found rearranging off succeeds without touching the Dock (reads: \(start))")
        }
        (hold, dock) = make(.off, marker: absent)
        suite.expect(hold.restoreForRemoval() && dock.events == ["live(true)", "write(nil)"]
                     && dock.value == .absent && defaults.object(forKey: marker) == nil,
                     "removal turns rearranging back on, removes a key that started missing and clears the marker")
        (hold, dock) = make(.off, marker: on)
        suite.expect(hold.restoreForRemoval() && dock.events == ["live(true)"]
                     && dock.value == .on && defaults.object(forKey: marker) == nil,
                     "removal turns rearranging back on as an explicit on and clears the marker")
        (hold, dock) = make(.off, marker: absent)
        dock.liveAvailable = false
        dock.writable = false
        suite.expect(!hold.restoreForRemoval() && dock.events == ["write(nil)"]
                     && dock.value == .off && defaults.string(forKey: marker) == absent,
                     "a removal whose restore failed reports it and keeps the marker")
        (hold, dock) = make(.off, marker: absent)
        dock.liveAvailable = false
        dock.restartSucceeds = false
        suite.expect(!hold.restoreForRemoval() && !hold.restoreForRemoval()
                     && dock.events == ["write(nil)", "restart", "restart"]
                     && defaults.object(forKey: marker) == nil && owed() == .fixed,
                     "a removal whose restart keeps failing never reports the restore as done")
        dock.restartSucceeds = true
        suite.expect(hold.restoreForRemoval() && dock.events == ["write(nil)", "restart", "restart", "restart"]
                     && defaults.object(forKey: marker) == nil && owed() == nil,
                     "a removal finishes once the owed restart runs")
        // The marker can already be gone while the Dock still owes a restart.
        (hold, dock) = make(.on, journal: owedBy500(.fixed, .on))
        dock.restartSucceeds = false
        suite.expect(!hold.restoreForRemoval() && !hold.restoreForRemoval()
                     && dock.events == ["restart", "restart"] && owed() == .fixed,
                     "a removal whose owed restart keeps failing without a marker never reports it done")
        dock.restartSucceeds = true
        suite.expect(hold.restoreForRemoval() && dock.events == ["restart", "restart", "restart"] && owed() == nil,
                     "removal runs an owed restart even without a marker")
        (hold, dock) = make(.absent, journal: owedBy500(.fixed, .absent))
        dock.dockPID = 900
        suite.expect(hold.restoreForRemoval() && dock.events.isEmpty && owed() == nil,
                     "a Dock that restarted since has read the restore, so removal owes it no restart")

        // Removal runs on the hold's queue, behind a sync still holding, so
        // the marker that sync writes is put back before removal returns.
        defaults.set(true, forKey: DefaultsKey.spacesOrderEnabled)
        defaults.set(true, forKey: AppFeature.spacesOrder.availabilityKey)
        (hold, dock) = make(.absent)
        dock.firstReadDelay = 200_000
        hold.syncWithPreferences()
        suite.expect(hold.restoreForRemoval() && dock.events == ["live(false)", "live(true)", "write(nil)"]
                     && dock.value == .absent && defaults.object(forKey: marker) == nil,
                     "removal waits for a sync still on the hold's queue and puts back what it held")
        defaults.removeObject(forKey: DefaultsKey.spacesOrderEnabled)
        defaults.removeObject(forKey: AppFeature.spacesOrder.availabilityKey)

        // MARK: Rearranging turned back on in System Settings

        let enabled = DefaultsKey.spacesOrderEnabled
        defaults.set(true, forKey: enabled)
        (hold, dock) = make(.on, marker: absent)
        suite.expect(hold.reconcile(wanted: true) && dock.events.isEmpty && dock.value == .on
                     && defaults.object(forKey: marker) == nil && !defaults.bool(forKey: enabled),
                     "a sync that finds rearranging back on keeps it and turns the feature off to match")
        defaults.set(true, forKey: enabled)
        (hold, dock) = make(.absent, marker: on)
        suite.expect(hold.reconcile(wanted: true) && dock.events.isEmpty && dock.value == .absent
                     && defaults.object(forKey: marker) == nil && !defaults.bool(forKey: enabled),
                     "a key removed while the feature was on is never turned off again")

        let available = AppFeature.spacesOrder.availabilityKey
        defaults.set(true, forKey: available)
        defaults.set(true, forKey: enabled)
        (hold, dock) = make(.off, marker: absent)
        suite.expect(!hold.letGoIfRearrangingReturned() && dock.events.isEmpty
                     && defaults.string(forKey: marker) == absent && defaults.bool(forKey: enabled),
                     "the check leaves a setting still held off alone")
        dock.value = .on
        suite.expect(hold.letGoIfRearrangingReturned() && dock.events.isEmpty
                     && defaults.object(forKey: marker) == nil && !defaults.bool(forKey: enabled),
                     "the check notices rearranging turned back on and turns the feature off")
        defaults.set(true, forKey: enabled)
        (hold, dock) = make(.on)
        suite.expect(!hold.letGoIfRearrangingReturned() && dock.events.isEmpty
                     && defaults.object(forKey: marker) == nil && defaults.bool(forKey: enabled),
                     "the check never turns rearranging off itself, so a hold is left to its own sync")
        // Fixed order turned on while rearranging is already off, then
        // rearranging turned back on in System Settings: the feature lets go
        // like any other hold, and the next launch leaves that choice alone.
        for check in ["watch", "sync"] {
            defaults.set(true, forKey: enabled)
            (hold, dock) = make(.off)
            suite.expect(hold.reconcile(wanted: true) && dock.events.isEmpty
                         && defaults.string(forKey: marker) == off && defaults.bool(forKey: enabled),
                         "fixed order over rearranging already off holds it without changing the Dock (\(check))")
            dock.value = .on
            let letGo = check == "watch" ? hold.letGoIfRearrangingReturned() : hold.reconcile(wanted: true)
            suite.expect(letGo && dock.events.isEmpty && dock.value == .on
                         && defaults.object(forKey: marker) == nil && !defaults.bool(forKey: enabled),
                         "rearranging turned back on over a hold that found it off lets go (\(check))")
            let relaunched = SpacesOrderHold(defaults: defaults, system: dock.system)
            suite.expect(relaunched.reconcile(wanted: defaults.bool(forKey: enabled)) && dock.events.isEmpty
                         && dock.value == .on && defaults.object(forKey: marker) == nil,
                         "the next launch never turns rearranging off over that choice (\(check))")
        }
        defaults.set(true, forKey: enabled)
        defaults.set(false, forKey: available)
        (hold, dock) = make(.on, marker: absent)
        suite.expect(!hold.letGoIfRearrangingReturned() && defaults.string(forKey: marker) == absent,
                     "an uninstalled feature is left to its own sync, which restores or forgets")

        // The sync starts the watch, so the check needs no caller of its own.
        defaults.set(true, forKey: available)
        defaults.set(true, forKey: enabled)
        (hold, dock) = make(.off, marker: absent)
        dock.changeAfterFirstRead = .on
        hold.syncWithPreferences()
        let noticeDeadline = Date().addingTimeInterval(3)
        // The toggle is the last write of a let-go and may land on the main
        // thread, so wait for it with the main run loop running.
        while defaults.bool(forKey: enabled), Date() < noticeDeadline {
            NSWorkspace.shared.notificationCenter.post(name: NSWorkspace.activeSpaceDidChangeNotification,
                                                       object: nil)
            RunLoop.main.run(mode: .default, before: Date().addingTimeInterval(0.02))
        }
        suite.expect(defaults.object(forKey: marker) == nil && !defaults.bool(forKey: enabled)
                     && dock.events.isEmpty && dock.value == .on && dock.reads == 2,
                     "a Space change after rearranging is turned back on turns the feature off")

        // Letting go hands the marker and the toggle back on the main thread.
        // Starts a let-go with `trigger`, checks that nothing changed while the
        // main run loop is not running, then runs it until the marker is gone
        // and the toggle reads off. Reports, for each of those two changes,
        // whether it was made on the main thread; nil when it never came.
        func letGoOnMain(_ dock: FakeDock, _ trigger: () -> Void)
            -> (heldUntilMain: Bool, markerOnMain: Bool?, toggleOnMain: Bool?) {
            let lock = NSLock()
            var markerOnMain: Bool?
            var toggleOnMain: Bool?
            let token = NotificationCenter.default.addObserver(forName: UserDefaults.didChangeNotification,
                                                               object: defaults, queue: nil) { _ in
                let onMain = Thread.isMainThread
                let markerGone = defaults.object(forKey: marker) == nil
                let toggleOff = !defaults.bool(forKey: enabled)
                lock.withLock {
                    if markerGone, markerOnMain == nil { markerOnMain = onMain }
                    if toggleOff, toggleOnMain == nil { toggleOnMain = onMain }
                }
            }
            defer { NotificationCenter.default.removeObserver(token) }
            trigger()
            // The read that decides to let go, then time for any work queued
            // after it on that thread.
            let decided = dock.readSignals.wait(timeout: .now() + 3) == .success
            usleep(200_000)
            let heldUntilMain = decided && defaults.string(forKey: marker) != nil
                && defaults.bool(forKey: enabled) && dock.value == .on && dock.events.isEmpty
            let deadline = Date().addingTimeInterval(3)
            while lock.withLock({ markerOnMain == nil || toggleOnMain == nil }), Date() < deadline {
                RunLoop.main.run(mode: .default, before: Date().addingTimeInterval(0.01))
            }
            return lock.withLock { (heldUntilMain, markerOnMain, toggleOnMain) }
        }

        defaults.set(true, forKey: enabled)
        (hold, dock) = make(.on, marker: absent)
        let syncLetGo = letGoOnMain(dock) { hold.syncWithPreferences() }
        suite.expect(syncLetGo.heldUntilMain,
                     "a sync that finds rearranging back on leaves the marker and the toggle until the main thread lets go")
        suite.expect(syncLetGo.markerOnMain == true && syncLetGo.toggleOnMain == true
                     && defaults.object(forKey: marker) == nil && !defaults.bool(forKey: enabled)
                     && dock.events.isEmpty && dock.value == .on,
                     "a sync that finds rearranging back on clears the marker and turns the feature off on the main thread")

        defaults.set(true, forKey: enabled)
        (hold, dock) = make(.off, marker: absent)
        dock.value = .on
        let checkHold = hold
        let checkDone = DispatchSemaphore(value: 0)
        var checkLetGo = false
        let checkLetGoResult = letGoOnMain(dock) {
            DispatchQueue.global().async {
                checkLetGo = checkHold.letGoIfRearrangingReturned()
                checkDone.signal()
            }
        }
        suite.expect(checkLetGoResult.heldUntilMain,
                     "the check run off the main thread leaves the marker and the toggle until the main thread lets go")
        suite.expect(checkDone.wait(timeout: .now() + 3) == .success && checkLetGo
                     && checkLetGoResult.markerOnMain == true && checkLetGoResult.toggleOnMain == true
                     && defaults.object(forKey: marker) == nil && !defaults.bool(forKey: enabled)
                     && dock.events.isEmpty && dock.value == .on,
                     "the check run off the main thread clears the marker and turns the feature off on the main thread")
        defaults.removeObject(forKey: enabled)
        defaults.removeObject(forKey: available)

        // MARK: Managed settings

        for wanted in [true, false] {
            (hold, dock) = make(.unsupported)
            suite.expect(hold.reconcile(wanted: wanted) && dock.events.isEmpty
                         && defaults.object(forKey: marker) == nil,
                         "a managed setting is never changed and never marked (wanted: \(wanted))")
        }

        // MARK: Following the toggle and the hub

        // A feature's keys survive its removal from the hub, so the toggle
        // alone must never keep rearranging off.
        func waitForMarker(_ expected: String?) -> Bool {
            let deadline = Date().addingTimeInterval(3)
            while defaults.string(forKey: marker) != expected, Date() < deadline { usleep(10_000) }
            return defaults.string(forKey: marker) == expected
        }
        defaults.set(true, forKey: DefaultsKey.spacesOrderEnabled)
        defaults.set(true, forKey: available)
        (hold, dock) = make(.absent)
        hold.syncWithPreferences()
        suite.expect(dock.signals.wait(timeout: .now() + 3) == .success
                     && dock.events == ["live(false)"] && defaults.string(forKey: marker) == absent,
                     "an installed feature with its toggle on keeps Spaces in place")
        defaults.set(false, forKey: available)
        (hold, dock) = make(.off, marker: absent)
        hold.syncWithPreferences()
        suite.expect(dock.signals.wait(timeout: .now() + 3) == .success
                     && dock.signals.wait(timeout: .now() + 3) == .success
                     && waitForMarker(nil)
                     && dock.events == ["live(true)", "write(nil)"],
                     "uninstalling the feature restores the setting even with its toggle still on")
        defaults.removeObject(forKey: DefaultsKey.spacesOrderEnabled)
        defaults.removeObject(forKey: available)

        // MARK: Catalog

        let feature = AppFeature.spacesOrder
        suite.expect(feature.group == .windowsDock && feature.enabledKeys == [DefaultsKey.spacesOrderEnabled]
                     && feature.permissions.isEmpty && feature.energyProfile == .idle && !feature.isBeta,
                     "fixed Space order is an idle feature in the window and Dock group that needs no permission")
        suite.expect(feature.settingsDestination == FeatureSettingsDestination(.dock, sectionAnchor: .spacesOrder)
                     && SettingsSectionAnchor.spacesOrder.page == .dock
                     && FeatureVisibilitySupport.features(for: .dock).contains(.spacesOrder),
                     "fixed Space order has its own card on the Dock page")
        suite.expect(FeaturePreset.allCases.allSatisfy {
                         !$0.features.contains(.spacesOrder)
                             && !$0.enableKeys.contains(DefaultsKey.spacesOrderEnabled)
                     },
                     "no preset installs or turns on a feature that can restart the Dock")
        suite.expect(SettingsBackupSupport.machineStateKeys.isSuperset(of: [marker, restartPending])
                     && SettingsBackupSupport.exportKeys().isDisjoint(with: [marker, restartPending]),
                     "the restore marker and an owed restart belong to this Mac and never travel in a backup")
    }
}
