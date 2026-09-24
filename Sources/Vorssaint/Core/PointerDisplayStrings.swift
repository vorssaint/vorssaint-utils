// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

struct PointerDisplayStrings {
    let title: String
    let caption: String

    static func localized(_ language: AppLanguage) -> PointerDisplayStrings {
        switch language {
        case .enUS: return .init(title: "Move pointer to next display", caption: "Puts the pointer in the center of the next display.")
        case .ptBR: return .init(title: "Mover ponteiro para o próximo display", caption: "Coloca o ponteiro no centro do próximo display.")
        case .tr: return .init(title: "İşaretçiyi sonraki ekrana taşı", caption: "İşaretçiyi sonraki ekranın ortasına götürür.")
        case .ru: return .init(title: "Переместить указатель на следующий дисплей", caption: "Ставит указатель в центр следующего дисплея.")
        case .es: return .init(title: "Mover puntero a la siguiente pantalla", caption: "Coloca el puntero en el centro de la siguiente pantalla.")
        case .de: return .init(title: "Zeiger auf nächstes Display bewegen", caption: "Setzt den Zeiger in die Mitte des nächsten Displays.")
        case .fr: return .init(title: "Déplacer le pointeur vers l’écran suivant", caption: "Place le pointeur au centre de l’écran suivant.")
        case .it: return .init(title: "Sposta il puntatore al display successivo", caption: "Porta il puntatore al centro del display successivo.")
        case .ja: return .init(title: "ポインタを次のディスプレイへ移動", caption: "ポインタを次のディスプレイの中央に移動します。")
        case .ko: return .init(title: "포인터를 다음 디스플레이로 이동", caption: "포인터를 다음 디스플레이의 가운데로 옮깁니다.")
        case .zhHans: return .init(title: "将指针移到下一台显示器", caption: "将指针移到下一台显示器的中央。")
        case .zhTW: return .init(title: "將指標移到下一台顯示器", caption: "將指標移到下一台顯示器的中央。")
        case .zhHK: return .init(title: "將指標移到下一部顯示器", caption: "將指標移到下一部顯示器的中央。")
        }
    }
}
