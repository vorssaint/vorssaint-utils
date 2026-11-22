// SPDX-License-Identifier: GPL-3.0-only
// Adapted from Open Tangerine (c) 2026 Sintax Error Private Limited, GPL-3.0-only,
// itself substantially based on Satsuma (c) 2026 plyght, MIT. See NOTICE.

import Foundation

enum ToolArity {
    case single
    case multiple
    case any
}

enum ToolID: String, CaseIterable, Identifiable {
    case compress
    case editMetadata
    case editImage
    case frameImage
    case cropImage
    case redactImage
    case removeBackground
    case upscaleImage
    case copyText
    case extractArchive
    case resizeImage
    case rotateImage
    case createPDF
    case createCollage
    case trimVideo
    case cropVideo
    case changeVideoSpeed
    case joinVideos
    case videoSnapshots
    case splitVideo
    case redactVideo
    case normalizeAudio
    case audioToVideo
    case trimAudio
    case audioChannels
    case redactAudio
    case annotatePDF
    case mergePDF
    case organizePDF
    case splitPDF

    var id: String { rawValue }

    var title: String {
        switch self {
        case .compress: return "Compress"
        case .editMetadata: return "Edit metadata"
        case .editImage: return "Edit photo"
        case .frameImage: return "Add a background"
        case .cropImage: return "Crop image"
        case .redactImage: return "Redact photo"
        case .removeBackground: return "Remove background"
        case .upscaleImage: return "Upscale"
        case .copyText: return "Copy text (OCR)"
        case .extractArchive: return "Extract here"
        case .resizeImage: return "Resize images"
        case .rotateImage: return "Rotate & flip"
        case .createPDF: return "Create a PDF"
        case .createCollage: return "Create a collage"
        case .trimVideo: return "Trim video"
        case .cropVideo: return "Crop video"
        case .changeVideoSpeed: return "Change video speed"
        case .joinVideos: return "Join videos"
        case .videoSnapshots: return "Save video frames"
        case .splitVideo: return "Split video"
        case .redactVideo: return "Redact video"
        case .normalizeAudio: return "Normalize volume"
        case .audioToVideo: return "Audio visualizer"
        case .trimAudio: return "Trim audio"
        case .audioChannels: return "Audio channels"
        case .redactAudio: return "Bleep audio"
        case .annotatePDF: return "Edit PDF"
        case .mergePDF: return "Merge PDFs"
        case .organizePDF: return "Organize PDF pages"
        case .splitPDF: return "Split PDF"
        }
    }

    var progressTitle: String {
        switch self {
        case .compress: return "Compressing"
        case .editMetadata: return "Editing metadata"
        case .editImage: return "Editing photo"
        case .frameImage: return "Adding background"
        case .cropImage, .cropVideo: return "Cropping"
        case .redactImage, .redactVideo: return "Redacting"
        case .removeBackground: return "Removing background"
        case .upscaleImage: return "Upscaling"
        case .copyText: return "Reading text"
        case .extractArchive: return "Extracting"
        case .resizeImage: return "Resizing"
        case .rotateImage: return "Rotating"
        case .createPDF: return "Creating PDF"
        case .createCollage: return "Creating collage"
        case .trimVideo, .trimAudio: return "Trimming"
        case .changeVideoSpeed: return "Changing speed"
        case .joinVideos: return "Joining"
        case .videoSnapshots: return "Saving frames"
        case .splitVideo, .splitPDF: return "Splitting"
        case .normalizeAudio: return "Normalizing"
        case .audioToVideo: return "Creating visualizer"
        case .audioChannels: return "Converting channels"
        case .redactAudio: return "Bleeping"
        case .annotatePDF: return "Editing PDF"
        case .mergePDF: return "Merging"
        case .organizePDF: return "Organizing"
        }
    }

    var radialLabel: String {
        switch self {
        case .compress: return "COMPRESS"
        case .editMetadata: return "METADATA"
        case .editImage: return "EDIT"
        case .frameImage: return "ADD BG"
        case .cropImage, .cropVideo: return "CROP"
        case .redactImage, .redactVideo: return "REDACT"
        case .removeBackground: return "REMOVE BG"
        case .upscaleImage: return "UPSCALE"
        case .copyText: return "COPY TEXT"
        case .extractArchive: return "EXTRACT"
        case .resizeImage: return "RESIZE"
        case .rotateImage: return "ROTATE"
        case .createPDF: return "PDF"
        case .createCollage: return "COLLAGE"
        case .trimVideo, .trimAudio: return "TRIM"
        case .changeVideoSpeed: return "SPEED"
        case .joinVideos: return "JOIN"
        case .videoSnapshots: return "FRAMES"
        case .splitVideo, .splitPDF: return "SPLIT"
        case .normalizeAudio: return "NORMALIZE"
        case .audioToVideo: return "VISUALIZE"
        case .audioChannels: return "CHANNELS"
        case .redactAudio: return "BLEEP"
        case .annotatePDF: return "EDIT PDF"
        case .mergePDF: return "MERGE"
        case .organizePDF: return "ORGANIZE"
        }
    }

    var symbol: String {
        switch self {
        case .compress: return "arrow.down.right.and.arrow.up.left"
        case .editMetadata: return "tag"
        case .editImage: return "slider.horizontal.3"
        case .frameImage: return "photo.artframe"
        case .cropImage, .cropVideo: return "crop"
        case .redactImage: return "eye.slash"
        case .removeBackground: return "person.crop.rectangle"
        case .upscaleImage: return "arrow.up.forward.square"
        case .copyText: return "text.viewfinder"
        case .extractArchive: return "archivebox"
        case .redactVideo: return "video.slash"
        case .resizeImage: return "arrow.up.left.and.arrow.down.right"
        case .rotateImage: return "rotate.right"
        case .createPDF: return "doc.richtext"
        case .createCollage: return "square.grid.2x2"
        case .trimVideo, .trimAudio: return "scissors"
        case .changeVideoSpeed: return "gauge.with.dots.needle.67percent"
        case .joinVideos: return "link"
        case .videoSnapshots: return "camera.viewfinder"
        case .splitVideo: return "rectangle.split.2x1"
        case .splitPDF: return "doc.on.doc"
        case .normalizeAudio: return "waveform"
        case .audioToVideo: return "waveform.and.magnifyingglass"
        case .audioChannels: return "headphones"
        case .redactAudio: return "speaker.slash"
        case .annotatePDF: return "pencil.and.outline"
        case .mergePDF: return "doc.on.doc.fill"
        case .organizePDF: return "rectangle.stack"
        }
    }

    var categories: Set<FormatCategory> {
        switch self {
        case .compress, .editMetadata:
            return [.image, .video, .audio, .document]
        case .editImage, .frameImage, .cropImage, .redactImage, .resizeImage, .rotateImage, .createPDF, .createCollage,
             .removeBackground, .upscaleImage:
            return [.image]
        case .copyText:
            return [.image, .document]
        case .extractArchive:
            return [.archive]
        case .trimVideo, .cropVideo, .changeVideoSpeed, .joinVideos, .videoSnapshots, .splitVideo, .redactVideo:
            return [.video]
        case .normalizeAudio, .audioToVideo, .trimAudio, .audioChannels, .redactAudio:
            return [.audio]
        case .annotatePDF, .mergePDF, .organizePDF, .splitPDF:
            return [.document]
        }
    }

    var arity: ToolArity {
        switch self {
        case .compress, .editMetadata, .resizeImage, .rotateImage, .createPDF, .mergePDF, .removeBackground, .upscaleImage, .extractArchive: return .any
        case .createCollage, .joinVideos: return .multiple
        default: return .single
        }
    }

    func applies(to formats: [FileFormat]) -> Bool {
        guard !formats.isEmpty else { return false }
        let categories = Set(formats.map(\.category))
        guard categories.count == 1, let category = categories.first, self.categories.contains(category) else { return false }
        if category == .document {
            switch self {
            case .annotatePDF, .mergePDF, .organizePDF, .splitPDF, .editMetadata, .compress, .copyText:
                guard formats.allSatisfy({ $0 == .pdf }) else { return false }
            default:
                return false
            }
        }
        if category == .video, formats.contains(.gif), self != .compress, self != .editMetadata { return false }
        switch arity {
        case .single: return formats.count == 1
        case .multiple: return formats.count >= 2
        case .any: return true
        }
    }

    static func available(for formats: [FileFormat]) -> [ToolID] {
        allCases.filter { $0.applies(to: formats) }
    }

    static var total: Int { allCases.count }
}

