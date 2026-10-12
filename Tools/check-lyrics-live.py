#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 Vorssaint

"""Exercise production lyrics lookup/downloader against LRCLIB, without app windows.

Sends selected fixture tracks' title, artist, album and duration to lrclib.net.
Song titles, artist names and albums may also be checked with musicbrainz.org. Prints metadata/status only, never lyrics. Requires Swift on macOS.
"""

from pathlib import Path
import argparse
import importlib.util
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[1]
sys.dont_write_bytecode = True
spec = importlib.util.spec_from_file_location("sourcegen", ROOT / "Tests/generate_sources.py")
sourcegen = importlib.util.module_from_spec(spec)
spec.loader.exec_module(sourcegen)

STUBS = """import Foundation
// Playback and settings dependencies are inert; networking and matching are production code.
struct UserDefaults {
    static let standard = UserDefaults()
    func bool(forKey: String) -> Bool { true }
}
struct Track {
    var title: String?; var artist: String?; var album: String?
    var appBundleIdentifier: String? = nil; var appPID: Int32? = nil
}
struct NotchPlayback {
    var track: Track; var duration: Double; var itemIdentifier: String? = nil
    var isPlaying = false; var hasPosition = false; var rate = 1.0
    var elapsed = 0.0; var sampledAt = Date()
    func position(at: Date) -> Double { elapsed }
}
enum NotchModule { case music }
enum NotchSupport {
    static func isEnabled(in: UserDefaults) -> Bool { true }
    static func modules(in: UserDefaults) -> [NotchModule] { [.music] }
}
enum AppFeature {
    case notchLyrics
    func isAvailable(in: UserDefaults) -> Bool { true }
}
enum DefaultsKey {
    static let notchLyricsEnabled = "enabled"; static let notchLyricsOnline = "online"
}
"""

MAIN = """import Foundation
let rows = try JSONSerialization.jsonObject(with: Data(contentsOf:
    URL(fileURLWithPath: CommandLine.arguments[1]))) as! [[String: Any]]
var failures = 0
let reportMetrics = CommandLine.arguments.contains("--metrics")
let probe = Probe()
// Run the selected metadata samples sequentially using one shared cache and rate limiter.
for row in rows {
    let song = row["track"] as! [String: Any]
    let track = NotchMusicIdentity(NotchPlayback(
        track: Track(title: song["title"] as? String, artist: song["artist"] as? String,
                     album: song["album"] as? String), duration: song["duration"] as! Double))
    let requestStart = probeRequests.count
    probe.start(track)
    let deadline = Date().addingTimeInterval(150)
    while probe.state == .loading && Date() < deadline {
        _ = RunLoop.main.run(mode: .default, before: Date().addingTimeInterval(0.1))
    }
    let matched = probe.state == .ready
    let expected = row["expectedAfter"] as! Bool
    let ok = expected ? matched : probe.state == .unavailable
    let kind = matched ? ((probe.memory.lyrics?.lines.isEmpty ?? true) ? "plain" : "synced") : "\\(probe.state)"
    print(track.title + ": " + kind + (ok ? " (PASS)" : " (CHANGED/FAILED)"))
    if reportMetrics {
        let requests = Array(probeRequests.dropFirst(requestStart))
        let metadata = requests.filter { $0.host == "musicbrainz.org" }.count
        print("  requests=\\(requests.count) metadata=\\(metadata)")
    }
    if !ok { failures += 1 }
}
exit(failures == 0 ? 0 : 1)
"""


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--all", action="store_true", help="check all corpus samples instead of the default 20")
    parser.add_argument("--metrics", action="store_true", help="print per-track request counts without lyrics")
    parser.add_argument("--title", action="append", help="Replay only these exact fixture titles (repeatable)")
    options = parser.parse_args()
    service_path = "Sources/Vorssaint/Services/Notch/NotchLyricsService.swift"
    bodies = "".join(sourcegen.declaration(service_path, prefix) for prefix in [
        "    private func load(", "    private func acceptsResult(",
        "    private func finish(", "    private func search(",
        "    private func resolveArtist(", "    private func requestArtistMetadata(",
        "    private func cacheArtist(", "    private func searchArtist(",
    ])
    downloader = (ROOT / service_path).read_text().split("private final class NotchLyricsDownload:", 1)[1]
    downloader = downloader.replace("        let configuration = URLSessionConfiguration.ephemeral", "        probeRequests.append(url)\n        let configuration = URLSessionConfiguration.ephemeral", 1)
    probe = """import Foundation
var probeRequests: [URL] = []
final class Probe {
    enum State { case idle, consent, loading, unavailable, failed, ready }
    var state: State = .idle
    var memory = NotchLyricsMemory()
    var track: NotchMusicIdentity? { memory.track }
    var session: URLSession?
    var generation = UUID()
    var visible = true
    var settledAttempt: (track: NotchMusicIdentity, failed: Bool, expires: Date)?
    var artistCache: [String: (identity: NotchLyricsSupport.ArtistIdentity?, failed: Bool, expires: Date)] = [:]
    var aliasWork: DispatchWorkItem?
    var lastAliasRequest: TimeInterval = 0
    func start(_ track: NotchMusicIdentity) { aliasWork?.cancel(); session?.invalidateAndCancel(); generation = UUID(); memory.select(track); load(track) }
""" + bodies + "}\nprivate final class NotchLyricsDownload:" + downloader
    with tempfile.TemporaryDirectory(prefix="vorssaint-lyrics-live-") as folder:
        directory = Path(folder)
        for name, content in [("Stubs.swift", STUBS), ("Probe.swift", probe), ("main.swift", MAIN)]:
            (directory / name).write_text(content)
        executable = directory / "probe"
        subprocess.run(["swiftc", str(directory / "Stubs.swift"),
                        str(ROOT / "Sources/Vorssaint/Services/Notch/NotchLyricsSupport.swift"),
                        str(directory / "Probe.swift"), str(directory / "main.swift"),
                        "-o", str(executable)], check=True)
        import json
        rows = []
        for filename in ["NotchLyricsCorpus.json", "NotchLyricsMultilingualCorpus.json", "NotchLyricsLessMainstreamCorpus.json"]:
            rows.extend(json.loads((ROOT / "Tests/Fixtures" / filename).read_text()))
        if options.title:
            rows = [row for row in rows if row["track"]["title"] in options.title]
            if not rows:
                parser.error("No fixture matches the requested titles")
        elif not options.all:
            rows = rows[:87][-7:] + rows[:13]
        fixture = directory / "corpus.json"
        fixture.write_text(json.dumps(rows, ensure_ascii=False))
        command = [str(executable), str(fixture)]
        if options.metrics:
            command.append("--metrics")
        return subprocess.run(command).returncode


if __name__ == "__main__":
    sys.exit(main())
