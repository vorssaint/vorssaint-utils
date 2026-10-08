// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

struct NotchLockScreenStrings {
    /// The name System Settings gives its own Lock Screen pane.
    let title: String
    let show: String
    let showHint: String
    let sounds: String
    let soundsHint: String
    /// Beside the names of the agents working while the Mac is locked.
    let working: String
    /// The card for Mission Control, which otherwise hides the island.
    let missionControlTitle: String
    let missionControl: String
    let missionControlHint: String
    let screenSaver: String
    let screenSaverHint: String
}

extension FeatureStrings {
    static func notchLockScreen(_ language: AppLanguage) -> NotchLockScreenStrings {
        switch language {
        case .enUS: return NotchLockScreenStrings(
            title: "Lock Screen",
            show: "Show on the Lock Screen",
            showHint: "Music and the Dynamic Island’s activities, like a timer, AI agents, downloads and your next event, appear above the password field. Anyone who can see your screen can read them.",
            sounds: "Lock and unlock sounds",
            soundsHint: "Play the macOS padlock sound when your Mac locks and unlocks.",
            working: "Working",
            missionControlTitle: "Mission Control",
            missionControl: "Show in Mission Control",
            missionControlHint: "Dynamic Island stays at the top of the screen in Mission Control and App Exposé. As on the Lock Screen, it only shows its status and doesn’t open. It can cover the names of your desktops.",
            screenSaver: "Show on the screen saver",
            screenSaverHint: "When your Mac locks as the screen saver starts, music and the Dynamic Island’s activities appear over it, as on the Lock Screen. A screen saver that leaves your Mac unlocked shows nothing.")
        case .ptBR: return NotchLockScreenStrings(
            title: "Tela Bloqueada",
            show: "Mostrar na Tela Bloqueada",
            showHint: "A música e as atividades do Dynamic Island, como temporizador, agentes de IA, downloads e o próximo compromisso, aparecem acima do campo de senha. Quem puder ver sua tela também poderá lê-las.",
            sounds: "Sons ao bloquear e desbloquear",
            soundsHint: "Toca o som de cadeado do macOS quando o Mac é bloqueado e desbloqueado.",
            working: "Trabalhando",
            missionControlTitle: "Mission Control",
            missionControl: "Mostrar no Mission Control",
            missionControlHint: "O Dynamic Island fica no topo da tela no Mission Control e no Exposé do app. Como na Tela Bloqueada, ele só mostra o status e não se abre. Ele pode cobrir os nomes das suas mesas.",
            screenSaver: "Mostrar no protetor de tela",
            screenSaverHint: "Quando o Mac é bloqueado ao iniciar o protetor de tela, a música e as atividades do Dynamic Island aparecem sobre ele, como na Tela Bloqueada. Um protetor de tela que deixa o Mac desbloqueado não mostra nada.")
        case .es: return NotchLockScreenStrings(
            title: "Pantalla de bloqueo",
            show: "Mostrar en la pantalla de bloqueo",
            showHint: "La música y las actividades del Dynamic Island, como el temporizador, los agentes de IA, las descargas y tu próxima cita, aparecen sobre el campo de contraseña. Cualquiera que vea tu pantalla podrá leerlas.",
            sounds: "Sonidos al bloquear y desbloquear",
            soundsHint: "Reproduce el sonido de candado de macOS cuando el Mac se bloquea y se desbloquea.",
            working: "Trabajando",
            missionControlTitle: "Mission Control",
            missionControl: "Mostrar en Mission Control",
            missionControlHint: "El Dynamic Island se queda en la parte superior de la pantalla en Mission Control y Exposé de apps. Como en la pantalla de bloqueo, solo muestra su estado y no se abre. Puede tapar los nombres de tus escritorios.",
            screenSaver: "Mostrar en el salvapantallas",
            screenSaverHint: "Cuando el Mac se bloquea al iniciarse el salvapantallas, la música y las actividades del Dynamic Island aparecen sobre él, como en la pantalla de bloqueo. Un salvapantallas que deja el Mac desbloqueado no muestra nada.")
        case .sk: return NotchLockScreenStrings(
            title: "Zamknutá obrazovka",
            show: "Zobraziť na zamknutej obrazovke",
            showHint: "Hudba a aktivity Dynamic Island, ako časovač, AI agenti, sťahovanie a vaše najbližšie stretnutie, sa zobrazia nad poľom na heslo. Prečíta si ich každý, kto vidí vašu obrazovku.",
            sounds: "Zvuky pri zamknutí a odomknutí",
            soundsHint: "Prehrá zvuk zámky z macOS, keď sa Mac zamkne a odomkne.",
            working: "Pracuje",
            missionControlTitle: "Mission Control",
            missionControl: "Zobraziť v Mission Control",
            missionControlHint: "Dynamic Island zostane hore na obrazovke v Mission Control a Exposé aplikácie. Ako na zamknutej obrazovke len ukazuje stav a neotvára sa. Môže zakryť názvy vašich plôch.",
            screenSaver: "Zobraziť na šetriči obrazovky",
            screenSaverHint: "Keď sa Mac pri spustení šetriča obrazovky zamkne, hudba a aktivity Dynamic Island sa zobrazia nad ním, ako na zamknutej obrazovke. Šetrič, ktorý nechá Mac odomknutý, nezobrazí nič.")
        case .de: return NotchLockScreenStrings(
            title: "Sperrbildschirm",
            show: "Auf dem Sperrbildschirm zeigen",
            showHint: "Musik und die Aktivitäten des Dynamic Island, etwa Timer, KI-Agenten, Downloads und dein nächster Termin, erscheinen über dem Passwortfeld. Wer deinen Bildschirm sieht, kann sie lesen.",
            sounds: "Töne beim Sperren und Entsperren",
            soundsHint: "Spielt das Vorhängeschloss-Geräusch von macOS, wenn dein Mac gesperrt und entsperrt wird.",
            working: "Arbeitet",
            missionControlTitle: "Mission Control",
            missionControl: "In Mission Control zeigen",
            missionControlHint: "Das Dynamic Island bleibt in Mission Control und App-Exposé oben auf dem Bildschirm. Wie auf dem Sperrbildschirm zeigt es nur seinen Status und öffnet sich nicht. Es kann die Namen deiner Schreibtische verdecken.",
            screenSaver: "Auf dem Bildschirmschoner zeigen",
            screenSaverHint: "Wenn sich dein Mac beim Start des Bildschirmschoners sperrt, erscheinen Musik und die Aktivitäten des Dynamic Island darüber, wie auf dem Sperrbildschirm. Ein Bildschirmschoner, der den Mac entsperrt lässt, zeigt nichts.")
        case .fr: return NotchLockScreenStrings(
            title: "Écran verrouillé",
            show: "Afficher sur l’écran verrouillé",
            showHint: "La musique et les activités du Dynamic Island, comme le minuteur, les agents IA, les téléchargements et votre prochain rendez-vous, apparaissent au-dessus du champ du mot de passe. Toute personne qui voit votre écran peut les lire.",
            sounds: "Sons de verrouillage et de déverrouillage",
            soundsHint: "Joue le son de cadenas de macOS quand votre Mac se verrouille et se déverrouille.",
            working: "En cours",
            missionControlTitle: "Mission Control",
            missionControl: "Afficher dans Mission Control",
            missionControlHint: "Le Dynamic Island reste en haut de l’écran dans Mission Control et Exposé d’app. Comme sur l’écran verrouillé, il affiche seulement son état et ne s’ouvre pas. Il peut masquer le nom de vos bureaux.",
            screenSaver: "Afficher sur l’économiseur d’écran",
            screenSaverHint: "Quand votre Mac se verrouille au démarrage de l’économiseur d’écran, la musique et les activités du Dynamic Island apparaissent par-dessus, comme sur l’écran verrouillé. Un économiseur qui laisse le Mac déverrouillé n’affiche rien.")
        case .it: return NotchLockScreenStrings(
            title: "Schermata di blocco",
            show: "Mostra nella schermata di blocco",
            showHint: "La musica e le attività del Dynamic Island, come timer, agenti IA, download e il prossimo appuntamento, appaiono sopra il campo della password. Chiunque veda il tuo schermo può leggerle.",
            sounds: "Suoni di blocco e sblocco",
            soundsHint: "Riproduce il suono del lucchetto di macOS quando il Mac si blocca e si sblocca.",
            working: "Al lavoro",
            missionControlTitle: "Mission Control",
            missionControl: "Mostra in Mission Control",
            missionControlHint: "Il Dynamic Island resta in cima allo schermo in Mission Control e in Exposé app. Come nella schermata di blocco, mostra solo il suo stato e non si apre. Può coprire i nomi delle tue scrivanie.",
            screenSaver: "Mostra sul salvaschermo",
            screenSaverHint: "Quando il Mac si blocca all’avvio del salvaschermo, la musica e le attività del Dynamic Island appaiono sopra di esso, come nella schermata di blocco. Un salvaschermo che lascia il Mac sbloccato non mostra nulla.")
        case .ru: return NotchLockScreenStrings(
            title: "Экран блокировки",
            show: "Показывать на экране блокировки",
            showHint: "Музыка и активности из выреза экрана, например таймер, ИИ-агенты, загрузки и ближайшая встреча, появляются над полем пароля. Их может прочитать любой, кто видит ваш экран.",
            sounds: "Звуки блокировки и разблокировки",
            soundsHint: "Воспроизводить звук замка macOS, когда Mac блокируется и разблокируется.",
            working: "Работает",
            missionControlTitle: "Mission Control",
            missionControl: "Показывать в Mission Control",
            missionControlHint: "Вырез экрана остаётся вверху в Mission Control и Exposé приложения. Как на экране блокировки, он только показывает состояние и не открывается. Он может закрывать названия рабочих столов.",
            screenSaver: "Показывать на заставке",
            screenSaverHint: "Когда Mac блокируется при запуске заставки, музыка и активности из выреза экрана появляются поверх неё, как на экране блокировки. Заставка, при которой Mac не блокируется, ничего не показывает.")
        case .tr: return NotchLockScreenStrings(
            title: "Kilitli Ekran",
            show: "Kilitli Ekranda göster",
            showHint: "Müzik ve çentikteki etkinlikler, örneğin zamanlayıcı, YZ ajanları, indirmeler ve sıradaki randevunuz, parola alanının üstünde görünür. Ekranınızı gören herkes bunları okuyabilir.",
            sounds: "Kilitleme ve kilit açma sesleri",
            soundsHint: "Mac kilitlendiğinde ve kilidi açıldığında macOS’in asma kilit sesini çalar.",
            working: "Çalışıyor",
            missionControlTitle: "Mission Control",
            missionControl: "Mission Control’de göster",
            missionControlHint: "Çentik, Mission Control’de ve Uygulama Exposé’sinde ekranın üstünde kalır. Kilit ekranındaki gibi yalnızca durumunu gösterir ve açılmaz. Masaüstlerinizin adlarını kapatabilir.",
            screenSaver: "Ekran koruyucuda göster",
            screenSaverHint: "Mac’iniz ekran koruyucu başlarken kilitlenirse müzik ve çentikteki etkinlikler, kilit ekranındaki gibi onun üstünde görünür. Mac’i kilitlemeyen bir ekran koruyucu hiçbir şey göstermez.")
        case .ja: return NotchLockScreenStrings(
            title: "ロック画面",
            show: "ロック画面に表示",
            showHint: "音楽と、タイマー、AIエージェント、ダウンロード、次の予定などのDynamic Islandのアクティビティが、パスワード欄の上に表示されます。画面が見える人なら誰でも読めます。",
            sounds: "ロックとロック解除のサウンド",
            soundsHint: "Macがロックされたときとロックが解除されたときに、macOSの南京錠のサウンドを再生します。",
            working: "作業中",
            missionControlTitle: "Mission Control",
            missionControl: "Mission Controlに表示",
            missionControlHint: "Mission ControlとApp ExposéでもDynamic Islandが画面上部に残ります。ロック画面と同じように状態を表示するだけで、開きません。デスクトップの名前が隠れることがあります。",
            screenSaver: "スクリーンセーバに表示",
            screenSaverHint: "スクリーンセーバの開始時にMacがロックされると、ロック画面と同じように音楽とDynamic Islandのアクティビティがその上に表示されます。Macがロックされないスクリーンセーバには何も表示されません。")
        case .ko: return NotchLockScreenStrings(
            title: "잠금 화면",
            show: "잠금 화면에 표시",
            showHint: "음악과 타이머, AI 에이전트, 다운로드, 다음 일정 같은 Dynamic Island 활동이 암호 입력란 위에 나타납니다. 화면을 볼 수 있는 사람은 누구나 읽을 수 있습니다.",
            sounds: "잠금 및 잠금 해제 사운드",
            soundsHint: "Mac이 잠기거나 잠금 해제될 때 macOS의 자물쇠 사운드를 재생합니다.",
            working: "작업 중",
            missionControlTitle: "Mission Control",
            missionControl: "Mission Control에서 보기",
            missionControlHint: "Mission Control과 App Exposé에서도 Dynamic Island가 화면 상단에 남아 있습니다. 잠금 화면에서처럼 상태만 보여 주고 열리지 않습니다. 데스크탑 이름을 가릴 수 있습니다.",
            screenSaver: "화면 보호기에 보기",
            screenSaverHint: "화면 보호기가 시작될 때 Mac이 잠기면 잠금 화면에서처럼 음악과 Dynamic Island 활동이 그 위에 나타납니다. Mac을 잠그지 않는 화면 보호기에는 아무것도 표시되지 않습니다.")
        case .zhHans: return NotchLockScreenStrings(
            title: "锁屏",
            show: "在锁屏上显示",
            showHint: "音乐以及计时器、AI 智能体、下载和下一个日程等Dynamic Island活动会显示在密码栏上方。任何能看到你屏幕的人都能读到它们。",
            sounds: "锁定和解锁音效",
            soundsHint: "Mac锁定和解锁时播放macOS的挂锁音效。",
            working: "工作中",
            missionControlTitle: "调度中心",
            missionControl: "在调度中心中显示",
            missionControlHint: "在调度中心和 App Exposé 中，Dynamic Island会留在屏幕顶部。和在锁定屏幕上一样，它只显示状态，不会展开，可能会遮住桌面的名称。",
            screenSaver: "在屏幕保护程序上显示",
            screenSaverHint: "屏幕保护程序启动时如果 Mac 被锁定，音乐和Dynamic Island活动会像在锁定屏幕上一样显示在其上方。不锁定 Mac 的屏幕保护程序上不显示任何内容。")
        case .zhTW: return NotchLockScreenStrings(
            title: "鎖定畫面",
            show: "在鎖定畫面上顯示",
            showHint: "音樂以及計時器、AI 代理、下載和下一個行程等Dynamic Island活動會顯示在密碼欄位上方。任何看得到你螢幕的人都能讀到。",
            sounds: "鎖定與解鎖音效",
            soundsHint: "Mac鎖定和解鎖時播放macOS的鎖頭音效。",
            working: "工作中",
            missionControlTitle: "指揮中心",
            missionControl: "在指揮中心顯示",
            missionControlHint: "在指揮中心和 App Exposé 中，Dynamic Island會留在螢幕頂端。和在鎖定畫面上一樣，它只顯示狀態，不會展開，可能會遮住桌面的名稱。",
            screenSaver: "在螢幕保護程式上顯示",
            screenSaverHint: "螢幕保護程式啟動時如果 Mac 被鎖定，音樂和Dynamic Island活動會像在鎖定畫面上一樣顯示在其上方。不鎖定 Mac 的螢幕保護程式上不會顯示任何內容。")
        case .zhHK: return NotchLockScreenStrings(
            title: "鎖定畫面",
            show: "在鎖定畫面上顯示",
            showHint: "音樂以及計時器、AI 代理、下載和下一個行程等Dynamic Island活動會顯示在密碼欄位上方。任何看到你螢幕的人都能讀到。",
            sounds: "鎖定及解鎖音效",
            soundsHint: "Mac鎖定及解鎖時播放macOS的鎖頭音效。",
            working: "工作中",
            missionControlTitle: "指揮中心",
            missionControl: "在指揮中心顯示",
            missionControlHint: "在指揮中心和 App Exposé 中，Dynamic Island會留在螢幕頂部。和在鎖定畫面上一樣，它只顯示狀態，不會展開，可能會遮住桌面的名稱。",
            screenSaver: "在螢幕保護程式上顯示",
            screenSaverHint: "螢幕保護程式啟動時如果 Mac 被鎖定，音樂和Dynamic Island活動會像在鎖定畫面上一樣顯示在其上方。不鎖定 Mac 的螢幕保護程式上不會顯示任何內容。")
        case .uk: return NotchLockScreenStrings(
            title: "Замкнений екран",
            show: "Показувати на замкненому екрані",
            showHint: "Музика й активності Dynamic Island, як-от таймер, ШІ-агенти, завантаження та найближча подія, з’являються над полем пароля. Їх може прочитати будь-хто, хто бачить ваш екран.",
            sounds: "Звуки замикання й розмикання",
            soundsHint: "Відтворювати звук замка macOS, коли Mac замикається й розмикається.",
            working: "Працює",
            missionControlTitle: "Mission Control",
            missionControl: "Показувати в Mission Control",
            missionControlHint: "Dynamic Island лишається вгорі екрана в Mission Control і App Exposé. Як на замкненому екрані, він лише показує стан і не відкривається. Він може закривати назви ваших робочих столів.",
            screenSaver: "Показувати на заставці",
            screenSaverHint: "Коли Mac замикається під час запуску заставки, музика й активності Dynamic Island з’являються поверх неї, як на замкненому екрані. Заставка, за якої Mac лишається розімкненим, нічого не показує.")
        }
    }
}
