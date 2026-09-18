// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// The one-line description under a redesigned Settings page's title, for
/// pages whose own string catalog has no room for it.
struct SettingsPageStrings {
    let energyDescription: String
    let monitorDescription: String
    let mouseDescription: String
    let switcherDescription: String
    let switcherLayoutWindows: String
    let switcherLayoutWindowsCaption: String
    let switcherLayoutIcons: String
    let switcherLayoutSimple: String
}

extension FeatureStrings {
    static func settingsPages(_ language: AppLanguage) -> SettingsPageStrings {
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

extension SettingsPageStrings {
    static let enUS = SettingsPageStrings(
        energyDescription: "Keep the Mac awake, control your displays and save battery.",
        monitorDescription: "What the menu bar and the panel show about your Mac, and when to warn you.",
        mouseDescription: "Give the wheel, the side buttons and the trackpad new jobs.",
        switcherDescription: "Switch between apps and windows your way, and see windows from the Dock.",
        switcherLayoutWindows: "Window previews",
        switcherLayoutWindowsCaption: "One preview per window, minimized ones included.",
        switcherLayoutIcons: "Large icons",
        switcherLayoutSimple: "Simple list"
    )

    static let ptBR = SettingsPageStrings(
        energyDescription: "Mantenha o Mac acordado, controle suas telas e economize bateria.",
        monitorDescription: "O que a barra de menus e o painel mostram sobre o Mac, e quando avisar você.",
        mouseDescription: "Dê novas funções à rodinha, aos botões laterais e ao trackpad.",
        switcherDescription: "Troque de app e de janela do seu jeito, e veja as janelas a partir do Dock.",
        switcherLayoutWindows: "Previews das janelas",
        switcherLayoutWindowsCaption: "Um preview por janela, incluindo as minimizadas.",
        switcherLayoutIcons: "Ícones grandes",
        switcherLayoutSimple: "Lista simples"
    )

    static let tr = SettingsPageStrings(
        energyDescription: "Mac’i uyanık tutun, ekranlarınızı yönetin ve pil tasarrufu yapın.",
        monitorDescription: "Menü çubuğu ve panelin Mac hakkında neler gösterdiği ve sizi ne zaman uyaracağı.",
        mouseDescription: "Tekerleğe, yan tuşlara ve izleme dörtgenine yeni görevler verin.",
        switcherDescription: "Uygulamalar ve pencereler arasında kendi tarzınızda geçin ve pencereleri Dock’tan görün.",
        switcherLayoutWindows: "Pencere önizlemeleri",
        switcherLayoutWindowsCaption: "Her pencere için bir önizleme, simge durumundakiler dahil.",
        switcherLayoutIcons: "Büyük simgeler",
        switcherLayoutSimple: "Basit liste"
    )

    static let ru = SettingsPageStrings(
        energyDescription: "Не давайте Mac уснуть, управляйте экранами и берегите батарею.",
        monitorDescription: "Что строка меню и панель показывают о Mac и когда вас предупреждать.",
        mouseDescription: "Дайте колёсику, боковым кнопкам и трекпаду новые задачи.",
        switcherDescription: "Переключайтесь между приложениями и окнами по-своему и смотрите окна прямо из Dock.",
        switcherLayoutWindows: "Миниатюры окон",
        switcherLayoutWindowsCaption: "По миниатюре на каждое окно, включая свёрнутые.",
        switcherLayoutIcons: "Крупные значки",
        switcherLayoutSimple: "Простой список"
    )

    static let es = SettingsPageStrings(
        energyDescription: "Mantén el Mac despierto, controla tus pantallas y ahorra batería.",
        monitorDescription: "Qué muestran la barra de menús y el panel sobre el Mac, y cuándo avisarte.",
        mouseDescription: "Dale nuevas funciones a la rueda, a los botones laterales y al trackpad.",
        switcherDescription: "Cambia de app y de ventana a tu manera, y mira las ventanas desde el Dock.",
        switcherLayoutWindows: "Vistas previas de ventanas",
        switcherLayoutWindowsCaption: "Una vista previa por ventana, incluidas las minimizadas.",
        switcherLayoutIcons: "Iconos grandes",
        switcherLayoutSimple: "Lista simple"
    )

    static let de = SettingsPageStrings(
        energyDescription: "Halte den Mac wach, steuere deine Bildschirme und spare Batterie.",
        monitorDescription: "Was Menüleiste und Panel über den Mac zeigen und wann du gewarnt wirst.",
        mouseDescription: "Gib dem Scrollrad, den Seitentasten und dem Trackpad neue Aufgaben.",
        switcherDescription: "Wechsle auf deine Art zwischen Apps und Fenstern und sieh Fenster direkt im Dock.",
        switcherLayoutWindows: "Fenstervorschauen",
        switcherLayoutWindowsCaption: "Eine Vorschau pro Fenster, auch für minimierte.",
        switcherLayoutIcons: "Große Symbole",
        switcherLayoutSimple: "Einfache Liste"
    )

    static let fr = SettingsPageStrings(
        energyDescription: "Gardez le Mac éveillé, réglez vos écrans et économisez la batterie.",
        monitorDescription: "Ce que la barre des menus et le panneau montrent du Mac, et quand vous prévenir.",
        mouseDescription: "Donnez de nouveaux rôles à la molette, aux boutons latéraux et au trackpad.",
        switcherDescription: "Passez d’une app ou d’une fenêtre à l’autre à votre façon, et voyez les fenêtres depuis le Dock.",
        switcherLayoutWindows: "Aperçus des fenêtres",
        switcherLayoutWindowsCaption: "Un aperçu par fenêtre, fenêtres réduites comprises.",
        switcherLayoutIcons: "Grandes icônes",
        switcherLayoutSimple: "Liste simple"
    )

    static let it = SettingsPageStrings(
        energyDescription: "Tieni il Mac sveglio, controlla i tuoi schermi e risparmia batteria.",
        monitorDescription: "Cosa mostrano la barra dei menu e il pannello sul Mac, e quando avvisarti.",
        mouseDescription: "Assegna nuovi compiti alla rotellina, ai tasti laterali e al trackpad.",
        switcherDescription: "Passa da un’app o una finestra all’altra a modo tuo, e guarda le finestre dal Dock.",
        switcherLayoutWindows: "Anteprime delle finestre",
        switcherLayoutWindowsCaption: "Un’anteprima per finestra, comprese quelle contratte.",
        switcherLayoutIcons: "Icone grandi",
        switcherLayoutSimple: "Elenco semplice"
    )

    static let ja = SettingsPageStrings(
        energyDescription: "Mac をスリープさせず、ディスプレイを調整し、バッテリーを節約します。",
        monitorDescription: "メニューバーとパネルに Mac の何を表示するか、いつ知らせるか。",
        mouseDescription: "ホイール、サイドボタン、トラックパッドに新しい役割を。",
        switcherDescription: "アプリやウインドウを自分のやり方で切り替え、Dock からウインドウを確認。",
        switcherLayoutWindows: "ウインドウのプレビュー",
        switcherLayoutWindowsCaption: "ウインドウごとにプレビューを表示。しまったウインドウも含みます。",
        switcherLayoutIcons: "大きなアイコン",
        switcherLayoutSimple: "シンプルなリスト"
    )

    static let ko = SettingsPageStrings(
        energyDescription: "Mac을 깨어 있게 하고, 화면을 조절하고, 배터리를 아끼세요.",
        monitorDescription: "메뉴 막대와 패널에 Mac의 무엇을 표시할지, 언제 알릴지.",
        mouseDescription: "휠, 사이드 버튼, 트랙패드에 새 역할을 맡기세요.",
        switcherDescription: "나만의 방식으로 앱과 윈도우를 전환하고, Dock에서 윈도우를 확인하세요.",
        switcherLayoutWindows: "윈도우 미리보기",
        switcherLayoutWindowsCaption: "윈도우마다 미리보기 하나, 축소된 윈도우도 포함합니다.",
        switcherLayoutIcons: "큰 아이콘",
        switcherLayoutSimple: "간단한 목록"
    )

    static let zhHans = SettingsPageStrings(
        energyDescription: "让 Mac 保持唤醒、调节显示器并节省电量。",
        monitorDescription: "菜单栏和面板显示 Mac 的哪些信息，以及何时提醒你。",
        mouseDescription: "让滚轮、侧键和触控板承担新的任务。",
        switcherDescription: "按你的方式切换 App 和窗口，并从程序坞查看窗口。",
        switcherLayoutWindows: "窗口预览",
        switcherLayoutWindowsCaption: "每个窗口一张预览，包括已最小化的窗口。",
        switcherLayoutIcons: "大图标",
        switcherLayoutSimple: "简单列表"
    )

    static let zhTW = SettingsPageStrings(
        energyDescription: "讓 Mac 保持喚醒、調整顯示器並節省電量。",
        monitorDescription: "選單列和面板顯示 Mac 的哪些資訊，以及何時提醒你。",
        mouseDescription: "讓滾輪、側鍵和觸控板承擔新的任務。",
        switcherDescription: "用你的方式切換 App 和視窗，並從 Dock 查看視窗。",
        switcherLayoutWindows: "視窗預覽",
        switcherLayoutWindowsCaption: "每個視窗一張預覽，包括已縮到最小的視窗。",
        switcherLayoutIcons: "大圖示",
        switcherLayoutSimple: "簡單列表"
    )

    static let zhHK = SettingsPageStrings(
        energyDescription: "讓 Mac 保持喚醒、調整顯示器並節省電量。",
        monitorDescription: "選單列和面板顯示 Mac 的哪些資訊，以及何時提醒你。",
        mouseDescription: "讓滾輪、側鍵和觸控板承擔新的任務。",
        switcherDescription: "用你的方式切換 App 和視窗，並從 Dock 查看視窗。",
        switcherLayoutWindows: "視窗預覽",
        switcherLayoutWindowsCaption: "每個視窗一張預覽，包括已縮到最小的視窗。",
        switcherLayoutIcons: "大圖示",
        switcherLayoutSimple: "簡單列表"
    )
}
