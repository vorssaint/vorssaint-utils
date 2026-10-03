// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// Strings for the media tools' PDF compressor.
struct MediaPDFStrings {
    let tool: String
    let start: String
    let resolution: String
    let dpiFormat: String
    let grayscale: String
    let caption: String
    let notSmallerFormat: String
    let notDownloaded: String
    let notWritable: String
    let notEnoughSpace: String
    let encrypted: String
    let signed: String
    let permissions: String
    let tagged: String
    let forms: String
    let attachments: String
    let scripted: String

    func protectionMessage(_ protection: MediaPDFCompressor.Protection) -> String {
        switch protection {
        case .encrypted: return encrypted
        case .signed: return signed
        case .permissions: return permissions
        case .tagged: return tagged
        case .forms: return forms
        case .attachments: return attachments
        case .scripted: return scripted
        }
    }

    static func localized(_ language: AppLanguage) -> MediaPDFStrings {
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
        case .uk: return .uk
        case .zhHans: return .zhHans
        case .zhTW: return .zhTW
        case .zhHK: return .zhHK
        }
    }

    static let enUS = MediaPDFStrings(
        tool: "PDF",
        start: "Compress PDF",
        resolution: "Image resolution",
        dpiFormat: "%d dpi",
        grayscale: "Convert to grayscale",
        caption: "Images inside the PDF are resampled; text, links and form fields stay as they are. Grayscale also turns text and drawings gray. The original file is never changed.",
        notSmallerFormat: "The compressed copy wasn’t at least 5%% smaller (%@ → %@), so nothing was saved.",
        notDownloaded: "This PDF is in iCloud and not downloaded yet. Download it first.",
        notWritable: "That folder can’t be written to. Choose another output location.",
        notEnoughSpace: "There isn’t enough free space for the compressed copy.",
        encrypted: "Left alone: this PDF is encrypted or password-protected.",
        signed: "Left alone: this PDF is digitally signed, and rewriting it would break the signature.",
        permissions: "Left alone: this PDF restricts changes.",
        tagged: "Left alone: this PDF is tagged for accessibility, and rewriting it would lose the tags.",
        forms: "Left alone: this PDF has an XFA form.",
        attachments: "Left alone: this PDF has attached files.",
        scripted: "Left alone: this PDF contains scripts.")

    static let ptBR = MediaPDFStrings(
        tool: "PDF",
        start: "Comprimir PDF",
        resolution: "Resolução das imagens",
        dpiFormat: "%d dpi",
        grayscale: "Converter para tons de cinza",
        caption: "As imagens dentro do PDF são reamostradas; texto, links e campos de formulário ficam como estão. Tons de cinza também deixam texto e desenhos em cinza. O arquivo original nunca é alterado.",
        notSmallerFormat: "A cópia comprimida não ficou pelo menos 5%% menor (%@ → %@), então nada foi salvo.",
        notDownloaded: "Este PDF está no iCloud e ainda não foi baixado. Baixe-o primeiro.",
        notWritable: "Não é possível gravar nessa pasta. Escolha outro local de saída.",
        notEnoughSpace: "Não há espaço livre suficiente para a cópia comprimida.",
        encrypted: "Não alterado: este PDF está criptografado ou protegido por senha.",
        signed: "Não alterado: este PDF tem assinatura digital, e reescrevê-lo invalidaria a assinatura.",
        permissions: "Não alterado: este PDF restringe alterações.",
        tagged: "Não alterado: este PDF tem tags de acessibilidade, que seriam perdidas.",
        forms: "Não alterado: este PDF tem um formulário XFA.",
        attachments: "Não alterado: este PDF tem arquivos anexados.",
        scripted: "Não alterado: este PDF contém scripts.")

    static let tr = MediaPDFStrings(
        tool: "PDF",
        start: "PDF’yi sıkıştır",
        resolution: "Resim çözünürlüğü",
        dpiFormat: "%d dpi",
        grayscale: "Gri tonlamaya dönüştür",
        caption: "PDF’teki resimler yeniden örneklenir; metin, bağlantılar ve form alanları olduğu gibi kalır. Gri tonlama metni ve çizimleri de griye çevirir. Özgün dosya hiçbir zaman değiştirilmez.",
        notSmallerFormat: "Sıkıştırılmış kopya en az %%5 daha küçük olmadı (%@ → %@), bu yüzden hiçbir şey kaydedilmedi.",
        notDownloaded: "Bu PDF iCloud’da ve henüz indirilmedi. Önce indirin.",
        notWritable: "Bu klasöre yazılamıyor. Başka bir çıktı konumu seçin.",
        notEnoughSpace: "Sıkıştırılmış kopya için yeterli boş alan yok.",
        encrypted: "Dokunulmadı: bu PDF şifreli veya parola korumalı.",
        signed: "Dokunulmadı: bu PDF dijital olarak imzalı; yeniden yazmak imzayı bozar.",
        permissions: "Dokunulmadı: bu PDF değişiklikleri kısıtlıyor.",
        tagged: "Dokunulmadı: bu PDF erişilebilirlik etiketleri içeriyor; etiketler kaybolur.",
        forms: "Dokunulmadı: bu PDF bir XFA formu içeriyor.",
        attachments: "Dokunulmadı: bu PDF’te ekli dosyalar var.",
        scripted: "Dokunulmadı: bu PDF betikler içeriyor.")

    static let ru = MediaPDFStrings(
        tool: "PDF",
        start: "Сжать PDF",
        resolution: "Разрешение изображений",
        dpiFormat: "%d dpi",
        grayscale: "Преобразовать в оттенки серого",
        caption: "Изображения внутри PDF пересчитываются; текст, ссылки и поля форм остаются как есть. Оттенки серого делают серыми и текст с рисунками. Исходный файл никогда не изменяется.",
        notSmallerFormat: "Сжатая копия не стала меньше хотя бы на 5%% (%@ → %@), поэтому ничего не сохранено.",
        notDownloaded: "Этот PDF находится в iCloud и ещё не загружен. Сначала загрузите его.",
        notWritable: "В эту папку нельзя записать. Выберите другое место сохранения.",
        notEnoughSpace: "Недостаточно свободного места для сжатой копии.",
        encrypted: "Не изменён: PDF зашифрован или защищён паролем.",
        signed: "Не изменён: PDF подписан цифровой подписью, перезапись нарушит подпись.",
        permissions: "Не изменён: PDF ограничивает изменения.",
        tagged: "Не изменён: PDF размечен для универсального доступа, разметка была бы потеряна.",
        forms: "Не изменён: PDF содержит форму XFA.",
        attachments: "Не изменён: PDF содержит вложенные файлы.",
        scripted: "Не изменён: PDF содержит скрипты.")

    static let es = MediaPDFStrings(
        tool: "PDF",
        start: "Comprimir PDF",
        resolution: "Resolución de imágenes",
        dpiFormat: "%d ppp",
        grayscale: "Convertir a escala de grises",
        caption: "Las imágenes del PDF se remuestrean; el texto, los enlaces y los campos de formulario se mantienen. La escala de grises también vuelve gris el texto y los dibujos. El archivo original nunca se modifica.",
        notSmallerFormat: "La copia comprimida no quedó al menos un 5 %% más pequeña (%@ → %@), así que no se guardó nada.",
        notDownloaded: "Este PDF está en iCloud y aún no se ha descargado. Descárgalo primero.",
        notWritable: "No se puede escribir en esa carpeta. Elige otra ubicación de salida.",
        notEnoughSpace: "No hay espacio libre suficiente para la copia comprimida.",
        encrypted: "Sin cambios: este PDF está cifrado o protegido con contraseña.",
        signed: "Sin cambios: este PDF tiene firma digital y reescribirlo la invalidaría.",
        permissions: "Sin cambios: este PDF restringe las modificaciones.",
        tagged: "Sin cambios: este PDF tiene etiquetas de accesibilidad que se perderían.",
        forms: "Sin cambios: este PDF tiene un formulario XFA.",
        attachments: "Sin cambios: este PDF tiene archivos adjuntos.",
        scripted: "Sin cambios: este PDF contiene scripts.")

    static let sk = MediaPDFStrings(
        tool: "PDF",
        start: "Komprimovať PDF",
        resolution: "Rozlíšenie obrázkov",
        dpiFormat: "%d dpi",
        grayscale: "Previesť na odtiene sivej",
        caption: "Obrázky v PDF sa prevzorkujú; text, odkazy a polia formulára zostanú bez zmeny. Odtiene sivej zmenia na sivé aj text a kresby. Pôvodný súbor sa nikdy nemení.",
        notSmallerFormat: "Komprimovaná kópia nie je menšia aspoň o 5 %% (%@ → %@), preto sa nič neuložilo.",
        notDownloaded: "Toto PDF je v iCloude a ešte nie je stiahnuté. Najprv ho stiahnite.",
        notWritable: "Do tohto priečinka sa nedá zapisovať. Vyberte iné umiestnenie výstupu.",
        notEnoughSpace: "Na komprimovanú kópiu nie je dosť voľného miesta.",
        encrypted: "Ponechané: toto PDF je zašifrované alebo chránené heslom.",
        signed: "Ponechané: toto PDF je digitálne podpísané a prepísanie by podpis porušilo.",
        permissions: "Ponechané: toto PDF obmedzuje zmeny.",
        tagged: "Ponechané: toto PDF má značky prístupnosti, ktoré by sa stratili.",
        forms: "Ponechané: toto PDF obsahuje formulár XFA.",
        attachments: "Ponechané: toto PDF má priložené súbory.",
        scripted: "Ponechané: toto PDF obsahuje skripty.")

    static let de = MediaPDFStrings(
        tool: "PDF",
        start: "PDF komprimieren",
        resolution: "Bildauflösung",
        dpiFormat: "%d dpi",
        grayscale: "In Graustufen umwandeln",
        caption: "Bilder im PDF werden neu berechnet; Text, Links und Formularfelder bleiben unverändert. Graustufen machen auch Text und Zeichnungen grau. Die Originaldatei wird nie verändert.",
        notSmallerFormat: "Die komprimierte Kopie war nicht mindestens 5 %% kleiner (%@ → %@), daher wurde nichts gesichert.",
        notDownloaded: "Dieses PDF liegt in iCloud und ist noch nicht geladen. Lade es zuerst.",
        notWritable: "In diesen Ordner kann nicht geschrieben werden. Wähle einen anderen Speicherort.",
        notEnoughSpace: "Für die komprimierte Kopie ist nicht genug freier Speicher vorhanden.",
        encrypted: "Unverändert: Dieses PDF ist verschlüsselt oder passwortgeschützt.",
        signed: "Unverändert: Dieses PDF ist digital signiert, Neuschreiben würde die Signatur ungültig machen.",
        permissions: "Unverändert: Dieses PDF schränkt Änderungen ein.",
        tagged: "Unverändert: Dieses PDF hat Tags für Bedienungshilfen, die verloren gingen.",
        forms: "Unverändert: Dieses PDF enthält ein XFA-Formular.",
        attachments: "Unverändert: Dieses PDF hat angehängte Dateien.",
        scripted: "Unverändert: Dieses PDF enthält Skripte.")

    static let fr = MediaPDFStrings(
        tool: "PDF",
        start: "Compresser le PDF",
        resolution: "Résolution des images",
        dpiFormat: "%d ppp",
        grayscale: "Convertir en niveaux de gris",
        caption: "Les images du PDF sont rééchantillonnées ; le texte, les liens et les champs de formulaire restent intacts. Les niveaux de gris rendent aussi le texte et les dessins gris. Le fichier d’origine n’est jamais modifié.",
        notSmallerFormat: "La copie compressée n’était pas plus petite d’au moins 5 %% (%@ → %@), rien n’a donc été enregistré.",
        notDownloaded: "Ce PDF est dans iCloud et n’est pas encore téléchargé. Téléchargez-le d’abord.",
        notWritable: "Impossible d’écrire dans ce dossier. Choisissez un autre emplacement de sortie.",
        notEnoughSpace: "Il n’y a pas assez d’espace libre pour la copie compressée.",
        encrypted: "Inchangé : ce PDF est chiffré ou protégé par mot de passe.",
        signed: "Inchangé : ce PDF est signé numériquement, le réécrire invaliderait la signature.",
        permissions: "Inchangé : ce PDF restreint les modifications.",
        tagged: "Inchangé : ce PDF est balisé pour l’accessibilité, les balises seraient perdues.",
        forms: "Inchangé : ce PDF contient un formulaire XFA.",
        attachments: "Inchangé : ce PDF contient des pièces jointes.",
        scripted: "Inchangé : ce PDF contient des scripts.")

    static let it = MediaPDFStrings(
        tool: "PDF",
        start: "Comprimi PDF",
        resolution: "Risoluzione immagini",
        dpiFormat: "%d dpi",
        grayscale: "Converti in scala di grigi",
        caption: "Le immagini nel PDF vengono ricampionate; testo, link e campi dei moduli restano invariati. La scala di grigi rende grigi anche testo e disegni. Il file originale non viene mai modificato.",
        notSmallerFormat: "La copia compressa non è risultata più piccola di almeno il 5%% (%@ → %@), quindi non è stato salvato nulla.",
        notDownloaded: "Questo PDF è su iCloud e non è ancora scaricato. Scaricalo prima.",
        notWritable: "Impossibile scrivere in quella cartella. Scegli un’altra posizione di uscita.",
        notEnoughSpace: "Non c’è abbastanza spazio libero per la copia compressa.",
        encrypted: "Non modificato: questo PDF è crittografato o protetto da password.",
        signed: "Non modificato: questo PDF ha una firma digitale che verrebbe invalidata.",
        permissions: "Non modificato: questo PDF limita le modifiche.",
        tagged: "Non modificato: questo PDF ha tag di accessibilità che andrebbero persi.",
        forms: "Non modificato: questo PDF contiene un modulo XFA.",
        attachments: "Non modificato: questo PDF ha file allegati.",
        scripted: "Non modificato: questo PDF contiene script.")

    static let ja = MediaPDFStrings(
        tool: "PDF",
        start: "PDFを圧縮",
        resolution: "画像の解像度",
        dpiFormat: "%d dpi",
        grayscale: "グレースケールに変換",
        caption: "PDF内の画像を再サンプリングします。テキスト、リンク、フォームフィールドはそのまま残ります。グレースケールではテキストや図形もグレーになります。元のファイルは変更されません。",
        notSmallerFormat: "圧縮したコピーが5%%以上小さくならなかったため（%@ → %@）、何も保存しませんでした。",
        notDownloaded: "このPDFはiCloud上にあり、まだダウンロードされていません。先にダウンロードしてください。",
        notWritable: "そのフォルダには書き込めません。別の保存先を選んでください。",
        notEnoughSpace: "圧縮したコピーを保存する空き容量が足りません。",
        encrypted: "変更なし：このPDFは暗号化またはパスワードで保護されています。",
        signed: "変更なし：このPDFにはデジタル署名があり、書き換えると署名が無効になります。",
        permissions: "変更なし：このPDFは変更が制限されています。",
        tagged: "変更なし：このPDFにはアクセシビリティ用のタグがあり、書き換えると失われます。",
        forms: "変更なし：このPDFにはXFAフォームがあります。",
        attachments: "変更なし：このPDFには添付ファイルがあります。",
        scripted: "変更なし：このPDFにはスクリプトが含まれています。")

    static let ko = MediaPDFStrings(
        tool: "PDF",
        start: "PDF 압축",
        resolution: "이미지 해상도",
        dpiFormat: "%d dpi",
        grayscale: "회색조로 변환",
        caption: "PDF 안의 이미지를 다시 샘플링합니다. 텍스트, 링크, 양식 필드는 그대로 유지됩니다. 회색조는 텍스트와 그림도 회색으로 바꿉니다. 원본 파일은 변경되지 않습니다.",
        notSmallerFormat: "압축한 사본이 5%% 이상 작아지지 않아(%@ → %@) 아무것도 저장하지 않았습니다.",
        notDownloaded: "이 PDF는 iCloud에 있으며 아직 다운로드되지 않았습니다. 먼저 다운로드하세요.",
        notWritable: "해당 폴더에 쓸 수 없습니다. 다른 저장 위치를 선택하세요.",
        notEnoughSpace: "압축한 사본을 저장할 여유 공간이 부족합니다.",
        encrypted: "변경 안 함: 이 PDF는 암호화되었거나 암호로 보호되어 있습니다.",
        signed: "변경 안 함: 이 PDF는 디지털 서명되어 있어 다시 쓰면 서명이 손상됩니다.",
        permissions: "변경 안 함: 이 PDF는 변경을 제한합니다.",
        tagged: "변경 안 함: 이 PDF에는 손쉬운 사용 태그가 있어 다시 쓰면 사라집니다.",
        forms: "변경 안 함: 이 PDF에는 XFA 양식이 있습니다.",
        attachments: "변경 안 함: 이 PDF에는 첨부 파일이 있습니다.",
        scripted: "변경 안 함: 이 PDF에는 스크립트가 있습니다.")

    static let uk = MediaPDFStrings(
        tool: "PDF",
        start: "Стиснути PDF",
        resolution: "Роздільність зображень",
        dpiFormat: "%d dpi",
        grayscale: "Перетворити на відтінки сірого",
        caption: "Зображення всередині PDF перераховуються; текст, посилання й поля форм лишаються як є. Відтінки сірого роблять сірими також текст і малюнки. Вихідний файл ніколи не змінюється.",
        notSmallerFormat: "Стиснена копія не стала меншою хоча б на 5%% (%@ → %@), тому нічого не збережено.",
        notDownloaded: "Цей PDF в iCloud і ще не завантажений. Спершу завантажте його.",
        notWritable: "У цю папку неможливо записати. Виберіть інше місце збереження.",
        notEnoughSpace: "Недостатньо вільного місця для стисненої копії.",
        encrypted: "Не змінено: PDF зашифрований або захищений паролем.",
        signed: "Не змінено: PDF має цифровий підпис, перезапис зламав би підпис.",
        permissions: "Не змінено: PDF обмежує зміни.",
        tagged: "Не змінено: PDF має теги доступності, які було б втрачено.",
        forms: "Не змінено: PDF містить форму XFA.",
        attachments: "Не змінено: PDF має вкладені файли.",
        scripted: "Не змінено: PDF містить скрипти.")

    static let zhHans = MediaPDFStrings(
        tool: "PDF",
        start: "压缩 PDF",
        resolution: "图像分辨率",
        dpiFormat: "%d dpi",
        grayscale: "转换为灰度",
        caption: "PDF 中的图像会被重新采样；文本、链接和表单字段保持不变。灰度也会让文本和图形变灰。原始文件绝不会被更改。",
        notSmallerFormat: "压缩后的副本没有缩小至少 5%%（%@ → %@），因此未保存任何内容。",
        notDownloaded: "此 PDF 位于 iCloud 中，尚未下载。请先下载。",
        notWritable: "无法写入该文件夹。请选择其他输出位置。",
        notEnoughSpace: "没有足够的可用空间保存压缩后的副本。",
        encrypted: "未更改：此 PDF 已加密或受密码保护。",
        signed: "未更改：此 PDF 带有数字签名，重写会破坏签名。",
        permissions: "未更改：此 PDF 限制修改。",
        tagged: "未更改：此 PDF 带有辅助功能标签，重写会丢失标签。",
        forms: "未更改：此 PDF 包含 XFA 表单。",
        attachments: "未更改：此 PDF 带有附件。",
        scripted: "未更改：此 PDF 包含脚本。")

    static let zhTW = MediaPDFStrings(
        tool: "PDF",
        start: "壓縮 PDF",
        resolution: "影像解析度",
        dpiFormat: "%d dpi",
        grayscale: "轉換為灰階",
        caption: "PDF 中的影像會重新取樣；文字、連結和表單欄位保持不變。灰階也會讓文字和圖形變灰。原始檔案絕不會被更改。",
        notSmallerFormat: "壓縮後的副本沒有縮小至少 5%%（%@ → %@），因此未儲存任何內容。",
        notDownloaded: "此 PDF 位於 iCloud 中，尚未下載。請先下載。",
        notWritable: "無法寫入該檔案夾。請選擇其他輸出位置。",
        notEnoughSpace: "沒有足夠的可用空間儲存壓縮後的副本。",
        encrypted: "未更改：此 PDF 已加密或受密碼保護。",
        signed: "未更改：此 PDF 帶有數位簽章，重寫會破壞簽章。",
        permissions: "未更改：此 PDF 限制修改。",
        tagged: "未更改：此 PDF 帶有輔助使用標籤，重寫會遺失標籤。",
        forms: "未更改：此 PDF 包含 XFA 表單。",
        attachments: "未更改：此 PDF 帶有附件。",
        scripted: "未更改：此 PDF 包含指令碼。")

    static let zhHK = MediaPDFStrings(
        tool: "PDF",
        start: "壓縮 PDF",
        resolution: "影像解析度",
        dpiFormat: "%d dpi",
        grayscale: "轉換為灰階",
        caption: "PDF 中的影像會重新取樣；文字、連結和表單欄位保持不變。灰階也會讓文字和圖形變灰。原始檔案絕不會被更改。",
        notSmallerFormat: "壓縮後的副本沒有縮小至少 5%%（%@ → %@），因此未儲存任何內容。",
        notDownloaded: "此 PDF 位於 iCloud 中，尚未下載。請先下載。",
        notWritable: "無法寫入該檔案夾。請選擇其他輸出位置。",
        notEnoughSpace: "沒有足夠的可用空間儲存壓縮後的副本。",
        encrypted: "未更改：此 PDF 已加密或受密碼保護。",
        signed: "未更改：此 PDF 帶有數位簽章，重寫會破壞簽章。",
        permissions: "未更改：此 PDF 限制修改。",
        tagged: "未更改：此 PDF 帶有輔助使用標籤，重寫會遺失標籤。",
        forms: "未更改：此 PDF 包含 XFA 表單。",
        attachments: "未更改：此 PDF 帶有附件。",
        scripted: "未更改：此 PDF 包含指令碼。")
}
