// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import Carbon.HIToolbox
import Combine
import CoreAudio
import CoreGraphics
import Darwin
import Foundation
import ImageIO
import VMStatisticsCompat

enum RepositoryFeatureTests {
    private struct SourceRead: Sendable {
        let path: String
        let source: String?
        let lines: [String]
        let error: String?
    }

    private final class SourceReadCollector: @unchecked Sendable {
        private let lock = NSLock()
        private var reads: [SourceRead] = []

        func append(contentsOf batch: [SourceRead]) {
            lock.withLock { reads.append(contentsOf: batch) }
        }

        func sortedReads() -> [SourceRead] {
            lock.withLock { reads.sorted { $0.path < $1.path } }
        }
    }

    private struct RepositorySnapshot {
        let swiftPaths: [String]
        let swiftSources: [String: String]
        let swiftLines: [String: [String]]
        let enumerationError: String?
        let readTimedOut: Bool
        let unreadablePaths: [String]
        let emptyPaths: [String]

        init(fileManager: FileManager = .default) {
            let paths: [String]
            var traversalError: String?
            do {
                paths = Array(Set(try fileManager.subpathsOfDirectory(atPath: "Sources")
                    .filter { $0.hasSuffix(".swift") }
                    .map { "Sources/" + $0 })).sorted()
            } catch {
                paths = []
                traversalError = String(describing: error)
            }

            let workerCount = min(paths.count, max(1, min(8, ProcessInfo.processInfo.activeProcessorCount)))
            let collector = SourceReadCollector()
            let queue = OperationQueue()
            queue.name = "RepositorySnapshot.SourceReads"
            queue.qualityOfService = .userInitiated
            queue.maxConcurrentOperationCount = max(1, workerCount)
            let readGroup = DispatchGroup()
            let operations: [Operation] = (0..<workerCount).map { workerIndex in
                readGroup.enter()
                return BlockOperation {
                    defer { readGroup.leave() }
                    var batch: [SourceRead] = []
                    batch.reserveCapacity((paths.count + workerCount - 1) / workerCount)
                    for index in stride(from: workerIndex, to: paths.count, by: workerCount) {
                        let path = paths[index]
                        do {
                            let source = try String(contentsOfFile: path, encoding: .utf8)
                            batch.append(SourceRead(path: path, source: source,
                                                   lines: source.components(separatedBy: "\n"),
                                                   error: nil))
                        } catch {
                            batch.append(SourceRead(path: path, source: nil, lines: [],
                                                   error: String(describing: error)))
                        }
                    }
                    collector.append(contentsOf: batch)
                }
            }
            queue.addOperations(operations, waitUntilFinished: false)
            let timedOut = readGroup.wait(timeout: .now() + 15) == .timedOut
            if timedOut { queue.cancelAllOperations() }

            let reads = collector.sortedReads()
            let sources = Dictionary(uniqueKeysWithValues: reads.compactMap { read in
                read.source.map { (read.path, $0) }
            })
            let lines = Dictionary(uniqueKeysWithValues: reads.compactMap { read in
                read.source.map { _ in (read.path, read.lines) }
            })

            swiftPaths = paths
            swiftSources = sources
            swiftLines = lines
            enumerationError = traversalError
            readTimedOut = timedOut
            unreadablePaths = reads.compactMap { read in
                read.error.map { "\(read.path): \($0)" }
            }
            emptyPaths = reads.compactMap { read in
                guard let source = read.source,
                      source.rangeOfCharacter(from: .whitespacesAndNewlines.inverted) == nil else { return nil }
                return read.path
            }
        }

        func source(at path: String) -> String {
            swiftSources[path] ?? ""
        }

        func lines(at path: String) -> [String] {
            swiftLines[path] ?? []
        }
    }

    static func run(_ suite: TestSuite) {
        func expectEqual(_ actual: String, _ expected: String, _ label: String,
                         file: StaticString = #filePath, line: UInt = #line) {
            suite.expect(actual == expected, "\(label): got \(actual), expected \(expected)",
                         file: file, line: line)
        }
        let repository = RepositorySnapshot()
        suite.expect(repository.enumerationError == nil,
               "the Swift source corpus is enumerable: \(repository.enumerationError ?? "")")
        suite.expect(!repository.swiftPaths.isEmpty,
               "the Swift source corpus contains files")
        suite.expect(!repository.readTimedOut,
               "the Swift source corpus finishes reading inside its bounded deadline")
        suite.expect(repository.unreadablePaths.isEmpty,
               "every Swift source is readable: \(repository.unreadablePaths)")
        suite.expect(repository.emptyPaths.isEmpty,
               "no Swift source is empty: \(repository.emptyPaths)")
        let requiredSourcePaths = [
            "Sources/Vorssaint/Services/CommandBar/CommandBarSupport.swift",
            "Sources/Vorssaint/Services/Homebrew/HomebrewManager.swift",
            "Sources/Vorssaint/Services/Metrics/DiskSampler.swift",
            "Sources/Vorssaint/Services/QuickTools/RecentCaptureService.swift",
            "Sources/Vorssaint/Services/QuickTools/RecentCaptureStore.swift",
            "Sources/Vorssaint/Services/SelfUninstall.swift",
            "Sources/Vorssaint/Services/Shelf/ShelfService.swift",
            "Sources/Vorssaint/Support/Uninstaller.swift",
            "Sources/Vorssaint/UI/Settings/URLCleanerSettings.swift",
            "Sources/Vorssaint/UI/Theme.swift",
        ]
        let missingSourcePaths = requiredSourcePaths.filter {
            repository.swiftSources[$0] == nil
        }
        suite.expect(missingSourcePaths.isEmpty,
               "every directly inspected Swift source is present: \(missingSourcePaths)")
        let buildScript = (try? String(contentsOfFile: "build.sh", encoding: .utf8)) ?? ""
        suite.expect(!buildScript.isEmpty, "build.sh is readable for repository contracts")

        // MARK: URL cleaning

        expectEqual(URLCleaning.clean("https://example.com/path?utm_source=news&id=42&fbclid=abc")?.url ?? "",
                    "https://example.com/path?id=42",
                    "URL cleaner removes tracking and preserves useful query")
        expectEqual(URLCleaning.clean(" https://example.com/?GCLID=one&utm_campaign=x#section ")?.url ?? "",
                    "https://example.com/#section",
                    "URL cleaner is case-insensitive and preserves fragments")
        expectEqual(URLCleaning.clean("https://example.com/?id=42")?.url ?? "",
                    "https://example.com/?id=42",
                    "URL cleaner leaves clean URLs alone")
        let customURLParameters = URLCleaning.customParameters(from: " Ref, source\nref,  ")
        suite.expect(customURLParameters == ["ref", "source"],
               "URL cleaner normalizes comma-separated custom parameter names")
        let customURLRules = URLCleaning.rules(globalNames: " Ref, source\nref,  ",
                                               siteNames: nil, disabledNames: nil)
        expectEqual(URLCleaning.clean("https://example.com/?REF=one&id=42&source=two",
                                              rules: customURLRules)?.url ?? "",
                    "https://example.com/?id=42",
                    "URL cleaner removes custom parameters by exact case-insensitive name")
        expectEqual(URLCleaning.clean("https://example.com/?reference=one",
                                              rules: customURLRules)?.url ?? "",
                    "https://example.com/?reference=one",
                    "URL cleaner does not treat custom parameter names as prefixes")
        // A grouped Form keeps a label column even for an empty label, which
        // left every field on the right half of its row. The hint has to
        // travel as `prompt:` and the label has to be hidden for a field to
        // own its whole row.
        let urlCleanerSettingsSource = repository.source(
            at: "Sources/Vorssaint/UI/Settings/URLCleanerSettings.swift")
        suite.expect(!urlCleanerSettingsSource.contains("TextField(l10n.s."),
               "no Clean URL field spends its row on a label instead of the field")
        suite.expect(urlCleanerSettingsSource.components(separatedBy: "TextField(").count
                == urlCleanerSettingsSource.components(separatedBy: ".labelsHidden()").count,
               "every Clean URL field hides its label so the field owns the row")

        // Rules are stored as a difference from the built-in tables, never as
        // a copy of them, so names a later version adds still reach someone
        // who has already edited their rules.
        let keptUTM = URLCleaning.rules(globalNames: nil, siteNames: nil, disabledNames: "|utm_*")
        expectEqual(URLCleaning.clean("https://example.com/?utm_source=news&fbclid=abc&id=1",
                                      rules: keptUTM)?.url ?? "",
                    "https://example.com/?utm_source=news&id=1",
                    "switching the utm row off keeps every utm name and leaves the rest cleaning")
        let keptShareToken = URLCleaning.rules(globalNames: nil, siteNames: nil,
                                               disabledNames: "youtube.com|si")
        expectEqual(URLCleaning.clean("https://www.youtube.com/watch?v=1&si=x&feature=share",
                                      rules: keptShareToken)?.url ?? "",
                    "https://www.youtube.com/watch?v=1&si=x",
                    "a switched off site name stays in the link while its siblings still go")
        let addedSiteRule = URLCleaning.rules(globalNames: nil, siteNames: "weibo.com|sudaref",
                                              disabledNames: nil)
        expectEqual(URLCleaning.clean("https://weibo.com/a?sudaref=x&id=1", rules: addedSiteRule)?.url ?? "",
                    "https://weibo.com/a?id=1",
                    "a name added to one site cleans that site")
        expectEqual(URLCleaning.clean("https://example.com/?sudaref=x", rules: addedSiteRule)?.url ?? "",
                    "https://example.com/?sudaref=x",
                    "a name added to one site never reaches another")
        suite.expect(URLCleaning.clean("https://example.com/?utm_source=a&fbclid=b&id=1")?.removed
                == ["utm_source", "fbclid"],
               "cleaning answers with the names it took out, in the order the link carried them")
        suite.expect(URLCleaning.outcome(for: nil, input: "nope") == .notAURL,
               "text that is not a link reads as no URL")
        let paddedLink = " https://example.com/?id=1 "
        suite.expect(URLCleaning.outcome(for: URLCleaning.clean(paddedLink), input: paddedLink) == .unchanged,
               "trimming alone does not count as a clean")

        let editedRules = URLCleaning.rules(globalNames: "ref", siteNames: "weibo.com|sudaref",
                                            disabledNames: "|fbclid")
        let ruleGroups = URLCleaning.ruleGroups(rules: editedRules)
        suite.expect(ruleGroups.first?.site == URLCleaning.allSites,
               "the rules that apply everywhere lead the list")
        suite.expect(ruleGroups.first?.entries.first?.name == URLCleaning.utmWildcard,
               "one row stands for every utm name")
        suite.expect(ruleGroups.first?.entries.allSatisfy {
            $0.name == URLCleaning.utmWildcard || !$0.name.hasPrefix("utm_")
        } == true, "the utm names that row already covers are not listed again")
        suite.expect(ruleGroups.first?.entries.contains { $0.name == "fbclid" && !$0.isEnabled } == true,
               "a switched off built-in stays listed so it can be switched back on")
        suite.expect(ruleGroups.first?.entries.contains { $0.name == "ref" && !$0.isBuiltIn } == true,
               "names the user added share the list with the built-in ones")
        suite.expect(ruleGroups.contains { $0.site == "weibo.com" },
               "a site the user added gets a row of its own")
        suite.expect(ruleGroups.contains { $0.site == "youtube.com" },
               "every built-in site is listed")
        expectEqual(URLCleaning.clean("https://www.xiaohongshu.com/?shareRedId=a&exSource=b&id=1")?.url ?? "",
                    "https://www.xiaohongshu.com/?id=1",
                    "a built-in name spelled in mixed case by the site is still removed")
        let upperCaseBuiltIns = URLCleaning.ruleGroups(rules: .none)
            .flatMap(\.entries).map(\.name).filter { $0 != $0.lowercased() }
        suite.expect(upperCaseBuiltIns.isEmpty,
               "built-in names are lowercase, since matching and switched off names are: \(upperCaseBuiltIns)")
        expectEqual(URLCleaning.siteKey(from: " https://WWW.Weibo.com/path?x=1 ") ?? "",
                    "weibo.com", "the site field takes a pasted link and keeps the host")
        suite.expect(URLCleaning.siteKey(from: "not a host") == nil,
               "text that is not a host is refused rather than stored")
        expectEqual(URLCleaning.parameterName(from: " Ref ") ?? "", "ref",
                    "a parameter name is trimmed and lowercased")
        suite.expect(URLCleaning.parameterName(from: "a=b") == nil,
               "a name a query cannot carry as one parameter is refused")
        suite.expect(URLCleaning.tokens(from: "youtube.com|si, |ref") == ["youtube.com": ["si"], "": ["ref"]],
               "stored tokens read back as site and global names")
        expectEqual(URLCleaning.storageValue(forTokens: URLCleaning.tokens(from: "youtube.com|si, |ref")),
                    "|ref,youtube.com|si", "tokens are stored in a stable order")

        suite.expect([DefaultsKey.urlCleanerCustomParameters,
                DefaultsKey.urlCleanerSiteParameters,
                DefaultsKey.urlCleanerDisabledParameters].allSatisfy {
                    Defaults.registeredDefaults[$0] as? String == ""
                        && SettingsBackupSupport.exportKeys().contains($0)
                },
               "URL cleaner rules start empty and travel in Settings backups")
        suite.expect(URLCleaning.clean("not a url") == nil,
               "URL cleaner rejects plain text")
        expectEqual(URLCleaning.clean("https://www.bilibili.com/video/BV1TY8J67EUB/?spm_id_from=333.1007.tianma.1-1-1.click&vd_source=3b2eea5")?.url ?? "",
                    "https://www.bilibili.com/video/BV1TY8J67EUB/",
                    "URL cleaner strips Bilibili share tracking")
        expectEqual(URLCleaning.clean("https://www.bilibili.com/video/BV1xx411c7mD/?p=3&t=90&vd_source=abc")?.url ?? "",
                    "https://www.bilibili.com/video/BV1xx411c7mD/?p=3&t=90",
                    "URL cleaner keeps the Bilibili part number and playback position")
        expectEqual(URLCleaning.clean("https://search.bilibili.com/all?keyword=swift&from_source=webtop_search")?.url ?? "",
                    "https://search.bilibili.com/all?keyword=swift",
                    "URL cleaner keeps the Bilibili search keyword")
        expectEqual(URLCleaning.clean("https://youtu.be/TImSMeurR84?si=Xq1&t=42")?.url ?? "",
                    "https://youtu.be/TImSMeurR84?t=42",
                    "URL cleaner strips the YouTube share token and keeps the timestamp")
        expectEqual(URLCleaning.clean("https://www.youtube.com/watch?v=TImSMeurR84")?.url ?? "",
                    "https://www.youtube.com/watch?v=TImSMeurR84",
                    "URL cleaner leaves a bare YouTube watch link alone")
        expectEqual(URLCleaning.clean("https://x.com/user/status/1?s=20&t=abc")?.url ?? "",
                    "https://x.com/user/status/1",
                    "URL cleaner strips X share tracking")
        expectEqual(URLCleaning.clean("https://example.com/?si=keep&t=keep&s=keep")?.url ?? "",
                    "https://example.com/?si=keep&t=keep&s=keep",
                    "site rules never leak onto other hosts")
        expectEqual(URLCleaning.clean("https://open.spotify.com/track/abc?si=xyz")?.url ?? "",
                    "https://open.spotify.com/track/abc",
                    "site rules match subdomains")
        expectEqual(URLCleaning.clean("https://www.reddit.com/r/swift/comments/abc/?%24deep_link=true&%243p=x&share_id=y&sort=new")?.url ?? "",
                    "https://www.reddit.com/r/swift/comments/abc/?sort=new",
                    "URL cleaner strips Reddit's deep-link tracking in either spelling")

        suite.expect(URLCleaning.canRewritePasteboard(types: [
            "public.utf8-plain-text", "public.url", "public.url-name",
            "NSStringPboardType", "NSURLPboardType",
        ]), "a plain link copy can be rewritten")
        suite.expect(!URLCleaning.canRewritePasteboard(types: []),
               "an empty pasteboard is left alone")
        suite.expect(URLCleaning.canRewritePasteboard(types: [
            "public.utf8-plain-text", "public.html", "public.rtf", "com.apple.flat-rtfd",
            "public.utf16-external-plain-text",
        ]), "formatted copies of the same link are dropped by the rewrite, not protected")
        suite.expect(URLCleaning.canRewritePasteboard(types: [
            "public.utf8-plain-text", "public.url", "org.chromium.source-url",
            "org.chromium.web-custom-data", "com.apple.WebKit.custom-pasteboard-data",
            "dyn.ah62d4rv4gu8y6y4grf0gn5xbrzw1gydcr7u1e3cytf2gn",
        ]), "a browser's or a messaging app's private notes about the copy do not block the rewrite")
        suite.expect(!URLCleaning.canRewritePasteboard(types: [
            "public.utf8-plain-text", "public.url", "public.tiff", "public.png",
        ]), "a copied picture with its source link as text is left alone")
        suite.expect(!URLCleaning.canRewritePasteboard(types: [
            "public.utf8-plain-text", "public.file-url", "NSFilenamesPboardType",
        ]) && !URLCleaning.canRewritePasteboard(types: [
            "public.utf8-plain-text", "NSFilenamesPboardType",
        ]) && !URLCleaning.canRewritePasteboard(types: [
            "public.utf8-plain-text", "com.apple.pasteboard.promised-file-url",
            "com.apple.pasteboard.promised-file-content-type",
        ]), "a copied or promised file is left alone")
        suite.expect(!URLCleaning.canRewritePasteboard(types: [
            "public.utf8-plain-text", "com.adobe.pdf",
        ]) && !URLCleaning.canRewritePasteboard(types: [
            "public.utf8-plain-text", "public.mpeg-4",
        ]) && !URLCleaning.canRewritePasteboard(types: [
            "public.utf8-plain-text", "com.apple.webarchive",
        ]), "a document, a movie or a web archive next to the text is left alone")
        suite.expect(!URLCleaning.canRewritePasteboard(types: [
            "public.utf8-plain-text", "org.nspasteboard.ConcealedType",
        ]) && !URLCleaning.canRewritePasteboard(types: [
            "public.utf8-plain-text", "org.nspasteboard.TransientType",
        ]), "a concealed or transient copy is never rewritten")

        // MARK: Homebrew command building and parsing

        let homebrewManagerSource = repository.source(
            at: "Sources/Vorssaint/Services/Homebrew/HomebrewManager.swift")
        let homebrewRunStreaming = homebrewManagerSource.components(separatedBy: "func runStreaming(")
            .dropFirst().first?.components(separatedBy: "private func appendLog").first ?? ""
        suite.expect(homebrewRunStreaming.contains("brewSilenceTimeout")
                && !homebrewRunStreaming.contains("waitUntilExit"),
               "Homebrew operations wait on a bounded semaphore, not waitUntilExit")

        suite.expect(HomebrewPackageKind.allCases == [.cask, .formula],
               "Homebrew package kinds keep casks before formulae")
        suite.expect(HomebrewCommandBuilder.isValidToken("jq"), "simple Homebrew token is valid")
        suite.expect(HomebrewCommandBuilder.isValidToken("python@3.14"), "versioned formula token is valid")
        suite.expect(HomebrewCommandBuilder.isValidToken("visual-studio-code"), "cask token is valid")
        suite.expect(HomebrewCommandBuilder.isValidToken("homebrew/cask-fonts/font-iosevka"), "tapped token is valid")
        suite.expect(!HomebrewCommandBuilder.isValidToken(""), "empty Homebrew token is invalid")
        suite.expect(HomebrewCommandBuilder.untrustedTapName(fromOutput:
            "Error: Refusing to load formula foo from untrusted tap someone/sometap.\nRun `brew trust someone/sometap` to trust it.")
            == "someone/sometap",
               "untrusted tap name is extracted from Homebrew's refusal")
        suite.expect(HomebrewCommandBuilder.untrustedTapName(fromOutput: "Error: no such formula") == nil,
               "other Homebrew errors extract no tap")
        suite.expect(HomebrewCommandBuilder.untrustedTapName(fromOutput:
            "from untrusted tap ../evil") == nil,
               "a tap name that fails token validation is rejected")
        let trustCommand = HomebrewCommandBuilder.trustTap(brewPath: "/opt/homebrew/bin/brew", tap: "someone/sometap")
        suite.expect(trustCommand.arguments == ["trust", "--tap", "someone/sometap"],
               "trust command targets the tap explicitly")
        suite.expect(!HomebrewCommandBuilder.isValidToken("-bad"), "leading dash Homebrew token is invalid")
        suite.expect(!HomebrewCommandBuilder.isValidToken("../bad"), "path traversal Homebrew token is invalid")
        suite.expect(!HomebrewCommandBuilder.isValidToken("bad token"), "spaced Homebrew token is invalid")

        let brewPath = "/opt/homebrew/bin/brew"
        let cask = HomebrewPackage(kind: .cask, name: "sample-tool",
                                   displayName: "Sample Tool", desc: nil,
                                   installedVersion: nil, stableVersion: nil, homepage: nil)
        suite.expect(HomebrewCommandBuilder.search(brewPath: brewPath, kind: .formula, query: "jq").arguments
               == ["search", "--formula", "jq"],
               "formula search command uses separated arguments")
        suite.expect(HomebrewCommandBuilder.outdated(brewPath: brewPath).arguments
               == ["outdated", "--json=v2"],
               "Homebrew outdated command uses read-only JSON v2 output")
        suite.expect(HomebrewCommandBuilder.update(brewPath: brewPath).arguments
               == ["update"],
               "Homebrew update command refreshes Homebrew metadata")
        suite.expect(HomebrewCommandBuilder.install(brewPath: brewPath, package: cask).arguments
               == ["install", "--cask", "sample-tool"],
               "cask install command uses --cask")
        suite.expect(HomebrewCommandBuilder.uninstall(brewPath: brewPath, package: cask).arguments
               == ["uninstall", "--cask", "sample-tool"],
               "cask uninstall command uses --cask")
        suite.expect(HomebrewCommandBuilder.upgrade(brewPath: brewPath, package: cask).arguments
               == ["upgrade", "--cask", "sample-tool"],
               "cask upgrade command uses --cask")
        let formula = HomebrewPackage(kind: .formula, name: "jq",
                                      displayName: "jq", desc: nil,
                                      installedVersion: "1.8.1", stableVersion: nil, homepage: nil)
        suite.expect(HomebrewCommandBuilder.upgrade(brewPath: brewPath, package: formula).arguments
               == ["upgrade", "jq"],
               "formula upgrade command uses separated arguments")
        suite.expect(HomebrewCommandBuilder.upgradeAll(brewPath: brewPath).arguments
               == ["upgrade"],
               "Homebrew update all command upgrades all outdated packages")

        // brew exits non-zero when it could not do all of a run, not only when it
        // did none of it, so the installed and outdated lists have to be re-read
        // after a failed operation too. Read from the source: the refresh happens
        // inside a completion closure that no unit test can drive.
        let managerSource = homebrewManagerSource
        suite.expect(!managerSource.isEmpty, "HomebrewManager source is readable for the refresh checks")
        let managerCode = managerSource
            .split(separator: "\n", omittingEmptySubsequences: false)
            .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }
            .joined(separator: "\n")
        let refreshCalls = managerCode
            .components(separatedBy: "self.refreshInstalled(clearingError: false)").count - 1
        suite.expect(refreshCalls == 3,
               "the cancelled, needs-terminal and failed operation paths all re-read, "
               + "found \(refreshCalls)")
        let guardedBannerClears = managerCode
            .components(separatedBy: "if clearingError { errorMessage = nil }").count - 1
        suite.expect(guardedBannerClears == 2,
               "both banner clears in refreshInstalled are behind its parameter, so the reason "
               + "a failed operation gave survives the refresh that follows it, found "
               + "\(guardedBannerClears)")
        suite.expect(HomebrewOperation.Action.install.runningSystemImage == "arrow.down.circle.fill",
               "Homebrew install status uses a download icon")
        suite.expect(HomebrewOperation.Action.uninstall.runningSystemImage == "trash.circle.fill",
               "Homebrew uninstall status uses a trash icon")
        suite.expect(HomebrewOperation.Action.upgrade.runningSystemImage == "arrow.up.circle.fill",
               "Homebrew package update status uses an update icon")
        suite.expect(HomebrewOperation.Action.updateHomebrew.runningSystemImage == "arrow.triangle.2.circlepath",
               "Homebrew metadata refresh status uses a refresh icon")
        suite.expect(HomebrewOperation.Action.uninstall.clearsSelectionOnSuccess,
               "Homebrew uninstall clears details for the package that left the installed list")
        suite.expect(!HomebrewOperation.Action.install.clearsSelectionOnSuccess
                && !HomebrewOperation.Action.upgrade.clearsSelectionOnSuccess,
               "Homebrew install and upgrade preserve package details after success")
        suite.expect(HomebrewCommandBuilder.needsTerminalFallback(output: "sudo: a terminal is required to read the password"),
               "sudo terminal error triggers Homebrew terminal fallback")
        suite.expect(HomebrewCommandBuilder.installerCommand == #"/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)""#,
               "Homebrew installer command matches the official install script entrypoint")
        expectEqual(HomebrewCommandBuilder.shellProfilePath(homeDirectory: "/Users/test", shellPath: "/bin/zsh"),
                    "/Users/test/.zprofile",
                    "Homebrew shell setup uses zprofile for zsh")
        expectEqual(HomebrewCommandBuilder.shellProfilePath(homeDirectory: "/Users/test", shellPath: "/bin/bash"),
                    "/Users/test/.bash_profile",
                    "Homebrew shell setup uses bash_profile for bash")
        expectEqual(HomebrewCommandBuilder.shellProfilePath(homeDirectory: "/Users/test", shellPath: "/opt/homebrew/bin/fish"),
                    "/Users/test/.config/fish/config.fish",
                    "Homebrew shell setup uses the interactive shell config")
        expectEqual(HomebrewCommandBuilder.shellEnvLine(brewPath: brewPath, shellPath: "/bin/zsh"),
                    #"eval "$(/opt/homebrew/bin/brew shellenv)""#,
                    "Homebrew shell setup line uses brew shellenv")
        expectEqual(HomebrewCommandBuilder.shellEnvLine(brewPath: brewPath, shellPath: "/opt/homebrew/bin/fish"),
                    "eval (/opt/homebrew/bin/brew shellenv fish)",
                    "Homebrew shell setup line matches the interactive shell")
        expectEqual(HomebrewAnalytics.url(kind: .formula).absoluteString,
                    "https://formulae.brew.sh/api/analytics/install-on-request/homebrew-core/30d.json",
                    "Homebrew formula popularity uses install-on-request analytics")
        expectEqual(HomebrewAnalytics.url(kind: .cask).absoluteString,
                    "https://formulae.brew.sh/api/analytics/cask-install/homebrew-cask/30d.json",
                    "Homebrew cask popularity uses cask install analytics")
        do {
            let originalLocale = MetricFormat.locale
            defer { MetricFormat.locale = originalLocale }
            // Run independently of both the Mac's region and other suites.
            for (region, thousands, millions) in [
                ("en_US_POSIX", "1.2K", "1.2M"),
                ("pt_BR", "1,2K", "1,2M"),
            ] {
                MetricFormat.locale = Locale(identifier: region)
                expectEqual(HomebrewAnalytics.compactCount(999), "999",
                            "Homebrew popularity under 1K stays plain in \(region)")
                expectEqual(HomebrewAnalytics.compactCount(1_250), thousands,
                            "Homebrew popularity compacts thousands in \(region)")
                expectEqual(HomebrewAnalytics.compactCount(1_200_000), millions,
                            "Homebrew popularity compacts millions in \(region)")
            }
        }
        let shellSetupCommand = HomebrewCommandBuilder.shellConfigCommand(brewPath: brewPath,
                                                                          homeDirectory: "/Users/test",
                                                                          shellPath: "/bin/zsh")
        suite.expect(shellSetupCommand.hasPrefix("/bin/sh -c ")
                && shellSetupCommand.contains("PROFILE=/Users/test/.zprofile")
                && shellSetupCommand.hasSuffix(#"; eval "$(/opt/homebrew/bin/brew shellenv)"; brew --version"#),
               "Homebrew shell setup command targets the detected profile")
        suite.expect(shellSetupCommand.contains(#"grep -qxF "$LINE""#),
               "Homebrew shell setup command avoids duplicate profile lines")
        let alternateShellSetupCommand = HomebrewCommandBuilder.shellConfigCommand(
            brewPath: brewPath,
            homeDirectory: "/Users/test",
            shellPath: "/opt/homebrew/bin/fish"
        )
        suite.expect(alternateShellSetupCommand.hasPrefix("/bin/sh -c ")
                && alternateShellSetupCommand.contains("/bin/mkdir -p /Users/test/.config/fish")
                && alternateShellSetupCommand.hasSuffix("; eval (/opt/homebrew/bin/brew shellenv fish); brew --version"),
               "Homebrew shell setup creates and activates the interactive shell config")
        suite.expectClose(HomebrewProgressParser.progressFraction(in: "######## 42.5%") ?? -1,
                    0.425,
                    "Homebrew progress parser reads percentage output")
        suite.expect(HomebrewProgressParser.phase(in: "==> Downloading https://example.com/file",
                                            action: .install) == .downloading,
               "Homebrew progress parser detects downloads")
        suite.expect(HomebrewProgressParser.phase(in: "==> Installing Cask sample-tool",
                                            action: .install) == .installing,
               "Homebrew progress parser detects installs")
        suite.expect(HomebrewProgressParser.phase(in: "==> Uninstalling Cask sample-tool",
                                            action: .uninstall) == .uninstalling,
               "Homebrew progress parser detects uninstalls")
        suite.expect(HomebrewProgressParser.phase(in: "==> Upgrading sample-formula",
                                            action: .upgrade) == .upgrading,
               "Homebrew progress parser detects upgrades")
        suite.expect(HomebrewProgressParser.phase(in: "Already up-to-date.",
                                            action: .updateHomebrew) == .refreshing,
               "Homebrew progress parser detects metadata refresh")
        suite.expect(HomebrewProgressParser.activity(in: "\u{001B}[32m==> Moving App 'Sample.app'\u{001B}[0m")
               == "Moving App 'Sample.app'",
               "Homebrew progress parser cleans activity lines")
        suite.expect(HomebrewProgressParser.visibleError(from: "$ brew install x\nError: Cask failed")
               == "Error: Cask failed",
               "Homebrew progress parser hides command lines from visible errors")

        let homebrewJSON = """
        {
          "formulae": [
            {
              "name": "sample-formula",
              "full_name": "sample-formula",
              "desc": "Sample formula",
              "homepage": "https://example.com/sample-formula",
              "versions": { "stable": "1.8.1" },
              "installed": [{ "version": "1.8.1" }]
            },
            {
              "name": "tapped-formula",
              "full_name": "example/tap/tapped-formula",
              "desc": "Formula from a third-party tap",
              "homepage": "https://example.com/tapped-formula",
              "versions": { "stable": "2.0.0" },
              "installed": [{ "version": "1.0.0" }]
            }
          ],
          "casks": [
            {
              "token": "sample-tool",
              "name": ["Sample Tool"],
              "desc": "Sample cask",
              "homepage": "https://example.com/sample-tool",
              "version": "1.108.1",
              "installed": "1.107.0"
            },
            {
              "token": "tapped-tool",
              "full_token": "example/tap/tapped-tool",
              "name": ["Tapped Tool"],
              "desc": "Cask from a third-party tap",
              "homepage": "https://example.com/tapped-tool",
              "version": "2.0.0",
              "installed": "1.0.0"
            }
          ]
        }
        """
        let homebrewPackages = (try? HomebrewParser.parseInfoJSON(Data(homebrewJSON.utf8))) ?? []
        suite.expect(homebrewPackages.count == 4, "Homebrew JSON parser keeps formulae and casks")
        suite.expect(homebrewPackages.first?.kind == .cask,
               "Homebrew JSON parser sorts casks before formulae")
        suite.expect(homebrewPackages.first(where: { $0.name == "sample-formula" })?.installedVersion == "1.8.1",
               "Homebrew parser reads installed formula version")
        let tappedFormula = homebrewPackages.first { $0.name == "example/tap/tapped-formula" }
        suite.expect(tappedFormula?.displayName == "example/tap/tapped-formula",
               "Homebrew parser keeps the canonical name for a formula from a tap")
        suite.expect(homebrewPackages.first(where: { $0.name == "sample-tool" })?.displayName == "Sample Tool",
               "Homebrew parser reads cask display name")
        let tappedCask = homebrewPackages.first { $0.name == "tapped-tool" }
        suite.expect(tappedCask != nil,
               "Homebrew parser identifies a cask from a tap by its short token")
        suite.expect(tappedCask?.displayName == "Tapped Tool",
               "Homebrew parser keeps the human-readable name for a cask from a tap")
        let cleanCommandPackages = (try? HomebrewParser.parseInfoCommandOutput(homebrewJSON)) ?? []
        suite.expect(cleanCommandPackages.count == 4,
               "Homebrew command output parser keeps clean JSON")
        let noisyHomebrewOutput = """
        Warning: Skipping some beta metadata
        {"notice": "not package data"}
        \(homebrewJSON)
        Warning: A newer Homebrew beta changed an optional field
        """
        let noisyCommandPackages = (try? HomebrewParser.parseInfoCommandOutput(noisyHomebrewOutput)) ?? []
        suite.expect(noisyCommandPackages.count == 4,
               "Homebrew command output parser accepts warnings around JSON")
        suite.expect(noisyCommandPackages.first(where: { $0.name == "sample-tool" })?.installedVersion == "1.107.0",
               "Homebrew command output parser keeps package data from noisy output")
        suite.expect((try? HomebrewParser.parseInfoCommandOutput("Warning: no JSON here")) == nil,
               "Homebrew command output parser rejects output without valid JSON")
        let outdatedJSON = """
        {
          "formulae": [
            {
              "name": "fmt",
              "installed_versions": ["12.1.0"],
              "current_version": "12.2.0",
              "pinned": false
            },
            {
              "name": "example/tap/tapped-formula",
              "installed_versions": ["1.0.0"],
              "current_version": "2.0.0",
              "pinned": false
            }
          ],
          "casks": [
            {
              "name": "sample-tool",
              "installed_versions": ["1.107.0"],
              "current_version": "1.108.1",
              "pinned": true
            },
            {
              "name": "tapped-tool",
              "installed_versions": ["1.0.0"],
              "current_version": "2.0.0",
              "pinned": false
            }
          ]
        }
        """
        let outdatedPackages = (try? HomebrewParser.parseOutdatedJSON(Data(outdatedJSON.utf8))) ?? [:]
        suite.expect(outdatedPackages.count == 4,
               "Homebrew outdated parser keeps formulae and casks")
        suite.expect(outdatedPackages["formula:fmt"]?.versionSummary == "12.1.0 -> 12.2.0",
               "Homebrew outdated parser renders installed to current version")
        suite.expect(outdatedPackages["cask:sample-tool"]?.isPinned == true,
               "Homebrew outdated parser reads pinned status")
        suite.expect(tappedFormula.flatMap { outdatedPackages[$0.id] }?.currentVersion == "2.0.0",
               "Homebrew installed and outdated data use the same ID for tapped formulae")
        suite.expect(tappedCask?.id == "cask:tapped-tool",
               "Homebrew installed cask data stays on the short token brew outdated reports")
        suite.expect(tappedCask.flatMap { outdatedPackages[$0.id] }?.currentVersion == "2.0.0",
               "Homebrew installed and outdated data use the same short-token ID for tapped casks")
        let noisyOutdatedOutput = """
        Warning: Homebrew updated metadata
        {"notice": "not outdated data"}
        \(outdatedJSON)
        """
        let noisyOutdatedPackages = (try? HomebrewParser.parseOutdatedCommandOutput(noisyOutdatedOutput)) ?? [:]
        suite.expect(noisyOutdatedPackages["formula:fmt"]?.currentVersion == "12.2.0",
               "Homebrew outdated command output parser accepts warnings around JSON")
        let orderingPackages = [
            HomebrewPackage(kind: .cask, name: "alpha-tool", displayName: "Alpha Tool",
                            desc: nil, installedVersion: "1.0", stableVersion: nil, homepage: nil),
            HomebrewPackage(kind: .cask, name: "beta-tool", displayName: "Beta Tool",
                            desc: nil, installedVersion: "1.0", stableVersion: nil, homepage: nil,
                            update: HomebrewPackageUpdate(kind: .cask, name: "beta-tool",
                                                          installedVersions: ["1.0"],
                                                          currentVersion: "2.0", isPinned: false)),
            HomebrewPackage(kind: .formula, name: "gamma-tool", displayName: "Gamma Tool",
                            desc: nil, installedVersion: "1.0", stableVersion: nil, homepage: nil,
                            update: HomebrewPackageUpdate(kind: .formula, name: "gamma-tool",
                                                          installedVersions: ["1.0"],
                                                          currentVersion: "2.0", isPinned: false)),
            HomebrewPackage(kind: .formula, name: "delta-tool", displayName: "Delta Tool",
                            desc: nil, installedVersion: "1.0", stableVersion: nil, homepage: nil)
        ]
        suite.expect(HomebrewPackageOrdering.updatesFirst(orderingPackages).map(\.name)
               == ["beta-tool", "gamma-tool", "alpha-tool", "delta-tool"],
               "Homebrew installed packages keep all pending updates first without reordering either group")
        let dependencyJSON = """
        {
          "formulae": [
            { "name": "app-a", "full_name": "app-a",
              "installed": [{ "version": "1", "installed_on_request": true,
                              "runtime_dependencies": [{ "full_name": "shared-lib" }, { "full_name": "deep-lib" }] }] },
            { "name": "app-b", "full_name": "example/tap/app-b",
              "installed": [{ "version": "1", "installed_on_request": true,
                              "runtime_dependencies": [{ "full_name": "shared-lib" }, { "full_name": "example/tap/tap-lib" }] }] },
            { "name": "shared-lib", "full_name": "shared-lib",
              "installed": [{ "version": "2", "installed_on_request": false,
                              "runtime_dependencies": [{ "full_name": "deep-lib" }] }] },
            { "name": "deep-lib", "full_name": "deep-lib",
              "installed": [{ "version": "3", "installed_on_request": false, "runtime_dependencies": [] }] },
            { "name": "tap-lib", "full_name": "example/tap/tap-lib",
              "installed": [{ "version": "4", "installed_on_request": false, "runtime_dependencies": [] }] },
            { "name": "cask-lib", "full_name": "cask-lib",
              "installed": [{ "version": "5", "installed_on_request": false, "runtime_dependencies": [] }] },
            { "name": "orphan-lib", "full_name": "orphan-lib",
              "installed": [{ "version": "6", "installed_on_request": false, "runtime_dependencies": [] }] }
          ],
          "casks": [
            { "token": "cask-app", "name": ["Cask App"], "installed": "1",
              "depends_on": { "formula": ["cask-lib"] } }
          ]
        }
        """
        let dependencyPackages = (try? HomebrewParser.parseInfoJSON(Data(dependencyJSON.utf8))) ?? []
        let folded = HomebrewDependencyGraph.fold(dependencyPackages, installed: dependencyPackages)
        suite.expect(folded.rows.map(\.name) == ["cask-app", "app-a", "example/tap/app-b"]
                     && folded.orphans.map(\.name) == ["orphan-lib"],
                     "Homebrew keeps requested packages as rows and lists a dependency nothing needs as an orphan, found \(folded.rows.map(\.name)) and \(folded.orphans.map(\.name))")
        suite.expect(folded.dependencies["formula:app-a"]?.map(\.name) == ["deep-lib", "shared-lib"],
                     "Homebrew lists direct and transitive dependencies under a requested formula")
        suite.expect(folded.dependencies["formula:example/tap/app-b"]?.map(\.name)
                     == ["deep-lib", "example/tap/tap-lib", "shared-lib"],
                     "Homebrew lists a shared dependency under each parent and resolves tapped names")
        suite.expect(folded.dependencies["cask:cask-app"]?.map(\.name) == ["cask-lib"],
                     "Homebrew lists a cask's formula dependencies under the cask")
        let withUpdate = HomebrewPackageOrdering.updatesFirst(dependencyPackages.map { package in
            var package = package
            if package.name == "shared-lib" {
                package.update = HomebrewPackageUpdate(kind: .formula, name: "shared-lib",
                                                       installedVersions: ["2"], currentVersion: "3", isPinned: false)
            }
            return package
        })
        let updateFolded = HomebrewDependencyGraph.fold(withUpdate, installed: withUpdate)
        suite.expect(updateFolded.rows.map(\.name) == ["shared-lib", "cask-app", "app-a", "example/tap/app-b"]
                     && updateFolded.dependencies["formula:app-a"]?.map(\.name) == ["deep-lib", "shared-lib"],
                     "Homebrew keeps a reached dependency with an update as its own first row and under its parent, found \(updateFolded.rows.map(\.name))")
        let orphanUpdate = HomebrewPackageOrdering.updatesFirst(dependencyPackages.map { package in
            var package = package
            if package.name == "orphan-lib" {
                package.update = HomebrewPackageUpdate(kind: .formula, name: "orphan-lib",
                                                       installedVersions: ["6"], currentVersion: "7", isPinned: false)
            }
            return package
        })
        let orphanUpdateFolded = HomebrewDependencyGraph.fold(orphanUpdate, installed: orphanUpdate)
        suite.expect(orphanUpdateFolded.rows.first?.name == "orphan-lib" && orphanUpdateFolded.orphans.isEmpty,
                     "Homebrew keeps an orphan with an update as the first row, found \(orphanUpdateFolded.rows.map(\.name))")
        let formulaOnly = dependencyPackages.filter { $0.kind == .formula }
        let formulaOnlyFolded = HomebrewDependencyGraph.fold(formulaOnly, installed: dependencyPackages)
        suite.expect(formulaOnlyFolded.rows.map(\.name).contains("cask-lib")
                     && formulaOnlyFolded.orphans.map(\.name) == ["orphan-lib"],
                     "Homebrew shows a cask's dependency as a row, not an orphan, when the filter hides the cask")
        let oldBrewPackages = (try? HomebrewParser.parseInfoJSON(Data(dependencyJSON
            .replacingOccurrences(of: "\"installed_on_request\": true,", with: "")
            .replacingOccurrences(of: "\"installed_on_request\": false,", with: "").utf8))) ?? []
        let oldBrewFolded = HomebrewDependencyGraph.fold(oldBrewPackages, installed: oldBrewPackages)
        suite.expect(oldBrewFolded.rows.count == 8 && oldBrewFolded.dependencies.isEmpty && oldBrewFolded.orphans.isEmpty,
                     "Homebrew keeps the flat list when brew does not report installed_on_request, found \(oldBrewFolded.rows.count)")
        let searchPackages = HomebrewParser.parseSearchOutput("sample-formula\nbad token\nsample-filter\nsample-tool\n",
                                                              kind: .formula,
                                                              installed: homebrewPackages)
        suite.expect(searchPackages.map(\.name) == ["sample-formula", "sample-filter", "sample-tool"],
               "Homebrew search parser keeps valid one-token results")
        let analyticsJSON = """
        {
          "category": "formula_install_on_request",
          "formulae": {
            "sample-formula": [
              { "formula": "sample-formula", "count": "21,557" },
              { "formula": "sample-formula --HEAD", "count": "30" }
            ],
            "sample-filter": [
              { "formula": "sample-filter", "count": "42,001" }
            ]
          }
        }
        """
        let popularity = (try? HomebrewAnalytics.parse(Data(analyticsJSON.utf8), kind: .formula)) ?? [:]
        suite.expect(popularity["sample-formula"]?.count == 21_557,
               "Homebrew analytics parser prefers the exact formula count")
        suite.expect(popularity["sample-filter"]?.rank == 1,
               "Homebrew analytics parser ranks by count")
        let rankedPackages = HomebrewAnalytics.enrichAndSort(searchPackages, popularity: popularity)
        suite.expect(rankedPackages.map(\.name) == ["sample-filter", "sample-formula", "sample-tool"],
               "Homebrew search results sort by popularity first")
        suite.expect(rankedPackages.first?.popularity?.compactCount == "42K",
               "Homebrew search results keep compact popularity")

        // MARK: Repository-wide source contracts

        // Reading a file is not a drawing step. The watermark logo was being
        // decoded inside the preview's body, so every frame of an opacity
        // drag re-read it from disk; it is loaded once per chosen file now,
        // which is what a task is for.
        let uiPrefix = "Sources/Vorssaint/UI/"
        let allUIFiles = repository.swiftPaths.filter { $0.hasPrefix(uiPrefix) }
        var decodingInBody: [String] = []
        for path in allUIFiles {
            let lines = repository.lines(at: path)
            for (index, line) in lines.enumerated() {
                let reads = line.contains("NSImage(contentsOfFile:")
                    || line.contains("Data(contentsOf:")
                guard reads else { continue }
                let around = lines[max(0, index - 6)...min(lines.count - 1, index + 2)]
                if !around.contains(where: { $0.contains(".task(") || $0.contains("func ")
                                             || $0.contains("Task {") }) {
                    decodingInBody.append("\(path):\(index + 1)")
                }
            }
        }
        suite.expect(decodingInBody.isEmpty,
               "a view reads a file once, never while drawing (\(decodingInBody.joined(separator: ", ")))")

        // An unpinned borderless Menu claims the free width of its row on
        // macOS 15 and starves whatever shares that row (issue #569), so the
        // rule is checked for every borderless menu in the app rather than for
        // the one this fix touches. Kill Process is the one deliberate
        // exception: its row controls take a shared minimum width so the Kill
        // button and the menu beside it line up down the list.
        let borderlessMenuException = "KillProcess/KillProcessView"
        var unpinnedBorderlessMenus: [String] = []
        let uiFiles = allUIFiles.filter { !$0.contains(" 2") }
        for path in uiFiles where !path.contains(borderlessMenuException) {
            let file = String(path.dropFirst(uiPrefix.count))
            let lines = repository.lines(at: path)
            for (index, line) in lines.enumerated()
            where line.contains(".menuStyle(.borderlessButton)") {
                // Read to the end of the menu's own modifier chain: the next
                // line that is neither a modifier nor a comment belongs to
                // something else.
                var pinned = false
                var cursor = index + 1
                while cursor < lines.count {
                    let text = lines[cursor].trimmingCharacters(in: .whitespaces)
                    guard text.hasPrefix(".") || text.hasPrefix("//") else { break }
                    if text.hasPrefix(".fixedSize()") { pinned = true; break }
                    cursor += 1
                }
                if !pinned { unpinnedBorderlessMenus.append("\(file):\(index + 1)") }
            }
        }
        suite.expect(!uiFiles.isEmpty && unpinnedBorderlessMenus.isEmpty,
               "every borderless menu keeps its own size, across \(uiFiles.count) "
               + "scanned files: \(unpinnedBorderlessMenus)")

        // `waitUntilAllOperationsAreFinished` has no deadline, and the window
        // walk that used it runs on the main thread while its operations run on
        // the shared dispatch pool. Once unrelated work had taken every worker
        // in that pool, not one operation started and the wait never returned,
        // taking the whole app with it (issue #971).
        let appPrefix = "Sources/Vorssaint/"
        let appSources = repository.swiftPaths.filter {
            $0.hasPrefix(appPrefix) && !$0.contains(" 2")
        }
        var unboundedOperationWaits: [String] = []
        for path in appSources {
            let file = String(path.dropFirst(appPrefix.count))
            for (index, line) in repository.lines(at: path).enumerated()
            where line.contains("waitUntilAllOperationsAreFinished") {
                unboundedOperationWaits.append("\(file):\(index + 1)")
            }
        }
        suite.expect(!appSources.isEmpty && unboundedOperationWaits.isEmpty,
               "no operation queue is waited on without a deadline: \(unboundedOperationWaits)")

        // Asking an application element for its role switches a Chromium app's
        // renderers into full accessibility mode for the rest of the process's
        // life. Both scans report real line numbers, so comments are excluded
        // in the predicate rather than removed from the source.
        func isCommentLine(_ line: String) -> Bool {
            line.trimmingCharacters(in: .whitespaces).hasPrefix("//")
        }
        var applicationRoleReads: [String] = []
        for path in appSources {
            let file = String(path.dropFirst(appPrefix.count))
            let lines = repository.lines(at: path)
            var applicationElements: Set<String> = []
            for line in lines where line.contains("AXUIElementCreateApplication(") {
                let assigned = (line.components(separatedBy: "=").first ?? "")
                    .trimmingCharacters(in: .whitespaces)
                    .components(separatedBy: " ")
                guard assigned.count == 2, assigned[0] == "let" || assigned[0] == "var" else { continue }
                applicationElements.insert(assigned[1])
            }
            for (index, line) in lines.enumerated()
            where line.contains("kAXRoleAttribute")
                && !isCommentLine(line)
                && applicationElements.contains(where: { line.contains("(\($0), ") }) {
                applicationRoleReads.append("\(file):\(index + 1)")
            }
        }
        suite.expect(!appSources.isEmpty && applicationRoleReads.isEmpty,
               "no application element is ever asked for its role: \(applicationRoleReads)")

        // A walk up kAXParent reaches an application element without naming it,
        // so every such walk must stop before asking that parent for its role.
        var unguardedParentWalks: [String] = []
        for path in appSources {
            let file = String(path.dropFirst(appPrefix.count))
            let lines = repository.lines(at: path)
            for (index, line) in lines.enumerated()
            where line.contains("role(of: parent)") && !isCommentLine(line) {
                let guarded = lines[max(0, index - 3)..<index]
                    .contains { $0.contains("isApplicationElement(parent)") && !isCommentLine($0) }
                if !guarded { unguardedParentWalks.append("\(file):\(index + 1)") }
            }
        }
        suite.expect(!appSources.isEmpty && unguardedParentWalks.isEmpty,
               "a walk up the parent chain stops at the application element: \(unguardedParentWalks)")

        // Availability is only ever written by the runtime that gates it, so a
        // new install surface cannot walk around the hardware check.
        var availabilityWriters: Set<String> = []
        for path in repository.swiftPaths {
            let writes = repository.lines(at: path).contains {
                $0.contains(".set(") && $0.contains("availabilityKey")
            }
            if writes { availabilityWriters.insert((path as NSString).lastPathComponent) }
        }
        suite.expect(availabilityWriters == ["FeatureRuntime.swift",
                                       "FeaturePresets.swift",
                                       "Defaults.swift"],
               "feature availability is written only where the hardware gate runs, "
               + "found \(availabilityWriters.sorted())")

        // A saved shelf may only be read through the loader that distinguishes
        // an unreadable or partial store from a valid empty one.
        let rawShelfStoreDecoders = repository.swiftPaths.compactMap { path in
            repository.source(at: path).contains("decode([ShelfPersistedItem]")
                ? (path as NSString).lastPathComponent : nil
        }
        suite.expect(!repository.swiftPaths.isEmpty && rawShelfStoreDecoders.isEmpty,
               "the saved shelf is read only through ShelfPersistenceSupport.load, "
               + "found a bare decode in \(rawShelfStoreDecoders.sorted()) "
               + "across \(repository.swiftPaths.count) scanned files")

        var bareActivationYields: [String] = []
        for path in repository.swiftPaths
        where (path as NSString).lastPathComponent != "ActivationHandoff.swift"
            && repository.source(at: path).contains("yieldActivation") {
            bareActivationYields.append((path as NSString).lastPathComponent)
        }
        suite.expect(!repository.swiftPaths.isEmpty && bareActivationYields.isEmpty,
               "activation is yielded only through ActivationHandoff, "
               + "found a bare yield in \(bareActivationYields.sorted()) "
               + "across \(repository.swiftPaths.count) scanned files")

        // Dropping the last Swift reference does not deregister an event tap;
        // every literal tap creation needs a matching invalidation or removal.
        var tapOwnersWithoutInvalidate: [String] = []
        var tapOwners = 0
        for path in appSources {
            let code = repository.lines(at: path)
                .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }
                .joined(separator: "\n")
            let taps = code.components(separatedBy: "CGEvent.tapCreate").count - 1
            guard taps > 0 else { continue }
            tapOwners += 1
            let invalidations = code.components(separatedBy: "CFMachPortInvalidate").count - 1
                + (code.components(separatedBy: "PointerTapRunLoop.remove(").count - 1)
            if invalidations < taps {
                let file = String(path.dropFirst(appPrefix.count))
                tapOwnersWithoutInvalidate.append("\(file) (\(taps) taps, \(invalidations) invalidated)")
            }
        }
        suite.expect(tapOwners > 0 && tapOwnersWithoutInvalidate.isEmpty,
               "every event tap owner invalidates its port on teardown, across "
               + "\(tapOwners) scanned owners: \(tapOwnersWithoutInvalidate)")

        // MARK: Localization source contracts

        // Visible localization source uses typographic apostrophes rather than
        // typewriter marks.
        let localizationSourcePaths = repository.swiftPaths.filter { path in
            let folder = (path as NSString).deletingLastPathComponent
            let name = (path as NSString).lastPathComponent
            return (folder == "Sources/Vorssaint/Core"
                    || folder == "Sources/Vorssaint/Core/Localizations")
                && (name.hasSuffix("Strings.swift") || name.hasPrefix("Strings+")
                    || name == "Localization.swift")
        }
        var typewriterMarks: [String] = []
        for path in localizationSourcePaths {
            for (index, line) in repository.lines(at: path).enumerated() {
                guard !line.trimmingCharacters(in: .whitespaces).hasPrefix("//") else { continue }
                guard let opening = line.firstIndex(of: "\""),
                      let closing = line.lastIndex(of: "\""), opening < closing else { continue }
                if line[opening..<closing].contains("'") {
                    typewriterMarks.append("\(path):\(index + 1)")
                }
            }
        }
        suite.expect(typewriterMarks.isEmpty,
               "visible text curls its apostrophes (\(typewriterMarks.prefix(6).joined(separator: ", ")))")

        // French double punctuation and guillemets use non-breaking spaces.
        func frenchLines(_ path: String) -> ArraySlice<String> {
            let lines = repository.lines(at: path)
            guard !path.hasSuffix("Strings+French.swift") else { return lines[...] }
            guard let start = lines.firstIndex(where: {
                $0.trimmingCharacters(in: .whitespaces).hasPrefix("static let fr = ")
            }) else { return [][...] }
            let end = lines[(start + 1)...].firstIndex {
                $0.trimmingCharacters(in: .whitespaces).hasPrefix("static let ")
            } ?? lines.endIndex
            return lines[start..<end]
        }
        let frenchSources = repository.swiftPaths.filter { path in
            path == "Sources/Vorssaint/Core/Localizations/Strings+French.swift"
                || ((path as NSString).deletingLastPathComponent == "Sources/Vorssaint/Core"
                    && path.hasSuffix("Strings.swift"))
        }
        var breakingFrench: [String] = []
        for path in frenchSources {
            for line in frenchLines(path) {
                guard !line.trimmingCharacters(in: .whitespaces).hasPrefix("//") else { continue }
                guard let opening = line.firstIndex(of: "\""),
                      let closing = line.lastIndex(of: "\""), opening < closing else { continue }
                let body = String(line[line.index(after: opening)..<closing])
                let breaks = [" ;", " :", " !", " ?", " \u{00BB}", "\u{00AB} "]
                if breaks.contains(where: { body.contains($0) }) {
                    breakingFrench.append((path as NSString).lastPathComponent)
                }
            }
        }
        suite.expect(breakingFrench.isEmpty,
               "French keeps its punctuation on the line it belongs to (\(Set(breakingFrench).sorted().prefix(4).joined(separator: ", ")))")

        let themeSource = repository.source(at: "Sources/Vorssaint/UI/Theme.swift")
        let raisedReads = themeSource
            .components(separatedBy: "accessibilityDisplayShouldIncreaseContrast").count - 1
        suite.expect(raisedReads == 2,
               "both panel outlines answer raised contrast, and nothing else pretends to")

        // Every formatted decimal explicitly chooses its locale. Long calls
        // may put that locale on either of the next two lines.
        var regionlessDecimals: [String] = []
        for path in repository.swiftPaths {
            let lines = repository.lines(at: path)
            for (index, line) in lines.enumerated() {
                let statement = lines[index...min(index + 2, lines.count - 1)].joined()
                guard line.contains("String(format:"), !statement.contains("locale:") else { continue }
                let piece = line.components(separatedBy: "String(format:").dropFirst().first ?? ""
                let format = piece.components(separatedBy: "\"").dropFirst().first ?? ""
                if format.contains("f") && format.contains("%") {
                    regionlessDecimals.append("\(path):\(index + 1)")
                }
            }
        }
        suite.expect(regionlessDecimals.isEmpty,
               "a decimal on screen names its region (\(regionlessDecimals.joined(separator: ", ")))")

        // Purgeable space is queried only for writable volumes.
        let samplerCode = repository.lines(
            at: "Sources/Vorssaint/Services/Metrics/DiskSampler.swift")
            .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }
            .joined(separator: "\n")
        suite.expect(!samplerCode.isEmpty, "the disk sampler reads back for its shape check")
        let bulkKeys = samplerCode.components(separatedBy: "let keys: Set<URLResourceKey>")
            .dropFirst().first?.components(separatedBy: "]").first ?? ""
        suite.expect(!bulkKeys.contains("volumeAvailableCapacityForImportantUsageKey")
                && bulkKeys.contains("volumeIsReadOnlyKey"),
               "the bulk volume fetch asks nothing that only a writable volume can answer")
        suite.expect(samplerCode.contains("guard !isReadOnly,"),
               "purgeable space is read only where there is something to purge")

        // Only localized fields that reach String(format:) need matching
        // placeholders in every language.
        var formatFields: Set<String> = []
        for path in repository.swiftPaths {
            for piece in repository.source(at: path).components(separatedBy: "String(format:").dropFirst() {
                let head = piece.prefix(120)
                guard let comma = head.firstIndex(of: ",") else { continue }
                let expression = head[head.startIndex..<comma]
                guard let dot = expression.lastIndex(of: ".") else { continue }
                let name = expression[expression.index(after: dot)...]
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                if !name.isEmpty, name.allSatisfy({ $0.isLetter || $0.isNumber }) {
                    formatFields.insert(name)
                }
            }
        }
        suite.expect(formatFields.count > 10, "the format fields were found to compare (\(formatFields.count))")
        var mismatched: [String] = []
        for (language, strings) in LocalizationTests.languages where language != .enUS {
            let mine = Mirror(reflecting: strings).children
            let base = Mirror(reflecting: Strings.enUS).children
            for (left, right) in zip(base, mine) {
                guard let label = left.label, formatFields.contains(label),
                      let english = left.value as? String,
                      let other = right.value as? String else { continue }
                if TestFormat.parse(english) == nil
                    || TestFormat.parse(english)?.arguments != TestFormat.parse(other)?.arguments {
                    mismatched.append("\(label)/\(language.rawValue)")
                }
            }
        }
        suite.expect(mismatched.isEmpty,
               "every language fills a format the same way (\(mismatched.prefix(5).joined(separator: ", ")))")

        // Every literal SF Symbol name resolves on the test system.
        var symbolNames: Set<String> = []
        for path in repository.swiftPaths {
            for piece in repository.source(at: path).components(separatedBy: "systemName: \"").dropFirst() {
                guard let end = piece.firstIndex(of: "\"") else { continue }
                let name = String(piece[piece.startIndex..<end])
                if !name.isEmpty, !name.contains("\\") { symbolNames.insert(name) }
            }
        }
        suite.expect(symbolNames.count > 80, "the symbol names were found (\(symbolNames.count))")
        var missingSymbols: [String] = []
        for name in symbolNames.sorted()
        where NSImage(systemSymbolName: name, accessibilityDescription: nil) == nil {
            missingSymbols.append(name)
        }
        suite.expect(missingSymbols.isEmpty,
               "every symbol the app draws exists (\(missingSymbols.joined(separator: ", ")))")

        // Every literal resource name requested by Swift is shipped or staged
        // by the build.
        var namedResources: Set<String> = []
        for path in repository.swiftPaths {
            let text = repository.source(at: path)
            for marker in ["url(forResource: \"", "path(forResource: \"", "NSImage(named: \""] {
                for piece in text.components(separatedBy: marker).dropFirst() {
                    guard let end = piece.firstIndex(of: "\"") else { continue }
                    let name = String(piece[piece.startIndex..<end])
                    if !name.isEmpty, !name.contains("\\") { namedResources.insert(name) }
                }
            }
        }
        suite.expect(namedResources.count >= 5, "the named resources were found (\(namedResources.count))")
        var shippedNames: Set<String> = []
        for path in (try? FileManager.default.subpathsOfDirectory(atPath: "Resources")) ?? [] {
            let file = (path as NSString).lastPathComponent
            shippedNames.insert((file as NSString).deletingPathExtension)
            shippedNames.insert(file)
        }
        suite.expect(!buildScript.isEmpty, "the build script reads back for its resource names")
        for word in buildScript.components(separatedBy: CharacterSet(charactersIn: " \n\t\"'()")) {
            let file = (word as NSString).lastPathComponent
            guard !file.isEmpty else { continue }
            shippedNames.insert((file as NSString).deletingPathExtension)
            shippedNames.insert(file)
        }
        shippedNames.insert("CHANGELOG")
        let absentResources = namedResources.filter { !shippedNames.contains($0) }.sorted()
        suite.expect(absentResources.isEmpty,
               "every file the app asks for by name is in the bundle (\(absentResources.joined(separator: ", ")))")

        // Embedded Finder scripts are compiled only when they run, so verify
        // that every multiline tell/repeat block balances here.
        var unbalancedScripts: [String] = []
        for path in repository.swiftPaths {
            let text = repository.source(at: path)
            for chunk in text.components(separatedBy: "\"\"\"").enumerated()
            where chunk.offset % 2 == 1 && chunk.element.contains("tell application") {
                let body = chunk.element.components(separatedBy: "\n")
                    .map { $0.trimmingCharacters(in: .whitespaces) }
                func opens(_ word: String, closing: String, inline: (String) -> Bool) -> Bool {
                    let started = body.filter { $0.hasPrefix(word + " ") && !inline($0) }.count
                    let ended = body.filter { $0 == closing }.count
                    return started != ended
                }
                let name = (path as NSString).lastPathComponent
                if opens("tell", closing: "end tell", inline: { $0.contains(" to ") }) {
                    unbalancedScripts.append("\(name):tell")
                }
                if opens("repeat", closing: "end repeat", inline: { _ in false }) {
                    unbalancedScripts.append("\(name):repeat")
                }
            }
        }
        suite.expect(unbalancedScripts.isEmpty,
               "every embedded script closes what it opens (\(unbalancedScripts.joined(separator: ", ")))")

        // Absolute command-line tool paths embedded in Swift must exist.
        var toolPaths: Set<String> = []
        for path in repository.swiftPaths {
            for piece in repository.source(at: path).components(separatedBy: "\"/").dropFirst() {
                guard let end = piece.firstIndex(of: "\"") else { continue }
                let candidate = "/" + piece[piece.startIndex..<end]
                guard candidate.hasPrefix("/bin/") || candidate.hasPrefix("/usr/bin/")
                        || candidate.hasPrefix("/usr/sbin/") else { continue }
                guard !candidate.contains(" "), !candidate.contains("\\") else { continue }
                toolPaths.insert(candidate)
            }
        }
        suite.expect(toolPaths.count >= 15, "the system tools were found (\(toolPaths.count))")
        let missingTools = toolPaths.sorted().filter {
            !FileManager.default.fileExists(atPath: $0)
        }
        suite.expect(missingTools.isEmpty,
               "every system tool the app runs is where it expects (\(missingTools.joined(separator: ", ")))")

        // User-file stores delete only paths whose ownership is established in
        // the local scope immediately before removal.
        var ungardedDeletes: [String] = []
        let ownershipGuards = ["isShelfOwnedFile", "discardablePaths", "ownedPayloadURLs",
                               "isRegularFile", "tempDir", "legacyDir", "root", "uuidString",
                               "storeRoot", "contentsOfDirectory"]
        for path in ["Sources/Vorssaint/Services/Shelf/ShelfService.swift",
                     "Sources/Vorssaint/Services/QuickTools/RecentCaptureService.swift",
                     "Sources/Vorssaint/Services/QuickTools/RecentCaptureStore.swift"] {
            let lines = repository.lines(at: path)
            suite.expect(!lines.isEmpty, "the store source reads back for its deletion check")
            for (index, line) in lines.enumerated() where line.contains("removeItem(at:") {
                let scope = lines[max(0, index - 10)...index].joined(separator: "\n")
                if !ownershipGuards.contains(where: scope.contains) {
                    ungardedDeletes.append("\((path as NSString).lastPathComponent):\(index + 1)")
                }
            }
        }
        suite.expect(ungardedDeletes.isEmpty,
               "a file is deleted only after the app checks it owns it (\(ungardedDeletes.joined(separator: ", ")))")

        // MARK: Result

        // MARK: Every temp dir build.sh stages in is swept when the script ends
        // `mktemp -d` lands outside the repo, so a dir the script does not
        // remove survives the run — a successful one as much as a failed one.
        // The sweep is therefore a trap, and a staging dir added later leaks on
        // every build until it is named in cleanup(). The names are read out of
        // the script so the two cannot drift apart.
        // The trap has to be installed before the first dir exists: a failure
        // between `mktemp -d` and a later `trap` leaks exactly as before.
        let sweepInstalled = buildScript.range(of: "trap cleanup EXIT")?.lowerBound
        let firstStaged = buildScript.range(of: "mktemp -d")?.lowerBound
        suite.expect(sweepInstalled != nil && firstStaged != nil && sweepInstalled! < firstStaged!,
               "build.sh installs the temp dir sweep before it stages the first dir")
        // zsh runs the EXIT trap on HUP but not on INT or TERM, so the signals
        // have to reach it through `exit` or Ctrl-C leaks the staged bundle.
        let signalsRouted = buildScript.range(of: "trap 'exit 1' INT TERM HUP")?.lowerBound
        suite.expect(signalsRouted != nil && firstStaged != nil && signalsRouted! < firstStaged!,
               "build.sh routes interrupts through the sweep before it stages the first dir")
        let cleanupBody = buildScript.components(separatedBy: "cleanup() {")
            .dropFirst().first?.components(separatedBy: "\n}").first ?? ""
        let stagedTempDirs = buildScript.components(separatedBy: "=\"$(mktemp -d)\"")
            .dropLast()
            .compactMap {
                $0.split(whereSeparator: { $0.isNewline || $0 == " " || $0 == "\t" })
                    .last.map(String.init)
            }
        suite.expect(!stagedTempDirs.isEmpty, "the staged temp dirs read back out of build.sh")
        // A dir reached through a path suffix — `X="$(mktemp -d)/name"` — puts
        // the parent in no variable at all, which is how the bundle staging dir
        // leaked. Every call has to be captured whole to be sweepable.
        suite.expect(buildScript.components(separatedBy: "mktemp -d").count - 1 == stagedTempDirs.count,
               "every mktemp -d in build.sh is a whole capture — no path suffix, no other spelling")
        for variable in Set(stagedTempDirs) {
            suite.expect(cleanupBody.contains("\"$\(variable)\""),
                   "temp dir \(variable) is swept by build.sh cleanup()")
            // The sweep runs under `set -u` before the dir is staged: an entry
            // whose variable is not empty first aborts cleanup() at that line,
            // leaving everything listed below it unswept and the exit status
            // untouched. The empty assignment is the third line of the pattern.
            // The leading newline keeps ICON_TMP off STAGE_ICON_TMP.
            let initialized = buildScript.range(of: "\n\(variable)=\"\"")?.lowerBound
            suite.expect(initialized != nil && sweepInstalled != nil && initialized! < sweepInstalled!,
                   "temp dir \(variable) is empty before the sweep is installed")
        }

        // MARK: An identity-less build that installs creates its stable signing identity
        // An ad-hoc signature changes hash on every build, so macOS orphans
        // Accessibility and Screen Recording grants on each rebuild while
        // System Settings keeps showing them as granted. build.sh therefore
        // routes identity-less installs through Tools/setup-signing.sh before
        // signing. The needle is the invocation at the start of a command
        // line: the ad-hoc fallback's advice string also names the script, and
        // must not satisfy this check.
        let runsSigningSetup = buildScript.components(separatedBy: "\n").contains {
            $0.range(of: #"^\s*(if\s+!?\s*)?\./Tools/setup-signing\.sh"#,
                     options: .regularExpression) != nil
        }
        suite.expect(runsSigningSetup,
               "an identity-less build that installs invokes Tools/setup-signing.sh itself")
        // The guard is on the install, not on the variant: a plain --install
        // replaces the bundle under the released id, so it strands the grants
        // on the app people actually use. CI never passes --install.
        let buildScriptCode = buildScript.components(separatedBy: "\n")
            .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("#") }
        suite.expect(buildScriptCode.contains { $0.contains("(( DEV || INSTALL ))")
                                            && $0.contains("developer_id_identity") },
               "the signing setup guard covers every install, not only the Developer variant")
        // The setup script must run against the stock /usr/bin/openssl, which
        // is LibreSSL: it rejects OpenSSL 3's -legacy flag outright, and the
        // script once died on exactly that with its stderr discarded. The
        // portable spelling names the PBE algorithms instead of the flag.
        let signingSetup = (try? String(contentsOfFile: "Tools/setup-signing.sh",
                                         encoding: .utf8)) ?? ""
        suite.expect(!signingSetup.isEmpty, "the signing setup script reads back for its shape check")
        let signingSetupCode = signingSetup.components(separatedBy: "\n")
            .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("#") }
            .joined(separator: "\n")
        suite.expect(!signingSetupCode.contains("-legacy"),
               "setup-signing.sh avoids the -legacy flag the stock LibreSSL openssl rejects")

        // MARK: The stable identity is judged by whether codesign can sign with it
        // A find-identity listing names certificates codesign then rejects, and
        // -v excludes every self-signed one, so neither spelling may decide.
        for (script, code, identity) in [("build.sh", buildScriptCode, "$LEGACY_IDENTITY"),
                                         ("Tools/setup-signing.sh", signingSetupCode.components(separatedBy: "\n"),
                                          "$IDENTITY")] {
            suite.expect(!code.contains { $0.contains("find-identity") && $0.contains(identity) },
                   "\(script) never decides the stable identity by a find-identity listing")
            suite.expect(code.contains { $0.contains("cp /bin/echo") }
                    && code.contains { $0.contains("--sign \"\(identity)\" \"$probe\"") },
                   "\(script) asks codesign to sign a throwaway copy of /bin/echo with the stable identity")
        }

        // MARK: Uninstallation paths stay aligned across SelfUninstall and Tools/uninstall.sh
        let selfUninstallSource = repository.source(
            at: "Sources/Vorssaint/Services/SelfUninstall.swift")
        let uninstallScriptSource = (try? String(contentsOfFile: "Tools/uninstall.sh",
                                                encoding: .utf8)) ?? ""
        suite.expect(!selfUninstallSource.isEmpty && !uninstallScriptSource.isEmpty,
               "uninstall sources read back for uninstallation alignment check")
        suite.expect(selfUninstallSource.contains("CleaningModeManager.shared.deactivateForSystemTeardown()"),
               "permission reset removes the cleaning input tap synchronously")
        let queryHabitSupportSource = repository.source(
            at: "Sources/Vorssaint/Services/CommandBar/CommandBarSupport.swift")
        let queryHabitServiceSource = repository.source(
            at: "Sources/Vorssaint/Services/CommandBar/CommandBarService.swift")
        suite.expect(!queryHabitSupportSource.isEmpty
                && !queryHabitServiceSource.isEmpty
                && !queryHabitSupportSource.contains("SecItem")
                && !queryHabitSupportSource.contains("import Security")
                && !selfUninstallSource.contains("removeInstallationKey")
                && !uninstallScriptSource.contains("delete-generic-password")
                && !queryHabitServiceSource.contains("DefaultsKey.commandBarQueryHabits"),
               "query learning and uninstall never access Keychain or persist query habits")
        let requiredSubpaths = ["Library/Application Support", "Library/Caches", "Library/HTTPStorages"]
        for subpath in requiredSubpaths {
            suite.expect(selfUninstallSource.contains(subpath) && uninstallScriptSource.contains(subpath),
                   "both in-app and script uninstall sweep \(subpath)")
        }
        suite.expect(uninstallScriptSource.contains("Library/Preferences/ByHost"),
               "script uninstall sweeps ByHost preferences")
        // Restoring sleep used to be fired and forgotten at both exits. A
        // failure there leaves `pmset disablesleep 1` set system-wide, and
        // removal deletes the flag that launch-time recovery reads before it
        // reads the setting, so nothing repairs it afterwards — a reinstall
        // included.
        let uninstallerSource = repository.source(
            at: "Sources/Vorssaint/Support/Uninstaller.swift")
        suite.expect(!uninstallerSource.isEmpty,
               "uninstaller entry point reads back for the sleep restore check")
        suite.expect(!selfUninstallSource.contains("_ = Sudoers.pmsetDisableSleep")
                && !uninstallerSource.contains("_ = Sudoers.pmsetDisableSleep"),
               "neither uninstall path discards the result of restoring sleep")
        suite.expect(selfUninstallSource.contains("guard detachFromSystem() else")
                && selfUninstallSource.contains("restoreSleepBeforeRemoval() -> Bool")
                && selfUninstallSource.contains("guard FanControlService.restoreAndUnregisterForRemoval() else")
                && selfUninstallSource.contains("adminPromptRecover")
                && selfUninstallSource.contains("verification.status == 0"),
               "in-app uninstall aborts unless fans and normal sleep are restored before removal")
        suite.expect(uninstallScriptSource.contains("SleepDisabled"),
               "script uninstall reads the sleep setting back for itself")
        let brightnessSource = repository.source(
            at: "Sources/Vorssaint/Services/Display/BrightnessService.swift")
        let brightnessTapMethod = brightnessSource
            .components(separatedBy: "    func suspendInputTaps()").dropFirst().first?
            .components(separatedBy: "    private func installFunctionKeyTap").first ?? ""
        let brightnessTapCode = brightnessTapMethod.components(separatedBy: "\n")
            .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }
            .joined(separator: "\n")
        suite.expect(selfUninstallSource.contains("TextSnippetService.shared.suspend()")
                && selfUninstallSource.contains("QuitProtectionService.shared.suspend()")
                && selfUninstallSource.contains("BrightnessService.shared.suspendInputTaps()")
                && selfUninstallSource.contains("BrightnessService.shared.resumeInputTaps()")
                && brightnessTapCode.contains("inputTapsSuspended = true")
                && brightnessTapCode.contains("removeKeyTap()")
                && brightnessTapCode.contains("removeFunctionKeyTap()")
                && !brightnessTapCode.contains("restoreManagedDisplays")
                && !brightnessTapCode.contains("restoreAllGamma"),
               "the permission teardown stops every persistent keyboard tap")
        let quitProtectionSource = repository.source(
            at: "Sources/Vorssaint/Services/QuitProtection/QuitProtectionService.swift")
        suite.expect(quitProtectionSource.contains("func suspend()"),
               "quit protection exposes the teardown the permission reset calls")

        // MARK: Secure input

        suite.expect(SecureInputSupport.holder(isEnabled: false,
                                         read: .noHolder,
                                         runningApp: { _ in nil },
                                         isProcessAlive: { _ in true }) == .off,
               "secure input off with no recorded holder is off")
        var secureInputNameLookups = 0
        let secureInputOffWithPid = SecureInputSupport.holder(
            isEnabled: false,
            read: .holder(4242),
            runningApp: { pid in
                secureInputNameLookups += 1
                return ("SomeBrowser", pid)
            },
            isProcessAlive: { _ in true })
        suite.expect(secureInputOffWithPid == .off,
               "secure input off stays off even with a pid still recorded")
        suite.expect(SecureInputSupport.holder(isEnabled: false,
                                         read: .unavailable,
                                         runningApp: { _ in nil },
                                         isProcessAlive: { _ in true }) == .off,
               "secure input off stays off when the session cannot be read")
        suite.expect(secureInputNameLookups == 0,
               "the name lookup is skipped when secure input is off")

        suite.expect(SecureInputSupport.holder(isEnabled: true,
                                         read: .holder(999),
                                         runningApp: { pid in
                                             pid == 999 ? ("SomeBrowser", 4242) : nil
                                         },
                                         isProcessAlive: { _ in true })
                   == .app(name: "SomeBrowser", pid: 4242),
               "a helper pid is attributed to the app responsible for it")
        suite.expect(SecureInputSupport.holder(isEnabled: true,
                                         read: .holder(4242),
                                         runningApp: { _ in nil },
                                         isProcessAlive: { _ in true }) == .unknown,
               "a running holder that is no regular app is never sent to log out")
        suite.expect(SecureInputSupport.holder(isEnabled: true,
                                         read: .holder(4242),
                                         runningApp: { _ in nil },
                                         isProcessAlive: { _ in false }) == .unattributed,
               "a holder that has exited is what a new login session clears")
        suite.expect(SecureInputSupport.holder(isEnabled: true,
                                         read: .noHolder,
                                         runningApp: { _ in nil },
                                         isProcessAlive: { _ in true }) == .unattributed,
               "secure input on with no recorded holder is unattributed")
        suite.expect(SecureInputSupport.holder(isEnabled: true,
                                         read: .holder(0),
                                         runningApp: { pid in ("SomeBrowser", pid) },
                                         isProcessAlive: { _ in true }) == .unattributed,
               "a zero pid is not an attribution")
        suite.expect(SecureInputSupport.holder(isEnabled: true,
                                         read: .holder(4242),
                                         runningApp: { pid in ("", pid) },
                                         isProcessAlive: { _ in false }) == .unattributed,
               "an empty app name is not an attribution")

        var secureInputUnavailableLookups = 0
        var secureInputUnavailableLivenessChecks = 0
        let secureInputUnavailable = SecureInputSupport.holder(
            isEnabled: true,
            read: .unavailable,
            runningApp: { pid in
                secureInputUnavailableLookups += 1
                return ("SomeBrowser", pid)
            },
            isProcessAlive: { _ in
                secureInputUnavailableLivenessChecks += 1
                return true
            })
        suite.expect(secureInputUnavailable == .unknown,
               "a session that cannot be read reports an unknown holder")
        suite.expect(secureInputUnavailableLookups == 0 && secureInputUnavailableLivenessChecks == 0,
               "a session that cannot be read costs no name lookup and no liveness check")

        suite.expect(!SecureInputSupport.shouldPoll(observingSurfaceCount: 0, windowIsOpen: true),
               "secure input keeps no timer without a visible surface")
        suite.expect(SecureInputSupport.shouldPoll(observingSurfaceCount: 1, windowIsOpen: true)
                   && SecureInputSupport.shouldPoll(observingSurfaceCount: 3, windowIsOpen: true),
               "a visible surface polls secure input while the window is open")
        suite.expect(SecureInputSupport.shouldPoll(observingSurfaceCount: 1, windowIsOpen: true)
                   == SecureInputSupport.shouldPoll(observingSurfaceCount: 2, windowIsOpen: true),
               "repeating a demand does not change whether secure input polls")
        suite.expect(!SecureInputSupport.shouldPoll(observingSurfaceCount: 1, windowIsOpen: false),
               "a demand left over from before the window closed does not poll on its own")
        suite.expect(!SecureInputSupport.shouldPoll(observingSurfaceCount: 0, windowIsOpen: false),
               "neither gate alone is enough")

    }
}
