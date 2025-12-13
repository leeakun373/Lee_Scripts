--[[
  Theme and UI styling for UCS Rename Tools
]]

local Theme = {}
local r = reaper

-- Modern Slate Theme (深岩灰风格)
function Theme.PushModernSlateTheme(ctx)
    -- 1. 样式变量：增加呼吸感和现代圆角
    r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_WindowRounding(),    6)  -- 窗口圆角
    r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_FrameRounding(),     4)  -- 输入框/按钮圆角 (4px 是现代 UI 标准)
    r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_PopupRounding(),     4)
    r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_GrabRounding(),      4)
    
    -- 间距设置：比默认稍微宽松一点，让中文不拥挤
    r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_ItemSpacing(),       8, 6)
    r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_FramePadding(),      8, 5) 
    r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_CellPadding(),       6, 4) -- 表格内部留白
    r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_WindowPadding(),     10, 10)

    -- 2. 颜色设置：Modern Slate (深岩灰风格)
    -- 核心逻辑：背景(深灰) -> 按钮(中灰) -> 输入框(黑灰) -> 文字(亮白)
    
    local bg_base      = 0x202020FF -- 整体背景 (深灰，不刺眼)
    local bg_popup     = 0x282828F0 -- 弹窗稍亮
    local bg_input     = 0x151515FF -- 输入框 (比背景黑，产生凹陷感)
    local border_col   = 0x383838FF -- 边框 (很淡)
    
    local btn_norm     = 0x353535FF -- 默认按钮 (中性灰)
    local btn_hover    = 0x454545FF -- 悬停
    local btn_active   = 0x252525FF -- 点击
    
    local accent_col   = 0x42A5F5FF -- 强调色：安静的蓝色 (用于选中、滑块)
    local accent_hover = 0x64B5F6FF

    -- [Window & Border]
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_WindowBg(),      bg_base)
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ChildBg(),       bg_base)
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_PopupBg(),       bg_popup)
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Border(),        border_col)
    
    -- [Header & Selection] (列表选中项)
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Header(),        0x42A5F533) -- 淡淡的蓝色背景
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_HeaderHovered(), 0x42A5F555)
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_HeaderActive(),  0x42A5F577)
    
    -- [Inputs / Frame] (关键：深色凹陷)
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_FrameBg(),       bg_input)
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_FrameBgHovered(),0x2A2A2AFF)
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_FrameBgActive(), 0x303030FF)
    
    -- [Button] (默认全部灰色，去除彩虹色)
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Button(),        btn_norm)
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonHovered(), btn_hover)
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonActive(),  btn_active)
    
    -- [Text]
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Text(),          0xE0E0E0FF) -- 稍微柔和的白
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_TextDisabled(),  0x808080FF)
    
    -- [Misc]
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_CheckMark(),     accent_col) -- 勾选框颜色
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_SliderGrab(),    btn_hover)  -- 滑块
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_SliderGrabActive(), accent_col)

    return 8, 18 -- 8 vars, 18 colors
end

-- 按钮辅助函数
-- 1. 普通功能按钮 (灰色，低调)
function Theme.BtnNormal(ctx, label)
    return r.ImGui_Button(ctx, label)
end

-- 2. 状态开关按钮 (激活时变蓝，否则灰)
function Theme.BtnToggle(ctx, label, is_active)
    if is_active then
        -- 激活时：使用舒适的蓝色
        r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Button(),        0x1976D2FF) 
        r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonHovered(), 0x2196F3FF)
        r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonActive(),  0x1565C0FF)
    end
    
    local clicked = r.ImGui_Button(ctx, label)
    
    if is_active then r.ImGui_PopStyleColor(ctx, 3) end
    return clicked
end

-- 3. 强调/执行按钮 (绿色，只用于 Apply)
function Theme.BtnPrimary(ctx, label, w, h)
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Button(),        0x2E7D32FF) -- 沉稳的绿色
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonHovered(), 0x388E3CFF)
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonActive(),  0x1B5E20FF)
    local clicked = r.ImGui_Button(ctx, label, w, h)
    r.ImGui_PopStyleColor(ctx, 3)
    return clicked
end

-- 4. 小按钮 (用于表格中的Fill/Clear按钮)
function Theme.BtnSmall(ctx, label)
    return r.ImGui_SmallButton(ctx, label)
end

-- 5. Alias按钮 (紫色，用于Alias功能)
function Theme.BtnAlias(ctx, label)
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Button(),        0x7B1FA2FF) -- 深紫色
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonHovered(), 0x9C27B0FF) -- 亮紫色
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonActive(),  0x6A1B9AFF) -- 点击后稍暗
    local clicked = r.ImGui_Button(ctx, label)
    r.ImGui_PopStyleColor(ctx, 3)
    return clicked
end

return Theme






