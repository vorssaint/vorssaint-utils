// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import SwiftUI

/// An in-place destination gallery. It only observes navigation, never the
/// contents or services of the sections represented by its buttons.
struct NotchSectionsView: View {
    @ObservedObject var service: NotchService
    @ObservedObject private var l10n = L10n.shared
    @Environment(\.colorSchemeContrast) private var contrast
    private var text: NotchStrings { FeatureStrings.notch(l10n.language) }
    private var sections: [NotchModule] { service.filteredSections }

    var body: some View {
        Group {
            if sections.isEmpty {
                NotchEmptyView(symbol: "magnifyingglass", message: FeatureStrings.clipboard(l10n.language).noResults)
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: NotchLayout.sectionSpacing),
                                                  count: service.geometry.sectionColumns),
                                  spacing: NotchLayout.sectionSpacing) {
                            ForEach(sections) { module in
                                tile(module).id(module.id)
                            }
                        }
                    }
                    .scrollIndicators(.automatic)
                    .onAppear {
                        if let section = service.highlightedSection { proxy.scrollTo(section.id) }
                    }
                    .onChange(of: service.highlightedSection) { _, section in
                        if let section { proxy.scrollTo(section.id) }
                    }
                }
                .accessibilityHint(text.sectionKeyboardHint)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .onChange(of: sections) { _, visible in
            if !visible.contains(where: { $0 == service.highlightedSection }) {
                service.highlightedSection = visible.first
            }
        }
    }

    private func tile(_ module: NotchModule) -> some View {
        let highlighted = service.highlightedSection == module
        let current = service.selected == module
        let shape = RoundedRectangle(cornerRadius: 16, style: .continuous)
        return Button { service.select(module) } label: {
            VStack(spacing: 6) {
                Image(systemName: module.symbol)
                    .font(.system(size: 22, weight: .medium))
                    .foregroundStyle(tint(for: module))
                    .frame(width: 25, height: 25)
                Text(module.title(l10n.language))
                    .font(.system(size: 11, weight: .medium))
                    .lineLimit(2)
                    .minimumScaleFactor(0.85)
                    .multilineTextAlignment(.center)
                    .frame(height: 27)
                Text("⌥⌘" + module.shortcutKey.uppercased())
                    .font(.system(size: 10, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.6))
            }
            .padding(.horizontal, 6)
            .frame(maxWidth: .infinity)
            .frame(height: NotchLayout.sectionTileHeight)
            .background(.white.opacity(highlighted ? 0.12 : 0.045), in: shape)
            .overlay {
                shape.strokeBorder(.white.opacity(highlighted ? 0.55 : contrast == .increased ? 0.4 : 0.04), lineWidth: 1)
            }
            .overlay(alignment: .topTrailing) {
                if current {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(.white.opacity(0.7))
                        .padding(7)
                }
            }
            .contentShape(shape)
        }
        .buttonStyle(NotchButtonStyle(cornerRadius: 16, lifts: false))
        .accessibilityLabel(module.title(l10n.language))
        .accessibilityAddTraits(current ? .isSelected : [])
        .accessibilityIdentifier("notch.module.\(module.rawValue)")
        .help(module.title(l10n.language) + "  ⌥⌘" + module.shortcutKey.uppercased())
    }

    private func tint(for module: NotchModule) -> Color {
        switch module {
        case .music: return .pink
        case .calendar: return .red
        case .timer: return .orange
        default: return .white.opacity(0.85)
        }
    }
}

/// The gallery's search lives in the header as a magnifier: the field
/// unfolds under the pointer or as soon as something is typed, since the
/// keyboard already goes to it while the gallery is open.
struct NotchSectionSearch: View {
    @ObservedObject var service: NotchService
    var maximumFieldWidth: CGFloat = 150
    @ObservedObject private var l10n = L10n.shared
    @FocusState private var searching: Bool
    @State private var hovered = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private var text: NotchStrings { FeatureStrings.notch(l10n.language) }
    private var expanded: Bool { hovered || !service.sectionQuery.isEmpty }

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(expanded ? .white : .white.opacity(0.55))
                .frame(width: 28, height: 28)
            // The field keeps its focus at a hair's width, so typing filters
            // the gallery before the field has even shown itself.
            TextField(text.searchSections, text: Binding(get: { service.sectionQuery }, set: service.searchSections))
                .textFieldStyle(.plain)
                .font(.system(size: 12))
                .focused($searching)
                .frame(width: expanded ? maximumFieldWidth : 1)
                .opacity(expanded ? 1 : 0)
                .accessibilityLabel(text.searchSections)
            if !service.sectionQuery.isEmpty {
                Button { service.searchSections(""); searching = true } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(l10n.s.actionClear)
            }
        }
        .padding(.trailing, expanded ? 8 : 0)
        .frame(height: 28)
        .background(.white.opacity(expanded ? 0.07 : 0), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
        .clipped()
        .onHover { hovering in
            withAnimation(reduceMotion ? nil : .easeOut(duration: 0.15)) { hovered = hovering }
        }
        .onTapGesture { searching = true }
        .onAppear { searching = true }
        .help(text.searchSections)
    }
}
