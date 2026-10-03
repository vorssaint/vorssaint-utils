// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// Provides the display names used by macOS for built-in alert sounds.
///
/// Apple's `AlertSounds.loctable` renames several of the files shipped in
/// `/System/Library/Sounds`. This table mirrors those names so the sound
/// picker matches macOS rather than exposing the underlying file names.
///
/// Languages not represented by a translated table intentionally use the
/// English names, matching Apple's localization data.
enum AlertSoundStrings {

    // MARK: - Public API

    /// Returns the macOS display name for a sound file.
    ///
    /// Sounds that do not have a renamed display name fall back to their
    /// original file name.
    static func displayName(
        for fileName: String,
        language: AppLanguage
    ) -> String {
        names(for: language)[fileName] ?? fileName
    }

    /// Sorts sound file names by their visible display name.
    ///
    /// Sorting uses the app's selected language rather than the Mac's
    /// current system language. If two display names are identical, the
    /// underlying file names provide a deterministic tie-breaker.
    static func sortedNames(
        _ fileNames: [String],
        language: AppLanguage
    ) -> [String] {
        let locale = Locale(identifier: language.rawValue)
        let table = names(for: language)

        return fileNames.sorted {
            let lhsDisplayName = table[$0] ?? $0
            let rhsDisplayName = table[$1] ?? $1

            let comparison = lhsDisplayName.compare(
                rhsDisplayName,
                options: [.caseInsensitive, .diacriticInsensitive],
                range: nil,
                locale: locale
            )

            switch comparison {
            case .orderedAscending:
                return true
            case .orderedDescending:
                return false
            case .orderedSame:
                return $0.localizedStandardCompare($1) == .orderedAscending
            }
        }
    }

    // MARK: - Localization

    private static func names(for language: AppLanguage) -> [String: String] {
        switch language {
        case .enUS:
            return english

        case .ptBR:
            return portugueseBrazil

        case .tr:
            return turkish

        case .ru:
            return russian

        case .es:
            return spanish

        case .sk:
            return slovak

        case .de:
            return german

        case .fr:
            return french

        case .it:
            return italian

        case .uk:
            return ukrainian

        // Apple's AlertSounds localization data keeps the English
        // display names for these locales.
        case .ja, .ko, .zhHans, .zhTW, .zhHK:
            return english
        }
    }

    // MARK: - English

    private static let english: [String: String] = [
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

    // MARK: - Portuguese (Brazil)

    private static let portugueseBrazil: [String: String] = [
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

    // MARK: - Turkish

    private static let turkish: [String: String] = [
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

    // MARK: - Russian

    private static let russian: [String: String] = [
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

    // MARK: - Spanish

    private static let spanish: [String: String] = [
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

    // MARK: - Slovak

    private static let slovak: [String: String] = [
        "Basso": "Mezzo",
        "Blow": "Vietor",
        "Bottle": "Štrk",
        "Frog": "Skok",
        "Funk": "Funky",
        "Glass": "Kryštál",
        "Hero": "Hrdinka",
        "Morse": "Pong",
        "Ping": "Sonar",
        "Pop": "Bublina",
        "Purr": "Trhnutie",
        "Sosumi": "Sonumi",
        "Submarine": "Ponorenie",
        "Tink": "Pípnutie",
    ]

    // MARK: - German

    private static let german: [String: String] = [
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

    // MARK: - French

    private static let french: [String: String] = [
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

    // MARK: - Italian

    private static let italian: [String: String] = [
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

    // MARK: - Ukrainian

    private static let ukrainian: [String: String] = [
        "Basso": "Мецо",
        "Blow": "Вітерець",
        "Bottle": "Галька",
        "Frog": "Стрибок",
        "Funk": "Модний",
        "Glass": "Кришталь",
        "Hero": "Героїня",
        "Morse": "Понг",
        "Ping": "Сонар",
        "Pop": "Булька",
        "Purr": "Щипок",
        "Sosumi": "Повідомлення",
        "Submarine": "Занурення",
        "Tink": "Тиць",
    ]
}
