// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// Strings for flexible scaling. Same contract as the other FeatureStrings
/// structs: memberwise init with labeled arguments in declaration order, one
/// static per language, all in this file. `%d` takes a number, `%@` a display
/// name; counts are phrased as "label: n" so no language needs plural forms.
struct DisplayScalingStrings {
    let pageTitle: String
    let hubDescription: String
    let enable: String
    let enableCaption: String
    let smallestSize: String
    let smallestSizeCaption: String
    let percentOfNativeFormat: String
    let noDisplays: String
    let unnamedDisplay: String
    let nativeFormat: String
    let stateNone: String
    let stateVorssaintFormat: String
    let stateForeignFormat: String
    let install: String
    let update: String
    let replace: String
    let remove: String
    let replaceCaption: String
    let installedNote: String
    let removedNote: String
    let failedNote: String
    let installPromptFormat: String
    let removePromptFormat: String
    let uninstallPrompt: String
    let resolution: String
    let resolutionValueFormat: String
    let renderedFormat: String
    let notHiDPI: String
    let nativeOneToOne: String
    let installedReconnectedNote: String
    let removedReconnectedNote: String

    func percentOfNative(_ percent: Int) -> String { String(format: percentOfNativeFormat, percent) }
    func native(_ width: Int, _ height: Int) -> String { String(format: nativeFormat, width, height) }
    func installPrompt(_ name: String) -> String { String(format: installPromptFormat, name) }
    func removePrompt(_ name: String) -> String { String(format: removePromptFormat, name) }
    func resolutionValue(_ size: ScaledResolution, percent: Int) -> String {
        String(format: resolutionValueFormat, size.width, size.height, percent)
    }
    func rendered(pixelWidth: Int, pixelHeight: Int, nativeWidth: Int, nativeHeight: Int) -> String {
        String(format: renderedFormat, pixelWidth, pixelHeight, nativeWidth, nativeHeight)
    }

    func state(_ state: DisplayScalingOverrideState) -> String {
        switch state {
        case .none: return stateNone
        case .vorssaint(let sizes): return String(format: stateVorssaintFormat, sizes)
        case .foreign(let sizes): return String(format: stateForeignFormat, sizes)
        }
    }
}

extension FeatureStrings {
    static func displayScaling(_ language: AppLanguage) -> DisplayScalingStrings {
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
        case .zhHans: return .zhHans
        case .zhTW: return .zhTW
        case .zhHK: return .zhHK
        case .uk: return .uk
        }
    }
}

extension DisplayScalingStrings {
    static let enUS = DisplayScalingStrings(
        pageTitle: "Flexible scaling",
        hubDescription: "Gives external monitors every sharp HiDPI size between half and full native resolution, so you can pick exactly how big the interface looks.",
        enable: "Show flexible scaling for external displays",
        enableCaption: "Installing sizes asks for your administrator password and writes a display override in /Library/Displays. It applies to every display of the same model.",
        smallestSize: "Smallest size",
        smallestSizeCaption: "The list runs from this size up to the native resolution, one step per percent.",
        percentOfNativeFormat: "%d%% of native",
        noDisplays: "No external display that can be scaled is connected.",
        unnamedDisplay: "External display",
        nativeFormat: "Native %d × %d",
        stateNone: "macOS default sizes.",
        stateVorssaintFormat: "HiDPI sizes from Vorssaint: %d",
        stateForeignFormat: "Sizes set by another app or by hand. HiDPI sizes: %d",
        install: "Install HiDPI sizes",
        update: "Update",
        replace: "Replace",
        remove: "Remove",
        replaceCaption: "The current file is kept and put back when you remove Vorssaint’s sizes.",
        installedNote: "Done. Disconnect and reconnect the display, or log out, and pick a size in System Settings › Displays.",
        removedNote: "Removed. The display returns to its previous sizes after it reconnects.",
        failedNote: "Nothing was changed.",
        installPromptFormat: "Vorssaint wants to install HiDPI sizes for %@.",
        removePromptFormat: "Vorssaint wants to remove its HiDPI sizes for %@.",
        uninstallPrompt: "Vorssaint wants to remove the HiDPI sizes it installed for your displays.",
        resolution: "Resolution",
        resolutionValueFormat: "%d × %d · %d%%",
        renderedFormat: "Sharp: drawn at %d × %d pixels, then fitted to the panel’s native %d × %d. Everything gets bigger, nothing gets blurrier.",
        notHiDPI: "The current mode is not HiDPI, so text is drawn at low resolution. Pick a size with the slider to make it sharp.",
        nativeOneToOne: "Native: every point is one pixel of the panel. Sharpest, smallest. macOS offers no HiDPI sizes between the last scaled stop and native on this display.",
        installedReconnectedNote: "Done. The display reconnected briefly and now offers the new sizes.",
        removedReconnectedNote: "Removed. The display reconnected briefly and is back to its previous sizes."
    )

    static let ptBR = DisplayScalingStrings(
        pageTitle: "Escala flexível",
        hubDescription: "Dá aos monitores externos todos os tamanhos HiDPI nítidos entre metade e a resolução nativa, para você escolher exatamente o tamanho da interface.",
        enable: "Mostrar escala flexível para monitores externos",
        enableCaption: "Instalar tamanhos pede a senha de administrador e grava uma substituição de monitor em /Library/Displays. Vale para todos os monitores do mesmo modelo.",
        smallestSize: "Menor tamanho",
        smallestSizeCaption: "A lista vai deste tamanho até a resolução nativa, um passo por porcento.",
        percentOfNativeFormat: "%d%% da nativa",
        noDisplays: "Nenhum monitor externo que possa ser escalado está conectado.",
        unnamedDisplay: "Monitor externo",
        nativeFormat: "Nativa %d × %d",
        stateNone: "Tamanhos padrão do macOS.",
        stateVorssaintFormat: "Tamanhos HiDPI do Vorssaint: %d",
        stateForeignFormat: "Tamanhos definidos por outro app ou manualmente. Tamanhos HiDPI: %d",
        install: "Instalar tamanhos HiDPI",
        update: "Atualizar",
        replace: "Substituir",
        remove: "Remover",
        replaceCaption: "O arquivo atual é guardado e volta quando você remover os tamanhos do Vorssaint.",
        installedNote: "Pronto. Desconecte e reconecte o monitor, ou encerre a sessão, e escolha um tamanho em Ajustes do Sistema › Monitores.",
        removedNote: "Removido. O monitor volta aos tamanhos anteriores depois de reconectar.",
        failedNote: "Nada foi alterado.",
        installPromptFormat: "O Vorssaint quer instalar tamanhos HiDPI para %@.",
        removePromptFormat: "O Vorssaint quer remover os tamanhos HiDPI de %@.",
        uninstallPrompt: "O Vorssaint quer remover os tamanhos HiDPI que instalou para seus monitores.",
        resolution: "Resolução",
        resolutionValueFormat: "%d × %d · %d%%",
        renderedFormat: "Nítido: desenhado em %d × %d pixels e ajustado à resolução nativa de %d × %d. Tudo fica maior, nada fica borrado.",
        notHiDPI: "O modo atual não é HiDPI, então o texto é desenhado em baixa resolução. Escolha um tamanho no controle para deixá-lo nítido.",
        nativeOneToOne: "Nativa: cada ponto é um pixel do painel. O mais nítido e o menor. O macOS não oferece tamanhos HiDPI entre a última etapa escalada e a nativa neste monitor.",
        installedReconnectedNote: "Pronto. O monitor reconectou por um instante e já oferece os novos tamanhos.",
        removedReconnectedNote: "Removido. O monitor reconectou por um instante e voltou aos tamanhos anteriores."
    )

    static let tr = DisplayScalingStrings(
        pageTitle: "Esnek ölçekleme",
        hubDescription: "Harici monitörlere yerel çözünürlüğün yarısı ile tamamı arasındaki tüm keskin HiDPI boyutlarını verir, böylece arayüzün ne kadar büyük görüneceğini tam olarak seçebilirsiniz.",
        enable: "Harici ekranlar için esnek ölçeklemeyi göster",
        enableCaption: "Boyut yüklemek yönetici parolanızı ister ve /Library/Displays içine bir ekran geçersiz kılma dosyası yazar. Aynı modeldeki tüm ekranlara uygulanır.",
        smallestSize: "En küçük boyut",
        smallestSizeCaption: "Liste bu boyuttan yerel çözünürlüğe kadar, yüzde başına bir adımla ilerler.",
        percentOfNativeFormat: "Yerelin %%%d kadarı",
        noDisplays: "Ölçeklenebilen bir harici ekran bağlı değil.",
        unnamedDisplay: "Harici ekran",
        nativeFormat: "Yerel %d × %d",
        stateNone: "macOS varsayılan boyutları.",
        stateVorssaintFormat: "Vorssaint HiDPI boyutları: %d",
        stateForeignFormat: "Boyutlar başka bir uygulama veya elle ayarlanmış. HiDPI boyutları: %d",
        install: "HiDPI boyutlarını yükle",
        update: "Güncelle",
        replace: "Değiştir",
        remove: "Kaldır",
        replaceCaption: "Mevcut dosya saklanır ve Vorssaint boyutlarını kaldırdığınızda geri konur.",
        installedNote: "Tamam. Ekranın bağlantısını kesip yeniden bağlayın veya oturumu kapatın, ardından Sistem Ayarları › Ekranlar’da bir boyut seçin.",
        removedNote: "Kaldırıldı. Ekran yeniden bağlandığında önceki boyutlarına döner.",
        failedNote: "Hiçbir şey değiştirilmedi.",
        installPromptFormat: "Vorssaint, %@ için HiDPI boyutları yüklemek istiyor.",
        removePromptFormat: "Vorssaint, %@ için HiDPI boyutlarını kaldırmak istiyor.",
        uninstallPrompt: "Vorssaint, ekranlarınız için yüklediği HiDPI boyutlarını kaldırmak istiyor.",
        resolution: "Çözünürlük",
        resolutionValueFormat: "%d × %d · %%%d",
        renderedFormat: "Keskin: %d × %d pikselde çizilir, ardından panelin yerel %d × %d çözünürlüğüne sığdırılır. Her şey büyür, hiçbir şey bulanıklaşmaz.",
        notHiDPI: "Mevcut mod HiDPI değil, bu yüzden metin düşük çözünürlükte çizilir. Keskinleştirmek için kaydırıcıyla bir boyut seçin.",
        nativeOneToOne: "Yerel: her nokta panelin bir pikselidir. En keskin ve en küçük. macOS bu ekranda son ölçekli adım ile yerel arasında HiDPI boyutu sunmaz.",
        installedReconnectedNote: "Tamam. Ekran kısa süreliğine yeniden bağlandı ve artık yeni boyutları sunuyor.",
        removedReconnectedNote: "Kaldırıldı. Ekran kısa süreliğine yeniden bağlandı ve önceki boyutlarına döndü."
    )

    static let ru = DisplayScalingStrings(
        pageTitle: "Гибкое масштабирование",
        hubDescription: "Даёт внешним мониторам все чёткие размеры HiDPI от половины до полного родного разрешения, чтобы вы точно выбрали размер интерфейса.",
        enable: "Показывать гибкое масштабирование для внешних дисплеев",
        enableCaption: "Установка размеров запрашивает пароль администратора и записывает переопределение дисплея в /Library/Displays. Оно действует на все дисплеи той же модели.",
        smallestSize: "Наименьший размер",
        smallestSizeCaption: "Список идёт от этого размера до родного разрешения с шагом в один процент.",
        percentOfNativeFormat: "%d%% от родного",
        noDisplays: "Не подключён внешний дисплей, который можно масштабировать.",
        unnamedDisplay: "Внешний дисплей",
        nativeFormat: "Родное %d × %d",
        stateNone: "Стандартные размеры macOS.",
        stateVorssaintFormat: "Размеры HiDPI от Vorssaint: %d",
        stateForeignFormat: "Размеры задало другое приложение или вручную. Размеры HiDPI: %d",
        install: "Установить размеры HiDPI",
        update: "Обновить",
        replace: "Заменить",
        remove: "Удалить",
        replaceCaption: "Текущий файл сохраняется и возвращается, когда вы удалите размеры Vorssaint.",
        installedNote: "Готово. Отключите и снова подключите дисплей или выйдите из системы и выберите размер в Системных настройках › Дисплеи.",
        removedNote: "Удалено. После переподключения дисплей вернётся к прежним размерам.",
        failedNote: "Ничего не изменено.",
        installPromptFormat: "Vorssaint хочет установить размеры HiDPI для %@.",
        removePromptFormat: "Vorssaint хочет удалить свои размеры HiDPI для %@.",
        uninstallPrompt: "Vorssaint хочет удалить размеры HiDPI, установленные для ваших дисплеев.",
        resolution: "Разрешение",
        resolutionValueFormat: "%d × %d · %d%%",
        renderedFormat: "Чётко: рисуется в %d × %d пикселей и вписывается в родные %d × %d панели. Всё становится крупнее, но не размытее.",
        notHiDPI: "Текущий режим не HiDPI, поэтому текст рисуется в низком разрешении. Выберите размер ползунком, чтобы сделать его чётким.",
        nativeOneToOne: "Родное: каждая точка соответствует одному пикселю панели. Самое чёткое и самое мелкое. Между последним масштабированным шагом и родным macOS на этом дисплее размеров HiDPI не даёт.",
        installedReconnectedNote: "Готово. Дисплей ненадолго переподключился и теперь предлагает новые размеры.",
        removedReconnectedNote: "Удалено. Дисплей ненадолго переподключился и вернулся к прежним размерам."
    )

    static let es = DisplayScalingStrings(
        pageTitle: "Escalado flexible",
        hubDescription: "Da a los monitores externos todos los tamaños HiDPI nítidos entre la mitad y la resolución nativa, para que elijas exactamente cuánto ocupa la interfaz.",
        enable: "Mostrar escalado flexible para pantallas externas",
        enableCaption: "Instalar tamaños pide tu contraseña de administrador y escribe una anulación de pantalla en /Library/Displays. Se aplica a todas las pantallas del mismo modelo.",
        smallestSize: "Tamaño más pequeño",
        smallestSizeCaption: "La lista va desde este tamaño hasta la resolución nativa, un paso por cada porcentaje.",
        percentOfNativeFormat: "%d %% de la nativa",
        noDisplays: "No hay conectada ninguna pantalla externa que se pueda escalar.",
        unnamedDisplay: "Pantalla externa",
        nativeFormat: "Nativa %d × %d",
        stateNone: "Tamaños predeterminados de macOS.",
        stateVorssaintFormat: "Tamaños HiDPI de Vorssaint: %d",
        stateForeignFormat: "Tamaños definidos por otra app o a mano. Tamaños HiDPI: %d",
        install: "Instalar tamaños HiDPI",
        update: "Actualizar",
        replace: "Sustituir",
        remove: "Quitar",
        replaceCaption: "El archivo actual se guarda y vuelve cuando quites los tamaños de Vorssaint.",
        installedNote: "Listo. Desconecta y vuelve a conectar la pantalla, o cierra sesión, y elige un tamaño en Ajustes del Sistema › Pantallas.",
        removedNote: "Quitado. La pantalla vuelve a sus tamaños anteriores al reconectarse.",
        failedNote: "No se cambió nada.",
        installPromptFormat: "Vorssaint quiere instalar tamaños HiDPI para %@.",
        removePromptFormat: "Vorssaint quiere quitar sus tamaños HiDPI de %@.",
        uninstallPrompt: "Vorssaint quiere quitar los tamaños HiDPI que instaló para tus pantallas.",
        resolution: "Resolución",
        resolutionValueFormat: "%d × %d · %d %%",
        renderedFormat: "Nítido: se dibuja a %d × %d píxeles y se ajusta a la resolución nativa de %d × %d. Todo se ve más grande, nada más borroso.",
        notHiDPI: "El modo actual no es HiDPI, así que el texto se dibuja en baja resolución. Elige un tamaño con el control para que sea nítido.",
        nativeOneToOne: "Nativa: cada punto es un píxel del panel. Lo más nítido y lo más pequeño. En esta pantalla macOS no ofrece tamaños HiDPI entre el último paso escalado y la nativa.",
        installedReconnectedNote: "Listo. La pantalla se reconectó un momento y ya ofrece los nuevos tamaños.",
        removedReconnectedNote: "Quitado. La pantalla se reconectó un momento y volvió a sus tamaños anteriores."
    )

    static let sk = DisplayScalingStrings(
        pageTitle: "Flexibilné škálovanie",
        hubDescription: "Dá externým monitorom všetky ostré veľkosti HiDPI od polovice po plné natívne rozlíšenie, aby ste presne zvolili veľkosť rozhrania.",
        enable: "Zobraziť flexibilné škálovanie pre externé displeje",
        enableCaption: "Inštalácia veľkostí si vyžiada heslo správcu a zapíše prepis displeja do /Library/Displays. Platí pre všetky displeje rovnakého modelu.",
        smallestSize: "Najmenšia veľkosť",
        smallestSizeCaption: "Zoznam ide od tejto veľkosti po natívne rozlíšenie, jeden krok na percento.",
        percentOfNativeFormat: "%d %% natívneho",
        noDisplays: "Nie je pripojený žiadny externý displej, ktorý sa dá škálovať.",
        unnamedDisplay: "Externý displej",
        nativeFormat: "Natívne %d × %d",
        stateNone: "Predvolené veľkosti macOS.",
        stateVorssaintFormat: "Veľkosti HiDPI od Vorssaintu: %d",
        stateForeignFormat: "Veľkosti nastavila iná aplikácia alebo ručne. Veľkosti HiDPI: %d",
        install: "Nainštalovať veľkosti HiDPI",
        update: "Aktualizovať",
        replace: "Nahradiť",
        remove: "Odstrániť",
        replaceCaption: "Súčasný súbor sa uchová a vráti sa, keď odstránite veľkosti Vorssaintu.",
        installedNote: "Hotovo. Odpojte a znova pripojte displej alebo sa odhláste a vyberte veľkosť v Nastaveniach systému › Displeje.",
        removedNote: "Odstránené. Po opätovnom pripojení sa displej vráti k predchádzajúcim veľkostiam.",
        failedNote: "Nič sa nezmenilo.",
        installPromptFormat: "Vorssaint chce nainštalovať veľkosti HiDPI pre %@.",
        removePromptFormat: "Vorssaint chce odstrániť svoje veľkosti HiDPI pre %@.",
        uninstallPrompt: "Vorssaint chce odstrániť veľkosti HiDPI, ktoré nainštaloval pre vaše displeje.",
        resolution: "Rozlíšenie",
        resolutionValueFormat: "%d × %d · %d %%",
        renderedFormat: "Ostré: kreslí sa v %d × %d pixeloch a potom sa prispôsobí natívnemu %d × %d panelu. Všetko je väčšie, nič nie je rozmazanejšie.",
        notHiDPI: "Aktuálny režim nie je HiDPI, preto sa text kreslí v nízkom rozlíšení. Vyberte veľkosť posuvníkom, aby bol ostrý.",
        nativeOneToOne: "Natívne: každý bod je jeden pixel panela. Najostrejšie a najmenšie. macOS na tomto displeji neponúka veľkosti HiDPI medzi posledným škálovaným krokom a natívnym.",
        installedReconnectedNote: "Hotovo. Displej sa nakrátko znova pripojil a ponúka nové veľkosti.",
        removedReconnectedNote: "Odstránené. Displej sa nakrátko znova pripojil a má späť predchádzajúce veľkosti."
    )

    static let de = DisplayScalingStrings(
        pageTitle: "Flexible Skalierung",
        hubDescription: "Gibt externen Monitoren jede scharfe HiDPI-Größe zwischen halber und voller nativer Auflösung, damit du genau wählst, wie groß die Oberfläche wirkt.",
        enable: "Flexible Skalierung für externe Displays anzeigen",
        enableCaption: "Das Installieren fragt nach deinem Administratorpasswort und schreibt eine Display-Überschreibung nach /Library/Displays. Sie gilt für alle Displays desselben Modells.",
        smallestSize: "Kleinste Größe",
        smallestSizeCaption: "Die Liste reicht von dieser Größe bis zur nativen Auflösung, in Schritten von einem Prozent.",
        percentOfNativeFormat: "%d %% der nativen",
        noDisplays: "Kein skalierbares externes Display angeschlossen.",
        unnamedDisplay: "Externes Display",
        nativeFormat: "Nativ %d × %d",
        stateNone: "Standardgrößen von macOS.",
        stateVorssaintFormat: "HiDPI-Größen von Vorssaint: %d",
        stateForeignFormat: "Größen von einer anderen App oder von Hand festgelegt. HiDPI-Größen: %d",
        install: "HiDPI-Größen installieren",
        update: "Aktualisieren",
        replace: "Ersetzen",
        remove: "Entfernen",
        replaceCaption: "Die aktuelle Datei bleibt erhalten und kommt zurück, wenn du die Größen von Vorssaint entfernst.",
        installedNote: "Fertig. Trenne das Display und schließe es wieder an oder melde dich ab, und wähle dann eine Größe in Systemeinstellungen › Displays.",
        removedNote: "Entfernt. Nach dem erneuten Verbinden hat das Display wieder seine vorherigen Größen.",
        failedNote: "Es wurde nichts geändert.",
        installPromptFormat: "Vorssaint möchte HiDPI-Größen für %@ installieren.",
        removePromptFormat: "Vorssaint möchte seine HiDPI-Größen für %@ entfernen.",
        uninstallPrompt: "Vorssaint möchte die HiDPI-Größen entfernen, die es für deine Displays installiert hat.",
        resolution: "Auflösung",
        resolutionValueFormat: "%d × %d · %d %%",
        renderedFormat: "Scharf: gezeichnet mit %d × %d Pixeln und dann auf die native Auflösung von %d × %d gebracht. Alles wird größer, nichts unschärfer.",
        notHiDPI: "Der aktuelle Modus ist kein HiDPI, daher wird Text in niedriger Auflösung gezeichnet. Wähle mit dem Regler eine Größe, damit er scharf wird.",
        nativeOneToOne: "Nativ: Jeder Punkt ist ein Pixel des Panels. Am schärfsten, am kleinsten. Zwischen der letzten skalierten Stufe und nativ bietet macOS auf diesem Display keine HiDPI-Größen an.",
        installedReconnectedNote: "Fertig. Das Display wurde kurz neu verbunden und bietet jetzt die neuen Größen an.",
        removedReconnectedNote: "Entfernt. Das Display wurde kurz neu verbunden und hat wieder seine vorherigen Größen."
    )

    static let fr = DisplayScalingStrings(
        pageTitle: "Mise à l’échelle flexible",
        hubDescription: "Donne aux moniteurs externes toutes les tailles HiDPI nettes entre la moitié et la résolution native, pour choisir exactement la taille de l’interface.",
        enable: "Afficher la mise à l’échelle flexible des écrans externes",
        enableCaption: "L’installation des tailles demande votre mot de passe administrateur et écrit un remplacement d’écran dans /Library/Displays. Il s’applique à tous les écrans du même modèle.",
        smallestSize: "Plus petite taille",
        smallestSizeCaption: "La liste va de cette taille jusqu’à la résolution native, par pas de 1 %.",
        percentOfNativeFormat: "%d %% de la native",
        noDisplays: "Aucun écran externe redimensionnable n’est connecté.",
        unnamedDisplay: "Écran externe",
        nativeFormat: "Native %d × %d",
        stateNone: "Tailles par défaut de macOS.",
        stateVorssaintFormat: "Tailles HiDPI de Vorssaint : %d",
        stateForeignFormat: "Tailles définies par une autre app ou à la main. Tailles HiDPI : %d",
        install: "Installer les tailles HiDPI",
        update: "Mettre à jour",
        replace: "Remplacer",
        remove: "Supprimer",
        replaceCaption: "Le fichier actuel est conservé et remis en place quand vous supprimez les tailles de Vorssaint.",
        installedNote: "Terminé. Débranchez puis rebranchez l’écran, ou fermez la session, puis choisissez une taille dans Réglages Système › Moniteurs.",
        removedNote: "Supprimé. L’écran retrouve ses tailles précédentes après reconnexion.",
        failedNote: "Rien n’a été modifié.",
        installPromptFormat: "Vorssaint veut installer des tailles HiDPI pour %@.",
        removePromptFormat: "Vorssaint veut supprimer ses tailles HiDPI pour %@.",
        uninstallPrompt: "Vorssaint veut supprimer les tailles HiDPI installées pour vos écrans.",
        resolution: "Résolution",
        resolutionValueFormat: "%d × %d · %d %%",
        renderedFormat: "Net : dessiné à %d × %d pixels puis ajusté à la résolution native %d × %d. Tout est plus grand, rien n’est plus flou.",
        notHiDPI: "Le mode actuel n’est pas HiDPI, le texte est donc dessiné en basse résolution. Choisissez une taille avec le curseur pour le rendre net.",
        nativeOneToOne: "Native : chaque point est un pixel de la dalle. Le plus net et le plus petit. Sur cet écran, macOS ne propose aucune taille HiDPI entre le dernier palier mis à l’échelle et la native.",
        installedReconnectedNote: "Terminé. L’écran s’est reconnecté un instant et propose maintenant les nouvelles tailles.",
        removedReconnectedNote: "Supprimé. L’écran s’est reconnecté un instant et a retrouvé ses tailles précédentes."
    )

    static let it = DisplayScalingStrings(
        pageTitle: "Ridimensionamento flessibile",
        hubDescription: "Dà ai monitor esterni tutte le dimensioni HiDPI nitide tra metà e piena risoluzione nativa, così scegli esattamente quanto è grande l’interfaccia.",
        enable: "Mostra il ridimensionamento flessibile per i monitor esterni",
        enableCaption: "L’installazione delle dimensioni chiede la password di amministratore e scrive una sostituzione del monitor in /Library/Displays. Vale per tutti i monitor dello stesso modello.",
        smallestSize: "Dimensione minima",
        smallestSizeCaption: "L’elenco va da questa dimensione fino alla risoluzione nativa, un passo per ogni punto percentuale.",
        percentOfNativeFormat: "%d%% della nativa",
        noDisplays: "Nessun monitor esterno ridimensionabile collegato.",
        unnamedDisplay: "Monitor esterno",
        nativeFormat: "Nativa %d × %d",
        stateNone: "Dimensioni predefinite di macOS.",
        stateVorssaintFormat: "Dimensioni HiDPI di Vorssaint: %d",
        stateForeignFormat: "Dimensioni impostate da un’altra app o a mano. Dimensioni HiDPI: %d",
        install: "Installa dimensioni HiDPI",
        update: "Aggiorna",
        replace: "Sostituisci",
        remove: "Rimuovi",
        replaceCaption: "Il file attuale viene conservato e rimesso al suo posto quando rimuovi le dimensioni di Vorssaint.",
        installedNote: "Fatto. Scollega e ricollega il monitor, o esci dalla sessione, e scegli una dimensione in Impostazioni di Sistema › Monitor.",
        removedNote: "Rimosso. Il monitor torna alle dimensioni precedenti dopo la riconnessione.",
        failedNote: "Non è stato modificato nulla.",
        installPromptFormat: "Vorssaint vuole installare dimensioni HiDPI per %@.",
        removePromptFormat: "Vorssaint vuole rimuovere le sue dimensioni HiDPI per %@.",
        uninstallPrompt: "Vorssaint vuole rimuovere le dimensioni HiDPI installate per i tuoi monitor.",
        resolution: "Risoluzione",
        resolutionValueFormat: "%d × %d · %d%%",
        renderedFormat: "Nitido: disegnato a %d × %d pixel e poi adattato alla risoluzione nativa di %d × %d. Tutto diventa più grande, niente più sfocato.",
        notHiDPI: "La modalità attuale non è HiDPI, quindi il testo è disegnato a bassa risoluzione. Scegli una dimensione con il cursore per renderlo nitido.",
        nativeOneToOne: "Nativa: ogni punto è un pixel del pannello. La più nitida e la più piccola. Su questo monitor macOS non offre dimensioni HiDPI tra l’ultimo passo ridimensionato e la nativa.",
        installedReconnectedNote: "Fatto. Il monitor si è ricollegato per un attimo e ora offre le nuove dimensioni.",
        removedReconnectedNote: "Rimosso. Il monitor si è ricollegato per un attimo ed è tornato alle dimensioni precedenti."
    )

    static let ja = DisplayScalingStrings(
        pageTitle: "フレキシブルスケーリング",
        hubDescription: "外部モニタに、ネイティブ解像度の半分から最大までのくっきりした HiDPI サイズをすべて追加し、画面表示の大きさを細かく選べるようにします。",
        enable: "外部ディスプレイのフレキシブルスケーリングを表示",
        enableCaption: "サイズのインストールには管理者パスワードが必要で、/Library/Displays にディスプレイのオーバーライドを書き込みます。同じ機種のすべてのディスプレイに適用されます。",
        smallestSize: "最小サイズ",
        smallestSizeCaption: "このサイズからネイティブ解像度まで、1% 刻みで並びます。",
        percentOfNativeFormat: "ネイティブの %d%%",
        noDisplays: "スケーリングできる外部ディスプレイが接続されていません。",
        unnamedDisplay: "外部ディスプレイ",
        nativeFormat: "ネイティブ %d × %d",
        stateNone: "macOS の標準サイズ。",
        stateVorssaintFormat: "Vorssaint の HiDPI サイズ：%d",
        stateForeignFormat: "ほかのアプリか手動で設定されたサイズ。HiDPI サイズ：%d",
        install: "HiDPI サイズをインストール",
        update: "更新",
        replace: "置き換える",
        remove: "削除",
        replaceCaption: "現在のファイルは保管され、Vorssaint のサイズを削除すると元に戻ります。",
        installedNote: "完了しました。ディスプレイを抜き差しするかログアウトしてから、システム設定 › ディスプレイでサイズを選んでください。",
        removedNote: "削除しました。再接続するとディスプレイは以前のサイズに戻ります。",
        failedNote: "何も変更されませんでした。",
        installPromptFormat: "Vorssaint が %@ に HiDPI サイズをインストールしようとしています。",
        removePromptFormat: "Vorssaint が %@ の HiDPI サイズを削除しようとしています。",
        uninstallPrompt: "Vorssaint がディスプレイ用にインストールした HiDPI サイズを削除しようとしています。",
        resolution: "解像度",
        resolutionValueFormat: "%d × %d・%d%%",
        renderedFormat: "くっきり表示：%d × %d ピクセルで描画し、パネル本来の %d × %d に合わせます。すべてが大きくなり、ぼやけることはありません。",
        notHiDPI: "現在のモードは HiDPI ではないため、文字が低解像度で描画されています。スライダでサイズを選ぶとくっきり表示になります。",
        nativeOneToOne: "ネイティブ：1 ポイントがパネルの 1 ピクセルに対応します。最もくっきりして最も小さい表示です。このディスプレイでは、最後の拡大縮小ステップとネイティブの間に macOS の HiDPI サイズはありません。",
        installedReconnectedNote: "完了しました。ディスプレイが一瞬再接続され、新しいサイズを選べるようになりました。",
        removedReconnectedNote: "削除しました。ディスプレイが一瞬再接続され、以前のサイズに戻りました。"
    )

    static let ko = DisplayScalingStrings(
        pageTitle: "유연한 배율",
        hubDescription: "외장 모니터에 기본 해상도의 절반부터 최대까지 선명한 HiDPI 크기를 모두 제공해, 화면 요소의 크기를 정확히 고를 수 있게 합니다.",
        enable: "외장 디스플레이의 유연한 배율 보기",
        enableCaption: "크기를 설치하면 관리자 암호를 묻고 /Library/Displays에 디스플레이 오버라이드를 기록합니다. 같은 모델의 모든 디스플레이에 적용됩니다.",
        smallestSize: "가장 작은 크기",
        smallestSizeCaption: "이 크기부터 기본 해상도까지 1% 단위로 나열됩니다.",
        percentOfNativeFormat: "기본 해상도의 %d%%",
        noDisplays: "배율을 조정할 수 있는 외장 디스플레이가 연결되어 있지 않습니다.",
        unnamedDisplay: "외장 디스플레이",
        nativeFormat: "기본 %d × %d",
        stateNone: "macOS 기본 크기.",
        stateVorssaintFormat: "Vorssaint HiDPI 크기: %d",
        stateForeignFormat: "다른 앱이나 수동으로 설정된 크기. HiDPI 크기: %d",
        install: "HiDPI 크기 설치",
        update: "업데이트",
        replace: "교체",
        remove: "제거",
        replaceCaption: "현재 파일은 보관되며 Vorssaint의 크기를 제거하면 다시 돌아옵니다.",
        installedNote: "완료되었습니다. 디스플레이를 분리했다가 다시 연결하거나 로그아웃한 다음 시스템 설정 › 디스플레이에서 크기를 고르세요.",
        removedNote: "제거되었습니다. 다시 연결하면 디스플레이가 이전 크기로 돌아갑니다.",
        failedNote: "변경된 사항이 없습니다.",
        installPromptFormat: "Vorssaint가 %@에 HiDPI 크기를 설치하려고 합니다.",
        removePromptFormat: "Vorssaint가 %@의 HiDPI 크기를 제거하려고 합니다.",
        uninstallPrompt: "Vorssaint가 디스플레이용으로 설치한 HiDPI 크기를 제거하려고 합니다.",
        resolution: "해상도",
        resolutionValueFormat: "%d × %d · %d%%",
        renderedFormat: "선명함: %d × %d 픽셀로 그린 뒤 패널의 기본 %d × %d에 맞춥니다. 모든 것이 커지지만 흐려지지 않습니다.",
        notHiDPI: "현재 모드는 HiDPI가 아니라서 텍스트가 낮은 해상도로 그려집니다. 슬라이더로 크기를 고르면 선명해집니다.",
        nativeOneToOne: "기본: 한 포인트가 패널의 한 픽셀입니다. 가장 선명하고 가장 작습니다. 이 디스플레이에서는 마지막 배율 단계와 기본 사이에 macOS가 HiDPI 크기를 제공하지 않습니다.",
        installedReconnectedNote: "완료되었습니다. 디스플레이가 잠시 다시 연결되어 이제 새 크기를 제공합니다.",
        removedReconnectedNote: "제거되었습니다. 디스플레이가 잠시 다시 연결되어 이전 크기로 돌아왔습니다."
    )

    static let zhHans = DisplayScalingStrings(
        pageTitle: "灵活缩放",
        hubDescription: "为外接显示器提供从一半到完整原生分辨率之间的所有清晰 HiDPI 尺寸，让你精确选择界面显示的大小。",
        enable: "显示外接显示器的灵活缩放",
        enableCaption: "安装尺寸需要输入管理员密码，并会在 /Library/Displays 中写入显示器覆盖文件。它适用于同一型号的所有显示器。",
        smallestSize: "最小尺寸",
        smallestSizeCaption: "列表从这个尺寸一直到原生分辨率，每 1% 一档。",
        percentOfNativeFormat: "原生的 %d%%",
        noDisplays: "没有连接可缩放的外接显示器。",
        unnamedDisplay: "外接显示器",
        nativeFormat: "原生 %d × %d",
        stateNone: "macOS 默认尺寸。",
        stateVorssaintFormat: "Vorssaint 的 HiDPI 尺寸：%d",
        stateForeignFormat: "尺寸由其他 App 或手动设置。HiDPI 尺寸：%d",
        install: "安装 HiDPI 尺寸",
        update: "更新",
        replace: "替换",
        remove: "移除",
        replaceCaption: "当前文件会被保留，移除 Vorssaint 的尺寸后会恢复。",
        installedNote: "完成。断开并重新连接显示器，或注销，然后在“系统设置 › 显示器”中选择尺寸。",
        removedNote: "已移除。显示器重新连接后会恢复之前的尺寸。",
        failedNote: "未做任何更改。",
        installPromptFormat: "Vorssaint 想为 %@ 安装 HiDPI 尺寸。",
        removePromptFormat: "Vorssaint 想移除 %@ 的 HiDPI 尺寸。",
        uninstallPrompt: "Vorssaint 想移除它为你的显示器安装的 HiDPI 尺寸。",
        resolution: "分辨率",
        resolutionValueFormat: "%d × %d · %d%%",
        renderedFormat: "清晰：以 %d × %d 像素绘制，再缩放到面板原生的 %d × %d。所有内容变大，但不会变模糊。",
        notHiDPI: "当前模式不是 HiDPI，文字以低分辨率绘制。用滑块选择一个尺寸即可变清晰。",
        nativeOneToOne: "原生：每个点就是面板的一个像素。最清晰，也最小。在这台显示器上，macOS 在最后一个缩放档和原生之间不提供 HiDPI 尺寸。",
        installedReconnectedNote: "完成。显示器已短暂重新连接，现在提供新的尺寸。",
        removedReconnectedNote: "已移除。显示器已短暂重新连接，恢复为之前的尺寸。"
    )

    static let zhTW = DisplayScalingStrings(
        pageTitle: "彈性縮放",
        hubDescription: "為外接顯示器提供從一半到完整原生解析度之間的所有清晰 HiDPI 尺寸，讓你精確選擇介面顯示的大小。",
        enable: "顯示外接顯示器的彈性縮放",
        enableCaption: "安裝尺寸需要輸入管理者密碼，並會在 /Library/Displays 寫入顯示器覆寫檔案。它適用於同一型號的所有顯示器。",
        smallestSize: "最小尺寸",
        smallestSizeCaption: "列表從這個尺寸一直到原生解析度，每 1% 一級。",
        percentOfNativeFormat: "原生的 %d%%",
        noDisplays: "沒有連接可縮放的外接顯示器。",
        unnamedDisplay: "外接顯示器",
        nativeFormat: "原生 %d × %d",
        stateNone: "macOS 預設尺寸。",
        stateVorssaintFormat: "Vorssaint 的 HiDPI 尺寸：%d",
        stateForeignFormat: "尺寸由其他 App 或手動設定。HiDPI 尺寸：%d",
        install: "安裝 HiDPI 尺寸",
        update: "更新",
        replace: "取代",
        remove: "移除",
        replaceCaption: "目前的檔案會被保留，移除 Vorssaint 的尺寸後會復原。",
        installedNote: "完成。中斷並重新連接顯示器，或登出，然後在「系統設定 › 顯示器」選擇尺寸。",
        removedNote: "已移除。顯示器重新連接後會恢復先前的尺寸。",
        failedNote: "沒有做任何變更。",
        installPromptFormat: "Vorssaint 想為 %@ 安裝 HiDPI 尺寸。",
        removePromptFormat: "Vorssaint 想移除 %@ 的 HiDPI 尺寸。",
        uninstallPrompt: "Vorssaint 想移除它為你的顯示器安裝的 HiDPI 尺寸。",
        resolution: "解析度",
        resolutionValueFormat: "%d × %d · %d%%",
        renderedFormat: "清晰：以 %d × %d 像素繪製，再縮放到面板原生的 %d × %d。所有內容變大，但不會變模糊。",
        notHiDPI: "目前模式不是 HiDPI，文字以低解析度繪製。用滑桿選擇一個尺寸即可變清晰。",
        nativeOneToOne: "原生：每個點就是面板的一個像素。最清晰，也最小。在這台顯示器上，macOS 在最後一個縮放級和原生之間不提供 HiDPI 尺寸。",
        installedReconnectedNote: "完成。顯示器已短暫重新連接，現在提供新的尺寸。",
        removedReconnectedNote: "已移除。顯示器已短暫重新連接，恢復為先前的尺寸。"
    )

    static let zhHK = DisplayScalingStrings(
        pageTitle: "彈性縮放",
        hubDescription: "為外接顯示器提供由一半至完整原生解像度之間的所有清晰 HiDPI 尺寸，讓你準確選擇介面顯示的大小。",
        enable: "顯示外接顯示器的彈性縮放",
        enableCaption: "安裝尺寸需要輸入管理員密碼，並會在 /Library/Displays 寫入顯示器覆寫檔案。它適用於同一型號的所有顯示器。",
        smallestSize: "最小尺寸",
        smallestSizeCaption: "列表由這個尺寸一直到原生解像度，每 1% 一級。",
        percentOfNativeFormat: "原生的 %d%%",
        noDisplays: "未有連接可縮放的外接顯示器。",
        unnamedDisplay: "外接顯示器",
        nativeFormat: "原生 %d × %d",
        stateNone: "macOS 預設尺寸。",
        stateVorssaintFormat: "Vorssaint 的 HiDPI 尺寸：%d",
        stateForeignFormat: "尺寸由其他 App 或手動設定。HiDPI 尺寸：%d",
        install: "安裝 HiDPI 尺寸",
        update: "更新",
        replace: "取代",
        remove: "移除",
        replaceCaption: "目前的檔案會被保留，移除 Vorssaint 的尺寸後會還原。",
        installedNote: "完成。中斷並重新連接顯示器，或登出，然後在「系統設定 › 顯示器」選擇尺寸。",
        removedNote: "已移除。顯示器重新連接後會回復之前的尺寸。",
        failedNote: "沒有作出任何更改。",
        installPromptFormat: "Vorssaint 想為 %@ 安裝 HiDPI 尺寸。",
        removePromptFormat: "Vorssaint 想移除 %@ 的 HiDPI 尺寸。",
        uninstallPrompt: "Vorssaint 想移除它為你的顯示器安裝的 HiDPI 尺寸。",
        resolution: "解像度",
        resolutionValueFormat: "%d × %d · %d%%",
        renderedFormat: "清晰：以 %d × %d 像素繪製，再縮放至面板原生的 %d × %d。所有內容變大，但不會變模糊。",
        notHiDPI: "目前模式不是 HiDPI，文字以低解像度繪製。用滑桿選擇一個尺寸便會變清晰。",
        nativeOneToOne: "原生：每個點就是面板的一個像素。最清晰，亦最小。在這部顯示器上，macOS 在最後一個縮放級和原生之間不提供 HiDPI 尺寸。",
        installedReconnectedNote: "完成。顯示器已短暫重新連接，現在提供新的尺寸。",
        removedReconnectedNote: "已移除。顯示器已短暫重新連接，回復為之前的尺寸。"
    )

    static let uk = DisplayScalingStrings(
        pageTitle: "Гнучке масштабування",
        hubDescription: "Дає зовнішнім моніторам усі чіткі розміри HiDPI від половини до повної рідної роздільності, щоб ви точно обрали розмір інтерфейсу.",
        enable: "Показувати гнучке масштабування для зовнішніх дисплеїв",
        enableCaption: "Встановлення розмірів запитує пароль адміністратора й записує перевизначення дисплея в /Library/Displays. Воно діє для всіх дисплеїв тієї самої моделі.",
        smallestSize: "Найменший розмір",
        smallestSizeCaption: "Список іде від цього розміру до рідної роздільності з кроком в один відсоток.",
        percentOfNativeFormat: "%d%% від рідної",
        noDisplays: "Не підключено зовнішній дисплей, який можна масштабувати.",
        unnamedDisplay: "Зовнішній дисплей",
        nativeFormat: "Рідна %d × %d",
        stateNone: "Стандартні розміри macOS.",
        stateVorssaintFormat: "Розміри HiDPI від Vorssaint: %d",
        stateForeignFormat: "Розміри задала інша програма або вручну. Розміри HiDPI: %d",
        install: "Встановити розміри HiDPI",
        update: "Оновити",
        replace: "Замінити",
        remove: "Видалити",
        replaceCaption: "Поточний файл зберігається й повертається, коли ви видалите розміри Vorssaint.",
        installedNote: "Готово. Від’єднайте та знову під’єднайте дисплей або вийдіть із системи й виберіть розмір у Системних параметрах › Дисплеї.",
        removedNote: "Видалено. Після повторного під’єднання дисплей повернеться до попередніх розмірів.",
        failedNote: "Нічого не змінено.",
        installPromptFormat: "Vorssaint хоче встановити розміри HiDPI для %@.",
        removePromptFormat: "Vorssaint хоче видалити свої розміри HiDPI для %@.",
        uninstallPrompt: "Vorssaint хоче видалити розміри HiDPI, які встановив для ваших дисплеїв.",
        resolution: "Роздільність",
        resolutionValueFormat: "%d × %d · %d%%",
        renderedFormat: "Чітко: малюється в %d × %d пікселях і вписується в рідні %d × %d панелі. Усе стає більшим, але не розмитішим.",
        notHiDPI: "Поточний режим не HiDPI, тому текст малюється в низькій роздільності. Виберіть розмір повзунком, щоб зробити його чітким.",
        nativeOneToOne: "Рідна: кожна точка відповідає одному пікселю панелі. Найчіткіше й найменше. Між останнім масштабованим кроком і рідною macOS на цьому дисплеї не пропонує розмірів HiDPI.",
        installedReconnectedNote: "Готово. Дисплей ненадовго перепід’єднався й тепер пропонує нові розміри.",
        removedReconnectedNote: "Видалено. Дисплей ненадовго перепід’єднався й повернувся до попередніх розмірів."
    )
}
