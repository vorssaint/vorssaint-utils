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
        playerOnlyCaption: "Play/Pause, Next and Previous control the open music app, such as Spotify or Music, instead of a browser tab. Without a music app open, the keys work as usual. Requires Accessibility; macOS asks once to let Vorssaint control the player.")
    static let ptBR = MediaKeyStrings(
        playerOnlyTitle: "Enviar as teclas de reprodução ao player de música",
        playerOnlyCaption: "Reproduzir/Pausar, Próxima e Anterior controlam o app de música aberto, como Spotify ou Música, em vez de uma aba do navegador. Sem um app de música aberto, as teclas funcionam como sempre. Requer Acessibilidade; o macOS pergunta uma vez se o Vorssaint pode controlar o player.")
    static let es = MediaKeyStrings(
        playerOnlyTitle: "Enviar las teclas de reproducción al reproductor de música",
        playerOnlyCaption: "Reproducir/Pausa, Siguiente y Anterior controlan la app de música abierta, como Spotify o Música, en lugar de una pestaña del navegador. Sin una app de música abierta, las teclas funcionan como siempre. Requiere Accesibilidad; macOS pregunta una vez si Vorssaint puede controlar el reproductor.")
    static let de = MediaKeyStrings(
        playerOnlyTitle: "Wiedergabetasten an den Musikplayer senden",
        playerOnlyCaption: "Wiedergabe/Pause, Weiter und Zurück steuern die geöffnete Musik-App, etwa Spotify oder Musik, statt eines Browser-Tabs. Ohne geöffnete Musik-App funktionieren die Tasten wie gewohnt. Erfordert Bedienungshilfen; macOS fragt einmal, ob Vorssaint den Player steuern darf.")
    static let fr = MediaKeyStrings(
        playerOnlyTitle: "Envoyer les touches de lecture au lecteur de musique",
        playerOnlyCaption: "Lecture/Pause, Suivant et Précédent contrôlent l’app de musique ouverte, comme Spotify ou Musique, plutôt qu’un onglet du navigateur. Sans app de musique ouverte, les touches fonctionnent comme d’habitude. Nécessite l’accessibilité ; macOS demande une fois si Vorssaint peut contrôler le lecteur.")
    static let it = MediaKeyStrings(
        playerOnlyTitle: "Invia i tasti di riproduzione al player musicale",
        playerOnlyCaption: "Riproduci/Pausa, Successivo e Precedente controllano l’app musicale aperta, come Spotify o Musica, invece di una scheda del browser. Senza un’app musicale aperta, i tasti funzionano come sempre. Richiede Accessibilità; macOS chiede una volta se Vorssaint può controllare il player.")
    static let ru = MediaKeyStrings(
        playerOnlyTitle: "Отправлять клавиши воспроизведения музыкальному плееру",
        playerOnlyCaption: "Воспроизведение/пауза, «Далее» и «Назад» управляют открытым музыкальным приложением, например Spotify или «Музыкой», а не вкладкой браузера. Если музыкальное приложение не открыто, клавиши работают как обычно. Требуется доступ к универсальному доступу; macOS один раз спросит, может ли Vorssaint управлять плеером.")
    static let tr = MediaKeyStrings(
        playerOnlyTitle: "Oynatma tuşlarını müzik oynatıcıya gönder",
        playerOnlyCaption: "Oynat/Duraklat, Sonraki ve Önceki tuşları bir tarayıcı sekmesi yerine Spotify veya Müzik gibi açık müzik uygulamasını denetler. Açık bir müzik uygulaması yoksa tuşlar her zamanki gibi çalışır. Erişilebilirlik gerektirir; macOS, Vorssaint’in oynatıcıyı denetlemesine izin vermek için bir kez sorar.")
    static let ja = MediaKeyStrings(
        playerOnlyTitle: "再生キーを音楽プレーヤーに送る",
        playerOnlyCaption: "再生/一時停止、次へ、前へのキーで、ブラウザのタブではなく Spotify やミュージックなど開いている音楽アプリを操作します。音楽アプリが開いていないときは通常どおり動作します。アクセシビリティが必要です。Vorssaint がプレーヤーを操作することを macOS が一度だけ確認します。")
    static let ko = MediaKeyStrings(
        playerOnlyTitle: "재생 키를 음악 플레이어로 보내기",
        playerOnlyCaption: "재생/일시 정지, 다음, 이전 키가 브라우저 탭 대신 Spotify나 음악 같은 열려 있는 음악 앱을 제어합니다. 음악 앱이 열려 있지 않으면 키가 평소처럼 작동합니다. 손쉬운 사용 권한이 필요하며, macOS가 Vorssaint의 플레이어 제어 허용 여부를 한 번 묻습니다.")
    static let zhHans = MediaKeyStrings(
        playerOnlyTitle: "将播放键发送到音乐播放器",
        playerOnlyCaption: "播放/暂停、下一首和上一首将控制已打开的音乐 App（如 Spotify 或音乐），而不是浏览器标签页。未打开音乐 App 时，这些键照常工作。需要辅助功能权限；macOS 会询问一次是否允许 Vorssaint 控制播放器。")
    static let zhTW = MediaKeyStrings(
        playerOnlyTitle: "將播放鍵傳送到音樂播放器",
        playerOnlyCaption: "播放／暫停、下一首和上一首會控制已開啟的音樂 App（例如 Spotify 或音樂），而不是瀏覽器分頁。未開啟音樂 App 時，按鍵會照常運作。需要輔助使用權限；macOS 會詢問一次是否允許 Vorssaint 控制播放器。")
    static let zhHK = MediaKeyStrings(
        playerOnlyTitle: "將播放鍵傳送到音樂播放器",
        playerOnlyCaption: "播放／暫停、下一首和上一首會控制已開啟的音樂 App（例如 Spotify 或音樂），而不是瀏覽器分頁。未開啟音樂 App 時，按鍵會照常運作。需要輔助使用權限；macOS 會詢問一次是否允許 Vorssaint 控制播放器。")
}
