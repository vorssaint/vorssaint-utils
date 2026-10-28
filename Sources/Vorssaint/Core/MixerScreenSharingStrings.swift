// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

struct MixerScreenSharingStrings {
    let allowVolumeControl: String
    let protectedCaption: String
    let sharingWarning: String

    static func localized(_ language: AppLanguage) -> MixerScreenSharingStrings {
        switch language {
        case .enUS: return .init(
            allowVolumeControl: "Allow volume control",
            protectedCaption: "Volume control is off to prevent echo when sharing audio.",
            sharingWarning: "Turn off volume control before sharing audio to avoid echo.")
        case .ptBR: return .init(
            allowVolumeControl: "Permitir controle de volume",
            protectedCaption: "O controle de volume está desativado para evitar eco ao compartilhar áudio.",
            sharingWarning: "Desative o controle de volume antes de compartilhar áudio para evitar eco.")
        case .tr: return .init(
            allowVolumeControl: "Ses düzeyi kontrolüne izin ver",
            protectedCaption: "Ses paylaşırken yankıyı önlemek için ses düzeyi kontrolü kapalı.",
            sharingWarning: "Yankıyı önlemek için ses paylaşmadan önce ses düzeyi kontrolünü kapatın.")
        case .ru: return .init(
            allowVolumeControl: "Разрешить регулировку громкости",
            protectedCaption: "Регулировка громкости отключена, чтобы избежать эха при передаче звука.",
            sharingWarning: "Отключите регулировку громкости перед передачей звука, чтобы избежать эха.")
        case .es: return .init(
            allowVolumeControl: "Permitir el control de volumen",
            protectedCaption: "El control de volumen está desactivado para evitar eco al compartir audio.",
            sharingWarning: "Desactiva el control de volumen antes de compartir audio para evitar eco.")
        case .sk: return .init(
            allowVolumeControl: "Povoliť ovládanie hlasitosti",
            protectedCaption: "Ovládanie hlasitosti je vypnuté, aby pri zdieľaní zvuku nevznikala ozvena.",
            sharingWarning: "Pred zdieľaním zvuku vypnite ovládanie hlasitosti, aby nevznikala ozvena.")
        case .de: return .init(
            allowVolumeControl: "Lautstärkeregelung erlauben",
            protectedCaption: "Die Lautstärkeregelung ist aus, um Echo beim Teilen von Audio zu vermeiden.",
            sharingWarning: "Schalte die Lautstärkeregelung vor dem Teilen von Audio aus, um Echo zu vermeiden.")
        case .fr: return .init(
            allowVolumeControl: "Autoriser le réglage du volume",
            protectedCaption: "Le réglage du volume est désactivé pour éviter l’écho lors du partage audio.",
            sharingWarning: "Désactivez le réglage du volume avant de partager l’audio pour éviter l’écho.")
        case .it: return .init(
            allowVolumeControl: "Consenti il controllo del volume",
            protectedCaption: "Il controllo del volume è disattivato per evitare l’eco durante la condivisione audio.",
            sharingWarning: "Disattiva il controllo del volume prima di condividere l’audio per evitare l’eco.")
        case .ja: return .init(
            allowVolumeControl: "音量調整を許可",
            protectedCaption: "音声共有時のエコーを防ぐため、音量調整は無効になっています。",
            sharingWarning: "エコーを防ぐため、音声を共有する前に音量調整を無効にしてください。")
        case .ko: return .init(
            allowVolumeControl: "음량 조절 허용",
            protectedCaption: "오디오 공유 시 에코를 방지하기 위해 음량 조절이 꺼져 있습니다.",
            sharingWarning: "에코를 방지하려면 오디오를 공유하기 전에 음량 조절을 끄세요.")
        case .uk: return .init(
            allowVolumeControl: "Дозволити регулювання гучності",
            protectedCaption: "Регулювання гучності вимкнено, щоб уникнути відлуння під час передавання звуку.",
            sharingWarning: "Вимкніть регулювання гучності перед передаванням звуку, щоб уникнути відлуння.")
        case .zhHans: return .init(
            allowVolumeControl: "允许音量控制",
            protectedCaption: "音量控制已关闭，以防止共享音频时产生回声。",
            sharingWarning: "共享音频前请关闭音量控制，以避免回声。")
        case .zhTW: return .init(
            allowVolumeControl: "允許音量控制",
            protectedCaption: "音量控制已關閉，以防止分享音訊時產生回音。",
            sharingWarning: "分享音訊前請關閉音量控制，以避免回音。")
        case .zhHK: return .init(
            allowVolumeControl: "允許音量控制",
            protectedCaption: "音量控制已關閉，以防止分享音訊時產生回音。",
            sharingWarning: "分享音訊前請關閉音量控制，以避免回音。")
        }
    }
}
