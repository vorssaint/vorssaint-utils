// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import QuartzCore

@MainActor
final class DictationHUD {
    // Listening is intentionally compact: the live state needs only the
    // recording indicator, waveform and title, leaving the target app visible.
    private let size = CGSize(width: 210, height: 44)
    private var panel: NSPanel?
    private var content: ContentView?

    func show(state: DictationState,
              level: Float,
              strings: DictationFeatureStrings,
              sessionDetail: String? = nil,
              listeningHint: String? = nil,
              opensSettings: Bool = false,
              onOpenSettings: (() -> Void)? = nil) {
        let content = content ?? ContentView(frame: CGRect(origin: .zero, size: size))
        content.update(state: state,
                       level: level,
                       strings: strings,
                       sessionDetail: sessionDetail,
                       listeningHint: listeningHint,
                       opensSettings: opensSettings,
                       onOpenSettings: onOpenSettings)
        self.content = content
        if panel == nil {
            guard let screen = NSScreen.main ?? NSScreen.screens.first else { return }
            let panel = NSPanel(contentRect: CGRect(origin: .zero, size: size),
                                styleMask: [.borderless, .nonactivatingPanel],
                                backing: .buffered,
                                defer: false)
            panel.contentView = content
            panel.isOpaque = false
            panel.backgroundColor = .clear
            panel.hasShadow = true
            panel.level = .statusBar
            panel.isReleasedWhenClosed = false
            panel.hidesOnDeactivate = false
            panel.becomesKeyOnlyIfNeeded = true
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary,
                                        .stationary, .ignoresCycle]
            let frame = screen.visibleFrame
            panel.setFrameOrigin(CGPoint(x: (frame.midX - size.width / 2).rounded(),
                                         y: (frame.minY + 18).rounded()))
            panel.alphaValue = 0
            panel.orderFrontRegardless()
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.15
                panel.animator().alphaValue = 1
            }
            self.panel = panel
        }
    }

    func updateLevel(_ level: Float) {
        content?.meter.level = level
    }

    func hide() {
        guard let panel else { return }
        self.panel = nil
        content = nil
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.14
            panel.animator().alphaValue = 0
        }, completionHandler: { panel.orderOut(nil) })
    }

    private final class ContentView: NSView {
        let meter = MeterView(frame: CGRect(x: 52, y: 10, width: 40, height: 24))
        private let icon = NSImageView(frame: CGRect(x: 16, y: 12, width: 20, height: 20))
        private let title = NSTextField(labelWithString: "")
        private let detail = NSTextField(labelWithString: "")
        private let progress = NSProgressIndicator(frame: CGRect(x: 18, y: 17, width: 20, height: 20))
        private let settingsButton = NSButton(title: "", target: nil, action: nil)
        private var onOpenSettings: (() -> Void)?

        override init(frame frameRect: NSRect) {
            super.init(frame: frameRect)
            wantsLayer = true
            title.font = .systemFont(ofSize: 13, weight: .semibold)
            title.textColor = .white
            title.lineBreakMode = .byTruncatingTail
            detail.font = .systemFont(ofSize: 10.5)
            detail.textColor = .white.withAlphaComponent(0.68)
            detail.lineBreakMode = .byTruncatingTail
            progress.style = .spinning
            progress.controlSize = .small
            settingsButton.bezelStyle = .rounded
            settingsButton.controlSize = .small
            settingsButton.target = self
            settingsButton.action = #selector(openSettings)
            addSubview(meter)
            addSubview(icon)
            addSubview(progress)
            addSubview(title)
            addSubview(detail)
            addSubview(settingsButton)
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) { nil }

        override func layout() {
            super.layout()
            let buttonWidth = settingsButton.isHidden ? 0 : min(150, settingsButton.intrinsicContentSize.width + 12)
            settingsButton.frame = CGRect(x: bounds.width - buttonWidth - 12,
                                          y: 8, width: buttonWidth, height: 28)
            let textX: CGFloat = 98
            let textWidth = bounds.width - textX - 14 - (buttonWidth > 0 ? buttonWidth + 8 : 0)
            title.frame = CGRect(x: textX, y: 13, width: textWidth, height: 18)
            detail.frame = CGRect(x: textX, y: 5, width: textWidth, height: 15)
        }

        func update(state: DictationState,
                    level: Float,
                    strings: DictationFeatureStrings,
                    sessionDetail: String?,
                    listeningHint: String?,
                    opensSettings: Bool,
                    onOpenSettings: (() -> Void)?) {
            self.onOpenSettings = onOpenSettings
            settingsButton.title = strings.openSettings
            settingsButton.isHidden = !opensSettings
            meter.isHidden = state != .listening
            detail.isHidden = state == .listening
            meter.level = level
            progress.isHidden = state != .processing
            if state == .processing { progress.startAnimation(nil) } else { progress.stopAnimation(nil) }
            // Listening shows both the recording indicator and the live meter;
            // only processing replaces the icon with its spinner.
            icon.isHidden = state == .processing
            switch state {
            case .idle:
                title.stringValue = ""
                detail.stringValue = ""
            case .listening:
                title.stringValue = strings.listening
                detail.stringValue = ""
            case .processing:
                title.stringValue = strings.processing
                detail.stringValue = strings.cancelHint
            case .failure(let failure):
                title.stringValue = strings.failureMessage(failure)
                detail.stringValue = ""
                icon.image = NSImage(systemSymbolName: "exclamationmark.triangle.fill",
                                     accessibilityDescription: nil)
                icon.contentTintColor = .systemOrange
            }
            if state == .listening {
                icon.image = NSImage(systemSymbolName: "record.circle.fill",
                                     accessibilityDescription: nil)
                icon.contentTintColor = .systemRed
            }
            if let sessionDetail, !sessionDetail.isEmpty {
                detail.stringValue = detail.stringValue.isEmpty
                    ? sessionDetail : "\(detail.stringValue) · \(sessionDetail)"
            }
            setAccessibilityLabel([title.stringValue, detail.stringValue]
                .filter { !$0.isEmpty }.joined(separator: ". "))
            needsLayout = true
        }

        override func draw(_ dirtyRect: NSRect) {
            let body = bounds.insetBy(dx: 0.5, dy: 0.5)
            let path = NSBezierPath(roundedRect: body, xRadius: body.height / 2, yRadius: body.height / 2)
            NSColor(calibratedWhite: 0.09, alpha: 0.95).setFill()
            path.fill()
            NSColor.white.withAlphaComponent(0.16).setStroke()
            path.lineWidth = 1
            path.stroke()
        }

        @objc private func openSettings() { onOpenSettings?() }
    }

    fileprivate final class MeterView: NSView {
        var level: Float = 0 { didSet { needsDisplay = true } }

        override func draw(_ dirtyRect: NSRect) {
            let heights: [CGFloat] = [0.45, 0.75, 1, 0.7, 0.4]
            // Apply visual gain only. The recorded samples are untouched; a
            // quiet microphone should still produce an unmistakable meter.
            let active = CGFloat(max(0.10, min(1, pow(max(0, level), 0.55))))
            for (index, weight) in heights.enumerated() {
                let height = max(3, bounds.height * weight * active)
                let rect = CGRect(x: CGFloat(index) * 8,
                                  y: (bounds.height - height) / 2,
                                  width: 4, height: height)
                NSColor.systemRed.withAlphaComponent(0.75 + CGFloat(index % 2) * 0.15).setFill()
                NSBezierPath(roundedRect: rect, xRadius: 2, yRadius: 2).fill()
            }
        }
    }
}
