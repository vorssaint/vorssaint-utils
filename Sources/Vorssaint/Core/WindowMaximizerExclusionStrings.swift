// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

struct WindowMaximizerExclusionStrings {
    let listTitle: String
    let addButton: String
    let removeButton: String
    let caption: String
}

extension FeatureStrings {
    static func windowMaximizerExclusions(_ language: AppLanguage) -> WindowMaximizerExclusionStrings {
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
        }
    }
}

extension WindowMaximizerExclusionStrings {
    static let enUS = WindowMaximizerExclusionStrings(
        listTitle: "Keep full screen in these apps",
        addButton: "Add an app…",
        removeButton: "Remove",
        caption: "The green button keeps its macOS behavior in these apps, so games, emulators and video players can still enter full screen."
    )

    static let ptBR = WindowMaximizerExclusionStrings(
        listTitle: "Manter tela cheia nestes apps",
        addButton: "Adicionar app…",
        removeButton: "Remover",
        caption: "O botão verde mantém o comportamento do macOS nestes apps, para jogos, emuladores e players de vídeo continuarem entrando em tela cheia."
    )

    static let tr = WindowMaximizerExclusionStrings(
        listTitle: "Bu uygulamalarda tam ekranı koru",
        addButton: "Uygulama ekle…",
        removeButton: "Kaldır",
        caption: "Yeşil düğme bu uygulamalarda macOS davranışını korur; böylece oyunlar, emülatörler ve video oynatıcılar yine tam ekrana geçebilir."
    )

    static let ru = WindowMaximizerExclusionStrings(
        listTitle: "Полноэкранный режим в этих приложениях",
        addButton: "Добавить приложение…",
        removeButton: "Удалить",
        caption: "В этих приложениях зелёная кнопка работает как в macOS, поэтому игры, эмуляторы и видеоплееры по-прежнему могут переходить в полноэкранный режим."
    )

    static let es = WindowMaximizerExclusionStrings(
        listTitle: "Mantener pantalla completa en estas apps",
        addButton: "Añadir app…",
        removeButton: "Quitar",
        caption: "El botón verde conserva el comportamiento de macOS en estas apps, para que juegos, emuladores y reproductores de vídeo puedan seguir usando la pantalla completa."
    )
    static let sk = WindowMaximizerExclusionStrings(
        listTitle: "Ponechať režim celej obrazovky v týchto aplikáciách",
        addButton: "Pridať aplikáciu…",
        removeButton: "Odstrániť",
        caption: "V týchto aplikáciách si zelené tlačidlo zachová správanie macOS, takže hry, emulátory a prehrávače videa môžu naďalej prejsť na celú obrazovku."
    )

    static let de = WindowMaximizerExclusionStrings(
        listTitle: "Vollbild in diesen Apps beibehalten",
        addButton: "App hinzufügen…",
        removeButton: "Entfernen",
        caption: "In diesen Apps verhält sich die grüne Taste wie in macOS, damit Spiele, Emulatoren und Videoplayer weiterhin in den Vollbildmodus wechseln können."
    )

    static let fr = WindowMaximizerExclusionStrings(
        listTitle: "Garder le plein écran dans ces apps",
        addButton: "Ajouter une app…",
        removeButton: "Retirer",
        caption: "Dans ces apps, le bouton vert garde son comportement macOS, pour que les jeux, émulateurs et lecteurs vidéo puissent toujours passer en plein écran."
    )

    static let it = WindowMaximizerExclusionStrings(
        listTitle: "Mantieni lo schermo intero in queste app",
        addButton: "Aggiungi app…",
        removeButton: "Rimuovi",
        caption: "In queste app il pulsante verde mantiene il comportamento di macOS, così giochi, emulatori e lettori video possono ancora passare a schermo intero."
    )

    static let ja = WindowMaximizerExclusionStrings(
        listTitle: "これらのAppではフルスクリーンを維持",
        addButton: "Appを追加…",
        removeButton: "削除",
        caption: "これらのAppでは緑のボタンがmacOS標準の動作のままになり、ゲーム、エミュレータ、ビデオプレーヤーでもフルスクリーンを使えます。"
    )

    static let ko = WindowMaximizerExclusionStrings(
        listTitle: "이 앱에서는 전체 화면 유지",
        addButton: "앱 추가…",
        removeButton: "제거",
        caption: "이 앱에서는 초록색 버튼이 macOS 기본 동작을 유지하므로 게임, 에뮬레이터, 동영상 플레이어에서도 전체 화면으로 전환할 수 있습니다."
    )

    static let zhHans = WindowMaximizerExclusionStrings(
        listTitle: "在这些 App 中保留全屏",
        addButton: "添加 App…",
        removeButton: "移除",
        caption: "在这些 App 中，绿色按钮保留 macOS 的原有行为，游戏、模拟器和视频播放器仍可进入全屏。"
    )

    static let zhTW = WindowMaximizerExclusionStrings(
        listTitle: "在這些 App 中保留全螢幕",
        addButton: "加入 App…",
        removeButton: "移除",
        caption: "在這些 App 中，綠色按鈕會保留 macOS 原本的行為，遊戲、模擬器和影片播放器仍可進入全螢幕。"
    )

    static let zhHK = WindowMaximizerExclusionStrings(
        listTitle: "在這些 App 中保留全螢幕",
        addButton: "加入 App…",
        removeButton: "移除",
        caption: "在這些 App 中，綠色按鈕會保留 macOS 原本的行為，遊戲、模擬器和影片播放器仍然可以進入全螢幕。"
    )
}
