--[[
  Function Loader Module
  Loads item functions from ItemFunctions directory
]]

local FunctionLoader = {}

-- Get function ID
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

-- Load item functions from directory
function FunctionLoader.loadFunctions(functions_dir, DataManager, colors)
    local loaded_functions = {}
    
    -- Default colors if not provided
    if not colors then
        colors = {
            BTN_ITEM_ON = 0x66BB6AFF,
            BTN_ITEM_OFF = 0x555555AA,
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
                    -- Force unified color for all non-custom functions
                    local btn_color = (colors and colors.BTN_ITEM_ON) or 0x0F766EFF
                    func_module.buttonColor = {
                        btn_color,
                        btn_color + 0x11111100,  -- Hovered (lighter)
                        btn_color - 0x11111100   -- Active (darker)
                    }
                    
                    table.insert(loaded_functions, func_module)
                end
            end
        end
        
        i = i + 1
    end
    
    return loaded_functions
end

-- Get function by ID
function FunctionLoader.getFunctionByID(func_id, item_functions, custom_actions, colors)
    if not func_id or func_id == "" or type(func_id) ~= "string" then
        return nil
    end
    
    -- Default colors if not provided
    if not colors then
        colors = {
            BTN_ITEM_ON = 0x0F766EFF,
            BTN_CUSTOM = 0x42A5F5AA,
        }
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
                            buttonColor = {colors.BTN_ITEM_ON, colors.BTN_ITEM_ON + 0x11111100, colors.BTN_ITEM_ON - 0x11111100},
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
                    -- Force unified color for all non-custom functions
                    local btn_color = (colors and colors.BTN_ITEM_ON) or 0x0F766EFF
                    func_copy.buttonColor = {
                        btn_color,
                        btn_color + 0x11111100,  -- Hovered (lighter)
                        btn_color - 0x11111100   -- Active (darker)
                    }
                    return func_copy
                end
            end
        end
    end
    return nil
end

-- Get all available functions (for stash)
function FunctionLoader.getAllAvailableFunctions(item_functions, custom_actions, active_functions, colors)
    -- Default colors if not provided
    if not colors then
        colors = {
            BTN_ITEM_ON = 0x0F766EFF,
            BTN_CUSTOM = 0x42A5F5AA,
        }
    end
    
    local all = {}
    
    -- Helper to get function ID
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
    
    -- Add all builtin functions
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
                    -- Force unified color for all non-custom functions
                    local btn_color = (colors and colors.BTN_ITEM_ON) or 0x0F766EFF
                    func_copy.buttonColor = {
                        btn_color,
                        btn_color + 0x11111100,  -- Hovered (lighter)
                        btn_color - 0x11111100   -- Active (darker)
                    }
                    table.insert(all, func_copy)
                end
            end
        end
    end
    
    -- Add all custom actions
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
                        buttonColor = {colors.BTN_ITEM_ON, colors.BTN_ITEM_ON + 0x11111100, colors.BTN_ITEM_ON - 0x11111100},
                        is_custom = true,
                        func_id = func_id
                    })
                end
            end
        end
    end
    
    return all
end

return FunctionLoader

