# Display HiDPI & Resolution Management Integration Design

## 1. 概述与背景

本项目目标是将 **MyDisplay** 工具中的核心显示器控制能力完整整合至 **Vorssaint** 的显示器管理子系统（`Services/Display` 与 `UI/MenuPanel/BrightnessSection`），为 macOS 用户提供直观、原生的 HiDPI 视网膜渲染切换、分辨率模式管理以及 15 秒防黑屏看门狗保护机制。

---

## 2. 核心目标与能力矩阵

1. **原生 HiDPI 模式发现与切换 (Native HiDPI)**：
   - 通过私有 `SkyLight.framework` 动态桥接，枚举底层 `CGSDisplayModeDescription` 中未对普通 API 公开的 HiDPI 模式（`density >= 1.5`）。
   - 用户可无缝一键激活硬件所支持的最佳 Retina 模式，保留当前最高刷新率，免除重启与配置丢失。

2. **虚拟屏镜像兜底 (Virtual Display Mirror Dummy)**：
   - 针对老旧显示器、电视或特定 HDMI 转接器（硬件本身未向 macOS 上报 HiDPI 模式）的场景，调用 CoreGraphics 私有 `CGVirtualDisplay` 接口动态创建高密度虚拟显示器（4K/5K 源），并将其与目标物理屏建立硬件级镜像，强制激活 macOS Retina 渲染。
   - 具备完整的生命周期管控：屏幕断开或应用退出时自动销毁虚拟屏、恢复原始拓扑结构。

3. **常用分辨率与刷新率快速选择**：
   - 在菜单栏显示卡片中列出推荐分辨率与刷新率，清晰标识「Retina HiDPI」或「1x 标准清晰度」，支持快速切换。

4. **15 秒安全看门狗与配置回滚 (Watchdog & Recovery)**：
   - 用户切换新分辨率或开启虚拟屏镜像时，启动 15 秒倒计时事务，并在屏幕顶部弹出半透明 `RecoveryHUD` 确认面板。
   - 用户按 Return/点击“保留”完成确认；按 Esc/点击“还原”或 15 秒超时未确认（屏幕无信号或黑屏），看门狗自动安全回滚至上一可用显示配置。

---

## 3. 详细架构设计

```
Sources/Vorssaint/
├── Services/Display/
│   ├── SkyLightBridge.swift          # SkyLight CGS 私有函数动态查找与模式包装
│   ├── VirtualDisplayService.swift   # CGVirtualDisplay 虚拟显示器包装与镜像控制
│   ├── DisplayResolutionService.swift# 模式枚举、HiDPI 判断与分辨率配置核心调度 (ObservableObject)
│   └── DisplayRecoveryManager.swift  # 15 秒看门狗事务、状态快照与自动回滚控制器
├── UI/MenuPanel/
│   ├── BrightnessSection.swift       # 扩展显示器列表行：分辨率信息、HiDPI 徽标与模式下拉菜单
│   └── RecoveryHUDView.swift         # 置顶倒计时 15 秒确认与回滚浮层 (NSPanel)
└── Core/
    ├── Localization.swift            # 新增 HiDPI / 分辨率 / 回滚相关词条定义
    └── Localizations/                # 同步更新 13 种受支持语言的翻译文件
```

### 3.1 `SkyLightBridge.swift`
- 动态加载 `/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight`：
  - `CGSGetNumberOfDisplayModes`
  - `CGSGetDisplayModeDescriptionOfLength`
  - `CGSConfigureDisplayMode`
- 定义数据结构 `CGSDisplayModeRecord`：
  - `modeNumber: Int32`
  - `width: Int`, `height: Int`
  - `pixelWidth: Int`, `pixelHeight: Int`
  - `refreshRate: Double`
  - `density: Float`
  - `isHiDPI: Bool` (`density >= 1.5`)
- 提供安全包装方法 `queryCGSModes(for:)` 和 `configureDisplayMode(config:displayID:modeNumber:)`。

### 3.2 `VirtualDisplayService.swift`
- 基于 CoreGraphics 私有 Objective-C 类 `CGVirtualDisplay`，使用动态接口（或 Objective-C Bridge）安全调用；
- 预设标准 Profile（16:9 5K/4K/2K 常用阶梯，16:10 常用阶梯）；
- 提供 `createVirtualDisplay(for:plan:)`、`mirror(targetDisplayID:to:)` 与 `destroyAll()` 方法；
- 维护物理显示器 UUID 到对应 Dummy 虚拟屏实例的映射字典。

### 3.3 `DisplayResolutionService.swift`
- 单例 `DisplayResolutionService.shared: ObservableObject`：
  - 属性 `@Published private(set) var displayModes: [CGDirectDisplayID: [DisplayModeItem]]`
  - 属性 `@Published private(set) var currentModes: [CGDirectDisplayID: DisplayModeItem]`
  - 属性 `@Published private(set) var activeHiDPIKind: [CGDirectDisplayID: HiDPIKind]`（`.none`, `.native`, `.virtualMirror`）
- 核心操作方法：
  - `refresh(displayIDs:)`：调用 `CGDisplayCopyAllDisplayModes` 与 `SkyLightBridge` 进行模式归一化与排序；
  - `applyMode(displayID:mode:withWatchdog:)`：通过 `DisplayRecoveryManager` 开始事务并应用模式；
  - `toggleHiDPI(displayID:)`：根据当前状态自动选择升阶原生 HiDPI、启动虚拟镜像或降阶回 1x 标准。
- 监听 `NSApplication.didChangeScreenParametersNotification` 实现热插拔状态同步。

### 3.4 `DisplayRecoveryManager.swift` 与 `RecoveryHUDView.swift`
- 事务快照结构 `DisplayTransactionSnapshot`：记录目标屏幕 ID、变动前的模式、变动前的镜像关系、创建的虚拟屏句柄；
- 倒计时控制器：
  - 启动 15 秒 `Timer`，每秒递减并发布剩余秒数；
  - 在所有活跃 `NSScreen` 顶部创建非激活无边框 `NSPanel`（`.statusBar` 窗口层级），嵌入 `RecoveryHUDView`；
  - 监听全局快捷键（Return 确认，Esc 还原）；
  - 超时自动调用 `rollback()`。
- `AppDelegate` 集成：
  - 在 `applicationWillTerminate` 中调用 `DisplayRecoveryManager.shared.cleanupOnExit()`，确保任何未保存配置被安全重置，且虚拟屏被彻底销毁。

### 3.5 UI 与本地化
- `BrightnessSection.swift`：
  - 在每个活跃显示器卡片（`display.isActive`）中，在亮度滑块下方新增紧凑的控制栏：
    - 当前分辨率文本（如 `2560 × 1440 · 75 Hz`）；
    - 状态徽标：`HiDPI`（强调色高亮）或 `1x 标准`（次要色）；
    - 下拉菜单（Menu）：展示可用分辨率与刷新率，按清晰度排序；
    - 一键 HiDPI 快捷按钮。
- `Core/Localization.swift`：
  - 严格添加所有相关词条，并在 `Core/Localizations/` 下的 13 个语言实现文件（English, 简体中文, 繁体中文, 日语, 德语, 法语等）中补齐对应翻译。

---

## 4. 容错与边缘情况防护

1. **屏幕黑屏或无响应**：15 秒看门狗自动倒计时结束，调用 `CGCompleteDisplayConfiguration` 恢复先前快照。
2. **应用意外退出 / 崩溃**：退出钩子立即销毁所有虚拟显示器，解除所有镜像。
3. **线缆热插拔**：监听屏幕参数变更通知，若目标屏幕已离线，立即中止未完成的看门狗事务，清理脏状态。
4. **兼容性安全**：若系统环境无法加载 `SkyLight` 私有符号，降级使用标准 `CGDisplayCopyAllDisplayModes`，不引起应用崩溃。

---

## 5. 验证与测试计划

1. **自动化编译验证**：
   - 运行 `./build.sh` 确保所有 13 种语言本地化完整性检查通过，且 `swiftc` 零错误零告警。
   - 运行 `./build.sh --test` 确保现有测试套件全部通过。
2. **自检命令**：
   - 运行 `./build/stage/Vorssaint.app/Contents/MacOS/Vorssaint --selftest` 确认健康检查通过。
3. **功能实测**：
   - 在实机上运行 Vorssaint，连接外接显示器；
   - 切换不同分辨率与刷新率，验证 15 秒看门狗面板是否正常浮现；
   - 测试点击“保留”与点击“还原”；测试 15 秒超时无操作自动还原；
   - 测试一键开启原生 HiDPI 及虚拟屏 HiDPI 镜像。
