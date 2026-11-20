// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit

/// Portable settings must never grant access to a picture on another Mac;
/// watermark placement must also survive the final capture's rounded mask.
enum ScreenshotWatermarkTests {
    static func run(_ suite: TestSuite) {
        backupChecks(suite)
        determinismChecks(suite)
        renderingChecks(suite)
        for language in AppLanguage.allCases {
            let strings = FeatureStrings.screenshot(language)
            let colors = ScreenshotSupport.ColorID.allCases.map(strings.watermarkColorName)
            let positions = ScreenshotSupport.WatermarkStyle.Anchor.allCases.map(strings.watermarkPositionName)
            suite.expect(Set(colors).count == 8 && colors.allSatisfy { !$0.isEmpty },
                         "watermark colors have distinct names in \(language.rawValue)")
            suite.expect(Set(positions).count == 9 && positions.allSatisfy { !$0.isEmpty },
                         "watermark positions have distinct names in \(language.rawValue)")
        }
    }

    private static func backupChecks(_ suite: TestSuite) {
        typealias Style = ScreenshotSupport.WatermarkStyle
        let local = Style(kind: .image, imagePath: "/local/PRIVATE-LOGO.png", anchor: .topLeading)
        var incoming = local
        incoming.imagePath = "/foreign/UNTRUSTED-LOGO.png"
        incoming.opacity = 0.7
        var text = Style(kind: .text, text: "Portable", color: "blue", rotation: 20)
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
            suite.expect(noLocal.kind == .none && noLocal.imagePath == nil && noLocal.opacity == 0.7,
                         "another Mac restores appearance without selecting a file")
            let sameMac = Style.decoded(SettingsBackupSupport.restoredScreenshotWatermark(
                restored: raw, local: local.encoded()))
            suite.expect(sameMac.kind == .image && sameMac.imagePath == local.imagePath
                         && sameMac.opacity == incoming.opacity,
                         "a restore can use only the picture already chosen on this Mac")
            let presets = ScreenshotSupport.decodedWatermarkPresets(settings[presetsKey] as? String)
            suite.expect(presets.count == 1 && presets[0].text == text.text
                         && presets[0].imagePath == nil && presets[0].rotation == 20,
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

    /// The backup path re-encodes the watermark/backdrop JSON on every export,
    /// so it must be byte-stable across processes. A plain `JSONEncoder()`
    /// orders object keys by a per-process hash, so two runs wrote different
    /// bytes; `.sortedKeys` makes the order alphabetical (and process
    /// independent), which is the property asserted here.
    private static func determinismChecks(_ suite: TestSuite) {
        let watermark = ScreenshotSupport.WatermarkStyle(
            kind: .text, text: "Draft", imagePath: nil, color: "white",
            anchor: .bottomTrailing, size: 0.4, opacity: 0.6, rotation: 12)
        let backdrop = ScreenshotSupport.BackdropStyle(
            kind: .gradient, presetID: nil, colors: [[0.1, 0.2, 0.3], [0.4, 0.5, 0.6]],
            imagePath: nil, padding: 0.5, cornerRadius: 0.2, blur: 0.1)
        let encoders: [(String, String)] = [
            ("watermark style", watermark.encoded()),
            ("backdrop style", backdrop.encoded()),
            ("watermark presets", ScreenshotSupport.encodedWatermarkPresets([watermark])),
            ("backdrop presets", ScreenshotSupport.encodedBackdropPresets([backdrop])),
        ]
        for (name, raw) in encoders {
            let keys = objectKeys(in: raw)
            suite.expect(!keys.isEmpty && keys == keys.sorted(),
                         "\(name) persists JSON keys in alphabetical order")
        }
        let source: [String: Any] = [
            DefaultsKey.screenshotWatermarkStyle: watermark.encoded(),
            DefaultsKey.screenshotWatermarkPresets:
                ScreenshotSupport.encodedWatermarkPresets([watermark]),
        ]
        let first = SettingsBackupSupport.payload(appVersion: "test", valueFor: { source[$0] })
        let second = SettingsBackupSupport.payload(appVersion: "test", valueFor: { source[$0] })
        let firstSettings = first[SettingsBackupSupport.settingsKey] as? [String: Any] ?? [:]
        let secondSettings = second[SettingsBackupSupport.settingsKey] as? [String: Any] ?? [:]
        suite.expect((firstSettings as NSDictionary).isEqual(secondSettings),
                     "two exports of the same settings produce identical values")
    }

    /// Object keys of a JSON string, in file order. Every value fed to this
    /// test is a scalar or an array of scalars, so a quoted key followed by a
    /// colon is unambiguous and string values never match.
    private static func objectKeys(in raw: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: "\"([^\"]+)\":") else { return [] }
        let range = NSRange(raw.startIndex..<raw.endIndex, in: raw)
        return regex.matches(in: raw, range: range).compactMap { match in
            guard match.numberOfRanges > 1, let r = Range(match.range(at: 1), in: raw) else { return nil }
            return String(raw[r])
        }
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
}
