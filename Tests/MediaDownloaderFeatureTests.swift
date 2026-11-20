// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

// Notch support is part of the test target, while the app service is not.
// Keep the test build independent of the process-running service implementation.
final class MediaDownloaderService {
    static let shared = MediaDownloaderService()
    var isDownloading = false
    var isBatchRunning = false
    var activeDownloadTitle: String? { nil }
    var activeDownloadFraction: Double? { nil }
}

enum MediaDownloaderFeatureTests {
    static func run(_ suite: TestSuite) {
        let youtube = URL(string: "https://www.youtube.com/watch?v=abc123")!
        let instagram = URL(string: "https://instagram.com/reel/xyz/")!

        suite.expect(MediaDownloaderPlatform.identify(youtube) == .youtube,
                     "YouTube subdomains are identified")
        suite.expect(MediaDownloaderPlatform.identify(URL(string: "https://youtu.be/abc123")!) == .youtube,
                     "youtu.be links are identified as YouTube")
        suite.expect(MediaDownloaderPlatform.identify(instagram) == .instagram,
                     "Instagram links are identified")
        suite.expect(MediaDownloaderPlatform.identify(URL(string: "https://www.tiktok.com/@user/video/1")!) == .tiktok,
                     "TikTok subdomains are identified")
        suite.expect(MediaDownloaderPlatform.identify(URL(string: "https://media.example.org/watch/1")!) == .other,
                     "unlisted sites use the generic platform")
        for language in AppLanguage.allCases {
            let copy = FeatureStrings.mediaDownloader(language)
            suite.expect(!copy.toolsTitle.isEmpty && !copy.linkTitle.isEmpty
                         && !copy.batchTitle.isEmpty && !copy.progressTitle.isEmpty,
                         "downloader settings headings exist for \(language.rawValue)")
        }

        suite.expect(MediaDownloaderSupport.normalizedURL("  https://example.org/video  ")?.absoluteString
                     == "https://example.org/video",
                     "media URLs are trimmed and normalized")
        suite.expect(MediaDownloaderSupport.normalizedURL("file:///tmp/video.mp4") == nil,
                     "non-web URLs are rejected")
        suite.expect(MediaDownloaderSupport.normalizedURL("https://user:pass@example.org/video") == nil,
                     "URLs containing credentials are rejected")

        let links = """
        https://youtu.be/abc123 #MKV
        https://instagram.com/reel/xyz/ #MP3
        https://example.org/photo #HEIC
        https://example.org/default
        https://youtu.be/abc123 #MP4
        """
        let items = MediaDownloaderSupport.batchItems(in: links)
        suite.expect(items.map(\.format) == [.mkv, .mp3, .heic, .mp4, .mp4],
                     "batch links accept format tags and default to MP4")
        suite.expect(items[0].kind == .video && items[1].kind == .audio && items[2].kind == .image,
                     "batch formats map to video, audio and image history types")
        suite.expect(items[0].url == items[4].url && items[0].id != items[4].id,
                     "the same URL can be queued with distinct output formats")
        suite.expect(items[0].format.historyQuality == "MKV · Best available"
                     && items[1].format.historyQuality == "MP3"
                     && items[2].format.historyQuality == "HEIC thumbnail",
                     "history labels describe the requested batch format")

        let ffmpeg = URL(fileURLWithPath: "/opt/homebrew/bin/ffmpeg")
        let folder = URL(fileURLWithPath: "/tmp/media-download-tests", isDirectory: true)
        let mp4Args = MediaDownloaderSupport.videoArguments(url: youtube, folder: folder,
                                                             quality: 720, ffmpeg: ffmpeg)
        suite.expect(mp4Args.contains("--remux-video") && mp4Args.contains("mp4")
                     && mp4Args.contains(where: { $0.contains("height<=720") }),
                     "video arguments request MP4 and honor the selected quality")
        let mkvArgs = MediaDownloaderSupport.videoArguments(url: youtube, folder: folder,
                                                             quality: nil, ffmpeg: ffmpeg,
                                                             outputFormat: "mkv")
        suite.expect(mkvArgs.contains("--recode-video") && mkvArgs.contains("mkv"),
                     "alternate video formats are passed to the media processor")
        let mp3Args = MediaDownloaderSupport.audioArguments(url: youtube, folder: folder,
                                                            format: "mp3", ffmpeg: ffmpeg)
        suite.expect(mp3Args.contains("--extract-audio") && mp3Args.contains("--audio-format")
                     && mp3Args.contains("mp3"),
                     "audio arguments request the selected audio format")
        let heicArgs = MediaDownloaderSupport.thumbnailArguments(url: youtube, folder: folder,
                                                                  ffmpeg: ffmpeg,
                                                                  outputFormat: "png")
        suite.expect(heicArgs.contains("--write-thumbnail") && heicArgs.contains("png"),
                     "image batch items fetch thumbnails for local image conversion")

        let metadataJSON = Data(#"{"title":"Sample","uploader":"Creator","duration":12.5,"formats":[{"format_id":"low","height":360,"ext":"mp4","vcodec":"h264","acodec":"aac"},{"format_id":"audio","ext":"m4a","vcodec":"none","acodec":"aac"}]}"#.utf8)
        let metadata = try? MediaDownloaderSupport.Metadata.decode(metadataJSON, platform: .youtube)
        suite.expect(metadata?.title == "Sample" && metadata?.uploader == "Creator"
                     && metadata?.videoQualities == [360]
                     && metadata?.formats.first(where: { $0.id == "audio" })?.isAudioOnly == true,
                     "metadata extraction exposes title, uploader and selectable video quality")
    }
}
