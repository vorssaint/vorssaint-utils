// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

struct MediaImageAdvancedStrings {
    let transform: String
    let rotation: String
    let noChange: String
    let flipHorizontal: String
    let flipVertical: String
    let crop: String
    let percentage: String
    let shortestSide: String
    let allowUpscaling: String
    let resampling: String
    let nearest: String
    let removeGPS: String
    let removeEXIF: String
    let removeIPTC: String
    let removeXMP: String
    let insertVariable: String

    static func localized(_ language: AppLanguage) -> MediaImageAdvancedStrings {
        switch language {
        case .enUS: return .init(transform: "Transform", rotation: "Rotation", noChange: "No change",
                                flipHorizontal: "Flip horizontally", flipVertical: "Flip vertically", crop: "Crop",
                                percentage: "Percentage", shortestSide: "Shortest side", allowUpscaling: "Allow upscaling",
                                resampling: "Resampling", nearest: "Nearest neighbor", removeGPS: "Remove location (GPS)",
                                removeEXIF: "Remove EXIF", removeIPTC: "Remove IPTC", removeXMP: "Remove XMP", insertVariable: "Insert variable")
        case .ptBR: return .init(transform: "Transformar", rotation: "Rotação", noChange: "Sem alterar",
                                flipHorizontal: "Virar horizontalmente", flipVertical: "Virar verticalmente", crop: "Recortar",
                                percentage: "Porcentagem", shortestSide: "Lado menor", allowUpscaling: "Permitir ampliação",
                                resampling: "Reamostragem", nearest: "Vizinho mais próximo", removeGPS: "Remover localização (GPS)",
                                removeEXIF: "Remover EXIF", removeIPTC: "Remover IPTC", removeXMP: "Remover XMP", insertVariable: "Inserir variável")
        case .tr: return .init(transform: "Dönüştür", rotation: "Döndürme", noChange: "Değişiklik yok",
                              flipHorizontal: "Yatay çevir", flipVertical: "Dikey çevir", crop: "Kırp",
                              percentage: "Yüzde", shortestSide: "Kısa kenar", allowUpscaling: "Büyütmeye izin ver",
                              resampling: "Yeniden örnekleme", nearest: "En yakın komşu", removeGPS: "Konumu kaldır (GPS)",
                              removeEXIF: "EXIF’i kaldır", removeIPTC: "IPTC’yi kaldır", removeXMP: "XMP’yi kaldır", insertVariable: "Değişken ekle")
        case .ru: return .init(transform: "Преобразование", rotation: "Поворот", noChange: "Без изменений",
                              flipHorizontal: "Отразить по горизонтали", flipVertical: "Отразить по вертикали", crop: "Обрезка",
                              percentage: "Процент", shortestSide: "Короткая сторона", allowUpscaling: "Разрешить увеличение",
                              resampling: "Интерполяция", nearest: "Ближайший сосед", removeGPS: "Удалить геолокацию (GPS)",
                              removeEXIF: "Удалить EXIF", removeIPTC: "Удалить IPTC", removeXMP: "Удалить XMP", insertVariable: "Вставить переменную")
        case .es: return .init(transform: "Transformar", rotation: "Rotación", noChange: "Sin cambios",
                              flipHorizontal: "Voltear horizontalmente", flipVertical: "Voltear verticalmente", crop: "Recortar",
                              percentage: "Porcentaje", shortestSide: "Lado corto", allowUpscaling: "Permitir ampliación",
                              resampling: "Remuestreo", nearest: "Vecino más cercano", removeGPS: "Eliminar ubicación (GPS)",
                              removeEXIF: "Eliminar EXIF", removeIPTC: "Eliminar IPTC", removeXMP: "Eliminar XMP", insertVariable: "Insertar variable")
        case .de: return .init(transform: "Transformieren", rotation: "Drehung", noChange: "Keine Änderung",
                              flipHorizontal: "Horizontal spiegeln", flipVertical: "Vertikal spiegeln", crop: "Zuschneiden",
                              percentage: "Prozent", shortestSide: "Kurze Seite", allowUpscaling: "Vergrößern erlauben",
                              resampling: "Neuberechnung", nearest: "Nächster Nachbar", removeGPS: "Standort entfernen (GPS)",
                              removeEXIF: "EXIF entfernen", removeIPTC: "IPTC entfernen", removeXMP: "XMP entfernen", insertVariable: "Variable einfügen")
        case .fr: return .init(transform: "Transformer", rotation: "Rotation", noChange: "Aucun changement",
                              flipHorizontal: "Retourner horizontalement", flipVertical: "Retourner verticalement", crop: "Recadrer",
                              percentage: "Pourcentage", shortestSide: "Côté court", allowUpscaling: "Autoriser l’agrandissement",
                              resampling: "Rééchantillonnage", nearest: "Plus proche voisin", removeGPS: "Supprimer la position (GPS)",
                              removeEXIF: "Supprimer EXIF", removeIPTC: "Supprimer IPTC", removeXMP: "Supprimer XMP", insertVariable: "Insérer une variable")
        case .it: return .init(transform: "Trasforma", rotation: "Rotazione", noChange: "Nessuna modifica",
                              flipHorizontal: "Rifletti orizzontalmente", flipVertical: "Rifletti verticalmente", crop: "Ritaglia",
                              percentage: "Percentuale", shortestSide: "Lato corto", allowUpscaling: "Consenti ingrandimento",
                              resampling: "Ricampionamento", nearest: "Vicino più prossimo", removeGPS: "Rimuovi posizione (GPS)",
                              removeEXIF: "Rimuovi EXIF", removeIPTC: "Rimuovi IPTC", removeXMP: "Rimuovi XMP", insertVariable: "Inserisci variabile")
        case .ja: return .init(transform: "変形", rotation: "回転", noChange: "変更なし",
                              flipHorizontal: "左右反転", flipVertical: "上下反転", crop: "切り抜き",
                              percentage: "パーセント", shortestSide: "短辺", allowUpscaling: "拡大を許可",
                              resampling: "リサンプリング", nearest: "最近傍", removeGPS: "位置情報を削除 (GPS)",
                              removeEXIF: "EXIFを削除", removeIPTC: "IPTCを削除", removeXMP: "XMPを削除", insertVariable: "変数を挿入")
        case .ko: return .init(transform: "변형", rotation: "회전", noChange: "변경 없음",
                              flipHorizontal: "좌우 뒤집기", flipVertical: "상하 뒤집기", crop: "자르기",
                              percentage: "백분율", shortestSide: "짧은 변", allowUpscaling: "확대 허용",
                              resampling: "리샘플링", nearest: "최근접", removeGPS: "위치 삭제 (GPS)",
                              removeEXIF: "EXIF 삭제", removeIPTC: "IPTC 삭제", removeXMP: "XMP 삭제", insertVariable: "변수 삽입")
        case .zhHans: return .init(transform: "变换", rotation: "旋转", noChange: "不更改",
                                  flipHorizontal: "水平翻转", flipVertical: "垂直翻转", crop: "裁剪",
                                  percentage: "百分比", shortestSide: "短边", allowUpscaling: "允许放大",
                                  resampling: "重采样", nearest: "最近邻", removeGPS: "移除位置 (GPS)",
                                  removeEXIF: "移除 EXIF", removeIPTC: "移除 IPTC", removeXMP: "移除 XMP", insertVariable: "插入变量")
        case .zhTW, .zhHK: return .init(transform: "變換", rotation: "旋轉", noChange: "不變更",
                                       flipHorizontal: "水平翻轉", flipVertical: "垂直翻轉", crop: "裁剪",
                                       percentage: "百分比", shortestSide: "短邊", allowUpscaling: "允許放大",
                                       resampling: "重新取樣", nearest: "最鄰近", removeGPS: "移除位置 (GPS)",
                                       removeEXIF: "移除 EXIF", removeIPTC: "移除 IPTC", removeXMP: "移除 XMP", insertVariable: "插入變數")
        }
    }
}
