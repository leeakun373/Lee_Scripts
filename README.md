# Lee Scripts 脚本库

https://github.com/leeakun373/Lee_Scripts/raw/master/index.xml

REAPER Lua脚本集合，按功能分类管理。

## 📁 目录结构

```
Lee_Scripts/
├── FX/                    # FX相关操作和管理工具
│   ├── FXMiner/           # FX浏览器和保存工具
│   ├── Lee_FX - Manager.lua
│   ├── Lee_FX - Open All Track FX Windows.lua
│   ├── Lee_FX - Close All FX Windows.lua
│   ├── Lee_FX - Toggle Bypass or Active.lua
│   └── Lee_FX - Toggle FX Chain Window.lua
├── Items/                 # Items相关操作
│   ├── ItemParameterCopier/  # Item参数复制工具
│   ├── Lee_Items - Add Fade In Out.lua
│   ├── Lee_Items - Bounce Items.lua
│   ├── Lee_Items - Implode Mono to Stereo.lua
│   ├── Lee_Items - Jump to Next.lua
│   ├── Lee_Items - Jump to Previous.lua
│   ├── Lee_Items - Move Cursor to Item End.lua
│   ├── Lee_Items - Move Cursor to Item Start.lua
│   ├── Lee_Items - Select All Items on Track.lua
│   ├── Lee_Items - Select Unmuted Items.lua
│   ├── Lee_Items - Slip-Edit Align Peak.lua
│   ├── Lee_Items - Split at Time Selection.lua
│   ├── Lee_Items - Toggle Time Selection to Items.lua
│   ├── Lee_Items - Trim Items to Reference Length.lua
│   └── Lee_Items - Trim to Time Selection.lua
├── Tracks/                # Tracks相关操作
├── Takes/                  # Takes相关操作
├── Markers/                # Markers相关操作
│   ├── UCS Rename Tools/   # UCS重命名工具
│   ├── Lee_Markers - Align Items To Markers.lua
│   ├── Lee_Markers - Copy Marker To Cursor.lua
│   ├── Lee_Markers - Create Markers From Items.lua
│   ├── Lee_Markers - Create Regions From Markers.lua
│   ├── Lee_Markers - Delete Markers In Time Selection.lua
│   ├── Lee_Markers - Move Marker To Cursor.lua
│   ├── Lee_Markers - Move Marker To Selected Item.lua
│   ├── Lee_Markers - Renumber Markers.lua
│   └── Lee_Markers - Take Marker Manager.lua
├── RadialMenu_Tool/        # 轮盘菜单工具
├── Main/                   # 主要工作流脚本
│   └── Lee_Main - Project File Explorer.lua
└── Shared/                  # 共享工具和框架
    ├── Toolbox/            # UI框架工具
    └── Lee_UI - Demo.lua
```

## 📝 命名规范

**格式：** `Lee_[分类] - [功能描述].lua`

### 分类前缀

- `Lee_FX` - FX操作（打开/关闭窗口、切换Bypass、管理FX等）
- `Lee_Items` - Items操作（分割、裁剪、fade、移动等）
- `Lee_Tracks` - Tracks操作（创建、删除、路由等）
- `Lee_Takes` - Takes操作（标记、切换、编辑等）
- `Lee_Markers` - Markers操作（创建、移动、删除等）
- `Lee_Main` - 主要工作流（放在Main目录）

### 示例

```
Lee_FX - Open All Track FX Windows.lua
Lee_Items - Split at Time Selection.lua
Lee_Items - Add Fade In Out.lua
Lee_Markers - Copy Marker To Cursor.lua
Lee_Main - Project File Explorer.lua
```

## 🚀 使用方法

1. 在REAPER中，通过 `Actions` → `Show action list` → `ReaScript` 加载脚本
2. 或直接将脚本添加到工具栏
3. 脚本按字母顺序排列，使用统一前缀便于查找

## 📋 脚本列表

### FX（效果器管理）

- `Lee_FX - Manager.lua` - FX管理器（模块化GUI工具）
- `Lee_FX - Open All Track FX Windows.lua` - 打开所选轨道/媒体项的所有FX窗口并自动排列
- `Lee_FX - Close All FX Windows.lua` - 关闭所有FX窗口和FX Chain窗口
- `Lee_FX - Toggle Bypass or Active.lua` - 切换所选轨道/媒体项的FX Bypass/Active状态
- `Lee_FX - Toggle FX Chain Window.lua` - 切换所选轨道/媒体项的FX Chain窗口
- `FXMiner/` - FX浏览器和保存工具

### Items（媒体项操作）

- `Lee_Items - Add Fade In Out.lua` - 给选中的items添加0.2秒fade in/out
- `Lee_Items - Bounce Items.lua` - 渲染选中的items
- `Lee_Items - Implode Mono to Stereo.lua` - 将匹配的单声道items合并为立体声item
- `Lee_Items - Jump to Next.lua` - 跳转到下一个Item
- `Lee_Items - Jump to Previous.lua` - 跳转到上一个Item
- `Lee_Items - Move Cursor to Item End.lua` - 移动光标到Item结束位置
- `Lee_Items - Move Cursor to Item Start.lua` - 移动光标到Item起始位置
- `Lee_Items - Select All Items on Track.lua` - 选择轨道上的所有Items
- `Lee_Items - Select Unmuted Items.lua` - 选择未静音的Items
- `Lee_Items - Slip-Edit Align Peak.lua` - 对齐Item峰值到光标
- `Lee_Items - Split at Time Selection.lua` - 在时间选区两端进行分割
- `Lee_Items - Toggle Time Selection to Items.lua` - 切换时间选区到Items
- `Lee_Items - Trim Items to Reference Length.lua` - 裁剪Items到参考长度
- `Lee_Items - Trim to Time Selection.lua` - 将items裁剪到时间选区
- `ItemParameterCopier/` - Item参数复制工具

### Markers（标记操作）

- `Lee_Markers - Align Items To Markers.lua` - 对齐Items到Markers
- `Lee_Markers - Copy Marker To Cursor.lua` - 复制最近的marker到光标处
- `Lee_Markers - Create Markers From Items.lua` - 从选中items创建markers
- `Lee_Markers - Create Regions From Markers.lua` - 从Markers创建Regions
- `Lee_Markers - Delete Markers In Time Selection.lua` - 删除时间选区内的所有markers
- `Lee_Markers - Move Marker To Cursor.lua` - 移动最近的marker到光标处
- `Lee_Markers - Move Marker To Selected Item.lua` - 移动marker到选中的Item
- `Lee_Markers - Renumber Markers.lua` - 重新编号Markers
- `Lee_Markers - Take Marker Manager.lua` - Take Marker管理器
- `UCS Rename Tools/` - UCS重命名工具（支持UCS标准标记重命名）

### RadialMenu Tool（轮盘菜单）

- `Lee_RadialMenu.lua` - 轮盘菜单主运行入口
- `Lee_RadialMenu_Setup.lua` - 轮盘菜单设置编辑器
  - 可视化编辑扇区和插槽
  - 支持Actions、FX、FX Chains、Track Templates
  - 拖放式配置界面
  - 实时预览
  - 中英文双语支持

### Main（主要工作流）

- `Lee_Main - Project File Explorer.lua` - 项目文件浏览器

### Shared（共享工具）

- `Toolbox/` - UI框架工具集
- `Lee_UI - Demo.lua` - UI演示脚本
