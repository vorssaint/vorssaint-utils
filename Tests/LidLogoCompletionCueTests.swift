// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import IOKit

@MainActor
enum LidLogoCompletionCueTests {
    static func run(_ suite: TestSuite) {
        preferences(suite)
        unsupportedHardware(suite)
        unavailableDuringStart(suite)
        resumesRecoveryAfterControllerQuits(suite)
        doublePulse(suite)
        unseenCompletions(suite)
        reminders(suite)
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let journal = folder.appendingPathComponent("lid-logo-restore")
        let driver = Driver(journal: journal)
        var anotherControllerRunning = true
        let cue = LidLogoCompletionCue(driver: { driver }, journal: journal,
                                       mayControlLogo: { !anotherControllerRunning })

        cue.play()
        suite.expect(driver.fades == 0 && !driver.hasJournal, "a competing logo controller takes priority")
        anotherControllerRunning = false
        driver.canFade = false
        cue.play()
        suite.expect(driver.fades == 0 && !driver.hasJournal, "an unavailable fade leaves the hardware alone")

        driver.canFade = true
        cue.play()
        suite.expect(driver.fades == 1 && driver.recordedBeforeFade,
                     "the logo cue records recovery before changing the light")
        cue.play()
        suite.expect(driver.fades == 1, "coincident notices do not restart an active cue")

        driver.isAwake = false
        cue.cancel()
        suite.expect(driver.restores.isEmpty && driver.hasJournal, "sleep keeps the recovery record for a later wake")
        driver.isAwake = true
        driver.restoreSucceeds = false
        cue.recover()
        suite.expect(driver.restores == [0] && driver.hasJournal, "a failed restore leaves the recovery record")

        driver.restoreSucceeds = true
        let relaunched = LidLogoCompletionCue(driver: { driver }, journal: journal, mayControlLogo: { true })
        relaunched.recover()
        suite.expect(driver.restores == [0, 0], "a fresh controller can recover an interrupted cue")
    }

    private static func unsupportedHardware(_ suite: TestSuite) {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let journal = folder.appendingPathComponent("lid-logo-restore")
        let cue = LidLogoCompletionCue(driver: { nil }, journal: journal, mayControlLogo: { true })
        cue.play()
        cue.play(repeatReminders: true)
        cue.cancel()
        suite.expect(!FileManager.default.fileExists(atPath: folder.path),
                     "an imported opt-in setting on an unsupported Mac creates no recovery state")

        // On hosted macOS runners this exercises the actual absent-device gate.
        let device = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceNameMatching("bklb-backlight"))
        if device == IO_OBJECT_NULL {
            suite.expect(!LidLogoCompletionCue.isSupported, "a Mac without the logo device reports no cue support")
        } else {
            IOObjectRelease(device)
        }
    }

    private static func unavailableDuringStart(_ suite: TestSuite) {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let journal = folder.appendingPathComponent("lid-logo-restore")
        let driver = Driver(journal: journal)
        driver.fadeResult = .unavailable
        let cue = LidLogoCompletionCue(driver: { driver }, journal: journal, mayControlLogo: { true })
        cue.play(repeatReminders: true)
        suite.expect(driver.fades == 1 && driver.restores.isEmpty && !driver.hasJournal,
                     "hardware lost after preflight produces neither a restore write nor a lingering record")
    }

    private static func resumesRecoveryAfterControllerQuits(_ suite: TestSuite) {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let journal = folder.appendingPathComponent("lid-logo-restore")
        let driver = Driver(journal: journal)
        let center = NotificationCenter()
        var anotherControllerRunning = false
        let cue = LidLogoCompletionCue(driver: { driver }, journal: journal,
                                       mayControlLogo: { !anotherControllerRunning }, recoveryCenter: center)
        cue.play(repeatReminders: true)
        anotherControllerRunning = true
        cue.cancel()
        suite.expect(driver.hasJournal && driver.restores.isEmpty,
                     "a competing controller delays recovery rather than receiving overlapping writes")
        anotherControllerRunning = false
        center.post(name: NSWorkspace.didTerminateApplicationNotification, object: nil)
        suite.expect(waitUntil { !driver.hasJournal } && driver.restores == [0] && driver.fades == 1,
                     "quitting the competing app retries recovery without a reminder")
    }

    private static func doublePulse(_ suite: TestSuite) {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let journal = folder.appendingPathComponent("lid-logo-restore")
        let driver = Driver(journal: journal)
        let timing = LidLogoCompletionCue.Timing(dim: 0.02, brighten: 0.03, settle: 0.02)
        let cue = LidLogoCompletionCue(driver: { driver }, journal: journal, mayControlLogo: { true }, timing: timing)
        cue.play()
        suite.expect(driver.dims == [0.02] && driver.hasJournal,
                     "the first pulse starts fading down with recovery armed")
        suite.expect(waitUntil { driver.finishedRestores == 2 } && driver.restores == [0.03, 0.03]
                        && driver.fades == 2 && !driver.hasJournal,
                     "a completion fades down and restores twice, verifying the baseline after each pulse")
        cue.cancel()
    }

    private static func unseenCompletions(_ suite: TestSuite) {
        let first = NotchAgentCompletion(provider: .codex, project: "first", date: Date())
        let second = NotchAgentCompletion(provider: .claude, project: "second", date: Date())
        let third = NotchAgentCompletion(provider: .codex, project: "third", date: Date())
        var completions = NotchAgentCompletions()
        completions.append(first)
        completions.append(second)
        suite.expect(completions.items.map(\.id) == [second.id, first.id] && completions.hasUnseen,
                     "independent finishes all remain available in newest-first order")
        suite.expect(completions.acknowledge(second.id) && !completions.acknowledge(second.id)
                        && completions.hasUnseen,
                     "viewing one row does not acknowledge another row")
        completions.append(third)
        completions.discardViewed()
        suite.expect(completions.items.map(\.id) == [third.id, first.id],
                     "a newly arrived completion and unseen overflow survive closing the page")
        completions.acknowledge(first.id)
        completions.acknowledge(third.id)
        suite.expect(!completions.hasUnseen, "viewing the final unread row clears unseen work")
        completions.discardViewed()
        completions.append(second)
        suite.expect(completions.hasUnseen && completions.items == [second],
                     "a later finish is unseen again")
    }

    private static func workingPreemption(_ suite: TestSuite) {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let journal = folder.appendingPathComponent("lid-logo-restore")
        let driver = Driver(journal: journal)
        let timing = LidLogoCompletionCue.Timing(dim: 0.02, brighten: 0.03, settle: 0.02)
        let cue = LidLogoCompletionCue(driver: { driver }, journal: journal, mayControlLogo: { true }, timing: timing)

        driver.canFade = false
        suite.expect(cue.playWorkingBreath(timing: timing) == .unavailable && driver.fades == 0,
                     "an unavailable logo reports a different outcome than completion contention")
        driver.canFade = true
        suite.expect(cue.playWorkingBreath(timing: timing) == .started, "the working breath can claim idle hardware")
        cue.cancelCompletion()
        suite.expect(driver.restores.isEmpty, "turning off completion effects leaves a working breath in progress")
        cue.play()
        suite.expect(driver.restores == [0.4] && cue.playWorkingBreath(timing: timing) == .busy,
                     "a completion eases out of a working breath before claiming the logo")
        suite.expect(waitUntil { driver.finishedRestores == 3 } && driver.restores == [0.4, 0.03, 0.03]
                        && driver.dims == [11, 0.02, 0.02] && !driver.hasJournal,
                     "the shorter working fade reverses, followed by a full-depth completion pair")
        suite.expect(cue.playWorkingBreath(timing: timing) == .started,
                     "completion cooldown does not block working")
        cue.stopWorkingBreath()
        suite.expect(driver.restores.last == 0.4, "normal working stop eases the logo back up")
        cue.cancel()
        suite.expect(driver.restores.last == 0, "global cancellation restores immediately during a working release")
    }

    private static func reminders(_ suite: TestSuite) {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let journal = folder.appendingPathComponent("lid-logo-restore")
        let driver = Driver(journal: journal)
        let timing = LidLogoCompletionCue.Timing(dim: 0.02, brighten: 0.03, settle: 0.01,
            cooldown: .milliseconds(200), reminderInterval: .milliseconds(460), reminderLifetime: .milliseconds(1100))

        var enabled = true
        let cue = LidLogoCompletionCue(driver: { driver }, journal: journal, mayControlLogo: { true }, timing: timing)
        cue.play(repeatReminders: true, remindersEnabled: { enabled })
        cue.play(repeatReminders: true, remindersEnabled: { enabled })
        suite.expect(waitUntil { driver.finishedRestores == 2 } && driver.fades == 2,
                     "overlapping completions share the initial pair")
        suite.expect(waitUntil { driver.fades == 3 } && driver.hasJournal,
                     "a first reminder begins while an unseen completion remains")
        cue.stopReminders()
        suite.expect(driver.restores.last == 0, "opening AI Agents restores an active reminder")
        cue.play(repeatReminders: true, remindersEnabled: { enabled })
        suite.expect(waitUntil { driver.finishedRestores == 5 } && driver.fades == 5 && !driver.hasJournal,
                     "a new finish queues a fresh pair even during completion cooldown")
        spin(for: 1.08)
        suite.expect(driver.fades == 9 && !driver.hasJournal,
                     "a later finish rearms reminders and they expire after the bounded window")

        enabled = true
        cue.play(repeatReminders: true, remindersEnabled: { enabled })
        enabled = false
        spin(for: 0.58)
        suite.expect(driver.fades == 11 && !driver.hasJournal,
                     "a changed preference is checked before the next hardware write")

        cue.play(repeatReminders: true)
        driver.isAwake = false
        cue.cancel()
        spin(for: 0.30)
        suite.expect(driver.fades == 12 && driver.hasJournal, "sleep cancels reminders and leaves recovery pending")
        driver.isAwake = true
        cue.recover()
        suite.expect(waitUntil { !driver.hasJournal }, "wake restores before any new cue")
        spin(for: 0.30)
        suite.expect(driver.fades == 12, "wake does not replay missed reminders")

        let overflow = LidLogoCompletionCue(driver: { driver }, journal: journal,
                                             mayControlLogo: { true }, timing: timing)
        let priorFades = driver.fades
        overflow.play(repeatReminders: true, remindersEnabled: { true })
        suite.expect(waitUntil { driver.fades == priorFades + 2 }, "the original finish starts its pair")
        overflow.stopReminders()
        spin(for: 0.60)
        suite.expect(driver.fades == priorFades + 2 && !driver.hasJournal,
                     "opening and leaving AI Agents permanently stops that stream even with unread overflow")

        suite.expect(LidLogoCompletionCue.Timing().reminderLifetime == .seconds(30 * 60),
                     "completion reminders remain eligible for 30 minutes")
    }

    private static func spin(for seconds: TimeInterval) {
        RunLoop.current.run(until: Date().addingTimeInterval(seconds))
    }

    private static func waitUntil(_ predicate: () -> Bool) -> Bool {
        let deadline = Date().addingTimeInterval(3)
        while !predicate() && Date() < deadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.015))
        }
        return predicate()
    }

    private static func preferences(_ suite: TestSuite) {
        let domain = "com.vorssaint.tests.lid-cue." + UUID().uuidString
        let defaults = UserDefaults(suiteName: domain)!
        defer { defaults.removePersistentDomain(forName: domain) }
        for (key, value) in Defaults.registeredDefaults where key.hasPrefix("notch") {
            defaults.set(value, forKey: key)
        }
        defaults.set(true, forKey: AppFeature.notch.availabilityKey)
        defaults.set(true, forKey: AppFeature.notchAgents.availabilityKey)
        defaults.set(true, forKey: DefaultsKey.notchEnabled)
        defaults.set(true, forKey: DefaultsKey.notchAgentsEnabled)
        defaults.set(60.0, forKey: DefaultsKey.notchAgentsFinishMinimum)
        suite.expect(!NotchAgentSupport.shouldPulseLidLogo(after: 60, in: defaults),
                     "finishing by itself does not opt in to the physical cue")
        defaults.set(true, forKey: DefaultsKey.notchAgentsPulseLidLogo)
        suite.expect(NotchAgentSupport.shouldPulseLidLogo(after: 60, in: defaults)
                        && !NotchAgentSupport.shouldPulseLidLogo(after: 59, in: defaults),
                     "the physical cue uses the existing notice duration")
        defaults.set(false, forKey: DefaultsKey.notchAgentsFinishAlert)
        suite.expect(!NotchAgentSupport.shouldPulseLidLogo(after: 90, in: defaults),
                     "turning off completion notices also turns off the physical cue")
        defaults.set(true, forKey: DefaultsKey.notchAgentsFinishAlert)
        defaults.set(false, forKey: AppFeature.notchAgents.availabilityKey)
        suite.expect(!NotchAgentSupport.shouldPulseLidLogo(after: 90, in: defaults),
                     "uninstalling Agents also turns off the physical cue")
        suite.expect(NotchAgentSupport.repeatsLidLogoCue(in: defaults)
                        && Defaults.registeredDefaults[DefaultsKey.notchAgentsRepeatLidLogoCue] as? Bool == true,
                     "reminders are on by default after opting into the lid cue")
        defaults.set(false, forKey: DefaultsKey.notchAgentsRepeatLidLogoCue)
        suite.expect(!NotchAgentSupport.repeatsLidLogoCue(in: defaults)
                        && SettingsBackupSupport.exportKeys().contains(DefaultsKey.notchAgentsRepeatLidLogoCue),
                     "the reminder setting can be disabled and is portable")
        suite.expect(Defaults.registeredDefaults[DefaultsKey.notchAgentsPulseLidLogo] as? Bool == false,
                     "a physical cue is opt-in")
        suite.expect(SettingsBackupSupport.exportKeys().contains(DefaultsKey.notchAgentsPulseLidLogo),
                     "the cue preference is portable")
    }

    private final class Driver: LidLogoFading {
        let journal: URL
        var isAwake = true
        var baselineAvailable = true
        var baselineChecks = 0
        var isAtBaseline: Bool {
            baselineChecks += 1
            return baselineAvailable
        }
        var canFade = true
        var restoreSucceeds = true
        var fadeResult = LidLogoFadeStart.started
        var dims: [Double] = []
        var fades: Int { dims.count }
        var recordedBeforeFade = false
        var restores: [Double] = []
        var finishedRestores = 0
        var hasJournal: Bool { FileManager.default.fileExists(atPath: journal.path) }

        init(journal: URL) { self.journal = journal }

        func fadeOut(duration: Double) -> LidLogoFadeStart {
            dims.append(duration)
            recordedBeforeFade = hasJournal
            return fadeResult
        }

        func restore(duration: Double) -> Bool {
            restores.append(duration)
            return restoreSucceeds
        }

        func finishRestore() -> Bool {
            finishedRestores += 1
            return true
        }
    }
}
