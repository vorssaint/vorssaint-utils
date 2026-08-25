// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import SwiftUI

/// A single keyboard key drawn like a physical keycap. Used across Settings and
/// onboarding to show shortcuts such as ⌘X / ⌘V.
struct KeyCap: View {
    let label: String

    var body: some View {
        Text(label)
            .font(.system(size: 12, weight: .semibold, design: .rounded))
            .frame(minWidth: 20, minHeight: 22)
            .padding(.horizontal, 5)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Color.primary.opacity(0.07))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.14), lineWidth: 1)
            )
    }
}

/// A row of keycaps for a shortcut, e.g. ["⌘", "X"].
struct ShortcutCaps: View {
    let keys: [String]

    var body: some View {
        HStack(spacing: 3) {
            ForEach(Array(keys.enumerated()), id: \.offset) { _, key in
                KeyCap(label: key)
            }
        }
    }
}

struct FullDiskAccessNote: View {
    var compact = false
    /// Why this surface needs the permission. The scan is the usual reason;
    /// a failed removal has its own, so it says so in its own words.
    var reason: String?

    @ObservedObject private var l10n = L10n.shared
    @ObservedObject private var permissions = Permissions.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(alignment: .top, spacing: compact ? 7 : 8) {
                Image(systemName: "info.circle")
                    .foregroundStyle(.secondary)
                Text(reason ?? l10n.s.uninstallerFDANote)
                    .font(compact ? .system(size: 10) : .caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Text(l10n.s.uninstallerFDAHint)
                .font(compact ? .system(size: 9) : .caption2)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: compact ? 7 : 8) {
                Button(l10n.s.uninstallerFDAGrant) { permissions.requestFullDiskAccess() }
                // Shown alongside because access only takes effect on relaunch.
                Button(l10n.s.uninstallerFDARelaunch) { appDelegate()?.relaunchApp() }
            }
            .controlSize(.small)
            .font(compact ? .system(size: 10.5) : nil)
        }
        .padding(compact ? 9 : 11)
        .background(
            RoundedRectangle(cornerRadius: compact ? 8 : 9, style: .continuous)
                .fill(Color.primary.opacity(compact ? 0.045 : 0.05))
        )
    }
}

/// What a removal left behind, and why. Sandboxed app data lives in
/// ~/Library/Containers, which macOS keeps behind Full Disk Access; the
/// administrator prompt Finder shows covers file ownership, not that
/// permission, so those items are refused however the removal is attempted.
/// Naming them at the moment they survive is the only point where the
/// permission has visibly cost the person something.
struct UninstallFailureNote: View {
    let items: [AppUninstaller.Leftover]
    var compact = false

    @ObservedObject private var l10n = L10n.shared
    @ObservedObject private var permissions = Permissions.shared

    private static let namesShown = 4

    var body: some View {
        VStack(alignment: .leading, spacing: compact ? 5 : 7) {
            Text(l10n.s.uninstallerSomeFailed)
                .font(compact ? .system(size: 10) : .caption)
                .foregroundStyle(.orange)
                .fixedSize(horizontal: false, vertical: true)
            ForEach(items.prefix(Self.namesShown)) { item in
                Text(item.name)
                    .font(compact ? .system(size: 9.5) : .caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            if items.count > Self.namesShown {
                Text(String(format: l10n.s.uninstallerFailedMoreFormat,
                            items.count - Self.namesShown))
                    .font(compact ? .system(size: 9.5) : .caption2)
                    .foregroundStyle(.tertiary)
            }
            if !permissions.fullDiskAccess {
                FullDiskAccessNote(compact: compact, reason: l10n.s.uninstallerFailedNeedsFDA)
            }
        }
    }
}

/// Translucent HUD material behind floating panels (the shelf, the switcher, the
/// cut-feedback HUD). Mirrors the switcher's backdrop so every floating surface
/// matches.
///
/// `contrast: .high` lays a flat plate over the material, for the panels that
/// are nothing but rows of text. The frost borrows so much of whatever window
/// sits behind it that such a list over a bright document stops being readable,
/// and the darker the theme the worse it reads: light text against a page of
/// white. The plate keeps the frost visible and gives the text something to sit
/// on. Where the system is already told to reduce transparency it makes the
/// material opaque by itself, so the plate stays out of the way.
///
/// `opacity` fades the material itself, for the one panel that lets the user
/// choose how much of the screen shows through. Reduce transparency wins over
/// it: the whole point of that setting is that panels stop being see-through,
/// so a stored preference must not quietly undo it.
struct HUDBackdrop: View {
    enum Contrast {
        case standard
        case high
    }

    var cornerRadius: CGFloat = 0
    var contrast: Contrast = .standard
    var opacity: Double = 1

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @AppStorage(DefaultsKey.liquidGlassEnabled) private var liquidGlassEnabled = false

    private var materialOpacity: Double {
        reduceTransparency ? 1 : min(max(opacity, 0), 1)
    }

    /// Chosen from the worst case rather than by eye: a panel over a full white
    /// window in the dark theme, or over a full black one in the light theme,
    /// with the material assumed to hold nothing back. At these values the
    /// plate alone carries white text to 4.8:1 and black text to 5.3:1, both
    /// past the 4.5:1 the accessibility guidelines ask of body text, and the
    /// real material only ever adds to that.
    private var plateOpacity: Double {
        guard contrast == .high, !reduceTransparency else { return 0 }
        return colorScheme == .dark ? 0.55 : 0.5
    }

    var body: some View {
#if compiler(>=6.2)
        if #available(macOS 26.0, *), liquidGlassEnabled, !reduceTransparency {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(Color.clear)
                .glassEffect(.regular, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .strokeBorder(colorScheme == .dark ? Color.white.opacity(0.12) : Color.black.opacity(0.08), lineWidth: 0.8)
                )
        } else {
            classicBackdrop
        }
#else
        classicBackdrop
#endif
    }

    @ViewBuilder
    private var classicBackdrop: some View {
        HUDBackdropMaterial(cornerRadius: cornerRadius, opacity: materialOpacity)
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(colorScheme == .dark ? Color.black : Color.white)
                    .opacity(plateOpacity)
            )
    }
}

/// The material itself.
///
/// The corner radius rounds the effect view's own layer, which matters for the
/// behind-window blur: SwiftUI's `.clipShape` rounds the drawn content but does
/// not clip an `NSVisualEffectView`'s behind-window material, so the blur (and
/// the borderless window's shadow, computed from it) keeps the full rectangular
/// bounds. Against a contrasty desktop that rectangle reads as a faint extra
/// outline just outside the rounded card, and whether it shows depends on what
/// is behind the window, which is why it looks intermittent. Clipping the layer
/// to the same radius as the card removes it. Pass the card's corner radius.
private struct HUDBackdropMaterial: NSViewRepresentable {
    var cornerRadius: CGFloat = 0
    var opacity: Double = 1

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .hudWindow
        view.blendingMode = .behindWindow
        view.state = .active
        apply(to: view)
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        apply(to: nsView)
    }

    private func apply(to view: NSVisualEffectView) {
        view.alphaValue = CGFloat(opacity)
        view.wantsLayer = true
        view.layer?.cornerRadius = cornerRadius
        view.layer?.cornerCurve = .continuous
        view.layer?.masksToBounds = true
    }
}

/// Plays an animated image. SwiftUI's Image shows only the first frame of a
/// GIF, so anything that has to move goes through AppKit.
struct AnimatedGIFView: NSViewRepresentable {
    let image: NSImage

    func makeNSView(context: Context) -> NSImageView {
        let view = NSImageView()
        view.imageAlignment = .alignCenter
        view.imageScaling = .scaleProportionallyUpOrDown
        view.animates = true
        view.wantsLayer = true
        view.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        view.setContentCompressionResistancePriority(.defaultLow, for: .vertical)
        return view
    }

    func updateNSView(_ view: NSImageView, context: Context) {
        guard view.image !== image else { return }
        view.image = image
        view.animates = true
    }
}

/// A disclosure header where the whole row toggles the group and the chevron
/// sits on the trailing side, the way a drop-down reads. The label supplies
/// the row's one Spacer, so trailing accessories stay flush to the chevron.
struct DisclosureHeaderRow<Label: View>: View {
    @ObservedObject private var l10n = L10n.shared

    private let isExpanded: Binding<Bool>
    private let label: () -> Label

    init(isExpanded: Binding<Bool>, @ViewBuilder label: @escaping () -> Label) {
        self.isExpanded = isExpanded
        self.label = label
    }

    var body: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.18)) {
                isExpanded.wrappedValue.toggle()
            }
        } label: {
            HStack(spacing: 8) {
                label()
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .rotationEffect(.degrees(isExpanded.wrappedValue ? 90 : 0))
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityValue(isExpanded.wrappedValue
            ? l10n.s.disclosureExpanded : l10n.s.disclosureCollapsed)
    }
}

extension View {
    /// Child rows sit inset under their group's header row.
    func disclosureIndent() -> some View {
        padding(.leading, 25)
    }
}
