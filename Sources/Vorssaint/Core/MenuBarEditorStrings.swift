// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

struct MenuBarEditorStrings {
    let previewPermission: String
    let removalFailed: String
    let inventory: String
    let visible: String
    let hidden: String
    let alwaysHidden: String
    let drop: String
    let locked: String
    let unavailable: String
}

extension FeatureStrings {
    static func menuBarEditor(_ language: AppLanguage) -> MenuBarEditorStrings {
        switch language {
        case .enUS: return MenuBarEditorStrings(
            previewPermission: "Allow Screen Recording to show the actual menu-bar icons. Previews stay on this Mac; arranging icons only needs Accessibility.",
            removalFailed: "The previous icon spacing could not be restored. The feature remains installed so you can retry Restore.",
            inventory: "Menu-bar items from running apps appear here. Drag an icon between groups, or right-click to move it.",
            visible: "Always shown in the menu bar.",
            hidden: "Shown and hidden with ○.",
            alwaysHidden: "Stays concealed until moved to another group.",
            drop: "Drop icons here",
            locked: "This item cannot be moved.",
            unavailable: "Menu-bar items could not be read. Grant Accessibility if needed, then click Refresh."
        )
        case .ptBR: return MenuBarEditorStrings(
            previewPermission: "Permita Gravação de Tela para mostrar os ícones reais da barra de menus. As prévias ficam neste Mac; organizar ícones só exige Acessibilidade.",
            removalFailed: "Não foi possível restaurar o espaçamento anterior. O recurso continua instalado para você tentar Restaurar novamente.",
            inventory: "Aqui aparecem os itens dos apps em execução. Arraste um ícone entre os grupos ou clique com o botão direito para movê-lo.",
            visible: "Sempre visíveis na barra de menus.",
            hidden: "Mostrados e ocultados com ○.",
            alwaysHidden: "Permanecem ocultos até serem movidos para outro grupo.",
            drop: "Solte ícones aqui",
            locked: "Este item não pode ser movido.",
            unavailable: "Não foi possível ler os itens. Permita Acessibilidade se necessário e clique em Atualizar."
        )
        case .ru: return MenuBarEditorStrings(
            previewPermission: "Разрешите запись экрана, чтобы видеть настоящие значки строки меню. Изображения остаются на этом Mac; для перемещения достаточно Универсального доступа.",
            removalFailed: "Не удалось восстановить прежний интервал значков. Функция остаётся установленной, чтобы можно было повторить восстановление.",
            inventory: "Здесь показаны значки работающих приложений. Перетащите значок в другую группу или выберите её в контекстном меню.",
            visible: "Всегда видны в строке меню.",
            hidden: "Показываются и скрываются кнопкой ○.",
            alwaysHidden: "Остаются скрытыми до переноса в другую группу.",
            drop: "Перетащите значки сюда",
            locked: "Этот значок нельзя переместить.",
            unavailable: "Не удалось прочитать значки. При необходимости разрешите Универсальный доступ и нажмите «Обновить»."
        )
        case .uk: return MenuBarEditorStrings(
            previewPermission: "Дозвольте запис екрана, щоб бачити справжні значки смуги меню. Зображення залишаються на цьому Mac; для переміщення достатньо Доступності.",
            removalFailed: "Не вдалося відновити попередній інтервал значків. Функція залишається встановленою, щоб ви могли повторити відновлення.",
            inventory: "Тут показано значки запущених програм. Перетягніть значок між групами або виберіть групу в контекстному меню.",
            visible: "Завжди видимі в смузі меню.",
            hidden: "Показуються та приховуються кнопкою ○.",
            alwaysHidden: "Залишаються прихованими до перенесення в іншу групу.",
            drop: "Перетягніть значки сюди",
            locked: "Цей значок не можна перемістити.",
            unavailable: "Не вдалося прочитати значки. За потреби надайте Доступність і натисніть «Оновити»."
        )
        case .es: return MenuBarEditorStrings(
            previewPermission: "Permite Grabación de pantalla para mostrar los iconos reales. Las vistas previas permanecen en este Mac; ordenarlos solo requiere Accesibilidad.",
            removalFailed: "No se pudo restaurar el espaciado anterior. La función sigue instalada para que puedas volver a restaurarlo.",
            inventory: "Aquí aparecen los iconos de las apps en ejecución. Arrástralos entre grupos o haz clic derecho para moverlos.",
            visible: "Siempre visibles en la barra de menús.",
            hidden: "Se muestran y ocultan con ○.",
            alwaysHidden: "Permanecen ocultos hasta moverlos a otro grupo.",
            drop: "Suelta iconos aquí",
            locked: "Este elemento no se puede mover.",
            unavailable: "No se pudieron leer los iconos. Permite Accesibilidad si es necesario y pulsa Actualizar."
        )
        case .de: return MenuBarEditorStrings(
            previewPermission: "Erlaube Bildschirmaufnahme, um die tatsächlichen Menüleistensymbole zu sehen. Vorschauen bleiben auf diesem Mac; zum Anordnen reichen Bedienungshilfen.",
            removalFailed: "Der vorherige Symbolabstand konnte nicht wiederhergestellt werden. Die Funktion bleibt installiert, damit du es erneut versuchen kannst.",
            inventory: "Hier erscheinen Menüleistensymbole laufender Apps. Ziehe ein Symbol in eine Gruppe oder verschiebe es per Rechtsklick.",
            visible: "Immer in der Menüleiste sichtbar.",
            hidden: "Mit ○ ein- und ausblenden.",
            alwaysHidden: "Bleiben verborgen, bis sie in eine andere Gruppe verschoben werden.",
            drop: "Symbole hier ablegen",
            locked: "Dieses Symbol kann nicht verschoben werden.",
            unavailable: "Die Symbole konnten nicht gelesen werden. Erlaube bei Bedarf Bedienungshilfen und klicke auf Aktualisieren."
        )
        case .fr: return MenuBarEditorStrings(
            previewPermission: "Autorisez Enregistrement de l’écran pour afficher les vraies icônes. Les aperçus restent sur ce Mac ; seule Accessibilité est nécessaire pour les déplacer.",
            removalFailed: "Impossible de rétablir l’espacement précédent. La fonction reste installée pour vous permettre de réessayer.",
            inventory: "Les icônes des apps en cours apparaissent ici. Glissez une icône entre les groupes ou déplacez-la par clic droit.",
            visible: "Toujours visibles dans la barre des menus.",
            hidden: "Affichées et masquées avec ○.",
            alwaysHidden: "Restent masquées jusqu’à leur déplacement vers un autre groupe.",
            drop: "Déposez les icônes ici",
            locked: "Cet élément ne peut pas être déplacé.",
            unavailable: "Impossible de lire les icônes. Autorisez Accessibilité si nécessaire, puis actualisez."
        )
        case .it: return MenuBarEditorStrings(
            previewPermission: "Consenti Registrazione schermo per vedere le icone reali. Le anteprime restano su questo Mac; per riordinarle basta Accessibilità.",
            removalFailed: "Impossibile ripristinare la spaziatura precedente. La funzione resta installata per consentire un nuovo tentativo.",
            inventory: "Qui appaiono le icone delle app in esecuzione. Trascina un’icona tra i gruppi o spostala con un clic destro.",
            visible: "Sempre visibili nella barra dei menu.",
            hidden: "Mostrate e nascoste con ○.",
            alwaysHidden: "Restano nascoste finché non le sposti in un altro gruppo.",
            drop: "Trascina qui le icone",
            locked: "Questo elemento non può essere spostato.",
            unavailable: "Impossibile leggere le icone. Consenti Accessibilità se necessario, poi aggiorna."
        )
        case .sk: return MenuBarEditorStrings(
            previewPermission: "Povoľte nahrávanie obrazovky pre skutočné ikony lišty. Náhľady zostávajú na tomto Macu; na usporiadanie stačí Prístupnosť.",
            removalFailed: "Predchádzajúce rozostupy ikon sa nepodarilo obnoviť. Funkcia zostáva nainštalovaná, aby ste mohli obnovenie skúsiť znova.",
            inventory: "Tu sa zobrazujú ikony spustených aplikácií. Presuňte ikonu medzi skupinami alebo použite pravé tlačidlo myši.",
            visible: "Vždy viditeľné v lište menu.",
            hidden: "Zobrazujú a skrývajú sa pomocou ○.",
            alwaysHidden: "Zostanú skryté, kým ich nepresuniete do inej skupiny.",
            drop: "Presuňte sem ikony",
            locked: "Túto položku nemožno presunúť.",
            unavailable: "Ikony sa nepodarilo načítať. V prípade potreby povoľte Prístupnosť a obnovte zoznam."
        )
        case .ja: return MenuBarEditorStrings(
            previewPermission: "実際のメニューバーアイコンを表示するには画面収録を許可してください。プレビューはこのMac内に保持され、並べ替えにはアクセシビリティのみが必要です。",
            removalFailed: "以前のアイコン間隔を復元できませんでした。再試行できるよう、この機能はインストールされたままです。",
            inventory: "実行中のアプリのメニューバー項目を表示します。アイコンを別のグループにドラッグするか、右クリックして移動できます。",
            visible: "メニューバーに常に表示します。",
            hidden: "○ で表示・非表示を切り替えます。",
            alwaysHidden: "別のグループに移すまで非表示のままです。",
            drop: "ここにアイコンをドロップ",
            locked: "この項目は移動できません。",
            unavailable: "メニューバー項目を読み取れません。必要に応じてアクセシビリティを許可し、更新してください。"
        )
        case .ko: return MenuBarEditorStrings(
            previewPermission: "실제 메뉴 막대 아이콘을 표시하려면 화면 기록을 허용하세요. 미리보기는 이 Mac에만 유지되며 아이콘 정렬에는 손쉬운 사용 권한만 필요합니다.",
            removalFailed: "이전 아이콘 간격을 복원하지 못했습니다. 다시 복원할 수 있도록 기능은 설치된 상태로 유지됩니다.",
            inventory: "실행 중인 앱의 메뉴 막대 항목이 표시됩니다. 아이콘을 다른 그룹으로 드래그하거나 오른쪽 클릭하여 이동하세요.",
            visible: "메뉴 막대에 항상 표시됩니다.",
            hidden: "○로 표시하거나 숨깁니다.",
            alwaysHidden: "다른 그룹으로 옮길 때까지 숨겨집니다.",
            drop: "여기에 아이콘 놓기",
            locked: "이 항목은 이동할 수 없습니다.",
            unavailable: "메뉴 막대 항목을 읽을 수 없습니다. 필요한 경우 손쉬운 사용을 허용한 후 새로 고침하세요."
        )
        case .zhHans: return MenuBarEditorStrings(
            previewPermission: "允许屏幕录制以显示真实的菜单栏图标。预览仅保留在此 Mac 上；排列图标只需要辅助功能权限。",
            removalFailed: "无法恢复原来的图标间距。此功能将保留安装，以便您重试恢复。",
            inventory: "这里显示正在运行的应用的菜单栏项目。将图标拖到其他分组，或右键点击以移动。",
            visible: "始终显示在菜单栏中。",
            hidden: "通过 ○ 显示或隐藏。",
            alwaysHidden: "移到其他分组前始终保持隐藏。",
            drop: "将图标拖到这里",
            locked: "无法移动此项目。",
            unavailable: "无法读取菜单栏项目。请按需允许辅助功能，然后刷新。"
        )
        case .zhTW: return MenuBarEditorStrings(
            previewPermission: "允許螢幕錄製以顯示實際的選單列圖示。預覽只保留在此 Mac 上；排列圖示只需要輔助使用權限。",
            removalFailed: "無法還原原來的圖示間距。此功能會保持安裝，讓您可以重試還原。",
            inventory: "這裡顯示執行中 App 的選單列項目。將圖示拖到其他群組，或按右鍵移動。",
            visible: "一律顯示在選單列中。",
            hidden: "透過 ○ 顯示或隱藏。",
            alwaysHidden: "移到其他群組前一律保持隱藏。",
            drop: "將圖示拖到這裡",
            locked: "無法移動此項目。",
            unavailable: "無法讀取選單列項目。請視需要允許輔助使用，然後重新整理。"
        )
        case .zhHK: return MenuBarEditorStrings(
            previewPermission: "允許螢幕錄製以顯示實際的選單列圖示。預覽只保留在此 Mac 上；排列圖示只需要輔助使用權限。",
            removalFailed: "無法還原原來的圖示間距。此功能將保持安裝，以便您重試還原。",
            inventory: "這裡顯示執行中 App 的選單列項目。將圖像拖到其他群組，或按右鍵移動。",
            visible: "一律顯示在選單列中。",
            hidden: "透過 ○ 顯示或隱藏。",
            alwaysHidden: "移到其他群組前一律保持隱藏。",
            drop: "將圖像拖到這裡",
            locked: "無法移動此項目。",
            unavailable: "無法讀取選單列項目。請視需要允許輔助使用，然後重新整理。"
        )
        case .tr: return MenuBarEditorStrings(
            previewPermission: "Gerçek menü çubuğu simgelerini görmek için Ekran Kaydı izni verin. Önizlemeler bu Mac’te kalır; düzenlemek için yalnızca Erişilebilirlik gerekir.",
            removalFailed: "Önceki simge aralığı geri yüklenemedi. Yeniden deneyebilmeniz için özellik yüklü kalır.",
            inventory: "Çalışan uygulamaların menü çubuğu simgeleri burada görünür. Bir simgeyi gruplar arasında sürükleyin veya taşımak için sağ tıklayın.",
            visible: "Menü çubuğunda her zaman görünür.",
            hidden: "○ ile gösterilir ve gizlenir.",
            alwaysHidden: "Başka bir gruba taşınana kadar gizli kalır.",
            drop: "Simgeleri buraya bırakın",
            locked: "Bu öğe taşınamaz.",
            unavailable: "Menü çubuğu öğeleri okunamadı. Gerekirse Erişilebilirliğe izin verip Yenile’ye tıklayın."
        )
        }
    }
}
