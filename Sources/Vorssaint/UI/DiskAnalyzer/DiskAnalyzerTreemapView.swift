// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import SwiftUI

/// AppKit treemap drawn in view coordinates. Click drills into folders;
/// right-click offers Reveal / Trash.
struct DiskAnalyzerTreemapView: NSViewRepresentable {
    let root: DiskAnalyzerSupport.Node?
    let selectedPath: String?
    let nestingDepth: Int
    let onSelect: (String) -> Void
    let onReveal: (String) -> Void
    let onTrash: (String) -> Void

    func makeNSView(context: Context) -> DiskAnalyzerTreemapNSView {
        let view = DiskAnalyzerTreemapNSView()
        view.onSelect = onSelect
        view.onReveal = onReveal
        view.onTrash = onTrash
        return view
    }

    func updateNSView(_ view: DiskAnalyzerTreemapNSView, context: Context) {
        view.onSelect = onSelect
        view.onReveal = onReveal
        view.onTrash = onTrash
        view.update(root: root, selectedPath: selectedPath, nestingDepth: nestingDepth)
    }
}

final class DiskAnalyzerTreemapNSView: NSView {
    var onSelect: ((String) -> Void)?
    var onReveal: ((String) -> Void)?
    var onTrash: ((String) -> Void)?

    private var root: DiskAnalyzerSupport.Node?
    private var selectedPath: String?
    private var nestingDepth = DiskAnalyzerSupport.defaultTreemapNestingDepth
    private var hoveredPath: String?
    private var cells: [DiskAnalyzerSupport.TreemapCell] = []
    private var layoutSize: CGSize = .zero
    private var trackingArea: NSTrackingArea?
    private let hoverTip = DiskAnalyzerHoverTipView()

    override var isFlipped: Bool { true }
    override var isOpaque: Bool { false }

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

    func update(root: DiskAnalyzerSupport.Node?, selectedPath: String?, nestingDepth: Int) {
        let depth = min(4, max(1, nestingDepth))
        let rootChanged = self.root?.path != root?.path
            || self.root?.size != root?.size
            || self.root?.children.map(\.path) != root?.children.map(\.path)
            || self.root?.children.map(\.size) != root?.children.map(\.size)
            || self.nestingDepth != depth
        let selectionChanged = self.selectedPath != selectedPath
        self.root = root
        self.selectedPath = selectedPath
        self.nestingDepth = depth

        let size = CGSize(width: floor(bounds.width), height: floor(bounds.height))
        let sizeChanged = abs(layoutSize.width - size.width) > 0.5
            || abs(layoutSize.height - size.height) > 0.5

        if rootChanged || sizeChanged || cells.isEmpty {
            rebuild(size: size)
        } else if selectionChanged {
            needsDisplay = true
        }
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea { removeTrackingArea(trackingArea) }
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
        NSColor.labelColor.withAlphaComponent(0.04).setFill()
        bounds.fill()

        for cell in cells {
            let fill = DiskAnalyzerSupport.color(for: cell.colorIndex, depth: cell.depth)
            fill.setFill()
            cell.rect.fill()
            NSColor.black.withAlphaComponent(0.22).setStroke()
            let border = NSBezierPath(rect: cell.rect)
            border.lineWidth = 0.5
            border.stroke()
        }

        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 10, weight: .semibold),
            .foregroundColor: NSColor.white
        ]
        for cell in cells where cell.rect.width > 54 && cell.rect.height > 18 {
            if cell.depth > 0, cell.rect.height < 28 { continue }
            let text = NSAttributedString(string: cell.name, attributes: attrs)
            let textSize = text.size()
            guard textSize.width + 8 < cell.rect.width else { continue }
            text.draw(at: CGPoint(x: cell.rect.midX - textSize.width / 2,
                                  y: cell.rect.minY + 3))
        }

        if let hoveredPath,
           hoveredPath != selectedPath,
           let cell = cell(for: hoveredPath) {
            NSColor.white.withAlphaComponent(0.75).setStroke()
            let path = NSBezierPath(rect: cell.rect.insetBy(dx: 0.75, dy: 0.75))
            path.lineWidth = 1.5
            path.stroke()
        }

        if let selectedPath, let cell = cell(for: selectedPath) {
            NSColor.white.setStroke()
            let path = NSBezierPath(rect: cell.rect.insetBy(dx: 1, dy: 1))
            path.lineWidth = 2
            path.stroke()
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
        guard let cell = deepestCell(at: point) else { return }
        onSelect?(cell.path)
    }

    override func rightMouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        guard let cell = deepestCell(at: point), !cell.isAggregate else { return }
        onSelect?(cell.path)

        let strings = FeatureStrings.diskAnalyzer(L10n.shared.language)
        let menu = NSMenu()
        let reveal = menu.addItem(
            withTitle: strings.revealInFinder,
            action: #selector(contextReveal(_:)),
            keyEquivalent: "")
        reveal.target = self
        reveal.representedObject = cell.path

        if DiskAnalyzerSupport.canTrash(URL(fileURLWithPath: cell.path, isDirectory: cell.isDirectory)) {
            let trash = menu.addItem(
                withTitle: strings.moveToTrash,
                action: #selector(contextTrash(_:)),
                keyEquivalent: "")
            trash.target = self
            trash.representedObject = cell.path
        }
        NSMenu.popUpContextMenu(menu, with: event, for: self)
    }

    @objc private func contextReveal(_ sender: NSMenuItem) {
        guard let path = sender.representedObject as? String else { return }
        onReveal?(path)
    }

    @objc private func contextTrash(_ sender: NSMenuItem) {
        guard let path = sender.representedObject as? String else { return }
        onTrash?(path)
    }

    private func deepestCell(at point: CGPoint) -> DiskAnalyzerSupport.TreemapCell? {
        cells.reversed().first { $0.rect.contains(point) }
    }

    private func cell(for path: String) -> DiskAnalyzerSupport.TreemapCell? {
        cells.reversed().first { $0.path == path }
    }

    private func updateHover(at point: CGPoint) {
        let cell = deepestCell(at: point)
        let path = cell?.path
        if path != hoveredPath {
            hoveredPath = path
            needsDisplay = true
            guard let cell else {
                hoverTip.isHidden = true
                return
            }
            let parentSize = max(cell.parentSize, 1)
            let fraction = Double(cell.size) / Double(parentSize)
            let strings = FeatureStrings.diskAnalyzer(L10n.shared.language)
            let percent = String(format: "%.1f%%", fraction * 100)
            hoverTip.configure(
                title: cell.name,
                sizeLine: "\(strings.sizeLabel): \(DiskAnalyzerSupport.formatBytes(cell.size))",
                percentLine: String(format: strings.percentOfParentFormat, percent),
                pathLine: ""
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

    private func rebuild(size: CGSize) {
        layoutSize = size
        let rect = CGRect(origin: .zero, size: size)
        if let root, size.width > 1, size.height > 1 {
            cells = DiskAnalyzerSupport.layoutTreemap(root: root, in: rect, maxDepth: nestingDepth)
        } else {
            cells = []
        }
        clearHover()
        needsDisplay = true
    }
}

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
