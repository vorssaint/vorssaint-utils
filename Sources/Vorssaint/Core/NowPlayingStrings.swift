// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// Localized strings for the panel's Now Playing section. The section title is
/// not here: `RadialMenuFeatureStrings.mediaNowPlaying` already carries "Now
/// Playing" in every language, and a second copy would need a test to keep the
/// two in agreement.
struct NowPlayingFeatureStrings {
    let hubDescription: String
    let nothingPlaying: String
}

extension FeatureStrings {
    static func nowPlaying(_ language: AppLanguage) -> NowPlayingFeatureStrings {
        switch language {
        case .enUS: return .enUS
        case .ptBR: return .ptBR
        case .tr: return .tr
        case .ru: return .ru
        case .es: return .es
        case .de: return .de
        case .fr: return .fr
        case .it: return .it
        case .ja: return .ja
        case .ko: return .ko
        case .zhHans: return .zhHans
        case .zhTW: return .zhTW
        case .zhHK: return .zhHK
        }
    }
}

extension NowPlayingFeatureStrings {
    static let enUS = NowPlayingFeatureStrings(
        hubDescription: "Shows what is playing in the panel, with playback controls",
        nothingPlaying: "Nothing playing"
    )
    static let ptBR = NowPlayingFeatureStrings(
        hubDescription: "Mostra o que está tocando no painel, com controles de reprodução",
        nothingPlaying: "Nada sendo reproduzido"
    )
    static let tr = NowPlayingFeatureStrings(
        hubDescription: "Panelde ne çaldığını oynatma denetimleriyle gösterir",
        nothingPlaying: "Çalan bir şey yok"
    )
    static let ru = NowPlayingFeatureStrings(
        hubDescription: "Показывает, что воспроизводится, и добавляет кнопки управления в панель",
        nothingPlaying: "Ничего не воспроизводится"
    )
    static let es = NowPlayingFeatureStrings(
        hubDescription: "Muestra lo que se está reproduciendo en el panel, con controles de reproducción",
        nothingPlaying: "No se está reproduciendo nada"
    )
    static let de = NowPlayingFeatureStrings(
        hubDescription: "Zeigt die aktuelle Wiedergabe im Panel, mit Steuerung",
        nothingPlaying: "Keine Wiedergabe"
    )
    static let fr = NowPlayingFeatureStrings(
        hubDescription: "Affiche la lecture en cours dans le panneau, avec les commandes",
        nothingPlaying: "Aucune lecture en cours"
    )
    static let it = NowPlayingFeatureStrings(
        hubDescription: "Mostra cosa è in riproduzione nel pannello, con i controlli",
        nothingPlaying: "Nessuna riproduzione"
    )
    static let ja = NowPlayingFeatureStrings(
        hubDescription: "パネルに再生中の項目と再生コントロールを表示します",
        nothingPlaying: "再生中の項目はありません"
    )
    static let ko = NowPlayingFeatureStrings(
        hubDescription: "패널에 재생 중인 항목과 재생 컨트롤을 표시합니다",
        nothingPlaying: "재생 중인 항목 없음"
    )
    static let zhHans = NowPlayingFeatureStrings(
        hubDescription: "在面板中显示正在播放的内容和播放控件",
        nothingPlaying: "没有正在播放的内容"
    )
    static let zhTW = NowPlayingFeatureStrings(
        hubDescription: "在面板中顯示正在播放的項目與播放控制項",
        nothingPlaying: "沒有正在播放的項目"
    )
    static let zhHK = NowPlayingFeatureStrings(
        hubDescription: "在面板中顯示正在播放的項目與播放控制項",
        nothingPlaying: "沒有正在播放的項目"
    )
}
