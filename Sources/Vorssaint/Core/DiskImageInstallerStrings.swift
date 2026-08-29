// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

struct DiskImageInstallerStrings {
    let title: String
    let hubDescription: String
    let promptTitle: String
    let promptBodyFormat: String
    let installButton: String
    let installedTitle: String
    let installedBodyFormat: String
    let installedKeepingMountBodyFormat: String
    let installedKeepingDownloadBodyFormat: String
    let failedTitle: String
    let failedBody: String
    let verificationFailedBody: String
    let alreadyInstalledBodyFormat: String
}

extension FeatureStrings {
    static func diskImageInstaller(_ language: AppLanguage) -> DiskImageInstallerStrings {
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

extension DiskImageInstallerStrings {
    static let enUS = DiskImageInstallerStrings(
        title: "Disk image installer",
        hubDescription: "Install the single app inside a disk image and clean up the download",
        promptTitle: "Install this app?",
        promptBodyFormat: "%@ will be copied to Applications. The disk image is then ejected and its download moved to Trash.",
        installButton: "Install",
        installedTitle: "App installed",
        installedBodyFormat: "%@ is ready in Applications. The disk image was ejected and its download moved to Trash.",
        installedKeepingMountBodyFormat: "%@ is installed, but the disk image could not be ejected. Its download was kept.",
        installedKeepingDownloadBodyFormat: "%@ is installed and the disk image was ejected, but its download could not be moved to Trash.",
        failedTitle: "Could not install",
        failedBody: "Nothing was changed. You can still drag the app to Applications.",
        verificationFailedBody: "This Mac could not verify the app, so nothing was installed.",
        alreadyInstalledBodyFormat: "%@ is already in Applications."
    )

    static let ptBR = DiskImageInstallerStrings(
        title: "Instalador de imagens de disco",
        hubDescription: "Instale o único app de uma imagem de disco e limpe o download",
        promptTitle: "Instalar este app?",
        promptBodyFormat: "%@ será copiado para Aplicativos. Depois, a imagem de disco será ejetada e o download irá para o Lixo.",
        installButton: "Instalar",
        installedTitle: "App instalado",
        installedBodyFormat: "%@ está pronto em Aplicativos. A imagem de disco foi ejetada e o download foi para o Lixo.",
        installedKeepingMountBodyFormat: "%@ foi instalado, mas não foi possível ejetar a imagem de disco. O download foi mantido.",
        installedKeepingDownloadBodyFormat: "%@ foi instalado e a imagem de disco foi ejetada, mas o download não pôde ir para o Lixo.",
        failedTitle: "Não foi possível instalar",
        failedBody: "Nada foi alterado. Você ainda pode arrastar o app para Aplicativos.",
        verificationFailedBody: "Este Mac não conseguiu verificar o app, então nada foi instalado.",
        alreadyInstalledBodyFormat: "%@ já está em Aplicativos."
    )

    static let tr = DiskImageInstallerStrings(
        title: "Disk görüntüsü yükleyicisi",
        hubDescription: "Disk görüntüsündeki tek uygulamayı yükle ve indirilen dosyayı temizle",
        promptTitle: "Bu uygulama yüklensin mi?",
        promptBodyFormat: "%@ Uygulamalar'a kopyalanacak. Ardından disk görüntüsü çıkarılacak ve indirilen dosya Çöp Sepeti'ne taşınacak.",
        installButton: "Yükle",
        installedTitle: "Uygulama yüklendi",
        installedBodyFormat: "%@ Uygulamalar'da hazır. Disk görüntüsü çıkarıldı ve indirilen dosya Çöp Sepeti'ne taşındı.",
        installedKeepingMountBodyFormat: "%@ yüklendi, ancak disk görüntüsü çıkarılamadı. İndirilen dosya tutuldu.",
        installedKeepingDownloadBodyFormat: "%@ yüklendi ve disk görüntüsü çıkarıldı, ancak indirilen dosya Çöp Sepeti'ne taşınamadı.",
        failedTitle: "Yüklenemedi",
        failedBody: "Hiçbir şey değiştirilmedi. Uygulamayı yine de Uygulamalar'a sürükleyebilirsiniz.",
        verificationFailedBody: "Bu Mac uygulamayı doğrulayamadığı için hiçbir şey yüklenmedi.",
        alreadyInstalledBodyFormat: "%@ zaten Uygulamalar'da."
    )

    static let ru = DiskImageInstallerStrings(
        title: "Установка из образа диска",
        hubDescription: "Установите единственное приложение из образа диска и удалите загрузку",
        promptTitle: "Установить это приложение?",
        promptBodyFormat: "%@ будет скопировано в папку «Программы». Затем образ диска будет извлечён, а загрузка перемещена в Корзину.",
        installButton: "Установить",
        installedTitle: "Приложение установлено",
        installedBodyFormat: "%@ готово в папке «Программы». Образ диска извлечён, а загрузка перемещена в Корзину.",
        installedKeepingMountBodyFormat: "%@ установлено, но образ диска не удалось извлечь. Загрузка сохранена.",
        installedKeepingDownloadBodyFormat: "%@ установлено и образ диска извлечён, но загрузку не удалось переместить в Корзину.",
        failedTitle: "Не удалось установить",
        failedBody: "Ничего не изменено. Приложение по-прежнему можно перетащить в папку «Программы».",
        verificationFailedBody: "Этот Mac не смог проверить приложение, поэтому оно не было установлено.",
        alreadyInstalledBodyFormat: "%@ уже находится в папке «Программы»."
    )

    static let es = DiskImageInstallerStrings(
        title: "Instalador de imágenes de disco",
        hubDescription: "Instala la única app de una imagen de disco y limpia la descarga",
        promptTitle: "¿Instalar esta app?",
        promptBodyFormat: "%@ se copiará en Aplicaciones. Después, se expulsará la imagen de disco y la descarga irá a la Papelera.",
        installButton: "Instalar",
        installedTitle: "App instalada",
        installedBodyFormat: "%@ está lista en Aplicaciones. La imagen de disco se expulsó y la descarga se movió a la Papelera.",
        installedKeepingMountBodyFormat: "%@ se instaló, pero no se pudo expulsar la imagen de disco. La descarga se conservó.",
        installedKeepingDownloadBodyFormat: "%@ se instaló y la imagen de disco se expulsó, pero la descarga no pudo moverse a la Papelera.",
        failedTitle: "No se pudo instalar",
        failedBody: "No se cambió nada. Todavía puedes arrastrar la app a Aplicaciones.",
        verificationFailedBody: "Este Mac no pudo verificar la app, así que no se instaló nada.",
        alreadyInstalledBodyFormat: "%@ ya está en Aplicaciones."
    )

    static let de = DiskImageInstallerStrings(
        title: "Disk-Image-Installer",
        hubDescription: "Installiere die einzige App in einem Disk-Image und räume den Download auf",
        promptTitle: "Diese App installieren?",
        promptBodyFormat: "%@ wird in Programme kopiert. Danach wird das Disk-Image ausgeworfen und der Download in den Papierkorb gelegt.",
        installButton: "Installieren",
        installedTitle: "App installiert",
        installedBodyFormat: "%@ ist in Programme bereit. Das Disk-Image wurde ausgeworfen und der Download in den Papierkorb gelegt.",
        installedKeepingMountBodyFormat: "%@ wurde installiert, aber das Disk-Image konnte nicht ausgeworfen werden. Der Download wurde behalten.",
        installedKeepingDownloadBodyFormat: "%@ wurde installiert und das Disk-Image ausgeworfen, aber der Download konnte nicht in den Papierkorb gelegt werden.",
        failedTitle: "Installation fehlgeschlagen",
        failedBody: "Es wurde nichts geändert. Du kannst die App weiterhin nach Programme ziehen.",
        verificationFailedBody: "Dieser Mac konnte die App nicht überprüfen, daher wurde nichts installiert.",
        alreadyInstalledBodyFormat: "%@ befindet sich bereits in Programme."
    )

    static let fr = DiskImageInstallerStrings(
        title: "Installation depuis une image disque",
        hubDescription: "Installez l'unique app d'une image disque et nettoyez le téléchargement",
        promptTitle: "Installer cette app ?",
        promptBodyFormat: "%@ sera copiée dans Applications. L'image disque sera ensuite éjectée et le téléchargement placé dans la Corbeille.",
        installButton: "Installer",
        installedTitle: "App installée",
        installedBodyFormat: "%@ est prête dans Applications. L'image disque a été éjectée et le téléchargement placé dans la Corbeille.",
        installedKeepingMountBodyFormat: "%@ est installée, mais l'image disque n'a pas pu être éjectée. Le téléchargement a été conservé.",
        installedKeepingDownloadBodyFormat: "%@ est installée et l'image disque a été éjectée, mais le téléchargement n'a pas pu être placé dans la Corbeille.",
        failedTitle: "Installation impossible",
        failedBody: "Rien n'a été modifié. Vous pouvez toujours faire glisser l'app vers Applications.",
        verificationFailedBody: "Ce Mac n'a pas pu vérifier l'app, donc rien n'a été installé.",
        alreadyInstalledBodyFormat: "%@ se trouve déjà dans Applications."
    )

    static let it = DiskImageInstallerStrings(
        title: "Installazione da immagine disco",
        hubDescription: "Installa l'unica app di un'immagine disco e ripulisci il download",
        promptTitle: "Installare questa app?",
        promptBodyFormat: "%@ verrà copiata in Applicazioni. Poi l'immagine disco verrà espulsa e il download spostato nel Cestino.",
        installButton: "Installa",
        installedTitle: "App installata",
        installedBodyFormat: "%@ è pronta in Applicazioni. L'immagine disco è stata espulsa e il download spostato nel Cestino.",
        installedKeepingMountBodyFormat: "%@ è stata installata, ma non è stato possibile espellere l'immagine disco. Il download è stato conservato.",
        installedKeepingDownloadBodyFormat: "%@ è stata installata e l'immagine disco espulsa, ma non è stato possibile spostare il download nel Cestino.",
        failedTitle: "Installazione non riuscita",
        failedBody: "Non è stato modificato nulla. Puoi ancora trascinare l'app in Applicazioni.",
        verificationFailedBody: "Questo Mac non ha potuto verificare l'app, quindi non è stato installato nulla.",
        alreadyInstalledBodyFormat: "%@ è già in Applicazioni."
    )

    static let ja = DiskImageInstallerStrings(
        title: "ディスクイメージからインストール",
        hubDescription: "ディスクイメージ内の1つのアプリをインストールし、ダウンロードを片付けます",
        promptTitle: "このアプリをインストールしますか？",
        promptBodyFormat: "%@をアプリケーションにコピーします。その後、ディスクイメージを取り出し、ダウンロードをゴミ箱に移動します。",
        installButton: "インストール",
        installedTitle: "アプリをインストールしました",
        installedBodyFormat: "%@をアプリケーションにインストールしました。ディスクイメージを取り出し、ダウンロードをゴミ箱に移動しました。",
        installedKeepingMountBodyFormat: "%@をインストールしましたが、ディスクイメージを取り出せませんでした。ダウンロードは残しています。",
        installedKeepingDownloadBodyFormat: "%@をインストールしてディスクイメージを取り出しましたが、ダウンロードをゴミ箱に移動できませんでした。",
        failedTitle: "インストールできませんでした",
        failedBody: "何も変更していません。アプリケーションへドラッグしてインストールできます。",
        verificationFailedBody: "このMacでアプリを確認できなかったため、インストールしませんでした。",
        alreadyInstalledBodyFormat: "%@はすでにアプリケーションにあります。"
    )

    static let ko = DiskImageInstallerStrings(
        title: "디스크 이미지 설치",
        hubDescription: "디스크 이미지 안의 단일 앱을 설치하고 다운로드를 정리합니다",
        promptTitle: "이 앱을 설치할까요?",
        promptBodyFormat: "%@을(를) 응용 프로그램에 복사합니다. 그런 다음 디스크 이미지를 추출하고 다운로드를 휴지통으로 이동합니다.",
        installButton: "설치",
        installedTitle: "앱 설치 완료",
        installedBodyFormat: "%@이(가) 응용 프로그램에 준비되었습니다. 디스크 이미지를 추출하고 다운로드를 휴지통으로 이동했습니다.",
        installedKeepingMountBodyFormat: "%@을(를) 설치했지만 디스크 이미지를 추출하지 못했습니다. 다운로드는 그대로 두었습니다.",
        installedKeepingDownloadBodyFormat: "%@을(를) 설치하고 디스크 이미지를 추출했지만 다운로드를 휴지통으로 이동하지 못했습니다.",
        failedTitle: "설치할 수 없음",
        failedBody: "아무것도 변경하지 않았습니다. 앱을 응용 프로그램으로 직접 드래그할 수 있습니다.",
        verificationFailedBody: "이 Mac에서 앱을 확인할 수 없어 설치하지 않았습니다.",
        alreadyInstalledBodyFormat: "%@은(는) 이미 응용 프로그램에 있습니다."
    )

    static let zhHans = DiskImageInstallerStrings(
        title: "磁盘映像安装器",
        hubDescription: "安装磁盘映像中的唯一 App，并清理下载文件",
        promptTitle: "安装此 App？",
        promptBodyFormat: "%@ 将拷贝到“应用程序”。随后会推出磁盘映像，并将下载文件移到废纸篓。",
        installButton: "安装",
        installedTitle: "App 已安装",
        installedBodyFormat: "%@ 已在“应用程序”中就绪。磁盘映像已推出，下载文件已移到废纸篓。",
        installedKeepingMountBodyFormat: "%@ 已安装，但无法推出磁盘映像。下载文件已保留。",
        installedKeepingDownloadBodyFormat: "%@ 已安装且磁盘映像已推出，但无法将下载文件移到废纸篓。",
        failedTitle: "无法安装",
        failedBody: "没有更改任何内容。你仍可将 App 拖到“应用程序”中。",
        verificationFailedBody: "这台 Mac 无法验证该 App，因此没有安装。",
        alreadyInstalledBodyFormat: "%@ 已在“应用程序”中。"
    )

    static let zhTW = DiskImageInstallerStrings(
        title: "磁碟映像檔安裝器",
        hubDescription: "安裝磁碟映像檔中的單一 App，並清理下載檔案",
        promptTitle: "要安裝此 App 嗎？",
        promptBodyFormat: "%@ 將複製到「應用程式」。接著會退出磁碟映像檔，並將下載檔案移到垃圾桶。",
        installButton: "安裝",
        installedTitle: "App 已安裝",
        installedBodyFormat: "%@ 已可在「應用程式」中使用。磁碟映像檔已退出，下載檔案已移到垃圾桶。",
        installedKeepingMountBodyFormat: "%@ 已安裝，但無法退出磁碟映像檔。下載檔案已保留。",
        installedKeepingDownloadBodyFormat: "%@ 已安裝且磁碟映像檔已退出，但無法將下載檔案移到垃圾桶。",
        failedTitle: "無法安裝",
        failedBody: "沒有變更任何內容。你仍可將 App 拖到「應用程式」。",
        verificationFailedBody: "這部 Mac 無法驗證此 App，因此沒有安裝。",
        alreadyInstalledBodyFormat: "%@ 已在「應用程式」中。"
    )

    static let zhHK = DiskImageInstallerStrings(
        title: "磁碟映像檔安裝器",
        hubDescription: "安裝磁碟映像檔中的單一 App，並清理下載檔案",
        promptTitle: "要安裝此 App 嗎？",
        promptBodyFormat: "%@ 將複製到「應用程式」。之後會退出磁碟映像檔，並將下載檔案移到垃圾桶。",
        installButton: "安裝",
        installedTitle: "App 已安裝",
        installedBodyFormat: "%@ 已可在「應用程式」中使用。磁碟映像檔已退出，下載檔案已移到垃圾桶。",
        installedKeepingMountBodyFormat: "%@ 已安裝，但無法退出磁碟映像檔。下載檔案已保留。",
        installedKeepingDownloadBodyFormat: "%@ 已安裝且磁碟映像檔已退出，但無法將下載檔案移到垃圾桶。",
        failedTitle: "無法安裝",
        failedBody: "沒有變更任何內容。你仍可將 App 拖到「應用程式」。",
        verificationFailedBody: "這部 Mac 無法驗證此 App，因此沒有安裝。",
        alreadyInstalledBodyFormat: "%@ 已在「應用程式」中。"
    )
}
