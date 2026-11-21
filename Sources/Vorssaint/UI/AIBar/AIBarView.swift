// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import SwiftUI

struct AIBarView: View {
    @ObservedObject private var service = AIBarService.shared
    @ObservedObject private var l10n = L10n.shared
    @State private var draft = ""
    @FocusState private var fieldFocused: Bool

    private var strings: AIBarFeatureStrings { FeatureStrings.aiBar(l10n.language) }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            contextLine
            HStack(spacing: 8) {
                Image(systemName: "sparkles").foregroundStyle(Color.accentColor)
                TextField(strings.placeholder, text: $service.request)
                    .textFieldStyle(.plain)
                    .font(.system(size: 15))
                    .focused($fieldFocused)
                    .onSubmit { service.submit() }
                    .disabled(service.phase == .generating || service.phase == .running)
                if service.phase == .generating || service.phase == .running {
                    ProgressView().controlSize(.small)
                }
            }
            switch service.phase {
            case .idle: EmptyView()
            case .generating:
                Text(strings.generating).font(.caption).foregroundStyle(.secondary)
            case .ready(let command):
                ready(command)
            case .running:
                EmptyView()
            case .finished(let output, let status, let timedOut):
                finished(output: output, status: status, timedOut: timedOut)
            case .failed(let message):
                failed(message)
            }
        }
        .padding(14)
        .frame(width: 560)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Color.primary.opacity(0.1)))
        .onAppear { fieldFocused = true }
        .onExitCommand { service.hide() }
    }

    private var contextLine: some View {
        HStack(spacing: 6) {
            Image(systemName: "folder").font(.caption)
            if let folder = service.folder {
                Text(String(format: strings.workingInFormat, folder.lastPathComponent)).lineLimit(1)
                Text("·")
            }
            Text(service.items.isEmpty ? strings.selectionNone
                 : String(format: strings.selectionCountFormat, service.items.count))
        }
        .font(.caption).foregroundStyle(.secondary)
    }

    private func ready(_ command: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField("", text: Binding(get: { draft.isEmpty ? command : draft },
                                        set: { draft = $0; service.edit(command: $0) }),
                      axis: .vertical)
                .textFieldStyle(.plain)
                .font(.system(size: 12, design: .monospaced))
                .lineLimit(1...6)
                .padding(8)
                .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))
            if let prediction = service.prediction {
                FlowEffects(effects: prediction.effects, risk: prediction.risk, strings: strings)
                if prediction.risk == .dangerous {
                    Text(strings.confirmDangerous).font(.caption).foregroundStyle(.red)
                }
            }
            HStack {
                Button(service.prediction?.risk == .dangerous ? strings.runAnyway : strings.run) {
                    service.confirmOrRun()
                }
                .keyboardShortcut(.defaultAction)
                .tint(service.prediction?.risk == .dangerous ? .red : .accentColor)
                Button(strings.copy) { service.copy(draft.isEmpty ? command : draft) }
                Spacer()
                Text(strings.outputLocal).font(.caption2).foregroundStyle(.tertiary)
            }
        }
        .onChange(of: command) { _, new in if draft != new { draft = "" } }
    }

    private func finished(output: String, status: Int32, timedOut: Bool) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(timedOut ? strings.timedOut : (status == 0 ? strings.finished : String(format: strings.failedFormat, Int(status))),
                  systemImage: status == 0 && !timedOut ? "checkmark.circle" : "exclamationmark.triangle")
                .font(.caption.weight(.semibold))
                .foregroundStyle(status == 0 && !timedOut ? Color.green : Color.orange)
            if !output.isEmpty {
                ScrollView {
                    Text(output).font(.system(size: 11, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: 180)
            }
            HStack {
                Button(strings.close) { service.hide() }.keyboardShortcut(.defaultAction)
                Spacer()
                Text(strings.outputLocal).font(.caption2).foregroundStyle(.tertiary)
            }
        }
    }

    private func failed(_ message: String) -> some View {
        Label(message, systemImage: "exclamationmark.triangle")
            .font(.caption).foregroundStyle(.orange)
            .fixedSize(horizontal: false, vertical: true)
    }
}

private struct FlowEffects: View {
    let effects: [AIBarPrediction.Effect]
    let risk: AIBarPrediction.Risk
    let strings: AIBarFeatureStrings

    var body: some View {
        HStack(spacing: 6) {
            ForEach(effects, id: \.rawValue) { effect in
                Text(label(effect))
                    .font(.system(size: 10, weight: .semibold))
                    .padding(.horizontal, 7).padding(.vertical, 2)
                    .background(color(effect).opacity(0.16), in: Capsule())
                    .foregroundStyle(color(effect))
            }
        }
    }

    private func label(_ effect: AIBarPrediction.Effect) -> String {
        switch effect {
        case .readsOnly: return strings.effectReads
        case .createsFiles: return strings.effectCreates
        case .movesOrOverwrites: return strings.effectMoves
        case .deletes: return strings.effectDeletes
        case .network: return strings.effectNetwork
        case .elevates: return strings.effectElevates
        case .system: return strings.effectSystem
        case .unknown: return strings.effectUnknown
        }
    }

    private func color(_ effect: AIBarPrediction.Effect) -> Color {
        switch effect {
        case .readsOnly, .createsFiles: return .green
        case .movesOrOverwrites, .network, .system, .unknown: return .orange
        case .deletes, .elevates: return .red
        }
    }
}
