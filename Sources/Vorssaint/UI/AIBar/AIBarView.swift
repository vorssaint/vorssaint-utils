// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import SwiftUI

struct AIBarView: View {
    @ObservedObject private var service = AIBarService.shared
    @ObservedObject private var l10n = L10n.shared
    @State private var draft = ""
    @FocusState private var fieldFocused: Bool

    private var strings: AIBarFeatureStrings { FeatureStrings.aiBar(l10n.language) }
    private var busy: Bool { service.phase == .generating || service.phase == .running }
    private var hasRequest: Bool { !service.request.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            field
            if showsDetail {
                Divider().opacity(0.5)
                VStack(alignment: .leading, spacing: 12) {
                    detail
                }
                .padding(.horizontal, 16).padding(.vertical, 14)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
            footer
        }
        .frame(width: 580)
        .background {
            ZStack {
                Rectangle().fill(.regularMaterial)
                LinearGradient(colors: [Color.accentColor.opacity(0.10), .clear],
                               startPoint: .topLeading, endPoint: .center)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(LinearGradient(colors: [Color.white.opacity(0.28), Color.white.opacity(0.05)],
                                             startPoint: .top, endPoint: .bottom), lineWidth: 1)
        )
        .animation(.spring(response: 0.34, dampingFraction: 0.85), value: service.phase)
        .onAppear { fieldFocused = true }
        .onExitCommand { service.hide() }
    }

    // MARK: Field

    private var field: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle().fill(LinearGradient(colors: [Color.accentColor, Color.accentColor.opacity(0.55)],
                                             startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(width: 30, height: 30)
                    .shadow(color: Color.accentColor.opacity(0.35), radius: 6, y: 2)
                Image(systemName: "sparkles").font(.system(size: 14, weight: .semibold)).foregroundStyle(.white)
            }
            TextField(strings.placeholder, text: $service.request)
                .textFieldStyle(.plain)
                .font(.system(size: 19, weight: .regular, design: .rounded))
                .focused($fieldFocused)
                .onSubmit { submitOrRun() }
                .disabled(busy)
            if busy {
                ProgressView().controlSize(.small)
            } else if hasRequest, service.phase == .idle || isFailed {
                Image(systemName: "return")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8).padding(.vertical, 5)
                    .background(Color.primary.opacity(0.08), in: RoundedRectangle(cornerRadius: 7))
                    .transition(.scale.combined(with: .opacity))
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 14)
    }

    private var isFailed: Bool {
        if case .failed = service.phase { return true }
        return false
    }

    private var showsDetail: Bool {
        switch service.phase {
        case .idle, .running: return false
        default: return true
        }
    }

    private func submitOrRun() {
        switch service.phase {
        case .ready: service.confirmOrRun()
        case .finished: service.hide()
        default: service.submit()
        }
    }

    // MARK: Detail

    @ViewBuilder private var detail: some View {
        switch service.phase {
        case .generating:
            HStack(spacing: 8) {
                Image(systemName: "wand.and.stars").foregroundStyle(Color.accentColor)
                Text(strings.generating).foregroundStyle(.secondary)
            }
            .font(.system(size: 12))
        case .ready(let command):
            ready(command)
        case .finished(let output, let status, let timedOut):
            finished(output: output, status: status, timedOut: timedOut)
        case .failed(let message):
            Label(message, systemImage: "exclamationmark.triangle.fill")
                .font(.system(size: 12)).foregroundStyle(.orange)
                .fixedSize(horizontal: false, vertical: true)
        default:
            EmptyView()
        }
    }

    private func ready(_ command: String) -> some View {
        let risk = service.prediction?.risk ?? .review
        let tint = riskColor(risk)
        return VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 0) {
                RoundedRectangle(cornerRadius: 2).fill(tint).frame(width: 3)
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text("$").foregroundStyle(tint)
                    TextField("", text: Binding(get: { draft.isEmpty ? command : draft },
                                                set: { draft = $0; service.edit(command: $0) }),
                              axis: .vertical)
                        .textFieldStyle(.plain)
                        .lineLimit(1...6)
                        .onSubmit { service.confirmOrRun() }
                }
                .font(.system(size: 13, weight: .medium, design: .monospaced))
                .padding(.horizontal, 12).padding(.vertical, 10)
            }
            .background(Color.black.opacity(0.22), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

            if let prediction = service.prediction {
                HStack(spacing: 6) {
                    ForEach(prediction.effects, id: \.rawValue) { effect in
                        EffectChip(effect: effect, strings: strings)
                    }
                }
                if prediction.risk == .dangerous {
                    Label(strings.confirmDangerous, systemImage: "exclamationmark.octagon.fill")
                        .font(.system(size: 11)).foregroundStyle(.red)
                }
            }
            HStack(spacing: 8) {
                Button { service.confirmOrRun() } label: {
                    Label(risk == .dangerous ? strings.runAnyway : strings.run, systemImage: "play.fill")
                        .font(.system(size: 12, weight: .semibold))
                        .padding(.horizontal, 14).padding(.vertical, 6)
                        .foregroundStyle(.white)
                        .background(risk == .dangerous ? Color.red : Color.accentColor, in: Capsule())
                }
                .buttonStyle(.plain)
                Button { service.copy(draft.isEmpty ? command : draft) } label: {
                    Label(strings.copy, systemImage: "doc.on.doc")
                        .font(.system(size: 12, weight: .medium))
                        .padding(.horizontal, 12).padding(.vertical, 6)
                        .background(Color.primary.opacity(0.08), in: Capsule())
                }
                .buttonStyle(.plain)
                Spacer()
            }
        }
        .onChange(of: command) { _, new in if draft != new { draft = "" } }
    }

    private func finished(output: String, status: Int32, timedOut: Bool) -> some View {
        let ok = status == 0 && !timedOut
        return VStack(alignment: .leading, spacing: 10) {
            Label(timedOut ? strings.timedOut : (ok ? strings.finished : String(format: strings.failedFormat, Int(status))),
                  systemImage: ok ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(ok ? Color.green : Color.orange)
            if !output.isEmpty {
                ScrollView {
                    Text(output)
                        .font(.system(size: 11, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(10)
                }
                .frame(maxHeight: 180)
                .background(Color.black.opacity(0.22), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
            Button { service.hide() } label: {
                Text(strings.close)
                    .font(.system(size: 12, weight: .semibold))
                    .padding(.horizontal, 14).padding(.vertical, 6)
                    .background(Color.primary.opacity(0.08), in: Capsule())
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: Footer

    private var footer: some View {
        HStack(spacing: 10) {
            Chip(symbol: "folder", text: service.folder?.lastPathComponent
                    ?? strings.selectionNone)
            Chip(symbol: "cursorarrow.click.2",
                 text: service.items.isEmpty ? strings.selectionNone
                    : String(format: strings.selectionCountFormat, service.items.count))
            Spacer()
            Image(systemName: "lock.fill").font(.system(size: 9))
            Text(strings.outputLocal).lineLimit(1)
        }
        .font(.system(size: 10))
        .foregroundStyle(.secondary)
        .padding(.horizontal, 16).padding(.vertical, 9)
        .background(Color.primary.opacity(0.04))
    }

    private func riskColor(_ risk: AIBarPrediction.Risk) -> Color {
        switch risk {
        case .low: return .green
        case .review: return .orange
        case .dangerous: return .red
        }
    }
}

private struct Chip: View {
    let symbol: String
    let text: String
    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: symbol).font(.system(size: 9, weight: .semibold))
            Text(text).lineLimit(1)
        }
        .padding(.horizontal, 7).padding(.vertical, 3)
        .background(Color.primary.opacity(0.07), in: Capsule())
    }
}

private struct EffectChip: View {
    let effect: AIBarPrediction.Effect
    let strings: AIBarFeatureStrings

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: symbol).font(.system(size: 9, weight: .bold))
            Text(label).font(.system(size: 10, weight: .semibold))
        }
        .padding(.horizontal, 8).padding(.vertical, 3)
        .background(color.opacity(0.16), in: Capsule())
        .foregroundStyle(color)
    }

    private var label: String {
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

    private var symbol: String {
        switch effect {
        case .readsOnly: return "eye"
        case .createsFiles: return "plus.square"
        case .movesOrOverwrites: return "arrow.left.arrow.right"
        case .deletes: return "trash"
        case .network: return "network"
        case .elevates: return "lock.shield"
        case .system: return "gearshape.2"
        case .unknown: return "questionmark.circle"
        }
    }

    private var color: Color {
        switch effect {
        case .readsOnly, .createsFiles: return .green
        case .movesOrOverwrites, .network, .system, .unknown: return .orange
        case .deletes, .elevates: return .red
        }
    }
}
