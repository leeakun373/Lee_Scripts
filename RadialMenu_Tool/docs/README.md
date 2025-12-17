## RadialMenu Tool（维护向 README）

本文档面向**代码维护者 / AI 修复者**，用于快速理解模块职责、定位问题与制定测试计划。

### 入口与启动链路

- **运行时入口**：`Lee_RadialMenu.lua`
  - 负责：初始化 `config.json`（不存在则从 `config.example.json` 复制）、设置 `package.path`、`require('main_runtime').run()`。
- **设置编辑器入口**：`Lee_RadialMenu_Setup.lua`
  - 负责：设置 `package.path`、`require('main_settings').show()`。
- **状态重置**：`Lee_RadialMenu_reset_state.lua`
  - 负责：清 ExtState `RadialMenu_Tool/Running`，解决“脚本崩溃后无法再打开”的僵尸锁。

### 当前目录结构（以维护为中心）

```
RadialMenu_Tool/
├── Lee_RadialMenu.lua                 # 运行时入口（Action List 绑定快捷键）
├── Lee_RadialMenu_Setup.lua           # 设置编辑器入口
├── Lee_RadialMenu_reset_state.lua     # 运行状态重置
├── config.example.json                # 配置模板（首次运行会复制为 config.json）
├── src/
│   ├── main_runtime.lua               # 兼容壳：return require('runtime.controller')
│   ├── main_settings.lua              # 兼容壳：return require('settings.controller')
│   ├── config_manager.lua             # 配置读写/默认值/迁移；写入 ConfigUpdated 触发热重载
│   ├── gui/
│   │   ├── wheel.lua                  # 轮盘扇区绘制与 hover 计算
│   │   ├── list_view.lua              # 子菜单列表（点击/拖拽状态）
│   │   └── styles.lua                 # ImGui 样式/颜色
│   ├── logic/
│   │   ├── execution.lua              # 插槽执行引擎（action/fx/chain/template + drop）
│   │   ├── actions.lua                # Actions 相关工具（供 list_view / browser 使用）
│   │   └── (无其它模块)               # 拆分后请尽量保持 logic 层“可单测/可复用”
│   ├── runtime/
│   │   ├── controller.lua             # 主循环/生命周期：init→loop→cleanup；热键按住/松开策略
│   │   ├── draw.lua                   # 绘制编排：wheel + list_view + drag/drop + 动画/性能
│   │   ├── input.lua                  # 触发键检测/拦截/按住判断（JS_VKeys）
│   │   ├── config_reload.lua          # 监听 ExtState(ConfigUpdated) 并热重载 config
│   │   ├── anim.lua                   # 动画策略（开场缩放、hover 扩展、anim_active 判定）
│   │   └── perf.lua                   # 性能 HUD / 统计
│   └── settings/
│       ├── controller.lua             # 设置编辑器主循环 + 布局编排（tabs）
│       ├── state.lua                  # 设置编辑器状态容器（唯一真源）
│       ├── ops.lua                    # deep_copy / deep_merge 等纯函数
│       └── tabs/
│           ├── preview.lua            # 左侧预览/全局参数
│           ├── grid.lua               # 中间网格（插槽编辑/交换）
│           ├── inspector.lua          # 右侧属性面板
│           ├── browser.lua            # 资源浏览器（Actions/FX/Chains/Templates）
│           └── presets.lua            # 预设管理
└── utils/
    ├── math_utils.lua                 # 几何/距离/角度等
    ├── im_utils.lua                   # ImGui 小工具
    ├── json.lua                       # JSON 编解码
    └── utils_fx.lua                   # FX/Chain/Template 扫描与缓存
```

> 说明：本次拆分后，`src/runtime/*` 负责运行时，`src/settings/*` 负责设置编辑器，`src/gui/*` 只做渲染与输入命中测试。

### require 约定（避免撞名）

- 统一使用命名空间：
  - `gui.*` / `logic.*` / `runtime.*` / `settings.*`
- 工具模块放在 `utils/` 根下，按文件名 `require("math_utils")` / `require("utils_fx")`。
- `src/main_runtime.lua`、`src/main_settings.lua` 仅作为**兼容壳**，不要再写业务逻辑。

### 运行时（轮盘）关键流程

- **入口**：`Lee_RadialMenu.lua` → `src/main_runtime.lua` → `src/runtime/controller.lua`
- **controller.init()**
  - 设定 ExtState：`RadialMenu_Tool/Running=1`
  - 检测并拦截触发键：`runtime.input.detect_and_intercept_trigger_key()`
  - 创建 ImGui context、加载 config、初始化样式。
- **controller.loop()**
  - `runtime.config_reload.maybe_reload(R)`：检测 `RadialMenu/ConfigUpdated` 变更并热重载
  - `track_shortcut_key()`：未 Pin 时，触发键松开则 `cleanup()`
  - `runtime.draw.draw(R, should_update)`：绘制与交互
- **cleanup()**
  - 释放 `JS_VKeys_Intercept(key, -1)`（除非走“延迟释放”路径）
  - 清 ExtState：`Running=0`、`WindowOpen=0`

### 热键“按住打开/松开关闭”维护要点

- 触发键检测与拦截在 `src/runtime/input.lua`。
- **按住判断必须稳定**：使用固定的 `script_start_time - 1` 作为 `JS_VKeys_GetState` 的基准窗口。
  - 之前的坑：使用 `time_precise()-1` 这种“滑动窗口”会在长按场景产生误判。
- “执行后立刻关 UI，但仍按住快捷键”需要走 `controller.lua` 的延迟释放逻辑（避免热键重复触发脚本）。

### 配置热重载（Runtime 依赖）

- `config_manager.lua` 在保存配置时写 ExtState：`RadialMenu/ConfigUpdated=<timestamp>`
- `runtime/config_reload.lua` 在运行时轮询该 ExtState，变更则 reload config + refresh styles + resize。

### ExtState 约定（当前使用）

- **运行时互斥**：`RadialMenu_Tool/Running`（1=运行中，0=可启动）
- **运行时窗口状态**：`RadialMenu_Tool/WindowOpen`（仅标记用）
- **设置编辑器互斥**：`RadialMenu/SettingsOpen`
- **热重载触发**：`RadialMenu/ConfigUpdated`

### 常见问题快速定位

- **长按快捷键/松开行为异常**：`src/runtime/controller.lua`（track_shortcut_key / defer_release_key_and_running） + `src/runtime/input.lua`
- **轮盘 hover 命中不对/角度错位**：`src/gui/wheel.lua` + `utils/math_utils.lua`
- **点击扇区/子菜单显示隐藏逻辑异常**：`src/runtime/draw.lua`（handle_sector_click / auto-hide submenu）
- **拖拽/放置行为异常**：`src/gui/list_view.lua`（drag 状态）+ `src/logic/execution.lua`（handle_drop）
- **设置编辑器按钮/状态不同步**：`src/settings/state.lua`（唯一真源）与各 `tabs/*.lua` 的读写接口

### 建议的最小测试清单（修 bug 前/后都跑）

- **基础打开/关闭**
  - 绑定热键：按下出现、松开消失（未 Pin）
  - 按住超过 2 秒仍稳定
  - ESC：未 Pin 关闭；Pin 时只收起子菜单（不关主窗口）
- **执行路径**
  - 点击执行 action：按住热键期间不会“重复弹出/连触发”
  - Pin 模式下执行：不应意外关闭
- **拖拽路径**
  - 从 Browser 拖到 Slot
  - 从 Slot 拖到 Arrange 的 item/track/空白：落点正确
  - 拖拽过程中子菜单不闪烁、不乱切 sector
- **热重载**
  - 打开运行时轮盘
  - 在设置编辑器里保存配置
  - 运行时应自动刷新样式/尺寸（无需重开脚本）

### 维护建议（让后续拆分更安全）

- 新增模块前先确定归属：
  - **生命周期/输入/互斥/ExtState** → `runtime/controller.lua`
  - **绘制编排/命中测试/交互策略** → `runtime/draw.lua`
  - **纯 UI 绘制** → `gui/*`
  - **执行与 REAPER API 行为** → `logic/*`
  - **编辑器 UI** → `settings/*`
- 避免在 `tabs/*.lua` 内部偷偷 `require` 一堆全局状态；统一通过 `state` 与回调传递。
- 保留 `src/main_runtime.lua`、`src/main_settings.lua` 作为兼容层，避免用户旧入口失效。
