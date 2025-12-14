# UCS Rename Tools - 版本更新日志

## v10.1 (2025-12-04) - Fixed CSV parsing + Water material priority boost

### 🔧 核心修复

1. **修复 CSV 解析问题**
   - 文件：`Modules/DataLoader.lua`
   - 问题：之前只跳过一行表头，导致 "UCS v8.2.1" 等元数据被当作数据读入
   - 修复：添加智能过滤，自动跳过：
     - 包含 "UCS v" 的元数据行
     - "Category" 表头行
     - 空行和无效行

2. **升级智能匹配算法**
   - 文件：`Config/Constants.lua`, `Modules/UCSMatcher.lua`
   - 问题：输入 "Water Balloon" 时，Balloon（子类60分）> Water（大类20分），导致误判为 Game
   - 修复：
     - 新增 `SAFE_DOMINANT_KEYWORDS` 列表（无歧义的物理材质词）
     - 新增 `SAFE_DOMINANT_BONUS = 50` 权重加成
     - Water 等安全材质词现在得分：20（基础）+ 50（加成）= **70分** > 60分（子类）

### 📋 安全材质列表

以下材质词会获得优先匹配权：
- water, liquid, ice
- glass, ceramic
- electricity
- mud, dirt
- stone, rock

### 🎯 效果验证

**修复前：**
- 输入：Water Balloon
- 匹配：GAME（错误）
- 原因：Balloon 子类 60分 > Water 大类 20分

**修复后：**
- 输入：Water Balloon
- 匹配：WATER（正确）✅
- 原因：Water 大类 70分（20+50加成）> Balloon 子类 60分

### 💡 双重保险建议

在脚本的 **[+ Alias]** 功能中添加规则：
```
Source: water ball
Target: splash
```

这样 "water ball" 会被预处理成 "water splash"，进一步确保准确性。

### 📝 技术细节

**修改的文件：**
1. `Lee_Markers - UCS RenameTools.lua` - 版本号更新
2. `Config/Constants.lua` - 添加版本信息和安全材质列表
3. `Modules/DataLoader.lua` - 修复 CSV 解析逻辑
4. `Modules/GUI.lua` - 在界面显示版本号
5. `Modules/UCSMatcher.lua` - 已支持安全材质加成（无需修改）

**向后兼容：**
- ✅ 完全保留原有 UI 布局
- ✅ 保留所有 Alias 功能
- ✅ 不影响现有工作流程
- ✅ 只增强算法，不破坏功能

---

## 如何确认版本

打开脚本后，你会在以下位置看到版本信息：

1. **窗口标题栏**：`UCS Toolkit v10.1 - Fixed CSV parsing + Water material priority boost`
2. **底部状态栏左侧**：`v10.1 (2025-12-04)`

如果看到这些信息，说明新版本已生效！🎉

















