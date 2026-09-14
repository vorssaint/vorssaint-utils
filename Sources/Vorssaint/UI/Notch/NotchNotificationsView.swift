// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import SwiftUI

struct NotchNotificationsView: View {
    @ObservedObject private var service = NotchNotificationService.shared
    @ObservedObject private var permissions = Permissions.shared
    @ObservedObject private var l10n = L10n.shared
    private var text: NotchNotificationStrings { FeatureStrings.notchNotifications(l10n.language) }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if !permissions.accessibility {
                PermissionRow(kind: .accessibility)
                Text(text.privacy).font(.callout).foregroundStyle(.white.opacity(0.7))
            } else if service.items.isEmpty {
                VStack(spacing: 14) {
                    Image(systemName: "bell").font(.system(size: 30)).foregroundStyle(.white.opacity(0.6))
                    Text(service.monitoring ? text.empty : text.waiting).font(.headline)
                    Text(text.privacy).font(.caption).foregroundStyle(.white.opacity(0.65))
                }
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 12) {
                        ForEach(service.items) { item in
                            NotchNotificationRow(item: item, service: service, text: text)
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .environment(\.locale, Locale(identifier: l10n.language.rawValue))
    }
}

private struct NotchNotificationRow: View {
    let item: NotchSystemNotification
    @ObservedObject var service: NotchNotificationService
    let text: NotchNotificationStrings
    @State private var feedback: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                NotchNotificationAppIcon(app: item.content.app, size: 22)
                Text(item.content.app.isEmpty ? text.title : item.content.app)
                    .lineLimit(1)
                Spacer(minLength: 8)
                Text(item.received, format: .dateTime.hour().minute()).monospacedDigit()
                Button { service.dismiss(item.id) } label: { Image(systemName: "xmark") }
                    .buttonStyle(.plain).help(text.dismiss).accessibilityLabel(text.dismiss)
                    .disabled(service.openingID == item.id)
            }.font(.caption).foregroundStyle(.white.opacity(0.6))
            Text(item.content.title).font(.system(size: 14, weight: .semibold)).lineLimit(2)
            if !item.content.subtitle.isEmpty { Text(item.content.subtitle).font(.callout).lineLimit(2) }
            if !item.content.body.isEmpty {
                Text(item.content.body).font(.callout).foregroundStyle(.white.opacity(0.8))
                    .lineLimit(5).textSelection(.enabled)
            }
            if service.canOpen(item) {
                Button(text.open) {
                    feedback = nil
                    service.open(item.id) { result in
                        if result == .unavailable || result == .uncertain { feedback = text.unavailable }
                    }
                }
                .buttonStyle(.bordered).controlSize(.small).disabled(service.openingID != nil)
            }
            if service.openingID == item.id { ProgressView().controlSize(.small) }
            if let feedback { Text(feedback).font(.caption).foregroundStyle(.white.opacity(0.7)) }
            else if service.unavailableID == item.id {
                Text(text.unavailable).font(.caption).foregroundStyle(.white.opacity(0.7))
            }
        }
        .padding(14)
        .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 14))
    }
}

struct NotchNotificationAppIcon: View {
    let app: String
    let size: CGFloat
    @ObservedObject private var service = NotchNotificationService.shared

    var body: some View {
        Group {
            if let icon = service.icon(for: app) {
                Image(nsImage: icon).resizable().scaledToFit()
            } else {
                Image(systemName: "bell.badge.fill")
                    .font(.system(size: size * 0.48, weight: .medium))
                    .foregroundStyle(.white.opacity(0.85))
                    .frame(width: size, height: size)
                    .background(.white.opacity(0.09), in: RoundedRectangle(cornerRadius: size * 0.24))
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}
