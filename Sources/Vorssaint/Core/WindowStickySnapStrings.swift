// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

struct WindowStickySnapStrings {
    let title: String
    let caption: String

    static func localized(_ language: AppLanguage) -> WindowStickySnapStrings {
        switch language {
        case .enUS: return .init(title: "Resize placed neighbors together", caption: "When two windows placed by Window layout share an edge, resizing one at that edge resizes the other with it. Windows that cannot be resized stay as they are, and dragging a window away ends the pairing.")
        case .ptBR: return .init(title: "Redimensionar janelas vizinhas juntas", caption: "Quando duas janelas posicionadas pelo Layout de janelas compartilham uma borda, redimensionar uma nessa borda redimensiona a outra junto. Janelas que não podem ser redimensionadas ficam como estão, e arrastar uma janela desfaz o par.")
        case .tr: return .init(title: "Yerleştirilen komşu pencereleri birlikte yeniden boyutlandır", caption: "Pencere yerleşimi ile yerleştirilen iki pencere bir kenarı paylaşıyorsa, birini o kenardan yeniden boyutlandırmak diğerini de boyutlandırır. Yeniden boyutlandırılamayan pencereler olduğu gibi kalır; bir pencereyi sürüklemek eşleşmeyi sonlandırır.")
        case .ru: return .init(title: "Менять размер соседних окон вместе", caption: "Если два окна, размещённых функцией «Раскладка окон», имеют общий край, изменение размера одного по этому краю меняет и другое. Окна, размер которых изменить нельзя, остаются как есть, а перетаскивание окна разрывает пару.")
        case .es: return .init(title: "Redimensionar juntas las ventanas vecinas", caption: "Cuando dos ventanas colocadas por Diseño de ventanas comparten un borde, redimensionar una por ese borde redimensiona también la otra. Las ventanas que no se pueden redimensionar se quedan como están, y arrastrar una ventana deshace la pareja.")
        case .sk: return .init(title: "Meniť veľkosť susedných okien spolu", caption: "Keď dve okná umiestnené funkciou Rozloženie okien zdieľajú okraj, zmena veľkosti jedného na tomto okraji zmení aj druhé. Okná, ktorým sa nedá meniť veľkosť, ostanú, ako sú, a presunutie okna dvojicu zruší.")
        case .de: return .init(title: "Angeordnete Nachbarfenster gemeinsam skalieren", caption: "Teilen sich zwei von der Fensterlayout platzierte Fenster eine Kante, skaliert das Ändern der Größe an dieser Kante das andere Fenster mit. Fenster, deren Größe sich nicht ändern lässt, bleiben unverändert, und Wegziehen eines Fensters löst die Kopplung.")
        case .fr: return .init(title: "Redimensionner ensemble les fenêtres voisines", caption: "Lorsque deux fenêtres placées par la Disposition des fenêtres partagent un bord, redimensionner l’une sur ce bord redimensionne aussi l’autre. Les fenêtres qui ne peuvent pas être redimensionnées restent telles quelles, et déplacer une fenêtre met fin au couplage.")
        case .it: return .init(title: "Ridimensiona insieme le finestre adiacenti", caption: "Quando due finestre posizionate dalla Layout finestre condividono un bordo, ridimensionarne una su quel bordo ridimensiona anche l’altra. Le finestre che non si possono ridimensionare restano come sono, e trascinare una finestra scioglie la coppia.")
        case .ja: return .init(title: "配置した隣のウインドウを一緒にリサイズ", caption: "ウインドウ配置で配置した2つのウインドウが辺を共有しているとき、その辺で一方のサイズを変えると、もう一方も一緒に変わります。サイズを変更できないウインドウはそのままで、ウインドウをドラッグすると組み合わせは解除されます。")
        case .ko: return .init(title: "배치한 이웃 윈도우를 함께 크기 조절", caption: "윈도우 정렬로 배치한 두 윈도우가 가장자리를 공유하면, 그 가장자리에서 한쪽 크기를 바꿀 때 다른 쪽도 함께 바뀝니다. 크기를 바꿀 수 없는 윈도우는 그대로 두며, 윈도우를 끌어 옮기면 짝이 해제됩니다.")
        case .zhHans: return .init(title: "一起调整相邻已排布窗口的大小", caption: "当由窗口布局排布的两个窗口共用一条边时，沿这条边调整其中一个的大小，另一个会随之调整。无法调整大小的窗口保持不变，拖动窗口会解除配对。")
        case .zhTW: return .init(title: "一併調整相鄰已配置視窗的大小", caption: "當由視窗排列功能配置的兩個視窗共用一條邊時，沿該邊調整其中一個的大小，另一個也會隨之調整。無法調整大小的視窗維持原樣，拖移視窗會解除配對。")
        case .zhHK: return .init(title: "一併調整相鄰已配置視窗的大小", caption: "當由視窗排列功能配置的兩個視窗共用一條邊時，沿該邊調整其中一個的大小，另一個亦會隨之調整。無法調整大小的視窗維持原樣，拖移視窗會解除配對。")
        case .uk: return .init(title: "Змінювати розмір сусідніх вікон разом", caption: "Якщо два вікна, розміщені функцією «Розкладка вікон», мають спільний край, зміна розміру одного біля цього краю змінює й друге. Вікна, розмір яких змінити не можна, залишаються як є, а перетягування вікна розриває пару.")
        }
    }
}
