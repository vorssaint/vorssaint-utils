// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

struct MenuBarOrganizerFeatureStrings {
    let title: String
    let hubDescription: String
    let enable: String
    let enableCaption: String
    /// One `%@`: the macOS version this Mac runs.
    let unsupportedOSFormat: String
    let unsupportedAPI: String
    /// One `%@`: the name of the other menu bar manager.
    let otherManagerFormat: String
    let icon: String
    let iconChevron: String
    let iconDots: String
    let iconLines: String
    let iconGrid: String
    /// Where the hidden icons show: back in the bar or in the shelf.
    let reveal: String
    let revealMenuBar: String
    let revealShelf: String
    let revealMenuBarCaption: String
    let revealShelfCaption: String
    let shelfMonochrome: String
    let shelfEmpty: String
    let showSection: String
    let showCaption: String
    let showEmpty: String
    let hideSection: String
    let hideCaption: String
    let hideEmpty: String
    let neverSection: String
    let neverCaption: String
    let neverEmpty: String
    /// The tier names as the row menu offers them.
    let tierShow: String
    let tierHide: String
    let tierNever: String
    let lockedSystem: String
    /// The clock and Control Center, which macOS does not let anyone move.
    let lockedPinned: String
    let lockedOwn: String
    let lockedHelper: String
    /// A note, not a lock: the row still moves between the tiers.
    let lockedUnsigned: String
    /// The system items as the editor rows name them.
    let systemBattery: String
    let systemBluetooth: String
    let systemClock: String
    let systemDisplays: String
    let systemKeyboard: String
    let systemSound: String
    let systemWiFi: String
    let systemScreenMirroring: String
    let systemControlCenter: String
    let applying: String
    /// `%1$d` moved, `%2$d` failed.
    let applyReportFormat: String
    let behaviorNoteTitle: String
    let mouseHint: String
    let dragHint: String
    let perAppNote: String
    let systemExtrasNote: String
    let autoRehide: String
    let autoRehideNever: String
    /// One `%d`: seconds.
    let autoRehideSecondsFormat: String
    let showHiddenIcons: String
    let hideIcons: String
    let statusCollapsed: String
    let statusExpanded: String
    let refresh: String
    let problemAccessibility: String
    let problemCollapserNotFound: String
    /// One `%@`: the underlying error.
    let problemActivationFormat: String
    let problemNothingToHide: String
    /// One `%@`: the name of the item the shelf could not open.
    let problemPeekFailedFormat: String
}

extension FeatureStrings {
    static func menuBarOrganizer(_ language: AppLanguage) -> MenuBarOrganizerFeatureStrings {
        switch language {
        case .enUS: return .enUS
        case .ptBR: return .ptBR
        case .tr: return .tr
        case .ru: return .ru
        case .es: return .es
        case .sk: return .sk
        case .de: return .de
        case .fr: return .fr
        case .it: return .it
        case .ja: return .ja
        case .ko: return .ko
        case .uk: return .uk
        case .zhHans: return .zhHans
        case .zhTW: return .zhTW
        case .zhHK: return .zhHK
        case .ar: return .ar
        }
    }
}

extension MenuBarOrganizerFeatureStrings {
    static let enUS = MenuBarOrganizerFeatureStrings(
        title: "Menu Bar Organizer", hubDescription: "Hide menu bar icons behind a collapse icon, keep others out of the bar for good, reorder them from Settings and bring the hidden ones back with one click, in the bar or in a shelf. macOS 27 or later.",
        enable: "Hide menu bar icons", enableCaption: "Icons left of the collapse icon hide. Click it to show them.",
        unsupportedOSFormat: "Menu Bar Organizer needs macOS 27 or later. This Mac runs macOS %@.", unsupportedAPI: "This macOS build does not expose the menu bar controls Menu Bar Organizer relies on.",
        otherManagerFormat: "%@ is running. Two menu bar managers hiding icons at once interfere; quit it first.",
        icon: "Icon", iconChevron: "Chevron", iconDots: "Dots", iconLines: "Lines", iconGrid: "Grid",
        reveal: "Show hidden icons", revealMenuBar: "In the menu bar", revealShelf: "In a shelf",
        revealMenuBarCaption: "A click on the collapse icon puts the hidden icons back into the bar.", revealShelfCaption: "A click on the collapse icon drops a shelf with the hidden icons. The bar stays as it is; click an icon in the shelf to open its menu.",
        shelfMonochrome: "Monochrome shelf icons", shelfEmpty: "Nothing is hidden.",
        showSection: "Show always", showCaption: "Right of the collapse icon. Always in the bar.", showEmpty: "Nothing is shown always.",
        hideSection: "Hide", hideCaption: "Left of the collapse icon. Hidden until you click it, hidden again when you click again.", hideEmpty: "Drop icons here, or ⌘-drag them left of the collapse icon in the bar.",
        neverSection: "Never show", neverCaption: "Not in the bar at all, not even while the hidden icons are shown. Applies to every icon of that app.", neverEmpty: "Nothing is hidden for good.",
        tierShow: "Show always", tierHide: "Hide", tierNever: "Never show",
        lockedSystem: "Managed by macOS", lockedPinned: "macOS keeps this at the end of the bar.", lockedOwn: "Vorssaint’s own icon stays visible", lockedHelper: "Drawn by a helper process macOS cannot hide", lockedUnsigned: "Not signed with an Apple-issued certificate: macOS hides it whenever any icon is hidden.",
        systemBattery: "Battery", systemBluetooth: "Bluetooth", systemClock: "Clock", systemDisplays: "Displays", systemKeyboard: "Input menu", systemSound: "Sound", systemWiFi: "Wi-Fi", systemScreenMirroring: "Screen Mirroring", systemControlCenter: "Control Center",
        applying: "Moving icons…", applyReportFormat: "%1$d moved, %2$d failed",
        behaviorNoteTitle: "Menu bar tips",
        mouseHint: "Keep the mouse still while icons move.", dragHint: "You can also ⌘-drag icons in the menu bar.",
        perAppNote: "Icons from the same app hide together.", systemExtrasNote: "Focus and some system extras hide while collapsed. Expand to restore them. Some locally built tools may hide too.",
        autoRehide: "Hide again automatically", autoRehideNever: "Never", autoRehideSecondsFormat: "After %d s", showHiddenIcons: "Show hidden icons", hideIcons: "Hide icons",
        statusCollapsed: "Icons are hidden", statusExpanded: "Icons are shown", refresh: "Refresh",
        problemAccessibility: "Accessibility is required to read the menu bar.", problemCollapserNotFound: "The collapse icon is not in the menu bar. Hiding is paused.",
        problemActivationFormat: "Hiding failed: %@", problemNothingToHide: "Nothing is left of the collapse icon, so nothing was hidden.",
        problemPeekFailedFormat: "%@ did not open from the shelf. Its icon is back in the bar; click it there.")
    static let ptBR = MenuBarOrganizerFeatureStrings(
        title: "Organizador da barra de menus", hubDescription: "Esconda ícones da barra de menus atrás de um ícone de recolher, mantenha outros sempre fora da barra, reordene-os nos Ajustes e traga os ocultos de volta com um clique, na barra ou em um painel. macOS 27 ou posterior.",
        enable: "Ocultar ícones da barra de menus", enableCaption: "Os ícones à esquerda do ícone de recolher ficam ocultos. Clique nele para mostrá-los.",
        unsupportedOSFormat: "O Organizador da barra de menus requer o macOS 27 ou posterior. Este Mac usa o macOS %@.", unsupportedAPI: "Esta versão do macOS não oferece os controles da barra de menus de que o Organizador da barra de menus depende.",
        otherManagerFormat: "%@ está aberto. Dois gerenciadores de barra de menus ocultando ícones ao mesmo tempo atrapalham um ao outro; encerre-o primeiro.",
        icon: "Ícone", iconChevron: "Seta", iconDots: "Pontos", iconLines: "Linhas", iconGrid: "Grade",
        reveal: "Mostrar ícones ocultos", revealMenuBar: "Na barra de menus", revealShelf: "Em um painel",
        revealMenuBarCaption: "Um clique no ícone de recolher devolve os ícones ocultos à barra.", revealShelfCaption: "Um clique no ícone de recolher abre um painel com os ícones ocultos. A barra fica como está; clique em um ícone do painel para abrir o menu dele.",
        shelfMonochrome: "Ícones do painel em monocromático", shelfEmpty: "Nada está oculto.",
        showSection: "Mostrar sempre", showCaption: "À direita do ícone de recolher. Sempre na barra.", showEmpty: "Nada é mostrado sempre.",
        hideSection: "Ocultar", hideCaption: "À esquerda do ícone de recolher. Ocultos até você clicar nele, ocultos de novo quando você clica outra vez.", hideEmpty: "Solte ícones aqui ou arraste-os com ⌘ para a esquerda do ícone de recolher na barra.",
        neverSection: "Nunca mostrar", neverCaption: "Fora da barra, mesmo enquanto os ícones ocultos são mostrados. Vale para todos os ícones do app.", neverEmpty: "Nada está oculto de forma permanente.",
        tierShow: "Mostrar sempre", tierHide: "Ocultar", tierNever: "Nunca mostrar",
        lockedSystem: "Gerenciado pelo macOS", lockedPinned: "O macOS mantém este item no fim da barra.", lockedOwn: "O ícone do Vorssaint fica sempre visível", lockedHelper: "Desenhado por um processo auxiliar que o macOS não consegue ocultar", lockedUnsigned: "Não assinado com um certificado emitido pela Apple: o macOS o oculta sempre que algum ícone está oculto.",
        systemBattery: "Bateria", systemBluetooth: "Bluetooth", systemClock: "Relógio", systemDisplays: "Telas", systemKeyboard: "Menu de entrada", systemSound: "Som", systemWiFi: "Wi-Fi", systemScreenMirroring: "Espelhamento de Tela", systemControlCenter: "Central de Controle",
        applying: "Movendo ícones…", applyReportFormat: "Movidos: %1$d, com falha: %2$d",
        behaviorNoteTitle: "Dicas da barra de menus",
        mouseHint: "Mantenha o mouse parado enquanto os ícones se movem.", dragHint: "Você também pode arrastar ícones na barra de menus com ⌘.",
        perAppNote: "Ícones do mesmo app são ocultados juntos.", systemExtrasNote: "Foco e alguns itens do sistema somem ao recolher. Expanda para restaurá-los. Algumas ferramentas compiladas localmente também podem sumir.",
        autoRehide: "Ocultar de novo automaticamente", autoRehideNever: "Nunca", autoRehideSecondsFormat: "Após %d s", showHiddenIcons: "Mostrar ícones ocultos", hideIcons: "Ocultar ícones",
        statusCollapsed: "Os ícones estão ocultos", statusExpanded: "Os ícones estão visíveis", refresh: "Atualizar",
        problemAccessibility: "É preciso Acessibilidade para ler a barra de menus.", problemCollapserNotFound: "O ícone de recolher não está na barra de menus. A ocultação está em pausa.",
        problemActivationFormat: "Falha ao ocultar: %@", problemNothingToHide: "Não há nada à esquerda do ícone de recolher, então nada foi ocultado.",
        problemPeekFailedFormat: "%@ não abriu pelo painel. O ícone voltou para a barra; clique nele lá.")
    static let tr = MenuBarOrganizerFeatureStrings(
        title: "Menü Çubuğu Düzenleyici", hubDescription: "Menü çubuğu simgelerini bir daraltma simgesinin arkasına gizleyin, bazılarını çubuktan tamamen çıkarın, Ayarlar’dan yeniden sıralayın ve gizlenenleri tek tıklamayla çubuğa ya da bir panele geri getirin. macOS 27 veya sonrası.",
        enable: "Menü çubuğu simgelerini gizle", enableCaption: "Daraltma simgesinin solundaki simgeler gizlenir. Göstermek için simgeye tıklayın.",
        unsupportedOSFormat: "Menü Çubuğu Düzenleyici için macOS 27 veya sonrası gerekir. Bu Mac’te macOS %@ yüklü.", unsupportedAPI: "Bu macOS sürümü, Menü Çubuğu Düzenleyici’nin ihtiyaç duyduğu menü çubuğu denetimlerini sunmuyor.",
        otherManagerFormat: "%@ çalışıyor. Aynı anda simge gizleyen iki menü çubuğu yöneticisi birbirini bozar; önce onu kapatın.",
        icon: "Simge", iconChevron: "Ok", iconDots: "Noktalar", iconLines: "Çizgiler", iconGrid: "Izgara",
        reveal: "Gizli simgeleri göster", revealMenuBar: "Menü çubuğunda", revealShelf: "Açılır panelde",
        revealMenuBarCaption: "Daraltma simgesine tıklamak gizli simgeleri çubuğa geri getirir.", revealShelfCaption: "Daraltma simgesine tıklamak gizli simgeleri içeren bir panel açar. Çubuk olduğu gibi kalır; menüsünü açmak için paneldeki bir simgeye tıklayın.",
        shelfMonochrome: "Panelde tek renkli simgeler", shelfEmpty: "Gizli bir şey yok.",
        showSection: "Her zaman göster", showCaption: "Daraltma simgesinin sağında. Her zaman çubukta.", showEmpty: "Her zaman gösterilen simge yok.",
        hideSection: "Gizle", hideCaption: "Daraltma simgesinin solunda. Simgeye tıklayana kadar gizli kalır, yeniden tıkladığınızda tekrar gizlenir.", hideEmpty: "Simgeleri buraya bırakın veya çubukta ⌘ ile daraltma simgesinin soluna sürükleyin.",
        neverSection: "Asla gösterme", neverCaption: "Çubukta hiç yer almaz, gizli simgeler gösterilirken bile. Uygulamanın tüm simgeleri için geçerlidir.", neverEmpty: "Kalıcı olarak gizlenen simge yok.",
        tierShow: "Her zaman göster", tierHide: "Gizle", tierNever: "Asla gösterme",
        lockedSystem: "macOS tarafından yönetiliyor", lockedPinned: "macOS bunu çubuğun sonunda tutar.", lockedOwn: "Vorssaint’in kendi simgesi hep görünür kalır", lockedHelper: "macOS’in gizleyemediği bir yardımcı işlem tarafından çiziliyor", lockedUnsigned: "Apple’ın verdiği bir sertifikayla imzalanmamış: herhangi bir simge gizliyken macOS bunu da gizler.",
        systemBattery: "Pil", systemBluetooth: "Bluetooth", systemClock: "Saat", systemDisplays: "Ekranlar", systemKeyboard: "Giriş menüsü", systemSound: "Ses", systemWiFi: "Wi-Fi", systemScreenMirroring: "Ekran Yansıtma", systemControlCenter: "Denetim Merkezi",
        applying: "Simgeler taşınıyor…", applyReportFormat: "%1$d taşındı, %2$d başarısız",
        behaviorNoteTitle: "Menü çubuğu ipuçları",
        mouseHint: "Simgeler taşınırken fareyi sabit tutun.", dragHint: "Menü çubuğundaki simgeleri ⌘ ile de sürükleyebilirsiniz.",
        perAppNote: "Aynı uygulamanın simgeleri birlikte gizlenir.", systemExtrasNote: "Daraltıldığında Odak ve bazı sistem öğeleri de gizlenir. Geri getirmek için genişletin. Yerel derlenen bazı araçlar da gizlenebilir.",
        autoRehide: "Otomatik olarak yeniden gizle", autoRehideNever: "Asla", autoRehideSecondsFormat: "%d sn sonra", showHiddenIcons: "Gizli simgeleri göster", hideIcons: "Simgeleri gizle",
        statusCollapsed: "Simgeler gizli", statusExpanded: "Simgeler görünür", refresh: "Yenile",
        problemAccessibility: "Menü çubuğunu okumak için Erişilebilirlik izni gerekir.", problemCollapserNotFound: "Daraltma simgesi menü çubuğunda değil. Gizleme duraklatıldı.",
        problemActivationFormat: "Gizleme başarısız: %@", problemNothingToHide: "Daraltma simgesinin solunda hiçbir şey olmadığı için hiçbir şey gizlenmedi.",
        problemPeekFailedFormat: "%@ panelden açılamadı. Simgesi çubuğa geri döndü; oradan tıklayın.")
    static let ru = MenuBarOrganizerFeatureStrings(
        title: "Органайзер строки меню", hubDescription: "Прячьте значки строки меню за значком сворачивания, убирайте лишние из строки насовсем, меняйте порядок в настройках и возвращайте скрытые одним нажатием в строку или в выпадающую панель. macOS 27 или новее.",
        enable: "Скрывать значки строки меню", enableCaption: "Значки слева от значка сворачивания скрываются. Нажмите его, чтобы показать их.",
        unsupportedOSFormat: "Органайзеру строки меню нужна macOS 27 или новее. На этом Mac установлена macOS %@.", unsupportedAPI: "Эта сборка macOS не предоставляет элементы управления строкой меню, на которые опирается Органайзер строки меню.",
        otherManagerFormat: "Запущено приложение %@. Два менеджера строки меню, скрывающие значки одновременно, мешают друг другу; сначала закройте его.",
        icon: "Значок", iconChevron: "Стрелка", iconDots: "Точки", iconLines: "Линии", iconGrid: "Сетка",
        reveal: "Показывать скрытые значки", revealMenuBar: "В строке меню", revealShelf: "В выпадающей панели",
        revealMenuBarCaption: "Нажатие на значок сворачивания возвращает скрытые значки в строку.", revealShelfCaption: "Нажатие на значок сворачивания открывает панель со скрытыми значками. Строка остаётся как есть; нажмите значок в панели, чтобы открыть его меню.",
        shelfMonochrome: "Монохромные значки в панели", shelfEmpty: "Ничего не скрыто.",
        showSection: "Показывать всегда", showCaption: "Справа от значка сворачивания. Всегда в строке меню.", showEmpty: "Нет значков, которые показываются всегда.",
        hideSection: "Скрывать", hideCaption: "Слева от значка сворачивания. Скрыты, пока вы не нажмёте его, и снова скрываются при повторном нажатии.", hideEmpty: "Перетащите значки сюда или, удерживая ⌘, перетащите их в строке меню левее значка сворачивания.",
        neverSection: "Никогда не показывать", neverCaption: "Их нет в строке меню совсем, даже когда показаны скрытые значки. Действует на все значки приложения.", neverEmpty: "Нет значков, скрытых насовсем.",
        tierShow: "Показывать всегда", tierHide: "Скрывать", tierNever: "Никогда не показывать",
        lockedSystem: "Управляется macOS", lockedPinned: "macOS держит этот элемент в конце строки меню.", lockedOwn: "Значок Vorssaint всегда остаётся на виду", lockedHelper: "Рисуется вспомогательным процессом, который macOS не может скрыть", lockedUnsigned: "Не подписано сертификатом, выданным Apple: macOS скрывает его всякий раз, когда скрыт любой значок.",
        systemBattery: "Аккумулятор", systemBluetooth: "Bluetooth", systemClock: "Часы", systemDisplays: "Дисплеи", systemKeyboard: "Меню ввода", systemSound: "Звук", systemWiFi: "Wi-Fi", systemScreenMirroring: "Повтор экрана", systemControlCenter: "Пункт управления",
        applying: "Перемещение значков…", applyReportFormat: "Перемещено: %1$d, не удалось: %2$d",
        behaviorNoteTitle: "Подсказки для строки меню",
        mouseHint: "Не двигайте мышь, пока значки перемещаются.", dragHint: "Значки в строке меню можно перетаскивать с ⌘.",
        perAppNote: "Значки одного приложения скрываются вместе.", systemExtrasNote: "При сворачивании скрываются Фокусирование и некоторые системные элементы. Разверните, чтобы вернуть их. Некоторые локальные сборки тоже могут скрыться.",
        autoRehide: "Скрывать снова автоматически", autoRehideNever: "Никогда", autoRehideSecondsFormat: "Через %d с", showHiddenIcons: "Показать скрытые значки", hideIcons: "Скрыть значки",
        statusCollapsed: "Значки скрыты", statusExpanded: "Значки показаны", refresh: "Обновить",
        problemAccessibility: "Чтобы читать строку меню, нужен Универсальный доступ.", problemCollapserNotFound: "Значка сворачивания нет в строке меню. Скрытие приостановлено.",
        problemActivationFormat: "Не удалось скрыть: %@", problemNothingToHide: "Слева от значка сворачивания ничего нет, поэтому ничего не скрыто.",
        problemPeekFailedFormat: "Не удалось открыть %@ из панели. Значок снова в строке меню; нажмите его там.")
    static let es = MenuBarOrganizerFeatureStrings(
        title: "Organizador de la barra de menús", hubDescription: "Oculta iconos de la barra de menús tras un icono de contraer, deja otros fuera de la barra para siempre, reordénalos desde Ajustes y recupera los ocultos con un clic, en la barra o en un panel desplegable. macOS 27 o posterior.",
        enable: "Ocultar iconos de la barra de menús", enableCaption: "Los iconos a la izquierda del icono de contraer se ocultan. Haz clic en él para mostrarlos.",
        unsupportedOSFormat: "El Organizador de la barra de menús necesita macOS 27 o posterior. Este Mac usa macOS %@.", unsupportedAPI: "Esta versión de macOS no ofrece los controles de la barra de menús de los que depende el Organizador de la barra de menús.",
        otherManagerFormat: "%@ está abierto. Dos gestores de la barra de menús ocultando iconos a la vez se estorban; ciérralo primero.",
        icon: "Icono", iconChevron: "Flecha", iconDots: "Puntos", iconLines: "Líneas", iconGrid: "Cuadrícula",
        reveal: "Mostrar iconos ocultos", revealMenuBar: "En la barra de menús", revealShelf: "En un panel desplegable",
        revealMenuBarCaption: "Un clic en el icono de contraer devuelve los iconos ocultos a la barra.", revealShelfCaption: "Un clic en el icono de contraer despliega un panel con los iconos ocultos. La barra se queda como está; haz clic en un icono del panel para abrir su menú.",
        shelfMonochrome: "Iconos del panel en monocromo", shelfEmpty: "No hay nada oculto.",
        showSection: "Mostrar siempre", showCaption: "A la derecha del icono de contraer. Siempre en la barra.", showEmpty: "No hay nada que se muestre siempre.",
        hideSection: "Ocultar", hideCaption: "A la izquierda del icono de contraer. Ocultos hasta que haces clic en él, y ocultos de nuevo cuando vuelves a hacer clic.", hideEmpty: "Suelta iconos aquí o arrástralos con ⌘ a la izquierda del icono de contraer en la barra.",
        neverSection: "No mostrar nunca", neverCaption: "Fuera de la barra por completo, incluso mientras se muestran los iconos ocultos. Se aplica a todos los iconos de la app.", neverEmpty: "No hay nada oculto para siempre.",
        tierShow: "Mostrar siempre", tierHide: "Ocultar", tierNever: "No mostrar nunca",
        lockedSystem: "Gestionado por macOS", lockedPinned: "macOS lo mantiene al final de la barra.", lockedOwn: "El icono de Vorssaint siempre queda visible", lockedHelper: "Lo dibuja un proceso auxiliar que macOS no puede ocultar", lockedUnsigned: "No está firmado con un certificado emitido por Apple: macOS lo oculta siempre que haya algún icono oculto.",
        systemBattery: "Batería", systemBluetooth: "Bluetooth", systemClock: "Reloj", systemDisplays: "Pantallas", systemKeyboard: "Menú de teclado", systemSound: "Sonido", systemWiFi: "Wi-Fi", systemScreenMirroring: "Duplicar pantalla", systemControlCenter: "Centro de control",
        applying: "Moviendo iconos…", applyReportFormat: "Movidos: %1$d, fallidos: %2$d",
        behaviorNoteTitle: "Consejos para la barra de menús",
        mouseHint: "No muevas el ratón mientras se mueven los iconos.", dragHint: "También puedes arrastrar iconos en la barra de menús con ⌘.",
        perAppNote: "Los iconos de una misma app se ocultan juntos.", systemExtrasNote: "Concentración y algunos elementos del sistema se ocultan al contraer. Expande para restaurarlos. Algunas herramientas compiladas localmente también pueden ocultarse.",
        autoRehide: "Volver a ocultar automáticamente", autoRehideNever: "Nunca", autoRehideSecondsFormat: "Tras %d s", showHiddenIcons: "Mostrar iconos ocultos", hideIcons: "Ocultar iconos",
        statusCollapsed: "Los iconos están ocultos", statusExpanded: "Los iconos están visibles", refresh: "Actualizar",
        problemAccessibility: "Se necesita Accesibilidad para leer la barra de menús.", problemCollapserNotFound: "El icono de contraer no está en la barra de menús. La ocultación está en pausa.",
        problemActivationFormat: "No se pudo ocultar: %@", problemNothingToHide: "No hay nada a la izquierda del icono de contraer, así que no se ocultó nada.",
        problemPeekFailedFormat: "%@ no se abrió desde el panel. Su icono ha vuelto a la barra; haz clic en él allí.")
    static let sk = MenuBarOrganizerFeatureStrings(
        title: "Organizér lišty", hubDescription: "Skryte ikony v lište za ikonu zbalenia, iné z lišty odstráňte natrvalo, zmeňte ich poradie v Nastaveniach a skryté jedným kliknutím vráťte späť do lišty alebo do panela. macOS 27 alebo novší.",
        enable: "Skrývať ikony v lište", enableCaption: "Ikony naľavo od ikony zbalenia sa skryjú. Kliknutím na ňu ich zobrazíte.",
        unsupportedOSFormat: "Organizér lišty vyžaduje macOS 27 alebo novší. Na tomto Macu beží macOS %@.", unsupportedAPI: "Táto verzia macOS neposkytuje ovládanie lišty, ktoré Organizér lišty potrebuje.",
        otherManagerFormat: "Beží aplikácia %@. Dvaja správcovia lišty, ktorí skrývajú ikony naraz, si prekážajú; najprv ju ukončite.",
        icon: "Ikona", iconChevron: "Šípka", iconDots: "Bodky", iconLines: "Čiary", iconGrid: "Mriežka",
        reveal: "Zobraziť skryté ikony", revealMenuBar: "V lište", revealShelf: "V rozbaľovacom paneli",
        revealMenuBarCaption: "Kliknutím na ikonu zbalenia sa skryté ikony vrátia do lišty.", revealShelfCaption: "Kliknutím na ikonu zbalenia sa otvorí panel so skrytými ikonami. Lišta zostane, ako je; kliknutím na ikonu v paneli otvoríte jej menu.",
        shelfMonochrome: "Jednofarebné ikony v paneli", shelfEmpty: "Nič nie je skryté.",
        showSection: "Vždy zobraziť", showCaption: "Napravo od ikony zbalenia. Vždy v lište.", showEmpty: "Nič sa nezobrazuje vždy.",
        hideSection: "Skryť", hideCaption: "Naľavo od ikony zbalenia. Skryté, kým na ňu nekliknete, a po ďalšom kliknutí znova skryté.", hideEmpty: "Pustite ikony sem alebo ich v lište s podržaným ⌘ potiahnite naľavo od ikony zbalenia.",
        neverSection: "Nikdy nezobraziť", neverCaption: "V lište vôbec nie sú, ani keď sú skryté ikony zobrazené. Platí pre všetky ikony danej aplikácie.", neverEmpty: "Nič nie je skryté natrvalo.",
        tierShow: "Vždy zobraziť", tierHide: "Skryť", tierNever: "Nikdy nezobraziť",
        lockedSystem: "Spravuje macOS", lockedPinned: "macOS ju drží na konci lišty.", lockedOwn: "Vlastná ikona Vorssaintu zostáva viditeľná", lockedHelper: "Kreslí ju pomocný proces, ktorý macOS nedokáže skryť", lockedUnsigned: "Nie je podpísaná certifikátom vydaným spoločnosťou Apple: macOS ju skryje vždy, keď je skrytá akákoľvek ikona.",
        systemBattery: "Batéria", systemBluetooth: "Bluetooth", systemClock: "Hodiny", systemDisplays: "Displeje", systemKeyboard: "Menu vstupu", systemSound: "Zvuk", systemWiFi: "Wi-Fi", systemScreenMirroring: "Zrkadlenie obrazovky", systemControlCenter: "Ovládacie centrum",
        applying: "Presúvajú sa ikony…", applyReportFormat: "Presunuté: %1$d, zlyhalo: %2$d",
        behaviorNoteTitle: "Tipy pre lištu",
        mouseHint: "Počas presúvania ikon nehýbte myšou.", dragHint: "Ikony v lište môžete ťahať aj s podržaným ⌘.",
        perAppNote: "Ikony rovnakej aplikácie sa skryjú spolu.", systemExtrasNote: "Pri zbalení sa skryje aj Môj čas a niektoré systémové položky. Rozbaľte lištu a obnovia sa. Skryť sa môžu aj niektoré lokálne zostavené nástroje.",
        autoRehide: "Znova skryť automaticky", autoRehideNever: "Nikdy", autoRehideSecondsFormat: "Po %d s", showHiddenIcons: "Zobraziť skryté ikony", hideIcons: "Skryť ikony",
        statusCollapsed: "Ikony sú skryté", statusExpanded: "Ikony sú zobrazené", refresh: "Obnoviť",
        problemAccessibility: "Na čítanie lišty je potrebná Prístupnosť.", problemCollapserNotFound: "Ikona zbalenia nie je v lište. Skrývanie je pozastavené.",
        problemActivationFormat: "Skrytie zlyhalo: %@", problemNothingToHide: "Naľavo od ikony zbalenia nič nie je, takže sa nič neskrylo.",
        problemPeekFailedFormat: "Položku %@ sa z panela nepodarilo otvoriť. Jej ikona je opäť v lište; kliknite na ňu tam.")
    static let de = MenuBarOrganizerFeatureStrings(
        title: "Menüleisten-Organizer", hubDescription: "Verstecke Menüleistensymbole hinter einem Einklappsymbol, halte andere dauerhaft aus der Leiste heraus, ordne sie in den Einstellungen neu an und hole die ausgeblendeten mit einem Klick zurück, in die Leiste oder in ein Aufklappfeld. macOS 27 oder neuer.",
        enable: "Menüleistensymbole ausblenden", enableCaption: "Symbole links vom Einklappsymbol werden ausgeblendet. Klicke darauf, um sie einzublenden.",
        unsupportedOSFormat: "Der Menüleisten-Organizer benötigt macOS 27 oder neuer. Auf diesem Mac läuft macOS %@.", unsupportedAPI: "Diese macOS-Version stellt die Menüleisten-Steuerung nicht bereit, auf die der Menüleisten-Organizer angewiesen ist.",
        otherManagerFormat: "%@ läuft gerade. Zwei Menüleisten-Manager, die gleichzeitig Symbole ausblenden, stören sich gegenseitig; beende die App zuerst.",
        icon: "Symbol", iconChevron: "Pfeil", iconDots: "Punkte", iconLines: "Linien", iconGrid: "Raster",
        reveal: "Ausgeblendete Symbole zeigen", revealMenuBar: "In der Menüleiste", revealShelf: "In einem Aufklappfeld",
        revealMenuBarCaption: "Ein Klick auf das Einklappsymbol holt die ausgeblendeten Symbole zurück in die Leiste.", revealShelfCaption: "Ein Klick auf das Einklappsymbol klappt ein Feld mit den ausgeblendeten Symbolen auf. Die Leiste bleibt, wie sie ist; klicke auf ein Symbol im Feld, um sein Menü zu öffnen.",
        shelfMonochrome: "Symbole im Aufklappfeld einfarbig", shelfEmpty: "Nichts ist ausgeblendet.",
        showSection: "Immer anzeigen", showCaption: "Rechts vom Einklappsymbol. Immer in der Leiste.", showEmpty: "Nichts wird immer angezeigt.",
        hideSection: "Ausblenden", hideCaption: "Links vom Einklappsymbol. Ausgeblendet, bis du darauf klickst, und beim nächsten Klick wieder ausgeblendet.", hideEmpty: "Lege Symbole hier ab oder ziehe sie in der Leiste mit ⌘ links neben das Einklappsymbol.",
        neverSection: "Nie anzeigen", neverCaption: "Gar nicht in der Leiste, auch nicht, während die ausgeblendeten Symbole eingeblendet sind. Gilt für alle Symbole der App.", neverEmpty: "Nichts ist dauerhaft ausgeblendet.",
        tierShow: "Immer anzeigen", tierHide: "Ausblenden", tierNever: "Nie anzeigen",
        lockedSystem: "Von macOS verwaltet", lockedPinned: "macOS hält dieses Symbol am Ende der Leiste.", lockedOwn: "Das eigene Symbol von Vorssaint bleibt sichtbar", lockedHelper: "Wird von einem Hilfsprozess gezeichnet, den macOS nicht ausblenden kann", lockedUnsigned: "Nicht mit einem von Apple ausgestellten Zertifikat signiert: macOS blendet es aus, sobald irgendein Symbol ausgeblendet ist.",
        systemBattery: "Batterie", systemBluetooth: "Bluetooth", systemClock: "Uhr", systemDisplays: "Displays", systemKeyboard: "Eingabemenü", systemSound: "Ton", systemWiFi: "WLAN", systemScreenMirroring: "Bildschirmsynchronisierung", systemControlCenter: "Kontrollzentrum",
        applying: "Symbole werden verschoben…", applyReportFormat: "%1$d verschoben, %2$d fehlgeschlagen",
        behaviorNoteTitle: "Tipps zur Menüleiste",
        mouseHint: "Halte die Maus still, während Symbole verschoben werden.", dragHint: "Du kannst Symbole auch mit ⌘ in der Menüleiste ziehen.",
        perAppNote: "Symbole derselben App werden gemeinsam ausgeblendet.", systemExtrasNote: "Fokus und einige Systemeinträge verschwinden beim Einklappen. Klappe die Leiste auf, um sie zurückzuholen. Manche lokal gebauten Programme können ebenfalls verschwinden.",
        autoRehide: "Automatisch wieder ausblenden", autoRehideNever: "Nie", autoRehideSecondsFormat: "Nach %d s", showHiddenIcons: "Ausgeblendete Symbole einblenden", hideIcons: "Symbole ausblenden",
        statusCollapsed: "Symbole sind ausgeblendet", statusExpanded: "Symbole sind eingeblendet", refresh: "Aktualisieren",
        problemAccessibility: "Zum Lesen der Menüleiste sind die Bedienungshilfen erforderlich.", problemCollapserNotFound: "Das Einklappsymbol ist nicht in der Menüleiste. Das Ausblenden ist pausiert.",
        problemActivationFormat: "Ausblenden fehlgeschlagen: %@", problemNothingToHide: "Links vom Einklappsymbol steht nichts, daher wurde nichts ausgeblendet.",
        problemPeekFailedFormat: "%@ ließ sich nicht aus dem Aufklappfeld öffnen. Das Symbol ist wieder in der Leiste; klicke es dort an.")
    static let fr = MenuBarOrganizerFeatureStrings(
        title: "Organisateur de la barre des menus", hubDescription: "Masquez des icônes de la barre des menus derrière une icône de réduction, retirez-en d’autres de la barre pour de bon, réorganisez-les depuis les réglages et retrouvez les icônes masquées d’un clic, dans la barre ou dans un panneau déroulant. macOS 27 ou ultérieur.",
        enable: "Masquer les icônes de la barre des menus", enableCaption: "Les icônes à gauche de l’icône de réduction sont masquées. Cliquez dessus pour les afficher.",
        unsupportedOSFormat: "L’Organisateur de la barre des menus nécessite macOS 27 ou ultérieur. Ce Mac utilise macOS %@.", unsupportedAPI: "Cette version de macOS ne fournit pas les commandes de la barre des menus dont l’Organisateur de la barre des menus a besoin.",
        otherManagerFormat: "%@ est ouvert. Deux gestionnaires de barre des menus qui masquent des icônes en même temps se gênent\u{00A0}; quittez-le d’abord.",
        icon: "Icône", iconChevron: "Chevron", iconDots: "Points", iconLines: "Lignes", iconGrid: "Grille",
        reveal: "Afficher les icônes masquées", revealMenuBar: "Dans la barre des menus", revealShelf: "Dans un panneau déroulant",
        revealMenuBarCaption: "Un clic sur l’icône de réduction remet les icônes masquées dans la barre.", revealShelfCaption: "Un clic sur l’icône de réduction déroule un panneau avec les icônes masquées. La barre reste telle quelle\u{00A0}; cliquez sur une icône du panneau pour ouvrir son menu.",
        shelfMonochrome: "Icônes du panneau en monochrome", shelfEmpty: "Rien n’est masqué.",
        showSection: "Toujours afficher", showCaption: "À droite de l’icône de réduction. Toujours dans la barre.", showEmpty: "Rien n’est affiché en permanence.",
        hideSection: "Masquer", hideCaption: "À gauche de l’icône de réduction. Masquées jusqu’à ce que vous cliquiez dessus, masquées à nouveau au clic suivant.", hideEmpty: "Déposez des icônes ici, ou faites-les glisser avec ⌘ à gauche de l’icône de réduction dans la barre.",
        neverSection: "Ne jamais afficher", neverCaption: "Absentes de la barre, même lorsque les icônes masquées sont affichées. S’applique à toutes les icônes de l’app.", neverEmpty: "Rien n’est masqué pour de bon.",
        tierShow: "Toujours afficher", tierHide: "Masquer", tierNever: "Ne jamais afficher",
        lockedSystem: "Géré par macOS", lockedPinned: "macOS garde cet élément au bout de la barre.", lockedOwn: "L’icône de Vorssaint reste toujours visible", lockedHelper: "Dessinée par un processus auxiliaire que macOS ne peut pas masquer", lockedUnsigned: "Non signée avec un certificat délivré par Apple\u{00A0}: macOS la masque dès qu’une icône est masquée.",
        systemBattery: "Batterie", systemBluetooth: "Bluetooth", systemClock: "Horloge", systemDisplays: "Moniteurs", systemKeyboard: "Menu de saisie", systemSound: "Son", systemWiFi: "Wi-Fi", systemScreenMirroring: "Recopie de l’écran", systemControlCenter: "Centre de contrôle",
        applying: "Déplacement des icônes…", applyReportFormat: "Déplacées\u{00A0}: %1$d, échecs\u{00A0}: %2$d",
        behaviorNoteTitle: "Conseils pour la barre des menus",
        mouseHint: "Ne bougez pas la souris pendant le déplacement des icônes.", dragHint: "Vous pouvez aussi déplacer les icônes dans la barre avec ⌘.",
        perAppNote: "Les icônes d’une même app sont masquées ensemble.", systemExtrasNote: "Concentration et certains éléments système sont masqués lorsque la barre est réduite. Déployez-la pour les retrouver. Certains outils compilés localement peuvent aussi être masqués.",
        autoRehide: "Masquer à nouveau automatiquement", autoRehideNever: "Jamais", autoRehideSecondsFormat: "Après %d s", showHiddenIcons: "Afficher les icônes masquées", hideIcons: "Masquer les icônes",
        statusCollapsed: "Les icônes sont masquées", statusExpanded: "Les icônes sont affichées", refresh: "Actualiser",
        problemAccessibility: "L’Accessibilité est requise pour lire la barre des menus.", problemCollapserNotFound: "L’icône de réduction n’est pas dans la barre des menus. Le masquage est en pause.",
        problemActivationFormat: "Échec du masquage\u{00A0}: %@", problemNothingToHide: "Il n’y a rien à gauche de l’icône de réduction, donc rien n’a été masqué.",
        problemPeekFailedFormat: "%@ ne s’est pas ouvert depuis le panneau. Son icône est de retour dans la barre\u{00A0}; cliquez dessus là-bas.")
    static let it = MenuBarOrganizerFeatureStrings(
        title: "Organizzatore barra dei menu", hubDescription: "Nascondi le icone della barra dei menu dietro un’icona di compressione, tienine altre sempre fuori dalla barra, riordinale dalle Impostazioni e riporta indietro quelle nascoste con un clic, nella barra o in un pannello a discesa. macOS 27 o successivo.",
        enable: "Nascondi le icone della barra dei menu", enableCaption: "Le icone a sinistra dell’icona di compressione vengono nascoste. Fai clic su di essa per mostrarle.",
        unsupportedOSFormat: "Organizzatore barra dei menu richiede macOS 27 o successivo. Questo Mac usa macOS %@.", unsupportedAPI: "Questa versione di macOS non offre i controlli della barra dei menu su cui si basa Organizzatore barra dei menu.",
        otherManagerFormat: "%@ è in esecuzione. Due gestori della barra dei menu che nascondono icone contemporaneamente si ostacolano; chiudilo prima.",
        icon: "Icona", iconChevron: "Freccia", iconDots: "Punti", iconLines: "Linee", iconGrid: "Griglia",
        reveal: "Mostra icone nascoste", revealMenuBar: "Nella barra dei menu", revealShelf: "In un pannello a discesa",
        revealMenuBarCaption: "Un clic sull’icona di compressione riporta le icone nascoste nella barra.", revealShelfCaption: "Un clic sull’icona di compressione apre un pannello con le icone nascoste. La barra resta com’è; fai clic su un’icona del pannello per aprirne il menu.",
        shelfMonochrome: "Icone del pannello in monocromia", shelfEmpty: "Non c’è niente di nascosto.",
        showSection: "Mostra sempre", showCaption: "A destra dell’icona di compressione. Sempre nella barra.", showEmpty: "Niente viene mostrato sempre.",
        hideSection: "Nascondi", hideCaption: "A sinistra dell’icona di compressione. Nascoste finché non ci fai clic, nascoste di nuovo al clic successivo.", hideEmpty: "Rilascia qui le icone, oppure trascinale con ⌘ a sinistra dell’icona di compressione nella barra.",
        neverSection: "Non mostrare mai", neverCaption: "Fuori dalla barra del tutto, anche mentre le icone nascoste sono mostrate. Vale per tutte le icone dell’app.", neverEmpty: "Niente è nascosto per sempre.",
        tierShow: "Mostra sempre", tierHide: "Nascondi", tierNever: "Non mostrare mai",
        lockedSystem: "Gestita da macOS", lockedPinned: "macOS la tiene alla fine della barra.", lockedOwn: "L’icona di Vorssaint resta sempre visibile", lockedHelper: "Disegnata da un processo ausiliario che macOS non può nascondere", lockedUnsigned: "Non firmata con un certificato rilasciato da Apple: macOS la nasconde ogni volta che un’icona è nascosta.",
        systemBattery: "Batteria", systemBluetooth: "Bluetooth", systemClock: "Orologio", systemDisplays: "Schermi", systemKeyboard: "Menu Tastiera", systemSound: "Suono", systemWiFi: "Wi-Fi", systemScreenMirroring: "Duplicazione schermo", systemControlCenter: "Centro di Controllo",
        applying: "Spostamento delle icone…", applyReportFormat: "Spostate: %1$d, non riuscite: %2$d",
        behaviorNoteTitle: "Suggerimenti per la barra dei menu",
        mouseHint: "Non muovere il mouse mentre le icone vengono spostate.", dragHint: "Puoi anche trascinare le icone nella barra dei menu con ⌘.",
        perAppNote: "Le icone della stessa app vengono nascoste insieme.", systemExtrasNote: "Full immersion e alcuni elementi di sistema scompaiono quando la barra è compressa. Espandila per ripristinarli. Anche alcuni strumenti compilati localmente potrebbero scomparire.",
        autoRehide: "Nascondi di nuovo automaticamente", autoRehideNever: "Mai", autoRehideSecondsFormat: "Dopo %d s", showHiddenIcons: "Mostra icone nascoste", hideIcons: "Nascondi icone",
        statusCollapsed: "Le icone sono nascoste", statusExpanded: "Le icone sono visibili", refresh: "Aggiorna",
        problemAccessibility: "Serve Accessibilità per leggere la barra dei menu.", problemCollapserNotFound: "L’icona di compressione non è nella barra dei menu. L’occultamento è in pausa.",
        problemActivationFormat: "Impossibile nascondere: %@", problemNothingToHide: "Non c’è niente a sinistra dell’icona di compressione, quindi non è stato nascosto nulla.",
        problemPeekFailedFormat: "Impossibile aprire %@ dal pannello. La sua icona è tornata nella barra; fai clic lì.")
    static let ja = MenuBarOrganizerFeatureStrings(
        title: "メニューバーオーガナイザー", hubDescription: "メニューバーのアイコンを折りたたみアイコンの後ろに隠し、不要なものはバーから完全に外し、設定から並べ替えて、隠したアイコンをワンクリックでバーやパネルに呼び戻せます。macOS 27以降。",
        enable: "メニューバーのアイコンを隠す", enableCaption: "折りたたみアイコンより左のアイコンが隠れます。クリックすると表示されます。",
        unsupportedOSFormat: "メニューバーオーガナイザーにはmacOS 27以降が必要です。このMacはmacOS %@です。", unsupportedAPI: "このmacOSビルドには、メニューバーオーガナイザーが必要とするメニューバーの制御機能がありません。",
        otherManagerFormat: "%@が実行中です。アイコンを隠すメニューバー管理アプリが2つ同時に動くと干渉します。先に終了してください。",
        icon: "アイコン", iconChevron: "矢印", iconDots: "ドット", iconLines: "ライン", iconGrid: "グリッド",
        reveal: "隠れたアイコンの表示", revealMenuBar: "メニューバー内", revealShelf: "パネル内",
        revealMenuBarCaption: "折りたたみアイコンをクリックすると、隠れたアイコンがバーに戻ります。", revealShelfCaption: "折りたたみアイコンをクリックすると、隠れたアイコンを並べたパネルが開きます。バーはそのままです。パネル内のアイコンをクリックするとそのメニューが開きます。",
        shelfMonochrome: "パネルのアイコンをモノクロにする", shelfEmpty: "隠れているものはありません。",
        showSection: "常に表示", showCaption: "折りたたみアイコンの右側。常にバーに表示されます。", showEmpty: "常に表示するアイコンはありません。",
        hideSection: "隠す", hideCaption: "折りたたみアイコンの左側。クリックするまで隠れ、もう一度クリックすると再び隠れます。", hideEmpty: "ここにアイコンをドロップするか、バーで⌘を押しながら折りたたみアイコンの左へドラッグしてください。",
        neverSection: "表示しない", neverCaption: "隠れたアイコンを表示している間も、バーには一切表示されません。そのアプリのすべてのアイコンに適用されます。", neverEmpty: "完全に非表示のアイコンはありません。",
        tierShow: "常に表示", tierHide: "隠す", tierNever: "表示しない",
        lockedSystem: "macOSが管理", lockedPinned: "macOSがバーの端に固定しています。", lockedOwn: "Vorssaint自身のアイコンは常に表示されます", lockedHelper: "macOSが隠せないヘルパープロセスが描画しています", lockedUnsigned: "Appleが発行した証明書で署名されていません。いずれかのアイコンが隠れている間、macOSはこれも隠します。",
        systemBattery: "バッテリー", systemBluetooth: "Bluetooth", systemClock: "時計", systemDisplays: "ディスプレイ", systemKeyboard: "入力メニュー", systemSound: "サウンド", systemWiFi: "Wi-Fi", systemScreenMirroring: "画面ミラーリング", systemControlCenter: "コントロールセンター",
        applying: "アイコンを移動中…", applyReportFormat: "%1$d 件を移動、%2$d 件が失敗",
        behaviorNoteTitle: "メニューバーのヒント",
        mouseHint: "アイコンの移動中はマウスを動かさないでください。", dragHint: "メニューバーのアイコンは⌘ドラッグでも移動できます。",
        perAppNote: "同じアプリのアイコンはまとめて隠れます。", systemExtrasNote: "折りたたむと集中モードなど一部のシステム項目も隠れます。展開すると戻ります。ローカルでビルドした一部のツールも隠れる場合があります。",
        autoRehide: "自動的に再び隠す", autoRehideNever: "しない", autoRehideSecondsFormat: "%d 秒後", showHiddenIcons: "隠れたアイコンを表示", hideIcons: "アイコンを隠す",
        statusCollapsed: "アイコンは隠れています", statusExpanded: "アイコンは表示されています", refresh: "更新",
        problemAccessibility: "メニューバーを読み取るにはアクセシビリティが必要です。", problemCollapserNotFound: "折りたたみアイコンがメニューバーにありません。非表示は一時停止中です。",
        problemActivationFormat: "隠せませんでした: %@", problemNothingToHide: "折りたたみアイコンの左に何もないため、何も隠されませんでした。",
        problemPeekFailedFormat: "%@ をパネルから開けませんでした。アイコンはバーに戻っています。そこでクリックしてください。")
    static let ko = MenuBarOrganizerFeatureStrings(
        title: "메뉴 막대 정리", hubDescription: "메뉴 막대 아이콘을 접기 아이콘 뒤로 숨기고, 일부는 막대에서 완전히 빼고, 설정에서 순서를 바꾸고, 숨긴 아이콘을 클릭 한 번으로 막대나 패널에 다시 꺼냅니다. macOS 27 이상.",
        enable: "메뉴 막대 아이콘 숨기기", enableCaption: "접기 아이콘 왼쪽의 아이콘이 숨겨집니다. 클릭하면 다시 표시됩니다.",
        unsupportedOSFormat: "메뉴 막대 정리를 사용하려면 macOS 27 이상이 필요합니다. 이 Mac은 macOS %@입니다.", unsupportedAPI: "이 macOS 빌드는 메뉴 막대 정리에 필요한 메뉴 막대 제어 기능을 제공하지 않습니다.",
        otherManagerFormat: "%@이(가) 실행 중입니다. 아이콘을 숨기는 메뉴 막대 관리 앱 두 개가 동시에 실행되면 서로 충돌하니 먼저 종료하세요.",
        icon: "아이콘", iconChevron: "화살표", iconDots: "점", iconLines: "줄", iconGrid: "격자",
        reveal: "숨겨진 아이콘 표시", revealMenuBar: "메뉴 막대에", revealShelf: "드롭다운 패널에",
        revealMenuBarCaption: "접기 아이콘을 클릭하면 숨겨진 아이콘이 막대로 돌아옵니다.", revealShelfCaption: "접기 아이콘을 클릭하면 숨겨진 아이콘이 담긴 패널이 열립니다. 막대는 그대로 유지되며, 패널에서 아이콘을 클릭하면 해당 메뉴가 열립니다.",
        shelfMonochrome: "패널 아이콘을 흑백으로 표시", shelfEmpty: "숨겨진 항목이 없습니다.",
        showSection: "항상 표시", showCaption: "접기 아이콘의 오른쪽. 항상 막대에 표시됩니다.", showEmpty: "항상 표시되는 아이콘이 없습니다.",
        hideSection: "숨기기", hideCaption: "접기 아이콘의 왼쪽. 클릭할 때까지 숨겨지고, 다시 클릭하면 또 숨겨집니다.", hideEmpty: "아이콘을 여기에 놓거나, 막대에서 ⌘을 누른 채 접기 아이콘 왼쪽으로 드래그하세요.",
        neverSection: "표시 안 함", neverCaption: "숨겨진 아이콘이 표시되는 동안에도 막대에 전혀 나타나지 않습니다. 해당 앱의 모든 아이콘에 적용됩니다.", neverEmpty: "완전히 숨긴 아이콘이 없습니다.",
        tierShow: "항상 표시", tierHide: "숨기기", tierNever: "표시 안 함",
        lockedSystem: "macOS에서 관리", lockedPinned: "macOS가 막대 끝에 고정합니다.", lockedOwn: "Vorssaint 자체 아이콘은 항상 표시됩니다", lockedHelper: "macOS가 숨길 수 없는 보조 프로세스가 그립니다", lockedUnsigned: "Apple이 발급한 인증서로 서명되지 않았습니다. 아이콘이 하나라도 숨겨져 있으면 macOS가 이 아이콘도 숨깁니다.",
        systemBattery: "배터리", systemBluetooth: "Bluetooth", systemClock: "시계", systemDisplays: "디스플레이", systemKeyboard: "입력 메뉴", systemSound: "사운드", systemWiFi: "Wi-Fi", systemScreenMirroring: "화면 미러링", systemControlCenter: "제어 센터",
        applying: "아이콘 이동 중…", applyReportFormat: "%1$d개 이동, %2$d개 실패",
        behaviorNoteTitle: "메뉴 막대 도움말",
        mouseHint: "아이콘이 이동하는 동안 마우스를 움직이지 마세요.", dragHint: "메뉴 막대의 아이콘은 ⌘ 드래그로도 옮길 수 있습니다.",
        perAppNote: "같은 앱의 아이콘은 함께 숨겨집니다.", systemExtrasNote: "접으면 집중 모드와 일부 시스템 항목도 숨겨집니다. 펼치면 다시 나타납니다. 로컬에서 빌드한 일부 도구도 숨겨질 수 있습니다.",
        autoRehide: "자동으로 다시 숨기기", autoRehideNever: "안 함", autoRehideSecondsFormat: "%d초 후", showHiddenIcons: "숨겨진 아이콘 표시", hideIcons: "아이콘 숨기기",
        statusCollapsed: "아이콘이 숨겨져 있습니다", statusExpanded: "아이콘이 표시되어 있습니다", refresh: "새로 고침",
        problemAccessibility: "메뉴 막대를 읽으려면 손쉬운 사용 권한이 필요합니다.", problemCollapserNotFound: "접기 아이콘이 메뉴 막대에 없습니다. 숨기기가 일시 중지되었습니다.",
        problemActivationFormat: "숨기지 못했습니다: %@", problemNothingToHide: "접기 아이콘 왼쪽에 아무것도 없어 숨긴 항목이 없습니다.",
        problemPeekFailedFormat: "패널에서 %@을(를) 열지 못했습니다. 아이콘이 막대로 돌아왔으니 그곳에서 클릭하세요.")
    static let uk = MenuBarOrganizerFeatureStrings(
        title: "Органайзер смуги меню", hubDescription: "Ховайте іконки смуги меню за іконкою згортання, прибирайте зайві зі смуги назовсім, змінюйте порядок у параметрах і повертайте приховані одним клацанням на смугу або у випадну панель. macOS 27 або новіша.",
        enable: "Приховувати іконки смуги меню", enableCaption: "Іконки ліворуч від іконки згортання приховуються. Клацніть її, щоб показати їх.",
        unsupportedOSFormat: "Органайзеру смуги меню потрібна macOS 27 або новіша. На цьому Mac інстальовано macOS %@.", unsupportedAPI: "Ця збірка macOS не надає елементів керування смугою меню, на які спирається Органайзер смуги меню.",
        otherManagerFormat: "Запущено програму %@. Два менеджери смуги меню, що одночасно приховують іконки, заважають один одному; спершу закрийте її.",
        icon: "Іконка", iconChevron: "Стрілка", iconDots: "Крапки", iconLines: "Лінії", iconGrid: "Сітка",
        reveal: "Показувати приховані іконки", revealMenuBar: "У смузі меню", revealShelf: "У випадній панелі",
        revealMenuBarCaption: "Клацання іконки згортання повертає приховані іконки на смугу.", revealShelfCaption: "Клацання іконки згортання відкриває панель із прихованими іконками. Смуга лишається як є; клацніть іконку в панелі, щоб відкрити її меню.",
        shelfMonochrome: "Монохромні іконки в панелі", shelfEmpty: "Нічого не приховано.",
        showSection: "Показувати завжди", showCaption: "Праворуч від іконки згортання. Завжди у смузі меню.", showEmpty: "Немає іконок, які показуються завжди.",
        hideSection: "Приховувати", hideCaption: "Ліворуч від іконки згортання. Приховані, доки ви не клацнете її, і знову приховуються після наступного клацання.", hideEmpty: "Перетягніть іконки сюди або, утримуючи ⌘, перетягніть їх у смузі меню ліворуч від іконки згортання.",
        neverSection: "Ніколи не показувати", neverCaption: "Їх немає у смузі меню взагалі, навіть коли приховані іконки показано. Стосується всіх іконок програми.", neverEmpty: "Немає іконок, прихованих назовсім.",
        tierShow: "Показувати завжди", tierHide: "Приховувати", tierNever: "Ніколи не показувати",
        lockedSystem: "Керується macOS", lockedPinned: "macOS тримає цей елемент у кінці смуги меню.", lockedOwn: "Іконка Vorssaint завжди лишається на видноті", lockedHelper: "Малюється допоміжним процесом, який macOS не може приховати", lockedUnsigned: "Не підписано сертифікатом, виданим Apple: macOS приховує його щоразу, коли приховано будь-яку іконку.",
        systemBattery: "Акумулятор", systemBluetooth: "Bluetooth", systemClock: "Годинник", systemDisplays: "Дисплеї", systemKeyboard: "Меню вводу", systemSound: "Звук", systemWiFi: "Wi-Fi", systemScreenMirroring: "Дублювання екрана", systemControlCenter: "Центр керування",
        applying: "Переміщення іконок…", applyReportFormat: "Переміщено: %1$d, не вдалося: %2$d",
        behaviorNoteTitle: "Поради для смуги меню",
        mouseHint: "Не рухайте мишу, поки іконки переміщуються.", dragHint: "Іконки у смузі меню можна перетягувати з ⌘.",
        perAppNote: "Іконки однієї програми приховуються разом.", systemExtrasNote: "Під час згортання приховуються Зосередження та деякі системні елементи. Розгорніть, щоб повернути їх. Деякі локальні збірки теж можуть приховатися.",
        autoRehide: "Автоматично приховувати знову", autoRehideNever: "Ніколи", autoRehideSecondsFormat: "Через %d с", showHiddenIcons: "Показати приховані іконки", hideIcons: "Приховати іконки",
        statusCollapsed: "Іконки приховано", statusExpanded: "Іконки показано", refresh: "Оновити",
        problemAccessibility: "Щоб читати смугу меню, потрібен Універсальний доступ.", problemCollapserNotFound: "Іконки згортання немає у смузі меню. Приховування призупинено.",
        problemActivationFormat: "Не вдалося приховати: %@", problemNothingToHide: "Ліворуч від іконки згортання нічого немає, тож нічого не приховано.",
        problemPeekFailedFormat: "Не вдалося відкрити %@ з панелі. Іконка знову на смузі; клацніть її там.")
    static let zhHans = MenuBarOrganizerFeatureStrings(
        title: "菜单栏整理器", hubDescription: "把菜单栏图标藏到折叠图标后面，让另一些图标彻底不出现在菜单栏中，在设置中调整顺序，点一下即可在菜单栏或下拉面板中重新显示隐藏的图标。需要 macOS 27 或更高版本。",
        enable: "隐藏菜单栏图标", enableCaption: "折叠图标左侧的图标会被隐藏。点按它即可显示。",
        unsupportedOSFormat: "菜单栏整理器需要 macOS 27 或更高版本。这台 Mac 运行的是 macOS %@。", unsupportedAPI: "此 macOS 版本未提供菜单栏整理器所依赖的菜单栏控制功能。",
        otherManagerFormat: "%@ 正在运行。两个菜单栏管理工具同时隐藏图标会互相干扰，请先退出它。",
        icon: "图标", iconChevron: "箭头", iconDots: "圆点", iconLines: "横线", iconGrid: "网格",
        reveal: "显示隐藏的图标", revealMenuBar: "在菜单栏中", revealShelf: "在下拉面板中",
        revealMenuBarCaption: "点按折叠图标会把隐藏的图标放回菜单栏。", revealShelfCaption: "点按折叠图标会展开一个列出隐藏图标的面板。菜单栏保持不变；点按面板中的图标即可打开它的菜单。",
        shelfMonochrome: "面板图标显示为单色", shelfEmpty: "没有隐藏任何图标。",
        showSection: "始终显示", showCaption: "位于折叠图标右侧，始终显示在菜单栏中。", showEmpty: "没有始终显示的图标。",
        hideSection: "隐藏", hideCaption: "位于折叠图标左侧。点按它之前保持隐藏，再次点按后重新隐藏。", hideEmpty: "将图标拖放到此处，或在菜单栏中按住 ⌘ 将图标拖到折叠图标左侧。",
        neverSection: "永不显示", neverCaption: "完全不出现在菜单栏中，显示隐藏的图标时也不例外。对该 App 的所有图标生效。", neverEmpty: "没有永久隐藏的图标。",
        tierShow: "始终显示", tierHide: "隐藏", tierNever: "永不显示",
        lockedSystem: "由 macOS 管理", lockedPinned: "macOS 将其固定在菜单栏末端。", lockedOwn: "Vorssaint 自己的图标始终显示", lockedHelper: "由 macOS 无法隐藏的辅助进程绘制", lockedUnsigned: "未使用 Apple 签发的证书签名：只要有图标被隐藏，macOS 就会将其隐藏。",
        systemBattery: "电池", systemBluetooth: "蓝牙", systemClock: "时钟", systemDisplays: "显示器", systemKeyboard: "输入法菜单", systemSound: "声音", systemWiFi: "Wi-Fi", systemScreenMirroring: "屏幕镜像", systemControlCenter: "控制中心",
        applying: "正在移动图标…", applyReportFormat: "已移动 %1$d 个，失败 %2$d 个",
        behaviorNoteTitle: "菜单栏提示",
        mouseHint: "图标移动时，请勿移动鼠标。", dragHint: "你也可以在菜单栏中按住 ⌘ 拖移图标。",
        perAppNote: "同一个 App 的图标会一起隐藏。", systemExtrasNote: "折叠时，专注模式和部分系统项目也会隐藏。展开后即可恢复。某些本地构建的工具也可能隐藏。",
        autoRehide: "自动重新隐藏", autoRehideNever: "永不", autoRehideSecondsFormat: "%d 秒后", showHiddenIcons: "显示隐藏的图标", hideIcons: "隐藏图标",
        statusCollapsed: "图标已隐藏", statusExpanded: "图标已显示", refresh: "刷新",
        problemAccessibility: "读取菜单栏需要辅助功能权限。", problemCollapserNotFound: "折叠图标不在菜单栏中。隐藏已暂停。",
        problemActivationFormat: "隐藏失败：%@", problemNothingToHide: "折叠图标左侧没有任何图标，因此没有隐藏任何内容。",
        problemPeekFailedFormat: "无法从面板打开 %@。它的图标已回到菜单栏，请在那里点按。")
    static let zhTW = MenuBarOrganizerFeatureStrings(
        title: "選單列整理器", hubDescription: "將選單列圖像藏到收合圖像後方，讓另一些圖像完全不出現在選單列中，在設定中調整順序，按一下即可在選單列或下拉面板中重新顯示隱藏的圖像。需要 macOS 27 或以上版本。",
        enable: "隱藏選單列圖像", enableCaption: "收合圖像左側的圖像會被隱藏。按一下它即可顯示。",
        unsupportedOSFormat: "選單列整理器需要 macOS 27 或以上版本。這部 Mac 執行的是 macOS %@。", unsupportedAPI: "此 macOS 版本未提供選單列整理器所仰賴的選單列控制功能。",
        otherManagerFormat: "%@ 正在執行。兩個選單列管理工具同時隱藏圖像會互相干擾，請先將其結束。",
        icon: "圖像", iconChevron: "箭頭", iconDots: "圓點", iconLines: "橫線", iconGrid: "格線",
        reveal: "顯示隱藏的圖像", revealMenuBar: "在選單列中", revealShelf: "在下拉面板中",
        revealMenuBarCaption: "按一下收合圖像會將隱藏的圖像放回選單列。", revealShelfCaption: "按一下收合圖像會展開列出隱藏圖像的面板。選單列保持不變；按一下面板中的圖像即可打開它的選單。",
        shelfMonochrome: "面板圖像以單色顯示", shelfEmpty: "沒有隱藏任何圖像。",
        showSection: "一律顯示", showCaption: "位於收合圖像右側，一律顯示在選單列中。", showEmpty: "沒有一律顯示的圖像。",
        hideSection: "隱藏", hideCaption: "位於收合圖像左側。按一下它之前保持隱藏，再按一下後重新隱藏。", hideEmpty: "將圖像拖放到此處，或在選單列中按住 ⌘ 將圖像拖到收合圖像左側。",
        neverSection: "永不顯示", neverCaption: "完全不出現在選單列中，顯示隱藏的圖像時也不例外。適用於該 App 的所有圖像。", neverEmpty: "沒有永久隱藏的圖像。",
        tierShow: "一律顯示", tierHide: "隱藏", tierNever: "永不顯示",
        lockedSystem: "由 macOS 管理", lockedPinned: "macOS 將其固定在選單列末端。", lockedOwn: "Vorssaint 自己的圖像一律顯示", lockedHelper: "由 macOS 無法隱藏的輔助程序繪製", lockedUnsigned: "未使用 Apple 核發的憑證簽署：只要有圖像被隱藏，macOS 就會將其隱藏。",
        systemBattery: "電池", systemBluetooth: "藍牙", systemClock: "時鐘", systemDisplays: "顯示器", systemKeyboard: "輸入法選單", systemSound: "聲音", systemWiFi: "Wi-Fi", systemScreenMirroring: "螢幕鏡像輸出", systemControlCenter: "控制中心",
        applying: "正在搬移圖像…", applyReportFormat: "已搬移 %1$d 個，失敗 %2$d 個",
        behaviorNoteTitle: "選單列提示",
        mouseHint: "圖像移動時，請勿移動滑鼠。", dragHint: "您也可以在選單列中按住 ⌘ 拖移圖像。",
        perAppNote: "同一個 App 的圖像會一起隱藏。", systemExtrasNote: "收合時，專注模式和部分系統項目也會隱藏。展開後即可恢復。某些本機建置的工具也可能隱藏。",
        autoRehide: "自動重新隱藏", autoRehideNever: "永不", autoRehideSecondsFormat: "%d 秒後", showHiddenIcons: "顯示隱藏的圖像", hideIcons: "隱藏圖像",
        statusCollapsed: "圖像已隱藏", statusExpanded: "圖像已顯示", refresh: "重新整理",
        problemAccessibility: "讀取選單列需要輔助使用權限。", problemCollapserNotFound: "收合圖像不在選單列中。隱藏已暫停。",
        problemActivationFormat: "隱藏失敗：%@", problemNothingToHide: "收合圖像左側沒有任何圖像，因此沒有隱藏任何項目。",
        problemPeekFailedFormat: "無法從面板打開 %@。它的圖像已回到選單列，請在那裡按一下。")
    static let zhHK = MenuBarOrganizerFeatureStrings(
        title: "選單列整理工具", hubDescription: "將選單列圖像收到收合圖像後面，讓另一些圖像完全不出現在選單列中，在設定中調整次序，按一下即可在選單列或下拉面板中重新顯示隱藏的圖像。需要 macOS 27 或以上版本。",
        enable: "隱藏選單列圖像", enableCaption: "收合圖像左邊的圖像會被隱藏。按一下它即可顯示。",
        unsupportedOSFormat: "選單列整理工具需要 macOS 27 或以上版本。這部 Mac 執行的是 macOS %@。", unsupportedAPI: "此 macOS 版本未提供選單列整理工具所依賴的選單列控制功能。",
        otherManagerFormat: "%@ 正在執行。兩個選單列管理工具同時隱藏圖像會互相干擾，請先將其結束。",
        icon: "圖像", iconChevron: "箭嘴", iconDots: "圓點", iconLines: "橫線", iconGrid: "格線",
        reveal: "顯示隱藏的圖像", revealMenuBar: "在選單列中", revealShelf: "在下拉面板中",
        revealMenuBarCaption: "按一下收合圖像會將隱藏的圖像放回選單列。", revealShelfCaption: "按一下收合圖像會展開列出隱藏圖像的面板。選單列保持不變；按一下面板中的圖像即可開啟它的選單。",
        shelfMonochrome: "面板圖像以單色顯示", shelfEmpty: "沒有隱藏任何圖像。",
        showSection: "一律顯示", showCaption: "位於收合圖像右邊，一律顯示在選單列中。", showEmpty: "沒有一律顯示的圖像。",
        hideSection: "隱藏", hideCaption: "位於收合圖像左邊。按一下它之前保持隱藏，再按一下後重新隱藏。", hideEmpty: "將圖像拖放到此處，或在選單列中按住 ⌘ 將圖像拖到收合圖像左邊。",
        neverSection: "永不顯示", neverCaption: "完全不出現在選單列中，顯示隱藏的圖像時亦不例外。適用於該 App 的所有圖像。", neverEmpty: "沒有永久隱藏的圖像。",
        tierShow: "一律顯示", tierHide: "隱藏", tierNever: "永不顯示",
        lockedSystem: "由 macOS 管理", lockedPinned: "macOS 將其固定在選單列末端。", lockedOwn: "Vorssaint 自己的圖像一律顯示", lockedHelper: "由 macOS 無法隱藏的輔助程序繪製", lockedUnsigned: "未使用 Apple 簽發的憑證簽署：只要有圖像被隱藏，macOS 就會將其隱藏。",
        systemBattery: "電池", systemBluetooth: "藍牙", systemClock: "時鐘", systemDisplays: "顯示器", systemKeyboard: "輸入法選單", systemSound: "聲音", systemWiFi: "Wi-Fi", systemScreenMirroring: "螢幕鏡像", systemControlCenter: "控制中心",
        applying: "正在移動圖像…", applyReportFormat: "已移動 %1$d 個，失敗 %2$d 個",
        behaviorNoteTitle: "選單列提示",
        mouseHint: "圖像移動時，請勿移動滑鼠。", dragHint: "您也可以在選單列中按住 ⌘ 拖移圖像。",
        perAppNote: "同一個 App 的圖像會一併隱藏。", systemExtrasNote: "收合時，專注模式和部分系統項目亦會隱藏。展開後即可恢復。某些本機建置的工具也可能隱藏。",
        autoRehide: "自動重新隱藏", autoRehideNever: "永不", autoRehideSecondsFormat: "%d 秒後", showHiddenIcons: "顯示隱藏的圖像", hideIcons: "隱藏圖像",
        statusCollapsed: "圖像已隱藏", statusExpanded: "圖像已顯示", refresh: "重新整理",
        problemAccessibility: "讀取選單列需要輔助使用權限。", problemCollapserNotFound: "收合圖像不在選單列中。隱藏已暫停。",
        problemActivationFormat: "隱藏失敗：%@", problemNothingToHide: "收合圖像左邊沒有任何圖像，因此沒有隱藏任何項目。",
        problemPeekFailedFormat: "無法從面板開啟 %@。它的圖像已回到選單列，請在那裏按一下。")
    static let ar = MenuBarOrganizerFeatureStrings(
        title: "منظّم شريط القوائم",
        hubDescription: "أخفِ أيقونات شريط القوائم خلف زر الطي، وأخفِ بعضها دائمًا، ورتّبها من الإعدادات. أظهر الأيقونات المخفية بنقرة في الشريط أو في درج منسدل. يتطلب macOS 27 أو أحدث.",
        enable: "إخفاء أيقونات شريط القوائم",
        enableCaption: "تُخفى الأيقونات الواقعة يسار زر الطي. انقره لإظهارها.",
        unsupportedOSFormat: "يتطلب منظّم شريط القوائم macOS 27 أو أحدث. يعمل هذا الجهاز بنظام macOS %@.",
        unsupportedAPI: "لا يوفّر إصدار macOS هذا أدوات التحكم التي يحتاجها منظّم شريط القوائم.",
        otherManagerFormat: "%@ قيد التشغيل. يتداخل عمل منظّمين يخفيان الأيقونات في الوقت نفسه؛ أغلقه أولًا.",
        icon: "الأيقونة",
        iconChevron: "سهم",
        iconDots: "نقاط",
        iconLines: "خطوط",
        iconGrid: "شبكة",
        reveal: "إظهار الأيقونات المخفية",
        revealMenuBar: "في شريط القوائم",
        revealShelf: "في درج منسدل",
        revealMenuBarCaption: "تعيد نقرة على زر الطي الأيقونات المخفية إلى الشريط.",
        revealShelfCaption: "تفتح نقرة على زر الطي درجًا بالأيقونات المخفية. يبقى الشريط كما هو؛ انقر أيقونة في الدرج لفتح قائمتها.",
        shelfMonochrome: "أيقونات الدرج بلون واحد",
        shelfEmpty: "لا توجد أيقونات مخفية.",
        showSection: "إظهار دائمًا",
        showCaption: "يمين زر الطي. تبقى ظاهرة في الشريط.",
        showEmpty: "لا توجد أيقونات تظهر دائمًا.",
        hideSection: "إخفاء",
        hideCaption: "يسار زر الطي. انقره لإظهار الأيقونات، وانقره مجددًا لإخفائها.",
        hideEmpty: "أفلت الأيقونات هنا، أو اسحبها مع الضغط على ⌘ إلى يسار زر الطي في الشريط.",
        neverSection: "إخفاء دائمًا",
        neverCaption: "تبقى خارج الشريط حتى عند إظهار الأيقونات المخفية. يشمل ذلك جميع أيقونات التطبيق.",
        neverEmpty: "لا توجد أيقونات مخفية دائمًا.",
        tierShow: "إظهار دائمًا",
        tierHide: "إخفاء",
        tierNever: "إخفاء دائمًا",
        lockedSystem: "يتحكم به macOS",
        lockedPinned: "يثبّت macOS هذا العنصر في نهاية الشريط.",
        lockedOwn: "تبقى أيقونة Vorssaint ظاهرة",
        lockedHelper: "يعرضه مساعد لا يستطيع macOS إخفاء أيقونته",
        lockedUnsigned: "غير موقّع بشهادة صادرة عن Apple؛ يخفيه macOS عند إخفاء أي أيقونة.",
        systemBattery: "البطارية",
        systemBluetooth: "Bluetooth",
        systemClock: "الساعة",
        systemDisplays: "الشاشات",
        systemKeyboard: "قائمة الإدخال",
        systemSound: "الصوت",
        systemWiFi: "Wi-Fi",
        systemScreenMirroring: "انعكاس الشاشة",
        systemControlCenter: "مركز التحكم",
        applying: "جارٍ نقل الأيقونات…",
        applyReportFormat: "نُقل %1$d، وتعذّر نقل %2$d",
        behaviorNoteTitle: "إرشادات شريط القوائم",
        mouseHint: "أبقِ المؤشر ثابتًا أثناء نقل الأيقونات.",
        dragHint: "يمكنك أيضًا سحب الأيقونات في شريط القوائم مع الضغط على ⌘.",
        perAppNote: "تُخفى أيقونات التطبيق الواحد معًا.",
        systemExtrasNote: "يختفي التركيز وبعض عناصر النظام عند طي الشريط. أظهر الأيقونات لاستعادتها. قد تختفي أيضًا بعض الأدوات المبنية محليًا.",
        autoRehide: "إعادة الإخفاء تلقائيًا",
        autoRehideNever: "أبدًا",
        autoRehideSecondsFormat: "بعد %d ثانية",
        showHiddenIcons: "إظهار الأيقونات المخفية",
        hideIcons: "إخفاء الأيقونات",
        statusCollapsed: "الأيقونات مخفية",
        statusExpanded: "الأيقونات ظاهرة",
        refresh: "تحديث",
        problemAccessibility: "يلزم إذن تسهيلات الاستخدام لقراءة شريط القوائم.",
        problemCollapserNotFound: "زر الطي غير موجود في شريط القوائم. الإخفاء متوقف مؤقتًا.",
        problemActivationFormat: "تعذّر الإخفاء: %@",
        problemNothingToHide: "لا توجد أيقونات يسار زر الطي، لذا لم يُخفَ أي شيء.",
        problemPeekFailedFormat: "تعذّر فتح %@ من الدرج. عادت أيقونته إلى الشريط؛ انقرها هناك.")
}
