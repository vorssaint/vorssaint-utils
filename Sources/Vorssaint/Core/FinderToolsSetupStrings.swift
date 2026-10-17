// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

enum FinderCreationSetting: CaseIterable, Identifiable {
    case open, hideExtension, sound, uniqueNames
    var id: Self { self }
    var keyPath: WritableKeyPath<FinderCreationPreferences, Bool> {
        switch self {
        case .open: return \.openAfterCreation
        case .hideExtension: return \.hideExtension
        case .sound: return \.playSound
        case .uniqueNames: return \.uniqueNames
        }
    }
    func title(_ language: String) -> String {
        let labels: [String]
        switch language {
        case "pt-BR": labels = ["Abrir após criar", "Ocultar extensão dos novos arquivos", "Tocar som ao criar", "Numerar novos arquivos quando o nome já existir"]
        case "es": labels = ["Abrir tras crear", "Ocultar extensión de archivos nuevos", "Sonido al crear", "Numerar archivos nuevos si el nombre existe"]
        case "fr": labels = ["Ouvrir après création", "Masquer l’extension des nouveaux fichiers", "Son à la création", "Numéroter les nouveaux fichiers si le nom existe"]
        case "de": labels = ["Nach dem Erstellen öffnen", "Endung neuer Dateien ausblenden", "Ton beim Erstellen", "Neue Dateien bei Namenskonflikten nummerieren"]
        case "it": labels = ["Apri dopo la creazione", "Nascondi estensione dei nuovi file", "Suono alla creazione", "Numera i nuovi file se il nome esiste"]
        case "tr": labels = ["Oluşturunca aç", "Yeni dosyaların uzantısını gizle", "Oluştururken ses çal", "Ad zaten varsa yeni dosyaları numaralandır"]
        case "sk": labels = ["Otvoriť po vytvorení", "Skryť príponu nových súborov", "Zvuk pri vytvorení", "Číslovať nové súbory pri rovnakom názve"]
        case "ru": labels = ["Открыть после создания", "Скрыть расширение новых файлов", "Звук при создании", "Нумеровать новые файлы при совпадении имён"]
        case "uk": labels = ["Відкрити після створення", "Приховати розширення нових файлів", "Звук під час створення", "Нумерувати нові файли при збігу назв"]
        case "ja": labels = ["作成後に開く", "新規ファイルの拡張子を隠す", "作成時に音を鳴らす", "同名ファイルがある場合は番号を付ける"]
        case "ko": labels = ["생성 후 열기", "새 파일 확장자 숨기기", "생성 시 소리 재생", "같은 이름이 있으면 새 파일에 번호 추가"]
        case "zh-Hans": labels = ["创建后打开", "隐藏新文件扩展名", "创建时播放声音", "重名时为新文件添加编号"]
        case "zh-TW", "zh-HK": labels = ["製作後打開", "隱藏新檔案副檔名", "製作時播放聲音", "重名時為新檔案加入編號"]
        default: labels = ["Open after creation", "Hide new file extensions", "Play a sound on creation", "Number new files when the name already exists"]
        }
        return labels[Self.allCases.firstIndex(of: self)!]
    }
}

struct FinderToolsSetupStrings {
    let title: String
    let description: String
    let open: String
    let enabled: String
    let disabled: String
    let localBuild: String
    static func localized(_ language: String) -> Self {
        let text: [String]
        switch language {
        case "en-US": text = ["Finder extension", "Enable the extension in System Settings to show these actions in Finder.", "Open Extension Settings", "Extension enabled", "Extension disabled", "This local build uses the default Finder menu. Sharing custom menu settings with the extension requires Developer ID signing."]
        case "pt-BR": text = ["Extensão do Finder", "Ative a extensão nos Ajustes do Sistema para mostrar estas ações no Finder.", "Abrir ajustes de extensões", "Extensão ativada", "Extensão desativada", "Esta compilação local usa o menu padrão do Finder. Compartilhar a personalização do menu com a extensão exige assinatura Developer ID."]
        case "es": text = ["Extensión de Finder", "Activa la extensión en Ajustes del Sistema para mostrar estas acciones en Finder.", "Abrir ajustes de extensiones", "Extensión activada", "Extensión desactivada", "Esta compilación local usa el menú predeterminado de Finder. Compartir la personalización del menú con la extensión requiere firma Developer ID."]
        case "fr": text = ["Extension Finder", "Activez l’extension dans Réglages Système pour afficher ces actions dans le Finder.", "Ouvrir les réglages des extensions", "Extension activée", "Extension désactivée", "Cette compilation locale utilise le menu Finder par défaut. Partager les réglages personnalisés avec l’extension nécessite une signature Developer ID."]
        case "de": text = ["Finder-Erweiterung", "Aktivieren Sie die Erweiterung in den Systemeinstellungen, um diese Aktionen im Finder anzuzeigen.", "Erweiterungseinstellungen öffnen", "Erweiterung aktiviert", "Erweiterung deaktiviert", "Dieser lokale Build verwendet das Standardmenü. Benutzerdefinierte Einstellungen für die Finder-Erweiterung erfordern eine Developer-ID-Signatur."]
        case "it": text = ["Estensione Finder", "Attiva l’estensione in Impostazioni di Sistema per mostrare queste azioni nel Finder.", "Apri impostazioni estensioni", "Estensione attivata", "Estensione disattivata", "Questa build locale usa il menu Finder predefinito. Condividere le personalizzazioni con l’estensione richiede una firma Developer ID."]
        case "sk": text = ["Rozšírenie Findera", "Ak chcete zobraziť tieto akcie vo Finderi, povoľte rozšírenie v Systémových nastaveniach.", "Otvoriť nastavenia rozšírení", "Rozšírenie je povolené", "Rozšírenie je vypnuté", "Táto lokálna zostava používa predvolené menu. Zdieľanie vlastných nastavení s rozšírením vyžaduje podpis Developer ID."]
        case "tr": text = ["Finder Uzantısı", "Bu eylemleri Finder’da göstermek için Sistem Ayarları’nda uzantıyı etkinleştirin.", "Uzantı Ayarlarını Aç", "Uzantı etkin", "Uzantı kapalı", "Bu yerel derleme varsayılan Finder menüsünü kullanır. Özel menü ayarlarını uzantıyla paylaşmak için Developer ID imzası gerekir."]
        case "ru": text = ["Расширение Finder", "Включите расширение в Системных настройках, чтобы показать эти действия в Finder.", "Открыть настройки расширений", "Расширение включено", "Расширение выключено", "Эта локальная сборка использует стандартное меню Finder. Для передачи настроек меню расширению нужна подпись Developer ID."]
        case "uk": text = ["Розширення Finder", "Увімкніть розширення в Системних параметрах, щоб показати ці дії у Finder.", "Відкрити параметри розширень", "Розширення ввімкнено", "Розширення вимкнено", "Ця локальна збірка використовує типове меню Finder. Передавання власних параметрів меню розширенню потребує підпису Developer ID."]
        case "ja": text = ["Finder機能拡張", "Finderにこれらの操作を表示するには、システム設定で機能拡張を有効にしてください。", "機能拡張の設定を開く", "機能拡張は有効です", "機能拡張は無効です", "このローカルビルドはデフォルトのFinderメニューを使用します。カスタム設定を機能拡張と共有するにはDeveloper ID署名が必要です。"]
        case "ko": text = ["Finder 확장 프로그램", "Finder에 이 작업을 표시하려면 시스템 설정에서 확장 프로그램을 활성화하세요.", "확장 프로그램 설정 열기", "확장 프로그램 활성화됨", "확장 프로그램 비활성화됨", "이 로컬 빌드는 기본 Finder 메뉴를 사용합니다. 사용자 지정 메뉴 설정을 확장 프로그램과 공유하려면 Developer ID 서명이 필요합니다."]
        case "zh-Hans": text = ["访达扩展", "在系统设置中启用扩展，即可在访达中显示这些操作。", "打开扩展设置", "扩展已启用", "扩展已停用", "此本地构建使用默认访达菜单。与扩展共享自定义菜单设置需要 Developer ID 签名。"]
        case "zh-TW": text = ["Finder 延伸功能", "在系統設定中啟用延伸功能，即可在 Finder 中顯示這些操作。", "打開延伸功能設定", "延伸功能已啟用", "延伸功能已停用", "此本機組建使用預設 Finder 選單。與延伸功能共享自訂選單設定需要 Developer ID 簽章。"]
        case "zh-HK": text = ["Finder 延伸功能", "在系統設定中啟用延伸功能，即可在 Finder 中顯示這些操作。", "開啟延伸功能設定", "延伸功能已啟用", "延伸功能已停用", "此本機組建使用預設 Finder 選單。與延伸功能共享自訂選單設定需要 Developer ID 簽章。"]
        default: return localized("en-US")
        }
        return Self(title: text[0], description: text[1], open: text[2], enabled: text[3], disabled: text[4], localBuild: text[5])
    }
}
