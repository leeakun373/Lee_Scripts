--[[
  REAPER Lua Script: Workstation Auto-Start Config
  Description: 配置 Workstation 自动启动
  - 使用 REAPER 内置 __startup.lua 机制
  - 每次 REAPER 启动时自动启动配置的 Workstation
  - 不需要 SWS，不需要手动设置
  
  使用方法:
  1. 运行此脚本配置要自动启动的 Workstation
  2. 勾选要自动启动的 Workstation
  3. 点击 "Save" 保存配置
  4. 重启 REAPER，Workstation 会自动启动
  
  注意：需要确保 Scripts/__startup.lua 文件存在
]]

local ext_name = "Lee_Workstation_AutoStart"
local config_key = "Workstations"

-- 自动检测可用的 Workstation 列表
local function detectWorkstations()
    local workstations = {}
    local resource_path = reaper.GetResourcePath()
    local sep = package.config:sub(1, 1)
    
    -- 定义 Workstation 搜索路径
    local search_paths = {
        {name = "Item Workstation", path = "Scripts" .. sep .. "Lee_Scripts" .. sep .. "Items" .. sep .. "ItemsWorkstation" .. sep .. "Lee_Items - Workstation.lua"},
        {name = "Marker Workstation", path = "Scripts" .. sep .. "Lee_Scripts" .. sep .. "Markers" .. sep .. "MarkersWorkstation" .. sep .. "Lee_Markers - Workstation.lua"}
    }
    
    for _, ws_info in ipairs(search_paths) do
        local full_path = resource_path .. sep .. ws_info.path
        local file = io.open(full_path, "r")
        if file then
            file:close()
            table.insert(workstations, {
                name = ws_info.name,
                script_path = ws_info.path,
                enabled = false
            })
        end
    end
    
    return workstations
end

-- 可用的 Workstation 列表（自动检测）
local available_workstations = detectWorkstations()

-- 加载配置
local function loadConfig()
    local config_str = reaper.GetExtState(ext_name, config_key)
    if config_str and config_str ~= "" then
        local success, config = pcall(function()
            return load("return " .. config_str)()
        end)
        if success and config then
            -- 更新可用列表的启用状态
            for i, ws in ipairs(available_workstations) do
                if config[ws.name] ~= nil then
                    ws.enabled = config[ws.name]
                end
            end
            return config
        end
    end
    return {}
end

-- 保存配置
local function saveConfig()
    local config = {}
    for _, ws in ipairs(available_workstations) do
        config[ws.name] = ws.enabled
    end
    
    -- 使用 JSON 风格的字符串保存配置
    local config_parts = {}
    for i, ws in ipairs(available_workstations) do
        table.insert(config_parts, string.format('["%s"] = %s', ws.name, tostring(ws.enabled)))
    end
    local config_str = "{" .. table.concat(config_parts, ", ") .. "}"
    reaper.SetExtState(ext_name, config_key, config_str, true)
end

-- 启动 Workstation
local function launchWorkstation(script_path)
    local resource_path = reaper.GetResourcePath()
    local sep = package.config:sub(1, 1)
    local script_path_full = resource_path .. sep .. script_path
    
    -- 检查文件是否存在
    local file = io.open(script_path_full, "r")
    if not file then
        return false
    end
    file:close()
    
    -- 使用 loadfile 和 pcall 执行脚本
    local success, err = pcall(function()
        local f = loadfile(script_path_full)
        if f then
            f()
        else
            error("Failed to load script")
        end
    end)
    
    return success
end

-- 检查 __startup.lua 是否存在
local function checkStartupScript()
    local resource_path = reaper.GetResourcePath()
    local sep = package.config:sub(1, 1)
    local startup_script = resource_path .. sep .. "Scripts" .. sep .. "__startup.lua"
    return io.open(startup_script, "r") ~= nil
end

-- 主函数
local function main()
    -- 重新检测 Workstation（可能新增了）
    available_workstations = detectWorkstations()
    
    -- 加载配置
    loadConfig()
    
    -- 配置模式：显示配置界面
    if not reaper.ImGui_CreateContext then
        -- 如果没有 ReaImGui，使用简单的消息框配置
        local msg = "Workstation Auto-Start Configuration\n\n"
        for i, ws in ipairs(available_workstations) do
            msg = msg .. string.format("%d. %s: %s\n", i, ws.name, ws.enabled and "Enabled" or "Disabled")
        end
        msg = msg .. "\nNote: Requires Scripts/__startup.lua to be present"
        reaper.ShowMessageBox(msg, "Workstation Auto-Start", 0)
    else
        -- 使用 ReaImGui 显示配置界面
        local ctx = reaper.ImGui_CreateContext('Workstation Auto-Start Config')
        local config_visible = true
        
        local function config_loop()
            reaper.ImGui_SetNextWindowSize(ctx, 400, 250, reaper.ImGui_Cond_FirstUseEver())
            
            local visible, open = reaper.ImGui_Begin(ctx, 'Workstation Auto-Start Config', true)
            if visible then
                reaper.ImGui_Text(ctx, "Select Workstations to auto-start:")
                reaper.ImGui_Separator(ctx)
                reaper.ImGui_Spacing(ctx)
                
                for _, ws in ipairs(available_workstations) do
                    local changed, checked = reaper.ImGui_Checkbox(ctx, ws.name, ws.enabled)
                    if changed then
                        ws.enabled = checked
                    end
                end
                
                reaper.ImGui_Separator(ctx)
                reaper.ImGui_Spacing(ctx)
                
                if reaper.ImGui_Button(ctx, "Save", 100, 25) then
                    saveConfig()
                    config_visible = false
                    reaper.ShowMessageBox("Configuration saved!\n\nWorkstations will auto-start when REAPER launches.", "Workstation Auto-Start", 0)
                end
                
                reaper.ImGui_SameLine(ctx)
                
                if reaper.ImGui_Button(ctx, "Test Launch", 100, 25) then
                    -- 测试启动所有启用的 Workstation
                    for _, ws in ipairs(available_workstations) do
                        if ws.enabled then
                            reaper.defer(function()
                                launchWorkstation(ws.script_path)
                            end)
                        end
                    end
                    config_visible = false
                end
                
                reaper.ImGui_SameLine(ctx)
                
                if reaper.ImGui_Button(ctx, "Cancel", 100, 25) then
                    loadConfig() -- 重新加载配置，取消更改
                    config_visible = false
                end
                
                reaper.ImGui_Spacing(ctx)
                reaper.ImGui_Separator(ctx)
                reaper.ImGui_Spacing(ctx)
                
                -- 检查 __startup.lua 状态
                local startup_exists = checkStartupScript()
                if startup_exists then
                    reaper.ImGui_Text(ctx, "✓ __startup.lua is active")
                    reaper.ImGui_Text(ctx, "Workstations will auto-start on REAPER launch")
                else
                    reaper.ImGui_Text(ctx, "⚠ __startup.lua not found")
                    reaper.ImGui_Text(ctx, "Auto-start will not work")
                    reaper.ImGui_Text(ctx, "Please ensure Scripts/__startup.lua exists")
                end
                
                reaper.ImGui_End(ctx)
            end
            
            if open and config_visible then
                reaper.defer(config_loop)
            end
        end
        
        config_loop()
    end
end

-- 运行主函数
main()
