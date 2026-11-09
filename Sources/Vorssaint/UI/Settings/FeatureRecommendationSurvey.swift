// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import SwiftUI

extension FeatureRecommendationContext {
    static func current() -> FeatureRecommendationContext {
        let defaults = UserDefaults.standard
        let installed = Set(AppFeature.allCases.filter(\.isAvailable))
        var enabled = Set(AppFeature.allCases.filter { feature in
            feature.enabledKeys.contains { defaults.bool(forKey: $0) }
        })
        if KeepAwakeManager.shared.isActive { enabled.insert(.keepAwake) }
        return FeatureRecommendationContext(
            installed: installed,
            enabled: enabled,
            eligible: Set(AppFeature.allCases.filter { $0.installBlockedReason == nil }),
            hasBattery: PowerSampler.hasInternalBattery)
    }
}

struct FeatureRecommendationSurvey: View {
    @ObservedObject private var l10n = L10n.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @FocusState private var surveyHasFocus: Bool
    @State private var question: FeatureSurveyQuestion = .activities
    @State private var detailTopic: FeatureSurveyTopic?
    @State private var answers = FeatureRecommendationAnswers()
    @State private var recommendationOrder: [AppFeature] = []
    @State private var proposedFeatures = Set<AppFeature>()
    @State private var installedFeatures = Set<AppFeature>()
    @State private var flashcardIndex = 0
    @State private var lastDecision: SurveyDecision?
    @State private var decisionCount = 0
    @State private var cardOffset: CGFloat = 0
    @State private var isAnimatingDecision = false

    let onExit: () -> Void
    let onApply: (Set<AppFeature>) -> Void

    private var hub: FeatureHubStrings { FeatureStrings.hub(l10n.language) }
    private var survey: FeatureRecommendationStrings {
        FeatureRecommendationStrings.localized(l10n.language)
    }
    private var stepAnimation: Animation? {
        reduceMotion ? nil : .easeInOut(duration: 0.18)
    }

    private var visibleSteps: [FeatureSurveyStep] {
        FeatureSurveyFlow.steps(for: answers)
    }
    private var currentStep: FeatureSurveyStep {
        if let detailTopic { return .topic(detailTopic) }
        return .question(question)
    }
    private var currentFlashcard: AppFeature? {
        recommendationOrder.indices.contains(flashcardIndex) ? recommendationOrder[flashcardIndex] : nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .center, spacing: 16) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(detailTopic?.title(survey)
                         ?? (question == .flashcards ? survey.text(.headerFlashcards) :
                             question == .review ? survey.text(.headerReview) : survey.text(.headerActivity)))
                        .font(.title3.weight(.semibold))
                    Text(question == .review
                         ? survey.text(.headerReviewSubtitle)
                         : question == .flashcards
                            ? survey.text(.headerFlashcardSubtitle)
                         : detailTopic == nil
                            ? survey.text(.headerQuestionSubtitle)
                            : survey.text(.headerDetailSubtitle))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button(action: onExit) {
                    Label(survey.text(.close), systemImage: "xmark")
                        .labelStyle(.titleAndIcon)
                        .font(.callout.weight(.medium))
                }
                .buttonStyle(.bordered)
                .keyboardShortcut(.cancelAction)
                .accessibilityLabel(survey.text(.closeAccessibility))
            }
            .padding(.bottom, 22)

            VStack(alignment: .leading, spacing: 7) {
                ProgressView(value: Double(questionIndex + 1),
                             total: Double(max(visibleSteps.count, 1)))
                    .tint(Color.accentColor)
                Text(String(format: survey.text(.stepFormat), questionIndex + 1, visibleSteps.count))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            .padding(.bottom, 18)

            ScrollView {
                Group {
                    if let detailTopic {
                        detailPage(detailTopic)
                            .transition(.opacity.combined(with: .move(edge: .trailing)))
                    } else if question == .flashcards {
                        flashcardContent
                            .transition(.opacity.combined(with: .move(edge: .trailing)))
                    } else if question == .review {
                        recommendationReview
                            .transition(.opacity.combined(with: .move(edge: .trailing)))
                    } else {
                        questionContent
                            .transition(.opacity.combined(with: .move(edge: .trailing)))
                    }
                }
                .id(detailTopic.map(String.init(describing:)) ?? String(describing: question))
                .animation(stepAnimation, value: question)
                .animation(stepAnimation, value: detailTopic)
                .frame(maxWidth: 1050, alignment: .leading)
                .frame(maxWidth: .infinity, alignment: .topLeading)
                .padding(.vertical, 4)
            }
            .scrollIndicators(.automatic)
            .frame(maxHeight: .infinity)

            HStack(spacing: 12) {
                if question == .flashcards && detailTopic == nil {
                    Button(survey.text(.finishMatching)) { finishFlashcards() }
                        .buttonStyle(.bordered)
                } else if questionIndex > 0 {
                    Button(survey.text(.back), action: goBack)
                        .buttonStyle(.bordered)
                }
                Spacer()
                if detailTopic != nil {
                    Button(FeatureSurveyFlow.hasRemainingDetails(after: currentStep, answers: answers)
                           ? survey.text(.skipRemainingDetails) : survey.text(.skipDetails),
                           action: skipDetails)
                        .buttonStyle(.bordered)
                    Button(survey.text(.continue), action: goForward)
                        .buttonStyle(.borderedProminent)
                        .keyboardShortcut(.defaultAction)
                } else if question == .flashcards {
                    Spacer()
                    if let currentFlashcard {
                        Button {
                            decide(.notForMe)
                        } label: {
                            Label(survey.text(.notForMe), systemImage: "xmark.circle.fill")
                                .foregroundStyle(.red)
                        }
                        .buttonStyle(.bordered)
                        .keyboardShortcut(.leftArrow, modifiers: [])

                        Button {
                            decide(.interested)
                        } label: {
                            Label(survey.text(.interested), systemImage: "checkmark.circle.fill")
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.green)
                        .keyboardShortcut(.rightArrow, modifiers: [])
                        .disabled(currentFlashcard.isAvailable)
                    }
                } else if question == .review {
                    Button(survey.text(.applySelection)) {
                        onApply(FeatureRecommendationEngine.selectionPreservingInstalled(
                            proposedFeatures,
                            installed: installedFeatures))
                    }
                        .buttonStyle(.borderedProminent)
                        .disabled(proposedFeatures.isEmpty && installedFeatures.isEmpty)
                } else {
                    Button(survey.text(.continue), action: goForward)
                        .buttonStyle(.borderedProminent)
                        .keyboardShortcut(.defaultAction)
                }
            }

            Label(survey.text(.privacyNote),
                  systemImage: "lock.shield")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 14)
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(.background)
        .focusable()
        .focused($surveyHasFocus)
        .onAppear { surveyHasFocus = true }
        .onKeyPress(.leftArrow) {
            guard question == .flashcards else { return .ignored }
            decide(.notForMe)
            return .handled
        }
        .onKeyPress(.rightArrow) {
            guard question == .flashcards else { return .ignored }
            decide(.interested)
            return .handled
        }
    }

    private var questionIndex: Int {
        visibleSteps.firstIndex(of: currentStep) ?? 0
    }

    private var questionContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(questionTitle)
                .font(.title2.weight(.semibold))
                .fixedSize(horizontal: false, vertical: true)
            Text(questionSubtitle)
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 330), alignment: .top)],
                      alignment: .leading, spacing: 12) {
                ForEach(options(for: question)) { option in
                    choiceCard(option)
                }
            }
            .padding(.top, 8)
        }
    }

    private var questionTitle: String {
        switch question {
        case .activities: survey.text(.activitiesQuestion)
        case .appCategories: survey.text(.categoriesQuestion)
        case .routines: survey.text(.routinesQuestion)
        case .captureNextStep: survey.text(.captureQuestion)
        case .flashcards: ""
        case .review: ""
        }
    }

    private var questionSubtitle: String {
        switch question {
        case .activities: survey.text(.activitiesSubtitle)
        case .appCategories: survey.text(.categoriesSubtitle)
        case .routines: survey.text(.routinesSubtitle)
        case .captureNextStep: survey.text(.captureSubtitle)
        case .flashcards: ""
        case .review: ""
        }
    }

    private func options(for question: FeatureSurveyQuestion) -> [SurveyOption] {
        switch question {
        case .activities:
            FeatureSurveyActivity.allCases.map {
                SurveyOption(id: $0.rawValue, title: survey.activityTitle($0),
                             subtitle: survey.activitySubtitle($0), symbol: $0.symbolName,
                             isSelected: answers.activities.contains($0),
                             priority: answers.activityPriority.firstIndex(of: $0).map { $0 + 1 })
            }
        case .appCategories:
            FeatureSurveyAppCategory.allCases.map {
                SurveyOption(id: $0.rawValue, title: survey.categoryTitle($0),
                             subtitle: nil, symbol: appCategorySymbol($0),
                             isSelected: answers.appCategories.contains($0),
                             priority: answers.appCategoryPriority.firstIndex(of: $0).map { $0 + 1 })
            }
        case .routines:
            FeatureSurveyRoutine.allCases.map {
                SurveyOption(id: $0.rawValue, title: survey.routineTitle($0),
                             subtitle: nil, symbol: routineSymbol($0),
                             isSelected: answers.routines.contains($0), priority: nil)
            }
        case .captureNextStep:
            FeatureSurveyCaptureNextStep.allCases.map {
                SurveyOption(id: $0.rawValue, title: survey.captureTitle($0),
                             subtitle: nil, symbol: captureSymbol($0),
                             isSelected: answers.captureNextStep == $0, priority: nil)
            }
        case .flashcards, .review:
            []
        }
    }

    private func choiceCard(_ option: SurveyOption) -> some View {
        Button {
            toggleChoice(option.id)
        } label: { choiceCardLabel(option) }
        .buttonStyle(.plain)
        .accessibilityLabel(option.title)
        .accessibilityAddTraits(option.isSelected ? .isSelected : [])
    }

    private func choiceCardLabel(_ option: SurveyOption) -> some View {
        HStack(spacing: 13) {
            Image(systemName: option.symbol)
                .font(.system(size: 26, weight: .medium))
                .foregroundStyle(option.isSelected ? Color.accentColor : Color.secondary)
                .frame(width: 40, height: 44)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text(option.title)
                    .font(.callout.weight(.medium))
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)
                optionSubtitle(option.subtitle)
            }
            Spacer(minLength: 4)
            optionPriority(option)
                .accessibilityHidden(true)
        }
        .padding(.horizontal, 19)
        .padding(.vertical, 17)
        .frame(maxWidth: .infinity, minHeight: option.subtitle == nil ? 92 : 108, alignment: .leading)
        .background(option.isSelected ? Color.accentColor.opacity(0.09) : Color.primary.opacity(0.025),
                    in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(option.isSelected ? Color.accentColor.opacity(0.55)
                                               : Color.primary.opacity(0.09), lineWidth: 1)
        }
    }

    @ViewBuilder
    private func optionSubtitle(_ subtitle: String?) -> some View {
        if let subtitle {
            Text(subtitle)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder
    private func optionPriority(_ option: SurveyOption) -> some View {
        if let priority = option.priority {
            Text("\(priority)")
                .font(.headline.monospacedDigit())
                .foregroundStyle(Color.accentColor)
                .frame(width: 30, height: 30)
                .background(Color.accentColor.opacity(0.11), in: Circle())
        } else {
            VStack(spacing: 5) {
                Image(systemName: option.isSelected ? "checkmark.circle.fill" : "chevron.right")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(option.isSelected ? Color.accentColor : Color.secondary.opacity(0.65))
                Text(option.isSelected ? survey.text(.selected) : survey.text(.choose))
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func detailPage(_ topic: FeatureSurveyTopic) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Label(topic.title(survey), systemImage: topicSymbol(topic))
                .font(.callout.weight(.medium))
                .foregroundStyle(Color.accentColor)
            Text(survey.text(.detailQuestion))
                .font(.title2.weight(.semibold))
            Text(survey.text(.detailSubtitle))
                .font(.callout)
                .foregroundStyle(.secondary)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 330), alignment: .top)],
                      alignment: .leading, spacing: 12) {
                ForEach(topic.detailChoices) { choice in
                    detailChoiceCard(choice, in: topic)
                }
            }
            Button(survey.text(.removeTopic)) {
                remove(topic)
            }
            .buttonStyle(.borderless)
            .foregroundStyle(.secondary)
            .padding(.top, 6)
        }
    }

    private func detailChoiceCard(_ choice: FeatureSurveyDetailChoice,
                                  in topic: FeatureSurveyTopic) -> some View {
        let isSelected = answers.selectedTasks[topic, default: []].contains(choice.id)
        return Button {
            if !answers.selectedTasks[topic, default: []].insert(choice.id).inserted {
                answers.selectedTasks[topic, default: []].remove(choice.id)
            }
        } label: {
            HStack(spacing: 13) {
                Image(systemName: choice.symbol)
                    .font(.system(size: 23, weight: .medium))
                    .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
                    .frame(width: 38, height: 38)
                Text(survey.detailTitle(choice))
                    .font(.callout.weight(.medium))
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 4)
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 20))
                    .foregroundStyle(isSelected ? Color.accentColor : Color.secondary.opacity(0.55))
            }
            .padding(18)
            .frame(maxWidth: .infinity, minHeight: 82, alignment: .leading)
            .background(isSelected ? Color.accentColor.opacity(0.09) : Color.primary.opacity(0.025),
                        in: RoundedRectangle(cornerRadius: 15, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 15, style: .continuous)
                    .strokeBorder(isSelected ? Color.accentColor.opacity(0.55)
                                             : Color.primary.opacity(0.09), lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var recommendationReview: some View {
        let selectedFeatures = recommendationOrder.filter(proposedFeatures.contains)
        return VStack(alignment: .leading, spacing: 12) {
            Label(String(format: survey.text(.reviewCountFormat),
                         selectedFeatures.count, recommendationOrder.count),
                  systemImage: "sparkles")
                .font(.callout.weight(.medium))
                .foregroundStyle(.secondary)

            Text(survey.text(.reviewExplanation))
                    .font(.callout)
                    .foregroundStyle(.secondary)

            if recommendationOrder.isEmpty {
                Text(survey.text(.currentSetup))
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(recommendationOrder, id: \.self) { feature in
                        recommendationRow(feature)
                    }
                }
            }
        }
    }

    private func goForward() {
        guard let next = FeatureSurveyFlow.nextStep(after: currentStep, answers: answers) else { return }
        if next == .question(.flashcards) {
            let context = FeatureRecommendationContext.current()
            installedFeatures = context.installed
            recommendationOrder = FeatureRecommendationEngine.recommend(answers, context: context)
            proposedFeatures = []
            flashcardIndex = 0
            decisionCount = 0
            lastDecision = nil
            if recommendationOrder.isEmpty {
                withAnimation(stepAnimation) {
                    detailTopic = nil
                    question = .review
                }
                return
            }
        }
        withAnimation(stepAnimation) {
            show(next)
        }
    }

    private func goBack() {
        guard let previous = FeatureSurveyFlow.previousStep(before: currentStep, answers: answers) else { return }
        if previous == .question(.flashcards) {
            flashcardIndex = 0
            lastDecision = nil
        }
        withAnimation(stepAnimation) {
            show(previous)
        }
    }

    private func skipDetails() {
        guard let next = FeatureSurveyFlow.nextQuestion(after: currentStep, answers: answers) else { return }
        withAnimation(stepAnimation) {
            show(next)
        }
    }

    private func show(_ step: FeatureSurveyStep) {
        switch step {
        case .question(let question):
            self.question = question
            detailTopic = nil
        case .topic(let topic):
            detailTopic = topic
            switch topic {
            case .activity: question = .activities
            case .appCategory: question = .appCategories
            }
        }
    }

    private func toggleChoice(_ id: String) {
        switch question {
        case .activities:
            guard let value = FeatureSurveyActivity(rawValue: id) else { return }
            if answers.activities.insert(value).inserted {
                answers.activityPriority.append(value)
            } else {
                answers.activities.remove(value)
                answers.activityPriority.removeAll { $0 == value }
                answers.selectedTasks.removeValue(forKey: .activity(value))
            }
        case .appCategories:
            guard let value = FeatureSurveyAppCategory(rawValue: id) else { return }
            if answers.appCategories.insert(value).inserted {
                answers.appCategoryPriority.append(value)
            } else {
                answers.appCategories.remove(value)
                answers.appCategoryPriority.removeAll { $0 == value }
                answers.selectedTasks.removeValue(forKey: .appCategory(value))
            }
        case .routines:
            guard let value = FeatureSurveyRoutine(rawValue: id) else { return }
            if answers.routines.insert(value).inserted {
                answers.routinePriority.append(value)
            } else {
                answers.routines.remove(value)
                answers.routinePriority.removeAll { $0 == value }
            }
        case .captureNextStep:
            answers.captureNextStep = FeatureSurveyCaptureNextStep(rawValue: id)
        case .flashcards, .review:
            break
        }
        if !FeatureSurveyFlow.shouldAskCaptureFollowUp(answers) {
            answers.captureNextStep = nil
        }
    }

    private func closeDetail() {
        withAnimation(stepAnimation) {
            detailTopic = nil
        }
    }

    private func remove(_ topic: FeatureSurveyTopic) {
        switch topic {
        case .activity(let activity):
            answers.activities.remove(activity)
            answers.activityPriority.removeAll { $0 == activity }
        case .appCategory(let category):
            answers.appCategories.remove(category)
            answers.appCategoryPriority.removeAll { $0 == category }
        }
        answers.selectedTasks.removeValue(forKey: topic)
        if !FeatureSurveyFlow.shouldAskCaptureFollowUp(answers) {
            answers.captureNextStep = nil
        }
        closeDetail()
    }

    private func topicSymbol(_ topic: FeatureSurveyTopic) -> String {
        switch topic {
        case .activity(let activity): activity.symbolName
        case .appCategory(let category): appCategorySymbol(category)
        }
    }

    private func decide(_ decision: SurveyDecision) {
        guard !isAnimatingDecision, currentFlashcard != nil else { return }
        isAnimatingDecision = true
        let target = decision == .interested
        if let feature = currentFlashcard {
            if target {
                proposedFeatures.insert(feature)
            } else {
                proposedFeatures.remove(feature)
            }
        }
        lastDecision = decision
        decisionCount += 1
        withAnimation(reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 0.78)) {
            cardOffset = target ? 650 : -650
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.24) {
            guard self.question == .flashcards else { return }
            self.flashcardIndex += 1
            self.cardOffset = 0
            self.isAnimatingDecision = false
            if self.currentFlashcard == nil {
                self.finishFlashcards()
            }
        }
    }

    private func finishFlashcards() {
        isAnimatingDecision = false
        withAnimation(stepAnimation) {
            question = .review
        }
    }

    private var flashcardContent: some View {
        VStack(spacing: 18) {
            if let feature = currentFlashcard {
                HStack {
                    Text(String(format: survey.text(.suggestionCountFormat),
                                flashcardIndex + 1, recommendationOrder.count))
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                    Spacer()
                    decisionFeedbackSymbol
                }
                VStack(alignment: .leading, spacing: 20) {
                    SettingsIconTile(symbol: feature.symbolName, size: 46, accentGroup: feature.group)
                    VStack(alignment: .leading, spacing: 8) {
                        Text(feature.hubTitle(l10n.s, hub: hub))
                            .font(.title2.weight(.semibold))
                        Text(feature.hubDescription(hub))
                            .font(.body)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Divider()
                    VStack(alignment: .leading, spacing: 6) {
                        Label(survey.text(.workflowTitle), systemImage: "arrow.turn.down.right")
                            .font(.callout.weight(.semibold))
                        Text(workflowDescription(for: feature))
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(28)
                .frame(maxWidth: 720, minHeight: 330, alignment: .leading)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.1), lineWidth: 1)
                }
                .offset(x: cardOffset)
                .rotationEffect(.degrees(Double(cardOffset / 42)))
                .gesture(
                    DragGesture(minimumDistance: 24)
                        .onEnded { value in
                            guard abs(value.translation.width) > 90,
                                  abs(value.translation.width) > abs(value.translation.height) else { return }
                            decide(value.translation.width > 0 ? .interested : .notForMe)
                        }
                )
                .accessibilityElement(children: .combine)
            } else {
                ContentUnavailableView(survey.text(.noSuggestionsTitle),
                                       systemImage: "sparkles",
                                       description: Text(survey.text(.existingSetupDescription)))
            }
        }
        .frame(maxWidth: .infinity, minHeight: 390, alignment: .center)
        .contentShape(Rectangle())
    }

    private func workflowDescription(for feature: AppFeature) -> String {
        let matchingTask = answers.selectedTasks
            .flatMap { entry in
                entry.key.detailChoices.filter { entry.value.contains($0.id) }
            }
            .first { $0.features.contains(feature) }
        let context: String
        if let matchingTask {
            context = survey.detailTitle(matchingTask)
        } else if let nextStep = answers.captureNextStep, nextStep.features.contains(feature) {
            context = survey.captureTitle(nextStep)
        } else if let routine = answers.routinePriority.first(where: {
            $0.features.contains(feature)
        }) ?? answers.routines.first(where: { $0.features.contains(feature) }) {
            context = survey.routineTitle(routine)
        } else if let activity = answers.activityPriority.first(where: {
            $0.features.contains(feature) && $0 != .everydayMix
        }) ?? answers.activities.first(where: { $0.features.contains(feature) && $0 != .everydayMix }) {
            context = survey.activityTitle(activity)
        } else if let category = answers.appCategoryPriority.first(where: {
            $0.features.contains(feature)
        }) ?? answers.appCategories.first(where: { $0.features.contains(feature) }) {
            context = survey.categoryTitle(category)
        } else {
            context = survey.text(.headerQuestionSubtitle)
        }
        return String(format: survey.text(.workflowFormat), context, feature.hubDescription(hub))
    }

    @ViewBuilder
    private var decisionFeedbackSymbol: some View {
        if #available(macOS 26.0, *), let lastDecision {
            if lastDecision == .interested {
                Image(systemName: "checkmark.circle.fill")
                    .symbolEffect(.bounce, value: lastDecision == .interested)
                    .foregroundStyle(.green)
            } else {
                Image(systemName: "xmark.circle.fill")
                    .symbolEffect(.bounce, value: lastDecision == .notForMe)
                    .foregroundStyle(.red)
            }
        }
    }

    private func appCategorySymbol(_ category: FeatureSurveyAppCategory) -> String {
        switch category {
        case .webAndMessaging: "bubble.left.and.bubble.right"
        case .photosAndVideo: "photo"
        case .musicAndMedia: "music.note"
        case .games: "gamecontroller"
        case .notesAndDocuments: "doc.text"
        case .creativeTools: "paintpalette"
        case .developmentAndLearning: "book.closed"
        }
    }

    private func routineSymbol(_ routine: FeatureSurveyRoutine) -> String {
        switch routine {
        case .switchBetweenApps: "rectangle.on.rectangle"
        case .copyAndReuseThings: "doc.on.clipboard"
        case .saveAndFindThings: "folder"
        case .captureScreen: "camera.viewfinder"
        case .repeatSteps: "arrow.trianglehead.2.clockwise"
        case .focusOnOneApp: "scope"
        case .useAccessories: "cable.connector"
        }
    }

    private func captureSymbol(_ step: FeatureSurveyCaptureNextStep) -> String {
        switch step {
        case .edit: "pencil.tip.crop.circle"
        case .share: "square.and.arrow.up"
        case .organize: "folder"
        case .findText: "text.viewfinder"
        case .view: "eye"
        }
    }

    private func recommendationRow(_ feature: AppFeature) -> some View {
        let isSelected = proposedFeatures.contains(feature)
        return Toggle(isOn: Binding(
            get: { proposedFeatures.contains(feature) },
            set: { selected in
                if selected { proposedFeatures.insert(feature) }
                else { proposedFeatures.remove(feature) }
            })) {
                HStack(alignment: .top, spacing: 9) {
                    SettingsIconTile(symbol: feature.symbolName, size: 23, accentGroup: feature.group)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(feature.hubTitle(l10n.s, hub: hub))
                            .font(.callout.weight(.medium))
                        Text(feature.hubDescription(hub))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                        Text(workflowDescription(for: feature))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .toggleStyle(.checkbox)
            .accessibilityLabel("\(feature.hubTitle(l10n.s, hub: hub)). \(feature.hubDescription(hub))")
            .accessibilityAddTraits(isSelected ? .isSelected : [])
            .padding(.vertical, 3)
    }
}

private struct SurveyOption: Identifiable {
    let id: String
    let title: String
    let subtitle: String?
    let symbol: String
    let isSelected: Bool
    let priority: Int?
}

private enum SurveyDecision: Equatable {
    case interested
    case notForMe
}
