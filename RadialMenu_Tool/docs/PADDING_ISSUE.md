# Padding 参数无效问题分析

## 问题描述
Padding 参数修改后完全不影响子栏绘制，无论如何改变参数都不影响显示。

## 根本原因

### 1. 非烘焙模式下的问题
在 `draw_submenu` 函数中：
- `WindowPadding` 被设置了（第 360 行）
- 但按钮是通过 `ImGui_Button` + `ImGui_SameLine` 绘制的
- **`WindowPadding` 只影响第一个元素的位置**
- 使用 `SameLine` 时，后续按钮会紧贴排列，**不会受到 padding 的影响**

### 2. 烘焙缓存模式下的问题
在 `draw_submenu_cached` 函数中：
- 按钮位置是直接计算的，使用了 padding（`submenu_bake_cache.lua:205-206`）
- 但如果缓存没有清除，就会使用**旧的 padding 值**
- 即使修改了代码中的 padding，缓存中的按钮位置仍然是旧的

## 当前代码流程

### 非烘焙模式（`draw_submenu`）
```lua
-- 设置 WindowPadding
reaper.ImGui_PushStyleVar(ctx, reaper.ImGui_StyleVar_WindowPadding(), padding, padding)

-- 绘制按钮（使用 SameLine）
for i = 1, render_count do
    if (i - 1) % GRID_COLS ~= 0 then
        reaper.ImGui_SameLine(ctx)  -- 紧贴排列，不受 padding 影响
    end
    M.draw_single_button(ctx, slot, i, slot_w, slot_h)
end
```

**问题**：`SameLine` 会让按钮紧贴排列，只有第一个按钮会受到 `WindowPadding` 的影响。

### 烘焙缓存模式（`draw_submenu_cached`）
```lua
-- 按钮位置在烘焙时计算（使用 padding）
local item_x_rel = sx_rel + padding + col * (slot_w + gap)
local item_y_rel = sy_rel + padding + row * (slot_h + gap)
```

**问题**：如果缓存没有清除，就会使用旧的 padding 值。

## 解决方案

### 方案 1：强制清除缓存（推荐）
1. 运行 `Lee_RadialMenu_clear_cache.lua`
2. 完全关闭轮盘菜单
3. 重新打开轮盘菜单

### 方案 2：临时禁用烘焙缓存
在 `list_view.lua` 第 299 行，临时注释掉：
```lua
-- if submenu_bake_cache.is_baked() then
--     return M.draw_submenu_cached(ctx, sector_data, center_x, center_y, anim_scale, config)
-- end
```

### 方案 3：修复非烘焙模式（需要代码修改）
在非烘焙模式下，不能依赖 `WindowPadding`，需要手动计算按钮位置，类似烘焙缓存模式。

## 验证方法

### 检查是否使用了烘焙缓存
在 `list_view.lua` 的 `draw_submenu` 函数开头添加调试输出：
```lua
if submenu_bake_cache.is_baked() then
    reaper.ShowConsoleMsg("使用烘焙缓存模式\n")
else
    reaper.ShowConsoleMsg("使用非烘焙模式\n")
end
```

### 检查窗口大小变化
即使按钮位置看起来没变，窗口大小应该会变化：
- padding = 0: 窗口宽度 = `(80 × 4) + (3 × 3) + (0 × 2) = 329` 像素
- padding = 100: 窗口宽度 = `(80 × 4) + (3 × 3) + (100 × 2) = 529` 像素

如果窗口大小变了但按钮位置没变，说明是缓存问题。

## 结论

**Padding 参数在烘焙缓存模式下是有效的**，但需要清除缓存才能看到效果。

**Padding 参数在非烘焙模式下基本无效**，因为 `SameLine` 会让按钮紧贴排列，只有第一个按钮会受到 `WindowPadding` 的影响。

如果要让 padding 在非烘焙模式下也生效，需要修改代码，手动计算按钮位置，而不是依赖 `WindowPadding` 和 `SameLine`。

