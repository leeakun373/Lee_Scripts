--[[
  REAPER Lua Script: Radial Menu (Mantrika-style)
  Description: Circular radial menu with submenus
  - Inspired by Mantrika Tools Radial Menu
  - Uses ReaImGui for rendering
  - Supports 1-6 sectors with submenus
  - Mouse hover to show submenus
  - Click to execute actions
  
  Features:
  - Circular menu with configurable sectors
  - Submenu on hover
  - Action execution
  - Basic configuration system
]]

-- Check if ReaImGui is available
if not reaper.ImGui_CreateContext then
    reaper.ShowMessageBox("This script requires ReaImGui extension.\nPlease install 'ReaImGui' from Extensions > ReaPack > Browse packages", "Missing Dependency", 0)
    return
end

-- Configuration
local config = {
    sector_count = 6,  -- Number of sectors (1-6)
    radius = 100,      -- Menu radius in pixels
    center_radius = 20, -- Center circle radius
    show_mode = 1,     -- 1: One-time mode, 2: Hold mode
    sectors = {}       -- Sector configurations
}

-- Initialize default sectors
for i = 1, config.sector_count do
    config.sectors[i] = {
        name = "Sector " .. i,
        items = {
            {label = "Action " .. i .. "-1", action = "", type = "action"},
            {label = "Action " .. i .. "-2", action = "", type = "action"}
        }
    }
end

-- GUI state
local ctx = reaper.ImGui_CreateContext('Radial Menu')
local gui = {
    visible = false,
    mouse_x = 0,
    mouse_y = 0,
    hovered_sector = -1,
    hovered_item = -1,
    show_submenu = false,
    submenu_sector = -1
}

-- Window settings
local window_flags = reaper.ImGui_WindowFlags_NoTitleBar() |
                     reaper.ImGui_WindowFlags_NoResize() |
                     reaper.ImGui_WindowFlags_NoMove() |
                     reaper.ImGui_WindowFlags_NoScrollbar() |
                     reaper.ImGui_WindowFlags_NoCollapse()

-- Math helpers
local pi = math.pi
local function deg2rad(deg) return deg * pi / 180 end
local function rad2deg(rad) return rad * 180 / pi end

-- Calculate sector angle range
local function getSectorAngleRange(sector_index, total_sectors)
    local angle_per_sector = 360 / total_sectors
    local start_angle = (sector_index - 1) * angle_per_sector
    local end_angle = sector_index * angle_per_sector
    return deg2rad(start_angle - 90), deg2rad(end_angle - 90)  -- -90 to start from top
end

-- Check if point is in sector
local function isPointInSector(x, y, center_x, center_y, start_angle, end_angle, inner_radius, outer_radius)
    local dx = x - center_x
    local dy = y - center_y
    local distance = math.sqrt(dx * dx + dy * dy)
    
    if distance < inner_radius or distance > outer_radius then
        return false
    end
    
    local angle = math.atan(dy, dx)  -- math.atan with 2 args works like atan2 in REAPER's Lua
    -- Normalize angle to 0-2π
    if angle < 0 then angle = angle + 2 * pi end
    
    -- Normalize start and end angles
    if start_angle < 0 then start_angle = start_angle + 2 * pi end
    if end_angle < 0 then end_angle = end_angle + 2 * pi end
    
    -- Handle wrap-around
    if start_angle > end_angle then
        return angle >= start_angle or angle <= end_angle
    else
        return angle >= start_angle and angle <= end_angle
    end
end

-- Draw sector using Path API
local function drawSector(draw_list, center_x, center_y, start_angle, end_angle, inner_radius, outer_radius, color, filled)
    if not filled then return end
    
    -- Start path
    reaper.ImGui_DrawList_PathClear(draw_list)
    
    -- Draw outer arc
    reaper.ImGui_DrawList_PathArcTo(draw_list, center_x, center_y, outer_radius, start_angle, end_angle, 16)
    
    -- Draw line to inner arc end
    local end_x = center_x + math.cos(end_angle) * inner_radius
    local end_y = center_y + math.sin(end_angle) * inner_radius
    reaper.ImGui_DrawList_PathLineTo(draw_list, end_x, end_y)
    
    -- Draw inner arc (reverse direction)
    reaper.ImGui_DrawList_PathArcTo(draw_list, center_x, center_y, inner_radius, end_angle, start_angle, 16)
    
    -- Close path and fill
    reaper.ImGui_DrawList_PathFillConvex(draw_list, color)
end

-- Draw text on sector
local function drawSectorText(draw_list, center_x, center_y, sector_index, total_sectors, text, radius)
    local angle_per_sector = 360 / total_sectors
    local sector_center_angle = (sector_index - 0.5) * angle_per_sector - 90
    local rad = deg2rad(sector_center_angle)
    
    local text_radius = radius * 0.7
    local text_x = center_x + math.cos(rad) * text_radius
    local text_y = center_y + math.sin(rad) * text_radius
    
    -- Simple text drawing (ReaImGui doesn't have direct text drawing in draw list)
    -- We'll use ImGui text at calculated position
    return text_x, text_y, rad
end

-- Execute action
local function executeAction(action_id, action_type)
    if not action_id or action_id == "" then return end
    
    if action_type == "action" then
        local cmd_id = tonumber(action_id)
        if cmd_id and cmd_id > 0 then
            reaper.Main_OnCommand(cmd_id, 0)
        end
    elseif action_type == "fx" then
        -- TODO: Add FX loading logic
        reaper.ShowMessageBox("FX loading not yet implemented", "Info", 0)
    elseif action_type == "track_template" then
        -- TODO: Add track template loading logic
        reaper.ShowMessageBox("Track template loading not yet implemented", "Info", 0)
    end
end

-- Main draw function
local function drawRadialMenu()
    local window_size = config.radius * 2 + 40
    local center_x = window_size / 2
    local center_y = window_size / 2
    
    -- Set window size and position
    reaper.ImGui_SetNextWindowSize(ctx, window_size, window_size, reaper.ImGui_Cond_Once())
    
    -- Position at mouse cursor
    local mouse_x, mouse_y = reaper.GetMousePosition()
    local screen_x, screen_y = reaper.ImGui_PointConvertNative(ctx, mouse_x, mouse_y, false)
    reaper.ImGui_SetNextWindowPos(ctx, screen_x - center_x, screen_y - center_y, reaper.ImGui_Cond_Once())
    
    -- Begin window
    local visible, open = reaper.ImGui_Begin(ctx, "Radial Menu", true, window_flags)
    if not visible then
        -- If window is not visible, don't call End (Begin already failed)
        return open
    end
    
    local draw_list = reaper.ImGui_GetWindowDrawList(ctx)
    local window_pos = {reaper.ImGui_GetWindowPos(ctx)}
    local window_draw_x = window_pos[1]
    local window_draw_y = window_pos[2]
    
    -- Get mouse position relative to window
    local mouse_pos = {reaper.ImGui_GetMousePos(ctx)}
    local rel_mouse_x = mouse_pos[1] - window_draw_x - center_x
    local rel_mouse_y = mouse_pos[2] - window_draw_y - center_y
    
    -- Colors (format: 0xAARRGGBB)
    local color_bg = 0xFF1E1E1E          -- Dark gray background
    local color_sector = 0xFF3C3C3C      -- Gray sector
    local color_sector_hover = 0xFF505078 -- Blue-gray hover
    local color_center = 0xFF282828      -- Dark center
    local color_text = 0xFFFFFFFF        -- White text
    
    -- Draw background circle
    reaper.ImGui_DrawList_AddCircleFilled(draw_list, window_draw_x + center_x, window_draw_y + center_y, 
                                         config.radius + 5, color_bg, 32)
    
    -- Draw sectors
    gui.hovered_sector = -1
    for i = 1, config.sector_count do
        local start_angle, end_angle = getSectorAngleRange(i, config.sector_count)
        local is_hovered = isPointInSector(rel_mouse_x, rel_mouse_y, 0, 0, 
                                          start_angle, end_angle, config.center_radius, config.radius)
        
        if is_hovered then
            gui.hovered_sector = i
        end
        
        local sector_color = (is_hovered and gui.hovered_sector == i) and color_sector_hover or color_sector
        drawSector(draw_list, window_draw_x + center_x, window_draw_y + center_y,
                  start_angle, end_angle, config.center_radius, config.radius, sector_color, true)
    end
    
    -- Draw center circle
    reaper.ImGui_DrawList_AddCircleFilled(draw_list, window_draw_x + center_x, window_draw_y + center_y,
                                         config.center_radius, color_center, 32)
    
    -- Draw sector labels
    reaper.ImGui_SetCursorPos(ctx, 0, 0)
    for i = 1, config.sector_count do
        local text_x, text_y, angle = drawSectorText(draw_list, window_draw_x + center_x, window_draw_y + center_y,
                                                     i, config.sector_count, config.sectors[i].name, config.radius)
        -- Note: ReaImGui text drawing in draw list is limited, using window text instead
        reaper.ImGui_SetCursorPos(ctx, text_x - window_draw_x - 20, text_y - window_draw_y - 8)
        reaper.ImGui_Text(ctx, config.sectors[i].name)
    end
    
    -- Store window position before ending
    local main_window_x = window_draw_x
    local main_window_y = window_draw_y
    
    -- Check for ESC key to close
    if reaper.ImGui_IsKeyPressed(ctx, reaper.ImGui_Key_Escape()) then
        gui.visible = false
    end
    
    -- Handle clicks outside main window to close
    if reaper.ImGui_IsMouseClicked(ctx, 0) then  -- Left mouse button
        -- Check if click is outside main window
        if not reaper.ImGui_IsWindowHovered(ctx) then
            gui.visible = false
        end
    end
    
    -- End main window
    reaper.ImGui_End(ctx)
    
    -- Draw submenu if hovering (as separate window, after main window is closed)
    if gui.hovered_sector > 0 and gui.hovered_sector <= config.sector_count and gui.visible then
        local sector = config.sectors[gui.hovered_sector]
        if sector and #sector.items > 0 then
            -- Calculate submenu position (to the side of the sector)
            local sector_angle = (gui.hovered_sector - 0.5) * (360 / config.sector_count) - 90
            local rad = deg2rad(sector_angle)
            local submenu_x = main_window_x + center_x + math.cos(rad) * (config.radius + 60)
            local submenu_y = main_window_y + center_y + math.sin(rad) * (config.radius + 60)
            
            -- Draw submenu background
            local submenu_width = 150
            local submenu_height = #sector.items * 30 + 10
            reaper.ImGui_SetNextWindowPos(ctx, submenu_x - submenu_width / 2, submenu_y - submenu_height / 2, 
                                         reaper.ImGui_Cond_Always())
            reaper.ImGui_SetNextWindowSize(ctx, submenu_width, submenu_height, reaper.ImGui_Cond_Always())
            
            local submenu_visible, submenu_open = reaper.ImGui_Begin(ctx, "Submenu##" .. gui.hovered_sector, true,
                                                                    reaper.ImGui_WindowFlags_NoTitleBar() |
                                                                    reaper.ImGui_WindowFlags_NoResize() |
                                                                    reaper.ImGui_WindowFlags_NoMove())
            if submenu_visible then
                reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_WindowBg(), 0x404040FF)
                
                for item_idx, item in ipairs(sector.items) do
                    if reaper.ImGui_Button(ctx, item.label, -1, 25) then
                        executeAction(item.action, item.type)
                        gui.visible = false  -- Close menu after action
                    end
                end
                
                reaper.ImGui_PopStyleColor(ctx)
                reaper.ImGui_End(ctx)
            end
        end
    end
    
    return open
end

-- Main loop
local function main()
    if gui.visible then
        local open = drawRadialMenu()
        if open and gui.visible then
            reaper.defer(main)
        else
            gui.visible = false
        end
    end
end

-- Show menu
gui.visible = true
reaper.defer(main)

