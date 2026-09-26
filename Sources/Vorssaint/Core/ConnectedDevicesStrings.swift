// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

struct ConnectedDevicesFeatureStrings {
    let title: String
    let hubDescription: String
    let noDevices: String
    let unnamedDevice: String
    let menuBarLabel: String
    let oneConnected: String
    let devicesConnectedFormat: String

    func formattedCount(_ count: Int) -> String {
        if count == 1 {
            return oneConnected
        }
        return String(format: devicesConnectedFormat, count)
    }
}

extension FeatureStrings {
    static func connectedDevices(_ language: AppLanguage) -> ConnectedDevicesFeatureStrings {
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
        case .zhHK: return .zhHK
        case .zhTW: return .zhTW
        }
    }
}

private extension ConnectedDevicesFeatureStrings {
    static let enUS = ConnectedDevicesFeatureStrings(
        title: "Connected Devices",
        hubDescription: "Count connected external USB peripherals",
        noDevices: "No external devices connected",
        unnamedDevice: "USB Device",
        menuBarLabel: "USB",
        oneConnected: "1 device connected",
        devicesConnectedFormat: "%d devices connected"
    )

    static let ptBR = ConnectedDevicesFeatureStrings(
        title: "Dispositivos conectados",
        hubDescription: "Contar periféricos USB externos conectados",
        noDevices: "Nenhum dispositivo externo conectado",
        unnamedDevice: "Dispositivo USB",
        menuBarLabel: "USB",
        oneConnected: "1 dispositivo conectado",
        devicesConnectedFormat: "%d dispositivos conectados"
    )

    static let tr = ConnectedDevicesFeatureStrings(
        title: "Bağlı Aygıtlar",
        hubDescription: "Bağlı harici USB çevre birimlerini say",
        noDevices: "Bağlı harici aygıt yok",
        unnamedDevice: "USB Aygıtı",
        menuBarLabel: "USB",
        oneConnected: "1 aygıt bağlı",
        devicesConnectedFormat: "%d aygıt bağlı"
    )

    static let ru = ConnectedDevicesFeatureStrings(
        title: "Подключенные устройства",
        hubDescription: "Подсчет подключенных внешних USB-устройств",
        noDevices: "Нет подключенных внешних устройств",
        unnamedDevice: "USB-устройство",
        menuBarLabel: "USB",
        oneConnected: "Подключено 1 устройство",
        devicesConnectedFormat: "Подключено устройств: %d"
    )

    static let es = ConnectedDevicesFeatureStrings(
        title: "Dispositivos conectados",
        hubDescription: "Contar periféricos USB externos conectados",
        noDevices: "No hay dispositivos externos conectados",
        unnamedDevice: "Dispositivo USB",
        menuBarLabel: "USB",
        oneConnected: "1 dispositivo conectado",
        devicesConnectedFormat: "%d dispositivos conectados"
    )
    static let sk = ConnectedDevicesFeatureStrings(
        title: "Pripojené zariadenia",
        hubDescription: "Počíta pripojené externé zariadenia USB",
        noDevices: "Nie sú pripojené žiadne externé zariadenia",
        unnamedDevice: "Zariadenie USB",
        menuBarLabel: "USB",
        oneConnected: "1 pripojené zariadenie",
        devicesConnectedFormat: "Pripojené zariadenia: %d"
    )

    static let de = ConnectedDevicesFeatureStrings(
        title: "Verbundene Geräte",
        hubDescription: "Angeschlossene externe USB-Geräte zählen",
        noDevices: "Keine externen Geräte verbunden",
        unnamedDevice: "USB-Gerät",
        menuBarLabel: "USB",
        oneConnected: "1 Gerät verbunden",
        devicesConnectedFormat: "%d Geräte verbunden"
    )

    static let fr = ConnectedDevicesFeatureStrings(
        title: "Appareils connectés",
        hubDescription: "Compter les périphériques USB externes connectés",
        noDevices: "Aucun appareil externe connecté",
        unnamedDevice: "Appareil USB",
        menuBarLabel: "USB",
        oneConnected: "1 appareil connecté",
        devicesConnectedFormat: "%d appareils connectés"
    )

    static let it = ConnectedDevicesFeatureStrings(
        title: "Dispositivi collegati",
        hubDescription: "Conta le periferiche USB esterne collegate",
        noDevices: "Nessun dispositivo esterno collegato",
        unnamedDevice: "Dispositivo USB",
        menuBarLabel: "USB",
        oneConnected: "1 dispositivo collegato",
        devicesConnectedFormat: "%d dispositivi collegati"
    )

    static let ja = ConnectedDevicesFeatureStrings(
        title: "接続されたデバイス",
        hubDescription: "接続されている外部USB周辺機器をカウント",
        noDevices: "接続されている外部デバイスはありません",
        unnamedDevice: "USBデバイス",
        menuBarLabel: "USB",
        oneConnected: "1台のデバイスが接続中",
        devicesConnectedFormat: "%d台のデバイスが接続中"
    )

    static let ko = ConnectedDevicesFeatureStrings(
        title: "연결된 기기",
        hubDescription: "연결된 외부 USB 주변기기 수 측정",
        noDevices: "연결된 외부 기기 없음",
        unnamedDevice: "USB 기기",
        menuBarLabel: "USB",
        oneConnected: "기기 1개 연결됨",
        devicesConnectedFormat: "기기 %d개 연결됨"
    )
    static let uk = ConnectedDevicesFeatureStrings(
        title: "Підключені пристрої",
        hubDescription: "Підраховує підключені зовнішні USB-пристрої",
        noDevices: "Немає підключених зовнішніх пристроїв",
        unnamedDevice: "USB-пристрій",
        menuBarLabel: "USB",
        oneConnected: "Підключено 1 пристрій",
        devicesConnectedFormat: "Підключено пристроїв: %d"
    )

    static let zhHans = ConnectedDevicesFeatureStrings(
        title: "已连接设备",
        hubDescription: "统计连接的外接 USB 设备数量",
        noDevices: "未连接外接设备",
        unnamedDevice: "USB 设备",
        menuBarLabel: "USB",
        oneConnected: "已连接 1 台设备",
        devicesConnectedFormat: "已连接 %d 台设备"
    )

    static let zhHK = ConnectedDevicesFeatureStrings(
        title: "已連接裝置",
        hubDescription: "統計連接的外接 USB 裝置數量",
        noDevices: "未連接外接裝置",
        unnamedDevice: "USB 裝置",
        menuBarLabel: "USB",
        oneConnected: "已連接 1 部裝置",
        devicesConnectedFormat: "已連接 %d 部裝置"
    )

    static let zhTW = ConnectedDevicesFeatureStrings(
        title: "已連接裝置",
        hubDescription: "統計連接的外接 USB 裝置數量",
        noDevices: "未連接外接裝置",
        unnamedDevice: "USB 裝置",
        menuBarLabel: "USB",
        oneConnected: "已連接 1 部裝置",
        devicesConnectedFormat: "已連接 %d 部裝置"
    )
}
