// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import SwiftUI

private struct SettingsFocusedFeatureKey: EnvironmentKey {
    static let defaultValue: AppFeature? = nil
}

extension EnvironmentValues {
    var settingsFocusedFeature: AppFeature? {
        get { self[SettingsFocusedFeatureKey.self] }
        set { self[SettingsFocusedFeatureKey.self] = newValue }
    }
}

struct FeaturePrimaryToggleModifier: ViewModifier {
    @Environment(\.settingsFocusedFeature) private var focusedFeature
    let feature: AppFeature

    @ViewBuilder
    func body(content: Content) -> some View {
        if focusedFeature != feature || feature.primaryEnabledKeys.isEmpty {
            content
        }
    }
}

struct SettingsIconTile: View {
    let symbol: String
    var size: CGFloat = 24
    var accentGroup: FeatureGroup? = nil
    @Environment(\.colorScheme) private var colorScheme

    private var usesBlackTileColor: Bool {
        ["dock.rectangle", "dock.arrow.down.rectangle", "macbook", "heart.fill"].contains(symbol)
    }

    private var color: Color {
        switch (accentGroup, symbol) {
        case (.energyDisplay, "bolt.fill"), (.energyDisplay, "moon.zzz.fill"),
             (.energyDisplay, "sun.max.fill"):
            return .orange
        case (.windowsDock, "rectangle.on.rectangle"),
             (.windowsDock, "rectangle.3.group"),
             (.windowsDock, "rectangle.split.3x1"):
            return .purple
        case (.mouseKeyboard, "rectangle.and.hand.point.up.left"):
            return .blue
        case (.mouseKeyboard, "cursorarrow.rays"):
            return .green
        case (.clipboardFiles, "finder"),
             (.clipboardFiles, "doc.on.clipboard"),
             (.clipboardFiles, "doc.plaintext"),
             (.clipboardFiles, "tray.full"),
             (.clipboardFiles, "externaldrive.badge.plus"):
            return .teal
        case (_, "arrow.down.app"):
            return .green
        case (_, "dock.rectangle"), (_, "dock.arrow.down.rectangle"), (_, "macbook"):
            return .black
        case (_, "camera.viewfinder"), (_, "screenshot"):
            return .gray
        case (_, "note.text"):
            return .yellow
        case (_, "record.circle"), (_, "trash"), (_, "xmark.octagon"), (_, "xmark.app"),
             (_, "xmark.circle"), (_, "heart.fill"):
            return .red
        case (_, "web.camera"):
            return .green
        default:
            return .accentColor
        }
    }

    var body: some View {
        symbolImage
            .frame(width: size, height: size)
            .background {
                if colorScheme == .dark {
                    RoundedRectangle(cornerRadius: size * 0.24, style: .continuous)
                        .fill(.black)
                } else {
                    RoundedRectangle(cornerRadius: size * 0.24, style: .continuous)
                        .fill(tileBackground(color))
                }
            }
            .shadow(color: color.opacity(0.18), radius: 1.5, y: 1)
            .accessibilityHidden(true)
    }

    private func tileBackground(_ color: Color) -> LinearGradient {
        LinearGradient(colors: [color.opacity(0.76), color, color.opacity(0.88)],
                       startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    @ViewBuilder
    private var symbolImage: some View {
        let symbolSize = symbol == AppFeature.middleClick.symbolName ? size * 0.62 : size * 0.5
        if colorScheme == .dark {
            Image(systemName: symbol)
                .font(.system(size: symbolSize, weight: .semibold))
                .symbolRenderingMode(.monochrome)
                .foregroundStyle(symbol == "heart.fill" ? color : (usesBlackTileColor ? .white : color))
        } else if symbol == "note.text", accentGroup == nil {
            Image(systemName: symbol)
                .font(.system(size: symbolSize, weight: .semibold))
                .symbolRenderingMode(.palette)
                .foregroundStyle(.black, .black.opacity(0.68), .black.opacity(0.38))
        } else {
            Image(systemName: symbol)
                .font(.system(size: symbolSize, weight: .semibold))
                .symbolRenderingMode(.palette)
                .foregroundStyle(.white, .white.opacity(0.76), .white.opacity(0.52))
        }
    }
}

struct SettingsFeatureHeader<Accessory: View>: View {
    let symbol: String
    let title: String
    let description: String?
    var accentGroup: FeatureGroup? = nil
    let accessory: Accessory
    var surface = true

    init(symbol: String, title: String, description: String?, accentGroup: FeatureGroup? = nil,
         surface: Bool = true,
         @ViewBuilder accessory: () -> Accessory) {
        self.symbol = symbol
        self.title = title
        self.description = description
        self.accentGroup = accentGroup
        self.surface = surface
        self.accessory = accessory()
    }

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            SettingsIconTile(symbol: symbol, size: 36, accentGroup: accentGroup)
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.title3.weight(.semibold))
                if let description, !description.isEmpty {
                    Text(description)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 12)
            accessory
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background {
            if surface {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(.quaternary.opacity(0.35))
            }
        }
    }
}

extension SettingsFeatureHeader where Accessory == EmptyView {
    init(symbol: String, title: String, description: String? = nil,
         accentGroup: FeatureGroup? = nil, surface: Bool = true) {
        self.init(symbol: symbol, title: title, description: description,
                  accentGroup: accentGroup, surface: surface) {
            EmptyView()
        }
    }
}

/// One grouped surface of related controls, matching the inset sections in
/// macOS System Settings.
struct SettingsCard<Content: View>: View {
    let title: String?
    let content: Content

    init(title: String? = nil, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let title {
                Text(title)
                    .font(.headline)
            }
            VStack(alignment: .leading, spacing: 0) {
                content
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(.quaternary.opacity(0.35),
                        in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Setting labels and continuation controls align after the reserved icon slot.
let settingsRowTextInset: CGFloat = 26 + 12

/// A plain setting label and optional explanation, with its control at the
/// trailing edge, like rows in macOS System Settings.
struct SettingsRow<Accessory: View>: View {
    let symbol: String?
    let title: String
    let badge: String?
    let caption: String?
    let accessory: Accessory

    init(symbol: String?, title: String, badge: String? = nil, caption: String? = nil,
         @ViewBuilder accessory: () -> Accessory) {
        self.symbol = symbol
        self.title = title
        self.badge = badge
        self.caption = caption
        self.accessory = accessory()
    }

    var body: some View {
        HStack(spacing: 12) {
            Group {
                if let symbol {
                    Image(systemName: symbol)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.secondary)
                } else {
                    Color.clear
                }
            }
            .frame(width: 26, height: 20)
            label
            Spacer(minLength: 12)
            accessory
        }
        .padding(.vertical, 7)
    }

    private var label: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                Text(title)
                if let badge {
                    Text(badge)
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(Color.white)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(Capsule().fill(Color.accentColor))
                        .accessibilityHidden(true)
                }
            }
            if let caption {
                Text(caption)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

/// A switch for an option that needs another feature. While it cannot be
/// used, its feature uninstalled or something else ruling it out, the option
/// reads greyed and off, since a disabled switch looks like one that is just
/// off, and a readable line under it says why.
struct SettingsFeatureSwitchRow: View {
    let symbol: String
    let title: String
    var caption: String? = nil
    @Binding var isOn: Bool
    let feature: AppFeature
    /// False while something else rules the option out, as the caption says.
    var enabled = true
    @ObservedObject private var l10n = L10n.shared
    @ObservedObject private var features = FeatureRuntime.shared

    var body: some View {
        let installed = features.isAvailable(feature)
        let usable = installed && enabled
        VStack(alignment: .leading, spacing: 6) {
            SettingsRow(symbol: symbol, title: title, caption: usable ? caption : nil) {
                Toggle(title, isOn: usable ? $isOn : .constant(false))
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .modifier(FeaturePrimaryToggleModifier(feature: feature))
            }
            .disabled(!usable)
            .saturation(usable ? 1 : 0)
            .opacity(usable ? 1 : 0.45)
            if !installed {
                HStack(spacing: 10) {
                    Text(feature.enableReason(l10n))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Button(FeatureStrings.notchEditor(l10n.language).openFeatures) { feature.showInFeatures() }
                        .controlSize(.small)
                }
                .padding(.leading, settingsRowTextInset)
            } else if !usable, let caption {
                Text(caption)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.leading, settingsRowTextInset)
            }
        }
    }
}

/// A row that picks one of a few options: segments beside the title while the
/// row fits on one line, under the title otherwise, and a menu there when the
/// segments don't fit either. A row wider than its column would center the page
/// and cut it on both sides.
struct SettingsChoiceRow<Value: Hashable, Options: View>: View {
    let symbol: String?
    let title: String
    @Binding var selection: Value
    let options: Options

    init(symbol: String?, title: String, selection: Binding<Value>, @ViewBuilder options: () -> Options) {
        self.symbol = symbol
        self.title = title
        _selection = selection
        self.options = options()
    }

    var body: some View {
        ViewThatFits(in: .horizontal) {
            SettingsRow(symbol: symbol, title: title) {
                picker.pickerStyle(.segmented).fixedSize()
            }
            VStack(alignment: .leading, spacing: 8) {
                SettingsRow(symbol: symbol, title: title) { EmptyView() }
                ViewThatFits(in: .horizontal) {
                    picker.pickerStyle(.segmented).fixedSize()
                    picker.pickerStyle(.menu).fixedSize()
                }
                .padding(.leading, settingsRowTextInset)
            }
        }
    }

    private var picker: some View {
        Picker(title, selection: $selection) { options }.labelsHidden()
    }
}

/// A row whose choice is a menu: beside the title while the row fits on one
/// line, under the title otherwise, lined up with its text, or with its icon
/// when the menu is wider than the text leaves room for. A menu kept beside a
/// title that has to wrap squeezes the title letter by letter, and a row
/// wider than its column would center the page and cut it on both sides.
struct SettingsMenuRow<Value: Hashable, Options: View>: View {
    let symbol: String?
    let title: String
    @Binding var selection: Value
    let options: Options

    init(symbol: String?, title: String, selection: Binding<Value>, @ViewBuilder options: () -> Options) {
        self.symbol = symbol
        self.title = title
        _selection = selection
        self.options = options()
    }

    var body: some View {
        ViewThatFits(in: .horizontal) {
            SettingsRow(symbol: symbol, title: title) { menu }
            VStack(alignment: .leading, spacing: 8) {
                SettingsRow(symbol: symbol, title: title) { EmptyView() }
                // Only the menu's width decides here: a title too long for one
                // line wraps above it either way.
                ViewThatFits(in: .horizontal) {
                    menu.padding(.leading, settingsRowTextInset)
                    menu
                }
            }
        }
    }

    private var menu: some View {
        Picker(title, selection: $selection) { options }.pickerStyle(.menu).labelsHidden().fixedSize()
    }
}

/// A switch pushed to the trailing edge with its label at the leading one,
/// so a shared control that carries its own label lines up with the rows
/// around it on a redesigned page.
struct TrailingSwitchToggleStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 12) {
            configuration.label
            Spacer(minLength: 12)
            Toggle(isOn: configuration.$isOn) { EmptyView() }
                .labelsHidden()
                .toggleStyle(.switch)
        }
    }
}
