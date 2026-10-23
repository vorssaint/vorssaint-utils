// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// Copy for the two menu bar icon gestures. The two hints say the one thing
/// neither gesture can explain by itself: the middle button is the mouse's, and
/// a hold is committed when it is released on the icon.
struct StatusItemQuickActionStrings {
    let title: String
    let middleClick: String
    let longPress: String
    let soundMute: String
    let middleHint: String
    let holdHint: String
    let unavailable: String
    /// How the Permissions tab names this gesture among Accessibility users.
    let middleClickUsage: String

    static func localized(_ language: AppLanguage) -> Self {
        switch language {
        case .enUS: return .init(title: "Menu bar icon quick actions",
            middleClick: "Middle-click", longPress: "Press and hold", soundMute: "Mute / unmute sound",
            middleHint: "Uses the mouse’s middle button, not its side buttons.",
            holdHint: "Hold for half a second, then release on the icon. Drag away to cancel.",
            unavailable: "Unavailable until this feature is installed",
            middleClickUsage: "Middle-click on the menu bar icon")
        case .ptBR: return .init(title: "Ações rápidas do ícone da barra de menus",
            middleClick: "Clique do meio", longPress: "Manter pressionado", soundMute: "Silenciar / ativar som",
            middleHint: "Usa o botão do meio do mouse, não os botões laterais.",
            holdHint: "Segure por meio segundo e solte sobre o ícone. Arraste para fora para cancelar.",
            unavailable: "Indisponível até instalar este recurso",
            middleClickUsage: "Clique do meio no ícone da barra de menus")
        case .tr: return .init(title: "Menü çubuğu simgesi hızlı eylemleri",
            middleClick: "Orta tıklama", longPress: "Basılı tutma", soundMute: "Sistem sesini sustur / aç",
            middleHint: "Yan düğmeleri değil farenin orta düğmesini kullanır.",
            holdHint: "Yarım saniye basılı tutup simge üzerinde bırakın. İptal için dışarı sürükleyin.",
            unavailable: "Bu özellik yüklenene kadar kullanılamaz",
            middleClickUsage: "Menü çubuğu simgesinde orta tıklama")
        case .ru: return .init(title: "Быстрые действия значка в строке меню",
            middleClick: "Средняя кнопка", longPress: "Удержание", soundMute: "Выключить / включить звук",
            middleHint: "Используется средняя кнопка мыши, не боковые.",
            holdHint: "Удерживайте полсекунды и отпустите над значком. Уведите курсор, чтобы отменить.",
            unavailable: "Недоступно, пока функция не установлена",
            middleClickUsage: "Средняя кнопка на значке в строке меню")
        case .es: return .init(title: "Acciones rápidas del icono de la barra de menús",
            middleClick: "Clic central", longPress: "Mantener pulsado", soundMute: "Silenciar / activar sonido",
            middleHint: "Usa el botón central del ratón, no los laterales.",
            holdHint: "Mantén medio segundo y suelta sobre el icono. Arrastra fuera para cancelar.",
            unavailable: "No disponible hasta instalar esta función",
            middleClickUsage: "Clic central en el icono de la barra de menús")
        case .sk: return .init(title: "Rýchle akcie ikony v lište",
            middleClick: "Stredné kliknutie", longPress: "Podržanie", soundMute: "Stlmiť / zapnúť zvuk",
            middleHint: "Používa stredné tlačidlo myši, nie bočné tlačidlá.",
            holdHint: "Podržte pol sekundy a pustite na ikone. Odtiahnutím zrušíte.",
            unavailable: "Nedostupné, kým funkciu nenainštalujete",
            middleClickUsage: "Stredné kliknutie na ikonu v lište")
        case .de: return .init(title: "Schnellaktionen für das Menüleistensymbol",
            middleClick: "Mittelklick", longPress: "Gedrückt halten", soundMute: "Ton aus- / einschalten",
            middleHint: "Verwendet die mittlere Maustaste, nicht die Seitentasten.",
            holdHint: "Eine halbe Sekunde halten und auf dem Symbol loslassen. Zum Abbrechen wegziehen.",
            unavailable: "Nicht verfügbar, bis diese Funktion installiert ist",
            middleClickUsage: "Mittelklick auf das Menüleistensymbol")
        case .fr: return .init(title: "Actions rapides de l’icône de la barre des menus",
            middleClick: "Clic du milieu", longPress: "Appui prolongé", soundMute: "Couper / rétablir le son",
            middleHint: "Utilise le bouton central de la souris, pas les boutons latéraux.",
            holdHint: "Maintenez une demi-seconde puis relâchez sur l’icône. Éloignez pour annuler.",
            unavailable: "Indisponible tant que cette fonction n’est pas installée",
            middleClickUsage: "Clic du milieu sur l’icône de la barre des menus")
        case .it: return .init(title: "Azioni rapide dell’icona nella barra dei menu",
            middleClick: "Clic centrale", longPress: "Pressione prolungata", soundMute: "Disattiva / attiva audio",
            middleHint: "Usa il tasto centrale del mouse, non quelli laterali.",
            holdHint: "Tieni premuto mezzo secondo e rilascia sull’icona. Trascina via per annullare.",
            unavailable: "Non disponibile finché la funzione non è installata",
            middleClickUsage: "Clic centrale sull’icona nella barra dei menu")
        case .ja: return .init(title: "メニューバーアイコンのクイック操作",
            middleClick: "中クリック", longPress: "長押し", soundMute: "システム音声のミュート切替",
            middleHint: "サイドボタンではなくマウスの中ボタンを使用します。",
            holdHint: "0.5秒押してアイコン上で離します。外へドラッグするとキャンセルします。",
            unavailable: "この機能をインストールするまで使用できません",
            middleClickUsage: "メニューバーアイコンの中クリック")
        case .ko: return .init(title: "메뉴 막대 아이콘 빠른 동작",
            middleClick: "가운데 클릭", longPress: "길게 누르기", soundMute: "시스템 소리 음소거 전환",
            middleHint: "측면 버튼이 아닌 마우스 가운데 버튼을 사용합니다.",
            holdHint: "0.5초 누른 뒤 아이콘에서 놓으세요. 밖으로 드래그하면 취소됩니다.",
            unavailable: "이 기능을 설치할 때까지 사용할 수 없습니다",
            middleClickUsage: "메뉴 막대 아이콘 가운데 클릭")
        case .uk: return .init(title: "Швидкі дії значка смуги меню",
            middleClick: "Середня кнопка", longPress: "Утримування", soundMute: "Вимкнути / увімкнути звук",
            middleHint: "Використовує середню кнопку миші, а не бічні.",
            holdHint: "Утримуйте пів секунди й відпустіть над значком. Відведіть для скасування.",
            unavailable: "Недоступно, поки цю функцію не встановлено",
            middleClickUsage: "Середня кнопка на значку смуги меню")
        case .zhHans: return .init(title: "菜单栏图标快捷操作",
            middleClick: "中键点按", longPress: "长按", soundMute: "切换系统静音",
            middleHint: "使用鼠标中键，不使用侧键。",
            holdHint: "按住半秒后在图标上松开。拖出图标可取消。",
            unavailable: "安装此功能后方可使用",
            middleClickUsage: "菜单栏图标中键点按")
        case .zhTW: return .init(title: "選單列圖示快速動作",
            middleClick: "中鍵點按", longPress: "長按", soundMute: "切換系統靜音",
            middleHint: "使用滑鼠中鍵，而非側鍵。",
            holdHint: "按住半秒後在圖示上放開。拖出圖示可取消。",
            unavailable: "安裝此功能後才能使用",
            middleClickUsage: "選單列圖示中鍵點按")
        case .zhHK: return .init(title: "選單列圖示快捷操作",
            middleClick: "中鍵點按", longPress: "長按", soundMute: "切換系統靜音",
            middleHint: "使用滑鼠中鍵，而非側鍵。",
            holdHint: "按住半秒後在圖示上放開。拖出圖示可取消。",
            unavailable: "安裝此功能後才能使用",
            middleClickUsage: "選單列圖示中鍵點按")
        }
    }
}

extension StatusItemQuickAction {
    func title(_ language: AppLanguage) -> String {
        switch self {
        case .none: return FeatureStrings.radialMenu(language).mouseTriggerOff
        case .keepAwake: return Strings.localized(language).keepAwakeTitle
        case .micMute: return Strings.localized(language).micMuteName
        case .soundMute: return StatusItemQuickActionStrings.localized(language).soundMute
        case .screenRecorder: return FeatureStrings.recorder(language).pageTitle
        case .screenshot: return FeatureStrings.screenshot(language).pageTitle
        }
    }
}
