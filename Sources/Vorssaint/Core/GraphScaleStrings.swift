// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

struct GraphScaleStrings {
    let title: String

    static func localized(_ language: AppLanguage) -> GraphScaleStrings {
        switch language {
        case .enUS: return .init(title: "Show graph scale")
        case .ptBR: return .init(title: "Mostrar escala dos gráficos")
        case .tr: return .init(title: "Grafik ölçeğini göster")
        case .ru: return .init(title: "Показывать шкалу графиков")
        case .es: return .init(title: "Mostrar escala de las gráficas")
        case .sk: return .init(title: "Zobraziť mierku grafov")
        case .de: return .init(title: "Diagrammskala anzeigen")
        case .fr: return .init(title: "Afficher l’échelle des graphiques")
        case .it: return .init(title: "Mostra la scala dei grafici")
        case .ja: return .init(title: "グラフの上限を表示")
        case .ko: return .init(title: "그래프 상한 표시")
        case .uk: return .init(title: "Показувати шкалу графіків")
        case .zhHans: return .init(title: "显示图表上限")
        case .zhTW: return .init(title: "顯示圖表上限")
        case .zhHK: return .init(title: "顯示圖表上限")
        }
    }
}
