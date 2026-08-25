// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

struct ChargeControlStrings {
    let title: String
    let description: String
    let enable: String
    let enableCaption: String
    let limit: String
    let discharge: String
    let topUp: String
    let approveHelper: String
    let resolveConflict: String
    let warning: String

    static func current(_ language: AppLanguage) -> Self {
        switch language {
        case .zhHans:
            return Self(title: "充电保护", description: "将 MacBook 的最高充电量限制在你选择的百分比。",
                        enable: "限制充电上限", enableCaption: "Vorssaint 运行期间生效；退出或控制失败时恢复正常充电。",
                        limit: "充电上限", discharge: "放电", topUp: "充满",
                        approveHelper: "允许后台充电控制",
                        resolveConflict: "检查 macOS 电池设置",
                        warning: "此 Beta 功能使用私有硬件接口。macOS 的优化充电或系统充电上限可能与它冲突。")
        case .zhTW, .zhHK:
            return Self(title: "充電保護", description: "將 MacBook 的最高充電量限制在你選擇的百分比。",
                        enable: "限制充電上限", enableCaption: "Vorssaint 執行期間生效；結束或控制失敗時恢復正常充電。",
                        limit: "充電上限", discharge: "放電", topUp: "充滿",
                        approveHelper: "允許背景充電控制",
                        resolveConflict: "檢查 macOS 電池設定",
                        warning: "此 Beta 功能使用私有硬體介面。macOS 的最佳化充電或系統充電上限可能與它衝突。")
        default:
            return Self(title: "Charge Protection", description: "Limit the maximum charge of your MacBook battery.",
                        enable: "Limit maximum charge", enableCaption: "Active while Vorssaint runs; normal charging is restored on exit or control failure.",
                        limit: "Charge limit", discharge: "Discharge", topUp: "Top Up",
                        approveHelper: "Allow background charge control",
                        resolveConflict: "Check macOS Battery Settings",
                        warning: "This beta uses private hardware interfaces. Optimized Charging or the macOS charge limit may conflict with it.")
        }
    }

    func status(_ value: ChargeControlStatus) -> String {
        if L10n.shared.language == .zhHans {
            switch value {
            case .uninstalled: return "未安装"
            case .disabled: return "已关闭"
            case .charging: return "正在充电"
            case .paused: return "已暂停充电"
            case .discharging: return "正在放电至上限"
            case .onBattery: return "正在使用电池"
            case .systemConflict: return "与 macOS 充电策略冲突"
            case .approvalRequired: return "需要在系统设置中允许后台控制"
            case .unsupportedHardware: return "硬件不支持"
            case .helperUnavailable: return "充电控制服务不可用"
            case .controlFailed: return "控制失败，已恢复系统充电"
            }
        }
        switch value {
        case .uninstalled: return "Not installed"
        case .disabled: return "Off"
        case .charging: return "Charging"
        case .paused: return "Charging paused"
        case .discharging: return "Discharging to limit"
        case .onBattery: return "On battery"
        case .systemConflict: return "System charging policy conflict"
        case .approvalRequired: return "Allow background control in System Settings"
        case .unsupportedHardware: return "Unsupported hardware"
        case .helperUnavailable: return "Charge control service unavailable"
        case .controlFailed: return "Control failed; system charging restored"
        }
    }
}
