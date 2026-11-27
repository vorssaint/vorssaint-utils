// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

@MainActor
enum LidLogoCompletionCueTests {
    static func run(_ suite: TestSuite) {
        preferences(suite)
        doublePulse(suite)
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let journal = folder.appendingPathComponent("lid-logo-restore")
        let driver = Driver(journal: journal)
        var anotherControllerRunning = true
        let cue = LidLogoCompletionCue(driver: { driver }, journal: journal,
                                       mayControlLogo: { !anotherControllerRunning })

        cue.play(.single)
        suite.expect(driver.fades == 0 && !driver.hasJournal, "a competing logo controller takes priority")
        anotherControllerRunning = false
        driver.canFade = false
        cue.play(.single)
        suite.expect(driver.fades == 0 && !driver.hasJournal, "an unavailable fade leaves the hardware alone")

        driver.canFade = true
        cue.play(.single)
        suite.expect(driver.fades == 1 && driver.recordedBeforeFade,
                     "the logo cue records recovery before changing the light")
        cue.play(.single)
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

    private static func doublePulse(_ suite: TestSuite) {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let journal = folder.appendingPathComponent("lid-logo-restore")

        let driver = Driver(journal: journal)
        let cue = LidLogoCompletionCue(driver: { driver }, journal: journal, mayControlLogo: { true })
        cue.play(.double)
        cue.play(.double)
        suite.expect(driver.fades == 1, "another completion cannot restart a double pulse")
        suite.expect(waitUntil { driver.fades == 2 } && driver.restores == [0.85] && driver.hasJournal,
                     "the second dip starts after the first return, with recovery still recorded")
        suite.expect(waitUntil { !driver.hasJournal } && driver.restores == [0.85, 0.85],
                     "the full double pulse restores and clears its journal")

        let cancelled = LidLogoCompletionCue(driver: { driver }, journal: journal, mayControlLogo: { true })
        cancelled.play(.double)
        suite.expect(waitUntil { driver.restores.count == 3 },
                     "the first return has started before cancellation")
        cancelled.cancel()
        suite.expect(waitUntil { !driver.hasJournal } && driver.fades == 3 && driver.restores.last == 0,
                     "canceling the first return restores without scheduling a second dip")

        let unsettled = LidLogoCompletionCue(driver: { driver }, journal: journal, mayControlLogo: { true })
        unsettled.play(.double)
        driver.baselineAvailable = false
        suite.expect(waitUntil { driver.restores.count == 5 }, "the unsettled first dip still attempts to return")
        let readbacks = driver.baselineChecks
        suite.expect(waitUntil { driver.baselineChecks > readbacks } && driver.hasJournal && driver.fades == 4,
                     "a failed brightness readback keeps recovery and skips the second dip")
        driver.baselineAvailable = true
        unsettled.recover()
        suite.expect(waitUntil { !driver.hasJournal }, "recovery can settle the light after the failed readback")

        var anotherControllerRunning = false
        let contested = LidLogoCompletionCue(driver: { driver }, journal: journal,
                                             mayControlLogo: { !anotherControllerRunning })
        contested.play(.double)
        suite.expect(waitUntil { driver.restores.count == 7 },
                     "the first return has started before another controller starts")
        anotherControllerRunning = true
        suite.expect(waitUntil { !driver.hasJournal } && driver.fades == 5,
                     "a competing controller prevents the second dip after a verified return")

        let interrupted = LidLogoCompletionCue(driver: { driver }, journal: journal, mayControlLogo: { true })
        interrupted.play(.double)
        suite.expect(waitUntil { driver.fades == 7 }, "the second dip has started before cancellation")
        interrupted.cancel()
        suite.expect(waitUntil { !driver.hasJournal } && driver.fades == 7 && driver.restores.last == 0,
                     "canceling the second dip restores and clears the recovery record")
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
        suite.expect(NotchAgentSupport.lidLogoPattern(in: defaults) == .single
                        && Defaults.registeredDefaults[DefaultsKey.notchAgentsLidLogoPattern] as? String == "single",
                     "existing preferences and the registered default give one pulse")
        defaults.set("unknown", forKey: DefaultsKey.notchAgentsLidLogoPattern)
        suite.expect(NotchAgentSupport.lidLogoPattern(in: defaults) == .single,
                     "unknown values fall back to one pulse")
        defaults.set("double", forKey: DefaultsKey.notchAgentsLidLogoPattern)
        suite.expect(NotchAgentSupport.lidLogoPattern(in: defaults) == .double
                        && SettingsBackupSupport.exportKeys().contains(DefaultsKey.notchAgentsLidLogoPattern),
                     "the double pulse setting is read back and portable")
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
        var fades = 0
        var recordedBeforeFade = false
        var restores: [Double] = []
        var hasJournal: Bool { FileManager.default.fileExists(atPath: journal.path) }

        init(journal: URL) { self.journal = journal }

        func fadeOut() -> Bool {
            fades += 1
            recordedBeforeFade = hasJournal
            return true
        }

        func restore(duration: Double) -> Bool {
            restores.append(duration)
            return restoreSucceeds
        }
    }
}
