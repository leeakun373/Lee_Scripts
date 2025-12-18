# UCS 智能匹配算法优化文档

## 优化目标
解决特定材质被错误归类的问题（例如 "Water Balloon" 被归类为 Game 而非 Water），同时防止对其他复杂类别产生误判。

## 修改内容

### 1. 配置修改 (Constants.lua)

#### 新增：安全材质霸权词表
```lua
Constants.SAFE_DOMINANT_KEYWORDS = {
    ["water"] = true, ["liquid"] = true, ["ice"] = true,
    ["glass"] = true, ["ceramic"] = true, ["electricity"] = true,
    ["mud"] = true, ["dirt"] = true
}
```

**设计原则：**
- ✅ **包含**：极少歧义的物理材质词汇（water, liquid, ice, glass, ceramic, electricity, mud, dirt）
- ❌ **不包含**：
  - `fire` - 避免与 Weapon 类冲突
  - `air` - 避免与 Alarm/Vehicle 类冲突  
  - `metal` - 避免与 Door/Impact 类冲突
  - `wood` - 避免与 Door 类冲突

#### 调整：权重配置
```lua
Constants.WEIGHTS = {
    CATEGORY_EXACT = 20,       -- 降低基础分 (原 50)
    CATEGORY_PART  = 5,        -- 降低部分匹配分 (原 10)
    SUBCATEGORY    = 60,       -- 保持子类主导地位
    SYNONYM        = 40,
    DESCRIPTION    = 5,
    PERFECT_BONUS  = 30,
    SAFE_DOMINANT_BONUS = 50   -- 新增安全材质奖励
}
```

**权重设计：**
- 普通大类匹配：20 分
- 安全材质大类匹配：20 + 50 = **70 分** （超过子类的 60 分）
- 子类匹配：60 分
- 完美匹配（大类+子类）：20 + 60 + 30 = 110 分

### 2. 算法修改 (UCSMatcher.lua)

#### 函数签名更新
```lua
function UCSMatcher.FindBestUCS(user_input, ucs_db, weights, match_threshold, 
                                 downgrade_words, helpers, safe_dominant_keywords)
```

#### 大类匹配逻辑增强
```lua
-- A. Category Match Logic (with Safe Dominant Bonus)
for _, k in ipairs(item.cat_en) do
    if k == word then 
        current_score = current_score + weights.CATEGORY_EXACT
        cat_hit = true
        
        -- Apply bonus for safe dominant keywords
        if safe_dominant_keywords and safe_dominant_keywords[word] then
            current_score = current_score + weights.SAFE_DOMINANT_BONUS
        end
    elseif k:find(word, 1, true) then 
        current_score = current_score + weights.CATEGORY_PART 
    end
end
```

### 3. 调用链更新

所有调用点已更新以传递 `safe_dominant_keywords` 参数：

#### NameProcessor.lua
```lua
function NameProcessor.AutoMatchItem(item, ucs_db, app_state, ucs_optional_fields, 
                                    ucs_matcher, weights, match_threshold, 
                                    downgrade_words, helpers, safe_dominant_keywords)
```

#### ProjectActions.lua
```lua
function ProjectActions.ActionSmartPaste(app_state, ucs_db, name_processor, ucs_matcher, 
                                        weights, match_threshold, downgrade_words, helpers, 
                                        ucs_optional_fields, safe_dominant_keywords)
```

#### GUI.lua (2处调用)
1. Auto 按钮：
```lua
NameProcessor.AutoMatchItem(item, ucs_db, app_state, Constants.UCS_OPTIONAL_FIELDS, 
    UCSMatcher, Constants.WEIGHTS, Constants.MATCH_THRESHOLD, 
    Constants.DOWNGRADE_WORDS, Helpers, Constants.SAFE_DOMINANT_KEYWORDS)
```

2. Paste 按钮：
```lua
ProjectActions.ActionSmartPaste(app_state, ucs_db, NameProcessor, UCSMatcher, 
    Constants.WEIGHTS, Constants.MATCH_THRESHOLD, Constants.DOWNGRADE_WORDS, 
    Helpers, Constants.UCS_OPTIONAL_FIELDS, Constants.SAFE_DOMINANT_KEYWORDS)
```

## 预期效果

### 测试案例 1: Water Balloon ✅
**输入：** "Water Balloon"

**分析：**
- `water` 匹配大类 + 安全词奖励：20 + 50 = **70 分**
- `balloon` 匹配子类：**60 分**

**结果：** 推荐 **WATR** (Water) 分类 ✅

---

### 测试案例 2: Metal Door ✅
**输入：** "Metal Door"

**分析：**
- `metal` 匹配大类（非安全词）：**20 分**
- `door` 匹配子类：**60 分**

**结果：** 推荐 **DOOR** 分类 ✅

---

### 测试案例 3: Glass Break ✅
**输入：** "Glass Break"

**分析：**
- `glass` 匹配大类 + 安全词奖励：20 + 50 = **70 分**
- `break` 匹配子类：**60 分**

**结果：** 推荐 **GLAS** (Glass) 分类 ✅

---

### 测试案例 4: Fire Weapon ✅
**输入：** "Fire Weapon"

**分析：**
- `fire` 匹配大类（非安全词）：**20 分**
- `weapon` 匹配子类：**60 分**

**结果：** 推荐 **WEAP** (Weapon) 分类 ✅

## 代码质量检查

✅ 无语法错误（Linter 检查通过）
✅ 参数传递完整（所有调用链已更新）
✅ 向后兼容（safe_dominant_keywords 有 nil 检查）
✅ UI 无变化（仅逻辑优化）

## 修改文件清单

1. `Config/Constants.lua` - 添加安全词表，调整权重
2. `Modules/UCSMatcher.lua` - 更新匹配算法
3. `Modules/NameProcessor.lua` - 更新函数签名
4. `Modules/ProjectActions.lua` - 更新函数签名和调用
5. `Modules/GUI.lua` - 更新调用点（2处）

---

**优化完成日期：** 2025-12-04  
**版本：** v10.1 (Algorithm Enhancement)


























