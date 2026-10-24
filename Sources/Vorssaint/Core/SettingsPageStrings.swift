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
    let dockTitle: String
    let dockDescription: String
    let dockTweaks: String
    let dockTweaksDescription: String
    let dockSizeLock: String
    let dockSizeLockCaption: String
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

extension SettingsPageStrings {
    static let uk = SettingsPageStrings(
        energyDescription: "Не давайте Mac заснути, керуйте екранами та заощаджуйте заряд акумулятора.",
        monitorDescription: "Що смуга меню й панель показують про Mac та коли попереджати вас.",
        mouseDescription: "Дайте колесу, боковим кнопкам і трекпеду нові функції.",
        switcherDescription: "Перемикайте програми й вікна на свій лад.",
        dockTitle: "Dock",
        dockDescription: "Переглядайте вікна програми з її значка в Dock і вибирайте, що робить клацання по ньому.",
        dockTweaks: "Налаштування Dock",
        dockTweaksDescription: "Дрібні зміни поведінки Dock, як-от блокування його розміру.",
        dockSizeLock: "Заблокувати розмір Dock",
        dockSizeLockCaption: "Не дає змінювати розмір Dock перетягуванням його роздільника. Щоб застосувати зміну, Dock один раз перезапуститься.",
        switcherLayoutWindows: "Мініатюри вікон",
        switcherLayoutWindowsCaption: "По одній мініатюрі для кожного вікна, включно зі згорнутими.",
        switcherLayoutIcons: "Великі значки",
        switcherLayoutSimple: "Простий список"
    )

    static let enUS = SettingsPageStrings(
        energyDescription: "Keep the Mac awake, control your displays and save battery.",
        monitorDescription: "What the menu bar and the panel show about your Mac, and when to warn you.",
        mouseDescription: "Give the wheel, the side buttons and the trackpad new jobs.",
        switcherDescription: "Switch between apps and windows your way.",
        dockTitle: "Dock",
        dockDescription: "See an app’s windows from its Dock icon, and choose what a click on it does.",
        dockTweaks: "Dock tweaks",
        dockTweaksDescription: "Small changes to how the Dock behaves, such as locking its size.",
        dockSizeLock: "Lock the Dock size",
        dockSizeLockCaption: "Stops the Dock from being resized by dragging its divider. The Dock restarts once to apply the change.",
        switcherLayoutWindows: "Window previews",
        switcherLayoutWindowsCaption: "One preview per window, minimized ones included.",
        switcherLayoutIcons: "Large icons",
        switcherLayoutSimple: "Simple list"
    )

    static let ptBR = SettingsPageStrings(
        energyDescription: "Mantenha o Mac acordado, controle suas telas e economize bateria.",
        monitorDescription: "O que a barra de menus e o painel mostram sobre o Mac, e quando avisar você.",
        mouseDescription: "Dê novas funções à rodinha, aos botões laterais e ao trackpad.",
        switcherDescription: "Troque de app e de janela do seu jeito.",
        dockTitle: "Dock",
        dockDescription: "Veja as janelas de um app pelo ícone no Dock e escolha o que um clique nele faz.",
        dockTweaks: "Ajustes do Dock",
        dockTweaksDescription: "Pequenas mudanças no comportamento do Dock, como travar o tamanho dele.",
        dockSizeLock: "Travar o tamanho do Dock",
        dockSizeLockCaption: "Impede que o Dock seja redimensionado ao arrastar o divisor. O Dock reinicia uma vez para aplicar a mudança.",
        switcherLayoutWindows: "Previews das janelas",
        switcherLayoutWindowsCaption: "Um preview por janela, incluindo as minimizadas.",
        switcherLayoutIcons: "Ícones grandes",
        switcherLayoutSimple: "Lista simples"
    )

    static let tr = SettingsPageStrings(
        energyDescription: "Mac’i uyanık tutun, ekranlarınızı yönetin ve pil tasarrufu yapın.",
        monitorDescription: "Menü çubuğu ve panelin Mac hakkında neler gösterdiği ve sizi ne zaman uyaracağı.",
        mouseDescription: "Tekerleğe, yan tuşlara ve izleme dörtgenine yeni görevler verin.",
        switcherDescription: "Uygulamalar ve pencereler arasında kendi tarzınızda geçin.",
        dockTitle: "Dock",
        dockDescription: "Bir uygulamanın pencerelerini Dock simgesinden görün ve simgeye tıklamanın ne yapacağını seçin.",
        dockTweaks: "Dock ince ayarları",
        dockTweaksDescription: "Dock’un davranışında küçük değişiklikler; örneğin boyutunu kilitlemek.",
        dockSizeLock: "Dock boyutunu kilitle",
        dockSizeLockCaption: "Dock’un ayırıcısı sürüklenerek yeniden boyutlandırılmasını engeller. Değişikliği uygulamak için Dock bir kez yeniden başlar.",
        switcherLayoutWindows: "Pencere önizlemeleri",
        switcherLayoutWindowsCaption: "Her pencere için bir önizleme, simge durumundakiler dahil.",
        switcherLayoutIcons: "Büyük simgeler",
        switcherLayoutSimple: "Basit liste"
    )

    static let ru = SettingsPageStrings(
        energyDescription: "Не давайте Mac уснуть, управляйте экранами и берегите батарею.",
        monitorDescription: "Что строка меню и панель показывают о Mac и когда вас предупреждать.",
        mouseDescription: "Дайте колёсику, боковым кнопкам и трекпаду новые задачи.",
        switcherDescription: "Переключайтесь между приложениями и окнами по-своему.",
        dockTitle: "Dock",
        dockDescription: "Смотрите окна приложения по его значку в Dock и выбирайте, что делает щелчок по нему.",
        dockTweaks: "Настройки Dock",
        dockTweaksDescription: "Небольшие изменения в поведении Dock, например фиксация его размера.",
        dockSizeLock: "Зафиксировать размер Dock",
        dockSizeLockCaption: "Не даёт менять размер Dock перетаскиванием его разделителя. Чтобы применить изменение, Dock один раз перезапустится.",
        switcherLayoutWindows: "Миниатюры окон",
        switcherLayoutWindowsCaption: "По миниатюре на каждое окно, включая свёрнутые.",
        switcherLayoutIcons: "Крупные значки",
        switcherLayoutSimple: "Простой список"
    )

    static let es = SettingsPageStrings(
        energyDescription: "Mantén el Mac despierto, controla tus pantallas y ahorra batería.",
        monitorDescription: "Qué muestran la barra de menús y el panel sobre el Mac, y cuándo avisarte.",
        mouseDescription: "Dale nuevas funciones a la rueda, a los botones laterales y al trackpad.",
        switcherDescription: "Cambia de app y de ventana a tu manera.",
        dockTitle: "Dock",
        dockDescription: "Mira las ventanas de una app desde su icono en el Dock y elige qué hace un clic en él.",
        dockTweaks: "Ajustes del Dock",
        dockTweaksDescription: "Pequeños cambios en el comportamiento del Dock, como bloquear su tamaño.",
        dockSizeLock: "Bloquear el tamaño del Dock",
        dockSizeLockCaption: "Evita que el Dock cambie de tamaño al arrastrar su separador. El Dock se reinicia una vez para aplicar el cambio.",
        switcherLayoutWindows: "Vistas previas de ventanas",
        switcherLayoutWindowsCaption: "Una vista previa por ventana, incluidas las minimizadas.",
        switcherLayoutIcons: "Iconos grandes",
        switcherLayoutSimple: "Lista simple"
    )

    static let sk = SettingsPageStrings(
        energyDescription: "Udržujte Mac v bdelom stave, ovládajte svoje displeje a šetrite batériu.",
        monitorDescription: "Čo lišta a panel zobrazujú o vašom Macu a kedy vás upozorniť.",
        mouseDescription: "Priraďte koliesku, bočným tlačidlám a trackpadu nové úlohy.",
        switcherDescription: "Prepínajte medzi aplikáciami a oknami po svojom.",
        dockTitle: "Dock",
        dockDescription: "Zobrazte okná aplikácie z jej ikony v Docku a vyberte, čo urobí kliknutie na ňu.",
        dockTweaks: "Úpravy Docku",
        dockTweaksDescription: "Drobné zmeny správania Docku, napríklad zamknutie jeho veľkosti.",
        dockSizeLock: "Zamknúť veľkosť Docku",
        dockSizeLockCaption: "Zabráni zmene veľkosti Docku ťahaním jeho oddeľovača. Dock sa na použitie zmeny raz reštartuje.",
        switcherLayoutWindows: "Náhľady okien",
        switcherLayoutWindowsCaption: "Jeden náhľad na okno, vrátane minimalizovaných.",
        switcherLayoutIcons: "Veľké ikony",
        switcherLayoutSimple: "Jednoduchý zoznam"
    )

    static let de = SettingsPageStrings(
        energyDescription: "Halte den Mac wach, steuere deine Bildschirme und spare Batterie.",
        monitorDescription: "Was Menüleiste und Panel über den Mac zeigen und wann du gewarnt wirst.",
        mouseDescription: "Gib dem Scrollrad, den Seitentasten und dem Trackpad neue Aufgaben.",
        switcherDescription: "Wechsle auf deine Art zwischen Apps und Fenstern.",
        dockTitle: "Dock",
        dockDescription: "Sieh die Fenster einer App über ihr Dock-Symbol und lege fest, was ein Klick darauf bewirkt.",
        dockTweaks: "Dock-Anpassungen",
        dockTweaksDescription: "Kleine Änderungen am Verhalten des Docks, etwa das Sperren seiner Größe.",
        dockSizeLock: "Dock-Größe sperren",
        dockSizeLockCaption: "Verhindert, dass die Größe des Docks durch Ziehen der Trennlinie geändert wird. Das Dock startet einmal neu, um die Änderung zu übernehmen.",
        switcherLayoutWindows: "Fenstervorschauen",
        switcherLayoutWindowsCaption: "Eine Vorschau pro Fenster, auch für minimierte.",
        switcherLayoutIcons: "Große Symbole",
        switcherLayoutSimple: "Einfache Liste"
    )

    static let fr = SettingsPageStrings(
        energyDescription: "Gardez le Mac éveillé, réglez vos écrans et économisez la batterie.",
        monitorDescription: "Ce que la barre des menus et le panneau montrent du Mac, et quand vous prévenir.",
        mouseDescription: "Donnez de nouveaux rôles à la molette, aux boutons latéraux et au trackpad.",
        switcherDescription: "Passez d’une app ou d’une fenêtre à l’autre à votre façon.",
        dockTitle: "Dock",
        dockDescription: "Voyez les fenêtres d’une app depuis son icône dans le Dock et choisissez l’effet d’un clic dessus.",
        dockTweaks: "Réglages du Dock",
        dockTweaksDescription: "De petits changements dans le comportement du Dock, comme le verrouillage de sa taille.",
        dockSizeLock: "Verrouiller la taille du Dock",
        dockSizeLockCaption: "Empêche de redimensionner le Dock en faisant glisser son séparateur. Le Dock redémarre une fois pour appliquer le changement.",
        switcherLayoutWindows: "Aperçus des fenêtres",
        switcherLayoutWindowsCaption: "Un aperçu par fenêtre, fenêtres réduites comprises.",
        switcherLayoutIcons: "Grandes icônes",
        switcherLayoutSimple: "Liste simple"
    )

    static let it = SettingsPageStrings(
        energyDescription: "Tieni il Mac sveglio, controlla i tuoi schermi e risparmia batteria.",
        monitorDescription: "Cosa mostrano la barra dei menu e il pannello sul Mac, e quando avvisarti.",
        mouseDescription: "Assegna nuovi compiti alla rotellina, ai tasti laterali e al trackpad.",
        switcherDescription: "Passa da un’app o una finestra all’altra a modo tuo.",
        dockTitle: "Dock",
        dockDescription: "Guarda le finestre di un’app dalla sua icona nel Dock e scegli cosa fa un clic su di essa.",
        dockTweaks: "Ritocchi al Dock",
        dockTweaksDescription: "Piccole modifiche al comportamento del Dock, come bloccarne le dimensioni.",
        dockSizeLock: "Blocca le dimensioni del Dock",
        dockSizeLockCaption: "Impedisce di ridimensionare il Dock trascinandone il separatore. Il Dock si riavvia una volta per applicare la modifica.",
        switcherLayoutWindows: "Anteprime delle finestre",
        switcherLayoutWindowsCaption: "Un’anteprima per finestra, comprese quelle contratte.",
        switcherLayoutIcons: "Icone grandi",
        switcherLayoutSimple: "Elenco semplice"
    )

    static let ja = SettingsPageStrings(
        energyDescription: "Mac をスリープさせず、ディスプレイを調整し、バッテリーを節約します。",
        monitorDescription: "メニューバーとパネルに Mac の何を表示するか、いつ知らせるか。",
        mouseDescription: "ホイール、サイドボタン、トラックパッドに新しい役割を。",
        switcherDescription: "アプリやウインドウを自分のやり方で切り替え。",
        dockTitle: "Dock",
        dockDescription: "Dock のアイコンからアプリのウインドウを確認し、クリックしたときの動作を選べます。",
        dockTweaks: "Dock の調整",
        dockTweaksDescription: "Dock のサイズのロックなど、Dock の動作を少し変更します。",
        dockSizeLock: "Dock のサイズをロック",
        dockSizeLockCaption: "区切り線のドラッグで Dock のサイズが変わらないようにします。変更を適用するために Dock が一度再起動します。",
        switcherLayoutWindows: "ウインドウのプレビュー",
        switcherLayoutWindowsCaption: "ウインドウごとにプレビューを表示。しまったウインドウも含みます。",
        switcherLayoutIcons: "大きなアイコン",
        switcherLayoutSimple: "シンプルなリスト"
    )

    static let ko = SettingsPageStrings(
        energyDescription: "Mac을 깨어 있게 하고, 화면을 조절하고, 배터리를 아끼세요.",
        monitorDescription: "메뉴 막대와 패널에 Mac의 무엇을 표시할지, 언제 알릴지.",
        mouseDescription: "휠, 사이드 버튼, 트랙패드에 새 역할을 맡기세요.",
        switcherDescription: "나만의 방식으로 앱과 윈도우를 전환하세요.",
        dockTitle: "Dock",
        dockDescription: "Dock 아이콘에서 앱의 윈도우를 확인하고, 아이콘을 클릭했을 때의 동작을 고르세요.",
        dockTweaks: "Dock 조정",
        dockTweaksDescription: "Dock 크기 잠그기처럼 Dock의 동작을 조금 바꿉니다.",
        dockSizeLock: "Dock 크기 잠그기",
        dockSizeLockCaption: "구분선을 드래그해 Dock 크기를 바꾸지 못하게 합니다. 변경 사항을 적용하려고 Dock이 한 번 다시 시작됩니다.",
        switcherLayoutWindows: "윈도우 미리보기",
        switcherLayoutWindowsCaption: "윈도우마다 미리보기 하나, 축소된 윈도우도 포함합니다.",
        switcherLayoutIcons: "큰 아이콘",
        switcherLayoutSimple: "간단한 목록"
    )

    static let zhHans = SettingsPageStrings(
        energyDescription: "让 Mac 保持唤醒、调节显示器并节省电量。",
        monitorDescription: "菜单栏和面板显示 Mac 的哪些信息，以及何时提醒你。",
        mouseDescription: "让滚轮、侧键和触控板承担新的任务。",
        switcherDescription: "按你的方式切换 App 和窗口。",
        dockTitle: "程序坞",
        dockDescription: "从程序坞图标查看 App 的窗口，并选择点按图标时的操作。",
        dockTweaks: "程序坞调整",
        dockTweaksDescription: "对程序坞的行为做些小改动，例如锁定其大小。",
        dockSizeLock: "锁定程序坞大小",
        dockSizeLockCaption: "防止通过拖移分隔线调整程序坞大小。为应用更改，程序坞会重新启动一次。",
        switcherLayoutWindows: "窗口预览",
        switcherLayoutWindowsCaption: "每个窗口一张预览，包括已最小化的窗口。",
        switcherLayoutIcons: "大图标",
        switcherLayoutSimple: "简单列表"
    )

    static let zhTW = SettingsPageStrings(
        energyDescription: "讓 Mac 保持喚醒、調整顯示器並節省電量。",
        monitorDescription: "選單列和面板顯示 Mac 的哪些資訊，以及何時提醒你。",
        mouseDescription: "讓滾輪、側鍵和觸控板承擔新的任務。",
        switcherDescription: "用你的方式切換 App 和視窗。",
        dockTitle: "Dock",
        dockDescription: "從 Dock 圖示查看 App 的視窗，並選擇點按圖示時的動作。",
        dockTweaks: "Dock 調整",
        dockTweaksDescription: "對 Dock 的行為做些小改動，例如鎖定其大小。",
        dockSizeLock: "鎖定 Dock 大小",
        dockSizeLockCaption: "避免拖移分隔線來調整 Dock 大小。為套用變更，Dock 會重新啟動一次。",
        switcherLayoutWindows: "視窗預覽",
        switcherLayoutWindowsCaption: "每個視窗一張預覽，包括已縮到最小的視窗。",
        switcherLayoutIcons: "大圖示",
        switcherLayoutSimple: "簡單列表"
    )

    static let zhHK = SettingsPageStrings(
        energyDescription: "讓 Mac 保持喚醒、調整顯示器並節省電量。",
        monitorDescription: "選單列和面板顯示 Mac 的哪些資訊，以及何時提醒你。",
        mouseDescription: "讓滾輪、側鍵和觸控板承擔新的任務。",
        switcherDescription: "用你的方式切換 App 和視窗。",
        dockTitle: "Dock",
        dockDescription: "從 Dock 圖示查看 App 的視窗，並選擇點按圖示時的動作。",
        dockTweaks: "Dock 調整",
        dockTweaksDescription: "對 Dock 的行為做些小改動，例如鎖定其大小。",
        dockSizeLock: "鎖定 Dock 大小",
        dockSizeLockCaption: "避免拖移分隔線來調整 Dock 大小。為套用變更，Dock 會重新啟動一次。",
        switcherLayoutWindows: "視窗預覽",
        switcherLayoutWindowsCaption: "每個視窗一張預覽，包括已縮到最小的視窗。",
        switcherLayoutIcons: "大圖示",
        switcherLayoutSimple: "簡單列表"
    )
}
