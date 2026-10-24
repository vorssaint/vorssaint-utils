// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

struct CleaningModeStrings {
    let autoUnlockAfter: String
    let timerCaption: String
}

extension FeatureStrings {
    static func cleaningMode(_ language: AppLanguage) -> CleaningModeStrings {
        switch language {
        case .enUS:
            return CleaningModeStrings(autoUnlockAfter: "Auto-unlock after",
                timerCaption: "Applies to the next cleaning session. Press Escape five times or click Unlock to end it early.")
        case .ptBR:
            return CleaningModeStrings(autoUnlockAfter: "Desbloquear automaticamente após",
                timerCaption: "Aplica-se à próxima sessão de limpeza. Pressione Escape cinco vezes ou clique em Desbloquear para encerrar antes.")
        case .tr:
            return CleaningModeStrings(autoUnlockAfter: "Otomatik kilit açma süresi",
                timerCaption: "Bir sonraki temizlik oturumunda uygulanır. Erken bitirmek için Escape tuşuna beş kez basın veya Kilidi Aç’a tıklayın.")
        case .ru:
            return CleaningModeStrings(autoUnlockAfter: "Автоматическая разблокировка через",
                timerCaption: "Применяется к следующему сеансу очистки. Нажмите Escape пять раз или кнопку разблокировки, чтобы завершить его раньше.")
        case .es:
            return CleaningModeStrings(autoUnlockAfter: "Desbloquear automáticamente después de",
                timerCaption: "Se aplica a la próxima sesión de limpieza. Pulsa Escape cinco veces o haz clic en Desbloquear para terminar antes.")
        case .sk:
            return CleaningModeStrings(autoUnlockAfter: "Automaticky odomknúť po",
                timerCaption: "Platí pre ďalšie čistenie. Na skoršie ukončenie stlačte Escape päťkrát alebo kliknite na Odomknúť.")
        case .de:
            return CleaningModeStrings(autoUnlockAfter: "Automatisch entsperren nach",
                timerCaption: "Gilt für die nächste Reinigung. Drücke fünfmal Escape oder klicke auf Entsperren, um sie früher zu beenden.")
        case .fr:
            return CleaningModeStrings(autoUnlockAfter: "Déverrouiller automatiquement après",
                timerCaption: "S’applique à la prochaine session de nettoyage. Appuyez cinq fois sur Échap ou cliquez sur Déverrouiller pour terminer plus tôt.")
        case .it:
            return CleaningModeStrings(autoUnlockAfter: "Sblocca automaticamente dopo",
                timerCaption: "Si applica alla prossima sessione di pulizia. Premi Esc cinque volte o fai clic su Sblocca per terminarla prima.")
        case .ja:
            return CleaningModeStrings(autoUnlockAfter: "自動ロック解除までの時間",
                timerCaption: "次回のクリーニングに適用されます。Escapeを5回押すか「ロック解除」をクリックすると、途中で終了できます。")
        case .ko:
            return CleaningModeStrings(autoUnlockAfter: "자동 잠금 해제 시간",
                timerCaption: "다음 청소 세션에 적용됩니다. 일찍 끝내려면 Escape를 다섯 번 누르거나 잠금 해제를 클릭하세요.")
        case .uk:
            return CleaningModeStrings(autoUnlockAfter: "Автоматично розблокувати через",
                timerCaption: "Застосовується до наступного сеансу очищення. Натисніть Escape п’ять разів або кнопку розблокування, щоб завершити раніше.")
        case .zhHans:
            return CleaningModeStrings(autoUnlockAfter: "自动解锁时间",
                timerCaption: "适用于下次清洁。按五次 Escape 或点击解锁可提前结束。")
        case .zhTW:
            return CleaningModeStrings(autoUnlockAfter: "自動解鎖時間",
                timerCaption: "適用於下次清潔。按五次 Escape 或點按解鎖可提前結束。")
        case .zhHK:
            return CleaningModeStrings(autoUnlockAfter: "自動解鎖時間",
                timerCaption: "適用於下次清潔。按五次 Escape 或按一下解鎖可提早結束。")
        }
    }
}
