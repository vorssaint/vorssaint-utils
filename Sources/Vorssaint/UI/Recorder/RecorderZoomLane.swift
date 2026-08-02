// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import SwiftUI

/// The lane where the zooms live: a block for each one, which can be added,
/// picked up, stretched from either end and thrown away.
///
/// One AppKit view rather than a stack of SwiftUI gestures, because eight
/// different things start with a mouse-down in the same thirty points of
/// height: create, select, move, two edge drags, duplicate. A single press
/// decides which of those this drag is and stays with that decision, which is
/// the only way the wrong one never fires. It is also what makes the pointer
/// change shape over an edge, and without that the handles are invisible.
struct RecorderZoomLane: NSViewRepresentable {
    /// Which of the two lanes this is. They behave identically on purpose:
    /// one set of gestures to learn, whatever kind of thing is on the rail.
    enum Kind {
        case zoom
        case text
    }

    @ObservedObject var model: RecorderEditorModel
    let kind: Kind
    let emptyHint: String

    func makeNSView(context: Context) -> ZoomLaneView {
        let view = ZoomLaneView()
        view.model = model
        view.kind = kind
        view.emptyHint = emptyHint
        return view
    }

    func updateNSView(_ nsView: ZoomLaneView, context: Context) {
        nsView.model = model
        nsView.kind = kind
        nsView.emptyHint = emptyHint
        nsView.refresh()
    }

    /// One block on a lane, whatever it happens to be.
    struct Item {
        let id: UUID
        let start: Double
        let end: Double
        let label: String
        let glyph: String
    }

    final class ZoomLaneView: NSView {
        weak var model: RecorderEditorModel?
        var kind: Kind = .zoom
        var emptyHint = ""

        private var items: [Item] { model?.laneItems(kind) ?? [] }
        private var selectedID: UUID? { model?.laneSelection(kind) }

        private enum Mode {
            case idle
            case pressed(id: UUID?, at: CGPoint, edge: RecorderTimeline.Edge?)
            case moving(id: UUID, grabOffset: Double)
            case resizing(id: UUID, edge: RecorderTimeline.Edge)
        }

        private var mode: Mode = .idle
        private var hoverX: CGFloat?
        private var tracking: NSTrackingArea?

        /// Wide enough to grab without looking, never so wide that a short
        /// block loses its body.
        private static let edgeHit: CGFloat = 11
        private static let snapPoints: CGFloat = 8
        private static let moveThreshold: CGFloat = 4
        private static let resizeThreshold: CGFloat = 3

        override var isFlipped: Bool { true }
        override var acceptsFirstResponder: Bool { true }

        func refresh() {
            needsDisplay = true
        }

        override func updateTrackingAreas() {
            super.updateTrackingAreas()
            if let tracking { removeTrackingArea(tracking) }
            let area = NSTrackingArea(rect: bounds,
                                      options: [.activeInKeyWindow, .mouseEnteredAndExited,
                                                .mouseMoved, .cursorUpdate],
                                      owner: self)
            addTrackingArea(area)
            tracking = area
        }

        // MARK: - Geometry

        private var duration: Double { max(0.001, model?.duration ?? 1) }

        private func x(for time: Double) -> CGFloat {
            CGFloat(min(1, max(0, time / duration))) * bounds.width
        }

        private func time(for x: CGFloat) -> Double {
            guard bounds.width > 0 else { return 0 }
            return Double(min(1, max(0, x / bounds.width))) * duration
        }

        private func rect(for item: Item) -> CGRect {
            let start = x(for: item.start)
            let end = x(for: item.end)
            return CGRect(x: start, y: 2, width: max(6, end - start), height: bounds.height - 4)
        }

        private func segment(at point: CGPoint) -> (segment: Item,
                                                    edge: RecorderTimeline.Edge?)? {
            for segment in items {
                let frame = rect(for: segment)
                let grab = min(Self.edgeHit, frame.width * 0.4)
                guard frame.insetBy(dx: -2, dy: 0).contains(point) else { continue }
                if point.x <= frame.minX + grab { return (segment, .start) }
                if point.x >= frame.maxX - grab { return (segment, .end) }
                return (segment, nil)
            }
            return nil
        }

        /// The nearest thing worth landing on, in screen distance so it feels
        /// the same whatever the recording's length.
        private func snapped(_ time: Double, ignoring id: UUID?) -> Double {
            guard let model else { return time }
            var targets: [Double] = [0, duration, model.sourceTime]
            targets.append(contentsOf: model.pointerTrack.clicks.filter(\.isDown).map(\.time))
            for segment in items where segment.id != id {
                targets.append(segment.start)
                targets.append(segment.end)
            }
            let tolerance = Double(Self.snapPoints / max(1, bounds.width)) * duration
            var best = time
            var bestDistance = tolerance
            for target in targets {
                let distance = abs(target - time)
                if distance < bestDistance {
                    bestDistance = distance
                    best = target
                }
            }
            return best
        }

        // MARK: - Mouse

        override func cursorUpdate(with event: NSEvent) {
            let point = convert(event.locationInWindow, from: nil)
            if let hit = segment(at: point) {
                (hit.edge == nil ? NSCursor.openHand : NSCursor.resizeLeftRight).set()
            } else {
                NSCursor.arrow.set()
            }
        }

        override func mouseMoved(with event: NSEvent) {
            hoverX = convert(event.locationInWindow, from: nil).x
            needsDisplay = true
        }

        override func mouseExited(with event: NSEvent) {
            hoverX = nil
            needsDisplay = true
        }

        override func mouseDown(with event: NSEvent) {
            window?.makeFirstResponder(self)
            let point = convert(event.locationInWindow, from: nil)
            if let hit = segment(at: point) {
                model?.selectLaneItem(kind, id: hit.segment.id)
                mode = .pressed(id: hit.segment.id, at: point, edge: hit.edge)
            } else {
                mode = .pressed(id: nil, at: point, edge: nil)
            }
            needsDisplay = true
        }

        override func mouseDragged(with event: NSEvent) {
            guard let model else { return }
            let point = convert(event.locationInWindow, from: nil)
            switch mode {
            case .idle:
                return
            case .pressed(let id, let origin, let edge):
                let travelled = abs(point.x - origin.x)
                guard let id, let segment = items.first(where: { $0.id == id }) else { return }
                if let edge, travelled >= Self.resizeThreshold {
                    mode = .resizing(id: id, edge: edge)
                } else if edge == nil, travelled >= Self.moveThreshold {
                    NSCursor.closedHand.set()
                    mode = .moving(id: id, grabOffset: time(for: origin.x) - segment.start)
                } else {
                    return
                }
                mouseDragged(with: event)
            case .moving(let id, let offset):
                let wanted = snapped(time(for: point.x) - offset, ignoring: id)
                model.moveLaneItem(kind, id: id, to: wanted)
            case .resizing(let id, let edge):
                let wanted = snapped(time(for: point.x), ignoring: id)
                model.resizeLaneItem(kind, id: id, edge: edge, to: wanted)
            }
            needsDisplay = true
        }

        override func mouseUp(with event: NSEvent) {
            let point = convert(event.locationInWindow, from: nil)
            if case .pressed(let id, _, _) = mode, id == nil {
                if selectedID != nil {
                    // Something is selected: the first click on empty lane is
                    // how you put it down, the way clicking away works
                    // everywhere else. The next one adds.
                    model?.selectLaneItem(kind, id: nil)
                } else {
                    // A click on empty lane is how a block is born, which is
                    // the one thing the empty state has to teach.
                    model?.addLaneItem(kind, at: snapped(time(for: point.x), ignoring: nil))
                }
            }
            if case .moving = mode { NSCursor.openHand.set() }
            mode = .idle
            model?.commitZoomEdit()
            needsDisplay = true
        }

        override func keyDown(with event: NSEvent) {
            switch Int(event.keyCode) {
            case 51, 117: // Delete, forward delete
                model?.removeSelectedLaneItem(kind)
            default:
                super.keyDown(with: event)
            }
        }

        override func menu(for event: NSEvent) -> NSMenu? {
            let point = convert(event.locationInWindow, from: nil)
            guard let hit = segment(at: point) else { return nil }
            model?.selectLaneItem(kind, id: hit.segment.id)
            let menu = NSMenu()
            menu.addItem(NSMenuItem(title: FeatureStrings.recorder(L10n.shared.language).removeZoom,
                                    action: #selector(removeFromMenu),
                                    keyEquivalent: ""))
            menu.items.forEach { $0.target = self }
            return menu
        }

        @objc private func removeFromMenu() {
            model?.removeSelectedLaneItem(kind)
            needsDisplay = true
        }

        // MARK: - Drawing

        override func draw(_ dirtyRect: NSRect) {
            guard let context = NSGraphicsContext.current?.cgContext else { return }
            let radius: CGFloat = 6

            context.setFillColor(CGColor(gray: 1, alpha: 0.04))
            context.addPath(CGPath(roundedRect: bounds, cornerWidth: radius,
                                   cornerHeight: radius, transform: nil))
            context.fillPath()

            let segments = items
            if segments.isEmpty {
                drawEmptyState(context, radius: radius)
                return
            }

            let accent = kind == .zoom
                ? (NSColor.controlAccentColor.usingColorSpace(.sRGB) ?? .systemBlue)
                : NSColor.systemPurple
            for segment in segments {
                let frame = rect(for: segment)
                let path = CGPath(roundedRect: frame, cornerWidth: radius,
                                  cornerHeight: radius, transform: nil)
                context.addPath(path)
                context.setFillColor(accent.withAlphaComponent(0.22).cgColor)
                context.fillPath()

                // The hold reads brighter than the two ramps, so a block shows
                // its own easing without anything having to explain it.
                let ramp = kind == .zoom ? RecorderMotion.zoomRampIn : RecorderTextOverlay.fade
                let rampIn = min(ramp, (segment.end - segment.start) / 2)
                let holdStart = x(for: segment.start + rampIn)
                let holdEnd = x(for: max(segment.start + rampIn, segment.end))
                if holdEnd > holdStart {
                    context.saveGState()
                    context.addPath(path)
                    context.clip()
                    context.setFillColor(accent.withAlphaComponent(0.16).cgColor)
                    context.fill(CGRect(x: holdStart, y: frame.minY,
                                        width: holdEnd - holdStart, height: frame.height))
                    context.restoreGState()
                }

                let selected = selectedID == segment.id
                context.addPath(path)
                context.setStrokeColor(accent.withAlphaComponent(selected ? 1 : 0.65).cgColor)
                context.setLineWidth(selected ? 2 : 1)
                context.strokePath()

                if frame.width > 34 {
                    drawHandle(context, at: frame.minX + 3.5, in: frame, accent: accent)
                    drawHandle(context, at: frame.maxX - 5.5, in: frame, accent: accent)
                }
                drawLabel(segment, in: frame)
            }

            if let hoverX {
                context.setStrokeColor(CGColor(gray: 1, alpha: 0.12))
                context.setLineWidth(1)
                context.move(to: CGPoint(x: hoverX, y: 0))
                context.addLine(to: CGPoint(x: hoverX, y: bounds.height))
                context.strokePath()
            }
        }

        private func drawHandle(_ context: CGContext,
                                at x: CGFloat,
                                in frame: CGRect,
                                accent: NSColor) {
            let bar = CGRect(x: x, y: frame.midY - frame.height * 0.18,
                             width: 2, height: frame.height * 0.36)
            context.setFillColor(accent.withAlphaComponent(0.9).cgColor)
            context.fill(bar)
        }

        private func drawLabel(_ segment: Item, in frame: CGRect) {
            let attributes: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 10, weight: .semibold),
                .foregroundColor: NSColor.white.withAlphaComponent(0.92),
            ]
            let text = frame.width > 56 ? "\(segment.glyph) \(segment.label)" : segment.glyph
            let size = text.size(withAttributes: attributes)
            guard size.width + 10 <= frame.width else { return }
            text.draw(at: CGPoint(x: frame.midX - size.width / 2,
                                  y: frame.midY - size.height / 2),
                      withAttributes: attributes)
        }

        private func drawEmptyState(_ context: CGContext, radius: CGFloat) {
            context.saveGState()
            context.setStrokeColor(CGColor(gray: 1, alpha: 0.22))
            context.setLineWidth(1)
            context.setLineDash(phase: 0, lengths: [5, 4])
            context.addPath(CGPath(roundedRect: bounds.insetBy(dx: 1, dy: 1),
                                   cornerWidth: radius, cornerHeight: radius, transform: nil))
            context.strokePath()
            context.restoreGState()

            let attributes: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 10.5, weight: .medium),
                .foregroundColor: NSColor.white.withAlphaComponent(0.4),
            ]
            let size = emptyHint.size(withAttributes: attributes)
            emptyHint.draw(at: CGPoint(x: bounds.midX - size.width / 2,
                                       y: bounds.midY - size.height / 2),
                           withAttributes: attributes)
        }
    }
}
