// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// The companion's character packs, on its Settings page.
struct NotchCompanionStrings {
    /// The style, and the row of packs to choose from.
    let character: String
    let characterHint: String
    /// No pack in the Companions folder.
    let empty: String
    let add: String
    let openFolder: String
    let reload: String
    /// A pack that can't be read, with the reason in its tooltip.
    let unusable: String
    let addFailed: String
    /// Starts drawing a new character with Codex.
    let generate: String
    let generateTitle: String
    let subject: String
    let subjectPlaceholder: String
    let look: String
    let illustration: String
    let anime: String
    let render: String
    let painterly: String
    let generateHint: String
    let start: String
    let cancel: String
    /// While Codex draws: the subject, and how many images are done.
    let drawing: String
    let images: String
    let needsCodex: String
    let generateFailed: String
    let generated: String
    /// Codex is there, but Swift is not.
    let needsTools: String

    func style(_ style: NotchCompanionGenerator.Style) -> String {
        switch style {
        case .illustration: return illustration
        case .anime: return anime
        case .render: return render
        case .painterly: return painterly
        }
    }
}

extension FeatureStrings {
    static func notchCompanion(_ language: AppLanguage) -> NotchCompanionStrings {
        switch language {
        case .enUS: return NotchCompanionStrings(
            character: "Character",
            characterHint: "An animated face of your own: a folder with a companion.json and its frames, in the Companions folder.",
            empty: "No characters yet. Add a folder, or put one in the Companions folder.",
            add: "Add…", openFolder: "Open Folder", reload: "Reload",
            unusable: "Can’t be used", addFailed: "This folder couldn’t be added",
            generate: "Generate…",
            generateTitle: "Generate a character",
            subject: "Who should it be?",
            subjectPlaceholder: "A sleepy fox, a cheerful robot, my cat Mochi…",
            look: "Look",
            illustration: "Illustration",
            anime: "Anime",
            render: "3D",
            painterly: "Painted",
            generateHint: "Codex draws the face and its expressions with image generation. It takes 10–20 minutes and uses your Codex plan.",
            start: "Generate",
            cancel: "Cancel",
            drawing: "Drawing %@",
            images: "%d of %d images",
            needsCodex: "Generating needs the Codex command line, signed in.",
            generateFailed: "Couldn’t generate the character",
            generated: "%@ is ready.",
            needsTools: "Generating also needs Apple’s Command Line Tools. Install them with “xcode-select --install” in Terminal.")
        case .ptBR: return NotchCompanionStrings(
            character: "Personagem",
            characterHint: "Um rosto animado só seu: uma pasta com um companion.json e seus quadros, na pasta Companions.",
            empty: "Nenhum personagem ainda. Adicione uma pasta ou coloque uma na pasta Companions.",
            add: "Adicionar…", openFolder: "Abrir pasta", reload: "Recarregar",
            unusable: "Não pode ser usado", addFailed: "Não foi possível adicionar esta pasta",
            generate: "Gerar…",
            generateTitle: "Gerar um personagem",
            subject: "Quem deve ser?",
            subjectPlaceholder: "Uma raposa sonolenta, um robô alegre, meu gato Mochi…",
            look: "Visual",
            illustration: "Ilustração",
            anime: "Anime",
            render: "3D",
            painterly: "Pintura",
            generateHint: "O Codex desenha o rosto e as expressões com geração de imagens. Leva de 10 a 20 minutos e usa seu plano do Codex.",
            start: "Gerar",
            cancel: "Cancelar",
            drawing: "Desenhando %@",
            images: "%d de %d imagens",
            needsCodex: "Para gerar, é preciso a linha de comando do Codex com login feito.",
            generateFailed: "Não foi possível gerar o personagem",
            generated: "%@ está pronto.",
            needsTools: "Gerar também requer as Command Line Tools da Apple. Instale-as com “xcode-select --install” no Terminal.")
        case .tr: return NotchCompanionStrings(
            character: "Karakter",
            characterHint: "Size ait hareketli bir yüz: Companions klasöründe companion.json ve kareleri bulunan bir klasör.",
            empty: "Henüz karakter yok. Bir klasör ekleyin ya da Companions klasörüne koyun.",
            add: "Ekle…", openFolder: "Klasörü Aç", reload: "Yeniden Yükle",
            unusable: "Kullanılamıyor", addFailed: "Bu klasör eklenemedi",
            generate: "Oluştur…",
            generateTitle: "Karakter oluştur",
            subject: "Kim olsun?",
            subjectPlaceholder: "Uykulu bir tilki, neşeli bir robot, kedim Mochi…",
            look: "Görünüm",
            illustration: "İllüstrasyon",
            anime: "Anime",
            render: "3B",
            painterly: "Resim",
            generateHint: "Codex yüzü ve ifadelerini görsel üretimle çizer. 10–20 dakika sürer ve Codex planınızı kullanır.",
            start: "Oluştur",
            cancel: "İptal",
            drawing: "%@ çiziliyor",
            images: "%d / %d görsel",
            needsCodex: "Oluşturmak için oturum açılmış Codex komut satırı gerekir.",
            generateFailed: "Karakter oluşturulamadı",
            generated: "%@ hazır.",
            needsTools: "Oluşturmak için Apple Command Line Tools da gerekir. Terminal’de “xcode-select --install” ile yükleyin.")
        case .ru: return NotchCompanionStrings(
            character: "Персонаж",
            characterHint: "Ваше собственное анимированное лицо: папка с companion.json и кадрами в папке Companions.",
            empty: "Персонажей пока нет. Добавьте папку или положите её в папку Companions.",
            add: "Добавить…", openFolder: "Открыть папку", reload: "Обновить",
            unusable: "Не удаётся загрузить", addFailed: "Не удалось добавить эту папку",
            generate: "Создать…",
            generateTitle: "Создать персонажа",
            subject: "Кто это будет?",
            subjectPlaceholder: "Сонная лиса, весёлый робот, мой кот Моти…",
            look: "Стиль",
            illustration: "Иллюстрация",
            anime: "Аниме",
            render: "3D",
            painterly: "Живопись",
            generateHint: "Codex нарисует лицо и его выражения с помощью генерации изображений. Это занимает 10–20 минут и расходует лимиты вашего плана Codex.",
            start: "Создать",
            cancel: "Отменить",
            drawing: "Рисую: %@",
            images: "%d из %d изображений",
            needsCodex: "Для создания нужна командная строка Codex с выполненным входом.",
            generateFailed: "Не удалось создать персонажа",
            generated: "Готово: %@.",
            needsTools: "Для создания также нужны Apple Command Line Tools. Установите их командой «xcode-select --install» в Терминале.")
        case .es: return NotchCompanionStrings(
            character: "Personaje",
            characterHint: "Una cara animada propia: una carpeta con un companion.json y sus fotogramas, en la carpeta Companions.",
            empty: "Aún no hay personajes. Añade una carpeta o pon una en la carpeta Companions.",
            add: "Añadir…", openFolder: "Abrir carpeta", reload: "Recargar",
            unusable: "No se puede usar", addFailed: "No se pudo añadir esta carpeta",
            generate: "Generar…",
            generateTitle: "Generar un personaje",
            subject: "¿Quién será?",
            subjectPlaceholder: "Un zorro dormilón, un robot alegre, mi gato Mochi…",
            look: "Estilo",
            illustration: "Ilustración",
            anime: "Anime",
            render: "3D",
            painterly: "Pintura",
            generateHint: "Codex dibuja la cara y sus expresiones con generación de imágenes. Tarda de 10 a 20 minutos y usa tu plan de Codex.",
            start: "Generar",
            cancel: "Cancelar",
            drawing: "Dibujando: %@",
            images: "%d de %d imágenes",
            needsCodex: "Para generar hace falta la línea de comandos de Codex con la sesión iniciada.",
            generateFailed: "No se pudo generar el personaje",
            generated: "%@ está listo.",
            needsTools: "Para generar también se necesitan las Command Line Tools de Apple. Instálalas con «xcode-select --install» en Terminal.")
        case .sk: return NotchCompanionStrings(
            character: "Postavička",
            characterHint: "Vlastná animovaná tvár: priečinok so súborom companion.json a jeho snímkami v priečinku Companions.",
            empty: "Zatiaľ žiadne postavičky. Pridajte priečinok alebo ho vložte do priečinka Companions.",
            add: "Pridať…", openFolder: "Otvoriť priečinok", reload: "Znova načítať",
            unusable: "Nedá sa použiť", addFailed: "Tento priečinok sa nepodarilo pridať",
            generate: "Vytvoriť…",
            generateTitle: "Vytvoriť postavičku",
            subject: "Kto to bude?",
            subjectPlaceholder: "Ospalá líška, veselý robot, moja mačka Mochi…",
            look: "Vzhľad",
            illustration: "Ilustrácia",
            anime: "Anime",
            render: "3D",
            painterly: "Maľba",
            generateHint: "Codex nakreslí tvár a jej výrazy pomocou generovania obrázkov. Trvá to 10 – 20 minút a čerpá z vášho plánu Codex.",
            start: "Vytvoriť",
            cancel: "Zrušiť",
            drawing: "Kreslí sa: %@",
            images: "%d z %d obrázkov",
            needsCodex: "Na vytváranie je potrebný príkazový riadok Codex s prihlásením.",
            generateFailed: "Postavičku sa nepodarilo vytvoriť",
            generated: "Hotovo: %@.",
            needsTools: "Na vytváranie sú potrebné aj Apple Command Line Tools. Nainštalujte ich príkazom „xcode-select --install“ v Termináli.")
        case .de: return NotchCompanionStrings(
            character: "Figur",
            characterHint: "Ein eigenes animiertes Gesicht: ein Ordner mit einer companion.json und ihren Bildern im Ordner „Companions“.",
            empty: "Noch keine Figuren. Füge einen Ordner hinzu oder lege einen in den Ordner „Companions“.",
            add: "Hinzufügen…", openFolder: "Ordner öffnen", reload: "Neu laden",
            unusable: "Nicht verwendbar", addFailed: "Dieser Ordner konnte nicht hinzugefügt werden",
            generate: "Erstellen…",
            generateTitle: "Figur erstellen",
            subject: "Wer soll es sein?",
            subjectPlaceholder: "Ein verschlafener Fuchs, ein fröhlicher Roboter, meine Katze Mochi…",
            look: "Stil",
            illustration: "Illustration",
            anime: "Anime",
            render: "3D",
            painterly: "Gemalt",
            generateHint: "Codex zeichnet das Gesicht und seine Ausdrücke mit Bildgenerierung. Das dauert 10–20 Minuten und nutzt dein Codex-Abo.",
            start: "Erstellen",
            cancel: "Abbrechen",
            drawing: "Zeichne: %@",
            images: "%d von %d Bildern",
            needsCodex: "Zum Erstellen wird die angemeldete Codex-Befehlszeile benötigt.",
            generateFailed: "Die Figur konnte nicht erstellt werden",
            generated: "%@ ist fertig.",
            needsTools: "Zum Erstellen werden auch Apples Command Line Tools benötigt. Installiere sie mit „xcode-select --install“ im Terminal.")
        case .fr: return NotchCompanionStrings(
            character: "Personnage",
            characterHint: "Un visage animé bien à vous : un dossier avec un companion.json et ses images, dans le dossier Companions.",
            empty: "Aucun personnage pour l’instant. Ajoutez un dossier ou placez-en un dans le dossier Companions.",
            add: "Ajouter…", openFolder: "Ouvrir le dossier", reload: "Recharger",
            unusable: "Inutilisable", addFailed: "Impossible d’ajouter ce dossier",
            generate: "Générer…",
            generateTitle: "Générer un personnage",
            subject: "Qui sera-t-il ?",
            subjectPlaceholder: "Un renard endormi, un robot joyeux, mon chat Mochi…",
            look: "Style",
            illustration: "Illustration",
            anime: "Anime",
            render: "3D",
            painterly: "Peinture",
            generateHint: "Codex dessine le visage et ses expressions par génération d’images. Cela prend 10 à 20 minutes et utilise votre forfait Codex.",
            start: "Générer",
            cancel: "Annuler",
            drawing: "Dessin : %@",
            images: "%d images sur %d",
            needsCodex: "Pour générer, il faut la ligne de commande Codex, connectée.",
            generateFailed: "Impossible de générer le personnage",
            generated: "%@ est prêt.",
            needsTools: "La génération nécessite aussi les Command Line Tools d’Apple. Installez-les avec « xcode-select --install » dans Terminal.")
        case .it: return NotchCompanionStrings(
            character: "Personaggio",
            characterHint: "Un volto animato tutto tuo: una cartella con un companion.json e i suoi fotogrammi, nella cartella Companions.",
            empty: "Ancora nessun personaggio. Aggiungi una cartella o mettine una nella cartella Companions.",
            add: "Aggiungi…", openFolder: "Apri cartella", reload: "Ricarica",
            unusable: "Non utilizzabile", addFailed: "Impossibile aggiungere questa cartella",
            generate: "Genera…",
            generateTitle: "Genera un personaggio",
            subject: "Chi sarà?",
            subjectPlaceholder: "Una volpe assonnata, un robot allegro, il mio gatto Mochi…",
            look: "Stile",
            illustration: "Illustrazione",
            anime: "Anime",
            render: "3D",
            painterly: "Dipinto",
            generateHint: "Codex disegna il volto e le sue espressioni con la generazione di immagini. Richiede 10–20 minuti e usa il tuo piano Codex.",
            start: "Genera",
            cancel: "Annulla",
            drawing: "Disegno: %@",
            images: "%d di %d immagini",
            needsCodex: "Per generare serve la riga di comando di Codex con accesso effettuato.",
            generateFailed: "Impossibile generare il personaggio",
            generated: "%@ è pronto.",
            needsTools: "Per generare servono anche i Command Line Tools di Apple. Installali con «xcode-select --install» nel Terminale.")
        case .ja: return NotchCompanionStrings(
            character: "キャラクター",
            characterHint: "自分だけのアニメーションする顔：Companions フォルダ内の、companion.json とフレーム画像を含むフォルダです。",
            empty: "キャラクターはまだありません。フォルダを追加するか、Companions フォルダに入れてください。",
            add: "追加…", openFolder: "フォルダを開く", reload: "再読み込み",
            unusable: "使用できません", addFailed: "このフォルダを追加できませんでした",
            generate: "生成…",
            generateTitle: "キャラクターを生成",
            subject: "誰にしますか？",
            subjectPlaceholder: "眠そうなキツネ、陽気なロボット、うちの猫のもち…",
            look: "画風",
            illustration: "イラスト",
            anime: "アニメ",
            render: "3D",
            painterly: "絵画風",
            generateHint: "Codex が画像生成で顔と表情を描きます。10〜20 分かかり、Codex のプランを使用します。",
            start: "生成",
            cancel: "キャンセル",
            drawing: "%@ を描いています",
            images: "%d / %d 枚",
            needsCodex: "生成するには、サインイン済みの Codex コマンドラインが必要です。",
            generateFailed: "キャラクターを生成できませんでした",
            generated: "%@ の準備ができました。",
            needsTools: "生成には Apple の Command Line Tools も必要です。ターミナルで「xcode-select --install」を実行してインストールしてください。")
        case .ko: return NotchCompanionStrings(
            character: "캐릭터",
            characterHint: "나만의 움직이는 얼굴: Companions 폴더 안에 companion.json과 프레임이 담긴 폴더입니다.",
            empty: "아직 캐릭터가 없습니다. 폴더를 추가하거나 Companions 폴더에 넣으세요.",
            add: "추가…", openFolder: "폴더 열기", reload: "새로고침",
            unusable: "사용할 수 없음", addFailed: "이 폴더를 추가할 수 없습니다",
            generate: "생성…",
            generateTitle: "캐릭터 생성",
            subject: "누구로 할까요?",
            subjectPlaceholder: "졸린 여우, 명랑한 로봇, 우리 고양이 모찌…",
            look: "스타일",
            illustration: "일러스트",
            anime: "애니메이션",
            render: "3D",
            painterly: "페인팅",
            generateHint: "Codex가 이미지 생성으로 얼굴과 표정을 그립니다. 10~20분이 걸리며 Codex 요금제를 사용합니다.",
            start: "생성",
            cancel: "취소",
            drawing: "%@ 그리는 중",
            images: "%d / %d 이미지",
            needsCodex: "생성하려면 로그인된 Codex 명령줄이 필요합니다.",
            generateFailed: "캐릭터를 생성할 수 없습니다",
            generated: "%@ 준비 완료.",
            needsTools: "생성하려면 Apple Command Line Tools도 필요합니다. 터미널에서 “xcode-select --install”로 설치하세요.")
        case .uk: return NotchCompanionStrings(
            character: "Персонаж",
            characterHint: "Ваше власне анімоване обличчя: тека з companion.json і кадрами в теці Companions.",
            empty: "Персонажів поки немає. Додайте теку або покладіть її в теку Companions.",
            add: "Додати…", openFolder: "Відкрити теку", reload: "Оновити",
            unusable: "Не вдається завантажити", addFailed: "Не вдалося додати цю теку",
            generate: "Створити…",
            generateTitle: "Створити персонажа",
            subject: "Ким він буде?",
            subjectPlaceholder: "Сонна лисиця, веселий робот, мій кіт Мочі…",
            look: "Стиль",
            illustration: "Ілюстрація",
            anime: "Аніме",
            render: "3D",
            painterly: "Живопис",
            generateHint: "Codex намалює обличчя та його вирази за допомогою генерації зображень. Це триває 10–20 хвилин і використовує ліміти вашого плану Codex.",
            start: "Створити",
            cancel: "Скасувати",
            drawing: "Малюю: %@",
            images: "%d з %d зображень",
            needsCodex: "Для створення потрібен командний рядок Codex із виконаним входом.",
            generateFailed: "Не вдалося створити персонажа",
            generated: "Готово: %@.",
            needsTools: "Для створення також потрібні Apple Command Line Tools. Установіть їх командою «xcode-select --install» у Терміналі.")
        case .zhHans: return NotchCompanionStrings(
            character: "角色",
            characterHint: "属于你的动画面孔：Companions 文件夹中包含 companion.json 及其帧图像的文件夹。",
            empty: "还没有角色。添加一个文件夹，或将其放入 Companions 文件夹。",
            add: "添加…", openFolder: "打开文件夹", reload: "重新载入",
            unusable: "无法使用", addFailed: "无法添加此文件夹",
            generate: "生成…",
            generateTitle: "生成角色",
            subject: "要谁？",
            subjectPlaceholder: "困倦的狐狸、开朗的机器人、我的猫麻糬…",
            look: "画风",
            illustration: "插画",
            anime: "动漫",
            render: "3D",
            painterly: "绘画",
            generateHint: "Codex 会用图像生成绘制面孔及其表情。需要 10–20 分钟，并会使用你的 Codex 套餐。",
            start: "生成",
            cancel: "取消",
            drawing: "正在绘制 %@",
            images: "%d / %d 张图像",
            needsCodex: "生成需要已登录的 Codex 命令行。",
            generateFailed: "无法生成角色",
            generated: "%@ 已就绪。",
            needsTools: "生成还需要 Apple 的 Command Line Tools。请在“终端”中运行“xcode-select --install”进行安装。")
        case .zhTW: return NotchCompanionStrings(
            character: "角色",
            characterHint: "屬於你的動畫臉孔：Companions 檔案夾中含有 companion.json 及其影格的檔案夾。",
            empty: "還沒有角色。加入一個檔案夾，或將其放進 Companions 檔案夾。",
            add: "加入…", openFolder: "打開檔案夾", reload: "重新載入",
            unusable: "無法使用", addFailed: "無法加入此檔案夾",
            generate: "生成…",
            generateTitle: "生成角色",
            subject: "要誰？",
            subjectPlaceholder: "愛睏的狐狸、開朗的機器人、我的貓麻糬…",
            look: "畫風",
            illustration: "插畫",
            anime: "動漫",
            render: "3D",
            painterly: "繪畫",
            generateHint: "Codex 會以影像生成繪製臉孔及其表情。需要 10–20 分鐘，並會使用你的 Codex 方案。",
            start: "生成",
            cancel: "取消",
            drawing: "正在繪製 %@",
            images: "%d / %d 張影像",
            needsCodex: "生成需要已登入的 Codex 命令列。",
            generateFailed: "無法生成角色",
            generated: "%@ 已準備就緒。",
            needsTools: "生成還需要 Apple 的 Command Line Tools。請在「終端機」中執行「xcode-select --install」來安裝。")
        case .zhHK: return NotchCompanionStrings(
            character: "角色",
            characterHint: "屬於你嘅動畫面孔：Companions 資料夾入面含有 companion.json 同埋影格嘅資料夾。",
            empty: "仲未有角色。加入一個資料夾，或者放入 Companions 資料夾。",
            add: "加入…", openFolder: "打開資料夾", reload: "重新載入",
            unusable: "無法使用", addFailed: "無法加入呢個資料夾",
            generate: "生成…",
            generateTitle: "生成角色",
            subject: "要邊個？",
            subjectPlaceholder: "眼瞓嘅狐狸、開朗嘅機械人、我隻貓麻糬…",
            look: "畫風",
            illustration: "插畫",
            anime: "動漫",
            render: "3D",
            painterly: "繪畫",
            generateHint: "Codex 會用影像生成畫出面孔同表情。需要 10–20 分鐘，並會用你嘅 Codex 計劃。",
            start: "生成",
            cancel: "取消",
            drawing: "正在畫 %@",
            images: "%d / %d 張影像",
            needsCodex: "生成需要已登入嘅 Codex 命令列。",
            generateFailed: "無法生成角色",
            generated: "%@ 準備好喇。",
            needsTools: "生成仲需要 Apple 嘅 Command Line Tools。請喺「終端機」執行「xcode-select --install」嚟安裝。")
        }
    }
}
