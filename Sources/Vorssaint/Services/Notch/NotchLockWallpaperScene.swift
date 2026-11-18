// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import CoreGraphics
import Foundation

/// The lock screen's own wallpaper: deep space in the MacBook's space black,
/// a field of stars, a faint Milky Way rising out of the bottom left corner
/// and a great moon rising out of the bottom right. It follows the lock
/// screen's layout: the moon crests just under the right rail and clear of
/// the login, and toward every widget the sky quietens to an even black, so
/// the glass tiles read the same everywhere.
///
/// The still frame is set as the desktop picture. Over the lock screen the
/// live layer adds only what moves, drawn from this same scene so it lands
/// on the still frame's own pixels: sparkles on its brightest stars,
/// shooting stars through open sky, and the moon again in tonight's phase.
/// Everything here is pure and safe to run off the main thread.
struct NotchLockWallpaperScene {
    typealias V3 = SIMD3<Double>

    /// A rounded box in points from the top left.
    struct Box: Equatable {
        var x, y, w, h: Double
        var rect: CGRect { CGRect(x: x, y: y, width: w, height: h) }
    }

    /// One of the still frame's stars, bright enough to sparkle.
    struct Star: Equatable {
        var x, y: Double
        var brightness: Double
        var tone: V3
    }

    /// Bumped whenever the drawing changes, so a still frame from an older
    /// scene is never taken for this one.
    static let version = 1

    let width: Double
    let height: Double
    /// Pixels to a point.
    let scale: Double
    /// Under the clock, the stage and both rails.
    let wells: [Box]
    /// The system's own clock and login controls, which nothing that moves
    /// may cross.
    let systemZones: [Box]
    let railBottom: Double
    let moonRadius: Double
    let moonCentre: CGPoint

    /// The sun the still frame is lit by: from the upper left and a little
    /// behind, a lit crest and a terminator sweeping down the moon's right.
    static let stillSun = normalize(V3(-0.82, 0.42, 0.3))

    init(width: Double, height: Double, scale: Double) {
        self.width = width
        self.height = height
        self.scale = scale
        let stageWidth = Double(NotchLockScreenLayout.stageWidth)
        let railWidth = Double(NotchLockScreenLayout.railWidth)
        let railTop = Double(NotchLockScreenLayout.railTop)
        let column = (width - stageWidth) / 2
        let inset = ((column - railWidth) / 2).rounded()
        railBottom = height - Double(NotchLockScreenLayout.loginClearance)
        let clockBottom = Double(NotchLockScreenLayout.clockBottom(screenHeight: CGFloat(height)))
        let stageTop = clockBottom + Double(NotchLockScreenLayout.rowGap + NotchLockScreenLayout.rowHeight
                                            + NotchLockScreenLayout.stageGap)
        let clock = Box(x: width / 2 - 220, y: 46, w: 440, h: clockBottom - 46)
        var wells = [Box(x: (width - stageWidth) / 2, y: stageTop, w: stageWidth, h: railBottom - stageTop), clock]
        // Both rails, whichever are on: the frame is set once and outlives
        // the lock screen's settings.
        if column >= railWidth + Double(NotchLockScreenLayout.railMargin) * 2 {
            wells.append(Box(x: inset, y: railTop, w: railWidth, h: railBottom - railTop))
            wells.append(Box(x: width - inset - railWidth, y: railTop, w: railWidth, h: railBottom - railTop))
        }
        self.wells = wells
        // The menu bar, the clock, and the login controls with the lock
        // screen message over them.
        let login = Box(x: width / 2 - 200, y: railBottom - 16, w: 400, h: height - railBottom + 16)
        systemZones = [Box(x: 0, y: 0, w: width, h: 36), clock, login]
        // Low on the right, cresting just under the rail. On a narrow display
        // it moves right until it and its fade keep off the login controls,
        // whose nearest point is their bottom right corner.
        let radius = width * 0.47
        let centreY = railBottom + 30 + radius
        let reach = radius + Self.moonFade + 4, below = centreY - height
        let clear = below < reach ? (reach * reach - below * below).squareRoot() : 0
        moonRadius = radius
        moonCentre = CGPoint(x: max(width * 0.94, login.x + login.w + clear), y: centreY)
    }

    /// How far past its limb the live moon fades into the still frame.
    static let moonFade = 34.0

    var pixelWidth: Int { Int((width * scale).rounded()) }
    var pixelHeight: Int { Int((height * scale).rounded()) }

    // MARK: Drawing

    /// The whole still frame.
    func renderFrame() -> CGImage? {
        render(CGRect(x: 0, y: 0, width: width, height: height)) { x, y in
            (shade(x, y, sun: Self.stillSun, earthshine: 0.03), 1)
        }
    }

    /// The moon lit by `sun`, over the sky it sits in, in points from the
    /// top left. It is opaque on the disc and fades out just past the limb,
    /// before the still frame's limb glow could differ from it.
    func renderMoon(sun: V3, earthshine: Double) -> (image: CGImage, frame: CGRect)? {
        let margin = Self.moonFade
        let r = moonRadius
        let frame = CGRect(x: moonCentre.x - r - margin, y: moonCentre.y - r - margin,
                           width: 2 * (r + margin), height: 2 * (r + margin))
            .intersection(CGRect(x: 0, y: 0, width: width, height: height)).integral
        guard !frame.isEmpty else { return nil }
        let image = render(frame) { x, y in
            let dx = x - moonCentre.x, dy = y - moonCentre.y
            let beyond = (dx * dx + dy * dy).squareRoot() - r
            let alpha = Self.smoothstep(margin - 2, 2, beyond)
            guard alpha > 0 else { return (.zero, 0) }
            return (shade(x, y, sun: sun, earthshine: earthshine), alpha)
        }
        return image.map { ($0, frame) }
    }

    /// Draws `frame` in sRGB, premultiplied, at the scene's scale.
    private func render(_ frame: CGRect, pixel: (Double, Double) -> (V3, Double)) -> CGImage? {
        let px = Int((frame.width * scale).rounded()), py = Int((frame.height * scale).rounded())
        guard px > 0, py > 0, let space = CGColorSpace(name: CGColorSpace.sRGB) else { return nil }
        var data = [UInt8](repeating: 0, count: px * py * 4)
        let originX = Double(frame.minX), originY = Double(frame.minY)
        data.withUnsafeMutableBufferPointer { buffer in
            let base = buffer.baseAddress!
            DispatchQueue.concurrentPerform(iterations: py) { j in
                let row = base + j * px * 4
                let y = originY + (Double(j) + 0.5) / scale
                for i in 0..<px {
                    let (c, a) = pixel(originX + (Double(i) + 0.5) / scale, y)
                    // Grain under a step of 8-bit colour, so the dark sky
                    // doesn't band. Keyed to the whole frame's pixel, so a
                    // part drawn alone matches the frame.
                    let gi = i + Int((originX * scale).rounded()), gj = j + Int((originY * scale).rounded())
                    let n = (Self.hash(gi, gj, 7) - 0.5) * 1.6
                    for k in 0..<3 {
                        let value = max(0, min(255, (c[k] * 255 + n).rounded()))
                        row[i * 4 + k] = UInt8((value * a).rounded())
                    }
                    row[i * 4 + 3] = UInt8((a * 255).rounded())
                }
            }
        }
        guard let provider = CGDataProvider(data: Data(data) as CFData) else { return nil }
        return CGImage(width: px, height: py, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: px * 4,
                       space: space, bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                       provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)
    }

    // MARK: The sky

    private static let ground = rgb(0x050608), groundLow = rgb(0x08090D)

    /// How far the nearest widget is, in points; negative inside one.
    func widgetDistance(_ x: Double, _ y: Double) -> Double {
        wells.reduce(Double.infinity) { min($0, Self.distance(x, y, $1)) }
    }

    func shade(_ x: Double, _ y: Double, sun: V3, earthshine: Double) -> V3 {
        // The sky quietens toward the widgets, so the glass shows an even
        // black, without hard edges where a widget is off.
        let near = widgetDistance(x, y)
        let open = Self.smoothstep(-6, 90, near)

        var sky = Self.mix(Self.ground, Self.groundLow, Self.smoothstep(0, 1, y / height))
        let g = galaxy(x, y) * open
        sky += Self.mix(V3(0.55, 0.6, 0.72), V3(0.8, 0.7, 0.6), g) * g * 0.24
        let starlight = Self.stars(x, y, cell: 11, chance: 0.32, seed: 101)
            + Self.stars(x, y, cell: 4, chance: 0.5 * g, seed: 211) * 0.45
        sky += starlight * (0.45 + 0.55 * Self.smoothstep(-10, 30, near))

        // The moon, and a breath of light off its sunlit limb.
        let u = (x - moonCentre.x) / moonRadius, v = (moonCentre.y - y) / moonRadius
        let r = (u * u + v * v).squareRoot()
        if r > 1 {
            let side = max(0, Self.dot(Self.normalize(V3(u, v, 0)), sun))
            sky += V3(0.6, 0.65, 0.75) * exp(-(r - 1) * moonRadius / 26) * 0.06 * side
        }
        let m = moon(u, v, sun: sun, earthshine: earthshine, pixel: 0.8 / (moonRadius * scale))
        return Self.mix(sky, m.color, m.cover)
    }

    /// The Milky Way: a faint band rising out of the bottom left corner,
    /// across from the moon.
    private func galaxy(_ x: Double, _ y: Double) -> Double {
        let ax = width * 0.32, ay = height * 1.08, bx = -width * 0.12, by = height * 0.3
        let dx = bx - ax, dy = by - ay
        let len = (dx * dx + dy * dy).squareRoot()
        let across = ((x - ax) * dy - (y - ay) * dx) / len
        let along = ((x - ax) * dx + (y - ay) * dy) / len
        let band = width * 0.085 * (0.8 + 0.5 * Self.fbm(along / 260, 0.5, octaves: 3, seed: 31))
        let strength = exp(-(across / band) * (across / band))
        let cloud = Self.fbm(x / 140, y / 140, octaves: 6, seed: 41)
        let dust = Self.smoothstep(0.45, 0.7, Self.fbm(x / 70 + 9, y / 70, octaves: 5, seed: 53))
        return strength * Self.smoothstep(0.2, 0.75, cloud) * (1 - 0.75 * dust * strength)
    }

    private static func starTone(_ i: Int, _ j: Int, seed: Int) -> V3 {
        mix(V3(0.78, 0.86, 1.0), V3(1.0, 0.9, 0.76), hash(i, j, seed + 4))
    }

    private static func starBrightness(_ i: Int, _ j: Int, seed: Int) -> Double {
        pow(hash(i, j, seed + 3), 7) * 1.4 + 0.05
    }

    /// Stars in a lattice of `cell` points, `chance` of one to a cell.
    private static func stars(_ x: Double, _ y: Double, cell: Double, chance: Double, seed: Int) -> V3 {
        var sum = V3.zero
        let cx = Int(floor(x / cell)), cy = Int(floor(y / cell))
        for j in (cy - 1)...(cy + 1) {
            for i in (cx - 1)...(cx + 1) {
                guard hash(i, j, seed) < chance else { continue }
                let sx = (Double(i) + hash(i, j, seed + 1)) * cell
                let sy = (Double(j) + hash(i, j, seed + 2)) * cell
                let brightness = starBrightness(i, j, seed: seed)
                let sigma = 0.3 + 0.45 * brightness
                let d2 = (x - sx) * (x - sx) + (y - sy) * (y - sy)
                var light = brightness * exp(-d2 / (2 * sigma * sigma))
                if brightness > 0.8 { light += brightness * 0.05 * exp(-d2.squareRoot() / 4) }
                sum += starTone(i, j, seed: seed) * light
            }
        }
        return sum
    }

    /// The still frame's brightest stars out in open sky: off the widgets,
    /// the moon and the system's own controls, where a sparkle may show.
    func sparklingStars(minimum: Double = 0.2) -> [Star] {
        let cell = 11.0, seed = 101
        var found: [Star] = []
        for j in 0...Int(height / cell) {
            for i in 0...Int(width / cell) {
                guard Self.hash(i, j, seed) < 0.32 else { continue }
                let brightness = Self.starBrightness(i, j, seed: seed)
                guard brightness >= minimum else { continue }
                let x = (Double(i) + Self.hash(i, j, seed + 1)) * cell
                let y = (Double(j) + Self.hash(i, j, seed + 2)) * cell
                guard isOpenSky(x, y, clearance: 24) else { continue }
                found.append(Star(x: x, y: y, brightness: brightness, tone: Self.starTone(i, j, seed: seed)))
            }
        }
        return found
    }

    /// Clear of every widget, the moon and the system's controls by
    /// `clearance` points, and on the display.
    func isOpenSky(_ x: Double, _ y: Double, clearance: Double) -> Bool {
        guard x >= clearance, y >= clearance, x <= width - clearance, y <= height - clearance,
              widgetDistance(x, y) >= clearance,
              !systemZones.contains(where: { Self.distance(x, y, $0, radius: 0) < clearance })
        else { return false }
        let dx = x - moonCentre.x, dy = y - moonCentre.y
        return (dx * dx + dy * dy).squareRoot() >= moonRadius + clearance
    }

    // MARK: The moon

    private struct Crater { var centre: V3; var radius: Double; var depth: Double; var fresh: Bool }

    private static let craters: [Crater] = {
        var list: [Crater] = []
        var i = 0
        while list.count < 1400 {
            defer { i += 1 }
            let u = hash(i, 1, 91) * 2 - 1, v = hash(i, 2, 91) * 1.1 - 0.1
            guard u * u + v * v < 0.98 else { continue }
            let centre = V3(u, v, (1 - u * u - v * v).squareRoot())
            let size = pow(hash(i, 3, 91), 9)
            list.append(Crater(centre: centre, radius: 0.004 + 0.12 * size,
                               depth: 0.5 + 0.5 * hash(i, 4, 91), fresh: hash(i, 5, 91) < 0.12))
        }
        return list
    }()

    /// The moon's colour at a point of its disc in moon units (y up), and
    /// how much of the pixel it covers.
    private func moon(_ u: Double, _ v: Double, sun: V3, earthshine: Double,
                      pixel: Double) -> (color: V3, cover: Double) {
        let r2 = u * u + v * v
        let cover = Self.smoothstep(1 + pixel, 1 - pixel, r2.squareRoot())
        guard cover > 0 else { return (.zero, 0) }
        let n = V3(u, v, max(0, 1 - r2).squareRoot())

        // Seas: broad dark plains, ragged at their shores.
        let sx = n.x * 3.2 + n.z * 1.4, sy = n.y * 3.2 - n.z * 0.8
        let sea = Self.smoothstep(0.46, 0.58, Self.fbm(sx + 3.1, sy + 7.7, octaves: 6, seed: 5))
        var albedo = Self.mix(0.56, 0.27, sea)
        albedo *= 0.86 + 0.28 * Self.fbm(sx * 9, sy * 9, octaves: 4, seed: 11)

        // Craters tip the surface: a bowl, a raised rim, and fresh ones bright.
        var normal = n
        for c in Self.craters {
            let cosA = Self.dot(n, c.centre)
            let reach = c.radius * 1.7
            guard 1 - cosA < reach * reach / 2 else { continue }
            let t = acos(min(1, cosA)) / c.radius
            let outward = n - c.centre * cosA
            let length = Self.dot(outward, outward).squareRoot()
            guard length > 1e-9 else { continue }
            let rim = 0.18 * exp(-((t - 1) / 0.22) * ((t - 1) / 0.22))
            let slope = 2 * t * Self.smoothstep(1.08, 0.86, t) - 2 * (t - 1) / (0.22 * 0.22) * rim
            normal -= outward / length * slope * c.depth * 0.2
            albedo *= 1 + (c.fresh ? 0.1 : -0.04) * Self.smoothstep(1.05, 0.75, t)
            if c.fresh { albedo += 0.05 * Self.smoothstep(1.7, 1.0, t) }
        }
        // Fine roughness, so the plains are not smooth as plaster.
        let bx = Self.fbm(sx * 40, sy * 40, octaves: 3, seed: 61) - 0.5
        let by = Self.fbm(sx * 40 + 5, sy * 40, octaves: 3, seed: 67) - 0.5
        normal = Self.normalize(normal + V3(bx, by, 0) * 0.35)

        // Lommel–Seeliger for the regolith's flat look, a little Lambert for
        // shape, and earthshine so the night side isn't empty.
        let mu0 = max(0, Self.dot(normal, sun)), mu = max(0.05, normal.z)
        let lit = mu0 / (mu0 + mu) * 1.05 + mu0 * 0.3
        let terminator = Self.smoothstep(-0.05, 0.12, Self.dot(n, sun))
        let b = albedo * lit * terminator + albedo * earthshine
        let warm = Self.mix(V3(0.93, 0.95, 1.0), V3(1.0, 0.96, 0.9), Self.smoothstep(0, 0.5, b))
        var color = warm * b * 0.95
        color = color / (color + 0.85) * 1.7  // a soft shoulder for the highlights
        return (color, cover)
    }

    // MARK: Tonight's moon

    /// From new (0) through full (0.5) and back, for `date`.
    static func phase(at date: Date) -> Double {
        let synodic = 29.530588853 * 86400
        // A new moon: 6 January 2000, 18:14 UTC.
        let age = (date.timeIntervalSince1970 - 947_182_440).truncatingRemainder(dividingBy: synodic)
        return (age < 0 ? age + synodic : age) / synodic
    }

    /// The sun as seen from here at `phase`: behind the moon when new, in
    /// front when full, lighting its right side as it waxes and its left as
    /// it wanes, as from the northern hemisphere.
    static func sun(phase: Double) -> V3 {
        let angle = phase * 2 * .pi
        return normalize(V3(sin(angle), 0.25, -cos(angle)))
    }

    /// Earthshine is brightest when the moon is new and Earth, seen from
    /// it, is nearly full.
    static func earthshine(phase: Double) -> Double {
        0.03 + 0.06 * (1 + cos(phase * 2 * .pi)) / 2
    }

    // MARK: Maths

    static func smoothstep(_ a: Double, _ b: Double, _ x: Double) -> Double {
        let t = min(max((x - a) / (b - a), 0), 1)
        return t * t * (3 - 2 * t)
    }

    private static func mix(_ a: V3, _ b: V3, _ t: Double) -> V3 { a + (b - a) * t }
    private static func mix(_ a: Double, _ b: Double, _ t: Double) -> Double { a + (b - a) * t }
    private static func dot(_ a: V3, _ b: V3) -> Double { (a * b).sum() }
    static func normalize(_ a: V3) -> V3 { a / (a * a).sum().squareRoot() }

    /// Signed distance to a rounded box, negative inside.
    static func distance(_ x: Double, _ y: Double, _ b: Box, radius: Double = 28) -> Double {
        let cx = b.x + b.w / 2, cy = b.y + b.h / 2
        let qx = abs(x - cx) - b.w / 2 + radius, qy = abs(y - cy) - b.h / 2 + radius
        let outside = (max(qx, 0) * max(qx, 0) + max(qy, 0) * max(qy, 0)).squareRoot()
        return outside + min(max(qx, qy), 0) - radius
    }

    private static func rgb(_ hex: UInt32) -> V3 {
        V3(Double(hex >> 16 & 0xFF), Double(hex >> 8 & 0xFF), Double(hex & 0xFF)) / 255
    }

    /// A repeatable random number in 0..<1 for a lattice point.
    static func hash(_ x: Int, _ y: Int, _ seed: Int = 0) -> Double {
        var h = UInt64(bitPattern: Int64(x &* 374_761_393 &+ y &* 668_265_263 &+ seed &* 2_147_483_647))
        h = (h ^ (h >> 29)) &* 0xBF58_476D_1CE4_E5B9
        h = (h ^ (h >> 32)) &* 0x94D0_49BB_1331_11EB
        return Double((h ^ (h >> 31)) >> 11) / Double(1 << 53)
    }

    private static func noise(_ x: Double, _ y: Double, _ seed: Int) -> Double {
        let ix = Int(floor(x)), iy = Int(floor(y))
        let fx = x - floor(x), fy = y - floor(y)
        let ux = fx * fx * (3 - 2 * fx), uy = fy * fy * (3 - 2 * fy)
        let a = hash(ix, iy, seed), b = hash(ix + 1, iy, seed)
        let c = hash(ix, iy + 1, seed), d = hash(ix + 1, iy + 1, seed)
        return mix(mix(a, b, ux), mix(c, d, ux), uy)
    }

    private static func fbm(_ x: Double, _ y: Double, octaves: Int, seed: Int) -> Double {
        var sum = 0.0, amp = 0.5, f = 1.0, norm = 0.0
        for o in 0..<octaves {
            sum += noise(x * f, y * f, seed + o * 17) * amp
            norm += amp
            amp *= 0.5
            f *= 2.03
        }
        return sum / norm
    }
}
