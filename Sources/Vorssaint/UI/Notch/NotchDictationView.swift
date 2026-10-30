// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import SwiftUI

/// An opaque recording surface. The island's native host owns its geometry;
/// fixed frequency bars respond in place to microphone audio.
struct NotchDictationView: View {
    let topInset: CGFloat
    @ObservedObject var speech = DictationService.shared
    @ObservedObject private var l10n = L10n.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private var text: DictationStrings { .localized(l10n.language) }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: symbol)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(speech.phase == .failed ? Color.orange.opacity(0.9) : Color.white.opacity(0.9))
                    .frame(width: 22).accessibilityHidden(true)
                Text(title).font(.system(size: 13, weight: .semibold)).lineLimit(1)
                Spacer(minLength: 8)
                if speech.phase == .recording {
                    Text(Duration.seconds(speech.elapsed).formatted(.time(pattern: .minuteSecond)))
                        .font(.system(size: 12, weight: .medium, design: .rounded)).monospacedDigit()
                        .foregroundStyle(.white.opacity(0.55)).frame(width: 44)
                        .padding(.vertical, 5).background(.white.opacity(0.045), in: Capsule())
                        .accessibilityLabel("Elapsed time")
                    Button(action: speech.finish) {
                        Image(systemName: "stop.fill").font(.system(size: 9, weight: .medium))
                            .foregroundStyle(.white.opacity(0.95)).frame(width: 28, height: 28)
                            .background(.white.opacity(0.1), in: Circle()).contentShape(Circle())
                    }.buttonStyle(.plain).help(text.stop).accessibilityLabel(text.stop)
                } else if speech.phase == .processing || speech.phase == .requestingPermission {
                    ProgressView().controlSize(.mini).tint(.white.opacity(0.7))
                } else {
                    icon("clock.arrow.circlepath", title: text.history, action: openHistory)
                }
                icon("xmark", title: text.cancel) {
                    if speech.phase.isBusy { speech.cancel() } else { speech.dismiss() }
                }
            }.frame(height: 28)

            if speech.phase == .recording {
                VStack(spacing: 7) {
                    DictationWaveform(bars: speech.waveform).frame(height: 32)
                    HStack(spacing: 4) {
                        Text("esc").font(.system(size: 8, weight: .medium, design: .rounded))
                            .padding(.horizontal, 4).padding(.vertical, 2)
                            .overlay(RoundedRectangle(cornerRadius: 3).stroke(.white.opacity(0.12), lineWidth: 0.5))
                        Text("to cancel").font(.system(size: 9))
                        Spacer()
                        Circle().fill(Color(red: 0.92, green: 0.35, blue: 0.32)).frame(width: 3, height: 3)
                        Text("On this Mac").font(.system(size: 9))
                    }.foregroundStyle(.white.opacity(0.35))
                }
            } else if speech.phase == .failed {
                HStack(alignment: .top, spacing: 8) {
                    Text(speech.error ?? text.failed).font(.system(size: 11)).foregroundStyle(.white.opacity(0.6))
                        .lineLimit(4).frame(maxWidth: .infinity, alignment: .leading)
                    if !speech.result.isEmpty { icon("doc.on.doc", title: text.copied, action: speech.copyResult) }
                    icon("gearshape", title: text.title, action: showSettings)
                }
            } else if speech.phase == .completed {
                Button(action: openHistory) {
                    Text(speech.result).font(.system(size: 12, weight: .regular)).foregroundStyle(.white.opacity(0.62))
                        .lineLimit(2).multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
                }.buttonStyle(.plain).help(text.history)
            } else {
                Text(speech.phase == .requestingPermission ? "Waiting for microphone permission…" : "Preparing your text…")
                    .font(.system(size: 11)).foregroundStyle(.white.opacity(0.42))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.horizontal, 24).padding(.top, topInset + 10).padding(.bottom, 16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Color.black).accessibilityIdentifier("notch.dictation")
        .animation(reduceMotion ? nil : .easeOut(duration: 0.18), value: speech.phase)
    }

    private func icon(_ symbol: String, title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 10, weight: .semibold)).foregroundStyle(.white.opacity(0.55))
                .frame(width: 26, height: 26)
                .background(.white.opacity(0.065), in: Circle())
                .overlay(Circle().stroke(.white.opacity(0.045), lineWidth: 0.5)).contentShape(Circle())
        }.buttonStyle(.plain).help(title).accessibilityLabel(title)
    }
    private var title: String {
        switch speech.phase {
        case .recording: return text.recording
        case .processing: return text.processing
        case .completed: return speech.status
        case .failed: return text.failed
        case .idle, .requestingPermission: return text.title
        }
    }
    private var symbol: String {
        switch speech.phase {
        case .completed: return "checkmark"
        case .failed: return "exclamationmark.circle"
        case .processing: return "waveform"
        default: return "mic"
        }
    }
    private func openHistory() {
        guard !speech.phase.isBusy else { return }
        speech.dismiss()
        NotchService.shared.open(.dictation)
    }
    private func showSettings() {
        speech.dismiss()
        SettingsRouter.shared.request(FeatureSettingsDestination(.dictation))
        (NSApp.delegate as? AppDelegate)?.openSettingsWindow()
    }
}

struct DictationWaveform: View {
    let bars: [Double]
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(alignment: .center, spacing: 4) {
            ForEach(bars.indices, id: \.self) { index in
                Capsule()
                    .fill(.white.opacity(0.28 + bars[index] * 0.58))
                    .frame(width: 3, height: 3 + bars[index] * 27)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .animation(reduceMotion ? nil : .interpolatingSpring(stiffness: 260, damping: 25), value: bars)
        .accessibilityHidden(true)
    }
}
