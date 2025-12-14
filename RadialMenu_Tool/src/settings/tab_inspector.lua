-- @description RadialMenu Tool - 属性编辑栏模块
-- @author Lee
-- @about
--   属性编辑栏：编辑选中插槽的属性

local M = {}

-- ============================================================================
-- 绘制函数
-- ============================================================================

-- 绘制插槽编辑器（属性栏）
-- @param ctx ImGui context
-- @param slot table: 插槽数据（可能为 nil）
-- @param index number: 插槽索引
-- @param sector table: 所属扇区
-- @param state table: 状态对象（包含 is_modified 等）
function M.draw(ctx, slot, index, sector, state)
    local header_text = string.format("插槽 %d", index)
    
    if not slot then
        reaper.ImGui_TextDisabled(ctx, header_text .. " (空)")
        return
    end
    
    reaper.ImGui_Text(ctx, header_text)
    reaper.ImGui_SameLine(ctx)
    
    -- 清理插槽按钮
    if reaper.ImGui_Button(ctx, "清理插槽##Slot" .. index, 0, 0) then
        -- 将插槽重置为空插槽，保留插槽位置
        sector.slots[index] = { type = "empty" }
        state.is_modified = true
    end
    
    reaper.ImGui_SameLine(ctx)
    
    -- 删除按钮
    if reaper.ImGui_Button(ctx, "删除##Slot" .. index, 0, 0) then
        sector.slots[index] = nil
        state.is_modified = true
    end
    
    reaper.ImGui_Spacing(ctx)
    
    -- 标签输入
    reaper.ImGui_Text(ctx, "  标签:")
    reaper.ImGui_SameLine(ctx)
    local name_buf = slot.name or ""
    local name_changed, new_name = reaper.ImGui_InputText(ctx, "##SlotName" .. index, name_buf, 256)
    if name_changed then
        slot.name = new_name
        state.is_modified = true
    end
    
    reaper.ImGui_Spacing(ctx)
    
    -- 类型下拉框
    reaper.ImGui_Text(ctx, "  类型:")
    reaper.ImGui_SameLine(ctx)
    local type_options = {"action", "fx", "chain", "template"}
    local current_type = slot.type or "action"
    local current_type_display = current_type
    
    -- 使用 BeginCombo/EndCombo
    if reaper.ImGui_BeginCombo(ctx, "##SlotType" .. index, current_type_display, reaper.ImGui_ComboFlags_None()) then
        for i, opt in ipairs(type_options) do
            local is_selected = (opt == current_type)
            if reaper.ImGui_Selectable(ctx, opt, is_selected, reaper.ImGui_SelectableFlags_None(), 0, 0) then
                slot.type = opt
                -- 重置 data 字段
                if slot.type == "action" then
                    slot.data = {command_id = 0}
                elseif slot.type == "fx" then
                    slot.data = {fx_name = ""}
                elseif slot.type == "chain" then
                    slot.data = {path = ""}
                elseif slot.type == "template" then
                    slot.data = {path = ""}
                end
                state.is_modified = true
            end
            if is_selected then
                reaper.ImGui_SetItemDefaultFocus(ctx)
            end
        end
        reaper.ImGui_EndCombo(ctx)
    end
    
    reaper.ImGui_Spacing(ctx)
    
    -- 根据类型显示不同的输入字段
    if slot.type == "action" then
        reaper.ImGui_Text(ctx, "  Command ID:")
        reaper.ImGui_SameLine(ctx)
        local cmd_id = slot.data and slot.data.command_id or 0
        local cmd_id_changed, new_cmd_id = reaper.ImGui_InputInt(ctx, "##SlotValue" .. index, cmd_id, 1, 100)
        if cmd_id_changed then
            if not slot.data then slot.data = {} end
            slot.data.command_id = new_cmd_id
            state.is_modified = true
        end
        
    elseif slot.type == "fx" then
        reaper.ImGui_Text(ctx, "  FX 名称:")
        reaper.ImGui_SameLine(ctx)
        local fx_name = slot.data and slot.data.fx_name or ""
        local fx_name_changed, new_fx_name = reaper.ImGui_InputText(ctx, "##SlotValue" .. index, fx_name, 256)
        if fx_name_changed then
            if not slot.data then slot.data = {} end
            slot.data.fx_name = new_fx_name
            state.is_modified = true
        end
        
    elseif slot.type == "chain" then
        reaper.ImGui_Text(ctx, "  Chain 路径:")
        reaper.ImGui_SameLine(ctx)
        local chain_path = slot.data and slot.data.path or ""
        local chain_path_changed, new_chain_path = reaper.ImGui_InputText(ctx, "##SlotValue" .. index, chain_path, 512)
        if chain_path_changed then
            if not slot.data then slot.data = {} end
            slot.data.path = new_chain_path
            state.is_modified = true
        end
        
    elseif slot.type == "template" then
        reaper.ImGui_Text(ctx, "  Template 路径:")
        reaper.ImGui_SameLine(ctx)
        local template_path = slot.data and slot.data.path or ""
        local template_path_changed, new_template_path = reaper.ImGui_InputText(ctx, "##SlotValue" .. index, template_path, 512)
        if template_path_changed then
            if not slot.data then slot.data = {} end
            slot.data.path = new_template_path
            state.is_modified = true
        end
    end
end

return M

