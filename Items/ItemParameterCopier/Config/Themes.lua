--[[
  Theme System for Item Parameter Copier
  Reference nvk PROPAGATE style - clean and modern
]]

local Themes = {}

-- Default Theme (current color scheme)
Themes.default = {
    name = "Default",
    -- Button colors
    BTN_COPY      = 0x42A5F5AA,
    BTN_PASTE     = 0x66BB6AAA,
    BTN_RELOAD    = 0x666666AA,
    BTN_CUSTOM    = 0x42A5F5AA,
    BTN_DELETE    = 0xFF5252AA,
    -- Text colors
    TEXT_NORMAL   = 0xEEEEEEFF,
    TEXT_DIM      = 0x888888FF,
    BG_HEADER     = 0x2A2A2AFF,
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
        if theme.style_vars.GRAB_ROUNDING then
            reaper.ImGui_PushStyleVar(ctx, reaper.ImGui_StyleVar_GrabRounding(), theme.style_vars.GRAB_ROUNDING)
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
    end
    
    -- Apply ImGui colors if specified
    if theme.WINDOW_BG then
        reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_WindowBg(), theme.WINDOW_BG)
        color_count = color_count + 1
    end
    if theme.CHILD_BG then
        reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ChildBg(), theme.CHILD_BG)
        color_count = color_count + 1
    end
    if theme.BORDER then
        reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Border(), theme.BORDER)
        color_count = color_count + 1
    end
    if theme.FRAME_BG then
        reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_FrameBg(), theme.FRAME_BG)
        color_count = color_count + 1
    end
    if theme.FRAME_BG_HOVERED then
        reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_FrameBgHovered(), theme.FRAME_BG_HOVERED)
        color_count = color_count + 1
    end
    if theme.FRAME_BG_ACTIVE then
        reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_FrameBgActive(), theme.FRAME_BG_ACTIVE)
        color_count = color_count + 1
    end
    if theme.BUTTON then
        reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Button(), theme.BUTTON)
        color_count = color_count + 1
    end
    if theme.BUTTON_HOVERED then
        reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ButtonHovered(), theme.BUTTON_HOVERED)
        color_count = color_count + 1
    end
    if theme.BUTTON_ACTIVE then
        reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ButtonActive(), theme.BUTTON_ACTIVE)
        color_count = color_count + 1
    end
    if theme.TEXT then
        reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Text(), theme.TEXT)
        color_count = color_count + 1
    end
    if theme.TEXT_DISABLED then
        reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_TextDisabled(), theme.TEXT_DISABLED)
        color_count = color_count + 1
    end
    if theme.CHECKMARK then
        reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_CheckMark(), theme.CHECKMARK)
        color_count = color_count + 1
    end
    
    return style_var_count, color_count
end

-- Pop theme styles and colors (call after window rendering)
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

-- Current theme name (default to modern)
local current_theme_name = "modern"

-- Set current theme
function Themes.setCurrentTheme(theme_name)
    if Themes[theme_name] then
        current_theme_name = theme_name
        return true
    end
    return false
end

-- Get current theme
function Themes.getCurrentTheme()
    return Themes[current_theme_name] or Themes.default
end

-- Modern Theme (参考 nvk PROPAGATE 风格 - 简洁现代)
Themes.modern = {
    name = "Modern",
    -- Button colors
    BTN_COPY      = 0x26A69AFF,  -- NVK 绿色系
    BTN_PASTE     = 0x4DB6ACFF,  -- 稍亮的绿色
    BTN_RELOAD    = 0x27272AFF,
    BTN_CUSTOM    = 0x27272AFF,
    BTN_DELETE    = 0x27272AFF,
    -- Text colors
    TEXT_NORMAL   = 0xE4E4E7FF,  -- 锌白
    TEXT_DIM      = 0xA1A1AAFF,  -- 灰字
    BG_HEADER     = 0x18181BFF,
    -- Style Vars (圆角和间距 - Modern 风格)
    style_vars = {
        WINDOW_ROUNDING = 6,   -- 窗口圆角
        FRAME_ROUNDING  = 4,   -- 输入框/按钮圆角
        POPUP_ROUNDING  = 4,   -- 弹窗圆角
        GRAB_ROUNDING   = 4,   -- 滚动条滑块圆角
        ITEM_SPACING    = {8, 8},  -- 间距设置
        FRAME_PADDING   = {10, 6}, -- 按钮/输入框内部留白
        WINDOW_PADDING  = {12, 12}, -- 窗口内边距
    },
    -- ImGui Colors (低饱和度，耐看 - Modern)
    WINDOW_BG      = 0x18181BFF,  -- Zinc-900
    CHILD_BG       = 0x18181B00,  -- Child背景透明
    BORDER         = 0x27272AFF,  -- 淡淡的边框
    FRAME_BG       = 0x09090BFF,  -- 极黑输入框
    FRAME_BG_HOVERED = 0x18181BFF,
    FRAME_BG_ACTIVE = 0x202020FF,
    BUTTON         = 0x27272AFF,
    BUTTON_HOVERED = 0x3F3F46FF,
    BUTTON_ACTIVE  = 0x18181BFF,
    TEXT           = 0xE4E4E7FF,
    TEXT_DISABLED  = 0xA1A1AAFF,
    CHECKMARK      = 0x26A69AFF,  -- NVK 绿勾
}

return Themes

