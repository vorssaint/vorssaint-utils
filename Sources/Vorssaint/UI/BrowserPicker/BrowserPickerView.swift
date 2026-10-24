// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import SwiftUI

/// The picker: the link on top, then one compact row per browser or profile,
/// numbered for the keyboard.
struct BrowserPickerView: View {
    @ObservedObject var service: BrowserPickerService
    @ObservedObject private var l10n = L10n.shared

    private var strings: BrowserPickerStrings { FeatureStrings.browserPicker(l10n.language) }
    private static let rowHeight: CGFloat = 30
    private static let visibleRows = 10

    /// Ordered by distance from the pointer: the first choice next to it, the
    /// actions after the choices, the link it is about farthest away. Below the
    /// pointer that reads top down; above it the same order runs bottom up.
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if service.opensAbovePointer {
                link
                Divider().padding(.horizontal, 4)
                footer
                Divider().padding(.horizontal, 4)
                choices
            } else {
                choices
                Divider().padding(.horizontal, 4)
                footer
                Divider().padding(.horizontal, 4)
                link
            }
        }
        .padding(8)
        .frame(width: 300)
        .background(HUDBackdrop(cornerRadius: 14, contrast: .high))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .accessibilityElement(children: .contain)
        .accessibilityLabel(strings.featureName)
    }

    /// The link and, when there is one, why the picker is asking about it.
    private var link: some View {
        VStack(alignment: .leading, spacing: 6) {
            header
            if let notice = service.pickerNotice {
                Label(notice, systemImage: "exclamationmark.triangle.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 6)
            }
        }
        .padding(service.opensAbovePointer ? .top : .bottom, 2)
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            VStack(alignment: .leading, spacing: 1) {
                Text(service.pendingURL.flatMap(BrowserPickerRules.host(of:)) ?? strings.featureName)
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)
                    .truncationMode(.middle)
                if let rest = remainder, !rest.isEmpty {
                    Text(rest)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
            Spacer(minLength: 4)
            if service.queuedCount > 0 {
                Text(String(format: strings.moreLinksFormat, service.queuedCount))
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(.quaternary, in: Capsule())
            }
        }
        .padding(.horizontal, 6)
        .help(service.pendingURL?.absoluteString ?? "")
    }

    /// Everything after the host, so a long link still shows where it goes.
    private var remainder: String? {
        guard let url = service.pendingURL else { return nil }
        var text = url.path(percentEncoded: false)
        if let query = url.query(percentEncoded: false) { text += "?" + query }
        return text == "/" ? nil : text
    }

    @ViewBuilder
    private var choices: some View {
        if service.choices.isEmpty {
            Text(strings.noBrowsers)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, minHeight: 44)
        } else {
            choiceList
        }
    }

    private var choiceList: some View {
        let numbered = Array(service.choices.enumerated())
        return ScrollViewReader { proxy in
            ScrollView {
                VStack(spacing: 1) {
                    ForEach(service.opensAbovePointer ? numbered.reversed() : numbered, id: \.element.id) { index, choice in
                        row(choice, index: index).id(index)
                    }
                }
            }
            .defaultScrollAnchor(service.opensAbovePointer ? .bottom : .top)
            .scrollIndicators(service.choices.count > Self.visibleRows ? .automatic : .never)
            .frame(height: CGFloat(min(service.choices.count, Self.visibleRows)) * (Self.rowHeight + 1))
            .onChange(of: service.highlighted) { _, index in proxy.scrollTo(index) }
        }
    }

    private func row(_ choice: BrowserPickerChoice, index: Int) -> some View {
        let selected = index == service.highlighted
        return Button {
            service.choose(index, remember: NSEvent.modifierFlags.contains(.option))
        } label: {
            HStack(spacing: 8) {
                Image(nsImage: BrowserPickerIcons.icon(for: choice.appURL))
                    .resizable()
                    .frame(width: 20, height: 20)
                Text(choice.title)
                    .font(.system(size: 13))
                    .lineLimit(1)
                if let subtitle = choice.subtitle {
                    Text(subtitle)
                        .font(.system(size: 11))
                        .foregroundStyle(selected ? Color.white.opacity(0.75) : .secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 4)
                if index < 9 {
                    Text("\(index + 1)")
                        .font(.system(size: 11, weight: .medium).monospacedDigit())
                        .foregroundStyle(selected ? Color.white.opacity(0.8) : Color.secondary.opacity(0.7))
                }
            }
            .foregroundStyle(selected ? Color.white : Color.primary)
            .padding(.horizontal, 8)
            .frame(height: Self.rowHeight)
            .background(selected ? Color.accentColor : .clear,
                        in: RoundedRectangle(cornerRadius: 7, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { if $0 { service.highlighted = index } }
        .help(strings.rememberHint)
        .accessibilityLabel(choice.subtitle.map { "\(choice.title), \($0)" } ?? choice.title)
        .accessibilityHint(strings.rememberHint)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private var footer: some View {
        HStack(spacing: 4) {
            Button {
                service.addRuleForPendingLink()
            } label: {
                Label(strings.addRuleFromLink, systemImage: "plus")
                    .lineLimit(1)
            }
            .disabled(service.choices.isEmpty || service.pendingURL.flatMap(BrowserPickerRules.suggestedSite(for:)) == nil)
            Spacer(minLength: 4)
            Button {
                service.copyPendingLink()
            } label: {
                Image(systemName: "doc.on.doc")
            }
            .help(strings.copyLink)
            .accessibilityLabel(strings.copyLink)
        }
        .buttonStyle(.borderless)
        .font(.system(size: 12))
        .foregroundStyle(.secondary)
        .padding(.horizontal, 6)
        .padding(.bottom, 1)
    }
}

/// App icons are looked up once per app; the picker asks for them on every
/// render.
enum BrowserPickerIcons {
    private static var cache: [URL: NSImage] = [:]

    static func icon(for appURL: URL) -> NSImage {
        if let icon = cache[appURL] { return icon }
        let icon = NSWorkspace.shared.icon(forFile: appURL.path)
        cache[appURL] = icon
        return icon
    }

    /// Menus draw an image at its own size, so they get a small copy.
    static func menuIcon(for appURL: URL) -> NSImage {
        let small = icon(for: appURL).copy() as? NSImage ?? NSImage()
        small.size = NSSize(width: 16, height: 16)
        return small
    }
}
