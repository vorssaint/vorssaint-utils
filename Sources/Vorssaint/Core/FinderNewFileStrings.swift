// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// Shared by the app and the Finder extension; the latter cannot load L10n.
struct FinderNewFileStrings {
    let title: String
    let description: String
    let enable: String
    let manage: String
    let extensionName: String
    let extensionEnabled: String
    let extensionDisabled: String
    let extensionHelp: String
    let cancel: String
    let error: String
    let text: String
    let page: String

    static let supportedCodes = Set(table.keys)

    static func localized(_ code: String) -> Self {
        // The host publishes the exact AppLanguage.rawValue. Do not duplicate
        // AppLanguage.systemDefault's locale normalization in the extension.
        table[code] ?? table["en-US"]!
    }

    private static let table: [String: Self] = [
        "en-US": .init(
            title: "New File",
            description: "Create blank documents from Finder’s context menu. Existing files are never replaced.",
            enable: "Enable New File",
            manage: "Manage Finder extension",
            extensionName: "Finder extension",
            extensionEnabled: "Enabled",
            extensionDisabled: "Not enabled",
            extensionHelp: "Enable the Finder extension for this app in System Settings to show New File in Finder’s context menu.",
            cancel: "Cancel",
            error: "Could not create the file",
            text: "Text document",
            page: "Finder"
        ),
        "pt-BR": .init(
            title: "Novo arquivo",
            description: "Crie documentos em branco pelo menu de contexto do Finder. Os arquivos existentes nunca são substituídos.",
            enable: "Ativar Novo arquivo",
            manage: "Gerenciar extensão do Finder",
            extensionName: "Extensão do Finder",
            extensionEnabled: "Ativada",
            extensionDisabled: "Não ativada",
            extensionHelp: "Ative a extensão do Finder deste app nos Ajustes do Sistema para mostrar Novo arquivo no menu de contexto do Finder.",
            cancel: "Cancelar",
            error: "Não foi possível criar o arquivo",
            text: "Documento de texto",
            page: "Finder"
        ),
        "tr": .init(
            title: "Yeni dosya",
            description: "Finder bağlam menüsünden boş belgeler oluşturun. Mevcut dosyalar asla değiştirilmez.",
            enable: "Yeni dosyayı etkinleştir",
            manage: "Finder uzantısını yönet",
            extensionName: "Finder uzantısı",
            extensionEnabled: "Etkin",
            extensionDisabled: "Etkin değil",
            extensionHelp: "Finder bağlam menüsünde Yeni dosya seçeneğini görmek için Sistem Ayarları’nda bu uygulamanın Finder uzantısını etkinleştirin.",
            cancel: "Vazgeç",
            error: "Dosya oluşturulamadı",
            text: "Metin belgesi",
            page: "Finder"
        ),
        "ru": .init(
            title: "Новый файл",
            description: "Создавайте пустые документы из контекстного меню Finder. Существующие файлы не заменяются.",
            enable: "Включить создание файлов",
            manage: "Управление расширением Finder",
            extensionName: "Расширение Finder",
            extensionEnabled: "Включено",
            extensionDisabled: "Не включено",
            extensionHelp: "Включите расширение Finder этого приложения в Системных настройках, чтобы пункт «Новый файл» появился в контекстном меню Finder.",
            cancel: "Отмена",
            error: "Не удалось создать файл",
            text: "Текстовый документ",
            page: "Finder"
        ),
        "es": .init(
            title: "Nuevo archivo",
            description: "Crea documentos en blanco desde el menú contextual del Finder. Nunca se sustituyen archivos existentes.",
            enable: "Activar Nuevo archivo",
            manage: "Gestionar la extensión del Finder",
            extensionName: "Extensión del Finder",
            extensionEnabled: "Activada",
            extensionDisabled: "No activada",
            extensionHelp: "Activa la extensión del Finder de esta app en Ajustes del Sistema para mostrar Nuevo archivo en el menú contextual del Finder.",
            cancel: "Cancelar",
            error: "No se pudo crear el archivo",
            text: "Documento de texto",
            page: "Finder"
        ),
        "sk": .init(
            title: "Nový súbor",
            description: "Vytvárajte prázdne dokumenty z kontextovej ponuky Findera. Existujúce súbory sa nikdy nenahrádzajú.",
            enable: "Zapnúť vytváranie súborov",
            manage: "Spravovať rozšírenie Findera",
            extensionName: "Rozšírenie Findera",
            extensionEnabled: "Zapnuté",
            extensionDisabled: "Vypnuté",
            extensionHelp: "Zapnite rozšírenie Findera pre túto aplikáciu v Systémových nastaveniach, aby sa v kontextovej ponuke Findera zobrazila možnosť Nový súbor.",
            cancel: "Zrušiť",
            error: "Súbor sa nepodarilo vytvoriť",
            text: "Textový dokument",
            page: "Finder"
        ),
        "de": .init(
            title: "Neue Datei",
            description: "Erstelle leere Dokumente über das Finder-Kontextmenü. Vorhandene Dateien werden nie ersetzt.",
            enable: "Neue Datei aktivieren",
            manage: "Finder-Erweiterung verwalten",
            extensionName: "Finder-Erweiterung",
            extensionEnabled: "Aktiviert",
            extensionDisabled: "Nicht aktiviert",
            extensionHelp: "Aktiviere die Finder-Erweiterung dieser App in den Systemeinstellungen, damit Neue Datei im Finder-Kontextmenü erscheint.",
            cancel: "Abbrechen",
            error: "Datei konnte nicht erstellt werden",
            text: "Textdokument",
            page: "Finder"
        ),
        "fr": .init(
            title: "Nouveau fichier",
            description: "Créez des documents vierges depuis le menu contextuel du Finder. Les fichiers existants ne sont jamais remplacés.",
            enable: "Activer Nouveau fichier",
            manage: "Gérer l’extension Finder",
            extensionName: "Extension Finder",
            extensionEnabled: "Activée",
            extensionDisabled: "Non activée",
            extensionHelp: "Activez l’extension Finder de cette app dans Réglages Système pour afficher Nouveau fichier dans le menu contextuel du Finder.",
            cancel: "Annuler",
            error: "Impossible de créer le fichier",
            text: "Document texte",
            page: "Finder"
        ),
        "it": .init(
            title: "Nuovo file",
            description: "Crea documenti vuoti dal menu contestuale del Finder. I file esistenti non vengono mai sostituiti.",
            enable: "Attiva Nuovo file",
            manage: "Gestisci l’estensione Finder",
            extensionName: "Estensione Finder",
            extensionEnabled: "Attivata",
            extensionDisabled: "Non attivata",
            extensionHelp: "Attiva l’estensione Finder di questa app in Impostazioni di Sistema per mostrare Nuovo file nel menu contestuale del Finder.",
            cancel: "Annulla",
            error: "Impossibile creare il file",
            text: "Documento di testo",
            page: "Finder"
        ),
        "ja": .init(
            title: "新規ファイル",
            description: "Finderのコンテキストメニューから空の書類を作成します。既存のファイルは上書きしません。",
            enable: "新規ファイルを有効にする",
            manage: "Finder拡張機能を管理",
            extensionName: "Finder拡張機能",
            extensionEnabled: "有効",
            extensionDisabled: "無効",
            extensionHelp: "Finderのコンテキストメニューに「新規ファイル」を表示するには、システム設定でこのアプリのFinder拡張機能を有効にしてください。",
            cancel: "キャンセル",
            error: "ファイルを作成できませんでした",
            text: "テキスト書類",
            page: "Finder"
        ),
        "ko": .init(
            title: "새로운 파일",
            description: "Finder 상황에 맞는 메뉴에서 빈 문서를 만듭니다. 기존 파일은 덮어쓰지 않습니다.",
            enable: "새로운 파일 활성화",
            manage: "Finder 확장 프로그램 관리",
            extensionName: "Finder 확장 프로그램",
            extensionEnabled: "활성화됨",
            extensionDisabled: "활성화되지 않음",
            extensionHelp: "Finder 상황에 맞는 메뉴에 새로운 파일을 표시하려면 시스템 설정에서 이 앱의 Finder 확장 프로그램을 활성화하세요.",
            cancel: "취소",
            error: "파일을 생성할 수 없음",
            text: "텍스트 문서",
            page: "Finder"
        ),
        "uk": .init(
            title: "Новий файл",
            description: "Створюйте порожні документи з контекстного меню Finder. Наявні файли ніколи не замінюються.",
            enable: "Увімкнути створення файлів",
            manage: "Керувати розширенням Finder",
            extensionName: "Розширення Finder",
            extensionEnabled: "Увімкнено",
            extensionDisabled: "Не ввімкнено",
            extensionHelp: "Увімкніть розширення Finder цієї програми в Системних параметрах, щоб пункт «Новий файл» з’явився в контекстному меню Finder.",
            cancel: "Скасувати",
            error: "Не вдалося створити файл",
            text: "Текстовий документ",
            page: "Finder"
        ),
        "zh-Hans": .init(
            title: "新建文件",
            description: "通过访达右键菜单创建空白文档，不会覆盖已有文件。",
            enable: "启用右键新建文件",
            manage: "管理访达扩展",
            extensionName: "访达扩展",
            extensionEnabled: "已启用",
            extensionDisabled: "未启用",
            extensionHelp: "请在系统设置中启用此应用的访达扩展，才能在访达右键菜单中使用新建文件。",
            cancel: "取消",
            error: "无法新建文件",
            text: "文本文档",
            page: "访达"
        ),
        "zh-TW": .init(
            title: "新增檔案",
            description: "透過 Finder 的右鍵選單建立空白文件，不會覆寫現有檔案。",
            enable: "啟用新增檔案",
            manage: "管理 Finder 延伸功能",
            extensionName: "Finder 延伸功能",
            extensionEnabled: "已啟用",
            extensionDisabled: "未啟用",
            extensionHelp: "請在系統設定中啟用此 App 的 Finder 延伸功能，才能在 Finder 的右鍵選單中使用新增檔案。",
            cancel: "取消",
            error: "無法建立檔案",
            text: "文字文件",
            page: "Finder"
        ),
        "zh-HK": .init(
            title: "新增檔案",
            description: "透過 Finder 的右鍵選單建立空白文件，不會覆寫現有檔案。",
            enable: "啟用新增檔案",
            manage: "管理 Finder 延伸功能",
            extensionName: "Finder 延伸功能",
            extensionEnabled: "已啟用",
            extensionDisabled: "未啟用",
            extensionHelp: "請在系統設定中啟用此 App 的 Finder 延伸功能，才能在 Finder 的右鍵選單中使用新增檔案。",
            cancel: "取消",
            error: "無法建立檔案",
            text: "文字文件",
            page: "Finder"
        ),
    ]
}
