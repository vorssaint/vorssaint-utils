// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

extension FeatureStrings {
    /// The screenshot and screen recording section of the Sounds page.
    static func captureSounds(_ language: AppLanguage) -> SoundGroupStrings {
        switch language {
        case .enUS: return SoundGroupStrings(
            title: "Screen capture",
            note: nil,
            moments: [
                .screenshotTaken: SoundMoment(title: "Screenshot taken",
                                              caption: "When a screenshot is captured, in any mode."),
                .recordingStarted: SoundMoment(title: "Recording started",
                                               caption: "When a screen recording begins."),
                .recordingStopped: SoundMoment(title: "Recording saved",
                                               caption: "When a screen recording stops and its video is kept."),
            ])
        case .ptBR: return SoundGroupStrings(
            title: "Captura de tela",
            note: nil,
            moments: [
                .screenshotTaken: SoundMoment(title: "Captura de tela feita",
                                              caption: "Quando uma captura de tela é feita, em qualquer modo."),
                .recordingStarted: SoundMoment(title: "Gravação iniciada",
                                               caption: "Quando uma gravação de tela começa."),
                .recordingStopped: SoundMoment(title: "Gravação salva",
                                               caption: "Quando uma gravação de tela termina e o vídeo é mantido."),
            ])
        case .tr: return SoundGroupStrings(
            title: "Ekran yakalama",
            note: nil,
            moments: [
                .screenshotTaken: SoundMoment(title: "Ekran görüntüsü alındı",
                                              caption: "Herhangi bir modda ekran görüntüsü alındığında."),
                .recordingStarted: SoundMoment(title: "Kayıt başladı",
                                               caption: "Bir ekran kaydı başladığında."),
                .recordingStopped: SoundMoment(title: "Kayıt kaydedildi",
                                               caption: "Bir ekran kaydı durup videosu saklandığında."),
            ])
        case .ru: return SoundGroupStrings(
            title: "Снимки и запись экрана",
            note: nil,
            moments: [
                .screenshotTaken: SoundMoment(title: "Снимок экрана сделан",
                                              caption: "Когда сделан снимок экрана, в любом режиме."),
                .recordingStarted: SoundMoment(title: "Запись началась",
                                               caption: "Когда начинается запись экрана."),
                .recordingStopped: SoundMoment(title: "Запись сохранена",
                                               caption: "Когда запись экрана остановлена и видео сохранено."),
            ])
        case .es: return SoundGroupStrings(
            title: "Captura de pantalla",
            note: nil,
            moments: [
                .screenshotTaken: SoundMoment(title: "Captura realizada",
                                              caption: "Cuando se hace una captura de pantalla, en cualquier modo."),
                .recordingStarted: SoundMoment(title: "Grabación iniciada",
                                               caption: "Cuando empieza una grabación de pantalla."),
                .recordingStopped: SoundMoment(title: "Grabación guardada",
                                               caption: "Cuando una grabación de pantalla se detiene y su vídeo se conserva."),
            ])
        case .sk: return SoundGroupStrings(
            title: "Snímanie obrazovky",
            note: nil,
            moments: [
                .screenshotTaken: SoundMoment(title: "Snímka obrazovky",
                                              caption: "Keď sa zachytí snímka obrazovky, v ľubovoľnom režime."),
                .recordingStarted: SoundMoment(title: "Nahrávanie začalo",
                                               caption: "Keď sa začne nahrávanie obrazovky."),
                .recordingStopped: SoundMoment(title: "Nahrávka uložená",
                                               caption: "Keď sa nahrávanie obrazovky zastaví a video sa ponechá."),
            ])
        case .de: return SoundGroupStrings(
            title: "Bildschirmaufnahme",
            note: nil,
            moments: [
                .screenshotTaken: SoundMoment(title: "Bildschirmfoto aufgenommen",
                                              caption: "Wenn ein Bildschirmfoto aufgenommen wird, in jedem Modus."),
                .recordingStarted: SoundMoment(title: "Aufnahme gestartet",
                                               caption: "Wenn eine Bildschirmaufnahme beginnt."),
                .recordingStopped: SoundMoment(title: "Aufnahme gesichert",
                                               caption: "Wenn eine Bildschirmaufnahme endet und ihr Video behalten wird."),
            ])
        case .fr: return SoundGroupStrings(
            title: "Capture d’écran",
            note: nil,
            moments: [
                .screenshotTaken: SoundMoment(title: "Capture d’écran prise",
                                              caption: "Quand une capture d’écran est prise, dans n’importe quel mode."),
                .recordingStarted: SoundMoment(title: "Enregistrement démarré",
                                               caption: "Quand un enregistrement de l’écran commence."),
                .recordingStopped: SoundMoment(title: "Enregistrement sauvegardé",
                                               caption: "Quand un enregistrement de l’écran s’arrête et que sa vidéo est conservée."),
            ])
        case .it: return SoundGroupStrings(
            title: "Cattura schermo",
            note: nil,
            moments: [
                .screenshotTaken: SoundMoment(title: "Istantanea scattata",
                                              caption: "Quando viene catturata un’istantanea dello schermo, in qualsiasi modalità."),
                .recordingStarted: SoundMoment(title: "Registrazione avviata",
                                               caption: "Quando inizia una registrazione dello schermo."),
                .recordingStopped: SoundMoment(title: "Registrazione salvata",
                                               caption: "Quando una registrazione dello schermo si ferma e il video viene tenuto."),
            ])
        case .ja: return SoundGroupStrings(
            title: "画面キャプチャ",
            note: nil,
            moments: [
                .screenshotTaken: SoundMoment(title: "スクリーンショットを撮影",
                                              caption: "どのモードでも、スクリーンショットを撮ったとき。"),
                .recordingStarted: SoundMoment(title: "収録を開始",
                                               caption: "画面収録が始まったとき。"),
                .recordingStopped: SoundMoment(title: "収録を保存",
                                               caption: "画面収録が止まり、ビデオが残されたとき。"),
            ])
        case .ko: return SoundGroupStrings(
            title: "화면 캡처",
            note: nil,
            moments: [
                .screenshotTaken: SoundMoment(title: "스크린샷 촬영",
                                              caption: "어떤 모드에서든 스크린샷을 찍었을 때."),
                .recordingStarted: SoundMoment(title: "녹화 시작",
                                               caption: "화면 녹화가 시작될 때."),
                .recordingStopped: SoundMoment(title: "녹화 저장",
                                               caption: "화면 녹화가 멈추고 비디오가 보관될 때."),
            ])
        case .uk: return SoundGroupStrings(
            title: "Знімки та запис екрана",
            note: nil,
            moments: [
                .screenshotTaken: SoundMoment(title: "Знімок екрана зроблено",
                                              caption: "Коли зроблено знімок екрана, у будь-якому режимі."),
                .recordingStarted: SoundMoment(title: "Запис почався",
                                               caption: "Коли починається запис екрана."),
                .recordingStopped: SoundMoment(title: "Запис збережено",
                                               caption: "Коли запис екрана зупинено і відео збережено."),
            ])
        case .zhHans: return SoundGroupStrings(
            title: "屏幕捕捉",
            note: nil,
            moments: [
                .screenshotTaken: SoundMoment(title: "已截屏",
                                              caption: "以任何模式截取屏幕快照时。"),
                .recordingStarted: SoundMoment(title: "录制已开始",
                                               caption: "屏幕录制开始时。"),
                .recordingStopped: SoundMoment(title: "录制已存储",
                                               caption: "屏幕录制停止并保留视频时。"),
            ])
        case .zhTW: return SoundGroupStrings(
            title: "螢幕擷取",
            note: nil,
            moments: [
                .screenshotTaken: SoundMoment(title: "已截圖",
                                              caption: "以任何模式擷取螢幕快照時。"),
                .recordingStarted: SoundMoment(title: "錄製已開始",
                                               caption: "螢幕錄製開始時。"),
                .recordingStopped: SoundMoment(title: "錄製已儲存",
                                               caption: "螢幕錄製停止並保留影片時。"),
            ])
        case .zhHK: return SoundGroupStrings(
            title: "螢幕擷取",
            note: nil,
            moments: [
                .screenshotTaken: SoundMoment(title: "已截圖",
                                              caption: "以任何模式擷取螢幕快照時。"),
                .recordingStarted: SoundMoment(title: "錄影已開始",
                                               caption: "螢幕錄影開始時。"),
                .recordingStopped: SoundMoment(title: "錄影已儲存",
                                               caption: "螢幕錄影停止並保留影片時。"),
            ])
        }
    }
}
