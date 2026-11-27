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

    private init(_ title: String, _ description: String, _ enable: String, _ manage: String,
                 _ cancel: String, _ error: String, _ text: String, _ page: String,
                 _ extensionName: String, _ extensionEnabled: String, _ extensionDisabled: String,
                 _ extensionHelp: String) {
        self.title = title; self.description = description; self.enable = enable; self.manage = manage
        self.cancel = cancel; self.error = error; self.text = text; self.page = page
        self.extensionName = extensionName; self.extensionEnabled = extensionEnabled
        self.extensionDisabled = extensionDisabled; self.extensionHelp = extensionHelp
    }

    static let supportedCodes = Set(table.keys)

    static func localized(_ code: String) -> Self {
        let normalized = code.replacingOccurrences(of: "_", with: "-")
        if let exact = table[normalized] { return exact }
        if normalized.hasPrefix("zh-HK") || normalized.hasPrefix("zh-Hant-HK") { return table["zh-HK"]! }
        if normalized.hasPrefix("zh-Hant") || normalized.hasPrefix("zh-TW") { return table["zh-TW"]! }
        if normalized.hasPrefix("zh") { return table["zh-Hans"]! }
        if normalized.hasPrefix("pt") { return table["pt-BR"]! }
        return table[String(normalized.split(separator: "-").first ?? "")] ?? table["en-US"]!
    }

    private static let table: [String: Self] = [
        "en-US": .init("New File", "Create blank documents from Finder’s context menu. Existing files are never replaced.", "Enable New File", "Manage Finder extension", "Cancel", "Could not create the file", "Text document", "Finder", "Finder extension", "Enabled", "Not enabled", "Enable the Finder extension for this app in System Settings to show New File in Finder’s context menu."),
        "pt-BR": .init("Novo arquivo", "Crie documentos em branco pelo menu de contexto do Finder. Os arquivos existentes nunca são substituídos.", "Ativar Novo arquivo", "Gerenciar extensão do Finder", "Cancelar", "Não foi possível criar o arquivo", "Documento de texto", "Finder", "Extensão do Finder", "Ativada", "Não ativada", "Ative a extensão do Finder deste app nos Ajustes do Sistema para mostrar Novo arquivo no menu de contexto do Finder."),
        "tr": .init("Yeni dosya", "Finder bağlam menüsünden boş belgeler oluşturun. Mevcut dosyalar asla değiştirilmez.", "Yeni dosyayı etkinleştir", "Finder uzantısını yönet", "Vazgeç", "Dosya oluşturulamadı", "Metin belgesi", "Finder", "Finder uzantısı", "Etkin", "Etkin değil", "Finder bağlam menüsünde Yeni dosya seçeneğini görmek için Sistem Ayarları’nda bu uygulamanın Finder uzantısını etkinleştirin."),
        "ru": .init("Новый файл", "Создавайте пустые документы из контекстного меню Finder. Существующие файлы не заменяются.", "Включить создание файлов", "Управление расширением Finder", "Отмена", "Не удалось создать файл", "Текстовый документ", "Finder", "Расширение Finder", "Включено", "Не включено", "Включите расширение Finder этого приложения в Системных настройках, чтобы пункт «Новый файл» появился в контекстном меню Finder."),
        "es": .init("Nuevo archivo", "Crea documentos en blanco desde el menú contextual del Finder. Nunca se sustituyen archivos existentes.", "Activar Nuevo archivo", "Gestionar la extensión del Finder", "Cancelar", "No se pudo crear el archivo", "Documento de texto", "Finder", "Extensión del Finder", "Activada", "No activada", "Activa la extensión del Finder de esta app en Ajustes del Sistema para mostrar Nuevo archivo en el menú contextual del Finder."),
        "sk": .init("Nový súbor", "Vytvárajte prázdne dokumenty z kontextovej ponuky Findera. Existujúce súbory sa nikdy nenahrádzajú.", "Zapnúť vytváranie súborov", "Spravovať rozšírenie Findera", "Zrušiť", "Súbor sa nepodarilo vytvoriť", "Textový dokument", "Finder", "Rozšírenie Findera", "Zapnuté", "Vypnuté", "Zapnite rozšírenie Findera pre túto aplikáciu v Systémových nastaveniach, aby sa v kontextovej ponuke Findera zobrazila možnosť Nový súbor."),
        "de": .init("Neue Datei", "Erstelle leere Dokumente über das Finder-Kontextmenü. Vorhandene Dateien werden nie ersetzt.", "Neue Datei aktivieren", "Finder-Erweiterung verwalten", "Abbrechen", "Datei konnte nicht erstellt werden", "Textdokument", "Finder", "Finder-Erweiterung", "Aktiviert", "Nicht aktiviert", "Aktiviere die Finder-Erweiterung dieser App in den Systemeinstellungen, damit Neue Datei im Finder-Kontextmenü erscheint."),
        "fr": .init("Nouveau fichier", "Créez des documents vierges depuis le menu contextuel du Finder. Les fichiers existants ne sont jamais remplacés.", "Activer Nouveau fichier", "Gérer l’extension Finder", "Annuler", "Impossible de créer le fichier", "Document texte", "Finder", "Extension Finder", "Activée", "Non activée", "Activez l’extension Finder de cette app dans Réglages Système pour afficher Nouveau fichier dans le menu contextuel du Finder."),
        "it": .init("Nuovo file", "Crea documenti vuoti dal menu contestuale del Finder. I file esistenti non vengono mai sostituiti.", "Attiva Nuovo file", "Gestisci l’estensione Finder", "Annulla", "Impossibile creare il file", "Documento di testo", "Finder", "Estensione Finder", "Attivata", "Non attivata", "Attiva l’estensione Finder di questa app in Impostazioni di Sistema per mostrare Nuovo file nel menu contestuale del Finder."),
        "ja": .init("新規ファイル", "Finderのコンテキストメニューから空の書類を作成します。既存のファイルは上書きしません。", "新規ファイルを有効にする", "Finder拡張機能を管理", "キャンセル", "ファイルを作成できませんでした", "テキスト書類", "Finder", "Finder拡張機能", "有効", "無効", "Finderのコンテキストメニューに「新規ファイル」を表示するには、システム設定でこのアプリのFinder拡張機能を有効にしてください。"),
        "ko": .init("새로운 파일", "Finder 상황에 맞는 메뉴에서 빈 문서를 만듭니다. 기존 파일은 덮어쓰지 않습니다.", "새로운 파일 활성화", "Finder 확장 프로그램 관리", "취소", "파일을 생성할 수 없음", "텍스트 문서", "Finder", "Finder 확장 프로그램", "활성화됨", "활성화되지 않음", "Finder 상황에 맞는 메뉴에 새로운 파일을 표시하려면 시스템 설정에서 이 앱의 Finder 확장 프로그램을 활성화하세요."),
        "uk": .init("Новий файл", "Створюйте порожні документи з контекстного меню Finder. Наявні файли ніколи не замінюються.", "Увімкнути створення файлів", "Керувати розширенням Finder", "Скасувати", "Не вдалося створити файл", "Текстовий документ", "Finder", "Розширення Finder", "Увімкнено", "Не ввімкнено", "Увімкніть розширення Finder цієї програми в Системних параметрах, щоб пункт «Новий файл» з’явився в контекстному меню Finder."),
        "zh-Hans": .init("新建文件", "通过访达右键菜单创建空白文档，不会覆盖已有文件。", "启用右键新建文件", "管理访达扩展", "取消", "无法新建文件", "文本文档", "访达", "访达扩展", "已启用", "未启用", "请在系统设置中启用此应用的访达扩展，才能在访达右键菜单中使用新建文件。"),
        "zh-TW": .init("新增檔案", "透過 Finder 的右鍵選單建立空白文件，不會覆寫現有檔案。", "啟用新增檔案", "管理 Finder 延伸功能", "取消", "無法建立檔案", "文字文件", "Finder", "Finder 延伸功能", "已啟用", "未啟用", "請在系統設定中啟用此 App 的 Finder 延伸功能，才能在 Finder 的右鍵選單中使用新增檔案。"),
        "zh-HK": .init("新增檔案", "透過 Finder 的右鍵選單建立空白文件，不會覆寫現有檔案。", "啟用新增檔案", "管理 Finder 延伸功能", "取消", "無法建立檔案", "文字文件", "Finder", "Finder 延伸功能", "已啟用", "未啟用", "請在系統設定中啟用此 App 的 Finder 延伸功能，才能在 Finder 的右鍵選單中使用新增檔案。"),
    ]
}
