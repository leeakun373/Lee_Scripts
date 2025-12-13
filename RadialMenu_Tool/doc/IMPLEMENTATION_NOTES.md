# RadialMenu Tool - 实现要点与技术建议

本文档记录了开发过程中的重要技术建议和注意事项。

---

## ✅ Phase 1 完成情况

### JSON 库选择

**决策**: 使用成熟的 dkjson 库，而非自己实现

**理由**:
- Lua 处理字符串解析较慢且容易出错
- dkjson 是 Lua 社区的标准库，稳定且高效
- 已经过大量项目验证

**实现状态**: ✅ 已集成 dkjson 到 `utils/json.lua`

### 配置管理

**实现状态**: ✅ 已完成
- 默认配置：6个扇区，每个扇区12个空槽位
- 完整的验证、加载、保存功能
- 自动合并默认值
- 辅助函数：添加/删除槽位等

---

## ⚠️ Phase 2 关键注意事项

### 1. 坐标系统的"坑" 🔴 高优先级

**问题**: 坐标系统混淆会导致菜单移动后点击区域错位

**解决方案**: 严格区分两种坐标系统

#### Screen Coordinates (屏幕绝对坐标)
```lua
-- 获取鼠标的屏幕坐标
local mouse_x, mouse_y = reaper.GetMousePosition()
```

#### Window Coordinates (窗口相对坐标)
```lua
-- 获取窗口位置
local window_x, window_y = reaper.ImGui_GetWindowPos(ctx)

-- 转换为屏幕空间坐标（用于绘制）
local cursor_screen_x, cursor_screen_y = reaper.ImGui_GetCursorScreenPos(ctx)
```

**实现建议**:
```lua
-- 在 gui/wheel.lua 中
function M.draw_wheel(ctx, config)
    local draw_list = reaper.ImGui_GetWindowDrawList(ctx)
    
    -- 方法1: 使用屏幕坐标（推荐）
    local center_x, center_y = reaper.ImGui_GetCursorScreenPos(ctx)
    center_x = center_x + window_width / 2
    center_y = center_y + window_height / 2
    
    -- 方法2: 统一转换到窗口空间
    local window_x, window_y = reaper.ImGui_GetWindowPos(ctx)
    local mouse_x, mouse_y = reaper.GetMousePosition()
    local relative_x = mouse_x - window_x
    local relative_y = mouse_y - window_y
    
    -- 所有绘制和碰撞检测使用同一坐标系
end
```

### 2. 中心"死区"必须实现 🔴 高优先级

**问题**: 鼠标在圆心微小移动会导致扇区高亮剧烈跳动（角度变化极大）

**解决方案**: 添加距离检查

```lua
-- 在 gui/wheel.lua 的 get_hovered_sector 函数中
function M.get_hovered_sector(mouse_x, mouse_y, center_x, center_y, config)
    local angle, distance = math_utils.get_mouse_angle_and_distance(
        mouse_x, mouse_y, center_x, center_y
    )
    
    local inner_radius = config.menu.inner_radius
    local outer_radius = config.menu.outer_radius
    
    -- 关键：距离检查
    if distance < inner_radius then
        return nil  -- 鼠标在中心空洞，不选中任何扇区
    elseif distance > outer_radius then
        return nil  -- 鼠标在轮盘外
    else
        -- 只有在圆环带内才计算角度
        local sector_index = calculate_sector_by_angle(angle, #config.sectors)
        return config.sectors[sector_index]
    end
end
```

---

## ⚠️ Phase 3 关键注意事项

### 子菜单智能定位 🟡 中优先级

**问题**: 轮盘在屏幕边缘时，子菜单可能飞出屏幕外

**解决方案**: 实现智能定位逻辑

```lua
-- 在 gui/list_view.lua 中
function M.calculate_submenu_position(ctx, sector_index, total_sectors, center_x, center_y)
    local viewport = reaper.ImGui_GetMainViewport(ctx)
    local screen_width = reaper.ImGui_Viewport_GetSize(viewport)
    
    local menu_width = 250  -- 子菜单宽度
    local menu_height = 400 -- 子菜单高度
    
    -- 计算扇区角度，确定默认显示位置
    local sector_angle = (sector_index - 1) * (2 * math.pi / total_sectors)
    local default_x = center_x + math.cos(sector_angle) * 150
    local default_y = center_y + math.sin(sector_angle) * 150
    
    -- 边界检测
    local final_x = default_x
    local final_y = default_y
    
    -- 检测右边界
    if default_x + menu_width > screen_width then
        final_x = center_x - menu_width - 20  -- 改为左侧显示
    end
    
    -- 检测下边界
    if default_y + menu_height > screen_height then
        final_y = screen_height - menu_height - 20
    end
    
    -- 检测上边界
    if final_y < 0 then
        final_y = 20
    end
    
    return final_x, final_y
end
```

---

## ⚠️ Phase 4 关键注意事项

### 拖拽功能 - 高风险警告 🔴 技术难度最高

**问题**: ImGui 拖拽到 Reaper 原生界面非常困难

**原因**:
- ReaImGui 的 `DragDropSource` 主要用于 ImGui 窗口之间拖拽
- Reaper 原生界面（如 TCP 轨道面板）无法识别 ImGui 的拖拽数据
- 跨窗口、跨应用拖拽需要操作系统级别的支持

**推荐的备选方案**: "点击-点击"模式

```lua
-- 在 logic/fx_engine.lua 中
local pending_fx = nil  -- 待挂载的 FX

function M.start_fx_placement(fx_name)
    pending_fx = fx_name
    -- 改变鼠标光标为特殊图标（如果 ImGui 支持）
    reaper.ShowConsoleMsg("点击目标轨道或 Item 以挂载 FX: " .. fx_name .. "\n")
end

function M.check_placement_click()
    if not pending_fx then return end
    
    -- 检测鼠标点击
    if reaper.ImGui_IsMouseClicked(ctx, 0) then
        local mouse_x, mouse_y = reaper.GetMousePosition()
        
        -- 尝试获取点击位置的轨道
        local track = reaper.GetTrackFromPoint(mouse_x, mouse_y)
        
        if track then
            M.add_fx_to_track(track, pending_fx)
            pending_fx = nil
            return true
        end
        
        -- 尝试获取点击位置的 Item
        local item = reaper.GetItemFromPoint(mouse_x, mouse_y, false)
        
        if item then
            M.add_fx_to_item(item, pending_fx)
            pending_fx = nil
            return true
        end
        
        -- 点击空白区域，取消
        pending_fx = nil
        reaper.ShowConsoleMsg("已取消 FX 挂载\n")
    end
    
    return false
end
```

**如果坚持实现拖拽**:
1. 研究 ReaImGui 的 `BeginDragDropSource` 和 `BeginDragDropTarget`
2. 可能需要使用 Windows API（如果在 Windows 上）
3. 考虑使用剪贴板作为中间数据传递方式
4. 预期投入大量时间调试，成功率不确定

---

## 📋 开发检查清单

### Phase 2 开始前
- [ ] 确认理解屏幕坐标 vs 窗口坐标
- [ ] 准备好坐标转换的辅助函数
- [ ] 规划中心死区的实现方式

### Phase 3 开始前
- [ ] 测试 Phase 2 的坐标系统是否正确
- [ ] 准备屏幕边界检测逻辑
- [ ] 考虑不同分辨率下的表现

### Phase 4 开始前
- [ ] 决定是否实现拖拽功能
- [ ] 如果不实现，准备"点击-点击"模式的 UI 反馈
- [ ] 测试 `reaper.GetTrackFromPoint()` 和 `reaper.GetItemFromPoint()`

---

## 🔧 调试技巧

### 坐标调试
```lua
-- 在 main_runtime.lua 的 draw() 函数中
function M.draw()
    local mouse_x, mouse_y = reaper.GetMousePosition()
    local window_x, window_y = reaper.ImGui_GetWindowPos(ctx)
    local cursor_x, cursor_y = reaper.ImGui_GetCursorScreenPos(ctx)
    
    reaper.ImGui_Text(ctx, string.format("Mouse: %.0f, %.0f", mouse_x, mouse_y))
    reaper.ImGui_Text(ctx, string.format("Window: %.0f, %.0f", window_x, window_y))
    reaper.ImGui_Text(ctx, string.format("Cursor: %.0f, %.0f", cursor_x, cursor_y))
    
    -- 绘制轮盘...
end
```

### 扇区悬停调试
```lua
-- 在 gui/wheel.lua 中
function M.draw_wheel(ctx, config)
    -- ... 绘制代码 ...
    
    local hovered = M.get_hovered_sector(mouse_x, mouse_y, center_x, center_y, config)
    if hovered then
        reaper.ImGui_Text(ctx, "Hovered: " .. hovered.name)
    else
        reaper.ImGui_Text(ctx, "Hovered: None")
    end
end
```

---

## 📚 参考资源

- [ReaImGui API Documentation](https://github.com/cfillion/reaimgui/blob/master/API.md)
- [REAPER API: GetTrackFromPoint](https://www.reaper.fm/sdk/reascript/reascripthelp.html#GetTrackFromPoint)
- [ImGui Coordinate Systems](https://github.com/ocornut/imgui/wiki/Getting-Started#coordinate-systems)

---

## 更新日志

- **2024-12-05**: 创建文档，记录 Phase 1 完成和 Phase 2-4 的关键注意事项

