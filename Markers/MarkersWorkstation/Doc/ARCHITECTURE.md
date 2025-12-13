# 架构设计说明

## 设计原则

1. **小功能模块化**：MarkerFunctions 保持独立，每个功能都是独立的小模块
2. **数据兼容**：使用相同的 ExtState key，确保数据兼容
3. **向后兼容**：不影响现有功能，启动方式不变
4. **易于维护**：模块职责单一，修改时只需关注相关文件

## 文件组织

### 核心模块（已完成）

- **Config/Constants.lua** - 常量定义
- **Config/Colors.lua** - 颜色配置  
- **Utils/Helpers.lua** - 工具函数
- **Modules/DataManager.lua** - 数据持久化（ExtState 管理）
- **Modules/FunctionLoader.lua** - 功能模块加载器

### 待完成模块

- **Modules/LayoutManager.lua** - 布局管理
- **Modules/CustomActionsManager.lua** - 自定义操作管理
- **Modules/GUI.lua** - GUI 渲染

### 主入口

- **Lee_Markers - Workstation.lua** - 主脚本（启动这个）

## 数据兼容性

### ExtState Keys（保持不变）

所有数据使用相同的 ExtState section 和 keys：

- Section: `MarkerWorkstation`
- Window state: `WindowX`, `WindowY`, `WindowWidth`, `WindowHeight`
- Function order: `FunctionOrderCount`, `FunctionOrder_*`
- Layout: `ActiveFunctionCount`, `ActiveFunction_*`, `StashFunctionCount`, `StashFunction_*`
- Layout presets: `LayoutPresetCount`, `LayoutPreset_*_*`
- Custom actions: `CustomActionCount`, `CustomAction_*_Name`, `CustomAction_*_ID`, `CustomAction_*_Description`, `CustomAction_*_Type`
- Script state: `MarkerWorkstation_Running`, `MarkerWorkstation_CloseRequest`

**这意味着：**
- 原脚本的数据可以无缝迁移
- Custom actions 会自动加载
- 布局配置会保留
- 窗口位置会记住

## MarkerFunctions 位置

MarkerFunctions 在 `MarkersWorkstation/MarkerFunctions/` 目录。

**新增功能都在这里添加**：只需在 `MarkerFunctions/` 目录下创建新的 `.lua` 文件，脚本会自动加载。

新脚本会从同目录加载这些功能模块：
```lua
local functions_dir = script_path .. "MarkerFunctions" .. path_sep
```

## 模块依赖关系

```
Lee_Markers - Workstation.lua
    ├── Config/Constants.lua
    ├── Config/Colors.lua
    ├── Utils/Helpers.lua
    ├── Modules/DataManager.lua
    ├── Modules/FunctionLoader.lua (依赖 DataManager)
    ├── Modules/LayoutManager.lua (依赖 DataManager)
    ├── Modules/CustomActionsManager.lua (依赖 DataManager, Helpers)
    └── Modules/GUI.lua (依赖所有其他模块)
```

## 优势

1. **小功能模块化**：MarkerFunctions 中的每个功能都是独立的小模块，易于添加和维护
2. **职责单一**：每个模块只负责一个功能，修改时不会影响其他模块
3. **数据兼容**：使用相同的 ExtState，完全兼容原脚本数据
4. **易于扩展**：添加新功能只需添加新模块或新 MarkerFunction
5. **AI 友好**：结构清晰，AI 修改时只需关注相关文件，降低修改成本

