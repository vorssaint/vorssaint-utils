// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

struct NotchFullscreenMenuBarStrings {
    let title: String
    let description: String
    /// Shown when macOS itself keeps the menu bar in full screen, so video cannot hide it.
    let systemShowsBarHint: String
}

extension FeatureStrings {
    static func notchFullscreenMenuBar(_ language: AppLanguage) -> NotchFullscreenMenuBarStrings {
        switch language {
        case .enUS: return NotchFullscreenMenuBarStrings(
            title: "Menu bar in full screen",
            description: "Keep the menu bar beside the notch in full-screen apps on the built-in display, and hide it while a video plays full screen. Other displays follow the system setting.",
            systemShowsBarHint: "macOS is set to keep the menu bar in full screen, so full-screen video cannot hide it. Change this in the menu bar settings of System Settings.")
        case .ptBR: return NotchFullscreenMenuBarStrings(
            title: "Barra de menus em tela cheia",
            description: "Mantenha a barra de menus ao lado do entalhe nos apps em tela cheia da tela integrada e oculte-a enquanto um vídeo é reproduzido em tela cheia. As outras telas seguem o ajuste do sistema.",
            systemShowsBarHint: "O macOS está ajustado para manter a barra de menus em tela cheia, então um vídeo em tela cheia não pode ocultá-la. Altere isso nos ajustes da barra de menus nos Ajustes do Sistema.")
        case .tr: return NotchFullscreenMenuBarStrings(
            title: "Tam ekranda menü çubuğu",
            description: "Yerleşik ekrandaki tam ekran uygulamalarda menü çubuğunu çentiğin yanında tutar, bir video tam ekran oynatılırken gizler. Diğer ekranlar sistem ayarını izler.",
            systemShowsBarHint: "macOS menü çubuğunu tam ekranda gösterecek şekilde ayarlı, bu yüzden tam ekran video onu gizleyemez. Bunu Sistem Ayarları’ndaki menü çubuğu ayarlarından değiştirin.")
        case .ru: return NotchFullscreenMenuBarStrings(
            title: "Строка меню в полноэкранном режиме",
            description: "Строка меню остается рядом с вырезом в полноэкранных приложениях на встроенном дисплее и скрывается, пока видео воспроизводится на весь экран. Другие дисплеи следуют системной настройке.",
            systemShowsBarHint: "В macOS включен показ строки меню в полноэкранном режиме, поэтому полноэкранное видео не может ее скрыть. Это можно изменить в настройках строки меню в Системных настройках.")
        case .es: return NotchFullscreenMenuBarStrings(
            title: "Barra de menús a pantalla completa",
            description: "Mantiene la barra de menús junto a la muesca en las apps a pantalla completa de la pantalla integrada y la oculta mientras se reproduce un vídeo a pantalla completa. Las demás pantallas siguen el ajuste del sistema.",
            systemShowsBarHint: "macOS está configurado para mantener la barra de menús a pantalla completa, así que un vídeo a pantalla completa no puede ocultarla. Cámbialo en los ajustes de la barra de menús de Ajustes del Sistema.")
        case .sk: return NotchFullscreenMenuBarStrings(
            title: "Lišta menu na celej obrazovke",
            description: "Ponechá lištu menu vedľa výrezu v apkách na celej obrazovke na vstavanom displeji a skryje ju, kým sa video prehráva na celej obrazovke. Ostatné displeje sa riadia nastavením systému.",
            systemShowsBarHint: "macOS je nastavený tak, aby lištu menu na celej obrazovke ponechal, takže video na celej obrazovke ju nemôže skryť. Zmeňte to v nastaveniach lišty menu v Systémových nastaveniach.")
        case .de: return NotchFullscreenMenuBarStrings(
            title: "Menüleiste im Vollbildmodus",
            description: "Behält die Menüleiste neben der Kerbe in Vollbild-Apps auf dem integrierten Display und blendet sie aus, während ein Video im Vollbild läuft. Andere Displays folgen der Systemeinstellung.",
            systemShowsBarHint: "macOS ist so eingestellt, dass die Menüleiste im Vollbildmodus bleibt, daher kann ein Video im Vollbild sie nicht ausblenden. Ändere dies in den Menüleisteneinstellungen der Systemeinstellungen.")
        case .fr: return NotchFullscreenMenuBarStrings(
            title: "Barre des menus en plein écran",
            description: "Garde la barre des menus à côté de l’encoche dans les apps en plein écran sur l’écran intégré et la masque pendant la lecture d’une vidéo en plein écran. Les autres écrans suivent le réglage du système.",
            systemShowsBarHint: "macOS est réglé pour garder la barre des menus en plein écran : une vidéo en plein écran ne peut donc pas la masquer. Modifiez cela dans les réglages de la barre des menus des Réglages Système.")
        case .it: return NotchFullscreenMenuBarStrings(
            title: "Barra dei menu a tutto schermo",
            description: "Mantiene la barra dei menu accanto al notch nelle app a tutto schermo sul display integrato e la nasconde mentre un video viene riprodotto a tutto schermo. Gli altri display seguono l’impostazione di sistema.",
            systemShowsBarHint: "macOS è impostato per mantenere la barra dei menu a tutto schermo, quindi un video a tutto schermo non può nasconderla. Modificalo nelle impostazioni della barra dei menu in Impostazioni di Sistema.")
        case .ja: return NotchFullscreenMenuBarStrings(
            title: "フルスクリーンでのメニューバー",
            description: "内蔵ディスプレイのフルスクリーンアプリで、ノッチの横にメニューバーを表示したままにし、ビデオをフルスクリーンで再生している間は隠します。ほかのディスプレイはシステムの設定に従います。",
            systemShowsBarHint: "macOSがフルスクリーンでもメニューバーを表示する設定になっているため、フルスクリーンのビデオでは隠せません。システム設定のメニューバーの設定で変更してください。")
        case .ko: return NotchFullscreenMenuBarStrings(
            title: "전체 화면에서 메뉴 막대",
            description: "내장 디스플레이의 전체 화면 앱에서 노치 옆에 메뉴 막대를 계속 표시하고, 비디오가 전체 화면으로 재생되는 동안에는 숨깁니다. 다른 디스플레이는 시스템 설정을 따릅니다.",
            systemShowsBarHint: "macOS가 전체 화면에서도 메뉴 막대를 표시하도록 설정되어 있어 전체 화면 비디오가 메뉴 막대를 숨길 수 없습니다. 시스템 설정의 메뉴 막대 설정에서 변경하십시오.")
        case .uk: return NotchFullscreenMenuBarStrings(
            title: "Рядок меню на весь екран",
            description: "Рядок меню залишається поруч із вирізом у повноекранних програмах на вбудованому дисплеї та ховається, поки відео відтворюється на весь екран. Інші дисплеї дотримуються системного параметра.",
            systemShowsBarHint: "У macOS увімкнено показ рядка меню на весь екран, тому повноекранне відео не може його сховати. Змініть це в параметрах рядка меню в Системних параметрах.")
        case .zhHans: return NotchFullscreenMenuBarStrings(
            title: "全屏幕时的菜单栏",
            description: "在内建显示器的全屏幕 App 中，让菜单栏保留在刘海旁边，并在视频全屏幕播放时将其隐藏。其他显示器遵循系统设置。",
            systemShowsBarHint: "macOS 设置为在全屏幕时保留菜单栏，因此全屏幕视频无法将其隐藏。请在“系统设置”的菜单栏设置中更改。")
        case .zhTW: return NotchFullscreenMenuBarStrings(
            title: "全螢幕時的選單列",
            description: "在內建顯示器的全螢幕 App 中，讓選單列保留在瀏海旁邊，並在影片以全螢幕播放時將其隱藏。其他顯示器遵循系統設定。",
            systemShowsBarHint: "macOS 設定為在全螢幕時保留選單列，因此全螢幕影片無法將其隱藏。請在「系統設定」的選單列設定中更改。")
        case .zhHK: return NotchFullscreenMenuBarStrings(
            title: "全螢幕時的選單列",
            description: "在內置顯示器的全螢幕 App 中，讓選單列保留在瀏海旁邊，並在影片以全螢幕播放時將其隱藏。其他顯示器遵循系統設定。",
            systemShowsBarHint: "macOS 設定為在全螢幕時保留選單列，因此全螢幕影片無法將其隱藏。請在「系統設定」的選單列設定中更改。")
        }
    }
}
