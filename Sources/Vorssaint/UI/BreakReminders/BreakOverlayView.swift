// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import SwiftUI

struct BreakOverlayView: View {
    let title: String
    let symbol: String
    let kind: BreakKind
    let seconds: Int
    let shownAt: Date
    let breathing: Bool
    let text: BreakReminderStrings
    let respond: (BreakAction) -> Void

    var body: some View {
        ZStack {
            BreakOverlayBlur().ignoresSafeArea()
            Color.black.opacity(0.45).ignoresSafeArea()
            VStack(spacing: 28) {
                if breathing {
                    BreathingGuide(shownAt: shownAt, text: text)
                } else {
                    Image(systemName: symbol)
                        .font(.system(size: 72, weight: .light))
                        .foregroundStyle(.white.opacity(0.9))
                }
                Text(title).font(.system(size: 34, weight: .semibold)).foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                if kind == .eyes && !breathing {
                    FollowTheDot(shownAt: shownAt)
                }
                CountdownRing(seconds: seconds, shownAt: shownAt, doneLabel: text.done)
                HStack(spacing: 12) {
                    Button(text.done) { respond(.done) }
                    Button(text.snooze) { respond(.snooze) }
                    Button(text.skip) { respond(.skip) }
                }
                .controlSize(.large)
            }
            .padding(40)
        }
    }
}

/// Blurs whatever is behind the panel.
private struct BreakOverlayBlur: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .fullScreenUI
        view.blendingMode = .behindWindow
        view.state = .active
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}

/// A ring that drains over the break, with the seconds left inside.
private struct CountdownRing: View {
    let seconds: Int
    let shownAt: Date
    let doneLabel: String

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30)) { context in
            let elapsed = context.date.timeIntervalSince(shownAt)
            let total = max(1, Double(seconds))
            let fraction = max(0, 1 - elapsed / total)
            let left = max(0, seconds - Int(elapsed))
            ZStack {
                Circle().stroke(.white.opacity(0.15), lineWidth: 8)
                Circle()
                    .trim(from: 0, to: fraction)
                    .stroke(.white, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                Text(left > 0 ? "\(left)" : doneLabel)
                    .font(.system(size: left > 0 ? 44 : 22, weight: .light).monospacedDigit())
                    .foregroundStyle(.white)
            }
            .frame(width: 140, height: 140)
        }
    }
}

/// A dot gliding slowly side to side, to give the eyes something distant to follow.
private struct FollowTheDot: View {
    let shownAt: Date
    static let period: Double = 6

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30)) { context in
            let t = context.date.timeIntervalSince(shownAt)
            let x = sin(t * 2 * .pi / Self.period)
            ZStack {
                Capsule().fill(.white.opacity(0.12)).frame(width: 360, height: 4)
                Circle().fill(.white).frame(width: 16, height: 16).offset(x: x * 170)
            }
            .frame(width: 360, height: 20)
        }
    }
}

/// Four seconds in, four seconds out.
private struct BreathingGuide: View {
    let shownAt: Date
    let text: BreakReminderStrings
    static let half: Double = 4

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30)) { context in
            let t = context.date.timeIntervalSince(shownAt)
            let phase = t.truncatingRemainder(dividingBy: Self.half * 2)
            let inhaling = phase < Self.half
            let progress = inhaling ? phase / Self.half : 1 - (phase - Self.half) / Self.half
            let eased = (1 - cos(progress * .pi)) / 2
            VStack(spacing: 12) {
                Circle()
                    .fill(.white.opacity(0.25))
                    .overlay(Circle().stroke(.white.opacity(0.8), lineWidth: 2))
                    .frame(width: 60 + 90 * eased, height: 60 + 90 * eased)
                    .frame(width: 150, height: 150)
                Text(inhaling ? text.inhale : text.exhale)
                    .font(.system(size: 18, weight: .medium)).foregroundStyle(.white.opacity(0.85))
            }
        }
    }
}
