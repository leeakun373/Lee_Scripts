--[[
  Helper functions for Item Workstation
]]

local Helpers = {}

-- Push button style colors
function Helpers.PushBtnStyle(ctx, color_code)
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Button(), color_code)
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ButtonHovered(), color_code + 0x11111100)
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ButtonActive(), color_code - 0x11111100)
end

-- Get tooltip text for a function (Chinese tooltips)
function Helpers.getTooltipText(func)
    -- Return description if available
    if func.description and func.description ~= "" then
        return func.description
    end
    -- For item functions, try to get Chinese description
    if func.name then
        -- Map common function names to Chinese descriptions
        local chinese_descriptions = {
            ["Jump to Previous"] = "跳转到选中轨道上的上一个媒体项",
            ["Jump to Next"] = "跳转到选中轨道上的下一个媒体项",
            ["Move Cursor to Item Start"] = "将编辑光标移动到选中媒体项的起始位置",
            ["Move Cursor to Item End"] = "将编辑光标移动到选中媒体项的结束位置",
            ["Select Unmuted Items"] = "选择所有未静音的媒体项",
            ["Trim Items to Reference Length"] = "将媒体项修剪到参考长度",
            ["Add Fade In Out"] = "为选中的媒体项添加淡入淡出",
            ["Select All Items on Track"] = "选择轨道上的所有媒体项",
        }
        if chinese_descriptions[func.name] then
            return chinese_descriptions[func.name]
        end
    end
    return "点击执行功能"
end

return Helpers

