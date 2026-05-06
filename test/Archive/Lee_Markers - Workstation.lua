--[[
  REAPER Lua Script: Marker Workstation
  Description: Modular marker/region management tool
  - Dynamically loads marker/region functions from MarkerFunctions directory
  - Provides unified GUI interface for all marker/region operations
  - Filter by Marker (M) or Region (R) type
  
  Usage:
  1. Run this script to open GUI
  2. Add new functions by creating .lua files in MarkerFunctions directory
  3. Each function file should return a table with: name, description, execute, buttonColor, type
  4. type field: "marker" or "region" (defaults to "marker" if not specified)
]]

-- Check if ReaImGui is available
if not reaper.ImGui_CreateContext then
    reaper.ShowMessageBox("This script requires ReaImGui extension.\nPlease install 'ReaImGui' from Extensions > ReaPack > Browse packages", "Missing Dependency", 0)
    return
end

-- Get script directory
local script_path = debug.getinfo(1, 'S').source:match("@(.+[/\\])")
local functions_dir = script_path .. "MarkerFunctions" .. (package.config:sub(1,1) == "/" and "/" or "\\")

-- Toggle functionality: Check if script is already running
local SCRIPT_ID = "MarkerWorkstation_Running"
local CLOSE_REQUEST = "MarkerWorkstation_CloseRequest"
local is_running = reaper.GetExtState("MarkerWorkstation", SCRIPT_ID) == "1"

if is_running then
    -- Script is already running, request it to close
    reaper.SetExtState("MarkerWorkstation", CLOSE_REQUEST, "1", false)
    -- Wait a moment for the other instance to close
    reaper.defer(function()
        reaper.SetExtState("MarkerWorkstation", SCRIPT_ID, "0", false)
        reaper.SetExtState("MarkerWorkstation", CLOSE_REQUEST, "0", false)
    end)
    return
else
    -- Mark script as running
    reaper.SetExtState("MarkerWorkstation", SCRIPT_ID, "1", false)
    reaper.SetExtState("MarkerWorkstation", CLOSE_REQUEST, "0", false)
end

-- GUI variables
local ctx = reaper.ImGui_CreateContext('Marker Workstation')
local gui = {
    visible = true,
    width = 500,
    height = 500,
    x = nil,  -- Window position X (nil = use default)
    y = nil   -- Window position Y (nil = use default)
}

-- Filter state
local filter_state = {
    show_markers = true,
    show_regions = true
}

-- Tooltip state
local tooltip_timers = {}  -- Track hover time for each button
local TOOLTIP_DELAY = 0.5  -- Show tooltip after 0.5 seconds

-- Status variable
local status_message = "Ready"

-- Drag-drop state for reordering
local pending_swaps = {}  -- Pending drag-drop swaps {src_name = source_name, dst_name = destination_name}
local function_order = {}  -- Saved order of function names

-- Custom actions management
local custom_actions = {}
local editing_index = nil
local new_action = {
    name = "",
    action_id = "",
    description = "",
    type = "marker"  -- Default to "marker", can be "marker" or "region"
}

-- Layout management
local active_functions = {}  -- Functions currently in UI (with order) - stored as function names
local stash_functions = {}   -- Functions in stash area (not in UI) - stored as function names
local pending_removals = {}  -- Pending removals to stash

-- Layout presets
local layout_presets = {}  -- {name = {active = {...}, stash = {...}}}
local current_preset_name = ""
local new_preset_name = ""

-- Load window position and size from ExtState
local function loadWindowState()
    local saved_x = reaper.GetExtState("MarkerWorkstation", "WindowX")
    local saved_y = reaper.GetExtState("MarkerWorkstation", "WindowY")
    local saved_width = reaper.GetExtState("MarkerWorkstation", "WindowWidth")
    local saved_height = reaper.GetExtState("MarkerWorkstation", "WindowHeight")
    
    if saved_x ~= "" and saved_y ~= "" then
        gui.x = tonumber(saved_x)
        gui.y = tonumber(saved_y)
    end
    
    if saved_width ~= "" and saved_height ~= "" then
        local w = tonumber(saved_width)
        local h = tonumber(saved_height)
        if w and h and w > 0 and h > 0 then
            gui.width = w
            gui.height = h
        end
    end
end

-- Save window position and size to ExtState
local function saveWindowState()
    if gui.x and gui.y then
        reaper.SetExtState("MarkerWorkstation", "WindowX", tostring(gui.x), true)
        reaper.SetExtState("MarkerWorkstation", "WindowY", tostring(gui.y), true)
    end
    reaper.SetExtState("MarkerWorkstation", "WindowWidth", tostring(gui.width), true)
    reaper.SetExtState("MarkerWorkstation", "WindowHeight", tostring(gui.height), true)
end

-- Load function order from ExtState
local function loadFunctionOrder()
    function_order = {}
    local count = tonumber(reaper.GetExtState("MarkerWorkstation", "FunctionOrderCount")) or 0
    for i = 1, count do
        local func_name = reaper.GetExtState("MarkerWorkstation", "FunctionOrder_" .. i)
        if func_name and func_name ~= "" then
            table.insert(function_order, func_name)
        end
    end
end

-- Save function order to ExtState
local function saveFunctionOrder()
    reaper.SetExtState("MarkerWorkstation", "FunctionOrderCount", tostring(#function_order), true)
    for i, func_name in ipairs(function_order) do
        reaper.SetExtState("MarkerWorkstation", "FunctionOrder_" .. i, func_name, true)
    end
end

-- Initialize: Load window state
loadWindowState()
-- Initialize: Load function order
loadFunctionOrder()

-- Color scheme (inspired by UCS Translate and Rename)
local COLORS = {
    BTN_MARKER_ON  = 0x90A4AEFF,  -- Marker color (blue-gray)
    BTN_MARKER_OFF = 0x555555AA,
    BTN_REGION_ON  = 0x7986CBFF,  -- Region color (indigo)
    BTN_REGION_OFF = 0x555555AA,
    BTN_RELOAD     = 0x666666AA,
    BTN_MANAGER    = 0x42A5F5AA,
    BTN_CUSTOM     = 0x42A5F5AA,
    BTN_DELETE     = 0xFF5252AA,
    TEXT_NORMAL    = 0xEEEEEEFF,
    TEXT_DIM       = 0x888888FF,
    BG_HEADER      = 0x2A2A2AFF,
}

-- Helper function to push button style
local function PushBtnStyle(color_code)
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Button(), color_code)
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ButtonHovered(), color_code + 0x11111100)
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ButtonActive(), color_code - 0x11111100)
end

-- Load marker functions
local marker_functions = {}

local function loadMarkerFunctions()
    local loaded_functions = {}
    
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
                    -- Set default type to "marker" if not specified
                    if not func_module.type then
                        func_module.type = "marker"
                    end
                    table.insert(loaded_functions, func_module)
                end
            end
        end
        
        i = i + 1
    end
    
    -- Sort by saved order if available
    if #function_order > 0 then
        local function_index = {}
        for idx, func_name in ipairs(function_order) do
            function_index[func_name] = idx
        end
        
        table.sort(loaded_functions, function(a, b)
            local a_idx = function_index[a.name] or 999999
            local b_idx = function_index[b.name] or 999999
            return a_idx < b_idx
        end)
        
        -- Update function_order to include any new functions
        local existing_names = {}
        for _, name in ipairs(function_order) do
            existing_names[name] = true
        end
        for _, func in ipairs(loaded_functions) do
            if not existing_names[func.name] then
                table.insert(function_order, func.name)
            end
        end
    else
        -- First time: create order from loaded functions
        function_order = {}
        for _, func in ipairs(loaded_functions) do
            table.insert(function_order, func.name)
        end
        saveFunctionOrder()
    end
    
    marker_functions = loaded_functions
    
    -- Fallback: if no functions loaded
    if #marker_functions == 0 then
        status_message = "Warning: No marker functions found in MarkerFunctions directory"
    end
end

-- Initialize: Load functions
loadMarkerFunctions()

-- Function identifier system (for layout management)
local function getFunctionID(func)
    if not func or not func.name then
        return nil
    end
    if func.is_custom then
        return "custom_" .. func.name
    else
        return "builtin_" .. func.name
    end
end

-- Load layout from ExtState
local function loadLayout()
    active_functions = {}
    stash_functions = {}
    
    -- Load active functions order (stored as function names)
    local active_count = tonumber(reaper.GetExtState("MarkerWorkstation", "ActiveFunctionCount")) or 0
    for i = 1, active_count do
        local func_name = reaper.GetExtState("MarkerWorkstation", "ActiveFunction_" .. i)
        if func_name and func_name ~= "" then
            table.insert(active_functions, func_name)
        end
    end
    
    -- Load stash functions (stored as function names)
    local stash_count = tonumber(reaper.GetExtState("MarkerWorkstation", "StashFunctionCount")) or 0
    for i = 1, stash_count do
        local func_name = reaper.GetExtState("MarkerWorkstation", "StashFunction_" .. i)
        if func_name and func_name ~= "" then
            table.insert(stash_functions, func_name)
        end
    end
end

-- Save layout to ExtState
local function saveLayout()
    -- Save active functions
    reaper.SetExtState("MarkerWorkstation", "ActiveFunctionCount", tostring(#active_functions), true)
    for i, func_name in ipairs(active_functions) do
        reaper.SetExtState("MarkerWorkstation", "ActiveFunction_" .. i, func_name, true)
    end
    
    -- Save stash functions
    reaper.SetExtState("MarkerWorkstation", "StashFunctionCount", tostring(#stash_functions), true)
    for i, func_name in ipairs(stash_functions) do
        reaper.SetExtState("MarkerWorkstation", "StashFunction_" .. i, func_name, true)
    end
end

-- Load layout presets from ExtState
local function loadLayoutPresets()
    layout_presets = {}
    local preset_count = tonumber(reaper.GetExtState("MarkerWorkstation", "LayoutPresetCount")) or 0
    for i = 1, preset_count do
        local name = reaper.GetExtState("MarkerWorkstation", "LayoutPreset_" .. i .. "_Name")
        if name and name ~= "" then
            local active_count = tonumber(reaper.GetExtState("MarkerWorkstation", "LayoutPreset_" .. i .. "_ActiveCount")) or 0
            local stash_count = tonumber(reaper.GetExtState("MarkerWorkstation", "LayoutPreset_" .. i .. "_StashCount")) or 0
            local active = {}
            local stash = {}
            for j = 1, active_count do
                local func_name = reaper.GetExtState("MarkerWorkstation", "LayoutPreset_" .. i .. "_Active_" .. j)
                if func_name and func_name ~= "" then
                    table.insert(active, func_name)
                end
            end
            for j = 1, stash_count do
                local func_name = reaper.GetExtState("MarkerWorkstation", "LayoutPreset_" .. i .. "_Stash_" .. j)
                if func_name and func_name ~= "" then
                    table.insert(stash, func_name)
                end
            end
            layout_presets[name] = {active = active, stash = stash}
        end
    end
end

-- Save layout presets to ExtState
local function saveLayoutPresets()
    local preset_names = {}
    for name, _ in pairs(layout_presets) do
        table.insert(preset_names, name)
    end
    table.sort(preset_names)
    
    reaper.SetExtState("MarkerWorkstation", "LayoutPresetCount", tostring(#preset_names), true)
    for i, name in ipairs(preset_names) do
        local preset = layout_presets[name]
        reaper.SetExtState("MarkerWorkstation", "LayoutPreset_" .. i .. "_Name", name, true)
        reaper.SetExtState("MarkerWorkstation", "LayoutPreset_" .. i .. "_ActiveCount", tostring(#preset.active), true)
        reaper.SetExtState("MarkerWorkstation", "LayoutPreset_" .. i .. "_StashCount", tostring(#preset.stash), true)
        for j, func_name in ipairs(preset.active) do
            reaper.SetExtState("MarkerWorkstation", "LayoutPreset_" .. i .. "_Active_" .. j, func_name, true)
        end
        for j, func_name in ipairs(preset.stash) do
            reaper.SetExtState("MarkerWorkstation", "LayoutPreset_" .. i .. "_Stash_" .. j, func_name, true)
        end
    end
end

-- Apply a layout preset
local function applyLayoutPreset(preset_name)
    if layout_presets[preset_name] then
        local preset = layout_presets[preset_name]
        active_functions = {}
        stash_functions = {}
        for _, func_name in ipairs(preset.active) do
            table.insert(active_functions, func_name)
        end
        for _, func_name in ipairs(preset.stash) do
            table.insert(stash_functions, func_name)
        end
        saveLayout()
        current_preset_name = preset_name
    end
end

-- Save current layout as preset
local function saveCurrentLayoutAsPreset(preset_name)
    if preset_name and preset_name ~= "" then
        local active_copy = {}
        local stash_copy = {}
        for _, func_name in ipairs(active_functions) do
            table.insert(active_copy, func_name)
        end
        for _, func_name in ipairs(stash_functions) do
            table.insert(stash_copy, func_name)
        end
        layout_presets[preset_name] = {active = active_copy, stash = stash_copy}
        saveLayoutPresets()
        current_preset_name = preset_name
        new_preset_name = ""
    end
end

-- Delete a layout preset
local function deleteLayoutPreset(preset_name)
    if layout_presets[preset_name] then
        layout_presets[preset_name] = nil
        saveLayoutPresets()
        if current_preset_name == preset_name then
            current_preset_name = ""
        end
    end
end

-- Load custom actions from ExtState
local function loadCustomActions()
    custom_actions = {}
    local count = tonumber(reaper.GetExtState("MarkerWorkstation", "CustomActionCount")) or 0
    for i = 1, count do
        local name = reaper.GetExtState("MarkerWorkstation", "CustomAction_" .. i .. "_Name")
        local action_id = reaper.GetExtState("MarkerWorkstation", "CustomAction_" .. i .. "_ID")
        local description = reaper.GetExtState("MarkerWorkstation", "CustomAction_" .. i .. "_Description")
        local action_type = reaper.GetExtState("MarkerWorkstation", "CustomAction_" .. i .. "_Type")
        if name ~= "" and action_id ~= "" then
            table.insert(custom_actions, {
                name = name,
                action_id = action_id,
                description = description or "",
                type = (action_type == "" or action_type == nil) and "marker" or action_type
            })
        end
    end
end

-- Save custom actions to ExtState
local function saveCustomActions()
    reaper.SetExtState("MarkerWorkstation", "CustomActionCount", tostring(#custom_actions), true)
    for i, action in ipairs(custom_actions) do
        reaper.SetExtState("MarkerWorkstation", "CustomAction_" .. i .. "_Name", action.name, true)
        reaper.SetExtState("MarkerWorkstation", "CustomAction_" .. i .. "_ID", action.action_id, true)
        reaper.SetExtState("MarkerWorkstation", "CustomAction_" .. i .. "_Description", action.description or "", true)
        reaper.SetExtState("MarkerWorkstation", "CustomAction_" .. i .. "_Type", action.type or "marker", true)
    end
end

-- Validate and convert action ID
local function validateActionID(action_id_str)
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

-- Initialize layout (first time setup)
local function initializeLayout()
    if #active_functions == 0 then
        -- First time: add all functions to active
        for _, func in ipairs(marker_functions) do
            if func and func.name then
                local already_added = false
                for _, active_name in ipairs(active_functions) do
                    if active_name == func.name then
                        already_added = true
                        break
                    end
                end
                if not already_added then
                    table.insert(active_functions, func.name)
                end
            end
        end
        -- Add custom actions
        for _, action in ipairs(custom_actions) do
            if action and action.name and action.action_id then
                local action_id = tonumber(action.action_id)
                if action_id then
                    local already_added = false
                    for _, active_name in ipairs(active_functions) do
                        if active_name == action.name then
                            already_added = true
                            break
                        end
                    end
                    if not already_added then
                        table.insert(active_functions, action.name)
                    end
                end
            end
        end
        saveLayout()
    end
end

-- Get function by name (for layout management)
local function getFunctionByName(func_name)
    if not func_name or func_name == "" then
        return nil
    end
    
    -- Check if it's a custom action
    for _, action in ipairs(custom_actions) do
        if action and action.name == func_name then
            local action_id = tonumber(action.action_id)
            -- Also try named command lookup if number conversion fails
            if not action_id then
                action_id = reaper.NamedCommandLookup(action.action_id)
            end
            if action_id and action_id > 0 then
                return {
                    name = action.name,
                    description = action.description or "",
                    type = action.type or "marker",
                    execute = function()
                        reaper.Main_OnCommand(action_id, 0)
                        return true, "Executed: " .. action.name
                    end,
                    buttonColor = {COLORS.BTN_CUSTOM, COLORS.BTN_CUSTOM + 0x11111100, COLORS.BTN_CUSTOM - 0x11111100},
                    is_custom = true,
                    func_name = func_name
                }
            end
        end
    end
    
    -- Check builtin functions
    for _, func in ipairs(marker_functions) do
        if func and func.name == func_name then
            local func_copy = {}
            for k, v in pairs(func) do
                func_copy[k] = v
            end
            func_copy.func_name = func_name
            return func_copy
        end
    end
    
    return nil
end

-- Get all available functions (for stash)
local function getAllAvailableFunctions()
    local all = {}
    -- Add all builtin functions
    for _, func in ipairs(marker_functions) do
        if func and func.name then
            -- Check if not in active
            local in_active = false
            for _, active_name in ipairs(active_functions) do
                if active_name == func.name then
                    in_active = true
                    break
                end
            end
            if not in_active then
                local func_copy = {}
                for k, v in pairs(func) do
                    func_copy[k] = v
                end
                func_copy.func_name = func.name
                table.insert(all, func_copy)
            end
        end
    end
    -- Add all custom actions
    for _, action in ipairs(custom_actions) do
        if action and action.name and action.action_id then
            local action_id = tonumber(action.action_id)
            if action_id then
                -- Check if not in active
                local in_active = false
                for _, active_name in ipairs(active_functions) do
                    if active_name == action.name then
                        in_active = true
                        break
                    end
                end
                if not in_active then
                    table.insert(all, {
                        name = action.name,
                        description = action.description or "",
                        type = action.type or "marker",
                        execute = function()
                            reaper.Main_OnCommand(action_id, 0)
                            return true, "Executed: " .. action.name
                        end,
                        buttonColor = {COLORS.BTN_CUSTOM, COLORS.BTN_CUSTOM + 0x11111100, COLORS.BTN_CUSTOM - 0x11111100},
                        is_custom = true,
                        func_name = action.name
                    })
                end
            end
        end
    end
    return all
end

-- Initialize: Load custom actions
loadCustomActions()

-- Initialize: Load layout
loadLayout()

-- Initialize: Load layout presets
loadLayoutPresets()

-- Initialize layout after loading functions and custom actions
initializeLayout()

-- Get brief tooltip description for a function
local function getTooltipText(func)
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

-- GUI main loop
local function main_loop()
    -- Check for close request (toggle functionality)
    if reaper.GetExtState("MarkerWorkstation", CLOSE_REQUEST) == "1" then
        gui.visible = false
        reaper.SetExtState("MarkerWorkstation", SCRIPT_ID, "0", false)
        reaper.SetExtState("MarkerWorkstation", CLOSE_REQUEST, "0", false)
        saveWindowState()
        return
    end
    
    reaper.ImGui_PushStyleVar(ctx, reaper.ImGui_StyleVar_WindowPadding(), 10, 10)
    reaper.ImGui_PushStyleVar(ctx, reaper.ImGui_StyleVar_ItemSpacing(), 6, 6)
    
    -- Set window position if saved
    if gui.x and gui.y then
        reaper.ImGui_SetNextWindowPos(ctx, gui.x, gui.y, reaper.ImGui_Cond_FirstUseEver())
    end
    
    -- Set window size
    reaper.ImGui_SetNextWindowSize(ctx, gui.width, gui.height, reaper.ImGui_Cond_FirstUseEver())
    
    -- Begin window with no special flags (allows dragging by default)
    local visible, open = reaper.ImGui_Begin(ctx, 'Marker/Region Workstation', true, reaper.ImGui_WindowFlags_None())
    
    if visible then
        -- Update window position and size (only track, save on close)
        local win_x, win_y = reaper.ImGui_GetWindowPos(ctx)
        local win_width, win_height = reaper.ImGui_GetWindowSize(ctx)
        
        if win_x and win_y then
            gui.x = win_x
            gui.y = win_y
        end
        if win_width and win_height and win_width > 0 and win_height > 0 then
            gui.width = win_width
            gui.height = win_height
        end
        
        -- Header: Title and action buttons
        reaper.ImGui_TextColored(ctx, COLORS.TEXT_NORMAL, "Marker/Region Workstation")
        reaper.ImGui_SameLine(ctx)
        reaper.ImGui_TextDisabled(ctx, string.format("(%d functions)", #marker_functions))
        
        reaper.ImGui_Separator(ctx)
        
        -- Top toolbar: Action buttons
        PushBtnStyle(COLORS.BTN_RELOAD)
        if reaper.ImGui_Button(ctx, " Reload ") then
            loadMarkerFunctions()
            status_message = string.format("Reloaded %d function(s)", #marker_functions)
        end
        reaper.ImGui_PopStyleColor(ctx, 3)
        reaper.ImGui_SameLine(ctx)
        
        PushBtnStyle(COLORS.BTN_MANAGER)
        if reaper.ImGui_Button(ctx, " Manager ") then
            reaper.Main_OnCommand(40326, 0)  -- View: Show region/marker manager window
            status_message = "Opened Region/Marker Manager"
        end
        reaper.ImGui_PopStyleColor(ctx, 3)
        
        reaper.ImGui_Separator(ctx)
        
        -- Filter section
        reaper.ImGui_Text(ctx, "Filter:")
        reaper.ImGui_SameLine(ctx)
        
        -- Marker filter button
        local marker_btn_col = filter_state.show_markers and COLORS.BTN_MARKER_ON or COLORS.BTN_MARKER_OFF
        PushBtnStyle(marker_btn_col)
        if reaper.ImGui_Button(ctx, " M ") then
            filter_state.show_markers = not filter_state.show_markers
        end
        reaper.ImGui_PopStyleColor(ctx, 3)
        reaper.ImGui_SameLine(ctx)
        
        -- Region filter button
        local region_btn_col = filter_state.show_regions and COLORS.BTN_REGION_ON or COLORS.BTN_REGION_OFF
        PushBtnStyle(region_btn_col)
        if reaper.ImGui_Button(ctx, " R ") then
            filter_state.show_regions = not filter_state.show_regions
        end
        reaper.ImGui_PopStyleColor(ctx, 3)
        
        reaper.ImGui_Separator(ctx)
        
        -- Tab bar
        if reaper.ImGui_BeginTabBar(ctx, "MainTabs") then
            -- Functions Tab
            if reaper.ImGui_BeginTabItem(ctx, " Functions ") then
                -- Process pending operations
                for _, swap in ipairs(pending_swaps) do
                    local src_name = swap.src_name
                    local dst_name = swap.dst_name
                    if src_name and dst_name and src_name ~= dst_name then
                        -- Find indices in active_functions
                        local src_idx = nil
                        local dst_idx = nil
                        for i, active_name in ipairs(active_functions) do
                            if active_name == src_name then
                                src_idx = i
                            end
                            if active_name == dst_name then
                                dst_idx = i
                            end
                            if src_idx and dst_idx then break end
                        end
                        
                        if src_idx and dst_idx and src_idx ~= dst_idx then
                            -- Remove source first
                            table.remove(active_functions, src_idx)
                            -- Adjust destination index: if dst > src, dst moves left by 1 after removal
                            local adjusted_dst = dst_idx
                            if dst_idx > src_idx then
                                adjusted_dst = dst_idx - 1
                            end
                            -- Insert at adjusted position
                            table.insert(active_functions, adjusted_dst, src_name)
                            saveLayout()
                            status_message = string.format("Reordered: %s", src_name)
                        end
                    end
                end
                pending_swaps = {}
                
                for _, removal in ipairs(pending_removals) do
                    if removal > 0 and removal <= #active_functions then
                        local func_name = active_functions[removal]
                        table.remove(active_functions, removal)
                        table.insert(stash_functions, func_name)
                        saveLayout()
                    end
                end
                pending_removals = {}
                
                -- Build active functions list from active_functions names
                local all_functions = {}
                local valid_active = {}
                for _, func_name in ipairs(active_functions) do
                    if func_name and func_name ~= "" then
                        local func = getFunctionByName(func_name)
                        if func and func.name then
                            table.insert(all_functions, func)
                            table.insert(valid_active, func_name)
                        end
                    end
                end
                -- Update active_functions if some were invalid
                if #valid_active ~= #active_functions then
                    active_functions = valid_active
                    saveLayout()
                end
                
                -- Filter by type
                local filtered_funcs = {}
                for _, func in ipairs(all_functions) do
                    local func_type = func.type or "marker"
                    if (func_type == "marker" and filter_state.show_markers) or
                       (func_type == "region" and filter_state.show_regions) then
                        table.insert(filtered_funcs, func)
                    end
                end
        
        if #filtered_funcs == 0 then
            reaper.ImGui_TextColored(ctx, COLORS.TEXT_DIM, "No functions match current filter.")
            if #active_functions == 0 then
                reaper.ImGui_TextColored(ctx, COLORS.TEXT_DIM, "Drag functions from Layout tab to add them.")
            elseif #marker_functions == 0 then
                reaper.ImGui_TextColored(ctx, COLORS.TEXT_DIM, "Add .lua files to MarkerFunctions directory")
            else
                local filter_info = {}
                if not filter_state.show_markers then
                    table.insert(filter_info, "Markers")
                end
                if not filter_state.show_regions then
                    table.insert(filter_info, "Regions")
                end
                if #filter_info > 0 then
                    reaper.ImGui_TextColored(ctx, COLORS.TEXT_DIM, string.format("Tip: Click M/R buttons to show %s", table.concat(filter_info, " and ")))
                end
            end
        else
            -- Calculate button layout (adaptive to window width)
            local avail_width = reaper.ImGui_GetContentRegionAvail(ctx)
            local button_padding = 6
            local buttons_per_row = math.max(1, math.floor((avail_width + button_padding) / (200 + button_padding)))
            local button_width = (avail_width - (buttons_per_row - 1) * button_padding) / buttons_per_row
            local button_height = 45
            
            -- Use child window for scrollable area
            local footer_height = 40
            local child_flags = reaper.ImGui_ChildFlags_Border and reaper.ImGui_ChildFlags_Border() or 1
            if reaper.ImGui_BeginChild(ctx, "functions_area", 0, -footer_height, child_flags) then
                -- Drop target for entire child area (for adding from stash)
                if reaper.ImGui_BeginDragDropTarget(ctx) then
                    local rv, payload = reaper.ImGui_AcceptDragDropPayload(ctx, "FUNCTION_FROM_STASH")
                    if rv and payload and payload ~= "" then
                        local func_name_stash = payload
                        -- Remove from stash
                        for j, stash_name in ipairs(stash_functions) do
                            if stash_name == func_name_stash then
                                table.remove(stash_functions, j)
                                break
                            end
                        end
                        -- Add to active at end
                        local already_added = false
                        for _, active_name in ipairs(active_functions) do
                            if active_name == func_name_stash then
                                already_added = true
                                break
                            end
                        end
                        if not already_added then
                            table.insert(active_functions, func_name_stash)
                            saveLayout()
                        end
                    end
                    reaper.ImGui_EndDragDropTarget(ctx)
                end
                
                for i, func in ipairs(filtered_funcs) do
                    -- Find actual index in marker_functions (not filtered)
                    -- For custom actions, use a unique ID based on name
                    local actual_idx = nil
                    if func.is_custom then
                        -- For custom actions, use name as unique identifier
                        actual_idx = "custom_" .. func.name
                    else
                        -- For builtin functions, find index in marker_functions
                        for j, orig_func in ipairs(marker_functions) do
                            if orig_func.name == func.name then
                                actual_idx = j
                                break
                            end
                        end
                    end
                    
                    if actual_idx then
                        reaper.ImGui_PushID(ctx, tostring(actual_idx))
                        
                        -- Apply custom color if specified
                        if func.buttonColor then
                            if type(func.buttonColor) == "table" then
                                -- Push all three colors manually to match Pop count
                                reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Button(), func.buttonColor[1] or 0xFFFFFFFF)
                                reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ButtonHovered(), func.buttonColor[2] or 0xFFFFFFFF)
                                reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ButtonActive(), func.buttonColor[3] or 0xFFFFFFFF)
                            end
                        end
                        
                        -- Create button
                        if reaper.ImGui_Button(ctx, func.name, button_width, button_height) then
                            local success, message = func.execute()
                            status_message = message or (success and "Success" or "Error")
                        end
                        
                        -- Drag source for reordering (use function name instead of index)
                        if reaper.ImGui_BeginDragDropSource(ctx, reaper.ImGui_DragDropFlags_None()) then
                            reaper.ImGui_SetDragDropPayload(ctx, "FUNCTION_REORDER", func.name)
                            reaper.ImGui_Text(ctx, func.name)
                            reaper.ImGui_EndDragDropSource(ctx)
                        end
                        
                        -- Drop target for reordering (use function name instead of index)
                        -- Must be called after button to register as drop target
                        if reaper.ImGui_BeginDragDropTarget(ctx) then
                            local rv, payload = reaper.ImGui_AcceptDragDropPayload(ctx, "FUNCTION_REORDER")
                            if rv and payload and payload ~= "" then
                                local src_name = payload
                                if src_name ~= func.name then
                                    table.insert(pending_swaps, {src_name = src_name, dst_name = func.name})
                                end
                            end
                            -- Also accept from stash
                            local rv2, payload2 = reaper.ImGui_AcceptDragDropPayload(ctx, "FUNCTION_FROM_STASH")
                            if rv2 and payload2 and payload2 ~= "" then
                                local func_name_stash = payload2
                                -- Find the position of current func in active_functions
                                local current_pos = nil
                                for j, active_name in ipairs(active_functions) do
                                    if active_name == func.name then
                                        current_pos = j
                                        break
                                    end
                                end
                                if current_pos then
                                    -- Remove from stash
                                    for j, stash_name in ipairs(stash_functions) do
                                        if stash_name == func_name_stash then
                                            table.remove(stash_functions, j)
                                            break
                                        end
                                    end
                                    -- Check if not already in active
                                    local already_added = false
                                    for _, active_name in ipairs(active_functions) do
                                        if active_name == func_name_stash then
                                            already_added = true
                                            break
                                        end
                                    end
                                    if not already_added then
                                        -- Add to active at this position
                                        table.insert(active_functions, current_pos, func_name_stash)
                                        saveLayout()
                                    end
                                end
                            end
                            reaper.ImGui_EndDragDropTarget(ctx)
                        end
                        
                        -- Tooltip: Show brief description after hover delay
                        local button_id = func.name  -- Use function name as unique ID
                        if reaper.ImGui_IsItemHovered(ctx) then
                            local current_time = reaper.time_precise()
                            
                            -- Initialize timer if not exists
                            if not tooltip_timers[button_id] then
                                tooltip_timers[button_id] = current_time
                            end
                            
                            -- Check if delay has passed
                            if current_time - tooltip_timers[button_id] >= TOOLTIP_DELAY then
                                if reaper.ImGui_BeginTooltip(ctx) then
                                    reaper.ImGui_Text(ctx, getTooltipText(func))
                                    reaper.ImGui_EndTooltip(ctx)
                                end
                            end
                        else
                            -- Reset timer when not hovering
                            tooltip_timers[button_id] = nil
                        end
                        
                        -- Pop colors if applied (must match Push count)
                        if func.buttonColor and type(func.buttonColor) == "table" then
                            reaper.ImGui_PopStyleColor(ctx, 3)
                        end
                        
                        reaper.ImGui_PopID(ctx)
                    end
                    
                    -- Same line for next button (if not last in row)
                    if i % buttons_per_row ~= 0 and i < #filtered_funcs then
                        reaper.ImGui_SameLine(ctx)
                    end
                end
                reaper.ImGui_EndChild(ctx)
            end
        end
                
                reaper.ImGui_EndTabItem(ctx)
            end
            
            -- Custom Actions Manager Tab
            if reaper.ImGui_BeginTabItem(ctx, " Custom Actions ") then
                -- Make entire tab content scrollable
                local child_flags = reaper.ImGui_ChildFlags_Border and reaper.ImGui_ChildFlags_Border() or 1
                if reaper.ImGui_BeginChild(ctx, "custom_actions_scroll", 0, 0, child_flags) then
                    reaper.ImGui_TextColored(ctx, COLORS.TEXT_NORMAL, "Custom REAPER Actions Manager")
                    reaper.ImGui_Separator(ctx)
                    
                    -- Add/Edit form
                    reaper.ImGui_Text(ctx, "Button Name:")
                    local name_buf = new_action.name or ""
                    local name_changed, name_value = reaper.ImGui_InputText(ctx, "##name", name_buf)
                    if name_changed then
                        new_action.name = name_value
                    end
                    
                    reaper.ImGui_Text(ctx, "Action ID:")
                    local id_buf = new_action.action_id or ""
                    local id_changed, id_value = reaper.ImGui_InputText(ctx, "##action_id", id_buf)
                    if id_changed then
                        new_action.action_id = id_value
                    end
                    
                    reaper.ImGui_Text(ctx, "Tooltip (optional):")
                    local desc_buf = new_action.description or ""
                    local desc_changed, desc_value = reaper.ImGui_InputText(ctx, "##description", desc_buf)
                    if desc_changed then
                        new_action.description = desc_value
                    end
                    
                    -- Type selection (Marker/Region)
                    reaper.ImGui_Text(ctx, "Type:")
                    reaper.ImGui_SameLine(ctx)
                    local type_options = {"marker", "region"}
                    local current_type_idx = 1
                    if new_action.type == "region" then
                        current_type_idx = 2
                    end
                    if reaper.ImGui_BeginCombo(ctx, "##type_combo", type_options[current_type_idx]) then
                        if reaper.ImGui_Selectable(ctx, "marker", new_action.type == "marker") then
                            new_action.type = "marker"
                        end
                        if reaper.ImGui_Selectable(ctx, "region", new_action.type == "region") then
                            new_action.type = "region"
                        end
                        reaper.ImGui_EndCombo(ctx)
                    end
                    
                    reaper.ImGui_TextColored(ctx, COLORS.TEXT_DIM, "Tip: Enter Action ID (number) or command name. Tooltip will show on hover.")
                    reaper.ImGui_Spacing(ctx)
                    
                    -- Add/Update button
                    local btn_text = editing_index and " Update " or " Add "
                    PushBtnStyle(COLORS.BTN_CUSTOM)
                    if reaper.ImGui_Button(ctx, btn_text) then
                        if new_action.name ~= "" and new_action.action_id ~= "" then
                            local action_id = validateActionID(new_action.action_id)
                            if action_id then
                                if editing_index then
                                    -- Update existing
                                    custom_actions[editing_index].name = new_action.name
                                    custom_actions[editing_index].action_id = tostring(action_id)
                                    custom_actions[editing_index].description = new_action.description or ""
                                    custom_actions[editing_index].type = new_action.type or "marker"
                                    editing_index = nil
                                    status_message = "Updated custom action"
                                else
                                    -- Add new
                                    table.insert(custom_actions, {
                                        name = new_action.name,
                                        action_id = tostring(action_id),
                                        description = new_action.description or "",
                                        type = new_action.type or "marker"
                                    })
                                    -- Add to active functions automatically
                                    local already_added = false
                                    for _, active_name in ipairs(active_functions) do
                                        if active_name == new_action.name then
                                            already_added = true
                                            break
                                        end
                                    end
                                    if not already_added then
                                        table.insert(active_functions, new_action.name)
                                        saveLayout()
                                        status_message = string.format("Added custom action: %s [%s]", new_action.name, (new_action.type or "marker"):upper())
                                    else
                                        status_message = string.format("Custom action '%s' already in UI", new_action.name)
                                    end
                                end
                                saveCustomActions()
                                new_action.name = ""
                                new_action.action_id = ""
                                new_action.description = ""
                                new_action.type = "marker"
                            else
                                status_message = "Error: Invalid Action ID"
                            end
                        else
                            status_message = "Error: Name and Action ID required"
                        end
                    end
                    reaper.ImGui_PopStyleColor(ctx, 3)
                    
                    if editing_index then
                        reaper.ImGui_SameLine(ctx)
                        if reaper.ImGui_Button(ctx, " Cancel ") then
                            editing_index = nil
                            new_action.name = ""
                            new_action.action_id = ""
                            new_action.description = ""
                            new_action.type = "marker"
                        end
                    end
                    
                    reaper.ImGui_Separator(ctx)
                    reaper.ImGui_Spacing(ctx)
                    
                    -- List of custom actions
                    reaper.ImGui_Text(ctx, "Custom Actions:")
                    if #custom_actions == 0 then
                        reaper.ImGui_TextColored(ctx, COLORS.TEXT_DIM, "No custom actions added yet")
                    else
                        for i, action in ipairs(custom_actions) do
                            reaper.ImGui_PushID(ctx, i)
                            local action_type = action.type or "marker"
                            local type_display = action_type == "region" and "[R]" or "[M]"
                            local type_color = action_type == "region" and COLORS.BTN_REGION_ON or COLORS.BTN_MARKER_ON
                            reaper.ImGui_Text(ctx, string.format("%d. %s", i, action.name))
                            reaper.ImGui_SameLine(ctx)
                            reaper.ImGui_TextColored(ctx, type_color, type_display)
                            reaper.ImGui_SameLine(ctx)
                            reaper.ImGui_Text(ctx, string.format("(ID: %s)", action.action_id))
                            if action.description and action.description ~= "" then
                                reaper.ImGui_SameLine(ctx)
                                reaper.ImGui_TextColored(ctx, COLORS.TEXT_DIM, " - " .. action.description)
                            end
                            reaper.ImGui_SameLine(ctx)
                            
                            -- Edit button
                            PushBtnStyle(COLORS.BTN_CUSTOM)
                            if reaper.ImGui_Button(ctx, " Edit ") then
                                editing_index = i
                                new_action.name = action.name
                                new_action.action_id = action.action_id
                                new_action.description = action.description or ""
                                new_action.type = action.type or "marker"
                            end
                            reaper.ImGui_PopStyleColor(ctx, 3)
                            reaper.ImGui_SameLine(ctx)
                            
                            -- Delete button
                            PushBtnStyle(COLORS.BTN_DELETE)
                            if reaper.ImGui_Button(ctx, " Del ") then
                                -- Remove from active functions if exists
                                for j, active_name in ipairs(active_functions) do
                                    if active_name == action.name then
                                        table.remove(active_functions, j)
                                        break
                                    end
                                end
                                -- Remove from stash if exists
                                for j, stash_name in ipairs(stash_functions) do
                                    if stash_name == action.name then
                                        table.remove(stash_functions, j)
                                        break
                                    end
                                end
                                table.remove(custom_actions, i)
                                saveCustomActions()
                                saveLayout()
                                status_message = "Deleted custom action"
                            end
                            reaper.ImGui_PopStyleColor(ctx, 3)
                            
                            reaper.ImGui_PopID(ctx)
                        end
                    end
                    
                    reaper.ImGui_EndChild(ctx)
                end
                
                reaper.ImGui_EndTabItem(ctx)
            end
            
            -- Layout Manager Tab
            if reaper.ImGui_BeginTabItem(ctx, " Layout ") then
                reaper.ImGui_TextColored(ctx, COLORS.TEXT_NORMAL, "Layout Manager")
                reaper.ImGui_TextColored(ctx, COLORS.TEXT_DIM, "Use Functions tab for drag-drop reordering")
                reaper.ImGui_Separator(ctx)
                
                -- Layout Presets Section
                reaper.ImGui_Text(ctx, "Layout Presets:")
                reaper.ImGui_SameLine(ctx)
                
                -- Preset dropdown/combo
                local preset_names = {}
                for name, _ in pairs(layout_presets) do
                    table.insert(preset_names, name)
                end
                table.sort(preset_names)
                
                local preview_value = current_preset_name
                if preview_value == "" then
                    preview_value = "(None)"
                end
                
                if reaper.ImGui_BeginCombo(ctx, "##preset_combo", preview_value) then
                    if reaper.ImGui_Selectable(ctx, "(None)", current_preset_name == "") then
                        current_preset_name = ""
                    end
                    for _, name in ipairs(preset_names) do
                        if reaper.ImGui_Selectable(ctx, name, current_preset_name == name) then
                            applyLayoutPreset(name)
                        end
                    end
                    reaper.ImGui_EndCombo(ctx)
                end
                
                reaper.ImGui_SameLine(ctx)
                -- Save as preset button
                PushBtnStyle(COLORS.BTN_CUSTOM)
                if reaper.ImGui_Button(ctx, " Save As ") then
                    if new_preset_name and new_preset_name ~= "" then
                        saveCurrentLayoutAsPreset(new_preset_name)
                        status_message = "Saved layout as preset: " .. new_preset_name
                    else
                        status_message = "Please enter a preset name"
                    end
                end
                reaper.ImGui_PopStyleColor(ctx, 3)
                
                reaper.ImGui_SameLine(ctx)
                -- Delete preset button
                if current_preset_name and current_preset_name ~= "" then
                    PushBtnStyle(COLORS.BTN_DELETE)
                    if reaper.ImGui_Button(ctx, " Delete ") then
                        deleteLayoutPreset(current_preset_name)
                        status_message = "Deleted preset: " .. current_preset_name
                    end
                    reaper.ImGui_PopStyleColor(ctx, 3)
                end
                
                reaper.ImGui_Text(ctx, "Preset Name:")
                reaper.ImGui_SameLine(ctx)
                local name_buf = new_preset_name or ""
                local name_changed, name_value = reaper.ImGui_InputText(ctx, "##new_preset_name", name_buf)
                if name_changed then
                    new_preset_name = name_value
                end
                
                reaper.ImGui_Separator(ctx)
                
                -- Active Functions Section
                reaper.ImGui_Text(ctx, "Active Functions (in UI):")
                reaper.ImGui_TextColored(ctx, COLORS.TEXT_DIM, "Use Functions tab for drag-drop reordering")
                local child_flags = reaper.ImGui_ChildFlags_Border and reaper.ImGui_ChildFlags_Border() or 1
                if reaper.ImGui_BeginChild(ctx, "active_functions", 0, 200, child_flags) then
                    -- Clean up invalid function names first
                    local valid_active = {}
                    for _, func_name in ipairs(active_functions) do
                        if func_name and func_name ~= "" then
                            local func = getFunctionByName(func_name)
                            if func and func.name then
                                table.insert(valid_active, func_name)
                            end
                        end
                    end
                    if #valid_active ~= #active_functions then
                        active_functions = valid_active
                        saveLayout()
                    end
                    
                    -- Use a copy of active_functions for iteration to avoid index issues
                    local active_list = {}
                    for _, func_name in ipairs(active_functions) do
                        table.insert(active_list, func_name)
                    end
                    
                    for display_idx, func_name in ipairs(active_list) do
                        if func_name and func_name ~= "" then
                            local func = getFunctionByName(func_name)
                            if func and func.name then
                                -- Find actual index in active_functions
                                local actual_idx = nil
                                for j, active_name in ipairs(active_functions) do
                                    if active_name == func_name then
                                        actual_idx = j
                                        break
                                    end
                                end
                                
                                if actual_idx then
                                    reaper.ImGui_PushID(ctx, "active_" .. actual_idx)
                                    
                                    -- Simple text display (no drag-drop in Layout tab)
                                    reaper.ImGui_Text(ctx, string.format("%d. %s", display_idx, func.name))
                                    
                                    -- Button on the same line
                                    reaper.ImGui_SameLine(ctx)
                                    PushBtnStyle(COLORS.BTN_DELETE)
                                    if reaper.ImGui_Button(ctx, " To Stash ") then
                                        -- Find and remove by name to avoid index issues
                                        for j, active_name in ipairs(active_functions) do
                                            if active_name == func_name then
                                                table.remove(active_functions, j)
                                                table.insert(stash_functions, func_name)
                                                saveLayout()
                                                status_message = "Moved " .. func.name .. " to stash"
                                                break
                                            end
                                        end
                                    end
                                    reaper.ImGui_PopStyleColor(ctx, 3)
                                    
                                    reaper.ImGui_PopID(ctx)
                                end
                            end
                        end
                    end
                    reaper.ImGui_EndChild(ctx)
                end
                
                reaper.ImGui_Spacing(ctx)
                
                -- Stash Section
                reaper.ImGui_Text(ctx, "Stash (Available Functions):")
                reaper.ImGui_TextColored(ctx, COLORS.TEXT_DIM, "Use 'To UI' button to add functions back")
                if reaper.ImGui_BeginChild(ctx, "stash_functions", 0, 0, child_flags) then
                    local available = getAllAvailableFunctions()
                    if #available == 0 then
                        reaper.ImGui_TextColored(ctx, COLORS.TEXT_DIM, "All functions are in UI")
                    else
                        for i, func in ipairs(available) do
                            reaper.ImGui_PushID(ctx, "stash_" .. i)
                            
                            -- Simple text display (no drag-drop in Layout tab)
                            reaper.ImGui_Text(ctx, func.name)
                            
                            if func.is_custom then
                                reaper.ImGui_SameLine(ctx)
                                reaper.ImGui_TextColored(ctx, COLORS.BTN_CUSTOM, "[Custom]")
                            end
                            
                            reaper.ImGui_SameLine(ctx)
                            
                            -- To UI button
                            PushBtnStyle(COLORS.BTN_CUSTOM)
                            if reaper.ImGui_Button(ctx, " To UI ") then
                                local func_name = func.func_name or func.name
                                if func_name then
                                    -- Remove from stash
                                    for j, stash_name in ipairs(stash_functions) do
                                        if stash_name == func_name then
                                            table.remove(stash_functions, j)
                                            break
                                        end
                                    end
                                    -- Add to active at end
                                    table.insert(active_functions, func_name)
                                    saveLayout()
                                    status_message = "Moved " .. func.name .. " to UI"
                                end
                            end
                            reaper.ImGui_PopStyleColor(ctx, 3)
                            
                            reaper.ImGui_PopID(ctx)
                        end
                    end
                    reaper.ImGui_EndChild(ctx)
                end
                
                reaper.ImGui_EndTabItem(ctx)
            end
            
            reaper.ImGui_EndTabBar(ctx)
        end
        
        -- Footer: Status info
        reaper.ImGui_Separator(ctx)
        
        -- Status info
        reaper.ImGui_TextColored(ctx, COLORS.TEXT_DIM, "Status:")
        reaper.ImGui_SameLine(ctx)
        reaper.ImGui_TextWrapped(ctx, status_message)
        
        reaper.ImGui_End(ctx)
    end
    
    reaper.ImGui_PopStyleVar(ctx, 2)
    
    -- Save window state when closing
    if not open or not gui.visible then
        saveWindowState()
    end
    
    if open and gui.visible then
        reaper.defer(main_loop)
    else
        saveWindowState()  -- Save one more time before exiting
        -- Clear running flag when closing
        reaper.SetExtState("MarkerWorkstation", SCRIPT_ID, "0", false)
        reaper.SetExtState("MarkerWorkstation", CLOSE_REQUEST, "0", false)
        return
    end
end

-- Launch GUI
main_loop()


