// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

struct NotchPomodoroHistoryStrings {
    let title: String
    let archive: String
    let backToTop: String
    let today: String
    let week: String
    let allDays: String
    let breaks: String
    let export: String
    let empty: String
    let emptyDay: String
    let unavailable: String
}

extension FeatureStrings {
    static func notchPomodoroHistory(_ language: AppLanguage) -> NotchPomodoroHistoryStrings {
        switch language {
        case .enUS: return NotchPomodoroHistoryStrings(
            title: "History",
            archive: "Jump to month",
            backToTop: "Back to top",
            today: "Today",
            week: "Last 7 days",
            allDays: "All days",
            breaks: "Breaks",
            export: "Export all history as CSV",
            empty: "Completed Pomodoro sessions appear here.",
            emptyDay: "No completed intervals on this day.",
            unavailable: "Some history could not be read or saved.")
        case .ptBR: return NotchPomodoroHistoryStrings(
            title: "Histórico",
            archive: "Ir para o mês",
            backToTop: "Voltar ao início",
            today: "Hoje",
            week: "Últimos 7 dias",
            allDays: "Todos os dias",
            breaks: "Pausas",
            export: "Exportar todo o histórico em CSV",
            empty: "As sessões Pomodoro concluídas aparecem aqui.",
            emptyDay: "Nenhum intervalo concluído neste dia.",
            unavailable: "Não foi possível ler ou salvar parte do histórico.")
        case .es: return NotchPomodoroHistoryStrings(
            title: "Historial",
            archive: "Ir al mes",
            backToTop: "Volver al inicio",
            today: "Hoy",
            week: "Últimos 7 días",
            allDays: "Todos los días",
            breaks: "Descansos",
            export: "Exportar todo el historial a CSV",
            empty: "Las sesiones Pomodoro completadas aparecen aquí.",
            emptyDay: "No hay intervalos completados en este día.",
            unavailable: "No se pudo leer o guardar parte del historial.")
        case .sk: return NotchPomodoroHistoryStrings(
            title: "História",
            archive: "Prejsť na mesiac",
            backToTop: "Späť na začiatok",
            today: "Dnes",
            week: "Posledných 7 dní",
            allDays: "Všetky dni",
            breaks: "Prestávky",
            export: "Exportovať celú históriu do CSV",
            empty: "Tu sa zobrazia dokončené relácie Pomodoro.",
            emptyDay: "V tento deň nebol dokončený žiadny interval.",
            unavailable: "Časť histórie sa nepodarilo načítať alebo uložiť.")
        case .de: return NotchPomodoroHistoryStrings(
            title: "Verlauf",
            archive: "Zum Monat springen",
            backToTop: "Zum Anfang",
            today: "Heute",
            week: "Letzte 7 Tage",
            allDays: "Alle Tage",
            breaks: "Pausen",
            export: "Gesamten Verlauf als CSV exportieren",
            empty: "Abgeschlossene Pomodoro-Sitzungen erscheinen hier.",
            emptyDay: "An diesem Tag wurden keine Intervalle abgeschlossen.",
            unavailable: "Ein Teil des Verlaufs konnte nicht gelesen oder gespeichert werden.")
        case .fr: return NotchPomodoroHistoryStrings(
            title: "Historique",
            archive: "Aller au mois",
            backToTop: "Retour en haut",
            today: "Aujourd’hui",
            week: "7 derniers jours",
            allDays: "Tous les jours",
            breaks: "Pauses",
            export: "Exporter tout l’historique en CSV",
            empty: "Les séances Pomodoro terminées s’affichent ici.",
            emptyDay: "Aucun intervalle terminé ce jour-là.",
            unavailable: "Une partie de l’historique n’a pas pu être lue ou enregistrée.")
        case .it: return NotchPomodoroHistoryStrings(
            title: "Cronologia",
            archive: "Vai al mese",
            backToTop: "Torna all’inizio",
            today: "Oggi",
            week: "Ultimi 7 giorni",
            allDays: "Tutti i giorni",
            breaks: "Pause",
            export: "Esporta tutta la cronologia in CSV",
            empty: "Le sessioni Pomodoro completate appaiono qui.",
            emptyDay: "Nessun intervallo completato in questo giorno.",
            unavailable: "Impossibile leggere o salvare parte della cronologia.")
        case .ru: return NotchPomodoroHistoryStrings(
            title: "История",
            archive: "Перейти к месяцу",
            backToTop: "К началу",
            today: "Сегодня",
            week: "Последние 7 дней",
            allDays: "Все дни",
            breaks: "Перерывы",
            export: "Экспорт всей истории в CSV",
            empty: "Здесь появятся завершённые этапы Pomodoro.",
            emptyDay: "В этот день нет завершённых интервалов.",
            unavailable: "Не удалось прочитать или сохранить часть истории.")
        case .tr: return NotchPomodoroHistoryStrings(
            title: "Geçmiş",
            archive: "Aya git",
            backToTop: "Başa dön",
            today: "Bugün",
            week: "Son 7 gün",
            allDays: "Tüm günler",
            breaks: "Molalar",
            export: "Tüm geçmişi CSV olarak dışa aktar",
            empty: "Tamamlanan Pomodoro oturumları burada görünür.",
            emptyDay: "Bu gün tamamlanan aralık yok.",
            unavailable: "Geçmişin bir bölümü okunamadı veya kaydedilemedi.")
        case .ja: return NotchPomodoroHistoryStrings(
            title: "履歴",
            archive: "月に移動",
            backToTop: "先頭に戻る",
            today: "今日",
            week: "過去7日間",
            allDays: "すべての日",
            breaks: "休憩",
            export: "全履歴をCSVで書き出す",
            empty: "完了したポモドーロセッションがここに表示されます。",
            emptyDay: "この日に完了した時間帯はありません。",
            unavailable: "履歴の一部を読み込めなかったか、保存できませんでした。")
        case .ko: return NotchPomodoroHistoryStrings(
            title: "기록",
            archive: "월로 이동",
            backToTop: "맨 위로",
            today: "오늘",
            week: "최근 7일",
            allDays: "모든 날짜",
            breaks: "휴식",
            export: "전체 기록을 CSV로 내보내기",
            empty: "완료한 포모도로 세션이 여기에 표시됩니다.",
            emptyDay: "이날 완료한 구간이 없습니다.",
            unavailable: "기록의 일부를 읽거나 저장할 수 없습니다.")
        case .zhHans: return NotchPomodoroHistoryStrings(
            title: "历史记录",
            archive: "跳转到月份",
            backToTop: "返回顶部",
            today: "今天",
            week: "最近 7 天",
            allDays: "所有日期",
            breaks: "休息",
            export: "将全部历史记录导出为 CSV",
            empty: "已完成的番茄钟时段会显示在这里。",
            emptyDay: "这一天没有已完成的时段。",
            unavailable: "部分历史记录无法读取或保存。")
        case .zhTW: return NotchPomodoroHistoryStrings(
            title: "歷史記錄",
            archive: "跳至月份",
            backToTop: "回到頂端",
            today: "今天",
            week: "最近 7 天",
            allDays: "所有日期",
            breaks: "休息",
            export: "將全部歷史記錄匯出為 CSV",
            empty: "已完成的番茄鐘時段會顯示在這裡。",
            emptyDay: "這一天沒有已完成的時段。",
            unavailable: "部分歷史記錄無法讀取或儲存。")
        case .zhHK: return NotchPomodoroHistoryStrings(
            title: "歷史記錄",
            archive: "跳至月份",
            backToTop: "返回頂部",
            today: "今日",
            week: "最近 7 日",
            allDays: "所有日期",
            breaks: "休息",
            export: "將全部歷史記錄匯出為 CSV",
            empty: "已完成的番茄鐘時段會在這裏顯示。",
            emptyDay: "這一日沒有已完成的時段。",
            unavailable: "部分歷史記錄無法讀取或儲存。")
        case .uk: return NotchPomodoroHistoryStrings(
            title: "Історія",
            archive: "Перейти до місяця",
            backToTop: "На початок",
            today: "Сьогодні",
            week: "Останні 7 днів",
            allDays: "Усі дні",
            breaks: "Перерви",
            export: "Експортувати всю історію в CSV",
            empty: "Тут з’являться завершені етапи Pomodoro.",
            emptyDay: "Цього дня немає завершених інтервалів.",
            unavailable: "Не вдалося прочитати або зберегти частину історії.")
        }
    }
}
