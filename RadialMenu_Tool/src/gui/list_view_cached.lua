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
function M.draw_submenu_cached(ctx, sector_data, center_x, center_y, anim_scale, config, dragging_slot_ref, draw_submenu_fallback)
    if not sector_data or not config then return false end
    
    -- 1. 直接读内存
    local cached_data = submenu_bake_cache.get_cached(sector_data.id)
    if not cached_data then
        if draw_submenu_fallback then
            return draw_submenu_fallback(ctx, sector_data, center_x, center_y, anim_scale, config)
        end
        return false
    end
    
    local draw_list = reaper.ImGui_GetWindowDrawList(ctx)
    if not draw_list then return false end
    
    local bake_cfg = submenu_bake_cache.get_config()
    local max_bounds = submenu_bake_cache.get_max_bounds()
    
    -- 获取窗口内的圆心位置
    local win_x, win_y = reaper.ImGui_GetWindowPos(ctx)
    local cx = win_x + max_bounds.center_offset_x
    local cy = win_y + max_bounds.center_offset_y
    
    -- 2. 直接画背景
    local bg_rect_rel = cached_data.bg_rect_rel
    reaper.ImGui_DrawList_AddRectFilled(draw_list, 
        cx + bg_rect_rel[1], cy + bg_rect_rel[2], cx + bg_rect_rel[3], cy + bg_rect_rel[4], 
        bake_cfg.bg_color, 8.0)
    
    -- 3. 绘制边框
    local border_color = styles.correct_rgba_to_u32({0, 0, 0, 255})
    reaper.ImGui_DrawList_AddRect(draw_list,
        cx + bg_rect_rel[1], cy + bg_rect_rel[2], cx + bg_rect_rel[3], cy + bg_rect_rel[4],
        border_color, 8.0, 0, 1.0)
    
    -- 4. 【单次遍历循环】绘制 + 交互
    local button_colors = button.get_button_colors()
    local is_submenu_hovered = false
    
    for i, item in ipairs(cached_data.items) do
        -- [A] 计算绝对坐标
        local rect = {
            cx + item.rect_rel[1],
            cy + item.rect_rel[2],
            cx + item.rect_rel[3],
            cy + item.rect_rel[4]
        }
        
        -- 生成唯一 ID
        local grid_index = (item.grid_pos[1] or 0) * cached_data.cols + (item.grid_pos[2] or 0) + 1
        local button_id = "##BakedSlot_" .. tostring(sector_data.id) .. "_" .. tostring(grid_index) .. "_" .. tostring(i)
        
        -- [B] 交互层：放置隐形按钮
        -- 【关键修复】使用 SetCursorScreenPos 替代 SetCursorPos
        -- 这样可以忽略窗口 Padding，确保按钮与 DrawList 绘制的位置严丝合缝
        reaper.ImGui_SetCursorScreenPos(ctx, rect[1], rect[2])
        
        reaper.ImGui_PushID(ctx, button_id) 
        reaper.ImGui_InvisibleButton(ctx, "btn", rect[3] - rect[1], rect[4] - rect[2])
        
        -- [C] 状态检测
        local is_active = reaper.ImGui_IsItemActive(ctx)
        local is_hover = reaper.ImGui_IsItemHovered(ctx)
        local is_clicked = reaper.ImGui_IsItemClicked(ctx, 0)
        
        if is_hover then is_submenu_hovered = true end
        
        local is_configured = item.slot and item.slot.type ~= "empty"
        
        -- [D] 拖拽触发 (已包含 CommandID 格式化修复)
        local is_dragging = false
        if is_configured and is_active then
            if reaper.ImGui_IsMouseDragging(ctx, 0) then
                is_dragging = true
                
                -- 获取 Command ID
                local cmd_id = nil
                if item.slot.data and item.slot.data.command_id then
                    cmd_id = item.slot.data.command_id
                elseif item.slot.command_id then
                    cmd_id = item.slot.command_id
                end

                if cmd_id then
                    if reaper.ImGui_BeginDragDropSource(ctx, reaper.ImGui_DragDropFlags_None()) then
                        local slot_name = item.slot.name or ""
                        local payload_data = string.format("%s|%s", tostring(cmd_id), slot_name)
                        
                        reaper.ImGui_SetDragDropPayload(ctx, "DND_ACTION", payload_data)
                        reaper.ImGui_Text(ctx, slot_name) -- 预览
                        reaper.ImGui_EndDragDropSource(ctx)
                    end
                end
                
                if dragging_slot_ref then dragging_slot_ref[1] = item.slot end
            end
        end
        
        reaper.ImGui_PopID(ctx) 
        
        -- [E] 绘制状态反馈 (DrawList)
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
        
        local bg_color = col_normal
        if is_active then bg_color = col_active
        elseif is_hover then bg_color = col_hover end
        
        reaper.ImGui_DrawList_AddRectFilled(draw_list, rect[1], rect[2], rect[3], rect[4], bg_color, 4.0)
        reaper.ImGui_DrawList_AddRect(draw_list, rect[1], rect[2], rect[3], rect[4], col_border, 4.0, 0, 1.0)
        
        if item.text and item.text ~= "" then
            local text_pos = { cx + item.text_pos_rel[1], cy + item.text_pos_rel[2] }
            reaper.ImGui_DrawList_PushClipRect(draw_list, rect[1], rect[2], rect[3], rect[4], true)
            reaper.ImGui_DrawList_AddText(draw_list, text_pos[1], text_pos[2], text_color, item.text)
            reaper.ImGui_DrawList_PopClipRect(draw_list)
        end
        
        -- [F] 点击处理
        if is_configured and item.slot then
            if is_clicked and not is_dragging then
                interaction.handle_item_click(item.slot)
            end
            
            -- Tooltip
            if is_hover and not is_dragging then
                local tooltip = item.slot.name
                if tooltip and tooltip ~= "" then
                    reaper.ImGui_BeginTooltip(ctx)
                    reaper.ImGui_Text(ctx, tooltip)
                    reaper.ImGui_EndTooltip(ctx)
                end
            end
        end
    end
    
    return is_submenu_hovered
end

return M
