// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation
import ImageIO
import UniformTypeIdentifiers

enum FinderPresentationTools {
    /// Recompresses the ZIP package and JPEG pictures without changing slide
    /// XML, image dimensions, relationships, or non-JPEG embedded content.
    static func compress(_ source: URL, to destination: URL, cancellation: FinderToolsCancellation) throws -> URL {
        try cancellation.check()
        let attributes = try source.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
        guard source.pathExtension.lowercased() == "pptx", attributes.isRegularFile == true,
              let size = attributes.fileSize, size <= FinderPresentationArchive.maximumArchiveBytes else {
            throw FinderFileActionError.unsupported(source, "Choose a PPTX file smaller than 256 MB")
        }
        guard !FileManager.default.fileExists(atPath: destination.path) else {
            throw FinderFileActionError.destinationExists(destination)
        }
        let reader = try FileHandle(forReadingFrom: source)
        defer { try? reader.close() }
        let original = try reader.read(upToCount: FinderPresentationArchive.maximumArchiveBytes + 1) ?? Data()
        let archive = try FinderPresentationArchive(original)
        let output = try archive.rewrite(cancellation: cancellation) { entry in
            let ext = (entry.name as NSString).pathExtension.lowercased()
            guard entry.name.hasPrefix("ppt/media/"), ["jpg", "jpeg"].contains(ext),
                  let image = CGImageSourceCreateWithData(entry.contents as CFData, nil),
                  CGImageSourceGetCount(image) == 1,
                  CGImageSourceGetType(image) as String? == UTType.jpeg.identifier,
                  let properties = CGImageSourceCopyPropertiesAtIndex(image, 0, nil) as? [CFString: Any],
                  let width = properties[kCGImagePropertyPixelWidth] as? Int,
                  let height = properties[kCGImagePropertyPixelHeight] as? Int,
                  width > 0, height > 0, width <= FinderImageTools.maximumDimension,
                  height <= FinderImageTools.maximumDimension, width * height <= FinderImageTools.maximumPixels else {
                return entry.contents
            }
            let compressed = NSMutableData()
            guard let encoder = CGImageDestinationCreateWithData(compressed, UTType.jpeg.identifier as CFString, 1, nil) else {
                return entry.contents
            }
            CGImageDestinationAddImageFromSource(encoder, image, 0,
                [kCGImageDestinationLossyCompressionQuality: 0.8] as CFDictionary)
            guard CGImageDestinationFinalize(encoder), compressed.length < entry.contents.count else { return entry.contents }
            return compressed as Data
        }
        try cancellation.check()
        guard output.count < original.count else {
            throw FinderFileActionError.invalidRequest("This presentation could not be made smaller. No output was created.")
        }
        let staged = try MediaSupport.temporaryOutputURL(for: destination)
        defer { MediaSupport.discardStagedOutput(staged) }
        try output.write(to: staged, options: .withoutOverwriting)
        try cancellation.check()
        try MediaSupport.installStagedOutput(staged, at: destination, replacingExisting: false)
        return destination
    }
}
