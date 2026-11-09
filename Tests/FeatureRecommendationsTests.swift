// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

enum FeatureRecommendationsTests {
    static func run(_ suite: TestSuite) {
        suite.expect(FeatureRecommendationEngine.isBroadEnough
                     && FeatureSurveyActivity.allCases.allSatisfy {
                         $0.features.count >= FeatureRecommendationEngine.minimumFeaturesPerActivity
                     }
                     && FeatureSurveyAppCategory.allCases.allSatisfy {
                         $0.features.count >= FeatureRecommendationEngine.minimumFeaturesPerActivity
                     },
                     "the survey is available once every activity and app-use path maps to useful features")
        suite.expect(FeatureRecommendationStrings.localized(.enUS)
                        .activityTitle(.softwareDevelopment) == "Software development"
                     && FeatureSurveyActivity.softwareDevelopment.detailChoices.count >= 2
                     && FeatureSurveyActivity.allCases
                        .filter { $0 != .everydayMix }
                        .allSatisfy { $0.detailChoices.count >= 2 }
                     && FeatureSurveyAppCategory.allCases.allSatisfy { !$0.detailChoices.isEmpty },
                     "every activity and app category opens a follow-up page with actionable multi-select choices")

        for (language, _) in LocalizationTests.languages {
            let strings = FeatureRecommendationStrings.localized(language)
            let formatResults = [
                String(format: strings.text(.stepFormat), 3, 9),
                String(format: strings.text(.reviewCountFormat), 3, 9),
                String(format: strings.text(.suggestionCountFormat), 3, 9),
                String(format: strings.text(.workflowFormat), "Mac use", "a feature")
            ]
            suite.expect(strings.allUserVisibleCopy.allSatisfy {
                            !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                         }
                         && formatResults.allSatisfy { !$0.contains("%") }
                         && formatResults[0].contains("3") && formatResults[0].contains("9")
                         && formatResults[1].contains("3") && formatResults[1].contains("9")
                         && formatResults[2].contains("3") && formatResults[2].contains("9")
                         && formatResults[3].contains("Mac use") && formatResults[3].contains("a feature"),
                         "the complete recommendation survey catalog and format arguments are valid in \(language.rawValue)")
            let detailChoices = Set(FeatureSurveyActivity.allCases.flatMap(\.detailChoices)
                + FeatureSurveyAppCategory.allCases.flatMap(\.detailChoices))
            suite.expect(detailChoices.allSatisfy {
                            !strings.detailTitle($0).isEmpty
                         },
                         "every recommendation survey follow-up answer is localized in \(language.rawValue)")
        }

        let noCaptureAnswers = FeatureRecommendationAnswers(
            activities: [.browsingAndPeople],
            appCategories: [.webAndMessaging],
            routines: [.switchBetweenApps])
        suite.expect(FeatureSurveyFlow.questions(for: noCaptureAnswers)
                     == [.activities, .appCategories, .routines, .flashcards, .review],
                     "every question is presented as an individual step and irrelevant capture follow-ups are skipped")
        suite.expect(FeatureSurveyFlow.next(after: .activities, answers: noCaptureAnswers)
                     == .appCategories
                     && FeatureSurveyFlow.previous(before: .routines, answers: noCaptureAnswers)
                        == .appCategories,
                     "the survey supports linear back and continue navigation")
        let multiActivityAnswers = FeatureRecommendationAnswers(
            activities: [.softwareDevelopment, .photosAndCreative],
            activityPriority: [.softwareDevelopment, .photosAndCreative],
            appCategories: [.developmentAndLearning, .photosAndVideo],
            appCategoryPriority: [.developmentAndLearning, .photosAndVideo],
            selectedTasks: [.activity(.softwareDevelopment): ["dev-repeat"]])
        suite.expect(FeatureSurveyFlow.steps(for: multiActivityAnswers) == [
            .question(.activities),
            .topic(.activity(.softwareDevelopment)),
            .topic(.activity(.photosAndCreative)),
            .question(.appCategories),
            .topic(.appCategory(.developmentAndLearning)),
            .topic(.appCategory(.photosAndVideo)),
            .question(.routines),
            .question(.captureNextStep),
            .question(.flashcards),
            .question(.review),
        ], "each selected activity and app category gets a sequential detail step in selection order")
        suite.expect(FeatureSurveyFlow.nextStep(after: .question(.activities), answers: multiActivityAnswers)
                        == .topic(.activity(.softwareDevelopment))
                     && FeatureSurveyFlow.nextStep(
                        after: .topic(.activity(.softwareDevelopment)), answers: multiActivityAnswers)
                        == .topic(.activity(.photosAndCreative))
                     && FeatureSurveyFlow.previousStep(
                        before: .topic(.activity(.photosAndCreative)), answers: multiActivityAnswers)
                        == .topic(.activity(.softwareDevelopment)),
                     "survey navigation advances and reverses through selected detail pages one at a time")
        var deselectedPathAnswers = multiActivityAnswers
        deselectedPathAnswers.activities.remove(.softwareDevelopment)
        deselectedPathAnswers.activityPriority.removeAll { $0 == .softwareDevelopment }
        let deselectedPathRecommendation = FeatureRecommendationEngine.recommend(
            deselectedPathAnswers,
            context: FeatureRecommendationContext(installed: [], enabled: [],
                                                  eligible: Set(AppFeature.allCases), hasBattery: true))
        suite.expect(!FeatureSurveyFlow.steps(for: deselectedPathAnswers)
                        .contains(.topic(.activity(.softwareDevelopment)))
                     && !deselectedPathRecommendation.contains(.radialMenu),
                     "deselecting a path removes its detail page and stale task answers stop affecting recommendations")
        let surveySource = (try? String(
            contentsOfFile: "Sources/Vorssaint/UI/Settings/FeatureRecommendationSurvey.swift",
            encoding: .utf8)) ?? ""
        let hardCodedSurveyCopy = (try? NSRegularExpression(
            pattern: #"(?:Text|Button|Label|ContentUnavailableView)\("[^\\]"#))?
            .firstMatch(in: surveySource,
                        range: NSRange(surveySource.startIndex..., in: surveySource)) != nil
        suite.expect(surveySource.contains("FeatureRecommendationStrings.localized(l10n.language)")
                     && !hardCodedSurveyCopy,
                     "all user-visible recommendation survey copy comes from the localized catalog")
        suite.expect(surveySource.contains("Button {\n            toggleChoice(option.id)")
                     && !surveySource.contains("openTopic(option.id)")
                     && !surveySource.contains("goForward()\n            }"),
                     "selecting a survey tile only updates its selection and never advances the page")
        suite.expect(surveySource.contains("@Environment(\\.accessibilityReduceMotion)")
                     && surveySource.contains("withAnimation(reduceMotion ? nil : .spring")
                     && surveySource.contains(".keyboardShortcut(.defaultAction)"),
                     "survey navigation supports Return and respects the system Reduce Motion preference")
        suite.expect(FeatureSurveyFlow.questions(
                        for: FeatureRecommendationAnswers(activities: [.everydayMix]))
                        == [.activities, .flashcards, .review],
                     "the everyday-mix path skips optional detail questions and offers essentials quickly")

        var captureAnswers = FeatureRecommendationAnswers(
            activities: [.photosAndCreative],
            appCategories: [.photosAndVideo],
            routines: [.captureScreen])
        suite.expect(FeatureSurveyFlow.shouldAskCaptureFollowUp(captureAnswers)
                     && FeatureSurveyFlow.questions(for: captureAnswers)
                        == [.activities, .appCategories, .routines, .captureNextStep, .flashcards, .review]
                     && FeatureSurveyFlow.next(after: .routines, answers: captureAnswers) == .captureNextStep
                     && FeatureSurveyFlow.previous(before: .flashcards, answers: captureAnswers) == .captureNextStep
                     && FeatureSurveyFlow.previous(before: .review, answers: captureAnswers) == .flashcards,
                     "capture-related follow-up is added only for relevant routines and flashcard review follows")
        captureAnswers.activities.remove(.photosAndCreative)
        captureAnswers.appCategories.remove(.photosAndVideo)
        captureAnswers.routines.remove(.captureScreen)
        suite.expect(!FeatureSurveyFlow.shouldAskCaptureFollowUp(captureAnswers)
                     && !FeatureSurveyFlow.questions(for: captureAnswers).contains(.captureNextStep),
                     "branching contracts again when the user changes answers that made a follow-up relevant")

        let allFeatures = Set(AppFeature.allCases)
        let context = FeatureRecommendationContext(
            installed: [],
            enabled: [],
            eligible: allFeatures,
            hasBattery: true)

        let balanced = Set(FeatureRecommendationEngine.recommend(
            FeatureRecommendationAnswers(activities: [.everydayMix]),
            context: context))
        suite.expect(balanced == FeaturePreset.essential.features,
                     "the broad everyday path returns a balanced Essentials starter bundle")

        let captureRecommendation = FeatureRecommendationEngine.recommend(
            FeatureRecommendationAnswers(activities: [.makingOrSharingCaptures],
                                         appCategories: [.photosAndVideo],
                                         routines: [.captureScreen],
                                         captureNextStep: .findText),
            context: context)
        suite.expect(captureRecommendation.first == .screenOCR
                     && captureRecommendation.contains(.screenshot)
                     && captureRecommendation.contains(.screenRecorder)
                     && captureRecommendation.count <= FeatureRecommendationEngine.maximumRecommendedAdditions,
                     "task-specific capture answers rank text extraction and related tools by usefulness")

        let initiallyVisible = FeatureRecommendationEngine.visibleRecommendations(
            from: captureRecommendation, expanded: false)
        let expandedResults = FeatureRecommendationEngine.visibleRecommendations(
            from: captureRecommendation, expanded: true)
        let initiallySelected = FeatureRecommendationEngine.initialSelection(from: captureRecommendation)
        suite.expect(initiallyVisible.count == FeatureRecommendationEngine.initiallyVisibleRecommendations
                     && expandedResults == captureRecommendation
                     && initiallySelected == Set(initiallyVisible)
                     && initiallySelected.count < captureRecommendation.count
                     && FeatureRecommendationEngine.hiddenRecommendationCount(in: captureRecommendation)
                        == captureRecommendation.count - initiallyVisible.count,
                     "ranked recommendations remain capped and the engine exposes a small starter selection")

        let noBatteryContext = FeatureRecommendationContext(
            installed: [],
            enabled: [],
            eligible: allFeatures,
            hasBattery: false)
        let batteryRecommendation = Set(FeatureRecommendationEngine.recommend(
            FeatureRecommendationAnswers(routines: [.useAccessories]),
            context: noBatteryContext))
        suite.expect(!batteryRecommendation.contains(.bluetoothSleep),
                     "battery-specific accessory recommendations are omitted when no internal battery is detected")

        let retainedContext = FeatureRecommendationContext(
            installed: [.dockPreview],
            enabled: [.dockPreview],
            eligible: allFeatures.subtracting([.finderRename]),
            hasBattery: true)
        let retainedRecommendation = Set(FeatureRecommendationEngine.recommend(
            FeatureRecommendationAnswers(activities: [.musicVideoAndGames]),
            context: retainedContext))
        let appliedRetainedRecommendation = FeatureRecommendationEngine.selectionPreservingInstalled(
            retainedRecommendation, installed: retainedContext.installed)
        suite.expect(!retainedRecommendation.contains(.dockPreview)
                     && appliedRetainedRecommendation.contains(.dockPreview)
                     && !appliedRetainedRecommendation.contains(.finderRename),
                     "results stay focused on new suggestions while applying them preserves installed features")

        let routineRecommendation = FeatureRecommendationEngine.recommend(
            FeatureRecommendationAnswers(routines: [.copyAndReuseThings]),
            context: context)
        let clipboardRank = routineRecommendation.firstIndex(of: .clipboardHistory) ?? .max
        let pasteRank = routineRecommendation.firstIndex(of: .pastePlain) ?? .max
        suite.expect(routineRecommendation.first == .clipboardHistory
                     && clipboardRank < pasteRank,
                     "recommendations are ordered by answer relevance rather than alphabetically")
        let developmentRecommendation = FeatureRecommendationEngine.recommend(
            FeatureRecommendationAnswers(
                activities: [.softwareDevelopment],
                appCategories: [.developmentAndLearning],
                selectedTasks: [.activity(.softwareDevelopment): ["dev-repeat"]]),
            context: context)
        suite.expect(developmentRecommendation.first == .commandBar
                     && developmentRecommendation.contains(.textSnippets)
                     && developmentRecommendation.contains(.clipboardHistory),
                     "software development and chosen coding tasks rank relevant developer workflows")
        let taskPathsRecommendation = FeatureRecommendationEngine.recommend(
            FeatureRecommendationAnswers(
                activities: [.softwareDevelopment],
                appCategories: [.notesAndDocuments],
                selectedTasks: [
                    .activity(.softwareDevelopment): ["dev-repeat"],
                        .appCategory(.notesAndDocuments): ["quick-notes"]
                ]),
            context: FeatureRecommendationContext(installed: [], enabled: [],
                                                  eligible: [.commandBar, .scratchpad, .notchCalendar],
                                                  hasBattery: true))
        suite.expect(taskPathsRecommendation.first == .commandBar
                         && taskPathsRecommendation.contains(.scratchpad)
                         && taskPathsRecommendation.contains(.notchCalendar),
                     "multi-select tasks across separate activity and app pages all contribute to ranking")
        let developmentFirst = FeatureRecommendationEngine.recommend(
            FeatureRecommendationAnswers(
                activities: [.softwareDevelopment, .photosAndCreative],
                activityPriority: [.softwareDevelopment, .photosAndCreative]),
            context: context)
        let photosFirst = FeatureRecommendationEngine.recommend(
            FeatureRecommendationAnswers(
                activities: [.softwareDevelopment, .photosAndCreative],
                activityPriority: [.photosAndCreative, .softwareDevelopment]),
            context: context)
        suite.expect((developmentFirst.firstIndex(of: .commandBar) ?? .max)
                        < (developmentFirst.firstIndex(of: .screenshot) ?? .max)
                     && (photosFirst.firstIndex(of: .screenshot) ?? .max)
                        < (photosFirst.firstIndex(of: .commandBar) ?? .max),
                     "the user's activity priority order changes the recommendation ranking")

        let queryFeatures: [AppFeature] = [.switcher, .dockPreview, .brightness]
        let installed: Set<AppFeature> = [.dockPreview]
        let search = FeatureCatalogQuery.filter(
            queryFeatures,
            text: "PREVIEW",
            category: .windowsDock,
            status: .installed,
            searchTerms: { "\($0.rawValue) dock previews" },
            isInstalled: { installed.contains($0) },
            isEnabled: { $0 == .dockPreview })
        suite.expect(search == [.dockPreview],
                     "catalog search composes case-insensitively with category and install-status filters")
        let enabled = FeatureCatalogQuery.filter(
            queryFeatures,
            text: "",
            category: nil,
            status: .enabled,
            searchTerms: { $0.rawValue },
            isInstalled: { installed.contains($0) },
            isEnabled: { $0 == .dockPreview })
        suite.expect(enabled == [.dockPreview],
                     "the enabled filter returns active features only")
        let alphabetical = FeatureCatalogQuery.sort(
            queryFeatures,
            by: .name,
            isInstalled: { installed.contains($0) },
            title: { $0 == .brightness ? "A" : ($0 == .switcher ? "B" : "C") })
        suite.expect(alphabetical == [.brightness, .switcher, .dockPreview],
                     "name sort uses localized display-title ordering")
        let installedFirst = FeatureCatalogQuery.sort(
            queryFeatures,
            by: .installedFirst,
            isInstalled: { installed.contains($0) },
            title: { $0.rawValue })
        suite.expect(installedFirst.first == .dockPreview,
                     "installed-first sort preserves a useful install-state grouping")
    }
}
