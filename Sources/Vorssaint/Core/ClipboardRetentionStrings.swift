// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

struct ClipboardRetentionStrings {
    let title: String
    let forever: String
    let oneDay: String
    let daysFormat: String
    let caption: String

    func label(days: Int) -> String {
        switch days {
        case 0: return forever
        case 1: return oneDay
        default: return String(format: daysFormat, days)
        }
    }
}

extension FeatureStrings {
    static func clipboardRetention(_ language: AppLanguage) -> ClipboardRetentionStrings {
        switch language {
        case .enUS: return .enUS
        case .ptBR: return .ptBR
        case .tr: return .tr
        case .ru: return .ru
        case .es: return .es
        case .sk: return .sk
        case .de: return .de
        case .fr: return .fr
        case .it: return .it
        case .ja: return .ja
        case .ko: return .ko
        case .zhHans: return .zhHans
        case .zhTW: return .zhTW
        case .zhHK: return .zhHK
        case .uk: return .uk
        }
    }
}

extension ClipboardRetentionStrings {
    static let enUS = ClipboardRetentionStrings(
        title: "Keep items for",
        forever: "Forever",
        oneDay: "1 day",
        daysFormat: "%d days",
        caption: "Older items are removed even below the limit. Pinned items are always kept."
    )

    static let ptBR = ClipboardRetentionStrings(
        title: "Manter itens por",
        forever: "Sempre",
        oneDay: "1 dia",
        daysFormat: "%d dias",
        caption: "Itens mais antigos são removidos mesmo abaixo do limite. Itens fixados são sempre mantidos."
    )

    static let tr = ClipboardRetentionStrings(
        title: "Öğeleri sakla",
        forever: "Süresiz",
        oneDay: "1 gün",
        daysFormat: "%d gün",
        caption: "Daha eski öğeler sınırın altında olsa bile silinir. Sabitlenmiş öğeler her zaman saklanır."
    )

    static let ru = ClipboardRetentionStrings(
        title: "Хранить элементы",
        forever: "Всегда",
        oneDay: "1 день",
        daysFormat: "%d дней",
        caption: "Более старые элементы удаляются, даже если лимит не достигнут. Закреплённые элементы сохраняются всегда."
    )

    static let es = ClipboardRetentionStrings(
        title: "Conservar elementos",
        forever: "Siempre",
        oneDay: "1 día",
        daysFormat: "%d días",
        caption: "Los elementos más antiguos se eliminan aunque no se alcance el límite. Los fijados se conservan siempre."
    )

    static let sk = ClipboardRetentionStrings(
        title: "Uchovávať položky",
        forever: "Navždy",
        oneDay: "1 deň",
        daysFormat: "%d dní",
        caption: "Staršie položky sa odstránia, aj keď limit nie je dosiahnutý. Pripnuté položky sa uchovajú vždy."
    )

    static let de = ClipboardRetentionStrings(
        title: "Einträge behalten",
        forever: "Für immer",
        oneDay: "1 Tag",
        daysFormat: "%d Tage",
        caption: "Ältere Einträge werden auch unterhalb des Limits entfernt. Angeheftete Einträge bleiben immer erhalten."
    )

    static let fr = ClipboardRetentionStrings(
        title: "Conserver les éléments",
        forever: "Toujours",
        oneDay: "1 jour",
        daysFormat: "%d jours",
        caption: "Les éléments plus anciens sont supprimés même sous la limite. Les éléments épinglés sont toujours conservés."
    )

    static let it = ClipboardRetentionStrings(
        title: "Conserva elementi per",
        forever: "Sempre",
        oneDay: "1 giorno",
        daysFormat: "%d giorni",
        caption: "Gli elementi più vecchi vengono rimossi anche sotto il limite. Gli elementi fissati vengono sempre mantenuti."
    )

    static let ja = ClipboardRetentionStrings(
        title: "項目の保持期間",
        forever: "無期限",
        oneDay: "1日",
        daysFormat: "%d日",
        caption: "上限に達していなくても、古い項目は削除されます。ピン留めした項目は常に保持されます。"
    )

    static let ko = ClipboardRetentionStrings(
        title: "항목 보관 기간",
        forever: "영구",
        oneDay: "1일",
        daysFormat: "%d일",
        caption: "제한에 도달하지 않아도 오래된 항목은 삭제됩니다. 고정된 항목은 항상 유지됩니다."
    )

    static let zhHans = ClipboardRetentionStrings(
        title: "项目保留时间",
        forever: "永久",
        oneDay: "1 天",
        daysFormat: "%d 天",
        caption: "即使未达到上限，较早的项目也会被移除。已固定的项目始终保留。"
    )

    static let zhTW = ClipboardRetentionStrings(
        title: "項目保留時間",
        forever: "永久",
        oneDay: "1 天",
        daysFormat: "%d 天",
        caption: "即使未達上限，較舊的項目也會被移除。已釘選的項目一律保留。"
    )

    static let zhHK = ClipboardRetentionStrings(
        title: "項目保留時間",
        forever: "永久",
        oneDay: "1 日",
        daysFormat: "%d 日",
        caption: "即使未達上限，較舊的項目亦會被移除。已釘選的項目一律保留。"
    )

    static let uk = ClipboardRetentionStrings(
        title: "Зберігати елементи",
        forever: "Завжди",
        oneDay: "1 день",
        daysFormat: "%d днів",
        caption: "Старіші елементи видаляються, навіть якщо ліміт не досягнуто. Закріплені елементи зберігаються завжди."
    )
}
