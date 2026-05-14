# reaper_dropstation（Drop Station OS 拖拽驱动）

本目录为 **Windows 专用** REAPER C++ 扩展：通过 `DoDragDrop` + `CF_HDROP` 向操作系统或其它应用程序拖出**真实文件**（与 Lua/ReaImGui 的 `REAPER_FILE_PATH` 载荷不同）。

## 编译与部署

1. 安装 **CMake**、**Visual Studio 2022**（含 MSVC x64）并保证 `cmake` 在 PATH 中。
2. 在 PowerShell 中执行：

   ```powershell
   powershell -ExecutionPolicy Bypass -File ".\scripts\build_and_deploy.ps1"
   ```

   脚本会：

   - 从 [reaper-sdk](https://github.com/justinfrankel/reaper-sdk) 下载 `reaper_plugin.h` / `reaper_plugin_functions.h` 到 `include/`；
   - 在 `build/` 下配置并 **Release** 编译；
   - 将 `reaper_dropstation.dll` 复制到 `%APPDATA%\REAPER\UserPlugins\`。

3. **重启 REAPER**，在 Action List 中搜索 **`Lee_StartOSDragDrop`**（扩展动作描述：`Lee: Start OS Drag & Drop for File Path`）。

## 与 Lua（Drop Station）的配合

- Lua 在调用动作前写入扩展状态：

  - Section：`Toolbox_DropStation`
  - Key：`Toolbox_DropStation_ExportPath`
  - Value：已存在的 **`.wav` 绝对路径**（UTF-8）

- 然后执行 `Main_OnCommand(NamedCommandLookup(...), 0)`。C++ 从 `GetExtState` 读取路径并进入阻塞式 `DoDragDrop`，直到用户在外部完成拖放。

仓库内对应 Lua 为 `Items/DropStation/`，由 `drop_export.lua` 中的 `M.draw_drag_to_external` 与主脚本 `draw()` 调用衔接。

## 仓库忽略项

`include/` 下 SDK 头文件由脚本自动生成；`build/` 为本地生成目录。二者已在 `.gitignore` 中忽略，勿提交二进制构建产物。
