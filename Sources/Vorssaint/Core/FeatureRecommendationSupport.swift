// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

enum FeatureCatalogLayout: String, CaseIterable, Identifiable {
    case cards
    case list

    var id: Self { self }
    var title: String { self == .cards ? "Cards" : "List" }
    var symbolName: String { self == .cards ? "square.grid.2x2" : "list.bullet" }
}

enum FeatureCatalogStatusFilter: String, CaseIterable, Identifiable {
    case all
    case installed
    case notInstalled
    case enabled

    var id: Self { self }
    var title: String {
        switch self {
        case .all: "All features"
        case .installed: "Installed"
        case .notInstalled: "Not installed"
        case .enabled: "Enabled"
        }
    }
}

enum FeatureCatalogSortOrder: String, CaseIterable, Identifiable {
    case defaultOrder
    case name
    case installedFirst

    var id: Self { self }
    var title: String {
        switch self {
        case .defaultOrder: "Recommended order"
        case .name: "Name"
        case .installedFirst: "Installed first"
        }
    }
}

enum FeatureCatalogQuery {
    static func filter(_ features: [AppFeature],
                       text query: String,
                       category: FeatureGroup?,
                       status: FeatureCatalogStatusFilter,
                       searchTerms: (AppFeature) -> String,
                       isInstalled: (AppFeature) -> Bool,
                       isEnabled: (AppFeature) -> Bool) -> [AppFeature] {
        let normalizedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
        return features.filter { feature in
            guard category == nil || feature.group == category else { return false }
            switch status {
            case .all: break
            case .installed where !isInstalled(feature): return false
            case .notInstalled where isInstalled(feature): return false
            case .enabled where !isEnabled(feature): return false
            default: break
            }
            guard !normalizedQuery.isEmpty else { return true }
            let terms = searchTerms(feature)
                .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            return terms.localizedStandardContains(normalizedQuery)
        }
    }

    static func sort(_ features: [AppFeature],
                     by order: FeatureCatalogSortOrder,
                     isInstalled: (AppFeature) -> Bool,
                     title: (AppFeature) -> String) -> [AppFeature] {
        switch order {
        case .defaultOrder:
            return features
        case .name:
            return features.sorted {
                title($0).localizedStandardCompare(title($1)) == .orderedAscending
            }
        case .installedFirst:
            return features.sorted {
                if isInstalled($0) != isInstalled($1) { return isInstalled($0) }
                return title($0).localizedStandardCompare(title($1)) == .orderedAscending
            }
        }
    }
}

enum FeatureSurveyActivity: String, CaseIterable, Identifiable {
    case browsingAndPeople
    case photosAndCreative
    case musicVideoAndGames
    case personalPlanning
    case movingBetweenApps
    case makingOrSharingCaptures
    case workOrStudy
    case softwareDevelopment
    case everydayMix

    var id: Self { self }

    var symbolName: String {
        switch self {
        case .browsingAndPeople: "bubble.left.and.bubble.right"
        case .photosAndCreative: "scribble.variable"
        case .musicVideoAndGames: "play.rectangle"
        case .personalPlanning: "note.text"
        case .movingBetweenApps: "rectangle.on.rectangle"
        case .makingOrSharingCaptures: "camera.viewfinder"
        case .workOrStudy: "book.closed"
        case .softwareDevelopment: "chevron.left.forwardslash.chevron.right"
        case .everydayMix: "sparkles"
        }
    }

    var features: Set<AppFeature> {
        switch self {
        case .browsingAndPeople:
            [.clipboardHistory, .quickLauncher, .commandBar, .notchNotifications]
        case .photosAndCreative:
            [.screenshot, .screenRecorder, .screenOCR, .colorPicker, .mediaTools]
        case .musicVideoAndGames:
            [.mixer, .soundOutputSwitcher, .notch, .notchLyrics, .notchTimer]
        case .personalPlanning:
            [.scratchpad, .clipboardHistory, .shelf, .finderRename, .notchCalendar]
        case .movingBetweenApps:
            [.switcher, .dockPreview, .dockClick, .windowLayout, .quickLauncher]
        case .makingOrSharingCaptures:
            [.screenshot, .screenRecorder, .screenOCR, .shelf]
        case .workOrStudy:
            [.clipboardHistory, .textSnippets, .screenOCR, .shelf, .commandBar]
        case .softwareDevelopment:
            [.commandBar, .clipboardHistory, .textSnippets, .windowLayout, .switcher, .quickLauncher]
        case .everydayMix:
            FeaturePreset.essential.features
        }
    }

    var detailChoices: [FeatureSurveyDetailChoice] {
        switch self {
        case .browsingAndPeople:
            [
                .init(id: "web-links", symbol: "link",
                      features: [.clipboardHistory, .shelf]),
                .init(id: "messages", symbol: "rectangle.on.rectangle",
                      features: [.switcher, .dockPreview, .quickLauncher]),
                .init(id: "notifications", symbol: "bell",
                      features: [.notchNotifications, .notch])
            ]
        case .photosAndCreative:
            [
                .init(id: "photo-capture", symbol: "camera.viewfinder",
                      features: [.screenshot, .screenRecorder]),
                .init(id: "photo-text", symbol: "text.viewfinder",
                      features: [.screenOCR, .clipboardHistory]),
                .init(id: "creative-tools", symbol: "eyedropper",
                      features: [.colorPicker, .radialMenu])
            ]
        case .musicVideoAndGames:
            [
                .init(id: "media-controls", symbol: "waveform",
                      features: [.mixer, .soundOutputSwitcher, .notchLyrics]),
                .init(id: "media-window", symbol: "macwindow",
                      features: [.windowLayout, .dockPreview]),
                .init(id: "media-timing", symbol: "timer",
                      features: [.notchTimer, .notch])
            ]
        case .personalPlanning:
            [
                .init(id: "quick-notes", symbol: "note.text",
                      features: [.scratchpad, .notchCalendar]),
                .init(id: "saved-items", symbol: "tray.full",
                      features: [.shelf, .clipboardHistory]),
                .init(id: "file-tidy", symbol: "folder",
                      features: [.finderRename, .finderCutPaste])
            ]
        case .movingBetweenApps:
            [
                .init(id: "switch-apps", symbol: "rectangle.on.rectangle",
                      features: [.switcher, .quickLauncher]),
                .init(id: "arrange-windows", symbol: "macwindow",
                      features: [.windowLayout, .windowMaximizer]),
                .init(id: "dock-apps", symbol: "dock.rectangle",
                      features: [.dockPreview, .dockClick])
            ]
        case .makingOrSharingCaptures:
            [
                .init(id: "capture-edit", symbol: "pencil.tip.crop.circle",
                      features: [.screenshot, .screenRecorder, .mediaTools]),
                .init(id: "capture-share", symbol: "square.and.arrow.up",
                      features: [.screenshot, .screenRecorder, .shelf]),
                .init(id: "capture-text", symbol: "text.viewfinder",
                      features: [.screenshot, .screenOCR, .clipboardHistory]),
                .init(id: "capture-organize", symbol: "folder",
                      features: [.screenshot, .screenRecorder, .shelf, .finderRename])
            ]
        case .workOrStudy:
            [
                .init(id: "work-research", symbol: "books.vertical",
                      features: [.shelf, .clipboardHistory, .finderRename]),
                .init(id: "work-documents", symbol: "doc.text",
                      features: [.textSnippets, .clipboardHistory, .pastePlain]),
                .init(id: "work-meetings", symbol: "rectangle.on.rectangle",
                      features: [.switcher, .windowLayout, .scratchpad])
            ]
        case .softwareDevelopment:
            [
                .init(id: "dev-copy", symbol: "doc.on.clipboard",
                      features: [.clipboardHistory, .pastePlain, .textSnippets]),
                .init(id: "dev-tools", symbol: "rectangle.on.rectangle",
                      features: [.switcher, .windowLayout, .quickLauncher]),
                .init(id: "dev-repeat", symbol: "command",
                      features: [.commandBar, .textSnippets, .radialMenu]),
                .init(id: "dev-inspect", symbol: "text.viewfinder",
                      features: [.screenOCR, .shelf])
            ]
        case .everydayMix:
            []
        }
    }
}

enum FeatureSurveyAppCategory: String, CaseIterable, Identifiable {
    case webAndMessaging
    case photosAndVideo
    case musicAndMedia
    case games
    case notesAndDocuments
    case creativeTools
    case developmentAndLearning

    var id: Self { self }

    var features: Set<AppFeature> {
        switch self {
        case .webAndMessaging:
            [.clipboardHistory, .quickLauncher, .commandBar, .notchNotifications]
        case .photosAndVideo:
            [.screenshot, .screenRecorder, .screenOCR, .mediaTools]
        case .musicAndMedia:
            [.mixer, .notchLyrics, .soundOutputSwitcher, .audioPriority]
        case .games:
            [.mixer, .dockPreview, .windowLayout, .notch]
        case .notesAndDocuments:
            [.clipboardHistory, .scratchpad, .shelf, .finderRename, .textSnippets]
        case .creativeTools:
            [.colorPicker, .screenshot, .screenRecorder, .mediaTools, .radialMenu]
        case .developmentAndLearning:
            [.commandBar, .textSnippets, .clipboardHistory, .screenOCR, .shelf]
        }
    }

    var detailChoices: [FeatureSurveyDetailChoice] {
        switch self {
        case .webAndMessaging: FeatureSurveyActivity.browsingAndPeople.detailChoices
        case .photosAndVideo: FeatureSurveyActivity.makingOrSharingCaptures.detailChoices
        case .musicAndMedia: FeatureSurveyActivity.musicVideoAndGames.detailChoices
        case .games: FeatureSurveyActivity.movingBetweenApps.detailChoices
        case .notesAndDocuments: FeatureSurveyActivity.personalPlanning.detailChoices
        case .creativeTools: FeatureSurveyActivity.photosAndCreative.detailChoices
        case .developmentAndLearning: FeatureSurveyActivity.softwareDevelopment.detailChoices
        }
    }
}

struct FeatureSurveyDetailChoice: Identifiable, Hashable {
    let id: String
    let symbol: String
    let features: Set<AppFeature>
}

enum FeatureSurveyTopic: Hashable {
    case activity(FeatureSurveyActivity)
    case appCategory(FeatureSurveyAppCategory)

    func title(_ strings: FeatureRecommendationStrings) -> String {
        switch self {
        case .activity(let activity): strings.activityTitle(activity)
        case .appCategory(let category): strings.categoryTitle(category)
        }
    }

    var detailChoices: [FeatureSurveyDetailChoice] {
        switch self {
        case .activity(let activity): activity.detailChoices
        case .appCategory(let category): category.detailChoices
        }
    }
}

enum FeatureSurveyRoutine: String, CaseIterable, Identifiable {
    case switchBetweenApps
    case copyAndReuseThings
    case saveAndFindThings
    case captureScreen
    case repeatSteps
    case focusOnOneApp
    case useAccessories

    var id: Self { self }

    var features: Set<AppFeature> {
        switch self {
        case .switchBetweenApps:
            [.switcher, .dockPreview, .windowLayout, .quickLauncher]
        case .copyAndReuseThings:
            [.clipboardHistory, .pastePlain, .textSnippets, .shelf]
        case .saveAndFindThings:
            [.shelf, .finderRename, .finderCutPaste, .clipboardHistory]
        case .captureScreen:
            [.screenshot, .screenRecorder, .screenOCR, .shelf]
        case .repeatSteps:
            [.commandBar, .textSnippets, .radialMenu, .quickLauncher]
        case .focusOnOneApp:
            [.quitWindowProtection, .keepAwake, .notchTimer, .mediaTools]
        case .useAccessories:
            [.connectedDevices, .notchAccessories, .bluetoothSleep]
        }
    }
}

enum FeatureSurveyCaptureNextStep: String, CaseIterable, Identifiable {
    case edit
    case share
    case organize
    case findText
    case view

    var id: Self { self }

    var features: Set<AppFeature> {
        switch self {
        case .edit: [.screenshot, .screenRecorder, .screenOCR]
        case .share: [.screenshot, .screenRecorder, .shelf, .clipboardHistory]
        case .organize: [.screenshot, .screenRecorder, .shelf, .finderRename]
        case .findText: [.screenshot, .screenOCR, .clipboardHistory]
        case .view: [.screenshot, .screenRecorder, .shelf]
        }
    }
}

enum FeatureSurveyQuestion: Int, CaseIterable, Identifiable {
    case activities
    case appCategories
    case routines
    case captureNextStep
    case flashcards
    case review

    var id: Self { self }
}

enum FeatureSurveyStep: Hashable {
    case question(FeatureSurveyQuestion)
    case topic(FeatureSurveyTopic)
}

struct FeatureRecommendationAnswers: Equatable {
    var activities = Set<FeatureSurveyActivity>()
    var activityPriority: [FeatureSurveyActivity] = []
    var appCategories = Set<FeatureSurveyAppCategory>()
    var appCategoryPriority: [FeatureSurveyAppCategory] = []
    var routines = Set<FeatureSurveyRoutine>()
    var routinePriority: [FeatureSurveyRoutine] = []
    var captureNextStep: FeatureSurveyCaptureNextStep?
    var selectedTasks: [FeatureSurveyTopic: Set<String>] = [:]
}

enum FeatureSurveyFlow {
    static func steps(for answers: FeatureRecommendationAnswers) -> [FeatureSurveyStep] {
        var steps: [FeatureSurveyStep] = [.question(.activities)]
        for activity in orderedActivities(in: answers) {
            steps.append(.topic(.activity(activity)))
        }
        let essentialsOnly = answers.activities == [.everydayMix]
        if !essentialsOnly {
            steps.append(.question(.appCategories))
            steps.append(.question(.routines))
        }
        if shouldAskCaptureFollowUp(answers) {
            steps.append(.question(.captureNextStep))
        }
        steps += [.question(.flashcards), .question(.review)]
        return steps
    }

    static func questions(for answers: FeatureRecommendationAnswers) -> [FeatureSurveyQuestion] {
        steps(for: answers).compactMap { step in
            guard case .question(let question) = step else { return nil }
            return question
        }
    }

    private static func orderedActivities(in answers: FeatureRecommendationAnswers) -> [FeatureSurveyActivity] {
        let selected = answers.activities.subtracting([.everydayMix])
        let ordered = answers.activityPriority.filter(selected.contains)
        return ordered + FeatureSurveyActivity.allCases.filter {
            selected.contains($0) && !ordered.contains($0)
        }
    }

    static func shouldAskCaptureFollowUp(_ answers: FeatureRecommendationAnswers) -> Bool {
        answers.activities.contains(.makingOrSharingCaptures)
            || answers.activities.contains(.photosAndCreative)
            || answers.appCategories.contains(.photosAndVideo)
            || answers.routines.contains(.captureScreen)
    }

    static func next(after step: FeatureSurveyStep,
                     answers: FeatureRecommendationAnswers) -> FeatureSurveyQuestion? {
        guard case .question(let next)? = nextStep(after: step, answers: answers) else { return nil }
        return next
    }

    static func next(after question: FeatureSurveyQuestion,
                     answers: FeatureRecommendationAnswers) -> FeatureSurveyQuestion? {
        let questions = questions(for: answers)
        guard let index = questions.firstIndex(of: question), questions.indices.contains(index + 1) else {
            return nil
        }
        return questions[index + 1]
    }

    static func previous(before question: FeatureSurveyQuestion,
                         answers: FeatureRecommendationAnswers) -> FeatureSurveyQuestion? {
        let questions = questions(for: answers)
        guard let index = questions.firstIndex(of: question), index > 0 else { return nil }
        return questions[index - 1]
    }

    static func nextStep(after step: FeatureSurveyStep,
                         answers: FeatureRecommendationAnswers) -> FeatureSurveyStep? {
        let steps = steps(for: answers)
        guard let index = steps.firstIndex(of: step), steps.indices.contains(index + 1) else { return nil }
        return steps[index + 1]
    }

    static func previousStep(before step: FeatureSurveyStep,
                             answers: FeatureRecommendationAnswers) -> FeatureSurveyStep? {
        let steps = steps(for: answers)
        guard let index = steps.firstIndex(of: step), index > 0 else { return nil }
        return steps[index - 1]
    }

    static func nextQuestion(after step: FeatureSurveyStep,
                             answers: FeatureRecommendationAnswers) -> FeatureSurveyStep? {
        let steps = steps(for: answers)
        guard let index = steps.firstIndex(of: step) else { return nil }
        return steps.dropFirst(index + 1).first { next in
            if case .question = next { return true }
            return false
        }
    }

    static func hasRemainingDetails(after step: FeatureSurveyStep,
                                    answers: FeatureRecommendationAnswers) -> Bool {
        let steps = steps(for: answers)
        guard let index = steps.firstIndex(of: step),
              let next = steps.dropFirst(index + 1).first else { return false }
        if case .topic = next { return true }
        return false
    }
}

struct FeatureRecommendationContext {
    let installed: Set<AppFeature>
    let enabled: Set<AppFeature>
    let eligible: Set<AppFeature>
    let hasBattery: Bool
}

enum FeatureRecommendationEngine {
    static let minimumFeaturesPerActivity = 2
    static let maximumRecommendedAdditions = 10
    static let initiallyVisibleRecommendations = 3

    static func visibleRecommendations(from ranked: [AppFeature],
                                       expanded: Bool) -> [AppFeature] {
        let count = expanded ? ranked.count : min(initiallyVisibleRecommendations, ranked.count)
        return Array(ranked.prefix(count))
    }

    static func initialSelection(from ranked: [AppFeature]) -> Set<AppFeature> {
        Set(visibleRecommendations(from: ranked, expanded: false))
    }

    static func hiddenRecommendationCount(in ranked: [AppFeature]) -> Int {
        max(0, ranked.count - initiallyVisibleRecommendations)
    }

    static func selectionPreservingInstalled(_ selection: Set<AppFeature>,
                                             installed: Set<AppFeature>) -> Set<AppFeature> {
        selection.union(installed)
    }

    static var isBroadEnough: Bool {
        FeatureSurveyActivity.allCases.allSatisfy {
            $0.features.count >= minimumFeaturesPerActivity
        }
            && FeatureSurveyAppCategory.allCases.allSatisfy { $0.features.count >= minimumFeaturesPerActivity }
    }

    static func recommend(_ answers: FeatureRecommendationAnswers,
                          context: FeatureRecommendationContext) -> [AppFeature] {
        var scores: [AppFeature: Int] = [:]
        let activityOrder = answers.activityPriority.isEmpty
            ? FeatureSurveyActivity.allCases.filter(answers.activities.contains)
            : answers.activityPriority.filter(answers.activities.contains)
        for (index, activity) in activityOrder.enumerated() {
            for feature in activity.features {
                scores[feature, default: 0] += activity == .everydayMix ? 1 : max(6, 12 - index)
            }
        }
        let categoryOrder = answers.appCategoryPriority.isEmpty
            ? FeatureSurveyAppCategory.allCases.filter(answers.appCategories.contains)
            : answers.appCategoryPriority.filter(answers.appCategories.contains)
        for (index, category) in categoryOrder.enumerated() {
            for feature in category.features {
                scores[feature, default: 0] += max(4, 8 - index)
            }
        }
        let routineOrder = answers.routinePriority.isEmpty
            ? FeatureSurveyRoutine.allCases.filter(answers.routines.contains)
            : answers.routinePriority.filter(answers.routines.contains)
        for (index, routine) in routineOrder.enumerated() {
            for feature in routine.features {
                scores[feature, default: 0] += max(3, 7 - index)
            }
        }
        let selectedTopics = Set(answers.activities
            .filter { $0 != .everydayMix }
            .map(FeatureSurveyTopic.activity))
        for (topic, taskIDs) in answers.selectedTasks where selectedTopics.contains(topic) {
            for choice in topic.detailChoices where taskIDs.contains(choice.id) {
                for feature in choice.features {
                    scores[feature, default: 0] += 8
                }
            }
        }
        if let nextStep = answers.captureNextStep {
            for feature in nextStep.features {
                scores[feature, default: 0] += 6
            }
        }
        if answers.activities.isEmpty && answers.appCategories.isEmpty && answers.routines.isEmpty {
            for feature in FeaturePreset.essential.features {
                scores[feature, default: 0] += 1
            }
        }
        if !context.hasBattery {
            scores.removeValue(forKey: .bluetoothSleep)
        }

        let candidates = scores.keys.filter {
            context.eligible.contains($0) && !context.installed.contains($0)
        }
        let ranked = candidates.sorted { lhs, rhs in
            let leftScore = scores[lhs, default: 0] + (context.enabled.contains(lhs) ? 1 : 0)
            let rightScore = scores[rhs, default: 0] + (context.enabled.contains(rhs) ? 1 : 0)
            if leftScore != rightScore { return leftScore > rightScore }
            return lhs.rawValue < rhs.rawValue
        }
        return Array(ranked.prefix(maximumRecommendedAdditions))
    }
}
