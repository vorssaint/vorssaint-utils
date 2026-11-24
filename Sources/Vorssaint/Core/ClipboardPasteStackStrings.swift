// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

struct ClipboardPasteStackStrings {
    let create: String
    let add: String
    let title: String
    let pasteNext: String
    let clear: String

    static func forLanguage(_ language: AppLanguage) -> Self {
        switch language {
        case .enUS:
            return Self(create: "Create Stack", add: "Add to Stack", title: "Paste Stack",
                        pasteNext: "Paste Next", clear: "Clear Stack")
        case .ptBR:
            return Self(create: "Criar pilha", add: "Adicionar à pilha", title: "Pilha para colar",
                        pasteNext: "Colar próximo item", clear: "Limpar pilha")
        case .tr:
            return Self(create: "Yığın oluştur", add: "Yığına ekle", title: "Yapıştırma yığını",
                        pasteNext: "Sıradakini yapıştır", clear: "Yığını temizle")
        case .ru:
            return Self(create: "Создать очередь", add: "Добавить в очередь", title: "Очередь вставки",
                        pasteNext: "Вставить следующий элемент", clear: "Очистить очередь")
        case .es:
            return Self(create: "Crear pila", add: "Añadir a la pila", title: "Pila de pegado",
                        pasteNext: "Pegar el siguiente elemento", clear: "Vaciar pila")
        case .sk:
            return Self(create: "Vytvoriť front", add: "Pridať do frontu", title: "Front vkladania",
                        pasteNext: "Vložiť ďalšiu položku", clear: "Vyprázdniť front")
        case .de:
            return Self(create: "Stapel erstellen", add: "Zum Stapel hinzufügen", title: "Einfügestapel",
                        pasteNext: "Nächstes Objekt einfügen", clear: "Stapel leeren")
        case .fr:
            return Self(create: "Créer une pile", add: "Ajouter à la pile", title: "Pile de collage",
                        pasteNext: "Coller l’élément suivant", clear: "Vider la pile")
        case .it:
            return Self(create: "Crea una pila", add: "Aggiungi alla pila", title: "Pila per incollare",
                        pasteNext: "Incolla l’elemento successivo", clear: "Svuota la pila")
        case .ja:
            return Self(create: "スタックを作成", add: "スタックに追加", title: "ペーストスタック",
                        pasteNext: "次の項目をペースト", clear: "スタックを空にする")
        case .ko:
            return Self(create: "스택 만들기", add: "스택에 추가", title: "붙여넣기 스택",
                        pasteNext: "다음 항목 붙여넣기", clear: "스택 비우기")
        case .uk:
            return Self(create: "Створити чергу", add: "Додати до черги", title: "Черга вставлення",
                        pasteNext: "Вставити наступний елемент", clear: "Очистити чергу")
        case .zhHans:
            return Self(create: "创建粘贴队列", add: "添加到队列", title: "粘贴队列",
                        pasteNext: "粘贴下一项", clear: "清空队列")
        case .zhTW:
            return Self(create: "建立貼上佇列", add: "加入佇列", title: "貼上佇列",
                        pasteNext: "貼上下一項", clear: "清空佇列")
        case .zhHK:
            return Self(create: "建立貼上隊列", add: "加入隊列", title: "貼上隊列",
                        pasteNext: "貼上下一項", clear: "清空隊列")
        }
    }
}
