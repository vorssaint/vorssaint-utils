// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

struct DiskImageInstallerStrings {
    let title: String
    let hubDescription: String
    let useUserApplications: String
    let applicationsFolder: String
    let userApplicationsFolder: String
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
    let trashDownloadOption: String
    let revealAppOption: String
    let installedKeptDownloadBodyFormat: String
    let installingFormat: String
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
        case .uk: return .uk
        }
    }
}

extension DiskImageInstallerStrings {
    static let enUS = DiskImageInstallerStrings(
        title: "Disk image installer",
        hubDescription: "Install the single app inside a disk image and clean up the download",
        useUserApplications: "Install in the Applications folder inside your home folder",
        applicationsFolder: "the Applications folder",
        userApplicationsFolder: "the Applications folder inside your home folder",
        promptTitle: "Install this app?",
        promptBodyFormat: "%@ will be copied to %@ and the disk image ejected.",
        installButton: "Install",
        installedTitle: "App installed",
        installedBodyFormat: "%@ is ready in %@. The disk image was ejected and its download moved to Trash.",
        installedKeepingMountBodyFormat: "%@ is installed in %@, but the disk image could not be ejected. Its download was kept.",
        installedKeepingDownloadBodyFormat: "%@ is installed in %@ and the disk image was ejected, but its download could not be moved to Trash.",
        failedTitle: "Could not install",
        failedBody: "Nothing was changed. You can still drag the app to Applications.",
        verificationFailedBody: "This Mac could not verify the app, so nothing was installed.",
        alreadyInstalledBodyFormat: "%@ is already in Applications.",
        trashDownloadOption: "Move the download to Trash",
        revealAppOption: "Show the installed app in Finder",
        installedKeptDownloadBodyFormat: "%@ is ready in %@. The disk image was ejected and its download kept.",
        installingFormat: "Installing %@…"
    )

    static let ptBR = DiskImageInstallerStrings(
        title: "Instalador de imagens de disco",
        hubDescription: "Instale o único app de uma imagem de disco e limpe o download",
        useUserApplications: "Instalar na pasta Aplicativos dentro da sua pasta pessoal",
        applicationsFolder: "pasta Aplicativos",
        userApplicationsFolder: "pasta Aplicativos dentro da sua pasta pessoal",
        promptTitle: "Instalar este app?",
        promptBodyFormat: "%@ será copiado para a %@ e a imagem de disco será ejetada.",
        installButton: "Instalar",
        installedTitle: "App instalado",
        installedBodyFormat: "%@ está pronto na %@. A imagem de disco foi ejetada e o download foi para o Lixo.",
        installedKeepingMountBodyFormat: "%@ foi instalado na %@, mas não foi possível ejetar a imagem de disco. O download foi mantido.",
        installedKeepingDownloadBodyFormat: "%@ foi instalado na %@ e a imagem de disco foi ejetada, mas o download não pôde ir para o Lixo.",
        failedTitle: "Não foi possível instalar",
        failedBody: "Nada foi alterado. Você ainda pode arrastar o app para Aplicativos.",
        verificationFailedBody: "Este Mac não conseguiu verificar o app, então nada foi instalado.",
        alreadyInstalledBodyFormat: "%@ já está em Aplicativos.",
        trashDownloadOption: "Mover o download para o Lixo",
        revealAppOption: "Mostrar o app instalado no Finder",
        installedKeptDownloadBodyFormat: "%@ está pronto na %@. A imagem de disco foi ejetada e o download foi mantido.",
        installingFormat: "Instalando %@…"
    )

    static let tr = DiskImageInstallerStrings(
        title: "Disk görüntüsü yükleyicisi",
        hubDescription: "Disk görüntüsündeki tek uygulamayı yükle ve indirilen dosyayı temizle",
        useUserApplications: "Ev klasörünüzdeki Uygulamalar klasörüne yükle",
        applicationsFolder: "Uygulamalar klasörü",
        userApplicationsFolder: "ev klasörünüzdeki Uygulamalar klasörü",
        promptTitle: "Bu uygulama yüklensin mi?",
        promptBodyFormat: "%@, %@ konumuna kopyalanacak ve disk görüntüsü çıkarılacak.",
        installButton: "Yükle",
        installedTitle: "Uygulama yüklendi",
        installedBodyFormat: "%@, %@ konumunda hazır. Disk görüntüsü çıkarıldı ve indirilen dosya Çöp Sepeti’ne taşındı.",
        installedKeepingMountBodyFormat: "%@, %@ konumuna yüklendi, ancak disk görüntüsü çıkarılamadı. İndirilen dosya tutuldu.",
        installedKeepingDownloadBodyFormat: "%@, %@ konumuna yüklendi ve disk görüntüsü çıkarıldı, ancak indirilen dosya Çöp Sepeti’ne taşınamadı.",
        failedTitle: "Yüklenemedi",
        failedBody: "Hiçbir şey değiştirilmedi. Uygulamayı yine de Uygulamalar’a sürükleyebilirsiniz.",
        verificationFailedBody: "Bu Mac uygulamayı doğrulayamadığı için hiçbir şey yüklenmedi.",
        alreadyInstalledBodyFormat: "%@ zaten Uygulamalar’da.",
        trashDownloadOption: "İndirilen dosyayı Çöp Sepeti’ne taşı",
        revealAppOption: "Yüklenen uygulamayı Finder’da göster",
        installedKeptDownloadBodyFormat: "%@, %@ konumunda hazır. Disk görüntüsü çıkarıldı ve indirilen dosya tutuldu.",
        installingFormat: "%@ yükleniyor…"
    )

    static let ru = DiskImageInstallerStrings(
        title: "Установка из образа диска",
        hubDescription: "Установите единственное приложение из образа диска и удалите загрузку",
        useUserApplications: "Установить в папку «Программы» внутри домашней папки",
        applicationsFolder: "папке «Программы»",
        userApplicationsFolder: "папке «Программы» внутри домашней папки",
        promptTitle: "Установить это приложение?",
        promptBodyFormat: "%@ будет установлено в %@, а образ диска извлечён.",
        installButton: "Установить",
        installedTitle: "Приложение установлено",
        installedBodyFormat: "%@ готово в %@. Образ диска извлечён, а загрузка перемещена в Корзину.",
        installedKeepingMountBodyFormat: "%@ установлено в %@, но образ диска не удалось извлечь. Загрузка сохранена.",
        installedKeepingDownloadBodyFormat: "%@ установлено в %@ и образ диска извлечён, но загрузку не удалось переместить в Корзину.",
        failedTitle: "Не удалось установить",
        failedBody: "Ничего не изменено. Приложение по-прежнему можно перетащить в папку «Программы».",
        verificationFailedBody: "Этот Mac не смог проверить приложение, поэтому оно не было установлено.",
        alreadyInstalledBodyFormat: "%@ уже находится в папке «Программы».",
        trashDownloadOption: "Переместить загрузку в Корзину",
        revealAppOption: "Показать установленное приложение в Finder",
        installedKeptDownloadBodyFormat: "%@ готово в %@. Образ диска извлечён, а загрузка сохранена.",
        installingFormat: "Установка %@…"
    )

    static let es = DiskImageInstallerStrings(
        title: "Instalador de imágenes de disco",
        hubDescription: "Instala la única app de una imagen de disco y limpia la descarga",
        useUserApplications: "Instalar en la carpeta Aplicaciones dentro de tu carpeta de inicio",
        applicationsFolder: "la carpeta Aplicaciones",
        userApplicationsFolder: "la carpeta Aplicaciones dentro de tu carpeta de inicio",
        promptTitle: "¿Instalar esta app?",
        promptBodyFormat: "%@ se copiará en %@ y se expulsará la imagen de disco.",
        installButton: "Instalar",
        installedTitle: "App instalada",
        installedBodyFormat: "%@ está lista en %@. La imagen de disco se expulsó y la descarga se movió a la Papelera.",
        installedKeepingMountBodyFormat: "%@ se instaló en %@, pero no se pudo expulsar la imagen de disco. La descarga se conservó.",
        installedKeepingDownloadBodyFormat: "%@ se instaló en %@ y se expulsó la imagen de disco, pero la descarga no pudo moverse a la Papelera.",
        failedTitle: "No se pudo instalar",
        failedBody: "No se cambió nada. Todavía puedes arrastrar la app a Aplicaciones.",
        verificationFailedBody: "Este Mac no pudo verificar la app, así que no se instaló nada.",
        alreadyInstalledBodyFormat: "%@ ya está en Aplicaciones.",
        trashDownloadOption: "Mover la descarga a la Papelera",
        revealAppOption: "Mostrar la app instalada en Finder",
        installedKeptDownloadBodyFormat: "%@ está lista en %@. La imagen de disco se expulsó y la descarga se conservó.",
        installingFormat: "Instalando %@…"
    )

    static let de = DiskImageInstallerStrings(
        title: "Disk-Image-Installer",
        hubDescription: "Installiere die einzige App in einem Disk-Image und räume den Download auf",
        useUserApplications: "Im Ordner Programme in deinem Benutzerordner installieren",
        applicationsFolder: "den Ordner Programme",
        userApplicationsFolder: "den Ordner Programme in deinem Benutzerordner",
        promptTitle: "Diese App installieren?",
        promptBodyFormat: "%@ wird in %@ kopiert und das Disk-Image ausgeworfen.",
        installButton: "Installieren",
        installedTitle: "App installiert",
        installedBodyFormat: "%@ wurde in %@ installiert. Das Disk-Image wurde ausgeworfen und der Download in den Papierkorb gelegt.",
        installedKeepingMountBodyFormat: "%@ wurde in %@ installiert, aber das Disk-Image konnte nicht ausgeworfen werden. Der Download wurde behalten.",
        installedKeepingDownloadBodyFormat: "%@ wurde in %@ installiert und das Disk-Image ausgeworfen, aber der Download konnte nicht in den Papierkorb gelegt werden.",
        failedTitle: "Installation fehlgeschlagen",
        failedBody: "Es wurde nichts geändert. Du kannst die App weiterhin nach Programme ziehen.",
        verificationFailedBody: "Dieser Mac konnte die App nicht überprüfen, daher wurde nichts installiert.",
        alreadyInstalledBodyFormat: "%@ befindet sich bereits in Programme.",
        trashDownloadOption: "Download in den Papierkorb legen",
        revealAppOption: "Installierte App im Finder anzeigen",
        installedKeptDownloadBodyFormat: "%@ wurde in %@ installiert. Das Disk-Image wurde ausgeworfen und der Download behalten.",
        installingFormat: "%@ wird installiert…"
    )

    static let fr = DiskImageInstallerStrings(
        title: "Installation depuis une image disque",
        hubDescription: "Installez l’unique app d’une image disque et nettoyez le téléchargement",
        useUserApplications: "Installer dans le dossier Applications de votre dossier personnel",
        applicationsFolder: "le dossier Applications",
        userApplicationsFolder: "le dossier Applications de votre dossier personnel",
        promptTitle: "Installer cette app\u{00A0}?",
        promptBodyFormat: "%@ sera copiée dans %@ et l’image disque éjectée.",
        installButton: "Installer",
        installedTitle: "App installée",
        installedBodyFormat: "%@ est prête dans %@. L’image disque a été éjectée et le téléchargement placé dans la Corbeille.",
        installedKeepingMountBodyFormat: "%@ est installée dans %@, mais l’image disque n’a pas pu être éjectée. Le téléchargement a été conservé.",
        installedKeepingDownloadBodyFormat: "%@ est installée dans %@ et l’image disque a été éjectée, mais le téléchargement n’a pas pu être placé dans la Corbeille.",
        failedTitle: "Installation impossible",
        failedBody: "Rien n’a été modifié. Vous pouvez toujours faire glisser l’app vers Applications.",
        verificationFailedBody: "Ce Mac n’a pas pu vérifier l’app, donc rien n’a été installé.",
        alreadyInstalledBodyFormat: "%@ se trouve déjà dans Applications.",
        trashDownloadOption: "Placer le téléchargement dans la Corbeille",
        revealAppOption: "Afficher l’app installée dans le Finder",
        installedKeptDownloadBodyFormat: "%@ est prête dans %@. L’image disque a été éjectée et le téléchargement conservé.",
        installingFormat: "Installation de %@…"
    )

    static let it = DiskImageInstallerStrings(
        title: "Installazione da immagine disco",
        hubDescription: "Installa l’unica app di un’immagine disco e ripulisci il download",
        useUserApplications: "Installa nella cartella Applicazioni dentro la tua cartella Inizio",
        applicationsFolder: "cartella Applicazioni",
        userApplicationsFolder: "cartella Applicazioni dentro la tua cartella Inizio",
        promptTitle: "Installare questa app?",
        promptBodyFormat: "%@ verrà copiata nella %@ e l’immagine disco espulsa.",
        installButton: "Installa",
        installedTitle: "App installata",
        installedBodyFormat: "%@ è pronta nella %@. L’immagine disco è stata espulsa e il download spostato nel Cestino.",
        installedKeepingMountBodyFormat: "%@ è stata installata nella %@, ma non è stato possibile espellere l’immagine disco. Il download è stato conservato.",
        installedKeepingDownloadBodyFormat: "%@ è stata installata nella %@ e l’immagine disco espulsa, ma non è stato possibile spostare il download nel Cestino.",
        failedTitle: "Installazione non riuscita",
        failedBody: "Non è stato modificato nulla. Puoi ancora trascinare l’app in Applicazioni.",
        verificationFailedBody: "Questo Mac non ha potuto verificare l’app, quindi non è stato installato nulla.",
        alreadyInstalledBodyFormat: "%@ è già in Applicazioni.",
        trashDownloadOption: "Sposta il download nel Cestino",
        revealAppOption: "Mostra l’app installata nel Finder",
        installedKeptDownloadBodyFormat: "%@ è pronta nella %@. L’immagine disco è stata espulsa e il download conservato.",
        installingFormat: "Installazione di %@…"
    )

    static let ja = DiskImageInstallerStrings(
        title: "ディスクイメージからインストール",
        hubDescription: "ディスクイメージ内の1つのアプリをインストールし、ダウンロードを片付けます",
        useUserApplications: "ホームフォルダ内のアプリケーションフォルダにインストール",
        applicationsFolder: "アプリケーションフォルダ",
        userApplicationsFolder: "ホームフォルダ内のアプリケーションフォルダ",
        promptTitle: "このアプリをインストールしますか？",
        promptBodyFormat: "%@を%@にコピーし、ディスクイメージを取り出します。",
        installButton: "インストール",
        installedTitle: "アプリをインストールしました",
        installedBodyFormat: "%@を%@にインストールしました。ディスクイメージを取り出し、ダウンロードをゴミ箱に移動しました。",
        installedKeepingMountBodyFormat: "%@を%@にインストールしましたが、ディスクイメージを取り出せませんでした。ダウンロードは残しています。",
        installedKeepingDownloadBodyFormat: "%@を%@にインストールしてディスクイメージを取り出しましたが、ダウンロードをゴミ箱に移動できませんでした。",
        failedTitle: "インストールできませんでした",
        failedBody: "何も変更していません。アプリケーションへドラッグしてインストールできます。",
        verificationFailedBody: "このMacでアプリを確認できなかったため、インストールしませんでした。",
        alreadyInstalledBodyFormat: "%@はすでにアプリケーションにあります。",
        trashDownloadOption: "ダウンロードをゴミ箱に移動",
        revealAppOption: "インストールしたアプリをFinderで表示",
        installedKeptDownloadBodyFormat: "%@を%@にインストールしました。ディスクイメージを取り出し、ダウンロードは残しています。",
        installingFormat: "%@をインストール中…"
    )

    static let ko = DiskImageInstallerStrings(
        title: "디스크 이미지 설치",
        hubDescription: "디스크 이미지 안의 단일 앱을 설치하고 다운로드를 정리합니다",
        useUserApplications: "홈 폴더 안의 응용 프로그램 폴더에 설치",
        applicationsFolder: "응용 프로그램 폴더",
        userApplicationsFolder: "홈 폴더 안의 응용 프로그램 폴더",
        promptTitle: "이 앱을 설치할까요?",
        promptBodyFormat: "%@을(를) %@에 복사하고 디스크 이미지를 추출합니다.",
        installButton: "설치",
        installedTitle: "앱 설치 완료",
        installedBodyFormat: "%@이(가) %@에 준비되었습니다. 디스크 이미지를 추출하고 다운로드를 휴지통으로 이동했습니다.",
        installedKeepingMountBodyFormat: "%@을(를) %@에 설치했지만 디스크 이미지를 추출하지 못했습니다. 다운로드는 그대로 두었습니다.",
        installedKeepingDownloadBodyFormat: "%@을(를) %@에 설치하고 디스크 이미지를 추출했지만 다운로드를 휴지통으로 이동하지 못했습니다.",
        failedTitle: "설치할 수 없음",
        failedBody: "아무것도 변경하지 않았습니다. 앱을 응용 프로그램으로 직접 드래그할 수 있습니다.",
        verificationFailedBody: "이 Mac에서 앱을 확인할 수 없어 설치하지 않았습니다.",
        alreadyInstalledBodyFormat: "%@은(는) 이미 응용 프로그램에 있습니다.",
        trashDownloadOption: "다운로드를 휴지통으로 이동",
        revealAppOption: "설치한 앱을 Finder에서 표시",
        installedKeptDownloadBodyFormat: "%@이(가) %@에 준비되었습니다. 디스크 이미지를 추출했고 다운로드는 그대로 두었습니다.",
        installingFormat: "%@ 설치 중…"
    )

    static let zhHans = DiskImageInstallerStrings(
        title: "磁盘映像安装器",
        hubDescription: "安装磁盘映像中的唯一 App，并清理下载文件",
        useUserApplications: "安装到个人文件夹内的“应用程序”文件夹",
        applicationsFolder: "“应用程序”文件夹",
        userApplicationsFolder: "个人文件夹内的“应用程序”文件夹",
        promptTitle: "安装此 App？",
        promptBodyFormat: "%@ 将拷贝到%@，随后会推出磁盘映像。",
        installButton: "安装",
        installedTitle: "App 已安装",
        installedBodyFormat: "%@ 已在%@中就绪。磁盘映像已推出，下载文件已移到废纸篓。",
        installedKeepingMountBodyFormat: "%@ 已安装到%@，但无法推出磁盘映像。下载文件已保留。",
        installedKeepingDownloadBodyFormat: "%@ 已安装到%@且磁盘映像已推出，但无法将下载文件移到废纸篓。",
        failedTitle: "无法安装",
        failedBody: "没有更改任何内容。你仍可将 App 拖到“应用程序”中。",
        verificationFailedBody: "这台 Mac 无法验证该 App，因此没有安装。",
        alreadyInstalledBodyFormat: "%@ 已在“应用程序”中。",
        trashDownloadOption: "将下载文件移到废纸篓",
        revealAppOption: "在访达中显示已安装的 App",
        installedKeptDownloadBodyFormat: "%@ 已在%@中就绪。磁盘映像已推出，下载文件已保留。",
        installingFormat: "正在安装 %@…"
    )

    static let zhTW = DiskImageInstallerStrings(
        title: "磁碟映像檔安裝器",
        hubDescription: "安裝磁碟映像檔中的單一 App，並清理下載檔案",
        useUserApplications: "安裝到個人檔案夾內的「應用程式」檔案夾",
        applicationsFolder: "「應用程式」檔案夾",
        userApplicationsFolder: "個人檔案夾內的「應用程式」檔案夾",
        promptTitle: "要安裝此 App 嗎？",
        promptBodyFormat: "%@ 將複製到%@，接著會退出磁碟映像檔。",
        installButton: "安裝",
        installedTitle: "App 已安裝",
        installedBodyFormat: "%@ 已可在%@中使用。磁碟映像檔已退出，下載檔案已移到垃圾桶。",
        installedKeepingMountBodyFormat: "%@ 已安裝到%@，但無法退出磁碟映像檔。下載檔案已保留。",
        installedKeepingDownloadBodyFormat: "%@ 已安裝到%@且磁碟映像檔已退出，但無法將下載檔案移到垃圾桶。",
        failedTitle: "無法安裝",
        failedBody: "沒有變更任何內容。你仍可將 App 拖到「應用程式」。",
        verificationFailedBody: "這部 Mac 無法驗證此 App，因此沒有安裝。",
        alreadyInstalledBodyFormat: "%@ 已在「應用程式」中。",
        trashDownloadOption: "將下載檔案移到垃圾桶",
        revealAppOption: "在 Finder 中顯示已安裝的 App",
        installedKeptDownloadBodyFormat: "%@ 已可在%@中使用。磁碟映像檔已退出，下載檔案已保留。",
        installingFormat: "正在安裝 %@…"
    )

    static let zhHK = DiskImageInstallerStrings(
        title: "磁碟映像檔安裝器",
        hubDescription: "安裝磁碟映像檔中的單一 App，並清理下載檔案",
        useUserApplications: "安裝到個人資料夾內的「應用程式」資料夾",
        applicationsFolder: "「應用程式」資料夾",
        userApplicationsFolder: "個人資料夾內的「應用程式」資料夾",
        promptTitle: "要安裝此 App 嗎？",
        promptBodyFormat: "%@ 將複製到%@，之後會退出磁碟映像檔。",
        installButton: "安裝",
        installedTitle: "App 已安裝",
        installedBodyFormat: "%@ 已可在%@中使用。磁碟映像檔已退出，下載檔案已移到垃圾桶。",
        installedKeepingMountBodyFormat: "%@ 已安裝到%@，但無法退出磁碟映像檔。下載檔案已保留。",
        installedKeepingDownloadBodyFormat: "%@ 已安裝到%@且磁碟映像檔已退出，但無法將下載檔案移到垃圾桶。",
        failedTitle: "無法安裝",
        failedBody: "沒有變更任何內容。你仍可將 App 拖到「應用程式」。",
        verificationFailedBody: "這部 Mac 無法驗證此 App，因此沒有安裝。",
        alreadyInstalledBodyFormat: "%@ 已在「應用程式」中。",
        trashDownloadOption: "將下載檔案移到垃圾桶",
        revealAppOption: "在 Finder 中顯示已安裝的 App",
        installedKeptDownloadBodyFormat: "%@ 已可在%@中使用。磁碟映像檔已退出，下載檔案已保留。",
        installingFormat: "正在安裝 %@…"
    )
    static let uk = DiskImageInstallerStrings(
        title: "Інсталятор образів диска",
        hubDescription: "Встановлює окрему програму з образу диска та очищає завантаження",
        useUserApplications: "Встановити в папку «Програми» у вашій домашній папці",
        applicationsFolder: "папці «Програми»",
        userApplicationsFolder: "папці «Програми» у вашій домашній папці",
        promptTitle: "Встановити цю програму?",
        promptBodyFormat: "%@ буде скопійовано до %@, а образ диска вийнято.",
        installButton: "Встановити",
        installedTitle: "Програму встановлено",
        installedBodyFormat: "%@ готова у %@. Образ диска вийнято, а завантаження переміщено в Кошик.",
        installedKeepingMountBodyFormat: "%@ встановлено до %@, але образ диска не вдалося вийняти. Завантаження збережено.",
        installedKeepingDownloadBodyFormat: "%@ встановлено до %@, а образ диска вийнято, але завантаження не вдалося перемістити в Кошик.",
        failedTitle: "Не вдалося встановити",
        failedBody: "Нічого не змінено. Ви все ще можете перетягнути програму у «Програми».",
        verificationFailedBody: "Цей Mac не зміг перевірити програму, тому нічого не встановлено.",
        alreadyInstalledBodyFormat: "%@ вже у папці «Програми».",
        trashDownloadOption: "Перемістити завантаження в Кошик",
        revealAppOption: "Показати встановлену програму у Finder",
        installedKeptDownloadBodyFormat: "%@ готова у %@. Образ диска вийнято, а завантаження збережено.",
        installingFormat: "Встановлення %@…"
    )
}
