// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

struct NotchFilesStrings {
    let archive: String
    let archiveHint: String
    let saved: String
    let downloadsTitle: String
    let downloadsDescription: String
    let downloadsHint: String
    let chooseFolder: String
    let folderUnavailable: String
    let waiting: String
    let inProgress: String
    let totalUnknown: String
    let completed: String
    let clearFolder: String
    let optimizeMedia: String
    let optimizeDropHint: String
    let resumeMedia: String
}

extension FeatureStrings {
    static func notchFiles(_ language: AppLanguage) -> NotchFilesStrings {
        switch language {
        case .enUS: return NotchFilesStrings(
            archive: "Create ZIP",
            archiveHint: "Each selected item is saved as a separate ZIP. Originals stay unchanged.",
            saved: "Saved",
            downloadsTitle: "Downloads",
            downloadsDescription: "See files arriving in a folder you choose, directly in the Dynamic Island.",
            downloadsHint: "Choose the folder where your browser saves downloads. Only that folder is watched.",
            chooseFolder: "Choose Folder…",
            folderUnavailable: "This folder is unavailable. Choose it again to restore access.",
            waiting: "No downloads in progress",
            inProgress: "Downloading",
            totalUnknown: "Total size unavailable",
            completed: "Download complete",
            clearFolder: "Forget Folder",
            optimizeMedia: "Optimize media",
            optimizeDropHint: "Drag images or one video onto the island, then drop on Optimize media to choose how to save a copy.",
            resumeMedia: "Return to media")
        case .ptBR: return NotchFilesStrings(
            archive: "Criar ZIP",
            archiveHint: "Cada item selecionado vira um ZIP separado. Os originais são preservados.",
            saved: "Salvo",
            downloadsTitle: "Downloads",
            downloadsDescription: "Veja os arquivos chegando em uma pasta escolhida, direto no Dynamic Island.",
            downloadsHint: "Escolha a pasta onde seu navegador salva os downloads. Só essa pasta será acompanhada.",
            chooseFolder: "Escolher pasta…",
            folderUnavailable: "A pasta está indisponível. Escolha novamente para recuperar o acesso.",
            waiting: "Nenhum download em andamento",
            inProgress: "Baixando",
            totalUnknown: "Tamanho total indisponível",
            completed: "Download concluído",
            clearFolder: "Esquecer pasta",
            optimizeMedia: "Otimizar mídia",
            optimizeDropHint: "Arraste imagens ou um vídeo até a ilha e solte em Otimizar mídia para escolher como salvar uma cópia.",
            resumeMedia: "Voltar à mídia")
        case .es: return NotchFilesStrings(
            archive: "Crear ZIP",
            archiveHint: "Cada elemento seleccionado se guarda en un ZIP separado. Se conservan los originales.",
            saved: "Guardado",
            downloadsTitle: "Descargas",
            downloadsDescription: "Ve los archivos que llegan a una carpeta elegida, directamente en el Dynamic Island.",
            downloadsHint: "Elige la carpeta donde tu navegador guarda las descargas. Solo se supervisa esa carpeta.",
            chooseFolder: "Elegir carpeta…",
            folderUnavailable: "La carpeta no está disponible. Elígela de nuevo para recuperar el acceso.",
            waiting: "No hay descargas en curso",
            inProgress: "Descargando",
            totalUnknown: "Tamaño total no disponible",
            completed: "Descarga completada",
            clearFolder: "Olvidar carpeta",
            optimizeMedia: "Optimizar contenido",
            optimizeDropHint: "Arrastra imágenes o un vídeo a la isla y suéltalos en Optimizar contenido para elegir cómo guardar una copia.",
            resumeMedia: "Volver al contenido multimedia")
        case .de: return NotchFilesStrings(
            archive: "ZIP erstellen",
            archiveHint: "Jedes ausgewählte Objekt wird als eigene ZIP-Datei gesichert. Die Originale bleiben erhalten.",
            saved: "Gesichert",
            downloadsTitle: "Downloads",
            downloadsDescription: "Sieh direkt im Dynamic Island, welche Dateien in einem ausgewählten Ordner ankommen.",
            downloadsHint: "Wähle den Ordner, in dem dein Browser Downloads sichert. Nur dieser Ordner wird beobachtet.",
            chooseFolder: "Ordner auswählen…",
            folderUnavailable: "Der Ordner ist nicht verfügbar. Wähle ihn erneut aus, um den Zugriff wiederherzustellen.",
            waiting: "Keine laufenden Downloads",
            inProgress: "Wird geladen",
            totalUnknown: "Gesamtgröße nicht verfügbar",
            completed: "Download abgeschlossen",
            clearFolder: "Ordner vergessen",
            optimizeMedia: "Medien optimieren",
            optimizeDropHint: "Ziehe Bilder oder ein Video auf die Insel und lege sie auf Medien optimieren ab, um eine Kopie nach Wunsch zu sichern.",
            resumeMedia: "Zurück zu Medien")
        case .fr: return NotchFilesStrings(
            archive: "Créer un ZIP",
            archiveHint: "Chaque élément sélectionné est enregistré dans un ZIP distinct. Les originaux sont conservés.",
            saved: "Enregistré",
            downloadsTitle: "Téléchargements",
            downloadsDescription: "Voyez les fichiers arriver dans un dossier choisi, directement dans le Dynamic Island.",
            downloadsHint: "Choisissez le dossier où votre navigateur enregistre les téléchargements. Seul ce dossier est suivi.",
            chooseFolder: "Choisir un dossier…",
            folderUnavailable: "Ce dossier est indisponible. Choisissez-le à nouveau pour rétablir l’accès.",
            waiting: "Aucun téléchargement en cours",
            inProgress: "Téléchargement",
            totalUnknown: "Taille totale indisponible",
            completed: "Téléchargement terminé",
            clearFolder: "Oublier le dossier",
            optimizeMedia: "Optimiser les médias",
            optimizeDropHint: "Faites glisser des images ou une vidéo sur l’îlot, puis déposez-les sur Optimiser les médias pour choisir comment enregistrer une copie.",
            resumeMedia: "Revenir aux médias")
        case .it: return NotchFilesStrings(
            archive: "Crea ZIP",
            archiveHint: "Ogni elemento selezionato viene salvato in uno ZIP separato. Gli originali restano invariati.",
            saved: "Salvato",
            downloadsTitle: "Download",
            downloadsDescription: "Vedi i file in arrivo in una cartella scelta, direttamente nel Dynamic Island.",
            downloadsHint: "Scegli la cartella in cui il browser salva i download. Viene monitorata solo quella cartella.",
            chooseFolder: "Scegli cartella…",
            folderUnavailable: "La cartella non è disponibile. Sceglila di nuovo per ripristinare l’accesso.",
            waiting: "Nessun download in corso",
            inProgress: "Download in corso",
            totalUnknown: "Dimensione totale non disponibile",
            completed: "Download completato",
            clearFolder: "Dimentica cartella",
            optimizeMedia: "Ottimizza contenuti",
            optimizeDropHint: "Trascina immagini o un video sull’isola e rilasciali su Ottimizza contenuti per scegliere come salvare una copia.",
            resumeMedia: "Torna ai contenuti multimediali")
        case .ru: return NotchFilesStrings(
            archive: "Создать ZIP",
            archiveHint: "Каждый выбранный объект сохраняется в отдельный ZIP. Оригиналы остаются без изменений.",
            saved: "Сохранено",
            downloadsTitle: "Загрузки",
            downloadsDescription: "Следите за файлами, поступающими в выбранную папку, прямо в вырезе.",
            downloadsHint: "Выберите папку, в которую браузер сохраняет загрузки. Отслеживается только эта папка.",
            chooseFolder: "Выбрать папку…",
            folderUnavailable: "Папка недоступна. Выберите её снова, чтобы восстановить доступ.",
            waiting: "Нет текущих загрузок",
            inProgress: "Загрузка",
            totalUnknown: "Общий размер недоступен",
            completed: "Загрузка завершена",
            clearFolder: "Забыть папку",
            optimizeMedia: "Оптимизировать медиа",
            optimizeDropHint: "Перетащите изображения или одно видео на островок и отпустите над «Оптимизировать медиа», чтобы выбрать параметры сохранения копии.",
            resumeMedia: "Вернуться к медиа")
        case .tr: return NotchFilesStrings(
            archive: "ZIP oluştur",
            archiveHint: "Seçilen her öğe ayrı bir ZIP olarak kaydedilir. Orijinaller korunur.",
            saved: "Kaydedildi",
            downloadsTitle: "İndirmeler",
            downloadsDescription: "Seçtiğiniz klasöre gelen dosyaları doğrudan çentikte görün.",
            downloadsHint: "Tarayıcınızın indirmeleri kaydettiği klasörü seçin. Yalnızca bu klasör izlenir.",
            chooseFolder: "Klasör seç…",
            folderUnavailable: "Bu klasöre erişilemiyor. Erişimi yeniden sağlamak için tekrar seçin.",
            waiting: "Devam eden indirme yok",
            inProgress: "İndiriliyor",
            totalUnknown: "Toplam boyut bilinmiyor",
            completed: "İndirme tamamlandı",
            clearFolder: "Klasörü unut",
            optimizeMedia: "Medyayı iyileştir",
            optimizeDropHint: "Görüntüleri veya tek bir videoyu adaya sürükleyip Medyayı iyileştir alanına bırakın ve kopyayı nasıl kaydedeceğinizi seçin.",
            resumeMedia: "Medyaya dön")
        case .ja: return NotchFilesStrings(
            archive: "ZIPを作成",
            archiveHint: "選択した項目ごとにZIPを保存します。元のファイルは保持されます。",
            saved: "保存済み",
            downloadsTitle: "ダウンロード",
            downloadsDescription: "選択したフォルダに届くファイルをDynamic Islandで確認できます。",
            downloadsHint: "ブラウザのダウンロード保存先フォルダを選択してください。このフォルダのみを監視します。",
            chooseFolder: "フォルダを選択…",
            folderUnavailable: "このフォルダは利用できません。アクセスを復元するには、もう一度選択してください。",
            waiting: "進行中のダウンロードはありません",
            inProgress: "ダウンロード中",
            totalUnknown: "合計サイズは不明です",
            completed: "ダウンロード完了",
            clearFolder: "フォルダの選択を解除",
            optimizeMedia: "メディアを最適化",
            optimizeDropHint: "画像または1本の動画をアイランドにドラッグし、「メディアを最適化」にドロップして、コピーの保存方法を選びます。",
            resumeMedia: "メディアに戻る")
        case .ko: return NotchFilesStrings(
            archive: "ZIP 만들기",
            archiveHint: "선택한 항목마다 별도의 ZIP으로 저장합니다. 원본은 유지됩니다.",
            saved: "저장됨",
            downloadsTitle: "다운로드",
            downloadsDescription: "선택한 폴더에 도착하는 파일을 Dynamic Island에서 바로 확인하세요.",
            downloadsHint: "브라우저가 다운로드를 저장하는 폴더를 선택하세요. 해당 폴더만 확인합니다.",
            chooseFolder: "폴더 선택…",
            folderUnavailable: "이 폴더를 사용할 수 없습니다. 접근 권한을 복원하려면 다시 선택하세요.",
            waiting: "진행 중인 다운로드 없음",
            inProgress: "다운로드 중",
            totalUnknown: "전체 크기를 알 수 없음",
            completed: "다운로드 완료",
            clearFolder: "폴더 선택 해제",
            optimizeMedia: "미디어 최적화",
            optimizeDropHint: "이미지 또는 동영상 하나를 아일랜드로 드래그한 뒤 미디어 최적화에 놓으면 사본 저장 방식을 선택할 수 있습니다.",
            resumeMedia: "미디어로 돌아가기")
        case .zhHans: return NotchFilesStrings(
            archive: "创建 ZIP",
            archiveHint: "每个所选项目单独保存为 ZIP。原始文件保持不变。",
            saved: "已保存",
            downloadsTitle: "下载",
            downloadsDescription: "直接在Dynamic Island中查看文件下载到所选文件夹的情况。",
            downloadsHint: "选择浏览器保存下载文件的文件夹。仅监视此文件夹。",
            chooseFolder: "选择文件夹…",
            folderUnavailable: "此文件夹不可用。请重新选择以恢复访问。",
            waiting: "没有正在进行的下载",
            inProgress: "正在下载",
            totalUnknown: "总大小未知",
            completed: "下载完成",
            clearFolder: "忘记文件夹",
            optimizeMedia: "优化媒体",
            optimizeDropHint: "将图片或一个视频拖到灵动岛，再放到“优化媒体”上，选择如何保存副本。",
            resumeMedia: "返回媒体")
        case .zhTW: return NotchFilesStrings(
            archive: "製作 ZIP",
            archiveHint: "每個所選項目會儲存為個別的 ZIP。原始檔案保持不變。",
            saved: "已儲存",
            downloadsTitle: "下載",
            downloadsDescription: "直接在Dynamic Island中查看檔案下載到所選檔案夾的情況。",
            downloadsHint: "選擇瀏覽器儲存下載檔案的檔案夾。只會監看此檔案夾。",
            chooseFolder: "選擇檔案夾…",
            folderUnavailable: "此檔案夾無法使用。請重新選擇以恢復存取。",
            waiting: "沒有進行中的下載",
            inProgress: "正在下載",
            totalUnknown: "總大小未知",
            completed: "下載完成",
            clearFolder: "忘記檔案夾",
            optimizeMedia: "最佳化媒體",
            optimizeDropHint: "將圖片或一部影片拖曳到動態島，再放到「最佳化媒體」上，選擇如何儲存副本。",
            resumeMedia: "返回媒體")
        case .zhHK: return NotchFilesStrings(
            archive: "製作 ZIP",
            archiveHint: "每個所選項目會儲存為個別的 ZIP。原始檔案保持不變。",
            saved: "已儲存",
            downloadsTitle: "下載",
            downloadsDescription: "直接在Dynamic Island中查看檔案下載到所選資料夾的情況。",
            downloadsHint: "選擇瀏覽器儲存下載檔案的資料夾。只會監察此資料夾。",
            chooseFolder: "選擇資料夾…",
            folderUnavailable: "此資料夾無法使用。請重新選擇以恢復取用。",
            waiting: "沒有進行中的下載",
            inProgress: "正在下載",
            totalUnknown: "總大小不詳",
            completed: "下載完成",
            clearFolder: "忘記資料夾",
            optimizeMedia: "最佳化媒體",
            optimizeDropHint: "將圖片或一段影片拖曳到動態島，再放到「最佳化媒體」上，選擇如何儲存副本。",
            resumeMedia: "返回媒體")
        case .ar: return NotchFilesStrings(
            archive: "إنشاء ZIP",
            archiveHint: "يُحفظ كل عنصر محدد في ملف ZIP منفصل. وتبقى الأصول دون تغيير.",
            saved: "تم الحفظ",
            downloadsTitle: "التنزيلات",
            downloadsDescription: "شاهِد الملفات الواصلة إلى مجلد تختاره، في الجزيرة الديناميكية مباشرةً.",
            downloadsHint: "اختر المجلد الذي يحفظ فيه متصفحك التنزيلات. ولا يُراقَب سواه.",
            chooseFolder: "اختيار مجلد…",
            folderUnavailable: "هذا المجلد غير متاح. اختره مجددًا لاستعادة الوصول.",
            waiting: "لا توجد تنزيلات جارية",
            inProgress: "جارٍ التنزيل",
            totalUnknown: "الحجم الإجمالي غير متاح",
            completed: "اكتمل التنزيل",
            clearFolder: "نسيان المجلد",
            optimizeMedia: "تحسين الوسائط",
            optimizeDropHint: "اسحب صورًا أو مقطع فيديو واحدًا إلى الجزيرة، ثم أفلِته على “تحسين الوسائط” لاختيار طريقة حفظ نسخة.",
            resumeMedia: "العودة إلى الوسائط")
        }
    }
}
