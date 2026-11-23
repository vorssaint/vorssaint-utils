// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import SwiftUI

struct NotchNotificationsView: View {
    let size: CGSize
    @ObservedObject private var service = NotchNotificationService.shared
    @ObservedObject private var permissions = Permissions.shared
    @ObservedObject private var l10n = L10n.shared
    private var text: NotchNotificationStrings { FeatureStrings.notchNotifications(l10n.language) }

    var body: some View {
        Group {
            if !permissions.accessibility {
                VStack(alignment: .leading, spacing: 10) {
                    PermissionRow(kind: .accessibility)
                    Text(text.privacy).font(.callout).foregroundStyle(.white.opacity(0.7))
                        .fixedSize(horizontal: false, vertical: true)
                }
            } else if service.items.isEmpty {
                HStack(spacing: 14) {
                    Image(systemName: "bell").font(.system(size: 26, weight: .light)).foregroundStyle(.white.opacity(0.6))
                        .frame(width: 56, height: 56)
                        .background(.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                    VStack(alignment: .leading, spacing: 4) {
                        Text(service.monitoring ? text.empty : text.waiting).font(.headline)
                        Text(text.privacy).font(.caption).foregroundStyle(.white.opacity(0.65))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                let rows = NotchLayout.railRows(count: service.items.count,
                                                perRow: NotchLayout.railCapacity(width: size.width, itemWidth: 240, spacing: 8),
                                                rowHeight: 120, spacing: 8, height: size.height)
                let cardHeight = (size.height - CGFloat(rows - 1) * 8) / CGFloat(rows)
                NotchRail(items: service.items, rows: rows, itemWidth: 240, width: size.width) { item in
                    NotchNotificationRow(item: item, service: service, text: text)
                        .frame(height: cardHeight)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .environment(\.locale, l10n.language.formattingLocale())
    }
}

/// The page shows only the cards, so clearing sits in the island's header
/// like the captures page's. Observes the inbox on its own, so a new message
/// does not redraw the island.
struct NotchClearNotificationsButton: View {
    @ObservedObject private var notifications = NotchNotificationService.shared
    @ObservedObject private var l10n = L10n.shared

    var body: some View {
        NotchIconButton(symbol: "trash", title: FeatureStrings.notchNotifications(l10n.language).clearAll,
                        action: Self.confirmClearAboveIsland)
            .disabled(notifications.items.isEmpty || notifications.openingID != nil)
    }

    /// With the system banner dismissed, a banner shown while the island was
    /// closed may never reach Notification Center before macOS 27, so the
    /// island can hold the only copy. Clearing asks first, above the island.
    static func confirmClearAboveIsland() {
        DispatchQueue.main.async {
            let l10n = L10n.shared
            let title = FeatureStrings.notchNotifications(l10n.language).clearAll
            guard NSAlert.confirmAboveIsland(title, message: "", action: title, destructive: true,
                                             cancel: l10n.s.uninstallerCancel) else { return }
            NotchNotificationService.shared.clearAll()
        }
    }
}

/// One card per message: its app and actions on top, the text below taking
/// whatever room the card has.
private struct NotchNotificationRow: View {
    let item: NotchSystemNotification
    @ObservedObject var service: NotchNotificationService
    let text: NotchNotificationStrings
    @State private var feedback: String?
    @ObservedObject private var l10n = L10n.shared
    @State private var draft = ""
    @State private var opening = false
    @State private var sending = false
    @FocusState private var typing: Bool
    private var replyText: NotificationReplyStrings { NotificationReplyStrings.localized(l10n.language) }
    private var replying: Bool { service.replyingID == item.id }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                NotchNotificationAppIcon(app: item.content.app, size: 18)
                Text(item.content.app.isEmpty ? text.title : item.content.app)
                    .lineLimit(1)
                Spacer(minLength: 4)
                Text(item.received, format: .dateTime.hour().minute()).monospacedDigit()
                if service.openingID == item.id {
                    ProgressView().controlSize(.mini)
                } else if service.canOpen(item) {
                    NotchIconButton(symbol: "arrow.up.forward.app", title: text.open) {
                        feedback = nil
                        service.open(item.id) { result in
                            if result == .unavailable || result == .uncertain { feedback = text.unavailable }
                        }
                    }
                    .disabled(service.openingID != nil)
                }
                NotchIconButton(symbol: "xmark", title: text.dismiss) { service.dismiss(item.id) }
                    .disabled(service.openingID == item.id)
            }
            .font(.system(size: 11)).foregroundStyle(.white.opacity(0.6))
            .frame(height: 22)
            Text(item.content.title).font(.system(size: 13, weight: .semibold)).lineLimit(2)
            if !item.content.subtitle.isEmpty { Text(item.content.subtitle).font(.system(size: 12)).lineLimit(1) }
            if !item.content.body.isEmpty {
                Text(item.content.body).font(.system(size: 12)).foregroundStyle(.white.opacity(0.8))
                    .lineLimit(replying ? 1 : nil)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            } else {
                Spacer(minLength: 0)
            }
            if let message = feedback ?? (service.unavailableID == item.id ? text.unavailable : nil) {
                Text(message).font(.caption).foregroundStyle(.orange).lineLimit(2)
                if message == replyText.unavailable {
                    Button(replyText.keepAlerts) { service.openAlertSettings(item.id) }
                        .buttonStyle(.plain).font(.caption.weight(.semibold)).foregroundStyle(.white.opacity(0.85))
                }
            }
            if replying {
                composer
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
            } else if item.canReply {
                replyPill
                    .transition(.opacity)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 14))
        .clipped()
        .animation(.spring(duration: 0.28, bounce: 0.15), value: replying)
        .accessibilityElement(children: .contain)
        .onDisappear { if replying { service.cancelReply(item.id) } }
    }

    /// Reply, under every message its app lets you answer from the notification.
    private var replyPill: some View {
        Button {
            feedback = nil
            opening = true
            service.beginReply(item.id) { opened in
                opening = false
                if opened { typing = true } else { feedback = replyText.unavailable }
            }
        } label: {
            HStack(spacing: 5) {
                if opening { ProgressView().controlSize(.mini) }
                else { Image(systemName: "arrowshape.turn.up.left.fill").font(.system(size: 10, weight: .semibold)) }
                Text(replyText.reply).font(.system(size: 11, weight: .semibold))
            }
            .padding(.horizontal, 11)
            .frame(height: 24)
            .background(.white.opacity(0.12), in: Capsule())
            .contentShape(Capsule())
        }
        .buttonStyle(NotchButtonStyle(cornerRadius: 12))
        .disabled(opening || service.replyingID != nil)
        .help(replyText.reply)
    }

    /// The reply box, sent through the app's own reply in its notification.
    private var composer: some View {
        HStack(spacing: 6) {
            TextField(replyText.placeholder, text: $draft)
                .textFieldStyle(.plain)
                .font(.system(size: 12))
                .focused($typing)
                .onSubmit(send)
                .onExitCommand { service.cancelReply(item.id); draft = "" }
                .padding(.horizontal, 10)
                .frame(height: 28)
                .background(.white.opacity(0.1), in: Capsule())
            Button(action: send) {
                Group {
                    if sending { ProgressView().controlSize(.mini) }
                    else { Image(systemName: "arrow.up").font(.system(size: 12, weight: .bold)) }
                }
                .foregroundStyle(.black)
                .frame(width: 28, height: 28)
                .background(Circle().fill(.white.opacity(draft.trimmingCharacters(in: .whitespaces).isEmpty ? 0.35 : 0.95)))
            }
            .buttonStyle(.plain)
            .disabled(sending || draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            .help(replyText.send)
            NotchIconButton(symbol: "xmark", title: FeatureStrings.clipboard(l10n.language).cancel) {
                service.cancelReply(item.id)
                draft = ""
            }
        }
    }

    private func send() {
        let message = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !message.isEmpty, !sending else { return }
        sending = true
        service.sendReply(item.id, text: message) { sent in
            sending = false
            if sent { draft = ""; feedback = nil } else { feedback = replyText.unavailable }
        }
    }
}

/// A banner held open under the pointer: the whole message with its actions,
/// laid out with the fonts and limits the service measured it with.
struct NotchNotificationPreviewView: View {
    let notice: NotchNotice
    let content: NotchNotificationContent
    @ObservedObject var service: NotchService
    @ObservedObject private var notifications = NotchNotificationService.shared
    @ObservedObject private var l10n = L10n.shared
    private var text: NotchNotificationStrings { FeatureStrings.notchNotifications(l10n.language) }
    private var item: NotchSystemNotification? {
        notifications.items.first { $0.id == notice.notificationID }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: NotchNotificationPreviewLayout.spacing) {
            HStack(spacing: 8) {
                NotchNotificationAppIcon(app: content.app, size: NotchNotificationPreviewLayout.iconSize)
                Text(content.app.isEmpty ? text.title : content.app)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.7))
                    .lineLimit(1)
                Spacer(minLength: 8)
                if let item {
                    Text(item.received, format: .dateTime.hour().minute())
                        .font(.system(size: 11)).monospacedDigit()
                        .foregroundStyle(.white.opacity(0.45))
                }
                NotchIconButton(symbol: "xmark", title: text.dismiss) { service.dismissNotification(notice) }
            }
            .frame(height: NotchNotificationPreviewLayout.headerHeight)
            // Earlier messages of the same chat, oldest first, quieter than the newest.
            ForEach(Array(notice.earlier.enumerated()), id: \.offset) { _, message in
                NotchNotificationStackRow(message: message)
                    .transition(.asymmetric(insertion: .opacity.combined(with: .move(edge: .bottom)), removal: .opacity))
            }
            if !content.title.isEmpty {
                Text(content.title)
                    .font(Font(NotchNotificationPreviewLayout.titleFont as CTFont))
                    .lineLimit(NotchNotificationPreviewLayout.titleLines)
            }
            if !content.subtitle.isEmpty {
                Text(content.subtitle)
                    .font(Font(NotchNotificationPreviewLayout.subtitleFont as CTFont))
                    .foregroundStyle(.white.opacity(0.9))
                    .lineLimit(NotchNotificationPreviewLayout.subtitleLines)
            }
            if !content.body.isEmpty {
                Text(content.body)
                    .font(Font(NotchNotificationPreviewLayout.bodyFont as CTFont))
                    .foregroundStyle(.white.opacity(0.82))
                    .lineLimit(NotchNotificationPreviewLayout.bodyLines)
                    .textSelection(.enabled)
            }
            HStack(spacing: 8) {
                if let item, notifications.canOpen(item) {
                    Button(text.open) { service.openNotice(notice) }
                        .buttonStyle(.bordered).controlSize(.small)
                        .disabled(notifications.openingID != nil)
                }
                if notifications.openingID == notice.notificationID { ProgressView().controlSize(.small) }
                Spacer(minLength: 8)
                if notifications.items.count > 1 {
                    Button { service.open(.notifications) } label: {
                        HStack(spacing: 5) {
                            Image(systemName: "tray.full").font(.system(size: 11, weight: .medium))
                            Text(notifications.items.count, format: .number)
                                .font(.system(size: 11, weight: .semibold)).monospacedDigit()
                        }
                        .foregroundStyle(.white.opacity(0.8))
                        .padding(.horizontal, 10)
                        .frame(height: 24)
                        .contentShape(Capsule())
                    }
                    .buttonStyle(NotchButtonStyle(cornerRadius: 12))
                    .modifier(NotchControlSurface(cornerRadius: 12))
                    .help(text.title)
                    .accessibilityLabel(text.title)
                    .accessibilityValue(Text(notifications.items.count, format: .number))
                }
            }
            .frame(height: NotchNotificationPreviewLayout.actionHeight)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxHeight: .infinity, alignment: .top)
        .clipped()
        .animation(.spring(duration: NotchMotion.growingHeight.duration, bounce: NotchMotion.growingHeight.bounce),
                   value: notice.earlier.count)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(notice.accessibilityText)
        .environment(\.locale, l10n.language.formattingLocale())
    }
}

/// One earlier message in an open stack: who wrote it and its first lines.
struct NotchNotificationStackRow: View {
    let message: NotchNotificationContent

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(message.title.isEmpty ? message.app : message.title)
                .font(Font(NotchNotificationPreviewLayout.stackTitleFont as CTFont))
                .foregroundStyle(.white.opacity(0.7))
                .lineLimit(1)
            if !message.compactDetail.isEmpty {
                Text(message.compactDetail)
                    .font(Font(NotchNotificationPreviewLayout.stackBodyFont as CTFont))
                    .foregroundStyle(.white.opacity(0.55))
                    .lineLimit(NotchNotificationPreviewLayout.stackBodyLines)
            }
        }
        .padding(NotchNotificationPreviewLayout.stackRowPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .accessibilityElement(children: .combine)
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
