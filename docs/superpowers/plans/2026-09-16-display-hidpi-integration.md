# Display HiDPI & Resolution Management Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development or superpowers:gan-style-harness to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 将 MyDisplay 中的原生 HiDPI 切换、虚拟屏镜像兜底以及 15 秒防黑屏安全看门狗完整整合至 Vorssaint 的显示器控制子系统。

**Architecture:** 
- `SkyLightBridge`: 动态加载 SkyLight 私有符号获取底层完整高密度模式。
- `VirtualDisplayService`: 基于 `CGVirtualDisplay` 创建 4K/5K 虚拟屏并建立物理屏镜像。
- `DisplayRecoveryManager`: 15 秒倒计时安全事务与回滚协调器。
- `DisplayResolutionService`: 聚合模式枚举、HiDPI 状态判定与切换调度。
- `RecoveryHUDView`: 悬浮置顶倒计时确认面板。
- `BrightnessSection`: 扩展菜单面板 UI，提供紧凑的分辨率切换与 HiDPI 状态指示。
- `Localization`: 严格满足 13 种受支持语言的本地化。

**Tech Stack:** Swift 5.9+ / Swift 6, AppKit, SwiftUI, Combine, CoreGraphics, SkyLight (Private Framework), IOKit.

---

### Task 1: 底层 SkyLight 私有桥接 (`SkyLightBridge.swift`)

**Files:**
- Create: `Sources/Vorssaint/Services/Display/SkyLightBridge.swift`
- Test: `Tests/Core/SkyLightBridgeTests.swift` (或集成至现有 `Tests/Core`)

- [ ] **Step 1: 编写底层 CGS 数据结构与动态加载**
实现 `CGSDisplayModeDescription`、`CGSDisplayModeRecord`，并通过 `dlopen`/`dlsym` 动态解析 `CGSGetNumberOfDisplayModes`、`CGSGetDisplayModeDescriptionOfLength`、`CGSConfigureDisplayMode`。

- [ ] **Step 2: 验证 SkyLight 符号加载与模式读取**
编译并运行快速检测，确保在 Apple Silicon 宿主环境下能够正常读取显示器数量及各模式的 `density`。

- [ ] **Step 3: Commit**
```bash
git add Sources/Vorssaint/Services/Display/SkyLightBridge.swift
git commit -m "feat(display): add SkyLightBridge for CGS display mode queries and configuration"
```

---

### Task 2: 虚拟显示器服务 (`VirtualDisplayService.swift`)

**Files:**
- Create: `Sources/Vorssaint/Services/Display/VirtualDisplayService.swift`

- [ ] **Step 1: 实现基于 CGVirtualDisplay 的虚拟屏实例封装**
使用 Objective-C Runtime (`NSClassFromString("CGVirtualDisplay")`) 动态构造虚拟显示器描述符与模式（支持 16:9 5K/4K/2K 与 16:10 标准阶梯），避免新增额外 C 桥接依赖。

- [ ] **Step 2: 实现物理屏幕与虚拟屏的镜像绑定/解除**
调用 `CGConfigureDisplayMirrorOfDisplay` 建立以虚拟屏为源、物理屏为目标的镜像，并支持 `destroyAll()` 退出清理。

- [ ] **Step 3: Commit**
```bash
git add Sources/Vorssaint/Services/Display/VirtualDisplayService.swift
git commit -m "feat(display): add VirtualDisplayService for dummy display creation and mirroring"
```

---

### Task 3: 15 秒安全看门狗与配置回滚协调器 (`DisplayRecoveryManager.swift`)

**Files:**
- Create: `Sources/Vorssaint/Services/Display/DisplayRecoveryManager.swift`
- Modify: `Sources/Vorssaint/App/AppDelegate.swift` (在退出时触发安全重置)

- [ ] **Step 1: 编写事务快照结构与倒计时逻辑**
记录变更前的 DisplayID、原始模式、原始镜像关系及创建的虚拟屏，启动 15 秒定时器。

- [ ] **Step 2: 实现 confirm() 与 rollback()**
确认时取消定时器并销毁快照；回滚或超时时调用 CoreGraphics 恢复原始配置并解除镜像。

- [ ] **Step 3: 在 AppDelegate 中添加 applicationWillTerminate 紧急清理钩子**
确保应用被关闭或杀掉时，不会残留无信号配置或多余虚拟屏幕。

- [ ] **Step 4: Commit**
```bash
git add Sources/Vorssaint/Services/Display/DisplayRecoveryManager.swift Sources/Vorssaint/App/AppDelegate.swift
git commit -m "feat(display): add DisplayRecoveryManager with 15-second watchdog and fail-safe hooks"
```

---

### Task 4: 分辨率与 HiDPI 聚合调度服务 (`DisplayResolutionService.swift`)

**Files:**
- Create: `Sources/Vorssaint/Services/Display/DisplayResolutionService.swift`

- [ ] **Step 1: 定义 DisplayResolutionMode 与 HiDPI 状态模型**
封装逻辑分辨率、物理渲染像素、刷新率、是否 HiDPI、是否原生支持。

- [ ] **Step 2: 实现模式枚举与排序**
合并 `CGDisplayCopyAllDisplayModes` 与 `SkyLightBridge.queryCGSModes`，按宽高比一致性、常用档位及刷新率智能排序。

- [ ] **Step 3: 实现智能一键切换与模式应用入口**
`toggleHiDPI(for displayID:)` 与 `applyMode(_ mode:for displayID:)`，统一经由看门狗接管。

- [ ] **Step 4: Commit**
```bash
git add Sources/Vorssaint/Services/Display/DisplayResolutionService.swift
git commit -m "feat(display): add DisplayResolutionService for resolution and HiDPI management"
```

---

### Task 5: 13 种语言本地化支持 (`Localization.swift`)

**Files:**
- Modify: `Sources/Vorssaint/Core/Localization.swift`
- Modify: `Sources/Vorssaint/Core/Localizations/Strings+English.swift`
- Modify: `Sources/Vorssaint/Core/Localizations/Strings+ChineseSimplified.swift`
- Modify: `Sources/Vorssaint/Core/Localizations/Strings+ChineseTraditionalTW.swift`
- Modify: `Sources/Vorssaint/Core/Localizations/Strings+ChineseTraditionalHK.swift`
- Modify: `Sources/Vorssaint/Core/Localizations/Strings+Japanese.swift`
- Modify: `Sources/Vorssaint/Core/Localizations/Strings+Korean.swift`
- Modify: `Sources/Vorssaint/Core/Localizations/Strings+German.swift`
- Modify: `Sources/Vorssaint/Core/Localizations/Strings+French.swift`
- Modify: `Sources/Vorssaint/Core/Localizations/Strings+Spanish.swift`
- Modify: `Sources/Vorssaint/Core/Localizations/Strings+Italian.swift`
- Modify: `Sources/Vorssaint/Core/Localizations/Strings+PortugueseBrazil.swift`
- Modify: `Sources/Vorssaint/Core/Localizations/Strings+Russian.swift`
- Modify: `Sources/Vorssaint/Core/Localizations/Strings+Turkish.swift`

- [ ] **Step 1: 在 Localization.swift 的 Strings 结构体中声明新词条**
`hiDPITag`, `nativeHiDPI`, `virtualHiDPI`, `standardMode`, `recoveryKeep`, `recoveryRevert`, `recoveryCountdownPrompt` 等。

- [ ] **Step 2: 在全部 13 种语言文件中严格补全翻译**
确保编译期强校验通过。

- [ ] **Step 3: Commit**
```bash
git add Sources/Vorssaint/Core/Localization.swift Sources/Vorssaint/Core/Localizations/
git commit -m "feat(l10n): add localization strings for display resolution and HiDPI across 13 locales"
```

---

### Task 6: 15 秒看门狗倒计时浮层 (`RecoveryHUDView.swift`)

**Files:**
- Create: `Sources/Vorssaint/UI/MenuPanel/RecoveryHUDView.swift`

- [ ] **Step 1: 编写置顶 NSPanel 与半透明毛玻璃 SwiftUI 界面**
居中悬浮在屏幕顶部，展示倒计时环形进度、剩余秒数提示。

- [ ] **Step 2: 绑定键盘事件（Return 确认，Esc 还原）与点击回调**
联动 `DisplayRecoveryManager.shared.confirm()` 与 `rollback()`。

- [ ] **Step 3: Commit**
```bash
git add Sources/Vorssaint/UI/MenuPanel/RecoveryHUDView.swift
git commit -m "feat(ui): add RecoveryHUDView floating confirmation panel"
```

---

### Task 7: 菜单面板集成 (`BrightnessSection.swift`)

**Files:**
- Modify: `Sources/Vorssaint/UI/MenuPanel/BrightnessSection.swift`

- [ ] **Step 1: 在显示器卡片行中集成分辨率信息与 HiDPI 徽标**
展示当前分辨率（如 `2560 × 1440 · 75 Hz`）与状态胶囊（`HiDPI` / `1x`）。

- [ ] **Step 2: 增加分辨率与刷新率下拉选择菜单 (Menu)**
清晰排列推荐分辨率与视网膜缩放档位。

- [ ] **Step 3: 增加一键智能 HiDPI 切换按钮**
一键在原生 HiDPI、虚拟 HiDPI 与标准模式间智能流转。

- [ ] **Step 4: Commit**
```bash
git add Sources/Vorssaint/UI/MenuPanel/BrightnessSection.swift
git commit -m "feat(ui): integrate resolution picker and HiDPI toggle into BrightnessSection"
```

---

### Task 8: 全面构建、测试与 Harness 验证

**Files:**
- Test: 自动化验证脚本与单元测试

- [ ] **Step 1: 运行 ./build.sh 进行全量 Release 编译**
验证 swift 编译器无报错，语言包完整度检查通过，产物签名正常。

- [ ] **Step 2: 运行 ./build.sh --test**
验证现有测试套件全部 PASS。

- [ ] **Step 3: 运行 ./build/stage/Vorssaint.app/Contents/MacOS/Vorssaint --selftest**
验证进程健康自检通过（`SELFTEST OK`）。

- [ ] **Step 4: 评估与 Harness 终审**
根据 Anthropic GAN-Style Harness 指南对整体功能完整度、代码鲁棒性与异常保护进行终评。
