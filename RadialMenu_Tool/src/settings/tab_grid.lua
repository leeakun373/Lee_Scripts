-- @description RadialMenu Tool - 网格编辑器模块
-- @author Lee
-- @about
--   子菜单网格编辑器：3x3 网格布局，支持拖放和交换

local M = {}

-- ============================================================================
-- 模块依赖
-- ============================================================================

local tab_browser = require("settings.tab_browser")

-- ============================================================================
-- 模块状态变量
-- ============================================================================

local tooltip_hover_start_time = 0  -- Tooltip 悬停开始时间
local tooltip_current_slot_id = nil  -- 当前悬停的插槽 ID

-- ============================================================================
-- 绘制函数
-- ============================================================================

-- 绘制子菜单网格编辑器（3列网格，支持拖放）
-- @param ctx ImGui context
-- @param sector table: 当前扇区
-- @param state table: 状态对象（包含 selected_slot_index, is_modified 等）
function M.draw(ctx, sector, state)
    -- 确保 slots 数组存在
    if not sector.slots then
        sector.slots = {}
    end
    
    -- 计算需要显示的插槽数量（至少9个，可扩展）
    local min_slots = 9
    local current_slot_count = #sector.slots
    local display_count = math.max(min_slots, current_slot_count)
    
    -- 3列网格布局（严格对齐）
    local cols = 3
    local spacing = 8  -- 列间距
    local btn_h = 40  -- 固定按钮高度，更好的视觉效果
    
    -- 计算按钮宽度（动态适应3列）
    local avail_w = reaper.ImGui_GetContentRegionAvail(ctx)
    local btn_w = (avail_w - (spacing * (cols - 1))) / cols
    
    -- 绘制网格（严格3列布局）
    for i = 1, display_count do
        -- 如果不是第一列，使用 SameLine
        if (i - 1) % cols ~= 0 then
            reaper.ImGui_SameLine(ctx, 0, spacing)
        end
        
        local slot = sector.slots[i]
        local slot_id = "##Slot" .. i
        
        reaper.ImGui_PushID(ctx, slot_id)
        
        -- 检查是否选中
        local is_selected = (state.selected_slot_index == i)
        
        -- Check if slot exists AND is not an "empty" placeholder
        local is_real_slot = slot and slot.type ~= "empty"
        
        -- 绘制插槽
        if is_real_slot then
            -- 已填充插槽：实心按钮样式
            local full_name = slot.name or "未命名"
            local button_label = full_name
            
            -- 计算文本宽度，如果太长则截断
            local text_width, text_height = reaper.ImGui_CalcTextSize(ctx, button_label)
            local max_text_width = btn_w - 16  -- 留出边距
            
            if text_width > max_text_width then
                -- 截断文本
                local truncated = ""
                for j = 1, string.len(button_label) do
                    local test_text = string.sub(button_label, 1, j)
                    local test_w, _ = reaper.ImGui_CalcTextSize(ctx, test_text .. "...")
                    if test_w > max_text_width then
                        truncated = string.sub(button_label, 1, j - 1) .. "..."
                        break
                    end
                end
                button_label = truncated or (string.sub(button_label, 1, 8) .. "...")
            end
            
            -- 已配置的按钮：比背景明显亮一个度（更易区分）
            local filled_bg = 0x2A2A2FFF  -- 比空插槽亮
            local filled_hovered = 0x3A3A3FFF
            local filled_active = 0x4A4A4FFF
            
            -- 如果选中，进一步高亮
            if is_selected then
                filled_bg = 0x3F3F46FF
                filled_hovered = 0x4F4F56FF
                filled_active = 0x5F5F66FF
            end
            
            reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Button(), filled_bg)
            reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ButtonHovered(), filled_hovered)
            reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ButtonActive(), filled_active)
            
            if reaper.ImGui_Button(ctx, button_label, btn_w, btn_h) then
                state.selected_slot_index = i
            end
            
            -- Simplified Context Menu (Only Clear)
            if reaper.ImGui_BeginPopupContextItem(ctx) then
                if is_real_slot then
                    if reaper.ImGui_MenuItem(ctx, "清除插槽 (Clear)") then
                        sector.slots[i] = { type = "empty" }
                        if state.selected_slot_index == i then state.selected_slot_index = nil end
                        state.is_modified = true
                    end
                else
                    -- Optional: Fast add for empty slots, or just nothing
                    if reaper.ImGui_MenuItem(ctx, "添加新 Action") then
                        sector.slots[i] = { type = "action", name = "新 Action", data = { command_id = 0 } }
                        state.selected_slot_index = i
                        state.is_modified = true
                    end
                end
                reaper.ImGui_EndPopup(ctx)
            end
            
            -- Delayed Tooltip with Original Info
            if is_real_slot then
                if reaper.ImGui_IsItemHovered(ctx) then
                    -- Logic: If hovering a new item, reset timer.
                    if tooltip_current_slot_id ~= i then
                        tooltip_current_slot_id = i
                        tooltip_hover_start_time = reaper.time_precise()
                    end
                    
                    -- Check for 1.0s delay
                    if (reaper.time_precise() - tooltip_hover_start_time) > 1.0 then
                        if reaper.ImGui_BeginTooltip(ctx) then
                            -- Content Generation
                            if slot.type == "action" then
                                local cmd_id = slot.data and slot.data.command_id
                                -- Fetch original name from actions cache
                                local orig_name = "Unknown Action"
                                local actions_cache = tab_browser.get_actions_cache()
                                if actions_cache then
                                    for _, action in ipairs(actions_cache) do
                                        if action.command_id == cmd_id then
                                            orig_name = action.name or "Unknown Action"
                                            break
                                        end
                                    end
                                end
                                
                                -- Format: "2020: Action: Disarm action"
                                reaper.ImGui_Text(ctx, string.format("%s: Action: %s", tostring(cmd_id), orig_name))
                                
                            elseif slot.type == "fx" then
                                local fx_name = slot.data and slot.data.fx_name or "Unknown"
                                reaper.ImGui_Text(ctx, "FX: " .. fx_name)
                                
                            elseif slot.type == "chain" then
                                local path = slot.data and slot.data.path or ""
                                local filename = path:match("([^/\\]+)$") or path
                                reaper.ImGui_Text(ctx, "Chain: " .. filename)
                                
                            elseif slot.type == "template" then
                                local path = slot.data and slot.data.path or ""
                                local filename = path:match("([^/\\]+)$") or path
                                reaper.ImGui_Text(ctx, "Template: " .. filename)
                            end
                            
                            reaper.ImGui_EndTooltip(ctx)
                        end
                    end
                else
                    -- Reset if mouse leaves this specific item
                    if tooltip_current_slot_id == i then
                        tooltip_current_slot_id = nil
                    end
                end
            end
            
            -- Pop 3 个颜色（Button, ButtonHovered, ButtonActive）
            reaper.ImGui_PopStyleColor(ctx, 3)
            
            -- 拖拽源：允许在网格内拖拽插槽进行交换
            if reaper.ImGui_BeginDragDropSource(ctx, reaper.ImGui_DragDropFlags_None()) then
                reaper.ImGui_SetDragDropPayload(ctx, "DND_GRID_SWAP", tostring(i))
                reaper.ImGui_Text(ctx, "Move: " .. (slot.name or "Empty"))
                reaper.ImGui_EndDragDropSource(ctx)
            end
        else
            -- 空插槽：更暗的背景，一眼就能看出是空的
            reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Button(), 0x141414FF)  -- 更暗
            reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ButtonHovered(), 0x1E1E1EFF)  -- 悬停时稍亮
            reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ButtonActive(), 0x282828FF)
            reaper.ImGui_PushStyleVar(ctx, reaper.ImGui_StyleVar_FrameBorderSize(), 1.0)
            
            if is_selected then
                reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Button(), 0x2A2A2AFF)
            end
            
            if reaper.ImGui_Button(ctx, "Empty", btn_w, btn_h) then
                -- 左键点击空插槽：选中
                state.selected_slot_index = i
            end
            
            -- Context Menu (Right Click) - Attached directly to button
            if reaper.ImGui_BeginPopupContextItem(ctx) then
                -- Empty slot options
                if reaper.ImGui_MenuItem(ctx, "添加新 Action") then
                    sector.slots[i] = { type = "action", name = "新 Action", data = { command_id = 0 } }
                    state.selected_slot_index = i
                    state.is_modified = true
                end
                reaper.ImGui_EndPopup(ctx)
            end
            
            if is_selected then
                reaper.ImGui_PopStyleColor(ctx, 1)
            end
            
            reaper.ImGui_PopStyleVar(ctx)
            reaper.ImGui_PopStyleColor(ctx, 3)
            
            -- 拖拽源：空插槽也可以拖拽（用于交换位置）
            if reaper.ImGui_BeginDragDropSource(ctx, reaper.ImGui_DragDropFlags_None()) then
                reaper.ImGui_SetDragDropPayload(ctx, "DND_GRID_SWAP", tostring(i))
                reaper.ImGui_Text(ctx, "Move: Empty")
                reaper.ImGui_EndDragDropSource(ctx)
            end
        end
        
        -- 设置插槽为拖放目标（在按钮之后，绑定到按钮）
        -- 支持覆盖已有内容：直接设置新值，无论插槽是否已有内容
        if reaper.ImGui_BeginDragDropTarget(ctx) then
            -- 优先处理网格内交换
            local ret_swap, payload_swap = reaper.ImGui_AcceptDragDropPayload(ctx, "DND_GRID_SWAP")
            if ret_swap and payload_swap then
                local source_idx = tonumber(payload_swap)
                local target_idx = i
                if source_idx and source_idx ~= target_idx and source_idx >= 1 and source_idx <= display_count then
                    -- SWAP
                    local temp = sector.slots[source_idx]
                    sector.slots[source_idx] = sector.slots[target_idx]
                    sector.slots[target_idx] = temp
                    
                    -- 如果选中的插槽被交换，更新选中索引
                    if state.selected_slot_index == source_idx then
                        state.selected_slot_index = target_idx
                    elseif state.selected_slot_index == target_idx then
                        state.selected_slot_index = source_idx
                    end
                    
                    state.is_modified = true
                end
            else
                -- 处理外部拖放（Action/FX）
                local ret, payload = reaper.ImGui_AcceptDragDropPayload(ctx, "DND_ACTION")
                if ret then
                    -- 处理 Action 拖放（payload 格式: "command_id|name"）
                    if payload then
                        local parts = {}
                        for part in string.gmatch(payload, "[^|]+") do
                            table.insert(parts, part)
                        end
                        if #parts >= 2 then
                            local cmd_id = tonumber(parts[1]) or 0
                            local name = parts[2] or ""
                            -- 直接覆盖，无论插槽是否已有内容
                            sector.slots[i] = {
                                type = "action",
                                name = name,
                                data = {command_id = cmd_id}
                            }
                            state.selected_slot_index = i  -- 自动选中该插槽
                            state.is_modified = true
                        end
                    end
                else
                    ret, payload = reaper.ImGui_AcceptDragDropPayload(ctx, "DND_FX")
                    if ret then
                        -- 处理 FX/Chain/Template 拖放（payload 格式: "type|id"）
                        if payload then
                            local parts = {}
                            for part in string.gmatch(payload, "[^|]+") do
                                table.insert(parts, part)
                            end
                            
                            if #parts >= 2 then
                                local payload_type = parts[1]  -- fx, chain, template
                                local payload_id = parts[2]    -- original_name, path, etc.
                                
                                -- 根据类型创建不同的插槽数据
                                if payload_type == "chain" then
                                    sector.slots[i] = {
                                        type = "chain",
                                        name = payload_id:match("([^/\\]+)%.RfxChain$") or payload_id,
                                        data = {path = payload_id}
                                    }
                                elseif payload_type == "template" then
                                    sector.slots[i] = {
                                        type = "template",
                                        name = payload_id:match("([^/\\]+)%.RTrackTemplate$") or payload_id,
                                        data = {path = payload_id}
                                    }
                                else
                                    -- 默认 FX
                                    sector.slots[i] = {
                                        type = "fx",
                                        name = payload_id:gsub("^[^:]+: ", ""),  -- 移除前缀
                                        data = {fx_name = payload_id}
                                    }
                                end
                                
                                state.selected_slot_index = i  -- 自动选中该插槽
                                state.is_modified = true
                            else
                                -- 兼容旧格式（只有 fx_name）
                                sector.slots[i] = {
                                    type = "fx",
                                    name = payload,
                                    data = {fx_name = payload}
                                }
                                state.selected_slot_index = i
                                state.is_modified = true
                            end
                        end
                    end
                end
            end
            reaper.ImGui_EndDragDropTarget(ctx)
        end
        
        reaper.ImGui_PopID(ctx)
    end
    
    -- 添加 "+" 按钮（扩展插槽）
    if (display_count % cols) ~= 0 then
        reaper.ImGui_SameLine(ctx, 0, spacing)
    end
    
    if reaper.ImGui_Button(ctx, "+", btn_w, btn_h) then
        -- 添加新插槽
        table.insert(sector.slots, {
            type = "action",
            name = "新插槽",
            data = {command_id = 0}
        })
        state.is_modified = true
    end
end

return M

