// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

extension FeatureStrings {
    /// The Dynamic Island section of the Sounds page.
    static func islandSounds(_ language: AppLanguage) -> SoundGroupStrings {
        switch language {
        case .enUS: return SoundGroupStrings(
            title: "Dynamic Island",
            note: "These sounds play while the Downloads and Calendar pages of the Dynamic Island are on.",
            moments: [
                .downloadFinished: SoundMoment(title: "Download finished",
                                               caption: "When a download in the island’s folder finishes."),
                .calendarEventSoon: SoundMoment(title: "Event starting soon",
                                                caption: "Five minutes before a timed event starts, once per event."),
            ])
        case .ptBR: return SoundGroupStrings(
            title: "Dynamic Island",
            note: "Estes sons tocam enquanto as páginas Downloads e Calendário da Dynamic Island estão ativadas.",
            moments: [
                .downloadFinished: SoundMoment(title: "Download concluído",
                                               caption: "Quando um download na pasta da ilha termina."),
                .calendarEventSoon: SoundMoment(title: "Evento começando",
                                                caption: "Cinco minutos antes de um evento com horário começar, uma vez por evento."),
            ])
        case .tr: return SoundGroupStrings(
            title: "Dynamic Island",
            note: "Bu sesler, Dynamic Island’ın İndirilenler ve Takvim sayfaları açıkken çalar.",
            moments: [
                .downloadFinished: SoundMoment(title: "İndirme bitti",
                                               caption: "Adanın klasöründeki bir indirme bittiğinde."),
                .calendarEventSoon: SoundMoment(title: "Etkinlik yaklaşıyor",
                                                caption: "Saatli bir etkinlik başlamadan beş dakika önce, etkinlik başına bir kez."),
            ])
        case .ru: return SoundGroupStrings(
            title: "Dynamic Island",
            note: "Эти звуки воспроизводятся, пока включены страницы «Загрузки» и «Календарь» в Dynamic Island.",
            moments: [
                .downloadFinished: SoundMoment(title: "Загрузка завершена",
                                               caption: "Когда завершается загрузка в папке острова."),
                .calendarEventSoon: SoundMoment(title: "Скоро событие",
                                                caption: "За пять минут до начала события со временем, один раз для каждого."),
            ])
        case .es: return SoundGroupStrings(
            title: "Dynamic Island",
            note: "Estos sonidos suenan mientras las páginas Descargas y Calendario de la Dynamic Island están activadas.",
            moments: [
                .downloadFinished: SoundMoment(title: "Descarga terminada",
                                               caption: "Cuando termina una descarga en la carpeta de la isla."),
                .calendarEventSoon: SoundMoment(title: "Evento a punto de empezar",
                                                caption: "Cinco minutos antes de que empiece un evento con hora, una vez por evento."),
            ])
        case .sk: return SoundGroupStrings(
            title: "Dynamic Island",
            note: "Tieto zvuky znejú, kým sú v Dynamic Island zapnuté stránky Stiahnuté a Kalendár.",
            moments: [
                .downloadFinished: SoundMoment(title: "Sťahovanie dokončené",
                                               caption: "Keď sa dokončí sťahovanie v priečinku ostrova."),
                .calendarEventSoon: SoundMoment(title: "Udalosť čoskoro začne",
                                                caption: "Päť minút pred začiatkom udalosti s časom, raz pre každú udalosť."),
            ])
        case .de: return SoundGroupStrings(
            title: "Dynamic Island",
            note: "Diese Töne spielen, solange die Seiten Downloads und Kalender der Dynamic Island aktiviert sind.",
            moments: [
                .downloadFinished: SoundMoment(title: "Download abgeschlossen",
                                               caption: "Wenn ein Download im Ordner der Insel fertig ist."),
                .calendarEventSoon: SoundMoment(title: "Termin beginnt bald",
                                                caption: "Fünf Minuten bevor ein Termin mit Uhrzeit beginnt, einmal pro Termin."),
            ])
        case .fr: return SoundGroupStrings(
            title: "Dynamic Island",
            note: "Ces sons sont lus tant que les pages Téléchargements et Calendrier de la Dynamic Island sont activées.",
            moments: [
                .downloadFinished: SoundMoment(title: "Téléchargement terminé",
                                               caption: "Quand un téléchargement dans le dossier de l’île se termine."),
                .calendarEventSoon: SoundMoment(title: "Événement imminent",
                                                caption: "Cinq minutes avant le début d’un événement horaire, une fois par événement."),
            ])
        case .it: return SoundGroupStrings(
            title: "Dynamic Island",
            note: "Questi suoni si sentono mentre le pagine Download e Calendario della Dynamic Island sono attive.",
            moments: [
                .downloadFinished: SoundMoment(title: "Download completato",
                                               caption: "Quando termina un download nella cartella dell’isola."),
                .calendarEventSoon: SoundMoment(title: "Evento in arrivo",
                                                caption: "Cinque minuti prima che inizi un evento con orario, una volta per evento."),
            ])
        case .ja: return SoundGroupStrings(
            title: "Dynamic Island",
            note: "これらのサウンドは、Dynamic Islandのダウンロードとカレンダーのページがオンのときに鳴ります。",
            moments: [
                .downloadFinished: SoundMoment(title: "ダウンロード完了",
                                               caption: "アイランドのフォルダでダウンロードが終わったとき。"),
                .calendarEventSoon: SoundMoment(title: "まもなくイベント",
                                                caption: "時刻のあるイベントが始まる5分前に、イベントごとに1回。"),
            ])
        case .ko: return SoundGroupStrings(
            title: "Dynamic Island",
            note: "이 사운드는 Dynamic Island의 다운로드 및 캘린더 페이지가 켜져 있을 때 재생됩니다.",
            moments: [
                .downloadFinished: SoundMoment(title: "다운로드 완료",
                                               caption: "아일랜드 폴더의 다운로드가 끝났을 때."),
                .calendarEventSoon: SoundMoment(title: "곧 시작하는 이벤트",
                                                caption: "시간이 정해진 이벤트가 시작되기 5분 전에, 이벤트마다 한 번."),
            ])
        case .uk: return SoundGroupStrings(
            title: "Dynamic Island",
            note: "Ці звуки лунають, поки в Dynamic Island ввімкнено сторінки «Завантаження» і «Календар».",
            moments: [
                .downloadFinished: SoundMoment(title: "Завантаження завершено",
                                               caption: "Коли завершується завантаження в папці острова."),
                .calendarEventSoon: SoundMoment(title: "Скоро подія",
                                                caption: "За п’ять хвилин до початку події з часом, один раз для кожної."),
            ])
        case .zhHans: return SoundGroupStrings(
            title: "Dynamic Island",
            note: "这些声音会在 Dynamic Island 的下载和日历页面开启时播放。",
            moments: [
                .downloadFinished: SoundMoment(title: "下载完成",
                                               caption: "灵动岛文件夹中的下载完成时。"),
                .calendarEventSoon: SoundMoment(title: "日程即将开始",
                                                caption: "有具体时间的日程开始前五分钟，每个日程一次。"),
            ])
        case .zhTW: return SoundGroupStrings(
            title: "Dynamic Island",
            note: "這些聲音會在 Dynamic Island 的下載項目和行事曆頁面開啟時播放。",
            moments: [
                .downloadFinished: SoundMoment(title: "下載完成",
                                               caption: "動態島資料夾中的下載完成時。"),
                .calendarEventSoon: SoundMoment(title: "行程即將開始",
                                                caption: "有時間的行程開始前五分鐘，每個行程一次。"),
            ])
        case .zhHK: return SoundGroupStrings(
            title: "Dynamic Island",
            note: "這些聲音會在 Dynamic Island 的下載項目和行事曆頁面開啟時播放。",
            moments: [
                .downloadFinished: SoundMoment(title: "下載完成",
                                               caption: "動態島資料夾中的下載完成時。"),
                .calendarEventSoon: SoundMoment(title: "行程即將開始",
                                                caption: "有時間的行程開始前五分鐘，每個行程一次。"),
            ])
        }
    }
}
