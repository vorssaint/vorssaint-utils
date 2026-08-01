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
        let name: String
    }

    /// The emoji people actually reach for, in the order they are usually
    /// wanted. Kept deliberately short: a full set would bury every other
    /// kind of row, and the system's own picker exists for the long tail.
    private static let emojiCharacters = [
        "😀", "😃", "😄", "😁", "😆", "😅", "🤣", "😂", "🙂", "🙃", "😉", "😊",
        "😍", "🥰", "😘", "😗", "😜", "🤪", "🤔", "🤗", "🤩", "🥳", "😎", "🤓",
        "😐", "😑", "😶", "🙄", "😏", "😥", "😮", "😴", "😌", "😔", "😪", "🤤",
        "😭", "😢", "😤", "😠", "😡", "🤬", "🤯", "😳", "🥺", "😱", "😨", "😰",
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

    /// The curated set with its Unicode names resolved once.
    static let emoji: [Emoji] = {
        emojiCharacters.compactMap { character in
            guard let name = unicodeName(of: character) else { return nil }
            return Emoji(character: character, name: name)
        }
    }()

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
