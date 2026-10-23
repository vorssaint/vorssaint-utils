// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// The Sounds page in Settings: what every moment shares. Each group's
/// title and moments are in its own file, beside `agentSounds`.
struct SoundStrings {
    let title: String
    /// Under the page's switch.
    let caption: String
    let playSounds: String
    let sound: String
    let volume: String
    let play: String
    let unavailable: String
    let repeats: String
    let once: String
    /// A repeat count above one, as in "2 times".
    let timesFormat: String
    /// The sections of the sound menu.
    let sourceSystem: String
    let sourceTones: String
    let sourceYours: String
    let addSound: String
    /// The page-wide rules under the page's switch.
    let quietWhileSharing: String
    let quietWhileSharingCaption: String
    let onlyWhenAway: String
    let onlyWhenAwayCaption: String
    let playOn: String
    let outputCurrent: String
    let outputAlerts: String

    func repeatCount(_ count: Int) -> String { count == 1 ? once : String(format: timesFormat, count) }
}

/// One moment's row.
struct SoundMoment {
    let title: String
    let caption: String
}

/// A section of the Sounds page. `note` shows while the group's
/// `noteApplies`, as when its feature is installed but not switched on.
struct SoundGroupStrings {
    let title: String
    let note: String?
    let moments: [AppSound: SoundMoment]
}

extension FeatureStrings {
    static func sounds(_ language: AppLanguage) -> SoundStrings {
        switch language {
        case .enUS: return SoundStrings(
            title: "Sounds",
            caption: "Choose which moments make a sound, which sound and how loud. Above 100%, a sound is boosted.",
            playSounds: "Play sounds",
            sound: "Sound",
            volume: "Volume",
            play: "Play",
            unavailable: "Not on this Mac",
            repeats: "Repeat",
            once: "Once",
            timesFormat: "%d times",
            sourceSystem: "macOS alerts",
            sourceTones: "Apple tones",
            sourceYours: "Your sounds",
            addSound: "Add a sound…",
            quietWhileSharing: "Quiet while sharing your screen or in a call",
            quietWhileSharingCaption: "No sound while your screen is shared or recorded, or an app is using a microphone.",
            onlyWhenAway: "Only when you’re not looking",
            onlyWhenAwayCaption: "An agent’s sounds wait until its terminal or app is not in front.",
            playOn: "Play sounds on",
            outputCurrent: "Current output",
            outputAlerts: "Alert sound device")
        case .ptBR: return SoundStrings(
            title: "Sons",
            caption: "Escolha quais momentos tocam um som, qual som e com que volume. Acima de 100%, o som é amplificado.",
            playSounds: "Tocar sons",
            sound: "Som",
            volume: "Volume",
            play: "Tocar",
            unavailable: "Não está neste Mac",
            repeats: "Repetir",
            once: "Uma vez",
            timesFormat: "%d vezes",
            sourceSystem: "Alertas do macOS",
            sourceTones: "Tons da Apple",
            sourceYours: "Seus sons",
            addSound: "Adicionar som…",
            quietWhileSharing: "Silenciar ao compartilhar a tela ou em chamadas",
            quietWhileSharingCaption: "Nenhum som enquanto a tela é compartilhada ou gravada, ou um app usa um microfone.",
            onlyWhenAway: "Só quando você não estiver olhando",
            onlyWhenAwayCaption: "Os sons de um agente só tocam quando o terminal ou app dele não está na frente.",
            playOn: "Tocar sons em",
            outputCurrent: "Saída atual",
            outputAlerts: "Dispositivo de alertas")
        case .tr: return SoundStrings(
            title: "Sesler",
            caption: "Hangi anların ses çıkaracağını, hangi sesi ve ne kadar yüksek olacağını seçin. %100’ün üzerinde ses güçlendirilir.",
            playSounds: "Sesleri çal",
            sound: "Ses",
            volume: "Ses düzeyi",
            play: "Çal",
            unavailable: "Bu Mac’te yok",
            repeats: "Tekrarla",
            once: "Bir kez",
            timesFormat: "%d kez",
            sourceSystem: "macOS uyarıları",
            sourceTones: "Apple tonları",
            sourceYours: "Sesleriniz",
            addSound: "Ses ekle…",
            quietWhileSharing: "Ekran paylaşırken veya görüşmedeyken sessiz",
            quietWhileSharingCaption: "Ekranınız paylaşılırken veya kaydedilirken ya da bir uygulama mikrofon kullanırken ses çalmaz.",
            onlyWhenAway: "Yalnızca bakmadığınızda",
            onlyWhenAwayCaption: "Bir ajanın sesleri, terminali veya uygulaması önde değilken çalar.",
            playOn: "Seslerin çalınacağı yer",
            outputCurrent: "Geçerli çıkış",
            outputAlerts: "Uyarı sesi aygıtı")
        case .ru: return SoundStrings(
            title: "Звуки",
            caption: "Выберите, какие моменты озвучиваются, каким звуком и насколько громко. Выше 100% звук усиливается.",
            playSounds: "Воспроизводить звуки",
            sound: "Звук",
            volume: "Громкость",
            play: "Воспроизвести",
            unavailable: "Нет на этом Mac",
            repeats: "Повтор",
            once: "Один раз",
            timesFormat: "%d раза",
            sourceSystem: "Сигналы macOS",
            sourceTones: "Мелодии Apple",
            sourceYours: "Ваши звуки",
            addSound: "Добавить звук…",
            quietWhileSharing: "Тишина при показе экрана и во время звонка",
            quietWhileSharingCaption: "Без звуков, пока экран транслируется или записывается либо приложение использует микрофон.",
            onlyWhenAway: "Только когда вы не смотрите",
            onlyWhenAwayCaption: "Звуки агента играют, только когда его терминал или приложение не на переднем плане.",
            playOn: "Воспроизводить на",
            outputCurrent: "Текущий выход",
            outputAlerts: "Устройство для сигналов")
        case .es: return SoundStrings(
            title: "Sonidos",
            caption: "Elige qué momentos suenan, con qué sonido y a qué volumen. Por encima del 100%, el sonido se amplifica.",
            playSounds: "Reproducir sonidos",
            sound: "Sonido",
            volume: "Volumen",
            play: "Reproducir",
            unavailable: "No está en este Mac",
            repeats: "Repetir",
            once: "Una vez",
            timesFormat: "%d veces",
            sourceSystem: "Alertas de macOS",
            sourceTones: "Tonos de Apple",
            sourceYours: "Tus sonidos",
            addSound: "Añadir sonido…",
            quietWhileSharing: "Silencio al compartir pantalla o en llamadas",
            quietWhileSharingCaption: "Sin sonidos mientras la pantalla se comparte o se graba, o una app usa un micrófono.",
            onlyWhenAway: "Solo cuando no estés mirando",
            onlyWhenAwayCaption: "Los sonidos de un agente suenan solo cuando su terminal o app no está delante.",
            playOn: "Reproducir en",
            outputCurrent: "Salida actual",
            outputAlerts: "Dispositivo de alertas")
        case .sk: return SoundStrings(
            title: "Zvuky",
            caption: "Vyberte, ktoré chvíle zaznejú, akým zvukom a ako nahlas. Nad 100 % sa zvuk zosilní.",
            playSounds: "Prehrávať zvuky",
            sound: "Zvuk",
            volume: "Hlasitosť",
            play: "Prehrať",
            unavailable: "Nie je v tomto Macu",
            repeats: "Opakovať",
            once: "Raz",
            timesFormat: "%d-krát",
            sourceSystem: "Upozornenia macOS",
            sourceTones: "Tóny Apple",
            sourceYours: "Vaše zvuky",
            addSound: "Pridať zvuk…",
            quietWhileSharing: "Ticho pri zdieľaní obrazovky alebo počas hovoru",
            quietWhileSharingCaption: "Žiadne zvuky, kým sa obrazovka zdieľa alebo nahráva, alebo aplikácia používa mikrofón.",
            onlyWhenAway: "Len keď sa nepozeráte",
            onlyWhenAwayCaption: "Zvuky agenta zaznejú, len keď jeho terminál alebo aplikácia nie je v popredí.",
            playOn: "Prehrávať na",
            outputCurrent: "Aktuálny výstup",
            outputAlerts: "Zariadenie pre upozornenia")
        case .de: return SoundStrings(
            title: "Töne",
            caption: "Wähle, welche Momente einen Ton spielen, welchen und wie laut. Über 100 % wird der Ton verstärkt.",
            playSounds: "Töne abspielen",
            sound: "Ton",
            volume: "Lautstärke",
            play: "Abspielen",
            unavailable: "Nicht auf diesem Mac",
            repeats: "Wiederholen",
            once: "Einmal",
            timesFormat: "%d-mal",
            sourceSystem: "macOS-Hinweistöne",
            sourceTones: "Apple-Töne",
            sourceYours: "Deine Töne",
            addSound: "Ton hinzufügen …",
            quietWhileSharing: "Stumm beim Bildschirmteilen oder in Anrufen",
            quietWhileSharingCaption: "Keine Töne, solange der Bildschirm geteilt oder aufgenommen wird oder eine App ein Mikrofon nutzt.",
            onlyWhenAway: "Nur wenn du nicht hinsiehst",
            onlyWhenAwayCaption: "Töne eines Agenten erklingen nur, wenn sein Terminal oder seine App nicht im Vordergrund ist.",
            playOn: "Töne wiedergeben auf",
            outputCurrent: "Aktuelle Ausgabe",
            outputAlerts: "Gerät für Warntöne")
        case .fr: return SoundStrings(
            title: "Sons",
            caption: "Choisissez quels moments émettent un son, lequel et à quel volume. Au-delà de 100 %, le son est amplifié.",
            playSounds: "Lire les sons",
            sound: "Son",
            volume: "Volume",
            play: "Écouter",
            unavailable: "Absent de ce Mac",
            repeats: "Répéter",
            once: "Une fois",
            timesFormat: "%d fois",
            sourceSystem: "Alertes macOS",
            sourceTones: "Tonalités Apple",
            sourceYours: "Vos sons",
            addSound: "Ajouter un son…",
            quietWhileSharing: "Silence pendant un partage d’écran ou un appel",
            quietWhileSharingCaption: "Aucun son tant que l’écran est partagé ou enregistré, ou qu’une app utilise un micro.",
            onlyWhenAway: "Seulement quand vous ne regardez pas",
            onlyWhenAwayCaption: "Les sons d’un agent ne jouent que si son terminal ou son app n’est pas au premier plan.",
            playOn: "Jouer les sons sur",
            outputCurrent: "Sortie actuelle",
            outputAlerts: "Appareil des alertes")
        case .it: return SoundStrings(
            title: "Suoni",
            caption: "Scegli quali momenti emettono un suono, quale suono e a che volume. Oltre il 100% il suono viene amplificato.",
            playSounds: "Riproduci suoni",
            sound: "Suono",
            volume: "Volume",
            play: "Riproduci",
            unavailable: "Non presente su questo Mac",
            repeats: "Ripeti",
            once: "Una volta",
            timesFormat: "%d volte",
            sourceSystem: "Avvisi di macOS",
            sourceTones: "Toni Apple",
            sourceYours: "I tuoi suoni",
            addSound: "Aggiungi suono…",
            quietWhileSharing: "Silenzio durante condivisione schermo o chiamate",
            quietWhileSharingCaption: "Nessun suono mentre lo schermo è condiviso o registrato, o un’app usa un microfono.",
            onlyWhenAway: "Solo quando non stai guardando",
            onlyWhenAwayCaption: "I suoni di un agente suonano solo quando il suo terminale o la sua app non è in primo piano.",
            playOn: "Riproduci su",
            outputCurrent: "Uscita attuale",
            outputAlerts: "Dispositivo avvisi")
        case .ja: return SoundStrings(
            title: "サウンド",
            caption: "どの場面で音を鳴らすか、どの音をどの音量で鳴らすかを選びます。100%を超えると音が増幅されます。",
            playSounds: "サウンドを再生",
            sound: "サウンド",
            volume: "音量",
            play: "再生",
            unavailable: "このMacにはありません",
            repeats: "繰り返し",
            once: "1回",
            timesFormat: "%d回",
            sourceSystem: "macOSの通知音",
            sourceTones: "Appleのトーン",
            sourceYours: "自分のサウンド",
            addSound: "サウンドを追加…",
            quietWhileSharing: "画面共有中や通話中は鳴らさない",
            quietWhileSharingCaption: "画面の共有や収録中、またはアプリがマイクを使用中はサウンドを鳴らしません。",
            onlyWhenAway: "見ていないときだけ",
            onlyWhenAwayCaption: "エージェントのターミナルやアプリが前面にないときだけ、そのサウンドを鳴らします。",
            playOn: "サウンドの出力先",
            outputCurrent: "現在の出力",
            outputAlerts: "警告音の装置")
        case .ko: return SoundStrings(
            title: "사운드",
            caption: "어떤 순간에 소리를 낼지, 어떤 소리를 얼마나 크게 낼지 선택하세요. 100%를 넘으면 소리가 증폭됩니다.",
            playSounds: "사운드 재생",
            sound: "사운드",
            volume: "음량",
            play: "재생",
            unavailable: "이 Mac에 없음",
            repeats: "반복",
            once: "1회",
            timesFormat: "%d회",
            sourceSystem: "macOS 알림음",
            sourceTones: "Apple 톤",
            sourceYours: "내 사운드",
            addSound: "사운드 추가…",
            quietWhileSharing: "화면 공유 중이나 통화 중에는 조용히",
            quietWhileSharingCaption: "화면을 공유하거나 녹화하는 중, 또는 앱이 마이크를 사용하는 중에는 소리를 내지 않습니다.",
            onlyWhenAway: "보고 있지 않을 때만",
            onlyWhenAwayCaption: "에이전트의 터미널이나 앱이 앞에 있지 않을 때만 소리를 냅니다.",
            playOn: "소리 재생 위치",
            outputCurrent: "현재 출력",
            outputAlerts: "경고음 기기")
        case .uk: return SoundStrings(
            title: "Звуки",
            caption: "Виберіть, які моменти звучать, яким звуком і наскільки гучно. Понад 100% звук підсилюється.",
            playSounds: "Відтворювати звуки",
            sound: "Звук",
            volume: "Гучність",
            play: "Відтворити",
            unavailable: "Немає на цьому Mac",
            repeats: "Повтор",
            once: "Один раз",
            timesFormat: "%d рази",
            sourceSystem: "Сигнали macOS",
            sourceTones: "Мелодії Apple",
            sourceYours: "Ваші звуки",
            addSound: "Додати звук…",
            quietWhileSharing: "Тиша під час показу екрана чи дзвінка",
            quietWhileSharingCaption: "Без звуків, поки екран транслюється чи записується або програма використовує мікрофон.",
            onlyWhenAway: "Лише коли ви не дивитеся",
            onlyWhenAwayCaption: "Звуки агента грають, лише коли його термінал чи програма не на передньому плані.",
            playOn: "Відтворювати на",
            outputCurrent: "Поточний вихід",
            outputAlerts: "Пристрій для сигналів")
        case .zhHans: return SoundStrings(
            title: "声音",
            caption: "选择哪些时刻发出声音、用什么声音以及音量多大。超过 100% 时声音会被增强。",
            playSounds: "播放声音",
            sound: "声音",
            volume: "音量",
            play: "播放",
            unavailable: "此 Mac 上没有",
            repeats: "重复",
            once: "一次",
            timesFormat: "%d 次",
            sourceSystem: "macOS 提示音",
            sourceTones: "Apple 铃声",
            sourceYours: "你的声音",
            addSound: "添加声音…",
            quietWhileSharing: "共享屏幕或通话时静音",
            quietWhileSharingCaption: "屏幕正在共享或录制，或有应用在使用麦克风时，不播放声音。",
            onlyWhenAway: "仅在你没在看时",
            onlyWhenAwayCaption: "仅当智能体的终端或应用不在最前面时，才播放它的声音。",
            playOn: "声音播放位置",
            outputCurrent: "当前输出",
            outputAlerts: "提醒声音设备")
        case .zhTW: return SoundStrings(
            title: "聲音",
            caption: "選擇哪些時刻發出聲音、使用什麼聲音以及音量大小。超過 100% 時聲音會被增強。",
            playSounds: "播放聲音",
            sound: "聲音",
            volume: "音量",
            play: "播放",
            unavailable: "此 Mac 上沒有",
            repeats: "重複",
            once: "一次",
            timesFormat: "%d 次",
            sourceSystem: "macOS 提示聲",
            sourceTones: "Apple 鈴聲",
            sourceYours: "你的聲音",
            addSound: "加入聲音…",
            quietWhileSharing: "分享螢幕或通話時靜音",
            quietWhileSharingCaption: "螢幕正在分享或錄製，或有 App 正在使用麥克風時，不播放聲音。",
            onlyWhenAway: "只在你沒在看時",
            onlyWhenAwayCaption: "只有當代理的終端機或 App 不在最前面時，才播放它的聲音。",
            playOn: "聲音播放位置",
            outputCurrent: "目前輸出",
            outputAlerts: "提示聲音裝置")
        case .zhHK: return SoundStrings(
            title: "聲音",
            caption: "選擇哪些時刻發出聲音、用甚麼聲音及音量大小。超過 100% 時聲音會被增強。",
            playSounds: "播放聲音",
            sound: "聲音",
            volume: "音量",
            play: "播放",
            unavailable: "此 Mac 上沒有",
            repeats: "重複",
            once: "一次",
            timesFormat: "%d 次",
            sourceSystem: "macOS 提示聲",
            sourceTones: "Apple 鈴聲",
            sourceYours: "你的聲音",
            addSound: "加入聲音…",
            quietWhileSharing: "分享螢幕或通話時靜音",
            quietWhileSharingCaption: "螢幕正在分享或錄製，或有 App 正在使用咪高峰時，不播放聲音。",
            onlyWhenAway: "只在你沒在看時",
            onlyWhenAwayCaption: "只有當代理的終端機或 App 不在最前面時，才播放它的聲音。",
            playOn: "聲音播放位置",
            outputCurrent: "目前輸出",
            outputAlerts: "提示聲音裝置")
        }
    }
}
