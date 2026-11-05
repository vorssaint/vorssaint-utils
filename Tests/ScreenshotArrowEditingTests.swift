// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit

/// The gesture methods are extracted from the real editor; desktop text
/// recognition and style controls are the only substituted collaborators.
enum ScreenshotArrowEditingTests {
    class Fixture {
        var annotations: [ScreenshotSupport.Annotation] = []
        var selectedID: UUID?
        let scale: CGFloat = 1
        let imageSize = CGSize(width: 240, height: 180)
        var activeHandle: ScreenshotSupport.Handle?
        var activePointIndex: Int?
        var moveOrigin: CGRect = .zero
        var movePoints: [CGPoint] = []
        var dragStart: CGPoint = .zero
        var dragRegistered = false
        var textSelectionAnchor: CGPoint?
        var selectedWordIndexes: [Int] = []
        var textWords: [ScreenshotSupport.RecognizedWord] = []
        var history: [[ScreenshotSupport.Annotation]] = []
        func syncControls(to annotation: ScreenshotSupport.Annotation) {}
        func clearTextSelection() { selectedWordIndexes = [] }
        func wordIndex(at point: CGPoint) -> Int? { nil }
        func registerUndo() { history.append(annotations) }
    }

    static func run(_ suite: TestSuite) {
        let tail = CGPoint(x: 20, y: 40), tip = CGPoint(x: 180, y: 40)
        let middle = CGPoint(x: 100, y: 120)
        let straight = ScreenshotSupport.Annotation(tool: .arrow, points: [tail, tip])
        suite.expect(ScreenshotSupport.annotationPointHandles(straight) == [tail, tip, CGPoint(x: 100, y: 40)],
                     "a straight arrow exposes a central bend grip without changing its document")

        let model = Model()
        model.annotations = [straight]
        model.selectedID = straight.id
        model.dragStart = CGPoint(x: 100, y: 40)
        model.beginSelectDrag(at: model.dragStart)
        model.continueSelectDrag(to: CGPoint(x: 100, y: 90))
        model.continueSelectDrag(to: middle)
        let bent = model.annotations[0]
        suite.expect(bent.points == [tail, tip, middle] && model.history.count == 1
                        && model.history[0] == [straight],
                     "dragging the central grip bends the arrow and records one undo step for the whole drag")
        let curve = ScreenshotSupport.ArrowCurve(from: tail, to: tip, through: middle)
        suite.expect(curve.point(at: 0) == tail && curve.point(at: 1) == tip && curve.point(at: 0.5) == middle,
                     "the quadratic Bézier passes through the draggable midpoint and both endpoints")
        suite.expect(model.hitTest(middle) == bent.id && model.hitTest(CGPoint(x: 100, y: 40)) == nil
                        && model.selectedAnnotationOwns(middle),
                     "a bent arrow is selected along its curve rather than its original straight chord")

        model.activePointIndex = nil
        model.dragRegistered = false
        model.dragStart = tip
        model.beginSelectDrag(at: tip)
        let newTip = CGPoint(x: 200, y: 60)
        model.continueSelectDrag(to: newTip)
        suite.expect(model.annotations[0].points == [tail, newTip, middle],
                     "moving a curved arrow endpoint preserves its other endpoint and bend grip")

        model.annotations = [bent]
        model.activePointIndex = nil
        model.dragRegistered = false
        model.dragStart = curve.point(at: 0.25)
        model.beginSelectDrag(at: model.dragStart)
        model.continueSelectDrag(to: CGPoint(x: model.dragStart.x + 10, y: model.dragStart.y + 15))
        suite.expect(model.annotations[0].points == bent.points.map { CGPoint(x: $0.x + 10, y: $0.y + 15) },
                     "dragging the curve moves its endpoints and midpoint together")

        for tool in [ScreenshotSupport.Tool.line, .ruler, .counter] {
            let annotation = ScreenshotSupport.Annotation(tool: tool, points: [tail, tip])
            suite.expect(ScreenshotSupport.annotationPointHandles(annotation) == [tail, tip],
                         "\(tool.rawValue) keeps its existing two endpoint grips")
        }
        for style in ScreenshotSupport.ArrowStyleID.allCases {
            for scale: CGFloat in [1, 2] {
                for shadows in [false, true] {
                    let annotation = ScreenshotSupport.Annotation(tool: .arrow, points: [tail, tip, middle],
                                                                  color: .red, arrowStyle: style, scribbleSeed: 17)
                    let context = CGContext(data: nil, width: 240, height: 180, bitsPerComponent: 8,
                                            bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
                    let base = context.makeImage()!
                    let image = ScreenshotRenderer.renderExport(
                        baseImage: base, annotations: [annotation], blurSources: .none, scale: scale,
                        annotationShadowsEnabled: shadows, watermark: ScreenshotSupport.WatermarkStyle(),
                        watermarkImage: nil, style: ScreenshotSupport.BackdropStyle(), fill: .none,
                        downscaleTo1x: false)!.image
                    let bytes = CFDataGetBytePtr(image.dataProvider!.data!)!
                    func alpha(_ x: Int, _ y: Int) -> UInt8 { bytes[y * image.bytesPerRow + x * 4 + 3] }
                    suite.expect(alpha(100, 120) > 180 && alpha(100, 40) == 0,
                                 "\(style.rawValue) curve at \(scale)x shadows=\(shadows) exports through the bend grip")
                }
            }
        }
        let head = curve.head(strokeWidth: 4)
        let headBase = CGPoint(x: (head.left.x + head.right.x) / 2, y: (head.left.y + head.right.y) / 2)
        suite.expect(headBase.x < tip.x && headBase.y > tip.y,
                     "the curved arrowhead follows the terminal tangent rather than the endpoint chord")
        let firstSketch = ScreenshotSupport.scribblyArrowPath(from: tail, to: tip, strokeWidth: 4,
                                                               seed: 17, through: middle)
        suite.expect(firstSketch == ScreenshotSupport.scribblyArrowPath(from: tail, to: tip, strokeWidth: 4,
                                                                         seed: 17, through: middle)
                        && firstSketch != ScreenshotSupport.scribblyArrowPath(from: tail, to: tip, strokeWidth: 4,
                                                                               seed: 18, through: middle),
                     "curved scribbly arrows keep their seeded variation through redraw and export")
        for tool in [ScreenshotSupport.Tool.rect, .ellipse, .line] {
            let first = ScreenshotSupport.Annotation(tool: tool, sloppy: true)
            let second = ScreenshotSupport.Annotation(tool: tool, sloppy: true)
            func path(_ seed: UInt64) -> CGPath {
                switch tool {
                case .rect: return ScreenshotSupport.sloppyRectPath(CGRect(x: 20, y: 20, width: 150, height: 90),
                                                                    strokeWidth: 4, seed: seed)
                case .ellipse: return ScreenshotSupport.sloppyEllipsePath(CGRect(x: 20, y: 20, width: 150, height: 90),
                                                                          strokeWidth: 4, seed: seed)
                default: return ScreenshotSupport.sloppyLinePath(from: tail, to: tip, strokeWidth: 4, seed: seed)
                }
            }
            suite.expect(first.scribbleSeed != second.scribbleSeed
                            && path(first.scribbleSeed) != path(second.scribbleSeed)
                            && path(first.scribbleSeed) == path(first.scribbleSeed),
                         "each new sloppy \(tool.rawValue) gets its own stable outline")
        }
    }
}
