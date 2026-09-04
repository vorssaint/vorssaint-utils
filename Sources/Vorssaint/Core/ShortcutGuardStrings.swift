// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

struct ShortcutGuardStrings {
    let title: String
    let description: String
    let enable: String
    let applications: String
    let add: String
    let noApplications: String
    let dropFromFinder: String
    let blockedShortcuts: String
    let record: String
    let noShortcuts: String
    let activeCaption: String
}

extension FeatureStrings {
    static func shortcutGuard(_ language: AppLanguage) -> ShortcutGuardStrings {
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

extension ShortcutGuardStrings {
    static let enUS = ShortcutGuardStrings(
        title: "Shortcut Guard",
        description: "Blocks selected keyboard shortcuts only while an app or process you choose is frontmost.",
        enable: "Enable Shortcut Guard",
        applications: "Applications",
        add: "Add…",
        noApplications: "No applications selected.",
        dropFromFinder: "Drop an app from Finder",
        blockedShortcuts: "Blocked shortcuts",
        record: "Record",
        noShortcuts: "No shortcuts selected.",
        activeCaption: "A shortcut is intercepted only while a selected app or process is frontmost."
    )

    static let ptBR = ShortcutGuardStrings(
        title: "Proteção de atalhos",
        description: "Bloqueia atalhos de teclado selecionados somente enquanto um app ou processo escolhido está em primeiro plano.",
        enable: "Ativar proteção de atalhos",
        applications: "Aplicativos",
        add: "Adicionar…",
        noApplications: "Nenhum aplicativo selecionado.",
        dropFromFinder: "Arraste um app do Finder",
        blockedShortcuts: "Atalhos bloqueados",
        record: "Gravar",
        noShortcuts: "Nenhum atalho selecionado.",
        activeCaption: "O atalho é interceptado apenas enquanto um app ou processo selecionado está em primeiro plano."
    )

    static let tr = ShortcutGuardStrings(
        title: "Kısayol koruması",
        description: "Seçilen klavye kısayollarını yalnızca seçtiğiniz uygulama veya işlem öndeyken engeller.",
        enable: "Kısayol korumasını etkinleştir",
        applications: "Uygulamalar",
        add: "Ekle…",
        noApplications: "Uygulama seçilmedi.",
        dropFromFinder: "Finder’dan bir uygulama bırakın",
        blockedShortcuts: "Engellenen kısayollar",
        record: "Kaydet",
        noShortcuts: "Kısayol seçilmedi.",
        activeCaption: "Bir kısayol yalnızca seçilen uygulama veya işlem öndeyken engellenir."
    )

    static let ru = ShortcutGuardStrings(
        title: "Блокировка сочетаний",
        description: "Блокирует выбранные сочетания клавиш только когда выбранное приложение или процесс находится на переднем плане.",
        enable: "Включить блокировку сочетаний",
        applications: "Приложения",
        add: "Добавить…",
        noApplications: "Приложения не выбраны.",
        dropFromFinder: "Перетащите приложение из Finder",
        blockedShortcuts: "Заблокированные сочетания",
        record: "Записать",
        noShortcuts: "Сочетания не выбраны.",
        activeCaption: "Сочетание перехватывается только когда выбранное приложение или процесс находится на переднем плане."
    )

    static let es = ShortcutGuardStrings(
        title: "Protección de atajos",
        description: "Bloquea los atajos de teclado seleccionados solo mientras una app o proceso elegido está en primer plano.",
        enable: "Activar protección de atajos",
        applications: "Aplicaciones",
        add: "Añadir…",
        noApplications: "No hay aplicaciones seleccionadas.",
        dropFromFinder: "Arrastra una app desde Finder",
        blockedShortcuts: "Atajos bloqueados",
        record: "Grabar",
        noShortcuts: "No hay atajos seleccionados.",
        activeCaption: "El atajo solo se intercepta mientras una app o proceso seleccionado está en primer plano."
    )

    static let de = ShortcutGuardStrings(
        title: "Kurzbefehl-Schutz",
        description: "Blockiert ausgewählte Tastenkürzel nur, solange eine ausgewählte App oder ein ausgewählter Prozess im Vordergrund ist.",
        enable: "Kurzbefehl-Schutz aktivieren",
        applications: "Programme",
        add: "Hinzufügen…",
        noApplications: "Keine Programme ausgewählt.",
        dropFromFinder: "App aus dem Finder hierher ziehen",
        blockedShortcuts: "Blockierte Tastenkürzel",
        record: "Aufzeichnen",
        noShortcuts: "Keine Tastenkürzel ausgewählt.",
        activeCaption: "Ein Tastenkürzel wird nur abgefangen, solange eine ausgewählte App oder ein Prozess im Vordergrund ist."
    )

    static let fr = ShortcutGuardStrings(
        title: "Protection des raccourcis",
        description: "Bloque les raccourcis clavier sélectionnés uniquement lorsqu’une app ou un processus choisi est au premier plan.",
        enable: "Activer la protection des raccourcis",
        applications: "Applications",
        add: "Ajouter…",
        noApplications: "Aucune application sélectionnée.",
        dropFromFinder: "Déposez une app depuis le Finder",
        blockedShortcuts: "Raccourcis bloqués",
        record: "Enregistrer",
        noShortcuts: "Aucun raccourci sélectionné.",
        activeCaption: "Un raccourci est intercepté uniquement lorsqu’une app ou un processus sélectionné est au premier plan."
    )

    static let it = ShortcutGuardStrings(
        title: "Protezione scorciatoie",
        description: "Blocca le scorciatoie da tastiera selezionate solo mentre un’app o un processo scelto è in primo piano.",
        enable: "Attiva protezione scorciatoie",
        applications: "Applicazioni",
        add: "Aggiungi…",
        noApplications: "Nessuna applicazione selezionata.",
        dropFromFinder: "Trascina un’app dal Finder",
        blockedShortcuts: "Scorciatoie bloccate",
        record: "Registra",
        noShortcuts: "Nessuna scorciatoia selezionata.",
        activeCaption: "Una scorciatoia viene intercettata solo mentre un’app o un processo selezionato è in primo piano."
    )

    static let ja = ShortcutGuardStrings(
        title: "ショートカットガード",
        description: "選択したアプリまたはプロセスが最前面のときだけ、指定したキーボードショートカットを無効にします。",
        enable: "ショートカットガードを有効にする",
        applications: "アプリケーション",
        add: "追加…",
        noApplications: "アプリケーションが選択されていません。",
        dropFromFinder: "Finder からアプリをドロップ",
        blockedShortcuts: "無効にするショートカット",
        record: "記録",
        noShortcuts: "ショートカットが選択されていません。",
        activeCaption: "ショートカットは、選択したアプリまたはプロセスが最前面のときだけ遮断されます。"
    )

    static let ko = ShortcutGuardStrings(
        title: "단축키 보호",
        description: "선택한 앱이나 프로세스가 전면에 있을 때만 지정한 키보드 단축키를 차단합니다.",
        enable: "단축키 보호 활성화",
        applications: "응용 프로그램",
        add: "추가…",
        noApplications: "선택한 응용 프로그램이 없습니다.",
        dropFromFinder: "Finder에서 앱을 드롭",
        blockedShortcuts: "차단된 단축키",
        record: "기록",
        noShortcuts: "선택한 단축키가 없습니다.",
        activeCaption: "단축키는 선택한 앱이나 프로세스가 전면에 있을 때만 차단됩니다."
    )

    static let zhHans = ShortcutGuardStrings(
        title: "快捷键保护",
        description: "仅在所选 App 或进程位于前台时阻止指定的键盘快捷键。",
        enable: "启用快捷键保护",
        applications: "应用程序",
        add: "添加…",
        noApplications: "未选择应用程序。",
        dropFromFinder: "从 Finder 拖入 App",
        blockedShortcuts: "已阻止的快捷键",
        record: "录制",
        noShortcuts: "未选择快捷键。",
        activeCaption: "仅当所选 App 或进程位于前台时才会拦截快捷键。"
    )

    static let zhTW = ShortcutGuardStrings(
        title: "快捷鍵保護",
        description: "只在所選 App 或程序位於最前方時阻擋指定的鍵盤快捷鍵。",
        enable: "啟用快捷鍵保護",
        applications: "應用程式",
        add: "加入…",
        noApplications: "尚未選取應用程式。",
        dropFromFinder: "從 Finder 拖入 App",
        blockedShortcuts: "已阻擋的快捷鍵",
        record: "錄製",
        noShortcuts: "尚未選取快捷鍵。",
        activeCaption: "只有在所選 App 或程序位於最前方時才會攔截快捷鍵。"
    )

    static let zhHK = ShortcutGuardStrings(
        title: "快捷鍵保護",
        description: "只在所選 App 或程序位於最前方時阻擋指定的鍵盤快捷鍵。",
        enable: "啟用快捷鍵保護",
        applications: "應用程式",
        add: "加入…",
        noApplications: "尚未選取應用程式。",
        dropFromFinder: "從 Finder 拖入 App",
        blockedShortcuts: "已阻擋的快捷鍵",
        record: "錄製",
        noShortcuts: "尚未選取快捷鍵。",
        activeCaption: "只有在所選 App 或程序位於最前方時才會攔截快捷鍵。"
    )
}
