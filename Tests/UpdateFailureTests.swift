// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import SwiftUI

/// Isolated preferences and production views; no updater download or app replacement.
enum UpdateFailureTests {
    static func run(_ suite: TestSuite) {
        let domain = "com.vorssaint.tests.update-failure.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: domain)!
        defer { defaults.removePersistentDomain(forName: domain) }
        let store = UpdateFailureStore(defaults: defaults)
        suite.expect(store.restore(currentVersion: "3.4.0") == nil, "a fresh install has no update failure")

        store.beginAttempt(installedVersion: "3.4.0", offeredVersion: "3.4.3")
        let first = store.consume(marker: "fail-verify\n", currentVersion: "3.4.0")
        suite.expect(first?.code == "fail-verify" && first?.attemptedVersion == "3.4.3",
                     "a completed failure preserves the offered version and verification step")
        let restarted = UpdateFailureStore(defaults: UserDefaults(suiteName: domain)!)
        suite.expect(restarted.restore(currentVersion: "3.4.0") == first,
                     "an update failure survives a new store and process preferences instance")
        suite.expect(defaults.string(forKey: DefaultsKey.updateLastInstallFailure) == "fail-verify",
                     "failure presentation retains the installer's existing retry input")
        store.dismiss()
        suite.expect(restarted.restore(currentVersion: "3.4.0")?.dismissed == true,
                     "dismissing the banner survives a restart without removing details")
        store.beginAttempt(installedVersion: "3.4.0", offeredVersion: "3.4.3")
        store.cancelAttempt()
        suite.expect(store.failure?.dismissed == true,
                     "cancelling authorization preserves the previous result and its dismissal")
        suite.expect(defaults.data(forKey: DefaultsKey.updateInstallAttempt) == nil,
                     "cancellation forgets only the pending attempt")
        store.beginAttempt(installedVersion: "3.4.0", offeredVersion: "3.4.3")
        suite.expect(store.consume(marker: "fail-copy", currentVersion: "3.4.0")?.dismissed == false,
                     "a new failed attempt makes the failure visible again")
        suite.expect(UpdateInstallerSupport.shouldForceAdminInstall(afterFailureCode:
            defaults.string(forKey: DefaultsKey.updateLastInstallFailure)),
                     "copy failures retain the existing administrator-assisted retry")
        suite.expect(store.consume(marker: "unexpected marker", currentVersion: "3.4.0")?.code == "fail-copy",
                     "an unknown marker does not pretend installation succeeded")
        suite.expect(store.restore(currentVersion: "3.4.0") != nil,
                     "starting the same installed version does not clear the result")
        suite.expect(store.restore(currentVersion: "3.3.5") != nil,
                     "a downgrade does not count as successful recovery")
        suite.expect(store.restore(currentVersion: "3.4.3") == nil
                     && defaults.string(forKey: DefaultsKey.updateLastInstallFailure) == nil,
                     "a manual upgrade clears both the failure UI and stale retry escalation")
        store.beginAttempt(installedVersion: "3.4.3", offeredVersion: "3.4.4-beta.1")
        _ = store.consume(marker: "fail-mount", currentVersion: "3.4.3")
        suite.expect(store.consume(marker: "ok\n", currentVersion: "3.4.4-beta.1") == nil
                     && defaults.data(forKey: DefaultsKey.updateInstallAttempt) == nil,
                     "a successful installer result clears all failure and attempt state")

        defaults.set("fail-swap", forKey: DefaultsKey.updateLastInstallFailure)
        suite.expect(store.restore(currentVersion: "3.4.0") == nil,
                     "an old unversioned retry code cannot invent a new failure after a manual upgrade")
        let legacy = store.consume(marker: "fail-swap", currentVersion: "3.4.0")
        suite.expect(legacy?.code == "fail-swap" && legacy?.attemptedVersion == nil,
                     "a fresh legacy installer marker gains persistent UI without inventing a target")
        suite.expect(SettingsBackupSupport.machineStateKeys.isSuperset(of: [
            DefaultsKey.updateInstallFailure, DefaultsKey.updateInstallAttempt, DefaultsKey.updateLastInstallFailure])
                     && SettingsBackupSupport.exportKeys().isDisjoint(with: [
                        DefaultsKey.updateInstallFailure, DefaultsKey.updateInstallAttempt, DefaultsKey.updateLastInstallFailure]),
                     "local update attempts, failures and dismissals never travel in settings backups")
        let repository = URL(string: "https://github.com/vorssaint/vorssaint-utils")!
        suite.expect(first?.releaseURL(repositoryURL: repository).absoluteString
                     == "https://github.com/vorssaint/vorssaint-utils/releases/tag/v3.4.3",
                     "manual recovery opens the release that actually failed")
        suite.expect(legacy?.releaseURL(repositoryURL: repository).absoluteString
                     == "https://github.com/vorssaint/vorssaint-utils/releases",
                     "unknown legacy targets open the release list")
        let diagnostic = first!.diagnostics(currentVersion: "3.4.0", macOSVersion: "15.8.1")
        suite.expect(diagnostic.contains("3.4.3") && diagnostic.contains("fail-verify")
                     && diagnostic.contains("15.8.1") && !diagnostic.contains(NSHomeDirectory()),
                     "copyable diagnostics identify the attempt without private paths")
        layout(suite)
    }

    private static func layout(_ suite: TestSuite) {
        let failure = UpdateInstallFailure(code: "fail-copy", installedVersion: "3.4.0",
                                           attemptedVersion: "3.4.3")
        for language in AppLanguage.allCases {
            let text = FeatureStrings.updateFailure(language)
            suite.expect(String(format: text.currentVersionFormat, "3.4.0").contains("3.4.0")
                         && String(format: text.attemptedVersionFormat, "3.4.3").contains("3.4.3"),
                         "\(language) failure messages retain both version placeholders")
            for code in ["fail-dmg-verify", "fail-verify", "fail-mount", "fail-tempdir", "fail-copy",
                         "fail-swap", "fail-no-app-in-dmg", "fail-version", "fail-future-step"] {
                suite.expect(!text.explanation(for: code).isEmpty
                             && !text.explanation(for: code).contains(code),
                             "\(language) explains \(code) without exposing the code as the explanation")
            }
            for scheme in [ColorScheme.light, .dark] {
                let banner = UpdateFailureBanner(text: text, currentVersion: "3.4.0", isBusy: false,
                                                  onRetry: {}, onDetails: {}, onDismiss: {})
                let host = NSHostingView(rootView: banner.frame(width: 308).environment(\.colorScheme, scheme))
                host.layoutSubtreeIfNeeded()
                suite.expect(host.fittingSize.width == 308 && host.fittingSize.height > 48
                             && host.fittingSize.height < 200,
                             "\(language) failure banner fits the measured menu panel slot in \(scheme)")
                let details = UpdateFailureDetails(failure: failure, text: text, currentVersion: "3.4.0",
                                                    isBusy: false, onRetry: {}, onDownload: {}, onCopy: {})
                let detailHost = NSHostingView(rootView: details.frame(width: 420).environment(\.colorScheme, scheme))
                detailHost.layoutSubtreeIfNeeded()
                suite.expect(detailHost.fittingSize.width == 420 && detailHost.fittingSize.height > 0
                             && detailHost.fittingSize.height < 400,
                             "\(language) failure details fit a narrow settings column in \(scheme)")
            }
        }
    }
}
