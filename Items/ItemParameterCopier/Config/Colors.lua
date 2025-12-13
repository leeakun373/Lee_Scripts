--[[
  Color scheme for Item Parameter Copier
  Colors are in 0xRRGGBBAA format
  
  Note: This file maintains backward compatibility.
  For theme system, see Themes.lua
  Colors are dynamically loaded from current theme.
]]

-- Helper function to get colors from current theme
local function getColorsFromTheme()
    local script_path = debug.getinfo(1, 'S').source:match("@(.+[/\\])")
    local path_sep = package.config:sub(1,1) == "/" and "/" or "\\"
    local Themes = loadfile(script_path .. "Themes.lua")()
    local current_theme = Themes.getCurrentTheme()
    
    return {
        BTN_COPY      = current_theme.BTN_COPY or current_theme.BTN_CUSTOM,
        BTN_PASTE     = current_theme.BTN_PASTE or current_theme.BTN_CUSTOM,
        TEXT_NORMAL   = current_theme.TEXT_NORMAL,
        TEXT_DIM      = current_theme.TEXT_DIM,
        BG_HEADER     = current_theme.BG_HEADER,
    }
end

-- Return colors from current theme
return getColorsFromTheme()

