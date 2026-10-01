// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import SwiftUI

/// A Claude Code or Codex request, in place of the page until it is answered
/// here, answered in the terminal, or handed back to the terminal: a tool to
/// allow, AskUserQuestion questions to answer, or an ExitPlanMode plan.
struct NotchAgentApprovalCard: View {
    let request: ClaudeApprovalRequest
    @ObservedObject private var l10n = L10n.shared
    /// Per question: the chosen option indices, whether "Other" is open, and its text.
    @State private var chosen: [Set<Int>] = []
    @State private var otherOpen: [Bool] = []
    @State private var other: [String] = []

    private var text: ClaudeApprovalStrings { FeatureStrings.claudeApprovals(l10n.language) }
    private var product: String { ClaudeApprovalSupport.productName(request.agent) }

    var body: some View {
        NotchAgentCardChrome {
            VStack(alignment: .leading, spacing: 6) {
                NotchAgentCardHeader(title: [request.project, request.toolName].filter { !$0.isEmpty }.joined(separator: " · "),
                                     symbol: "checkmark.shield", tint: .orange, provider: request.agent) { EmptyView() }
                switch request.kind {
                case .tool: tool
                case .questions(let questions): ask(questions)
                case .plan(let plan): review(plan)
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(String(format: label, product))
    }

    private var label: String {
        switch request.kind {
        case .tool: return text.requestLabelFormat
        case .questions: return text.questionLabelFormat
        case .plan: return text.planLabelFormat
        }
    }

    @ViewBuilder private var tool: some View {
        Text(request.summary)
            .font(.system(size: 10, design: .monospaced))
            .foregroundStyle(.white.opacity(0.85))
            .lineLimit(2)
            .truncationMode(.middle)
            .help(request.summary)
        Spacer(minLength: 0)
        buttons {
            notchAgentPill(text.deny, prominent: false, tint: .orange) { answer(.deny) }
            if request.canAlways {
                notchAgentPill(text.always, prominent: false, tint: .orange) { answer(.always) }
                    .help(text.alwaysHelp)
            }
            notchAgentPill(text.allow, tint: .orange) { answer(.allow) }
        }
    }

    // MARK: Questions

    /// No Deny: the terminal picker stays the way out of a question.
    @ViewBuilder private func ask(_ questions: [ClaudeApprovalQuestion]) -> some View {
        let answers = ClaudeApprovalSupport.answers(for: questions, chosen: chosen, other: typedOther)
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(Array(questions.enumerated()), id: \.offset) { index, question in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(alignment: .firstTextBaseline, spacing: 5) {
                            if let header = question.header, !header.isEmpty {
                                Text(header)
                                    .font(.system(size: 9, weight: .semibold))
                                    .foregroundStyle(.white.opacity(0.7))
                                    .padding(.horizontal, 6)
                                    .frame(height: 15)
                                    .background(.white.opacity(0.1), in: Capsule(style: .continuous))
                            }
                            Text(question.text)
                                .font(.system(size: 10.5, weight: .medium))
                                .foregroundStyle(.white.opacity(0.9))
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        ForEach(Array(question.options.enumerated()), id: \.offset) { option, item in
                            optionRow(item.title, description: item.description, recommended: item.isRecommended,
                                      chosen: isChosen(index, option), multiSelect: question.multiSelect) {
                                toggle(index, option, in: question)
                            }
                        }
                        optionRow(text.other, description: nil, recommended: false,
                                  chosen: isOtherOpen(index), multiSelect: question.multiSelect) {
                            toggleOther(index, in: question)
                        }
                        if isOtherOpen(index) {
                            TextField(text.otherPlaceholder, text: otherBinding(index))
                                .textFieldStyle(.plain)
                                .font(.system(size: 11))
                                .padding(.horizontal, 8)
                                .frame(height: 22)
                                .background(.white.opacity(0.08), in: Capsule(style: .continuous))
                                .onSubmit { if let answers { answer(.answers(answers)) } }
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .scrollIndicators(.automatic)
        .onAppear { reset(questions) }
        buttons {
            notchAgentPill(text.answer, tint: .orange) { if let answers { answer(.answers(answers)) } }
                .disabled(answers == nil)
                .opacity(answers == nil ? 0.45 : 1)
        }
    }

    /// A full-width choice like Claude Code's picker: radio or checkbox, the
    /// title, and its description underneath.
    private func optionRow(_ title: String, description: String?, recommended: Bool, chosen: Bool,
                           multiSelect: Bool, action: @escaping () -> Void) -> some View {
        let indicator = multiSelect ? (chosen ? "checkmark.square.fill" : "square")
                                    : (chosen ? "largecircle.fill.circle" : "circle")
        return Button(action: action) {
            HStack(alignment: .firstTextBaseline, spacing: 7) {
                Image(systemName: indicator)
                    .font(.system(size: 10))
                    .foregroundStyle(chosen ? AnyShapeStyle(.orange) : AnyShapeStyle(.white.opacity(0.4)))
                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 4) {
                        Text(title)
                            .font(.system(size: 10.5, weight: .semibold))
                            .foregroundStyle(chosen ? AnyShapeStyle(.orange) : AnyShapeStyle(.white.opacity(0.9)))
                        if recommended {
                            Image(systemName: "star.fill").font(.system(size: 8)).foregroundStyle(.orange)
                        }
                    }
                    if let description, !description.isEmpty {
                        Text(description)
                            .font(.system(size: 9.5))
                            .foregroundStyle(.white.opacity(0.55))
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(chosen ? AnyShapeStyle(.orange.opacity(0.14)) : AnyShapeStyle(.white.opacity(0.05)),
                        in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(NotchButtonStyle(cornerRadius: 8))
    }

    private var typedOther: [String] {
        other.indices.map { otherOpen.indices.contains($0) && otherOpen[$0] ? other[$0] : "" }
    }

    private func reset(_ questions: [ClaudeApprovalQuestion]) {
        let count = questions.count
        guard chosen.count != count else { return }
        chosen = Array(repeating: [], count: count)
        otherOpen = Array(repeating: false, count: count)
        other = Array(repeating: "", count: count)
    }

    private func isChosen(_ index: Int, _ option: Int) -> Bool {
        chosen.indices.contains(index) && chosen[index].contains(option)
    }

    private func isOtherOpen(_ index: Int) -> Bool {
        otherOpen.indices.contains(index) && otherOpen[index]
    }

    /// Multi-select toggles membership; single select replaces, and closes "Other".
    private func toggle(_ index: Int, _ option: Int, in question: ClaudeApprovalQuestion) {
        guard chosen.indices.contains(index) else { return }
        if question.multiSelect {
            if chosen[index].contains(option) { chosen[index].remove(option) } else { chosen[index].insert(option) }
        } else {
            chosen[index] = chosen[index] == [option] ? [] : [option]
            otherOpen[index] = false
        }
    }

    private func toggleOther(_ index: Int, in question: ClaudeApprovalQuestion) {
        guard otherOpen.indices.contains(index) else { return }
        otherOpen[index].toggle()
        if otherOpen[index], !question.multiSelect { chosen[index] = [] }
    }

    private func otherBinding(_ index: Int) -> Binding<String> {
        Binding(get: { other.indices.contains(index) ? other[index] : "" },
                set: { if other.indices.contains(index) { other[index] = $0 } })
    }

    // MARK: Plan

    @ViewBuilder private func review(_ plan: String) -> some View {
        Text(ClaudeApprovalSupport.planTitle(plan) ?? text.planFallbackTitle)
            .font(.system(size: 10.5, weight: .medium))
            .foregroundStyle(.white.opacity(0.9))
            .lineLimit(1)
        // Plain text: the island has no room for rendered headings and lists.
        ScrollView {
            Text(plan)
                .font(.system(size: 10))
                .foregroundStyle(.white.opacity(0.8))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .scrollIndicators(.automatic)
        buttons {
            notchAgentPill(text.keepPlanning, prominent: false, tint: .orange) { answer(.deny) }
            notchAgentPill(text.approveAcceptEdits, prominent: false, tint: .orange) { answer(.allowAcceptingEdits) }
                .help(text.approveAcceptEditsHelp)
            notchAgentPill(text.approve, tint: .orange) { answer(.allow) }
        }
    }

    private func buttons<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        HStack(spacing: 6) {
            Spacer(minLength: 0)
            content()
        }
    }

    private func answer(_ decision: ClaudeApprovalDecision) {
        ClaudeApprovalService.shared.answer(decision, to: request)
    }
}
