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
        var neverUsed: [AppFeature] { features.offersNeverUsed ? [.notch] : [] }
        let recentlyUninstalled: [AppFeature] = []
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
                    if [.clipboardHistory, .mixer, .screenRecorder, .fanControl].contains(feature) {
                        FeatureRow(feature: feature).frame(height: 44)
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

    final class FeatureRowView: NSView {
        var feature: AppFeature?
    }
    struct FeatureRow: NSViewRepresentable {
        let feature: AppFeature
        func makeNSView(context: Context) -> FeatureRowView {
            let view = FeatureRowView()
            view.feature = feature
            return view
        }
        func updateNSView(_ view: FeatureRowView, context: Context) { view.feature = feature }
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
        guard let document = scroll.documentView else {
            suite.expect(false, "the Features page has a scroll document")
            return
        }
        func scrollToOffset(_ y: CGFloat) {
            let bottom = max(0, document.frame.height - scroll.contentView.bounds.height)
            scroll.contentView.scroll(to: NSPoint(x: 0, y: min(bottom, max(0, y))))
            scroll.reflectScrolledClipView(scroll.contentView)
        }
        // A fixed catalog must not change height as more cards enter view.
        // Reverse direction and jump past cards, including at a wider width.
        for width: CGFloat in [560, 820] {
            window.setContentSize(NSSize(width: width, height: 848))
            settle()
            let height = document.frame.height
            suite.expect(height.isFinite && height > scroll.contentView.bounds.height,
                         "the Features catalog has a finite scrollable height at \(width)pt")
            let bottom = max(0, height - scroll.contentView.bounds.height)
            for fraction: CGFloat in [0, 0.25, 0.5, 0.75, 1, 0.9, 0.7, 0.4, 0.1, 0, 1, 0.35, 0.85, 0] {
                let target = bottom * fraction
                scrollToOffset(target)
                settle()
                suite.expect(abs(document.frame.height - height) < 2,
                             "scrolling to \(fraction) at \(width)pt does not re-estimate the catalog height")
                suite.expect(abs(scroll.contentView.bounds.minY - target) < 2,
                             "scrolling to \(fraction) at \(width)pt reaches the requested offset")
            }
        }
        window.setContentSize(NSSize(width: 560, height: 848))
        settle()
        // A notice the user can still see grows normally, without scrolling
        // the page away from its title or tab picker.
        for offset: CGFloat in [0, 40] {
            runtime.needsRestartToUnload = false
            runtime.offersNeverUsed = false
            settle()
            scrollToOffset(offset)
            settle()
            for (offers, restart) in [(true, false), (true, true), (false, true), (false, false)] {
                withAnimation(.easeOut(duration: 0.22)) {
                    runtime.offersNeverUsed = offers
                    runtime.needsRestartToUnload = restart
                }
                settle()
                suite.expect(abs(scroll.contentView.bounds.minY - offset) < 2,
                             "a visible notice leaves the viewport at \(offset)pt")
            }
        }
        // Lay out a notice without draining the main queue, leaving the
        // asynchronous compensation pending when another action intervenes.
        for resize in [false, true] {
            runtime.needsRestartToUnload = false
            runtime.offersNeverUsed = true
            settle()
            scrollToOffset(document.frame.height / 2)
            settle()
            let previousHeight = document.frame.height
            runtime.needsRestartToUnload = true
            host.needsLayout = true
            host.layoutSubtreeIfNeeded()
            suite.expect(abs(document.frame.height - previousHeight) > 2,
                         "the notice changes layout before its pending scroll adjustment")
            if resize {
                window.setContentSize(NSSize(width: 560, height: 720))
                host.needsLayout = true
                host.layoutSubtreeIfNeeded()
            } else {
                scrollToOffset(scroll.contentView.bounds.minY - 240)
            }
            let requestedOffset = scroll.contentView.bounds.minY
            settle()
            suite.expect(abs(scroll.contentView.bounds.minY - requestedOffset) < 2,
                         "a pending notice adjustment does not override \(resize ? "a resized viewport" : "a new scroll or navigation")")
            window.setContentSize(NSSize(width: 560, height: 848))
            settle()
        }
        func rowFrame(_ feature: AppFeature) -> NSRect? {
            guard let row = row(feature, in: host) else { return nil }
            return row.convert(row.bounds, to: host)
        }
        // Check the middle of the page as well as the last row: staying at
        // the document's bottom alone can hide a lost offscreen anchor.
        for feature: AppFeature in [.clipboardHistory, .mixer, .screenRecorder, .fanControl] {
            runtime.needsRestartToUnload = false
            runtime.offersNeverUsed = true
            settle()
            guard let marker = row(feature, in: host) else {
                suite.expect(false, "\(feature.rawValue) has a laid-out row before scrolling")
                continue
            }
            scrollToOffset(marker.convert(marker.bounds, to: document).midY - scroll.contentView.bounds.height / 2)
            settle()
            guard let initial = rowFrame(feature), host.bounds.contains(initial) else {
                suite.expect(false, "\(feature.rawValue) is visible before changing availability")
                continue
            }
            // Uninstall adds the restart notice above the viewport; reinstall
            // removes it. Repeat without scrolling, as in the reported failure.
            for restart in [true, false, true, false] {
                withAnimation(.easeOut(duration: 0.22)) {
                    runtime.needsRestartToUnload = restart
                }
                settle()
                let current = rowFrame(feature)
                suite.expect(current.map { host.bounds.contains($0) } == true,
                             "\(feature.rawValue) stays visible when the offscreen restart notice is \(restart ? "added" : "removed")")
                suite.expect(current.map { abs($0.midY - initial.midY) < 2 } == true,
                             "changing the restart notice preserves \(feature.rawValue)'s position: \(String(describing: current)) vs \(initial)")
                suite.expect(abs(scroll.contentView.bounds.minY
                    - scroll.contentView.constrainBoundsRect(scroll.contentView.bounds).minY) < 2,
                             "changing the restart notice keeps the viewport inside the document")
            }
            // Uninstalling the last of three never-used features takes that
            // offer away above the viewport too, with or without a notice.
            for (offers, restart) in [(false, true), (true, false), (false, true), (true, true), (false, true)] {
                withAnimation(.easeOut(duration: 0.22)) {
                    runtime.offersNeverUsed = offers
                    runtime.needsRestartToUnload = restart
                }
                settle()
                let current = rowFrame(feature)
                suite.expect(current.map { host.bounds.contains($0) } == true,
                             "\(feature.rawValue) stays visible when the offscreen never-used offer is \(offers ? "added" : "removed")")
                suite.expect(current.map { abs($0.midY - initial.midY) < 2 } == true,
                             "changing the never-used offer preserves \(feature.rawValue)'s position: \(String(describing: current)) vs \(initial)")
                suite.expect(abs(scroll.contentView.bounds.minY
                    - scroll.contentView.constrainBoundsRect(scroll.contentView.bounds).minY) < 2,
                             "changing the never-used offer keeps the viewport inside the document")
            }
        }
    }

    private static func row(_ feature: AppFeature, in view: NSView) -> FeatureRowView? {
        if let match = view as? FeatureRowView, match.feature == feature { return match }
        return view.subviews.lazy.compactMap { row(feature, in: $0) }.first
    }

    private static func descendant<T: NSView>(_ type: T.Type, in view: NSView) -> T? {
        if let match = view as? T { return match }
        return view.subviews.lazy.compactMap { descendant(type, in: $0) }.first
    }
}
