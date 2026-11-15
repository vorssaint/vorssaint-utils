// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import SwiftUI

/// AppKit-backed treemap. SwiftUI Canvas rebuilt nested boxes on every
/// selection change; this caches a filled bitmap and only overlays selection.
/// Hover shows a fast tooltip so users can identify blocks without clicking.
struct DiskAnalyzerTreemapView: NSViewRepresentable {
    let root: DiskAnalyzerSupport.Node?
    let selectedPath: String?
    let onSelect: (String) -> Void
    let onActivate: (String) -> Void

    func makeNSView(context: Context) -> DiskAnalyzerTreemapNSView {
        let view = DiskAnalyzerTreemapNSView()
        view.onSelect = onSelect
        view.onActivate = onActivate
        return view
    }

    func updateNSView(_ view: DiskAnalyzerTreemapNSView, context: Context) {
        view.onSelect = onSelect
        view.onActivate = onActivate
        view.update(root: root, selectedPath: selectedPath)
    }
}

final class DiskAnalyzerTreemapNSView: NSView {
    var onSelect: ((String) -> Void)?
    var onActivate: ((String) -> Void)?

    private var root: DiskAnalyzerSupport.Node?
    private var selectedPath: String?
    private var hoveredPath: String?
    private var cells: [DiskAnalyzerSupport.TreemapCell] = []
    private var layoutSize: CGSize = .zero
    private var baseImage: CGImage?
    private var lastClickTime: TimeInterval = 0
    private var lastClickPath: String?
    private var trackingArea: NSTrackingArea?
    private let hoverTip = DiskAnalyzerHoverTipView()

    override var isFlipped: Bool { true }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        commonInit()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        commonInit()
    }

    private func commonInit() {
        hoverTip.isHidden = true
        addSubview(hoverTip)
    }

    func update(root: DiskAnalyzerSupport.Node?, selectedPath: String?) {
        let rootChanged = self.root?.path != root?.path
            || self.root?.size != root?.size
            || self.root?.children.count != root?.children.count
        let selectionChanged = self.selectedPath != selectedPath
        self.root = root
        self.selectedPath = selectedPath

        let size = CGSize(width: floor(bounds.width), height: floor(bounds.height))
        let sizeChanged = abs(layoutSize.width - size.width) > 0.5
            || abs(layoutSize.height - size.height) > 0.5

        if rootChanged || sizeChanged || baseImage == nil {
            rebuild(size: size)
        } else if selectionChanged {
            needsDisplay = true
        }
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea {
            removeTrackingArea(trackingArea)
        }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.activeInKeyWindow, .mouseMoved, .mouseEnteredAndExited, .inVisibleRect],
            owner: self,
            userInfo: nil)
        addTrackingArea(area)
        trackingArea = area
    }

    override func setFrameSize(_ newSize: NSSize) {
        let next = CGSize(width: floor(newSize.width), height: floor(newSize.height))
        let sizeChanged = abs(next.width - layoutSize.width) > 0.5
            || abs(next.height - layoutSize.height) > 0.5
        super.setFrameSize(newSize)
        if sizeChanged, bounds.width > 1, bounds.height > 1 {
            rebuild(size: next)
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        context.setFillColor(NSColor.labelColor.withAlphaComponent(0.04).cgColor)
        context.fill(bounds)

        if let baseImage {
            context.interpolationQuality = .none
            context.draw(baseImage, in: CGRect(origin: .zero, size: layoutSize))
        }

        if let hoveredPath,
           hoveredPath != selectedPath,
           let cell = cells.first(where: { $0.path == hoveredPath }) {
            context.setStrokeColor(NSColor.white.withAlphaComponent(0.7).cgColor)
            context.setLineWidth(1.5)
            context.stroke(cell.rect.insetBy(dx: 0.75, dy: 0.75))
        }

        if let selectedPath,
           let cell = cells.first(where: { $0.path == selectedPath }) {
            context.setStrokeColor(NSColor.white.cgColor)
            context.setLineWidth(2)
            context.stroke(cell.rect.insetBy(dx: 1, dy: 1))
        }
    }

    override func mouseMoved(with event: NSEvent) {
        updateHover(at: convert(event.locationInWindow, from: nil))
    }

    override func mouseEntered(with event: NSEvent) {
        updateHover(at: convert(event.locationInWindow, from: nil))
    }

    override func mouseExited(with event: NSEvent) {
        clearHover()
    }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        guard let cell = cells.first(where: { $0.rect.contains(point) }) else { return }
        let now = ProcessInfo.processInfo.systemUptime
        let isDouble = lastClickPath == cell.path && (now - lastClickTime) < NSEvent.doubleClickInterval
        lastClickTime = now
        lastClickPath = cell.path
        onSelect?(cell.path)
        if isDouble {
            onActivate?(cell.path)
        }
    }

    private func updateHover(at point: CGPoint) {
        let cell = cells.first { $0.rect.contains(point) }
        let path = cell?.path
        if path != hoveredPath {
            hoveredPath = path
            needsDisplay = true
            guard let cell else {
                hoverTip.isHidden = true
                return
            }
            let parentSize = max(root?.size ?? cell.size, 1)
            let fraction = Double(cell.size) / Double(parentSize)
            let strings = FeatureStrings.diskAnalyzer(L10n.shared.language)
            let percent = String(format: "%.1f%%", fraction * 100)
            hoverTip.configure(
                title: cell.name,
                sizeLine: "\(strings.sizeLabel): \(DiskAnalyzerSupport.formatBytes(cell.size))",
                percentLine: String(format: strings.percentOfParentFormat, percent),
                pathLine: prettyPath(cell.path)
            )
            hoverTip.isHidden = false
        }
        guard !hoverTip.isHidden else { return }
        positionHoverTip(near: point)
    }

    private func clearHover() {
        if hoveredPath != nil {
            hoveredPath = nil
            needsDisplay = true
        }
        hoverTip.isHidden = true
    }

    private func positionHoverTip(near point: CGPoint) {
        hoverTip.layoutSubtreeIfNeeded()
        let tipSize = hoverTip.fittingSize
        hoverTip.frame.size = tipSize
        let margin: CGFloat = 14
        var origin = CGPoint(x: point.x + margin, y: point.y + margin)
        if origin.x + tipSize.width > bounds.width - 4 {
            origin.x = point.x - tipSize.width - margin
        }
        if origin.y + tipSize.height > bounds.height - 4 {
            origin.y = point.y - tipSize.height - margin
        }
        origin.x = min(max(4, origin.x), max(4, bounds.width - tipSize.width - 4))
        origin.y = min(max(4, origin.y), max(4, bounds.height - tipSize.height - 4))
        hoverTip.frame.origin = origin
    }

    private func prettyPath(_ path: String) -> String {
        if path.contains(".__vorssaint_") { return "" }
        return path.replacingOccurrences(of: NSHomeDirectory(), with: "~")
    }

    private func rebuild(size: CGSize) {
        layoutSize = size
        let rect = CGRect(origin: .zero, size: size)
        if let root, size.width > 1, size.height > 1 {
            cells = DiskAnalyzerSupport.layoutTreemap(root: root, in: rect)
        } else {
            cells = []
        }
        baseImage = renderBaseImage()
        clearHover()
        needsDisplay = true
    }

    private func renderBaseImage() -> CGImage? {
        guard layoutSize.width > 1, layoutSize.height > 1, !cells.isEmpty else { return nil }
        let scale = max(window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2, 1)
        let pixelWidth = Int((layoutSize.width * scale).rounded())
        let pixelHeight = Int((layoutSize.height * scale).rounded())
        guard pixelWidth > 0, pixelHeight > 0 else { return nil }

        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(
            data: nil,
            width: pixelWidth,
            height: pixelHeight,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }

        context.translateBy(x: 0, y: CGFloat(pixelHeight))
        context.scaleBy(x: scale, y: -scale)

        for cell in cells {
            context.setFillColor(DiskAnalyzerSupport.color(for: cell.colorIndex, depth: 0).cgColor)
            context.fill(cell.rect)
            context.setStrokeColor(NSColor.black.withAlphaComponent(0.22).cgColor)
            context.setLineWidth(0.5)
            context.stroke(cell.rect)
        }

        NSGraphicsContext.saveGraphicsState()
        let nsContext = NSGraphicsContext(cgContext: context, flipped: true)
        NSGraphicsContext.current = nsContext
        for cell in cells where cell.rect.width > 56 && cell.rect.height > 22 {
            let attrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 10, weight: .semibold),
                .foregroundColor: NSColor.white
            ]
            let text = NSAttributedString(string: cell.name, attributes: attrs)
            let textSize = text.size()
            guard textSize.width + 8 < cell.rect.width else { continue }
            text.draw(at: CGPoint(x: cell.rect.midX - textSize.width / 2,
                                  y: cell.rect.minY + 6))
        }
        NSGraphicsContext.restoreGraphicsState()

        return context.makeImage()
    }
}

/// Compact hover card for treemap blocks.
private final class DiskAnalyzerHoverTipView: NSView {
    private let titleLabel = NSTextField(labelWithString: "")
    private let sizeLabel = NSTextField(labelWithString: "")
    private let percentLabel = NSTextField(labelWithString: "")
    private let pathLabel = NSTextField(labelWithString: "")
    private let stack = NSStackView()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.cornerRadius = 8
        layer?.masksToBounds = true
        layer?.backgroundColor = NSColor.controlBackgroundColor.withAlphaComponent(0.96).cgColor
        layer?.borderWidth = 1
        layer?.borderColor = NSColor.separatorColor.cgColor

        titleLabel.font = .systemFont(ofSize: 12, weight: .semibold)
        titleLabel.lineBreakMode = .byTruncatingMiddle
        sizeLabel.font = .systemFont(ofSize: 11)
        sizeLabel.textColor = .secondaryLabelColor
        percentLabel.font = .systemFont(ofSize: 11)
        percentLabel.textColor = .secondaryLabelColor
        pathLabel.font = .systemFont(ofSize: 10)
        pathLabel.textColor = .tertiaryLabelColor
        pathLabel.lineBreakMode = .byTruncatingMiddle
        pathLabel.maximumNumberOfLines = 2

        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 2
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.addArrangedSubview(titleLabel)
        stack.addArrangedSubview(sizeLabel)
        stack.addArrangedSubview(percentLabel)
        stack.addArrangedSubview(pathLabel)
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: topAnchor, constant: 8),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -8),
            widthAnchor.constraint(lessThanOrEqualToConstant: 280),
            widthAnchor.constraint(greaterThanOrEqualToConstant: 160)
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(title: String, sizeLine: String, percentLine: String, pathLine: String) {
        titleLabel.stringValue = title
        sizeLabel.stringValue = sizeLine
        percentLabel.stringValue = percentLine
        pathLabel.stringValue = pathLine
        pathLabel.isHidden = pathLine.isEmpty
        invalidateIntrinsicContentSize()
    }

    override var fittingSize: NSSize {
        layoutSubtreeIfNeeded()
        let stackSize = stack.fittingSize
        return NSSize(width: min(280, max(160, stackSize.width + 20)),
                      height: stackSize.height + 16)
    }
}
