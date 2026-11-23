// SPDX-License-Identifier: GPL-3.0-only
// Adapted from Open Tangerine (c) 2026 Sintax Error Private Limited, GPL-3.0-only,
// itself substantially based on Satsuma (c) 2026 plyght, MIT. See NOTICE.

import AVFoundation
import Foundation
import ImageIO
import PDFKit
import UniformTypeIdentifiers

struct MetadataField: Identifiable, Hashable {
    let id: String
    let group: String
    let key: String
    var value: String
    let editable: Bool
    let sensitive: Bool
}

enum MetadataOps {
    static let sensitiveGroups: Set<String> = ["GPS", "Exif", "MakerApple", "TIFF", "IPTC", "XMP"]

    static func read(_ url: URL) async -> [MetadataField] {
        guard let format = FileFormat.detect(url) else { return [] }
        switch format.category {
        case .image: return readImage(url)
        case .audio, .video: return await readAV(url)
        case .document where format == .pdf: return readPDF(url)
        default: return fileFields(url)
        }
    }

    static func fileFields(_ url: URL) -> [MetadataField] {
        var fields: [MetadataField] = []
        let attrs = try? FileManager.default.attributesOfItem(atPath: url.path)
        fields.append(MetadataField(id: "file.name", group: "File", key: "Name", value: url.lastPathComponent, editable: false, sensitive: false))
        if let size = attrs?[.size] as? Int64 {
            fields.append(MetadataField(id: "file.size", group: "File", key: "Size", value: FileSizeFormatter.string(size), editable: false, sensitive: false))
        }
        if let created = attrs?[.creationDate] as? Date {
            fields.append(MetadataField(id: "file.created", group: "File", key: "Created", value: created.formatted(), editable: false, sensitive: false))
        }
        if let modified = attrs?[.modificationDate] as? Date {
            fields.append(MetadataField(id: "file.modified", group: "File", key: "Modified", value: modified.formatted(), editable: false, sensitive: false))
        }
        return fields
    }

    static func readImage(_ url: URL) -> [MetadataField] {
        var fields = fileFields(url)
        let props = ImageIOBridge.properties(url)
        for (key, value) in props {
            let name = key as String
            if let dictionary = value as? [CFString: Any] {
                let group = name.replacingOccurrences(of: "{", with: "").replacingOccurrences(of: "}", with: "")
                for (subKey, subValue) in dictionary {
                    let sub = subKey as String
                    fields.append(MetadataField(id: "\(group).\(sub)", group: group, key: sub, value: describe(subValue), editable: isEditableImageKey(group: group, key: sub), sensitive: sensitiveGroups.contains(group)))
                }
            } else {
                fields.append(MetadataField(id: "Image.\(name)", group: "Image", key: name, value: describe(value), editable: false, sensitive: false))
            }
        }
        return fields.sorted { ($0.group, $0.key) < ($1.group, $1.key) }
    }

    private static func isEditableImageKey(group: String, key: String) -> Bool {
        let editable: Set<String> = ["Artist", "Copyright", "ImageDescription", "Software", "Make", "Model", "UserComment", "DateTimeOriginal", "DateTimeDigitized", "DateTime", "LensModel", "Keywords", "Caption/Abstract", "Byline", "CopyrightNotice", "ObjectName", "City", "Country/PrimaryLocationName"]
        return editable.contains(key)
    }

    static func readAV(_ url: URL) async -> [MetadataField] {
        var fields = fileFields(url)
        let asset = AVURLAsset(url: url)
        let info = await MediaInfo.load(url)
        if info.duration > 0 { fields.append(MetadataField(id: "media.duration", group: "Media", key: "Duration", value: TimeFormatter.clock(info.duration), editable: false, sensitive: false)) }
        if info.hasVideo { fields.append(MetadataField(id: "media.size", group: "Media", key: "Dimensions", value: "\(Int(info.naturalSize.width)) × \(Int(info.naturalSize.height))", editable: false, sensitive: false)) }
        if info.frameRate > 0 { fields.append(MetadataField(id: "media.fps", group: "Media", key: "Frame rate", value: String(format: "%.2f fps", locale: .current, info.frameRate), editable: false, sensitive: false)) }
        if info.channelCount > 0 { fields.append(MetadataField(id: "media.channels", group: "Media", key: "Channels", value: "\(info.channelCount)", editable: false, sensitive: false)) }
        if info.sampleRate > 0 { fields.append(MetadataField(id: "media.rate", group: "Media", key: "Sample rate", value: "\(Int(info.sampleRate)) Hz", editable: false, sensitive: false)) }
        let items = (try? await asset.load(.metadata)) ?? []
        let common = (try? await asset.load(.commonMetadata)) ?? []
        for item in common + items {
            guard let key = item.commonKey?.rawValue ?? (item.key.map { "\($0)" }) else { continue }
            var value = (try? await item.load(.stringValue)) ?? ""
            if value.isEmpty, let raw = try? await item.load(.value) { value = "\(raw)" }
            guard !value.isEmpty else { continue }
            let id = "av.\(item.keySpace?.rawValue ?? "common").\(key)"
            if fields.contains(where: { $0.id == id }) { continue }
            fields.append(MetadataField(id: id, group: "Tags", key: key.replacingOccurrences(of: "©", with: ""), value: value, editable: item.commonKey != nil, sensitive: key.lowercased().contains("location")))
        }
        if let ffmpegFields = await readWithFFprobe(url), !ffmpegFields.isEmpty {
            for field in ffmpegFields where !fields.contains(where: { $0.key.lowercased() == field.key.lowercased() && $0.group == field.group }) {
                fields.append(field)
            }
        }
        return fields
    }

    private static func readWithFFprobe(_ url: URL) async -> [MetadataField]? {
        guard let probe = FFmpeg.probePath else { return nil }
        guard let result = try? await ConvertShell.run(probe, ["-v", "error", "-show_entries", "format_tags:stream_tags:chapters", "-of", "json", url.path]), result.succeeded,
              let data = result.stdout.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        var fields: [MetadataField] = []
        if let format = object["format"] as? [String: Any], let tags = format["tags"] as? [String: Any] {
            for (key, value) in tags {
                fields.append(MetadataField(id: "ff.format.\(key)", group: "Tags", key: key, value: describe(value), editable: true, sensitive: key.lowercased().contains("location")))
            }
        }
        if let streams = object["streams"] as? [[String: Any]] {
            for (index, stream) in streams.enumerated() {
                guard let tags = stream["tags"] as? [String: Any] else { continue }
                for (key, value) in tags {
                    fields.append(MetadataField(id: "ff.stream\(index).\(key)", group: "Track \(index + 1)", key: key, value: describe(value), editable: false, sensitive: false))
                }
            }
        }
        if let chapters = object["chapters"] as? [[String: Any]] {
            for (index, chapter) in chapters.enumerated() {
                let title = ((chapter["tags"] as? [String: Any])?["title"] as? String) ?? "Chapter \(index + 1)"
                let start = chapter["start_time"] as? String ?? ""
                fields.append(MetadataField(id: "ff.chapter\(index)", group: "Chapters", key: title, value: start, editable: false, sensitive: false))
            }
        }
        return fields
    }

    static func readPDF(_ url: URL) -> [MetadataField] {
        var fields = fileFields(url)
        guard let document = PDFDocument(url: url) else { return fields }
        fields.append(MetadataField(id: "pdf.pages", group: "Document", key: "Pages", value: "\(document.pageCount)", editable: false, sensitive: false))
        for (key, value) in document.documentAttributes ?? [:] {
            let name = (key.base as? PDFDocumentAttribute)?.rawValue ?? "\(key)"
            fields.append(MetadataField(id: "pdf.\(name)", group: "Document", key: name, value: describe(value), editable: true, sensitive: name == "Author" || name == "Creator" || name == "Producer"))
        }
        return fields
    }

    static func describe(_ value: Any) -> String {
        if let string = value as? String { return string }
        if let number = value as? NSNumber { return number.stringValue }
        if let date = value as? Date { return date.formatted() }
        if let array = value as? [Any] { return array.map(describe).joined(separator: ", ") }
        if let dictionary = value as? [AnyHashable: Any] { return dictionary.map { "\($0.key)=\(describe($0.value))" }.sorted().joined(separator: "; ") }
        return "\(value)"
    }

    static func write(_ url: URL, edits: [MetadataField], removeAll: Bool, removeSensitive: Bool, to destination: URL, progress: @escaping (Double) -> Void) async throws {
        guard let format = FileFormat.detect(url) else { throw OpenTangerineError.unreadable(url) }
        switch format.category {
        case .image:
            try writeImage(url, edits: edits, removeAll: removeAll, removeSensitive: removeSensitive, to: destination)
        case .audio, .video:
            try await writeAV(url, format: format, edits: edits, removeAll: removeAll || removeSensitive, to: destination, progress: progress)
        case .document where format == .pdf:
            try writePDF(url, edits: edits, removeAll: removeAll, removeSensitive: removeSensitive, to: destination)
        default:
            throw OpenTangerineError.invalidInput("Metadata editing is not supported for \(format.displayName).")
        }
        progress(1)
    }

    private static func writeImage(_ url: URL, edits: [MetadataField], removeAll: Bool, removeSensitive: Bool, to destination: URL) throws {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil), let type = CGImageSourceGetType(source) else { throw OpenTangerineError.unreadable(url) }
        let count = CGImageSourceGetCount(source)
        let outputType: CFString = ImageIOBridge.nativeEncoders.contains(type as String) ? type : (UTType.png.identifier as CFString)
        guard let dest = CGImageDestinationCreateWithURL(destination as CFURL, outputType, count, nil) else { throw OpenTangerineError.encodeFailed(destination.lastPathComponent) }
        for index in 0..<count {
            var props = (CGImageSourceCopyPropertiesAtIndex(source, index, nil) as? [CFString: Any]) ?? [:]
            if removeAll {
                let keep: Set<CFString> = [kCGImagePropertyOrientation, kCGImagePropertyDPIWidth, kCGImagePropertyDPIHeight, kCGImagePropertyPixelWidth, kCGImagePropertyPixelHeight, kCGImagePropertyColorModel, kCGImagePropertyHasAlpha, kCGImagePropertyDepth, kCGImagePropertyProfileName]
                props = props.filter { keep.contains($0.key) }
                props[kCGImagePropertyExifDictionary] = kCFNull
                props[kCGImagePropertyGPSDictionary] = kCFNull
                props[kCGImagePropertyIPTCDictionary] = kCFNull
                props[kCGImagePropertyTIFFDictionary] = kCFNull
                props[kCGImagePropertyMakerAppleDictionary] = kCFNull
                props[kCGImagePropertyExifAuxDictionary] = kCFNull
            } else {
                if removeSensitive {
                    props[kCGImagePropertyIPTCDictionary] = kCFNull
                    props[kCGImagePropertyGPSDictionary] = kCFNull
                    props[kCGImagePropertyMakerAppleDictionary] = kCFNull
                    props[kCGImagePropertyExifAuxDictionary] = kCFNull
                    if var exif = props[kCGImagePropertyExifDictionary] as? [CFString: Any] {
                        for key in [kCGImagePropertyExifUserComment, kCGImagePropertyExifSubjectLocation, kCGImagePropertyExifLensModel, kCGImagePropertyExifLensMake, kCGImagePropertyExifBodySerialNumber, kCGImagePropertyExifLensSerialNumber, kCGImagePropertyExifCameraOwnerName] {
                            exif[key] = kCFNull
                        }
                        props[kCGImagePropertyExifDictionary] = exif
                    }
                    if var tiff = props[kCGImagePropertyTIFFDictionary] as? [CFString: Any] {
                        for key in [kCGImagePropertyTIFFMake, kCGImagePropertyTIFFModel, kCGImagePropertyTIFFSoftware, kCGImagePropertyTIFFArtist, kCGImagePropertyTIFFHostComputer] {
                            tiff[key] = kCFNull
                        }
                        props[kCGImagePropertyTIFFDictionary] = tiff
                    }
                }
                for edit in edits where edit.editable && !(removeSensitive && edit.sensitive) {
                    let groupKey = groupDictionaryKey(edit.group)
                    guard let groupKey else { continue }
                    var dict = (props[groupKey] as? [CFString: Any]) ?? [:]
                    if edit.value.isEmpty {
                        dict[edit.key as CFString] = kCFNull
                    } else {
                        dict[edit.key as CFString] = edit.value
                    }
                    props[groupKey] = dict
                }
            }
            var options = props
            options[kCGImageDestinationMetadata] = kCFNull
            if removeAll { options[kCGImageDestinationMergeMetadata] = false }
            CGImageDestinationAddImageFromSource(dest, source, index, options as CFDictionary)
        }
        guard CGImageDestinationFinalize(dest) else { throw OpenTangerineError.encodeFailed(destination.lastPathComponent) }
    }

    private static func groupDictionaryKey(_ group: String) -> CFString? {
        switch group {
        case "Exif": return kCGImagePropertyExifDictionary
        case "TIFF": return kCGImagePropertyTIFFDictionary
        case "IPTC": return kCGImagePropertyIPTCDictionary
        case "GPS": return kCGImagePropertyGPSDictionary
        case "PNG": return kCGImagePropertyPNGDictionary
        default: return nil
        }
    }

    private static func writeAV(_ url: URL, format: FileFormat, edits: [MetadataField], removeAll: Bool, to destination: URL, progress: @escaping (Double) -> Void) async throws {
        let nativeTarget = VideoEngine.nativeTargets.contains(format) || format == .m4a
        if nativeTarget, await MediaInfo.isNativelyReadable(url) {
            var items: [AVMetadataItem] = []
            if !removeAll {
                for edit in edits where edit.editable && edit.id.hasPrefix("av.") {
                    let key = edit.id.components(separatedBy: ".").last ?? ""
                    let commonKey = AVMetadataKey(rawValue: key)
                    let item = AVMutableMetadataItem()
                    item.keySpace = .common
                    item.key = commonKey.rawValue as NSString
                    item.value = edit.value as NSString
                    items.append(item)
                }
            }
            try await AVExporter.export(asset: AVURLAsset(url: url), to: destination, format: format, preset: AVAssetExportPresetPassthrough, metadata: items, progress: progress)
            return
        }
        var args = ["-i", url.path, "-map", "0", "-c", "copy"]
        if removeAll {
            args += ["-map_metadata", "-1", "-map_chapters", "-1"]
        } else {
            args += ["-map_metadata", "0"]
            for edit in edits where edit.editable {
                args += ["-metadata", "\(edit.key)=\(edit.value)"]
            }
        }
        args.append(destination.path)
        try await FFmpeg.run(args, purpose: "Writing metadata")
    }

    private static func writePDF(_ url: URL, edits: [MetadataField], removeAll: Bool, removeSensitive: Bool, to destination: URL) throws {
        let document = try PDFOps.document(url)
        if removeAll {
            document.documentAttributes = [:]
        } else {
            var attrs = document.documentAttributes ?? [:]
            if removeSensitive {
                for key in [PDFDocumentAttribute.authorAttribute, .creatorAttribute, .producerAttribute] { attrs.removeValue(forKey: key) }
            }
            for edit in edits where edit.editable && edit.id.hasPrefix("pdf.") && !(removeSensitive && edit.sensitive) {
                let name = String(edit.id.dropFirst(4))
                let key = AnyHashable(PDFDocumentAttribute(rawValue: name))
                if edit.value.isEmpty {
                    attrs.removeValue(forKey: key)
                } else {
                    attrs[key] = edit.value
                }
            }
            document.documentAttributes = attrs
        }
        guard document.write(to: destination) else { throw OpenTangerineError.encodeFailed(destination.lastPathComponent) }
    }
}

