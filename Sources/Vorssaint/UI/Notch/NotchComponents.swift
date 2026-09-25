// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import SwiftUI

/// Feedback is local to a visible control. No recurring work is needed.
/// The pointer lifts a control slightly and a press settles it back, which is
/// what makes the panel feel physical rather than painted on.
struct NotchButtonStyle: ButtonStyle {
    var cornerRadius: CGFloat = 10
    var lifts = true
    @State private var hovered = false
    @Environment(\.isEnabled) private var enabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        let active = enabled && hovered
        configuration.label
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(.white.opacity(active ? 0.09 : 0))
                    .allowsHitTesting(false)
            }
            .opacity(enabled ? (configuration.isPressed ? 0.8 : 1) : 0.4)
            .scaleEffect(reduceMotion || !lifts ? 1
                         : configuration.isPressed ? 0.965 : (active ? 1.022 : 1))
            .animation(reduceMotion ? nil : .spring(response: 0.28, dampingFraction: 0.7),
                       value: configuration.isPressed)
            .animation(reduceMotion ? nil : .spring(response: 0.32, dampingFraction: 0.75), value: hovered)
            .onHover { hovered = $0 }
    }
}

extension NotchArtworkTint {
    var color: Color { Color(.sRGB, red: red, green: green, blue: blue, opacity: 1) }
}

/// The bars with the live levels attached. Only this small view observes the
/// audio service, so its thirty updates a second never re-render the island.
struct NotchLiveEqualizerBars: View {
    var isPlaying = true
    var bars = 4
    var barWidth: CGFloat = 2.5
    var height: CGFloat = 14
    var tint: Color = .white
    @ObservedObject private var audio = NotchAudioLevelService.shared

    var body: some View {
        NotchEqualizerBars(isPlaying: isPlaying, bars: bars, barWidth: barWidth, height: height, tint: tint,
                           live: audio.levels)
    }
}

/// A level readout in the same language as the notch's sliders, instead of the
/// thin system bar, so every meter in the panel matches.
struct NotchMeter: View {
    let value: Double
    var height: CGFloat = 5
    var tint: Color = .white

    var body: some View {
        let fraction = value.isFinite ? min(1, max(0, value)) : 0
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule(style: .continuous).fill(.white.opacity(0.14))
                Capsule(style: .continuous)
                    .fill(tint.opacity(0.9))
                    .frame(width: max(fraction > 0 ? height : 0, proxy.size.width * fraction))
            }
        }
        .frame(height: height)
        .accessibilityHidden(true)
    }
}

struct NotchIconButton: View {
    let symbol: String
    let title: String
    var selected = false
    let action: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(selected ? .white : .white.opacity(0.55))
                .contentTransition(.symbolEffect(.replace))
                .animation(reduceMotion ? nil : .smooth(duration: 0.24), value: symbol)
                .frame(width: 28, height: 28)
                .background(.white.opacity(selected ? 0.12 : 0),
                            in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                .contentShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
        }
        .buttonStyle(NotchButtonStyle(cornerRadius: 9))
        .help(title)
        .accessibilityLabel(title)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// A short island puts the glyph beside its message; taller ones stack them.
struct NotchEmptyView: View {
    let symbol: String
    let message: String

    var body: some View {
        ViewThatFits(in: .vertical) {
            VStack(spacing: 12) {
                glyph
                label.frame(maxWidth: 250)
            }
            HStack(spacing: 14) {
                glyph
                label.frame(maxWidth: 260, alignment: .leading)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var glyph: some View {
        Image(systemName: symbol)
            .font(.system(size: 26, weight: .light))
            .foregroundStyle(.white.opacity(0.65))
            .frame(width: 56, height: 56)
            .background(.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .accessibilityHidden(true)
    }

    private var label: some View {
        Text(message)
            .font(.system(size: 12))
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }
}

struct NotchArtwork: View {
    let image: NSImage?
    let size: CGFloat

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image).resizable().scaledToFill()
            } else {
                Color.black.overlay {
                    Image(systemName: "music.note")
                        .font(.system(size: size * 0.3, weight: .light))
                        .foregroundStyle(.white.opacity(0.45))
                }
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: size * 0.19, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: size * 0.19, style: .continuous)
                .strokeBorder(.white.opacity(0.12), lineWidth: 0.5)
        }
        .accessibilityHidden(true)
    }
}

/// Items fill each column top to bottom and continue sideways, so a short
/// island scrolls to the side and never down. Whenever everything fits
/// without scrolling, the items read left to right instead, in rows of equal
/// cells across the full width, and a short last row sits centered.
struct NotchRail<Item: Identifiable, Content: View>: View {
    let items: [Item]
    let rows: Int
    let itemWidth: CGFloat
    let width: CGFloat
    var spacing: CGFloat = 8
    var rowSpacing: CGFloat = 8
    var scrollTarget: Item.ID? = nil
    @ViewBuilder let content: (Item) -> Content
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var columns: Int { NotchLayout.railColumns(count: items.count, rows: rows) }
    private var starts: [Int] { Array(stride(from: 0, to: items.count, by: max(1, rows))) }
    private var rowStarts: [Int] { Array(stride(from: 0, to: items.count, by: max(1, columns))) }
    private var fits: Bool {
        NotchLayout.railFits(columns: columns, itemWidth: itemWidth, spacing: spacing, width: width)
    }

    // Scroll to the column itself: its identity is known before lazy children
    // are created, including a target well outside the current viewport.
    private var targetColumn: Int? {
        guard let scrollTarget, let index = items.firstIndex(where: { $0.id == scrollTarget }) else { return nil }
        return index / max(1, rows) * max(1, rows)
    }

    var body: some View {
        if fits {
            let cell = (width - CGFloat(max(0, columns - 1)) * spacing) / CGFloat(max(1, columns))
            VStack(spacing: rowSpacing) {
                ForEach(rowStarts, id: \.self) { start in row(start, cell: cell) }
            }
        } else {
            ScrollViewReader { proxy in
                // Legacy scroll bars would take a row's worth of height; the
                // column cut at the edge is the cue that more follows.
                ScrollView(.horizontal) {
                    LazyHStack(alignment: .top, spacing: spacing) {
                        ForEach(starts, id: \.self) { start in column(start).frame(width: itemWidth).id(start) }
                    }
                    .contentShape(Rectangle())
                }
                .scrollIndicators(.never)
                .onAppear {
                    if let targetColumn { proxy.scrollTo(targetColumn, anchor: .center) }
                }
                .onChange(of: targetColumn) { _, target in
                    guard let target else { return }
                    withAnimation(reduceMotion ? nil : .easeOut(duration: 0.16)) {
                        proxy.scrollTo(target, anchor: .center)
                    }
                }
            }
        }
    }

    private func row(_ start: Int, cell: CGFloat) -> some View {
        HStack(alignment: .top, spacing: spacing) {
            ForEach(items[start..<min(items.count, start + max(1, columns))]) { item in
                content(item).frame(width: cell)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func column(_ start: Int) -> some View {
        VStack(spacing: rowSpacing) {
            ForEach(items[start..<min(items.count, start + max(1, rows))]) { item in
                content(item)
            }
        }
    }
}

private struct NotchGlassSurfaceKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    var notchGlassSurface: Bool {
        get { self[NotchGlassSurfaceKey.self] }
        set { self[NotchGlassSurfaceKey.self] = newValue }
    }

    /// A page drawn in Settings to preview the island. It shows what the
    /// island shows but must leave the island's state and the keyboard alone.
    var notchSettingsPreview: Bool {
        get { self[NotchSettingsPreviewKey.self] }
        set { self[NotchSettingsPreviewKey.self] = newValue }
    }
}

private struct NotchSettingsPreviewKey: EnvironmentKey {
    static let defaultValue = false
}

/// The native host publishes the same path used by its animated mask. Keeping
/// this in canvas coordinates avoids scaling the glass's corners independently.
final class NotchBackdropPresentation: ObservableObject {
    @Published var contour = Path()
    @Published var usesGlass = false
    @Published private(set) var fade = NotchGlassFade.open

    /// Measured from the top edge, as the fade is planned: a floating
    /// capsule's contour starts below it.
    var openness: Double { Double(fade.openness(atHeight: contourBottom)) }
    private var contourBottom: CGFloat { contour.boundingRect.isNull ? 0 : contour.boundingRect.maxY }

    /// How much of the resting black still lies beneath the glass. It lets go
    /// a stretch after the glass opens: the drawn gradient trails the island
    /// by a frame as it grows, and uncovered clear glass read as a grey flash.
    var restingBlack: Double {
        1 - Double(fade.openness(atHeight: contourBottom - fade.blackLag))
    }

    /// Plans a resize from `start` to `end` from what is on screen now.
    func planFade(from start: CGFloat, to end: CGFloat, endsInGlass: Bool) {
        setFade(.plan(from: start, to: end, endsInGlass: endsInGlass,
                      current: usesGlass ? fade.openness(atHeight: start) : 0))
    }

    func openFully() { setFade(.open) }

    /// The fade follows the moving contour frame by frame; SwiftUI must not
    /// add an animation of its own on top.
    private func setFade(_ next: NotchGlassFade) {
        guard fade != next else { return }
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) { fade = next }
    }
}

struct NotchBackdropShape: Shape {
    var contour: Path
    func path(in rect: CGRect) -> Path { contour }
}

struct NotchWindowBackground: View {
    @ObservedObject var presentation: NotchBackdropPresentation
    @AppStorage(DefaultsKey.liquidGlassEnabled) private var glass = false

    var body: some View {
        NotchSurfaceBackground(presentation: presentation, glass: glass)
    }
}

/// Keep the upper content dark and open the lower surface into a refractive lip.
struct NotchSurfaceBackground: View {
    @ObservedObject var presentation: NotchBackdropPresentation
    let glass: Bool
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    private var offersGlass: Bool {
#if compiler(>=6.2)
        if #available(macOS 26, *) { return glass && !reduceTransparency }
#endif
        return false
    }

    private var showsGlass: Bool { offersGlass && presentation.usesGlass }

    var body: some View {
        ZStack {
            // The black the island rests in stays beneath the glass until
            // the glass has opened, and the glass exists only while that
            // black lets it show, so the window's resizes at either end of a
            // transition happen in plain black.
            Color.black.opacity(showsGlass ? presentation.restingBlack : 1)
#if compiler(>=6.2)
            if #available(macOS 26, *), showsGlass, presentation.restingBlack < 1 {
                let shape = NotchBackdropShape(contour: presentation.contour)
                Color.clear
                    .glassEffect(.clear, in: shape)
                    .environment(\.appearsActive, true)
                    .materialActiveAppearance(.active)
                    .overlay {
                        LinearGradient(stops: Self.shade(openness: presentation.openness, contrast: contrast),
                                       startPoint: .top, endPoint: .bottom)
                            .frame(height: presentation.contour.boundingRect.height)
                            .frame(maxHeight: .infinity, alignment: .top)
                            .mask(shape)
                    }
            }
#endif
        }
        .environment(\.colorScheme, .dark)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    /// The dimming over the glass, from the top of the island to its lip. Near
    /// a black strip the lip closes up, so the last frames of a collapse
    /// already match the resting island.
    static func shade(openness: Double, contrast: ColorSchemeContrast) -> [Gradient.Stop] {
        (0...64).map { index in
            let t = Double(index) / 64
            return Gradient.Stop(
                color: .black.opacity(1 - openness * (contrast == .increased ? 0.10 : 0.45) * pow(t, 2.5)),
                location: t)
        }
    }
}

/// Controls on the glass shell use quiet translucent fills, leaving the
/// refraction to the island rather than stacking separate glass lenses.
struct NotchControlSurface: ViewModifier {
    let cornerRadius: CGFloat
    var selected = false
    var interactive = true
    @AppStorage(DefaultsKey.liquidGlassEnabled) private var glass = false
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.notchGlassSurface) private var glassSurface

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        Group {
            if glassSurface {
                content
                    .background(.white.opacity(selected ? 0.11 : 0.045), in: shape)
                    .overlay {
                        shape.strokeBorder(.white.opacity(selected ? 0.16 : 0.065), lineWidth: 0.5)
                            .allowsHitTesting(false)
                    }
            } else {
#if compiler(>=6.2)
                if #available(macOS 26, *), glass, !reduceTransparency {
                    content.background(.white.opacity(selected ? 0.12 : 0.065), in: shape)
                        .glassEffect(.regular.interactive(interactive), in: shape)
                } else {
                    content.background(.white.opacity(selected ? 0.12 : 0.065), in: shape)
                }
#else
                content.background(.white.opacity(selected ? 0.12 : 0.065), in: shape)
#endif
            }
        }
        .overlay {
            shape.strokeBorder(.white.opacity(contrast == .increased ? 0.5 : 0), lineWidth: 0.75)
                .allowsHitTesting(false)
        }
    }
}

/// One entry of a native menu popped up from a SwiftUI control.
struct NotchMenuItem {
    let title: String
    var checked = false
    var symbol: String? = nil
    var enabled = true
    var action: () -> Void = {}

    /// A line between groups of entries.
    static let separator = NotchMenuItem(title: "")
    var isSeparator: Bool { title.isEmpty }
}

/// A control SwiftUI draws in full that pops up a native menu. `Menu`
/// cannot do this: its borderless style turns the label into a pop-up
/// button title, one line cut with an ellipsis, images moved to the front
/// and frames ignored, so anything but a lone glyph loses its shape.
struct NotchMenuButton<Label: View>: View {
    let title: String
    let items: [NotchMenuItem]
    var cornerRadius: CGFloat = 6
    @ViewBuilder let label: () -> Label
    @State private var anchor = NotchMenuAnchor()

    var body: some View {
        Button { anchor.popUp(items) } label: { label() }
            .buttonStyle(NotchButtonStyle(cornerRadius: cornerRadius, lifts: false))
            .background(NotchMenuAnchorView(anchor: anchor))
            .accessibilityLabel(title)
    }
}

/// A chooser whose current choice reads in full: up to two centred lines, or
/// one line cut in the middle, with the list as a native menu below it.
struct NotchDeviceMenu: View {
    let title: String
    let current: String
    var width: CGFloat = 100
    var lines = 2
    var alignment: TextAlignment = .center
    let items: [NotchMenuItem]

    var body: some View {
        NotchMenuButton(title: title, items: items) {
            Text("\(current) \(Image(systemName: "chevron.down"))")
                .font(.system(size: 10, weight: .medium))
                .lineLimit(lines)
                .multilineTextAlignment(alignment)
                .truncationMode(lines > 1 ? .tail : .middle)
                .foregroundStyle(.secondary)
                .frame(maxWidth: width, alignment: frameAlignment)
                .padding(.horizontal, 4)
                .contentShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        }
        .help(current)
        .accessibilityValue(current)
    }

    private var frameAlignment: Alignment {
        switch alignment {
        case .leading: return .leading
        case .center: return .center
        case .trailing: return .trailing
        }
    }
}

/// Owns the native menu's targets while it is up and remembers the view it
/// pops up from. Menu tracking keeps the island open on its own.
final class NotchMenuAnchor: NSObject {
    fileprivate weak var view: NSView?
    private var actions: [() -> Void] = []

    func popUp(_ items: [NotchMenuItem]) {
        guard let view else { return }
        actions = items.map(\.action)
        let menu = NSMenu()
        menu.autoenablesItems = false
        for (index, item) in items.enumerated() {
            guard !item.isSeparator else { menu.addItem(.separator()); continue }
            let entry = NSMenuItem(title: item.title, action: #selector(choose(_:)), keyEquivalent: "")
            entry.target = self
            entry.tag = index
            entry.state = item.checked ? .on : .off
            entry.isEnabled = item.enabled
            if let symbol = item.symbol {
                entry.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
            }
            menu.addItem(entry)
        }
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: 0), in: view)
    }

    @objc private func choose(_ sender: NSMenuItem) {
        guard actions.indices.contains(sender.tag) else { return }
        actions[sender.tag]()
    }
}

private struct NotchMenuAnchorView: NSViewRepresentable {
    let anchor: NotchMenuAnchor

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        anchor.view = view
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        anchor.view = nsView
    }
}

extension NSAlert {
    /// A SwiftUI alert or confirmation dialog hangs from the island as a
    /// sheet, which moves and reskins the borderless surface. Inside the
    /// island a tool asks the same question on its own, just above it, like
    /// the Scratchpad page does, and the island gets the keyboard back after.
    static func confirmAboveIsland(_ title: String, message: String, action: String,
                                   destructive: Bool, cancel: String) -> Bool {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.addButton(withTitle: action).hasDestructiveAction = destructive
        // Escape cancels in every language, like the dialog's cancel role.
        alert.addButton(withTitle: cancel).keyEquivalent = "\u{1b}"
        return alert.runAboveIsland() == .alertFirstButtonReturn
    }

    private func runAboveIsland() -> NSApplication.ModalResponse {
        let island = NotchService.shared.presentationWindow
        var observers: [NSObjectProtocol] = []
        if let island {
            // The modal session puts the alert at the modal panel level, below
            // the island, and puts it back there when it activates the app or
            // makes the alert key. Raise it once running and after each of those.
            let level = NSWindow.Level(rawValue: island.level.rawValue + 1)
            let alertWindow = window
            let raise: (Notification) -> Void = { _ in alertWindow.level = level }
            observers = [NSWindow.didBecomeKeyNotification, NSApplication.didBecomeActiveNotification].map {
                NotificationCenter.default.addObserver(forName: $0, object: nil, queue: .main, using: raise)
            }
            DispatchQueue.main.async { alertWindow.level = level }
        }
        NSApp.activate(ignoringOtherApps: true)
        let response = runModal()
        observers.forEach(NotificationCenter.default.removeObserver)
        // A closed island declines key status, so this only returns to an open one.
        if let island, island.isVisible { island.makeKey() }
        return response
    }
}
