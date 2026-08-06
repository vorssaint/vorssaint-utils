// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

struct FanControlFeatureStrings {
    let title: String
    let hubDescription: String
    let showInPanel: String
    let settingsCaption: String
    let automatic: String
    let maximumCooling: String
    let fanNameFormat: String
    let rpmFormat: String
    let startCooling: String
    let stopCooling: String
    let allowControl: String
    let approvalCaption: String
    let openSettings: String
    let noFans: String
    let unsupported: String
    let alreadyControlled: String
    let failed: String
    let safetyCaption: String
    let timeLimitStopped: String
    let safetyStopped: String
    let menuBarTitle: String
}

extension FeatureStrings {
    static func fanControl(_ language: AppLanguage) -> FanControlFeatureStrings {
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

extension FanControlFeatureStrings {
    static let enUS = FanControlFeatureStrings(
        title: "Fan Control",
        hubDescription: "Runs every fan at maximum temporarily, then returns control to the Mac",
        showInPanel: "Show Fan Control in the panel",
        settingsCaption: "Adds a temporary maximum cooling control to the menu bar panel.",
        automatic: "Automatic",
        maximumCooling: "Maximum cooling",
        fanNameFormat: "Fan %d",
        rpmFormat: "%d RPM",
        startCooling: "Cool at maximum for 15 min",
        stopCooling: "Return to automatic",
        allowControl: "Allow fan control",
        approvalCaption: "Allow Vorssaint in Login Items to use the protected fan controller.",
        openSettings: "Open System Settings",
        noFans: "This Mac has no controllable fan.",
        unsupported: "Fan control is not available on this Mac.",
        alreadyControlled: "Another process is controlling the fans. Return it to automatic first.",
        failed: "The fans stayed automatic because control could not be verified.",
        safetyCaption: "Uses only the maximum reported by this Mac. Control returns to automatic after 15 minutes or if the connection stops.",
        timeLimitStopped: "Returned to automatic after 15 minutes.",
        safetyStopped: "Returned to automatic because control was interrupted.",
        menuBarTitle: "Fan speed"
    )

    static let ptBR = FanControlFeatureStrings(
        title: "Controle das ventoinhas",
        hubDescription: "Coloca todas as ventoinhas no máximo por um tempo e devolve o controle ao Mac",
        showInPanel: "Mostrar controle das ventoinhas no painel",
        settingsCaption: "Adiciona ao painel um controle temporário de resfriamento máximo.",
        automatic: "Automático",
        maximumCooling: "Resfriamento máximo",
        fanNameFormat: "Ventoinha %d",
        rpmFormat: "%d RPM",
        startCooling: "Resfriar no máximo por 15 min",
        stopCooling: "Voltar ao automático",
        allowControl: "Permitir controle",
        approvalCaption: "Permita o Vorssaint nos Itens de Início para usar o controle protegido das ventoinhas.",
        openSettings: "Abrir Ajustes do Sistema",
        noFans: "Este Mac não tem ventoinha controlável.",
        unsupported: "O controle das ventoinhas não está disponível neste Mac.",
        alreadyControlled: "Outro processo está controlando as ventoinhas. Volte ao automático nele primeiro.",
        failed: "As ventoinhas continuaram no automático porque não foi possível confirmar o controle.",
        safetyCaption: "Usa somente o máximo informado por este Mac. O controle volta ao automático após 15 minutos ou se a conexão parar.",
        timeLimitStopped: "Voltou ao automático após 15 minutos.",
        safetyStopped: "Voltou ao automático porque o controle foi interrompido.",
        menuBarTitle: "Velocidade das ventoinhas"
    )

    static let tr = FanControlFeatureStrings(
        title: "Fan denetimi",
        hubDescription: "Tüm fanları geçici olarak en yüksek hızda çalıştırır ve denetimi Mac'e geri verir",
        showInPanel: "Fan denetimini panelde göster",
        settingsCaption: "Menü çubuğu paneline geçici en yüksek soğutma denetimi ekler.",
        automatic: "Otomatik",
        maximumCooling: "En yüksek soğutma",
        fanNameFormat: "Fan %d",
        rpmFormat: "%d RPM",
        startCooling: "15 dk en yüksek hızda soğut",
        stopCooling: "Otomatiğe dön",
        allowControl: "Fan denetimine izin ver",
        approvalCaption: "Korumalı fan denetimini kullanmak için Giriş Öğeleri'nde Vorssaint'e izin verin.",
        openSettings: "Sistem Ayarları'nı aç",
        noFans: "Bu Mac'te denetlenebilir fan yok.",
        unsupported: "Fan denetimi bu Mac'te kullanılamıyor.",
        alreadyControlled: "Fanları başka bir işlem denetliyor. Önce orada otomatiğe dönün.",
        failed: "Denetim doğrulanamadığı için fanlar otomatikte kaldı.",
        safetyCaption: "Yalnızca bu Mac'in bildirdiği en yüksek hızı kullanır. Denetim 15 dakika sonra veya bağlantı kesilirse otomatiğe döner.",
        timeLimitStopped: "15 dakika sonra otomatiğe döndü.",
        safetyStopped: "Denetim kesildiği için otomatiğe döndü.",
        menuBarTitle: "Fan hızı"
    )

    static let ru = FanControlFeatureStrings(
        title: "Управление вентиляторами",
        hubDescription: "Временно включает все вентиляторы на максимум и возвращает управление Mac",
        showInPanel: "Показывать управление вентиляторами в панели",
        settingsCaption: "Добавляет в панель временное максимальное охлаждение.",
        automatic: "Автоматически",
        maximumCooling: "Максимальное охлаждение",
        fanNameFormat: "Вентилятор %d",
        rpmFormat: "%d об/мин",
        startCooling: "Максимум на 15 минут",
        stopCooling: "Вернуть автоматику",
        allowControl: "Разрешить управление",
        approvalCaption: "Разрешите Vorssaint в Объектах входа для защищённого управления вентиляторами.",
        openSettings: "Открыть Системные настройки",
        noFans: "На этом Mac нет управляемого вентилятора.",
        unsupported: "Управление вентиляторами недоступно на этом Mac.",
        alreadyControlled: "Вентиляторами управляет другой процесс. Сначала верните там автоматический режим.",
        failed: "Вентиляторы остались в автоматическом режиме, потому что управление не удалось проверить.",
        safetyCaption: "Используется только максимум, указанный этим Mac. Через 15 минут или при обрыве связи управление вернётся в автоматический режим.",
        timeLimitStopped: "Автоматический режим возвращён через 15 минут.",
        safetyStopped: "Автоматический режим возвращён из-за прерывания управления.",
        menuBarTitle: "Скорость вентиляторов"
    )

    static let es = FanControlFeatureStrings(
        title: "Control de ventiladores",
        hubDescription: "Pone todos los ventiladores al máximo temporalmente y devuelve el control al Mac",
        showInPanel: "Mostrar el control de ventiladores en el panel",
        settingsCaption: "Añade al panel un control temporal de refrigeración máxima.",
        automatic: "Automático",
        maximumCooling: "Refrigeración máxima",
        fanNameFormat: "Ventilador %d",
        rpmFormat: "%d RPM",
        startCooling: "Enfriar al máximo durante 15 min",
        stopCooling: "Volver a automático",
        allowControl: "Permitir el control",
        approvalCaption: "Permite Vorssaint en Ítems de inicio para usar el control protegido de ventiladores.",
        openSettings: "Abrir Ajustes del Sistema",
        noFans: "Este Mac no tiene ningún ventilador controlable.",
        unsupported: "El control de ventiladores no está disponible en este Mac.",
        alreadyControlled: "Otro proceso controla los ventiladores. Devuélvelos primero al modo automático.",
        failed: "Los ventiladores siguieron en modo automático porque no se pudo verificar el control.",
        safetyCaption: "Solo usa el máximo indicado por este Mac. El control vuelve a automático tras 15 minutos o si se corta la conexión.",
        timeLimitStopped: "Volvió a automático después de 15 minutos.",
        safetyStopped: "Volvió a automático porque se interrumpió el control.",
        menuBarTitle: "Velocidad de ventiladores"
    )

    static let de = FanControlFeatureStrings(
        title: "Lüftersteuerung",
        hubDescription: "Lässt alle Lüfter vorübergehend maximal laufen und gibt die Steuerung an den Mac zurück",
        showInPanel: "Lüftersteuerung im Panel anzeigen",
        settingsCaption: "Fügt dem Menüleistenpanel eine zeitlich begrenzte maximale Kühlung hinzu.",
        automatic: "Automatisch",
        maximumCooling: "Maximale Kühlung",
        fanNameFormat: "Lüfter %d",
        rpmFormat: "%d U/min",
        startCooling: "15 Min. maximal kühlen",
        stopCooling: "Zurück zu Automatisch",
        allowControl: "Lüftersteuerung erlauben",
        approvalCaption: "Erlaube Vorssaint unter Anmeldeobjekte, um die geschützte Lüftersteuerung zu verwenden.",
        openSettings: "Systemeinstellungen öffnen",
        noFans: "Dieser Mac hat keinen steuerbaren Lüfter.",
        unsupported: "Die Lüftersteuerung ist auf diesem Mac nicht verfügbar.",
        alreadyControlled: "Ein anderer Prozess steuert die Lüfter. Stelle sie dort zuerst auf Automatisch.",
        failed: "Die Lüfter blieben automatisch, weil die Steuerung nicht bestätigt werden konnte.",
        safetyCaption: "Verwendet nur das von diesem Mac gemeldete Maximum. Nach 15 Minuten oder bei unterbrochener Verbindung wird auf Automatisch zurückgestellt.",
        timeLimitStopped: "Nach 15 Minuten auf Automatisch zurückgestellt.",
        safetyStopped: "Wegen unterbrochener Steuerung auf Automatisch zurückgestellt.",
        menuBarTitle: "Lüfterdrehzahl"
    )

    static let fr = FanControlFeatureStrings(
        title: "Contrôle des ventilateurs",
        hubDescription: "Fait tourner tous les ventilateurs au maximum temporairement puis rend le contrôle au Mac",
        showInPanel: "Afficher le contrôle des ventilateurs dans le panneau",
        settingsCaption: "Ajoute au panneau un contrôle temporaire du refroidissement maximal.",
        automatic: "Automatique",
        maximumCooling: "Refroidissement maximal",
        fanNameFormat: "Ventilateur %d",
        rpmFormat: "%d tr/min",
        startCooling: "Refroidir au maximum pendant 15 min",
        stopCooling: "Revenir en automatique",
        allowControl: "Autoriser le contrôle",
        approvalCaption: "Autorisez Vorssaint dans Ouverture pour utiliser le contrôle protégé des ventilateurs.",
        openSettings: "Ouvrir Réglages Système",
        noFans: "Ce Mac n'a aucun ventilateur contrôlable.",
        unsupported: "Le contrôle des ventilateurs n'est pas disponible sur ce Mac.",
        alreadyControlled: "Un autre processus contrôle les ventilateurs. Rétablissez d'abord le mode automatique.",
        failed: "Les ventilateurs sont restés en mode automatique car le contrôle n'a pas pu être vérifié.",
        safetyCaption: "Utilise uniquement le maximum indiqué par ce Mac. Le contrôle redevient automatique après 15 minutes ou si la connexion s'arrête.",
        timeLimitStopped: "Mode automatique rétabli après 15 minutes.",
        safetyStopped: "Mode automatique rétabli car le contrôle a été interrompu.",
        menuBarTitle: "Vitesse des ventilateurs"
    )

    static let it = FanControlFeatureStrings(
        title: "Controllo ventole",
        hubDescription: "Porta temporaneamente tutte le ventole al massimo e restituisce il controllo al Mac",
        showInPanel: "Mostra il controllo ventole nel pannello",
        settingsCaption: "Aggiunge al pannello un controllo temporaneo del raffreddamento massimo.",
        automatic: "Automatico",
        maximumCooling: "Raffreddamento massimo",
        fanNameFormat: "Ventola %d",
        rpmFormat: "%d RPM",
        startCooling: "Raffredda al massimo per 15 min",
        stopCooling: "Torna ad automatico",
        allowControl: "Consenti il controllo",
        approvalCaption: "Consenti Vorssaint in Elementi login per usare il controllo protetto delle ventole.",
        openSettings: "Apri Impostazioni di Sistema",
        noFans: "Questo Mac non ha ventole controllabili.",
        unsupported: "Il controllo delle ventole non è disponibile su questo Mac.",
        alreadyControlled: "Un altro processo controlla le ventole. Prima riportale in automatico.",
        failed: "Le ventole sono rimaste in automatico perché non è stato possibile verificare il controllo.",
        safetyCaption: "Usa solo il massimo indicato da questo Mac. Il controllo torna automatico dopo 15 minuti o se la connessione si interrompe.",
        timeLimitStopped: "Ritorno automatico dopo 15 minuti.",
        safetyStopped: "Ritorno automatico perché il controllo è stato interrotto.",
        menuBarTitle: "Velocità ventole"
    )

    static let ja = FanControlFeatureStrings(
        title: "ファン制御",
        hubDescription: "すべてのファンを一時的に最大で回し、制御をMacに戻します",
        showInPanel: "パネルにファン制御を表示",
        settingsCaption: "一時的な最大冷却の操作をメニューバーパネルに追加します。",
        automatic: "自動",
        maximumCooling: "最大冷却",
        fanNameFormat: "ファン%d",
        rpmFormat: "%d RPM",
        startCooling: "15分間最大で冷却",
        stopCooling: "自動に戻す",
        allowControl: "ファン制御を許可",
        approvalCaption: "保護されたファン制御を使うには、ログイン項目でVorssaintを許可してください。",
        openSettings: "システム設定を開く",
        noFans: "このMacには制御できるファンがありません。",
        unsupported: "このMacではファン制御を利用できません。",
        alreadyControlled: "別のプロセスがファンを制御しています。先に自動へ戻してください。",
        failed: "制御を確認できなかったため、ファンは自動のままです。",
        safetyCaption: "このMacが示す最大値だけを使います。15分後または接続が止まると自動制御に戻ります。",
        timeLimitStopped: "15分後に自動制御へ戻りました。",
        safetyStopped: "制御が中断されたため自動へ戻りました。",
        menuBarTitle: "ファン速度"
    )

    static let ko = FanControlFeatureStrings(
        title: "팬 제어",
        hubDescription: "모든 팬을 잠시 최대로 작동한 뒤 제어를 Mac에 돌려줍니다",
        showInPanel: "패널에 팬 제어 표시",
        settingsCaption: "메뉴 막대 패널에 임시 최대 냉각 제어를 추가합니다.",
        automatic: "자동",
        maximumCooling: "최대 냉각",
        fanNameFormat: "팬 %d",
        rpmFormat: "%d RPM",
        startCooling: "15분간 최대로 냉각",
        stopCooling: "자동으로 돌아가기",
        allowControl: "팬 제어 허용",
        approvalCaption: "보호된 팬 제어를 사용하려면 로그인 항목에서 Vorssaint를 허용하세요.",
        openSettings: "시스템 설정 열기",
        noFans: "이 Mac에는 제어할 수 있는 팬이 없습니다.",
        unsupported: "이 Mac에서는 팬 제어를 사용할 수 없습니다.",
        alreadyControlled: "다른 프로세스가 팬을 제어하고 있습니다. 먼저 자동으로 돌려놓으세요.",
        failed: "제어를 확인할 수 없어 팬이 자동 상태로 유지되었습니다.",
        safetyCaption: "이 Mac이 보고한 최대값만 사용합니다. 15분이 지나거나 연결이 끊기면 자동 제어로 돌아갑니다.",
        timeLimitStopped: "15분 후 자동 제어로 돌아갔습니다.",
        safetyStopped: "제어가 중단되어 자동으로 돌아갔습니다.",
        menuBarTitle: "팬 속도"
    )

    static let zhHans = FanControlFeatureStrings(
        title: "风扇控制",
        hubDescription: "暂时让所有风扇全速运行，然后把控制权交还给Mac",
        showInPanel: "在面板中显示风扇控制",
        settingsCaption: "在菜单栏面板中添加临时最大散热控制。",
        automatic: "自动",
        maximumCooling: "最大散热",
        fanNameFormat: "风扇%d",
        rpmFormat: "%d RPM",
        startCooling: "全速散热15分钟",
        stopCooling: "恢复自动",
        allowControl: "允许风扇控制",
        approvalCaption: "请在登录项中允许Vorssaint使用受保护的风扇控制。",
        openSettings: "打开系统设置",
        noFans: "这台Mac没有可控制的风扇。",
        unsupported: "这台Mac不支持风扇控制。",
        alreadyControlled: "另一个进程正在控制风扇。请先在那里恢复自动模式。",
        failed: "无法验证控制，风扇保持自动模式。",
        safetyCaption: "仅使用这台Mac报告的最高转速。15分钟后或连接中断时会恢复自动控制。",
        timeLimitStopped: "15分钟后已恢复自动控制。",
        safetyStopped: "控制中断，已恢复自动模式。",
        menuBarTitle: "风扇转速"
    )

    static let zhTW = FanControlFeatureStrings(
        title: "風扇控制",
        hubDescription: "暫時讓所有風扇全速運轉，然後把控制權交還給Mac",
        showInPanel: "在面板中顯示風扇控制",
        settingsCaption: "在選單列面板中加入暫時的最大散熱控制。",
        automatic: "自動",
        maximumCooling: "最大散熱",
        fanNameFormat: "風扇%d",
        rpmFormat: "%d RPM",
        startCooling: "全速散熱15分鐘",
        stopCooling: "恢復自動",
        allowControl: "允許風扇控制",
        approvalCaption: "請在登入項目中允許Vorssaint使用受保護的風扇控制。",
        openSettings: "打開系統設定",
        noFans: "這台Mac沒有可控制的風扇。",
        unsupported: "這台Mac不支援風扇控制。",
        alreadyControlled: "另一個程序正在控制風扇。請先在那裡恢復自動模式。",
        failed: "無法驗證控制，風扇維持自動模式。",
        safetyCaption: "只使用這台Mac回報的最高轉速。15分鐘後或連線中斷時會恢復自動控制。",
        timeLimitStopped: "15分鐘後已恢復自動控制。",
        safetyStopped: "控制中斷，已恢復自動模式。",
        menuBarTitle: "風扇轉速"
    )

    static let zhHK = FanControlFeatureStrings(
        title: "風扇控制",
        hubDescription: "暫時讓所有風扇全速運轉，然後把控制權交還給Mac",
        showInPanel: "在面板中顯示風扇控制",
        settingsCaption: "在選單列面板中加入暫時的最大散熱控制。",
        automatic: "自動",
        maximumCooling: "最大散熱",
        fanNameFormat: "風扇%d",
        rpmFormat: "%d RPM",
        startCooling: "全速散熱15分鐘",
        stopCooling: "恢復自動",
        allowControl: "允許風扇控制",
        approvalCaption: "請在登入項目中允許Vorssaint使用受保護的風扇控制。",
        openSettings: "打開系統設定",
        noFans: "這部Mac沒有可控制的風扇。",
        unsupported: "這部Mac不支援風扇控制。",
        alreadyControlled: "另一個程序正在控制風扇。請先在那裡恢復自動模式。",
        failed: "無法驗證控制，風扇維持自動模式。",
        safetyCaption: "只使用這部Mac回報的最高轉速。15分鐘後或連線中斷時會恢復自動控制。",
        timeLimitStopped: "15分鐘後已恢復自動控制。",
        safetyStopped: "控制中斷，已恢復自動模式。",
        menuBarTitle: "風扇轉速"
    )
}
