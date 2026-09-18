// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// Display names for the built-in alert sound files, matching what macOS
/// itself has shown in Sound settings since Big Sur: several no longer
/// match the file name in /System/Library/Sounds (Tink shows as Boop, Ping
/// as Sonar, and so on). Sourced from Apple's own AlertSounds.loctable so
/// the picker reads the same as System Settings instead of drifting from
/// it, and translated only for the thirteen languages this app supports;
/// a name outside this table (a sound this Mac ships that macOS never
/// renamed) falls back to the file name unchanged.
enum AlertSoundStrings {
    static func displayName(for fileName: String, language: AppLanguage) -> String {
        table(for: language)[fileName] ?? fileName
    }

    /// `fileNames` ordered by what each shows in `language`, using that
    /// language's own collation rather than whatever locale the system
    /// happens to be in, since the app's own language can differ from it.
    /// The picker lists what people read, so its order has to sort by that,
    /// not by the file names underneath. Ties (none today, across any
    /// language) fall back to the file name so the order stays deterministic.
    static func sortedNames(_ fileNames: [String], language: AppLanguage) -> [String] {
        let locale = Locale(identifier: language.rawValue)
        return fileNames.sorted { lhs, rhs in
            let comparison = displayName(for: lhs, language: language)
                .compare(displayName(for: rhs, language: language), options: [], range: nil, locale: locale)
            return comparison == .orderedSame ? lhs < rhs : comparison == .orderedAscending
        }
    }

    private static func table(for language: AppLanguage) -> [String: String] {
        switch language {
        case .enUS: return enUS
        case .ptBR: return ptBR
        case .tr: return tr
        case .ru: return ru
        case .es: return es
        case .de: return de
        case .fr: return fr
        case .it: return it
        // Apple's own loctable keeps the English names for these
        // languages too, rather than translating them.
        case .ja, .ko, .zhHans, .zhTW, .zhHK: return enUS
        }
    }

    private static let enUS: [String: String] = [
        "Basso": "Mezzo",
        "Blow": "Breeze",
        "Bottle": "Pebble",
        "Frog": "Jump",
        "Funk": "Funky",
        "Glass": "Crystal",
        "Hero": "Heroine",
        "Morse": "Pong",
        "Ping": "Sonar",
        "Pop": "Bubble",
        "Purr": "Pluck",
        "Sosumi": "Sonumi",
        "Submarine": "Submerge",
        "Tink": "Boop",
    ]

    private static let ptBR: [String: String] = [
        "Basso": "Médio",
        "Blow": "Brisa",
        "Bottle": "Seixo",
        "Frog": "Pulo",
        "Funk": "Funky",
        "Glass": "Cristal",
        "Hero": "Heroína",
        "Morse": "Morse",
        "Ping": "Sonar",
        "Pop": "Balão",
        "Purr": "Ronrom",
        "Sosumi": "Sonumi",
        "Submarine": "Submarino",
        "Tink": "Tinido",
    ]

    private static let tr: [String: String] = [
        "Basso": "Mezzo",
        "Blow": "Esinti",
        "Bottle": "Çakıl Taşı",
        "Frog": "Zıpla",
        "Funk": "Funky",
        "Glass": "Kristal",
        "Hero": "Heroine",
        "Morse": "Pong",
        "Ping": "Sonar",
        "Pop": "Balon",
        "Purr": "Pluck",
        "Sosumi": "Sonumi",
        "Submarine": "Submerge",
        "Tink": "Boop",
    ]

    private static let ru: [String: String] = [
        "Basso": "Меццо",
        "Blow": "Бриз",
        "Bottle": "Галька",
        "Frog": "Пружина",
        "Funk": "Фанк",
        "Glass": "Кристалл",
        "Hero": "Героиня",
        "Morse": "Понг",
        "Ping": "Сонар",
        "Pop": "Пузырьки",
        "Purr": "Щипок",
        "Sosumi": "Сонуми",
        "Submarine": "Погружение",
        "Tink": "Капля",
    ]

    private static let es: [String: String] = [
        "Basso": "Mezzo",
        "Blow": "Brisa",
        "Bottle": "Piedrecita",
        "Frog": "Salto",
        "Funk": "Funky",
        "Glass": "Cristal",
        "Hero": "Líder",
        "Morse": "Pong",
        "Ping": "Sonda",
        "Pop": "Burbuja",
        "Purr": "Punteo",
        "Sosumi": "Sonumi",
        "Submarine": "Inmersión",
        "Tink": "Boop",
    ]

    private static let de: [String: String] = [
        "Basso": "Mezzo",
        "Blow": "Brise",
        "Bottle": "Kiesel",
        "Frog": "Springen",
        "Funk": "Funky",
        "Glass": "Kristall",
        "Hero": "Heldin",
        "Morse": "Pong",
        "Ping": "Sonar",
        "Pop": "Blase",
        "Purr": "Zupfen",
        "Sosumi": "Sonumi",
        "Submarine": "Untertauchen",
        "Tink": "Buup",
    ]

    private static let fr: [String: String] = [
        "Basso": "Mezzo",
        "Blow": "Brise",
        "Bottle": "Galet",
        "Frog": "Saut",
        "Funk": "Funky",
        "Glass": "Cristal",
        "Hero": "Héroïne",
        "Morse": "Pong",
        "Ping": "Sonar",
        "Pop": "Bulle",
        "Purr": "Pincement",
        "Sosumi": "Sonumi",
        "Submarine": "Submersible",
        "Tink": "Boop",
    ]

    private static let it: [String: String] = [
        "Basso": "Mezzo",
        "Blow": "Brezza",
        "Bottle": "Ciottolo",
        "Frog": "Salto",
        "Funk": "Funky",
        "Glass": "Cristallo",
        "Hero": "Eroe",
        "Morse": "Pong",
        "Ping": "Sonar",
        "Pop": "Fumetto",
        "Purr": "Pizzico",
        "Sosumi": "Sonumi",
        "Submarine": "Immersione",
        "Tink": "Boop",
    ]
}
