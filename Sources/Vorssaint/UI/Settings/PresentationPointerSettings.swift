// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// The presentation pointer's card on the Mouse & Trackpad page: the two live
/// switches first, then how the pointer looks, taps and sounds, then its
/// shortcuts.
struct PresentationPointerSection: View {
    @ObservedObject private var l10n = L10n.shared
    @ObservedObject private var service = PresentationPointerService.shared
    @AppStorage(DefaultsKey.presentationPointerStyle) private var style =
        PresentationPointerSupport.defaultStyle.rawValue
    @AppStorage(DefaultsKey.presentationPointerColor) private var color = PresentationPointerSupport.defaultColor
    @AppStorage(DefaultsKey.presentationPointerSize) private var size = PresentationPointerSupport.defaultSize
    @AppStorage(DefaultsKey.presentationPointerEnergy) private var energy = PresentationPointerSupport.defaultEnergy
    @AppStorage(DefaultsKey.presentationPointerBursts) private var bursts = true
    @AppStorage(DefaultsKey.presentationPointerSoundEnabled) private var soundEnabled = false
    @AppStorage(DefaultsKey.presentationPointerSoundName) private var soundName =
        PresentationPointerSupport.defaultSoundName
    @AppStorage(DefaultsKey.presentationPointerSoundVolume) private var volume =
        PresentationPointerSupport.defaultSoundVolume
    @AppStorage(DefaultsKey.presentationPointerCustomSoundPath) private var customSoundPath = ""
    @AppStorage(DefaultsKey.presentationPointerShortcutEnabled) private var shortcutEnabled = true
    @AppStorage(DefaultsKey.presentationPointerBlockClicksShortcutEnabled) private var blockClicksShortcutEnabled = true

    private var text: PresentationPointerStrings { FeatureStrings.presentationPointer(l10n.language) }

    private var selectedStyle: PresentationPointerStyle { PresentationPointerSupport.style(stored: style) }

    var body: some View {
        SettingsCard(title: text.title) {
            SettingsRow(symbol: "hand.point.up.left", title: text.showToggle, caption: text.caption) {
                Toggle(text.showToggle, isOn: showingBinding).labelsHidden()
            }
            SettingsRow(symbol: "hand.raised", title: text.blockClicksTitle, caption: text.blockClicksCaption) {
                Toggle(text.blockClicksTitle, isOn: blockingBinding).labelsHidden()
            }
            // What viewers need for the pointer to reach them, next to the
            // switch that shows it.
            Text(text.shareNote)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.leading, settingsRowTextInset)

            Divider()

            SettingsRow(symbol: "paintpalette", title: text.styleLabel) {
                EmptyView()
            }
            // The looks and the two choices that change them, with the
            // pointer as it will look beside them where the window is wide
            // enough, and beside the two choices under the looks where not.
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .center, spacing: 20) {
                    VStack(alignment: .leading, spacing: 12) {
                        stylePicker
                        sizeAndColor
                    }
                    .frame(width: Self.columnWidth)
                    preview(side: 132)
                }
                VStack(alignment: .leading, spacing: 12) {
                    stylePicker
                    HStack(alignment: .center, spacing: 16) {
                        sizeAndColor
                        preview(side: 96)
                    }
                    .frame(width: Self.columnWidth)
                }
            }
            .padding(.leading, settingsRowTextInset)

            Divider()

            SettingsRow(symbol: "bolt.fill", title: text.energyLabel, caption: text.energyCaption) {
                EmptyView()
            }
            // End labels of its own: a slider dims the ones it is given.
            HStack(spacing: 8) {
                Text(text.energySubtle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Slider(value: $energy, in: 0...1) {
                    Text(text.energyLabel)
                }
                .labelsHidden()
                Text(text.energyBold)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(width: Self.columnWidth)
            .padding(.leading, settingsRowTextInset)
            SettingsRow(symbol: "sparkle", title: text.burstsToggle) {
                Toggle(text.burstsToggle, isOn: $bursts).labelsHidden()
            }

            Divider()

            SettingsRow(symbol: "speaker.wave.2.fill", title: text.soundToggle, caption: text.soundCaption) {
                Toggle(text.soundToggle, isOn: $soundEnabled).labelsHidden()
            }
            if soundEnabled {
                soundControls
                    .frame(width: Self.columnWidth, alignment: .leading)
                    .padding(.leading, settingsRowTextInset)
            }

            Divider()

            // The General page's shortcut pattern, a switch row with its
            // recorder under it, once for each of the two switches at the top.
            SettingsRow(symbol: "keyboard", title: text.shortcutToggle) {
                Toggle(text.shortcutToggle, isOn: $shortcutEnabled).labelsHidden()
            }
            ShortcutPreferenceRow(role: .presentationPointer, isEnabled: shortcutEnabled,
                                  label: text.title) {
                service.syncWithPreferences()
            }
            .padding(.leading, settingsRowTextInset)
            if shortcutEnabled, service.shortcutRegistrationFailed {
                unavailableShortcutNote
            }
            SettingsRow(symbol: "keyboard", title: text.blockClicksShortcutToggle) {
                Toggle(text.blockClicksShortcutToggle, isOn: $blockClicksShortcutEnabled).labelsHidden()
            }
            ShortcutPreferenceRow(role: .presentationPointerBlockClicks, isEnabled: blockClicksShortcutEnabled,
                                  label: text.blockClicksTitle) {
                service.syncWithPreferences()
            }
            .padding(.leading, settingsRowTextInset)
            if blockClicksShortcutEnabled, service.blockClicksShortcutRegistrationFailed {
                unavailableShortcutNote
            }
        }
        .onChange(of: preferenceState) { _, _ in
            service.syncWithPreferences()
        }
        .onDisappear {
            service.stopPreview()
        }
    }

    // MARK: - Style

    private static let tileWidth: CGFloat = 72
    private static let tileSpacing: CGFloat = 8

    /// The five looks side by side. The controls under them share this width,
    /// so every slider and picker ends where the last look does.
    private static let columnWidth = CGFloat(PresentationPointerStyle.allCases.count) * tileWidth
        + CGFloat(PresentationPointerStyle.allCases.count - 1) * tileSpacing

    private var sizeAndColor: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Continuous, so no tick marks crowd the track; the binding keeps
            // the value to whole points.
            SettingsSliderRow(title: text.sizeLabel, value: sizeBinding,
                              range: PresentationPointerSupport.sizeRange,
                              readout: "\(Int(PresentationPointerSupport.sanitizedSize(size))) pt")
            HStack(spacing: 12) {
                Text(text.colorLabel)
                Spacer(minLength: 12)
                ColorPicker(text.colorLabel, selection: colorBinding, supportsOpacity: false)
                    .labelsHidden()
            }
        }
    }

    private func preview(side: CGFloat) -> some View {
        PresentationPointerPreview(style: selectedStyle, colorHex: color,
                                   size: PresentationPointerSupport.sanitizedSize(size), side: side)
    }

    /// Every look as it will appear, picked by clicking it.
    private var stylePicker: some View {
        HStack(spacing: Self.tileSpacing) {
            ForEach(PresentationPointerStyle.allCases) { option in
                let selected = selectedStyle == option
                Button {
                    style = option.rawValue
                } label: {
                    VStack(spacing: 4) {
                        PresentationPointerThumbnail(style: option, colorHex: color)
                            .frame(width: 40, height: 40)
                        Text(name(of: option))
                            .font(.caption)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                    .padding(.vertical, 6)
                    .frame(width: Self.tileWidth)
                    .choiceTile(selected: selected)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(name(of: option))
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
    }

    // MARK: - Sound

    private var soundControls: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                Text(text.soundPickerLabel)
                    .frame(minWidth: 96, alignment: .leading)
                soundPicker
                Spacer(minLength: 0)
            }
            if soundName == PresentationPointerSupport.customSoundName {
                HStack(spacing: 10) {
                    Text(customSoundPath.isEmpty
                         ? text.soundNoFile
                         : URL(fileURLWithPath: customSoundPath).lastPathComponent)
                        .font(.callout)
                        .foregroundStyle(customSoundPath.isEmpty ? .secondary : .primary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Button(text.soundChooseFile, action: chooseSoundFile)
                        .controlSize(.small)
                }
                .padding(.leading, 96 + 12)
            }
            SettingsSliderRow(title: text.volumeLabel, value: volumeBinding, range: 0...1,
                              readout: "\(Int((volumeBinding.wrappedValue * 100).rounded()))%") { editing in
                if !editing { service.previewSound() }
            }
        }
    }

    private var soundPicker: some View {
        Picker(text.soundPickerLabel, selection: $soundName) {
            // The pointer's own taps first, then the Mac's alert sounds,
            // then a file of the person's own.
            ForEach(PresentationPointerTapSound.allCases) { sound in
                Text(name(of: sound)).tag(sound.storageValue)
            }
            Divider()
            ForEach(AlertSoundStrings.sortedNames(TextSnippetSupport.alertSoundNames,
                                                  language: l10n.language), id: \.self) { name in
                Text(AlertSoundStrings.displayName(for: name, language: l10n.language)).tag(name)
            }
            Divider()
            Text(text.soundCustom).tag(PresentationPointerSupport.customSoundName)
            // A name saved on another Mac, or one this macOS no longer
            // ships, needs a row of its own or the picker shows nothing.
            // It plays the default tap, as the row says.
            if soundName != PresentationPointerSupport.defaultSoundName,
               PresentationPointerSoundChoice.resolve(stored: soundName,
                                                      systemNames: TextSnippetSupport.alertSoundNames)
                == .builtIn(.drum) {
                Text(text.soundUnavailable).tag(soundName)
            }
        }
        .labelsHidden()
        .fixedSize()
        .onChange(of: soundName) { _, name in
            service.syncWithPreferences()
            // A custom file not chosen yet would preview the fallback,
            // which is not the sound just picked.
            if name != PresentationPointerSupport.customSoundName || !customSoundPath.isEmpty {
                service.previewSound()
            }
        }
    }

    private func chooseSoundFile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.audio]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        customSoundPath = url.path
        service.syncWithPreferences()
        service.previewSound()
    }

    // MARK: - Bindings

    /// Every stored choice that changes how the pointer looks or sounds, so
    /// one change handler reaches the service for all of them.
    private var preferenceState: [String] {
        [style, color, String(size), String(energy), String(bursts), String(soundEnabled), soundName,
         String(volume), customSoundPath, String(shortcutEnabled), String(blockClicksShortcutEnabled)]
    }

    private var showingBinding: Binding<Bool> {
        Binding(get: { service.mode.isShowing },
                set: { if $0 != service.mode.isShowing { service.toggle() } })
    }

    private var blockingBinding: Binding<Bool> {
        Binding(get: { service.mode.blocksClicks },
                set: { if $0 != service.mode.blocksClicks { service.toggleBlockingClicks() } })
    }

    /// A volume restored from a backup is any number; the slider and its
    /// value read it as the taps play it, from silent to full.
    private var volumeBinding: Binding<Double> {
        Binding(get: { PresentationPointerSupport.clampedFraction(volume) },
                set: { volume = PresentationPointerSupport.clampedFraction($0) })
    }

    private var sizeBinding: Binding<Double> {
        Binding(get: { PresentationPointerSupport.sanitizedSize(size) },
                set: { size = PresentationPointerSupport.sanitizedSize($0.rounded()) })
    }

    private var colorBinding: Binding<Color> {
        Binding {
            let rgb = MenuBarUsageBarSupport.rgb(for: color, fallback: PresentationPointerSupport.defaultColor)
            return Color(red: rgb.red, green: rgb.green, blue: rgb.blue)
        } set: { newColor in
            guard let converted = NSColor(newColor).usingColorSpace(.sRGB) else { return }
            color = MenuBarUsageBarSupport.hex(red: Double(converted.redComponent),
                                               green: Double(converted.greenComponent),
                                               blue: Double(converted.blueComponent))
        }
    }

    private var unavailableShortcutNote: some View {
        Text(l10n.s.shortcutUnavailable)
            .font(.caption)
            .foregroundStyle(.orange)
            .padding(.leading, settingsRowTextInset)
    }

    private func name(of sound: PresentationPointerTapSound) -> String {
        switch sound {
        case .drum: return text.soundDrum
        case .tap: return text.soundTap
        case .knock: return text.soundKnock
        case .pop: return text.soundPop
        case .tick: return text.soundTick
        }
    }

    private func name(of style: PresentationPointerStyle) -> String {
        switch style {
        case .hand: return text.styleHand
        case .wand: return text.styleWand
        case .pencil: return text.stylePencil
        case .banana: return text.styleBanana
        case .ring: return text.styleRing
        }
    }
}

/// One look in the style picker, drawn by the same code the overlay uses.
private struct PresentationPointerThumbnail: View {
    let style: PresentationPointerStyle
    let colorHex: String

    var body: some View {
        // A box even without its picture, so a look never loses its tile.
        ZStack {
            if let image = PresentationPointerThumbnails.tile(style, colorHex: colorHex, side: 34) {
                Image(nsImage: image)
                    .accessibilityHidden(true)
            }
        }
    }
}

/// The pointer as it will look, drawn by the same code the overlay uses.
private struct PresentationPointerPreview: View {
    let style: PresentationPointerStyle
    let colorHex: String
    let size: Double
    let side: CGFloat

    var body: some View {
        ZStack {
            // A shallow well in both appearances, like the unpicked looks.
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.primary.opacity(0.04))
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
            if let image {
                // True to size up to the box; the largest sizes are shown
                // scaled down rather than cut off.
                let fit = min(1, (side - 12) / max(image.size.width, 1))
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .frame(width: image.size.width * fit, height: image.size.height * fit)
            }
        }
        .frame(width: side, height: side)
        .accessibilityHidden(true)
    }

    private var image: NSImage? {
        PresentationPointerThumbnails.image(style, colorHex: colorHex, size: CGFloat(size.rounded()))
    }
}
