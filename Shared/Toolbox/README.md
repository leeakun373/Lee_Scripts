# Shared/Toolbox 使用说明（零基础版）

> 这是一个给 REAPER ReaScript 用的“公共工具箱”。
> 目的：把常用的事情（UI 窗口、统一主题、按钮/控件封装、配置保存、日志/终端等）做成公共模块。
> 以后你写任何脚本需要界面，只要“引用 Toolbox”，就不用每次从头造轮子。

---

## 1. Toolbox 是什么？

- **Toolbox = 公共零件库**
  - 里面放的是“可复用的代码模块”。
  - 好处：以后做新脚本，只写“这个脚本独有的功能”，UI/配置/日志等直接复用。

- **不会让所有脚本长得一模一样**
  - Toolbox 提供“底盘/主题/控件/框架”。
  - 每个脚本决定“界面里放什么按钮、按钮点了做什么、业务逻辑怎么写”。

---

## 2. 目录结构（你只需要记住 2 个入口）

- `Lee_Scripts/Lee_UI - Demo.lua`
  - **入口脚本**（Action List 里好找）
  - 运行它会自动转到 Shared 里真正的 Demo。

- `Lee_Scripts/Shared/Toolbox/`
  - `Demo_UI.lua`：**示例脚本**（演示怎么用 Toolbox 开 UI）
  - `framework/`：真正的模块都在这里
  - `fonts/`：可选字体目录（放 `.ttf/.otf`）

---

## 3. 运行 Demo（你只需要会这一步就能看到效果）

1) 确保装了 ReaImGui
- 打开 REAPER → ReaPack → Browse packages
- 搜索并安装：`ReaImGui: ReaScript binding for Dear ImGui`

2) 运行 Demo
- Actions → Show action list → ReaScript → Load...
- 选择：`Lee_Scripts/Lee_UI - Demo.lua`
- 运行后会打开一个 UI 窗口（带 Log/Terminal/Theme/Style 等示例）

---

## 4. 以后写新脚本，怎么“引用 Toolbox”？（最重要）

你不需要懂很多 Lua。
你只需要把下面这段“模板”复制到新脚本里，然后在 `draw()` 里写你自己的按钮。

### 4.1 最小模板（建议复制）

```lua
-- 你的脚本：一个最小 UI 示例

local function script_dir()
  local src = debug.getinfo(1, 'S').source
  return src:match('^@(.+[\\/])')
end

local root = script_dir()

-- 关键：把 Toolbox 的模块路径加进来
package.path = root .. 'Shared/Toolbox/framework/?.lua;' .. package.path

local bootstrap = require('bootstrap')
local ImGui = bootstrap.ensure_imgui('0.9')
if not ImGui then return end

local App = require('app').App
local Theme = require('ui_theme')
local Log = require('log')

local app = App.new(ImGui, {
  title = 'My Script UI',
  ext_section = 'My_Script_UI_Config',
})

local function draw()
  local ctx = app.ctx
  ImGui.Text(ctx, 'Hello UI')

  if ImGui.Button(ctx, 'Do Something') then
    Log.info(app.log, 'clicked!')
  end

  if ImGui.Button(ctx, 'Close') then
    app.open = false
  end
end

local function loop()
  Theme.begin(app)

  local visible, open
  if app.open == false then
    visible, open = false, false
  else
    visible, open = app:begin_window()
    if visible then draw() end
    app:end_window()
    if app.open == false then open = false end
  end

  Theme.end_(app)

  if open then
    reaper.defer(loop)
  else
    Theme.destroy(app)
    app:destroy()
  end
end

reaper.defer(loop)
```

### 4.2 你应该改哪里？
- **改窗口标题**：`title = 'My Script UI'`
- **改配置名**：`ext_section = 'My_Script_UI_Config'`
  - 不同脚本用不同 ext_section，避免互相覆盖设置。
- **改 draw() 里面的内容**：这就是你脚本的 UI。

---

## 5. framework 里每个模块大概是干啥的（简单解释）

- `bootstrap.lua`
  - 检查是否安装了 ReaImGui，没装就提示。

- `app.lua`
  - 管理窗口：打开/关闭、窗口 flags、focus 状态。

- `ui_theme.lua` / `ui_colors.lua` / `ui_style.lua` / `ui_font.lua`
  - 统一外观：主题颜色、圆角间距、字体层级。

- `config.lua`
  - 把 UI 设置保存到 ExtState（比如 scale、是否显示 log 等）。

- `log.lua`
  - 一个 Log 缓冲区 + UI 展示（filter/copy/clear）。

- `terminal.lua`
  - 简易终端：输入 Lua 表达式执行（主要用于调试）。

- `dock.lua`
  - DockSpace（如果你的 ReaImGui 支持就启用，不支持就自动降级）。

- `widgets.lua`
  - 小组件封装（help marker、separator text 等）。

- `icon_bar.lua`
  - 顶部工具栏（开关 Log/Theme/Style/Terminal 等）。

- `editors.lua`
  - Theme/Style 的调试窗口（可改颜色/样式）。

---

## 6. 常见问题（你遇到过的那种）

- **(1) 没有关闭按钮 / 点了关不掉**
  - 这个框架里是靠 `app.open = false` 来关闭的。
  - 你自己的脚本里建议总保留一个 `Close` 按钮。

- **(2) Dock/表格/某些控件报错**
  - 这是 ReaImGui 版本差异导致的。
  - Toolbox 已经尽量做了兼容（不可用就降级），但不同 REAPER/ImGui 组合仍可能缺 API。

- **(3) 主题编辑器 ColorEdit 报参数错误**
  - 你的 ReaImGui 可能只支持某一种签名。
  - Toolbox 目前用的是更兼容的 U32 方式。

---

## 7. 你只需要怎么“跟我提需求”

以后你可以直接这样说：
- “给 `XXX.lua` 加一个设置窗口，用 Shared/Toolbox 的 UI 风格。”
- “这个脚本要 3 个开关 + 2 个按钮 + 一个列表，配置要保存。”
- “再加一个 Log 窗口/Terminal 窗口，用 Toolbox 的模块。”

我会默认复用 `Shared/Toolbox/framework`，保证风格统一、代码不重复。
