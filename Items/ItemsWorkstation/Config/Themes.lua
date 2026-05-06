--[[
  Theme System for Item Workstation
  Uses same theme system as Marker Workstation
]]

local Themes = {}

-- Default Theme (current color scheme)
Themes.default = {
    name = "Default",
    -- Button colors (Items use BTN_ITEM_ON, same as Region color)
    BTN_ITEM_ON    = 0x0F766EFF,  -- Item color (Teal-700, same as Region)
    BTN_ITEM_OFF   = 0x555555AA,
    BTN_RELOAD     = 0x666666AA,
    BTN_CUSTOM     = 0x42A5F5AA,
    BTN_DELETE     = 0xFF5252AA,
    -- Text colors
    TEXT_NORMAL    = 0xEEEEEEFF,
    TEXT_DIM       = 0x888888FF,
    BG_HEADER      = 0x2A2A2AFF,
    -- ImGui window colors
    WINDOW_BG      = nil,  -- nil = use ImGui default
    TITLE_BG       = nil,
    TITLE_BG_ACTIVE = nil,
    FRAME_BG       = nil,
    TEXT           = nil,
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
    if theme.POPUP_BG then
        reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_PopupBg(), theme.POPUP_BG)
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
    if theme.BORDER_SHADOW then
        reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_BorderShadow(), theme.BORDER_SHADOW)
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
    if theme.TITLE_BG_COLLAPSED then
        reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_TitleBgCollapsed(), theme.TITLE_BG_COLLAPSED)
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
    if theme.HEADER then
        reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Header(), theme.HEADER)
        color_count = color_count + 1
    end
    if theme.HEADER_HOVERED then
        reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_HeaderHovered(), theme.HEADER_HOVERED)
        color_count = color_count + 1
    end
    if theme.HEADER_ACTIVE then
        reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_HeaderActive(), theme.HEADER_ACTIVE)
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
    if theme.SLIDER_GRAB then
        reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_SliderGrab(), theme.SLIDER_GRAB)
        color_count = color_count + 1
    end
    if theme.SLIDER_GRAB_ACTIVE then
        reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_SliderGrabActive(), theme.SLIDER_GRAB_ACTIVE)
        color_count = color_count + 1
    end
    -- Tab 选项卡颜色
    if theme.TAB then
        reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Tab(), theme.TAB)
        color_count = color_count + 1
    end
    if theme.TAB_HOVERED then
        reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_TabHovered(), theme.TAB_HOVERED)
        color_count = color_count + 1
    end
    if theme.TAB_ACTIVE then
        if reaper.ImGui_Col_TabSelected then
            reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_TabSelected(), theme.TAB_ACTIVE)
            color_count = color_count + 1
        elseif reaper.ImGui_Col_TabActive then
            reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_TabActive(), theme.TAB_ACTIVE)
            color_count = color_count + 1
        end
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

-- Current theme name (fixed to modern)
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

-- Get current theme name
function Themes.getCurrentThemeName()
    return current_theme_name
end

-- Modern Studio Theme (Muted - 低饱和度，与Marker Workstation一致)
Themes.modern = {
    name = "Modern",
    -- Button colors (Items use BTN_ITEM_ON, same as Region color)
    BTN_ITEM_ON    = 0x0F766EFF,  -- Item 激活时使用深青色 (Teal-700, same as Region)
    BTN_ITEM_OFF   = 0x27272AFF,  -- 非激活使用深灰
    BTN_RELOAD     = 0x27272AFF,  -- 普通按钮，使用深灰
    BTN_CUSTOM     = 0x27272AFF,  -- 通用按钮，使用深灰（不抢戏）
    BTN_DELETE     = 0x27272AFF,  -- 删除按钮，使用深灰
    -- Text colors
    TEXT_NORMAL    = 0xE4E4E7FF,  -- 锌白
    TEXT_DIM       = 0xA1A1AAFF,  -- 灰字
    BG_HEADER      = 0x18181BFF,
    -- Style Vars (圆角和间距 - Modern Studio 风格)
    style_vars = {
        WINDOW_ROUNDING = 6,   -- 窗口圆角
        FRAME_ROUNDING  = 4,   -- 输入框/按钮圆角
        POPUP_ROUNDING  = 4,   -- 弹窗圆角
        GRAB_ROUNDING   = 4,   -- 滚动条滑块圆角
        ITEM_SPACING    = {8, 8},  -- 间距设置
        FRAME_PADDING   = {10, 6}, -- 按钮/输入框内部留白
    },
    -- ImGui Colors (低饱和度，耐看 - Modern Studio Muted)
    WINDOW_BG      = 0x18181BFF,  -- Zinc-900 (更中性的深灰)
    POPUP_BG       = 0x1D1D20F0,  -- 弹窗稍亮
    CHILD_BG       = 0x18181B00,  -- Child背景透明
    BORDER         = 0x27272AFF,  -- 淡淡的边框
    TITLE_BG       = 0x18181BFF,  -- 标题栏融入背景
    TITLE_BG_ACTIVE = 0x18181BFF, -- 激活时也不变色
    FRAME_BG       = 0x09090BFF,  -- 极黑输入框 (形成凹陷感)
    FRAME_BG_HOVERED = 0x18181BFF,  -- 悬停稍亮
    FRAME_BG_ACTIVE = 0x202020FF,  -- 激活时稍亮
    -- 默认按钮 (改为深灰，不再用高饱和度色)
    BUTTON         = 0x27272AFF,  -- 默认深灰
    BUTTON_HOVERED = 0x3F3F46FF,  -- 悬停变亮
    BUTTON_ACTIVE  = 0x18181BFF,  -- 点击变深
    -- Tab 选项卡 (激活的 Tab 也是灰色，不刺眼)
    TAB            = 0x18181BFF,  -- Tab 默认透明/背景色
    TAB_HOVERED    = 0x52525BFF,  -- Tab 悬停
    TAB_ACTIVE     = 0x3F3F46FF,  -- Tab 激活（灰色，不刺眼）
    TAB_UNFOCUSED  = 0x18181BFF,  -- Tab 失去焦点
    TAB_UNFOCUSED_ACTIVE = 0x27272AFF,  -- Tab 失去焦点但激活
    -- Header (列表选中项)
    HEADER         = 0x3F3F46FF,  -- 选中态 (深灰)
    HEADER_HOVERED = 0x52525BFF,  -- 悬停态 (稍亮)
    HEADER_ACTIVE  = 0x27272AFF,  -- 激活态 (更深)
    TEXT           = 0xE4E4E7FF,   -- 锌白
    TEXT_DISABLED  = 0xA1A1AAFF,   -- 灰字
}

-- Studio Theme (NVK Deep Space - 极黑背景、锐利边框、高亮输入框)
Themes.studio = {
    name = "Studio",
    -- Button colors (Items use BTN_ITEM_ON, same as Region color)
    BTN_ITEM_ON    = 0x0F766EFF,  -- Item 激活时使用深青色 (Teal-700, same as Region)
    BTN_ITEM_OFF   = 0x252525FF,  -- 非激活使用深灰
    BTN_RELOAD     = 0x252525FF,  -- 普通按钮，使用深灰
    BTN_CUSTOM     = 0x00695CFF,  -- 执行按钮，使用 NVK 深青色 (BtnNVK_Green)
    BTN_DELETE     = 0x212121FF,  -- 删除按钮，使用 NVK 深色 (BtnNVK_Dark)
    -- Text colors
    TEXT_NORMAL    = 0xE0E0E0FF,  -- 亮灰白，高对比度
    TEXT_DIM       = 0x666666FF,  -- 禁用文本
    BG_HEADER      = 0x111111FF,
    -- Style Vars (锐利、精密 - NVK 风格)
    style_vars = {
        WINDOW_ROUNDING = 0,   -- NVK 风格通常没有圆角
        CHILD_ROUNDING  = 0,   -- Child 无圆角
        FRAME_ROUNDING  = 2,   -- 按钮/输入框微圆角
        POPUP_ROUNDING  = 2,   -- 弹窗微圆角
        ITEM_SPACING    = {8, 6},  -- 间距设置
        FRAME_PADDING   = {8, 6},  -- 按钮/输入框内部留白
        WINDOW_PADDING  = {12, 12}, -- 窗口内边距稍大，显得大气
    },
    -- ImGui Colors (Deep Space - 极致的深色，几乎纯黑)
    WINDOW_BG      = 0x111111FF,  -- 极致的深色，几乎纯黑
    CHILD_BG       = 0x11111100,  -- Child背景透明
    POPUP_BG       = 0x1A1A1AF0,  -- 弹窗稍亮
    BORDER         = 0x333333FF,  -- 锐利的深灰，分割线
    BORDER_SHADOW  = 0x00000000,  -- 无边框阴影
    FRAME_BG       = 0x080808FF,  -- 极黑输入框，形成凹陷感（关键点）
    FRAME_BG_HOVERED = 0x151515FF,
    FRAME_BG_ACTIVE = 0x191919FF,
    TITLE_BG       = 0x111111FF,  -- 标题栏融入背景
    TITLE_BG_ACTIVE = 0x111111FF,
    TITLE_BG_COLLAPSED = 0x111111FF,
    -- 普通按钮：默认状态极简
    BUTTON         = 0x252525FF,  -- 默认很暗
    BUTTON_HOVERED = 0x333333FF,  -- 悬停变亮
    BUTTON_ACTIVE  = 0x1A1A1AFF,  -- 点击
    -- Tab 选项卡：模仿 NVK 的平铺风格
    TAB            = 0x11111100,  -- 默认透明
    TAB_HOVERED    = 0x222222FF,  -- 悬停微亮
    TAB_ACTIVE     = 0x26A69A33,  -- 选中时，带一点点绿色的微光背景
    TAB_UNFOCUSED  = 0x11111100,  -- 失去焦点时透明
    TAB_UNFOCUSED_ACTIVE = 0x222222FF,  -- 失去焦点但激活
    -- 滚动条：极细、极简
    SCROLLBAR_BG   = 0x00000000,  -- 透明背景
    SCROLLBAR_GRAB = 0x333333FF,  -- 深灰
    SCROLLBAR_GRAB_HOVERED = 0x444444FF,  -- 悬停稍亮
    SCROLLBAR_GRAB_ACTIVE = 0x26A69AFF,  -- 拖动时变绿
    -- 其他组件
    CHECKMARK      = 0x26A69AFF,  -- NVK 绿勾
    SLIDER_GRAB    = 0x26A69AFF,  -- NVK 绿色
    SLIDER_GRAB_ACTIVE = 0x4DB6ACFF,  -- 激活时稍亮
    -- 列表选中项 (Header)：NVK 绿色系
    HEADER         = 0x26A69A44,  -- 列表选中色（半透明）
    HEADER_HOVERED = 0x26A69A66,  -- 悬停更明显
    HEADER_ACTIVE  = 0x26A69A88,  -- 激活时更明显
    TEXT           = 0xE0E0E0FF,   -- 亮灰白，高对比度
    TEXT_DISABLED  = 0x666666FF,
}

-- Get all available themes
function Themes.getAllThemes()
    return {
        default = Themes.default,
        modern = Themes.modern,
        studio = Themes.studio,
    }
end

-- Get theme names list (for dropdown)
function Themes.getThemeNames()
    local names = {}
    local all_themes = Themes.getAllThemes()
    for name, theme in pairs(all_themes) do
        table.insert(names, name)
    end
    table.sort(names)
    return names
end

return Themes

