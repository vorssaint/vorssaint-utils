// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import SwiftUI

/// Only the transition owns animation state. No timer or display link survives
/// the reveal, and a reversed transition cannot enable a departing button.
final class NotchQuickAccessMotion: ObservableObject {
    @Published private(set) var progress: CGFloat = 0
    @Published private(set) var interactive = false
    @Published private(set) var configuration = NotchQuickAccessConfiguration(side: .left, actions: [.explore])
    @Published private(set) var placements: [NotchQuickAccessPlacement] = []
    private var bodyFrame = CGRect.zero
    private var visible = false
    private var generation = 0

    func configure(_ configuration: NotchQuickAccessConfiguration, body: CGRect, headerTop: CGFloat, animated: Bool) {
        let values = NotchQuickAccessLayout.placements(configuration, body: body, headerTop: headerTop)
        guard self.configuration != configuration || placements != values else { return }
        let animation: Animation? = animated && visible
            ? .spring(duration: NotchMotion.duration(from: bodyFrame.size, to: body.size), bounce: 0) : nil
        bodyFrame = body
        withAnimation(animation) {
            self.configuration = configuration
            placements = values
        }
    }

    var hoverRects: [CGRect] {
        NotchQuickAccessSide.allCases.compactMap { side in
            let values = placements.filter { $0.side == side }
            guard let first = values.first else { return nil }
            return NotchQuickAccessLayout.hoverRect(count: values.count, edge: first.edge, top: first.top, side: side)
        }
    }

    func setVisible(_ visible: Bool, animated: Bool, delay: TimeInterval = 0) {
        guard self.visible != visible else { return }
        self.visible = visible
        generation += 1
        let token = generation
        interactive = false
        let animation: Animation? = animated
            ? (visible ? .spring(duration: 0.38, bounce: 0.12).delay(delay) : .easeIn(duration: NotchQuickAccessLayout.withdrawalDuration))
            : nil
        withAnimation(animation, completionCriteria: .logicallyComplete) {
            progress = visible ? 1 : 0
        } completion: { [weak self] in
            guard let self, self.generation == token else { return }
            self.interactive = visible
        }
    }

    func contains(_ point: CGPoint) -> Bool {
        interactive && placements.contains { value in
            let center = value.center(progress: 1)
            return hypot(point.x - center.x, point.y - center.y) <= NotchQuickAccessLayout.diameter / 2
        }
    }
}

struct NotchQuickAccessView: View {
    @ObservedObject var service: NotchService
    @ObservedObject var motion: NotchQuickAccessMotion
    @ObservedObject private var l10n = L10n.shared
    @ObservedObject private var awake = KeepAwakeManager.shared
    @ObservedObject private var microphone = MicMuteService.shared
    @ObservedObject private var recorder = ScreenRecorderService.shared
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        ZStack(alignment: .topLeading) {
            ForEach(motion.placements) { placement in
                NotchQuickAccessDrop(progress: motion.progress, index: placement.index, edge: placement.edge,
                                     top: placement.top, side: placement.side)
                    .fill(.black)
                    .allowsHitTesting(false)
                bubble(placement.button)
                    .scaleEffect(0.4 + 0.6 * motion.progress)
                    .opacity(Double(motion.progress))
                    .position(placement.center(progress: motion.progress))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .environment(\.colorScheme, .dark)
        .environment(\.notchPresentation, true)
        .foregroundStyle(.white)
        .tint(.white)
        .allowsHitTesting(motion.interactive)
        .accessibilityHidden(!motion.interactive)
    }

    private func bubble(_ button: NotchQuickButton) -> some View {
        let action = button.action ?? .explore
        let isBack = action == .explore && service.showingSections
        let selected: Bool = {
            if action == .explore { return service.showingSections }
            if action == .pin { return service.pinned }
            if action == .control(.keepAwake) { return awake.isActive }
            if action == .control(.microphone) { return microphone.isMuted }
            if action == .control(.recording) { return recorder.isRecording }
            if case .module(let module) = action {
                return !service.showingSections && !service.showingAppPanel && service.selected == module
            }
            return false
        }()
        var actionTitle = action.title(l10n)
        var symbol = action.symbol
        switch action {
        case .explore where isBack: symbol = "arrow.uturn.backward"
        case .pin:
            actionTitle = service.pinned ? FeatureStrings.notch(l10n.language).unpin : FeatureStrings.notch(l10n.language).pin
            if service.pinned { symbol = "pin.fill" }
        case .control(.microphone):
            actionTitle = microphone.isMuted ? l10n.s.micUnmuteName : l10n.s.micMuteName
            if microphone.isMuted { symbol = "mic.slash.fill" }
        case .control(.keepAwake) where awake.isActive: symbol = "cup.and.saucer.fill"
        case .control(.recording) where recorder.isRecording: symbol = "stop.circle.fill"
        default: break
        }
        let title = isBack ? l10n.s.obBack : button.label.isEmpty ? actionTitle : button.label
        return Button {
            service.activateQuickAction(action)
        } label: {
            Image(systemName: symbol)
                .font(.system(size: 17, weight: .medium))
                .frame(width: NotchQuickAccessLayout.diameter, height: NotchQuickAccessLayout.diameter)
                .background(.black, in: Circle())
                .overlay {
                    Circle().strokeBorder(.white.opacity(selected || contrast == .increased ? 0.6 : 0.16), lineWidth: 0.75)
                        .allowsHitTesting(false)
                }
                .contentShape(Circle())
        }
        .buttonStyle(NotchButtonStyle(cornerRadius: NotchQuickAccessLayout.diameter / 2))
        .help(title)
        .accessibilityLabel(title)
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityIdentifier("notch.quickAccess.\(button.id.uuidString)")
    }
}

struct NotchQuickAccessDrop: Shape {
    var progress: CGFloat
    let index: Int
    var edge: CGFloat
    var top: CGFloat
    let side: NotchQuickAccessSide
    var animatableData: AnimatablePair<CGFloat, AnimatablePair<CGFloat, CGFloat>> {
        get { AnimatablePair(progress, AnimatablePair(edge, top)) }
        set { progress = newValue.first; edge = newValue.second.first; top = newValue.second.second }
    }

    func path(in rect: CGRect) -> Path {
        let phase = min(1.1, max(0, progress))
        guard phase > 0.001 else { return Path() }
        let anchor = side == .bottom ? rect.height - edge : side == .left ? edge : rect.width - edge
        let center = NotchQuickAccessLayout.center(index: index, progress: phase, edge: anchor, top: top, side: .left)
        let radius = NotchQuickAccessLayout.diameter / 2 * (0.4 + 0.6 * phase)
        var path = Path(ellipseIn: CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2))
        // The narrow connection dissolves before the circle finishes moving.
        // Its other end sits under the notch, so there is no visible seam.
        let neck = radius * max(0, 1 - phase / 0.84)
        if neck > 0, center.x + radius < anchor {
            path.move(to: CGPoint(x: anchor + 2, y: center.y + neck))
            path.addCurve(to: CGPoint(x: center.x + radius * 0.55, y: center.y + neck * 0.75),
                          control1: CGPoint(x: anchor - 7, y: center.y + neck),
                          control2: CGPoint(x: center.x + radius, y: center.y + neck * 0.15))
            path.addLine(to: CGPoint(x: center.x + radius * 0.55, y: center.y - neck * 0.75))
            path.addCurve(to: CGPoint(x: anchor + 2, y: center.y - neck),
                          control1: CGPoint(x: center.x + radius, y: center.y - neck * 0.15),
                          control2: CGPoint(x: anchor - 7, y: center.y - neck))
            path.closeSubpath()
        }
        if side == .bottom { return path.applying(CGAffineTransform(a: 0, b: -1, c: 1, d: 0, tx: 0, ty: rect.height)) }
        if side == .right { return path.applying(CGAffineTransform(a: -1, b: 0, c: 0, d: 1, tx: rect.width, ty: 0)) }
        return path
    }
}

extension NotchQuickAction {
    var symbol: String {
        switch self {
        case .explore: return "square.grid.2x2"
        case .settings: return "gearshape"
        case .pin: return "pin"
        case .module(let module): return module.symbol
        case .control(let item): return item.symbol
        }
    }

    func title(_ l10n: L10n) -> String {
        switch self {
        case .explore: return FeatureStrings.notch(l10n.language).sectionsTitle
        case .settings: return l10n.s.menuSettings
        case .pin: return FeatureStrings.notch(l10n.language).pin
        case .module(let module): return module.title(l10n.language)
        case .control(let item): return item.title(l10n)
        }
    }
}
