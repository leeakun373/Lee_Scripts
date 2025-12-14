local r = reaper

-- Check if ReaImGui is available
if not r.APIExists('ImGui_GetVersion') then
    r.ShowMessageBox("Please install 'ReaImGui' via ReaPack.", "Error", 0)
    return
end

-- Get script directory
local script_path = debug.getinfo(1, 'S').source:match("@(.+[/\\])")
local path_sep = package.config:sub(1,1) == "/" and "/" or "\\"

-- Helper function to load module
local function loadModule(module_path)
    local f = loadfile(module_path)
    if f then
        return f()
    end
    return nil
end

-- Load modules
local Constants = loadModule(script_path .. "Config" .. path_sep .. "Constants.lua")
local Theme = loadModule(script_path .. "Config" .. path_sep .. "Theme.lua")
local Helpers = loadModule(script_path .. "Utils" .. path_sep .. "Helpers.lua")
local DataLoader = loadModule(script_path .. "Modules" .. path_sep .. "DataLoader.lua")
local UCSMatcher = loadModule(script_path .. "Modules" .. path_sep .. "UCSMatcher.lua")
local NameProcessor = loadModule(script_path .. "Modules" .. path_sep .. "NameProcessor.lua")
local ProjectActions = loadModule(script_path .. "Modules" .. path_sep .. "ProjectActions.lua")
local GUI = loadModule(script_path .. "Modules" .. path_sep .. "GUI.lua")

-- Check if all modules loaded successfully
if not Constants or not Theme or not Helpers or not DataLoader or not UCSMatcher or 
   not NameProcessor or not ProjectActions or not GUI then
    r.ShowMessageBox("Failed to load required modules. Please ensure all module files exist.", "Error", 0)
    return
end

-- Initialize ImGui context
local ctx = r.ImGui_CreateContext('MarkerTranslatorPro')

-- Get script path using Helpers
local script_path_func = function()
    return script_path
end

-- Initialize UCS database
local ucs_db = Constants.createUCSDB()

-- Initialize application state
local app_state = Constants.createAppState()

-- Load UCS data
-- Use script_path from main file, not Helpers.GetScriptPath() (which would point to Helpers.lua)
DataLoader.LoadUCSData(ucs_db, app_state, script_path, Constants.CSV_DB_FILE, Constants.CSV_ALIAS_FILE, Helpers)

-- Reload project data with smart initialization
ProjectActions.ReloadProjectData(app_state, ucs_db, NameProcessor, Constants.UCS_OPTIONAL_FIELDS, 
    UCSMatcher, Constants.WEIGHTS, Constants.MATCH_THRESHOLD, Constants.DOWNGRADE_WORDS, Helpers, Constants.SAFE_DOMINANT_KEYWORDS)

-- Prepare module dependencies for GUI
local modules = {
    Constants = Constants,
    Theme = Theme,
    Helpers = Helpers,
    DataLoader = DataLoader,
    UCSMatcher = UCSMatcher,
    NameProcessor = NameProcessor,
    ProjectActions = ProjectActions,
    ucs_db = ucs_db,
    app_state = app_state,
    script_path = script_path
}

-- Start main loop
local function main_loop()
    local should_continue = GUI.Loop(ctx, modules)
    if should_continue then
        r.defer(main_loop)
    end
end

-- Launch GUI
main_loop()

