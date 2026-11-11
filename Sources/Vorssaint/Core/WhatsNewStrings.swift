// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

struct WhatsNewStrings {
    /// The %@ is the version the person updated from, such as 3.4.1.
    let updatedFromFormat: String
    let newFeatures: String
    /// Installed features that changed in this update.
    let yourFeatures: String
    let notInstalled: String
    /// The three kinds head a feature's list of changes and label the counts on
    /// the overview, so they must read well both above a list and under a number.
    let kindNew: String
    let kindChanged: String
    let kindFixed: String
    /// VoiceOver value for a sidebar row whose unread dot is showing.
    let updated: String
    let chooseFeatureHint: String
    /// Checkbox in the pre-install window footer, beside Cancel and Download and install.
    let skipPreviewCheckbox: String
    let showPreviewToggle: String
    let showPreviewCaption: String
}

extension FeatureStrings {
    static func whatsNew(_ language: AppLanguage) -> WhatsNewStrings {
        switch language {
        case .enUS:
            return WhatsNewStrings(
                updatedFromFormat: "Updated from %@",
                newFeatures: "New features",
                yourFeatures: "Your features",
                notInstalled: "Not installed",
                kindNew: "New",
                kindChanged: "Changed",
                kindFixed: "Fixed",
                updated: "Updated",
                chooseFeatureHint: "Choose a feature to see what changed in it.",
                skipPreviewCheckbox: "Don’t show what’s new before updating",
                showPreviewToggle: "Show what’s new before updating",
                showPreviewCaption: "What changed in your features still appears after each update.")
        case .ptBR:
            return WhatsNewStrings(
                updatedFromFormat: "Atualizado da versão %@",
                newFeatures: "Novos recursos",
                yourFeatures: "Seus recursos",
                notInstalled: "Não instalados",
                kindNew: "Novidades",
                kindChanged: "Mudanças",
                kindFixed: "Correções",
                updated: "Atualizado",
                chooseFeatureHint: "Escolha um recurso para ver o que mudou nele.",
                skipPreviewCheckbox: "Não mostrar novidades antes de atualizar",
                showPreviewToggle: "Mostrar novidades antes de atualizar",
                showPreviewCaption: "O que mudou nos seus recursos continua aparecendo após cada atualização.")
        case .tr:
            return WhatsNewStrings(
                updatedFromFormat: "%@ sürümünden güncellendi",
                newFeatures: "Yeni özellikler",
                yourFeatures: "Özellikleriniz",
                notInstalled: "Yüklü olmayanlar",
                kindNew: "Yeni",
                kindChanged: "Değişen",
                kindFixed: "Düzeltilen",
                updated: "Güncellendi",
                chooseFeatureHint: "Neyin değiştiğini görmek için bir özellik seçin.",
                skipPreviewCheckbox: "Güncellemeden önce yenilikleri gösterme",
                showPreviewToggle: "Güncellemeden önce yenilikleri göster",
                showPreviewCaption: "Özelliklerinizdeki değişiklikler her güncellemeden sonra yine gösterilir.")
        case .ru:
            return WhatsNewStrings(
                updatedFromFormat: "Обновлено с версии %@",
                newFeatures: "Новые функции",
                yourFeatures: "Ваши функции",
                notInstalled: "Не установлено",
                kindNew: "Новое",
                kindChanged: "Изменено",
                kindFixed: "Исправлено",
                updated: "Обновлено",
                chooseFeatureHint: "Выберите функцию, чтобы увидеть, что в ней изменилось.",
                skipPreviewCheckbox: "Не показывать изменения перед обновлением",
                showPreviewToggle: "Показывать изменения перед обновлением",
                showPreviewCaption: "Изменения в ваших функциях по-прежнему показываются после каждого обновления.")
        case .es:
            return WhatsNewStrings(
                updatedFromFormat: "Actualizado desde la versión %@",
                newFeatures: "Nuevas funciones",
                yourFeatures: "Tus funciones",
                notInstalled: "No instaladas",
                kindNew: "Novedades",
                kindChanged: "Cambios",
                kindFixed: "Correcciones",
                updated: "Actualizada",
                chooseFeatureHint: "Elige una función para ver sus cambios.",
                skipPreviewCheckbox: "No mostrar novedades antes de actualizar",
                showPreviewToggle: "Mostrar novedades antes de actualizar",
                showPreviewCaption: "Los cambios en tus funciones seguirán apareciendo después de cada actualización.")
        case .sk:
            return WhatsNewStrings(
                updatedFromFormat: "Aktualizované z verzie %@",
                newFeatures: "Nové funkcie",
                yourFeatures: "Vaše funkcie",
                notInstalled: "Nenainštalované",
                kindNew: "Nové",
                kindChanged: "Zmenené",
                kindFixed: "Opravené",
                updated: "Aktualizované",
                chooseFeatureHint: "Vyberte funkciu a pozrite si, čo sa v nej zmenilo.",
                skipPreviewCheckbox: "Nezobrazovať novinky pred aktualizáciou",
                showPreviewToggle: "Zobrazovať novinky pred aktualizáciou",
                showPreviewCaption: "Zmeny vo vašich funkciách sa budú naďalej zobrazovať po každej aktualizácii.")
        case .cs:
            return WhatsNewStrings(
                updatedFromFormat: "Aktualizováno z verze %@",
                newFeatures: "Nové funkce",
                yourFeatures: "Vaše funkce",
                notInstalled: "Nenainstalováno",
                kindNew: "Nové",
                kindChanged: "Změněno",
                kindFixed: "Opraveno",
                updated: "Aktualizováno",
                chooseFeatureHint: "Vyberte funkci a podívejte se, co se v ní změnilo.",
                skipPreviewCheckbox: "Nezobrazovat novinky před aktualizací",
                showPreviewToggle: "Zobrazovat novinky před aktualizací",
                showPreviewCaption: "Změny ve vašich funkcích se budou nadále zobrazovat po každé aktualizaci.")
        case .de:
            return WhatsNewStrings(
                updatedFromFormat: "Aktualisiert von Version %@",
                newFeatures: "Neue Funktionen",
                yourFeatures: "Deine Funktionen",
                notInstalled: "Nicht installiert",
                kindNew: "Neu",
                kindChanged: "Geändert",
                kindFixed: "Behoben",
                updated: "Aktualisiert",
                chooseFeatureHint: "Wähle eine Funktion, um zu sehen, was sich geändert hat.",
                skipPreviewCheckbox: "Neuigkeiten vor dem Update nicht anzeigen",
                showPreviewToggle: "Neuigkeiten vor dem Update anzeigen",
                showPreviewCaption: "Was sich in deinen Funktionen geändert hat, siehst du weiterhin nach jedem Update.")
        case .fr:
            return WhatsNewStrings(
                updatedFromFormat: "Mis à jour depuis la version %@",
                newFeatures: "Nouvelles fonctions",
                yourFeatures: "Vos fonctions",
                notInstalled: "Non installées",
                kindNew: "Nouveautés",
                kindChanged: "Modifications",
                kindFixed: "Corrections",
                updated: "Mise à jour",
                chooseFeatureHint: "Choisissez une fonction pour voir ce qui a changé.",
                skipPreviewCheckbox: "Masquer les nouveautés avant la mise à jour",
                showPreviewToggle: "Afficher les nouveautés avant la mise à jour",
                showPreviewCaption: "Ce qui a changé dans vos fonctions s’affiche toujours après chaque mise à jour.")
        case .it:
            return WhatsNewStrings(
                updatedFromFormat: "Aggiornato dalla versione %@",
                newFeatures: "Nuove funzioni",
                yourFeatures: "Le tue funzioni",
                notInstalled: "Non installate",
                kindNew: "Novità",
                kindChanged: "Modifiche",
                kindFixed: "Correzioni",
                updated: "Aggiornata",
                chooseFeatureHint: "Scegli una funzione per vedere cosa è cambiato.",
                skipPreviewCheckbox: "Non mostrare le novità prima di aggiornare",
                showPreviewToggle: "Mostra le novità prima di aggiornare",
                showPreviewCaption: "Le modifiche alle tue funzioni continuano ad apparire dopo ogni aggiornamento.")
        case .ja:
            return WhatsNewStrings(
                updatedFromFormat: "バージョン%@からアップデート",
                newFeatures: "新しい機能",
                yourFeatures: "インストール済みの機能",
                notInstalled: "未インストール",
                kindNew: "新規",
                kindChanged: "変更",
                kindFixed: "修正",
                updated: "アップデート済み",
                chooseFeatureHint: "機能を選択すると、変更内容が表示されます。",
                skipPreviewCheckbox: "アップデート前に新機能を表示しない",
                showPreviewToggle: "アップデート前に新機能を表示",
                showPreviewCaption: "インストール済みの機能の変更内容は、アップデートのたびに引き続き表示されます。")
        case .ko:
            return WhatsNewStrings(
                updatedFromFormat: "버전 %@에서 업데이트됨",
                newFeatures: "새 기능",
                yourFeatures: "설치된 기능",
                notInstalled: "설치되지 않음",
                kindNew: "신규",
                kindChanged: "변경",
                kindFixed: "수정",
                updated: "업데이트됨",
                chooseFeatureHint: "기능을 선택하면 변경된 내용을 볼 수 있습니다.",
                skipPreviewCheckbox: "업데이트 전에 새로운 기능 보지 않기",
                showPreviewToggle: "업데이트 전에 새로운 기능 보기",
                showPreviewCaption: "업데이트할 때마다 설치된 기능의 변경 사항은 계속 표시됩니다.")
        case .uk:
            return WhatsNewStrings(
                updatedFromFormat: "Оновлено з версії %@",
                newFeatures: "Нові функції",
                yourFeatures: "Ваші функції",
                notInstalled: "Не встановлено",
                kindNew: "Нове",
                kindChanged: "Змінено",
                kindFixed: "Виправлено",
                updated: "Оновлено",
                chooseFeatureHint: "Виберіть функцію, щоб побачити, що в ній змінилося.",
                skipPreviewCheckbox: "Не показувати зміни перед оновленням",
                showPreviewToggle: "Показувати зміни перед оновленням",
                showPreviewCaption: "Зміни у ваших функціях і далі показуватимуться після кожного оновлення.")
        case .zhHans:
            return WhatsNewStrings(
                updatedFromFormat: "已从版本 %@ 更新",
                newFeatures: "新增功能",
                yourFeatures: "已安装的功能",
                notInstalled: "未安装",
                kindNew: "新增",
                kindChanged: "变更",
                kindFixed: "修复",
                updated: "已更新",
                chooseFeatureHint: "选择一个功能以查看其中的变化。",
                skipPreviewCheckbox: "更新前不显示新功能",
                showPreviewToggle: "更新前显示新功能",
                showPreviewCaption: "每次更新后仍会显示已安装功能的变化。")
        case .zhTW, .zhHK:
            return WhatsNewStrings(
                updatedFromFormat: "已從版本 %@ 更新",
                newFeatures: "新增功能",
                yourFeatures: "已安裝的功能",
                notInstalled: "未安裝",
                kindNew: "新增",
                kindChanged: "變更",
                kindFixed: "修正",
                updated: "已更新",
                chooseFeatureHint: "選擇一個功能以查看其中的變化。",
                skipPreviewCheckbox: "更新前不顯示新功能",
                showPreviewToggle: "更新前顯示新功能",
                showPreviewCaption: "每次更新後仍會顯示已安裝功能的變化。")
        }
    }
}
