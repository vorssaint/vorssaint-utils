// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

enum AppUpdateTests {
    static func run(expect: (Bool, String) -> Void) {
        // MARK: App updates

        expect(AppUpdatesSupport.compare("1.130.0", "1.129.0") == .orderedDescending
                && AppUpdatesSupport.compare("0.730.0.7300790", "0.731.0") == .orderedAscending
                && AppUpdatesSupport.compare("26.084.0504", "26.119.0622.0003") == .orderedAscending,
               "versions compare part by part, as numbers")
        expect(AppUpdatesSupport.compare("1.2", "1.2.0") == .orderedSame
                && AppUpdatesSupport.compare("1.2", "1.2.1") == .orderedAscending
                && AppUpdatesSupport.compare("3.5.230", "3.5.230") == .orderedSame,
               "a missing part counts as zero")
        expect(AppUpdatesSupport.compare("2026.723.1724", "2026.714.1952") == .orderedDescending
                && AppUpdatesSupport.compare("00123", "123") == .orderedSame,
               "leading zeros never decide a comparison")
        expect(!AppUpdatesSupport.isNewer("1.9a", than: "1.10")
                && AppUpdatesSupport.isNewer("1.10", than: "1.9a")
                && !AppUpdatesSupport.isNewer("3.5beta", than: "3.5")
                && AppUpdatesSupport.isNewer("3.5", than: "3.5beta")
                && AppUpdatesSupport.isNewer("1.9b", than: "1.9a"),
               "a lettered part compares by its number first, and the bare number outranks its own suffixed run")
        expect(AppUpdatesSupport.versionCore("3.5.262,260717dcrpwg7m0") == "3.5.262"
                && AppUpdatesSupport.versionCore("0.0.402") == "0.0.402",
               "the revision after a comma is not part of the version")
        expect(AppUpdatesSupport.isNewer("3.5.262,260717dcrpwg7m0", than: "3.5.230")
                && !AppUpdatesSupport.isNewer("1.130.0", than: "1.130.0"),
               "an update is only newer when the number really grew")
        expect(AppUpdatesSupport.isUncomparable("latest") && AppUpdatesSupport.isUncomparable("")
                && !AppUpdatesSupport.isUncomparable("1.0"),
               "a package without a version number cannot be judged")

        func caskUpdate(_ token: String, installed: String, current: String,
                        pinned: Bool = false) -> HomebrewPackageUpdate {
            HomebrewPackageUpdate(kind: .cask, name: token, installedVersions: [installed],
                                  currentVersion: current, isPinned: pinned)
        }
        let caskRecords = [
            HomebrewCaskRecord(token: "editor", displayName: "Editor",
                               installedVersion: "1.129.0", appFileNames: ["Editor.app"]),
            HomebrewCaskRecord(token: "chat", displayName: "Chat",
                               installedVersion: "0.0.374", appFileNames: ["Chat.app"]),
            HomebrewCaskRecord(token: "installer", displayName: "Installer",
                               installedVersion: "26.078", appFileNames: []),
        ]
        // The receipt says 1.129 while the app on disk already updated itself
        // to 1.130: believing the receipt would offer an update that happened.
        let packageApps = [
            AppUpdatesSupport.InstalledApp(name: "Editor", bundleID: "com.vendor.editor",
                                           path: "/Applications/Editor.app", version: "1.130.0",
                                           isFromAppStore: false),
            AppUpdatesSupport.InstalledApp(name: "Chat", bundleID: "com.vendor.chat",
                                           path: "/Applications/Chat.app", version: "0.0.401",
                                           isFromAppStore: false),
        ]
        let packageRows = AppUpdatesSupport.packageUpdates(
            outdated: [caskUpdate("editor", installed: "1.129.0", current: "1.130.0"),
                       caskUpdate("chat", installed: "0.0.374", current: "0.0.402"),
                       caskUpdate("installer", installed: "26.078", current: "26.119"),
                       caskUpdate("pinnedApp", installed: "1.0", current: "2.0", pinned: true),
                       caskUpdate("rolling", installed: "latest", current: "latest")],
            installed: caskRecords,
            apps: packageApps)
        expect(!packageRows.contains { $0.token == "editor" },
               "an app that already updated itself is not offered again")
        expect(packageRows.contains { $0.token == "chat" && $0.installedVersion == "0.0.401" },
               "the version the app reports wins over the package receipt")
        expect(!packageRows.contains { $0.token == "installer" },
               "a package record without an app bundle is not presented as an installed app")
        // Packages that install through an installer declare no app, so the
        // catalog name is tried as a bundle name before giving up.
        let namedRows = AppUpdatesSupport.packageUpdates(
            outdated: [caskUpdate("installer", installed: "26.078", current: "26.119")],
            installed: caskRecords,
            apps: [AppUpdatesSupport.InstalledApp(name: "Installer", bundleID: "com.vendor.installer",
                                                  path: "/Applications/Installer.app", version: "26.084",
                                                  isFromAppStore: false)])
        expect(namedRows.first?.installedVersion == "26.084",
               "a package with no declared app is matched by its catalog name")
        let exactPathRecord = HomebrewCaskRecord(token: "editor", displayName: "Editor",
                                                 installedVersion: "1.0",
                                                 appFileNames: ["Editor.app"],
                                                 appPaths: ["/Users/test/Applications/Editor.app"])
        let duplicateNamedApps = [
            AppUpdatesSupport.InstalledApp(name: "Editor system", bundleID: "com.vendor.editor",
                                           path: "/Applications/Editor.app", version: "9.0",
                                           isFromAppStore: false),
            AppUpdatesSupport.InstalledApp(name: "Editor managed", bundleID: "com.vendor.editor",
                                           path: "/Users/test/Applications/Editor.app", version: "1.0",
                                           isFromAppStore: false),
        ]
        expect(AppUpdatesSupport.packageBundle(for: exactPathRecord,
                                               apps: duplicateNamedApps)?.version == "1.0",
               "package updates use the exact managed app path when same-named copies exist")
        expect(AppUpdatesSupport.packageBundle(for: caskRecords[0],
                                               apps: duplicateNamedApps,
                                               homeDirectory: "/Users/test") == nil,
               "a name-only package record never guesses between same-named app copies")
        let downloadOnlyCopy = AppUpdatesSupport.InstalledApp(
            name: "Editor download", bundleID: "com.vendor.editor",
            path: "/Users/test/Downloads/Editor.app", version: "1.0",
            isFromAppStore: false)
        expect(AppUpdatesSupport.packageBundle(for: caskRecords[0],
                                               apps: [downloadOnlyCopy],
                                               homeDirectory: "/Users/test") == nil,
               "a name-only package record never claims a homonymous app outside standard app folders")
        let alreadyCurrent = AppUpdatesSupport.packageUpdates(
            outdated: [caskUpdate("installer", installed: "26.078", current: "26.119")],
            installed: caskRecords,
            apps: [AppUpdatesSupport.InstalledApp(name: "Installer", bundleID: "com.vendor.installer",
                                                  path: "/Applications/Installer.app", version: "26.200",
                                                  isFromAppStore: false)])
        expect(alreadyCurrent.isEmpty,
               "the name match also suppresses an app that ran ahead of its package")
        expect(!packageRows.contains { $0.token == "pinnedApp" }
                && !packageRows.contains { $0.token == "rolling" },
               "pinned packages and packages without a version stay out")
        expect(packageRows.allSatisfy { $0.canInstallInPlace },
               "package rows can be installed on the spot")
        let ownPackageRows = AppUpdatesSupport.packageUpdates(
            outdated: [caskUpdate("vorssaint", installed: "3.1.12", current: "3.2.0")],
            installed: [],
            ignoredTokens: ["vorssaint"],
            apps: [])
        expect(ownPackageRows.isEmpty,
               "the app update list never offers to replace Vorssaint through its own package")

        let storeApps = [
            AppUpdatesSupport.InstalledApp(name: "Blocker", bundleID: "net.example.blocker",
                                           path: "/Applications/Blocker.app",
                                           version: "2026.714.1952", isFromAppStore: true),
            AppUpdatesSupport.InstalledApp(name: "Sheets", bundleID: "com.example.sheets",
                                           path: "/Applications/Sheets.app",
                                           version: "16.111.1", isFromAppStore: true),
            AppUpdatesSupport.InstalledApp(name: "Chat", bundleID: "com.example.chat",
                                           path: "/Applications/Chat.app",
                                           version: "0.0.401", isFromAppStore: false),
            AppUpdatesSupport.InstalledApp(name: "Future", bundleID: "com.example.future",
                                           path: "/Applications/Future.app",
                                           version: "1.0", isFromAppStore: true),
        ]
        let candidates = AppUpdatesSupport.appStoreCandidates(apps: storeApps,
                                                              coveredPaths: ["/Applications/Chat.app"])
        expect(candidates.count == 3 && !candidates.contains { $0.bundleID == "com.example.chat" },
               "only store purchases are asked about, and never one the package manager answers for")
        let storeVersions = [
            "net.example.blocker": AppUpdatesSupport.StoreEntry(bundleID: "net.example.blocker",
                                                                version: "2026.723.1724",
                                                                minimumOSVersion: "14.0",
                                                                page: "https://apps.apple.com/app"),
            "com.example.sheets": AppUpdatesSupport.StoreEntry(bundleID: "com.example.sheets",
                                                               version: "16.111.1",
                                                               minimumOSVersion: nil, page: nil),
            "com.example.future": AppUpdatesSupport.StoreEntry(bundleID: "com.example.future",
                                                               version: "2.0",
                                                               minimumOSVersion: "26.0", page: nil),
        ]
        let storeRows = AppUpdatesSupport.appStoreUpdates(apps: candidates,
                                                         storeVersions: storeVersions,
                                                         operatingSystemVersion: "15.7")
        expect(storeRows.count == 1 && storeRows[0].name == "Blocker"
                && !storeRows[0].canInstallInPlace,
               "a store app is listed only when its newer version runs on this macOS")

        let mergedRows = AppUpdatesSupport.merged(storeRows, packageRows)
        expect(mergedRows.count == packageRows.count + storeRows.count
                && mergedRows.first?.canInstallInPlace == true
                && mergedRows.last?.canInstallInPlace == false,
               "the merged list puts what can be updated here first")
        let everything = Set(mergedRows.map(\.id))
        expect(AppUpdatesSupport.tokens(in: mergedRows, selection: everything).count == packageRows.count
                && AppUpdatesSupport.hasStoreSelection(in: mergedRows, selection: everything),
               "the selection splits into package tokens and store hand-offs")
        expect(AppUpdatesSupport.tokens(in: mergedRows, selection: []).isEmpty
                && !AppUpdatesSupport.hasStoreSelection(in: mergedRows, selection: []),
               "an empty selection asks for nothing")
        expect(AppUpdatesSupport.singleStorePage(in: mergedRows, selection: everything)
                == "https://apps.apple.com/app",
               "one ticked store row hands off to its own page, where its own button goes")
        let secondStoreRow = AppUpdatesSupport.Item(id: "store:com.example.notes",
                                                    source: .appStore,
                                                    name: "Notes",
                                                    installedVersion: "1.0",
                                                    latestVersion: "2.0",
                                                    token: nil,
                                                    bundlePath: nil,
                                                    storePage: "https://apps.apple.com/notes")
        let twoStoreRows = mergedRows + [secondStoreRow]
        expect(AppUpdatesSupport.singleStorePage(in: twoStoreRows,
                                                 selection: Set(twoStoreRows.map(\.id))) == nil
                && AppUpdatesSupport.singleStorePage(in: mergedRows, selection: []) == nil,
               "two store rows, or none, have no single page to land on")

        let keptSelection = AppUpdatesSupport.reconciledSelection(
            previous: [mergedRows[0].id, "gone:row"],
            knownIDs: Set(mergedRows.map(\.id)),
            items: mergedRows)
        expect(keptSelection == [mergedRows[0].id],
               "a row that disappeared leaves the selection behind")
        let withNewFinding = AppUpdatesSupport.reconciledSelection(
            previous: [], knownIDs: [], items: mergedRows)
        expect(withNewFinding == Set(mergedRows.map(\.id)),
               "findings the person has not seen yet arrive already ticked")

        expect(AppUpdatesSupport.storeLookupURL(bundleIDs: [], country: "BR") == nil,
               "no identifiers means no request")
        let lookup = AppUpdatesSupport.storeLookupURL(bundleIDs: ["a.b", "c.d"], country: "BR")?
            .absoluteString ?? ""
        expect(lookup.contains("bundleId=a.b,c.d") && lookup.contains("country=BR")
                && lookup.contains("entity=macSoftware"),
               "several apps are asked about in one request")
        let noCountry = AppUpdatesSupport.storeLookupURL(bundleIDs: ["a.b"], country: nil)?
            .absoluteString ?? ""
        expect(!noCountry.contains("country="), "without a region the request carries none")
        let lookupBody = Data(#"{"resultCount":2,"results":[{"kind":"mac-software","bundleId":"a.b","version":"2.0","minimumOsVersion":"15.0","trackViewUrl":"https://x"},{"kind":"software","bundleId":"c.d","version":"9.0","minimumOsVersion":"12.0"}]}"#.utf8)
        let lookupEntries = AppUpdatesSupport.parseStoreLookup(lookupBody)
        let lookupEntry = lookupEntries["a.b"]
        expect(lookupEntry?.version == "2.0" && lookupEntry?.minimumOSVersion == "15.0",
               "the store answer is read back")
        expect(lookupEntries["c.d"] == nil,
               "another platform's listing is not the installed Mac app's version")
        expect(AppUpdatesSupport.parseStoreLookup(Data("not json".utf8)).isEmpty,
               "a broken store answer yields nothing instead of throwing")

        let completeLookup = AppUpdatesSupport.storeLookupResponse(
            lookupBody, statusCode: 200)
        expect(AppUpdatesSupport.hasStoreCoverage(bundleIDs: ["a.b"], entries: completeLookup)
                && completeLookup["a.b"]?.version == "2.0",
               "a successful Mac listing covers its requested app")
        let partialLookup = AppUpdatesSupport.storeLookupResponse(
            lookupBody, statusCode: 200)
        expect(!AppUpdatesSupport.hasStoreCoverage(bundleIDs: ["a.b", "c.d"], entries: partialLookup)
                && partialLookup["a.b"]?.version == "2.0",
               "another platform's listing leaves coverage incomplete without losing valid results")
        expect(!AppUpdatesSupport.hasStoreCoverage(bundleIDs: ["a.b", "missing.app"], entries: partialLookup),
               "a catalog omission cannot mean the missing app is up to date")
        let storeFailures: [(Data?, Int?)] = [
            (nil, 200), (lookupBody, nil), (lookupBody, 429), (lookupBody, 500),
            (Data("not json".utf8), 200), (Data("{}".utf8), 200),
            (Data(#"{"resultCount":0,"results":[]}"#.utf8), 200),
            (Data(#"{"results":[{"kind":"mac-software","bundleId":"a.b","version":""}]}"#.utf8), 200),
        ]
        for (body, status) in storeFailures {
            let result = AppUpdatesSupport.storeLookupResponse(body, statusCode: status)
            expect(!AppUpdatesSupport.hasStoreCoverage(bundleIDs: ["a.b"], entries: result) && result.isEmpty,
                   "failed, malformed and empty store responses never certify an app as checked")
        }
        let partiallyCheckedApps = [AppUpdatesSupport.InstalledApp(
            name: "Editor", bundleID: "a.b", path: "/Applications/Editor.app",
            version: "1.0", isFromAppStore: true)]
        let partialStoreRows = AppUpdatesSupport.appStoreUpdates(
            apps: partiallyCheckedApps, storeVersions: partialLookup,
            operatingSystemVersion: "26.0")
        expect(partialStoreRows.count == 1 && partialStoreRows[0].latestVersion == "2.0",
               "a partial store check still offers the updates it could verify")
        let uncheckedReader = AppUpdatesSupport.InstalledApp(
            name: "Reader", bundleID: "reader.example", path: "/Applications/Reader.app",
            version: "1.0", isFromAppStore: false)
        expect(AppUpdatesSupport.uncheckedAppNames(
            partiallyCheckedApps + [uncheckedReader, uncheckedReader],
            checkedPaths: [partiallyCheckedApps[0].path]) == ["Reader"],
               "partial checks name only pending apps and coalesce repeated source failures")
        expect(AppUpdatesSupport.uncheckedAppNames(
            [uncheckedReader], checkedPaths: [uncheckedReader.path]).isEmpty,
               "a successful publisher answer removes the app from failed catalog details")

        expect(AppUpdatesSupport.storeIDLookupURL(ids: ["123", "456"], country: "BR")?
            .absoluteString.contains("id=123,456") == true
                && AppUpdatesSupport.storeIDLookupURL(ids: ["123"], country: "BR")?
                    .absoluteString.contains("platform=macappstore") == true,
               "store lookups use the product identity and explicitly request Mac metadata")
        expect(AppUpdatesSupport.storeIDLookupURL(ids: [], country: nil) == nil
                && AppUpdatesSupport.storeIDLookupURL(ids: ["12&country=US"], country: nil) == nil,
               "store identifiers cannot add query parameters or create an empty request")
        let universalStoreBody = Data(#"""
        {"results":{
          "123":{"bundleId":"com.example.universal","kind":"iosSoftware","deviceFamilies":["mac","iphone"],"minimumOSVersion":"14.0","url":"https://apps.apple.com/app/id123","offers":[{"version":{"display":"2.0"},"assets":[{"flavor":"macSoftware"}]},{"version":{"display":"9.0"},"assets":[{"flavor":"iosSoftware"}]}]},
          "456":{"bundleId":"com.example.mobile","deviceFamilies":["iphone"],"minimumOSVersion":"18.0","offers":[{"version":{"display":"9.0"},"assets":[{"flavor":"iosSoftware"}]}]},
          "789":{"bundleId":"com.example.no-mac-offer","deviceFamilies":["mac","iphone"],"minimumOSVersion":"14.0","offers":[{"version":{"display":"9.0"},"assets":[{"flavor":"iosSoftware"}]}]}
        }}
        """#.utf8)
        let universalEntries = AppUpdatesSupport.storeMetadataResponse(universalStoreBody, statusCode: 200)
        expect(universalEntries.count == 1 && universalEntries["com.example.universal"]?.version == "2.0"
                && universalEntries["com.example.universal"]?.minimumOSVersion == "14.0",
               "universal store apps use the Mac offer and Mac OS requirement, not the mobile version")
        let universalApp = AppUpdatesSupport.InstalledApp(name: "Universal", bundleID: "com.example.universal",
            path: "/Applications/Universal.app", version: "1.0", isFromAppStore: true)
        expect(AppUpdatesSupport.appStoreUpdates(apps: [universalApp], storeVersions: universalEntries,
                                                operatingSystemVersion: "15.0").count == 1
                && AppUpdatesSupport.appStoreUpdates(apps: [universalApp], storeVersions: universalEntries,
                                                    operatingSystemVersion: "13.0").isEmpty,
               "a universal app update is detected only on a compatible Mac")
        expect(AppUpdatesSupport.storeMetadataResponse(universalStoreBody, statusCode: 500).isEmpty
                && AppUpdatesSupport.storeMetadataResponse(Data("{}".utf8), statusCode: 200).isEmpty,
               "failed platform-specific lookups cannot create updates")
        let renamedStoreApp = AppUpdatesSupport.InstalledApp(
            name: "Editor", bundleID: "com.vendor.editor", path: "/Applications/Editor.app",
            version: "1.0", isFromAppStore: true)
        expect(AppUpdatesSupport.packageUpdates(
            outdated: [caskUpdate("editor", installed: "1.0", current: "2.0")],
            installed: caskRecords, apps: [renamedStoreApp]).isEmpty,
               "an old package receipt cannot claim the store edition of an app")

        let publisherFeed = AppUpdateFeedSupport.feed(
            info: ["SUFeedURL": "https://updates.example.com/feed.xml"], configuration: nil)
        expect(publisherFeed?.format == .appcast, "the app's declared feed is a supported source")
        let packagedFeed = AppUpdateFeedSupport.feed(info: [:], configuration:
            "provider: generic\nurl: 'https://updates.example.com/stable'\n")
        expect(packagedFeed?.url.absoluteString == "https://updates.example.com/stable/latest-mac.yml",
               "packaged update configuration selects the Mac release manifest")
        let hostedFeed = AppUpdateFeedSupport.feed(info: [:], configuration:
            "provider: github\nowner: example\nrepo: editor\n")
        expect(hostedFeed?.url.absoluteString == "https://github.com/example/editor/releases/latest/download/latest-mac.yml",
               "an explicitly declared release repository supplies its Mac metadata")
        for invalid in ["file:///tmp/feed.xml", "http://example.com/feed.xml",
                        "https://user:password@example.com/feed.xml", "https://localhost/feed.xml",
                        "https://127.0.0.1/feed.xml", "https://192.168.1.1/feed.xml"] {
            expect(AppUpdateFeedSupport.publicURL(invalid) == nil,
                   "feed discovery rejects local, insecure and credential-bearing URLs")
        }
        for invalid in ["provider: github\nowner: ../user\nrepo: editor",
                        "provider: github\nowner: user\nrepo: editor\nprivate: true",
                        "provider: generic\nurl: https://example.com\nchannel: beta",
                        "provider: generic\nurl: https://example.com\nrequestHeaders:\n  Authorization: secret",
                        "provider: custom\nurl: https://example.com",
                        "provider: generic\nurl: https://example.com\nurl: https://other.example.com"] {
            expect(AppUpdateFeedSupport.feed(info: [:], configuration: invalid) == nil,
                   "private, ambiguous and unsupported update configuration is not guessed")
        }
        let appcast = Data(#"""
        <rss xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle"><channel>
          <item><sparkle:version>110</sparkle:version><sparkle:shortVersionString>1.1</sparkle:shortVersionString><sparkle:minimumSystemVersion>14.0</sparkle:minimumSystemVersion><enclosure url="https://example.com/app.zip" /></item>
          <item><sparkle:version>200</sparkle:version><sparkle:shortVersionString>2.0</sparkle:shortVersionString><sparkle:minimumSystemVersion>27.0</sparkle:minimumSystemVersion><enclosure url="https://example.com/new.zip" /></item>
          <item><sparkle:channel>beta</sparkle:channel><enclosure sparkle:version="300" sparkle:shortVersionString="3.0" url="https://example.com/beta.zip" /></item>
          <item><enclosure sparkle:version="400" sparkle:shortVersionString="4.0" sparkle:os="windows" url="https://example.com/app.exe" /></item>
          <item><sparkle:deltas><enclosure sparkle:version="500" sparkle:deltaFrom="100" url="https://example.com/app.delta" /></sparkle:deltas></item>
        </channel></rss>
        """#.utf8)
        let feedApp = AppUpdatesSupport.InstalledApp(
            name: "Editor", bundleID: "com.example.editor", path: "/Applications/Editor.app",
            version: "1.0", isFromAppStore: false, buildVersion: "100")
        let releases = AppUpdateFeedSupport.releases(data: appcast, format: .appcast) ?? []
        func feedUpdate(_ releases: [AppUpdateFeedSupport.Release],
                        format: AppUpdateFeedSupport.Format = .appcast) -> AppUpdatesSupport.Item? {
            AppUpdateFeedSupport.update(app: feedApp, releases: releases, format: format,
                                        operatingSystemVersion: "15.7", kernelVersion: "24.6.0",
                                        architecture: "arm64")
        }
        expect(feedUpdate(releases)?.latestVersion == "1.1",
               "feeds choose the newest compatible stable Mac release, not the first or largest entry")
        expect(feedUpdate(releases)?.isSelectable == false && feedUpdate(releases)?.token == nil,
               "publisher findings leave installation with the app's own updater")
        expect(feedUpdate([.init(version: "101", displayVersion: "1.0", hasDownload: true)])?
            .latestVersion == "1.0 (101)",
               "new builds with the same visible version are detected and distinguished")
        for excluded in [
            AppUpdateFeedSupport.Release(version: "99", displayVersion: "2.0", hasDownload: true),
            .init(version: "110", displayVersion: "1.1beta", hasDownload: true),
            .init(version: "110", displayVersion: "1.1", maximumOS: "14.0", hasDownload: true),
            .init(version: "110", displayVersion: "1.1", minimumInstalledVersion: "105", hasDownload: true),
            .init(version: "110", displayVersion: "1.1", hardware: "x86_64", hasDownload: true),
        ] {
            expect(feedUpdate([excluded]) == nil,
                   "older builds, preview releases and incompatible update paths are excluded")
        }
        for invalid in [Data("<rss><channel><item>".utf8), Data("<html/>".utf8),
                        Data(#"<!DOCTYPE rss [<!ENTITY x "110">]><rss><channel><item><version>&x;</version></item></channel></rss>"#.utf8),
                        Data(repeating: 32, count: AppUpdateFeedSupport.byteLimit + 1)] {
            expect(AppUpdateFeedSupport.releases(data: invalid, format: .appcast) == nil,
                   "malformed, non-feed, entity-bearing and oversized responses are rejected")
        }
        let manifest = Data("version: 1.2\nfiles:\n  - url: app.zip\nminimumSystemVersion: 24.0.0\n".utf8)
        let manifestReleases = AppUpdateFeedSupport.releases(data: manifest, format: .manifest) ?? []
        expect(feedUpdate(manifestReleases, format: .manifest)?.latestVersion == "1.2",
               "Mac manifests compare visible app versions and use the kernel version for their OS requirement")
        expect(feedUpdate([.init(version: "1.2", displayVersion: "1.2", minimumOS: "25.0.0", hasDownload: true)],
                          format: .manifest) == nil,
               "a manifest requiring a newer kernel cannot be offered")

        let onlineCatalogBody = Data(#"""
        [
          {"token":"notes-stable","version":"2.0,revision","artifacts":[{"uninstall":[{"quit":"com.example.notes"}]},{"app":["Notes.app"],"target":"/Applications/Notes.app"}],"depends_on":{"macos":{">=":["14"]}}},
          {"token":"notes-preview","version":"3.0","artifacts":[{"uninstall":[{"quit":["com.example.notes.preview"]}]},{"app":["Notes.app"]}],"depends_on":{"macos":{">=":["14"]}}},
          {"token":"writer","version":"2.0","artifacts":[{"app":["Writer Source.app",{"target":"Writer.app"}],"target":"/Applications/Writer.app"}]},
          {"token":"duplicate-one","version":"2.0","artifacts":[{"uninstall":[{"quit":"com.example.one"}]},{"app":["Duplicate.app"]}]},
          {"token":"duplicate-two","version":"2.0","artifacts":[{"uninstall":[{"quit":"com.example.two"}]},{"app":["Duplicate.app"]}]},
          {"token":"future","version":"4.0","artifacts":[{"app":["Future.app"]}],"depends_on":{"macos":{">=":["26"]}}},
          {"token":"exact","version":"5.0","artifacts":[{"app":["Exact.app"]}],"depends_on":{"macos":{"==":["15"]}}},
          {"token":"rolling","version":"latest","artifacts":[{"app":["Rolling.app"]}]},
          {"token":"case-sensitive","version":"2.0","artifacts":[{"app":["Case.app"]}]},
          {"token":"older","version":"1.0","artifacts":[{"app":["Older.app"]}]},
          {"token":"own-tool","version":"9.0","artifacts":[{"app":["Own.app"]}]}
        ]
        """#.utf8)
        let onlineCatalog = AppUpdatesSupport.parseOnlineCatalog(onlineCatalogBody) ?? []
        expect(onlineCatalog.count == 11
                && onlineCatalog.first?.bundleIDs == ["com.example.notes"]
                && onlineCatalog.first?.minimumOSVersions == ["14"]
                && onlineCatalog.first { $0.token == "writer" }?.appNames == ["Writer.app"],
               "the online catalog keeps final app names, explicit bundle identifiers and OS rules")
        expect(AppUpdatesSupport.parseOnlineCatalogResponse(onlineCatalogBody, statusCode: 200)?.count == 11
                && AppUpdatesSupport.parseOnlineCatalogResponse(nil, statusCode: 200) == nil
                && AppUpdatesSupport.parseOnlineCatalogResponse(onlineCatalogBody, statusCode: 500) == nil
                && AppUpdatesSupport.parseOnlineCatalogResponse(Data("broken".utf8), statusCode: 200) == nil,
               "missing, failed and malformed network responses never become successful empty coverage")

        let onlineApps = [
            AppUpdatesSupport.InstalledApp(name: "Notes", bundleID: "com.example.notes",
                                           path: "/Applications/Notes.app", version: "1.0",
                                           isFromAppStore: false),
            AppUpdatesSupport.InstalledApp(name: "Writer", bundleID: "com.example.writer",
                                           path: "/Applications/Writer.app", version: "1.0",
                                           isFromAppStore: false),
            AppUpdatesSupport.InstalledApp(name: "Duplicate", bundleID: "com.example.other",
                                           path: "/Applications/Duplicate.app", version: "1.0",
                                           isFromAppStore: false),
            AppUpdatesSupport.InstalledApp(name: "Future", bundleID: "com.example.future",
                                           path: "/Applications/Future.app", version: "1.0",
                                           isFromAppStore: false),
            AppUpdatesSupport.InstalledApp(name: "Exact", bundleID: "com.example.exact",
                                           path: "/Applications/Exact.app", version: "1.0",
                                           isFromAppStore: false),
            AppUpdatesSupport.InstalledApp(name: "Rolling", bundleID: "com.example.rolling",
                                           path: "/Applications/Rolling.app", version: "1.0",
                                           isFromAppStore: false),
            AppUpdatesSupport.InstalledApp(name: "Case", bundleID: "com.example.case",
                                           path: "/Applications/case.app", version: "1.0",
                                           isFromAppStore: false),
            AppUpdatesSupport.InstalledApp(name: "Older", bundleID: "com.example.older",
                                           path: "/Applications/Older.app", version: "2.0",
                                           isFromAppStore: false),
            AppUpdatesSupport.InstalledApp(name: "Own", bundleID: "com.example.own",
                                           path: "/Applications/Own.app", version: "1.0",
                                           isFromAppStore: false),
        ]
        let onlineRows = AppUpdatesSupport.onlineCatalogUpdates(
            apps: onlineApps, catalog: onlineCatalog, operatingSystemVersion: "15.7",
            ignoredTokens: ["own-tool"])
        expect(Set(onlineRows.map(\.name)) == ["Notes", "Writer", "Exact"]
                && onlineRows.allSatisfy { $0.source == .onlineCatalog && !$0.isSelectable },
               "online matching requires an exact unique bundle name, uses an explicit ID to resolve ambiguity and keeps rows action-only")
        let expandedCatalogBody = Data(#"""
        [
          {"token":"installer","version":"2.0","artifacts":[{"pkg":["installer.pkg"]},{"uninstall":[{"quit":["com.example.installer","com.example.installer.helper"],"delete":["/Applications/Installed.app","/Applications/Wild*.app","/tmp/Other.app"]}]}]},
          {"token":"renamed","version":"2.0","artifacts":[{"app":["Original.app"]},{"uninstall":[{"quit":"com.example.renamed"}]}]},
          {"token":"unrelated","version":"9.0","artifacts":[{"app":["Unrelated.app"]},{"uninstall":[{"quit":"com.example.other"}]}]},
          {"token":"companion","version":"99.0","artifacts":[{"app":["Companion.app"]},{"uninstall":[{"quit":["com.example.companion","com.example.renamed"]}]}]}
        ]
        """#.utf8)
        let expandedCatalog = AppUpdatesSupport.parseOnlineCatalog(expandedCatalogBody) ?? []
        expect(expandedCatalog.first?.appNames == ["Installed.app"],
               "installer removal metadata supplies exact app names without treating globs or temporary paths as installed apps")
        let expandedApps = [
            AppUpdatesSupport.InstalledApp(name: "Installer", bundleID: "com.example.installer",
                path: "/Applications/Installed.app", version: "1.0", isFromAppStore: false),
            AppUpdatesSupport.InstalledApp(name: "Renamed", bundleID: "com.example.renamed",
                path: "/Applications/My App.app", version: "1.0", isFromAppStore: false),
            AppUpdatesSupport.InstalledApp(name: "Unrelated", bundleID: "com.example.unrelated",
                path: "/Applications/Unrelated.app", version: "1.0", isFromAppStore: false),
        ]
        let expandedRows = AppUpdatesSupport.onlineCatalogUpdates(
            apps: expandedApps, catalog: expandedCatalog, operatingSystemVersion: "15.7")
        expect(Set(expandedRows.map(\.name)) == ["Installer", "Renamed"],
               "identity matching finds installer-based and renamed apps without accepting a conflicting same-name app")
        expect(expandedRows.allSatisfy { $0.latestVersion == "2.0" },
               "a companion app's quit list cannot take over another app's identity")
        expect(AppUpdatesSupport.onlineCatalogUpdates(
            apps: expandedApps, catalog: expandedCatalog + expandedCatalog,
            operatingSystemVersion: "15.7").isEmpty,
               "multiple catalog entries claiming the same identity cannot choose an update by guesswork")
        expect(!onlineRows.contains { $0.name == "Duplicate" || $0.name == "Future"
                || $0.name == "Rolling" || $0.name == "Case" || $0.name == "Older"
                || $0.name == "Own" },
               "ambiguous, incompatible, uncomparable, differently cased, current and ignored catalog entries stay out")
        let externalCandidates = AppUpdatesSupport.onlineCatalogCandidates(
            apps: [onlineApps[0],
                   AppUpdatesSupport.InstalledApp(name: "Store", bundleID: "com.example.store",
                                                  path: "/Applications/Store.app", version: "1.0",
                                                  isFromAppStore: true),
                   onlineApps[1]],
            coveredPaths: [onlineApps[1].path])
        expect(externalCandidates == [onlineApps[0]],
               "store receipts and package-managed paths never reach the online catalog source")

        let listWithOnline = AppUpdatesSupport.merged(mergedRows, onlineRows)
        let selectionWithOnline = AppUpdatesSupport.reconciledSelection(
            previous: Set(onlineRows.map(\.id)), knownIDs: [], items: listWithOnline)
        expect(selectionWithOnline == Set(mergedRows.map(\.id))
                && listWithOnline.suffix(onlineRows.count).allSatisfy { $0.source == .onlineCatalog },
               "online rows remain outside bulk selection and follow the managed sources in the list")
        let discoveredPaths = InstalledApps.applicationScanPaths(
            folderPaths: ["/Applications/Editor.app",
                          "/System/Applications/System Utility.app",
                          "/Applications/Editor.app"],
            spotlightPaths: ["/Users/test/Tools/Side App.app",
                             "/Users/test/.Trash/Old.app",
                             "/Users/test/Library/Services/Helper.app",
                             "/Users/test/Projects/Sample/build/Debug.app",
                             "/Users/test/Tools/Container.app/Contents/Helper.app",
                             "/Volumes/Installer/Sample.app"],
            homeDirectory: "/Users/test")
        expect(discoveredPaths == ["/Applications/Editor.app", "/Users/test/Tools/Side App.app"],
               "shared app discovery keeps installed apps and rejects system, transient, nested and duplicate copies")

        let noon = Date(timeIntervalSince1970: 1_800_000_000)
        expect(AppUpdatesSupport.nextCheckDate(lastCheck: noon, frequency: .off, now: noon) == nil,
               "with the schedule off nothing is armed")
        expect(AppUpdatesSupport.nextCheckDate(lastCheck: nil, frequency: .daily, now: noon)
                == noon.addingTimeInterval(AppUpdatesSupport.catchUpDelay),
               "a schedule that never ran starts shortly after launch")
        expect(AppUpdatesSupport.nextCheckDate(lastCheck: noon, frequency: .daily, now: noon)
                == noon.addingTimeInterval(86_400),
               "the next daily check follows the last one")
        expect(AppUpdatesSupport.nextCheckDate(lastCheck: noon.addingTimeInterval(-200_000),
                                               frequency: .daily, now: noon)
                == noon.addingTimeInterval(AppUpdatesSupport.catchUpDelay),
               "a check missed while the Mac was off runs soon, not instantly")
        expect(AppUpdatesSupport.shouldRecheck(hasCheckedThisSession: false, handoffPending: false,
                                               lastCheck: noon, now: noon),
               "a session that never scanned always scans on opening")
        expect(AppUpdatesSupport.shouldRecheck(hasCheckedThisSession: true, handoffPending: true,
                                               lastCheck: noon, now: noon),
               "coming back from the store always re-reads the list")
        expect(!AppUpdatesSupport.shouldRecheck(hasCheckedThisSession: true, handoffPending: false,
                                                lastCheck: noon, now: noon.addingTimeInterval(60)),
               "reopening the panel right away costs nothing")
        expect(AppUpdatesSupport.shouldRecheck(hasCheckedThisSession: true, handoffPending: false,
                                               lastCheck: noon,
                                               now: noon.addingTimeInterval(AppUpdatesSupport.staleAfter)),
               "an old answer is read again")
        expect(AppUpdatesSupport.CheckFrequency.sanitized("weekly") == .weekly
                && AppUpdatesSupport.CheckFrequency.sanitized("nonsense") == .off
                && AppUpdatesSupport.CheckFrequency.sanitized(nil) == .off,
               "a damaged frequency falls back to off")

        expect(HomebrewCommandBuilder.upgradeCasks(brewPath: "/opt/x/brew", tokens: [])?.arguments == nil
                && HomebrewCommandBuilder.upgradeCasks(brewPath: "/opt/x/brew",
                                                       tokens: ["; rm -rf /"])?.arguments == nil,
               "an upgrade with nothing valid to name builds no command")
        expect(HomebrewCommandBuilder.upgradeCasks(brewPath: "/opt/x/brew",
                                                   tokens: ["chat", "--force", "editor"])?.arguments
                == ["upgrade", "--cask", "--greedy", "chat", "editor"],
               "only real package names reach the upgrade command")
        expect(HomebrewCommandBuilder.outdatedCasksIncludingSelfUpdating(brewPath: "/opt/x/brew").arguments
                == ["outdated", "--cask", "--greedy", "--json=v2"],
               "the update check asks for the apps that carry their own updater too")
        let caskJSON = #"{"formulae":[],"casks":[{"token":"editor","name":["Editor"],"installed":"1.129.0","artifacts":[{"app":["Source.app",{"target":"Editor.app"}],"target":"/Applications/Editor.app"},{"zap":[]}]},{"token":"tapped-tool","full_token":"example/tap/tapped-tool","name":["Tapped Tool"],"installed":"1.0.0","artifacts":[{"app":["Tapped Tool.app"]}]}]}"#
        let parsedRecords = HomebrewParser.parseInstalledCaskRecords(caskJSON)
        expect(parsedRecords.count == 2 && parsedRecords[0].appFileNames == ["Editor.app"]
                && parsedRecords[0].appPaths == ["/Applications/Editor.app"]
                && parsedRecords[0].displayName == "Editor"
                && parsedRecords[0].installedVersion == "1.129.0",
               "an installed package is traced to the final app name after a rename")
        expect(parsedRecords.first { $0.token == "tapped-tool" }?.displayName == "Tapped Tool",
               "parseInstalledCaskRecords keeps the short token brew outdated reports for a cask from a tap")
        expect(HomebrewParser.parseInstalledCaskRecords("garbage").isEmpty,
               "unreadable package output yields no records")
        let managedPackage = HomebrewOwnershipSupport.packageManagingApplication(
            atPath: "/Applications/Editor.app",
            installed: parsedRecords
        )
        expect(managedPackage?.name == "editor" && managedPackage?.kind == .cask,
               "the exact installed app path resolves to its package")
        expect(HomebrewOwnershipSupport.packageManagingApplication(
            atPath: "/Users/test/Desktop/Editor.app",
            installed: parsedRecords
        ) == nil,
        "a same-named app outside the managed path never resolves to a package")
        let legacyRecord = HomebrewCaskRecord(token: "legacy-tool",
                                              displayName: "Legacy Tool",
                                              installedVersion: "2.0",
                                              appFileNames: ["Legacy Tool.app"])
        expect(HomebrewOwnershipSupport.packageManagingApplication(
            atPath: "/Users/test/Applications/Legacy Tool.app",
            installed: [legacyRecord]
        ) == nil,
        "package uninstall requires exact path ownership even when the catalog omits its target")
        expect(HomebrewOwnershipSupport.packageManagingApplication(
            atPath: "/Applications/Legacy Tool.app",
            installed: [legacyRecord, legacyRecord]
        ) == nil,
        "ambiguous package ownership is never used for uninstall")

        expect(Defaults.utilityOrderWithAppUpdates("screenshot,quickLauncher,cleaner,homebrew")
                == ["screenshot", "quickLauncher", "appUpdates", "cleaner", "homebrew"],
               "app updates joins a saved panel order next to its siblings")
        expect(Defaults.utilityOrderWithAppUpdates("media,clipboard")
                == ["media", "appUpdates", "clipboard"],
               "without the cleaner to anchor to, it still lands near the top")
        expect(Defaults.utilityOrderWithAppUpdates("cleaner,appUpdates,media")
                == ["cleaner", "appUpdates", "media"],
               "an order that already has it is left alone")
        expect(Defaults.utilityOrderWithAppUpdates("") == ["appUpdates"],
               "an empty saved order does not lose the entry")
        expect(Defaults.registeredDefaults[DefaultsKey.appUpdatesCheckFrequency] as? String == "off",
               "the background check starts off")
        expect(Defaults.registeredDefaults[DefaultsKey.appUpdatesIncludeHomebrewApps] as? Bool == true
                && Defaults.registeredDefaults[DefaultsKey.appUpdatesIncludeAppStore] as? Bool == true
                && Defaults.registeredDefaults[DefaultsKey.appUpdatesIncludeOnlineCatalog] as? Bool == true
                && Defaults.registeredDefaults[DefaultsKey.appUpdatesNotify] as? Bool == true
                && Defaults.registeredDefaults[DefaultsKey.panelUtilityAppUpdates] as? Bool == true,
               "the app update defaults are registered")
        expect(SettingsBackupSupport.exportKeys().contains(DefaultsKey.appUpdatesCheckFrequency)
                && SettingsBackupSupport.exportKeys().contains(DefaultsKey.appUpdatesIncludeHomebrewApps)
                && SettingsBackupSupport.exportKeys().contains(DefaultsKey.appUpdatesIncludeOnlineCatalog)
                && !SettingsBackupSupport.exportKeys().contains(DefaultsKey.appUpdatesLastCheck),
               "app update preferences travel in a backup, the last check does not")
        expect(AppFeature.appUpdates.enabledKeys.isEmpty
                && AppFeature.appUpdates.permissions == [.notifications, .appManagement]
                && AppFeature.appUpdates.group == .tools,
               "app updates is an on demand tool that declares its update access")
        expect(FeatureVisibilitySupport.features(for: .appUpdates) == [.appUpdates]
                && !FeatureVisibilitySupport.isPageVisible(.appUpdates, isAvailable: { _ in false }),
               "the page follows the feature in the hub")
        expect(activeSet(.notifications, on: [DefaultsKey.appUpdatesNotify],
                         strings: [DefaultsKey.appUpdatesCheckFrequency: "daily"])
                .contains(.appUpdates),
               "app updates only use notifications with a background check armed")
        expect(!activeSet(.notifications, on: [DefaultsKey.appUpdatesNotify])
                .contains(.appUpdates),
               "with the schedule off, app updates need no notification permission")
    }
}
