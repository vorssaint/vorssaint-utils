// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

struct WindowSnapLayoutsStrings {
    let title: String
    let caption: String
    /// "Desktop 2": a desktop the dragged window can be dropped onto.
    let desktopFormat: String

    func desktop(_ number: Int) -> String {
        String(format: desktopFormat, number.formatted())
    }

    static func localized(_ language: AppLanguage) -> WindowSnapLayoutsStrings {
        switch language {
        case .enUS: return .init(title: "Show snap layouts while dragging a window", caption: "As soon as a window moves, Dynamic Island opens with layouts: drop the window on a part of one to put it there, or on a desktop to move it to that Space. Apps listed under Ignore apps are skipped.", desktopFormat: "Desktop %@")
        case .ptBR: return .init(title: "Mostrar layouts de encaixe ao arrastar uma janela", caption: "Assim que uma janela se move, a Dynamic Island abre com layouts: solte a janela em uma parte de um deles para colocá-la ali, ou em uma mesa para levá-la a esse Espaço. Apps listados em Ignorar apps são ignorados.", desktopFormat: "Mesa %@")
        case .tr: return .init(title: "Pencere sürüklenirken yerleşim düzenlerini göster", caption: "Bir pencere hareket etmeye başlar başlamaz Dynamic Island düzenlerle açılır: pencereyi oraya koymak için bir düzenin bir bölümüne, o Alana taşımak için bir masaüstüne bırakın. Yoksayılacak uygulamalar bölümündeki uygulamalar atlanır.", desktopFormat: "Masaüstü %@")
        case .ru: return .init(title: "Показывать раскладки при перетаскивании окна", caption: "Как только окно сдвигается, Dynamic Island открывается с раскладками: отпустите окно на часть раскладки, чтобы поставить его туда, или на рабочий стол, чтобы перенести его в это пространство. Приложения из раздела «Игнорируемые приложения» пропускаются.", desktopFormat: "Рабочий стол %@")
        case .es: return .init(title: "Mostrar diseños de ajuste al arrastrar una ventana", caption: "En cuanto una ventana se mueve, Dynamic Island se abre con diseños: suelta la ventana en una parte de uno para colocarla ahí, o en un escritorio para llevarla a ese espacio. Se omiten las apps de la lista Ignorar apps.", desktopFormat: "Escritorio %@")
        case .sk: return .init(title: "Zobraziť rozloženia pri ťahaní okna", caption: "Hneď ako sa okno pohne, Dynamic Island sa otvorí s rozloženiami: pustite okno na časť rozloženia, aby sa tam umiestnilo, alebo na plochu, aby sa presunulo do tohto priestoru. Aplikácie v sekcii Ignorované aplikácie sa preskakujú.", desktopFormat: "Plocha %@")
        case .de: return .init(title: "Beim Ziehen eines Fensters Layouts zeigen", caption: "Sobald sich ein Fenster bewegt, öffnet sich Dynamic Island mit Layouts: Lass das Fenster auf einem Teil eines Layouts los, um es dorthin zu setzen, oder auf einem Schreibtisch, um es in diesen Space zu bringen. Apps unter „Apps ignorieren“ bleiben außen vor.", desktopFormat: "Schreibtisch %@")
        case .fr: return .init(title: "Afficher les dispositions en faisant glisser une fenêtre", caption: "Dès qu’une fenêtre bouge, Dynamic Island s’ouvre avec des dispositions : déposez la fenêtre sur une partie de l’une d’elles pour l’y placer, ou sur un bureau pour l’envoyer dans cet espace. Les apps de la liste « Apps à ignorer » sont exclues.", desktopFormat: "Bureau %@")
        case .it: return .init(title: "Mostra i layout mentre trascini una finestra", caption: "Appena una finestra si muove, Dynamic Island si apre con i layout: rilascia la finestra su una parte di un layout per metterla lì, o su una scrivania per spostarla in quello spazio. Le app nell’elenco «Ignora app» vengono saltate.", desktopFormat: "Scrivania %@")
        case .ja: return .init(title: "ウインドウをドラッグ中にスナップレイアウトを表示", caption: "ウインドウが動き出すと Dynamic Island がレイアウトを表示します。レイアウトの一部にドロップするとそこに配置され、デスクトップにドロップするとその操作スペースに移動します。「無視するApp」に入っているAppは対象外です。", desktopFormat: "デスクトップ %@")
        case .ko: return .init(title: "윈도우를 끄는 동안 스냅 레이아웃 보기", caption: "윈도우가 움직이기 시작하면 Dynamic Island가 레이아웃을 보여 줍니다. 레이아웃의 한 부분에 놓으면 그 자리에 배치되고, 데스크탑에 놓으면 해당 Space로 이동합니다. 무시할 앱에 있는 앱은 건너뜁니다.", desktopFormat: "데스크탑 %@")
        case .zhHans: return .init(title: "拖移窗口时显示贴靠布局", caption: "窗口一开始移动，Dynamic Island 就会展开布局：把窗口放到某个布局的一部分即可放在那里，放到某个桌面即可移到那个空间。“忽略的 App”中的 App 不受影响。", desktopFormat: "桌面 %@")
        case .zhTW: return .init(title: "拖移視窗時顯示貼齊佈局", caption: "視窗一開始移動，Dynamic Island 就會展開佈局：將視窗放到某個佈局的一部分即可放在那裡，放到某個桌面即可移到那個空間。「忽略的 App」中的 App 不受影響。", desktopFormat: "桌面 %@")
        case .zhHK: return .init(title: "拖移視窗時顯示貼齊佈局", caption: "視窗一開始移動，Dynamic Island 就會展開佈局：將視窗放到某個佈局的一部分即可放喺嗰度，放到某個桌面即可移到嗰個空間。「忽略的 App」中的 App 不受影響。", desktopFormat: "桌面 %@")
        case .uk: return .init(title: "Показувати розкладки під час перетягування вікна", caption: "Щойно вікно зрушує, Dynamic Island відкривається з розкладками: відпустіть вікно на частину розкладки, щоб поставити його туди, або на робочий стіл, щоб перенести його в той простір. Програми з розділу «Ігноровані програми» пропускаються.", desktopFormat: "Робочий стіл %@")
        }
    }
}
