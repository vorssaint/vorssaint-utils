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
            ])
        case .ptBR: return SoundGroupStrings(
            title: "Captura de tela",
            note: nil,
            moments: [
                .screenshotTaken: SoundMoment(title: "Captura de tela feita",
                                              caption: "Quando uma captura de tela é feita, em qualquer modo."),
            ])
        case .tr: return SoundGroupStrings(
            title: "Ekran yakalama",
            note: nil,
            moments: [
                .screenshotTaken: SoundMoment(title: "Ekran görüntüsü alındı",
                                              caption: "Herhangi bir modda ekran görüntüsü alındığında."),
            ])
        case .ru: return SoundGroupStrings(
            title: "Снимки и запись экрана",
            note: nil,
            moments: [
                .screenshotTaken: SoundMoment(title: "Снимок экрана сделан",
                                              caption: "Когда сделан снимок экрана, в любом режиме."),
            ])
        case .es: return SoundGroupStrings(
            title: "Captura de pantalla",
            note: nil,
            moments: [
                .screenshotTaken: SoundMoment(title: "Captura realizada",
                                              caption: "Cuando se hace una captura de pantalla, en cualquier modo."),
            ])
        case .sk: return SoundGroupStrings(
            title: "Snímanie obrazovky",
            note: nil,
            moments: [
                .screenshotTaken: SoundMoment(title: "Snímka obrazovky",
                                              caption: "Keď sa zachytí snímka obrazovky, v ľubovoľnom režime."),
            ])
        case .de: return SoundGroupStrings(
            title: "Bildschirmaufnahme",
            note: nil,
            moments: [
                .screenshotTaken: SoundMoment(title: "Bildschirmfoto aufgenommen",
                                              caption: "Wenn ein Bildschirmfoto aufgenommen wird, in jedem Modus."),
            ])
        case .fr: return SoundGroupStrings(
            title: "Capture d’écran",
            note: nil,
            moments: [
                .screenshotTaken: SoundMoment(title: "Capture d’écran prise",
                                              caption: "Quand une capture d’écran est prise, dans n’importe quel mode."),
            ])
        case .it: return SoundGroupStrings(
            title: "Cattura schermo",
            note: nil,
            moments: [
                .screenshotTaken: SoundMoment(title: "Istantanea scattata",
                                              caption: "Quando viene catturata un’istantanea dello schermo, in qualsiasi modalità."),
            ])
        case .ja: return SoundGroupStrings(
            title: "画面キャプチャ",
            note: nil,
            moments: [
                .screenshotTaken: SoundMoment(title: "スクリーンショットを撮影",
                                              caption: "どのモードでも、スクリーンショットを撮ったとき。"),
            ])
        case .ko: return SoundGroupStrings(
            title: "화면 캡처",
            note: nil,
            moments: [
                .screenshotTaken: SoundMoment(title: "스크린샷 촬영",
                                              caption: "어떤 모드에서든 스크린샷을 찍었을 때."),
            ])
        case .uk: return SoundGroupStrings(
            title: "Знімки та запис екрана",
            note: nil,
            moments: [
                .screenshotTaken: SoundMoment(title: "Знімок екрана зроблено",
                                              caption: "Коли зроблено знімок екрана, у будь-якому режимі."),
            ])
        case .zhHans: return SoundGroupStrings(
            title: "屏幕捕捉",
            note: nil,
            moments: [
                .screenshotTaken: SoundMoment(title: "已截屏",
                                              caption: "以任何模式截取屏幕快照时。"),
            ])
        case .zhTW: return SoundGroupStrings(
            title: "螢幕擷取",
            note: nil,
            moments: [
                .screenshotTaken: SoundMoment(title: "已截圖",
                                              caption: "以任何模式擷取螢幕快照時。"),
            ])
        case .zhHK: return SoundGroupStrings(
            title: "螢幕擷取",
            note: nil,
            moments: [
                .screenshotTaken: SoundMoment(title: "已截圖",
                                              caption: "以任何模式擷取螢幕快照時。"),
            ])
        }
    }
}
