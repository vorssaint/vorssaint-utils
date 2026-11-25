// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

// MARK: - PomodoroFeatureStrings

struct PomodoroFeatureStrings {
    let title: String
    let hubDescription: String
    let enable: String
    let enableCaption: String
    let focusDuration: String
    let shortBreakDuration: String
    let longBreakDuration: String
    let longBreakInterval: String
    let autoStartBreaks: String
    let autoStartFocus: String
    let soundAlerts: String
    let showInMenuBar: String
    let shortcut: String
    let start: String
    let pause: String
    let resume: String
    let skip: String
    let reset: String
    let focusPhase: String
    let shortBreakPhase: String
    let longBreakPhase: String
    let completedCycles: String
    let notificationFocusFinishedTitle: String
    let notificationFocusFinishedBody: String
    let notificationBreakFinishedTitle: String
    let notificationBreakFinishedBody: String
}

// MARK: - FeatureStrings Extension

extension FeatureStrings {

    static func pomodoro(_ language: AppLanguage) -> PomodoroFeatureStrings {
        switch language {
        case .enUS:
            return PomodoroFeatureStrings(
                title: "Pomodoro Timer",
                hubDescription: "Stay focused with the Pomodoro technique. Work in focused intervals, take regular breaks, and maintain productivity throughout the day.",
                enable: "Enable Pomodoro",
                enableCaption: "Activate the Pomodoro timer to manage your focus and breaks",
                focusDuration: "Focus Duration",
                shortBreakDuration: "Short Break Duration",
                longBreakDuration: "Long Break Duration",
                longBreakInterval: "Long Break Interval",
                autoStartBreaks: "Auto-start Breaks",
                autoStartFocus: "Auto-start Focus Sessions",
                soundAlerts: "Sound Alerts",
                showInMenuBar: "Show in Menu Bar",
                shortcut: "Shortcut",
                start: "Start",
                pause: "Pause",
                resume: "Resume",
                skip: "Skip",
                reset: "Reset",
                focusPhase: "Focus",
                shortBreakPhase: "Short Break",
                longBreakPhase: "Long Break",
                completedCycles: "Completed Cycles",
                notificationFocusFinishedTitle: "Focus Session Complete",
                notificationFocusFinishedBody: "Your focus session is done. Time for a break!",
                notificationBreakFinishedTitle: "Break Over",
                notificationBreakFinishedBody: "Your break is over. Ready to focus again?"
            )

        case .ptBR:
            return PomodoroFeatureStrings(
                title: "Cronômetro Pomodoro",
                hubDescription: "Mantenha o foco com a técnica Pomodoro. Trabalhe em intervalos concentrados, faça pausas regulares e mantenha a produtividade ao longo do dia.",
                enable: "Ativar Pomodoro",
                enableCaption: "Ative o cronômetro Pomodoro para gerenciar seu foco e pausas",
                focusDuration: "Duração do Foco",
                shortBreakDuration: "Duração da Pausa Curta",
                longBreakDuration: "Duração da Pausa Longa",
                longBreakInterval: "Intervalo da Pausa Longa",
                autoStartBreaks: "Iniciar Pausas Automaticamente",
                autoStartFocus: "Iniciar Sessões de Foco Automaticamente",
                soundAlerts: "Alertas Sonoros",
                showInMenuBar: "Mostrar na Barra de Menu",
                shortcut: "Atalho",
                start: "Iniciar",
                pause: "Pausar",
                resume: "Retomar",
                skip: "Pular",
                reset: "Reiniciar",
                focusPhase: "Foco",
                shortBreakPhase: "Pausa Curta",
                longBreakPhase: "Pausa Longa",
                completedCycles: "Ciclos Concluídos",
                notificationFocusFinishedTitle: "Sessão de Foco Concluída",
                notificationFocusFinishedBody: "Sua sessão de foco terminou. Hora de uma pausa!",
                notificationBreakFinishedTitle: "Pausa Encerrada",
                notificationBreakFinishedBody: "Sua pausa terminou. Pronto para focar novamente?"
            )

        case .tr:
            return PomodoroFeatureStrings(
                title: "Pomodoro Zamanlayıcı",
                hubDescription: "Pomodoro tekniğiyle odaklanın. Odaklanmış aralıklarda çalışın, düzenli mola verin ve gün boyunca üretkenliğinizi koruyun.",
                enable: "Pomodoro’yu Etkinleştir",
                enableCaption: "Odaklanma ve molalarınızı yönetmek için Pomodoro zamanlayıcısını etkinleştirin",
                focusDuration: "Odak Süresi",
                shortBreakDuration: "Kısa Mola Süresi",
                longBreakDuration: "Uzun Mola Süresi",
                longBreakInterval: "Uzun Mola Aralığı",
                autoStartBreaks: "Molaları Otomatik Başlat",
                autoStartFocus: "Odak Oturumlarını Otomatik Başlat",
                soundAlerts: "Sesli Uyarılar",
                showInMenuBar: "Menü Çubuğunda Göster",
                shortcut: "Kısayol",
                start: "Başlat",
                pause: "Duraklat",
                resume: "Devam Et",
                skip: "Atla",
                reset: "Sıfırla",
                focusPhase: "Odak",
                shortBreakPhase: "Kısa Mola",
                longBreakPhase: "Uzun Mola",
                completedCycles: "Tamamlanan Döngüler",
                notificationFocusFinishedTitle: "Odak Oturumu Tamamlandı",
                notificationFocusFinishedBody: "Odak oturumunuz bitti. Mola zamanı!",
                notificationBreakFinishedTitle: "Mola Bitti",
                notificationBreakFinishedBody: "Molanız bitti. Tekrar odaklanmaya hazır mısınız?"
            )

        case .ru:
            return PomodoroFeatureStrings(
                title: "Таймер Помодоро",
                hubDescription: "Сохраняйте концентрацию с помощью техники Помодоро. Работайте в сфокусированных интервалах, делайте регулярные перерывы и поддерживайте продуктивность в течение дня.",
                enable: "Включить Помодоро",
                enableCaption: "Активируйте таймер Помодоро для управления фокусом и перерывами",
                focusDuration: "Длительность фокуса",
                shortBreakDuration: "Длительность короткого перерыва",
                longBreakDuration: "Длительность длинного перерыва",
                longBreakInterval: "Интервал длинного перерыва",
                autoStartBreaks: "Автоматический запуск перерывов",
                autoStartFocus: "Автоматический запуск сессий фокуса",
                soundAlerts: "Звуковые оповещения",
                showInMenuBar: "Показывать в строке меню",
                shortcut: "Горячая клавиша",
                start: "Начать",
                pause: "Пауза",
                resume: "Продолжить",
                skip: "Пропустить",
                reset: "Сбросить",
                focusPhase: "Фокус",
                shortBreakPhase: "Короткий перерыв",
                longBreakPhase: "Длинный перерыв",
                completedCycles: "Завершённые циклы",
                notificationFocusFinishedTitle: "Сессия фокуса завершена",
                notificationFocusFinishedBody: "Ваша сессия фокуса окончена. Время для перерыва!",
                notificationBreakFinishedTitle: "Перерыв окончен",
                notificationBreakFinishedBody: "Ваш перерыв закончился. Готовы снова сосредоточиться?"
            )

        case .es:
            return PomodoroFeatureStrings(
                title: "Temporizador Pomodoro",
                hubDescription: "Mantén el enfoque con la técnica Pomodoro. Trabaja en intervalos concentrados, toma descansos regulares y mantén la productividad a lo largo del día.",
                enable: "Activar Pomodoro",
                enableCaption: "Activa el temporizador Pomodoro para gestionar tu enfoque y descansos",
                focusDuration: "Duración del enfoque",
                shortBreakDuration: "Duración del descanso corto",
                longBreakDuration: "Duración del descanso largo",
                longBreakInterval: "Intervalo del descanso largo",
                autoStartBreaks: "Iniciar descansos automáticamente",
                autoStartFocus: "Iniciar sesiones de enfoque automáticamente",
                soundAlerts: "Alertas sonoras",
                showInMenuBar: "Mostrar en la barra de menú",
                shortcut: "Atajo",
                start: "Iniciar",
                pause: "Pausar",
                resume: "Reanudar",
                skip: "Omitir",
                reset: "Reiniciar",
                focusPhase: "Enfoque",
                shortBreakPhase: "Descanso corto",
                longBreakPhase: "Descanso largo",
                completedCycles: "Ciclos completados",
                notificationFocusFinishedTitle: "Sesión de enfoque completada",
                notificationFocusFinishedBody: "Tu sesión de enfoque ha terminado. ¡Hora de descansar!",
                notificationBreakFinishedTitle: "Descanso finalizado",
                notificationBreakFinishedBody: "Tu descanso ha terminado. ¿Listo para concentrarte de nuevo?"
            )

        case .sk:
            return PomodoroFeatureStrings(
                title: "Časovač Pomodoro",
                hubDescription: "Zostaňte sústredení pomocou techniky Pomodoro. Pracujte v sústredených intervaloch, robte pravidelné prestávky a udržujte si produktívnosť počas dňa.",
                enable: "Povoliť Pomodoro",
                enableCaption: "Aktivujte časovač Pomodoro na správu sústredenia a prestávok",
                focusDuration: "Dĺžka sústredenia",
                shortBreakDuration: "Dĺžka krátkej prestávky",
                longBreakDuration: "Dĺžka dlhej prestávky",
                longBreakInterval: "Interval dlhej prestávky",
                autoStartBreaks: "Automatické spustenie prestávok",
                autoStartFocus: "Automatické spustenie sústredenia",
                soundAlerts: "Zvukové upozornenia",
                showInMenuBar: "Zobraziť v paneli s menu",
                shortcut: "Klávesová skratka",
                start: "Štart",
                pause: "Pauza",
                resume: "Pokračovať",
                skip: "Preskočiť",
                reset: "Obnoviť",
                focusPhase: "Sústreďovanie",
                shortBreakPhase: "Krátka prestávka",
                longBreakPhase: "Dlhá prestávka",
                completedCycles: "Dokončené cykly",
                notificationFocusFinishedTitle: "Sústreďovanie dokončené",
                notificationFocusFinishedBody: "Vaše sústreďovanie sa skončilo. Čas na prestávku!",
                notificationBreakFinishedTitle: "Prestávka skončená",
                notificationBreakFinishedBody: "Vaša prestávka sa skončila. Ste pripravení sústrediť sa znova?"
            )

        case .de:
            return PomodoroFeatureStrings(
                title: "Pomodoro-Timer",
                hubDescription: "Bleiben Sie mit der Pomodoro-Technik fokussiert. Arbeiten Sie in konzentrierten Intervallen, machen Sie regelmäßige Pausen und halten Sie Ihre Produktivität den ganzen Tag aufrecht.",
                enable: "Pomodoro aktivieren",
                enableCaption: "Aktivieren Sie den Pomodoro-Timer, um Fokus und Pausen zu verwalten",
                focusDuration: "Fokussdauer",
                shortBreakDuration: "Dauer der kurzen Pause",
                longBreakDuration: "Dauer der langen Pause",
                longBreakInterval: "Intervall der langen Pause",
                autoStartBreaks: "Pausen automatisch starten",
                autoStartFocus: "Fokus-Sitzungen automatisch starten",
                soundAlerts: "Tonalerne",
                showInMenuBar: "In der Menüleiste anzeigen",
                shortcut: "Tastenkürzel",
                start: "Starten",
                pause: "Pause",
                resume: "Fortsetzen",
                skip: "Überspringen",
                reset: "Zurücksetzen",
                focusPhase: "Fokus",
                shortBreakPhase: "Kurze Pause",
                longBreakPhase: "Lange Pause",
                completedCycles: "Abgeschlossene Zyklen",
                notificationFocusFinishedTitle: "Fokus-Sitzung abgeschlossen",
                notificationFocusFinishedBody: "Ihre Fokus-Sitzung ist beendet. Zeit für eine Pause!",
                notificationBreakFinishedTitle: "Pause beendet",
                notificationBreakFinishedBody: "Ihre Pause ist vorbei. Bereit, sich wieder zu konzentrieren?"
            )

        case .fr:
            return PomodoroFeatureStrings(
                title: "Minuteur Pomodoro",
                hubDescription: "Restez concentré grâce à la technique Pomodoro. Travaillez par intervalles concentrés, prenez des pauses régulières et maintenez votre productivité tout au long de la journée.",
                enable: "Activer Pomodoro",
                enableCaption: "Activez le minuteur Pomodoro pour gérer votre concentration et vos pauses",
                focusDuration: "Durée de concentration",
                shortBreakDuration: "Durée de la pause courte",
                longBreakDuration: "Durée de la pause longue",
                longBreakInterval: "Intervalle de la pause longue",
                autoStartBreaks: "Démarrer les pauses automatiquement",
                autoStartFocus: "Démarrer les sessions de concentration automatiquement",
                soundAlerts: "Alertes sonores",
                showInMenuBar: "Afficher dans la barre de menu",
                shortcut: "Raccourci",
                start: "Démarrer",
                pause: "Pause",
                resume: "Reprendre",
                skip: "Passer",
                reset: "Réinitialiser",
                focusPhase: "Concentration",
                shortBreakPhase: "Pause courte",
                longBreakPhase: "Pause longue",
                completedCycles: "Cycles terminés",
                notificationFocusFinishedTitle: "Session de concentration terminée",
                notificationFocusFinishedBody: "Votre session de concentration est terminée. C’est l’heure d’une pause !",
                notificationBreakFinishedTitle: "Pause terminée",
                notificationBreakFinishedBody: "Votre pause est terminée. Prêt à vous concentrer à nouveau ?"
            )

        case .it:
            return PomodoroFeatureStrings(
                title: "Timer Pomodoro",
                hubDescription: "Mantieni la concentrazione con la tecnica Pomodoro. Lavora a intervalli concentrati, fai pause regolari e mantieni la produttività durante tutta la giornata.",
                enable: "Attiva Pomodoro",
                enableCaption: "Attiva il timer Pomodoro per gestire concentrazione e pause",
                focusDuration: "Durata della concentrazione",
                shortBreakDuration: "Durata della pausa breve",
                longBreakDuration: "Durata della pausa lunga",
                longBreakInterval: "Intervallo della pausa lunga",
                autoStartBreaks: "Avvia automaticamente le pause",
                autoStartFocus: "Avvia automaticamente le sessioni di concentrazione",
                soundAlerts: "Avvisi sonori",
                showInMenuBar: "Mostra nella barra del menu",
                shortcut: "Scorciatoia",
                start: "Avvia",
                pause: "Pausa",
                resume: "Riprendi",
                skip: "Salta",
                reset: "Reimposta",
                focusPhase: "Concentrazione",
                shortBreakPhase: "Pausa breve",
                longBreakPhase: "Pausa lunga",
                completedCycles: "Cicli completati",
                notificationFocusFinishedTitle: "Sessione di concentrazione completata",
                notificationFocusFinishedBody: "La tua sessione di concentrazione è finita. Ora di fare una pausa!",
                notificationBreakFinishedTitle: "Pausa terminata",
                notificationBreakFinishedBody: "La tua pausa è finita. Pronto a concentrarti di nuovo?"
            )

        case .ja:
            return PomodoroFeatureStrings(
                title: "ポモドーロタイマー",
                hubDescription: "ポモドーロテクニックで集中力を保ちましょう。集中した区間で作業し、定期的に休憩を取り、一日中生産性を維持します。",
                enable: "ポモドーロを有効にする",
                enableCaption: "集中と休憩を管理するためにポモドーロタイマーを有効にします",
                focusDuration: "集中時間",
                shortBreakDuration: "短い休憩の時間",
                longBreakDuration: "長い休憩の時間",
                longBreakInterval: "長い休憩の間隔",
                autoStartBreaks: "休憩を自動開始",
                autoStartFocus: "集中セッションを自動開始",
                soundAlerts: "サウンドアラート",
                showInMenuBar: "メニューバーに表示",
                shortcut: "ショートカット",
                start: "開始",
                pause: "一時停止",
                resume: "再開",
                skip: "スキップ",
                reset: "リセット",
                focusPhase: "集中",
                shortBreakPhase: "短い休憩",
                longBreakPhase: "長い休憩",
                completedCycles: "完了したサイクル",
                notificationFocusFinishedTitle: "集中セッション完了",
                notificationFocusFinishedBody: "集中セッションが終了しました。休憩の時間です！",
                notificationBreakFinishedTitle: "休憩終了",
                notificationBreakFinishedBody: "休憩が終了しました。もう一度集中する準備はできましたか？"
            )

        case .ko:
            return PomodoroFeatureStrings(
                title: "포모도로 타이머",
                hubDescription: "포모도로 기법으로 집중력을 유지하세요. 집중된 간격으로 작업하고, 규칙적인 휴식을 취하며, 하루 종일 생산성을 유지하세요.",
                enable: "포모도로 활성화",
                enableCaption: "집중과 휴식을 관리하려면 포모도로 타이머를 활성화하세요",
                focusDuration: "집중 시간",
                shortBreakDuration: "짧은 휴식 시간",
                longBreakDuration: "긴 휴식 시간",
                longBreakInterval: "긴 휴식 간격",
                autoStartBreaks: "휴식 자동 시작",
                autoStartFocus: "집중 세션 자동 시작",
                soundAlerts: "소리 알림",
                showInMenuBar: "메뉴 바에 표시",
                shortcut: "단축키",
                start: "시작",
                pause: "일시정지",
                resume: "재개",
                skip: "건너뛰기",
                reset: "초기화",
                focusPhase: "집중",
                shortBreakPhase: "짧은 휴식",
                longBreakPhase: "긴 휴식",
                completedCycles: "완료된 사이클",
                notificationFocusFinishedTitle: "집중 세션 완료",
                notificationFocusFinishedBody: "집중 세션이 끝났습니다. 휴식할 시간입니다!",
                notificationBreakFinishedTitle: "휴식 종료",
                notificationBreakFinishedBody: "휴식이 끝났습니다. 다시 집중할 준비가 되셨나요?"
            )

        case .zhHans:
            return PomodoroFeatureStrings(
                title: "番茄钟",
                hubDescription: "使用番茄工作法保持专注。在集中的时间间隔内工作，定期休息，全天保持生产力。",
                enable: "启用番茄钟",
                enableCaption: "启用番茄钟以管理您的专注和休息",
                focusDuration: "专注时长",
                shortBreakDuration: "短休息时长",
                longBreakDuration: "长休息时长",
                longBreakInterval: "长休息间隔",
                autoStartBreaks: "自动开始休息",
                autoStartFocus: "自动开始专注",
                soundAlerts: "声音提醒",
                showInMenuBar: "显示在菜单栏",
                shortcut: "快捷键",
                start: "开始",
                pause: "暂停",
                resume: "继续",
                skip: "跳过",
                reset: "重置",
                focusPhase: "专注",
                shortBreakPhase: "短休息",
                longBreakPhase: "长休息",
                completedCycles: "已完成周期",
                notificationFocusFinishedTitle: "专注完成",
                notificationFocusFinishedBody: "您的专注时间结束了，该休息了！",
                notificationBreakFinishedTitle: "休息结束",
                notificationBreakFinishedBody: "您的休息时间结束了，准备好再次专注了吗？"
            )

        case .zhTW:
            return PomodoroFeatureStrings(
                title: "番茄鐘",
                hubDescription: "使用番茄工作法保持專注。在集中的時間間隔內工作，定期休息，全天保持生產力。",
                enable: "啟用番茄鐘",
                enableCaption: "啟用番茄鐘以管理您的專注與休息",
                focusDuration: "專注時長",
                shortBreakDuration: "短休息時長",
                longBreakDuration: "長休息時長",
                longBreakInterval: "長休息間隔",
                autoStartBreaks: "自動開始休息",
                autoStartFocus: "自動開始專注",
                soundAlerts: "聲音提醒",
                showInMenuBar: "顯示在選單列",
                shortcut: "快捷鍵",
                start: "開始",
                pause: "暫停",
                resume: "繼續",
                skip: "跳過",
                reset: "重設",
                focusPhase: "專注",
                shortBreakPhase: "短休息",
                longBreakPhase: "長休息",
                completedCycles: "已完成週期",
                notificationFocusFinishedTitle: "專注完成",
                notificationFocusFinishedBody: "您的專注時間結束了，該休息了！",
                notificationBreakFinishedTitle: "休息結束",
                notificationBreakFinishedBody: "您的休息時間結束了，準備好再次專注了嗎？"
            )

        case .zhHK:
            return PomodoroFeatureStrings(
                title: "番茄鐘",
                hubDescription: "用番茄工作法保持專注。喺集中嘅時間間隔入面工作，定期休息，成日保持生產力。",
                enable: "啟用番茄鐘",
                enableCaption: "啟用番茄鐘嚟管理你嘅專注同休息",
                focusDuration: "專注時長",
                shortBreakDuration: "短休息時長",
                longBreakDuration: "長休息時長",
                longBreakInterval: "長休息間隔",
                autoStartBreaks: "自動開始休息",
                autoStartFocus: "自動開始專注",
                soundAlerts: "聲音提醒",
                showInMenuBar: "顯示喺選單列",
                shortcut: "快捷鍵",
                start: "開始",
                pause: "暫停",
                resume: "繼續",
                skip: "跳過",
                reset: "重設",
                focusPhase: "專注",
                shortBreakPhase: "短休息",
                longBreakPhase: "長休息",
                completedCycles: "已完成週期",
                notificationFocusFinishedTitle: "專注完成",
                notificationFocusFinishedBody: "你嘅專注時間完咗，該休息喇！",
                notificationBreakFinishedTitle: "休息結束",
                notificationBreakFinishedBody: "你嘅休息時間完咗，準備好再專注一次未？"
            )

        case .uk:
            return PomodoroFeatureStrings(
                title: "Таймер Помодоро",
                hubDescription: "Зберігайте концентрацію за допомогою техніки Помодоро. Працюйте в зосереджених інтервалах, робіть регулярні перерви та підтримуйте продуктивність протягом дня.",
                enable: "Увімкнути Помодоро",
                enableCaption: "Активуйте таймер Помодоро для керування фокусом та перервами",
                focusDuration: "Тривалість фокусу",
                shortBreakDuration: "Тривалість короткої перерви",
                longBreakDuration: "Тривалість довгої перерви",
                longBreakInterval: "Інтервал довгої перерви",
                autoStartBreaks: "Автоматичний запуск перерв",
                autoStartFocus: "Автоматичний запуск сесій фокусу",
                soundAlerts: "Звукові сповіщення",
                showInMenuBar: "Показувати в рядку меню",
                shortcut: "Гаряча клавіша",
                start: "Почати",
                pause: "Пауза",
                resume: "Продовжити",
                skip: "Пропустити",
                reset: "Скинути",
                focusPhase: "Фокус",
                shortBreakPhase: "Коротка перерва",
                longBreakPhase: "Довга перерва",
                completedCycles: "Завершені цикли",
                notificationFocusFinishedTitle: "Сесію фокусу завершено",
                notificationFocusFinishedBody: "Вашу сесію фокусу завершено. Час на перерву!",
                notificationBreakFinishedTitle: "Перерву завершено",
                notificationBreakFinishedBody: "Вашу перерву завершено. Готові знову зосередитися?"
            )
        }
    }
}
