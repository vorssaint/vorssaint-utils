// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation
import SwiftUI

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

    /// The five skin tones variants Unicode offers, and the yellow default.
    /// Raw values are the stored preference, so they never change.
    enum SkinTone: String, CaseIterable, Identifiable {
        case none = ""
        case light
        case mediumLight
        case medium
        case mediumDark
        case dark

        var id: String { rawValue }

        /// The modifier that carries this tone, or nothing for the default.
        var modifier: Unicode.Scalar? {
            switch self {
            case .none: return nil
            case .light: return Unicode.Scalar(0x1F3FB)
            case .mediumLight: return Unicode.Scalar(0x1F3FC)
            case .medium: return Unicode.Scalar(0x1F3FD)
            case .mediumDark: return Unicode.Scalar(0x1F3FE)
            case .dark: return Unicode.Scalar(0x1F3FF)
            }
        }

        /// The same raised hand in each tone. A picker of these shows what the
        /// choice changes.
        var swatch: String { CommandBarEmoji.applying(self, to: "✋") }
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

    /// Single-scalar bases can carry a tone, except the legacy family emoji:
    /// it has Emoji_Modifier_Base but no RGI skin-tone sequences. Multi-scalar
    /// sequences need placement rules of their own and are left unchanged.
    static func acceptsSkinTone(_ character: String) -> Bool {
        let base = canonicalCharacter(character).unicodeScalars
        guard base.count == 1, let scalar = base.first else { return false }
        return scalar.value != 0x1F46A && scalar.properties.isEmojiModifierBase
    }

    /// The emoji wearing a tone. The variation selector goes with it, because
    /// a modifier already means emoji presentation and the pickers on the Mac
    /// produce the sequence without it.
    static func applying(_ tone: SkinTone, to character: String) -> String {
        guard let modifier = tone.modifier, acceptsSkinTone(character) else { return character }
        return canonicalCharacter(character) + String(modifier)
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

/// One tile of the emoji grid, as big as the person wants their emoji.
/// Raw values are the stored preference, so they never change.
enum CommandBarEmojiTileSize: String, CaseIterable, Identifiable {
    case small
    case medium
    case large

    var id: String { rawValue }

    /// The glyph size inside a tile. The medium step matches the feel of the
    /// launchers people know.
    var glyphSize: CGFloat {
        switch self {
        case .small: return 20
        case .medium: return 28
        case .large: return 38
        }
    }

    /// The tile's own width, glyph plus caption plus breathing room. The grid
    /// derives its cell size from this, so a chip never splits mid-render.
    var tileSize: CGFloat {
        switch self {
        case .small: return 70
        case .medium: return 92
        case .large: return 122
        }
    }

    /// How a stored preference reads back. Anything unknown is the default,
    /// because a tile size is a look and a wrong spelling must not blank it.
    static func resolved(raw: String?) -> CommandBarEmojiTileSize {
        CommandBarEmojiTileSize(rawValue: raw ?? "") ?? .medium
    }

    /// Columns the viewport can hold after the grid's side insets. The width
    /// is the scroll view's offered width, including any legacy scroller inset.
    static func columns(availableWidth: CGFloat,
                        tileSize: CommandBarEmojiTileSize,
                        horizontalPadding: CGFloat = 32,
                        spacing: CGFloat = 6) -> Int {
        let contentWidth = max(0, availableWidth - horizontalPadding)
        return max(1, Int((contentWidth + spacing) / (tileSize.tileSize + spacing)))
    }

    /// Ideal grid height, including inter-row spacing and its vertical inset.
    /// The view caps this at the list ceiling and lets the rest scroll.
    static func contentHeight(itemCount: Int,
                              columns: Int,
                              tileHeight: CGFloat,
                              rowSpacing: CGFloat = 8,
                              verticalPadding: CGFloat = 16,
                              headerHeight: CGFloat = 0) -> CGFloat {
        guard itemCount > 0, columns > 0 else { return 0 }
        let rows = (itemCount + columns - 1) / columns
        return CGFloat(rows) * tileHeight
            + CGFloat(max(0, rows - 1)) * rowSpacing
            + verticalPadding
            + headerHeight
    }

    /// Where one grid step lands, pure so the tests can pin it. Rows sit in
    /// reading order; `columns` is what the view reports. A walk off the top
    /// or the bottom stops at the edge, and a vertical move into a last row
    /// that ends early holds the column instead of sliding to its end.
    static func gridTarget(from at: Int, dx: Int, dy: Int, columns: Int, count: Int) -> Int {
        guard columns > 0, count > 0 else { return at }
        let row = at / columns
        let column = at % columns
        if dx == 0, dy != 0 {
            let targetRow = row + dy
            guard targetRow >= 0 else { return 0 }
            let targetLength = min(columns, count - targetRow * columns)
            guard targetLength > 0 else { return count - 1 }
            return targetRow * columns + min(column, targetLength - 1)
        }
        if dy == 0, dx != 0 {
            let nextColumn = column + dx
            // A row that ends early reports its own extent, not the column
            // count: a step past its end holds where it is instead of naming
            // a tile the grid never laid out.
            guard nextColumn >= 0,
                  nextColumn < min(columns, count - row * columns) else { return at }
            return row * columns + nextColumn
        }
        // Both axes at once never happens from a keyboard: one press, one
        // axis. The clamped arithmetic keeps even that honest.
        return max(0, min(count - 1, at + dx + dy * columns))
    }
}

/// A modified horizontal arrow belongs to the field when it has text. With an
/// empty field it still walks the grid, including while the grid's hotkey
/// modifiers are being released.
enum CommandBarEmojiGridNavigation {
    static func consumesHorizontalArrow(gridIsNavigable: Bool,
                                       modifiersPresent: Bool,
                                       queryIsEmpty: Bool) -> Bool {
        gridIsNavigable && (!modifiersPresent || queryIsEmpty)
    }
}
