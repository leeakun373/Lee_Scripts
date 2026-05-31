# reaper_lee_tools（Lee 个人 REAPER C++ 扩展）

本目录为 **Windows 专用** REAPER C++ 扩展 DLL：所有 Lua 无法实现或不宜实现的底层能力（系统 API、高性能计算、第三方 C/C++ 库）统一集成于此。

> **工程架构（扩展多功能时怎么放目录）**：见 [`Doc/LeeTools/ARCHITECTURE.md`](../../Doc/LeeTools/ARCHITECTURE.md)  
> 参考 Mantrika Tools 文档分层（Guide / Functions / Actions），目标结构为 `plugin/` + `shared/` + `platform/` + `features/*`。

## 已注册动作

| Action ID | Action List 描述 | 模块 |
|-----------|------------------|------|
| `Lee_DropStation_Open` | Lee: Drop Station — Open window | `features/drop_station/Register.cpp` |
| `Lee_DropStation_AddSelected` | Lee: Drop Station — Add selected items | `features/drop_station/Register.cpp` |
| `Lee_ItemHub_Show` | Lee: Item Hub — Hold to adjust | `features/item_hub/Register.cpp` |

## 运行时依赖

- **REAPER**（任何近代版本）
- **ReaImGui**（[cfillion/reaimgui](https://github.com/cfillion/reaimgui)，建议 ≥ v0.10）—— Drop Station UI 需要；未安装时打开窗口会提示，不影响 DLL 加载。

## 编译与部署

```powershell
powershell -ExecutionPolicy Bypass -File ".\scripts\build_and_deploy.ps1"
```

脚本会下载 SDK / ReaImGui 头文件（首次）、Release 编译，并将 `reaper_lee_tools.dll` 复制到 `%APPDATA%\REAPER\UserPlugins\`。

预编译 DLL 见 [`release/reaper_lee_tools.dll`](release/reaper_lee_tools.dll)，可直接复制到 `%APPDATA%\REAPER\UserPlugins\` 使用。

**重启 REAPER** 后在 Action List 搜索 `Lee: Drop Station`。

## 源码结构

```
LeeTools/
├── CMakeLists.txt
├── scripts/build_and_deploy.ps1
├── include/
├── third_party/reaimgui/
└── src/
    ├── plugin/                         # 插件壳
    │   ├── main.cpp
    │   ├── PluginContext.*
    │   ├── CommandRegistry.*
    │   └── FeatureRegistry.*           # 汇总各 feature 的 Register/Shutdown
    ├── shared/
    │   ├── reaper/ReaImGuiApi.*
    │   └── ui/LeeUiTheme.*
    ├── platform/win/OsFileDrag.*
    └── features/drop_station/
        ├── Register.*                  # Action 注册 + timer
        ├── domain/Model.*, Store.*, SliceReplicator.*
        └── ui/Window.*
```

### 新增功能（推荐流程）

完整规范见 [`Doc/LeeTools/ARCHITECTURE.md`](../../Doc/LeeTools/ARCHITECTURE.md) 第 9 节「检查清单」。摘要：

1. 在 `src/features/<name>/` 实现模块（`domain/` + `ui/` + `Register.cpp`）。
2. 在 `plugin/FeatureRegistry.cpp` 增加 `your_feature::Register()` / `Shutdown()`。
3. 共享代码放 `shared/` 或 `platform/`，禁止 feature 互相引用。
4. Action 命名：`Lee_<Category>_<Verb>` / `Lee: Category — Label`。
5. 用户文档：`Doc/LeeTools/functions/<name>.md`。

### Action 命名规范

- **ID**：`Lee_<Category>_<Verb>`，例如 `Lee_DropStation_Open`。
- **描述**（Action List 可见）：`Lee: <Category> — <简短说明>`，类别前置，便于搜索与分组。
- 不要注册仅供 Lua IPC 使用的隐藏动作；C++ 模块内部直接调用共享代码。

## Drop Station

- **Open**：打开/关闭中转站窗口（ReaImGui + Toolbox 主题）。
- **Add selected items**：不开窗口也可把当前选中 item 的切片快照追加到列表（适合绑快捷键）。
- **列表**：每条存 source path + take offset / length / fade / vol / playrate + item GUID；按 GUID 去重。
- **拖出**：在列表行上 **按下并拖动**（无需先单击选中）；支持 Ctrl/Shift 多选后一次拖出多个 CF_HDROP 文件。
- **拖回 REAPER**：勾选 *Replicate slice in REAPER*（默认开）后，drop 时自动复刻切片属性。
- **持久化**：`SetProjExtState` section `Lee_DropStation`，随工程保存。

旧版 Lua Drop Station（`Items/DropStation/`）已移除；功能由本 DLL 接管。

## 开发原则（摘要）

- **C++**：系统 API、CF_HDROP、无法用 Lua 做的部分；Drop Station 是用户同意的「C++ 驱动 ReaImGui」例外。
- **Lua**：其它 UI 与业务仍优先 Lua；不要在本 DLL 手搓 Win32/DX UI。
- **线程**：`DoDragDrop` 等阻塞 API 只在主线程 / timer 回调中调用，禁止在音频线程执行。
- **跨语言**：若将来需要 Lua 调用 C++，优先 ExtState 传字符串；不要为一次性 IPC 注册 Action。

## 忽略项

`include/`、`third_party/`、`build/` 由脚本生成，已在 `.gitignore` 中，勿提交。
