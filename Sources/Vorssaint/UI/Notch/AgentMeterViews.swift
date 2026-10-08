// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import SwiftUI

struct AgentMeterRing: Identifiable, Equatable {
    var id: String
    var provider: AgentProvider
    var fraction: Double
    var spinning: Bool
    var waiting: Bool
    /// Hover text: the account, whether it is waiting, where the session runs, and when the window resets.
    var detail: String = ""
}

enum AgentMeterRings {
    /// Closed island shows at most six rings, the accounts closest to a full window first.
    static func models(snapshot: AgentUsageSnapshot, waiting: Set<AgentProvider>, settled: Set<AgentProvider> = [],
                       details: [AgentProvider: String] = [:], signedIn: Set<AgentProvider> = [],
                       now: Date) -> [AgentMeterRing] {
        let providers: [AgentProvider] = [.claude, .codex, .cursor]
        var rings: [AgentMeterRing] = []
        for provider in providers {
            let live = snapshot.live.contains { $0.provider == provider }
            let asks = waiting.contains(provider)
            let calm = settled.contains(provider)
            // Resting rings need a session; a live or waiting turn always shows.
            guard live || asks || calm || (signedIn.contains(provider) && snapshot.seen.contains(provider))
                    || (signedIn.contains(provider) && snapshot.limits[provider] != nil) else { continue }
            let fraction = AgentMeterQuota.headline(snapshot.limits[provider]?.windows ?? [])?.usedFraction ?? 0
            rings.append(AgentMeterRing(id: provider.rawValue, provider: provider, fraction: fraction,
                                        spinning: live && !asks && !calm, waiting: asks,
                                        detail: NotchAgentSupport.meterDetail(
                                            provider: provider, live: snapshot.live, waiting: asks,
                                            reason: details[provider], limits: snapshot.limits[provider], now: now)))
        }
        return Array(rings.sorted { $0.fraction > $1.fraction }.prefix(6))
    }
}

struct AgentMeterRingRow: View {
    var rings: [AgentMeterRing]
    var size: CGFloat = 11

    var body: some View {
        HStack(spacing: 4) {
            ForEach(rings) { ring in
                // Thinking fills the slot. Waiting shrinks so the amber ring
                // has room and the mark sits inside it.
                let outer = ring.waiting ? size * 0.82 : size
                let mark = ring.waiting ? outer * 0.52 : outer * 0.72
                Button {
                    AgentMeterFocus.activate(ring.provider)
                } label: {
                    ZStack {
                        if ring.waiting {
                            AgentMeterPulse(tint: .orange, lineWidth: max(1.25, outer * 0.06))
                        }
                        NotchAgentGlyph(provider: ring.provider, size: mark,
                                        working: ring.spinning, waiting: false)
                    }
                    .frame(width: outer, height: outer)
                    .frame(width: size, height: size)
                    .animation(.easeInOut(duration: 0.28), value: ring.waiting)
                    .animation(.easeInOut(duration: 0.28), value: ring.spinning)
                }
                .buttonStyle(.plain)
                .help(ring.detail.isEmpty ? ring.provider.displayName : ring.detail)
                .accessibilityLabel(ring.provider.displayName)
            }
        }
    }
}

/// The waiting ring brightens and settles, and holds still under Reduce Motion.
private struct AgentMeterPulse: View {
    var tint: Color
    var lineWidth: CGFloat
    @State private var bright = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Circle()
            .stroke(tint.opacity(reduceMotion || bright ? 1 : 0.4), lineWidth: lineWidth)
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.85).repeatForever(autoreverses: true), value: bright)
            .onAppear { bright = true }
    }
}

enum AgentMeterFocus {
    static func activate(_ provider: AgentProvider) {
        for identifier in identifiers(provider) {
            if let app = NSRunningApplication.runningApplications(withBundleIdentifier: identifier).first {
                app.activate(options: .activateAllWindows)
                return
            }
        }
        NotchService.shared.openActivity(.agents)
    }

    private static func identifiers(_ provider: AgentProvider) -> [String] {
        switch provider {
        case .claude: return [AgentClaudeAppUsage.bundleIdentifier]
        case .codex: return AgentCodexServer.appIdentifiers
        case .cursor: return ["com.todesktop.230313mzl4w4u92"]
        case .opencode, .copilot: return []
        }
    }
}

enum AgentMeterFeedback {
    static func playFinished() { NSSound(named: "Glass")?.play() }
    static func playWaiting() { NSSound(named: "Ping")?.play() }
}

/// The always-on meter. Off until AI Agents settings turn it on. It draws the
/// same rings as the island and does not raise its own alerts.
final class AgentMeterPin {
    static let shared = AgentMeterPin()
    private var panel: NSPanel?

    func sync() {
        if Thread.isMainThread {
            apply()
        } else {
            DispatchQueue.main.async { self.apply() }
        }
    }

    func place() {
        guard let panel, let screen = panel.screen ?? NSScreen.main else { return }
        let width = panel.frame.width
        let height = panel.frame.height
        let visible = screen.visibleFrame
        let stored = UserDefaults.standard.double(forKey: DefaultsKey.notchAgentsEdgeOffset)
        let x = min(max(visible.minX + 8, visible.midX - width / 2 + stored), visible.maxX - width - 8)
        panel.setFrameOrigin(NSPoint(x: x, y: visible.maxY - height - 4))
    }

    private func apply() {
        let on = UserDefaults.standard.bool(forKey: DefaultsKey.notchAgentsEdgeMeter)
        guard on else {
            panel?.orderOut(nil)
            return
        }
        if panel == nil {
            let host = NSHostingView(rootView: AgentMeterPinView())
            host.frame = NSRect(x: 0, y: 0, width: 168, height: 28)
            let panel = NSPanel(contentRect: host.frame, styleMask: [.borderless, .nonactivatingPanel],
                                backing: .buffered, defer: false)
            panel.isFloatingPanel = true
            panel.level = .statusBar
            panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
            panel.backgroundColor = .clear
            panel.isOpaque = false
            panel.hasShadow = false
            panel.contentView = host
            self.panel = panel
        }
        place()
        panel?.orderFrontRegardless()
    }
}

private struct AgentMeterPinView: View {
    @ObservedObject private var usage = AgentUsageService.shared
    @AppStorage(DefaultsKey.notchAgentsEdgeOffset) private var offset = 0.0
    @State private var dragStart: Double?

    var body: some View {
        AgentMeterRingRow(rings: AgentMeterRings.models(snapshot: usage.snapshot, waiting: usage.meterWaiting,
                                                        settled: usage.meterSettled,
                                                        details: usage.meterWaitingDetail,
                                                        signedIn: usage.meterSignedIn, now: Date()),
                          size: 14)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(.black.opacity(0.82), in: Capsule())
            .gesture(DragGesture().onChanged { value in
                if dragStart == nil { dragStart = offset }
                offset = (dragStart ?? 0) + value.translation.width
                AgentMeterPin.shared.place()
            }.onEnded { _ in
                dragStart = nil
            })
    }
}
