// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import QuartzCore

/// One opaque status chip. A new value replaces both its text and fade deadline.
final class ScreenshotPinFeedbackView: NSView {
    private let label = NSTextField(labelWithString: "")
    private var fade: DispatchWorkItem?
    var message: String { label.stringValue }
    var isPresented: Bool { (layer?.opacity ?? 0) > 0 }

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.backgroundColor = CGColor(gray: 0.12, alpha: 1)
        layer?.cornerRadius = 14
        layer?.opacity = 0
        label.textColor = .white
        label.font = .monospacedDigitSystemFont(ofSize: 12, weight: .semibold)
        label.alignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)
        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: centerXAnchor),
            label.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])
        setAccessibilityElement(true)
        setAccessibilityRole(.staticText)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    func show(_ text: String) {
        fade?.cancel()
        layer?.removeAllAnimations()
        label.stringValue = text
        setAccessibilityValue(text)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer?.opacity = 1
        CATransaction.commit()
        let work = DispatchWorkItem { [weak self] in
            guard let self, let layer = self.layer else { return }
            let animation = CABasicAnimation(keyPath: "opacity")
            animation.fromValue = 1
            animation.toValue = 0
            animation.duration = 0.2
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            layer.opacity = 0
            layer.add(animation, forKey: "fade")
            CATransaction.commit()
        }
        fade = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1, execute: work)
    }

    func dismiss() {
        fade?.cancel()
        fade = nil
        layer?.removeAllAnimations()
        layer?.opacity = 0
    }

    deinit { fade?.cancel() }
}
