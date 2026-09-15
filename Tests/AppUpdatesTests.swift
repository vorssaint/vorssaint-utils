// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// Generated production methods run with URLSession, controlled responses and a
/// clock. No installed app is scanned, opened or changed by these contracts.
enum AppUpdatesContract {
    final class Clock {
        var value = Date(timeIntervalSince1970: 1_800_000_000)
        var reads = 0
        var expireAfterReads = Int.max
        func now() -> Date {
            reads += 1
            return reads > expireAfterReads ? value.addingTimeInterval(61) : value
        }
    }

    enum URLSessionConfiguration {
        static var ephemeral: Foundation.URLSessionConfiguration {
            let configuration = Foundation.URLSessionConfiguration.ephemeral
            configuration.protocolClasses = [ResponseProtocol.self]
            return configuration
        }
    }

    final class ResponseProtocol: URLProtocol {
        struct Response {
            var status = 200
            var body = Data()
            var error: URLError?
            var delay: TimeInterval = 0
            var declaredLength: Int?
        }
        static let lock = NSLock()
        static var responses: [String: Response] = [:]
        static var requests: [String] = []
        private var delivery: DispatchWorkItem?

        static func reset(_ values: [String: Response]) {
            lock.withLock { responses = values; requests = [] }
        }
        static var requestCount: Int { lock.withLock { requests.count } }
        override class func canInit(with request: URLRequest) -> Bool { true }
        override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
        override func startLoading() {
            let response = Self.lock.withLock { () -> Response in
                let url = request.url!.absoluteString
                Self.requests.append(url)
                return Self.responses[url] ?? Response(error: URLError(.resourceUnavailable))
            }
            let delivery = DispatchWorkItem { [weak self] in
                guard let self else { return }
                if let error = response.error {
                    client?.urlProtocol(self, didFailWithError: error)
                    return
                }
                let headers = ["Content-Length": "\(response.declaredLength ?? response.body.count)"]
                let http = HTTPURLResponse(url: request.url!, statusCode: response.status,
                                           httpVersion: "HTTP/1.1", headerFields: headers)!
                client?.urlProtocol(self, didReceive: http, cacheStoragePolicy: .notAllowed)
                client?.urlProtocol(self, didLoad: response.body)
                client?.urlProtocolDidFinishLoading(self)
            }
            self.delivery = delivery
            DispatchQueue.global().asyncAfter(deadline: .now() + response.delay, execute: delivery)
        }
        override func stopLoading() { delivery?.cancel() }
    }

    final class Reply {
        let semaphore = DispatchSemaphore(value: 0)
        var value: Service.SourceResult?
    }

    static func publisher(_ apps: [AppUpdatesSupport.InstalledApp], service: Service = Service(),
                          suite: TestSuite) -> Service.SourceResult {
        let reply = Reply()
        service.workQueue.async {
            service.publisherFindings(for: apps, operatingSystemVersion: "15.7") {
                reply.value = $0
                reply.semaphore.signal()
            }
        }
        let finished = reply.semaphore.wait(timeout: .now() + 5) == .success
        suite.expect(finished, "publisher requests finish once without a live network")
        return reply.value ?? .init(items: [], available: false, uncheckedApps: apps)
    }

    static func catalog(_ apps: [AppUpdatesSupport.InstalledApp], service: Service, refresh: Bool,
                        suite: TestSuite) -> Service.SourceResult {
        let reply = Reply()
        service.workQueue.async {
            service.onlineCatalogFindings(for: apps, operatingSystemVersion: "15.7", forceRefresh: refresh) {
                reply.value = $0
                reply.semaphore.signal()
            }
        }
        let finished = reply.semaphore.wait(timeout: .now() + 5) == .success
        suite.expect(finished, "catalog requests finish without a live network")
        return reply.value ?? .init(items: [], available: false, uncheckedApps: apps)
    }

    enum UserDefaults {
        static let suiteName = "com.vorssaint.tests.app-updates.\(UUID().uuidString)"
        static var standard: Foundation.UserDefaults {
            Foundation.UserDefaults(suiteName: suiteName)!
        }
    }

    static func run(_ suite: TestSuite) {
        defer { UserDefaults.standard.removePersistentDomain(forName: UserDefaults.suiteName) }
        func item(_ source: AppUpdatesSupport.Source, version: String = "2.0") -> AppUpdatesSupport.Item {
            .init(id: "\(source.rawValue):editor", source: source, name: "Editor",
                  installedVersion: "1.0", latestVersion: version,
                  token: source == .packageManager ? "editor" : nil,
                  bundlePath: "/Applications/Editor.app", storePage: nil)
        }
        let releases = [item(.packageManager), item(.appStore), item(.onlineCatalog)]
        let ignoredService = Service()
        ignoredService.items = releases
        ignoredService.selection = Set(releases.filter(\.isSelectable).map(\.id))
        ignoredService.knownIDs = Set(releases.map(\.id))
        Service.saveAnnouncedIDs(ignoredService.knownIDs)
        for release in releases {
            ignoredService.ignore(release)
            suite.expect(!ignoredService.items.contains(release)
                         && !ignoredService.selection.contains(release.id)
                         && !ignoredService.knownIDs.contains(release.id)
                         && !Service.announcedIDs().contains(release.id),
                         "ignoring removes the release from the list and bulk selection for every source")
            suite.expect(UserDefaults.standard.integer(forKey: DefaultsKey.appUpdatesLastCount)
                         == ignoredService.items.count,
                         "ignoring updates the stored visible count immediately")
        }
        suite.expect(Service.visibleItems(releases).isEmpty,
                     "a fresh defaults instance keeps ignored releases hidden on subsequent scans")
        let nextReleases = [item(.packageManager, version: "3.0"), item(.appStore, version: "3.0"),
                            item(.onlineCatalog, version: "3.0")]
        suite.expect(Service.visibleItems(nextReleases).isEmpty,
                     "new versions remain ignored for every source until manually restored")
        let other = AppUpdatesSupport.Item(id: "other", source: .onlineCatalog, name: "Other",
            installedVersion: "1.0", latestVersion: "2.0", token: nil, bundlePath: nil, storePage: nil)
        suite.expect(Service.visibleItems(releases + [other]) == [other],
                     "ignoring one app never hides another app with the same version")
        ignoredService.ignore(other)
        suite.expect(Service.visibleItems([other]) == [other],
                     "a stale row cannot ignore an update outside the current list")
        let relaunched = Service()
        suite.expect(relaunched.ignoredItems.count == releases.count
                     && relaunched.ignoredItems.allSatisfy {
                         $0.name == "Editor" && $0.version == "2.0" && $0.bundlePath == "/Applications/Editor.app"
                     } && Service.visibleItems(nextReleases).isEmpty,
                     "ignored apps, names and icon paths survive a new service instance")
        let restored = relaunched.ignoredItems.first { $0.id == releases[0].id }!
        relaunched.restore(restored)
        suite.expect(Service.visibleItems(releases) == [releases[0]]
                     && Service.visibleItems(nextReleases) == [nextReleases[0]]
                     && relaunched.ignoredItems.count == 2 && relaunched.refreshRequests == 1,
                     "restore removes only one ignore rule and requests fresh releases")
        suite.expect(UserDefaults.standard.dictionary(forKey: DefaultsKey.appUpdatesIgnoredNames)?[restored.id] == nil
                     && UserDefaults.standard.dictionary(forKey: DefaultsKey.appUpdatesIgnoredPaths)?[restored.id] == nil,
                     "restore removes stored display metadata too")
        relaunched.restore(restored)
        suite.expect(relaunched.refreshRequests == 1, "restoring a stale row is harmless")
        let legacyID = "onlineCatalog:/Applications/Legacy.app"
        var versions = UserDefaults.standard.dictionary(forKey: DefaultsKey.appUpdatesIgnoredVersions) as! [String: String]
        versions[legacyID] = "4.0"
        UserDefaults.standard.set(versions, forKey: DefaultsKey.appUpdatesIgnoredVersions)
        let legacy = Service().ignoredItems.first { $0.id == legacyID }!
        suite.expect(legacy.name == "Legacy" && legacy.version == "4.0"
                     && legacy.bundlePath == "/Applications/Legacy.app",
                     "previous ignore preferences remain visible without stored display names")
        let legacyUpdate = AppUpdatesSupport.Item(id: legacyID, source: .onlineCatalog, name: "Legacy",
            installedVersion: "4.0", latestVersion: "5.0", token: nil,
            bundlePath: "/Applications/Legacy.app", storePage: nil)
        suite.expect(Service.visibleItems([legacyUpdate]).isEmpty,
                     "existing ignore preferences also hide future versions")
        relaunched.restore(legacy)
        suite.expect(!Service().ignoredItems.contains { $0.id == legacyID },
                     "previous ignore preferences can also be restored")
        for language in AppLanguage.allCases {
            let strings = FeatureStrings.appUpdates(language)
            suite.expect(!strings.ignoreVersion.isEmpty && strings.ignoreVersionHintFormat.contains("%@")
                         && !strings.availableTab.isEmpty && !strings.ignoredTab.isEmpty
                         && !strings.restoreVersion.isEmpty && !strings.noIgnoredUpdates.isEmpty,
                         "ignore controls have localized labels and version hints")
        }
        let app = AppUpdatesSupport.InstalledApp(name: "Editor", bundleID: "com.example.editor",
            path: "/Applications/Editor.app", version: "1.0", isFromAppStore: false)
        func entry(version: String = "2.0", name: String = "Editor.app", ids: [String] = ["com.example.editor"],
                   minimum: [String] = [], unsupported: Bool = false, token: String = "editor") -> AppUpdatesSupport.CatalogEntry {
            .init(token: token, version: version, appNames: [name], bundleIDs: ids,
                  minimumOSVersions: minimum, exactOSVersions: [], hasUnsupportedOSConstraint: unsupported)
        }
        let cases: [(String, [AppUpdatesSupport.CatalogEntry], Bool, Int)] = [
            ("missing", [], false, 0),
            ("unrelated", [entry(name: "Other.app", ids: ["com.example.other"])], false, 0),
            ("uncomparable", [entry(version: "latest")], false, 0),
            ("empty version", [entry(version: "")], false, 0),
            ("ambiguous", [entry(), entry()], false, 0),
            ("wrong identity", [entry(ids: ["com.example.other"])], false, 0),
            ("companion identity", [entry(name: "Other.app", ids: ["com.example.other", app.bundleID])], false, 0),
            ("incompatible", [entry(minimum: ["99"])], false, 0),
            ("unknown compatibility", [entry(unsupported: true)], false, 0),
            ("ignored", [entry(token: "vorssaint")], false, 0),
            ("current", [entry(version: "1.0")], true, 0),
            ("installed newer", [entry(version: "0.9")], true, 0),
            ("available update", [entry()], true, 1),
            ("renamed", [entry(name: "Original.app")], true, 1),
        ]
        let manifest = Data("version: 2.0\npath: app.zip\n".utf8)
        let appcast = Data(#"<rss xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle"><channel><item><enclosure url="https://updates.example.com/app.zip" sparkle:version="2.0" /></item></channel></rss>"#.utf8)
        let url = "https://updates.example.com/feed"
        for format in [AppUpdateFeedSupport.Format.manifest, .appcast] {
            var candidate = app
            candidate.updateFeed = .init(url: URL(string: url)!, format: format)
            for status in [404, 410] {
                ResponseProtocol.reset([url: .init(status: status)])
                let feed = publisher([candidate], suite: suite)
                for (name, entries, covered, rowCount) in cases {
                    let online = Service().onlineResult(candidates: [candidate], catalog: entries, operatingSystemVersion: "15.7")
                    let resolved = feed.resolvingCatalogFallback(checkedPaths: online.checkedPaths, candidates: [candidate])
                    let label = "\(format) \(status) \(name)"
                    suite.expect(resolved.available == covered, "\(label): only usable catalog coverage clears a missing-feed warning")
                    suite.expect(resolved.uncheckedApps.map(\.path) == (covered ? [] : [candidate.path]),
                                 "\(label): missing coverage keeps the app named")
                    suite.expect(online.items.count == rowCount && resolved.checkedPaths.isEmpty,
                                 "\(label): fallback preserves catalog updates and never claims a publisher answer")
                }
            }
            for response in [ResponseProtocol.Response(status: 403), .init(status: 500),
                             .init(error: URLError(.timedOut)), .init(body: Data("broken".utf8)),
                             .init(body: Data(repeating: 32, count: AppUpdateFeedSupport.byteLimit + 1)),
                             .init(body: Data(repeating: 32, count: AppUpdateFeedSupport.byteLimit + 1), declaredLength: 0)] {
                ResponseProtocol.reset([url: response])
                let feed = publisher([candidate], suite: suite)
                let resolved = feed.resolvingCatalogFallback(checkedPaths: [candidate.path], candidates: [candidate])
                suite.expect(!resolved.available && resolved.uncheckedApps == [candidate],
                             "real publisher failures remain incomplete even when the catalog covers the app")
            }
            ResponseProtocol.reset([url: .init(body: format == .manifest ? manifest : appcast)])
            let success = publisher([candidate], suite: suite)
            suite.expect(success.available && success.items.count == 1 && success.checkedPaths == [candidate.path]
                         && success.uncheckedApps.isEmpty && success.catalogFallbackPaths.isEmpty,
                         "readable publisher updates retain precedence and have no fallback requirement")
            let currentBody = String(data: format == .manifest ? manifest : appcast, encoding: .utf8)!
                .replacingOccurrences(of: "2.0", with: "1.0")
            ResponseProtocol.reset([url: .init(body: Data(currentBody.utf8))])
            let current = publisher([candidate], suite: suite)
            let online = Service().onlineResult(candidates: [candidate], catalog: [entry()], operatingSystemVersion: "15.7")
            let visible = online.items.filter { !current.checkedPaths.contains($0.bundlePath ?? "") }
            suite.expect(current.available && current.items.isEmpty && visible.isEmpty,
                         "a successful publisher answer with no update still overrides a newer catalog row")
        }

        let unknownVersion = AppUpdatesSupport.InstalledApp(name: app.name, bundleID: app.bundleID, path: app.path, version: "latest", isFromAppStore: false)
        suite.expect(Service().onlineResult(candidates: [unknownVersion], catalog: [entry()], operatingSystemVersion: "15.7").checkedPaths.isEmpty,
                     "an unknown installed version cannot prove catalog coverage")

        var shared = app
        shared.updateFeed = .init(url: URL(string: url)!, format: .manifest)
        let renamed = AppUpdatesSupport.InstalledApp(name: "Other Copy", bundleID: app.bundleID,
            path: "/Users/test/Applications/Other Copy.app", version: "1.0", isFromAppStore: false, updateFeed: shared.updateFeed)
        ResponseProtocol.reset([url: .init(status: 404)])
        let grouped = publisher([shared, renamed], suite: suite)
        suite.expect(ResponseProtocol.requestCount == 1, "apps sharing one feed perform one request")
        let partlyCovered = grouped.resolvingCatalogFallback(checkedPaths: [shared.path], candidates: [shared, renamed])
        suite.expect(!partlyCovered.available && partlyCovered.uncheckedApps == [renamed],
                     "coverage belongs to the exact app path, not every copy sharing a feed or identity")

        let batch = (0..<6).map { index in
            AppUpdatesSupport.InstalledApp(name: "App \(index)", bundleID: "com.example.app\(index)",
                path: "/Applications/App\(index).app", version: "1.0", isFromAppStore: false,
                updateFeed: .init(url: URL(string: "https://updates.example.com/\(index)")!, format: .manifest))
        }
        ResponseProtocol.reset(Dictionary(uniqueKeysWithValues: batch.enumerated().map { index, item in
            (item.updateFeed!.url.absoluteString, .init(status: index.isMultiple(of: 2) ? 404 : 500, delay: Double(6 - index) / 1000))
        }))
        let mixed = publisher(batch, suite: suite)
        let resolvedMixed = mixed.resolvingCatalogFallback(checkedPaths: Set(batch.map(\.path)), candidates: batch)
        suite.expect(!resolvedMixed.available && Set(resolvedMixed.uncheckedApps.map(\.path)) == Set(batch.enumerated().filter { !$0.offset.isMultiple(of: 2) }.map { $0.element.path }),
                     "out-of-order batches keep real failures separate from covered absent feeds")
        suite.expect(ResponseProtocol.requestCount == 6, "every distinct feed is visited once across batches")
        for cutoff in [1, 2] {
            let service = Service()
            service.clock.expireAfterReads = cutoff
            ResponseProtocol.reset(Dictionary(uniqueKeysWithValues: batch.map { ($0.updateFeed!.url.absoluteString, .init(status: 404)) }))
            let stopped = publisher(batch, service: service, suite: suite)
            let resolved = stopped.resolvingCatalogFallback(checkedPaths: Set(batch.map(\.path)), candidates: batch)
            suite.expect(!resolved.available && resolved.uncheckedApps.count == (cutoff == 1 ? 6 : 2),
                         "deadline-cut feeds stay named even with complete catalog coverage")
            suite.expect(ResponseProtocol.requestCount == (cutoff == 1 ? 0 : 4), "deadline stops new batches")
        }
        ResponseProtocol.reset([:])
        let empty = publisher([], suite: suite)
        let noFeed = publisher([app], suite: suite)
        suite.expect(empty.available && noFeed.available && ResponseProtocol.requestCount == 0,
                     "empty and catalog-only candidates create no publisher requests")

        let catalogURL = AppUpdatesSupport.onlineCatalogURL.absoluteString
        let body = Data(#"[{"token":"editor","version":"1.0","artifacts":[{"app":["Editor.app"]},{"uninstall":[{"quit":"com.example.editor"}]}]}]"#.utf8)
        let service = Service()
        ResponseProtocol.reset([catalogURL: .init(body: body)])
        let first = catalog([shared], service: service, refresh: true, suite: suite)
        suite.expect(first.available && first.items.isEmpty && first.checkedPaths == [shared.path],
                     "a current app is covered after reading and parsing a real catalog response")
        ResponseProtocol.reset([catalogURL: .init(status: 500)])
        let cached = catalog([renamed], service: service, refresh: false, suite: suite)
        suite.expect(cached.checkedPaths == [renamed.path] && ResponseProtocol.requestCount == 0,
                     "cached catalog entries recompute coverage for the current app paths")
        let failedRefresh = catalog([shared], service: service, refresh: true, suite: suite)
        suite.expect(!failedRefresh.available && failedRefresh.checkedPaths.isEmpty && failedRefresh.uncheckedApps == [shared],
                     "a failed manual refresh cannot reuse stale catalog coverage")
        let uncovered = grouped.resolvingCatalogFallback(checkedPaths: failedRefresh.checkedPaths, candidates: [shared, renamed])
        suite.expect(!uncovered.available && uncovered.uncheckedApps.count == 2,
                     "a missing publisher plus failed catalog retains both unresolved apps")
        service.clock.value = service.clock.value.addingTimeInterval(3601)
        ResponseProtocol.reset([catalogURL: .init(body: Data("[]".utf8))])
        let expired = catalog([shared], service: service, refresh: false, suite: suite)
        suite.expect(expired.available && expired.checkedPaths.isEmpty && ResponseProtocol.requestCount == 1,
                     "an expired cache cannot conceal an app removed from the catalog")
        ResponseProtocol.reset([catalogURL: .init(body: Data("invalid".utf8))])
        let malformed = catalog([shared], service: service, refresh: true, suite: suite)
        suite.expect(!malformed.available && malformed.uncheckedApps == [shared],
                     "an unreadable catalog cannot establish fallback coverage")
    }
}
