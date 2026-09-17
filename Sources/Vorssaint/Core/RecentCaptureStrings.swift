// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

struct RecentCaptureStrings {
    let title: String
    let empty: String
    let screenshot: String
    let recording: String
    let restore: String
    let open: String
    let remove: String
    let clear: String
}

extension FeatureStrings {
    static func recentCaptures(_ language: AppLanguage) -> RecentCaptureStrings {
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

extension RecentCaptureStrings {
    static let enUS = RecentCaptureStrings(
        title: "Recent captures",
        empty: "Take a screenshot or save a recording to find it here.",
        screenshot: "Screenshot",
        recording: "Recording",
        restore: "Restore",
        open: "Open",
        remove: "Remove from history",
        clear: "Clear history"
    )

    static let ptBR = RecentCaptureStrings(
        title: "Capturas recentes",
        empty: "Faça uma captura de tela ou salve uma gravação para encontrá-la aqui.",
        screenshot: "Captura de tela",
        recording: "Gravação",
        restore: "Restaurar",
        open: "Abrir",
        remove: "Remover do histórico",
        clear: "Limpar histórico"
    )

    static let tr = RecentCaptureStrings(
        title: "Son yakalamalar",
        empty: "Burada görmek için ekran görüntüsü alın veya bir kayıt kaydedin.",
        screenshot: "Ekran görüntüsü",
        recording: "Kayıt",
        restore: "Geri getir",
        open: "Aç",
        remove: "Geçmişten kaldır",
        clear: "Geçmişi temizle"
    )

    static let ru = RecentCaptureStrings(
        title: "Недавние снимки",
        empty: "Сделайте снимок экрана или сохраните запись, чтобы увидеть её здесь.",
        screenshot: "Снимок экрана",
        recording: "Запись",
        restore: "Вернуть",
        open: "Открыть",
        remove: "Удалить из истории",
        clear: "Очистить историю"
    )

    static let es = RecentCaptureStrings(
        title: "Capturas recientes",
        empty: "Haz una captura o guarda una grabación para verla aquí.",
        screenshot: "Captura de pantalla",
        recording: "Grabación",
        restore: "Restaurar",
        open: "Abrir",
        remove: "Quitar del historial",
        clear: "Borrar historial"
    )

    static let de = RecentCaptureStrings(
        title: "Letzte Aufnahmen",
        empty: "Erstelle ein Bildschirmfoto oder speichere eine Aufnahme, um sie hier zu sehen.",
        screenshot: "Bildschirmfoto",
        recording: "Aufnahme",
        restore: "Wiederherstellen",
        open: "Öffnen",
        remove: "Aus Verlauf entfernen",
        clear: "Verlauf löschen"
    )

    static let fr = RecentCaptureStrings(
        title: "Captures récentes",
        empty: "Prenez une capture ou enregistrez une vidéo pour la retrouver ici.",
        screenshot: "Capture d’écran",
        recording: "Enregistrement",
        restore: "Restaurer",
        open: "Ouvrir",
        remove: "Retirer de l’historique",
        clear: "Effacer l’historique"
    )

    static let it = RecentCaptureStrings(
        title: "Catture recenti",
        empty: "Cattura una schermata o salva una registrazione per trovarla qui.",
        screenshot: "Schermata",
        recording: "Registrazione",
        restore: "Ripristina",
        open: "Apri",
        remove: "Rimuovi dalla cronologia",
        clear: "Cancella cronologia"
    )

    static let ja = RecentCaptureStrings(
        title: "最近のキャプチャ",
        empty: "スクリーンショットを撮るか録画を保存すると、ここに表示されます。",
        screenshot: "スクリーンショット",
        recording: "録画",
        restore: "復元",
        open: "開く",
        remove: "履歴から削除",
        clear: "履歴を消去"
    )

    static let ko = RecentCaptureStrings(
        title: "최근 캡처",
        empty: "스크린샷을 찍거나 녹화를 저장하면 여기에 표시됩니다.",
        screenshot: "스크린샷",
        recording: "녹화",
        restore: "복원",
        open: "열기",
        remove: "기록에서 제거",
        clear: "기록 지우기"
    )

    static let zhHans = RecentCaptureStrings(
        title: "最近捕捉",
        empty: "截取屏幕或存储录屏后，就会显示在这里。",
        screenshot: "截图",
        recording: "录屏",
        restore: "恢复",
        open: "打开",
        remove: "从历史记录中移除",
        clear: "清除历史记录"
    )

    static let zhTW = RecentCaptureStrings(
        title: "最近擷取",
        empty: "截取畫面或儲存螢幕錄影後，就會顯示在這裡。",
        screenshot: "截圖",
        recording: "螢幕錄影",
        restore: "回復",
        open: "開啟",
        remove: "從記錄中移除",
        clear: "清除記錄"
    )

    static let zhHK = RecentCaptureStrings(
        title: "最近擷取",
        empty: "截取畫面或儲存螢幕錄影後，就會顯示喺呢度。",
        screenshot: "截圖",
        recording: "螢幕錄影",
        restore: "還原",
        open: "開啟",
        remove: "從記錄移除",
        clear: "清除記錄"
    )
}
