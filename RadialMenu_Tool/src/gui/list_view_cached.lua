-- @description RadialMenu Tool - 子菜单烘焙缓存绘制模块
-- @author Lee
-- @about
--   使用烘焙缓存直接绘制子菜单（无计算，只画图，极速模式）
local M = {}

-- 加载依赖
local styles = require("gui.styles")
local submenu_bake_cache = require("gui.submenu_bake_cache")
local button = require("gui.list_view_button")
local interaction = require("gui.list_view_interaction")

-- ============================================================================
-- 烘焙缓存绘制
-- ============================================================================
-- 使用烘焙缓存直接绘制（无计算，只画图）
-- @param ctx ImGui context
-- @param sector_data table: 扇区数据
-- @param center_x number: 轮盘中心 X 坐标
-- @param center_y number: 轮盘中心 Y 坐标
-- @param anim_scale number: 动画缩放（未使用）
-- @param config table: 配置对象
-- @param dragging_slot_ref table: 拖拽状态引用
-- @param draw_submenu_fallback function: 回退绘制函数（如果缓存不存在）
-- @return boolean: 是否悬停在子菜单上
function M.draw_submenu_cached(ctx, sector_data, center_x, center_y, anim_scale, config, dragging_slot_ref, draw_submenu_fallback)
    if not sector_data or not config then return false end
    
    -- 1. 直接读内存，0 耗时
    local cached_data = submenu_bake_cache.get_cached(sector_data.id)
    if not cached_data then
        -- 如果缓存不存在，回退到原始绘制方法
        if draw_submenu_fallback then
            return draw_submenu_fallback(ctx, sector_data, center_x, center_y, anim_scale, config)
        end
        return false
    end
    
    local draw_list = reaper.ImGui_GetWindowDrawList(ctx)
    if not draw_list then return false end
    
    local bake_cfg = submenu_bake_cache.get_config()
    local max_bounds = submenu_bake_cache.get_max_bounds()
    
    -- 获取窗口内的圆心位置（这是稳定的绘制中心）
    local win_x, win_y = reaper.ImGui_GetWindowPos(ctx)
    local cx = win_x + max_bounds.center_offset_x
    local cy = win_y + max_bounds.center_offset_y
    
    -- 将相对坐标转换为绝对坐标
    local bg_rect_rel = cached_data.bg_rect_rel
    local bg_rect = {
        cx + bg_rect_rel[1],
        cy + bg_rect_rel[2],
        cx + bg_rect_rel[3],
        cy + bg_rect_rel[4]
    }
    
    local is_submenu_hovered = false
    
    -- 2. 直接画背景，不用算坐标
    reaper.ImGui_DrawList_AddRectFilled(draw_list, 
        bg_rect[1], bg_rect[2], bg_rect[3], bg_rect[4], 
        bake_cfg.bg_color, 8.0)
    
    -- 3. 绘制边框
    local border_color = styles.correct_rgba_to_u32({0, 0, 0, 255})
    reaper.ImGui_DrawList_AddRect(draw_list,
        bg_rect[1], bg_rect[2], bg_rect[3], bg_rect[4],
        border_color, 8.0, 0, 1.0)
    
    -- 4. 遍历画选项
    -- 先创建所有按钮（用于状态检测），然后再绘制
    local button_states = {}  -- 存储每个按钮的状态和 ID
    
    for i, item in ipairs(cached_data.items) do
        -- 将相对坐标转换为绝对坐标
        local rect_rel = item.rect_rel
        local rect = {
            cx + rect_rel[1],
            cy + rect_rel[2],
            cx + rect_rel[3],
            cy + rect_rel[4]
        }
        
        -- 使用 InvisibleButton 进行点击检测（先创建，用于状态检测）
        local rel_x = rect[1] - win_x
        local rel_y = rect[2] - win_y
        reaper.ImGui_SetCursorPos(ctx, rel_x, rel_y)
        -- 确保 ID 唯一：使用 sector_id + grid_pos + index 组合
        local grid_index = (item.grid_pos[1] or 0) * cached_data.cols + (item.grid_pos[2] or 0) + 1
        local button_id = "##BakedSlot_" .. tostring(sector_data.id) .. "_" .. tostring(grid_index) .. "_" .. tostring(i)
        reaper.ImGui_InvisibleButton(ctx, button_id, rect[3] - rect[1], rect[4] - rect[2])
        
        -- button state
        local is_hover = reaper.ImGui_IsItemHovered(ctx)
        local is_active = reaper.ImGui_IsItemActive(ctx)
        local is_clicked = reaper.ImGui_IsItemClicked(ctx, 0)
        local is_dragging = false
        if is_active then
            is_dragging = reaper.ImGui_IsMouseDragging(ctx, 0)
            if not is_dragging then
                local mouse_delta_x, mouse_delta_y = reaper.ImGui_GetMouseDelta(ctx, 0)
                local drag_distance = math.sqrt(mouse_delta_x * mouse_delta_x + mouse_delta_y * mouse_delta_y)
                if drag_distance > 3 then
                    is_dragging = true
                end
            end
        end
        
        if is_hover then
            is_submenu_hovered = true
        end
        
        if is_dragging and item.slot and item.slot.type ~= "empty" then
            if dragging_slot_ref then
                dragging_slot_ref[1] = item.slot
            end
        end
        
        -- 存储按钮状态（用于第二次循环绘制）
        button_states[i] = {
            rect = rect,
            is_hover = is_hover,
            is_active = is_active,
            is_clicked = is_clicked,
            is_dragging = is_dragging,
            item = item,
            button_id = button_id,
            rel_x = rel_x,
            rel_y = rel_y
        }
    end
    
    -- 现在绘制所有按钮（使用检测到的状态）
    local button_colors = button.get_button_colors()
    
    for i, state in ipairs(button_states) do
        local item = state.item
        local rect = state.rect
        local is_hover = state.is_hover
        local is_active = state.is_active
        
        local text_pos_rel = item.text_pos_rel
        local text_pos = {
            cx + text_pos_rel[1],
            cy + text_pos_rel[2]
        }
        
        -- 判断是否为已配置的插槽
        local is_configured = item.slot and item.slot.type ~= "empty"
        
        -- 使用与原来相同的按钮颜色系统
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
        
        -- 绘制按钮背景（根据状态选择颜色）
        local bg_color = col_normal
        if is_active then
            bg_color = col_active
        elseif is_hover then
            bg_color = col_hover
        end
        
        -- 绘制按钮背景（圆角矩形）
        reaper.ImGui_DrawList_AddRectFilled(draw_list, 
            rect[1], rect[2], rect[3], rect[4], 
            bg_color, 4.0)
        
        -- 绘制按钮边框（圆角矩形）
        reaper.ImGui_DrawList_AddRect(draw_list,
            rect[1], rect[2], rect[3], rect[4],
            col_border, 4.0, 0, 1.0)
        
        -- 绘制文字，使用裁剪区域防止溢出
        if item.text and item.text ~= "" then
            reaper.ImGui_DrawList_PushClipRect(draw_list, rect[1], rect[2], rect[3], rect[4], true)
            reaper.ImGui_DrawList_AddText(draw_list, 
                text_pos[1], text_pos[2], text_color, item.text)
            reaper.ImGui_DrawList_PopClipRect(draw_list)
        end
        
        -- 交互处理：点击、拖拽、悬停（使用第一次循环中检测到的状态）
        if is_configured and item.slot then
            -- 使用第一次循环中存储的状态
            local is_clicked = state.is_clicked
            local is_dragging = state.is_dragging
            
            -- 重新设置光标位置以访问按钮状态（用于拖拽源检测）
            reaper.ImGui_SetCursorPos(ctx, state.rel_x, state.rel_y)
            -- 使用 PushID 确保每个按钮的 ID 唯一
            reaper.ImGui_PushID(ctx, state.button_id)
            
            -- 重新创建 InvisibleButton 以访问当前帧的状态（仅用于拖拽源）
            reaper.ImGui_InvisibleButton(ctx, state.button_id, rect[3] - rect[1], rect[4] - rect[2])
            
            -- 拖拽源：如果开始拖拽，设置拖拽 payload
            if is_dragging and item.slot.type == "action" and item.slot.data and item.slot.data.command_id then
                if reaper.ImGui_BeginDragDropSource(ctx, reaper.ImGui_DragDropFlags_None()) then
                    -- payload 格式：command_id|name（与 browser.lua 保持一致）
                    local cmd_id = item.slot.data.command_id
                    local slot_name = item.slot.name or ""
                    local payload_data = string.format("%d|%s", cmd_id, slot_name)
                    reaper.ImGui_SetDragDropPayload(ctx, "DND_ACTION", payload_data)
                    reaper.ImGui_Text(ctx, slot_name)
                    reaper.ImGui_EndDragDropSource(ctx)
                end
            end
            
            -- 点击处理：纯点击（非拖拽）时执行 Action
            -- 关键：使用第一次循环中检测到的 is_clicked 和 is_dragging 状态
            if is_clicked and not is_dragging then
                -- 执行 slot（空值检查）
                if item.slot then
                    interaction.handle_item_click(item.slot)
                end
            end
            
            -- Tooltip：悬停时显示名称
            if reaper.ImGui_IsItemHovered(ctx) and not is_dragging then
                local tooltip = item.slot.name
                if tooltip and tooltip ~= "" then
                    reaper.ImGui_BeginTooltip(ctx)
                    reaper.ImGui_Text(ctx, tooltip)
                    reaper.ImGui_EndTooltip(ctx)
                end
            end
            
            reaper.ImGui_PopID(ctx)
        end
    end
    
    return is_submenu_hovered
end

return M

