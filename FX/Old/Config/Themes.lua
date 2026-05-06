--[[
  Theme System for FX Manager
  Uses same theme system as Item/Marker Workstation
]]

local Themes = {}

-- Default Theme - Modern Dark Studio
Themes.default = {
    name = "Modern Dark Studio",
    -- Button colors
    BTN_FX_ON      = 0x6C5CE7FF,  -- Modern Purple Base (#6C5CE7)
    BTN_FX_HOVER   = 0xA29BFEFF,  -- Modern Purple Hover (#A29BFE)
    BTN_FX_ACTIVE  = 0xFFFFFF80,  -- White/High Bright Purple Active
    BTN_FX_BORDER  = 0xD8BFD880,  -- Light Purple Border
    BTN_FX_OFF     = 0x555555AA,
    BTN_RELOAD     = 0x666666AA,
    BTN_VIEW       = 0x0984E3FF,  -- Tech Blue (#0984E3)
    BTN_PROCESSING = 0xD63031FF,  -- Alert Red (#D63031)
    BTN_CUSTOM     = 0x6C5CE7FF,
    BTN_DELETE     = 0xD63031FF,
    -- Text colors
    TEXT_NORMAL    = 0xDFE6E9FF,  -- Soft White (#DFE6E9)
    TEXT_DIM       = 0x888888FF,
    BG_HEADER      = 0x29292EFF,  -- Panel Background (#29292E)
    BG_WINDOW      = 0x1F1F23FF,  -- Window Background (#1F1F23)
    -- Style Vars (圆角设置 - 更硬朗)
    style_vars = {
        WINDOW_ROUNDING = 6,   -- 窗口圆角
        CHILD_ROUNDING  = 4,   -- Child窗口圆角（更硬朗）
        FRAME_ROUNDING  = 4,   -- 按钮/输入框圆角（硬朗）
        POPUP_ROUNDING  = 4,   -- 弹窗圆角
        ITEM_SPACING    = {8, 8},  -- 间距设置（增加间距）
        FRAME_PADDING   = {12, 8},  -- 按钮/输入框内部留白（增加）
        WINDOW_PADDING  = {12, 12}, -- 窗口内边距
        FRAME_BORDER_SIZE = 1.0,  -- 边框大小
    },
    -- ImGui window colors
    WINDOW_BG      = 0x1F1F23FF,  -- #1F1F23
    TITLE_BG       = 0x29292EFF,   -- #29292E
    TITLE_BG_ACTIVE = 0x29292EFF,
    FRAME_BG       = 0x29292EFF,  -- #29292E
    TEXT           = 0xDFE6E9FF,   -- #DFE6E9
}

-- Apply theme to ImGui context
function Themes.applyTheme(ctx, theme)
    if not theme or not ctx then
        return 0, 0  -- return style_var_count, color_count
    end
    
    local style_var_count = 0
    local color_count = 0
    
    -- Apply Style Vars if specified
    if theme.style_vars then
        if theme.style_vars.WINDOW_ROUNDING then
            reaper.ImGui_PushStyleVar(ctx, reaper.ImGui_StyleVar_WindowRounding(), theme.style_vars.WINDOW_ROUNDING)
            style_var_count = style_var_count + 1
        end
        if theme.style_vars.CHILD_ROUNDING then
            reaper.ImGui_PushStyleVar(ctx, reaper.ImGui_StyleVar_ChildRounding(), theme.style_vars.CHILD_ROUNDING)
            style_var_count = style_var_count + 1
        end
        if theme.style_vars.FRAME_ROUNDING then
            reaper.ImGui_PushStyleVar(ctx, reaper.ImGui_StyleVar_FrameRounding(), theme.style_vars.FRAME_ROUNDING)
            style_var_count = style_var_count + 1
        end
        if theme.style_vars.POPUP_ROUNDING then
            reaper.ImGui_PushStyleVar(ctx, reaper.ImGui_StyleVar_PopupRounding(), theme.style_vars.POPUP_ROUNDING)
            style_var_count = style_var_count + 1
        end
        if theme.style_vars.ITEM_SPACING then
            reaper.ImGui_PushStyleVar(ctx, reaper.ImGui_StyleVar_ItemSpacing(), theme.style_vars.ITEM_SPACING[1], theme.style_vars.ITEM_SPACING[2])
            style_var_count = style_var_count + 1
        end
        if theme.style_vars.FRAME_PADDING then
            reaper.ImGui_PushStyleVar(ctx, reaper.ImGui_StyleVar_FramePadding(), theme.style_vars.FRAME_PADDING[1], theme.style_vars.FRAME_PADDING[2])
            style_var_count = style_var_count + 1
        end
        if theme.style_vars.WINDOW_PADDING then
            reaper.ImGui_PushStyleVar(ctx, reaper.ImGui_StyleVar_WindowPadding(), theme.style_vars.WINDOW_PADDING[1], theme.style_vars.WINDOW_PADDING[2])
            style_var_count = style_var_count + 1
        end
        if theme.style_vars.FRAME_BORDER_SIZE then
            reaper.ImGui_PushStyleVar(ctx, reaper.ImGui_StyleVar_FrameBorderSize(), theme.style_vars.FRAME_BORDER_SIZE)
            style_var_count = style_var_count + 1
        end
    end
    
    -- Apply ImGui colors if specified
    if theme.WINDOW_BG then
        reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_WindowBg(), theme.WINDOW_BG)
        color_count = color_count + 1
    end
    if theme.TITLE_BG then
        reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_TitleBg(), theme.TITLE_BG)
        color_count = color_count + 1
    end
    if theme.TITLE_BG_ACTIVE then
        reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_TitleBgActive(), theme.TITLE_BG_ACTIVE)
        color_count = color_count + 1
    end
    if theme.FRAME_BG then
        reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_FrameBg(), theme.FRAME_BG)
        color_count = color_count + 1
    end
    if theme.TEXT then
        reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Text(), theme.TEXT)
        color_count = color_count + 1
    end
    
    return style_var_count, color_count
end

-- Pop theme styles and colors
function Themes.popTheme(ctx, style_var_count, color_count)
    if not ctx then
        return
    end
    
    if color_count and color_count > 0 then
        reaper.ImGui_PopStyleColor(ctx, color_count)
    end
    if style_var_count and style_var_count > 0 then
        reaper.ImGui_PopStyleVar(ctx, style_var_count)
    end
end

-- Get current theme
function Themes.getCurrentTheme()
    return Themes.default
end

return Themes

