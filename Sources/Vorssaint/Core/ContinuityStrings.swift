// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

struct ContinuityStrings {
    let start: String
    let title: String
    let settingsTitle: String
    let hotspot: String
    let discover: String
    let chooseHotspot: String
    let apps: String
    let appsCaption: String
    let addApp: String
    let removeApp: String
    let connecting: String
    let quitting: String
    let countdown: String
    let cancel: String
    let restore: String
    let active: String
    let permission: String
    let unavailable: String
    let connectionFailed: String
    let quitFailed: String
    let brightnessFailed: String
    let setup: String
    let help: String
}

extension FeatureStrings {
    static func continuity(_ language: AppLanguage) -> ContinuityStrings {
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
        case .zhHans: return .zhHans
        case .zhTW: return .zhTW
        case .zhHK: return .zhHK
        case .uk: return .uk
        }
    }
}

extension ContinuityStrings {
    static let enUS = ContinuityStrings(
        start: "Start handoff",
        title: "Handoff to iPhone",
        settingsTitle: "Handoff options",
        hotspot: "iPhone hotspot",
        discover: "Find iPhone",
        chooseHotspot: "Choose an iPhone",
        apps: "Apps to quit",
        appsCaption: "These apps quit normally after connecting. Unsaved work can stop handoff.",
        addApp: "Add app",
        removeApp: "Remove app",
        connecting: "Connecting to iPhone…",
        quitting: "Quitting selected apps…",
        countdown: "Display dims in %d seconds",
        cancel: "Cancel",
        restore: "Restore brightness",
        active: "Handoff active",
        permission: "Allow Accessibility access in System Settings to connect to your iPhone.",
        unavailable: "No iPhone hotspot found. Keep your iPhone nearby with Wi-Fi and Bluetooth on.",
        connectionFailed: "Could not connect to the selected iPhone. Your display has not been dimmed.",
        quitFailed: "Some apps did not quit. Save your work and try again.",
        brightnessFailed: "Could not change the built-in display brightness.",
        setup: "Choose your iPhone in Handoff options first.",
        help: "Uses System Settings to connect to your iPhone. Existing network connections may reconnect. Cancelling does not reopen apps or switch Wi-Fi back."
    )

    static let ptBR = ContinuityStrings(
        start: "Iniciar continuidade",
        title: "Continuar no iPhone",
        settingsTitle: "Opções de continuidade",
        hotspot: "Acesso Pessoal do iPhone",
        discover: "Encontrar iPhone",
        chooseHotspot: "Escolher um iPhone",
        apps: "Apps a encerrar",
        appsCaption: "Estes apps são encerrados normalmente após a conexão. Trabalho não salvo pode interromper a continuidade.",
        addApp: "Adicionar app",
        removeApp: "Remover app",
        connecting: "Conectando ao iPhone…",
        quitting: "Encerrando os apps selecionados…",
        countdown: "A tela escurecerá em %d segundos",
        cancel: "Cancelar",
        restore: "Restaurar brilho",
        active: "Continuidade ativa",
        permission: "Permita o acesso de Acessibilidade nos Ajustes do Sistema para conectar ao iPhone.",
        unavailable: "Nenhum Acesso Pessoal de iPhone encontrado. Mantenha o iPhone por perto com Wi-Fi e Bluetooth ativados.",
        connectionFailed: "Não foi possível conectar ao iPhone selecionado. A tela não foi escurecida.",
        quitFailed: "Alguns apps não foram encerrados. Salve seu trabalho e tente novamente.",
        brightnessFailed: "Não foi possível alterar o brilho da tela integrada.",
        setup: "Primeiro, escolha seu iPhone nas opções de continuidade.",
        help: "Usa os Ajustes do Sistema para conectar ao iPhone. As conexões de rede existentes podem se reconectar. Cancelar não reabre os apps nem restaura a conexão Wi-Fi anterior."
    )

    static let tr = ContinuityStrings(
        start: "Devamlılığı başlat",
        title: "iPhone’a geç",
        settingsTitle: "Geçiş seçenekleri",
        hotspot: "iPhone kişisel erişim noktası",
        discover: "iPhone bul",
        chooseHotspot: "Bir iPhone seç",
        apps: "Kapatılacak uygulamalar",
        appsCaption: "Bağlandıktan sonra bu uygulamalar normal şekilde kapatılır. Kaydedilmemiş çalışmalar geçişi durdurabilir.",
        addApp: "Uygulama ekle",
        removeApp: "Uygulamayı kaldır",
        connecting: "iPhone’a bağlanılıyor…",
        quitting: "Seçilen uygulamalar kapatılıyor…",
        countdown: "Ekran %d saniye içinde kararacak",
        cancel: "İptal",
        restore: "Parlaklığı geri yükle",
        active: "Geçiş etkin",
        permission: "iPhone’unuza bağlanmak için Sistem Ayarları’nda Erişilebilirlik erişimine izin verin.",
        unavailable: "iPhone kişisel erişim noktası bulunamadı. iPhone’unuzu Wi-Fi ve Bluetooth açık olarak yakınınızda tutun.",
        connectionFailed: "Seçilen iPhone’a bağlanılamadı. Ekranınız karartılmadı.",
        quitFailed: "Bazı uygulamalar kapatılmadı. Çalışmanızı kaydedip yeniden deneyin.",
        brightnessFailed: "Yerleşik ekranın parlaklığı değiştirilemedi.",
        setup: "Önce geçiş seçeneklerinden iPhone’unuzu seçin.",
        help: "iPhone’unuza bağlanmak için Sistem Ayarları’nı kullanır. Mevcut ağ bağlantıları yeniden bağlanabilir. İptal etmek uygulamaları yeniden açmaz veya önceki Wi-Fi bağlantısına dönmez."
    )

    static let ru = ContinuityStrings(
        start: "Начать передачу",
        title: "Перейти на iPhone",
        settingsTitle: "Параметры перехода",
        hotspot: "Точка доступа iPhone",
        discover: "Найти iPhone",
        chooseHotspot: "Выбрать iPhone",
        apps: "Приложения для завершения",
        appsCaption: "После подключения эти приложения завершатся обычным способом. Несохранённая работа может остановить переход.",
        addApp: "Добавить приложение",
        removeApp: "Убрать приложение",
        connecting: "Подключение к iPhone…",
        quitting: "Завершение выбранных приложений…",
        countdown: "Экран потускнеет через %d сек.",
        cancel: "Отмена",
        restore: "Восстановить яркость",
        active: "Переход активен",
        permission: "Разрешите доступ в разделе «Универсальный доступ» Системных настроек для подключения к iPhone.",
        unavailable: "Точка доступа iPhone не найдена. Держите iPhone рядом с включёнными Wi-Fi и Bluetooth.",
        connectionFailed: "Не удалось подключиться к выбранному iPhone. Яркость экрана не была снижена.",
        quitFailed: "Некоторые приложения не завершились. Сохраните работу и повторите попытку.",
        brightnessFailed: "Не удалось изменить яркость встроенного дисплея.",
        setup: "Сначала выберите iPhone в параметрах перехода.",
        help: "Для подключения к iPhone используются Системные настройки. Текущие сетевые соединения могут подключиться повторно. Отмена не открывает приложения заново и не возвращает прежнее подключение Wi-Fi."
    )

    static let es = ContinuityStrings(
        start: "Iniciar transferencia",
        title: "Continuar en el iPhone",
        settingsTitle: "Opciones de continuidad",
        hotspot: "Punto de acceso del iPhone",
        discover: "Buscar iPhone",
        chooseHotspot: "Elegir un iPhone",
        apps: "Apps que se cerrarán",
        appsCaption: "Estas apps se cierran normalmente tras la conexión. El trabajo sin guardar puede detener la continuidad.",
        addApp: "Añadir app",
        removeApp: "Quitar app",
        connecting: "Conectando al iPhone…",
        quitting: "Cerrando las apps seleccionadas…",
        countdown: "La pantalla se atenuará en %d segundos",
        cancel: "Cancelar",
        restore: "Restaurar brillo",
        active: "Continuidad activa",
        permission: "Permite el acceso de Accesibilidad en Ajustes del Sistema para conectarte al iPhone.",
        unavailable: "No se encontró ningún punto de acceso de iPhone. Mantén el iPhone cerca con Wi-Fi y Bluetooth activados.",
        connectionFailed: "No se pudo conectar al iPhone seleccionado. La pantalla no se ha atenuado.",
        quitFailed: "Algunas apps no se cerraron. Guarda tu trabajo e inténtalo de nuevo.",
        brightnessFailed: "No se pudo cambiar el brillo de la pantalla integrada.",
        setup: "Primero elige tu iPhone en las opciones de continuidad.",
        help: "Usa Ajustes del Sistema para conectarse al iPhone. Las conexiones de red existentes pueden volver a conectarse. Cancelar no vuelve a abrir las apps ni restaura la conexión Wi-Fi anterior."
    )

    static let sk = ContinuityStrings(
        start: "Spustiť odovzdanie",
        title: "Prejsť na iPhone",
        settingsTitle: "Možnosti prechodu",
        hotspot: "Osobný hotspot iPhonu",
        discover: "Nájsť iPhone",
        chooseHotspot: "Vybrať iPhone",
        apps: "Aplikácie na ukončenie",
        appsCaption: "Tieto aplikácie sa po pripojení bežne ukončia. Neuložená práca môže prechod zastaviť.",
        addApp: "Pridať aplikáciu",
        removeApp: "Odobrať aplikáciu",
        connecting: "Pripájanie k iPhonu…",
        quitting: "Ukončovanie vybraných aplikácií…",
        countdown: "Displej sa stlmí o %d sekúnd",
        cancel: "Zrušiť",
        restore: "Obnoviť jas",
        active: "Prechod je aktívny",
        permission: "Na pripojenie k iPhonu povoľte prístup k Prístupnosti v Systémových nastaveniach.",
        unavailable: "Osobný hotspot iPhonu sa nenašiel. Majte iPhone nablízku so zapnutými Wi-Fi a Bluetooth.",
        connectionFailed: "K vybranému iPhonu sa nepodarilo pripojiť. Displej sa nestlmil.",
        quitFailed: "Niektoré aplikácie sa neukončili. Uložte prácu a skúste to znova.",
        brightnessFailed: "Jas vstavaného displeja sa nepodarilo zmeniť.",
        setup: "Najprv vyberte iPhone v možnostiach prechodu.",
        help: "Na pripojenie k iPhonu používa Systémové nastavenia. Existujúce sieťové pripojenia sa môžu znova pripojiť. Zrušenie znova neotvorí aplikácie ani neobnoví predchádzajúce pripojenie Wi-Fi."
    )

    static let de = ContinuityStrings(
        start: "Übergabe starten",
        title: "Zum iPhone wechseln",
        settingsTitle: "Übergabeoptionen",
        hotspot: "iPhone-Hotspot",
        discover: "iPhone suchen",
        chooseHotspot: "iPhone auswählen",
        apps: "Zu beendende Apps",
        appsCaption: "Diese Apps werden nach dem Verbinden regulär beendet. Ungesicherte Arbeit kann die Übergabe anhalten.",
        addApp: "App hinzufügen",
        removeApp: "App entfernen",
        connecting: "Verbindung zum iPhone wird hergestellt…",
        quitting: "Ausgewählte Apps werden beendet…",
        countdown: "Display wird in %d Sekunden gedimmt",
        cancel: "Abbrechen",
        restore: "Helligkeit wiederherstellen",
        active: "Übergabe aktiv",
        permission: "Erlaube den Zugriff unter Bedienungshilfen in den Systemeinstellungen, um dein iPhone zu verbinden.",
        unavailable: "Kein iPhone-Hotspot gefunden. Halte dein iPhone mit aktiviertem WLAN und Bluetooth in der Nähe.",
        connectionFailed: "Verbindung zum ausgewählten iPhone fehlgeschlagen. Dein Display wurde nicht gedimmt.",
        quitFailed: "Einige Apps wurden nicht beendet. Sichere deine Arbeit und versuche es erneut.",
        brightnessFailed: "Die Helligkeit des integrierten Displays konnte nicht geändert werden.",
        setup: "Wähle zuerst dein iPhone in den Übergabeoptionen aus.",
        help: "Verbindet dein iPhone über die Systemeinstellungen. Bestehende Netzwerkverbindungen können sich erneut verbinden. Beim Abbrechen werden Apps nicht erneut geöffnet und die vorherige WLAN-Verbindung wird nicht wiederhergestellt."
    )

    static let fr = ContinuityStrings(
        start: "Démarrer le transfert",
        title: "Passer à l’iPhone",
        settingsTitle: "Options de transfert",
        hotspot: "Partage de connexion de l’iPhone",
        discover: "Rechercher un iPhone",
        chooseHotspot: "Choisir un iPhone",
        apps: "Apps à quitter",
        appsCaption: "Ces apps se ferment normalement après la connexion. Un travail non enregistré peut interrompre le transfert.",
        addApp: "Ajouter une app",
        removeApp: "Retirer l’app",
        connecting: "Connexion à l’iPhone…",
        quitting: "Fermeture des apps sélectionnées…",
        countdown: "L’écran s’assombrira dans %d secondes",
        cancel: "Annuler",
        restore: "Rétablir la luminosité",
        active: "Transfert actif",
        permission: "Autorisez l’accès à l’accessibilité dans Réglages Système pour vous connecter à votre iPhone.",
        unavailable: "Aucun partage de connexion d’iPhone trouvé. Gardez votre iPhone à proximité avec le Wi-Fi et le Bluetooth activés.",
        connectionFailed: "Impossible de se connecter à l’iPhone sélectionné. Votre écran n’a pas été assombri.",
        quitFailed: "Certaines apps ne se sont pas fermées. Enregistrez votre travail et réessayez.",
        brightnessFailed: "Impossible de modifier la luminosité de l’écran intégré.",
        setup: "Choisissez d’abord votre iPhone dans les options de transfert.",
        help: "Utilise Réglages Système pour se connecter à votre iPhone. Les connexions réseau existantes peuvent se reconnecter. L’annulation ne rouvre pas les apps et ne rétablit pas la connexion Wi-Fi précédente."
    )

    static let it = ContinuityStrings(
        start: "Avvia trasferimento",
        title: "Passa a iPhone",
        settingsTitle: "Opzioni di passaggio",
        hotspot: "Hotspot di iPhone",
        discover: "Cerca iPhone",
        chooseHotspot: "Scegli un iPhone",
        apps: "App da chiudere",
        appsCaption: "Queste app si chiudono normalmente dopo la connessione. Il lavoro non salvato può interrompere il passaggio.",
        addApp: "Aggiungi app",
        removeApp: "Rimuovi app",
        connecting: "Connessione a iPhone…",
        quitting: "Chiusura delle app selezionate…",
        countdown: "Lo schermo si attenuerà tra %d secondi",
        cancel: "Annulla",
        restore: "Ripristina luminosità",
        active: "Passaggio attivo",
        permission: "Consenti l’accesso ad Accessibilità in Impostazioni di Sistema per connetterti al tuo iPhone.",
        unavailable: "Nessun hotspot di iPhone trovato. Tieni iPhone vicino con Wi-Fi e Bluetooth attivi.",
        connectionFailed: "Impossibile connettersi all’iPhone selezionato. Lo schermo non è stato attenuato.",
        quitFailed: "Alcune app non si sono chiuse. Salva il lavoro e riprova.",
        brightnessFailed: "Impossibile modificare la luminosità dello schermo integrato.",
        setup: "Prima scegli il tuo iPhone nelle opzioni di passaggio.",
        help: "Usa Impostazioni di Sistema per connettersi al tuo iPhone. Le connessioni di rete esistenti potrebbero riconnettersi. Annullare non riapre le app e non ripristina la connessione Wi-Fi precedente."
    )

    static let ja = ContinuityStrings(
        start: "引き継ぎを開始",
        title: "iPhoneに引き継ぐ",
        settingsTitle: "引き継ぎオプション",
        hotspot: "iPhoneのインターネット共有",
        discover: "iPhoneを探す",
        chooseHotspot: "iPhoneを選択",
        apps: "終了するアプリ",
        appsCaption: "接続後、これらのアプリを通常の方法で終了します。未保存の作業があると、引き継ぎが停止することがあります。",
        addApp: "アプリを追加",
        removeApp: "アプリを削除",
        connecting: "iPhoneに接続中…",
        quitting: "選択したアプリを終了中…",
        countdown: "%d秒後に画面を暗くします",
        cancel: "キャンセル",
        restore: "明るさを元に戻す",
        active: "引き継ぎ中",
        permission: "iPhoneに接続するには、システム設定でアクセシビリティへのアクセスを許可してください。",
        unavailable: "iPhoneのインターネット共有が見つかりません。iPhoneを近くに置き、Wi-FiとBluetoothをオンにしてください。",
        connectionFailed: "選択したiPhoneに接続できませんでした。画面の明るさは変更されていません。",
        quitFailed: "一部のアプリが終了しませんでした。作業を保存して、もう一度お試しください。",
        brightnessFailed: "内蔵ディスプレイの明るさを変更できませんでした。",
        setup: "まず引き継ぎオプションでiPhoneを選択してください。",
        help: "システム設定を使ってiPhoneに接続します。既存のネットワーク接続が再接続される場合があります。キャンセルしてもアプリは開き直されず、Wi-Fi接続も元に戻りません。"
    )

    static let ko = ContinuityStrings(
        start: "이어받기 시작",
        title: "iPhone으로 이어가기",
        settingsTitle: "이어가기 옵션",
        hotspot: "iPhone 개인용 핫스팟",
        discover: "iPhone 찾기",
        chooseHotspot: "iPhone 선택",
        apps: "종료할 앱",
        appsCaption: "연결 후 이 앱들이 정상적으로 종료됩니다. 저장하지 않은 작업이 있으면 이어가기가 중단될 수 있습니다.",
        addApp: "앱 추가",
        removeApp: "앱 제거",
        connecting: "iPhone에 연결 중…",
        quitting: "선택한 앱 종료 중…",
        countdown: "%d초 후 화면이 어두워집니다",
        cancel: "취소",
        restore: "밝기 복원",
        active: "이어가기 활성화됨",
        permission: "iPhone에 연결하려면 시스템 설정에서 손쉬운 사용 접근을 허용하세요.",
        unavailable: "iPhone 개인용 핫스팟을 찾지 못했습니다. Wi-Fi와 Bluetooth를 켠 상태로 iPhone을 가까이 두세요.",
        connectionFailed: "선택한 iPhone에 연결하지 못했습니다. 화면 밝기는 변경되지 않았습니다.",
        quitFailed: "일부 앱이 종료되지 않았습니다. 작업을 저장하고 다시 시도하세요.",
        brightnessFailed: "내장 디스플레이 밝기를 변경하지 못했습니다.",
        setup: "먼저 이어가기 옵션에서 iPhone을 선택하세요.",
        help: "시스템 설정을 사용하여 iPhone에 연결합니다. 기존 네트워크 연결이 다시 연결될 수 있습니다. 취소해도 앱이 다시 열리거나 이전 Wi-Fi 연결로 돌아가지 않습니다."
    )

    static let zhHans = ContinuityStrings(
        start: "开始接力",
        title: "接力到手机",
        settingsTitle: "接力选项",
        hotspot: "iPhone 个人热点",
        discover: "查找 iPhone",
        chooseHotspot: "选择 iPhone",
        apps: "要退出的 App",
        appsCaption: "连接后会正常退出这些 App。未保存的工作可能会中止接力。",
        addApp: "添加 App",
        removeApp: "移除 App",
        connecting: "正在连接 iPhone…",
        quitting: "正在退出所选 App…",
        countdown: "%d 秒后调暗屏幕",
        cancel: "取消",
        restore: "恢复亮度",
        active: "接力已启用",
        permission: "请在系统设置中允许辅助功能访问，以连接你的 iPhone。",
        unavailable: "未找到 iPhone 个人热点。请将 iPhone 放在附近，并开启 Wi-Fi 和蓝牙。",
        connectionFailed: "无法连接所选 iPhone。屏幕尚未调暗。",
        quitFailed: "部分 App 未退出。请保存工作后重试。",
        brightnessFailed: "无法更改内建显示屏的亮度。",
        setup: "请先在接力选项中选择你的 iPhone。",
        help: "通过系统设置连接你的 iPhone。现有网络连接可能会重新连接。取消不会重新打开 App，也不会恢复原来的 Wi-Fi 连接。"
    )

    static let zhTW = ContinuityStrings(
        start: "開始接力",
        title: "接力到手機",
        settingsTitle: "接力選項",
        hotspot: "iPhone 個人熱點",
        discover: "尋找 iPhone",
        chooseHotspot: "選擇 iPhone",
        apps: "要結束的 App",
        appsCaption: "連線後會正常結束這些 App。尚未儲存的工作可能會中止接力。",
        addApp: "加入 App",
        removeApp: "移除 App",
        connecting: "正在連接 iPhone…",
        quitting: "正在結束所選 App…",
        countdown: "%d 秒後調暗螢幕",
        cancel: "取消",
        restore: "恢復亮度",
        active: "接力已啟用",
        permission: "請在「系統設定」中允許「輔助使用」存取權限，以連接你的 iPhone。",
        unavailable: "找不到 iPhone 個人熱點。請將 iPhone 放在附近，並開啟 Wi-Fi 和藍牙。",
        connectionFailed: "無法連接所選 iPhone。螢幕尚未調暗。",
        quitFailed: "部分 App 尚未結束。請儲存工作後再試一次。",
        brightnessFailed: "無法變更內建顯示器的亮度。",
        setup: "請先在接力選項中選擇你的 iPhone。",
        help: "透過「系統設定」連接你的 iPhone。現有網路連線可能會重新連線。取消不會重新開啟 App，也不會恢復原本的 Wi-Fi 連線。"
    )

    static let zhHK = ContinuityStrings(
        start: "開始接力",
        title: "接力到手機",
        settingsTitle: "接力選項",
        hotspot: "iPhone 個人熱點",
        discover: "尋找 iPhone",
        chooseHotspot: "選擇 iPhone",
        apps: "要結束的 App",
        appsCaption: "連線後會正常結束這些 App。尚未儲存的工作可能會中止接力。",
        addApp: "加入 App",
        removeApp: "移除 App",
        connecting: "正在連接 iPhone…",
        quitting: "正在結束所選 App…",
        countdown: "%d 秒後調暗螢幕",
        cancel: "取消",
        restore: "還原亮度",
        active: "接力已啟用",
        permission: "請在「系統設定」中允許「輔助使用」取用權限，以連接你的 iPhone。",
        unavailable: "找不到 iPhone 個人熱點。請將 iPhone 放在附近，並開啟 Wi-Fi 和藍牙。",
        connectionFailed: "無法連接所選 iPhone。螢幕尚未調暗。",
        quitFailed: "部分 App 尚未結束。請儲存工作後再試一次。",
        brightnessFailed: "無法更改內置顯示器的亮度。",
        setup: "請先在接力選項中選擇你的 iPhone。",
        help: "透過「系統設定」連接你的 iPhone。現有網絡連線可能會重新連線。取消不會重新開啟 App，也不會還原原本的 Wi-Fi 連線。"
    )

    static let uk = ContinuityStrings(
        start: "Почати передавання",
        title: "Перейти на iPhone",
        settingsTitle: "Параметри переходу",
        hotspot: "Точка доступу iPhone",
        discover: "Знайти iPhone",
        chooseHotspot: "Вибрати iPhone",
        apps: "Програми для завершення",
        appsCaption: "Після підключення ці програми завершаться звичайним способом. Незбережена робота може зупинити перехід.",
        addApp: "Додати програму",
        removeApp: "Прибрати програму",
        connecting: "Підключення до iPhone…",
        quitting: "Завершення вибраних програм…",
        countdown: "Екран потьмяніє через %d с",
        cancel: "Скасувати",
        restore: "Відновити яскравість",
        active: "Перехід активний",
        permission: "Надайте дозвіл «Доступність» у Системних параметрах, щоб підключитися до iPhone.",
        unavailable: "Точку доступу iPhone не знайдено. Тримайте iPhone поруч з увімкненими Wi-Fi та Bluetooth.",
        connectionFailed: "Не вдалося підключитися до вибраного iPhone. Яскравість екрана не зменшено.",
        quitFailed: "Деякі програми не завершилися. Збережіть роботу й повторіть спробу.",
        brightnessFailed: "Не вдалося змінити яскравість вбудованого дисплея.",
        setup: "Спочатку виберіть iPhone у параметрах переходу.",
        help: "Для підключення до iPhone використовуються Системні параметри. Наявні мережеві з’єднання можуть підключитися повторно. Скасування не відкриває програми знову й не відновлює попереднє з’єднання Wi-Fi."
    )
}
