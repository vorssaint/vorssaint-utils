// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

/// User-facing copy when an incoming file fails to finish saving
/// or cannot fit on the shelf after it was accepted.
struct ShelfPromiseDeliveryStrings {
    let failedTitle: String
    let failedBody: String
    let fullTitle: String
    let fullBody: String
    let okButton: String

    static func localized(_ language: AppLanguage) -> ShelfPromiseDeliveryStrings {
        switch language {
        case .enUS:
            return .init(
                failedTitle: "Couldn’t add attachment",
                failedBody: "The file never finished saving to the shelf.",
                fullTitle: "Shelf is full",
                fullBody: "The attachment finished saving but there is no room left on the shelf.",
                okButton: "OK")
        case .ptBR:
            return .init(
                failedTitle: "Não foi possível adicionar o anexo",
                failedBody: "O arquivo não terminou de ser salvo na prateleira.",
                fullTitle: "Prateleira cheia",
                fullBody: "O anexo terminou de ser salvo, mas não há espaço na prateleira.",
                okButton: "OK")
        case .tr:
            return .init(
                failedTitle: "Eklenemedi",
                failedBody: "Dosya rafa kaydedilirken tamamlanmadı.",
                fullTitle: "Raf dolu",
                fullBody: "Ek kaydedildi ancak rafta yer kalmadı.",
                okButton: "Tamam")
        case .ru:
            return .init(
                failedTitle: "Не удалось добавить вложение",
                failedBody: "Файл так и не закончил сохраняться на полку.",
                fullTitle: "Полка заполнена",
                fullBody: "Вложение сохранилось, но на полке больше нет места.",
                okButton: "OK")
        case .es:
            return .init(
                failedTitle: "No se pudo añadir el adjunto",
                failedBody: "El archivo no terminó de guardarse en la bandeja.",
                fullTitle: "Bandeja llena",
                fullBody: "El adjunto terminó de guardarse, pero no queda sitio en la bandeja.",
                okButton: "OK")
        case .de:
            return .init(
                failedTitle: "Anhang konnte nicht hinzugefügt werden",
                failedBody: "Die Datei wurde nicht vollständig im Ablagefach gespeichert.",
                fullTitle: "Ablagefach voll",
                fullBody: "Der Anhang wurde gespeichert, aber im Ablagefach ist kein Platz mehr.",
                okButton: "OK")
        case .fr:
            return .init(
                failedTitle: "Impossible d’ajouter la pièce jointe",
                failedBody: "Le fichier n’a pas fini d’être enregistré sur l’étagère.",
                fullTitle: "Étagère pleine",
                fullBody: "La pièce jointe a fini d’être enregistrée, mais il n’y a plus de place.",
                okButton: "OK")
        case .it:
            return .init(
                failedTitle: "Impossibile aggiungere l’allegato",
                failedBody: "Il file non ha finito di salvarsi sullo scaffale.",
                fullTitle: "Scaffale pieno",
                fullBody: "L’allegato si è salvato, ma sullo scaffale non c’è più spazio.",
                okButton: "OK")
        case .ja:
            return .init(
                failedTitle: "添付ファイルを追加できませんでした",
                failedBody: "ファイルのシェルフへの保存が完了しませんでした。",
                fullTitle: "シェルフがいっぱいです",
                fullBody: "保存は完了しましたが、シェルフに空きがありません。",
                okButton: "OK")
        case .ko:
            return .init(
                failedTitle: "첨부 파일을 추가할 수 없음",
                failedBody: "파일이 선반에 완전히 저장되지 않았습니다.",
                fullTitle: "선반이 가득 참",
                fullBody: "첨부가 저장되었지만 선반에 남은 공간이 없습니다.",
                okButton: "확인")
        case .zhHans:
            return .init(
                failedTitle: "无法添加附件",
                failedBody: "文件未能完成保存到临时搁板。",
                fullTitle: "临时搁板已满",
                fullBody: "附件已保存，但临时搁板已没有空间。",
                okButton: "好")
        case .zhTW, .zhHK:
            return .init(
                failedTitle: "無法加入附件",
                failedBody: "檔案未能完成儲存到暫存架。",
                fullTitle: "暫存架已滿",
                fullBody: "附件已儲存，但暫存架已沒有空間。",
                okButton: "好")
        }
    }
}
