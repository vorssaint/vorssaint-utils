// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import CoreGraphics
import Foundation

/// Runs the editor's production press, hover, selection, dirty-state,
/// remembered dim, dim slider and style-bar rules for spotlight regions
/// against plain state. No window is created.
enum ScreenshotSpotlightEditingTests {
    /// Stands in for the app defaults, so the remembered dim is read back
    /// without writing the test process's own.
    enum UserDefaults {
        final class Store {
            private(set) var doubles: [String: Double] = [:]
            func set(_ value: Double, forKey key: String) { doubles[key] = value }
        }
        static let standard = Store()
    }

    /// Records the cursor the hover rule picks.
    final class NSCursor {
        static let openHand = NSCursor()
        static let crosshair = NSCursor()
        static let iBeam = NSCursor()
        static let arrow = NSCursor()
        static var current: NSCursor?
        func set() { NSCursor.current = self }
    }

    class State {
        var tool: ScreenshotSupport.Tool = .spotlight
        var annotations: [ScreenshotSupport.Annotation] = []
        var selectedID: UUID?
        var draftID: UUID?
        let scale: CGFloat = 1
        let imageSize = CGSize(width: 200, height: 100)
        var dragStart: CGPoint = .zero
        var dragRegistered = false
        var editingSelectedAnnotation = false
        var cropDraft: CGRect?
        var cropLoupePoint: CGPoint?
        var activeHandle: ScreenshotSupport.Handle?
        var cropResizeOrigin: CGRect?
        var cropMoveOrigin: CGRect?
        var cropSelectionOrigin: CGRect?
        var expansionDraft: CGRect?
        var expansionHandle: ScreenshotSupport.Handle?
        var expansionStartPoint: CGPoint?
        var expansionRejected = false
        let currentDisplayZoom: CGFloat = 1
        var color: ScreenshotSupport.ColorID = .red
        var stroke: ScreenshotSupport.StrokeID = .medium
        var arrowStyle: ScreenshotSupport.ArrowStyleID = .filled
        var blurLevel = ScreenshotSupport.BlurStrength.defaultLevel
        var blurStyle: ScreenshotSupport.BlurStyleID = .pixelate
        var blurTextOnly = false
        var selectDrags: [CGPoint] = []

        let baseImage: CGImage
        var cleanImage: CGImage?
        var cleanAnnotations: [ScreenshotSupport.Annotation] = []
        var backdropStyle = ScreenshotSupport.BackdropStyle()
        var cleanBackdropStyle = ScreenshotSupport.BackdropStyle().sanitized()
        var watermarkStyle = ScreenshotSupport.WatermarkStyle()
        var cleanWatermarkStyle = ScreenshotSupport.WatermarkStyle().sanitized()
        var annotationShadowsEnabled = false
        var cleanAnnotationShadowsEnabled = false
        var spotlightDimStrength: CGFloat = 0.5
        var cleanSpotlightDimStrength: CGFloat = 0.5
        var isDirty = false

        init(image: CGImage) {
            baseImage = image
            cleanImage = image
        }

        func registerUndo() {}
        func wordIndex(at point: CGPoint) -> Int? { nil }
        func beginSelectDrag(at point: CGPoint) { selectDrags.append(point) }
        @discardableResult
        func ensureBlurSample(_ style: ScreenshotSupport.BlurStyleID, level: Int) -> Bool { true }
    }

    static func run(_ suite: TestSuite) {
        guard let image = CGContext(data: nil, width: 2, height: 2, bitsPerComponent: 8,
                                    bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)?.makeImage()
        else {
            suite.expect(false, "the spotlight editing fixture has a capture")
            return
        }
        let rect = CGRect(x: 40, y: 20, width: 120, height: 60)
        func model(tool: ScreenshotSupport.Tool, selected: ScreenshotSupport.Tool) -> Model {
            let model = Model(image: image)
            model.tool = tool
            let mark = ScreenshotSupport.Annotation(tool: selected, rect: rect)
            model.annotations = [mark]
            model.selectedID = mark.id
            return model
        }

        let corner = model(tool: .spotlight, selected: .spotlight)
        corner.beginDrag(at: CGPoint(x: rect.minX, y: rect.minY))
        let edge = model(tool: .spotlight, selected: .spotlight)
        edge.beginDrag(at: CGPoint(x: rect.minX, y: rect.minY + 15))
        suite.expect(corner.editingSelectedAnnotation && corner.annotations.count == 1
                && corner.selectDrags.count == 1
                && edge.editingSelectedAnnotation && edge.annotations.count == 1,
               "the spotlight tool resizes a fresh region from its handles and moves it by its edge")

        let inside = model(tool: .spotlight, selected: .spotlight)
        inside.beginDrag(at: CGPoint(x: rect.midX, y: rect.midY))
        suite.expect(!inside.editingSelectedAnnotation && inside.selectDrags.isEmpty
                && inside.annotations.count == 2 && inside.selectedID == nil
                && inside.annotations.last?.tool == .spotlight
                && inside.draftID == inside.annotations.last?.id,
               "a drag inside a fresh spotlight region starts another region")

        let box = model(tool: .rect, selected: .rect)
        box.beginDrag(at: CGPoint(x: rect.midX, y: rect.midY))
        suite.expect(box.editingSelectedAnnotation && box.annotations.count == 1,
               "other rectangle tools still move a fresh mark from inside it")

        let expanding = model(tool: .expandCanvas, selected: .rect)
        expanding.beginDrag(at: CGPoint(x: rect.midX, y: rect.midY))
        Bar(model: expanding).updateHoverCursor(at: CGPoint(x: rect.midX, y: rect.midY))
        suite.expect(!expanding.editingSelectedAnnotation && expanding.selectDrags.isEmpty
                && expanding.annotations.count == 1
                && expanding.expansionDraft == CGRect(origin: .zero, size: expanding.imageSize)
                && NSCursor.current === NSCursor.crosshair,
               "expanding the canvas never moves a picked mark, and the hover never offers to")

        let hovered = model(tool: .spotlight, selected: .spotlight)
        Bar(model: hovered).updateHoverCursor(at: CGPoint(x: rect.midX, y: rect.midY))
        let insideCursor = NSCursor.current
        Bar(model: hovered).updateHoverCursor(at: CGPoint(x: rect.minX, y: rect.minY))
        let cornerCursor = NSCursor.current
        Bar(model: hovered).updateHoverCursor(at: CGPoint(x: rect.minX, y: rect.minY + 15))
        let edgeCursor = NSCursor.current
        Bar(model: model(tool: .rect, selected: .rect))
            .updateHoverCursor(at: CGPoint(x: rect.midX, y: rect.midY))
        let boxCursor = NSCursor.current
        suite.expect(insideCursor === NSCursor.crosshair && cornerCursor === NSCursor.openHand
                && edgeCursor === NSCursor.openHand && boxCursor === NSCursor.openHand,
               "the spotlight hover offers a fresh region's handles and edge, and draws inside it")

        let pickedRegion = model(tool: .select, selected: .spotlight)
        let pickedBox = model(tool: .select, selected: .rect)
        let nothingPicked = Model(image: image)
        nothingPicked.tool = .select
        suite.expect(!Bar(model: pickedRegion).showsColorControls
                && Bar(model: pickedRegion).showsSpotlightControls
                && Bar(model: pickedBox).showsColorControls
                && !Bar(model: pickedBox).showsSpotlightControls
                && Bar(model: corner).showsSpotlightControls
                && !Bar(model: corner).showsColorControls
                && !Bar(model: nothingPicked).showsSpotlightControls,
               "a picked spotlight region shows the dim control instead of color and thickness")

        let empty = Model(image: image)
        empty.spotlightDimStrength = 0.8
        empty.refreshDirtyState()
        let lit = Model(image: image)
        lit.annotations = [ScreenshotSupport.Annotation(tool: .spotlight, rect: rect)]
        lit.cleanAnnotations = lit.annotations
        lit.refreshDirtyState()
        let litClean = !lit.isDirty
        lit.spotlightDimStrength = 0.8
        lit.refreshDirtyState()
        suite.expect(!empty.isDirty && litClean && lit.isDirty,
               "moving the dim marks the edit changed only when a spotlight region exists")

        let remembering = Model(image: image)
        remembering.spotlightDimStrength = 0.35
        suite.expect(UserDefaults.standard.doubles[DefaultsKey.screenshotSpotlightDim] == 0.35,
               "moving the dim remembers it for the next capture")

        let dimming = Model(image: image)
        let dim = Bar(model: dimming).spotlightDimValue
        dim.wrappedValue = 0.52
        let roundedDown = dimming.spotlightDimStrength
        dim.wrappedValue = 0.68
        let roundedUp = dimming.spotlightDimStrength
        dim.wrappedValue = 1.3
        suite.expect(roundedDown == 0.5 && roundedUp == 0.7 && dimming.spotlightDimStrength == 1
                && ScreenshotSupport.steppedSpotlightDim(-0.2) == 0
                && ScreenshotSupport.steppedSpotlightDim(0.35) == 0.35,
               "the continuous dim slider settles on the nearest 5% step")
    }
}
