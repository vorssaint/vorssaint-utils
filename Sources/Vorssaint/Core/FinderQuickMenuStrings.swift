// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

enum FinderQuickMenuStrings {
    static func title(_ language: String) -> String { values(language)[0] }
    static func description(_ language: String) -> String { values(language)[1] }
    private static func values(_ language: String) -> [String] {
        switch language {
        case "en-US": return ["Quick File Menu", "Open the configured menu at the pointer with a global shortcut. The current Finder selection is read only with existing Automation access. Otherwise, choose files in the workspace. Each action opens its controls before running."]
        case "pt-BR": return ["Menu rápido de arquivos", "Abra o menu configurado no cursor com um atalho global. A seleção atual do Finder só é lida com acesso de Automação já concedido. Caso contrário, escolha os arquivos no painel. Cada ação abre seus controles antes de executar."]
        case "es": return ["Menú rápido de archivos", "Abre el menú configurado en el cursor con un atajo global. La selección del Finder solo se lee con acceso de Automatización ya concedido. De lo contrario, elige los archivos en el panel. Cada acción muestra sus controles antes de ejecutarse."]
        case "fr": return ["Menu rapide de fichiers", "Ouvre le menu configuré au pointeur avec un raccourci global. La sélection du Finder est lue uniquement si l’accès Automatisation est déjà accordé. Sinon, choisissez les fichiers dans le panneau. Chaque action affiche ses commandes avant de s’exécuter."]
        case "de": return ["Datei-Schnellmenü", "Öffnet das konfigurierte Menü am Zeiger über einen globalen Kurzbefehl. Die Finder-Auswahl wird nur mit bereits erteiltem Automatisierungszugriff gelesen. Andernfalls wählen Sie Dateien im Fenster. Jede Aktion zeigt vor der Ausführung ihre Optionen."]
        case "it": return ["Menu rapido dei file", "Apre il menu configurato al puntatore con una scorciatoia globale. La selezione del Finder viene letta solo con accesso Automazione già concesso. Altrimenti scegli i file nel pannello. Ogni azione mostra i controlli prima di eseguirsi."]
        case "ja": return ["ファイルクイックメニュー", "グローバルショートカットでポインタ位置にメニューを開きます。Finderの選択項目はオートメーションが許可済みの場合のみ取得します。それ以外はパネルでファイルを選択します。各操作は実行前に設定を表示します。"]
        case "ko": return ["빠른 파일 메뉴", "전역 단축키로 포인터 위치에 설정된 메뉴를 엽니다. 자동화 접근이 이미 허용된 경우에만 Finder 선택 항목을 읽습니다. 그렇지 않으면 패널에서 파일을 선택하세요. 각 작업은 실행 전에 설정을 표시합니다."]
        case "zh-Hans": return ["文件快捷菜单", "通过全局快捷键在指针位置打开已配置的菜单。只有已获得自动化访问权限时才读取 Finder 当前选择，否则请在面板中选择文件。每项操作都会先显示设置，再执行。"]
        case "zh-TW": return ["檔案快捷選單", "透過全域快速鍵在指標位置打開已設定的選單。只有已取得自動化存取權限時才讀取 Finder 目前選取項目，否則請在面板中選擇檔案。每項操作都會先顯示設定，再執行。"]
        case "zh-HK": return ["檔案快捷選單", "透過全域快速鍵在指標位置開啟已設定的選單。只有已取得自動化存取權限時才讀取 Finder 目前選取項目，否則請在面板中選擇檔案。每項操作都會先顯示設定，再執行。"]
        case "ru": return ["Быстрое меню файлов", "Открывает настроенное меню у указателя глобальной клавишей. Выбор Finder считывается только при уже разрешённой Автоматизации. Иначе выберите файлы в панели. Каждое действие сначала показывает свои настройки."]
        case "uk": return ["Швидке меню файлів", "Відкриває налаштоване меню біля вказівника глобальною клавішею. Вибір Finder зчитується лише за вже наданого доступу Автоматизації. Інакше виберіть файли на панелі. Кожна дія спершу показує свої налаштування."]
        case "tr": return ["Hızlı Dosya Menüsü", "Genel bir kısayolla yapılandırılmış menüyü imleçte açar. Finder seçimi yalnızca Otomasyon erişimi önceden verilmişse okunur. Aksi halde dosyaları panelden seçin. Her eylem çalışmadan önce denetimlerini açar."]
        case "sk": return ["Rýchla ponuka súborov", "Otvorí nastavenú ponuku pri ukazovateli globálnou skratkou. Výber Findera sa číta len s už udeleným prístupom Automatizácie. Inak vyberte súbory v paneli. Každá akcia pred spustením zobrazí svoje ovládanie."]
        default: return values("en-US")
        }
    }
}
