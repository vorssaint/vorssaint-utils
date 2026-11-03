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
    enum WindowActivationPolicy {
        static var retention = WindowActivationRetention()
        static var history: [Int] = []
        static func retain() {
            _ = retention.retain()
            history.append(retention.count)
        }
        static func release() {
            _ = retention.release()
            history.append(retention.count)
        }
    }
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
        var updateWindowsKeepingAppRegular = Set<ObjectIdentifier>()
        var settingsFloatsForWhatsNew = false
        var configureUpdateWindow: ((NSWindow) -> Void)?
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
            configureUpdateWindow?(whatsNewWindow!)
            shown.append("whatsNew \(previous)")
            return true
        }
        func showSupportUpdateIntro(isReview: Bool = false) {
            guard !isTerminating, isReview || !AppInfo.isBeta else { return }
            supportIntroIsReview = isReview
            supportIntroWindow = NSPanel()
            configureUpdateWindow?(supportIntroWindow!)
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
            WindowActivationPolicy.retention = WindowActivationRetention()
            WindowActivationPolicy.history = []
            let host = Host()
            host.configureUpdateWindow = { [weak host] window in host?.keepUpdateWindowReachable(window) }
            return host
        }
        func close(_ window: NSWindow?, in host: Host) {
            guard let window else { suite.expect(false, "the expected intro exists"); return }
            host.windowWillClose(Notification(name: NSWindow.willCloseNotification, object: window))
            DispatchQueue.main.drain()
            suite.expect(DispatchQueue.main.jobs.isEmpty, "intro transitions settle without a loop")
        }
        for version in ["3.4.3", "3.4.4"] {
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
                for nextVersion in [version, "3.4.20", "3.4.21"] {
                    AppInfo.version = nextVersion
                    let relaunch = Host()
                    relaunch.presentUpdateIntros()
                    suite.expect(relaunch.shown == ["finished"], "completed intros never repeat on relaunch or later hotfixes")
                }
            }
        }
        // Someone who finished both intros in 3.4.2 gets the next support
        // page on 3.4.3, once.
        let seenIn342 = reset("3.4.3")
        UserDefaults.standard.set(UpdateHighlightsInfo.releaseVersion, forKey: DefaultsKey.updateHighlightsSeenVersion)
        UserDefaults.standard.set("3.4.2-support", forKey: DefaultsKey.supportUpdateIntroVersion)
        seenIn342.presentUpdateIntros()
        suite.expect(seenIn342.shown == ["support"], "3.4.2 users see the next support page in 3.4.3")
        seenIn342.supportIntroCanClose = true
        close(seenIn342.supportIntroWindow, in: seenIn342)
        AppInfo.version = "3.4.4"
        let afterSupport = Host()
        afterSupport.presentUpdateIntros()
        suite.expect(afterSupport.shown == ["finished"], "the next support page does not repeat in later patches")

        let beta = reset("3.4.0-beta.7")
        beta.markOnboardingComplete()
        suite.expect(UserDefaults.standard.string(forKey: DefaultsKey.supportUpdateIntroVersion) == nil,
                     "beta onboarding cannot consume the future stable support screen")
        AppInfo.version = "3.4.3"
        let upgraded = Host()
        upgraded.presentUpdateIntros()
        close(upgraded.updateHighlightsWindow, in: upgraded)
        suite.expect(upgraded.shown == ["tour", "support"], "a fresh beta install gets both intros on stable upgrade")

        for version in ["3.4.0-beta.7", "3.4.0", "3.4.2"] {
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
        for version in ["3.4.3", "3.4.4"] {
            let clean = reset(version)
            clean.markOnboardingComplete()
            AppInfo.version = "3.4.20"
            clean.presentUpdateIntros()
            suite.expect(clean.shown == ["finished"], "fresh stable onboarding does not repeat introductions after a hotfix")
        }
        let partial = reset("3.4.3")
        partial.presentUpdateIntros()
        close(partial.updateHighlightsWindow, in: partial)
        partial.isTerminating = true
        close(partial.supportIntroWindow, in: partial)
        AppInfo.version = "3.4.4"
        let resumed = Host()
        resumed.presentUpdateIntros()
        suite.expect(resumed.shown == ["support"], "a hotfix resumes only the unfinished support page")
        close(resumed.supportIntroWindow, in: resumed)
        AppInfo.version = "3.4.20"
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

        runWindowReachability(suite, reset: reset, close: close)
        runWhatsNew(suite, domain: domain, reset: reset, close: close)
    }

    private static func runWindowReachability(_ suite: TestSuite, reset: (String) -> Host,
                                              close: (NSWindow?, Host) -> Void) {
        let host = reset("3.4.3")
        host.showWhatsNew(from: "3.4.2", isReview: true)
        let tour = host.whatsNewWindow!
        host.keepUpdateWindowReachable(tour)
        suite.expect(WindowActivationPolicy.retention.count == 1,
                     "reopening the same tour retains Dock presence only once")
        suite.expect(tour.level == .floating && tour.level.rawValue < NSWindow.Level.modalPanel.rawValue,
                     "the tour floats above ordinary windows without using a modal or overlay level")
        suite.expect(!tour.hidesOnDeactivate && !tour.canHide
                        && tour.collectionBehavior.contains(.participatesInCycle)
                        && !tour.collectionBehavior.contains(.ignoresCycle),
                     "the tour stays visible and participates in window cycling")
        host.settingsWindow = NSWindow()
        host.settingsWindow!.level = .floating
        host.settingsFloatsForWhatsNew = true
        close(tour, host)
        suite.expect(WindowActivationPolicy.history == [1, 2, 1],
                     "the support handoff keeps the Dock and Command Tab entry continuously available")
        suite.expect(host.settingsWindow?.level == .normal && !host.settingsFloatsForWhatsNew,
                     "closing the tour restores any temporarily raised Settings window")
        let support = host.supportIntroWindow!
        suite.expect(support.level == .floating && !support.hidesOnDeactivate && !support.canHide
                        && support.collectionBehavior.contains(.participatesInCycle),
                     "the support panel also stays visible and participates in window cycling")
        close(tour, host)
        suite.expect(WindowActivationPolicy.retention.count == 1,
                     "a duplicate close cannot release the next window's activation")
        close(support, host)
        suite.expect(WindowActivationPolicy.retention.count == 0 && host.updateWindowsKeepingAppRegular.isEmpty,
                     "closing the final preview restores the menu-bar-only lifecycle")

        let withSettings = reset("3.4.3")
        withSettings.showWhatsNew(from: "3.4.2", isReview: true)
        withSettings.settingsWindow = NSWindow()
        withSettings.settingsKeepsAppRegular = true
        WindowActivationPolicy.retain()
        withSettings.settingsWindow!.level = .floating
        withSettings.settingsFloatsForWhatsNew = true
        close(withSettings.settingsWindow, withSettings)
        suite.expect(WindowActivationPolicy.retention.count == 1
                        && withSettings.settingsWindow?.level == .normal,
                     "closing Settings restores its level without removing the tour from Command Tab")
        withSettings.isTerminating = true
        close(withSettings.whatsNewWindow, withSettings)
        suite.expect(WindowActivationPolicy.retention.count == 0 && withSettings.supportIntroWindow == nil,
                     "termination releases the tour without opening or retaining support")
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

        let stable = reset("3.4.3")
        UserDefaults.standard.set(UpdateHighlightsInfo.releaseVersion, forKey: DefaultsKey.updateHighlightsSeenVersion)
        UserDefaults.standard.set("3.4.2-support", forKey: DefaultsKey.supportUpdateIntroVersion)
        launch(stable, previous: "3.4.2")
        suite.expect(stable.shown == ["whatsNew 3.4.2"], "an update opens What's New before every other intro")
        close(stable.whatsNewWindow, stable)
        suite.expect(stable.shown == ["whatsNew 3.4.2", "support"], "the next support page follows What's New even after the old invitation was seen")
        suite.expect(UserDefaults.standard.string(forKey: pendingKey) == nil
                        && UserDefaults.standard.string(forKey: DefaultsKey.whatsNewSeenVersion) == "3.4.3",
                     "closing What's New consumes the update")
        suite.expect(UserDefaults.standard.string(forKey: DefaultsKey.whatsNewKnownFeatures)
                        == WhatsNewInfo.knownFeaturesValue,
                     "closing What's New records the features this version has")
        stable.supportIntroCanClose = true
        close(stable.supportIntroWindow, stable)
        let relaunch = Host()
        launch(relaunch, previous: "3.4.3")
        suite.expect(relaunch.shown == ["finished"], "What's New never repeats for the same update")

        let olderUpgrade = reset("3.4.3")
        launch(olderUpgrade, previous: "3.3.2")
        close(olderUpgrade.whatsNewWindow, olderUpgrade)
        suite.expect(olderUpgrade.shown == ["whatsNew 3.3.2", "tour"],
                     "an unseen feature tour follows the changelog before support")
        close(olderUpgrade.updateHighlightsWindow, olderUpgrade)
        suite.expect(olderUpgrade.shown == ["whatsNew 3.3.2", "tour", "support"],
                     "support follows both the changelog and the pending feature tour")

        let beta = reset("3.4.3-beta.1")
        UserDefaults.standard.set("3.4.0", forKey: DefaultsKey.updateHighlightsSeenVersion)
        launch(beta, previous: "3.4.2")
        suite.expect(beta.shown == ["whatsNew 3.4.2"], "beta updates open What's New too")
        close(beta.whatsNewWindow, beta)
        suite.expect(beta.shown == ["whatsNew 3.4.2", "finished"], "a beta skips the stable-only intros after it")

        let interrupted = reset("3.4.2")
        launch(interrupted, previous: "3.4.0")
        interrupted.isTerminating = true
        close(interrupted.whatsNewWindow, interrupted)
        suite.expect(interrupted.shown == ["whatsNew 3.4.0"]
                        && UserDefaults.standard.string(forKey: pendingKey) == "3.4.0",
                     "quitting during What's New keeps it for the next launch and opens nothing else")
        AppInfo.version = "3.4.3"
        let secondUpdate = Host()
        launch(secondUpdate, previous: "3.4.2")
        suite.expect(secondUpdate.shown == ["whatsNew 3.4.0"],
                     "a second update before the window was read keeps the older start")

        let skippedStart = reset("3.4.2")
        // A start that does not finish queues the update but opens nothing.
        skippedStart.queueWhatsNewIfNeeded(previousVersion: "3.4.0")
        UserDefaults.standard.set(AppInfo.version, forKey: DefaultsKey.lastUpdateIntroVersion)
        let nextStart = Host()
        launch(nextStart, previous: "3.4.2")
        suite.expect(nextStart.shown.first == "whatsNew 3.4.0", "an interrupted start still shows What's New later")

        let downgraded = reset("3.4.2")
        launch(downgraded, previous: "3.4.0")
        AppInfo.version = "3.4.0"
        let older = Host()
        older.queueWhatsNewIfNeeded(previousVersion: "3.4.2")
        suite.expect(UserDefaults.standard.string(forKey: pendingKey) == nil, "a downgrade drops the waiting window")

        for previous in [nil, "", "dev", "3.4.2", "3.5.0"] as [String?] {
            let host = reset("3.4.2")
            host.queueWhatsNewIfNeeded(previousVersion: previous)
            suite.expect(UserDefaults.standard.string(forKey: pendingKey) == nil,
                         "no update from \(previous ?? "nil") queues nothing")
        }

        let developer = reset("3.4.2")
        AppInfo.isDeveloperBuild = true
        developer.queueWhatsNewIfNeeded(previousVersion: "3.4.0")
        AppInfo.isDeveloperBuild = false
        suite.expect(UserDefaults.standard.string(forKey: pendingKey) == nil,
                     "the Developer build never queues What's New on its own")

        let nothingForYou = reset("3.4.3")
        UserDefaults.standard.set(UpdateHighlightsInfo.releaseVersion, forKey: DefaultsKey.updateHighlightsSeenVersion)
        nothingForYou.whatsNewHasContent = false
        launch(nothingForYou, previous: "3.4.0")
        suite.expect(nothingForYou.shown == ["support"] && UserDefaults.standard.string(forKey: pendingKey) == nil,
                     "an update with nothing for this Mac skips What's New and consumes it")

        let optedOut = reset("3.4.3")
        UserDefaults.standard.set(UpdateHighlightsInfo.releaseVersion, forKey: DefaultsKey.updateHighlightsSeenVersion)
        UserDefaults.standard.set(false, forKey: DefaultsKey.releaseNotesOnUpdate)
        launch(optedOut, previous: "3.4.0")
        suite.expect(optedOut.shown == ["support"] && UserDefaults.standard.string(forKey: pendingKey) == nil,
                     "with What's New turned off the update counts as read and the next intro follows")

        let fresh = reset("3.4.3")
        fresh.markOnboardingComplete()
        // A backup made on an older version restores that version's marker.
        fresh.queueWhatsNewIfNeeded(previousVersion: "3.4.0")
        suite.expect(UserDefaults.standard.string(forKey: pendingKey) == nil,
                     "restoring an older backup after onboarding is not an update")

        let onboarding = reset("3.4.2")
        UserDefaults.standard.set("3.4.0", forKey: pendingKey)
        onboarding.markOnboardingComplete()
        suite.expect(UserDefaults.standard.string(forKey: pendingKey) == "3.4.0",
                     "reviewing the intro leaves a waiting What's New alone")
        suite.expect(UserDefaults.standard.string(forKey: DefaultsKey.whatsNewKnownFeatures)
                        == WhatsNewInfo.knownFeaturesValue,
                     "onboarding records the features it offered")

        for version in ["3.4.3-beta.2", "3.4.3", "3.5.0"] {
            let review = reset(version)
            let before = UserDefaults.standard.persistentDomain(forName: domain) ?? [:]
            review.showWhatsNew(from: "3.4.2", includeUnreleased: true, isReview: true)
            close(review.whatsNewWindow, review)
            suite.expect(review.shown == ["whatsNew 3.4.2", "support"] && review.supportIntroIsReview,
                         "closing a changelog preview opens the support preview on any build")
            close(review.supportIntroWindow, review)
            suite.expect(NSDictionary(dictionary: before).isEqual(
                            to: UserDefaults.standard.persistentDomain(forName: domain) ?? [:]),
                         "neither preview consumes automatic launch markers")
        }
        let quittingReview = reset("3.4.3-beta.2")
        quittingReview.showWhatsNew(from: "3.4.2", includeUnreleased: true, isReview: true)
        quittingReview.isTerminating = true
        close(quittingReview.whatsNewWindow, quittingReview)
        suite.expect(quittingReview.shown == ["whatsNew 3.4.2"],
                     "quitting the app during the changelog preview never opens support")
    }
}
