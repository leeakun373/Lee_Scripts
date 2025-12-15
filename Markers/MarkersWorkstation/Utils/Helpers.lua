--[[
  Helper functions for Marker Workstation
]]

local Helpers = {}

-- Push button style colors
function Helpers.PushBtnStyle(ctx, color_code)
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Button(), color_code)
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ButtonHovered(), color_code + 0x11111100)
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ButtonActive(), color_code - 0x11111100)
end

-- Validate and convert action ID
function Helpers.validateActionID(action_id_str)
    -- Try as number first
    local action_id = tonumber(action_id_str)
    if action_id then
        return action_id
    end
    
    -- Try as named command
    action_id = reaper.NamedCommandLookup(action_id_str)
    if action_id and action_id > 0 then
        return action_id
    end
    
    return nil
end

-- Get tooltip text for a function
function Helpers.getTooltipText(func)
    local tooltips = {
        ["Align to Markers"] = "根据文件名匹配，将选中的媒体项对齐到同名标记位置",
        ["Copy to Cursor"] = "复制最近的标记到光标位置",
        ["Create from Items"] = "在选中媒体项的位置创建标记（使用备注作为名称）",
        ["Create Regions from Markers"] = "为每个标记附近的媒体项创建区域",
        ["Delete in Time Selection"] = "删除时间选择范围内的所有标记",
        ["Move to Cursor"] = "将最近的标记移动到光标位置",
        ["Move to Item Head"] = "批量将标记移动到选中媒体项的头部",
        ["Renumber Markers"] = "按时间顺序重新编号所有标记为 1, 2, 3..."
    }
    
    return tooltips[func.name] or func.description or "点击执行功能"
end

return Helpers


























