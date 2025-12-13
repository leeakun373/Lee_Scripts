--[[
  Helper functions for Item Parameter Copier
]]

local Helpers = {}

-- Push button style colors
function Helpers.PushBtnStyle(ctx, color_code)
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Button(), color_code)
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ButtonHovered(), color_code + 0x11111100)
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ButtonActive(), color_code - 0x11111100)
end

-- Helper to safely get item position
function Helpers.getItemPosition(item)
    if not item or not reaper.ValidatePtr(item, "MediaItem*") then
        return nil
    end
    return reaper.GetMediaItemInfo_Value(item, "D_POSITION")
end

-- Helper to safely get item length
function Helpers.getItemLength(item)
    if not item or not reaper.ValidatePtr(item, "MediaItem*") then
        return nil
    end
    return reaper.GetMediaItemInfo_Value(item, "D_LENGTH")
end

return Helpers

