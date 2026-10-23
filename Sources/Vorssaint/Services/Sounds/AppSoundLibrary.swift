// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// One sound a moment can play, stored as `source:name`. A bare name, as
/// the first release stored, is a macOS alert sound.
struct AppSoundChoice: Hashable, Identifiable {
    enum Source: String, CaseIterable {
        /// The short alert sounds in System Settings.
        case system
        /// The fuller tones Apple ships for messages and alerts.
        case tone
        /// Sounds in ~/Library/Sounds and /Library/Sounds.
        case user
        /// A sound macOS keeps elsewhere that one moment made before the
        /// Sounds page, offered only to that moment.
        case builtIn = "app"
    }

    /// The padlock as the Mac locks, and as it unlocks.
    static let padlockClosing = AppSoundChoice(source: .builtIn, name: "lock")
    static let padlockOpening = AppSoundChoice(source: .builtIn, name: "unlock")

    let source: Source
    /// A file name without extension for `system`, a path under the tone
    /// folder without extension for `tone`, a file name for `user`.
    let name: String

    init(source: Source, name: String) {
        self.source = source
        self.name = name
    }

    init?(id: String) {
        guard !id.isEmpty else { return nil }
        if let colon = id.firstIndex(of: ":"), let source = Source(rawValue: String(id[..<colon])) {
            let name = String(id[id.index(after: colon)...])
            guard !name.isEmpty else { return nil }
            self.init(source: source, name: name)
        } else {
            self.init(source: .system, name: id)
        }
    }

    var id: String { "\(source.rawValue):\(name)" }
}

/// The sounds on this Mac a moment can play, found where macOS keeps them.
/// Read on the main thread; `reload` picks up a sound added since.
final class AppSoundLibrary {
    static let shared = AppSoundLibrary()

    static let systemFolder = URL(fileURLWithPath: TextSnippetSupport.systemSoundsPath)
    /// Apple's alert tones. A private folder, so a release that moves it
    /// leaves the other sources.
    static let toneFolder = URL(fileURLWithPath:
        "/System/Library/PrivateFrameworks/ToneLibrary.framework/Versions/A/Resources/AlertTones")
    /// The tone collections offered, in menu order; loose files there are
    /// effects, not alerts.
    static let toneCollections = ["Modern", "EncoreInfinitum", "Classic"]
    static let soundExtensions: Set<String> = ["aiff", "aif", "caf", "m4r", "m4a", "wav", "mp3"]

    let systemFolder: URL
    let toneFolder: URL
    let userFolders: [URL]
    private(set) var files: [AppSoundChoice: URL] = [:]
    private(set) var choices: [AppSoundChoice] = []
    /// Found by `url(for:)` but never listed in `choices`.
    let builtIns: [AppSoundChoice: URL]

    init(systemFolder: URL = AppSoundLibrary.systemFolder, toneFolder: URL = AppSoundLibrary.toneFolder,
         userFolders: [URL] = AppSoundLibrary.userFolders(),
         builtIns: [AppSoundChoice: URL] = AppSoundLibrary.builtInSounds(), fileManager: FileManager = .default) {
        self.systemFolder = systemFolder
        self.toneFolder = toneFolder
        self.userFolders = userFolders
        self.builtIns = builtIns
        reload(fileManager: fileManager)
    }

    /// The padlock from SecurityInterface, or the alert sounds that stand
    /// in for it.
    static func builtInSounds() -> [AppSoundChoice: URL] {
        var sounds: [AppSoundChoice: URL] = [:]
        sounds[AppSoundChoice.padlockClosing] = NotchLockScreenSupport.soundURL(locking: true)
        sounds[AppSoundChoice.padlockOpening] = NotchLockScreenSupport.soundURL(locking: false)
        return sounds
    }

    static func userFolders(home: URL = FileManager.default.homeDirectoryForCurrentUser) -> [URL] {
        [home.appending(path: "Library/Sounds"), URL(fileURLWithPath: "/Library/Sounds")]
    }

    /// Where an added sound is copied.
    var addedFolder: URL? { userFolders.first }

    func reload(fileManager: FileManager = .default) {
        var files: [AppSoundChoice: URL] = [:]
        var order: [AppSoundChoice] = []
        func add(_ choice: AppSoundChoice, _ url: URL) {
            guard files[choice] == nil else { return }
            files[choice] = url
            order.append(choice)
        }
        func sounds(in folder: URL) -> [URL] {
            ((try? fileManager.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? [])
                .filter { Self.soundExtensions.contains($0.pathExtension.lowercased()) }
                .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
        }
        for url in sounds(in: systemFolder) {
            add(AppSoundChoice(source: .system, name: url.deletingPathExtension().lastPathComponent), url)
        }
        for collection in Self.toneCollections {
            for url in sounds(in: toneFolder.appending(path: collection)) {
                add(AppSoundChoice(source: .tone, name: "\(collection)/\(url.deletingPathExtension().lastPathComponent)"), url)
            }
        }
        for folder in userFolders {
            for url in sounds(in: folder) { add(AppSoundChoice(source: .user, name: url.lastPathComponent), url) }
        }
        self.files = files
        choices = order
    }

    func url(for choice: AppSoundChoice) -> URL? { files[choice] ?? builtIns[choice] }

    func choices(from source: AppSoundChoice.Source) -> [AppSoundChoice] {
        choices.filter { $0.source == source }
    }

    /// The name a person knows: macOS's own for alert sounds, the tone's
    /// name without its collection, a file's name without its extension.
    static func displayName(_ choice: AppSoundChoice, language: AppLanguage) -> String {
        switch choice.source {
        case .system:
            return AlertSoundStrings.displayName(for: choice.name, language: language)
        case .tone:
            let base = choice.name.split(separator: "/").last.map(String.init) ?? choice.name
            return base.replacingOccurrences(of: "-EncoreInfinitum", with: "")
        case .user:
            return (choice.name as NSString).deletingPathExtension
        case .builtIn:
            return FeatureStrings.padlockSound(language).name
        }
    }
}
