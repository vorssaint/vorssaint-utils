// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

struct MediaKeyStrings {
    let playerOnlyTitle: String
    let playerOnlyCaption: String
}

extension FeatureStrings {
    static func mediaKeys(_ language: AppLanguage) -> MediaKeyStrings {
        switch language {
        case .enUS: return .enUS
        case .ptBR: return .ptBR
        case .es: return .es
        case .de: return .de
        case .fr: return .fr
        case .it: return .it
        case .sk: return .sk
        case .uk: return .uk
        case .ru: return .ru
        case .tr: return .tr
        case .ja: return .ja
        case .ko: return .ko
        case .zhHans: return .zhHans
        case .zhTW: return .zhTW
        case .zhHK: return .zhHK
        }
    }
}

extension MediaKeyStrings {
    static let enUS = MediaKeyStrings(
        playerOnlyTitle: "Send playback keys to the music player",
        playerOnlyCaption: "Play/Pause, Next and Previous control the open music app instead of a browser tab. The keys work as usual when no music app is open, or while another app plays sound and the music app is paused. Requires Accessibility; macOS asks once to let Vorssaint control the player.")
    static let ptBR = MediaKeyStrings(
        playerOnlyTitle: "Enviar as teclas de reprodução ao player de música",
        playerOnlyCaption: "Reproduzir/Pausar, Próxima e Anterior controlam o app de música aberto em vez de uma aba do navegador. As teclas funcionam como sempre quando não há um app de música aberto, ou enquanto outro app toca som e o app de música está pausado. Requer Acessibilidade; o macOS pergunta uma vez se o Vorssaint pode controlar o player.")
    static let es = MediaKeyStrings(
        playerOnlyTitle: "Enviar las teclas de reproducción al reproductor de música",
        playerOnlyCaption: "Reproducir/Pausa, Siguiente y Anterior controlan la app de música abierta en lugar de una pestaña del navegador. Las teclas funcionan como siempre cuando no hay una app de música abierta, o mientras otra app reproduce sonido y la de música está en pausa. Requiere Accesibilidad; macOS pregunta una vez si Vorssaint puede controlar el reproductor.")
    static let de = MediaKeyStrings(
        playerOnlyTitle: "Wiedergabetasten an den Musikplayer senden",
        playerOnlyCaption: "Wiedergabe/Pause, Weiter und Zurück steuern die geöffnete Musik-App statt eines Browser-Tabs. Ohne geöffnete Musik-App, oder solange eine andere App Ton wiedergibt und die Musik-App pausiert ist, funktionieren die Tasten wie gewohnt. Erfordert Bedienungshilfen; macOS fragt einmal, ob Vorssaint den Player steuern darf.")
    static let fr = MediaKeyStrings(
        playerOnlyTitle: "Envoyer les touches de lecture au lecteur de musique",
        playerOnlyCaption: "Lecture/Pause, Suivant et Précédent contrôlent l’app de musique ouverte plutôt qu’un onglet du navigateur. Les touches fonctionnent comme d’habitude sans app de musique ouverte, ou pendant qu’une autre app émet du son et que l’app de musique est en pause. Nécessite l’accessibilité ; macOS demande une fois si Vorssaint peut contrôler le lecteur.")
    static let it = MediaKeyStrings(
        playerOnlyTitle: "Invia i tasti di riproduzione al player musicale",
        playerOnlyCaption: "Riproduci/Pausa, Successivo e Precedente controllano l’app musicale aperta invece di una scheda del browser. I tasti funzionano come sempre senza un’app musicale aperta, o mentre un’altra app riproduce audio e l’app musicale è in pausa. Richiede Accessibilità; macOS chiede una volta se Vorssaint può controllare il player.")
    static let ru = MediaKeyStrings(
        playerOnlyTitle: "Отправлять клавиши воспроизведения музыкальному плееру",
        playerOnlyCaption: "Воспроизведение/пауза, «Далее» и «Назад» управляют открытым музыкальным приложением, а не вкладкой браузера. Клавиши работают как обычно, если музыкальное приложение не открыто или пока другое приложение воспроизводит звук, а музыкальное стоит на паузе. Требуется универсальный доступ; macOS один раз спросит, может ли Vorssaint управлять плеером.")
    static let tr = MediaKeyStrings(
        playerOnlyTitle: "Oynatma tuşlarını müzik oynatıcıya gönder",
        playerOnlyCaption: "Oynat/Duraklat, Sonraki ve Önceki tuşları bir tarayıcı sekmesi yerine açık müzik uygulamasını denetler. Açık bir müzik uygulaması yoksa ya da müzik uygulaması duraklatılmışken başka bir uygulama ses çalıyorsa tuşlar her zamanki gibi çalışır. Erişilebilirlik gerektirir; macOS, Vorssaint’in oynatıcıyı denetlemesine izin vermek için bir kez sorar.")
    static let ja = MediaKeyStrings(
        playerOnlyTitle: "再生キーを音楽プレーヤーに送る",
        playerOnlyCaption: "再生/一時停止、次へ、前へのキーで、ブラウザのタブではなく開いている音楽アプリを操作します。音楽アプリが開いていないとき、または音楽アプリが一時停止中にほかのアプリが音を出しているときは、通常どおり動作します。アクセシビリティが必要です。Vorssaint がプレーヤーを操作することを macOS が一度だけ確認します。")
    static let ko = MediaKeyStrings(
        playerOnlyTitle: "재생 키를 음악 플레이어로 보내기",
        playerOnlyCaption: "재생/일시 정지, 다음, 이전 키가 브라우저 탭 대신 열려 있는 음악 앱을 제어합니다. 음악 앱이 열려 있지 않거나, 음악 앱이 일시 정지된 동안 다른 앱이 소리를 내고 있으면 키가 평소처럼 작동합니다. 손쉬운 사용 권한이 필요하며, macOS가 Vorssaint의 플레이어 제어 허용 여부를 한 번 묻습니다.")
    static let zhHans = MediaKeyStrings(
        playerOnlyTitle: "将播放键发送到音乐播放器",
        playerOnlyCaption: "播放/暂停、下一首和上一首将控制已打开的音乐 App，而不是浏览器标签页。未打开音乐 App 时，或音乐 App 已暂停而其他 App 正在播放声音时，这些键照常工作。需要辅助功能权限；macOS 会询问一次是否允许 Vorssaint 控制播放器。")
    static let zhTW = MediaKeyStrings(
        playerOnlyTitle: "將播放鍵傳送到音樂播放器",
        playerOnlyCaption: "播放／暫停、下一首和上一首會控制已開啟的音樂 App，而不是瀏覽器分頁。未開啟音樂 App 時，或音樂 App 已暫停而其他 App 正在播放聲音時，按鍵會照常運作。需要輔助使用權限；macOS 會詢問一次是否允許 Vorssaint 控制播放器。")
    static let zhHK = MediaKeyStrings(
        playerOnlyTitle: "將播放鍵傳送到音樂播放器",
        playerOnlyCaption: "播放／暫停、下一首和上一首會控制已開啟的音樂 App，而不是瀏覽器分頁。未開啟音樂 App 時，或音樂 App 已暫停而其他 App 正在播放聲音時，按鍵會照常運作。需要輔助使用權限；macOS 會詢問一次是否允許 Vorssaint 控制播放器。")
    static let sk = MediaKeyStrings(
        playerOnlyTitle: "Posielať klávesy prehrávania hudobnému prehrávaču",
        playerOnlyCaption: "Prehrať/Pozastaviť, Ďalšia a Predchádzajúca ovládajú otvorenú hudobnú aplikáciu namiesto karty prehliadača. Klávesy fungujú ako zvyčajne, keď nie je otvorená hudobná aplikácia alebo keď iná aplikácia prehráva zvuk a hudba je pozastavená. Vyžaduje Prístupnosť; macOS sa raz opýta, či môže Vorssaint ovládať prehrávač.")
    static let uk = MediaKeyStrings(
        playerOnlyTitle: "Надсилати клавіші відтворення музичному програвачу",
        playerOnlyCaption: "Відтворення/Пауза, Наступний і Попередній керують відкритою музичною програмою замість вкладки браузера. Клавіші працюють як зазвичай, коли музичну програму не відкрито або коли інша програма відтворює звук, а музику призупинено. Потрібен доступ до Спеціальних можливостей; macOS один раз запитає, чи може Vorssaint керувати програвачем.")

}
