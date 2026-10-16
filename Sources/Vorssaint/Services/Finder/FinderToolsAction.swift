// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

enum FinderToolsAction: String, CaseIterable, Identifiable, Codable {
    case newFile, newFolder, template, pasteText, pasteMarkdown
    case copyPath, copyName, copyStem, copyMarkdown, copyContents, fileTree, directoryTree, size, sha256
    case copyTo, moveTo, alias, hide, unhide, lock, unlock, group, flatten

    case mergePDF, splitPDF, watermarkPDF
    case rotateLeft, rotateRight, stitchHorizontal, stitchVertical, removeBackground, replaceBackground, recolor, readQR
    case editImage, convertImages, convertVideo, extractText

    case batchRename, duplicates, zip, quickLook, reveal, info, packageContents, trash, permanentDelete
    case eject, hideExtension, showExtension, extractIcon, wallpaper, share, openTerminal, copySummary

    case compressPDF, diskImage, encryptedDiskImage, extractAudio, pasteImage, pasteFiles, pasteAliases

    case setIcon, resetIcon, defaultApplication, openWith, searchFolder, repairNames, aliasDesktop, pasteZIP
    case shareLAN, recordAudio, recordVideo
    case cutFiles, pasteMovedFiles, airDrop, uninstallApp

    var usesSystemUI: Bool { [.airDrop, .setIcon, .resetIcon, .defaultApplication, .openWith, .quickLook, .reveal, .info, .packageContents, .eject,
        .extractIcon, .wallpaper, .share, .openTerminal].contains(self) }

    var isDocumentOutput: Bool { [.compressPDF, .diskImage, .encryptedDiskImage, .extractAudio, .pasteImage,.mergePDF, .splitPDF, .watermarkPDF, .rotateLeft, .rotateRight,
        .stitchHorizontal, .stitchVertical, .removeBackground, .replaceBackground, .recolor].contains(self) }
    var usesExistingTool: Bool { [.cutFiles, .pasteMovedFiles, .uninstallApp, .recordAudio, .recordVideo, .shareLAN, .editImage, .convertImages, .convertVideo, .extractText].contains(self) }

    var id: String { rawValue }
    var needsName: Bool { isDocumentOutput || self == .batchRename || self == .searchFolder || [.newFile, .newFolder, .template, .pasteText, .pasteMarkdown, .group].contains(self) }
    var needsDestination: Bool { isDocumentOutput || [.pasteMovedFiles, .pasteZIP, .pasteFiles, .pasteAliases,.zip, .extractIcon].contains(self) || [.newFile, .newFolder, .template, .pasteText, .pasteMarkdown, .copyTo, .moveTo, .alias, .group].contains(self) }
    var needsSelection: Bool { ![.pasteMovedFiles, .recordAudio, .recordVideo, .pasteZIP, .pasteImage, .pasteFiles, .pasteAliases,.newFile, .newFolder, .pasteText, .pasteMarkdown].contains(self) }
    var changesSources: Bool { [.pasteMovedFiles, .repairNames, .setIcon, .resetIcon, .defaultApplication, .batchRename, .trash, .permanentDelete, .hideExtension, .showExtension,.moveTo, .hide, .unhide, .lock, .unlock, .group, .flatten].contains(self) }

    func title(languageCode: String) -> String {
        if let index = [Self.cutFiles, .pasteMovedFiles, .airDrop, .uninstallApp].firstIndex(of: self) {
            return Self.integrationTitles(languageCode)[index]
        }
        if self == .recordAudio || self == .recordVideo { return Self.captureTitles(languageCode)[self == .recordVideo ? 1 : 0] }
        if self == .shareLAN { return FinderLANShareStrings.localized(languageCode).title }
        let index = Self.allCases.firstIndex(of: self)!
        return (Self.titles(languageCode) + Self.documentTitles(languageCode) + Self.fileExtraTitles(languageCode) + Self.mediaExtraTitles(languageCode) + Self.navigationTitles(languageCode))[index]
    }

    private static func titles(_ language: String) -> [String] {
        switch language {
        case "en-US": return ["New File", "New Folder", "New from Template", "Paste as Text File", "Paste as Markdown File", "Copy Paths", "Copy Names", "Copy Names without Extensions", "Copy Markdown Links", "Read Text Contents", "File Tree", "Directory Tree", "Total Size", "SHA-256", "Copy to Folder", "Move to Folder", "Create Aliases", "Hide Items", "Unhide Items", "Lock Items", "Unlock Items", "Group in New Folder", "Move Contents to Parent Folder"]
        case "pt-BR": return ["Novo arquivo", "Nova pasta", "Novo a partir de modelo", "Colar como arquivo de texto", "Colar como arquivo Markdown", "Copiar caminhos", "Copiar nomes", "Copiar nomes sem extensão", "Copiar links Markdown", "Ler conteúdo de texto", "Árvore de arquivos", "Árvore de pastas", "Tamanho total", "SHA-256", "Copiar para pasta", "Mover para pasta", "Criar aliases", "Ocultar itens", "Mostrar itens ocultos", "Bloquear itens", "Desbloquear itens", "Agrupar em nova pasta", "Mover conteúdo para a pasta superior"]
        case "tr": return ["Yeni Dosya", "Yeni Klasör", "Şablondan Yeni", "Metin Dosyası Olarak Yapıştır", "Markdown Olarak Yapıştır", "Yolları Kopyala", "Adları Kopyala", "Uzantısız Adları Kopyala", "Markdown Bağlantılarını Kopyala", "Metin İçeriğini Oku", "Dosya Ağacı", "Klasör Ağacı", "Toplam Boyut", "SHA-256", "Klasöre Kopyala", "Klasöre Taşı", "Takma Ad Oluştur", "Öğeleri Gizle", "Öğeleri Göster", "Öğeleri Kilitle", "Kilitleri Aç", "Yeni Klasörde Grupla", "İçeriği Üst Klasöre Taşı"]
        case "ru": return ["Новый файл", "Новая папка", "Создать из шаблона", "Вставить как текст", "Вставить как Markdown", "Копировать пути", "Копировать имена", "Имена без расширений", "Копировать ссылки Markdown", "Прочитать текст", "Дерево файлов", "Дерево папок", "Общий размер", "SHA-256", "Копировать в папку", "Переместить в папку", "Создать псевдонимы", "Скрыть объекты", "Показать объекты", "Заблокировать объекты", "Разблокировать объекты", "Сгруппировать в папке", "Переместить содержимое в родительскую папку"]
        case "es": return ["Nuevo archivo", "Nueva carpeta", "Nuevo desde plantilla", "Pegar como archivo de texto", "Pegar como Markdown", "Copiar rutas", "Copiar nombres", "Copiar nombres sin extensión", "Copiar enlaces Markdown", "Leer contenido de texto", "Árbol de archivos", "Árbol de carpetas", "Tamaño total", "SHA-256", "Copiar a carpeta", "Mover a carpeta", "Crear alias", "Ocultar elementos", "Mostrar elementos", "Bloquear elementos", "Desbloquear elementos", "Agrupar en nueva carpeta", "Mover contenido a carpeta superior"]
        case "sk": return ["Nový súbor", "Nový priečinok", "Nový zo šablóny", "Vložiť ako textový súbor", "Vložiť ako Markdown", "Kopírovať cesty", "Kopírovať názvy", "Názvy bez prípon", "Kopírovať odkazy Markdown", "Čítať textový obsah", "Strom súborov", "Strom priečinkov", "Celková veľkosť", "SHA-256", "Kopírovať do priečinka", "Presunúť do priečinka", "Vytvoriť aliasy", "Skryť položky", "Zobraziť položky", "Zamknúť položky", "Odomknúť položky", "Zoskupiť v novom priečinku", "Presunúť obsah do nadradeného priečinka"]
        case "de": return ["Neue Datei", "Neuer Ordner", "Neu aus Vorlage", "Als Textdatei einsetzen", "Als Markdown einsetzen", "Pfade kopieren", "Namen kopieren", "Namen ohne Erweiterung kopieren", "Markdown-Links kopieren", "Textinhalt lesen", "Dateibaum", "Ordnerbaum", "Gesamtgröße", "SHA-256", "In Ordner kopieren", "In Ordner bewegen", "Aliasse erstellen", "Objekte ausblenden", "Objekte einblenden", "Objekte schützen", "Schutz aufheben", "In neuem Ordner gruppieren", "Inhalt in übergeordneten Ordner bewegen"]
        case "fr": return ["Nouveau fichier", "Nouveau dossier", "Nouveau depuis un modèle", "Coller en fichier texte", "Coller en Markdown", "Copier les chemins", "Copier les noms", "Noms sans extension", "Copier les liens Markdown", "Lire le contenu texte", "Arborescence des fichiers", "Arborescence des dossiers", "Taille totale", "SHA-256", "Copier vers un dossier", "Déplacer vers un dossier", "Créer des alias", "Masquer les éléments", "Afficher les éléments", "Verrouiller les éléments", "Déverrouiller les éléments", "Regrouper dans un dossier", "Déplacer le contenu vers le dossier parent"]
        case "it": return ["Nuovo file", "Nuova cartella", "Nuovo da modello", "Incolla come file di testo", "Incolla come Markdown", "Copia percorsi", "Copia nomi", "Nomi senza estensione", "Copia link Markdown", "Leggi contenuto testuale", "Albero dei file", "Albero delle cartelle", "Dimensione totale", "SHA-256", "Copia nella cartella", "Sposta nella cartella", "Crea alias", "Nascondi elementi", "Mostra elementi", "Blocca elementi", "Sblocca elementi", "Raggruppa in nuova cartella", "Sposta contenuto nella cartella superiore"]
        case "ja": return ["新規ファイル", "新規フォルダ", "テンプレートから作成", "テキストファイルとしてペースト", "Markdown としてペースト", "パスをコピー", "名前をコピー", "拡張子なしの名前をコピー", "Markdown リンクをコピー", "テキスト内容を読む", "ファイルツリー", "フォルダツリー", "合計サイズ", "SHA-256", "フォルダにコピー", "フォルダに移動", "エイリアスを作成", "項目を隠す", "項目を表示", "項目をロック", "ロックを解除", "新規フォルダにまとめる", "内容を親フォルダに移動"]
        case "ko": return ["새 파일", "새 폴더", "템플릿으로 만들기", "텍스트 파일로 붙여넣기", "Markdown으로 붙여넣기", "경로 복사", "이름 복사", "확장자 없이 이름 복사", "Markdown 링크 복사", "텍스트 내용 읽기", "파일 트리", "폴더 트리", "전체 크기", "SHA-256", "폴더로 복사", "폴더로 이동", "별칭 만들기", "항목 숨기기", "항목 표시", "항목 잠그기", "잠금 해제", "새 폴더에 모으기", "내용을 상위 폴더로 이동"]
        case "zh-Hans": return ["新建文件", "新建文件夹", "从模板新建", "粘贴为文本文件", "粘贴为 Markdown", "复制路径", "复制名称", "复制不含扩展名的名称", "复制 Markdown 链接", "读取文本内容", "文件树", "目录树", "总大小", "SHA-256", "复制到文件夹", "移动到文件夹", "创建替身", "隐藏项目", "显示项目", "锁定项目", "解锁项目", "归入新文件夹", "将内容移至上级文件夹"]
        case "zh-TW": return ["新增檔案", "新增資料夾", "從範本新增", "貼上為文字檔", "貼上為 Markdown", "複製路徑", "複製名稱", "複製不含副檔名的名稱", "複製 Markdown 連結", "讀取文字內容", "檔案樹", "目錄樹", "總大小", "SHA-256", "複製到資料夾", "移動到資料夾", "製作替身", "隱藏項目", "顯示項目", "鎖定項目", "解鎖項目", "歸入新資料夾", "將內容移至上層資料夾"]
        case "zh-HK": return ["新增檔案", "新增資料夾", "從範本新增", "貼上為文字檔", "貼上為 Markdown", "複製路徑", "複製名稱", "複製不含副檔名的名稱", "複製 Markdown 連結", "讀取文字內容", "檔案樹", "目錄樹", "總大小", "SHA-256", "複製到資料夾", "移動到資料夾", "製作替身", "隱藏項目", "顯示項目", "鎖定項目", "解鎖項目", "歸入新資料夾", "將內容移至上層資料夾"]
        case "uk": return ["Новий файл", "Нова папка", "Створити з шаблону", "Вставити як текст", "Вставити як Markdown", "Копіювати шляхи", "Копіювати назви", "Назви без розширень", "Копіювати посилання Markdown", "Прочитати текст", "Дерево файлів", "Дерево папок", "Загальний розмір", "SHA-256", "Копіювати до папки", "Перемістити до папки", "Створити псевдоніми", "Приховати об’єкти", "Показати об’єкти", "Заблокувати об’єкти", "Розблокувати об’єкти", "Згрупувати в новій папці", "Перемістити вміст до батьківської папки"]
        default: return titles("en-US")
        }
    }

    private static func documentTitles(_ language: String) -> [String] {
        switch language {
        case "en-US": return ["Merge PDFs and Images", "Split PDF Pages", "Watermark PDF", "Rotate Left", "Rotate Right", "Stitch Horizontally", "Stitch Vertically", "Remove Background", "Replace Background", "Recolor Image", "Read QR Codes", "Edit Image", "Convert and Resize Images", "Convert Video", "Extract Text"]
        case "pt-BR": return ["Mesclar PDFs e imagens", "Separar páginas do PDF", "Marca d’água no PDF", "Girar à esquerda", "Girar à direita", "Unir na horizontal", "Unir na vertical", "Remover fundo", "Substituir fundo", "Recolorir imagem", "Ler códigos QR", "Editar imagem", "Converter e redimensionar imagens", "Converter vídeo", "Extrair texto"]
        case "es": return ["Combinar PDF e imágenes", "Separar páginas PDF", "Marca de agua en PDF", "Girar a la izquierda", "Girar a la derecha", "Unir horizontalmente", "Unir verticalmente", "Quitar fondo", "Reemplazar fondo", "Cambiar color de imagen", "Leer códigos QR", "Editar imagen", "Convertir y redimensionar imágenes", "Convertir vídeo", "Extraer texto"]
        case "fr": return ["Fusionner PDF et images", "Séparer les pages PDF", "Filigrane PDF", "Pivoter à gauche", "Pivoter à droite", "Assembler horizontalement", "Assembler verticalement", "Supprimer le fond", "Remplacer le fond", "Recolorer l’image", "Lire les codes QR", "Modifier l’image", "Convertir et redimensionner les images", "Convertir la vidéo", "Extraire le texte"]
        case "de": return ["PDFs und Bilder zusammenführen", "PDF-Seiten aufteilen", "PDF-Wasserzeichen", "Nach links drehen", "Nach rechts drehen", "Horizontal zusammenfügen", "Vertikal zusammenfügen", "Hintergrund entfernen", "Hintergrund ersetzen", "Bild neu einfärben", "QR-Codes lesen", "Bild bearbeiten", "Bilder konvertieren und skalieren", "Video konvertieren", "Text extrahieren"]
        case "it": return ["Unisci PDF e immagini", "Separa pagine PDF", "Filigrana PDF", "Ruota a sinistra", "Ruota a destra", "Unisci in orizzontale", "Unisci in verticale", "Rimuovi sfondo", "Sostituisci sfondo", "Ricolora immagine", "Leggi codici QR", "Modifica immagine", "Converti e ridimensiona immagini", "Converti video", "Estrai testo"]
        case "tr": return ["PDF ve Görselleri Birleştir", "PDF Sayfalarını Ayır", "PDF Filigranı", "Sola Döndür", "Sağa Döndür", "Yatay Birleştir", "Dikey Birleştir", "Arka Planı Kaldır", "Arka Planı Değiştir", "Görseli Renklendir", "QR Kodlarını Oku", "Görseli Düzenle", "Görselleri Dönüştür ve Boyutlandır", "Videoyu Dönüştür", "Metni Çıkar"]
        case "sk": return ["Zlúčiť PDF a obrázky", "Rozdeliť strany PDF", "Vodoznak PDF", "Otočiť doľava", "Otočiť doprava", "Spojiť vodorovne", "Spojiť zvislo", "Odstrániť pozadie", "Nahradiť pozadie", "Prefarbiť obrázok", "Čítať QR kódy", "Upraviť obrázok", "Konvertovať a zmeniť veľkosť obrázkov", "Konvertovať video", "Extrahovať text"]
        case "ru": return ["Объединить PDF и изображения", "Разделить страницы PDF", "Водяной знак PDF", "Повернуть влево", "Повернуть вправо", "Соединить по горизонтали", "Соединить по вертикали", "Удалить фон", "Заменить фон", "Перекрасить изображение", "Прочитать QR-коды", "Редактировать изображение", "Преобразовать и изменить размер изображений", "Преобразовать видео", "Извлечь текст"]
        case "uk": return ["Об’єднати PDF і зображення", "Розділити сторінки PDF", "Водяний знак PDF", "Повернути ліворуч", "Повернути праворуч", "З’єднати горизонтально", "З’єднати вертикально", "Видалити тло", "Замінити тло", "Перефарбувати зображення", "Прочитати QR-коди", "Редагувати зображення", "Перетворити та змінити розмір зображень", "Перетворити відео", "Витягти текст"]
        case "ja": return ["PDFと画像を結合", "PDFページを分割", "PDFに透かしを追加", "左に回転", "右に回転", "横に結合", "縦に結合", "背景を削除", "背景を置換", "画像を再着色", "QRコードを読み取る", "画像を編集", "画像を変換・サイズ変更", "動画を変換", "テキストを抽出"]
        case "ko": return ["PDF 및 이미지 병합", "PDF 페이지 분할", "PDF 워터마크", "왼쪽으로 회전", "오른쪽으로 회전", "가로로 합치기", "세로로 합치기", "배경 제거", "배경 교체", "이미지 색상 변경", "QR 코드 읽기", "이미지 편집", "이미지 변환 및 크기 조절", "동영상 변환", "텍스트 추출"]
        case "zh-Hans": return ["合并 PDF 和图像", "拆分 PDF 页面", "PDF 水印", "向左旋转", "向右旋转", "横向拼接", "纵向拼接", "移除背景", "替换背景", "图像重新着色", "读取二维码", "编辑图像", "转换和调整图像大小", "转换视频", "提取文本"]
        case "zh-TW": return ["合併 PDF 和影像", "拆分 PDF 頁面", "PDF 浮水印", "向左旋轉", "向右旋轉", "橫向拼接", "縱向拼接", "移除背景", "取代背景", "影像重新著色", "讀取 QR 碼", "編輯影像", "轉換和調整影像大小", "轉換影片", "擷取文字"]
        case "zh-HK": return ["合併 PDF 和影像", "拆分 PDF 頁面", "PDF 浮水印", "向左旋轉", "向右旋轉", "橫向拼接", "縱向拼接", "移除背景", "取代背景", "影像重新著色", "讀取 QR 碼", "編輯影像", "轉換和調整影像大小", "轉換影片", "擷取文字"]
        default: return documentTitles("en-US")
        }
    }

    private static func fileExtraTitles(_ language: String) -> [String] {
        switch language {
        case "en-US": return ["Batch Rename", "Find Duplicates", "Create ZIP Archives", "Quick Look", "Show in Finder", "Get Info", "Show Package Contents", "Move to Trash", "Delete Permanently", "Eject Volume", "Hide Extensions", "Show Extensions", "Extract Icon", "Set as Wallpaper", "Share", "Open Terminal Here", "Copy File Summary"]
        case "pt-BR": return ["Renomear em lote", "Encontrar duplicados", "Criar arquivos ZIP", "Visualização rápida", "Mostrar no Finder", "Obter informações", "Mostrar conteúdo do pacote", "Mover para a Lixeira", "Apagar permanentemente", "Ejetar volume", "Ocultar extensões", "Mostrar extensões", "Extrair ícone", "Definir como papel de parede", "Compartilhar", "Abrir Terminal aqui", "Copiar resumo dos arquivos"]
        case "es": return ["Renombrar en lote", "Buscar duplicados", "Crear archivos ZIP", "Vista rápida", "Mostrar en Finder", "Obtener información", "Mostrar contenido del paquete", "Mover a la papelera", "Eliminar permanentemente", "Expulsar volumen", "Ocultar extensiones", "Mostrar extensiones", "Extraer icono", "Usar como fondo de pantalla", "Compartir", "Abrir Terminal aquí", "Copiar resumen de archivos"]
        case "fr": return ["Renommer par lot", "Rechercher les doublons", "Créer des archives ZIP", "Coup d’œil", "Afficher dans le Finder", "Lire les informations", "Afficher le contenu du paquet", "Placer dans la corbeille", "Supprimer définitivement", "Éjecter le volume", "Masquer les extensions", "Afficher les extensions", "Extraire l’icône", "Définir comme fond d’écran", "Partager", "Ouvrir Terminal ici", "Copier le résumé des fichiers"]
        case "de": return ["Stapelweise umbenennen", "Duplikate suchen", "ZIP-Archive erstellen", "Übersicht", "Im Finder zeigen", "Informationen", "Paketinhalt zeigen", "In den Papierkorb legen", "Endgültig löschen", "Volume auswerfen", "Erweiterungen ausblenden", "Erweiterungen einblenden", "Symbol extrahieren", "Als Hintergrundbild festlegen", "Teilen", "Terminal hier öffnen", "Dateiübersicht kopieren"]
        case "it": return ["Rinomina in gruppo", "Trova duplicati", "Crea archivi ZIP", "Visualizzazione rapida", "Mostra nel Finder", "Ottieni informazioni", "Mostra contenuto pacchetto", "Sposta nel Cestino", "Elimina definitivamente", "Espelli volume", "Nascondi estensioni", "Mostra estensioni", "Estrai icona", "Imposta come sfondo", "Condividi", "Apri Terminale qui", "Copia riepilogo file"]
        case "tr": return ["Toplu Yeniden Adlandır", "Yinelenenleri Bul", "ZIP Arşivleri Oluştur", "Göz At", "Finder’da Göster", "Bilgi Ver", "Paket İçeriğini Göster", "Çöp Sepetine Taşı", "Kalıcı Olarak Sil", "Birimi Çıkar", "Uzantıları Gizle", "Uzantıları Göster", "Simgeyi Çıkar", "Duvar Kağıdı Yap", "Paylaş", "Terminali Burada Aç", "Dosya Özetini Kopyala"]
        case "sk": return ["Hromadne premenovať", "Nájsť duplikáty", "Vytvoriť ZIP archívy", "Rýchly náhľad", "Zobraziť vo Finderi", "Informácie", "Zobraziť obsah balíka", "Presunúť do koša", "Natrvalo vymazať", "Vysunúť zväzok", "Skryť prípony", "Zobraziť prípony", "Extrahovať ikonu", "Nastaviť ako tapetu", "Zdieľať", "Otvoriť Terminál tu", "Kopírovať súhrn súborov"]
        case "ru": return ["Пакетное переименование", "Найти дубликаты", "Создать ZIP-архивы", "Быстрый просмотр", "Показать в Finder", "Свойства", "Показать содержимое пакета", "Переместить в Корзину", "Удалить навсегда", "Извлечь том", "Скрыть расширения", "Показать расширения", "Извлечь значок", "Установить как обои", "Поделиться", "Открыть Терминал здесь", "Копировать сводку файлов"]
        case "uk": return ["Пакетне перейменування", "Знайти дублікати", "Створити ZIP-архіви", "Швидкий перегляд", "Показати у Finder", "Інформація", "Показати вміст пакета", "Перемістити до Смітника", "Видалити назавжди", "Витягти том", "Приховати розширення", "Показати розширення", "Витягти піктограму", "Установити як шпалери", "Поділитися", "Відкрити Термінал тут", "Копіювати зведення файлів"]
        case "ja": return ["一括名称変更", "重複を検索", "ZIPアーカイブを作成", "クイックルック", "Finderで表示", "情報を見る", "パッケージの内容を表示", "ゴミ箱に入れる", "完全に削除", "ボリュームを取り出す", "拡張子を隠す", "拡張子を表示", "アイコンを抽出", "壁紙に設定", "共有", "ここでターミナルを開く", "ファイル概要をコピー"]
        case "ko": return ["일괄 이름 변경", "중복 찾기", "ZIP 아카이브 생성", "훑어보기", "Finder에서 보기", "정보 가져오기", "패키지 내용 보기", "휴지통으로 이동", "영구 삭제", "볼륨 추출", "확장자 숨기기", "확장자 표시", "아이콘 추출", "배경화면으로 설정", "공유", "여기서 터미널 열기", "파일 요약 복사"]
        case "zh-Hans": return ["批量重命名", "查找重复文件", "创建 ZIP 压缩包", "快速查看", "在访达中显示", "显示简介", "显示包内容", "移到废纸篓", "永久删除", "推出宗卷", "隐藏扩展名", "显示扩展名", "提取图标", "设为墙纸", "共享", "在此处打开终端", "复制文件摘要"]
        case "zh-TW": return ["批次重新命名", "尋找重複檔案", "製作 ZIP 壓縮檔", "快速查看", "在 Finder 中顯示", "取得資訊", "顯示套件內容", "移到垃圾桶", "永久刪除", "退出卷宗", "隱藏副檔名", "顯示副檔名", "擷取圖像", "設為背景圖片", "分享", "在此處打開終端機", "複製檔案摘要"]
        case "zh-HK": return ["批次重新命名", "尋找重複檔案", "製作 ZIP 壓縮檔", "快速查看", "在 Finder 中顯示", "取得資訊", "顯示套件內容", "移到垃圾桶", "永久刪除", "退出卷宗", "隱藏副檔名", "顯示副檔名", "擷取圖像", "設為背景圖片", "分享", "在此處開啟終端機", "複製檔案摘要"]
        default: return fileExtraTitles("en-US")
        }
    }

    private static func mediaExtraTitles(_ language: String) -> [String] {
        switch language {
        case "en-US": return ["Reduce PDF Size", "Create Disk Image", "Create Encrypted Disk Image", "Extract Audio", "Paste Clipboard Image", "Paste Clipboard Files", "Paste Clipboard Aliases"]
        case "pt-BR": return ["Reduzir tamanho do PDF", "Criar imagem de disco", "Criar imagem de disco criptografada", "Extrair áudio", "Colar imagem copiada", "Colar arquivos copiados", "Colar aliases dos arquivos copiados"]
        case "es": return ["Reducir tamaño del PDF", "Crear imagen de disco", "Crear imagen de disco cifrada", "Extraer audio", "Pegar imagen copiada", "Pegar archivos copiados", "Pegar alias de archivos copiados"]
        case "fr": return ["Réduire la taille du PDF", "Créer une image disque", "Créer une image disque chiffrée", "Extraire l’audio", "Coller l’image copiée", "Coller les fichiers copiés", "Coller les alias des fichiers copiés"]
        case "de": return ["PDF verkleinern", "Disk-Image erstellen", "Verschlüsseltes Disk-Image erstellen", "Audio extrahieren", "Bild aus Zwischenablage einsetzen", "Dateien aus Zwischenablage einsetzen", "Aliasse aus Zwischenablage einsetzen"]
        case "it": return ["Riduci dimensione PDF", "Crea immagine disco", "Crea immagine disco crittografata", "Estrai audio", "Incolla immagine copiata", "Incolla file copiati", "Incolla alias dei file copiati"]
        case "tr": return ["PDF Boyutunu Küçült", "Disk Görüntüsü Oluştur", "Şifreli Disk Görüntüsü Oluştur", "Sesi Çıkar", "Panodaki Görseli Yapıştır", "Panodaki Dosyaları Yapıştır", "Panodaki Dosyaların Takma Adlarını Yapıştır"]
        case "sk": return ["Zmenšiť PDF", "Vytvoriť obraz disku", "Vytvoriť šifrovaný obraz disku", "Extrahovať zvuk", "Vložiť obrázok zo schránky", "Vložiť súbory zo schránky", "Vložiť aliasy súborov zo schránky"]
        case "ru": return ["Уменьшить размер PDF", "Создать образ диска", "Создать зашифрованный образ диска", "Извлечь аудио", "Вставить изображение из буфера", "Вставить файлы из буфера", "Вставить псевдонимы файлов из буфера"]
        case "uk": return ["Зменшити розмір PDF", "Створити образ диска", "Створити зашифрований образ диска", "Витягти аудіо", "Вставити зображення з буфера", "Вставити файли з буфера", "Вставити псевдоніми файлів з буфера"]
        case "ja": return ["PDFサイズを縮小", "ディスクイメージを作成", "暗号化ディスクイメージを作成", "音声を抽出", "コピーした画像をペースト", "コピーしたファイルをペースト", "コピーしたファイルのエイリアスをペースト"]
        case "ko": return ["PDF 크기 줄이기", "디스크 이미지 생성", "암호화된 디스크 이미지 생성", "오디오 추출", "복사한 이미지 붙여넣기", "복사한 파일 붙여넣기", "복사한 파일의 별칭 붙여넣기"]
        case "zh-Hans": return ["缩小 PDF 大小", "创建磁盘映像", "创建加密磁盘映像", "提取音频", "粘贴剪贴板图像", "粘贴剪贴板文件", "粘贴剪贴板文件替身"]
        case "zh-TW": return ["縮小 PDF 大小", "製作磁碟映像檔", "製作加密磁碟映像檔", "擷取音訊", "貼上剪貼簿影像", "貼上剪貼簿檔案", "貼上剪貼簿檔案替身"]
        case "zh-HK": return ["縮小 PDF 大小", "製作磁碟映像檔", "製作加密磁碟映像檔", "擷取音訊", "貼上剪貼簿影像", "貼上剪貼簿檔案", "貼上剪貼簿檔案替身"]
        default: return mediaExtraTitles("en-US")
        }
    }

    private static func navigationTitles(_ language: String) -> [String] {
        switch language {
        case "en-US": return ["Set File Icon", "Restore File Icon", "Set Default Application for File Type", "Open With Application", "Search in Folder", "Repair Filename Encoding", "Create Desktop Aliases", "Paste Clipboard as ZIP"]
        case "pt-BR": return ["Definir ícone", "Restaurar ícone", "Definir aplicativo padrão para o tipo de arquivo", "Abrir com aplicativo", "Buscar na pasta", "Corrigir codificação dos nomes", "Criar aliases na Mesa", "Colar arquivos copiados como ZIP"]
        case "es": return ["Asignar icono", "Restaurar icono", "Asignar aplicación predeterminada al tipo de archivo", "Abrir con aplicación", "Buscar en carpeta", "Reparar codificación de nombres", "Crear alias en el escritorio", "Pegar archivos copiados como ZIP"]
        case "fr": return ["Définir l’icône", "Restaurer l’icône", "Définir l’application par défaut pour ce type", "Ouvrir avec une application", "Rechercher dans le dossier", "Réparer l’encodage des noms", "Créer des alias sur le bureau", "Coller les fichiers copiés en ZIP"]
        case "de": return ["Dateisymbol festlegen", "Dateisymbol zurücksetzen", "Standard-App für Dateityp festlegen", "Mit App öffnen", "Im Ordner suchen", "Zeichenkodierung der Namen reparieren", "Aliasse auf Schreibtisch erstellen", "Kopierte Dateien als ZIP einsetzen"]
        case "it": return ["Imposta icona", "Ripristina icona", "Imposta app predefinita per tipo di file", "Apri con applicazione", "Cerca nella cartella", "Ripara codifica dei nomi", "Crea alias sulla scrivania", "Incolla file copiati come ZIP"]
        case "tr": return ["Dosya Simgesini Ayarla", "Dosya Simgesini Sıfırla", "Dosya Türünün Varsayılan Uygulamasını Ayarla", "Uygulamayla Aç", "Klasörde Ara", "Dosya Adı Kodlamasını Onar", "Masaüstünde Takma Ad Oluştur", "Panodaki Dosyaları ZIP Olarak Yapıştır"]
        case "sk": return ["Nastaviť ikonu", "Obnoviť ikonu", "Nastaviť predvolenú aplikáciu typu súboru", "Otvoriť v aplikácii", "Hľadať v priečinku", "Opraviť kódovanie názvov", "Vytvoriť aliasy na ploche", "Vložiť súbory zo schránky ako ZIP"]
        case "ru": return ["Назначить значок", "Восстановить значок", "Назначить приложение для типа файлов", "Открыть в приложении", "Поиск в папке", "Исправить кодировку имён", "Создать псевдонимы на рабочем столе", "Вставить файлы из буфера как ZIP"]
        case "uk": return ["Призначити піктограму", "Відновити піктограму", "Призначити програму для типу файлів", "Відкрити у програмі", "Пошук у папці", "Виправити кодування назв", "Створити псевдоніми на робочому столі", "Вставити файли з буфера як ZIP"]
        case "ja": return ["アイコンを設定", "アイコンを復元", "ファイルの種類のデフォルトアプリを設定", "アプリケーションで開く", "フォルダ内を検索", "ファイル名の文字コードを修復", "デスクトップにエイリアスを作成", "コピーしたファイルをZIPとしてペースト"]
        case "ko": return ["아이콘 설정", "아이콘 복원", "파일 유형의 기본 앱 설정", "앱으로 열기", "폴더에서 검색", "파일 이름 인코딩 복구", "데스크탑에 별칭 생성", "복사한 파일을 ZIP으로 붙여넣기"]
        case "zh-Hans": return ["设置文件图标", "还原文件图标", "设置文件类型的默认应用", "使用应用打开", "在文件夹中搜索", "修复文件名编码", "在桌面创建替身", "将剪贴板文件粘贴为 ZIP"]
        case "zh-TW": return ["設定檔案圖像", "還原檔案圖像", "設定檔案類型的預設應用程式", "使用應用程式打開", "在資料夾中搜尋", "修復檔案名稱編碼", "在桌面製作替身", "將剪貼簿檔案貼上為 ZIP"]
        case "zh-HK": return ["設定檔案圖像", "還原檔案圖像", "設定檔案類型的預設應用程式", "使用應用程式開啟", "在資料夾中搜尋", "修復檔案名稱編碼", "在桌面製作替身", "將剪貼簿檔案貼上為 ZIP"]
        default: return navigationTitles("en-US")
        }
    }

    private static func captureTitles(_ language: String) -> [String] {
        switch language {
        case "en-US": return ["Record Microphone", "Record Camera"]
        case "pt-BR": return ["Gravar microfone", "Gravar câmera"]
        case "es": return ["Grabar micrófono", "Grabar cámara"]
        case "fr": return ["Enregistrer le microphone", "Enregistrer la caméra"]
        case "de": return ["Mikrofon aufnehmen", "Kamera aufnehmen"]
        case "it": return ["Registra microfono", "Registra videocamera"]
        case "tr": return ["Mikrofonu Kaydet", "Kamerayı Kaydet"]
        case "sk": return ["Nahrať mikrofón", "Nahrať kameru"]
        case "ru": return ["Записать микрофон", "Записать камеру"]
        case "uk": return ["Записати мікрофон", "Записати камеру"]
        case "ja": return ["マイクを録音", "カメラを録画"]
        case "ko": return ["마이크 녹음", "카메라 녹화"]
        case "zh-Hans": return ["录制麦克风", "录制摄像头"]
        case "zh-TW": return ["錄製麥克風", "錄製攝影機"]
        case "zh-HK": return ["錄製咪高峰", "錄製攝影機"]
        default: return captureTitles("en-US")
        }
    }
}

private extension FinderToolsAction {
    static func integrationTitles(_ language: String) -> [String] {
        switch language {
        case "pt-BR": return ["Recortar arquivos", "Colar arquivos recortados", "AirDrop", "Desinstalar aplicativo"]
        case "es": return ["Cortar archivos", "Pegar archivos cortados", "AirDrop", "Desinstalar aplicación"]
        case "fr": return ["Couper les fichiers", "Coller les fichiers coupés", "AirDrop", "Désinstaller l’application"]
        case "de": return ["Dateien ausschneiden", "Ausgeschnittene Dateien einsetzen", "AirDrop", "App deinstallieren"]
        case "it": return ["Taglia file", "Incolla file tagliati", "AirDrop", "Disinstalla applicazione"]
        case "tr": return ["Dosyaları Kes", "Kesilen Dosyaları Yapıştır", "AirDrop", "Uygulamayı Kaldır"]
        case "sk": return ["Vystrihnúť súbory", "Vložiť vystrihnuté súbory", "AirDrop", "Odinštalovať aplikáciu"]
        case "ru": return ["Вырезать файлы", "Вставить вырезанные файлы", "AirDrop", "Удалить приложение"]
        case "uk": return ["Вирізати файли", "Вставити вирізані файли", "AirDrop", "Видалити програму"]
        case "ja": return ["ファイルをカット", "カットしたファイルをペースト", "AirDrop", "アプリをアンインストール"]
        case "ko": return ["파일 잘라내기", "잘라낸 파일 붙여넣기", "AirDrop", "앱 제거"]
        case "zh-Hans": return ["剪切文件", "粘贴已剪切的文件", "AirDrop", "卸载应用"]
        case "zh-TW", "zh-HK": return ["剪下檔案", "貼上已剪下的檔案", "AirDrop", "解除安裝應用程式"]
        default: return ["Cut Files", "Paste Cut Files", "AirDrop", "Uninstall Application"]
        }
    }
}
