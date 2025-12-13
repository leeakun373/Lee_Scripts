--[[
  Constants for Item Parameter Copier
  All constant values used across the application
]]

return {
    -- Script identification
    SCRIPT_ID = "ItemParameterCopier_Running",
    CLOSE_REQUEST = "ItemParameterCopier_CloseRequest",
    EXT_STATE_SECTION = "ItemParameterCopier",
    
    -- Tooltip settings
    TOOLTIP_DELAY = 0.5,  -- Show tooltip after 0.5 seconds
    
    -- Default GUI settings
    DEFAULT_WIDTH = 380,
    DEFAULT_HEIGHT = 600,
    
    -- Parameter definitions
    PARAM_GROUPS = {
        TAKE = "Take Parameters",
        ITEM = "Item Parameters",
        ENVELOPES = "Take Envelopes"
    },
    
    -- Take parameters
    TAKE_PARAMS = {
        {key = "D_VOL", name = "Volume", desc = "音量"},
        {key = "D_PAN", name = "Pan", desc = "声像"},
        {key = "D_PLAYRATE", name = "Playrate", desc = "播放速率"},
        {key = "D_PITCH", name = "Pitch", desc = "音高"},
        {key = "I_CHANMODE", name = "Channels", desc = "通道模式"},
        {key = "D_STARTOFFS", name = "Start Offset", desc = "起始偏移"},
        {key = "D_PANLAW", name = "Pan Law", desc = "声像法则"},
    },
    
    -- Item parameters
    ITEM_PARAMS = {
        {key = "B_MUTE", name = "Mute", desc = "静音"},
        {key = "C_LOCK", name = "Lock", desc = "锁定"},
        {key = "B_LOOPSRC", name = "Loop Source", desc = "循环源"},
        {key = "D_FADEINLEN", name = "Fade In Length", desc = "淡入长度"},
        {key = "D_FADEOUTLEN", name = "Fade Out Length", desc = "淡出长度"},
        {key = "C_FADEINSHAPE", name = "Fade In Shape", desc = "淡入形状"},
        {key = "C_FADEOUTSHAPE", name = "Fade Out Shape", desc = "淡出形状"},
        {key = "D_FADEINDIR", name = "Fade In Direction", desc = "淡入方向"},
        {key = "D_FADEOUTDIR", name = "Fade Out Direction", desc = "淡出方向"},
        {key = "D_SNAPOFFSET", name = "Snap Offset", desc = "对齐偏移"},
    },
    
    -- Take envelope names
    ENVELOPES = {
        {name = "Volume", desc = "音量包络"},
        {name = "Pan", desc = "声像包络"},
        {name = "Mute", desc = "静音包络"},
        {name = "Pitch", desc = "音高包络"},
    },
}

