// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// Strings for the settings backup (export and import on the Advanced page).
/// Same contract as the other FeatureStrings structs: memberwise init in
/// declaration order, one static per language, all in this file.
struct BackupFeatureStrings {
    let title: String
    let description: String
    let exportButton: String
    let importButton: String
    let exported: String
    let importConfirmTitle: String
    let importConfirmBody: String
    let importAction: String
    let invalidFile: String
}

extension FeatureStrings {
    static func backup(_ language: AppLanguage) -> BackupFeatureStrings {
        switch language {
        case .enUS: return .enUS
        case .ptBR: return .ptBR
        case .tr: return .tr
        case .ru: return .ru
        case .es: return .es
        case .de: return .de
        case .fr: return .fr
        case .it: return .it
        case .ja: return .ja
        case .ko: return .ko
        case .zhHans: return .zhHans
        case .zhTW: return .zhTW
        case .zhHK: return .zhHK
        }
    }
}

extension BackupFeatureStrings {
    static let ko = BackupFeatureStrings(
        title: "백업",
        description: "설정을 다른 Mac으로 옮기세요. 모든 환경설정을 파일로 내보낸 뒤 그곳에서 가져올 수 있습니다. 클립보드 기록, 선반 항목 및 시스템 권한은 이 Mac 밖으로 나가지 않습니다.",
        exportButton: "설정 내보내기…",
        importButton: "설정 가져오기…",
        exported: "백업을 저장했습니다",
        importConfirmTitle: "이 설정을 가져올까요?",
        importConfirmBody: "현재 설정이 파일의 설정으로 바뀌고 앱이 다시 시작됩니다. 이 Mac의 다른 항목은 변경되지 않습니다.",
        importAction: "가져오고 다시 시작",
        invalidFile: "이 파일은 유효한 Vorssaint 백업이 아닙니다."
    )
}

extension BackupFeatureStrings {
    static let enUS = BackupFeatureStrings(
        title: "Backup",
        description: "Take your setup to another Mac: export every preference to a file and import it there. Clipboard history, Shelf items and system permissions never leave this Mac.",
        exportButton: "Export settings…",
        importButton: "Import settings…",
        exported: "Backup saved",
        importConfirmTitle: "Import these settings?",
        importConfirmBody: "Your current settings are replaced by the file's and the app restarts. Nothing else on this Mac is touched.",
        importAction: "Import and restart",
        invalidFile: "This file is not a valid Vorssaint backup."
    )

    static let ptBR = BackupFeatureStrings(
        title: "Backup",
        description: "Leve sua configuração para outro Mac: exporte todas as preferências para um arquivo e importe lá. Histórico da área de transferência, itens da área temporária e permissões do sistema nunca saem deste Mac.",
        exportButton: "Exportar configurações…",
        importButton: "Importar configurações…",
        exported: "Backup salvo",
        importConfirmTitle: "Importar estas configurações?",
        importConfirmBody: "As configurações atuais são substituídas pelas do arquivo e o app reinicia. Nada mais neste Mac é alterado.",
        importAction: "Importar e reiniciar",
        invalidFile: "Este arquivo não é um backup válido do Vorssaint."
    )

    static let tr = BackupFeatureStrings(
        title: "Yedek",
        description: "Kurulumunuzu başka bir Mac'e taşıyın: tüm tercihleri bir dosyaya aktarın ve orada içe aktarın. Pano geçmişi, raf öğeleri ve sistem izinleri bu Mac'ten asla çıkmaz.",
        exportButton: "Ayarları dışa aktar…",
        importButton: "Ayarları içe aktar…",
        exported: "Yedek kaydedildi",
        importConfirmTitle: "Bu ayarlar içe aktarılsın mı?",
        importConfirmBody: "Mevcut ayarlar dosyadakilerle değiştirilir ve uygulama yeniden başlar. Bu Mac'te başka hiçbir şeye dokunulmaz.",
        importAction: "İçe aktar ve yeniden başlat",
        invalidFile: "Bu dosya geçerli bir Vorssaint yedeği değil."
    )

    static let ru = BackupFeatureStrings(
        title: "Резервная копия",
        description: "Перенесите настройки на другой Mac: экспортируйте все параметры в файл и импортируйте его там. История буфера обмена, объекты полки и системные разрешения никогда не покидают этот Mac.",
        exportButton: "Экспортировать настройки…",
        importButton: "Импортировать настройки…",
        exported: "Копия сохранена",
        importConfirmTitle: "Импортировать эти настройки?",
        importConfirmBody: "Текущие настройки заменяются настройками из файла, и приложение перезапускается. Больше ничего на этом Mac не меняется.",
        importAction: "Импортировать и перезапустить",
        invalidFile: "Этот файл не является корректной резервной копией Vorssaint."
    )

    static let es = BackupFeatureStrings(
        title: "Copia de seguridad",
        description: "Lleva tu configuración a otro Mac: exporta todas las preferencias a un archivo e impórtalo allí. El historial del portapapeles, los elementos del estante y los permisos del sistema nunca salen de este Mac.",
        exportButton: "Exportar ajustes…",
        importButton: "Importar ajustes…",
        exported: "Copia guardada",
        importConfirmTitle: "¿Importar estos ajustes?",
        importConfirmBody: "Los ajustes actuales se sustituyen por los del archivo y la app se reinicia. Nada más cambia en este Mac.",
        importAction: "Importar y reiniciar",
        invalidFile: "Este archivo no es una copia de seguridad válida de Vorssaint."
    )

    static let de = BackupFeatureStrings(
        title: "Backup",
        description: "Nimm deine Einrichtung mit auf einen anderen Mac: exportiere alle Einstellungen in eine Datei und importiere sie dort. Zwischenablage-Verlauf, Ablage-Objekte und Systemberechtigungen verlassen diesen Mac nie.",
        exportButton: "Einstellungen exportieren…",
        importButton: "Einstellungen importieren…",
        exported: "Backup gesichert",
        importConfirmTitle: "Diese Einstellungen importieren?",
        importConfirmBody: "Die aktuellen Einstellungen werden durch die der Datei ersetzt und die App startet neu. Sonst ändert sich auf diesem Mac nichts.",
        importAction: "Importieren und neu starten",
        invalidFile: "Diese Datei ist kein gültiges Vorssaint-Backup."
    )

    static let fr = BackupFeatureStrings(
        title: "Sauvegarde",
        description: "Emportez votre configuration sur un autre Mac : exportez toutes les préférences dans un fichier et importez-le là-bas. L'historique du presse-papiers, les éléments de l'étagère et les autorisations système ne quittent jamais ce Mac.",
        exportButton: "Exporter les réglages…",
        importButton: "Importer les réglages…",
        exported: "Sauvegarde enregistrée",
        importConfirmTitle: "Importer ces réglages ?",
        importConfirmBody: "Les réglages actuels sont remplacés par ceux du fichier et l'app redémarre. Rien d'autre ne change sur ce Mac.",
        importAction: "Importer et redémarrer",
        invalidFile: "Ce fichier n'est pas une sauvegarde Vorssaint valide."
    )

    static let it = BackupFeatureStrings(
        title: "Backup",
        description: "Porta la tua configurazione su un altro Mac: esporta tutte le preferenze in un file e importalo lì. Cronologia degli appunti, elementi della mensola e permessi di sistema non lasciano mai questo Mac.",
        exportButton: "Esporta impostazioni…",
        importButton: "Importa impostazioni…",
        exported: "Backup salvato",
        importConfirmTitle: "Importare queste impostazioni?",
        importConfirmBody: "Le impostazioni attuali vengono sostituite da quelle del file e l'app si riavvia. Nient'altro cambia su questo Mac.",
        importAction: "Importa e riavvia",
        invalidFile: "Questo file non è un backup Vorssaint valido."
    )

    static let ja = BackupFeatureStrings(
        title: "バックアップ",
        description: "設定を別のMacへ。すべての環境設定をファイルに書き出し、そちらで読み込みます。クリップボード履歴、シェルフの項目、システム権限がこのMacの外に出ることはありません。",
        exportButton: "設定を書き出す…",
        importButton: "設定を読み込む…",
        exported: "バックアップを保存しました",
        importConfirmTitle: "この設定を読み込みますか?",
        importConfirmBody: "現在の設定はファイルの内容に置き換えられ、アプリが再起動します。このMacのほかの部分は変わりません。",
        importAction: "読み込んで再起動",
        invalidFile: "このファイルは有効なVorssaintのバックアップではありません。"
    )

    static let zhHans = BackupFeatureStrings(
        title: "备份",
        description: "把你的配置带到另一台 Mac:将所有偏好设置导出为文件并在那里导入。剪贴板历史、暂存架项目和系统权限永远不会离开这台 Mac。",
        exportButton: "导出设置…",
        importButton: "导入设置…",
        exported: "备份已保存",
        importConfirmTitle: "导入这些设置?",
        importConfirmBody: "当前设置将被文件中的设置替换,应用会重启。这台 Mac 上的其他内容不受影响。",
        importAction: "导入并重启",
        invalidFile: "该文件不是有效的 Vorssaint 备份。"
    )

    static let zhTW = BackupFeatureStrings(
        title: "備份",
        description: "把你的設定帶到另一台 Mac:將所有偏好設定匯出為檔案並在那裡匯入。剪貼板歷史、暫存架項目和系統權限永遠不會離開這台 Mac。",
        exportButton: "匯出設定…",
        importButton: "匯入設定…",
        exported: "備份已儲存",
        importConfirmTitle: "匯入這些設定?",
        importConfirmBody: "目前設定將被檔案中的設定取代,App 會重新啟動。這台 Mac 上的其他內容不受影響。",
        importAction: "匯入並重新啟動",
        invalidFile: "此檔案不是有效的 Vorssaint 備份。"
    )

    static let zhHK = BackupFeatureStrings(
        title: "備份",
        description: "把你的設定帶到另一台 Mac:將所有偏好設定匯出為檔案並在那裡匯入。剪貼板歷史、暫存架項目和系統權限永遠不會離開這台 Mac。",
        exportButton: "匯出設定…",
        importButton: "匯入設定…",
        exported: "備份已儲存",
        importConfirmTitle: "匯入這些設定?",
        importConfirmBody: "目前設定將被檔案中的設定取代,App 會重新啟動。這台 Mac 上的其他內容不受影響。",
        importAction: "匯入並重新啟動",
        invalidFile: "此檔案不是有效嘅 Vorssaint 備份。"
    )
}
