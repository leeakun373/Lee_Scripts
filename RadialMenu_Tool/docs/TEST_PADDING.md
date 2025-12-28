# Padding 参数测试说明

## 问题分析

Padding 参数修改后没有效果的原因：

### 1. 烘焙缓存模式（最常见）
- 如果使用了烘焙缓存，按钮位置是在烘焙时预先计算的
- 修改 padding 后必须清除缓存并重新烘焙才能看到效果

### 2. 窗口大小已包含 padding
- 窗口总大小 = `(按钮宽度 × 列数) + (间距 × (列数-1)) + (内边距 × 2)`
- 所以 padding 增加时，窗口也会变大，但按钮与边框的距离应该会变化

## 验证方法

### 方法 1：清除缓存测试
1. 修改 `padding = 10`（已修改）
2. 运行 `Lee_RadialMenu_clear_cache.lua` 清除缓存
3. **完全关闭并重新打开轮盘菜单**（重要！）
4. 观察按钮与子栏边框的距离

### 方法 2：临时禁用烘焙缓存
在 `list_view.lua` 的 `draw_submenu` 函数中，临时注释掉烘焙缓存检查：

```lua
function M.draw_submenu(ctx, sector_data, center_x, center_y, anim_scale, config)
    if not sector_data or not config then return false end

    -- 【临时禁用】测试时注释掉这行
    -- if submenu_bake_cache.is_baked() then
    --     return M.draw_submenu_cached(ctx, sector_data, center_x, center_y, anim_scale, config)
    -- end

    -- ... 其余代码
```

这样会强制使用非烘焙模式，`WindowPadding` 样式变量会立即生效。

### 方法 3：检查窗口大小变化
即使按钮位置看起来没变，窗口大小应该会变化：
- padding = 0: 窗口宽度 = 246 像素
- padding = 10: 窗口宽度 = 266 像素

## 当前参数值

- `list_view.lua:25`: `DEFAULT_WINDOW_PADDING = 10` ✅
- `submenu_bake_cache.lua:54`: `local padding = 10` ✅

## 如果仍然没有效果

1. **确认是否使用了烘焙缓存**：
   - 检查 `submenu_bake_cache.is_baked()` 的返回值
   - 如果返回 true，必须清除缓存

2. **检查窗口大小**：
   - 如果窗口大小从 246 变成了 266，说明 padding 确实生效了
   - 但按钮位置可能因为缓存没有更新

3. **强制重新烘焙**：
   - 关闭轮盘菜单
   - 运行清除缓存脚本
   - 重新打开轮盘菜单（会触发重新烘焙）

