// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

struct RecorderExportStrings {
    let speed: String
    let custom: String
    let duration: String
    let previewNote: String
}

struct RecorderCompressionStrings {
    let originalResolution: String
    let limitFileSize: String
    let estimateHint: String
}

extension FeatureStrings {
    static func recorderCompression(_ language: AppLanguage) -> RecorderCompressionStrings {
        switch language {
        case .enUS:
            return .init(originalResolution: "Automatic (quality preset)", limitFileSize: "Limit file size",
                         estimateHint: "Approximate size based on bitrate, including audio and edits. The actual file may be smaller; a size limit is checked before saving. Applies to video, not GIF.")
        case .ptBR:
            return .init(originalResolution: "Automática (qualidade)", limitFileSize: "Limitar tamanho do arquivo",
                         estimateHint: "Estimativa pela taxa de bits, incluindo áudio e edições. O arquivo pode ser menor; o limite é verificado antes de salvar. Vale para vídeo, não GIF.")
        case .tr:
            return .init(originalResolution: "Otomatik (kalite ayarı)", limitFileSize: "Dosya boyutunu sınırla",
                         estimateHint: "Ses ve düzenlemeler dahil bit hızına dayalı tahmin. Dosya daha küçük olabilir; boyut sınırı kaydetmeden önce denetlenir. GIF için değil, video için geçerlidir.")
        case .ru:
            return .init(originalResolution: "Авто (по качеству)", limitFileSize: "Ограничить размер файла",
                         estimateHint: "Оценка по битрейту с учётом звука и монтажа. Файл может оказаться меньше; лимит проверяется перед сохранением. Применяется к видео, не к GIF.")
        case .es:
            return .init(originalResolution: "Automática (calidad)", limitFileSize: "Limitar tamaño del archivo",
                         estimateHint: "Estimación según la tasa de bits, con audio y edición. El archivo puede ser menor; el límite se verifica antes de guardar. Se aplica al vídeo, no al GIF.")
        case .sk:
            return .init(originalResolution: "Automatické (kvalita)", limitFileSize: "Obmedziť veľkosť súboru",
                         estimateHint: "Odhad podľa dátového toku vrátane zvuku a úprav. Súbor môže byť menší; limit sa overí pred uložením. Platí pre video, nie GIF.")
        case .de:
            return .init(originalResolution: "Automatisch (Qualitätsstufe)", limitFileSize: "Dateigröße begrenzen",
                         estimateHint: "Schätzung anhand der Bitrate einschließlich Ton und Bearbeitung. Die Datei kann kleiner sein; das Limit wird vor dem Speichern geprüft. Gilt für Video, nicht GIF.")
        case .fr:
            return .init(originalResolution: "Automatique (qualité)", limitFileSize: "Limiter la taille du fichier",
                         estimateHint: "Estimation selon le débit, avec le son et les modifications. Le fichier peut être plus petit ; la limite est vérifiée avant l’enregistrement. Pour la vidéo, pas le GIF.")
        case .it:
            return .init(originalResolution: "Automatica (qualità)", limitFileSize: "Limita dimensione del file",
                         estimateHint: "Stima dal bitrate, con audio e modifiche. Il file può essere più piccolo; il limite viene verificato prima del salvataggio. Vale per i video, non per i GIF.")
        case .ja:
            return .init(originalResolution: "自動（画質設定）", limitFileSize: "ファイルサイズを制限",
                         estimateHint: "音声と編集を含むビットレートからの概算です。実際のファイルは小さくなる場合があります。上限は保存前に確認されます。動画に適用され、GIFには適用されません。")
        case .ko:
            return .init(originalResolution: "자동 (화질 설정)", limitFileSize: "파일 크기 제한",
                         estimateHint: "오디오와 편집을 포함한 비트 전송률 기반 예상 크기입니다. 실제 파일은 더 작을 수 있으며 저장 전에 제한을 확인합니다. GIF가 아닌 동영상에 적용됩니다.")
        case .uk:
            return .init(originalResolution: "Авто (за якістю)", limitFileSize: "Обмежити розмір файлу",
                         estimateHint: "Оцінка за бітрейтом з урахуванням звуку й монтажу. Файл може бути меншим; ліміт перевіряється перед збереженням. Застосовується до відео, не до GIF.")
        case .zhHans:
            return .init(originalResolution: "自动（画质预设）", limitFileSize: "限制文件大小",
                         estimateHint: "根据码率估算，包含音频和编辑。实际文件可能更小，保存前会检查大小上限。适用于视频，不适用于 GIF。")
        case .zhTW:
            return .init(originalResolution: "自動（畫質預設）", limitFileSize: "限制檔案大小",
                         estimateHint: "依位元率估算，包含音訊和編輯。實際檔案可能較小，儲存前會檢查大小上限。適用於影片，不適用於 GIF。")
        case .zhHK:
            return .init(originalResolution: "自動（畫質預設）", limitFileSize: "限制檔案大小",
                         estimateHint: "按位元率估算，包含音訊及編輯。實際檔案可能較小，儲存前會檢查大小上限。適用於影片，不適用於 GIF。")
        }
    }
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
        case .sk:
            return RecorderExportStrings(
                speed: "Rýchlosť exportu", custom: "Vlastná rýchlosť", duration: "Dĺžka exportu",
                previewNote: "Platí pre video, GIF a zdieľané odkazy. Náhľad úprav zostáva na 1×, pôvodná nahrávka sa nemení.")
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
        case .uk:
            return RecorderExportStrings(
                speed: "Швидкість експорту", custom: "Власна швидкість", duration: "Тривалість експорту",
                previewNote: "Застосовується до відео, GIF і спільних посилань. Попередній перегляд під час редагування залишається на швидкості 1×; оригінальний запис не змінюється.")
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
