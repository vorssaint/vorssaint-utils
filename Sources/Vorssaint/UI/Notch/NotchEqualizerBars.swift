// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import SwiftUI

/// Decorative motion is stepped on the bars' own layers at a limited rate,
/// without a SwiftUI timeline or repeated Canvas drawing in the app process.
struct NotchEqualizerBars: View {
    var isPlaying = true
    var bars = 4
    var barWidth: CGFloat = 2.5
    var height: CGFloat = 14
    var tint: Color = .white
    /// The cover blurred to a few colours, `NotchArtworkTint.barField`. When
    /// present the bars are cut out of it instead of the tint's gradient.
    var field: [Double] = []
    /// Band levels from 0 to 1 read from the player's audio. When present the
    /// bars follow them instead of the stepped synthetic motion.
    var live: [Double]? = nil
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let count = max(1, bars)
        NotchEqualizerBridge(animates: isPlaying && !reduceMotion, bars: count,
                             barWidth: barWidth, height: height, tint: NSColor(tint), field: field,
                             levels: isPlaying && !reduceMotion ? live : nil)
            .frame(width: CGFloat(count) * barWidth + CGFloat(count - 1) * barWidth * 0.85,
                   height: height)
            // A hosted view has no baseline of its own, so beside text it
            // would hang below the line and make the row taller. The bars
            // stand on the baseline like the glyphs next to them.
            .alignmentGuide(.firstTextBaseline) { $0[.bottom] }
            .alignmentGuide(.lastTextBaseline) { $0[.bottom] }
            .accessibilityHidden(true)
            .allowsHitTesting(false)
    }
}

private struct NotchEqualizerBridge: NSViewRepresentable {
    let animates: Bool
    let bars: Int
    let barWidth: CGFloat
    let height: CGFloat
    let tint: NSColor
    let field: [Double]
    let levels: [Double]?

    func makeNSView(context: Context) -> NotchEqualizerView { NotchEqualizerView() }

    func updateNSView(_ view: NotchEqualizerView, context: Context) {
        view.configure(animates: animates, bars: bars, barWidth: barWidth, height: height,
                       tint: tint, field: field, levels: levels)
    }

    static func dismantleNSView(_ view: NotchEqualizerView, coordinator: ()) { view.stop() }
}

final class NotchEqualizerView: NSView {
    private var bars: [CALayer] = []
    private var barWidth: CGFloat = 0
    private var height: CGFloat = 0
    private var animates = false
    private var levels: [Double]?
    private var visibilityObservers: [NSObjectProtocol] = []
    /// Each bar's swing: its lowest and highest height, how long it takes
    /// to rise, and how far into its swing it starts.
    private var swings: [(low: CGFloat, high: CGFloat, rise: Double, lead: Double)] = []
    private(set) var motionStart: CFTimeInterval = 0
    /// Set once the view has joined the shared wave, so a hide, a cover or a
    /// display change does not start that wave over.
    private var joinedWave = false
    /// Heights copied from the wave already on screen. Kept through the frames
    /// that show this window, then dropped so the next level can move on.
    private var pinnedHeights: [CGFloat]?
    private lazy var clock = NotchDecorativeClock { [weak self] time in self?.step(at: time) }

    /// Every copy of the wave, the island and the ones on other displays,
    /// measures from this instant. Each copy keeping its own start made the
    /// bars jump when the windows traded places.
    private static let waveOrigin: CFTimeInterval = CACurrentMediaTime()
    static let holdWaveNotification = Notification.Name("NotchEqualizerHoldWave")

    /// The bars are cut out of one paint that runs across the row: the
    /// cover's own colours where it has them, else a gradient of the tint.
    private let paint = CALayer()
    private let gradient = CAGradientLayer()
    private let artwork = CALayer()
    private let barMask = CALayer()
    private var field: [Double] = []

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        setAccessibilityElement(false)
        gradient.startPoint = CGPoint(x: 0, y: 0.5)
        gradient.endPoint = CGPoint(x: 1, y: 0.5)
        // The few colours of the field are stretched over the row and
        // blended between, which is the blur the phone's island shows.
        artwork.magnificationFilter = .linear
        paint.addSublayer(gradient)
        paint.addSublayer(artwork)
        paint.mask = barMask
        layer?.addSublayer(paint)
    }

    /// The field as an image of `fieldColumns` by `fieldRows` pixels, top row
    /// first, or nil when it does not hold one.
    static func fieldImage(_ field: [Double]) -> CGImage? {
        let columns = NotchArtworkTint.fieldColumns, rows = NotchArtworkTint.fieldRows
        guard field.count == columns * rows * 3, let space = CGColorSpace(name: CGColorSpace.sRGB) else { return nil }
        var bytes = [UInt8](repeating: 255, count: columns * rows * 4)
        for cell in 0..<(columns * rows) {
            for channel in 0..<3 {
                bytes[cell * 4 + channel] = UInt8((min(1, max(0, field[cell * 3 + channel])) * 255).rounded())
            }
        }
        return bytes.withUnsafeMutableBytes { buffer -> CGImage? in
            guard let base = buffer.baseAddress else { return nil }
            return CGContext(data: base, width: columns, height: rows, bitsPerComponent: 8,
                             bytesPerRow: columns * 4, space: space,
                             bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)?.makeImage()
        }
    }

    /// The bar colour running toward a paler shade of itself across the row,
    /// the way the phone's island colours its bars, the more so the softer it is. How muted it starts is
    /// the caller's: see `NotchArtworkTint.barColor`.
    static func gradientColors(for tint: NSColor) -> [CGColor] {
        guard let rgb = tint.usingColorSpace(.sRGB) else { return [tint.cgColor, tint.cgColor] }
        var hue: CGFloat = 0, saturation: CGFloat = 0, brightness: CGFloat = 0, alpha: CGFloat = 0
        rgb.getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: &alpha)
        // A soft colour pales a good way across the row; a vivid one keeps
        // most of its strength, so hot pink does not wash out to pastel.
        let end = NSColor(hue: hue, saturation: saturation * (0.45 + 0.4 * saturation),
                          brightness: min(1, brightness + 0.1), alpha: alpha)
        return [rgb.cgColor, end.cgColor]
    }

    required init?(coder: NSCoder) { nil }

    deinit {
        visibilityObservers.forEach(NotificationCenter.default.removeObserver)
    }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    func configure(animates: Bool, bars count: Int, barWidth: CGFloat, height: CGFloat,
                   tint: NSColor, field: [Double] = [], levels: [Double]? = nil) {
        let count = max(1, count)
        self.animates = animates
        self.levels = levels
        self.barWidth = barWidth
        self.height = height
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        if bars.count != count {
            bars.forEach { $0.removeFromSuperlayer() }
            bars = (0..<count).map { _ in
                let bar = CALayer()
                bar.backgroundColor = NSColor.white.cgColor
                barMask.addSublayer(bar)
                return bar
            }
        }
        gradient.colors = Self.gradientColors(for: tint)
        if field != self.field {
            self.field = field
            artwork.contents = Self.fieldImage(field)
        }
        artwork.isHidden = artwork.contents == nil
        gradient.isHidden = !artwork.isHidden
        CATransaction.commit()
        updateBars()
    }

    func stop() {
        animates = false
        levels = nil
        updateBars()
        visibilityObservers.forEach(NotificationCenter.default.removeObserver)
        visibilityObservers = []
    }

    /// Draws the wave in its present pose. A display change asks for this
    /// while the copy is still covered, so uncovering it does not blink dots.
    func refreshMotion() { updateBars() }

    func barHeights() -> [CGFloat] { bars.map(\.bounds.height) }

    var barLayers: [CALayer] { bars }
    var barColors: [CGColor] { gradient.colors as? [CGColor] ?? [] }
    var showsArtwork: Bool { !artwork.isHidden }

    /// Shows `heights` until the window is on screen and the pose is let go.
    /// The island then covers a copy without the bars jumping to their own reading.
    func adopt(heights: [CGFloat]) {
        guard heights.count == bars.count else { return }
        pinnedHeights = heights
        updateBars()
    }

    func releasePose() { pinnedHeights = nil }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        visibilityObservers.forEach(NotificationCenter.default.removeObserver)
        visibilityObservers = []
        if let window {
            let names = [NSWindow.didChangeOcclusionStateNotification, Self.holdWaveNotification]
            visibilityObservers = names.map { name in
                NotificationCenter.default.addObserver(forName: name, object: window, queue: .main) { [weak self] _ in
                    self?.updateBars()
                }
            }
        }
        updateBars()
    }

    override func viewDidHide() { super.viewDidHide(); updateBars() }
    override func viewDidUnhide() { super.viewDidUnhide(); updateBars() }
    override func layout() { super.layout(); updateBars() }

    var isMoving: Bool { clock.isRunning }

    private func updateBars() {
        let exposed = !isHiddenOrHasHiddenAncestor
            && window?.isVisible == true && window?.occlusionState.contains(.visible) == true
        // Offscreen only to change displays: keep the pose. Dropping to dots
        // and rising again is the blink while music plays.
        let held = (window as? NotchWaveHold)?.holdsWave == true
        let moving = animates && (exposed || held)
        let live = moving ? levels.flatMap { $0.isEmpty ? nil : $0 } : nil
        let center = Double(bars.count - 1) / 2
        swings = bars.indices.map { index in
            let distance = abs(Double(index) - center) / max(1, center)
            let envelope = pow(1 - distance, 1.5)
            return (low: max(barWidth, height * (0.12 + envelope * 0.25)),
                    high: max(barWidth, height * (0.12 + envelope * 0.88)),
                    rise: .pi / (5.2 + Double(index) * 0.61), lead: Double(index) * 0.17)
        }
        let swinging = moving && live == nil && swings.contains { $0.high > $0.low }
        // Metadata, tint and layout updates must not restart the motion.
        // Neither does becoming visible again: every copy shares one origin.
        if swinging, !joinedWave {
            motionStart = Self.waveOrigin
            joinedWave = true
        }
        let now = CACurrentMediaTime()
        let shaped = live.map { live in
            bars.indices.map { live[NotchAudioLevelSupport.barIndex($0, of: bars.count, bands: live.count)] }
        }
        var heights = bars.indices.map { index -> CGFloat in
            if let shaped { return max(barWidth, height * CGFloat(shaped[index])) }
            if swinging { return swingHeight(index, at: now) }
            return moving ? swings[index].low : barWidth
        }
        // The pose already on the other display wins over a fresh reading,
        // including one made because the window just became visible.
        let pinned = pinnedHeights.flatMap { $0.count == bars.count && moving ? $0 : nil }
        if let pinned { heights = pinned } else { pinnedHeights = nil }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        paint.frame = bounds
        gradient.frame = paint.bounds
        artwork.frame = paint.bounds
        barMask.frame = paint.bounds
        for (index, bar) in bars.enumerated() {
            bar.bounds.size.width = barWidth
            bar.position = CGPoint(x: CGFloat(index) * barWidth * 1.85 + barWidth / 2, y: bounds.midY)
            bar.cornerRadius = barWidth / 2
        }
        CATransaction.commit()
        // Live levels arrive thirty times a second. Each bar glides to its
        // new height over one interval instead of jumping, so the motion
        // reads as continuous rather than stepped.
        let glides = live != nil && pinned == nil
        CATransaction.begin()
        CATransaction.setDisableActions(!glides)
        CATransaction.setAnimationDuration(1 / NotchAudioLevelSupport.updatesPerSecond)
        CATransaction.setAnimationTimingFunction(CAMediaTimingFunction(name: .linear))
        for (index, bar) in bars.enumerated() { bar.bounds.size.height = heights[index] }
        CATransaction.commit()
        if swinging { clock.start(in: self) } else { clock.stop() }
    }

    private func swingHeight(_ index: Int, at time: CFTimeInterval) -> CGFloat {
        let swing = swings[index]
        guard swing.high > swing.low else { return swing.low }
        let travel = NotchDecorativeClock.swing((time - motionStart + swing.lead) / swing.rise)
        return swing.low + (swing.high - swing.low) * CGFloat(travel)
    }

    func step(at time: CFTimeInterval) {
        guard clock.isRunning, pinnedHeights == nil else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for (index, bar) in bars.enumerated() where index < swings.count {
            bar.bounds.size.height = swingHeight(index, at: time)
        }
        CATransaction.commit()
    }
}

/// A window offscreen only to change displays. The music wave reads this
/// and keeps its pose instead of falling to dots.
protocol NotchWaveHold: AnyObject {
    var holdsWave: Bool { get }
}

extension NSView {
    /// The equalizers under this view draw their present pose. A hosting view
    /// keeps them as descendants, including a copy another display is showing.
    func refreshEqualizerMotion() {
        if let bars = self as? NotchEqualizerView { bars.refreshMotion() }
        subviews.forEach { $0.refreshEqualizerMotion() }
    }

    func collectEqualizerHeights() -> [[CGFloat]] {
        var found: [[CGFloat]] = []
        if let bars = self as? NotchEqualizerView { found.append(bars.barHeights()) }
        subviews.forEach { found.append(contentsOf: $0.collectEqualizerHeights()) }
        return found
    }

    func adoptEqualizerHeights(_ heights: [[CGFloat]]) {
        var remaining = heights
        adoptEqualizerHeights(from: &remaining)
    }

    private func adoptEqualizerHeights(from heights: inout [[CGFloat]]) {
        if let bars = self as? NotchEqualizerView, !heights.isEmpty {
            bars.adopt(heights: heights.removeFirst())
        }
        subviews.forEach { $0.adoptEqualizerHeights(from: &heights) }
    }

    func releaseEqualizerPose() {
        if let bars = self as? NotchEqualizerView { bars.releasePose() }
        subviews.forEach { $0.releaseEqualizerPose() }
    }
}
