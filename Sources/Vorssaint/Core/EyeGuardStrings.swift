// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

struct EyeGuardStrings {
    let pageTitle: String
    let hubDescription: String
    let enableToggle: String
    let enableCaption: String
    let scheduleLabel: String
    let presetTwentyTwentyTwenty: String
    let presetBalanced: String
    let presetLongSession: String
    let presetCustom: String
    let presetCaption: String
    let workLabel: String
    let breakLabel: String
    let skipButton: String
    let breakHeadline: String
    let warningFormat: String
    let breakRemainingFormat: String

    func warning(secondsLeft: Int) -> String {
        String(format: warningFormat, secondsLeft)
    }

    func breakRemaining(secondsLeft: Int) -> String {
        String(format: breakRemainingFormat, secondsLeft)
    }

    func name(for preset: EyeGuardPreset) -> String {
        switch preset {
        case .twentyTwentyTwenty: return presetTwentyTwentyTwenty
        case .balanced: return presetBalanced
        case .longSession: return presetLongSession
        case .custom: return presetCustom
        }
    }
}

extension FeatureStrings {
    static func eyeGuard(_ language: AppLanguage) -> EyeGuardStrings {
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

extension EyeGuardStrings {
    static let enUS = EyeGuardStrings(
        pageTitle: "Eye-Guard",
        hubDescription: "Fades every screen to black on a work and break schedule, so you actually look away.",
        enableToggle: "Run on a schedule",
        enableCaption: "Fades the screens to black when a break falls due, warning you first and keeping a Skip button while it is up. Time already spent away from the keyboard counts as the break.",
        scheduleLabel: "Schedule",
        presetTwentyTwentyTwenty: "20-20-20 rule",
        presetBalanced: "Balanced",
        presetLongSession: "Long session",
        presetCustom: "Custom",
        presetCaption: "The 20-20-20 timing is the one the American Optometric Association and the American Academy of Ophthalmology publish: every 20 minutes, look about 20 feet away for 20 seconds.",
        workLabel: "Work (minutes)",
        breakLabel: "Break (seconds)",
        skipButton: "Skip break",
        breakHeadline: "Look away",
        warningFormat: "Break in %ds",
        breakRemainingFormat: "%ds left"
    )

    static let ptBR = EyeGuardStrings(
        pageTitle: "Eye-Guard",
        hubDescription: "Escurece todas as telas em um ciclo de trabalho e pausa, para você realmente descansar a vista.",
        enableToggle: "Seguir um cronograma",
        enableCaption: "Escurece as telas quando a pausa chega, avisando antes e mantendo um botão Pular enquanto ela dura. O tempo longe do teclado já conta como pausa.",
        scheduleLabel: "Cronograma",
        presetTwentyTwentyTwenty: "Regra 20-20-20",
        presetBalanced: "Equilibrado",
        presetLongSession: "Sessão longa",
        presetCustom: "Personalizado",
        presetCaption: "O intervalo 20-20-20 é o publicado pela American Optometric Association e pela American Academy of Ophthalmology: a cada 20 minutos, olhe para algo a cerca de 6 metros por 20 segundos.",
        workLabel: "Trabalho (minutos)",
        breakLabel: "Pausa (segundos)",
        skipButton: "Pular pausa",
        breakHeadline: "Olhe para longe",
        warningFormat: "Pausa em %ds",
        breakRemainingFormat: "Faltam %ds"
    )

    static let tr = EyeGuardStrings(
        pageTitle: "Eye-Guard",
        hubDescription: "Çalışma ve mola döngüsüne göre tüm ekranları karartır, böylece gerçekten uzağa bakarsınız.",
        enableToggle: "Zamanlamaya göre çalıştır",
        enableCaption: "Mola zamanı geldiğinde ekranları karartır; öncesinde uyarır ve mola sürerken bir Atla düğmesi tutar. Klavyeden uzakta geçen süre zaten mola sayılır.",
        scheduleLabel: "Zamanlama",
        presetTwentyTwentyTwenty: "20-20-20 kuralı",
        presetBalanced: "Dengeli",
        presetLongSession: "Uzun oturum",
        presetCustom: "Özel",
        presetCaption: "20-20-20 zamanlaması American Optometric Association ve American Academy of Ophthalmology tarafından yayımlanan kuraldır: her 20 dakikada bir, yaklaşık 6 metre uzağa 20 saniye bakın.",
        workLabel: "Çalışma (dakika)",
        breakLabel: "Mola (saniye)",
        skipButton: "Molayı atla",
        breakHeadline: "Uzağa bakın",
        warningFormat: "%d sn içinde mola",
        breakRemainingFormat: "%d sn kaldı"
    )

    static let ru = EyeGuardStrings(
        pageTitle: "Eye-Guard",
        hubDescription: "Затемняет все экраны по расписанию работы и перерывов, чтобы глаза действительно отдыхали.",
        enableToggle: "Работать по расписанию",
        enableCaption: "Затемняет экраны, когда наступает перерыв. Сначала показывается предупреждение, а во время перерыва доступна кнопка «Пропустить». Время, проведённое вдали от клавиатуры, уже засчитывается как перерыв.",
        scheduleLabel: "Расписание",
        presetTwentyTwentyTwenty: "Правило 20-20-20",
        presetBalanced: "Сбалансированное",
        presetLongSession: "Длинная сессия",
        presetCustom: "Своё",
        presetCaption: "Интервал 20-20-20 опубликован American Optometric Association и American Academy of Ophthalmology: каждые 20 минут смотрите вдаль, примерно на 6 метров, в течение 20 секунд.",
        workLabel: "Работа (минуты)",
        breakLabel: "Перерыв (секунды)",
        skipButton: "Пропустить перерыв",
        breakHeadline: "Посмотрите вдаль",
        warningFormat: "Перерыв через %d с",
        breakRemainingFormat: "Осталось %d с"
    )

    static let es = EyeGuardStrings(
        pageTitle: "Eye-Guard",
        hubDescription: "Oscurece todas las pantallas según un ciclo de trabajo y descanso, para que apartes la vista de verdad.",
        enableToggle: "Ejecutar según un horario",
        enableCaption: "Funde las pantallas a negro cuando toca el descanso, avisando antes y manteniendo un botón Omitir mientras dura. El tiempo que ya has pasado lejos del teclado cuenta como descanso.",
        scheduleLabel: "Horario",
        presetTwentyTwentyTwenty: "Regla 20-20-20",
        presetBalanced: "Equilibrado",
        presetLongSession: "Sesión larga",
        presetCustom: "Personalizado",
        presetCaption: "El intervalo 20-20-20 es el que publican la American Optometric Association y la American Academy of Ophthalmology: cada 20 minutos, mira a unos 6 metros durante 20 segundos.",
        workLabel: "Trabajo (minutos)",
        breakLabel: "Descanso (segundos)",
        skipButton: "Omitir descanso",
        breakHeadline: "Aparta la vista",
        warningFormat: "Descanso en %d s",
        breakRemainingFormat: "Quedan %d s"
    )

    static let de = EyeGuardStrings(
        pageTitle: "Eye-Guard",
        hubDescription: "Dunkelt alle Bildschirme nach einem Arbeits- und Pausenrhythmus ab, damit die Augen wirklich ruhen.",
        enableToggle: "Nach Zeitplan ausführen",
        enableCaption: "Blendet die Bildschirme auf Schwarz, wenn eine Pause fällig ist – mit Vorwarnung und einer Taste zum Überspringen, solange sie läuft. Zeit, die bereits abseits der Tastatur vergangen ist, zählt als Pause.",
        scheduleLabel: "Zeitplan",
        presetTwentyTwentyTwenty: "20-20-20-Regel",
        presetBalanced: "Ausgewogen",
        presetLongSession: "Lange Sitzung",
        presetCustom: "Eigen",
        presetCaption: "Die 20-20-20-Taktung stammt von der American Optometric Association und der American Academy of Ophthalmology: alle 20 Minuten 20 Sekunden lang etwa 6 Meter weit schauen.",
        workLabel: "Arbeit (Minuten)",
        breakLabel: "Pause (Sekunden)",
        skipButton: "Pause überspringen",
        breakHeadline: "Schau in die Ferne",
        warningFormat: "Pause in %d s",
        breakRemainingFormat: "Noch %d s"
    )

    static let fr = EyeGuardStrings(
        pageTitle: "Eye-Guard",
        hubDescription: "Assombrit tous les écrans selon un cycle de travail et de pause, pour que les yeux se reposent vraiment.",
        enableToggle: "Exécuter selon un horaire",
        enableCaption: "Fond les écrans au noir à l’heure de la pause, en prévenant avant et en gardant un bouton Passer pendant. Le temps déjà passé loin du clavier compte comme une pause.",
        scheduleLabel: "Horaire",
        presetTwentyTwentyTwenty: "Règle 20-20-20",
        presetBalanced: "Équilibré",
        presetLongSession: "Session longue",
        presetCustom: "Personnalisé",
        presetCaption: "Le rythme 20-20-20 est celui que publient l’American Optometric Association et l’American Academy of Ophthalmology. Toutes les 20 minutes, regardez à environ 6 mètres pendant 20 secondes.",
        workLabel: "Travail (minutes)",
        breakLabel: "Pause (secondes)",
        skipButton: "Passer la pause",
        breakHeadline: "Regardez au loin",
        warningFormat: "Pause dans %d s",
        breakRemainingFormat: "%d s restantes"
    )

    static let it = EyeGuardStrings(
        pageTitle: "Eye-Guard",
        hubDescription: "Oscura tutti gli schermi seguendo un ciclo di lavoro e pausa, così gli occhi riposano davvero.",
        enableToggle: "Esegui secondo una pianificazione",
        enableCaption: "Sfuma gli schermi al nero quando arriva la pausa, avvisando prima e mantenendo un pulsante Salta mentre è attiva. Il tempo già trascorso lontano dalla tastiera conta come pausa.",
        scheduleLabel: "Pianificazione",
        presetTwentyTwentyTwenty: "Regola 20-20-20",
        presetBalanced: "Bilanciato",
        presetLongSession: "Sessione lunga",
        presetCustom: "Personalizzato",
        presetCaption: "La cadenza 20-20-20 è quella pubblicata da American Optometric Association e American Academy of Ophthalmology: ogni 20 minuti guarda a circa 6 metri per 20 secondi.",
        workLabel: "Lavoro (minuti)",
        breakLabel: "Pausa (secondi)",
        skipButton: "Salta la pausa",
        breakHeadline: "Guarda lontano",
        warningFormat: "Pausa tra %d s",
        breakRemainingFormat: "%d s rimanenti"
    )

    static let ja = EyeGuardStrings(
        pageTitle: "Eye-Guard",
        hubDescription: "作業と休憩のスケジュールに合わせてすべての画面を暗くし、目を確実に休ませます。",
        enableToggle: "スケジュールで実行",
        enableCaption: "休憩の時間になると画面を黒くフェードします。事前に予告し、休憩中はスキップボタンを表示します。キーボードから離れていた時間は休憩として数えます。",
        scheduleLabel: "スケジュール",
        presetTwentyTwentyTwenty: "20-20-20ルール",
        presetBalanced: "バランス",
        presetLongSession: "長時間セッション",
        presetCustom: "カスタム",
        presetCaption: "20-20-20は米国検眼協会（AOA）と米国眼科学会（AAO）が公表している間隔です。20分ごとに、約6メートル先を20秒間見ます。",
        workLabel: "作業（分）",
        breakLabel: "休憩（秒）",
        skipButton: "休憩をスキップ",
        breakHeadline: "遠くを見てください",
        warningFormat: "%d秒後に休憩",
        breakRemainingFormat: "残り%d秒"
    )

    static let ko = EyeGuardStrings(
        pageTitle: "Eye-Guard",
        hubDescription: "작업과 휴식 일정에 맞춰 모든 화면을 어둡게 하여 눈을 확실히 쉬게 합니다.",
        enableToggle: "일정에 따라 실행",
        enableCaption: "휴식 시간이 되면 화면을 검게 페이드합니다. 미리 알려 주고, 휴식 중에는 건너뛰기 버튼을 표시합니다. 키보드에서 떨어져 있던 시간은 휴식으로 계산합니다.",
        scheduleLabel: "일정",
        presetTwentyTwentyTwenty: "20-20-20 규칙",
        presetBalanced: "균형",
        presetLongSession: "긴 세션",
        presetCustom: "사용자 지정",
        presetCaption: "20-20-20 간격은 미국검안협회(AOA)와 미국안과학회(AAO)가 공표한 것입니다. 20분마다 약 6미터 떨어진 곳을 20초간 바라보세요.",
        workLabel: "작업(분)",
        breakLabel: "휴식(초)",
        skipButton: "휴식 건너뛰기",
        breakHeadline: "먼 곳을 보세요",
        warningFormat: "%d초 후 휴식",
        breakRemainingFormat: "%d초 남음"
    )

    static let zhHans = EyeGuardStrings(
        pageTitle: "Eye-Guard",
        hubDescription: "按工作与休息的节奏将所有屏幕渐暗，让眼睛真正得到休息。",
        enableToggle: "按计划运行",
        enableCaption: "到了休息时间将屏幕渐变为黑色，事先预告，休息期间保留“跳过”按钮。已经离开键盘的时间会计为休息。",
        scheduleLabel: "计划",
        presetTwentyTwentyTwenty: "20-20-20 法则",
        presetBalanced: "均衡",
        presetLongSession: "长时段",
        presetCustom: "自定义",
        presetCaption: "20-20-20 间隔由美国验光协会（AOA）与美国眼科学会（AAO）发布：每 20 分钟，看向约 6 米外的地方 20 秒。",
        workLabel: "工作（分钟）",
        breakLabel: "休息（秒）",
        skipButton: "跳过休息",
        breakHeadline: "请看向远处",
        warningFormat: "%d 秒后休息",
        breakRemainingFormat: "剩余 %d 秒"
    )

    static let zhTW = EyeGuardStrings(
        pageTitle: "Eye-Guard",
        hubDescription: "依工作與休息的節奏將所有螢幕淡暗，讓眼睛確實休息。",
        enableToggle: "依排程執行",
        enableCaption: "休息時間到時將螢幕淡出為黑色，事前預告，休息期間保留「略過」按鈕。已經離開鍵盤的時間會計為休息。",
        scheduleLabel: "排程",
        presetTwentyTwentyTwenty: "20-20-20 法則",
        presetBalanced: "均衡",
        presetLongSession: "長時段",
        presetCustom: "自訂",
        presetCaption: "20-20-20 間隔由美國驗光協會（AOA）與美國眼科醫學會（AAO）發布：每 20 分鐘，看向約 6 公尺外的地方 20 秒。",
        workLabel: "工作（分鐘）",
        breakLabel: "休息（秒）",
        skipButton: "略過休息",
        breakHeadline: "請看向遠方",
        warningFormat: "%d 秒後休息",
        breakRemainingFormat: "剩餘 %d 秒"
    )

    static let zhHK = EyeGuardStrings(
        pageTitle: "Eye-Guard",
        hubDescription: "依工作與休息的節奏將所有螢幕淡暗，讓眼睛真正休息。",
        enableToggle: "按排程執行",
        enableCaption: "休息時間到時將螢幕淡出為黑色，事前預告，休息期間保留「略過」按鈕。已經離開鍵盤的時間會計為休息。",
        scheduleLabel: "排程",
        presetTwentyTwentyTwenty: "20-20-20 法則",
        presetBalanced: "均衡",
        presetLongSession: "長時段",
        presetCustom: "自訂",
        presetCaption: "20-20-20 間隔由美國驗光協會（AOA）與美國眼科醫學會（AAO）發布：每 20 分鐘，望向約 6 米外的地方 20 秒。",
        workLabel: "工作（分鐘）",
        breakLabel: "休息（秒）",
        skipButton: "略過休息",
        breakHeadline: "請望向遠處",
        warningFormat: "%d 秒後休息",
        breakRemainingFormat: "剩餘 %d 秒"
    )
}
