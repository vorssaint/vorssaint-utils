// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit

/// What the editor reads off the capture as the pointer moves: the color
/// under it, the live measurement, and the colors and size of the crop
/// selection. An object of its own, so a moving pointer redraws only these
/// readouts and never the whole canvas.
final class ScreenshotEditorInspector: ObservableObject {
    typealias Support = ScreenshotInspectionSupport

    /// The image pixel under the pointer, or nil while it is off the capture.
    @Published var pointer: CGPoint? {
        didSet { refreshPointerReadings() }
    }
    @Published private(set) var pointerColor: Support.RGBA?
    @Published var liveMode: Support.LiveMode? {
        didSet { refreshLiveSpan() }
    }
    @Published private(set) var liveSpan: Support.Span?
    @Published var unit: Support.MeasureUnit {
        didSet { UserDefaults.standard.set(unit.rawValue, forKey: DefaultsKey.screenshotMeasureUnit) }
    }
    /// True while Space is held, when a drag moves the canvas instead of drawing.
    @Published var panning = false

    /// The crop selection's size and colors, read in the background.
    struct SelectionReading: Equatable {
        let size: CGSize
        let average: Support.RGBA?
        let pair: Support.ColorPair?
    }
    @Published private(set) var selection: SelectionReading?

    private(set) var image: CGImage?
    private(set) var scale: CGFloat = 1
    private var line: (key: LineKey, pixels: [Support.RGBA])?
    private var selectionGeneration = 0
    private static let selectionQueue = DispatchQueue(label: "Vorssaint.ScreenshotSelectionReading",
                                                      qos: .userInitiated)

    private struct LineKey: Equatable {
        let image: ObjectIdentifier
        let axis: Support.Axis
        let index: Int
    }

    init() {
        unit = Support.MeasureUnit.sanitized(
            UserDefaults.standard.string(forKey: DefaultsKey.screenshotMeasureUnit))
    }

    var imageSize: CGSize {
        image.map { CGSize(width: $0.width, height: $0.height) } ?? .zero
    }

    /// The editor hands over every new capture state: a crop, an expansion
    /// or an undo all change what the pixels are.
    func setImage(_ image: CGImage, scale: CGFloat) {
        guard image !== self.image || scale != self.scale else { return }
        self.image = image
        self.scale = scale
        line = nil
        refreshPointerReadings()
    }

    // MARK: Pointer

    private func refreshPointerReadings() {
        if let pointer, let image {
            let pixel = CGRect(x: pointer.x.rounded(.down), y: pointer.y.rounded(.down), width: 1, height: 1)
            pointerColor = Support.pixelGrid(of: image, region: pixel)?.pixels.first
        } else {
            pointerColor = nil
        }
        refreshLiveSpan()
    }

    private func refreshLiveSpan() {
        guard let mode = liveMode, let pointer, image != nil else {
            liveSpan = nil
            return
        }
        switch mode {
        case .guide(let axis):
            liveSpan = Support.guideSpan(axis: axis, pointer: pointer, imageSize: imageSize)
        case .distance(let axis):
            guard let pixels = linePixels(axis: axis, through: pointer) else {
                liveSpan = nil
                return
            }
            liveSpan = Support.measuredSpan(line: pixels, axis: axis, pointer: pointer)
        }
    }

    /// The row or column under the pointer. Moving along it reads nothing new.
    private func linePixels(axis: Support.Axis, through pointer: CGPoint) -> [Support.RGBA]? {
        guard let image else { return nil }
        let index = Int((axis == .horizontal ? pointer.y : pointer.x).rounded(.down))
        let key = LineKey(image: ObjectIdentifier(image), axis: axis, index: index)
        if let line, line.key == key { return line.pixels }
        let region = axis == .horizontal
            ? CGRect(x: 0, y: index, width: image.width, height: 1)
            : CGRect(x: index, y: 0, width: 1, height: image.height)
        guard let grid = Support.pixelGrid(of: image, region: region) else { return nil }
        line = (key, grid.pixels)
        return grid.pixels
    }

    /// The darkest color around the pointer, which over text is its ink.
    func textColorNearPointer() -> Support.RGBA? {
        guard let pointer, let image else { return nil }
        let side = max(20, 10 * scale)
        let region = CGRect(x: pointer.x - side / 2, y: pointer.y - side / 2, width: side, height: side)
        return Support.pixelGrid(of: image, region: region).flatMap(Support.darkest)
    }

    // MARK: Selection

    /// Reads the crop selection off the main thread. Only the latest answer
    /// lands, so dragging a grip never shows a reading for an older rectangle.
    func readSelection(_ rect: CGRect?) {
        selectionGeneration += 1
        let generation = selectionGeneration
        guard let rect, let image, rect.width >= 1, rect.height >= 1 else {
            selection = nil
            return
        }
        let size = rect.integral.size
        Self.selectionQueue.async { [weak self] in
            let grid = Support.pixelGrid(of: image, region: rect, maximumSide: 640)
            let reading = SelectionReading(size: size,
                                           average: grid.flatMap(Support.average),
                                           pair: grid.flatMap(Support.dominantPair))
            DispatchQueue.main.async { [weak self] in
                guard let self, self.selectionGeneration == generation else { return }
                self.selection = reading
            }
        }
    }

    /// The selection trimmed to its content, read at full resolution so the
    /// new edge lands on the exact pixel.
    func contentRect(in rect: CGRect) -> CGRect? {
        guard let image,
              let grid = Support.pixelGrid(of: image, region: rect),
              let content = Support.contentRect(in: grid)
        else { return nil }
        let origin = rect.integral.intersection(CGRect(x: 0, y: 0, width: image.width, height: image.height)).origin
        return content.offsetBy(dx: origin.x, dy: origin.y)
    }

    // MARK: Scrolling

    /// The scroll view the canvas sits in, found by the canvas itself.
    weak var scrollView: NSScrollView?

    /// Moves the canvas with the pointer, the way a hand tool does.
    func pan(by delta: CGSize) {
        guard let scrollView, let document = scrollView.documentView else { return }
        let clip = scrollView.contentView
        var origin = clip.bounds.origin
        origin.x -= delta.width
        origin.y += document.isFlipped ? -delta.height : delta.height
        scroll(scrollView, to: origin)
    }

    /// Brings `target`, in canvas points from the top left, to the middle.
    func center(on target: CGRect) {
        guard let scrollView, let document = scrollView.documentView else { return }
        let viewport = scrollView.contentView.bounds.size
        var origin = ScreenshotOutputSupport.scrollOrigin(centering: target, viewport: viewport,
                                                          content: document.frame.size)
        if !document.isFlipped {
            origin.y = document.frame.height - viewport.height - origin.y
        }
        scroll(scrollView, to: origin)
    }

    private func scroll(_ scrollView: NSScrollView, to origin: CGPoint) {
        guard let document = scrollView.documentView else { return }
        let clip = scrollView.contentView
        let limit = CGPoint(x: max(document.frame.width - clip.bounds.width, 0),
                            y: max(document.frame.height - clip.bounds.height, 0))
        clip.scroll(to: CGPoint(x: min(max(origin.x, 0), limit.x), y: min(max(origin.y, 0), limit.y)))
        scrollView.reflectScrolledClipView(clip)
    }

    // MARK: Colors

    static func nsColor(_ color: Support.RGBA) -> NSColor {
        NSColor(srgbRed: CGFloat(color.red) / 255, green: CGFloat(color.green) / 255,
                blue: CGFloat(color.blue) / 255, alpha: 1)
    }
}
