// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

struct NotchSpacesStrings {
    let allDisplays: String
    let allDisplaysHint: String
    let spaceFormat: String
    let showWhenIdle: String
    let title: String
    let description: String
    let desktopFormat: String
    let fullscreen: String
    let rename: String
    let resetName: String
    let showCurrent: String
    let shortcutHint: String
    let unavailable: String
    let gestureHint: String
}

extension FeatureStrings {
    static func notchSpaces(_ language: AppLanguage) -> NotchSpacesStrings {
        switch language {
        case .enUS: return NotchSpacesStrings(
            allDisplays: "Show Spaces from all displays",
            allDisplaysHint: "Show desktops from the built-in and external displays in the Dynamic Island. Selecting a desktop switches its display.",
            spaceFormat: "Space %d",
            showWhenIdle: "Show Spaces when the island is idle",
            title: "Spaces",
            description: "Name desktops and switch between them on the pointer’s display.",
            desktopFormat: "Desktop %d",
            fullscreen: "Full Screen",
            rename: "Rename",
            resetName: "Reset Name",
            showCurrent: "Show current Space in the closed island",
            shortcutHint: "Enable Move left/right a space in System Settings > Keyboard > Keyboard Shortcuts > Mission Control.",
            unavailable: "Spaces are unavailable on this display.",
            gestureHint: "Swipe left or right, or use the arrow keys to switch.")
        case .ptBR: return NotchSpacesStrings(
            allDisplays: "Mostrar Spaces de todas as telas",
            allDisplaysHint: "Mostre as mesas das telas integrada e externas na Ilha Dinâmica. Selecionar uma mesa alterna a tela correspondente.",
            spaceFormat: "Space %d",
            showWhenIdle: "Mostrar Spaces quando a ilha estiver ociosa",
            title: "Spaces",
            description: "Nomeie as mesas e alterne entre elas na tela do cursor.",
            desktopFormat: "Mesa %d",
            fullscreen: "Tela Cheia",
            rename: "Renomear",
            resetName: "Redefinir Nome",
            showCurrent: "Mostrar o Space atual na ilha fechada",
            shortcutHint: "Ative Mover um espaço à esquerda/direita em Ajustes do Sistema > Teclado > Atalhos de Teclado > Mission Control.",
            unavailable: "Spaces indisponíveis nesta tela.",
            gestureHint: "Deslize para a esquerda ou direita ou use as setas para alternar.")
        case .tr: return NotchSpacesStrings(
            allDisplays: "Tüm ekranların alanlarını göster",
            allDisplaysHint: "Yerleşik ve harici ekranların masaüstlerini Dinamik Ada’da gösterir. Bir masaüstü seçildiğinde ait olduğu ekran geçiş yapar.",
            spaceFormat: "Alan %d",
            showWhenIdle: "Ada boştayken alanları göster",
            title: "Alanlar",
            description: "Masaüstlerini adlandırın ve imlecin bulunduğu ekranda aralarında geçiş yapın.",
            desktopFormat: "Masaüstü %d",
            fullscreen: "Tam Ekran",
            rename: "Yeniden Adlandır",
            resetName: "Adı Sıfırla",
            showCurrent: "Kapalı adada geçerli alanı göster",
            shortcutHint: "Sistem Ayarları > Klavye > Klavye Kestirmeleri > Mission Control bölümünde bir alan sola/sağa gitmeyi etkinleştirin.",
            unavailable: "Bu ekranda alanlar kullanılamıyor.",
            gestureHint: "Geçiş için sola veya sağa kaydırın ya da ok tuşlarını kullanın.")
        case .ru: return NotchSpacesStrings(
            allDisplays: "Показывать пространства всех экранов",
            allDisplaysHint: "Показывает рабочие столы встроенного и внешних экранов в динамическом острове. Выбор стола переключает соответствующий экран.",
            spaceFormat: "Пространство %d",
            showWhenIdle: "Показывать пространства, когда остров не занят",
            title: "Пространства",
            description: "Назовите рабочие столы и переключайте их на экране с указателем.",
            desktopFormat: "Рабочий стол %d",
            fullscreen: "Полный экран",
            rename: "Переименовать",
            resetName: "Сбросить имя",
            showCurrent: "Показывать текущее пространство в закрытом острове",
            shortcutHint: "Включите переход влево/вправо между пространствами в Системные настройки > Клавиатура > Сочетания клавиш > Mission Control.",
            unavailable: "Пространства недоступны на этом экране.",
            gestureHint: "Смахните влево или вправо либо используйте клавиши со стрелками.")
        case .es: return NotchSpacesStrings(
            allDisplays: "Mostrar espacios de todas las pantallas",
            allDisplaysHint: "Muestra los escritorios de las pantallas integrada y externas en la isla dinámica. Al elegir un escritorio, cambia su pantalla.",
            spaceFormat: "Espacio %d",
            showWhenIdle: "Mostrar espacios cuando la isla esté inactiva",
            title: "Espacios",
            description: "Asigna nombres a los escritorios y cambia entre ellos en la pantalla del cursor.",
            desktopFormat: "Escritorio %d",
            fullscreen: "Pantalla completa",
            rename: "Renombrar",
            resetName: "Restablecer nombre",
            showCurrent: "Mostrar el espacio actual en la isla cerrada",
            shortcutHint: "Activa Ir un espacio a la izquierda/derecha en Ajustes del Sistema > Teclado > Funciones rápidas de teclado > Mission Control.",
            unavailable: "Los espacios no están disponibles en esta pantalla.",
            gestureHint: "Desliza a izquierda o derecha, o usa las flechas para cambiar.")
        case .sk: return NotchSpacesStrings(
            allDisplays: "Zobraziť plochy zo všetkých displejov",
            allDisplaysHint: "Zobrazí plochy vstavaného a externých displejov v dynamickom ostrove. Výber plochy prepne príslušný displej.",
            spaceFormat: "Plocha %d",
            showWhenIdle: "Zobraziť plochy, keď je ostrov nečinný",
            title: "Plochy",
            description: "Pomenujte plochy a prepínajte medzi nimi na displeji s kurzorom.",
            desktopFormat: "Plocha %d",
            fullscreen: "Celá obrazovka",
            rename: "Premenovať",
            resetName: "Obnoviť názov",
            showCurrent: "Zobraziť aktuálnu plochu v zatvorenom ostrove",
            shortcutHint: "Zapnite presun o plochu doľava/doprava v Systémové nastavenia > Klávesnica > Klávesové skratky > Mission Control.",
            unavailable: "Plochy na tomto displeji nie sú dostupné.",
            gestureHint: "Prepínajte potiahnutím doľava alebo doprava alebo šípkami.")
        case .de: return NotchSpacesStrings(
            allDisplays: "Spaces aller Bildschirme anzeigen",
            allDisplaysHint: "Zeigt Schreibtische des integrierten und externer Bildschirme in der Dynamic Island. Die Auswahl wechselt den zugehörigen Bildschirm.",
            spaceFormat: "Space %d",
            showWhenIdle: "Spaces anzeigen, wenn die Insel untätig ist",
            title: "Spaces",
            description: "Benenne Schreibtische und wechsle auf dem Bildschirm mit dem Zeiger zwischen ihnen.",
            desktopFormat: "Schreibtisch %d",
            fullscreen: "Vollbild",
            rename: "Umbenennen",
            resetName: "Namen zurücksetzen",
            showCurrent: "Aktuellen Space in der geschlossenen Insel anzeigen",
            shortcutHint: "Aktiviere Space nach links/rechts wechseln unter Systemeinstellungen > Tastatur > Tastaturkurzbefehle > Mission Control.",
            unavailable: "Spaces sind auf diesem Bildschirm nicht verfügbar.",
            gestureHint: "Wische nach links oder rechts oder verwende die Pfeiltasten.")
        case .fr: return NotchSpacesStrings(
            allDisplays: "Afficher les espaces de tous les écrans",
            allDisplaysHint: "Affiche les bureaux des écrans intégré et externes dans l’îlot dynamique. Choisir un bureau change l’espace de son écran.",
            spaceFormat: "Espace %d",
            showWhenIdle: "Afficher les espaces quand l’îlot est inactif",
            title: "Espaces",
            description: "Nommez les bureaux et passez de l’un à l’autre sur l’écran du pointeur.",
            desktopFormat: "Bureau %d",
            fullscreen: "Plein écran",
            rename: "Renommer",
            resetName: "Réinitialiser le nom",
            showCurrent: "Afficher l’espace actuel dans l’îlot fermé",
            shortcutHint: "Activez le déplacement à gauche/droite d’un espace dans Réglages Système > Clavier > Raccourcis clavier > Mission Control.",
            unavailable: "Les espaces sont indisponibles sur cet écran.",
            gestureHint: "Balayez vers la gauche ou la droite, ou utilisez les touches fléchées.")
        case .it: return NotchSpacesStrings(
            allDisplays: "Mostra gli spazi di tutti gli schermi",
            allDisplaysHint: "Mostra le scrivanie degli schermi integrato ed esterni nell’isola dinamica. La selezione cambia lo spazio dello schermo corrispondente.",
            spaceFormat: "Spazio %d",
            showWhenIdle: "Mostra gli spazi quando l’isola è inattiva",
            title: "Spazi",
            description: "Assegna nomi alle scrivanie e passa da una all’altra sullo schermo del puntatore.",
            desktopFormat: "Scrivania %d",
            fullscreen: "Schermo intero",
            rename: "Rinomina",
            resetName: "Ripristina nome",
            showCurrent: "Mostra lo spazio attuale nell’isola chiusa",
            shortcutHint: "Attiva il passaggio a sinistra/destra di uno spazio in Impostazioni di Sistema > Tastiera > Abbreviazioni da tastiera > Mission Control.",
            unavailable: "Gli spazi non sono disponibili su questo schermo.",
            gestureHint: "Scorri a sinistra o destra, oppure usa i tasti freccia.")
        case .ja: return NotchSpacesStrings(
            allDisplays: "すべてのディスプレイの操作スペースを表示",
            allDisplaysHint: "内蔵および外部ディスプレイのデスクトップをダイナミックアイランドに表示します。選択したデスクトップのディスプレイが切り替わります。",
            spaceFormat: "操作スペース %d",
            showWhenIdle: "アイランドが待機中のときに操作スペースを表示",
            title: "操作スペース",
            description: "デスクトップに名前を付け、ポインタのある画面で切り替えます。",
            desktopFormat: "デスクトップ %d",
            fullscreen: "フルスクリーン",
            rename: "名前を変更",
            resetName: "名前をリセット",
            showCurrent: "閉じたアイランドに現在の操作スペースを表示",
            shortcutHint: "システム設定 > キーボード > キーボードショートカット > Mission Controlで、左／右の操作スペースに移動を有効にしてください。",
            unavailable: "この画面では操作スペースを利用できません。",
            gestureHint: "左右にスワイプするか、矢印キーで切り替えます。")
        case .ko: return NotchSpacesStrings(
            allDisplays: "모든 디스플레이의 Space 표시",
            allDisplaysHint: "내장 및 외장 디스플레이의 데스크탑을 다이내믹 아일랜드에 표시합니다. 데스크탑을 선택하면 해당 디스플레이가 전환됩니다.",
            spaceFormat: "작업 공간 %d",
            showWhenIdle: "아일랜드가 대기 중일 때 작업 공간 표시",
            title: "작업 공간",
            description: "데스크탑에 이름을 지정하고 포인터가 있는 화면에서 전환합니다.",
            desktopFormat: "데스크탑 %d",
            fullscreen: "전체 화면",
            rename: "이름 변경",
            resetName: "이름 재설정",
            showCurrent: "닫힌 아일랜드에 현재 작업 공간 표시",
            shortcutHint: "시스템 설정 > 키보드 > 키보드 단축키 > Mission Control에서 왼쪽/오른쪽 공간으로 이동을 켜세요.",
            unavailable: "이 화면에서 작업 공간을 사용할 수 없습니다.",
            gestureHint: "좌우로 쓸어넘기거나 화살표 키로 전환하세요.")
        case .uk: return NotchSpacesStrings(
            allDisplays: "Показувати простори всіх дисплеїв",
            allDisplaysHint: "Показує робочі столи вбудованого й зовнішніх дисплеїв у динамічному острові. Вибір столу перемикає відповідний дисплей.",
            spaceFormat: "Простір %d",
            showWhenIdle: "Показувати простори, коли острів не зайнятий",
            title: "Простори",
            description: "Назвіть робочі столи й перемикайте їх на екрані з вказівником.",
            desktopFormat: "Робочий стіл %d",
            fullscreen: "Повний екран",
            rename: "Перейменувати",
            resetName: "Скинути назву",
            showCurrent: "Показувати поточний простір у закритому острові",
            shortcutHint: "Увімкніть перехід ліворуч/праворуч між просторами в Системні параметри > Клавіатура > Клавіатурні скорочення > Mission Control.",
            unavailable: "Простори недоступні на цьому екрані.",
            gestureHint: "Проведіть ліворуч або праворуч чи скористайтеся клавішами зі стрілками.")
        case .zhHans: return NotchSpacesStrings(
            allDisplays: "显示所有显示器的空间",
            allDisplaysHint: "在灵动岛中显示内置和外接显示器的桌面。选择桌面会切换其所在显示器的空间。",
            spaceFormat: "空间 %d",
            showWhenIdle: "灵动岛空闲时显示空间",
            title: "空间",
            description: "为桌面命名，并在指针所在的显示器上切换。",
            desktopFormat: "桌面 %d",
            fullscreen: "全屏",
            rename: "重命名",
            resetName: "重置名称",
            showCurrent: "在收起的灵动岛中显示当前空间",
            shortcutHint: "请在系统设置 > 键盘 > 键盘快捷键 > Mission Control 中启用向左／向右移动一个空间。",
            unavailable: "此显示器上的空间不可用。",
            gestureHint: "向左或向右轻扫，或使用方向键切换。")
        case .zhTW: return NotchSpacesStrings(
            allDisplays: "顯示所有顯示器的空間",
            allDisplaysHint: "在動態島中顯示內建和外接顯示器的桌面。選取桌面會切換其所在顯示器的空間。",
            spaceFormat: "空間 %d",
            showWhenIdle: "動態島閒置時顯示空間",
            title: "空間",
            description: "為桌面命名，並在指標所在的顯示器上切換。",
            desktopFormat: "桌面 %d",
            fullscreen: "全螢幕",
            rename: "重新命名",
            resetName: "重設名稱",
            showCurrent: "在收合的動態島中顯示目前空間",
            shortcutHint: "請在系統設定 > 鍵盤 > 鍵盤快速鍵 > Mission Control 中啟用向左／向右移動一個空間。",
            unavailable: "此顯示器上的空間無法使用。",
            gestureHint: "向左或向右滑動，或使用方向鍵切換。")
        case .zhHK: return NotchSpacesStrings(
            allDisplays: "顯示所有顯示器的空間",
            allDisplaysHint: "在動態島中顯示內置和外接顯示器的桌面。選取桌面會切換其所在顯示器的空間。",
            spaceFormat: "空間 %d",
            showWhenIdle: "動態島閒置時顯示空間",
            title: "空間",
            description: "為桌面命名，並在指標所在的顯示器上切換。",
            desktopFormat: "桌面 %d",
            fullscreen: "全螢幕",
            rename: "重新命名",
            resetName: "重設名稱",
            showCurrent: "在收合的動態島中顯示目前空間",
            shortcutHint: "請在系統設定 > 鍵盤 > 鍵盤快捷鍵 > Mission Control 中啟用向左／向右移動一個空間。",
            unavailable: "此顯示器上的空間無法使用。",
            gestureHint: "向左或向右滑動，或使用方向鍵切換。")
        }
    }
}
