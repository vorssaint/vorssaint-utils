// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import SwiftUI

/// Exercises the production hub's scroll layout with inert cards: installing
/// a feature must not start services just to check where its row is drawn.
enum FeatureHubLayoutTests {
    final class FeatureRuntime: ObservableObject {
        static let shared = FeatureRuntime()
        @Published var needsRestartToUnload = false
        @Published var offersNeverUsed = false
        func apply(_ preset: FeaturePreset) {}
        func relaunchApp() {}
    }

    struct Page: View {
        typealias FeatureRuntime = FeatureHubLayoutTests.FeatureRuntime
        typealias SettingsCard<Content: View> = FeatureHubLayoutTests.SettingsCard<Content>
        typealias PermissionsPortalSections = FeatureHubLayoutTests.PermissionsPortalSections
        enum Tab { case features, permissions }
        @ObservedObject var features = FeatureRuntime.shared
        @State var tab = Tab.features
        @State var confirmingPreset: FeaturePreset?
        let hub = FeatureStrings.hub(.enUS)
        var body: some View { content }
        func presetName(_ preset: FeaturePreset) -> String { "Preset" }
        var summaryCard: some View { Text("Installed features").frame(height: 90) }
        @ViewBuilder var neverUsedCard: some View {
            if features.offersNeverUsed { Text("Never used").frame(height: 120) }
        }
        var dynamicIslandCard: some View {
            Text("Dynamic Island").frame(height: 900).id(FeatureGroup.dynamicIsland)
        }
        var presetsCard: some View { Text("Presets").frame(height: 180) }
        func groupCard(_ group: FeatureGroup) -> some View {
            SettingsCard {
                Text(group.rawValue)
                ForEach(AppFeature.features(in: group), id: \.self) { feature in
                    if feature == .fanControl {
                        FanRow().frame(height: 44)
                    } else {
                        Text(feature.rawValue).frame(height: 44)
                    }
                }
            }
            .id(group)
        }
    }

    struct PermissionsPortalSections: View {
        let hub: FeatureHubStrings
        var body: some View { Text("Permissions") }
    }

    final class FanRowView: NSView {}
    struct FanRow: NSViewRepresentable {
        func makeNSView(context: Context) -> FanRowView { FanRowView() }
        func updateNSView(_ view: FanRowView, context: Context) {}
    }

    static func run(_ suite: TestSuite) {
        _ = NSApplication.shared
        let runtime = FeatureRuntime.shared
        runtime.needsRestartToUnload = false
        runtime.offersNeverUsed = true
        let host = NSHostingView(rootView: Page())
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 560, height: 848),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        defer {
            window.close()
            runtime.needsRestartToUnload = false
            runtime.offersNeverUsed = false
        }
        func settle() {
            let deadline = Date().addingTimeInterval(0.3)
            while Date() < deadline {
                host.layoutSubtreeIfNeeded()
                RunLoop.current.run(until: min(deadline, Date().addingTimeInterval(0.01)))
            }
        }
        settle()
        guard let scroll = descendant(NSScrollView.self, in: host) else {
            suite.expect(false, "the Features page draws a scroll view")
            return
        }
        // Visit the intervening cards, as when scrolling down to Fan Control.
        for _ in 0..<24 {
            let bottom = max(0, (scroll.documentView?.frame.height ?? 0) - scroll.contentView.bounds.height)
            scroll.contentView.scroll(to: NSPoint(x: 0, y: min(bottom, scroll.contentView.bounds.minY + 500)))
            scroll.reflectScrolledClipView(scroll.contentView)
            settle()
        }
        func rowFrame() -> NSRect? {
            guard let row = descendant(FanRowView.self, in: host) else { return nil }
            return row.convert(row.bounds, to: host)
        }
        guard let initial = rowFrame(), host.bounds.contains(initial) else {
            suite.expect(false, "Fan Control is visible before changing availability")
            return
        }
        // Uninstall adds the restart notice above the viewport; reinstall
        // removes it. Repeat without scrolling, as in the reported failure.
        for restart in [true, false, true, false] {
            withAnimation(.easeOut(duration: 0.22)) {
                runtime.needsRestartToUnload = restart
            }
            settle()
            let current = rowFrame()
            suite.expect(current.map { host.bounds.contains($0) } == true,
                         "Fan Control stays visible when the offscreen restart notice is \(restart ? "added" : "removed")")
            suite.expect(current.map { abs($0.midY - initial.midY) < 2 } == true,
                         "changing the restart notice preserves the visible row's position: \(String(describing: current)) vs \(initial)")
        }
        // Uninstalling the last of three never-used features takes that offer
        // away above the viewport too, along with the restart notice or while
        // an earlier uninstall already shows it.
        for (offers, restart) in [(false, true), (true, false), (false, true), (true, true), (false, true)] {
            withAnimation(.easeOut(duration: 0.22)) {
                runtime.offersNeverUsed = offers
                runtime.needsRestartToUnload = restart
            }
            settle()
            let current = rowFrame()
            suite.expect(current.map { host.bounds.contains($0) } == true,
                         "Fan Control stays visible when the offscreen never-used offer is \(offers ? "added" : "removed")")
            suite.expect(current.map { abs($0.midY - initial.midY) < 2 } == true,
                         "changing the never-used offer preserves the visible row's position: \(String(describing: current)) vs \(initial)")
        }
    }

    private static func descendant<T: NSView>(_ type: T.Type, in view: NSView) -> T? {
        if let match = view as? T { return match }
        return view.subviews.lazy.compactMap { descendant(type, in: $0) }.first
    }
}
