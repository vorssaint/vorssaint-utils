// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import SwiftUI

struct FeedbackView: View {
    let onClose: () -> Void

    @ObservedObject private var l10n = L10n.shared
    @State private var kind: FeedbackKind
    @State private var message = ""
    @State private var includeDiagnostics = false
    @State private var isSending = false
    @State private var wasSent = false
    @State private var errorMessage: String?

    private let diagnostics = FeedbackDiagnostics.current()

    init(initialKind: FeedbackKind = .bug, onClose: @escaping () -> Void) {
        _kind = State(initialValue: initialKind)
        self.onClose = onClose
    }

    private var strings: FeedbackStrings { FeatureStrings.feedback(l10n.language) }
    private var count: Int { message.utf16.count }
    private var canSend: Bool {
        let trimmedCount = message.trimmingCharacters(in: .whitespacesAndNewlines).utf16.count
        return trimmedCount >= 10 && count <= 2_000 && !isSending
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            if wasSent {
                sentView
            } else {
                form
            }
        }
        .frame(width: 600, height: 650)
    }

    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: "bubble.left.and.text.bubble.right.fill")
                .font(.title2)
                .foregroundStyle(.tint)
            Text(strings.windowTitle)
                .font(.title2.weight(.semibold))
            Spacer()
            Button(strings.done, action: onClose)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 18)
    }

    private var form: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Picker("", selection: $kind) {
                        Text(strings.bugTitle).tag(FeedbackKind.bug)
                        Text(strings.featureTitle).tag(FeedbackKind.feature)
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)

                    VStack(alignment: .leading, spacing: 8) {
                        Text(strings.messageLabel)
                            .font(.headline)
                        ZStack(alignment: .topLeading) {
                            TextEditor(text: $message)
                                .font(.body)
                                .scrollContentBackground(.hidden)
                                .padding(6)
                            if message.isEmpty {
                                Text(kind == .bug ? strings.bugPlaceholder : strings.featurePlaceholder)
                                    .foregroundStyle(.tertiary)
                                    .padding(.horizontal, 11)
                                    .padding(.top, 6)
                                    .allowsHitTesting(false)
                            }
                        }
                        .frame(minHeight: 145)
                        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 9))
                        .overlay {
                            RoundedRectangle(cornerRadius: 9)
                                .strokeBorder(.separator, lineWidth: 1)
                        }
                        Text(String(format: strings.charactersFormat, count))
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(count > 2_000 ? .red : .secondary)
                            .frame(maxWidth: .infinity, alignment: .trailing)
                    }

                    VStack(alignment: .leading, spacing: 5) {
                        Toggle(strings.includeDiagnostics, isOn: $includeDiagnostics)
                        Text(strings.includeDiagnosticsCaption)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    VStack(alignment: .leading, spacing: 12) {
                        Label(strings.whatSentTitle, systemImage: "eye")
                            .font(.headline)
                        Label(strings.whatSentBasic, systemImage: "text.alignleft")
                        if includeDiagnostics {
                            Label(strings.whatSentDiagnostics, systemImage: "info.circle")
                            diagnosticsPreview
                                .padding(.leading, 26)
                        }
                        Divider()
                        Label(strings.privacyNote, systemImage: "hand.raised")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Label(strings.retentionNote, systemImage: "clock")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(16)
                    .background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 12))
                }
                .padding(24)
            }

            Divider()
            HStack(spacing: 12) {
                if let errorMessage {
                    Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(.red)
                        .lineLimit(2)
                }
                Spacer()
                if isSending {
                    ProgressView()
                        .controlSize(.small)
                    Text(strings.sending)
                        .foregroundStyle(.secondary)
                }
                Button(strings.sendButton) { send() }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .disabled(!canSend)
                    .keyboardShortcut(.return, modifiers: [.command])
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 16)
        }
        .onChange(of: message) { oldValue, newValue in
            if newValue.utf16.count > 2_000 {
                var limited = ""
                var units = 0
                for character in newValue {
                    let piece = String(character)
                    let pieceUnits = piece.utf16.count
                    if units + pieceUnits > 2_000 { break }
                    limited.append(contentsOf: piece)
                    units += pieceUnits
                }
                message = limited.isEmpty ? oldValue : limited
            }
            if errorMessage != nil { errorMessage = nil }
        }
    }

    private var diagnosticsPreview: some View {
        Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 5) {
            diagnosticRow("Vorssaint", "\(diagnostics.appVersion) (\(diagnostics.appBuild))")
            diagnosticRow("macOS", diagnostics.macOS)
            if let model = diagnostics.macModel { diagnosticRow("Mac", model) }
            diagnosticRow(l10n.s.languageLabel, diagnostics.language)
            diagnosticRow(l10n.s.betaBadgeLabel, diagnostics.isBeta ? "✓" : "○")
            diagnosticRow(strings.diagnosticsChannelLabel,
                          diagnostics.updateChannel.replacingOccurrences(of: "-", with: " ").capitalized)
        }
        .font(.caption.monospaced())
        .foregroundStyle(.secondary)
    }

    private func diagnosticRow(_ label: String, _ value: String) -> some View {
        GridRow {
            Text(label).foregroundStyle(.tertiary)
            Text(value).textSelection(.enabled)
        }
    }

    private var sentView: some View {
        VStack(spacing: 14) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 54))
                .foregroundStyle(.green)
            Text(strings.sentTitle)
                .font(.title2.weight(.semibold))
            Text(strings.sentCaption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 400)
            Button(strings.done, action: onClose)
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .padding(.top, 8)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(40)
    }

    private func send() {
        guard canSend else { return }
        isSending = true
        errorMessage = nil
        Task {
            do {
                try await FeedbackService.shared.submit(
                    kind: kind,
                    message: message,
                    diagnostics: includeDiagnostics ? diagnostics : nil
                )
                wasSent = true
                message = ""
            } catch FeedbackError.rateLimited {
                errorMessage = strings.rateLimitError
            } catch FeedbackError.unavailable {
                errorMessage = strings.unavailableError
            } catch {
                errorMessage = strings.genericError
            }
            isSending = false
        }
    }
}
