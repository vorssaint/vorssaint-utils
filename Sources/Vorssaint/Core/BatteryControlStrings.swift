// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// User-facing strings for the battery charge limit. Self-contained like the
/// other feature string files: one struct plus one switch arm per language.
struct BatteryControlFeatureStrings {
    let title: String
    let hubDescription: String
    let limitLabel: String
    let hysteresisLabel: String
    let dischargeLabel: String
    let dischargeNote: String
    let dischargeUnavailable: String
    let engage: String
    let approve: String
    let helperUnavailable: String
    let unsupported: String
    let safetyCaption: String
    let statusIdle: String
    let statusHeldFormat: String
    let statusOff: String
    let phaseDischarging: String

    static func batteryControl(_ language: AppLanguage) -> BatteryControlFeatureStrings {
        switch language {
        case .enUS:
            return BatteryControlFeatureStrings(
                title: "Battery Charge Limit",
                hubDescription: "Hold charging below a threshold and run full cycles",
                limitLabel: "Charge limit",
                hysteresisLabel: "Resume charging",
                dischargeLabel: "Discharge while plugged in",
                dischargeNote: "At the limit the Mac runs on the battery even with the charger connected, drains to the resume level, then charges again — a full cycle without unplugging.",
                dischargeUnavailable: "This Mac has no wall-power switch",
                engage: "Limit charging",
                approve: "Allow the privileged helper",
                helperUnavailable: "The privileged helper did not respond",
                unsupported: "This Mac cannot control charging",
                safetyCaption: "Stops at the limit and recharges a few points lower, so daily desk time never holds the battery at 100 %. Charging pauses before sleep and resumes after wake.",
                statusIdle: "Charging normally",
                statusHeldFormat: "Held at %1$d %%",
                statusOff: "Limit off",
                phaseDischarging: "Discharging")
        case .ptBR:
            return BatteryControlFeatureStrings(
                title: "Limite de carga da bateria",
                hubDescription: "Mantém a carga abaixo do limite e executa ciclos completos",
                limitLabel: "Limite de carga",
                hysteresisLabel: "Retomar carga",
                dischargeLabel: "Descarregar ligado à tomada",
                dischargeNote: "No limite, o Mac usa a bateria mesmo com o carregador conectado, descarrega até o nível de retomada e volta a carregar — um ciclo completo sem desconectar.",
                dischargeUnavailable: "Este Mac não tem chave de energia da tomada",
                engage: "Limitar carga",
                approve: "Permitir o auxiliar privilegiado",
                helperUnavailable: "O auxiliar privilegiado não respondeu",
                unsupported: "Este Mac não controla o carregamento",
                safetyCaption: "Para no limite e recarrega alguns pontos abaixo, para o tempo de mesa nunca segurar a bateria em 100 %. A carga pausa antes de dormir e retoma ao acordar.",
                statusIdle: "Carregando normalmente",
                statusHeldFormat: "Mantida em %1$d %%",
                statusOff: "Limite desligado",
                phaseDischarging: "Descarregando")
        case .tr:
            return BatteryControlFeatureStrings(
                title: "Pil şarj sınırı",
                hubDescription: "Şarjı sınırın altında tutar ve tam döngüler çalıştırır",
                limitLabel: "Şarj sınırı",
                hysteresisLabel: "Şarjı sürdür",
                dischargeLabel: "Fişteyken boşalt",
                dischargeNote: "Sınırda Mac, şarj aleti takılıyken bile pille çalışır, devam seviyesine kadar boşalır ve yeniden şarj olur — fişi çekmeden tam bir döngü.",
                dischargeUnavailable: "Bu Mac’te şebeke gücü anahtarı yok",
                engage: "Şarjı sınırla",
                approve: "Ayrıcalıklı yardımcıya izin ver",
                helperUnavailable: "Ayrıcalıklı yardımcı yanıt vermedi",
                unsupported: "Bu Mac şarjı kontrol edemiyor",
                safetyCaption: "Sınırda durur ve birkaç puan altında yeniden şarj eder; böylece masa başında geçen zaman pili %100’de tutmaz. Şarj uyku öncesi durur, uyanınca sürer.",
                statusIdle: "Normal şekilde şarj oluyor",
                statusHeldFormat: "%%%1$d’de tutuluyor",
                statusOff: "Sınır kapalı",
                phaseDischarging: "Boşalıyor")
        case .ru:
            return BatteryControlFeatureStrings(
                title: "Предел заряда батареи",
                hubDescription: "Держит заряд ниже предела и запускает полные циклы",
                limitLabel: "Предел заряда",
                hysteresisLabel: "Возобновлять заряд",
                dischargeLabel: "Разряд при подключении",
                dischargeNote: "На пределе Mac работает от батареи даже с подключённым адаптером, разряжается до уровня возобновления и снова заряжается — полный цикл без отключения.",
                dischargeUnavailable: "У этого Mac нет переключателя питания от сети",
                engage: "Ограничить заряд",
                approve: "Разрешить привилегированный помощник",
                helperUnavailable: "Привилегированный помощник не отвечает",
                unsupported: "Этот Mac не может управлять зарядом",
                safetyCaption: "Останавливается на пределе и догоняет на несколько процентов ниже, чтобы время за столом не держало батарею на 100 %. Заряд приостанавливается перед сном и возобновляется после пробуждения.",
                statusIdle: "Заряжается обычным образом",
                statusHeldFormat: "Удерживается на %1$d %%",
                statusOff: "Предел выключен",
                phaseDischarging: "Разряд")
        case .es:
            return BatteryControlFeatureStrings(
                title: "Límite de carga de la batería",
                hubDescription: "Mantén la carga por debajo de un umbral y ejecuta ciclos completos",
                limitLabel: "Límite de carga",
                hysteresisLabel: "Reanudar carga",
                dischargeLabel: "Descargar con el cargador conectado",
                dischargeNote: "Al llegar al límite, el Mac funciona con la batería aunque el cargador esté conectado, se descarga hasta el nivel de reanudación y vuelve a cargar: un ciclo completo sin desenchufar.",
                dischargeUnavailable: "Este Mac no tiene interruptor de corriente de red",
                engage: "Limitar carga",
                approve: "Permitir el ayudante privilegiado",
                helperUnavailable: "El ayudante privilegiado no respondió",
                unsupported: "Este Mac no puede controlar la carga",
                safetyCaption: "Se detiene en el límite y recarga unos puntos por debajo, para que el tiempo en el escritorio no sostenga la batería al 100 %. La carga se pausa antes de dormir y se reanuda al despertar.",
                statusIdle: "Cargando normalmente",
                statusHeldFormat: "Mantida al %1$d %%",
                statusOff: "Límite desactivado",
                phaseDischarging: "Descargando")
        case .sk:
            return BatteryControlFeatureStrings(
                title: "Limit nabíjania batérie",
                hubDescription: "Drží nabíjanie pod prahom a spúšťa celé cykly",
                limitLabel: "Limit nabíjania",
                hysteresisLabel: "Obnoviť nabíjanie",
                dischargeLabel: "Vybíjať pri pripojenom adaptéri",
                dischargeNote: "Pri limite Mac beží na batériu aj s pripojenou nabíjačkou, vybije sa na úroveň obnovenia a znova sa nabíja – celý cyklus bez odpojenia.",
                dischargeUnavailable: "Tento Mac nemá vypínač sieťového napájania",
                engage: "Obmedziť nabíjanie",
                approve: "Povoliť privilegovaného pomocníka",
                helperUnavailable: "Privilegovaný pomocník neodpovedá",
                unsupported: "Tento Mac nevie riadiť nabíjanie",
                safetyCaption: "Zastaví sa na limite a dobije o pár percent nižšie, aby čas pri stole nedržal batériu na 100 %. Nabíjanie sa pozastaví pred spánkom a obnoví po prebudení.",
                statusIdle: "Nabíja sa bežne",
                statusHeldFormat: "Udržiavaná na %1$d %%",
                statusOff: "Limit vypnutý",
                phaseDischarging: "Vybíja sa")
        case .de:
            return BatteryControlFeatureStrings(
                title: "Batterieladelimit",
                hubDescription: "Hält das Laden unter einer Schwelle und durchläuft volle Zyklen",
                limitLabel: "Ladelimit",
                hysteresisLabel: "Laden fortsetzen",
                dischargeLabel: "Entladen am Netzteil",
                dischargeNote: "Am Limit läuft der Mac trotz angeschlossenem Netzteil im Akkubetrieb, entlädt sich bis zur Wiederaufnahme und lädt dann wieder – ein voller Zyklus ohne Abstecken.",
                dischargeUnavailable: "Dieser Mac hat keinen Netzstrom-Schalter",
                engage: "Laden begrenzen",
                approve: "Privilegierte Zusatzkomponente erlauben",
                helperUnavailable: "Die privilegierte Zusatzkomponente hat nicht geantwortet",
                unsupported: "Dieser Mac kann das Laden nicht steuern",
                safetyCaption: "Stoppt am Limit und lädt einige Punkte tiefer nach, damit Alltagszeit am Schreibtisch die Batterie nie auf 100 % hält. Das Laden pausiert vor dem Ruhezustand und läuft nach dem Aufwachen weiter.",
                statusIdle: "Lädt normal",
                statusHeldFormat: "Gehalten bei %1$d %%",
                statusOff: "Limit aus",
                phaseDischarging: "Entlädt")
        case .fr:
            return BatteryControlFeatureStrings(
                title: "Limite de charge de la batterie",
                hubDescription: "Maintient la charge sous un seuil et lance des cycles complets",
                limitLabel: "Limite de charge",
                hysteresisLabel: "Reprendre la charge",
                dischargeLabel: "Décharger sur secteur",
                dischargeNote: "À la limite, le Mac fonctionne sur la batterie même chargeur branché, se décharge jusqu’au niveau de reprise puis recharge — un cycle complet sans débrancher.",
                dischargeUnavailable: "Ce Mac n’a pas de commutateur d’alimentation secteur",
                engage: "Limiter la charge",
                approve: "Autoriser le service privilégié",
                helperUnavailable: "Le service privilégié n’a pas répondu",
                unsupported: "Ce Mac ne peut pas gérer la charge",
                safetyCaption: "S’arrête à la limite et recharge quelques points plus bas, pour que les journées au bureau ne tiennent jamais la batterie à 100 %. La charge se met en pause avant la veille et reprend au réveil.",
                statusIdle: "Charge normalement",
                statusHeldFormat: "Maintenue à %1$d %%",
                statusOff: "Limite désactivée",
                phaseDischarging: "Décharge")
        case .it:
            return BatteryControlFeatureStrings(
                title: "Limite di carica della batteria",
                hubDescription: "Mantiene la carica sotto una soglia ed esegue cicli completi",
                limitLabel: "Limite di carica",
                hysteresisLabel: "Riprendi la carica",
                dischargeLabel: "Scarica con alimentatore collegato",
                dischargeNote: "Al limite il Mac funziona a batteria anche con l’alimentatore collegato, si scarica fino al livello di ripresa e poi ricarica: un ciclo completo senza scollegare.",
                dischargeUnavailable: "Questo Mac non ha un interruttore per l’alimentazione di rete",
                engage: "Limita la carica",
                approve: "Consenti l’helper privilegiato",
                helperUnavailable: "L’helper privilegiato non ha risposto",
                unsupported: "Questo Mac non può controllare la carica",
                safetyCaption: "Si ferma al limite e ricarica qualche punto più in basso, così le ore alla scrivania non tengono la batteria al 100 %. La carica si ferma prima del riposo e riprende al risveglio.",
                statusIdle: "Carica normalmente",
                statusHeldFormat: "Mantenuta al %1$d %%",
                statusOff: "Limite disattivato",
                phaseDischarging: "In scarica")
        case .ja:
            return BatteryControlFeatureStrings(
                title: "バッテリー充電上限",
                hubDescription: "充電をしきい値未満に保ち、フルサイクルを実行します",
                limitLabel: "充電上限",
                hysteresisLabel: "充電を再開",
                dischargeLabel: "接続したまま放電",
                dischargeNote: "上限に達すると、充電器をつないだままでもバッテリー駆動に切り替わり、再開レベルまで放電してから再び充電します。抜き差しなしで1サイクルを実行できます。",
                dischargeUnavailable: "このMacには電源供給の切り替えがありません",
                engage: "充電を制限",
                approve: "特権ヘルパーを許可",
                helperUnavailable: "特権ヘルパーが応答しません",
                unsupported: "このMacは充電を制御できません",
                safetyCaption: "上限で停止し、数ポイント下がってから再充電するため、デスク作業でバッテリーが100%%のまま維持されません。スリープ前に充電を停止し、復帰後に再開します。",
                statusIdle: "通常どおり充電中",
                statusHeldFormat: "%1$d%%で維持",
                statusOff: "上限オフ",
                phaseDischarging: "放電中")
        case .ko:
            return BatteryControlFeatureStrings(
                title: "배터리 충전 한도",
                hubDescription: "충전을 임계값 아래로 유지하고 완전 충방전 사이클을 실행합니다",
                limitLabel: "충전 한도",
                hysteresisLabel: "충전 재개",
                dischargeLabel: "연결 상태에서 방전",
                dischargeNote: "한도에 도달하면 충전기를 연결한 채로도 배터리로 동작하여 재개 수준까지 방전한 뒤 다시 충전합니다. 플러그를 뽑지 않고 한 사이클을 완료합니다.",
                dischargeUnavailable: "이 Mac에는 전원 공급 전환 기능이 없습니다",
                engage: "충전 제한",
                approve: "특권 도우미 허용",
                helperUnavailable: "특권 도우미가 응답하지 않았습니다",
                unsupported: "이 Mac은 충전을 제어할 수 없습니다",
                safetyCaption: "한도에서 멈추고 몇 퍼센트 아래에서 다시 충전해, 책상에서 보내는 시간 동안 배터리가 100%%에 머물지 않게 합니다. 절전 전에 충전을 멈추고 깨어나면 재개합니다.",
                statusIdle: "평소처럼 충전 중",
                statusHeldFormat: "%1$d%% 유지",
                statusOff: "한도 꺼짐",
                phaseDischarging: "방전 중")
        case .uk:
            return BatteryControlFeatureStrings(
                title: "Ліміт заряду батареї",
                hubDescription: "Тримає заряд нижче межі та запускає повні цикли",
                limitLabel: "Ліміт заряду",
                hysteresisLabel: "Поновити заряд",
                dischargeLabel: "Розряд під час підключення",
                dischargeNote: "На ліміті Mac працює від батареї навіть із підключеним адаптером, розряджається до рівня відновлення й знову заряджається — повний цикл без відключення.",
                dischargeUnavailable: "У цього Mac немає перемикача живлення від мережі",
                engage: "Обмежити заряд",
                approve: "Дозволити привілейованого помічника",
                helperUnavailable: "Привілейований помічник не відповів",
                unsupported: "Цей Mac не може керувати зарядом",
                safetyCaption: "Зупиняється на межі й доганяє на кілька відсотків нижче, щоб час за столом не тримав батарею на 100 %. Заряд призупиняється перед сном і поновлюється після пробудження.",
                statusIdle: "Заряджається звичайно",
                statusHeldFormat: "Утримується на %1$d %%",
                statusOff: "Ліміт вимкнено",
                phaseDischarging: "Розряд")
        case .zhHans:
            return BatteryControlFeatureStrings(
                title: "电池充电上限",
                hubDescription: "将充电保持在阈值以下并执行完整循环",
                limitLabel: "充电上限",
                hysteresisLabel: "恢复充电",
                dischargeLabel: "接通电源时放电",
                dischargeNote: "达到上限后，即使充电器已连接，Mac 也改用电池供电，放电到恢复水平后再次充电——无需拔插即可完成一次完整循环。",
                dischargeUnavailable: "此 Mac 没有外接电源开关",
                engage: "限制充电",
                approve: "允许特权辅助工具",
                helperUnavailable: "特权辅助工具没有响应",
                unsupported: "此 Mac 无法控制充电",
                safetyCaption: "到达上限即停止，回落数点后继续充电，日常桌面使用不会再把电池顶在 100%。睡前暂停充电，唤醒后恢复。",
                statusIdle: "正常充电",
                statusHeldFormat: "保持在 %1$d%%",
                statusOff: "上限关闭",
                phaseDischarging: "放电中")
        case .zhTW:
            return BatteryControlFeatureStrings(
                title: "電池充電上限",
                hubDescription: "將充電保持在門檻以下並執行完整循環",
                limitLabel: "充電上限",
                hysteresisLabel: "恢復充電",
                dischargeLabel: "接上電源時放電",
                dischargeNote: "達到上限後，即使充電器已連接，Mac 也會改用電池供電，放電到恢復水準後再次充電——不必拔插即可完成一次完整循環。",
                dischargeUnavailable: "此 Mac 沒有外接電源開關",
                engage: "限制充電",
                approve: "允許特權輔助工具",
                helperUnavailable: "特權輔助工具沒有回應",
                unsupported: "此 Mac 無法控制充電",
                safetyCaption: "抵達上限即停止，回落數點後繼續充電，日常桌面使用不會再把電池頂在 100%。睡前暫停充電，喚醒後恢復。",
                statusIdle: "正常充電",
                statusHeldFormat: "保持在 %1$d%%",
                statusOff: "上限關閉",
                phaseDischarging: "放電中")
        case .zhHK:
            return BatteryControlFeatureStrings(
                title: "電池充電上限",
                hubDescription: "將充電保持在門檻以下並執行完整循環",
                limitLabel: "充電上限",
                hysteresisLabel: "恢復充電",
                dischargeLabel: "接上電源時放電",
                dischargeNote: "達到上限後，即使充電器已連接，Mac 都會改用電池供電，放電到恢復水平後再次充電——唔使拔插都可以完成一次完整循環。",
                dischargeUnavailable: "此 Mac 冇外接電源開關",
                engage: "限制充電",
                approve: "允許特權輔助工具",
                helperUnavailable: "特權輔助工具沒有回應",
                unsupported: "此 Mac 無法控制充電",
                safetyCaption: "到達上限即停止，回落數點後繼續充電，日常桌面使用不會再把電池頂在 100%。睡前暫停充電，喚醒後恢復。",
                statusIdle: "正常充電",
                statusHeldFormat: "保持在 %1$d%%",
                statusOff: "上限關閉",
                phaseDischarging: "放電中")
        }
    }
}
