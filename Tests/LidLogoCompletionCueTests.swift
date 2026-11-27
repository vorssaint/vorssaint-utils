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
        slowBreath(suite)
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

    private static func slowBreath(_ suite: TestSuite) {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let journal = folder.appendingPathComponent("lid-logo-restore")
        let driver = Driver(journal: journal)
        let timing = LidLogoCompletionCue.Timing(dim: 0.02, brighten: 0.03, settle: 0.02)
        let cue = LidLogoCompletionCue(driver: { driver }, journal: journal, mayControlLogo: { true }, timing: timing)
        cue.play()
        suite.expect(driver.dims == [0.02] && driver.hasJournal,
                     "the breath starts fading down with recovery armed")
        suite.expect(waitUntil { !driver.hasJournal } && driver.restores == [0.03] && driver.fades == 1
                        && driver.finishedRestores == 1,
                     "one breath fades back up and clears its verified recovery record")
        cue.cancel()
    }

    private static func reminders(_ suite: TestSuite) {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let journal = folder.appendingPathComponent("lid-logo-restore")
        let driver = Driver(journal: journal)
        let timing = LidLogoCompletionCue.Timing(dim: 0.02, brighten: 0.03, settle: 0.02,
            cooldown: .milliseconds(100), reminderInterval: .milliseconds(240), reminderLifetime: .milliseconds(650))

        let cue = LidLogoCompletionCue(driver: { driver }, journal: journal, mayControlLogo: { true }, timing: timing)
        cue.play(repeatReminders: true)
        suite.expect(waitUntil { !driver.hasJournal }, "the initial breath finishes before any reminder")
        cue.play(repeatReminders: true)
        suite.expect(driver.fades == 1, "a second completion shares the pending reminder")
        spin(for: 0.77)
        suite.expect(driver.fades == 3 && driver.restores == [0.03, 0.03, 0.03] && !driver.hasJournal,
                     "reminders end after the original window and every breath restores")

        let acknowledged = LidLogoCompletionCue(driver: { driver }, journal: journal,
                                                mayControlLogo: { true }, timing: timing)
        acknowledged.play(repeatReminders: true)
        suite.expect(waitUntil { driver.fades == 5 } && driver.hasJournal,
                     "one reminder is playing when the user opens AI Agents")
        acknowledged.stopReminders()
        spin(for: 0.54)
        suite.expect(driver.fades == 5 && driver.restores.last == 0 && !driver.hasJournal,
                     "acknowledgment restores an active reminder and prevents the next one")

        var enabled = true
        let disabled = LidLogoCompletionCue(driver: { driver }, journal: journal, mayControlLogo: { true }, timing: timing)
        disabled.play(repeatReminders: true, remindersEnabled: { enabled })
        enabled = false
        spin(for: 0.36)
        suite.expect(driver.fades == 6 && !driver.hasJournal,
                     "a changed preference is checked before the next hardware write")

        let sleeping = LidLogoCompletionCue(driver: { driver }, journal: journal, mayControlLogo: { true }, timing: timing)
        sleeping.play(repeatReminders: true)
        driver.isAwake = false
        sleeping.cancel()
        spin(for: 0.28)
        suite.expect(driver.fades == 7 && driver.hasJournal, "sleep cancels reminders and leaves recovery pending")
        driver.isAwake = true
        sleeping.recover()
        suite.expect(waitUntil { !driver.hasJournal }, "wake restores before any new cue")
        spin(for: 0.28)
        suite.expect(driver.fades == 7, "wake does not replay missed reminders")
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
