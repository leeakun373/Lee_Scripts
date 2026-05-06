--[[
  REAPER Lua Script: Item Workstation
  Description: Modular item management tool
  - Dynamically loads item functions from ItemFunctions directory
  - Provides unified GUI interface for all item operations
  - Custom REAPER action support with custom button names
  
  Usage:
  1. Run this script to open GUI
  2. Add new functions by creating .lua files in ItemFunctions directory
  3. Each function file should return a table with: name, description, execute, buttonColor
  4. Use "Custom Actions" button to add REAPER actions with custom names
]]

-- Check if ReaImGui is available
if not reaper.ImGui_CreateContext then
    reaper.ShowMessageBox("This script requires ReaImGui extension.\nPlease install 'ReaImGui' from Extensions > ReaPack > Browse packages", "Missing Dependency", 0)
    return
end

-- Get script directory
local script_path = debug.getinfo(1, 'S').source:match("@(.+[/\\])")
local functions_dir = script_path .. "ItemFunctions" .. (package.config:sub(1,1) == "/" and "/" or "\\")

-- GUI variables
local ctx = reaper.ImGui_CreateContext('Item Workstation')
local gui = {
    visible = true,
    width = 500,
    height = 500
}

-- Status variable
local status_message = "Ready"

-- Tab state
local current_tab = 1  -- 1 = Functions, 2 = Custom Actions Manager

-- Tooltip state
local tooltip_timers = {}  -- Track hover time for each button
local TOOLTIP_DELAY = 0.5  -- Show tooltip after 0.5 seconds

-- Color scheme (unified with Marker Workstation)
local COLORS = {
    BTN_ITEM_ON    = 0x66BB6AFF,  -- Item color (green)
    BTN_ITEM_OFF   = 0x555555AA,
    BTN_RELOAD      = 0x666666AA,
    BTN_CUSTOM      = 0x42A5F5AA,
    BTN_DELETE      = 0xFF5252AA,
    TEXT_NORMAL     = 0xEEEEEEFF,
    TEXT_DIM        = 0x888888FF,
    BG_HEADER       = 0x2A2A2AFF,
}

-- Helper function to push button style
local function PushBtnStyle(color_code)
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Button(), color_code)
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ButtonHovered(), color_code + 0x11111100)
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ButtonActive(), color_code - 0x11111100)
end

-- Custom actions management
local custom_actions = {}
local show_custom_manager = false
local editing_index = nil
local new_action = {
    name = "",
    action_id = "",
    description = ""
}

-- Layout management
local active_functions = {}  -- Functions currently in UI (with order)
local stash_functions = {}   -- Functions in stash area (not in UI)
local pending_swaps = {}     -- Pending drag-drop swaps
local pending_removals = {}  -- Pending removals to stash
local pending_adds = {}      -- Pending adds from stash

-- Layout presets
local layout_presets = {}  -- {name = {active = {...}, stash = {...}}}
local current_preset_name = ""
local new_preset_name = ""

-- Function identifier system
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
    
    -- Load active functions order
    local active_count = tonumber(reaper.GetExtState("ItemWorkstation", "ActiveFunctionCount")) or 0
    for i = 1, active_count do
        local func_id = reaper.GetExtState("ItemWorkstation", "ActiveFunction_" .. i)
        if func_id and func_id ~= "" then
            table.insert(active_functions, func_id)
        end
    end
    
    -- Load stash functions
    local stash_count = tonumber(reaper.GetExtState("ItemWorkstation", "StashFunctionCount")) or 0
    for i = 1, stash_count do
        local func_id = reaper.GetExtState("ItemWorkstation", "StashFunction_" .. i)
        if func_id and func_id ~= "" then
            table.insert(stash_functions, func_id)
        end
    end
end

-- Save layout to ExtState
local function saveLayout()
    -- Save active functions
    reaper.SetExtState("ItemWorkstation", "ActiveFunctionCount", tostring(#active_functions), true)
    for i, func_id in ipairs(active_functions) do
        reaper.SetExtState("ItemWorkstation", "ActiveFunction_" .. i, func_id, true)
    end
    
    -- Save stash functions
    reaper.SetExtState("ItemWorkstation", "StashFunctionCount", tostring(#stash_functions), true)
    for i, func_id in ipairs(stash_functions) do
        reaper.SetExtState("ItemWorkstation", "StashFunction_" .. i, func_id, true)
    end
end

-- Load layout presets from ExtState
local function loadLayoutPresets()
    layout_presets = {}
    local preset_count = tonumber(reaper.GetExtState("ItemWorkstation", "LayoutPresetCount")) or 0
    for i = 1, preset_count do
        local name = reaper.GetExtState("ItemWorkstation", "LayoutPreset_" .. i .. "_Name")
        if name and name ~= "" then
            local active_count = tonumber(reaper.GetExtState("ItemWorkstation", "LayoutPreset_" .. i .. "_ActiveCount")) or 0
            local stash_count = tonumber(reaper.GetExtState("ItemWorkstation", "LayoutPreset_" .. i .. "_StashCount")) or 0
            local active = {}
            local stash = {}
            for j = 1, active_count do
                local func_id = reaper.GetExtState("ItemWorkstation", "LayoutPreset_" .. i .. "_Active_" .. j)
                if func_id and func_id ~= "" then
                    table.insert(active, func_id)
                end
            end
            for j = 1, stash_count do
                local func_id = reaper.GetExtState("ItemWorkstation", "LayoutPreset_" .. i .. "_Stash_" .. j)
                if func_id and func_id ~= "" then
                    table.insert(stash, func_id)
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
    
    reaper.SetExtState("ItemWorkstation", "LayoutPresetCount", tostring(#preset_names), true)
    for i, name in ipairs(preset_names) do
        local preset = layout_presets[name]
        reaper.SetExtState("ItemWorkstation", "LayoutPreset_" .. i .. "_Name", name, true)
        reaper.SetExtState("ItemWorkstation", "LayoutPreset_" .. i .. "_ActiveCount", tostring(#preset.active), true)
        reaper.SetExtState("ItemWorkstation", "LayoutPreset_" .. i .. "_StashCount", tostring(#preset.stash), true)
        for j, func_id in ipairs(preset.active) do
            reaper.SetExtState("ItemWorkstation", "LayoutPreset_" .. i .. "_Active_" .. j, func_id, true)
        end
        for j, func_id in ipairs(preset.stash) do
            reaper.SetExtState("ItemWorkstation", "LayoutPreset_" .. i .. "_Stash_" .. j, func_id, true)
        end
    end
end

-- Apply a layout preset
local function applyLayoutPreset(preset_name)
    if layout_presets[preset_name] then
        local preset = layout_presets[preset_name]
        active_functions = {}
        stash_functions = {}
        for _, func_id in ipairs(preset.active) do
            table.insert(active_functions, func_id)
        end
        for _, func_id in ipairs(preset.stash) do
            table.insert(stash_functions, func_id)
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
        for _, func_id in ipairs(active_functions) do
            table.insert(active_copy, func_id)
        end
        for _, func_id in ipairs(stash_functions) do
            table.insert(stash_copy, func_id)
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

-- Initialize layout (first time setup)
local function initializeLayout()
    if #active_functions == 0 then
        -- First time: add all functions to active
        if item_functions then
            for _, func in ipairs(item_functions) do
                if func and func.name then
                    local func_id = getFunctionID(func)
                    if func_id then
                        table.insert(active_functions, func_id)
                    end
                end
            end
        end
        if custom_actions then
            for _, action in ipairs(custom_actions) do
                if action and action.name and action.action_id then
                    local action_id = tonumber(action.action_id)
                    if action_id then
                        table.insert(active_functions, "custom_" .. action.name)
                    end
                end
            end
        end
        saveLayout()
    end
end

-- Load custom actions from ExtState
local function loadCustomActions()
    custom_actions = {}
    local count = tonumber(reaper.GetExtState("ItemWorkstation", "CustomActionCount")) or 0
    for i = 1, count do
        local name = reaper.GetExtState("ItemWorkstation", "CustomAction_" .. i .. "_Name")
        local action_id = reaper.GetExtState("ItemWorkstation", "CustomAction_" .. i .. "_ID")
        local description = reaper.GetExtState("ItemWorkstation", "CustomAction_" .. i .. "_Description")
        if name ~= "" and action_id ~= "" then
            table.insert(custom_actions, {
                name = name,
                action_id = action_id,
                description = description or ""
            })
        end
    end
end

-- Save custom actions to ExtState
local function saveCustomActions()
    reaper.SetExtState("ItemWorkstation", "CustomActionCount", tostring(#custom_actions), true)
    for i, action in ipairs(custom_actions) do
        reaper.SetExtState("ItemWorkstation", "CustomAction_" .. i .. "_Name", action.name, true)
        reaper.SetExtState("ItemWorkstation", "CustomAction_" .. i .. "_ID", action.action_id, true)
        reaper.SetExtState("ItemWorkstation", "CustomAction_" .. i .. "_Description", action.description or "", true)
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

-- Initialize: Load custom actions
loadCustomActions()

-- Initialize: Load layout
loadLayout()

-- Initialize: Load layout presets
loadLayoutPresets()

-- Load item functions
local item_functions = {}

local function loadItemFunctions()
    item_functions = {}
    
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
                    table.insert(item_functions, func_module)
                end
            end
        end
        
        i = i + 1
    end
    
    -- Fallback: if no functions loaded
    if #item_functions == 0 then
        status_message = "Warning: No item functions found in ItemFunctions directory"
    end
end

-- Initialize: Load functions
loadItemFunctions()

-- Initialize layout after loading functions
initializeLayout()

-- Get brief tooltip description for a function (Chinese tooltips)
local function getTooltipText(func)
    -- Return description if available, default to Chinese message
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

-- Get function by ID
local function getFunctionByID(func_id)
    if not func_id or func_id == "" or type(func_id) ~= "string" then
        return nil
    end
    
    -- Check if it's a custom action
    if func_id:match("^custom_") then
        local name = func_id:match("^custom_(.+)$")
        if name then
            for _, action in ipairs(custom_actions) do
                if action and action.name == name then
                    local action_id = tonumber(action.action_id)
                    if action_id then
                        return {
                            name = action.name,
                            description = action.description or "",
                            execute = function()
                                reaper.Main_OnCommand(action_id, 0)
                                return true, "Executed: " .. action.name
                            end,
                            buttonColor = {COLORS.BTN_CUSTOM, COLORS.BTN_CUSTOM + 0x11111100, COLORS.BTN_CUSTOM - 0x11111100},
                            is_custom = true,
                            func_id = func_id
                        }
                    end
                end
            end
        end
    elseif func_id:match("^builtin_") then
        local name = func_id:match("^builtin_(.+)$")
        if name then
            for _, func in ipairs(item_functions) do
                if func and func.name == name then
                    local func_copy = {}
                    for k, v in pairs(func) do
                        func_copy[k] = v
                    end
                    func_copy.func_id = func_id
                    return func_copy
                end
            end
        end
    end
    return nil
end

-- Get all available functions (for stash)
local function getAllAvailableFunctions()
    local all = {}
    -- Add all builtin functions
    if item_functions then
        for _, func in ipairs(item_functions) do
            if func and func.name then
                local func_id = getFunctionID(func)
                if func_id then
                    -- Check if not in active
                    local in_active = false
                    for _, active_id in ipairs(active_functions) do
                        if active_id == func_id then
                            in_active = true
                            break
                        end
                    end
                    if not in_active then
                        local func_copy = {}
                        for k, v in pairs(func) do
                            func_copy[k] = v
                        end
                        func_copy.func_id = func_id
                        table.insert(all, func_copy)
                    end
                end
            end
        end
    end
    -- Add all custom actions
    if custom_actions then
        for _, action in ipairs(custom_actions) do
            if action and action.name and action.action_id then
                local action_id = tonumber(action.action_id)
                if action_id then
                    local func_id = "custom_" .. action.name
                    -- Check if not in active
                    local in_active = false
                    for _, active_id in ipairs(active_functions) do
                        if active_id == func_id then
                            in_active = true
                            break
                        end
                    end
                    if not in_active then
                        table.insert(all, {
                            name = action.name,
                            description = action.description or "",
                            execute = function()
                                reaper.Main_OnCommand(action_id, 0)
                                return true, "Executed: " .. action.name
                            end,
                            buttonColor = {COLORS.BTN_CUSTOM, COLORS.BTN_CUSTOM + 0x11111100, COLORS.BTN_CUSTOM - 0x11111100},
                            is_custom = true,
                            func_id = func_id
                        })
                    end
                end
            end
        end
    end
    return all
end

-- GUI main loop
local function main_loop()
    reaper.ImGui_PushStyleVar(ctx, reaper.ImGui_StyleVar_WindowPadding(), 10, 10)
    reaper.ImGui_PushStyleVar(ctx, reaper.ImGui_StyleVar_ItemSpacing(), 6, 6)
    
    reaper.ImGui_SetNextWindowSize(ctx, gui.width, gui.height, reaper.ImGui_Cond_FirstUseEver())
    
    local visible, open = reaper.ImGui_Begin(ctx, 'Item Workstation', true, reaper.ImGui_WindowFlags_None())
    
    if visible then
        -- Fixed header area (not affected by scrolling)
        -- Header: Title and action buttons
        reaper.ImGui_TextColored(ctx, COLORS.TEXT_NORMAL, "Item Workstation")
        reaper.ImGui_SameLine(ctx)
        local total_funcs = #item_functions + #custom_actions
        reaper.ImGui_TextDisabled(ctx, string.format("(%d functions)", total_funcs))
        
        reaper.ImGui_Separator(ctx)
        
        -- Top toolbar: Action buttons
        PushBtnStyle(COLORS.BTN_RELOAD)
        if reaper.ImGui_Button(ctx, " Reload ") then
            loadItemFunctions()
            status_message = string.format("Reloaded %d function(s)", #item_functions)
        end
        reaper.ImGui_PopStyleColor(ctx, 3)
        
        reaper.ImGui_Separator(ctx)
        
        -- Tab bar (fixed, not scrolling)
        -- Scrollable content area for tab content
        local avail_width, avail_height = reaper.ImGui_GetContentRegionAvail(ctx)
        local footer_height = 35  -- Space for status bar
        local scrollable_height = avail_height - footer_height
        
        local child_flags = reaper.ImGui_ChildFlags_Border and reaper.ImGui_ChildFlags_Border() or 1
        if reaper.ImGui_BeginChild(ctx, "TabContentArea", 0, scrollable_height, child_flags) then
            if reaper.ImGui_BeginTabBar(ctx, "MainTabs") then
                -- Functions Tab
                if reaper.ImGui_BeginTabItem(ctx, " Functions ") then
                -- Process pending operations
                for _, swap in ipairs(pending_swaps) do
                    local src_idx = swap.src
                    local dst_idx = swap.dst
                    if src_idx > 0 and src_idx <= #active_functions and dst_idx > 0 and dst_idx <= #active_functions and src_idx ~= dst_idx then
                        local func_id = active_functions[src_idx]
                        if func_id then
                            -- Remove source first
                            table.remove(active_functions, src_idx)
                            -- Adjust destination index: if dst > src, dst moves left by 1 after removal
                            local adjusted_dst = dst_idx
                            if dst_idx > src_idx then
                                adjusted_dst = dst_idx - 1
                            end
                            -- Insert at adjusted position
                            table.insert(active_functions, adjusted_dst, func_id)
                            saveLayout()
                        end
                    end
                end
                pending_swaps = {}
                
                for _, removal in ipairs(pending_removals) do
                    if removal > 0 and removal <= #active_functions then
                        local func_id = active_functions[removal]
                        table.remove(active_functions, removal)
                        table.insert(stash_functions, func_id)
                        saveLayout()
                    end
                end
                pending_removals = {}
                
                for _, add in ipairs(pending_adds) do
                    local func_id = add.func_id
                    local pos = add.pos or #active_functions + 1
                    -- Remove from stash if exists
                    for i, stash_id in ipairs(stash_functions) do
                        if stash_id == func_id then
                            table.remove(stash_functions, i)
                            break
                        end
                    end
                    table.insert(active_functions, pos, func_id)
                    saveLayout()
                end
                pending_adds = {}
                
                -- Build active functions list (clean invalid IDs)
                local all_functions = {}
                local valid_active = {}
                for _, func_id in ipairs(active_functions) do
                    if func_id and func_id ~= "" then
                        local func = getFunctionByID(func_id)
                        if func and func.name then
                            table.insert(all_functions, func)
                            table.insert(valid_active, func_id)
                        end
                    end
                end
                -- Update active_functions if some were invalid
                if #valid_active ~= #active_functions then
                    active_functions = valid_active
                    saveLayout()
                end
                
                -- Drop target for adding from stash (empty area)
                if reaper.ImGui_BeginDragDropTarget(ctx) then
                    local rv, payload = reaper.ImGui_AcceptDragDropPayload(ctx, "FUNCTION_FROM_STASH")
                    if rv and payload and payload ~= "" then
                        local func_id_stash = payload
                        -- Remove from stash
                        for j, stash_id in ipairs(stash_functions) do
                            if stash_id == func_id_stash then
                                table.remove(stash_functions, j)
                                break
                            end
                        end
                        -- Add to active at end
                        table.insert(active_functions, func_id_stash)
                        saveLayout()
                    end
                    reaper.ImGui_EndDragDropTarget(ctx)
                end
                
                if #all_functions == 0 then
                    reaper.ImGui_TextColored(ctx, COLORS.TEXT_DIM, "No functions in UI. Drag functions from Layout tab to add them.")
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
                                local func_id_stash = payload
                                -- Remove from stash
                                for j, stash_id in ipairs(stash_functions) do
                                    if stash_id == func_id_stash then
                                        table.remove(stash_functions, j)
                                        break
                                    end
                                end
                                -- Add to active at end
                                table.insert(active_functions, func_id_stash)
                                saveLayout()
                            end
                            reaper.ImGui_EndDragDropTarget(ctx)
                        end
                        for display_idx, func in ipairs(all_functions) do
                            -- Find actual index in active_functions
                            local actual_idx = nil
                            for j, func_id in ipairs(active_functions) do
                                if func_id == func.func_id then
                                    actual_idx = j
                                    break
                                end
                            end
                            
                            if actual_idx then
                                reaper.ImGui_PushID(ctx, actual_idx)
                                
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
                                end
                                
                                -- Drag source for reordering
                                if reaper.ImGui_BeginDragDropSource(ctx) then
                                    reaper.ImGui_SetDragDropPayload(ctx, "FUNCTION_REORDER", tostring(actual_idx))
                                    reaper.ImGui_Text(ctx, func.name)
                                    reaper.ImGui_EndDragDropSource(ctx)
                                end
                                
                                -- Drop target for reordering
                                if reaper.ImGui_BeginDragDropTarget(ctx) then
                                    local rv, payload = reaper.ImGui_AcceptDragDropPayload(ctx, "FUNCTION_REORDER")
                                    if rv and payload then
                                        local src_idx = tonumber(payload)
                                        if src_idx and src_idx > 0 and src_idx <= #active_functions and src_idx ~= actual_idx then
                                            table.insert(pending_swaps, {src = src_idx, dst = actual_idx})
                                        end
                                    end
                                    -- Also accept from stash
                                    local rv2, payload2 = reaper.ImGui_AcceptDragDropPayload(ctx, "FUNCTION_FROM_STASH")
                                    if rv2 and payload2 then
                                        local func_id_stash = payload2
                                        if func_id_stash and func_id_stash ~= "" then
                                            -- Remove from stash
                                            for j, stash_id in ipairs(stash_functions) do
                                                if stash_id == func_id_stash then
                                                    table.remove(stash_functions, j)
                                                    break
                                                end
                                            end
                                            -- Add to active at this position
                                            if actual_idx > 0 and actual_idx <= #active_functions + 1 then
                                                table.insert(active_functions, actual_idx, func_id_stash)
                                                saveLayout()
                                            end
                                        end
                                    end
                                    reaper.ImGui_EndDragDropTarget(ctx)
                                end
                            
                                -- Tooltip: Show brief description after hover delay
                                local button_id = func.name .. (func.is_custom and "_custom" or "")
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
                                
                                -- Pop colors if applied
                                if func.buttonColor and type(func.buttonColor) == "table" then
                                    reaper.ImGui_PopStyleColor(ctx, 3)
                                end
                                
                                reaper.ImGui_PopID(ctx)
                                
                                -- Same line for next button (if not last in row)
                                if display_idx % buttons_per_row ~= 0 and display_idx < #all_functions then
                                    reaper.ImGui_SameLine(ctx)
                                end
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
                                    editing_index = nil
                                    status_message = "Updated custom action"
                                else
                                    -- Add new
                                    table.insert(custom_actions, {
                                        name = new_action.name,
                                        action_id = tostring(action_id),
                                        description = new_action.description or ""
                                    })
                                    -- Add to active functions automatically
                                    local func_id = "custom_" .. new_action.name
                                    table.insert(active_functions, func_id)
                                    saveLayout()
                                    status_message = "Added custom action"
                                end
                                saveCustomActions()
                                new_action.name = ""
                                new_action.action_id = ""
                                new_action.description = ""
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
                            reaper.ImGui_Text(ctx, string.format("%d. %s (ID: %s)", i, action.name, action.action_id))
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
                            end
                            reaper.ImGui_PopStyleColor(ctx, 3)
                            reaper.ImGui_SameLine(ctx)
                            
                            -- Delete button
                            PushBtnStyle(COLORS.BTN_DELETE)
                            if reaper.ImGui_Button(ctx, " Del ") then
                                local func_id = "custom_" .. action.name
                                -- Remove from active functions if exists
                                for j, active_id in ipairs(active_functions) do
                                    if active_id == func_id then
                                        table.remove(active_functions, j)
                                        break
                                    end
                                end
                                -- Remove from stash if exists
                                for j, stash_id in ipairs(stash_functions) do
                                    if stash_id == func_id then
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
                    -- Clean up invalid function IDs first
                    local valid_active = {}
                    for _, func_id in ipairs(active_functions) do
                        if func_id and func_id ~= "" then
                            local func = getFunctionByID(func_id)
                            if func and func.name then
                                table.insert(valid_active, func_id)
                            end
                        end
                    end
                    if #valid_active ~= #active_functions then
                        active_functions = valid_active
                        saveLayout()
                    end
                    
                    for i, func_id in ipairs(active_functions) do
                        if func_id and func_id ~= "" then
                            local func = getFunctionByID(func_id)
                            if func and func.name then
                                reaper.ImGui_PushID(ctx, "active_" .. i)
                                
                                -- Simple text display (no drag-drop in Layout tab)
                                reaper.ImGui_Text(ctx, string.format("%d. %s", i, func.name))
                                
                                -- Button on the same line
                                reaper.ImGui_SameLine(ctx)
                                PushBtnStyle(COLORS.BTN_DELETE)
                                if reaper.ImGui_Button(ctx, " To Stash ") then
                                    if i > 0 and i <= #active_functions then
                                        local func_id_to_remove = active_functions[i]
                                        if func_id_to_remove then
                                            table.remove(active_functions, i)
                                            table.insert(stash_functions, func_id_to_remove)
                                            saveLayout()
                                            status_message = "Moved " .. func.name .. " to stash"
                                        end
                                    end
                                end
                                reaper.ImGui_PopStyleColor(ctx, 3)
                                
                                reaper.ImGui_PopID(ctx)
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
                                local func_id = func.func_id
                                if func_id then
                                    -- Remove from stash
                                    for j, stash_id in ipairs(stash_functions) do
                                        if stash_id == func_id then
                                            table.remove(stash_functions, j)
                                            break
                                        end
                                    end
                                    -- Add to active at end
                                    table.insert(active_functions, func_id)
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
            reaper.ImGui_EndChild(ctx)
        end
        
        -- Fixed footer area (not affected by scrolling)
        reaper.ImGui_Separator(ctx)
        
        -- Status info
        reaper.ImGui_TextColored(ctx, COLORS.TEXT_DIM, "Status:")
        reaper.ImGui_SameLine(ctx)
        reaper.ImGui_TextWrapped(ctx, status_message)
        
        reaper.ImGui_End(ctx)
    end
    
    reaper.ImGui_PopStyleVar(ctx, 2)
    
    if open and gui.visible then
        reaper.defer(main_loop)
    else
        return
    end
end

-- Launch GUI
main_loop()

