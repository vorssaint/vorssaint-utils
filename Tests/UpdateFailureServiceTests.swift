// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// Production failure consumption, banner gates and retry routing with an isolated
/// marker and preferences. A fake check avoids network and the install preview.
enum UpdateFailureServiceTests {
    enum UserDefaults { static var standard: Foundation.UserDefaults! }
    enum AppInfo {
        static var version = "3.4.0"
        static var isDeveloperBuild = true
    }
    enum Notifier {
        static var bodies: [String] = []
        static func post(title: String, body: String) { bodies.append(body) }
    }
    enum L10n {
        struct Strings {
            let updateNotifyTitle = "Update"
            let updateInstallFailedBody = "Installation failed"
        }
        struct Value { let s = Strings() }
        static let shared = Value()
    }
    class Fixture {
        static var installResultURL: URL?
        var lastInstallFailure: UpdateInstallFailure?
        var checks = 0
        var nextOffer = false
        func check(manual: Bool, completion: (() -> Void)? = nil) {
            checks += 1
            if let service = self as? Service {
                service.state = nextOffer ? .available(version: "3.4.3") : .failed("offline")
            }
            completion?()
        }
    }

    static func run(_ suite: TestSuite) {
        let domain = "com.vorssaint.tests.update-failure-service.\(UUID().uuidString)"
        UserDefaults.standard = Foundation.UserDefaults(suiteName: domain)!
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try! FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        Fixture.installResultURL = directory.appendingPathComponent("result")
        defer {
            UserDefaults.standard.removePersistentDomain(forName: domain)
            UserDefaults.standard = nil
            Fixture.installResultURL = nil
            try? FileManager.default.removeItem(at: directory)
        }
        let service = Service()
        let store = UpdateFailureStore(defaults: UserDefaults.standard)
        store.beginAttempt(installedVersion: "3.4.0", offeredVersion: "3.4.3")
        try! "fail-verify".write(to: Fixture.installResultURL!, atomically: true, encoding: .utf8)
        service.consumeInstallResult()
        suite.expect(service.lastInstallFailure?.attemptedVersion == "3.4.3" && service.showsFailureBanner,
                     "a real failure marker produces a persistent banner even before an update check")
        suite.expect(!FileManager.default.fileExists(atPath: Fixture.installResultURL!.path),
                     "the consumed marker cannot replay its notification on every launch")
        let states: [Service.State] = [.idle, .checking, .upToDate, .available(version: "3.4.3"), .failed("offline")]
        for state in states {
            service.state = state
            suite.expect(service.showsFailureBanner && service.showsMenuPanelBanner,
                         "\(state) cannot hide a recorded installation failure or drop its panel height")
        }
        for state in [Service.State.downloading(progress: 0.2), .installing] {
            service.state = state
            suite.expect(!service.showsInstallFailure && service.showsMenuPanelBanner,
                         "a retry shows progress in place of the failure without losing the banner slot")
        }
        service.state = .available(version: "3.4.3")
        var previews = 0
        service.prepareInstallRetry { previews += 1 }
        suite.expect(previews == 1 && service.checks == 0,
                     "retry reuses a known offer and opens the existing confirmation flow")
        service.state = .idle
        service.nextOffer = true
        service.prepareInstallRetry { previews += 1 }
        suite.expect(previews == 2 && service.checks == 1,
                     "retry after restart first checks for an offer then opens its confirmation")
        service.state = .idle
        service.nextOffer = false
        service.prepareInstallRetry { previews += 1 }
        suite.expect(previews == 2 && service.showsFailureBanner,
                     "a failed retry check keeps the explanation and cannot start installation")
        service.dismissFailureBanner()
        suite.expect(!service.showsFailureBanner && service.showsInstallFailure
                     && service.lastInstallFailure?.dismissed == true && store.failure?.dismissed == true,
                     "dismissal hides only the banner, preserving About details and persisted state")
        try! "ok".write(to: Fixture.installResultURL!, atomically: true, encoding: .utf8)
        service.consumeInstallResult()
        suite.expect(service.lastInstallFailure == nil && !service.showsFailureBanner,
                     "a successful marker clears the published failure and banner")
    }
}
