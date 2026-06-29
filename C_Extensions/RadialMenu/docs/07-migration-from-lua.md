# 从 Lua 迁移

## 配置

无需迁移：`config.json` 路径不变（`RadialMenu_Tool/config.json`）。C++ 与 Lua 共用 Preset 2.0 格式。

## Action 绑定

1. 打开 **Actions > Show action list**
2. 搜索并添加：
   - `Lee_RadialMenu_Open`（原 `Lee_RadialMenu.lua` 的快捷键改绑到此）
   - `Lee_RadialMenu_Setup`（原 `Lee_RadialMenu_Setup.lua`）
3. 可选：从旧 ReaScript 条目移除快捷键，避免重复触发

## 并行运行

不要同时运行 Lua 入口与 C++ Action：`RadialMenu_Tool/Running` ExtState 会互斥，但仍建议只保留一种入口。

## 依赖

确认已安装 **ReaImGui** 与 **JS_ReaScriptAPI**（与 Lua 版相同）。

## 回退

保留 `RadialMenu_Tool` 文件夹与 Lua 脚本；将快捷键改回 `Lee_RadialMenu.lua` 即可。
