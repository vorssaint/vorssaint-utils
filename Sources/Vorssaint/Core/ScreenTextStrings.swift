// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// Localized strings for the text capture's confirmation.
struct ScreenTextStrings {
    let ocrCopiedWithoutBreaks: String
    let ocrRemoveBreaks: String
    let ocrKeepBreaks: String
}

extension FeatureStrings {
    static func screenText(_ language: AppLanguage) -> ScreenTextStrings {
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

extension ScreenTextStrings {
    static let enUS = ScreenTextStrings(
        ocrCopiedWithoutBreaks: "Text copied without line breaks",
        ocrRemoveBreaks: "Remove line breaks",
        ocrKeepBreaks: "Keep line breaks"
    )

    static let ptBR = ScreenTextStrings(
        ocrCopiedWithoutBreaks: "Texto copiado sem quebras de linha",
        ocrRemoveBreaks: "Remover quebras de linha",
        ocrKeepBreaks: "Manter quebras de linha"
    )

    static let tr = ScreenTextStrings(
        ocrCopiedWithoutBreaks: "Metin satır sonları olmadan kopyalandı",
        ocrRemoveBreaks: "Satır sonlarını kaldır",
        ocrKeepBreaks: "Satır sonlarını koru"
    )

    static let ru = ScreenTextStrings(
        ocrCopiedWithoutBreaks: "Текст скопирован без переносов строк",
        ocrRemoveBreaks: "Убрать переносы строк",
        ocrKeepBreaks: "Сохранить переносы строк"
    )

    static let es = ScreenTextStrings(
        ocrCopiedWithoutBreaks: "Texto copiado sin saltos de línea",
        ocrRemoveBreaks: "Quitar saltos de línea",
        ocrKeepBreaks: "Mantener saltos de línea"
    )

    static let sk = ScreenTextStrings(
        ocrCopiedWithoutBreaks: "Text skopírovaný bez zalomení riadkov",
        ocrRemoveBreaks: "Odstrániť zalomenia riadkov",
        ocrKeepBreaks: "Ponechať zalomenia riadkov"
    )

    static let de = ScreenTextStrings(
        ocrCopiedWithoutBreaks: "Text ohne Zeilenumbrüche kopiert",
        ocrRemoveBreaks: "Zeilenumbrüche entfernen",
        ocrKeepBreaks: "Zeilenumbrüche behalten"
    )

    static let fr = ScreenTextStrings(
        ocrCopiedWithoutBreaks: "Texte copié sans retours à la ligne",
        ocrRemoveBreaks: "Supprimer les retours à la ligne",
        ocrKeepBreaks: "Garder les retours à la ligne"
    )

    static let it = ScreenTextStrings(
        ocrCopiedWithoutBreaks: "Testo copiato senza a capo",
        ocrRemoveBreaks: "Rimuovi gli a capo",
        ocrKeepBreaks: "Mantieni gli a capo"
    )

    static let ja = ScreenTextStrings(
        ocrCopiedWithoutBreaks: "改行なしでテキストをコピーしました",
        ocrRemoveBreaks: "改行を削除",
        ocrKeepBreaks: "改行を保持"
    )

    static let ko = ScreenTextStrings(
        ocrCopiedWithoutBreaks: "줄바꿈 없이 텍스트를 복사함",
        ocrRemoveBreaks: "줄바꿈 제거",
        ocrKeepBreaks: "줄바꿈 유지"
    )

    static let zhHans = ScreenTextStrings(
        ocrCopiedWithoutBreaks: "已拷贝文字（无换行）",
        ocrRemoveBreaks: "移除换行",
        ocrKeepBreaks: "保留换行"
    )

    static let zhTW = ScreenTextStrings(
        ocrCopiedWithoutBreaks: "已拷貝文字（無換行）",
        ocrRemoveBreaks: "移除換行",
        ocrKeepBreaks: "保留換行"
    )

    static let zhHK = ScreenTextStrings(
        ocrCopiedWithoutBreaks: "已拷貝文字（無換行）",
        ocrRemoveBreaks: "移除換行",
        ocrKeepBreaks: "保留換行"
    )

    static let uk = ScreenTextStrings(
        ocrCopiedWithoutBreaks: "Текст скопійовано без розривів рядків",
        ocrRemoveBreaks: "Прибрати розриви рядків",
        ocrKeepBreaks: "Зберегти розриви рядків"
    )
}
