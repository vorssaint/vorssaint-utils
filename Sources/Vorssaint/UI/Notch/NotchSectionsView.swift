// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import SwiftUI

/// An in-place destination gallery. It only observes navigation, never the
/// contents or services of the sections represented by its buttons.
struct NotchSectionsView: View {
    @ObservedObject var service: NotchService
    @ObservedObject private var l10n = L10n.shared
    @FocusState private var searching: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorSchemeContrast) private var contrast
    private var text: NotchStrings { FeatureStrings.notch(l10n.language) }
    private var sections: [NotchModule] { service.filteredSections }

    var body: some View {
        VStack(spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField(text.searchSections, text: Binding(get: { service.sectionQuery }, set: service.searchSections))
                    .textFieldStyle(.plain)
                    .font(.system(size: 12))
                    .focused($searching)
                    .accessibilityLabel(text.searchSections)
                if !service.sectionQuery.isEmpty {
                    Button { service.searchSections(""); searching = true } label: {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(l10n.s.actionClear)
                }
            }
            .padding(.horizontal, 12)
            .frame(height: NotchLayout.sectionSearchHeight)
            .background(.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 12))

            if sections.isEmpty {
                NotchEmptyView(symbol: "magnifyingglass", message: FeatureStrings.clipboard(l10n.language).noResults)
                    .frame(maxHeight: .infinity)
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        Group {
                            if service.sectionQuery.isEmpty {
                                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: NotchLayout.sectionSpacing),
                                                          count: service.geometry.sectionColumns), spacing: NotchLayout.sectionSpacing) {
                                    ForEach(sections) { module in tile(module).id(module) }
                                }
                            } else {
                                LazyVStack(spacing: NotchLayout.sectionSpacing) {
                                    ForEach(sections) { module in tile(module).id(module) }
                                }
                            }
                        }
                        .padding(2)
                    }
                    .scrollIndicators(.automatic)
                    .onAppear {
                        if let target = service.highlightedSection { proxy.scrollTo(target, anchor: .center) }
                    }
                    .onChange(of: service.highlightedSection) { _, target in
                        guard let target else { return }
                        withAnimation(reduceMotion ? nil : .easeOut(duration: 0.16)) {
                            proxy.scrollTo(target, anchor: .center)
                        }
                    }
                }
            }
            Text(text.sectionKeyboardHint)
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .frame(height: 14)
                .opacity(sections.isEmpty ? 0 : 1)
                .accessibilityHidden(sections.isEmpty)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .onAppear { searching = true }
        .onChange(of: sections) { _, visible in
            if !visible.contains(where: { $0 == service.highlightedSection }) {
                service.highlightedSection = visible.first
            }
        }
    }

    private func tile(_ module: NotchModule) -> some View {
        let asRow = !service.sectionQuery.isEmpty
        let highlighted = service.highlightedSection == module
        let current = service.selected == module
        let shape = RoundedRectangle(cornerRadius: 16, style: .continuous)
        return Button { service.select(module) } label: {
            let layout = asRow ? AnyLayout(HStackLayout(spacing: 12)) : AnyLayout(VStackLayout(spacing: 6))
            layout {
                Image(systemName: module.symbol)
                    .font(.system(size: 22, weight: .medium))
                    .foregroundStyle(tint(for: module))
                    .frame(width: 25, height: 25)
                Text(module.title(l10n.language))
                    .font(.system(size: 11, weight: .medium))
                    .lineLimit(2)
                    .minimumScaleFactor(0.85)
                    .multilineTextAlignment(asRow ? .leading : .center)
                    .frame(maxWidth: asRow ? .infinity : nil, alignment: asRow ? .leading : .center)
                    .frame(height: 27)
                Text("⌥⌘" + module.shortcutKey.uppercased())
                    .font(.system(size: 10, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.6))
            }
            .padding(.horizontal, asRow ? 14 : 6)
            .frame(maxWidth: .infinity)
            .frame(height: asRow ? NotchLayout.sectionResultHeight : NotchLayout.sectionTileHeight)
            .background(.white.opacity(highlighted ? 0.12 : 0.045), in: shape)
            .overlay {
                shape.strokeBorder(.white.opacity(highlighted ? 0.55 : contrast == .increased ? 0.4 : 0.04), lineWidth: 1)
            }
            .overlay(alignment: .topTrailing) {
                if current, !asRow {
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
