// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

struct AlwaysOnTopFeatureStrings {
    let title: String
    let hubDescription: String
    let enable: String
    let enableCaption: String
    let activeNow: String
    let shortcut: String
    let showBorder: String
    let borderColor: String
    let borderThickness: String
    let playSound: String
    let excludeTitle: String
    let excludeEmpty: String
    let addApp: String
    let excludeCaption: String
    let pinningUnavailable: String
    let permissionRequired: String
}

extension FeatureStrings {
    static func alwaysOnTop(_ language: AppLanguage) -> AlwaysOnTopFeatureStrings {
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

extension AlwaysOnTopFeatureStrings {
    static let enUS = AlwaysOnTopFeatureStrings(
        title: "Always On Top",
        hubDescription: "Pin the frontmost window above other windows",
        enable: "Enable Always On Top",
        enableCaption: "Press the shortcut to pin or unpin the frontmost window.",
        activeNow: "Pinning is on",
        shortcut: "Pin window",
        showBorder: "Show border around pinned windows",
        borderColor: "Border color",
        borderThickness: "Border thickness",
        playSound: "Play a sound when pinning",
        excludeTitle: "Excluded apps",
        excludeEmpty: "No apps excluded",
        addApp: "Add App",
        excludeCaption: "The shortcut does nothing when one of these apps is frontmost.",
        pinningUnavailable: "This Mac cannot pin other apps' windows. The shortcut will do nothing.",
        permissionRequired: "Accessibility is required to find the frontmost window."
    )

    static let ptBR = AlwaysOnTopFeatureStrings(
        title: "Sempre no topo",
        hubDescription: "Fixa a janela da frente acima das outras",
        enable: "Ativar Sempre no topo",
        enableCaption: "Pressione o atalho para fixar ou desafixar a janela da frente.",
        activeNow: "A fixação está ligada",
        shortcut: "Fixar janela",
        showBorder: "Mostrar borda nas janelas fixadas",
        borderColor: "Cor da borda",
        borderThickness: "Espessura da borda",
        playSound: "Tocar um som ao fixar",
        excludeTitle: "Apps excluídos",
        excludeEmpty: "Nenhum app excluído",
        addApp: "Adicionar App",
        excludeCaption: "O atalho não faz nada quando um destes apps está na frente.",
        pinningUnavailable: "Este Mac não consegue fixar janelas de outros apps. O atalho não fará nada.",
        permissionRequired: "A Acessibilidade é necessária para encontrar a janela da frente."
    )

    static let tr = AlwaysOnTopFeatureStrings(
        title: "Her Zaman Üstte",
        hubDescription: "Öndeki pencereyi diğer pencerelerin üstünde tut",
        enable: "Her Zaman Üstte’yi aç",
        enableCaption: "Öndeki pencereyi sabitlemek veya kaldırmak için kısayola basın.",
        activeNow: "Sabitleme açık",
        shortcut: "Pencereyi sabitle",
        showBorder: "Sabitlenen pencerelerin çevresinde kenarlık göster",
        borderColor: "Kenarlık rengi",
        borderThickness: "Kenarlık kalınlığı",
        playSound: "Sabitlerken bir ses çal",
        excludeTitle: "Hariç tutulan uygulamalar",
        excludeEmpty: "Hariç tutulan uygulama yok",
        addApp: "Uygulama Ekle",
        excludeCaption: "Bu uygulamalardan biri öndeyken kısayol hiçbir şey yapmaz.",
        pinningUnavailable: "Bu Mac diğer uygulamaların pencerelerini sabitleyemez. Kısayol hiçbir şey yapmaz.",
        permissionRequired: "Öndeki pencereyi bulmak için Erişilebilirlik gerekir."
    )

    static let ru = AlwaysOnTopFeatureStrings(
        title: "Поверх всех окон",
        hubDescription: "Закрепляет переднее окно над остальными",
        enable: "Включить «Поверх всех окон»",
        enableCaption: "Нажмите сочетание клавиш, чтобы закрепить или открепить переднее окно.",
        activeNow: "Закрепление включено",
        shortcut: "Закрепить окно",
        showBorder: "Показывать рамку вокруг закреплённых окон",
        borderColor: "Цвет рамки",
        borderThickness: "Толщина рамки",
        playSound: "Звук при закреплении",
        excludeTitle: "Исключённые приложения",
        excludeEmpty: "Нет исключённых приложений",
        addApp: "Добавить приложение",
        excludeCaption: "Сочетание ничего не делает, когда одно из этих приложений на переднем плане.",
        pinningUnavailable: "Этот Mac не может закреплять окна других приложений. Сочетание ничего не сделает.",
        permissionRequired: "Для поиска переднего окна нужна Универсальный доступ."
    )

    static let es = AlwaysOnTopFeatureStrings(
        title: "Siempre visible",
        hubDescription: "Fija la ventana delantera por encima de las demás",
        enable: "Activar Siempre visible",
        enableCaption: "Pulsa el atajo para fijar o desfijar la ventana delantera.",
        activeNow: "La fijación está activa",
        shortcut: "Fijar ventana",
        showBorder: "Mostrar borde alrededor de las ventanas fijadas",
        borderColor: "Color del borde",
        borderThickness: "Grosor del borde",
        playSound: "Reproducir un sonido al fijar",
        excludeTitle: "Apps excluidas",
        excludeEmpty: "Ninguna app excluida",
        addApp: "Añadir App",
        excludeCaption: "El atajo no hace nada cuando una de estas apps está al frente.",
        pinningUnavailable: "Este Mac no puede fijar ventanas de otras apps. El atajo no hará nada.",
        permissionRequired: "Se necesita Accesibilidad para encontrar la ventana delantera."
    )

    static let de = AlwaysOnTopFeatureStrings(
        title: "Immer im Vordergrund",
        hubDescription: "Hält das vorderste Fenster über den anderen",
        enable: "Immer im Vordergrund aktivieren",
        enableCaption: "Drücke das Tastenkürzel, um das vorderste Fenster anzuheften oder zu lösen.",
        activeNow: "Anheften ist an",
        shortcut: "Fenster anheften",
        showBorder: "Rahmen um angeheftete Fenster zeigen",
        borderColor: "Rahmenfarbe",
        borderThickness: "Rahmenstärke",
        playSound: "Beim Anheften einen Ton abspielen",
        excludeTitle: "Ausgeschlossene Apps",
        excludeEmpty: "Keine Apps ausgeschlossen",
        addApp: "App hinzufügen",
        excludeCaption: "Das Tastenkürzel tut nichts, wenn eine dieser Apps im Vordergrund ist.",
        pinningUnavailable: "Dieser Mac kann Fenster anderer Apps nicht anheften. Das Tastenkürzel tut nichts.",
        permissionRequired: "Bedienungshilfen sind nötig, um das vorderste Fenster zu finden."
    )

    static let fr = AlwaysOnTopFeatureStrings(
        title: "Toujours au premier plan",
        hubDescription: "Épingle la fenêtre au premier plan au-dessus des autres",
        enable: "Activer Toujours au premier plan",
        enableCaption: "Appuyez sur le raccourci pour épingler ou détacher la fenêtre au premier plan.",
        activeNow: "L’épinglage est activé",
        shortcut: "Épingler la fenêtre",
        showBorder: "Afficher une bordure autour des fenêtres épinglées",
        borderColor: "Couleur de la bordure",
        borderThickness: "Épaisseur de la bordure",
        playSound: "Jouer un son lors de l’épinglage",
        excludeTitle: "Apps exclues",
        excludeEmpty: "Aucune app exclue",
        addApp: "Ajouter une app",
        excludeCaption: "Le raccourci ne fait rien lorsqu’une de ces apps est au premier plan.",
        pinningUnavailable: "Ce Mac ne peut pas épingler les fenêtres des autres apps. Le raccourci ne fera rien.",
        permissionRequired: "L’accessibilité est requise pour trouver la fenêtre au premier plan."
    )

    static let it = AlwaysOnTopFeatureStrings(
        title: "Sempre in primo piano",
        hubDescription: "Fissa la finestra in primo piano sopra le altre",
        enable: "Attiva Sempre in primo piano",
        enableCaption: "Premi la scorciatoia per fissare o sbloccare la finestra in primo piano.",
        activeNow: "Il fissaggio è attivo",
        shortcut: "Fissa finestra",
        showBorder: "Mostra un bordo intorno alle finestre fissate",
        borderColor: "Colore del bordo",
        borderThickness: "Spessore del bordo",
        playSound: "Riproduci un suono quando fissi",
        excludeTitle: "App escluse",
        excludeEmpty: "Nessuna app esclusa",
        addApp: "Aggiungi App",
        excludeCaption: "La scorciatoia non fa nulla quando una di queste app è in primo piano.",
        pinningUnavailable: "Questo Mac non può fissare le finestre di altre app. La scorciatoia non farà nulla.",
        permissionRequired: "Accessibilità è necessaria per trovare la finestra in primo piano."
    )

    static let ja = AlwaysOnTopFeatureStrings(
        title: "常に最前面",
        hubDescription: "最前面のウインドウを他のウインドウの上に固定します",
        enable: "常に最前面を有効にする",
        enableCaption: "ショートカットで最前面のウインドウを固定または解除します。",
        activeNow: "固定はオンです",
        shortcut: "ウインドウを固定",
        showBorder: "固定したウインドウの周りに枠を表示",
        borderColor: "枠の色",
        borderThickness: "枠の太さ",
        playSound: "固定するときに音を鳴らす",
        excludeTitle: "除外するアプリ",
        excludeEmpty: "除外するアプリはありません",
        addApp: "アプリを追加",
        excludeCaption: "これらのアプリが最前面のときはショートカットは何もしません。",
        pinningUnavailable: "この Mac は他のアプリのウインドウを固定できません。ショートカットは何もしません。",
        permissionRequired: "最前面のウインドウを見つけるにはアクセシビリティが必要です。"
    )

    static let ko = AlwaysOnTopFeatureStrings(
        title: "항상 위",
        hubDescription: "맨 앞 윈도우를 다른 윈도우 위에 고정합니다",
        enable: "항상 위 켜기",
        enableCaption: "단축키로 맨 앞 윈도우를 고정하거나 해제합니다.",
        activeNow: "고정이 켜져 있습니다",
        shortcut: "윈도우 고정",
        showBorder: "고정된 윈도우 주위에 테두리 표시",
        borderColor: "테두리 색",
        borderThickness: "테두리 두께",
        playSound: "고정할 때 소리 재생",
        excludeTitle: "제외된 앱",
        excludeEmpty: "제외된 앱이 없습니다",
        addApp: "앱 추가",
        excludeCaption: "이 앱 중 하나가 맨 앞에 있으면 단축키는 아무 것도 하지 않습니다.",
        pinningUnavailable: "이 Mac은 다른 앱의 윈도우를 고정할 수 없습니다. 단축키는 아무 것도 하지 않습니다.",
        permissionRequired: "맨 앞 윈도우를 찾으려면 손쉬운 사용이 필요합니다."
    )

    static let zhHans = AlwaysOnTopFeatureStrings(
        title: "始终置顶",
        hubDescription: "将最前面的窗口固定在其他窗口之上",
        enable: "启用始终置顶",
        enableCaption: "按快捷键固定或取消固定最前面的窗口。",
        activeNow: "置顶已开启",
        shortcut: "固定窗口",
        showBorder: "在已固定窗口周围显示边框",
        borderColor: "边框颜色",
        borderThickness: "边框粗细",
        playSound: "固定时播放声音",
        excludeTitle: "排除的 App",
        excludeEmpty: "没有排除的 App",
        addApp: "添加 App",
        excludeCaption: "这些 App 在最前面时，快捷键不会执行任何操作。",
        pinningUnavailable: "这台 Mac 无法固定其他 App 的窗口。快捷键不会执行任何操作。",
        permissionRequired: "需要辅助功能才能找到最前面的窗口。"
    )

    static let zhTW = AlwaysOnTopFeatureStrings(
        title: "永遠置頂",
        hubDescription: "將最前面的視窗固定在其他視窗之上",
        enable: "啟用永遠置頂",
        enableCaption: "按快捷鍵固定或取消固定最前面的視窗。",
        activeNow: "置頂已開啟",
        shortcut: "固定視窗",
        showBorder: "在已固定視窗周圍顯示邊框",
        borderColor: "邊框顏色",
        borderThickness: "邊框粗細",
        playSound: "固定時播放聲音",
        excludeTitle: "排除的 App",
        excludeEmpty: "沒有排除的 App",
        addApp: "加入 App",
        excludeCaption: "這些 App 在最前面時，快捷鍵不會執行任何操作。",
        pinningUnavailable: "這台 Mac 無法固定其他 App 的視窗。快捷鍵不會執行任何操作。",
        permissionRequired: "需要輔助使用才能找到最前面的視窗。"
    )

    static let zhHK = AlwaysOnTopFeatureStrings(
        title: "永遠置頂",
        hubDescription: "將最前面的視窗固定在其他視窗之上",
        enable: "啟用永遠置頂",
        enableCaption: "按快捷鍵固定或取消固定最前面的視窗。",
        activeNow: "置頂已開啟",
        shortcut: "固定視窗",
        showBorder: "在已固定視窗周圍顯示邊框",
        borderColor: "邊框顏色",
        borderThickness: "邊框粗細",
        playSound: "固定時播放聲音",
        excludeTitle: "排除的 App",
        excludeEmpty: "沒有排除的 App",
        addApp: "加入 App",
        excludeCaption: "這些 App 在最前面時，快捷鍵不會執行任何操作。",
        pinningUnavailable: "這部 Mac 無法固定其他 App 的視窗。快捷鍵不會執行任何操作。",
        permissionRequired: "需要輔助使用才能找到最前面的視窗。"
    )
}
