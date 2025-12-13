-- @description RadialMenu Tool - ImGui 工具模块
-- @author Lee
-- @about
--   ReaImGui 辅助函数封装
--   简化常用的 ImGui 操作

local M = {}

-- ============================================================================
-- Phase 2 - 颜色转换
-- ============================================================================

-- 将 RGBA 颜色转换为 ImGui 的 U32 格式
-- r, g, b, a: 0-255
function M.color_to_u32(r, g, b, a)
    a = a or 255
    
    -- 限制在有效范围
    r = math.floor(math.max(0, math.min(255, r)))
    g = math.floor(math.max(0, math.min(255, g)))
    b = math.floor(math.max(0, math.min(255, b)))
    a = math.floor(math.max(0, math.min(255, a)))
    
    -- 转换公式: (a << 24) | (b << 16) | (g << 8) | r
    return (a << 24) | (b << 16) | (g << 8) | r
end

-- 将 U32 格式颜色转换为 RGBA
function M.u32_to_color(color)
    local r = color & 0xFF
    local g = (color >> 8) & 0xFF
    local b = (color >> 16) & 0xFF
    local a = (color >> 24) & 0xFF
    return r, g, b, a
end

-- 将 {r, g, b, a} 表格式转换为 U32
function M.rgba_table_to_u32(color_table)
    if not color_table then
        return 0xFFFFFFFF
    end
    
    local r = color_table[1] or 255
    local g = color_table[2] or 255
    local b = color_table[3] or 255
    local a = color_table[4] or 255
    
    return M.color_to_u32(r, g, b, a)
end

-- ============================================================================
-- Phase 2 - 窗口辅助
-- ============================================================================

-- 将窗口居中显示
function M.center_window(ctx, width, height)
    local viewport = reaper.ImGui_GetMainViewport(ctx)
    local viewport_x, viewport_y = reaper.ImGui_Viewport_GetPos(viewport)
    local viewport_width, viewport_height = reaper.ImGui_Viewport_GetSize(viewport)
    
    local pos_x = viewport_x + (viewport_width - width) / 2
    local pos_y = viewport_y + (viewport_height - height) / 2
    
    reaper.ImGui_SetNextWindowPos(ctx, pos_x, pos_y, reaper.ImGui_Cond_FirstUseEver())
    reaper.ImGui_SetNextWindowSize(ctx, width, height, reaper.ImGui_Cond_FirstUseEver())
end

-- 将窗口放置在鼠标位置
function M.set_window_at_mouse(ctx, offset_x, offset_y)
    offset_x = offset_x or 10
    offset_y = offset_y or 10
    
    local mouse_x, mouse_y = reaper.ImGui_GetMousePos(ctx)
    reaper.ImGui_SetNextWindowPos(ctx, mouse_x + offset_x, mouse_y + offset_y)
end

-- ============================================================================
-- Phase 2 - 绘制辅助
-- ============================================================================

-- 绘制居中文本
function M.draw_text_centered(draw_list, ctx, x, y, text, color)
    local text_width, text_height = reaper.ImGui_CalcTextSize(ctx, text)
    local text_x = x - text_width / 2
    local text_y = y - text_height / 2
    
    reaper.ImGui_DrawList_AddText(draw_list, text_x, text_y, color, text)
end

-- 绘制带边框的圆
function M.draw_circle_with_border(draw_list, cx, cy, radius, fill_color, border_color, border_width)
    border_width = border_width or 1
    
    -- 绘制填充圆
    reaper.ImGui_DrawList_AddCircleFilled(draw_list, cx, cy, radius, fill_color, 0)
    
    -- 绘制边框
    if border_width > 0 then
        reaper.ImGui_DrawList_AddCircle(draw_list, cx, cy, radius, border_color, 0, border_width)
    end
end

-- 绘制带阴影的文本
function M.draw_text_with_shadow(draw_list, ctx, x, y, text, color, shadow_offset)
    shadow_offset = shadow_offset or 1
    local shadow_color = M.color_to_u32(0, 0, 0, 150)
    
    -- 绘制阴影
    reaper.ImGui_DrawList_AddText(draw_list, x + shadow_offset, y + shadow_offset, shadow_color, text)
    
    -- 绘制文本
    reaper.ImGui_DrawList_AddText(draw_list, x, y, color, text)
end

-- ============================================================================
-- Phase 3 - UI 组件辅助
-- ============================================================================

-- 显示工具提示
function M.tooltip(ctx, text)
    if reaper.ImGui_IsItemHovered(ctx) then
        reaper.ImGui_SetTooltip(ctx, text)
    end
end

-- 显示帮助标记 (?)
function M.help_marker(ctx, description)
    reaper.ImGui_TextDisabled(ctx, "(?)")
    M.tooltip(ctx, description)
end

-- ============================================================================
-- Phase 2 - 布局辅助
-- ============================================================================

-- 在同一行添加元素，带自定义间距
function M.same_line_with_spacing(ctx, spacing)
    if spacing then
        reaper.ImGui_SameLine(ctx, 0, spacing)
    else
        reaper.ImGui_SameLine(ctx)
    end
end

-- 添加垂直间距
function M.vertical_spacing(ctx, count)
    count = count or 1
    for i = 1, count do
        reaper.ImGui_Spacing(ctx)
    end
end

-- ============================================================================
-- Phase 3 - 输入辅助
-- ============================================================================

-- 检查鼠标是否在矩形内点击
function M.is_mouse_clicked_in_rect(ctx, x, y, w, h, button)
    button = button or 0  -- 0=左键，1=右键，2=中键
    
    if not reaper.ImGui_IsMouseClicked(ctx, button) then
        return false
    end
    
    local mouse_x, mouse_y = reaper.ImGui_GetMousePos(ctx)
    
    return mouse_x >= x and mouse_x <= x + w and
           mouse_y >= y and mouse_y <= y + h
end

-- ============================================================================
-- Phase 2 - 坐标转换辅助
-- ============================================================================

-- 获取窗口中心的屏幕坐标
function M.get_window_center_screen_pos(ctx)
    local window_x, window_y = reaper.ImGui_GetWindowPos(ctx)
    local window_width, window_height = reaper.ImGui_GetWindowSize(ctx)
    
    return window_x + window_width / 2, window_y + window_height / 2
end

-- 将屏幕坐标转换为窗口相对坐标
function M.screen_to_window_pos(ctx, screen_x, screen_y)
    local window_x, window_y = reaper.ImGui_GetWindowPos(ctx)
    return screen_x - window_x, screen_y - window_y
end

-- 将窗口相对坐标转换为屏幕坐标
function M.window_to_screen_pos(ctx, window_x, window_y)
    local win_x, win_y = reaper.ImGui_GetWindowPos(ctx)
    return window_x + win_x, window_y + win_y
end

-- ============================================================================
-- Phase 2 - 其他辅助
-- ============================================================================

-- 推送禁用状态
function M.push_disabled(ctx, disabled)
    if disabled then
        reaper.ImGui_BeginDisabled(ctx)
    end
end

-- 弹出禁用状态
function M.pop_disabled(ctx, disabled)
    if disabled then
        reaper.ImGui_EndDisabled(ctx)
    end
end

return M
