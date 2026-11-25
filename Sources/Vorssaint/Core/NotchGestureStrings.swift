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
            description: "Open and close the Dynamic Island with scrolling, and swipe to change tracks or pages.",
            hint: "Scroll down to open. Scroll up over the top row to close. Swipe left or right over the music to change tracks. Swipe sideways over the top row or any other page to move between pages. Lists keep their own scrolling.")
        case .ptBR: return NotchGestureStrings(
            title: "Gestos do Dynamic Island",
            description: "Abra e feche o Dynamic Island com a rolagem e deslize para trocar de música ou de página.",
            hint: "Role para baixo para abrir. Role para cima sobre a faixa superior para fechar. Deslize para os lados sobre a música para trocar de faixa. Deslize para os lados sobre a faixa superior ou outra página para mudar de página. As listas mantêm a própria rolagem.")
        case .es: return NotchGestureStrings(
            title: "Gestos del Dynamic Island",
            description: "Abre y cierra el Dynamic Island al desplazarte y desliza para cambiar de canción o de página.",
            hint: "Desplázate hacia abajo para abrir. Hacia arriba sobre la fila superior para cerrar. Desliza a los lados sobre la música para cambiar de pista. Desliza a los lados sobre la fila superior u otra página para cambiar de página. Las listas conservan su desplazamiento.")
        case .sk: return NotchGestureStrings(
            title: "Gestá Dynamic Island",
            description: "Otvorte a zatvorte Dynamic Island posúvaním a potiahnutím zmeňte skladbu alebo stránku.",
            hint: "Posunutím nadol otvoríte. Posunutím nahor nad horným riadkom zatvoríte. Potiahnutím doľava alebo doprava nad hudbou zmeníte skladbu. Potiahnutím do strán nad horným riadkom alebo inou stránkou prejdete na susednú stránku. Zoznamy si zachovávajú vlastné posúvanie.")
        case .de: return NotchGestureStrings(
            title: "Dynamic Island-Gesten",
            description: "Öffne und schließe den Dynamic Island durch Scrollen und wechsle Titel oder Seiten durch Wischen.",
            hint: "Scrolle zum Öffnen nach unten und über der oberen Zeile zum Schließen nach oben. Wische über der Musik seitlich, um den Titel zu wechseln. Wische über der oberen Zeile oder einer anderen Seite seitlich, um die Seite zu wechseln. Listen behalten ihr Scrollverhalten.")
        case .fr: return NotchGestureStrings(
            title: "Gestes du Dynamic Island",
            description: "Ouvrez et fermez le Dynamic Island par défilement et balayez pour changer de morceau ou de page.",
            hint: "Faites défiler vers le bas pour ouvrir, vers le haut sur la rangée supérieure pour fermer. Balayez latéralement sur la musique pour changer de morceau. Balayez latéralement sur la rangée supérieure ou une autre page pour changer de page. Les listes gardent leur défilement.")
        case .it: return NotchGestureStrings(
            title: "Gesti del Dynamic Island",
            description: "Apri e chiudi il Dynamic Island scorrendo e cambia brano o pagina con un gesto laterale.",
            hint: "Scorri verso il basso per aprire e verso l’alto sulla riga superiore per chiudere. Scorri lateralmente sulla musica per cambiare brano. Scorri lateralmente sulla riga superiore o su un’altra pagina per cambiare pagina. Le liste mantengono il loro scorrimento.")
        case .ru: return NotchGestureStrings(
            title: "Жесты для выреза",
            description: "Открывайте и закрывайте панель прокруткой, меняйте треки и страницы смахиванием.",
            hint: "Прокрутите вниз для открытия и вверх над верхней строкой для закрытия. Смахните влево или вправо над музыкой для смены трека. Смахните в сторону над верхней строкой или другой страницей, чтобы перейти на соседнюю страницу. Прокрутка списков работает как обычно.")
        case .tr: return NotchGestureStrings(
            title: "Çentik Hareketleri",
            description: "Kaydırarak çentiği açıp kapatın ve parçaları ya da sayfaları değiştirin.",
            hint: "Açmak için aşağı kaydırın. Kapatmak için üst satırda yukarı kaydırın. Parçayı değiştirmek için müziğin üzerinde yana kaydırın. Sayfalar arasında geçmek için üst satırda veya başka bir sayfada yana kaydırın. Listeler kendi kaydırma davranışını korur.")
        case .ja: return NotchGestureStrings(
            title: "Dynamic Islandのジェスチャ",
            description: "スクロールでDynamic Islandを開閉し、スワイプで曲やページを切り替えます。",
            hint: "下にスクロールすると開き、上部の行で上にスクロールすると閉じます。音楽の上で左右にスワイプすると曲が切り替わります。上部の行やほかのページで左右にスワイプするとページが切り替わります。リストは通常どおりスクロールできます。")
        case .ko: return NotchGestureStrings(
            title: "Dynamic Island 제스처",
            description: "스크롤로 Dynamic Island를 열고 닫고, 옆으로 쓸어 곡이나 페이지를 바꾸세요.",
            hint: "아래로 스크롤하면 열립니다. 상단 줄에서 위로 스크롤하면 닫힙니다. 음악 위에서 좌우로 쓸면 곡이 바뀝니다. 상단 줄이나 다른 페이지에서 좌우로 쓸면 페이지가 바뀝니다. 목록은 기존처럼 스크롤됩니다.")
        case .zhHans: return NotchGestureStrings(
            title: "Dynamic Island手势",
            description: "滚动以打开或关闭Dynamic Island，左右轻扫以切换歌曲或页面。",
            hint: "向下滚动以打开，在顶部栏向上滚动以关闭。在音乐上左右轻扫以切换歌曲。在顶部栏或其他页面上左右轻扫以切换页面。列表保持原有滚动方式。")
        case .zhTW: return NotchGestureStrings(
            title: "Dynamic Island手勢",
            description: "捲動以打開或關閉Dynamic Island，左右滑動以切換歌曲或頁面。",
            hint: "向下捲動以打開，在頂部列向上捲動以關閉。在音樂上左右滑動以切換歌曲。在頂部列或其他頁面上左右滑動以切換頁面。列表保留原有的捲動方式。")
        case .zhHK: return NotchGestureStrings(
            title: "Dynamic Island手勢",
            description: "捲動以開啟或關閉Dynamic Island，左右滑動以切換歌曲或頁面。",
            hint: "向下捲動以開啟，在頂部列向上捲動以關閉。在音樂上左右滑動以切換歌曲。在頂部列或其他頁面上左右滑動以切換頁面。列表保留原有的捲動方式。")
        case .uk: return NotchGestureStrings(
            title: "Жести Dynamic Island",
            description: "Відкривайте та закривайте Dynamic Island прокручуванням і змінюйте треки та сторінки змахуванням.",
            hint: "Прокрутіть униз, щоб відкрити, і вгору над верхнім рядком, щоб закрити. Змахніть ліворуч або праворуч над музикою, щоб змінити трек. Змахніть убік над верхнім рядком або іншою сторінкою, щоб перейти на сусідню сторінку. Списки прокручуються як зазвичай.")
        }
    }
}
