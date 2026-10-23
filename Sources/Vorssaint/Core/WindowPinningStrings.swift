// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

struct WindowPinningStrings {
    let pageTitle: String
    let featureCaption: String
    let enableToggle: String
    let enableCaption: String
    let shortcutSection: String
    let shortcutCaption: String
    let pinNowButton: String
    let unpinAllButton: String
    let pinnedCountFormat: String
    let pinnedNone: String
    let unsupportedTitle: String
    let unsupportedCaption: String
    let permissionRowTitle: String
    let permissionRowCaption: String
    let allSpacesToggle: String
    let allSpacesCaption: String
}

extension WindowPinningStrings {
    static let enUS = WindowPinningStrings(
        pageTitle: "Window Pinning",
        featureCaption: "Keeps the windows you pin floating above everything else.",
        enableToggle: "Pin windows on top",
        enableCaption: "Shows a live clone of the focused window that stays in front of everything else. Accessibility finds the window; Screen Recording draws the clone.",
        shortcutSection: "Shortcut",
        shortcutCaption: "Press it to pin or unpin the window that is currently focused.",
        pinNowButton: "Pin Focused Window",
        unpinAllButton: "Unpin All",
        pinnedCountFormat: "Pinned windows: %d",
        pinnedNone: "No pinned windows",
        unsupportedTitle: "Window Pinning is waiting for Accessibility",
        unsupportedCaption: "Grant Accessibility so Vorssaint can find the focused window and keep pinned windows in front.",
        permissionRowTitle: "Permissions",
        permissionRowCaption: "Accessibility finds the focused window. Screen Recording draws the live clone that stays in front.",
        allSpacesToggle: "Show pinned windows on all Spaces",
        allSpacesCaption: "The clone follows you to every Space. There it is a live view only: click it to go back to the window. Some apps, such as Chrome, stop drawing a window on another Space, so its clone can freeze or turn black."
    )

    static let ptBR = WindowPinningStrings(
        pageTitle: "Fixar Janelas no Topo",
        featureCaption: "Mantém as janelas que você fixa sempre acima de tudo.",
        enableToggle: "Fixar janelas no topo",
        enableCaption: "Mostra um clone ao vivo da janela em foco que fica sempre na frente de tudo. A Acessibilidade encontra a janela; a Gravação de Tela desenha o clone.",
        shortcutSection: "Atalho",
        shortcutCaption: "Pressione para fixar ou desafixar a janela em foco.",
        pinNowButton: "Fixar Janela em Foco",
        unpinAllButton: "Desafixar Tudo",
        pinnedCountFormat: "Janelas fixadas: %d",
        pinnedNone: "Nenhuma janela fixada",
        unsupportedTitle: "A fixação de janelas está aguardando a Acessibilidade",
        unsupportedCaption: "Conceda a Acessibilidade para que o Vorssaint possa encontrar a janela em foco e manter as janelas fixadas na frente.",
        permissionRowTitle: "Permissões",
        permissionRowCaption: "A Acessibilidade encontra a janela em foco. A Gravação de Tela desenha o clone ao vivo que fica na frente.",
        allSpacesToggle: "Mostrar janelas fixadas em todos os Espaços",
        allSpacesCaption: "O clone acompanha você em todos os Espaços. Lá ele é só uma visualização ao vivo: clique nele para voltar à janela. Alguns apps, como o Chrome, param de desenhar uma janela que está em outro Espaço, então o clone pode congelar ou ficar preto."
    )

    static let tr = WindowPinningStrings(
        pageTitle: "Pencere Sabitleme",
        featureCaption: "Sabitlediğiniz pencerelerin diğer tüm pencerelerin üzerinde kalmasını sağlar.",
        enableToggle: "Pencereleri en üstte sabitle",
        enableCaption: "Odaklanılan pencerenin, diğer her şeyin üzerinde kalan canlı bir kopyasını gösterir. Erişilebilirlik pencereyi bulur; Ekran Kaydı kopyayı çizer.",
        shortcutSection: "Kısayol",
        shortcutCaption: "Şu anda odaklanılan pencereyi sabitlemek veya sabitlemesini kaldırmak için basın.",
        pinNowButton: "Odaklanılan pencereyi sabitle",
        unpinAllButton: "Tüm sabitlemeleri kaldır",
        pinnedCountFormat: "Sabitlenmiş pencereler: %d",
        pinnedNone: "Sabitlenmiş pencere yok",
        unsupportedTitle: "Pencere Sabitleme Erişilebilirlik iznini bekliyor",
        unsupportedCaption: "Vorssaint’ın odaklanılan pencereyi bulabilmesi ve sabitlenmiş pencereleri ön planda tutabilmesi için Erişilebilirlik izni verin.",
        permissionRowTitle: "İzinler",
        permissionRowCaption: "Erişilebilirlik odaklanılan pencereyi bulur. Ekran Kaydı, ön planda kalan canlı kopyayı çizer.",
        allSpacesToggle: "Sabitlenmiş pencereleri tüm Alanlarda göster",
        allSpacesCaption: "Klon sizi her Alana takip eder. Orada yalnızca canlı bir görüntüdür: pencereye dönmek için tıklayın. Chrome gibi bazı uygulamalar başka bir Alandaki pencereyi çizmeyi bırakır, bu yüzden klon donabilir veya kararabilir."
    )

    static let ru = WindowPinningStrings(
        pageTitle: "Закрепление окон",
        featureCaption: "Держит закреплённые окна поверх всех остальных.",
        enableToggle: "Закреплять окна поверх других окон",
        enableCaption: "Показывает живую копию активного окна поверх всех остальных окон. Универсальный доступ находит окно, а Запись экрана рисует копию.",
        shortcutSection: "Сочетание клавиш",
        shortcutCaption: "Нажмите, чтобы закрепить или открепить активное окно.",
        pinNowButton: "Закрепить активное окно",
        unpinAllButton: "Открепить все",
        pinnedCountFormat: "Закреплено окон: %d",
        pinnedNone: "Нет закреплённых окон",
        unsupportedTitle: "Закрепление окон ждёт Универсальный доступ",
        unsupportedCaption: "Предоставьте Универсальный доступ, чтобы Vorssaint мог находить активное окно и держать закреплённые окна поверх остальных.",
        permissionRowTitle: "Разрешения",
        permissionRowCaption: "Универсальный доступ находит активное окно, а Запись экрана рисует живую копию, которая остаётся поверх.",
        allSpacesToggle: "Показывать закреплённые окна на всех рабочих столах",
        allSpacesCaption: "Клон следует за вами на каждый рабочий стол. Там он только показывает окно: нажмите на него, чтобы вернуться к окну. Некоторые приложения, например Chrome, перестают отрисовывать окно на другом рабочем столе, поэтому клон может застыть или стать чёрным."
    )

    static let es = WindowPinningStrings(
        pageTitle: "Anclaje de ventanas",
        featureCaption: "Mantiene las ventanas que anclas flotando por encima de todo lo demás.",
        enableToggle: "Anclar ventanas encima",
        enableCaption: "Muestra un clon en vivo de la ventana activa que permanece por delante de todo lo demás. Accesibilidad encuentra la ventana; Grabación de pantalla dibuja el clon.",
        shortcutSection: "Atajo",
        shortcutCaption: "Púlsalo para anclar o desanclar la ventana activa.",
        pinNowButton: "Anclar ventana activa",
        unpinAllButton: "Desanclar todas",
        pinnedCountFormat: "Ventanas ancladas: %d",
        pinnedNone: "Sin ventanas ancladas",
        unsupportedTitle: "El anclaje de ventanas está esperando Accesibilidad",
        unsupportedCaption: "Concede Accesibilidad para que Vorssaint pueda encontrar la ventana activa y mantener las ventanas ancladas al frente.",
        permissionRowTitle: "Permisos",
        permissionRowCaption: "Accesibilidad encuentra la ventana activa. Grabación de pantalla dibuja el clon en vivo que permanece al frente.",
        allSpacesToggle: "Mostrar las ventanas ancladas en todos los Espacios",
        allSpacesCaption: "El clon te sigue a cada Espacio. Allí solo es una vista en vivo: haz clic en él para volver a la ventana. Algunas apps, como Chrome, dejan de dibujar una ventana que está en otro Espacio, así que su clon puede congelarse o quedarse en negro."
    )

    static let sk = WindowPinningStrings(
        pageTitle: "Pripnutie okien",
        featureCaption: "Udržiava okná, ktoré pripnete, plávajúce nad všetkým ostatným.",
        enableToggle: "Pripínať okná vždy navrchu",
        enableCaption: "Zobrazuje živý klon zameraného okna, ktorý zostáva pred všetkým ostatným. Okno nájde Prístupnosť, klon vykreslí Nahrávanie obrazovky.",
        shortcutSection: "Skratka",
        shortcutCaption: "Stlačením pripnete alebo odpnete práve zamerané okno.",
        pinNowButton: "Pripnúť zamerané okno",
        unpinAllButton: "Odpnúť všetko",
        pinnedCountFormat: "Pripnuté okná: %d",
        pinnedNone: "Žiadne pripnuté okná",
        unsupportedTitle: "Pripnutie okien čaká na Prístupnosť",
        unsupportedCaption: "Udeľte Prístupnosť, aby Vorssaint mohol nájsť zamerané okno a udržiavať pripnuté okná navrchu.",
        permissionRowTitle: "Povolenia",
        permissionRowCaption: "Prístupnosť nájde zamerané okno. Nahrávanie obrazovky vykreslí živý klon, ktorý zostáva navrchu.",
        allSpacesToggle: "Zobrazovať pripnuté okná na všetkých plochách",
        allSpacesCaption: "Klon vás nasleduje na každú plochu. Tam je to iba živý náhľad: kliknutím naň sa vrátite k oknu. Niektoré aplikácie, napríklad Chrome, prestanú vykresľovať okno na inej ploche, takže jeho klon môže zamrznúť alebo sčernieť."
    )

    static let de = WindowPinningStrings(
        pageTitle: "Fenster anheften",
        featureCaption: "Hält die Fenster, die du anheftest, immer im Vordergrund.",
        enableToggle: "Fenster immer im Vordergrund anheften",
        enableCaption: "Zeigt einen Live-Klon des fokussierten Fensters an, der immer vor allem anderen bleibt. Die Bedienungshilfen finden das Fenster; die Bildschirmaufnahme zeichnet den Klon.",
        shortcutSection: "Kurzbefehl",
        shortcutCaption: "Drücke ihn, um das aktuell fokussierte Fenster anzuheften oder wieder zu lösen.",
        pinNowButton: "Aktives Fenster anheften",
        unpinAllButton: "Alle lösen",
        pinnedCountFormat: "Angeheftete Fenster: %d",
        pinnedNone: "Keine angehefteten Fenster",
        unsupportedTitle: "Fenster anheften wartet auf die Bedienungshilfen",
        unsupportedCaption: "Gewähre den Zugriff auf die Bedienungshilfen, damit Vorssaint das fokussierte Fenster finden und angeheftete Fenster im Vordergrund halten kann.",
        permissionRowTitle: "Berechtigungen",
        permissionRowCaption: "Die Bedienungshilfen finden das fokussierte Fenster. Die Bildschirmaufnahme zeichnet den Live-Klon, der im Vordergrund bleibt.",
        allSpacesToggle: "Angeheftete Fenster in allen Spaces zeigen",
        allSpacesCaption: "Der Klon folgt dir in jeden Space. Dort ist er nur eine Live-Ansicht: Klicke darauf, um zum Fenster zurückzukehren. Manche Apps wie Chrome zeichnen ein Fenster in einem anderen Space nicht mehr, daher kann sein Klon einfrieren oder schwarz werden."
    )

    static let fr = WindowPinningStrings(
        pageTitle: "Épinglage de fenêtres",
        featureCaption: "Garde les fenêtres épinglées flottant au-dessus de tout le reste.",
        enableToggle: "Épingler les fenêtres au premier plan",
        enableCaption: "Affiche un clone en direct de la fenêtre active qui reste au-dessus de tout le reste. L’Accessibilité repère la fenêtre, l’Enregistrement de l’écran dessine le clone.",
        shortcutSection: "Raccourci",
        shortcutCaption: "Appuyer dessus pour épingler ou désépingler la fenêtre actuellement active.",
        pinNowButton: "Épingler la fenêtre active",
        unpinAllButton: "Tout désépingler",
        pinnedCountFormat: "Fenêtres épinglées\u{00A0}: %d",
        pinnedNone: "Aucune fenêtre épinglée",
        unsupportedTitle: "L’épinglage de fenêtres attend l’Accessibilité",
        unsupportedCaption: "Accordez l’Accessibilité à Vorssaint pour qu’il puisse repérer la fenêtre active et garder les fenêtres épinglées au premier plan.",
        permissionRowTitle: "Autorisations",
        permissionRowCaption: "L’Accessibilité repère la fenêtre active. L’Enregistrement de l’écran dessine le clone en direct qui reste au premier plan.",
        allSpacesToggle: "Afficher les fenêtres épinglées dans tous les espaces",
        allSpacesCaption: "Le clone vous suit dans chaque espace. Là, ce n’est qu’un aperçu en direct\u{00A0}: cliquez dessus pour revenir à la fenêtre. Certaines apps, comme Chrome, cessent de dessiner une fenêtre située dans un autre espace, et son clone peut alors se figer ou devenir noir."
    )

    static let it = WindowPinningStrings(
        pageTitle: "Finestre in primo piano",
        featureCaption: "Mantiene le finestre bloccate sopra tutte le altre.",
        enableToggle: "Blocca le finestre in primo piano",
        enableCaption: "Mostra un clone in tempo reale della finestra attiva che resta sopra tutto il resto. Accessibilità trova la finestra; Registrazione schermo disegna il clone.",
        shortcutSection: "Scorciatoia",
        shortcutCaption: "Premila per bloccare o sbloccare la finestra attualmente attiva.",
        pinNowButton: "Blocca la finestra attiva",
        unpinAllButton: "Sblocca tutte",
        pinnedCountFormat: "Finestre bloccate: %d",
        pinnedNone: "Nessuna finestra bloccata",
        unsupportedTitle: "Il blocco delle finestre è in attesa di Accessibilità",
        unsupportedCaption: "Concedi Accessibilità a Vorssaint per trovare la finestra attiva e tenere le finestre bloccate in primo piano.",
        permissionRowTitle: "Autorizzazioni",
        permissionRowCaption: "Accessibilità trova la finestra attiva. Registrazione schermo disegna il clone in tempo reale che resta in primo piano.",
        allSpacesToggle: "Mostra le finestre bloccate in tutti gli Spazi",
        allSpacesCaption: "Il clone ti segue in ogni Spazio. Lì è solo un’anteprima dal vivo: fai clic su di esso per tornare alla finestra. Alcune app, come Chrome, smettono di disegnare una finestra che si trova in un altro Spazio, quindi il suo clone può bloccarsi o diventare nero."
    )

    static let ja = WindowPinningStrings(
        pageTitle: "ウインドウのピン留め",
        featureCaption: "ピン留めしたウインドウを常に最前面に表示します。",
        enableToggle: "ウインドウを最前面にピン留め",
        enableCaption: "フォーカス中のウインドウのライブクローンを表示し、常に最前面に表示します。アクセシビリティがウインドウを探し、画面収録がクローンを描画します。",
        shortcutSection: "ショートカット",
        shortcutCaption: "押すと、フォーカス中のウインドウをピン留めまたは解除します。",
        pinNowButton: "フォーカス中のウインドウをピン留め",
        unpinAllButton: "すべてのピン留めを解除",
        pinnedCountFormat: "ピン留め中のウインドウ：%d",
        pinnedNone: "ピン留め中のウインドウはありません",
        unsupportedTitle: "ウインドウのピン留めはアクセシビリティを待っています",
        unsupportedCaption: "アクセシビリティを許可すると、Vorssaintはフォーカス中のウインドウを探し、ピン留めしたウインドウを前面に表示し続けられます。",
        permissionRowTitle: "権限",
        permissionRowCaption: "アクセシビリティがフォーカス中のウインドウを探し、画面収録が常に最前面に表示するライブクローンを描画します。",
        allSpacesToggle: "ピン留めしたウインドウをすべてのスペースに表示",
        allSpacesCaption: "クローンがすべてのスペースについてきます。そこではライブ表示のみで、クリックすると元のウインドウに戻ります。Chrome などの一部のアプリは別のスペースにあるウインドウの描画を止めるため、クローンが止まったり黒くなったりすることがあります。"
    )

    static let ko = WindowPinningStrings(
        pageTitle: "윈도우 고정",
        featureCaption: "고정한 윈도우를 다른 모든 윈도우 위에 떠 있도록 유지합니다.",
        enableToggle: "윈도우를 맨 위에 고정",
        enableCaption: "포커스된 윈도우의 실시간 복제를 만들어 다른 모든 것보다 앞에 유지합니다. 손쉬운 사용이 윈도우를 찾고, 화면 녹화가 복제를 그립니다.",
        shortcutSection: "단축키",
        shortcutCaption: "눌러서 현재 포커스된 윈도우를 고정하거나 고정 해제합니다.",
        pinNowButton: "포커스된 윈도우 고정",
        unpinAllButton: "모두 고정 해제",
        pinnedCountFormat: "고정된 윈도우: %d개",
        pinnedNone: "고정된 윈도우 없음",
        unsupportedTitle: "윈도우 고정이 손쉬운 사용을 기다리고 있습니다",
        unsupportedCaption: "손쉬운 사용을 허용하면 Vorssaint가 포커스된 윈도우를 찾고 고정된 윈도우를 앞에 유지할 수 있습니다.",
        permissionRowTitle: "권한",
        permissionRowCaption: "손쉬운 사용이 포커스된 윈도우를 찾고, 화면 녹화가 앞에 유지되는 실시간 복제를 그립니다.",
        allSpacesToggle: "고정된 윈도우를 모든 스페이스에 표시",
        allSpacesCaption: "클론이 모든 스페이스로 따라옵니다. 그곳에서는 실시간 보기만 가능하며, 클릭하면 원래 윈도우로 돌아갑니다. Chrome 같은 일부 앱은 다른 스페이스에 있는 윈도우를 그리지 않으므로 클론이 멈추거나 검게 보일 수 있습니다."
    )

    static let zhHans = WindowPinningStrings(
        pageTitle: "窗口置顶",
        featureCaption: "让你置顶的窗口始终浮于其他窗口之上。",
        enableToggle: "将窗口置顶",
        enableCaption: "显示聚焦窗口的实时克隆，让它始终保持在其他所有内容之上。辅助功能负责找到窗口，屏幕录制负责绘制克隆。",
        shortcutSection: "快捷键",
        shortcutCaption: "按下即可置顶或取消置顶当前聚焦的窗口。",
        pinNowButton: "置顶聚焦窗口",
        unpinAllButton: "全部取消置顶",
        pinnedCountFormat: "已置顶的窗口：%d",
        pinnedNone: "没有置顶的窗口",
        unsupportedTitle: "窗口置顶正在等待辅助功能权限",
        unsupportedCaption: "授予辅助功能权限，以便 Vorssaint 找到聚焦的窗口并让置顶的窗口保持在最前。",
        permissionRowTitle: "权限",
        permissionRowCaption: "辅助功能找到聚焦的窗口，屏幕录制绘制始终保持在最前的实时克隆。",
        allSpacesToggle: "在所有桌面上显示置顶的窗口",
        allSpacesCaption: "克隆会跟随你到每个桌面。在那里它只是实时画面：点击它即可回到原窗口。Chrome 等部分应用会停止绘制位于其他桌面的窗口，因此克隆可能会卡住或变黑。"
    )

    static let zhTW = WindowPinningStrings(
        pageTitle: "視窗釘選",
        featureCaption: "讓你釘選的視窗浮動在其他所有視窗之上。",
        enableToggle: "將視窗釘選置頂",
        enableCaption: "顯示焦點視窗的即時複本，使其保持在所有內容之前。輔助使用負責尋找視窗，螢幕錄製負責繪製複本。",
        shortcutSection: "快速鍵",
        shortcutCaption: "按下即可釘選或取消釘選目前聚焦的視窗。",
        pinNowButton: "釘選焦點視窗",
        unpinAllButton: "全部取消釘選",
        pinnedCountFormat: "已釘選的視窗：%d",
        pinnedNone: "沒有已釘選的視窗",
        unsupportedTitle: "視窗釘選正在等待輔助使用授權",
        unsupportedCaption: "請授予輔助使用權限，讓 Vorssaint 能尋找焦點視窗，並將釘選的視窗保持在最前面。",
        permissionRowTitle: "權限",
        permissionRowCaption: "輔助使用會尋找焦點視窗，螢幕錄製會繪製保持在最前面的即時複本。",
        allSpacesToggle: "在所有桌面上顯示已釘選的視窗",
        allSpacesCaption: "克隆會跟著你到每個桌面。在那裡它只是即時畫面：按一下即可回到原視窗。Chrome 等部分 App 會停止繪製位於其他桌面的視窗，因此克隆可能會停住或變黑。"
    )

    static let zhHK = WindowPinningStrings(
        pageTitle: "視窗置頂",
        featureCaption: "讓你置頂的視窗保持在所有其他內容之上。",
        enableToggle: "將視窗置頂",
        enableCaption: "顯示目前視窗的即時複製畫面，讓它保持在所有內容之前。「輔助使用」尋找視窗；「螢幕錄製」繪製複製畫面。",
        shortcutSection: "快捷鍵",
        shortcutCaption: "按下即可置頂或取消置頂目前的視窗。",
        pinNowButton: "置頂目前的視窗",
        unpinAllButton: "全部取消置頂",
        pinnedCountFormat: "已置頂的視窗：%d",
        pinnedNone: "沒有已置頂的視窗",
        unsupportedTitle: "視窗置頂正在等待「輔助使用」權限",
        unsupportedCaption: "授予「輔助使用」權限，讓 Vorssaint 可以找到目前的視窗，並將已置頂的視窗保持在最前。",
        permissionRowTitle: "權限",
        permissionRowCaption: "「輔助使用」尋找目前的視窗。「螢幕錄製」繪製即時複製畫面，讓它保持在最前。",
        allSpacesToggle: "在所有桌面上顯示已置頂的視窗",
        allSpacesCaption: "克隆會跟著你到每個桌面。在那裡它只是即時畫面：按一下即可回到原視窗。Chrome 等部分 App 會停止繪製位於其他桌面的視窗，因此克隆可能會停住或變黑。"
    )

    static let uk = WindowPinningStrings(
        pageTitle: "Закріплення вікон",
        featureCaption: "Тримає закріплені вами вікна поверх усіх інших.",
        enableToggle: "Закріплювати вікна поверх",
        enableCaption: "Показує живу копію вікна у фокусі, яка лишається поверх усього іншого. «Доступність» знаходить вікно, а «Запис екрана» малює копію.",
        shortcutSection: "Комбінація клавіш",
        shortcutCaption: "Натисніть її, щоб закріпити або відкріпити вікно, яке зараз у фокусі.",
        pinNowButton: "Закріпити активне вікно",
        unpinAllButton: "Відкріпити все",
        pinnedCountFormat: "Закріплених вікон: %d",
        pinnedNone: "Немає закріплених вікон",
        unsupportedTitle: "Закріплення вікон чекає на «Доступність»",
        unsupportedCaption: "Надайте дозвіл «Доступність», щоб Vorssaint міг знаходити активне вікно та тримати закріплені вікна поверх інших.",
        permissionRowTitle: "Дозволи",
        permissionRowCaption: "«Доступність» знаходить вікно у фокусі. «Запис екрана» малює живу копію, що лишається поверх.",
        allSpacesToggle: "Показувати закріплені вікна на всіх Space",
        allSpacesCaption: "Клон іде за вами на кожен Space. Там він лише показує вікно: натисніть на нього, щоб повернутися до вікна. Деякі програми, як-от Chrome, перестають малювати вікно на іншому Space, тому клон може застигнути або стати чорним."
    )
}
