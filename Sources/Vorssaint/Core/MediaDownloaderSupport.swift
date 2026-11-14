// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

enum MediaDownloaderPlatform: String, CaseIterable, Codable, Hashable {
    case youtube, instagram, tiktok, other

    var title: String {
        switch self {
        case .youtube: return "YouTube"
        case .instagram: return "Instagram"
        case .tiktok: return "TikTok"
        case .other: return "Other site"
        }
    }

    static func identify(_ url: URL) -> Self {
        let host = (url.host ?? "").lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "."))
        if host == "youtube.com" || host.hasSuffix(".youtube.com") || host == "youtu.be" {
            return .youtube
        }
        if host == "instagram.com" || host.hasSuffix(".instagram.com") {
            return .instagram
        }
        if host == "tiktok.com" || host.hasSuffix(".tiktok.com") {
            return .tiktok
        }
        return .other
    }
}

enum MediaDownloaderSupport {
    static let historyFileName = "media-downloader-history.json"
    static let outputTemplate = "%(title).200B [%(id)s].%(ext)s"

    struct Dependencies: Equatable {
        let ytDLP: URL?
        let ffmpeg: URL?

        var areReady: Bool { ytDLP != nil && ffmpeg != nil }

        static func locate(fileManager: FileManager = .default) -> Self {
            let bundledBin = Bundle.main.resourceURL?
                .appendingPathComponent("MediaDownloader/bin", isDirectory: true).path
            let roots = [bundledBin, "/opt/homebrew/bin", "/usr/local/bin",
                         "/opt/homebrew/opt/yt-dlp/bin", "/usr/local/opt/yt-dlp/bin"].compactMap { $0 }
            func find(_ name: String) -> URL? {
                for root in roots {
                    let url = URL(fileURLWithPath: root, isDirectory: true).appendingPathComponent(name)
                    if fileManager.isExecutableFile(atPath: url.path) { return url }
                }
                return nil
            }
            return Self(ytDLP: find("yt-dlp"), ffmpeg: find("ffmpeg"))
        }
    }

    struct Format: Identifiable, Hashable {
        let id: String
        let height: Int
        let extensionName: String
        let isAudioOnly: Bool
    }

    enum BatchFormat: String, CaseIterable, Hashable {
        case mp4, mkv, mov, webm, avi, flv, gif
        case mp3, m4a, wav, opus, flac, aac, alac, vorbis, original
        case heic, heif, jpg, png, webp

        var isAudio: Bool {
            [.mp3, .m4a, .wav, .opus, .flac, .aac, .alac, .vorbis, .original].contains(self)
        }
        var isImage: Bool { [.heic, .heif, .jpg, .png, .webp].contains(self) }
        var isVideo: Bool { !isAudio && !isImage }
        var title: String { self == .original ? "Original audio" : rawValue.uppercased() }
        var historyQuality: String {
            if isImage { return "\(title) thumbnail" }
            return isAudio ? title : "\(title) · Best available"
        }
    }

    struct BatchItem: Identifiable, Hashable {
        let url: URL
        let format: BatchFormat

        var id: String { "\(url.absoluteString)|\(format.rawValue)" }
        var kind: HistoryEntry.Kind { format.isImage ? .image : (format.isAudio ? .audio : .video) }
        var formatTag: String { format.title }
    }

    struct Metadata: Hashable {
        let title: String
        let uploader: String
        let duration: TimeInterval?
        let platform: MediaDownloaderPlatform
        let formats: [Format]

        var videoQualities: [Int] {
            Array(Set(formats.filter { !$0.isAudioOnly && $0.height > 0 }.map(\.height))).sorted(by: >)
        }

        static func decode(_ data: Data, platform: MediaDownloaderPlatform) throws -> Self {
            guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                throw MediaDownloaderError.invalidMetadata
            }
            let formats = (object["formats"] as? [[String: Any]] ?? []).compactMap { format -> Format? in
                guard let id = format["format_id"] as? String, !id.isEmpty else { return nil }
                let videoCodec = format["vcodec"] as? String ?? "none"
                let audioCodec = format["acodec"] as? String ?? "none"
                return Format(id: id,
                              height: format["height"] as? Int ?? 0,
                              extensionName: format["ext"] as? String ?? "file",
                              isAudioOnly: videoCodec == "none" && audioCodec != "none")
            }
            return Self(title: (object["title"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? "Untitled media",
                        uploader: object["uploader"] as? String ?? object["channel"] as? String ?? "",
                        duration: object["duration"] as? Double,
                        platform: platform,
                        formats: formats)
        }
    }

    struct Progress: Equatable {
        let fraction: Double?
        let downloadedBytes: Int64?
        let totalBytes: Int64?
        let speedBytesPerSecond: Double?
        let secondsRemaining: Double?

        var speedText: String? {
            guard let speedBytesPerSecond, speedBytesPerSecond > 0 else { return nil }
            return ByteCountFormatter.string(fromByteCount: Int64(speedBytesPerSecond), countStyle: .file) + "/s"
        }

        static func parseProgressLine(_ line: String) -> Self? {
            let marker = "VORSSAINT_PROGRESS:"
            guard let range = line.range(of: marker) else { return nil }
            let fields = line[range.upperBound...].split(separator: "|", omittingEmptySubsequences: false)
            guard fields.count == 5 else { return nil }
            func number<T: LosslessStringConvertible>(_ index: Int) -> T? {
                let field = fields[index].trimmingCharacters(in: .whitespacesAndNewlines)
                return field == "NA" ? nil : T(field)
            }
            let downloaded: Int64? = number(0)
            let exactTotal: Int64? = number(1)
            let estimatedTotal: Int64? = number(2)
            let total = exactTotal ?? estimatedTotal
            let fraction = total.flatMap { total -> Double? in
                guard total > 0, let downloaded else { return nil }
                return min(1, max(0, Double(downloaded) / Double(total)))
            }
            return Self(fraction: fraction,
                        downloadedBytes: downloaded,
                        totalBytes: total,
                        speedBytesPerSecond: number(3),
                        secondsRemaining: number(4))
        }
    }

    struct HistoryEntry: Codable, Identifiable, Hashable {
        let id: UUID
        let title: String
        let url: String
        let platform: MediaDownloaderPlatform
        let filePath: String
        let kind: Kind
        let quality: String
        let completedAt: Date

        enum Kind: String, Codable, Hashable { case video, audio, image }

        var fileURL: URL { URL(fileURLWithPath: filePath) }

        init(title: String, url: String, platform: MediaDownloaderPlatform,
             filePath: String, kind: Kind, quality: String, completedAt: Date = Date()) {
            id = UUID()
            self.title = title
            self.url = url
            self.platform = platform
            self.filePath = filePath
            self.kind = kind
            self.quality = quality
            self.completedAt = completedAt
        }
    }

    static func normalizedURL(_ rawValue: String) -> URL? {
        let candidate = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let components = URLComponents(string: candidate),
              let scheme = components.scheme?.lowercased(), ["http", "https"].contains(scheme),
              let host = components.host, !host.isEmpty,
              components.user == nil, components.password == nil,
              let url = components.url
        else { return nil }
        return url
    }

    static func batchItems(in text: String) -> [BatchItem] {
        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) else {
            return []
        }
        let matches = detector.matches(in: text, range: NSRange(text.startIndex..., in: text))
        let source = text as NSString
        var seen = Set<String>()
        return matches.enumerated().compactMap { index, match in
            guard let url = match.url,
                  ["http", "https"].contains(url.scheme?.lowercased() ?? "") else { return nil }

            let suffixStart = NSMaxRange(match.range)
            let nextLinkStart = matches.dropFirst(index + 1).first?.range.location ?? source.length
            let newline = source.range(of: "\n", range: NSRange(location: suffixStart,
                                                                  length: max(0, source.length - suffixStart)))
            let lineEnd = min(nextLinkStart, newline.location == NSNotFound ? source.length : newline.location)
            let suffix = lineEnd > suffixStart
                ? source.substring(with: NSRange(location: suffixStart, length: lineEnd - suffixStart))
                : ""
            let tags = suffix.lowercased().split { !$0.isLetter && !$0.isNumber }
            let format = tags.reversed()
                .compactMap { BatchFormat(rawValue: String($0)) }
                .first ?? .mp4
            let item = BatchItem(url: url, format: format)
            guard seen.insert(item.id).inserted else { return nil }
            return item
        }
    }

    static func metadataArguments(url: URL) -> [String] {
        ["--ignore-config", "--no-playlist", "--no-warnings", "--no-progress", "--quiet",
         "--dump-single-json", "--skip-download", "--", url.absoluteString]
    }

    static func videoArguments(url: URL, folder: URL, quality: Int?, ffmpeg: URL,
                               outputFormat: String = "mp4") -> [String] {
        let selector: String
        if let quality {
            selector = "bv*[height<=\(quality)]+ba/b[height<=\(quality)]/best[height<=\(quality)]"
        } else {
            selector = "bv*+ba/best"
        }
        let prefix = commonDownloadArguments(url: url, folder: folder, ffmpeg: ffmpeg)
            + ["--format", selector,
               "--format-sort", "vcodec:h264,lang,quality,res,fps,hdr:12,acodec:aac"]
        if outputFormat == "mp4" {
            return prefix + ["--merge-output-format", "mp4", "--remux-video", "mp4", "--", url.absoluteString]
        }
        if outputFormat == "gif" {
            return prefix + ["--recode-video", "gif", "--", url.absoluteString]
        }
        return prefix + ["--merge-output-format", outputFormat,
                         "--recode-video", outputFormat, "--", url.absoluteString]
    }

    static func thumbnailArguments(url: URL, folder: URL, ffmpeg: URL, outputFormat: String = "png") -> [String] {
        ["--ignore-config", "--no-playlist", "--no-warnings", "--quiet", "--progress", "--newline",
         "--progress-template",
         "download:VORSSAINT_PROGRESS:%(progress.downloaded_bytes)s|%(progress.total_bytes)s|%(progress.total_bytes_estimate)s|%(progress.speed)s|%(progress.eta)s",
         "--skip-download", "--write-thumbnail", "--convert-thumbnails", outputFormat,
         "--paths", folder.path, "--output", "thumbnail:cover.%(ext)s",
         "--ffmpeg-location", ffmpeg.deletingLastPathComponent().path, "--", url.absoluteString]
    }

    static func audioArguments(url: URL, folder: URL, format: String, ffmpeg: URL) -> [String] {
        let prefix = commonDownloadArguments(url: url, folder: folder, ffmpeg: ffmpeg)
        if format == "original" {
            return prefix + ["--format", "bestaudio/best", "--", url.absoluteString]
        }
        return prefix + ["--format", "bestaudio/best", "--extract-audio",
                         "--audio-format", format, "--audio-quality", "0", "--", url.absoluteString]
    }

    static func historyURL(container: URL? = PrivateFileStore.containerURL) -> URL? {
        container?.appendingPathComponent(historyFileName, isDirectory: false)
    }

    private static func commonDownloadArguments(url: URL, folder: URL, ffmpeg: URL) -> [String] {
        ["--ignore-config", "--no-playlist", "--no-warnings", "--quiet", "--progress", "--newline",
         "--progress-template",
         "download:VORSSAINT_PROGRESS:%(progress.downloaded_bytes)s|%(progress.total_bytes)s|%(progress.total_bytes_estimate)s|%(progress.speed)s|%(progress.eta)s",
         "--print", "after_move:VORSSAINT_FILE:%(filepath)j",
         "--paths", folder.path, "--output", outputTemplate,
         "--ffmpeg-location", ffmpeg.deletingLastPathComponent().path]
    }
}

enum MediaDownloaderError: LocalizedError {
    case invalidURL
    case invalidMetadata
    case dependenciesMissing
    case outputFileMissing
    case processFailed(String)

    var errorDescription: String? {
        switch self {
        case .invalidURL: return "Enter a valid video or media URL."
        case .invalidMetadata: return "The site returned media details in an unreadable format."
        case .dependenciesMissing: return "Install yt-dlp and FFmpeg to download media."
        case .outputFileMissing: return "The download finished, but yt-dlp did not return its saved file."
        case .processFailed(let message): return message
        }
    }
}
