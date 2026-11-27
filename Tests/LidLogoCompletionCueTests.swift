// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

@MainActor
enum LidLogoCompletionCueTests {
    static func run(_ suite: TestSuite) {
        preferences(suite)
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
        suite.expect(Defaults.registeredDefaults[DefaultsKey.notchAgentsPulseLidLogo] as? Bool == false,
                     "a physical cue is opt-in")
        suite.expect(SettingsBackupSupport.exportKeys().contains(DefaultsKey.notchAgentsPulseLidLogo),
                     "the cue preference is portable")
    }

    private final class Driver: LidLogoFading {
        let journal: URL
        var isAwake = true
        var isAtBaseline = true
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
