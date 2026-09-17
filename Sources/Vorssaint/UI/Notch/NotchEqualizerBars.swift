// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import SwiftUI

/// Decorative motion belongs to the compositor, without a display-rate
/// SwiftUI timeline or repeated Canvas drawing in the app process.
struct NotchEqualizerBars: View {
    var isPlaying = true
    var bars = 4
    var barWidth: CGFloat = 2.5
    var height: CGFloat = 14
    var tint: Color = .white
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let count = max(1, bars)
        NotchEqualizerBridge(animates: isPlaying && !reduceMotion, bars: count,
                             barWidth: barWidth, height: height, tint: NSColor(tint))
            .frame(width: CGFloat(count) * barWidth + CGFloat(count - 1) * barWidth * 0.85,
                   height: height)
            .accessibilityHidden(true)
            .allowsHitTesting(false)
    }
}

private struct NotchEqualizerBridge: NSViewRepresentable {
    let animates: Bool
    let bars: Int
    let barWidth: CGFloat
    let height: CGFloat
    let tint: NSColor

    func makeNSView(context: Context) -> NotchEqualizerView { NotchEqualizerView() }

    func updateNSView(_ view: NotchEqualizerView, context: Context) {
        view.configure(animates: animates, bars: bars, barWidth: barWidth, height: height, tint: tint)
    }

    static func dismantleNSView(_ view: NotchEqualizerView, coordinator: ()) { view.stop() }
}

final class NotchEqualizerView: NSView {
    private var bars: [CALayer] = []
    private var barWidth: CGFloat = 0
    private var height: CGFloat = 0
    private var animates = false
    private var visibilityObserver: NSObjectProtocol?
    private static let animationKey = "notch.equalizer"

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        setAccessibilityElement(false)
    }

    required init?(coder: NSCoder) { nil }

    deinit {
        if let visibilityObserver { NotificationCenter.default.removeObserver(visibilityObserver) }
    }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    func configure(animates: Bool, bars count: Int, barWidth: CGFloat, height: CGFloat, tint: NSColor) {
        let count = max(1, count)
        let geometryChanged = bars.count != count || self.barWidth != barWidth || self.height != height
        self.animates = animates
        self.barWidth = barWidth
        self.height = height
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        if bars.count != count {
            bars.forEach { $0.removeFromSuperlayer() }
            bars = (0..<count).map { _ in
                let bar = CALayer()
                layer?.addSublayer(bar)
                return bar
            }
        }
        for bar in bars {
            bar.backgroundColor = tint.cgColor
            if geometryChanged { bar.removeAnimation(forKey: Self.animationKey) }
        }
        CATransaction.commit()
        updateBars()
    }

    func stop() {
        animates = false
        updateBars()
        if let visibilityObserver { NotificationCenter.default.removeObserver(visibilityObserver) }
        visibilityObserver = nil
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if let visibilityObserver { NotificationCenter.default.removeObserver(visibilityObserver) }
        visibilityObserver = window.map { window in
            NotificationCenter.default.addObserver(forName: NSWindow.didChangeOcclusionStateNotification,
                                                   object: window, queue: .main) { [weak self] _ in
                self?.updateBars()
            }
        }
        updateBars()
    }

    override func viewDidHide() { super.viewDidHide(); updateBars() }
    override func viewDidUnhide() { super.viewDidUnhide(); updateBars() }
    override func layout() { super.layout(); updateBars() }

    private func updateBars() {
        let moving = animates && !isHiddenOrHasHiddenAncestor
            && window?.isVisible == true && window?.occlusionState.contains(.visible) == true
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }
        let center = Double(bars.count - 1) / 2
        for (index, bar) in bars.enumerated() {
            let distance = abs(Double(index) - center) / max(1, center)
            let envelope = pow(1 - distance, 1.5)
            let low = max(barWidth, height * (0.12 + envelope * 0.25))
            let high = max(barWidth, height * (0.12 + envelope * 0.88))
            bar.bounds = CGRect(x: 0, y: 0, width: barWidth, height: moving ? low : barWidth)
            bar.position = CGPoint(x: CGFloat(index) * barWidth * 1.85 + barWidth / 2, y: bounds.midY)
            bar.cornerRadius = barWidth / 2
            guard moving, high > low else {
                bar.removeAnimation(forKey: Self.animationKey)
                continue
            }
            // Metadata, tint and layout updates must not restart the motion.
            guard bar.animation(forKey: Self.animationKey) == nil else { continue }
            let animation = CABasicAnimation(keyPath: "bounds.size.height")
            animation.fromValue = low
            animation.toValue = high
            animation.duration = .pi / (5.2 + Double(index) * 0.61)
            animation.autoreverses = true
            animation.repeatCount = .infinity
            animation.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            animation.beginTime = bar.convertTime(CACurrentMediaTime(), from: nil)
            animation.timeOffset = Double(index) * 0.17
            bar.add(animation, forKey: Self.animationKey)
        }
    }
}
