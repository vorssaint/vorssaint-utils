// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit

/// Portable settings must never grant access to a picture on another Mac;
/// watermark placement must also survive the final capture's rounded mask.
enum ScreenshotWatermarkTests {
    static func run(_ suite: TestSuite) {
        layoutChecks(suite)
        backupChecks(suite)
        renderingChecks(suite)
        tilingChecks(suite)
        for language in AppLanguage.allCases {
            let strings = FeatureStrings.screenshot(language)
            let colors = ScreenshotSupport.ColorID.allCases.map(strings.watermarkColorName)
            let positions = ScreenshotSupport.WatermarkStyle.Anchor.allCases.map(strings.watermarkPositionName)
            suite.expect(Set(colors).count == 8 && colors.allSatisfy { !$0.isEmpty },
                         "watermark colors have distinct names in \(language.rawValue)")
            suite.expect(Set(positions).count == 9 && positions.allSatisfy { !$0.isEmpty },
                         "watermark positions have distinct names in \(language.rawValue)")
            suite.expect(!strings.watermarkLayoutLabel.isEmpty
                         && !strings.watermarkLayoutSingle.isEmpty
                         && !strings.watermarkLayoutTiled.isEmpty
                         && strings.watermarkLayoutSingle != strings.watermarkLayoutTiled,
                         "watermark layouts have distinct names in \(language.rawValue)")
        }
    }

    private static func layoutChecks(_ suite: TestSuite) {
        typealias Style = ScreenshotSupport.WatermarkStyle
        let style = Style(kind: .text, text: "Private", anchor: .topLeading,
                          size: 0.2, opacity: 0.3, rotation: 45, layout: .tiled)
        suite.expect(Style.decoded(style.encoded()) == style,
                     "tiled watermark settings round-trip without changing their appearance")
        suite.expect(ScreenshotSupport.decodedWatermarkPresets(
            ScreenshotSupport.encodedWatermarkPresets([style])) == [style],
                     "tiled watermark presets retain their layout")
        var json = try! JSONSerialization.jsonObject(with: Data(style.encoded().utf8)) as! [String: Any]
        var single = style
        single.layout = .single
        for layout in [nil, "future-layout"] as [String?] {
            json["layout"] = layout
            let raw = String(data: try! JSONSerialization.data(withJSONObject: json), encoding: .utf8)!
            suite.expect(Style.decoded(raw) == single,
                         "old or unknown layouts keep the existing single watermark settings")
            suite.expect(ScreenshotSupport.decodedWatermarkPresets("[\(raw)]") == [single],
                         "old or unknown preset layouts preserve the preset")
        }
    }

    private static func backupChecks(_ suite: TestSuite) {
        typealias Style = ScreenshotSupport.WatermarkStyle
        let local = Style(kind: .image, imagePath: "/local/PRIVATE-LOGO.png", anchor: .topLeading)
        var incoming = local
        incoming.imagePath = "/foreign/UNTRUSTED-LOGO.png"
        incoming.opacity = 0.7
        incoming.layout = .tiled
        var text = Style(kind: .text, text: "Portable", color: "blue", rotation: 20, layout: .tiled)
        text.imagePath = incoming.imagePath // Inactive file choices are private too.
        let styleKey = DefaultsKey.screenshotWatermarkStyle
        let presetsKey = DefaultsKey.screenshotWatermarkPresets
        let source: [String: Any] = [styleKey: incoming.encoded(), presetsKey:
            ScreenshotSupport.encodedWatermarkPresets([incoming, text])]
        let payload = SettingsBackupSupport.payload(appVersion: "test", valueFor: { source[$0] })
        let exported = payload[SettingsBackupSupport.settingsKey] as? [String: Any] ?? [:]
        let forged: [String: Any] = [SettingsBackupSupport.formatVersionKey: 1,
                                     SettingsBackupSupport.settingsKey: source]
        let imported = SettingsBackupSupport.sanitizedSettings(from: forged) ?? [:]
        for settings in [exported, imported] {
            suite.expect(!(settings[styleKey] as? String ?? "").contains("UNTRUSTED-LOGO")
                         && !(settings[presetsKey] as? String ?? "").contains("UNTRUSTED-LOGO"),
                         "watermark export and import remove active and inactive picture paths")
            let raw = settings[styleKey] as? String
            let noLocal = Style.decoded(SettingsBackupSupport.restoredScreenshotWatermark(
                restored: raw, local: nil))
            suite.expect(noLocal.kind == .none && noLocal.imagePath == nil && noLocal.opacity == 0.7
                         && noLocal.layout == .tiled,
                         "another Mac restores appearance without selecting a file")
            let sameMac = Style.decoded(SettingsBackupSupport.restoredScreenshotWatermark(
                restored: raw, local: local.encoded()))
            suite.expect(sameMac.kind == .image && sameMac.imagePath == local.imagePath
                         && sameMac.opacity == incoming.opacity && sameMac.layout == .tiled,
                         "a restore can use only the picture already chosen on this Mac")
            let presets = ScreenshotSupport.decodedWatermarkPresets(settings[presetsKey] as? String)
            suite.expect(presets.count == 1 && presets[0].text == text.text
                         && presets[0].imagePath == nil && presets[0].rotation == 20
                         && presets[0].layout == .tiled,
                         "text presets remain portable without hidden picture paths")
        }
        let direct = Style.decoded(SettingsBackupSupport.restoredScreenshotWatermark(
            restored: incoming.encoded(), local: nil))
        suite.expect(direct.kind == .none && direct.imagePath == nil,
                     "the final restoration step also rejects an incoming file path")
        var disabled = local
        disabled.kind = .none
        let restoredOff = Style.decoded(SettingsBackupSupport.restoredScreenshotWatermark(
            restored: disabled.encoded(), local: local.encoded()))
        suite.expect(restoredOff.kind == .none && restoredOff.imagePath == local.imagePath,
                     "an explicit off choice stays off while retaining the local file choice")
        var sequence = Style.decoded(SettingsBackupSupport.restoredScreenshotWatermark(
            restored: text.encoded(), local: restoredOff.encoded()))
        sequence.opacity = 0.2
        sequence = Style.decoded(sequence.encoded())
        suite.expect(sequence.kind == .text && sequence.text == text.text
                     && sequence.imagePath == local.imagePath && sequence.opacity == 0.2,
                     "changing another preference after restore does not lose or replace the local picture")
        sequence.kind = .image
        suite.expect(sequence.sanitized().imagePath == local.imagePath,
                     "switching back to image uses the retained local choice")
        let older = Style.decoded(SettingsBackupSupport.restoredScreenshotWatermark(
            restored: nil, local: local.encoded()))
        suite.expect(older.kind == .none && older.imagePath == local.imagePath,
                     "older backups leave the watermark off without forgetting the local file")
        let localPresets = ScreenshotSupport.encodedWatermarkPresets([local])
        let portableText = (0..<12).map { Style(kind: .text, text: "Mark \($0)") }
        let allIncoming = ScreenshotSupport.encodedWatermarkPresets(portableText)
        let restoredPresets = SettingsBackupSupport.restoredScreenshotWatermarkPresets(
            restored: allIncoming, local: localPresets)
        let presets = ScreenshotSupport.decodedWatermarkPresets(restoredPresets)
        suite.expect(presets.count == 12 && presets.contains(local),
                     "full imported presets cannot evict a local image preset")
        suite.expect(ScreenshotSupport.decodedWatermarkPresets(
            SettingsBackupSupport.restoredScreenshotWatermarkPresets(
                restored: allIncoming, local: restoredPresets)) == presets,
                     "repeated restoration does not duplicate image presets")
        suite.expect(ScreenshotSupport.decodedWatermarkPresets(
            SettingsBackupSupport.restoredScreenshotWatermarkPresets(
                restored: nil, local: localPresets)) == [local],
                     "an older backup preserves local image presets")
        suite.expect(ScreenshotSupport.decodedWatermarkPresets(
            SettingsBackupSupport.restoredScreenshotWatermarkPresets(
                restored: source[presetsKey] as? String, local: nil)).allSatisfy {
                    $0.kind == .text && $0.imagePath == nil
                }, "forged image presets cannot authorize any file")
    }

    private static func bitmap(width: Int, height: Int) -> CGContext {
        CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
                  bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    }

    private static func pixels(_ image: CGImage) -> [UInt8] {
        let context = bitmap(width: image.width, height: image.height)
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        return Array(UnsafeBufferPointer(start: context.data!.assumingMemoryBound(to: UInt8.self),
                                         count: image.width * image.height * 4))
    }

    private static func renderingChecks(_ suite: TestSuite) {
        let side = 200
        let size = CGSize(width: side, height: side)
        let white = bitmap(width: side, height: side)
        white.setFillColor(CGColor(gray: 1, alpha: 1))
        white.fill(CGRect(origin: .zero, size: size))
        let base = white.makeImage()!
        let stamp = bitmap(width: 20, height: 20)
        stamp.setFillColor(CGColor(gray: 0, alpha: 1))
        stamp.fill(CGRect(x: 0, y: 0, width: 20, height: 20))
        let logo = stamp.makeImage()!
        for anchor in ScreenshotSupport.WatermarkStyle.Anchor.allCases {
            for angle in [-45.0, 0, 45] {
                let mark = ScreenshotSupport.WatermarkStyle(kind: .image, imagePath: "/logo.png",
                                                            anchor: anchor, size: 0, opacity: 1,
                                                            rotation: angle)
                let preview = bitmap(width: side, height: side)
                preview.draw(base, in: CGRect(origin: .zero, size: size))
                preview.translateBy(x: 0, y: CGFloat(side))
                preview.scaleBy(x: 1, y: -1)
                let radius = ScreenshotSupport.cardCornerRadius(for: size, factor: 1)
                ScreenshotRenderer.drawWatermark(mark, image: logo, in: preview,
                    imageSize: size, scale: 1, shadowsEnabled: false, cornerRadius: radius)
                let reference = pixels(preview.makeImage()!)
                let exported = ScreenshotRenderer.renderExport(baseImage: base, annotations: [],
                    blurSources: .none, scale: 1, annotationShadowsEnabled: false, watermark: mark,
                    watermarkImage: logo, style: .init(kind: .none, cornerRadius: 1),
                    fill: .none, downscaleTo1x: false)!
                let actual = pixels(exported.image)
                let marked = stride(from: 0, to: reference.count, by: 4).filter { reference[$0] < 250 }
                suite.expect(!marked.isEmpty && marked.allSatisfy {
                    actual[$0 + 3] == 255 && abs(Int(reference[$0]) - Int(actual[$0])) <= 1
                }, "rounded export preserves the entire preview mark at \(anchor), \(angle) degrees")
            }
        }
        let standard = ScreenshotSupport.watermarkPlacement(contentSize: CGSize(width: 50, height: 20),
            rotation: 0, anchor: .topLeading, in: size)!
        suite.expect(standard.center == CGPoint(x: 35, y: 20),
                     "square captures keep the original watermark spacing")
        for side in [1.0, 2, 3, 10, 1000] {
            let tiny = CGSize(width: side, height: side)
            let p = ScreenshotSupport.watermarkPlacement(contentSize: CGSize(width: 2000, height: 100),
                rotation: 45, anchor: .bottomTrailing, in: tiny,
                cornerRadius: ScreenshotSupport.cardCornerRadius(for: tiny, factor: 1))!
            suite.expect(p.fit > 0 && p.fit <= 1 && p.center.x.isFinite && p.center.y.isFinite,
                         "rounded placement stays usable after a crop to \(side) pixels")
        }
    }

    private static func tilingChecks(_ suite: TestSuite) {
        let side = 200
        let size = CGSize(width: side, height: side)
        let white = bitmap(width: side, height: side)
        white.setFillColor(CGColor(gray: 1, alpha: 1))
        white.fill(CGRect(origin: .zero, size: size))
        let base = white.makeImage()!
        let stamp = bitmap(width: 20, height: 20)
        stamp.setFillColor(CGColor(gray: 0, alpha: 1))
        stamp.fill(CGRect(x: 0, y: 0, width: 20, height: 20))
        stamp.setFillColor(CGColor(srgbRed: 0, green: 0, blue: 1, alpha: 1))
        stamp.fill(CGRect(x: 0, y: 10, width: 20, height: 10))
        let logo = stamp.makeImage()!
        for kind in [ScreenshotSupport.WatermarkStyle.Kind.text, .image] {
            for angle in [-90.0, -45, 0, 45, 90] {
                for factor in [0.0, 1] {
                    let radius = ScreenshotSupport.cardCornerRadius(for: size, factor: factor)
                    let mark = ScreenshotSupport.WatermarkStyle(kind: kind, text: "Private",
                        imagePath: "/logo.png", color: "black", size: 0, opacity: 0.35,
                        rotation: angle, layout: .tiled)
                    let preview = bitmap(width: side + 40, height: side + 40)
                    preview.draw(base, in: CGRect(x: 20, y: 20, width: side, height: side))
                    preview.translateBy(x: 20, y: CGFloat(side + 20))
                    preview.scaleBy(x: 1, y: -1)
                    ScreenshotRenderer.drawWatermark(mark, image: logo, in: preview,
                        imageSize: size, scale: 1, shadowsEnabled: false, cornerRadius: radius)
                    let reference = pixels(preview.makeImage()!)
                    let exported = ScreenshotRenderer.renderExport(baseImage: base, annotations: [],
                        blurSources: .none, scale: 1, annotationShadowsEnabled: false,
                        watermark: mark, watermarkImage: logo,
                        style: .init(kind: .none, cornerRadius: factor),
                        fill: .none, downscaleTo1x: false)!
                    let actual = pixels(exported.image)
                    var mismatch: String?
                    var staysInside = true
                    var markedRegions = Set<Int>()
                    for y in 0..<(side + 40) {
                        for x in 0..<(side + 40) {
                            let index = (y * (side + 40) + x) * 4
                            guard (20..<(side + 20)).contains(x), (20..<(side + 20)).contains(y) else {
                                staysInside = staysInside && reference[index + 3] == 0
                                continue
                            }
                            let px = x - 20, py = y - 20
                            let target = (py * side + px) * 4
                            // The export masks the base too; compare its opaque interior separately.
                            if radius > 0 && actual[target + 3] != 255 { continue }
                            let matches = (0..<4).allSatisfy {
                                abs(Int(reference[index + $0]) - Int(actual[target + $0])) <= 1
                            }
                            if !matches && mismatch == nil {
                                mismatch = "\(px),\(py): \(Array(reference[index..<(index + 4)]))"
                                    + " vs \(Array(actual[target..<(target + 4)]))"
                            }
                            if actual[target + 1] < 245 {
                                markedRegions.insert(min(2, py * 3 / side) * 3 + min(2, px * 3 / side))
                            }
                        }
                    }
                    suite.expect(staysInside, "tiled \(kind) at \(angle) degrees stays off the backdrop")
                    suite.expect(mismatch == nil,
                                 "tiled \(kind) at \(angle) degrees matches the exported interior: \(mismatch ?? "")")
                    suite.expect(markedRegions.count == 9,
                                 "tiled \(kind) covers all nine image regions at \(angle) degrees")
                    if radius > 0 {
                        suite.expect(actual[3] == 0, "a tiled watermark preserves rounded transparent corners")
                    }
                    if kind == .image && angle == 0 {
                        func sample(_ x: Int, _ y: Int) -> [UInt8] {
                            let index = (y * side + x) * 4
                            return Array(actual[index..<(index + 4)])
                        }
                        suite.expect(sample(100, 98) == sample(122, 98)
                                     && sample(100, 98) == sample(111, 120)
                                     && sample(100, 98) != sample(100, 102),
                                     "repeated pictures keep their orientation across rows and columns")
                        suite.expect(abs(Int(sample(100, 98)[1]) - 166) <= 1,
                                     "tiled image opacity is applied once")
                    }
                }
            }
        }
        for dimensions in [(1, 1), (2, 3), (32, 12_000), (12_000, 32)] {
            let context = bitmap(width: dimensions.0, height: dimensions.1)
            context.translateBy(x: 0, y: CGFloat(dimensions.1))
            context.scaleBy(x: 1, y: -1)
            let mark = ScreenshotSupport.WatermarkStyle(kind: dimensions.0 < 3 ? .image : .text,
                text: String(repeating: "W", count: 120), imagePath: "/logo.png", color: "black",
                size: 1, opacity: 1, rotation: 45, layout: .tiled)
            ScreenshotRenderer.drawWatermark(mark, image: logo, in: context,
                imageSize: CGSize(width: dimensions.0, height: dimensions.1),
                scale: 1, shadowsEnabled: false)
            let result = pixels(context.makeImage()!)
            suite.expect(stride(from: 3, to: result.count, by: 4).contains { result[$0] > 0 },
                         "tiled marks remain visible on a \(dimensions) canvas")
        }
    }
}
