// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit

/// Run the production launch gates, close callbacks and completion writes with
/// isolated preferences and an explicit queue. No app windows become visible.
enum UpdateIntroFlowTests {
    enum AppInfo {
        static var version = "3.4.0"
        static var isBeta: Bool { version.contains("beta") }
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
        for version in ["3.4.0", "3.4.1", "3.4.2"] {
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
        for version in ["3.4.0", "3.4.1", "3.4.2"] {
            let clean = reset(version)
            clean.markOnboardingComplete()
            AppInfo.version = "3.4.10"
            clean.presentUpdateIntros()
            suite.expect(clean.shown == ["finished"], "fresh stable onboarding does not repeat introductions after a hotfix")
        }
        let partial = reset("3.4.0")
        partial.presentUpdateIntros()
        close(partial.updateHighlightsWindow, in: partial)
        partial.isTerminating = true
        close(partial.supportIntroWindow, in: partial)
        AppInfo.version = "3.4.1"
        let resumed = Host()
        resumed.presentUpdateIntros()
        suite.expect(resumed.shown == ["support"], "a hotfix resumes only the unfinished support page")
        close(resumed.supportIntroWindow, in: resumed)
        AppInfo.version = "3.4.2"
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
    }
}
