// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

struct PowerTimerStrings {
    let title: String
    let description: String
    let action: String
    let after: String
    let at: String
    let minutes: String
    let start: String
    let scheduled: String
    let working: String
    let note: String
    let shutdownNote: String
    let permissionError: String
    let failureError: String
    let timeError: String
    let clamshellError: String
    let permissionTitle: String
}

extension FeatureStrings {
    static func powerTimer(_ language: AppLanguage) -> PowerTimerStrings {
        switch language {
        case .enUS: return .enUS
        case .ptBR: return .ptBR
        case .ru: return .ru
        case .uk: return .uk
        case .de: return .de
        case .fr: return .fr
        case .es: return .es
        case .it: return .it
        case .sk: return .sk
        case .tr: return .tr
        case .ja: return .ja
        case .ko: return .ko
        case .zhHans: return .zhHans
        case .zhTW: return .zhTW
        case .zhHK: return .zhHK
        }
    }
}

extension PowerTimerStrings {
    static let enUS = PowerTimerStrings(
        title: "Sleep and shutdown timer",
        description: "Put the Mac to sleep or shut it down after a duration or at a chosen time.",
        action: "Action",
        after: "After",
        at: "At",
        minutes: "Minutes",
        start: "Start timer",
        scheduled: "Scheduled for",
        working: "Working…",
        note: "Keeps the Mac awake until the timer ends. Sleeping the Mac, quitting Vorssaint or uninstalling this feature cancels the timer.",
        shutdownNote: "Shut down closes your apps. Unsaved work can prevent shutdown.",
        permissionError: "Allow Vorssaint to control System Events in System Settings → Privacy & Security → Automation, then try again.",
        failureError: "The power action could not finish. Check your power settings and try again.",
        timeError: "Choose a future time within 24 hours, or a duration from 1 to 1440 minutes.",
        clamshellError: "Turn off Keep Awake with the lid closed before starting this timer.",
        permissionTitle: "Automation: System Events"
    )

    static let ptBR = PowerTimerStrings(
        title: "Timer de repouso e desligamento",
        description: "Coloque o Mac em repouso ou desligue após um intervalo ou em um horário escolhido.",
        action: "Ação",
        after: "Após",
        at: "Às",
        minutes: "Minutos",
        start: "Iniciar timer",
        scheduled: "Agendado para",
        working: "Processando…",
        note: "Mantém o Mac acordado até o fim do timer. Colocar o Mac em repouso, sair do Vorssaint ou desinstalar este recurso cancela o timer.",
        shutdownNote: "Desligar fecha seus apps. Trabalho não salvo pode impedir o desligamento.",
        permissionError: "Permita que o Vorssaint controle o System Events em Ajustes do Sistema → Privacidade e Segurança → Automação e tente novamente.",
        failureError: "A ação de energia não pôde ser concluída. Confira os ajustes de energia e tente novamente.",
        timeError: "Escolha um horário futuro nas próximas 24 horas ou uma duração de 1 a 1440 minutos.",
        clamshellError: "Desative Manter acordado com a tampa fechada antes de iniciar este timer.",
        permissionTitle: "Automação: System Events"
    )

    static let ru = PowerTimerStrings(
        title: "Таймер сна и выключения",
        description: "Переведите Mac в сон или выключите через заданный интервал или в выбранное время.",
        action: "Действие",
        after: "Через",
        at: "В",
        minutes: "Минуты",
        start: "Запустить таймер",
        scheduled: "Запланировано на",
        working: "Выполняется…",
        note: "Не даёт Mac уснуть до конца таймера. Сон Mac, выход из Vorssaint или удаление этой функции отменяет таймер.",
        shutdownNote: "Выключение закрывает приложения. Несохранённая работа может помешать выключению.",
        permissionError: "Разрешите Vorssaint управлять System Events: Системные настройки → Конфиденциальность и безопасность → Автоматизация. Затем повторите попытку.",
        failureError: "Не удалось выполнить действие. Проверьте настройки питания и повторите попытку.",
        timeError: "Выберите время в ближайшие 24 часа или интервал от 1 до 1440 минут.",
        clamshellError: "Отключите режим бодрствования с закрытой крышкой перед запуском таймера.",
        permissionTitle: "Автоматизация: System Events"
    )

    static let uk = PowerTimerStrings(
        title: "Таймер сну та вимкнення",
        description: "Переведіть Mac у сон або вимкніть через заданий інтервал чи у вибраний час.",
        action: "Дія",
        after: "Через",
        at: "О",
        minutes: "Хвилини",
        start: "Запустити таймер",
        scheduled: "Заплановано на",
        working: "Виконується…",
        note: "Не дає Mac заснути до завершення таймера. Сон Mac, вихід із Vorssaint або видалення цієї функції скасовує таймер.",
        shutdownNote: "Вимкнення закриває програми. Незбережена робота може завадити вимкненню.",
        permissionError: "Дозвольте Vorssaint керувати System Events: Системні параметри → Приватність і безпека → Автоматизація. Потім спробуйте знову.",
        failureError: "Не вдалося виконати дію. Перевірте параметри живлення та спробуйте знову.",
        timeError: "Виберіть час у найближчі 24 години або інтервал від 1 до 1440 хвилин.",
        clamshellError: "Вимкніть режим роботи із закритою кришкою перед запуском таймера.",
        permissionTitle: "Автоматизація: System Events"
    )

    static let de = PowerTimerStrings(
        title: "Ruhezustands- und Ausschalt-Timer",
        description: "Versetze den Mac nach einer Dauer oder zu einer gewählten Zeit in den Ruhezustand oder schalte ihn aus.",
        action: "Aktion",
        after: "Nach",
        at: "Um",
        minutes: "Minuten",
        start: "Timer starten",
        scheduled: "Geplant für",
        working: "Wird ausgeführt…",
        note: "Hält den Mac bis zum Timerende wach. Ruhezustand, Beenden von Vorssaint oder Deinstallieren dieser Funktion bricht den Timer ab.",
        shutdownNote: "Ausschalten schließt deine Apps. Ungesicherte Arbeit kann das Ausschalten verhindern.",
        permissionError: "Erlaube Vorssaint unter Systemeinstellungen → Datenschutz & Sicherheit → Automation die Steuerung von System Events und versuche es erneut.",
        failureError: "Die Energieaktion konnte nicht abgeschlossen werden. Prüfe die Energieeinstellungen und versuche es erneut.",
        timeError: "Wähle eine Zeit in den nächsten 24 Stunden oder eine Dauer von 1 bis 1440 Minuten.",
        clamshellError: "Deaktiviere Wachbleiben bei geschlossenem Deckel, bevor du diesen Timer startest.",
        permissionTitle: "Automation: System Events"
    )

    static let fr = PowerTimerStrings(
        title: "Minuteur de veille et d’extinction",
        description: "Mettez le Mac en veille ou éteignez-le après une durée ou à une heure choisie.",
        action: "Action",
        after: "Après",
        at: "À",
        minutes: "Minutes",
        start: "Démarrer le minuteur",
        scheduled: "Prévu pour",
        working: "En cours…",
        note: "Maintient le Mac éveillé jusqu’à la fin du minuteur. La mise en veille, la fermeture de Vorssaint ou la désinstallation de cette fonction annule le minuteur.",
        shutdownNote: "L’extinction ferme vos apps. Le travail non enregistré peut empêcher l’extinction.",
        permissionError: "Autorisez Vorssaint à contrôler System Events dans Réglages Système → Confidentialité et sécurité → Automatisation, puis réessayez.",
        failureError: "L’action d’alimentation n’a pas pu aboutir. Vérifiez vos réglages d’alimentation et réessayez.",
        timeError: "Choisissez une heure dans les prochaines 24 heures ou une durée de 1 à 1440 minutes.",
        clamshellError: "Désactivez le maintien éveillé avec le couvercle fermé avant de lancer ce minuteur.",
        permissionTitle: "Automatisation\u{00A0}: System Events"
    )

    static let es = PowerTimerStrings(
        title: "Temporizador de reposo y apagado",
        description: "Pon el Mac en reposo o apágalo tras un intervalo o a una hora elegida.",
        action: "Acción",
        after: "Después de",
        at: "A las",
        minutes: "Minutos",
        start: "Iniciar temporizador",
        scheduled: "Programado para",
        working: "En curso…",
        note: "Mantiene el Mac despierto hasta el fin del temporizador. El reposo del Mac, cerrar Vorssaint o desinstalar esta función cancela el temporizador.",
        shutdownNote: "Apagar cierra tus apps. El trabajo sin guardar puede impedir el apagado.",
        permissionError: "Permite que Vorssaint controle System Events en Ajustes del Sistema → Privacidad y seguridad → Automatización y vuelve a intentarlo.",
        failureError: "No se pudo completar la acción de energía. Comprueba los ajustes de energía y vuelve a intentarlo.",
        timeError: "Elige una hora en las próximas 24 horas o una duración de 1 a 1440 minutos.",
        clamshellError: "Desactiva Mantener despierto con la tapa cerrada antes de iniciar este temporizador.",
        permissionTitle: "Automatización: System Events"
    )

    static let it = PowerTimerStrings(
        title: "Timer di stop e spegnimento",
        description: "Metti il Mac in stop o spegnilo dopo un intervallo o a un’ora scelta.",
        action: "Azione",
        after: "Dopo",
        at: "Alle",
        minutes: "Minuti",
        start: "Avvia timer",
        scheduled: "Programmato per",
        working: "In corso…",
        note: "Mantiene il Mac attivo fino alla fine del timer. Lo stop del Mac, l’uscita da Vorssaint o la disinstallazione di questa funzione annulla il timer.",
        shutdownNote: "Lo spegnimento chiude le app. Il lavoro non salvato può impedirlo.",
        permissionError: "Consenti a Vorssaint di controllare System Events in Impostazioni di Sistema → Privacy e sicurezza → Automazione, poi riprova.",
        failureError: "L’azione di alimentazione non è riuscita. Controlla le impostazioni di alimentazione e riprova.",
        timeError: "Scegli un’ora nelle prossime 24 ore o una durata da 1 a 1440 minuti.",
        clamshellError: "Disattiva il mantenimento attivo con il coperchio chiuso prima di avviare il timer.",
        permissionTitle: "Automazione: System Events"
    )

    static let sk = PowerTimerStrings(
        title: "Časovač spánku a vypnutia",
        description: "Uspite alebo vypnite Mac po zvolenom intervale alebo v určenom čase.",
        action: "Akcia",
        after: "Po",
        at: "O",
        minutes: "Minúty",
        start: "Spustiť časovač",
        scheduled: "Naplánované na",
        working: "Prebieha…",
        note: "Udržuje Mac bdelý do konca časovača. Spánok Macu, ukončenie Vorssaint alebo odinštalovanie tejto funkcie zruší časovač.",
        shutdownNote: "Vypnutie zatvorí aplikácie. Neuložená práca môže zabrániť vypnutiu.",
        permissionError: "Povoľte Vorssaint ovládať System Events v Systémové nastavenia → Súkromie a bezpečnosť → Automatizácia a skúste znova.",
        failureError: "Akciu napájania sa nepodarilo dokončiť. Skontrolujte nastavenia napájania a skúste znova.",
        timeError: "Zvoľte čas v nasledujúcich 24 hodinách alebo interval od 1 do 1440 minút.",
        clamshellError: "Pred spustením časovača vypnite udržiavanie bdelosti so zatvoreným vekom.",
        permissionTitle: "Automatizácia: System Events"
    )

    static let tr = PowerTimerStrings(
        title: "Uyku ve kapatma zamanlayıcısı",
        description: "Mac’i bir süre sonra veya seçtiğiniz saatte uyutun ya da kapatın.",
        action: "İşlem",
        after: "Sonra",
        at: "Saat",
        minutes: "Dakika",
        start: "Zamanlayıcıyı başlat",
        scheduled: "Planlanan saat",
        working: "İşleniyor…",
        note: "Zamanlayıcı bitene kadar Mac’i uyanık tutar. Mac’i uyutmak, Vorssaint’ten çıkmak veya bu özelliği kaldırmak zamanlayıcıyı iptal eder.",
        shutdownNote: "Kapatma uygulamalarınızı kapatır. Kaydedilmemiş çalışmalar kapatmayı engelleyebilir.",
        permissionError: "Sistem Ayarları → Gizlilik ve Güvenlik → Otomasyon bölümünde Vorssaint’in System Events’i kontrol etmesine izin verip yeniden deneyin.",
        failureError: "Güç işlemi tamamlanamadı. Güç ayarlarınızı kontrol edip yeniden deneyin.",
        timeError: "Önümüzdeki 24 saat içinde bir saat veya 1 ile 1440 dakika arasında bir süre seçin.",
        clamshellError: "Bu zamanlayıcıyı başlatmadan önce kapak kapalıyken uyanık tutmayı kapatın.",
        permissionTitle: "Otomasyon: System Events"
    )

    static let ja = PowerTimerStrings(
        title: "スリープ・システム終了タイマー",
        description: "指定した時間後、または指定した時刻にMacをスリープさせるかシステム終了します。",
        action: "操作",
        after: "時間後",
        at: "時刻",
        minutes: "分",
        start: "タイマーを開始",
        scheduled: "予定時刻",
        working: "処理中…",
        note: "タイマー終了までMacを起動状態に保ちます。Macのスリープ、Vorssaintの終了、この機能のアンインストールでタイマーはキャンセルされます。",
        shutdownNote: "システム終了するとアプリが閉じます。未保存の作業により終了が中止される場合があります。",
        permissionError: "システム設定 → プライバシーとセキュリティ → オートメーションでVorssaintによるSystem Eventsの制御を許可し、再試行してください。",
        failureError: "電源操作を完了できませんでした。電源設定を確認して再試行してください。",
        timeError: "24時間以内の未来の時刻、または1〜1440分の時間を選んでください。",
        clamshellError: "タイマーを開始する前に、ふたを閉じた状態での起動維持をオフにしてください。",
        permissionTitle: "オートメーション：System Events"
    )

    static let ko = PowerTimerStrings(
        title: "잠자기 및 종료 타이머",
        description: "지정한 시간이 지난 후 또는 선택한 시각에 Mac을 잠자기로 전환하거나 종료합니다.",
        action: "동작",
        after: "시간 후",
        at: "시각",
        minutes: "분",
        start: "타이머 시작",
        scheduled: "예약 시각",
        working: "처리 중…",
        note: "타이머가 끝날 때까지 Mac을 깨어 있게 합니다. Mac 잠자기, Vorssaint 종료 또는 이 기능 제거 시 타이머가 취소됩니다.",
        shutdownNote: "종료하면 앱이 닫힙니다. 저장하지 않은 작업으로 인해 종료가 중단될 수 있습니다.",
        permissionError: "시스템 설정 → 개인정보 보호 및 보안 → 자동화에서 Vorssaint의 System Events 제어를 허용한 후 다시 시도하세요.",
        failureError: "전원 동작을 완료하지 못했습니다. 전원 설정을 확인하고 다시 시도하세요.",
        timeError: "24시간 이내의 미래 시각 또는 1~1440분의 시간을 선택하세요.",
        clamshellError: "타이머를 시작하기 전에 덮개를 닫은 상태에서 깨어 있기를 끄세요.",
        permissionTitle: "자동화: System Events"
    )

    static let zhHans = PowerTimerStrings(
        title: "睡眠与关机定时器",
        description: "在指定时长后或指定时间让 Mac 睡眠或关机。",
        action: "操作",
        after: "时长",
        at: "时间",
        minutes: "分钟",
        start: "开始定时器",
        scheduled: "计划时间",
        working: "处理中…",
        note: "让 Mac 保持唤醒直到定时器结束。让 Mac 睡眠、退出 Vorssaint 或卸载此功能都会取消定时器。",
        shutdownNote: "关机会关闭应用。未保存的工作可能阻止关机。",
        permissionError: "请在系统设置 → 隐私与安全性 → 自动化中允许 Vorssaint 控制 System Events，然后重试。",
        failureError: "无法完成电源操作。请检查电源设置后重试。",
        timeError: "请选择未来 24 小时内的时间，或 1 至 1440 分钟的时长。",
        clamshellError: "开始定时器前，请关闭合盖保持唤醒模式。",
        permissionTitle: "自动化：System Events"
    )

    static let zhTW = PowerTimerStrings(
        title: "睡眠與關機計時器",
        description: "在指定時長後或指定時間讓 Mac 睡眠或關機。",
        action: "操作",
        after: "時長",
        at: "時間",
        minutes: "分鐘",
        start: "開始計時器",
        scheduled: "預定時間",
        working: "處理中…",
        note: "讓 Mac 保持喚醒直到計時器結束。讓 Mac 睡眠、結束 Vorssaint 或解除安裝此功能都會取消計時器。",
        shutdownNote: "關機會關閉 App。未儲存的工作可能阻止關機。",
        permissionError: "請在系統設定 → 隱私權與安全性 → 自動化中允許 Vorssaint 控制 System Events，然後再試一次。",
        failureError: "無法完成電源操作。請檢查電源設定後再試一次。",
        timeError: "請選擇未來 24 小時內的時間，或 1 至 1440 分鐘的時長。",
        clamshellError: "開始計時器前，請關閉闔蓋保持喚醒模式。",
        permissionTitle: "自動化：System Events"
    )

    static let zhHK = PowerTimerStrings(
        title: "睡眠與關機計時器",
        description: "在指定時長後或指定時間讓 Mac 睡眠或關機。",
        action: "操作",
        after: "時長",
        at: "時間",
        minutes: "分鐘",
        start: "開始計時器",
        scheduled: "預定時間",
        working: "處理中…",
        note: "讓 Mac 保持喚醒直到計時器結束。讓 Mac 睡眠、結束 Vorssaint 或解除安裝此功能都會取消計時器。",
        shutdownNote: "關機會關閉 App。未儲存的工作可能阻止關機。",
        permissionError: "請在系統設定 → 私隱與保安 → 自動化中允許 Vorssaint 控制 System Events，然後再試一次。",
        failureError: "無法完成電源操作。請檢查電源設定後再試一次。",
        timeError: "請選擇未來 24 小時內的時間，或 1 至 1440 分鐘的時長。",
        clamshellError: "開始計時器前，請關閉闔蓋保持喚醒模式。",
        permissionTitle: "自動化：System Events"
    )

}
