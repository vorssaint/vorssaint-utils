// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import SwiftUI

/// the chat, drawn in islands style as the page itself
struct CompanionChatView: View {
    @ObservedObject var service: CompanionChatService
    @ObservedObject private var l10n = L10n.shared
    @FocusState private var focused: Bool
    private var canSend: Bool {
        !service.busy && !service.checking && service.health == .ready && service.draft.count <= 16000
            && !service.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        VStack(spacing: 8) {
            header
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 6) {
                        ForEach(service.messages) { message in
                            Text(message.text).textSelection(.enabled)
                                .font(.system(size: 12))
                                .foregroundStyle(.white.opacity(0.92))
                                .padding(.horizontal, 10).padding(.vertical, 7)
                                .modifier(NotchControlSurface(cornerRadius: 12, selected: message.isUser, interactive: false))
                                .frame(maxWidth: .infinity, alignment: message.isUser ? .trailing : .leading)
                                .padding(message.isUser ? .leading : .trailing, 36)
                                .id(message.id)
                        }
                    }
                }
                .scrollIndicators(.hidden)
                .onChange(of: service.messages.last?.id) { _, id in if let id { proxy.scrollTo(id, anchor: .bottom) } }
            }
            if !service.status.isEmpty {
                Text(service.status).font(.system(size: 10.5)).foregroundStyle(.white.opacity(0.6))
                    .textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
            }
            if let label = CompanionSetupSupport.actionLabel(service.health) {
                Button(label) { service.runFix(service.agent) }.buttonStyle(.borderedProminent).controlSize(.small)
            }
            composer
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear { focused = true }
    }

    private var header: some View {
        HStack(spacing: 6) {
            Image(systemName: "sparkles").font(.system(size: 12, weight: .medium)).foregroundStyle(.white.opacity(0.7))
            Menu {
                ForEach(CompanionAgent.listed(chosen: service.agent)) { option in
                    Button { service.switchAgent(option) } label: {
                        if option == service.agent { Label(option.title, systemImage: "checkmark") } else { Text(option.title) }
                    }
                }
            } label: {
                Text(service.agent.title).font(.system(size: 12, weight: .medium))
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .disabled(service.sending)
            .help(CompanionSetupText.text(.switchAI, l10n.language)).accessibilityLabel(CompanionSetupText.text(.switchAI, l10n.language))
            Spacer(minLength: 0)
            iconButton("arrow.clockwise", CompanionChatText.refresh, disabled: service.busy || service.checking,
                       action: service.recheck)
            iconButton("arrow.up.forward.app", CompanionChatText.openApp(service.agent.title), disabled: false, action: service.openApp)
            iconButton("xmark", CompanionSetupText.text(.close, l10n.language), disabled: false, action: service.dismiss)
        }
    }

    private func iconButton(_ symbol: String, _ help: String, disabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 11, weight: .medium))
                .foregroundStyle(.white.opacity(disabled ? 0.3 : 0.75)).frame(width: 24, height: 24)
                .contentShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(NotchButtonStyle(cornerRadius: 8, lifts: false))
        .disabled(disabled).help(help).accessibilityLabel(help)
    }

    private var composer: some View {
        HStack(alignment: .bottom, spacing: 6) {
            TextField(CompanionChatText.ask(service.agent.title), text: $service.draft, axis: .vertical)
                .textFieldStyle(.plain).font(.system(size: 12)).lineLimit(1...3)
                .focused($focused)
                .padding(.horizontal, 10).padding(.vertical, 7)
                .modifier(NotchControlSurface(cornerRadius: 12, interactive: false))
                .onSubmit { if canSend { service.send() } }
            Button(action: service.send) {
                Image(systemName: "arrow.up.circle.fill").font(.system(size: 24))
                    .foregroundStyle(.white.opacity(canSend ? 0.9 : 0.3))
            }
            .buttonStyle(.plain).disabled(!canSend).help(CompanionChatText.send).accessibilityLabel(CompanionChatText.send)
        }
    }
}
