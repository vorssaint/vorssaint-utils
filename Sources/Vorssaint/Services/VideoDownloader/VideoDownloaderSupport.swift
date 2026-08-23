// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Darwin
import Foundation

enum VideoDownloaderSystemSettingsDestination: Equatable, Hashable {
    case fullDiskAccess
    case automation
}

enum VideoDownloaderFailureRecoveryAction: Equatable, Hashable {
    case retry
    case configureBrowserCookies
    case openSystemSettings(VideoDownloaderSystemSettingsDestination)
    case copyErrorDetails(String)
    case viewHelp
}

struct VideoDownloaderFailureRecoveryPlan: Equatable {
    let primary: VideoDownloaderFailureRecoveryAction
    let secondary: VideoDownloaderFailureRecoveryAction?

    init(primary: VideoDownloaderFailureRecoveryAction,
         secondary: VideoDownloaderFailureRecoveryAction? = nil) {
        self.primary = primary
        self.secondary = secondary
    }
}

enum VideoDownloaderFailureRecoveryPolicy {
    static func plan(for failure: VideoDownloaderFailure) -> VideoDownloaderFailureRecoveryPlan {
        switch failure {
        case .restricted:
            return VideoDownloaderFailureRecoveryPlan(
                primary: .configureBrowserCookies,
                secondary: .retry)
        case .cookiesPermission:
            return VideoDownloaderFailureRecoveryPlan(
                primary: .openSystemSettings(.fullDiskAccess),
                secondary: .retry)
        case .terminalPermission:
            return VideoDownloaderFailureRecoveryPlan(
                primary: .openSystemSettings(.automation),
                secondary: .retry)
        case .rateLimited:
            return VideoDownloaderFailureRecoveryPlan(primary: .retry, secondary: .viewHelp)
        case let .extractorError(details)
            where VideoDownloaderRateLimitSupport.shouldSuggestRateLimitHelp(details):
            return VideoDownloaderFailureRecoveryPlan(primary: .retry, secondary: .viewHelp)
        case let .extractorError(details):
            return VideoDownloaderFailureRecoveryPlan(
                primary: .copyErrorDetails(details),
                secondary: .retry)
        default:
            return VideoDownloaderFailureRecoveryPlan(primary: .retry)
        }
    }
}

enum VideoDownloaderExecutionEnvironment {
    static func make(base: [String: String] = ProcessInfo.processInfo.environment,
                     executable: String,
                     additionalDirectories: [String]) -> [String: String] {
        var environment = base
        let executableDirectory = URL(fileURLWithPath: executable).deletingLastPathComponent().path
        let inherited = (base["PATH"] ?? "").split(separator: ":").map(String.init)
        let system = ["/usr/bin", "/bin", "/usr/sbin", "/sbin"]
        var seen = Set<String>()
        let directories = ([executableDirectory] + additionalDirectories + inherited + system).filter {
            !$0.isEmpty && seen.insert($0).inserted
        }
        environment["PATH"] = directories.joined(separator: ":")
        return environment
    }
}

enum VideoDownloaderCommandBuilder {
    static let progressPrefix = "__VORSSAINT_DOWNLOADER_PROGRESS__"
    static let titlePrefix = "__VORSSAINT_DOWNLOADER_TITLE__"
    static let qualityPrefix = "__VORSSAINT_DOWNLOADER_QUALITY__"
    static let pathPrefix = "__VORSSAINT_DOWNLOADER_PATH__"
    // Strip leading dots so titles starting with punctuation don't become hidden files in Finder.
    static let outputTemplate = "%(title).148B [%(id).40B].%(ext)s"
    // Some extractors omit the `live_status` field entirely on normal videos; using `!=?` prevents
    // false-positive rejections.
    static let nonLiveMatchFilter = "!is_live & live_status!=?is_live & live_status!=?is_upcoming & live_status!=?post_live"

    static func inspection(ytDlpPath: String,
                           denoPath: String? = nil,
                           cookiesFromBrowser: String? = nil,
                           cacheDirectory: URL = VideoDownloaderFileSupport.cacheDirectory) -> VideoDownloaderToolCommand {
        let runtimeArguments = denoPath.map { ["--js-runtimes", "deno:\($0)"] } ?? []
        return VideoDownloaderToolCommand(executable: ytDlpPath,
                                          arguments: ytDlpArguments(cookiesFromBrowser: cookiesFromBrowser) + [
            // Inspect only the first item of a playlist so users can see metadata quickly without
            // triggering yt-dlp's exit code 101 from `--max-downloads`.
            "--yes-playlist", "--playlist-items", "1",
            "--skip-download", "--dump-single-json", "--no-check-formats",
            "--socket-timeout", "8", "--batch-file", "-",
        ] + runtimeArguments + cacheArguments(cacheDirectory),
        executableSearchDirectories: denoPath.map { [URL(fileURLWithPath: $0).deletingLastPathComponent().path] } ?? [])
    }

    static func dependencyProbe(tool: VideoDownloaderTool,
                                executablePath: String) -> VideoDownloaderToolCommand {
        switch tool {
        case .ytDlp:
            return VideoDownloaderToolCommand(executable: executablePath,
                                              arguments: ytDlpBaseArguments + ["--help"])
        case .ffmpeg:
            return VideoDownloaderToolCommand(executable: executablePath, arguments: ["-version"])
        case .ffprobe:
            return VideoDownloaderToolCommand(executable: executablePath, arguments: ["-version"])
        case .deno:
            return VideoDownloaderToolCommand(executable: executablePath, arguments: ["--version"])
        }
    }

    static func download(ytDlpPath: String,
                         ffmpegPath: String,
                         denoPath: String? = nil,
                         staging: URL,
                         request: VideoDownloaderRequest,
                         cookiesFromBrowser: String? = nil,
                         cacheDirectory: URL = VideoDownloaderFileSupport.cacheDirectory) -> VideoDownloaderToolCommand {
        var arguments = ytDlpArguments(cookiesFromBrowser: cookiesFromBrowser) + [
            // Re-verify playlist and live-stream filters during download in case the URL was changed
            // or bypassed inspection via fallback.
            "--no-playlist", "--playlist-items", "1",
            "--match-filters", nonLiveMatchFilter,
            "--ffmpeg-location", ffmpegPath,
            "--concurrent-fragments", "4",
            "--newline", "--progress", "--progress-delta", "0.15",
            // yt-dlp outputs bare `NA` for missing template values, which breaks JSON parsing.
            // Setting the placeholder to `null` keeps progress updates valid JSON.
            "--output-na-placeholder", "null",
            "--no-overwrites", "--no-post-overwrites", "--no-keep-video",
            "--no-write-info-json", "--no-write-playlist-metafiles",
            "--no-write-description", "--no-write-comments", "--no-embed-info-json",
            "--paths", staging.path, "--paths", "temp:\(staging.path)",
            "--output", outputTemplate,
            "--progress-template", "download:\(progressPrefix){\"downloaded\":%(progress.downloaded_bytes)j,\"total\":%(progress.total_bytes,total_bytes_estimate)j,\"percent\":%(progress._percent_str)j,\"speed\":%(progress.speed)j,\"eta\":%(progress.eta)j,\"elapsed\":%(progress.elapsed)j,\"fragment_index\":%(progress.fragment_index)j,\"fragment_count\":%(progress.fragment_count)j,\"extension\":%(info.ext)j,\"format_id\":%(info.format_id)j,\"vcodec\":%(info.vcodec)j,\"acodec\":%(info.acodec)j,\"video_ext\":%(info.video_ext)j,\"audio_ext\":%(info.audio_ext)j}",
            "--print", "before_dl:\(titlePrefix)%(title)j",
            "--print", "before_dl:\(qualityPrefix)%(height)j",
            "--print", "after_move:\(pathPrefix)%(filepath)j",
        ]
        if let denoPath {
            arguments += ["--js-runtimes", "deno:\(denoPath)"]
        }

        switch request.mode {
        case .video:
            // Target MP4/M4A for native Apple ecosystem compatibility, but fallback cleanly to MKV
            // to avoid lossy, slow video re-encoding.
            arguments += ["--format", videoFormatSelector(request.quality),
                          "--merge-output-format", "mp4/mkv",
                          "--remux-video", "mp4>mp4/mov>mp4/mkv"]
        case .audio:
            arguments += ["--format", "ba[ext=m4a]/ba", "--extract-audio", "--audio-format", "m4a",
                          "--audio-quality", "0"]
        }

        // Thumbnails are fetched and validated in our own pipeline to prevent SSRF against LAN endpoints.
        arguments += ["--no-write-thumbnail", "--no-embed-thumbnail"]
        arguments.append("--embed-metadata")

        arguments.append("--embed-chapters")

        if request.mode == .video {
            // Fetch subtitles in the primary download command to save an extra network roundtrip and extractor initialization.
            if let subtitle = request.subtitle {
                arguments += ["--sub-langs", subtitle.code, "--sub-format", "srt/vtt/best",
                              "--convert-subs", "srt"]
                switch subtitle.source {
                case .manual:
                    arguments += ["--write-subs", "--no-write-auto-subs"]
                case .automatic:
                    arguments += ["--no-write-subs", "--write-auto-subs"]
                }
            } else {
                arguments += ["--no-write-subs", "--no-write-auto-subs"]
            }
            arguments.append("--no-embed-subs")
        } else {
            arguments += ["--no-write-subs", "--no-write-auto-subs"]
        }
        arguments += ["--batch-file", "-"]
        arguments += cacheArguments(cacheDirectory)
        return VideoDownloaderToolCommand(
            executable: ytDlpPath,
            arguments: arguments,
            executableSearchDirectories: [ffmpegPath, denoPath].compactMap { path in
                path.map { URL(fileURLWithPath: $0).deletingLastPathComponent().path }
            }
        )
    }

    static func videoFormatSelector(_ quality: VideoDownloaderQuality) -> String {
        switch quality {
        case .best:
            return "bv*[ext=mp4]+ba[ext=m4a]/b[ext=mp4]/bv*+ba/b"
        case let .height(value):
            let cap = max(1, value)
            return "bv*[ext=mp4][height<=\(cap)]+ba[ext=m4a]/b[ext=mp4][height<=\(cap)]/bv*[height<=\(cap)]+ba/b[height<=\(cap)]"
        }
    }

    static func ffmpegSubtitle(ffmpegPath: String,
                               input: URL,
                               subtitle: URL,
                               output: URL,
                               language: String) -> VideoDownloaderToolCommand {
        let subtitleCodec = input.pathExtension.lowercased() == "mp4" ? "mov_text" : "srt"
        return VideoDownloaderToolCommand(executable: ffmpegPath, arguments: [
            "-nostdin", "-hide_banner", "-loglevel", "error",
            "-i", input.path, "-i", subtitle.path,
            "-map", "0", "-map", "1:0", "-map_metadata", "0", "-map_chapters", "0",
            "-c", "copy", "-c:s", subtitleCodec,
            "-metadata:s:s:0", "language=\(language)",
            output.path,
        ])
    }

    static func ffmpegArtwork(ffmpegPath: String,
                              input: URL,
                              artwork: URL,
                              output: URL,
                              mode: VideoDownloaderOutputMode) -> VideoDownloaderToolCommand {
        var arguments = ["-nostdin", "-hide_banner", "-loglevel", "error", "-i", input.path]
        switch mode {
        case .video:
            if input.pathExtension.lowercased() == "mkv" {
                // MKV expects cover art attached as a binary stream (`-attach`), unlike MP4 which multiplexes it as a video stream.
                arguments += ["-map", "0", "-map_metadata", "0", "-map_chapters", "0",
                              "-c", "copy", "-attach", artwork.path,
                              "-metadata:s:t", "mimetype=image/jpeg",
                              "-metadata:s:t", "filename=cover.jpg"]
            } else {
                arguments += ["-i", artwork.path, "-map", "0", "-map", "1:v:0",
                              "-map_metadata", "0", "-map_chapters", "0", "-c", "copy",
                              "-c:v:1", "mjpeg", "-disposition:v:1", "attached_pic"]
            }
        case .audio:
            arguments += ["-i", artwork.path, "-map", "0", "-map", "1:v:0",
                          "-map_metadata", "0", "-map_chapters", "0", "-c", "copy",
                          "-c:v:0", "mjpeg", "-disposition:v:0", "attached_pic"]
        }
        arguments.append(output.path)
        return VideoDownloaderToolCommand(executable: ffmpegPath, arguments: arguments)
    }

    static func ffprobe(ffprobePath: String, input: URL) -> VideoDownloaderToolCommand {
        VideoDownloaderToolCommand(executable: ffprobePath, arguments: [
            "-v", "error", "-show_streams", "-show_chapters", "-show_format",
            "-of", "json", input.path,
        ])
    }

    static func homebrewInstall(brewPath: String,
                                missingTools: Set<VideoDownloaderTool>) -> VideoDownloaderToolCommand? {
        let formulae = VideoDownloaderTool.formulae(for: missingTools)
        guard !formulae.isEmpty else { return nil }
        return VideoDownloaderToolCommand(executable: brewPath, arguments: ["install"] + formulae)
    }

    // Keep downloader behavior reproducible across machines by ignoring personal shell configs,
    // custom plugins, or untrusted hooks.
    private static let ytDlpBaseArguments = [
        "--ignore-config", "--no-config-locations", "--no-plugin-dirs",
        "--no-cookies", "--no-cookies-from-browser",
        "--no-color", "--no-exec", "--force-ipv4",
    ]

    /// Isolate challenge solvers to an app-owned cache directory to avoid polluting or conflicting with global yt-dlp caches.
    static func cacheArguments(_ cacheDirectory: URL = VideoDownloaderFileSupport.cacheDirectory) -> [String] {
        ["--cache-dir", cacheDirectory.path, "--remote-components", "ejs:github"]
    }

    // When browser cookies are requested, drop `--no-cookies` flags so `--cookies-from-browser` takes effect.
    private static func ytDlpArguments(cookiesFromBrowser: String?) -> [String] {
        guard let browser = cookiesFromBrowser, !browser.isEmpty else { return ytDlpBaseArguments }
        return ytDlpBaseArguments.filter { $0 != "--no-cookies" && $0 != "--no-cookies-from-browser" }
            + ["--cookies-from-browser", browser]
    }
}

/// Fall back to interactive Terminal commands when automated Homebrew installation requires sudo passwords or user prompts.
enum VideoDownloaderTerminalSetup {
    static let installerBodyProducer = HomebrewCommandBuilder.installerBodyProducer
    static let brewCandidatePaths = HomebrewCommandBuilder.candidatePaths

    static let defaultFormulae = ["yt-dlp", "ffmpeg", "deno"]

    static func formulae(for missingTools: Set<VideoDownloaderTool>) -> [String] {
        VideoDownloaderTool.formulae(for: missingTools)
    }

    static func command(formulae: [String] = defaultFormulae,
                        installHomebrew: Bool = true,
                        installerBodyProducer: String = installerBodyProducer,
                        brewCandidatePaths: [String] = brewCandidatePaths) -> String {
        HomebrewCommandBuilder.terminalInstallCommand(
            formulae: formulae,
            installHomebrew: installHomebrew,
            installerBodyProducer: installerBodyProducer,
            brewCandidatePaths: brewCandidatePaths
        )
    }

    static func shellQuote(_ value: String) -> String {
        HomebrewCommandBuilder.shellQuote(value)
    }
}

enum VideoDownloaderFileSupport {
    static let stagingPrefix = ".vorssaint-video-download-"
    static let ownerMarkerName = ".vorssaint-owner-pid"
    static let staleAge: TimeInterval = 24 * 60 * 60
    private static let ownerMarkerHeader = "vorssaint-video-download-v1"

    /// Cache JavaScript challenge solvers locally so we only download them from GitHub once.
    static var cacheDirectory: URL {
        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return base
            .appendingPathComponent("Vorssaint", isDirectory: true)
            .appendingPathComponent("yt-dlp-ejs", isDirectory: true)
    }

    static func makeStagingDirectory(in destination: URL,
                                     id: UUID = UUID(),
                                     ownerPID: pid_t = getpid(),
                                     fileManager: FileManager = .default,
                                     writeOwnerMarker: ((URL) throws -> Void)? = nil) throws -> URL {
        let url = destination.appendingPathComponent(stagingPrefix + id.uuidString, isDirectory: true)
        try fileManager.createDirectory(at: url, withIntermediateDirectories: false,
                                        attributes: [.posixPermissions: NSNumber(value: 0o700)])
        do {
            if let writeOwnerMarker {
                try writeOwnerMarker(url.appendingPathComponent(ownerMarkerName))
            } else {
                try ownerMarkerData(id: id, pid: ownerPID)
                    .write(to: url.appendingPathComponent(ownerMarkerName), options: .atomic)
            }
        } catch {
            try? fileManager.removeItem(at: url)
            throw error
        }
        return url
    }

    static func withStagingDirectory<T>(in destination: URL,
                                        id: UUID = UUID(),
                                        fileManager: FileManager = .default,
                                        body: (URL) throws -> T) throws -> T {
        let staging = try makeStagingDirectory(in: destination, id: id, fileManager: fileManager)
        defer { try? fileManager.removeItem(at: staging) }
        return try body(staging)
    }

    static func isContained(_ candidate: URL, in staging: URL) -> Bool {
        let root = staging.standardizedFileURL.resolvingSymlinksInPath().path
        let value = candidate.standardizedFileURL.resolvingSymlinksInPath().path
        return value.hasPrefix(root + "/")
    }

    /// Use identical file validation rules during active downloading and final publication so both stages agree on valid media.
    static func mediaCandidates(in staging: URL,
                                mode: VideoDownloaderOutputMode,
                                fileManager: FileManager = .default) -> [URL] {
        let expectedExtensions = mode.allowedExtensions
        guard let enumerator = fileManager.enumerator(at: staging,
                                                      includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey],
                                                      options: []) else { return [] }
        return enumerator.compactMap { $0 as? URL }.filter { url in
            guard expectedExtensions.contains(url.pathExtension.lowercased()),
                  isContained(url, in: staging),
                  let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey]) else {
                return false
            }
            return values.isRegularFile == true && (values.fileSize ?? 0) > 0
        }
    }

    static func finalMedia(in staging: URL,
                           reportedPath: String,
                           mode: VideoDownloaderOutputMode,
                           fileManager: FileManager = .default) throws -> URL {
        let reported = URL(fileURLWithPath: reportedPath)
        let reportedExtension = reported.pathExtension.lowercased()
        let expectedExtensions = mode.allowedExtensions
        guard isContained(reported, in: staging),
              expectedExtensions.contains(reportedExtension) else {
            throw VideoDownloaderFailure.fileSafety
        }
        let media = mediaCandidates(in: staging, mode: mode, fileManager: fileManager)
        guard media.count == 1,
              media[0].standardizedFileURL.resolvingSymlinksInPath()
                == reported.standardizedFileURL.resolvingSymlinksInPath() else {
            throw VideoDownloaderFailure.fileSafety
        }
        return reported
    }

    static func collisionSafeURL(for fileName: String,
                                 in destination: URL,
                                 fileExists: (String) -> Bool = FileManager.default.fileExists(atPath:)) -> URL {
        let source = URL(fileURLWithPath: fileName)
        let rawName = source.lastPathComponent
        let strippedName = String(rawName.drop(while: { $0 == "." }))
        let visibleName = strippedName.isEmpty ? "download" : strippedName
        let visibleSource = URL(fileURLWithPath: visibleName)
        let ext = visibleSource.pathExtension
        let base = visibleSource.deletingPathExtension().lastPathComponent
        var candidate = destination.appendingPathComponent(visibleName)
        var index = 2
        while fileExists(candidate.path) {
            let suffix = "\(base) (\(index))" + (ext.isEmpty ? "" : ".\(ext)")
            candidate = destination.appendingPathComponent(suffix)
            index += 1
        }
        return candidate
    }

    static func normalizeExtension(of media: URL,
                                   in staging: URL,
                                   for container: VideoDownloaderMediaContainer,
                                   fileManager: FileManager = .default) throws -> URL {
        guard isContained(media, in: staging) else { throw VideoDownloaderFailure.fileSafety }
        let expected = container.pathExtension
        guard media.pathExtension.lowercased() != expected else { return media }
        let normalized = media.deletingPathExtension().appendingPathExtension(expected)
        guard isContained(normalized, in: staging),
              !fileManager.fileExists(atPath: normalized.path) else {
            throw VideoDownloaderFailure.fileSafety
        }
        try fileManager.moveItem(at: media, to: normalized)
        return normalized
    }

    static func publish(_ staged: URL,
                        into destination: URL,
                        fileManager: FileManager = .default) throws -> URL {
        var attempt = 0
        while attempt < 10_000 {
            let target = collisionSafeURL(for: staged.lastPathComponent,
                                          in: destination,
                                          fileExists: fileManager.fileExists(atPath:))
            do {
                try fileManager.moveItem(at: staged, to: target)
                return target
            } catch CocoaError.fileWriteFileExists {
                attempt += 1
            }
        }
        throw VideoDownloaderFailure.fileSafety
    }

    static func cleanupStaleDirectories(in destination: URL,
                                        now: Date = Date(),
                                        fileManager: FileManager = .default) {
        guard let values = try? fileManager.contentsOfDirectory(at: destination,
                                                                includingPropertiesForKeys: [.contentModificationDateKey, .isDirectoryKey],
                                                                options: [.skipsSubdirectoryDescendants]) else { return }
        for url in values where url.lastPathComponent.hasPrefix(stagingPrefix) {
            guard let info = try? url.resourceValues(forKeys: [.contentModificationDateKey, .isDirectoryKey]),
                  info.isDirectory == true,
                  let date = info.contentModificationDate,
                  now.timeIntervalSince(date) >= staleAge,
                  let directoryID = stagingDirectoryID(url),
                  let markerData = try? Data(contentsOf: url.appendingPathComponent(ownerMarkerName)),
                  let ownerPID = ownerPID(from: markerData, expectedID: directoryID) else { continue }
            if VideoDownloaderProcessTree.isAlive(ownerPID) {
                continue
            }
            try? fileManager.removeItem(at: url)
        }
    }

    static func ownerMarkerData(id: UUID, pid: pid_t) -> Data {
        Data("\(ownerMarkerHeader)\n\(id.uuidString)\n\(pid)\n".utf8)
    }

    private static func stagingDirectoryID(_ url: URL) -> UUID? {
        let name = url.lastPathComponent
        guard name.hasPrefix(stagingPrefix) else { return nil }
        return UUID(uuidString: String(name.dropFirst(stagingPrefix.count)))
    }

    private static func ownerPID(from data: Data, expectedID: UUID) -> pid_t? {
        guard data.count <= 512, let value = String(data: data, encoding: .utf8) else { return nil }
        let lines = value.split(whereSeparator: { $0.isNewline }).map(String.init)
        guard lines.count == 3, lines[0] == ownerMarkerHeader,
              UUID(uuidString: lines[1]) == expectedID,
              let pid = pid_t(lines[2]), pid > 0 else { return nil }
        return pid
    }
}

enum VideoDownloaderDestinationSupport {
    enum AccessStatus: Equatable {
        case available, denied, unknown
    }

    static func configured(savedPath: String?, fileManager: FileManager = .default) -> URL {
        if let savedPath, !savedPath.isEmpty {
            return URL(fileURLWithPath: savedPath, isDirectory: true)
        }
        let fallback = fileManager.urls(for: .downloadsDirectory, in: .userDomainMask).first
            ?? fileManager.homeDirectoryForCurrentUser.appendingPathComponent("Downloads", isDirectory: true)
        return fallback
    }

    static func resolved(savedPath: String?,
                         downloads: URL,
                         isUsableDirectory: (URL) -> Bool,
                         prepareFallback: () -> Void = {}) -> URL {
        if let savedPath, !savedPath.isEmpty {
            let saved = URL(fileURLWithPath: savedPath, isDirectory: true)
            if isUsableDirectory(saved) { return saved }
        }
        prepareFallback()
        return downloads
    }

    static func resolved(savedPath: String?, fileManager: FileManager = .default) -> URL {
        let fallback = fileManager.urls(for: .downloadsDirectory, in: .userDomainMask).first
            ?? fileManager.homeDirectoryForCurrentUser.appendingPathComponent("Downloads", isDirectory: true)
        return resolved(savedPath: savedPath, downloads: fallback) { url in
            var isDirectory: ObjCBool = false
            return fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory)
                && isDirectory.boolValue && fileManager.isWritableFile(atPath: url.path)
        } prepareFallback: {
            if !fileManager.fileExists(atPath: fallback.path) {
                try? fileManager.createDirectory(at: fallback, withIntermediateDirectories: true)
            }
        }
    }

    /// Avoid prompting the user for folder creation permissions until they actually start a download.
    static func accessStatus(savedPath: String?,
                             fileManager: FileManager = .default) -> AccessStatus {
        let hasSavedPath = !(savedPath ?? "").isEmpty
        let destination = configured(savedPath: savedPath, fileManager: fileManager)
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: destination.path, isDirectory: &isDirectory) else {
            return hasSavedPath ? .unknown : .denied
        }
        guard isDirectory.boolValue else { return .denied }
        return fileManager.isWritableFile(atPath: destination.path) ? .available : .denied
    }
}

enum VideoDownloaderDependencySupport {
    static let minimumDenoVersion = [2, 3, 0]

    static func candidatePaths(for tool: VideoDownloaderTool,
                               home: URL,
                               pathEnvironment: String?) -> [String] {
        let fixed = ["/opt/homebrew/bin", "/usr/local/bin", "/opt/local/bin",
                     home.appendingPathComponent(".local/bin").path]
        let pathDirectories = (pathEnvironment ?? "").split(separator: ":").map(String.init)
        var seen = Set<String>()
        return (fixed + pathDirectories).compactMap { directory in
            let path = URL(fileURLWithPath: directory, isDirectory: true)
                .appendingPathComponent(tool.executableName).path
            return seen.insert(path).inserted ? path : nil
        }
    }

    static func brewPath(fileManager: FileManager = .default) -> String? {
        HomebrewCommandBuilder.candidatePaths.first {
            fileManager.isExecutableFile(atPath: $0)
        }
    }

    static func supportsRequiredCapabilities(_ tool: VideoDownloaderTool,
                                             output: Data) -> Bool {
        let value = String(decoding: output, as: UTF8.self)
        switch tool {
        case .ytDlp:
            // Verify required CLI flags to catch outdated yt-dlp binaries before they fail mid-download.
            let requiredOptions = [
                "--ignore-config", "--no-config-locations", "--no-plugin-dirs",
                "--no-cache-dir", "--no-cookies", "--no-cookies-from-browser",
                "--js-runtimes", "--output-na-placeholder", "--progress-delta", "--no-exec",
                "--cache-dir", "--remote-components", "--force-ipv4",
            ]
            return requiredOptions.allSatisfy(value.contains)
        case .deno:
            guard let firstLine = value.split(whereSeparator: \.isNewline).first else { return false }
            let components = firstLine.split(separator: " ")
            guard components.first?.lowercased() == "deno",
                  components.count >= 2 else { return false }
            let version = components[1].split(separator: ".").prefix(3).compactMap { token -> Int? in
                let digits = token.prefix(while: \.isNumber)
                return digits.isEmpty ? nil : Int(digits)
            }
            guard version.count == 3 else { return false }
            return !version.lexicographicallyPrecedes(minimumDenoVersion)
        case .ffmpeg, .ffprobe:
            return !output.isEmpty
        }
    }
}

enum VideoDownloaderProcessTree {
    static func descendants(of root: pid_t) -> [pid_t] {
        var visited = Set<pid_t>()
        var result: [pid_t] = []
        func visit(_ parent: pid_t) {
            for child in children(of: parent) where child > 0 && visited.insert(child).inserted {
                visit(child)
                result.append(child)
            }
        }
        visit(root)
        return result
    }

    static func snapshot(of root: pid_t) -> [pid_t] {
        guard root > 0 else { return [] }
        return descendants(of: root) + [root]
    }

    static func terminate(_ root: pid_t,
                          initiallyTracked: [pid_t]? = nil,
                          grace: TimeInterval = 0.2) {
        guard root > 0 else { return }
        var tracked = Set((initiallyTracked ?? snapshot(of: root)).filter { $0 > 0 })
        tracked.insert(root)

        func discoverAndTerminateNewDescendants() {
            let parents = tracked.filter(isAlive)
            var discovered: [pid_t] = []
            for parent in parents {
                for descendant in descendants(of: parent)
                    where descendant > 0 && tracked.insert(descendant).inserted {
                    discovered.append(descendant)
                }
            }
            for pid in discovered where isAlive(pid) { _ = Darwin.kill(pid, SIGTERM) }
        }

        for pid in tracked where isAlive(pid) { _ = Darwin.kill(pid, SIGTERM) }
        let deadline = Date().addingTimeInterval(grace)
        while Date() < deadline, tracked.contains(where: isAlive) {
            discoverAndTerminateNewDescendants()
            usleep(20_000)
        }
        discoverAndTerminateNewDescendants()
        for pid in tracked where isAlive(pid) { _ = Darwin.kill(pid, SIGKILL) }
        let killDeadline = Date().addingTimeInterval(0.4)
        while Date() < killDeadline, tracked.contains(where: isAlive) { usleep(10_000) }
    }

    static func isAlive(_ pid: pid_t) -> Bool {
        guard pid > 0 else { return false }
        if Darwin.kill(pid, 0) == 0 {
            var info = proc_bsdinfo()
            let size = Int32(MemoryLayout<proc_bsdinfo>.size)
            if proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, size) == size,
               Int32(info.pbi_status) == SZOMB {
                return false
            }
            return true
        }
        return errno == EPERM
    }

    static func isOwnedByCurrentUser(_ pid: pid_t) -> Bool {
        guard pid > 0 else { return false }
        var info = proc_bsdinfo()
        let size = Int32(MemoryLayout<proc_bsdinfo>.size)
        guard proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, size) == size else { return false }
        return pid_t(info.pbi_pid) == pid
            && info.pbi_uid == getuid()
            && Int32(info.pbi_status) != SZOMB
    }

    private static func children(of pid: pid_t) -> [pid_t] {
        let needed = proc_listchildpids(pid, nil, 0)
        guard needed > 0 else { return [] }
        var values = [pid_t](repeating: 0, count: Int(needed))
        let count = values.withUnsafeMutableBytes { buffer in
            proc_listchildpids(pid, buffer.baseAddress, Int32(buffer.count))
        }
        guard count > 0 else { return [] }
        return Array(values.prefix(Int(count))).filter { $0 > 0 }
    }
}
