--[[
  Constants for FX Manager
  All constant values used across the application
]]

return {
    -- Script identification
    SCRIPT_ID = "FXManager_Running",
    CLOSE_REQUEST = "FXManager_CloseRequest",
    EXT_STATE_SECTION = "FXManager",
    
    -- Tooltip settings
    TOOLTIP_DELAY = 0.5,  -- Show tooltip after 0.5 seconds
    
    -- Default GUI settings
    DEFAULT_WIDTH = 450,
    DEFAULT_HEIGHT = 300,
    
    -- Button layout
    DEFAULT_BUTTON_WIDTH = 200,
    DEFAULT_BUTTON_HEIGHT = 45,
    DEFAULT_BUTTONS_PER_ROW = 2,
    
    -- FX Window arrangement
    FX_WINDOW_SPACING = 20,  -- Spacing between FX windows in pixels
    FX_WINDOW_GRID_COLS = 3,  -- Default grid columns
    FX_WINDOW_MIN_WIDTH = 400,  -- Minimum FX window width (estimate)
    FX_WINDOW_MIN_HEIGHT = 500,  -- Minimum FX window height (estimate)
}

