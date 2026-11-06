// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

struct NotchNavigationStrings {
    let tab: String
    let styleTitle: String
    let styleCaption: String
    let topBar: String
    let sideButtons: String
    let itemsTitle: String
    let itemsCaption: String
    let secondaryClick: String
    let secondaryClickCaption: String
    let sideButtonsHint: String

    static func localized(_ language: AppLanguage) -> NotchNavigationStrings {
        switch language {
        case .enUS:
            return .init(tab: "Navigation", styleTitle: "Navigation style",
                         styleCaption: "How you move between pages in the open island.",
                         topBar: "Top bar", sideButtons: "Side buttons",
                         itemsTitle: "Top bar items",
                         itemsCaption: "Drag to reorder. Uncheck an item to hide it. Settings always comes last.",
                         secondaryClick: "Right-click to switch",
                         secondaryClickCaption: "Right-clicking Keep Awake or the microphone turns it on or off.",
                         sideButtonsHint: "Arrange the side buttons on the Layout tab.")
        case .ptBR:
            return .init(tab: "Navegação", styleTitle: "Estilo de navegação",
                         styleCaption: "Como você passa de uma página a outra na ilha aberta.",
                         topBar: "Barra superior", sideButtons: "Botões laterais",
                         itemsTitle: "Itens da barra superior",
                         itemsCaption: "Arraste para reordenar. Desmarque um item para ocultá-lo. Ajustes fica sempre por último.",
                         secondaryClick: "Clique secundário para alternar",
                         secondaryClickCaption: "O clique secundário em Manter acordado ou no microfone liga ou desliga.",
                         sideButtonsHint: "Organize os botões laterais na aba Layout.")
        case .tr:
            return .init(tab: "Gezinme", styleTitle: "Gezinme stili",
                         styleCaption: "Açık adada sayfalar arasında nasıl geçeceğiniz.",
                         topBar: "Üst çubuk", sideButtons: "Yan düğmeler",
                         itemsTitle: "Üst çubuk öğeleri",
                         itemsCaption: "Sıralamak için sürükleyin. Gizlemek için işareti kaldırın. Ayarlar her zaman en sonda.",
                         secondaryClick: "Sağ tıklayarak aç/kapat",
                         secondaryClickCaption: "Uyanık Tut veya mikrofona sağ tıklamak onu açar ya da kapatır.",
                         sideButtonsHint: "Yan düğmeleri Yerleşim sekmesinde düzenleyin.")
        case .ru:
            return .init(tab: "Навигация", styleTitle: "Стиль навигации",
                         styleCaption: "Как переходить между страницами открытого острова.",
                         topBar: "Верхняя панель", sideButtons: "Боковые кнопки",
                         itemsTitle: "Элементы верхней панели",
                         itemsCaption: "Перетащите, чтобы изменить порядок. Снимите флажок, чтобы скрыть. Настройки всегда в конце.",
                         secondaryClick: "Переключать правым кликом",
                         secondaryClickCaption: "Правый клик по «Не спать» или микрофону включает или выключает их.",
                         sideButtonsHint: "Боковые кнопки настраиваются на вкладке «Макет».")
        case .es:
            return .init(tab: "Navegación", styleTitle: "Estilo de navegación",
                         styleCaption: "Cómo te mueves entre las páginas de la isla abierta.",
                         topBar: "Barra superior", sideButtons: "Botones laterales",
                         itemsTitle: "Elementos de la barra superior",
                         itemsCaption: "Arrastra para reordenar. Desmarca un elemento para ocultarlo. Ajustes va siempre al final.",
                         secondaryClick: "Clic secundario para alternar",
                         secondaryClickCaption: "El clic secundario en Mantener despierto o en el micrófono lo activa o desactiva.",
                         sideButtonsHint: "Organiza los botones laterales en la pestaña Diseño.")
        case .sk:
            return .init(tab: "Navigácia", styleTitle: "Štýl navigácie",
                         styleCaption: "Ako sa presúvate medzi stránkami otvoreného ostrova.",
                         topBar: "Horná lišta", sideButtons: "Bočné tlačidlá",
                         itemsTitle: "Položky hornej lišty",
                         itemsCaption: "Poradie zmeníte potiahnutím. Zrušením označenia položku skryjete. Nastavenia sú vždy posledné.",
                         secondaryClick: "Prepínať pravým kliknutím",
                         secondaryClickCaption: "Pravé kliknutie na Nespať alebo mikrofón ho zapne alebo vypne.",
                         sideButtonsHint: "Bočné tlačidlá usporiadate na karte Rozloženie.")
        case .de:
            return .init(tab: "Navigation", styleTitle: "Navigationsstil",
                         styleCaption: "Wie du in der geöffneten Insel zwischen Seiten wechselst.",
                         topBar: "Obere Leiste", sideButtons: "Seitliche Tasten",
                         itemsTitle: "Elemente der oberen Leiste",
                         itemsCaption: "Zum Ordnen ziehen. Zum Ausblenden das Häkchen entfernen. Einstellungen steht immer am Ende.",
                         secondaryClick: "Mit Rechtsklick umschalten",
                         secondaryClickCaption: "Ein Rechtsklick auf Wach halten oder das Mikrofon schaltet es ein oder aus.",
                         sideButtonsHint: "Die seitlichen Tasten ordnest du im Tab Layout an.")
        case .fr:
            return .init(tab: "Navigation", styleTitle: "Style de navigation",
                         styleCaption: "Comment passer d’une page à l’autre dans l’île ouverte.",
                         topBar: "Barre supérieure", sideButtons: "Boutons latéraux",
                         itemsTitle: "Éléments de la barre supérieure",
                         itemsCaption: "Faites glisser pour réordonner. Décochez un élément pour le masquer. Réglages reste en dernier.",
                         secondaryClick: "Clic secondaire pour basculer",
                         secondaryClickCaption: "Un clic secondaire sur Garder éveillé ou le micro l’active ou le désactive.",
                         sideButtonsHint: "Disposez les boutons latéraux dans l’onglet Disposition.")
        case .it:
            return .init(tab: "Navigazione", styleTitle: "Stile di navigazione",
                         styleCaption: "Come passi da una pagina all’altra nell’isola aperta.",
                         topBar: "Barra superiore", sideButtons: "Pulsanti laterali",
                         itemsTitle: "Elementi della barra superiore",
                         itemsCaption: "Trascina per riordinare. Deseleziona un elemento per nasconderlo. Impostazioni resta sempre ultimo.",
                         secondaryClick: "Clic secondario per attivare",
                         secondaryClickCaption: "Il clic secondario su Mantieni attivo o sul microfono lo attiva o disattiva.",
                         sideButtonsHint: "Disponi i pulsanti laterali nella scheda Layout.")
        case .ja:
            return .init(tab: "ナビゲーション", styleTitle: "ナビゲーションの種類",
                         styleCaption: "開いたアイランドでページを切り替える方法です。",
                         topBar: "トップバー", sideButtons: "サイドボタン",
                         itemsTitle: "トップバーの項目",
                         itemsCaption: "ドラッグで並べ替え、チェックを外すと非表示になります。設定は常に最後です。",
                         secondaryClick: "右クリックで切り替え",
                         secondaryClickCaption: "スリープ防止またはマイクを右クリックすると、オン・オフが切り替わります。",
                         sideButtonsHint: "サイドボタンは「レイアウト」タブで配置します。")
        case .ko:
            return .init(tab: "탐색", styleTitle: "탐색 방식",
                         styleCaption: "열린 아일랜드에서 페이지 사이를 이동하는 방법입니다.",
                         topBar: "상단 막대", sideButtons: "측면 버튼",
                         itemsTitle: "상단 막대 항목",
                         itemsCaption: "드래그해 순서를 바꾸고, 체크를 해제하면 숨겨집니다. 설정은 항상 마지막입니다.",
                         secondaryClick: "오른쪽 클릭으로 전환",
                         secondaryClickCaption: "잠자기 방지나 마이크를 오른쪽 클릭하면 켜거나 끕니다.",
                         sideButtonsHint: "측면 버튼은 레이아웃 탭에서 배치합니다.")
        case .uk:
            return .init(tab: "Навігація", styleTitle: "Стиль навігації",
                         styleCaption: "Як переходити між сторінками відкритого острова.",
                         topBar: "Верхня панель", sideButtons: "Бічні кнопки",
                         itemsTitle: "Елементи верхньої панелі",
                         itemsCaption: "Перетягніть, щоб змінити порядок. Зніміть позначку, щоб приховати. Налаштування завжди останні.",
                         secondaryClick: "Перемикати правим кліком",
                         secondaryClickCaption: "Правий клік на «Не спати» або мікрофоні вмикає чи вимикає їх.",
                         sideButtonsHint: "Бічні кнопки налаштовуються на вкладці «Макет».")
        case .zhHans:
            return .init(tab: "导航", styleTitle: "导航样式",
                         styleCaption: "在打开的岛中切换页面的方式。",
                         topBar: "顶部栏", sideButtons: "侧边按钮",
                         itemsTitle: "顶部栏项目",
                         itemsCaption: "拖动以重新排序，取消勾选即可隐藏。设置始终在最后。",
                         secondaryClick: "右键点按切换",
                         secondaryClickCaption: "右键点按“保持唤醒”或麦克风即可打开或关闭。",
                         sideButtonsHint: "在“布局”标签页中排列侧边按钮。")
        case .zhTW:
            return .init(tab: "導覽", styleTitle: "導覽樣式",
                         styleCaption: "在開啟的島中切換頁面的方式。",
                         topBar: "頂部列", sideButtons: "側邊按鈕",
                         itemsTitle: "頂部列項目",
                         itemsCaption: "拖移以重新排序，取消勾選即可隱藏。設定一律在最後。",
                         secondaryClick: "按右鍵切換",
                         secondaryClickCaption: "在「保持喚醒」或麥克風上按右鍵即可開啟或關閉。",
                         sideButtonsHint: "在「佈局」標籤頁中排列側邊按鈕。")
        case .zhHK:
            return .init(tab: "導覽", styleTitle: "導覽樣式",
                         styleCaption: "在開啟的島中切換頁面的方式。",
                         topBar: "頂部列", sideButtons: "側邊按鈕",
                         itemsTitle: "頂部列項目",
                         itemsCaption: "拖移以重新排序，取消剔選即可隱藏。設定一律在最後。",
                         secondaryClick: "按右鍵切換",
                         secondaryClickCaption: "在「保持喚醒」或咪高峰上按右鍵即可開啟或關閉。",
                         sideButtonsHint: "在「佈局」標籤頁中排列側邊按鈕。")
        }
    }
}
