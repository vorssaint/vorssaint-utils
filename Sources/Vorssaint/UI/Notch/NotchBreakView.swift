// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import SwiftUI

struct NotchBreakView: View {
    let title: String
    let seconds: Int
    let shownAt: Date

    var body: some View {
        VStack(spacing: 6) {
            Text(title).font(.system(size: 15, weight: .semibold)).foregroundStyle(.white)
                .lineLimit(2).multilineTextAlignment(.center)
            TimelineView(.periodic(from: shownAt, by: 1)) { context in
                let left = max(0, seconds - Int(context.date.timeIntervalSince(shownAt)))
                Text("\(left)").font(.system(size: 28, weight: .light).monospacedDigit()).foregroundStyle(.white)
            }
        }
        .frame(maxWidth: .infinity)
    }
}

struct NotchBreakActions: View {
    let text: BreakReminderStrings
    let respond: (BreakAction) -> Void

    var body: some View {
        HStack(spacing: 8) {
            Button(text.done) { respond(.done) }
            Button(text.snooze) { respond(.snooze) }
            Button(text.skip) { respond(.skip) }
        }
        .buttonStyle(.borderless)
        .foregroundStyle(.white)
    }
}
