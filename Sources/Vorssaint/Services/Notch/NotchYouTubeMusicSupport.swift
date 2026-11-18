// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// YouTube Music in Safari, or added from Safari to the Dock, tells macOS only
/// the song that plays: no queue, and nothing before a song starts. Its page
/// is read through Accessibility instead, which needs no port, plug-in or
/// browser setting. WebKit names each element by its DOM classes, and YouTube
/// Music scopes every element with its component's name ("song-title
/// style-scope ytmusic-player-queue-item"), so the rows are found by those
/// names rather than by their place on the page.
enum NotchYouTubeMusicSupport {
    static let host = "music.youtube.com"
    static let maximumRows = 20
    /// How far before a row's title its cover and play button may sit.
    static let lookBehind = 8

    /// The play button over a row's cover names the song ("Play Song"), which
    /// tells it apart from the menu of the row before.
    static func playButton(for title: String, in buttons: [(index: Int, ref: Int, text: String)], at index: Int) -> Int? {
        let song = fold(title)
        guard !song.isEmpty else { return nil }
        return buttons.last { index - $0.index <= lookBehind && fold($0.text).contains(song) }?.ref
    }

    /// One element of the page, in the order the page reads, each after the
    /// elements inside it.
    struct Entry: Equatable {
        var role: String
        var classes: Set<String> = []
        /// What the element says: its own label, or the text inside it.
        var text: String = ""
        /// An image's source.
        var url: URL? = nil
        /// Where the reader keeps the element, to press it later.
        var ref: Int = 0

        func has(_ name: String) -> Bool { classes.contains(name) }
    }

    struct Row: Equatable, Identifiable {
        let id: String
        let title: String
        let subtitle: String
        let duration: Double
        let imageURL: URL?
        /// The element to press to play the row.
        let action: Int
    }

    /// Case, accents, width and spacing set aside, so the page's title and
    /// the one macOS reports compare.
    static func fold(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: nil)
            .split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    /// "3:45" or "1:02:03", in seconds; anything else is unknown.
    static func duration(_ text: String) -> Double {
        let parts = text.trimmingCharacters(in: .whitespaces).split(separator: ":")
        guard (2...3).contains(parts.count) else { return 0 }
        var total = 0.0
        for part in parts {
            guard let value = Int(part), value >= 0, part.count <= 2 || part == parts.first else { return 0 }
            total = total * 60 + Double(value)
        }
        return total
    }

    /// The bundles that show YouTube Music through WebKit: Safari, and web
    /// apps added from it to the Dock.
    static func isCandidate(bundleIdentifier: String?) -> Bool {
        guard let id = bundleIdentifier else { return false }
        return ["com.apple.Safari", "com.apple.SafariTechnologyPreview"].contains(id)
            || id.hasPrefix("com.apple.Safari.WebApp.")
    }

    static func isYouTubeMusic(_ url: URL?) -> Bool {
        url?.scheme?.lowercased() == "https" && url?.host?.lowercased() == host
    }

    /// The covers worth loading come from YouTube's own image hosts, over HTTPS.
    static func isCoverURL(_ url: URL?) -> Bool {
        guard let url, url.scheme?.lowercased() == "https", let host = url.host?.lowercased() else { return false }
        return ["ytimg.com", "googleusercontent.com", "ggpht.com"].contains { host == $0 || host.hasSuffix("." + $0) }
    }

    // MARK: Up next

    /// The songs of the player's queue, in order. Its autoplay songs follow
    /// the queue's own in the same list, as they play after it.
    struct QueueParser {
        private(set) var rows: [(title: String, subtitle: String, duration: Double, imageURL: URL?, action: Int)] = []
        private var index = 0
        private var lastImage: (index: Int, url: URL)?
        private var buttons: [(index: Int, ref: Int, text: String)] = []

        private static let scope = "ytmusic-player-queue-item"

        mutating func feed(_ entry: Entry) {
            index += 1
            if entry.role == "AXImage", let url = entry.url, isCoverURL(url) {
                lastImage = (index, url)
                return
            }
            if entry.role == "AXButton" {
                buttons = buttons.suffix(lookBehind) + [(index, entry.ref, entry.text)]
                return
            }
            guard entry.has(Self.scope) else { return }
            if entry.has("song-title") {
                let title = entry.text.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !title.isEmpty else { return }
                // The thumbnail and its play button come just before the title.
                let image = lastImage.flatMap { index - $0.index <= lookBehind ? $0.url : nil }
                // Without its play button, the title takes the click the row would.
                let button = playButton(for: title, in: buttons, at: index)
                rows.append((title, "", 0, image, button ?? entry.ref))
                lastImage = nil
                buttons = []
            } else if entry.has("byline"), let last = rows.indices.last, rows[last].subtitle.isEmpty {
                rows[last].subtitle = entry.text.trimmingCharacters(in: .whitespacesAndNewlines)
            } else if entry.has("duration"), let last = rows.indices.last, rows[last].duration == 0 {
                rows[last].duration = duration(entry.text)
            }
        }

        /// The songs after the one playing, found by its title. Nil when the
        /// queue does not hold that song: the page plays something else, or
        /// its queue could not be read.
        func upcoming(after title: String) -> [Row]? {
            let current = fold(title)
            guard !current.isEmpty, let playing = rows.firstIndex(where: { fold($0.title) == current }) else { return nil }
            return rows[(playing + 1)...].prefix(maximumRows).enumerated().map { offset, row in
                Row(id: "ytm-queue-\(offset + 1)", title: row.title, subtitle: row.subtitle,
                    duration: row.duration, imageURL: row.imageURL, action: row.action)
            }
        }
    }

    // MARK: Listen again

    /// YouTube Music's own name for the shelf, in the languages it is shown
    /// in most often, folded.
    static let listenAgainTitles: Set<String> = Set([
        "Listen again", "Volver a escuchar", "Escuchar de nuevo", "Ouvir novamente", "Ouça novamente",
        "Ouvir de novo", "Nochmal anhören", "Noch einmal anhören", "Erneut anhören", "À réécouter",
        "Réécouter", "Ascolta di nuovo", "Riascolta", "Слушать снова", "Послушать ещё раз", "Послушать снова",
        "Слухати знову", "Послухати ще раз", "Tekrar dinle", "Yeniden dinle", "もう一度聴く", "もう一度聞く",
        "다시 듣기", "再次收听", "再听一次", "再次收聽", "再聽一次", "Vypočujte si znova", "Počúvať znova",
        "Znova si vypočuť", "Opnieuw luisteren", "Posłuchaj ponownie", "Dengarkan lagi", "Nghe lại",
        "फिर से सुनें", "Lyssna igen", "Lyt igen", "Hør igjen", "Kuuntele uudelleen",
    ].map(fold))

    /// The cards of the home page's Listen again shelf. Feeding stops once
    /// the shelf has ended, so the rest of the page is not read.
    struct ListenAgainParser {
        private(set) var rows: [Row] = []
        private(set) var finished = false
        private var started = false
        private var index = 0
        private var lastImage: (index: Int, url: URL)?
        private var buttons: [(index: Int, ref: Int, text: String)] = []
        /// A card's title sits in a link, read just before the title itself.
        private var lastLink: (index: Int, ref: Int, text: String)?

        private static let cardScopes = ["ytmusic-two-row-item-renderer", "ytmusic-responsive-list-item-renderer"]
        private static let headerScopes = ["ytmusic-carousel-shelf-basic-header-renderer", "ytmusic-shelf-renderer",
                                           "ytmusic-carousel-shelf-renderer"]

        private func isHeading(_ entry: Entry) -> Bool {
            guard !entry.has("strapline"), !entry.text.isEmpty else { return false }
            if entry.role == "AXHeading" { return true }
            return entry.has("title") && Self.headerScopes.contains(where: entry.has)
        }

        /// Returns true once nothing more is needed.
        @discardableResult
        mutating func feed(_ entry: Entry) -> Bool {
            guard !finished else { return true }
            index += 1
            if isHeading(entry) {
                if listenAgainTitles.contains(fold(entry.text)) {
                    started = true
                } else if started, !rows.isEmpty {
                    finished = true
                }
                return finished
            }
            guard started else { return false }
            if entry.role == "AXImage", let url = entry.url, isCoverURL(url) {
                lastImage = (index, url)
                return false
            }
            if entry.role == "AXLink" {
                lastLink = (index, entry.ref, entry.text)
                return false
            }
            if entry.role == "AXButton" {
                buttons = buttons.suffix(lookBehind) + [(index, entry.ref, entry.text)]
                return false
            }
            guard Self.cardScopes.contains(where: entry.has) else { return false }
            if entry.has("title") {
                let title = entry.text.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !title.isEmpty else { return false }
                let image = lastImage.flatMap { index - $0.index <= lookBehind ? $0.url : nil }
                // A card without a play button opens its page from the title's link.
                let link = lastLink.flatMap { index - $0.index <= 3 && fold($0.text) == fold(title) ? $0.ref : nil }
                let action = playButton(for: title, in: buttons, at: index) ?? link ?? -1
                rows.append(Row(id: "ytm-again-\(rows.count + 1)", title: title, subtitle: "", duration: 0,
                                imageURL: image, action: action))
                lastImage = nil
                lastLink = nil
                buttons = []
            } else if entry.has("subtitle") || entry.has("flex-column") || entry.has("secondary-flex-columns"),
                      let last = rows.indices.last, rows[last].subtitle.isEmpty {
                let row = rows[last]
                let text = entry.text.trimmingCharacters(in: .whitespacesAndNewlines)
                guard fold(text) != fold(row.title) else { return false }
                rows[last] = Row(id: row.id, title: row.title, subtitle: text, duration: 0,
                                 imageURL: row.imageURL, action: row.action)
            }
            if rows.count >= maximumRows { finished = true }
            return finished
        }

        /// The cards that can be played or opened.
        var playable: [Row] { rows.filter { $0.action >= 0 } }
    }
}
