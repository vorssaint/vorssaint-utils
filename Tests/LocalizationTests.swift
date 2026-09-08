// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Darwin
import Foundation

enum LocalizationTests {
    static func run(expect: (Bool, String) -> Void) {
        func expectFormat(_ format: String, _ expected: [String], _ label: String) {
            let actual = formatSpecifiers(in: format)
            expect(actual == expected, "\(label): got \(actual), expected \(expected)")
        }

        // MARK: Localization format contracts

        let localizedStrings: [(AppLanguage, Strings)] = [
            (.enUS, .enUS),
            (.ptBR, .ptBR),
            (.tr, .tr),
            (.ru, .ru),
            (.es, .es),
            (.de, .de),
            (.fr, .fr),
            (.it, .it),
            (.ja, .ja),
            (.ko, .ko),
            (.zhHans, .zhHans),
            (.zhTW, .zhTW),
            (.zhHK, .zhHK)
        ]
        expect(localizedStrings.count == AppLanguage.allCases.count, "all app languages are covered by tests")
        // Thirty-six feature string sets were held to the no-em-dash rule and
        // the main one never was, so a caption in every language carried a
        // pair of them.
        for (language, strings) in localizedStrings {
            let values = Mirror(reflecting: strings).children.compactMap { $0.value as? String }
            expect(values.allSatisfy { !$0.contains("\u{2014}") },
                   "no em-dash in visible strings (\(language.rawValue))")
        }
        // The system writes an apostrophe as a curled mark, and so does every
        // string here now: five hundred and ninety-nine of them were typewriter
        // straight, and eleven quoted a setting with straight pairs instead of
        // the marks their language uses.
        var typewriterMarks: [String] = []
        for folder in ["Sources/Vorssaint/Core", "Sources/Vorssaint/Core/Localizations"] {
            for name in (try? FileManager.default.contentsOfDirectory(atPath: folder)) ?? [] {
                guard name.hasSuffix("Strings.swift") || name.hasPrefix("Strings+")
                        || name == "Localization.swift" else { continue }
                let full = folder + "/" + name
                for (index, line) in (((try? String(contentsOfFile: full, encoding: .utf8)) ?? "")
                    .components(separatedBy: "\n")).enumerated() {
                    guard !line.trimmingCharacters(in: .whitespaces).hasPrefix("//") else { continue }
                    guard let opening = line.firstIndex(of: "\""),
                          let closing = line.lastIndex(of: "\""), opening < closing else { continue }
                    if line[opening..<closing].contains("'") {
                        typewriterMarks.append("\(full):\(index + 1)")
                    }
                }
            }
        }
        expect(typewriterMarks.isEmpty,
               "visible text curls its apostrophes (\(typewriterMarks.prefix(6).joined(separator: ", ")))")
        // French sets a space before its double punctuation and inside its
        // quotes, and that space must not break: a plain one lets a colon or a
        // closing guillemet fall alone onto the next line of a narrow panel.
        // Written as an escape so the character stays visible in the source.
        func frenchLines(_ path: String) -> ArraySlice<String> {
            let lines = ((try? String(contentsOfFile: path, encoding: .utf8)) ?? "")
                .components(separatedBy: "\n")
            guard !path.hasSuffix("Strings+French.swift") else { return lines[...] }
            guard let start = lines.firstIndex(where: {
                $0.trimmingCharacters(in: .whitespaces).hasPrefix("static let fr = ")
            }) else { return [][...] }
            let end = lines[(start + 1)...].firstIndex {
                $0.trimmingCharacters(in: .whitespaces).hasPrefix("static let ")
            } ?? lines.endIndex
            return lines[start..<end]
        }
        var breakingFrench: [String] = []
        var frenchSources = ["Sources/Vorssaint/Core/Localizations/Strings+French.swift"]
        frenchSources += ((try? FileManager.default
            .contentsOfDirectory(atPath: "Sources/Vorssaint/Core")) ?? [])
            .filter { $0.hasSuffix("Strings.swift") }
            .sorted()
            .map { "Sources/Vorssaint/Core/" + $0 }
        for path in frenchSources {
            for line in frenchLines(path) {
                guard !line.trimmingCharacters(in: .whitespaces).hasPrefix("//") else { continue }
                guard let opening = line.firstIndex(of: "\""),
                      let closing = line.lastIndex(of: "\""), opening < closing else { continue }
                let body = String(line[line.index(after: opening)..<closing])
                let breaks = [" ;", " :", " !", " ?", " \u{00BB}", "\u{00AB} "]
                if breaks.contains(where: { body.contains($0) }) {
                    breakingFrench.append(path.components(separatedBy: "/").last ?? path)
                }
            }
        }
        expect(breakingFrench.isEmpty,
               "French keeps its punctuation on the line it belongs to (\(Set(breakingFrench).sorted().prefix(4).joined(separator: ", ")))")
        let themeSource = (try? String(contentsOfFile: "Sources/Vorssaint/UI/Theme.swift",
                                       encoding: .utf8)) ?? ""
        let raisedReads = themeSource
            .components(separatedBy: "accessibilityDisplayShouldIncreaseContrast").count - 1
        expect(raisedReads == 2,
               "both panel outlines answer raised contrast, and nothing else pretends to")
        // A decimal built without a region is always written with a point, so
        // the panel, the menu bar and the editors were showing one to readers
        // whose system writes a comma. Every float says which region it is in;
        // the two that feed a command line say so out loud.
        var regionlessDecimals: [String] = []
        for path in (try? FileManager.default.subpathsOfDirectory(atPath: "Sources")) ?? [] {
            guard path.hasSuffix(".swift") else { continue }
            let full = "Sources/" + path
            let lines = ((try? String(contentsOfFile: full, encoding: .utf8)) ?? "")
                .components(separatedBy: "\n")
            for (index, line) in lines.enumerated() {
                // A long call puts the region on the next line, so the whole
                // statement is read, not the first line of it.
                let statement = lines[index...min(index + 2, lines.count - 1)].joined()
                guard line.contains("String(format:"), !statement.contains("locale:") else { continue }
                let piece = line.components(separatedBy: "String(format:").dropFirst().first ?? ""
                let format = piece.components(separatedBy: "\"").dropFirst().first ?? ""
                if format.contains("f") && format.contains("%") {
                    regionlessDecimals.append("\(full):\(index + 1)")
                }
            }
        }
        expect(regionlessDecimals.isEmpty,
               "a decimal on screen names its region (\(regionlessDecimals.joined(separator: ", ")))")
        // Purgeable space is a question for a writable volume. Asked of every
        // mounted one, an attached disk image answered with an error on every
        // sample; the bulk fetch no longer carries the key at all.
        let samplerCode = ((try? String(
            contentsOfFile: "Sources/Vorssaint/Services/Metrics/DiskSampler.swift",
            encoding: .utf8)) ?? "")
            .components(separatedBy: "\n")
            .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }
            .joined(separator: "\n")
        expect(!samplerCode.isEmpty, "the disk sampler reads back for its shape check")
        let bulkKeys = samplerCode.components(separatedBy: "let keys: Set<URLResourceKey>")
            .dropFirst().first?.components(separatedBy: "]").first ?? ""
        expect(!bulkKeys.contains("volumeAvailableCapacityForImportantUsageKey")
                && bulkKeys.contains("volumeIsReadOnlyKey"),
               "the bulk volume fetch asks nothing that only a writable volume can answer")
        expect(samplerCode.contains("guard !isReadOnly,"),
               "purgeable space is read only where there is something to purge")
        // A format string whose placeholders differ between languages feeds
        // String(format:) arguments it was not written for, and the result is
        // garbage or worse. Only fields that really reach a format are read:
        // one caption documents the app's own file-name tokens in prose and
        // its percent signs mean nothing here.
        var formatFields: Set<String> = []
        for path in (try? FileManager.default.subpathsOfDirectory(atPath: "Sources")) ?? [] {
            guard path.hasSuffix(".swift") else { continue }
            let text = (try? String(contentsOfFile: "Sources/" + path, encoding: .utf8)) ?? ""
            for piece in text.components(separatedBy: "String(format:").dropFirst() {
                let head = piece.prefix(120)
                guard let comma = head.firstIndex(of: ",") else { continue }
                // The last dot BEFORE the comma: a dot in the arguments that
                // follow belongs to something else entirely.
                let expression = head[head.startIndex..<comma]
                guard let dot = expression.lastIndex(of: ".") else { continue }
                let name = expression[expression.index(after: dot)...]
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                if !name.isEmpty, name.allSatisfy({ $0.isLetter || $0.isNumber }) {
                    formatFields.insert(name)
                }
            }
        }
        expect(formatFields.count > 10, "the format fields were found to compare (\(formatFields.count))")
        var mismatched: [String] = []
        for (language, strings) in localizedStrings where language != .enUS {
            let mine = Mirror(reflecting: strings).children
            let base = Mirror(reflecting: Strings.enUS).children
            for (left, right) in zip(base, mine) {
                guard let label = left.label, formatFields.contains(label),
                      let english = left.value as? String,
                      let other = right.value as? String else { continue }
                if placeholderShape(english) != placeholderShape(other) {
                    mismatched.append("\(label)/\(language.rawValue)")
                }
            }
        }
        expect(mismatched.isEmpty,
               "every language fills a format the same way (\(mismatched.prefix(5).joined(separator: ", ")))")
        // Quotation marks are part of looking native and each language has its
        // own. Checked against what the system itself ships on this Mac: French
        // and Russian use the angled pair, German pairs a low opening mark with
        // a high closing one, and every other language here uses the curly
        // pair. Spanish, Italian, Portuguese and Turkish had picked up the
        // angled pair, which reads as a translation from somewhere else.
        // A label that says work is under way ends with the ellipsis character,
        // the way the system's own do, not with three periods. Ten of the
        // thirteen languages had the periods while three already had the
        // character, which is the tell that it was never a decision.
        for (language, strings) in localizedStrings {
            let working = [strings.homebrewOperationPreparing, strings.homebrewOperationDownloading,
                           strings.homebrewOperationInstalling, strings.homebrewOperationUninstalling,
                           strings.homebrewOperationUpgrading, strings.homebrewOperationFinalizing,
                           strings.homebrewOperationRefreshing]
            expect(working.allSatisfy { !$0.contains("...") && $0.contains("…") },
                   "work in progress ends with the ellipsis character in \(language.rawValue)")
        }
        for (language, strings) in localizedStrings {
            let values = Mirror(reflecting: strings).children.compactMap { $0.value as? String }
            let anglesUsed = values.contains { $0.contains("«") || $0.contains("»") }
            expect(anglesUsed == (language == .fr || language == .ru),
                   "only French and Russian quote with angled marks (\(language.rawValue))")
            let lowOpenUsed = values.contains { $0.contains("„") }
            expect(lowOpenUsed == (language == .de),
                   "only German opens a quote with the low mark (\(language.rawValue))")
        }
        for (language, strings) in localizedStrings {
            let prefix = "localization \(language.rawValue)"
            expect(!strings.smoothScrollStepLabel.isEmpty
                   && !strings.smoothScrollResponseLabel.isEmpty
                   && !strings.smoothScrollStepLabel.contains("—")
                   && !strings.smoothScrollResponseLabel.contains("—"),
                   "\(prefix) smooth scrolling controls are present without em dash")
            expect(strings.quickToolsTab == strings.launcherName,
                   "\(prefix) Quick panel keeps the same name in Settings")
            expectFormat(strings.cutMovedPluralFormat, ["d"], "\(prefix) cut plural format")
            expectFormat(strings.uninstallerSelectedFormat, ["d", "d"], "\(prefix) uninstaller selected format")
            expectFormat(strings.uninstallerFreedFormat, ["@"], "\(prefix) uninstaller freed format")
            expectFormat(strings.shelfSelectedFormat, ["d"], "\(prefix) shelf selection format")
            expect(!strings.shelfClearOnClose.isEmpty
                   && !strings.shelfClearOnCloseCaption.isEmpty
                   && !strings.shelfClearOnClose.contains("—")
                   && !strings.shelfClearOnCloseCaption.contains("—"),
                   "\(prefix) shelf clear-on-close labels are present without em dash")
            expectFormat(strings.powerAdapterMaxFormat, ["@"], "\(prefix) adapter max format")
            expectFormat(strings.mixerInputErrorFormat, ["@"], "\(prefix) mixer input error format")
            expect(!strings.mixerSoundEffectsOutputTitle.isEmpty
                   && !strings.mixerSoundEffectsOutputTooltip.isEmpty
                   && !strings.mixerSoundEffectsOutputTitle.contains("—")
                   && !strings.mixerSoundEffectsOutputTooltip.contains("—"),
                   "\(prefix) system sound output labels are present without em dash")
            expect(!strings.keepAwakeRightClickToggle.isEmpty
                   && !strings.keepAwakeRightClickToggleCaption.isEmpty
                   && !strings.keepAwakeRightClickToggle.contains("—")
                   && !strings.keepAwakeRightClickToggleCaption.contains("—"),
                   "\(prefix) right-click Keep Awake labels are present without em dash")
            expectFormat(strings.homebrewConfirmInstallBodyFormat, ["@"], "\(prefix) Homebrew install format")
            expectFormat(strings.homebrewConfirmUninstallBodyFormat, ["@"], "\(prefix) Homebrew uninstall format")
            expectFormat(strings.homebrewConfirmUpgradeBodyFormat, ["@"], "\(prefix) Homebrew upgrade format")
            expect(!strings.homebrewUpgradeAll.isEmpty, "\(prefix) Homebrew update all title is present")
            expect(!strings.homebrewUpdateHomebrew.isEmpty, "\(prefix) Homebrew update Homebrew title is present")
            expectFormat(strings.switcherIconRowMode, ["@"], "\(prefix) App Switcher icon-row title format")
            expect(!strings.switcherIconRowModeCaption.isEmpty, "\(prefix) App Switcher icon-row caption is present")
            expect(!strings.switcherSimpleMode.isEmpty, "\(prefix) App Switcher simple-mode title is present")
            expect(!strings.switcherSimpleModeCaption.isEmpty, "\(prefix) App Switcher simple-mode caption is present")
            expect(!strings.switcherCurrentSpaceOnly.isEmpty
                   && !strings.switcherCurrentSpaceOnly.contains("—"),
                   "\(prefix) App Switcher current-desktop title is present without em dash")
            expect(!strings.switcherCurrentSpaceOnlyCaption.isEmpty
                   && !strings.switcherCurrentSpaceOnlyCaption.contains("—"),
                   "\(prefix) App Switcher current-desktop caption is present without em dash")
            expect(!strings.switcherCurrentDisplayOnly.isEmpty
                   && !strings.switcherCurrentDisplayOnly.contains("—"),
                   "\(prefix) App Switcher current-display title is present without em dash")
            expect(!strings.switcherCurrentDisplayOnlyCaption.isEmpty
                   && !strings.switcherCurrentDisplayOnlyCaption.contains("—"),
                   "\(prefix) App Switcher current-display caption is present without em dash")
            expect([strings.switcherScreenPlacementLabel,
                    strings.switcherScreenPlacementPointer,
                    strings.switcherScreenPlacementMenuBar,
                    strings.switcherScreenPlacementActiveWindow,
                    strings.switcherScreenPlacementCaption]
                   .allSatisfy { !$0.isEmpty && !$0.contains("—") },
                   "\(prefix) App Switcher screen placement labels are present without em dash")
            expect(!strings.switcherOtherDesktop.isEmpty
                   && !strings.switcherOtherDesktop.contains("—"),
                   "\(prefix) App Switcher other-desktop label is present without em dash")
            expect(!strings.switcherSearchPin.isEmpty
                   && !strings.switcherSearchPinCaption.isEmpty
                   && !strings.switcherSearchPin.contains("—")
                   && !strings.switcherSearchPinCaption.contains("—"),
                   "\(prefix) App Switcher pinned-search labels are present without em dash")
            expect(!strings.switcherShowShortcutHints.isEmpty
                   && !strings.switcherShowShortcutHintsCaption.isEmpty
                   && !strings.switcherShowShortcutHints.contains("—")
                   && !strings.switcherShowShortcutHintsCaption.contains("—"),
                   "\(prefix) App Switcher shortcut-hint labels are present without em dash")
            expect(!strings.switcherAppearanceDelay.isEmpty
                   && !strings.switcherAppearanceDelayCaption.isEmpty
                   && !strings.switcherAppearanceDelay.contains("—")
                   && !strings.switcherAppearanceDelayCaption.contains("—"),
                   "\(prefix) App Switcher appearance-delay labels are present without em dash")
            expect(!strings.switcherWindowlessApps.isEmpty
                   && !strings.switcherWindowlessApps.contains("—"),
                   "\(prefix) App Switcher windowless apps title is present without em dash")
            expect(!strings.switcherWindowlessAppsCaption.isEmpty
                   && !strings.switcherWindowlessAppsCaption.contains("—"),
                   "\(prefix) App Switcher windowless apps caption is present without em dash")
            expect(!strings.dockClickHide.isEmpty
                   && !strings.dockClickHideCaption.isEmpty
                   && !strings.dockClickHide.contains("—")
                   && !strings.dockClickHideCaption.contains("—"),
                   "\(prefix) Dock hide labels are present without em dash")
            expect(!strings.switcherWindowlessAppsOff.isEmpty
                   && !strings.switcherWindowlessAppsFinder.isEmpty
                   && !strings.switcherWindowlessAppsAll.isEmpty
                   && !strings.switcherWindowlessAppsOff.contains("—")
                   && !strings.switcherWindowlessAppsFinder.contains("—")
                   && !strings.switcherWindowlessAppsAll.contains("—"),
                   "\(prefix) App Switcher windowless apps choices are all present without em dash")
            expect(!strings.diskAvailable.isEmpty
                   && !strings.diskPurgeable.isEmpty
                   && !strings.diskAvailable.contains("—")
                   && !strings.diskPurgeable.contains("—"),
                   "\(prefix) disk available and purgeable labels are present without em dash")
            expect(!strings.switcherNoOpenWindow.isEmpty
                   && !strings.switcherNoOpenWindow.contains("—"),
                   "\(prefix) App Switcher no-open-window tile label is present without em dash")
            expect(!strings.dockPreviewBackgroundOpacity.isEmpty
                   && !strings.dockPreviewBackgroundOpacity.contains("—"),
                   "\(prefix) Dock Preview background title is present without em dash")
            expect(!strings.dockPreviewBackgroundOpacityCaption.isEmpty
                   && !strings.dockPreviewBackgroundOpacityCaption.contains("—"),
                   "\(prefix) Dock Preview background caption is present without em dash")
            expect(!strings.dockPreviewOpenDelay.isEmpty
                   && !strings.dockPreviewOpenDelay.contains("—"),
                   "\(prefix) Dock Preview open delay title is present without em dash")
            expect(!strings.dockPreviewOpenDelayCaption.isEmpty
                   && !strings.dockPreviewOpenDelayCaption.contains("—"),
                   "\(prefix) Dock Preview open delay caption is present without em dash")
            expect(!strings.minimalWindowPreviews.isEmpty && !strings.minimalWindowPreviewsCaption.isEmpty
                   && !strings.minimalWindowPreviews.contains("—") && !strings.minimalWindowPreviewsCaption.contains("—"),
                   "\(prefix) minimal previews have a localized title and explanation")
            expect(!strings.dockPreviewQuitAppOnClose.isEmpty
                   && !strings.dockPreviewQuitAppOnClose.contains("—")
                   && !strings.dockPreviewQuitAppOnCloseCaption.isEmpty
                   && !strings.dockPreviewQuitAppOnCloseCaption.contains("—"),
                   "\(prefix) Dock Preview quit-on-close labels are present without em dash")
            expect(!strings.switcherShortcutHintApps.isEmpty, "\(prefix) App Switcher app shortcut hint is present")
            expect(!strings.switcherShortcutHintWindows.isEmpty, "\(prefix) App Switcher window shortcut hint is present")
            expect(!strings.networkApps.isEmpty, "\(prefix) network app usage title is present")
            expect(!strings.networkAppsIdle.isEmpty, "\(prefix) network app idle text is present")
            expect(!strings.monitorOpenActivityMonitor.isEmpty
                   && !strings.monitorOpenActivityMonitor.contains("—"),
                   "\(prefix) Activity Monitor action is present without em dash")
            expect(!strings.memoryCompressed.isEmpty
                   && !strings.memoryCompressed.contains("—")
                   && !strings.memoryCachedFiles.isEmpty
                   && !strings.memoryCachedFiles.contains("—"),
                   "\(prefix) memory compressed and cached labels are present without em dash")
            expect(!strings.launchAtLoginNeedsApplications.isEmpty
                   && !strings.launchAtLoginNeedsApplications.contains("—"),
                   "\(prefix) launch at login location note is present without em dash")
            // Shortcut recording: the waiting cap, the two hints under the row
            // and the honest message for a combination that never arrived (#308).
            let shortcutCaptureStrings = [strings.shortcutPressKeys, strings.shortcutEscapeHint,
                                          strings.shortcutDeleteHint, strings.shortcutNotCaptured,
                                          strings.shortcutRecording, strings.shortcutInvalid]
            expect(shortcutCaptureStrings.allSatisfy { !$0.isEmpty && !$0.contains("—") },
                   "\(prefix) shortcut recording strings are present without em dash")
            expect(!ShortcutRecordingCaption.text(strings, canClear: false).isEmpty
                   && !ShortcutRecordingCaption.text(strings, canClear: false)
                       .contains(strings.shortcutDeleteHint),
                   "\(prefix) a field that cannot clear never promises that Delete clears")
            expect(ShortcutRecordingCaption.text(strings, canClear: true)
                       .contains(strings.shortcutDeleteHint),
                   "\(prefix) a field that can clear says so")
            expect(strings.shortcutPressKeys.count <= 16,
                   "\(prefix) the waiting cap stays short enough for the field")
            let ocrStrings = [strings.ocrRemoveLineBreaksToggle, strings.ocrRemoveLineBreaksCaption,
                              strings.ocrQRToggle, strings.ocrQRCaption, strings.ocrQRCopied,
                              strings.qrResultTitle, strings.qrResultCopy, strings.qrResultOpen]
            expect(ocrStrings.allSatisfy { !$0.isEmpty && !$0.contains("—") },
                   "\(prefix) screen OCR strings are present without em dash")
            let cleaningStrings = [strings.cleaningKeepScreenVisibleToggle, strings.cleaningKeepScreenVisibleCaption,
                                   strings.cleaningStartNow, strings.cleaningOverlayTitle,
                                   strings.cleaningOverlaySubtitle, strings.cleaningOverlayUnlock,
                                   strings.cleaningOverlayMouseHint, strings.cleaningPanelCaption]
            expect(cleaningStrings.allSatisfy { !$0.isEmpty && !$0.contains("—") },
                   "\(prefix) cleaning mode strings are present without em dash")
            let highlightsStrings = [strings.highlightsTitle, strings.highlightsTitleClipboardRedesign,
                                     strings.highlightsCaptionDockPreview,
                                     strings.highlightsCaptionScreenshot,
                                     strings.highlightsCaptionSnippetLibrary,
                                     strings.highlightsCaptionCapturePalette,
                                     strings.highlightsCaptionClipboardRedesign,
                                     strings.highlightsConfigure,
                                     strings.highlightsTry, strings.highlightsSeeAll,
                                     strings.reviewIntro, strings.reviewHighlights]
            expect(highlightsStrings.allSatisfy { !$0.isEmpty && !$0.contains("—") },
                   "\(prefix) update highlights strings are present without em dash")
            let officialHomebrewIntroStrings = [
                strings.homebrewOfficialIntroTitle,
                strings.homebrewOfficialIntroMessage,
                strings.homebrewOfficialIntroInstallLabel,
                strings.homebrewOfficialIntroMigrationTitle,
                strings.homebrewOfficialIntroMigrationMessage,
                strings.homebrewOfficialIntroCopyButton,
                strings.supportIntroDoneButton,
            ]
            expect(officialHomebrewIntroStrings.allSatisfy { !$0.isEmpty },
                   "\(prefix) official Homebrew intro is complete")
            expect(officialHomebrewIntroStrings.allSatisfy { !$0.contains("—") },
                   "\(prefix) official Homebrew intro has no em dash")
            let supportCommunityStrings = [
                strings.donateHeading,
                strings.donateMessage,
                strings.donateButton,
                strings.supportIntroTitle,
                strings.supportIntroMessage,
                strings.supportIntroStarButton,
                strings.supportIntroStarMessage,
                strings.supportIntroCoffeeButton,
                strings.discordIntroTitle,
                strings.discordIntroMessage,
                strings.discordIntroJoinButton,
                strings.communityIntroTitle,
                strings.communityIntroMessage,
                strings.communityIntroFollowButton,
            ]
            expect(supportCommunityStrings.allSatisfy { !$0.isEmpty && !$0.contains("—") },
                   "\(prefix) support and community strings are complete without em dash")
            expect(strings.donateButton.contains("Buy Me a Coffee")
                   && strings.supportIntroCoffeeButton.contains("Buy Me a Coffee"),
                   "\(prefix) financial support points only to Buy Me a Coffee")
            expect(strings.supportIntroStarMessage.localizedCaseInsensitiveContains("GitHub")
                   && strings.discordIntroJoinButton.localizedCaseInsensitiveContains("Discord"),
                   "\(prefix) non-financial support and community actions name their destinations")
            expect(strings.discordIntroMessage.count <= 320,
                   "\(prefix) Discord introduction stays concise")
            expect(!strings.communityIntroMessage.isEmpty
                   && strings.communityIntroMessage.contains("X"),
                   "\(prefix) community intro invites users to follow previews on X")
            let retiredWeeklyPhrases = [
                "uma vez por semana", "once a week", "haftada bir", "раз в неделю",
                "una vez por semana", "einmal pro Woche", "une fois par semaine",
                "una volta a settimana", "週1回", "매주 한 번", "每周更新一次", "每週更新一次",
            ]
            expect(retiredWeeklyPhrases.allSatisfy {
                !strings.communityIntroMessage.localizedCaseInsensitiveContains($0)
            }, "\(prefix) community intro no longer promises weekly updates")
            expect(!strings.communityIntroMessage.contains("—")
                   && strings.communityIntroMessage.count <= 320,
                   "\(prefix) community intro stays concise and has no em dash")
            if language == .enUS {
                expect(strings.discordIntroMessage.contains("new")
                       && strings.discordIntroMessage.contains("still being built"),
                       "English Discord introduction says the community is new and in development")
            } else if language == .ptBR {
                expect(strings.discordIntroMessage.contains("nova")
                       && strings.discordIntroMessage.contains("em desenvolvimento"),
                       "Portuguese Discord introduction says the community is new and in development")
            }
            expect(!strings.updateShowcaseTitle.isEmpty, "\(prefix) update showcase title is present")
            expect(!strings.updateShowcaseMessage.isEmpty, "\(prefix) update showcase message is present")
            expect(!strings.updateShowcaseUnavailable.isEmpty, "\(prefix) update showcase fallback is present")
            expect(!strings.updateShowcaseRestart.isEmpty, "\(prefix) update showcase restart control is present")
            expect(!strings.homebrewConfirmUpgradeAllTitle.isEmpty, "\(prefix) Homebrew update all confirmation title is present")
            expect(!strings.homebrewConfirmUpgradeAllBody.isEmpty, "\(prefix) Homebrew update all confirmation body is present")
            expect(!strings.homebrewConfirmUpdateHomebrewTitle.isEmpty, "\(prefix) Homebrew update Homebrew confirmation title is present")
            expect(!strings.homebrewConfirmUpdateHomebrewBody.isEmpty, "\(prefix) Homebrew update Homebrew confirmation body is present")
            expectFormat(strings.homebrewPopularityFormat, ["@", "@"], "\(prefix) Homebrew popularity format")
            expectFormat(strings.homebrewOperationInstallFormat, ["@"], "\(prefix) Homebrew operation install format")
            expectFormat(strings.homebrewOperationUninstallFormat, ["@"], "\(prefix) Homebrew operation uninstall format")
            expectFormat(strings.homebrewOperationUpgradeFormat, ["@"], "\(prefix) Homebrew operation upgrade format")
            expect(!strings.homebrewOperationUpgradeAll.isEmpty, "\(prefix) Homebrew operation update all is present")
            expect(!strings.homebrewOperationUpdateHomebrew.isEmpty, "\(prefix) Homebrew operation update Homebrew is present")
            expectFormat(strings.homebrewOperationInstalledFormat, ["@"], "\(prefix) Homebrew operation installed format")
            expectFormat(strings.homebrewOperationUninstalledFormat, ["@"], "\(prefix) Homebrew operation uninstalled format")
            expectFormat(strings.homebrewOperationUpgradedFormat, ["@"], "\(prefix) Homebrew operation upgraded format")
            expect(!strings.homebrewOperationUpgradedAll.isEmpty, "\(prefix) Homebrew operation updated all is present")
            expect(!strings.homebrewOperationUpdatedHomebrew.isEmpty, "\(prefix) Homebrew operation updated Homebrew is present")
            expectFormat(strings.homebrewOperationFailedFormat, ["@"], "\(prefix) Homebrew operation failed format")
            expectFormat(strings.homebrewOperationElapsedFormat, ["@"], "\(prefix) Homebrew operation elapsed format")

            let rendered = [
                String(format: strings.cutMovedPluralFormat, 2),
                String(format: strings.uninstallerSelectedFormat, 1, 3),
                String(format: strings.uninstallerFreedFormat, "1 MB"),
                String(format: strings.shelfSelectedFormat, 2),
                String(format: strings.powerAdapterMaxFormat, "30 W"),
                String(format: strings.mixerInputErrorFormat, "OSStatus -1"),
                String(format: strings.homebrewConfirmInstallBodyFormat, "jq"),
                String(format: strings.homebrewConfirmUninstallBodyFormat, "jq"),
                String(format: strings.homebrewPopularityFormat, "1,234", "30"),
                String(format: strings.homebrewOperationInstallFormat, "jq"),
                String(format: strings.homebrewOperationUninstallFormat, "jq"),
                String(format: strings.homebrewOperationInstalledFormat, "jq"),
                String(format: strings.homebrewOperationUninstalledFormat, "jq"),
                String(format: strings.homebrewOperationFailedFormat, "jq"),
                String(format: strings.homebrewOperationElapsedFormat, "10s"),
            ]
            for value in rendered {
                expect(!value.isEmpty && !value.contains("%"), "\(prefix) renders format strings")
            }
        }
    }

    static func runDeviceStrings(expect: (Bool, String) -> Void) {
        func expectFormat(_ format: String, _ expected: [String], _ label: String) {
            let actual = formatSpecifiers(in: format)
            expect(actual == expected, "\(label): got \(actual), expected \(expected)")
        }

        expect(BluetoothSleepSupport.sleepPlan(isPoweredOn: true, restoresOnWake: true)
                == BluetoothSleepSupport.SleepPlan(powersOff: true, owesRestore: true),
               "Bluetooth on before sleep is switched off and owed back")
        expect(BluetoothSleepSupport.sleepPlan(isPoweredOn: true, restoresOnWake: false)
                == BluetoothSleepSupport.SleepPlan(powersOff: true, owesRestore: false),
               "without the restore option, sleep switches Bluetooth off for good")
        expect(BluetoothSleepSupport.sleepPlan(isPoweredOn: false, restoresOnWake: true)
                == BluetoothSleepSupport.SleepPlan(powersOff: false, owesRestore: false),
               "Bluetooth already off before sleep is left alone, so the wake never turns it on")
        expect(BluetoothSleepSupport.restores(owesRestore: true, isPoweredOn: false),
               "a wake that still owes a restore switches Bluetooth back on")
        expect(!BluetoothSleepSupport.restores(owesRestore: false, isPoweredOn: false),
               "a wake owing nothing leaves Bluetooth off")
        expect(!BluetoothSleepSupport.restores(owesRestore: true, isPoweredOn: true),
               "Bluetooth the user switched on first is left alone")

        for language in AppLanguage.allCases {
            let strings = FeatureStrings.bluetoothSleep(language)
            let values = Mirror(reflecting: strings).children.compactMap { $0.value as? String }
            expect(values.count == 7 && values.allSatisfy { !$0.isEmpty },
                   "Bluetooth on sleep has every localized field for \(language.rawValue)")
            expect(values.allSatisfy { !$0.contains("—") },
                   "Bluetooth on sleep text uses human punctuation for \(language.rawValue)")
        }
        expect((Defaults.registeredDefaults[DefaultsKey.panelShowFanControl] as? Bool) == true,
               "installing fan control reveals its panel section by default")

        for language in AppLanguage.allCases {
            let strings = FeatureStrings.diskImageInstaller(language)
            let values = Mirror(reflecting: strings).children.compactMap { $0.value as? String }
            expect(values.count == 17 && values.allSatisfy { !$0.isEmpty },
                   "disk image installer has every localized field for \(language.rawValue)")
            expect(values.allSatisfy { !$0.contains("—") },
                   "disk image installer text uses human punctuation for \(language.rawValue)")
            expectFormat(strings.promptBodyFormat, ["@"],
                         "\(language.rawValue) installer prompt format")
            expectFormat(strings.installedBodyFormat, ["@"],
                         "\(language.rawValue) installer success format")
            expectFormat(strings.installedKeepingMountBodyFormat, ["@"],
                         "\(language.rawValue) installer mounted-image format")
            expectFormat(strings.installedKeepingDownloadBodyFormat, ["@"],
                         "\(language.rawValue) installer kept-download format")
            expectFormat(strings.alreadyInstalledBodyFormat, ["@"],
                         "\(language.rawValue) installer existing-app format")
            expectFormat(strings.installedKeptDownloadBodyFormat, ["@"],
                         "\(language.rawValue) installer kept-by-choice format")
            expectFormat(strings.installingFormat, ["@"],
                         "\(language.rawValue) installer progress format")
        }

        let installerInfo: [String: Any] = [
            "images": [[
                "image-path": "/Users/test/Downloads/App.dmg",
                "system-entities": [[
                    "dev-entry": "/dev/disk9s1",
                    "mount-point": "/private/tmp/Installer Mount",
                ]],
            ]],
        ]
        if let installerData = try? PropertyListSerialization.data(fromPropertyList: installerInfo,
                                                                    format: .xml,
                                                                    options: 0) {
            expect(DiskImageInstallerSupport.imageURL(
                mountedAt: URL(fileURLWithPath: "/tmp/Installer Mount"),
                hdiutilInfo: installerData)?.path == "/Users/test/Downloads/App.dmg",
                "hdiutil plist maps the canonical mount path back to its disk image")
            expect(DiskImageInstallerSupport.imageURL(
                mountedAt: URL(fileURLWithPath: "/tmp/Other Mount"),
                hdiutilInfo: installerData) == nil,
                "an unrelated mounted volume is never treated as the disk image")
        } else {
            expect(false, "disk image installer plist fixture can be encoded")
        }
        expect(DiskImageInstallerSupport.destinationURL(
            for: URL(fileURLWithPath: "/Volumes/Installer/Example.app"),
            applicationsURL: URL(fileURLWithPath: "/Applications", isDirectory: true))?.path
            == "/Applications/Example.app",
            "a top-level app gets one fixed Applications destination")
        expect(DiskImageInstallerSupport.destinationURL(
            for: URL(fileURLWithPath: "/Volumes/Installer/.Hidden.app"),
            applicationsURL: URL(fileURLWithPath: "/Applications", isDirectory: true)) == nil,
            "hidden app bundles cannot create hidden Applications entries")
        expect(DiskImageInstallerSupport.displayName(
            preferred: "  Example\nApp\u{0007}  ",
            appURL: URL(fileURLWithPath: "/Volumes/Installer/Fallback.app")) == "Example App",
            "untrusted bundle names are flattened before entering an alert")
    }

    static func runFeatureStrings(expect: (Bool, String) -> Void) {
        func expectFormat(_ format: String, _ expected: [String], _ label: String) {
            let actual = formatSpecifiers(in: format)
            expect(actual == expected, "\(label): got \(actual), expected \(expected)")
        }

        // MARK: Features hub strings

        for language in AppLanguage.allCases {
            let hub = FeatureStrings.hub(language)
            let values = Mirror(reflecting: hub).children.compactMap { $0.value as? String }
            expect(!values.isEmpty && values.allSatisfy { !$0.isEmpty },
                   "every hub string is set for \(language.rawValue)")
            expect(values.allSatisfy { !$0.contains("—") },
                   "no em-dash in visible hub strings (\(language.rawValue))")
            expect(hub.activeCountFormat.contains("%1$d") && hub.activeCountFormat.contains("%2$d"),
                   "count format keeps positional specifiers (\(language.rawValue))")
        }
        for language in AppLanguage.allCases {
            let clipboard = FeatureStrings.clipboard(language)
            let values = Mirror(reflecting: clipboard).children
                .compactMap { $0.value as? String }
            expect(values.count == 54 && values.allSatisfy { !$0.isEmpty },
                   "every clipboard string is set for \(language.rawValue)")
            expect(values.allSatisfy { !$0.contains("—") },
                   "no em-dash in visible clipboard strings (\(language.rawValue))")
            expectFormat(clipboard.deleteSelectedFormat, ["d"],
                         "\(language.rawValue) clipboard bulk-delete format")
        }
        for language in AppLanguage.allCases {
            let values = Mirror(reflecting: FeatureStrings.mouseButtons(language)).children
                .compactMap { $0.value as? String }
            expect(values.count == 32 && values.allSatisfy { !$0.isEmpty },
                   "every mouse button string is set for \(language.rawValue)")
            expect(values.allSatisfy { !$0.contains("—") },
                   "no em-dash in visible mouse button strings (\(language.rawValue))")
        }
        expect(FeatureStrings.hub(.ptBR).pageTitle == "Recursos"
                && FeatureStrings.hub(.enUS).pageTitle == "Features",
               "hub page title reads naturally in the owner languages")
        for language in AppLanguage.allCases {
            let snippetValues = Mirror(reflecting: FeatureStrings.snippets(language)).children
                .compactMap { $0.value as? String }
            expect(!snippetValues.isEmpty && snippetValues.allSatisfy { !$0.isEmpty },
                   "every snippet string is set for \(language.rawValue)")
            expect(snippetValues.allSatisfy { !$0.contains("—") },
                   "no em-dash in visible snippet strings (\(language.rawValue))")
            let backupValues = Mirror(reflecting: FeatureStrings.backup(language)).children
                .compactMap { $0.value as? String }
            expect(!backupValues.isEmpty && backupValues.allSatisfy { !$0.isEmpty },
                   "every backup string is set for \(language.rawValue)")
            expect(backupValues.allSatisfy { !$0.contains("—") },
                   "no em-dash in visible backup strings (\(language.rawValue))")
            let mixerValues = Mirror(reflecting: FeatureStrings.mixer(language)).children
                .compactMap { $0.value as? String }
            expect(!mixerValues.isEmpty && mixerValues.allSatisfy { !$0.isEmpty },
                   "every mixer feature string is set for \(language.rawValue)")
            expect(FeatureStrings.backup(language).description.contains(
                FeatureStrings.scratchpad(language).pageTitle),
                   "every backup description accounts for the Scratchpad text (\(language.rawValue))")
            let guideValues = Mirror(reflecting: FeatureStrings.permissionGuide(language)).children
                .compactMap { $0.value as? String }
            expect(!guideValues.isEmpty && guideValues.allSatisfy { !$0.isEmpty },
                   "every permission guide string is set for \(language.rawValue)")
            expect(guideValues.allSatisfy { !$0.contains("—") },
                   "no em-dash in permission guide strings (\(language.rawValue))")
            let brightnessValues = Mirror(reflecting: FeatureStrings.brightness(language)).children
                .compactMap { $0.value as? String }
            expect(!brightnessValues.isEmpty && brightnessValues.allSatisfy { !$0.isEmpty },
                   "every brightness string is set for \(language.rawValue)")
            expect(brightnessValues.allSatisfy { !$0.contains("—") },
                   "no em-dash in visible brightness strings (\(language.rawValue))")
            let quickToggleValues = Mirror(reflecting: FeatureStrings.quickToggles(language)).children
                .compactMap { $0.value as? String }
            expect(!quickToggleValues.isEmpty && quickToggleValues.allSatisfy { !$0.isEmpty },
                   "every quick toggle string is set for \(language.rawValue)")
            expect(quickToggleValues.allSatisfy { !$0.contains("—") },
                   "no em-dash in visible quick toggle strings (\(language.rawValue))")
            let keepAwakeAutomationValues = Mirror(
                reflecting: FeatureStrings.keepAwakeAutomation(language)
            ).children.compactMap { $0.value as? String }
            expect(!keepAwakeAutomationValues.isEmpty
                    && keepAwakeAutomationValues.allSatisfy { !$0.isEmpty },
                   "every Keep Awake automation string is set for \(language.rawValue)")
            expect(keepAwakeAutomationValues.allSatisfy { !$0.contains("—") },
                   "no em-dash in Keep Awake automation strings (\(language.rawValue))")
            let displaySleepValues = Mirror(
                reflecting: FeatureStrings.keepAwakeDisplaySleep(language)
            ).children.compactMap { $0.value as? String }
            expect(displaySleepValues.count == 2 && displaySleepValues.allSatisfy { !$0.isEmpty },
                   "every Keep Awake display sleep string is set for \(language.rawValue)")
            expect(displaySleepValues.allSatisfy { !$0.contains("—") },
                   "no em-dash in Keep Awake display sleep strings (\(language.rawValue))")
            let batteryTimeValues = Mirror(reflecting: FeatureStrings.batteryTime(language)).children
                .compactMap { $0.value as? String }
            expect(!batteryTimeValues.isEmpty && batteryTimeValues.allSatisfy { !$0.isEmpty },
                   "every battery time string is set for \(language.rawValue)")
            expect(batteryTimeValues.allSatisfy { !$0.contains("—") },
                   "no em-dash in visible battery time strings (\(language.rawValue))")
            let menuBarAppearanceValues = Mirror(reflecting: FeatureStrings.menuBarAppearance(language)).children
                .compactMap { $0.value as? String }
            expect(!menuBarAppearanceValues.isEmpty && menuBarAppearanceValues.allSatisfy { !$0.isEmpty },
                   "every menu bar appearance string is set for \(language.rawValue)")
            expect(menuBarAppearanceValues.allSatisfy { !$0.contains("—") },
                   "no em-dash in visible menu bar appearance strings (\(language.rawValue))")
            let appUpdateValues = Mirror(reflecting: FeatureStrings.appUpdates(language)).children
                .compactMap { $0.value as? String }
            expect(appUpdateValues.count == 40 && appUpdateValues.allSatisfy { !$0.isEmpty },
                   "every app update string is set for \(language.rawValue)")
            expect(appUpdateValues.allSatisfy { !$0.contains("—") },
                   "no em-dash in visible app update strings (\(language.rawValue))")
            expect(FeatureStrings.appUpdates(language).updateSelectedFormat.contains("%d")
                    && FeatureStrings.appUpdates(language).lastCheckFormat.contains("%@")
                    && FeatureStrings.appUpdates(language).nextCheckFormat.contains("%@")
                    && FeatureStrings.appUpdates(language).notificationBodyFormat.contains("%@"),
                   "app update formats keep their placeholders (\(language.rawValue))")
            expect(!FeatureStrings.appUpdates(language).notificationBodyOne.contains("%"),
                   "the single-app note carries no placeholder (\(language.rawValue))")
            let killProcessValues = Mirror(reflecting: FeatureStrings.killProcess(language)).children
                .compactMap { $0.value as? String }
            expect(killProcessValues.count == 30 && killProcessValues.allSatisfy { !$0.isEmpty },
                   "every kill process string is set for \(language.rawValue)")
            expect(killProcessValues.allSatisfy { !$0.contains("—") },
                   "no em-dash in visible kill process strings (\(language.rawValue))")
            expect(FeatureStrings.killProcess(language).pidLabelFormat.contains("%d")
                    && FeatureStrings.killProcess(language).processCountFormat.contains("%d")
                    && FeatureStrings.killProcess(language).killAllFormat.contains("%@")
                    && FeatureStrings.killProcess(language).confirmKillFormat.contains("%@")
                    && FeatureStrings.killProcess(language).confirmForceKillFormat.contains("%@")
                    && FeatureStrings.killProcess(language).confirmKillAllFormat.contains("%@")
                    && FeatureStrings.killProcess(language).confirmKillTreeFormat.contains("%@")
                    && FeatureStrings.killProcess(language).adminPromptFormat.contains("%@"),
                   "kill process formats keep their placeholders (\(language.rawValue))")
        }
    }
}
