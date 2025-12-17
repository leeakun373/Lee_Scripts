-- src/settings/tab_inspector.lua
-- @description RadialMenu Tool - 属性编辑栏模块 (Final Logic Fix)
-- @author Lee

local M = {}
local execution = require("logic.execution")

function M.draw(ctx, slot, index, sector, state)
    -- [已移除] 自动初始化代码。现在只有真正有内容的插槽才会进入这里。
    if not slot then return end

    -- [CHANGED] Compact Header Layout
    -- Reduce spacing and vertical padding
    reaper.ImGui_PushStyleVar(ctx, reaper.ImGui_StyleVar_ItemSpacing(), 8, 4)
    
    reaper.ImGui_AlignTextToFramePadding(ctx)
    reaper.ImGui_Text(ctx, string.format("插槽 %d", index)) -- Simplified title
    
    reaper.ImGui_SameLine(ctx)
    local avail_w = reaper.ImGui_GetContentRegionAvail(ctx)
    
    -- [CHANGED] Smart Button Logic
    -- 1. "Clear" (Available for all non-empty slots)
    -- 2. "Delete" (Only available if slot count > 9)
    
    local total_slots = #sector.slots
    local show_delete = total_slots > 9
    
    local btn_w = 60
    local btn_spacing = 5
    
    -- Calculate position to align right
    local right_align_start = reaper.ImGui_GetCursorPosX(ctx) + avail_w
    if show_delete then
        right_align_start = right_align_start - (btn_w * 2) - btn_spacing
    else
        right_align_start = right_align_start - btn_w
    end
    
    reaper.ImGui_SetCursorPosX(ctx, right_align_start)
    
    -- Draw Clear Button
    if reaper.ImGui_Button(ctx, "清除", btn_w, 0) then
        sector.slots[index] = { type = "empty" }
        state.is_modified = true
    end
    if reaper.ImGui_IsItemHovered(ctx) then
        reaper.ImGui_SetTooltip(ctx, "清空内容，保留位置")
    end
    
    -- Draw Delete Button (Conditionally)
    if show_delete then
        reaper.ImGui_SameLine(ctx, 0, btn_spacing)
        reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Button(), 0x992222FF)
        reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ButtonHovered(), 0xB92b2bFF)
        if reaper.ImGui_Button(ctx, "删除", btn_w, 0) then
            table.remove(sector.slots, index)
            state.selected_slot_index = nil
            state.is_modified = true
        end
        reaper.ImGui_PopStyleColor(ctx, 2)
        if reaper.ImGui_IsItemHovered(ctx) then
            reaper.ImGui_SetTooltip(ctx, "移除此格子 (后续格子前移)")
        end
    end
    
    reaper.ImGui_PopStyleVar(ctx) -- Pop ItemSpacing
    
    reaper.ImGui_Separator(ctx)
    -- reaper.ImGui_Spacing(ctx) -- Remove extra spacing for compactness

    -- === 属性表单 (简化为 2 列) ===
    if reaper.ImGui_BeginTable(ctx, "InspectorTable", 2, reaper.ImGui_TableFlags_BordersInnerV()) then
        reaper.ImGui_TableSetupColumn(ctx, "Label", reaper.ImGui_TableColumnFlags_WidthFixed(), 65)
        reaper.ImGui_TableSetupColumn(ctx, "Input", reaper.ImGui_TableColumnFlags_WidthStretch())
        
        -- Row 1: Name
        reaper.ImGui_TableNextRow(ctx)
        reaper.ImGui_TableNextColumn(ctx)
        reaper.ImGui_AlignTextToFramePadding(ctx)
        reaper.ImGui_Text(ctx, "显示名称")
        reaper.ImGui_TableNextColumn(ctx)
        reaper.ImGui_SetNextItemWidth(ctx, -1)
        local name_buf = slot.name or ""
        local name_changed, new_name = reaper.ImGui_InputText(ctx, "##SlotName", name_buf, 256)
        if name_changed then slot.name = new_name; state.is_modified = true end
        
        -- Row 2: Content
        reaper.ImGui_TableNextRow(ctx)
        reaper.ImGui_TableNextColumn(ctx)
        reaper.ImGui_AlignTextToFramePadding(ctx)
        local type_label = "内容"
        if slot.type == "action" then type_label = "Cmd ID"
        elseif slot.type == "fx" then type_label = "FX 名"
        elseif slot.type == "chain" then type_label = "Chain"
        elseif slot.type == "template" then type_label = "Templ"
        end
        reaper.ImGui_Text(ctx, type_label)
        
        reaper.ImGui_TableNextColumn(ctx)
        reaper.ImGui_SetNextItemWidth(ctx, -1)
        
        -- Input Logic
        if slot.type == "action" then
            local cmd_id = slot.data and slot.data.command_id or ""
            local id_str = tostring(cmd_id)
            if id_str == "0" then id_str = "" end
            local id_changed, new_id_str = reaper.ImGui_InputText(ctx, "##ContentInput", id_str, 256)
            if id_changed then
                if not slot.data then slot.data = {} end
                local num = tonumber(new_id_str)
                slot.data.command_id = num or new_id_str
                -- 自动填充名字
                if (not slot.name or slot.name == "" or slot.name == "新 Action") and new_id_str ~= "" then
                     local int_id = num or reaper.NamedCommandLookup(new_id_str)
                     if int_id and int_id > 0 then
                         local action_name = reaper.CF_GetCommandText(0, int_id)
                         if action_name and action_name ~= "" then slot.name = action_name end
                     end
                end
                state.is_modified = true
            end
        elseif slot.type == "fx" then
            local fx_name = slot.data and slot.data.fx_name or ""
            local fx_changed, new_fx = reaper.ImGui_InputText(ctx, "##ContentInput", fx_name, 256)
            if fx_changed then
                if not slot.data then slot.data = {} end
                slot.data.fx_name = new_fx; state.is_modified = true
            end
        else
            -- Chain/Template Path
            local path = slot.data and slot.data.path or ""
            local path_changed, new_path = reaper.ImGui_InputText(ctx, "##ContentInput", path, 512)
            if path_changed then
                if not slot.data then slot.data = {} end
                slot.data.path = new_path; state.is_modified = true
            end
        end
        
        reaper.ImGui_EndTable(ctx)
    end
    
    -- === 辅助信息 ===
    -- [CHANGED] Remove the "Open Action List" button from the bottom
    -- It is being moved to the browser section.
    if slot.type == "fx" then
        reaper.ImGui_Spacing(ctx)
        reaper.ImGui_TextDisabled(ctx, "提示: 推荐从下方 FX 列表拖入，手写需精准")
    end
end

return M
