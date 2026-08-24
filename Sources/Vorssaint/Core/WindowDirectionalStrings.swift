// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

struct WindowDirectionalStrings {
    let title: String
    let caption: String

    static func localized(_ language: AppLanguage) -> WindowDirectionalStrings {
        switch language {
        case .enUS: return .init(title: "Shortcut + pointer layout", caption: "Hold the shortcut, move the pointer toward an edge or corner, then release to place the active window.")
        case .ptBR: return .init(title: "Atalho + ponteiro", caption: "Segure o atalho, mova o ponteiro para uma borda ou canto e solte para posicionar a janela ativa.")
        case .tr: return .init(title: "Kestirme + işaretçi düzeni", caption: "Kestirmeyi basılı tutun, işaretçiyi bir kenara veya köşeye götürün ve etkin pencereyi yerleştirmek için bırakın.")
        case .ru: return .init(title: "Сочетание + указатель", caption: "Удерживайте сочетание, переместите указатель к краю или углу и отпустите, чтобы разместить активное окно.")
        case .es: return .init(title: "Atajo + puntero", caption: "Mantén el atajo, mueve el puntero hacia un borde o esquina y suéltalo para colocar la ventana activa.")
        case .de: return .init(title: "Kürzel + Zeiger", caption: "Kürzel halten, Zeiger zu einem Rand oder einer Ecke bewegen und loslassen, um das aktive Fenster anzuordnen.")
        case .fr: return .init(title: "Raccourci + pointeur", caption: "Maintenez le raccourci, déplacez le pointeur vers un bord ou un coin, puis relâchez pour placer la fenêtre active.")
        case .it: return .init(title: "Scorciatoia + puntatore", caption: "Tieni premuta la scorciatoia, sposta il puntatore verso un bordo o angolo e rilascia per posizionare la finestra attiva.")
        case .ja: return .init(title: "ショートカット＋ポインタ配置", caption: "ショートカットを押したままポインタを端または角へ動かし、放すとアクティブウインドウを配置します。")
        case .ko: return .init(title: "단축키 + 포인터 배치", caption: "단축키를 누른 채 포인터를 가장자리나 모서리로 이동한 다음 놓아 활성 윈도우를 배치합니다.")
        case .zhHans: return .init(title: "快捷键 + 鼠标布局", caption: "按住快捷键，将鼠标移向屏幕边缘或角落，松开后摆放当前窗口。")
        case .zhTW: return .init(title: "快速鍵 + 滑鼠配置", caption: "按住快速鍵，將滑鼠移向螢幕邊緣或角落，放開後配置目前視窗。")
        case .zhHK: return .init(title: "快捷鍵 + 滑鼠配置", caption: "按住快捷鍵，將滑鼠移向螢幕邊緣或角落，放開後配置目前視窗。")
        }
    }
}
