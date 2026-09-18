// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

struct NotchGestureStrings {
    let title: String
    let description: String
    let hint: String
}

extension FeatureStrings {
    static func notchGestures(_ language: AppLanguage) -> NotchGestureStrings {
        switch language {
        case .enUS: return NotchGestureStrings(
            title: "Dynamic Island Gestures",
            description: "Open and close the Dynamic Island with scrolling, and swipe to change tracks.",
            hint: "Scroll down to open. Scroll up over the top row to close. Swipe left or right over the music to change tracks. Lists keep their own scrolling.")
        case .ptBR: return NotchGestureStrings(
            title: "Gestos do Dynamic Island",
            description: "Abra e feche o Dynamic Island com a rolagem e deslize para trocar de música.",
            hint: "Role para baixo para abrir. Role para cima sobre a faixa superior para fechar. Deslize para os lados sobre a música para trocar de faixa. As listas mantêm a própria rolagem.")
        case .es: return NotchGestureStrings(
            title: "Gestos del Dynamic Island",
            description: "Abre y cierra el Dynamic Island al desplazarte y desliza para cambiar de canción.",
            hint: "Desplázate hacia abajo para abrir. Hacia arriba sobre la fila superior para cerrar. Desliza a los lados sobre la música para cambiar de pista. Las listas conservan su desplazamiento.")
        case .de: return NotchGestureStrings(
            title: "Dynamic Island-Gesten",
            description: "Öffne und schließe den Dynamic Island durch Scrollen und wechsle Titel durch Wischen.",
            hint: "Scrolle zum Öffnen nach unten und über der oberen Zeile zum Schließen nach oben. Wische über der Musik seitlich, um den Titel zu wechseln. Listen behalten ihr Scrollverhalten.")
        case .fr: return NotchGestureStrings(
            title: "Gestes du Dynamic Island",
            description: "Ouvrez et fermez le Dynamic Island par défilement et balayez pour changer de morceau.",
            hint: "Faites défiler vers le bas pour ouvrir, vers le haut sur la rangée supérieure pour fermer. Balayez latéralement sur la musique pour changer de morceau. Les listes gardent leur défilement.")
        case .it: return NotchGestureStrings(
            title: "Gesti del Dynamic Island",
            description: "Apri e chiudi il Dynamic Island scorrendo e cambia brano con un gesto laterale.",
            hint: "Scorri verso il basso per aprire e verso l’alto sulla riga superiore per chiudere. Scorri lateralmente sulla musica per cambiare brano. Le liste mantengono il loro scorrimento.")
        case .ru: return NotchGestureStrings(
            title: "Жесты для выреза",
            description: "Открывайте и закрывайте панель прокруткой, меняйте треки смахиванием.",
            hint: "Прокрутите вниз для открытия и вверх над верхней строкой для закрытия. Смахните влево или вправо над музыкой для смены трека. Прокрутка списков работает как обычно.")
        case .tr: return NotchGestureStrings(
            title: "Çentik Hareketleri",
            description: "Kaydırarak çentiği açıp kapatın ve parçaları değiştirin.",
            hint: "Açmak için aşağı kaydırın. Kapatmak için üst satırda yukarı kaydırın. Parçayı değiştirmek için müziğin üzerinde yana kaydırın. Listeler kendi kaydırma davranışını korur.")
        case .ja: return NotchGestureStrings(
            title: "Dynamic Islandのジェスチャ",
            description: "スクロールでDynamic Islandを開閉し、スワイプで曲を切り替えます。",
            hint: "下にスクロールすると開き、上部の行で上にスクロールすると閉じます。音楽の上で左右にスワイプすると曲が切り替わります。リストは通常どおりスクロールできます。")
        case .ko: return NotchGestureStrings(
            title: "Dynamic Island 제스처",
            description: "스크롤로 Dynamic Island를 열고 닫고, 옆으로 쓸어 곡을 바꾸세요.",
            hint: "아래로 스크롤하면 열립니다. 상단 줄에서 위로 스크롤하면 닫힙니다. 음악 위에서 좌우로 쓸면 곡이 바뀝니다. 목록은 기존처럼 스크롤됩니다.")
        case .zhHans: return NotchGestureStrings(
            title: "Dynamic Island手势",
            description: "滚动以打开或关闭Dynamic Island，左右轻扫以切换歌曲。",
            hint: "向下滚动以打开，在顶部栏向上滚动以关闭。在音乐上左右轻扫以切换歌曲。列表保持原有滚动方式。")
        case .zhTW: return NotchGestureStrings(
            title: "Dynamic Island手勢",
            description: "捲動以打開或關閉Dynamic Island，左右滑動以切換歌曲。",
            hint: "向下捲動以打開，在頂部列向上捲動以關閉。在音樂上左右滑動以切換歌曲。列表保留原有的捲動方式。")
        case .zhHK: return NotchGestureStrings(
            title: "Dynamic Island手勢",
            description: "捲動以開啟或關閉Dynamic Island，左右滑動以切換歌曲。",
            hint: "向下捲動以開啟，在頂部列向上捲動以關閉。在音樂上左右滑動以切換歌曲。列表保留原有的捲動方式。")
        case .uk: return NotchGestureStrings(
            title: "Жести Dynamic Island",
            description: "Відкривайте та закривайте Dynamic Island прокручуванням і змінюйте треки змахуванням.",
            hint: "Прокрутіть униз, щоб відкрити, і вгору над верхнім рядком, щоб закрити. Змахніть ліворуч або праворуч над музикою, щоб змінити трек. Списки прокручуються як зазвичай.")
        }
    }
}
