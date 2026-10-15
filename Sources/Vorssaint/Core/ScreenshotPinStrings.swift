// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

struct ScreenshotPinStrings {
    let title: String
    let rounded: String
    let lock: String
    let unlock: String
    let clickThrough: String
    let drag: String

    static func localized(_ language: AppLanguage) -> Self {
        switch language {
        case .enUS: return .init(title: "Pinned screenshots", rounded: "Rounded pinned screenshots", lock: "Lock position and size", unlock: "Unlock position and size", clickThrough: "Click through image", drag: "Drag me")
        case .ptBR: return .init(title: "Capturas fixadas", rounded: "Arredondar capturas fixadas", lock: "Bloquear posição e tamanho", unlock: "Desbloquear posição e tamanho", clickThrough: "Clicar através da imagem", drag: "Arraste-me")
        case .tr: return .init(title: "Sabitlenen ekran görüntüleri", rounded: "Sabitlenen görüntüleri yuvarlat", lock: "Konumu ve boyutu kilitle", unlock: "Konum ve boyut kilidini aç", clickThrough: "Görüntünün arkasına tıkla", drag: "Beni sürükle")
        case .ru: return .init(title: "Закреплённые снимки", rounded: "Скруглять закреплённые снимки", lock: "Заблокировать положение и размер", unlock: "Разблокировать положение и размер", clickThrough: "Пропускать нажатия сквозь изображение", drag: "Перетащите")
        case .es: return .init(title: "Capturas fijadas", rounded: "Redondear las capturas fijadas", lock: "Bloquear posición y tamaño", unlock: "Desbloquear posición y tamaño", clickThrough: "Hacer clic a través de la imagen", drag: "Arrástrame")
        case .sk: return .init(title: "Pripnuté snímky", rounded: "Zaobliť pripnuté snímky", lock: "Zamknúť polohu a veľkosť", unlock: "Odomknúť polohu a veľkosť", clickThrough: "Kliknúť cez obrázok", drag: "Potiahnite ma")
        case .de: return .init(title: "Angeheftete Screenshots", rounded: "Angeheftete Screenshots abrunden", lock: "Position und Größe sperren", unlock: "Position und Größe entsperren", clickThrough: "Durch das Bild klicken", drag: "Ziehen")
        case .fr: return .init(title: "Captures épinglées", rounded: "Arrondir les captures épinglées", lock: "Verrouiller la position et la taille", unlock: "Déverrouiller la position et la taille", clickThrough: "Cliquer à travers l’image", drag: "Glissez-moi")
        case .it: return .init(title: "Istantanee fissate", rounded: "Arrotonda le istantanee fissate", lock: "Blocca posizione e dimensioni", unlock: "Sblocca posizione e dimensioni", clickThrough: "Fai clic attraverso l’immagine", drag: "Trascinami")
        case .ja: return .init(title: "固定したスクリーンショット", rounded: "固定したスクリーンショットの角を丸くする", lock: "位置とサイズをロック", unlock: "位置とサイズのロックを解除", clickThrough: "画像をクリック透過", drag: "ドラッグ")
        case .ko: return .init(title: "고정된 스크린샷", rounded: "고정된 스크린샷 모서리 둥글게", lock: "위치와 크기 잠금", unlock: "위치와 크기 잠금 해제", clickThrough: "이미지 클릭 통과", drag: "드래그")
        case .uk: return .init(title: "Закріплені знімки", rounded: "Заокруглювати закріплені знімки", lock: "Заблокувати положення та розмір", unlock: "Розблокувати положення та розмір", clickThrough: "Пропускати натискання крізь зображення", drag: "Перетягніть")
        case .zhHans: return .init(title: "钉住的截屏", rounded: "钉住截屏使用圆角", lock: "锁定位置和大小", unlock: "解锁位置和大小", clickThrough: "点击穿透图像", drag: "拖动文件")
        case .zhTW: return .init(title: "釘選的截圖", rounded: "釘選截圖使用圓角", lock: "鎖定位置與大小", unlock: "解除鎖定位置與大小", clickThrough: "點擊穿透影像", drag: "拖移檔案")
        case .zhHK: return .init(title: "釘選的截圖", rounded: "釘選截圖使用圓角", lock: "鎖定位置與大小", unlock: "解除鎖定位置與大小", clickThrough: "點擊穿透圖像", drag: "拖移檔案")
        }
    }
}
