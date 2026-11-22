// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import SwiftUI

/// The pop-up, as the island opened: a black shape hung from the camera that
/// springs down from it. The window around it is clear.
struct AgentAskView: View {
    @ObservedObject var service: AgentAskService
    let cameraInset: CGFloat

    var body: some View {
        VStack(spacing: 0) {
            if let request = service.current {
                AgentAskCard(request: request, service: service, cameraInset: cameraInset)
                    .id(request.id)
                    .transition(.scale(scale: 0.5, anchor: .top).combined(with: .opacity))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .animation(.spring(response: 0.45, dampingFraction: 0.8), value: service.current?.id)
    }
}

private struct AgentAskCard: View {
    let request: AgentAskRequest
    let service: AgentAskService
    let cameraInset: CGFloat
    @State private var step = 0
    @State private var answers: [String: String] = [:]
    @State private var picked: [String] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Color.clear.frame(height: cameraInset)
            header
            switch request.kind {
            case .questions(let questions): questionBody(questions)
            case .permission(let tool, let summary): permissionBody(tool: tool, summary: summary)
            }
            Button("Answer in terminal") { service.deferToTerminal(request) }
                .buttonStyle(.plain).font(.system(size: 11)).foregroundStyle(.white.opacity(0.5))
                .frame(maxWidth: .infinity, alignment: .center)
        }
        .padding(.horizontal, 22).padding(.bottom, 16)
        .frame(width: 540)
        .background(NotchShape(attached: true, radius: 30).fill(.black))
        .foregroundStyle(.white)
        .environment(\.colorScheme, .dark)
    }

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "terminal.fill").font(.system(size: 12, weight: .semibold)).foregroundStyle(.orange)
            Text(request.project.isEmpty ? "\(request.agent) asks" : "\(request.agent) · \(request.project)")
                .font(.system(size: 12, weight: .semibold)).foregroundStyle(.white.opacity(0.75))
            Spacer(minLength: 0)
            if case .questions(let questions) = request.kind, questions.count > 1 {
                Text("\(step + 1) of \(questions.count)").font(.system(size: 11)).foregroundStyle(.white.opacity(0.5))
            }
        }
    }

    // MARK: Questions

    @ViewBuilder private func questionBody(_ questions: [AgentAskQuestion]) -> some View {
        let question = questions[min(step, questions.count - 1)]
        VStack(alignment: .leading, spacing: 10) {
            if !question.header.isEmpty {
                Text(question.header.uppercased()).font(.system(size: 10, weight: .bold)).foregroundStyle(.white.opacity(0.45))
            }
            Text(question.text).font(.system(size: 15, weight: .semibold)).fixedSize(horizontal: false, vertical: true)
            VStack(spacing: 6) {
                ForEach(question.options) { option in optionRow(option, in: question, of: questions.count) }
            }
            if question.multiSelect {
                Button { commit(question, labels: picked, of: questions.count) } label: {
                    Text("Send").font(.system(size: 13, weight: .semibold)).frame(maxWidth: .infinity, minHeight: 34)
                        .background(Capsule().fill(.white.opacity(picked.isEmpty ? 0.15 : 0.95)))
                        .foregroundStyle(picked.isEmpty ? .white.opacity(0.5) : .black)
                }
                .buttonStyle(.plain).disabled(picked.isEmpty)
            }
        }
    }

    private func optionRow(_ option: AgentAskQuestion.Option, in question: AgentAskQuestion, of count: Int) -> some View {
        let selected = picked.contains(option.label)
        return Button {
            if question.multiSelect {
                if selected { picked.removeAll { $0 == option.label } } else { picked.append(option.label) }
            } else {
                commit(question, labels: [option.label], of: count)
            }
        } label: {
            HStack(alignment: .top, spacing: 10) {
                if question.multiSelect {
                    Image(systemName: selected ? "checkmark.square.fill" : "square").font(.system(size: 14))
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(option.label).font(.system(size: 13, weight: .semibold)).multilineTextAlignment(.leading)
                    if !option.detail.isEmpty {
                        Text(option.detail).font(.system(size: 11)).foregroundStyle(.white.opacity(0.55))
                            .multilineTextAlignment(.leading).lineLimit(2)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12).padding(.vertical, 9)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(.white.opacity(selected ? 0.24 : 0.1)))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func commit(_ question: AgentAskQuestion, labels: [String], of count: Int) {
        answers[question.text] = labels.joined(separator: ", ")
        picked = []
        if step + 1 < count { step += 1 } else { service.answer(request, answers: answers) }
    }

    // MARK: Permission

    private func permissionBody(tool: String, summary: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Allow \(tool)?").font(.system(size: 15, weight: .semibold))
            Text(summary).font(.system(size: 12, design: .monospaced)).foregroundStyle(.white.opacity(0.8))
                .lineLimit(5).fixedSize(horizontal: false, vertical: true)
                .padding(10).frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(.white.opacity(0.08)))
            HStack(spacing: 8) {
                Button { service.decide(request, allow: false) } label: {
                    Text("Deny").font(.system(size: 13, weight: .semibold)).frame(maxWidth: .infinity, minHeight: 34)
                        .background(Capsule().fill(.red.opacity(0.35)))
                }
                Button { service.decide(request, allow: true) } label: {
                    Text("Allow").font(.system(size: 13, weight: .semibold)).foregroundStyle(.black)
                        .frame(maxWidth: .infinity, minHeight: 34).background(Capsule().fill(.white.opacity(0.95)))
                }
            }
            .buttonStyle(.plain)
        }
    }
}
