--[[
  REAPER Lua Script: Marker Workstation (Optimized Version)
  Description: Modular marker management tool with performance optimizations
  - Reduced redraws using frame skipping
  - Conditional updates
  - Optimized ImGui usage
]]

-- Check if ReaImGui is available
if not reaper.ImGui_CreateContext then
    reaper.ShowMessageBox("This script requires ReaImGui extension.\nPlease install 'ReaImGui' from Extensions > ReaPack > Browse packages", "Missing Dependency", 0)
    return
end

-- Get script directory
local script_path = debug.getinfo(1, 'S').source:match("@(.+[/\\])")
local functions_dir = script_path .. "MarkerFunctions" .. (package.config:sub(1,1) == "/" and "/" or "\\")

-- GUI variables
local ctx = reaper.ImGui_CreateContext('Marker Workstation')
local gui = {
    visible = true,
    width = 400,
    height = 300
}

-- Performance optimization variables
local last_update_time = 0
local update_interval = 0.016  -- ~60fps (16ms per frame)
local needs_redraw = true
local last_status_message = ""

-- Status variable
local status_message = "Ready"

-- Load marker functions
local marker_functions = {}

local function loadMarkerFunctions()
    marker_functions = {}
    
    -- Rescan directory
    reaper.EnumerateFiles(functions_dir, -1)
    
    -- Try to load functions from directory
    local i = 0
    while true do
        local file = reaper.EnumerateFiles(functions_dir, i)
        if not file then break end
        
        if file:match("%.lua$") then
            local file_path = functions_dir .. file
            local success, func_module = pcall(function()
                local f = loadfile(file_path)
                if f then
                    return f()
                end
                return nil
            end)
            
            if success and func_module and type(func_module) == "table" then
                if func_module.name and func_module.execute then
                    table.insert(marker_functions, func_module)
                end
            end
        end
        
        i = i + 1
    end
    
    -- Fallback: if no functions loaded
    if #marker_functions == 0 then
        status_message = "Warning: No marker functions found in MarkerFunctions directory"
    end
    
    needs_redraw = true  -- Force redraw after reload
end

-- Initialize: Load functions
loadMarkerFunctions()

-- GUI main loop (optimized)
local function main_loop()
    local current_time = reaper.time_precise()
    
    -- Frame skipping: only update if enough time has passed or if redraw is needed
    if not needs_redraw and (current_time - last_update_time) < update_interval then
        reaper.defer(main_loop)
        return
    end
    
    last_update_time = current_time
    needs_redraw = false
    
    reaper.ImGui_SetNextWindowSize(ctx, gui.width, gui.height, reaper.ImGui_Cond_FirstUseEver())
    
    local visible, open = reaper.ImGui_Begin(ctx, 'Marker Workstation', true)
    if visible then
        -- Title
        reaper.ImGui_Text(ctx, "Marker Workstation")
        reaper.ImGui_Separator(ctx)
        
        -- Reload button and Manager button
        if reaper.ImGui_Button(ctx, "Reload Functions", 120, 25) then
            loadMarkerFunctions()
            status_message = string.format("Reloaded %d function(s)", #marker_functions)
            needs_redraw = true
        end
        
        reaper.ImGui_SameLine(ctx)
        
        -- Open Region/Marker Manager button
        if reaper.ImGui_Button(ctx, "Open Manager", 120, 25) then
            reaper.Main_OnCommand(40326, 0)  -- View: Show region/marker manager window
            status_message = "Opened Region/Marker Manager"
            needs_redraw = true
        end
        
        reaper.ImGui_Separator(ctx)
        reaper.ImGui_Spacing(ctx)
        
        -- Function buttons
        if #marker_functions == 0 then
            reaper.ImGui_Text(ctx, "No marker functions found.")
            reaper.ImGui_Text(ctx, "Add .lua files to MarkerFunctions directory")
        else
            local buttons_per_row = 2
            local button_width = 180
            local button_height = 40
            
            for i, func in ipairs(marker_functions) do
                -- Apply custom color if specified
                if func.buttonColor then
                    if type(func.buttonColor) == "table" then
                        reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Button(), func.buttonColor[1] or 0xFFFFFFFF)
                        reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ButtonHovered(), func.buttonColor[2] or 0xFFFFFFFF)
                        reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ButtonActive(), func.buttonColor[3] or 0xFFFFFFFF)
                    end
                end
                
                -- Create button
                if reaper.ImGui_Button(ctx, func.name, button_width, button_height) then
                    local success, message = func.execute()
                    status_message = message or (success and "Success" or "Error")
                    needs_redraw = true
                end
                
                -- Pop colors if applied
                if func.buttonColor then
                    reaper.ImGui_PopStyleColor(ctx, 3)
                end
                
                -- Same line for next button (if not last in row)
                if i % buttons_per_row ~= 0 and i < #marker_functions then
                    reaper.ImGui_SameLine(ctx)
                end
            end
        end
        
        reaper.ImGui_Separator(ctx)
        reaper.ImGui_Spacing(ctx)
        
        -- Status info (only update if changed)
        if status_message ~= last_status_message then
            last_status_message = status_message
            needs_redraw = true
        end
        
        reaper.ImGui_Text(ctx, "Status:")
        reaper.ImGui_TextWrapped(ctx, status_message)
        
        reaper.ImGui_Separator(ctx)
        
        -- Close button (red)
        reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Button(), 0xFF0000FF)  -- Red
        reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ButtonHovered(), 0xFF3333FF)
        reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ButtonActive(), 0xCC0000FF)
        
        if reaper.ImGui_Button(ctx, "Close", 100, 25) then
            gui.visible = false
        end
        
        reaper.ImGui_PopStyleColor(ctx, 3)
        
        reaper.ImGui_End(ctx)
    end
    
    if open and gui.visible then
        reaper.defer(main_loop)
    else
        return
    end
end

-- Launch GUI
main_loop()




