#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 Vorssaint

"""Exercise production lyrics lookup/downloader against LRCLIB, without app windows.

Sends 20 fixture tracks' title, artist, album and duration to
lrclib.net. Prints metadata/status only, never lyrics. Requires Swift on macOS.
"""

from pathlib import Path
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
// Include all seven desktop reproductions plus thirteen seeded library samples.
for row in Array(rows.suffix(7)) + Array(rows.prefix(13)) {
    let song = row["track"] as! [String: Any]
    let track = NotchMusicIdentity(NotchPlayback(
        track: Track(title: song["title"] as? String, artist: song["artist"] as? String,
                     album: song["album"] as? String), duration: song["duration"] as! Double))
    let probe = Probe(); probe.start(track)
    let deadline = Date().addingTimeInterval(30)
    while probe.state == .loading && Date() < deadline {
        _ = RunLoop.main.run(mode: .default, before: Date().addingTimeInterval(0.1))
    }
    let matched = probe.state == .ready
    let expected = row["expectedAfter"] as! Bool
    let ok = expected ? matched : probe.state == .unavailable
    let kind = matched ? ((probe.memory.lyrics?.lines.isEmpty ?? true) ? "plain" : "synced") : "\\(probe.state)"
    print(track.title + ": " + kind + (ok ? " (PASS)" : " (CHANGED/FAILED)"))
    if !ok { failures += 1 }
}
exit(failures == 0 ? 0 : 1)
"""


def main():
    service_path = "Sources/Vorssaint/Services/Notch/NotchLyricsService.swift"
    bodies = "".join(sourcegen.declaration(service_path, prefix) for prefix in [
        "    private func load(", "    private func acceptsResult(",
        "    private func finish(", "    private func search(",
    ])
    downloader = (ROOT / service_path).read_text().split("private final class NotchLyricsDownload:", 1)[1]
    probe = """import Foundation
final class Probe {
    enum State { case idle, consent, loading, unavailable, failed, ready }
    var state: State = .idle
    var memory = NotchLyricsMemory()
    var track: NotchMusicIdentity? { memory.track }
    var session: URLSession?
    var generation = UUID()
    var visible = true
    func start(_ track: NotchMusicIdentity) { memory.select(track); load(track) }
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
        return subprocess.run([str(executable), str(ROOT / "Tests/Fixtures/NotchLyricsCorpus.json")]).returncode


if __name__ == "__main__":
    sys.exit(main())
