# UCS Rename Tools 重构方案

## 📁 目录结构

```
UCS Rename Tools/
├── Lee_Markers - UCS RenameTools.lua  (主入口，~100行)
├── Config/
│   ├── Constants.lua                  (配置常量)
│   └── Theme.lua                      (主题和UI样式)
├── Modules/
│   ├── DataLoader.lua                 (CSV加载和解析)
│   ├── UCSMatcher.lua                 (智能匹配逻辑)
│   ├── NameProcessor.lua              (名称处理和UCS格式)
│   ├── ProjectActions.lua              (工程交互操作)
│   └── GUI.lua                        (UI渲染主循环)
└── Utils/
    └── Helpers.lua                     (工具函数)
```

## 📦 模块职责划分

### 1. **Config/Constants.lua** (~150行)
- CSV文件路径配置
- 智能匹配权重配置 (WEIGHTS, MATCH_THRESHOLD)
- 降级词汇表 (DOWNGRADE_WORDS)
- 可选字段配置 (ucs_optional_fields)
- 应用状态初始化 (app_state)

### 2. **Config/Theme.lua** (~120行)
- PushModernSlateTheme() - 主题设置
- BtnNormal(), BtnToggle(), BtnPrimary(), BtnSmall() - 按钮样式
- 颜色常量定义（如果需要）

### 3. **Utils/Helpers.lua** (~50行)
- GetScriptPath()
- ParseCSVLine()
- Tokenize()
- EscapePattern()
- FilterMatch()

### 4. **Modules/DataLoader.lua** (~150行)
- LoadUserAlias()
- LoadUCSData()
- 返回 ucs_db 数据结构

### 5. **Modules/UCSMatcher.lua** (~100行)
- FindBestUCS(user_input)
- 智能匹配核心算法

### 6. **Modules/NameProcessor.lua** (~300行)
- UpdateFinalName(item)
- UpdateItemStatus(item)
- SyncFromID(item)
- AutoMatchItem(item)
- ParseUCSName(name)
- FillFieldToAll(field_key)
- ClearFieldToAll(field_key)
- ClearHiddenFieldsAndUpdate()
- ValidateField(field_key, value)
- UpdateAllItemsMode()

### 7. **Modules/ProjectActions.lua** (~200行)
- JumpToMarkerOrRegion(item)
- ReloadProjectData()
- ActionSmartPaste()
- ActionApply()
- ActionCopyOriginal()

### 8. **Modules/GUI.lua** (~600行)
- Loop() - 主UI循环
- 所有表格渲染逻辑
- 所有输入框和交互逻辑

### 9. **Lee_Markers - UCS RenameTools.lua** (主入口，~100行)
- 初始化 ImGui Context
- 加载所有模块
- 初始化数据
- 启动主循环

## 🔄 模块依赖关系

```
主入口
  ├─> Config/Constants.lua
  ├─> Config/Theme.lua
  ├─> Utils/Helpers.lua
  ├─> Modules/DataLoader.lua (依赖 Helpers)
  ├─> Modules/UCSMatcher.lua (依赖 Constants, Helpers)
  ├─> Modules/NameProcessor.lua (依赖 Constants, DataLoader, UCSMatcher)
  ├─> Modules/ProjectActions.lua (依赖 Constants, NameProcessor)
  └─> Modules/GUI.lua (依赖所有模块)
```

## ✅ 重构优势

1. **可维护性**：每个模块职责单一，易于定位和修改
2. **可测试性**：可以单独测试每个模块
3. **可扩展性**：新增功能只需添加新模块
4. **可读性**：主文件只有100行，一目了然
5. **复用性**：工具函数和匹配逻辑可被其他脚本复用

## 🚀 实施步骤

1. 创建目录结构
2. 按模块拆分代码（保持功能不变）
3. 在主文件中使用 `dofile()` 加载模块
4. 测试确保功能正常
5. 清理旧代码

## 📝 注意事项

- REAPER脚本需要使用相对路径加载模块
- 使用 `GetScriptPath()` 确保路径正确
- 保持全局变量和模块接口的清晰定义
- 考虑向后兼容性（如果用户有自定义配置）


