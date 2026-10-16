// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

struct FinderLANShareStrings {
    let title: String
    let description: String
    let start: String
    let stop: String
    let stopped: String

    static func localized(_ language: String) -> Self {
        let text: [String]
        switch language {
        case "en-US": text = ["Share on Local Network", "Anyone with this link on your local network can download the selected files for 10 minutes. Transfers are not encrypted.", "Start Sharing", "Stop Sharing", "Sharing has stopped."]
        case "pt-BR": text = ["Compartilhar na rede local", "Qualquer pessoa com este link na sua rede local pode baixar os arquivos selecionados por 10 minutos. As transferências não são criptografadas.", "Iniciar compartilhamento", "Parar compartilhamento", "O compartilhamento foi encerrado."]
        case "es": text = ["Compartir en la red local", "Cualquier persona con este enlace en tu red local puede descargar los archivos seleccionados durante 10 minutos. Las transferencias no están cifradas.", "Iniciar uso compartido", "Detener uso compartido", "El uso compartido ha terminado."]
        case "fr": text = ["Partager sur le réseau local", "Toute personne disposant de ce lien sur votre réseau local peut télécharger les fichiers sélectionnés pendant 10 minutes. Les transferts ne sont pas chiffrés.", "Démarrer le partage", "Arrêter le partage", "Le partage est terminé."]
        case "de": text = ["Im lokalen Netzwerk teilen", "Jeder mit diesem Link in Ihrem lokalen Netzwerk kann die ausgewählten Dateien 10 Minuten lang herunterladen. Übertragungen sind unverschlüsselt.", "Teilen starten", "Teilen beenden", "Das Teilen wurde beendet."]
        case "it": text = ["Condividi sulla rete locale", "Chiunque abbia questo link nella tua rete locale può scaricare i file selezionati per 10 minuti. I trasferimenti non sono crittografati.", "Avvia condivisione", "Interrompi condivisione", "La condivisione è terminata."]
        case "sk": text = ["Zdieľať v lokálnej sieti", "Ktokoľvek s týmto odkazom vo vašej lokálnej sieti môže 10 minút sťahovať vybrané súbory. Prenosy nie sú šifrované.", "Začať zdieľanie", "Zastaviť zdieľanie", "Zdieľanie sa skončilo."]
        case "tr": text = ["Yerel Ağda Paylaş", "Yerel ağınızda bu bağlantıya sahip herkes seçili dosyaları 10 dakika boyunca indirebilir. Aktarımlar şifrelenmez.", "Paylaşımı Başlat", "Paylaşımı Durdur", "Paylaşım durduruldu."]
        case "ru": text = ["Поделиться в локальной сети", "Любой, у кого есть эта ссылка в вашей локальной сети, может скачивать выбранные файлы в течение 10 минут. Передача не шифруется.", "Начать общий доступ", "Остановить общий доступ", "Общий доступ остановлен."]
        case "uk": text = ["Поділитися в локальній мережі", "Будь-хто з цим посиланням у вашій локальній мережі може завантажувати вибрані файли протягом 10 хвилин. Передавання не шифрується.", "Почати спільний доступ", "Зупинити спільний доступ", "Спільний доступ зупинено."]
        case "ja": text = ["ローカルネットワークで共有", "ローカルネットワーク上でこのリンクを持つ人は、選択したファイルを10分間ダウンロードできます。転送は暗号化されません。", "共有を開始", "共有を停止", "共有は終了しました。"]
        case "ko": text = ["로컬 네트워크에서 공유", "로컬 네트워크에서 이 링크를 가진 사람은 10분 동안 선택한 파일을 다운로드할 수 있습니다. 전송은 암호화되지 않습니다.", "공유 시작", "공유 중지", "공유가 종료되었습니다."]
        case "zh-Hans": text = ["在局域网共享", "局域网中拥有此链接的人可以在 10 分钟内下载所选文件。传输不加密。", "开始共享", "停止共享", "共享已停止。"]
        case "zh-TW": text = ["在區域網路分享", "區域網路中擁有此連結的人可以在 10 分鐘內下載所選檔案。傳輸不加密。", "開始分享", "停止分享", "分享已停止。"]
        case "zh-HK": text = ["在區域網絡分享", "區域網絡中擁有此連結的人可以在 10 分鐘內下載所選檔案。傳輸不加密。", "開始分享", "停止分享", "分享已停止。"]
        default: return localized("en-US")
        }
        return Self(title: text[0], description: text[1], start: text[2], stop: text[3], stopped: text[4])
    }
}
