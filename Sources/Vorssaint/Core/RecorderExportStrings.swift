// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

struct RecorderExportStrings {
    let speed: String
    let custom: String
    let duration: String
    let previewNote: String
}

extension FeatureStrings {
    static func recorderExport(_ language: AppLanguage) -> RecorderExportStrings {
        switch language {
        case .enUS:
            return RecorderExportStrings(
                speed: "Export speed", custom: "Custom speed", duration: "Export duration",
                previewNote: "Applies to video, GIF and shared links. The editing preview stays at 1×; the original recording is unchanged.")
        case .ptBR:
            return RecorderExportStrings(
                speed: "Velocidade de exportação", custom: "Velocidade personalizada", duration: "Duração exportada",
                previewNote: "Vale para vídeo, GIF e links compartilhados. A prévia de edição continua em 1×; a gravação original não muda.")
        case .tr:
            return RecorderExportStrings(
                speed: "Dışa aktarma hızı", custom: "Özel hız", duration: "Dışa aktarılan süre",
                previewNote: "Video, GIF ve paylaşılan bağlantılara uygulanır. Düzenleme önizlemesi 1× hızında kalır; orijinal kayıt değişmez.")
        case .ru:
            return RecorderExportStrings(
                speed: "Скорость экспорта", custom: "Своя скорость", duration: "Длительность экспорта",
                previewNote: "Применяется к видео, GIF и общим ссылкам. Предпросмотр остаётся на скорости 1×; исходная запись не меняется.")
        case .es:
            return RecorderExportStrings(
                speed: "Velocidad de exportación", custom: "Velocidad personalizada", duration: "Duración exportada",
                previewNote: "Se aplica a vídeos, GIF y enlaces compartidos. La vista previa sigue a 1×; la grabación original no cambia.")
        case .de:
            return RecorderExportStrings(
                speed: "Exportgeschwindigkeit", custom: "Eigene Geschwindigkeit", duration: "Exportdauer",
                previewNote: "Gilt für Videos, GIFs und geteilte Links. Die Bearbeitungsvorschau bleibt bei 1×; die Originalaufnahme bleibt unverändert.")
        case .fr:
            return RecorderExportStrings(
                speed: "Vitesse d’exportation", custom: "Vitesse personnalisée", duration: "Durée exportée",
                previewNote: "S’applique aux vidéos, GIF et liens partagés. L’aperçu de montage reste à 1× ; l’enregistrement original reste inchangé.")
        case .it:
            return RecorderExportStrings(
                speed: "Velocità di esportazione", custom: "Velocità personalizzata", duration: "Durata esportata",
                previewNote: "Si applica a video, GIF e link condivisi. L’anteprima di modifica resta a 1×; la registrazione originale non cambia.")
        case .ja:
            return RecorderExportStrings(
                speed: "書き出し速度", custom: "カスタム速度", duration: "書き出し後の長さ",
                previewNote: "動画、GIF、共有リンクに適用されます。編集プレビューは1×のままで、元の録画は変更されません。")
        case .ko:
            return RecorderExportStrings(
                speed: "내보내기 속도", custom: "사용자 지정 속도", duration: "내보내기 재생 시간",
                previewNote: "동영상, GIF 및 공유 링크에 적용됩니다. 편집 미리보기는 1×로 유지되며 원본 녹화는 변경되지 않습니다.")
        case .zhHans:
            return RecorderExportStrings(
                speed: "导出速度", custom: "自定义速度", duration: "导出时长",
                previewNote: "适用于视频、GIF 和分享链接。编辑预览保持 1×，原始录制不会改变。")
        case .zhTW:
            return RecorderExportStrings(
                speed: "匯出速度", custom: "自訂速度", duration: "匯出長度",
                previewNote: "適用於影片、GIF 和分享連結。編輯預覽維持 1×，原始錄影不會變更。")
        case .zhHK:
            return RecorderExportStrings(
                speed: "匯出速度", custom: "自訂速度", duration: "匯出長度",
                previewNote: "適用於影片、GIF 和分享連結。編輯預覽維持 1×，原始錄影不會改變。")
        }
    }
}
