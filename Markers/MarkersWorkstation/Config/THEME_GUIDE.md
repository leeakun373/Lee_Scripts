# 主题系统使用指南

## 概述

主题系统已集成到 Marker Workstation 中，当前使用默认主题（保持原有配色）。

## 文件结构

- `Colors.lua` - 向后兼容的颜色定义（使用默认主题）
- `Themes.lua` - 主题系统核心（包含所有主题定义）

## 当前主题

**Default Theme** - 默认主题（保持原有配色）
- 所有现有颜色保持不变
- ImGui 窗口颜色使用默认值（nil = 使用 ImGui 默认）

## 如何添加新主题

在 `Themes.lua` 中添加新主题：

```lua
-- 示例：深色主题
Themes.dark = {
    name = "Dark",
    -- 按钮颜色
    BTN_MARKER_ON  = 0x90A4AEFF,
    BTN_MARKER_OFF = 0x555555AA,
    -- ... 其他颜色
    -- ImGui 窗口颜色
    WINDOW_BG      = 0x1E1E1EFF,  -- 深灰色背景
    TITLE_BG       = 0x2A2A2AFF,
    TITLE_BG_ACTIVE = 0x3A3A3AFF,
    FRAME_BG       = 0x2A2A2AFF,
    TEXT           = 0xEEEEEEFF,
}
```

然后在 `getAllThemes()` 函数中注册：

```lua
function Themes.getAllThemes()
    return {
        default = Themes.default,
        dark = Themes.dark,  -- 添加新主题
    }
end
```

## 颜色格式

所有颜色使用 `0xRRGGBBAA` 格式：
- `RR` = 红色 (00-FF)
- `GG` = 绿色 (00-FF)
- `BB` = 蓝色 (00-FF)
- `AA` = 透明度 (00-FF, FF = 不透明)

## 可用的 ImGui 颜色

- `WINDOW_BG` - 窗口背景
- `TITLE_BG` - 标题栏背景
- `TITLE_BG_ACTIVE` - 活动标题栏
- `FRAME_BG` - 框架背景
- `TEXT` - 文本颜色

设置为 `nil` 表示使用 ImGui 默认颜色。

## 维护性

- **单一职责**：每个主题都是独立的配置对象
- **易于扩展**：添加新主题只需在 Themes.lua 中添加新对象
- **向后兼容**：Colors.lua 保持原有接口，不影响现有代码
- **集中管理**：所有主题在一个文件中，易于维护

## 下一步

当你需要定制主题时，告诉我：
1. 主题名称
2. 想要的颜色方案
3. 是否需要改变窗口背景等 ImGui 颜色

我会帮你在 Themes.lua 中添加新主题。


























