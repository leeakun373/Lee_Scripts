# Marker Workstation - 模块化架构

## 目录结构

```
Markers/
└── MarkersWorkstation/               # 完整的模块化结构
    ├── Lee_Markers - Workstation.lua # ⭐ 主入口（启动这个文件）
    ├── MarkerFunctions/              # 功能模块目录 ✅
    │   ├── CopyMarkerToCursor.lua
    │   ├── CreateMarkersFromItems.lua
    │   └── ... (所有功能模块都在这里)
    ├── Modules/
    │   ├── GUI.lua                   # GUI 渲染模块（待完成）
    │   ├── LayoutManager.lua          # 布局管理模块（待完成）
    │   ├── CustomActionsManager.lua   # 自定义操作管理模块（待完成）
    │   ├── DataManager.lua            # 数据持久化模块 ✅
    │   └── FunctionLoader.lua         # 功能加载器模块 ✅
    ├── Config/
    │   ├── Colors.lua                 # 颜色配置 ✅
    │   └── Constants.lua              # 常量定义 ✅
    └── Utils/
        └── Helpers.lua                # 工具函数 ✅
```

## 重要说明

1. **MarkerFunctions 位置**：功能模块在 `MarkersWorkstation/MarkerFunctions/` 目录
   - **新增功能都在这里添加**：创建新的 `.lua` 文件即可自动加载
   - 每个功能都是独立的小模块，易于维护和扩展
2. **数据兼容性**：所有数据（Custom actions、布局等）使用相同的 ExtState key，完全兼容原脚本
3. **启动方式**：直接运行 `Lee_Markers - Workstation.lua`，和之前一样
4. **自定义操作不增加代码大小**：
   - 自定义操作只存储数据（名称、Action ID、描述、类型）
   - 数据保存在 REAPER 的 ExtState 中，不在代码文件里
   - 即使添加很多自定义操作，代码文件大小不变

## 模块职责

### 已完成模块

1. **Config/Constants.lua** - 所有常量定义
2. **Config/Colors.lua** - 颜色配置
3. **Utils/Helpers.lua** - 工具函数（PushBtnStyle, validateActionID, getTooltipText）
4. **Modules/DataManager.lua** - 所有 ExtState 读写操作
   - Window state
   - Function order
   - Layout
   - Layout presets
   - Custom actions
   - Script state (toggle)
5. **Modules/FunctionLoader.lua** - 功能模块加载
   - 从 MarkerFunctions 目录加载
   - 按保存的顺序排序
   - 获取函数（内置和自定义）

### 待完成模块

1. **Modules/LayoutManager.lua** - 布局管理逻辑
   - Active/Stash 管理
   - 布局预设管理
   - 初始化布局

2. **Modules/CustomActionsManager.lua** - 自定义操作管理
   - 添加/编辑/删除自定义操作
   - 验证 Action ID

3. **Modules/GUI.lua** - GUI 渲染
   - 所有 ImGui 界面代码
   - 标签页渲染
   - 按钮渲染

4. **Lee_Markers - Workstation.lua** - 主入口
   - 初始化检查
   - 模块加载
   - 主循环协调

## 使用方式

### 模块加载

使用 `loadfile` 直接加载（兼容 REAPER Lua 环境）：

```lua
-- 在主脚本中
local function loadModule(module_path)
    local f = loadfile(module_path)
    if f then
        return f()
    end
    return nil
end

-- 加载模块
local Constants = loadModule(script_path .. "Config" .. path_sep .. "Constants.lua")
local DataManager = loadModule(script_path .. "Modules" .. path_sep .. "DataManager.lua")
```

### 数据流

1. **初始化**：Lee_Markers - Workstation.lua → 加载所有模块 → 初始化状态
2. **数据加载**：DataManager.load*() → 从 ExtState 读取（兼容原数据）
3. **功能加载**：FunctionLoader.loadFunctions() → 从 `MarkerFunctions/` 加载（同目录下）
4. **GUI 渲染**：GUI.render() → 使用所有模块
5. **数据保存**：DataManager.save*() → 写入 ExtState（使用相同 key，兼容原数据）

### Custom Actions 数据位置

Custom actions 数据保存在 REAPER 的 ExtState 中：
- Section: `MarkerWorkstation`
- Keys: `CustomAction_*_Name`, `CustomAction_*_ID`, `CustomAction_*_Description`, `CustomAction_*_Type`

**完全兼容原脚本的数据**，迁移后可以继续使用之前添加的自定义操作。

## 优势

1. **职责单一**：每个模块只负责一个功能
2. **易于维护**：修改某个功能只需修改对应模块
3. **易于扩展**：添加新功能只需添加新模块
4. **低耦合**：模块之间通过接口通信
5. **AI 友好**：结构清晰，AI 修改时只需关注相关文件

## 下一步

1. 完成 LayoutManager 模块
2. 完成 CustomActionsManager 模块
3. 完成 GUI 模块
4. 完成 Main.lua 主入口
5. 测试和优化

