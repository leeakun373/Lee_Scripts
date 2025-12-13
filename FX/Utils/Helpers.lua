--[[
  Helper functions for FX Manager
]]

local Helpers = {}
local r = reaper

-- Push button style colors
function Helpers.PushBtnStyle(ctx, color_code)
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Button(), color_code)
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonHovered(), color_code + 0x11111100)
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonActive(), color_code - 0x11111100)
end

-- Push FX button style (Hero buttons with border)
function Helpers.PushFXButtonStyle(ctx, theme)
    local base_color = theme.BTN_FX_ON or 0x6C5CE7FF
    local hover_color = theme.BTN_FX_HOVER or 0xA29BFEFF
    local active_color = theme.BTN_FX_ACTIVE or 0xFFFFFF80
    local border_color = theme.BTN_FX_BORDER or 0xD8BFD880
    
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Button(), base_color)
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonHovered(), hover_color)
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonActive(), active_color)
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Border(), border_color)
    
    -- Enable border
    r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_FrameBorderSize(), 1.0)
    -- Harder rounding
    r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_FrameRounding(), 4.0)
end

-- Pop FX button style
function Helpers.PopFXButtonStyle(ctx)
    r.ImGui_PopStyleVar(ctx, 2)
    r.ImGui_PopStyleColor(ctx, 4)
end

-- Check if JS_ReaScriptAPI is available (needed for window operations)
function Helpers.IsJSAvailable()
    return r.APIExists("JS_Window_GetRect") and r.APIExists("JS_Window_Move")
end

-- Get screen dimensions
function Helpers.GetScreenDimensions()
    if not Helpers.IsJSAvailable() then
        return 1920, 1080  -- Default fallback
    end
    
    -- Get main window handle
    local hwnd = r.JS_Window_Find("REAPER", true)
    if hwnd then
        local ret, left, top, right, bottom = r.JS_Window_GetRect(hwnd)
        if ret then
            -- Get screen dimensions (approximate)
            return right - left, bottom - top
        end
    end
    
    return 1920, 1080  -- Default fallback
end

-- Calculate grid layout for FX windows
function Helpers.CalculateGridLayout(count, max_cols)
    max_cols = max_cols or 3
    local cols = math.min(count, max_cols)
    local rows = math.ceil(count / cols)
    return cols, rows
end

-- Get FX window dimensions (estimate)
function Helpers.GetFXWindowDimensions()
    -- These are estimates, actual windows may vary
    return 400, 500  -- width, height
end

return Helpers

