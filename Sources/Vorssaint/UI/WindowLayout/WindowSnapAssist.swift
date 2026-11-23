// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import SwiftUI

/// A window Snap Assist can offer for the rest of a layout.
struct WindowSnapAssistCandidate: Identifiable, Equatable {
    let windowID: CGWindowID
    let pid: pid_t
    let title: String
    let appName: String
    /// The window server's rectangle, in Quartz points.
    let frame: CGRect
    var id: CGWindowID { windowID }

    /// Ordinary windows on the desktop showing, frontmost first, without the
    /// one just placed, Vorssaint's own, or a listed app's.
    static func onScreen(excluding placed: CGWindowID) -> [WindowSnapAssistCandidate] {
        guard let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
            as? [[String: Any]] else { return [] }
        let own = ProcessInfo.processInfo.processIdentifier
        return list.compactMap { info in
            guard (info[kCGWindowLayer as String] as? Int) == 0,
                  let id = info[kCGWindowNumber as String] as? CGWindowID, id != placed,
                  let pid = info[kCGWindowOwnerPID as String] as? pid_t, pid != own,
                  (info[kCGWindowAlpha as String] as? Double ?? 1) > 0,
                  let bounds = info[kCGWindowBounds as String] as? [String: Any],
                  let frame = CGRect(dictionaryRepresentation: bounds as CFDictionary),
                  frame.width >= 160, frame.height >= 120,
                  let app = NSRunningApplication(processIdentifier: pid), app.activationPolicy == .regular,
                  !WindowLayoutIgnoredApps.shared.contains(bundleID: app.bundleIdentifier,
                                                           executablePath: app.executableURL?.path)
            else { return nil }
            let name = app.localizedName ?? (info[kCGWindowOwnerName as String] as? String ?? "")
            let title = (info[kCGWindowName as String] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? name
            return WindowSnapAssistCandidate(windowID: id, pid: pid, title: title, appName: name, frame: frame)
        }
    }
}

final class WindowSnapAssistModel: ObservableObject {
    @Published var candidates: [WindowSnapAssistCandidate] = []
    @Published var thumbnails: [CGWindowID: NSImage] = [:]
}

/// Windows 11's Snap Assist: after a window takes one part of a layout, the
/// other parts offer the remaining windows, and a click puts one there.
/// Escape, or a click anywhere else, ends it.
final class WindowSnapAssist {
    static let shared = WindowSnapAssist()

    typealias Place = (WindowSnapAssistCandidate, WindowLayoutAction) -> Void

    private let model = WindowSnapAssistModel()
    private var panels: [WindowLayoutAction: NSPanel] = [:]
    private var monitors: [Any] = []
    private var place: Place?

    private init() {}

    var isActive: Bool { !panels.isEmpty }

    /// `zones` are the layout's still-empty parts, each with its frame in AppKit points.
    func begin(zones: [(action: WindowLayoutAction, frame: CGRect)], excluding placed: CGWindowID, place: @escaping Place) {
        end()
        let candidates = WindowSnapAssistCandidate.onScreen(excluding: placed)
        guard !zones.isEmpty, !candidates.isEmpty else { return }
        self.place = place
        model.candidates = candidates
        model.thumbnails = [:]
        for zone in zones {
            let panel = makePanel(frame: zone.frame)
            panel.contentView = FirstMouseHostingView(rootView: WindowSnapAssistZoneView(model: model) { [weak self] candidate in
                self?.choose(candidate, for: zone.action)
            })
            panel.alphaValue = 0
            panel.orderFrontRegardless()
            NSAnimationContext.runAnimationGroup { $0.duration = 0.16; panel.animator().alphaValue = 1 }
            panels[zone.action] = panel
        }
        loadThumbnails(for: candidates)
        // A click outside Vorssaint's panels, or Escape, puts the windows back to normal use.
        if let click = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown], handler: { [weak self] _ in self?.end() }) {
            monitors.append(click)
        }
        let escape: (NSEvent) -> Bool = { $0.keyCode == 53 }
        if let key = NSEvent.addGlobalMonitorForEvents(matching: .keyDown, handler: { [weak self] in if escape($0) { self?.end() } }) {
            monitors.append(key)
        }
        if let local = NSEvent.addLocalMonitorForEvents(matching: .keyDown, handler: { [weak self] event in
            guard escape(event) else { return event }
            self?.end()
            return nil
        }) {
            monitors.append(local)
        }
    }

    func end() {
        monitors.forEach(NSEvent.removeMonitor)
        monitors.removeAll()
        for panel in panels.values { fadeOut(panel) }
        panels.removeAll()
        place = nil
        // The window thumbnails are full captures; none is kept once the choice is over.
        model.candidates = []
        model.thumbnails = [:]
    }

    private func choose(_ candidate: WindowSnapAssistCandidate, for action: WindowLayoutAction) {
        place?(candidate, action)
        model.candidates.removeAll { $0.windowID == candidate.windowID }
        if let panel = panels.removeValue(forKey: action) { fadeOut(panel) }
        if panels.isEmpty || model.candidates.isEmpty { end() }
    }

    private func fadeOut(_ panel: NSPanel) {
        NSAnimationContext.runAnimationGroup({ $0.duration = 0.14; panel.animator().alphaValue = 0 },
                                             completionHandler: { panel.orderOut(nil) })
    }

    /// Captures shrunk to card size: a full window capture can run to tens of megabytes.
    private static let thumbnailEdge = 480

    private func loadThumbnails(for candidates: [WindowSnapAssistCandidate]) {
        let model = self.model
        for candidate in candidates.prefix(12) {
            Task {
                guard let image = await WindowPreviewProvider.captureViaWindowServer(candidate.windowID,
                                                                                     waitingForOtherCaptures: false),
                      let small = Self.shrunk(image, to: Self.thumbnailEdge)
                else { return }
                let thumbnail = NSImage(cgImage: small, size: NSSize(width: small.width, height: small.height))
                await MainActor.run {
                    // A capture that comes back after the choice is over is dropped.
                    guard model.candidates.contains(where: { $0.windowID == candidate.windowID }) else { return }
                    model.thumbnails[candidate.windowID] = thumbnail
                }
            }
        }
    }

    private static func shrunk(_ image: CGImage, to edge: Int) -> CGImage? {
        let longest = max(image.width, image.height)
        guard longest > edge else { return image }
        let factor = CGFloat(edge) / CGFloat(longest)
        let width = max(1, Int(CGFloat(image.width) * factor)), height = max(1, Int(CGFloat(image.height) * factor))
        guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue) else { return nil }
        context.interpolationQuality = .medium
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage()
    }

    private func makePanel(frame: CGRect) -> NSPanel {
        let panel = OverlayPanel(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel],
                                 backing: .buffered, defer: false)
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]
        panel.animationBehavior = .none
        panel.setFrame(frame, display: false)
        return panel
    }
}

/// The first click on a window that is not key still reaches its buttons.
private final class FirstMouseHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

private struct WindowSnapAssistZoneView: View {
    @ObservedObject var model: WindowSnapAssistModel
    let choose: (WindowSnapAssistCandidate) -> Void

    var body: some View {
        GeometryReader { proxy in
            let columns = max(1, min(4, Int(proxy.size.width / 220)))
            ScrollView {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 14), count: columns), spacing: 14) {
                    ForEach(model.candidates) { candidate in
                        WindowSnapAssistCard(candidate: candidate, thumbnail: model.thumbnails[candidate.windowID]) {
                            choose(candidate)
                        }
                    }
                }
                .padding(18)
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(.white.opacity(0.18), lineWidth: 1))
            .padding(4)
        }
    }
}

private struct WindowSnapAssistCard: View {
    let candidate: WindowSnapAssistCandidate
    let thumbnail: NSImage?
    let choose: () -> Void
    @State private var hovered = false

    var body: some View {
        Button(action: choose) {
            VStack(alignment: .leading, spacing: 6) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.black.opacity(0.25))
                    if let thumbnail {
                        Image(nsImage: thumbnail).resizable().interpolation(.medium).scaledToFit().padding(4)
                    } else if let icon = NSRunningApplication(processIdentifier: candidate.pid)?.icon {
                        Image(nsImage: icon).resizable().frame(width: 40, height: 40)
                    }
                }
                .aspectRatio(16 / 10, contentMode: .fit)
                HStack(spacing: 5) {
                    if let icon = NSRunningApplication(processIdentifier: candidate.pid)?.icon {
                        Image(nsImage: icon).resizable().frame(width: 14, height: 14)
                    }
                    Text(candidate.title).font(.system(size: 11, weight: .medium)).lineLimit(1)
                }
            }
            .padding(6)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.white.opacity(hovered ? 0.16 : 0.0)))
            .scaleEffect(hovered ? 1.03 : 1)
            .animation(.easeOut(duration: 0.12), value: hovered)
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
        .help(candidate.appName)
    }
}

/// Covers a window's new place while it is moved and resized, so it seems to
/// land there in one step, then fades to show it.
final class WindowSnapLandingCover {
    static let shared = WindowSnapLandingCover()
    private var panel: NSPanel?
    private var generation = 0

    private init() {}

    /// `frame` is the place, in AppKit points.
    func cover(_ frame: CGRect, for duration: TimeInterval = 0.28) {
        generation += 1
        let trip = generation
        let panel = self.panel ?? makePanel()
        self.panel = panel
        panel.setFrame(frame, display: true)
        panel.alphaValue = 1
        panel.orderFrontRegardless()
        DispatchQueue.main.asyncAfter(deadline: .now() + duration) { [weak self] in
            guard let self, trip == self.generation else { return }
            NSAnimationContext.runAnimationGroup({ $0.duration = 0.16; panel.animator().alphaValue = 0 },
                                                 completionHandler: { [weak self] in
                guard let self, trip == self.generation else { return }
                panel.orderOut(nil)
            })
        }
    }

    private func makePanel() -> NSPanel {
        let panel = OverlayPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel],
                                 backing: .buffered, defer: false)
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]
        panel.animationBehavior = .none
        let effect = NSVisualEffectView()
        effect.material = .hudWindow
        effect.blendingMode = .behindWindow
        effect.state = .active
        effect.wantsLayer = true
        effect.layer?.cornerRadius = 12
        effect.layer?.masksToBounds = true
        panel.contentView = effect
        return panel
    }
}
