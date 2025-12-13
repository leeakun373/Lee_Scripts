# 根目录脚本功能分析

## 📋 脚本功能总结

### 1. **Lee_FolderMode_Test.lua** - 文件夹组织工具
**功能：** 自动将选中的轨道组织成文件夹结构
- 第一个选中的轨道作为父文件夹
- 其他选中的轨道作为子轨道
- 自动移动到顶层
- GUI界面（ReaImGui）

**分类建议：** `Tracks/` 或 `Workflow/`

---

### 2. **Lee_TakeMarkerManagerV1.lua** - Take Marker管理器
**功能：** Take Marker和Project Marker之间的转换工具
- Copy to Project: 将Take Markers复制为Project Markers
- Paste from Project: 将Project Markers粘贴为Take Markers
- Clear Take Markers: 清除选中items的Take Markers
- Clear Project Markers: 清除所有Project Markers
- GUI界面（ReaImGui）

**分类建议：** `Takes/` 或 `Markers/`

---

### 3. **Lee_Trim selected items to Time Selection.lua** - 裁剪工具
**功能：** 将items裁剪到时间选区
- 如果有选中items：只处理选中的items
- 如果没有选中items：处理所有轨道上与time selection重叠的items
- 自动删除时间选区外的部分

**分类建议：** `Items/`

---

### 4. **Lee_WorkFlow_AutoMoveItem.lua** - 轨道内容转移工具
**功能：** 批量转移轨道内容（移动或复制）
- 支持8个源轨道到目标轨道的映射
- 自动匹配源轨道（[chan X]格式）
- 自动匹配目标轨道（根据Track Notes中的TYPE=MIC）
- 支持移动或复制模式
- GUI界面（ReaImGui）

**分类建议：** `Workflow/`

---

### 5. **Lee_Workflow_Backup and Clean Project.lua** - 工程备份清理工具
**功能：** 工程备份和清理工作流
- Save As: 另存工程
- Clean items: 清理所有被静音的items
- Clean tracks: 清理空轨道（包括静音的文件夹）
- Clean assets: 清理未使用的音频资源
- Render: 设置渲染格式为96k 24Bit Mono
- GUI界面（ReaImGui）

**分类建议：** `Workflow/`

---

### 6. **Lee_WorkFlow_Bounce.lua** - 渲染工具
**功能：** 渲染items或tracks（非常复杂的功能）
- 支持渲染items或tracks模式
- 支持pre/post fader
- 支持mono/stereo/multi通道
- 支持tail（延迟/混响尾音）
- 支持UNITE（合并交叉淡入淡出/重叠的items）
- 支持渲染后管理源轨道（隐藏/删除）

**分类建议：** `Workflow/`

---

### 7. **Lee_Workflow_JumpToNextItemOnTrack.lua** - 导航工具
**功能：** 跳转到选中轨道上的下一个item
- 移动编辑光标到下一个item的起始位置
- 自动滚动视图

**分类建议：** `Workflow/` 或 `Utilities/`

---

### 8. **Lee_Workflow_JumpToPreviousItemOnTrack.lua** - 导航工具
**功能：** 跳转到选中轨道上的上一个item
- 移动编辑光标到上一个item的起始位置
- 自动滚动视图

**分类建议：** `Workflow/` 或 `Utilities/`

---

## 📊 分类统计

| 分类 | 脚本数量 | 脚本列表 |
|------|---------|---------|
| **Items** | 1 | Trim selected items to Time Selection |
| **Takes** | 1 | TakeMarkerManagerV1 |
| **Tracks** | 1 | FolderMode_Test |
| **Workflow** | 5 | AutoMoveItem, Backup and Clean, Bounce, JumpToNextItem, JumpToPreviousItem |

---

## 🎯 建议的整理方案

### 方案1：按功能分类（推荐）

```
Lee_Scripts/
├── Items/
│   └── Lee_Items - Trim to Time Selection.lua  (重命名)
├── Takes/
│   └── Lee_Takes - Marker Manager.lua  (重命名)
├── Tracks/
│   └── Lee_Tracks - Create Folder Structure.lua  (重命名)
└── Workflow/
    ├── Lee_Workflow - Auto Move Items.lua  (重命名)
    ├── Lee_Workflow - Backup and Clean Project.lua
    ├── Lee_Workflow - Bounce Items.lua  (重命名)
    ├── Lee_Workflow - Jump to Next Item.lua  (重命名)
    └── Lee_Workflow - Jump to Previous Item.lua  (重命名)
```

### 方案2：保持Workflow为主

如果这些都是工作流相关，可以都放在Workflow目录：
```
Workflow/
├── Lee_Workflow - Auto Move Items.lua
├── Lee_Workflow - Backup and Clean Project.lua
├── Lee_Workflow - Bounce Items.lua
├── Lee_Workflow - Create Folder Structure.lua
├── Lee_Workflow - Jump to Next Item.lua
├── Lee_Workflow - Jump to Previous Item.lua
└── Lee_Workflow - Trim Items to Time Selection.lua
```

---

## 🔍 功能特点分析

### GUI脚本（3个）
1. **FolderMode_Test** - 文件夹组织
2. **TakeMarkerManagerV1** - Marker管理
3. **AutoMoveItem** - 轨道内容转移

### 工作流脚本（5个）
1. **Backup and Clean** - 工程维护
2. **Bounce** - 渲染处理
3. **AutoMoveItem** - 内容转移
4. **JumpToNextItem** - 导航
5. **JumpToPreviousItem** - 导航

### 简单工具（1个）
1. **Trim to Time Selection** - 裁剪工具

---

## 💡 建议

1. **TakeMarkerManager** 可以考虑整合到 **Marker Workstation** 中
2. **JumpToNextItem/PreviousItem** 可以合并为一个脚本（带参数）
3. **FolderMode_Test** 可以重命名为更清晰的名称
4. 所有脚本都应该遵循命名规范：`Lee_[分类] - [功能描述].lua`

