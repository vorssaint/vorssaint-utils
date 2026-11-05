// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import ImageIO

/// Saving a capture as PNG, JPEG or whichever suits the picture.
enum ScreenshotSaveFormatTests {
    typealias Format = ScreenshotSaveFormat

    /// An sRGB image whose pixel (x, y), top row first, is `color(x, y)` as
    /// red, green, blue and alpha.
    static func image(width: Int, height: Int, color: (Int, Int) -> [UInt8]) -> CGImage {
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        for y in 0..<height {
            for x in 0..<width {
                let pixel = color(x, y)
                let alpha = Int(pixel[3])
                let offset = (y * width + x) * 4
                for channel in 0..<3 { bytes[offset + channel] = UInt8(Int(pixel[channel]) * alpha / 255) }
                bytes[offset + 3] = pixel[3]
            }
        }
        let provider = CGDataProvider(data: Data(bytes) as CFData)!
        return CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32,
                       bytesPerRow: width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                       bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                       provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)!
    }

    static func run(_ suite: TestSuite) {
        suite.expect(Format.sanitized(nil) == .png && Format.sanitized("jpeg") == .jpeg
                     && Format.sanitized("automatic") == .automatic && Format.sanitized("webp") == .png,
                     "saving stays PNG unless another format was chosen")

        // A screen of text and controls: white, black ink and one accent.
        let interface = image(width: 64, height: 64) { x, y in
            if (x + y) % 9 == 0 { return [0, 0, 0, 255] }
            return x % 31 == 0 ? [10, 120, 250, 255] : [255, 255, 255, 255]
        }
        // A photo-like picture where nearly every pixel differs.
        let photo = image(width: 64, height: 64) { x, y in
            [UInt8((x * 4 + y) % 256), UInt8((y * 4 + x * 3) % 256), UInt8((x * y) % 256), 255]
        }
        let cutOut = image(width: 64, height: 64) { x, y in
            x == 0 && y == 0 ? [0, 0, 0, 0] : [UInt8((x * 4 + y) % 256), UInt8((y * 4 + x * 3) % 256), UInt8((x * y) % 256), 255]
        }
        let interfaceSample = Format.sample(of: interface)
        let photoSample = Format.sample(of: photo)
        suite.expect(interfaceSample?.pixels == 4096 && interfaceSample?.opaque == true
                     && (interfaceSample?.distinctColors ?? 0) <= 3,
                     "the sample counts the colors a capture really holds")
        suite.expect(Format.automatic.fileType(for: interfaceSample) == .png
                     && Format.automatic.fileType(for: photoSample) == .jpeg
                     && Format.automatic.fileType(for: Format.sample(of: cutOut)) == .png
                     && Format.automatic.fileType(for: nil) == .png,
                     "Automatic keeps text and transparency as PNG and saves photos as JPEG")
        suite.expect(Format.png.fileType(for: photoSample) == .png
                     && Format.jpeg.fileType(for: interfaceSample) == .jpeg,
                     "a chosen format is used as chosen")
        let large = image(width: 1000, height: 10) { x, _ in [UInt8(x % 2 * 255), 0, 0, 255] }
        suite.expect(Format.sample(of: large)?.pixels == 128 * 1,
                     "a large capture is sampled down to a small grid")
        suite.expect(Format.FileType(fileExtension: "JPEG") == .jpeg && Format.FileType(fileExtension: "jpg") == .jpeg
                     && Format.FileType(fileExtension: "png") == .png && Format.FileType.jpeg.fileExtension == "jpg",
                     "the file name and the format follow each other")

        // Whole 16 pixel blocks, so compression keeps the two halves apart.
        let transparent = image(width: 32, height: 16) { x, _ in x < 16 ? [0, 0, 0, 0] : [200, 30, 30, 255] }
        if let data = Format.jpegData(from: transparent, scale: 2),
           let source = CGImageSourceCreateWithData(data as CFData, nil),
           let decoded = CGImageSourceCreateImageAtIndex(source, 0, nil),
           let context = CGContext(data: nil, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                                   space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                   bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue),
           let corner = decoded.cropping(to: CGRect(x: 4, y: 8, width: 1, height: 1)) {
            let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
            let dpi = (properties?[kCGImagePropertyDPIWidth] as? NSNumber)?.doubleValue
            suite.expect(CGImageSourceGetType(source) as String? == "public.jpeg" && dpi == 144,
                         "a JPEG keeps the capture's pixels per point")
            context.draw(corner, in: CGRect(x: 0, y: 0, width: 1, height: 1))
            let bytes = context.data!.assumingMemoryBound(to: UInt8.self)
            suite.expect(bytes[0] > 240 && bytes[1] > 240 && bytes[2] > 240,
                         "a JPEG puts see-through parts on white")
        } else {
            suite.expect(false, "a capture encodes as JPEG")
        }

        suite.expect(Defaults.registeredDefaults[DefaultsKey.screenshotSaveFormat] as? String == ""
                     && SettingsBackupSupport.exportKeys().contains(DefaultsKey.screenshotSaveFormat),
                     "the file format starts at PNG and travels in backups")
        for language in AppLanguage.allCases {
            let strings = FeatureStrings.screenshotFormat(language)
            let values = Mirror(reflecting: strings).children.compactMap { $0.value as? String }
            suite.expect(values.count == 3 && values.allSatisfy { !$0.isEmpty }
                         && values.allSatisfy { !$0.contains("\u{2014}") && !$0.contains("\u{2013}") && !$0.contains("'") },
                         "the file format setting is translated without long dashes or straight apostrophes "
                         + "(\(language.rawValue))")
            suite.expect(strings.saveFormatCaption.contains("PNG") && strings.saveFormatCaption.contains("JPEG"),
                         "the caption names both formats (\(language.rawValue))")
        }
    }
}
