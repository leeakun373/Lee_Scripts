# Lee Scripts 脚本库

REAPER Lua脚本集合，按功能分类管理。

## 📁 目录结构

```
Lee_Scripts/
├── FX/                    # FX相关操作和管理工具
│   ├── Lee_FX - Manager.lua              # FX管理器（模块化GUI工具）
│   ├── Lee_FX - Open All Track FX Windows.lua
│   ├── Lee_FX - Close All FX Windows.lua
│   ├── Lee_FX - Toggle Bypass or Active.lua
│   ├── Lee_FX - Toggle FX Chain Window.lua
│   └── Modules/           # FX管理器模块
├── Items/                 # Items相关操作（分割、裁剪、fade等）
│   ├── ItemsWorkstation/  # Items工作站（模块化GUI工具）
│   └── ItemParameterCopier/ # Item参数复制工具
├── Tracks/                # Tracks相关操作
├── Takes/                  # Takes相关操作
├── Markers/                # Markers相关操作（工作站+功能模块）
│   ├── MarkersWorkstation/ # Marker工作站（模块化GUI工具）
│   └── UCS Rename Tools/   # UCS重命名工具
├── RadialMenu_Tool/        # 轮盘菜单工具（现代化轮盘菜单系统）
├── Main/                   # 主要工作流脚本
└── Doc/                    # 文档目录
```

## 📝 命名规范

**格式：** `Lee_[分类] - [功能描述].lua`

### 分类前缀

- `Lee_FX` - FX操作（打开/关闭窗口、切换Bypass、管理FX等）
- `Lee_Items` - Items操作（分割、裁剪、fade、移动等）
- `Lee_Tracks` - Tracks操作（创建、删除、路由等）
- `Lee_Takes` - Takes操作（标记、切换、编辑等）
- `Lee_Markers` - Markers操作（工作站、功能模块等）
- `Lee_Workflow` - 工作流自动化
- `Lee_Utils` - 工具类脚本
- `Lee_Main` - 主要工作流（放在Main目录）
- `Lee_Test` - 测试脚本（放在test目录）

### 示例

```
Lee_FX - Open All Track FX Windows.lua
Lee_Items - Split at Time Selection.lua
Lee_Items - Add Fade In Out.lua
Lee_Tracks - Add New Track.lua
Lee_Markers - Workstation.lua
Lee_Workflow - Auto Move Item.lua
```

## 🚀 使用方法

1. 在REAPER中，通过 `Actions` → `Show action list` → `ReaScript` 加载脚本
2. 或直接将脚本添加到工具栏
3. 脚本按字母顺序排列，使用统一前缀便于查找

## 📋 脚本列表

### FX（效果器管理）
- `Lee_FX - Manager.lua` - FX管理器（模块化GUI工具）
  - 打开/关闭所有FX窗口
  - 切换Bypass/Active状态
  - 切换FX Chain窗口
  - 快速加载FX插件
- `Lee_FX - Open All Track FX Windows.lua` - 打开所选轨道/媒体项的所有FX窗口并自动排列
- `Lee_FX - Close All FX Windows.lua` - 关闭所有FX窗口和FX Chain窗口
- `Lee_FX - Toggle Bypass or Active.lua` - 切换所选轨道/媒体项的FX Bypass/Active状态
- `Lee_FX - Toggle FX Chain Window.lua` - 切换所选轨道/媒体项的FX Chain窗口

### Items（媒体项操作）
- `Lee_Items - Workstation.lua` - Items工作站（模块化GUI工具）
  - 跳转到上一个/下一个Item
  - 移动光标到Item起始/结束位置
  - 选择未静音的Items
  - 裁剪Items到参考长度
  - 添加Fade In/Out
  - 选择轨道上的所有Items
  - 对齐Item峰值到光标
- `Lee_Items - Split at Time Selection.lua` - 在时间选区两端进行分割
- `Lee_Items - Add Fade In Out.lua` - 给选中的items添加0.2秒fade in/out
- `Lee_Items - Trim to Time Selection.lua` - 将items裁剪到时间选区（选中items或所有重叠items）
- `Lee_Items - Implode Mono to Stereo.lua` - 将匹配的单声道items合并为立体声item
- `Lee_Items - Copy Paste Parameters.lua` - Item参数复制工具

### Markers（标记操作）
- `Lee_Markers - Workstation.lua` - Marker工作站（模块化GUI工具）
  - Copy to Cursor - 复制最近的marker到光标处
  - Move to Cursor - 移动最近的marker到光标处
  - Create from Items - 从选中items创建markers（优化版，避免重复）
  - Delete in Time Selection - 删除时间选区内的所有markers
- `Lee_Markers - UCS RenameTools.lua` - UCS重命名工具（支持UCS标准标记重命名）

### RadialMenu Tool（轮盘菜单）
- `Lee_RadialMenu.lua` - 轮盘菜单主运行入口
- `Lee_RadialMenu_Setup.lua` - 轮盘菜单设置编辑器
  - 可视化编辑扇区和插槽
  - 支持Actions、FX、FX Chains、Track Templates
  - 拖放式配置界面
  - 实时预览

### Main（主要工作流）
- `Lee_Main - Project File Explorer.lua` - 项目文件浏览器

## 🔄 工作流程

### 开发流程
1. **测试阶段**：在 `test/` 目录下创建和测试脚本
2. **验证通过**：功能稳定后，移至对应的正式分类目录
3. **命名规范**：使用 `Lee_[分类] - [功能描述].lua` 格式

### Marker功能添加流程
1. 在 `test/MarkerFunctions/` 创建新功能模块进行测试
2. 测试通过后，复制到 `Markers/MarkerFunctions/`
3. Marker Workstation会自动加载新功能

## 📚 文档

- **[文档目录](Doc/README.md)** - 完整文档索引
- **[版本控制指南](Doc/VERSION_CONTROL_GUIDE.md)** - Git 使用和版本管理
- **[项目维护指南](Doc/MAINTENANCE.md)** - 项目维护规范

## 🔄 版本控制

本项目使用 Git 进行版本管理，已推送到 GitHub：
- **仓库地址**: https://github.com/leeakun373/Lee_Reaper_Scripts
- **版本控制指南**: 查看 [Doc/VERSION_CONTROL_GUIDE.md](Doc/VERSION_CONTROL_GUIDE.md)

### 快速开始

```bash
# 查看状态
git status

# 提交修改
git add .
git commit -m "feat: 添加新功能"
git push origin master
```

详细操作请参考 [版本控制指南](Doc/VERSION_CONTROL_GUIDE.md)。

## 🔄 更新日志

### 2024-12-09
- **RadialMenu Tool**: 修复右键菜单和工具提示功能，优化拖拽行为
- **RadialMenu Tool**: 为主脚本添加ReaPack headers
- **FX**: 从FXFunctions模块提取4个独立脚本（Open/Close FX Windows, Toggle Bypass, Toggle Chain）
- **Markers**: UCS Rename Tools更新和优化
- **清理**: 删除归档测试文件

### 2024-11-18
- 添加版本控制指南和维护文档
- 添加"Implode Mono to Stereo"功能（基于rodilab脚本）
- 修复Bounce脚本的offline问题（分离offline/online操作，添加错误检查）
- 整理根目录脚本，将有用脚本移至对应分类目录
- 添加"Delete in Time Selection"功能到Marker Workstation
- 创建Markers目录，Marker Workstation正式化

### 2024-11-17
- 创建分类目录结构，统一命名规范

