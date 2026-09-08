// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

enum UninstallerTests {
    static func run(expect: (Bool, String) -> Void) {
        expect(CleanerSupport.isProtectedBundleID("com.apple.Music")
               && CleanerSupport.isProtectedBundleID("com.apple")
               && CleanerSupport.isProtectedBundleID("group.com.apple.notes")
               && CleanerSupport.isProtectedBundleID("com.vorssaint.utils"),
               "system domains and this app can never be junk owners")
        expect(!CleanerSupport.isProtectedBundleID("com.vendor.editor"),
               "third party identifiers are eligible for the leftover check")
        expect(UninstallerSupport.verifiedBundleID("com.vendor.editor") == "com.vendor.editor"
               && UninstallerSupport.verifiedBundleID("com.vendor.editor.helper") == "com.vendor.editor.helper"
               && UninstallerSupport.verifiedBundleID("test.editor") == "test.editor"
               && UninstallerSupport.verifiedBundleID("editor.test") == "editor.test",
               "the uninstaller accepts exact third party bundle identifiers, two-component IDs, and embedded helpers")
        expect(UninstallerSupport.verifiedBundleID(nil) == nil
               && UninstallerSupport.verifiedBundleID("") == nil
               && UninstallerSupport.verifiedBundleID("plain-name") == nil
               && UninstallerSupport.verifiedBundleID("com.vendor../escape") == nil
               && UninstallerSupport.verifiedBundleID("com.vorssaint.utils") == nil
               && UninstallerSupport.verifiedBundleID("com.apple.system") == nil,
               "malformed, protected and current app identifiers never enter uninstall paths")
        let uninstallAppURL = URL(fileURLWithPath: "/Applications/Editor.app")
        expect(UninstallerSupport.isNestedBundle(
                   URL(fileURLWithPath: "/Applications/Editor.app/Contents/Library/LoginItems/Background.app"),
                   in: uninstallAppURL)
               && !UninstallerSupport.isNestedBundle(uninstallAppURL, in: uninstallAppURL)
               && !UninstallerSupport.isNestedBundle(
                   URL(fileURLWithPath: "/Applications/Editor.app-copy/Contents/Background.app"),
                   in: uninstallAppURL)
               && !UninstallerSupport.isNestedBundle(nil, in: uninstallAppURL),
               "the uninstaller stops only background apps nested inside the selected bundle")
        expect(!UninstallerSupport.sharedDataIsExclusive(
            selectedURL: URL(fileURLWithPath: "/Users/test/Downloads/Editor.app"),
            bundleID: "com.vendor.editor",
            knownApplications: [
                (URL(fileURLWithPath: "/Users/test/Downloads/Editor.app"), "com.vendor.editor"),
                (URL(fileURLWithPath: "/Applications/Editor.app"), "com.vendor.editor"),
            ])
            && UninstallerSupport.sharedDataIsExclusive(
                selectedURL: URL(fileURLWithPath: "/Applications/Editor.app"),
                bundleID: "com.vendor.editor",
                knownApplications: [
                    (URL(fileURLWithPath: "/Applications/Editor.app"), "com.vendor.editor"),
                    (URL(fileURLWithPath: "/Applications/Other.app"), "com.vendor.other"),
                ]),
               "shared app data is eligible only when no other installed copy owns the bundle identifier")
        expect(UninstallerSupport.sharedDataIsExclusive(
            selectedURL: URL(fileURLWithPath: "/Applications/Editor.app"),
            bundleID: "com.vendor.editor.helper",
            knownApplications: [
                (URL(fileURLWithPath: "/Applications/Editor.app/Contents/Helpers/Helper.app"),
                 "com.vendor.editor.helper"),
            ])
            && UninstallerSupport.applicationIsInTrustedInstallRoot(
                URL(fileURLWithPath: "/Applications/Editor.app"),
                home: URL(fileURLWithPath: "/Users/test"))
            && !UninstallerSupport.applicationIsInTrustedInstallRoot(
                URL(fileURLWithPath: "/Users/test/Downloads/Editor.app"),
                home: URL(fileURLWithPath: "/Users/test")),
               "embedded helpers belong to the selected app while unregistered download copies never own shared data")
        let uninstallCandidateIDs: Set<String> = ["com.vendor.editor", "com.vendor.editor.helper"]
        expect(UninstallerSupport.exclusiveBundleIDs(
                   uninstallCandidateIDs,
                   selectedURL: uninstallAppURL,
                   knownApplications: []) == uninstallCandidateIDs
               && UninstallerSupport.exclusiveBundleIDs(
                   uninstallCandidateIDs,
                   selectedURL: uninstallAppURL,
                   knownApplications: [
                       (URL(fileURLWithPath: "/Applications/Other.app"),
                        "com.vendor.editor.helper"),
                   ]) == ["com.vendor.editor"],
               "package removal preserves helper candidates while excluding an owner installed elsewhere")
        let uninstallIDs: Set<String> = ["com.vendor.editor", "com.vendor.editor.helper"]
        let leftoverIdentity = UninstallerSupport.identity(
            bundleIDs: uninstallIDs, displayNames: ["Editor", "Editor.app"])
        expect(leftoverIdentity.nameTokens.contains("editor")
               && !leftoverIdentity.nameTokens.contains("helper"),
               "display names become match tokens and helper suffixes do not")
        expect(UninstallerSupport.leftoverMatch("Editor", identity: leftoverIdentity) == .related
               && UninstallerSupport.leftoverMatch("com.vendor.editor.plist", identity: leftoverIdentity) == .exact
               && UninstallerSupport.leftoverMatch(
                   "com.vendor.editor.B787EFF9-B8E2-5296-96AF-DF9D3CD3AC4F.plist",
                   identity: leftoverIdentity) == .exact
               && UninstallerSupport.leftoverMatch("COM.VENDOR.EDITOR.PLIST", identity: leftoverIdentity) == .exact
               && UninstallerSupport.leftoverMatch("Editor.prefPane", identity: leftoverIdentity) == .related
               && UninstallerSupport.leftoverMatch(
                   "ABCD123456.com.vendor.editor", identity: leftoverIdentity) == .none
               && UninstallerSupport.leftoverMatch(
                   "group.com.vendor.editor", identity: leftoverIdentity) == .none
               && UninstallerSupport.leftoverMatch(
                   "com.wrapper.com.vendor.editor", identity: leftoverIdentity) == .none
               && UninstallerSupport.leftoverMatch("Google", identity: leftoverIdentity) == .none
               && UninstallerSupport.leftoverMatch("com.vendor.editor2", identity: leftoverIdentity) == .none
               && UninstallerSupport.leftoverMatch(
                   "com.vendor.editor.extra", identity: leftoverIdentity) == .related
               && UninstallerSupport.leftoverMatch(
                   "com.vendor.editor.helper.plist", identity: leftoverIdentity) == .exact
               && UninstallerSupport.leftoverMatch("Editorial", identity: leftoverIdentity) == .related
               && UninstallerSupport.leftoverMatch("Editor/Nested", identity: leftoverIdentity) == .none,
               "owned identifiers are exact, while prefixes and names stay optional without unsigned wrappers")
        let technicalIdentity = UninstallerSupport.technicalIdentity(leftoverIdentity)
        expect(UninstallerSupport.leftoverMatch("Editor", identity: technicalIdentity) == .none
               && UninstallerSupport.leftoverMatch(
                   "com.vendor.editor.plist", identity: technicalIdentity) == .exact,
               "sensitive roots accept technical ownership and never a display name")
        expect(UninstallerSupport.leftoverEntryMatches(
                   "Editor_2024-01-01-120000_Mac.plist",
                   identity: leftoverIdentity, crashReporter: true)
               && !UninstallerSupport.leftoverEntryMatches(
                   "Editor_2024-01-01-120000_Mac.plist",
                   identity: leftoverIdentity, crashReporter: false),
               "crash reports may use the app name as a prefix only in that folder")
        expect(UninstallerSupport.ownerBundleID(for: "com.vendor.editor.helper.plist",
                                                identity: leftoverIdentity)
                == "com.vendor.editor.helper"
               && UninstallerSupport.ownerBundleID(for: "Editor", identity: leftoverIdentity)
                == "com.vendor.editor",
               "a helper identifier wins when it is in the name, otherwise the app identifier owns a name match")
        expect(UninstallerSupport.normalizedToken("Example App 2") == "exampleapp2"
               && UninstallerSupport.nameWithoutTrailingVersion("Example App 2") == "Example App"
               && UninstallerSupport.nameWithoutTrailingVersion("Example App Nightly") == "Example App"
               && UninstallerSupport.leftoverMatch(
                   "Example App",
                   identity: UninstallerSupport.identity(bundleIDs: ["com.vendor.exampleapp"],
                                                         displayNames: ["Example App 2"])) == .related
               && UninstallerSupport.leftoverEntryMatches(
                   "ExampleApp2.plist",
                   identity: UninstallerSupport.identity(bundleIDs: ["com.vendor.exampleapp"],
                                                         displayNames: ["Example App 2"])),
               "spaces and trailing version numbers do not hide a leftover named after the app")
        let twoPartIdentity = UninstallerSupport.identity(
            primaryBundleID: "test.editor",
            bundleIDs: ["test.editor"],
            displayNames: ["Editor", "Editor.app"])
        expect(twoPartIdentity.nameTokens.contains("editor")
               && twoPartIdentity.bundleIDs.contains("test.editor"),
               "two-part bundle identifiers yield both display name tokens and exact bundle IDs")
        expect(UninstallerSupport.leftoverMatch("Editor", identity: twoPartIdentity) == .related
               && UninstallerSupport.leftoverMatch("editor", identity: twoPartIdentity) == .related
               && UninstallerSupport.leftoverMatch("test.editor.plist", identity: twoPartIdentity) == .exact
               && UninstallerSupport.leftoverMatch("test.editor", identity: twoPartIdentity) == .exact
               && UninstallerSupport.leftoverMatch("test.editor.helper", identity: twoPartIdentity) == .related
               && UninstallerSupport.leftoverMatch("Unrelated", identity: twoPartIdentity) == .none,
               "two-part bundle identifiers match exact and related leftovers correctly")
        expect(UninstallerSupport.identity(primaryBundleID: "com.vendor.browser",
                                           bundleIDs: ["com.vendor.browser"],
                                           displayNames: ["Vendor Browser"]).nameTokens.contains("browser"),
               "the last identifier component is a token when it names the app")
        let browserIdentity = UninstallerSupport.identity(primaryBundleID: "com.vendor.browser",
                                                          bundleIDs: ["com.vendor.browser"],
                                                          displayNames: ["Vendor Browser"])
        let browserListings = [
            UninstallerSupport.DirListing(name: "Vendor", children: [
                UninstallerSupport.DirListing(name: "Browser", children: []),
                UninstallerSupport.DirListing(name: "Docs", children: []),
            ]),
            UninstallerSupport.DirListing(name: "SuiteApp", children: [
                UninstallerSupport.DirListing(name: "logs", children: []),
            ]),
            UninstallerSupport.DirListing(name: "com.vendor.browser", children: []),
        ]
        expect(UninstallerSupport.leftoverHitRecords(
                   listings: browserListings,
                   identity: browserIdentity,
                   extraChildDepth: 1).map(\.path) == ["Vendor/Browser", "com.vendor.browser"],
               "a leftover nested under a vendor folder is found without taking the whole vendor folder")
        expect(UninstallerSupport.leftoverHitRecords(
                   listings: browserListings,
                   identity: browserIdentity,
                   extraChildDepth: 0).map(\.path) == ["com.vendor.browser"],
               "vendor nesting is not searched when the folder is a leaf location")
        expect(UninstallerSupport.leftoverHitRecords(
                   listings: [UninstallerSupport.DirListing(name: "Browser", children: [
                       UninstallerSupport.DirListing(name: "com.vendor.browser", children: [])
                   ])],
                   identity: browserIdentity,
                   extraChildDepth: 1).map(\.path) == ["Browser/com.vendor.browser"],
               "an exact child wins over a broader related parent folder")
        expect(UninstallerSupport.leftoverHitRecords(
                   listings: [UninstallerSupport.DirListing(
                       name: "Unrelated.component", children: [],
                       bundleIdentifier: "com.vendor.browser")],
                   identity: browserIdentity,
                   extraChildDepth: 0).first?.confidence == .exact,
               "plugin bundle metadata finds a component whose filename does not identify the app")
        expect(UninstallerSupport.leftoverHitRecords(
                   listings: [UninstallerSupport.DirListing(name: "Vendor", children: [
                       UninstallerSupport.DirListing(name: "Mid", children: [
                           UninstallerSupport.DirListing(name: "Editor", children: [])
                       ])
                   ])],
                   identity: leftoverIdentity,
                   extraChildDepth: 2).map(\.path) == ["Vendor/Mid/Editor"],
               "Application Support is searched two levels for vendor/mid/app nesting")
        let teamedIdentity = UninstallerSupport.identity(
            bundleIDs: ["com.vendor.editor"], displayNames: [],
            teamIDs: ["abcd123456"], groupIDs: ["group.com.vendor.editor"])
        expect(UninstallerSupport.leftoverMatch("ABCD123456.com.other", identity: teamedIdentity) == .related
               && UninstallerSupport.leftoverMatch(
                   "ABCD123456.com.vendor.editor", identity: teamedIdentity) == .exact
               && UninstallerSupport.leftoverMatch(
                   "ZZZZ123456.com.vendor.editor", identity: teamedIdentity) == .none
               && UninstallerSupport.leftoverMatch("group.com.vendor.editor", identity: teamedIdentity) == .exact
               && UninstallerSupport.matchingGroupID(
                   "group.com.vendor.editor", identity: teamedIdentity) == "group.com.vendor.editor"
               && UninstallerSupport.containerMetadataMatches("com.vendor.editor",
                                                              identity: leftoverIdentity) == .exact,
               "team prefixes are related, app groups and container metadata keep the exact owner")
        let leftoverFolders = UninstallerSupport.searchFolders(
            home: URL(fileURLWithPath: "/Users/tester"), darwinCache: nil, darwinTemp: nil)
        expect(leftoverFolders.contains(where: {
                   $0.url.path == "/Users/tester/Library/Group Containers" && $0.kind == .containers
                   && $0.readsContainerMetadata && !$0.allowsNameMatches
                   && $0.requiresSignedGroup
               })
               && leftoverFolders.contains(where: {
                   $0.url.path == "/Users/tester/Library/PreferencePanes" && $0.kind == .other
               })
               && leftoverFolders.contains(where: {
                   $0.url.path.hasSuffix("CrashReporter") && $0.crashReporter
               })
               && leftoverFolders.contains(where: { $0.url.path == "/private/var/db/receipts" })
               && leftoverFolders.contains(where: { $0.url.path.hasSuffix("/Automator") })
               && leftoverFolders.contains(where: { $0.url.path.hasSuffix("/Frameworks") })
               && leftoverFolders.contains(where: {
                   $0.url.path == "/Users/tester/.config" && !$0.allowsNameMatches
               })
               && leftoverFolders.contains(where: {
                   $0.url.path == "/Users/tester/Library/Preferences/ByHost"
                       && !$0.allowsNameMatches
               })
               && leftoverFolders.contains(where: {
                   $0.url.path == "/Users/tester/Library/Caches/com.apple.nsurlsessiond/Downloads"
                       && !$0.allowsNameMatches
               })
               && !leftoverFolders.contains(where: { $0.url.path.contains("/Desktop") })
               && leftoverFolders.contains(where: {
                   $0.url.path == "/Users/tester/Library/Application Support" && $0.extraChildDepth == 2
               }),
               "leftover search covers Library support, plugins and receipts, not the Desktop")
        let spotlightQuery = UninstallerSupport.leftoverSpotlightExpression(identity: leftoverIdentity) ?? ""
        expect(spotlightQuery.contains("com.vendor.editor")
               && spotlightQuery.contains("editor")
               && UninstallerSupport.leftoverSpotlightPathIsAllowed(
                    "/Users/tester/Library/Caches/Editor",
                    roots: [URL(fileURLWithPath: "/Users/tester/Library")])
               && !UninstallerSupport.leftoverSpotlightPathIsAllowed(
                    "/Users/tester/Desktop/Editor",
                    roots: [URL(fileURLWithPath: "/Users/tester/Library")]),
               "Spotlight leftovers stay inside Library-like roots")
        let spotlightGroupIdentity = UninstallerSupport.spotlightIdentity(
            for: "/Users/tester/Library/Group Containers/group.com.vendor.editor",
            identity: teamedIdentity)
        let spotlightLaunchIdentity = UninstallerSupport.spotlightIdentity(
            for: "/Users/tester/Library/LaunchAgents/Editor.plist",
            identity: teamedIdentity)
        expect(spotlightGroupIdentity.bundleIDs.isEmpty
               && spotlightGroupIdentity.groupIDs == ["group.com.vendor.editor"]
               && spotlightLaunchIdentity.nameTokens.isEmpty,
               "Spotlight preserves signed-group and technical-only rules for sensitive roots")
        let safetyFixture = FileManager.default.temporaryDirectory
            .appendingPathComponent("vorssaint-uninstaller-\(UUID().uuidString)", isDirectory: true)
        let safetyRoot = safetyFixture.appendingPathComponent("root", isDirectory: true)
        let outsideRoot = safetyFixture.appendingPathComponent("outside", isDirectory: true)
        let safeFile = safetyRoot.appendingPathComponent("safe.plist")
        let replacementFile = safetyRoot.appendingPathComponent("replacement.plist")
        let outsideFile = outsideRoot.appendingPathComponent("foreign.plist")
        let link = safetyRoot.appendingPathComponent("link", isDirectory: true)
        try? FileManager.default.createDirectory(at: safetyRoot, withIntermediateDirectories: true)
        try? FileManager.default.createDirectory(at: outsideRoot, withIntermediateDirectories: true)
        _ = FileManager.default.createFile(atPath: safeFile.path, contents: Data("old".utf8))
        _ = FileManager.default.createFile(atPath: replacementFile.path, contents: Data("new".utf8))
        _ = FileManager.default.createFile(atPath: outsideFile.path, contents: Data("foreign".utf8))
        try? FileManager.default.createSymbolicLink(at: link, withDestinationURL: outsideRoot)
        let originalFileIdentity = UninstallerSupport.fileIdentity(at: safeFile)
        let safePathWasAccepted = UninstallerSupport.removalPathIsSafe(safeFile, within: safetyRoot)
        let linkedPathWasRejected = !UninstallerSupport.removalPathIsSafe(
            link.appendingPathComponent("foreign.plist"), within: safetyRoot)
        try? FileManager.default.removeItem(at: safeFile)
        try? FileManager.default.moveItem(at: replacementFile, to: safeFile)
        expect(safePathWasAccepted && linkedPathWasRejected
               && originalFileIdentity != nil
               && UninstallerSupport.fileIdentity(at: safeFile) != originalFileIdentity,
               "removal stays inside its scan root, rejects symlink escapes and detects path replacement")
        try? FileManager.default.removeItem(at: safetyFixture)
        // Building the installed-apps oracle walks the application folders, and
        // the removal guard reads it under `.leftovers` alone — with leftover
        // rows unchecked by default, the common clean must not pay for that
        // walk. JunkCleaner is not part of this test binary, so pin the gate
        // and the premise that makes an empty oracle safe at their source.
        let junkCleanerSource = (try? String(
            contentsOfFile: "Sources/Vorssaint/Services/Cleaner/JunkCleaner.swift",
            encoding: .utf8)) ?? ""
        let cleanSelectedBody = sourceBody(of: junkCleanerSource, from: "func cleanSelected(",
                                           to: "private static func mayRemove")
        expect(cleanSelectedBody.contains("chosen.contains { $0.category == .leftovers }")
               && cleanSelectedBody.contains("? Self.installedBundleIDs() : []")
               && !cleanSelectedBody.contains("let installed = Self.installedBundleIDs()"),
               "a clean builds the installed-apps oracle only when a leftover row is selected")
        let mayRemoveBody = sourceBody(of: junkCleanerSource, from: "private static func mayRemove",
                                       to: "private static func trashViaFinder")
        let leftoverBranch = mayRemoveBody.range(of: "if item.category == .leftovers")
        expect(mayRemoveBody.components(separatedBy: "installed: installed").count == 2,
               "the removal guard consults the installed-apps oracle exactly once")
        expect(leftoverBranch.map { branch in
                   mayRemoveBody.range(of: "installed: installed",
                                       range: branch.upperBound..<mayRemoveBody.endIndex) != nil
               } == true,
               "the removal guard reads the installed-apps oracle inside its leftovers branch")
        // The known-application roster opens every installed app, and only the
        // shared-data claims read it. AppUninstaller is not part of this test
        // binary either, so pin the gate that keeps a removal that cannot claim
        // shared data from paying for the roster.
        let appUninstallerSource = (try? String(
            contentsOfFile: "Sources/Vorssaint/Services/Uninstall/AppUninstaller.swift",
            encoding: .utf8)) ?? ""
        let removeSelectedBody = sourceBody(of: appUninstallerSource, from: "func removeSelected()",
                                            to: "func removeSelectedWithHomebrew()")
        expect(removeSelectedBody.contains("let knownApplications = mayClaimSharedData"),
               "a removal builds the known-application roster only when it may claim shared data")
        expect(CleanerSupport.bundleIDCandidate(fromEntryName: "com.vendor.editor.prefPane")
                == "com.vendor.editor",
               "preference panes map to their owning bundle identifier")
        expect(CleanerSupport.bundleIDCandidate(fromEntryName: "app-0.0.409") == nil
               && CleanerSupport.bundleIDCandidate(fromEntryName: "0.0.409") == nil
               && CleanerSupport.bundleIDCandidate(fromEntryName: "1.57.0") == nil
               && CleanerSupport.bundleIDCandidate(fromEntryName: "com.v2.editor")
                == "com.v2.editor",
               "version directories never become deletion ownership evidence")
        let supportRoot = URL(fileURLWithPath: "/Users/tester/Library/Application Support")
        expect(CleanerSupport.isDirectChild(
                   supportRoot.appendingPathComponent("com.vendor.editor"), of: supportRoot)
               && !CleanerSupport.isDirectChild(
                   supportRoot.appendingPathComponent("vendor/app-0.0.409"), of: supportRoot),
               "the general Cleaner accepts only direct children of each leftover root")
        expect(CleanerSupport.bundleIDCandidate(fromEntryName:
               "com.vendor.editor.Helper.B787EFF9-B8E2-5296-96AF-DF9D3CD3AC4F.plist")
                == "com.vendor.editor.Helper"
               && CleanerSupport.bundleIDCandidate(fromEntryName:
               "com.vendor.B787EFF9-B8E2-5296-96AF-DF9D3CD3AC4F.editor") == nil
               && CleanerSupport.bundleIDCandidate(fromEntryName: "ABCD123456.com.vendor.editor")
                == "com.vendor.editor",
               "ByHost UUIDs and team prefixes unwrap to the owning identifier")
        expect(CleanerSupport.hasSharedContainerWrapper("group.com.vendor.editor")
               && CleanerSupport.hasSharedContainerWrapper("ABCD123456.com.vendor.editor")
               && !CleanerSupport.hasSharedContainerWrapper("abcd123456.com.vendor.editor")
               && !CleanerSupport.hasSharedContainerWrapper("com.vendor.editor"),
               "the general Cleaner leaves shared-container wrappers to signed app-specific scans")
        let helperAppIdentity = UninstallerSupport.identity(
            primaryBundleID: "com.vendor.chat",
            bundleIDs: ["com.vendor.chat", "com.vendor.chat.helper.Renderer", "com.vendor.chat.helper.GPU"],
            displayNames: ["Chat App"])
        expect(!helperAppIdentity.nameTokens.contains("renderer")
               && !helperAppIdentity.nameTokens.contains("gpu")
               && helperAppIdentity.nameTokens.contains("chatapp")
               && UninstallerSupport.leftoverMatch("renderer.log", identity: helperAppIdentity) == .none
               && !UninstallerSupport.leftoverSpotlightPathIsAllowed(
                    "/Users/tester/Library/Application Support/OtherApp/logs/sub/renderer.log",
                    roots: [URL(fileURLWithPath: "/Users/tester/Library/Application Support")]),
               "helper subprocess roles and deeply nested foreign logs are never claimed as leftovers")
        expect(CleanerSupport.isProtectedBundleID("systemgroup.com.apple.icloud.searchpartyd.sharedsettings")
               && CleanerSupport.isProtectedBundleID("243LU875E5.groups.com.apple.podcasts")
               && CleanerSupport.isProtectedBundleID("developer.apple.wwdc")
               && CleanerSupport.isProtectedBundleID("is.workflow.my.app")
               && CleanerSupport.isProtectedBundleID("vorss.tests.switcher.shortcut"),
               "system domains stay protected in every wrapping, team prefixes included")
        expect(CleanerSupport.sharedInfrastructurePrefixes.allSatisfy {
                   CleanerSupport.isProtectedBundleID($0)
               },
               "embedded updaters and crash reporters can never be junk owners")
        expect(CleanerSupport.bundleIDCandidate(fromEntryName: "systemgroup.com.apple.icloud.sharedsettings.plist")
               == "com.apple.icloud.sharedsettings",
               "systemgroup wrappers unwrap to the real owner")
        expect(CleanerSupport.bundleIDCandidate(fromEntryName:
               "com.vendor.B787EFF9-B8E2-5296-96AF-DF9D3CD3AC4F.editor") == nil,
               "a UUID in the middle of a name stays unattributable")
        expect(CleanerSupport.containsUUIDComponent("x.B787EFF9-B8E2-5296-96AF-DF9D3CD3AC4F")
               && !CleanerSupport.containsUUIDComponent("com.vendor.editor"),
               "the UUID detector matches dashed UUIDs and nothing else")
        expect(CleanerSupport.sharesVendorNamespace(candidate: "com.vendor.backgroundtool",
                                                    withInstalled: ["com.vendor.editor"])
               && CleanerSupport.sharesVendorNamespace(candidate: "com.publisher.agent",
                                                       withInstalled: ["com.publisher.browser"]),
               "a vendor's updaters are owned while any app of that vendor is installed")
        expect(!CleanerSupport.sharesVendorNamespace(candidate: "com.vendor.editor",
                                                     withInstalled: ["com.publisher.browser"]),
               "different vendors never own each other")
        expect(!CleanerSupport.sharesVendorNamespace(candidate: "io.github.account.tool",
                                                     withInstalled: ["io.github.other.app"]),
               "code hosting namespaces are shared by unrelated developers and never match")
        expect(CleanerPolicy.precheckCacheEntry("Homebrew")
               && CleanerPolicy.precheckCacheEntry("com.vendor.editor"),
               "download caches and third party app caches start checked")
        expect(!CleanerPolicy.precheckCacheEntry("PlainVendorFolder")
               && !CleanerPolicy.precheckCacheEntry("com.apple.Music")
               && !CleanerPolicy.precheckCacheEntry("com.spotify.client")
               && !CleanerPolicy.precheckCacheEntry("ms-playwright"),
               "system, sensitive and unattributable caches start unchecked")
        expect(CleanerSupport.Category.deviceBackups.rawValue == 6
               && CleanerSupport.Category.allCases.count == 7,
               "device backups joined the cleaner with a stable category id")
        expect(!CleanerPolicy.precheckDeviceBackups,
               "device backups never start checked, they are the user's safety net")
        // CleanerScheduler and CleanerView are outside this test binary, so
        // pin escalation at the call sites: the unattended pass must never
        // reach Finder's administrator prompt, and no default lets a later
        // automatic caller inherit it.
        let compact = { (path: String) -> String in
            ((try? String(contentsOfFile: path, encoding: .utf8)) ?? "")
                .split(whereSeparator: \.isWhitespace).joined()
        }
        let schedulerCode = compact("Sources/Vorssaint/Services/Cleaner/CleanerScheduler.swift")
        let cleanerViewCode = compact("Sources/Vorssaint/UI/Cleaner/CleanerView.swift")
        expect(schedulerCode.components(separatedBy: "cleanSelected(").count == 2
               && schedulerCode.contains("cleanSelected(escalate:false)")
               && schedulerCode.contains("notifyIfWanted(freed:freed,failed:failed)"),
               "the scheduled clean never escalates and reports what it left in place")
        expect(junkCleanerSource.contains("func cleanSelected(escalate: Bool) {")
               && cleanerViewCode.components(separatedBy: "cleanSelected(").count == 2
               && cleanerViewCode.contains("cleanSelected(escalate:true)"),
               "cleanSelected has no default escalation and the manual clean still asks")
        expect(CleanerPolicy.developerJunkPaths.contains("/Library/Developer/Xcode/iOS DeviceSupport")
               && CleanerPolicy.developerJunkPaths.contains("/Library/Developer/Xcode/watchOS DeviceSupport"),
               "stale DeviceSupport symbol caches count as developer junk")
        expect(CleanerSupport.looksLikeBundleID("com.vendor.editor")
               && CleanerSupport.looksLikeBundleID("com.foo.Bar-Helper_2")
               && CleanerSupport.looksLikeBundleID("test.editor")
               && CleanerSupport.looksLikeBundleID("editor.test")
               && CleanerSupport.looksLikeBundleID("com.foo"),
               "reverse DNS names and two-component bundle identifiers are recognized")
        expect(!CleanerSupport.looksLikeBundleID("VendorFolder")
               && !CleanerSupport.looksLikeBundleID("Editor")
               && !CleanerSupport.looksLikeBundleID("com..foo")
               && !CleanerSupport.looksLikeBundleID(".com.foo")
               && !CleanerSupport.looksLikeBundleID("com.foo.")
               && !CleanerSupport.looksLikeBundleID("com.foo.bár"),
               "plain names, empty parts and odd characters never match by name")
        expect(CleanerSupport.bundleIDCandidate(fromEntryName: "com.vendor.editor.plist") == "com.vendor.editor"
               && CleanerSupport.bundleIDCandidate(fromEntryName: "test.editor.plist") == "test.editor"
               && CleanerSupport.bundleIDCandidate(fromEntryName: "group.com.foo.bar") == "com.foo.bar"
               && CleanerSupport.bundleIDCandidate(fromEntryName: "group.test.editor") == "test.editor"
               && CleanerSupport.bundleIDCandidate(fromEntryName: "ABCD123456.test.editor") == "test.editor"
               && CleanerSupport.bundleIDCandidate(fromEntryName: "com.foo.bar.savedState") == "com.foo.bar"
               && CleanerSupport.bundleIDCandidate(fromEntryName: "com.foo.bar.binarycookies") == "com.foo.bar",
               "entry names map to their owning bundle identifier")
        expect(CleanerSupport.bundleIDCandidate(fromEntryName: "VendorFolder") == nil,
               "folders without a bundle shaped name are never candidates")
        expect(CleanerSupport.isOwned(candidate: "com.vendor.editor.startuphelper",
                                      byInstalled: ["com.vendor.editor"]),
               "embedded helper identifiers are owned by their installed app")
        expect(CleanerSupport.isOwned(candidate: "com.maker",
                                      byInstalled: ["com.maker.app"]),
               "a family prefix of an installed app counts as owned")
        expect(!CleanerSupport.isOwned(candidate: "com.vendor.editor", byInstalled: ["com.publisher.browser"]),
               "identifiers with no installed relative are unowned")
        expect(!CleanerSupport.isOwned(candidate: "com.makerapp.tool", byInstalled: ["com.maker.app"]),
               "prefix ownership requires a dot boundary, not a string prefix")
        expect(CleanerSupport.executablePaths(inLaunchPlist: [
                   "Program": "/Applications/Gone.app/Contents/MacOS/agent",
                   "ProgramArguments": ["/usr/local/bin/gone-tool", "--flag"],
                   "BundleProgram": "Contents/MacOS/relative",
               ]) == ["/Applications/Gone.app/Contents/MacOS/agent", "/usr/local/bin/gone-tool"],
               "launch plists yield their absolute executables and skip relative ones")
        expect(CleanerSupport.launchPlistIsRemovableOrphan(label: "com.vendor.editor.launchdaemon",
                                                           executables: ["/Applications/Gone.app/x"],
                                                           executableExists: { _ in false }),
               "a plist whose executables are all gone is a removable orphan")
        expect(!CleanerSupport.launchPlistIsRemovableOrphan(label: "com.vendor.editor.launchdaemon",
                                                            executables: ["/bin/ls"],
                                                            executableExists: { _ in true }),
               "a plist with a living executable is never an orphan")
        expect(!CleanerSupport.launchPlistIsRemovableOrphan(label: "com.apple.something",
                                                            executables: ["/gone"],
                                                            executableExists: { _ in false })
               && !CleanerSupport.launchPlistIsRemovableOrphan(label: nil,
                                                               executables: [],
                                                               executableExists: { _ in false }),
               "system agents and undecidable plists are never offered")
    }

    static func runFailurePresentation(expect: (Bool, String) -> Void) {
        // MARK: A failed removal explains itself where it failed
        // A green tick above "some items couldn't be moved to the Trash" told
        // nobody that sandboxed app data needs Full Disk Access, and the note
        // offering the permission only ever appeared before an app was picked.
        expect(UninstallerSupport.doneSymbol(hasLeftovers: false) == "checkmark.circle.fill",
               "a removal that took everything ends on a tick")
        expect(UninstallerSupport.doneSymbol(hasLeftovers: true)
                != UninstallerSupport.doneSymbol(hasLeftovers: false),
               "a removal that left something behind does not end on the same mark")
        // The permission note has to be true when it appears: only sandboxed
        // container data is gated by Full Disk Access, so a failure list made
        // of ownership or identity refusals must not offer it.
        let fdaHome = "/Users/someone"
        expect(UninstallerSupport.failureNeedsFullDiskAccess(
                   paths: [fdaHome + "/Library/Containers/com.vendor.editor"]),
               "a failed container is the case Full Disk Access would have changed")
        expect(UninstallerSupport.failureNeedsFullDiskAccess(
                   paths: [fdaHome + "/Library/Application Support/Editor",
                           fdaHome + "/Library/Group Containers/group.com.vendor.editor",
                           fdaHome + "/Library/Caches/com.vendor.editor"]),
               "one failed container among others is enough to offer the permission")
        expect(UninstallerSupport.failureNeedsFullDiskAccess(
                   paths: [fdaHome + "/Library/Application Scripts/com.vendor.editor"]),
               "application scripts sit behind the same permission as containers")
        expect(!UninstallerSupport.failureNeedsFullDiskAccess(
                   paths: ["/Applications/Editor.app",
                           fdaHome + "/Library/Application Support/Editor",
                           fdaHome + "/Library/Preferences/com.vendor.editor.plist",
                           "/Library/LaunchAgents/com.vendor.editor.plist"]),
               "failures outside containers never offer a permission that would not help")
        expect(!UninstallerSupport.failureNeedsFullDiskAccess(paths: []),
               "no failure, no permission note")
        // Both done states have to route through that decision and name what
        // survived; neither may spell a tick of its own.
        for path in ["Sources/Vorssaint/UI/Uninstall/UninstallerView.swift",
                     "Sources/Vorssaint/UI/MenuPanel/PanelUninstallerView.swift"] {
            let source = (try? String(contentsOfFile: path, encoding: .utf8)) ?? ""
            expect(source.contains("UninstallFailureNote(items:"),
                   "\(path) names what the removal left behind")
            expect(!source.contains("\"checkmark.circle.fill\""),
                   "\(path) takes its done symbol from UninstallerSupport")
        }
        let sharedUISource = (try? String(contentsOfFile: "Sources/Vorssaint/UI/SharedUI.swift",
                                          encoding: .utf8)) ?? ""
        expect(sharedUISource.contains("uninstallerFailedNeedsFDA"),
               "the failure note explains the permission the removal needed")
    }
}
