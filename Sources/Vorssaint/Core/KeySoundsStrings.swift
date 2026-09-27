// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

struct KeySoundsStrings {
    let title: String
    let hubDescription: String
    let enable: String
    let caption: String
    let panelCaption: String
    let active: String
    let switchSection: String
    let switchLabel: String
    let preview: String
    let noPacks: String
    let volume: String
    let feelSection: String
    let velocity: String
    let velocityCaption: String
    let sensitivity: String
    let sensorRunning: String
    let sensorUnavailable: String
    let lastHit: String
    let release: String
    let releaseCaption: String
    let muteModifiers: String
    let builtInOnly: String
    let builtInOnlyCaption: String
    let shortcutSection: String
    let shortcutEnable: String
    let shortcutTitle: String
    let shortcutFailed: String
    let credits: String
    let soft: String
    let medium: String
    let hard: String
    let slam: String

    func strength(_ strength: KeySoundStrength) -> String {
        switch strength {
        case .soft: return soft
        case .medium: return medium
        case .hard: return hard
        case .slam: return slam
        }
    }
}

extension FeatureStrings {
    static func keySounds(_ language: AppLanguage) -> KeySoundsStrings {
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

extension KeySoundsStrings {
    static let enUS = KeySoundsStrings(
        title: "Key Sounds",
        hubDescription: "Mechanical keyboard sounds as you type",
        enable: "Play key sounds",
        caption: "Plays a mechanical switch sound for every key. Space, Return, Delete, arrows and modifiers each have their own sound.",
        panelCaption: "Mechanical keyboard sounds",
        active: "Listening to the keyboard",
        switchSection: "Switch",
        switchLabel: "Switch type",
        preview: "Preview",
        noPacks: "No sound packs were found in the app.",
        volume: "Volume",
        feelSection: "Feel",
        velocity: "Velocity-sensitive",
        velocityCaption: "Uses the MacBook’s motion sensor: type harder for a louder, deeper click.",
        sensitivity: "Sensitivity",
        sensorRunning: "Motion sensor active",
        sensorUnavailable: "No motion sensor on this Mac. Every key plays at medium strength.",
        lastHit: "Last hit",
        release: "Play key release sounds",
        releaseCaption: "Only some switches include a release sound.",
        muteModifiers: "Silence modifier keys",
        builtInOnly: "Only on built-in speakers",
        builtInOnlyCaption: "Stays quiet while headphones or other outputs are in use.",
        shortcutSection: "Quick toggle",
        shortcutEnable: "Toggle with a keyboard shortcut",
        shortcutTitle: "Toggle key sounds",
        shortcutFailed: "Another app already uses this shortcut.",
        credits: "Sound packs by Mechvibes and ClickClack contributors (MIT).",
        soft: "Soft", medium: "Medium", hard: "Hard", slam: "Slam"
    )

    static let ptBR = KeySoundsStrings(
        title: "Sons de teclas",
        hubDescription: "Sons de teclado mecânico enquanto você digita",
        enable: "Tocar sons de teclas",
        caption: "Toca um som de switch mecânico a cada tecla. Espaço, Return, Delete, setas e modificadores têm som próprio.",
        panelCaption: "Sons de teclado mecânico",
        active: "Ouvindo o teclado",
        switchSection: "Switch",
        switchLabel: "Tipo de switch",
        preview: "Ouvir",
        noPacks: "Nenhum pacote de sons foi encontrado no app.",
        volume: "Volume",
        feelSection: "Sensação",
        velocity: "Sensível à força",
        velocityCaption: "Usa o sensor de movimento do MacBook: digite com mais força para um clique mais alto e grave.",
        sensitivity: "Sensibilidade",
        sensorRunning: "Sensor de movimento ativo",
        sensorUnavailable: "Este Mac não tem sensor de movimento. Todas as teclas tocam com força média.",
        lastHit: "Último toque",
        release: "Tocar som ao soltar a tecla",
        releaseCaption: "Só alguns switches incluem som de soltura.",
        muteModifiers: "Silenciar teclas modificadoras",
        builtInOnly: "Somente nos alto-falantes internos",
        builtInOnlyCaption: "Fica em silêncio com fones ou outras saídas em uso.",
        shortcutSection: "Atalho rápido",
        shortcutEnable: "Ativar/desativar com um atalho",
        shortcutTitle: "Ativar/desativar sons de teclas",
        shortcutFailed: "Outro app já usa este atalho.",
        credits: "Pacotes de sons dos colaboradores do Mechvibes e ClickClack (MIT).",
        soft: "Suave", medium: "Médio", hard: "Forte", slam: "Batida"
    )

    static let tr = KeySoundsStrings(
        title: "Tuş Sesleri",
        hubDescription: "Yazarken mekanik klavye sesleri",
        enable: "Tuş seslerini çal",
        caption: "Her tuş için mekanik switch sesi çalar. Boşluk, Return, Delete, oklar ve değiştirici tuşların kendi sesi vardır.",
        panelCaption: "Mekanik klavye sesleri",
        active: "Klavye dinleniyor",
        switchSection: "Switch",
        switchLabel: "Switch türü",
        preview: "Dinle",
        noPacks: "Uygulamada ses paketi bulunamadı.",
        volume: "Ses düzeyi",
        feelSection: "His",
        velocity: "Vuruş hassasiyeti",
        velocityCaption: "MacBook’un hareket sensörünü kullanır: daha sert yazınca daha yüksek ve tok bir tık duyulur.",
        sensitivity: "Hassasiyet",
        sensorRunning: "Hareket sensörü etkin",
        sensorUnavailable: "Bu Mac’te hareket sensörü yok. Tüm tuşlar orta güçte çalar.",
        lastHit: "Son vuruş",
        release: "Tuş bırakma seslerini çal",
        releaseCaption: "Yalnızca bazı switch’lerde bırakma sesi vardır.",
        muteModifiers: "Değiştirici tuşları sessize al",
        builtInOnly: "Yalnızca dahili hoparlörlerde",
        builtInOnlyCaption: "Kulaklık veya başka bir çıkış kullanılırken sessiz kalır.",
        shortcutSection: "Hızlı açma/kapama",
        shortcutEnable: "Klavye kısayoluyla aç/kapat",
        shortcutTitle: "Tuş seslerini aç/kapat",
        shortcutFailed: "Bu kısayolu başka bir uygulama kullanıyor.",
        credits: "Ses paketleri: Mechvibes ve ClickClack katkıda bulunanları (MIT).",
        soft: "Yumuşak", medium: "Orta", hard: "Sert", slam: "Çok sert"
    )

    static let ru = KeySoundsStrings(
        title: "Звуки клавиш",
        hubDescription: "Звуки механической клавиатуры при наборе",
        enable: "Воспроизводить звуки клавиш",
        caption: "Воспроизводит звук механического переключателя для каждой клавиши. У пробела, Return, Delete, стрелок и модификаторов свой звук.",
        panelCaption: "Звуки механической клавиатуры",
        active: "Клавиатура отслеживается",
        switchSection: "Переключатель",
        switchLabel: "Тип переключателя",
        preview: "Прослушать",
        noPacks: "В приложении не найдены наборы звуков.",
        volume: "Громкость",
        feelSection: "Ощущение",
        velocity: "Чувствительность к силе нажатия",
        velocityCaption: "Использует датчик движения MacBook: чем сильнее нажатие, тем громче и глубже щелчок.",
        sensitivity: "Чувствительность",
        sensorRunning: "Датчик движения активен",
        sensorUnavailable: "На этом Mac нет датчика движения. Все клавиши звучат со средней силой.",
        lastHit: "Последнее нажатие",
        release: "Звук отпускания клавиши",
        releaseCaption: "Звук отпускания есть только у некоторых переключателей.",
        muteModifiers: "Без звука для клавиш-модификаторов",
        builtInOnly: "Только через встроенные динамики",
        builtInOnlyCaption: "Молчит, когда используются наушники или другой выход.",
        shortcutSection: "Быстрое переключение",
        shortcutEnable: "Переключать сочетанием клавиш",
        shortcutTitle: "Включить/выключить звуки клавиш",
        shortcutFailed: "Это сочетание уже использует другое приложение.",
        credits: "Наборы звуков: участники Mechvibes и ClickClack (MIT).",
        soft: "Мягко", medium: "Средне", hard: "Сильно", slam: "Удар"
    )

    static let es = KeySoundsStrings(
        title: "Sonidos de teclas",
        hubDescription: "Sonidos de teclado mecánico mientras escribes",
        enable: "Reproducir sonidos de teclas",
        caption: "Reproduce un sonido de interruptor mecánico con cada tecla. Espacio, Return, Delete, flechas y modificadores tienen su propio sonido.",
        panelCaption: "Sonidos de teclado mecánico",
        active: "Escuchando el teclado",
        switchSection: "Interruptor",
        switchLabel: "Tipo de interruptor",
        preview: "Escuchar",
        noPacks: "No se encontraron paquetes de sonidos en la app.",
        volume: "Volumen",
        feelSection: "Sensación",
        velocity: "Sensible a la fuerza",
        velocityCaption: "Usa el sensor de movimiento del MacBook: escribe más fuerte para un clic más alto y grave.",
        sensitivity: "Sensibilidad",
        sensorRunning: "Sensor de movimiento activo",
        sensorUnavailable: "Este Mac no tiene sensor de movimiento. Todas las teclas suenan con fuerza media.",
        lastHit: "Última pulsación",
        release: "Reproducir sonido al soltar la tecla",
        releaseCaption: "Solo algunos interruptores incluyen sonido al soltar.",
        muteModifiers: "Silenciar teclas modificadoras",
        builtInOnly: "Solo en los altavoces integrados",
        builtInOnlyCaption: "Se mantiene en silencio con auriculares u otras salidas.",
        shortcutSection: "Activación rápida",
        shortcutEnable: "Activar o desactivar con un atajo",
        shortcutTitle: "Activar o desactivar sonidos de teclas",
        shortcutFailed: "Otra app ya usa este atajo.",
        credits: "Paquetes de sonidos de los colaboradores de Mechvibes y ClickClack (MIT).",
        soft: "Suave", medium: "Medio", hard: "Fuerte", slam: "Golpe"
    )

    static let sk = KeySoundsStrings(
        title: "Zvuky kláves",
        hubDescription: "Zvuky mechanickej klávesnice pri písaní",
        enable: "Prehrávať zvuky kláves",
        caption: "Pri každom klávese prehrá zvuk mechanického spínača. Medzerník, Return, Delete, šípky a modifikátory majú vlastný zvuk.",
        panelCaption: "Zvuky mechanickej klávesnice",
        active: "Klávesnica sa sleduje",
        switchSection: "Spínač",
        switchLabel: "Typ spínača",
        preview: "Vypočuť",
        noPacks: "V aplikácii sa nenašli žiadne balíky zvukov.",
        volume: "Hlasitosť",
        feelSection: "Pocit",
        velocity: "Citlivé na silu úderu",
        velocityCaption: "Používa pohybový senzor MacBooku: silnejší úder znamená hlasnejšie a hlbšie cvaknutie.",
        sensitivity: "Citlivosť",
        sensorRunning: "Pohybový senzor je aktívny",
        sensorUnavailable: "Tento Mac nemá pohybový senzor. Všetky klávesy znejú so strednou silou.",
        lastHit: "Posledný úder",
        release: "Prehrávať zvuk pustenia klávesu",
        releaseCaption: "Zvuk pustenia majú len niektoré spínače.",
        muteModifiers: "Stlmiť modifikačné klávesy",
        builtInOnly: "Iba na vstavaných reproduktoroch",
        builtInOnlyCaption: "Zostane ticho, keď sa používajú slúchadlá alebo iný výstup.",
        shortcutSection: "Rýchle prepnutie",
        shortcutEnable: "Prepínať klávesovou skratkou",
        shortcutTitle: "Zapnúť/vypnúť zvuky kláves",
        shortcutFailed: "Túto skratku už používa iná aplikácia.",
        credits: "Balíky zvukov od prispievateľov Mechvibes a ClickClack (MIT).",
        soft: "Jemne", medium: "Stredne", hard: "Silno", slam: "Úder"
    )

    static let de = KeySoundsStrings(
        title: "Tastengeräusche",
        hubDescription: "Geräusche einer mechanischen Tastatur beim Tippen",
        enable: "Tastengeräusche abspielen",
        caption: "Spielt für jede Taste den Klang eines mechanischen Schalters. Leertaste, Return, Löschen, Pfeile und Sondertasten klingen jeweils eigen.",
        panelCaption: "Geräusche einer mechanischen Tastatur",
        active: "Tastatur wird mitgehört",
        switchSection: "Schalter",
        switchLabel: "Schaltertyp",
        preview: "Anhören",
        noPacks: "In der App wurden keine Klangpakete gefunden.",
        volume: "Lautstärke",
        feelSection: "Anschlag",
        velocity: "Anschlagdynamik",
        velocityCaption: "Nutzt den Bewegungssensor des MacBook: Fester tippen ergibt einen lauteren, tieferen Klick.",
        sensitivity: "Empfindlichkeit",
        sensorRunning: "Bewegungssensor aktiv",
        sensorUnavailable: "Dieser Mac hat keinen Bewegungssensor. Alle Tasten klingen mittelstark.",
        lastHit: "Letzter Anschlag",
        release: "Klang beim Loslassen abspielen",
        releaseCaption: "Nur einige Schalter haben einen Loslass-Klang.",
        muteModifiers: "Sondertasten stumm schalten",
        builtInOnly: "Nur über die eingebauten Lautsprecher",
        builtInOnlyCaption: "Bleibt still, solange Kopfhörer oder andere Ausgänge verwendet werden.",
        shortcutSection: "Schnell umschalten",
        shortcutEnable: "Per Tastenkürzel ein- und ausschalten",
        shortcutTitle: "Tastengeräusche ein/aus",
        shortcutFailed: "Eine andere App verwendet dieses Tastenkürzel bereits.",
        credits: "Klangpakete von den Mitwirkenden an Mechvibes und ClickClack (MIT).",
        soft: "Leicht", medium: "Mittel", hard: "Fest", slam: "Hart"
    )

    static let fr = KeySoundsStrings(
        title: "Sons des touches",
        hubDescription: "Des sons de clavier mécanique pendant la frappe",
        enable: "Jouer les sons des touches",
        caption: "Joue un son d’interrupteur mécanique à chaque touche. Espace, Retour, Supprimer, flèches et modificateurs ont chacun leur son.",
        panelCaption: "Sons de clavier mécanique",
        active: "Écoute du clavier en cours",
        switchSection: "Interrupteur",
        switchLabel: "Type d’interrupteur",
        preview: "Écouter",
        noPacks: "Aucun pack de sons trouvé dans l’app.",
        volume: "Volume",
        feelSection: "Ressenti",
        velocity: "Sensible à la force de frappe",
        velocityCaption: "Utilise le capteur de mouvement du MacBook : tapez plus fort pour un clic plus fort et plus grave.",
        sensitivity: "Sensibilité",
        sensorRunning: "Capteur de mouvement actif",
        sensorUnavailable: "Ce Mac n’a pas de capteur de mouvement. Toutes les touches jouent à force moyenne.",
        lastHit: "Dernière frappe",
        release: "Jouer le son au relâchement",
        releaseCaption: "Seuls certains interrupteurs ont un son de relâchement.",
        muteModifiers: "Couper le son des touches de modification",
        builtInOnly: "Uniquement sur les haut-parleurs intégrés",
        builtInOnlyCaption: "Reste silencieux avec un casque ou une autre sortie.",
        shortcutSection: "Activation rapide",
        shortcutEnable: "Activer ou désactiver avec un raccourci",
        shortcutTitle: "Activer ou désactiver les sons des touches",
        shortcutFailed: "Une autre app utilise déjà ce raccourci.",
        credits: "Packs de sons des contributeurs de Mechvibes et ClickClack (MIT).",
        soft: "Légère", medium: "Moyenne", hard: "Forte", slam: "Frappe"
    )

    static let it = KeySoundsStrings(
        title: "Suoni dei tasti",
        hubDescription: "Suoni di tastiera meccanica mentre scrivi",
        enable: "Riproduci i suoni dei tasti",
        caption: "Riproduce il suono di uno switch meccanico a ogni tasto. Spazio, Invio, Elimina, frecce e modificatori hanno un suono proprio.",
        panelCaption: "Suoni di tastiera meccanica",
        active: "Ascolto della tastiera attivo",
        switchSection: "Switch",
        switchLabel: "Tipo di switch",
        preview: "Ascolta",
        noPacks: "Nessun pacchetto di suoni trovato nell’app.",
        volume: "Volume",
        feelSection: "Sensazione",
        velocity: "Sensibile alla forza",
        velocityCaption: "Usa il sensore di movimento del MacBook: premi più forte per un clic più forte e profondo.",
        sensitivity: "Sensibilità",
        sensorRunning: "Sensore di movimento attivo",
        sensorUnavailable: "Questo Mac non ha un sensore di movimento. Tutti i tasti suonano con forza media.",
        lastHit: "Ultimo colpo",
        release: "Riproduci il suono al rilascio",
        releaseCaption: "Solo alcuni switch includono un suono di rilascio.",
        muteModifiers: "Silenzia i tasti modificatori",
        builtInOnly: "Solo sugli altoparlanti integrati",
        builtInOnlyCaption: "Resta in silenzio con cuffie o altre uscite in uso.",
        shortcutSection: "Attivazione rapida",
        shortcutEnable: "Attiva o disattiva con un’abbreviazione",
        shortcutTitle: "Attiva o disattiva i suoni dei tasti",
        shortcutFailed: "Un’altra app usa già questa abbreviazione.",
        credits: "Pacchetti di suoni dei collaboratori di Mechvibes e ClickClack (MIT).",
        soft: "Leggero", medium: "Medio", hard: "Forte", slam: "Colpo"
    )

    static let ja = KeySoundsStrings(
        title: "キーサウンド",
        hubDescription: "入力時にメカニカルキーボードの音を鳴らします",
        enable: "キーサウンドを再生",
        caption: "キーを押すたびにメカニカルスイッチの音を鳴らします。スペース、Return、Delete、矢印、修飾キーはそれぞれ専用の音です。",
        panelCaption: "メカニカルキーボードの音",
        active: "キーボードを監視中",
        switchSection: "スイッチ",
        switchLabel: "スイッチの種類",
        preview: "試聴",
        noPacks: "アプリ内にサウンドパックが見つかりません。",
        volume: "音量",
        feelSection: "打鍵感",
        velocity: "打鍵の強さに反応",
        velocityCaption: "MacBookのモーションセンサーを使用します。強く打つほど大きく深いクリック音になります。",
        sensitivity: "感度",
        sensorRunning: "モーションセンサー動作中",
        sensorUnavailable: "このMacにはモーションセンサーがありません。すべてのキーが中程度の強さで鳴ります。",
        lastHit: "直前の打鍵",
        release: "キーを離したときの音を再生",
        releaseCaption: "離したときの音は一部のスイッチのみ対応しています。",
        muteModifiers: "修飾キーを消音",
        builtInOnly: "内蔵スピーカーのみ",
        builtInOnlyCaption: "ヘッドフォンなど他の出力を使用中は鳴りません。",
        shortcutSection: "クイック切り替え",
        shortcutEnable: "キーボードショートカットで切り替え",
        shortcutTitle: "キーサウンドのオン/オフ",
        shortcutFailed: "このショートカットは別のアプリが使用しています。",
        credits: "サウンドパック: MechvibesとClickClackの貢献者 (MIT)。",
        soft: "弱", medium: "中", hard: "強", slam: "最強"
    )

    static let ko = KeySoundsStrings(
        title: "키 사운드",
        hubDescription: "입력할 때 기계식 키보드 소리 재생",
        enable: "키 사운드 재생",
        caption: "키를 누를 때마다 기계식 스위치 소리를 재생합니다. 스페이스, Return, Delete, 화살표, 보조 키는 각각 고유한 소리를 냅니다.",
        panelCaption: "기계식 키보드 소리",
        active: "키보드 입력 감지 중",
        switchSection: "스위치",
        switchLabel: "스위치 종류",
        preview: "미리 듣기",
        noPacks: "앱에서 사운드 팩을 찾을 수 없습니다.",
        volume: "음량",
        feelSection: "타건감",
        velocity: "타건 세기 감지",
        velocityCaption: "MacBook의 모션 센서를 사용합니다. 세게 칠수록 더 크고 깊은 소리가 납니다.",
        sensitivity: "민감도",
        sensorRunning: "모션 센서 작동 중",
        sensorUnavailable: "이 Mac에는 모션 센서가 없습니다. 모든 키가 중간 세기로 재생됩니다.",
        lastHit: "마지막 타건",
        release: "키를 뗄 때 소리 재생",
        releaseCaption: "일부 스위치에만 떼는 소리가 있습니다.",
        muteModifiers: "보조 키 소리 끄기",
        builtInOnly: "내장 스피커에서만",
        builtInOnlyCaption: "헤드폰이나 다른 출력 장치를 사용할 때는 소리가 나지 않습니다.",
        shortcutSection: "빠른 전환",
        shortcutEnable: "키보드 단축키로 켜고 끄기",
        shortcutTitle: "키 사운드 켜기/끄기",
        shortcutFailed: "다른 앱이 이미 이 단축키를 사용 중입니다.",
        credits: "사운드 팩: Mechvibes 및 ClickClack 기여자 (MIT).",
        soft: "약하게", medium: "보통", hard: "강하게", slam: "매우 강하게"
    )

    static let zhHans = KeySoundsStrings(
        title: "按键音效",
        hubDescription: "打字时播放机械键盘声音",
        enable: "播放按键音效",
        caption: "每次按键都会播放机械轴的声音。空格、Return、Delete、方向键和修饰键各有专属声音。",
        panelCaption: "机械键盘声音",
        active: "正在监听键盘",
        switchSection: "轴体",
        switchLabel: "轴体类型",
        preview: "试听",
        noPacks: "App 中未找到声音包。",
        volume: "音量",
        feelSection: "手感",
        velocity: "力度感应",
        velocityCaption: "使用 MacBook 的运动传感器：敲得越重，声音越响越沉。",
        sensitivity: "灵敏度",
        sensorRunning: "运动传感器已启用",
        sensorUnavailable: "此 Mac 没有运动传感器，所有按键均以中等力度播放。",
        lastHit: "上次敲击",
        release: "播放松开按键的声音",
        releaseCaption: "只有部分轴体包含松开声音。",
        muteModifiers: "修饰键静音",
        builtInOnly: "仅使用内置扬声器",
        builtInOnlyCaption: "使用耳机或其他输出设备时保持静音。",
        shortcutSection: "快速开关",
        shortcutEnable: "使用键盘快捷键开关",
        shortcutTitle: "开关按键音效",
        shortcutFailed: "其他 App 已在使用此快捷键。",
        credits: "声音包来自 Mechvibes 与 ClickClack 贡献者（MIT）。",
        soft: "轻", medium: "中", hard: "重", slam: "猛击"
    )

    static let zhTW = KeySoundsStrings(
        title: "按鍵音效",
        hubDescription: "打字時播放機械鍵盤聲音",
        enable: "播放按鍵音效",
        caption: "每次按鍵都會播放機械軸的聲音。空白鍵、Return、Delete、方向鍵與輔助鍵各有專屬聲音。",
        panelCaption: "機械鍵盤聲音",
        active: "正在監聽鍵盤",
        switchSection: "軸體",
        switchLabel: "軸體類型",
        preview: "試聽",
        noPacks: "App 中找不到聲音包。",
        volume: "音量",
        feelSection: "手感",
        velocity: "力度感應",
        velocityCaption: "使用 MacBook 的動作感應器：敲得越重，聲音越響越沉。",
        sensitivity: "靈敏度",
        sensorRunning: "動作感應器已啟用",
        sensorUnavailable: "這台 Mac 沒有動作感應器，所有按鍵皆以中等力度播放。",
        lastHit: "上次敲擊",
        release: "播放放開按鍵的聲音",
        releaseCaption: "只有部分軸體包含放開聲音。",
        muteModifiers: "輔助鍵靜音",
        builtInOnly: "僅使用內建揚聲器",
        builtInOnlyCaption: "使用耳機或其他輸出裝置時保持靜音。",
        shortcutSection: "快速開關",
        shortcutEnable: "使用鍵盤快速鍵開關",
        shortcutTitle: "開關按鍵音效",
        shortcutFailed: "其他 App 已在使用此快速鍵。",
        credits: "聲音包來自 Mechvibes 與 ClickClack 貢獻者（MIT）。",
        soft: "輕", medium: "中", hard: "重", slam: "猛擊"
    )

    static let zhHK = KeySoundsStrings(
        title: "按鍵音效",
        hubDescription: "打字時播放機械鍵盤聲音",
        enable: "播放按鍵音效",
        caption: "每次按鍵都會播放機械軸的聲音。空白鍵、Return、Delete、方向鍵同輔助鍵各有專屬聲音。",
        panelCaption: "機械鍵盤聲音",
        active: "正在監聽鍵盤",
        switchSection: "軸體",
        switchLabel: "軸體類型",
        preview: "試聽",
        noPacks: "App 入面搵唔到聲音包。",
        volume: "音量",
        feelSection: "手感",
        velocity: "力度感應",
        velocityCaption: "使用 MacBook 的動作感應器：打得越大力，聲音越響越沉。",
        sensitivity: "靈敏度",
        sensorRunning: "動作感應器已啟用",
        sensorUnavailable: "呢部 Mac 冇動作感應器，所有按鍵都會以中等力度播放。",
        lastHit: "上次敲擊",
        release: "播放放開按鍵的聲音",
        releaseCaption: "只有部分軸體有放開聲音。",
        muteModifiers: "輔助鍵靜音",
        builtInOnly: "只用內置揚聲器",
        builtInOnlyCaption: "使用耳機或其他輸出裝置時保持靜音。",
        shortcutSection: "快速開關",
        shortcutEnable: "用鍵盤快捷鍵開關",
        shortcutTitle: "開關按鍵音效",
        shortcutFailed: "其他 App 已經用緊呢個快捷鍵。",
        credits: "聲音包來自 Mechvibes 同 ClickClack 貢獻者（MIT）。",
        soft: "輕", medium: "中", hard: "重", slam: "猛擊"
    )

    static let uk = KeySoundsStrings(
        title: "Звуки клавіш",
        hubDescription: "Звуки механічної клавіатури під час набору",
        enable: "Відтворювати звуки клавіш",
        caption: "Відтворює звук механічного перемикача для кожної клавіші. Пробіл, Return, Delete, стрілки й модифікатори мають власний звук.",
        panelCaption: "Звуки механічної клавіатури",
        active: "Клавіатура відстежується",
        switchSection: "Перемикач",
        switchLabel: "Тип перемикача",
        preview: "Прослухати",
        noPacks: "У застосунку не знайдено наборів звуків.",
        volume: "Гучність",
        feelSection: "Відчуття",
        velocity: "Чутливість до сили натискання",
        velocityCaption: "Використовує датчик руху MacBook: що сильніше натискання, то гучніше й глибше клацання.",
        sensitivity: "Чутливість",
        sensorRunning: "Датчик руху активний",
        sensorUnavailable: "На цьому Mac немає датчика руху. Усі клавіші звучать із середньою силою.",
        lastHit: "Останнє натискання",
        release: "Звук відпускання клавіші",
        releaseCaption: "Звук відпускання мають лише деякі перемикачі.",
        muteModifiers: "Без звуку для клавіш-модифікаторів",
        builtInOnly: "Лише через вбудовані динаміки",
        builtInOnlyCaption: "Мовчить, коли використовуються навушники чи інший вихід.",
        shortcutSection: "Швидке перемикання",
        shortcutEnable: "Перемикати сполученням клавіш",
        shortcutTitle: "Увімкнути/вимкнути звуки клавіш",
        shortcutFailed: "Це сполучення вже використовує інший застосунок.",
        credits: "Набори звуків: учасники Mechvibes і ClickClack (MIT).",
        soft: "М’яко", medium: "Середньо", hard: "Сильно", slam: "Удар"
    )
}
