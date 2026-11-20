// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import CoreGraphics
import Foundation
import Metal

enum NotchLightsTests {
    static func run(_ suite: TestSuite) {
        defaultsAndBackup(suite)
        rayMath(suite)
        bayerMatrix(suite)
        overlayGeometry(suite)
        uniformMemoryLayout(suite)
        metalShaderCompilation(suite)
        fluidLevelSpring(suite)
        brightnessChangeDetector(suite)
    }

    private static func defaultsAndBackup(_ suite: TestSuite) {
        let keys = [
            DefaultsKey.notchLightsEnabled,
            DefaultsKey.notchHaloStyle,
            DefaultsKey.notchHaloArmWidth,
            DefaultsKey.notchHaloThickness,
            DefaultsKey.notchHaloEntry,
            DefaultsKey.notchHaloMotion,
            DefaultsKey.notchHaloTransition,
            DefaultsKey.notchEdgeWaveEnabled,
            DefaultsKey.notchLightSurfaceStyle,
            DefaultsKey.notchLightsAgentActivity,
            DefaultsKey.notchLightsMusicActivity,
            DefaultsKey.notchLightsCopySweep,
            DefaultsKey.notchLightsNotices,
            DefaultsKey.notchOutlineTheme,
            DefaultsKey.notchLightsRestingOutline,
            DefaultsKey.notchLightsLevelBars
        ]
        suite.expect(keys.allSatisfy { Defaults.registeredDefaults[$0] != nil },
                     "all island light defaults are registered")
        suite.expect(SettingsBackupSupport.exportKeys().isSuperset(of: keys),
                     "all island light keys export cleanly with notch backups")
        suite.expect(NotchOutlineTheme.allCases.count == 8
                        && NotchLevelPrismPalette.volume != NotchLevelPrismPalette.sunlight
                        && NotchLevelPrismPalette.silence != NotchLevelPrismPalette.volume,
                     "outline themes and audio/brightness/silence prism palettes are distinct")
        suite.expect(NotchLightsSupport.clampedThickness(0.1) == 0.6
                        && NotchLightsSupport.clampedThickness(4.5) == 2.0
                        && NotchLightsSupport.clampedThickness(.nan) == 1.0,
                     "thickness clamps strictly to 0.6...2.0 with finite fallback")
        suite.expect(NotchHaloArmWidth.extraWide.points <= NotchLightsSupport.maxArmRun,
                     "extra-wide arm reach stays within 520pt cap")
    }

    private static func rayMath(_ suite: TestSuite) {
        let leftA = NotchLightsSupport.armRays(armRun: 130, thicknessScale: 1.0, intensity: 1.0, sign: -1.0)
        let leftB = NotchLightsSupport.armRays(armRun: 130, thicknessScale: 1.0, intensity: 1.0, sign: -1.0)
        let right = NotchLightsSupport.armRays(armRun: 130, thicknessScale: 1.0, intensity: 1.0, sign: 1.0)
        suite.expect(leftA == leftB, "organic ray generation is deterministic across frames")
        suite.expect((5...34).contains(leftA.count), "ray count per arm stays within 5...34")
        suite.expect(leftA.allSatisfy { $0.xOffset < 0 } && right.allSatisfy { $0.xOffset > 0 },
                     "left and right arm rays preserve horizontal sign symmetry")

        let wideRays = NotchLightsSupport.armRays(armRun: 600, thicknessScale: 2.0, intensity: 1.0, sign: 1.0)
        suite.expect(wideRays.count <= 34 && wideRays.allSatisfy { $0.width >= 2.6 },
                     "wide ray counts cap at 34 and scale linearly with thickness")
    }

    private static func bayerMatrix(_ suite: TestSuite) {
        let matrix = NotchLightsSupport.bayer8x8
        suite.expect(matrix.count == 64 && Set(matrix).count == 64,
                     "8x8 Bayer matrix contains 64 distinct ordered dithering thresholds")
        suite.expect(matrix.min() == 0.0 && matrix.max() == 63.0 / 64.0,
                     "Bayer thresholds normalize cleanly across 0/64...63/64")
    }

    private static func overlayGeometry(_ suite: TestSuite) {
        let screen = CGRect(x: 0, y: 0, width: 1728, height: 1117)
        let notched = NotchGeometry(screen: screen, safeAreaTop: 38, cameraWidth: 185, silhouette: .notch)
        let notchedFrame = NotchLightsSupport.overlayFrame(
            geometry: notched, closedSize: CGSize(width: 240, height: 38), armRun: 130, thicknessScale: 1.0
        )
        suite.expect(abs(notchedFrame.midX - screen.midX) <= 1.0 && notchedFrame.maxY == screen.maxY,
                     "notched overlay hugs the top screen center above the island")

        let capsule = NotchGeometry(screen: screen, safeAreaTop: 0, cameraWidth: 0, silhouette: .capsule)
        let capsuleFrame = NotchLightsSupport.overlayFrame(
            geometry: capsule, closedSize: CGSize(width: 180, height: 26), armRun: 130, thicknessScale: 1.0
        )
        suite.expect(capsuleFrame.width > 180 + 260 && capsuleFrame.height > 26 + 90,
                     "floating capsule overlay allows bloom margins around arms and contour")

        let closedSize = CGSize(width: 240, height: 38)
        let exactAttached = NotchLightsSupport.overlayLayout(
            islandScreenRect: notched.frame(for: closedSize),
            floatingGap: notched.floatingGap,
            armRun: 130,
            thicknessScale: 1.0
        )
        suite.expect(exactAttached.islandRect.minY == 0
                        && exactAttached.islandRect.size == closedSize
                        && abs(exactAttached.islandRect.midX - exactAttached.overlayScreenRect.width / 2) <= 0.5
                        && exactAttached.shoulder == NotchLayout.shoulder(height: closedSize.height),
                     "attached halo overlay maps NotchShape origin and shoulder geometry cleanly")

        let capSize = CGSize(width: 180, height: 24)
        let exactCapsule = NotchLightsSupport.overlayLayout(
            islandScreenRect: capsule.frame(for: capSize),
            floatingGap: capsule.floatingGap,
            armRun: 130,
            thicknessScale: 1.0
        )
        suite.expect(exactCapsule.floatingGap == capsule.floatingGap
                        && exactCapsule.islandRect.minY > 0
                        && exactCapsule.islandRect.size == capSize,
                     "floating capsule halo reserves top bloom room and preserves capsule gap")
    }

    private static func uniformMemoryLayout(_ suite: TestSuite) {
        suite.expect(MemoryLayout<NotchEdgeWaveUniforms>.stride == 80,
                     "EdgeWave Metal uniform struct matches 80-byte 16-byte-aligned layout")
    }

    private static func metalShaderCompilation(_ suite: TestSuite) {
        guard let device = MTLCreateSystemDefaultDevice() else { return }
        do {
            let library = try device.makeLibrary(source: NotchEdgeWaveShaderSource.metalSource, options: nil)
            let vertex = library.makeFunction(name: "edgeWaveVertex")
            let fragment = library.makeFunction(name: "edgeWaveFragment")
            suite.expect(vertex != nil && fragment != nil,
                         "EdgeWave MSL shader compiles at runtime with vertex and fragment entry points")
        } catch {
            suite.expect(false, "EdgeWave MSL runtime compilation failed: \(error)")
        }
    }

    private static func fluidLevelSpring(_ suite: TestSuite) {
        var spring = NotchFluidLevelSpring()
        spring.retarget(to: 0.25, at: 10.0, continuing: false)
        let s0 = spring.sample(at: 10.0)
        suite.expect(abs(s0.value - 0.25) < 0.0001 && s0.energy >= 0.5,
                     "initial level activation lands immediately with non-zero kinetic energy")

        spring.retarget(to: 0.75, at: 10.0, continuing: true)
        let midUp = spring.sample(at: 10.06)
        suite.expect(midUp.value > 0.25 && midUp.value < 0.75 && midUp.velocity > 0,
                     "continuing upward retarget glides smoothly without overshoot")

        // Mid-flight reverse preserves C1 continuous position & velocity.
        spring.retarget(to: 0.20, at: 10.06, continuing: true)
        let revAtSwitch = spring.sample(at: 10.06)
        let revLater = spring.sample(at: 10.14)
        let settled = spring.sample(at: 10.60)
        suite.expect(abs(revAtSwitch.value - midUp.value) < 0.0001
                        && abs(revAtSwitch.velocity - midUp.velocity) < 0.0001
                        && revLater.value < revAtSwitch.value
                        && abs(settled.value - 0.20) < 0.001,
                     "reverse retarget preserves C1 continuity and settles critically onto target")

        let reduced = spring.sample(at: 10.01, reduceMotion: true)
        suite.expect(reduced.value == 0.20 && reduced.velocity == 0 && reduced.energy == 0,
                     "Reduce Motion snaps level immediately without spring energy")
    }

    private static func brightnessChangeDetector(_ suite: TestSuite) {
        var detector = NotchBrightnessChangeDetector()
        suite.expect(detector.observe(level: 0.50, at: 1.0) == nil,
                     "initial brightness sample seeds baseline quietly")
        suite.expect(detector.observe(level: 0.504, at: 2.0) == nil,
                     "small ambient auto-brightness drift outside key window stays ignored")
        suite.expect(detector.observe(level: 0.5625, at: 3.0) == 0.5625,
                     "standard step brightness change triggers feedback")

        // Deduped when BrightnessService already handled the exact adjustment.
        detector.noteHandled(level: 0.625, at: 4.0)
        suite.expect(detector.observe(level: 0.625, at: 4.10) == nil,
                     "recent handled brightness write does not double-fire")

        // Boundary press at 100% / 0% fires once right after a key press.
        detector.noteHandled(level: 1.0, at: 5.0)
        detector.noteKeyPress(at: 5.5)
        suite.expect(detector.observe(level: 1.0, at: 5.6, forceBoundaryOnKey: true) == 1.0,
                     "repeating key at upper boundary reports HUD without stall")
    }
}
