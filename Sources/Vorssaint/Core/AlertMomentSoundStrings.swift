// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// The padlock's name in the lock moment's sound menu.
struct PadlockSoundStrings {
    let name: String
}

extension FeatureStrings {
    /// The alarms and alerts section of the Sounds page: the island’s timer,
    /// watch and padlock.
    static func alertSounds(_ language: AppLanguage) -> SoundGroupStrings {
        switch language {
        case .enUS: return SoundGroupStrings(
            title: "Alarms and alerts",
            note: "These sounds play while the Dynamic Island is on.",
            moments: [
                .timerFinished: SoundMoment(title: "Timer finished",
                                            caption: "When the island’s timer reaches zero. It rings until you dismiss it, for up to five minutes."),
                .watchFinished: SoundMoment(title: "Watch finished",
                                            caption: "When a window the island watches finishes or stops changing."),
                .screenLock: SoundMoment(title: "Lock and unlock",
                                         caption: "When the Mac locks and unlocks. The padlock closes, then opens."),
            ])
        case .ptBR: return SoundGroupStrings(
            title: "Alarmes e alertas",
            note: "Estes sons tocam enquanto a Dynamic Island está ativada.",
            moments: [
                .timerFinished: SoundMoment(title: "Timer terminou",
                                            caption: "Quando o timer da ilha chega a zero. Ele toca até você dispensá-lo, por até cinco minutos."),
                .watchFinished: SoundMoment(title: "Observação concluída",
                                            caption: "Quando uma janela observada pela ilha termina ou para de mudar."),
                .screenLock: SoundMoment(title: "Bloquear e desbloquear",
                                         caption: "Quando o Mac é bloqueado e desbloqueado. O cadeado fecha e depois abre."),
            ])
        case .tr: return SoundGroupStrings(
            title: "Alarmlar ve uyarılar",
            note: "Bu sesler Dynamic Island açıkken çalar.",
            moments: [
                .timerFinished: SoundMoment(title: "Zamanlayıcı bitti",
                                            caption: "Adanın zamanlayıcısı sıfıra ulaştığında. Siz kapatana kadar, en fazla beş dakika çalar."),
                .watchFinished: SoundMoment(title: "İzleme bitti",
                                            caption: "Adanın izlediği bir pencere bittiğinde ya da değişmeyi bıraktığında."),
                .screenLock: SoundMoment(title: "Kilitleme ve kilit açma",
                                         caption: "Mac kilitlendiğinde ve kilidi açıldığında. Asma kilit kapanır, sonra açılır."),
            ])
        case .ru: return SoundGroupStrings(
            title: "Будильники и оповещения",
            note: "Эти звуки воспроизводятся, пока включён Dynamic Island.",
            moments: [
                .timerFinished: SoundMoment(title: "Таймер завершён",
                                            caption: "Когда таймер острова доходит до нуля. Он звенит, пока вы его не закроете, но не дольше пяти минут."),
                .watchFinished: SoundMoment(title: "Наблюдение завершено",
                                            caption: "Когда окно, за которым следит остров, завершает работу или перестаёт меняться."),
                .screenLock: SoundMoment(title: "Блокировка и разблокировка",
                                         caption: "Когда Mac блокируется и разблокируется. Замок закрывается, затем открывается."),
            ])
        case .es: return SoundGroupStrings(
            title: "Alarmas y avisos",
            note: "Estos sonidos suenan mientras la Dynamic Island está activada.",
            moments: [
                .timerFinished: SoundMoment(title: "Temporizador terminado",
                                            caption: "Cuando el temporizador de la isla llega a cero. Suena hasta que lo descartes, durante un máximo de cinco minutos."),
                .watchFinished: SoundMoment(title: "Vigilancia terminada",
                                            caption: "Cuando una ventana que vigila la isla termina o deja de cambiar."),
                .screenLock: SoundMoment(title: "Bloquear y desbloquear",
                                         caption: "Cuando el Mac se bloquea y se desbloquea. El candado se cierra y luego se abre."),
            ])
        case .sk: return SoundGroupStrings(
            title: "Budíky a upozornenia",
            note: "Tieto zvuky znejú, kým je zapnutý Dynamic Island.",
            moments: [
                .timerFinished: SoundMoment(title: "Časovač skončil",
                                            caption: "Keď časovač ostrova dosiahne nulu. Zvoní, kým ho nezrušíte, najviac päť minút."),
                .watchFinished: SoundMoment(title: "Sledovanie skončilo",
                                            caption: "Keď okno, ktoré ostrov sleduje, skončí alebo sa prestane meniť."),
                .screenLock: SoundMoment(title: "Zamknutie a odomknutie",
                                         caption: "Keď sa Mac zamkne a odomkne. Zámok sa zatvorí a potom otvorí."),
            ])
        case .de: return SoundGroupStrings(
            title: "Wecker und Hinweise",
            note: "Diese Töne spielen, solange die Dynamic Island aktiviert ist.",
            moments: [
                .timerFinished: SoundMoment(title: "Timer abgelaufen",
                                            caption: "Wenn der Timer der Insel null erreicht. Er klingelt, bis du ihn schließt, höchstens fünf Minuten lang."),
                .watchFinished: SoundMoment(title: "Beobachtung beendet",
                                            caption: "Wenn ein Fenster, das die Insel beobachtet, fertig ist oder sich nicht mehr ändert."),
                .screenLock: SoundMoment(title: "Sperren und Entsperren",
                                         caption: "Wenn der Mac gesperrt und entsperrt wird. Das Vorhängeschloss schließt sich, dann öffnet es sich."),
            ])
        case .fr: return SoundGroupStrings(
            title: "Alarmes et alertes",
            note: "Ces sons sont lus tant que la Dynamic Island est activée.",
            moments: [
                .timerFinished: SoundMoment(title: "Minuteur terminé",
                                            caption: "Quand le minuteur de l’île atteint zéro. Il sonne jusqu’à ce que vous le fermiez, pendant cinq minutes au plus."),
                .watchFinished: SoundMoment(title: "Surveillance terminée",
                                            caption: "Quand une fenêtre surveillée par l’île a fini ou cesse de changer."),
                .screenLock: SoundMoment(title: "Verrouiller et déverrouiller",
                                         caption: "Quand le Mac se verrouille et se déverrouille. Le cadenas se ferme, puis s’ouvre."),
            ])
        case .it: return SoundGroupStrings(
            title: "Sveglie e avvisi",
            note: "Questi suoni vengono riprodotti mentre la Dynamic Island è attiva.",
            moments: [
                .timerFinished: SoundMoment(title: "Timer terminato",
                                            caption: "Quando il timer dell’isola arriva a zero. Suona finché non lo chiudi, per un massimo di cinque minuti."),
                .watchFinished: SoundMoment(title: "Osservazione terminata",
                                            caption: "Quando una finestra osservata dall’isola finisce o smette di cambiare."),
                .screenLock: SoundMoment(title: "Blocco e sblocco",
                                         caption: "Quando il Mac si blocca e si sblocca. Il lucchetto si chiude, poi si apre."),
            ])
        case .ja: return SoundGroupStrings(
            title: "アラームと通知",
            note: "これらのサウンドは Dynamic Island がオンのときに再生されます。",
            moments: [
                .timerFinished: SoundMoment(title: "タイマー終了",
                                            caption: "アイランドのタイマーがゼロになったとき。閉じるまで最大5分間鳴ります。"),
                .watchFinished: SoundMoment(title: "見守り終了",
                                            caption: "アイランドが見守っているウインドウが完了したか、変化しなくなったとき。"),
                .screenLock: SoundMoment(title: "ロックとロック解除",
                                         caption: "Mac がロックされたときとロック解除されたとき。南京錠が閉じ、そして開きます。"),
            ])
        case .ko: return SoundGroupStrings(
            title: "알람 및 알림",
            note: "이 사운드는 Dynamic Island가 켜져 있을 때 재생됩니다.",
            moments: [
                .timerFinished: SoundMoment(title: "타이머 종료",
                                            caption: "아일랜드의 타이머가 0이 되었을 때. 닫을 때까지 최대 5분 동안 울립니다."),
                .watchFinished: SoundMoment(title: "지켜보기 종료",
                                            caption: "아일랜드가 지켜보는 윈도우가 끝나거나 더 이상 바뀌지 않을 때."),
                .screenLock: SoundMoment(title: "잠금 및 잠금 해제",
                                         caption: "Mac이 잠기고 잠금 해제될 때. 자물쇠가 닫혔다가 열립니다."),
            ])
        case .uk: return SoundGroupStrings(
            title: "Будильники та сповіщення",
            note: "Ці звуки відтворюються, поки ввімкнено Dynamic Island.",
            moments: [
                .timerFinished: SoundMoment(title: "Таймер завершено",
                                            caption: "Коли таймер острова доходить до нуля. Він дзвонить, доки ви його не закриєте, але не довше п’яти хвилин."),
                .watchFinished: SoundMoment(title: "Спостереження завершено",
                                            caption: "Коли вікно, за яким стежить острів, завершує роботу або перестає змінюватися."),
                .screenLock: SoundMoment(title: "Блокування та розблокування",
                                         caption: "Коли Mac блокується та розблоковується. Замок закривається, потім відкривається."),
            ])
        case .zhHans: return SoundGroupStrings(
            title: "闹钟与提醒",
            note: "这些声音会在 Dynamic Island 开启时播放。",
            moments: [
                .timerFinished: SoundMoment(title: "计时器结束",
                                            caption: "当岛上的计时器归零时。它会一直响到你关闭为止，最长五分钟。"),
                .watchFinished: SoundMoment(title: "观察结束",
                                            caption: "当岛观察的窗口完成或不再变化时。"),
                .screenLock: SoundMoment(title: "锁定与解锁",
                                         caption: "当 Mac 锁定和解锁时。挂锁先合上，再打开。"),
            ])
        case .zhTW: return SoundGroupStrings(
            title: "鬧鐘與提醒",
            note: "這些聲音會在 Dynamic Island 開啟時播放。",
            moments: [
                .timerFinished: SoundMoment(title: "計時器結束",
                                            caption: "當島上的計時器歸零時。它會一直響到你關閉為止，最長五分鐘。"),
                .watchFinished: SoundMoment(title: "觀察結束",
                                            caption: "當島觀察的視窗完成或不再變化時。"),
                .screenLock: SoundMoment(title: "鎖定與解鎖",
                                         caption: "當 Mac 鎖定和解鎖時。掛鎖先扣上，再打開。"),
            ])
        case .zhHK: return SoundGroupStrings(
            title: "鬧鐘與提示",
            note: "這些聲音會在 Dynamic Island 開啟時播放。",
            moments: [
                .timerFinished: SoundMoment(title: "計時器結束",
                                            caption: "當島上的計時器歸零時。它會一直響到你關閉為止，最長五分鐘。"),
                .watchFinished: SoundMoment(title: "觀察結束",
                                            caption: "當島觀察的視窗完成或不再變化時。"),
                .screenLock: SoundMoment(title: "鎖定與解鎖",
                                         caption: "當 Mac 鎖定和解鎖時。掛鎖先扣上，再打開。"),
            ])
        }
    }

    /// The padlock the Mac's own lock screen plays, the lock moment's sound
    /// until another is chosen.
    static func padlockSound(_ language: AppLanguage) -> PadlockSoundStrings {
        switch language {
        case .enUS: return PadlockSoundStrings(name: "Padlock")
        case .ptBR: return PadlockSoundStrings(name: "Cadeado")
        case .tr: return PadlockSoundStrings(name: "Asma kilit")
        case .ru: return PadlockSoundStrings(name: "Замок")
        case .es: return PadlockSoundStrings(name: "Candado")
        case .sk: return PadlockSoundStrings(name: "Zámok")
        case .de: return PadlockSoundStrings(name: "Vorhängeschloss")
        case .fr: return PadlockSoundStrings(name: "Cadenas")
        case .it: return PadlockSoundStrings(name: "Lucchetto")
        case .ja: return PadlockSoundStrings(name: "南京錠")
        case .ko: return PadlockSoundStrings(name: "자물쇠")
        case .uk: return PadlockSoundStrings(name: "Замок")
        case .zhHans: return PadlockSoundStrings(name: "挂锁")
        case .zhTW: return PadlockSoundStrings(name: "掛鎖")
        case .zhHK: return PadlockSoundStrings(name: "掛鎖")
        }
    }
}
