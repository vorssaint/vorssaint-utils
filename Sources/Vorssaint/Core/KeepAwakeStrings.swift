// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

struct KeepAwakeAutomationStrings {
    let automationSection: String
    let automationCaption: String
    let automationOff: String
    let externalDisplayToggle: String
    let externalDisplayActive: String
    let powerToggle: String
    let powerActive: String
    let runningAppsToggle: String
    let runningAppsActive: String
    let runningAppsListTitle: String
    let runningAppsAddButton: String
    let runningAppsRemoveButton: String
    let runningAppsListCaption: String
    let automationActive: String
    let pauseWhenLockedToggle: String
    let pauseWhenLockedCaption: String

    func activeStatus(for conditions: Set<KeepAwakeAutomationCondition>) -> String {
        if conditions == [.externalDisplay] { return externalDisplayActive }
        if conditions == [.power] { return powerActive }
        if conditions == [.runningApps] { return runningAppsActive }
        return automationActive
    }
}

struct KeepAwakeDisplaySleepStrings {
    let allowDisplaySleep: String
    let allowDisplaySleepCaption: String
}

extension FeatureStrings {
    static func keepAwakeAutomation(_ language: AppLanguage) -> KeepAwakeAutomationStrings {
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

    static func keepAwakeDisplaySleep(_ language: AppLanguage) -> KeepAwakeDisplaySleepStrings {
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

extension KeepAwakeDisplaySleepStrings {
    static let enUS = KeepAwakeDisplaySleepStrings(
        allowDisplaySleep: "Allow the display to sleep",
        allowDisplaySleepCaption: "Keeps the Mac awake while the display follows its normal sleep timer."
    )

    static let ptBR = KeepAwakeDisplaySleepStrings(
        allowDisplaySleep: "Permitir que a tela apague",
        allowDisplaySleepCaption: "Mantém o Mac acordado enquanto a tela segue o tempo de repouso normal."
    )

    static let tr = KeepAwakeDisplaySleepStrings(
        allowDisplaySleep: "Ekranın uyumasına izin ver",
        allowDisplaySleepCaption: "Mac uyanık kalırken ekran normal uyku süresini izler."
    )

    static let ru = KeepAwakeDisplaySleepStrings(
        allowDisplaySleep: "Разрешить дисплею выключаться",
        allowDisplaySleepCaption: "Mac остаётся активным, а дисплей выключается по обычному таймеру."
    )

    static let es = KeepAwakeDisplaySleepStrings(
        allowDisplaySleep: "Permitir que la pantalla se apague",
        allowDisplaySleepCaption: "Mantiene el Mac activo mientras la pantalla sigue su temporizador de reposo habitual."
    )

    static let de = KeepAwakeDisplaySleepStrings(
        allowDisplaySleep: "Display-Ruhezustand erlauben",
        allowDisplaySleepCaption: "Hält den Mac wach, während sich das Display nach der üblichen Zeit ausschaltet."
    )

    static let fr = KeepAwakeDisplaySleepStrings(
        allowDisplaySleep: "Autoriser l’écran à s’éteindre",
        allowDisplaySleepCaption: "Garde le Mac éveillé pendant que l’écran suit son délai d’extinction habituel."
    )

    static let it = KeepAwakeDisplaySleepStrings(
        allowDisplaySleep: "Consenti lo spegnimento dello schermo",
        allowDisplaySleepCaption: "Mantiene attivo il Mac mentre lo schermo segue il normale timer di stop."
    )

    static let ja = KeepAwakeDisplaySleepStrings(
        allowDisplaySleep: "ディスプレイのスリープを許可",
        allowDisplaySleepCaption: "Macをスリープさせず、ディスプレイは通常の時間で消灯します。"
    )

    static let ko = KeepAwakeDisplaySleepStrings(
        allowDisplaySleep: "디스플레이 잠자기 허용",
        allowDisplaySleepCaption: "Mac은 깨어 있는 상태를 유지하고 디스플레이는 평소 시간에 꺼집니다."
    )

    static let zhHans = KeepAwakeDisplaySleepStrings(
        allowDisplaySleep: "允许显示器休眠",
        allowDisplaySleepCaption: "Mac 保持唤醒，显示器仍按正常时间关闭。"
    )

    static let zhTW = KeepAwakeDisplaySleepStrings(
        allowDisplaySleep: "允許顯示器進入睡眠",
        allowDisplaySleepCaption: "Mac 保持喚醒，顯示器仍會依正常時間關閉。"
    )

    static let zhHK = KeepAwakeDisplaySleepStrings(
        allowDisplaySleep: "允許顯示器進入睡眠",
        allowDisplaySleepCaption: "Mac 保持喚醒，顯示器仍會按正常時間關閉。"
    )
}

extension KeepAwakeAutomationStrings {
    static let enUS = KeepAwakeAutomationStrings(
        automationSection: "Automation",
        automationCaption: "Starts when any selected condition is active.",
        automationOff: "Off",
        externalDisplayToggle: "External display",
        externalDisplayActive: "Active while an external display is connected",
        powerToggle: "Power",
        powerActive: "Active while connected to power",
        runningAppsToggle: "Applications",
        runningAppsActive: "Active while a selected app is running",
        runningAppsListTitle: "Selected apps",
        runningAppsAddButton: "Add an app…",
        runningAppsRemoveButton: "Remove",
        runningAppsListCaption: "Keep Awake starts while any of these apps is open, even in the background.",
        automationActive: "Active because an automatic condition is met",
        pauseWhenLockedToggle: "Pause while the Mac is locked",
        pauseWhenLockedCaption: "Follows normal sleep rules while locked and resumes the remaining session after you unlock."
    )

    static let ptBR = KeepAwakeAutomationStrings(
        automationSection: "Automação",
        automationCaption: "Inicia quando qualquer condição selecionada estiver ativa.",
        automationOff: "Desligado",
        externalDisplayToggle: "Monitor externo",
        externalDisplayActive: "Ativo enquanto há um monitor externo conectado",
        powerToggle: "Energia",
        powerActive: "Ativo enquanto está conectado à energia",
        runningAppsToggle: "Aplicativos",
        runningAppsActive: "Ativo enquanto um app selecionado estiver aberto",
        runningAppsListTitle: "Apps selecionados",
        runningAppsAddButton: "Adicionar app…",
        runningAppsRemoveButton: "Remover",
        runningAppsListCaption: "O Keep Awake inicia enquanto qualquer um destes apps estiver aberto, mesmo em segundo plano.",
        automationActive: "Ativo porque uma condição automática foi atendida",
        pauseWhenLockedToggle: "Pausar enquanto o Mac estiver bloqueado",
        pauseWhenLockedCaption: "Segue as regras normais de repouso enquanto estiver bloqueado e retoma o tempo restante após o desbloqueio."
    )

    static let tr = KeepAwakeAutomationStrings(
        automationSection: "Otomasyon",
        automationCaption: "Seçilen koşullardan biri etkinken başlar.",
        automationOff: "Kapalı",
        externalDisplayToggle: "Harici ekran",
        externalDisplayActive: "Harici ekran bağlı olduğu sürece etkin",
        powerToggle: "Güç",
        powerActive: "Güce bağlı olduğu sürece etkin",
        runningAppsToggle: "Uygulamalar",
        runningAppsActive: "Seçili bir uygulama çalışırken etkin",
        runningAppsListTitle: "Seçili uygulamalar",
        runningAppsAddButton: "Uygulama ekle…",
        runningAppsRemoveButton: "Kaldır",
        runningAppsListCaption: "Bu uygulamalardan herhangi biri açıkken (arka planda bile) Uyanık Tut başlar.",
        automationActive: "Otomatik bir koşul sağlandığı için etkin",
        pauseWhenLockedToggle: "Mac kilitliyken duraklat",
        pauseWhenLockedCaption: "Kilitliyken normal uyku kurallarını izler ve kilidi açtığınızda kalan oturumu sürdürür."
    )

    static let ru = KeepAwakeAutomationStrings(
        automationSection: "Автоматизация",
        automationCaption: "Запускается при выполнении любого выбранного условия.",
        automationOff: "Выкл.",
        externalDisplayToggle: "Внешний дисплей",
        externalDisplayActive: "Активно, пока подключён внешний дисплей",
        powerToggle: "Питание",
        powerActive: "Активно, пока подключено питание",
        runningAppsToggle: "Приложения",
        runningAppsActive: "Активно, пока запущено выбранное приложение",
        runningAppsListTitle: "Выбранные приложения",
        runningAppsAddButton: "Добавить приложение…",
        runningAppsRemoveButton: "Удалить",
        runningAppsListCaption: "Не давать Mac уснуть, пока открыто любое из этих приложений, даже в фоне.",
        automationActive: "Активно по автоматическому условию",
        pauseWhenLockedToggle: "Приостанавливать, пока Mac заблокирован",
        pauseWhenLockedCaption: "Пока Mac заблокирован, действуют обычные правила сна, а после разблокировки продолжается оставшееся время сеанса."
    )

    static let es = KeepAwakeAutomationStrings(
        automationSection: "Automatización",
        automationCaption: "Se inicia cuando se cumple cualquier condición seleccionada.",
        automationOff: "Desactivado",
        externalDisplayToggle: "Pantalla externa",
        externalDisplayActive: "Activo mientras haya una pantalla externa conectada",
        powerToggle: "Corriente",
        powerActive: "Activo mientras está conectado a la corriente",
        runningAppsToggle: "Aplicaciones",
        runningAppsActive: "Activo mientras se ejecuta una app seleccionada",
        runningAppsListTitle: "Apps seleccionadas",
        runningAppsAddButton: "Añadir app…",
        runningAppsRemoveButton: "Quitar",
        runningAppsListCaption: "Keep Awake se activa mientras cualquiera de estas apps esté abierta, incluso en segundo plano.",
        automationActive: "Activo porque se cumple una condición automática",
        pauseWhenLockedToggle: "Pausar mientras el Mac esté bloqueado",
        pauseWhenLockedCaption: "Sigue las reglas de reposo habituales mientras está bloqueado y reanuda el tiempo restante al desbloquearlo."
    )

    static let de = KeepAwakeAutomationStrings(
        automationSection: "Automatik",
        automationCaption: "Startet, wenn eine ausgewählte Bedingung erfüllt ist.",
        automationOff: "Aus",
        externalDisplayToggle: "Externes Display",
        externalDisplayActive: "Aktiv, solange ein externes Display verbunden ist",
        powerToggle: "Strom",
        powerActive: "Aktiv, solange Strom verbunden ist",
        runningAppsToggle: "Apps",
        runningAppsActive: "Aktiv, solange eine ausgewählte App läuft",
        runningAppsListTitle: "Ausgewählte Apps",
        runningAppsAddButton: "App hinzufügen…",
        runningAppsRemoveButton: "Entfernen",
        runningAppsListCaption: "Wachhalten startet, solange eine dieser Apps geöffnet ist, auch im Hintergrund.",
        automationActive: "Aktiv, weil eine automatische Bedingung erfüllt ist",
        pauseWhenLockedToggle: "Pausieren, solange der Mac gesperrt ist",
        pauseWhenLockedCaption: "Im Sperrzustand gelten die normalen Ruhezustandsregeln. Nach dem Entsperren läuft die verbleibende Sitzung weiter."
    )

    static let fr = KeepAwakeAutomationStrings(
        automationSection: "Automatisation",
        automationCaption: "Démarre lorsqu’une condition sélectionnée est remplie.",
        automationOff: "Désactivé",
        externalDisplayToggle: "Écran externe",
        externalDisplayActive: "Actif tant qu’un écran externe est connecté",
        powerToggle: "Secteur",
        powerActive: "Actif tant que le Mac est branché sur secteur",
        runningAppsToggle: "Applications",
        runningAppsActive: "Actif tant qu’une app sélectionnée est ouverte",
        runningAppsListTitle: "Apps sélectionnées",
        runningAppsAddButton: "Ajouter une app…",
        runningAppsRemoveButton: "Retirer",
        runningAppsListCaption: "Garder éveillé démarre tant que l’une de ces apps est ouverte, même en arrière-plan.",
        automationActive: "Actif car une condition automatique est remplie",
        pauseWhenLockedToggle: "Suspendre lorsque le Mac est verrouillé",
        pauseWhenLockedCaption: "Suit les règles de veille habituelles pendant le verrouillage et reprend le temps restant après le déverrouillage."
    )

    static let it = KeepAwakeAutomationStrings(
        automationSection: "Automazione",
        automationCaption: "Si avvia quando una condizione selezionata è soddisfatta.",
        automationOff: "Disattivato",
        externalDisplayToggle: "Schermo esterno",
        externalDisplayActive: "Attivo mentre è collegato uno schermo esterno",
        powerToggle: "Alimentazione",
        powerActive: "Attivo mentre è collegato all’alimentazione",
        runningAppsToggle: "App",
        runningAppsActive: "Attivo mentre un’app selezionata è in esecuzione",
        runningAppsListTitle: "App selezionate",
        runningAppsAddButton: "Aggiungi app…",
        runningAppsRemoveButton: "Rimuovi",
        runningAppsListCaption: "Mantieni attivo si avvia mentre una di queste app è aperta, anche in background.",
        automationActive: "Attivo perché una condizione automatica è soddisfatta",
        pauseWhenLockedToggle: "Metti in pausa quando il Mac è bloccato",
        pauseWhenLockedCaption: "Segue le normali regole di stop quando è bloccato e riprende il tempo rimanente dopo lo sblocco."
    )

    static let ja = KeepAwakeAutomationStrings(
        automationSection: "自動化",
        automationCaption: "選択した条件のいずれかが満たされると開始します。",
        automationOff: "オフ",
        externalDisplayToggle: "外部ディスプレイ",
        externalDisplayActive: "外部ディスプレイ接続中は有効",
        powerToggle: "電源",
        powerActive: "電源に接続されている間は有効",
        runningAppsToggle: "アプリケーション",
        runningAppsActive: "選択したアプリの実行中は有効",
        runningAppsListTitle: "選択したアプリ",
        runningAppsAddButton: "アプリを追加…",
        runningAppsRemoveButton: "削除",
        runningAppsListCaption: "これらのアプリのいずれかが開いている間（バックグラウンドでも）スリープを防ぎます。",
        automationActive: "自動条件が満たされているため有効",
        pauseWhenLockedToggle: "Macのロック中は一時停止",
        pauseWhenLockedCaption: "ロック中は通常のスリープ設定に従い、ロック解除後に残りのセッションを再開します。"
    )

    static let ko = KeepAwakeAutomationStrings(
        automationSection: "자동화",
        automationCaption: "선택한 조건 중 하나가 충족되면 시작합니다.",
        automationOff: "꺼짐",
        externalDisplayToggle: "외부 디스플레이",
        externalDisplayActive: "외부 디스플레이가 연결된 동안 활성화",
        powerToggle: "전원",
        powerActive: "전원에 연결된 동안 활성화",
        runningAppsToggle: "앱",
        runningAppsActive: "선택한 앱이 실행 중일 때 활성화",
        runningAppsListTitle: "선택한 앱",
        runningAppsAddButton: "앱 추가…",
        runningAppsRemoveButton: "제거",
        runningAppsListCaption: "이 앱 중 하나라도 열려 있으면(백그라운드 포함) 절전 방지가 시작됩니다.",
        automationActive: "자동 조건이 충족되어 활성화",
        pauseWhenLockedToggle: "Mac이 잠겨 있는 동안 일시 정지",
        pauseWhenLockedCaption: "잠겨 있는 동안 일반 잠자기 설정을 따르고 잠금 해제 후 남은 세션을 다시 시작합니다."
    )

    static let zhHans = KeepAwakeAutomationStrings(
        automationSection: "自动化",
        automationCaption: "任一所选条件满足时自动启动。",
        automationOff: "关闭",
        externalDisplayToggle: "外接显示器",
        externalDisplayActive: "外接显示器连接期间保持唤醒",
        powerToggle: "电源",
        powerActive: "连接电源期间保持唤醒",
        runningAppsToggle: "应用程序",
        runningAppsActive: "所选应用运行期间保持唤醒",
        runningAppsListTitle: "所选应用",
        runningAppsAddButton: "添加应用…",
        runningAppsRemoveButton: "移除",
        runningAppsListCaption: "只要这些应用中有任一在运行（包括后台），就会保持唤醒。",
        automationActive: "因满足自动条件而保持唤醒",
        pauseWhenLockedToggle: "Mac 锁定时暂停",
        pauseWhenLockedCaption: "锁定期间遵循正常的睡眠设置，解锁后继续剩余时段。"
    )

    static let zhTW = KeepAwakeAutomationStrings(
        automationSection: "自動化",
        automationCaption: "任一所選條件符合時自動啟動。",
        automationOff: "關閉",
        externalDisplayToggle: "外接顯示器",
        externalDisplayActive: "外接顯示器連接期間保持喚醒",
        powerToggle: "電源",
        powerActive: "連接電源期間保持喚醒",
        runningAppsToggle: "應用程式",
        runningAppsActive: "所選 App 執行期間保持喚醒",
        runningAppsListTitle: "所選 App",
        runningAppsAddButton: "新增 App…",
        runningAppsRemoveButton: "移除",
        runningAppsListCaption: "只要這些 App 中有任一正在執行（包括背景），就會保持喚醒。",
        automationActive: "因符合自動條件而保持喚醒",
        pauseWhenLockedToggle: "Mac 鎖定時暫停",
        pauseWhenLockedCaption: "鎖定期間會依照正常的睡眠設定，解鎖後繼續剩餘時段。"
    )

    static let zhHK = KeepAwakeAutomationStrings(
        automationSection: "自動化",
        automationCaption: "任何所選條件符合時自動啟動。",
        automationOff: "關閉",
        externalDisplayToggle: "外置顯示器",
        externalDisplayActive: "外置顯示器連接期間保持喚醒",
        powerToggle: "電源",
        powerActive: "連接電源期間保持喚醒",
        runningAppsToggle: "應用程式",
        runningAppsActive: "所選 App 執行期間保持喚醒",
        runningAppsListTitle: "所選 App",
        runningAppsAddButton: "新增 App…",
        runningAppsRemoveButton: "移除",
        runningAppsListCaption: "只要這些 App 中有任何一個正在執行（包括背景），就會保持喚醒。",
        automationActive: "因符合自動條件而保持喚醒",
        pauseWhenLockedToggle: "Mac 鎖定時暫停",
        pauseWhenLockedCaption: "鎖定期間會按正常睡眠設定運作，解鎖後繼續餘下時段。"
    )
}
