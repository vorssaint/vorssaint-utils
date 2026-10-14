// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// Strings for the Bluetooth on sleep feature. Same contract as the other
/// FeatureStrings structs: memberwise init with labeled arguments in
/// declaration order, one static per language, all in this file.
struct BluetoothSleepStrings {
    let pageTitle: String
    let hubDescription: String
    let enable: String
    let enableCaption: String
    let restoreToggle: String
    let restoreCaption: String
    let unsupported: String
    let modeLabel: String
    let powerOffMode: String
    let selectedDevicesMode: String
    let selectedCaption: String
    let devicesLabel: String
    let noDevices: String
    let refresh: String
    let connected: String
    let disconnected: String
    let notPaired: String
    let emptySelection: String
    let failedFormat: String
    let reconnectNote: String
}

extension FeatureStrings {
    static func bluetoothSleep(_ language: AppLanguage) -> BluetoothSleepStrings {
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

extension BluetoothSleepStrings {
    static let enUS = BluetoothSleepStrings(
        pageTitle: "Bluetooth on sleep",
        hubDescription: "Disconnect selected devices or turn Bluetooth off when the Mac sleeps.",
        enable: "Manage Bluetooth when the Mac sleeps",
        enableCaption: "Choose whether to turn Bluetooth off or disconnect selected devices.",
        restoreToggle: "Turn Bluetooth back on when the Mac wakes",
        restoreCaption: "Only when Vorssaint was the one that switched it off.",
        unsupported: "This Mac has no Bluetooth controller.",
        modeLabel: "Sleep action",
        powerOffMode: "Turn Bluetooth off",
        selectedDevicesMode: "Disconnect selected devices",
        selectedCaption: "Bluetooth stays on. Only checked devices disconnect; leave your keyboard and mouse unchecked.",
        devicesLabel: "Devices to disconnect",
        noDevices: "No paired Bluetooth devices found. Check Bluetooth access in System Settings if devices are missing.",
        refresh: "Refresh devices",
        connected: "Connected",
        disconnected: "Disconnected",
        notPaired: "Not currently paired",
        emptySelection: "Select a device to disconnect. An empty selection disconnects nothing.",
        failedFormat: "%d selected devices could not be disconnected on the last sleep.",
        reconnectNote: "Devices stay paired. Vorssaint does not reconnect them on wake."
    )

    static let ptBR = BluetoothSleepStrings(
        pageTitle: "Bluetooth ao dormir",
        hubDescription: "Desconecta dispositivos selecionados ou desliga o Bluetooth quando o Mac dorme.",
        enable: "Gerenciar Bluetooth quando o Mac dormir",
        enableCaption: "Escolha entre desligar o Bluetooth e desconectar dispositivos selecionados.",
        restoreToggle: "Ligar o Bluetooth de volta quando o Mac acordar",
        restoreCaption: "Apenas quando foi o Vorssaint que o desligou.",
        unsupported: "Este Mac não tem controlador Bluetooth.",
        modeLabel: "Ação ao dormir",
        powerOffMode: "Desligar Bluetooth",
        selectedDevicesMode: "Desconectar dispositivos selecionados",
        selectedCaption: "O Bluetooth continua ligado. Só os dispositivos marcados são desconectados; deixe o teclado e o mouse desmarcados.",
        devicesLabel: "Dispositivos para desconectar",
        noDevices: "Nenhum dispositivo Bluetooth pareado encontrado. Se faltarem dispositivos, confira o acesso ao Bluetooth nos Ajustes do Sistema.",
        refresh: "Atualizar dispositivos",
        connected: "Conectado",
        disconnected: "Desconectado",
        notPaired: "Não pareado no momento",
        emptySelection: "Selecione um dispositivo para desconectar. Uma seleção vazia não desconecta nada.",
        failedFormat: "Não foi possível desconectar %d dispositivos selecionados no último repouso.",
        reconnectNote: "Os dispositivos continuam pareados. O Vorssaint não os reconecta ao acordar."
    )

    static let tr = BluetoothSleepStrings(
        pageTitle: "Uykuda Bluetooth",
        hubDescription: "Mac uyuduğunda seçilen aygıtların bağlantısını keser veya Bluetooth’u kapatır.",
        enable: "Mac uyuduğunda Bluetooth’u yönet",
        enableCaption: "Bluetooth’u kapatmayı veya seçilen aygıtların bağlantısını kesmeyi seçin.",
        restoreToggle: "Mac uyandığında Bluetooth’u yeniden aç",
        restoreCaption: "Yalnızca kapatan Vorssaint olduğunda.",
        unsupported: "Bu Mac’te Bluetooth denetleyicisi yok.",
        modeLabel: "Uyku eylemi",
        powerOffMode: "Bluetooth’u kapat",
        selectedDevicesMode: "Seçilen aygıtların bağlantısını kes",
        selectedCaption: "Bluetooth açık kalır. Yalnızca işaretli aygıtların bağlantısı kesilir; klavye ve fareyi işaretlemeyin.",
        devicesLabel: "Bağlantısı kesilecek aygıtlar",
        noDevices: "Eşlenmiş Bluetooth aygıtı bulunamadı. Aygıtlar eksikse Sistem Ayarları’nda Bluetooth erişimini kontrol edin.",
        refresh: "Aygıtları yenile",
        connected: "Bağlı",
        disconnected: "Bağlı değil",
        notPaired: "Şu anda eşlenmemiş",
        emptySelection: "Bağlantısı kesilecek bir aygıt seçin. Boş seçim hiçbir bağlantıyı kesmez.",
        failedFormat: "Son uykuda %d seçili aygıtın bağlantısı kesilemedi.",
        reconnectNote: "Aygıtlar eşlenmiş kalır. Vorssaint uyanışta yeniden bağlantı kurmaz."
    )

    static let ru = BluetoothSleepStrings(
        pageTitle: "Bluetooth при сне",
        hubDescription: "Отключает выбранные устройства или выключает Bluetooth, когда Mac засыпает.",
        enable: "Управлять Bluetooth при переходе Mac в сон",
        enableCaption: "Выберите выключение Bluetooth или отключение выбранных устройств.",
        restoreToggle: "Включать Bluetooth обратно при пробуждении Mac",
        restoreCaption: "Только если его выключил сам Vorssaint.",
        unsupported: "На этом Mac нет контроллера Bluetooth.",
        modeLabel: "Действие при переходе в сон",
        powerOffMode: "Выключить Bluetooth",
        selectedDevicesMode: "Отключить выбранные устройства",
        selectedCaption: "Bluetooth остаётся включённым. Отключаются только отмеченные устройства; не отмечайте клавиатуру и мышь.",
        devicesLabel: "Устройства для отключения",
        noDevices: "Сопряжённые устройства Bluetooth не найдены. Если устройства отсутствуют, проверьте доступ к Bluetooth в Системных настройках.",
        refresh: "Обновить устройства",
        connected: "Подключено",
        disconnected: "Отключено",
        notPaired: "Сейчас не сопряжено",
        emptySelection: "Выберите устройство для отключения. Пустой выбор ничего не отключает.",
        failedFormat: "При последнем переходе в сон не удалось отключить выбранные устройства: %d.",
        reconnectNote: "Устройства остаются сопряжёнными. Vorssaint не подключает их при пробуждении."
    )

    static let es = BluetoothSleepStrings(
        pageTitle: "Bluetooth al reposo",
        hubDescription: "Desconecta dispositivos seleccionados o apaga Bluetooth cuando el Mac entra en reposo.",
        enable: "Gestionar Bluetooth cuando el Mac entre en reposo",
        enableCaption: "Elige entre apagar Bluetooth y desconectar dispositivos seleccionados.",
        restoreToggle: "Volver a encender el Bluetooth cuando el Mac despierte",
        restoreCaption: "Solo cuando fue Vorssaint quien lo apagó.",
        unsupported: "Este Mac no tiene controlador Bluetooth.",
        modeLabel: "Acción al entrar en reposo",
        powerOffMode: "Apagar Bluetooth",
        selectedDevicesMode: "Desconectar dispositivos seleccionados",
        selectedCaption: "Bluetooth permanece encendido. Solo se desconectan los dispositivos marcados; deja el teclado y el ratón sin marcar.",
        devicesLabel: "Dispositivos para desconectar",
        noDevices: "No se encontraron dispositivos Bluetooth enlazados. Si faltan dispositivos, revisa el acceso a Bluetooth en Ajustes del Sistema.",
        refresh: "Actualizar dispositivos",
        connected: "Conectado",
        disconnected: "Desconectado",
        notPaired: "No enlazado actualmente",
        emptySelection: "Selecciona un dispositivo para desconectar. Una selección vacía no desconecta nada.",
        failedFormat: "No se pudieron desconectar %d dispositivos seleccionados en el último reposo.",
        reconnectNote: "Los dispositivos siguen enlazados. Vorssaint no los reconecta al despertar."
    )

    static let sk = BluetoothSleepStrings(
        pageTitle: "Bluetooth v spánku",
        hubDescription: "Odpojí vybrané zariadenia alebo vypne Bluetooth, keď Mac zaspí.",
        enable: "Spravovať Bluetooth, keď Mac zaspí",
        enableCaption: "Vyberte, či sa má vypnúť Bluetooth alebo odpojiť vybrané zariadenia.",
        restoreToggle: "Znova zapnúť Bluetooth pri prebudení Macu",
        restoreCaption: "Iba ak ho vypol Vorssaint.",
        unsupported: "Tento Mac nemá Bluetooth radič.",
        modeLabel: "Akcia pri spánku",
        powerOffMode: "Vypnúť Bluetooth",
        selectedDevicesMode: "Odpojiť vybrané zariadenia",
        selectedCaption: "Bluetooth ostáva zapnutý. Odpoja sa iba označené zariadenia; klávesnicu a myš nechajte neoznačené.",
        devicesLabel: "Zariadenia na odpojenie",
        noDevices: "Nenašli sa žiadne spárované Bluetooth zariadenia. Ak zariadenia chýbajú, skontrolujte prístup k Bluetooth v Systémových nastaveniach.",
        refresh: "Obnoviť zariadenia",
        connected: "Pripojené",
        disconnected: "Odpojené",
        notPaired: "Momentálne nespárované",
        emptySelection: "Vyberte zariadenie na odpojenie. Prázdny výber nič neodpojí.",
        failedFormat: "Pri poslednom spánku sa nepodarilo odpojiť %d vybraných zariadení.",
        reconnectNote: "Zariadenia ostávajú spárované. Vorssaint ich pri prebudení znova nepripojí."
    )

    static let de = BluetoothSleepStrings(
        pageTitle: "Bluetooth im Ruhezustand",
        hubDescription: "Trennt ausgewählte Geräte oder schaltet Bluetooth aus, wenn der Mac in den Ruhezustand geht.",
        enable: "Bluetooth im Ruhezustand verwalten",
        enableCaption: "Wählen Sie, ob Bluetooth ausgeschaltet oder ausgewählte Geräte getrennt werden.",
        restoreToggle: "Bluetooth wieder einschalten, wenn der Mac aufwacht",
        restoreCaption: "Nur wenn Vorssaint es ausgeschaltet hat.",
        unsupported: "Dieser Mac hat keinen Bluetooth-Controller.",
        modeLabel: "Aktion im Ruhezustand",
        powerOffMode: "Bluetooth ausschalten",
        selectedDevicesMode: "Ausgewählte Geräte trennen",
        selectedCaption: "Bluetooth bleibt eingeschaltet. Nur markierte Geräte werden getrennt; lassen Sie Tastatur und Maus unmarkiert.",
        devicesLabel: "Zu trennende Geräte",
        noDevices: "Keine gekoppelten Bluetooth-Geräte gefunden. Prüfen Sie bei fehlenden Geräten den Bluetooth-Zugriff in den Systemeinstellungen.",
        refresh: "Geräte aktualisieren",
        connected: "Verbunden",
        disconnected: "Getrennt",
        notPaired: "Derzeit nicht gekoppelt",
        emptySelection: "Wählen Sie ein zu trennendes Gerät. Eine leere Auswahl trennt nichts.",
        failedFormat: "%d ausgewählte Geräte konnten beim letzten Ruhezustand nicht getrennt werden.",
        reconnectNote: "Die Geräte bleiben gekoppelt. Vorssaint verbindet sie beim Aufwachen nicht erneut."
    )

    static let fr = BluetoothSleepStrings(
        pageTitle: "Bluetooth en veille",
        hubDescription: "Déconnecte les appareils sélectionnés ou coupe le Bluetooth quand le Mac se met en veille.",
        enable: "Gérer le Bluetooth quand le Mac se met en veille",
        enableCaption: "Choisissez de couper le Bluetooth ou de déconnecter les appareils sélectionnés.",
        restoreToggle: "Rallumer le Bluetooth au réveil du Mac",
        restoreCaption: "Uniquement si c’est Vorssaint qui l’a coupé.",
        unsupported: "Ce Mac n’a pas de contrôleur Bluetooth.",
        modeLabel: "Action à la mise en veille",
        powerOffMode: "Couper le Bluetooth",
        selectedDevicesMode: "Déconnecter les appareils sélectionnés",
        selectedCaption: "Le Bluetooth reste activé. Seuls les appareils cochés sont déconnectés ; laissez le clavier et la souris décochés.",
        devicesLabel: "Appareils à déconnecter",
        noDevices: "Aucun appareil Bluetooth jumelé trouvé. Si des appareils manquent, vérifiez l’accès au Bluetooth dans Réglages Système.",
        refresh: "Actualiser les appareils",
        connected: "Connecté",
        disconnected: "Déconnecté",
        notPaired: "Non jumelé actuellement",
        emptySelection: "Sélectionnez un appareil à déconnecter. Une sélection vide ne déconnecte rien.",
        failedFormat: "%d appareils sélectionnés n’ont pas pu être déconnectés lors de la dernière veille.",
        reconnectNote: "Les appareils restent jumelés. Vorssaint ne les reconnecte pas au réveil."
    )

    static let it = BluetoothSleepStrings(
        pageTitle: "Bluetooth in stop",
        hubDescription: "Disconnette i dispositivi selezionati o spegne Bluetooth quando il Mac va in stop.",
        enable: "Gestisci Bluetooth quando il Mac va in stop",
        enableCaption: "Scegli se spegnere Bluetooth o disconnettere i dispositivi selezionati.",
        restoreToggle: "Riaccendi il Bluetooth quando il Mac si riattiva",
        restoreCaption: "Solo quando è stato Vorssaint a spegnerlo.",
        unsupported: "Questo Mac non ha un controller Bluetooth.",
        modeLabel: "Azione in stop",
        powerOffMode: "Spegni Bluetooth",
        selectedDevicesMode: "Disconnetti i dispositivi selezionati",
        selectedCaption: "Bluetooth resta acceso. Si disconnettono solo i dispositivi selezionati; lascia tastiera e mouse non selezionati.",
        devicesLabel: "Dispositivi da disconnettere",
        noDevices: "Nessun dispositivo Bluetooth abbinato trovato. Se mancano dispositivi, verifica l’accesso a Bluetooth in Impostazioni di Sistema.",
        refresh: "Aggiorna dispositivi",
        connected: "Connesso",
        disconnected: "Disconnesso",
        notPaired: "Attualmente non abbinato",
        emptySelection: "Seleziona un dispositivo da disconnettere. Una selezione vuota non disconnette nulla.",
        failedFormat: "Non è stato possibile disconnettere %d dispositivi selezionati durante l’ultimo stop.",
        reconnectNote: "I dispositivi restano abbinati. Vorssaint non li riconnette alla riattivazione."
    )

    static let ja = BluetoothSleepStrings(
        pageTitle: "スリープ時のBluetooth",
        hubDescription: "Macのスリープ時に選択したデバイスを切断するか、Bluetoothをオフにします。",
        enable: "Macのスリープ時にBluetoothを管理",
        enableCaption: "Bluetoothをオフにするか、選択したデバイスだけを切断するか選びます。",
        restoreToggle: "Macの復帰時に Bluetooth を戻す",
        restoreCaption: "Vorssaintが切った場合のみ戻します。",
        unsupported: "このMacにはBluetoothコントローラがありません。",
        modeLabel: "スリープ時の動作",
        powerOffMode: "Bluetoothをオフにする",
        selectedDevicesMode: "選択したデバイスを切断",
        selectedCaption: "Bluetoothはオンのままです。チェックしたデバイスだけを切断します。キーボードとマウスはチェックしないでください。",
        devicesLabel: "切断するデバイス",
        noDevices: "ペアリング済みのBluetoothデバイスが見つかりません。デバイスが表示されない場合はシステム設定でBluetoothへのアクセスを確認してください。",
        refresh: "デバイスを更新",
        connected: "接続済み",
        disconnected: "未接続",
        notPaired: "現在ペアリングされていません",
        emptySelection: "切断するデバイスを選択してください。何も選択しない場合は切断しません。",
        failedFormat: "前回のスリープ時に選択した%d台のデバイスを切断できませんでした。",
        reconnectNote: "ペアリングは維持されます。Vorssaintはスリープ解除時に再接続しません。"
    )

    static let ko = BluetoothSleepStrings(
        pageTitle: "잠자기 시 Bluetooth",
        hubDescription: "Mac이 잠들면 선택한 기기의 연결을 끊거나 Bluetooth를 끕니다.",
        enable: "Mac이 잠들 때 Bluetooth 관리",
        enableCaption: "Bluetooth를 끄거나 선택한 기기만 연결 해제하도록 선택하세요.",
        restoreToggle: "Mac이 깨어나면 Bluetooth 다시 켜기",
        restoreCaption: "Vorssaint가 껐을 때만 다시 켭니다.",
        unsupported: "이 Mac에는 Bluetooth 컨트롤러가 없습니다.",
        modeLabel: "잠자기 동작",
        powerOffMode: "Bluetooth 끄기",
        selectedDevicesMode: "선택한 기기 연결 해제",
        selectedCaption: "Bluetooth는 켜진 상태로 유지됩니다. 체크한 기기만 연결 해제되므로 키보드와 마우스는 체크하지 마세요.",
        devicesLabel: "연결 해제할 기기",
        noDevices: "페어링된 Bluetooth 기기를 찾을 수 없습니다. 기기가 누락되면 시스템 설정에서 Bluetooth 접근 권한을 확인하세요.",
        refresh: "기기 새로 고침",
        connected: "연결됨",
        disconnected: "연결 안 됨",
        notPaired: "현재 페어링되지 않음",
        emptySelection: "연결 해제할 기기를 선택하세요. 선택하지 않으면 아무것도 연결 해제되지 않습니다.",
        failedFormat: "지난 잠자기에서 선택한 기기 %d개를 연결 해제하지 못했습니다.",
        reconnectNote: "기기의 페어링은 유지됩니다. Vorssaint는 깨어날 때 다시 연결하지 않습니다."
    )

    static let zhHans = BluetoothSleepStrings(
        pageTitle: "睡眠时的蓝牙",
        hubDescription: "Mac 睡眠时断开所选设备或关闭蓝牙。",
        enable: "管理 Mac 睡眠时的蓝牙",
        enableCaption: "选择关闭蓝牙或仅断开所选设备。",
        restoreToggle: "Mac 唤醒时重新打开蓝牙",
        restoreCaption: "仅在蓝牙是由 Vorssaint 关闭时。",
        unsupported: "这台 Mac 没有蓝牙控制器。",
        modeLabel: "睡眠时的操作",
        powerOffMode: "关闭蓝牙",
        selectedDevicesMode: "断开所选设备",
        selectedCaption: "蓝牙保持开启。仅断开勾选的设备；请勿勾选键盘和鼠标。",
        devicesLabel: "要断开的设备",
        noDevices: "未找到已配对的蓝牙设备。如果设备未显示，请在系统设置中检查蓝牙访问权限。",
        refresh: "刷新设备",
        connected: "已连接",
        disconnected: "未连接",
        notPaired: "当前未配对",
        emptySelection: "请选择要断开的设备。未选择任何设备时不会断开连接。",
        failedFormat: "上次睡眠时有 %d 个所选设备未能断开连接。",
        reconnectNote: "设备保持配对。Vorssaint 不会在唤醒时重新连接它们。"
    )

    static let zhTW = BluetoothSleepStrings(
        pageTitle: "睡眠時的藍牙",
        hubDescription: "Mac 睡眠時中斷所選裝置的連線或關閉藍牙。",
        enable: "管理 Mac 睡眠時的藍牙",
        enableCaption: "選擇關閉藍牙或僅中斷所選裝置的連線。",
        restoreToggle: "Mac 喚醒時重新開啟藍牙",
        restoreCaption: "僅在藍牙是由 Vorssaint 關閉時。",
        unsupported: "這台 Mac 沒有藍牙控制器。",
        modeLabel: "睡眠時的動作",
        powerOffMode: "關閉藍牙",
        selectedDevicesMode: "中斷所選裝置的連線",
        selectedCaption: "藍牙保持開啟。僅中斷勾選裝置的連線；請勿勾選鍵盤和滑鼠。",
        devicesLabel: "要中斷連線的裝置",
        noDevices: "找不到已配對的藍牙裝置。如果裝置未顯示，請在系統設定中檢查藍牙存取權限。",
        refresh: "重新整理裝置",
        connected: "已連接",
        disconnected: "未連接",
        notPaired: "目前未配對",
        emptySelection: "請選擇要中斷連線的裝置。未選擇任何裝置時不會中斷連線。",
        failedFormat: "上次睡眠時有 %d 個所選裝置無法中斷連線。",
        reconnectNote: "裝置保持配對。Vorssaint 不會在喚醒時重新連接它們。"
    )

    static let zhHK = BluetoothSleepStrings(
        pageTitle: "睡眠時的藍牙",
        hubDescription: "Mac 睡眠時中斷所選裝置的連線或關閉藍牙。",
        enable: "管理 Mac 睡眠時的藍牙",
        enableCaption: "選擇關閉藍牙或只中斷所選裝置的連線。",
        restoreToggle: "Mac 喚醒時重新開啟藍牙",
        restoreCaption: "只在藍牙是由 Vorssaint 關閉時。",
        unsupported: "這部 Mac 沒有藍牙控制器。",
        modeLabel: "睡眠時的動作",
        powerOffMode: "關閉藍牙",
        selectedDevicesMode: "中斷所選裝置的連線",
        selectedCaption: "藍牙保持開啟。只會中斷已勾選裝置的連線；請勿勾選鍵盤和滑鼠。",
        devicesLabel: "要中斷連線的裝置",
        noDevices: "找不到已配對的藍牙裝置。如果裝置未顯示，請在系統設定中檢查藍牙存取權限。",
        refresh: "重新整理裝置",
        connected: "已連接",
        disconnected: "未連接",
        notPaired: "目前未配對",
        emptySelection: "請選擇要中斷連線的裝置。沒有選擇任何裝置時不會中斷連線。",
        failedFormat: "上次睡眠時有 %d 個所選裝置未能中斷連線。",
        reconnectNote: "裝置保持配對。Vorssaint 不會在喚醒時重新連接它們。"
    )
    static let uk = BluetoothSleepStrings(
        pageTitle: "Bluetooth під час сну",
        hubDescription: "Від’єднує вибрані пристрої або вимикає Bluetooth, коли Mac засинає.",
        enable: "Керувати Bluetooth, коли Mac засинає",
        enableCaption: "Виберіть вимкнення Bluetooth або від’єднання вибраних пристроїв.",
        restoreToggle: "Ввімкнути Bluetooth назад, коли Mac прокидається",
        restoreCaption: "Лише коли Vorssaint сам його вимкнув.",
        unsupported: "На цьому Mac немає Bluetooth-контролера.",
        modeLabel: "Дія під час переходу в сон",
        powerOffMode: "Вимкнути Bluetooth",
        selectedDevicesMode: "Від’єднати вибрані пристрої",
        selectedCaption: "Bluetooth залишається ввімкненим. Від’єднуються лише позначені пристрої; не позначайте клавіатуру та мишу.",
        devicesLabel: "Пристрої для від’єднання",
        noDevices: "Спарованих пристроїв Bluetooth не знайдено. Якщо пристрої відсутні, перевірте доступ до Bluetooth у Системних параметрах.",
        refresh: "Оновити пристрої",
        connected: "Під’єднано",
        disconnected: "Від’єднано",
        notPaired: "Зараз не спаровано",
        emptySelection: "Виберіть пристрій для від’єднання. Порожній вибір нічого не від’єднує.",
        failedFormat: "Під час останнього переходу в сон не вдалося від’єднати вибрані пристрої: %d.",
        reconnectNote: "Пристрої залишаються спарованими. Vorssaint не під’єднує їх при пробудженні."
    )
}
