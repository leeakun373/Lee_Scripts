# UCS Rename Tools - v10.2 更新日志

## 版本：v10.2 (2025-12-04) - Enhanced UX

### 🎯 新增功能

#### 1. Alias 系统（别名管理）
- **[+ Alias] 按钮**：在顶部工具栏 Refresh 按钮右侧，紫色高亮显示
- **智能预填**：点击按钮时，如果选中了某一行，自动填充：
  - Source：当前行的 Translation（原名）
  - Target：当前匹配的 SubCategory 或 CatID
- **实时保存**：添加的别名立即写入 `ucs_alias.csv` 并刷新匹配逻辑
- **功能说明**：别名系统可以将常见短语映射到标准术语，提高匹配准确性

**使用示例**：
```
Source: water ball
Target: splash
```
添加后，所有包含 "water ball" 的输入都会被替换为 "splash"，确保准确匹配到 Water 分类。

---

#### 2. 智能初始化（Smart Initialization）
- **自动识别**：打开脚本时，自动检测所有 Marker/Region 名称
- **UCS 拆分**：如果名称符合 `CatID_Name` 格式，自动拆分并填充字段
- **英文自动匹配**：对于纯英文文件名（不含中文字符），自动运行匹配算法
- **即时建议**：打开脚本即可看到推荐的分类，无需先点击 Paste

**效果**：
- 之前：需要手动点击 Paste 或 Auto 才能获得建议
- 现在：打开脚本时，英文文件名已自动匹配并显示建议

---

#### 3. 增强型下拉框（Editable Combo Boxes）
- **直接编辑**：Category 和 SubCategory 现在可以直接在输入框中编辑
- **复制粘贴**：可以直接选择、复制框内文本，无需打开下拉菜单
- **箭头按钮**：点击右侧箭头按钮打开下拉列表
- **模糊搜索**：在弹出的列表中包含搜索框，支持实时过滤

**交互改进**：
- InputText：直接输入或编辑分类名称
- ArrowButton：打开带搜索功能的弹出列表
- Popup：显示过滤后的分类列表，点击选择

---

### 🔧 UI 优化

#### 4. 布局修复
- **垂直对齐**：CatID 文本和 [Auto] 按钮现在完美垂直居中对齐
- **表格模式**：从 `SizingStretchProp` 改为 `SizingFixedFit`，减少空白浪费

#### 5. 列宽自适应
- **固定列宽**：
  - ID: 35px
  - Category: 90px
  - SubCategory: 90px
  - CatID: 95px
  - Original: 150px
  - FXName/Replace: 120px
  - Optional fields: 70px
- **自适应 Preview**：Preview 列使用 `WidthStretch(3.0)`，占满所有剩余空间
- **效果**：长文件名能完整显示，不再被截断

---

### 📝 技术改进

#### 修改的文件：
1. **DataLoader.lua**
   - 新增 `SaveUserAlias()` 函数，支持追加写入别名到 CSV
   
2. **Constants.lua**
   - 添加紫色按钮颜色常量 `BTN_ALIAS`
   - 更新版本信息到 v10.2

3. **Theme.lua**
   - 新增 `BtnAlias()` 函数，紫色风格按钮

4. **GUI.lua**
   - 添加 [+ Alias] 按钮和模态窗口
   - 重构 Category/SubCategory 为 InputText + ArrowButton + Popup
   - 添加 `AlignTextToFramePadding()` 修复对齐
   - 修改表格标志位为 `SizingFixedFit`
   - 优化列宽设置

5. **ProjectActions.lua**
   - `ReloadProjectData()` 添加智能初始化逻辑
   - 扩展函数签名以支持自动匹配参数
   - `ActionApply()` 同步更新函数签名

6. **Lee_Markers - UCS RenameTools.lua**
   - 传递 `script_path` 到 GUI 模块
   - 更新所有函数调用以匹配新签名

---

### 🎨 用户体验提升

1. **更快的工作流程**：打开脚本即可看到匹配建议，无需额外操作
2. **更灵活的编辑**：可以直接在输入框中编辑、复制分类名称
3. **更强的定制性**：通过 Alias 系统自定义短语映射
4. **更好的可读性**：优化的列宽确保长文件名完整显示
5. **更精准的对齐**：UI 元素垂直居中，视觉更舒适

---

### ✅ 向后兼容

- 所有现有功能保持不变
- CSV 文件格式完全兼容
- 不影响已保存的配置和数据
- 平滑升级，无需额外操作

---

### 🚀 升级建议

从 v10.1 升级到 v10.2：
1. 直接替换所有文件即可
2. 首次运行时，英文 Marker/Region 将自动匹配
3. 开始使用 [+ Alias] 按钮添加自定义映射

---

### 📋 完整功能列表

**v10.2 包含的所有功能**：
- ✅ v10.1: 修复 CSV 解析 + Water 材质优先级提升
- ✅ v10.2: Alias 系统
- ✅ v10.2: 智能初始化（英文自动匹配）
- ✅ v10.2: 增强型下拉框（可编辑 Combo）
- ✅ v10.2: UI 对齐修复
- ✅ v10.2: 表格列宽优化

---

## 确认版本

打开脚本后查看：
- **窗口标题**：`UCS Toolkit v10.2 - Enhanced UX: Alias system, Smart init, Editable combos`
- **底部状态栏**：`v10.2 (2025-12-04)`

看到以上信息说明已成功升级到 v10.2！🎉














