// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit

/// The presentation pointer's quick controls in the menu bar icon's menu:
/// show it, block clicks, pick a look, set the tap energy, and switch bursts
/// and sound, without opening Settings. The menu opens above
/// everything, blocked clicks included.
final class PresentationPointerMenu: NSObject {
    static let shared = PresentationPointerMenu()

    /// The submenu's item, built fresh each time the menu opens so every
    /// check mark is current.
    func item() -> NSMenuItem {
        let text = FeatureStrings.presentationPointer(L10n.shared.language)
        let item = NSMenuItem(title: text.title, action: nil, keyEquivalent: "")
        item.image = NSImage(systemSymbolName: AppFeature.presentationPointer.symbolName,
                             accessibilityDescription: nil)
        item.submenu = submenu(text)
        return item
    }

    private func submenu(_ text: PresentationPointerStrings) -> NSMenu {
        let service = PresentationPointerService.shared
        let defaults = UserDefaults.standard
        let menu = NSMenu()

        menu.addItem(switchItem(text.showToggle, on: service.isShowing, action: #selector(toggleShowing),
                                shortcut: .presentationPointer,
                                enabledKey: DefaultsKey.presentationPointerShortcutEnabled))
        menu.addItem(switchItem(text.blockClicksTitle, on: service.blocksClicks, action: #selector(toggleBlocking),
                                shortcut: .presentationPointerBlockClicks,
                                enabledKey: DefaultsKey.presentationPointerBlockClicksShortcutEnabled))
        menu.addItem(.separator())

        let current = PresentationPointerSupport.style(stored: defaults.string(forKey: DefaultsKey.presentationPointerStyle))
        let color = defaults.string(forKey: DefaultsKey.presentationPointerColor) ?? PresentationPointerSupport.defaultColor
        for (index, style) in PresentationPointerStyle.allCases.enumerated() {
            let item = NSMenuItem(title: Self.name(of: style, text), action: #selector(chooseStyle(_:)),
                                  keyEquivalent: "")
            item.target = self
            item.tag = index
            item.state = style == current ? .on : .off
            item.image = PresentationPointerThumbnails.tile(style, colorHex: color, side: 16)
            menu.addItem(item)
        }
        menu.addItem(.separator())

        let energy = NSMenuItem()
        energy.view = EnergySliderView(
            subtle: text.energySubtle, bold: text.energyBold, label: text.energyLabel,
            value: PresentationPointerSupport.clampedFraction(defaults.double(forKey: DefaultsKey.presentationPointerEnergy)))
        menu.addItem(energy)
        menu.addItem(switchItem(text.burstsToggle, on: defaults.bool(forKey: DefaultsKey.presentationPointerBursts),
                                action: #selector(toggleBursts)))
        menu.addItem(switchItem(text.soundToggle,
                                on: defaults.bool(forKey: DefaultsKey.presentationPointerSoundEnabled),
                                action: #selector(toggleSound)))
        menu.addItem(.separator())

        let settings = NSMenuItem(title: L10n.shared.s.menuSettings, action: #selector(openSettings),
                                  keyEquivalent: "")
        settings.target = self
        menu.addItem(settings)
        return menu
    }

    /// A checkable item, with its global shortcut shown on the right while
    /// that shortcut is switched on.
    private func switchItem(_ title: String, on: Bool, action: Selector, shortcut: GlobalShortcutRole? = nil,
                            enabledKey: String? = nil) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        item.state = on ? .on : .off
        if let shortcut, let enabledKey, UserDefaults.standard.bool(forKey: enabledKey) {
            item.badge = NSMenuItemBadge(string: shortcut.savedShortcut.displayString)
        }
        return item
    }

    static func name(of style: PresentationPointerStyle, _ text: PresentationPointerStrings) -> String {
        switch style {
        case .hand: return text.styleHand
        case .wand: return text.styleWand
        case .pencil: return text.stylePencil
        case .banana: return text.styleBanana
        case .ring: return text.styleRing
        }
    }

    // MARK: - Actions

    @objc private func toggleShowing() {
        PresentationPointerService.shared.toggle()
    }

    @objc private func toggleBlocking() {
        PresentationPointerService.shared.toggleBlockingClicks()
    }

    @objc private func chooseStyle(_ sender: NSMenuItem) {
        guard PresentationPointerStyle.allCases.indices.contains(sender.tag) else { return }
        UserDefaults.standard.set(PresentationPointerStyle.allCases[sender.tag].rawValue,
                                  forKey: DefaultsKey.presentationPointerStyle)
        PresentationPointerService.shared.syncWithPreferences()
    }

    @objc private func toggleBursts() { flip(DefaultsKey.presentationPointerBursts) }
    @objc private func toggleSound() { flip(DefaultsKey.presentationPointerSoundEnabled) }

    private func flip(_ key: String) {
        UserDefaults.standard.set(!UserDefaults.standard.bool(forKey: key), forKey: key)
        PresentationPointerService.shared.syncWithPreferences()
    }

    @objc private func openSettings() {
        SettingsRouter.shared.request(AppFeature.presentationPointer.settingsDestination,
                                      sidebarFeature: .presentationPointer)
        appDelegate()?.openSettingsWindow()
    }
}

/// Pictures of each look for the menu, the panel and Settings, drawn by the
/// overlay's own code once per look, color and size and kept.
enum PresentationPointerThumbnails {
    private static var cache: [String: NSImage] = [:]

    static func image(_ style: PresentationPointerStyle, colorHex: String, size: CGFloat) -> NSImage? {
        // Only the ring is drawn in the chosen color; a picture is the same
        // picture whatever the color.
        let key = style == .ring ? "ring-\(colorHex)-\(size)" : "\(style.rawValue)-\(size)"
        if let cached = cache[key] { return cached }
        // A size slider being dragged asks for many sizes; keep the set small.
        if cache.count > 48 { cache = [:] }
        let rgb = MenuBarUsageBarSupport.rgb(for: colorHex, fallback: PresentationPointerSupport.defaultColor)
        let color = NSColor(srgbRed: rgb.red, green: rgb.green, blue: rgb.blue, alpha: 1)
        guard let artwork = PresentationPointerArtwork.make(style: style, color: color, pointerSize: size, scale: 2)
        else { return nil }
        let image = NSImage(cgImage: artwork.image, size: artwork.size)
        cache[key] = image
        return image
    }

    /// A look for a picker tile or menu item, `side` points across. Every
    /// picture leaves a margin inside its square while the ring fills its
    /// own, so the ring is drawn a little smaller to weigh the same.
    static func tile(_ style: PresentationPointerStyle, colorHex: String, side: CGFloat) -> NSImage? {
        image(style, colorHex: colorHex, size: style == .ring ? (side * 0.82).rounded() : side)
    }
}

/// Tap energy as a slider inside the menu, from subtle to bold, applied as it
/// moves.
private final class EnergySliderView: NSView {
    private let slider: NSSlider

    init(subtle: String, bold: String, label: String, value: Double) {
        slider = NSSlider(value: value, minValue: 0, maxValue: 1, target: nil, action: nil)
        super.init(frame: CGRect(x: 0, y: 0, width: 250, height: 30))
        slider.target = self
        slider.action = #selector(changed)
        slider.isContinuous = true
        slider.controlSize = .small
        slider.setAccessibilityLabel(label)
        let low = Self.caption(subtle)
        let high = Self.caption(bold)
        let row = NSStackView(views: [low, slider, high])
        row.orientation = .horizontal
        row.spacing = 8
        row.translatesAutoresizingMaskIntoConstraints = false
        addSubview(row)
        NSLayoutConstraint.activate([
            row.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 22),
            row.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -14),
            row.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    private static func caption(_ text: String) -> NSTextField {
        let field = NSTextField(labelWithString: text)
        field.font = .menuFont(ofSize: NSFont.smallSystemFontSize)
        field.textColor = .secondaryLabelColor
        field.setContentHuggingPriority(.required, for: .horizontal)
        return field
    }

    @objc private func changed() {
        UserDefaults.standard.set(slider.doubleValue, forKey: DefaultsKey.presentationPointerEnergy)
        PresentationPointerService.shared.syncWithPreferences()
    }
}
