// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

struct NotchClipboardSizeStrings {
    let entrySize: String
    let compact: String
    let comfortable: String
    let hint: String
}

/// How tall a clipboard entry is on the island's page. Compact shows one or
/// two lines and opens up to the full entry when the pointer rests on it.
enum NotchClipboardCardSize: String, CaseIterable, Identifiable {
    case compact, comfortable
    var id: String { rawValue }

    /// How long the pointer rests on a compact entry before it opens.
    static let dwell: TimeInterval = 0.7

    /// How long the arrow keys rest on a compact entry before it opens: longer
    /// than the pointer, since keys cross many entries on their way.
    static let keyDwell: TimeInterval = 1.4

    /// An entry opened to show its text goes up to this many lines, then ends in an ellipsis.
    static let maximumOpenLines = 8
    static let openLineHeight: CGFloat = 16
    /// What an open entry needs besides its content: padding, spacing and the row of actions.
    static let openChrome: CGFloat = 48
    static let maximumOpenImage: CGFloat = 170
    static let minimumOpenImage: CGFloat = 80

    /// Lines the text takes at 12 points in `width`, counting each paragraph on its own.
    static func openLines(for text: String, width: CGFloat) -> Int {
        let perLine = max(8, Int(width / 6.4))
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false)
            .reduce(0) { $0 + max(1, ($1.count + perLine - 1) / perLine) }
        return min(maximumOpenLines, max(1, lines))
    }

    /// The height of an open text entry, which shows as much of it as fits in a few lines.
    static func openHeight(text: String, width: CGFloat) -> CGFloat {
        CGFloat(openLines(for: text, width: width)) * openLineHeight + openChrome
    }

    /// The height of an open image entry: the image at its own proportions, within a range.
    static func openHeight(aspectRatio: CGFloat?, width: CGFloat) -> CGFloat {
        let natural = max(1, width) / max(0.2, aspectRatio ?? 1.5)
        return min(maximumOpenImage, max(minimumOpenImage, natural)) + openChrome
    }

    static func current(in defaults: UserDefaults = .standard) -> NotchClipboardCardSize {
        NotchClipboardCardSize(rawValue: defaults.string(forKey: DefaultsKey.notchClipboardCardSize) ?? "") ?? .compact
    }
}

extension FeatureStrings {
    static func notchClipboardSize(_ language: AppLanguage) -> NotchClipboardSizeStrings {
        switch language {
        case .enUS: return NotchClipboardSizeStrings(
            entrySize: "Entry size",
            compact: "Compact",
            comfortable: "Comfortable",
            hint: "Compact entries show one or two lines and open up when the pointer rests on them.")
        case .ptBR: return NotchClipboardSizeStrings(
            entrySize: "Tamanho das entradas",
            compact: "Compacto",
            comfortable: "Confortável",
            hint: "As entradas compactas mostram uma ou duas linhas e se expandem quando o ponteiro fica sobre elas.")
        case .es: return NotchClipboardSizeStrings(
            entrySize: "Tamaño de las entradas",
            compact: "Compacto",
            comfortable: "Cómodo",
            hint: "Las entradas compactas muestran una o dos líneas y se amplían cuando el puntero se detiene sobre ellas.")
        case .sk: return NotchClipboardSizeStrings(
            entrySize: "Veľkosť položiek",
            compact: "Kompaktná",
            comfortable: "Pohodlná",
            hint: "Kompaktné položky zobrazujú jeden alebo dva riadky a rozbalia sa, keď sa na nich zastaví ukazovateľ.")
        case .de: return NotchClipboardSizeStrings(
            entrySize: "Größe der Einträge",
            compact: "Kompakt",
            comfortable: "Großzügig",
            hint: "Kompakte Einträge zeigen eine oder zwei Zeilen und öffnen sich, wenn der Zeiger darauf verweilt.")
        case .fr: return NotchClipboardSizeStrings(
            entrySize: "Taille des entrées",
            compact: "Compacte",
            comfortable: "Confortable",
            hint: "Les entrées compactes montrent une ou deux lignes et s’agrandissent quand le pointeur s’y arrête.")
        case .it: return NotchClipboardSizeStrings(
            entrySize: "Dimensione delle voci",
            compact: "Compatta",
            comfortable: "Comoda",
            hint: "Le voci compatte mostrano una o due righe e si espandono quando il puntatore vi si sofferma.")
        case .ru: return NotchClipboardSizeStrings(
            entrySize: "Размер записей",
            compact: "Компактный",
            comfortable: "Свободный",
            hint: "Компактные записи показывают одну-две строки и раскрываются, если задержать на них указатель.")
        case .tr: return NotchClipboardSizeStrings(
            entrySize: "Girdi boyutu",
            compact: "Kompakt",
            comfortable: "Rahat",
            hint: "Kompakt girdiler bir veya iki satır gösterir ve imleç üzerinde durunca genişler.")
        case .ja: return NotchClipboardSizeStrings(
            entrySize: "項目のサイズ",
            compact: "コンパクト",
            comfortable: "ゆったり",
            hint: "コンパクトな項目は1〜2行を表示し、ポインタを重ねたままにすると広がります。")
        case .ko: return NotchClipboardSizeStrings(
            entrySize: "항목 크기",
            compact: "컴팩트",
            comfortable: "여유",
            hint: "컴팩트 항목은 한두 줄을 보여 주며 포인터를 잠시 올려 두면 확장됩니다.")
        case .uk: return NotchClipboardSizeStrings(
            entrySize: "Розмір записів",
            compact: "Компактний",
            comfortable: "Просторий",
            hint: "Компактні записи показують один-два рядки й розгортаються, якщо затримати на них вказівник.")
        case .zhHans: return NotchClipboardSizeStrings(
            entrySize: "条目大小",
            compact: "紧凑",
            comfortable: "宽松",
            hint: "紧凑条目显示一到两行，指针停留时会展开。")
        case .zhTW: return NotchClipboardSizeStrings(
            entrySize: "項目大小",
            compact: "精簡",
            comfortable: "寬鬆",
            hint: "精簡項目顯示一到兩行，指標停留時會展開。")
        case .zhHK: return NotchClipboardSizeStrings(
            entrySize: "項目大小",
            compact: "精簡",
            comfortable: "寬鬆",
            hint: "精簡項目顯示一到兩行，指標停留時會展開。")
        }
    }
}
