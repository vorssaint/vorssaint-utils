// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit

/// Color picking is extracted from the real editor model; the published
/// controls keep the same didSet hooks the model gives them.
enum ScreenshotCustomColorTests {
    typealias CustomColor = ScreenshotSupport.CustomColor

    class Fixture {
        var annotations: [ScreenshotSupport.Annotation] = []
        var selectedID: UUID?
        let scale: CGFloat = 1
        var history: [[ScreenshotSupport.Annotation]] = []
        var color: ScreenshotSupport.ColorID = .red { didSet { (self as? Model)?.applyStyleToSelection() } }
        var customColor: CustomColor? { didSet { (self as? Model)?.applyStyleToSelection() } }
        var usesCustomColor = false { didSet { (self as? Model)?.applyStyleToSelection() } }
        var stroke: ScreenshotSupport.StrokeID = .medium
        var arrowStyle: ScreenshotSupport.ArrowStyleID = .filled
        var textSize = ScreenshotSupport.defaultTextSize
        var textStyle: ScreenshotSupport.TextStyleID = .plain
        var shapeFill: ScreenshotSupport.ShapeFillID = .outline
        var sloppy = false
        var deferringStyleApply = false
        var coalescesColorEdits = false
        var coalescedColorEditID: UUID?
        func registerUndo() { history.append(annotations) }
    }

    static func run(_ suite: TestSuite) {
        // Storage, contrast and rendering are covered with the other style
        // checks in ScreenshotFeatureTests; these cover picking in the editor.
        let teal = CustomColor(red: 0.1, green: 0.6, blue: 0.55)
        let model = Model()
        let box = ScreenshotSupport.Annotation(tool: .rect, rect: CGRect(x: 0, y: 0, width: 40, height: 40))
        model.annotations = [box]
        model.selectedID = box.id
        model.pickCustomColor(teal)
        suite.expect(model.annotations[0].customColor == teal && model.history.count == 1
                && model.activeCustomColor == teal,
               "picking a custom color recolors the selected mark in one undo step")

        let coral = CustomColor(red: 1, green: 0.5, blue: 0.4)
        let plum = CustomColor(red: 0.5, green: 0.2, blue: 0.5)
        model.beginColorPanelSession()
        model.pickCustomColor(coral, continuous: true)
        model.pickCustomColor(plum, continuous: true)
        suite.expect(model.annotations[0].customColor == plum && model.history.count == 2
                && model.history[1][0].customColor == teal,
               "dragging across the color panel is one undo step back to the color before")
        model.beginColorPanelSession()
        model.pickCustomColor(coral, continuous: true)
        suite.expect(model.history.count == 3,
               "showing the panel again starts a new undo step")

        model.pickPresetColor(.green)
        suite.expect(model.annotations[0].customColor == nil && model.annotations[0].color == .green
                && model.history.count == 4 && model.customColor == coral && !model.usesCustomColor,
               "a preset replaces the custom color in one step and keeps the custom swatch")
        model.pickPresetColor(.green)
        suite.expect(model.history.count == 4,
               "picking the color already in use records nothing")

        let sticker = ScreenshotSupport.Annotation(tool: .sticker)
        model.annotations = [sticker]
        model.selectedID = sticker.id
        model.pickCustomColor(teal)
        suite.expect(model.annotations[0].customColor == nil && model.history.count == 4,
               "marks without a color ignore a custom pick")
    }
}
