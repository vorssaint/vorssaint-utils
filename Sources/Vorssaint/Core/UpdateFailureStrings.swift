// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

struct UpdateFailureStrings {
    let title: String
    let currentVersionFormat: String
    let attemptedVersionFormat: String
    let retry: String
    let details: String
    let dismiss: String
    let downloadManually: String
    let copyDetails: String
    let verifyFailure: String
    let mountFailure: String
    let temporaryFailure: String
    let copyFailure: String
    let swapFailure: String
    let missingAppFailure: String
    let versionFailure: String
    let unknownFailure: String

    func explanation(for code: String) -> String {
        switch code {
        case "fail-dmg-verify", "fail-verify": return verifyFailure
        case "fail-mount": return mountFailure
        case "fail-tempdir": return temporaryFailure
        case "fail-copy": return copyFailure
        case "fail-swap": return swapFailure
        case "fail-no-app-in-dmg": return missingAppFailure
        case "fail-version": return versionFailure
        default: return unknownFailure
        }
    }
}

extension FeatureStrings {
    static func updateFailure(_ language: AppLanguage) -> UpdateFailureStrings {
        switch language {
        case .enUS: return UpdateFailureStrings(
            title: "Update couldn’t be installed",
            currentVersionFormat: "You’re using version %@.",
            attemptedVersionFormat: "Attempted update: %@",
            retry: "Try Again",
            details: "Details…",
            dismiss: "Dismiss",
            downloadManually: "Download Manually",
            copyDetails: "Copy Details",
            verifyFailure: "The update couldn’t be verified.",
            mountFailure: "The update’s disk image couldn’t be opened.",
            temporaryFailure: "Temporary installation files couldn’t be prepared.",
            copyFailure: "The new app couldn’t be copied. Trying again may request administrator approval.",
            swapFailure: "The installed app couldn’t be replaced. Trying again may request administrator approval.",
            missingAppFailure: "The download didn’t contain an app to install.",
            versionFailure: "The downloaded app’s version didn’t match the offered update.",
            unknownFailure: "The installation couldn’t be completed.")
        case .ptBR: return UpdateFailureStrings(
            title: "Não foi possível instalar a atualização",
            currentVersionFormat: "Você está usando a versão %@.",
            attemptedVersionFormat: "Atualização tentada: %@",
            retry: "Tentar novamente",
            details: "Detalhes…",
            dismiss: "Dispensar",
            downloadManually: "Baixar manualmente",
            copyDetails: "Copiar detalhes",
            verifyFailure: "Não foi possível verificar a atualização.",
            mountFailure: "Não foi possível abrir a imagem de disco da atualização.",
            temporaryFailure: "Não foi possível preparar os arquivos temporários de instalação.",
            copyFailure: "Não foi possível copiar o novo app. Uma nova tentativa pode solicitar autorização de administrador.",
            swapFailure: "Não foi possível substituir o app instalado. Uma nova tentativa pode solicitar autorização de administrador.",
            missingAppFailure: "O download não continha um app para instalar.",
            versionFailure: "A versão do app baixado não correspondia à atualização oferecida.",
            unknownFailure: "Não foi possível concluir a instalação.")
        case .es: return UpdateFailureStrings(
            title: "No se pudo instalar la actualización",
            currentVersionFormat: "Estás usando la versión %@.",
            attemptedVersionFormat: "Actualización intentada: %@",
            retry: "Reintentar",
            details: "Detalles…",
            dismiss: "Descartar",
            downloadManually: "Descargar manualmente",
            copyDetails: "Copiar detalles",
            verifyFailure: "No se pudo verificar la actualización.",
            mountFailure: "No se pudo abrir la imagen de disco de la actualización.",
            temporaryFailure: "No se pudieron preparar los archivos temporales de instalación.",
            copyFailure: "No se pudo copiar la nueva app. Al reintentar puede solicitarse autorización de administrador.",
            swapFailure: "No se pudo reemplazar la app instalada. Al reintentar puede solicitarse autorización de administrador.",
            missingAppFailure: "La descarga no contenía una app para instalar.",
            versionFailure: "La versión de la app descargada no coincidía con la actualización ofrecida.",
            unknownFailure: "No se pudo completar la instalación.")
        case .fr: return UpdateFailureStrings(
            title: "La mise à jour n’a pas pu être installée",
            currentVersionFormat: "Vous utilisez la version %@.",
            attemptedVersionFormat: "Mise à jour tentée : %@",
            retry: "Réessayer",
            details: "Détails…",
            dismiss: "Masquer",
            downloadManually: "Télécharger manuellement",
            copyDetails: "Copier les détails",
            verifyFailure: "La mise à jour n’a pas pu être vérifiée.",
            mountFailure: "L’image disque de la mise à jour n’a pas pu être ouverte.",
            temporaryFailure: "Les fichiers temporaires d’installation n’ont pas pu être préparés.",
            copyFailure: "La nouvelle app n’a pas pu être copiée. Un nouvel essai peut demander une autorisation d’administrateur.",
            swapFailure: "L’app installée n’a pas pu être remplacée. Un nouvel essai peut demander une autorisation d’administrateur.",
            missingAppFailure: "Le téléchargement ne contenait aucune app à installer.",
            versionFailure: "La version de l’app téléchargée ne correspondait pas à la mise à jour proposée.",
            unknownFailure: "L’installation n’a pas pu être terminée.")
        case .de: return UpdateFailureStrings(
            title: "Update konnte nicht installiert werden",
            currentVersionFormat: "Du verwendest Version %@.",
            attemptedVersionFormat: "Versuchtes Update: %@",
            retry: "Erneut versuchen",
            details: "Details…",
            dismiss: "Ausblenden",
            downloadManually: "Manuell laden",
            copyDetails: "Details kopieren",
            verifyFailure: "Das Update konnte nicht überprüft werden.",
            mountFailure: "Das Image des Updates konnte nicht geöffnet werden.",
            temporaryFailure: "Temporäre Installationsdateien konnten nicht vorbereitet werden.",
            copyFailure: "Die neue App konnte nicht kopiert werden. Ein erneuter Versuch erfordert möglicherweise eine Administratorfreigabe.",
            swapFailure: "Die installierte App konnte nicht ersetzt werden. Ein erneuter Versuch erfordert möglicherweise eine Administratorfreigabe.",
            missingAppFailure: "Der Download enthielt keine installierbare App.",
            versionFailure: "Die Version der geladenen App entsprach nicht dem angebotenen Update.",
            unknownFailure: "Die Installation konnte nicht abgeschlossen werden.")
        case .it: return UpdateFailureStrings(
            title: "Impossibile installare l’aggiornamento",
            currentVersionFormat: "Stai usando la versione %@.",
            attemptedVersionFormat: "Aggiornamento tentato: %@",
            retry: "Riprova",
            details: "Dettagli…",
            dismiss: "Nascondi",
            downloadManually: "Scarica manualmente",
            copyDetails: "Copia dettagli",
            verifyFailure: "Non è stato possibile verificare l’aggiornamento.",
            mountFailure: "Non è stato possibile aprire l’immagine disco dell’aggiornamento.",
            temporaryFailure: "Non è stato possibile preparare i file temporanei di installazione.",
            copyFailure: "Non è stato possibile copiare la nuova app. Un nuovo tentativo potrebbe richiedere l’autorizzazione di un amministratore.",
            swapFailure: "Non è stato possibile sostituire l’app installata. Un nuovo tentativo potrebbe richiedere l’autorizzazione di un amministratore.",
            missingAppFailure: "Il download non conteneva un’app da installare.",
            versionFailure: "La versione dell’app scaricata non corrispondeva all’aggiornamento proposto.",
            unknownFailure: "Non è stato possibile completare l’installazione.")
        case .sk: return UpdateFailureStrings(
            title: "Aktualizáciu sa nepodarilo nainštalovať",
            currentVersionFormat: "Používate verziu %@.",
            attemptedVersionFormat: "Pokus o aktualizáciu: %@",
            retry: "Skúsiť znova",
            details: "Podrobnosti…",
            dismiss: "Skryť",
            downloadManually: "Stiahnuť ručne",
            copyDetails: "Kopírovať podrobnosti",
            verifyFailure: "Aktualizáciu sa nepodarilo overiť.",
            mountFailure: "Obraz disku aktualizácie sa nepodarilo otvoriť.",
            temporaryFailure: "Dočasné inštalačné súbory sa nepodarilo pripraviť.",
            copyFailure: "Novú aplikáciu sa nepodarilo skopírovať. Ďalší pokus môže vyžadovať súhlas správcu.",
            swapFailure: "Nainštalovanú aplikáciu sa nepodarilo nahradiť. Ďalší pokus môže vyžadovať súhlas správcu.",
            missingAppFailure: "Stiahnutý súbor neobsahoval aplikáciu na inštaláciu.",
            versionFailure: "Verzia stiahnutej aplikácie nezodpovedala ponúkanej aktualizácii.",
            unknownFailure: "Inštaláciu sa nepodarilo dokončiť.")
        case .tr: return UpdateFailureStrings(
            title: "Güncelleme yüklenemedi",
            currentVersionFormat: "%@ sürümünü kullanıyorsunuz.",
            attemptedVersionFormat: "Denenen güncelleme: %@",
            retry: "Yeniden Dene",
            details: "Ayrıntılar…",
            dismiss: "Gizle",
            downloadManually: "Elle İndir",
            copyDetails: "Ayrıntıları Kopyala",
            verifyFailure: "Güncelleme doğrulanamadı.",
            mountFailure: "Güncellemenin disk görüntüsü açılamadı.",
            temporaryFailure: "Geçici yükleme dosyaları hazırlanamadı.",
            copyFailure: "Yeni uygulama kopyalanamadı. Yeniden denemek yönetici onayı gerektirebilir.",
            swapFailure: "Yüklü uygulama değiştirilemedi. Yeniden denemek yönetici onayı gerektirebilir.",
            missingAppFailure: "İndirme, yüklenecek bir uygulama içermiyordu.",
            versionFailure: "İndirilen uygulamanın sürümü sunulan güncellemeyle eşleşmedi.",
            unknownFailure: "Yükleme tamamlanamadı.")
        case .ru: return UpdateFailureStrings(
            title: "Не удалось установить обновление",
            currentVersionFormat: "Вы используете версию %@.",
            attemptedVersionFormat: "Попытка обновления до %@",
            retry: "Повторить",
            details: "Подробнее…",
            dismiss: "Скрыть",
            downloadManually: "Скачать вручную",
            copyDetails: "Скопировать сведения",
            verifyFailure: "Не удалось проверить обновление.",
            mountFailure: "Не удалось открыть образ диска обновления.",
            temporaryFailure: "Не удалось подготовить временные файлы установки.",
            copyFailure: "Не удалось скопировать новое приложение. Повторная попытка может потребовать разрешения администратора.",
            swapFailure: "Не удалось заменить установленное приложение. Повторная попытка может потребовать разрешения администратора.",
            missingAppFailure: "Загрузка не содержала приложения для установки.",
            versionFailure: "Версия загруженного приложения не совпала с предложенным обновлением.",
            unknownFailure: "Не удалось завершить установку.")
        case .uk: return UpdateFailureStrings(
            title: "Не вдалося встановити оновлення",
            currentVersionFormat: "Ви використовуєте версію %@.",
            attemptedVersionFormat: "Спроба оновлення до %@",
            retry: "Спробувати ще",
            details: "Докладніше…",
            dismiss: "Приховати",
            downloadManually: "Завантажити вручну",
            copyDetails: "Скопіювати відомості",
            verifyFailure: "Не вдалося перевірити оновлення.",
            mountFailure: "Не вдалося відкрити образ диска оновлення.",
            temporaryFailure: "Не вдалося підготувати тимчасові файли встановлення.",
            copyFailure: "Не вдалося скопіювати нову програму. Повторна спроба може вимагати дозволу адміністратора.",
            swapFailure: "Не вдалося замінити встановлену програму. Повторна спроба може вимагати дозволу адміністратора.",
            missingAppFailure: "Завантаження не містило програми для встановлення.",
            versionFailure: "Версія завантаженої програми не відповідала запропонованому оновленню.",
            unknownFailure: "Не вдалося завершити встановлення.")
        case .ja: return UpdateFailureStrings(
            title: "アップデートをインストールできませんでした",
            currentVersionFormat: "バージョン %@ を使用しています。",
            attemptedVersionFormat: "試行したアップデート：%@",
            retry: "再試行",
            details: "詳細…",
            dismiss: "非表示",
            downloadManually: "手動でダウンロード",
            copyDetails: "詳細をコピー",
            verifyFailure: "アップデートを検証できませんでした。",
            mountFailure: "アップデートのディスクイメージを開けませんでした。",
            temporaryFailure: "インストール用の一時ファイルを準備できませんでした。",
            copyFailure: "新しいアプリをコピーできませんでした。再試行時に管理者の承認が必要になる場合があります。",
            swapFailure: "インストール済みのアプリを置き換えられませんでした。再試行時に管理者の承認が必要になる場合があります。",
            missingAppFailure: "ダウンロードにインストール可能なアプリが含まれていませんでした。",
            versionFailure: "ダウンロードしたアプリのバージョンが提示されたアップデートと一致しませんでした。",
            unknownFailure: "インストールを完了できませんでした。")
        case .ko: return UpdateFailureStrings(
            title: "업데이트를 설치하지 못했습니다",
            currentVersionFormat: "버전 %@을(를) 사용 중입니다.",
            attemptedVersionFormat: "시도한 업데이트: %@",
            retry: "다시 시도",
            details: "세부사항…",
            dismiss: "숨기기",
            downloadManually: "수동 다운로드",
            copyDetails: "세부사항 복사",
            verifyFailure: "업데이트를 확인하지 못했습니다.",
            mountFailure: "업데이트의 디스크 이미지를 열지 못했습니다.",
            temporaryFailure: "임시 설치 파일을 준비하지 못했습니다.",
            copyFailure: "새로운 앱을 복사하지 못했습니다. 다시 시도하면 관리자 승인이 필요할 수 있습니다.",
            swapFailure: "설치된 앱을 교체하지 못했습니다. 다시 시도하면 관리자 승인이 필요할 수 있습니다.",
            missingAppFailure: "다운로드에 설치할 앱이 포함되어 있지 않았습니다.",
            versionFailure: "다운로드한 앱의 버전이 제공된 업데이트와 일치하지 않았습니다.",
            unknownFailure: "설치를 완료하지 못했습니다.")
        case .zhHans: return UpdateFailureStrings(
            title: "未能安装更新",
            currentVersionFormat: "你正在使用版本 %@。",
            attemptedVersionFormat: "尝试更新至：%@",
            retry: "重试",
            details: "详情…",
            dismiss: "忽略",
            downloadManually: "手动下载",
            copyDetails: "复制详情",
            verifyFailure: "未能验证更新。",
            mountFailure: "未能打开更新的磁盘映像。",
            temporaryFailure: "未能准备临时安装文件。",
            copyFailure: "未能复制新应用。重试时可能需要管理员授权。",
            swapFailure: "未能替换已安装的应用。重试时可能需要管理员授权。",
            missingAppFailure: "下载内容中没有可安装的应用。",
            versionFailure: "下载的应用版本与提供的更新不匹配。",
            unknownFailure: "未能完成安装。")
        case .zhTW: return UpdateFailureStrings(
            title: "無法安裝更新",
            currentVersionFormat: "你正在使用版本 %@。",
            attemptedVersionFormat: "嘗試更新至：%@",
            retry: "重試",
            details: "詳細資訊…",
            dismiss: "關閉提示",
            downloadManually: "手動下載",
            copyDetails: "拷貝詳細資訊",
            verifyFailure: "無法驗證更新。",
            mountFailure: "無法開啟更新的磁碟映像檔。",
            temporaryFailure: "無法準備暫存安裝檔案。",
            copyFailure: "無法拷貝新的 App。重試時可能需要管理者授權。",
            swapFailure: "無法取代已安裝的 App。重試時可能需要管理者授權。",
            missingAppFailure: "下載內容中沒有可安裝的 App。",
            versionFailure: "下載的 App 版本與提供的更新不符。",
            unknownFailure: "無法完成安裝。")
        case .zhHK: return UpdateFailureStrings(
            title: "無法安裝更新",
            currentVersionFormat: "你正在使用版本 %@。",
            attemptedVersionFormat: "嘗試更新至：%@",
            retry: "重試",
            details: "詳細資料…",
            dismiss: "關閉提示",
            downloadManually: "手動下載",
            copyDetails: "複製詳細資料",
            verifyFailure: "無法驗證更新。",
            mountFailure: "無法開啟更新的磁碟映像檔。",
            temporaryFailure: "無法準備暫存安裝檔案。",
            copyFailure: "無法複製新的 App。重試時可能需要管理員授權。",
            swapFailure: "無法取代已安裝的 App。重試時可能需要管理員授權。",
            missingAppFailure: "下載內容中沒有可安裝的 App。",
            versionFailure: "下載的 App 版本與提供的更新不符。",
            unknownFailure: "無法完成安裝。")
        }
    }
}
