# reaper_lee_tools

Windows 版 REAPER C++ 扩展 DLL。Lua 不好做或不该做的底层能力集中在这里。

## 动作


| Action ID                     | 说明                   |
| ----------------------------- | -------------------- |
| `Lee_DropStation_Open`        | 打开 / 关闭 Drop Station |
| `Lee_DropStation_AddSelected` | 将选中 item 加入列表        |
| `Lee_ItemHub_Show`            | Item Hub（按住调整参数）     |
| `Lee_ProjectExplorer_Open`    | Project File Explorer — 打开 / 关闭工程文件浏览器 |
| `Lee_ProjectExplorer_OpenProjectFolder` | Project File Explorer — 直接打开当前工程目录 |
| `Lee_Splitter_Open`           | Element Split — 打开 / 关闭窗口 |
| `Lee_RadialMenu_Open`         | 轮盘菜单 — 打开 / 关闭（需 JS_ReaScriptAPI） |
| `Lee_RadialMenu_Setup`        | 轮盘菜单 — 设置编辑器 |


## 依赖

- REAPER
- [ReaImGui](https://github.com/cfillion/reaimgui)（Drop Station / Item Hub / Splitter / RadialMenu 需要）
- [JS_ReaScriptAPI](https://github.com/juliansader/ReaExtensions)（RadialMenu 打开轮盘需要）

## 安装

**预编译**：复制 `[release/reaper_lee_tools.dll](release/reaper_lee_tools.dll)` 到 `%APPDATA%\REAPER\UserPlugins\`，重启 REAPER。

**自行编译**：

```powershell
powershell -ExecutionPolicy Bypass -File ".\scripts\build_and_deploy.ps1"
```

## 目录

```
src/plugin/          插件壳、Action 注册
src/shared/          ReaImGui、UI 主题
src/platform/win/    系统能力（如拖拽）
src/features/        各功能模块（drop_station、item_hub …）
```

## 功能简述

**Drop Station** — 切片中转列表，支持拖出 CF_HDROP、拖回时复刻属性，数据存工程 ExtState `Lee_DropStation`。

**Item Hub** — 选中 item 后快捷调整音量、 pitch、 fade、 pan、 reverse 等；多选时部分参数为相对量。

**Project File Explorer** — 当前工程目录浏览器，支持工程 tab 切换自动刷新、双击打开/插入、系统级文件拖入 REAPER 编排区，以及直接打开当前工程目录。

**Splitter（Element Split）** — 五种元素分离算法 + Quick 一键模式；批处理写轨、试听、多 item 并行。用户文档见 `Doc/LeeTools/functions/splitter.md`。

**RadialMenu** — 轮盘快捷菜单；与 Lua 版共用 `RadialMenu_Tool/config.json`。开发区见 `C_Extensions/RadialMenu/`。

## 开发

- 新功能放在 `src/features/<name>/`，在 `FeatureRegistry.cpp` 注册。
- Action 命名：`Lee_<Category>_<Verb>`，描述：`Lee: Category — Label`。
- `include/`、`third_party/`、`build/` 由构建脚本生成，勿提交。

### 改代码后：编译并部署

修改 C++ 源码后**必须**执行构建脚本，DLL 才会写入 REAPER 插件目录；**重启 REAPER** 后新行为才生效。

```powershell
cd C_Extensions\LeeTools
powershell -ExecutionPolicy Bypass -File ".\scripts\build_and_deploy.ps1"
```

脚本会：配置 CMake → Release 编译 → 复制 `reaper_lee_tools.dll` 到 `%APPDATA%\REAPER\UserPlugins\`。

依赖：CMake（PATH）、Visual Studio（MSVC）。ReaImGui 头文件与 REAPER SDK 头文件由脚本自动下载。

详细架构与变更记录见 `Doc/LeeTools/ARCHITECTURE.md`。

