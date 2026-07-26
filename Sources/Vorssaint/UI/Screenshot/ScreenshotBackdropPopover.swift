// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import SwiftUI
import UniformTypeIdentifiers

/// The backdrop picker: gradient presets, the user's saved customs, the
/// Mac's current wallpapers and any image from disk, plus a custom solid or
/// gradient builder and the margin and corner sliders. Everything applies
/// live; the save button keeps a custom look in the presets row.
struct ScreenshotBackdropPopover: View {
    @ObservedObject var model: ScreenshotEditorModel
    @ObservedObject private var l10n = L10n.shared

    @State private var wallpapers: [URL] = []
    @State private var customIsGradient = false
    @State private var solidComponents: [Double] = [0.20, 0.47, 0.96]
    @State private var gradientStartComponents: [Double] = [0.20, 0.47, 0.96]
    @State private var gradientEndComponents: [Double] = [0.45, 0.83, 0.98]
    /// Which well the inline palette paints: 0 = solid or gradient start,
    /// 1 = gradient end.
    @State private var activeWell = 0

    /// The inline palette, so picking a color never leaves the popover.
    private static let palette: [[Double]] = [
        [0.96, 0.26, 0.21], [1.00, 0.58, 0.00], [1.00, 0.80, 0.00], [0.55, 0.86, 0.25],
        [0.20, 0.78, 0.35], [0.10, 0.74, 0.61], [0.15, 0.78, 0.85], [0.04, 0.52, 1.00],
        [0.35, 0.34, 0.84], [0.69, 0.32, 0.87], [1.00, 0.45, 0.66], [0.91, 0.12, 0.39],
        [0.55, 0.39, 0.29], [0.11, 0.16, 0.32], [0.05, 0.05, 0.06], [0.25, 0.25, 0.28],
        [0.55, 0.55, 0.58], [0.85, 0.85, 0.87], [1.00, 1.00, 1.00], [0.99, 0.93, 0.85],
    ]

    private var strings: ScreenshotFeatureStrings {
        FeatureStrings.screenshot(l10n.language)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            swatchGrid
            Divider()
            customSection
            Divider()
            slidersSection
        }
        .padding(14)
        .frame(width: 292)
        .onAppear {
            loadWallpapers()
            seedCustomStates()
        }
    }

    // MARK: - Swatches

    private var swatchGrid: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 4),
                  spacing: 8) {
            swatch(for: ScreenshotSupport.BackdropStyle(kind: .none),
                   accessibility: strings.backdropNone) {
                ZStack {
                    Color.primary.opacity(0.06)
                    Image(systemName: "slash.circle")
                        .foregroundStyle(.secondary)
                }
            }
            ForEach(ScreenshotSupport.BackdropID.allCases.filter { $0 != .none },
                    id: \.self) { preset in
                let style = ScreenshotSupport.BackdropStyle(kind: .preset,
                                                            presetID: preset.rawValue)
                swatch(for: style, accessibility: strings.backdropLabel) {
                    LinearGradient(colors: Self.previewColors(for: style),
                                   startPoint: .topLeading, endPoint: .bottomTrailing)
                }
            }
            ForEach(Array(model.backdropPresets.enumerated()), id: \.offset) { index, preset in
                savedSwatch(preset, index: index)
            }
            ForEach(wallpapers, id: \.self) { url in
                wallpaperSwatch(url)
            }
            imagePickerSwatch
        }
    }

    private func swatch<Content: View>(for style: ScreenshotSupport.BackdropStyle,
                                       accessibility: String,
                                       @ViewBuilder content: () -> Content) -> some View {
        let selected = Self.sameLook(style, model.backdropStyle)
        return Button {
            apply(style)
        } label: {
            content()
                .frame(height: 38)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(selected ? Color.accentColor : Color.primary.opacity(0.12),
                                      lineWidth: selected ? 2.5 : 1)
                )
        }
        .buttonStyle(.borderless)
        .accessibilityLabel(accessibility)
    }

    private func savedSwatch(_ preset: ScreenshotSupport.BackdropStyle, index: Int) -> some View {
        swatch(for: preset, accessibility: strings.backdropCustomLabel) {
            Group {
                if preset.kind == .image, let path = preset.imagePath,
                   let thumbnail = Self.thumbnail(for: URL(fileURLWithPath: path)) {
                    Image(nsImage: thumbnail)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } else {
                    LinearGradient(colors: Self.previewColors(for: preset),
                                   startPoint: .topLeading, endPoint: .bottomTrailing)
                }
            }
        }
        .contextMenu {
            Button(strings.backdropDeletePreset, role: .destructive) {
                model.removeBackdropPreset(at: index)
            }
        }
    }

    private func wallpaperSwatch(_ url: URL) -> some View {
        let style = ScreenshotSupport.BackdropStyle(kind: .image, imagePath: url.path)
        return swatch(for: style, accessibility: strings.backdropWallpaperLabel) {
            Group {
                if let thumbnail = Self.thumbnail(for: url) {
                    Image(nsImage: thumbnail)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } else {
                    Color.primary.opacity(0.06)
                }
            }
            .overlay(alignment: .bottomTrailing) {
                Image(systemName: "menubar.dock.rectangle")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(3)
                    .background(.black.opacity(0.45), in: RoundedRectangle(cornerRadius: 4))
                    .padding(3)
            }
        }
        .screenshotSafeHelp(strings.backdropWallpaperLabel)
    }

    private var imagePickerSwatch: some View {
        Button {
            chooseImage()
        } label: {
            ZStack {
                Color.primary.opacity(0.06)
                VStack(spacing: 2) {
                    Image(systemName: "photo.badge.plus")
                        .foregroundStyle(.secondary)
                }
            }
            .frame(height: 38)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.12),
                                  style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
            )
        }
        .buttonStyle(.borderless)
        .screenshotSafeHelp(strings.backdropImageButton)
        .accessibilityLabel(strings.backdropImageButton)
    }

    // MARK: - Custom colors

    private var customSection: some View {
        VStack(spacing: 9) {
            HStack(spacing: 8) {
                Picker("", selection: $customIsGradient) {
                    Text(strings.backdropSolidLabel).tag(false)
                    Text(strings.backdropGradientLabel).tag(true)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .controlSize(.small)
                .onChange(of: customIsGradient) { _, _ in
                    activeWell = 0
                    applyCustom()
                }

                Spacer(minLength: 0)

                if customIsGradient {
                    well(components: gradientStartComponents, index: 0)
                    well(components: gradientEndComponents, index: 1)
                } else {
                    well(components: solidComponents, index: 0)
                }

                Button {
                    model.saveCurrentBackdropAsPreset()
                } label: {
                    Image(systemName: "plus.circle.fill")
                }
                .buttonStyle(.borderless)
                .disabled(!canSavePreset)
                .screenshotSafeHelp(strings.backdropSavePreset)
                .accessibilityLabel(strings.backdropSavePreset)
            }

            palette
        }
    }

    /// One editable color well; the ring marks which one the palette paints.
    private func well(components: [Double], index: Int) -> some View {
        let active = !customIsGradient || activeWell == index
        return Button {
            activeWell = index
        } label: {
            Circle()
                .fill(Self.color(components))
                .frame(width: 18, height: 18)
                .overlay(Circle().strokeBorder(Color.primary.opacity(0.25), lineWidth: 0.5))
                .overlay(
                    Circle()
                        .strokeBorder(Color.accentColor, lineWidth: active ? 2 : 0)
                        .padding(-3)
                )
                .padding(3)
        }
        .buttonStyle(.borderless)
        .accessibilityLabel(customIsGradient
                                ? strings.backdropGradientLabel : strings.backdropSolidLabel)
    }

    /// Colors picked right here, never in a separate panel.
    private var palette: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 5), count: 10),
                  spacing: 5) {
            ForEach(Self.palette.indices, id: \.self) { index in
                let components = Self.palette[index]
                Button {
                    assignToActiveWell(components)
                } label: {
                    Circle()
                        .fill(Self.color(components))
                        .frame(width: 17, height: 17)
                        .overlay(
                            Circle().strokeBorder(Color.primary.opacity(0.18), lineWidth: 0.5)
                        )
                }
                .buttonStyle(.borderless)
                .accessibilityLabel(customIsGradient
                                        ? strings.backdropGradientLabel
                                        : strings.backdropSolidLabel)
            }
        }
    }

    private func assignToActiveWell(_ components: [Double]) {
        if customIsGradient {
            if activeWell == 0 {
                gradientStartComponents = components
            } else {
                gradientEndComponents = components
            }
        } else {
            solidComponents = components
        }
        applyCustom()
    }

    private var canSavePreset: Bool {
        switch model.backdropStyle.sanitized().kind {
        case .solid, .gradient, .image: return true
        case .none, .preset: return false
        }
    }

    // MARK: - Sliders

    private var slidersSection: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                Text(strings.backdropPaddingLabel)
                    .font(.system(size: 12))
                    .frame(width: 64, alignment: .leading)
                    .foregroundStyle(model.showsBackdrop ? .secondary : .tertiary)
                Slider(value: paddingBinding, in: 0...1)
                    .controlSize(.small)
                    .disabled(!model.showsBackdrop)
            }
            HStack(spacing: 8) {
                Text(strings.backdropCornersLabel)
                    .font(.system(size: 12))
                    .frame(width: 64, alignment: .leading)
                    .foregroundStyle(.secondary)
                Slider(value: cornerBinding, in: 0...1)
                    .controlSize(.small)
            }
        }
    }

    private var paddingBinding: Binding<Double> {
        Binding {
            model.backdropStyle.padding
        } set: { value in
            model.backdropStyle.padding = value
        }
    }

    private var cornerBinding: Binding<Double> {
        Binding {
            model.backdropStyle.cornerRadius
        } set: { value in
            model.backdropStyle.cornerRadius = value
        }
    }

    // MARK: - Actions

    /// Applies a look while keeping the user's slider positions.
    private func apply(_ style: ScreenshotSupport.BackdropStyle) {
        var applied = style
        applied.padding = model.backdropStyle.padding
        applied.cornerRadius = model.backdropStyle.cornerRadius
        withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
            model.backdropStyle = applied
        }
    }

    private func applyCustom() {
        if customIsGradient {
            apply(ScreenshotSupport.BackdropStyle(
                kind: .gradient,
                colors: [gradientStartComponents, gradientEndComponents]))
        } else {
            apply(ScreenshotSupport.BackdropStyle(kind: .solid, colors: [solidComponents]))
        }
    }

    private func chooseImage() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.image]
        if panel.runModal() == .OK, let url = panel.url {
            apply(ScreenshotSupport.BackdropStyle(kind: .image, imagePath: url.path))
        }
    }

    private func loadWallpapers() {
        var seen = Set<String>()
        wallpapers = NSScreen.screens.compactMap { screen in
            guard let url = NSWorkspace.shared.desktopImageURL(for: screen),
                  url.isFileURL,
                  FileManager.default.fileExists(atPath: url.path),
                  !seen.contains(url.path)
            else { return nil }
            seen.insert(url.path)
            return url
        }
    }

    private func seedCustomStates() {
        let style = model.backdropStyle.sanitized()
        switch style.kind {
        case .solid:
            if let components = style.colors?.first {
                solidComponents = components
                customIsGradient = false
            }
        case .gradient:
            if let colors = style.colors, colors.count == 2 {
                gradientStartComponents = colors[0]
                gradientEndComponents = colors[1]
                customIsGradient = true
            }
        case .none, .preset, .image:
            break
        }
    }

    // MARK: - Helpers

    /// Two styles look the same when everything but the sliders matches.
    static func sameLook(_ lhs: ScreenshotSupport.BackdropStyle,
                         _ rhs: ScreenshotSupport.BackdropStyle) -> Bool {
        var left = lhs.sanitized()
        var right = rhs.sanitized()
        left.padding = 0; left.cornerRadius = 0
        right.padding = 0; right.cornerRadius = 0
        return left == right
    }

    static func previewColors(for style: ScreenshotSupport.BackdropStyle) -> [Color] {
        let sanitized = style.sanitized()
        switch sanitized.kind {
        case .none:
            return [.clear]
        case .preset:
            guard let id = sanitized.presetID,
                  let preset = ScreenshotSupport.BackdropID(rawValue: id)
            else { return [.clear] }
            return preset.stops.map {
                Color(.sRGB, red: $0.red, green: $0.green, blue: $0.blue, opacity: 1)
            }
        case .solid, .gradient:
            let colors = (sanitized.colors ?? []).map { Self.color($0) }
            return colors.isEmpty ? [.clear] : colors
        case .image:
            return [Color(.sRGB, white: 0.5, opacity: 1)]
        }
    }

    static func color(_ components: [Double]) -> Color {
        guard components.count == 3 else { return .clear }
        return Color(.sRGB, red: components[0], green: components[1],
                     blue: components[2], opacity: 1)
    }

    /// Small cached thumbnails for wallpaper and saved-image swatches.
    private static let thumbnailCache: NSCache<NSString, NSImage> = {
        let cache = NSCache<NSString, NSImage>()
        cache.countLimit = 24
        return cache
    }()

    static func thumbnail(for url: URL) -> NSImage? {
        let key = url.path as NSString
        if let cached = thumbnailCache.object(forKey: key) { return cached }
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: 220,
            kCGImageSourceCreateThumbnailWithTransform: true,
        ]
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
        else { return nil }
        let image = NSImage(cgImage: cgImage, size: .zero)
        thumbnailCache.setObject(image, forKey: key)
        return image
    }
}
