// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// The one-line description under a redesigned Settings page's title, for
/// pages whose own string catalog has no room for it.
struct SettingsPageStrings {
    let energyDescription: String
    let monitorDescription: String
    let mouseDescription: String
    let advancedDescription: String
    let releaseNotesDescription: String
    let aboutDescription: String
    let supportDescription: String
    let keyRemappingDescription: String
    let switcherDescription: String
    let dockTitle: String
    let dockDescription: String
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
        monitorDescription: "Виберіть системні показники для смуги меню й панелі та налаштуйте сповіщення.",
        mouseDescription: "Налаштуйте прокручування, кнопки миші, жести трекпада й клавіатурні інструменти.",
        advancedDescription: "Експортуйте й відновлюйте налаштування, скидайте дозволи Vorssaint або повністю видаляйте програму.",
        releaseNotesDescription: "Перегляньте нові функції, зміни та виправлення в цій версії Vorssaint.",
        aboutDescription: "Інструменти Mac для керування вікнами, введенням, екранами, файлами, звуком і системою зі смуги меню.",
        supportDescription: "Знайдіть посилання на проєкт і підтримайте розробку зіркою на GitHub або донатом.",
        keyRemappingDescription: "Перепризначайте клавіші, вимикайте їх або створюйте послідовності, зокрема окремо для кожної програми.",
        switcherDescription: "Перемикайте програми й вікна на свій лад.",
        dockTitle: "Dock",
        dockDescription: "Переглядайте вікна програми з її значка в Dock і вибирайте, що робить клацання по ньому.",
        switcherLayoutWindows: "Мініатюри вікон",
        switcherLayoutWindowsCaption: "По одній мініатюрі для кожного вікна, включно зі згорнутими.",
        switcherLayoutIcons: "Великі значки",
        switcherLayoutSimple: "Простий список"
    )

    static let enUS = SettingsPageStrings(
        energyDescription: "Keep the Mac awake, control your displays and save battery.",
        monitorDescription: "Choose which CPU, memory, network, disk, power and device stats appear in the menu bar and panel, and set alerts.",
        mouseDescription: "Set up scrolling, mouse buttons, trackpad gestures and keyboard input tools.",
        advancedDescription: "Export or restore settings, reset Vorssaint’s permissions, or completely uninstall the app.",
        releaseNotesDescription: "Browse the new features, changes and fixes in this version of Vorssaint.",
        aboutDescription: "Mac utilities for managing windows, input, displays, files, audio and system tools from the menu bar.",
        supportDescription: "Find project links and support development with a GitHub star or donation.",
        keyRemappingDescription: "Remap, disable or chain keys, with optional per-app rules.",
        switcherDescription: "Switch between apps and windows your way.",
        dockTitle: "Dock",
        dockDescription: "See an app’s windows from its Dock icon, and choose what a click on it does.",
        switcherLayoutWindows: "Window previews",
        switcherLayoutWindowsCaption: "One preview per window, minimized ones included.",
        switcherLayoutIcons: "Large icons",
        switcherLayoutSimple: "Simple list"
    )

    static let ptBR = SettingsPageStrings(
        energyDescription: "Mantenha o Mac acordado, controle suas telas e economize bateria.",
        monitorDescription: "Escolha quais dados do sistema aparecem na barra de menus e no painel e configure alertas.",
        mouseDescription: "Configure a rolagem, os botões do mouse, os gestos do trackpad e as ferramentas de teclado.",
        advancedDescription: "Exporte ou restaure ajustes, redefina as permissões do Vorssaint ou desinstale o app por completo.",
        releaseNotesDescription: "Veja os novos recursos, as mudanças e as correções desta versão do Vorssaint.",
        aboutDescription: "Utilitários para Mac para gerenciar janelas, entrada, telas, arquivos, áudio e ferramentas do sistema pela barra de menus.",
        supportDescription: "Acesse os links do projeto e apoie o desenvolvimento com uma estrela no GitHub ou uma doação.",
        keyRemappingDescription: "Remapeie, desative ou encadeie teclas, com regras opcionais por app.",
        switcherDescription: "Troque de app e de janela do seu jeito.",
        dockTitle: "Dock",
        dockDescription: "Veja as janelas de um app pelo ícone no Dock e escolha o que um clique nele faz.",
        switcherLayoutWindows: "Previews das janelas",
        switcherLayoutWindowsCaption: "Um preview por janela, incluindo as minimizadas.",
        switcherLayoutIcons: "Ícones grandes",
        switcherLayoutSimple: "Lista simples"
    )

    static let tr = SettingsPageStrings(
        energyDescription: "Mac’i uyanık tutun, ekranlarınızı yönetin ve pil tasarrufu yapın.",
        monitorDescription: "Menü çubuğunda ve panelde hangi sistem ölçümlerinin gösterileceğini seçin ve uyarıları ayarlayın.",
        mouseDescription: "Kaydırmayı, fare düğmelerini, izleme dörtgeni hareketlerini ve klavye araçlarını yapılandırın.",
        advancedDescription: "Ayarları dışa aktarın veya geri yükleyin, Vorssaint izinlerini sıfırlayın ya da uygulamayı tamamen kaldırın.",
        releaseNotesDescription: "Vorssaint’in bu sürümündeki yeni özellikleri, değişiklikleri ve düzeltmeleri görün.",
        aboutDescription: "Menü çubuğundan pencereleri, giriş aygıtlarını, ekranları, dosyaları, sesi ve sistem araçlarını yönetmek için Mac araçları.",
        supportDescription: "Proje bağlantılarını bulun ve GitHub’da yıldız vererek veya bağış yaparak geliştirmeyi destekleyin.",
        keyRemappingDescription: "İsteğe bağlı uygulama kurallarıyla tuşları yeniden eşleyin, devre dışı bırakın veya zincirleyin.",
        switcherDescription: "Uygulamalar ve pencereler arasında kendi tarzınızda geçin.",
        dockTitle: "Dock",
        dockDescription: "Bir uygulamanın pencerelerini Dock simgesinden görün ve simgeye tıklamanın ne yapacağını seçin.",
        switcherLayoutWindows: "Pencere önizlemeleri",
        switcherLayoutWindowsCaption: "Her pencere için bir önizleme, simge durumundakiler dahil.",
        switcherLayoutIcons: "Büyük simgeler",
        switcherLayoutSimple: "Basit liste"
    )

    static let ru = SettingsPageStrings(
        energyDescription: "Не давайте Mac уснуть, управляйте экранами и берегите батарею.",
        monitorDescription: "Выберите показатели системы для строки меню и панели и настройте предупреждения.",
        mouseDescription: "Настройте прокрутку, кнопки мыши, жесты трекпада и инструменты клавиатуры.",
        advancedDescription: "Экспортируйте и восстанавливайте настройки, сбрасывайте разрешения Vorssaint или полностью удаляйте приложение.",
        releaseNotesDescription: "Просматривайте новые функции, изменения и исправления в этой версии Vorssaint.",
        aboutDescription: "Утилиты для Mac: управление окнами, вводом, дисплеями, файлами, звуком и системными инструментами из строки меню.",
        supportDescription: "Перейдите по ссылкам проекта и поддержите разработку звездой на GitHub или пожертвованием.",
        keyRemappingDescription: "Переназначайте клавиши, отключайте их или создавайте последовательности, в том числе отдельно для приложений.",
        switcherDescription: "Переключайтесь между приложениями и окнами по-своему.",
        dockTitle: "Dock",
        dockDescription: "Смотрите окна приложения по его значку в Dock и выбирайте, что делает щелчок по нему.",
        switcherLayoutWindows: "Миниатюры окон",
        switcherLayoutWindowsCaption: "По миниатюре на каждое окно, включая свёрнутые.",
        switcherLayoutIcons: "Крупные значки",
        switcherLayoutSimple: "Простой список"
    )

    static let es = SettingsPageStrings(
        energyDescription: "Mantén el Mac despierto, controla tus pantallas y ahorra batería.",
        monitorDescription: "Elige qué datos del sistema aparecen en la barra de menús y el panel, y configura alertas.",
        mouseDescription: "Configura el desplazamiento, los botones del ratón, los gestos del trackpad y las herramientas de teclado.",
        advancedDescription: "Exporta o restaura ajustes, restablece los permisos de Vorssaint o desinstala la app por completo.",
        releaseNotesDescription: "Consulta las novedades, los cambios y las correcciones de esta versión de Vorssaint.",
        aboutDescription: "Utilidades para Mac para gestionar ventanas, entrada, pantallas, archivos, audio y herramientas del sistema desde la barra de menús.",
        supportDescription: "Consulta los enlaces del proyecto y apoya su desarrollo con una estrella en GitHub o una donación.",
        keyRemappingDescription: "Reasigna, desactiva o encadena teclas, con reglas opcionales para cada app.",
        switcherDescription: "Cambia de app y de ventana a tu manera.",
        dockTitle: "Dock",
        dockDescription: "Mira las ventanas de una app desde su icono en el Dock y elige qué hace un clic en él.",
        switcherLayoutWindows: "Vistas previas de ventanas",
        switcherLayoutWindowsCaption: "Una vista previa por ventana, incluidas las minimizadas.",
        switcherLayoutIcons: "Iconos grandes",
        switcherLayoutSimple: "Lista simple"
    )

    static let sk = SettingsPageStrings(
        energyDescription: "Udržujte Mac v bdelom stave, ovládajte svoje displeje a šetrite batériu.",
        monitorDescription: "Vyberte systémové údaje zobrazované v lište a paneli a nastavte upozornenia.",
        mouseDescription: "Nastavte posúvanie, tlačidlá myši, gestá trackpadu a nástroje klávesnice.",
        advancedDescription: "Exportujte alebo obnovte nastavenia, resetujte povolenia Vorssaintu alebo aplikáciu úplne odinštalujte.",
        releaseNotesDescription: "Prečítajte si o nových funkciách, zmenách a opravách v tejto verzii Vorssaintu.",
        aboutDescription: "Nástroje pre Mac na správu okien, vstupu, displejov, súborov, zvuku a systému z lišty.",
        supportDescription: "Nájdite odkazy na projekt a podporte vývoj hviezdičkou na GitHube alebo darom.",
        keyRemappingDescription: "Premapujte, vypnite alebo reťazte klávesy, prípadne nastavte pravidlá pre jednotlivé aplikácie.",
        switcherDescription: "Prepínajte medzi aplikáciami a oknami po svojom.",
        dockTitle: "Dock",
        dockDescription: "Zobrazte okná aplikácie z jej ikony v Docku a vyberte, čo urobí kliknutie na ňu.",
        switcherLayoutWindows: "Náhľady okien",
        switcherLayoutWindowsCaption: "Jeden náhľad na okno, vrátane minimalizovaných.",
        switcherLayoutIcons: "Veľké ikony",
        switcherLayoutSimple: "Jednoduchý zoznam"
    )

    static let de = SettingsPageStrings(
        energyDescription: "Halte den Mac wach, steuere deine Bildschirme und spare Batterie.",
        monitorDescription: "Lege fest, welche Systemwerte in Menüleiste und Panel erscheinen, und richte Warnungen ein.",
        mouseDescription: "Richte Scrollen, Maustasten, Trackpad-Gesten und Tastaturwerkzeuge ein.",
        advancedDescription: "Exportiere oder stelle Einstellungen wieder her, setze Vorssaints Berechtigungen zurück oder deinstalliere die App vollständig.",
        releaseNotesDescription: "Entdecke die neuen Funktionen, Änderungen und Fehlerbehebungen dieser Vorssaint-Version.",
        aboutDescription: "Mac-Werkzeuge zur Verwaltung von Fenstern, Eingabe, Bildschirmen, Dateien, Audio und Systemfunktionen über die Menüleiste.",
        supportDescription: "Finde Projektlinks und unterstütze die Entwicklung mit einem GitHub-Stern oder einer Spende.",
        keyRemappingDescription: "Belege Tasten neu, deaktiviere sie oder verknüpfe Tastenfolgen, auf Wunsch pro App.",
        switcherDescription: "Wechsle auf deine Art zwischen Apps und Fenstern.",
        dockTitle: "Dock",
        dockDescription: "Sieh die Fenster einer App über ihr Dock-Symbol und lege fest, was ein Klick darauf bewirkt.",
        switcherLayoutWindows: "Fenstervorschauen",
        switcherLayoutWindowsCaption: "Eine Vorschau pro Fenster, auch für minimierte.",
        switcherLayoutIcons: "Große Symbole",
        switcherLayoutSimple: "Einfache Liste"
    )

    static let fr = SettingsPageStrings(
        energyDescription: "Gardez le Mac éveillé, réglez vos écrans et économisez la batterie.",
        monitorDescription: "Choisissez les données système affichées dans la barre des menus et le panneau, et configurez les alertes.",
        mouseDescription: "Configurez le défilement, les boutons de la souris, les gestes du trackpad et les outils clavier.",
        advancedDescription: "Exportez ou restaurez les réglages, réinitialisez les autorisations de Vorssaint ou désinstallez complètement l’app.",
        releaseNotesDescription: "Découvrez les nouveautés, les changements et les corrections de cette version de Vorssaint.",
        aboutDescription: "Des outils Mac pour gérer les fenêtres, les périphériques d’entrée, les écrans, les fichiers, l’audio et le système depuis la barre des menus.",
        supportDescription: "Accédez aux liens du projet et soutenez le développement avec une étoile GitHub ou un don.",
        keyRemappingDescription: "Réattribuez ou désactivez des touches, ou créez des séquences, avec des règles par app en option.",
        switcherDescription: "Passez d’une app ou d’une fenêtre à l’autre à votre façon.",
        dockTitle: "Dock",
        dockDescription: "Voyez les fenêtres d’une app depuis son icône dans le Dock et choisissez l’effet d’un clic dessus.",
        switcherLayoutWindows: "Aperçus des fenêtres",
        switcherLayoutWindowsCaption: "Un aperçu par fenêtre, fenêtres réduites comprises.",
        switcherLayoutIcons: "Grandes icônes",
        switcherLayoutSimple: "Liste simple"
    )

    static let it = SettingsPageStrings(
        energyDescription: "Tieni il Mac sveglio, controlla i tuoi schermi e risparmia batteria.",
        monitorDescription: "Scegli quali dati di sistema mostrare nella barra dei menu e nel pannello e configura gli avvisi.",
        mouseDescription: "Configura scorrimento, pulsanti del mouse, gesti del trackpad e strumenti per la tastiera.",
        advancedDescription: "Esporta o ripristina le impostazioni, reimposta i permessi di Vorssaint o disinstalla completamente l’app.",
        releaseNotesDescription: "Scopri le novità, le modifiche e le correzioni di questa versione di Vorssaint.",
        aboutDescription: "Utility Mac per gestire finestre, input, schermi, file, audio e strumenti di sistema dalla barra dei menu.",
        supportDescription: "Trova i link del progetto e sostieni lo sviluppo con una stella su GitHub o una donazione.",
        keyRemappingDescription: "Rimappa, disattiva o concatena i tasti, con regole facoltative per ogni app.",
        switcherDescription: "Passa da un’app o una finestra all’altra a modo tuo.",
        dockTitle: "Dock",
        dockDescription: "Guarda le finestre di un’app dalla sua icona nel Dock e scegli cosa fa un clic su di essa.",
        switcherLayoutWindows: "Anteprime delle finestre",
        switcherLayoutWindowsCaption: "Un’anteprima per finestra, comprese quelle contratte.",
        switcherLayoutIcons: "Icone grandi",
        switcherLayoutSimple: "Elenco semplice"
    )

    static let ja = SettingsPageStrings(
        energyDescription: "Mac をスリープさせず、ディスプレイを調整し、バッテリーを節約します。",
        monitorDescription: "メニューバーとパネルに表示するシステム情報を選び、通知を設定できます。",
        mouseDescription: "スクロール、マウスボタン、トラックパッドのジェスチャ、キーボードツールを設定できます。",
        advancedDescription: "設定の書き出しと復元、Vorssaint の権限のリセット、アプリの完全なアンインストールができます。",
        releaseNotesDescription: "このバージョンの新機能、変更点、修正内容を確認できます。",
        aboutDescription: "メニューバーからウインドウ、入力、ディスプレイ、ファイル、オーディオ、システムツールを管理する Mac ユーティリティです。",
        supportDescription: "プロジェクトのリンクを確認し、GitHub のスターや寄付で開発を支援できます。",
        keyRemappingDescription: "キーの割り当て変更、無効化、連続入力を設定できます。アプリごとのルールにも対応します。",
        switcherDescription: "アプリやウインドウを自分のやり方で切り替え。",
        dockTitle: "Dock",
        dockDescription: "Dock のアイコンからアプリのウインドウを確認し、クリックしたときの動作を選べます。",
        switcherLayoutWindows: "ウインドウのプレビュー",
        switcherLayoutWindowsCaption: "ウインドウごとにプレビューを表示。しまったウインドウも含みます。",
        switcherLayoutIcons: "大きなアイコン",
        switcherLayoutSimple: "シンプルなリスト"
    )

    static let ko = SettingsPageStrings(
        energyDescription: "Mac을 깨어 있게 하고, 화면을 조절하고, 배터리를 아끼세요.",
        monitorDescription: "메뉴 막대와 패널에 표시할 시스템 정보를 고르고 알림을 설정하세요.",
        mouseDescription: "스크롤, 마우스 버튼, 트랙패드 제스처와 키보드 도구를 설정하세요.",
        advancedDescription: "설정을 내보내거나 복원하고, Vorssaint 권한을 재설정하거나 앱을 완전히 제거할 수 있습니다.",
        releaseNotesDescription: "이번 Vorssaint 버전의 새 기능, 변경 사항, 수정 사항을 확인하세요.",
        aboutDescription: "메뉴 막대에서 윈도우, 입력, 디스플레이, 파일, 오디오와 시스템 도구를 관리하는 Mac 유틸리티입니다.",
        supportDescription: "프로젝트 링크를 확인하고 GitHub 스타나 기부로 개발을 후원할 수 있습니다.",
        keyRemappingDescription: "키를 다시 지정하거나 끄고 연속 입력을 설정하세요. 앱별 규칙도 선택할 수 있습니다.",
        switcherDescription: "나만의 방식으로 앱과 윈도우를 전환하세요.",
        dockTitle: "Dock",
        dockDescription: "Dock 아이콘에서 앱의 윈도우를 확인하고, 아이콘을 클릭했을 때의 동작을 고르세요.",
        switcherLayoutWindows: "윈도우 미리보기",
        switcherLayoutWindowsCaption: "윈도우마다 미리보기 하나, 축소된 윈도우도 포함합니다.",
        switcherLayoutIcons: "큰 아이콘",
        switcherLayoutSimple: "간단한 목록"
    )

    static let zhHans = SettingsPageStrings(
        energyDescription: "让 Mac 保持唤醒、调节显示器并节省电量。",
        monitorDescription: "选择在菜单栏和面板中显示哪些系统数据，并设置提醒。",
        mouseDescription: "配置滚动、鼠标按键、触控板手势和键盘工具。",
        advancedDescription: "导出或恢复设置、重置 Vorssaint 权限，或彻底卸载 App。",
        releaseNotesDescription: "查看此版本 Vorssaint 的新功能、变更和修复。",
        aboutDescription: "通过菜单栏管理窗口、输入设备、显示器、文件、音频和系统工具的 Mac 实用工具集。",
        supportDescription: "查看项目链接，并通过在 GitHub 上点星或捐款来支持项目开发。",
        keyRemappingDescription: "重新映射、禁用或串联按键，也可为不同 App 设置规则。",
        switcherDescription: "按你的方式切换 App 和窗口。",
        dockTitle: "程序坞",
        dockDescription: "从程序坞图标查看 App 的窗口，并选择点按图标时的操作。",
        switcherLayoutWindows: "窗口预览",
        switcherLayoutWindowsCaption: "每个窗口一张预览，包括已最小化的窗口。",
        switcherLayoutIcons: "大图标",
        switcherLayoutSimple: "简单列表"
    )

    static let zhTW = SettingsPageStrings(
        energyDescription: "讓 Mac 保持喚醒、調整顯示器並節省電量。",
        monitorDescription: "選擇在選單列和面板顯示哪些系統資料，並設定提醒。",
        mouseDescription: "設定捲動、滑鼠按鍵、觸控板手勢與鍵盤工具。",
        advancedDescription: "匯出或還原設定、重設 Vorssaint 權限，或徹底解除安裝 App。",
        releaseNotesDescription: "查看此版本 Vorssaint 的新功能、變更與修正。",
        aboutDescription: "透過選單列管理視窗、輸入裝置、顯示器、檔案、音訊與系統工具的 Mac 實用工具集。",
        supportDescription: "查看專案連結，並透過在 GitHub 上加星或捐款支持專案開發。",
        keyRemappingDescription: "重新對應、停用或串接按鍵，也可為不同 App 設定規則。",
        switcherDescription: "用你的方式切換 App 和視窗。",
        dockTitle: "Dock",
        dockDescription: "從 Dock 圖示查看 App 的視窗，並選擇點按圖示時的動作。",
        switcherLayoutWindows: "視窗預覽",
        switcherLayoutWindowsCaption: "每個視窗一張預覽，包括已縮到最小的視窗。",
        switcherLayoutIcons: "大圖示",
        switcherLayoutSimple: "簡單列表"
    )

    static let zhHK = SettingsPageStrings(
        energyDescription: "讓 Mac 保持喚醒、調整顯示器並節省電量。",
        monitorDescription: "選擇喺選單列同面板顯示邊啲系統資料，並設定提醒。",
        mouseDescription: "設定捲動、滑鼠按鍵、觸控板手勢同鍵盤工具。",
        advancedDescription: "匯出或還原設定、重設 Vorssaint 權限，或徹底解除安裝 App。",
        releaseNotesDescription: "查看此版本 Vorssaint 的新功能、變更與修正。",
        aboutDescription: "透過選單列管理視窗、輸入裝置、顯示器、檔案、音訊同系統工具嘅 Mac 實用工具集。",
        supportDescription: "查看專案連結，並透過在 GitHub 上加星或捐款支持專案開發。",
        keyRemappingDescription: "重新對應、停用或串接按鍵，亦可為唔同 App 設定規則。",
        switcherDescription: "用你的方式切換 App 和視窗。",
        dockTitle: "Dock",
        dockDescription: "從 Dock 圖示查看 App 的視窗，並選擇點按圖示時的動作。",
        switcherLayoutWindows: "視窗預覽",
        switcherLayoutWindowsCaption: "每個視窗一張預覽，包括已縮到最小的視窗。",
        switcherLayoutIcons: "大圖示",
        switcherLayoutSimple: "簡單列表"
    )
}
