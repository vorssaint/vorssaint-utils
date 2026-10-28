// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

struct DockSpacerStrings {
    let title: String
    let description: String
    let addLarge: String
    let addSmall: String
    let restart: String
    let restartAfterAdding: String
    let restartCaption: String
    let largeAdded: String
    let smallAdded: String
    let largeAddedAndRestarted: String
    let smallAddedAndRestarted: String
    let addedButRestartFailed: String
    let restarted: String
    let addFailed: String
    let restartFailed: String
}

extension FeatureStrings {
    static func dockSpacer(_ language: AppLanguage) -> DockSpacerStrings {
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
        }
    }
}

extension DockSpacerStrings {
    static let enUS = DockSpacerStrings(
        title: "Dock spacer",
        description: "Add empty space between apps. After restarting the Dock, drag spacers to arrange them or drag them out to remove them.",
        addLarge: "Add large spacer",
        addSmall: "Add small spacer",
        restart: "Restart Dock",
        restartAfterAdding: "Restart Dock after adding spacer",
        restartCaption: "Restart to show newly added spacers, automatically or with Restart Dock. This briefly hides the Dock.",
        largeAdded: "Large spacer added. Restart the Dock to show it.",
        smallAdded: "Small spacer added. Restart the Dock to show it.",
        largeAddedAndRestarted: "Large spacer added and Dock restarted.",
        smallAddedAndRestarted: "Small spacer added and Dock restarted.",
        addedButRestartFailed: "Spacer added, but the Dock could not restart. Use Restart Dock to apply it without adding another spacer.",
        restarted: "Dock restarted.",
        addFailed: "Could not add the spacer. Try again.",
        restartFailed: "Could not restart the Dock. Try again."
    )

    static let ptBR = DockSpacerStrings(
        title: "Espaçador do Dock",
        description: "Adicione espaços vazios entre os apps. Após reiniciar o Dock, arraste os espaçadores para organizá-los ou arraste-os para fora para removê-los.",
        addLarge: "Adicionar espaçador grande",
        addSmall: "Adicionar espaçador pequeno",
        restart: "Reiniciar o Dock",
        restartAfterAdding: "Reiniciar o Dock após adicionar um espaçador",
        restartCaption: "Reinicie automaticamente ou com Reiniciar o Dock para mostrar os novos espaçadores. Isso oculta o Dock por um instante.",
        largeAdded: "Espaçador grande adicionado. Reinicie o Dock para mostrá-lo.",
        smallAdded: "Espaçador pequeno adicionado. Reinicie o Dock para mostrá-lo.",
        largeAddedAndRestarted: "Espaçador grande adicionado e Dock reiniciado.",
        smallAddedAndRestarted: "Espaçador pequeno adicionado e Dock reiniciado.",
        addedButRestartFailed: "Espaçador adicionado, mas não foi possível reiniciar o Dock. Use Reiniciar o Dock para aplicá-lo sem adicionar outro espaçador.",
        restarted: "Dock reiniciado.",
        addFailed: "Não foi possível adicionar o espaçador. Tente novamente.",
        restartFailed: "Não foi possível reiniciar o Dock. Tente novamente."
    )

    static let tr = DockSpacerStrings(
        title: "Dock boşluğu",
        description: "Uygulamalar arasına boşluk ekleyin. Dock’u yeniden başlattıktan sonra boşlukları düzenlemek için sürükleyin veya kaldırmak için Dock’un dışına sürükleyin.",
        addLarge: "Büyük boşluk ekle",
        addSmall: "Küçük boşluk ekle",
        restart: "Dock’u yeniden başlat",
        restartAfterAdding: "Boşluk ekledikten sonra Dock’u yeniden başlat",
        restartCaption: "Yeni eklenen boşlukları göstermek için otomatik olarak veya Dock’u yeniden başlat ile yeniden başlatın. Bu işlem Dock’u kısa süreliğine gizler.",
        largeAdded: "Büyük boşluk eklendi. Göstermek için Dock’u yeniden başlatın.",
        smallAdded: "Küçük boşluk eklendi. Göstermek için Dock’u yeniden başlatın.",
        largeAddedAndRestarted: "Büyük boşluk eklendi ve Dock yeniden başlatıldı.",
        smallAddedAndRestarted: "Küçük boşluk eklendi ve Dock yeniden başlatıldı.",
        addedButRestartFailed: "Boşluk eklendi ancak Dock yeniden başlatılamadı. Başka bir boşluk eklemeden uygulamak için Dock’u yeniden başlat seçeneğini kullanın.",
        restarted: "Dock yeniden başlatıldı.",
        addFailed: "Boşluk eklenemedi. Yeniden deneyin.",
        restartFailed: "Dock yeniden başlatılamadı. Yeniden deneyin."
    )

    static let ru = DockSpacerStrings(
        title: "Разделитель Dock",
        description: "Добавляйте пустое пространство между приложениями. После перезапуска Dock перетаскивайте разделители, чтобы упорядочить их, или вытаскивайте за пределы Dock, чтобы удалить.",
        addLarge: "Добавить большой разделитель",
        addSmall: "Добавить маленький разделитель",
        restart: "Перезапустить Dock",
        restartAfterAdding: "Перезапускать Dock после добавления разделителя",
        restartCaption: "Чтобы увидеть новые разделители, перезапустите Dock автоматически или кнопкой «Перезапустить Dock». Dock ненадолго исчезнет.",
        largeAdded: "Большой разделитель добавлен. Перезапустите Dock, чтобы увидеть его.",
        smallAdded: "Маленький разделитель добавлен. Перезапустите Dock, чтобы увидеть его.",
        largeAddedAndRestarted: "Большой разделитель добавлен, Dock перезапущен.",
        smallAddedAndRestarted: "Маленький разделитель добавлен, Dock перезапущен.",
        addedButRestartFailed: "Разделитель добавлен, но не удалось перезапустить Dock. Нажмите «Перезапустить Dock», чтобы применить его, не добавляя ещё один разделитель.",
        restarted: "Dock перезапущен.",
        addFailed: "Не удалось добавить разделитель. Повторите попытку.",
        restartFailed: "Не удалось перезапустить Dock. Повторите попытку."
    )

    static let es = DockSpacerStrings(
        title: "Separador del Dock",
        description: "Añade espacios vacíos entre las apps. Tras reiniciar el Dock, arrastra los separadores para organizarlos o sácalos del Dock para eliminarlos.",
        addLarge: "Añadir separador grande",
        addSmall: "Añadir separador pequeño",
        restart: "Reiniciar el Dock",
        restartAfterAdding: "Reiniciar el Dock después de añadir un separador",
        restartCaption: "Reinicia automáticamente o con Reiniciar el Dock para mostrar los nuevos separadores. El Dock se ocultará brevemente.",
        largeAdded: "Separador grande añadido. Reinicia el Dock para verlo.",
        smallAdded: "Separador pequeño añadido. Reinicia el Dock para verlo.",
        largeAddedAndRestarted: "Separador grande añadido y Dock reiniciado.",
        smallAddedAndRestarted: "Separador pequeño añadido y Dock reiniciado.",
        addedButRestartFailed: "Separador añadido, pero no se pudo reiniciar el Dock. Usa Reiniciar el Dock para aplicarlo sin añadir otro separador.",
        restarted: "Dock reiniciado.",
        addFailed: "No se pudo añadir el separador. Inténtalo de nuevo.",
        restartFailed: "No se pudo reiniciar el Dock. Inténtalo de nuevo."
    )

    static let sk = DockSpacerStrings(
        title: "Oddeľovač v Docku",
        description: "Pridajte prázdne miesto medzi aplikácie. Po reštartovaní Docku usporiadajte oddeľovače potiahnutím alebo ich odstráňte potiahnutím mimo Docku.",
        addLarge: "Pridať veľký oddeľovač",
        addSmall: "Pridať malý oddeľovač",
        restart: "Reštartovať Dock",
        restartAfterAdding: "Reštartovať Dock po pridaní oddeľovača",
        restartCaption: "Nové oddeľovače zobrazíte automatickým reštartovaním alebo tlačidlom Reštartovať Dock. Dock sa na chvíľu skryje.",
        largeAdded: "Veľký oddeľovač bol pridaný. Zobrazíte ho reštartovaním Docku.",
        smallAdded: "Malý oddeľovač bol pridaný. Zobrazíte ho reštartovaním Docku.",
        largeAddedAndRestarted: "Veľký oddeľovač bol pridaný a Dock bol reštartovaný.",
        smallAddedAndRestarted: "Malý oddeľovač bol pridaný a Dock bol reštartovaný.",
        addedButRestartFailed: "Oddeľovač bol pridaný, ale Dock sa nepodarilo reštartovať. Použite Reštartovať Dock, aby sa zmena prejavila bez pridania ďalšieho oddeľovača.",
        restarted: "Dock bol reštartovaný.",
        addFailed: "Oddeľovač sa nepodarilo pridať. Skúste to znova.",
        restartFailed: "Dock sa nepodarilo reštartovať. Skúste to znova."
    )

    static let de = DockSpacerStrings(
        title: "Dock-Abstandshalter",
        description: "Füge Leerraum zwischen Apps ein. Nach dem Neustart des Docks kannst du Abstandshalter zum Anordnen verschieben oder zum Entfernen aus dem Dock ziehen.",
        addLarge: "Großen Abstandshalter hinzufügen",
        addSmall: "Kleinen Abstandshalter hinzufügen",
        restart: "Dock neu starten",
        restartAfterAdding: "Dock nach dem Hinzufügen eines Abstandshalters neu starten",
        restartCaption: "Starte das Dock automatisch oder über „Dock neu starten“ neu, um neue Abstandshalter anzuzeigen. Dabei wird das Dock kurz ausgeblendet.",
        largeAdded: "Großer Abstandshalter hinzugefügt. Starte das Dock neu, um ihn anzuzeigen.",
        smallAdded: "Kleiner Abstandshalter hinzugefügt. Starte das Dock neu, um ihn anzuzeigen.",
        largeAddedAndRestarted: "Großer Abstandshalter hinzugefügt und Dock neu gestartet.",
        smallAddedAndRestarted: "Kleiner Abstandshalter hinzugefügt und Dock neu gestartet.",
        addedButRestartFailed: "Abstandshalter hinzugefügt, aber das Dock konnte nicht neu gestartet werden. Verwende „Dock neu starten“, um ihn anzuwenden, ohne einen weiteren Abstandshalter hinzuzufügen.",
        restarted: "Dock neu gestartet.",
        addFailed: "Der Abstandshalter konnte nicht hinzugefügt werden. Versuche es erneut.",
        restartFailed: "Das Dock konnte nicht neu gestartet werden. Versuche es erneut."
    )

    static let fr = DockSpacerStrings(
        title: "Espaceur du Dock",
        description: "Ajoutez des espaces vides entre les apps. Après avoir redémarré le Dock, faites glisser les espaceurs pour les organiser ou sortez-les du Dock pour les supprimer.",
        addLarge: "Ajouter un grand espaceur",
        addSmall: "Ajouter un petit espaceur",
        restart: "Redémarrer le Dock",
        restartAfterAdding: "Redémarrer le Dock après l’ajout d’un espaceur",
        restartCaption: "Redémarrez automatiquement ou avec Redémarrer le Dock pour afficher les nouveaux espaceurs. Le Dock sera brièvement masqué.",
        largeAdded: "Grand espaceur ajouté. Redémarrez le Dock pour l’afficher.",
        smallAdded: "Petit espaceur ajouté. Redémarrez le Dock pour l’afficher.",
        largeAddedAndRestarted: "Grand espaceur ajouté et Dock redémarré.",
        smallAddedAndRestarted: "Petit espaceur ajouté et Dock redémarré.",
        addedButRestartFailed: "Espaceur ajouté, mais le Dock n’a pas pu redémarrer. Utilisez Redémarrer le Dock pour appliquer la modification sans ajouter un autre espaceur.",
        restarted: "Dock redémarré.",
        addFailed: "Impossible d’ajouter l’espaceur. Réessayez.",
        restartFailed: "Impossible de redémarrer le Dock. Réessayez."
    )

    static let it = DockSpacerStrings(
        title: "Spaziatore del Dock",
        description: "Aggiungi spazi vuoti tra le app. Dopo aver riavviato il Dock, trascina gli spaziatori per disporli oppure trascinali fuori dal Dock per rimuoverli.",
        addLarge: "Aggiungi spaziatore grande",
        addSmall: "Aggiungi spaziatore piccolo",
        restart: "Riavvia il Dock",
        restartAfterAdding: "Riavvia il Dock dopo aver aggiunto uno spaziatore",
        restartCaption: "Riavvia automaticamente o con Riavvia il Dock per mostrare i nuovi spaziatori. Il Dock verrà nascosto per un istante.",
        largeAdded: "Spaziatore grande aggiunto. Riavvia il Dock per mostrarlo.",
        smallAdded: "Spaziatore piccolo aggiunto. Riavvia il Dock per mostrarlo.",
        largeAddedAndRestarted: "Spaziatore grande aggiunto e Dock riavviato.",
        smallAddedAndRestarted: "Spaziatore piccolo aggiunto e Dock riavviato.",
        addedButRestartFailed: "Spaziatore aggiunto, ma non è stato possibile riavviare il Dock. Usa Riavvia il Dock per applicare la modifica senza aggiungere un altro spaziatore.",
        restarted: "Dock riavviato.",
        addFailed: "Impossibile aggiungere lo spaziatore. Riprova.",
        restartFailed: "Impossibile riavviare il Dock. Riprova."
    )

    static let ja = DockSpacerStrings(
        title: "Dockのスペーサー",
        description: "アプリの間に空白を追加します。Dockを再起動した後、スペーサーをドラッグして並べ替えたり、Dockの外へドラッグして削除したりできます。",
        addLarge: "大きいスペーサーを追加",
        addSmall: "小さいスペーサーを追加",
        restart: "Dockを再起動",
        restartAfterAdding: "スペーサーの追加後にDockを再起動",
        restartCaption: "追加したスペーサーを表示するには、自動で、または「Dockを再起動」で再起動します。Dockが一時的に非表示になります。",
        largeAdded: "大きいスペーサーを追加しました。Dockを再起動すると表示されます。",
        smallAdded: "小さいスペーサーを追加しました。Dockを再起動すると表示されます。",
        largeAddedAndRestarted: "大きいスペーサーを追加し、Dockを再起動しました。",
        smallAddedAndRestarted: "小さいスペーサーを追加し、Dockを再起動しました。",
        addedButRestartFailed: "スペーサーを追加しましたが、Dockを再起動できませんでした。「Dockを再起動」を使うと、別のスペーサーを追加せずに反映できます。",
        restarted: "Dockを再起動しました。",
        addFailed: "スペーサーを追加できませんでした。もう一度お試しください。",
        restartFailed: "Dockを再起動できませんでした。もう一度お試しください。"
    )

    static let ko = DockSpacerStrings(
        title: "Dock 공백",
        description: "앱 사이에 빈 공간을 추가합니다. Dock을 재시작한 후 공백을 드래그하여 배치하거나 Dock 밖으로 드래그하여 제거할 수 있습니다.",
        addLarge: "큰 공백 추가",
        addSmall: "작은 공백 추가",
        restart: "Dock 재시작",
        restartAfterAdding: "공백 추가 후 Dock 재시작",
        restartCaption: "새로 추가한 공백을 표시하려면 자동으로 또는 Dock 재시작 버튼으로 재시작하세요. Dock이 잠시 숨겨집니다.",
        largeAdded: "큰 공백을 추가했습니다. 표시하려면 Dock을 재시작하세요.",
        smallAdded: "작은 공백을 추가했습니다. 표시하려면 Dock을 재시작하세요.",
        largeAddedAndRestarted: "큰 공백을 추가하고 Dock을 재시작했습니다.",
        smallAddedAndRestarted: "작은 공백을 추가하고 Dock을 재시작했습니다.",
        addedButRestartFailed: "공백을 추가했지만 Dock을 재시작하지 못했습니다. 다른 공백을 추가하지 않고 적용하려면 Dock 재시작을 사용하세요.",
        restarted: "Dock을 재시작했습니다.",
        addFailed: "공백을 추가하지 못했습니다. 다시 시도하세요.",
        restartFailed: "Dock을 재시작하지 못했습니다. 다시 시도하세요."
    )

    static let uk = DockSpacerStrings(
        title: "Роздільник Dock",
        description: "Додавайте порожнє місце між програмами. Після перезапуску Dock перетягуйте роздільники, щоб упорядкувати їх, або витягуйте за межі Dock, щоб видалити.",
        addLarge: "Додати великий роздільник",
        addSmall: "Додати малий роздільник",
        restart: "Перезапустити Dock",
        restartAfterAdding: "Перезапускати Dock після додавання роздільника",
        restartCaption: "Щоб побачити нові роздільники, перезапустіть Dock автоматично або кнопкою «Перезапустити Dock». Dock ненадовго зникне.",
        largeAdded: "Великий роздільник додано. Перезапустіть Dock, щоб побачити його.",
        smallAdded: "Малий роздільник додано. Перезапустіть Dock, щоб побачити його.",
        largeAddedAndRestarted: "Великий роздільник додано, Dock перезапущено.",
        smallAddedAndRestarted: "Малий роздільник додано, Dock перезапущено.",
        addedButRestartFailed: "Роздільник додано, але не вдалося перезапустити Dock. Натисніть «Перезапустити Dock», щоб застосувати зміну, не додаючи ще один роздільник.",
        restarted: "Dock перезапущено.",
        addFailed: "Не вдалося додати роздільник. Спробуйте ще раз.",
        restartFailed: "Не вдалося перезапустити Dock. Спробуйте ще раз."
    )

    static let zhHans = DockSpacerStrings(
        title: "程序坞空白间隔",
        description: "在 App 之间添加空白间隔。重新启动程序坞后，可拖动间隔来调整位置，或将其拖出程序坞以移除。",
        addLarge: "添加大间隔",
        addSmall: "添加小间隔",
        restart: "重新启动程序坞",
        restartAfterAdding: "添加间隔后重新启动程序坞",
        restartCaption: "自动重新启动或使用“重新启动程序坞”来显示新添加的间隔。程序坞会短暂隐藏。",
        largeAdded: "已添加大间隔。重新启动程序坞即可显示。",
        smallAdded: "已添加小间隔。重新启动程序坞即可显示。",
        largeAddedAndRestarted: "已添加大间隔并重新启动程序坞。",
        smallAddedAndRestarted: "已添加小间隔并重新启动程序坞。",
        addedButRestartFailed: "已添加间隔，但无法重新启动程序坞。请使用“重新启动程序坞”使其生效，无需再次添加间隔。",
        restarted: "程序坞已重新启动。",
        addFailed: "无法添加间隔。请重试。",
        restartFailed: "无法重新启动程序坞。请重试。"
    )

    static let zhTW = DockSpacerStrings(
        title: "Dock 空白間隔",
        description: "在 App 之間加入空白間隔。重新啟動 Dock 後，可拖移間隔來調整位置，或將其拖出 Dock 來移除。",
        addLarge: "加入大間隔",
        addSmall: "加入小間隔",
        restart: "重新啟動 Dock",
        restartAfterAdding: "加入間隔後重新啟動 Dock",
        restartCaption: "自動重新啟動或使用「重新啟動 Dock」來顯示新加入的間隔。Dock 會暫時隱藏。",
        largeAdded: "已加入大間隔。重新啟動 Dock 即可顯示。",
        smallAdded: "已加入小間隔。重新啟動 Dock 即可顯示。",
        largeAddedAndRestarted: "已加入大間隔並重新啟動 Dock。",
        smallAddedAndRestarted: "已加入小間隔並重新啟動 Dock。",
        addedButRestartFailed: "已加入間隔，但無法重新啟動 Dock。請使用「重新啟動 Dock」來套用變更，無需再加入另一個間隔。",
        restarted: "Dock 已重新啟動。",
        addFailed: "無法加入間隔。請再試一次。",
        restartFailed: "無法重新啟動 Dock。請再試一次。"
    )

    static let zhHK = DockSpacerStrings(
        title: "Dock 空白間隔",
        description: "在 App 之間加入空白間隔。重新啟動 Dock 後，可拖移間隔來調整位置，或將其拖出 Dock 來移除。",
        addLarge: "加入大間隔",
        addSmall: "加入小間隔",
        restart: "重新啟動 Dock",
        restartAfterAdding: "加入間隔後重新啟動 Dock",
        restartCaption: "自動重新啟動或使用「重新啟動 Dock」來顯示新加入的間隔。Dock 會短暫隱藏。",
        largeAdded: "已加入大間隔。重新啟動 Dock 即可顯示。",
        smallAdded: "已加入小間隔。重新啟動 Dock 即可顯示。",
        largeAddedAndRestarted: "已加入大間隔並重新啟動 Dock。",
        smallAddedAndRestarted: "已加入小間隔並重新啟動 Dock。",
        addedButRestartFailed: "已加入間隔，但無法重新啟動 Dock。請使用「重新啟動 Dock」來套用變更，毋須再加入另一個間隔。",
        restarted: "Dock 已重新啟動。",
        addFailed: "無法加入間隔。請再試一次。",
        restartFailed: "無法重新啟動 Dock。請再試一次。"
    )
}
