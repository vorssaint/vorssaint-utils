// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit

/// What the editor reads off the capture as the pointer moves, such as the
/// live measurement. An object of its own, so a moving pointer redraws only
/// these readouts and never the whole canvas.
final class ScreenshotEditorInspector: ObservableObject {
    typealias Support = ScreenshotInspectionSupport

    /// The image pixel under the pointer, or nil while it is off the capture.
    @Published var pointer: CGPoint? {
        didSet { refreshPointerReadings() }
    }
    @Published var liveMode: Support.LiveMode? {
        didSet { refreshLiveSpan() }
    }
    @Published private(set) var liveSpan: Support.Span?
    @Published var unit: Support.MeasureUnit {
        didSet { UserDefaults.standard.set(unit.rawValue, forKey: DefaultsKey.screenshotMeasureUnit) }
    }

    private(set) var image: CGImage?
    private(set) var scale: CGFloat = 1
    private var line: (key: LineKey, pixels: [Support.RGBA])?

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
}
