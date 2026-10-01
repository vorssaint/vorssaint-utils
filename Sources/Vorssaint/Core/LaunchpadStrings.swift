// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

struct LaunchpadStrings {
    let pageTitle: String
    let hubDescription: String
    let openButton: String
    let searchPlaceholder: String
    let shortcutToggle: String
    let pinchToggle: String
    let newFolderDefaultName: String
    let utilitiesFolderName: String
    let resetLayoutButton: String
    let resetLayoutConfirmTitle: String
    let resetLayoutConfirmMessage: String
}

extension FeatureStrings {
    static func launchpad(_ language: AppLanguage) -> LaunchpadStrings {
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
        case .uk: return .uk
        case .zhHans: return .zhHans
        case .zhTW: return .zhTW
        case .zhHK: return .zhHK
        }
    }
}

extension LaunchpadStrings {
    static let enUS = LaunchpadStrings(
        pageTitle: "Launchpad Classic",
        hubDescription: "Open a full-screen grid of every installed app, like the original Launchpad.",
        openButton: "Open Launchpad",
        searchPlaceholder: "Search Applications",
        shortcutToggle: "Global shortcut to open Launchpad",
        pinchToggle: "Open with a four-finger pinch",
        newFolderDefaultName: "New Folder",
        utilitiesFolderName: "Utilities",
        resetLayoutButton: "Reset",
        resetLayoutConfirmTitle: "Reset layout",
        resetLayoutConfirmMessage: "Restore every app to its default order and remove your folders? This can’t be undone.")

    static let ptBR = LaunchpadStrings(
        pageTitle: "Launchpad Classic",
        hubDescription: "Abra uma grade em tela cheia com todos os apps instalados, como o Launchpad original.",
        openButton: "Abrir Launchpad",
        searchPlaceholder: "Buscar Aplicativos",
        shortcutToggle: "Atalho global para abrir o Launchpad",
        pinchToggle: "Abrir com um beliscão de quatro dedos",
        newFolderDefaultName: "Nova Pasta",
        utilitiesFolderName: "Utilitários",
        resetLayoutButton: "Redefinir",
        resetLayoutConfirmTitle: "Redefinir layout",
        resetLayoutConfirmMessage: "Restaurar todos os apps para a ordem padrão e remover suas pastas? Isso não pode ser desfeito.")

    static let tr = LaunchpadStrings(
        pageTitle: "Launchpad Classic",
        hubDescription: "Orijinal Launchpad gibi, yüklü tüm uygulamaların tam ekran bir ızgarasını açar.",
        openButton: "Launchpad’i Aç",
        searchPlaceholder: "Uygulama Ara",
        shortcutToggle: "Launchpad’i açmak için genel kısayol",
        pinchToggle: "Dört parmakla sıkıştırarak aç",
        newFolderDefaultName: "Yeni Klasör",
        utilitiesFolderName: "Yardımcı Programlar",
        resetLayoutButton: "Sıfırla",
        resetLayoutConfirmTitle: "Düzeni sıfırla",
        resetLayoutConfirmMessage: "Tüm uygulamalar varsayılan sıraya döndürülsün ve klasörleriniz kaldırılsın mı? Bu geri alınamaz.")

    static let ru = LaunchpadStrings(
        pageTitle: "Launchpad Classic",
        hubDescription: "Открывает полноэкранную сетку всех установленных приложений, как в оригинальном Launchpad.",
        openButton: "Открыть Launchpad",
        searchPlaceholder: "Поиск приложений",
        shortcutToggle: "Глобальное сочетание клавиш для открытия Launchpad",
        pinchToggle: "Открывать сведением четырёх пальцев",
        newFolderDefaultName: "Новая папка",
        utilitiesFolderName: "Утилиты",
        resetLayoutButton: "Сбросить",
        resetLayoutConfirmTitle: "Сбросить раскладку",
        resetLayoutConfirmMessage: "Восстановить порядок приложений по умолчанию и удалить папки? Это нельзя отменить.")

    static let es = LaunchpadStrings(
        pageTitle: "Launchpad Classic",
        hubDescription: "Abre una cuadrícula a pantalla completa con todas las apps instaladas, como el Launchpad original.",
        openButton: "Abrir Launchpad",
        searchPlaceholder: "Buscar aplicaciones",
        shortcutToggle: "Atajo global para abrir Launchpad",
        pinchToggle: "Abrir con un pellizco de cuatro dedos",
        newFolderDefaultName: "Nueva carpeta",
        utilitiesFolderName: "Utilidades",
        resetLayoutButton: "Restablecer",
        resetLayoutConfirmTitle: "Restablecer diseño",
        resetLayoutConfirmMessage: "¿Restaurar todas las apps a su orden predeterminado y eliminar tus carpetas? Esto no se puede deshacer.")

    static let sk = LaunchpadStrings(
        pageTitle: "Launchpad Classic",
        hubDescription: "Otvorí celoobrazovkovú mriežku všetkých nainštalovaných aplikácií, podobne ako pôvodný Launchpad.",
        openButton: "Otvoriť Launchpad",
        searchPlaceholder: "Hľadať aplikácie",
        shortcutToggle: "Globálna skratka na otvorenie Launchpadu",
        pinchToggle: "Otvoriť stiahnutím štyrmi prstami",
        newFolderDefaultName: "Nový priečinok",
        utilitiesFolderName: "Pomôcky",
        resetLayoutButton: "Obnoviť",
        resetLayoutConfirmTitle: "Obnoviť rozloženie",
        resetLayoutConfirmMessage: "Obnoviť predvolené poradie všetkých aplikácií a odstrániť priečinky? Toto sa nedá vrátiť späť.")

    static let de = LaunchpadStrings(
        pageTitle: "Launchpad Classic",
        hubDescription: "Öffnet ein Vollbildraster aller installierten Apps, wie das ursprüngliche Launchpad.",
        openButton: "Launchpad öffnen",
        searchPlaceholder: "Programme suchen",
        shortcutToggle: "Globale Tastenkombination zum Öffnen von Launchpad",
        pinchToggle: "Mit einer Vier-Finger-Kneifgeste öffnen",
        newFolderDefaultName: "Neuer Ordner",
        utilitiesFolderName: "Dienstprogramme",
        resetLayoutButton: "Zurücksetzen",
        resetLayoutConfirmTitle: "Layout zurücksetzen",
        resetLayoutConfirmMessage: "Alle Apps auf die Standardreihenfolge zurücksetzen und deine Ordner entfernen? Dies kann nicht rückgängig gemacht werden.")

    static let fr = LaunchpadStrings(
        pageTitle: "Launchpad Classic",
        hubDescription: "Ouvre une grille plein écran de toutes les apps installées, comme le Launchpad d’origine.",
        openButton: "Ouvrir Launchpad",
        searchPlaceholder: "Rechercher des applications",
        shortcutToggle: "Raccourci global pour ouvrir Launchpad",
        pinchToggle: "Ouvrir avec un pincement à quatre doigts",
        newFolderDefaultName: "Nouveau dossier",
        utilitiesFolderName: "Utilitaires",
        resetLayoutButton: "Réinitialiser",
        resetLayoutConfirmTitle: "Réinitialiser la disposition",
        resetLayoutConfirmMessage: "Restaurer l’ordre par défaut de toutes les apps et supprimer vos dossiers\u{202F}? Cette action est irréversible.")

    static let it = LaunchpadStrings(
        pageTitle: "Launchpad Classic",
        hubDescription: "Apre una griglia a schermo intero con tutte le app installate, come il Launchpad originale.",
        openButton: "Apri Launchpad",
        searchPlaceholder: "Cerca applicazioni",
        shortcutToggle: "Scorciatoia globale per aprire Launchpad",
        pinchToggle: "Apri con un pizzico a quattro dita",
        newFolderDefaultName: "Nuova cartella",
        utilitiesFolderName: "Utility",
        resetLayoutButton: "Ripristina",
        resetLayoutConfirmTitle: "Ripristina disposizione",
        resetLayoutConfirmMessage: "Ripristinare l’ordine predefinito di tutte le app e rimuovere le cartelle? Questa azione non può essere annullata.")

    static let ja = LaunchpadStrings(
        pageTitle: "Launchpad Classic",
        hubDescription: "元のLaunchpadのように、インストール済みのすべてのアプリを全画面表示のグリッドで開きます。",
        openButton: "Launchpadを開く",
        searchPlaceholder: "アプリケーションを検索",
        shortcutToggle: "Launchpadを開くグローバルショートカット",
        pinchToggle: "4本指のピンチで開く",
        newFolderDefaultName: "新規フォルダ",
        utilitiesFolderName: "ユーティリティ",
        resetLayoutButton: "リセット",
        resetLayoutConfirmTitle: "レイアウトをリセット",
        resetLayoutConfirmMessage: "すべてのアプリを初期の並び順に戻し、フォルダを削除しますか？この操作は元に戻せません。")

    static let ko = LaunchpadStrings(
        pageTitle: "Launchpad Classic",
        hubDescription: "원래의 Launchpad처럼 설치된 모든 앱을 전체 화면 그리드로 엽니다.",
        openButton: "Launchpad 열기",
        searchPlaceholder: "응용 프로그램 검색",
        shortcutToggle: "Launchpad를 여는 전역 단축키",
        pinchToggle: "네 손가락으로 오므려서 열기",
        newFolderDefaultName: "새로운 폴더",
        utilitiesFolderName: "유틸리티",
        resetLayoutButton: "재설정",
        resetLayoutConfirmTitle: "레이아웃 재설정",
        resetLayoutConfirmMessage: "모든 앱을 기본 순서로 복원하고 폴더를 제거하시겠습니까? 이 작업은 되돌릴 수 없습니다.")

    static let uk = LaunchpadStrings(
        pageTitle: "Launchpad Classic",
        hubDescription: "Відкриває повноекранну сітку всіх встановлених застосунків, як оригінальний Launchpad.",
        openButton: "Відкрити Launchpad",
        searchPlaceholder: "Пошук програм",
        shortcutToggle: "Глобальне сполучення клавіш для відкриття Launchpad",
        pinchToggle: "Відкривати зведенням чотирьох пальців",
        newFolderDefaultName: "Нова папка",
        utilitiesFolderName: "Утиліти",
        resetLayoutButton: "Скинути",
        resetLayoutConfirmTitle: "Скинути розташування",
        resetLayoutConfirmMessage: "Відновити типовий порядок усіх застосунків і видалити ваші папки? Це неможливо скасувати.")

    static let zhHans = LaunchpadStrings(
        pageTitle: "Launchpad Classic",
        hubDescription: "像原来的 Launchpad 一样，全屏显示所有已安装应用的网格。",
        openButton: "打开 Launchpad",
        searchPlaceholder: "搜索应用程序",
        shortcutToggle: "打开 Launchpad 的全局快捷键",
        pinchToggle: "用四指捏合手势打开",
        newFolderDefaultName: "新建文件夹",
        utilitiesFolderName: "实用工具",
        resetLayoutButton: "重置",
        resetLayoutConfirmTitle: "重置布局",
        resetLayoutConfirmMessage: "将所有应用恢复为默认顺序并删除您的文件夹？此操作无法撤销。")

    static let zhTW = LaunchpadStrings(
        pageTitle: "Launchpad Classic",
        hubDescription: "像原本的 Launchpad 一樣，以全螢幕方式顯示所有已安裝應用程式的網格。",
        openButton: "打開 Launchpad",
        searchPlaceholder: "搜尋應用程式",
        shortcutToggle: "打開 Launchpad 的全域快速鍵",
        pinchToggle: "用四指縮放手勢開啟",
        newFolderDefaultName: "新資料夾",
        utilitiesFolderName: "工具程式",
        resetLayoutButton: "重設",
        resetLayoutConfirmTitle: "重設版面配置",
        resetLayoutConfirmMessage: "將所有應用程式還原為預設順序並移除您的檔案夾？此操作無法復原。")

    static let zhHK = LaunchpadStrings(
        pageTitle: "Launchpad Classic",
        hubDescription: "像原本的 Launchpad 一樣，以全螢幕顯示所有已安裝應用程式的網格。",
        openButton: "打開 Launchpad",
        searchPlaceholder: "搜尋應用程式",
        shortcutToggle: "打開 Launchpad 的全域快速鍵",
        pinchToggle: "用四指縮放手勢開啟",
        newFolderDefaultName: "新資料夾",
        utilitiesFolderName: "工具程式",
        resetLayoutButton: "重設",
        resetLayoutConfirmTitle: "重設版面配置",
        resetLayoutConfirmMessage: "將所有應用程式還原為預設順序並移除您的資料夾？此操作無法復原。")
}
