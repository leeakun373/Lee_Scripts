# REAPER UI框架资源网站

## 📚 官方文档和资源

### 1. ReaImGui (官方推荐)
- **官方文档**: https://github.com/cfillion/reaimgui
- **API参考**: 在REAPER中安装ReaImGui后，查看 `Extensions > ReaImGui > Documentation`
- **示例脚本**: 
  - `ReaTeam Scripts/Development/` 目录下有很多示例
  - 搜索包含 `ImGui_` 的脚本
- **特点**: 
  - 免费开源
  - 性能优秀
  - 持续更新
  - 可自由使用和修改

### 2. REAPER Toolkit (rtk)
- **官方网站**: https://reapertoolkit.dev/
- **GitHub**: https://github.com/jtackaberry/reapertoolkit
- **文档**: https://reapertoolkit.dev/docs/
- **教程**: https://reapertoolkit.dev/tutorial/
- **特点**:
  - 完全免费开源 (MIT License)
  - 可以自由搬运和使用
  - 专为REAPER设计
  - 流式布局系统

### 3. Lokasenna GUI v2
- **GitHub**: https://github.com/jalovatt/Lokasenna_GUI
- **文档位置**: `ReaTeam Scripts/Development/Lokasenna_GUI v2/`
- **示例模板**: `Development/Lokasenna_GUI v2/Developer Tools/Examples and Templates/`
- **特点**:
  - 免费开源
  - 广泛使用
  - 基于gfx API
  - 可以自由使用

### 4. Scythe Library v3
- **位置**: `ReaTeam Scripts/Development/Scythe library v3/`
- **示例**: `Development/Scythe library v3/development/examples/`
- **特点**:
  - 免费开源
  - 现代UI框架
  - 可以自由使用

## 🌐 社区资源网站

### REAPER论坛
- **主论坛**: https://forum.cockos.com/
- **ReaScript子论坛**: https://forum.cockos.com/forumdisplay.php?f=3
- **UI开发讨论**: 搜索 "ReaImGui", "rtk", "GUI framework"

### ReaPack资源
- **ReaPack**: REAPER内置的包管理器
- **安装方式**: `Extensions > ReaPack > Browse packages`
- **搜索关键词**: 
  - `ReaImGui` - 官方UI框架
  - `rtk` - REAPER Toolkit
  - `Lokasenna GUI` - GUI库
  - `Scythe` - Scythe框架

### GitHub资源
1. **ReaImGui**: https://github.com/cfillion/reaimgui
2. **rtk**: https://github.com/jtackaberry/reapertoolkit
3. **Lokasenna GUI**: https://github.com/jalovatt/Lokasenna_GUI
4. **REAPER脚本集合**: 
   - https://github.com/ReaTeam/ReaScripts (ReaTeam官方)
   - https://github.com/X-Raym/REAPER-ReaScripts (X-Raym)
   - https://github.com/michaelpilyavskiy/ReaScripts (MPL)

## 📖 本地资源（你的REAPER安装中）

### 示例脚本位置
```
C:\Users\DELL\AppData\Roaming\REAPER\Scripts\
├── ReaTeam Scripts\Development\
│   ├── Lokasenna_GUI v2\          # Lokasenna GUI完整库和示例
│   │   ├── Developer Tools\        # 开发工具和模板
│   │   └── Library\                # 库文件
│   └── Scythe library v3\          # Scythe框架
│       ├── development\examples\   # 示例脚本
│       └── library\                # 库文件
└── ReaTeam Extensions\API\
    └── gfx2imgui.lua               # gfx到ImGui的转换层
```

### 可搬运的UI组件
1. **Lokasenna GUI模板**: 
   - `Template - Blank GUI script.lua` - 空白模板
   - `Example - General demonstration.lua` - 通用示例
   - `Example - Menubar, Listbox, and TextEditor.lua` - 控件示例

2. **Scythe示例**:
   - `Scythe_Example - General demonstration.lua`
   - `Scythe_Example - Working with Images.lua`

3. **ReaImGui示例**:
   - 搜索包含 `ImGui_CreateContext` 的脚本

## 🔧 实用工具

### 开发工具
- **Lokasenna GUI Builder**: `Development/Lokasenna_GUI v2/Developer Tools/GUI Builder/`
- **cfillion_Interactive ReaScript**: 交互式脚本开发工具
- **cfillion_Lua profiler**: 性能分析工具

## ⚖️ 许可证说明

### 可以自由使用的框架
- ✅ **ReaImGui**: MIT License - 可自由使用和修改
- ✅ **rtk**: MIT License - 可自由使用和修改
- ✅ **Lokasenna GUI v2**: 开源 - 可自由使用
- ✅ **Scythe**: 开源 - 可自由使用

### 使用建议
1. **查看许可证**: 每个框架的许可证文件通常在GitHub仓库中
2. **保留版权声明**: 使用开源代码时保留原作者信息
3. **遵守许可证**: 大多数REAPER脚本框架都是MIT或类似宽松许可证

## 🚀 快速开始

### 1. 安装ReaImGui（推荐）
```
Extensions > ReaPack > Browse packages > 搜索 "ReaImGui" > 安装
```

### 2. 查看示例
```
Actions > Show action list > 搜索 "ImGui" 或 "GUI"
```

### 3. 学习资源
- 打开 `ReaTeam Scripts/Development/` 中的示例脚本
- 阅读脚本注释
- 参考GitHub上的文档

## 📝 推荐学习路径

1. **初学者**: Lokasenna GUI v2（文档完善，示例多）
2. **进阶**: ReaImGui（性能好，官方推荐）
3. **高级**: rtk（功能强大，需要一定学习曲线）

## 🔗 有用的链接

- REAPER官方文档: https://www.reaper.fm/sdk/
- REAPER API文档: https://www.extremraym.com/cloud/reascript-doc/
- REAPER论坛: https://forum.cockos.com/
- ReaPack索引: https://github.com/ReaTeam/ReaPack-index

