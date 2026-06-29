# RadialMenu 开发区（C++）

本目录是 **RadialMenu 轮盘菜单** C++ 复刻的开发区：规格文档 + 源码。编译产物通过 [LeeTools](../LeeTools/) 打入 `reaper_lee_tools.dll`。


| 目录             | 说明                                                  |
| -------------- | --------------------------------------------------- |
| [docs/](docs/) | 架构、schema、测试、迁移                                     |
| [src/](src/)   | C++ 实现（`Register`、`domain/`、`runtime/`、`ui/setup/`） |


**已上线 Lua 功能**（用户配置不变）：[RadialMenu_Tool](../../RadialMenu_Tool/)

## Action ID


| Action ID              | 说明                      |
| ---------------------- | ----------------------- |
| `Lee_RadialMenu_Open`  | 打开轮盘（需 JS_ReaScriptAPI） |
| `Lee_RadialMenu_Setup` | 设置编辑器                   |


## 配置路径

`%APPDATA%\REAPER\Scripts\Lee_Scripts\RadialMenu_Tool\config.json`（与 Lua 共用）

## 限制（Windows 首期）

- 轮盘锚点使用 `GetCursorPos` 屏幕像素，高 DPI 或多显示器时可能与光标略有偏移。
- 需 **ReaImGui** 与 **JS_ReaScriptAPI**（打开轮盘）。

## 编译

```powershell
cd ..\LeeTools
powershell -ExecutionPolicy Bypass -File ".\scripts\build_and_deploy.ps1"
```

## 文档

见 [docs/](docs/) 目录索引。