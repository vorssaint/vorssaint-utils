// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

enum HomebrewTests {
    static func run(expect: (Bool, String) -> Void) {
        func expectEqual(_ actual: String, _ expected: String, _ label: String) {
            expect(actual == expected, "\(label): got \"\(actual)\", expected \"\(expected)\"")
        }
        func expectClose(_ actual: Double, _ expected: Double, _ label: String, tol: Double = 0.0001) {
            expect(!(abs(actual - expected) > tol), "\(label): got \(actual), expected \(expected)")
        }

        // MARK: Homebrew command building and parsing

        let homebrewManagerSource = (try? String(
            contentsOfFile: "Sources/Vorssaint/Services/Homebrew/HomebrewManager.swift",
            encoding: .utf8)) ?? ""
        let homebrewRunStreaming = homebrewManagerSource.components(separatedBy: "func runStreaming(")
            .dropFirst().first?.components(separatedBy: "private func appendLog").first ?? ""
        expect(homebrewRunStreaming.contains("brewSilenceTimeout")
                && !homebrewRunStreaming.contains("waitUntilExit"),
               "Homebrew operations wait on a bounded semaphore, not waitUntilExit")

        expect(HomebrewPackageKind.allCases == [.cask, .formula],
               "Homebrew package kinds keep casks before formulae")
        expect(HomebrewCommandBuilder.isValidToken("jq"), "simple Homebrew token is valid")
        expect(HomebrewCommandBuilder.isValidToken("python@3.14"), "versioned formula token is valid")
        expect(HomebrewCommandBuilder.isValidToken("visual-studio-code"), "cask token is valid")
        expect(HomebrewCommandBuilder.isValidToken("homebrew/cask-fonts/font-iosevka"), "tapped token is valid")
        expect(!HomebrewCommandBuilder.isValidToken(""), "empty Homebrew token is invalid")
        expect(HomebrewCommandBuilder.untrustedTapName(fromOutput:
            "Error: Refusing to load formula foo from untrusted tap someone/sometap.\nRun `brew trust someone/sometap` to trust it.")
            == "someone/sometap",
               "untrusted tap name is extracted from Homebrew's refusal")
        expect(HomebrewCommandBuilder.untrustedTapName(fromOutput: "Error: no such formula") == nil,
               "other Homebrew errors extract no tap")
        expect(HomebrewCommandBuilder.untrustedTapName(fromOutput:
            "from untrusted tap ../evil") == nil,
               "a tap name that fails token validation is rejected")
        let trustCommand = HomebrewCommandBuilder.trustTap(brewPath: "/opt/homebrew/bin/brew", tap: "someone/sometap")
        expect(trustCommand.arguments == ["trust", "--tap", "someone/sometap"],
               "trust command targets the tap explicitly")
        expect(!HomebrewCommandBuilder.isValidToken("-bad"), "leading dash Homebrew token is invalid")
        expect(!HomebrewCommandBuilder.isValidToken("../bad"), "path traversal Homebrew token is invalid")
        expect(!HomebrewCommandBuilder.isValidToken("bad token"), "spaced Homebrew token is invalid")

        let brewPath = "/opt/homebrew/bin/brew"
        let cask = HomebrewPackage(kind: .cask, name: "sample-tool",
                                   displayName: "Sample Tool", desc: nil,
                                   installedVersion: nil, stableVersion: nil, homepage: nil)
        expect(HomebrewCommandBuilder.search(brewPath: brewPath, kind: .formula, query: "jq").arguments
               == ["search", "--formula", "jq"],
               "formula search command uses separated arguments")
        expect(HomebrewCommandBuilder.outdated(brewPath: brewPath).arguments
               == ["outdated", "--json=v2"],
               "Homebrew outdated command uses read-only JSON v2 output")
        expect(HomebrewCommandBuilder.update(brewPath: brewPath).arguments
               == ["update"],
               "Homebrew update command refreshes Homebrew metadata")
        expect(HomebrewCommandBuilder.install(brewPath: brewPath, package: cask).arguments
               == ["install", "--cask", "sample-tool"],
               "cask install command uses --cask")
        expect(HomebrewCommandBuilder.uninstall(brewPath: brewPath, package: cask).arguments
               == ["uninstall", "--cask", "sample-tool"],
               "cask uninstall command uses --cask")
        expect(HomebrewCommandBuilder.upgrade(brewPath: brewPath, package: cask).arguments
               == ["upgrade", "--cask", "sample-tool"],
               "cask upgrade command uses --cask")
        let formula = HomebrewPackage(kind: .formula, name: "jq",
                                      displayName: "jq", desc: nil,
                                      installedVersion: "1.8.1", stableVersion: nil, homepage: nil)
        expect(HomebrewCommandBuilder.upgrade(brewPath: brewPath, package: formula).arguments
               == ["upgrade", "jq"],
               "formula upgrade command uses separated arguments")
        expect(HomebrewCommandBuilder.upgradeAll(brewPath: brewPath).arguments
               == ["upgrade"],
               "Homebrew update all command upgrades all outdated packages")

        // brew exits non-zero when it could not do all of a run, not only when it
        // did none of it, so the installed and outdated lists have to be re-read
        // after a failed operation too. Read from the source: the refresh happens
        // inside a completion closure that no unit test can drive.
        let managerSource = (try? String(
            contentsOfFile: "Sources/Vorssaint/Services/Homebrew/HomebrewManager.swift",
            encoding: .utf8)) ?? ""
        expect(!managerSource.isEmpty, "HomebrewManager source is readable for the refresh checks")
        let managerCode = managerSource
            .split(separator: "\n", omittingEmptySubsequences: false)
            .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }
            .joined(separator: "\n")
        let refreshCalls = managerCode
            .components(separatedBy: "self.refreshInstalled(clearingError: false)").count - 1
        expect(refreshCalls == 3,
               "the cancelled, needs-terminal and failed operation paths all re-read, "
               + "found \(refreshCalls)")
        let guardedBannerClears = managerCode
            .components(separatedBy: "if clearingError { errorMessage = nil }").count - 1
        expect(guardedBannerClears == 2,
               "both banner clears in refreshInstalled are behind its parameter, so the reason "
               + "a failed operation gave survives the refresh that follows it, found "
               + "\(guardedBannerClears)")
        expect(HomebrewOperation.Action.install.runningSystemImage == "arrow.down.circle.fill",
               "Homebrew install status uses a download icon")
        expect(HomebrewOperation.Action.uninstall.runningSystemImage == "trash.circle.fill",
               "Homebrew uninstall status uses a trash icon")
        expect(HomebrewOperation.Action.upgrade.runningSystemImage == "arrow.up.circle.fill",
               "Homebrew package update status uses an update icon")
        expect(HomebrewOperation.Action.updateHomebrew.runningSystemImage == "arrow.triangle.2.circlepath",
               "Homebrew metadata refresh status uses a refresh icon")
        expect(HomebrewOperation.Action.uninstall.clearsSelectionOnSuccess,
               "Homebrew uninstall clears details for the package that left the installed list")
        expect(!HomebrewOperation.Action.install.clearsSelectionOnSuccess
                && !HomebrewOperation.Action.upgrade.clearsSelectionOnSuccess,
               "Homebrew install and upgrade preserve package details after success")
        expect(HomebrewCommandBuilder.needsTerminalFallback(output: "sudo: a terminal is required to read the password"),
               "sudo terminal error triggers Homebrew terminal fallback")
        expect(HomebrewCommandBuilder.installerCommand == #"/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)""#,
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
        expectEqual(HomebrewAnalytics.compactCount(999), "999", "Homebrew popularity under 1K stays plain")
        expectEqual(HomebrewAnalytics.compactCount(1_250), "1.2K", "Homebrew popularity compacts thousands")
        expectEqual(HomebrewAnalytics.compactCount(1_200_000), "1.2M", "Homebrew popularity compacts millions")
        let shellSetupCommand = HomebrewCommandBuilder.shellConfigCommand(brewPath: brewPath,
                                                                          homeDirectory: "/Users/test",
                                                                          shellPath: "/bin/zsh")
        expect(shellSetupCommand.hasPrefix("/bin/sh -c ")
                && shellSetupCommand.contains("PROFILE=/Users/test/.zprofile")
                && shellSetupCommand.hasSuffix(#"; eval "$(/opt/homebrew/bin/brew shellenv)"; brew --version"#),
               "Homebrew shell setup command targets the detected profile")
        expect(shellSetupCommand.contains(#"grep -qxF "$LINE""#),
               "Homebrew shell setup command avoids duplicate profile lines")
        let alternateShellSetupCommand = HomebrewCommandBuilder.shellConfigCommand(
            brewPath: brewPath,
            homeDirectory: "/Users/test",
            shellPath: "/opt/homebrew/bin/fish"
        )
        expect(alternateShellSetupCommand.hasPrefix("/bin/sh -c ")
                && alternateShellSetupCommand.contains("/bin/mkdir -p /Users/test/.config/fish")
                && alternateShellSetupCommand.hasSuffix("; eval (/opt/homebrew/bin/brew shellenv fish); brew --version"),
               "Homebrew shell setup creates and activates the interactive shell config")
        expectClose(HomebrewProgressParser.progressFraction(in: "######## 42.5%") ?? -1,
                    0.425,
                    "Homebrew progress parser reads percentage output")
        expect(HomebrewProgressParser.phase(in: "==> Downloading https://example.com/file",
                                            action: .install) == .downloading,
               "Homebrew progress parser detects downloads")
        expect(HomebrewProgressParser.phase(in: "==> Installing Cask sample-tool",
                                            action: .install) == .installing,
               "Homebrew progress parser detects installs")
        expect(HomebrewProgressParser.phase(in: "==> Uninstalling Cask sample-tool",
                                            action: .uninstall) == .uninstalling,
               "Homebrew progress parser detects uninstalls")
        expect(HomebrewProgressParser.phase(in: "==> Upgrading sample-formula",
                                            action: .upgrade) == .upgrading,
               "Homebrew progress parser detects upgrades")
        expect(HomebrewProgressParser.phase(in: "Already up-to-date.",
                                            action: .updateHomebrew) == .refreshing,
               "Homebrew progress parser detects metadata refresh")
        expect(HomebrewProgressParser.activity(in: "\u{001B}[32m==> Moving App 'Sample.app'\u{001B}[0m")
               == "Moving App 'Sample.app'",
               "Homebrew progress parser cleans activity lines")
        expect(HomebrewProgressParser.visibleError(from: "$ brew install x\nError: Cask failed")
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
        expect(homebrewPackages.count == 4, "Homebrew JSON parser keeps formulae and casks")
        expect(homebrewPackages.first?.kind == .cask,
               "Homebrew JSON parser sorts casks before formulae")
        expect(homebrewPackages.first(where: { $0.name == "sample-formula" })?.installedVersion == "1.8.1",
               "Homebrew parser reads installed formula version")
        let tappedFormula = homebrewPackages.first { $0.name == "example/tap/tapped-formula" }
        expect(tappedFormula?.displayName == "example/tap/tapped-formula",
               "Homebrew parser keeps the canonical name for a formula from a tap")
        expect(homebrewPackages.first(where: { $0.name == "sample-tool" })?.displayName == "Sample Tool",
               "Homebrew parser reads cask display name")
        let tappedCask = homebrewPackages.first { $0.name == "tapped-tool" }
        expect(tappedCask != nil,
               "Homebrew parser identifies a cask from a tap by its short token")
        expect(tappedCask?.displayName == "Tapped Tool",
               "Homebrew parser keeps the human-readable name for a cask from a tap")
        let cleanCommandPackages = (try? HomebrewParser.parseInfoCommandOutput(homebrewJSON)) ?? []
        expect(cleanCommandPackages.count == 4,
               "Homebrew command output parser keeps clean JSON")
        let noisyHomebrewOutput = """
        Warning: Skipping some beta metadata
        {"notice": "not package data"}
        \(homebrewJSON)
        Warning: A newer Homebrew beta changed an optional field
        """
        let noisyCommandPackages = (try? HomebrewParser.parseInfoCommandOutput(noisyHomebrewOutput)) ?? []
        expect(noisyCommandPackages.count == 4,
               "Homebrew command output parser accepts warnings around JSON")
        expect(noisyCommandPackages.first(where: { $0.name == "sample-tool" })?.installedVersion == "1.107.0",
               "Homebrew command output parser keeps package data from noisy output")
        expect((try? HomebrewParser.parseInfoCommandOutput("Warning: no JSON here")) == nil,
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
        expect(outdatedPackages.count == 4,
               "Homebrew outdated parser keeps formulae and casks")
        expect(outdatedPackages["formula:fmt"]?.versionSummary == "12.1.0 -> 12.2.0",
               "Homebrew outdated parser renders installed to current version")
        expect(outdatedPackages["cask:sample-tool"]?.isPinned == true,
               "Homebrew outdated parser reads pinned status")
        expect(tappedFormula.flatMap { outdatedPackages[$0.id] }?.currentVersion == "2.0.0",
               "Homebrew installed and outdated data use the same ID for tapped formulae")
        expect(tappedCask?.id == "cask:tapped-tool",
               "Homebrew installed cask data stays on the short token brew outdated reports")
        expect(tappedCask.flatMap { outdatedPackages[$0.id] }?.currentVersion == "2.0.0",
               "Homebrew installed and outdated data use the same short-token ID for tapped casks")
        let noisyOutdatedOutput = """
        Warning: Homebrew updated metadata
        {"notice": "not outdated data"}
        \(outdatedJSON)
        """
        let noisyOutdatedPackages = (try? HomebrewParser.parseOutdatedCommandOutput(noisyOutdatedOutput)) ?? [:]
        expect(noisyOutdatedPackages["formula:fmt"]?.currentVersion == "12.2.0",
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
        expect(HomebrewPackageOrdering.updatesFirst(orderingPackages).map(\.name)
               == ["beta-tool", "gamma-tool", "alpha-tool", "delta-tool"],
               "Homebrew installed packages keep all pending updates first without reordering either group")
        let searchPackages = HomebrewParser.parseSearchOutput("sample-formula\nbad token\nsample-filter\nsample-tool\n",
                                                              kind: .formula,
                                                              installed: homebrewPackages)
        expect(searchPackages.map(\.name) == ["sample-formula", "sample-filter", "sample-tool"],
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
        expect(popularity["sample-formula"]?.count == 21_557,
               "Homebrew analytics parser prefers the exact formula count")
        expect(popularity["sample-filter"]?.rank == 1,
               "Homebrew analytics parser ranks by count")
        let rankedPackages = HomebrewAnalytics.enrichAndSort(searchPackages, popularity: popularity)
        expect(rankedPackages.map(\.name) == ["sample-filter", "sample-formula", "sample-tool"],
               "Homebrew search results sort by popularity first")
        expect(rankedPackages.first?.popularity?.compactCount == "42K",
               "Homebrew search results keep compact popularity")
    }
}
