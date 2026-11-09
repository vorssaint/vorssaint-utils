// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

struct NotchCustomShortcutStrings {
    let title: String
    let add: String
    let edit: String
    let delete: String
    let shortcutName: String
    let symbol: String
    let shortcutNameHint: String
    let empty: String
    let invalidSymbol: String

    static func localized(_ language: AppLanguage) -> Self {
        switch language {
        case .enUS:
            return .init(title: "Custom Shortcuts", add: "Add Shortcut", edit: "Edit Shortcut", delete: "Delete",
                         shortcutName: "Shortcut name", symbol: "SF Symbol", shortcutNameHint: "Use the name shown in the Shortcuts app.",
                         empty: "Add a shortcut to show it in the Island and Explore.", invalidSymbol: "Enter a valid SF Symbol name.")
        case .ptBR:
            return .init(title: "Atalhos personalizados", add: "Adicionar Atalho", edit: "Editar Atalho", delete: "Apagar",
                         shortcutName: "Nome do atalho", symbol: "Símbolo SF", shortcutNameHint: "Use o nome exibido no app Atalhos.",
                         empty: "Adicione um atalho para exibi-lo na Ilha e em Explorar.", invalidSymbol: "Digite um nome de símbolo SF válido.")
        case .tr:
            return .init(title: "Özel Kestirmeler", add: "Kestirme Ekle", edit: "Kestirmeyi Düzenle", delete: "Sil",
                         shortcutName: "Kestirme adı", symbol: "SF Sembolü", shortcutNameHint: "Kestirmeler uygulamasında görünen adı kullanın.",
                         empty: "Adada ve Keşfet’te göstermek için bir kestirme ekleyin.", invalidSymbol: "Geçerli bir SF Sembolü adı girin.")
        case .ru:
            return .init(title: "Свои команды", add: "Добавить команду", edit: "Изменить команду", delete: "Удалить",
                         shortcutName: "Название команды", symbol: "Символ SF", shortcutNameHint: "Используйте название из приложения «Команды».",
                         empty: "Добавьте команду, чтобы она появилась на острове и в разделе «Обзор».", invalidSymbol: "Введите имя существующего символа SF.")
        case .es:
            return .init(title: "Atajos personalizados", add: "Añadir atajo", edit: "Editar atajo", delete: "Eliminar",
                         shortcutName: "Nombre del atajo", symbol: "Símbolo SF", shortcutNameHint: "Usa el nombre que aparece en la app Atajos.",
                         empty: "Añade un atajo para mostrarlo en la Isla y en Explorar.", invalidSymbol: "Introduce un nombre de símbolo SF válido.")
        case .sk:
            return .init(title: "Vlastné skratky", add: "Pridať skratku", edit: "Upraviť skratku", delete: "Odstrániť",
                         shortcutName: "Názov skratky", symbol: "SF symbol", shortcutNameHint: "Použite názov zobrazený v apke Skratky.",
                         empty: "Pridajte skratku, aby sa zobrazila na ostrove a v časti Preskúmať.", invalidSymbol: "Zadajte platný názov SF symbolu.")
        case .de:
            return .init(title: "Eigene Kurzbefehle", add: "Kurzbefehl hinzufügen", edit: "Kurzbefehl bearbeiten", delete: "Löschen",
                         shortcutName: "Kurzbefehlsname", symbol: "SF Symbol", shortcutNameHint: "Verwende den Namen aus der App Kurzbefehle.",
                         empty: "Füge einen Kurzbefehl hinzu, damit er in der Insel und unter „Entdecken“ erscheint.", invalidSymbol: "Gib einen gültigen SF-Symbolnamen ein.")
        case .fr:
            return .init(title: "Raccourcis personnalisés", add: "Ajouter un raccourci", edit: "Modifier le raccourci", delete: "Supprimer",
                         shortcutName: "Nom du raccourci", symbol: "Symbole SF", shortcutNameHint: "Utilisez le nom affiché dans l’app Raccourcis.",
                         empty: "Ajoutez un raccourci pour l’afficher dans l’îlot et Explorer.", invalidSymbol: "Saisissez un nom de symbole SF valide.")
        case .it:
            return .init(title: "Comandi rapidi personalizzati", add: "Aggiungi comando rapido", edit: "Modifica comando rapido", delete: "Elimina",
                         shortcutName: "Nome del comando rapido", symbol: "Simbolo SF", shortcutNameHint: "Usa il nome mostrato nell’app Comandi Rapidi.",
                         empty: "Aggiungi un comando rapido per mostrarlo nell’isola e in Esplora.", invalidSymbol: "Inserisci un nome di simbolo SF valido.")
        case .ja:
            return .init(title: "カスタムショートカット", add: "ショートカットを追加", edit: "ショートカットを編集", delete: "削除",
                         shortcutName: "ショートカット名", symbol: "SF シンボル", shortcutNameHint: "ショートカットアプリに表示される名前を入力します。",
                         empty: "ショートカットを追加すると、Island と Explore に表示されます。", invalidSymbol: "有効な SF シンボル名を入力してください。")
        case .ko:
            return .init(title: "사용자 설정 단축어", add: "단축어 추가", edit: "단축어 편집", delete: "삭제",
                         shortcutName: "단축어 이름", symbol: "SF 기호", shortcutNameHint: "단축어 앱에 표시된 이름을 사용하세요.",
                         empty: "단축어를 추가하면 Island와 탐색에 표시됩니다.", invalidSymbol: "올바른 SF 기호 이름을 입력하세요.")
        case .uk:
            return .init(title: "Власні команди", add: "Додати команду", edit: "Змінити команду", delete: "Вилучити",
                         shortcutName: "Назва команди", symbol: "Символ SF", shortcutNameHint: "Використайте назву з програми «Команди».",
                         empty: "Додайте команду, щоб вона з’явилася на острові та в розділі «Огляд».", invalidSymbol: "Введіть назву наявного символу SF.")
        case .zhHans:
            return .init(title: "自定义快捷指令", add: "添加快捷指令", edit: "编辑快捷指令", delete: "删除",
                         shortcutName: "快捷指令名称", symbol: "SF 符号", shortcutNameHint: "使用“快捷指令”App 中显示的名称。",
                         empty: "添加快捷指令后，它会显示在灵动岛和“探索”中。", invalidSymbol: "请输入有效的 SF 符号名称。")
        case .zhTW:
            return .init(title: "自訂捷徑", add: "加入捷徑", edit: "編輯捷徑", delete: "刪除",
                         shortcutName: "捷徑名稱", symbol: "SF 符號", shortcutNameHint: "請使用「捷徑」App 中顯示的名稱。",
                         empty: "加入捷徑後，它會顯示在動態島和「探索」中。", invalidSymbol: "請輸入有效的 SF 符號名稱。")
        case .zhHK:
            return .init(title: "自訂捷徑", add: "加入捷徑", edit: "編輯捷徑", delete: "刪除",
                         shortcutName: "捷徑名稱", symbol: "SF 符號", shortcutNameHint: "請使用「捷徑」App 中顯示的名稱。",
                         empty: "加入捷徑後，它會顯示在動態島和「探索」中。", invalidSymbol: "請輸入有效的 SF 符號名稱。")
        }
    }
}
