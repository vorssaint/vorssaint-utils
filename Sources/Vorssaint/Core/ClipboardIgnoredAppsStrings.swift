// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

struct ClipboardIgnoredAppsStrings {
    let listTitle: String
    let addButton: String
    let removeButton: String
    let caption: String
}

extension FeatureStrings {
    static func clipboardIgnoredApps(_ language: AppLanguage) -> ClipboardIgnoredAppsStrings {
        switch language {
        case .enUS: return .enUS
        case .ptBR: return .ptBR
        case .tr: return .tr
        case .ru: return .ru
        case .es: return .es
        case .de: return .de
        case .fr: return .fr
        case .it: return .it
        case .ja: return .ja
        case .ko: return .ko
        case .zhHans: return .zhHans
        case .zhTW: return .zhTW
        case .zhHK: return .zhHK
        }
    }
}

extension ClipboardIgnoredAppsStrings {
    static let enUS = ClipboardIgnoredAppsStrings(
        listTitle: "Apps to skip",
        addButton: "Add an app…",
        removeButton: "Remove",
        caption: "Nothing you copy in these apps is saved to the history."
    )

    static let ptBR = ClipboardIgnoredAppsStrings(
        listTitle: "Apps para pular",
        addButton: "Adicionar app…",
        removeButton: "Remover",
        caption: "Nada que você copiar nesses apps é guardado no histórico."
    )

    static let tr = ClipboardIgnoredAppsStrings(
        listTitle: "Atlanacak uygulamalar",
        addButton: "Uygulama ekle…",
        removeButton: "Kaldır",
        caption: "Bu uygulamalarda kopyaladığınız hiçbir şey geçmişe kaydedilmez."
    )

    static let ru = ClipboardIgnoredAppsStrings(
        listTitle: "Приложения без записи",
        addButton: "Добавить приложение…",
        removeButton: "Удалить",
        caption: "Ничего скопированного в этих приложениях не попадает в историю."
    )

    static let es = ClipboardIgnoredAppsStrings(
        listTitle: "Apps que se saltan",
        addButton: "Añadir app…",
        removeButton: "Quitar",
        caption: "Nada de lo que copies en estas apps se guarda en el historial."
    )

    static let de = ClipboardIgnoredAppsStrings(
        listTitle: "Apps, die übersprungen werden",
        addButton: "App hinzufügen…",
        removeButton: "Entfernen",
        caption: "Nichts, was du in diesen Apps kopierst, landet im Verlauf."
    )

    static let fr = ClipboardIgnoredAppsStrings(
        listTitle: "Apps à ignorer",
        addButton: "Ajouter une app…",
        removeButton: "Retirer",
        caption: "Rien de ce que vous copiez dans ces apps n'est gardé dans l'historique."
    )

    static let it = ClipboardIgnoredAppsStrings(
        listTitle: "App da saltare",
        addButton: "Aggiungi app…",
        removeButton: "Rimuovi",
        caption: "Niente di quello che copi in queste app finisce nella cronologia."
    )

    static let ja = ClipboardIgnoredAppsStrings(
        listTitle: "記録しないApp",
        addButton: "Appを追加…",
        removeButton: "削除",
        caption: "これらのAppでコピーしたものは履歴に残りません。"
    )

    static let ko = ClipboardIgnoredAppsStrings(
        listTitle: "기록하지 않을 앱",
        addButton: "앱 추가…",
        removeButton: "제거",
        caption: "이 앱들에서 복사한 내용은 기록에 저장되지 않습니다."
    )

    static let zhHans = ClipboardIgnoredAppsStrings(
        listTitle: "不记录的 App",
        addButton: "添加 App…",
        removeButton: "移除",
        caption: "在这些 App 里拷贝的内容都不会存进历史。"
    )

    static let zhTW = ClipboardIgnoredAppsStrings(
        listTitle: "不記錄的 App",
        addButton: "加入 App…",
        removeButton: "移除",
        caption: "在這些 App 裡複製的內容都不會存進歷史。"
    )

    static let zhHK = ClipboardIgnoredAppsStrings(
        listTitle: "不記錄的 App",
        addButton: "加入 App…",
        removeButton: "移除",
        caption: "在這些 App 裡複製的內容都不會存進歷史。"
    )
}
