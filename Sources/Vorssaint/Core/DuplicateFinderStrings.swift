// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

struct DuplicateFinderStrings {
    let title: String
    let intro: String
    let open: String
    let scope: String
    let privacy: String
    let add: String
    let scan: String
    let cancel: String
    let trash: String
    let folders: String
    let remove: String
    let cancelled: String
    let noDuplicates: String
    let preview: String
    let reveal: String
    let choosePreview: String
    let enumerating: String
    let comparing: String
    let working: String
    let logicalSize: String
    let keepNote: String
    let moved: String
    let notMoved: String
    let skipped: String
    let confirm: String
    let trashNote: String
    let hidden: String
    let package: String
    let trashReason: String
    let symbolicLink: String
    let alias: String
    let hardLink: String
    let cloud: String
    let resourceFork: String
    let inaccessible: String
    let changed: String
    let cancelledReason: String
    let keepCopy: String
    let failed: String

    func reason(_ reason: DuplicateFinderSupport.Reason) -> String {
        switch reason {
        case .hidden: return hidden
        case .package: return package
        case .trash: return trashReason
        case .symbolicLink: return symbolicLink
        case .alias: return alias
        case .hardLink: return hardLink
        case .cloud: return cloud
        case .resourceFork: return resourceFork
        case .inaccessible: return inaccessible
        case .changed: return changed
        case .cancelled: return cancelledReason
        case .keepCopy: return keepCopy
        case .failed: return failed
        }
    }
}

extension FeatureStrings {
    static func duplicateFinder(_ language: AppLanguage) -> DuplicateFinderStrings {
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
}

extension DuplicateFinderStrings {
    static let enUS = DuplicateFinderStrings(
        title: "Duplicate File Finder",
        intro: "Choose folders to find identical file contents, preview copies, and review each removal.",
        open: "Open Duplicate File Finder",
        scope: "Scans visible, ordinary local files in selected folders and subfolders. Skips packages, links, cloud-only files and resource forks.",
        privacy: "Folders, results and previews stay in this window session. File contents are read locally and never uploaded.",
        add: "Add Folders…",
        scan: "Scan",
        cancel: "Cancel",
        trash: "Move Selected to Trash",
        folders: "Folders",
        remove: "Remove Folder",
        cancelled: "Scan cancelled",
        noDuplicates: "No exact duplicates found",
        preview: "Preview",
        reveal: "Reveal in Finder",
        choosePreview: "Select a file to preview.",
        enumerating: "Discovering files",
        comparing: "Comparing contents",
        working: "Working…",
        logicalSize: "Selected duplicate bytes",
        keepNote: "Keep at least one copy in each group. Duplicate bytes are logical size, not guaranteed disk savings.",
        moved: "Moved to Trash",
        notMoved: "Not moved",
        skipped: "Skipped files",
        confirm: "Review files to move to Trash",
        trashNote: "These files remain in Trash until it is emptied. Restore them using Finder. Identical contents do not mean both locations are unnecessary.",
        hidden: "Hidden item",
        package: "Package contents",
        trashReason: "Trash folder",
        symbolicLink: "Symbolic link",
        alias: "Finder alias",
        hardLink: "Hard-linked file",
        cloud: "Not available locally",
        resourceFork: "Resource fork",
        inaccessible: "Cannot access",
        changed: "Changed or replaced; rescan",
        cancelledReason: "Cancelled",
        keepCopy: "Remaining copy could not be verified; rescan",
        failed: "Trash operation failed"
    )

    static let ptBR = DuplicateFinderStrings(
        title: "Localizador de arquivos duplicados",
        intro: "Escolha pastas para encontrar conteúdo idêntico, visualizar cópias e revisar cada remoção.",
        open: "Abrir localizador de duplicados",
        scope: "Verifica arquivos locais comuns e visíveis nas pastas selecionadas e subpastas. Ignora pacotes, links, arquivos somente na nuvem e bifurcações de recursos.",
        privacy: "Pastas, resultados e prévias ficam nesta sessão da janela. O conteúdo é lido localmente e nunca enviado.",
        add: "Adicionar pastas…",
        scan: "Verificar",
        cancel: "Cancelar",
        trash: "Mover selecionados para o Lixo",
        folders: "Pastas",
        remove: "Remover pasta",
        cancelled: "Verificação cancelada",
        noDuplicates: "Nenhum duplicado exato encontrado",
        preview: "Prévia",
        reveal: "Mostrar no Finder",
        choosePreview: "Selecione um arquivo para visualizar.",
        enumerating: "Descobrindo arquivos",
        comparing: "Comparando conteúdo",
        working: "Processando…",
        logicalSize: "Bytes duplicados selecionados",
        keepNote: "Mantenha pelo menos uma cópia em cada grupo. Os bytes representam tamanho lógico, não economia garantida de espaço.",
        moved: "Movidos para o Lixo",
        notMoved: "Não movidos",
        skipped: "Arquivos ignorados",
        confirm: "Revisar arquivos para mover ao Lixo",
        trashNote: "Os arquivos ficam no Lixo até ele ser esvaziado. Restaure-os pelo Finder. Conteúdo idêntico não significa que ambas as localizações sejam desnecessárias.",
        hidden: "Item oculto",
        package: "Conteúdo de pacote",
        trashReason: "Pasta do Lixo",
        symbolicLink: "Link simbólico",
        alias: "Alias do Finder",
        hardLink: "Arquivo com link físico",
        cloud: "Não disponível localmente",
        resourceFork: "Bifurcação de recursos",
        inaccessible: "Sem acesso",
        changed: "Alterado ou substituído; verifique novamente",
        cancelledReason: "Cancelado",
        keepCopy: "Não foi possível verificar a cópia restante; verifique novamente",
        failed: "Falha ao mover para o Lixo"
    )

    static let tr = DuplicateFinderStrings(
        title: "Yinelenen dosya bulucu",
        intro: "Aynı dosya içeriklerini bulmak, kopyaları önizlemek ve her kaldırmayı incelemek için klasör seçin.",
        open: "Yinelenen dosya bulucuyu aç",
        scope: "Seçilen klasörlerdeki ve alt klasörlerdeki görünür, normal yerel dosyaları tarar. Paketleri, bağlantıları, yalnızca buluttaki dosyaları ve kaynak çatallarını atlar.",
        privacy: "Klasörler, sonuçlar ve önizlemeler bu pencere oturumunda kalır. İçerik yerel olarak okunur ve yüklenmez.",
        add: "Klasör ekle…",
        scan: "Tara",
        cancel: "İptal",
        trash: "Seçilenleri Çöp Sepeti’ne taşı",
        folders: "Klasörler",
        remove: "Klasörü kaldır",
        cancelled: "Tarama iptal edildi",
        noDuplicates: "Tam olarak aynı dosya bulunamadı",
        preview: "Önizleme",
        reveal: "Finder’da göster",
        choosePreview: "Önizlemek için bir dosya seçin.",
        enumerating: "Dosyalar bulunuyor",
        comparing: "İçerikler karşılaştırılıyor",
        working: "İşleniyor…",
        logicalSize: "Seçilen yinelenen baytlar",
        keepNote: "Her grupta en az bir kopya tutun. Baytlar mantıksal boyuttur; disk tasarrufu garantisi değildir.",
        moved: "Çöp Sepeti’ne taşındı",
        notMoved: "Taşınmadı",
        skipped: "Atlanan dosyalar",
        confirm: "Çöp Sepeti’ne taşınacak dosyaları inceleyin",
        trashNote: "Dosyalar boşaltılana kadar Çöp Sepeti’nde kalır. Finder ile geri yükleyin. Aynı içerik, her iki konumun da gereksiz olduğu anlamına gelmez.",
        hidden: "Gizli öğe",
        package: "Paket içeriği",
        trashReason: "Çöp Sepeti klasörü",
        symbolicLink: "Sembolik bağlantı",
        alias: "Finder takma adı",
        hardLink: "Sabit bağlantılı dosya",
        cloud: "Yerel olarak mevcut değil",
        resourceFork: "Kaynak çatalı",
        inaccessible: "Erişilemiyor",
        changed: "Değişti veya değiştirildi; yeniden tarayın",
        cancelledReason: "İptal edildi",
        keepCopy: "Kalan kopya doğrulanamadı; yeniden tarayın",
        failed: "Çöp Sepeti işlemi başarısız"
    )

    static let ru = DuplicateFinderStrings(
        title: "Поиск дубликатов файлов",
        intro: "Выберите папки, найдите файлы с одинаковым содержимым, просмотрите копии и проверьте каждое удаление.",
        open: "Открыть поиск дубликатов",
        scope: "Проверяются обычные видимые локальные файлы в выбранных папках и подпапках. Пропускаются пакеты, ссылки, облачные файлы без локальной копии и файлы с ресурсной вилкой.",
        privacy: "Папки, результаты и предпросмотр хранятся только в сеансе этого окна. Содержимое читается локально и никуда не отправляется.",
        add: "Добавить папки…",
        scan: "Сканировать",
        cancel: "Отмена",
        trash: "Переместить выбранное в Корзину",
        folders: "Папки",
        remove: "Убрать папку",
        cancelled: "Сканирование отменено",
        noDuplicates: "Точные дубликаты не найдены",
        preview: "Предпросмотр",
        reveal: "Показать в Finder",
        choosePreview: "Выберите файл для предпросмотра.",
        enumerating: "Поиск файлов",
        comparing: "Сравнение содержимого",
        working: "Обработка…",
        logicalSize: "Размер выбранных дубликатов",
        keepNote: "Оставьте хотя бы одну копию в каждой группе. Указан логический размер, а не гарантированная экономия места.",
        moved: "Перемещено в Корзину",
        notMoved: "Не перемещено",
        skipped: "Пропущенные файлы",
        confirm: "Проверьте файлы для перемещения в Корзину",
        trashNote: "Файлы остаются в Корзине до её очистки. Восстановить их можно через Finder. Одинаковое содержимое не означает, что обе копии не нужны в своих папках.",
        hidden: "Скрытый объект",
        package: "Содержимое пакета",
        trashReason: "Папка Корзины",
        symbolicLink: "Символическая ссылка",
        alias: "Псевдоним Finder",
        hardLink: "Файл с жёсткой ссылкой",
        cloud: "Нет локальной копии",
        resourceFork: "Ресурсная вилка",
        inaccessible: "Нет доступа",
        changed: "Изменён или заменён; повторите сканирование",
        cancelledReason: "Отменено",
        keepCopy: "Оставшуюся копию не удалось проверить; повторите сканирование",
        failed: "Не удалось переместить в Корзину"
    )

    static let es = DuplicateFinderStrings(
        title: "Buscador de archivos duplicados",
        intro: "Elige carpetas para encontrar contenidos idénticos, previsualizar copias y revisar cada eliminación.",
        open: "Abrir buscador de duplicados",
        scope: "Analiza archivos locales normales y visibles en las carpetas elegidas y sus subcarpetas. Omite paquetes, enlaces, archivos solo en la nube y bifurcaciones de recursos.",
        privacy: "Las carpetas, los resultados y las vistas previas permanecen en esta sesión. El contenido se lee localmente y nunca se sube.",
        add: "Añadir carpetas…",
        scan: "Analizar",
        cancel: "Cancelar",
        trash: "Mover seleccionados a la Papelera",
        folders: "Carpetas",
        remove: "Quitar carpeta",
        cancelled: "Análisis cancelado",
        noDuplicates: "No se encontraron duplicados exactos",
        preview: "Vista previa",
        reveal: "Mostrar en Finder",
        choosePreview: "Selecciona un archivo para previsualizarlo.",
        enumerating: "Buscando archivos",
        comparing: "Comparando contenido",
        working: "Procesando…",
        logicalSize: "Bytes duplicados seleccionados",
        keepNote: "Conserva al menos una copia en cada grupo. Los bytes indican tamaño lógico, no ahorro de disco garantizado.",
        moved: "Movidos a la Papelera",
        notMoved: "No movidos",
        skipped: "Archivos omitidos",
        confirm: "Revisar archivos para mover a la Papelera",
        trashNote: "Los archivos permanecen en la Papelera hasta vaciarla. Restáuralos con Finder. Un contenido idéntico no implica que ambas ubicaciones sean innecesarias.",
        hidden: "Elemento oculto",
        package: "Contenido de paquete",
        trashReason: "Carpeta de la Papelera",
        symbolicLink: "Enlace simbólico",
        alias: "Alias de Finder",
        hardLink: "Archivo con enlace físico",
        cloud: "No disponible localmente",
        resourceFork: "Bifurcación de recursos",
        inaccessible: "Sin acceso",
        changed: "Modificado o sustituido; vuelve a analizar",
        cancelledReason: "Cancelado",
        keepCopy: "No se pudo verificar la copia restante; vuelve a analizar",
        failed: "Error al mover a la Papelera"
    )

    static let sk = DuplicateFinderStrings(
        title: "Vyhľadávač duplicitných súborov",
        intro: "Vyberte priečinky, nájdite totožný obsah, prezrite si kópie a skontrolujte každé odstránenie.",
        open: "Otvoriť vyhľadávač duplicít",
        scope: "Prehľadáva bežné viditeľné lokálne súbory vo vybraných priečinkoch a podpriečinkoch. Preskakuje balíky, odkazy, iba cloudové súbory a zdrojové vetvy.",
        privacy: "Priečinky, výsledky a náhľady zostávajú v tejto relácii okna. Obsah sa číta lokálne a nikam sa nenahráva.",
        add: "Pridať priečinky…",
        scan: "Prehľadať",
        cancel: "Zrušiť",
        trash: "Presunúť vybrané do Koša",
        folders: "Priečinky",
        remove: "Odobrať priečinok",
        cancelled: "Prehľadávanie zrušené",
        noDuplicates: "Nenašli sa presné duplicity",
        preview: "Náhľad",
        reveal: "Zobraziť vo Finderi",
        choosePreview: "Vyberte súbor na zobrazenie náhľadu.",
        enumerating: "Vyhľadávanie súborov",
        comparing: "Porovnávanie obsahu",
        working: "Spracovanie…",
        logicalSize: "Vybrané duplicitné bajty",
        keepNote: "V každej skupine ponechajte aspoň jednu kópiu. Bajty označujú logickú veľkosť, nie zaručenú úsporu miesta.",
        moved: "Presunuté do Koša",
        notMoved: "Nepresunuté",
        skipped: "Preskočené súbory",
        confirm: "Skontrolovať súbory na presun do Koša",
        trashNote: "Súbory zostanú v Koši do jeho vyprázdnenia. Obnovte ich vo Finderi. Totožný obsah neznamená, že obe umiestnenia sú zbytočné.",
        hidden: "Skrytá položka",
        package: "Obsah balíka",
        trashReason: "Priečinok Koša",
        symbolicLink: "Symbolický odkaz",
        alias: "Alias Findera",
        hardLink: "Súbor s pevným odkazom",
        cloud: "Nedostupné lokálne",
        resourceFork: "Zdrojová vetva",
        inaccessible: "Nedostupné",
        changed: "Zmenené alebo nahradené; prehľadajte znova",
        cancelledReason: "Zrušené",
        keepCopy: "Zostávajúcu kópiu sa nepodarilo overiť; prehľadajte znova",
        failed: "Presun do Koša zlyhal"
    )

    static let de = DuplicateFinderStrings(
        title: "Duplikatdateien finden",
        intro: "Wähle Ordner, finde identische Dateiinhalte, sieh Kopien an und prüfe jede Entfernung.",
        open: "Duplikatsuche öffnen",
        scope: "Durchsucht normale sichtbare lokale Dateien in gewählten Ordnern und Unterordnern. Überspringt Pakete, Links, reine Cloud-Dateien und Ressourcenzweige.",
        privacy: "Ordner, Ergebnisse und Vorschauen bleiben in dieser Fenstersitzung. Inhalte werden lokal gelesen und nie hochgeladen.",
        add: "Ordner hinzufügen…",
        scan: "Scannen",
        cancel: "Abbrechen",
        trash: "Auswahl in den Papierkorb",
        folders: "Ordner",
        remove: "Ordner entfernen",
        cancelled: "Scan abgebrochen",
        noDuplicates: "Keine exakten Duplikate gefunden",
        preview: "Vorschau",
        reveal: "Im Finder zeigen",
        choosePreview: "Wähle eine Datei für die Vorschau.",
        enumerating: "Dateien suchen",
        comparing: "Inhalte vergleichen",
        working: "Verarbeitung…",
        logicalSize: "Ausgewählte Duplikatbytes",
        keepNote: "Behalte mindestens eine Kopie pro Gruppe. Die Bytes sind die logische Größe, keine garantierte Speicherersparnis.",
        moved: "Im Papierkorb",
        notMoved: "Nicht verschoben",
        skipped: "Übersprungene Dateien",
        confirm: "Dateien für den Papierkorb prüfen",
        trashNote: "Dateien bleiben bis zum Leeren im Papierkorb. Stelle sie im Finder wieder her. Identische Inhalte bedeuten nicht, dass beide Speicherorte unnötig sind.",
        hidden: "Verstecktes Objekt",
        package: "Paketinhalt",
        trashReason: "Papierkorbordner",
        symbolicLink: "Symbolischer Link",
        alias: "Finder-Alias",
        hardLink: "Datei mit Hardlink",
        cloud: "Nicht lokal verfügbar",
        resourceFork: "Ressourcenzweig",
        inaccessible: "Kein Zugriff",
        changed: "Geändert oder ersetzt; erneut scannen",
        cancelledReason: "Abgebrochen",
        keepCopy: "Verbleibende Kopie nicht verifiziert; erneut scannen",
        failed: "Verschieben in den Papierkorb fehlgeschlagen"
    )

    static let fr = DuplicateFinderStrings(
        title: "Recherche de fichiers en double",
        intro: "Choisissez des dossiers pour trouver des contenus identiques, prévisualiser les copies et examiner chaque suppression.",
        open: "Ouvrir la recherche de doublons",
        scope: "Analyse les fichiers locaux ordinaires et visibles des dossiers choisis et de leurs sous-dossiers. Ignore les paquets, liens, fichiers uniquement dans le cloud et fourches de ressources.",
        privacy: "Les dossiers, résultats et aperçus restent dans cette session. Le contenu est lu localement et jamais téléversé.",
        add: "Ajouter des dossiers…",
        scan: "Analyser",
        cancel: "Annuler",
        trash: "Placer la sélection dans la Corbeille",
        folders: "Dossiers",
        remove: "Retirer le dossier",
        cancelled: "Analyse annulée",
        noDuplicates: "Aucun doublon exact trouvé",
        preview: "Aperçu",
        reveal: "Afficher dans le Finder",
        choosePreview: "Sélectionnez un fichier à prévisualiser.",
        enumerating: "Recherche de fichiers",
        comparing: "Comparaison du contenu",
        working: "Traitement…",
        logicalSize: "Octets en double sélectionnés",
        keepNote: "Gardez au moins une copie par groupe. Les octets indiquent la taille logique, pas une économie d’espace garantie.",
        moved: "Placés dans la Corbeille",
        notMoved: "Non déplacés",
        skipped: "Fichiers ignorés",
        confirm: "Examiner les fichiers à placer dans la Corbeille",
        trashNote: "Les fichiers restent dans la Corbeille jusqu’à ce qu’elle soit vidée. Restaurez-les avec le Finder. Un contenu identique ne signifie pas que les deux emplacements sont inutiles.",
        hidden: "Élément masqué",
        package: "Contenu de paquet",
        trashReason: "Dossier de la Corbeille",
        symbolicLink: "Lien symbolique",
        alias: "Alias du Finder",
        hardLink: "Fichier avec lien physique",
        cloud: "Non disponible localement",
        resourceFork: "Fourche de ressources",
        inaccessible: "Accès impossible",
        changed: "Modifié ou remplacé ; relancez l’analyse",
        cancelledReason: "Annulé",
        keepCopy: "Copie restante non vérifiée ; relancez l’analyse",
        failed: "Échec du déplacement dans la Corbeille"
    )

    static let it = DuplicateFinderStrings(
        title: "Ricerca file duplicati",
        intro: "Scegli cartelle per trovare contenuti identici, vedere le copie e controllare ogni rimozione.",
        open: "Apri ricerca duplicati",
        scope: "Analizza file locali ordinari e visibili nelle cartelle scelte e nelle sottocartelle. Ignora pacchetti, collegamenti, file solo nel cloud e fork di risorse.",
        privacy: "Cartelle, risultati e anteprime restano in questa sessione. I contenuti vengono letti localmente e mai caricati.",
        add: "Aggiungi cartelle…",
        scan: "Analizza",
        cancel: "Annulla",
        trash: "Sposta selezionati nel Cestino",
        folders: "Cartelle",
        remove: "Rimuovi cartella",
        cancelled: "Analisi annullata",
        noDuplicates: "Nessun duplicato esatto trovato",
        preview: "Anteprima",
        reveal: "Mostra nel Finder",
        choosePreview: "Seleziona un file per l’anteprima.",
        enumerating: "Ricerca dei file",
        comparing: "Confronto dei contenuti",
        working: "Elaborazione…",
        logicalSize: "Byte duplicati selezionati",
        keepNote: "Conserva almeno una copia per gruppo. I byte indicano la dimensione logica, non un risparmio di spazio garantito.",
        moved: "Spostati nel Cestino",
        notMoved: "Non spostati",
        skipped: "File ignorati",
        confirm: "Controlla i file da spostare nel Cestino",
        trashNote: "I file restano nel Cestino finché non viene svuotato. Ripristinali dal Finder. Contenuti identici non significano che entrambe le posizioni siano superflue.",
        hidden: "Elemento nascosto",
        package: "Contenuto di pacchetto",
        trashReason: "Cartella del Cestino",
        symbolicLink: "Collegamento simbolico",
        alias: "Alias del Finder",
        hardLink: "File con collegamento fisico",
        cloud: "Non disponibile localmente",
        resourceFork: "Fork di risorse",
        inaccessible: "Accesso impossibile",
        changed: "Modificato o sostituito; ripeti l’analisi",
        cancelledReason: "Annullato",
        keepCopy: "Copia restante non verificata; ripeti l’analisi",
        failed: "Spostamento nel Cestino non riuscito"
    )

    static let ja = DuplicateFinderStrings(
        title: "重複ファイル検索",
        intro: "フォルダを選択し、同じ内容のファイルを検索して、コピーをプレビューし、移動前に確認します。",
        open: "重複ファイル検索を開く",
        scope: "選択したフォルダとサブフォルダ内の通常のローカルファイルを検索します。非表示項目、パッケージ、リンク、クラウドのみのファイル、リソースフォークは除外します。",
        privacy: "フォルダ、結果、プレビューはこのウインドウのセッション内だけに保持します。内容はローカルで読み取り、アップロードしません。",
        add: "フォルダを追加…",
        scan: "検索",
        cancel: "キャンセル",
        trash: "選択したファイルをゴミ箱へ",
        folders: "フォルダ",
        remove: "フォルダを除外",
        cancelled: "検索をキャンセルしました",
        noDuplicates: "完全に一致する重複はありません",
        preview: "プレビュー",
        reveal: "Finderで表示",
        choosePreview: "プレビューするファイルを選択してください。",
        enumerating: "ファイルを探索中",
        comparing: "内容を比較中",
        working: "処理中…",
        logicalSize: "選択した重複のバイト数",
        keepNote: "各グループに少なくとも1つのコピーを残してください。表示は論理サイズであり、空き容量の増加を保証しません。",
        moved: "ゴミ箱に移動済み",
        notMoved: "未移動",
        skipped: "除外したファイル",
        confirm: "ゴミ箱に移動するファイルを確認",
        trashNote: "ファイルはゴミ箱を空にするまで残ります。Finderで復元できます。内容が同じでも、両方の場所で必要な場合があります。",
        hidden: "非表示項目",
        package: "パッケージの内容",
        trashReason: "ゴミ箱フォルダ",
        symbolicLink: "シンボリックリンク",
        alias: "Finderのエイリアス",
        hardLink: "ハードリンクのあるファイル",
        cloud: "ローカルにありません",
        resourceFork: "リソースフォーク",
        inaccessible: "アクセスできません",
        changed: "変更または置換されました。再検索してください",
        cancelledReason: "キャンセル済み",
        keepCopy: "残すコピーを確認できません。再検索してください",
        failed: "ゴミ箱への移動に失敗しました"
    )

    static let ko = DuplicateFinderStrings(
        title: "중복 파일 찾기",
        intro: "폴더를 선택하여 동일한 파일 내용을 찾고, 사본을 미리 보고, 이동 전에 검토하세요.",
        open: "중복 파일 찾기 열기",
        scope: "선택한 폴더와 하위 폴더의 일반 로컬 파일을 검색합니다. 숨겨진 항목, 패키지, 링크, 클라우드 전용 파일 및 리소스 포크는 건너뜁니다.",
        privacy: "폴더, 결과 및 미리보기는 이 윈도우 세션에만 보관됩니다. 내용은 로컬에서 읽으며 업로드하지 않습니다.",
        add: "폴더 추가…",
        scan: "검색",
        cancel: "취소",
        trash: "선택한 파일을 휴지통으로 이동",
        folders: "폴더",
        remove: "폴더 제거",
        cancelled: "검색 취소됨",
        noDuplicates: "완전히 동일한 중복 파일 없음",
        preview: "미리보기",
        reveal: "Finder에서 보기",
        choosePreview: "미리 볼 파일을 선택하세요.",
        enumerating: "파일 검색 중",
        comparing: "내용 비교 중",
        working: "처리 중…",
        logicalSize: "선택한 중복 바이트",
        keepNote: "각 그룹에 사본을 하나 이상 남겨 두세요. 바이트는 논리적 크기이며 디스크 공간 절약을 보장하지 않습니다.",
        moved: "휴지통으로 이동됨",
        notMoved: "이동되지 않음",
        skipped: "건너뛴 파일",
        confirm: "휴지통으로 이동할 파일 검토",
        trashNote: "파일은 휴지통을 비울 때까지 남아 있습니다. Finder에서 복원하세요. 내용이 같아도 두 위치에서 모두 필요할 수 있습니다.",
        hidden: "숨겨진 항목",
        package: "패키지 내용",
        trashReason: "휴지통 폴더",
        symbolicLink: "심볼릭 링크",
        alias: "Finder 별칭",
        hardLink: "하드 링크 파일",
        cloud: "로컬에서 사용할 수 없음",
        resourceFork: "리소스 포크",
        inaccessible: "접근할 수 없음",
        changed: "변경되거나 교체됨; 다시 검색하세요",
        cancelledReason: "취소됨",
        keepCopy: "남은 사본을 확인할 수 없음; 다시 검색하세요",
        failed: "휴지통 이동 실패"
    )

    static let uk = DuplicateFinderStrings(
        title: "Пошук дублікатів файлів",
        intro: "Виберіть папки, знайдіть файли з однаковим вмістом, перегляньте копії та перевірте кожне видалення.",
        open: "Відкрити пошук дублікатів",
        scope: "Перевіряє звичайні видимі локальні файли у вибраних папках і підпапках. Пропускає пакети, посилання, хмарні файли без локальної копії та ресурсні вилки.",
        privacy: "Папки, результати й перегляд зберігаються лише в сеансі цього вікна. Вміст читається локально й нікуди не надсилається.",
        add: "Додати папки…",
        scan: "Сканувати",
        cancel: "Скасувати",
        trash: "Перемістити вибране до Смітника",
        folders: "Папки",
        remove: "Прибрати папку",
        cancelled: "Сканування скасовано",
        noDuplicates: "Точних дублікатів не знайдено",
        preview: "Перегляд",
        reveal: "Показати у Finder",
        choosePreview: "Виберіть файл для перегляду.",
        enumerating: "Пошук файлів",
        comparing: "Порівняння вмісту",
        working: "Обробка…",
        logicalSize: "Розмір вибраних дублікатів",
        keepNote: "Залиште принаймні одну копію в кожній групі. Вказано логічний розмір, а не гарантовану економію місця.",
        moved: "Переміщено до Смітника",
        notMoved: "Не переміщено",
        skipped: "Пропущені файли",
        confirm: "Перевірте файли для переміщення до Смітника",
        trashNote: "Файли залишаються у Смітнику до його очищення. Відновіть їх у Finder. Однаковий вміст не означає, що обидві копії не потрібні у своїх папках.",
        hidden: "Прихований об’єкт",
        package: "Вміст пакета",
        trashReason: "Папка Смітника",
        symbolicLink: "Символічне посилання",
        alias: "Псевдонім Finder",
        hardLink: "Файл із жорстким посиланням",
        cloud: "Немає локальної копії",
        resourceFork: "Ресурсна вилка",
        inaccessible: "Немає доступу",
        changed: "Змінено або замінено; повторіть сканування",
        cancelledReason: "Скасовано",
        keepCopy: "Решту копій не вдалося перевірити; повторіть сканування",
        failed: "Не вдалося перемістити до Смітника"
    )

    static let zhHans = DuplicateFinderStrings(
        title: "重复文件查找器",
        intro: "选择文件夹，查找内容完全相同的文件，预览副本并检查每次移除。",
        open: "打开重复文件查找器",
        scope: "扫描所选文件夹及子文件夹中的普通可见本地文件。跳过软件包、链接、仅在云端的文件和资源分支。",
        privacy: "文件夹、结果和预览仅保留在此窗口会话中。文件内容仅在本地读取，绝不上传。",
        add: "添加文件夹…",
        scan: "扫描",
        cancel: "取消",
        trash: "将所选文件移到废纸篓",
        folders: "文件夹",
        remove: "移除文件夹",
        cancelled: "扫描已取消",
        noDuplicates: "未发现完全相同的重复文件",
        preview: "预览",
        reveal: "在访达中显示",
        choosePreview: "选择要预览的文件。",
        enumerating: "正在查找文件",
        comparing: "正在比较内容",
        working: "正在处理…",
        logicalSize: "所选重复内容字节数",
        keepNote: "每组至少保留一个副本。字节数是逻辑大小，并非保证可节省的磁盘空间。",
        moved: "已移到废纸篓",
        notMoved: "未移动",
        skipped: "已跳过的文件",
        confirm: "检查要移到废纸篓的文件",
        trashNote: "文件会保留在废纸篓中，直到清空为止。可通过访达恢复。内容相同并不意味着两个位置的文件都不需要。",
        hidden: "隐藏项目",
        package: "软件包内容",
        trashReason: "废纸篓文件夹",
        symbolicLink: "符号链接",
        alias: "访达替身",
        hardLink: "硬链接文件",
        cloud: "本地不可用",
        resourceFork: "资源分支",
        inaccessible: "无法访问",
        changed: "已更改或替换；请重新扫描",
        cancelledReason: "已取消",
        keepCopy: "无法验证保留的副本；请重新扫描",
        failed: "移到废纸篓失败"
    )

    static let zhTW = DuplicateFinderStrings(
        title: "重複檔案尋找器",
        intro: "選擇檔案夾，尋找內容完全相同的檔案，預覽副本並檢查每次移除。",
        open: "開啟重複檔案尋找器",
        scope: "掃描所選檔案夾及子檔案夾中的一般可見本機檔案。略過套件、連結、僅在雲端的檔案和資源分支。",
        privacy: "檔案夾、結果和預覽僅保留在此視窗工作階段中。檔案內容僅在本機讀取，絕不上傳。",
        add: "加入檔案夾…",
        scan: "掃描",
        cancel: "取消",
        trash: "將所選檔案移到垃圾桶",
        folders: "檔案夾",
        remove: "移除檔案夾",
        cancelled: "已取消掃描",
        noDuplicates: "未找到完全相同的重複檔案",
        preview: "預覽",
        reveal: "在 Finder 中顯示",
        choosePreview: "選擇要預覽的檔案。",
        enumerating: "正在尋找檔案",
        comparing: "正在比較內容",
        working: "正在處理…",
        logicalSize: "所選重複內容位元組數",
        keepNote: "每組至少保留一個副本。位元組數為邏輯大小，並非保證可節省的磁碟空間。",
        moved: "已移到垃圾桶",
        notMoved: "未移動",
        skipped: "略過的檔案",
        confirm: "檢查要移到垃圾桶的檔案",
        trashNote: "檔案會保留在垃圾桶中，直到清空為止。可透過 Finder 還原。內容相同不代表兩個位置的檔案都不需要。",
        hidden: "隱藏項目",
        package: "套件內容",
        trashReason: "垃圾桶檔案夾",
        symbolicLink: "符號連結",
        alias: "Finder 替身",
        hardLink: "硬連結檔案",
        cloud: "本機無法使用",
        resourceFork: "資源分支",
        inaccessible: "無法存取",
        changed: "已更改或取代；請重新掃描",
        cancelledReason: "已取消",
        keepCopy: "無法驗證保留的副本；請重新掃描",
        failed: "移到垃圾桶失敗"
    )

    static let zhHK = DuplicateFinderStrings(
        title: "重複檔案尋找器",
        intro: "選擇資料夾，尋找內容完全相同的檔案，預覽副本並檢查每次移除。",
        open: "開啟重複檔案尋找器",
        scope: "掃描所選資料夾及子資料夾中的一般可見本機檔案。略過套件、連結、僅在雲端的檔案和資源分支。",
        privacy: "資料夾、結果和預覽只保留在此視窗階段中。檔案內容只在本機讀取，絕不上傳。",
        add: "加入資料夾…",
        scan: "掃描",
        cancel: "取消",
        trash: "將所選檔案移至垃圾桶",
        folders: "資料夾",
        remove: "移除資料夾",
        cancelled: "掃描已取消",
        noDuplicates: "找不到完全相同的重複檔案",
        preview: "預覽",
        reveal: "在 Finder 顯示",
        choosePreview: "選擇要預覽的檔案。",
        enumerating: "正在尋找檔案",
        comparing: "正在比較內容",
        working: "正在處理…",
        logicalSize: "所選重複內容位元組數",
        keepNote: "每組至少保留一個副本。位元組數是邏輯大小，並非保證可節省的磁碟空間。",
        moved: "已移至垃圾桶",
        notMoved: "未移動",
        skipped: "略過的檔案",
        confirm: "檢查要移至垃圾桶的檔案",
        trashNote: "檔案會保留在垃圾桶，直到清空為止。可透過 Finder 還原。內容相同不代表兩個位置的檔案都不需要。",
        hidden: "隱藏項目",
        package: "套件內容",
        trashReason: "垃圾桶資料夾",
        symbolicLink: "符號連結",
        alias: "Finder 替身",
        hardLink: "硬連結檔案",
        cloud: "本機無法使用",
        resourceFork: "資源分支",
        inaccessible: "無法存取",
        changed: "已更改或取代；請重新掃描",
        cancelledReason: "已取消",
        keepCopy: "無法驗證保留的副本；請重新掃描",
        failed: "移至垃圾桶失敗"
    )

}
