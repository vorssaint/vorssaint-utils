// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit

/// Run the production launch gates, close callbacks and completion writes with
/// isolated preferences and an explicit queue. No app windows become visible.
enum UpdateIntroFlowTests {
    enum AppInfo {
        static var version = "3.4.0"
        static var isBeta: Bool { version.contains("beta") }
        static var isDeveloperBuild = false
    }
    enum UserDefaults { static var standard: Foundation.UserDefaults! }
    enum DispatchQueue {
        static var main = Queue()
        final class Queue {
            var jobs: [() -> Void] = []
            func async(execute action: @escaping () -> Void) { jobs.append(action) }
            func drain() {
                for _ in 0..<20 where !jobs.isEmpty { jobs.removeFirst()() }
            }
        }
    }
    enum WindowActivationPolicy { static func release() {} }
    final class SecureInputMonitor {
        static let shared = SecureInputMonitor()
        func setSettingsWindowOpen(_ open: Bool) {}
    }
    class Fixture {
        var settingsWindow: NSWindow?
        var settingsKeepsAppRegular = false
        var onboardingWindow: NSWindow?
        var supportIntroWindow: NSWindow?
        var supportIntroCanClose = false
        var supportIntroIsReview = false
        var updateHighlightsWindow: NSWindow?
        var updateHighlightsIsReview = false
        var updateShowcaseWindow: NSWindow?
        var updatePreviewWindow: NSWindow?
        var whatsNewWindow: NSWindow?
        var whatsNewIsReview = false
        /// Whether the update touches anything this Mac uses.
        var whatsNewHasContent = true
        var isTerminating = false
        var shown: [String] = []
        func saveSettingsWindowSize(_ window: NSWindow) {}
        func markUpdateShowcaseIntroSeenIfCurrentUpdate() {}
        func markUpdateShowcaseIntroSeen() {}
        func showUpdateShowcaseIntroIfNeeded() -> Bool { false }
        func showBrightnessUpdatePromptIfNeeded() { shown.append("finished") }
        func showUpdateHighlights(isReview: Bool = false) {
            updateHighlightsIsReview = isReview
            updateHighlightsWindow = NSWindow()
            shown.append("tour")
        }
        @discardableResult
        func showWhatsNew(from previous: String, includeUnreleased: Bool = false, isReview: Bool = false) -> Bool {
            guard whatsNewHasContent || isReview else { return false }
            whatsNewIsReview = isReview
            whatsNewWindow = NSWindow()
            shown.append("whatsNew \(previous)")
            return true
        }
        func showSupportUpdateIntro(isReview: Bool = false) {
            guard !isTerminating, isReview || !AppInfo.isBeta else { return }
            supportIntroIsReview = isReview
            supportIntroWindow = NSWindow()
            shown.append("support")
        }
    }

    static func run(_ suite: TestSuite) {
        let domain = "com.vorssaint.tests.update-intros.\(UUID().uuidString)"
        UserDefaults.standard = Foundation.UserDefaults(suiteName: domain)!
        defer {
            UserDefaults.standard.removePersistentDomain(forName: domain)
            UserDefaults.standard = nil
        }
        func reset(_ version: String) -> Host {
            UserDefaults.standard.removePersistentDomain(forName: domain)
            AppInfo.version = version
            DispatchQueue.main = DispatchQueue.Queue()
            return Host()
        }
        func close(_ window: NSWindow?, in host: Host) {
            guard let window else { suite.expect(false, "the expected intro exists"); return }
            host.windowWillClose(Notification(name: NSWindow.willCloseNotification, object: window))
            DispatchQueue.main.drain()
            suite.expect(DispatchQueue.main.jobs.isEmpty, "intro transitions settle without a loop")
        }
        for version in ["3.4.1", "3.4.2"] {
            for previous in [nil, "3.3.2", "3.4.0-beta.1"] as [String?] {
                let host = reset(version)
                UserDefaults.standard.set(previous, forKey: DefaultsKey.updateHighlightsSeenVersion)
                // Older beta onboarding prematurely saved this value.
                UserDefaults.standard.set("3.4.0", forKey: DefaultsKey.supportUpdateIntroVersion)
                host.presentUpdateIntros()
                suite.expect(host.shown == ["tour"], "stable upgraders see the tour first")
                close(host.updateHighlightsWindow, in: host)
                suite.expect(host.shown == ["tour", "support"], "finishing the tour opens only support next")
                suite.expect(!host.windowShouldClose(host.supportIntroWindow!), "support waits for its Done action")
                host.supportIntroCanClose = true
                suite.expect(host.windowShouldClose(host.supportIntroWindow!), "Done allows support to close")
                close(host.supportIntroWindow, in: host)
                for nextVersion in [version, "3.4.10", "3.4.11"] {
                    AppInfo.version = nextVersion
                    let relaunch = Host()
                    relaunch.presentUpdateIntros()
                    suite.expect(relaunch.shown == ["finished"], "completed intros never repeat on relaunch or later hotfixes")
                }
            }
        }
        // Someone who finished both intros in 3.4.0 gets only the support
        // page again on 3.4.1, once.
        let seenIn340 = reset("3.4.1")
        UserDefaults.standard.set(UpdateHighlightsInfo.releaseVersion, forKey: DefaultsKey.updateHighlightsSeenVersion)
        UserDefaults.standard.set("3.4.0-support", forKey: DefaultsKey.supportUpdateIntroVersion)
        seenIn340.presentUpdateIntros()
        suite.expect(seenIn340.shown == ["support"], "3.4.0 users who saw everything see the support page again in 3.4.1")
        seenIn340.supportIntroCanClose = true
        close(seenIn340.supportIntroWindow, in: seenIn340)
        AppInfo.version = "3.4.2"
        let afterSupport = Host()
        afterSupport.presentUpdateIntros()
        suite.expect(afterSupport.shown == ["finished"], "the 3.4.1 support page does not repeat in later patches")

        let beta = reset("3.4.0-beta.7")
        beta.markOnboardingComplete()
        suite.expect(UserDefaults.standard.string(forKey: DefaultsKey.supportUpdateIntroVersion) == nil,
                     "beta onboarding cannot consume the future stable support screen")
        AppInfo.version = "3.4.2"
        let upgraded = Host()
        upgraded.presentUpdateIntros()
        close(upgraded.updateHighlightsWindow, in: upgraded)
        suite.expect(upgraded.shown == ["tour", "support"], "a fresh beta install gets both intros on stable upgrade")

        for version in ["3.4.0-beta.7", "3.4.0", "3.4.1"] {
            let host = reset(version)
            for _ in 0..<3 {
                let before = UserDefaults.standard.persistentDomain(forName: domain) ?? [:]
                host.showUpdateHighlights(isReview: true)
                close(host.updateHighlightsWindow, in: host)
                suite.expect(host.supportIntroIsReview, "manual review includes support even on beta or later releases")
                close(host.supportIntroWindow, in: host)
                suite.expect(host.shown.suffix(2) == ["tour", "support"], "review ends after the support page")
                suite.expect(NSDictionary(dictionary: before).isEqual(to: UserDefaults.standard.persistentDomain(forName: domain) ?? [:]),
                             "manual review never consumes automatic launch markers")
            }
        }
        for version in ["3.4.1", "3.4.2"] {
            let clean = reset(version)
            clean.markOnboardingComplete()
            AppInfo.version = "3.4.10"
            clean.presentUpdateIntros()
            suite.expect(clean.shown == ["finished"], "fresh stable onboarding does not repeat introductions after a hotfix")
        }
        let partial = reset("3.4.1")
        partial.presentUpdateIntros()
        close(partial.updateHighlightsWindow, in: partial)
        partial.isTerminating = true
        close(partial.supportIntroWindow, in: partial)
        AppInfo.version = "3.4.2"
        let resumed = Host()
        resumed.presentUpdateIntros()
        suite.expect(resumed.shown == ["support"], "a hotfix resumes only the unfinished support page")
        close(resumed.supportIntroWindow, in: resumed)
        AppInfo.version = "3.4.10"
        let completed = Host()
        completed.presentUpdateIntros()
        suite.expect(completed.shown == ["finished"], "finishing the remaining page prevents later repeats")
        let interrupted = reset("3.4.0")
        interrupted.presentUpdateIntros()
        interrupted.isTerminating = true
        close(interrupted.updateHighlightsWindow, in: interrupted)
        suite.expect(UserDefaults.standard.string(forKey: DefaultsKey.updateHighlightsSeenVersion) == nil,
                     "quitting during the tour does not consume it")
        let quittingReview = reset("3.4.0-beta.7")
        quittingReview.showUpdateHighlights(isReview: true)
        quittingReview.isTerminating = true
        close(quittingReview.updateHighlightsWindow, in: quittingReview)
        suite.expect(quittingReview.shown == ["tour"], "quitting during review never opens another window")

        runWhatsNew(suite, domain: domain, reset: reset, close: close)
    }

    private static func runWhatsNew(_ suite: TestSuite, domain: String, reset clear: (String) -> Host,
                                     close: (NSWindow?, Host) -> Void) {
        let pendingKey = DefaultsKey.whatsNewPendingVersion
        // The app registers this switch as on; the test domain has no
        // registered defaults, and registering one would outlive this suite.
        func reset(_ version: String) -> Host {
            let host = clear(version)
            UserDefaults.standard.set(true, forKey: DefaultsKey.releaseNotesOnUpdate)
            return host
        }
        func launch(_ host: Host, previous: String?) {
            // The launch reads the last version before it overwrites it.
            host.queueWhatsNewIfNeeded(previousVersion: previous)
            UserDefaults.standard.set(AppInfo.version, forKey: DefaultsKey.lastUpdateIntroVersion)
            host.presentUpdateIntros()
        }

        let stable = reset("3.4.1")
        UserDefaults.standard.set(UpdateHighlightsInfo.releaseVersion, forKey: DefaultsKey.updateHighlightsSeenVersion)
        launch(stable, previous: "3.4.0")
        suite.expect(stable.shown == ["whatsNew 3.4.0"], "an update opens What's New before every other intro")
        close(stable.whatsNewWindow, stable)
        suite.expect(stable.shown == ["whatsNew 3.4.0", "support"], "the support page follows What's New")
        suite.expect(UserDefaults.standard.string(forKey: pendingKey) == nil
                        && UserDefaults.standard.string(forKey: DefaultsKey.whatsNewSeenVersion) == "3.4.1",
                     "closing What's New consumes the update")
        suite.expect(UserDefaults.standard.string(forKey: DefaultsKey.whatsNewKnownFeatures)
                        == WhatsNewInfo.knownFeaturesValue,
                     "closing What's New records the features this version has")
        stable.supportIntroCanClose = true
        close(stable.supportIntroWindow, stable)
        let relaunch = Host()
        launch(relaunch, previous: "3.4.1")
        suite.expect(relaunch.shown == ["finished"], "What's New never repeats for the same update")

        let beta = reset("3.4.2-beta.1")
        UserDefaults.standard.set("3.4.0", forKey: DefaultsKey.updateHighlightsSeenVersion)
        launch(beta, previous: "3.4.1")
        suite.expect(beta.shown == ["whatsNew 3.4.1"], "beta updates open What's New too")
        close(beta.whatsNewWindow, beta)
        suite.expect(beta.shown == ["whatsNew 3.4.1", "finished"], "a beta skips the stable-only intros after it")

        let interrupted = reset("3.4.1")
        launch(interrupted, previous: "3.4.0")
        interrupted.isTerminating = true
        close(interrupted.whatsNewWindow, interrupted)
        suite.expect(interrupted.shown == ["whatsNew 3.4.0"]
                        && UserDefaults.standard.string(forKey: pendingKey) == "3.4.0",
                     "quitting during What's New keeps it for the next launch and opens nothing else")
        AppInfo.version = "3.4.2"
        let secondUpdate = Host()
        launch(secondUpdate, previous: "3.4.1")
        suite.expect(secondUpdate.shown == ["whatsNew 3.4.0"],
                     "a second update before the window was read keeps the older start")

        let skippedStart = reset("3.4.1")
        // A start that does not finish queues the update but opens nothing.
        skippedStart.queueWhatsNewIfNeeded(previousVersion: "3.4.0")
        UserDefaults.standard.set(AppInfo.version, forKey: DefaultsKey.lastUpdateIntroVersion)
        let nextStart = Host()
        launch(nextStart, previous: "3.4.1")
        suite.expect(nextStart.shown.first == "whatsNew 3.4.0", "an interrupted start still shows What's New later")

        let downgraded = reset("3.4.1")
        launch(downgraded, previous: "3.4.0")
        AppInfo.version = "3.4.0"
        let older = Host()
        older.queueWhatsNewIfNeeded(previousVersion: "3.4.1")
        suite.expect(UserDefaults.standard.string(forKey: pendingKey) == nil, "a downgrade drops the waiting window")

        for previous in [nil, "", "dev", "3.4.1", "3.5.0"] as [String?] {
            let host = reset("3.4.1")
            host.queueWhatsNewIfNeeded(previousVersion: previous)
            suite.expect(UserDefaults.standard.string(forKey: pendingKey) == nil,
                         "no update from \(previous ?? "nil") queues nothing")
        }

        let developer = reset("3.4.1")
        AppInfo.isDeveloperBuild = true
        developer.queueWhatsNewIfNeeded(previousVersion: "3.4.0")
        AppInfo.isDeveloperBuild = false
        suite.expect(UserDefaults.standard.string(forKey: pendingKey) == nil,
                     "the Developer build never queues What's New on its own")

        let nothingForYou = reset("3.4.1")
        UserDefaults.standard.set(UpdateHighlightsInfo.releaseVersion, forKey: DefaultsKey.updateHighlightsSeenVersion)
        nothingForYou.whatsNewHasContent = false
        launch(nothingForYou, previous: "3.4.0")
        suite.expect(nothingForYou.shown == ["support"] && UserDefaults.standard.string(forKey: pendingKey) == nil,
                     "an update with nothing for this Mac skips What's New and consumes it")

        let optedOut = reset("3.4.1")
        UserDefaults.standard.set(UpdateHighlightsInfo.releaseVersion, forKey: DefaultsKey.updateHighlightsSeenVersion)
        UserDefaults.standard.set(false, forKey: DefaultsKey.releaseNotesOnUpdate)
        launch(optedOut, previous: "3.4.0")
        suite.expect(optedOut.shown == ["support"] && UserDefaults.standard.string(forKey: pendingKey) == nil,
                     "with What's New turned off the update counts as read and the next intro follows")

        let fresh = reset("3.4.2")
        fresh.markOnboardingComplete()
        // A backup made on an older version restores that version's marker.
        fresh.queueWhatsNewIfNeeded(previousVersion: "3.4.0")
        suite.expect(UserDefaults.standard.string(forKey: pendingKey) == nil,
                     "restoring an older backup after onboarding is not an update")

        let onboarding = reset("3.4.1")
        UserDefaults.standard.set("3.4.0", forKey: pendingKey)
        onboarding.markOnboardingComplete()
        suite.expect(UserDefaults.standard.string(forKey: pendingKey) == "3.4.0",
                     "reviewing the intro leaves a waiting What's New alone")
        suite.expect(UserDefaults.standard.string(forKey: DefaultsKey.whatsNewKnownFeatures)
                        == WhatsNewInfo.knownFeaturesValue,
                     "onboarding records the features it offered")

        let review = reset("3.4.1")
        let before = UserDefaults.standard.persistentDomain(forName: domain) ?? [:]
        review.showWhatsNew(from: "3.4.0", includeUnreleased: true, isReview: true)
        close(review.whatsNewWindow, review)
        suite.expect(review.shown == ["whatsNew 3.4.0"], "a preview opens nothing after it")
        suite.expect(NSDictionary(dictionary: before).isEqual(
                        to: UserDefaults.standard.persistentDomain(forName: domain) ?? [:]),
                     "a preview never consumes launch markers")
    }
}
