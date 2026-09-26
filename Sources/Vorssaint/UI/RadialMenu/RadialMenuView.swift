// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import SwiftUI

/// The wheel itself: a glass disc with one chip per action, a highlight wedge
/// under the pointed slice and a hub that names the selection or leads back.
struct RadialMenuView: View {
    @ObservedObject private var service = RadialMenuService.shared
    @ObservedObject private var l10n = L10n.shared
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @AppStorage(DefaultsKey.liquidGlassEnabled) private var liquidGlassEnabled = false

    /// Where the highlight sits right now. Kept unwrapped past a full turn, so
    /// the step from the last slice to the first is one step onward and not a
    /// spin all the way back.
    @State private var wedgeAngle = 0.0
    @State private var wedgeSlice = Double.pi / 3
    @State private var wedgeShown = false

    /// The whole opening sweep lands inside this, however many slices there
    /// are: a wheel of twelve must not take twice as long to draw itself as a
    /// wheel of six.
    private static let sweepDuration = 0.17

    private var text: RadialMenuFeatureStrings { FeatureStrings.radialMenu(l10n.language) }
    private var items: [RadialMenuItem] { service.stack.last ?? [] }
    /// Reduce Motion is the only switch over this wheel: opening this way is
    /// what the menu is now, not a preference.
    private var animates: Bool { !reduceMotion }
    private var profileColor: Color {
        service.activeProfile?.color.color(for: colorScheme) ?? .accentColor
    }

    var body: some View {
        ZStack {
            backplate
            wedge
            ring.id(service.stack.count)
            hub
        }
        .frame(width: RadialMenuLayout.panelSize, height: RadialMenuLayout.panelSize)
        // The whole panel is tappable; the service decides by distance, so a
        // click on the transparent corners dismisses instead of dying.
        .contentShape(Rectangle())
        .onTapGesture { service.activatePointer() }
        // The wheel grows into the screen and settles back instead of being
        // stamped onto it. The window's own fade carries the shadow and the
        // material; this carries the size.
        .scaleEffect(service.visible || !animates ? 1 : 0.9)
        .animation(animates
                   ? (service.visible
                      ? .spring(response: 0.27, dampingFraction: 0.86)
                      : .easeIn(duration: 0.13))
                   : nil,
                   value: service.visible)
        .onChange(of: service.highlightedIndex) { _, _ in syncWedge() }
        .onChange(of: items.count) { _, _ in syncWedge() }
        .accessibilityLabel(text.pageTitle)
    }

    /// One shape that sweeps to the slice under the pointer instead of a new
    /// one being stamped over the old. Always present, so moving between
    /// slices is a movement and not a swap.
    private var wedge: some View {
        RadialWedgeShape(centerAngle: wedgeAngle,
                         sliceAngle: wedgeSlice,
                         innerRadius: RadialMenuLayout.deadZoneRadius,
                         outerRadius: RadialMenuLayout.wheelDiameter / 2 - 4)
            // Strongest out at the chip, almost gone by the hub: the wedge
            // points outward, the way the gesture does.
            .fill(RadialGradient(colors: [profileColor.opacity(colorScheme == .light ? 0.05 : 0.08),
                                          profileColor.opacity(colorScheme == .light ? 0.20 : 0.30)],
                                 center: .center,
                                 startRadius: RadialMenuLayout.deadZoneRadius,
                                 endRadius: RadialMenuLayout.wheelDiameter / 2))
            .opacity(wedgeShown ? 1 : 0)
    }

    private func syncWedge() {
        let count = items.count
        guard count > 0, let index = service.highlightedIndex, items.indices.contains(index) else {
            guard wedgeShown else { return }
            withAnimation(animates ? .easeOut(duration: 0.12) : nil) { wedgeShown = false }
            return
        }
        let slice = 2 * Double.pi / Double(count)
        var angle = slice * Double(index)
        guard wedgeShown else {
            // Nothing to sweep from: the highlight simply appears under the
            // pointer that armed it.
            var placement = Transaction()
            placement.disablesAnimations = true
            withTransaction(placement) {
                wedgeAngle = angle
                wedgeSlice = slice
            }
            withAnimation(animates ? .easeOut(duration: 0.12) : nil) { wedgeShown = true }
            return
        }
        // The short way round, so the step from the last slice to the first
        // crosses the top instead of unwinding the whole wheel. The remainder
        // is signed and never past half a turn, which is exactly that step.
        angle = wedgeAngle + (angle - wedgeAngle).remainder(dividingBy: 2 * Double.pi)
        withAnimation(animates ? .spring(response: 0.2, dampingFraction: 0.86) : nil) {
            wedgeAngle = angle
            wedgeSlice = slice
        }
    }

    private var backplate: some View {
        discMaterial
            // Glass is glass because of its edge: lit at the top, gone by the
            // bottom. A flat stroke all the way round reads as cut paper.
            .overlay(Circle().strokeBorder(PanelSurface.rimHighlight(for: colorScheme), lineWidth: 1.2))
            .overlay(Circle().strokeBorder(PanelSurface.border(for: colorScheme), lineWidth: 0.8))
            .overlay(sliceGuides)
            .frame(width: RadialMenuLayout.wheelDiameter, height: RadialMenuLayout.wheelDiameter)
            .shadow(color: .black.opacity(colorScheme == .light ? 0.22 : 0.55), radius: 24, y: 8)
    }

    @ViewBuilder
    private var discMaterial: some View {
#if compiler(>=6.2)
        if #available(macOS 26.0, *), liquidGlassEnabled, !reduceTransparency {
            Circle()
                .fill(Color.clear)
                .glassEffect(.regular, in: Circle())
                .overlay(Circle().fill(PanelSurface.baseFill(for: colorScheme).opacity(colorScheme == .light ? 0.35 : 0.45)))
        } else {
            Circle()
                .fill(.regularMaterial)
                .overlay(Circle().fill(PanelSurface.baseFill(for: colorScheme)))
        }
#else
        Circle()
            .fill(.regularMaterial)
            .overlay(Circle().fill(PanelSurface.baseFill(for: colorScheme)))
#endif
    }

    /// A hairline between one slice and the next. Almost invisible on its own,
    /// but it is what turns a ring of buttons into a wheel with directions:
    /// the eye reads the whole wedge as the target, not just the icon.
    private var sliceGuides: some View {
        let count = items.count
        return ZStack {
            if count > 1 {
                ForEach(0..<count, id: \.self) { index in
                    Capsule()
                        .fill(Color.primary.opacity(colorScheme == .light ? 0.07 : 0.09))
                        .frame(width: 1, height: RadialMenuLayout.wheelDiameter / 2
                               - RadialMenuLayout.deadZoneRadius - 14)
                        .offset(y: -(RadialMenuLayout.deadZoneRadius
                                     + (RadialMenuLayout.wheelDiameter / 2
                                        - RadialMenuLayout.deadZoneRadius - 14) / 2 + 7))
                        .rotationEffect(.radians(2 * Double.pi * (Double(index) + 0.5) / Double(count)))
                }
            }
        }
    }

    /// The chips are thrown out of the hub one after another, clockwise from
    /// twelve o'clock, so the wheel draws itself around the pointer instead of
    /// landing on it whole. A submenu is a new set of chips and draws itself
    /// the same way.
    private var ring: some View {
        let count = items.count
        return ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
            RadialChipView(item: item,
                           name: item.displayName(text, nowPlayingState: service.nowPlayingState),
                           nowPlayingState: service.nowPlayingState,
                           highlighted: service.highlightedIndex == index,
                           animates: animates,
                           profileColor: profileColor,
                           direction: RadialMenuGeometry.unitPosition(index: index, itemCount: count),
                           openDelay: Self.openDelay(index: index, count: count),
                           open: service.visible)
                .accessibilityLabel(item.displayName(text, nowPlayingState: service.nowPlayingState))
        }
    }

    private static func openDelay(index: Int, count: Int) -> Double {
        guard count > 1 else { return 0 }
        return sweepDuration * Double(index) / Double(count - 1)
    }

    // No disc behind the hub: the label, the back hint and the brand mark sit
    // straight on the wheel's glass, quiet and centered. What it says changes
    // with every slice the pointer crosses, so it changes by crossing over
    // rather than by being replaced between two frames.
    private var hub: some View {
        ZStack {
            // The dead zone is a target: it steps back out of a submenu and
            // it is where the pointer rests without arming anything. A plate
            // this faint is not decoration, it is the only thing that says so.
            Circle()
                .fill(Color.primary.opacity(colorScheme == .light ? 0.045 : 0.075))
                .frame(width: RadialMenuLayout.hubDiameter, height: RadialMenuLayout.hubDiameter)
            hubFace
                .id(hubFaceKey)
                .transition(.opacity.combined(with: .scale(scale: 0.92)))
        }
        .frame(width: RadialMenuLayout.hubDiameter, height: RadialMenuLayout.hubDiameter)
        .animation(animates ? .easeOut(duration: 0.14) : nil, value: hubFaceKey)
    }

    /// What the hub is saying right now. A change here is a change of face,
    /// which is what the cross-fade is keyed on.
    private var hubFaceKey: String {
        if let index = service.highlightedIndex, items.indices.contains(index) {
            return "item.\(items[index].id)"
        }
        if let parent = service.trail.last { return "back.\(parent)" }
        return "brand"
    }

    @ViewBuilder
    private var hubFace: some View {
        if let index = service.highlightedIndex, items.indices.contains(index) {
            Text(items[index].displayName(text, nowPlayingState: service.nowPlayingState))
                .font(.system(size: 11, weight: .semibold))
                .multilineTextAlignment(.center)
                .lineLimit(3)
                .minimumScaleFactor(0.8)
                .padding(.horizontal, 8)
        } else if let parent = service.trail.last {
            VStack(spacing: 3) {
                Image(systemName: "chevron.backward")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
                Text(parent.isEmpty ? text.kindSubmenu : parent)
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 8)
            }
            .accessibilityLabel(text.backButton)
        } else {
            // Black on the light theme, white on the dark one: the owner
            // wants the mark clearly readable at the center.
            BrandMark(width: 34, tint: Color.primary)
        }
    }
}

private struct RadialChipView: View {
    let item: RadialMenuItem
    let name: String
    let nowPlayingState: RadialNowPlayingState
    let highlighted: Bool
    let animates: Bool
    let profileColor: Color
    /// Where on the ring this chip belongs, and when its turn comes in the
    /// opening sweep.
    let direction: (dx: CGFloat, dyUp: CGFloat)
    let openDelay: Double
    /// The wheel's own state. Chips fly out of the hub when it opens and fold
    /// back into it when it closes, so the wheel gathers itself up on the way
    /// out instead of simply going dark.
    let open: Bool
    @Environment(\.colorScheme) private var colorScheme
    @State private var settled = false

    var body: some View {
        ZStack {
            Circle()
                .fill(highlighted ? AnyShapeStyle(profileColor)
                                  : AnyShapeStyle(PanelSurface.raisedFill(for: colorScheme)))
                .overlay(Circle().strokeBorder(highlighted
                                               ? Color.clear
                                               : PanelSurface.raisedBorder(for: colorScheme),
                                               lineWidth: 0.8))
                // Its own shadow is what puts the chip ON the glass instead of
                // in it, the way the system's own round toggles sit on theirs.
                // Pointed at, that shadow takes the wheel's colour, so which
                // one is armed is never only a change of tint.
                .shadow(color: highlighted ? profileColor.opacity(0.45)
                                           : PanelSurface.raisedShadow(for: colorScheme),
                        radius: highlighted ? 13 : 5,
                        y: highlighted ? 4 : 2)
            icon
        }
        .frame(width: RadialMenuLayout.chipSize, height: RadialMenuLayout.chipSize)
        .scaleEffect(highlighted && animates ? 1.14 : 1)
        .animation(animates ? .spring(response: 0.24, dampingFraction: 0.72) : nil, value: highlighted)
        // The opening sweep rides outside the highlight's own animation, so
        // pointing at a chip mid-flight does not fight with its arrival.
        .scaleEffect(settled || !animates ? 1 : 0.35)
        .opacity(settled || !animates ? 1 : 0)
        .offset(x: direction.dx * reach, y: -direction.dyUp * reach)
        // A chip born into an open wheel is a submenu arriving, and draws
        // itself in the same sweep the wheel itself did.
        .onAppear { if open { bloom() } else { settled = false } }
        .onChange(of: open) { _, isOpen in
            if isOpen { bloom() } else { fold() }
        }
    }

    /// How far out the chip sits: folded into the hub to begin with, then out
    /// to its place on the ring.
    private var reach: CGFloat {
        settled || !animates ? RadialMenuLayout.ringRadius : RadialMenuLayout.deadZoneRadius * 0.2
    }

    private func bloom() {
        guard animates else {
            settled = true
            return
        }
        withAnimation(.spring(response: 0.36, dampingFraction: 0.75).delay(openDelay)) {
            settled = true
        }
    }

    /// Folding in is tighter than opening out: what is being dismissed should
    /// not be waited for.
    private func fold() {
        guard animates else {
            settled = false
            return
        }
        withAnimation(.easeIn(duration: 0.1).delay(openDelay * 0.25)) {
            settled = false
        }
    }

    @ViewBuilder
    private var icon: some View {
        if item.mediaKey == .nowPlaying {
            if case let .playing(snapshot) = nowPlayingState,
               let icon = RadialNowPlayingApplication.icon(for: snapshot) {
                Image(nsImage: icon)
                    .resizable()
                    .interpolation(.high)
                    .frame(width: 34, height: 34)
            } else {
                Image(systemName: "music.note")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(highlighted ? AnyShapeStyle(.white) : AnyShapeStyle(.primary))
            }
        } else if item.symbolName.isEmpty, let customImage = RadialMenuIconStore.customIcon(for: item) {
            Image(nsImage: customImage)
                .resizable()
                .interpolation(.high)
                .frame(width: 34, height: 34)
        } else if item.usesFileIcon {
            Image(nsImage: RadialMenuIconStore.fileIcon(for: item.payload))
                .resizable()
                .interpolation(.high)
                .frame(width: 34, height: 34)
        } else {
            Image(systemName: item.effectiveSymbolName)
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(highlighted ? AnyShapeStyle(.white) : AnyShapeStyle(.primary))
        }
    }
}

/// A slice-shaped highlight between the hub and the wheel border.
struct RadialWedgeShape: Shape {
    var centerAngle: Double
    var sliceAngle: Double
    let innerRadius: CGFloat
    let outerRadius: CGFloat

    /// The angle and the width are what move, so the highlight sweeps to the
    /// slice under the pointer, and re-fits when a submenu holds a different
    /// number of them.
    var animatableData: AnimatablePair<Double, Double> {
        get { AnimatablePair(centerAngle, sliceAngle) }
        set {
            centerAngle = newValue.first
            sliceAngle = newValue.second
        }
    }

    func path(in rect: CGRect) -> Path {
        let center = CGPoint(x: rect.midX, y: rect.midY)
        // Screen angles: 0 at +x, growing clockwise (flipped y); our slice
        // angles run clockwise from 12 o'clock, so shift by a quarter turn.
        let start = Angle(radians: centerAngle - sliceAngle / 2 - .pi / 2)
        let end = Angle(radians: centerAngle + sliceAngle / 2 - .pi / 2)
        var path = Path()
        path.addArc(center: center, radius: innerRadius, startAngle: start, endAngle: end, clockwise: false)
        path.addArc(center: center, radius: outerRadius, startAngle: end, endAngle: start, clockwise: true)
        path.closeSubpath()
        return path
    }
}

/// Real icons and display names for slices that point at the disk, cached so
/// the wheel never touches the file system while the pointer is tracked (a
/// dead network mount would otherwise stall every highlight change).
/// Configurations are tiny (a wheel holds 12 items), so entries accumulate.
enum RadialMenuIconStore {
    private static var icons: [String: NSImage] = [:]
    private static var names: [String: String] = [:]
    private static var customIcons: [UUID: NSImage] = [:]

    static func fileIcon(for payload: String) -> NSImage {
        if let cached = icons[payload] { return cached }
        let path = (payload as NSString).expandingTildeInPath
        let icon = NSWorkspace.shared.icon(forFile: path)
        icon.size = NSSize(width: 34, height: 34)
        icons[payload] = icon
        return icon
    }

    static func customIcon(for item: RadialMenuItem) -> NSImage? {
        guard let data = item.customIconData else { return nil }
        if let cached = customIcons[item.id] { return cached }
        guard let image = NSImage(data: data) else { return nil }
        image.size = NSSize(width: 34, height: 34)
        customIcons[item.id] = image
        return image
    }

    static func fileName(for payload: String) -> String {
        if let cached = names[payload] { return cached }
        let path = (payload as NSString).expandingTildeInPath
        let name = FileManager.default.displayName(atPath: path)
        names[payload] = name
        return name
    }

    static func invalidate(_ payload: String) {
        icons.removeValue(forKey: payload)
        names.removeValue(forKey: payload)
    }

    static func invalidate(item: RadialMenuItem) {
        icons.removeValue(forKey: item.payload)
        names.removeValue(forKey: item.payload)
        customIcons.removeValue(forKey: item.id)
    }
}

/// Name resolution shared by the wheel and the Settings editor: a custom name
/// wins, everything else derives from the target in the user's language.
extension RadialMenuItem {
    func displayName(_ text: RadialMenuFeatureStrings,
                     nowPlayingState: RadialNowPlayingState? = nil) -> String {
        if !name.isEmpty { return name }
        switch kind {
        case .app, .file:
            return RadialMenuIconStore.fileName(for: payload)
        case .url:
            let normalized = RadialMenuSupport.normalizedURL(payload) ?? payload
            return URL(string: normalized)?.host ?? payload
        case .shortcut:
            return GlobalShortcut(storageValue: payload)?.displayString ?? text.kindShortcut
        case .tool:
            guard let tool else { return text.kindTool }
            return tool.feature.hubTitle(L10n.shared.s, hub: FeatureStrings.hub(L10n.shared.language))
        case .quickToggle:
            return quickToggle?.radialTitle ?? FeatureStrings.quickToggles(L10n.shared.language).pageTitle
        case .windowLayout:
            guard let windowLayoutAction else {
                return FeatureStrings.windowLayout(L10n.shared.language).title
            }
            return windowLayoutAction.title(FeatureStrings.windowLayout(L10n.shared.language))
        case .media:
            switch mediaKey {
            case .playPause: return text.mediaPlayPause
            case .previousTrack: return text.mediaPrevious
            case .nextTrack: return text.mediaNext
            case .nowPlaying:
                switch nowPlayingState {
                case let .some(.playing(snapshot)): return snapshot.radialLabel ?? text.mediaNowPlaying
                case .some(.nothingPlaying): return text.mediaNothingPlaying
                case .some(.loading), .none: return text.mediaNowPlaying
                }
            case nil: return text.kindMedia
            }
        case .submenu:
            return text.kindSubmenu
        }
    }

    var usesFileIcon: Bool {
        (kind == .app || kind == .file) && symbolName.isEmpty
    }
}

extension RadialMenuQuickToggle {
    var radialTitle: String {
        let strings = FeatureStrings.quickToggles(L10n.shared.language)
        let toggles = QuickTogglesService.shared
        switch self {
        case .darkMode:
            return toggles.systemAppearanceIsDark == true ? strings.darkModeToLight : strings.darkModeToDark
        case .emptyTrash: return strings.emptyTrashTitle
        case .ejectDisks: return strings.ejectTitle
        case .hiddenFiles: return toggles.hiddenFilesShown ? strings.hiddenFilesHide : strings.hiddenFilesShow
        case .desktopIcons: return toggles.desktopIconsShown ? strings.desktopIconsHide : strings.desktopIconsShow
        case .lockScreen: return strings.lockScreenTitle
        case .displayOff: return strings.displayOffTitle
        case .screenSaver: return strings.screenSaverTitle
        }
    }
}
