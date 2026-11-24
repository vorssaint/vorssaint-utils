// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import SwiftUI

extension HomeAssistantRGB {
    var color: Color { Color(.sRGB, red: Double(red) / 255, green: Double(green) / 255, blue: Double(blue) / 255, opacity: 1) }
}

private struct HomeAssistantCardVisibleKey: EnvironmentKey { static let defaultValue = true }
extension EnvironmentValues {
    var homeAssistantCardVisible: Bool {
        get { self[HomeAssistantCardVisibleKey.self] }
        set { self[HomeAssistantCardVisibleKey.self] = newValue }
    }
}

/// A local draft keeps dragging responsive without flooding HA with commands.
/// Brightness stays on the card; this wheel chooses hue and saturation only.
struct HomeAssistantColorSelector: View {
    let name: String
    let text: HomeAssistantStrings
    let enabled: Bool
    let apply: (HomeAssistantRGB) -> Void
    let cancel: () -> Void
    @State private var hue: Double
    @State private var saturation: Double

    init(name: String, initial: HomeAssistantRGB, text: HomeAssistantStrings, enabled: Bool,
         apply: @escaping (HomeAssistantRGB) -> Void, cancel: @escaping () -> Void) {
        self.name = name; self.text = text; self.enabled = enabled; self.apply = apply; self.cancel = cancel
        var hue: CGFloat = 0, saturation: CGFloat = 0, brightness: CGFloat = 0, alpha: CGFloat = 1
        NSColor(srgbRed: Double(initial.red) / 255, green: Double(initial.green) / 255, blue: Double(initial.blue) / 255, alpha: 1)
            .getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: &alpha)
        _hue = State(initialValue: Double(hue)); _saturation = State(initialValue: Double(saturation))
    }
    private var rgb: HomeAssistantRGB {
        let color = NSColor(hue: hue, saturation: saturation, brightness: 1, alpha: 1).usingColorSpace(.sRGB)!
        return HomeAssistantRGB(red: Int((color.redComponent * 255).rounded()), green: Int((color.greenComponent * 255).rounded()),
                                blue: Int((color.blueComponent * 255).rounded()))
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(text[.selectColor]).font(.headline)
            HStack {
                Circle().fill(rgb.color).frame(width: 16, height: 16)
                Text(name).font(.subheadline).lineLimit(2)
            }
            wheel.frame(maxWidth: .infinity)
            VStack(alignment: .leading, spacing: 4) {
                Text(text[.hue]).font(.caption)
                Slider(value: $hue, in: 0...1).accessibilityLabel(text[.hue])
                Text(text[.saturation]).font(.caption)
                Slider(value: $saturation, in: 0...1).accessibilityLabel(text[.saturation])
            }
            Text(text[.colorHint]).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            HStack {
                Button(text[.cancelColor], action: cancel).keyboardShortcut(.cancelAction)
                Spacer()
                Button(text[.applyColor]) { apply(rgb) }.keyboardShortcut(.defaultAction).disabled(!enabled)
            }
        }.padding(16).frame(width: 280)
    }
    private var wheel: some View {
        GeometryReader { geometry in
            let radius = geometry.size.width / 2
            ZStack {
                Circle().fill(AngularGradient(colors: (0...6).map { Color(hue: Double($0) / 6, saturation: 1, brightness: 1) }, center: .center))
                Circle().fill(RadialGradient(colors: [.white, .white.opacity(0)], center: .center, startRadius: 0, endRadius: radius))
                Circle().fill(rgb.color).frame(width: 14, height: 14)
                    .overlay { Circle().strokeBorder(.white, lineWidth: 2) }
                    .shadow(color: .black.opacity(0.5), radius: 2)
                    .offset(x: cos(hue * 2 * .pi) * saturation * radius,
                            y: sin(hue * 2 * .pi) * saturation * radius)
            }.contentShape(Circle())
                .gesture(DragGesture(minimumDistance: 0).onChanged { value in
                    let x = value.location.x - radius, y = value.location.y - radius
                    let angle = atan2(y, x) / (2 * .pi)
                    hue = angle < 0 ? angle + 1 : angle
                    saturation = min(1, max(0, hypot(x, y) / radius))
                })
        }.frame(width: 160, height: 160).accessibilityHidden(true)
    }
}

/// AppKit's secondary click includes the trackpad's two-finger click. Consume
/// only that event on a visible RGB card; regular clicks and sliders pass through.
struct HomeAssistantSecondaryClick: NSViewRepresentable {
    let enabled: Bool
    let action: () -> Void
    func makeNSView(context: Context) -> Capture { Capture() }
    func updateNSView(_ view: Capture, context: Context) { view.enabled = enabled; view.action = action }
    static func dismantleNSView(_ view: Capture, coordinator: ()) { view.stop() }
    final class Capture: NSView {
        var enabled = false { didSet { if enabled != oldValue { syncMonitor() } } }
        var action: (() -> Void)?
        private var monitor: Any?
        override func hitTest(_ point: NSPoint) -> NSView? { nil }
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow(); syncMonitor()
        }
        private func syncMonitor() {
            stop()
            guard enabled, window != nil else { return }
            monitor = NSEvent.addLocalMonitorForEvents(matching: [.rightMouseDown, .leftMouseDown]) { [weak self] event in
                guard let self, self.enabled, event.window === self.window, !self.isHiddenOrHasHiddenAncestor,
                      event.type == .rightMouseDown || event.modifierFlags.contains(.control),
                      self.visibleRect.contains(self.convert(event.locationInWindow, from: nil)) else { return event }
                self.action?()
                return nil
            }
        }
        func stop() { if let monitor { NSEvent.removeMonitor(monitor) }; monitor = nil }
        deinit { stop() }
    }
}
