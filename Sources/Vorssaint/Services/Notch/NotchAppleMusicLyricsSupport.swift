// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation
import os

enum NotchLyricsProvider: String, CaseIterable {
    case lrclib, appleMusic

    static func selected(in defaults: UserDefaults = .standard) -> Self {
        Self(rawValue: defaults.string(forKey: DefaultsKey.notchLyricsProvider) ?? "") ?? .lrclib
    }
}

enum NotchAppleMusicLyricsSupport {
    private static let log = Logger(subsystem: Bundle.main.bundleIdentifier ?? "vorssaint", category: "AppleMusicLyrics")
    static func isSelected(in defaults: UserDefaults = .standard) -> Bool {
        NotchLyricsSupport.isEnabled(in: defaults) && NotchLyricsProvider.selected(in: defaults) == .appleMusic
    }

    static func canLoad(_ track: NotchMusicIdentity?, in defaults: UserDefaults = .standard) -> Bool {
        track?.bundle == "com.apple.Music" && isSelected(in: defaults) && NotchLyricsSupport.onlineEnabled(in: defaults)
    }

    static func validCatalogID(_ value: String?) -> String? {
        guard let value, !value.isEmpty, value.utf8.count <= 20,
              value.utf8.allSatisfy({ (48...57).contains($0) }), value.contains(where: { $0 != "0" }) else { return nil }
        return value
    }

    static func matches(_ song: [String: Any], track: NotchMusicIdentity, searching: Bool) -> Bool {
        guard validCatalogID(song["id"] as? String) != nil, let attributes = song["attributes"] as? [String: Any],
              normalized(attributes["name"] as? String) == normalized(track.title),
              let duration = (attributes["durationInMillis"] as? NSNumber)?.doubleValue, duration.isFinite,
              abs(duration / 1000 - track.duration) <= 2 else { return false }
        if searching {
            guard normalized(attributes["artistName"] as? String) == normalized(track.artist),
                  track.album.isEmpty || normalized(NotchLyricsSupport.catalogAlbum(attributes["albumName"] as? String ?? ""))
                    == normalized(NotchLyricsSupport.catalogAlbum(track.album)) else { return false }
        }
        return true
    }

    private static func normalized(_ value: String?) -> String {
        (value ?? "").precomposedStringWithCompatibilityMapping.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    /// Filter only Apple's public web developer token, never a subscriber token.
    /// The Apple server verifies its signature when handling the request.
    static func publicTokenExpiration(_ source: String, now: Date = .now) -> Date? {
        guard source.utf8.count <= 4096 else { return nil }
        let parts = source.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 3 else { return nil }
        var payload = String(parts[1]).replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        payload += String(repeating: "=", count: (4 - payload.count % 4) % 4)
        guard let data = Data(base64Encoded: payload),
              let claims = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              claims["iss"] as? String == "AMPWebPlay", let expiration = claims["exp"] as? Double,
              expiration.isFinite, expiration > now.timeIntervalSince1970 + 60 else { return nil }
        return Date(timeIntervalSince1970: expiration)
    }

    /// Apple delivers TTML, including songs with no timing. LRC is accepted
    /// only if the Apple response supplies it; no second provider is queried.
    static func decode(_ source: String, duration: Double) -> NotchLyrics? {
        decode(Data(source.utf8), duration: duration)
    }

    /// Keep original XML bytes so file BOMs and encoding declarations agree.
    static func decode(_ data: Data, duration: Double) -> NotchLyrics? {
        guard data.count <= NotchLyricsSupport.maximumBytes, duration.isFinite, duration > 0 else { return nil }
        let trimmed = String(data: data, encoding: .utf8)?.trimmingCharacters(in:
            .whitespacesAndNewlines.union(CharacterSet(charactersIn: "\u{FEFF}")))
        let prefix = Array(data.prefix(4))
        let utf16 = prefix.starts(with: [0xFF, 0xFE]) || prefix.starts(with: [0xFE, 0xFF])
            || prefix.starts(with: [0, 0x3C, 0, 0x3F]) || prefix.starts(with: [0x3C, 0, 0x3F, 0])
        if !utf16, trimmed?.hasPrefix("<") != true {
            guard let source = String(data: data, encoding: .utf8) else { return nil }
            let lines = NotchLyricsSupport.parse(source, duration: duration)
            return lines.isEmpty ? nil : NotchLyrics(lines: lines, plain: "", instrumental: false)
        }
        let reader = AppleMusicTTMLReader(duration: duration)
        let parser = XMLParser(data: data)
        parser.shouldProcessNamespaces = true
        parser.shouldResolveExternalEntities = false
        parser.externalEntityResolvingPolicy = .never
        parser.delegate = reader
        guard parser.parse(), reader.isTTML else {
            let reason = reader.failure
            Self.log.error("TTML rejected: \(reason, privacy: .public)")
            return nil
        }
        if reader.result == nil { Self.log.error("TTML rejected: empty-lyrics") }
        return reader.result
    }

    static func time(_ source: String?) -> Double? {
        guard let source, !source.isEmpty else { return nil }
        if source.hasSuffix("ms") { return nonnegative(String(source.dropLast(2))).map { $0 / 1000 } }
        if source.hasSuffix("s") { return nonnegative(String(source.dropLast())) }
        // Apple's web service also emits bare decimal seconds (e.g. 12.345)
        // rather than the clock values used in its delivery specification.
        if !source.contains(":") { return nonnegative(source) }
        let parts = source.split(separator: ":", omittingEmptySubsequences: false)
        guard (2...3).contains(parts.count),
              let seconds = nonnegative(String(parts.last!)), seconds < 60,
              let minutes = nonnegative(String(parts[parts.count - 2])), minutes.rounded() == minutes,
              parts.count == 2 || minutes < 60 else { return nil }
        let hours = parts.count == 3 ? nonnegative(String(parts[0])) : 0
        guard let hours, hours.rounded() == hours else { return nil }
        let value = hours * 3600 + minutes * 60 + seconds
        return value.isFinite ? value : nil
    }

    private static func nonnegative(_ source: String) -> Double? {
        guard !source.isEmpty, source.utf8.allSatisfy({ (48...57).contains($0) || $0 == 46 }),
              let value = Double(source), value.isFinite, value >= 0 else { return nil }
        return value
    }
}

private final class AppleMusicTTMLReader: NSObject, XMLParserDelegate {
    struct Line { let begin: Double?; let end: Double?; let text: String; let syllables: [NotchLyricSyllable]; let voices: [NotchLyricVoice] }
    struct Timing: Equatable { let begin: Double; let end: Double; let background: Bool }
    struct Piece { let text: String; let timing: Timing?; let agent: String?; let background: Bool; var lineBreak = false }
    struct VoiceKey: Hashable { let agent: String?; let background: Bool }
    let duration: Double
    var isTTML = false
    var failure = "xml-syntax"
    private var path: [String] = []
    private var elements = 0
    private var bodyDepth: Int?
    private var paragraphDepth: Int?
    private var words = ""
    private var begin: Double?
    private var end: Double?
    private var spans: [(Double, Double)] = []
    private var spanStack: [(depth: Int, timing: Timing?, background: Bool)] = []
    private var pieces: [Piece] = []
    private var lines: [Line] = []
    private var untimed = false
    private var agentPath: [String] = []
    private var backgroundPath: [Bool] = []
    private var voiceSides: [String: NotchLyricSide] = [:]
    private var personCount = 0
    private var writers: [String] = []
    private var writerDepth: Int?
    private var writerText = ""

    init(duration: Double) { self.duration = duration }

    var result: NotchLyrics? {
        guard !lines.isEmpty else { return nil }
        let plain = lines.map(\.text).joined(separator: "\n")
        guard plain.utf8.count <= NotchLyricsSupport.maximumBytes else { return nil }
        // Never invent timestamps for an untimed or partially timed document.
        guard !untimed, lines.allSatisfy({ $0.begin != nil && $0.end != nil }) else {
            return NotchLyrics(lines: [], plain: plain, instrumental: false, writers: writers)
        }
        let ordered = lines.enumerated().sorted {
            if $0.element.begin == $1.element.begin { return $0.offset < $1.offset }
            return $0.element.begin! < $1.element.begin!
        }.map(\.element)
        var timeline: [NotchLyricLine] = []
        var activeUntil = 0.0
        var index = 0
        while index < ordered.count {
            let start = ordered[index].begin!
            if !timeline.isEmpty, activeUntil < start { timeline.append(.init(time: activeUntil, text: "")) }
            var texts: [String] = []
            var syllables: [NotchLyricSyllable] = []
            var textOffset = 0
            var lineEnd = start
            var voices: [NotchLyricVoice] = []
            repeat {
                for syllable in ordered[index].syllables {
                    syllables.append(.init(range: NSRange(location: textOffset + syllable.range.location,
                                                         length: syllable.range.length),
                                           begin: syllable.begin, end: syllable.end, background: syllable.background))
                }
                texts.append(ordered[index].text)
                voices += ordered[index].voices
                textOffset += ordered[index].text.utf16.count + 1
                lineEnd = max(lineEnd, ordered[index].end!)
                activeUntil = max(activeUntil, ordered[index].end!)
                index += 1
            } while index < ordered.count && ordered[index].begin == start
            timeline.append(.init(time: start, text: texts.joined(separator: "\n"), end: lineEnd,
                                  syllables: syllables, voices: voices))
        }
        if activeUntil < duration { timeline.append(.init(time: activeUntil, text: "")) }
        return NotchLyrics(lines: timeline, plain: plain, instrumental: false, writers: writers)
    }

    func parser(_ parser: XMLParser, didStartElement element: String, namespaceURI: String?,
                qualifiedName: String?, attributes: [String: String]) {
        path.append(element)
        let agent = attributes["ttm:agent"] ?? agentPath.last ?? ""
        agentPath.append(agent.utf8.count <= 128 ? agent : "")
        backgroundPath.append(attributes["ttm:role"] == "x-bg" || backgroundPath.last == true)
        elements += 1
        guard path.count <= 32, elements <= 16_000, attributes.count <= 32 else { failure = "xml-complexity"; parser.abortParsing(); return }
        if path.count == 1 {
            isTTML = element == "tt" && namespaceURI == "http://www.w3.org/ns/ttml"
            guard isTTML else { failure = "root-namespace"; parser.abortParsing(); return }
            untimed = attributes["itunes:timing"] == "None"
        }
        if element == "body", path.count == 2 { bodyDepth = path.count }
        if element == "songwriter", bodyDepth == nil, path.contains("songwriters") {
            writerDepth = path.count
            writerText = ""
        }
        if element == "agent", namespaceURI == "http://www.w3.org/ns/ttml#metadata",
           let id = attributes["xml:id"], !id.isEmpty, id.utf8.count <= 128, voiceSides[id] == nil {
            switch attributes["type"] {
            case "group": voiceSides[id] = .center
            case "other": voiceSides[id] = .trailing
            default: voiceSides[id] = personCount.isMultiple(of: 2) ? .leading : .trailing; personCount += 1
            }
        }
        guard bodyDepth != nil else { return }
        if element == "p" {
            guard paragraphDepth == nil, lines.count < NotchLyricsSupport.maximumLines else { failure = "paragraph-shape"; parser.abortParsing(); return }
            paragraphDepth = path.count
            words = ""
            spans = []
            spanStack = []
            pieces = []
            begin = NotchAppleMusicLyricsSupport.time(attributes["begin"])
            end = NotchAppleMusicLyricsSupport.time(attributes["end"])
            if attributes["begin"] != nil || attributes["end"] != nil {
                guard let begin, let end else { failure = "paragraph-time-format"; parser.abortParsing(); return }
                guard begin < end, end <= duration + 2 else { failure = "paragraph-time-bounds"; parser.abortParsing(); return }
            }
        } else if element == "span", paragraphDepth != nil {
            let background = backgroundPath.last == true
            var timing = spanStack.last?.timing
            if attributes["begin"] != nil || attributes["end"] != nil {
                guard let start = NotchAppleMusicLyricsSupport.time(attributes["begin"]),
                      let finish = NotchAppleMusicLyricsSupport.time(attributes["end"]),
                      start < finish, finish <= duration + 2,
                      begin.map({ start >= $0 }) ?? true, end.map({ finish <= $0 }) ?? true else {
                    failure = "syllable-time-bounds"; parser.abortParsing(); return
                }
                spans.append((start, finish))
                timing = Timing(begin: start, end: finish, background: background)
            }
            spanStack.append((path.count, timing, background))
        } else if element == "br", namespaceURI == "http://www.w3.org/ns/ttml", paragraphDepth != nil {
            words += "\n"
            let agent = agentPath.last ?? ""
            pieces.append(Piece(text: "", timing: nil, agent: agent.isEmpty ? nil : agent,
                                background: backgroundPath.last == true, lineBreak: true))
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        if writerDepth != nil, writerText.utf8.count + string.utf8.count <= 1024 { writerText += string }
        guard paragraphDepth != nil else { return }
        guard string.utf8.count <= NotchLyricsSupport.maximumBytes - words.utf8.count else { parser.abortParsing(); return }
        words += string
        let agent = agentPath.last ?? ""
        pieces.append(Piece(text: string, timing: spanStack.last?.timing,
                            agent: agent.isEmpty ? nil : agent, background: backgroundPath.last == true))
    }

    func parser(_ parser: XMLParser, didEndElement element: String, namespaceURI: String?, qualifiedName: String?) {
        if writerDepth == path.count {
            let name = writerText.trimmingCharacters(in: .whitespacesAndNewlines)
            if !name.isEmpty, !writers.contains(name), writers.count < 64 { writers.append(name) }
            writerDepth = nil
        }
        if paragraphDepth == path.count {
            let (text, syllables) = normalizedPieces()
            let start = begin ?? spans.map(\.0).min()
            let finish = end ?? spans.map(\.1).max()
            if !text.isEmpty, start.map({ $0 <= duration }) ?? true {
                lines.append(.init(begin: start, end: finish.map { min(duration, $0) }, text: text,
                                   syllables: untimed ? [] : syllables,
                                   voices: untimed ? [] : normalizedVoices(begin: start, end: finish)))
            }
            paragraphDepth = nil
        }
        if spanStack.last?.depth == path.count { spanStack.removeLast() }
        if bodyDepth == path.count { bodyDepth = nil }
        path.removeLast()
        agentPath.removeLast()
        backgroundPath.removeLast()
    }

    /// Collapse XML whitespace while retaining the exact UTF-16 ranges TextKit
    /// uses. Adjacent spans can be syllables of one word; no spaces are invented.
    private func normalizedPieces(_ selected: [Piece]? = nil) -> (String, [NotchLyricSyllable]) {
        var text = ""
        var result: [NotchLyricSyllable] = []
        var pendingSpace = false
        var pendingBreaks = 0
        for piece in selected ?? pieces {
            if piece.lineBreak {
                if !text.isEmpty { pendingBreaks += 1 }
                pendingSpace = false
                continue
            }
            var start: Int?
            var length = 0
            for character in piece.text {
                if character.isWhitespace { pendingSpace = !text.isEmpty; continue }
                if pendingBreaks > 0 {
                    text += String(repeating: "\n", count: pendingBreaks)
                    pendingBreaks = 0
                    pendingSpace = false
                } else if pendingSpace { text += " "; pendingSpace = false }
                if start == nil { start = text.utf16.count }
                text.append(character)
                length = text.utf16.count - start!
            }
            if let timing = piece.timing, let start, length > 0 {
                let next = NotchLyricSyllable(range: NSRange(location: start, length: length),
                    begin: timing.begin, end: timing.end, background: piece.background)
                if let last = result.last, last.begin == next.begin, last.end == next.end,
                   last.background == next.background, NSMaxRange(last.range) == next.range.location {
                    result[result.count - 1] = .init(range: NSRange(location: last.range.location, length: last.range.length + next.range.length),
                                                   begin: last.begin, end: last.end, background: last.background)
                } else { result.append(next) }
            }
        }
        return (text, result)
    }

    private func normalizedVoices(begin: Double?, end: Double?) -> [NotchLyricVoice] {
        let mainAgent = pieces.first(where: { !$0.background && $0.agent != nil })?.agent
        var ordered: [VoiceKey] = []
        var grouped: [VoiceKey: [Piece]] = [:]
        for piece in pieces {
            let key = VoiceKey(agent: piece.agent ?? mainAgent, background: piece.background)
            if grouped[key] == nil { ordered.append(key) }
            grouped[key, default: []].append(piece)
        }
        return ordered.compactMap { key in
            let (text, syllables) = normalizedPieces(grouped[key])
            guard !text.isEmpty, let start = syllables.map(\.begin).min() ?? begin,
                  let finish = syllables.map(\.end).max() ?? end, finish > start else { return nil }
            let side: NotchLyricSide
            if let agent = key.agent {
                if voiceSides[agent] == nil {
                    voiceSides[agent] = personCount.isMultiple(of: 2) ? .leading : .trailing
                    personCount += 1
                }
                side = voiceSides[agent] ?? .leading
            } else { side = .leading }
            return NotchLyricVoice(text: text, time: start, end: min(duration, finish), agent: key.agent,
                                   side: side, background: key.background, syllables: syllables)
        }
    }

    func parser(_ parser: XMLParser, foundInternalEntityDeclarationWithName name: String, value: String?) { parser.abortParsing() }
    func parser(_ parser: XMLParser, foundExternalEntityDeclarationWithName name: String, publicID: String?, systemID: String?) { parser.abortParsing() }
}
