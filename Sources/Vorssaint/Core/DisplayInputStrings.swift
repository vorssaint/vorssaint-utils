// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

struct DisplayInputStrings {
    let title: String
    let commonCaption: String
    let shortcutTitle: String
    let shortcutCaption: String

    static func localized(_ language: AppLanguage) -> DisplayInputStrings {
        switch language {
        case .enUS: return .init(
            title: "Input source",
            commonCaption: "This monitor did not list its inputs. These are the usual ones.",
            shortcutTitle: "Switch input source",
            shortcutCaption: "Moves the monitor under the pointer to its next ticked input. Monitors cannot report which inputs have a signal, so untick the ones you do not use.")
        case .ptBR: return .init(
            title: "Fonte de entrada",
            commonCaption: "Este monitor não informou suas entradas. Estas são as mais comuns.",
            shortcutTitle: "Trocar fonte de entrada",
            shortcutCaption: "Passa o monitor sob o ponteiro para a próxima entrada marcada. Monitores não informam quais entradas têm sinal, então desmarque as que você não usa.")
        case .tr: return .init(
            title: "Giriş kaynağı",
            commonCaption: "Bu monitör girişlerini bildirmedi. Bunlar yaygın olanlardır.",
            shortcutTitle: "Giriş kaynağını değiştir",
            shortcutCaption: "İşaretçinin altındaki monitörü işaretli bir sonraki girişe geçirir. Monitörler hangi girişte sinyal olduğunu bildiremez; kullanmadıklarınızın işaretini kaldırın.")
        case .ru: return .init(
            title: "Источник сигнала",
            commonCaption: "Монитор не сообщил свои входы. Это наиболее распространённые.",
            shortcutTitle: "Сменить источник сигнала",
            shortcutCaption: "Переключает монитор под указателем на следующий отмеченный вход. Мониторы не сообщают, на каких входах есть сигнал, поэтому снимите отметку с неиспользуемых.")
        case .es: return .init(
            title: "Fuente de entrada",
            commonCaption: "Este monitor no indicó sus entradas. Estas son las habituales.",
            shortcutTitle: "Cambiar fuente de entrada",
            shortcutCaption: "Pasa el monitor bajo el puntero a su siguiente entrada marcada. Los monitores no indican qué entradas tienen señal, así que desmarca las que no uses.")
        case .sk: return .init(
            title: "Zdroj vstupu",
            commonCaption: "Tento monitor neuviedol svoje vstupy. Toto sú tie bežné.",
            shortcutTitle: "Prepnúť zdroj vstupu",
            shortcutCaption: "Prepne monitor pod kurzorom na ďalší zaškrtnutý vstup. Monitory nevedia oznámiť, ktoré vstupy majú signál, preto zrušte zaškrtnutie tých, ktoré nepoužívate.")
        case .de: return .init(
            title: "Eingangsquelle",
            commonCaption: "Dieser Monitor hat seine Eingänge nicht gemeldet. Dies sind die üblichen.",
            shortcutTitle: "Eingangsquelle wechseln",
            shortcutCaption: "Schaltet den Monitor unter dem Zeiger auf seinen nächsten markierten Eingang. Monitore melden nicht, welche Eingänge ein Signal haben, daher ungenutzte Eingänge abwählen.")
        case .fr: return .init(
            title: "Source d’entrée",
            commonCaption: "Ce moniteur n’a pas indiqué ses entrées. Voici les plus courantes.",
            shortcutTitle: "Changer de source d’entrée",
            shortcutCaption: "Passe le moniteur sous le pointeur à sa prochaine entrée cochée. Les moniteurs n’indiquent pas quelles entrées reçoivent un signal : décochez celles que vous n’utilisez pas.")
        case .it: return .init(
            title: "Sorgente di ingresso",
            commonCaption: "Questo monitor non ha indicato i suoi ingressi. Questi sono quelli più comuni.",
            shortcutTitle: "Cambia sorgente di ingresso",
            shortcutCaption: "Passa il monitor sotto il puntatore al prossimo ingresso selezionato. I monitor non indicano quali ingressi hanno segnale, quindi deseleziona quelli che non usi.")
        case .ja: return .init(
            title: "入力ソース",
            commonCaption: "このモニタは入力を報告しませんでした。一般的な入力を表示しています。",
            shortcutTitle: "入力ソースを切り替える",
            shortcutCaption: "ポインタの下にあるモニタを、チェックした次の入力に切り替えます。モニタはどの入力に信号があるかを報告できないため、使わない入力はチェックを外してください。")
        case .ko: return .init(
            title: "입력 소스",
            commonCaption: "이 모니터가 입력 목록을 알려 주지 않았습니다. 일반적인 입력입니다.",
            shortcutTitle: "입력 소스 전환",
            shortcutCaption: "포인터 아래 모니터를 체크된 다음 입력으로 전환합니다. 모니터는 어느 입력에 신호가 있는지 알려 주지 않으므로 사용하지 않는 입력은 체크를 해제하세요.")
        case .uk: return .init(
            title: "Джерело сигналу",
            commonCaption: "Монітор не повідомив свої входи. Це найпоширеніші.",
            shortcutTitle: "Змінити джерело сигналу",
            shortcutCaption: "Перемикає монітор під вказівником на наступний позначений вхід. Монітори не повідомляють, на яких входах є сигнал, тож зніміть позначку з невикористовуваних.")
        case .zhHans: return .init(
            title: "输入源",
            commonCaption: "此显示器未报告其输入端口，以下为常见端口。",
            shortcutTitle: "切换输入源",
            shortcutCaption: "将指针所在的显示器切换到下一个已勾选的输入端口。显示器无法报告哪些端口有信号，请取消勾选不用的端口。")
        case .zhTW: return .init(
            title: "輸入來源",
            commonCaption: "此顯示器未回報其輸入埠，以下為常見的輸入埠。",
            shortcutTitle: "切換輸入來源",
            shortcutCaption: "將指標所在的顯示器切換到下一個已勾選的輸入埠。顯示器無法回報哪些輸入埠有訊號，請取消勾選不使用的輸入埠。")
        case .zhHK: return .init(
            title: "輸入來源",
            commonCaption: "此顯示器未有報告其輸入埠，以下為常見的輸入埠。",
            shortcutTitle: "切換輸入來源",
            shortcutCaption: "將指標所在的顯示器切換到下一個已剔選的輸入埠。顯示器無法報告哪些輸入埠有訊號，請取消剔選不使用的輸入埠。")
        }
    }
}
