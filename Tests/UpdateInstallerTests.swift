// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import Foundation

enum UpdateInstallerTests {
    static func runProgress(expect: (Bool, String) -> Void) {
        expect(UpdateInstallerSupport.progressStepAdvanced(from: nil, to: 0.004),
               "the first known download fraction always publishes")
        expect(!UpdateInstallerSupport.progressStepAdvanced(from: 0.011, to: 0.019),
               "fractions inside the same percent stay quiet")
        expect(UpdateInstallerSupport.progressStepAdvanced(from: 0.019, to: 0.021),
               "crossing into the next percent publishes")
        expect(!UpdateInstallerSupport.progressStepAdvanced(from: 0.5, to: 0.5),
               "an unchanged fraction stays quiet")

        let updateCeiling = UpdateInstallerSupport.downloadCeilingBytes
        expect(UpdateInstallerSupport.downloadByteLimit(expectedBytes: 9_638_011) == 9_638_011,
               "a download stops at the size the release advertises")
        expect(UpdateInstallerSupport.downloadByteLimit(expectedBytes: nil) == updateCeiling,
               "an asset with no size still stops at the ceiling")
        expect(UpdateInstallerSupport.downloadByteLimit(expectedBytes: 0) == updateCeiling,
               "a zero size is not a limit of zero")
        expect(UpdateInstallerSupport.downloadByteLimit(expectedBytes: updateCeiling + 1) == updateCeiling,
               "an advertised size beyond the ceiling cannot raise it")

        expect(UpdateInstallerSupport.downloadIsUsable(status: 200,
                                                       receivedBytes: 9_638_011,
                                                       expectedBytes: 9_638_011),
               "a complete asset download is handed to the installer")
        expect(!UpdateInstallerSupport.downloadIsUsable(status: 404,
                                                        receivedBytes: 1_200,
                                                        expectedBytes: 9_638_011),
               "an error page is refused whatever it contains")
        expect(!UpdateInstallerSupport.downloadIsUsable(status: 200,
                                                        receivedBytes: 4_000_000,
                                                        expectedBytes: 9_638_011),
               "a truncated body is refused")
        expect(!UpdateInstallerSupport.downloadIsUsable(status: 200,
                                                        receivedBytes: 0,
                                                        expectedBytes: nil),
               "an empty body is refused even with no advertised size")
        expect(!UpdateInstallerSupport.downloadIsUsable(status: 200,
                                                        receivedBytes: updateCeiling + 1,
                                                        expectedBytes: nil),
               "a body past the ceiling is refused with no advertised size")
        expect(UpdateInstallerSupport.downloadIsUsable(status: 200,
                                                       receivedBytes: 9_638_011,
                                                       expectedBytes: nil),
               "a plausible body with no advertised size is accepted")

        // The showcase loader is a @StateObject, so it can be released without
        // `.onDisappear` running. Its session holds the download delegate, and
        // that delegate's deinit is what deletes the scratch file, so the
        // release path has to invalidate the session too.
        let showcaseSource = (try? String(
            contentsOfFile: "Sources/Vorssaint/Services/Update/UpdateShowcaseMedia.swift",
            encoding: .utf8)) ?? ""
        let showcaseDeinitBody = (showcaseSource.components(separatedBy: "\n    deinit {")
            .dropFirst().first ?? "").components(separatedBy: "\n    }").first ?? ""
        expect(showcaseDeinitBody.contains("session?.invalidateAndCancel()"),
               "a released showcase loader invalidates its session, freeing the delegate and its scratch file")
        expect(!showcaseDeinitBody.contains("finishTasksAndInvalidate"),
               "a released showcase loader cancels its download instead of letting it finish")
    }

    static func run(expect: (Bool, String) -> Void) {
        expect(UpdateInstallerSupport.shouldForceAdminInstall(afterFailureCode: "fail-copy"),
               "a copy failure retries through the admin prompt")
        expect(UpdateInstallerSupport.shouldForceAdminInstall(afterFailureCode: "fail-swap"),
               "a swap failure retries through the admin prompt")
        expect(!UpdateInstallerSupport.shouldForceAdminInstall(afterFailureCode: "fail-verify"),
               "a verification failure is not a permission problem")
        expect(!UpdateInstallerSupport.shouldForceAdminInstall(afterFailureCode: nil),
               "no remembered failure means the normal path")

        let adminSource = AdminShell.appleScriptSource(
            command: #"printf "quoted" \ path"#,
            prompt: #"Approve "update" \ now"#)
        expect(adminSource == #"do shell script "printf \"quoted\" \\ path" with administrator privileges with prompt "Approve \"update\" \\ now""#,
               "administrator source keeps commands and prompts inside AppleScript strings")
        var adminCompileError: NSDictionary?
        expect(NSAppleScript(source: adminSource)?.compileAndReturnError(&adminCompileError) == true,
               "administrator source compiles in process")
        let inProcessScript = AppleScriptRunner.run(
            #"do shell script "/usr/bin/printf admin-probe""#)
        expect(inProcessScript.ok && inProcessScript.output == "admin-probe",
               "in-process AppleScript executes a shell command and returns its output")
        let cancelledScript = AppleScriptRunner.runDetailed("error number -128")
        expect(!cancelledScript.ok && cancelledScript.errorNumber == -128,
               "in-process AppleScript preserves cancellation as a failed request")

        let hiddenLayout = WindowLayoutAction.hiddenActions(from: "leftHalf, restore,bogus")
        expect(hiddenLayout == [.leftHalf, .restore],
               "hidden layout actions parse names and drop unknown ones")
        expect(WindowLayoutAction.hiddenActionsStorageValue([.restore, .leftHalf])
                   == "leftHalf,restore",
               "hidden layout actions serialize sorted for stable storage")
        expect(WindowLayoutAction.hiddenActions(from: "").isEmpty,
               "an empty stored value hides nothing")

        expect(MediaSupport.inputMatchesTool(contentType: .jpeg, inputTypes: [.image]),
               "a JPEG drop fits the image tool")
        expect(!MediaSupport.inputMatchesTool(contentType: .pdf, inputTypes: [.image]),
               "a PDF drop does not fit the image tool")
        expect(!MediaSupport.inputMatchesTool(contentType: nil, inputTypes: [.image]),
               "an unreadable content type is rejected")
        expect(MediaSupport.inputMatchesTool(contentType: .quickTimeMovie,
                                             inputTypes: [.movie, .video]),
               "a movie drop fits the video tools")

        expect(MediaSupport.outputGrew(originalBytes: 9_000, outputBytes: 12_000),
               "a larger output earns the grew caption")
        expect(!MediaSupport.outputGrew(originalBytes: 12_000, outputBytes: 9_000),
               "a smaller output does not")
        expect(!MediaSupport.outputGrew(originalBytes: 0, outputBytes: 12_000),
               "an unknown original size never triggers the grew caption")

        expect(UpdateInstallerSupport.shellSingleQuoted("/Applications/My App.app")
                   == "'/Applications/My App.app'",
               "shell quoting wraps paths with spaces")
        expect(UpdateInstallerSupport.shellSingleQuoted("it's") == "'it'\\''s'",
               "shell quoting survives embedded single quotes")
        expect(UpdateInstallerSupport.installFailureCode(fromMarker: "ok\n") == nil,
               "an ok marker is not a failure")
        expect(UpdateInstallerSupport.installFailureCode(fromMarker: " fail-verify\n") == "fail-verify",
               "a fail marker surfaces its step code")
        expect(UpdateInstallerSupport.installFailureCode(fromMarker: "") == nil,
               "an empty marker is not a failure")
        expect(UpdateInstallerSupport.runsFromImmutableLocation(
                   appPath: "/private/var/folders/ab/xyz/T/AppTranslocation/1F2/d/Vorssaint.app",
                   volumeIsReadOnly: { _ in false }),
               "translocated apps are flagged as not updatable in place")
        expect(UpdateInstallerSupport.runsFromImmutableLocation(appPath: "/Volumes/Vorssaint/Vorssaint.app",
                                                                volumeIsReadOnly: { _ in true }),
               "apps on a read-only volume (the DMG) are flagged as not updatable in place")
        expect(!UpdateInstallerSupport.runsFromImmutableLocation(appPath: "/Volumes/ExternalSSD/Vorssaint.app",
                                                                 volumeIsReadOnly: { _ in false }),
               "apps on a writable external volume stay updatable in place")
        let installerScript = UpdateInstallerSupport.installerScript()
        for step in ["fail-dmg-verify", "fail-tempdir", "fail-mount", "fail-no-app-in-dmg",
                     "fail-copy", "fail-version", "fail-verify", "fail-swap", "note ok"] {
            expect(installerScript.contains(step),
                   "installer script reports the \(step) step")
        }
        expect(installerScript.contains("spctl --status"),
               "installer script skips Gatekeeper assessment when the user disabled it")
        let dmgVerification = installerScript.range(of: "DMG_VERIFY_REQ")
        let dmgMount = installerScript.range(of: "/usr/bin/hdiutil attach")
        expect(dmgVerification != nil && dmgMount != nil
               && dmgVerification!.lowerBound < dmgMount!.lowerBound,
               "installer verifies the release signer before mounting the DMG")
        expect(installerScript.contains("BUNDLE_VERSION=")
               && installerScript.contains("\"$BUNDLE_VERSION\" = \"$EXPECTED_VERSION\""),
               "installer requires the signed app to match the offered release version")
        expect(installerScript.contains("chown -R"),
               "an elevated install hands the bundle back to the user")
        expect(installerScript.contains("update-old.$PID"),
               "the swap backup name is unique per run so a stale root-owned one never blocks it")
        expect(installerScript.contains("launchctl asuser"),
               "installer script relaunches as the user when running as root")
        expect(installerScript.contains("$RESULT.progress") && installerScript.contains("finalize"),
               "installer markers stay in a progress file until the run finishes")
        expect(installerScript.contains("/usr/bin/sudo -n -u \"#$ASUSER\" /bin/sh -c")
                && installerScript.contains("'/bin/echo \"$1\" > \"$2.progress\"' marker \"$1\" \"$RESULT\"")
                && installerScript.contains("/usr/bin/sudo -n -u \"#$ASUSER\" /bin/mv -f")
                && !installerScript.contains("note() { /bin/echo \"$1\" > \"$RESULT.progress\""),
               "elevated marker writes drop to the original user's credentials")
        let elevated = UpdateInstallerSupport.elevatedInstallCommand(
            appPath: "/Applications/Vorssaint.app",
            dmgPath: "/tmp/Vorssaint-update.dmg",
            pid: 123,
            resultPath: "/tmp/result",
            uid: 501,
            expectedVersion: "3.3.3")
        expect(elevated.contains("POSIX::setsid()") && elevated.hasSuffix("&"),
               "elevated installer leaves this app's session so it outlives the app it replaces")
        expect(elevated.contains("nohup"),
               "elevated installer keeps the nohup fallback if setsid is unavailable")
        expect(elevated.contains("'/Applications/Vorssaint.app'"),
               "elevated installer passes the app path quoted for the shell")
        expect(elevated.contains("'3.3.3'"),
               "elevated installer passes the expected version quoted for the shell")
        // The script travels inline and is long; it must be spelled once, with
        // both the setsid attempt and the fallback reusing the same "$@".
        expect(elevated.components(separatedBy: "DMG_VERIFY_REQ=").count == 2
               && elevated.components(separatedBy: "\"$@\"").count == 3,
               "elevated installer names its arguments once and reuses them for the fallback")
    }

    static func runReconciliation(expect: (Bool, String) -> Void) {
        // MARK: - UpdateServiceSupport & SemVer channel reconciliation

        let vStable = UpdateServiceSupport.SemanticVersion(raw: "3.3.3")
        expect(vStable?.major == 3 && vStable?.minor == 3 && vStable?.patch == 3 && !vStable!.isPrerelease,
               "parses standard stable version")

        let vBeta = UpdateServiceSupport.SemanticVersion(raw: "v3.3.4-beta.1")
        expect(vBeta?.major == 3 && vBeta?.minor == 3 && vBeta?.patch == 4 && vBeta!.isPrerelease,
               "parses beta version with leading v")

        let vBuild = UpdateServiceSupport.SemanticVersion(raw: "3.3.4-rc.2+20260822")
        expect(vBuild?.major == 3 && vBuild?.minor == 3 && vBuild?.patch == 4 && vBuild!.isPrerelease,
               "parses version with build metadata")

        // SemVer 2.0.0 ordering rules
        expect(UpdateServiceSupport.isNewer("3.3.4", than: "3.3.3"),
               "newer major/minor/patch stable is newer")
        expect(!UpdateServiceSupport.isNewer("3.3.3", than: "3.3.4"),
               "older stable is not newer")
        expect(UpdateServiceSupport.isNewer("3.3.4-beta.1", than: "3.3.3"),
               "beta of higher version is newer than older stable")
        expect(UpdateServiceSupport.isNewer("3.3.4-beta.2", than: "3.3.4-beta.1"),
               "beta.2 is newer than beta.1 of the same cycle")
        expect(UpdateServiceSupport.isNewer("3.3.4-rc.1", than: "3.3.4-beta.2"),
               "rc.1 is newer than beta.2")
        expect(UpdateServiceSupport.isNewer("3.3.4", than: "3.3.4-beta.2"),
               "final stable release is newer than beta of same version")
        expect(UpdateServiceSupport.isNewer("3.3.4", than: "3.3.4-rc.1"),
               "final stable release is newer than rc of same version")
        expect(!UpdateServiceSupport.isNewer("3.3.3", than: "3.3.4-beta.1"),
               "older stable is never newer than a beta of higher version (no downgrade)")
        expect(!UpdateServiceSupport.isNewer("3.3.4-beta.1", than: "3.3.4"),
               "beta is not newer than the released final version")

        // Release candidate selection
        let dummyDMG = URL(string: "https://github.com/vorssaint/vorssaint-utils/releases/download/v3.3.4/Vorssaint.dmg")!
        let dummyBetaDMG = URL(string: "https://github.com/vorssaint/vorssaint-utils/releases/download/v3.3.4-beta.1/Vorssaint.dmg")!

        let candidateList = [
            UpdateServiceSupport.ReleaseCandidate(tagName: "v3.3.4-beta.1", isPrerelease: true, isDraft: false, dmgURL: dummyBetaDMG, dmgExpectedBytes: 1000, body: "Beta notes"),
            UpdateServiceSupport.ReleaseCandidate(tagName: "v3.3.3", isPrerelease: false, isDraft: false, dmgURL: dummyDMG, dmgExpectedBytes: 1000, body: "Stable notes"),
            UpdateServiceSupport.ReleaseCandidate(tagName: "v3.3.5-beta.1", isPrerelease: true, isDraft: true, dmgURL: dummyBetaDMG, dmgExpectedBytes: 1000, body: "Draft notes")
        ]

        let selectedStable = UpdateServiceSupport.selectUpdate(from: candidateList, currentVersion: "3.3.2", includeBetas: false)
        expect(selectedStable?.tagName == "v3.3.3", "stable channel only picks stable releases")

        let selectedBeta = UpdateServiceSupport.selectUpdate(from: candidateList, currentVersion: "3.3.2", includeBetas: true)
        expect(selectedBeta?.tagName == "v3.3.4-beta.1", "beta channel picks highest non-draft release")

        let selectedFromHigherBeta = UpdateServiceSupport.selectUpdate(from: candidateList, currentVersion: "3.3.4-beta.1", includeBetas: false)
        expect(selectedFromHigherBeta == nil, "user on beta turning off betas does not downgrade to older stable")

        let knownDigest = "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"
        expect(UpdateServiceSupport.sha256Matches(Data("abc".utf8), expectedHex: knownDigest),
               "update media accepts its pinned SHA-256 digest")
        expect(!UpdateServiceSupport.sha256Matches(Data("altered".utf8), expectedHex: knownDigest),
               "update media rejects content that does not match its pinned digest")
        expect(!UpdateServiceSupport.sha256Matches(Data("abc".utf8), expectedHex: "invalid"),
               "update media rejects a malformed pinned digest")

        // Defaults registered
        expect(Defaults.registeredDefaults[DefaultsKey.includeBetaUpdates] as? Bool == false,
               "includeBetaUpdates defaults to false in registeredDefaults")

        let testDefaults = UserDefaults(suiteName: "com.vorssaint.tests.betaActivation")!
        testDefaults.removePersistentDomain(forName: "com.vorssaint.tests.betaActivation")
        Defaults.activateBetaChannelIfRunningBeta(in: testDefaults, version: "3.3.3-beta.1")
        expect(testDefaults.bool(forKey: DefaultsKey.includeBetaUpdates) == true,
               "beta channel is activated automatically on a beta build")
        testDefaults.set(false, forKey: DefaultsKey.includeBetaUpdates)
        Defaults.activateBetaChannelIfRunningBeta(in: testDefaults, version: "3.3.3-beta.1")
        expect(testDefaults.bool(forKey: DefaultsKey.includeBetaUpdates) == false,
               "manual opt-out on a beta build is preserved across launches")

        // Stable version does not activate beta channel
        let stableDefaults = UserDefaults(suiteName: "com.vorssaint.tests.stableActivation")!
        stableDefaults.removePersistentDomain(forName: "com.vorssaint.tests.stableActivation")
        Defaults.activateBetaChannelIfRunningBeta(in: stableDefaults, version: "3.3.3")
        expect(stableDefaults.object(forKey: DefaultsKey.includeBetaUpdates) == nil,
               "stable release does not touch beta channel default")
        stableDefaults.removePersistentDomain(forName: "com.vorssaint.tests.stableActivation")
        testDefaults.removePersistentDomain(forName: "com.vorssaint.tests.betaActivation")

        // Localization completeness & formatting
        for language in AppLanguage.allCases {
            L10n.shared.language = language
            let s = L10n.shared.s
            expect(!s.includeBetaUpdatesToggle.isEmpty, "\(language.rawValue) includeBetaUpdatesToggle non-empty")
            expect(!s.includeBetaUpdatesCaption.isEmpty, "\(language.rawValue) includeBetaUpdatesCaption non-empty")
            expect(!s.betaBadgeLabel.isEmpty, "\(language.rawValue) betaBadgeLabel non-empty")
            expect(!s.includeBetaUpdatesCaption.contains("—"), "\(language.rawValue) has no em dash")
        }
        L10n.shared.language = .enUS

        // MARK: Launch at login reconciliation

        expect(LaunchAtLoginSupport.startupAction(wanted: true, registration: .off,
                                                  locationIsUnstable: false) == .register,
               "a lost registration the user wants is redone at startup")
        expect(LaunchAtLoginSupport.startupAction(wanted: true, registration: .off,
                                                  locationIsUnstable: true) == .none,
               "no registration is redone from an unstable location")
        expect(LaunchAtLoginSupport.startupAction(wanted: true, registration: .enabled,
                                                  locationIsUnstable: false) == .none
                && LaunchAtLoginSupport.startupAction(wanted: true, registration: .enabled,
                                                      locationIsUnstable: true) == .none,
               "a healthy registration is left alone")
        expect(LaunchAtLoginSupport.startupAction(wanted: false, registration: .enabled,
                                                  locationIsUnstable: false) == .adoptEnabled
                && LaunchAtLoginSupport.startupAction(wanted: false, registration: .enabled,
                                                      locationIsUnstable: true) == .adoptEnabled,
               "an enable made outside the app becomes the stored choice")
        expect(LaunchAtLoginSupport.startupAction(wanted: false, registration: .off,
                                                  locationIsUnstable: false) == .none
                && LaunchAtLoginSupport.startupAction(wanted: false, registration: .off,
                                                      locationIsUnstable: true) == .none,
               "startup never turns launch at login on for a user who never asked")
        expect(LaunchAtLoginSupport.startupAction(wanted: true, registration: .needsApproval,
                                                  locationIsUnstable: false) == .none
                && LaunchAtLoginSupport.startupAction(wanted: false, registration: .needsApproval,
                                                      locationIsUnstable: false) == .none,
               "an item awaiting approval in System Settings is never registered over (issue #260)")
        // `SMAppService.Status` cannot be driven without a real login item, so
        // what the service does with the third state is pinned by source. Both
        // needles are public symbols, not a line's spelling.
        let launchAtLoginSource = (try? String(
            contentsOfFile: "Sources/Vorssaint/Services/LaunchAtLogin.swift",
            encoding: .utf8)) ?? ""
        expect(launchAtLoginSource.contains(".requiresApproval"),
               "an approval-pending login item is read as its own state")
        expect(launchAtLoginSource.contains("throw NeedsApprovalError()"),
               "turning launch at login on says so when only approval is missing")
    }
}
