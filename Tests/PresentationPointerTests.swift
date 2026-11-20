// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit

/// The presentation pointer's decisions and drawing: which switches follow
/// which, how a series of clicks escalates, how hard each tap lands, which
/// display a point belongs to, what each look draws and that the drawn tip
/// always sits on the mouse.
enum PresentationPointerTests {
    static func run(_ suite: TestSuite) {
        mode(suite)
        tapSeries(suite)
        tapExpression(suite)
        tilt(suite)
        screens(suite)
        artwork(suite)
        overlay(suite)
        sounds(suite)
        preferences(suite)
    }

    private static func mode(_ suite: TestSuite) {
        var mode = PresentationPointerMode()
        suite.expect(!mode.isShowing && !mode.blocksClicks, "the pointer starts hidden with clicks passing")

        mode.toggleShowing()
        suite.expect(mode.isShowing && !mode.blocksClicks, "showing the pointer leaves clicks alone")
        mode.toggleShowing()
        suite.expect(mode == PresentationPointerMode(), "hiding the pointer returns to the start")

        mode.toggleBlockingClicks()
        suite.expect(mode.isShowing && mode.blocksClicks,
                     "blocking clicks brings the pointer, so no click disappears unseen")
        mode.toggleBlockingClicks()
        suite.expect(mode.isShowing && !mode.blocksClicks,
                     "letting clicks through again keeps the pointer on screen")

        mode.toggleBlockingClicks()
        mode.toggleShowing()
        suite.expect(!mode.isShowing && !mode.blocksClicks,
                     "hiding the pointer while clicks are blocked lets them through too")

        mode.toggleBlockingClicks()
        mode.reset()
        suite.expect(mode == PresentationPointerMode(), "a reset leaves nothing blocked")
    }

    private static func tapSeries(_ suite: TestSuite) {
        let gap = PresentationPointerTapSeries.continuationInterval
        var series = PresentationPointerTapSeries()
        suite.expect(series.registerPress(at: 100) == 1, "a lone click is the first level")
        let levels = (1...6).map { series.registerPress(at: 100 + Double($0) * gap * 0.5) }
        suite.expect(levels == [2, 3, 4, 5, 5, 5],
                     "quick clicks climb one level each and stop at the top (\(levels))")
        suite.expect(series.registerPress(at: 103.5 + gap * 1.01) == 1,
                     "a pause longer than the window starts over")
        suite.expect(series.registerPress(at: 103.5 + gap * 1.01 + gap * 0.99) == 2,
                     "a click just inside the window continues the series")
        suite.expect(series.registerPress(at: 50) == 1,
                     "a timestamp from before the last click cannot continue a series")
        series.reset()
        suite.expect(series.level == 0 && series.registerPress(at: 50.1) == 1,
                     "a reset forgets the series")
    }

    private static func tapExpression(_ suite: TestSuite) {
        let maximum = PresentationPointerTapSeries.maximumLevel
        for energy in stride(from: 0.0, through: 1.0, by: 0.25) {
            var previous: PresentationPointerTapExpression?
            for level in 1...maximum {
                let expression = PresentationPointerTapExpression.make(level: level, energy: energy)
                suite.expect(expression.pressScale < 1 && expression.pressScale >= 0.6,
                             "a tap always presses in, and never shrinks the pointer away")
                suite.expect((6...12).contains(expression.rayCount), "bursts keep between six and twelve rays")
                suite.expect(expression.soundGain > 0 && expression.soundGain <= 1,
                             "the sound gain stays a fraction of the chosen volume")
                if let previous {
                    suite.expect(expression.pressScale <= previous.pressScale
                                 && expression.burstRadius >= previous.burstRadius
                                 && expression.rayCount >= previous.rayCount
                                 && expression.soundGain >= previous.soundGain,
                                 "level \(level) at energy \(energy) never lands softer than level \(level - 1)")
                }
                previous = expression
            }
        }
        for level in 1...maximum {
            suite.expect(PresentationPointerTapExpression.intensity(level: level, energy: 1)
                         > PresentationPointerTapExpression.intensity(level: level, energy: 0),
                         "more energy taps harder at level \(level)")
        }
        suite.expect(PresentationPointerTapExpression.intensity(level: 1, energy: 0) > 0,
                     "the subtlest tap is still visible")
        suite.expectClose(PresentationPointerTapExpression.intensity(level: maximum, energy: 1), 1,
                          "the boldest tap at the top level")
        suite.expect(PresentationPointerTapExpression.make(level: 0, energy: -3)
                     == PresentationPointerTapExpression.make(level: 1, energy: 0)
                     && PresentationPointerTapExpression.make(level: 99, energy: .infinity)
                     == PresentationPointerTapExpression.make(level: maximum, energy: 0)
                     && PresentationPointerTapExpression.make(level: 99, energy: 7)
                     == PresentationPointerTapExpression.make(level: maximum, energy: 1),
                     "levels and energy outside their ranges are clamped, and a broken energy is the calmest")
    }

    private static func tilt(_ suite: TestSuite) {
        let full = PresentationPointerSupport.maximumTiltDegrees * .pi / 180
        suite.expect(PresentationPointerSupport.tiltRadians(horizontalSpeed: 300) < 0,
                     "moving right leans the top to the right, clockwise")
        suite.expect(PresentationPointerSupport.tiltRadians(horizontalSpeed: -300) > 0,
                     "moving left leans it the other way")
        suite.expectClose(PresentationPointerSupport.tiltRadians(horizontalSpeed: 1_000_000), -full,
                          "a flick never leans past the limit")
        suite.expectClose(PresentationPointerSupport.tiltRadians(horizontalSpeed: 0), 0, "standing still")
        suite.expectClose(PresentationPointerSupport.tiltRadians(horizontalSpeed: .nan), 0,
                          "a broken speed does not lean")
    }

    private static func screens(_ suite: TestSuite) {
        let frames = [CGRect(x: 0, y: 0, width: 1512, height: 982),
                      CGRect(x: 1512, y: -200, width: 2560, height: 1440)]
        suite.expect(PresentationPointerSupport.screenIndex(containing: CGPoint(x: 700, y: 500), in: frames) == 0,
                     "a point on the first display")
        suite.expect(PresentationPointerSupport.screenIndex(containing: CGPoint(x: 1512, y: 500), in: frames) == 1,
                     "the shared edge belongs to the display that starts there")
        suite.expect(PresentationPointerSupport.screenIndex(containing: CGPoint(x: 4072, y: 1240), in: frames) == 1,
                     "the far top corner, outside every half-open frame, goes to the nearest display")
        suite.expect(PresentationPointerSupport.screenIndex(containing: CGPoint(x: 700, y: 982), in: frames) == 0,
                     "the top edge of the first display stays on it")
        suite.expect(PresentationPointerSupport.screenIndex(containing: .zero, in: []) == nil,
                     "no displays, no answer")
    }

    /// The pictures as the repository ships them, read the way the app reads
    /// them from its bundle.
    static let repositoryPicture: PresentationPointerArtwork.PictureLoader = { style in
        guard let name = style.pictureResource,
              let source = CGImageSourceCreateWithURL(
                  URL(fileURLWithPath: "Resources/Images/\(name).png") as CFURL, nil)
        else { return nil }
        return CGImageSourceCreateImageAtIndex(source, 0, nil)
    }

    /// Every look draws at every size, clicks where it is drawn, and points
    /// the way a pointer does; every picture ships with its licence.
    private static func artwork(_ suite: TestSuite) {
        let license = (try? String(contentsOfFile: "Resources/Images/presentation-pointer-pictures-LICENSE.txt",
                                   encoding: .utf8)) ?? ""
        suite.expect(license.contains("MIT License") && license.contains("Copyright (c) Microsoft Corporation"),
                     "the pictures ship with their MIT licence and copyright notice")
        for style in PresentationPointerStyle.allCases {
            guard let name = style.pictureResource, let tip = style.pictureTip else {
                suite.expect(style == .ring, "\(style) has a picture and the point it clicks with")
                continue
            }
            suite.expect(license.contains("\(name).png"), "the licence file names \(name).png")
            guard let source = repositoryPicture(style) else {
                suite.expect(false, "Resources/Images/\(name).png is there to bundle")
                continue
            }
            suite.expect(CGFloat(source.width) == PresentationPointerSupport.picturePixels
                         && CGFloat(source.height) == PresentationPointerSupport.picturePixels,
                         "\(name).png is the square the tips are measured in")
            suite.expect(Pixels(source).alpha(at: tip) >= 128, "\(style)'s tip is on the picture itself")
            suite.expect(tip.x < PresentationPointerSupport.picturePixels / 2
                         && tip.y < PresentationPointerSupport.picturePixels / 2,
                         "\(style) points up and to the left, like a pointer")
        }

        let colors: [NSColor] = [.white, NSColor(srgbRed: 1, green: 0.77, blue: 0, alpha: 1),
                                 NSColor(srgbRed: 0.1, green: 0.1, blue: 0.12, alpha: 1)]
        let sizes = [PresentationPointerSupport.sizeRange.lowerBound, PresentationPointerSupport.defaultSize,
                     PresentationPointerSupport.sizeRange.upperBound]
        for style in PresentationPointerStyle.allCases {
            var previousWidth: CGFloat = 0
            for size in sizes {
                for scale: CGFloat in [1, 2] {
                    for color in colors {
                        let label = "\(style) at \(size) points, \(scale)x"
                        guard let art = PresentationPointerArtwork.make(style: style, color: color,
                                                                        pointerSize: CGFloat(size), scale: scale,
                                                                        picture: repositoryPicture)
                        else {
                            suite.expect(false, "\(label) draws")
                            continue
                        }
                        suite.expect(art.image.width == Int((art.size.width * scale).rounded(.up))
                                     && art.image.height == Int((art.size.height * scale).rounded(.up)),
                                     "\(label): the image has the pixels its size promises")
                        suite.expect(CGRect(origin: .zero, size: art.size).contains(art.hotSpot),
                                     "\(label): the click point is inside the image")
                        let pixels = Pixels(art.image)
                        let tip = CGPoint(x: art.hotSpot.x * scale, y: art.hotSpot.y * scale)
                        let reach = max(2, 2.5 * scale)
                        if style == .ring {
                            suite.expect(pixels.alpha(at: tip) == 0,
                                         "\(label): the ring leaves the system pointer visible in its middle")
                            suite.expect(pixels.maxAlpha(near: CGPoint(x: tip.x, y: tip.y - CGFloat(size) * 0.42 * scale),
                                                         radius: reach) > 200,
                                         "\(label): the ring itself is drawn around the middle")
                        } else {
                            suite.expect(pixels.maxAlpha(near: tip, radius: reach) > 100,
                                         "\(label): the click lands on the drawn tip")
                        }
                    }
                }
                if let art = PresentationPointerArtwork.make(style: style, color: .white,
                                                             pointerSize: CGFloat(size), scale: 1,
                                                             picture: repositoryPicture) {
                    suite.expect(art.size.width > previousWidth, "\(style) grows with the size setting")
                    previousWidth = art.size.width
                }
            }
        }
        suite.expect(PresentationPointerArtwork.make(style: .hand, color: .white, pointerSize: 44, scale: 2,
                                                     picture: { _ in nil }) == nil,
                     "a picture that cannot be read draws nothing rather than an empty pointer")
        suite.expect(PresentationPointerArtwork.make(style: .ring, color: .white, pointerSize: 0, scale: 2) == nil
                     && PresentationPointerArtwork.make(style: .ring, color: .white, pointerSize: 44, scale: 0) == nil,
                     "an empty size or scale draws nothing rather than a broken image")
        func inkBrightness(for color: NSColor) -> CGFloat {
            PresentationPointerArtwork.outline(for: color).usingColorSpace(.sRGB)?.brightnessComponent ?? -1
        }
        suite.expect(inkBrightness(for: .white) < 0.3
                     && inkBrightness(for: NSColor(srgbRed: 0.05, green: 0.05, blue: 0.08, alpha: 1)) > 0.8,
                     "light colors are inked dark and very dark ones light, so the ring keeps its outline")
        suite.expect(inkBrightness(for: NSColor(srgbRed: 1, green: 0.84, blue: 0.04, alpha: 1)) < 0.3,
                     "a yellow ring keeps a dark outline")
        suite.expect(inkBrightness(for: NSColor(white: 0.5, alpha: 1)) >= 0,
                     "a gray picked in another color space still gets an ink")
        suite.expectClose(Double(PresentationPointerSupport.relativeLuminance(red: 1, green: 1, blue: 1)), 1,
                          "white is fully luminous")
        suite.expectClose(Double(PresentationPointerSupport.relativeLuminance(red: 0, green: 0, blue: 0)), 0,
                          "black has no luminance")
    }

    /// The drawing surface keeps the drawn tip on the mouse, on any display,
    /// whatever the pointer is doing.
    private static func overlay(_ suite: TestSuite) {
        let frame = CGRect(x: 1512, y: -200, width: 2560, height: 1440)
        let overlay = PresentationPointerOverlay(frame: frame, displayID: 2)
        suite.expect(overlay.drawnTip == nil, "nothing is drawn before a pointer is placed")
        for style in PresentationPointerStyle.allCases {
            guard let art = PresentationPointerArtwork.make(style: style, color: .white, pointerSize: 64, scale: 2,
                                                            picture: repositoryPicture)
            else {
                suite.expect(false, "\(style) draws on the overlay")
                continue
            }
            overlay.apply(art)
            for point in [CGPoint(x: 1512, y: -200), CGPoint(x: 2800.5, y: 610.25), CGPoint(x: 4071, y: 1239)] {
                overlay.movePointer(to: point)
                suite.expect(overlay.drawnTip.map { hypot($0.x - point.x, $0.y - point.y) < 0.01 } == true,
                             "\(style): the drawn tip sits on the mouse at \(point) (\(String(describing: overlay.drawnTip)))")
            }
            let point = CGPoint(x: 3000, y: 400)
            overlay.movePointer(to: point)
            overlay.setTilt(0.2, animated: false)
            suite.expect(overlay.drawnTip.map { hypot($0.x - point.x, $0.y - point.y) < 0.01 } == true,
                         "\(style): leaning turns the pointer about its tip, which stays on the mouse")
            overlay.setTilt(0, animated: false)
        }
        let expression = PresentationPointerTapExpression.make(level: 5, energy: 1)
        overlay.press(expression, reduceMotion: false)
        overlay.burst(at: CGPoint(x: 3000, y: 400), expression, reduceMotion: false)
        overlay.release(reduceMotion: false)
        overlay.press(expression, reduceMotion: true)
        overlay.release(reduceMotion: true)
        overlay.fadeIn(reduceMotion: false)
        overlay.movePointer(to: CGPoint(x: 3000, y: 400))
        overlay.setSuppressed(true)
        suite.expect(overlay.drawnTip == nil,
                     "while macOS shows its own pointer, the picture steps aside so only one shows")
        overlay.setSuppressed(false)
        suite.expect(overlay.drawnTip.map { hypot($0.x - 3000, $0.y - 400) < 0.01 } == true,
                     "once the system pointer hides again, the picture is back on the mouse")
        overlay.hidePointer()
        suite.expect(overlay.drawnTip == nil, "a hidden pointer has no tip on screen")
        overlay.update(frame: CGRect(x: 0, y: 0, width: 1512, height: 982))
        overlay.movePointer(to: CGPoint(x: 10, y: 20))
        suite.expect(overlay.drawnTip.map { hypot($0.x - 10, $0.y - 20) < 0.01 } == true,
                     "after the display moves, the tip follows the new frame")
        overlay.close()
    }

    /// The pointer's own tap sounds: clean at both ends, never clipping,
    /// higher at each level, the same every time, and valid as a file.
    private static func sounds(_ suite: TestSuite) {
        let rate = Double(PresentationPointerTapSound.sampleRate)
        for sound in PresentationPointerTapSound.allCases {
            var previousCrossings = 0
            for level in 1...PresentationPointerTapSeries.maximumLevel {
                let samples = sound.samples(level: level)
                let label = "\(sound) at level \(level)"
                suite.expect(samples.count == Int(sound.duration * rate) && sound.duration <= 0.25,
                             "\(label) is a short tap")
                let peak = samples.reduce(0) { max($0, abs($1)) }
                suite.expect(peak > 0.8 && peak <= 0.851, "\(label) is loud enough and never clips (\(peak))")
                suite.expect(abs(samples.first ?? 1) < 0.01 && abs(samples.last ?? 1) < 0.01,
                             "\(label) starts and ends in silence, so it never clicks")
                suite.expect(samples == sound.samples(level: level), "\(label) sounds the same every time")
                // Zero crossings of the tone, after the opening click, rise
                // with the pitch.
                let window = samples[Int(0.005 * rate)..<Int(min(0.03, sound.duration) * rate)]
                let crossings = zip(window, window.dropFirst()).filter { ($0 < 0) != ($1 < 0) }.count
                suite.expect(crossings >= previousCrossings, "\(label) is no lower than the level before")
                previousCrossings = crossings
            }
            suite.expect(PresentationPointerTapSound(storageValue: sound.storageValue) == sound,
                         "\(sound) is found again from what is saved")
        }
        suite.expect(PresentationPointerTapSound(storageValue: "Pop") == nil
                     && PresentationPointerTapSound(storageValue: nil) == nil,
                     "a system sound's name is never taken for one of the pointer's own")

        let samples: [Float] = [0, 0.5, -0.5, 1.5, -1.5]
        let wav = PresentationPointerTapSound.wavData(samples)
        func word(_ offset: Int) -> UInt32 { wav.subdata(in: offset..<offset + 4).withUnsafeBytes { $0.load(as: UInt32.self) } }
        suite.expect(wav.count == 44 + samples.count * 2
                     && String(decoding: wav.prefix(4), as: UTF8.self) == "RIFF"
                     && String(decoding: wav.subdata(in: 8..<16), as: UTF8.self) == "WAVEfmt "
                     && word(4) == UInt32(36 + samples.count * 2)
                     && word(24) == UInt32(PresentationPointerTapSound.sampleRate)
                     && word(40) == UInt32(samples.count * 2),
                     "the tap is a well-formed 16-bit mono WAV file")
        let last = wav.suffix(2).withUnsafeBytes { $0.load(as: Int16.self) }
        suite.expect(last == -Int16.max, "samples beyond full scale are clamped, not wrapped")

        let system = ["Glass", "Pop", "Tink"]
        suite.expect(PresentationPointerSoundChoice.resolve(stored: "builtin.knock", systemNames: system)
                     == .builtIn(.knock)
                     && PresentationPointerSoundChoice.resolve(stored: "Pop", systemNames: system) == .system("Pop")
                     && PresentationPointerSoundChoice.resolve(stored: "custom", systemNames: system) == .custom,
                     "a saved sound name finds the pointer's own, the Mac's, or the person's file")
        suite.expect(PresentationPointerSoundChoice.resolve(stored: "Funky Retired Sound", systemNames: system)
                     == .builtIn(.drum)
                     && PresentationPointerSoundChoice.resolve(stored: nil, systemNames: system) == .builtIn(.drum),
                     "a sound this Mac does not have plays the default sound rather than nothing")
        suite.expect(PresentationPointerSupport.defaultSoundName == PresentationPointerTapSound.drum.storageValue,
                     "the default sound is the pointer's own drum")
    }

    /// Reads a drawn image's alpha, rows from the top.
    private struct Pixels {
        let width: Int
        let height: Int
        let bytes: [UInt8]

        init(_ image: CGImage) {
            width = image.width
            height = image.height
            var bytes = [UInt8](repeating: 0, count: width * height * 4)
            let (width, height) = (width, height)
            bytes.withUnsafeMutableBytes { buffer in
                CGContext(data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8,
                          bytesPerRow: width * 4,
                          space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)?
                    .draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            }
            self.bytes = bytes
        }

        func alpha(at point: CGPoint) -> UInt8 {
            let x = Int(point.x.rounded(.down))
            let y = Int(point.y.rounded(.down))
            guard x >= 0, y >= 0, x < width, y < height else { return 0 }
            return bytes[(y * width + x) * 4 + 3]
        }

        func maxAlpha(near point: CGPoint, radius: CGFloat) -> UInt8 {
            var best: UInt8 = 0
            let steps = Int(radius.rounded(.up))
            for dy in -steps...steps {
                for dx in -steps...steps where CGFloat(dx * dx + dy * dy) <= radius * radius {
                    best = max(best, alpha(at: CGPoint(x: point.x + CGFloat(dx), y: point.y + CGFloat(dy))))
                }
            }
            return best
        }
    }

    private static func preferences(_ suite: TestSuite) {
        suite.expect(PresentationPointerSupport.style(stored: nil) == .hand
                     && PresentationPointerSupport.style(stored: "laser") == .hand
                     && PresentationPointerSupport.style(stored: "ring") == .ring,
                     "an unknown or missing style falls back to the hand")
        suite.expect(PresentationPointerStyle.allCases.filter(\.replacesSystemPointer)
                     == [.hand, .wand, .pencil, .banana],
                     "every picture replaces the system pointer, and only the ring circles it")
        let range = PresentationPointerSupport.sizeRange
        suite.expect(PresentationPointerSupport.sanitizedSize(1) == range.lowerBound
                     && PresentationPointerSupport.sanitizedSize(1000) == range.upperBound
                     && PresentationPointerSupport.sanitizedSize(.nan) == PresentationPointerSupport.defaultSize
                     && PresentationPointerSupport.sanitizedSize(50) == 50,
                     "sizes stay within the slider's range")
        suite.expect(range.contains(PresentationPointerSupport.defaultSize), "the default size is on the slider")

        let registered = Defaults.registeredDefaults
        for key in [DefaultsKey.presentationPointerStyle, DefaultsKey.presentationPointerColor,
                    DefaultsKey.presentationPointerSize, DefaultsKey.presentationPointerEnergy,
                    DefaultsKey.presentationPointerBursts, DefaultsKey.presentationPointerSoundEnabled,
                    DefaultsKey.presentationPointerSoundName, DefaultsKey.presentationPointerSoundVolume,
                    DefaultsKey.presentationPointerShortcutEnabled, DefaultsKey.presentationPointerShortcut,
                    DefaultsKey.presentationPointerBlockClicksShortcutEnabled,
                    DefaultsKey.presentationPointerBlockClicksShortcut] {
            suite.expect(registered[key] != nil && SettingsBackupSupport.exportKeys().contains(key),
                         "\(key) has a default and travels with a settings backup")
        }
        suite.expect(SettingsBackupSupport.machineStateKeys.contains(DefaultsKey.presentationPointerCustomSoundPath)
                     && !SettingsBackupSupport.exportKeys().contains(DefaultsKey.presentationPointerCustomSoundPath),
                     "a sound file's path belongs to one Mac and stays out of backups")
        suite.expect(registered[DefaultsKey.presentationPointerSoundEnabled] as? Bool == false,
                     "taps are silent until sound is chosen")


        PresentationPointerClickBlock.set(true)
        let blocking = PresentationPointerClickBlock.isActive
        PresentationPointerClickBlock.set(false)
        suite.expect(blocking && !PresentationPointerClickBlock.isActive,
                     "the input taps can read whether clicks are blocked, and see it end")

        let feature = AppFeature.presentationPointer
        suite.expect(feature.permissions.isEmpty && !feature.installedByDefault && feature.group == .mouseKeyboard,
                     "the pointer is an opt-in mouse feature that asks for no permission")
        suite.expect(GlobalShortcutRole.presentationPointer.feature == feature
                     && GlobalShortcutRole.presentationPointerBlockClicks.feature == feature,
                     "both shortcuts follow the feature's availability")
        suite.expect(GlobalShortcutRole.presentationPointer.defaultShortcut
                     != GlobalShortcutRole.presentationPointerBlockClicks.defaultShortcut,
                     "showing the pointer and blocking clicks start on different keys")
    }
}
