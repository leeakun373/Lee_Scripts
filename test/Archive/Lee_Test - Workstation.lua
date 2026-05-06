--[[
  REAPER Lua Script: Test Workstation
  Description: Test script launcher and manager
  - Dynamically loads test scripts from test directory
  - Provides unified GUI interface for running and testing scripts
  - Supports refresh to reload scripts
  
  Usage:
  1. Run this script to open GUI
  2. Click "Refresh" to reload all test scripts
  3. Click any script button to run it
]]

-- Check if ReaImGui is available
if not reaper.ImGui_CreateContext then
    reaper.ShowMessageBox("This script requires ReaImGui extension.\nPlease install 'ReaImGui' from Extensions > ReaPack > Browse packages", "Missing Dependency", 0)
    return
end

-- Get script directory
local script_path = debug.getinfo(1, 'S').source:match("@(.+[/\\])")
local test_dir = script_path

-- GUI variables
local ctx = reaper.ImGui_CreateContext('Test Workstation')
local gui = {
    visible = true,
    width = 500,
    height = 600
}

-- Status variable
local status_message = "Ready - Click Refresh to load scripts"

-- Test scripts storage
local test_scripts = {}

-- Extract script info from file
local function extractScriptInfo(file_path)
    local info = {
        name = "",
        description = "",
        version = "",
        author = ""
    }
    
    local file = io.open(file_path, "r")
    if not file then return info end
    
    for line in file:lines() do
        -- Extract @description
        local desc = line:match("@description%s+(.+)")
        if desc then
            info.description = desc
        end
        
        -- Extract @version
        local ver = line:match("@version%s+(.+)")
        if ver then
            info.version = ver
        end
        
        -- Extract @author
        local auth = line:match("@author%s+(.+)")
        if auth then
            info.author = auth
        end
        
        -- Extract name from first comment or description
        if not info.name or info.name == "" then
            local name = line:match("--%s*(.+)")
            if name and not name:match("@") then
                info.name = name
            end
        end
    end
    
    file:close()
    return info
end

-- Load test scripts
local function loadTestScripts()
    test_scripts = {}
    
    -- Enumerate files in test directory
    local i = 0
    while true do
        local file = reaper.EnumerateFiles(test_dir, i)
        if not file then break end
        
        -- Only load .lua files, exclude Archive and subdirectories
        if file:match("%.lua$") and not file:match("^Archive") and not file:match("Workstation") then
            local file_path = test_dir .. file
            local file_info = extractScriptInfo(file_path)
            
            -- Use filename as name if no description found
            if file_info.name == "" then
                -- Clean up filename: remove "Lee_Test - " prefix and .lua extension
                file_info.name = file:gsub("%.lua$", ""):gsub("^Lee_Test%s*-%s*", "")
                if file_info.name == "" then
                    file_info.name = file:gsub("%.lua$", "")
                end
            end
            
            table.insert(test_scripts, {
                filename = file,
                filepath = file_path,
                name = file_info.name,
                description = file_info.description,
                version = file_info.version,
                author = file_info.author
            })
        end
        
        i = i + 1
    end
    
    -- Sort by filename
    table.sort(test_scripts, function(a, b)
        return a.filename < b.filename
    end)
    
    status_message = string.format("Loaded %d test script(s)", #test_scripts)
end

-- Run a test script
local function runTestScript(script_info)
    local success, err = pcall(function()
        local f = loadfile(script_info.filepath)
        if f then
            f()
            return true
        else
            error("Failed to load script")
        end
    end)
    
    if success then
        status_message = string.format("✓ Ran: %s", script_info.name)
    else
        status_message = string.format("✗ Error running %s: %s", script_info.name, tostring(err))
    end
end

-- Initialize: Load scripts
loadTestScripts()

-- GUI main loop
local function main_loop()
    reaper.ImGui_SetNextWindowSize(ctx, gui.width, gui.height, reaper.ImGui_Cond_FirstUseEver())
    
    local visible, open = reaper.ImGui_Begin(ctx, 'Test Workstation', true)
    if visible then
        -- Title
        reaper.ImGui_Text(ctx, "Test Workstation")
        reaper.ImGui_Separator(ctx)
        
        -- Refresh button
        if reaper.ImGui_Button(ctx, "🔄 Refresh", 120, 30) then
            loadTestScripts()
        end
        
        reaper.ImGui_SameLine(ctx)
        reaper.ImGui_Text(ctx, string.format("(%d scripts)", #test_scripts))
        
        reaper.ImGui_Separator(ctx)
        reaper.ImGui_Spacing(ctx)
        
        -- Script list with scroll
        local flags = reaper.ImGui_WindowFlags_None()
        if reaper.ImGui_BeginChild(ctx, "ScriptList", 0, -80, true) then
            if #test_scripts == 0 then
                reaper.ImGui_Text(ctx, "No test scripts found.")
                reaper.ImGui_Text(ctx, "Add .lua files to test directory")
            else
                for i, script in ipairs(test_scripts) do
                    -- Script name button
                    local button_text = script.name
                    if script.version and script.version ~= "" then
                        button_text = button_text .. " (v" .. script.version .. ")"
                    end
                    
                    if reaper.ImGui_Button(ctx, button_text, -1, 35) then
                        runTestScript(script)
                    end
                    
                    -- Tooltip with description
                    if reaper.ImGui_IsItemHovered(ctx) then
                        local tooltip = script.filename
                        if script.description and script.description ~= "" then
                            tooltip = tooltip .. "\n" .. script.description
                        end
                        if script.author and script.author ~= "" then
                            tooltip = tooltip .. "\nAuthor: " .. script.author
                        end
                        reaper.ImGui_SetTooltip(ctx, tooltip)
                    end
                    
                    -- Show filename in smaller text
                    reaper.ImGui_SameLine(ctx, 10)
                    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Text(), 0x888888FF)
                    reaper.ImGui_Text(ctx, script.filename)
                    reaper.ImGui_PopStyleColor(ctx)
                    
                    reaper.ImGui_Spacing(ctx)
                end
            end
            reaper.ImGui_EndChild(ctx)
        end
        
        reaper.ImGui_Separator(ctx)
        
        -- Status info
        reaper.ImGui_Text(ctx, "Status:")
        reaper.ImGui_TextWrapped(ctx, status_message)
        
        reaper.ImGui_Separator(ctx)
        
        -- Close button
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

