--[[
  Function Loader Module
  Loads marker functions from MarkerFunctions directory
]]

-- Constants
local DEFAULT_TYPE = "marker"

local FunctionLoader = {}

-- Load marker functions from directory
function FunctionLoader.loadFunctions(functions_dir, DataManager, colors)
    local loaded_functions = {}
    
    -- Default colors if not provided
    if not colors then
        colors = {
            BTN_MARKER_ON = 0x90A4AEFF,
            BTN_MARKER_OFF = 0x555555AA,
            BTN_REGION_ON = 0x7986CBFF,
            BTN_REGION_OFF = 0x555555AA,
        }
    end
    
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
                        func_module.type = DEFAULT_TYPE
                    end
                    
                    -- Apply theme colors based on function type
                    -- Override buttonColor from theme (unless explicitly disabled)
                    local func_type = func_module.type or DEFAULT_TYPE
                    if func_type == "marker" then
                        func_module.buttonColor = {
                            colors.BTN_MARKER_ON,
                            colors.BTN_MARKER_ON + 0x11111100,  -- Hovered (lighter)
                            colors.BTN_MARKER_ON - 0x11111100   -- Active (darker)
                        }
                    elseif func_type == "region" then
                        func_module.buttonColor = {
                            colors.BTN_REGION_ON,
                            colors.BTN_REGION_ON + 0x11111100,  -- Hovered (lighter)
                            colors.BTN_REGION_ON - 0x11111100   -- Active (darker)
                        }
                    end
                    
                    table.insert(loaded_functions, func_module)
                end
            end
        end
        
        i = i + 1
    end
    
    -- Sort by saved order if available
    local function_order = DataManager.loadFunctionOrder()
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
        local updated_order = {}
        for _, name in ipairs(function_order) do
            table.insert(updated_order, name)
        end
        for _, func in ipairs(loaded_functions) do
            if not existing_names[func.name] then
                table.insert(updated_order, func.name)
            end
        end
        DataManager.saveFunctionOrder(updated_order)
    else
        -- First time: create order from loaded functions
        local new_order = {}
        for _, func in ipairs(loaded_functions) do
            table.insert(new_order, func.name)
        end
        DataManager.saveFunctionOrder(new_order)
    end
    
    return loaded_functions
end

-- Get function by name (for layout management)
function FunctionLoader.getFunctionByName(func_name, marker_functions, custom_actions, colors)
    if not func_name or func_name == "" then
        return nil
    end
    
    -- Default colors if not provided
    if not colors then
        colors = {
            BTN_MARKER_ON = 0x90A4AEFF,
            BTN_MARKER_OFF = 0x555555AA,
            BTN_REGION_ON = 0x7986CBFF,
            BTN_REGION_OFF = 0x555555AA,
            BTN_CUSTOM = 0x42A5F5AA,
        }
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
                local action_type = action.type or DEFAULT_TYPE
                -- Use button color based on type (marker or region)
                local btn_color = colors.BTN_MARKER_ON
                if action_type == "region" then
                    btn_color = colors.BTN_REGION_ON
                end
                
                return {
                    name = action.name,
                    description = action.description or "",
                    type = action_type,
                    execute = function()
                        reaper.Main_OnCommand(action_id, 0)
                        return true, "Executed: " .. action.name
                    end,
                    buttonColor = {btn_color, btn_color + 0x11111100, btn_color - 0x11111100},
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
function FunctionLoader.getAllAvailableFunctions(marker_functions, custom_actions, active_functions, colors)
    -- Default colors if not provided
    if not colors then
        colors = {
            BTN_MARKER_ON = 0x90A4AEFF,
            BTN_MARKER_OFF = 0x555555AA,
            BTN_REGION_ON = 0x7986CBFF,
            BTN_REGION_OFF = 0x555555AA,
            BTN_CUSTOM = 0x42A5F5AA,
        }
    end
    
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
                    local action_type = action.type or DEFAULT_TYPE
                    -- Use button color based on type (marker or region)
                    local btn_color = colors.BTN_MARKER_ON
                    if action_type == "region" then
                        btn_color = colors.BTN_REGION_ON
                    end
                    
                    table.insert(all, {
                        name = action.name,
                        description = action.description or "",
                        type = action_type,
                        execute = function()
                            reaper.Main_OnCommand(action_id, 0)
                            return true, "Executed: " .. action.name
                        end,
                        buttonColor = {btn_color, btn_color + 0x11111100, btn_color - 0x11111100},
                        is_custom = true,
                        func_name = action.name
                    })
                end
            end
        end
    end
    return all
end

return FunctionLoader

