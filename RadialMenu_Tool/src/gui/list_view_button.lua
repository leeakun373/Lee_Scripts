-- @description RadialMenu Tool - 子菜单按钮绘制模块
-- @author Lee
-- @about
--   负责子菜单按钮的绘制：单个按钮、网格布局、颜色管理
local M = {}

-- 加载依赖
local styles = require("gui.styles")
local layout = require("gui.list_view_layout")
local interaction = require("gui.list_view_interaction")

-- ============================================================================
-- 按钮颜色管理（性能优化：预计算颜色）
-- ============================================================================
local button_colors = {
    configured = {
        normal = nil,
        hover = nil,
        active = nil,
        border = nil,
        text = nil
    },
    empty = {
        normal = nil,
        hover = nil,
        active = nil,
        border = nil,
        text = nil
    }
}

-- 初始化预计算颜色（在模块加载时执行一次）
local function init_precomputed_colors()
    -- 有功能的按钮颜色
    button_colors.configured.normal = styles.correct_rgba_to_u32({60, 62, 66, 255})
    button_colors.configured.hover = styles.correct_rgba_to_u32(styles.colors.sector_active_out)
    button_colors.configured.active = styles.correct_rgba_to_u32(styles.colors.sector_active_in)
    button_colors.configured.border = styles.correct_rgba_to_u32({85, 85, 90, 100})
    button_colors.configured.text = styles.correct_rgba_to_u32(styles.colors.text_normal)
    
    -- 空插槽颜色
    button_colors.empty.normal = styles.correct_rgba_to_u32({30, 30, 32, 100})
    button_colors.empty.hover = styles.correct_rgba_to_u32({50, 50, 55, 150})
    button_colors.empty.active = styles.correct_rgba_to_u32({60, 60, 65, 150})
    button_colors.empty.border = styles.correct_rgba_to_u32({60, 60, 60, 60})
    button_colors.empty.text = styles.correct_rgba_to_u32(styles.colors.text_disabled)
end

-- 初始化颜色
init_precomputed_colors()

-- 导出颜色获取函数（供其他模块使用）
function M.get_button_colors()
    return button_colors
end

-- ============================================================================
-- 单个按钮绘制
-- ============================================================================
-- 绘制单个按钮（普通模式）
-- @param ctx ImGui context
-- @param slot table: 插槽数据
-- @param index number: 按钮索引
-- @param w number: 按钮宽度
-- @param h number: 按钮高度
-- @param dragging_slot_ref table: 拖拽状态引用（用于更新 dragging_slot）
function M.draw_single_button(ctx, slot, index, w, h, dragging_slot_ref)
    -- 判断是否为已配置的插槽
    local is_configured = slot and slot.type ~= "empty"
    local label = is_configured and slot.name or ""
    
    -- 获取颜色
    local col_normal, col_hover, col_active, col_border, text_color
    if is_configured then
        col_normal = button_colors.configured.normal
        col_hover = button_colors.configured.hover
        col_active = button_colors.configured.active
        col_border = button_colors.configured.border
        text_color = button_colors.configured.text
    else
        col_normal = button_colors.empty.normal
        col_hover = button_colors.empty.hover
        col_active = button_colors.empty.active
        col_border = button_colors.empty.border
        text_color = button_colors.empty.text
    end

    -- 应用颜色
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Button(), col_normal)
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ButtonHovered(), col_hover)
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ButtonActive(), col_active)
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Border(), col_border)
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Text(), text_color)
    
    -- 应用样式
    reaper.ImGui_PushStyleVar(ctx, reaper.ImGui_StyleVar_FrameRounding(), 4)
    reaper.ImGui_PushStyleVar(ctx, reaper.ImGui_StyleVar_FrameBorderSize(), 1)
    
    -- 绘制按钮
    local button_id = "##Slot_" .. tostring(index)
    local button_clicked = false
    if is_configured then
        button_clicked = reaper.ImGui_Button(ctx, (label ~= "" and label or "") .. button_id, w, h)
    else
        -- 空插槽也绘制按钮（用于占位）
        reaper.ImGui_Button(ctx, button_id, w, h)
    end
    
    -- 检测拖拽
    local is_dragging = false
    if is_configured and reaper.ImGui_IsItemActive(ctx) then
        is_dragging = reaper.ImGui_IsMouseDragging(ctx, 0)
        if not is_dragging then
            local mouse_delta_x, mouse_delta_y = reaper.ImGui_GetMouseDelta(ctx, 0)
            local drag_distance = math.sqrt(mouse_delta_x * mouse_delta_x + mouse_delta_y * mouse_delta_y)
            if drag_distance > 3 then
                is_dragging = true
            end
        end
        
        if is_dragging then
            local mouse_delta_x, mouse_delta_y = reaper.ImGui_GetMouseDelta(ctx, 0)
            local drag_distance = math.sqrt(mouse_delta_x * mouse_delta_x + mouse_delta_y * mouse_delta_y)
            if drag_distance > 3 then
                if dragging_slot_ref and (not dragging_slot_ref[1] or dragging_slot_ref[1] ~= slot) then
                    dragging_slot_ref[1] = slot
                end
            end
        end
    end
    
    -- 处理拖拽源
    if is_dragging and is_configured and slot and slot.type == "action" and slot.data and slot.data.command_id then
        if reaper.ImGui_BeginDragDropSource(ctx, reaper.ImGui_DragDropFlags_None()) then
            local cmd_id = slot.data.command_id
            local slot_name = slot.name or ""
            local payload_data = string.format("%d|%s", cmd_id, slot_name)
            reaper.ImGui_SetDragDropPayload(ctx, "DND_ACTION", payload_data)
            reaper.ImGui_Text(ctx, slot_name)
            reaper.ImGui_EndDragDropSource(ctx)
        end
    end
    
    -- 处理点击
    -- 关键：使用局部 is_dragging 检查，与老版本逻辑一致
    -- button_clicked 在按钮释放时返回 true，但如果正在拖拽，不应该触发点击
    if button_clicked and is_configured and not is_dragging and slot then
        interaction.handle_item_click(slot)
    end
    
    reaper.ImGui_PopStyleVar(ctx, 2)
    reaper.ImGui_PopStyleColor(ctx, 5)
    
    -- Tooltip
    if is_configured and reaper.ImGui_IsItemHovered(ctx) and (not dragging_slot_ref or not dragging_slot_ref[1]) then
        local tooltip = slot.name
        if tooltip and tooltip ~= "" then
            reaper.ImGui_BeginTooltip(ctx)
            reaper.ImGui_Text(ctx, tooltip)
            reaper.ImGui_EndTooltip(ctx)
        end
    end
end

-- ============================================================================
-- 网格绘制
-- ============================================================================
-- 绘制按钮网格（普通模式）
-- @param ctx ImGui context
-- @param sector_data table: 扇区数据
-- @param slot_w number: 按钮宽度
-- @param slot_h number: 按钮高度
-- @param slot_count number: 插槽数量
-- @param gap number: 按钮间距
-- @param padding number: 窗口内边距
-- @param dragging_slot_ref table: 拖拽状态引用
function M.draw_grid_buttons(ctx, sector_data, slot_w, slot_h, slot_count, gap, padding, dragging_slot_ref)
    gap = gap or layout.DEFAULT_GAP
    padding = padding or layout.DEFAULT_WINDOW_PADDING
    
    -- 使用 PushID 确保每个扇区的按钮 ID 唯一
    reaper.ImGui_PushID(ctx, "Sector_" .. tostring(sector_data.id))
    
    -- 虚拟化渲染：如果项目数超过9个，只渲染可见项
    local enable_virtualization = (slot_count > 9)
    
    if enable_virtualization then
        -- 虚拟化模式：只渲染可见区域的按钮
        M.draw_virtualized_grid(ctx, sector_data, slot_w, slot_h, slot_count, gap, padding, dragging_slot_ref)
    else
        -- 普通模式：渲染所有按钮（至少12个）
        local render_count = math.max(12, slot_count)
        
        -- 手动添加 padding 偏移，确保 padding 参数生效
        reaper.ImGui_SetCursorPos(ctx, padding, padding)
        
        for i = 1, render_count do
            -- 为每个按钮使用 PushID 确保 ID 唯一
            reaper.ImGui_PushID(ctx, i)
            
            local slot = sector_data.slots and sector_data.slots[i] or nil
            
            -- 计算当前按钮的行列位置
            local row = math.floor((i - 1) / layout.GRID_COLS)
            local col = (i - 1) % layout.GRID_COLS
            
            -- 如果不是第一列，需要手动计算位置
            if col ~= 0 then
                local x_pos = padding + col * (slot_w + gap)
                local y_pos = padding + row * (slot_h + gap)
                reaper.ImGui_SetCursorPos(ctx, x_pos, y_pos)
            elseif row ~= 0 then
                local y_pos = padding + row * (slot_h + gap)
                reaper.ImGui_SetCursorPos(ctx, padding, y_pos)
            end
            
            M.draw_single_button(ctx, slot, i, slot_w, slot_h, dragging_slot_ref)
            
            reaper.ImGui_PopID(ctx)
        end
    end
    
    reaper.ImGui_PopID(ctx)  -- 弹出扇区级别的 ID
end

-- 虚拟化网格绘制（当前实现：渲染所有项目）
-- @param ctx ImGui context
-- @param sector_data table: 扇区数据
-- @param slot_w number: 按钮宽度
-- @param slot_h number: 按钮高度
-- @param slot_count number: 插槽数量
-- @param gap number: 按钮间距
-- @param padding number: 窗口内边距
-- @param dragging_slot_ref table: 拖拽状态引用
function M.draw_virtualized_grid(ctx, sector_data, slot_w, slot_h, slot_count, gap, padding, dragging_slot_ref)
    -- 【当前实现】由于窗口不支持滚动，渲染所有项目
    -- 【未来改进】如果添加滚动容器，可以只渲染可见区域
    
    for i = 1, slot_count do
        reaper.ImGui_PushID(ctx, i)
        
        local slot = sector_data.slots and sector_data.slots[i] or nil
        local row = math.floor((i - 1) / layout.GRID_COLS)
        local col = (i - 1) % layout.GRID_COLS
        local x_pos = padding + col * (slot_w + gap)
        local y_pos = padding + row * (slot_h + gap)
        reaper.ImGui_SetCursorPos(ctx, x_pos, y_pos)
        M.draw_single_button(ctx, slot, i, slot_w, slot_h, dragging_slot_ref)
        
        reaper.ImGui_PopID(ctx)
    end
end

return M

