// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// The emoji the command bar can type at the cursor, and the words that find
/// them. Pure Foundation, so the set and its names are pinned by the tests.
enum CommandBarEmoji {
    /// One emoji as the bar offers it: the character, and the words that find
    /// it. Names come from Unicode itself, so there is no list of names to
    /// maintain and nothing to fall out of date.
    struct Emoji {
        let character: String
        let identity: String
        let name: String
        let keywords: String
    }

    /// The emoji people reach for most, in the order they are usually wanted.
    /// They lead browsing and break equally good search ties; the Unicode set
    /// below supplies the long tail without displacing these familiar rows.
    private static let popularEmojiCharacters = [
        "😀", "😃", "😄", "😁", "😆", "😅", "🤣", "😂", "🙂", "🙃", "😉", "😊",
        "😍", "🥰", "😘", "😗", "😜", "🤪", "🤔", "🤗", "🤩", "🥳", "😎", "🤓",
        "😐", "😑", "😶", "🙄", "😏", "😥", "😮", "😴", "😌", "😔", "😪", "🤤",
        "😭", "😢", "😤", "😠", "😡", "🤬", "🤯", "😳", "🥺", "😱", "😨", "😰", "💀", "☠️",
        "🙏", "👍", "👎", "👌", "🤌", "✌️", "🤞", "🤟", "🤘", "👏", "🙌", "👐",
        "💪", "🫶", "👋", "🤝", "✍️", "💅", "👀", "🧠", "🫀", "🦾", "🦿", "👣",
        "❤️", "🧡", "💛", "💚", "💙", "💜", "🖤", "🤍", "💔", "❣️", "💕", "💞",
        "🔥", "✨", "⭐️", "🌟", "💫", "⚡️", "☀️", "🌤", "☁️", "🌧", "⛈", "❄️",
        "🎉", "🎊", "🎁", "🎂", "🍰", "🍕", "🍔", "🍟", "🌮", "🍣", "🍎", "🍌",
        "☕️", "🍺", "🍻", "🥂", "🍷", "🧉", "🥤", "🍫", "🍪", "🍩", "🥐", "🧀",
        "🚀", "✈️", "🚗", "🚕", "🚲", "🛴", "🏠", "🏢", "🌍", "🌎", "🌏", "🗺",
        "💻", "🖥", "⌨️", "🖱", "📱", "⌚️", "🎧", "📷", "🔋", "💾", "🖨", "📡",
        "📁", "📂", "📄", "📌", "📎", "🔖", "🔍", "🔒", "🔓", "🔑", "🛠", "⚙️",
        "✅", "❌", "⚠️", "❓", "❗️", "💡", "🔔", "🔕", "♻️", "🆗", "🆕", "🔝",
        "🐶", "🐱", "🐭", "🐰", "🦊", "🐻", "🐼", "🐨", "🦁", "🐮", "🐷", "🐸",
        "🌱", "🌲", "🌳", "🌴", "🌵", "🌷", "🌸", "🌹", "🌺", "🌻", "🍀", "🍁",
        "⏰", "⏳", "📅", "📈", "📉", "📊", "💰", "💳", "🏆", "🥇", "🎯", "🧩",
    ]

    /// Human search terms that Unicode's formal names do not carry. Keep this
    /// deliberately compact: names cover literal searches, aliases cover the
    /// common intent words people actually type into an emoji picker.
    private static let aliases: [String: String] = [
        "😂": "haha lol roflmao laugh laughing tears funny",
        "🤣": "haha lol rofl roflmao laugh laughing funny",
        "😊": "happy smile blush",
        "🥰": "love affection hearts",
        "😘": "kiss love",
        "😎": "cool sunglasses",
        "🤔": "think thinking hmm",
        "🙄": "eyeroll whatever",
        "😭": "cry crying sad sob",
        "🥺": "please pleading puppy eyes",
        "😡": "angry mad rage",
        "🤬": "swear cursing angry",
        "🤷": "idk shrug whatever",
        "💀": "dead death dying skeleton halloween",
        "☠️": "dead death danger poison pirate",
        "🙏": "appreciate please thanks thank thx you pray prayer high five",
        "👍": "yes good approve like okay",
        "👎": "no bad disapprove dislike",
        "👌": "okay perfect good",
        "👏": "clap applause congrats congratulations",
        "🙌": "hooray celebrate praise",
        "🫶": "love heart hands",
        "👀": "look looking eyes see",
        "❤️": "love heart red",
        "💔": "heartbreak broken heart sad",
        "🔥": "fire hot lit trending",
        "✨": "sparkle sparkles magic clean",
        "🎉": "party celebrate celebration congrats congratulations",
        "✅": "check done yes complete success",
        "❌": "cross no wrong error fail",
        "⚠️": "warning caution alert",
        "💡": "idea lightbulb tip",
        "🚀": "launch ship rocket fast",
    ]

    /// Popular emoji first, followed by every single-scalar emoji in Unicode
    /// sorted by name. Resolved once, so searching the larger set does not
    /// repeat Unicode-name work on each keystroke.
    static let emoji: [Emoji] = {
        var seen: Set<String> = []
        func makeEmoji(_ character: String, aliasCharacter: String? = nil) -> Emoji? {
            let canonical = canonicalCharacter(character)
            guard seen.insert(canonical).inserted else { return nil }
            guard let name = unicodeName(of: character) else { return nil }
            return Emoji(character: character,
                         identity: aliasCharacter ?? character,
                         name: name,
                         keywords: aliases[aliasCharacter ?? character] ?? "")
        }

        let popular = popularEmojiCharacters.compactMap { character in
            makeEmoji(emojiPresentation(of: character), aliasCharacter: character)
        }
        let longTail = (0...0x1FAFF).compactMap(Unicode.Scalar.init)
            .compactMap { scalar -> String? in
                let isKeycapBase = scalar.value == 0x23
                    || scalar.value == 0x2A
                    || (0x30...0x39).contains(scalar.value)
                guard scalar.properties.isEmoji,
                      !scalar.properties.isEmojiModifier,
                      !(0x1F1E6...0x1F1FF).contains(scalar.value),
                      !(0x1F9B0...0x1F9B3).contains(scalar.value),
                      !isKeycapBase else { return nil }
                // Text-default emoji need the selector to display as emoji,
                // while native emoji-presentation scalars stand on their own.
                return String(scalar)
                    + (scalar.properties.isEmojiPresentation ? "" : "\u{FE0F}")
            }
            .compactMap { makeEmoji($0) }
            .sorted { $0.name < $1.name }
        return popular + longTail
    }()

    /// Single text-default scalars need the selector to render as emoji. Keep
    /// existing sequences intact because their presentation is intentional.
    private static func emojiPresentation(of character: String) -> String {
        let scalars = character.unicodeScalars
        guard scalars.count == 1,
              let scalar = scalars.first,
              scalar.properties.isEmoji,
              !scalar.properties.isEmojiPresentation else { return character }
        return character + "\u{FE0F}"
    }

    /// Variation selectors change presentation, not identity. Folding them
    /// keeps a popular text-style sequence from returning once more as the
    /// equivalent bare Unicode scalar in the long tail.
    private static func canonicalCharacter(_ character: String) -> String {
        String(character.unicodeScalars.filter { $0.value != 0xFE0F && $0.value != 0xFE0E })
    }

    /// "❤️" becomes "heavy black heart". Foundation exposes the Unicode name
    /// table, so the words that find an emoji cost nothing to ship.
    private static func unicodeName(of character: String) -> String? {
        // Skin tone and variation selectors carry names of their own that
        // would only add noise.
        let stripped = String(character.unicodeScalars.filter {
            $0.value != 0xFE0F && $0.value != 0xFE0E
        })
        guard let raw = stripped.applyingTransform(StringTransform("Any-Name"), reverse: false)
        else { return nil }
        // The transform yields "\N{HEAVY BLACK HEART}" per scalar.
        let names = raw.components(separatedBy: "\\N{")
            .dropFirst()
            .map { $0.components(separatedBy: "}").first ?? "" }
            .filter { !$0.isEmpty && !$0.hasPrefix("ZERO WIDTH") }
        guard !names.isEmpty else { return nil }
        return names.joined(separator: " ").lowercased()
    }
}
