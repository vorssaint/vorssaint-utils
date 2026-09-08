// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

enum ReleaseTests {
    static func run(expect: (Bool, String) -> Void) {
        let registeredDefaults = Defaults.registeredDefaults
        expect(registeredDefaults[DefaultsKey.autoCheckUpdates] as? Bool == true,
               "update checks are on for clean installs")
        expect(registeredDefaults[DefaultsKey.updateShowcaseIntroVersion] as? String == "",
               "update showcase intro starts unseen")
        expect(registeredDefaults[DefaultsKey.updateShowcaseMediaOverride] as? String == "",
               "update showcase media override is empty by default")
        expect(SupportUpdateIntroInfo.releaseVersion == "3.3.2",
               "support prompt is deliberately pinned to 3.3.2")
        expect(SupportUpdateIntroInfo.shouldShow(appVersion: "3.3.2", lastSeenVersion: "3.3.1"),
               "support prompt shows once after updating to its pinned release")
        expect(!SupportUpdateIntroInfo.shouldShow(appVersion: "3.3.2", lastSeenVersion: "3.3.2"),
               "support prompt stays hidden after it is seen")
        expect(!SupportUpdateIntroInfo.shouldShow(appVersion: "3.3.0", lastSeenVersion: nil)
               && !SupportUpdateIntroInfo.shouldShow(appVersion: "3.3.1", lastSeenVersion: nil)
               && !SupportUpdateIntroInfo.shouldShow(appVersion: "3.3.3", lastSeenVersion: nil),
               "support prompt never leaks into another release")
        expect(SupportUpdateIntroStep.support.next == .social
               && SupportUpdateIntroStep.social.next == nil,
               "update intro moves from support to social updates")
        expect(SupportUpdateIntroStep.support.previous == nil
               && SupportUpdateIntroStep.social.previous == .support,
               "update intro navigates back without closing")
        expect(SupportUpdateIntroStep.allCases == [.support, .social],
               "update intro page indicators follow the navigation order")
        expect(AppInfo.discordURL.absoluteString == "https://discord.gg/M6BwWH4BJp",
               "the community action uses the permanent Discord invitation")
        expect(AppInfo.coffeeURL.absoluteString == "https://buymeacoffee.com/vorssaint",
               "financial support uses Buy Me a Coffee")
        expect(AppInfo.socialURL.absoluteString == "https://x.com/vorssaint",
               "social previews keep the official X profile")
        // AppInfo.version falls back to "dev" in this bare harness, so read
        // the plist the shipped app will actually carry. The pin is a
        // per-release decision: this check fails on every version bump so the
        // decision above is made consciously, never by omission.
        let releasePlist = NSDictionary(contentsOfFile: "Resources/Info.plist")
        let plistVersion = (releasePlist?["CFBundleShortVersionString"] as? String) ?? ""
        expect(plistVersion == "3.3.5",
               "bumping the app version requires re-deciding the support prompt pin above")
        let plistBuild = (releasePlist?["CFBundleVersion"] as? String) ?? ""
        expect(plistBuild == "86",
               "every app version needs its own incremented bundle build")
        expect(SupportUpdateIntroInfo.releaseVersion == "3.3.2",
               "the support prompt remains deliberately pinned to 3.3.2")
        // 3.3.3 adds several headline features, so the tour is re-curated
        // around only what this update introduces. The hotfix releases patch
        // that release: whoever skipped 3.3.3 still gets its tour once, and
        // whoever already saw it does not see it again.
        expect(UpdateHighlightsInfo.releaseVersion == "3.3.3",
               "re-decide the highlights tour on a feature release: re-curate its rows and move the pin to the shipping version")
        expect(UpdateHighlightsInfo.shouldShow(appVersion: "3.3.3", lastSeenVersion: "3.3.2")
               && UpdateHighlightsInfo.shouldShow(appVersion: "3.3.3-beta.5", lastSeenVersion: "3.3.2")
               && UpdateHighlightsInfo.shouldShow(appVersion: "3.3.3", lastSeenVersion: nil)
               && UpdateHighlightsInfo.shouldShow(appVersion: "3.3.4", lastSeenVersion: "3.3.2")
               && UpdateHighlightsInfo.shouldShow(appVersion: "3.3.4", lastSeenVersion: nil),
               "highlights tour shows once after updating to its pinned release, its betas or a patch of it")
        expect(!UpdateHighlightsInfo.shouldShow(appVersion: "3.3.3", lastSeenVersion: "3.3.3")
               && !UpdateHighlightsInfo.shouldShow(appVersion: "3.3.3-beta.5", lastSeenVersion: "3.3.3")
               && !UpdateHighlightsInfo.shouldShow(appVersion: "3.3.4", lastSeenVersion: "3.3.3"),
               "highlights tour stays hidden after it is seen, patches included")
        expect(!UpdateHighlightsInfo.shouldShow(appVersion: "3.3.2", lastSeenVersion: nil)
               && !UpdateHighlightsInfo.shouldShow(appVersion: "3.4.0", lastSeenVersion: nil)
               && !UpdateHighlightsInfo.shouldShow(appVersion: "4.0.0", lastSeenVersion: nil),
               "highlights tour never leaks into another feature release")
        expect(UpdateHighlightsInfo.shouldShow(appVersion: "3.3.5", lastSeenVersion: "3.3.2"),
               "updating directly from 3.3.2 to 3.3.5 shows the feature tour that was skipped")
        expect(UpdateHighlightsInfo.shouldShow(appVersion: "3.3.5", lastSeenVersion: nil),
               "3.3.5 shows the feature tour when no earlier tour was recorded")
        expect(!UpdateHighlightsInfo.shouldShow(appVersion: "3.3.5", lastSeenVersion: "3.3.3"),
               "a tour already seen in 3.3.3 or its hotfixes does not repeat in 3.3.5")
        expect(FileManager.default.fileExists(atPath: "Resources/Images/highlights-windowlayout.png")
               && FileManager.default.fileExists(atPath: "Resources/Images/highlights-quitprotection.png")
               && FileManager.default.fileExists(atPath: "Resources/Images/highlights-recorderblur.png"),
               "3.3.3 highlights tour includes curated real captures for window layout, quit protection and recorder blur")
    }

    static func runNotes(expect: (Bool, String) -> Void) {
        // MARK: Release notes parsing

        let changelog = """
        # Changelog

        ## [2.17.2] - 2026-06-17

        ### Summary
        This update keeps **Shelf** clear
        and the update window centered.

        ### Fixed
        - **Shelf** no longer shows an extra outline.
        - The update window opens centered
          on the visible screen.

        ### Added
        - Coffee shortcut in the menu panel.
        ![Menu bar temperature metrics](Resources/Images/menu-bar-temperature-metrics.png)

        ### Website
        - Official site: [vorssaint.com](https://vorssaint.com).

        ## [2.17.1] - 2026-06-17

        ### Fixed
        - Older release note.
        """
        let notes = ReleaseNotes.notes(for: "2.17.2", changelog: changelog)
        expect(notes.version == "2.17.2", "release notes version is parsed")
        expect(notes.date == "2026-06-17", "release notes date is parsed")
        expect(notes.sections.count == 3, "release notes keep sections for the requested version")
        expect(notes.sections.first?.title == "Summary", "release notes first section title is parsed")
        expect(notes.sections.first?.paragraphItems.first == "This update keeps Shelf clear and the update window centered.",
               "release notes parse summary paragraphs")
        expect(notes.sections.dropFirst().first?.title == "Fixed", "release notes fixed section title is parsed")
        expect(notes.sections.dropFirst().first?.bulletItems.first == "Shelf no longer shows an extra outline.",
               "release notes strip simple markdown emphasis")
        expect(notes.sections.dropFirst().first?.bulletItems.dropFirst().first == "The update window opens centered on the visible screen.",
               "release notes join continuation lines")
        expect(notes.sections.last?.bulletItems == ["Coffee shortcut in the menu panel."],
               "release notes stop before the next version")
        expect(notes.sections.last?.items.last == .image(ReleaseNoteImage(alt: "Menu bar temperature metrics",
                                                                          path: "Resources/Images/menu-bar-temperature-metrics.png")),
               "release notes parse changelog images")
        expect(!notes.sections.contains(where: { $0.title == "Website" }),
               "release notes hide website sections from the feature list")
        let previewBodyWithoutSummaryHeading = """
        ## [2.17.3]

        A short release summary from the GitHub release body.

        ### Fixed
        - Preview bullet.
        """
        let previewNotes = ReleaseNotes.notes(for: "2.17.3", changelog: previewBodyWithoutSummaryHeading)
        expect(previewNotes.sections.first?.title == "Summary",
               "release notes preserve an unheaded release-body summary paragraph")
        expect(previewNotes.sections.first?.paragraphItems.first == "A short release summary from the GitHub release body.",
               "release notes keep summary text before the first subsection")
        let githubReleaseBodyWithFooter = """
        ### Fixed
        - Update preview stays focused on changes.

        Signed with an Apple Developer ID and notarized by Apple, so it downloads and opens normally. Requires macOS 14 or later. Open the .dmg below and drag Vorssaint to Applications.
        """
        let inAppUpdateBody = ReleaseNotes.inAppUpdateNotes(from: githubReleaseBodyWithFooter) ?? ""
        expect(!inAppUpdateBody.contains("Signed with an Apple Developer ID"),
               "in-app update notes remove the GitHub installation footer")
        let githubPreviewNotes = ReleaseNotes.notes(for: "2.17.4",
                                                    changelog: "## [2.17.4]\n\n" + inAppUpdateBody)
        expect(githubPreviewNotes.sections.first?.bulletItems == ["Update preview stays focused on changes."],
               "in-app update notes keep release changes after removing the footer")
        let unreleasedChangelog = """
        ## [Unreleased]

        ### Added
        - Feature pending release.

        ## [2.17.4] - 2026-06-18

        ### Fixed
        - Shipped fix.
        """
        let unreleasedNotes = ReleaseNotes.notes(for: "Unreleased", changelog: unreleasedChangelog)
        expect(unreleasedNotes.version == "Unreleased" && unreleasedNotes.date == nil
               && unreleasedNotes.sections.first?.bulletItems == ["Feature pending release."],
               "release notes parse unreleased blocks without dates")
        expect(ReleaseNotes.allVersions(changelog: unreleasedChangelog) == ["2.17.4"],
               "allVersions excludes the unreleased header")
        expect(ReleaseNotes.rawNotes(for: "dev", changelog: unreleasedChangelog).contains("Feature pending release."),
               "rawNotes for dev falls back to the unreleased block")
    }
}
